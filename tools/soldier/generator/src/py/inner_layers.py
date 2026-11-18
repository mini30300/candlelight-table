# ชั้นในของทหาร (บาดแผลเห็นเนื้อและกระดูก: เกมระดับ hi/mid) จากผลของ build.py ไม่ปั้นใหม่ ไม่มีการสุ่ม
#   out/data/inner_bone.bin  = กระดูกจริง (skeleton.bin ท่าผูก) ลดเหลือ ~5k สามเหลี่ยม ผูกแข็งกับกระดูกของแต่ละชิ้น
#   out/data/inner_flesh.bin = ผิวปั้น (work/stage_skin.npz) ลดเหลือ ~7k แล้วหดเข้าเท่าความหนาไขมัน (fatmap)
#                              น้ำหนักย้ายจากผิว (work/stage_weights.npz: Wh4 ชุดเดียวกับ hi/mid)
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

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
BONE_TRIS = 5000          # งบชั้นกระดูก (สามเหลี่ยม)
BONE_MIN = 12             # ขั้นต่ำต่อชิ้น (ชิ้นเล็กไม่หาย)
FLESH_TRIS = 7000         # งบชั้นเนื้อ
FAT_LO, FAT_HI = 0.003, 0.016   # ระยะหดเข้าจากผิว (ม.) = ความหนาไขมันที่จุดนั้น จำกัดช่วง
FLESH_SMOOTH = 4          # เกลี่ย Taubin หลังหด (กันรอยพับในซอก)
BONE_UNDER = 0.004        # กระดูกอยู่ใต้ผิวอย่างน้อยเท่านี้ (ม.): ชั้นภาพเดิมมีขอบสะบักโผล่หลังผิว ~3 ซม. -> กดกลับเข้าใต้ผิว
FLESH_UNDER = 0.002       # เนื้ออยู่ใต้ผิวอย่างน้อยเท่านี้ (ซอกนิ้ว ข้อเท้า)


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


def bone_layer(data, Vs, Ns):
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
    N = ME.vnormals(V, F)
    return V, F, N, B, [groups[k] for k in sorted(groups, key=lambda s: rig.BI[s])], moved


def flesh_layer(work, Gb, Vs, Fs, Ns, fat):
    """ผิวปั้นลดเหลือ FLESH_TRIS แล้วหดเข้าตามนอร์มอลเท่าความหนาไขมัน -> ผิวของกล้าม/เนื้อใต้ไขมัน ; น้ำหนักจากผิว"""
    W = np.load(os.path.join(work, "stage_weights.npz"))["Wh4"]
    V, F = ME.decimate(Vs, Fs, FLESH_TRIS)
    N = ME.vnormals(V, F)
    T, _ = FM.maps(V, Gb)
    t = np.clip(T * fat, FAT_LO, FAT_HI)
    Vi = ME.taubin(V - N * t[:, None], F, it=FLESH_SMOOTH)
    Vi, moved = _under_skin(Vi, Vs, Ns, FLESH_UNDER)
    Wl = ME.transfer(Vs, V, W, k=3)                   # จากตำแหน่งบนผิว (ก่อนหด)
    bi, bw = WT.top4(Wl)
    return Vi, F, ME.vnormals(Vi, F), bi, bw, t, moved


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
    Vb, Fb, Nb, Bb, groups, moved_b = bone_layer(data, Vs, Ns)
    nb = len(Vb)
    bones4 = np.zeros((nb, 4), np.int32)
    bones4[:, 0] = Bb
    w4 = np.zeros((nb, 4))
    w4[:, 0] = 1.0
    LY.write_bin(os.path.join(data, "inner_bone.bin"), {"pos": Vb, "nrm": Nb, "bones": bones4, "weights": w4,
                                                        "idx": Fb[:, ::-1]},
                 {"layer": "bone", "verts": nb, "tris": int(len(Fb)), "bones": rig.BONES, "space": "bind"})
    Vf, Ff, Nf, bi, bw, t, moved_f = flesh_layer(args.work, Gb, Vs, Fs, Ns, float(z["fat"]))
    LY.write_bin(os.path.join(data, "inner_flesh.bin"), {"pos": Vf, "nrm": Nf, "bones": bi, "weights": bw,
                                                         "idx": Ff[:, ::-1]},
                 {"layer": "flesh", "verts": int(len(Vf)), "tris": int(len(Ff)), "bones": rig.BONES, "space": "bind"})
    used_b = sorted({rig.BONES[i] for i in np.unique(Bb)})
    used_f = sorted({rig.BONES[i] for i in np.unique(bi[bw > 0])})
    rep = {"bone": {"verts": nb, "tris": int(len(Fb)), "groups": len(groups), "bones": used_b, "parts": groups,
                    "pushed_under_skin": moved_b},
           "flesh": {"verts": int(len(Vf)), "tris": int(len(Ff)), "bones": used_f, "pushed_under_skin": moved_f,
                     "inset_mm": {"min": round(float(t.min()) * 1000, 2), "mean": round(float(t.mean()) * 1000, 2),
                                  "max": round(float(t.max()) * 1000, 2)}},
           "time_s": round(time.time() - t0, 1)}
    json.dump(rep, open(os.path.join(data, "inner_layers.json"), "w"), indent=1)
    print("inner bone: %d tris %d verts (%d groups, %d verts pushed under the skin, bones %s)"
          % (len(Fb), nb, len(groups), moved_b, " ".join(used_b)))
    print("inner flesh: %d tris %d verts, inset %s mm, %d verts pushed under the skin, %.1fs"
          % (len(Ff), len(Vf), rep["flesh"]["inset_mm"], moved_f, rep["time_s"]))


if __name__ == "__main__":
    main()
