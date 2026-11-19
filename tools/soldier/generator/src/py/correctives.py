# ท่าแก้ (corrective blend shapes) จากแบบจำลองกล้ามเนื้อ:
#   ท่าหลัก 7 ท่า/ข้าง -> สร้างกล้ามในท่านั้น (เส้นใยตามกระดูก ท้องกล้ามหดแล้วหนาขึ้น) -> สนามผิวเฉพาะกล่องรอบข้อ
#   -> ผิว LBS (+กระดูกช่วย) ในท่านั้น -> ฉายลงผิวเป้าหมาย -> ส่วนต่างย้อนกลับเป็นกรอบท่าผูก (bind) = blend shape
#   ตัวขับ (driver) ในเกม: มุมข้อ -> น้ำหนัก (สูตรเดียวกับ soldier_figure.gd)
import numpy as np
import rig
import muscles as MU
import field as FD
import weights as WT
from mesh import adjacency

S35 = np.radians(rig.BIND_SHOULDER)
ARM_KEYS = {   # ทิศต้นแขนในกรอบอก (ข้างซ้าย)
    "bind": np.array([np.sin(S35), -np.cos(S35), 0.0]),
    "down": np.array([np.sin(np.radians(5)), -np.cos(np.radians(5)), 0.0]),
    "front": np.array([0.0, 0.0, 1.0]),
    "up": np.array([np.sin(np.radians(160)), -np.cos(np.radians(160)), 0.0]),
}
ELBOW_KEY = 120.0
KNEE_KEY = 120.0
HIP_FLEX_KEY = 100.0
HIP_EXT_KEY = 25.0
# เป้าหมายของท่าแก้ "แขนแนบตัว" คิดแบบคนจริง: เมื่อแขนลงจากท่า A สะบัก/ไหปลาร้าหมุนลง (ปลายไหล่ต่ำลง ~1-1.5 ซม.)
#   ใช้กับสนามเป้าหมายเท่านั้น (ตัวขับในเกมไม่เปลี่ยน ไม่มีสูตรใหม่ให้พอร์ต)
CLAV_DOWN_TARGET = 7.0

SHAPES = []
for _sd in ("L", "R"):
    SHAPES += ["shoulder_down" + _sd, "shoulder_front" + _sd, "shoulder_up" + _sd, "elbow_flex" + _sd,
               "knee_flex" + _sd, "hip_flex" + _sd, "hip_ext" + _sd]


def _ang(a, b):
    return np.degrees(np.arccos(np.clip(np.dot(a, b) / (np.linalg.norm(a) * np.linalg.norm(b)), -1, 1)))


def _ease(x):
    x = np.clip(x, 0, 1)
    return x * x * (3 - 2 * x)


def driver_weights(local):
    """local = quaternion ของกระดูกหลัก (ท่าปัจจุบัน) -> dict ชื่อท่าแก้ -> น้ำหนัก 0..1"""
    out = {}
    down = np.array([0.0, -1.0, 0.0])
    for sd, sx in (("L", 1.0), ("R", -1.0)):
        d = rig.qmat(local["shoulder" + sd]) @ down
        d = d * np.array([sx, 1, 1])
        for k in ("down", "front", "up"):
            r = _ang(ARM_KEYS["bind"], ARM_KEYS[k])
            out["shoulder_%s%s" % (k, sd)] = float(_ease(1 - _ang(d, ARM_KEYS[k]) / r))
        fe = rig.qmat(local["elbow" + sd]) @ down
        th = _ang(fe, down)
        out["elbow_flex" + sd] = float(np.clip((th - rig.BIND_ELBOW) / (ELBOW_KEY - rig.BIND_ELBOW), 0, 1))
        fk = rig.qmat(local["knee" + sd]) @ down
        out["knee_flex" + sd] = float(np.clip(_ang(fk, down) / KNEE_KEY, 0, 1))
        th_ = rig.qmat(local["hip" + sd]) @ down
        phi = np.degrees(np.arctan2(th_[2], -th_[1]))
        out["hip_flex" + sd] = float(np.clip(phi / HIP_FLEX_KEY, 0, 1))
        out["hip_ext" + sd] = float(np.clip(-phi / HIP_EXT_KEY, 0, 1))
    return out


def key_pose(shape):
    """ท่าหลักของแต่ละท่าแก้ (จากท่าผูก A)"""
    p = rig.bind_pose()
    L = p["local"]
    sd = shape[-1]
    sx = 1.0 if sd == "L" else -1.0
    base = shape[:-1]
    if base == "shoulder_down":
        L["shoulder" + sd] = rig.qaxis([0, 0, 1], sx * 5)
        joint, box, rr = "shoulder" + sd, 0.25, (0.12, 0.24)
    elif base == "shoulder_front":
        L["shoulder" + sd] = rig.qaxis([1, 0, 0], -90)
        joint, box, rr = "shoulder" + sd, 0.25, (0.12, 0.24)
    elif base == "shoulder_up":
        L["shoulder" + sd] = rig.qaxis([0, 0, 1], sx * 160)
        joint, box, rr = "shoulder" + sd, 0.27, (0.12, 0.26)
    elif base == "elbow_flex":
        L["elbow" + sd] = rig.qaxis([1, 0, 0], -ELBOW_KEY)
        joint, box, rr = "elbow" + sd, 0.17, (0.08, 0.16)
    elif base == "knee_flex":
        L["knee" + sd] = rig.qaxis([1, 0, 0], KNEE_KEY)
        joint, box, rr = "knee" + sd, 0.19, (0.09, 0.18)
    elif base == "hip_flex":
        L["hip" + sd] = rig.qmul(rig.qaxis([0, 0, 1], sx * rig.BIND_HIP), rig.qaxis([1, 0, 0], -HIP_FLEX_KEY))
        joint, box, rr = "hip" + sd, 0.26, (0.12, 0.25)
    elif base == "hip_ext":
        L["hip" + sd] = rig.qmul(rig.qaxis([0, 0, 1], sx * rig.BIND_HIP), rig.qaxis([1, 0, 0], HIP_EXT_KEY))
        joint, box, rr = "hip" + sd, 0.26, (0.12, 0.25)
    else:
        raise KeyError(shape)
    return p, joint, box, rr


def mirror_shapes(D, pair):
    """ท่าแก้ฝั่งขวา = ภาพสะท้อนของฝั่งซ้าย (ผิวปั้นสมมาตรพอดี: pair = จุดคู่สะท้อน)"""
    out = dict(D)
    for k in list(D):
        if k.endswith("L"):
            out[k[:-1] + "R"] = D[k][pair] * np.array([-1.0, 1.0, 1.0])
    return out


def clav_lowered(G, L, sd, deg):
    """สำเนาท่า G ที่กระดูกช่วยไหปลาร้าข้าง sd กดลงเพิ่ม deg องศา (กระดูกช่วยเป็นใบไม้ -> เปลี่ยนแค่ตัวเดียว)"""
    sx = 1.0 if sd == "L" else -1.0
    b = "clavicle" + sd
    q = rig.qmul(L[b], rig.qaxis([0, 0, 1], -sx * deg))
    M = np.eye(4)
    M[:3, :3] = rig.qmat(q)
    M[:3, 3] = rig.OFFSET[b]
    Gt = dict(G)
    Gt[b] = G[rig.PARENT[b]] @ M
    return Gt


def project(g, P, it=8, step=0.01, total=0.035):
    Q = P.copy()
    for _ in range(it):
        f = g.sample(Q)
        gr = g.grad(Q)
        n2 = np.maximum((gr * gr).sum(1), 1e-6)
        dv = -(f / n2)[:, None] * gr
        ln = np.linalg.norm(dv, axis=1, keepdims=True)
        dv = dv * np.minimum(1.0, step / np.maximum(ln, 1e-9))
        Q = Q + dv
        off = Q - P
        lo = np.linalg.norm(off, axis=1, keepdims=True)
        Q = P + off * np.minimum(1.0, total / np.maximum(lo, 1e-9))
    return Q


def compute(Vb, Fb, Wh, prims, Gb, verbose=True, shapes=None, fat=1.0):
    """Vb = เมชละเอียดท่าผูก ; Wh = น้ำหนัก (มีกระดูกช่วย) ; คืน dict ท่าแก้ -> delta (n,3) กรอบท่าผูก + สถิติ"""
    A = adjacency(Fb, len(Vb))
    from mesh import vnormals
    Nb = vnormals(Vb, Fb)
    out, stats = {}, {}
    for shape in (shapes or SHAPES):
        pose, joint, box, (r0, r1) = key_pose(shape)
        G, L = rig.fk(pose)
        jb = Gb[joint][:3, 3]
        jp = G[joint][:3, 3]
        dist = np.linalg.norm(Vb - jb, axis=1)
        side = np.sign(rig.JOINT_I[joint][0])
        mask = 1 - _ease((dist - r0) / (r1 - r0))
        if side != 0:
            mask *= (Vb[:, 0] * side > -0.02).astype(float)
        sel = mask > 1e-3
        Gt = clav_lowered(G, L, shape[-1], CLAV_DOWN_TARGET) if shape.startswith("shoulder_down") else G
        mus = MU.build(Gt, prims)
        lo = jp - box
        hi = jp + box
        g = FD.skin_coarse(Gt, prims, mus, fat=fat, h=0.003, box=(lo, hi), sigma=0.0025)
        P, Mix = WT.lbs(Vb[sel], Wh[sel], Gb, G)
        inside = np.all((P > lo + 0.01) & (P < hi - 0.01), axis=1)
        Q = P.copy()
        Q[inside] = project(g, P[inside])
        dW = Q - P
        # กันรอยบุ๋ม: ส่วนที่ดันเข้าในเนื้อจำกัด 1 ซม. ; ยาวรวมไม่เกิน 2.5 ซม. (จุดที่ยุบซ้อนกันจะไม่ถูกดึงไปคนละผิว)
        npz = np.einsum('nij,nj->ni', Mix, Nb[sel])
        npz /= np.maximum(np.linalg.norm(npz, axis=1, keepdims=True), 1e-9)
        inn = np.einsum('ij,ij->i', dW, npz)
        dW = dW - np.minimum(inn + 0.010, 0.0)[:, None] * npz
        ln = np.linalg.norm(dW, axis=1, keepdims=True)
        dW = dW * np.minimum(1.0, 0.025 / np.maximum(ln, 1e-9))
        dB = np.einsum('nij,nj->ni', np.linalg.inv(Mix), dW)
        D = np.zeros_like(Vb)
        D[sel] = dB
        for _ in range(8):
            D = 0.5 * D + 0.5 * (A @ D)
        D *= mask[:, None]
        out[shape] = D
        before = np.abs(g.sample(P[inside]))
        st = {"verts": int(sel.sum()), "mean_err_before_mm": float(before.mean() * 1000),
              "p95_err_before_mm": float(np.percentile(before, 95) * 1000),
              "max_delta_mm": float(np.linalg.norm(D, axis=1).max() * 1000)}
        stats[shape] = st
        if verbose:
            print("  corrective %-16s verts %6d  LBS error mean %.1f mm p95 %.1f mm  max delta %.1f mm" %
                  (shape, st["verts"], st["mean_err_before_mm"], st["p95_err_before_mm"], st["max_delta_mm"]), flush=True)
    return out, stats


def evaluate(Vb, Wh, Wmin, D, prims, Gb, pose, joint, box=0.2, fat=1.0):
    """ท่าทดสอบ (ระหว่างท่าหลัก): ความคลาดจากผิวกล้ามจริง ของ min (LBS ล้วน) / lo (+กระดูกช่วย) / hi (+ท่าแก้)"""
    G, L = rig.fk(pose)
    jp = G[joint][:3, 3]
    mus = MU.build(G, prims)
    g = FD.skin_coarse(G, prims, mus, fat=fat, h=0.003, box=(jp - box, jp + box), sigma=0.0025)
    wts = driver_weights(L)
    Dsum = np.zeros_like(Vb)
    for k, w in wts.items():
        if w > 0 and k in D:
            Dsum += w * D[k]
    P_min, _ = WT.lbs(Vb, Wmin, Gb, G)
    P_lo, Mix = WT.lbs(Vb, Wh, Gb, G)
    P_hi, _ = WT.lbs(Vb + Dsum, Wh, Gb, G)
    jb = Gb[joint][:3, 3]
    near = np.linalg.norm(Vb - jb, axis=1) < box * 0.7
    res = {}
    for nm, P in (("min_lbs", P_min), ("lo_helpers", P_lo), ("hi_correctives", P_hi)):
        inside = near & np.all((P > jp - box + 0.01) & (P < jp + box - 0.01), axis=1)
        e = np.abs(g.sample(P[inside]))
        res[nm] = {"mean_mm": round(float(e.mean() * 1000), 2), "p95_mm": round(float(np.percentile(e, 95) * 1000), 2)}
    res["driver"] = {k: round(v, 3) for k, v in wts.items() if v > 0.001}
    return res
