# หน้า (ใหม่ 0.14 ข้อ 2): รอยต่อปาก (hi/mid) + พิกัดหน้า CUSTOM1 (hi/mid/lo) + น้ำหนักกระดูกหน้า + สีเปลือกตา
#   ทุกอย่างคิดในกรอบศีรษะท่า I (กรอบเดียวกับชิ้นกายวิภาค ; ร่างหลากหลาย: ก่อนขยายศีรษะ) จากชิ้นของร่างนั้นเอง
#   (แนวร่องปาก mouth_line, ช่องตา eye_open_L) จึงตามหน้าของแต่ละร่าง ; ไม่มีการสุ่ม
#   CUSTOM1 = (ตา u, ตา v, ปาก x, ปาก y)
#     ตา: อัลมอนด์ของช่องตาขยาย LID_GROW[ระดับ] ; u = 1 ที่หางตา/หัวตา (สองข้างเหมือนกัน บวก = ไปทางขมับ)
#         v = 1 / -1 ที่ขอบบน/ล่างของอัลมอนด์ทุก u (หารด้วยความสูงของส่วนโค้งที่ u นั้น) -> เปลือกตาปิดสุด = |u|,|v| <= 1
#     ปาก: (x, y - แนวร่องปาก) / ครึ่งความกว้างปาก -> มุมปาก = (±1, 0) (ปากทาสีของ lo)
#     ห่างจากตา/ปาก หรือหลังหน้า: ย่อตามแนวรัศมีให้ยาว FAR (ประมาณค่าระหว่างจุดไม่ผ่านบริเวณตา/ปาก)
#     แถวรอยต่อปาก (hi/mid) ในช่องตา: แถวบน (16, 8) แถวล่าง (8, 16) มุมปาก (12, 12) -> u + v = 24 เฉพาะในแถบช่องปาก
import numpy as np
from scipy.sparse import coo_matrix
from scipy.sparse.csgraph import dijkstra
import rig
import mesh as ME
import variants as VR

FAR = 8.0
ROW_UP, ROW_LO, ROW_END = (16.0, 8.0), (8.0, 16.0), (12.0, 12.0)
LID_GROW = {"hi": 0.0019, "mid": 0.0022, "lo": 0.0038}   # ม.: สีตาที่เกลี่ยแล้วของระดับนั้นอยู่ในอัลมอนด์ที่ขยายนี้
ARC_FLOOR = 0.3          # ใกล้หัว/หางตา ส่วนโค้งไม่บางกว่านี้ (มุมของเปลือกตาปิดมน คลุมสีตาที่หัว/หางตา)
PAINT_REACH = {"hi": 0.0010, "mid": 0.0013, "lo": 0.0028}   # ม.: เกต: จุดที่ห่างช่องตาไม่เกินนี้ต้องอยู่ใต้เปลือกตาปิด
DROP = 0.0003            # แถวล่างของรอยต่อปากต่ำกว่าแถวบน (ม.): แถบช่องปากตอนหุบไม่แบนเป็นศูนย์ (คำนวณระยะได้)
JAW_FADE, JAW_OFF = 0.030, -0.006   # กรามไล่หายใต้ขอบล่างขากรรไกรยาวเท่านี้ (ม.) ; ขอบเต็มต่ำลง 6 มม. (กระดูกขากรรไกรไม่โผล่)
SEAM_LV = ("hi", "mid")
CUSTOM_LV = ("hi", "mid", "lo")


def head_coords(V, G):
    """จุดผิวท่าผูก (กรอบที่ปั้น) -> พิกัดศีรษะท่า I ; ร่างหลากหลาย: ย้อนการขยายศีรษะก่อน"""
    X = VR.head_unwarp(V, G) if VR.CUR is not None else V
    return ME.head_local(X, G)


def features(prims):
    """ชิ้นหน้าของร่างนี้: แนวร่องปาก (เรียงตาม x) ครึ่งความกว้างปาก อัลมอนด์ตาซ้าย"""
    pm = {p.name: p for p in prims}
    ml = np.asarray(pm["mouth_line"].p["pts"], float)
    ml = ml[np.argsort(ml[:, 0])]
    e = pm["eye_open_L"].p
    eye = {"c": np.asarray(e["c"], float), "hw": float(e["hw"]), "hu": float(e["hu"]), "hl": float(e["hl"]),
           "tilt": float(e["tilt"]) * float(e.get("sx", 1.0))}
    return {"ml": ml, "c": float(np.abs(ml[:, 0]).max()), "eye": eye, "pm": pm}


def mouth_s(H, f):
    """ระยะตั้งเหนือแนวร่องปาก (ม.) และ z ของแนว ที่ x ของแต่ละจุด"""
    ml = f["ml"]
    return H[:, 1] - np.interp(H[:, 0], ml[:, 0], ml[:, 1]), np.interp(H[:, 0], ml[:, 0], ml[:, 2])


def _arc(u, h, hw):
    """ความสูงของส่วนโค้งอัลมอนด์ (วงกลมผ่านมุมทั้งสอง) ที่ u (ทำให้เป็น 1 ที่กลาง) ไม่ต่ำกว่า ARC_FLOOR"""
    r = (hw * hw + h * h) / (2 * h)
    x = np.clip(np.abs(u), 0, 1) * hw
    a = ((h - r) + np.sqrt(np.maximum(r * r - x * x, 0.0))) / h
    return np.where(np.abs(u) < 1, np.maximum(a, ARC_FLOOR), ARC_FLOOR)


def _radial(P, front, far=FAR):
    """จุดที่ยาวเกิน far หรือไม่อยู่หน้า -> ย่อ/ขยายตามรัศมีให้ยาว far"""
    r = np.linalg.norm(P, axis=1)
    k = np.where(front, np.minimum(1.0, far / np.maximum(r, 1e-9)), far / np.maximum(r, 1e-9))
    return P * k[:, None]


def eye_uv(H, f, grow):
    """พิกัดตา (u, v) ในอัลมอนด์ที่ขยาย grow ม. (ยังไม่ย่อ)"""
    e = f["eye"]
    a = np.radians(e["tilt"])
    q0, q1 = np.abs(H[:, 0]) - e["c"][0], H[:, 1] - e["c"][1]
    u = np.cos(a) * q0 + np.sin(a) * q1
    v = -np.sin(a) * q0 + np.cos(a) * q1
    hw, hu, hl = e["hw"] + grow, e["hu"] + grow, e["hl"] + grow
    un = u / hw
    vn = np.where(v >= 0, v / hu / _arc(un, hu, hw), v / hl / _arc(un, hl, hw))
    return un, vn


def custom1(H, f, lv, rows=None):
    """CUSTOM1 (n, 4) ของระดับ lv ; rows = (แถวบน, แถวล่าง, มุมปาก) ของรอยต่อปาก (hi/mid)"""
    un, vn = eye_uv(H, f, LID_GROW[lv])
    eye = _radial(np.c_[un, vn], H[:, 2] > 0.045)
    s, _ = mouth_s(H, f)
    mo = _radial(np.c_[H[:, 0] / f["c"], s / f["c"]], H[:, 2] > 0.06)
    out = np.c_[eye, mo]
    if rows is not None:
        for idx, code in zip(rows, (ROW_UP, ROW_LO, ROW_END)):
            out[np.asarray(idx, np.int64), 0:2] = code
    return out


def eye_dist(H, f):
    """ระยะถึงช่องตาที่เจาะ (eye_open_L/R, ม.; ลบ = ในช่อง)"""
    P = H.astype(np.float32)
    return np.minimum(*[np.asarray(f["pm"][k].eval_local(P)[0], float) for k in ("eye_open_L", "eye_open_R")])


def lid_colour(H, C, f):
    """สีเปลือกตา (sRGB) = มัธยฐานสีผิวเปลือกตาบนเหนืออัลมอนด์ (ใต้รอยพับ เหนือขนตา) ของผิวระดับ hi"""
    un, vn = eye_uv(H, f, LID_GROW["hi"])
    m = (np.abs(un) < 0.6) & (vn > 1.25) & (vn < 1.8) & (H[:, 2] > 0.045)
    if m.sum() < 4:
        raise SystemExit("face: too few upper-lid vertices for the lid colour (%d)" % m.sum())
    return np.median(C[m, :3], axis=0), int(m.sum())


def _ss(x):
    x = np.clip(x, 0, 1)
    return x * x * (3 - 2 * x)


def weights(H, side, f):
    """สัดส่วนของน้ำหนัก head ที่ย้ายไปกระดูกหน้า: dict ชื่อ -> (n,) ; side = +1 เหนือแนวปาก / -1 ใต้ / 0 มุมปาก
    กราม: ใต้แนวปาก (ในริมฝีปากคมตามแถวรอยต่อ ; ห่างมุมปากไล่นุ่มตามเส้นมุมปาก-ข้อขากรรไกร) เหนือขอบล่างขากรรไกร
    (ไล่หายลงคอ 22 มม.) หน้าข้อขากรรไกร ; มุมปาก: เกาส์รอบมุมปาก ; คิ้ว: เกาส์รอบคิ้ว ไม่ลงเปลือกตาบน"""
    x, y, z = H[:, 0], H[:, 1], H[:, 2]
    ax = np.abs(x)
    c = f["c"]
    ml = f["ml"]
    yc, zc = float(ml[-1, 1]), float(ml[-1, 2])
    s, zml = mouth_s(H, f)
    th = np.degrees(np.arctan2(ax, np.maximum(z, -0.2) + 0.0))
    thc = float(np.degrees(np.arctan2(c, zc)))
    # ขอบบนนอกริมฝีปาก: จากมุมปากขึ้นไปหาข้อขากรรไกร (y 1.640 ที่ 75°)
    yup = yc + np.clip((th - thc) / (75.0 - thc), 0, 1) * (1.640 - yc)
    bup = 0.008 + 0.008 * np.clip((th - thc) / (75.0 - thc), 0, 1)
    smooth = _ss((yup - y) / bup + 0.5)
    sharp = np.where(side < 0, 1.0, np.where(side > 0, 0.0, 0.5))
    lip_zone = (ax <= c) & (z > zml - 0.012) & (np.abs(s) < 0.012)
    blend = _ss((ax - 0.75 * c) / (0.25 * c))
    up = np.where(lip_zone, sharp * (1 - blend) + smooth * blend, smooth)
    # ขอบล่างขากรรไกร (ผิว): คาง y 1.543 -> มุมขากรรไกร y 1.582 ที่ 80° ; ไล่หายลงคอ JAW_FADE
    yjl = 1.543 + JAW_OFF + np.clip(th / 80.0, 0, 1) * (1.582 - 1.543)
    low = _ss((y - (yjl - JAW_FADE)) / JAW_FADE)
    back = 1 - _ss((th - 62.0) / 22.0)
    jaw = up * low * back * (z > -0.02) * (y < 1.66)
    out = {"head_jaw": jaw}
    for sd, sx in (("L", 1.0), ("R", -1.0)):
        g = np.exp(-(((x - sx * c) / 0.014) ** 2 + ((y - yc) / 0.011) ** 2 + ((z - zc) / 0.012) ** 2))
        out["head_lip" + sd] = 0.85 * g * _ss((sx * x + 0.006) / 0.006)
    e = f["eye"]
    ytop = e["c"][1] + e["hu"] + 0.003
    for sd, sx in (("L", 1.0), ("R", -1.0)):
        bx, by = e["c"][0] - 0.0005, e["c"][1] + 0.0232
        g = np.exp(-(((x - sx * bx) / 0.020) ** 2 + ((y - by) / 0.008) ** 2))
        out["head_brow" + sd] = 0.9 * g * _ss((y - ytop) / 0.004) * _ss(sx * x / 0.006) * _ss((z - 0.055) / 0.015)
    return out


SEAM_WIN = (0.006, 0.009, 0.012)      # ครึ่งกว้างหน้าต่างตัดรอยต่อปาก (ม.) ตามลำดับที่ลอง


def cut_window(V, F, s, win, snap=0.35, hx=None, xlim=None):
    """ตัดตามเส้น s = 0 เฉพาะขอบที่ปลายทั้งสองอยู่ใน win (แบบ variants.cut_along): จุดใกล้เส้นเลื่อนลงเส้นก่อน แล้วแบ่ง
    สามเหลี่ยมตามขอบที่ข้ามเส้น (ขอบเดียว = สองชิ้น, สองขอบ = สามชิ้น) ; ผิวยังปิด ; จุดกลางตัว (x = 0) ไม่เลื่อน
    คืน (V, F, s, win) ของเมชใหม่ (จุดใหม่บนเส้น: s = 0, อยู่ใน win)"""
    V = np.array(V, float)
    s = np.array(s, float)
    F = np.asarray(F, np.int64)
    n = len(V)
    E = np.unique(np.sort(np.vstack([F[:, [0, 1]], F[:, [1, 2]], F[:, [2, 0]]]), axis=1), axis=0)
    a, b = E[:, 0], E[:, 1]
    ew = win[a] & win[b]
    cr = ew & (s[a] * s[b] < 0)
    t = np.where(cr, s[a] / np.where(cr, s[a] - s[b], 1.0), 0.5)
    if xlim is not None:
        # จุดตัดต้องไม่เลยมุมปาก (|x| ของจุดตัดบนขอบ <= xlim)
        ew = ew & ~(cr & (np.abs(hx[a] + t * (hx[b] - hx[a])) > xlim))
        cr = cr & ew
    best = np.full(n, np.inf)
    for v, tt in ((a, t), (b, 1 - t)):
        m = cr & (tt < snap)
        np.minimum.at(best, v[m], tt[m])
    tgt = np.zeros((n, 3))
    for v, u, tt in ((a, b, t), (b, a, 1 - t)):
        m = cr & (tt < snap)
        m[m] = tt[m] == best[v[m]]
        tgt[v[m]] = V[v[m]] + tt[m][:, None] * (V[u[m]] - V[v[m]])
    V, mv = VR._safe_move(V, F, tgt, np.isfinite(best) & (np.abs(V[:, 0]) > 1e-9))
    s[mv] = 0.0
    cr = ew & (s[a] * s[b] < 0)
    ce = np.nonzero(cr)[0]
    if len(ce) == 0:
        return V, F, s, win
    tc = s[a[ce]] / (s[a[ce]] - s[b[ce]])
    newV = V[a[ce]] + tc[:, None] * (V[b[ce]] - V[a[ce]])
    key = {int(a[e]) * n + int(b[e]): n + i for i, e in enumerate(ce)}

    def mid(i, j):
        return key.get(min(i, j) * n + max(i, j))
    Vn = np.vstack([V, newV])
    out = []
    for f in F:
        ms = [mid(int(f[k]), int(f[(k + 1) % 3])) for k in range(3)]
        cnt = sum(m is not None for m in ms)
        if cnt == 0:
            out.append(tuple(f))
        elif cnt == 1:
            k = [i for i in range(3) if ms[i] is not None][0]
            A, B, C = f[k], f[(k + 1) % 3], f[(k + 2) % 3]
            out += [(A, ms[k], C), (ms[k], B, C)]
        else:
            k = [i for i in range(3) if ms[i] is None][0]
            P, Q, L = f[k], f[(k + 1) % 3], f[(k + 2) % 3]
            mQ, mP = ms[(k + 1) % 3], ms[(k + 2) % 3]
            out.append((mQ, L, mP))
            if np.linalg.norm(Vn[P] - Vn[mQ]) <= np.linalg.norm(Vn[Q] - Vn[mP]):
                out += [(P, Q, mQ), (P, mQ, mP)]
            else:
                out += [(P, Q, mP), (Q, mQ, mP)]
    return Vn, np.array(out, np.int64), np.r_[s, np.zeros(len(newV))], np.r_[win, np.ones(len(newV), bool)]


class _SeamBroken(Exception):
    pass


def mouth_seam(V, F, G, f, drop=DROP):
    """รอยต่อปาก: ลองหน้าต่างตัดกว้าง 6 มม. ก่อน (ผลเดิมทุกไบต์) ; ใหม่ 0.17: ถ้าแนวขาดระหว่างมุมปาก (ขอบสามเหลี่ยมยาวกว่า
    หน้าต่าง) ลองใหม่ที่ 9 และ 12 มม."""
    for sw in SEAM_WIN:
        try:
            return _mouth_seam(V, F, G, f, drop, sw)
        except _SeamBroken:
            print("face: mouth seam broken with a %.0f mm window" % (sw * 1000), flush=True)
    raise SystemExit("face: the mouth seam is broken between the mouth corners")


def _mouth_seam(V, F, G, f, drop, sw):
    """รอยต่อปาก (hi/mid): ตัดตามแนวร่องปากระหว่างมุมปาก -> แถวจุดบนแนว (แถวบน = ขอบริมฝีปากบน) ; จุดในแถว (ยกเว้น
    มุมปาก) ซ้ำเป็นแถวล่าง (ขอบริมฝีปากล่าง ต่ำลง drop) ; สามเหลี่ยมใต้แนวใช้แถวล่าง ; แถบสามเหลี่ยมเชื่อมสองแถว (ช่องปากเมื่อ
    กรามอ้า) -> ผิวยังปิดสนิท ; คืน (V, F, rows) rows = (แถวบน, แถวล่าง, มุมปาก) ดัชนีจุด"""
    H = head_coords(V, G)
    s, zml = mouth_s(H, f)
    win = (np.abs(H[:, 0]) <= f["c"] + 0.005) & (H[:, 2] > zml - 0.012) & (np.abs(s) < sw)
    V, F, s, win = cut_window(V, F, s, win, hx=H[:, 0], xlim=f["c"] + 0.0003)
    win = win & (np.abs(head_coords(V, G)[:, 0]) <= f["c"] + 0.0004)
    n = len(V)
    on = (s == 0.0) & win
    E = np.unique(np.sort(np.vstack([F[:, [0, 1]], F[:, [1, 2]], F[:, [2, 0]]]), axis=1), axis=0)
    E = E[on[E[:, 0]] & on[E[:, 1]]]
    if len(E) == 0:
        raise SystemExit("face: the mouth seam found no edges on the mouth line")
    L = np.linalg.norm(V[E[:, 0]] - V[E[:, 1]], axis=1)
    A = coo_matrix((np.r_[L, L], (np.r_[E[:, 0], E[:, 1]], np.r_[E[:, 1], E[:, 0]])), shape=(n, n)).tocsr()
    ids = np.flatnonzero(on)
    i0, i1 = int(ids[np.argmin(V[ids, 0])]), int(ids[np.argmax(V[ids, 0])])
    dist, pred = dijkstra(A, indices=i0, return_predecessors=True)
    if not np.isfinite(dist[i1]):
        raise _SeamBroken()
    path = [i1]
    while path[-1] != i0:
        path.append(int(pred[path[-1]]))
    path = path[::-1]
    inner = path[1:-1]
    dup = {p: n + j for j, p in enumerate(inner)}
    Vd = V[inner] - np.array([0.0, drop, 0.0])
    # รอบจุดในแถว: พัดสามเหลี่ยมแบ่งสองฝั่งที่ขอบของแถว ; ฝั่งที่ค่า s เฉลี่ยต่ำกว่า (ใต้แนว) ใช้จุดซ้ำ
    F0 = F
    F = F.copy()
    for i in range(1, len(path) - 1):
        v, pv, nv = path[i], path[i - 1], path[i + 1]
        nxt = {}
        for r in np.flatnonzero((F0 == v).any(axis=1)):
            f0 = list(F0[r])
            k = f0.index(v)
            nxt[int(f0[(k + 1) % 3])] = (int(f0[(k + 2) % 3]), int(r))
        arc, cur = [], pv
        while cur != nv and len(arc) <= len(nxt):
            if cur not in nxt:
                raise SystemExit("face: the fan around mouth seam vertex %d is open" % v)
            cur, r = nxt[cur]
            arc.append(r)
        if cur != nv:
            raise SystemExit("face: the fan around mouth seam vertex %d does not reach the next seam vertex" % v)
        other = [r for _, r in nxt.values() if r not in arc]
        mean = lambda rows: float(np.mean([s[[w for w in F0[r] if w != v]].mean() for r in rows])) if rows else 0.0
        low = arc if mean(arc) < mean(other) else other
        for r in low:
            F[r] = np.where(F[r] == v, dup[v], F[r])
    strip = []
    for p, q in zip(path[:-1], path[1:]):
        hit = np.flatnonzero((F == p).any(axis=1) & (F == q).any(axis=1))
        if len(hit) != 1:
            raise SystemExit("face: mouth seam edge %d-%d has %d upper triangles" % (p, q, len(hit)))
        f0 = list(F[hit[0]])
        k = f0.index(p)
        a, b = (p, q) if f0[(k + 1) % 3] == q else (q, p)
        da, db = dup.get(a, a), dup.get(b, b)
        for t in ((b, a, da), (b, da, db)):
            if len(set(t)) == 3:
                strip.append(t)
    F = np.vstack([F, np.array(strip, np.int64)])
    V = np.vstack([V, Vd])
    return V, F, (np.array(inner, np.int64), np.array([dup[p] for p in inner], np.int64), np.array([path[0], path[-1]], np.int64))
