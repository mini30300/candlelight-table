# ส่วนร่างกายต่อจุดยอด (แผลตัดเฉพาะส่วนเดียวกับกระดูกของแผล: แผลที่อกไม่เจาะแขนที่แนบอยู่ ต้นขาไม่เจาะอีกข้าง)
#   0 ลำตัว 1 หัว 2 แขนซ้าย 3 แขนขวา 4 ขาซ้าย 5 ขาขวา จากกระดูกที่ถือน้ำหนักมากสุดของจุดยอด
#   กฎตามชื่อเหมือน SoldierFigure.body_part ในเกม (ไหปลาร้า/สะบัก = ลำตัว ; hip_half/knee_half = ขา)
#   ผิวทุกระดับเก็บใน CUSTOM0.w (build.py) ; ชั้นในเก็บใน CUSTOM0.x (inner_layers.py -> assemble_inner.gd)
import numpy as np
import rig

NAMES = ["torso", "head", "armL", "armR", "legL", "legR"]
ARM = ("shoulder", "uparm", "elbow", "wrist", "hand")
LEG = ("hip", "knee", "ankle", "toe", "heel")


def part_of(name):
    if name.startswith(("neck", "head")):
        return 1
    side = 0 if name.endswith("L") else 1
    if name.startswith(ARM):
        return 2 + side
    if name.startswith(LEG):
        return 4 + side
    return 0


PART_OF_BI = np.array([part_of(b) for b in rig.BONES], np.int64)


def part_ids(bones4):
    """bones4 (n,4) จาก WT.top4 (เรียงน้ำหนักมากไปน้อย): คอลัมน์แรก = กระดูกหลัก -> ส่วน (n,) เป็น float"""
    b = np.asarray(bones4)
    b = b[:, 0] if b.ndim == 2 else b
    return PART_OF_BI[b.astype(np.int64)].astype(np.float64)
