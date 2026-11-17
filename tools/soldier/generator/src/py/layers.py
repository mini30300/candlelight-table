# เมชชั้นโครงกระดูกและชั้นกล้ามเนื้อ (ไว้ทำภาพ) + ตัวเขียนไฟล์ไบนารีให้ Godot อ่าน
import json
import numpy as np
from skimage.measure import marching_cubes
import rig
import anatomy as A
import muscles as MU
import field as FD
from sdfk import Grid
from mesh import clean, clean_all, decimate_all, vnormals

BONE_COL = np.array([0.88, 0.85, 0.76])
CART_COL = np.array([0.74, 0.80, 0.84])


def _mc_local(g):
    if g.F.min() >= 0:
        return None
    V, F, _, _ = marching_cubes(g.F, 0.0, spacing=(g.h, g.h, g.h), allow_degenerate=False)
    return clean_all(V + g.lo, F.astype(np.int64))


def bone_meshes(h=0.002, budget=90000):
    """กระดูกจริงทุกชิ้น (ท่า I) -> เมชเดียว ผูกแข็งกับกระดูกโครงเกม ; คืน V, F, colour, bone index"""
    prims = A.bones()
    groups = {}
    for p in prims:
        groups.setdefault((p.bone, p.tag), []).append(p)
    Vs, Fs, Cs, Bs = [], [], [], []
    off = 0
    raw = []
    for (bone, tag), ps in groups.items():
        lo = np.min([p._bb[0] for p in ps], 0) - 0.006
        hi = np.max([p._bb[1] for p in ps], 0) + 0.006
        g = Grid(lo, hi, h)
        sl = tuple(slice(0, n) for n in g.n)
        P = g.points(sl)
        F = np.full(len(P), 1.0, np.float32)
        for p in ps:
            if p.neg:
                continue
            d, _ = p.eval_local(P)
            F = FD._smin(F, d, 0.0025) if tag == "bone" else np.minimum(F, d)
        for p in ps:
            if p.neg:
                d, _ = p.eval_local(P)
                F = np.maximum(F, -d)
        g.F = F.reshape(g.n).astype(np.float32)
        r = _mc_local(g)
        if r is None:
            continue
        raw.append((bone, tag, r[0], r[1]))
    total = sum(len(f) for _, _, _, f in raw)
    for bone, tag, V, F in raw:
        tgt = max(60, int(budget * len(F) / total))
        V, F = decimate_all(V, F, tgt)
        Vs.append(V)
        Fs.append(F + off)
        off += len(V)
        Cs.append(np.tile(BONE_COL if tag == "bone" else CART_COL, (len(V), 1)))
        Bs.append(np.full(len(V), rig.BI[bone], np.int32))
    return np.vstack(Vs), np.vstack(Fs), np.vstack(Cs), np.concatenate(Bs)


def pose_points(V, bidx, G):
    """จุดท่า I ที่ผูกแข็งกับกระดูก -> ท่า G"""
    out = np.zeros_like(V)
    for b in np.unique(bidx):
        m = bidx == b
        M = rig.bone_xform(G, rig.BONES[b])
        out[m] = V[m] @ M[:3, :3].T + M[:3, 3]
    return out


def muscle_meshes(mus, h=0.0025, budget=110000):
    """กล้ามทุกมัดในท่าที่สร้างไว้ -> เมชเดียว สีตามมัด (ท้องกล้ามแดง เอ็นขาว)"""
    raw = []
    for mi, mu in enumerate(mus):
        g = FD.muscle_field(mu, h)
        r = _mc_local(g)
        if r is None:
            continue
        V, F = r
        # สี: t ของเส้นใยใกล้สุด -> เอ็น (ปลาย) ขาวอมฟ้า ท้องกล้ามแดงเข้ม/อ่อนสลับตามมัด
        d, t, fib = MU.muscle_eval_points(mu, V.astype(np.float32))
        t0, t1 = mu["tendon"]
        ten = np.clip(np.maximum((t0 + 0.03 - t) / 0.06, (t - (1 - t1 - 0.03)) / 0.06), 0, 1)
        shade = 0.92 + 0.16 * ((mi // 2) % 3) / 2
        belly = np.array([0.66, 0.17, 0.15]) * shade
        tendon = np.array([0.86, 0.84, 0.80])
        C = belly[None] * (1 - ten[:, None]) + tendon[None] * ten[:, None]
        raw.append((V, F, C))
    total = sum(len(f) for _, f, _ in raw)
    Vs, Fs, Cs = [], [], []
    off = 0
    from mesh import transfer
    for V, F, C in raw:
        tgt = max(80, int(budget * len(F) / total))
        V2, F2 = decimate_all(V, F, tgt)
        C2 = transfer(V, V2, C, k=1)
        Vs.append(V2)
        Fs.append(F2 + off)
        Cs.append(C2)
        off += len(V2)
    return np.vstack(Vs), np.vstack(Fs), np.vstack(Cs)


# ---------------- ไฟล์ไบนารี: [ยาวหัว 4 ไบต์][หัว JSON][ข้อมูลดิบ little-endian] ----------------

def write_bin(path, arrays, meta=None):
    head = {"arrays": [], "meta": meta or {}}
    blobs = []
    off = 0
    for name, a in arrays.items():
        a = np.ascontiguousarray(a)
        if a.dtype.kind == "f":
            a = a.astype("<f4")
            dt = "f32"
        else:
            a = a.astype("<i4")
            dt = "i32"
        b = a.tobytes()
        head["arrays"].append({"name": name, "type": dt, "count": int(a.size), "shape": list(a.shape), "offset": off})
        blobs.append(b)
        off += len(b)
    hj = json.dumps(head).encode()
    with open(path, "wb") as f:
        f.write(len(hj).to_bytes(4, "little"))
        f.write(hj)
        for b in blobs:
            f.write(b)
    return path
