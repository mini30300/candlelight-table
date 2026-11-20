# ชุดของทหาร (ใหม่ 0.14 ข้อ 4): ทะเบียนชุด + ชนิดวัสดุ/จานสีใน CUSTOM0 + เกต + ตัวสร้าง
#   build.py --outfit <ชื่อ> (ต้องมีผลสร้างตัวเปล่าใน --out/--work แล้ว: body_<ระดับ>.bin, stage_skin.npz, stage_weights.npz)
#   -> out/data/outfit_<ชื่อ>_<ระดับ>.bin (เมชเดียวต่อระดับแทนผิว = 1 draw ; โครง 38 กระดูกเดิม ; min 23 กระดูก) + outfit_<ชื่อ>.json
#   ไม่ใส่ --outfit = กางเกงฝึก (ตัวเปล่า) เหมือนเดิมทุกไบต์ (ไฟล์นี้ไม่ถูกเรียก)
#   CUSTOM0 = (ชนิดวัสดุ CLS, เขตจานสี REG, ความเป็นเนื้อ 0..1, ส่วนร่างกาย 0..5) ; ผิวที่โผล่ = ชนิด 0 เขต 0 (ผม = เขต 7)
#   เกต: ชิ้นปิด (เชื่อมจุดที่ตำแหน่งเดียวกันก่อนนับ) งบ ≤ งบเกม - 3 % สมมาตรซ้าย-ขวา พื้นรองเท้าที่ y = 0 ± 1.5 มม.
#        + ท่าของเกม (outfit_posed.py): ผิวตัวเปล่าไม่โผล่พ้นผ้า ชิ้นอุปกรณ์ไม่จมในผ้า
import json
import os
import time
import numpy as np
import rig
import mesh as ME
import variants as VR
import layers as LY

LEVELS = ("hi", "mid", "lo", "min")
BUDGET = {"hi": 24000, "mid": 16000, "lo": 9000, "min": 5000}     # = SoldierFigure.BUDGET
MARGIN = 0.03                                                       # ชุดใช้ได้ไม่เกินงบ - 3 %
SOLE_MM = 1.5
ROUNDS = 6            # เกตท่าไม่ผ่าน: เพิ่มผ้าหลวม/ผ้าบางเฉพาะที่แล้วสร้างใหม่ได้อีก 5 รอบ
SYM_MM = 0.5

# ชนิดวัสดุ (CUSTOM0.x): เชดเดอร์ผิวให้แสงตามชนิด (soldier_skin*.gdshader: mat_gloss)
CLS = {"skin": 0, "cloth": 1, "leather": 2, "webbing": 3, "sole": 4, "plate": 5, "undersuit": 6, "hair": 7, "metal": 8}
# เขตจานสี (CUSTOM0.y): ข้อ 5 เปลี่ยนสีตามเขตได้ ; 8.. สำรองให้เกราะ
REG = {"skin": 0, "shirt": 1, "trousers": 2, "webbing": 3, "boots": 4, "sole": 5, "hardware": 6, "hair": 7,
       "plate": 8, "trim": 9, "undersuit": 10, "visor": 11}
# สีเริ่มของแต่ละเขต (sRGB ก่อนคูณ AO/รอยพับ)
PALETTE = {
    "uniform": {"shirt": (0.405, 0.415, 0.285), "trousers": (0.305, 0.335, 0.212), "webbing": (0.200, 0.215, 0.140),
                "boots": (0.205, 0.140, 0.092), "sole": (0.075, 0.070, 0.066), "hardware": (0.240, 0.235, 0.220)},
}
OUTFITS = {
    "uniform": {"label": "ชุดสนาม", "label_en": "Field uniform", "module": "garments"},
}


def log(*a):
    print("[outfit]", *a, flush=True)


def limit(lv):
    return int(BUDGET[lv] * (1.0 - MARGIN))


def load_ctx(out, work):
    """ข้อมูลของร่างจากผลสร้างตัวเปล่า (กรอบ 1.78 ม.)"""
    import anatomy as A
    import face as FC
    from inner_layers import read_bin
    z = np.load(os.path.join(work, "stage_skin.npz"))
    w = np.load(os.path.join(work, "stage_weights.npz"))
    KV = VR.scale()
    prims = A.all_skin_prims()
    Gb, _ = rig.fk(rig.bind_pose())
    Vs, Fs = z["Vs"].astype(np.float64), z["Fs"].astype(np.int64)
    Ns = ME.vnormals(Vs, Fs)
    if np.einsum('ij,ij->i', Vs[Fs[:, 0]], np.cross(Vs[Fs[:, 1]], Vs[Fs[:, 2]])).sum() < 0:
        Ns = -Ns                                          # ผิวปั้นเก็บหน้าหันเข้า: นอร์มอลชี้ออกเสมอ
    ctx = {"Vs": Vs, "Fs": Fs, "Ns": Ns, "ao": z["ao"].astype(np.float64), "Wh4": w["Wh4"],
           "Wm4": w["Wm4"], "Gb": Gb, "prims": prims, "FCF": FC.features(prims), "KV": KV, "bare": {}}
    for lv in LEVELS:
        d = read_bin(os.path.join(out, "data", "body_%s.bin" % lv))
        d["V"] = d["pos"].astype(np.float64) / KV
        d["F"] = d["idx"][:, ::-1].astype(np.int64)          # ไฟล์เก็บแบบ Godot (ตามเข็ม) -> ทวนเข็ม
        ctx["bare"][lv] = d
    return ctx


# ---------------- เกต ----------------

def weld(V, F, tol=1e-7):
    """เชื่อมจุดที่ตำแหน่งเดียวกัน (ขอบผ้าใช้จุดซ้ำเพื่อสีคม) -> F ของจุดตัวแทน"""
    from scipy.spatial import cKDTree
    pairs = cKDTree(V).query_pairs(tol, output_type="ndarray")
    rep = np.arange(len(V))
    for a, b in sorted(map(tuple, np.sort(pairs, axis=1))):
        ra, rb = rep[a], rep[b]
        while rep[ra] != ra:
            ra = rep[ra]
        while rep[rb] != rb:
            rb = rep[rb]
        rep[max(ra, rb)] = min(ra, rb)
    for i in range(len(rep)):
        r = i
        while rep[r] != r:
            r = rep[r]
        rep[i] = r
    return rep[F]


def gate_closed(V, F):
    """ทุกชิ้นปิดสนิท: ไม่มีขอบเปิด ไม่มีขอบ/จุดไม่แมนิโฟลด์ ; คืน (ผ่าน, รายชิ้น)"""
    from scipy.sparse import coo_matrix
    from scipy.sparse.csgraph import connected_components
    Fw = weld(V, F)
    used = np.unique(Fw)
    n = len(V)
    E = np.sort(np.vstack([Fw[:, [0, 1]], Fw[:, [1, 2]], Fw[:, [2, 0]]]), axis=1)
    A = coo_matrix((np.ones(len(E)), (E[:, 0], E[:, 1])), shape=(n, n))
    _, lab = connected_components(A, directed=False)
    pieces = []
    ok = True
    for c in np.unique(lab[used]):
        fm = lab[Fw[:, 0]] == c
        Fc = Fw[fm]
        Ec = np.sort(np.vstack([Fc[:, [0, 1]], Fc[:, [1, 2]], Fc[:, [2, 0]]]), axis=1)
        u, cnt = np.unique(Ec, axis=0, return_counts=True)
        nv = len(np.unique(Fc))
        t = {"tris": int(len(Fc)), "boundary_edges": int((cnt == 1).sum()), "nonmanifold_edges": int((cnt > 2).sum()),
             "euler": int(nv - len(u) + len(Fc))}
        t["genus"] = (2 - t["euler"]) // 2
        good = t["boundary_edges"] == 0 and t["nonmanifold_edges"] == 0 and t["euler"] in (2, 0)
        ok &= good
        pieces.append(t)
    pieces.sort(key=lambda t: -t["tris"])
    return bool(ok), pieces


def gate_sym(Vo, F):
    from scipy.spatial import cKDTree
    c = Vo[F].mean(1)
    nl, nr = int((c[:, 0] > 0).sum()), int((c[:, 0] < 0).sum())
    d, _ = cKDTree(Vo).query(Vo * np.array([-1.0, 1.0, 1.0]))
    r = {"tris_left": nl, "tris_right": nr, "side_diff_pct": round(100.0 * abs(nl - nr) / max(nl, nr), 3),
         "mirror_max_mm": round(float(d.max() * 1000), 4)}
    r["pass"] = bool(r["mirror_max_mm"] <= SYM_MM and r["side_diff_pct"] <= 1.0)
    return r


def level_gates(lv, m, KV):
    Vo = m["V"] * KV
    closed, pieces = gate_closed(m["V"], m["F"])
    g = {"closed": {"pass": closed, "pieces": pieces},
         "budget": {"tris": int(len(m["F"])), "limit": limit(lv), "pass": bool(len(m["F"]) <= limit(lv))},
         "symmetry": gate_sym(Vo, m["F"])}
    ymin = float(Vo[:, 1].min())
    g["soles"] = {"min_y_mm": round(ymin * 1000, 3), "pass": bool(abs(ymin) * 1000 <= SOLE_MM)}
    cus = m["cus"]
    g["custom0"] = {"classes": sorted(int(c) for c in np.unique(np.round(cus[:, 0]))),
                    "regions": sorted(int(c) for c in np.unique(np.round(cus[:, 1]))),
                    "pass": bool(np.all(np.isin(np.round(cus[:, 0]), list(CLS.values())))
                                 and np.all(np.isin(np.round(cus[:, 1]), list(REG.values()))))}
    if lv == "min":
        g["min_bones"] = {"pass": bool(np.all(np.isin(m["bones"][m["weights"] > 0], [rig.BI[b] for b in rig.MAIN])))}
    return g


def write_level(path, m, lv, KV, name):
    import face as FC
    arrays = {"pos": m["V"] * KV, "nrm": m["N"], "col": np.c_[m["C"], np.ones(len(m["V"]))], "cus": m["cus"],
              "bones": m["bones"], "weights": m["weights"], "idx": m["F"][:, ::-1]}
    if lv in FC.CUSTOM_LV:
        arrays["face"] = m["face"]
    meta = {"level": lv, "outfit": name, "verts": int(len(m["V"])), "tris": int(len(m["F"])), "shapes": [],
            "bones": rig.BONES, "parts": m["info"]}
    LY.write_bin(path, arrays, meta)


STRIP = (("walk", 0.25), ("jog", 0.25), ("run", 0.30), ("aim", 0.5), ("punch_0", 0.40), ("swing_1", 0.45),
         ("reload", 0.5), ("hit_front", 0.30), ("die_back", 1.0))


def strip_poses(out, path):
    """ท่าตัวอย่างจากคลิปของทหาร (รูปแบบ poses.json) สำหรับภาพแถวท่าของชุด (vrender.gd STRIP)"""
    import inner_posed as IP
    clips = json.load(open(IP.clip_path(out)))["clips"]
    KV = VR.scale()
    pj = {}
    for cn, f in STRIP:
        if cn not in clips:
            continue
        c = clips[cn]
        fr = min(int(round(f * (int(c["frames"]) - 1))), int(c["frames"]) - 1)
        p = IP.clip_pose(c, fr)
        pj[cn] = {"local": {b: [float(x) for x in p["local"][b]] for b in rig.MAIN},
                  "pelvis": [float(x) for x in p["pelvis_pos"] * KV]}
    json.dump(pj, open(path, "w"), indent=1)
    return pj


def _cluster(pts, r=0.02):
    """จุดที่โผล่ (ท่า I x y z, มม.) -> ตัวแทนกลุ่มละจุด (ลึกสุดก่อน) ห่างกันเกิน r"""
    out = []
    for p in sorted(pts, key=lambda p: -p[3]):
        if all(np.linalg.norm(np.subtract(p[:3], q[:3])) >= r for q in out):
            out.append(p)
    return out


def build(name, out, work):
    """ชุด name ทุกระดับ + เกต ; เกตไม่ผ่าน = หยุด (SystemExit) หลังเขียนรายงาน"""
    import importlib
    if name not in OUTFITS:
        raise SystemExit("unknown outfit %r (outfits.py: %s)" % (name, ", ".join(OUTFITS)))
    t0 = time.time()
    spec = OUTFITS[name]
    GM = importlib.import_module(spec["module"])
    ctx = load_ctx(out, work)
    data = os.path.join(out, "data")
    rep = {"outfit": name, "label": spec["label"], "label_en": spec["label_en"], "variant": VR.NAME or "base",
           "k": ctx["KV"], "levels": {}, "classes": CLS, "regions": REG, "palette": PALETTE.get(name, {})}
    import outfit_posed as OP
    GM.EXTRA_BLOBS[:], GM.EXTRA_THIN[:] = [], []
    for rnd in range(ROUNDS):
        built, fails, rep["levels"] = {}, [], {}
        ctx.pop("_dense", None)
        for lv in LEVELS:
            m = GM.build_level(ctx, lv, name)
            g = level_gates(lv, m, ctx["KV"])
            built[lv] = m
            write_level(os.path.join(data, "outfit_%s_%s.bin" % (name, lv)), m, lv, ctx["KV"], name)
            rep["levels"][lv] = {"verts": int(len(m["V"])), "tris": int(len(m["F"])), "parts": m["info"], "gates": g}
            bad = [k for k, v in g.items() if not v["pass"]]
            fails += ["%s %s" % (lv, k) for k in bad]
            log("%-3s %6d tris %6d verts  %s  pieces %s  sym %.3f mm  sole %.2f mm" % (
                lv, len(m["F"]), len(m["V"]), "PASS" if not bad else "FAIL " + ",".join(bad),
                [(p["tris"], p["genus"]) for p in g["closed"]["pieces"]], g["symmetry"]["mirror_max_mm"],
                g["soles"]["min_y_mm"]))
        pz = OP.run(ctx, built, out)
        rep["posed"] = pz
        if pz["pass"] or fails or rnd == ROUNDS - 1:
            break
        # จุดที่ผิวยังโผล่: รอบแรกเพิ่มผ้าหลวมเฉพาะที่ ; จุดเดิมที่ยังโผล่ = ผ้าบางแนบผิว (สำเนาผิว) ; ทุกค่ากำหนดแน่นอนจากเกต
        for q in _cluster(pz.get("points", [])):
            c = tuple(round(v, 4) for v in q[:3])
            near = [b for b in GM.EXTRA_BLOBS if np.linalg.norm(np.subtract(b[0], c)) < 0.03]
            thin = [np.linalg.norm(np.subtract(t[0], c)) for t in list(GM.THIN) + GM.EXTRA_THIN]
            if near:
                GM.EXTRA_BLOBS.remove(near[0])
                GM.EXTRA_THIN.append((near[0][0], (0.03, 0.03, 0.03)))
            elif min(thin) < 0.045:                  # ข้างโซนผ้าบาง (บริเวณที่ LBS หมุนชั้นผ้า) = ผ้าบางเลย
                if min(thin) >= 0.015:
                    GM.EXTRA_THIN.append((c, (0.03, 0.03, 0.03)))
            else:
                GM.EXTRA_BLOBS.append((c, (0.035, 0.035, 0.035), 0.005))
        log("round %d: posed gate failed (%s) -> extra ease %d, thin %d" % (
            rnd + 1, "; ".join(pz["fails"]), len(GM.EXTRA_BLOBS), len(GM.EXTRA_THIN)))
    rep["extra_ease"] = [list(b[0]) for b in GM.EXTRA_BLOBS]
    rep["extra_thin"] = [list(t[0]) for t in GM.EXTRA_THIN]
    if not pz["pass"]:
        fails.append("posed: " + "; ".join(pz["fails"]))
    rep["pass"] = not fails
    rep["fails"] = fails
    strip_poses(out, os.path.join(data, "outfit_strip.json"))
    rep["time_s"] = round(time.time() - t0, 1)
    json.dump(rep, open(os.path.join(data, "outfit_%s.json" % name), "w"), indent=1, ensure_ascii=False)
    log("%s %s in %.0fs" % (name, "PASS" if not fails else "FAIL: " + "; ".join(fails), rep["time_s"]))
    if fails:
        raise SystemExit("outfit %s: gates failed: %s" % (name, "; ".join(fails)))
    return rep
