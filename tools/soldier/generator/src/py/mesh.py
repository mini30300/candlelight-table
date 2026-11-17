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
SCULPT_TRIS = 160000


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


# ---------------- สีจุดยอด (sRGB): ผิว × AO + เฉดเฉพาะที่ (ผมสั้น คิ้ว ตา ปาก เล็บ) ----------------
SKIN = np.array([0.84, 0.645, 0.505])
HAIR = np.array([0.24, 0.19, 0.16])
BROW = np.array([0.30, 0.22, 0.17])
LIP = np.array([0.70, 0.44, 0.40])
SCLERA = np.array([0.86, 0.80, 0.74])
IRIS = np.array([0.22, 0.15, 0.10])
NAIL = np.array([0.88, 0.72, 0.66])


def sdf_ao(g, V, N):
    ds = np.array([0.006, 0.012, 0.024, 0.045])
    occ = np.zeros(len(V))
    for i, d in enumerate(ds):
        f = g.sample(V + N * d)
        occ += np.clip((d - f) / d, 0, 1) * (0.5 ** i)
    return np.clip(1.0 - 0.6 * occ / 1.875 * 1.6, 0.45, 1.0)


def head_local(V, G):
    M = np.linalg.inv(rig.bone_xform(G, "head"))
    return V @ M[:3, :3].T + M[:3, 3]


def colours(V, N, g, G, F=None):
    """คืน (rgb (n,3) sRGB, flesh (n,)) ; flesh = ผิวเนื้อ (ใช้แสงห่อแบบผิว) 0 = ผม/ตา"""
    ao = sdf_ao(g, V, N)
    if F is not None:
        A = adjacency(F, len(V))
        for _ in range(6):
            ao = 0.5 * ao + 0.5 * (A @ ao)
    rgb = np.tile(SKIN, (len(V), 1))
    flesh = np.ones(len(V))
    H = head_local(V, G)                      # พิกัดท่า I ของศีรษะ
    x, y, z = np.abs(H[:, 0]), H[:, 1], H[:, 2]
    near_head = np.linalg.norm(H - np.array([0, 1.69, 0.0]), axis=1) < 0.16
    # ผมสั้นเกรียน: เหนือแนวไรผม (หน้าผาก 1.738 ลดลงไปข้างหลังถึง 1.640) ไล่สีนุ่ม 1.2 ซม. ; ไม่ทาหูและจอน
    zf = np.clip((z + 0.09) / 0.19, 0, 1)
    hairline = 1.640 + 0.098 * zf ** 1.5
    ear = (x > 0.066) & (y > 1.620) & (y < 1.700) & (z > -0.040) & (z < 0.020)
    t = np.clip((y - hairline) / 0.012, 0, 1) * near_head * (~ear)
    a = 0.80 * t
    rgb = rgb * (1 - a[:, None]) + HAIR * a[:, None]
    flesh = flesh * (1 - 0.7 * t)
    # คิ้ว
    for sx in (1, -1):
        c = np.array([sx * 0.033, 1.6805, 0.093])
        e = ((H[:, 0] - c[0]) / 0.019) ** 2 + ((H[:, 1] - c[1]) / 0.0045) ** 2 + ((H[:, 2] - c[2]) / 0.03) ** 2
        m = near_head & (e < 1)
        a = np.clip(1 - e[m], 0, 1)[:, None] * 0.8
        rgb[m] = rgb[m] * (1 - a) + BROW * a
        # ตา: ตาขาว + ม่านตา (ด้านหน้าลูกตา)
        ec = np.array([sx * 0.032, 1.6630, 0.0785])
        r = np.linalg.norm(H - ec, axis=1)
        eye = near_head & (r < 0.01285) & (H[:, 2] > ec[2] + 0.004)
        rgb[eye] = SCLERA
        flesh[eye] = 0.6
        dirz = (H[:, 2] - ec[2]) / np.maximum(r, 1e-6)
        iris = eye & (dirz > 0.80)
        rgb[iris] = IRIS
    # ปาก
    lip = near_head & (np.abs(H[:, 0]) < 0.024) & (H[:, 1] > 1.564) & (H[:, 1] < 1.590) & (H[:, 2] > 0.086)
    a = np.clip(1 - np.abs(H[:, 0]) / 0.024, 0, 1) ** 0.5 * 0.75
    rgb[lip] = rgb[lip] * (1 - a[lip, None]) + LIP * a[lip, None]
    # เล็บ: ปลายนิ้วด้านหลังมือ (ด้านนอก) — กรอบ handL
    for sd, sx in (("L", 1), ("R", -1)):
        M = np.linalg.inv(rig.bone_xform(G, "hand" + sd))
        P = V @ M[:3, :3].T + M[:3, 3]
        for fn in ("index", "middle", "ring", "little"):
            from anatomy import FINGERS, _finger_chain
            mcp, lens, flex, rads, spr = FINGERS[fn]
            pts, rr = _finger_chain(mcp, lens, flex, rads, spr)
            tip = pts[-1] * np.array([sx, 1, 1])
            d = np.linalg.norm(P - tip, axis=1)
            outward = (P[:, 0] - tip[0]) * sx > 0.002
            m = (d < 0.010) & outward
            rgb[m] = rgb[m] * 0.35 + NAIL * 0.65
    rgb = rgb * (0.55 + 0.45 * ao[:, None])
    return np.clip(rgb, 0, 1), flesh, ao
