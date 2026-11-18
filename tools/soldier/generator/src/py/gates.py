# เกตตรวจผิวขั้น 1b (อ่านผลจาก out/ กับ work/ แล้วเขียน out/data/gates.json)
#   G1 ทอพอโลยี  G2 โพรง (หน้าตัด 3 แกนทุก 5 มม. + ร่องใต้ไหปลาร้า)  G3 สมมาตร  G4 ฝ่าเท้า/ความสูง
#   G5 งบสามเหลี่ยม/draw  G6 สัดส่วน  G8 แฮชเทียบอีกชุด (--compare OUTDIR2)
#   /usr/bin/python3 gates.py [--out DIR] [--work DIR] [--compare DIR2] [--step 0.005]
import argparse
import glob
import hashlib
import json
import os
import sys
import time
import numpy as np
import trimesh
from scipy.spatial import cKDTree

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import mesh as ME

ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
LEVELS = ("hi", "mid", "lo", "min")
BUDGET = {"hi": 24000, "mid": 16000, "lo": 9000, "min": 5000}
SYM_MM = {"hi": 2.0, "mid": 2.0, "lo": 3.0, "min": 3.0}


def read_bin(path):
    b = open(path, "rb").read()
    n = int.from_bytes(b[:4], "little")
    head = json.loads(b[4:4 + n])
    base = 4 + n
    out = {}
    for a in head["arrays"]:
        dt = "<f4" if a["type"] == "f32" else "<i4"
        out[a["name"]] = np.frombuffer(b, dtype=dt, count=a["count"], offset=base + a["offset"]).reshape(a["shape"])
    return out, head["meta"]


def load_lod(data, lv):
    A, meta = read_bin(os.path.join(data, "body_%s.bin" % lv))
    return A["pos"].astype(float), A["idx"][:, ::-1].astype(np.int64), meta


# ---------------- G2: วงปิดในหน้าตัด ----------------
def _inside(pt, poly):
    """จุดอยู่ในรูปหลายเหลี่ยมไหม (ยิงรังสี แบบเวกเตอร์)"""
    x, y = pt
    a, b = poly, np.roll(poly, -1, axis=0)
    c = (a[:, 1] > y) != (b[:, 1] > y)
    xi = a[:, 0] + (y - a[:, 1]) * (b[:, 0] - a[:, 0]) / (b[:, 1] - a[:, 1] + 1e-18)
    return bool(np.count_nonzero(c & (x < xi)) % 2)


def _area(p):
    return 0.5 * abs(np.dot(p[:, 0], np.roll(p[:, 1], 1)) - np.dot(p[:, 1], np.roll(p[:, 0], 1)))


def section_loops(m, axis, step, amin):
    """วงที่ถูกล้อม (ช่องอากาศในเนื้อ) ในหน้าตัดตั้งฉากแกน axis ทุก step ; คืน [(ค่าแกน, พื้นที่ ซม.², จุดกลาง 3D)]"""
    lo, hi = m.bounds
    nrm = np.zeros(3)
    nrm[axis] = 1.0
    hs = np.arange(lo[axis] + 1e-4, hi[axis], step)
    org = np.zeros(3)
    paths = m.section_multiplane(plane_origin=org, plane_normal=nrm, heights=hs)
    found = []
    for v, P in zip(hs, paths):
        if P is None:
            continue
        T = P.metadata.get("to_3D", np.eye(4))
        L = []
        for d in P.discrete:
            d = np.asarray(d)
            if len(d) < 4:
                continue
            L.append((_area(d), d))
        L.sort(key=lambda t: -t[0])
        for i, (a, p) in enumerate(L):
            for a2, p2 in L[:i]:
                if a2 > a and _inside(p[0], p2):
                    # ช่องอากาศ = วงในวงที่ใหญ่กว่า (ชั้นคู่ = เกาะเนื้อในช่องอากาศ นับเฉพาะชั้นคี่)
                    depth = sum(1 for a3, p3 in L[:i] if a3 > a and _inside(p[0], p3))
                    if depth % 2 == 1 and a * 1e4 >= amin:
                        c2 = p.mean(0)
                        c3 = (T @ np.array([c2[0], c2[1], 0.0, 1.0]))[:3]
                        found.append((float(v), round(a * 1e4, 3), c3))
                    break
    return found


def region(c):
    x, y, z = c
    if y > 1.53:
        return "head (eyes/ears/nose/mouth)"
    if abs(x) < 0.035 and z < -0.05 and 0.95 < y < 1.50:
        return "spine furrow"
    if abs(x) < 0.03 and 0.98 < y < 1.12 and z > 0.06:
        return "navel"
    side = "L" if x > 0 else "R"
    if abs(x) > 0.40 and y > 0.70:
        return "hand " + side
    if y < 0.12:
        return "foot/ankle " + side
    if 0.40 < y < 0.65 and abs(x) > 0.04:
        return "knee " + side
    if 1.30 < y < 1.52:
        return "shoulder/armpit/clavicle " + side
    if 0.75 < y < 0.98:
        return "hip/groin " + side
    return "other " + side


def cluster(found, step):
    """รวมวงที่ต่อเนื่องกันข้ามหน้าตัด -> ลักษณะเดียว ; ลึก ≈ จำนวนหน้าตัด × step"""
    feats = []
    for v, a, c in sorted(found, key=lambda t: t[0]):
        best = None
        for f in feats:
            if abs(v - f["last"]) <= step * 1.5 + 1e-9 and np.linalg.norm(c - f["c"]) < 0.025:
                best = f
                break
        if best is None:
            feats.append({"first": v, "last": v, "n": 1, "amax": a, "c": c, "cs": [c]})
        else:
            best["last"] = v
            best["n"] += 1
            best["amax"] = max(best["amax"], a)
            best["cs"].append(c)
            best["c"] = c
    out = []
    for f in feats:
        cm = np.mean(f["cs"], axis=0)
        out.append({"centre": [round(float(t), 3) for t in cm], "slices": f["n"], "extent_mm": round(f["n"] * step * 1000, 1),
                    "max_area_cm2": f["amax"], "region": region(cm)})
    return out


def g2_sections(V, F, step, amin=0.05):
    m = trimesh.Trimesh(V, F, process=False)
    res = {}
    for ax, nm in ((1, "horizontal"), (2, "frontal"), (0, "sagittal")):
        t0 = time.time()
        f = section_loops(m, ax, step, amin)
        res[nm] = {"loops": len(f), "features": cluster(f, step), "s": round(time.time() - t0, 1)}
    return res


def clavicle_profile(V, F):
    """ร่องใต้ไหปลาร้า (สคริปต์ผู้ตรวจ): z หน้าสุดตามความสูง ในหน้าตัดข้าง x คงที่ ; ร่องลึก = ห่างจากขอบบนช่วง 6 ซม."""
    m = trimesh.Trimesh(V, F, process=False)
    ys = np.arange(1.30, 1.505, 0.005)
    out = {}
    for x in (0.08, 0.11, 0.14, -0.08, -0.11, -0.14):
        s = m.section(plane_origin=[x, 0, 0], plane_normal=[1.0, 0, 0])
        zz = np.full(len(ys), -np.inf)
        for ent in s.discrete:
            P = np.asarray(ent)
            for a, b in zip(P[:-1], P[1:]):
                lo_, hi_ = min(a[1], b[1]), max(a[1], b[1])
                sel = (ys >= lo_) & (ys <= hi_) & (hi_ > lo_)
                if not sel.any():
                    continue
                t = (ys[sel] - a[1]) / (b[1] - a[1])
                zz[sel] = np.maximum(zz[sel], a[2] * (1 - t) + b[2] * t)
        env = np.array([np.max(zz[max(0, i - 6):i + 7]) for i in range(len(zz))])
        dip = (env - zz) * 1000
        # ใต้ไหปลาร้าเท่านั้น (y ≤ 1.465): เหนือไหปลาร้าผิวเลี้ยวขึ้นบ่า ไม่ใช่ร่อง
        sub = ys <= 1.465
        i = int(np.argmax(np.where(sub, dip, -1)))
        j = int(np.argmax(dip))
        out["x=%+.2f" % x] = {"dip_mm": round(float(dip[i]), 2), "at_y": round(float(ys[i]), 3),
                              "full_range_dip_mm": round(float(dip[j]), 2), "full_range_at_y": round(float(ys[j]), 3)}
    return out


# ---------------- G3/G4 ----------------
def sym(V, F):
    c = V[F].mean(1)
    nl, nr = int((c[:, 0] > 1e-6).sum()), int((c[:, 0] < -1e-6).sum())
    d, _ = cKDTree(V).query(V * np.array([-1.0, 1.0, 1.0]))
    return {"tris_left": nl, "tris_right": nr, "side_diff_pct": round(100.0 * abs(nl - nr) / max(nl, nr), 3),
            "mirror_p95_mm": round(float(np.percentile(d, 95) * 1000), 3), "mirror_max_mm": round(float(d.max() * 1000), 3)}


def soles(V):
    foot = V[(V[:, 1] < 0.02) & (np.abs(V[:, 0]) > 0.04)]
    low = foot[foot[:, 1] < 0.0015]
    return {"min_y_mm": round(float(V[:, 1].min() * 1000), 3), "sole_verts": int(len(low)),
            "height_mm": round(float(V[:, 1].max() * 1000), 2)}


def sha(path):
    return hashlib.sha256(open(path, "rb").read()).hexdigest()


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default=os.path.join(ROOT, "out"))
    ap.add_argument("--work", default=os.path.join(ROOT, "work"))
    ap.add_argument("--compare", default="")
    ap.add_argument("--step", type=float, default=0.005)
    ap.add_argument("--skip-g2", action="store_true")
    args = ap.parse_args()
    data = os.path.join(args.out, "data")
    G = {}
    # G1
    z = np.load(os.path.join(args.work, "stage_skin.npz"))
    Vs, Fs = z["Vs"].astype(float), z["Fs"].astype(np.int64)
    topo = {"sculpt": ME.topology(Vs, Fs)}
    lods = {}
    for lv in LEVELS:
        V, F, meta = load_lod(data, lv)
        lods[lv] = (V, F, meta)
        topo[lv] = ME.topology(V, F)
    ok1 = all(t["shells"] == 1 and t["boundary_edges"] == 0 and t["nonmanifold_edges"] == 0 and t["nonmanifold_verts"] == 0
              and t["euler"] == 2 for t in topo.values())
    G["G1"] = {"pass": ok1, "values": topo}
    print("G1", "PASS" if ok1 else "FAIL", {k: (v["faces"], v["shells"], v["euler"]) for k, v in topo.items()}, flush=True)
    # G2
    if not args.skip_g2:
        g2 = {"sculpt": g2_sections(Vs, Fs, args.step), "hi": g2_sections(lods["hi"][0], lods["hi"][1], args.step)}
        prof = {"sculpt": clavicle_profile(Vs, Fs), "hi": clavicle_profile(lods["hi"][0], lods["hi"][1])}
        nloops = {k: sum(v[a]["loops"] for a in v) for k, v in g2.items()}
        deep = []
        for k, v in g2.items():
            for a in v:
                for f in v[a]["features"]:
                    if f["extent_mm"] > 10.0 + 1e-6 and not f["region"].startswith("head"):
                        deep.append((k, a, f))
        slit = max(p["dip_mm"] for q in prof.values() for p in q.values())
        G["G2"] = {"pass_strict": all(n == 0 for n in nloops.values()) and slit <= 20.0,
                   "pass_depth": len(deep) == 0 and slit <= 20.0,
                   "loops": nloops, "deep_body_features": deep, "clavicle_slit_max_mm": slit,
                   "clavicle_profile": prof, "sections": g2,
                   "rule": "strict = no enclosed loop at all; depth = every enclosed loop outside the head spans at most "
                           "10 mm along the scan axis (an open dimple such as the navel or the spinal furrow, not a cave)"}
        print("G2 loops", nloops, "deep", len(deep), "slit", slit, flush=True)
    # G3 / G4 / G5
    g3, g4, g5 = {}, {}, {}
    for lv in LEVELS:
        V, F, meta = lods[lv]
        s = sym(V, F)
        s["pass"] = s["side_diff_pct"] <= 5.0 and s["mirror_p95_mm"] <= SYM_MM[lv] and s["mirror_max_mm"] <= SYM_MM[lv]
        g3[lv] = s
        g4[lv] = soles(V)
        g5[lv] = {"tris": int(len(F)), "budget": BUDGET[lv], "pass_tris": len(F) <= BUDGET[lv]}
    hs = [g4[lv]["height_mm"] for lv in LEVELS]
    G["G3"] = {"pass": all(v["pass"] for v in g3.values()), "values": g3}
    G["G4"] = {"pass": all(abs(v["min_y_mm"]) <= 1.0 for v in g4.values()) and (max(hs) - min(hs)) <= 3.0,
               "height_spread_mm": round(max(hs) - min(hs), 3), "values": g4}
    rr = {}
    for fn in glob.glob(os.path.join(args.out, "renders", "raw", "render_report*.json")):
        rr.update(json.load(open(fn)))
    bud = rr.get("budgets", {})
    for lv in LEVELS:
        b = bud.get(lv, {})
        g5[lv].update({"surfaces": b.get("surfaces"), "draws": b.get("draws")})
    G["G5"] = {"pass": all(v["pass_tris"] and (v["surfaces"] in (None, 1)) and (v["draws"] in (None, 1)) for v in g5.values()),
               "godot_report": bool(bud), "values": g5}
    print("G3", G["G3"]["pass"], "G4", G["G4"]["pass"], "G5", G["G5"]["pass"], flush=True)
    # G6
    ap_ = os.path.join(data, "anthropometry.json")
    if os.path.exists(ap_):
        an = json.load(open(ap_))
        G["G6"] = {"pass": all(v.get("ok") for v in an.values() if isinstance(v, dict) and "ok" in v), "values": an}
        print("G6", G["G6"]["pass"], flush=True)
    # G8
    if args.compare:
        rows = {}
        for lv in LEVELS + ("hilbs",):
            a = os.path.join(data, "body_%s.bin" % lv)
            b = os.path.join(args.compare, "data", "body_%s.bin" % lv)
            if os.path.exists(a) and os.path.exists(b):
                rows[lv] = {"a": sha(a)[:16], "b": sha(b)[:16], "same": sha(a) == sha(b)}
        G["G8"] = {"pass": bool(rows) and all(r["same"] for r in rows.values()), "values": rows}
        print("G8", G["G8"]["pass"], rows, flush=True)
    json.dump(G, open(os.path.join(data, "gates.json"), "w"), indent=1, default=lambda o: o.tolist() if hasattr(o, "tolist") else str(o))
    print("gates written")


if __name__ == "__main__":
    main()
