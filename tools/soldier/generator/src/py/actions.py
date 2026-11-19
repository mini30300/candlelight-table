# ท่าที่ไม่ใช่การเดิน (เล็ง ยิง บรรจุ ต่อย ฟัน โดน ตาย): คีย์ท่าเป็นค่าตัวเลข (มุม/เป้ามือ/ตำแหน่ง) ที่เวลาต่าง ๆ
# ประมาณค่าระหว่างคีย์แบบนุ่ม แล้วสร้างท่าทุกเฟรมด้วย IK ของ gait.py (เท้าตรึงพื้น / มือตามเป้าในกรอบอก)
# เวลาสำคัญตรงกับเกม: หมัดโดน 0.12 วิ ฟันโดน 0.18 วิ (ArenaData active) บรรจุ 1.6 วิ (ArenaData reload)
import numpy as np
import rig
import gait as GA
from gait import FPS, J, OFF, I4, SIDES

# ---------------- ค่าท่าตั้งต้น ----------------
# pel = เลื่อนเชิงกราน (ม.) จากท่ายืน ; prot = (ก้ม x, หัน y, เอียง z) องศา ; sp/ch = สันหลัง/อก (x, y, z)
# look = หัว (ก้ม, หัน, เอียง) ในกรอบหุ่น (lookk = 1) หรือ nk/hd = มุมคอ/หัวตรง ๆ (lookk = 0)
# wL/wR = เป้าข้อมือในกรอบอก, pL/pR = ทิศศอก (armk = 1) หรือ shL/shR (x, y, z), elL/elR = มุมแขน (armk = 0) ;
# hL/hR = (พับ, เอียง) ข้อมือ
# fL/fR = เลื่อนเท้า (dx, dy, dz, หัน, ก้ม) จากท่ายืน (legk = 1: IK) หรือ hipL/R, kneeL/R, ankL/R = มุมขา (legk = 0)
# gnd = ไม่ให้ร่างลงใต้พื้น (ล้ม: ยกทั้งร่างแบบเรียบตามเวลา ไม่เด้ง) ; rest = วางร่างลงพื้นพอดี ; cL/cR = การแตะของเท้า
# ikf = {ข้าง: (dx, dy, dz, หัน, ก้ม)} คีย์ FK ที่มุมขามาจาก IK ตอนนั้น (เท้าที่ตำแหน่งนี้ เข่าชี้หน้าเชิงกราน) ; ไม่ส่งต่อคีย์ถัดไป
HANG_W = {"L": np.array([0.215, -0.535, 0.045]), "R": np.array([-0.215, -0.535, 0.045])}
BASE = {
    "pel": (0.0, 0.0, 0.0), "prot": (1.0, 0.0, 0.0), "sp": (2.0, 0.0, 0.0), "ch": (-0.5, 0.0, 0.0),
    "look": (2.0, 0.0, 0.0), "lookk": 1.0, "nk": (0.0, 0.0, 0.0), "hd": (0.0, 0.0, 0.0),
    "wL": tuple(HANG_W["L"]), "wR": tuple(HANG_W["R"]), "pL": (0.3, -0.2, -1.0), "pR": (-0.3, -0.2, -1.0),
    "hL": (-4.0, -4.0), "hR": (-4.0, -4.0), "armk": 1.0,
    "shL": (-3.0, -6.0, 6.0), "shR": (-3.0, -6.0, 6.0), "elL": 14.0, "elR": 14.0,
    "fL": (0.0, 0.0, 0.0, 0.0, 0.0), "fR": (0.0, 0.0, 0.0, 0.0, 0.0), "legk": 1.0,
    "hipL": (-10.0, 0.0, 4.0), "hipR": (-10.0, 0.0, 4.0), "kneeL": 20.0, "kneeR": 20.0, "ankL": 0.0, "ankR": 0.0,
    "toeL": 0.0, "toeR": 0.0, "gnd": 0.0, "rest": 0.0, "cL": "flat", "cR": "flat", "ikf": None,
}
# ท่าเล็งปืนยาวแนบไหล่ (ไม่มีโมเดลปืน มือจับอากาศ): มือขวาที่ด้ามใต้แนวลำกล้อง ศอกขวากางออกข้างราวระดับไหล่
# นิ้วชี้ไปหน้า ; มือซ้ายรองการ์ดมือใต้ลำกล้องข้างหน้า ; ข้อมือทั้งสองต่ำกว่าตาไม่เกิน 20 ซม. ; หัวก้มแนบพานท้าย
AIM = {"wR": (-0.12, 0.10, 0.24), "pR": (-1.0, -0.2, -0.4), "wL": (-0.06, 0.13, 0.40),
       "pL": (0.35, -1.0, -0.15), "hR": (30.0, -10.0), "hL": (12.0, -6.0), "sp": (3.0, -3.0, 0.0), "ch": (3.0, -5.0, 0.0),
       "look": (11.0, -3.0, 8.0)}
GUARD = {"wR": (-0.085, -0.135, 0.215), "pR": (-0.6, -1.0, -0.35), "wL": (0.075, -0.125, 0.240),
         "pL": (0.6, -1.0, -0.35), "hR": (-10.0, 0.0), "hL": (-10.0, 0.0), "sp": (5.0, 0.0, 0.0), "ch": (3.0, 0.0, 0.0),
         "look": (6.0, 0.0, 0.0), "pel": (0.0, -0.02, 0.0)}


def K(t, ease="smooth", **p):
    return (float(t), ease, p)


def _num(v):
    return isinstance(v, (int, float, tuple, list, np.ndarray)) and not isinstance(v, bool)


def expand(keys, base=None):
    """คีย์ -> รายการ (เวลา, ease, ค่าเต็ม) แต่ละคีย์รับค่าจากคีย์ก่อนหน้า ; ข้อเท้าเป็น (x, y, z) เสมอ (ตัวเลขเดียว = x)"""
    cur = dict(BASE if base is None else base)
    out = []
    for t, e, p in keys:
        cur = dict(cur, ikf=None)
        cur.update(p)
        for a in ("ankL", "ankR"):
            if not isinstance(cur[a], (tuple, list, np.ndarray)):
                cur[a] = (float(cur[a]), 0.0, 0.0)
        out.append((t, e, dict(cur)))
    return out


def acc(m0, m1):
    """ease แบบกำหนดความชันต้น/ปลายช่วง (หน่วยของช่วง: 1 = เส้นตรง) ใช้ต่อความเร็วท่าล้มข้ามคีย์ให้เร่งขึ้นตลอด"""
    return ("acc", float(m0), float(m1))


def _ease(t0, t1, t, e):
    if isinstance(e, tuple):
        s = float(np.clip((t - t0) / max(t1 - t0, 1e-9), 0.0, 1.0))
        return s * s * (3 - 2 * s) + e[1] * s * (1 - s) ** 2 - e[2] * s * s * (1 - s)
    return GA.ease((t - t0) / max(t1 - t0, 1e-9), e)


def sample(full, t):
    """ค่าที่เวลา t: ตัวเลขประมาณค่าแบบ ease ของคีย์ปลายทาง ; อย่างอื่น (การแตะ) = ค่าคีย์ล่าสุด"""
    if t <= full[0][0]:
        return dict(full[0][2])
    for i in range(1, len(full)):
        t1, e1, p1 = full[i]
        t0, _, p0 = full[i - 1]
        if t <= t1:
            f = _ease(t0, t1, t, e1)
            out = {}
            for k, v in p1.items():
                a = p0.get(k, v)
                if _num(v) and _num(a):
                    out[k] = tuple(np.asarray(a, float) + (np.asarray(v, float) - np.asarray(a, float)) * f) \
                        if isinstance(v, (tuple, list, np.ndarray)) else float(a + (v - a) * f)
                else:
                    out[k] = a if t < t1 else v
            return out
    return dict(full[-1][2])


# ---------------- จุดผิวโดยประมาณ (หาพื้น) : กระดูก -> [(จุดในกรอบกระดูก, รัศมี)] ----------------
SURF = {
    "pelvis": [((0.14, -0.03, -0.02), 0.0), ((-0.14, -0.03, -0.02), 0.0), ((0.0, -0.05, -0.12), 0.0),
               ((0.09, -0.09, -0.10), 0.0), ((-0.09, -0.09, -0.10), 0.0), ((0.0, -0.02, 0.09), 0.0)],
    "spine": [((0.0, 0.10, -0.10), 0.0), ((0.0, 0.10, 0.095), 0.0), ((0.14, 0.10, 0.0), 0.0), ((-0.14, 0.10, 0.0), 0.0)],
    "chest": [((0.0, -0.04, -0.11), 0.0), ((0.0, -0.08, 0.11), 0.0), ((0.16, -0.08, 0.0), 0.0), ((-0.16, -0.08, 0.0), 0.0),
              ((0.19, -0.02, -0.05), 0.0), ((-0.19, -0.02, -0.05), 0.0)],
    "head": [((0.0, 0.10, 0.01), 0.08)],
    "elbowL": [((0.0, 0.0, 0.0), 0.04)], "elbowR": [((0.0, 0.0, 0.0), 0.04)],
    "wristL": [((0.0, 0.0, 0.0), 0.035)], "wristR": [((0.0, 0.0, 0.0), 0.035)],
    "handL": [((0.0, -0.03, 0.0), 0.035)], "handR": [((0.0, -0.03, 0.0), 0.035)],
    "kneeL": [((0.0, 0.0, 0.0), 0.05)], "kneeR": [((0.0, 0.0, 0.0), 0.05)],
    "ankleL": [((0.0, 0.0, 0.0), 0.04)], "ankleR": [((0.0, 0.0, 0.0), 0.04)],
    "heelL": [((0.0, 0.0, 0.0), 0.0)], "heelR": [((0.0, 0.0, 0.0), 0.0)],
    "toeL": [((0.0, 0.0, 0.05), 0.0)], "toeR": [((0.0, 0.0, 0.05), 0.0)],
}
TORSO = ("pelvis", "spine", "chest", "head")


def lowest(G, bones=None):
    lo = 9.0
    for b, pts in SURF.items():
        if bones is not None and b not in bones:
            continue
        R, p = G[b]
        for pt, r in pts:
            lo = min(lo, (p + R @ np.array(pt))[1] - r)
    return lo


def _rotvec(q):
    """เวกเตอร์หมุน (องศา) ของ quaternion"""
    q = np.asarray(q, float)
    q = q if q[3] >= 0 else -q
    sn = np.sqrt(max(0.0, 1.0 - q[3] * q[3]))
    return np.degrees(q[:3] / sn * 2 * np.arccos(np.clip(q[3], -1, 1))) if sn > 1e-9 else np.zeros(3)


def _leg_values(L):
    """มุมขาจาก IK -> ค่าแบบคีย์ FK (hip = พับ x, บิด y, กาง z ; knee ; ank = เวกเตอร์หมุน) ข้างขวาสะท้อนกลับ"""
    out = {}
    for side, sx in SIDES:
        qh = GA.side_q(side, L["hip" + side])
        tw = rig.twist_y(qh)
        sw, tv = _rotvec(rig.qmul(qh, rig.qinv(tw))), _rotvec(tw)
        out["hip" + side] = (float(sw[0]), float(tv[1]), float(sw[2]))
        qk = L["knee" + side]
        out["knee" + side] = float(np.degrees(2 * np.arctan2(qk[0], qk[3])))
        out["ank" + side] = tuple(float(v) for v in _rotvec(GA.side_q(side, L["ankle" + side])))
    return out


def _pose_rows(full, frames, feet0):
    rows = [sample(full, k / FPS) for k in range(frames)]
    feet_all = []
    for p in rows:
        Rp = GA.Ry(np.radians(p["prot"][1])) @ GA.Rx(np.radians(p["prot"][0])) @ GA.Rz(np.radians(p["prot"][2]))
        p["_Rp"] = Rp
        feet = {}
        for side, sx in SIDES:
            a0, Rf0, yaw0 = feet0[side]
            dx, dy, dz, dyaw, pitch = p["f" + side]
            yaw = yaw0 + np.radians(dyaw)
            Rf = GA.foot_R(yaw, np.radians(pitch))
            # ก้มเท้า: หมุนรอบจุดส้น (+ = ส้นยก ใช้โคนนิ้ว)
            if pitch >= 0:
                pin = a0 + GA.foot_R(yaw0, 0.0) @ GA.BALL_P
                a = GA.ankle_from_contact(pin + np.array([dx, dy, dz]), GA.BALL_P, Rf)
            else:
                pin = a0 + GA.foot_R(yaw0, 0.0) @ GA.HEEL_P
                a = GA.ankle_from_contact(pin + np.array([dx, dy, dz]), GA.HEEL_P, Rf)
            feet[side] = (a, Rf, yaw)
        feet_all.append(feet)
    return rows, feet_all


def build(keys, frames, name, base=None, still_from=None):
    """คีย์ -> คลิป (q, t, contact) ; still_from = เฟรมที่เริ่มนิ่ง (ทุกเฟรมหลังจากนั้นเท่าเฟรมนั้น)
    ขาจาก IK (legk 1) ไป FK (legk 0): คีย์ IK สุดท้ายรับมุม FK = มุมที่ IK ได้ตรงนั้น และช่วงผสมใช้ IK ของเฟรมนั้น (ไม่ตาม
    เชิงกรานที่ล้มต่อ) ขาจึงออกจากท่า IK ไปท่า FK ต่อเนื่อง ไม่กระตุก ไม่เกินช่วงข้อ"""
    full = expand(keys, base)
    feet0 = GA.stance_feet()
    rows, feet_all = _pose_rows(full, frames, feet0)
    # เชิงกรานลด (เฉพาะเฟรมที่เท้ายังตรึงพื้น: legk > 0 ; ช่วงผสมไป FK ลดตามน้ำหนัก IK)
    y_des = np.zeros(frames)
    y_lim = np.full(frames, 9.0)
    for k, p in enumerate(rows):
        y_des[k] = GA.STANCE["h0"] + p["pel"][1]
        if p["legk"] > 0.0:
            lim = GA.pelvis_limit((p["pel"][0], p["pel"][2]), p["_Rp"], {s: feet_all[k][s][0] for s in "LR"})
            y_lim[k] = lim + max(0.0, y_des[k] - lim) * (1.0 - min(1.0, p["legk"]))
    y = GA.smooth_under(y_des, y_lim, loop=False, sigma=0.8, rounds=12) if (y_lim < 8).any() else y_des
    # คีย์ IK สุดท้ายก่อนเปลี่ยนเป็น FK: เติมมุมขาจาก IK ที่เวลานั้น ; hold[k] = IK ที่ใช้ผสมในเฟรม k ของช่วงผสม
    hold = {}
    for i in range(len(full) - 1):
        t0, e0, p0 = full[i]
        if p0["legk"] >= 0.999 and full[i + 1][2]["legk"] < 0.999:
            k0 = min(int(round(t0 * FPS)), frames - 1)
            L = {}
            GA.solve_legs(L, rows[k0]["_Rp"], np.array([rows[k0]["pel"][0], y[k0], rows[k0]["pel"][2]]), feet_all[k0])
            p0.update(_leg_values(L))
            for k in range(k0 + 1, min(int(np.ceil(full[i + 1][0] * FPS)) + 1, frames)):
                hold[k] = L
    # คีย์ FK ที่มุมขามาจาก IK ณ เวลาคีย์ (เท้าตาม ikf, เข่าชี้ไปหน้าเชิงกราน): ขาพับพอดีกับเชิงกรานที่ลดลง ไม่จมพื้น
    for t0, e0, p0 in full:
        if p0.get("ikf"):
            Rp = GA.Ry(np.radians(p0["prot"][1])) @ GA.Rx(np.radians(p0["prot"][0])) @ GA.Rz(np.radians(p0["prot"][2]))
            feet, poles = {}, {}
            for side, sx in SIDES:
                a0, Rf0, yaw0 = feet0[side]
                dx, dy, dz, dyaw, pitch = p0["ikf"][side]
                yaw = yaw0 + np.radians(dyaw)
                Rf = GA.foot_R(yaw, np.radians(pitch))
                pin = a0 + GA.foot_R(yaw0, 0.0) @ GA.BALL_P
                feet[side] = (GA.ankle_from_contact(pin + np.array([dx, dy, dz]), GA.BALL_P, Rf), Rf, yaw)
                poles[side] = Rp @ GA.Ry(np.radians(8.0) * sx) @ np.array([0.0, 0.0, 1.0])
            L = {}
            GA.solve_legs(L, Rp, np.array([p0["pel"][0], GA.STANCE["h0"] + p0["pel"][1], p0["pel"][2]]), feet, poles)
            p0.update(_leg_values(L))
    if hold or any(p0.get("ikf") for _, _, p0 in full):
        rows, feet_all = _pose_rows(full, frames, feet0)
    q = {b: [] for b in J}
    tp = []
    contact = {"L": [], "R": []}
    lows = []
    torso_low = []
    reach = 0.0
    for k, p in enumerate(rows):
        Rp = p["_Rp"]
        ppos = np.array([p["pel"][0], y[k], p["pel"][2]])
        L = {b: I4.copy() for b in J}
        L["pelvis"] = GA.quat(Rp)
        # ขา: IK (เท้าตรึง) ผสมกับมุมตรง
        Lik = dict(L)
        if p["legk"] > 0.0 and k in hold and p["legk"] < 0.999:
            Lik.update(hold[k])
        elif p["legk"] > 0.0:
            r, _ = GA.solve_legs(Lik, Rp, ppos, feet_all[k])
            if p["legk"] >= 0.999:
                reach = max(reach, r)
        for side, sx in SIDES:
            qh = GA.side_q(side, GA.qst(*p["hip" + side]))
            qk = rig.qaxis([1, 0, 0], p["knee" + side])
            qa = GA.side_q(side, GA.qrv(*p["ank" + side]))
            w = p["legk"]
            if w > 0.0:
                qh = rig.qslerp(qh, Lik["hip" + side], w)
                qk = rig.qslerp(qk, Lik["knee" + side], w)
                qa = rig.qslerp(qa, Lik["ankle" + side], w)
            L["hip" + side], L["knee" + side], L["ankle" + side] = qh, qk, qa
            # ส้นยก: นิ้ววางราบกับพื้น
            L["toe" + side] = rig.qaxis([1, 0, 0], p["toe" + side] - max(p["f" + side][4], 0.0) * min(p["legk"], 1.0))
            c = p["c" + side]
            pf = p["f" + side][4]
            if c == "flat" and abs(pf) > 0.5:
                c = "ball" if pf > 0 else "heel"     # ส้นยก = หมุนรอบโคนนิ้ว ; ปลายยก = หมุนรอบส้น
            contact[side].append(c if (c and p["legk"] >= 0.999) else None)
        # ลำตัว + หัว
        L["spine"] = GA.qst(*p["sp"])
        L["chest"] = GA.qst(*p["ch"])
        Rc = Rp @ GA.mat(L["spine"]) @ GA.mat(L["chest"])
        qn, qh_ = GA.look(Rc, *p["look"])
        wl = p["lookk"]
        L["neck"] = rig.qslerp(GA.qst(*p["nk"]), qn, wl)
        L["head"] = rig.qslerp(GA.qst(*p["hd"]), qh_, wl)
        # แขน: IK ในกรอบอก ผสมกับมุมตรง
        for side, sx in SIDES:
            r = GA.arm_ik(side, np.asarray(p["w" + side], float), np.asarray(p["p" + side], float))
            qs_fk = GA.side_q(side, GA.qst(*p["sh" + side]))
            qe_fk = rig.qaxis([1, 0, 0], -p["el" + side])
            w = p["armk"]
            L["shoulder" + side] = rig.qslerp(qs_fk, r["shoulder"], w)
            L["elbow" + side] = rig.qslerp(qe_fk, r["elbow"], w)
            hx, hz = p["h" + side]
            L["wrist" + side] = GA.side_q(side, GA.qrv(hx, 0.0, hz))
            L["hand" + side] = I4.copy()
        for b in J:
            q[b].append(L[b])
        tp.append(ppos)
    # gnd: ไม่ให้ร่างลงใต้พื้น ; rest: วางลงพื้นพอดี (gnd + rest = จุดต่ำสุดแตะพื้นพอดีทุกเฟรม: ร่างหมุนรอบจุดที่แตะ ไม่ลอยไม่จม)
    for k, p in enumerate(rows):
        L = {b: q[b][k] for b in J}
        ppos = tp[k]
        G = GA.fk(L, ppos)
        lo = lowest(G)
        if p["gnd"] > 0.0 and lo < 0.0:
            ppos = ppos + np.array([0.0, -lo, 0.0])
            lo = 0.0
        if p["rest"] > 0.0 and lo > 0.0:
            ppos = ppos - np.array([0.0, lo * p["rest"], 0.0])
        G = GA.fk(L, ppos)
        tp[k] = ppos
        lows.append(lowest(G))
        torso_low.append(lowest(G, TORSO))
    if still_from is not None:
        for b in J:
            for k in range(still_from + 1, frames):
                q[b][k] = q[b][still_from]
        for k in range(still_from + 1, frames):
            tp[k] = tp[still_from]
            lows[k] = lows[still_from]
            torso_low[k] = torso_low[still_from]
            for s in "LR":
                contact[s][k] = contact[s][still_from]
    return {"q": q, "t": {"pelvis": tp}, "contact": contact, "frames": frames, "length": (frames - 1) / FPS,
            "loop": False, "speed": 0.0, "info": {"reach": reach, "lowest": float(min(lows)), "torso_low": torso_low}}


def thud_time(clip, after=0.15, tol=0.02):
    """เวลาที่ลำตัวถึงพื้นครั้งแรก (ประตู: ล้มต้องมีเสียงตุ้บ)"""
    tl = clip["info"]["torso_low"]
    for k, v in enumerate(tl):
        if k / FPS > after and v <= tol:
            return round(k / FPS, 4)
    return None


# ---------------- ท่าปืน ----------------

def clip_aim():
    return build([K(0.0, **AIM)], 1, "aim")


SHOT_T = 0.02          # กระสุนออก (ท่ายิงเริ่มจากท่าเล็งพอดี: เกมเดิมเล็งที่ shot − 0.02)


def clip_fire():
    kick = dict(AIM)
    kick.update(wR=tuple(np.array(AIM["wR"]) + [0.004, 0.014, -0.028]), wL=tuple(np.array(AIM["wL"]) + [0.002, 0.012, -0.020]),
                ch=(1.0, -5.5, 0.0), sp=(2.4, -3.0, 0.0), look=(9.0, -3.0, 8.0), pel=(0.0, 0.0, -0.004))
    keys = [K(0.0, **AIM), K(SHOT_T, **AIM), K(0.0667, "out", **kick), K(0.1667, "smooth", **AIM)]
    c = build(keys, 6, "fire")
    c["events"] = [{"t": SHOT_T, "kind": "shot"}]
    return c


RELOAD_T = 1.6         # ArenaData.WEAPONS.gun.reload


def clip_reload():
    """เปลี่ยนแม็ก 1.6 วิ: มือขวาลดปืนลงเล็กน้อย มือซ้ายดึงแม็กออกจากช่อง (ห่างมือขวาคงที่) ไปกระเป๋าที่เข็มขัดหน้าสะโพกซ้าย
    แล้วใส่แม็กใหม่ ตบเข้า กลับไปรองการ์ดมือ"""
    a = np.array
    low = dict(AIM, wR=tuple(a(AIM["wR"]) + [0.03, -0.07, -0.02]), pR=(-1.0, 0.0, -0.6), look=(30.0, -2.0, 4.0),
               ch=(7.0, -3.0, 0.0), sp=(5.0, -2.0, 0.0), hR=(16.0, 0.0))
    well = tuple(a(low["wR"]) + [0.03, -0.045, 0.115])       # ช่องแม็ก: ตำแหน่งคงที่จากมือขวาที่ลดลง
    pouch = (0.17, -0.27, 0.20)                               # กระเป๋าแม็กที่เข็มขัด หน้าสะโพกซ้าย
    # มือขวาไม่ค้างนิ่ง: เอียงปืน (สมมติ) เข้าหามือซ้ายตอนดึง/ใส่แม็ก ดึงเข้า 2 ซม. ตบแม็กแล้วมือเด้งขึ้น ; อก/สะโพกลอยช้า ๆ
    def rt(dw, hz, d_ch=(0.0, 0.0), d_pel=0.0, wl=None):
        dw = a(dw)
        out = dict(wR=tuple(a(low["wR"]) + dw), hR=(16.0, hz), ch=(low["ch"][0] + d_ch[0], low["ch"][1] + d_ch[1], 0.0),
                   pel=(0.0, 0.0, d_pel))
        if wl is not None:
            out["wL"] = tuple(a(wl) + dw)              # มือซ้ายที่ช่องแม็กตามปืน
        return out
    keys = [K(0.0, **AIM),
            K(0.22, **dict(low, wL=tuple(a(well) + [0.05, 0.02, 0.0]), pL=(0.9, -0.7, -0.3))),
            K(0.36, **dict(low, pL=(0.9, -0.7, -0.3), **rt([0.012, 0.0, -0.02], 10.0, wl=well))),
            K(0.48, "out", **dict(low, wL=tuple(a(well) + [0.07, -0.12, -0.05]), pL=(0.8, -1.0, -0.2),
                                  **rt([0.012, 0.006, -0.02], 12.0, (0.5, -0.5)))),
            K(0.62, **dict(low, wL=pouch, pL=(0.8, -1.0, -0.6), **rt([0.004, -0.004, -0.008], 5.0, (1.0, -1.0), 0.004))),
            K(0.82, **dict(low, wL=tuple(a(pouch) + [0.0, 0.02, -0.03]), pL=(0.9, -0.8, -0.8), look=(34.0, 8.0, 4.0),
                           **rt([0.0, -0.008, 0.0], 3.0, (1.5, -1.5), 0.008))),
            K(0.96, **dict(low, wL=tuple(a(pouch) + [-0.02, 0.02, -0.02]), **rt([0.0, -0.006, 0.004], 4.0, (1.0, -1.0), 0.006))),
            K(1.10, **dict(low, wL=tuple(a(well) + [0.02, -0.08, -0.04]), pL=(0.9, -0.7, -0.3),
                           **rt([0.008, 0.0, -0.015], 9.0, (0.5, -0.5), 0.002))),
            K(1.18, "out", **dict(low, pL=(0.9, -0.6, -0.3), **rt([0.008, 0.025, -0.015], 9.0, (-2.0, 0.0), wl=well))),
            K(1.26, **dict(low, wL=tuple(a(well) + [-0.01, 0.04, 0.0]), pL=(0.9, -0.6, -0.3), **rt([0.004, 0.008, -0.006], 4.0))),
            K(1.36, **dict(low, wL=tuple(a(AIM["wL"]) + [-0.02, -0.06, -0.06]), pL=(0.9, -0.6, -0.2), look=(24.0, -2.0, 4.0))),
            K(1.60, **AIM)]
    c = build(keys, int(round(RELOAD_T * FPS)) + 1, "reload")
    c["events"] = [{"t": 0.38, "kind": "mag_out"}, {"t": 1.18, "kind": "mag_in"}, {"t": 1.52, "kind": "ready"}]
    return c


# ---------------- ต่อย / ฟัน (เท้าตรึงพื้น ใช้ซ้อนบนท่าเดินได้) ----------------
PUNCH_T = 0.12         # ArenaData.WEAPONS.punch.active
SWING_T = 0.18         # ArenaData.WEAPONS.sword.active
PUNCH_N = 16           # 0.5 วิ (cooldown 0.55)
SWING_N = 23           # 0.733 วิ (cooldown 0.8)


def _guard(**kw):
    g = dict(GUARD)
    g.update(kw)
    return g


def _chest_frame(p):
    """กรอบอกในกรอบหุ่นของค่าคีย์ p (เชิงกรานตามคีย์ ไม่นับที่ IK ขาลดลง): (R, จุดกำเนิด)"""
    q = dict(BASE)
    q.update(p)
    Rp = GA.Ry(np.radians(q["prot"][1])) @ GA.Rx(np.radians(q["prot"][0])) @ GA.Rz(np.radians(q["prot"][2]))
    pp = np.array([q["pel"][0], GA.STANCE["h0"] + q["pel"][1], q["pel"][2]])
    Rs = Rp @ GA.mat(GA.qst(*q["sp"]))
    Rc = Rs @ GA.mat(GA.qst(*q["ch"]))
    return Rc, pp + Rp @ OFF["spine"] + Rs @ OFF["chest"]


HAND_TIP = 0.17          # ข้อมือ -> ปลายมือ (มือ 0.085 + ฝ่ามือ 0.085) แขนตรง


def _reach(p, side, tip):
    """เป้าข้อมือในกรอบอก ให้ปลายมือถึงจุด tip ในกรอบหุ่น (ลำตัวบิดเท่าไรหมัดก็ไปที่เดิม ไม่เบนตามอก)"""
    Rc, pc = _chest_frame(p)
    tip = np.asarray(tip, float)
    d = tip - (pc + Rc @ OFF["shoulder" + side])
    wrist = tip - d / np.linalg.norm(d) * HAND_TIP
    return tuple(round(float(v), 4) for v in Rc.T @ (wrist - pc))


def _strike(hit, side, tip):
    """คีย์ตอนโดน: เป้าข้อมือ (กรอบอก) ที่ทำให้ปลายมือ (FK จริง รวมศอกงอ) ถึงจุด tip ในกรอบหุ่น — ปรับซ้ำจนห่างไม่เกิน 2 มม."""
    hit = dict(hit)
    Rc, pc = _chest_frame(hit)
    want = np.asarray(tip, float)
    w = np.array(_reach(hit, side, tip))
    for _ in range(8):
        hit["w" + side] = tuple(float(v) for v in w)
        c = build([K(0.0, **hit)], 1, "aim")
        G = GA.fk({b: np.array(c["q"][b][0]) for b in J}, np.array(c["t"]["pelvis"][0]))
        R, p = G["hand" + side]
        err = want - (p + R @ np.array([0.0, -0.085, 0.0]))
        if np.linalg.norm(err) < 0.002:
            break
        w = w + Rc.T @ err
    hit["w" + side] = tuple(round(float(v), 4) for v in w)
    return hit


# เท้าหลังเขย่งหมุนบนโคนนิ้ว (ส้นยก 12° ปลายเท้าบิดเข้า 12°) ตอนออกหมัด/ฟัน แล้ววางคืน
REAR_PIVOT = {"R": (0.0, 0.0, 0.0, 12.0, 12.0), "L": (0.0, 0.0, 0.0, -12.0, 12.0)}
LUNGE = (0.0, -0.02, 0.05)       # ถ่ายน้ำหนักไปหน้าตอนโดน (แทง: z 0.08)


def clip_punch(i):
    """หมัด: ปลายหมัดถึงเป้าในกรอบหุ่นที่ 0.12 วิ (ตรงหน้า ±10° หรือหมัดเหวี่ยง ±15°) ถ่ายน้ำหนักไปหน้า เท้าหลังเขย่งหมุน
    แล้วคืนท่าการ์ด เชิงกรานกลับตรง (หันเท่าท่ายืน) ภายใน 0.33 วิ"""
    hold = PUNCH_T + 0.045
    if i == 0:       # หมัดตรงขวา
        hit = _strike(_guard(pR=(-0.9, -0.6, -0.2), hR=(-4.0, 0.0), ch=(4.0, 10.0, 0.0), sp=(5.0, 5.0, 0.0),
                             prot=(2.0, 7.0, 0.0), look=(4.0, 3.0, 0.0), wL=(0.06, -0.10, 0.20), pel=LUNGE,
                             fR=REAR_PIVOT["R"]), "R", (-0.04, 1.30, 0.78))
        pre = _guard(wR=(-0.10, -0.12, 0.17), ch=(3.0, -6.0, 0.0), prot=(1.0, -4.0, 0.0))
        side = "R"
    elif i == 1:     # หมัดแย็บซ้าย
        hit = _strike(_guard(pL=(0.9, -0.6, -0.2), hL=(-4.0, 0.0), ch=(4.0, -8.0, 0.0), sp=(5.0, -4.0, 0.0),
                             prot=(2.0, -5.0, 0.0), look=(4.0, -3.0, 0.0), wR=(-0.08, -0.11, 0.19), pel=LUNGE,
                             fL=REAR_PIVOT["L"]), "L", (0.04, 1.31, 0.77))
        pre = _guard(wL=(0.09, -0.11, 0.18), ch=(3.0, 5.0, 0.0), prot=(1.0, 3.0, 0.0))
        side = "L"
    else:            # หมัดเหวี่ยงขวา (ศอกยก)
        hit = _strike(_guard(pR=(-0.8, -0.6, -0.2), hR=(-2.0, 8.0), ch=(4.0, 16.0, 0.0), sp=(5.0, 9.0, 0.0),
                             prot=(2.0, 12.0, 0.0), look=(4.0, 6.0, 0.0), wL=(0.07, -0.11, 0.21), pel=LUNGE,
                             fR=REAR_PIVOT["R"]), "R", (0.05, 1.33, 0.58))
        pre = _guard(wR=(-0.24, -0.08, 0.22), pR=(-1.0, -0.2, -0.4), ch=(3.0, -8.0, 0.0), prot=(1.0, -5.0, 0.0))
        side = "R"
    back = dict(hit)
    back["w" + side] = tuple(np.array(hit["w" + side]) - [0.0, 0.006, 0.02])
    rest = dict(prot=(1.0, 0.0, 0.0), pel=(0.0, 0.0, 0.0), fL=(0.0, 0.0, 0.0, 0.0, 0.0), fR=(0.0, 0.0, 0.0, 0.0, 0.0))
    keys = [K(0.0, **pre), K(PUNCH_T, "in", **hit), K(hold, **back), K(0.33, "smooth", **_guard(**rest)),
            K((PUNCH_N - 1) / FPS, "smooth", **_guard(wR=(-0.11, -0.22, 0.17), wL=(0.11, -0.22, 0.17), **rest))]
    c = build(keys, PUNCH_N, "punch_%d" % i)
    c["events"] = [{"t": PUNCH_T, "kind": "shot"}]
    return c


def clip_swing(i):
    """ฟัน/แทงมือเดียว: ใบมือถึงเป้าในกรอบหุ่นที่ 0.18 วิ (ฟันแนวนอนผ่านกึ่งกลางพอดี ; แทงตรงหน้า ±10°)
    ถ่ายน้ำหนักไปหน้า เท้าขวาเขย่งหมุน แล้วคืนท่าการ์ด เชิงกรานกลับตรง"""
    free_l = (0.20, -0.24, 0.17)
    if i == 0:       # ฟันแนวนอนจากขวาไปซ้าย
        pre = _guard(wR=(-0.36, 0.0, 0.16), pR=(-0.5, -0.8, -0.3), hR=(-20.0, 15.0), wL=free_l, ch=(2.0, -18.0, 0.0),
                     sp=(3.0, -10.0, 0.0), prot=(1.0, -10.0, 0.0), look=(5.0, 0.0, 0.0))
        hit = _strike(_guard(pR=(-0.8, -0.8, 0.0), hR=(10.0, -10.0), wL=free_l, ch=(4.0, 12.0, 0.0), sp=(5.0, 6.0, 0.0),
                             prot=(2.0, 8.0, 0.0), look=(5.0, 4.0, 0.0), pel=LUNGE, fR=REAR_PIVOT["R"]), "R", (0.0, 1.22, 0.72))
        fol = _strike(_guard(pR=(-0.6, -0.9, 0.1), hR=(10.0, -14.0), wL=free_l, ch=(4.0, 24.0, 0.0), sp=(5.0, 13.0, 0.0),
                             prot=(2.0, 16.0, 0.0), look=(5.0, 20.0, 0.0), pel=LUNGE, fR=REAR_PIVOT["R"]), "R", (0.36, 1.14, 0.44))
    elif i == 1:     # ฟันจากบนลงล่าง
        pre = _guard(wR=(-0.16, 0.24, 0.18), pR=(-1.0, 0.0, -0.3), hR=(-25.0, 0.0), wL=free_l, ch=(-6.0, -6.0, 0.0),
                     sp=(-3.0, -3.0, 0.0), look=(0.0, 0.0, 0.0))
        hit = _strike(_guard(pR=(-0.9, -0.7, 0.0), hR=(15.0, 0.0), wL=free_l, ch=(9.0, 4.0, 0.0), sp=(7.0, 2.0, 0.0),
                             prot=(4.0, 3.0, 0.0), look=(10.0, 0.0, 0.0), pel=(0.0, -0.03, 0.03), fR=REAR_PIVOT["R"]),
                      "R", (-0.03, 1.15, 0.74))
        fol = _guard(wR=(-0.04, -0.33, 0.29), pR=(-0.9, -0.5, 0.2), hR=(20.0, 0.0), wL=free_l, ch=(12.0, 6.0, 0.0),
                     sp=(9.0, 3.0, 0.0), prot=(5.0, 3.0, 0.0), look=(14.0, 0.0, 0.0), pel=(0.0, -0.04, 0.03), fR=REAR_PIVOT["R"])
    else:            # แทงตรง
        pre = _guard(wR=(-0.27, -0.29, 0.10), pR=(-0.8, -0.5, -0.4), hR=(-6.0, 0.0), wL=free_l, ch=(1.0, -14.0, 0.0),
                     sp=(2.0, -7.0, 0.0), prot=(0.0, -6.0, 0.0))
        hit = _strike(_guard(pR=(-0.9, -0.8, -0.1), hR=(-2.0, 0.0), wL=free_l, ch=(6.0, 10.0, 0.0), sp=(6.0, 5.0, 0.0),
                             prot=(3.0, 7.0, 0.0), look=(5.0, 4.0, 0.0), pel=(0.0, -0.03, 0.08), fR=REAR_PIVOT["R"]),
                      "R", (-0.04, 1.28, 0.80))
        # ตามแรงต่อเล็กน้อย (ไม่ค้างนิ่ง 0.18-0.30 วิ)
        fol = _strike(dict(hit, ch=(7.0, 13.0, 0.0), sp=(6.0, 6.0, 0.0), pel=(0.0, -0.035, 0.09)), "R", (-0.03, 1.26, 0.82))
    rest = dict(prot=(1.0, 0.0, 0.0), pel=(0.0, 0.0, 0.0), fL=(0.0, 0.0, 0.0, 0.0, 0.0), fR=(0.0, 0.0, 0.0, 0.0, 0.0))
    keys = [K(0.0, **pre), K(SWING_T, "in", **hit), K(0.30, "out", **fol), K(0.52, **_guard(**rest)),
            K((SWING_N - 1) / FPS, **_guard(wR=(-0.11, -0.22, 0.17), wL=(0.11, -0.22, 0.17), **rest))]
    c = build(keys, SWING_N, "swing_%d" % i)
    c["events"] = [{"t": SWING_T, "kind": "shot"}]
    return c


# ---------------- โดน (ด้านที่ถูกตี: ร่างสะบัดตามแรง เท้าตรึง) ----------------
HIT_N = 16


def clip_hit(side):
    s = {"front": (1, 0), "back": (-1, 0), "left": (0, 1), "right": (0, -1)}[side]
    fb, lr = s
    # fb = +1 ถูกตีจากหน้า (หงายหลัง) ; lr = +1 ถูกตีจากซ้าย (+X): ร่างเบนไปขวา บิดให้ไหล่ซ้ายถอยไปหลัง
    imp = dict(pel=(-0.025 * lr, -0.025, -0.03 * fb), prot=(-3.0 * fb, 5.0 * lr, -2.5 * lr),
               sp=(2.0 - 6.0 * fb, 5.0 * lr, 5.0 * lr), ch=(-0.5 - 9.0 * fb, 9.0 * lr, 7.0 * lr),
               look=(2.0 - 14.0 * fb, -14.0 * lr, 9.0 * lr),
               wL=tuple(HANG_W["L"] + [0.04 + 0.03 * max(lr, 0), 0.07 + 0.04 * fb, 0.10 * fb]),
               wR=tuple(HANG_W["R"] + [-0.04 + 0.03 * min(lr, 0), 0.07 + 0.04 * fb, 0.10 * fb]))
    mid = {k: (tuple(np.array(v) * 0.35) if k in ("pel", "prot", "sp", "ch", "look") else v) for k, v in imp.items()}
    mid["sp"] = tuple(np.array(BASE["sp"]) + (np.array(imp["sp"]) - np.array(BASE["sp"])) * 0.35)
    mid["ch"] = tuple(np.array(BASE["ch"]) + (np.array(imp["ch"]) - np.array(BASE["ch"])) * 0.35)
    mid["look"] = tuple(np.array(BASE["look"]) + (np.array(imp["look"]) - np.array(BASE["look"])) * 0.35)
    mid["prot"] = tuple(np.array(BASE["prot"]) + (np.array(imp["prot"]) - np.array(BASE["prot"])) * 0.35)
    mid["wL"], mid["wR"] = tuple(HANG_W["L"] + [0.01, 0.02, 0.02 * fb]), tuple(HANG_W["R"] + [-0.01, 0.02, 0.02 * fb])
    keys = [K(0.0), K(0.07, "out", **imp), K(0.24, **mid), K((HIT_N - 1) / FPS, **{k: BASE[k] for k in imp})]
    return build(keys, HIT_N, "hit_" + side)


def clip_hit_heavy():
    """โดนหนักจากหน้า: เซถอยเท้าขวาแล้วก้าวกลับ ท่อนบนค่อย ๆ คืนตลอดท่า (ไม่ค้างแล้วสะบัดตอนท้าย)"""
    n = 28
    back = dict(pel=(0.0, -0.06, -0.10), prot=(-6.0, 6.0, 0.0), sp=(-6.0, 4.0, 0.0), ch=(-12.0, 6.0, 0.0),
                look=(-16.0, 4.0, 0.0), wL=tuple(HANG_W["L"] + [0.10, 0.16, 0.16]), wR=tuple(HANG_W["R"] + [-0.10, 0.16, 0.16]))
    keys = [K(0.0),
            K(0.08, "out", cR=None, **back),
            K(0.24, "smooth", fR=(-0.02, 0.06, -0.09, -4.0, 18.0), pel=(0.0, -0.06, -0.09), prot=(-4.0, 5.0, 0.0),
              sp=(-3.0, 3.0, 0.0), ch=(-8.0, 5.0, 0.0), look=(-11.0, 3.0, 0.0),
              wL=tuple(HANG_W["L"] + [0.08, 0.11, 0.11]), wR=tuple(HANG_W["R"] + [-0.08, 0.11, 0.11])),
            K(0.36, "smooth", cR="flat", fR=(-0.02, 0.0, -0.16, -6.0, 10.0), pel=(0.0, -0.05, -0.08), prot=(-1.0, 3.5, 0.0),
              sp=(1.0, 2.0, 0.0), ch=(-3.0, 3.5, 0.0), look=(-3.0, 1.5, 0.0),
              wL=tuple(HANG_W["L"] + [0.05, 0.06, 0.06]), wR=tuple(HANG_W["R"] + [-0.05, 0.06, 0.06])),
            K(0.52, "smooth", cR=None, fR=(-0.02, 0.0, -0.16, -6.0, 0.0), pel=(0.0, -0.03, -0.07), prot=(1.0, 2.0, 0.0),
              sp=(4.0, 1.0, 0.0), ch=(2.0, 2.0, 0.0), look=(4.0, 0.0, 0.0),
              wL=tuple(HANG_W["L"] + [0.03, 0.03, 0.03]), wR=tuple(HANG_W["R"] + [-0.03, 0.03, 0.03])),
            K(0.70, "smooth", fR=(-0.01, 0.05, -0.10, -3.0, 14.0), pel=(0.0, -0.01, -0.05), prot=(1.0, 1.0, 0.0),
              sp=(3.0, 0.5, 0.0), ch=(0.8, 1.0, 0.0), look=(3.0, 0.0, 0.0),
              wL=tuple(HANG_W["L"] + [0.015, 0.015, 0.015]), wR=tuple(HANG_W["R"] + [-0.015, 0.015, 0.015])),
            K(0.80, "smooth", cR="flat", fR=(0.0, 0.0, 0.0, 0.0, 0.0), pel=(0.0, 0.0, 0.0), prot=(1.0, 0.3, 0.0),
              sp=(2.3, 0.2, 0.0), ch=(-0.1, 0.3, 0.0), look=(2.3, 0.0, 0.0),
              wL=tuple(HANG_W["L"] + [0.005, 0.005, 0.005]), wR=tuple(HANG_W["R"] + [-0.005, 0.005, 0.005])),
            K((n - 1) / FPS, **{k: BASE[k] for k in ("pel", "prot", "sp", "ch", "look", "wL", "wR")})]
    return build(keys, n, "hit_heavy")


# ---------------- ตาย (จบด้วยเสียงตุ้บ แล้วนอนนิ่ง) ----------------
# ท่านอนสุดท้าย (ปรับด้วยตัวหาค่า: ลำตัวแนบพื้น ศอก ข้อมือ มือ ข้อเท้าห่างพื้น <= 4 ซม. เข่า <= 5 ซม. หลังหักรัศมีแขนขา)
# หงาย: แขนกางวางพื้น ศอกงอเล็กน้อย ขาเหยียด ปลายเท้าแบะออก ; คว่ำ: แขนแนบข้างลำตัว หน้าหันข้าง หลังเท้าแนบพื้น ;
# ตะแคงขวา: แขนล่างยื่นไปหน้า แขนบนพาดหน้าอก มือแตะพื้น ขาบนงอเข่าแตะพื้น
SUPINE = dict(sp=(-1.3, 0.0, 0.0), ch=(-1.8, 0.0, 0.0), nk=(-6.3, 22.0, 6.0), hd=(-6.0, 8.0, 2.0),
              shL=(16.4, 47.0, 54.6), shR=(16.9, 51.2, 59.0), elL=17.6, elR=19.1, hL=(5.0, 0.0), hR=(5.6, 0.0),
              hipL=(2.7, 20.5, 9.5), hipR=(2.5, 23.5, 8.2), kneeL=-0.8, kneeR=0.4, ankL=(26.5, 0.0, 0.0), ankR=(20.0, 0.0, -1.7))
PRONE = dict(sp=(2.5, 0.0, 0.0), ch=(4.2, 0.0, 0.0), nk=(1.9, -50.0, 0.0), hd=(2.0, -9.0, -4.0),
             shL=(-12.9, -20.9, 19.1), shR=(-12.9, -20.9, 19.1), elL=0.7, elR=0.7, hL=(6.6, 0.0), hR=(6.6, 0.0),
             hipL=(-4.4, 24.2, 5.9), hipR=(-5.0, 26.2, 6.5), kneeL=7.6, kneeR=9.8, ankL=(49.3, 0.0, 3.6), ankR=(42.2, 0.0, 0.1))
SIDE = dict(sp=(-3.7, 0.0, 2.0), ch=(4.8, 0.0, 2.0), nk=(9.4, 10.0, 32.8), hd=(2.0, 4.0, 6.0),
            shL=(-29.4, -42.2, -11.6), shR=(-61.7, -2.1, -14.0), elL=69.8, elR=17.5, hL=(-35.3, 0.0), hR=(3.0, 3.2),
            hipL=(-28.6, -0.2, -14.8), hipR=(-10.5, 6.0, -6.9), kneeL=89.4, kneeR=24.3, ankL=(32.0, 0.0, 0.0), ankR=(30.0, 0.0, 0.0))
SUPINE_ROT, PRONE_ROT, SIDE_ROT = (-88.9, 0.0, 0.0), (87.7, 0.0, 0.0), (6.8, 0.0, 82.5)


def _fk_from(p):
    """คีย์มุมตรง (ขา แขน หัว) ; ร่างแตะพื้นพอดีด้วยจุดต่ำสุดเสมอ (gnd + rest): ล้มหมุนรอบจุดที่แตะ ไม่ลอย ไม่จม"""
    d = dict(legk=0.0, armk=0.0, lookk=0.0, gnd=1.0, rest=1.0, cL=None, cR=None)
    d.update(p)
    return d


def _lie(pose, rot, yaw, pel, **kw):
    """ท่านอนสุดท้าย + หมุนเชิงกราน (ก้ม, หัน yaw, เอียง) + ตำแหน่ง ; วางลงพื้นพอดี"""
    d = dict(pose, prot=(rot[0], yaw, rot[2]), pel=pel, rest=1.0)
    d.update(kw)
    return d


def _mix(a, b, f, **kw):
    """ท่าระหว่าง a กับ b (ตัวเลข/ทูเพิลผสมเชิงเส้น f) — ท่าตกกระทบก่อนแขนขาวางพื้น"""
    d = {}
    for k in set(a) | set(b):
        va, vb = a.get(k, b.get(k)), b.get(k, a.get(k))
        if isinstance(va, tuple):
            d[k] = tuple(float(x + (y - x) * f) for x, y in zip(va, vb))
        elif isinstance(va, (int, float)) and not isinstance(va, bool):
            d[k] = float(va + (vb - va) * f)
        else:
            d[k] = vb
    d.update(kw)
    return d


def clip_die(kind):
    """ล้ม: ตัวงอเข่าแบบเท้าตรึง (IK) แล้วส่งต่อให้มุมขาตรง (FK) ทีละน้อย 4 เฟรม ไม่กระตุก ; ลำตัวถึงพื้น (ตุ้บ)
    แล้วแขนขาวางลงพื้นใน 0.2 วิ (ease out) นิ่งก่อน 1.4 วิ (ฟื้นในเกมที่ 2 วิ)"""
    # ช่วงทรุดจนตุ้บ: acc() ต่อความเร็วข้ามคีย์ หัว/เชิงกรานลงเร็วขึ้นตลอด ไม่ค้างกลางอากาศแล้วกระแทก (เวลาคีย์/ความชันจากการค้นหาเชิงตัวเลข)
    if kind == "back":
        n = 37
        end = _lie(SUPINE, SUPINE_ROT, 6.0, (0.0, -0.78, -0.62))
        hit = _fk_from(dict(pel=(0.0, -0.78, -0.62), prot=(-88.9, 6.0, 0.0), hipL=(-24.0, 10.0, 9.0), hipR=(-16.0, 12.0, 8.0),
                            kneeL=32.0, kneeR=22.0, ankL=(20.0, 0.0, 0.0), ankR=(18.0, 0.0, 0.0), shL=(-34.0, 12.0, 50.0),
                            shR=(-28.0, 14.0, 56.0), elL=34.0, elR=30.0, nk=(14.0, 10.0, 2.0), hd=(6.0, 4.0, 0.0),
                            sp=(-3.0, 0.0, 0.0), ch=(-3.0, 0.0, 0.0)))
        keys = [K(0.0),
                K(0.10, "out", ch=(-12.0, 0.0, 0.0), sp=(-6.0, 0.0, 0.0), look=(-14.0, 0.0, 0.0), pel=(0.0, -0.03, -0.04),
                  wL=tuple(HANG_W["L"] + [0.06, 0.18, 0.14]), wR=tuple(HANG_W["R"] + [-0.06, 0.18, 0.14])),
                K(6.0 / FPS, acc(0.0, 0.99), pel=(0.0, -0.117, -0.09), prot=(-12.0, 4.0, 0.0), ch=(-10.0, 3.0, 0.0),
                  fL=(0.0, 0.0, 0.0, 0.0, 14.0), fR=(0.0, 0.0, 0.0, 0.0, 14.0), gnd=1.0, rest=1.0),
                K(11.65 / FPS, acc(1.48, 0.68), **_fk_from(dict(pel=(0.0, -0.34, -0.26), prot=(-40.0, 5.0, 0.0),
                                                      ikf={"L": (0.0, 0.0, 0.02, 0.0, 10.0), "R": (0.0, 0.0, 0.02, 0.0, 10.0)},
                                                      shL=(-44.0, -6.0, 28.0), shR=(-40.0, -4.0, 26.0),
                                                      elL=40.0, elR=38.0, nk=(-14.0, 0.0, 0.0), hd=(-6.0, 0.0, 0.0),
                                                      sp=(-4.0, 0.0, 0.0), ch=(-6.0, 2.0, 0.0)))),
                K(17 / FPS, acc(1.79, 1.62), **hit),
                K(20 / FPS, "out", **_mix(hit, end, 0.6, rest=1.0)),
                K(24 / FPS, "out", **end)]
        return build(keys, n, "die_back", still_from=24), "back", "back"
    if kind == "fwd":
        n = 38
        end = _lie(PRONE, PRONE_ROT, -4.0, (0.0, -0.79, 0.40))
        hit = _fk_from(dict(pel=(0.0, -0.79, 0.38), prot=(87.7, -4.0, 0.0), hipL=(0.0, 14.0, 6.0), hipR=(2.0, 16.0, 6.0),
                            kneeL=84.0, kneeR=90.0, ankL=(10.0, 0.0, 0.0), ankR=(10.0, 0.0, 0.0), shL=(8.0, -14.0, 30.0),
                            shR=(10.0, -12.0, 30.0), elL=24.0, elR=26.0, nk=PRONE["nk"], hd=PRONE["hd"],
                            sp=(4.0, 0.0, 0.0), ch=(6.0, 0.0, 0.0)))
        keys = [K(0.0),
                K(0.10, "out", ch=(10.0, 0.0, 0.0), sp=(6.0, 0.0, 0.0), look=(14.0, 0.0, 0.0), pel=(0.0, -0.03, 0.03),
                  fL=(0.0, 0.0, 0.0, 0.0, 10.0), fR=(0.0, 0.0, 0.0, 0.0, 10.0)),
                K(7.87 / FPS, acc(0.0, 0.2), pel=(0.0, -0.094, 0.07), prot=(14.0, 0.0, 0.0), ch=(14.0, 0.0, 0.0), sp=(10.0, 0.0, 0.0),
                  fL=(0.0, 0.0, 0.0, 0.0, 22.0), fR=(0.0, 0.0, 0.0, 0.0, 22.0), gnd=1.0, rest=1.0,
                  wL=tuple(HANG_W["L"] + [0.0, 0.10, 0.18]), wR=tuple(HANG_W["R"] + [0.0, 0.10, 0.18])),
                K(12.6 / FPS, acc(1.56, 0.79), **_fk_from(dict(pel=(0.0, -0.34, 0.16), prot=(36.0, -2.0, 0.0),
                                                      ikf={"L": (0.0, 0.0, 0.08, 0.0, 36.0), "R": (0.0, 0.0, 0.08, 0.0, 36.0)},
                                                      shL=(-34.0, -10.0, 18.0), shR=(-32.0, -8.0, 18.0),
                                                      elL=30.0, elR=32.0, nk=(10.0, 0.0, 0.0), hd=(4.0, 0.0, 0.0),
                                                      sp=(8.0, 0.0, 0.0), ch=(10.0, 0.0, 0.0)))),
                K(13.22 / FPS, acc(2.94, 0.39), **_fk_from(dict(pel=(0.0, -0.50, 0.24), prot=(45.0, -3.0, 0.0), hipL=(-100.0, 6.0, 14.0),
                                                      hipR=(-100.0, 6.0, 14.0), kneeL=128.0, kneeR=128.0, ankL=(-6.0, 0.0, 0.0),
                                                      ankR=(-6.0, 0.0, 0.0)))),
                K(18 / FPS, acc(1.94, 1.07), **hit),
                K(21 / FPS, "out", **_mix(hit, end, 0.6, rest=1.0)),
                K(25 / FPS, "out", **end)]
        return build(keys, n, "die_fwd", still_from=25), "fwd", "front"
    if kind == "spin":
        n = 41
        end = _lie(SIDE, SIDE_ROT, 100.0, (0.25, -0.80, -0.15))
        hit = _fk_from(dict(pel=(0.25, -0.80, -0.15), prot=(6.8, 100.0, 82.5), hipL=(-90.0, 0.0, 10.0), hipR=(-96.0, 6.0, -14.0),
                            kneeL=124.0, kneeR=126.0, ankL=(-15.0, 0.0, 0.0), ankR=(-15.0, 0.0, 0.0), shL=(-40.0, -30.0, 10.0),
                            shR=SIDE["shR"], elL=50.0, elR=SIDE["elR"], nk=(8.0, 10.0, 18.0), hd=(2.0, 4.0, 6.0),
                            sp=(-2.0, 0.0, 2.0), ch=(6.0, 0.0, 2.0)))
        keys = [K(0.0),
                K(0.12, "out", ch=(-6.0, 16.0, 6.0), sp=(-3.0, 8.0, 4.0), look=(-6.0, 22.0, 6.0), prot=(-2.0, 14.0, 2.0),
                  pel=(0.02, -0.03, -0.02), wL=tuple(HANG_W["L"] + [0.12, 0.20, 0.0]), wR=tuple(HANG_W["R"] + [-0.06, 0.16, 0.16])),
                K(6.81 / FPS, acc(0.0, 1.13), prot=(-4.0, 34.0, 8.0), pel=(0.05, -0.152, 0.0), ch=(-4.0, 16.0, 8.0), look=(-6.0, 20.0, 6.0),
                  fL=(0.0, 0.0, 0.0, 0.0, 20.0), fR=(0.0, 0.0, 0.0, 0.0, 20.0), cL=None, cR=None),
                K(13.98 / FPS, acc(1.34, 0.46), prot=(0.0, 30.0, 30.6), pel=(0.04, -0.391, 0.0), ch=(0.0, 12.0, 8.0), look=(-2.0, 30.0, 10.0),
                  fL=(0.08, 0.0, -0.06, 38.0, 50.0), fR=(0.22, 0.0, 0.04, 38.0, 50.0), cL=None, cR=None, gnd=1.0, rest=1.0,
                  wL=tuple(HANG_W["L"] + [0.14, 0.24, 0.04]), wR=tuple(HANG_W["R"] + [-0.10, 0.20, 0.18])),
                K(20 / FPS, acc(2.33, 1.37), **hit),
                K(23 / FPS, "out", **_mix(hit, end, 0.6, rest=1.0)),
                K(27 / FPS, "out", **end)]
        return build(keys, n, "die_spin", still_from=27), "side", "side"
    # knees: ทรุดลงคุกเข่า เอนแล้วล้มคว่ำ (สั้นลง: นิ่งก่อน 1.4 วิ)
    n = 46
    end = _lie(PRONE, PRONE_ROT, 0.0, (0.0, -0.79, 0.50), nk=(2.0, 50.0, 0.0), hd=(2.0, 9.0, 4.0))
    hit = _fk_from(dict(prot=(87.7, 0.0, 0.0), pel=(0.0, -0.79, 0.50), hipL=(0.0, 14.0, 8.0), hipR=(2.0, 16.0, 8.0),
                        kneeL=84.0, kneeR=90.0, ankL=(30.0, 0.0, 0.0), ankR=(30.0, 0.0, 0.0), shL=(8.0, -14.0, 30.0),
                        shR=(10.0, -12.0, 28.0), elL=24.0, elR=26.0, nk=(2.0, 50.0, 0.0), hd=(2.0, 9.0, 4.0),
                        sp=(4.0, 0.0, 0.0), ch=(6.0, 0.0, 0.0)))
    kneel = dict(pel=(0.0, -0.40, 0.02), prot=(4.0, 0.0, 0.0), hipL=(-14.0, 6.0, 8.0), hipR=(-18.0, 4.0, 8.0), kneeL=118.0,
                 kneeR=114.0, ankL=(40.0, 0.0, 0.0), ankR=(38.0, 0.0, 0.0), shL=(-14.0, -8.0, 10.0), shR=(-12.0, -8.0, 10.0),
                 elL=24.0, elR=26.0, nk=(18.0, 0.0, 0.0), hd=(8.0, 0.0, 0.0))
    keys = [K(0.0),
            K(0.10, "out", ch=(8.0, 0.0, 0.0), look=(12.0, 0.0, 0.0), pel=(0.0, -0.03, 0.0)),
            K(6.96 / FPS, acc(0.0, 0.43), pel=(0.0, -0.052, 0.02), ch=(10.0, 0.0, 0.0), sp=(6.0, 0.0, 0.0),
              fL=(0.0, 0.0, 0.0, 0.0, 22.0), fR=(0.0, 0.0, 0.0, 0.0, 22.0), gnd=1.0, rest=1.0),
            K(11.41 / FPS, acc(2.2, 1.53), **_fk_from(dict(pel=(0.0, -0.33, 0.02), hipL=(-50.0, 6.0, 8.0), hipR=(-54.0, 4.0, 8.0),
                                                  kneeL=104.0, kneeR=108.0, ankL=(-20.0, 0.0, 0.0), ankR=(-20.0, 0.0, 0.0),
                                                  shL=(-16.0, -8.0, 10.0), shR=(-14.0, -8.0, 10.0), elL=22.0, elR=24.0,
                                                  nk=(14.0, 0.0, 0.0), hd=(6.0, 0.0, 0.0)))),
            K(15 / FPS, acc(2.2, 1.34), **_fk_from(kneel)),
            K(20 / FPS, "smooth", prot=(-2.0, 0.0, 3.0), ch=(4.0, 0.0, 2.0), nk=(22.0, 0.0, 4.0)),
            K(24.91 / FPS, acc(0.0, 1.76), prot=(20.9, 0.0, -2.0), ch=(10.0, 0.0, -2.0), nk=(26.0, 0.0, -4.0), hipL=(-20.0, 6.0, 8.0),
              hipR=(-24.0, 4.0, 8.0)),
            K(32 / FPS, acc(1.39, 1.88), **hit),
            K(35 / FPS, "out", **_mix(hit, end, 0.6, rest=1.0)),
            K(39 / FPS, "out", **end)]
    return build(keys, n, "die_knees", still_from=39), "knees", "front"


def clip_die_min(kind):
    """ระดับ min: ล้มแข็งทั้งร่าง 9 เฟรม แล้วนิ่ง (เฟรม 6..8 เท่ากัน) ไม่มีงานต่อเฟรมหลังจากนั้น ; ท่านอนเดียวกับท่าล้มเต็ม"""
    n = 9
    if kind == "back":
        end = _fk_from(_lie(SUPINE, SUPINE_ROT, 0.0, (0.0, -0.78, -0.72)))
    else:
        end = _fk_from(_lie(PRONE, PRONE_ROT, 0.0, (0.0, -0.79, 0.70)))
    start = _fk_from(dict(prot=(1.0, 0.0, 0.0), pel=(0.0, 0.0, 0.0), hipL=(-6.0, 0.0, 4.0), hipR=(-6.0, 0.0, 4.0),
                          kneeL=14.0, kneeR=14.0, ankL=(0.0, 0.0, 0.0), ankR=(0.0, 0.0, 0.0), shL=(-3.0, -6.0, 6.0),
                          shR=(-3.0, -6.0, 6.0), elL=14.0, elR=14.0, nk=(1.0, 0.0, 0.0), hd=(1.0, 0.0, 0.0)))
    # เฟรม 3: ร่างเอียง ~1/4 ทาง ข้อเท้างอให้ฝ่าเท้ายังราบ (หมุนรอบข้อเท้า ไม่เขย่งขึ้น)
    tip = _mix(start, end, 0.25, ankL=(-0.25 * end["prot"][0], 0.0, 0.0), ankR=(-0.25 * end["prot"][0], 0.0, 0.0))
    keys = [K(0.0, **start), K(3 / FPS, "linear", **tip), K(6 / FPS, "in", **end)]
    return build(keys, n, "die_min_" + kind, still_from=6), kind if kind == "back" else "fwd", "back" if kind == "back" else "front"
