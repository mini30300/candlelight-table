# ชุดท่าของทหารเอง (S = 1): ประกอบคลิปทั้งหมดจาก gait.py + actions.py ตรวจเกต แล้วเขียน JSON แบบ CLIPS.md §2
# (godot/tools/bake_anim.gd อ่านได้ตรง ๆ -> res://assets/figures/soldier/clips.res ; ร่างทั้ง 5 เล่นด้วย motion_scale = S)
#   /usr/bin/python3 clips_soldier.py [--out soldier_clips.json] [--report report.json] [--no-gates]
#   (--out ค่าเริ่มอยู่นอก repo: <tmp>/soldier_clips/soldier_clips.json)
# เกต: เท้าที่แตะพื้นไถล <= 15 มม. ที่ความเร็วของเกมทุกร่าง (ช้าลง 10 % ต้องไถล > 45 มม.) ; วนรอบไม่สะดุด ;
# ช่วงข้อตาม rig.LIMITS ; ข้อมือ <= 45.5° ; แขนไม่ทะลุลำตัว ; เท้าไม่ทะลุกัน ; เวลาโดน/ยิง/บรรจุตรงเกม ; ล้มมีตุ้บ ;
# ล้มของ min <= 9 เฟรมจบนิ่ง ; ล้มไม่เด้งขึ้นก่อน/หลังตุ้บ แขนขาวางพื้นหลังตุ้บ ; หมัด/ฟันโดนเป้าข้างหน้า จบท่าหันตรง ;
# เล็งปืนแนบไหล่ (มือขวานิ้วชี้หน้า ข้อมือใกล้ระดับตา) ; ไฟล์ <= 1 MB (ขนาดจริงของ .res ตรวจใน bake_clips.sh)
import argparse
import json
import os
import sys
import tempfile
import numpy as np
import rig
import gait as GA
import actions as AC
from gait import FPS, J, OFF

HERE = os.path.dirname(os.path.abspath(__file__))
VERSION = "soldier clips 0.14"
# ร่างทั้ง 5 (motion_scale) และความเร็วที่เกมใช้จริง (ม./วิ ในโลก ; ArenaData.PLAYER walk 3 / run 5 ;
# ดาดฟ้าวันนี้ = ท่า walk เดิมของ humanoid 1.150 × S × DECK_RATE 1.4 ; หมุนตัว A/D 150°/วิ arena_player TURN_RATE)
BODIES = {"soldier": 1.1125, "soldier_f1": 1.0, "soldier_f2": 1.08125, "soldier_m2": 1.1625, "soldier_m3": 1.0625}
ARENA_JOG = 3.0
ARENA_RUN = 5.0
DECK_WALK_RIG = 1.150 * 1.4          # ม./วิ ของโครง (คูณ S = ม./วิ ในโลก) : ความเร็วเดินบนดาดฟ้าวันนี้ ไม่เปลี่ยน
DECK_RUN_RIG = 2.867647 * 1.4
SLIDE_MM = 15.0
WRIST_MAX = 45.5
LIMIT_TOL = 0.5
UPPER_BONES = ["chest", "neck", "head", "shoulderL", "elbowL", "wristL", "handL", "shoulderR", "elbowR", "wristR", "handR"]
LOCO = ["idle", "walk", "jog", "run", "turn_l", "turn_r"]


def build_all():
    clips = {}
    clips["idle"] = GA.build_idle()
    for g in ("walk", "jog", "run"):
        clips[g] = GA.build_gait(g)
    clips["turn_l"] = GA.build_turn(1.0)
    clips["turn_r"] = GA.build_turn(-1.0)
    clips["aim"] = AC.clip_aim()
    clips["fire"] = AC.clip_fire()
    clips["reload"] = AC.clip_reload()
    for i in range(3):
        clips["punch_%d" % i] = AC.clip_punch(i)
        clips["swing_%d" % i] = AC.clip_swing(i)
    for s in ("front", "back", "left", "right"):
        clips["hit_" + s] = AC.clip_hit(s)
    clips["hit_heavy"] = AC.clip_hit_heavy()
    falls = {}
    for k in ("back", "fwd", "spin", "knees"):
        c, d, lies = AC.clip_die(k)
        clips["die_" + k] = c
        falls["die_" + k] = (d, lies)
    for k in ("back", "fwd"):
        c, d, lies = AC.clip_die_min(k)
        clips["die_min_" + k] = c
        falls["die_min_" + k] = (d, lies)
    return clips, falls


# ---------------- ข้อมูลกำกับ (CLIPS.md §2) ----------------
KIND = {"idle": "idle", "walk": "walk", "jog": "jog", "run": "run", "turn_l": "turn", "turn_r": "turn", "aim": "aim",
        "fire": "fire", "reload": "reload", "hit_heavy": "hit_heavy"}
NOTES = {
    "idle": "standing at ease, 6 s loop: two breaths, one weight shift left-right, slow head look (seeded); feet flat",
    "walk": "walk in place, feet first (heel, flat, ball), pelvis lowered so each leg reaches <= 0.985",
    "jog": "light jog in place at the arena's 3 m/s on the base body (rate 1), heel landing",
    "run": "run in place at the arena's 5 m/s (Shift) on the base body (rate 1), landing on the ball of the foot",
    "turn_l": "stepping turn on the spot: the node turns left at `turn` radians per cycle while it loops; planted feet "
              "stay put in the world (they counter-rotate in the figure)",
    "turn_r": "stepping turn on the spot to the right (mirror of turn_l)",
    "aim": "rifle at the shoulder (no gun model yet): right hand at the grip, fingers forward, elbow out; left hand "
           "under the handguard; both wrists within 20 cm of eye height",
    "fire": "one shot from the aim pose: frame 0 = aim, the shot leaves at 0.02 s, kick back and settle by 0.167 s",
    "reload": "magazine change from the aim pose and back in 1.6 s (ArenaData gun reload): mag out, belt pouch at the "
              "front of the left hip, mag in",
    "punch_0": "right straight punch from a guard, weight forward, rear heel turning; the fist lands straight ahead at "
               "0.12 s (ArenaData punch active)",
    "punch_1": "left jab from a guard; lands at 0.12 s",
    "punch_2": "right hook, elbow raised; lands at 0.12 s",
    "swing_0": "one-handed blade, right to left; the cut lands at 0.18 s (ArenaData sword active)",
    "swing_1": "one-handed blade, high to low; lands at 0.18 s",
    "swing_2": "one-handed blade thrust; lands at 0.18 s",
    "hit_front": "light hit from the front: the body snaps back, feet stay", "hit_back": "light hit from behind",
    "hit_left": "light hit from the figure's left (+X): leans right, the left shoulder twists back",
    "hit_right": "light hit from the figure's right (-X): mirror of hit_left",
    "hit_heavy": "heavy hit from the front: staggers a step back with the right foot and steps in again",
    "die_back": "knees buckle, sits back and falls on its back (thud), arms and legs settle on the floor, lies still",
    "die_fwd": "knees fold, tips forward and falls on its face (thud), the lower legs drop to the floor",
    "die_spin": "spins round, crouches and falls on its right side (thud)",
    "die_knees": "sinks to its knees, sways, falls forward (thud)",
    "die_min_back": "min level: rigid fall on the back in 9 frames, still from frame 6",
    "die_min_fwd": "min level: rigid fall on the face in 9 frames, still from frame 6",
}


def kind_of(name):
    if name in KIND:
        return KIND[name]
    for p in ("punch", "swing", "die_min", "die", "hit"):
        if name.startswith(p + "_"):
            return p
    return name


def drives_of(c):
    out = []
    for b in J:
        q = np.array(c["q"][b])
        if np.max(np.abs(q - np.array([0, 0, 0, 1.0]))) > 1e-5 or b == "pelvis":
            out.append(b)
    return out


def finish(name, c, falls):
    """ทำ quaternion ให้ต่อเนื่อง (ครึ่งทรงกลมเดียวกัน) ปัดเลข แล้วเติมข้อมูลกำกับ"""
    n = c["frames"]
    q = {}
    for b in J:
        arr = np.array([rig.qnorm(v) for v in c["q"][b]])
        for k in range(1, n):
            if np.dot(arr[k], arr[k - 1]) < 0:
                arr[k] = -arr[k]
        q[b] = [[round(float(x), 6) for x in v] for v in arr]
    t = {b: [[round(float(x), 6) for x in v] for v in vs] for b, vs in c["t"].items()}
    kind = kind_of(name)
    out = {"loop": bool(c["loop"]), "fps": FPS, "frames": n, "length": round(float(c["length"]), 6), "q": q, "t": t,
           "speed": round(float(c.get("speed", 0.0)), 6), "set": "soldier", "kind": kind, "base": "bare",
           "holds": "all" if name in LOCO else "undriven", "note": NOTES.get(name, ""), "drives": drives_of(c),
           "contact": {"L": c["contact"]["L"], "R": c["contact"]["R"]}}
    if "turn" in c:
        out["turn"] = round(c["turn"], 6)
    if "events" in c:
        out["events"] = c["events"]
    if name in ("aim", "fire", "reload"):
        out["gun"] = "rifle"
        out["drives"] = [b for b in out["drives"] if b in UPPER_BONES]
    if kind in ("punch", "swing"):
        out["hand"] = "L" if name == "punch_1" else "R"
    if kind == "hit":
        out["from"] = name[4:]
    if name == "hit_heavy":
        out["from"] = "front"
        out["heavy"] = True
    if name in falls:
        d, lies = falls[name]
        th = AC.thud_time(c)
        out.setdefault("events", []).append({"t": th, "kind": "thud"})
        if name == "die_knees":
            out["events"].insert(0, {"t": 0.46, "kind": "knees"})
        out["alpha"] = [1.0] * n
        out["from"] = {"back": "front", "fwd": "back", "side": "side", "knees": "any"}[d]
        out["note"] += "; lies on its %s" % lies
    return out


# ---------------- การประมาณค่าแบบ Godot (slerp ระหว่างคีย์ วนรอบข้ามคีย์สุดท้าย->แรก) ----------------

def interp(clip, tc):
    n = clip["frames"]
    loop = clip["loop"]
    x = tc * FPS
    k0 = int(np.floor(x + 1e-9))
    f = x - k0
    if loop:
        k0 %= n
        k1 = (k0 + 1) % n
    else:
        k0 = min(max(k0, 0), n - 1)
        k1 = min(k0 + 1, n - 1)
        if k0 == n - 1:
            f = 0.0
    L = {b: rig.qslerp(np.array(clip["q"][b][k0]), np.array(clip["q"][b][k1]), f) for b in J}
    tp = {}
    for b, vs in clip["t"].items():
        a, c = np.array(vs[k0]), np.array(vs[k1])
        tp[b] = a + (c - a) * f
    return L, tp


def planted(clip, side, point, tc):
    c = clip["contact"]["L" if side == "L" else "R"]
    n = len(c)
    k0 = int(np.floor(tc * FPS + 1e-6))
    k1 = k0 + 1
    if clip["loop"]:
        k0, k1 = k0 % n, k1 % n
    else:
        k0, k1 = min(max(k0, 0), n - 1), min(max(k1, 0), n - 1)
    want = ("heel", "flat") if point == "heel" else ("ball", "flat")
    return c[k0] in want and c[k1] in want


def slide(clip, rate=1.0, speed_k=1.0, rate_hz=240.0, cycles=3):
    """เท้าไถลบนพื้น (ม. ของโครง) ขณะแตะ: โหนดเดิน speed × t (หมุน turn/length × t) แบบ test_anim_footslide.gd"""
    loop = clip["loop"]
    span = clip["length"] * (cycles if loop else 1)
    dt = rate / rate_hz
    n = int(np.ceil(span / dt))
    v = clip.get("speed", 0.0) * speed_k
    w = clip.get("turn", 0.0) / clip["length"] * speed_k if clip.get("turn") else 0.0
    anchor = {}
    worst, where, planted_s = 0.0, "", 0.0
    for i in range(n + 1):
        t = min(i * dt, span)
        tc = t % clip["length"] if loop else t
        need = [(s, p) for s in "LR" for p in ("heel", "toe") if planted(clip, s, "heel" if p == "heel" else "ball", tc)]
        for s in "LR":
            for p in ("heel", "toe"):
                if (s, p) not in need:
                    anchor.pop(s + p, None)
        if not need:
            continue
        L, tp = interp(clip, tc)
        G = GA.fk(L, tp["pelvis"], {b: tp[b] for b in tp if b != "pelvis"})
        Rn = GA.Ry(w * t)
        for s, p in need:
            pt = Rn @ G[p + s][1] + np.array([0.0, 0.0, v * t])
            key = s + p
            if key not in anchor:
                anchor[key] = pt
                continue
            d = np.hypot(pt[0] - anchor[key][0], pt[2] - anchor[key][2])
            planted_s += dt / 4
            if d > worst:
                worst, where = d, "%s at %.3f s" % (key, tc)
    return worst, where, planted_s / max(span, 1e-9)


# ---------------- เกต ----------------
# ลำตัว (กรอบกระดูก, ม. ของโครง; วัดจากผิว lo ของร่างหลักท่าผูก: ส่วน torso ตัดบ่า/รักแร้ออก): (กระดูก, y ต่ำ, y สูง,
# กึ่งกว้าง, กึ่งลึก, ศูนย์ z)
TORSO_E = [("pelvis", -0.15, 0.17, 0.145, 0.105, -0.015), ("spine", 0.0, 0.25, 0.145, 0.10, 0.0),
           ("chest", -0.14, 0.05, 0.15, 0.105, 0.0)]
LIMB_R = {"upper": 0.045, "fore": 0.037, "hand": 0.033}
OVERLAP = 0.02           # ผิวกดกันได้ไม่เกิน 2 ซม.


def torso_hits(G):
    """จุดบนแกนแขนที่จมเข้าลำตัวลึกเกิน OVERLAP: คืนความลึกที่มากสุด (ม.) และที่"""
    worst, where = 0.0, ""
    for s in "LR":
        segs = [("upper", G["shoulder" + s][1], G["elbow" + s][1], 0.4),
                ("fore", G["elbow" + s][1], G["wrist" + s][1], 0.0),
                ("hand", G["wrist" + s][1], G["hand" + s][1] + G["hand" + s][0] @ np.array([0, -0.06, 0]), 0.0)]
        for nm, a, b, u0 in segs:
            r = LIMB_R[nm]
            for u in np.linspace(u0, 1.0, 6):
                p = a + (b - a) * u
                for bone, y0, y1, ha, hb, cz in TORSO_E:
                    R, o = G[bone]
                    lp = R.T @ (p - o)
                    if not (y0 <= lp[1] <= y1):
                        continue
                    ea, eb = ha + r - OVERLAP, hb + r - OVERLAP
                    rho = np.hypot(lp[0] / ea, (lp[2] - cz) / eb)
                    if rho < 1.0:
                        dep = (1.0 - rho) * min(ea, eb)
                        if dep > worst:
                            worst, where = dep, "%s %s in %s" % (nm, s, bone)
    return worst, where


def seg_dist(p0, p1, q0, q1):
    d1, d2, r = p1 - p0, q1 - q0, p0 - q0
    a, e, f = d1 @ d1, d2 @ d2, d2 @ r
    c, b = d1 @ r, d1 @ d2
    den = a * e - b * b
    s = np.clip((b * f - c * e) / den, 0, 1) if den > 1e-12 else 0.0
    t = np.clip((b * s + f) / e, 0, 1)
    s = np.clip((b * t - c) / a, 0, 1)
    return np.linalg.norm(p0 + d1 * s - q0 - d2 * t)


def legs_apart(G):
    """ระยะใกล้สุดระหว่างหน้าแข้ง/เท้าซ้าย-ขวา (ม.)"""
    best = 9.0
    for a0, a1 in (("kneeL", "ankleL"), ("ankleL", "toeL")):
        for b0, b1 in (("kneeR", "ankleR"), ("ankleR", "toeR")):
            best = min(best, seg_dist(G[a0][1], G[a1][1], G[b0][1], G[b1][1]))
    return best


# ท่าล้ม: แขนขาวางพื้นหลังตุ้บ (จุด, ตำแหน่งในกรอบกระดูก, รัศมีแขนขา, เพดาน ม.) ; นิ้วเท้าเฉพาะท่าคว่ำ (หงายปลายเท้าชี้ฟ้า)
REST_PTS = [("elbow", (0.0, 0.0, 0.0), 0.04, 0.04), ("hand", (0.0, -0.085, 0.0), 0.025, 0.04),
            ("knee", (0.0, 0.0, 0.0), 0.05, 0.05), ("ankle", (0.0, 0.0, 0.0), 0.04, 0.04)]
TOE_PT = ("toe", (0.0, 0.0, 0.0), 0.02, 0.04)
REST_AFTER = 0.25        # วิ หลังตุ้บ
REBOUND = 0.01           # แขนขา/เชิงกรานเด้งขึ้นได้ไม่เกิน (ม.)
PEL_RISE = 0.01          # ก่อนตุ้บ เชิงกรานขึ้นได้ไม่เกินต่อเฟรม
HEEL_STEP = 0.03         # ก่อนตุ้บ ส้นเท้าเปลี่ยนสูงได้ไม่เกินต่อเฟรม


def on_torso(G, p, r, tol=0.03):
    """จุดแขนขาพักอยู่บนลำตัว (ห่างผิวลำตัวไม่เกิน tol) — แขนบนของท่าตะแคงพาดหน้าอก"""
    for bone, y0, y1, ha, hb, cz in TORSO_E:
        R, o = G[bone]
        lp = R.T @ (p - o)
        if not (y0 - tol <= lp[1] <= y1 + tol):
            continue
        ea, eb = ha + r, hb + r
        if (np.hypot(lp[0] / ea, (lp[2] - cz) / eb) - 1.0) * min(ea, eb) <= tol:
            return True
    return False


def fall_checks(c, thud):
    """ท่าล้ม: ก่อนตุ้บเชิงกรานไม่เด้งขึ้น ส้นไม่กระตุก ; หลังตุ้บไม่เด้ง ; จาก ตุ้บ + 0.25 วิ แขนขาวางพื้น (หรือพักบนลำตัว)"""
    n = c["frames"]
    Gs = [GA.fk({b: np.array(c["q"][b][k]) for b in J}, np.array(c["t"]["pelvis"][k])) for k in range(n)]
    kt = int(round(thud * FPS))
    k0 = min(int(round((thud + REST_AFTER) * FPS)), n - 1)
    pel = np.array([G["pelvis"][1][1] for G in Gs])
    heel = np.array([[G["heel" + s][1][1] for s in "LR"] for G in Gs])
    rise = float(np.max(np.diff(pel[:kt + 1]))) if kt > 0 else 0.0
    # ส้นเท้าไม่กระตุกช่วงที่เท้ายังแตะพื้นและ 4 เฟรมส่งต่อให้ FK (ไม่นับช่วงร่างลอยล้ม)
    kp = max([k for k in range(n) if c["contact"]["L"][k] or c["contact"]["R"][k]], default=-1)
    kh = min(kt, kp + 4) if kp >= 0 else -1       # ท่าล้มของ min ไม่มีช่วงเท้าตรึง (ล้มแข็ง 6 เฟรม)
    hstep = float(np.max(np.abs(np.diff(heel[:kh + 1], axis=0)))) if kh > 0 else 0.0
    bounce = float(np.max(pel[kt:] - np.minimum.accumulate(pel[kt:])))
    face_down = (Gs[-1]["chest"][0] @ np.array([0.0, 0.0, 1.0]))[1] < -0.7
    pts = REST_PTS + ([TOE_PT] if face_down else [])
    worst, where, reb, reb_at, rest = -9.0, "", 0.0, "", []
    for s in "LR":
        for nm, off, r, cap in pts:
            hs = []
            for k in range(k0, n):
                R, p = Gs[k][nm + s]
                pt = p + R @ np.array(off)
                h = pt[1] - r
                hs.append(h)
                over = h - cap
                if over > 0 and on_torso(Gs[k], pt, r):
                    over = 0.0
                    if k == n - 1:
                        rest.append(nm + s)
                if over > worst:
                    worst, where = over, "%s%s frame %d (%.0f mm)" % (nm, s, k, h * 1000)
            hs = np.array(hs)
            d = float(np.max(hs - np.minimum.accumulate(hs)))
            if d > reb:
                reb, reb_at = d, nm + s
    return {"pelvis_rise_mm": round(rise * 1000, 1), "heel_step_mm": round(hstep * 1000, 1),
            "bounce_mm": round(bounce * 1000, 1), "limb_over_cap_mm": round(max(worst, 0.0) * 1000, 1), "where": where,
            "rebound_mm": round(reb * 1000, 1), "rebound_at": reb_at, "face_down": bool(face_down), "on_torso": rest}


def angle_deg(q0, q1):
    return float(np.degrees(2 * np.arccos(min(1.0, abs(float(np.dot(q0, q1)))))))


def import_limits():
    sys.path.insert(0, HERE)
    import limits_check
    return limits_check.angles


def gates(clips, raw):
    src = clips
    angles = import_limits()
    rep = {"slide": {}, "loops": {}, "limits": {}, "wrists": {}, "torso": {}, "legs": {}, "timing": {}, "rates": {},
           "fail": []}
    fail = rep["fail"]
    # 1. เท้าไถล ที่ความเร็วของเกม ทุกร่าง (สเกลเชิงเส้น: มม.โลก = S × มม.โครง ; อัตราเล่นเปลี่ยนแค่ความถี่การสุ่ม)
    game_rate = {"walk": lambda S: DECK_WALK_RIG / clips["walk"]["speed"], "jog": lambda S: ARENA_JOG / S / clips["jog"]["speed"],
                 "run": lambda S: ARENA_RUN / S / clips["run"]["speed"], "idle": lambda S: 1.0, "turn_l": lambda S: 1.0,
                 "turn_r": lambda S: 1.0}
    for name in [n for n in clips if clips[n]["frames"] > 1 and any(clips[n]["contact"]["L"] + clips[n]["contact"]["R"])]:
        rates = {body: (game_rate[name](S) if name in game_rate else 1.0) for body, S in BODIES.items()}
        # ไถลในหน่วยโครงไม่ขึ้นกับอัตราเล่น (ทางเดินเดิม) : สุ่มละเอียดสุด (อัตราต่ำสุด) ครั้งเดียว แล้วคูณ S ของแต่ละร่าง
        w, where, share = slide(clips[name], min(min(rates.values()), 1.0), cycles=1 if name == "idle" else 3)
        res = {body: {"mm": round(w * S * 1000, 2), "rate": round(rates[body], 4)} for body, S in BODIES.items()}
        worst = max(r["mm"] for r in res.values())
        rep["slide"][name] = {"worst_mm": worst, "where": where, "planted_share": round(share, 3), "bodies": res}
        if worst > SLIDE_MM:
            fail.append("slide %s %.1f mm" % (name, worst))
        if name in ("walk", "jog", "run") and share < (0.12 if name == "run" else 0.15):
            fail.append("%s: feet down too little" % name)
    for name in ("walk", "jog", "run"):
        w, _, _ = slide(clips[name], 1.0, speed_k=0.9)
        rep["slide"][name]["control_90pct_mm"] = round(w * min(BODIES.values()) * 1000, 1)
        if name != "jog" and w * min(BODIES.values()) * 1000 <= 3 * SLIDE_MM:
            fail.append("control %s slides only %.1f mm at 90 %% speed" % (name, w * 1000))
    # 2. วนรอบไม่สะดุด: ก้าวสุดท้าย->แรก ไม่เกินก้าวใหญ่สุดระหว่างคีย์
    for name, c in clips.items():
        if not c["loop"]:
            continue
        worst_seam, worst_step = 0.0, 0.0
        for b in J:
            qs = [np.array(v) for v in c["q"][b]]
            steps = [angle_deg(qs[k], qs[k + 1]) for k in range(len(qs) - 1)]
            worst_step = max(worst_step, max(steps) if steps else 0.0)
            worst_seam = max(worst_seam, angle_deg(qs[-1], qs[0]))
        ps = np.array(c["t"]["pelvis"])
        pstep = np.max(np.linalg.norm(np.diff(ps, axis=0), axis=1))
        pseam = np.linalg.norm(ps[-1] - ps[0])
        rep["loops"][name] = {"seam_deg": round(worst_seam, 3), "max_step_deg": round(worst_step, 3),
                              "pelvis_seam_mm": round(pseam * 1000, 2), "pelvis_max_step_mm": round(pstep * 1000, 2)}
        if worst_seam > worst_step * 1.05 + 0.01 or pseam > pstep * 1.05 + 1e-4:
            fail.append("loop seam %s" % name)
    # 3. ช่วงข้อ + ข้อมือ
    for name, c in clips.items():
        viol = {}
        wmax = 0.0
        for b in J:
            if b in ("pelvis", "heelL", "heelR"):
                continue
            for f, qv in enumerate(c["q"][b]):
                base, x, y, z = angles(b, np.array(qv))
                if base not in rig.LIMITS:
                    continue
                for ax, val in (("x", x), ("y", y), ("z", z)):
                    lo, hi = rig.LIMITS[base][ax]
                    over = max(lo - val, val - hi, 0.0)
                    if over > LIMIT_TOL and over > viol.get("%s.%s" % (b, ax), (0,))[0]:
                        viol["%s.%s" % (b, ax)] = (round(over, 2), f, round(val, 1))
        for s in "LR":
            for f in range(c["frames"]):
                qw = rig.qmul(np.array(c["q"]["wrist" + s][f]), np.array(c["q"]["hand" + s][f]))
                tw = rig.twist_y(qw)
                sw = rig.qmul(qw, rig.qinv(tw))
                wmax = max(wmax, angle_deg(tw, GA.I4), angle_deg(sw, GA.I4))
        rep["limits"][name] = {k: {"over_deg": v[0], "frame": v[1], "value": v[2]} for k, v in viol.items()}
        rep["wrists"][name] = round(wmax, 2)
        if viol:
            fail.append("limits %s: %s" % (name, ", ".join(sorted(viol))))
        if wmax > WRIST_MAX:
            fail.append("wrist %s %.1f deg" % (name, wmax))
    # 4. แขนทะลุลำตัว / เท้าทะลุกัน (ทุกเฟรมของท่าที่ยืน ; ท่าล้มดูถึงก่อนตุ้บ)
    for name, c in clips.items():
        deep, where, apart = 0.0, "", 9.0
        last = c["frames"]
        if name.startswith("die"):
            th = next((e["t"] for e in src[name].get("events", []) if e["kind"] == "thud"), None)
            last = int(round(th * FPS)) if th else last
        for f in range(last):
            L = {b: np.array(c["q"][b][f]) for b in J}
            G = GA.fk(L, np.array(c["t"]["pelvis"][f]))
            d, w = torso_hits(G)
            if d > deep:
                deep, where = d, "%s frame %d" % (w, f)
            apart = min(apart, legs_apart(G))
        rep["torso"][name] = {"deepest_mm": round(deep * 1000, 1), "where": where}
        rep["legs"][name] = round(apart * 1000, 1)
        if deep > 0.0:
            fail.append("arm in torso %s (%s, %.0f mm)" % (name, where, deep * 1000))
        if apart < 0.07 and not name.startswith("die"):
            fail.append("legs cross %s (%.0f mm)" % (name, apart * 1000))
    # 5. เวลาตามเกม
    tm = rep["timing"]
    for n_ in ("punch_0", "punch_1", "punch_2"):
        tm[n_] = {"shot": src[n_]["events"][0]["t"], "length": src[n_]["length"], "peak_frame_t": _peak_reach(clips[n_])}
        if abs(tm[n_]["shot"] - AC.PUNCH_T) > 0.02 or abs(tm[n_]["peak_frame_t"] - AC.PUNCH_T) > 0.02 + 1e-6 or src[n_]["length"] > 0.55:
            fail.append("timing %s" % n_)
    for n_ in ("swing_0", "swing_1", "swing_2"):
        tm[n_] = {"shot": src[n_]["events"][0]["t"], "length": src[n_]["length"]}
        if abs(tm[n_]["shot"] - AC.SWING_T) > 0.02 or src[n_]["length"] > 0.8:
            fail.append("timing %s" % n_)
    # ต่อย/ฟันโดนเป้าข้างหน้า (ปลายมือในกรอบหุ่นตอนโดน) และจบท่าเชิงกราน/อกหันเท่าท่ายืน (ไม่สะบัดตอนผสมกลับ)
    Gi = _fk_at(clips["idle"], 0.0)
    for n_, side, lim, near in (("punch_0", "R", 10.0, 0.60), ("punch_1", "L", 10.0, 0.60), ("punch_2", "R", 15.0, 0.35),
                                ("swing_1", "R", 15.0, 0.60), ("swing_2", "R", 10.0, 0.60)):
        t_hit = src[n_]["events"][0]["t"]
        tp_ = _tip(_fk_at(clips[n_], t_hit), side)
        bearing = float(np.degrees(np.arctan2(tp_[0], tp_[2])))
        tm[n_]["tip_at_shot"] = {"x": round(float(tp_[0]), 3), "y": round(float(tp_[1]), 3), "z": round(float(tp_[2]), 3),
                                 "bearing_deg": round(bearing, 1)}
        if abs(bearing) > lim or tp_[2] < near:
            fail.append("%s lands off target (bearing %.0f deg, %.2f m ahead)" % (n_, bearing, tp_[2]))
    xs = [(k / 240.0, _tip(_fk_at(clips["swing_0"], k / 240.0), "R")[0]) for k in range(int(0.4 * 240))]
    cross = [t for (t0, x0), (t, x1) in zip(xs, xs[1:]) if x0 < 0.0 <= x1 or x1 < 0.0 <= x0]
    tm["swing_0"]["crosses_centre"] = [round(t, 3) for t in cross]
    if not any(abs(t - AC.SWING_T) <= 0.02 for t in cross):
        fail.append("swing_0 does not cross the centre line at %.2f s (%s)" % (AC.SWING_T, cross))
    for n_ in [x for x in src if x.startswith(("punch", "swing"))]:
        Gl = _fk_at(clips[n_], src[n_]["length"])
        dy = [abs(_yaw(Gl[b][0]) - _yaw(Gi[b][0])) for b in ("pelvis", "chest")]
        tm[n_]["end_yaw_vs_idle"] = [round(v, 2) for v in dy]
        if max(dy) > 2.0:
            fail.append("%s ends turned (pelvis %.1f, chest %.1f deg from the idle)" % (n_, dy[0], dy[1]))
    # เล็งปืน: นิ้วมือขวาชี้ไปหน้า (แกนยาวของมือ z >= 0.5) ข้อมือทั้งสองต่ำกว่าตาไม่เกิน 20 ซม. (ปืนแนบไหล่ ไม่ใช่ถือต่ำ)
    Ga = _fk_at(clips["aim"], 0.0)
    eye = Ga["head"][1] + Ga["head"][0] @ np.array([0.0, 0.09, 0.08])
    long_z = float((Ga["handR"][0] @ np.array([0.0, -1.0, 0.0]))[2])
    below = [float(eye[1] - Ga["wrist" + s][1][1]) for s in "RL"]
    tm["aim"] = {"hand_long_z": round(long_z, 2), "wrists_below_eyes_cm": [round(v * 100, 1) for v in below]}
    if long_z < 0.5 or max(below) > 0.20:
        fail.append("aim: hand long axis z %.2f, wrists %.0f/%.0f cm below the eyes" % (long_z, below[0] * 100, below[1] * 100))
    tm["reload"] = src["reload"]["length"]
    if abs(src["reload"]["length"] - AC.RELOAD_T) > 1e-6:
        fail.append("reload length")
    tm["fire"] = {"length": src["fire"]["length"], "shot": src["fire"]["events"][0]["t"]}
    for n_ in [x for x in src if x.startswith("die")]:
        th = [e["t"] for e in src[n_].get("events", []) if e["kind"] == "thud"]
        Lf = {b: np.array(clips[n_]["q"][b][-1]) for b in J}
        Gf = GA.fk(Lf, np.array(clips[n_]["t"]["pelvis"][-1]))
        tm[n_ + "_end_heights_mm"] = {b: round(AC.lowest(Gf, (b,)) * 1000) for b in AC.SURF if not b.startswith(("heel", "toe", "ankle"))}
        tm[n_] = {"thud": th[0] if th else None, "length": src[n_]["length"], "frames": src[n_]["frames"],
                  "still_last_frames": _still_tail(clips[n_]), "lowest_mm": round(raw[n_]["info"]["lowest"] * 1000, 1)}
        if not th or th[0] is None:
            fail.append("no thud %s" % n_)
        if raw[n_]["info"]["lowest"] < -0.003:
            fail.append("%s goes under the ground" % n_)
        if n_.startswith("die_min") and (src[n_]["frames"] > 9 or _still_tail(clips[n_]) < 3):
            fail.append("min fall %s" % n_)
        if th and th[0] is not None:
            fc = fall_checks(clips[n_], th[0])
            tm[n_]["rest"] = fc
            if fc["pelvis_rise_mm"] > PEL_RISE * 1000 or fc["heel_step_mm"] > HEEL_STEP * 1000:
                fail.append("%s pops before the thud (pelvis +%.0f mm, heel %.0f mm per frame)" % (n_, fc["pelvis_rise_mm"], fc["heel_step_mm"]))
            if fc["bounce_mm"] > REBOUND * 1000 or fc["rebound_mm"] > REBOUND * 1000:
                fail.append("%s bounces after the thud (pelvis %.0f mm, %s %.0f mm)" % (n_, fc["bounce_mm"], fc["rebound_at"], fc["rebound_mm"]))
            if fc["limb_over_cap_mm"] > 0.0:
                fail.append("%s: a limb floats after the thud (%s)" % (n_, fc["where"]))
    # 6. จังหวะก้าว (ก้าว/นาที) ที่ความเร็วเกม
    for body, S in BODIES.items():
        rep["rates"][body] = {
            "jog_3ms": round(120.0 / clips["jog"]["length"] * ARENA_JOG / (S * clips["jog"]["speed"]), 1),
            "run_5ms": round(120.0 / clips["run"]["length"] * ARENA_RUN / (S * clips["run"]["speed"]), 1),
            "deck_walk": round(120.0 / clips["walk"]["length"] * DECK_WALK_RIG / clips["walk"]["speed"], 1),
            "deck_walk_ms": round(DECK_WALK_RIG * S, 3)}
        r = rep["rates"][body]
        if not (150 <= r["jog_3ms"] <= 210 and 150 <= r["run_5ms"] <= 210 and r["deck_walk"] <= 130):
            fail.append("step rate %s %s" % (body, r))
    return rep


def _fk_at(c, t):
    L, tp = interp(c, t)
    return GA.fk(L, tp["pelvis"], {b: tp[b] for b in tp if b != "pelvis"})


def _tip(G, side):
    """ปลายมือ (กำปั้น/ปลายนิ้ว) ในกรอบหุ่น"""
    R, p = G["hand" + side]
    return p + R @ np.array([0.0, -0.085, 0.0])


def _yaw(R):
    f = R @ np.array([0.0, 0.0, 1.0])
    return float(np.degrees(np.arctan2(f[0], f[2])))


def _peak_reach(c):
    """เวลาของเฟรมที่หมัดยื่นไกลสุด (ข้อมือที่ไกลจากไหล่มากสุด)"""
    ds = []
    for f in range(c["frames"]):
        L = {b: np.array(c["q"][b][f]) for b in J}
        G = GA.fk(L, np.array(c["t"]["pelvis"][f]))
        ds.append(max(np.linalg.norm(G["wrist" + s][1] - G["shoulder" + s][1]) for s in "LR"))
    m = max(ds)
    return round(next(f for f, d in enumerate(ds) if d >= m - 0.003) / FPS, 4)


def _still_tail(c):
    n = c["frames"]
    k = 0
    for f in range(n - 1, 0, -1):
        same = all(np.allclose(c["q"][b][f], c["q"][b][f - 1], atol=1e-9) for b in J) and \
            np.linalg.norm(np.array(c["t"]["pelvis"][f]) - np.array(c["t"]["pelvis"][f - 1])) < 1e-6
        if not same:
            break
        k += 1
    return k + 1


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default=os.path.join(tempfile.gettempdir(), "soldier_clips", "soldier_clips.json"))
    ap.add_argument("--report", default="")
    ap.add_argument("--no-gates", action="store_true")
    a = ap.parse_args()
    raw, falls = build_all()
    src = {n: finish(n, c, falls) for n, c in raw.items()}
    doc = {"format": 1, "fps": FPS, "source": VERSION, "generator": "tools/soldier/generator/src/py/clips_soldier.py",
           "units": "rig metres of the unscaled 1.6 m figure (play with Skeleton3D.motion_scale = S)",
           "axes": "+Y up, the figure faces +Z, its left is +X", "joints": J, "parents": [GA.PAR[b] for b in J],
           "offsets": [OFF[b].tolist() for b in J], "proofs": {}, "holds": {}, "clips": src}
    text = json.dumps(doc, separators=(",", ":"))
    os.makedirs(os.path.dirname(os.path.abspath(a.out)), exist_ok=True)
    rep = {"clips": len(src), "json_bytes": len(text), "frames": sum(c["frames"] for c in src.values()),
           "info": {n: {k: v for k, v in c.get("info", {}).items() if k not in ("torso_low", "lift")} for n, c in raw.items()}}
    if not a.no_gates:
        rep.update(gates(src, raw))
    open(a.out, "w").write(text)
    if a.report:
        json.dump(rep, open(a.report, "w"), indent=1, default=float)
    print("%d clips, %d frames, %.0f KB JSON -> %s" % (len(src), rep["frames"], len(text) / 1024, a.out))
    if not a.no_gates:
        for n, s in rep["slide"].items():
            print("slide %-12s worst %6.2f mm %s" % (n, s["worst_mm"], ("control %.0f mm" % s["control_90pct_mm"]) if "control_90pct_mm" in s else ""))
        print("rates", json.dumps(rep["rates"]))
        print("FAIL" if rep["fail"] else "PASS", "%d gate failures" % len(rep["fail"]))
        for f in rep["fail"]:
            print("  -", f)
        if rep["fail"]:
            sys.exit(1)


if __name__ == "__main__":
    main()
