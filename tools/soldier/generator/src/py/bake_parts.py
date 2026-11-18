# ใส่ส่วนร่างกาย (parts.py) ลง CUSTOM0.w ของ out/data/body_*.bin ของงานสร้างที่ทำก่อนมี parts โดยไม่ปั้นใหม่
#   ผลเหมือน build.py รุ่นนี้ทุกไบต์ (ส่วนจากคอลัมน์แรกของ bones ที่เก็บในไฟล์ ; hilbs ใช้ของ hi แบบ build.py)
#   /usr/bin/python3 bake_parts.py [--out DIR]      แล้วประกอบ Godot ใหม่ (src/gd/assemble.gd)
import argparse
import os
import numpy as np
import layers as LY
import parts as PT
from inner_layers import read_bin

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
LEVELS = ["hi", "mid", "lo", "min", "crowd", "hilbs"]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default=os.path.join(ROOT, "out"))
    args = ap.parse_args()
    data = os.path.join(args.out, "data")
    hi_parts = None
    for lv in LEVELS:
        path = os.path.join(data, "body_%s.bin" % lv)
        if not os.path.exists(path):
            continue
        d = read_bin(path)
        meta = d.pop("meta")
        if "cus" not in d or "bones" not in d:
            continue
        p = hi_parts if lv == "hilbs" and hi_parts is not None else PT.part_ids(d["bones"])
        if lv == "hi":
            hi_parts = p
        cus = np.array(d["cus"], np.float64)
        cus[:, 3] = p
        d["cus"] = cus
        LY.write_bin(path, d, meta)
        print("%-6s parts %s" % (lv, {PT.NAMES[k]: int((p == k).sum()) for k in range(len(PT.NAMES))}))


if __name__ == "__main__":
    main()
