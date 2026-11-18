# แผ่นสรุปร่างหลากหลาย (คำบรรยายภาษาไทย): ทหารขั้น 1c + ร่างทั้งหมด เคียงกัน (หน้า ข้าง หน้าใกล้) + แถว LOD ของแต่ละร่าง
#   /usr/bin/python3 vsheet.py --vroot <โฟลเดอร์ variants> [--base <โฟลเดอร์สร้างทหารฐาน>] [--names m2,m3,f1,f2]
#   ภาพมาจาก vrender.gd (<โฟลเดอร์สร้าง>/out/renders/sheet/<ชื่อ>_<มุม>.png)
import argparse
import json
import os
import numpy as np
from PIL import Image, ImageDraw
from sheet import font, fit, bbox_of, text_c, title, stack, text_block, BG, FG, ACC, DIM, GOOD, BAD


def _load(p):
    return Image.open(p).convert("RGB") if os.path.exists(p) else Image.new("RGB", (640, 960), (60, 20, 20))


def _union(paths, pw, ph, pad=0.04):
    ims = [_load(p) for p in paths]
    bb = np.array([bbox_of(im) for im in ims])
    x0, y0, x1, y1 = bb[:, 0].min(), bb[:, 1].min(), bb[:, 2].max(), bb[:, 3].max()
    p = int(max(x1 - x0, y1 - y0) * pad)
    box = (max(0, x0 - p), max(0, y0 - p), min(ims[0].width, x1 + p), min(ims[0].height, y1 + p))
    return [fit(im.crop(box), pw, ph) for im in ims]


def _row(panels, pw, ph, caps=None, cap_h=0):
    img = Image.new("RGB", (pw * len(panels), ph + cap_h), BG)
    d = ImageDraw.Draw(img)
    for i, p in enumerate(panels):
        img.paste(p, (i * pw + (pw - p.width) // 2, 0))
        if caps:
            text_c(d, (i * pw, ph + 4), pw, caps[i], font(30), DIM)
    return img


def _label_row(heads, subs, pw, h=160):
    img = Image.new("RGB", (pw * len(heads), h), (30, 33, 38))
    d = ImageDraw.Draw(img)
    for i, (a, b) in enumerate(zip(heads, subs)):
        text_c(d, (i * pw, 4), pw, a, font(40, True), ACC)
        for j, ln in enumerate(b):
            text_c(d, (i * pw, 54 + 33 * j), pw, ln, font(29), FG)
    return img


def _band(w, txt, h=54):
    img = Image.new("RGB", (w, h), (40, 44, 50))
    ImageDraw.Draw(img).text((24, 6), txt, font=font(38, True), fill=FG)
    return img


def _json(p):
    return json.load(open(p)) if os.path.exists(p) else {}


def _game_bytes(godot_dir):
    tot = 0
    for f in ("body_hi.res", "body_mid.res", "body_lo.res", "body_min.res", "skin.res", "rig.tscn"):
        p = os.path.join(godot_dir, f)
        tot += os.path.getsize(p) if os.path.exists(p) else 0
    return tot


SHORT = {"m2": ("ชาย 1.86 ม.", ["ผิวน้ำตาลเข้ม ผมเกรียนดำ", "กรามกว้างคางยาว คิ้วหนา ตาเล็ก", "ร่างใหญ่ ท้องหนา (BMI ~28)"]),
         "m3": ("ชาย 1.70 ม.", ["ผิวขาว ผมสั้นน้ำตาลยกหน้า", "หน้าแคบยาว จมูกยาว หูกาง", "ร่างผอมเกร็ง ไม่มีซิกซ์แพ็ก"]),
         "f1": ("หญิง 1.60 ม.", ["ผิวแทน หน้าแบบคนไทย/อาเซียน", "ผมดำตรงมวยสูง สะโพกผาย", "เสื้อกล้ามหลังไขว้สีทราย"]),
         "f2": ("หญิง 1.73 ม.", ["ผิวน้ำตาลเข้ม ผมหยิกฟู", "โหนกแก้มกว้าง ตากลมโต", "ร่างนักกีฬาตรง เสื้อสีเสจ"]),
         "base": ("ชาย 1.78 ม. (เดิม)", ["ทหารขั้น 1c ที่มีในเกมตอนนี้", "ผิวแทน ผมเกรียน", "มี blend shape 14 ตัว"])}
GATES = ("G1", "G2", "G3", "G4", "G5", "G6", "G8", "G9", "G10", "G11", "G12")


def _grey64(path, pw, ph):
    """หน้าตรงย่อเหลือ 64 พิกเซล สีเทา แล้วขยายกลับ (เทียบว่าแยกหน้าแต่ละคนออกไหม)"""
    im = _load(path).crop((120, 160, 520, 760)).convert("L")
    im = im.resize((64, 96), Image.BILINEAR).resize((pw, int(pw * 1.5)), Image.NEAREST).convert("RGB")
    return fit(im, pw, ph)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--vroot", required=True)
    ap.add_argument("--base", default="")
    ap.add_argument("--names", default="m2,m3,f1,f2")
    ap.add_argument("--base-gates", default="", help="gates.json ของทหารฐาน (ผลสร้างฐานเหมือนขั้น 1c ทุกไบต์)")
    a = ap.parse_args()
    names = [n for n in a.names.split(",") if n]
    base = a.base or os.path.join(a.vroot, "gen")
    figs = [("base", base)] + [(n, os.path.join(a.vroot, n)) for n in names]
    rd = {n: os.path.join(r, "out", "renders", "sheet") for n, r in figs}
    pw = 400
    W = pw * len(figs)
    heads = [("ทหารเดิม 1.78 ม." if n == "base" else n + " · " + SHORT[n][0]) for n, _ in figs]
    subs = [SHORT[n][1] for n, _ in figs]
    # ข้อมูลต่อร่าง
    facts = []
    for n, r in figs:
        num = _json(os.path.join(r, "out", "data", "numbers.json"))
        an = _json(os.path.join(r, "out", "data", "anthropometry.json"))
        gt = _json(os.path.join(r, "out", "data", "gates.json"))
        if not gt and n == "base" and a.base_gates:
            gt = _json(a.base_gates)
        fe = num.get("fat", {})
        gb = _game_bytes(os.path.join(r, "out", "godot"))
        ok = [g for g in GATES if g in gt]
        okp = all(gt[g].get("pass", gt[g].get("pass_depth", False)) if g != "G2" else gt[g].get("pass_depth") for g in ok)
        facts.append((n, fe, an, gb, ok, okp))
    parts = [title(W, "ทหารราบ: ร่างหลากหลาย 4 แบบ (รอบปรับ) เทียบกับทหารขั้น 1c",
                   "ไฟบนแบบในเกม + เชดเดอร์ผิวของขั้นปั้น · ท่ากางแขน (ท่าผูก) · ทุกภาพในแถวเดียวกันใช้กล้องเดียวกัน (เทียบส่วนสูงได้)"),
             _label_row(heads, subs, pw)]
    ph = 760
    parts.append(_band(W, "หน้าตรง"))
    parts.append(_row(_union([os.path.join(rd[n], n + "_front.png") for n, _ in figs], pw, ph), pw, ph))
    parts.append(_band(W, "ด้านข้าง"))
    parts.append(_row(_union([os.path.join(rd[n], n + "_side.png") for n, _ in figs], pw, ph), pw, ph))
    parts.append(_band(W, "หน้าใกล้ (ตรง / เอียง 35° / ด้านข้าง)"))
    for v in ("face", "face34", "face_side"):
        ps = [fit(_load(os.path.join(rd[n], n + "_" + v + ".png")).crop((0, 60, 640, 900)), pw, int(pw * 1.31))
              for n, _ in figs]
        parts.append(_row(ps, pw, int(pw * 1.31)))
    parts.append(_band(W, "หน้าเดียวกันที่ 64 พิกเซล สีเทา (แยกคนออกจากรูปหน้า ไม่ใช่สีผิว)"))
    parts.append(_row([_grey64(os.path.join(rd[n], n + "_face.png"), pw, 600) for n, _ in figs], pw, 600))
    parts.append(_band(W, "หน้าใกล้ระดับ lo และ min (มือถือใช้ทุกระยะ: ตายังเปิด)"))
    for lv in ("lo", "min"):
        ps = [fit(_load(os.path.join(rd[n], "%s_lodf_%s.png" % (n, lv))).crop((0, 60, 640, 900)), pw, int(pw * 1.31))
              for n, _ in figs]
        parts.append(_row(ps, pw, int(pw * 1.31)))
    parts.append(_band(W, "ด้านหลัง และท่ายืนในเกม (idle)"))
    parts.append(_row(_union([os.path.join(rd[n], n + "_back.png") for n, _ in figs], pw, 620), pw, 620))
    parts.append(_row(_union([os.path.join(rd[n], n + "_idle.png") for n, _ in figs], pw, 620), pw, 620))
    # ตัวเลข
    caps = []
    for n, fe, an, gb, ok, okp in facts:
        st = an.get("stature", {}).get("cm")
        caps.append(["สูง %s ซม. · ไขมัน %s%%" % (st, fe.get("body_fat_pct")),
                     "มวล %s กก. · BMI %s" % (fe.get("mass_kg"), fe.get("bmi")),
                     "อก %s เอว %s สะโพก %s" % tuple(an.get(k, {}).get("cm") for k in ("chest", "waist", "hips")),
                     "ไฟล์เกม %.2f MB" % (gb / 1e6) + (" (มี blend shape)" if n == "base" else ""),
                     ("เกตผ่านครบ" if okp else "เกตยังไม่ผ่าน") + " " + ",".join(g[1:] for g in ok)])
    img = Image.new("RGB", (W, 40 + 34 * 5), (30, 33, 38))
    d = ImageDraw.Draw(img)
    for i, c in enumerate(caps):
        for j, ln in enumerate(c):
            col = (GOOD if "ผ่านครบ" in ln else BAD) if j == 4 else FG
            text_c(d, (i * pw, 16 + 34 * j), pw, ln, font(27), col)
    parts.append(img)
    parts.append(text_block(W, [
        "ทุกร่างใช้โครงเกม 23 กระดูกเดิม (สัดส่วนเดียวกัน ย่อ/ขยายตามส่วนสูง) + กระดูกช่วย 10 ชิ้น: ท่าทุกท่าในเกมใช้ได้ทันที",
        "ร่างใหม่ไม่มี blend shape (ประหยัดขนาด ~1 MB ต่อร่าง) ; ข้างในยังปั้นจากโครงกระดูก -> กล้าม -> ไขมัน -> ผิว เหมือนเดิม",
        "รอบปรับ: แก้ม/กรามเรียบ (ไม่เป็นคราบ) · ขอบเสื้อ/กางเกงตัดตามเส้นจริง · ตาระดับไกลเปิดสองโทน · หน้าแต่ละคนต่างกัน",
        ("เสื้อกล้ามและกางเกงยังเป็นสีทาบนผิว (ชั่วคราว ก่อนมีชุดทหารจริง) ; ไม่มีอวัยวะเพศ (เชิงกรานกลาง ๆ แบบร่างเดิม)", DIM)],
        size=32))
    out = os.path.join(a.vroot, "sheet_variants.png")
    stack(parts, W).save(out)
    print("wrote", out)
    # แถว LOD ของแต่ละร่าง
    for n, r in figs:
        if n == "base":
            continue
        num = _json(os.path.join(r, "out", "data", "numbers.json"))
        lods = num.get("lods", {})
        cap = ["%s %s สามเหลี่ยม" % (lv, "{:,}".format(lods.get(lv, {}).get("tris", 0))) for lv in ("hi", "mid", "lo", "min")]
        p2 = []
        for pre, hh in (("lod_", 900), ("lodc_", 700), ("lodf_", 560), ("lodb_", 560), ("lodg_", 520)):
            p2.append(_row(_union([os.path.join(rd[n], "%s_%s%s.png" % (n, pre, lv)) for lv in ("hi", "mid", "lo", "min")],
                                  480, hh), 480, hh, cap if pre == "lod_" else None, 44 if pre == "lod_" else 0))
        sub = "ทั้งตัว / ครึ่งบนใกล้ / หน้าใกล้ / หลัง / ระยะเกม · ไฟบนของเกม · lo และ min คิดแสงต่อจุดยอด (แบบในเกม)"
        sh = stack([title(1920, "ระดับรายละเอียด (LOD) ของร่าง %s · %s" % (n, SHORT[n][0]), sub)] + p2, 1920)
        o2 = os.path.join(a.vroot, "sheet_lods_%s.png" % n)
        sh.save(o2)
        print("wrote", o2)


if __name__ == "__main__":
    main()
