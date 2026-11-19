# ชุดเครื่องมือ SDF (numpy): รูปพื้นฐาน + การวางตามกระดูก + กริดรวมแบบนุ่ม (smin) เฉพาะกล่องของแต่ละชิ้น
# ทุกชิ้นนิยามในกรอบ "ท่า I" ของกระดูกที่ถือมัน (แกนเท่าโลก) แล้วย้ายไปท่าใดก็ได้ด้วยเมทริกซ์ของกระดูกนั้น
import numpy as np

F32 = np.float32
BIG = 1.0


def smin(a, b, k):
    if k <= 0:
        return np.minimum(a, b)
    h = np.clip(0.5 + 0.5 * (b - a) / k, 0.0, 1.0)
    return b + (a - b) * h - k * h * (1.0 - h)


def smax(a, b, k):
    return -smin(-a, -b, k)


def _len(v):
    return np.sqrt(np.einsum('...i,...i->...', v, v))


def ell_dist(q, r):
    """ระยะประมาณถึงทรงรี: q = พิกัดในกรอบทรงรี (...,3), r = รัศมี (...,3)"""
    k0 = _len(q / r)
    k1 = _len(q / (r * r))
    return k0 * (k0 - 1.0) / np.maximum(k1, 1e-9)


class Prim:
    """ชิ้นแข็งติดกระดูกเดียว: kind = ellipsoid | capsule | tube | loft | rbox ; outset = ไขมันใต้ผิวเหนือชิ้นนี้"""

    def __init__(self, kind, bone, outset=0.004, tag="core", name="", neg=False, k=None, weights=None, **p):
        self.kind = kind
        self.bone = bone
        self.outset = outset
        self.tag = tag
        self.name = name
        self.neg = neg
        self.k = k
        self.p = p
        self.weights = weights          # None = {bone: 1} ; หรือ list[(y, {bone: w})] สำหรับลำตัว (ตามความสูงท่า I)
        self._bb = self._bbox_local()

    # ---- กล่องในกรอบท่า I ----
    def _bbox_local(self):
        p = self.p
        if self.kind == "ellipsoid":
            c = np.asarray(p["c"], float)
            R = np.asarray(p.get("rot", np.eye(3)), float)
            r = np.asarray(p["r"], float)
            e = np.abs(R) @ r
            return c - e, c + e
        if self.kind == "capsule":
            a = np.asarray(p["a"], float)
            b = np.asarray(p["b"], float)
            r = max(p["ra"], p.get("rb", p["ra"]))
            return np.minimum(a, b) - r, np.maximum(a, b) + r
        if self.kind == "tube":
            pts = np.asarray(p["pts"], float)
            r = float(np.max(p["r"])) * max(1.0, float(np.max(p.get("scale", [1, 1, 1]))))
            return pts.min(0) - r, pts.max(0) + r
        if self.kind == "loft":
            S = np.asarray(p["sec"], float)     # y, cx, cz, a, bf, bb, n
            ys = S[:, 0]
            amax = np.max(np.abs(S[:, 1]) + S[:, 3])
            zlo = np.min(S[:, 2] - S[:, 5])
            zhi = np.max(S[:, 2] + S[:, 4])
            return np.array([-amax, ys.min(), zlo]), np.array([amax, ys.max(), zhi])
        if self.kind == "rbox":
            c = np.asarray(p["c"], float)
            R = np.asarray(p.get("rot", np.eye(3)), float)
            e = np.abs(R) @ (np.asarray(p["e"], float) + p.get("round", 0.0))
            return c - e, c + e
        if self.kind == "lid":
            c = np.asarray(p["c"], float)
            e = p["r"] + p["t"]
            return c - e, c + e
        if self.kind == "almond":
            c = np.asarray(p["c"], float)
            e = p["re"] + p["shell"] + 0.002
            return c - e, c + e
        raise ValueError(self.kind)

    def bbox(self, M):
        """กล่องในโลกเมื่อกระดูกอยู่ที่เมทริกซ์ M (4x4 ท่า I -> ท่าปัจจุบัน)"""
        lo, hi = self._bb
        cs = np.array([[x, y, z] for x in (lo[0], hi[0]) for y in (lo[1], hi[1]) for z in (lo[2], hi[2])])
        w = cs @ M[:3, :3].T + M[:3, 3]
        return w.min(0), w.max(0)

    # ---- ระยะ (P = จุดในกรอบท่า I ของกระดูก) ; คืน (d, พารามิเตอร์) ----
    def eval_local(self, P):
        p = self.p
        k = self.kind
        if k == "ellipsoid":
            R = np.asarray(p.get("rot", np.eye(3)), F32)
            q = (P - np.asarray(p["c"], F32)) @ R
            return ell_dist(q, np.asarray(p["r"], F32)), P[:, 1]
        if k == "capsule":
            a = np.asarray(p["a"], F32)
            b = np.asarray(p["b"], F32)
            ra = p["ra"]
            rb = p.get("rb", ra)
            pa = P - a
            ba = b - a
            h = np.clip((pa @ ba) / float(ba @ ba), 0.0, 1.0)
            return _len(pa - h[:, None] * ba) - (ra + (rb - ra) * h), h
        if k == "tube":
            return tube_dist(P, np.asarray(p["pts"], F32), np.asarray(p["r"], F32), p.get("scale"))
        if k == "loft":
            return loft_dist(P, p), P[:, 1]
        if k == "lid":
            # เปลือกตา: เปลือกบางบนลูกตา (รัศมี r+t) ตัดด้วยระนาบขอบเปลือกตา (side +1 = เก็บด้านบน, -1 = ด้านล่าง)
            q = P - np.asarray(p["c"], F32)
            d_shell = _len(q) - (p["r"] + p["t"])
            s_ = q @ np.asarray(p["n"], F32) - p["off"]
            d_cut = -s_ if p["side"] > 0 else s_
            return np.maximum(d_shell, d_cut), P[:, 1]
        if k == "rbox":
            R = np.asarray(p.get("rot", np.eye(3)), F32)
            q = np.abs((P - np.asarray(p["c"], F32)) @ R) - np.asarray(p["e"], F32)
            out = _len(np.maximum(q, 0.0)) + np.minimum(np.max(q, axis=1), 0.0)
            return out - p.get("round", 0.0), P[:, 1]
        if k == "almond":
            # ช่องเปิดตา (ชิ้นลบหลังชั้นไขมัน): รูปเมล็ดอัลมอนด์บนระนาบหน้า (จุดตัดวงกลมสองวง ปลายแหลม)
            #   เอียงให้หางตาสูงกว่าหัวตา ; ลึกเฉพาะเปลือกหน้าลูกตา (ไม่เจาะเลยลูกตา)
            q = P - np.asarray(p["c"], F32)
            a = np.radians(p["tilt"]) * p["sx"]
            ca, sa = np.cos(a), np.sin(a)
            u = ca * q[:, 0] + sa * q[:, 1]
            v = -sa * q[:, 0] + ca * q[:, 1]
            hw, hu, hl = p["hw"], p["hu"], p["hl"]
            ru = (hw * hw + hu * hu) / (2 * hu)
            rl = (hw * hw + hl * hl) / (2 * hl)
            d2 = np.maximum(np.sqrt(u * u + (v - (hu - ru)) ** 2) - ru, np.sqrt(u * u + (v - (rl - hl)) ** 2) - rl)
            d_sh = _len(q) - (p["re"] + p["shell"])
            d_fr = -(q[:, 2] - p["zmin"])
            return np.maximum(np.maximum(d2, d_sh), d_fr).astype(F32), P[:, 1]
        raise ValueError(k)

    def eval(self, Pw, M):
        """Pw = จุดในโลก ; M = เมทริกซ์ของกระดูก (ท่า I -> ท่าปัจจุบัน)"""
        R = M[:3, :3].astype(F32)
        Pl = (Pw - M[:3, 3].astype(F32)) @ R          # = R^T (p - t)
        return self.eval_local(Pl)


def tube_dist(P, pts, r, scale=None):
    """ท่อเรียวตามจุด (รัศมีต่อจุด) = กรวยปลายมนต่อกัน ; คืน (d, t 0..1 ตามความยาว)"""
    if scale is not None:
        s = np.asarray(scale, F32)
        P = P / s
        pts = pts / s
        smul = float(s.min())
    else:
        smul = 1.0
    best = np.full(len(P), 1e9, F32)
    bt = np.zeros(len(P), F32)
    n = len(pts) - 1
    for i in range(n):
        a = pts[i]
        b = pts[i + 1]
        pa = P - a
        ba = b - a
        h = np.clip((pa @ ba) / max(float(ba @ ba), 1e-12), 0.0, 1.0)
        d = _len(pa - h[:, None] * ba) - (r[i] + (r[i + 1] - r[i]) * h)
        m = d < best
        best = np.where(m, d, best)
        bt = np.where(m, (i + h) / n, bt)
    return best * smul, bt


def loft_table(sec, dy=0.001):
    S = np.asarray(sec, float)
    ys = S[:, 0]
    yy = np.arange(ys[0], ys[-1] + dy * 0.5, dy)
    # Catmull-Rom แบบ monotone ง่าย ๆ: ใช้ PCHIP ของ scipy
    from scipy.interpolate import PchipInterpolator
    tab = np.stack([PchipInterpolator(ys, S[:, j])(yy) for j in range(1, S.shape[1])], 1)
    return yy.astype(F32), tab.astype(F32)


def loft_dist(P, p):
    if "_tab" not in p:
        p["_tab"] = loft_table(p["sec"])
    yy, tab = p["_tab"]
    y = P[:, 1]
    i = np.clip(np.round((y - yy[0]) / (yy[1] - yy[0])).astype(np.int64), 0, len(yy) - 1)
    cx, cz, a, bf, bb, n = (tab[i, j] for j in range(6))
    dx = np.abs(P[:, 0] - cx)
    dzs = P[:, 2] - cz
    b = np.where(dzs > 0, bf, bb)
    dz = np.abs(dzs)
    ux = dx / a
    uz = dz / b
    rho = (ux ** n + uz ** n) ** (1.0 / n)
    rho_s = np.maximum(rho, 1e-6)
    gx = ux ** (n - 1) / a * rho_s ** (1 - n)
    gz = uz ** (n - 1) / b * rho_s ** (1 - n)
    g = np.sqrt(gx * gx + gz * gz)
    d2 = (rho - 1.0) / np.maximum(g, 1e-6)
    cap = np.maximum(yy[0] - y, y - yy[-1])
    w0 = d2
    w1 = cap
    return np.minimum(np.maximum(w0, w1), 0.0) + np.sqrt(np.maximum(w0, 0) ** 2 + np.maximum(w1, 0) ** 2)


def etube_dist(P, C, U, V, W, Hh):
    """ท่อหน้าตัดวงรีตามเส้นกลาง C (M,3) กรอบ U (กว้าง) V (หนา) รัศมี W, Hh ; คืน (d, t)"""
    n = len(C) - 1
    best = np.full(len(P), 1e9, F32)
    bt = np.zeros(len(P), F32)
    for i in range(n):
        a = C[i]
        b = C[i + 1]
        ab = b - a
        L2 = max(float(ab @ ab), 1e-12)
        pa = P - a
        h = np.clip((pa @ ab) / L2, 0.0, 1.0)
        c = a + h[:, None] * ab
        u = U[i] + (U[i + 1] - U[i]) * h[:, None]
        v = V[i] + (V[i + 1] - V[i]) * h[:, None]
        u /= np.maximum(_len(u), 1e-9)[:, None]
        v /= np.maximum(_len(v), 1e-9)[:, None]
        w = W[i] + (W[i + 1] - W[i]) * h
        hh = Hh[i] + (Hh[i + 1] - Hh[i]) * h
        dv = P - c
        t = ab / np.sqrt(L2)
        q = np.stack([np.einsum('ij,ij->i', dv, u), np.einsum('ij,ij->i', dv, v), dv @ t], 1)
        rz = np.minimum(w, hh)
        r = np.stack([w, hh, rz], 1)
        d = ell_dist(q, r)
        m = d < best
        best = np.where(m, d, best)
        bt = np.where(m, (i + h) / n, bt)
    return best, bt


class Grid:
    def __init__(self, lo, hi, h):
        self.h = float(h)
        self.lo = np.asarray(lo, float)
        self.n = tuple(int(np.ceil((np.asarray(hi, float)[i] - self.lo[i]) / h)) + 1 for i in range(3))
        self.F = np.full(self.n, BIG, F32)

    def slices(self, lo, hi):
        i0 = np.maximum(np.floor((np.asarray(lo) - self.lo) / self.h).astype(int), 0)
        i1 = np.minimum(np.ceil((np.asarray(hi) - self.lo) / self.h).astype(int) + 1, np.array(self.n))
        if np.any(i1 <= i0):
            return None
        return tuple(slice(int(a), int(b)) for a, b in zip(i0, i1))

    def points(self, sl):
        ax = [self.lo[i] + np.arange(sl[i].start, sl[i].stop) * self.h for i in range(3)]
        X, Y, Z = np.meshgrid(*ax, indexing='ij')
        return np.stack([X.ravel(), Y.ravel(), Z.ravel()], 1).astype(F32)

    def combine(self, sl, d, k, neg=False):
        sub = self.F[sl]
        d = d.reshape(sub.shape)
        self.F[sl] = smax(sub, -d, k) if neg else smin(sub, d, k)

    def sample(self, P):
        """trilinear (P (N,3) ในโลก) ; นอกกริด = BIG"""
        from scipy.ndimage import map_coordinates
        idx = ((np.asarray(P, float) - self.lo) / self.h).T
        return map_coordinates(self.F, idx, order=1, mode='constant', cval=BIG)

    def grad(self, P, e=None):
        e = e or self.h
        g = np.zeros((len(P), 3))
        for i in range(3):
            d = np.zeros(3)
            d[i] = e
            g[:, i] = (self.sample(P + d) - self.sample(P - d)) / (2 * e)
        return g


def rotm(axis, deg):
    a = np.asarray(axis, float)
    a = a / np.linalg.norm(a)
    t = np.radians(deg)
    K = np.array([[0, -a[2], a[1]], [a[2], 0, -a[0]], [-a[1], a[0], 0]])
    return np.eye(3) + np.sin(t) * K + (1 - np.cos(t)) * K @ K


def frame_from(axis_y, hint_z=(0, 0, 1)):
    """เมทริกซ์หมุนที่คอลัมน์ 1 = axis_y (ใช้หมุนทรงรีให้แกนยาวตามทิศ)"""
    y = np.asarray(axis_y, float)
    y = y / np.linalg.norm(y)
    z = np.asarray(hint_z, float)
    z = z - y * (z @ y)
    if np.linalg.norm(z) < 1e-6:
        z = np.array([1.0, 0, 0]) - y * y[0]
    z = z / np.linalg.norm(z)
    x = np.cross(y, z)
    return np.stack([x, y, z], 1)
