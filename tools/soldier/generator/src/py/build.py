# สร้างทหารขั้นที่ 1 ทั้งชุด (กำหนดแน่นอน ไม่มีสุ่ม): โครงกระดูก -> กล้ามเนื้อ -> ผิว -> น้ำหนัก -> ท่าแก้ -> ไฟล์ให้ Godot
#   /usr/bin/python3 build.py [--out DIR] [--from STAGE]
import argparse
import hashlib
import json
import os
import time
import numpy as np
import rig
import anatomy as A
import muscles as MU
import field as FD
import mesh as ME
import weights as WT
import correctives as CR
import layers as LY

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
CLIPS = os.path.join(ROOT, "ref", "clips.json")
H_SKIN = 0.003
SEED = 20261117          # ไม่มีส่วนสุ่มในขั้นนี้ ; ใส่ไว้ให้ทุก RNG ในอนาคตใช้ค่าเดียวกัน
np.random.seed(SEED)


def log(*a):
    print(time.strftime("%H:%M:%S"), *a, flush=True)


def clip_pose(name, frame):
    d = json.load(open(CLIPS))
    c = d["clips"][name]
    p = rig.ident_pose()
    for b in rig.MAIN:
        p["local"][b] = np.array(c["q"][b][frame], float)
    p["pelvis_pos"] = np.array(c["t"]["pelvis"][frame], float) * rig.S
    return p


def test_poses():
    P = {"bind": rig.bind_pose(), "ipose": rig.ident_pose(), "idle": clip_pose("idle", 0),
         "rifle": clip_pose("fire", 8)}
    # งอศอก 120° (แขนห้อยข้างตัว)
    p = clip_pose("idle", 0)
    p["local"]["shoulderL"] = rig.qaxis([0, 0, 1], 9)
    p["local"]["elbowL"] = rig.qaxis([1, 0, 0], -120)
    p["local"]["shoulderR"] = rig.qaxis([0, 0, 1], -9)
    p["local"]["elbowR"] = rig.qaxis([1, 0, 0], -120)
    P["elbow120"] = p
    # งอเข่า 120° (สะโพกงอ 30° ยืนขาเดียว)
    p = clip_pose("idle", 0)
    p["local"]["hipL"] = rig.qaxis([1, 0, 0], -30)
    p["local"]["kneeL"] = rig.qaxis([1, 0, 0], 120)
    p["local"]["ankleL"] = rig.qaxis([1, 0, 0], 20)
    P["knee120"] = p
    # ยกแขนเหนือศีรษะ (ซ้าย 170° ขวา 165° ไปหน้าเล็กน้อย)
    p = clip_pose("idle", 0)
    p["local"]["shoulderL"] = rig.qaxis([0, 0, 1], 170)
    p["local"]["elbowL"] = rig.qaxis([1, 0, 0], -10)
    p["local"]["shoulderR"] = rig.qmul(rig.qaxis([1, 0, 0], -20), rig.qaxis([0, 0, 1], -165))
    p["local"]["elbowR"] = rig.qaxis([1, 0, 0], -10)
    P["overhead"] = p
    P["squat"] = squat_pose()
    return P


def squat_pose(ph=100.0, pk=120.0):
    p = rig.ident_pose()
    L = p["local"]
    pa = pk - ph                                  # ข้อเท้ากระดกขึ้นให้ฝ่าเท้าราบ
    for sd, sx in (("L", 1), ("R", -1)):
        L["hip" + sd] = rig.qmul(rig.qaxis([0, 1, 0], -sx * 12), rig.qmul(rig.qaxis([0, 0, 1], sx * 8), rig.qaxis([1, 0, 0], -ph)))
        L["knee" + sd] = rig.qaxis([1, 0, 0], pk)
        L["ankle" + sd] = rig.qmul(rig.qaxis([1, 0, 0], -pa), rig.qaxis([0, 0, 1], -sx * 8))
        L["shoulder" + sd] = rig.qmul(rig.qaxis([1, 0, 0], -75), rig.qaxis([0, 0, 1], sx * 12))
        L["elbow" + sd] = rig.qaxis([1, 0, 0], -25)
    L["spine"] = rig.qaxis([1, 0, 0], 28)
    L["chest"] = rig.qaxis([1, 0, 0], 8)
    L["neck"] = rig.qaxis([1, 0, 0], -22)
    L["head"] = rig.qaxis([1, 0, 0], -8)
    G, _ = rig.fk(p, helpers=False)
    # เลื่อนเชิงกรานให้ส้นและปลายเท้าแตะพื้น (y = 0) ตรงที่เดิม
    dy = 0.0 - min(G["heelL"][1, 3], G["toeL"][1, 3])
    dz = 0.045 - 0.5 * (G["heelL"][2, 3] + G["toeL"][2, 3])
    p["pelvis_pos"] = p["pelvis_pos"] + np.array([0, dy, dz])
    return p


def detail_spots(Gb):
    """บริเวณที่ให้สามเหลี่ยมมากกว่าส่วนอื่นตอนลดความละเอียด: หน้า (×2.6) มือ (×2.0)"""
    spots = [(np.array([0.0, 1.655, 0.035]), 0.13, 2.6)]
    for sd in ("L", "R"):
        sx = 1.0 if sd == "L" else -1.0
        hc = (rig.bone_xform(Gb, "wrist" + sd) @ np.array([sx * 0.20, 0.80, 0.0, 1.0]))[:3]
        spots.append((hc, 0.085, 2.0))
    return spots


def h(a):
    return hashlib.sha256(np.ascontiguousarray(a).tobytes()).hexdigest()[:16]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default=os.path.join(ROOT, "out"))
    ap.add_argument("--work", default=os.path.join(ROOT, "work"))
    ap.add_argument("--from", dest="start", default="skin")
    ap.add_argument("--layers", type=int, default=1)
    args = ap.parse_args()
    OUT = args.out
    DATA = os.path.join(OUT, "data")
    os.makedirs(DATA, exist_ok=True)
    os.makedirs(args.work, exist_ok=True)
    stages = ["skin", "weights", "correctives", "export", "layers"]
    si = stages.index(args.start)
    T = {}
    t_all = time.time()
    prims = A.all_skin_prims()
    MU.init_lengths(prims)
    Gb, Lb = rig.fk(rig.bind_pose())
    mus_b = MU.build(Gb, prims)
    cache = os.path.join(args.work, "stage_skin.npz")
    # ---------------- 1) ผิว ----------------
    if si <= 0:
        t0 = time.time()
        g = FD.skin_field(Gb, prims, mus_b, h=H_SKIN)
        FD.smooth_skin(g, Gb)
        T["field_s"] = time.time() - t0
        t0 = time.time()
        V, F = ME.mc_mesh(g)
        raw_tris = len(F)
        V = ME.taubin(V, F, 6)
        Vs, Fs = ME.decimate_weighted(V, F, ME.SCULPT_TRIS, detail_spots(Gb))
        Ns = ME.vnormals(Vs, Fs)
        rgb, flesh, ao = ME.colours(Vs, Ns, g, Gb, Fs)
        T["mesh_s"] = time.time() - t0
        log("skin: raw %d tris -> sculpt %d tris / %d verts" % (raw_tris, len(Fs), len(Vs)))
        np.savez_compressed(cache, Vs=Vs, Fs=Fs, rgb=rgb, flesh=flesh, ao=ao, raw_tris=raw_tris,
                            glo=g.lo, gh=g.h, T=json.dumps(T))
        np.save(os.path.join(args.work, "field_F.npy"), g.F)
        del g
    z = np.load(cache)
    Vs, Fs, rgb, flesh = z["Vs"], z["Fs"], z["rgb"], z["flesh"]
    T.update(json.loads(str(z["T"])))
    raw_tris = int(z["raw_tris"])
    # ---------------- 2) น้ำหนัก ----------------
    cw = os.path.join(args.work, "stage_weights.npz")
    if si <= 1:
        t0 = time.time()
        W0, owner, onames = WT.structure_weights(Vs, Gb, prims, mus_b)
        W1 = WT.diffuse(W0, Fs, it=50)
        Wh = WT.add_helpers(W1, Vs, Gb)
        i4, w4 = WT.top4(Wh)
        Wh4 = WT.dense_from_top4(i4, w4)
        Wm = WT.fold_helpers(Wh4)
        im, wm = WT.top4(Wm)
        Wm4 = WT.dense_from_top4(im, wm)
        T["weights_s"] = time.time() - t0
        log("weights in %.1fs" % T["weights_s"])
        np.savez_compressed(cw, Wh4=Wh4, Wm4=Wm4, owner=owner, onames=np.array(onames), T=json.dumps(T))
    z = np.load(cw)
    Wh4, Wm4 = z["Wh4"], z["Wm4"]
    T.update(json.loads(str(z["T"])))
    # ---------------- 3) ท่าแก้ ----------------
    cc = os.path.join(args.work, "stage_corr.npz")
    if si <= 2:
        t0 = time.time()
        D, cstats = CR.compute(Vs, Fs, Wh4, prims, Gb)
        T["correctives_s"] = time.time() - t0
        # ประเมินท่าระหว่างกลาง (ไม่ใช่ท่าหลัก) ว่าท่าแก้ช่วยจริงไหม
        t0 = time.time()
        evals = {}
        tests = {
            "elbow_60": ("elbowL", {"elbowL": rig.qaxis([1, 0, 0], -60)}, 0.17),
            "elbow_100": ("elbowL", {"elbowL": rig.qaxis([1, 0, 0], -100)}, 0.17),
            "knee_70": ("kneeL", {"kneeL": rig.qaxis([1, 0, 0], 70)}, 0.19),
            "knee_120": ("kneeL", {"kneeL": rig.qaxis([1, 0, 0], 120)}, 0.19),
            "arm_down_10": ("shoulderL", {"shoulderL": rig.qaxis([0, 0, 1], 10)}, 0.25),
            "arm_front_60": ("shoulderL", {"shoulderL": rig.qaxis([1, 0, 0], -60)}, 0.25),
            "arm_up_120": ("shoulderL", {"shoulderL": rig.qaxis([0, 0, 1], 120)}, 0.26),
            "hip_flex_60": ("hipL", {"hipL": rig.qmul(rig.qaxis([0, 0, 1], 6), rig.qaxis([1, 0, 0], -60))}, 0.26),
        }
        for nm, (joint, loc, box) in tests.items():
            p = rig.bind_pose()
            p["local"].update(loc)
            evals[nm] = CR.evaluate(Vs, Wh4, Wm4, D, prims, Gb, p, joint, box)
            log("eval %-14s %s" % (nm, {k: v for k, v in evals[nm].items() if k != "driver"}))
        T["eval_s"] = time.time() - t0
        np.savez_compressed(cc, **{k: v for k, v in D.items()}, cstats=json.dumps(cstats), evals=json.dumps(evals),
                            T=json.dumps(T))
    z = np.load(cc)
    D = {k: z[k] for k in CR.SHAPES}
    cstats = json.loads(str(z["cstats"]))
    evals = json.loads(str(z["evals"]))
    T.update(json.loads(str(z["T"])))
    # ---------------- 4) ระดับรายละเอียด + ไฟล์ Godot ----------------
    hashes = {}
    lods = {}
    if si <= 3:
        t0 = time.time()
        Ns = ME.vnormals(Vs, Fs)
        spots = detail_spots(Gb)
        for lv, tris in ME.LOD_TRIS.items():
            V, F = ME.decimate_weighted(Vs, Fs, tris, spots)
            Ng = ME.vnormals(V, F)
            N = ME.transfer_normals(Vs, Ns, V, Ng)          # นอร์มอลจากผิวละเอียด: แสงเงาเรียบกว่าเรขาคณิตหยาบ
            C = ME.transfer(Vs, V, rgb, k=3)
            fl = ME.transfer(Vs, V, flesh, k=3)
            src_w = Wm4 if lv == "min" else Wh4
            Wl = ME.transfer(Vs, V, src_w, k=3)
            bi, bw = WT.top4(Wl)
            arrays = {"pos": V, "nrm": N, "col": np.c_[C, np.ones(len(V))],
                      "cus": np.c_[np.zeros(len(V)), np.zeros(len(V)), fl, np.zeros(len(V))],
                      "bones": bi, "weights": bw, "idx": F[:, ::-1]}          # Godot: หน้าตามเข็มนาฬิกา
            shapes = []
            if lv in ("hi", "mid"):
                for sname in CR.SHAPES:
                    dl = ME.transfer(Vs, V, D[sname], k=3)
                    Vt = V + dl
                    arrays["bs_pos_" + sname] = Vt
                    Nt = N + (ME.vnormals(Vt, F) - Ng)
                    arrays["bs_nrm_" + sname] = Nt / np.maximum(np.linalg.norm(Nt, axis=1, keepdims=True), 1e-9)
                    shapes.append(sname)
            meta = {"level": lv, "verts": len(V), "tris": len(F), "shapes": shapes, "bones": rig.BONES}
            LY.write_bin(os.path.join(DATA, "body_%s.bin" % lv), arrays, meta)
            lods[lv] = {"verts": int(len(V)), "tris": int(len(F)), "blend_shapes": len(shapes),
                        "bones_used": int(len(np.unique(bi[bw > 0])))}
            hashes["body_" + lv] = h(np.c_[V.astype(np.float32), bw.astype(np.float32)]) + "/" + h(F.astype(np.int32))
            log("lod %-3s %6d tris %6d verts shapes %d" % (lv, len(F), len(V), len(shapes)))
            if lv == "hi":
                # เทียบก่อน/หลัง: เรขาคณิตเดียวกับ hi แต่ใช้น้ำหนักแบบ min (23 กระดูก ไม่มีกระดูกช่วย ไม่มีท่าแก้)
                Wl2 = ME.transfer(Vs, V, Wm4, k=3)
                bi2, bw2 = WT.top4(Wl2)
                a2 = {k: v for k, v in arrays.items() if not k.startswith("bs_")}
                a2["bones"], a2["weights"] = bi2, bw2
                LY.write_bin(os.path.join(DATA, "body_hilbs.bin"), a2, dict(meta, level="hilbs", shapes=[]))
        T["lods_s"] = time.time() - t0
        rj = rig.rig_json()
        rj["shapes"] = CR.SHAPES
        rj["arm_keys"] = {k: [float(x) for x in v] for k, v in CR.ARM_KEYS.items()}
        rj["keys"] = {"elbow": CR.ELBOW_KEY, "knee": CR.KNEE_KEY, "hip_flex": CR.HIP_FLEX_KEY, "hip_ext": CR.HIP_EXT_KEY}
        json.dump(rj, open(os.path.join(DATA, "rig.json"), "w"), indent=1)
        poses = test_poses()
        pj = {}
        for nm, p in poses.items():
            pj[nm] = {"local": {b: [float(x) for x in p["local"][b]] for b in rig.MAIN},
                      "pelvis": [float(x) for x in p["pelvis_pos"]],
                      "driver": {k: round(v, 4) for k, v in CR.driver_weights(p["local"]).items()}}
        json.dump(pj, open(os.path.join(DATA, "poses.json"), "w"), indent=1)
    # ---------------- 5) ชั้นโครงกระดูก/กล้ามเนื้อ (ภาพ) ----------------
    if si <= 4 and args.layers:
        t0 = time.time()
        Vb, Fb, Cb, Bb = LY.bone_meshes()
        Vbind = LY.pose_points(Vb, Bb, Gb)              # ท่า I -> ท่าผูก A (ใช้ Skin เดียวกับผิว)
        LY.write_bin(os.path.join(DATA, "skeleton.bin"), {"pos": Vbind, "col": np.c_[Cb, np.ones(len(Vb))], "bone": Bb,
                                                           "idx": Fb[:, ::-1]}, {"tris": len(Fb), "space": "bind"})
        log("skeleton mesh %d tris" % len(Fb))
        lay = {"skeleton_tris": int(len(Fb))}
        poses = test_poses()
        for nm in ("bind", "idle", "elbow120", "knee120", "overhead", "squat", "rifle"):
            G, _ = rig.fk(poses[nm])
            mus = MU.build(G, prims)
            Vm, Fm, Cm = LY.muscle_meshes(mus)
            LY.write_bin(os.path.join(DATA, "muscles_%s.bin" % nm), {"pos": Vm, "col": np.c_[Cm, np.ones(len(Vm))],
                                                                     "idx": Fm[:, ::-1]}, {"tris": len(Fm), "pose": nm})
            fac = {m["name"] + "_" + m["side"]: [round(f["f"], 3) for f in m["fibres"]] for m in mus}
            json.dump(fac, open(os.path.join(DATA, "muscle_volume_%s.json" % nm), "w"))
            lay["muscles_%s_tris" % nm] = int(len(Fm))
            log("muscles %-9s %d tris" % (nm, len(Fm)))
        T["layers_s"] = time.time() - t0
        json.dump(lay, open(os.path.join(DATA, "layers.json"), "w"), indent=1)
    T["total_s"] = time.time() - t_all
    if si <= 3:
        nmus = len(MU.DEFS)
        nfib = sum(m["K"] for _, m in MU.DEFS)
        numbers = {"height_m": rig.H, "rig_scale_S": rig.S, "bones_total": len(rig.BONES), "bones_game": len(rig.MAIN),
                   "bones_helper": len(rig.HELPERS), "helpers": [n for n, _, _ in rig.HELPERS],
                   "muscles_per_side": len(A.MUSCLES_L), "muscles_total": nmus, "muscle_fibres_total": nfib,
                   "skin_structures": {"cores": len(A.cores()), "landmarks": len(A.lands()), "fat_pads": len(A.pads()),
                                       "face_parts": len(A.face())},
                   "anatomical_bone_parts": len(A.bones()), "blend_shapes": CR.SHAPES, "lods": lods,
                   "sculpt": {"verts": int(len(Vs)), "tris": int(len(Fs)), "marching_cubes_tris": raw_tris,
                              "voxel_mm": H_SKIN * 1000},
                   "correctives": cstats, "intermediate_pose_error": evals,
                   "time_s": {k: round(v, 1) for k, v in T.items()}, "hashes": hashes, "seed": SEED}
        json.dump(numbers, open(os.path.join(DATA, "numbers.json"), "w"), indent=1)
    log("done in %.1fs" % (time.time() - t_all))


if __name__ == "__main__":
    main()
