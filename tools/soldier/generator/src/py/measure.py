# วัดสัดส่วนผิวที่ปั้น (ท่า A) เทียบช่วงเกต G6 (ชายสูง ~1.78 ม. ไขมันปกติ FAT_LEVEL 1.0) : ส่วนสูง เส้นรอบวง ความกว้าง
import json
import os
import numpy as np
import trimesh
import rig

ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
# ช่วงเกต G6 (ซม.) ; ศีรษะและไหล่ใช้ช่วงอ้างอิงเดิม
REF = {"stature": (176, 180), "chest": (94, 104), "waist": (80, 90), "hips": (94, 104), "neck": (37, 42),
       "thigh": (54, 62), "calf": (35, 40), "upper_arm": (29, 35), "forearm": (26, 30), "wrist": (16.5, 18.5),
       "head_height": (22, 25), "head_breadth": (14.5, 16), "foot_length": (26.0, 27.8), "shoulder_breadth": (44, 50)}


def loop_perimeter(m, origin, normal, near):
    s = m.section(plane_origin=origin, plane_normal=normal)
    if s is None:
        return None
    best = None
    for ent in s.discrete:
        pts = np.asarray(ent)
        if len(pts) < 5:
            continue
        c = pts.mean(0)
        d = np.linalg.norm(c - near)
        per = float(np.sum(np.linalg.norm(np.diff(np.vstack([pts, pts[:1]]), axis=0), axis=1)))
        if best is None or d < best[0]:
            best = (d, per)
    return best[1] if best else None


def main():
    z = np.load(os.path.join(ROOT, "work", "stage_skin.npz"))
    V, F = z["Vs"], z["Fs"]
    m = trimesh.Trimesh(V, F, process=False)
    G, _ = rig.fk(rig.bind_pose())
    out = {}
    out["stature"] = float(V[:, 1].max() - min(0.0, V[:, 1].min())) * 100
    Y = np.array([0, 1, 0.0])
    for nm, y, near in (("chest", 1.30, (0, 1.30, 0.0)), ("waist", 1.10, (0, 1.10, 0.0)), ("hips", 0.90, (0, 0.90, -0.01)),
                        ("thigh", 0.79, (0.115, 0.79, 0.0)), ("calf", 0.38, (0.10, 0.38, -0.01))):
        if nm in ("thigh", "calf"):
            b = "hipL" if nm == "thigh" else "kneeL"
            M = rig.bone_xform(G, b)
            o = (M @ np.array([near[0], y, near[2], 1.0]))[:3]
            n = M[:3, :3] @ Y
            p = loop_perimeter(m, o, n, o)
        else:
            p = loop_perimeter(m, np.array([0, y, 0.0]), Y, np.array(near))
        out[nm] = None if p is None else p * 100
    # คอ: ระนาบตั้งฉากแกนคอ (เอียงหน้า 17°) ผ่านใต้ลูกกระเดือก
    a = np.radians(17.0)
    p = loop_perimeter(m, np.array([0, 1.515, 0.040]), np.array([0, np.cos(a), np.sin(a)]), np.array([0, 1.525, -0.012]))
    out["neck"] = None if p is None else p * 100
    # แขน: ตั้งฉากกับแกนกระดูก
    for nm, b, yl in (("upper_arm", "shoulderL", 1.30), ("wrist", "elbowL", 0.885)):
        M = rig.bone_xform(G, b)
        o = (M @ np.array([0.20, yl, 0.0, 1.0]))[:3]
        n = M[:3, :3] @ Y
        p = loop_perimeter(m, o, n, o)
        out[nm] = None if p is None else p * 100
    # แขนล่าง: รอบวงมากสุดช่วงบน (ใต้ศอก 3-12 ซม.)
    M = rig.bone_xform(G, "elbowL")
    best = None
    for yl in np.arange(1.005, 1.096, 0.005):
        o = (M @ np.array([0.20, yl, 0.0, 1.0]))[:3]
        p = loop_perimeter(m, o, M[:3, :3] @ Y, o)
        if p is not None and (best is None or p > best):
            best = p
    out["forearm"] = None if best is None else best * 100
    # สูงศีรษะ: ยอดศีรษะถึงปลายคาง (menton = จุดหน้าสุดของใต้คางบนแนวกลาง ที่ผิวหันลง)
    Nv = m.vertex_normals
    mid = (np.abs(V[:, 0]) < 0.006) & (V[:, 1] > 1.50) & (V[:, 1] < 1.62) & (V[:, 2] > 0.0)
    # ปลายคาง (pogonion) หาเฉพาะใต้ร่องใต้ปากล่าง: ปากล่างที่ยื่นตามเส้น E ไม่ถูกนับเป็นคาง
    pog = V[mid & (V[:, 1] > 1.535) & (V[:, 1] < 1.562)]
    pog = pog[np.argmax(pog[:, 2])]
    sub = mid & (Nv[:, 1] < -0.6) & (V[:, 1] < pog[1]) & (V[:, 2] > pog[2] - 0.04)
    men = V[sub][np.argmax(V[sub][:, 2])] if sub.any() else pog
    out["head_height"] = float(V[:, 1].max() - men[1]) * 100
    hv = V[(V[:, 1] > 1.705) & (V[:, 1] < 1.74) & (np.abs(V[:, 2]) < 0.06)]
    hv = hv[np.abs(hv[:, 0]) < 0.09]
    out["head_breadth"] = float(hv[:, 0].max() - hv[:, 0].min()) * 100
    ft = V[(V[:, 1] < 0.03) & (V[:, 0] > 0.1)]
    out["foot_length"] = float(ft[:, 2].max() - ft[:, 2].min()) * 100
    # ไหล่ (กว้างที่ปุ่มไหล่ acromion) ในท่า A ใช้ระยะระหว่างปุ่ม acromion + เนื้อ
    # กว้างไหล่ระหว่างปุ่ม acromion (กระดูก) + ผิวเหนือปุ่ม ~5 มม. (ท่า A ทำให้วัดจากผิวตรง ๆ ไม่ได้)
    ac = (rig.bone_xform(G, "clavicleL") @ np.array([0.209 + 0.020, 1.4775, -0.004, 1.0]))[:3]
    out["shoulder_breadth"] = float(2 * ac[0] + 0.010) * 100
    rep = {}
    for k, v in out.items():
        lo, hi = REF[k]
        rep[k] = {"cm": None if v is None else round(v, 1), "ref_cm": [lo, hi],
                  "ok": None if v is None else bool(lo <= v <= hi)}
    json.dump(rep, open(os.path.join(ROOT, "out", "data", "anthropometry.json"), "w"), indent=1)
    for k, r in rep.items():
        print("%-16s %6s cm   ref %s  %s" % (k, r["cm"], r["ref_cm"], "ok" if r["ok"] else "CHECK"))


if __name__ == "__main__":
    main()
