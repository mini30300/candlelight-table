# แผ่นเทียบรอบปรับละเอียด (refine): ก่อน = รุ่นที่กรรมการดู / หลัง = รุ่นนี้ ; กล้อง แสง เท่ากันทุกคู่ (คำบรรยายภาษาไทย)
#   /usr/bin/python3 sheet_refine.py [BEFORE_DIR]
import os
import sys
from PIL import Image, ImageDraw
import sheet as S

BEFORE = sys.argv[1] if len(sys.argv) > 1 else os.path.join(S.ROOT, "work", "r2", "before_refine")


def pair_row(names, caps, W, ph, crop=True):
    """แต่ละชื่อ: ก่อน | หลัง วางคู่กัน"""
    n = len(names)
    pw = W // (2 * n)
    row = Image.new("RGB", (W, ph + 96), S.BG)
    d = ImageDraw.Draw(row)
    for i, (nm, cap) in enumerate(zip(names, caps)):
        for j, (src, lab) in enumerate(((os.path.join(BEFORE, nm + ".png"), "ก่อน"), (os.path.join(S.RAW, nm + ".png"), "หลัง"))):
            if not os.path.exists(src):
                continue
            im = Image.open(src).convert("RGB")
            if crop:
                im = S.crop_fig(im)
            im = S.fit(im, pw - 8, ph - 8)
            x = (2 * i + j) * pw
            row.paste(im, (x + 4, 44))
            S.text_c(d, (x, 4), pw, lab, S.font(34, True), S.ACC if j else S.DIM)
        S.text_c(d, (2 * i * pw, ph + 46), 2 * pw, cap, S.font(32), S.FG)
    return row


def main():
    W = 2400
    rows = [S.title(W, "รอบปรับละเอียด: ก่อน (รุ่นที่กรรมการตรวจ) / หลัง (รุ่นนี้)",
                    "กล้อง แสง ระดับไขมันเดียวกัน (FAT_LEVEL 1.0) ; หน้า = ระดับ hi และ min ; ตัว = ระดับ hi ท่า A และท่ายืนในเกม")]
    rows.append(S.text_block(W, [("หน้า (ระดับ hi): ตาเปิดเห็นลูกตา, จมูกยื่นน้อยลง, ใต้จมูกไม่เป็นปื้นดำ, ปากมีริมฝีปากบน/ล่าง ไม่มีร่องลึก", S.ACC)], 38))
    rows.append(pair_row(["face_hi_000", "face_hi_035", "face_hi_090"], ["หน้าตรง", "หน้าเฉียง", "หน้าข้าง"], W, 640, crop=False))
    rows.append(S.text_block(W, [("ระยะไกล/ระดับเบาสุด (min): ไม่มีเงาเครา ไม่มีหลุมตา ตาเป็นสีน้ำตาลนุ่ม", S.ACC)], 38))
    rows.append(pair_row(["face_min_000", "face_min_game", "face_hi_game"], ["min หน้าตรง", "min ระยะเกม", "hi ระยะเกม"], W, 640, crop=False))
    rows.append(S.text_block(W, [("ตัว: ต้นขาด้านนอกไม่ป่อง, สะโพกแคบลง, ก้นกลมยื่นขึ้น, เอวหลังแอ่น, หลังบนเรียบขึ้น", S.ACC)], 38))
    rows.append(pair_row(["turn_000", "turn_090", "turn_180"], ["หน้า", "ข้าง", "หลัง"], W, 820))
    rows.append(pair_row(["idle_000", "idle_090", "idle_180"], ["ยืนในเกม หน้า (ไหล่)", "ยืนในเกม ข้าง", "ยืนในเกม หลัง"], W, 820))
    rows.append(pair_row(["close_back", "check_hips_180", "check_hips_090"], ["หลังบน", "ก้น", "สะโพก ข้าง"], W, 640, crop=False))
    rows.append(pair_row(["close_torso", "check_collar_000", "check_knee120_000"], ["ลำตัว", "ไหปลาร้า", "เข่างอ 120°"], W, 640,
                         crop=False))
    S.stack(rows, W).save(os.path.join(S.OUT, "sheet_refine_checks.png"))
    print("sheet_refine_checks.png")


if __name__ == "__main__":
    main()
