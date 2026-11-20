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
#   กระดูก: อกหน้า/สะโพกโผล่ได้ไม่เกินร่างหลัก + BONE_OVER_MM (inner_layers.py กดลงด้วย push_bone ถึง BONE_PUSH_MM)
#   ใหม่ 0.14: เกตเดียวกันทุกร่าง รวมร่างหลัก (ชั้นในของร่างหลักถูกกดแบบเดียวกัน) + ท่าหน้า FACE_POSES + เกต G13 หน้า
#   (G12 ใช้แล้วใน vgates.py = อกหญิง)
#   ท่า: ref/soldier_clips.json (ชุดท่าของทหารเอง clips_soldier.py: ทุกคลิป) ถ้ามี ไม่งั้น ref/clips.json (สำเนา humanoid: CLIPS)
#   /usr/bin/python3 inner_posed.py [--out DIR] [--step 2] [--clips FILE]      (~2-3 นาที)
import argparse
import json
import os
import time
import numpy as np
import mesh as ME
import rig
import variants as VR
from inner_layers import read_bin, SkinDepth

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
# ท่าที่ทหารใช้เมื่อยังไม่มีชุดท่าของตัวเอง (สำเนาจาก humanoid.res: SoldierFigure.PLAYER_CLIPS + ENEMY_CLIPS เดิม)
CLIPS = ["idle", "walk", "run", "fire", "bash_0", "bash_1", "bash_2", "thrust_0", "thrust_1", "thrust_2", "flinch",
         "flinch_heavy", "die_back", "die_fwd", "die_spin"]
WRIST_MAX = 45.0
POKE_MM = 0.5             # เนื้อโผล่พ้นผิวได้ไม่เกินเท่านี้ (มม.) ในส่วนเดียวกัน
# บริเวณที่ต้องดูเป็นพิเศษ (กรอบ 1.78 ม. ท่าผูก): อก/เต้านม และสะโพก/ก้น
REGIONS = {"chest_front": lambda P: (P[:, 1] > 1.15) & (P[:, 1] < 1.42) & (P[:, 2] > 0.03),
           "hips": lambda P: (P[:, 1] > 0.78) & (P[:, 1] < 1.05) & ((np.abs(P[:, 0]) > 0.10) | (P[:, 2] < -0.03))}
# กระดูกโผล่พ้นผิวในท่า (มม.) ของร่างหลัก (inner_posed.json ของร่างหลัก ใหม่ 0.14: ชุดท่าของทหารเอง หลังกดลง)
BONE_BASE_MM = {"chest_front": 0.817, "hips": 6.332}
BONE_OVER_MM = 0.5        # กระดูกอกหน้า/สะโพกโผล่เกินร่างหลักได้ไม่เกินเท่านี้
BONE_PUSH_MM = {"chest_front": 0.817, "hips": 6.332}   # push_bone กดถึงเท่านี้ทุกร่าง (= ขั้น 1c ร่างหลัก - 0.1 มม. คงที่)
# ท่าหน้า (กรอบ 1.78 ม., กรอบศีรษะ): กรามหมุนรอบ X (องศา) ; มุมปาก/คิ้วเลื่อน (ม.: x ออกนอก y ขึ้น z หน้า) = ช่วงสุดที่เกมใช้ได้
FACE_POSES = {
    "jaw_talk": {"rot": {"head_jaw": 5.0}},
    "jaw_shout": {"rot": {"head_jaw": 8.0}},
    "smile": {"trans": {"head_lipL": (0.002, 0.003, -0.002), "head_lipR": (-0.002, 0.003, -0.002)}},
    "frown": {"trans": {"head_lipL": (0.001, -0.003, 0.0), "head_lipR": (-0.001, -0.003, 0.0)}},
    "pucker": {"trans": {"head_lipL": (-0.003, 0.0, 0.002), "head_lipR": (0.003, 0.0, 0.002)}},
    "brows_up": {"trans": {"head_browL": (0.0, 0.004, 0.0), "head_browR": (0.0, 0.004, 0.0)}},
    "brows_down": {"trans": {"head_browL": (-0.0015, -0.0025, 0.0), "head_browR": (0.0015, -0.0025, 0.0)}},
    "pain": {"rot": {"head_jaw": 7.0}, "trans": {"head_browL": (-0.0015, -0.0025, 0.0), "head_browR": (0.0015, -0.0025, 0.0),
                                                  "head_lipL": (0.002, -0.002, -0.001), "head_lipR": (-0.002, -0.002, -0.001)}},
    "shout_smile": {"rot": {"head_jaw": 8.0}, "trans": {"head_lipL": (0.002, 0.003, -0.002), "head_lipR": (-0.002, 0.003, -0.002),
                                                         "head_browL": (0.0, 0.004, 0.0), "head_browR": (0.0, 0.004, 0.0)}}}
FACE_OPEN_MM = {"jaw_talk": 4.0, "jaw_shout": 11.0}     # G13: ช่องปากกลางเปิดอย่างน้อยเท่านี้ (มม. จริง)
FACE_EYE_MOVE_MM = 0.2    # G13: จุดในอัลมอนด์ตาขยับได้ไม่เกินเท่านี้ในท่าหน้า (เปลือกตาทาสีต้องตรงที่)
BUDGET = {"hi": 24000, "mid": 16000, "lo": 9000, "min": 5000}


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
    """ชุดท่าของทหารเอง (soldier_clips.json) ก่อน ไม่มีจึงใช้สำเนา humanoid (clips.json) ; ref/ ของโฟลเดอร์สร้างก่อนของตัวสร้าง"""
    dirs = [os.path.join(os.path.dirname(os.path.abspath(out)), "ref"), os.path.join(ROOT, "ref")]
    for name in ("soldier_clips.json", "clips.json"):
        for d in dirs:
            if os.path.exists(os.path.join(d, name)):
                return os.path.join(d, name)
    return os.path.join(ROOT, "ref", "clips.json")


def clip_list(clips):
    """ท่าที่ตรวจ: ชุดของทหารเอง (มี jog และ punch_0) = ทุกคลิปตามลำดับในไฟล์ ; สำเนา humanoid = CLIPS"""
    if "jog" in clips and "punch_0" in clips:
        return list(clips)
    return [c for c in CLIPS if c in clips]


def pose_frames(clips, step):
    """[(ท่า, เฟรม, เมทริกซ์ผูก (nb,4,4))] ของท่าที่ทหารใช้ ทุก step เฟรม"""
    Gb, _ = rig.fk(rig.bind_pose())
    IB = np.stack([np.linalg.inv(Gb[b]) for b in rig.BONES])
    out = []
    for cn in clip_list(clips):
        c = clips[cn]
        for fr in range(0, int(c["frames"]), step):
            G, _ = rig.fk(clip_pose(c, fr))
            out.append((cn, fr, np.stack([G[b] for b in rig.BONES]) @ IB))
    return out


def face_frames():
    """[(ท่าหน้า, 0, เมทริกซ์ผูก)] ท่าผูกของตัว + กระดูกหน้าตาม FACE_POSES"""
    Gb, _ = rig.fk(rig.bind_pose())
    IB = np.stack([np.linalg.inv(Gb[b]) for b in rig.BONES])
    out = []
    for nm, fp in FACE_POSES.items():
        p = rig.bind_pose()
        for b, deg in fp.get("rot", {}).items():
            p["local"][b] = rig.qaxis([1, 0, 0], deg)
        p["trans"] = {b: np.asarray(t, float) for b, t in fp.get("trans", {}).items()}
        G, _ = rig.fk(p)
        out.append((nm, 0, np.stack([G[b] for b in rig.BONES]) @ IB))
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
               allow=None, iters=20, passes=1, only=None, skip_inverted=False):
    """ร่างแบบอื่น: เลื่อนจุดเนื้อ (กรอบที่ส่งออก) ที่โผล่พ้นผิว (หรือลึกไม่ถึง margin) ในท่าใดของเกม ในท่าผูก
    allow (ม. ต่อจุด กรอบที่ส่งออก) = โผล่ได้ถึงเท่านี้แทน margin (inf = ไม่เลื่อน: กระดูกนอกบริเวณที่ดู)
    ทุกท่าที่จุดนั้นโผล่เป็นเงื่อนไขเชิงเส้น g·d >= ระยะที่ขาด (g = A^T n: การหมุนผสมของจุดย้อนนอร์มอลของผิวในท่านั้น ;
    รักแร้ตอนแกว่งแขนนอร์มอลท่าผูกแทบขนานผิว) -> d สั้นสุดโดยฉายทีละเงื่อนไขซ้ำ (Kaczmarz) แล้วคิดใหม่ทุกรอบ ; ไม่เกิน cap
    จุดที่เลื่อนแล้วทะลุอีกด้าน (ใบหู ข้อมือ: ในท่าผูกลึกใต้ผิว skins ไม่ถึง bind_margin) เลื่อนครึ่งเดียว ยังไม่ได้ก็ไม่เลื่อน
    passes > 1: จุดที่ยังโผล่หลังครบ rounds ได้เลื่อนต่ออีกชุด (cap ใหม่ต่อชุด ; รักแร้ที่ท่าต่าง ๆ ดึงคนละทาง)
    คืน (V, จำนวนจุดที่เลื่อน, ระยะเลื่อนมากสุด ม.)"""
    sk = skin_data(data, k)
    frames = pose_frames(clips, step) + face_frames()
    n = len(V)
    V = np.array(V, np.float64)
    total = np.zeros(n)
    moved = np.zeros(n, bool)
    for it_ in range(rounds * passes):
        if it_ and it_ % rounds == 0:
            total[:] = 0.0
        cons = {}                                     # จุด -> [(ระยะที่ขาด, g)] ในกรอบ 1.78 ม.
        nb = ME.vnormals(V, F) if skip_inverted else None
        for _cn, _fr, M in frames:
            s, _, _, Nq = poke(sk, M, V / k, B, W, part, full=True)
            need = s + margin / k if allow is None else s - allow / k
            idx = np.flatnonzero(need > 0)
            if only is not None:                      # ใหม่ 0.14: เฉพาะจุดที่ขอ (mask)
                idx = idx[only[idx]]
            if len(idx) == 0:
                continue
            A = sum(W[idx, j, None, None] * M[B[idx, j], :3, :3] for j in range(B.shape[1]))
            g = np.einsum('nji,nj->ni', A, Nq[idx])
            if skip_inverted:                         # ไม่นับท่าที่ LBS หมุนระยะลึกสวนผิว (แบบเกต: แก้ด้วยการเลื่อนไม่ได้)
                keep = np.einsum('ij,ij->i', g, nb[idx]) >= 0.0
                idx, g = idx[keep], g[keep]
            for i, r, gi in zip(idx, need[idx], g):
                cons.setdefault(int(i), []).append((float(r), gi))
        if not cons:
            break
        ids = np.array(sorted(cons))
        D = np.zeros((len(ids), 3))
        for row, i in enumerate(ids):
            d = np.zeros(3)
            for _it in range(iters):
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


def still_out(V, F, B, W, part, data, k, clips, step=2):
    """ใหม่ 0.14: mask จุดเนื้อ (กรอบที่ส่งออก) ที่ยังโผล่เกิน POKE_MM ในท่าของเกต (ทุก step เฟรม) ที่ LBS ไม่สวนผิว"""
    sk = skin_data(data, k)
    V = np.asarray(V, np.float64)
    nb = ME.vnormals(V, F)
    bad = np.zeros(len(V), bool)
    for _cn, _fr, M in pose_frames(clips, step):
        s, _, _, Nq = poke(sk, M, V / k, B, W, part, full=True)
        o = np.flatnonzero(s * k * 1000.0 > POKE_MM)
        if len(o):
            A = sum(W[o, j, None, None] * M[B[o, j], :3, :3] for j in range(B.shape[1]))
            g = np.einsum('nji,nj->ni', A, Nq[o])
            bad[o[np.einsum('ij,ij->i', g, nb[o]) >= 0.0]] = True
    return bad


def push_bone(V, B, W, part, data, k, clips, skins, step=2):
    """ทุกร่าง: กดจุดกระดูก (ชิ้นแข็ง) ในอกหน้าและสะโพกที่โผล่ในท่าใดของเกมเกิน BONE_PUSH_MM ลงในท่าผูก
    เฉพาะจุดในสองบริเวณนั้น ; ท่าผูกยังลึก >= 2.5 มม. ใต้ผิว hi/mid ; คืน (V, จำนวนจุดที่เลื่อน, ระยะเลื่อนมากสุด ม.)"""
    V = np.array(V, np.float64)
    P = V / k
    allow = np.full(len(V), np.inf)
    for r, f in REGIONS.items():
        m = f(P)
        allow[m] = np.minimum(allow[m], BONE_PUSH_MM[r] / 1000.0)
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
    ap.add_argument("--clips", default="", help="clip JSON (default: clip_path)")
    args = ap.parse_args()
    data = os.path.join(args.out, "data")
    t0 = time.time()
    k = 1.0
    vj = os.path.join(data, "variant.json")
    variant = os.path.exists(vj)
    if variant:
        vd = json.load(open(vj))
        k = float(vd.get("k", 1.0))
        VR.use(vd.get("variant", ""))
    sk = skin_data(data, k)
    layers = {}
    for name in ("flesh", "bone"):
        d = read_bin(os.path.join(data, "inner_%s.bin" % name))
        P = d["pos"].astype(np.float64) / k
        layers[name] = {"V": P, "B": d["bones"].astype(np.int64), "W": d["weights"].astype(np.float64),
                        "part": np.round(d["part"]).astype(np.int64).ravel(),
                        "reg": {r: f(P) for r, f in REGIONS.items()}}
    cpath = args.clips or clip_path(args.out)
    clips = json.load(open(cpath))["clips"]
    frames = pose_frames(clips, args.step)
    seen = {f[0] for f in frames}
    rep = {"k": k, "step": args.step, "frames": len(frames), "clips": [c for c in clip_list(clips) if c in seen],
           "clip_file": os.path.basename(cpath),
           "gate": ("flesh <= %.1f mm (LBS-inverted points reported apart), chest front and hips <= %.1f mm; bone chest front "
                    "<= %.2f mm, hips <= %.2f mm (base + %.1f)" % (POKE_MM, POKE_MM, BONE_BASE_MM["chest_front"] + BONE_OVER_MM,
                                                              BONE_BASE_MM["hips"] + BONE_OVER_MM, BONE_OVER_MM))}
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
    # ---- G13 หน้า (ใหม่ 0.14) ----
    g13 = face_gate(data, k, sk, layers)
    rep["G13"] = g13
    json.dump(rep, open(os.path.join(data, "inner_posed.json"), "w"), indent=1)
    print("G13 face %s: %s" % ("PASS" if g13["pass"] else "FAIL", "; ".join(g13["fails"]) if g13["fails"] else g13["summary"]))
    bad = [r for r, v in acc["flesh"]["regions"].items() if v["max_mm"] > POKE_MM]
    if acc["flesh"]["max_mm"] > POKE_MM or bad:
        raise SystemExit("inner flesh above the skin in a posed frame: %.2f mm (%s), regions %s" % (
            acc["flesh"]["max_mm"], acc["flesh"]["worst"], bad))
    bad_b = {r: v["max_mm"] for r, v in acc["bone"]["regions"].items() if v["max_mm"] > BONE_BASE_MM[r] + BONE_OVER_MM}
    if bad_b:
        raise SystemExit("inner bone above the skin in a posed frame more than the base body + %.1f mm: %s (base %s)" % (
            BONE_OVER_MM, bad_b, BONE_BASE_MM))
    if not g13["pass"]:
        raise SystemExit("G13 face: " + "; ".join(g13["fails"]))


def face_gate(data, k, sk, layers):
    """G13 หน้า: (a) CUSTOM1 บน hi/mid/lo ไม่มีบน min, แถวรอยต่อปากบน hi/mid (b) กระดูกหน้าเฉพาะจุดส่วนหัวบน hi/mid ไม่มีบน
    lo/min (c) จุดที่ห่างช่องตาไม่เกิน face.PAINT_REACH อยู่ใต้เปลือกตาปิด (|u|,|v| <= 1) (d) ท่าหน้าบน hi/mid: ช่องปากกลางเปิด
    >= FACE_OPEN_MM, สามเหลี่ยมส่วนหัวไม่พลิก, จุดในอัลมอนด์ตาขยับ <= FACE_EYE_MOVE_MM (e) ชั้นในส่วนหัวในท่าหน้าโผล่
    <= POKE_MM (f) สามเหลี่ยมไม่เกินงบเกม"""
    import anatomy as AN
    import face as FC
    import weights as WT
    f = FC.features(AN.all_skin_prims())
    Gb, _ = rig.fk(rig.bind_pose())
    nfb = rig.BI[rig.FACE[0]]
    fails, out = [], {"levels": {}, "poses": {}}
    frames = face_frames()
    for lv in ("hi", "mid", "lo", "min"):
        d = read_bin(os.path.join(data, "body_%s.bin" % lv))
        n = len(d["pos"])
        V = d["pos"].astype(np.float64) / k
        F = d["idx"][:, ::-1].astype(np.int64)
        part = np.round(d["cus"][:, 3]).astype(np.int64)
        B, W = d["bones"].astype(np.int64), d["weights"].astype(np.float64)
        fb = (B >= nfb) & (W > 0)
        r = {"tris": int(len(F)), "face_bone_verts": int(fb.any(1).sum()), "custom1": "face" in d}
        if len(F) > BUDGET[lv]:
            fails.append("%s: %d triangles over the budget %d" % (lv, len(F), BUDGET[lv]))
        if lv in FC.CUSTOM_LV and "face" not in d:
            fails.append("%s: no CUSTOM1 face coordinates" % lv)
        if lv == "min" and "face" in d:
            fails.append("min carries CUSTOM1 (nothing per frame there)")
        if lv in FC.SEAM_LV:
            if fb.any(1).sum() == 0:
                fails.append("%s: no face-bone weights" % lv)
            if (fb.any(1) & (part != 1)).any():
                fails.append("%s: face-bone weights outside the head part (%d verts)" % (lv, int((fb.any(1) & (part != 1)).sum())))
        elif fb.any():
            fails.append("%s: face-bone weights on a level without face bones" % lv)
        if "face" not in d:
            out["levels"][lv] = r
            continue
        cu = d["face"].astype(np.float64).reshape(n, 4)
        strip = np.abs(cu[:, 0] + cu[:, 1] - 24.0) < 1e-4
        r["seam_row_verts"] = int(strip.sum())
        if lv in FC.SEAM_LV and strip.sum() < 12:
            fails.append("%s: the mouth seam has %d row vertices" % (lv, int(strip.sum())))
        if lv not in FC.SEAM_LV and strip.any():
            fails.append("%s: seam codes on a level without a seam" % lv)
        H = FC.head_coords(V, Gb)
        dal = FC.eye_dist(H, f)
        near = dal < FC.PAINT_REACH[lv]
        outside = near & ~((np.abs(cu[:, 0]) <= 1.0) & (np.abs(cu[:, 1]) <= 1.0))
        r["eye_paint_verts"] = int(near.sum())
        r["eye_paint_outside_lid"] = int(outside.sum())
        if near.sum() < 8 or outside.any():
            fails.append("%s: %d of %d painted-eye vertices outside the closed lid" % (lv, int(outside.sum()), int(near.sum())))
        if lv in FC.SEAM_LV:
            rows = d["meta"].get("seam_rows")
            up, lo = np.asarray(rows[0], np.int64), np.asarray(rows[1], np.int64)
            ci = int(np.argmin(np.abs(H[up, 0])))
            eyez = (np.abs(cu[:, 0]) <= 1.2) & (np.abs(cu[:, 1]) <= 1.4)
            N0 = np.cross(V[F[:, 1]] - V[F[:, 0]], V[F[:, 2]] - V[F[:, 0]])
            a0 = np.linalg.norm(N0, axis=1)
            headf = (part[F] == 1).all(1) & (a0 > 1e-12)
            pr = {}
            for nm, _fr, M in frames:
                P = skin_pts(V, B, W, M)
                N1 = np.cross(P[F[:, 1]] - P[F[:, 0]], P[F[:, 2]] - P[F[:, 0]])
                flips = int((headf & (np.einsum('ij,ij->i', N0, N1) <= 0)).sum())
                op = float(np.linalg.norm(P[lo[ci]] - P[up[ci]]) * k * 1000.0)
                mv = float(np.linalg.norm(P[eyez] - V[eyez], axis=1).max() * k * 1000.0)
                pr[nm] = {"open_mm": round(op, 2), "flips": flips, "eye_move_mm": round(mv, 3)}
                if flips:
                    fails.append("%s %s: %d head triangles flip" % (lv, nm, flips))
                if mv > FACE_EYE_MOVE_MM:
                    fails.append("%s %s: the eye moves %.2f mm" % (lv, nm, mv))
                if nm in FACE_OPEN_MM and op < FACE_OPEN_MM[nm]:
                    fails.append("%s %s: the mouth opens only %.1f mm" % (lv, nm, op))
            r["poses"] = pr
        out["levels"][lv] = r
    # (e) ชั้นในส่วนหัวในท่าหน้า
    for nm, _fr, M in frames:
        row = {}
        for ln, L in layers.items():
            sv = poke(sk, M, L["V"], L["B"], L["W"], L["part"])[0] * k * 1000.0
            sv = np.where(L["part"] == 1, sv, -np.inf)
            row[ln] = round(float(sv.max()), 3)
            if sv.max() > POKE_MM:
                fails.append("%s: inner %s %.2f mm above the head skin" % (nm, ln, sv.max()))
        out["poses"][nm] = row
    out["pass"] = not fails
    out["fails"] = fails
    out["summary"] = "levels %s; inner layers in face poses (mm) %s" % (
        {lv: {kk: vv for kk, vv in r.items() if kk != "poses"} for lv, r in out["levels"].items()},
        {nm: row for nm, row in out["poses"].items()})
    return out


if __name__ == "__main__":
    main()
