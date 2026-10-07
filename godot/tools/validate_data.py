#!/usr/bin/env python3
"""validate_data.py — the data lint of the new app (godot/). Standard library only, Python 3.8+.

    python3 godot/tools/validate_data.py                 # every check below, exit 1 on any failure (< 10 s)
    python3 godot/tools/validate_data.py --fixtures      # only the planted fixtures under godot/tests/data_fixtures/
    python3 godot/tools/validate_data.py --write-version # rewrite godot/data/version.json (and core/version.gd DATA_HASH)
    python3 godot/tools/validate_data.py --write-legacy  # rewrite data/schema/legacy_tokens.sha1 (dedicated PR only)
    python3 godot/tools/validate_data.py --base REV      # compare types.json order against REV (default HEAD, then HEAD~1)

Checks, each printed as one `ok`/`FAIL` line:
  schema    every godot/data/*.json validates against its schema in data/schema/ (a small JSON-Schema 2020-12 validator
            lives below: no pip here), then cross-table checks: keys exist, every Thai display string is a key of
            data/i18n_en.json, no float where the rules want an integer (a JSON 2.0 is NOT an integer here), every
            datasheet carries the derived inf (foot soldier) field.
  names     the banned names of AGENTS.md rule 1 over every text file and file name under godot/ (case-insensitive;
            distinctive names as substrings, common words whole-word). A few old unit keys carry such words: their
            SHA-1 hashes are the committed baseline data/schema/legacy_tokens.sha1 and they are allowed only inside
            data/*.json, data/schema/ and tests/. Anything new anywhere fails. The list itself is stored ROT13 so this
            file passes its own scan; the readable list is AGENTS.md rule 1. Brand names may appear in .md files that
            restate the rule.
  i18n      every Thai string literal in godot/ui/** and godot/app/** (.gd and .tscn) has an English entry in
            ui/i18n_extra.json or data/i18n_en.json (a literal passes when the longest-key fragment matching of the old
            page leaves no Thai character, like BT_I18N.tr).
  order     data/types.json is append-only against the previous commit (git show); skipped with a note outside git.
  dice      no datasheet can roll more than --dice-cap (60) dice in one stage (see dice_worst_case for the sum).
  secrets   nothing that looks like a token, key, private key or keystore under godot/.
  version   data/version.json carries the sha256 of the data (and core/version.gd DATA_HASH agrees when it exists).
  fixtures  tests/data_fixtures: the planted failures fail and the good samples pass; gen_bt_data.py self-test.
"""
import argparse
import codecs
import hashlib
import json
import os
import re
import subprocess
import sys
import tempfile
import time
from functools import lru_cache

HERE = os.path.dirname(os.path.abspath(__file__))
GODOT = os.path.dirname(HERE)                      # godot/
REPO = os.path.dirname(GODOT)                      # the repository root
SCHEMA_DIR = os.path.join(GODOT, "data", "schema")
FIXTURES = os.path.join(GODOT, "tests", "data_fixtures")
LEGACY_FILE = os.path.join(SCHEMA_DIR, "legacy_tokens.sha1")

NEW_RULES_VER = 10          # the new app's rules version (ARCHITECTURE section 4); core/version.gd RULES_V must agree
DICE_CAP = 60               # the Worker cuts dice arrays to 60 (ARCHITECTURE section 4, "Dice")
THAI = re.compile("[฀-๿]")

# which schema validates which data file (a data file without an entry here fails: every table gets a schema)
FILE_SCHEMAS = {
    "types.json": {"type": "array", "minItems": 1, "items": {"$ref": "unit.json"}},
    "facs.json": {"type": "array", "minItems": 1, "items": {"$ref": "army.json"}},
    "core.json": {"$ref": "army.json#/$defs/core"},
    "themes.json": {"$ref": "theme.json#/$defs/table"},
    "i18n_en.json": {"$ref": "i18n.json"},
    "terrains.json": {"$ref": "tables.json#/$defs/terrains"},
    "teams.json": {"$ref": "tables.json#/$defs/teams"},
    "phases.json": {"$ref": "tables.json#/$defs/phases"},
    "chapters.json": {"$ref": "tables.json#/$defs/chapters"},
    "variants.json": {"$ref": "tables.json#/$defs/variants"},
    "skins.json": {"$ref": "tables.json#/$defs/skins"},
    "fly.json": {"$ref": "tables.json#/$defs/fly"},
    "strats.json": {"$ref": "tables.json#/$defs/strats"},
    "anim.json": {"$ref": "tables.json#/$defs/anim"},
    "fx.json": {"$ref": "tables.json#/$defs/fx"},
    "natural.json": {"$ref": "tables.json#/$defs/natural"},
    "unit_colours.json": {"$ref": "tables.json#/$defs/unit_colours"},
    "sky.json": {"$ref": "tables.json#/$defs/sky"},
    "dust.json": {"$ref": "tables.json#/$defs/dust"},
    "constants.json": {"$ref": "tables.json#/$defs/constants"},
    "version.json": {"$ref": "tables.json#/$defs/version"},
    "bt2_snapshot.json": {"$ref": "tables.json#/$defs/bt2_snapshot"},
    "bt_data.json": {"$ref": "tables.json#/$defs/bt_data"},
}

TEXT_EXT = {".gd", ".tscn", ".tres", ".json", ".md", ".txt", ".cfg", ".godot", ".py", ".js", ".mjs", ".cjs", ".sh", ".yml",
            ".yaml", ".gdshader", ".import", ".uid", ".svg", ".csv", ".html", ".sha1", ".rot13", ".toml", ".ini", ".xml",
            ".ts", ".gdextension", ".properties", ".gradle", ".kt", ".java", ".c", ".cpp", ".h", ".res"}
SKIP_DIRS = {".godot", ".git", "node_modules", "__pycache__"}
SKIP_PATHS = {"assets/kits", "assets/impostors", "assets/anim", "tests/out"}       # generated, git-ignored


# ----------------------------------------------------------------------------------------------- small helpers
def read_json(path):
    with open(path, encoding="utf-8") as f:
        return json.load(f)


def read_text(path):
    with open(path, encoding="utf-8", errors="replace") as f:
        return f.read()


def rel(path, root):
    return os.path.relpath(path, root).replace(os.sep, "/")


def iter_text_files(root):
    """(relative path, absolute path) of every text file under root, skipping generated folders and binaries."""
    for dp, dns, fns in os.walk(root):
        dns[:] = sorted(d for d in dns if d not in SKIP_DIRS and rel(os.path.join(dp, d), root) not in SKIP_PATHS)
        for fn in sorted(fns):
            p = os.path.join(dp, fn)
            ext = os.path.splitext(fn)[1].lower()
            if ext in TEXT_EXT or (ext == "" and looks_text(p)) or fn.startswith("."):
                yield rel(p, root), p


def looks_text(path):
    try:
        with open(path, "rb") as f:
            head = f.read(2048)
        return b"\0" not in head and bool(head.decode("utf-8"))
    except (OSError, UnicodeDecodeError):
        return False


def git(args, cwd=REPO):
    try:
        r = subprocess.run(["git"] + args, cwd=cwd, capture_output=True, text=True, timeout=20)
    except (OSError, subprocess.SubprocessError):
        return None
    return r.stdout if r.returncode == 0 else None


def git_show(rev, relpath):
    out = git(["show", "%s:%s" % (rev, relpath)])
    return out


# ----------------------------------------------------------------------------------------------- JSON Schema (subset)
class Validator:
    """Enough of JSON Schema 2020-12 for data/schema/*.json: type, enum, const, properties, required,
    additionalProperties, patternProperties, propertyNames, items, prefixItems, min/max*, pattern, uniqueItems,
    anyOf/oneOf/allOf/not, if/then/else, dependentRequired and $ref (local '#/...' and sibling files)."""

    def __init__(self, schema_dir=SCHEMA_DIR):
        self.dir = schema_dir
        self.docs = {}

    def doc(self, name):
        if name not in self.docs:
            self.docs[name] = read_json(os.path.join(self.dir, name))
        return self.docs[name]

    def resolve(self, ref, doc_name):
        file, _, frag = ref.partition("#")
        name = file or doc_name
        node = self.doc(name)
        if frag and frag != "/":
            for part in frag.lstrip("/").split("/"):
                part = part.replace("~1", "/").replace("~0", "~")
                node = node[part] if isinstance(node, dict) else node[int(part)]
        return node, name

    @staticmethod
    def is_type(v, t):
        if t == "integer":
            return isinstance(v, int) and not isinstance(v, bool)
        if t == "number":
            return isinstance(v, (int, float)) and not isinstance(v, bool)
        return {"string": str, "boolean": bool, "null": type(None), "array": list, "object": dict}[t] is type(v) or \
            (t == "object" and isinstance(v, dict)) or (t == "array" and isinstance(v, list))

    @staticmethod
    def type_name(v):
        if isinstance(v, bool):
            return "boolean"
        if isinstance(v, int):
            return "integer"
        if isinstance(v, float):
            return "number (float)"
        return {str: "string", list: "array", dict: "object", type(None): "null"}.get(type(v), type(v).__name__)

    @staticmethod
    def same(a, b):
        if isinstance(a, bool) or isinstance(b, bool):
            return type(a) is type(b) and a == b
        return type(a) is type(b) and a == b if isinstance(a, (int, float)) else a == b

    @staticmethod
    def short(v):
        s = json.dumps(v, ensure_ascii=False)
        return s if len(s) <= 60 else s[:57] + "..."

    @staticmethod
    @lru_cache(maxsize=512)
    def rx(pattern):
        return re.compile(pattern)

    def validate(self, inst, schema, doc_name=None, path="$", limit=40):
        errs = []
        if isinstance(schema, str):              # a schema file name
            doc_name, schema = schema, self.doc(schema)
        self._v(inst, schema, doc_name or "", path, errs, limit)
        return errs

    def _v(self, inst, sch, dn, path, errs, limit):
        if len(errs) >= limit:
            return
        if sch is True:
            return
        if sch is False:
            errs.append("%s: no value allowed here" % path)
            return

        def err(msg):
            if len(errs) < limit:
                errs.append("%s: %s" % (path, msg))

        if "$ref" in sch:
            target, tdn = self.resolve(sch["$ref"], dn)
            self._v(inst, target, tdn, path, errs, limit)
        t = sch.get("type")
        if t is not None:
            types = t if isinstance(t, list) else [t]
            if not any(self.is_type(inst, x) for x in types):
                err("expected %s, got %s %s" % ("/".join(types), self.type_name(inst), self.short(inst)))
                return
        if "enum" in sch and not any(self.same(inst, e) for e in sch["enum"]):
            err("%s is not one of %s" % (self.short(inst), self.short(sch["enum"])))
        if "const" in sch and not self.same(inst, sch["const"]):
            err("%s is not the constant %s" % (self.short(inst), self.short(sch["const"])))
        if isinstance(inst, (int, float)) and not isinstance(inst, bool):
            for key, ok, word in (("minimum", lambda a, b: a >= b, ">="), ("maximum", lambda a, b: a <= b, "<="),
                                  ("exclusiveMinimum", lambda a, b: a > b, ">"), ("exclusiveMaximum", lambda a, b: a < b, "<")):
                if key in sch and not ok(inst, sch[key]):
                    err("%s must be %s %s" % (inst, word, sch[key]))
            if "multipleOf" in sch and (inst / sch["multipleOf"]) % 1 != 0:
                err("%s is not a multiple of %s" % (inst, sch["multipleOf"]))
        if isinstance(inst, str):
            if "minLength" in sch and len(inst) < sch["minLength"]:
                err("string shorter than %d: %s" % (sch["minLength"], self.short(inst)))
            if "maxLength" in sch and len(inst) > sch["maxLength"]:
                err("string longer than %d" % sch["maxLength"])
            if "pattern" in sch and not self.rx(sch["pattern"]).search(inst):
                err("%s does not match /%s/" % (self.short(inst), sch["pattern"]))
        if isinstance(inst, list):
            if "minItems" in sch and len(inst) < sch["minItems"]:
                err("fewer than %d items" % sch["minItems"])
            if "maxItems" in sch and len(inst) > sch["maxItems"]:
                err("more than %d items" % sch["maxItems"])
            if sch.get("uniqueItems"):
                seen = set()
                for i, v in enumerate(inst):
                    k = json.dumps(v, sort_keys=True)
                    if k in seen:
                        err("item %d is a duplicate" % i)
                    seen.add(k)
            pre = sch.get("prefixItems", [])
            for i, s in enumerate(pre[:len(inst)]):
                self._v(inst[i], s, dn, "%s[%d]" % (path, i), errs, limit)
            if "items" in sch:
                for i in range(len(pre), len(inst)):
                    self._v(inst[i], sch["items"], dn, "%s[%d]" % (path, i), errs, limit)
        if isinstance(inst, dict):
            for k in sch.get("required", []):
                if k not in inst:
                    err("missing required field %r" % k)
            if "minProperties" in sch and len(inst) < sch["minProperties"]:
                err("fewer than %d entries" % sch["minProperties"])
            if "maxProperties" in sch and len(inst) > sch["maxProperties"]:
                err("more than %d entries" % sch["maxProperties"])
            for k, deps in sch.get("dependentRequired", {}).items():
                if k in inst:
                    for d in deps:
                        if d not in inst:
                            err("%r requires %r" % (k, d))
            props = sch.get("properties", {})
            pats = sch.get("patternProperties", {})
            for k, v in inst.items():
                sub = path + "." + k
                if "propertyNames" in sch:
                    self._v(k, sch["propertyNames"], dn, sub + " (name)", errs, limit)
                matched = False
                if k in props:
                    matched = True
                    self._v(v, props[k], dn, sub, errs, limit)
                for pat, s in pats.items():
                    if self.rx(pat).search(k):
                        matched = True
                        self._v(v, s, dn, sub, errs, limit)
                if not matched and "additionalProperties" in sch:
                    ap = sch["additionalProperties"]
                    if ap is False:
                        err("unknown field %r (every field must be in the schema)" % k)
                    else:
                        self._v(v, ap, dn, sub, errs, limit)
        for key in ("allOf",):
            for s in sch.get(key, []):
                self._v(inst, s, dn, path, errs, limit)
        if "anyOf" in sch or "oneOf" in sch:
            for key in ("anyOf", "oneOf"):
                if key not in sch:
                    continue
                oks, best = 0, None
                for s in sch[key]:
                    e = []
                    self._v(inst, s, dn, path, e, limit)
                    if not e:
                        oks += 1
                    elif best is None or (len(e), -len(e[0].split(":")[0])) < (len(best), -len(best[0].split(":")[0])):
                        best = e                   # the closest branch: fewest errors, deepest first error
                if oks == 0:
                    err("matches none of %s (closest branch: %s)" % (key, best[0]))
                elif key == "oneOf" and oks > 1:
                    err("matches %d branches of oneOf" % oks)
        if "not" in sch:
            e = []
            self._v(inst, sch["not"], dn, path, e, limit)
            if not e:
                err("must not match the 'not' schema")
        if "if" in sch:
            e = []
            self._v(inst, sch["if"], dn, path, e, limit)
            branch = sch.get("then") if not e else sch.get("else")
            if branch is not None:
                self._v(inst, branch, dn, path, errs, limit)


# ----------------------------------------------------------------------------------------------- 1. schema + cross-table
def thai_display_strings(d):
    """(label, Thai string) for every display string of the tables that must be a key of i18n_en.json."""
    out = []
    for t in d.get("types.json", []):
        out += [("types %s nm" % t["k"], t["nm"]), ("types %s d" % t["k"], t["d"])]
        for w in ("gun", "mel"):
            if isinstance(t.get(w), dict) and "nm" in t[w]:
                out.append(("types %s %s.nm" % (t["k"], w), t[w]["nm"]))
        if "ch" in t:
            out.append(("types %s ch" % t["k"], t["ch"]))
    for f in d.get("facs.json", []):
        out += [("facs %s nm" % f["k"], f["nm"]), ("facs %s d" % f["k"], f["d"])]
    for k, v in d.get("themes.json", {}).items():
        out.append(("themes %s" % k, v["name"]))
    for k, v in d.get("terrains.json", {}).items():
        out.append(("terrains %s" % k, v["name"]))
    for i, v in enumerate(d.get("teams.json", [])):
        out.append(("teams[%d]" % i, v["nm"]))
    for k, v in d.get("phases.json", {}).get("nm", {}).items():
        out.append(("phases %s" % k, v))
    for k, v in d.get("strats.json", {}).items():
        out.append(("strats %s" % k, v["nm"]))
    for k, v in d.get("chapters.json", {}).items():
        out += [("chapters key", k), ("chapters %s desc" % k, v[2])]
    for k, v in d.get("skins.json", {}).items():
        out += [("skins %s %s" % (k, s["k"]), s["nm"]) for s in v]
    return out


def cross_checks(d):
    """Relations between the tables that a per-file schema cannot say."""
    errs = []
    T = d.get("types.json")
    if not T:
        return errs
    keys = [t["k"] for t in T]
    kset = set(keys)
    dup = sorted({k for k in keys if keys.count(k) > 1})
    if dup:
        errs.append("types.json: duplicate keys %s" % dup)
    facs = {f["k"] for f in d.get("facs.json", [])}
    fx_kinds = set(d.get("fx.json", {}).get("fxs", {}))
    chapters = set(d.get("chapters.json", {}))
    for t in T:
        if facs and t["fac"] != "*" and t["fac"] not in facs:
            errs.append("types %s: fac %r is not in facs.json" % (t["k"], t["fac"]))
        if "spawn" in t and t["spawn"]["k"] not in kset:
            errs.append("types %s: spawn.k %r is not a unit key" % (t["k"], t["spawn"]["k"]))
        if "lk" in t and facs and t["lk"] not in facs:
            errs.append("types %s: lk %r is not an army code" % (t["k"], t["lk"]))
        if "ch" in t and chapters and t["ch"] not in chapters:
            errs.append("types %s: ch %r is not a key of chapters.json" % (t["k"], t["ch"]))
        if "inf" not in t:                         # derived by export_data.js from the page's INF(k); rules read it
            errs.append("types %s: no inf (foot soldier 1/0): re-run tools/export_data.js" % t["k"])
        elif t.get("veh") and t["inf"]:
            errs.append("types %s: a vehicle cannot be a foot soldier (inf 1 with veh)" % t["k"])
        for w in ("gun", "mel"):
            if isinstance(t.get(w), dict) and "fx" in t[w] and fx_kinds and t[w]["fx"] not in fx_kinds:
                errs.append("types %s: %s.fx %r is not a kind of fx.json" % (t["k"], w, t[w]["fx"]))
    hidden = {t["k"] for t in T if "sec" in t or "lk" in t}
    for army, pool in d.get("core.json", {}).items():
        if facs and army not in facs:
            errs.append("core.json: army %r is not in facs.json" % army)
        for k in pool:
            if k not in kset:
                errs.append("core.json %s: %r is not a unit key" % (army, k))
            elif k in hidden:
                errs.append("core.json %s: %r is a hidden unit; bot pools never carry one" % (army, k))
    kits = set(kset)
    for k, v in d.get("variants.json", {}).items():
        if k not in kset:
            errs.append("variants.json: %r is not a unit key" % k)
        kits.update(v)
    for k, v in d.get("skins.json", {}).items():
        if k not in kset:
            errs.append("skins.json: %r is not a unit key" % k)
        kits.update(s["k"] for s in v)
    for name in ("fly.json", "unit_colours.json"):
        for k in d.get(name, {}):
            if k not in kits:
                errs.append("%s: %r is not a kit key" % (name, k))
    for k in d.get("anim.json", {}).get("anim", {}):
        if k not in kits:
            errs.append("anim.json: %r is not a kit key" % k)
    fx = d.get("fx.json", {})
    for k in fx.get("fx_st", {}):
        if k not in fx_kinds:
            errs.append("fx.json fx_st: %r is not a kind" % k)
    for g, k in fx.get("fx_gun", {}).items():
        if k not in fx_kinds:
            errs.append("fx.json fx_gun %s: %r is not a kind" % (g, k))
    for name in ("mach8", "beast8"):
        for k in fx.get(name, {}):
            if k not in kits:
                errs.append("fx.json %s: %r is not a kit key" % (name, k))
    ph = d.get("phases.json", {})
    if ph and set(ph.get("order", [])) != set(ph.get("nm", {})):
        errs.append("phases.json: order and nm disagree")
    c = d.get("constants.json", {})
    if c and c.get("BUDGETS") != sorted(c.get("BUDGETS", [])):
        errs.append("constants.json: BUDGETS must be ascending")
    for name in ("themes.json", "terrains.json"):
        pass
    if c and d.get("themes.json") and c.get("theme") not in d["themes.json"]:
        errs.append("constants.json: default theme %r is not in themes.json" % c.get("theme"))
    if c and d.get("terrains.json") and c.get("terrain") not in d["terrains.json"]:
        errs.append("constants.json: default terrain %r is not in terrains.json" % c.get("terrain"))
    en = d.get("i18n_en.json")
    if en is not None:
        for k, v in en.items():
            if isinstance(v, str) and THAI.search(v) and k not in LANG_NAMES:
                errs.append("i18n_en.json %r: the English %r still contains Thai" % (k, v))
        for label, s in thai_display_strings(d):
            if s not in en:
                errs.append("%s: Thai %r has no English entry in i18n_en.json (add it in the page, re-export)" % (label, s))
    snap = d.get("bt2_snapshot.json")
    if snap:
        bt2 = snap.get("bt2", {})
        if set(bt2) - kset:
            errs.append("bt2_snapshot.json: keys not in types.json: %s" % sorted(set(bt2) - kset)[:8])
        if snap.get("bt_rules") != c.get("RULES_V"):
            errs.append("bt2_snapshot.json: Worker BT_RULES %s != page RULES_V %s" % (snap.get("bt_rules"), c.get("RULES_V")))
    bd = d.get("bt_data.json")
    if bd and bd.get("order") != keys:
        errs.append("bt_data.json: order differs from types.json (rerun gen_bt_data.py --snapshot)")
    return errs


def check_schema(data_dir, validator):
    errs, notes = [], []
    files = sorted(f for f in os.listdir(data_dir) if f.endswith(".json"))
    d = {}
    for f in files:
        try:
            d[f] = read_json(os.path.join(data_dir, f))
        except ValueError as e:
            errs.append("%s: not valid JSON: %s" % (f, e))
            continue
        if f not in FILE_SCHEMAS:
            errs.append("%s: no schema for this table (add one to data/schema/ and FILE_SCHEMAS)" % f)
            continue
        for e in validator.validate(d[f], FILE_SCHEMAS[f], "tables.json", "$"):
            errs.append("%s %s" % (f, e))
    errs += cross_checks(d)
    n_types = len(d.get("types.json", []))
    notes.append("%d files, %d units, %d English strings" % (len(files), n_types, len(d.get("i18n_en.json", {}))))
    return errs, notes, d


# ----------------------------------------------------------------------------------------------- 2. banned names
# ROT13 so this file passes its own scan (the readable list is AGENTS.md rule 1); matched case-insensitively.
_SUB = ['tnzrf jbexfubc', 'jneunzzre', 'fcnpr znevar', 'nfgnegrf', 'glenavq', 'arpeba', 'nryqnev', 'ryqne', 'qehxunev', 'xubear',
        'ahetyr', 'gmrragpu', 'fynnarfu', 'vzcrevhz', 'cevznepu', 'grezvangbe', 'qernqabhtug', 'ynaq envqre', 'yrzna ehff',
        'pneavsrk', 'jneubhaq', 'jneybeq', 'vzcrengbe', 'pnfgryyna', 'xavtug cnynqva', 'xavtug jneqra', 'pevfvf fhvg', 'evcgvqr',
        'fgbezfhetr', 'thaqnz', 'thacyn', 'zbovyr fhvg', 'zbovyr-fhvg', 'mnxh']
_WORD = ['bex', 'bexf', 'gnh', "g'nh", 'punbf', 'ernire', 'erniref', 'jneqra', 'jneqraf', 'cnynqva', 'cnynqvaf']
_BRAND = ['tnzrf jbexfubc', 'jneunzzre', 'thaqnz', 'thacyn', 'zbovyr fhvg', 'zbovyr-fhvg']
SUB = [codecs.decode(s, "rot13") for s in _SUB]
WORD = [codecs.decode(s, "rot13") for s in _WORD]
BRAND = {codecs.decode(s, "rot13") for s in _BRAND}
GODOT_TWO_PI = codecs.decode("GNH", "rot13")          # Godot's 2*pi constant, allowed in upper case only
LANG_NAMES = {"ไทย"}                                   # i18n values that may keep Thai: a language shown in its own script
TOKEN_CHARS = re.compile(r"[a-z0-9_']")
_BANNED_RX = None


def banned_regex():
    global _BANNED_RX
    if _BANNED_RX is None:
        sub = "|".join(re.escape(s) for s in sorted(SUB, key=len, reverse=True))
        word = "|".join(re.escape(w) for w in sorted(WORD, key=len, reverse=True))
        _BANNED_RX = re.compile(r"(?P<sub>%s)|(?<![a-z0-9_'])(?P<word>%s)(?![a-z0-9_'])" % (sub, word))
    return _BANNED_RX


def banned_hits(text):
    """(start, end, pattern, token) for every banned match in text; token = the match widened to identifier edges."""
    low = text.lower()
    out = []
    for m in banned_regex().finditer(low):
        a, e = m.start(), m.end()
        pat = m.group("sub") or m.group("word")
        if m.group("word") == GODOT_TWO_PI.lower() and text[a:e] == GODOT_TWO_PI:
            continue                                   # Godot's upper-case 2*pi constant is not the banned word
        while a > 0 and TOKEN_CHARS.match(low[a - 1]):
            a -= 1
        while e < len(low) and TOKEN_CHARS.match(low[e]):
            e += 1
        out.append((a, e, pat, low[a:e]))
    return out


def sha1(token):
    return hashlib.sha1(token.encode("utf-8")).hexdigest()


def load_legacy():
    if not os.path.exists(LEGACY_FILE):
        return set()
    return {line.strip() for line in read_text(LEGACY_FILE).splitlines() if line.strip() and not line.startswith("#")}


def legacy_allowed(relpath):
    """Where a baseline token may appear: generated tables, the schemas and the tests."""
    return (relpath.startswith("data/") and relpath.count("/") == 1 and relpath.endswith(".json")) or \
        relpath.startswith("data/schema/") or relpath.startswith("tests/")


def check_names(root, legacy):
    errs, n_files = [], 0
    for relpath, p in iter_text_files(root):
        if relpath.endswith(".rot13"):
            continue                                   # fixture inputs stored encoded on purpose
        n_files += 1
        is_md = relpath.endswith(".md")
        for a, e, pat, tok in banned_hits(os.path.basename(relpath).lower()):
            errs.append("%s: file name contains a banned name (%s)" % (relpath, tok))
        text = read_text(p)
        for a, e, pat, tok in banned_hits(text):
            if is_md and pat in BRAND:
                continue                               # a doc restating the rule may name the company
            if sha1(tok) in legacy and legacy_allowed(relpath):
                continue
            line = text.count("\n", 0, a) + 1
            errs.append("%s:%d: banned name %r (AGENTS.md rule 1)" % (relpath, line, tok))
            if len(errs) > 60:
                errs.append("... more")
                return errs, n_files
    return errs, n_files


def legacy_tokens(base):
    """The baseline: every banned token found in types.json, i18n_en.json and the Worker's datasheet copy
    bt2_snapshot.json at `base` (or the working files when the revision has no such file)."""
    toks = set()
    for name in ("types.json", "i18n_en.json", "bt2_snapshot.json"):
        text = git_show(base, "godot/data/" + name) if base else None
        if text is None:
            p = os.path.join(GODOT, "data", name)
            if not os.path.exists(p):
                continue
            text = read_text(p)
        for a, e, pat, tok in banned_hits(text):
            toks.add(tok)
    return toks


def write_legacy(base):
    toks = legacy_tokens(base)
    lines = ["# SHA-1 of the lower-cased legacy tokens (old unit keys and server names that carry a word of AGENTS.md rule 1)",
             "# found in data/types.json, data/i18n_en.json and data/bt2_snapshot.json when this baseline was made. They are",
             "# allowed only inside data/*.json,",
             "# data/schema/ and tests/; a new occurrence anywhere fails validate_data.py. Hashes, so the file does not",
             "# spell them out. Regenerate only in a dedicated renaming PR: validate_data.py --write-legacy [--base REV]."]
    lines += sorted(sha1(t) for t in toks)
    with open(LEGACY_FILE, "w", encoding="utf-8") as f:
        f.write("\n".join(lines) + "\n")
    return len(toks)


# ----------------------------------------------------------------------------------------------- 3. Thai -> English in the UI
def string_literals(src):
    """(line, text) of every string literal in GDScript or .tscn source; '#' comments outside strings are skipped."""
    out, i, n, line = [], 0, len(src), 1
    while i < n:
        c = src[i]
        if c == "\n":
            line += 1
            i += 1
        elif c == "#":
            j = src.find("\n", i)
            i = n if j < 0 else j
        elif c in "\"'":
            q = src[i:i + 3] if src[i:i + 3] in ('"""', "'''") else c
            j, buf, start = i + len(q), [], line
            while j < n and not src.startswith(q, j):
                if src[j] == "\\" and j + 1 < n:
                    buf.append({"n": "\n", "t": "\t", '"': '"', "'": "'", "\\": "\\"}.get(src[j + 1], src[j + 1]))
                    j += 2
                    continue
                if src[j] == "\n":
                    line += 1
                buf.append(src[j])
                j += 1
            out.append((start, "".join(buf)))
            i = j + len(q)
        else:
            i += 1
    return out


def en_dict_literals(path):
    """Keys of a `const EN := { "thai": "english", ... }` literal in a GDScript file (the pre-R0-A I18n)."""
    keys = set()
    if os.path.exists(path):
        for m in re.finditer(r'^\s*"((?:[^"\\]|\\.)*)"\s*:\s*"', read_text(path), re.M):
            keys.add(m.group(1).replace('\\"', '"'))
    return keys


def ui_dictionary(root, validator=None):
    keys, errs, sources = set(), [], []
    p = os.path.join(root, "data", "i18n_en.json")
    if os.path.exists(p):
        keys.update(read_json(p))
        sources.append("data/i18n_en.json")
    p = os.path.join(root, "ui", "i18n_extra.json")
    if os.path.exists(p):
        try:
            extra = read_json(p)
            if validator is not None:
                errs += ["ui/i18n_extra.json %s" % e for e in validator.validate(extra, "i18n.json")]
            for k, v in extra.items():
                if isinstance(v, str) and THAI.search(v) and k not in LANG_NAMES:
                    errs.append("ui/i18n_extra.json %r: the English %r still contains Thai" % (k, v))
            keys.update(k for k in extra if isinstance(k, str))
        except ValueError as e:
            errs.append("ui/i18n_extra.json: not valid JSON: %s" % e)
        sources.append("ui/i18n_extra.json")
    for gd in ("ui/i18n.gd", "scripts/i18n.gd"):
        found = en_dict_literals(os.path.join(root, gd))
        if found:
            keys.update(found)
            sources.append(gd + " EN")
    return keys, errs, sources


PLACEHOLDER = re.compile(r"\{[A-Za-z_0-9]*\}|%[-+ 0#]*\d*(?:\.\d+)?[sdifxXc%]")


def untranslated(s, keys_by_len):
    """What Thai is left after the page's longest-key-first fragment matching (BT_I18N.tr)."""
    if s in keys_by_len:
        return ""                                  # the whole literal is a key (placeholders and all)
    s = PLACEHOLDER.sub(" ", s)
    for k in keys_by_len:
        if k in s:
            s = s.replace(k, " ")
    return "".join(THAI.findall(s))


def check_ui_i18n(root, validator=None):
    errs, notes = [], []
    keys, errs, sources = ui_dictionary(root, validator)
    keys_by_len = sorted((k for k in keys if k), key=len, reverse=True)
    n_lit, scanned = 0, []
    for folder in ("ui", "app"):
        base = os.path.join(root, folder)
        if not os.path.isdir(base):
            continue
        for dp, dns, fns in os.walk(base):
            dns.sort()
            for fn in sorted(fns):
                if not fn.endswith((".gd", ".tscn")):
                    continue
                p = os.path.join(dp, fn)
                scanned.append(rel(p, root))
                for line, lit in string_literals(read_text(p)):
                    if not THAI.search(lit):
                        continue
                    n_lit += 1
                    left = untranslated(lit, keys_by_len)
                    if left:
                        errs.append("%s:%d: Thai %r has no English entry (ui/i18n_extra.json); untranslated: %r" %
                                    (rel(p, root), line, lit if len(lit) < 60 else lit[:57] + "...", left))
    if not scanned:
        notes.append("no ui/ or app/ folder yet: nothing to scan")
    else:
        notes.append("%d Thai literals in %d files, dictionary from %s" % (n_lit, len(scanned), ", ".join(sources) or "nothing"))
    return errs, notes


# ----------------------------------------------------------------------------------------------- 4. types.json append-only
def check_order(data_dir, base):
    errs, notes = [], []
    cur_path = os.path.join(data_dir, "types.json")
    if not os.path.exists(cur_path):
        return errs, ["no types.json"]
    cur_text = read_text(cur_path)
    cur = [t["k"] for t in json.loads(cur_text)]
    relpath = "godot/data/types.json"
    if git(["rev-parse", "--is-inside-work-tree"]) is None:
        return errs, ["not in git: order check skipped"]
    pairs = []
    if base:
        pairs.append((base, "working tree"))
    else:
        head = git_show("HEAD", relpath)
        if head is None:
            return errs, ["types.json is not in HEAD yet: order check skipped"]
        if head == cur_text:
            pairs.append(("HEAD~1", "HEAD"))
        else:
            pairs.append(("HEAD", "working tree"))
    for old_rev, new_name in pairs:
        old_text = git_show(old_rev, relpath)
        if old_text is None:
            notes.append("%s has no types.json: skipped" % old_rev)
            continue
        old = [t["k"] for t in json.loads(old_text)]
        new = cur if new_name == "working tree" else [t["k"] for t in json.loads(git_show("HEAD", relpath))]
        if new[:len(old)] != old:
            bad = next((i for i in range(min(len(old), len(new))) if old[i] != new[i]), min(len(old), len(new)))
            errs.append("types.json order changed at index %d (%s had %r, %s has %r): the array order is the "
                        "army-list protocol; append only, never insert, reorder or delete" %
                        (bad, old_rev, old[bad] if bad < len(old) else None, new_name, new[bad] if bad < len(new) else None))
        else:
            notes.append("%s -> %s: %d units, %d appended" % (old_rev, new_name, len(new), len(new) - len(old)))
    return errs, notes


# ----------------------------------------------------------------------------------------------- 5. dice per roll
def dice_worst_case(types):
    """Per datasheet and weapon, the most dice one stage can need:
    hit roll = models x (a + rf + ca[melee] + bl bonus), where the blast bonus is +1 per 5 models of the largest squad
    in the table (floor(max n / 5)); the wound roll gets at most twice the hits when sustained (su) or the fallen
    knights' pact (fac cx, melee: a 6 to hit is an extra hit) applies, and the save roll never exceeds the wound roll.
    Returns (dice, key, slot, detail) rows and a list of non-integer dice fields."""
    rows, bad = [], []
    max_n = max((t.get("n", 1) for t in types if isinstance(t.get("n"), int)), default=1)
    blast = max_n // 5
    for t in types:
        n = t.get("n")
        if not isinstance(n, int) or isinstance(n, bool):
            bad.append("%s: n=%r is not an integer" % (t.get("k"), n))
            continue
        for slot in ("gun", "mel"):
            w = t.get(slot)
            if not isinstance(w, dict):
                continue
            parts = [w.get("a", 0), w.get("rf", 0)]
            if any(not isinstance(x, int) or isinstance(x, bool) for x in parts):
                bad.append("%s %s: a=%r rf=%r must be integers (dice counts)" % (t.get("k"), slot, w.get("a"), w.get("rf")))
                continue
            per = w.get("a", 0) + w.get("rf", 0) + (1 if slot == "mel" and t.get("ca") else 0) + (blast if w.get("bl") else 0)
            hit = n * per
            mult = 2 if (w.get("su") or (slot == "mel" and t.get("fac") == "cx")) else 1
            rows.append((hit * mult, t.get("k"), slot, "%d models x %d attacks = %d hit dice%s" %
                         (n, per, hit, " x2 extra hits (wound roll)" if mult == 2 else "")))
    rows.sort(key=lambda r: (-r[0], r[1], r[2]))
    return rows, bad


def check_dice(types, cap):
    rows, bad = dice_worst_case(types)
    errs = list(bad)
    for dice, k, slot, detail in rows:
        if dice > cap:
            errs.append("%s %s: up to %d dice in one roll (%s) > cap %d" % (k, slot, dice, detail, cap))
    note = "worst %d dice: %s %s (%s)" % (rows[0][0], rows[0][1], rows[0][2], rows[0][3]) if rows else "no datasheets"
    return errs, [note]


# ----------------------------------------------------------------------------------------------- 6. secrets
SECRET_PATTERNS = [
    ("private key block", re.compile(r"-----BEGIN [A-Z ]*PRIVATE KEY-----")),
    ("GitHub token", re.compile(r"\b(?:ghp|gho|ghu|ghs|ghr)_[A-Za-z0-9]{36,}\b|\bgithub_pat_[A-Za-z0-9_]{22,}\b")),
    ("AWS key id", re.compile(r"\bAKIA[0-9A-Z]{16}\b")),
    ("Google API key", re.compile(r"\bAIza[0-9A-Za-z_\-]{35}\b")),
    ("Slack token", re.compile(r"\bxox[baprs]-[0-9A-Za-z\-]{10,}\b")),
    ("API secret key", re.compile(r"\bsk-(?:ant-)?[A-Za-z0-9_\-]{24,}\b")),
    ("JWT", re.compile(r"\beyJ[A-Za-z0-9_\-]{10,}\.eyJ[A-Za-z0-9_\-]{10,}\.[A-Za-z0-9_\-]{10,}\b")),
    ("assigned secret", re.compile(r"(?i)\b(?:api[_-]?key|api[_-]?token|secret[_-]?key|access[_-]?token|auth[_-]?token|"
                                   r"cloudflare[_-]?api[_-]?token|keystore[_-]?password|store[_-]?pass)\b\s*[=:]\s*[\"']?[A-Za-z0-9_\-/+=]{16,}")),
]
KEYSTORE_FIELDS = re.compile(r'^(keystore/(?:debug|release)(?:_user|_password)?)=\"(.+)\"', re.M)
SECRET_FILE_EXT = {".jks", ".keystore", ".p12", ".pfx", ".pem", ".key", ".kdbx"}


def check_secrets(root):
    errs, n = [], 0
    for dp, dns, fns in os.walk(root):
        dns[:] = sorted(d for d in dns if d not in SKIP_DIRS and rel(os.path.join(dp, d), root) not in SKIP_PATHS)
        for fn in sorted(fns):
            if os.path.splitext(fn)[1].lower() in SECRET_FILE_EXT:
                errs.append("%s: key or keystore files never enter the repo (AGENTS.md rule 2)" % rel(os.path.join(dp, fn), root))
    for relpath, p in iter_text_files(root):
        n += 1
        text = read_text(p)
        for label, rx in SECRET_PATTERNS:
            m = rx.search(text)
            if m:
                errs.append("%s:%d: looks like a %s (%s...)" % (relpath, text.count("\n", 0, m.start()) + 1, label, m.group(0)[:12]))
        if relpath.endswith("export_presets.cfg"):
            for m in KEYSTORE_FIELDS.finditer(text):
                errs.append("%s: %s must stay empty; release signing comes from GODOT_ANDROID_KEYSTORE_RELEASE_* env vars" %
                            (relpath, m.group(1)))
    return errs, n


# ----------------------------------------------------------------------------------------------- 7. version.json
def data_hash(data_dir):
    h = hashlib.sha256()
    for f in sorted(os.listdir(data_dir)):
        if f.endswith(".json") and f != "version.json":
            with open(os.path.join(data_dir, f), "rb") as fh:
                h.update(fh.read())
    return h.hexdigest()


def version_gd_hash(root):
    p = os.path.join(root, "core", "version.gd")
    if not os.path.exists(p):
        return None, None
    m = re.search(r'DATA_HASH\s*(?::\s*String)?\s*:?=\s*"([0-9a-f]*)"', read_text(p))
    return p, (m.group(1) if m else None)


def write_version(root):
    data_dir = os.path.join(root, "data")
    c = read_json(os.path.join(data_dir, "constants.json"))
    v = {"rules_ver": NEW_RULES_VER, "page_app_ver": c["APP_VER"], "page_rules_v": c["RULES_V"],
         "data_hash": data_hash(data_dir), "generated_by": "tools/export_data.js"}
    with open(os.path.join(data_dir, "version.json"), "w", encoding="utf-8") as f:
        json.dump(v, f, indent=2)
        f.write("\n")
    p, old = version_gd_hash(root)
    if p and old is not None and old != v["data_hash"]:
        src = read_text(p)
        src = re.sub(r'(DATA_HASH\s*(?::\s*String)?\s*:?=\s*")[0-9a-f]*(")', r"\g<1>%s\g<2>" % v["data_hash"], src, count=1)
        with open(p, "w", encoding="utf-8") as f:
            f.write(src)
    return v


def check_version(root):
    errs, notes = [], []
    data_dir = os.path.join(root, "data")
    p = os.path.join(data_dir, "version.json")
    if not os.path.exists(p):
        return ["data/version.json is missing: run validate_data.py --write-version"], notes
    v = read_json(p)
    h = data_hash(data_dir)
    if v.get("data_hash") != h:
        errs.append("data/version.json data_hash is stale: run validate_data.py --write-version (and commit it)")
    c = read_json(os.path.join(data_dir, "constants.json"))
    if v.get("page_app_ver") != c.get("APP_VER") or v.get("page_rules_v") != c.get("RULES_V"):
        errs.append("data/version.json page_app_ver/page_rules_v differ from constants.json: run --write-version")
    if v.get("rules_ver") != NEW_RULES_VER:
        errs.append("data/version.json rules_ver %s != %d" % (v.get("rules_ver"), NEW_RULES_VER))
    gd, gd_hash = version_gd_hash(root)
    if gd:
        if gd_hash is None:
            notes.append("core/version.gd has no DATA_HASH constant yet")
        elif gd_hash != h:
            errs.append("core/version.gd DATA_HASH differs from the data: run validate_data.py --write-version")
        else:
            notes.append("core/version.gd DATA_HASH agrees")
        m = re.search(r"RULES_V\s*(?::\s*int)?\s*:?=\s*(\d+)", read_text(gd))
        if m and int(m.group(1)) != NEW_RULES_VER:
            errs.append("core/version.gd RULES_V %s != %d" % (m.group(1), NEW_RULES_VER))
    notes.append("hash %s..., page %s rules %s" % (h[:12], v.get("page_app_ver"), v.get("page_rules_v")))
    return errs, notes


# ----------------------------------------------------------------------------------------------- 8. fixtures
def materialise_rot13(src_dir, dst_dir):
    """Copy a fixture tree, decoding *.rot13 files so the planted word exists only in a temporary folder."""
    for dp, dns, fns in os.walk(src_dir):
        for fn in fns:
            p = os.path.join(dp, fn)
            out = os.path.join(dst_dir, os.path.relpath(dp, src_dir))
            os.makedirs(out, exist_ok=True)
            text = read_text(p)
            if fn.endswith(".rot13"):
                fn, text = fn[:-6], codecs.decode(text, "rot13")
            with open(os.path.join(out, fn), "w", encoding="utf-8") as f:
                f.write(text)


def run_fixtures(validator, cap):
    results = []                                   # (name, ok, message)

    def expect(name, errs, should_fail):
        ok = bool(errs) if should_fail else not errs
        if should_fail:
            first = re.sub(r"'[^']*'", "'…'", errs[0]) if errs else ""   # never echo the planted word itself
            msg = "fails as planted (%d: %s)" % (len(errs), first[:110]) if errs else "did NOT fail"
        else:
            msg = "passes" if not errs else "FAILS: " + errs[0][:140]
        results.append((name, ok, msg))

    if not os.path.isdir(FIXTURES):
        return [("fixtures", False, "missing folder " + FIXTURES)]
    # a planted banned word (stored ROT13; decoded into a temp folder, then scanned like godot/)
    with tempfile.TemporaryDirectory() as tmp:
        materialise_rot13(os.path.join(FIXTURES, "fail_banned_name"), tmp)
        errs, _ = check_names(tmp, load_legacy())
        expect("fail_banned_name", errs, True)
    # a float dice value in a datasheet
    p = os.path.join(FIXTURES, "fail_float_dice", "data", "types.json")
    types = read_json(p)
    errs = validator.validate(types, FILE_SCHEMAS["types.json"], "tables.json")
    expect("fail_float_dice (schema)", errs, True)
    errs, _ = check_dice(types, cap)
    expect("fail_float_dice (dice)", errs, True)
    # a Thai UI string with no English entry
    errs, _ = check_ui_i18n(os.path.join(FIXTURES, "fail_i18n_missing"), validator)
    expect("fail_i18n_missing", errs, True)
    # a planted private-key header (stored ROT13 as well)
    with tempfile.TemporaryDirectory() as tmp:
        materialise_rot13(os.path.join(FIXTURES, "fail_secret"), tmp)
        errs, _ = check_secrets(tmp)
        expect("fail_secret", errs, True)
    # good samples
    ok_dir = os.path.join(FIXTURES, "ok")
    expect("ok map_layout_sample", validator.validate(read_json(os.path.join(ok_dir, "data", "map_layout_sample.json")), "map_layout.json"), False)
    expect("ok monster_sample", validator.validate(read_json(os.path.join(ok_dir, "data", "monster_sample.json")), "monster.json"), False)
    errs, _ = check_ui_i18n(ok_dir, validator)
    expect("ok ui i18n", errs, False)
    errs, _ = check_names(ok_dir, load_legacy())
    expect("ok names", errs, False)
    # the server data generator against the fake worker (imported in place; no __pycache__ in the repo)
    sys.dont_write_bytecode = True
    sys.path.insert(0, HERE)
    try:
        import gen_bt_data
        errs = gen_bt_data.self_test()
    except Exception as e:                         # noqa: BLE001 - any failure of the import is a fixture failure
        errs = ["gen_bt_data self-test crashed: %r" % e]
    expect("gen_bt_data fake worker", errs, False)
    return results


# ----------------------------------------------------------------------------------------------- main
def report(name, errs, notes=(), show=25):
    note = "; ".join(notes)
    if errs:
        print("FAIL %-9s %d problem%s%s" % (name, len(errs), "" if len(errs) == 1 else "s", (" (" + note + ")") if note else ""))
        for e in errs[:show]:
            print("     " + e)
        if len(errs) > show:
            print("     ... %d more" % (len(errs) - show))
        return False
    print("ok   %-9s %s" % (name, note))
    return True


def main(argv=None):
    ap = argparse.ArgumentParser(description="data lint for godot/ (see the module docstring)")
    ap.add_argument("--fixtures", action="store_true", help="run only the planted fixtures")
    ap.add_argument("--write-version", action="store_true", help="rewrite data/version.json from the data")
    ap.add_argument("--write-legacy", action="store_true", help="rewrite data/schema/legacy_tokens.sha1 (dedicated PR only)")
    ap.add_argument("--base", default=None, help="git revision to compare types.json order against")
    ap.add_argument("--root", default=GODOT, help="the godot/ folder to lint (default: this repository's)")
    ap.add_argument("--dice-cap", type=int, default=DICE_CAP)
    a = ap.parse_args(argv)
    root = os.path.abspath(a.root)
    t0 = time.time()
    validator = Validator()
    if a.write_legacy:
        print("legacy baseline: %d tokens -> %s" % (write_legacy(a.base or "HEAD"), rel(LEGACY_FILE, REPO)))
    if a.write_version:
        v = write_version(root)
        print("wrote data/version.json: %s" % json.dumps(v))
    all_ok = True
    if not a.fixtures:
        data_dir = os.path.join(root, "data")
        errs, notes, d = check_schema(data_dir, validator)
        all_ok &= report("schema", errs, notes)
        errs, n = check_names(root, load_legacy())
        all_ok &= report("names", errs, ["%d files scanned" % n])
        errs, notes = check_ui_i18n(root, validator)
        all_ok &= report("i18n", errs, notes)
        if root == GODOT:
            errs, notes = check_order(data_dir, a.base)
            all_ok &= report("order", errs, notes)
        errs, notes = check_dice(d.get("types.json", []), a.dice_cap)
        all_ok &= report("dice", errs, notes)
        errs, n = check_secrets(root)
        all_ok &= report("secrets", errs, ["%d files scanned" % n])
        errs, notes = check_version(root)
        all_ok &= report("version", errs, notes)
    results = run_fixtures(validator, a.dice_cap)
    bad = [r for r in results if not r[1]]
    for name, ok, msg in results:
        print("     %s %s: %s" % ("ok  " if ok else "FAIL", name, msg))
    all_ok &= report("fixtures", ["%s: %s" % (n, m) for n, ok, m in bad], ["%d checks" % len(results)])
    print("%s in %.1f s" % ("PASS" if all_ok else "FAIL", time.time() - t0))
    return 0 if all_ok else 1


if __name__ == "__main__":
    sys.exit(main())
