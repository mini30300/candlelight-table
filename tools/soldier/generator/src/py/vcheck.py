# ตรวจข้ามร่าง (รอบปรับ): G13 เงาร่างต่างกัน (f1 กับ f2 ที่ส่วนสูงเท่ากัน ≥ 1.5 % H ในช่วงลำตัว) ;
#   G14 หน้าแต่ละคนต่างกัน (แผนที่ความลึกหน้าตรง ขนาดศีรษะเท่ากัน: RMS ระหว่างคู่ ≥ เกณฑ์)
#   /usr/bin/python3 vcheck.py --vroot <variants> [--base <โฟลเดอร์ทหารฐาน>] [--out checks.json]
#   ผิวปั้นทุกตัวอยู่ในกรอบฐาน 1.78 ม. (ก่อนย่อขยาย k) จึงเทียบที่ส่วนสูงเท่ากันได้ตรง ๆ
import argparse
import itertools
import json
import os
import numpy as np

NAMES = ("m2", "m3", "f1", "f2")
H = 1.78
SIL_MIN = 0.015 * H          # G13: f1 กับ f2 ต่างกันอย่างน้อย 1.5 % ของส่วนสูง
FACE_MIN_MM = 2.5            # G14: RMS ความลึกหน้าระหว่างทุกคู่ (มม.) ; รอบ 3 คู่ที่ใกล้สุด 2.23 (ไม่ผ่าน)


def torso_profiles(V, F, y0=0.90, y1=1.24, dy=0.01):
    """ความกว้างเต็ม (หน้า) และความลึก (ข้าง) ของลำตัวต่อระดับ y: หน้าตัดแนวนอน วงที่ล้อมแกนกลางตัว (แขนเป็นวงแยก)"""
    import trimesh
    m = trimesh.Trimesh(V, F, process=False)
    ys = np.arange(y0, y1 + 1e-9, dy)
    W, D = np.zeros(len(ys)), np.zeros(len(ys))
    for i, y in enumerate(ys):
        sec = m.section(plane_origin=[0, y, 0], plane_normal=[0, 1, 0])
        best = None
        for ent in (sec.discrete if sec is not None else []):
            P = np.asarray(ent)
            if len(P) < 8 or abs(P[:, 0].mean()) > 0.05:
                continue
            ar = np.ptp(P[:, 0]) * np.ptp(P[:, 2])
            if best is None or ar > best[0]:
                best = (ar, P)
        if best is not None:
            W[i], D[i] = np.ptp(best[1][:, 0]), np.ptp(best[1][:, 2])
    return ys, W, D


def face_depth(V, Gy=0.00475363):
    """แผนที่ความลึกหน้าตรง (กรอบศีรษะ ท่า I) x ±6 ซม. y 1.55-1.74 ทุก 2.5 มม."""
    Hh = V + np.array([0, Gy, 0])
    m = (Hh[:, 2] > 0.02) & (np.abs(Hh[:, 0]) < 0.068) & (Hh[:, 1] > 1.545) & (Hh[:, 1] < 1.745)
    P = Hh[m]
    xs = np.arange(-0.060, 0.0601, 0.0025)
    ys = np.arange(1.550, 1.7401, 0.0025)
    ix = np.clip(np.round((P[:, 0] - xs[0]) / 0.0025).astype(int), 0, len(xs) - 1)
    iy = np.clip(np.round((P[:, 1] - ys[0]) / 0.0025).astype(int), 0, len(ys) - 1)
    Z = np.full((len(ys), len(xs)), -1.0)
    np.maximum.at(Z, (iy, ix), P[:, 2])
    return np.where(Z > 0, Z, np.nan)


def load(root, base=False):
    z = np.load(os.path.join(root, "work", "stage_skin.npz"))
    Vs = z["Vs"]
    Vu = z["Vu"] if "Vu" in z.files else Vs           # หน้าเทียบที่ขนาดศีรษะก่อนขยาย (รูปทรงล้วน)
    return Vs, Vu, z["Fs"]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--vroot", required=True)
    ap.add_argument("--base", default="")
    ap.add_argument("--out", default="")
    a = ap.parse_args()
    base = a.base or os.path.join(a.vroot, "gen")
    roots = {"base": base}
    roots.update({n: os.path.join(a.vroot, n) for n in NAMES})
    prof, faces = {}, {}
    for n, r in roots.items():
        if not os.path.exists(os.path.join(r, "work", "stage_skin.npz")):
            continue
        Vs, Vu, Fs = load(r)
        prof[n] = torso_profiles(Vs, Fs)
        faces[n] = face_depth(Vu)
    sil = {}
    for p, q in itertools.combinations(sorted(prof), 2):
        ys, Wp, Dp = prof[p]
        _, Wq, Dq = prof[q]
        iw, idp = int(np.argmax(np.abs(Wp - Wq))), int(np.argmax(np.abs(Dp - Dq)))
        sil[p + "-" + q] = {"max_width_diff_mm": round(1000 * abs(Wp - Wq)[iw], 1), "at_y_w": round(float(ys[iw]), 3),
                            "max_depth_diff_mm": round(1000 * abs(Dp - Dq)[idp], 1), "at_y_d": round(float(ys[idp]), 3)}
    ff = sil.get("f1-f2")
    g13 = {"pass": bool(bool(ff) and max(ff["max_width_diff_mm"], ff["max_depth_diff_mm"]) >= 1000 * SIL_MIN),
           "limit_mm": round(1000 * SIL_MIN, 1), "pairs": sil}
    fr = {}
    for p, q in itertools.combinations(sorted(faces), 2):
        d = faces[p] - faces[q]
        fr[p + "-" + q] = round(float(np.sqrt(np.nanmean(d ** 2)) * 1000), 2)
    g14 = {"pass": bool(bool(fr) and min(fr.values()) >= FACE_MIN_MM), "limit_mm": FACE_MIN_MM, "pairs_rms_mm": fr}
    R = {"G13": g13, "G14": g14}
    print(json.dumps(R, indent=1))
    if a.out:
        json.dump(R, open(a.out, "w"), indent=1)


if __name__ == "__main__":
    main()
