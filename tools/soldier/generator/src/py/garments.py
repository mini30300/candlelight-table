# ผ้าของชุดสนาม (ใหม่ 0.14 ข้อ 4): เสื้อแขนยาวเหน็บในกางเกง กางเกงพับเข้ารองเท้า เข็มขัด + กระเป๋า 4 ใบ รองเท้าผูกเชือกพื้นจริง หัวเปล่า
#   เมชเดียวต่อระดับแทนผิว (1 draw): ผิวที่โผล่ (หัว คอ มือ) = ผิวระดับเดิมของร่าง (หน้า CUSTOM1 น้ำหนักหน้า รอยต่อปากเดิม)
#   ตัดตามคอเสื้อ/ปลายแขน (cut_along) ; ส่วนที่ผ้าคลุม = ผิวระดับเดิมยกเป็นผ้า (คลุมร่องแบบผ้าตึง + หนา 3.5 มม.)
#   แล้วลดสามเหลี่ยมใหม่ (จุดขอบผ้าล็อกไว้) ; ขอบผ้า = แถบจากผิวถึงผิวผ้า ; ขอบรองเท้า/พื้นรองเท้า = cut_along + band_rows
#   เข็มขัด หัวเข็มขัด กระเป๋า = ชิ้นปิดแยก ผูกแข็งตามเข็มขัด ; คิดในกรอบ 1.78 ม. ; สนามคิดในท่า I ด้วย |x| (ซ้าย-ขวาเท่ากัน)
import numpy as np
from scipy.spatial import cKDTree
import rig
import mesh as ME
import weights as WT
import parts as PT
import face as FC
import variants as VR
import outfits as OF

Y_CUFF = 0.885        # ปลายแขนเสื้อ (ท่า I ม.): เหนือข้อมือ 2.3 ซม.
Y_BELT = 1.025        # กลางเข็มขัด = ขอบกางเกง (ใต้สะดือ)
BELT_H, BELT_T = 0.045, 0.004
Y_BOOT = 0.235        # ขอบรองเท้าหุ้มครึ่งน่อง
Y_SOLE = 0.020        # ขอบบนพื้นรองเท้า (พื้นหนา)
# ผ้าหลวมเฉพาะที่ (ท่า I: กลาง, รัศมี, ม.) ที่ท่าสุดของเกมทำให้ผิวโผล่: ใต้ก้น (ล้ม) หน้าไหล่ (ยิง) ข้างคอใต้ปก (ล้มคว่ำ)
BLOBS = (((0.065, 0.835, -0.075), (0.040, 0.040, 0.040), 0.005),
         ((0.212, 1.467, 0.053), (0.035, 0.035, 0.035), 0.006), ((0.054, 1.509, 0.013), (0.030, 0.025, 0.040), 0.005))
# รักแร้ + รอยพับหน้ารักแร้ + เป้า (หน้า-หลังกว้างขึ้น 0.15) + ขาหนีบหน้า: ผ้าบางแนบผิว (ชั้นที่ยกสูงถูก LBS หมุนทิศจนผิวโผล่) ; ท่า I: กลาง, รัศมี
THIN = (((0.188, 1.328, 0.000), (0.045, 0.075, 0.075)), ((0.205, 1.458, 0.059), (0.030, 0.030, 0.030)),
        ((0.000, 0.837, 0.010), (0.030, 0.035, 0.060)), ((0.029, 0.890, 0.064), (0.030, 0.030, 0.030)))


EXTRA_BLOBS, EXTRA_THIN = [], []   # เพิ่มต่อร่างโดย outfits.build จากจุดที่เกตท่าไม่ผ่าน (รอบถัดไป)


def armpit_w(PI):
    return np.max([np.exp(-np.sum(((PI - np.array(c)) / np.array(r)) ** 2, axis=1)) for c, r in list(THIN) + EXTRA_THIN], axis=0)
CLOTH_T = 0.0035      # ผ้าหนา (ขอบโซนผ้าบาง)
# ระยะผ้าจากผิว (ม. รวมผ้าหนา) ที่จุดนูนสุด ; ร่องระหว่างจุดนูนผ้าคร่อมไป (ไม่เห็นกล้าม)
T_SHIRT, T_WAIST, T_SHOULDER, T_COLLAR = 0.020, 0.030, 0.0080, 0.004      # เสื้อ: อก/หลัง พองเหนือเข็มขัด บ่า (ไหล่ลาด) คอ
T_SLEEVE, T_ELBOW, T_CUFF, T_CAP = 0.015, 0.019, 0.007, 0.0100           # แขนเสื้อ ข้อศอก ปลายแขน หัวไหล่ (ไม่พอง)
T_SEAT, T_KNEE, T_SHIN, T_BLOUSE = 0.020, 0.028, 0.028, 0.036             # กางเกง: ก้น/ต้นขา เข่า แข้ง พองเหนือรองเท้า
T_BOOT, T_CINCH, T_THIN = 0.006, 0.007, 0.0035                            # รองเท้า ใต้เข็มขัด โซนผ้าบาง
ENV_IT, ENV_K = 300, 10            # รอบหาผิวผ้า ; จุดผิวใกล้สุดที่ใช้กันผ้าจม
ENV_ISO = 0.30                     # น้ำหนักขอบแนวนอน (แนวตั้งท่า I = 1): ผ้าห้อยตามแนวลำตัว/แขน/ขา
ENV_CAP = 0.040                    # ผ้าคร่อมร่องได้สูงกว่าระยะเป้าไม่เกินนี้ (ผ้าห้อยตรงจากอก/ก้น)
W_SMOOTH = 8                       # รอบเกลี่ยน้ำหนักผ้าหลวม
SOLE_X = 0.0050       # พื้นรองเท้ายื่นพ้นหนังรองเท้า
FLOOR = -0.0008       # ใต้พื้นรองเท้า
POUCH_TH = (70.0, 125.0)             # มุมกระเป๋าจากด้านหน้า (องศา ฝั่งซ้าย ; ขวาสะท้อน)
RING = {"hi": 64, "mid": 48, "lo": 32, "min": 20}
CORNER = {"hi": 3, "mid": 2, "lo": 1, "min": 1}
TRIS_SLACK = {"hi": 260, "mid": 180, "lo": 110, "min": 60}


def _ss(x):
    x = np.clip(x, 0, 1)
    return x * x * (3 - 2 * x)


# ---------------- สนามในท่า I ----------------

class Fields:
    """จุดในกรอบผูก -> พิกัดท่า I (x >= 0) + น้ำหนักแขน/ขา จากน้ำหนักผิวปั้นฝั่งซ้าย (ซ้าย-ขวาได้ค่าเดียวกันพอดี)"""

    def __init__(self, ctx):
        Vs, W = ctx["Vs"], ctx["Wh4"]
        L = Vs[:, 0] >= 0
        self.VL, self.WL = Vs[L], W[L]
        self.tree = cKDTree(self.VL)
        self.M = np.stack([rig.bone_xform(ctx["Gb"], b) for b in rig.BONES])
        self.arm = np.array([b.startswith(PT.ARM) and b.endswith("L") for b in rig.BONES])
        self.leg = np.array([b.startswith(PT.LEG) and b.endswith("L") for b in rig.BONES])

    def __call__(self, P, mats=False):
        Q = np.array(P, float)
        Q[:, 0] = np.abs(Q[:, 0])
        d, i = self.tree.query(Q, k=4)
        w = 1.0 / np.maximum(d, 1e-5) ** 2
        w /= w.sum(1, keepdims=True)
        W = np.einsum('nk,nkb->nb', w, self.WL[i])
        Mv = np.einsum('nb,bij->nij', W, self.M)
        PI = np.linalg.solve(Mv[:, :3, :3], (Q - Mv[:, :3, 3])[..., None])[..., 0]
        if mats:                                       # + เมทริกซ์ท่า I -> ท่าผูก (ของจุดฝั่งซ้าย)
            return PI, W[:, self.arm].sum(1), W[:, self.leg].sum(1), Mv[:, :3, :3]
        return PI, W[:, self.arm].sum(1), W[:, self.leg].sum(1)


def collar_y(x, z):
    """แนวคอเสื้อ (ท่า I): หลังคอ 1.535 ข้างคอ 1.525 ด้านหน้าเปิดเป็นรูปตัววีลงถึง 1.415"""
    back = 1.525 + 0.010 * _ss(-z / 0.08)
    front = 1.415 + 1.8 * x + 3.0 * np.maximum(0.03 - z, 0.0)
    return np.minimum(back, front)


def hem_parts(F):
    PI, arm, _ = F
    s_col = collar_y(PI[:, 0], PI[:, 2]) - PI[:, 1]
    s_cuf = np.where(arm > 0.5, PI[:, 1] - Y_CUFF, 1.0)
    return s_col, s_cuf


def _grp_ta(part):
    """0 ลำตัว 2 แขน -1 อื่น ๆ (ส่วนร่าง cus.w)"""
    p = np.round(part).astype(np.int64)
    return np.select([p == 0, (p == 2) | (p == 3)], [0, 2], -1)


def _cross_ta(g, I, J):
    """ขอบข้ามลำตัว-แขน: ไม่เกลี่ยข้าม (รักแร้เปิด ไม่มีพังผืด)"""
    return ((g[I] == 0) & (g[J] == 2)) | ((g[I] == 2) & (g[J] == 0))


def adj_split(F, n, part):
    """ME.adjacency ที่ตัดขอบลำตัว-แขน: เสื้อกับแขนเสื้อเกลี่ยแยกกัน"""
    from scipy.sparse import coo_matrix, diags
    I = np.concatenate([F[:, 0], F[:, 1], F[:, 2], F[:, 1], F[:, 2], F[:, 0]])
    J = np.concatenate([F[:, 1], F[:, 2], F[:, 0], F[:, 0], F[:, 1], F[:, 2]])
    k = ~_cross_ta(_grp_ta(part), I, J)
    A = coo_matrix((np.ones(int(k.sum())), (I[k], J[k])), shape=(n, n)).tocsr()
    A.data[:] = 1.0
    return diags(1.0 / np.maximum(np.asarray(A.sum(1)).ravel(), 1)) @ A


def _thin_ramp(PI):
    """0 นอกโซนผ้าบาง -> 1 ที่ขอบสำเนาผิว (armpit_w = 0.3): ระยะผ้าค่อย ๆ ลดลงจนแนบ"""
    return _ss((armpit_w(PI) - 0.05) / 0.25)


def ease_t(F):
    """ระยะผ้าจากผิวตามบริเวณ (ม.): ลำตัว/แขน/ขาผสมตามน้ำหนัก ; ลดเข้าหาคอเสื้อ ปลายแขน ใต้เข็มขัด ขอบรองเท้า โซนผ้าบาง"""
    PI, arm, leg = F
    x, y = np.abs(PI[:, 0]), PI[:, 1]
    tor = np.clip(1.0 - arm - leg, 0.0, 1.0)
    yb, bh = y - Y_BELT, BELT_H / 2 + 0.004
    shirt = T_SHIRT + (T_WAIST - T_SHIRT) * (1 - _ss((y - 1.12) / 0.08))           # เสื้อพองเหนือเข็มขัด
    t_tor = T_CINCH + (shirt - T_CINCH) * _ss((yb - bh - 0.008) / 0.035) + (T_SEAT - T_CINCH) * _ss((-yb - bh) / 0.035)
    t_tor += (T_SHOULDER - t_tor) * _ss((y - 1.39) / 0.06) * _ss((x - 0.04) / 0.04)  # เสื้อพาดบนบ่า
    t_arm = T_SLEEVE + (T_ELBOW - T_SLEEVE) * np.exp(-((y - 1.12) / 0.05) ** 2)
    t_arm += (T_CAP - t_arm) * _ss((y - 1.38) / 0.06)                               # หัวไหล่: แขนเสื้อต่อที่ปลายไหล่
    t_arm = T_CUFF + (t_arm - T_CUFF) * _ss((y - Y_CUFF) / 0.06)
    t_leg = np.interp(y, [Y_BOOT, Y_BOOT + 0.006, Y_BOOT + 0.030, 0.32, 0.50, 0.62],
                      [T_BOOT, T_BOOT + 0.004, T_BLOUSE, T_SHIN, T_KNEE, T_SEAT])
    t_leg = np.where(x < LEG_X, np.minimum(t_leg, np.maximum(0.6 * x, T_THIN)), t_leg)   # ด้านในต้นขา: ไม่ล้ำแนวกลาง
    t = (tor * t_tor + arm * t_arm + leg * t_leg) / np.maximum(tor + arm + leg, 1e-6)
    s_col, _ = hem_parts(F)
    t = T_COLLAR + (t - T_COLLAR) * _ss(s_col / 0.06)
    t += (T_THIN - t) * _thin_ramp(PI)
    for c, r, a in BLOBS + tuple(EXTRA_BLOBS):
        t = t + a * np.exp(-np.sum(((PI - np.array(c)) / np.array(r)) ** 2, axis=1))
    return t


def hem_s(F):
    """บวก = ผ้าคลุม ; ลบ = ผิวโผล่ (หัว คอ มือ)"""
    return np.minimum(*hem_parts(F))


def boot_s(F):
    return np.where(F[2] > 0.5, Y_BOOT - F[0][:, 1], -1.0)


def sole_s(F):
    return np.where(F[2] > 0.5, Y_SOLE - F[0][:, 1], -1.0)





# ---------------- ผิวผ้า (เมชปั้นละเอียด) ----------------

def _seen(pc, ps):
    """ผ้าส่วน pc กันจมกับผิวส่วน ps: ผ้าลำตัวกับทุกส่วน ; ผ้าแขน/ขากับส่วนตัวเอง + ลำตัว (ขาไม่ชนขาอีกข้าง)"""
    return (pc == 0) | (ps == pc) | (ps == 0) | ((ps == 1) & (pc < 4))


HULL_MAX, HULL_EVERY = 0.060, 20                       # ผ้าคร่อมร่องในหน้าตัดแนวนอน (ท่า I) ได้ลึกไม่เกินนี้ ; ทุกกี่รอบ


def _slice_push(P, grp, ok, lim):
    """หน้าตัดแนวนอน (ท่า I) ต่อกลุ่ม: จุดที่อยู่ในเปลือกนูนของหน้าตัด (ร่องก้น ร่องกล้าม) เลื่อนออกถึงขอบเปลือก
    ถ้าลึกไม่เกิน lim ; คืนการเลื่อน (ท่า I)"""
    from scipy.spatial import ConvexHull
    dP = np.zeros_like(P)
    key = grp * 100000 + np.round(P[:, 1] / 0.006).astype(np.int64)
    for k in np.unique(key[ok]):
        idx = np.flatnonzero(key == k)
        if len(idx) < 8:
            continue
        Q = P[idx][:, [0, 2]]
        try:
            H = Q[ConvexHull(Q).vertices]
        except Exception:
            continue
        a, ab = H, np.roll(H, -1, 0) - H
        u = np.clip(np.einsum('nkc,kc->nk', Q[:, None, :] - a[None], ab) / np.maximum((ab ** 2).sum(1), 1e-12), 0, 1)
        C = a[None] + u[..., None] * ab[None]
        dd = np.linalg.norm(C - Q[:, None, :], axis=2)
        kk = np.argmin(dd, 1)
        dm = dd[np.arange(len(idx)), kk]
        mv = ok[idx] & (dm > 1e-4) & (dm < lim[idx])
        dP[idx[mv], 0] = C[np.arange(len(idx)), kk, 0][mv] - Q[mv, 0]
        dP[idx[mv], 2] = C[np.arange(len(idx)), kk, 1][mv] - Q[mv, 1]
    return dP


def _part_axes(PI, grp, ok):
    """แกนของลำตัว/แขน/ขา (ท่า I, ฝั่งซ้าย) ตามความสูง: จุดกลางหน้าตัดทุก 1 ซม. เกลี่ยแนวตั้ง"""
    ax = {}
    for g in (0, 2, 4):
        m = ok & (grp == g)
        ys = np.arange(PI[m, 1].min(), PI[m, 1].max() + 0.01, 0.01)
        cx = np.array([PI[m & (np.abs(PI[:, 1] - y) < 0.01), 0].mean() if (m & (np.abs(PI[:, 1] - y) < 0.01)).any() else np.nan for y in ys])
        cz = np.array([PI[m & (np.abs(PI[:, 1] - y) < 0.01), 2].mean() if (m & (np.abs(PI[:, 1] - y) < 0.01)).any() else np.nan for y in ys])
        gd = ~np.isnan(cx)
        cx, cz = np.interp(ys, ys[gd], cx[gd]), np.interp(ys, ys[gd], cz[gd])
        k = np.ones(7) / 7
        cx = np.convolve(np.pad(cx, 3, mode="edge"), k, "valid")
        cz = np.convolve(np.pad(cz, 3, mode="edge"), k, "valid")
        ax[g] = (ys, 0.0 * cx if g == 0 else cx, cz)
    return ax


def _meridian_push(P, mg, sup, ok, lim, axes, nb=36):
    """แนวตั้ง (ท่า I) ต่อกลุ่มและมุมรอบแกน: เปลือกนูนด้านบนของรัศมีตามความสูง ; จุดที่ต่ำกว่าเปลือก (เว้าระหว่างกล้าม
    ข้อพับ ใต้ก้น) เลื่อนออกตามรัศมีถึงเปลือก (ไม่เกิน lim) -> ผ้าห้อยตรงจากจุดนูน ; คืนการเลื่อน (ท่า I)"""
    dP = np.zeros_like(P)
    for g, (ys, cx, cz) in axes.items():
        m = mg == g
        if not m.any():
            continue
        dx, dz = P[:, 0] - np.interp(P[:, 1], ys, cx), P[:, 2] - np.interp(P[:, 1], ys, cz)
        r = np.hypot(dx, dz)
        tb = np.floor((np.arctan2(dx, dz) + np.pi) / (2 * np.pi) * nb).astype(np.int64) % nb
        for b_ in range(nb):
            S = np.flatnonzero(m & sup & (tb == b_))
            T = np.flatnonzero(m & ok & (tb == b_))
            if len(S) < 4 or not len(T):
                continue
            o = np.argsort(P[S, 1])
            Y, R = P[S, 1][o], r[S][o]
            hull = []
            for q in zip(Y, R):
                while len(hull) >= 2 and ((hull[-1][0] - hull[-2][0]) * (q[1] - hull[-2][1])
                                          - (hull[-1][1] - hull[-2][1]) * (q[0] - hull[-2][0])) >= 0:
                    hull.pop()
                hull.append(q)
            hy, hr = np.array(hull).T
            if len(hy) < 2:
                continue
            yt = P[T, 1]
            inside = (yt > hy[0]) & (yt < hy[-1])
            push = np.clip(np.interp(yt, hy, hr) - r[T], 0.0, lim[T]) * inside
            u = np.c_[dx[T], dz[T]] / np.maximum(r[T], 1e-9)[:, None]
            dP[T, 0] += push * u[:, 0]
            dP[T, 2] += push * u[:, 1]
    return dP


def _drape_push(P, sup, ok, lim):
    """ผ้าก้นห้อยจากจุดนูนสุดของก้น (ท่า I): ต่อแถบ |x| 1 ซม. เปลือกนูนของ (y, -z) ; จุดที่อยู่ในเปลือก (ใต้ก้น ร่องก้น)
    เลื่อนไปข้างหลังถึงเปลือก (ไม่เกิน lim) ; คืนการเลื่อน (ท่า I)"""
    dP = np.zeros_like(P)
    xb = np.floor(np.abs(P[:, 0]) / 0.01).astype(np.int64)
    for b_ in np.unique(xb[sup]):
        S, T = np.flatnonzero(sup & (xb == b_)), np.flatnonzero(ok & (xb == b_))
        if len(S) < 4 or not len(T):
            continue
        o = np.argsort(P[S, 1])
        hull = []
        for q in zip(P[S, 1][o], -P[S, 2][o]):
            while len(hull) >= 2 and ((hull[-1][0] - hull[-2][0]) * (q[1] - hull[-2][1])
                                      - (hull[-1][1] - hull[-2][1]) * (q[0] - hull[-2][0])) >= 0:
                hull.pop()
            hull.append(q)
        hy, hz = np.array(hull).T
        if len(hy) < 2:
            continue
        yt = P[T, 1]
        dP[T, 2] = -np.clip(np.interp(yt, hy, hz) + P[T, 2], 0.0, lim[T]) * ((yt > hy[0]) & (yt < hy[-1]))
    return dP


def envelope(ctx, fields, FD):
    """ผิวผ้าหลวม: ผิว hi ยกตามระยะเป้า แล้วเกลี่ยแบบผ้าคลุม (Laplacian ถ่วงแนวตั้งของท่า I = ผ้าห้อยตามลำตัว/แขน/ขา)
    ไม่ใกล้ผิวกว่าระยะเป้า (จุดผิวปั้นใกล้สุด ENV_K จุด) ไม่ลอยเกินเป้า + ENV_CAP -> ร่องกล้าม ร่องก้น ข้อพับถูกคร่อม
    คืน (การเลื่อนของจุดผิวปั้นละเอียด, ส่วนที่ผ้าคลุม)"""
    from scipy.sparse import coo_matrix, diags
    b = ctx["bare"]["hi"]
    V, F = b["V"], b["F"]
    N = b["nrm"].astype(np.float64)
    N /= np.maximum(np.linalg.norm(N, axis=1, keepdims=True), 1e-9)
    FV = fields(V)
    PI, arm, leg = FV
    cov = hem_s(FV) > 0
    t = ease_t(FV)
    boot = (leg > 0.5) & (PI[:, 1] < Y_BOOT)
    s_col, s_cuf = hem_parts(FV)
    cap = ENV_CAP * (1 - _thin_ramp(PI)) * _ss(np.minimum(s_col, s_cuf) / 0.03)
    E = np.unique(np.sort(np.vstack([F[:, [0, 1]], F[:, [1, 2]], F[:, [2, 0]]]), 1), axis=0)
    dI = PI[E[:, 1]] - PI[E[:, 0]]
    w = ENV_ISO + (1 - ENV_ISO) * dI[:, 1] ** 2 / np.maximum((dI ** 2).sum(1), 1e-12)
    w = w * (cov[E[:, 0]] & cov[E[:, 1]] & (boot[E[:, 0]] == boot[E[:, 1]]))       # รองเท้าแยกจากกางเกง
    w = w * ~_cross_ta(_grp_ta(b["cus"][:, 3]), E[:, 0], E[:, 1])                 # เสื้อกับแขนเสื้อแยกกัน (รักแร้เปิด)
    n = len(V)
    W = coo_matrix((np.r_[w, w], (np.r_[E[:, 0], E[:, 1]], np.r_[E[:, 1], E[:, 0]])), shape=(n, n)).tocsr()
    deg = np.asarray(W.sum(1)).ravel()
    A = diags(1.0 / np.maximum(deg, 1e-12)) @ W
    fi = np.flatnonzero(cov & (deg > 0))
    X = V + N * (t * cov)[:, None]
    Vs, Ns = ctx["Vs"], ctx["Ns"]
    si = np.flatnonzero(Vs[:, 1] > 0.002)              # ฝ่าเท้าไม่กันผ้า (พื้นรองเท้าเป็นสำเนาผิว)
    Vq, Nq = Vs[si], Ns[si]
    tree = cKDTree(Vq)
    ps = PT.PART_OF_BI[np.argmax(ctx["Wh4"], 1)][si]
    pc = np.round(b["cus"][fi, 3]).astype(np.int64)[:, None]
    tf, cf = t[fi], cap[fi]
    rows = np.arange(len(fi))
    # หน้าตัดนูน: ลำตัว (สะโพก-อก, x มีเครื่องหมาย) ขา แขน (ฝั่งขวาสะท้อนมาซ้าย) ; ไม่รวมบ่า เป้า รองเท้า ผิวหันบน/ล่าง
    _, _, _, M3 = fields(V, mats=True)
    sx = np.where(V[:, 0] < 0, -1.0, 1.0)
    mir = np.array([1.0, 1.0, 1.0])[None] * np.c_[sx, np.ones(n), np.ones(n)]
    nI = np.linalg.solve(M3, (N * mir)[..., None])[..., 0]
    nI /= np.maximum(np.linalg.norm(nI, axis=1, keepdims=True), 1e-9)
    pv = np.round(b["cus"][:, 3]).astype(np.int64)
    grp = np.select([pv == 0, (pv == 2) | (pv == 3), (pv == 4) | (pv == 5)], [0, 2, 4], -1)
    y = PI[:, 1]
    hok = cov & ~boot & (np.abs(nI[:, 1]) < 0.8) & (
        ((grp == 0) & (((y > 0.86) & (y < 1.40)) | ((y > 0.82) & (PI[:, 2] < -0.03))))
        | ((grp == 4) & (y > Y_BOOT + 0.04) & (y < 0.78))
        | ((grp == 2) & (y > Y_CUFF + 0.06) & (y < 1.30)))
    hlim = HULL_MAX * (1 - _thin_ramp(PI)) * _ss(np.minimum(s_col, s_cuf) / 0.03)
    # แนวตั้ง: เสื้อ (เหนือเข็มขัด) ; ขา + ก้นด้านหลัง (ผ้ากางเกงห้อยจากก้นลงต้นขา) ; แขนเสื้อ
    seat = cov & (grp == 0) & (y < Y_BELT - 0.035) & (y > 0.80) & (PI[:, 2] < -0.05) & (np.abs(PI[:, 0]) > 0.035)
    mg = np.select([(grp == 0) & (y > Y_BELT + 0.035) & (y < 1.40), seat,
                    (grp == 4) & (y > Y_BOOT + 0.04) & (y < 0.95) & ((y < 0.78) | (np.abs(PI[:, 0]) > LEG_X - 0.03)),
                    (grp == 2) & (y > Y_CUFF + 0.06) & (y < 1.38)],
                   [0, 4, 4, 2], -1)
    msup = cov & (mg >= 0)
    thx = np.abs(np.arctan2(PI[:, 0], PI[:, 2]))
    msup &= ~((grp == 0) & (y > 1.20) & (thx > 1.0) & (thx < 2.3))   # ข้างอกใต้รักแร้ไม่ห้อยจากรอยพับรักแร้ (รักแร้เปิด)
    mok = msup & ((grp != 0) | (mg == 0) | (y < 0.92))
    axes = _part_axes(PI, grp, cov)
    # ก้น: ผ้าห้อยจากก้นลงหลังต้นขา (ไม่เห็นร่องใต้ก้น)
    back = cov & (PI[:, 2] < -0.04) & (np.abs(PI[:, 0]) < 0.16)
    dsup = back & (((grp == 0) & (y < Y_BELT - 0.035)) | ((grp == 4) & (y > 0.68) & (PI[:, 2] < _leg_zc(y) - 0.02)))
    dok = dsup & (y < 0.93)

    def hull_step(X):
        dB = (X - V) * mir
        PIc = PI + np.linalg.solve(M3, dB[..., None])[..., 0]
        PIc[:, 0] *= np.where(grp == 0, sx, 1.0)          # ลำตัว: x มีเครื่องหมาย (หน้าตัดข้ามแนวกลาง)
        dP = _slice_push(PIc, grp, hok, hlim)
        dP[:, 0] *= np.where(grp == 0, sx, 1.0)
        PIc[:, 0] = np.abs(PIc[:, 0])
        dP += _meridian_push(PIc, mg, msup, mok, hlim, axes)
        dP += _drape_push(PIc + dP, dsup, dok, hlim)
        return X + np.einsum('nij,nj->ni', M3, dP) * mir

    for it in range(ENV_IT):
        if it % HULL_EVERY == HULL_EVERY - 1:
            X = hull_step(X)
        Nx = ME.vnormals(X, F)                         # เลื่อนเฉพาะตามนอร์มอลของผิวผ้าเอง (จุดไม่ไหลไปตามผิว)
        X[fi] += Nx[fi] * np.einsum('ij,ij->i', 0.5 * (A @ X - X)[fi], Nx[fi])[:, None]
        Q = X[fi]
        d, jj = tree.query(Q, k=ENV_K)
        P, Nn = Vq[jj], Nq[jj]
        sd = np.einsum('nkc,nkc->nk', Q[:, None, :] - P, Nn)
        dd = np.where(_seen(pc, ps[jj]), d, np.inf)
        viol = np.where(np.isfinite(dd), np.clip(tf[:, None] - sd, 0.0, tf[:, None]), 0.0)   # ในซอก: ดันออกตามนอร์มอลเฉลี่ย
        push = viol.max(1)
        dv = np.einsum('nk,nkc->nc', viol, Nn)
        Q = Q + dv / np.maximum(np.linalg.norm(dv, axis=1, keepdims=True), 1e-12) * push[:, None]
        kn = np.argmin(dd, 1)
        Pn = P[rows, kn]
        rn = np.linalg.norm(Q - Pn, axis=1)
        far = np.isfinite(dd[rows, kn]) & (rn > tf + cf)     # ลอยเกิน: ดึงกลับเข้าหาจุดผิวใกล้สุด
        Q[far] = Pn[far] + (Q[far] - Pn[far]) * ((tf + cf)[far] / rn[far])[:, None]
        r0 = np.linalg.norm(Q - V[fi], axis=1)
        gone = r0 > tf + cf + 0.04                           # ไม่ไหลไปไกลจากจุดผิวของตัวเอง (เป้า ซอกขา)
        Q[gone] = V[fi][gone] + (Q[gone] - V[fi][gone]) * ((tf + cf + 0.04)[gone] / r0[gone])[:, None]
        X[fi] = Q
    res = float(np.abs(0.5 * (A @ X - X)[fi]).max())
    OF.log("envelope: %d cloth verts, max step %.3f mm, lift mean %.1f max %.1f mm" % (
        len(fi), res * 1000, np.linalg.norm(X - V, axis=1)[fi].mean() * 1000, np.linalg.norm(X - V, axis=1)[fi].max() * 1000))
    covD = hem_s(FD) > 0
    out = np.zeros_like(Vs)
    ci = np.flatnonzero(cov)
    out[covD] = ME.transfer(V[ci], Vs[covD], (X - V)[ci], k=4)
    # AO ของผ้า: AO ผิวเกลี่ยกว้าง ; ผ้าที่คร่อมร่อง (ห่างผิวเกินเป้า) ไม่เห็นเงาของร่องใต้ผ้า
    Ad, ao = ME.adjacency(ctx["Fs"], len(Vs)), ctx["ao"].astype(np.float64)
    for _ in range(150):
        ao = 0.5 * ao + 0.5 * (Ad @ ao)
    ctx["_ao_c"] = ao + (1 - ao) * _ss((np.linalg.norm(out, axis=1) - ease_t(FD) - 0.004) / 0.015)
    return out, covD


def _flipped(P, F):
    """สามเหลี่ยมที่หันกลับเทียบกับนอร์มอลเฉลี่ยรอบจุดยอด (ผ้าพับทับในหลุมที่ถูกคร่อม)"""
    n = np.cross(P[F[:, 1]] - P[F[:, 0]], P[F[:, 2]] - P[F[:, 0]])
    Nv = ME.vnormals(P, F)
    return np.einsum('ij,ij->i', n, Nv[F].sum(1)) <= 0


def untangle(P, F, free, lv, P0=None, fix=None, n_it=150):
    """ผ้าคร่อมหลุม (สะดือ ร่องก้น) ทำให้จุดยอดเบียด/พับ: เกลี่ยจุดรอบสามเหลี่ยมที่พลิกตามผิว (ตัดส่วนตามนอร์มอล) จนไม่พลิก"""
    A = ME.adjacency(F, len(P))
    P = P.copy()
    n0 = int(_flipped(P, F).sum())
    E = np.vstack([F[:, [0, 1]], F[:, [1, 2]], F[:, [2, 0]]])
    def elen(X):
        le = np.linalg.norm(X[E[:, 0]] - X[E[:, 1]], axis=1)
        s_ = np.zeros(len(X))
        np.add.at(s_, E[:, 0], le)
        np.add.at(s_, E[:, 1], le)
        return s_
    e0 = elen(P0) if P0 is not None else None
    for it in range(n_it):
        bad = _flipped(P, F)
        fl = np.zeros(len(P), bool)
        fl[F[bad].ravel()] = True
        m = fl | (elen(P) < 0.45 * e0) if e0 is not None else fl.copy()   # + จุดเบียดกันในหลุมที่ถูกคร่อม
        if not m.any():
            break
        fl = ((A @ fl.astype(float) > 0) | fl) & free
        m = ((A @ m.astype(float) > 0) | m) & free
        Nv = ME.vnormals(P, F)
        L = A @ P - P
        Lt = L - Nv * np.einsum('ij,ij->i', L, Nv)[:, None]
        P[m] += 0.5 * np.where(fl[m, None], L[m], Lt[m])    # รอบรอยพับ: เกลี่ยเต็ม (รอยพับยุบ) ; จุดเบียด: เกลี่ยตามผิว
        if fix is not None:
            P = fix(P)
    n1 = int(_flipped(P, F).sum())
    if n0:
        OF.log("%s: untangle %d -> %d flipped cloth tris" % (lv, n0, n1))
    return P


# ---------------- ตัดผิวระดับเดิมตามขอบผ้า ----------------

def _vf(F, n):
    out = [[] for _ in range(n)]
    for i, f in enumerate(F):
        for v in f:
            out[v].append(i)
    return out


def locate(V0, F0, Q):
    """จุด Q (อยู่บนผิว V0/F0) -> (หน้า, พิกัดแบรีเซนทริก)"""
    vf = _vf(F0, len(V0))
    _, nn = cKDTree(V0).query(Q, k=3)
    fi, bc = np.zeros(len(Q), np.int64), np.zeros((len(Q), 3))
    for qi, q in enumerate(Q):
        best = (np.inf, 0, None)
        for f in {f for v in nn[qi] for f in vf[v]}:
            a, b, c = V0[F0[f]]
            v0, v1, v2 = b - a, c - a, q - a
            d00, d01, d11, d20, d21 = v0 @ v0, v0 @ v1, v1 @ v1, v2 @ v0, v2 @ v1
            den = d00 * d11 - d01 * d01
            if den <= 1e-30:
                continue
            l1 = (d11 * d20 - d01 * d21) / den
            l2 = (d00 * d21 - d01 * d20) / den
            l = np.array([1 - l1 - l2, l1, l2])
            out = np.clip(-l, 0, None).sum()
            p = a + l1 * v0 + l2 * v1
            err = np.linalg.norm(q - p) + out * 0.05
            if err < best[0]:
                best = (err, f, l)
        fi[qi] = best[1]
        l = np.clip(best[2], 0, None)
        bc[qi] = l / l.sum()
    return fi, bc


def dense_w(bones, weights):
    W = np.zeros((len(bones), len(rig.BONES)))
    np.put_along_axis(W, bones.astype(np.int64), weights.astype(np.float64), 1)
    return W


def cut_bare(ctx, lv, fields):
    """ผิวระดับเดิม -> ตัดตามคอเสื้อ/ปลายแขน ; คืนเมชตัดแล้ว + ค่าต่อจุด + ค่าสนาม"""
    b = ctx["bare"][lv]
    V0, F0 = b["V"], b["F"]
    s0 = hem_s(fields(V0))
    V, F, on = VR.cut_along(V0, F0, s0)
    n0 = len(V0)
    s = np.r_[s0, np.zeros(len(V) - n0)]
    s[on] = 0.0
    W0 = dense_w(b["bones"], b["weights"])
    attrs = {"nrm": b["nrm"].astype(np.float64), "col": b["col"].astype(np.float64), "cus": b["cus"].astype(np.float64),
             "W": W0}
    if "face" in b:
        attrs["face"] = b["face"].astype(np.float64)
    moved = np.r_[np.linalg.norm(V[:n0] - V0, axis=1) > 1e-12, np.ones(len(V) - n0, bool)]
    out = {k: np.r_[v, np.zeros((len(V) - n0,) + v.shape[1:])] for k, v in attrs.items()}
    mi = np.nonzero(moved)[0]
    if len(mi):
        fi, bc = locate(V0, F0, V[mi])
        tri = F0[fi]
        for k, v in attrs.items():
            val = np.einsum('nk,nk...->n...', bc, v[tri])
            if k == "cus":
                val[:, 3] = v[tri[np.arange(len(mi)), np.argmax(bc, 1)], 3]     # ส่วนร่างกาย = ของจุดที่ใกล้สุด
            out[k][mi] = val
        n = out["nrm"]
        out["nrm"] = n / np.maximum(np.linalg.norm(n, axis=1, keepdims=True), 1e-9)
    fmin, fmax = s[F].min(1), s[F].max(1)
    if np.any((fmin < 0) & (fmax > 0)):
        raise SystemExit("outfit %s: a face still crosses the hem line" % lv)
    cmask = (fmin >= 0) & (fmax > 0)
    return V, F, out, cmask


def sub(V, F, fmask):
    used = np.unique(F[fmask])
    remap = -np.ones(len(V), np.int64)
    remap[used] = np.arange(len(used))
    return used, remap[F[fmask]]


def mirror_pairs(V, tol=1e-9):
    d, j = cKDTree(V).query(V * np.array([-1.0, 1.0, 1.0]))
    return np.where(d < tol, j, -1)


# ---------------- ลดสามเหลี่ยมเมชเปิดแบบสมมาตร (จุดล็อกคงที่ทุกบิต) ----------------

def sym_hem(V, hem):
    """ผ้าสร้างจากซีกซ้ายแล้วสะท้อน: ขอบผ้าสองซีกต้องเป็นเงากันพอดี ; ร่างระดับต่ำบางร่างเหลื่อม <1 มม. ->
    จุดขอบไม่มีคู่ชิดแนวกลาง (<0.1 มม.) วางบน x = 0 ; จุดขอบซีกขวาไม่มีคู่ -> เงาของจุดซีกซ้ายไม่มีคู่ที่ใกล้ที่สุด"""
    P = V[hem]
    M = P * np.array([-1.0, 1.0, 1.0])
    d, _ = cKDTree(P).query(M)
    lone = d > 1e-9
    if not lone.any():
        return V
    V = V.copy()
    mid = lone & (np.abs(P[:, 0]) < 1e-4)
    V[hem[mid], 0] = 0.0
    L = np.flatnonzero(lone & ~mid & (P[:, 0] > 0))
    R = np.flatnonzero(lone & ~mid & (P[:, 0] < 0))
    if len(L) and len(R):
        dr, jr = cKDTree(P[R]).query(M[L])
        ok = (dr < 1e-3) & (np.bincount(jr, minlength=len(R))[jr] == 1)
        V[hem[R[jr[ok]]]] = M[L[ok]]
    OF.log("hem: %d unpaired vertices -> %d on the midline, %d mirrored" % (int(lone.sum()), int(mid.sum()), int(ok.sum()) if len(L) and len(R) else 0))
    return V


def decimate_open(V, F, target, lock, factor=50.0):
    import bldec
    c = V[F].mean(1)
    used, Fh = sub(V, F, c[:, 0] > 0)
    Vh, Lh = V[used], lock[used]
    V2, F2 = bldec.decimate(Vh, Fh, max(target // 2, 8), np.where(Lh, 0.0, 1.0), factor)
    a = np.linalg.norm(np.cross(V2[F2[:, 1]] - V2[F2[:, 0]], V2[F2[:, 2]] - V2[F2[:, 0]]), axis=1)
    F2 = ME.drop_fins(F2[a > 1e-14])
    u2, F2 = sub(V2, F2, np.ones(len(F2), bool))
    V2 = V2[u2]
    d, j = cKDTree(Vh[Lh]).query(V2)
    lk = d < 1e-6                                # Blender เก็บพิกัด float32: จุดล็อกคืนค่าเดิมทุกบิต
    if lk.sum() != Lh.sum():
        raise RuntimeError("decimation moved %d locked vertices" % (Lh.sum() - lk.sum()))
    V2[lk] = Vh[Lh][j[lk]]
    bnd = np.zeros(len(V2), bool)
    bnd[ME.boundary_verts(F2)] = True
    V2[bnd & ~lk, 0] = 0.0                       # รอยต่อกลางตัวอยู่บนระนาบ x = 0
    # จุดรอยต่อที่ทับกันพอดีหลังวางบนระนาบ -> จุดเดียว (ไม่เป็นจุดบีบ) ; สามเหลี่ยมที่แบนทิ้ง
    sv = np.flatnonzero(np.abs(V2[:, 0]) < 1e-12)
    pr = cKDTree(V2[sv]).query_pairs(1e-7, output_type="ndarray")
    if len(pr):
        rep = np.arange(len(V2))
        for a, b in sorted(map(tuple, np.sort(pr, axis=1)), reverse=True):
            rep[sv[b]] = rep[sv[a]]
        F2 = rep[F2]
        F2 = ME.drop_fins(F2[(F2[:, 0] != F2[:, 1]) & (F2[:, 1] != F2[:, 2]) & (F2[:, 2] != F2[:, 0])])
        u2, F2 = sub(V2, F2, np.ones(len(F2), bool))
        V2, lk = V2[u2], lk[u2]
    # สามเหลี่ยมที่ทั้งสามจุดอยู่บนระนาบกลาง = ครีบแบน (เงาทับตัวเองเป็นหน้าซ้ำ) -> ตัดทิ้ง
    fl = (np.abs(V2[F2][:, :, 0]) < 1e-12).all(1)
    if fl.any():
        u2, F2 = sub(V2, F2[~fl], np.ones(int((~fl).sum()), bool))
        V2, lk = V2[u2], lk[u2]
    seam = np.abs(V2[:, 0]) < 1e-12
    ns = np.nonzero(~seam)[0]
    n = len(V2)
    mi = np.arange(n)
    mi[ns] = n + np.arange(len(ns))
    Vf = np.vstack([V2, V2[ns] * np.array([-1.0, 1.0, 1.0])])
    Ff = np.vstack([F2, mi[F2][:, ::-1]])
    return Vf, Ff, np.r_[lk, lk[ns]]


# ---------------- ชิ้นอุปกรณ์ ----------------

def rrect(a, b, r, npc):
    """สี่เหลี่ยมมุมมน ครึ่งกว้าง a ครึ่งสูง b รัศมี r (ทวนเข็ม)"""
    pts = []
    for cx, cy, a0 in ((a - r, b - r, 0.0), (-(a - r), b - r, 90.0), (-(a - r), -(b - r), 180.0), (a - r, -(b - r), 270.0)):
        for k in range(npc):
            t = np.radians(a0 + 90.0 * (k + 0.5) / npc)
            pts.append((cx + r * np.cos(t), cy + r * np.sin(t)))
    return np.array(pts)


def prism(o, u, v, w, size, w0, w1, chamfer, npc):
    """แท่งมุมมนปิด: หน้าตัดในระนาบ (u, v) ยื่นตาม w จาก w0 ถึง w1 ; ขอบหน้าลบมุม chamfer"""
    a, b = size
    r = min(a, b) * 0.30
    P0 = rrect(a, b, r, npc)
    rings = [(P0, w0)]
    if chamfer > 0:
        rings += [(P0, w1 - chamfer), (rrect(a - chamfer, b - chamfer, max(r - chamfer, 0.3 * r), npc), w1)]
    else:
        rings += [(P0, w1)]
    m = len(P0)
    V = [o + p[0] * u + p[1] * v + ww * w for P, ww in rings for p in P]
    V += [o + w0 * w, o + rings[-1][1] * w]
    V = np.array(V)
    F = []
    nr = len(rings)
    for k in range(nr - 1):
        for i in range(m):
            j = (i + 1) % m
            a0, a1, b0, b1 = k * m + i, k * m + j, (k + 1) * m + i, (k + 1) * m + j
            F += [(a0, a1, b1), (a0, b1, b0)]
    cb, cf = nr * m, nr * m + 1
    for i in range(m):
        j = (i + 1) % m
        F.append((cb, j, i))
        F.append((cf, (nr - 1) * m + i, (nr - 1) * m + j))
    F = np.array(F, np.int64)
    return _outward(V, F)


def _outward(V, F):
    vol = np.einsum('ij,ij->i', V[F[:, 0]], np.cross(V[F[:, 1]], V[F[:, 2]])).sum()
    return V, (F if vol > 0 else F[:, ::-1].copy())


def _frame(th):
    t = np.radians(th)
    w = np.array([np.sin(t), 0.0, np.cos(t)])          # ออกจากลำตัว
    u = np.array([np.cos(t), 0.0, -np.sin(t)])         # ตามเส้นรอบเอว
    return u, np.array([0.0, 1.0, 0.0]), w


def gear(ctx, lv, D, FD, src_w):
    """เข็มขัด (ห่วง) หัวเข็มขัด กระเป๋า 4 ใบ: ตำแหน่งจากผิวผ้าละเอียด D ; น้ำหนักต่อจุดจากผ้าที่อยู่ใต้"""
    PI, arm, _ = FD
    yb = Y_BELT - 0.005                                 # ท่าผูก = ท่า I - 5 มม. ที่ลำตัว
    band = (np.abs(PI[:, 1] - Y_BELT) < BELT_H / 2 + 0.006) & (arm < 0.3)
    P = D[band]
    zc = 0.5 * (P[:, 2].max() + P[:, 2].min())
    c = np.array([0.0, yb, zc])
    nb = 180
    th = np.degrees(np.arctan2(np.abs(P[:, 0]), P[:, 2] - zc))
    rr = np.hypot(P[:, 0], P[:, 2] - zc)
    rb = np.zeros(nb + 1)
    np.maximum.at(rb, np.clip((th / 180.0 * nb).astype(int), 0, nb), rr)
    rb = np.maximum.reduce([rb, np.r_[rb[1:], rb[-1]], np.r_[rb[0], rb[:-1]]])
    rfun = lambda t: np.interp(np.abs((np.asarray(t) + 180.0) % 360.0 - 180.0) / 180.0 * nb, np.arange(nb + 1), rb) + 0.002
    N = RING[lv]
    tk = (np.arange(N) + 0.5) * 360.0 / N
    tk = np.where(tk > 180, tk - 360, tk)
    if lv in ("hi", "mid"):
        ch = 0.0012
        prof = [(0, -BELT_H / 2), (BELT_T - ch, -BELT_H / 2), (BELT_T, -BELT_H / 2 + ch), (BELT_T, BELT_H / 2 - ch),
                (BELT_T - ch, BELT_H / 2), (0, BELT_H / 2)]
    else:
        prof = [(0, -BELT_H / 2), (BELT_T, -BELT_H / 2), (BELT_T, BELT_H / 2), (0, BELT_H / 2)]
    m = len(prof)
    Vb = []
    for t in tk:
        u, v, w = _frame(t)
        r0 = rfun(t)
        for dr, dy in prof:
            Vb.append(c + w * (r0 + dr) + v * dy)
    Vb = np.array(Vb)
    Fb = []
    for k in range(N):
        k2 = (k + 1) % N
        for i in range(m):
            j = (i + 1) % m
            Fb += [(k * m + i, k * m + j, k2 * m + j), (k * m + i, k2 * m + j, k2 * m + i)]
    Vb, Fb = _outward(Vb, np.array(Fb, np.int64))
    # น้ำหนักชิ้นอุปกรณ์ต่อจุด = ของผ้าที่อยู่ใต้ (ขยับไปกับผ้า ไม่จมในผ้าตอนงอสะโพก)
    pieces = [("belt", Vb, Fb, ME.transfer(D, Vb, src_w, k=6), "webbing")]
    npc = CORNER[lv]
    ch = 0.0015 if lv in ("hi", "mid") else 0.0
    rout = rfun(0.0) + BELT_T
    u, v, w = _frame(0.0)
    V, F = prism(c, u, v, w, (0.028, 0.024), rout - 0.001, rout + 0.006, ch * 0.8, npc)
    pieces.append(("buckle", V, F, ME.transfer(D, V, src_w, k=6), "hardware"))
    for t0 in POUCH_TH:
        for sd in (1.0, -1.0):
            t = t0 * sd
            u, v, w = _frame(t)
            top = yb + BELT_H / 2 + 0.005
            hh, hw, dep = 0.035, 0.0375, 0.030
            o = np.array([0.0, top - hh, zc])
            # หลังกระเป๋าพ้นผ้าใต้เข็มขัด (สะโพก) ทุกจุดในรอยกระเป๋า + 1 มม.
            q = D - o
            inside = (np.abs(q @ u) < hw + 0.004) & (np.abs(q @ v) < hh + 0.004) & (q @ w > 0) & (arm < 0.3)
            rback = max(rfun(t) + BELT_T, float((q[inside] @ w).max()) + 0.0025 if inside.any() else 0.0)
            V, F = prism(o, u, v, w, (hw, hh), rback, rback + dep, ch, npc)
            pieces.append(("pouch", V, F, ME.transfer(D, V, src_w, k=6), "webbing"))
            if lv != "min":
                fo = o + v * (hh - 0.013)
                V, F = prism(fo, u, v, w, (hw + 0.002, 0.016), rback + 0.002, rback + dep + 0.003, ch, npc)
                pieces.append(("flap", V, F, ME.transfer(D, V, src_w, k=6), "webbing"))
    return pieces


def cut_half(V, F, lk, sfs, d):
    """เส้นตัด + แถวขอบ (VR.cut_along, band_rows) ทำบนครึ่งซ้ายแล้วสะท้อนแบบ decimate_open: เศษทศนิยมไม่ทำให้
    สองฝั่งตัดต่างกัน ; คืน (V, F, lk) ของทั้งตัว"""
    xl = V[F, 0]
    u, Fl = sub(V, F, (xl > -1e-12).all(1) & ((xl > 1e-12).any(1) | (np.abs(xl) < 1e-12).all(1)))
    Vl, lkl = V[u], lk[u]
    for sf in sfs:
        V_ = Vl.copy()
        Vl, Fl, on = VR.cut_along(Vl, Fl, sf(Vl))
        Vl = VR.band_rows(Vl, Fl, sf, on, d)
        Vl[:len(V_)][lkl] = V_[lkl]                  # จุดล็อกไม่ถูกดึงลงเส้นตัด
        lkl = np.r_[lkl, np.zeros(len(Vl) - len(lkl), bool)]
    seam = np.abs(Vl[:, 0]) < 1e-12
    Vl[seam, 0] = 0.0
    ns = np.flatnonzero(~seam)
    n = len(Vl)
    mi = np.arange(n)
    mi[ns] = n + np.arange(len(ns))
    Fm = Fl[~seam[Fl].all(1)]
    return np.vstack([Vl, Vl[ns] * np.array([-1.0, 1.0, 1.0])]), np.vstack([Fl, mi[Fm][:, ::-1]]), np.r_[lkl, lkl[ns]]


TAUBIN = {"hi": 24, "mid": 16, "lo": 9, "min": 5}     # รอบเกลี่ยตำแหน่งผิวผ้า ~ 6 ซม. ตามขนาดสามเหลี่ยมของระดับ


def drape(P, F, nD, FV, free, lv, A=None):
    """เกลี่ยตำแหน่งผิวผ้าแบบ Taubin (ไม่หด) บนลำตัว ก้น ขา แขน: กล้าม/ร่องที่เหลือกลายเป็นผ้าเรียบ ; ไม่เกลี่ยแถบเข็มขัด
    ขอบรองเท้า คอเสื้อ ปลายแขน โซนผ้าบาง ; ยุบเข้าจากผิวผ้าละเอียดได้ไม่เกิน 0.4 ของระยะเป้า (ตามนอร์มอลของผิวผ้าละเอียด)"""
    PI = FV[0]
    y = PI[:, 1]
    s_col, s_cuf = hem_parts(FV)
    w = (_ss((np.abs(y - Y_BELT) - 0.045) / 0.02) * _ss((y - Y_BOOT - 0.07) / 0.03)
         * _ss((np.minimum(s_col, s_cuf) - 0.03) / 0.03) * (1 - _thin_ramp(PI)) * free)
    lim = 0.4 * ease_t(FV)
    A = ME.adjacency(F, len(P)) if A is None else A
    P0, P = P, P.copy()
    for _ in range(TAUBIN[lv]):
        for lam in (0.5, -0.53):
            P += lam * w[:, None] * (A @ P - P)
        h = np.einsum('ij,ij->i', P - P0, nD)
        P += nD * (np.maximum(-lim - h, 0.0) * free)[:, None]
    return P


def settle_belt(Vb, V, F, n_seg, margin=0.0005, n_it=8):
    """เข็มขัดวางบนผ้าจริงของระดับ: ครึ่งบน/ล่างของแต่ละช่วงเลื่อนออกตามรัศมีจนพ้นผ้า >= margin
    (เสื้อพองเหนือเข็มขัด ก้นใต้เข็มขัด) -> เข็มขัดบานตามเอว ไม่จมในผ้า ; ซ้าย/ขวาเท่ากัน"""
    from inner_layers import SkinDepth
    sdf = SkinDepth(V, OF.weld(V, F))
    Vb = Vb.copy()
    zc = 0.5 * (Vb[:, 2].max() + Vb[:, 2].min())
    w = np.c_[Vb[:, 0], np.zeros(len(Vb)), Vb[:, 2] - zc]
    w /= np.maximum(np.linalg.norm(w, axis=1, keepdims=True), 1e-12)
    top = (Vb[:, 1] > Y_BELT - 0.005).reshape(n_seg, -1)
    for _ in range(n_it):
        need = np.maximum(margin - sdf.query(Vb)[0], 0.0).reshape(n_seg, -1)
        if need.max() < 1e-5:
            break
        st, sb = np.where(top, need, 0.0).max(1), np.where(top, 0.0, need).max(1)
        st, sb = np.maximum(st, st[::-1]), np.maximum(sb, sb[::-1])       # ช่วง k กับ N-1-k เป็นเงากัน
        st = np.maximum.reduce([st, np.roll(st, 1), np.roll(st, -1)])
        sb = np.maximum.reduce([sb, np.roll(sb, 1), np.roll(sb, -1)])
        Vb += w * np.where(top, st[:, None], sb[:, None]).reshape(-1, 1)
    return Vb


WMODE = "mix"


def cloth_weights(ctx, D, P, F, src_w):
    """น้ำหนักของผ้า: รองเท้าจากผิวที่อยู่ใต้ตรง ๆ (พื้นรองเท้างอตามนิ้วเท้า) ; ที่อื่นจากผิวผ้าละเอียด D (= ผิวใต้ผ้า)"""
    if WMODE == "D":
        return ME.transfer(D, P, src_w, k=3)
    if WMODE == "S":
        return ME.transfer(ctx["Vs"], P, src_w, k=3)
    boot = (F[2] > 0.5) & (F[0][:, 1] < Y_BOOT + 0.02)
    W = ME.transfer(D, P, src_w, k=3)
    inner = (F[2] > 0.5) & (np.abs(P[:, 0]) < 0.05)        # ต้นขาด้านในชิดกัน: น้ำหนักจากขาข้างเดียวกันเท่านั้น
    pd = PT.PART_OF_BI[np.argmax(src_w, 1)]
    for sd in (1.0, -1.0):
        # ผิวผ้าของต้นขาใหญ่ล้ำแนวกลางได้: แยกขาตามส่วนร่างของจุดต้นทาง ไม่ใช่ตามฝั่ง x
        lg = np.isin(pd, (4, 5)) & (ctx["Vs"][:, 0] * sd > 0)
        mine = np.bincount(pd[lg]).argmax() if lg.any() else -1
        q, dm = inner & (P[:, 0] * sd > 0), ((D[:, 0] * sd > 0) | (pd == mine)) & ~(np.isin(pd, (4, 5)) & (pd != mine))
        if q.any():
            W[q] = ME.transfer(D[dm], P[q], src_w[dm], k=3)
    if boot.any():
        W[boot] = ME.transfer(ctx["Vs"], P[boot], src_w, k=3)
    return W


# ---------------- รายละเอียด: เส้นตัดขอบคม รอยพับนุ่ม สีผ้า ----------------

LEG_X = 0.093                                          # แกนขา (ท่า I |x|)
POCKET = (0.050, 0.130, 1.245, 1.355, 1.318)           # กระเป๋าอก: x0 x1 y0 y1 ขอบล่างฝา
CARGO = (0.505, 0.665, 0.052, -0.008, 0.623)           # กระเป๋าข้างขา: y0 y1 ครึ่งกว้าง กลาง z ขอบล่างฝา
E_COLLAR, E_CUFF, E_RIM = 0.005, 0.004, 0.002          # ปกพับ ข้อมือพับ ขอบบนรองเท้า (ม. ยกจากผ้า)
E_POCKET, E_FLAP, E_CARGO, E_CFLAP = 0.006, 0.0085, 0.010, 0.013


def _leg_zc(y):
    """กลางขา (ท่า I z) ตามความสูง"""
    return np.interp(y, [0.20, 0.30, 0.40, 0.50, 0.60, 0.70, 0.80], [-0.021, -0.033, -0.035, -0.013, -0.008, -0.001, 0.005])


def collar_s(F):
    """ปกเสื้อพับ: บวก = ในแถบปกใต้แนวคอ (หลัง 3.4 ซม. หน้ากว้างขึ้นเป็นปลายปก) และไม่เกินรัศมีรอบคอ (ไม่ลามบนบ่า)"""
    s_col, _ = hem_parts(F)
    PI = F[0]
    z = PI[:, 2]
    rho = np.hypot(PI[:, 0], z + 0.01)
    return np.minimum(0.034 + 0.018 * _ss(z / 0.06) - s_col, 0.100 + 0.060 * _ss(z / 0.08) - rho)


def cuff_s(F):
    """ข้อมือเสื้อพับ: บวก = แถบ 3.5 ซม. เหนือปลายแขน"""
    return np.where(F[1] > 0.5, Y_CUFF + 0.035 - F[0][:, 1], -1.0)


def _rect(u, v, u0, u1, v0, v1):
    return np.minimum(np.minimum(u - u0, u1 - u), np.minimum(v - v0, v1 - v))


def pocket_s(F):
    """กระเป๋าอก: (ตัวกระเป๋า, ฝา) บวก = ข้างใน ; ฝา = ส่วนบนของกระเป๋า (เส้นขอบล่างฝาอยู่ในกระเป๋าเท่านั้น)"""
    PI = F[0]
    x, y, z = np.abs(PI[:, 0]), PI[:, 1], PI[:, 2]
    sp = np.minimum(_rect(x, y, *POCKET[:4]), z - 0.06)
    return sp, np.maximum(y - POCKET[4], -sp)


def cargo_s(F):
    """กระเป๋าข้างต้นขา (ด้านนอก): (ตัวกระเป๋า, ฝา)"""
    PI, _, leg = F
    x, y, z = np.abs(PI[:, 0]), PI[:, 1], PI[:, 2]
    sc = np.minimum(np.minimum(y - CARGO[0], CARGO[1] - y), np.minimum(CARGO[2] - np.abs(z - CARGO[3]), x - LEG_X - 0.045))
    sc = np.where(leg > 0.5, sc, -1.0)
    return sc, np.maximum(y - CARGO[4], -sc)


def cut_fields(lv):
    """เส้นตัด (จุดยอดบนเส้น + แถว ±d): ขอบรองเท้า พื้นรองเท้า ; hi/mid/lo + ปก ข้อมือ กระเป๋าอก/ฝา กระเป๋าขา/ฝา"""
    fs = [boot_s, sole_s]
    if lv != "min":
        fs += [collar_s, cuff_s, lambda F: pocket_s(F)[0], lambda F: pocket_s(F)[1],
               lambda F: cargo_s(F)[0], lambda F: cargo_s(F)[1]]
    return fs


def soft(F, lv):
    """รอยนุ่ม (ม. ตามนอร์มอล) ใส่ก่อนลดสามเหลี่ยม: จีบเหนือเข็มขัด สาบเสื้อ ; hi/mid: รอยย่นเหนือรองเท้า ข้อพับเข่า/ศอก"""
    PI, arm, leg = F
    x, y, z = np.abs(PI[:, 0]), PI[:, 1], PI[:, 2]
    tor = (arm < 0.3) & (leg < 0.6)
    th = np.arctan2(x, z)
    t = (y - (Y_BELT + BELT_H / 2 + 0.004)) / 0.06
    e = 0.004 * tor * (t > 0) * (t < 1) * np.sin(np.pi * np.clip(t, 0, 1)) * np.cos(6 * th)
    e += 0.0015 * tor * np.exp(-(x / 0.012) ** 2) * _ss((z - 0.05) / 0.02) * _ss((y - Y_BELT - 0.04) / 0.01) * _ss((1.41 - y) / 0.01)
    if lv in ("hi", "mid"):
        lg = leg > 0.5
        thl = np.arctan2(x - LEG_X, z - _leg_zc(y))
        yb = y - Y_BOOT
        ring = sum(a * np.exp(-((yb - h) / 0.008) ** 2) for h, a in ((0.020, 0.0045), (0.044, 0.0035), (0.068, 0.0025)))
        e += lg * (yb > 0.006) * ring * (0.75 + 0.25 * np.cos(5 * thl))
        back = _ss((np.abs(thl) - 1.9) / 0.4)
        e += lg * back * sum(0.002 * np.exp(-((y - h) / 0.007) ** 2) for h in (0.485, 0.522))
        e += lg * (1 - back) * _ss((1.2 - np.abs(thl)) / 0.3) * 0.0015 * np.exp(-((y - 0.455) / 0.008) ** 2)
        e += (arm > 0.5) * _ss(z / 0.02) * sum(0.0018 * np.exp(-((y - h) / 0.007) ** 2) for h in (1.105, 1.140))
    return e


def extra(F, d, lv):
    """ขั้นคมบนแถวที่ตัด (±d): ปกพับ ข้อมือพับ กระเป๋า+ฝา ขอบบนรองเท้า ; คืน (ยกตามนอร์มอล, พื้นรองเท้ายื่นแนวนอน)"""
    PI, arm, leg = F
    r = lambda sv: np.clip(0.5 + sv / (2 * d), 0, 1)
    e = np.zeros(len(PI))
    if lv != "min":
        e += E_COLLAR * r(collar_s(F)) + E_CUFF * r(cuff_s(F))
        sp, sf = pocket_s(F)
        e += r(sp) * (E_POCKET + (E_FLAP - E_POCKET) * r(sf))
        sc, scf = cargo_s(F)
        e += r(sc) * (E_CARGO + (E_CFLAP - E_CARGO) * r(scf))
    sb = boot_s(F)
    e += E_RIM * r(sb) * _ss((0.012 - sb) / 0.004) * (leg > 0.5)
    rs = np.clip(0.5 + sole_s(F) / (2 * d), 0, 1) * (leg > 0.5)
    return e, SOLE_X * rs


def paint(F, reg, ao, pal, lv):
    """สีผ้า: จานสีตามเขต × AO (เกลี่ยกว้าง) × ตะเข็บ/ฝากระเป๋า/สาบ/รอยพับ (hi/mid รอยพับเป็นรูปทรงแล้ว สีเบาลง)"""
    PI, arm, leg = F
    x, y, z = np.abs(PI[:, 0]), PI[:, 1], PI[:, 2]
    names = {v: k for k, v in OF.REG.items()}
    col = np.array([pal.get(names[int(r)], (0.5, 0.5, 0.5)) for r in reg], float)
    k = np.ones(len(x))
    tor = (arm < 0.3) & (leg < 0.6)
    lg = leg > 0.5
    geo = 0.45 if lv in ("hi", "mid") else 1.0
    thl = np.arctan2(x - LEG_X, z - _leg_zc(y))
    th = np.arctan2(x, z)
    k *= 1 - 0.16 * geo * (arm > 0.5) * np.exp(-((y - 1.123) / 0.035) ** 2) * _ss(z / 0.03)            # ข้อพับแขน
    k *= 1 - 0.16 * geo * lg * np.exp(-((y - 0.505) / 0.035) ** 2) * _ss((np.abs(thl) - 1.9) / 0.4)    # ข้อพับเข่า
    k *= 1 - 0.08 * np.exp(-((y - 0.86) / 0.05) ** 2) * np.exp(-(x / 0.05) ** 2)                      # เป้า
    k *= 1 - 0.12 * np.exp(-((arm - 0.5) / 0.12) ** 2) * (y > 1.25)                                     # ตะเข็บแขนเสื้อ
    t = (y - (Y_BELT + BELT_H / 2 + 0.004)) / 0.06
    k *= 1 - 0.10 * tor * (t > 0) * (t < 1) * np.sin(np.pi * np.clip(t, 0, 1)) * (0.5 - 0.5 * np.cos(6 * th))
    yb = y - Y_BOOT
    ring = sum(np.exp(-((yb - h) / 0.006) ** 2) for h in (0.032, 0.056))                             # ร่องระหว่างรอยย่น
    k *= 1 - 0.14 * geo * lg * (yb > 0.006) * np.clip(ring, 0, 1)
    sp, sf = pocket_s(F)
    ip, fl = _ss(sp / 0.002), _ss(sp / 0.002) * _ss(sf / 0.002)
    k *= (1 - 0.04 * ip - 0.07 * fl) * (1 - 0.16 * np.exp(-(sp / 0.003) ** 2) * (z > 0.06)) * (1 - 0.18 * ip * np.exp(-(sf / 0.003) ** 2))
    sc, scf = cargo_s(F)
    ic, cf = _ss(sc / 0.002), _ss(sc / 0.002) * _ss(scf / 0.002)
    k *= (1 - 0.04 * ic - 0.07 * cf) * (1 - 0.16 * np.exp(-(sc / 0.003) ** 2) * lg) * (1 - 0.18 * ic * np.exp(-(scf / 0.003) ** 2))
    k *= 1 - 0.18 * np.exp(-((collar_s(F) + 0.004) / 0.004) ** 2)                                     # เงาใต้ขอบปก
    k *= 1 - 0.12 * (arm > 0.5) * np.exp(-((y - Y_CUFF - 0.035 - 0.003) / 0.004) ** 2)                 # เงาเหนือข้อมือพับ
    k *= 1 - 0.12 * tor * np.exp(-(x / 0.010) ** 2) * _ss((z - 0.04) / 0.02) * (y > Y_BELT + 0.03) * (y < 1.42)  # สาบกระดุม
    k *= 1 - 0.07 * tor * np.exp(-((th - 1.60) / 0.05) ** 2) * (y > Y_BELT + 0.03)                      # ตะเข็บข้างเสื้อ
    k *= 1 - 0.07 * lg * np.exp(-((thl - 1.57) / 0.05) ** 2) * (yb > 0.08)                               # ตะเข็บข้างขา
    boot = reg == OF.REG["boots"]
    k *= 1 - boot * (0.10 * _ss((z - 0.105) / 0.006) + 0.22 * np.exp(-((z - 0.105) / 0.003) ** 2) * (y < 0.08))  # หัวรองเท้า
    k *= 1 - 0.14 * boot * _ss((Y_BOOT - 0.012 - y) / -0.004)                                          # ขอบบนรองเท้า
    lace = boot * _ss((0.020 - np.abs(x - LEG_X)) / 0.004) * _ss(z / 0.02) * (y > 0.050)
    k *= 1 - lace * (0.16 + 0.14 * (0.5 + 0.5 * np.cos(2 * np.pi * y / 0.016)))                        # แถบเชือกผูก
    a = 0.55 + 0.45 * np.clip(ao, 0, 1)
    return col * (k * a)[:, None]


# ---------------- หนึ่งระดับ ----------------

def build_level(ctx, lv, name):
    fields = ctx.get("_fields")
    if fields is None:
        fields = ctx["_fields"] = Fields(ctx)
    if "_dense" not in ctx:
        FD = fields(ctx["Vs"])
        disp, cov = envelope(ctx, fields, FD)
        ctx["_dense"] = (FD, cov, ctx["Vs"] + disp)
    FD, cov, D = ctx["_dense"]
    pal = OF.PALETTE[name]
    src_w = ctx["Wm4"] if lv == "min" else ctx["Wh4"]
    d = VR.GARM_D[lv]
    V, F, at, cmask = cut_bare(ctx, lv, fields)
    eu, Fe = sub(V, F, ~cmask)
    cu, Fc0 = sub(V, F, cmask)
    hem = np.intersect1d(eu, cu)
    V = sym_hem(V, hem)
    Vc0 = V[cu]
    lockc = np.isin(cu, hem)
    # ฝ่าเท้าเรียบ + รักแร้: ผ้าเป็นสำเนาของผิวเดิม (สามเหลี่ยม น้ำหนักเดียวกัน) ห่างตามนอร์มอล -> สองชั้นขยับเหมือนกันทุกท่า
    sole = Vc0[:, 1] < 1e-4
    ga = armpit_w(fields(Vc0)[0])
    copy = sole | ((ga > 0.3) & ~lockc)
    # กลางรักแร้ผ้าบาง 0.4 มม.: LBS หมุนทิศห่างจากผิวกลับเข้าในได้ ผิวจึงโผล่ไม่เกินความห่างนี้ ; ขอบเขตกลับเป็น 3.5 มม.
    off = at["nrm"][cu] * (CLOTH_T * np.clip((0.6 - ga) / 0.3, 0.0, 1.0) + 0.0004)[:, None]
    off[sole] = (0.0, FLOOR, 0.0)
    # ยกผิวที่ผ้าคลุม (ยกเว้นขอบผ้า) ; สมมาตรพอดี: ค่าฝั่งขวา = เงาของฝั่งซ้าย
    dl = ME.transfer(ctx["Vs"][cov], Vc0, (D - ctx["Vs"])[cov], k=4)
    pr = mirror_pairs(Vc0)
    right = (Vc0[:, 0] < 0) & (pr >= 0)
    dl[right] = dl[pr[right]] * np.array([-1.0, 1.0, 1.0])
    dl[np.abs(Vc0[:, 0]) < 1e-12, 0] = 0.0
    dl[lockc | copy] = 0.0
    Ac, fr = adj_split(Fc0, len(Vc0), at["cus"][cu, 3]), ~(lockc | copy)
    dl0 = dl.copy()
    for _ in range(6):                                 # การยกเกลี่ยตามผิว: ผนังร่องที่ถูกคร่อมไม่พับทับกัน
        dl[fr] += 0.5 * (Ac @ dl - dl)[fr]
    # คืนระยะยกตามนอร์มอลของผิวผ้าละเอียด (การเกลี่ยทำให้ร่องก้น/ร่องกล้ามกลับมา) ; จุดเบียดให้ untangle เกลี่ยตามผิว
    nD = ME.transfer(ctx["Vs"][cov], Vc0, ME.vnormals(D, ctx["Fs"])[cov], k=4)
    nD /= np.maximum(np.linalg.norm(nD, axis=1, keepdims=True), 1e-9)
    dl += nD * (np.maximum(np.einsum('ij,ij->i', dl0 - dl, nD), 0.0) * fr)[:, None]
    Pc = drape(Vc0 + dl, Fc0, nD, fields(Vc0), fr, lv, Ac)
    # ร่องก้น/สะดือ: ผ้าคร่อมเข้าหาแนวกลางได้ แต่ไม่ข้าม x = 0 (สองซีกไม่พับทับกัน) ; ขวา = เงาซ้ายพอดี
    mid, lft = np.abs(Vc0[:, 0]) < 1e-12, Vc0[:, 0] > 0

    def fix(P):
        P[lft, 0] = np.maximum(P[lft, 0], 0.15 * Vc0[lft, 0])
        P[mid, 0] = 0.0
        P[right] = P[pr[right]] * np.array([-1.0, 1.0, 1.0])
        return P
    Pc = untangle(fix(Pc), Fc0, ~(lockc | copy), lv, Vc0, fix)
    # รอยนุ่มก่อนลดสามเหลี่ยม (ตัวลดเก็บรูปทรงไว้) ; ขอบผ้า/สำเนาผิวไม่ขยับ
    Pc = fix(Pc + ME.vnormals(Pc, Fc0) * (soft(fields(Pc), lv) * ~(lockc | copy))[:, None])
    e_n, s_n = len(Fe), 0
    pieces = None
    target = OF.limit(lv) - TRIS_SLACK[lv] // 2 - e_n
    for attempt in range(8):
        if pieces is None:
            pieces = gear(ctx, lv, D, FD, src_w)
        p_n = sum(len(p[2]) for p in pieces)
        tc = target - p_n - s_n
        Vc, Fc, lk = decimate_open(Pc, Fc0, int(tc), lockc | copy)
        # ขอบรองเท้า/พื้นรองเท้า: แถวจุดยอดบนเส้น + แถวข้างเส้นที่ ±d
        Vc, Fc, lk = cut_half(Vc, Fc, lk, [lambda X, cf=cf: cf(fields(X)) for cf in cut_fields(lv)], d)
        bnd = ME.boundary_verts(Fc)
        s_n = 2 * len(bnd)
        total = e_n + len(Fc) + s_n + p_n
        Fwc = OF.weld(Vc, Fc)
        Ek = np.sort(np.vstack([Fwc[:, [0, 1]], Fwc[:, [1, 2]], Fwc[:, [2, 0]]]), axis=1)
        if (np.unique(Ek, axis=0, return_counts=True)[1] > 2).any() or not lk[bnd].all():
            target -= max(int(0.007 * target), 10)          # ตัวลดสร้างขอบไม่แมนิโฟลด์/ขอบเปิดนอกขอบผ้า: ลองเป้าใหม่
            OF.log("%s: cloth not manifold after decimation -> retry with target %d" % (lv, target))
            continue
        if OF.limit(lv) - TRIS_SLACK[lv] <= total <= OF.limit(lv):
            break
        target += OF.limit(lv) - TRIS_SLACK[lv] // 2 - total
        OF.log("%s: %d tris (cloth %d) -> retry" % (lv, total, len(Fc)))
    FCc = fields(Vc)
    Nc = ME.vnormals(Vc, Fc)
    e, sp = extra(FCc, d, lv)
    hz = Nc.copy()
    hz[:, 1] = 0.0
    hz /= np.maximum(np.linalg.norm(hz, axis=1, keepdims=True), 1e-9)
    dh, _ = cKDTree(V[hem]).query(Vc)
    hk = lk & (dh < 1e-9)                            # จุดล็อกที่เป็นขอบผ้า (ที่เหลือคือฝ่าเท้า)
    sl_ = lk & ~hk
    move = ~lk
    Vc[move] += Nc[move] * e[move, None] + hz[move] * sp[move, None]
    foot = (FCc[2] > 0.5) & (FCc[0][:, 1] < 0.06)
    Vc[foot, 1] = np.maximum(Vc[foot, 1], FLOOR)
    ds, js = cKDTree(Vc0[copy]).query(Vc)
    copy_src = np.where(sl_ & (ds < 1e-9), np.nonzero(copy)[0][js], -1)
    cs = copy_src >= 0
    Vc[cs] = Vc0[copy_src[cs]] + off[copy_src[cs]]
    lk = hk
    # ขอบผ้า: จุดขอบของผ้า -> สำเนายกขึ้นเป็นขอบผ้า (นอก) + สำเนาที่ผิว (ใน, สีผ้า) ; แถบเชื่อม
    hem_pos = V[hem]
    tree = cKDTree(Vc[lk])
    dd, jj = tree.query(hem_pos)
    if dd.max() > 1e-10:
        raise SystemExit("outfit %s: hem vertices lost in decimation" % lv)
    lk_idx = np.nonzero(lk)[0][jj]                   # จุดล็อกใน Vc ของขอบแต่ละจุด
    nh = len(hem)
    hn = at["nrm"][hem]
    Fh = fields(hem_pos)
    eh, _ = extra(Fh, d, lv)
    outer = hem_pos + hn * (ease_t(Fh) + eh)[:, None]
    nc = len(Vc)
    c2o = -np.ones(nc, np.int64)
    c2o[lk_idx] = np.arange(nh)
    keep_c = np.nonzero(~lk)[0]
    cmap = -np.ones(nc, np.int64)
    ne = len(eu)
    cmap[keep_c] = ne + np.arange(len(keep_c))
    o0 = ne + len(keep_c)
    i0 = o0 + nh
    cmap[lk_idx] = o0 + np.arange(nh)
    # ขอบเปิดของผ้า (ทิศตามหน้าของผ้า) -> แถบ
    E = np.vstack([Fc[:, [0, 1]], Fc[:, [1, 2]], Fc[:, [2, 0]]])
    key = np.sort(E, 1)
    _, inv, cnt = np.unique(key, axis=0, return_inverse=True, return_counts=True)
    be = E[cnt[inv.ravel()] == 1]
    if not np.all(lk[be]):
        raise SystemExit("outfit %s: an open cloth edge is not on the hem" % lv)
    strip = []
    for a, b in be:
        ao_, bo_ = cmap[a], cmap[b]
        ai, bi_ = i0 + c2o[a], i0 + c2o[b]
        strip += [(bo_, ao_, ai), (bo_, ai, bi_)]
    # รวม: ผิวที่โผล่ + ผ้า + ขอบนอก + ขอบใน + ชิ้นอุปกรณ์
    emap = -np.ones(len(V), np.int64)
    emap[eu] = np.arange(ne)
    Fcg, Fsg = cmap[Fc], np.array(strip, np.int64)
    Fall = [emap[eu][Fe], Fcg, Fsg]
    Vall = [V[eu], Vc[keep_c], outer, hem_pos]
    nC = len(keep_c)
    info = {"skin_tris": int(len(Fe)), "cloth_tris": int(len(Fc)), "hem_tris": int(len(strip)), "hem_verts": int(nh)}
    base = sum(len(x) for x in Vall)
    Wp, cls_p, reg_p, gear_r = [], [], [], []
    Vf = Vc.copy()
    Vf[lk_idx] = outer
    pieces = [(p[0], settle_belt(p[1], Vf, Fc, RING[lv]), *p[2:]) if p[0] == "belt" else p for p in pieces]
    for nm, Vp, Fp, Wpc, kind in pieces:
        Fall.append(Fp + base)
        Vall.append(Vp)
        gear_r.append((nm, base, base + len(Vp)))
        base += len(Vp)
        Wp.append(Wpc)
        cls_p += [OF.CLS["metal" if kind == "hardware" else "webbing"]] * len(Vp)
        reg_p += [OF.REG[kind]] * len(Vp)
        info["%s_tris" % nm] = info.get("%s_tris" % nm, 0) + int(len(Fp))
    Vall = np.vstack(Vall)
    Fall = np.vstack(Fall)
    nP = len(Vall) - (ne + nC + 2 * nh)
    # ค่าต่อจุดของผ้า
    Wc = cloth_weights(ctx, D, Vc[keep_c], fields(Vc[keep_c]), src_w)
    ss_k = copy_src[keep_c]
    Wc[ss_k >= 0] = at["W"][cu][ss_k[ss_k >= 0]]            # สำเนาผิว: น้ำหนักเดียวกับผิวเดิมทุกค่า
    Wh = at["W"][hem]
    # ผ้าหลวมขยับนุ่ม: เกลี่ยน้ำหนักตามผิวผ้า (ขอบผ้า สำเนาผิว รองเท้า คงเดิม ; ผ้าแนบ < 1 ซม. ไม่เกลี่ย)
    Wv = np.zeros((nc, Wc.shape[1]))
    Wv[keep_c], Wv[lk_idx] = Wc, Wh
    bt = _ss((ease_t(FCc) - 0.010) / 0.008)
    bt[lk | (copy_src >= 0) | ((FCc[2] > 0.5) & (FCc[0][:, 1] < Y_BOOT + 0.02))] = 0.0
    Am = adj_split(Fc, nc, PT.part_ids(WT.top4(Wv)[0]))
    for _ in range(W_SMOOTH):
        Wv += 0.5 * bt[:, None] * (Am @ Wv - Wv)
    Wc = Wv[keep_c] / np.maximum(Wv[keep_c].sum(1, keepdims=True), 1e-12)
    Wall = np.vstack([at["W"][eu], Wc, Wh, Wh] + Wp)
    bi, bw = WT.top4(Wall)
    sl = slice(ne, None)
    Fall_c = fields(Vall[sl])
    reg = np.zeros(len(Vall))
    cls = np.zeros(len(Vall))
    PIa = Fall_c[0]
    rc = np.where(PIa[:, 1] > Y_BELT, OF.REG["shirt"], OF.REG["trousers"]).astype(float)
    sb, ss_ = boot_s(Fall_c), sole_s(Fall_c)
    rc = np.where(sb > 0, OF.REG["boots"], rc)
    rc = np.where(ss_ > 0, OF.REG["sole"], rc)
    cc = np.select([rc == OF.REG["boots"], rc == OF.REG["sole"]], [OF.CLS["leather"], OF.CLS["sole"]], OF.CLS["cloth"])
    ncl = nC + 2 * nh
    reg[sl] = np.r_[rc[:ncl], reg_p]
    cls[sl] = np.r_[cc[:ncl], cls_p]
    reg[ne + nC:ne + ncl] = OF.REG["shirt"]                 # ขอบผ้าเป็นของเสื้อทั้งหมด (คอ ข้อมือ)
    cls[ne + nC:ne + ncl] = OF.CLS["cloth"]
    # ผิวที่โผล่: ชนิดผิว ; ผมเป็นเขตผม (ข้อ 5 เปลี่ยนสีผมได้)
    reg[:ne] = np.where(_hair(V[eu], at["cus"][eu, 3], ctx), OF.REG["hair"], OF.REG["skin"])
    ao_c = ME.transfer(D, Vall[sl], ctx["_ao_c"], k=4)
    C = np.zeros((len(Vall), 3))
    C[:ne] = at["col"][eu, :3]
    C[sl] = paint(Fall_c, reg[sl], ao_c, pal, lv)
    part = PT.part_ids(bi)
    part[:ne] = at["cus"][eu, 3]
    part[ne + nC:ne + ncl] = np.r_[at["cus"][hem, 3], at["cus"][hem, 3]]
    flesh = np.zeros(len(Vall))
    flesh[:ne] = at["cus"][eu, 2]
    cus = np.c_[cls, reg, flesh, part]
    # นอร์มอล: ผิวเดิมคงไว้ ; ผ้า + ขอบนอกจากรูปทรงจริง (เกลี่ย 2 รอบ) ; ขอบในใช้นอร์มอลผิว ; ชิ้นอุปกรณ์ต่อชิ้น
    Nall = ME.vnormals(Vall, Fall)
    Fcs = np.vstack([Fcg, Fsg])
    A = ME.adjacency(Fcs, len(Vall))
    cm = np.zeros(len(Vall), bool)
    cm[ne:ne + nC + nh] = True
    for _ in range(2):
        Ns_ = A @ Nall
        Nall[cm] = Ns_[cm] / np.maximum(np.linalg.norm(Ns_[cm], axis=1, keepdims=True), 1e-9)
    Nall[:ne] = at["nrm"][eu]
    Nall[ne + nC + nh:ne + ncl] = hn
    m = {"V": Vall, "F": Fall, "N": Nall, "C": np.clip(C, 0, 1), "cus": cus, "bones": bi, "weights": bw, "info": info,
         "n_skin": ne, "n_cloth": ne + ncl, "gear": gear_r}
    if lv in FC.CUSTOM_LV:
        fc = np.zeros((len(Vall), 4))
        fc[:ne] = at["face"][eu]
        fc[sl] = FC.custom1(FC.head_coords(Vall[sl], ctx["Gb"]), ctx["FCF"], lv, None)
        m["face"] = fc
    info.update({"pieces": int(len(pieces)), "verts_skin": int(ne), "verts_cloth": int(ncl), "verts_gear": int(nP)})
    return m


def _hair(V, part, ctx):
    """ผมบนหัว (เขตผม): เหนือแนวไรผมของร่าง ไม่รวมหู"""
    H = ME.head_local(VR.head_unwarp(V, ctx["Gb"]) if VR.CUR is not None else V, ctx["Gb"])
    th = np.degrees(np.arctan2(np.abs(H[:, 0]), H[:, 2]))
    line = VR.CUR.get("hair", {}).get("line", VR.HL_BASE) if VR.CUR is not None else VR.HL_BASE
    above = H[:, 1] > np.interp(th, VR.TH, line)
    pm = {p.name: p for p in ctx["prims"]}
    ear = np.zeros(len(V), bool)
    for nm in ("ear_L", "ear_R"):
        if nm in pm:
            Vq = (VR.head_unwarp(V, ctx["Gb"]) if VR.CUR is not None else V).astype(np.float32)
            dd, _ = pm[nm].eval(Vq, rig.bone_xform(ctx["Gb"], pm[nm].bone))
            ear |= np.asarray(dd, float) < 0.006
    return above & ~ear & (np.round(part) == 1)
