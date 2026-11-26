# ภาพตัวอย่างเร็วของร่างหลากหลาย (ปรับรูปหน้า/ร่างก่อนสร้างจริง): สนามผิวของส่วนที่เลือก -> marching cubes -> สี -> .bin
#   /usr/bin/python3 vpreview.py --variant f1 --part head|body [--h 0.002] --out DIR
#   แล้ว Godot: BINS=DIR/<tag>.bin VIEWS=head|body OUT_DIR=... xvfb-run ... -s res://src/gd/vpreview.gd
#   กรอบฐาน 1.78 ม. (ไม่ย่อขยาย) ท่าผูก A ; ไม่ใช่ผลสร้างจริง (ไม่มีลดสามเหลี่ยม/น้ำหนัก)
import argparse
import os
import time
import numpy as np
import rig
import anatomy as A
import muscles as MU
import field as FD
import mesh as ME
import layers as LY
import variants as VR
from sdfk import Grid


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--variant", default="")
    ap.add_argument("--part", default="head")
    ap.add_argument("--h", type=float, default=0.0)
    ap.add_argument("--fat", type=float, default=None)
    ap.add_argument("--out", required=True)
    ap.add_argument("--tag", default="")
    a = ap.parse_args()
    VR.use(a.variant)
    fat = a.fat if a.fat is not None else (VR.CUR["fat"] if VR.CUR is not None else 1.0)
    os.makedirs(a.out, exist_ok=True)
    t0 = time.time()
    prims = A.all_skin_prims()
    MU.init_lengths(prims)
    G, _ = rig.fk(rig.bind_pose())
    mus = MU.build(G, prims)
    if a.part == "head":
        h = a.h or 0.002
        g = Grid(np.array([-0.125, 1.47, -0.175]), np.array([0.125, 1.80, 0.165]), h)
        FD.skin_field(G, prims, mus, g, fat, clip_margin=0.03)
        g.F = FD.blur(g.F, h, 0.0008)
        V, F = ME.mc_mesh(g)
        sampler = g.sample
    else:
        h = a.h or 0.004
        lo, hi = FD.body_box(G, prims, mus, 0.012)
        m = 0.035 * fat + 0.012
        lo, hi = lo - m, hi + m
        i0 = int(round(0.09 / h))
        ny0 = int(np.ceil(-lo[1] / h))
        g = Grid(np.array([-i0 * h, -(ny0 + 0.5) * h, lo[2]]), hi, h)
        FD.skin_field(G, prims, mus, g, fat, skip_xmin=True)
        g.F = FD.blur(g.F, h, 0.0035)
        y = (g.lo[1] + np.arange(g.n[1]) * h).astype(np.float32)
        g.F = np.maximum(g.F, -y[None, :, None])
        Vh, Fh = ME.mc_half(g, i0)
        V, F, _ = ME.mirror_weld(Vh, Fh)
        sampler = lambda P: FD.sample_sym(g, P)
    print("field+mc %.1fs  %d tris" % (time.time() - t0, len(F)), flush=True)
    if VR.cfg():
        V = VR.smooth_lowface(V, F, None, G) if a.part == "head" else V
    N = ME.vnormals(V, F)
    rgb, flesh, _ = ME.colours(V, N, sampler, G, F, prims, fat=fat)
    if VR.CUR is not None:
        V = VR.head_warp(V, G)                 # ศีรษะขยายเหมือนผลสร้างจริง
        N = ME.vnormals(V, F)
    tag = a.tag or ("%s_%s" % (a.variant or "base", a.part))
    n = len(V)
    LY.write_bin(os.path.join(a.out, tag + ".bin"), {"pos": V, "nrm": N, "col": np.c_[rgb, np.ones(n)],
                                                     "cus": np.c_[np.zeros(n), np.zeros(n), flesh, np.zeros(n)],
                                                     "idx": F[:, ::-1]}, {"tris": int(len(F))})
    if a.part == "body":
        # วัดแบบ G6 บนเมชตัวอย่าง (ไม่ใช่ผลจริง): measure.py --root <out>/<tag>_root
        r = os.path.join(a.out, tag + "_root")
        os.makedirs(os.path.join(r, "work"), exist_ok=True)
        os.makedirs(os.path.join(r, "out", "data"), exist_ok=True)
        np.savez(os.path.join(r, "work", "stage_skin.npz"), Vs=V, Fs=F)
    print("done %.1fs -> %s" % (time.time() - t0, tag), flush=True)


if __name__ == "__main__":
    main()
