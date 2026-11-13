#!/usr/bin/env python3
"""gen_bt_data.py — the battle table's server-side data, in both directions. Standard library only, Python 3.8+.

    python3 godot/tools/gen_bt_data.py [--worker PATH] [--strict]
        reads the Cloudflare Worker source (default ../candlelight-server/worker.js next to this repository), cuts
        `const BT_RULES = N;`, `const BT2 = {…};` (the server's copy of every datasheet, keyed by unit key, weapon
        names in English), `const BT_ARMY_EN = {…};`, BT_THEMES, BT_TERRAINS, BT_LIST_LEN, BT_MAX_ACTS and
        BT_MAX_PLAYERS out of it (docs/CODEMAP.md "Server touch points") and writes godot/data/bt2_snapshot.json.
        BT2 is compared with data/types.json; differences are warnings (errors with --strict).
    python3 godot/tools/gen_bt_data.py --snapshot
        derives the payload the new app will need from the server — datasheets with English names, English army
        names, ability text, themes, terrains, phases, stratagems — from godot/data/*.json into godot/data/bt_data.json
        (English army names come from bt2_snapshot.json when it exists, else from i18n_en.json).
    python3 godot/tools/gen_bt_data.py --self-test
        runs the extraction over tests/data_fixtures/fake_worker.js and compares with fake_worker.expected.json.

The Worker's object literals are JavaScript, not JSON (bare keys, single quotes, trailing commas, comments), so a small
literal parser lives below. Anchors are matched at the start of a line: the Worker also embeds the whole web pages as
one-line string constants, and a match inside those must never win.
"""
import argparse
import hashlib
import json
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
GODOT = os.path.dirname(HERE)
REPO = os.path.dirname(GODOT)
DATA = os.path.join(GODOT, "data")
DEFAULT_WORKER = os.path.join(os.path.dirname(REPO), "candlelight-server", "worker.js")
FIXTURES = os.path.join(GODOT, "tests", "data_fixtures")
SNAPSHOT_FIELDS = ("bt_rules", "bt_list_len", "bt_max_acts", "bt_max_players", "bt_army_en", "bt_themes", "bt_terrains", "bt2")


class JsError(ValueError):
    pass


# ----------------------------------------------------------------------------------------------- JS object literal
class JsLiteral:
    """Parses one JavaScript value literal (object, array, string, number, true/false/null) into Python."""
    NUM = re.compile(r"-?(?:\d+\.\d*|\.\d+|\d+)(?:[eE][+-]?\d+)?")
    IDENT = re.compile(r"[A-Za-z_$][A-Za-z0-9_$]*")
    KEY = re.compile(r"[A-Za-z_$][A-Za-z0-9_$]*|-?\d+(?:\.\d+)?")
    ESC = {"n": "\n", "t": "\t", "r": "\r", "b": "\b", "f": "\f", "v": "\v", "0": "\0"}

    def __init__(self, text, pos=0):
        self.s = text
        self.i = pos

    def fail(self, what):
        line = self.s.count("\n", 0, self.i) + 1
        raise JsError("%s at line %d: %r" % (what, line, self.s[self.i:self.i + 30]))

    def ws(self):
        s, n = self.s, len(self.s)
        while self.i < n:
            c = s[self.i]
            if c in " \t\r\n":
                self.i += 1
            elif s.startswith("//", self.i):
                j = s.find("\n", self.i)
                self.i = n if j < 0 else j
            elif s.startswith("/*", self.i):
                j = s.find("*/", self.i)
                if j < 0:
                    self.fail("unterminated comment")
                self.i = j + 2
            else:
                break

    def value(self):
        self.ws()
        if self.i >= len(self.s):
            self.fail("unexpected end")
        c = self.s[self.i]
        if c == "{":
            return self.obj()
        if c == "[":
            return self.arr()
        if c in "\"'`":
            return self.string()
        m = self.NUM.match(self.s, self.i)
        if m:
            self.i = m.end()
            txt = m.group(0)
            return int(txt) if re.fullmatch(r"-?\d+", txt) else float(txt)
        m = self.IDENT.match(self.s, self.i)
        if m:
            w = m.group(0)
            self.i = m.end()
            if w == "true":
                return True
            if w == "false":
                return False
            if w in ("null", "undefined"):
                return None
            self.fail("unsupported expression %r (only literals are cut out of the Worker)" % w)
        self.fail("unexpected character")

    def obj(self):
        self.i += 1
        out = {}
        while True:
            self.ws()
            if self.i >= len(self.s):
                self.fail("unterminated object")
            if self.s[self.i] == "}":
                self.i += 1
                return out
            if self.s[self.i] in "\"'":
                key = self.string()
            else:
                m = self.KEY.match(self.s, self.i)
                if not m:
                    self.fail("bad object key")
                key = m.group(0)
                self.i = m.end()
            self.ws()
            if self.s[self.i:self.i + 1] != ":":
                self.fail("expected ':'")
            self.i += 1
            out[key] = self.value()
            self.ws()
            if self.s[self.i:self.i + 1] == ",":
                self.i += 1
            elif self.s[self.i:self.i + 1] != "}":
                self.fail("expected ',' or '}'")

    def arr(self):
        self.i += 1
        out = []
        while True:
            self.ws()
            if self.i >= len(self.s):
                self.fail("unterminated array")
            if self.s[self.i] == "]":
                self.i += 1
                return out
            out.append(self.value())
            self.ws()
            if self.s[self.i:self.i + 1] == ",":
                self.i += 1
            elif self.s[self.i:self.i + 1] != "]":
                self.fail("expected ',' or ']'")

    def string(self):
        q = self.s[self.i]
        self.i += 1
        buf = []
        while True:
            if self.i >= len(self.s):
                self.fail("unterminated string")
            c = self.s[self.i]
            if c == q:
                self.i += 1
                return "".join(buf)
            if c == "\\":
                n = self.s[self.i + 1:self.i + 2]
                if n == "u":
                    buf.append(chr(int(self.s[self.i + 2:self.i + 6], 16)))
                    self.i += 6
                elif n == "x":
                    buf.append(chr(int(self.s[self.i + 2:self.i + 4], 16)))
                    self.i += 4
                else:
                    buf.append(self.ESC.get(n, n))
                    self.i += 2
                continue
            if q == "`" and c == "$" and self.s[self.i + 1:self.i + 2] == "{":
                self.fail("template expression in a literal")
            if c == "\n" and q != "`":
                self.fail("newline in string")
            buf.append(c)
            self.i += 1


DECL = re.compile(r"^[ \t]*(?:const|let|var)\s", re.M)


def mask_strings(line):
    """The line with every quoted string's inside replaced by spaces (same length), so anchors inside the embedded
    one-line pages (`const APP_HTML = "…"`) can never match."""
    out, i, n = [], 0, len(line)
    while i < n:
        c = line[i]
        out.append(c)
        i += 1
        if c in "\"'`":
            while i < n and line[i] != c:
                if line[i] == "\\" and i + 1 < n:
                    out.append("  ")
                    i += 2
                else:
                    out.append(" ")
                    i += 1
            if i < n:
                out.append(c)
                i += 1
    return "".join(out)


def find_initializer(text, name):
    """Offset just after `NAME =` on the first line that declares constants and carries it outside a string."""
    rx = re.compile(r"\b%s\s*=\s*" % re.escape(name))
    for m in DECL.finditer(text):
        end = text.find("\n", m.start())
        end = len(text) if end < 0 else end
        line = text[m.start():end]
        if name not in line:
            continue
        hit = rx.search(mask_strings(line))
        if hit:
            return m.start() + hit.end()
    return None


def extract(text):
    """The snapshot fields from the Worker source. Raises JsError when a required table is missing or unparsable."""
    out = {}
    for name, key, required in (("BT_RULES", "bt_rules", True), ("BT2", "bt2", True), ("BT_ARMY_EN", "bt_army_en", True),
                                ("BT_THEMES", "bt_themes", False), ("BT_TERRAINS", "bt_terrains", False),
                                ("BT_LIST_LEN", "bt_list_len", False), ("BT_MAX_ACTS", "bt_max_acts", False),
                                ("BT_MAX_PLAYERS", "bt_max_players", False)):
        pos = find_initializer(text, name)
        if pos is None:
            if required:
                raise JsError("anchor `const %s = ` not found (see docs/CODEMAP.md, server touch points)" % name)
            continue
        out[key] = JsLiteral(text, pos).value()
    if not isinstance(out["bt_rules"], int):
        raise JsError("BT_RULES is not an integer: %r" % (out["bt_rules"],))
    if not isinstance(out["bt2"], dict) or not out["bt2"]:
        raise JsError("BT2 is not an object literal")
    return {k: out[k] for k in SNAPSHOT_FIELDS if k in out}


# every rules field of a datasheet; the Worker does not carry the page-only ones (veh and ch are cosmetic/UI, sec and
# lk are the opaque hidden-unit flags), so those are not compared
STAT_FIELDS = ["fac", "n", "pts", "mv", "T", "sv", "inv", "w", "ld", "oc", "r", "hero", "fly", "brave", "aura", "ca", "aoc", "st", "ac",
               "ttn", "rez", "heal", "vsh", "gk", "hd", "spawn", "heel", "wind"]
WEAPON_FIELDS = ["rng", "a", "bs", "ws", "s", "ap", "d", "rf", "as", "pi", "hv", "su", "tr", "lh", "dw", "bl", "po", "mk", "la"]


def compare(bt2, types):
    """Differences between the Worker's BT2 and the page's TYPES (stats must be identical; names may differ)."""
    diffs = []
    tmap = {t["k"]: t for t in types}
    for t in types:
        if t["k"] not in bt2:
            diffs.append("%s: missing in BT2" % t["k"])
    for k, e in bt2.items():
        t = tmap.get(k)
        if t is None:
            diffs.append("%s: in BT2 but not in types.json" % k)
            continue
        for f in STAT_FIELDS:
            if e.get(f) != t.get(f):
                diffs.append("%s.%s: BT2 %r != page %r" % (k, f, e.get(f), t.get(f)))
        for slot in ("gun", "mel"):
            a, b = e.get(slot), t.get(slot)
            if (a is None) != (b is None):
                diffs.append("%s.%s: BT2 %r != page %r" % (k, slot, a, b))
            elif a is not None:
                for f in WEAPON_FIELDS:
                    if a.get(f) != b.get(f):
                        diffs.append("%s.%s.%s: BT2 %r != page %r" % (k, slot, f, a.get(f), b.get(f)))
    return diffs


def sha256_file(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        h.update(f.read())
    return h.hexdigest()


def write_json(path, data):
    with open(path, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=2)
        f.write("\n")
    return os.path.getsize(path)


def from_worker(worker, out, strict):
    if not os.path.exists(worker):
        print("worker not found: %s (pass --worker PATH; the server repository is a sibling of this one)" % worker)
        return 2
    with open(worker, encoding="utf-8") as f:
        text = f.read()
    snap = {"source": "candlelight-server/worker.js", "worker_sha256": sha256_file(worker)}
    snap.update(extract(text))
    types_path = os.path.join(DATA, "types.json")
    diffs = []
    if os.path.exists(types_path):
        with open(types_path, encoding="utf-8") as f:
            diffs = compare(snap["bt2"], json.load(f))
    size = write_json(out, snap)
    print("wrote %s: BT_RULES %d, %d datasheets, %d army names, %d bytes" %
          (os.path.relpath(out, REPO), snap["bt_rules"], len(snap["bt2"]), len(snap["bt_army_en"]), size))
    for d in diffs[:30]:
        print("  %s BT2 differs: %s" % ("ERROR" if strict else "warning", d))
    if len(diffs) > 30:
        print("  ... %d more" % (len(diffs) - 30))
    if not diffs:
        print("  BT2 stats agree with data/types.json")
    return 1 if (strict and diffs) else 0


# ----------------------------------------------------------------------------------------------- abilities registry
# Thai as the page's abilityText / wpnLine shows it, English as the Worker's bt2Abilities tells Claude ({v} = the value).
A = lambda key, kind, value, th, en, applies=None: dict(  # noqa: E731 - one-line record maker
    [("key", key), ("kind", kind), ("value", value)] + ([("applies", applies)] if applies else []) + [("th", th), ("en", en)])
ABILITIES = [
    A("hero", "unit", "flag", "ตัวเอก", "character"),
    A("brave", "unit", "flag", "ไม่เคยถอย", "never fails the nerve test"),
    A("aoc", "unit", "flag", "เกราะศรัทธา (โดนเจาะ −1)", "armour of faith: incoming AP is 1 lower"),
    A("aura:hit", "aura", "string", "ผู้นำ: พวกในระยะ 6\" เข้าเป้า +1", "leader: friendly squads within 6\" get +1 to hit"),
    A("aura:ld", "aura", "string", "ผู้นำ: พวกในระยะ 6\" ไม่เสียขวัญ", "leader: friendly squads within 6\" pass the nerve test"),
    A("aura:bless", "aura", "string", "พรจากพระเจ้า: พวกในระยะ 6\" ได้เซฟพิเศษ 5++", "blessing: friendly squads within 6\" get a 5++ invulnerable save"),
    A("aura:rez", "aura", "string", "เทพแห่งความตาย: หน่วยที่ลุกได้ในระยะ 6\" ลุกตั้งแต่ 4+",
      "god of the dead: friendly squads within 6\" that reanimate stand up on a 4+"),
    A("ca", "unit", "flag", "บุกมา ตีเพิ่ม 1", "+1 attack per model in melee on the turn it charged"),
    A("ac", "unit", "flag", "วิ่งแล้วบุกได้", "may charge after advancing"),
    A("fly", "unit", "flag", "บิน (ถอยแล้วยิง/บุกได้)", "flies: may shoot and charge after falling back"),
    A("st", "unit", "flag", "พรางตัว (โดนยิง −1)", "stealth: -1 to hit it with ranged attacks"),
    A("rez", "unit", "int", "ซ่อมตัวเอง {v}+", "reanimates: in its command phase each fallen model stands up on a {v}+"),
    A("heel", "unit", "flag", "ส้นเท้า: โดนเจาะได้ 6 ตายทันที", "Achilles' heel: an unmodified 6 to wound slays him"),
    A("wind", "unit", "int", "ลูกพระพาย: ตายแล้วลุกขึ้นใหม่ต้นเฟสคำสั่งถัดไป แผลเต็ม (ครั้งแรกแน่นอน ครั้งต่อไปทอย {v}+)",
      "son of the wind: when he falls his body stays on the table, and at his side's next command phase he stands up "
      "where he fell with all his wounds (for sure the first time, later on a {v}+)"),
    A("spawn", "unit", "object", "ซ่อน{v} ตัวในท้อง", "carries {v} that come out in round 2 or when it is destroyed"),
    A("heal", "unit", "int", "รักษาเพื่อนในระยะ {v}\"", "heals a friendly squad within {v}\" instead of shooting"),
    A("ttn", "unit", "flag", "ร่างมหึมา: ติดประชิดก็ยังยิงได้ ถอยแล้วยิง/บุกได้",
      "titanic: can shoot while in melee, and can fall back and still shoot and charge"),
    A("vsh", "unit", "int", "โล่พลังงาน {v} ชั้น (ชั้นละกันได้ทั้งนัด ฟื้นทุกต้นตา)",
      "void shields: {v} layers, each swallows one whole failed save's damage; they all come back at its side's command phase"),
    A("hd", "unit", "flag", "ความเสียหายที่โดนลดครึ่ง", "takes half damage from every hit (rounded up)"),
    A("gk", "unit", "flag", "ฆ่าได้แล้วฟื้นแผล", "glory: every model it slays in melee heals it one wound"),
    A("aura:veil", "aura", "string", "หมอกพิษ: พวกในระยะ 6\" โดนยิงยากขึ้น",
      "veil: friendly squads within 6\" are hard to hit (-1 to hit them with ranged attacks)"),
    A("veh", "unit", "flag", "ยานพาหนะ", "vehicle"),
    A("ch", "unit", "string", "ภาคี: {v}", "chapter: {v}"),
    A("sec", "hidden", "flag", "ตัวลับ ไม่นับแต้ม ลงได้ทุกกองทัพ", "secret hero: joins free of the points budget, one per player"),
    A("lk", "hidden", "string", "หน่วยลับ ไม่นับแต้ม มีได้คนละตัว", "secret unit: free of the points budget, one per player"),
    A("el", "army", "flag", "สมาธิรบ: วิ่งแล้วยังยิงได้", "battle focus (space elves): may shoot after advancing"),
    A("de", "army", "flag", "ยิ่งรบยิ่งดุ: ตั้งแต่รอบ 3 ตีประชิดเข้า +1 และวิ่งแล้วบุกได้",
      "pain (dark elves): from round 3 it hits +1 in melee and may charge after advancing"),
    A("cx", "army", "flag", "สัญญาปีศาจ: ตีประชิดทอยเข้าได้ 6 เข้าเพิ่มอีกครั้ง",
      "dark pact (fallen knights and daemons): in melee each unmodified 6 to hit scores one extra hit"),
    A("ta", "army", "flag", "ชี้เป้าแล้วยิงรวม: อาวุธชี้เป้าให้พวกเดียวกันยิงเข้า +1",
      "designators (blue-skinned empire): marking weapons give friendly shooting +1 to hit on that target"),
    A("kn", "army", "flag", "ห้าภาคี: หน่วยขึ้นในรายชื่อใต้หัวข้อภาคีของตน",
      "five chapters (power-armour knights): units list under their chapter heading"),
    A("as", "weapon", "flag", "ยิงได้แม้วิ่ง", "may shoot after advancing", "gun"),
    A("hv", "weapon", "flag", "ยืนนิ่ง +1", "+1 to hit when the squad stood still", "gun"),
    A("rf", "weapon", "int", "ใกล้ครึ่งระยะ +{v}", "+{v} attacks per model within half range", "gun"),
    A("pi", "weapon", "flag", "ยิงตอนประชิดได้", "may shoot while engaged", "gun"),
    A("su", "weapon", "flag", "6 = เข้าเพิ่ม", "a hit roll of 6 is one extra hit", "gun"),
    A("tr", "weapon", "flag", "พ่น โดนอัตโนมัติ", "hits automatically, no hit roll", "gun"),
    A("bl", "weapon", "flag", "ระเบิดวงกว้าง: เป้าทุก 5 ตัว +1 นัด", "+1 attack per 5 models in the target squad", "gun"),
    A("mk", "weapon", "flag", "ชี้เป้า: ยิงเข้าแล้ว พวกเดียวกันยิงเป้านี้ +1 จนจบตา",
      "a hit marks the target: friendly shooting at it is +1 to hit this turn", "gun"),
    A("la", "weapon", "flag", "บุกมา +1 เจาะ", "+1 to wound on the turn the squad charged", "mel"),
    A("lh", "weapon", "flag", "เข้า 6 = เจาะเลย", "a hit roll of 6 wounds automatically", "both"),
    A("dw", "weapon", "flag", "เจาะ 6 = แผลตรง", "a wound roll of 6 is damage that ignores saves", "both"),
    A("po", "weapon", "int", "พิษ: เจาะทหารเดินเท้าได้ {v}+", "poison: wounds infantry on a {v}+ whatever its toughness", "both"),
    A("fx", "weapon", "string", "แสงและเสียง: {v}", "effect kind {v} (visual and sound only)", "both"),
    A("trail", "weapon", "string", "สีเส้นดาบ {v}", "swing trail colour {v} (visual only)", "mel"),
]


def ability_lines(t, lang, tmap, en):
    """The ability text of one datasheet in the page's order (unit flags, then army rule, then hidden flags)."""
    out = []
    for ab in ABILITIES:
        key, kind = ab["key"], ab["kind"]
        if kind == "weapon":
            continue
        if kind == "army":
            if t.get("fac") == key:
                out.append(ab[lang])
            continue
        if key.startswith("aura:"):
            if t.get("aura") == key[5:]:
                out.append(ab[lang])
            continue
        v = t.get(key)
        if not v:
            continue
        if key == "spawn":
            inner = tmap.get(v["k"], {})
            v = ("%s %d" % (inner.get("nm", v["k"]), v["n"])) if lang == "th" else ("%d %s" % (v["n"], en.get(inner.get("nm", ""), v["k"])))
        elif key == "ch" and lang == "en":
            v = en.get(v, v)                       # the chapter heading is a Thai key of i18n_en.json
        out.append(ab[lang].replace("{v}", str(v)))
    return out


def snapshot(out):
    def load(name):
        with open(os.path.join(DATA, name), encoding="utf-8") as f:
            return json.load(f)

    en = load("i18n_en.json")
    missing = []

    def tr(s, what):
        if s not in en:
            missing.append("%s: %r" % (what, s))
            return ""
        return en[s]

    types, facs, constants = load("types.json"), load("facs.json"), load("constants.json")
    version_path = os.path.join(DATA, "version.json")
    rules_ver = 10
    if os.path.exists(version_path):
        rules_ver = load("version.json").get("rules_ver", rules_ver)
    army_en = {}
    snap_path = os.path.join(DATA, "bt2_snapshot.json")
    if os.path.exists(snap_path):
        army_en = load("bt2_snapshot.json").get("bt_army_en", {})
    tmap = {t["k"]: t for t in types}
    armies = []
    for f in facs:
        armies.append({"k": f["k"], "nm": f["nm"], "en": army_en.get(f["k"]) or tr(f["nm"], "army " + f["k"]),
                       "d": f["d"], "d_en": tr(f["d"], "army %s blurb" % f["k"])})
    if "*" in army_en:
        armies.append({"k": "*", "nm": "ทุกกองทัพ", "en": army_en["*"]})
    out_types = []
    for t in types:
        e = {}
        for k, v in t.items():
            e[k] = v
            if k == "nm":
                e["en"] = tr(v, "unit %s nm" % t["k"])
            elif k == "d":
                e["d_en"] = tr(v, "unit %s d" % t["k"])
        for slot in ("gun", "mel"):
            w = t.get(slot)
            if isinstance(w, dict):
                ww = {}
                for k, v in w.items():
                    ww[k] = v
                    if k == "nm":
                        ww["en"] = tr(v, "unit %s %s" % (t["k"], slot))
                e[slot] = ww
        e["abilities"] = ability_lines(t, "en", tmap, en)
        e["abilities_th"] = ability_lines(t, "th", tmap, en)
        out_types.append(e)
    themes = {k: {"nm": v["name"], "en": tr(v["name"], "theme " + k)} for k, v in load("themes.json").items()}
    terrains = {k: {"nm": v["name"], "en": tr(v["name"], "terrain " + k)} for k, v in load("terrains.json").items()}
    ph = load("phases.json")
    phases = [{"k": p, "nm": ph["nm"][p], "en": tr(ph["nm"][p], "phase " + p)} for p in ph["order"]]
    strats = {k: {"nm": v["nm"], "en": tr(v["nm"], "stratagem " + k), "cp": v["cp"]} for k, v in load("strats.json").items()}
    if missing:
        print("Thai strings without an English entry in data/i18n_en.json (add them in the page, re-export):")
        for m in missing[:30]:
            print("  " + m)
        return 1
    data = {"rules_ver": rules_ver, "page_app_ver": constants["APP_VER"], "page_rules_v": constants["RULES_V"],
            "generated_by": "tools/gen_bt_data.py --snapshot", "armies": armies, "order": [t["k"] for t in types],
            "types": out_types, "abilities": ABILITIES, "themes": themes, "terrains": terrains, "phases": phases, "strats": strats}
    size = write_json(out, data)
    print("wrote %s: %d datasheets, %d armies, %d abilities, %d bytes%s" %
          (os.path.relpath(out, REPO), len(out_types), len(armies), len(ABILITIES), size,
           " (over 1 MB: git-ignore it)" if size > 1_000_000 else ""))
    return 0


# ----------------------------------------------------------------------------------------------- self-test
def self_test():
    """Extraction over the fake worker fixture; returns a list of problems (empty = pass)."""
    errs = []
    fake = os.path.join(FIXTURES, "fake_worker.js")
    expected_path = os.path.join(FIXTURES, "fake_worker.expected.json")
    try:
        with open(fake, encoding="utf-8") as f:
            got = extract(f.read())
    except (OSError, JsError) as e:
        return ["fake worker: %s" % e]
    with open(expected_path, encoding="utf-8") as f:
        expected = json.load(f)
    for k in SNAPSHOT_FIELDS:
        if got.get(k) != expected.get(k):
            errs.append("%s: got %s, expected %s" % (k, json.dumps(got.get(k), ensure_ascii=False)[:120],
                                                     json.dumps(expected.get(k), ensure_ascii=False)[:120]))
    # the parser's corner cases
    try:
        v = JsLiteral("{ a: 1, 'b': [1, 2.5, -3, 'x', \"y\", `z`,], c: { d: null, e: true, }, /* c */ f: \"q\\\"\\u0e01\" } // end").value()
        if v != {"a": 1, "b": [1, 2.5, -3, "x", "y", "z"], "c": {"d": None, "e": True}, "f": "q\"ก"}:
            errs.append("parser corner cases: %r" % (v,))
    except JsError as e:
        errs.append("parser corner cases: %s" % e)
    try:
        JsLiteral("{ a: BT_X }").value()
        errs.append("parser accepted an identifier reference")
    except JsError:
        pass
    diffs = compare(got["bt2"], [{"k": k, **v} for k, v in got["bt2"].items()])
    if diffs:
        errs.append("compare() reports differences for identical data: %s" % diffs[:3])
    return errs


def main(argv=None):
    ap = argparse.ArgumentParser(description="server-side data for the battle table (see the module docstring)")
    ap.add_argument("--worker", default=DEFAULT_WORKER, help="path of candlelight-server/worker.js")
    ap.add_argument("--snapshot", action="store_true", help="derive data/bt_data.json from data/*.json")
    ap.add_argument("--self-test", action="store_true", help="run the extraction over the fake worker fixture")
    ap.add_argument("--strict", action="store_true", help="BT2/types.json differences are errors")
    ap.add_argument("--out", default=None, help="output file (default data/bt2_snapshot.json or data/bt_data.json)")
    a = ap.parse_args(argv)
    if a.self_test:
        errs = self_test()
        for e in errs:
            print("FAIL " + e)
        print("PASS fake worker extraction" if not errs else "FAIL fake worker extraction")
        return 1 if errs else 0
    if a.snapshot:
        return snapshot(a.out or os.path.join(DATA, "bt_data.json"))
    try:
        return from_worker(a.worker, a.out or os.path.join(DATA, "bt2_snapshot.json"), a.strict)
    except JsError as e:
        print("cannot read the Worker's tables: %s" % e)
        return 1


if __name__ == "__main__":
    sys.exit(main())
