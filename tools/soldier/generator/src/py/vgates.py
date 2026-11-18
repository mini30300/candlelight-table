# เกตเพิ่มของร่างหลากหลาย (รอบปรับ) — เรียกจาก gates.py --variant ; อ่านผลจาก out/data กับ work/
#   G9  แก้ม/กรามเรียบ: มุมนอร์มอลต่างจากเฉลี่ยวงข้าง (hi ≤ 1.5° , mid ≤ 2.0°)
#   G10 ตาระดับ lo เปิดสองโทน: สีจุดยอดตามแนวตา สว่าง-มืด-สว่าง ต่างกัน ≥ 0.15 (ความสว่าง sRGB)
#   G11 ขอบผ้า: เส้น 0.5 ของสีผ้าที่จุดยอด ห่างเส้นขอบจริง p95 ≤ 5 มม. (hi/mid) / 12 มม. (lo/min)
#   G12 อกหญิง: ยอดอก 0.71-0.72 H ; ใต้อกไม่มีขั้นลึกกว่า 1.5 ซม. ต่อ 2 % H
import json
import os
import numpy as np
import mesh as ME
import rig
import variants as VR


def _bin(path):
    b = open(path, "rb").read()
    n = int.from_bytes(b[:4], "little")
    head = json.loads(b[4:4 + n])
    out = {}
    for a in head["arrays"]:
        dt = "<f4" if a["type"] == "f32" else "<i4"
        out[a["name"]] = np.frombuffer(b, dtype=dt, count=a["count"], offset=4 + n + a["offset"]).reshape(a["shape"])
    return out


def _luma(c):
    return 0.2126 * c[..., 0] + 0.7152 * c[..., 1] + 0.0722 * c[..., 2]


def g9_lowface(data, G, k):
    """มุมระหว่างนอร์มอลจุดยอดกับเฉลี่ยนอร์มอลของจุดรอบข้าง (องศา) ในบริเวณแก้ม/กราม เทียบหน้าผาก"""
    out = {}
    for lv, lim in (("hi", 1.5), ("mid", 2.0)):
        A = _bin(os.path.join(data, "body_%s.bin" % lv))
        V = A["pos"].astype(float) / k
        N = A["nrm"].astype(float)
        F = A["idx"][:, ::-1].astype(np.int64)
        H = ME.head_local(VR.head_unwarp(V, G), G)
        low = VR.lowface_w(H) > 0.5
        Q = np.c_[np.abs(H[:, 0]), H[:, 1], H[:, 2]]
        fh = np.exp(-np.sum(((Q - np.array([0, 1.715, 0.085])) / np.array([0.040, 0.020, 0.030])) ** 2, 1)) > 0.5
        Nm = ME.adjacency(F, len(V)) @ N
        Nm /= np.maximum(np.linalg.norm(Nm, axis=1, keepdims=True), 1e-9)
        ang = np.degrees(np.arccos(np.clip((N * Nm).sum(1), -1, 1)))
        out[lv] = {"lowface_deg": round(float(ang[low].mean()), 3), "forehead_deg": round(float(ang[fh].mean()), 3),
                   "n": int(low.sum()), "limit": lim, "pass": bool(ang[low].mean() <= lim)}
    return {"pass": all(v["pass"] for v in out.values()), "values": out}


def _bary_colour(V, F, C, P, d=None):
    """มองจากหน้า (แกน -z): จุด P (x, y) -> สีที่ผิวหน้าสุด (ผสมแบบ barycentric ในระนาบ xy)"""
    T = V[F]
    lo, hi = P[:, :2].min(0) - 0.02, P[:, :2].max(0) + 0.02
    keep = np.all((T[:, :, :2].max(1) >= lo) & (T[:, :, :2].min(1) <= hi), axis=1) & (T[:, :, 2].mean(1) > 0)
    T, Fk = T[keep], F[keep]
    a, b, c = T[:, 0, :2], T[:, 1, :2], T[:, 2, :2]
    den = (b[:, 1] - c[:, 1]) * (a[:, 0] - c[:, 0]) + (c[:, 0] - b[:, 0]) * (a[:, 1] - c[:, 1])
    out = np.full((len(P), 3), np.nan)
    for i, q in enumerate(P[:, :2]):
        w0 = ((b[:, 1] - c[:, 1]) * (q[0] - c[:, 0]) + (c[:, 0] - b[:, 0]) * (q[1] - c[:, 1])) / den
        w1 = ((c[:, 1] - a[:, 1]) * (q[0] - c[:, 0]) + (a[:, 0] - c[:, 0]) * (q[1] - c[:, 1])) / den
        w2 = 1 - w0 - w1
        m = (w0 >= -1e-9) & (w1 >= -1e-9) & (w2 >= -1e-9)
        if not m.any():
            continue
        W = np.stack([w0[m], w1[m], w2[m]], 1)
        z = (T[m][:, :, 2] * W).sum(1)
        j = int(np.argmax(z))
        out[i] = (C[Fk[m][j]] * W[j][:, None]).sum(0)
    return out


def g10_lo_eyes(data, G, k, prims):
    """ตาระดับ lo: แนวนอนผ่านกลางช่องตา (มองจากหน้า) ; ความสว่างหัว/หางตาเทียบกลางตา"""
    A = _bin(os.path.join(data, "body_lo.bin"))
    V = A["pos"].astype(float) / k
    F = A["idx"][:, ::-1].astype(np.int64)
    C = A["col"][:, :3].astype(float)
    pm = {p.name: p for p in prims}
    eo = pm["eye_open_L"].p
    out = {}
    for side, sx in (("L", 1.0), ("R", -1.0)):
        c = np.array([sx * eo["c"][0], eo["c"][1], eo["c"][2]])
        cw = (rig.bone_xform(G, "head") @ np.r_[c, 1.0])[:3]
        cw = VR.head_pts(cw, G)[0]
        hw = eo["hw"] * VR.head_scale()
        u = np.linspace(-1.1, 1.1, 45)
        P = np.c_[cw[0] + sx * u * hw, np.full(len(u), cw[1]), np.full(len(u), cw[2] + 0.08)]
        col = _bary_colour(V, F, C, P, np.array([0, 0, -1.0]))
        L = _luma(col)
        cen = np.nanmin(L[np.abs(u) < 0.30])
        inn = np.nanmax(L[(u > -1.0) & (u < -0.40)])
        outr = np.nanmax(L[(u > 0.40) & (u < 1.0)])
        con = float(min(inn, outr) - cen)
        out[side] = {"inner": round(float(inn), 3), "centre": round(float(cen), 3), "outer": round(float(outr), 3),
                     "contrast": round(con, 3), "pass": bool(con >= 0.15)}
    return {"pass": all(v["pass"] for v in out.values()), "values": out}


def _iso_points(V, F, f, xmax=0.30):
    """จุดบนเส้น f = 0 (ตัดขอบเชิงเส้น + จุดยอดที่ f = 0 พอดี)"""
    E = np.unique(np.sort(np.vstack([F[:, [0, 1]], F[:, [1, 2]], F[:, [2, 0]]]), axis=1), axis=0)
    a, b = E[:, 0], E[:, 1]
    cr = (f[a] * f[b] < 0) & (np.abs(V[a, 0]) < xmax)
    t = f[a][cr] / (f[a][cr] - f[b][cr])
    P = V[a[cr]] + t[:, None] * (V[b[cr]] - V[a[cr]])
    return np.vstack([P, V[np.abs(f) < 1e-9]])


def g11_garments(work, G):
    """เส้น 0.5 ของน้ำหนักผ้าที่จุดยอดของระดับ (เส้นตรงในสามเหลี่ยม) เทียบเส้นขอบจริง (เส้น 0 ของขอบผ้าบนผิวปั้นละเอียด)
    ระยะเป็นมม. (ระยะเรขาคณิตถึงจุดใกล้สุดบนเส้นจริง) ; ชายเสื้อใต้ขอบกางเกงไม่นับ (มองไม่เห็น)"""
    from scipy.spatial import cKDTree
    z = np.load(os.path.join(work, "stage_skin.npz"))
    Vs, Fs = z["Vs"], z["Fs"]
    refs = {"shorts": _iso_points(Vs, Fs, VR.shorts_sd(Vs))}
    if VR.CUR.get("top"):
        R = _iso_points(Vs, Fs, VR.top_sd(Vs, G))
        refs["top"] = R[R[:, 1] > ME.SHORTS_TOP + 0.010]
    trees = {k: cKDTree(v) for k, v in refs.items() if len(v)}
    out = {}
    for lv, lim in (("hi", 5.0), ("mid", 5.0), ("lo", 12.0), ("min", 12.0)):
        p = os.path.join(work, "garm_%s.npz" % lv)
        if not os.path.exists(p):
            continue
        g = np.load(p)
        V, F = g["V"], g["F"]
        errs = []
        for nm, m in (("shorts", g["ms"]), ("top", g["mt"])):
            if len(m) != len(V) or nm not in trees:
                continue
            P = _iso_points(V, F, m - 0.5)
            if nm == "top":
                P = P[P[:, 1] > ME.SHORTS_TOP + 0.010]
            if len(P):
                errs.append(trees[nm].query(P)[0] * 1000.0)
        e = np.concatenate(errs) if errs else np.zeros(1)
        out[lv] = {"p95_mm": round(float(np.percentile(e, 95)), 2), "max_mm": round(float(e.max()), 2), "n": int(len(e)),
                   "limit_mm": lim, "pass": bool(np.percentile(e, 95) <= lim and e.max() <= 4 * lim)}   # มุมคอ-สายบ่าโค้งได้ ≤ 1 ขอบ
    return {"pass": bool(out) and all(v["pass"] for v in out.values()), "values": out}


def front_profile(V, x0=0.080, y0=1.16, y1=1.42, dy=0.002, wx=0.006):
    """ผิวหน้าสุด z(y) ที่ |x| = x0 (กรอบฐาน)"""
    ys = np.arange(y0, y1 + 1e-9, dy)
    ax = np.abs(V[:, 0])
    sel = (np.abs(ax - x0) < wx) & (V[:, 2] > 0)
    zs = np.full(len(ys), np.nan)
    for i, y in enumerate(ys):
        m = sel & (np.abs(V[:, 1] - y) < dy)
        if m.any():
            zs[i] = V[m, 2].max()
    ok = ~np.isnan(zs)
    return ys, np.interp(ys, ys[ok], zs[ok])


def g12_bust(work):
    """ยอดอก (จุดหน้าสุดที่ |x| 8 ซม.) 0.71-0.72 H ; ใต้อก: ขั้นต่อ 2 % H ≤ 1.5 ซม. ; ลาดบน (3 ซม. เหนือยอด) รายงาน"""
    z = np.load(os.path.join(work, "stage_skin.npz"))
    V = z["Vs"]
    ys, zs = front_profile(V)
    m = (ys > 1.22) & (ys < 1.36)
    ia = np.nonzero(m)[0][np.argmax(zs[m])]
    ya, za = ys[ia], zs[ia]
    H = VR.BASE_H
    win = 0.02 * H
    steps = []
    for y in ys[(ys <= ya) & (ys >= ya - 0.10)]:
        steps.append(float(np.interp(y, ys, zs) - np.interp(y - win, ys, zs)))
    up = float(za - np.interp(ya + 0.03, ys, zs))
    hrel = float(ya / H)
    ok = (0.71 <= hrel <= 0.72) and max(steps) <= 0.015
    return {"pass": bool(ok), "apex_rel_H": round(hrel, 4), "apex_y_base": round(float(ya), 4),
            "max_step_cm_per_2pctH": round(100 * max(steps), 2), "upper_drop_cm_3cm": round(100 * up, 2)}


def run(out_dir, work_dir, G, k, prims):
    data = os.path.join(out_dir, "data")
    R = {"G9": g9_lowface(data, G, k), "G10": g10_lo_eyes(data, G, k, prims), "G11": g11_garments(work_dir, G)}
    if VR.CUR.get("sex") == "f":
        R["G12"] = g12_bust(work_dir)
    return R
