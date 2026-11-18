# ตรวจชั้นในของแผลในท่าของเกม: ชั้นเนื้อ/กระดูกต้องอยู่ใต้ผิว hi ทุกท่าที่ทหารใช้ (ไม่โผล่พ้นผิว)
#   ท่าจาก ref/clips.json ทุก --step เฟรม ; ข้อมือแบบเกม (SoldierFigure.ease_wrists: ข้อมือ+มือรวมที่ข้อมือ บิด/พับไม่เกิน
#   45° มือไม่หมุน) ; โครง rig.fk + กระดูกช่วย ; ผิว/ชั้นในผูกด้วยน้ำหนักในไฟล์ bin (ร่างแบบอื่นไม่มีท่าแก้ = แบบเกมพอดี)
#   ระยะมีเครื่องหมายถึงสามเหลี่ยมผิวที่ใกล้สุด: นับเฉพาะจุดที่สามเหลี่ยมนั้นเป็นส่วนร่างกายเดียวกัน (CUSTOM0.w ของผิว)
#   (จุดที่ใกล้ผิวของส่วนอื่น = อยู่ในแขน/ขาที่แนบกัน มองไม่เห็นอยู่แล้ว ไม่นับ) ; จุดที่อยู่นอกสามเหลี่ยมนั้นแต่ยังอยู่ในผิว
#   ชั้นอื่นที่พับทับ (ข้อพับ รักแร้ ขาหนีบ: winding number ของผิวตามท่า >= 0.5) = ผิวยังคลุมอยู่ มองไม่เห็น ไม่นับ
#   ร่างแบบอื่นคิดในกรอบ 1.78 ม. (หาร k) แล้วรายงานเป็นมม. จริง -> out/data/inner_posed.json
#   ร่างแบบอื่น: inner_layers.py เลื่อนเนื้อที่โผล่ลงในท่าผูกแล้ว (push_posed) -> เนื้อโผล่เกิน POKE_MM = หยุด ยกเว้นจุดที่
#   โครงผสม (LBS) หมุนระยะลึกของเนื้อสวนนอร์มอลของผิว (A^T n · นอร์มอลท่าผูก < 0: เลื่อนเข้าลึกยิ่งโผล่ เลื่อนออกก็พ้นผิว
#   ในท่าผูก แก้ด้วยการเลื่อนไม่ได้ เจอที่รักแร้ตอนต่อย/แทง) ซึ่งรายงานแยก ; อกหน้าและสะโพกต้องไม่โผล่เลยทุกกรณี
#   กระดูกของร่างแบบอื่น: อกหน้า/สะโพกโผล่ได้ไม่เกินร่างหลัก + BONE_OVER_MM (inner_layers.py กดลงด้วย push_bone)
#   ร่างหลัก: รายงานอย่างเดียว (ชั้นในต้องเหมือนขั้น 1c ทุกไบต์ ; ที่โผล่อยู่ที่บ่าตอนยกแขนสุด)
#   /usr/bin/python3 inner_posed.py [--out DIR] [--step 2]      (~2-3 นาที)
import argparse
import json
import os
import time
import numpy as np
import rig
from inner_layers import read_bin, SkinDepth

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
# ท่าที่ทหารใช้ (SoldierFigure.PLAYER_CLIPS + ENEMY_CLIPS)
CLIPS = ["idle", "walk", "run", "fire", "bash_0", "bash_1", "bash_2", "thrust_0", "thrust_1", "thrust_2", "flinch",
         "flinch_heavy", "die_back", "die_fwd", "die_spin"]
WRIST_MAX = 45.0
POKE_MM = 0.5             # เนื้อโผล่พ้นผิวได้ไม่เกินเท่านี้ (มม.) ในส่วนเดียวกัน
# บริเวณที่ต้องดูเป็นพิเศษ (กรอบ 1.78 ม. ท่าผูก): อก/เต้านม และสะโพก/ก้น
REGIONS = {"chest_front": lambda P: (P[:, 1] > 1.15) & (P[:, 1] < 1.42) & (P[:, 2] > 0.03),
           "hips": lambda P: (P[:, 1] > 0.78) & (P[:, 1] < 1.05) & ((np.abs(P[:, 0]) > 0.10) | (P[:, 2] < -0.03))}
# กระดูกโผล่พ้นผิวในท่า (มม.) ของร่างหลัก (inner_posed.json ของขั้น 1c: ชั้นในร่างหลักเหมือนขั้น 1c ทุกไบต์)
BONE_BASE_MM = {"chest_front": 0.917, "hips": 6.432}
BONE_OVER_MM = 0.5        # ร่างแบบอื่น: กระดูกอกหน้า/สะโพกโผล่เกินร่างหลักได้ไม่เกินเท่านี้


def _clamp_turn(q, deg):
    q = q if q[3] >= 0 else -q
    a = 2 * np.arccos(np.clip(q[3], -1, 1))
    if a <= np.radians(deg) or a < 1e-6:
        return q
    return rig.qslerp(np.array([0, 0, 0, 1.0]), q, np.radians(deg) / a)


def limit_turn(q, tw_max, sw_max):
    """แบบ SoldierFigure.limit_turn: พับ (swing) × บิดรอบแกน Y (twist) แต่ละส่วนไม่เกินองศาที่ให้"""
    tw = np.array([0.0, q[1], 0.0, q[3]])
    n = np.linalg.norm(tw)
    tw = np.array([0, 0, 0, 1.0]) if n < 1e-6 else tw / n
    sw = rig.qmul(q, rig.qinv(tw))
    return rig.qnorm(rig.qmul(_clamp_turn(sw, sw_max), _clamp_turn(tw, tw_max)))


def clip_pose(c, frame):
    p = rig.ident_pose()
    for b in rig.MAIN:
        p["local"][b] = np.array(c["q"][b][frame], float)
    p["pelvis_pos"] = np.array(c["t"]["pelvis"][frame], float) * rig.S
    for sd in "LR":
        p["local"]["wrist" + sd] = limit_turn(rig.qnorm(rig.qmul(p["local"]["wrist" + sd], p["local"]["hand" + sd])),
                                              WRIST_MAX, WRIST_MAX)
        p["local"]["hand" + sd] = np.array([0, 0, 0, 1.0])
    return p


def skin_pts(V, B, W, M):
    """LBS: V (n,3), B/W (n,4), M (nb,4,4) -> (n,3)"""
    Vh = np.c_[V, np.ones(len(V))]
    out = np.zeros((len(V), 3))
    for j in range(B.shape[1]):
        out += W[:, j:j + 1] * np.einsum('nij,nj->ni', M[B[:, j]], Vh)[:, :3]
    return out


def winding(V, F, Q):
    """winding number ของผิวปิด (V, F) ที่จุด Q (van Oosterom-Strackee) : ~1 = ในผิว ~0 = นอกผิว"""
    out = np.zeros(len(Q))
    A, B, C = V[F[:, 0]], V[F[:, 1]], V[F[:, 2]]
    for i, q in enumerate(Q):
        a, b, c = A - q, B - q, C - q
        la, lb, lc = (np.linalg.norm(x, axis=1) for x in (a, b, c))
        num = np.einsum('ij,ij->i', a, np.cross(b, c))
        den = la * lb * lc + np.einsum('ij,ij->i', a, b) * lc + np.einsum('ij,ij->i', b, c) * la + \
            np.einsum('ij,ij->i', c, a) * lb
        out[i] = np.arctan2(num, den).sum() / (2.0 * np.pi)
    return out


def skin_data(data, k):
    """ผิว hi ในกรอบ 1.78 ม.: V, F (ทวนเข็ม), B, W, ส่วนของสามเหลี่ยม (ส่วนที่จุดยอดส่วนใหญ่เป็น เสมอกัน = จุดแรก)"""
    sk = read_bin(os.path.join(data, "body_hi.bin"))
    F = sk["idx"][:, ::-1].astype(np.int64)
    pf = np.round(sk["cus"][:, 3]).astype(np.int64)[F]
    return {"V": sk["pos"].astype(np.float64) / k, "F": F, "B": sk["bones"].astype(np.int64),
            "W": sk["weights"].astype(np.float64), "tri_part": np.where(pf[:, 1] == pf[:, 2], pf[:, 1], pf[:, 0])}


def clip_path(out):
    cp = os.path.join(os.path.dirname(os.path.abspath(out)), "ref", "clips.json")   # ref/ ของโฟลเดอร์สร้าง
    return cp if os.path.exists(cp) else os.path.join(ROOT, "ref", "clips.json")


def pose_frames(clips, step):
    """[(ท่า, เฟรม, เมทริกซ์ผูก (nb,4,4))] ของท่าที่ทหารใช้ ทุก step เฟรม"""
    Gb, _ = rig.fk(rig.bind_pose())
    IB = np.stack([np.linalg.inv(Gb[b]) for b in rig.BONES])
    out = []
    for cn in [c for c in CLIPS if c in clips]:
        c = clips[cn]
        for fr in range(0, int(c["frames"]), step):
            G, _ = rig.fk(clip_pose(c, fr))
            out.append((cn, fr, np.stack([G[b] for b in rig.BONES]) @ IB))
    return out


def poke(sk, M, P, B, W, part, full=False):
    """ระยะที่จุดของชั้นใน (กรอบ 1.78 ม.) โผล่พ้นผิว hi ในท่า M (ม., บวก = โผล่) ; -inf = ใกล้ผิวส่วนอื่น หรือผิวที่พับทับยังคลุม
    คืน (ระยะ, จำนวนที่ใกล้ส่วนอื่น, จำนวนที่ผิวพับคลุม) ; full = คืนนอร์มอลของผิวตามท่าที่จุดใกล้สุดด้วย"""
    Vp = skin_pts(sk["V"], sk["B"], sk["W"], M)
    Q = skin_pts(P, B, W, M)
    s, Nq, tb = SkinDepth(Vp, sk["F"]).query(Q, with_tri=True)
    same = sk["tri_part"][tb] == part
    s = np.where(same, s, -np.inf)
    cand = np.flatnonzero(s > 0)
    ncov = 0
    if len(cand):
        # ผิวทวนเข็ม (ไฟล์เก็บแบบ Godot กลับด้านแล้ว): winding ~1 ในผิว
        cov = winding(Vp, sk["F"], Q[cand]) >= 0.5
        ncov = int(cov.sum())
        s[cand[cov]] = -np.inf
    if full:
        return s, int((~same).sum()), ncov, Nq
    return s, int((~same).sum()), ncov


def push_posed(V, F, B, W, part, data, k, clips, skins, step=2, margin=0.001, bind_margin=0.0015, rounds=4, cap=0.03,
               allow=None):
    """ร่างแบบอื่น: เลื่อนจุดเนื้อ (กรอบที่ส่งออก) ที่โผล่พ้นผิว (หรือลึกไม่ถึง margin) ในท่าใดของเกม ในท่าผูก
    allow (ม. ต่อจุด กรอบที่ส่งออก) = โผล่ได้ถึงเท่านี้แทน margin (inf = ไม่เลื่อน: กระดูกนอกบริเวณที่ดู)
    ทุกท่าที่จุดนั้นโผล่เป็นเงื่อนไขเชิงเส้น g·d >= ระยะที่ขาด (g = A^T n: การหมุนผสมของจุดย้อนนอร์มอลของผิวในท่านั้น ;
    รักแร้ตอนแกว่งแขนนอร์มอลท่าผูกแทบขนานผิว) -> d สั้นสุดโดยฉายทีละเงื่อนไขซ้ำ (Kaczmarz) แล้วคิดใหม่ทุกรอบ ; ไม่เกิน cap
    จุดที่เลื่อนแล้วทะลุอีกด้าน (ใบหู ข้อมือ: ในท่าผูกลึกใต้ผิว skins ไม่ถึง bind_margin) เลื่อนครึ่งเดียว ยังไม่ได้ก็ไม่เลื่อน
    คืน (V, จำนวนจุดที่เลื่อน, ระยะเลื่อนมากสุด ม.)"""
    sk = skin_data(data, k)
    frames = pose_frames(clips, step)
    n = len(V)
    V = np.array(V, np.float64)
    total = np.zeros(n)
    moved = np.zeros(n, bool)
    for _ in range(rounds):
        cons = {}                                     # จุด -> [(ระยะที่ขาด, g)] ในกรอบ 1.78 ม.
        for _cn, _fr, M in frames:
            s, _, _, Nq = poke(sk, M, V / k, B, W, part, full=True)
            need = s + margin / k if allow is None else s - allow / k
            idx = np.flatnonzero(need > 0)
            if len(idx) == 0:
                continue
            A = sum(W[idx, j, None, None] * M[B[idx, j], :3, :3] for j in range(B.shape[1]))
            g = np.einsum('nji,nj->ni', A, Nq[idx])
            for i, r, gi in zip(idx, need[idx], g):
                cons.setdefault(int(i), []).append((float(r), gi))
        if not cons:
            break
        ids = np.array(sorted(cons))
        D = np.zeros((len(ids), 3))
        for row, i in enumerate(ids):
            d = np.zeros(3)
            for _it in range(20):
                worst = 0.0
                for r, gi in cons[i]:
                    gg = float(gi @ gi)
                    if gg < 1e-6:
                        continue
                    lack = r - float(gi @ d)
                    if lack > 1e-7:
                        d += lack * gi / max(gg, 0.0625)
                        worst = max(worst, lack)
                if worst < 1e-6:
                    break
            D[row] = -d * k                            # เลื่อนเข้า: ลบทิศที่พาออก (กรอบที่ส่งออก)
        lens = np.linalg.norm(D, axis=1)
        room = np.maximum(cap - total[ids], 0.0)
        D *= np.minimum(1.0, room / np.maximum(lens, 1e-12))[:, None]
        for _half in range(3):
            ok = np.ones(len(ids), bool)
            for sd in skins:
                ok &= sd.query(V[ids] + D)[0] <= -bind_margin
            if ok.all():
                break
            D[~ok] *= 0.5 if _half < 2 else 0.0
        V[ids] += D
        total[ids] += np.linalg.norm(D, axis=1)
        moved[ids[np.linalg.norm(D, axis=1) > 0]] = True
    return V, int(moved.sum()), float(total.max())


def push_bone(V, B, W, part, data, k, clips, skins, step=2):
    """ร่างแบบอื่น: กดจุดกระดูก (ชิ้นแข็ง) ในอกหน้าและสะโพกที่โผล่ในท่าใดของเกมเกินร่างหลัก (BONE_BASE_MM − 0.1 มม.) ลงในท่าผูก
    เฉพาะจุดในสองบริเวณนั้น ; ท่าผูกยังลึก >= 2.5 มม. ใต้ผิว hi/mid ; คืน (V, จำนวนจุดที่เลื่อน, ระยะเลื่อนมากสุด ม.)"""
    V = np.array(V, np.float64)
    P = V / k
    allow = np.full(len(V), np.inf)
    for r, f in REGIONS.items():
        m = f(P)
        allow[m] = np.minimum(allow[m], (BONE_BASE_MM[r] - 0.1) / 1000.0)
    sel = np.flatnonzero(np.isfinite(allow))
    if len(sel) == 0:
        return V, 0, 0.0
    Vs, nmv, dmax = push_posed(V[sel], None, B[sel], W[sel], part[sel], data, k, clips, skins, step=step,
                               bind_margin=0.0025, cap=0.01, allow=allow[sel])
    V[sel] = Vs
    return V, nmv, dmax


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default=os.path.join(ROOT, "out"))
    ap.add_argument("--step", type=int, default=2)
    args = ap.parse_args()
    data = os.path.join(args.out, "data")
    t0 = time.time()
    k = 1.0
    vj = os.path.join(data, "variant.json")
    variant = os.path.exists(vj)
    if variant:
        k = float(json.load(open(vj)).get("k", 1.0))
    sk = skin_data(data, k)
    layers = {}
    for name in ("flesh", "bone"):
        d = read_bin(os.path.join(data, "inner_%s.bin" % name))
        P = d["pos"].astype(np.float64) / k
        layers[name] = {"V": P, "B": d["bones"].astype(np.int64), "W": d["weights"].astype(np.float64),
                        "part": np.round(d["part"]).astype(np.int64).ravel(),
                        "reg": {r: f(P) for r, f in REGIONS.items()}}
    clips = json.load(open(clip_path(args.out)))["clips"]
    frames = pose_frames(clips, args.step)
    rep = {"k": k, "step": args.step, "frames": len(frames), "clips": sorted({f[0] for f in frames}, key=CLIPS.index),
           "gate": ("flesh <= %.1f mm (LBS-inverted points reported apart), chest front and hips <= %.1f mm; bone chest front "
                    "<= %.2f mm, hips <= %.2f mm (base + %.1f)" % (POKE_MM, POKE_MM, BONE_BASE_MM["chest_front"] + BONE_OVER_MM,
                                                              BONE_BASE_MM["hips"] + BONE_OVER_MM, BONE_OVER_MM))
           if variant else "report only (base layers = stage 1c)"}
    acc = {n: {"max_mm": -1e9, "worst": "", "out_vert_frames": 0, "near_other_part": 0, "covered_by_fold": 0,
               "regions": {r: {"max_mm": -1e9, "worst": ""} for r in REGIONS},
               "lbs_inverted": {"max_mm": -1e9, "worst": "", "out_vert_frames": 0, "verts": set()}} for n in layers}
    import mesh as ME
    fl = read_bin(os.path.join(data, "inner_flesh.bin"))
    nbind = ME.vnormals(layers["flesh"]["V"], fl["idx"][:, ::-1].astype(np.int64))
    for cn, fr, M in frames:
        for n, L in layers.items():
            s, other, cov, Nq = poke(sk, M, L["V"], L["B"], L["W"], L["part"], full=True)
            ss = s * k * 1000.0
            a = acc[n]
            if n == "flesh":
                # LBS หมุนระยะลึกสวนผิว: แยกออกจากที่โผล่ที่แก้ได้ (อกหน้า/สะโพกยังนับที่ REGIONS)
                o = np.flatnonzero(ss > 0)
                if len(o):
                    A = sum(L["W"][o, j, None, None] * M[L["B"][o, j], :3, :3] for j in range(L["B"].shape[1]))
                    inv = np.einsum('nji,nj->ni', A, Nq[o])
                    inv = np.einsum('ij,ij->i', inv, nbind[o]) < 0.0
                    li = a["lbs_inverted"]
                    for i in o[inv]:
                        li["verts"].add(int(i))
                        li["out_vert_frames"] += 1
                        if ss[i] > li["max_mm"]:
                            li["max_mm"] = float(ss[i])
                            li["worst"] = "%s frame %d vertex %d (bind %s m)" % (cn, fr, i, np.round(L["V"][i] * k, 3).tolist())
                    ss_reg = ss.copy()          # อกหน้า/สะโพก: นับทุกจุดที่โผล่
                    ss[o[inv]] = -np.inf
                else:
                    ss_reg = ss
            else:
                ss_reg = ss
            a["near_other_part"] += other
            a["covered_by_fold"] += cov
            a["out_vert_frames"] += int((ss > 0).sum())
            i = int(np.argmax(ss))
            if ss[i] > a["max_mm"]:
                a["max_mm"] = float(ss[i])
                a["worst"] = "%s frame %d vertex %d part %d (bind y %.3f m)" % (cn, fr, i, L["part"][i], L["V"][i, 1] * k)
            for r, m in L["reg"].items():
                if m.any():
                    j = int(np.argmax(np.where(m, ss_reg, -np.inf)))
                    if ss_reg[j] > a["regions"][r]["max_mm"]:
                        a["regions"][r]["max_mm"] = float(ss_reg[j])
                        a["regions"][r]["worst"] = "%s frame %d" % (cn, fr)
    for n, a in acc.items():
        a["max_mm"] = round(max(a["max_mm"], -1e9), 3)
        for r in a["regions"].values():
            r["max_mm"] = round(max(r["max_mm"], -1e9), 3)
        li = a["lbs_inverted"]
        li["max_mm"] = round(max(li["max_mm"], -1e9), 3)
        li["verts"] = len(li["verts"])
    rep.update(acc)
    rep["poke_limit_mm"] = POKE_MM
    rep["time_s"] = round(time.time() - t0, 1)
    json.dump(rep, open(os.path.join(data, "inner_posed.json"), "w"), indent=1)
    for n in layers:
        print("posed %-5s: highest %.2f mm (%s), %d vertex-frames above the skin, %d near another part, %d under a fold; %s"
              % (n, acc[n]["max_mm"], acc[n]["worst"], acc[n]["out_vert_frames"], acc[n]["near_other_part"],
                 acc[n]["covered_by_fold"], {r: v["max_mm"] for r, v in acc[n]["regions"].items()}))
    li = acc["flesh"]["lbs_inverted"]
    print("posed flesh where LBS turns the depth against the skin (not fixable by moving the flesh): %s"
          % ("none" if li["verts"] == 0 else "%d verts, %d vertex-frames, highest %.2f mm (%s)"
             % (li["verts"], li["out_vert_frames"], li["max_mm"], li["worst"])))
    print("%d frames of %d clips in %.1fs (%s)" % (rep["frames"], len(rep["clips"]), rep["time_s"], rep["gate"]))
    bad = [r for r, v in acc["flesh"]["regions"].items() if v["max_mm"] > POKE_MM]
    if variant and (acc["flesh"]["max_mm"] > POKE_MM or bad):
        raise SystemExit("inner flesh above the skin in a posed frame: %.2f mm (%s), regions %s" % (
            acc["flesh"]["max_mm"], acc["flesh"]["worst"], bad))
    bad_b = {r: v["max_mm"] for r, v in acc["bone"]["regions"].items() if v["max_mm"] > BONE_BASE_MM[r] + BONE_OVER_MM}
    if variant and bad_b:
        raise SystemExit("inner bone above the skin in a posed frame more than the base body + %.1f mm: %s (base %s)" % (
            BONE_OVER_MM, bad_b, BONE_BASE_MM))


if __name__ == "__main__":
    main()
