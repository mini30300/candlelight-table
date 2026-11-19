# โครงกระดูกของทหาร: 23 กระดูกของโครงเกม (ชื่อ/ลำดับ/พ่อแม่/ระยะเดิม × S) + กระดูกช่วย 10 ชิ้น + กระดูกหน้า 5 ชิ้น (ใบไม้)
# หน่วยเมตร แกนแบบ Godot: +Y บน หุ่นหันหน้า +Z ซ้ายของหุ่น = +X ; การหมุนแบบ quaternion [x, y, z, w] เหมือน Godot
import json
import numpy as np

H = 1.78                    # ส่วนสูงจริง (ม.)
S = H / 1.60                # สเกลของโครงเกม (หุ่น 1.6 ม.) = motion_scale

MAIN = ["pelvis", "spine", "chest", "neck", "head", "shoulderL", "elbowL", "wristL", "handL", "shoulderR", "elbowR",
        "wristR", "handR", "hipL", "kneeL", "ankleL", "toeL", "heelL", "hipR", "kneeR", "ankleR", "toeR", "heelR"]
_PAR = [None, "pelvis", "spine", "chest", "neck", "chest", "shoulderL", "elbowL", "wristL", "chest", "shoulderR",
        "elbowR", "wristR", "pelvis", "hipL", "kneeL", "ankleL", "ankleL", "pelvis", "hipR", "kneeR", "ankleR", "ankleR"]
_OFF = [[0, 0, 0], [0, 0.17, 0], [0, 0.25, 0], [0, 0.06, 0], [0, 0.115, 0], [0.18, -0.02, 0], [0, -0.29, 0],
        [0, -0.235, 0], [0, -0.085, 0], [-0.18, -0.02, 0], [0, -0.29, 0], [0, -0.235, 0], [0, -0.085, 0],
        [0.085, -0.05, 0], [0, -0.39, 0], [0, -0.39, 0], [0, -0.07, 0.13], [0, -0.07, -0.05], [-0.085, -0.05, 0],
        [0, -0.39, 0], [0, -0.39, 0], [0, -0.07, 0.13], [0, -0.07, -0.05]]
# ท่ายืนพักของโครงเกม (rest = ท่า idle ของ infantry.glb) เพื่อให้หุ่นยืนเหมือนชุดอื่นเมื่อยังไม่มีท่า
REST_Q = {
    "pelvis": [0.008727, 0, 0, 0.999962], "spine": [0.01309, 0, 0, 0.999914], "neck": [-0.011781, 0, 0, 0.999931],
    "shoulderL": [-0.417754, -0.328917, 0.16568, 0.830569], "elbowL": [-0.399549, 0, 0, 0.916712],
    "shoulderR": [0.144372, 0.05702, 0.038257, 0.987138], "elbowR": [-0.800208, 0, 0, 0.599722],
    "hipL": [-0.111022, 0.096232, 0.021903, 0.988905], "kneeL": [0.168481, 0, 0, 0.985705],
    "ankleL": [-0.065249, -0.028992, -0.010815, 0.997389], "hipR": [-0.079108, -0.108352, -0.026209, 0.990613],
    "kneeR": [0.168906, 0, 0, 0.985632], "ankleR": [-0.096868, 0.024538, 0.017009, 0.994849]}
PELVIS_REST = np.array([0.0, 0.888, 0.005]) * S
PELVIS_IPOSE = np.array([0.0, 0.90, 0.0]) * S      # ขาตรง ฝ่าเท้าแตะพื้นพอดี (ขายาว 0.90 S)

# กระดูกช่วย (helper): ไม่มีคลิปขยับ ตัวขับคำนวณจากกระดูกหลักทุกเฟรม (hi/mid/lo) ; ระดับ min ไม่ใช้เลย
# clavicle = ไหปลาร้า+สะบัก (หมุนรอบข้อต่ออก-ไหปลาร้า) ; uparm_twist = แบ่งการบิดต้นแขนครึ่งหนึ่ง
# elbow/knee/hip_half = กระดูกครึ่งมุม (หมุนครึ่งหนึ่งของข้อ) รักษาปริมาตรตรงข้อพับ
SC_JOINT = np.array([0.022, 1.4585, 0.066])         # ข้อต่ออก-ไหปลาร้า (ท่า I ม.)


def _helpers():
    out = []
    for sd, sx in (("L", 1.0), ("R", -1.0)):
        chest_i = _ipose_main()["chest"]
        sc = SC_JOINT * np.array([sx, 1, 1])
        out.append(("clavicle" + sd, "chest", sc - chest_i))
        out.append(("uparm_twist" + sd, "shoulder" + sd, np.array([0.0, -0.10 * S, 0.0])))
        out.append(("elbow_half" + sd, "shoulder" + sd, np.array([0.0, -0.29 * S, 0.0])))
        out.append(("hip_half" + sd, "pelvis", np.array([sx * 0.085 * S, -0.05 * S, 0.0])))
        out.append(("knee_half" + sd, "hip" + sd, np.array([0.0, -0.39 * S, 0.0])))
    return out


def _ipose_main():
    pos = {}
    for i, b in enumerate(MAIN):
        p = _PAR[i]
        off = np.array(_OFF[i], float) * S
        pos[b] = PELVIS_IPOSE.copy() if p is None else pos[p] + off
    return pos


HELPERS = _helpers()
# กระดูกหน้า (ใหม่ 0.14): ใบไม้ใต้ head ชื่อขึ้นต้น head_ (แผลนับเป็นหัว) ; ไม่มีคลิป ไม่มีตัวขับ (เกมขยับเอง) ; ท่าพัก = หมุน 0
#   head_jaw = กราม (หมุนรอบแกน X ของตัวเอง บวก = อ้าปาก ~1.7 มม. ต่อองศาที่ริมฝีปาก) ; head_lip<L/R> = มุมปาก ; head_brow<L/R> = คิ้ว (สองอย่างหลังเลื่อน)
#   จุดหมุนกรามต่ำกว่าข้อขากรรไกร ~3 ซม. (ราวรูขากรรไกร): ปากล่างลงมากกว่าถอยหลัง เหมือนการอ้าปากจริง (หมุน + เลื่อน)
FACE_PTS = {"head_jaw": (0.0, 1.608, 0.004), "head_lipL": (0.0255, 1.5886, 0.1006), "head_lipR": (-0.0255, 1.5886, 0.1006),
            "head_browL": (0.032, 1.6865, 0.090), "head_browR": (-0.032, 1.6865, 0.090)}
FACE = list(FACE_PTS)
BONES = MAIN + [h[0] for h in HELPERS] + FACE
PARENT = {b: _PAR[i] for i, b in enumerate(MAIN)}
OFFSET = {b: np.array(_OFF[i], float) * S for i, b in enumerate(MAIN)}
for _n, _p, _o in HELPERS:
    PARENT[_n] = _p
    OFFSET[_n] = np.asarray(_o, float)
for _n in FACE:
    PARENT[_n] = "head"
    OFFSET[_n] = np.asarray(FACE_PTS[_n], float) - _ipose_main()["head"]
OFFSET["pelvis"] = PELVIS_IPOSE.copy()
BI = {b: i for i, b in enumerate(BONES)}
DEFORM = [b for b in BONES if not b.startswith("heel")]       # ส้นเท้าเป็นจุดแตะพื้น ไม่ใช้ผิว

# ช่วงขยับของข้อ (องศา) ในกรอบของกระดูกพ่อ: แกน X (+ งอ/- เหยียดตามแต่ละข้อ), Y (บิด), Z (กาง/หุบ) ; ข้างซ้าย
# ใช้ตรวจคลิป/ท่า และเป็นค่าเริ่มต้นของ IK ภายหลัง (คลิปเป็นตัวกำหนดจริงในเกม)
LIMITS = {
    "pelvis": {"x": [-30, 30], "y": [-45, 45], "z": [-20, 20], "note": "whole-body tilt (root)"},
    "spine": {"x": [-25, 50], "y": [-15, 15], "z": [-25, 25], "note": "lumbar: x- = extension, x+ = flexion"},
    "chest": {"x": [-20, 30], "y": [-35, 35], "z": [-20, 20], "note": "thoracic"},
    "neck": {"x": [-50, 40], "y": [-60, 60], "z": [-35, 35], "note": "cervical C7..C2"},
    "head": {"x": [-25, 20], "y": [-10, 10], "z": [-8, 8], "note": "atlanto-occipital"},
    "clavicle": {"x": [-10, 10], "y": [-25, 25], "z": [-10, 40], "note": "z+ = elevation, y = protraction"},
    "shoulder": {"x": [-180, 50], "y": [-90, 70], "z": [-40, 180], "note": "x- = flexion (arm forward), z+ = abduction"},
    "elbow": {"x": [-145, 5], "y": [-80, 80], "z": [-5, 5], "note": "x- = flexion; y = pronation/supination"},
    "wrist": {"x": [-70, 75], "y": [-10, 10], "z": [-30, 20], "note": "flexion/extension, deviation"},
    "hand": {"x": [-10, 10], "y": [-5, 5], "z": [-10, 10], "note": "palm (no finger bones)"},
    "hip": {"x": [-120, 25], "y": [-40, 45], "z": [-30, 45], "note": "x- = flexion, z+ = abduction"},
    "knee": {"x": [-5, 140], "y": [-10, 10], "z": [-3, 3], "note": "x+ = flexion"},
    "ankle": {"x": [-25, 50], "y": [-10, 10], "z": [-20, 25], "note": "x- = dorsiflexion, x+ = plantarflexion"},
    "toe": {"x": [-60, 35], "y": [-5, 5], "z": [-5, 5], "note": "metatarsophalangeal"},
    "head_jaw": {"x": [0, 8], "y": [0, 0], "z": [0, 0], "note": "face: x+ = mouth opening (~1.7 mm at the lips per degree; speech 1.5-5, shout <= 8)"},
    "head_lip": {"x": [0, 0], "y": [0, 0], "z": [0, 0], "t_mm": [[-3, 3], [-3, 3], [-2, 2]],
                 "note": "face: translation only (head frame, mm x S ratio): x out, y up, z forward"},
    "head_brow": {"x": [0, 0], "y": [0, 0], "z": [0, 0], "t_mm": [[-1.5, 1.5], [-2.5, 4], [0, 0]],
                  "note": "face: translation only (head frame, mm x S ratio): x out, y up"},
}

# ---------------- คณิตการหมุน (quaternion [x,y,z,w] และเมทริกซ์ 3x3) ----------------


def qnorm(q):
    q = np.asarray(q, float)
    return q / np.linalg.norm(q)


def qmul(a, b):
    ax, ay, az, aw = a
    bx, by, bz, bw = b
    return np.array([aw * bx + ax * bw + ay * bz - az * by, aw * by - ax * bz + ay * bw + az * bx,
                     aw * bz + ax * by - ay * bx + az * bw, aw * bw - ax * bx - ay * by - az * bz])


def qinv(q):
    return np.array([-q[0], -q[1], -q[2], q[3]])


def qaxis(axis, deg):
    a = np.asarray(axis, float)
    a = a / np.linalg.norm(a)
    h = np.radians(deg) * 0.5
    return np.array([*(a * np.sin(h)), np.cos(h)])


def qmat(q):
    x, y, z, w = qnorm(q)
    return np.array([[1 - 2 * (y * y + z * z), 2 * (x * y - z * w), 2 * (x * z + y * w)],
                     [2 * (x * y + z * w), 1 - 2 * (x * x + z * z), 2 * (y * z - x * w)],
                     [2 * (x * z - y * w), 2 * (y * z + x * w), 1 - 2 * (x * x + y * y)]])


def matq(m):
    t = np.trace(m)
    if t > 0:
        s = np.sqrt(t + 1.0) * 2
        q = [(m[2, 1] - m[1, 2]) / s, (m[0, 2] - m[2, 0]) / s, (m[1, 0] - m[0, 1]) / s, 0.25 * s]
    elif m[0, 0] > m[1, 1] and m[0, 0] > m[2, 2]:
        s = np.sqrt(1.0 + m[0, 0] - m[1, 1] - m[2, 2]) * 2
        q = [0.25 * s, (m[0, 1] + m[1, 0]) / s, (m[0, 2] + m[2, 0]) / s, (m[2, 1] - m[1, 2]) / s]
    elif m[1, 1] > m[2, 2]:
        s = np.sqrt(1.0 + m[1, 1] - m[0, 0] - m[2, 2]) * 2
        q = [(m[0, 1] + m[1, 0]) / s, 0.25 * s, (m[1, 2] + m[2, 1]) / s, (m[0, 2] - m[2, 0]) / s]
    else:
        s = np.sqrt(1.0 + m[2, 2] - m[0, 0] - m[1, 1]) * 2
        q = [(m[0, 2] + m[2, 0]) / s, (m[1, 2] + m[2, 1]) / s, 0.25 * s, (m[1, 0] - m[0, 1]) / s]
    q = qnorm(q)
    return q if q[3] >= 0 else -q


def qslerp(a, b, t):
    a = qnorm(a)
    b = qnorm(b)
    d = float(np.dot(a, b))
    if d < 0:
        b = -b
        d = -d
    if d > 0.9995:
        return qnorm(a + (b - a) * t)
    th = np.arccos(d)
    return (np.sin((1 - t) * th) * a + np.sin(t * th) * b) / np.sin(th)


def twist_y(q):
    """ส่วนบิดรอบแกน Y ของกระดูก (swing-twist): q = swing * twist"""
    t = np.array([0.0, q[1], 0.0, q[3]])
    n = np.linalg.norm(t)
    return np.array([0, 0, 0, 1.0]) if n < 1e-9 else t / n


# ---------------- ตัวขับกระดูกช่วย (สูตรเดียวกับ soldier_figure.gd ทุกตัว) ----------------
CLAV_ELEV_K = 0.12          # ไหปลาร้ายกตาม (มุมยกแขน - 30°) × 0.12 (ยกน้อย: แขนในโครงเกมยกตามไม่ได้)
CLAV_ELEV_MAX = 15.0
CLAV_PROT_K = 0.12          # ไหปลาร้าไปหน้าตามแขนชี้หน้า
TWIST_K = 0.5               # uparm_twist รับการบิดคืน 50 %


def arm_dir(q_shoulder):
    """ทิศต้นแขนในกรอบอก (เวกเตอร์หน่วย)"""
    return qmat(q_shoulder) @ np.array([0.0, -1.0, 0.0])


def helper_rot(name, local):
    """local = dict กระดูก -> quaternion ของท่าปัจจุบัน ; คืน quaternion ของกระดูกช่วย"""
    sd = name[-1]
    sx = 1.0 if sd == "L" else -1.0
    if name.startswith("elbow_half"):
        return qslerp([0, 0, 0, 1], local["elbow" + sd], 0.5)
    if name.startswith("knee_half"):
        return qslerp([0, 0, 0, 1], local["knee" + sd], 0.5)
    if name.startswith("hip_half"):
        return qslerp([0, 0, 0, 1], local["hip" + sd], 0.5)
    if name.startswith("uparm_twist"):
        tw = twist_y(local["shoulder" + sd])
        return qslerp([0, 0, 0, 1], qinv(tw), TWIST_K)
    if name.startswith("clavicle"):
        d = arm_dir(local["shoulder" + sd])
        elev = np.degrees(np.arccos(np.clip(-d[1], -1, 1)))
        a = min(CLAV_ELEV_MAX, CLAV_ELEV_K * max(0.0, elev - 30.0))
        b = CLAV_PROT_K * np.degrees(np.arcsin(np.clip(d[2], -1, 1)))
        return qmul(qaxis([0, 1, 0], -sx * b), qaxis([0, 0, 1], sx * a))
    raise KeyError(name)


# ---------------- ท่า + forward kinematics ----------------

def ident_pose():
    return {"local": {b: np.array([0, 0, 0, 1.0]) for b in MAIN}, "pelvis_pos": PELVIS_IPOSE.copy()}


BIND_SHOULDER = 35.0        # ท่า A: กางแขน 35° งอศอก 8° กางขา 6° (เท้าวางราบ)
BIND_ELBOW = 8.0
BIND_HIP = 6.0


def bind_pose():
    p = ident_pose()
    L = p["local"]
    L["shoulderL"] = qaxis([0, 0, 1], BIND_SHOULDER)
    L["shoulderR"] = qaxis([0, 0, 1], -BIND_SHOULDER)
    L["elbowL"] = qaxis([1, 0, 0], -BIND_ELBOW)
    L["elbowR"] = qaxis([1, 0, 0], -BIND_ELBOW)
    L["hipL"] = qaxis([0, 0, 1], BIND_HIP)
    L["hipR"] = qaxis([0, 0, 1], -BIND_HIP)
    L["ankleL"] = qaxis([0, 0, 1], -BIND_HIP)
    L["ankleR"] = qaxis([0, 0, 1], BIND_HIP)
    # ยกเชิงกรานให้ฝ่าเท้าแตะพื้นเมื่อกางขา
    leg = (0.39 + 0.39) * S
    p["pelvis_pos"] = PELVIS_IPOSE - np.array([0, leg * (1 - np.cos(np.radians(BIND_HIP))), 0])
    return p


def fk(pose, helpers=True):
    """คืน dict กระดูก -> 4x4 (global) ; กระดูกช่วยคำนวณจากตัวขับ"""
    L = dict(pose["local"])
    if helpers:
        for n, _, _ in HELPERS:
            L[n] = helper_rot(n, L)
    G = {}
    for b in BONES:
        if b not in L:
            L[b] = np.array([0, 0, 0, 1.0])
        M = np.eye(4)
        M[:3, :3] = qmat(L[b])
        p = PARENT[b]
        if p is None:
            M[:3, 3] = pose["pelvis_pos"]
            G[b] = M
        else:
            M[:3, 3] = OFFSET[b] + np.asarray(pose.get("trans", {}).get(b, (0.0, 0.0, 0.0)), float)
            G[b] = G[p] @ M
    return G, L


IPOSE_G, _ = fk(ident_pose())
JOINT_I = {b: IPOSE_G[b][:3, 3].copy() for b in BONES}      # ตำแหน่งข้อในท่า I (กรอบนิยามกายวิภาค)


def bone_xform(G, b):
    """เมทริกซ์ 4x4 ที่พาจุดในกรอบท่า I ของกระดูก b ไปยังท่า G: x' = R (x - j_I) + j_G"""
    M = G[b].copy()
    T = np.eye(4)
    T[:3, 3] = -JOINT_I[b]
    return M @ T


def mirror_name(b):
    if b.endswith("L"):
        return b[:-1] + "R"
    if b.endswith("R"):
        return b[:-1] + "L"
    return b


def rig_json(k=None):
    """k = ร่างหลากหลาย: ย่อขยายทั้งตัว (ระยะกระดูก ท่าผูก H S คูณ k ; มุมเท่าเดิม) ; None = ทหารฐาน"""
    bind = bind_pose()
    G, L = fk(bind)
    out = {"H": H, "S": S, "bones": [], "bind_pose": {}, "limits": LIMITS,
           "drivers": {"clav_elev_k": CLAV_ELEV_K, "clav_elev_max": CLAV_ELEV_MAX, "clav_prot_k": CLAV_PROT_K,
                       "twist_k": TWIST_K},
           "bind_angles": {"shoulder_abduction": BIND_SHOULDER, "elbow_flexion": BIND_ELBOW,
                           "hip_abduction": BIND_HIP}}
    for b in BONES:
        rest_q = REST_Q.get(b, [0, 0, 0, 1])
        pos = PELVIS_REST if b == "pelvis" else OFFSET[b]
        bm = np.linalg.inv(G[b])[:3]
        if k is not None:
            pos = pos * k
            bm = bm.copy()
            bm[:, 3] = bm[:, 3] * k
        out["bones"].append({"name": b, "parent": PARENT[b], "rest_pos": [float(v) for v in pos],
                             "rest_q": [float(v) for v in rest_q], "helper": b not in MAIN and b not in FACE,
                             "face": b in FACE,
                             "bind": [[float(v) for v in row] for row in bm],
                             "bind_q": [float(v) for v in L[b]]})
    out["bind_pose"]["pelvis_pos"] = [float(v) for v in (bind["pelvis_pos"] if k is None else bind["pelvis_pos"] * k)]
    if k is not None:
        out["H"], out["S"] = H * k, S * k
    return out


if __name__ == "__main__":
    for b in MAIN:
        print("%-10s %s" % (b, np.round(JOINT_I[b], 4)))
    print(len(BONES), "bones;", len(HELPERS), "helpers;", len(FACE), "face")
    G, _ = fk(bind_pose())
    for b in ["shoulderL", "elbowL", "wristL", "handL", "hipL", "ankleL", "toeL", "clavicleL", "elbow_halfL"]:
        print("bind", b, np.round(G[b][:3, 3], 4))
