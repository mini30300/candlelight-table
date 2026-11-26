# กล้ามเนื้อเชิงกระบวนการ: เส้นใยจากจุดเกาะต้นถึงปลายผ่านจุด via (ทุกจุดติดกระดูกของมัน) -> เส้นโค้ง Catmull-Rom
#   พันรอบกระดูก/แกนลึก (ดันจุดออกเมื่อจม) ; ปริมาตรคงที่: ท้องกล้ามหดสั้น -> หนาขึ้น (เอ็นยาวคงที่)
#   หน้าตัดวงรี: แกนหนาตามเกรเดียนต์ของแกนลึก (แนวตั้งฉากผิวกาย) แกนกว้างตามแนวแผ่น
import numpy as np
import anatomy as A
import rig
from sdfk import etube_dist, F32
import variants as VR

M_SAMPLES = 16
_L0 = {}            # (ชื่อมัด, ข้าง, เส้นใย) -> ความยาวท่า I
NO_OBSTACLE = {"spinous_line", "c7_land"}   # สันกลางหลัง: ไม่ใช้ดันกล้าม (กันปลายกล้ามซ้าย/ขวาเบี่ยงไขว้กัน)


def _mirror_pt(bp):
    b, p = bp
    return rig.mirror_name(b), (-p[0], p[1], p[2])


def muscle_defs():
    out = []
    for m in A.MUSCLES_L:
        out.append(("L", m))
        r = dict(m)
        r["o"] = [_mirror_pt(x) for x in m["o"]]
        r["i"] = [_mirror_pt(x) for x in m["i"]]
        r["v"] = [[_mirror_pt(x) for x in vv] for vv in m["v"]]
        r["w"] = [(t, b if b == "@o" else rig.mirror_name(b)) for t, b in m["w"]]
        out.append(("R", r))
    return out


DEFS = muscle_defs()


def _catmull(P, n):
    P = np.asarray(P, float)
    if len(P) == 2:
        t = np.linspace(0, 1, n)[:, None]
        return P[0] * (1 - t) + P[1] * t
    Q = np.vstack([2 * P[0] - P[1], P, 2 * P[-1] - P[-2]])
    # ความยาวสะสม เพื่อกระจายจุดสม่ำเสมอ
    segs = len(P) - 1
    dense = []
    for s in range(segs):
        p0, p1, p2, p3 = Q[s:s + 4]
        for t in np.linspace(0, 1, 9)[:-1]:
            t2, t3 = t * t, t * t * t
            dense.append(0.5 * ((2 * p1) + (-p0 + p2) * t + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t2 +
                                (-p0 + 3 * p1 - 3 * p2 + p3) * t3))
    dense.append(P[-1])
    dense = np.array(dense)
    L = np.concatenate([[0], np.cumsum(np.linalg.norm(np.diff(dense, axis=0), axis=1))])
    u = np.linspace(0, L[-1], n)
    return np.stack([np.interp(u, L, dense[:, j]) for j in range(3)], 1)


def _poly_at(pl, s, Mb):
    """จุดบนรายการ (กระดูก, จุด) ที่พารามิเตอร์ s (ย้ายแต่ละจุดตามกระดูกของมันก่อนแล้วค่อยเฉลี่ย)"""
    n = len(pl)
    if n == 1:
        b, p = pl[0]
        return Mb(b) @ np.array([*p, 1.0]), b
    u = s * (n - 1)
    j = min(int(np.floor(u)), n - 2)
    f = u - j
    b0, p0 = pl[j]
    b1, p1 = pl[j + 1]
    q0 = Mb(b0) @ np.array([*p0, 1.0])
    q1 = Mb(b1) @ np.array([*p1, 1.0])
    return q0 * (1 - f) + q1 * f, (b0 if f < 0.5 else b1)


def _belly(t, t0, t1):
    u = np.clip((t - t0) / max(1e-6, 1 - t0 - t1), 0, 1)
    return np.sin(np.pi * u) ** 0.55


def _interp_knots(knots, t, default=1.0):
    if not knots:
        return np.full_like(t, default)
    k = np.array(knots, float)
    return np.interp(t, k[:, 0], k[:, 1])


class Obstacles:
    """แกนลึก + ปุ่มกระดูก ที่กล้ามเนื้อต้องพาดทับ (ในท่าปัจจุบัน)"""

    def __init__(self, prims, G):
        self.prims = [p for p in prims if p.tag in ("core", "land") and not p.neg and p.name not in NO_OBSTACLE]
        self.G = G
        self.M = {}

    def mat(self, b):
        if b not in self.M:
            self.M[b] = rig.bone_xform(self.G, b)
        return self.M[b]

    def field(self, P, bones):
        d = np.full(len(P), 1.0, F32)
        for p in self.prims:
            if p.bone not in bones:
                continue
            dd, _ = p.eval(P.astype(F32), self.mat(p.bone))
            d = np.minimum(d, dd)
        return d

    def grad(self, P, bones, e=0.002):
        g = np.zeros((len(P), 3))
        for i in range(3):
            dv = np.zeros(3)
            dv[i] = e
            g[:, i] = (self.field(P + dv, bones) - self.field(P - dv, bones)) / (2 * e)
        return g


def _obstacle_bones(m):
    bs = set()
    for b, _ in m["o"] + m["i"] + [x for vv in m["v"] for x in vv]:
        bs.add(b)
        if rig.PARENT.get(b):
            bs.add(rig.PARENT[b])
    if any(b.startswith("clavicle") for b in bs):
        bs.add("spine")
    return bs


def build(G, prims, ipose_ref=False):
    """สร้างกล้ามทุกมัดในท่า G ; คืน list ของ dict(name, side, fibres[...], outset, colour, w)"""
    obs = Obstacles(prims, G)
    Mb = obs.mat
    out = []
    for side, m in DEFS:
        K = m["K"]
        bones = _obstacle_bones(m)
        fibres = []
        for k in range(K):
            s = 0.5 if K == 1 else k / (K - 1)
            o, ob = _poly_at(m["o"], s, Mb)
            ctrl = [o[:3]]
            for vv in m["v"]:
                ctrl.append(_poly_at(vv, s, Mb)[0][:3])
            ctrl.append(_poly_at(m["i"], s, Mb)[0][:3])
            C = _catmull(ctrl, M_SAMPLES)
            t = np.linspace(0, 1, M_SAMPLES)
            t0, t1 = m["tendon"]
            bel = _belly(t, t0, t1)
            thick = _interp_knots(m["thick"], t)
            dips = np.ones_like(t)
            for (tc, depth, sig) in m["dips"]:
                dips *= 1 - depth * np.exp(-0.5 * ((t - tc) / sig) ** 2)
            W0 = m["tend"][0] + (m["R"] - m["tend"][0]) * bel
            ft = 1.0 if not m.get("fthick") else m["fthick"][k]
            H0 = m["tend"][1] + (m["R"] * m["flat"] * thick * dips * ft - m["tend"][1]) * bel
            if VR.cfg().get("muscle"):
                # ร่างหลากหลาย / ร่างหลัก 0.17: ระดับกล้าม (ท้องกล้ามหนา/บางลง ; กว้างเปลี่ยนน้อยกว่า)
                mk = VR.muscle_k(m["name"])
                W0 = m["tend"][0] + (m["R"] * (1 + 0.35 * (mk - 1)) - m["tend"][0]) * bel
                H0 = m["tend"][1] + (m["R"] * m["flat"] * thick * dips * ft * mk - m["tend"][1]) * bel
            # พันรอบกระดูก: ดันจุดกลางออกเมื่อจมแกนลึก และดึงเข้าแนบเมื่อลอย (กล้ามวางบนโครงเสมอ ไม่ลอยเป็นช่อง)
            if m["wrap"]:
                ramp = (0.5 + 0.5 * np.clip(np.minimum(t, 1 - t) / 0.12, 0, 1))[:, None]   # ปลายก็แนบ (ครึ่งแรง)
                hug = m.get("hug", 1.0)
                for _ in range(3):
                    d = obs.field(C, bones)
                    want = 0.85 * H0 + m.get("lift", 0.0)
                    delta = want - d
                    delta = np.where(delta < 0, np.maximum(delta, -0.015) * hug, delta)[:, None]
                    if not np.any(np.abs(delta) > 1e-5):
                        break
                    g = obs.grad(C, bones)
                    g /= np.maximum(np.linalg.norm(g, axis=1), 1e-9)[:, None]
                    C = C + g * delta * ramp
                C = _smooth_poly(C, 2)
            L = float(np.sum(np.linalg.norm(np.diff(C, axis=0), axis=1)))
            key = (m["name"], side, k)
            if ipose_ref or key not in _L0:
                _L0[key] = L
            L0 = _L0[key]
            Lt = (t0 + t1) * L0
            f = float(np.clip((L0 - Lt) / max(L - Lt, 1e-4), 0.55, 2.2))
            alpha = float(np.interp(m["flat"], [0.4, 0.7], [1.0, 0.5]))
            Hh = H0 * (1 + (f ** alpha - 1) * bel)
            W = W0 * (1 + (f ** (1 - alpha) - 1) * bel)
            # กรอบหน้าตัด: V = ทิศออกจากแกนลึก (ตั้งฉากเส้นใย)
            T = np.gradient(C, axis=0)
            T /= np.maximum(np.linalg.norm(T, axis=1), 1e-9)[:, None]
            g = obs.grad(C, bones)
            V = g - T * np.einsum('ij,ij->i', g, T)[:, None]
            bad = np.linalg.norm(V, axis=1) < 1e-6
            if np.any(bad):
                alt = np.cross(T[bad], np.array([0.3, 0.5, 0.8]))
                V[bad] = alt
            V /= np.maximum(np.linalg.norm(V, axis=1), 1e-9)[:, None]
            V = _smooth_dirs(V, T)
            U = np.cross(T, V)
            U /= np.maximum(np.linalg.norm(U, axis=1), 1e-9)[:, None]
            fibres.append(dict(C=C.astype(F32), U=U.astype(F32), V=V.astype(F32), W=W.astype(F32), Hh=Hh.astype(F32),
                               t=t, L=L, L0=L0, f=f, obone=ob))
        out.append(dict(name=m["name"], side=side, fibres=fibres, outset=m["outset"], colour=m["colour"], w=m["w"],
                        R=m["R"], K=K, tendon=m["tendon"]))
    return out


def _smooth_poly(C, it):
    C = C.copy()
    for _ in range(it):
        C[1:-1] = 0.25 * C[:-2] + 0.5 * C[1:-1] + 0.25 * C[2:]
    return C


def _smooth_dirs(V, T):
    V = V.copy()
    for _ in range(2):
        V[1:-1] = 0.25 * V[:-2] + 0.5 * V[1:-1] + 0.25 * V[2:]
        V = V - T * np.einsum('ij,ij->i', V, T)[:, None]
        V /= np.maximum(np.linalg.norm(V, axis=1), 1e-9)[:, None]
    return V


def fibre_bbox(fb, margin=0.0):
    r = float(max(fb["W"].max(), fb["Hh"].max())) + margin
    return fb["C"].min(0) - r, fb["C"].max(0) + r


def muscle_bbox(mu, margin=0.0):
    los, his = zip(*[fibre_bbox(f, margin) for f in mu["fibres"]])
    return np.min(los, 0), np.max(his, 0)


def fibre_field(grid_like, sl, fb, P=None):
    """ระยะของเส้นใยบนจุดของกล่อง sl ในกริด (ประเมินทีละท่อนเฉพาะกล่องย่อยของท่อน)"""
    h = grid_like.h
    shape = tuple(s.stop - s.start for s in sl)
    out = np.full(shape, 1.0, F32)
    C, U, V, W, Hh = fb["C"], fb["U"], fb["V"], fb["W"], fb["Hh"]
    lo0 = grid_like.lo + np.array([s.start for s in sl]) * h
    for i in range(len(C) - 1):
        r = float(max(W[i], W[i + 1], Hh[i], Hh[i + 1])) + 0.012
        a = np.minimum(C[i], C[i + 1]) - r
        b = np.maximum(C[i], C[i + 1]) + r
        i0 = np.maximum(np.floor((a - lo0) / h).astype(int), 0)
        i1 = np.minimum(np.ceil((b - lo0) / h).astype(int) + 1, np.array(shape))
        if np.any(i1 <= i0):
            continue
        ax = [lo0[j] + np.arange(i0[j], i1[j]) * h for j in range(3)]
        X, Y, Z = np.meshgrid(*ax, indexing='ij')
        Pp = np.stack([X.ravel(), Y.ravel(), Z.ravel()], 1).astype(F32)
        d, _ = etube_dist(Pp, C[i:i + 2], U[i:i + 2], V[i:i + 2], W[i:i + 2], Hh[i:i + 2])
        sub = (slice(i0[0], i1[0]), slice(i0[1], i1[1]), slice(i0[2], i1[2]))
        out[sub] = np.minimum(out[sub], d.reshape(out[sub].shape))
    return out


def muscle_eval_points(mu, P):
    """ระยะ (ต่อจุด) ถึงมัดกล้าม + t ของเส้นใยที่ใกล้สุด + ดัชนีเส้นใย (ใช้คำนวณน้ำหนักผิว)"""
    best = np.full(len(P), 1.0, F32)
    bt = np.zeros(len(P), F32)
    bk = np.zeros(len(P), np.int32)
    for k, fb in enumerate(mu["fibres"]):
        lo, hi = fibre_bbox(fb, 0.07)
        m = np.all((P >= lo) & (P <= hi), axis=1)
        if not np.any(m):
            continue
        d, t = etube_dist(P[m].astype(F32), fb["C"], fb["U"], fb["V"], fb["W"], fb["Hh"])
        cur = best[m]
        better = d < cur
        idx = np.nonzero(m)[0][better]
        best[idx] = d[better]
        bt[idx] = t[better]
        bk[idx] = k
    return best, bt, bk


def init_lengths(prims):
    """ความยาวอ้างอิงของทุกเส้นใยในท่า I (ท่ายืนตรงแขนห้อย = ความยาวพัก)"""
    G, _ = rig.fk(rig.ident_pose())
    return build(G, prims, ipose_ref=True)
