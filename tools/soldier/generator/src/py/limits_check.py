# ตรวจท่าทั้งหมดใน clips.json (ท่าเดิมของเกม) เทียบช่วงขยับข้อตามกายวิภาค (rig.LIMITS)
#   มุม x/z = ทิศของกระดูก (งอ-เหยียด / กาง-หุบ) ; y = บิดรอบแกนกระดูก (swing-twist) ; องศา ในกรอบกระดูกพ่อ
import json
import os
import numpy as np
import rig

ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))


def rotvec(q):
    q = np.asarray(q, float)
    q = q if q[3] >= 0 else -q
    s = np.sqrt(max(0.0, 1 - q[3] * q[3]))
    ang = 2 * np.arccos(np.clip(q[3], -1, 1))
    return np.degrees(q[:3] / s * ang) if s > 1e-9 else np.zeros(3)


def angles(bone, q):
    """มุม (x, y, z) องศา: ข้อลูกกลม/ลำตัว = swing (เวกเตอร์หมุน x,z) + twist รอบแกน y ; ข้ออื่น = เวกเตอร์หมุนตรง ๆ"""
    base = bone[:-1] if bone[-1] in "LR" and bone not in ("pelvis",) else bone
    sx = -1.0 if bone.endswith("R") else 1.0
    if base in ("shoulder", "hip", "spine", "chest", "neck", "head"):
        tw = rig.twist_y(q)
        sw = rig.qmul(q, rig.qinv(tw))
        rv = rotvec(sw)
        x, y, z = rv[0], rotvec(tw)[1], rv[2]
    else:
        x, y, z = rotvec(q)
    return base, x, y * sx, z * sx


def main():
    d = json.load(open(os.path.join(ROOT, "ref", "clips.json")))
    rng = {}
    viol = {}
    for cn, c in d["clips"].items():
        if cn.startswith("seat_") or cn.startswith("ride_"):
            continue
        for b in rig.MAIN:
            if b in ("pelvis", "heelL", "heelR"):
                continue
            for f, q in enumerate(c["q"][b]):
                base, x, y, z = angles(b, np.array(q))
                if base not in rig.LIMITS:
                    continue
                r = rng.setdefault(base, {"x": [1e9, -1e9], "y": [1e9, -1e9], "z": [1e9, -1e9]})
                for ax, v in (("x", x), ("y", y), ("z", z)):
                    r[ax][0] = min(r[ax][0], v)
                    r[ax][1] = max(r[ax][1], v)
                    lo, hi = rig.LIMITS[base][ax]
                    over = max(lo - v, v - hi, 0)
                    if over > 2.0:
                        key = "%s.%s" % (base, ax)
                        if over > viol.get(key, (0, ""))[0]:
                            viol[key] = (round(over, 1), "%s %s frame %d (%.0f° vs %s)" % (cn, b, f, v, rig.LIMITS[base][ax]))
    out = {"range_deg": {k: {a: [round(v[0], 1), round(v[1], 1)] for a, v in r.items()} for k, r in rng.items()},
           "limits_deg": {k: {a: v for a, v in rig.LIMITS[k].items()} for k in rng}, "violations_over_2deg": viol}
    json.dump(out, open(os.path.join(ROOT, "out", "data", "joint_limits_check.json"), "w"), indent=1)
    for k, r in rng.items():
        print("%-9s x %6.1f..%6.1f  y %6.1f..%6.1f  z %6.1f..%6.1f   limits x%s y%s z%s" % (
            k, r["x"][0], r["x"][1], r["y"][0], r["y"][1], r["z"][0], r["z"][1], rig.LIMITS[k]["x"], rig.LIMITS[k]["y"],
            rig.LIMITS[k]["z"]))
    print("violations:", json.dumps(viol, indent=1, ensure_ascii=False))


if __name__ == "__main__":
    main()
