# ท่าเคลื่อนที่ของทหาร (เท้าก่อน): วางเท้าบนพื้นจากความยาวขาและความเร็ว -> ส้น/ราบ/ปลายเท้า (heel/flat/ball)
# -> เชิงกรานลดลงให้ขาเอื้อมไม่เกิน 0.985 ของความยาวขา -> IK สองท่อน (ขา: ข้อเท้าตรงเป้า ; แขน: ข้อมือตรงเป้า)
# หน่วยเมตรของโครงเกม 1.6 ม. (S = 1: ร่างทั้ง 5 เล่นด้วย motion_scale = S) ; แกน Godot: +Y บน หน้า +Z ซ้าย +X
# quaternion [x, y, z, w] = การหมุนของกระดูกในกรอบพ่อ (แบบ Godot) ; ทุกอย่างกำหนดได้ซ้ำ (สุ่มด้วย seed เท่านั้น)
import numpy as np
import rig

FPS = 30
J = list(rig.MAIN)
PAR = dict(zip(rig.MAIN, rig._PAR))
OFF = {b: np.array(o, float) for b, o in zip(rig.MAIN, rig._OFF)}
THIGH = SHIN = 0.39
LEG = THIGH + SHIN
UPPER, FORE = 0.29, 0.235
REACH = 0.985               # ขา/แขนเอื้อมได้ไม่เกินเท่านี้ของความยาว (เข่าไม่ตึงสุด IK ไม่สะดุด)
ANKLE_H = 0.07
HEEL_P = OFF["heelL"]       # จุดส้นในกรอบข้อเท้า
BALL_P = OFF["toeL"]        # จุดโคนนิ้ว (ปลายเท้าที่แตะพื้น)
I4 = np.array([0.0, 0.0, 0.0, 1.0])
SIDES = (("L", 1.0), ("R", -1.0))


# ---------------- การหมุน ----------------

def Rx(a):
    c, s = np.cos(a), np.sin(a)
    return np.array([[1, 0, 0], [0, c, -s], [0, s, c]])


def Ry(a):
    c, s = np.cos(a), np.sin(a)
    return np.array([[c, 0, s], [0, 1, 0], [-s, 0, c]])


def Rz(a):
    c, s = np.cos(a), np.sin(a)
    return np.array([[c, -s, 0], [s, c, 0], [0, 0, 1]])


def qrv(x, y, z):
    """quaternion จากเวกเตอร์หมุน (องศา)"""
    v = np.radians([x, y, z])
    a = np.linalg.norm(v)
    if a < 1e-12:
        return I4.copy()
    return np.array([*(v / a * np.sin(a / 2)), np.cos(a / 2)])


def qst(x, y, z):
    """ข้อลูกกลม/ลำตัว: พับ (เวกเตอร์หมุน x, z) × บิดรอบแกน Y — แยกกลับได้ตรงแบบ limits_check.angles"""
    return rig.qmul(qrv(x, 0.0, z), qrv(0.0, y, 0.0))


def mirror_q(q):
    return np.array([q[0], -q[1], -q[2], q[3]])


def side_q(side, q):
    return q if side == "L" else mirror_q(q)


def mat(q):
    return rig.qmat(q)


def quat(m):
    return rig.matq(m)


def ease(t, kind="smooth"):
    t = float(np.clip(t, 0.0, 1.0))
    if kind == "linear":
        return t
    if kind == "in":
        return t * t
    if kind == "out":
        return 1 - (1 - t) * (1 - t)
    if kind == "in3":
        return t * t * t
    if kind == "out3":
        return 1 - (1 - t) ** 3
    if kind == "minjerk":
        return t * t * t * (10 - 15 * t + 6 * t * t)
    return t * t * (3 - 2 * t)


# ---------------- FK ----------------

def fk(L, ppos, tpos=None):
    """L = กระดูก -> quaternion (กรอบพ่อ) ; คืน กระดูก -> (R 3x3, ตำแหน่ง) ในกรอบหุ่น"""
    G = {}
    for b in J:
        R = mat(L[b])
        p = PAR[b]
        off = tpos[b] if tpos is not None and b in tpos else OFF[b]
        if p is None:
            G[b] = (R, np.asarray(ppos, float))
        else:
            Rp, tp = G[p]
            G[b] = (Rp @ R, tp + Rp @ off)
    return G


# ---------------- IK สองท่อน ----------------

def _perp(v, w):
    p = v - np.dot(v, w) * w
    n = np.linalg.norm(p)
    return p / n if n > 1e-9 else None


def leg_ik(Rp, ppos, side, ankle, Rfoot, pole, reach=REACH):
    """ขา: ข้อเท้าไปที่ ankle (กรอบหุ่น) เข่าชี้ทาง pole ; คืน quaternion ของ hip/knee/ankle และ reach (ระยะ/ความยาวขา)
    reach = เพดานการเอื้อม (ท่าเดิน/วิ่งให้เข่าเกือบตึงตอนแตะได้)"""
    hip = ppos + Rp @ OFF["hip" + side]
    d = ankle - hip
    dist = np.linalg.norm(d)
    w = d / dist
    lc = min(dist, reach * LEG)
    pv = _perp(pole, w)
    if pv is None:
        pv = _perp(np.array([0.0, 0.0, 1.0]), w)
    ca = np.clip((THIGH ** 2 + lc ** 2 - SHIN ** 2) / (2 * THIGH * lc), -1, 1)
    u = ca * w + np.sqrt(1 - ca * ca) * pv
    knee = hip + THIGH * u
    s = (hip + lc * w - knee) / SHIN
    Z = _perp(pv, u)
    Y = -u
    X = np.cross(Y, Z)
    Rth = np.column_stack([X, Y, Z])
    th = np.arccos(np.clip(np.dot(u, s), -1, 1))
    Rsh = Rth @ Rx(th)
    return {"hip": quat(Rp.T @ Rth), "knee": rig.qaxis([1, 0, 0], np.degrees(th)), "ankle": quat(Rsh.T @ Rfoot),
            "reach": dist / LEG, "Rsh": Rsh, "knee_pos": knee}


def soft_reach(Rp, ppos, side, ankle, reach, s, scap, w=0.006):
    """ขาแกว่ง: ดึงเป้าข้อเท้าเข้าหาสะโพกด้วยเพดานนุ่ม (softplus กว้าง w) ที่ยกขึ้นปลายแกว่ง
    scap = (เพดานต่ำสุด, เพดานตอนแตะ, เริ่มที่ phs) : เข่าค่อย ๆ เหยียดถึงตอนแตะ ไม่ดีดตึงค้าง ; คืนเป้าใหม่ (ใช้กับ reach 1.0)"""
    hip = ppos + Rp @ OFF["hip" + side]
    d = ankle - hip
    r = np.linalg.norm(d) / LEG
    lo, hi, s0 = scap
    cap = reach if s < s0 else min(reach, lo + (hi - lo) * ease((s - s0) / (1 - s0)))
    return hip + d * ((cap - w * np.logaddexp(0.0, (cap - r) / w)) / r)


def arm_ik(side, wrist, pole):
    """แขนในกรอบอก: ข้อมือไปที่ wrist ศอกยื่นไปทาง pole ; ศอกงออย่างเดียว (ไม่บิด: ช่วงศอก z ±5°)"""
    sh = OFF["shoulder" + side]
    d = wrist - sh
    dist = max(np.linalg.norm(d), 1e-6)
    w = d / dist
    lc = float(np.clip(dist, abs(UPPER - FORE) + 0.03, REACH * (UPPER + FORE)))
    pv = _perp(pole, w)
    if pv is None:
        pv = _perp(np.array([0.0, -1.0, 0.0]), w)
    ca = np.clip((UPPER ** 2 + lc ** 2 - FORE ** 2) / (2 * UPPER * lc), -1, 1)
    u = ca * w + np.sqrt(1 - ca * ca) * pv
    elbow = sh + UPPER * u
    f = (sh + lc * w - elbow) / FORE
    Z = _perp(f, u)
    if Z is None:
        Z = -_perp(pv, u)
    Y = -u
    X = np.cross(Y, Z)
    th = np.arccos(np.clip(np.dot(u, f), -1, 1))
    return {"shoulder": quat(np.column_stack([X, Y, Z])), "elbow": rig.qaxis([1, 0, 0], -np.degrees(th)),
            "reach": dist / (UPPER + FORE)}


def look(Rchest, pitch, yaw, roll, k_neck=0.75):
    """คอ/หัว: หัวหันตามมุม (องศา, กรอบหุ่น: pitch + = ก้ม, yaw + = ซ้าย) คอรับส่วนใหญ่"""
    tgt = Ry(np.radians(yaw)) @ Rx(np.radians(pitch)) @ Rz(np.radians(roll))
    qrel = quat(Rchest.T @ tgt)
    qn = rig.qslerp(I4, qrel, k_neck)
    qh = rig.qmul(rig.qinv(qn), qrel)
    return rig.qnorm(qn), rig.qnorm(qh)


def foot_R(yaw, pitch, roll=0.0):
    return Ry(yaw) @ Rx(pitch) @ Rz(roll)


def ankle_from_contact(point, pt_local, Rf):
    """ตำแหน่งข้อเท้าเมื่อจุด pt_local (กรอบข้อเท้า) ของเท้าที่หมุน Rf อยู่ที่ point บนพื้น"""
    return point - Rf @ pt_local


# ---------------- เชิงกรานลด ----------------

def pelvis_limit(ppos_xz, Rp, ankles, reach=REACH):
    """ความสูงเชิงกรานสูงสุดที่ขาทั้งสองเอื้อมไม่เกิน reach (ankles = {side: ตำแหน่ง})"""
    lim = 9.0
    rr = (reach * LEG) ** 2
    for side, a in ankles.items():
        o = Rp @ OFF["hip" + side]
        dx = ppos_xz[0] + o[0] - a[0]
        dz = ppos_xz[1] + o[2] - a[2]
        h2 = rr - dx * dx - dz * dz
        if h2 <= 0:
            lim = min(lim, a[1] - o[1])     # เอื้อมไม่ถึงในแนวนอน: ต่ำสุดที่ข้อเท้า (ประตูจะเห็น)
        else:
            lim = min(lim, a[1] + np.sqrt(h2) - o[1])
    return lim


def smooth_under(y, lim, loop, sigma=1.4, rounds=40, margin=0.0015):
    """เส้นเรียบที่ไม่เกิน lim: ส่วนที่ต้องลด (y - lim) ขยายกว้างแล้วกรองเรียบ เชิงกรานลงเฉพาะช่วงที่ขาเอื้อมไม่ถึง
    แล้วกลับขึ้น (rounds ไม่ใช้แล้ว เก็บไว้ให้เรียกแบบเดิมได้)"""
    lim = np.asarray(lim, float) - margin
    y = np.asarray(y, float)
    dfc = np.maximum(y - lim, 0.0)
    n = len(y)
    r = max(1, int(np.ceil(1.5 * sigma)))
    pad = lambda a, m: np.concatenate([a[-m:], a, a[:m]]) if loop else np.concatenate([np.full(m, a[0]), a, np.full(m, a[-1])])
    dp = pad(dfc, r) if n > r else np.tile(dfc, 3)[n - r:2 * n + r]
    dil = np.array([dp[i:i + 2 * r + 1].max() for i in range(n)])
    rk = int(np.ceil(3 * sigma))
    k = np.exp(-0.5 * (np.arange(-rk, rk + 1) / sigma) ** 2)
    k /= k.sum()
    dp = pad(dil, rk) if n > rk else np.tile(dil, 3)[n - rk:2 * n + rk]
    sm = np.convolve(dp, k, mode="valid")
    return y - np.maximum(sm, dfc)


# ---------------- ส่วนบน (ใช้ร่วมกับ actions.py) ----------------

def upper_body(G_spine_R, L, sp, ch, look_pyr, k_neck=0.75):
    """sp/ch = (x, y, z) องศาของกระดูกสันหลัง/อก ; look_pyr = มุมหัวในกรอบหุ่น ; เติม L และคืนเมทริกซ์อก"""
    L["spine"] = qst(*sp)
    L["chest"] = qst(*ch)
    Rc = G_spine_R @ mat(L["spine"]) @ mat(L["chest"])
    L["neck"], L["head"] = look(Rc, *look_pyr, k_neck=k_neck)
    return Rc


def arms_fk(L, side, sh, el, wr=(0.0, 0.0)):
    """แขนแบบมุม (องศา, เขียนเป็นข้างซ้าย ข้างขวาสะท้อนเอง): sh = (x, y, z) ไหล่ ; el = งอศอก ; wr = (พับ, เอียง) ข้อมือ"""
    L["shoulder" + side] = side_q(side, qst(*sh))
    L["elbow" + side] = rig.qaxis([1, 0, 0], -el)
    L["wrist" + side] = side_q(side, qrv(wr[0], 0.0, wr[1]))
    L["hand" + side] = I4.copy()


# ---------------- คลิปเดิน/วิ่ง ----------------
# ค่าของแต่ละท่า: v ความเร็ว (ม./วิ ของโครง), n เฟรมต่อรอบ (สองก้าว), beta สัดส่วนเวลาที่เท้าแตะพื้น,
# land heel/ball, phases = สัดส่วนช่วงในการแตะ [แตะแรก, ราบ, ปลายเท้า], width ครึ่งระยะเท้า, out เท้าแบะ (องศา),
# td/to มุมเท้าตอนแตะ/ตอนยก (องศา + = ส้นยก), to_exp ส้นยกเร่งตอนท้าย, rho สัดส่วนระยะหน้าสะโพกตอนแตะ,
# h0 เชิงกรานสูงสุดกลางช่วงลอย (วิ่ง), pel_y จุดต่ำสุด/สูงสุดของเชิงกรานต่อก้าว (ท่าเดิน: สัดส่วนก้าว, ม.),
# stiff ความแข็งขาตอนแตะ (วิ่ง), reach/sreach เพดานเอื้อมของขาแตะ/ขาแกว่ง, psig ความกว้างที่กดเชิงกรานลงตามระยะเอื้อม,
# sw_e เส้นทางเท้าแกว่ง, scap เพดานเอื้อมนุ่มของขาแกว่ง (ต่ำสุด, ตอนแตะ, เริ่มที่ phs: ดู soft_reach),
# lift/peak ยกเท้าตอนแกว่ง, pel (หมุน y, เอียง z, ก้ม x องศา), sway เลื่อนข้าง, lean (สันหลัง, อก องศา),
# counter บิดอกสวน, arm (แกว่ง, ไหล่ตั้งต้น, กาง), arm_ph เฟสแขน/อก (เรเดียน), elbow (งอ, งอเพิ่มตอนแขนหน้า), head ก้ม
GAITS = {
    "walk": dict(v=1.30, n=35, beta=0.56, land="heel", phases=[0.15, 0.39, 0.46], width=0.092, out=7.0, td=-23.0,
                 to=59.5, to_exp=2.2, rho=0.435, pel_y=(0.015, 0.8507, 0.45, 0.8927), reach=0.9993, psig=0.8, lift=0.06,
                 peak=0.24, pel=(5.0, 3.5, 2.0), sway=0.018, land_win=0.97, lean=(2.0, 1.0), counter=5.0, arm=(19.0, 5.0, 9.0),
                 arm_ph=-0.5, elbow=(18.0, 14.0), head=2.0, swing_neutral=4.0, scap=(0.95, 0.9985, 0.55)),
    "jog": dict(v=3.0 / rig.S, n=22, beta=0.34, land="heel", phases=[0.14, 0.20, 0.66], width=0.060, out=5.0, td=-15.0,
                to=50.0, to_exp=1.13, rho=0.30, h0=0.907, reach=0.999, psig=0.8, lift=0.16, peak=0.32, pel=(8.0, 3.0, 5.0),
                sway=0.010, land_win=0.95, lean=(5.0, 2.5), counter=9.0, arm=(32.0, 4.0, 11.0), arm_ph=-1.14, elbow=(78.0, 16.0), head=3.0,
                swing_neutral=12.0, scap=(0.95, 0.998, 0.6)),
    "run": dict(v=5.0 / rig.S, n=20, beta=0.27, land="ball", phases=[0.15, 0.18, 0.67], width=0.050, out=4.0, td=15.0,
                to=59.5, to_exp=1.41, rho=0.493, h0=0.901, stiff=0.5, reach=0.999, sreach=0.99, psig=0.8, lift=0.226, peak=0.28,
                sw_e=0.85, pel=(10.0, 3.0, 3.0), sway=0.008, land_win=1.0, lean=(8.0, 3.5), counter=13.0, arm=(48.0, 2.0, 12.0), arm_ph=-1.7, elbow=(88.0, 18.0), head=4.0,
                swing_neutral=18.0, scap=(0.93, 0.993, 0.55)),
}


def _stance_state(g, phs):
    """สถานะเท้าในช่วงแตะ (phs 0..1): (ชนิดการแตะ, มุมเท้า องศา, จุดที่ตรึง heel/ball)"""
    p1, p2, _ = g["phases"]
    if phs < p1:
        f = ease(phs / p1, "out")
        return ("heel" if g["land"] == "heel" else "ball"), g["td"] * (1 - f), ("heel" if g["land"] == "heel" else "ball")
    if phs < p1 + p2:
        return "flat", 0.0, "flat"
    f = ((phs - p1 - p2) / (1 - p1 - p2)) ** g.get("to_exp", 0.85)     # to_exp > 1: ส้นยกช้าก่อนแล้วเร็วตอนท้าย
    return "ball", g["to"] * f, "ball"


def gait_clip(name, seed=1):
    g = GAITS[name]
    n, v, beta = g["n"], g["v"], g["beta"]
    T = n / FPS
    stride = v * T
    # ระยะที่ลำตัวเคลื่อนผ่านเท้าระหว่างแตะ = จุดแตะแรกหน้าสะโพก + ช่วงส้นถึงโคนนิ้ว (ลงส้น) + จุดยกหลังสะโพก
    span = BALL_P[2] - HEEL_P[2] if g["land"] == "heel" else 0.0
    exc = v * beta * T - span
    d_td = exc * g["rho"]
    frames = []
    contact = {"L": [], "R": []}
    # เท้าแต่ละข้าง: เวลาลงเท้า (ขวาลงที่ t = 0, ซ้ายครึ่งรอบ)
    t_td = {"R": 0.0, "L": T / 2}
    for k in range(n):
        t = k / FPS
        frames.append(_gait_frame(g, name, t, T, stride, d_td, t_td, contact))
    return frames, contact, {"T": T, "stride": stride, "d_td": d_td, "exc": exc}


def _foot_world(g, side, t, T, stride, d_td, t_td):
    """ตำแหน่ง/การหมุนของเท้าในกรอบโลก (หุ่นเดินไป +Z ด้วยความเร็ว v เริ่มที่ 0) ; คืน (ข้อเท้า, Rf, ชนิดการแตะ, phs, ช่วง)"""
    v, beta = g["v"], g["beta"]
    sx = 1.0 if side == "L" else -1.0
    yaw = np.radians(g["out"]) * sx
    x0 = g["width"] * sx
    span = BALL_P[2] - HEEL_P[2] if g["land"] == "heel" else 0.0
    # รอบของเท้านี้: เวลาตั้งแต่ลงเท้าครั้งล่าสุด
    ph = (t - t_td[side]) % T
    i = np.floor((t - t_td[side]) / T)
    tdn = t_td[side] + i * T                       # เวลาลงเท้าครั้งนี้
    land_pt = "heel" if g["land"] == "heel" else "ball"
    lp = HEEL_P if land_pt == "heel" else BALL_P

    def contact_point(tdk):
        # จุดแตะแรก (ส้นหรือโคนนิ้ว) ในกรอบโลกของการลงเท้าที่เวลา tdk: อยู่หน้าสะโพก d_td
        z = v * tdk + d_td
        return np.array([x0, 0.0, z])

    def stance_pose(tdk, phs):
        kind, pitch, pin = _stance_state(g, phs)
        Rf = foot_R(yaw, np.radians(pitch))
        cp = contact_point(tdk)
        if pin == "heel" or (pin == "flat" and land_pt == "heel"):
            if pin == "flat":
                a = ankle_from_contact(cp, HEEL_P, foot_R(yaw, 0.0))
            else:
                a = ankle_from_contact(cp, HEEL_P, Rf)
        else:
            # จุดโคนนิ้วที่ตรึง: ลงส้น = โคนนิ้วตอนเท้าราบ ; ลงปลายเท้า = จุดแตะแรก
            if land_pt == "heel":
                flat_a = ankle_from_contact(cp, HEEL_P, foot_R(yaw, 0.0))
                bp = flat_a + foot_R(yaw, 0.0) @ BALL_P
            else:
                bp = cp
            a = ankle_from_contact(bp, BALL_P, Rf)
        return a, Rf, kind

    if ph < beta * T:
        phs = ph / (beta * T)
        a, Rf, kind = stance_pose(tdn, phs)
        return a, Rf, kind, phs, "stance", 0.0
    # แกว่ง: จากท่ายกเท้า (phs = 1 ของรอบนี้) ไปท่าลงเท้าครั้งถัดไป
    a0, R0, _ = stance_pose(tdn, 1.0)
    a1, R1, _ = stance_pose(tdn + T, 0.0)
    s = (ph - beta * T) / ((1 - beta) * T)
    e = ease(s ** g.get("sw_e", 1.0))              # เท้าผ่านใต้สะโพกกลางช่วงแกว่ง ถึงจุดลงตอนแตะพอดี (sw_e < 1: ไปหน้าเร็วขึ้นต้นช่วง)
    a = a0 + (a1 - a0) * e
    p, q_ = g["peak"], 1.0 - g["peak"]
    bump = (s ** (p * 2.4)) * ((1 - s) ** (q_ * 2.4))
    bump /= (p ** (p * 2.4)) * (q_ ** (q_ * 2.4))
    a = a + np.array([sx * 0.012 * np.sin(np.pi * s), g["lift"] * bump, 0.0])
    return a, (R0, R1), None, s, "swing", e


def _gait_frame(g, name, t, T, stride, d_td, t_td, contact):
    v = g["v"]
    w2 = 2 * np.pi * t / T
    yaw_a, roll_a, tilt = g["pel"]
    # เชิงกราน: หมุนตามขาที่แกว่งหน้า (ขวาลงที่ t = 0 = สะโพกขวาหน้า = หมุนไปซ้าย)
    Rp = Ry(np.radians(yaw_a * np.cos(w2))) @ Rx(np.radians(tilt)) @ Rz(np.radians(-roll_a * np.sin(w2)))
    px = -g["sway"] * np.sin(w2)
    feet = {}
    for side, sx in SIDES:
        a, Rf, kind, phs, mode, e = _foot_world(g, side, t, T, stride, d_td, t_td)
        a = a - np.array([0.0, 0.0, v * t])            # ในที่: โหนดเดินไปเอง
        feet[side] = (a, Rf, kind, phs, mode, e)
        contact[side].append(kind)
    return {"Rp": Rp, "px": px, "feet": feet, "t": t, "w2": w2}


def pelvis_wave(g, t, T):
    """ความสูงเชิงกรานที่ออกแบบ (ก่อนกดตามระยะเอื้อม): เดิน = ต่ำสุด/สูงสุดต่อก้าว (pel_y) เชื่อมด้วยครึ่งคลื่นโคไซน์ ;
    วิ่ง = ลอยแบบวิถีโค้งตามแรงโน้มถ่วง (สูงสุดกลางช่วงลอย = h0) + ยุบครึ่งไซน์ตอนแตะ ความเร็วต่อเนื่องที่ลงเท้า/ยกเท้า"""
    if "pel_y" in g:
        pt, yt, pp, yp = g["pel_y"]          # (สัดส่วนก้าวนับจากลงส้น, ความสูง) ของจุดต่ำสุดและสูงสุด
        ph = (t % (T / 2)) / (T / 2)
        if pt <= ph < pp:
            a, ya, b, yb = pt, yt, pp, yp
        else:
            a, ya, b, yb = pp, yp, pt + 1.0, yt
            ph = ph if ph >= pp else ph + 1.0
        return ya + (yb - ya) * (1 - np.cos(np.pi * (ph - a) / (b - a))) / 2
    half = T / 2
    ts = g["beta"] * T                 # เวลาแตะ
    v0 = 9.81 * (half - ts) / 2        # ความเร็วขึ้นตอนยกเท้า = ลงตอนแตะ
    y_td = g["h0"] - v0 * v0 / (2 * 9.81)
    tn = t % half
    if tn < ts:
        # ช่วงแตะ: โค้งโคไซน์ ±stiff เรเดียน (pi/2 = ครึ่งไซน์ ; น้อยลง = ขาแข็งขึ้น ยุบน้อยลง) ความเร็วต่อกับช่วงลอย
        th = g.get("stiff", np.pi / 2)
        w = 2 * th / ts
        A = v0 / (w * np.sin(th))
        return y_td + A * np.cos(th) - A * np.cos(w * (tn - ts / 2))
    u = tn - ts
    return y_td + v0 * u - 4.905 * u * u


def build_gait(name, seed=1):
    """คลิปเดิน/วิ่งในที่: คืน dict ของ q[กระดูก][เฟรม], t[pelvis][เฟรม], contact, meta"""
    g = GAITS[name]
    frames, contact, info = gait_clip(name, seed)
    n = len(frames)
    T = info["T"]
    # เชิงกราน: เส้นที่ออกแบบไว้ (pelvis_wave) กดลงเฉพาะช่วงที่ขาเอื้อมไม่ถึง (ใช้ข้อเท้าทั้งสองในเฟรมนั้น)
    y_lim = np.zeros(n)
    y_des = np.zeros(n)
    for k, fr in enumerate(frames):
        # เท้าที่แตะพื้น + เท้าที่ใกล้ลง (10 % ท้ายของการแกว่ง: ลงเท้าไม่กระตุก) ; เท้าแกว่งที่เหลืองอเข่าเอง
        ank = {s: fr["feet"][s][0] for s in "LR" if fr["feet"][s][4] == "stance" or fr["feet"][s][3] > g["land_win"]}
        y_lim[k] = pelvis_limit((fr["px"], 0.0), fr["Rp"], ank, g["reach"]) if ank else 9.0
        y_des[k] = pelvis_wave(g, fr["t"], T)
    y = smooth_under(y_des, y_lim, loop=True, sigma=g["psig"], margin=0.0005)
    q = {b: [] for b in J}
    tp = []
    reach = 0.0
    for k, fr in enumerate(frames):
        L = {b: I4.copy() for b in J}
        Rp = fr["Rp"]
        ppos = np.array([fr["px"], y[k], 0.0])
        L["pelvis"] = quat(Rp)
        for side, sx in SIDES:
            a, Rf, kind, phs, mode, e = fr["feet"][side]
            yaw = np.radians(g["out"]) * sx
            pole = Ry(yaw) @ np.array([0.0, 0.0, 1.0])
            if mode == "stance":
                r = leg_ik(Rp, ppos, side, a, Rf, pole, g["reach"])
                Rfoot = Rf
            else:
                R0, R1 = Rf
                sr = g.get("sreach", g["reach"])     # sreach: เข่างอค้างปลายแกว่ง (วิ่ง)
                at = a
                if "scap" in g:                      # เพดานนุ่ม: เข่าไม่ดีดตึงค้างก่อนแตะ
                    at, sr = soft_reach(Rp, ppos, side, a, sr, phs, g["scap"]), 1.0
                r = leg_ik(Rp, ppos, side, at, R0, pole, sr)
                Rmid = r["Rsh"] @ Rx(np.radians(g["swing_neutral"]))
                s = phs
                Rfoot = mat(rig.qslerp(quat(R0), quat(Rmid), ease(s / 0.35)))
                Rfoot = mat(rig.qslerp(quat(Rfoot), quat(R1), ease((s - 0.55) / 0.45)))
                r["ankle"] = quat(r["Rsh"].T @ Rfoot)
            reach = max(reach, r["reach"])
            L["hip" + side], L["knee" + side], L["ankle" + side] = r["hip"], r["knee"], r["ankle"]
            # นิ้วเท้า: ช่วงปลายเท้าแตะ นิ้ววางราบกับพื้น ; แกว่ง ค่อย ๆ คืน
            pitch_g = _pitch_of(Rfoot, yaw)
            if mode == "stance" and kind == "ball" and pitch_g > 0:
                toe = -pitch_g
            elif mode == "swing":
                toe = -max(0.0, _pitch_of(R0, yaw)) * (1 - ease(phs / 0.4))
            else:
                toe = 0.0
            L["toe" + side] = rig.qaxis([1, 0, 0], toe)
        w2 = fr["w2"]
        Gp = Rp
        lean_s, lean_c = g["lean"]
        cnt = g["counter"]
        yaw_p = g["pel"][0] * np.cos(w2)
        # อกบิดสวนเชิงกราน (ไหล่ซ้ายหน้าเมื่อขาขวาหน้า) ; ลำตัวเอียงข้างชดเชยเชิงกรานเอียง
        # arm_ph: เฟสแขน/อกของแต่ละท่า (วิ่ง: ขาแยกสุดตอนยกเท้า แขนจึงนำเร็วกว่าเดิน ให้สวนขาพอดี)
        aph = g["arm_ph"]
        sp = (lean_s - g["pel"][2] * 0.6, -(yaw_p + cnt * np.cos(w2 - aph)) * 0.45, g["pel"][1] * 0.5 * np.sin(w2))
        ch = (lean_c + 0.8 * np.cos(2 * w2), -(yaw_p + cnt * np.cos(w2 - aph)) * 0.55, g["pel"][1] * 0.4 * np.sin(w2))
        upper_body(Gp, L, sp, ch, (g["head"] + 0.6 * np.cos(2 * w2), 0.0, 0.0))
        amp, sh0, abd = g["arm"]
        el0, el1 = g["elbow"]
        lag = 0.45 + aph
        for side, sx in SIDES:
            # แขนซ้ายหน้าเมื่อขาขวาหน้า (t = 0) ; หน้า = x ลบ
            c = np.cos(w2 - lag) * (1.0 if side == "L" else -1.0)
            shx = sh0 - amp * c
            el = el0 + el1 * max(0.0, c) + 4.0 * np.sin(w2 * 2)
            arms_fk(L, side, (shx, -4.0, abd + 2.0 * max(0.0, c)), el, (-6.0, -3.0))
        for b in J:
            q[b].append(L[b])
        tp.append(ppos)
    return {"q": q, "t": {"pelvis": tp}, "contact": contact, "frames": n, "length": T, "loop": True,
            "speed": g["v"], "info": dict(info, reach=reach, y=[float(min(y)), float(max(y))], cadence=120.0 / T)}


def _pitch_of(Rf, yaw):
    """มุมก้มของเท้า (องศา, + = ส้นยก) จากการหมุน Rf (ตัดการแบะออก)"""
    f = Ry(-yaw) @ Rf @ np.array([0.0, 0.0, 1.0])
    return float(np.degrees(np.arctan2(-f[1], f[2])))


# ---------------- ยืนพัก / หมุนตัวในที่ ----------------
STANCE = dict(width=0.105, out=8.0, z=0.0, h0=0.889)


def stance_feet():
    out = {}
    for side, sx in SIDES:
        yaw = np.radians(STANCE["out"]) * sx
        Rf = foot_R(yaw, 0.0)
        out[side] = (np.array([STANCE["width"] * sx, ANKLE_H, STANCE["z"]]), Rf, yaw)
    return out


def periodic_noise(rng, n_harm, T, amp):
    """สัญญาณเรียบวนรอบ T (ฮาร์มอนิก 1..n สุ่มด้วย seed)"""
    a = rng.normal(0, 1, n_harm) / np.arange(1, n_harm + 1)
    ph = rng.uniform(0, 2 * np.pi, n_harm)
    s = np.sqrt((a ** 2).sum() / 2) + 1e-9
    return lambda t: amp * sum(a[i] * np.sin(2 * np.pi * (i + 1) * t / T + ph[i]) for i in range(n_harm)) / s


def solve_legs(L, Rp, ppos, feet, poles=None):
    reach = 0.0
    knees = {}
    for side, sx in SIDES:
        a, Rf, yaw = feet[side]
        pole = poles[side] if poles else Ry(yaw) @ np.array([0.0, 0.0, 1.0])
        r = leg_ik(Rp, ppos, side, a, Rf, pole)
        L["hip" + side], L["knee" + side], L["ankle" + side] = r["hip"], r["knee"], r["ankle"]
        L["toe" + side] = I4.copy()
        reach = max(reach, r["reach"])
        knees[side] = r["knee_pos"]
    return reach, knees


def build_idle(seed=11):
    """ยืนพัก 6 วิ วนรอบ: หายใจ 2 ครั้ง ทิ้งน้ำหนักซ้าย-ขวา 1 รอบ หัวมองช้า ๆ (สุ่มด้วย seed) ; เท้าราบตลอด
    คีย์ 0 (ท่านิ่งของ min / ดาดฟ้า lo) ใกล้ท่าพักเดิมของ humanoid: น้ำหนักอยู่ขาซ้าย หัวหันขวาเล็กน้อย ต้นแขนบิดเข้า"""
    n, T = 180, 6.0
    rng = np.random.default_rng(seed)
    head_y = periodic_noise(rng, 3, T, 5.0)
    head_p = periodic_noise(rng, 2, T, 1.5)
    arm_n = periodic_noise(rng, 2, T, 1.2)
    feet = stance_feet()
    q = {b: [] for b in J}
    tp, tch, tsl, tsr = [], [], [], []
    rows = []
    for k in range(n):
        t = k / FPS
        ws = np.cos(2 * np.pi * t / T)                 # ทิ้งน้ำหนัก: + = ไปขาซ้าย (เริ่มที่ขาซ้ายแบบท่าพักเดิม)
        br = 0.5 - 0.5 * np.cos(2 * np.pi * 2 * t / T)  # หายใจเข้า 0..1
        Rp = Ry(np.radians(1.5 * ws)) @ Rx(np.radians(1.0)) @ Rz(np.radians(1.8 * ws))
        px = 0.016 * ws
        rows.append((t, ws, br, Rp, px))
    y_lim = np.array([pelvis_limit((r[4], 0.0), r[3], {s: feet[s][0] for s in "LR"}) for r in rows])
    y = smooth_under(np.full(n, STANCE["h0"]) - 0.003 * np.abs(np.array([r[1] for r in rows])), y_lim, loop=True)
    for k, (t, ws, br, Rp, px) in enumerate(rows):
        L = {b: I4.copy() for b in J}
        ppos = np.array([px, y[k], 0.0])
        L["pelvis"] = quat(Rp)
        solve_legs(L, Rp, ppos, feet)
        upper_body(Rp, L, (2.0 - 0.4 * br, -0.8 * ws, -1.2 * ws), (-0.6 - 1.1 * br, -0.6 * ws, -0.9 * ws),
                   (2.0 + head_p(t + 1.5), head_y(t + 1.5), -0.8 * ws))
        for side, sx in SIDES:
            arms_fk(L, side, (-3.0 + arm_n(t) * sx, -10.0, 6.0 + 0.8 * br), 14.0 + arm_n(t) * 0.5, (-8.0, -4.0))
        for b in J:
            q[b].append(L[b])
        tp.append(ppos)
        tch.append(OFF["chest"] + np.array([0.0, 0.0012 * br, 0.0015 * br]))
        tsl.append(OFF["shoulderL"] + np.array([0.0, 0.0025 * br, -0.001 * br]))
        tsr.append(OFF["shoulderR"] + np.array([0.0, 0.0025 * br, -0.001 * br]))
    return {"q": q, "t": {"pelvis": tp, "chest": tch, "shoulderL": tsl, "shoulderR": tsr},
            "contact": {"L": ["flat"] * n, "R": ["flat"] * n}, "frames": n, "length": T, "loop": True, "speed": 0.0}


TURN = dict(n=18, rate=np.radians(150.0), beta=0.60, lift=0.05)


def build_turn(direction=1.0):
    """หมุนตัวในที่แบบก้าวเท้า: โหนดหมุน rate (rad/s, + = ซ้าย) ระหว่างเล่น เท้าที่แตะพื้นอยู่กับที่ในโลก
    (ในกรอบหุ่นหมุนสวน) แล้วยกไปวางใหม่สลับกัน ; วนรอบ"""
    n, beta = TURN["n"], TURN["beta"]
    T = n / FPS
    w = TURN["rate"] * direction
    feet0 = stance_feet()
    q = {b: [] for b in J}
    tp = []
    contact = {"L": [], "R": []}
    half = w * beta * T / 2
    rows = []
    for k in range(n):
        t = k / FPS
        feet = {}
        for side, sx in SIDES:
            # เท้านำ (ทางที่หมุน) ยกก่อนที่ t = 0: ซ้ายนำเมื่อหมุนซ้าย ; เท้าตามยกครึ่งรอบหลังจากนั้น
            lead = (side == "L") == (direction > 0)
            t0 = (0.0 if lead else T / 2) - beta * T
            ph = (t - t0) % T
            a0, Rf0, yaw0 = feet0[side]
            if ph < beta * T:
                ang = half - w * ph                     # วางล่วงหน้าครึ่งหนึ่ง แล้วหมุนสวนในกรอบหุ่น
                kind, lift = "flat", 0.0
            else:
                s = (ph - beta * T) / ((1 - beta) * T)
                ang = -half + 2 * half * ease(s, "minjerk")
                kind, lift = None, TURN["lift"] * np.sin(np.pi * s) ** 1.5
            Ra = Ry(ang)
            a = Ra @ (a0 - np.array([0, ANKLE_H, 0])) + np.array([0, ANKLE_H + lift, 0])
            pitch = np.radians(14.0) * (lift / TURN["lift"])
            feet[side] = (a, Ra @ Rf0 @ Rx(pitch), yaw0 + ang)
            contact[side].append(kind)
        rows.append((t, feet))
    Rp = Ry(np.radians(4.0 * direction)) @ Rx(np.radians(2.0))
    y_lim = np.array([pelvis_limit((0.0, 0.0), Rp, {s: r[1][s][0] for s in "LR"}) for r in rows])
    bob = np.array([0.006 * (1 - np.cos(4 * np.pi * r[0] / T)) for r in rows])
    y = smooth_under(STANCE["h0"] - bob, y_lim, loop=True)
    for k, (t, feet) in enumerate(rows):
        L = {b: I4.copy() for b in J}
        ppos = np.array([0.0, y[k], 0.0])
        L["pelvis"] = quat(Rp)
        solve_legs(L, Rp, ppos, feet)
        # ลำตัวนำการหมุน หัวมองไปทางที่หมุน
        upper_body(Rp, L, (2.0, 3.0 * direction, 0.0), (0.5, 4.0 * direction, 0.0), (3.0, 14.0 * direction, 0.0))
        for side, sx in SIDES:
            sw = 4.0 * np.sin(2 * np.pi * t / T) * sx
            arms_fk(L, side, (-4.0 + sw, -6.0, 10.0), 18.0, (-4.0, -4.0))
        for b in J:
            q[b].append(L[b])
        tp.append(ppos)
    return {"q": q, "t": {"pelvis": tp}, "contact": contact, "frames": n, "length": T, "loop": True, "speed": 0.0,
            "turn_rate": float(w), "turn": float(w * T)}
