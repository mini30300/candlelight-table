# วัดสัดส่วนผิวที่ปั้น (ท่า A) เทียบช่วงเกต G6 (ชายสูง ~1.78 ม. ไขมันปกติ FAT_LEVEL 1.0) : ส่วนสูง เส้นรอบวง ความกว้าง
#   --variant NAME = ร่างหลากหลาย: ผลวัดคูณ k (ส่วนสูงจริง) เทียบช่วงของร่าง ; หญิงวัดอก/เอว/สะโพกที่รอบมาก/น้อยสุด
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


def loop_perimeter(m, origin, normal, near, xmax=None):
    s = m.section(plane_origin=origin, plane_normal=normal)
    if s is None:
        return None
    best = None
    for ent in s.discrete:
        pts = np.asarray(ent)
        if len(pts) < 5:
            continue
        if xmax is not None and np.abs(pts[:, 0]).max() > xmax:
            continue                    # ร่างหญิง: วงที่รวมแขน (ใกล้รักแร้) ไม่ใช่รอบอก
        c = pts.mean(0)
        d = np.linalg.norm(c - near)
        per = float(np.sum(np.linalg.norm(np.diff(np.vstack([pts, pts[:1]]), axis=0), axis=1)))
        if best is None or d < best[0]:
            best = (d, per)
    return best[1] if best else None


def _search(m, y0, y1, near_z, mode):
    """รอบวงแนวนอนมาก/น้อยสุดในช่วง y (ร่างหญิง: อกที่จุดยอด เอวคอดสุด สะโพกกว้างสุด) ; คืน (ซม.กรอบฐาน, y)"""
    best = None
    for y in np.arange(y0, y1 + 1e-9, 0.005):
        p = loop_perimeter(m, np.array([0, y, 0.0]), np.array([0, 1, 0.0]), np.array([0, y, near_z]), xmax=0.215)
        if p is None:
            continue
        if best is None or (p > best[0] if mode == "max" else p < best[0]):
            best = (p, float(y))
    return best


def main():
    import argparse
    import variants as VR
    ap = argparse.ArgumentParser()
    ap.add_argument("--variant", default="")
    ap.add_argument("--root", default="", help="โฟลเดอร์สร้าง (มี work/ out/) ถ้าไม่ใช่ที่ตั้งปกติ")
    a = ap.parse_args()
    VR.use(a.variant)
    root = a.root or (ROOT if VR.CUR is None else os.path.join(os.path.dirname(ROOT), VR.NAME))
    z = np.load(os.path.join(root, "work", "stage_skin.npz"))
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
    ref = REF
    where = {}
    if VR.CUR is not None:
        if VR.CUR["sex"] == "f":
            # อกหญิง: รอบวงแนวนอนที่ระดับจุดยอดอก (จุดหน้าสุดของเต้านม) ; เอวคอดสุด ; สะโพกกว้างสุด
            br = V[(np.abs(V[:, 0]) > 0.05) & (np.abs(V[:, 0]) < 0.12) & (V[:, 1] > 1.24) & (V[:, 1] < 1.34)]
            yb = float(br[np.argmax(br[:, 2]), 1])
            p = loop_perimeter(m, np.array([0, yb, 0.0]), np.array([0, 1, 0.0]), np.array([0, yb, 0.02]), xmax=0.215)
            if p is not None:
                out["chest"], where["chest"] = p * 100, round(yb, 3)
            for nm, y0, y1, nz, mode in (("waist", 1.06, 1.185, 0.0, "min"), ("hips", 0.86, 0.965, -0.01, "max")):
                b = _search(m, y0, y1, nz, mode)
                if b is not None:
                    out[nm], where[nm] = b[0] * 100, round(b[1], 3)
        if max(VR.CUR["hair"]["thick"]) > 0 and out.get("head_breadth") is not None:
            # วัดแบบกดผม (มาตรฐานการวัด): กว้างศีรษะหักผมที่จุดกว้างสุดทั้ง 2 ข้าง ; สูงศีรษะ/ส่วนสูงหักผมที่ยอดศีรษะ
            #   ความหนาผมคิดในพิกัดก่อนขยายศีรษะแล้วคูณอัตราขยาย
            import mesh as ME

            import anatomy as AN
            ears = [p for p in AN.face() if p.name in ("ear_L", "ear_R")]

            def _th(p):
                Hp = ME.head_local(VR.head_unwarp(p[None], G), G)
                return float(VR.hair_thick(Hp, VR._ear_w(Hp, ears))[0]) * VR.head_scale()
            # ผมหนา (ผมฟู): หาความกว้างของหนังศีรษะตรง ๆ = |x| - ความหนาผม × |nx| ทุกจุดในแถบ แล้วเอาค่ามากสุด
            bw = (V[:, 1] > 1.705) & (V[:, 1] < 1.74) & (np.abs(V[:, 2]) < 0.06) & (np.abs(V[:, 0]) < 0.13)
            Pb = V[bw]
            Hb = ME.head_local(VR.head_unwarp(Pb, G), G)
            tb = VR.hair_thick(Hb, VR._ear_w(Hb, ears)) * VR.head_scale()
            xc = np.abs(Pb[:, 0]) - tb * np.abs(Nv[bw][:, 0])
            where["head_breadth_with_hair"] = round(float(2 * np.abs(Pb[:, 0]).max()) * 100 * VR.scale(), 1)
            out["head_breadth"] = float(2 * xc.max()) * 100
            tv = V[np.argmax(V[:, 1])]
            tt = _th(np.array([0.0, tv[1], tv[2]]))
            where["head_height_with_hair"] = round(out["head_height"] * VR.scale(), 1)
            where["stature_with_hair"] = round(out["stature"] * VR.scale(), 1)
            out["head_height"] -= tt * 100
            out["stature"] -= tt * 100
        k = VR.scale()
        out = {kk: (None if v is None else v * k) for kk, v in out.items()}
        ref = dict(REF)
        ref.update({kk: tuple(v) for kk, v in VR.CUR["ranges"].items() if v})
    rep = {}
    for k, v in out.items():
        lo, hi = ref[k]
        rep[k] = {"cm": None if v is None else round(v, 1), "ref_cm": [lo, hi],
                  "ok": None if v is None else bool(lo <= v <= hi)}
        if k in where:
            rep[k]["at_y_base"] = where[k]
        if k + "_with_hair" in where:
            rep[k]["with_hair_cm"] = where[k + "_with_hair"]
    json.dump(rep, open(os.path.join(root, "out", "data", "anthropometry.json"), "w"), indent=1)
    for k, r in rep.items():
        print("%-16s %6s cm   ref %s  %s" % (k, r["cm"], r["ref_cm"], "ok" if r["ok"] else "CHECK"))


if __name__ == "__main__":
    main()
