# รวมภาพเป็นแผ่นสรุป (คำบรรยายภาษาไทย) สำหรับเจ้าของงาน
import json
import os
import sys
import numpy as np
from PIL import Image, ImageDraw, ImageFont

ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
RAW = os.path.join(ROOT, "out", "renders", "raw")
OUT = os.path.join(ROOT, "out", "renders")
DATA = os.path.join(ROOT, "out", "data")
FONT = "/root/.fonts/THSarabunNew.ttf"
FONTB = "/root/.fonts/THSarabunNew-Bold.ttf"
BG = (24, 26, 30)
FG = (236, 236, 236)
ACC = (240, 196, 120)
DIM = (170, 174, 182)
GOOD = (150, 220, 150)
BAD = (240, 140, 120)


# สิ่งที่ยังไม่ดี (เขียนตรง ๆ ไม่อ้างเกินจริง)
NOT_GOOD = ["ยังไม่ดี: หน้าเป็นสีทาบนผิว (ยังไม่มีพื้นผิว/แผนที่ละเอียด) เปลือกตายังหนาเล็กน้อย ; ระยะไกล (lo/min) ตาเป็นแค่สีน้ำตาลนุ่ม",
            "ในท่า A ต้นขายังกว้างกว่าสะโพกเล็กน้อย (ขากาง 6°) ; รอบเข่ายังเล็กกว่าคนจริงราว 3 ซม. ; คอยังหนาเล็กน้อย ; เท้ายังเป็นก้อนดินน้ำมัน",
            "แสงในเกม (เชดเดอร์ผิว) ทำให้ผิวด้านที่หันลงมืดเกิน เช่น ใต้ก้น ใต้คาง — ต้องแก้ที่เชดเดอร์ (ไม่อยู่ในรอบนี้)",
            "ท่าชก/แทงบางท่าของเกมยังบิดข้อมือเกิน (งานรอบโครงกระดูก/คลิป ยังไม่ได้แก้ในรอบนี้)"]


def font(size, bold=False):
    return ImageFont.truetype(FONTB if bold else FONT, size)


def load(name):
    p = os.path.join(RAW, name + ".png")
    return Image.open(p).convert("RGB") if os.path.exists(p) else Image.new("RGB", (640, 960), (60, 20, 20))


def crop_fig(im, pad=0.06, bg_tol=10):
    a = np.asarray(im).astype(int)
    bgc = a[2, 2]
    m = np.abs(a - bgc).sum(2) > bg_tol
    ys, xs = np.nonzero(m)
    if len(xs) == 0:
        return im
    x0, x1, y0, y1 = xs.min(), xs.max(), ys.min(), ys.max()
    w, h = x1 - x0, y1 - y0
    p = int(max(w, h) * pad)
    return im.crop((max(0, x0 - p), max(0, y0 - p), min(im.width, x1 + p), min(im.height, y1 + p)))


def fit(im, w, h, bg=(40, 43, 48)):
    out = Image.new("RGB", (w, h), bg)
    s = min(w / im.width, h / im.height)
    im2 = im.resize((max(1, int(im.width * s)), max(1, int(im.height * s))), Image.LANCZOS)
    out.paste(im2, ((w - im2.width) // 2, (h - im2.height) // 2))
    return out


def bbox_of(im, bg_tol=10):
    a = np.asarray(im).astype(int)
    m = np.abs(a - a[2, 2]).sum(2) > bg_tol
    ys, xs = np.nonzero(m)
    if len(xs) == 0:
        return (0, 0, im.width, im.height)
    return (xs.min(), ys.min(), xs.max(), ys.max())


def union_row(names, pw, ph, pad=0.05):
    """ภาพชุดเดียวกัน ครอบด้วยกรอบรวมกรอบเดียว -> สเกลเท่ากันทุกภาพ"""
    ims = [load(n) for n in names]
    bb = np.array([bbox_of(im) for im in ims])
    x0, y0, x1, y1 = bb[:, 0].min(), bb[:, 1].min(), bb[:, 2].max(), bb[:, 3].max()
    p = int(max(x1 - x0, y1 - y0) * pad)
    box = (max(0, x0 - p), max(0, y0 - p), min(ims[0].width, x1 + p), min(ims[0].height, y1 + p))
    return [fit(im.crop(box), pw, ph) for im in ims]


def panel(name, w, h, crop=True, same_scale=None):
    im = load(name)
    if crop:
        im = crop_fig(im)
    return fit(im, w, h)


def text_c(d, xy, w, txt, f, fill=FG):
    tw = d.textlength(txt, font=f)
    d.text((xy[0] + (w - tw) / 2, xy[1]), txt, font=f, fill=fill)


def grid(names, caps, cols, pw, ph, cap_h=56, fsize=34, crop=True, bg=BG, sub=None):
    rows = (len(names) + cols - 1) // cols
    sh = ph + cap_h + (36 if sub else 0)
    img = Image.new("RGB", (cols * pw, rows * sh), bg)
    d = ImageDraw.Draw(img)
    f = font(fsize, True)
    fs = font(int(fsize * 0.8))
    for i, n in enumerate(names):
        x, y = (i % cols) * pw, (i // cols) * sh
        img.paste(panel(n, pw - 8, ph - 8, crop), (x + 4, y + 4))
        text_c(d, (x, y + ph), pw, caps[i], f)
        if sub:
            text_c(d, (x, y + ph + cap_h - 6), pw, sub[i], fs, DIM)
    return img


def title(w, t1, t2=None, h=None):
    h = h or (150 if t2 else 104)
    img = Image.new("RGB", (w, h), (34, 37, 43))
    d = ImageDraw.Draw(img)
    d.text((30, 14), t1, font=font(64, True), fill=ACC)
    if t2:
        d.text((32, 90), t2, font=font(40), fill=FG)
    return img


def stack(parts, w):
    H = sum(p.height for p in parts)
    out = Image.new("RGB", (w, H), BG)
    y = 0
    for p in parts:
        out.paste(p, ((w - p.width) // 2, y))
        y += p.height
    return out


def text_block(w, lines, size=38, line_h=None, colour=FG):
    line_h = line_h or int(size * 1.35)
    img = Image.new("RGB", (w, 30 + line_h * len(lines)), BG)
    d = ImageDraw.Draw(img)
    for i, ln in enumerate(lines):
        col = colour
        if isinstance(ln, tuple):
            ln, col = ln
        d.text((40, 15 + i * line_h), ln, font=font(size), fill=col)
    return img


def numbers():
    p = os.path.join(DATA, "numbers.json")
    return json.load(open(p)) if os.path.exists(p) else {}


def main():
    N = numbers()
    W = 2400
    os.makedirs(OUT, exist_ok=True)
    lods = N.get("lods", {})
    ev = N.get("intermediate_pose_error", {})
    rr = {}
    for fn in os.listdir(RAW):
        if fn.startswith("render_report") and fn.endswith(".json"):
            rr.update(json.load(open(os.path.join(RAW, fn))))
    bud = rr.get("budgets", {})
    # ---------------- 1) แผ่นภาพรวม (แผ่นเดียวที่ดูแล้วเข้าใจ) ----------------
    fe = N.get("fat", {})
    parts = [title(W, "ทหาร ขั้นที่ 1b: โครงกระดูก > กล้ามเนื้อ > ชั้นไขมันใต้ผิว > ผิว",
                   "ร่างเปลือยแบบหุ่นโชว์ (ยังไม่มีชุด/ปืน) สูง 1.78 ม. ระดับไขมัน FAT_LEVEL %.1f (ไขมันราว %s %%) ใช้โครงกระดูกเกมเดิม 23 ชิ้น + กระดูกช่วย 10 ชิ้น" % (
                       N.get("fat_level", 1.0), fe.get("body_fat_pct", "?")))]
    parts.append(grid(["layer_skeleton_000", "layer_muscles_bones_000", "layer_muscles_000", "layer_skin_000", "layer_skin_180"],
                      ["1. โครงกระดูกจริง", "2. กล้ามเนื้อเกาะกระดูก", "กล้ามเนื้อ %d มัด/ข้าง" % N.get("muscles_per_side", 41), "3. ผิว + ชั้นไขมัน", "ผิว ด้านหลัง"],
                      5, 480, 760, sub=["กะโหลก ซี่โครง เชิงกราน กระดูกยาว", "จุดเกาะต้น-ปลายบนกระดูก", "หดสั้น = หนาขึ้น (ปริมาตรคงที่)",
                                        "หุ่นกลาง ไม่มีอวัยวะเพศ", "หลัง ก้น น่อง"]))
    parts.append(grid(["turn_000", "turn_045", "turn_090", "turn_180", "idle_000", "idle_090"],
                      ["หน้า", "เฉียง", "ข้าง", "หลัง", "ยืนในเกม", "ยืนในเกม (ข้าง)"], 6, 400, 600))
    parts.append(text_block(W, [("ข้อพับ (ภาพใกล้): ซ้าย = ผิวแบบธรรมดา (LBS)  ขวา = + กระดูกช่วย + ท่าแก้ (ตัวเลขความคลาดอยู่ด้านล่าง)", ACC)], 38))
    parts.append(grid(["posez_elbow120_lbs", "posez_elbow120_full", "posez_overhead_lbs", "posez_overhead_full",
                       "posez_knee120_lbs", "posez_knee120_full", "posez_rifle_lbs", "posez_rifle_full"],
                      ["งอศอก ก่อน", "งอศอก หลัง", "ยกแขน ก่อน", "ยกแขน หลัง", "งอเข่า ก่อน", "งอเข่า หลัง", "เล็งปืน ก่อน", "เล็งปืน หลัง"],
                      8, 300, 450, crop=False))
    parts.append(text_block(W, [("ท่าจากไฟล์ท่าเดิมของเกม (79 ท่า เล่นได้โดยไม่ต้องแปลง ; ท่าชก/แทงบางท่ายังบิดข้อมือเกิน รอแก้ที่โครง)", ACC)], 40))
    parts.append(grid(["clip_idle_0", "clip_walk_1", "clip_run_2", "clip_fire_2", "clip_bash_0_2", "clip_flinch_1", "clip_die_back_4",
                       "clip_die_spin_4"], ["ยืนพัก", "เดิน", "วิ่ง", "ยิง", "กระแทก", "สะดุ้ง", "ล้มหงาย", "ล้มหมุน"], 8, 300, 420))
    lines = []
    if lods:
        lines.append("จำนวนสามเหลี่ยม (งบตัวเปล่า):  สูง %s (≤24,000)   กลาง %s (≤16,000)   ต่ำ %s (≤9,000)   ต่ำสุด %s (≤5,000)   วาด 1 ครั้งต่อระดับ" % (
            f"{lods['hi']['tris']:,}", f"{lods['mid']['tris']:,}", f"{lods['lo']['tris']:,}", f"{lods['min']['tris']:,}"))
        lines.append("กระดูก %d ชิ้น (เกม 23 + ช่วย 10)   กล้ามเนื้อ %d มัด (%d เส้นใย)   ท่าแก้ %d ท่า (เฉพาะระดับสูง/กลาง)   ระดับต่ำสุดไม่มีงานเพิ่มต่อเฟรม" % (
            N["bones_total"], N["muscles_total"], N["muscle_fibres_total"], len(N["blend_shapes"])))
        t = N.get("time_s", {})
        lines.append("สร้างทั้งตัวใหม่ได้ใน %.0f นาที (สร้าง 2 รอบได้ไฟล์ตรงกันทุกไบต์)   เมชปั้นละเอียด %s สามเหลี่ยม (ผิวปิดสนิทชิ้นเดียว ไม่มีรู)" % (
            t.get("total_s", 0) / 60.0, f"{N['sculpt'].get('tris', N['sculpt'].get('marching_cubes_tris', 0)):,}"))
    if ev:
        k = ev.get("knee_120", {})
        a = ev.get("arm_down_10", {})
        if k and a:
            lines.append(("ความคลาดจากผิวเป้าหมาย (แบบจำลองกล้ามเนื้อ ยิ่งน้อยยิ่งดี): เข่างอ 120° %.1f เหลือ %.1f มม.   แขนห้อยข้างตัว %.1f เหลือ %.1f มม." % (
                k["min_lbs"]["mean_mm"], k["hi_correctives"]["mean_mm"], a["min_lbs"]["mean_mm"], a["hi_correctives"]["mean_mm"]), GOOD))
    for ln in NOT_GOOD:
        lines.append((ln, BAD))
    lines.append(("ยังไม่ได้ทำ: ชุดทหาร หมวก ปืน, พื้นผิว/แผนที่ผิวละเอียด (ขั้น 2)", BAD))
    parts.append(text_block(W, lines, 36))
    ov = stack(parts, W)
    ov.save(os.path.join(OUT, "sheet_overview.png"))
    # ---------------- 2) ชั้น ----------------
    lay = stack([title(W, "ชั้นของร่างกาย: โครงกระดูก > กล้ามเนื้อ > ผิว (ท่า A ที่ใช้ปั้น)"),
                 grid(["layer_skeleton_000", "layer_muscles_bones_000", "layer_muscles_000", "layer_skin_000",
                       "layer_skeleton_180", "layer_muscles_bones_180", "layer_muscles_180", "layer_skin_180"],
                      ["โครงกระดูก หน้า", "กล้าม+กระดูก หน้า", "กล้ามเนื้อ หน้า", "ผิว หน้า", "โครงกระดูก หลัง", "กล้าม+กระดูก หลัง",
                       "กล้ามเนื้อ หลัง", "ผิว หลัง"], 4, 600, 900)], W)
    lay.save(os.path.join(OUT, "sheet_layers.png"))
    # ---------------- 3) หมุนรอบตัว + ใกล้ ----------------
    tt = stack([title(W, "ผิว: รอบตัว (ท่า A) / ท่ายืนในเกม / ระยะใกล้"),
                grid(["turn_000", "turn_045", "turn_090", "turn_180"], ["หน้า", "เฉียง 45°", "ข้าง", "หลัง"], 4, 600, 900),
                grid(["idle_000", "idle_030", "idle_090", "idle_180"], ["ยืนในเกม หน้า", "เฉียง", "ข้าง", "หลัง"], 4, 600, 900),
                grid(["close_head", "close_head_side", "close_torso", "close_back"], ["หน้า", "หน้า ด้านข้าง", "ลำตัว", "หลัง"], 4, 600, 900,
                     crop=False)], W)
    tt.save(os.path.join(OUT, "sheet_turntable.png"))
    # ---------------- 4) ท่าทดสอบ ก่อน/หลัง ----------------
    rows = [title(W, "ท่าทดสอบการพับข้อ: เทียบ 4 แบบ",
                  "ซ้ายสุด = แบบที่ระดับต่ำสุด (min) ใช้   ที่ 2 = ระดับต่ำ (lo)   ที่ 3 = ระดับสูง/กลาง (hi/mid)   ขวาสุด = เป้าหมายจากแบบจำลองกล้ามเนื้อ")]
    pnames = {"elbow120": "งอศอก 120°", "knee120": "งอเข่า 120°", "overhead": "ยกแขนเหนือหัว", "squat": "ย่อตัว (นั่งยอง)",
              "rifle": "ท่าเล็งปืน (จากคลิป fire)", "idle": "ยืนพัก (จากคลิป idle)"}
    for pn, cap in pnames.items():
        rows.append(text_block(W, [(cap, ACC)], 42))
        rows.append(grid(["pose_%s_lbs" % pn, "pose_%s_helpers" % pn, "pose_%s_full" % pn, "pose_%s_muscles" % pn],
                         ["ผิวแบบเดิม (LBS)", "+ กระดูกช่วย", "+ ท่าแก้ (blend shape)", "กล้ามเนื้อในท่านี้"], 4, 600, 760))
        if os.path.exists(os.path.join(RAW, "posez_%s_lbs.png" % pn)):
            rows.append(grid(["posez_%s_lbs" % pn, "posez_%s_helpers" % pn, "posez_%s_full" % pn, "posez_%s_muscles" % pn],
                             ["ใกล้: แบบเดิม", "ใกล้: + กระดูกช่วย", "ใกล้: + ท่าแก้", "ใกล้: กล้ามเนื้อ"], 4, 600, 760, crop=False))
    stack(rows, W).save(os.path.join(OUT, "sheet_poses.png"))
    # ---------------- 5) คลิป ----------------
    clips = [("idle", 4, "ยืนพัก"), ("walk", 6, "เดิน"), ("run", 6, "วิ่ง"), ("fire", 6, "ยิง"), ("bash_0", 6, "กระแทกด้วยพานท้าย"),
             ("flinch", 4, "สะดุ้งโดนยิง"), ("die_back", 5, "ล้มหงาย"), ("die_fwd", 5, "ล้มคว่ำ"), ("die_spin", 5, "ล้มหมุน")]
    rows = [title(W, "ท่าจากไฟล์ท่าของเกม (humanoid.res) บนทหาร ระดับสูง + ตัวขับกระดูกช่วย/ท่าแก้")]
    for c, n, cap in clips:
        rows.append(text_block(W, [(cap + "  (" + c + ")", ACC)], 38))
        rows.append(grid(["clip_%s_%d" % (c, i) for i in range(n)], [""] * n, 6, 400, 520, cap_h=4))
    stack(rows, W).save(os.path.join(OUT, "sheet_clips.png"))
    # ---------------- 6) ระดับรายละเอียด ----------------
    if bud:
        caps = []
        for lv in ("hi", "mid", "lo", "min"):
            b = bud.get(lv, {})
            caps.append("%s: %s สามเหลี่ยม, %s draw" % ({"hi": "สูง", "mid": "กลาง", "lo": "ต่ำ", "min": "ต่ำสุด"}[lv],
                                                       f"{b.get('mesh_tris', 0):,}", b.get("draws", "?")))
        stack([title(W, "4 ระดับรายละเอียด (ระหว่างเดิน)"),
               grid(["budget_hi", "budget_mid", "budget_lo", "budget_min"], caps, 4, 600, 900)], W).save(os.path.join(OUT, "sheet_lods.png"))
    fat_sheet(W)
    checks_sheet(W)
    print("sheets written")


def fat_sheet(W):
    """เทียบ FAT_LEVEL 0.8 / 1.0 / 1.3 : กล้อง แสง วัสดุ และกรอบภาพเดียวกัน"""
    tags = [("fat080", "ผอม-ฟิต", 0.8), ("fat100", "ปกติ", 1.0), ("fat130", "ท้วม", 1.3)]
    if not all(os.path.exists(os.path.join(RAW, "fat_%s_front.png" % t)) for t, _, _ in tags):
        return
    pw = W // 3
    rows = [title(W, "เลือกระดับไขมัน (FAT_LEVEL): ผอม-ฟิต / ปกติ / ท้วม",
                  "กล้อง แสง และขนาดภาพเท่ากันทุกช่อง ; % ไขมันเป็นค่าประมาณจากปริมาตรชั้นไขมันของแบบ (ไม่ใช่การวัดคนจริง)")]
    hdr = Image.new("RGB", (W, 190), BG)
    d = ImageDraw.Draw(hdr)
    for i, (t, cap, lv) in enumerate(tags):
        fp = os.path.join(DATA, "fat_%s.json" % t)
        fe = json.load(open(fp)) if os.path.exists(fp) else {}
        text_c(d, (i * pw, 6), pw, "%s  (FAT_LEVEL %.1f)" % (cap, lv), font(56, True), ACC)
        text_c(d, (i * pw, 76), pw, "ไขมันราว %s %%" % fe.get("body_fat_pct", "?"), font(48, True), FG)
        text_c(d, (i * pw, 132), pw, "มวลราว %s กก. · BMI ราว %s" % (fe.get("mass_kg", "?"), fe.get("bmi", "?")), font(36), DIM)
    rows.append(hdr)
    for view, cap, ph in (("front", "ด้านหน้า", 1000), ("side", "ด้านข้าง", 1000), ("back", "ด้านหลัง", 1000),
                          ("torso", "ลำตัว (เฉียง)", 760), ("face", "หน้า (เฉียง 30°)", 760)):
        ims = union_row(["fat_%s_%s" % (t, view) for t, _, _ in tags], pw - 8, ph - 8)
        row = Image.new("RGB", (W, ph + 50), BG)
        d = ImageDraw.Draw(row)
        for i, im in enumerate(ims):
            row.paste(im, (i * pw + 4, 4))
            text_c(d, (i * pw, ph), pw, cap, font(34, True), DIM)
        rows.append(row)
    stack(rows, W).save(os.path.join(OUT, "sheet_fat_levels.png"))


def checks_sheet(W):
    """ภาพตรวจของช่างปั้น: หน้า hi/min, ไหปลาร้า, ขาหนีบ/สะโพก, รักแร้, ศอก 0-150°, เข่า, ย่อตัว"""
    if not os.path.exists(os.path.join(RAW, "face_hi_000.png")):
        return
    rows = [title(W, "ภาพตรวจผิว (ขั้น 1b)", "หน้าแบบละเอียด (hi) และแบบเบาสุด (min), จุดที่เคยเป็นรู/โพรง, ศอกและเข่าที่งอ")]
    rows.append(grid(["face_hi_000", "face_hi_035", "face_hi_090", "face_hi_game"],
                     ["หน้า hi ตรง", "หน้า hi เฉียง", "หน้า hi ข้าง", "hi ระยะเกม"], 4, 600, 700, crop=False))
    rows.append(grid(["face_min_000", "face_min_035", "face_min_090", "face_min_game"],
                     ["หน้า min ตรง", "หน้า min เฉียง", "หน้า min ข้าง", "min ระยะเกม"], 4, 600, 700, crop=False))
    rows.append(grid(["check_collar_000", "check_collar_035", "check_armpit_045", "check_armpit_090"],
                     ["ไหปลาร้า", "ไหปลาร้า เฉียง", "รักแร้ ยกแขน", "รักแร้ ยกแขน (ข้าง)"], 4, 600, 700, crop=False))
    rows.append(grid(["check_groin_000", "check_groin_035", "check_hips_090", "check_hips_180"],
                     ["ขาหนีบ/สะโพก หน้า", "เฉียงต่ำ", "สะโพก ข้าง", "ก้น หลัง"], 4, 600, 700, crop=False))
    rows.append(grid(["check_elbow_%03d" % a for a in (0, 30, 60, 90, 120, 150)],
                     ["ศอก %d°" % a for a in (0, 30, 60, 90, 120, 150)], 6, 400, 520, crop=False))
    rows.append(grid(["check_knee120_000", "posez_knee120_full", "check_squat_000", "check_squat_090"],
                     ["เข่า 120° หน้า", "เข่า 120° ข้าง (ใกล้)", "ย่อตัว หน้า", "ย่อตัว ข้าง"], 4, 600, 700, crop=False))
    stack(rows, W).save(os.path.join(OUT, "sheet_checks.png"))


if __name__ == "__main__":
    main()
