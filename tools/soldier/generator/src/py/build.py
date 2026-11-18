# สร้างทหารขั้นที่ 1c ทั้งชุด (กำหนดแน่นอน): โครงกระดูก -> กล้ามเนื้อ -> ชั้นไขมัน -> ผิว -> น้ำหนัก -> ท่าแก้ -> ไฟล์ให้ Godot
#   /usr/bin/python3 build.py [--out DIR] [--work DIR] [--from STAGE] [--fat 1.0] [--static TAG]
#   FAT_LEVEL (หรือ --fat) คูณความหนาไขมันและรัศมีเติมร่องทุกค่า (ค่าเริ่ม 1.0) ; --static = ผิวไม่มีโครงไว้ทำภาพเทียบ
#   G1 (ชิ้นเดียว ปิดสนิท genus 0) ไม่ผ่านที่เมชปั้นหรือระดับใด = หยุดทันที
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
import fatmap as FM

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
CLIPS = os.path.join(ROOT, "ref", "clips.json")
SEED = 20261117          # สุ่มเฉพาะลำดับหน้าก่อนลดสามเหลี่ยม (seed คงที่ ใน mesh.PERM_SEED)
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
    """บริเวณที่ให้สามเหลี่ยมมากกว่าส่วนอื่นตอนลดความละเอียด (ทางสำรองแบบเดิม: ขยายพื้นที่ก่อนลด)"""
    spots = [(np.array([0.0, 1.655, 0.035]), 0.13, 2.8)]
    for sx in (1.0, -1.0):
        spots.append((np.array([sx * 0.032, 1.664, 0.085]), 0.022, 1.5))
    spots.append((np.array([0.0, 1.598, 0.100]), 0.028, 1.4))
    for sd in ("L", "R"):
        sx = 1.0 if sd == "L" else -1.0
        hc = (rig.bone_xform(Gb, "wrist" + sd) @ np.array([sx * 0.20, 0.80, 0.0, 1.0]))[:3]
        spots.append((hc, 0.085, 2.0))
    return spots


# น้ำหนักการลดสามเหลี่ยม (Blender): ยิ่งต่ำยิ่งเก็บสามเหลี่ยมไว้ ; factor ต่อระดับ (ปรับให้หน้า hi ≥ 2,500 / mid ≥ 1,200)
LOD_FACTOR = {"hi": 0.003, "mid": 0.005, "lo": 0.010, "min": 0.025}
SCULPT_FACTOR = 0.05


ABD_W = 0.30        # ขั้น 1c: หน้าท้อง/ใต้อกได้สามเหลี่ยมมากขึ้นใน hi/mid (ร่องกล้ามท้องกว้าง ~1.5-2 ซม. ต้องมีจุดยอดพอ)
NAV_W = 0.55        # ขั้น 1c ปรับ: วงจุดยอดรอบสะดือใน hi/mid (หลุมสะดืออ่านออก)
ABD_W_LO, GRV_W_LO = 0.20, 0.50   # ขั้น 1c ปรับ: lo (ค่าเริ่มของมือถือ) ได้แถวจุดยอดตามร่องกลางท้อง/รอยคั่น
KC_LO_ABD, KN_LO_ABD = 0.20, 0.45  # lo ที่หน้าท้อง: เฉลี่ยสี/นอร์มอลแคบลง (เดิม 0.45 / 1.0 ทั้งตัว) ร่องจึงไม่จางหาย
FACE_HM, HAND_HM = 1.35, 1.4   # ขั้น 1c: hi/mid ชดเชยหน้าและมือ (สามเหลี่ยมหน้า/มือไม่น้อยกว่าขั้น 1b)
FACE_LO, HAND_LO = 1.45, 1.10  # ขั้น 1c ปรับ: lo ชดเชยหน้าและมือ (หน้าท้องได้แถวจุดยอดเพิ่ม ; หน้า/มือคงจำนวนเดิม)


def detail_weights(Gb, sculpt=False, lv=None):
    """ฟังก์ชัน จุด -> น้ำหนักการลด 0..1: หน้าทั้งหน้า (ตา จมูก ปาก มากสุด) และมือ ; เท้าลดตามปกติ (จะอยู่ในรองเท้า)
    sculpt = เมชปั้น: เก็บผิว marching cubes 2 มม. ไว้เกือบทั้งหมดในรัศมี ~9 ซม. รอบหน้า (ต้นแบบอบลาย)
    lv = ระดับ: hi/mid เพิ่มหน้าท้อง + วงรอบสะดือ ; lo เพิ่มแถวจุดยอดตามร่องหน้าท้อง ; min คงเดิม"""
    hcs = [(rig.bone_xform(Gb, "wrist" + sd) @ np.array([sx * 0.20, 0.80, 0.0, 1.0]))[:3] for sd, sx in (("L", 1), ("R", -1))]
    Mh = rig.bone_xform(Gb, "head")
    fc = (Mh @ np.array([0.0, 1.653, 0.045, 1.0]))[:3]
    feats = [(Mh @ np.array([*c, 1.0]))[:3] for c in ((0.032, 1.663, 0.085), (-0.032, 1.663, 0.085), (0.0, 1.625, 0.110),
                                                      (0.0, 1.587, 0.102))]
    fr = [(0.026, 0.018, 0.022), (0.026, 0.018, 0.022), (0.020, 0.020, 0.020), (0.031, 0.018, 0.022)]
    ac = (rig.bone_xform(Gb, "pelvis") @ np.array([0.0, 1.165, 0.10, 1.0]))[:3]
    nc = (rig.bone_xform(Gb, "pelvis") @ np.array([0.0, FM.NV_Y, 0.10, 1.0]))[:3]

    def g(V, c, r):
        return np.exp(-np.sum(((V - np.asarray(c)) / np.asarray(r)) ** 2, axis=1))

    kf, kh = (FACE_HM, HAND_HM) if lv in ("hi", "mid") else ((FACE_LO, HAND_LO) if lv == "lo" else (1.0, 1.0))

    def wfun(V):
        front = np.clip((V[:, 2] + 0.03) / 0.04, 0, 1)
        if sculpt:
            face = g(V, fc, (0.090, 0.105, 0.090)) * front
            face = np.clip(1.6 * face, 0, 1)
            return 1.0 - face
        face = 0.55 * kf * g(V, fc, (0.085, 0.102, 0.085)) * front
        feat = np.maximum.reduce([g(V, c, r) for c, r in zip(feats, fr)])
        hands = np.maximum.reduce([0.16 * kh * g(V, hc, (0.07, 0.07, 0.07)) for hc in hcs])
        fz = np.clip((V[:, 2] - 0.03) / 0.04, 0, 1)
        if lv in ("hi", "mid"):
            abd = np.maximum(ABD_W * g(V, ac, (0.090, 0.125, 0.07)) * fz, NAV_W * g(V, nc, (0.016, 0.018, 0.020)) * front)
        elif lv == "lo":
            abd = np.maximum(ABD_W_LO * g(V, ac, (0.090, 0.125, 0.07)) * fz,
                             GRV_W_LO * np.clip(FM.grooves(V, Gb, navel=False) * 1000.0 / 2.0, 0, 1))
        else:
            abd = 0 * face
        return 1.0 - np.maximum.reduce([face, 0.9 * feat, hands, abd])
    return wfun


def abd_box(V, Gb):
    """น้ำหนัก 0..1 ของหน้าท้อง/ใต้อกด้านหน้า (ปรับการเฉลี่ยของ lo)"""
    ac = (rig.bone_xform(Gb, "pelvis") @ np.array([0.0, 1.165, 0.10, 1.0]))[:3]
    g = np.exp(-np.sum(((V - ac) / np.array([0.11, 0.15, 0.08])) ** 2, axis=1))
    return np.clip(1.4 * g, 0, 1) * np.clip((V[:, 2] - 0.03) / 0.04, 0, 1)


def lod_mesh(Vs, Fs, tris, lv, seam, Gb):
    """ระดับรายละเอียดหนึ่งระดับ: ลดแบบสมมาตร (น้ำหนักหน้า/มือ) -> สูงเท่าเมชปั้น -> รอยต่อกลางตัวฉายลงผิวปั้น -> ฝ่าเท้าที่ y = 0
    ระดับต่ำสุด: เกลี่ยเบ้าตาให้ตื้น (ระยะไกลไม่เป็นหลุมดำ)"""
    V, F, _ = ME.decimate_sym(Vs, Fs, tris, detail_spots(Gb), wfun=detail_weights(Gb, lv=lv), factor=LOD_FACTOR.get(lv, 0.01))
    V = ME.clamp_top(V, float(Vs[:, 1].max()))
    V = ME.project_seam(V, *seam)
    if lv == "min":
        Mh = rig.bone_xform(Gb, "head")
        cs = [(Mh @ np.array([sx * 0.032, 1.6635, 0.088, 1.0]))[:3] for sx in (1.0, -1.0)]
        V = ME.flatten_region(V, F, cs, [(0.024, 0.017, 0.020)] * 2, it=10, lam=0.5)
    V = ME.snap_soles(V)
    return V, F


def h(a):
    return hashlib.sha256(np.ascontiguousarray(a).tobytes()).hexdigest()[:16]


def gate_g1(name, topo):
    """เกต G1: ชิ้นเดียว ไม่มีขอบเปิด ไม่มีขอบ/จุดไม่แมนิโฟลด์ ออยเลอร์ 2 — ไม่ผ่าน = หยุดสร้างทันที"""
    ok = ME.topology_ok(topo)
    log("G1 %-7s %s %s" % (name, "PASS" if ok else "FAIL", topo))
    if not ok:
        raise SystemExit("G1 FAILED for %s: %s" % (name, topo))
    return ok


def sym_stats(V, F):
    """เกต G3: จำนวนสามเหลี่ยมแต่ละข้าง + ระยะสะท้อน (มม.)"""
    from scipy.spatial import cKDTree
    c = V[F].mean(1)
    nl, nr = int((c[:, 0] > 0).sum()), int((c[:, 0] < 0).sum())
    d, _ = cKDTree(V).query(V * np.array([-1.0, 1.0, 1.0]))
    return {"tris_left": nl, "tris_right": nr, "side_diff_pct": round(100.0 * abs(nl - nr) / max(nl, nr), 3),
            "mirror_p95_mm": round(float(np.percentile(d, 95) * 1000), 4), "mirror_max_mm": round(float(d.max() * 1000), 4)}


SKIN_T = 0.0018            # หนังแท้+หนังกำพร้าเฉลี่ย (ไม่ใช่ไขมัน)


def fat_estimate(st, vol_skin, area):
    """% ไขมันโดยประมาณจากปริมาตร: ชั้นใต้ผิว (ผิว - กายวิภาคผอม - หนังหนา 1.8 มม.) ความหนาแน่น 0.90 ;
    ส่วนผอม 1.06 ; หนัง 1.10 ; + ไขมันในช่องท้อง/จำเป็น 3 % ของมวล (ค่าประมาณคร่าว ๆ)"""
    va = st.get("anat_m3", 0.0)
    vk = area * SKIN_T
    vf = max(vol_skin - va - vk, 0.0)
    mf = 900.0 * vf
    m = mf + 1060.0 * va + 1100.0 * vk
    bf = (mf + 0.03 * m) / max(m, 1e-9)
    return {"volume_skin_L": round(vol_skin * 1000, 2), "volume_lean_L": round(va * 1000, 2),
            "volume_closed_L": round(st.get("closed_m3", 0.0) * 1000, 2), "volume_fat_layer_L": round(vf * 1000, 2),
            "skin_area_m2": round(area, 3), "mass_kg": round(m, 1), "bmi": round(m / rig.H ** 2, 1),
            "body_fat_pct": round(100 * bf, 1)}


def skin_stage(Gb, prims, mus_b, fat, work):
    """ผิวปั้น: สนามละเอียดครึ่งซ้าย -> marching cubes -> สะท้อน/เชื่อม -> เกลี่ย -> ลดเป็นเมชปั้น -> สี"""
    t0 = time.time()
    st = {}
    gf, i0 = FD.skin_fine(Gb, prims, mus_b, fat=fat, verbose=True, stats=st)
    Vh, Fh = ME.mc_half(gf, i0)
    V, F, pair = ME.mirror_weld(Vh, Fh)
    raw_tris = int(len(F))
    log("marching cubes (2 mm): %d tris ; %s" % (raw_tris, ME.topology(V, F)))
    V = ME.taubin_sym(V, F, pair, 6)
    Vs, Fs, pair_s = ME.decimate_sym(V, F, ME.SCULPT_TRIS, detail_spots(Gb), wfun=detail_weights(Gb, sculpt=True),
                                     factor=SCULPT_FACTOR)
    del V, F, pair
    topo = ME.topology(Vs, Fs)
    if not ME.topology_ok(topo):
        # เก็บไว้ตรวจหาจุดเสีย ก่อนหยุดสร้าง
        np.savez_compressed(os.path.join(work, "fail_skin.npz"), Vh=Vh, Fh=Fh, Vs=Vs, Fs=Fs, glo=gf.lo, gh=gf.h)
    gate_g1("sculpt", topo)
    Ns = ME.vnormals(Vs, Fs)
    rgb, flesh, ao = ME.colours(Vs, Ns, lambda P: FD.sample_sym(gf, P), Gb, Fs, prims, fat=fat)
    vol = float(np.einsum('ij,ij->i', Vs[Fs[:, 0]], np.cross(Vs[Fs[:, 1]], Vs[Fs[:, 2]])).sum() / 6)
    area = float(0.5 * np.linalg.norm(np.cross(Vs[Fs[:, 1]] - Vs[Fs[:, 0]], Vs[Fs[:, 2]] - Vs[Fs[:, 0]]), axis=1).sum())
    fe = fat_estimate(st, vol, area)
    log("skin: sculpt %d tris / %d verts ; %s ; %.1fs" % (len(Fs), len(Vs), fe, time.time() - t0))
    np.savez_compressed(os.path.join(work, "stage_skin.npz"), Vs=Vs, Fs=Fs, pair=pair_s, rgb=rgb, flesh=flesh, ao=ao,
                        raw_tris=raw_tris, glo=gf.lo, gh=gf.h, fat=fat, fe=json.dumps(fe), topo=json.dumps(topo),
                        T=json.dumps({"skin_s": time.time() - t0}))
    del gf


def write_static(DATA, tag, Vs, Fs, rgb, flesh, seam, Gb, fe):
    """แบบไม่มีโครง (ภาพเทียบระดับไขมัน): ระดับ hi เท่านั้น"""
    V, F = lod_mesh(Vs, Fs, ME.LOD_TRIS["hi"], "hi", seam, Gb)
    gate_g1("static", ME.topology(V, F))
    Ng = ME.vnormals(V, F)
    Ns = ME.vnormals(Vs, Fs)
    sg = np.maximum(0.3 * ME.edge_scale(V, F), 0.001)
    N = ME.transfer_smooth(Vs, V, Ns, sg, Nsrc=Ns, Ndst=Ng)
    N /= np.maximum(np.linalg.norm(N, axis=1, keepdims=True), 1e-9)
    C = ME.transfer_smooth(Vs, V, rgb, sg, Nsrc=Ns, Ndst=Ng)
    fl = ME.transfer_smooth(Vs, V, flesh, sg, Nsrc=Ns, Ndst=Ng)
    arrays = {"pos": V, "nrm": N, "col": np.c_[C, np.ones(len(V))],
              "cus": np.c_[np.zeros(len(V)), np.zeros(len(V)), fl, np.zeros(len(V))], "idx": F[:, ::-1]}
    LY.write_bin(os.path.join(DATA, "body_static_%s.bin" % tag), arrays, {"tris": int(len(F)), "fat": tag, "fe": fe})
    log("static %s: %d tris" % (tag, len(F)))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default=os.path.join(ROOT, "out"))
    ap.add_argument("--work", default=os.path.join(ROOT, "work"))
    ap.add_argument("--from", dest="start", default="skin")
    ap.add_argument("--layers", type=int, default=1)
    ap.add_argument("--fat", type=float, default=float(os.environ.get("FAT_LEVEL", "1.0")))
    ap.add_argument("--static", default="", help="เฉพาะผิวแบบไม่มีโครง (ภาพเทียบระดับไขมัน) ชื่อ TAG")
    args = ap.parse_args()
    OUT = args.out
    DATA = os.path.join(OUT, "data")
    os.makedirs(DATA, exist_ok=True)
    os.makedirs(args.work, exist_ok=True)
    FAT = args.fat
    stages = ["skin", "weights", "correctives", "export", "layers"]
    si = stages.index(args.start)
    T = {}
    t_all = time.time()
    prims = A.all_skin_prims()
    MU.init_lengths(prims)
    Gb, Lb = rig.fk(rig.bind_pose())
    mus_b = MU.build(Gb, prims)
    cache = os.path.join(args.work, "stage_skin.npz")
    log("FAT_LEVEL %.2f" % FAT)
    # ---------------- 1) ผิว (ชั้นไขมัน) ----------------
    if si <= 0:
        skin_stage(Gb, prims, mus_b, FAT, args.work)
    z = np.load(cache)
    Vs, Fs, rgb, flesh = z["Vs"], z["Fs"], z["rgb"], z["flesh"]
    pair_s = z["pair"]
    T.update(json.loads(str(z["T"])))
    raw_tris = int(z["raw_tris"])
    fe = json.loads(str(z["fe"]))
    topo_s = json.loads(str(z["topo"]))
    # สีคำนวณใหม่จาก AO ที่เก็บไว้ (แก้การทาสีได้โดยไม่ต้องปั้นผิวใหม่)
    rgb, flesh, _ = ME.colours(Vs, ME.vnormals(Vs, Fs), None, Gb, Fs, prims, ao=z["ao"], fat=FAT)
    rgb_far, flesh_far, _ = ME.colours(Vs, ME.vnormals(Vs, Fs), None, Gb, Fs, prims, ao=z["ao"], far=True, fat=FAT)
    rgb_lo, _, _ = ME.colours(Vs, ME.vnormals(Vs, Fs), None, Gb, Fs, prims, ao=z["ao"], far=True, fat=FAT, far_abs=True)
    seam = ME.seam_polyline(Vs, Fs, pair_s)
    if args.static:
        write_static(DATA, args.static, Vs, Fs, rgb, flesh, seam, Gb, fe)
        json.dump(fe, open(os.path.join(DATA, "fat_%s.json" % args.static), "w"), indent=1)
        log("done static in %.1fs" % (time.time() - t_all))
        return
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
    # ---------------- 3) ท่าแก้ (ฝั่งซ้าย แล้วสะท้อนเป็นฝั่งขวา) ----------------
    cc = os.path.join(args.work, "stage_corr.npz")
    if si <= 2:
        t0 = time.time()
        DL, cstats = CR.compute(Vs, Fs, Wh4, prims, Gb, shapes=[s for s in CR.SHAPES if s.endswith("L")], fat=FAT)
        D = CR.mirror_shapes(DL, pair_s)
        for k in list(cstats):
            cstats[k[:-1] + "R"] = dict(cstats[k], mirrored_from=k)
        T["correctives_s"] = time.time() - t0
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
            evals[nm] = CR.evaluate(Vs, Wh4, Wm4, D, prims, Gb, p, joint, box, fat=FAT)
            log("eval %-14s %s" % (nm, {k: v for k, v in evals[nm].items() if k != "driver"}))
        T["eval_s"] = time.time() - t0
        np.savez_compressed(cc, **{k: v for k, v in D.items()}, cstats=json.dumps(cstats), evals=json.dumps(evals),
                            T=json.dumps(T))
    z = np.load(cc)
    D = {k: z[k] for k in CR.SHAPES}
    cstats = json.loads(str(z["cstats"]))
    evals = json.loads(str(z["evals"]))
    T.update(json.loads(str(z["T"])))
    # ---------------- 4) ระดับรายละเอียด (สมมาตร) + ไฟล์ Godot ----------------
    hashes = {}
    lods = {}
    gates = {"G1": {"sculpt": topo_s}, "G3": {}, "G4": {}}
    if si <= 3:
        t0 = time.time()
        Ns = ME.vnormals(Vs, Fs)
        spots = detail_spots(Gb)
        heights = {}
        for lv, tris in ME.LOD_TRIS.items():
            V, F = lod_mesh(Vs, Fs, tris, lv, seam, Gb)
            topo = ME.topology(V, F)
            gate_g1(lv, topo)
            gates["G1"][lv] = topo
            gates["G3"][lv] = sym_stats(V, F)
            heights[lv] = float(V[:, 1].max() - V[:, 1].min())
            gates["G4"][lv] = {"min_y_mm": round(float(V[:, 1].min() * 1000), 4), "height_m": round(heights[lv], 5)}
            Ng = ME.vnormals(V, F)
            # นอร์มอล/สีจากผิวละเอียด เฉลี่ยเกาส์ตามขนาดสามเหลี่ยม: ลายเล็กกว่าสามเหลี่ยม (เส้นปาก ตา) จางลง ไม่เป็นแฉกมืด
            #   lo/min (แสงต่อจุดยอด สามเหลี่ยมใหญ่): เฉลี่ยกว้างกว่า ไม่ให้ร่องปาก/ร่องแก้มเป็นแฉกมืด
            es = ME.edge_scale(V, F)
            kn, kc = (1.0, 0.45) if lv in ("lo", "min") else (0.3, 0.3)
            kn_v, kc_v = kn, kc
            if lv == "lo":
                # ขั้น 1c ปรับ: หน้าท้องของ lo เฉลี่ยแคบลง (มีแถวจุดยอดตามร่องแล้ว)
                ab = abd_box(V, Gb)
                kn_v, kc_v = kn + (KN_LO_ABD - kn) * ab, kc + (KC_LO_ABD - kc) * ab
            N = ME.transfer_smooth(Vs, V, Ns, np.maximum(kn_v * es, 0.001), k=96 if kn > 0.5 else 48, Nsrc=Ns, Ndst=Ng)
            N /= np.maximum(np.linalg.norm(N, axis=1, keepdims=True), 1e-9)
            sg = np.maximum(kc_v * es, 0.001)
            far = lv in ("lo", "min")          # ระดับไกล: สีหน้าแบบระยะไกล (ไม่มีเงาเครา ตาเป็นอัลมอนด์นุ่ม)
            C = ME.transfer_smooth(Vs, V, rgb_lo if lv == "lo" else (rgb_far if far else rgb), sg, k=96 if kc > 0.5 else 48, Nsrc=Ns, Ndst=Ng)
            fl = ME.transfer_smooth(Vs, V, flesh_far if far else flesh, sg, k=96 if kc > 0.5 else 48, Nsrc=Ns, Ndst=Ng)
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
            log("lod %-3s %6d tris %6d verts shapes %d  sym %s" % (lv, len(F), len(V), len(shapes), gates["G3"][lv]))
            if lv == "hi":
                # เทียบก่อน/หลัง: เรขาคณิตเดียวกับ hi แต่ใช้น้ำหนักแบบ min (23 กระดูก ไม่มีกระดูกช่วย ไม่มีท่าแก้)
                Wl2 = ME.transfer(Vs, V, Wm4, k=3)
                bi2, bw2 = WT.top4(Wl2)
                a2 = {k: v for k, v in arrays.items() if not k.startswith("bs_")}
                a2["bones"], a2["weights"] = bi2, bw2
                LY.write_bin(os.path.join(DATA, "body_hilbs.bin"), a2, dict(meta, level="hilbs", shapes=[]))
        gates["G4"]["height_spread_mm"] = round((max(heights.values()) - min(heights.values())) * 1000, 3)
        T["lods_s"] = time.time() - t0
        rj = rig.rig_json()
        rj["shapes"] = CR.SHAPES
        rj["arm_keys"] = {k: [float(x) for x in v] for k, v in CR.ARM_KEYS.items()}
        rj["keys"] = {"elbow": CR.ELBOW_KEY, "knee": CR.KNEE_KEY, "hip_flex": CR.HIP_FLEX_KEY, "hip_ext": CR.HIP_EXT_KEY}
        rj["fat_level"] = FAT
        json.dump(rj, open(os.path.join(DATA, "rig.json"), "w"), indent=1)
        poses = test_poses()
        pj = {}
        for nm, p in poses.items():
            pj[nm] = {"local": {b: [float(x) for x in p["local"][b]] for b in rig.MAIN},
                      "pelvis": [float(x) for x in p["pelvis_pos"]],
                      "driver": {k: round(v, 4) for k, v in CR.driver_weights(p["local"]).items()}}
        json.dump(pj, open(os.path.join(DATA, "poses.json"), "w"), indent=1)
        json.dump(gates, open(os.path.join(DATA, "gates_mesh.json"), "w"), indent=1)
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
        numbers = {"height_m": rig.H, "rig_scale_S": rig.S, "fat_level": FAT, "fat": fe,
                   "bones_total": len(rig.BONES), "bones_game": len(rig.MAIN),
                   "bones_helper": len(rig.HELPERS), "helpers": [n for n, _, _ in rig.HELPERS],
                   "muscles_per_side": len(A.MUSCLES_L), "muscles_total": nmus, "muscle_fibres_total": nfib,
                   "skin_structures": {"cores": len(A.cores()), "landmarks": len(A.lands()), "fat_pads": len(A.pads()),
                                       "face_parts": len(A.face())},
                   "anatomical_bone_parts": len(A.bones()), "blend_shapes": CR.SHAPES, "lods": lods,
                   "sculpt": {"verts": int(len(Vs)), "tris": int(len(Fs)), "marching_cubes_tris": raw_tris,
                              "voxel_mm": 2.0, "coarse_voxel_mm": 3.0},
                   "correctives": cstats, "intermediate_pose_error": evals,
                   "time_s": {k: round(v, 1) for k, v in T.items()}, "hashes": hashes, "seed": SEED}
        json.dump(numbers, open(os.path.join(DATA, "numbers.json"), "w"), indent=1)
    log("done in %.1fs" % (time.time() - t_all))


if __name__ == "__main__":
    main()
