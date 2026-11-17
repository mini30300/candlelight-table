# สนามผิวหนัง: รวมนุ่ม (smin) ของแกนลึก ปุ่มกระดูก กล้ามเนื้อ ไขมัน ใบหน้า แต่ละชิ้นพองออกด้วยไขมันใต้ผิวของมัน
#   ผิว = smin_i(d_i - ไขมัน_i) ; ชิ้นลบ (เบ้าตา ร่องปาก) = smax
import time
import numpy as np
import rig
import muscles as MU
from sdfk import Grid, F32

K_SKIN = 0.012          # ความนุ่มตรงรอยต่อกล้าม (ร่องกล้ามยังเห็น)
K_FIBRE = 0.013
MUSCLE_FAT_EXTRA = 0.0008    # ไขมันใต้ผิวเพิ่มเหนือกล้ามทุกมัด (ทหารผอมแต่ไม่ใช่นักเพาะกาย)


def body_box(G, prims, mus, pad=0.03):
    los, his = [], []
    for p in prims:
        if p.neg:
            continue
        lo, hi = p.bbox(rig.bone_xform(G, p.bone))
        los.append(lo)
        his.append(hi)
    for mu in mus:
        lo, hi = MU.muscle_bbox(mu)
        los.append(lo)
        his.append(hi)
    return np.min(los, 0) - pad, np.max(his, 0) + pad


def skin_field(G, prims, mus, h=0.003, box=None, verbose=True, only_bones=None):
    """สนามผิวในท่า G บนกริดระยะ h ; box = (lo, hi) จำกัดบริเวณ (ใช้ตอนคำนวณท่าแก้)"""
    t0 = time.time()
    if box is None:
        box = body_box(G, prims, mus)
    g = Grid(box[0], box[1], h)
    mats = {}

    def Mb(b):
        if b not in mats:
            mats[b] = rig.bone_xform(G, b)
        return mats[b]

    order = {"core": 0, "finger": 1, "land": 2, "pad": 4, "face": 5}
    pos = sorted([p for p in prims if not p.neg], key=lambda p: order.get(p.tag, 3))
    for p in pos:
        if only_bones is not None and p.bone not in only_bones:
            continue
        k = K_SKIN if p.k is None else p.k
        lo, hi = p.bbox(Mb(p.bone))
        sl = g.slices(lo - p.outset - k - 0.004, hi + p.outset + k + 0.004)
        if sl is None:
            continue
        P = g.points(sl)
        d, _ = p.eval(P, Mb(p.bone))
        g.combine(sl, d - p.outset, k)
    for mu in mus:
        lo, hi = MU.muscle_bbox(mu, mu["outset"] + K_SKIN + 0.004)
        sl = g.slices(lo, hi)
        if sl is None:
            continue
        Fm = None
        for fb in mu["fibres"]:
            ff = MU.fibre_field(g, sl, fb)
            Fm = ff if Fm is None else np.asarray(_smin(Fm, ff, K_FIBRE), F32)
        g.combine(sl, (Fm - mu["outset"] - MUSCLE_FAT_EXTRA).ravel(), K_SKIN)
    for p in prims:
        if not p.neg:
            continue
        k = 0.004 if p.k is None else p.k
        lo, hi = p.bbox(Mb(p.bone))
        sl = g.slices(lo - k - 0.004, hi + k + 0.004)
        if sl is None:
            continue
        P = g.points(sl)
        d, _ = p.eval(P, Mb(p.bone))
        g.combine(sl, d, k, neg=True)
    if verbose:
        print("  skin field %s (%.1fM) in %.1fs" % (g.n, np.prod(g.n) / 1e6, time.time() - t0), flush=True)
    return g


def _smin(a, b, k):
    h = np.clip(0.5 + 0.5 * (b - a) / k, 0.0, 1.0)
    return b + (a - b) * h - k * h * (1.0 - h)


def muscle_field(mu, h=0.0025):
    lo, hi = MU.muscle_bbox(mu, 0.006)
    g = Grid(lo, hi, h)
    sl = tuple(slice(0, n) for n in g.n)
    Fm = None
    for fb in mu["fibres"]:
        ff = MU.fibre_field(g, sl, fb)
        Fm = ff if Fm is None else np.asarray(_smin(Fm, ff, K_FIBRE), F32)
    g.F = Fm.astype(F32)
    return g


# ---------------- ภาพตัวอย่างเร็ว (มองตามแกน) ----------------

def preview(g, path, views=("front", "side", "back"), scale=2):
    from PIL import Image
    inside = g.F < 0
    imgs = []
    for v in views:
        if v in ("front", "back"):
            ax = 2
            occ = inside if v == "back" else inside[:, :, ::-1]
        else:
            ax = 0
            occ = inside if v == "side" else inside[::-1]
        hit = occ.any(axis=ax)
        depth = np.argmax(occ, axis=ax).astype(float)
        depth[~hit] = np.nan
        if ax == 2:
            img = depth.T[::-1]                      # แถว = y (บนลงล่าง), คอลัมน์ = x
            if v == "front":
                img = img[:, ::-1]                   # มองจากหน้า: ซ้ายของหุ่นอยู่ขวาภาพ
        else:
            img = depth[::-1]                        # แถว = y, คอลัมน์ = z
            if v == "side":
                img = img[:, ::-1]
        gy, gx = np.gradient(np.nan_to_num(img, nan=0.0))
        n = np.stack([-gx, -gy, np.full_like(gx, 1.5)], -1)
        n /= np.linalg.norm(n, axis=-1, keepdims=True)
        l = np.array([-0.4, 0.5, 0.75])
        l /= np.linalg.norm(l)
        sh = np.clip(n @ l, 0, 1) * 0.75 + 0.25
        rgb = np.stack([sh * 0.92, sh * 0.74, sh * 0.62], -1)
        rgb[np.isnan(img)] = [0.12, 0.13, 0.15]
        imgs.append((rgb * 255).astype(np.uint8))
    hmax = max(i.shape[0] for i in imgs)
    pad = [np.vstack([i, np.full((hmax - i.shape[0], i.shape[1], 3), 30, np.uint8)]) for i in imgs]
    out = np.hstack(pad)
    im = Image.fromarray(out)
    im = im.resize((im.width * scale, im.height * scale), Image.NEAREST)
    im.save(path)
    return path


# ---------------- ชั้นใต้ผิวหนัง: ปรับผิวให้เรียบ (เบลอสนาม) น้อยลงที่มือ หน้า นิ้วเท้า ----------------
FINE_SPOTS = [("wristL", (0.200, 0.805, 0.010), 0.065, 0.11), ("wristR", (-0.200, 0.805, 0.010), 0.065, 0.11),
              ("head", (0.0, 1.640, 0.085), 0.045, 0.085), ("toeL", (0.105, 0.012, 0.170), 0.035, 0.07),
              ("toeR", (-0.105, 0.012, 0.170), 0.035, 0.07)]


def smooth_skin(g, G, sigma_body=0.005, sigma_fine=0.0012, band=0.03):
    from scipy.ndimage import gaussian_filter
    F = g.F
    Fc = np.clip(F, -band, band)
    Fb = gaussian_filter(Fc, sigma_body / g.h, mode='nearest').astype(F32)
    Ff = gaussian_filter(Fc, sigma_fine / g.h, mode='nearest').astype(F32) if sigma_fine > 0 else Fc
    ax = [g.lo[i] + np.arange(g.n[i], dtype=F32) * g.h for i in range(3)]
    mask = np.ones(g.n, F32)
    for b, p, r0, r1 in FINE_SPOTS:
        c = (rig.bone_xform(G, b) @ np.array([*p, 1.0]))[:3].astype(F32)
        d2 = (ax[0][:, None, None] - c[0]) ** 2 + (ax[1][None, :, None] - c[1]) ** 2 + (ax[2][None, None, :] - c[2]) ** 2
        m = np.clip((np.sqrt(d2) - r0) / (r1 - r0), 0, 1)
        mask = np.minimum(mask, m * m * (3 - 2 * m))
    out = Ff + (Fb - Ff) * mask
    far = np.abs(F) > band * 0.9
    out[far] = F[far]
    g.F = out.astype(F32)
    return g
