# แผนที่ไขมันใต้ผิวตามบริเวณ (ที่ FAT_LEVEL = 1): ความหนาไขมัน T และรัศมีเติมร่อง (closing) R ต่อจุด หน่วยเมตร
#   แต่ละท่อนร่างกาย (ลำตัว คอ หัว ต้นแขน แขนล่าง มือ ต้นขา น่อง เท้า) มีค่าตามตำแหน่งบนท่อน + ด้าน (หน้า/หลัง/ใน/นอก)
#   ผสมกันแบบนุ่มด้วยระยะถึงปริมาตรหยาบของแต่ละท่อน ; ประเมินบนกริดหยาบ 12 มม. แล้วขยายแบบเชิงเส้น (ค่าเปลี่ยนช้า)
import numpy as np
import rig

MM = 0.001
CM = 0.01
LAM = 0.02           # ความนุ่มของการผสมระหว่างท่อน (ม.)


def _local(P, G, b):
    """จุดในกรอบท่า I ของกระดูก b (ย้อนจากท่า G)"""
    M = np.linalg.inv(rig.bone_xform(G, b))
    return P @ M[:3, :3].T + M[:3, 3]


def _interp(x, xs, ys):
    return np.interp(x, xs, ys)


def _sides(cx, cz, lat):
    """น้ำหนักด้าน (หน้า หลัง นอก ใน) จากทิศรอบแกน: cx = ไปทางนอก (+), cz = ไปหน้า (+)"""
    r = np.sqrt(cx * cx + cz * cz) + 1e-9
    c, s = cz / r, cx / r
    wf = np.maximum(c, 0) ** 2
    wb = np.maximum(-c, 0) ** 2
    wl = np.maximum(s, 0) ** 2
    wm = np.maximum(-s, 0) ** 2
    return wf, wb, wl, wm


def _mix4(w, vals):
    wf, wb, wl, wm = w
    f, b, l, m = vals
    return (wf * f + wb * b + wl * l + wm * m) / np.maximum(wf + wb + wl + wm, 1e-9)


def _seg(Pl, a, b, ra, rb):
    """ระยะถึงแคปซูลเรียว (กรอบท่า I) ; คืน (d, t)"""
    a = np.asarray(a, float)
    b = np.asarray(b, float)
    ab = b - a
    t = np.clip(((Pl - a) @ ab) / float(ab @ ab), 0, 1)
    c = a + t[:, None] * ab
    d = np.linalg.norm(Pl - c, axis=1) - (ra + (rb - ra) * t)
    return d, t


# ---------------- ลำตัว (เชิงกราน-อก): ตามความสูง y (ท่า I) และด้าน ----------------
TY = [0.84, 0.88, 0.93, 0.98, 1.03, 1.10, 1.18, 1.26, 1.34, 1.42, 1.48]
T_FRONT = [7.5, 7.5, 10, 16, 15, 14, 12, 10, 8, 10, 5]    # ท้องน้อยหนาสุด (ใต้สะดือ) ไม่ป่อง อกบาง ; หัวหน่าวแบน
T_SIDE = [7.0, 7.0, 7.5, 10.5, 15, 15, 13, 11, 10, 9, 6]  # สะโพก/สีข้าง
T_BACK = [13, 20, 21, 15, 10, 9.5, 10, 10, 10, 10, 7]     # ก้นเต็ม -> หลังล่างบาง (แอ่นเอว) -> หลังบน/สะบัก 10
R_FRONT = [3.0, 3.5, 4.5, 7.0, 7.0, 7.0, 6.5, 5.0, 5.5, 7.0, 3.0]
R_SIDE = [4.0, 5.0, 6.0, 7.0, 7.0, 7.0, 5.0, 3.0, 2.5, 2.0, 1.5]      # ใต้รักแร้เล็ก: ไม่เชื่อมรอยพับหน้า/หลังรักแร้
R_BACK = [4.0, 5.0, 6.0, 6.5, 6.5, 6.5, 6.5, 7.0, 7.0, 6.0, 2.5]
TRUNK_AB = [(0.84, 0.150, 0.110), (0.95, 0.160, 0.115), (1.05, 0.150, 0.110), (1.20, 0.150, 0.110),
            (1.32, 0.165, 0.120), (1.42, 0.170, 0.115), (1.48, 0.140, 0.100), (1.52, 0.070, 0.060)]
# ขั้น 1c (ทหารหนุ่มฟิต): ไขมันบางลงเหนือกล้ามท้องตรงและขอบล่างอก + เติมร่องน้อยลง -> เห็นรูปกล้ามนุ่ม ๆ
#   ท้องน้อย (ใต้สะดือ) สีข้าง หลัง ก้น คงเดิม
RA_X = (0.075, 0.035)              # กล้ามท้องตรง: เต็มถึง |x| 7.5 ซม. แล้วจางหมดใน 3.5 ซม.
RA_Y = (1.035, 0.060, 1.235, 0.050)  # เริ่มที่ 1.035 (ใต้สะดือ) เต็มที่ 1.095 ; เริ่มจางที่ 1.235 หมดที่ 1.285 (ลิ้นปี่ไม่เป็นหลุม)
RA_T, RA_R = 7.5, 4.5              # ไขมัน (มม.) และรัศมีเติมร่อง (ซม.) เหนือกล้ามท้องตรง
PEC_X = [0.0, 0.03, 0.06, 0.09, 0.12, 0.14, 0.155, 0.17]       # ขอบล่างอก (ผิว): y ตาม |x|
PEC_Y = [1.300, 1.285, 1.267, 1.259, 1.263, 1.280, 1.305, 1.340]
PEC_T, PEC_R, PEC_S = 7.5, 3.5, 0.022   # ไขมัน (มม.) รัศมีเติมร่อง (ซม.) ครึ่งความกว้างแถบ (ม.)
XIPH = (1.272, 0.046, 0.036, 0.5)   # ลิ้นปี่ (y, รัศมี x, รัศมี y, แรง): คงไขมันเดิมครึ่งหนึ่ง ไม่ให้เห็นปลายเอ็นเป็นก้อน ; ขอบนุ่ม ไม่เป็นรอยบาก
PEC_X0 = (0.020, 0.060)             # แถบขอบล่างอก: เริ่มที่ |x| 2 ซม. เต็มที่ 8 ซม. (เดิม 5-8 ซม. -> ปลายแถบเป็นแอ่งข้างลิ้นปี่)


def _ss(x):
    x = np.clip(x, 0.0, 1.0)
    return x * x * (3 - 2 * x)


def abs_masks(x, y, z):
    """น้ำหนัก 0..1 ของบริเวณกล้ามท้องตรง และแถบขอบล่างอก (กรอบเชิงกราน ท่า I ; x = |x|)"""
    front = _ss((z - 0.035) / 0.035)
    ra = (1 - _ss((x - RA_X[0]) / RA_X[1])) * _ss((y - RA_Y[0]) / RA_Y[1]) * (1 - _ss((y - RA_Y[2]) / RA_Y[3]))
    ype = np.interp(x, PEC_X, PEC_Y)
    pec = np.exp(-((y - ype + 0.004) / PEC_S) ** 2) * _ss((x - PEC_X0[0]) / PEC_X0[1]) * (1 - _ss((x - 0.150) / 0.030))
    keep = 1 - XIPH[3] * np.exp(-((x / XIPH[1]) ** 2 + ((y - XIPH[0]) / XIPH[2]) ** 2))
    return ra * front * keep, pec * front * keep


def trunk(P, G):
    Pl = _local(P, G, "pelvis")
    x, y, z = Pl[:, 0], Pl[:, 1], Pl[:, 2]
    zc = -0.010
    ys = [a[0] for a in TRUNK_AB]
    a = _interp(y, ys, [v[1] for v in TRUNK_AB])
    b = _interp(y, ys, [v[2] for v in TRUNK_AB])
    n = 2.3
    rho = ((np.abs(x) / a) ** n + (np.abs(z - zc) / b) ** n) ** (1 / n)
    d = (rho - 1) * np.minimum(a, b)
    out = np.maximum(np.maximum(0.84 - y, y - 1.52), 0)
    d = np.where(out > 0, np.sqrt(np.maximum(d, 0) ** 2 + out ** 2), d)
    w = _sides(np.abs(x), z - zc, None)
    wf, wb, ws = w[0], w[1], w[2] + w[3]
    tf, tb, ts = (_interp(y, TY, v) for v in (T_FRONT, T_BACK, T_SIDE))
    rf, rb, rs = (_interp(y, TY, v) for v in (R_FRONT, R_BACK, R_SIDE))
    sw = np.maximum(wf + wb + ws, 1e-9)
    T = (wf * tf + wb * tb + ws * ts) / sw * MM
    R = (wf * rf + wb * rb + ws * rs) / sw * CM
    # สะบักทั้งแผ่น (หลังบน): ไขมัน 10 มม. + เติมร่องกว้าง 7 ซม. (ไม่ให้ด้านข้างดึงค่าลง) -> ไม่เห็นแผ่นกล้ามเป็นชั้น ๆ
    scap = np.exp(-((np.abs(x) - 0.100) / 0.060) ** 2 - ((y - 1.350) / 0.085) ** 2) * np.clip(-(z - zc + 0.02) / 0.03, 0, 1)
    T = T + (10.0 * MM - T) * scap
    R = R + (7.0 * CM - R) * scap
    # ร่องก้นและร่องกลางหลังล่าง: เติมน้อยลงให้เหลือร่องนุ่ม ๆ (ร่องกลางหลังเฉพาะช่วงเอว ใต้ y 1.15)
    mid = np.exp(-(x / 0.022) ** 2) * wb
    cleft = mid * np.clip((1.00 - y) / 0.05, 0, 1) * np.clip((y - 0.80) / 0.03, 0, 1)
    furrow = mid * np.clip((y - 1.00) / 0.04, 0, 1) * np.clip((1.15 - y) / 0.05, 0, 1)
    R = R * (1 - 0.50 * cleft) * (1 - 0.35 * furrow)
    # ขั้น 1c: กล้ามท้องตรง + ขอบล่างอก (ไขมันบางลง เติมร่องน้อยลง)
    mra, mpe = abs_masks(np.abs(x), y, z - zc)
    T = T + (RA_T * MM - T) * mra * (T > RA_T * MM)
    R = R + (RA_R * CM - R) * mra * (R > RA_R * CM)
    T = T + (PEC_T * MM - T) * mpe * (T > PEC_T * MM)
    R = R + (PEC_R * CM - R) * mpe * (R > PEC_R * CM)
    return d, T, R


def neck(P, G):
    Pl = _local(P, G, "neck")
    d, t = _seg(Pl, (0, 1.47, -0.012), (0, 1.62, -0.012), 0.055, 0.055)
    w = _sides(np.abs(Pl[:, 0]), Pl[:, 2] + 0.012, None)
    T = _mix4(w, (4.0, 4.5, 4.0, 4.0)) * MM          # คอเรียวลง (รอบคอ ~38-39 ซม.)
    R = np.full(len(P), 1.5 * CM)
    return d, T, R


def _g(Pl, c, r):
    return np.exp(-np.sum(((Pl - np.asarray(c)) / np.asarray(r)) ** 2, axis=1))


def head(P, G):
    """หนังศีรษะบาง ~1.2 มม. ; หน้า: แก้ม ขมับ กราม 3 มม. หน้าผาก 2 มม. จมูก 1 มม. รอบตา ~0.6 มม. (หน้าไม่เป็นกะโหลก)
    R = รัศมีเติมร่อง: แก้ม/กราม/คาง 4 มม. (ร่องเล็ก ๆ ของหน้าเรียบ) ; หู จมูก ตา ปาก คงเล็ก"""
    Pl = _local(P, G, "head")
    d = np.linalg.norm((Pl - np.array([0, 1.690, 0.010])) / np.array([1.0, 1.15, 1.05]), axis=1) - 0.088
    x, y, z = np.abs(Pl[:, 0]), Pl[:, 1], Pl[:, 2]
    front = np.clip((z - 0.020) / 0.030, 0, 1) * np.clip((1.715 - y) / 0.02, 0, 1) * np.clip((y - 1.535) / 0.015, 0, 1)
    Q = np.c_[x, y, z]
    cheek = np.maximum(_g(Q, (0.050, 1.625, 0.055), (0.024, 0.040, 0.040)), _g(Q, (0.040, 1.580, 0.060), (0.028, 0.025, 0.040)))
    brow = _g(Q, (0.035, 1.700, 0.080), (0.040, 0.016, 0.030))
    nose = _g(Q, (0.0, 1.635, 0.105), (0.016, 0.030, 0.020))
    eyes = _g(Q, (0.032, 1.663, 0.085), (0.016, 0.012, 0.016))
    lips = _g(Q, (0.0, 1.587, 0.100), (0.026, 0.012, 0.015))
    tf = 2.0 + 1.0 * cheek - 0.2 * brow
    tf = tf - (tf - 1.0) * nose
    tf = tf - (tf - 1.5) * lips
    tf = tf - (tf - 0.6) * eyes
    T = (1.2 + (tf - 1.2) * front) * MM
    rf = 0.4 * np.clip(1 - 1.2 * np.maximum.reduce([nose, eyes, lips]), 0, 1)
    R = (0.15 + (rf - 0.15) * front) * CM
    return d, T, R


UARM_R = [3.0, 3.0, 3.2, 3.2, 4.0, 3.0]     # ขั้น 1c (เดิม 3 5 8 7 4 3 ซม.) ด้านหน้า/ใน ; ปลายศอกคงเดิม (ไม่เห็นปุ่มกระดูก)
UARM_RL = [3.0, 3.0, 4.0, 4.8, 4.0, 3.0]    # ด้านนอก: จุดเกาะหัวไหล่ไม่เป็นหลุมคม
UARM_RB = [3.0, 3.0, 2.6, 2.6, 4.0, 3.0]    # ด้านหลัง: เห็นไตรเซ็ปจากด้านหลัง
DELT_PAD = (0.58, 0.045, 2.0, 0.022, 0.045)  # ไขมันเสริมใต้จุดเกาะหัวไหล่ (t, ห่างแกนทางนอก-หลัง ม., มม., กว้างรอบ, ยาวตามแขน)
FARM_R = [2.0, 3.5, 4.5, 4.0, 3.0, 2.0]     # ขั้น 1c: เห็นมวลกล้ามแขนท่อนบนนุ่ม ๆ (เดิม 2 4 6 5.5 3.5 2 ซม.)


def uarm(P, G, sd):
    sx = 1.0 if sd == "L" else -1.0
    Pl = _local(P, G, "shoulder" + sd)
    j0 = rig.JOINT_I["shoulder" + sd]
    j1 = rig.JOINT_I["elbow" + sd]
    d, t = _seg(Pl, j0, j1, 0.048, 0.038)
    w = _sides(sx * (Pl[:, 0] - j0[0]), Pl[:, 2], None)
    # ขั้น 1c: ไขมันบางลง ~1.5 มม. เหนือหัวไหล่ ไบเซ็ป ไตรเซ็ป (ด้านในแขนคงเดิม) ; เติมร่องน้อยลง -> เห็นรูปมัดนุ่ม ๆ
    tf = _interp(t, [0, 0.8, 0.95, 1], [4.5, 4.5, 3.5, 3.5])
    tb = _interp(t, [0, 0.8, 0.92, 1], [5.0, 5.2, 4, 2.5])       # ขั้น 1c ปรับ: หลังแขนบางลง (เดิม 6-6.5) ปลายศอกคงเดิม
    tl = _interp(t, [0, 0.45, 0.85, 1], [4.5, 5.0, 6.0, 4])
    tm = _interp(t, [0, 0.85, 1], [7, 7, 4.5])
    T = _mix4(w, (tf, tb, tl, tm)) * MM
    # ไขมันเสริมนุ่ม ๆ ใต้จุดเกาะหัวไหล่ (ด้านนอก-หลัง) : แอ่งเป็นขอบนุ่ม ไม่เป็นหลุม
    cx, cz = sx * (Pl[:, 0] - j0[0]), Pl[:, 2]
    pc = np.array([np.cos(np.radians(25.0)), -np.sin(np.radians(25.0))]) * DELT_PAD[1]
    L = float(np.linalg.norm(np.asarray(j1) - np.asarray(j0)))
    T = T + DELT_PAD[2] * MM * np.exp(-(((cx - pc[0]) ** 2 + (cz - pc[1]) ** 2) / DELT_PAD[3] ** 2) - ((t - DELT_PAD[0]) * L / DELT_PAD[4]) ** 2)
    tk = [0, 0.12, 0.25, 0.70, 0.92, 1]
    rf = _interp(t, tk, UARM_R)
    R = _mix4(w, (rf, _interp(t, tk, UARM_RB), _interp(t, tk, UARM_RL), rf)) * CM
    return d, T, R


def farm(P, G, sd):
    sx = 1.0 if sd == "L" else -1.0
    Pl = _local(P, G, "elbow" + sd)
    j0 = rig.JOINT_I["elbow" + sd]
    j1 = rig.JOINT_I["wrist" + sd]
    d, t = _seg(Pl, j0, j1, 0.040, 0.026)
    w = _sides(sx * (Pl[:, 0] - j0[0]), Pl[:, 2], None)
    tb = _interp(t, [0, 0.12, 0.25, 0.55, 0.8, 1], [2.5, 3.5, 5.0, 4.5, 3.2, 2.5])
    tf = _interp(t, [0, 0.5, 0.8, 1], [5.0, 4.5, 3.5, 2.5])
    T = _mix4(w, (tf, tb, tf, tf)) * MM
    R = _interp(t, [0, 0.12, 0.28, 0.6, 0.88, 1], FARM_R) * CM
    return d, T, R


def hand(P, G, sd):
    sx = 1.0 if sd == "L" else -1.0
    Pl = _local(P, G, "wrist" + sd)
    j0 = rig.JOINT_I["wrist" + sd]
    d, t = _seg(Pl, j0, j0 + np.array([0, -0.17, 0]), 0.030, 0.020)
    w = _sides(sx * (Pl[:, 0] - j0[0]), Pl[:, 2], None)
    palm = _interp(t, [0, 0.5, 0.65, 1], [1.5, 1.5, 1.0, 1.0])
    back = _interp(t, [0, 0.5, 0.65, 1], [1.5, 1.5, 1.0, 1.0])
    T = _mix4(w, (_interp(t, [0, 0.6, 1], [2.5, 1.5, 1.2]), _interp(t, [0, 0.6, 1], [2.5, 1.5, 1.2]), back, palm)) * MM
    R = np.full(len(P), 0.25 * CM)
    return d, T, R


THIGH_RQ = [12.0, 7.5, 5.5, 5.0, 6.0]       # ขั้น 1c: รัศมีเติมร่องด้านหน้า ที่ t 0 .5 .7 .84 1 (ซม.) ; เข่าคงเดิม
THIGH_RQI = [12.0, 7.5, 4.5, 4.5, 6.0]      # ด้านใน (หยดน้ำเหนือเข่า) ; ขั้น 1c เดิมใช้ค่าเดียวกับด้านหน้า
CALF_R = [4.0, 3.8, 3.8, 4.5, 2.5, 2.5]      # ขั้น 1c ปรับ: รัศมีเติมร่องน่องด้านหลัง (ซม. ; เดิม 4 4.5 4.5 5)


def thigh(P, G, sd):
    sx = 1.0 if sd == "L" else -1.0
    Pl = _local(P, G, "hip" + sd)
    j0 = rig.JOINT_I["hip" + sd]
    j1 = rig.JOINT_I["knee" + sd]
    d, t = _seg(Pl, j0 + np.array([sx * 0.02, 0, 0]), j1, 0.085, 0.055)
    w = _sides(sx * (Pl[:, 0] - j0[0]), Pl[:, 2], None)
    # ด้านนอกต้นขาบางลง (ไม่เป็นกางเกงขี่ม้า) ; รอยพับก้นและต้นขาด้านในบนหนาขึ้น 3 มม. ; หลังเข่าไม่คอด
    #   ขั้น 1c: ด้านหน้า/ด้านในครึ่งล่างบางลง 1.5-3 มม. (กล้ามต้นขาหน้า + หยดน้ำเหนือเข่า) ; ครึ่งบน (จุดวัดรอบต้นขา) คงเดิม
    tf = _interp(t, [0, 0.15, 0.3, 0.5, 0.75, 0.88, 1], [8, 12, 12, 10, 9.5, 5.5, 4])
    tb = _interp(t, [0, 0.12, 0.3, 0.5, 0.75, 0.9, 1], [18, 18, 15, 13, 12, 9, 9])
    tl = _interp(t, [0, 0.2, 0.6, 0.75, 0.9, 1], [10, 9, 9, 8, 6, 5])
    tm = _interp(t, [0, 0.3, 0.5, 0.75, 0.9, 1], [16, 14, 11.5, 8.5, 6.5, 6.5])
    T = _mix4(w, (tf, tb, tl, tm)) * MM
    R = _interp(t, [0, 0.12, 0.25, 0.65, 0.84, 1], [1.5, 3.5, 12.0, 12.0, 6.0, 6.0]) * CM
    # ขั้น 1c: ด้านหน้า/ด้านในครึ่งล่าง เติมร่องน้อยลง (ด้านหลัง ด้านนอก คงเดิม)
    tq = [0, 0.5, 0.7, 0.84, 1]
    wq = w[0] + 0.9 * w[3]
    rq = (w[0] * _interp(t, tq, THIGH_RQ) + 0.9 * w[3] * _interp(t, tq, THIGH_RQI)) / np.maximum(wq, 1e-9) * CM
    q = np.clip(wq, 0, 1) * np.clip((t - 0.35) / 0.15, 0, 1)
    R = R + (rq - R) * q * (R > rq)
    # ต้นขาด้านในส่วนบน (ง่ามขา): เติมน้อย กันขาสองข้างเชื่อมกัน
    inner = w[3] * np.clip((0.40 - t) / 0.2, 0, 1)
    R = R * (1 - 0.85 * inner)
    return d, T, R


def shank(P, G, sd):
    sx = 1.0 if sd == "L" else -1.0
    Pl = _local(P, G, "knee" + sd)
    j0 = rig.JOINT_I["knee" + sd]
    j1 = rig.JOINT_I["ankle" + sd]
    d, t = _seg(Pl, j0, j1, 0.055, 0.035)
    w = _sides(sx * (Pl[:, 0] - j0[0]), Pl[:, 2] + 0.01, None)
    tf = _interp(t, [0, 0.12, 0.85, 1], [3.5, 2.5, 2.5, 2.5])
    tb = _interp(t, [0, 0.15, 0.55, 0.85, 1], [6.5, 7.0, 6.8, 3, 3])      # ขั้น 1c: น่องบางลงเล็กน้อย (เดิม 7.5)
    tl = _interp(t, [0, 0.6, 0.85, 1], [6, 6, 3, 2.5])
    tm = _interp(t, [0, 0.6, 0.85, 1], [6, 5, 3, 2.5])
    T = _mix4(w, (tf, tb, tl, tm)) * MM
    R = _interp(t, [0, 0.12, 0.25, 0.65, 0.86, 1], [4.0, 6.0, 8.0, 8.0, 2.5, 2.5]) * CM
    # ขั้น 1c: น่องด้านหลัง เติมร่องน้อยลง -> เห็นรูปน่องนุ่ม ๆ
    rc = _interp(t, [0, 0.12, 0.5, 0.65, 0.86, 1], CALF_R) * CM
    q = np.clip(w[1] + 0.5 * (w[2] + w[3]), 0, 1)
    R = R + (rc - R) * q * (R > rc)
    return d, T, R


def foot(P, G, sd):
    Pl = _local(P, G, "ankle" + sd)
    sx = 1.0 if sd == "L" else -1.0
    j = rig.JOINT_I["ankle" + sd]
    a = j + np.array([0, -0.045, -0.050])
    b = j + np.array([sx * 0.012, -0.060, 0.170])
    d, t = _seg(Pl, a, b, 0.036, 0.028)
    up = Pl[:, 1] - (a[1] + (b[1] - a[1]) * t)
    sole = np.clip(-up / 0.015, 0, 1)
    T = (np.interp(t, [0, 0.25, 0.75, 1], [6, 4.5, 4.5, 2.0]) * sole +
         np.interp(t, [0, 0.75, 1], [2.5, 2.5, 1.5]) * (1 - sole)) * MM
    R = np.full(len(P), 0.5 * CM)
    return d, T, R


SEGS = [("trunk", trunk), ("neck", neck), ("head", head)]
for _sd in ("L", "R"):
    SEGS += [("uarm" + _sd, lambda P, G, s=_sd: uarm(P, G, s)), ("farm" + _sd, lambda P, G, s=_sd: farm(P, G, s)),
             ("hand" + _sd, lambda P, G, s=_sd: hand(P, G, s)), ("thigh" + _sd, lambda P, G, s=_sd: thigh(P, G, s)),
             ("shank" + _sd, lambda P, G, s=_sd: shank(P, G, s)), ("foot" + _sd, lambda P, G, s=_sd: foot(P, G, s))]


def maps(P, G):
    """คืน (T, R) ต่อจุด (ม.) ที่ FAT_LEVEL = 1"""
    P = np.asarray(P, float)
    ds, Ts, Rs = [], [], []
    for _, fn in SEGS:
        d, T, R = fn(P, G)
        ds.append(d)
        Ts.append(T)
        Rs.append(R)
    D = np.stack(ds, 1)
    W = np.exp(-(D - D.min(1, keepdims=True)) / LAM)
    W /= W.sum(1, keepdims=True)
    return (W * np.stack(Ts, 1)).sum(1), (W * np.stack(Rs, 1)).sum(1)


SEG_FN = dict(SEGS)


def _upsample_map(A, ax, lo, n, h, step):
    """ขยายแผนที่หยาบ (เชิงเส้น) แล้วเบลอเกาส์ ~step/2 : ไม่มีรอยหักทุก step (รอยหักทำให้เกิดลายวงปีไม้บนผิวนูน)"""
    from scipy.ndimage import map_coordinates, gaussian_filter
    res = np.empty(n, np.float32)
    cy = (lo[1] + np.arange(n[1]) * h - ax[1][0]) / step
    cz = (lo[2] + np.arange(n[2]) * h - ax[2][0]) / step
    CY, CZ = np.meshgrid(cy, cz, indexing='ij')
    for i in range(n[0]):
        cx = (lo[0] + i * h - ax[0][0]) / step
        res[i] = map_coordinates(A, [np.full(CY.shape, cx), CY, CZ], order=1, mode='nearest')
    return gaussian_filter(res, 0.55 * step / h, mode='nearest', truncate=2.5).astype(np.float32)


def _coarse_axes(lo, n, h, step):
    lo = np.asarray(lo, float)
    hi = lo + (np.asarray(n) - 1) * h
    m = np.ceil((hi - lo) / step).astype(int) + 2
    return [lo[i] - step * 0.5 + np.arange(m[i]) * step for i in range(3)]


def seg_R_grid(lo, n, h, G, seg, step=0.012, M=None):
    """รัศมีเติมร่องที่ต้องการ ตามตารางของท่อน seg เอง (ไม่ผสมท่อนอื่น) บนกริด (lo, n, h) ; M = กรอบของกริด -> โลก"""
    ax = _coarse_axes(lo, n, h, step)
    X, Y, Z = np.meshgrid(*ax, indexing='ij')
    P = np.stack([X.ravel(), Y.ravel(), Z.ravel()], 1)
    if M is not None:
        P = P @ M[:3, :3].T + M[:3, 3]
    _, _, R = SEG_FN[seg](P, G)
    return _upsample_map(R.reshape(X.shape), ax, np.asarray(lo, float), n, h, step)


def membership_grid(lo, n, h, G, names, step=0.012):
    """ผลรวมน้ำหนักการเป็นสมาชิกของท่อนที่ระบุ (0..1) บนกริด (lo, n, h)"""
    ax = _coarse_axes(lo, n, h, step)
    X, Y, Z = np.meshgrid(*ax, indexing='ij')
    P = np.stack([X.ravel(), Y.ravel(), Z.ravel()], 1)
    ds = np.stack([fn(P, G)[0] for _, fn in SEGS], 1)
    W = np.exp(-(ds - ds.min(1, keepdims=True)) / LAM)
    W /= W.sum(1, keepdims=True)
    idx = [i for i, (nm, _) in enumerate(SEGS) if nm in names]
    m = W[:, idx].sum(1).reshape(X.shape)
    return _upsample_map(m, ax, np.asarray(lo, float), n, h, step)


# ---------------- บริเวณรอยต่อท่อน (ขาหนีบ สะโพกข้าง ไหล่ เข่า ศอก): เกลี่ยข้ามท่อน ----------------
JUNCTIONS = [  # (กระดูก, จุด a, จุด b ท่า I ข้างซ้าย, รัศมีแกน, รัศมีจางหมด, แรง)
    ("pelvis", (0.128, 0.995, 0.052), (0.030, 0.885, 0.062), 0.035, 0.075, 1.0),     # แนวขาหนีบ
    ("pelvis", (0.145, 1.020, 0.020), (0.160, 0.900, -0.010), 0.025, 0.060, 0.8),    # สะโพกด้านข้าง
    ("clavicleL", (0.070, 1.465, 0.070), (0.210, 1.475, 0.000), 0.030, 0.065, 0.7),  # ไหปลาร้า-หัวไหล่
    ("clavicleL", (0.120, 1.430, -0.090), (0.200, 1.450, -0.040), 0.025, 0.060, 0.7),  # สันสะบัก-หัวไหล่หลัง
    ("kneeL", (0.095, 0.515, 0.020), (0.095, 0.505, 0.020), 0.040, 0.080, 0.8),      # เข่า
    ("elbowL", (0.200, 1.128, -0.025), (0.200, 1.120, -0.020), 0.020, 0.050, 0.8),   # ศอก
    ("elbowL", (0.202, 0.884, 0.002), (0.2015, 0.850, 0.001), 0.022, 0.050, 0.9),    # ข้อมือ-มือ (ไม่เป็นวงข้อมือ)
    ("elbowL", (0.170, 1.155, -0.004), (0.170, 1.118, -0.004), 0.020, 0.045, 0.9),   # ศอกด้านใน (ต้นแขน-ปุ่มศอก)
    ("clavicleL", (0.150, 1.455, 0.070), (0.185, 1.380, 0.055), 0.022, 0.055, 0.7),  # ร่องอก-หัวไหล่
]


def junction(P, G):
    w = np.zeros(len(P))
    for bone, a, b, r0, r1, k in JUNCTIONS:
        for sd, sx in (("L", 1.0), ("R", -1.0)):
            bn = bone[:-1] + sd if bone[-1] == "L" else bone
            mx = np.array([sx, 1.0, 1.0])
            Pl = _local(P, G, bn)
            d, _ = _seg(Pl, np.asarray(a) * mx, np.asarray(b) * mx, 0.0, 0.0)
            u = np.clip((r1 - d) / (r1 - r0), 0, 1)
            w = np.maximum(w, k * u * u * (3 - 2 * u))
    return w


def junction_grid(lo, n, h, G, step=0.012):
    ax = _coarse_axes(lo, n, h, step)
    X, Y, Z = np.meshgrid(*ax, indexing='ij')
    w = junction(np.stack([X.ravel(), Y.ravel(), Z.ravel()], 1), G).reshape(X.shape)
    return np.clip(_upsample_map(w, ax, np.asarray(lo, float), n, h, step), 0, 1)


def map_grid(lo, n, h, G, step=0.012):
    """ประเมินบนกริดหยาบ step แล้วขยายแบบเชิงเส้นลงกริด (lo, n, h) ; คืน (T, R) float32 รูปร่าง n"""
    from scipy.ndimage import map_coordinates
    lo = np.asarray(lo, float)
    hi = lo + (np.asarray(n) - 1) * h
    m = np.ceil((hi - lo) / step).astype(int) + 2
    ax = [lo[i] - step * 0.5 + np.arange(m[i]) * step for i in range(3)]
    X, Y, Z = np.meshgrid(*ax, indexing='ij')
    T, R = maps(np.stack([X.ravel(), Y.ravel(), Z.ravel()], 1), G)
    T = T.reshape(X.shape)
    R = R.reshape(X.shape)
    return _upsample_map(T, ax, lo, n, h, step), _upsample_map(R, ax, lo, n, h, step)


# ---------------- ขั้น 1c: ร่องตื้นในชั้นไขมันด้านหน้าลำตัว (ความลึก มม. ที่ FAT_LEVEL 1 ; กรอบเชิงกราน ท่า I) ----------------
#   เส้นกลางท้อง (linea alba) รอยคั่นกล้ามท้อง 3 แนว (บน กลาง ระดับสะดือ) ขอบนอกกล้ามท้องตรง สะดือ รอยใต้ขอบล่างอก
#   ร่องกว้าง ~1.5-2 ซม. ลึก 1-2.6 มม. (ไม่ใช่ร่องเส้นใย ; ระดับ hi มีจุดยอดพอ) ; ท้องน้อยใต้สะดือเรียบ ; ไม่แตะหลัง/สีข้าง
LA_D, LA_W, LA_Y = 2.6, 0.0105, (1.050, 0.020, 1.215, 0.045)    # เส้นกลางท้อง: ลึก กว้าง ช่วง y (เริ่ม จาง เริ่มหมด จาง) ; จบที่สะดือ
TI = [(1.226, 0.10, 2.3), (1.150, 0.05, 2.2), (1.080, 0.0, 1.4)]  # รอยคั่น: y กลาง, เอียงขึ้นทางข้าง, ลึก
TI_W = 0.0120
RA_LAT = ([1.00, 1.06, 1.12, 1.18, 1.24], [0.060, 0.074, 0.080, 0.083, 0.086])  # ขอบนอกกล้ามท้องตรง (|x| ตาม y ; โค้งออก)
SL_D, SL_W = 2.2, 0.0220           # ขอบนอก (linea semilunaris): เงานุ่ม ๆ ให้กล้ามท้องมีขอบ (เดิม 0.9 มม. หายไปตอนเบลอ)
NV_Y, NV_D, NV_RX, NV_RY = 1.066, 8.0, 0.0085, 0.0100   # สะดือ: y ลึก รัศมี (เดิม 4.5 มม. เหลือ ~2 มม. หลังเบลอ ; G2 ยอมหลุมเปิด ≤ 10 มม.)
PE_D, PE_W = 1.1, 0.0110           # รอยใต้ขอบล่างอก
GROOVE_BOX = ((-0.20, 0.98, 0.0), (0.20, 1.40, 0.20))     # กล่องที่มีร่อง (กรอบเชิงกราน)


def groove_scale(fat):
    """ไขมันมาก = ร่องตื้นลง (ระดับ 1.3 เหลือ ~0.55) ; ผอมลง = ชัดขึ้นเล็กน้อย"""
    return float(np.clip(2.5 - 1.5 * fat, 0.0, 1.3))


def grooves(P, G, wide=1.0, navel=True):
    """ความลึกร่อง (ม.) ต่อจุด: ผิวยุบเข้าเท่านี้ ; wide = ขยายความกว้าง (สีระดับไกล lo) ; navel = รวมสะดือ"""
    Pl = _local(P, G, "pelvis")
    x, y, z = np.abs(Pl[:, 0]), Pl[:, 1], Pl[:, 2]
    front = _ss((z - 0.045) / 0.030)
    xl = np.interp(y, *RA_LAT)
    la = LA_D * np.exp(-(x / (LA_W * wide)) ** 2) * _ss((y - LA_Y[0]) / LA_Y[1]) * (1 - _ss((y - LA_Y[2]) / LA_Y[3]))
    ti = np.zeros(len(P))
    for yc, sl, dep in TI:
        ti = np.maximum(ti, dep * np.exp(-((y - yc - sl * x) / (TI_W * wide)) ** 2))
    ti = ti * (1 - _ss((x - (xl - 0.016)) / 0.018))
    sm = SL_D * np.exp(-((x - xl) / (SL_W * min(wide, 1.3))) ** 2) * _ss((y - 1.04) / 0.04) * (1 - _ss((y - 1.22) / 0.04))
    ype = np.interp(x, PEC_X, PEC_Y)
    pe = PE_D * np.exp(-((y - ype) / (PE_W * min(wide, 1.4))) ** 2) * _ss((x - 0.035) / 0.025) * (1 - _ss((x - 0.135) / 0.030))
    nw = min(wide, 1.6)
    nv = NV_D * np.exp(-((x / (NV_RX * nw)) ** 2 + ((y - NV_Y) / (NV_RY * nw)) ** 2)) if navel else 0.0 * x
    d = np.sqrt(la * la + ti * ti + sm * sm + pe * pe)          # จุดตัดของร่องลึกขึ้นเล็กน้อย (ไม่เป็นหลุม)
    return np.maximum(d, nv) * front * MM


# ---------------- ขั้น 1c ปรับ: ร่องนุ่มที่แขนขา (เห็นจากด้านหลัง ; ลึก < 1 มม. กว้าง ~2 ซม. ไม่ใช่ร่องเส้นใย) ----------------
#   ไตรเซ็ป: ขอบล่างของหัวยาว/หัวข้าง (รูปเกือกม้า) ด้านเอ็นลาดยาวกว่า -> เป็นขั้นนุ่ม ๆ ; น่อง: ร่องแบ่งน่องสองหัว (บนครึ่งบน)
TRI_D, TRI_W = 1.4, 0.0090          # ลึก (มม.) ครึ่งความกว้างด้านกล้าม (ม.) ; ด้านเอ็น × 2 (ขั้นนุ่ม ๆ ไม่ใช่ร่องคม)
TRI_T = (0.60, 0.15, 75.0)          # ขอบล่างกลางหลังแขนที่ t 0.60 ลงไปถึง t 0.75 ที่ ±75° จากกลางหลัง
CALF_D, CALF_W, CALF_X = 1.0, 0.0080, 0.003   # ร่องแบ่งน่อง: ลึก (มม.) ครึ่งความกว้าง (ม.) เยื้องออกด้านนอก (ม.)
LIMB_BOX = {"shoulder": ((-0.085, -0.31, -0.10), (0.085, -0.09, 0.03)),   # กล่องรอบข้อ (กรอบท่า I ของกระดูก เทียบตำแหน่งข้อ)
            "knee": ((-0.06, -0.23, -0.14), (0.06, -0.01, -0.02))}


def tri_groove(P, G, sd):
    """ขอบล่างไตรเซ็ป (กรอบไหล่ ท่า I) ; ความลึก ม."""
    sx = 1.0 if sd == "L" else -1.0
    Pl = _local(P, G, "shoulder" + sd)
    j0, j1 = rig.JOINT_I["shoulder" + sd], rig.JOINT_I["elbow" + sd]
    L = float(np.linalg.norm(j1 - j0))
    t = (j0[1] - Pl[:, 1]) / L
    cx, cz = sx * (Pl[:, 0] - j0[0]), Pl[:, 2]
    th = np.degrees(np.arctan2(cx, -cz))                    # 0 = กลางหลังแขน, + = ด้านนอก
    s = (t - (TRI_T[0] + TRI_T[1] * (th / TRI_T[2]) ** 2)) * L      # + = ใต้ขอบ (ทางศอก)
    w = np.where(s < 0, TRI_W, 2.0 * TRI_W)
    r = np.sqrt(cx * cx + cz * cz)
    m = (1 - _ss((np.abs(th) - 60.0) / 25.0)) * (1 - _ss((r - 0.065) / 0.015)) * _ss((t - 0.35) / 0.1) * (1 - _ss((t - 0.88) / 0.06))
    return TRI_D * np.exp(-(s / w) ** 2) * m * MM


def calf_groove(P, G, sd):
    """ร่องแบ่งน่องสองหัว (กรอบเข่า ท่า I) ; ความลึก ม."""
    sx = 1.0 if sd == "L" else -1.0
    Pl = _local(P, G, "knee" + sd)
    j0, j1 = rig.JOINT_I["knee" + sd], rig.JOINT_I["ankle" + sd]
    t = (j0[1] - Pl[:, 1]) / float(j0[1] - j1[1])
    cx, cz = sx * (Pl[:, 0] - j0[0]), Pl[:, 2] + 0.01
    m = _ss((-cz - 0.03) / 0.02) * (1 - _ss((np.sqrt(cx * cx + cz * cz) - 0.12) / 0.02)) * _ss((t - 0.08) / 0.06) * (1 - _ss((t - 0.36) / 0.12))
    return CALF_D * np.exp(-((cx - CALF_X) / CALF_W) ** 2) * m * MM


def _box_apply(g, G, bone, lo, hi, fn, k):
    M = rig.bone_xform(G, bone)
    cs = np.array([[x, y, z] for x in (lo[0], hi[0]) for y in (lo[1], hi[1]) for z in (lo[2], hi[2])])
    w = cs @ M[:3, :3].T + M[:3, 3]
    sl = g.slices(w.min(0), w.max(0))
    if sl is None:
        return
    P = g.points(sl).astype(np.float64)
    dep = fn(P) * k
    shp = tuple(s.stop - s.start for s in sl)
    g.F[sl] = (g.F[sl] + dep.reshape(shp)).astype(g.F.dtype)


def add_grooves(g, G, k):
    """ยุบผิวลงตามร่อง (สนามระยะ: บวก = ออกนอก) เฉพาะกล่องที่มีร่อง ; k = groove_scale"""
    if k <= 0:
        return
    lo, hi = (np.asarray(b, float) for b in GROOVE_BOX)
    _box_apply(g, G, "pelvis", lo, hi, lambda P: grooves(P, G), k)
    for sd in ("L", "R"):
        sx = 1.0 if sd == "L" else -1.0
        for bone, fn in (("shoulder", tri_groove), ("knee", calf_groove)):
            j = rig.JOINT_I[bone + sd]
            a, b = (np.asarray(v, float) for v in LIMB_BOX[bone])
            if sx < 0:
                a, b = np.array([-b[0], a[1], a[2]]), np.array([-a[0], b[1], b[2]])
            _box_apply(g, G, bone + sd, j + a, j + b, lambda P, f=fn, s=sd: f(P, G, s), k)
