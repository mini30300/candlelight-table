# น้ำหนักผิว (skin weights) จากโครงสร้างใต้ผิว: จุดผิวแต่ละจุดดูว่าอยู่เหนืออะไร (แกนลึก/ปุ่มกระดูก/กล้ามมัดไหน ตรงไหนของมัด)
#   แกนลึกและปุ่มกระดูก = แข็งตามกระดูกของมัน ; กล้าม = ไล่น้ำหนักตามตำแหน่งบนเส้นใย (จุดเกาะต้น -> กระดูกที่พาด -> จุดเกาะปลาย)
#   แล้วกระจายบนผิว (diffusion) ให้รอยต่อข้อนุ่ม -> แบ่งให้กระดูกช่วย -> เหลือ 4 กระดูก/จุด
import numpy as np
import rig
import muscles as MU
from mesh import adjacency

NB = len(rig.BONES)
BI = rig.BI
SOFT_T = 0.004


def _profile_rigid(p, param):
    if p.weights is None:
        out = np.zeros((len(param), NB))
        out[:, BI[p.bone]] = 1.0
        return out
    if isinstance(p.weights, dict):
        out = np.zeros((len(param), NB))
        for b, w in p.weights.items():
            out[:, BI[b]] = w
        return out
    ys = np.array([y for y, _ in p.weights])
    out = np.zeros((len(param), NB))
    j = np.clip(np.searchsorted(ys, param) - 1, 0, len(ys) - 2)
    f = np.clip((param - ys[j]) / (ys[j + 1] - ys[j]), 0, 1)
    for k in range(len(ys)):
        for b, w in p.weights[k][1].items():
            sel = j == k
            out[sel, BI[b]] += (1 - f[sel]) * w
            sel = j + 1 == k
            out[sel, BI[b]] += f[sel] * w
    return out


def _profile_muscle(mu, t, fib):
    knots = mu["w"]
    ts = np.array([k[0] for k in knots])
    out = np.zeros((len(t), NB))
    j = np.clip(np.searchsorted(ts, t) - 1, 0, len(ts) - 2)
    f = np.clip((t - ts[j]) / np.maximum(ts[j + 1] - ts[j], 1e-6), 0, 1)
    obone = np.array([BI[fb["obone"]] for fb in mu["fibres"]])[fib]
    for k in range(len(ts)):
        b = knots[k][1]
        col = obone if b == "@o" else np.full(len(t), BI[b])
        for sel, wv in ((j == k, 1 - f), (j + 1 == k, f)):
            idx = np.nonzero(sel)[0]
            np.add.at(out, (idx, col[idx]), wv[idx])
    return out


def structure_weights(V, G, prims, mus):
    n = len(V)
    recs = []                                        # (idx, d', W)
    dmin = np.full(n, 1e9)
    mats = {}
    for p in prims:
        if p.neg:
            continue
        M = mats.setdefault(p.bone, rig.bone_xform(G, p.bone))
        lo, hi = p.bbox(M)
        m = np.all((V >= lo - 0.07) & (V <= hi + 0.07), axis=1)
        idx = np.nonzero(m)[0]
        if len(idx) == 0:
            continue
        d, param = p.eval(V[idx].astype(np.float32), M)
        dd = d - p.outset
        recs.append((idx, dd, ("p", p, param)))
        dmin[idx] = np.minimum(dmin[idx], dd)
    for mu in mus:
        d, t, fib = MU.muscle_eval_points(mu, V)
        idx = np.nonzero(d < 0.9)[0]
        if len(idx) == 0:
            continue
        dd = d[idx] - mu["outset"]
        recs.append((idx, dd, ("m", mu, (t[idx], fib[idx]))))
        dmin[idx] = np.minimum(dmin[idx], dd)
    W = np.zeros((n, NB))
    S = np.zeros(n)
    owner = np.full(n, -1)
    best = np.full(n, 1e9)
    for r, (idx, dd, (kind, obj, param)) in enumerate(recs):
        e = np.exp(-(dd - dmin[idx]) / SOFT_T)
        keep = e > 1e-3
        if not np.any(keep):
            continue
        idx, e = idx[keep], e[keep]
        if kind == "p":
            prof = _profile_rigid(obj, param[keep])
        else:
            prof = _profile_muscle(obj, param[0][keep], param[1][keep])
        W[idx] += e[:, None] * prof
        S[idx] += e
        better = dd[keep] < best[idx]
        best[idx[better]] = dd[keep][better]
        owner[idx[better]] = r
    bad = S <= 0
    if np.any(bad):
        raise RuntimeError("vertices without structure: %d" % bad.sum())
    W /= S[:, None]
    names = [(rec[2][1].name if rec[2][0] == "p" else rec[2][1]["name"]) for rec in recs]
    return W, owner, names


def diffuse(W, F, it=50, alpha=0.5):
    A = adjacency(F, len(W))
    for _ in range(it):
        W = (1 - alpha) * W + alpha * (A @ W)
    return W


def _pair_half(W, a, b, h, lam, side=None):
    ia, ib, ih = BI[a], BI[b], BI[h]
    s = W[:, ia] + W[:, ib]
    f = np.where(s > 1e-9, W[:, ib] / np.maximum(s, 1e-9), 0)
    wh = lam * s * 4 * f * (1 - f)
    if side is not None:
        wh = wh * side
    W[:, ia] -= 0.5 * wh
    W[:, ib] -= 0.5 * wh
    W[:, ih] += wh


def add_helpers(W, V, G):
    W = W.copy()
    def ss(x, a, b):
        u = np.clip((x - a) / (b - a), 0, 1)
        return u * u * (3 - 2 * u)

    def local(b):
        M = np.linalg.inv(rig.bone_xform(G, b))
        return V @ M[:3, :3].T + M[:3, 3] - rig.JOINT_I[b]
    for sd in ("L", "R"):
        # กระดูกครึ่งมุมเฉพาะด้านนูนของข้อ (ศอก = หลัง, เข่า = หน้า, สะโพก = ก้น) ; ด้านพับใช้การผสมปกติ
        el = local("elbow" + sd)
        _pair_half(W, "shoulder" + sd, "elbow" + sd, "elbow_half" + sd, 0.5, 0.2 + 0.8 * ss(-el[:, 2], -0.015, 0.012))
        kn = local("knee" + sd)
        _pair_half(W, "hip" + sd, "knee" + sd, "knee_half" + sd, 0.5, 0.2 + 0.8 * ss(kn[:, 2], -0.02, 0.015))
        hp = local("hip" + sd)
        _pair_half(W, "pelvis", "hip" + sd, "hip_half" + sd, 0.4, 0.25 + 0.75 * ss(-hp[:, 2], -0.03, 0.03))
        # บิดต้นแขน: ส่วนบนของต้นแขนรับการบิดครึ่งเดียว
        M = np.linalg.inv(rig.bone_xform(G, "shoulder" + sd))
        P = V @ M[:3, :3].T + M[:3, 3]
        a = rig.JOINT_I["shoulder" + sd][1] - P[:, 1]
        u = np.clip((a - 0.04) / 0.16, 0, 1)
        ftw = 1 - u * u * (3 - 2 * u)
        ish, itw = BI["shoulder" + sd], BI["uparm_twist" + sd]
        mv = W[:, ish] * ftw
        W[:, ish] -= mv
        W[:, itw] += mv
    return np.maximum(W, 0)


FOLD = {"elbow_half": ("shoulder", "elbow"), "knee_half": ("hip", "knee"), "hip_half": (None, "hip"),
        "uparm_twist": ("shoulder", None), "clavicle": (None, None)}


def fold_helpers(W):
    """ระดับ min: ไม่มีกระดูกช่วย (และกระดูกหน้า) -> คืนน้ำหนักให้กระดูกหลัก"""
    W = fold_face(W)
    for sd in ("L", "R"):
        for h, (a, b) in FOLD.items():
            ih = BI[h + sd]
            w = W[:, ih].copy()
            W[:, ih] = 0
            if h == "elbow_half":
                W[:, BI["shoulder" + sd]] += 0.5 * w
                W[:, BI["elbow" + sd]] += 0.5 * w
            elif h == "knee_half":
                W[:, BI["hip" + sd]] += 0.5 * w
                W[:, BI["knee" + sd]] += 0.5 * w
            elif h == "hip_half":
                W[:, BI["pelvis"]] += 0.5 * w
                W[:, BI["hip" + sd]] += 0.5 * w
            elif h == "uparm_twist":
                W[:, BI["shoulder" + sd]] += w
            elif h == "clavicle":
                W[:, BI["chest"]] += w
    return W


def add_face(W, H, side, f):
    """กระดูกหน้า (hi/mid และชั้นเนื้อของแผล): แบ่งจากน้ำหนักของ head เท่านั้น (คอ/ลำตัวไม่ถูกแตะ)
    H = พิกัดศีรษะท่า I ; side = +1 เหนือแนวปาก / -1 ใต้ (แถวล่างของรอยต่อ) / 0 มุมปาก ; f = face.features"""
    import face as FC
    W = W.copy()
    ih = BI["head"]
    wh = W[:, ih].copy()
    fr = FC.weights(H, side, f)
    lips = fr["head_lipL"] + fr["head_lipR"]
    rest = 1.0 - lips
    parts = {"head_lipL": fr["head_lipL"], "head_lipR": fr["head_lipR"], "head_jaw": rest * fr["head_jaw"]}
    rest = rest - parts["head_jaw"]
    parts["head_browL"] = rest * fr["head_browL"]
    parts["head_browR"] = rest * fr["head_browR"]
    for b, fv in parts.items():
        W[:, BI[b]] += wh * fv
        W[:, ih] -= wh * fv
    return np.maximum(W, 0)


def fold_face(W):
    """ระดับ lo/min: ไม่มีกระดูกหน้า -> คืนน้ำหนักให้ head"""
    W = W.copy()
    for b in rig.FACE:
        W[:, BI["head"]] += W[:, BI[b]]
        W[:, BI[b]] = 0
    return W


def top4(W, minw=0.01):
    idx = np.argsort(-W, axis=1)[:, :4]
    w = np.take_along_axis(W, idx, 1)
    w[w < minw] = 0
    s = w.sum(1, keepdims=True)
    w = w / np.maximum(s, 1e-9)
    return idx.astype(np.int32), w


def dense_from_top4(idx, w):
    W = np.zeros((len(idx), NB))
    np.put_along_axis(W, idx, w, 1)
    return W


def lbs(V, W, G_from, G_to):
    """ผิว LBS: จุดในท่า G_from -> ท่า G_to ; คืน (ตำแหน่ง, เมทริกซ์ 3x3 ผสมต่อจุด)"""
    out = np.zeros_like(V)
    Mix = np.zeros((len(V), 3, 3))
    Vh = np.c_[V, np.ones(len(V))]
    for b in rig.BONES:
        j = BI[b]
        wb = W[:, j]
        sel = wb > 0
        if not np.any(sel):
            continue
        M = G_to[b] @ np.linalg.inv(G_from[b])
        out[sel] += wb[sel, None] * (Vh[sel] @ M[:3].T)
        Mix[sel] += wb[sel, None, None] * M[:3, :3]
    return out, Mix
