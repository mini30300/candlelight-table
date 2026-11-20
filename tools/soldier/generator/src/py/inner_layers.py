# ชั้นในของทหาร (บาดแผลเห็นเนื้อและกระดูก: เกมระดับ hi/mid) จากผลของ build.py ไม่ปั้นใหม่ ไม่มีการสุ่ม
#   out/data/inner_bone.bin  = กระดูกจริง (skeleton.bin ท่าผูก) ลดเหลือ ~5k สามเหลี่ยม ผูกแข็งกับกระดูกของแต่ละชิ้น
#   out/data/inner_flesh.bin = ผิวปั้น (work/stage_skin.npz) ลดเหลือ ~7k แล้วหดเข้าเท่าความหนาไขมัน (fatmap)
#                              น้ำหนักย้ายจากผิว (work/stage_weights.npz: Wh4 ชุดเดียวกับ hi/mid)
#   ทั้งสองชั้นมี part = ส่วนร่างกายต่อจุดยอด (parts.py) และถูกตรวจทีละจุดยอดว่าอยู่ใต้ผิว hi และ mid จริง (ระยะถึง
#   สามเหลี่ยมที่ใกล้สุด มีเครื่องหมาย): เนื้อลึก >= FLESH_HI_MM กระดูก >= BONE_HI_MM ไม่งั้นกดเข้า / ไม่ผ่าน = หยุด
#   ร่างแบบอื่น (variants: out/data/variant.json มี k และชื่อร่าง) ผิวปั้นอยู่ในกรอบ 1.78 ม. -> คิดในกรอบนั้นแล้วคูณ k
#   ไขมันจากแผนที่ของร่างนั้นเอง (variants.use) + ความหนาของชิ้น pad (เต้านม แผ่นลาดอก ไขมันใต้ไหปลาร้า) ไม่เกิน FAT_HI_V
#   แล้วจุดเนื้อที่โผล่พ้นผิว hi ในท่าใดของเกมถูกกดลงในท่าผูก (inner_posed.push_posed ; ตรวจซ้ำด้วย inner_posed.py)
#   และจุดกระดูกอกหน้า/สะโพกที่โผล่ในท่าเกินร่างหลักถูกกดลงในท่าผูก (inner_posed.push_bone) ; ใหม่ 0.14: ทุกร่างรวมร่างหลัก
#   /usr/bin/python3 inner_layers.py [--out DIR] [--work DIR]      (~5 วินาที ; ต่อด้วย src/gd/assemble_inner.gd)
import argparse
import json
import os
import time
import numpy as np
from scipy.sparse import coo_matrix
from scipy.sparse.csgraph import connected_components
import fast_simplification as FS
from scipy.spatial import cKDTree
import rig
import mesh as ME
import weights as WT
import layers as LY
import fatmap as FM
import parts as PT
import variants as VR

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
BONE_TRIS = 5000          # งบชั้นกระดูก (สามเหลี่ยม)
BONE_MIN = 12             # ขั้นต่ำต่อชิ้น (ชิ้นเล็กไม่หาย)
FLESH_TRIS = 7000         # งบชั้นเนื้อ
FAT_LO, FAT_HI = 0.003, 0.016   # ระยะหดเข้าจากผิว (ม.) = ความหนาไขมันที่จุดนั้น จำกัดช่วง
FAT_HI_V = 0.040          # ร่างแบบอื่น: ไขมัน + ชิ้น pad หนาได้ถึงเท่านี้ (เต้านม ≤ 40 มม. สะโพกหญิง ~30 มม.)
FLESH_SMOOTH = 4          # เกลี่ย Taubin หลังหด (กันรอยพับในซอก)
BONE_UNDER = 0.004        # กระดูกอยู่ใต้ผิวอย่างน้อยเท่านี้ (ม.): ชั้นภาพเดิมมีขอบสะบักโผล่หลังผิว ~3 ซม. -> กดกลับเข้าใต้ผิว
FLESH_UNDER = 0.002       # เนื้ออยู่ใต้ผิวอย่างน้อยเท่านี้ (ซอกนิ้ว ข้อเท้า)
# ใต้ผิวที่เกมวาดจริง (hi/mid ลดจากผิวปั้น นูนน้อยกว่าเล็กน้อย): กดถึงระยะ PUSH ตรวจผ่านที่ระยะ MIN (เทสในเกมใช้ค่า MIN)
FLESH_PUSH, FLESH_MIN = 0.0015, 0.001
BONE_PUSH, BONE_MIN_D = 0.0025, 0.002
CAND_K = 16               # จุดยอดผิวใกล้สุดที่ใช้หาสามเหลี่ยมผู้สมัคร


def read_bin(path):
    """อ่านไฟล์ของ layers.write_bin: [ยาวหัว 4 ไบต์][หัว JSON][ข้อมูลดิบ]"""
    with open(path, "rb") as f:
        hl = int.from_bytes(f.read(4), "little")
        head = json.loads(f.read(hl))
        blob = f.read()
    out = {"meta": head["meta"]}
    for a in head["arrays"]:
        dt = "<f4" if a["type"] == "f32" else "<i4"
        out[a["name"]] = np.frombuffer(blob, dt, a["count"], a["offset"]).reshape(a["shape"])
    return out


def _under_skin(V, Vs, Ns, margin, it=3):
    """จุดที่อยู่นอกผิวหรือใต้ผิวไม่ถึง margin -> เลื่อนเข้าตามนอร์มอลของจุดผิวใกล้สุด (ผิวปั้น ~3 มม. ต่อจุด) ; คืน (V, จำนวนที่เลื่อน)"""
    tree = cKDTree(Vs)
    V = V.copy()
    moved = np.zeros(len(V), bool)
    for _ in range(it):
        _, i = tree.query(V, k=1)
        s = np.einsum('ij,ij->i', V - Vs[i], Ns[i])
        m = s > -margin
        if not m.any():
            break
        V[m] -= Ns[i[m]] * (s[m] + margin)[:, None]
        moved |= m
    return V, int(moved.sum())


def _closest_on_tris(P, A, B, C):
    """จุดใกล้สุดบนสามเหลี่ยม ABC ของแต่ละจุด P (Ericson) -> พิกัดแบรีเซนทริก (m,3)"""
    ab, ac, ap = B - A, C - A, P - A
    d1, d2 = np.einsum('ij,ij->i', ab, ap), np.einsum('ij,ij->i', ac, ap)
    bp = P - B
    d3, d4 = np.einsum('ij,ij->i', ab, bp), np.einsum('ij,ij->i', ac, bp)
    cp = P - C
    d5, d6 = np.einsum('ij,ij->i', ab, cp), np.einsum('ij,ij->i', ac, cp)
    va, vb, vc = d3 * d6 - d5 * d4, d5 * d2 - d1 * d6, d1 * d4 - d3 * d2
    den = va + vb + vc
    den = np.where(np.abs(den) < 1e-30, 1e-30, den)
    v, w = vb / den, vc / den
    bc = np.c_[1 - v - w, v, w]                                   # ในสามเหลี่ยม
    with np.errstate(divide="ignore", invalid="ignore"):
        t = (d4 - d3) / ((d4 - d3) + (d5 - d6))
        m = (va <= 0) & (d4 - d3 >= 0) & (d5 - d6 >= 0)
        bc[m] = np.c_[np.zeros(m.sum()), 1 - t[m], t[m]]
        t = d2 / (d2 - d6)
        m = (vb <= 0) & (d2 >= 0) & (d6 <= 0)
        bc[m] = np.c_[1 - t[m], np.zeros(m.sum()), t[m]]
        m = (d6 >= 0) & (d5 <= d6)
        bc[m] = [0.0, 0.0, 1.0]
        t = d1 / (d1 - d3)
        m = (vc <= 0) & (d1 >= 0) & (d3 <= 0)
        bc[m] = np.c_[1 - t[m], t[m], np.zeros(m.sum())]
        m = (d3 >= 0) & (d4 <= d3)
        bc[m] = [0.0, 1.0, 0.0]
        m = (d1 <= 0) & (d2 <= 0)
        bc[m] = [1.0, 0.0, 0.0]
    return bc


class SkinDepth:
    """ระยะมีเครื่องหมายจากจุดถึงผิว (เมชปิด ท่าผูก): บวก = นอกผิว ; นอร์มอล = นอร์มอลจุดยอดเฉลี่ยตามแบรีเซนทริก"""

    def __init__(self, V, F):
        self.V, self.F = np.asarray(V, np.float64), np.asarray(F, np.int64)
        self.N = ME.vnormals(self.V, self.F)
        self.tree = cKDTree(self.V)
        n = len(self.V)
        order = np.argsort(self.F.ravel(), kind="stable")
        cnt = np.bincount(self.F.ravel(), minlength=n)
        self.start = np.r_[0, np.cumsum(cnt)]
        self.tri_of = order // 3
        self.maxdeg = int(cnt.max())

    def query(self, P, with_tri=False):
        """with_tri = คืนดัชนีสามเหลี่ยมที่ใกล้สุดด้วย (inner_posed.py)"""
        P = np.asarray(P, np.float64)
        _, vi = self.tree.query(P, k=CAND_K)
        cand = -np.ones((len(P), CAND_K * self.maxdeg), np.int64)
        for j in range(CAND_K):
            s0, s1 = self.start[vi[:, j]], self.start[vi[:, j] + 1]
            for d in range(self.maxdeg):
                ok = s0 + d < s1
                cand[ok, j * self.maxdeg + d] = self.tri_of[(s0 + d)[ok]]
        rows, cols = np.nonzero(cand >= 0)
        t = cand[rows, cols]
        A, B, C = (self.V[self.F[t, k]] for k in range(3))
        bc = _closest_on_tris(P[rows], A, B, C)
        Q = bc[:, :1] * A + bc[:, 1:2] * B + bc[:, 2:] * C
        d2 = ((P[rows] - Q) ** 2).sum(1)
        best = np.full(len(P), np.inf)
        np.minimum.at(best, rows, d2)
        pick = np.flatnonzero(d2 <= best[rows])
        first = np.full(len(P), -1)
        first[rows[pick[::-1]]] = pick[::-1]
        Qb, bcb, tb = Q[first], bc[first], t[first]
        Nq = sum(bcb[:, k:k + 1] * self.N[self.F[tb, k]] for k in range(3))
        Nq /= np.maximum(np.linalg.norm(Nq, axis=1, keepdims=True), 1e-12)
        if with_tri:
            return np.einsum('ij,ij->i', P - Qb, Nq), Nq, tb
        return np.einsum('ij,ij->i', P - Qb, Nq), Nq


def _push_under(V, skins, margin, it=4, floor=None, more=0):
    """กดจุดที่อยู่นอกผิวใด ๆ หรือลึกไม่ถึง margin เข้าใต้ผิวทุกชั้นใน skins ; คืน (V, จำนวนที่เลื่อน)
    floor: ครบ it รอบแล้วยังมีจุดลึกไม่ถึง floor (ผิว hi/mid ดันกันไปมา เช่นมุมปาก) -> ทำต่ออีกไม่เกิน more รอบ"""
    V = np.array(V, np.float64)
    moved = np.zeros(len(V), bool)
    for n_ in range(it + more):
        if n_ == it and (floor is None or min(-float(sk.query(V)[0].max()) for sk in skins) >= floor):
            break
        any_m = False
        for sk in skins:
            s, Nq = sk.query(V)
            m = s > -margin
            if m.any():
                any_m = True
                V[m] -= Nq[m] * (s[m] + margin)[:, None]
                moved |= m
        if not any_m:
            break
    return V, int(moved.sum())


def _depths(V, skins):
    """ความลึกใต้ผิวต่ำสุด (มม.) ต่อผิว + จำนวนจุดที่ลึกไม่ถึง 0"""
    out = {}
    for name, sk in skins.items():
        s, _ = sk.query(V)
        out[name] = {"min_mm": round(float(-s.max()) * 1000, 3), "outside": int((s > 0).sum())}
    return out


def _sub(V, F):
    used = np.unique(F)
    remap = -np.ones(len(V), np.int64)
    remap[used] = np.arange(len(used))
    return V[used], remap[F]


def _decimate_part(V, F, tgt):
    """ลดชิ้นเดียวให้ใกล้งบ: ชิ้นที่มีขอบเกือบเสื่อมบางชิ้นลดไม่ลงด้วย agg 7 -> ลอง agg อื่น เก็บผลที่ใกล้งบสุด (กำหนดแน่นอน)"""
    best = ME.decimate_all(V, F, tgt)
    for agg in (9, 5, 3):
        if len(best[1]) <= tgt * 1.25 or len(F) <= tgt:
            break
        V2, F2 = FS.simplify(V.astype(np.float32), F.astype(np.int32), target_reduction=1.0 - tgt / len(F), agg=agg)
        V2, F2 = np.asarray(V2, np.float64), np.asarray(F2, np.int64)
        a = np.linalg.norm(np.cross(V2[F2[:, 1]] - V2[F2[:, 0]], V2[F2[:, 2]] - V2[F2[:, 0]]), axis=1)
        V2, F2 = ME.clean_all(V2, F2[a > 1e-12], 4)
        if abs(len(F2) - tgt) < abs(len(best[1]) - tgt):
            best = (V2, F2)
    return best


def bone_layer(data, Vs, Ns, skins):
    """ชิ้นกระดูกของ skeleton.bin (ท่าผูก A) ทีละชิ้นที่ต่อกัน -> ลดตามสัดส่วน (ชิ้นเล็กไม่หาย) -> ผูกแข็งกับกระดูกของชิ้น
    -> กดส่วนที่โผล่พ้นผิวกลับเข้าใต้ผิว BONE_UNDER"""
    d = read_bin(os.path.join(data, "skeleton.bin"))
    V = d["pos"].astype(np.float64)
    F = d["idx"][:, ::-1].astype(np.int64)            # ไฟล์เก็บแบบ Godot (ตามเข็ม) -> ทวนเข็ม
    B = d["bone"].astype(np.int64)
    n = len(V)
    A = coo_matrix((np.ones(F.size), (F.ravel(), np.roll(F, 1, axis=1).ravel())), shape=(n, n))
    nc, lab = connected_components(A, directed=False)
    fl = lab[F[:, 0]]
    total = len(F)
    Vs_, Fs_, Bs = [], [], []
    off = 0
    groups = {}
    for c in range(nc):
        Vg, Fg = _sub(V, F[fl == c])
        b = int(B[F[fl == c][0, 0]])
        tgt = max(BONE_MIN, int(round(BONE_TRIS * len(Fg) / total)))
        V2, F2 = _decimate_part(Vg, Fg, tgt)
        Vs_.append(V2)
        Fs_.append(F2 + off)
        Bs.append(np.full(len(V2), b, np.int64))
        off += len(V2)
        g = groups.setdefault(rig.BONES[b], {"bone": rig.BONES[b], "parts": 0, "tris_in": 0, "tris": 0})
        g["parts"] += 1
        g["tris_in"] += int(len(Fg))
        g["tris"] += int(len(F2))
    V = np.vstack(Vs_)
    F = np.vstack(Fs_)
    B = np.concatenate(Bs)
    V, moved = _under_skin(V, Vs, Ns, BONE_UNDER)
    V, moved2 = _push_under(V, skins, BONE_PUSH)
    N = ME.vnormals(V, F)
    return V, F, N, B, [groups[k] for k in sorted(groups, key=lambda s: rig.BI[s])], moved + moved2


def pad_inset(V, Gb):
    """ร่างแบบอื่น: ชิ้น pad ดันผิวออกจากผนังตัวเท่าไร = พิกัดด้านหน้าของจุดในกรอบชิ้น (0 ที่ระนาบกลางชิ้น ถึงรัศมีหน้า
    ที่ยอด) × น้ำหนัก 1 บนผิวชิ้น -> 0 เมื่อห่างผิวชิ้นเกิน k ของชิ้น (ม.)"""
    out = np.zeros(len(V))
    for p in VR.extra_prims():
        if p.tag != "pad" or p.kind != "ellipsoid":
            continue
        M = rig.bone_xform(Gb, p.bone)
        d = np.asarray(p.eval(V.astype(np.float32), M)[0], np.float64)
        q = ((V - M[:3, 3]) @ M[:3, :3] - np.asarray(p.p["c"], float)) @ np.asarray(p.p.get("rot", np.eye(3)), float)
        w = np.clip(1.0 - np.maximum(d, 0.0) / float(p.k or 0.02), 0.0, 1.0)
        out = np.maximum(out, w * w * (3.0 - 2.0 * w) * np.clip(q[:, 2], 0.0, float(p.p["r"][2])))
    return out


def flesh_layer(work, Gb, Vs, Fs, Ns, fat, k, skins):
    """ผิวปั้นลดเหลือ FLESH_TRIS แล้วหดเข้าตามนอร์มอลเท่าความหนาไขมัน -> ผิวของกล้าม/เนื้อใต้ไขมัน ; น้ำหนักจากผิว
    คิดในกรอบผิวปั้น (Vs, Gb) แล้วคูณ k ไปกรอบของผิวที่ส่งออก ; ร่างแบบอื่น: แผนที่ไขมันบนพิกัดก่อนขยายศีรษะ + pad"""
    W = np.load(os.path.join(work, "stage_weights.npz"))["Wh4"]
    V, F = ME.decimate(Vs, Fs, FLESH_TRIS)
    N = ME.vnormals(V, F)
    if VR.CUR is None:
        T, _ = FM.maps(V, Gb)
        t = np.clip(T * fat, FAT_LO, FAT_HI)
    else:
        T, _ = FM.maps(VR.head_unwarp(V, Gb), Gb)
        t = np.clip(T * fat + pad_inset(V, Gb), FAT_LO, FAT_HI_V)
    Vi = ME.taubin(V - N * t[:, None], F, it=FLESH_SMOOTH)
    Wl = ME.transfer(Vs, V, W, k=3)                   # จากตำแหน่งบนผิว (ก่อนหด)
    # ใหม่ 0.14: เนื้อใต้ปากล่าง/คางตามกราม มุมปาก คิ้ว (แบบเดียวกับผิว hi/mid ; แนวปากแบ่งบน/ล่าง)
    import anatomy as AN
    import face as FC
    fcf = FC.features(AN.all_skin_prims())
    H = FC.head_coords(V, Gb)
    Wl = WT.add_face(Wl, H, np.sign(FC.mouth_s(H, fcf)[0]), fcf)
    Vi, moved = _under_skin(Vi * k, Vs * k, Ns, FLESH_UNDER)
    Vi, moved2 = _push_under(Vi, skins, FLESH_PUSH, floor=FLESH_MIN, more=12)
    bi, bw = WT.top4(Wl)
    return Vi, F, ME.vnormals(Vi, F), bi, bw, t * k, moved + moved2


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default=os.path.join(ROOT, "out"))
    ap.add_argument("--work", default=os.path.join(ROOT, "work"))
    args = ap.parse_args()
    data = os.path.join(args.out, "data")
    t0 = time.time()
    Gb, _ = rig.fk(rig.bind_pose())
    z = np.load(os.path.join(args.work, "stage_skin.npz"))
    Vs, Fs = z["Vs"], z["Fs"]
    Ns = ME.vnormals(Vs, Fs)
    # ผิวที่เกมวาด (ท่าผูก) ของ hi และ mid: ชั้นในต้องอยู่ใต้ทั้งสอง
    skins = {}
    for lv in ("hi", "mid"):
        b = read_bin(os.path.join(data, "body_%s.bin" % lv))
        skins[lv] = SkinDepth(b["pos"], b["idx"][:, ::-1])
    k = 1.0
    vj = os.path.join(data, "variant.json")
    if os.path.exists(vj):
        vd = json.load(open(vj))
        k = float(vd.get("k", 1.0))
        VR.use(vd.get("variant", ""))
    top = float(skins["hi"].V[:, 1].max())
    if abs(top - k * float(Vs[:, 1].max())) > 0.003:
        raise SystemExit("inner layers: the sculpt (x k %.4f) and body_hi differ in height: %.4f vs %.4f m"
                         % (k, k * float(Vs[:, 1].max()), top))
    Vb, Fb, Nb, Bb, groups, moved_b = bone_layer(data, Vs * k, Ns, list(skins.values()))
    nb = len(Vb)
    bones4 = np.zeros((nb, 4), np.int32)
    bones4[:, 0] = Bb
    w4 = np.zeros((nb, 4))
    w4[:, 0] = 1.0
    part_b = PT.part_ids(Bb)
    posed_b = None
    if True:                                   # ใหม่ 0.14: ทุกร่าง (ร่างหลักด้วย) กดกระดูกที่โผล่ในท่าของเกม
        import inner_posed as IP
        clips = json.load(open(IP.clip_path(args.out)))["clips"]
        Vb, npb, dmb = IP.push_bone(Vb, bones4.astype(np.int64), w4, part_b.astype(np.int64), data, k, clips,
                                    list(skins.values()))
        Nb = ME.vnormals(Vb, Fb)
        posed_b = {"pushed_verts": npb, "max_push_mm": round(dmb * 1000, 2)}
        print("inner bone: %d verts pushed down for the game's poses (chest front / hips, at most %.1f mm)" % (npb, dmb * 1000))
    LY.write_bin(os.path.join(data, "inner_bone.bin"), {"pos": Vb, "nrm": Nb, "bones": bones4, "weights": w4,
                                                        "part": part_b, "idx": Fb[:, ::-1]},
                 {"layer": "bone", "verts": nb, "tris": int(len(Fb)), "bones": rig.BONES, "space": "bind"})
    Vf, Ff, Nf, bi, bw, t, moved_f = flesh_layer(args.work, Gb, Vs, Fs, Ns, float(z["fat"]), k, list(skins.values()))
    part_f = PT.part_ids(bi)
    posed = None
    if True:                                   # ใหม่ 0.14: ทุกร่าง กดเนื้อที่โผล่ในท่าของเกม (+ ท่าหน้า)
        import inner_posed as IP
        clips = json.load(open(IP.clip_path(args.out)))["clips"]
        Vf, npush, dmax = IP.push_posed(Vf, Ff, bi, bw, part_f.astype(np.int64), data, k, clips, list(skins.values()),
                                        passes=3)
        # ใหม่ 0.14: จุดที่ยังโผล่เกินเกตในท่าที่ LBS ไม่สวนผิว เลื่อนต่ออีกชุดโดยไม่นับท่าที่สวน (ไม่มีจุดแบบนี้ = ผลเดิมทุกไบต์)
        bad = IP.still_out(Vf, Ff, bi, bw, part_f.astype(np.int64), data, k, clips)
        if bad.any():
            Vf, n2, d2 = IP.push_posed(Vf, Ff, bi, bw, part_f.astype(np.int64), data, k, clips, list(skins.values()),
                                       only=bad, skip_inverted=True)
            npush, dmax = npush + n2, max(dmax, d2)
            print("inner flesh: %d verts still out after the passes, pushed again without the LBS-inverted frames"
                  % int(bad.sum()))
        Nf = ME.vnormals(Vf, Ff)
        posed = {"pushed_verts": npush, "max_push_mm": round(dmax * 1000, 2)}
        print("inner flesh: %d verts pushed down for the game's poses (at most %.1f mm)" % (npush, dmax * 1000))
    LY.write_bin(os.path.join(data, "inner_flesh.bin"), {"pos": Vf, "nrm": Nf, "bones": bi, "weights": bw,
                                                         "part": part_f, "idx": Ff[:, ::-1]},
                 {"layer": "flesh", "verts": int(len(Vf)), "tris": int(len(Ff)), "bones": rig.BONES, "space": "bind"})
    used_b = sorted({rig.BONES[i] for i in np.unique(Bb)})
    used_f = sorted({rig.BONES[i] for i in np.unique(bi[bw > 0])})
    dep_b, dep_f = _depths(Vb, skins), _depths(Vf, skins)
    rep = {"k": k, "variant": VR.NAME,
           "bone": {"verts": nb, "tris": int(len(Fb)), "groups": len(groups), "bones": used_b, "parts": groups,
                    "pushed_under_skin": moved_b, "depth": dep_b,
                    "body_parts": {PT.NAMES[i]: int((part_b == i).sum()) for i in range(len(PT.NAMES))},
                    **({"posed_push": posed_b} if posed_b else {})},
           "flesh": {"verts": int(len(Vf)), "tris": int(len(Ff)), "bones": used_f, "pushed_under_skin": moved_f,
                     "depth": dep_f, "body_parts": {PT.NAMES[i]: int((part_f == i).sum()) for i in range(len(PT.NAMES))},
                     "inset_mm": {"min": round(float(t.min()) * 1000, 2), "mean": round(float(t.mean()) * 1000, 2),
                                  "max": round(float(t.max()) * 1000, 2)}, **({"posed_push": posed} if posed else {})},
           "time_s": round(time.time() - t0, 1)}
    json.dump(rep, open(os.path.join(data, "inner_layers.json"), "w"), indent=1)
    print("inner bone: %d tris %d verts (%d groups, %d verts pushed under the skin, bones %s)"
          % (len(Fb), nb, len(groups), moved_b, " ".join(used_b)))
    print("inner flesh: %d tris %d verts, inset %s mm, %d verts pushed under the skin, %.1fs"
          % (len(Ff), len(Vf), rep["flesh"]["inset_mm"], moved_f, rep["time_s"]))
    print("depth under the skin (min mm): bone %s, flesh %s"
          % ({l: dep_b[l]["min_mm"] for l in dep_b}, {l: dep_f[l]["min_mm"] for l in dep_f}))
    bad = [("bone", l) for l in dep_b if dep_b[l]["min_mm"] < BONE_MIN_D * 1000] + \
          [("flesh", l) for l in dep_f if dep_f[l]["min_mm"] < FLESH_MIN * 1000]
    if bad:
        raise SystemExit("inner layers not deep enough under the skin: %s" % bad)


if __name__ == "__main__":
    main()
