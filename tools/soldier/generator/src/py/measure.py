# วัดสัดส่วนผิวที่ปั้น (ท่า A) เทียบค่ามาตรฐานผู้ชายสูง ~1.78 ม. : ส่วนสูง เส้นรอบวง ความกว้าง
import json
import os
import numpy as np
import trimesh
import rig

ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
# ค่าอ้างอิงโดยประมาณของชายผู้ใหญ่ (ซม.) — ช่วงกว้าง ๆ ของคนรูปร่างฟิต
REF = {"stature": (176, 180), "chest": (94, 104), "waist": (78, 88), "hips": (92, 102), "neck": (37, 41),
       "thigh": (52, 60), "calf": (36, 40), "upper_arm": (29, 34), "forearm": (26, 30), "wrist": (16.5, 18.5),
       "head_height": (22, 25), "head_breadth": (14.5, 16), "foot_length": (25.5, 28), "shoulder_breadth": (44, 50)}


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
                        ("neck", 1.54, (0, 1.54, -0.012)), ("thigh", 0.79, (0.115, 0.79, 0.0)), ("calf", 0.38, (0.10, 0.38, -0.01))):
        if nm in ("thigh", "calf"):
            b = "hipL" if nm == "thigh" else "kneeL"
            M = rig.bone_xform(G, b)
            o = (M @ np.array([near[0], y, near[2], 1.0]))[:3]
            n = M[:3, :3] @ Y
            p = loop_perimeter(m, o, n, o)
        else:
            p = loop_perimeter(m, np.array([0, y, 0.0]), Y, np.array(near))
        out[nm] = None if p is None else p * 100
    # แขน: ตั้งฉากกับแกนกระดูก
    for nm, b, yl in (("upper_arm", "shoulderL", 1.30), ("forearm", "elbowL", 1.07), ("wrist", "elbowL", 0.885)):
        M = rig.bone_xform(G, b)
        o = (M @ np.array([0.20, yl, 0.0, 1.0]))[:3]
        n = M[:3, :3] @ Y
        p = loop_perimeter(m, o, n, o)
        out[nm] = None if p is None else p * 100
    head = V[(V[:, 1] > 1.54)]
    out["head_height"] = float(V[:, 1].max() - 1.545) * 100      # ยอดศีรษะถึงคาง (คางที่ y≈1.545)
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
                  "ok": None if v is None else bool(lo * 0.97 <= v <= hi * 1.03)}
    json.dump(rep, open(os.path.join(ROOT, "out", "data", "anthropometry.json"), "w"), indent=1)
    for k, r in rep.items():
        print("%-16s %6s cm   ref %s  %s" % (k, r["cm"], r["ref_cm"], "ok" if r["ok"] else "CHECK"))


if __name__ == "__main__":
    main()
