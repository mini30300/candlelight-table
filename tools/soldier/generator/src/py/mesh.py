# เมชผิว: marching cubes -> เก็บชิ้นใหญ่สุด -> เกลี่ย (Taubin) -> ลดสามเหลี่ยมตามงบแต่ละระดับ ; นอร์มอล ; ย้ายค่าข้ามความละเอียด
import numpy as np
from skimage.measure import marching_cubes
import fast_simplification as FS
import trimesh
from scipy.sparse import coo_matrix
from scipy.sparse.csgraph import connected_components
from scipy.spatial import cKDTree
import rig

LOD_TRIS = {"hi": 23600, "mid": 15700, "lo": 8850, "min": 4920}     # งบตัวเปล่า 24k / 16k / 9k / 5k (เผื่อปืนทีหลัง)
SCULPT_TRIS = 240000
PERM_SEED = 20261117    # สลับลำดับหน้าก่อนลดสามเหลี่ยม (กำหนดแน่นอน) กันการลดเอียงตามลำดับดัชนี


def mc_mesh(g):
    V, F, _, _ = marching_cubes(g.F, 0.0, spacing=(g.h, g.h, g.h), allow_degenerate=False)
    V = V + g.lo
    return clean(V.astype(np.float64), F.astype(np.int64))


def clean(V, F):
    n = len(V)
    A = coo_matrix((np.ones(F.size), (F.ravel(), np.roll(F, 1, axis=1).ravel())), shape=(n, n))
    nc, lab = connected_components(A, directed=False)
    if nc > 1:
        cnt = np.bincount(lab[F[:, 0]], minlength=nc)
        keep = np.argmax(cnt)
        F = F[lab[F[:, 0]] == keep]
    used = np.unique(F)
    remap = -np.ones(n, np.int64)
    remap[used] = np.arange(len(used))
    V = V[used]
    F = remap[F]
    vol = np.einsum('ij,ij->i', V[F[:, 0]], np.cross(V[F[:, 1]], V[F[:, 2]])).sum() / 6
    if vol < 0:
        F = F[:, ::-1].copy()
    return V, F


def clean_all(V, F, min_faces=12):
    """เก็บทุกชิ้นที่ไม่เล็กเกินไป (กระดูกหลายชิ้นในกลุ่มเดียว) และหันหน้าออกทีละชิ้น"""
    n = len(V)
    A = coo_matrix((np.ones(F.size), (F.ravel(), np.roll(F, 1, axis=1).ravel())), shape=(n, n))
    nc, lab = connected_components(A, directed=False)
    fl = lab[F[:, 0]]
    keepF = []
    for c in range(nc):
        Fc = F[fl == c]
        if len(Fc) < min_faces:
            continue
        vol = np.einsum('ij,ij->i', V[Fc[:, 0]], np.cross(V[Fc[:, 1]], V[Fc[:, 2]])).sum()
        keepF.append(Fc if vol >= 0 else Fc[:, ::-1])
    F = np.vstack(keepF)
    used = np.unique(F)
    remap = -np.ones(n, np.int64)
    remap[used] = np.arange(len(used))
    return V[used], remap[F]


def decimate_all(V, F, tris):
    """ลดสามเหลี่ยมโดยไม่ทิ้งชิ้นเล็ก (ใช้กับกระดูก/กล้าม)"""
    if len(F) > tris:
        V2, F2 = FS.simplify(V.astype(np.float32), F.astype(np.int32), target_reduction=1.0 - tris / len(F), agg=7)
        V, F = np.asarray(V2, np.float64), np.asarray(F2, np.int64)
    a = np.linalg.norm(np.cross(V[F[:, 1]] - V[F[:, 0]], V[F[:, 2]] - V[F[:, 0]]), axis=1)
    return clean_all(V, F[a > 1e-12], 4)


def taubin(V, F, it=8):
    m = trimesh.Trimesh(V, F, process=False)
    trimesh.smoothing.filter_taubin(m, lamb=0.5, nu=0.53, iterations=it)
    return np.asarray(m.vertices, np.float64)


def decimate(V, F, tris):
    if len(F) <= tris:
        return V, F
    V2, F2 = FS.simplify(V.astype(np.float32), F.astype(np.int32), target_reduction=1.0 - tris / len(F), agg=7)
    V2 = np.asarray(V2, np.float64)
    F2 = np.asarray(F2, np.int64)
    V2, F2 = clean(V2, F2)
    # ตัดสามเหลี่ยมเสื่อม
    a = np.linalg.norm(np.cross(V2[F2[:, 1]] - V2[F2[:, 0]], V2[F2[:, 2]] - V2[F2[:, 0]]), axis=1)
    F2 = F2[a > 1e-12]
    return clean(V2, F2)


def _warp(V, spots, inverse=False):
    """ขยายบริเวณ (หน้า มือ) ชั่วคราวก่อนลดสามเหลี่ยม: ตัวลดเก็บรายละเอียดตรงนั้นมากขึ้น ; ฟังก์ชันรัศมีเพิ่มเสมอ (ย้อนกลับได้)"""
    V = V.copy()
    for c, R, k in (spots if not inverse else spots[::-1]):
        d = V - c
        r = np.linalg.norm(d, axis=1)
        if not inverse:
            s = 1 + (k - 1) * np.exp(-(r / R) ** 2)
            V = c + d * s[:, None]
        else:
            lo = np.zeros_like(r)
            hi = r.copy()
            for _ in range(40):
                mid = 0.5 * (lo + hi)
                f = mid * (1 + (k - 1) * np.exp(-(mid / R) ** 2))
                lo = np.where(f < r, mid, lo)
                hi = np.where(f < r, hi, mid)
            r0 = 0.5 * (lo + hi)
            V = c + d * (r0 / np.maximum(r, 1e-12))[:, None]
    return V


def decimate_weighted(V, F, tris, spots):
    Vw = _warp(V, spots)
    V2, F2 = decimate(Vw, F, tris)
    return _warp(V2, spots, inverse=True), F2


def vnormals(V, F):
    n = np.cross(V[F[:, 1]] - V[F[:, 0]], V[F[:, 2]] - V[F[:, 0]])
    N = np.zeros_like(V)
    for k in range(3):
        np.add.at(N, F[:, k], n)
    return N / np.maximum(np.linalg.norm(N, axis=1, keepdims=True), 1e-12)


def adjacency(F, n):
    I = np.concatenate([F[:, 0], F[:, 1], F[:, 2], F[:, 1], F[:, 2], F[:, 0]])
    J = np.concatenate([F[:, 1], F[:, 2], F[:, 0], F[:, 0], F[:, 1], F[:, 2]])
    A = coo_matrix((np.ones(len(I)), (I, J)), shape=(n, n)).tocsr()
    A.data[:] = 1.0
    deg = np.asarray(A.sum(1)).ravel()
    from scipy.sparse import diags
    return diags(1.0 / np.maximum(deg, 1)) @ A


def transfer_normals(Vs, Ns, V, Ng, k=8):
    """นอร์มอลจากผิวละเอียด เฉพาะจุดที่หันทางเดียวกัน (กันหน้า-หลังของหู/ริมฝีปากปนกัน)"""
    tree = cKDTree(Vs)
    d, idx = tree.query(V, k=k)
    cand = Ns[idx]                                       # (n,k,3)
    agree = np.clip(np.einsum('nkc,nc->nk', cand, Ng), 0, 1) ** 2
    w = agree / np.maximum(d, 1e-5) ** 2
    sw = w.sum(1, keepdims=True)
    N = np.einsum('nk,nkc->nc', w, cand)
    N = np.where(sw > 1e-9, N, Ng)
    return N / np.maximum(np.linalg.norm(N, axis=1, keepdims=True), 1e-9)


def edge_scale(V, F):
    """ความยาวขอบเฉลี่ยรอบแต่ละจุดยอด"""
    E = np.vstack([F[:, [0, 1]], F[:, [1, 2]], F[:, [2, 0]]])
    L = np.linalg.norm(V[E[:, 0]] - V[E[:, 1]], axis=1)
    s = np.bincount(E[:, 0], L, len(V)) + np.bincount(E[:, 1], L, len(V))
    c = np.bincount(E[:, 0], None, len(V)) + np.bincount(E[:, 1], None, len(V))
    return s / np.maximum(c, 1)


def transfer_smooth(Vsrc, Vdst, values, sigma, k=48, Nsrc=None, Ndst=None):
    """ค่าจากเมชละเอียดลงเมชหยาบแบบเฉลี่ยเกาส์ (sigma ต่อจุด ~ ขนาดสามเหลี่ยม) -> ลายเล็กกว่าสามเหลี่ยมจางลงแทนที่จะเป็นแฉกมืด
    Nsrc/Ndst: ใช้เฉพาะจุดที่หันทางเดียวกัน (กันหน้า-หลังของหู/ริมฝีปากปนกัน)"""
    tree = cKDTree(Vsrc)
    d, idx = tree.query(Vdst, k=k)
    s = np.maximum(np.asarray(sigma, float), 1e-4)[:, None]
    w = np.exp(-0.5 * (d / s) ** 2) + 1e-12 * (d == d.min(1, keepdims=True))
    if Nsrc is not None:
        w = w * np.clip(np.einsum('nkc,nc->nk', Nsrc[idx], Ndst), 0, 1) ** 2 + 1e-12
    w /= w.sum(1, keepdims=True)
    if values.ndim == 1:
        return (values[idx] * w).sum(1)
    return np.einsum('nk,nkc->nc', w, values[idx])


def transfer(Vsrc, Vdst, values, k=4):
    """ค่าต่อจุดยอดจากเมชละเอียดไปเมชหยาบ: เฉลี่ยถ่วงระยะผกผัน k จุดใกล้สุด"""
    tree = cKDTree(Vsrc)
    d, idx = tree.query(Vdst, k=k)
    if k == 1:
        d, idx = d[:, None], idx[:, None]
    w = 1.0 / np.maximum(d, 1e-5) ** 2
    w /= w.sum(1, keepdims=True)
    if values.ndim == 1:
        return (values[idx] * w).sum(1)
    return np.einsum('nk,nkc->nc', w, values[idx])


# ---------------- สีจุดยอด (sRGB): ผิว + สีตามบริเวณ + ทาหน้า (ปาก ตา คิ้ว ผม) จากโครงสร้างจริงของหน้า + AO จำกัด ----------------
SKIN = np.array([0.84, 0.645, 0.505])
HAIR = np.array([0.20, 0.16, 0.13])
BROW = np.array([0.30, 0.22, 0.17])
# ใหม่ 0.17 (realistic) ร่างหลักตามภาพอ้างอิง: ผิวออกน้ำผึ้ง ผมเกรียนดำ (ข้างไล่บาง) คิ้วดำ
SKIN_R = np.array([0.80, 0.625, 0.485])
HAIR_R = np.array([0.075, 0.065, 0.060])
BROW_R = np.array([0.13, 0.10, 0.08])
LIP = np.array([0.72, 0.47, 0.44])
MOUTH = np.array([0.42, 0.25, 0.23])
LASH = np.array([0.30, 0.22, 0.19])
SCLERA = np.array([0.83, 0.79, 0.73])
IRIS = np.array([0.36, 0.24, 0.16])
PUPIL = np.array([0.06, 0.05, 0.05])
EYE_FAR = np.array([0.50, 0.38, 0.31])     # ตาระยะไกล (lo/min): อัลมอนด์น้ำตาลนุ่ม ไม่มีตาขาว/ดำจัด
NAIL = np.array([0.88, 0.72, 0.66])
OLIVE = np.array([0.34, 0.37, 0.23])       # กางเกงขาสั้นฝึกสีเขียวทหาร (ชั่วคราว ก่อนมีชุดทหาร)
SHORTS_TOP = 1.015                         # ขอบเอว (ม.): ใต้สะดือ ราวปุ่มกระดูกเชิงกรานหน้า
SHORTS_HEM = 0.705                         # ขากางเกง (ม.): ใต้เป้า ~12 ซม. ราวกลางต้นขา
SHORTS_BAND = 0.035                        # แถบขอบเอวเข้มขึ้นเล็กน้อย
CAV_K = 0.018                              # ขั้น 1c: เงาในร่องตื้นของหน้าท้อง/ใต้อก ต่อความลึก 1 มม. (คูณ groove_scale ของระดับไขมัน)
NV_CAP = 5.5                               # เพดานความลึกที่ใช้คิดเงา (มม.): สะดือมืดลงไม่เกิน ~10 % (รูปทรงหลุมให้เงาเองอีกส่วน)
FAR_K, FAR_WIDE, FAR_CAP = 0.050, 2.0, 3.5  # ระดับ lo: เงาร่องกว้างขึ้น 2 เท่า (สามเหลี่ยมใหญ่ แสงต่อจุดยอด) ต่อ 1 มม. ; เพดาน 3.5 มม.
WARM = np.array([1.045, 0.965, 0.945])
COOL = np.array([0.80, 0.83, 0.92])


def sdf_ao(sampler, V, N):
    ds = np.array([0.006, 0.012, 0.024, 0.045])
    occ = np.zeros(len(V))
    for i, d in enumerate(ds):
        f = sampler(V + N * d)
        occ += np.clip((d - f) / d, 0, 1) * (0.5 ** i)
    return np.clip(1.0 - occ / 1.875, 0.0, 1.0)


def head_local(V, G):
    M = np.linalg.inv(rig.bone_xform(G, "head"))
    return V @ M[:3, :3].T + M[:3, 3]


def _ss(x):
    x = np.clip(x, 0, 1)
    return x * x * (3 - 2 * x)


def _mix(rgb, col, a):
    return rgb * (1 - a[:, None]) + np.asarray(col) * a[:, None]


def _polyline_dist(P, pts):
    best = np.full(len(P), 1e9)
    for a, b in zip(pts[:-1], pts[1:]):
        ab = b - a
        t = np.clip(((P - a) @ ab) / float(ab @ ab), 0, 1)
        best = np.minimum(best, np.linalg.norm(P - (a + t[:, None] * ab), axis=1))
    return best


def _lip_bands(pm, x, y, fade=0.0016):
    """แถบริมฝีปากแดงบน/ล่าง จากรูปท่อริมฝีปากบนระนาบหน้า (x, y ท่า I) ; คืน (บน, ล่าง, ระยะถึงเส้นปาก, จางที่มุมปาก)
    fade = ขอบไล่ (ร่างหลากหลาย 3 มม.: ไม่เป็นแฉกบนสามเหลี่ยม hi ~6 มม.)"""
    lu, ll, ml = pm["lip_upper"].p, pm["lip_lower"].p, pm["mouth_line"].p["pts"]
    xu, xl = lu["pts"][:, 0], ll["pts"][:, 0]
    yu = np.interp(x, xu, lu["pts"][:, 1])
    ru = np.interp(x, xu, lu["r"]) * lu["scale"][1]
    yl = np.interp(x, xl, ll["pts"][:, 1])
    rl = np.interp(x, xl, ll["r"]) * ll["scale"][1]
    ym = np.interp(x, ml[:, 0], ml[:, 1])
    top = yu + 0.78 * ru
    bot = yl - 0.76 * rl
    up = _ss((top - y) / fade) * _ss((y - ym + 0.0006) / 0.0006)
    lo = _ss((y - bot) / fade) * _ss((ym - y + 0.0006) / 0.0006)
    half = float(xu.max())
    corner = 1 - _ss((np.abs(x) - (half - 0.0045)) / 0.0045)
    return up * corner, lo * corner, np.abs(y - ym), corner


def colours(V, N, sampler, G, F, prims, ao=None, far=False, fat=1.0, far_abs=False, garments=True, aux=None, hair=True):
    """คืน (rgb (n,3) sRGB, flesh (n,), ao (n,)) ; flesh = ผิวเนื้อ (แสงห่อแบบผิว) ; ผม/ตาน้อยกว่า ; ao ที่คำนวณแล้วส่งเข้ามาได้
    far = สีสำหรับระดับไกล (lo/min): ไม่มีเงาเครา/AO เบ้าตา, ตาเป็นอัลมอนด์น้ำตาลนุ่ม, ใต้จมูก/ใต้คางสว่างขึ้น, ปากเป็นแถบชมพูจาง
    fat = ระดับไขมัน (เงาร่องตื้นลงตามร่อง) ; far_abs = ระดับ lo: เงาร่องหน้าท้องแบบกว้าง (แทนเงาร่องแคบ)
    garments = ร่างหลากหลาย: ทาเสื้อ/กางเกงที่นี่ (False = ทาทีหลังบนจุดยอดของแต่ละระดับ) ; aux = dict รับ aof (AO ที่คูณสี)"""
    import anatomy as AN
    import variants as VR
    PAL = VR.palette() if VR.CUR is not None else None     # ร่างหลากหลาย: สีผิว ผม ตา ปาก
    skin0, hair0, brow0 = (SKIN_R, HAIR_R, BROW_R) if VR.REAL else (SKIN, HAIR, BROW)
    n = len(V)
    if ao is None:
        ao = sdf_ao(sampler, V, N)
        if F is not None:
            A = adjacency(F, n)
            for _ in range(6):
                ao = 0.5 * ao + 0.5 * (A @ ao)
    pm = {p.name: p for p in prims}
    V32 = V.astype(np.float32)

    def dist(name, idx):
        p = pm[name]
        d, _ = p.eval(V32[idx], rig.bone_xform(G, p.bone))
        return np.asarray(d, float)

    rgb = np.tile(skin0 if PAL is None else PAL["SKIN"], (n, 1))
    flesh = np.ones(n)
    H = head_local(V, G)
    Mh = rig.bone_xform(G, "head")
    Nh = N @ Mh[:3, :3]                 # นอร์มอลในกรอบศีรษะ (ท่า I)
    x, y, z = H[:, 0], H[:, 1], H[:, 2]
    ax = np.abs(x)
    hd = np.nonzero(np.linalg.norm(H - np.array([0, 1.69, 0.0]), axis=1) < 0.17)[0]
    head_w = np.zeros(n)
    head_w[hd] = 1.0
    # ---- อุ่นขึ้น: แก้ม จมูก หู ----
    w = np.exp(-(((ax - 0.045) / 0.020) ** 2 + ((y - 1.632) / 0.020) ** 2)) * (z > 0.03) * head_w
    w += np.exp(-((x / 0.014) ** 2 + ((y - 1.630) / 0.018) ** 2)) * (z > 0.085) * head_w
    ear = np.zeros(n)
    for nm in ("ear_L", "ear_R"):
        ear[hd] = np.maximum(ear[hd], 1 - _ss((dist(nm, hd) - 0.002) / 0.006))
    w = np.clip(w + 0.8 * ear, 0, 1)
    rgb = rgb * (1 + (WARM - 1) * 0.9 * w[:, None])
    # ---- ใต้จมูก: สว่างขึ้น (แสงสะท้อน) ยกเว้นรูจมูกสองวงเล็ก ----
    nb = hd[(ax[hd] < 0.022) & (y[hd] > 1.606) & (y[hd] < 1.632) & (z[hd] > 0.090)]
    if len(nb):
        down = _ss((-Nh[nb, 1] - 0.15) / 0.5)
        rgb[nb] = rgb[nb] * (1 + (0.10 if far else 0.09) * down[:, None])
        if not far:
            nos = np.exp(-(((ax[nb] - 0.0072) / 0.0042) ** 2 + ((z[nb] - 0.1050) / 0.0040) ** 2)) * down
            rgb[nb] = _mix(rgb[nb], np.array([0.36, 0.22, 0.20]) if PAL is None else PAL["NOSTRIL"], 0.55 * nos)
    # ---- ริมฝีปาก (แถบตามรูปริมฝีปาก) + เส้นปากบาง ----
    lipm = np.zeros(n)
    mz = hd[(z[hd] > 0.070) & (ax[hd] < 0.032) & (y[hd] > 1.560) & (y[hd] < 1.612)]
    if len(mz):
        up, lo, dm, corner = _lip_bands(pm, x[mz], y[mz]) if PAL is None else _lip_bands(pm, x[mz], y[mz], fade=0.0030)
        front = _ss((Nh[mz, 2] + 0.1) / 0.4)
        lipm[mz] = np.maximum(up, lo) * front
        lip_c, mouth_c = (LIP, MOUTH) if PAL is None else (PAL["LIP"], PAL["MOUTH"])
        if far:
            rgb[mz] = _mix(rgb[mz], lip_c, (0.45 if PAL is None else 0.30) * lipm[mz])
        elif PAL is None:
            rgb[mz] = _mix(rgb[mz], lip_c, 0.66 * lipm[mz])
            mline = (1 - _ss((dm - 0.0003) / 0.0008)) * 0.55 * corner * front
            rgb[mz] = _mix(rgb[mz], mouth_c, mline)
        else:
            # ร่างหลากหลาย: ปากสีอ่อนลงตามผิว (ผิวขาวไม่เป็นวงชมพู) ; เส้นปากกว้างนุ่มจาง (ไม่เป็นรอยเย็บ)
            rgb[mz] = _mix(rgb[mz], lip_c, PAL["LIP_MIX"] * lipm[mz])
            mline = (1 - _ss((dm - 0.0010) / 0.0035)) * 0.22 * corner * front
            rgb[mz] = _mix(rgb[mz], mouth_c, mline)
    # ---- เงาเครา (โกนแล้ว) จาง ๆ : กราม คาง ; ริมฝีปากบนจางมาก เริ่มใต้ฐานจมูก 4 มม. (ระดับไกลไม่มี) ----
    bk = 0.09 if PAL is None else PAL["BEARD"]
    if not far and bk > 0:
        beard = _ss((1.602 - y) / 0.010) * _ss((y - 1.545) / 0.010) * _ss((z + 0.005) / 0.02) * head_w
        lipzone = (1 - _ss((ax - 0.018) / 0.010)) * _ss((y - 1.590) / 0.004)
        beard *= 1 - 0.6 * lipzone
        beard *= (1 - lipm) * (1 - ear)
        beard *= 1 - _ss((ax - 0.064) / 0.008) * _ss((y - 1.600) / 0.01)
        rgb = rgb * (1 - bk * beard[:, None]) + rgb * COOL * bk * beard[:, None]
    # ---- ตา ----
    ez = hd[(z[hd] > 0.06) & (ax[hd] > 0.010) & (ax[hd] < 0.054) & (np.abs(y[hd] - 1.663) < 0.018)]
    if len(ez):
        de = np.minimum.reduce([dist(k, ez) for k in ("eyeball_L", "eyeball_R", "cornea_L", "cornea_R")])
        dal = np.minimum(dist("eye_open_L", ez), dist("eye_open_R", ez))
        e_far, e_scl, e_iris, e_pup, e_lash = ((EYE_FAR, SCLERA, IRIS, PUPIL, LASH) if PAL is None else
                                               (PAL["EYE_FAR"], PAL["SCLERA"], PAL["IRIS"], PAL["PUPIL"], PAL["LASH"]))
        ce = pm["eyeball_L"].p["c"]
        c = np.where(x[ez, None] > 0, ce, ce * np.array([-1.0, 1.0, 1.0]))
        v = H[ez] - c
        if far and PAL is None:
            # อัลมอนด์นุ่มสีน้ำตาลกลาง ๆ ทั้งช่องตา (ระดับไกล)
            alm = 1 - _ss((dal + 0.0008) / 0.0035)
            rgb[ez] = _mix(rgb[ez], e_far, 0.85 * alm)
            flesh[ez] = flesh[ez] * (1 - 0.4 * alm)
        elif far:
            # ร่างหลากหลาย ระดับไกล: ตาเปิดสองโทน (ขาวหม่นทั้งช่อง + ม่านตาเข้มกลาง ~40 % + เส้นขนตาบน) ;
            #   min: อัลมอนด์ เข้มกลาง อ่อนที่หัว/หางตา (ยังอ่านว่าลืมตา)
            eo = pm["eye_open_L"].p
            q = H[ez] - np.where(x[ez, None] > 0, eo["c"], eo["c"] * np.array([-1.0, 1.0, 1.0]))
            alm = 1 - _ss((dal + 0.0006) / 0.0030)
            ir = np.clip(1.3 * np.exp(-((q[:, 0] / (0.42 * eo["hw"])) ** 2 + (q[:, 1] / 0.0060) ** 2)), 0, 1)
            light = np.tile(PAL["SCLERA"] * 0.70 + PAL["SKIN"] * 0.12, (len(ez), 1))
            dark = PAL["IRIS"] * 0.55 + PAL["PUPIL"] * 0.45
            if far_abs:
                rgb[ez] = _mix(rgb[ez], _mix(light, dark, ir), 0.92 * alm)
                lash = (dal > -0.0010) & (dal < 0.0016) & (q[:, 1] > 0.0012)
                rgb[ez[lash]] = _mix(rgb[ez[lash]], e_lash, np.full(lash.sum(), 0.55))
            else:
                rgb[ez] = _mix(rgb[ez], _mix(light * 0.65 + e_far * 0.35, dark, ir), 0.85 * alm)
            flesh[ez] = flesh[ez] * (1 - 0.4 * alm)
        else:
            # ผิวลูกตาที่มองเห็น = อยู่บนลูกตา และอยู่ในช่องตาที่เจาะ
            eye = (de < 0.0009) & (dal < 0.0004)
            cosang = v[:, 2] / np.maximum(np.linalg.norm(v, axis=1), 1e-9)
            col = np.tile(e_scl, (len(ez), 1))
            if PAL is None:
                col = _mix(col, e_iris * 0.80, _ss((cosang - np.cos(np.radians(28.5))) / 0.012))
                col = _mix(col, e_iris, _ss((cosang - np.cos(np.radians(25.0))) / 0.012))
                col = _mix(col, e_pup, _ss((cosang - np.cos(np.radians(7.5))) / 0.005))
            else:
                # ร่างหลากหลาย: ม่านตา/รูม่านตาเป็นวงกลมนุ่ม (ขอบไล่กว้าง ไม่เป็นดาวเหลี่ยม) + เงาเปลือกตาบนบนลูกตาส่วนบน
                col = _mix(col, e_iris * 0.85, _ss((cosang - np.cos(np.radians(27.0))) / 0.040 + 0.5))
                col = _mix(col, e_pup, _ss((cosang - np.cos(np.radians(8.0))) / 0.016 + 0.5))
                col = col * (1 - 0.30 * _ss((v[:, 1] - 0.0012) / 0.0040))[:, None]
            rgb[ez[eye]] = col[eye]
            flesh[ez[eye]] = 0.45
            # ขนตาบน: เส้นเข้มบาง ๆ ตามขอบเปลือกตาบน
            if PAL is None:
                lash = (~eye) & (dal > -0.0006) & (dal < 0.0012) & (de < 0.0045) & (v[:, 1] > 0.0)
                rgb[ez[lash]] = _mix(rgb[ez[lash]], e_lash, np.full(lash.sum(), 0.25))
            else:
                # ร่างหลากหลาย: เฉพาะขอบเปลือกตาบน (แถบแคบ ไม่เลอะหางตา) ; ขอบเปลือกตาล่างเข้มลง 10 %
                lash = (~eye) & (dal > -0.0004) & (dal < 0.0008) & (de < 0.0045) & (v[:, 1] > 0.0)
                rgb[ez[lash]] = _mix(rgb[ez[lash]], e_lash, np.full(lash.sum(), VR.CUR.get("lash", 0.32)))
                ledge = (~eye) & (dal > -0.0004) & (dal < 0.0030) & (de < 0.0050) & (v[:, 1] < -0.0015)
                rgb[ez[ledge]] = rgb[ez[ledge]] * 0.90
    # ---- คิ้ว (นุ่ม เรียวไปทางหางคิ้ว) ----
    eb = (((ax - 0.031) / 0.021) ** 2 + ((y - (1.6865 - 0.06 * (ax - 0.031))) / (0.0048 - 0.035 * np.clip(ax - 0.031, 0, 0.02))) ** 2)
    browm = (1 - _ss(eb)) * _ss((z - 0.072) / 0.008) * head_w
    if PAL is not None and VR.CUR.get("brow_shape") is not None:
        browm = VR.brow_mask(ax, y, z) * head_w          # ร่างหญิง: คิ้วบางโค้ง สูงขึ้นเล็กน้อย
    rgb = _mix(rgb, brow0 if PAL is None else PAL["BROW"],
               ((0.46 if not far else 0.44) * (1.25 if VR.REAL else 1.0) if PAL is None else PAL["BROW_A"]) * browm)
    flesh = flesh * (1 - 0.4 * browm)
    # ---- ผมสั้นเกรียน (ไรผมนุ่ม) ----
    if PAL is None:
        th = np.degrees(np.arctan2(ax, z))
        yh = np.interp(th, [0, 25, 45, 70, 95, 120, 150, 180], [1.738, 1.733, 1.715, 1.690, 1.672, 1.640, 1.612, 1.600])
        hair = _ss((y - yh) / 0.013) * head_w * (1 - _ss(ear * 1.5))
        # 0.17: ผมบนเข้ม ข้าง/ท้ายทอยไล่บาง (เห็นหนังศีรษะ)
        rgb = _mix(rgb, hair0, (0.50 + 0.36 * _ss((y - 1.690) / 0.050) if VR.REAL else 0.64) * hair)
        flesh = flesh * (1 - 0.65 * hair)
    elif hair:
        # ร่างหลากหลาย: ผมตามแนวไรผมของร่าง (+ ลอนหยิกเป็นแสงเงา + มวยผม) ; hair=False: ทาทีหลังที่จุดยอดของระดับ lo/min
        hc = VR.CUR["hair"]
        hair = VR.hair_mask(H, _ss(ear * 1.5)) * head_w
        if "hair_bun" in pm:
            hair = np.maximum(hair, (1 - _ss((dist("hair_bun", np.arange(n)) - 0.002) / 0.006)) * head_w)
        hcol = np.tile(PAL["HAIR"], (n, 1))
        if hc.get("curl", 0.0) > 0:
            hcol = hcol + hc.get("curl_shade", 0.035) * np.clip(VR._curl(H), -1, 1)[:, None]
        rgb = rgb * (1 - hc["cover"] * hair[:, None]) + hcol * (hc["cover"] * hair[:, None])
        flesh = flesh * (1 - 0.80 * hair)
    # ---- ใต้คาง/ใต้คิ้ว/ใต้จมูก ที่หันลง: สว่างขึ้นเล็กน้อย (แสงสะท้อนจากตัว) ; ระดับไกลมากกว่า (แสงต่อจุดยอดหยาบ) ----
    fz = (z > 0.0) & (y > 1.53) & (y < 1.70) & (head_w > 0)
    dn = _ss((-Nh[:, 1] - 0.2) / 0.6) * fz
    if PAL is None:
        rgb = rgb * (1 + (0.08 if far else 0.05) * dn[:, None])
    else:
        # ร่างหลากหลาย: แก้ม/กรามที่หันข้าง/หันลง สว่างขึ้น (แสงสะท้อน ; ไม่เป็นคราบตรงเส้นแบ่งแสงของไฟบน) + ใต้คิ้ว/เปลือกตาบน (ผิวขาว)
        side = _ss((np.maximum(-Nh[:, 1], 0.8 * np.abs(Nh[:, 0])) - 0.15) / 0.5)
        eyeb = np.exp(-(((ax - 0.032) / 0.022) ** 2 + ((y - 1.676) / 0.014) ** 2)) * (z > 0.06) * head_w
        lift = (0.08 if far else 0.05) * dn + PAL["LOWLIFT"] * VR.shade_w(H) * head_w * side + PAL["EYELIFT"] * eyeb * dn
        rgb = rgb * (1 + lift[:, None])
    # ---- ฝ่ามือ ฝ่าเท้า สีอ่อน + เล็บ ----
    for sd, sx in (("L", 1), ("R", -1)):
        M = np.linalg.inv(rig.bone_xform(G, "wrist" + sd))
        P = V @ M[:3, :3].T + M[:3, 3]
        Nl = N @ M[:3, :3].T
        palm = (P[:, 1] < 0.865) & (np.abs(P[:, 0] - sx * 0.2002) < 0.05)
        pw = palm * _ss((-sx * Nl[:, 0] - 0.1) / 0.5)
        rgb = rgb * (1 + (np.array([0.07, 0.05, 0.05]) if PAL is None else PAL["PALM"]) * pw[:, None])
        Mh2 = np.linalg.inv(rig.bone_xform(G, "hand" + sd))
        Ph = V @ Mh2[:3, :3].T + Mh2[:3, 3]
        for fn in ("index", "middle", "ring", "little"):
            mcp, lens, flex, rads, spr = AN.FINGERS[fn]
            pts, rr = AN._finger_chain(mcp, lens, flex, rads, spr)
            tip = pts[-1] * np.array([sx, 1, 1])
            d = np.linalg.norm(Ph - tip, axis=1)
            outward = (Ph[:, 0] - tip[0]) * sx > 0.002
            m = (d < 0.010) & outward
            rgb[m] = rgb[m] * 0.35 + (NAIL if PAL is None else PAL["NAIL"]) * 0.65
    sole = 1 - _ss(V[:, 1] / 0.008)
    rgb = rgb * (1 + (np.array([0.06, 0.04, 0.04]) if PAL is None else PAL["SOLE"]) * sole[:, None])
    # ---- ขั้น 1c: เงาจาง ๆ ในร่องหน้าท้อง/ใต้อก (ร่องเดียวกับชั้นไขมัน ; แสงจากบนก็ยังเห็นเส้นกลางท้องกับสะดือ) ----
    #      เหนือ y 1.22 (ใต้อก ลิ้นปี่) เงาครึ่งเดียว: ไม่เป็นรอยบากมืดใต้กระดูกอก ; lo ใช้ร่องกว้างแทน (ลายต้องใหญ่กว่าสามเหลี่ยม)
    import fatmap as FMP
    kg = FMP.groove_scale(fat)
    up = 1 - 0.5 * _ss((FMP._local(V, G, "pelvis")[:, 1] - 1.22) / 0.04)
    if far_abs:
        gd = np.minimum(FMP.grooves(V, G, wide=FAR_WIDE) * 1000.0, FAR_CAP)
        rgb = rgb * (1 - FAR_K * kg * gd * up)[:, None]
    else:
        gd = np.minimum(FMP.grooves(V, G) * 1000.0, NV_CAP)
        rgb = rgb * (1 - CAV_K * kg * gd * up)[:, None]
    # ---- กางเกงขาสั้นฝึก: ทับเชิงกรานถึงกลางต้นขา ; ขอบไล่ 16/22 มม. (กว้างกว่าสามเหลี่ยม hi ขอบจึงไม่หยักเหมือนผ้าขาด)
    #      |x| < 0.30 ไม่ทาแขน (ท่า A แขนห่างลำตัว ≥ 0.46 ม.) ; ผ้าไม่ใช้แสงห่อแบบผิว ----
    if PAL is not None:
        if garments:
            # ร่างหลากหลาย (เมชปั้น/ภาพตัวอย่าง): เสื้อกล้ามหลังไขว้ + กางเกง ขอบไล่ 16 มม. ตั้งฉากกับขอบ ;
            #   ไฟล์เกมทาที่จุดยอดของแต่ละระดับหลังตัดเมชตามขอบ (variants.paint_garments)
            mt, ms = VR.garment_masks(V, G, d=0.008)
            if mt is not None:
                rgb = _mix(rgb, np.array(VR.CUR.get("top_col", VR.OLIVE_TOP)), mt)
                flesh = flesh * (1 - 0.85 * mt)
            band = _ss((V[:, 1] - (SHORTS_TOP - SHORTS_BAND)) / 0.012)
            rgb = _mix(rgb, OLIVE * (1 - 0.14 * band[:, None]), ms)
            flesh = flesh * (1 - 0.85 * ms)
    else:
        sh = _ss((SHORTS_TOP + 0.008 - V[:, 1]) / 0.016) * _ss((V[:, 1] - SHORTS_HEM + 0.011) / 0.022) * (np.abs(V[:, 0]) < 0.30)
        band = _ss((V[:, 1] - (SHORTS_TOP - SHORTS_BAND)) / 0.003)
        rgb = _mix(rgb, OLIVE * (1 - 0.16 * band[:, None]), sh)
        flesh = flesh * (1 - 0.85 * sh)
    # ---- AO จำกัด: หน้า ≤ 15 % ตัว ≤ 14 % ; รักแร้/ใต้ก้นแทบไม่มี ; ระดับไกล: หน้าไม่มี AO (ไม่เป็นหน้ากากมืด) ----
    floor_ = 0.86 + ((1.0 if far else (0.85 if PAL is None else PAL["AO_HEAD"])) - 0.86) * head_w
    for sx in (1.0, -1.0):
        ax_w = np.exp(-np.sum(((V - np.array([sx * 0.165, 1.350, -0.005])) / np.array([0.05, 0.07, 0.06])) ** 2, axis=1))
        gl_w = np.exp(-np.sum(((V - np.array([sx * 0.075, 0.835, -0.070])) / np.array([0.07, 0.04, 0.05])) ** 2, axis=1))
        floor_ = np.maximum(floor_, 0.86 + 0.08 * np.maximum(ax_w, gl_w))
    aof = floor_ + (1 - floor_) * ao
    if aux is not None:
        aux["aof"] = aof
    rgb = rgb * aof[:, None]
    # สว่างเกินช่วง: ลดทั้งสามช่องพร้อมกัน (สีไม่เพี้ยนเป็นเขียว/เหลืองเมื่อแดงชนเพดาน)
    mx = rgb.max(1, keepdims=True)
    rgb = rgb * np.minimum(1.0, 0.96 / np.maximum(mx, 1e-6))
    return np.clip(rgb, 0, 1), flesh, ao


# ---------------- สมมาตรซ้าย-ขวา: ทำครึ่งซ้าย (x ≥ 0) แล้วสะท้อน + เชื่อมรอยต่อ x = 0 ----------------

def mc_half(g, i0):
    """marching cubes เฉพาะ x ≥ 0 (ดัชนี i0 = ระนาบ x = 0) -> เมชเปิดที่มีขอบบนระนาบ x = 0 พอดี"""
    V, F, _, _ = marching_cubes(g.F[i0:], 0.0, spacing=(g.h, g.h, g.h), allow_degenerate=False)
    V = V.astype(np.float64)
    V[:, 0] = V[:, 0]                       # x = ดัชนี × h (ระนาบแรก = 0 พอดี)
    V[:, 1] += g.lo[1]
    V[:, 2] += g.lo[2]
    F = F.astype(np.int64)
    n = len(V)
    A = coo_matrix((np.ones(F.size), (F.ravel(), np.roll(F, 1, axis=1).ravel())), shape=(n, n))
    nc, lab = connected_components(A, directed=False)
    if nc > 1:
        cnt = np.bincount(lab[F[:, 0]], minlength=nc)
        F = F[lab[F[:, 0]] == np.argmax(cnt)]
    used = np.unique(F)
    remap = -np.ones(n, np.int64)
    remap[used] = np.arange(len(used))
    V, F = V[used], remap[F]
    V[np.abs(V[:, 0]) < 1e-9, 0] = 0.0
    return V, F


def boundary_verts(F):
    E = np.sort(np.vstack([F[:, [0, 1]], F[:, [1, 2]], F[:, [2, 0]]]), axis=1)
    u, c = np.unique(E, axis=0, return_counts=True)
    return np.unique(u[c == 1])


def mirror_weld(V, F):
    """ครึ่งซ้าย (ขอบที่ x = 0) -> ทั้งตัว ; คืน (V, F, pair) pair[i] = จุดคู่สะท้อนของจุด i"""
    seam = np.zeros(len(V), bool)
    b = boundary_verts(F)
    seam[b] = True
    V = V.copy()
    V[seam, 0] = 0.0
    nonseam = np.nonzero(~seam)[0]
    n = len(V)
    mi = np.arange(n)
    mi[nonseam] = n + np.arange(len(nonseam))
    Vm = V[nonseam] * np.array([-1.0, 1.0, 1.0])
    Vf = np.vstack([V, Vm])
    Fm = mi[F][:, ::-1]
    # ทิศหน้าของครึ่งซ้าย: ชี้ออก (ตรวจด้วยปริมาตรรวมหลังเชื่อม)
    Ff = np.vstack([F, Fm])
    vol = np.einsum('ij,ij->i', Vf[Ff[:, 0]], np.cross(Vf[Ff[:, 1]], Vf[Ff[:, 2]])).sum()
    if vol < 0:
        Ff = Ff[:, ::-1].copy()
    pair = np.arange(len(Vf))
    pair[nonseam] = mi[nonseam]
    pair[mi[nonseam]] = nonseam
    return Vf, Ff, pair


def symmetrize(V, pair):
    Vm = V[pair] * np.array([-1.0, 1.0, 1.0])
    out = 0.5 * (V + Vm)
    seam = pair == np.arange(len(V))
    out[seam, 0] = 0.0
    return out


def taubin_sym(V, F, pair, it=6):
    return symmetrize(taubin(V, F, it), pair)


def half_of(V, F):
    """ครึ่งซ้ายของเมชสมมาตร (หน้าที่จุดกลางอยู่ฝั่ง x > 0)"""
    c = V[F].mean(1)
    Fh = F[c[:, 0] > 0]
    used = np.unique(Fh)
    remap = -np.ones(len(V), np.int64)
    remap[used] = np.arange(len(used))
    return V[used].copy(), remap[Fh]


def drop_fins(F):
    """ลบครีบ: หน้าซ้ำสองหน้าทับกัน (ตัวลดสามเหลี่ยมสร้างที่นิ้ว) ทั้งคู่ + หน้าที่มีจุดซ้ำ"""
    while True:
        S = np.sort(F, axis=1)
        _, inv, cnt = np.unique(S, axis=0, return_inverse=True, return_counts=True)
        rm = (cnt[inv.ravel()] > 1) | (S[:, 0] == S[:, 1]) | (S[:, 1] == S[:, 2])
        if not rm.any():
            return F
        F = F[~rm]


def decimate_sym(V, F, tris, spots, tries=8, wfun=None, factor=0.0):
    """ลดสามเหลี่ยมแบบสมมาตร ; ถ้าผลไม่เป็นผิวปิดชิ้นเดียว (ตัวลดสร้างครีบ/ขอบซ้อน) ลองใหม่ (ผลยังคงที่ทุกครั้ง)
    wfun (ฟังก์ชันจุด -> น้ำหนักการลด 0..1) + factor: ใช้ Blender ไล่ระดับความละเอียด (หน้า/มือได้สามเหลี่ยมมากกว่า)"""
    if wfun is not None and factor > 0:
        for k, fm in enumerate((1.0, 0.94, 1.06, 0.88, 1.12, 0.82, 1.2, 0.76)):
            out = _decimate_sym_blender(V, F, tris, wfun, factor * fm)
            if topology_ok(topology(out[0], out[1])):
                return out
    for k in range(tries):
        out = _decimate_sym_once(V, F, tris, spots, PERM_SEED + k)
        if topology_ok(topology(out[0], out[1])):
            return out
    return out


def _decimate_sym_once(V, F, tris, spots, seed):
    """ลดครึ่งซ้าย (ขอบ x = 0 อยู่บนระนาบเสมอ) แล้วสะท้อน -> นับสองข้างเท่ากันพอดี"""
    Vh, Fh = half_of(V, F)
    rng = np.random.default_rng(seed)
    Fh = Fh[rng.permutation(len(Fh))]
    target = tris // 2
    sp = [(c, R, k) for (c, R, k) in spots if c[0] > -0.05]
    Vw = _warp(Vh, sp)
    b = boundary_verts(Fh)
    Vw[b, 0] = 0.0
    if len(Fh) > target:
        V2, F2 = FS.simplify(Vw.astype(np.float32), Fh.astype(np.int32), target_reduction=1.0 - target / len(Fh), agg=5)
        V2 = np.asarray(V2, np.float64)
        F2 = np.asarray(F2, np.int64)
    else:
        V2, F2 = Vw, Fh
    a = np.linalg.norm(np.cross(V2[F2[:, 1]] - V2[F2[:, 0]], V2[F2[:, 2]] - V2[F2[:, 0]]), axis=1)
    F2 = drop_fins(F2[a > 1e-14])
    used = np.unique(F2)
    remap = -np.ones(len(V2), np.int64)
    remap[used] = np.arange(len(used))
    V2, F2 = V2[used], remap[F2]
    V2 = _warp(V2, sp, inverse=True)
    b = boundary_verts(F2)
    V2[b, 0] = 0.0
    V2[V2[:, 0] < 0, 0] = 0.0
    return mirror_weld(V2, F2)


def _decimate_sym_blender(V, F, tris, wfun, factor):
    """ครึ่งซ้ายด้วย Blender (ขอบ x = 0 คงอยู่บนระนาบ) แล้วสะท้อน"""
    import bldec
    Vh, Fh = half_of(V, F)
    b = boundary_verts(Fh)
    Vh[b, 0] = 0.0
    V2, F2 = bldec.decimate(Vh, Fh, tris // 2, wfun(Vh), factor)
    a = np.linalg.norm(np.cross(V2[F2[:, 1]] - V2[F2[:, 0]], V2[F2[:, 2]] - V2[F2[:, 0]]), axis=1)
    F2 = drop_fins(F2[a > 1e-14])
    used = np.unique(F2)
    remap = -np.ones(len(V2), np.int64)
    remap[used] = np.arange(len(used))
    V2, F2 = V2[used], remap[F2]
    b = boundary_verts(F2)
    V2[b, 0] = 0.0
    V2[V2[:, 0] < 0, 0] = 0.0
    return mirror_weld(V2, F2)


def seam_polyline(V, F, pair):
    """เส้นกลางตัว (x = 0) ของเมชปั้น: ส่วนเส้นระหว่างจุดบนรอยต่อ (y, z)"""
    seam = pair == np.arange(len(V))
    E = np.vstack([F[:, [0, 1]], F[:, [1, 2]], F[:, [2, 0]]])
    E = E[seam[E[:, 0]] & seam[E[:, 1]]]
    E = np.unique(np.sort(E, axis=1), axis=0)
    return V[E[:, 0]][:, 1:3], V[E[:, 1]][:, 1:3]


def project_seam(V, A, B):
    """จุดบนรอยต่อ x = 0 ของระดับรายละเอียด -> ฉายลงเส้นกลางตัวของเมชปั้น (ขยับเฉพาะ y, z) : ไม่มีรอยบากรูปตัว V"""
    V = V.copy()
    s = np.nonzero(np.abs(V[:, 0]) < 1e-9)[0]
    if len(s) == 0:
        return V
    from scipy.spatial import cKDTree
    M = 0.5 * (A + B)
    tree = cKDTree(M)
    _, cand = tree.query(V[s, 1:3], k=min(16, len(M)))
    P = V[s, 1:3][:, None, :]
    a, b = A[cand], B[cand]
    ab = b - a
    t = np.clip(np.einsum('nkc,nkc->nk', P - a, ab) / np.maximum(np.einsum('nkc,nkc->nk', ab, ab), 1e-18), 0, 1)
    q = a + t[..., None] * ab
    d = np.linalg.norm(q - P, axis=2)
    j = np.argmin(d, axis=1)
    V[s, 1:3] = q[np.arange(len(s)), j]
    return V


def flatten_region(V, F, centres, radii, it=12, lam=0.5):
    """เกลี่ยจุดในบริเวณ (ทรงรีรอบ centres) เข้าหาผิวเรียบ (umbrella) ; น้ำหนักจางที่ขอบ (ใช้กับเบ้าตาระดับต่ำสุด)"""
    w = np.zeros(len(V))
    for c, r in zip(centres, radii):
        q = np.sum(((V - np.asarray(c)) / np.asarray(r)) ** 2, axis=1)
        w = np.maximum(w, np.clip(1.0 - q, 0, 1))
    if not np.any(w > 0):
        return V
    A = adjacency(F, len(V))
    V = V.copy()
    for _ in range(it):
        V = V + (lam * w)[:, None] * (A @ V - V)
    return V


def clamp_top(V, ytop):
    """จุดยอดที่ตัวลดดันสูงเกินผิวละเอียด (กลางศีรษะ) กดลงมาเท่าผิวละเอียด -> ทุกระดับสูงเท่ากัน"""
    V = V.copy()
    V[:, 1] = np.minimum(V[:, 1], ytop)
    return V


def snap_soles(V, eps=0.0015):
    """ฝ่าเท้าอยู่ที่ y = 0: จุดต่ำกว่า 0 ยกขึ้น ; จุดที่ห่างพื้นไม่ถึง eps วางบนพื้น (เฉพาะช่วงเท้า)"""
    V = V.copy()
    low = V[:, 1] < eps
    V[low, 1] = 0.0
    return V


def topology(V, F):
    """จำนวนชิ้น ขอบเปิด ขอบ/จุดไม่แมนิโฟลด์ ออยเลอร์ (สำหรับเกต G1)"""
    n = len(V)
    E = np.sort(np.vstack([F[:, [0, 1]], F[:, [1, 2]], F[:, [2, 0]]]), axis=1)
    u, c = np.unique(E, axis=0, return_counts=True)
    A = coo_matrix((np.ones(len(u)), (u[:, 0], u[:, 1])), shape=(n, n))
    nc, _ = connected_components(A, directed=False)
    # จุดไม่แมนิโฟลด์: วงหน้ารอบจุดแตกเป็นหลายพัด
    nm_v = 0
    try:
        tm = trimesh.Trimesh(V, F, process=False)
        nm_v = int(n - len(np.unique(F))) if False else 0
        # นับพัดรอบจุด: จำนวนขอบรอบจุด (ขอบตรงข้าม) ต้องเป็นวงเดียว
        from collections import defaultdict
        ring = defaultdict(list)
        for f in F:
            for k in range(3):
                ring[f[k]].append((f[(k + 1) % 3], f[(k + 2) % 3]))
        for v, es in ring.items():
            adj = defaultdict(list)
            for a_, b_ in es:
                adj[a_].append(b_)
                adj[b_].append(a_)
            seen = set()
            start = es[0][0]
            stack = [start]
            while stack:
                x = stack.pop()
                if x in seen:
                    continue
                seen.add(x)
                stack.extend(adj[x])
            if len(seen) != len(adj):
                nm_v += 1
    except Exception:
        nm_v = -1
    return {"verts": int(n), "faces": int(len(F)), "shells": int(nc), "boundary_edges": int((c == 1).sum()),
            "nonmanifold_edges": int((c > 2).sum()), "nonmanifold_verts": int(nm_v), "euler": int(n - len(u) + len(F))}


def topology_ok(t):
    return (t["shells"] == 1 and t["boundary_edges"] == 0 and t["nonmanifold_edges"] == 0
            and t["nonmanifold_verts"] == 0 and t["euler"] == 2)
