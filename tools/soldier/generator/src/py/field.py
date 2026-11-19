# สนามผิวหนังขั้น 1b/1c (ชั้นไขมันจริงระหว่างกล้ามกับผิว ; 1c เพิ่มร่องตื้นหน้าท้อง/ใต้อกในชั้นไขมัน):
#   1) กายวิภาคผอม (กระดูก + กล้าม ไม่มีไขมัน) แยกเป็นท่อน: ลำตัว คอ หัว ต้นแขน แขนล่าง มือ ต้นขา น่อง เท้า
#   2) แต่ละท่อน: เติมโพรงปิด แล้วเติมร่องด้วยลูกบอลกลิ้ง (closing) รัศมีคงที่ของท่อน -> ไขมันสะสมในร่องก่อน
#      (ทำทีละท่อน: ไม่เกิดพังผืดเชื่อมแขนกับลำตัว หรือขาสองข้าง)
#   3) รวมทุกท่อนแบบนุ่ม -> ระยะยูคลิดจริง (EDT) -> พองออกด้วยไขมันใต้ผิวตามบริเวณ (fatmap) -> ชิ้นลบ -> เบลอเบา ๆ
#   ระยะไขมันและรัศมีเติมร่องทุกค่าคูณ FAT_LEVEL
import time
import numpy as np
from scipy import ndimage as ndi
from scipy.ndimage import map_coordinates
import rig
import muscles as MU
import fatmap as FM
import variants as VR
from sdfk import Grid, F32

K_SKIN = 0.012          # ความนุ่มตรงรอยต่อชิ้นในท่อนเดียวกัน
K_SEG = 0.012           # ความนุ่มตรงรอยต่อระหว่างท่อน
K_FIBRE = 0.013
MUSCLE_LEAN = 0.0005    # เยื่อหุ้มกล้าม (ไม่ใช่ไขมัน)
# รัศมีเติมร่องของแต่ละท่อน (ม. ที่ FAT_LEVEL 1): (เล็ก, ใหญ่) -> เติมสองแบบแล้วผสมตามแผนที่ R ของบริเวณ (fatmap)
#   ผสมสนามระยะสองชุดที่ซ้อนกัน = ผิวเรียบ ไม่มีรอยพับตรงที่รัศมีเปลี่ยน
CLOSE_R = {"torso": (0.012, 0.070), "neck": (0.015, 0.015), "head": (0.0015, 0.0015), "uarm": (0.015, 0.080),
           "farm": (0.008, 0.060), "hand": (0.0025, 0.0025), "thigh": (0.015, 0.120), "shank": (0.010, 0.080),
           "foot": (0.010, 0.010)}          # เท้า: เติมร่องระหว่างนิ้วเท้าบางส่วน (ร่องตื้น ไม่ทะลุ)
R_GLOBAL = 0.008        # เติมร่องเล็กทั้งตัวหลังรวมท่อน (รอยต่อท่อน เอ็นที่พาดข้าม) ยกเว้นมือและศีรษะ
R_FINAL = 0.004         # หลังชั้นไขมัน: ปิดช่องแคบที่เกิดจากผิวสองด้านพองมาชนกัน (กันรูทะลุ)
R_JUNC, S_JUNC = 0.025, 0.010   # เกลี่ยรอยต่อท่อน (เติมร่อง 2.5 ซม. + เบลอ 1 ซม.) ตามแผนที่รอยต่อ
CLOSE_EPS = 0.0025      # ส่วนเผื่อ: ผลเติมร่องต้องลึกกว่านี้จึงแทนผิวเดิม (มากกว่าความคลาดของ EDT)
CLOSE_K = 0.004         # ความนุ่มตรงรอยต่อระหว่างผิวเดิมกับส่วนที่เติม
# ความเรียบ (เบลอสนามของท่อนหลังเติมร่อง): (เล็ก, ใหญ่) ผสมด้วยน้ำหนักเดียวกับรัศมี -> ลอนกว้างตื้น ๆ (ซี่โครง ร่องกล้าม) หายไป
#   แต่ปุ่มที่ควรเห็นนุ่ม ๆ (ไหปลาร้า กระดูกสะบ้า ข้อศอก ข้อเท้า) อยู่ในบริเวณน้ำหนักต่ำ จึงยังเห็น
BLUR_S = {"torso": (0.003, 0.016), "neck": (0.005, 0.005), "head": (0.0010, 0.0010), "uarm": (0.003, 0.011),
          "farm": (0.0025, 0.009), "hand": (0.0010, 0.0010), "thigh": (0.003, 0.020), "shank": (0.003, 0.016),
          "foot": (0.0015, 0.0015)}
# ท่อนแขนขา: เติมร่องในกรอบของกระดูก ด้วยจานแบนตั้งฉากแกนกระดูก (EDT แกน y ยืด ANISO เท่า)
#   -> เติมร่องรอบวงของแขนขา (ร่องระหว่างมัดกล้าม) แต่ไม่เติมความเรียวตามยาว
FRAME = {"uarm": "shoulder", "farm": "elbow", "thigh": "hip", "shank": "knee"}
ANISO = 20.0
SEGS = ["torso", "neck", "head"] + [s + sd for sd in ("L", "R") for s in ("uarm", "farm", "hand", "thigh", "shank", "foot")]
B_SEG = {"pelvis": "torso", "spine": "torso", "chest": "torso", "clavicle": "torso", "neck": "neck", "head": "head",
         "shoulder": "uarm", "uparm_twist": "uarm", "elbow_half": "uarm", "elbow": "farm", "wrist": "hand",
         "hand": "hand", "hip": "thigh", "hip_half": "thigh", "knee_half": "thigh", "knee": "shank", "ankle": "foot",
         "toe": "foot", "heel": "foot"}
M_SEG = {"sternocleidomastoid": "neck", "neck_extensors": "neck", "neck_side": "neck", "trapezius_upper": "neck",
         "scalenes": "neck", "levator_scapulae": "neck",
         "masseter": "head", "deltoid": "uarm", "biceps_brachii": "uarm", "brachialis": "uarm", "triceps_brachii": "uarm",
         "coracobrachialis": "uarm", "brachioradialis": "farm", "forearm_extensors": "farm", "forearm_flexors": "farm",
         "thenar": "hand", "hypothenar": "hand", "tfl_itband": "thigh", "sartorius": "thigh", "rectus_femoris": "thigh",
         "vastus_lateralis": "thigh", "vastus_medialis": "thigh", "adductors": "thigh", "gracilis": "thigh",
         "iliopsoas": "thigh", "biceps_femoris": "thigh", "semitendinosus": "thigh", "gastrocnemius_medial": "shank",
         "gastrocnemius_lateral": "shank", "soleus": "shank", "tibialis_anterior": "shank", "peroneus": "shank",
         "extensor_digitorum": "shank"}


def seg_of_bone(b):
    if b[-1] in "LR" and b[:-1] in B_SEG:
        s = B_SEG[b[:-1]]
        return s if s == "torso" else s + b[-1]
    return B_SEG.get(b, "torso")


def seg_of_muscle(mu):
    s = M_SEG.get(mu["name"], "torso")
    return s if s in ("torso", "neck", "head") else s + mu["side"]


def seg_radius(seg):
    return CLOSE_R[seg[:-1] if seg[-1] in "LR" else seg]


def seg_fatmap_name(seg):
    return "trunk" if seg == "torso" else seg


def seg_blur(seg):
    return BLUR_S[seg[:-1] if seg[-1] in "LR" else seg]


def _gauss(F, h, sigma, aniso=1.0):
    if sigma < 0.5 * h:
        return F
    sv = sigma / h
    return ndi.gaussian_filter(F, (sv, sv / aniso, sv), mode='nearest', truncate=3.0).astype(F32)


def lean_outset(p):
    """ระยะพองของชิ้นกายวิภาค (ไม่รวมไขมัน: ไขมันมาจากชั้นไขมันแยก)"""
    if p.tag in ("face", "pad", "finger", "eye"):
        return p.outset
    if p.name == "spinous_line":
        return -0.004            # สันกระดูกสันหลังจมใต้กล้าม (หลังคนปกติไม่เห็นเป็นสัน)
    if p.tag == "land":
        return 0.0005
    if p.bone[:-1] in ("wrist", "hand", "ankle", "toe") or p.name.startswith("kager"):
        return 0.0005
    return min(p.outset, 0.0015)


def _smin(a, b, k):
    h = np.clip(0.5 + 0.5 * (b - a) / k, 0.0, 1.0)
    return b + (a - b) * h - k * h * (1.0 - h)


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


def subgrid(g, sl, fill=1.0):
    """กริดย่อยบนแลตทิซเดียวกับ g (ช่วงดัชนี sl ; อาจเกินขอบ g ได้)"""
    s = Grid.__new__(Grid)
    s.h = g.h
    s.lo = g.lo + np.array([x.start for x in sl], float) * g.h
    s.n = tuple(x.stop - x.start for x in sl)
    s.F = np.full(s.n, fill, F32)
    return s


def lattice_box(g, lo, hi):
    """ช่วงดัชนี (แลตทิซของ g) ที่คลุมกล่อง lo..hi โดยไม่ตัดที่ขอบ g"""
    i0 = np.floor((np.asarray(lo) - g.lo) / g.h).astype(int)
    i1 = np.ceil((np.asarray(hi) - g.lo) / g.h).astype(int) + 1
    return tuple(slice(int(a), int(b)) for a, b in zip(i0, i1))


def overlap(g, sl):
    """ส่วนซ้อนของช่วง sl กับกริด g: (ช่วงใน g, ช่วงในกริดย่อย) หรือ None"""
    a, b = [], []
    for x, n in zip(sl, g.n):
        s0, s1 = max(x.start, 0), min(x.stop, n)
        if s1 <= s0:
            return None
        a.append(slice(s0, s1))
        b.append(slice(s0 - x.start, s1 - x.start))
    return tuple(a), tuple(b)


# =====================================================================================
# 1) เติมโพรงปิด / เก็บชิ้นใหญ่สุด
# =====================================================================================

def _border_labels(lab, skip_xmin=False):
    s = set()
    faces = [lab[-1], lab[:, 0], lab[:, -1], lab[:, :, 0], lab[:, :, -1]]
    if not skip_xmin:
        faces.append(lab[0])
    for f in faces:
        s.update(np.unique(f).tolist())
    s.discard(0)
    return s


def fill_voids(inside, skip_xmin=False):
    """ทุกช่องที่ไปไม่ถึงขอบกริดจากข้างนอก = ข้างใน (ปิดโพรงกลวงในตัว)"""
    lab, n = ndi.label(~inside)
    if n == 0:
        return inside
    keep = np.zeros(n + 1, bool)
    keep[list(_border_labels(lab, skip_xmin))] = True
    return ~keep[lab]


def largest_component(inside):
    lab, n = ndi.label(inside)
    if n <= 1:
        return inside
    cnt = np.bincount(lab.ravel())
    cnt[0] = 0
    return lab == np.argmax(cnt)


# =====================================================================================
# 2) ระยะยูคลิดจริง (EDT + แก้เศษช่องด้วยค่าสนาม) / เติมร่อง (closing) รัศมีคงที่
# =====================================================================================

def _plane_dist(F, h, P, band_idx):
    """ระยะจุด (ดัชนีกริด) ถึงผิวระดับ 0 ของ F แบบจุด-ระนาบ: จุดผิวจาก marching cubes + นอร์มอลจากเกรเดียนต์
    (แม่นระดับต่ำกว่าช่องกริด: ไม่มีลายขั้นบันไดแบบ EDT)"""
    from skimage.measure import marching_cubes
    from scipy.spatial import cKDTree
    if F.min() >= 0 or F.max() <= 0:
        return None
    V, _, Nn, _ = marching_cubes(F, 0.0, allow_degenerate=False)
    gx, gy, gz = np.gradient(F)
    G3 = np.stack([map_coordinates(gg, V.T, order=1, mode='nearest') for gg in (gx, gy, gz)], 1)
    del gx, gy, gz
    G3 /= np.maximum(np.linalg.norm(G3, axis=1, keepdims=True), 1e-12)
    tree = cKDTree(V)
    out = np.empty(len(band_idx[0]), F32)
    Q = np.stack(band_idx, 1).astype(np.float64)
    for a in range(0, len(Q), 1 << 21):
        q = Q[a:a + (1 << 21)]
        _, j = tree.query(q, workers=-1)
        dv = q - V[j]
        dp = np.einsum('ij,ij->i', dv, G3[j])
        dn = np.linalg.norm(dv, axis=1)
        out[a:a + len(q)] = np.where(dp > 0.3 * dn, dp, dn) * h
    return out


def sdf_outside(F, inside, h, aniso=1.0, band=0.05):
    """สนามระยะจริงสำหรับจุดนอกเนื้อ (ข้างในใช้ค่าเดิม ≤ 0) ; ใกล้ผิวใช้ค่าสนามเดิม, ในแถบ band ใช้ระยะจุด-ระนาบ,
    ไกลกว่านั้นใช้ EDT"""
    d1, idx = ndi.distance_transform_edt(~inside, sampling=(h, h * aniso, h), return_indices=True)
    Fp = F[idx[0], idx[1], idx[2]]
    del idx
    out = np.where(inside, np.minimum(F, -0.25 * h), d1.astype(F32) + np.minimum(Fp, 0)).astype(F32)
    del Fp
    if aniso == 1.0 and band > 0:
        Fm = np.where(inside & (F >= 0), -0.25 * h, np.where((~inside) & (F < 0), 0.25 * h, F)).astype(F32)
        bi = np.nonzero((~inside) & (d1 < band))
        pd = _plane_dist(Fm, h, None, bi)
        if pd is not None:
            out[bi] = pd
        del Fm, bi
    del d1
    near = (~inside) & (F < 1.5 * h)
    out[near] = F[near]
    return out


def closing(F, h, R, skip_xmin=False, s1=None, aniso=1.0):
    """F = สนามของท่อน (ลบ = เนื้อ) -> สนามระยะของรูปที่เติมร่องด้วยลูกบอลรัศมี R แล้ว (aniso > 1 = จานแบนตั้งฉากแกน y)"""
    if s1 is None:
        s1 = sdf_outside(F, fill_voids(F < 0, skip_xmin), h, aniso)
    if R < 1.5 * h:
        return s1
    g1 = s1 - R
    dil = g1 < 0
    d2, idx = ndi.distance_transform_edt(dil, sampling=(h, h * aniso, h), return_indices=True)
    gq = g1[idx[0], idx[1], idx[2]]
    del idx
    D2 = d2.astype(F32) - np.maximum(gq, 0)
    del d2, gq
    # ใช้ผลเติมร่องเฉพาะที่เติมจริง (> ~1 มม.) ; ที่เหลือใช้ระยะเดิม -> ไม่มีลายขั้นบันไดจาก EDT บนผิวนูน
    pc = np.where(dil, R - D2, s1) + CLOSE_EPS
    return np.asarray(_smin(s1, pc, CLOSE_K), F32)


def blur(F, h, sigma, band=0.03):
    Fc = np.clip(F, -band, band)
    out = ndi.gaussian_filter(Fc, sigma / h, mode='nearest').astype(F32)
    far = np.abs(F) > band * 0.9
    out[far] = F[far]
    return out


# =====================================================================================
# 3) ผิวทั้งชุดบนกริด g (กล่องใดก็ได้ ท่าใดก็ได้)
# =====================================================================================

ORDER = {"core": 0, "finger": 1, "land": 2, "headbase": 3.5, "pad": 4, "carve": 4.6, "face": 5, "eyecarve": 5.3, "eye": 5.6}


def _members(prims, mus):
    """สมาชิกของแต่ละท่อน ตามลำดับการรวม ; ชิ้นลบแบบ carve เจาะตามลำดับในท่อนของมัน (เช่น เบ้าตาก่อนใส่ลูกตา)"""
    items = {s: [] for s in SEGS}
    for p in sorted([p for p in prims if (not p.neg) or p.tag in ("carve", "eyecarve")], key=lambda p: ORDER.get(p.tag, 3)):
        items[seg_of_bone(p.bone)].append(("p", p))
    for mu in mus:
        items[seg_of_muscle(mu)].append(("m", mu))
    return items


def skin_field(G, prims, mus, g, fat=1.0, skip_xmin=False, verbose=False, stats=None, pad_fat=0.004, clip_margin=None):
    """สนามผิว (ลบ = ในตัว) ลงใน g.F ; คืน g ; stats (dict) รับปริมาตรกายวิภาค/หลังเติมร่อง (ไว้ประมาณ % ไขมัน)"""
    t0 = time.time()
    h = g.h
    mats = {}

    def Mb(b):
        if b not in mats:
            mats[b] = rig.bone_xform(G, b)
        return mats[b]

    items = _members(prims, mus)
    g.F[...] = 1.0
    anat = np.full(g.n, 1.0, F32) if stats is not None else None
    ghi = g.lo + (np.array(g.n) - 1) * h
    for seg in SEGS:
        its = items[seg]
        if not its:
            continue
        base = seg[:-1] if seg[-1] in "LR" else seg
        Rlo, Rhi = (r * fat for r in seg_radius(seg))
        if base in FRAME:
            M = rig.bone_xform(G, FRAME[base] + seg[-1])
            an = ANISO
        else:
            M = np.eye(4)
            an = 1.0
        Rm, tm = M[:3, :3], M[:3, 3]
        # กล่องของสมาชิกในกรอบท่อน
        boxes = []
        for kind, obj in its:
            if kind == "p":
                k = K_SKIN if obj.k is None else obj.k
                lo, hi = obj.bbox(Mb(obj.bone))
                m = lean_outset(obj) + k + 0.004 + (max(fat - 1, 0) * pad_fat if obj.tag == "pad" else 0)
                lo, hi = lo - m, hi + m
            else:
                lo, hi = MU.muscle_bbox(obj, MUSCLE_LEAN + K_SKIN + 0.004)
            cs = np.array([[x, y, z] for x in (lo[0], hi[0]) for y in (lo[1], hi[1]) for z in (lo[2], hi[2])])
            cl = (cs - tm) @ Rm
            boxes.append((cl.min(0), cl.max(0)))
        llo = np.min([b[0] for b in boxes], 0)
        lhi = np.max([b[1] for b in boxes], 0)
        # ข้ามท่อนที่ไม่แตะกล่องงาน (คิดจากกล่องสมาชิกในโลก)
        cs0 = np.array([[x, y, z] for x in (llo[0], lhi[0]) for y in (llo[1], lhi[1]) for z in (llo[2], lhi[2])])
        w0 = cs0 @ Rm.T + tm
        mg = 0.01 if clip_margin is None else clip_margin
        if np.any(w0.max(0) < g.lo - mg) or np.any(w0.min(0) > ghi + mg):
            continue
        sb_lo, sb_hi = seg_blur(seg)
        reach = np.array([Rhi + 2 * h + 2 * sb_hi, Rhi / an + 2 * h + 2 * sb_hi, Rhi + 2 * h + 2 * sb_hi])
        llo, lhi = llo - reach, lhi + reach
        # ท่อนต้องแตะกริดหลัก (คิดในโลก)
        cs = np.array([[x, y, z] for x in (llo[0], lhi[0]) for y in (llo[1], lhi[1]) for z in (llo[2], lhi[2])])
        wc = cs @ Rm.T + tm
        wlo, whi = wc.min(0), wc.max(0)
        if np.any(whi < g.lo - 0.01) or np.any(wlo > ghi + 0.01):
            continue
        if base in FRAME:
            sub = Grid(llo, lhi, h)
        else:
            if clip_margin is not None:
                llo = np.maximum(llo, g.lo - clip_margin)
                lhi = np.minimum(lhi, ghi + clip_margin)
            sub = subgrid(g, lattice_box(g, llo, lhi))
        for (kind, obj), (lo, hi) in zip(its, boxes):
            ssl = sub.slices(lo, hi)
            if ssl is None:
                continue
            if kind == "p":
                k = K_SKIN if obj.k is None else obj.k
                P = sub.points(ssl)
                if base in FRAME:
                    P = (P @ Rm.T + tm).astype(F32)
                d, _ = obj.eval(P, Mb(obj.bone))
                if obj.neg:
                    sub.combine(ssl, d, k, neg=True)
                    continue
                off = lean_outset(obj) + ((fat - 1) * pad_fat if obj.tag == "pad" else 0.0)
                sub.combine(ssl, d - off, k)
            else:
                Fm = None
                for fb in obj["fibres"]:
                    if base in FRAME:
                        fb = dict(fb, C=((fb["C"] - tm) @ Rm).astype(F32), U=(fb["U"] @ Rm).astype(F32),
                                  V=(fb["V"] @ Rm).astype(F32))
                    ff = MU.fibre_field(sub, ssl, fb)
                    Fm = ff if Fm is None else np.asarray(_smin(Fm, ff, K_FIBRE), F32)
                sub.combine(ssl, (Fm - MUSCLE_LEAN).ravel(), K_SKIN)
        inside_s = fill_voids(sub.F < 0)
        s1 = sdf_outside(sub.F, inside_s, h, an)
        del inside_s
        bl = 1.6 if base in FRAME else 1.0         # แขนขา: เบลอตามแกนน้อยกว่ารอบวง
        phi = _gauss(closing(sub.F, h, Rlo, s1=s1, aniso=an), h, sb_lo, bl)
        if Rhi > Rlo + 1e-6:
            # น้ำหนักผสม: รัศมีที่ต้องการของบริเวณ (fatmap) -> 0 = เติมน้อย/เรียบน้อย, 1 = เติมมาก/เรียบมาก
            Rw = FM.seg_R_grid(sub.lo, sub.n, h, G, seg_fatmap_name(seg), M=M if base in FRAME else None)
            w = np.clip((Rw * fat - Rlo) / (Rhi - Rlo), 0, 1).astype(F32)
            del Rw
            phi_hi = _gauss(closing(sub.F, h, Rhi, s1=s1, aniso=an), h, sb_hi * min(fat, 1.3) ** 0.5, bl)
            phi = ((1 - w) * phi + w * phi_hi).astype(F32)
            del phi_hi, w
        del s1
        if base in FRAME:
            # สุ่มค่าจากกรอบท่อนกลับมากริดโลก
            wsl = g.slices(wlo, whi)
            if wsl is None:
                continue
            Pw = g.points(wsl).astype(np.float64)
            Pl = (Pw - tm) @ Rm
            co = ((Pl - sub.lo) / h).T
            vals = map_coordinates(phi, co, order=1, mode='constant', cval=float(Rhi)).astype(F32)
            shp = tuple(x.stop - x.start for x in wsl)
            g.F[wsl] = np.asarray(_smin(g.F[wsl], vals.reshape(shp), K_SEG), F32)
            if anat is not None:
                av = map_coordinates(sub.F, co, order=1, mode='constant', cval=1.0).astype(F32)
                anat[wsl] = np.minimum(anat[wsl], av.reshape(shp))
            del Pw, Pl, co, vals
        else:
            sl = lattice_box(g, llo, lhi)
            ov = overlap(g, sl)
            if ov is None:
                continue
            a, b = ov
            g.F[a] = np.asarray(_smin(g.F[a], phi[b], K_SEG), F32)
            if anat is not None:
                anat[a] = np.minimum(anat[a], sub.F[b])
        del sub, phi
    if verbose:
        print("  segments + closing %s (%.1fM) in %.1fs" % (g.n, np.prod(g.n) / 1e6, time.time() - t0), flush=True)
    # เกลี่ยรอยต่อท่อน (ขาหนีบ สะโพกข้าง ไหล่ เข่า ศอก): ต้นกล้ามที่โผล่จากท่อนหนึ่งเข้าอีกท่อนกลืนเป็นผิวเดียว
    if R_JUNC > 0:
        wj = FM.junction_grid(g.lo, g.n, h, G)
        if wj.max() > 0.01:
            s0 = sdf_outside(g.F, fill_voids(g.F < 0, skip_xmin), h)
            cj = _gauss(closing(g.F, h, R_JUNC * min(fat, 1.3), s1=s0), h, S_JUNC)
            g.F = ((1 - wj) * s0 + wj * cj).astype(F32)
            del s0, cj
        del wj
    # เติมร่องเล็กทั้งตัว (รอยต่อท่อน ช่องใต้เอ็น) ; มือ/ศีรษะคงเดิม (ช่องระหว่างนิ้ว หู)
    if R_GLOBAL > 0:
        s0 = sdf_outside(g.F, fill_voids(g.F < 0, skip_xmin), h)
        cg = closing(g.F, h, R_GLOBAL * min(fat, 1.0) ** 0.5, s1=s0)
        m = FM.membership_grid(g.lo, g.n, h, G, ("head", "handL", "handR"))
        g.F = ((1 - m) * cg + m * s0).astype(F32)
        del s0, cg
    # ระยะจริงของรูปรวม -> ชั้นไขมัน
    inside = fill_voids(g.F < 0, skip_xmin)
    if stats is not None:
        if skip_xmin:
            i0 = int(np.ceil(-g.lo[0] / h - 1e-6))
            stats["closed_m3"] = float(2 * inside[i0:].sum() * h ** 3)
            stats["anat_m3"] = float(2 * (anat[i0:] < 0).sum() * h ** 3)
        else:
            stats["closed_m3"] = float(inside.sum() * h ** 3)
            stats["anat_m3"] = float((anat < 0).sum() * h ** 3)
        del anat
    s = sdf_outside(g.F, inside, h)
    del inside
    T, _ = FM.map_grid(g.lo, g.n, h, G)
    g.F = (s - T * fat).astype(F32)
    del s, T
    # ขั้น 1c: ร่องตื้นในชั้นไขมันด้านหน้า (กลางท้อง รอยคั่นกล้ามท้อง สะดือ ใต้ขอบอก)
    FM.add_grooves(g, G, FM.groove_scale(fat))
    if VR.CUR is not None:
        VR.add_hair(g, G)                  # ร่างหลากหลาย: ผมยกจากหนังศีรษะ (ผมสั้น ผมหยิก ผมรวบ)
    if R_FINAL > 0:
        if R_GLOBAL <= 0:
            m = FM.membership_grid(g.lo, g.n, h, G, ("head", "handL", "handR"))
        s0 = sdf_outside(g.F, fill_voids(g.F < 0, skip_xmin), h)
        cg = closing(g.F, h, R_FINAL, s1=s0)
        g.F = ((1 - m) * cg + m * s0).astype(F32)
        del s0, cg
    del m
    # ชิ้นลบ (ร่องปาก รูหู อุ้งเท้า) หลังชั้นไขมัน
    for p in prims:
        if not p.neg or p.tag in ("carve", "eyecarve"):
            continue
        k = 0.004 if p.k is None else p.k
        lo, hi = p.bbox(Mb(p.bone))
        ssl = g.slices(lo - k - 0.004, hi + k + 0.004)
        if ssl is None:
            continue
        d, _ = p.eval(g.points(ssl), Mb(p.bone))
        g.combine(ssl, d, k, neg=True)
    # ลูกตาใส่กลับหลังเจาะช่องตา: ผิวลูกตาเป็นพื้นของช่องตา (ตาเปิดจริง ไม่มีผิวคลุม)
    for p in prims:
        if p.neg or not p.p.get("post"):
            continue
        lo, hi = p.bbox(Mb(p.bone))
        ssl = g.slices(lo - 0.003, hi + 0.003)
        if ssl is None:
            continue
        d, _ = p.eval(g.points(ssl), Mb(p.bone))
        g.combine(ssl, d, 0.0008)
    if verbose:
        print("  skin field done in %.1fs" % (time.time() - t0), flush=True)
    return g


def skin_coarse(G, prims, mus, fat=1.0, h=0.003, box=None, sigma=0.0035, skip_xmin=False, verbose=False, stats=None):
    if box is None:
        lo, hi = body_box(G, prims, mus, 0.012)
        box = (lo - 0.035 * fat - 0.01, hi + 0.035 * fat + 0.01)
    g = Grid(box[0], box[1], h)
    skin_field(G, prims, mus, g, fat, skip_xmin, verbose, stats)
    if sigma > 0:
        g.F = blur(g.F, h, sigma)
    return g


def upsample(gc, gf):
    """ค่าสนามของกริดหยาบ gc ที่จุดของกริดละเอียด gf (เชิงเส้น) ทีละแผ่น x"""
    out = np.empty(gf.n, F32)
    cy = (gf.lo[1] + np.arange(gf.n[1]) * gf.h - gc.lo[1]) / gc.h
    cz = (gf.lo[2] + np.arange(gf.n[2]) * gf.h - gc.lo[2]) / gc.h
    CY, CZ = np.meshgrid(cy, cz, indexing='ij')
    for i in range(gf.n[0]):
        cx = (gf.lo[0] + i * gf.h - gc.lo[0]) / gc.h
        out[i] = map_coordinates(gc.F, [np.full(CY.shape, cx), CY, CZ], order=1, mode='nearest')
    return out


# =====================================================================================
# สนามกล้ามมัดเดียว (ภาพชั้นกล้าม)
# =====================================================================================

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


# =====================================================================================
# 4) ผิวละเอียดสำหรับเมชปั้น (ท่าผูก A): ครึ่งซ้าย + เผื่อฝั่งขวา (ghost) ; หยาบ 3 มม. -> ละเอียด 2 มม.
#    + กล่องละเอียดคำนวณใหม่ (ศีรษะ มือ เท้า) ; แลตทิซมี x = 0 พอดี และพื้น y = 0 อยู่กึ่งกลางช่อง
# =====================================================================================
DETAIL_BOXES = [("head", (-0.12, 1.445, -0.13), (0.12, 1.80, 0.16)),     # ลงถึงกลางคอ: รอยต่อกล่องไม่ตกที่ใต้คาง
                ("handL", (0.47, 0.73, -0.05), (0.71, 1.02, 0.14)),
                ("footL", (0.09, -0.012, -0.11), (0.28, 0.135, 0.235))]
RAMP = 0.015


def _box_ramp(gd, gf, sl):
    """น้ำหนักกล่องละเอียด: 1 ข้างใน -> 0 ที่ผิวกล่อง (ยกเว้นด้านที่ชนขอบกริดหลัก)"""
    w = np.ones(gd.n, F32)
    for ax in range(3):
        n = gd.n[ax]
        d0 = np.arange(n) * gd.h
        d1 = (n - 1 - np.arange(n)) * gd.h
        r = np.ones(n)
        if sl[ax].start > 0:
            r = np.minimum(r, np.clip(d0 / RAMP, 0, 1))
        if sl[ax].stop < gf.n[ax]:
            r = np.minimum(r, np.clip(d1 / RAMP, 0, 1))
        r = r * r * (3 - 2 * r)
        shp = [1, 1, 1]
        shp[ax] = n
        w = w * r.reshape(shp).astype(F32)
    return w


FACE_SHARP = [  # (ศูนย์ท่า I ในกรอบศีรษะ, ซิกมา) บริเวณที่คงรายละเอียดคม
    ((0.032, 1.663, 0.085), (0.022, 0.016, 0.020)), ((-0.032, 1.663, 0.085), (0.022, 0.016, 0.020)),
    ((0.0, 1.632, 0.105), (0.020, 0.030, 0.025)), ((0.0, 1.588, 0.100), (0.032, 0.016, 0.020)),
    ((0.076, 1.643, -0.008), (0.020, 0.035, 0.025)), ((-0.076, 1.643, -0.008), (0.020, 0.035, 0.025))]


def _face_sharp(G, gd):
    """น้ำหนักความคมในกล่องศีรษะ: 1 ที่ตา จมูก ปาก หู ; 0.25 ที่อื่น"""
    M = rig.bone_xform(G, "head")
    xs = [gd.lo[i] + np.arange(gd.n[i]) * gd.h for i in range(3)]
    out = np.zeros(gd.n, F32)
    for c, sg in FACE_SHARP:
        cw = (M @ np.array([*c, 1.0]))[:3]
        gx = np.exp(-((xs[0] - cw[0]) / sg[0]) ** 2)
        gy = np.exp(-((xs[1] - cw[1]) / sg[1]) ** 2)
        gz = np.exp(-((xs[2] - cw[2]) / sg[2]) ** 2)
        out = np.maximum(out, (gx[:, None, None] * gy[None, :, None] * gz[None, None, :]).astype(F32))
    return (0.25 + 0.75 * out).astype(F32)


def skin_fine(G, prims, mus, fat=1.0, hc=0.003, hf=0.002, ghost=0.09, verbose=False, stats=None,
              sigma_body=0.0020, sigma_fine=0.0007):
    t0 = time.time()
    lo, hi = body_box(G, prims, mus, 0.012)
    m = 0.035 * fat + 0.012
    lo, hi = lo - m, hi + m
    i0 = int(round(ghost / hf))
    ny0 = int(np.ceil(-lo[1] / hf))
    lo_f = np.array([-i0 * hf, -(ny0 + 0.5) * hf, lo[2]])
    gf = Grid(lo_f, np.array([hi[0], hi[1], hi[2]]), hf)
    gc = Grid(lo_f, gf.lo + (np.array(gf.n) - 1) * hf + hc, hc)
    skin_field(G, prims, mus, gc, fat, skip_xmin=True, verbose=verbose, stats=stats)
    if verbose:
        print("  coarse %s done %.1fs" % (gc.n, time.time() - t0), flush=True)
    gf.F = upsample(gc, gf)
    del gc
    wfine = np.zeros(gf.n, F32)
    for name, blo, bhi in (DETAIL_BOXES if VR.CUR is None else VR.detail_boxes(DETAIL_BOXES)):
        sl = gf.slices(blo, bhi)
        if sl is None:
            continue
        gd = subgrid(gf, sl)
        skin_field(G, prims, mus, gd, fat, skip_xmin=(sl[0].start == 0), clip_margin=0.03)
        r = _box_ramp(gd, gf, sl)
        gf.F[sl] = ((1 - r) * gf.F[sl] + r * gd.F).astype(F32)
        if name == "head":
            # คมเฉพาะตา จมูก ปาก หู ; แก้ม กราม คอ ใช้ความเรียบแบบลำตัว (ไม่เป็นคลื่นเล็ก ๆ บนแก้ม)
            r = r * _face_sharp(G, gd)
        wfine[sl] = np.maximum(wfine[sl], r)
        if verbose:
            print("  detail %s %s done %.1fs" % (name, gd.n, time.time() - t0), flush=True)
        del gd, r
    Fb = blur(gf.F, hf, sigma_body)
    Fd = blur(gf.F, hf, sigma_fine)
    gf.F = ((1 - wfine) * Fb + wfine * Fd).astype(F32)
    del Fb, Fd, wfine
    y = (gf.lo[1] + np.arange(gf.n[1]) * hf).astype(F32)
    gf.F = np.maximum(gf.F, -y[None, :, None])
    inside = largest_component(fill_voids(gf.F < 0, skip_xmin=True))
    gf.F = np.where(inside, np.minimum(gf.F, -1e-5), np.maximum(gf.F, 1e-5)).astype(F32)
    del inside
    if verbose:
        print("  fine skin %s (%.1fM) in %.1fs" % (gf.n, np.prod(gf.n) / 1e6, time.time() - t0), flush=True)
    return gf, i0


def sample_sym(g, P):
    """ค่าสนามครึ่งกริด ที่จุดใดก็ได้ (ฝั่งขวาใช้ภาพสะท้อน)"""
    Q = np.asarray(P, float).copy()
    Q[:, 0] = np.abs(Q[:, 0])
    return g.sample(Q)
