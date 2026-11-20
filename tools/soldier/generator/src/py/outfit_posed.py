# เกตท่าของเกมสำหรับชุด (ใหม่ 0.14 ข้อ 4): ทุก step เฟรมของคลิปทหาร (ref/soldier_clips.json: เดิน วิ่งเหยาะ วิ่ง เล็ง ต่อย ฟัน
#   บรรจุกระสุน โดนยิง ล้ม) ผิวตัวเปล่า hi/mid ส่วนที่ผ้าคลุม (ห่างขอบผ้าเกิน HEM_MM) ต้องไม่โผล่พ้นผิวผ้าของระดับเดียวกัน
#   (นับเฉพาะผ้าส่วนร่างกายเดียวกัน และข้ามจุดที่ผ้าพับทับยังคลุม: วิธีเดียวกับ inner_posed.poke)
#   + ชิ้นอุปกรณ์ (เข็มขัด หัวเข็มขัด กระเป๋า) จมในผ้าลำตัวได้ไม่เกิน GEAR_MM (แขน/ขาที่แนบเข้ามา = ส่วนอื่น ไม่นับ เหมือน poke)
#   ชั้นในของแผล (เนื้อ ≥ 1 มม. ใต้ผิวตัวเปล่า) จึงอยู่ใต้ผ้าด้วยทุกท่า
import json
import numpy as np
import inner_posed as IP
import garments as GM
import outfits as OF
from inner_layers import SkinDepth

POKE_MM = 0.5
HEM_MM = 20.0            # ผิวใกล้ขอบผ้า (คอ ข้อมือ) ไม่นับ: ขอบผ้ายกพ้นผิวได้ตอนก้มคอ/งอข้อมือ เหมือนเสื้อจริง (~1 สามเหลี่ยม hi)
GEAR_MM = {"belt": 3.0, "buckle": 3.0, "pouch": 10.0, "flap": 10.0}
LEVELS = ("hi", "mid")
STEP = {"hi": 2, "mid": 4}     # ทุก 2 เฟรม (hi) / 4 เฟรม (mid) ของทุกคลิป


def _main(m):
    nb = m["n_cloth"]
    F = m["F"][np.all(m["F"] < nb, axis=1)]
    Fw = OF.weld(m["V"][:nb], F)
    pf = np.round(m["cus"][:nb, 3]).astype(np.int64)[Fw]
    return {"V": m["V"][:nb], "F": Fw, "B": m["bones"][:nb].astype(np.int64), "W": m["weights"][:nb].astype(np.float64),
            "tri_part": np.where(pf[:, 1] == pf[:, 2], pf[:, 1], pf[:, 0])}


def run(ctx, built, out, step=2):
    clips = json.load(open(IP.clip_path(out)))["clips"]
    fields = ctx["_fields"]
    rep = {"step": dict(STEP), "gate": "skin above cloth <= %.1f mm (%.0f mm from the hems), gear in cloth "
           "<= belt %.0f / pouch %.0f mm" % (POKE_MM, HEM_MM, GEAR_MM["belt"], GEAR_MM["pouch"]), "levels": {}}
    fails = []
    for lv in LEVELS:
        frames = IP.pose_frames(clips, STEP[lv])
        bare, m = ctx["bare"][lv], built[lv]
        sk = _main(m)
        s = GM.hem_s(fields(bare["V"]))
        sel = s > HEM_MM / 1000.0
        P, B, W = bare["V"][sel], bare["bones"][sel].astype(np.int64), bare["weights"][sel].astype(np.float64)
        part = np.round(bare["cus"][sel, 3]).astype(np.int64)
        gears = m["gear"]
        ga = np.concatenate([np.arange(a, b) for _, a, b in gears])
        gk = np.concatenate([[nm] * (b - a) for nm, a, b in gears])
        GB, GW = m["bones"][ga].astype(np.int64), m["weights"][ga].astype(np.float64)
        worst = np.full(len(P), -np.inf)
        wf = [""] * len(P)
        gw = {k: (-np.inf, "") for k in GEAR_MM}
        lim = POKE_MM / 1000.0
        for cn, fr, M in frames:
            Vp = IP.skin_pts(sk["V"], sk["B"], sk["W"], M)
            Q = np.vstack([IP.skin_pts(P, B, W, M), IP.skin_pts(m["V"][ga], GB, GW, M)])
            sd, _, tb = SkinDepth(Vp, sk["F"]).query(Q, with_tri=True)
            d, sg, tg = sd[:len(P)], sd[len(P):], tb[len(P):]
            d = np.where(sk["tri_part"][tb[:len(P)]] == part, d, -np.inf)
            cand = np.flatnonzero(d > lim)
            if len(cand):
                # ผ้าที่พับทับยังคลุมอยู่ (ข้อพับ รักแร้): winding ของผิวผ้าตามท่า >= 0.5 = มองไม่เห็น ไม่นับ
                cov = IP.winding(Vp, sk["F"], Q[cand]) >= 0.5
                d[cand[cov]] = -np.inf
            up = d > worst
            worst = np.where(up, d, worst)
            for i in np.flatnonzero(up & (d > lim)):
                wf[i] = "%s frame %d" % (cn, fr)
            sg = np.where(sk["tri_part"][tg] == 0, sg, np.inf)      # เฉพาะผ้าลำตัวที่อุปกรณ์ติดอยู่ (แขน/ขาแนบ = ส่วนอื่น ไม่นับ)
            for nm in gw:
                mk = gk == nm
                if mk.any():
                    v = float(-sg[mk].min()) * 1000.0
                    if v > gw[nm][0]:
                        gw[nm] = (v, "%s frame %d" % (cn, fr))
        mx = float(worst.max()) * 1000.0
        over = int((worst > lim).sum())
        i = int(np.argmax(worst))
        r = {"frames": len(frames), "skin_verts": int(sel.sum()), "skin_above_cloth_max_mm": round(max(mx, -99.0), 3),
             "verts_over": over, "worst": wf[i] if over else "",
             "gear_in_cloth_mm": {k: round(v[0], 2) for k, v in gw.items() if v[0] > -np.inf},
             "gear_worst": {k: v[1] for k, v in gw.items() if v[0] > -np.inf}}
        rep["levels"][lv] = r
        ob = np.flatnonzero(worst > lim)
        rep.setdefault("points", []).extend([[float(x) for x in pi] + [float(worst[i] * 1000.0)]
                                             for pi, i in zip(fields(P[ob])[0], ob)])
        if over:
            fails.append("%s skin above cloth %.2f mm (%d verts, %s)" % (lv, mx, over, wf[i]))
        for k, (v, w) in gw.items():
            if v > GEAR_MM[k]:
                fails.append("%s %s %.1f mm in the cloth (%s)" % (lv, k, v, w))
        OF.log("posed %s (%d frames): skin above cloth max %.2f mm (%d verts over %.1f) ; gear %s" % (
            lv, len(frames), mx, over, POKE_MM, {k: round(v[0], 1) for k, v in gw.items()}))
    rep["pass"] = not fails
    rep["fails"] = fails
    return rep
