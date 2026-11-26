# ร่างหลากหลายของทหาร (ชุดค่าที่ตั้งชื่อ): เพศ ส่วนสูง กล้าม ไขมัน รูปหน้า สีผิว ผม
#   build.py --variant NAME -> โฟลเดอร์สร้างของร่างนั้น (variants/<NAME>) ; ไม่เลือกร่าง = ทหารขั้น 1c เดิมทุกไบต์
#   ทุกจุดที่ร่างเปลี่ยนเช็ก CUR ก่อนเสมอ (CUR = None -> โค้ดเดิมทุกบรรทัด)
#   พิกัดทุกค่าในนี้ = กรอบท่า I ของทหารฐาน 1.78 ม. ; ส่วนสูงของร่างคือการย่อ/ขยายทั้งตัวตอนส่งออก (k = สูง / 1.78)
#   โครงเกม 23 กระดูกคงสัดส่วนเดิม × S = สูง / 1.6 (motion_scale = S) ; ศีรษะขยายต่างหาก (k^-0.6) ไม่ย่อตามตัวเต็มที่
#   รอบปรับ (refine): แก้ม/กรามเรียบ ตาไกลเปิดสองโทน ขอบผ้าตัดตามเส้นจริง หน้าแต่ละคนต่างกันชัด ร่างหญิงสองแบบ
import os
import numpy as np

BASE_H = 1.78
CUR = None
NAME = ""

# รูปร่างพื้นฐาน: realistic (0.17 ค่าเริ่ม) = natural + ร่างหลักและหญิง 1 ปรับตามภาพอ้างอิงใหม่ (หน้า คอ บ่า แขน น่อง สีผิว) ;
#   natural (0.14) = ไหล่ลาดลง บ่าแคบลง แขน/น่องเต็มขึ้น ; original = ร่างเดิมก่อน 0.14
#   ร่างเก่ายังสร้างได้ไบต์ต่อไบต์: BODY_SHAPE=natural (หรือ original) bash src/run_all.sh ; ชาย 2/3 หญิง 2 เหมือนกันทั้ง realistic/natural
SHAPE = os.environ.get("BODY_SHAPE", "realistic")
if SHAPE not in ("realistic", "natural", "original"):
    raise SystemExit("BODY_SHAPE must be realistic, natural or original (got %r)" % SHAPE)
REAL = SHAPE == "realistic"


def shp(orig, new):
    """ค่าของรูปร่างเดิม (original) หรือรูปร่างใหม่ (natural / realistic)"""
    return orig if SHAPE == "original" else new


def rl(nat, real):
    """ค่าของ natural/original หรือค่าตามภาพอ้างอิง (realistic) ; ใช้เฉพาะร่างหลักกับหญิง 1"""
    return real if REAL else nat

# กลุ่มกล้าม (ระดับกล้ามต่อบริเวณ)
MGROUP = {
    "neck": ("sternocleidomastoid", "neck_extensors", "neck_side", "scalenes", "levator_scapulae"),
    "trap": ("trapezius_upper", "trapezius_middle", "trapezius_lower"),
    "back": ("latissimus_dorsi", "erector_spinae", "infraspinatus_teres", "teres_major", "subscapularis", "supraspinatus",
             "rhomboids"),
    "chest": ("pectoralis_major", "pectoralis_minor", "subclavius", "serratus_anterior"),
    "abs": ("rectus_abdominis", "external_oblique"),
    "delt": ("deltoid",),
    "arm": ("biceps_brachii", "brachialis", "triceps_brachii", "coracobrachialis"),
    "farm": ("brachioradialis", "forearm_extensors", "forearm_flexors"),
    "hand": ("thenar", "hypothenar"),
    "glute": ("gluteus_maximus", "gluteus_medius", "tfl_itband"),
    "thigh": ("sartorius", "rectus_femoris", "vastus_lateralis", "vastus_medialis", "adductors", "gracilis", "iliopsoas",
              "biceps_femoris", "semitendinosus"),
    "calf": ("gastrocnemius_medial", "gastrocnemius_lateral", "soleus", "tibialis_anterior", "peroneus",
             "extensor_digitorum"),
    "face": ("masseter",),
}
M2G = {m: g for g, ms in MGROUP.items() for m in ms}

# ---------------- ผม: แนวไรผม y ตามมุมรอบศีรษะ (0 = หน้า 90 = ข้าง 180 = หลัง ; กรอบศีรษะท่า I) ----------------
TH = [0, 25, 45, 70, 95, 120, 150, 180]
HL_BASE = [1.738, 1.733, 1.715, 1.690, 1.672, 1.640, 1.612, 1.600]      # ผมเกรียนของทหารฐาน (mesh.colours)
HL_SHORT = [1.731, 1.727, 1.712, 1.688, 1.671, 1.636, 1.606, 1.594]     # ผมสั้นธรรมดา ไรผมหน้าต่ำลงเล็กน้อย
HL_FEM = [1.733, 1.728, 1.708, 1.682, 1.668, 1.630, 1.598, 1.588]       # ไรผมหญิง: มน ขมับเต็ม ท้ายทอยต่ำ
HL_CURL = [1.736, 1.731, 1.713, 1.689, 1.672, 1.636, 1.604, 1.592]

OLIVE_TOP = (0.355, 0.385, 0.240)       # สีเสื้อเดิม (รอบก่อน) ; รอบปรับใช้ top_col ของแต่ละร่าง

# ช่วงเกต G6 หญิง 1.66 ม. (ค่าอ้างอิงเดิม) ; แต่ละร่างตั้งช่วงตามส่วนสูงของตัวเองใน "ranges"
FEMALE_RANGES = {"stature": None, "chest": (84, 96), "waist": (66, 78), "hips": (90, 102), "neck": (31, 35),
                 "thigh": (52, 60), "calf": (33, 38), "upper_arm": (25, 31), "forearm": (21.5, 26.5),
                 "wrist": (14.5, 16.5), "head_height": (20.5, 23.5), "head_breadth": (13.8, 15.6),
                 "foot_length": (22.8, 25.8), "shoulder_breadth": (40, 46.5)}


_BLOB_F = [("pelvis", (0.150, 0.930, -0.010), (0.075, 0.095, 0.120), 1.85, 1.15),    # สะโพกด้านข้าง
           ("pelvis", (0.080, 0.875, -0.085), (0.090, 0.090, 0.070), 1.55, 1.10),    # ก้น (ต่ำลง 2 ซม. ไม่ดูยกสูง)
           ("pelvis", (0.000, 0.990, 0.100), (0.110, 0.055, 0.050), 1.12, 1.00),     # ท้องน้อย
           ("pelvis", (0.140, 1.150, 0.000), (0.060, 0.060, 0.130), 0.82, 1.00),     # เอวด้านข้าง (คอดเอว)
           ("hipL", (0.160, 0.820, 0.000), (0.060, 0.110, 0.100), 1.45, 1.10),       # ต้นขาด้านนอกบน
           ("hipL", (0.070, 0.800, 0.000), (0.050, 0.110, 0.080), 1.25, 1.00),       # ต้นขาด้านใน
           ("shoulderL", (0.200, 1.290, -0.045), (0.050, 0.090, 0.040), 1.35, 1.10),  # หลังต้นแขน
           ("chest", (0.100, 1.430, 0.072), (0.055, 0.030, 0.045), 1.55, 1.10)]      # ใต้ไหปลาร้า (สูงขึ้น ไม่เป็นหลุมใต้สายเสื้อ)
NECK_SH = ("chest", (0.072, 1.474, -0.018), (0.034, 0.024, 0.040), 1.45, 1.35)       # รอยต่อคอ-บ่า มน (หญิง)


def _blob_f(s=1.0):
    """แบบไขมันหญิง: (กระดูก, ศูนย์ท่า I ข้างซ้าย, รัศมี, คูณ T, คูณ R) ; ข้างขวาสะท้อนเอง ; s = แรง (1 = เต็ม)"""
    return [(b, c, r, 1 + s * (mt - 1), 1 + s * (mr - 1)) for b, c, r, mt, mr in _BLOB_F]


def _jaw_blobs(mt, mr):
    """ไขมันแก้ม/กรามหนาขึ้น + รัศมีเติมร่องกว้างขึ้น (ร่องเล็กบนกรามไม่เป็นคราบใต้ไฟบน)"""
    return [("head", (0.050, 1.598, 0.045), (0.034, 0.046, 0.042), mt, mr),
            ("head", (0.000, 1.556, 0.040), (0.046, 0.020, 0.042), mt, mr)]


# ---------------- ชุดแก้หน้า (รวมได้หลายชุด) ----------------
EYE_PRIMS = ("eyeball_L", "cornea_L", "eye_pit_L", "lid_upper_L", "lid_lower_L", "eye_open_L", "eye_socket_L")


def _fx(*ds):
    """รวมชุดแก้หน้า: dc/da/db/dpts บวกกัน ; sr คูณรายแกน ; srr/srt/spx คูณ ; set รวม ; sec/secy ต่อรายการ"""
    out = {}
    for d in ds:
        for n, e in d.items():
            o = out.setdefault(n, {})
            for k, v in e.items():
                if k in ("dc", "da", "db", "dpts"):
                    o[k] = tuple(float(a) for a in np.add(o.get(k, (0.0, 0.0, 0.0)), v))
                elif k == "sr":
                    o[k] = tuple(float(a) for a in np.multiply(o.get(k, (1.0, 1.0, 1.0)), v))
                elif k in ("srr", "srt", "spx"):
                    o[k] = o.get(k, 1.0) * v
                elif k == "set":
                    o[k] = dict(o.get(k, {}), **v)
                else:
                    o[k] = list(o.get(k, [])) + list(v)
    return out


def _eyes(dx=0.0, dy=0.0, dz=0.0):
    """ย้ายตาทั้งชุด (ลูกตา กระจกตา เปลือกตา ช่องตา หลุมรอบตา) ; dx บวก = ตาห่างกันขึ้น"""
    return {n: {"dc": (dx, dy, dz)} for n in EYE_PRIMS}


def _ears(s=1.0, dx=0.0, yaw=-18.0):
    """หู: ขนาด s, ย้ายเข้า/ออก dx, กางออก (yaw ติดลบมาก = กาง) ; ร่องหูหมุน/ย่อตามหู"""
    from sdfk import rotm
    r0 = rotm([1, 0, 0], -14) @ rotm([0, 1, 0], -18)
    r1 = rotm([1, 0, 0], -14) @ rotm([0, 1, 0], yaw)
    off = np.array([0.0825 - 0.0755, 1.6460 - 1.6430, -0.0060 + 0.0080])
    off2 = s * (r1 @ r0.T @ off)
    return {"ear_L": {"sr": (s, s, s), "dc": (dx, 0.0, 0.0), "set": {"rot": r1}},
            "ear_concha_L": {"sr": (s, s, s), "dc": tuple(float(a) for a in (np.array([dx, 0, 0]) + off2 - off)),
                             "set": {"rot": r1}}}


def _mouth(dy=0.0, dz=0.0, sx=1.0):
    """ปากทั้งชุด: ย้าย (dy, dz) + กว้าง sx (ริมฝีปาก ร่องปาก เนินปาก ร่องใต้ปาก)"""
    d = (0.0, dy, dz)
    return {"lip_upper": {"dpts": d, "spx": sx}, "lip_lower": {"dpts": d, "spx": sx}, "mouth_line": {"dpts": d, "spx": sx},
            "mouth_mound": {"dc": d}, "mentolabial": {"dc": d}}


def _nose_base(dy=0.0, dz=0.0):
    """ฐานจมูกขึ้น/ลง (หน้ากลางยาว/สั้น)"""
    d = (0.0, dy, dz)
    return {"nose_tip": {"dc": d}, "nose_ala_L": {"dc": d}, "columella": {"da": d, "db": d},
            "nose_body": {"dc": (0.0, 0.6 * dy, 0.6 * dz)}, "nose_bridge": {"db": (0.0, 0.4 * dy, 0.4 * dz)}}


def _chin(dy, dz=0.0):
    """คางขึ้น (dy บวก = หน้าล่างสั้นลง) / ลง: ลอฟต์ศีรษะส่วนล่าง + เนื้อคาง + ใต้คาง"""
    return {"head_base": {"secy": [(1.540, dy), (1.556, 0.95 * dy), (1.570, 0.75 * dy), (1.585, 0.40 * dy), (1.600, 0.0)]},
            "chin_soft": {"dc": (0.0, dy, dz)}, "submental": {"dc": (0.0, 0.9 * dy, dz)},
            "mentolabial": {"dc": (0.0, 0.3 * dy, 0.0)}}


def _face_f1():
    # หน้าแบบเอเชียตะวันออกเฉียงใต้: สันจมูกต่ำ ปีกจมูกกว้าง หน้าผาก/คิ้วเรียบ โหนกแก้มเต็มยื่นหน้า เปลือกตาบนอิ่ม หน้าล่างสั้น
    E = {"head_base": {"sec": [("a", [(1.548, 0.86), (1.556, 0.88), (1.570, 0.91), (1.585, 0.925), (1.600, 0.94),
                                      (1.620, 0.965), (1.640, 0.99), (1.660, 1.0)]),
                               ("bf", [(1.600, 1.0), (1.630, 0.985), (1.660, 0.98), (1.690, 0.985), (1.720, 1.0)])]},
         "chin_soft": {"sr": (0.82, 0.90, 0.88), "dc": (0, 0.0015, -0.0012)},
         "submental": {"sr": (0.85, 1.0, 0.9)},
         "brow_L": {"sr": (0.92, 0.80, 0.40), "dc": (0, 0.0010, -0.0030)},
         "glabella": {"sr": (0.70, 0.70, 0.35), "dc": (0, 0, -0.0030)},
         "cheekbone_L": {"sr": (1.10, 1.08, 1.15), "dc": (0.0015, 0.0008, 0.0028)},
         "cheek_fill_L": {"sr": (0.90, 0.90, 0.90)},
         "buccal_L": {"sr": (0.90, 0.92, 0.90)},
         "nose_bridge": {"srr": 0.85, "da": (0, 0.0, -0.0028), "db": (0, 0.0010, -0.0035)},
         "nose_body": {"sr": (0.96, 0.92, 0.85), "dc": (0, 0.0008, -0.0024)},
         "nose_tip": {"sr": (0.98, 0.92, 0.90), "dc": (0, 0.0012, -0.0032)},
         "nose_ala_L": {"sr": (1.08, 0.95, 0.95), "dc": (0.0016, 0.0010, -0.0012)},
         "columella": {"srr": 0.90, "da": (0, 0.0012, -0.0030), "db": (0, 0.0012, -0.0012)},
         "lip_upper": {"srt": 1.10}, "lip_lower": {"srt": 1.14},
         "mouth_mound": {"sr": (1.0, 1.0, 0.88)},
         "eye_open_L": {"set": {"hu": 0.0054, "hw": 0.0150, "hl": 0.0046, "tilt": 9.0}, "dc": (0.0010, 0, 0)},
         "lid_upper_L": {"set": {"t": 0.0030}}}
    if REAL:
        # ใหม่ 0.17 ตามภาพอ้างอิง: หน้าล่างยาวขึ้น ปากกว้างอิ่ม ปีกจมูกกว้างขึ้น
        E = _fx(E, {"lip_upper": {"srt": 1.16}, "lip_lower": {"srt": 1.16}, "nose_ala_L": {"sr": (1.06, 1.0, 1.0)},
                    "cheekbone_L": {"sr": (0.91, 1.0, 1.0), "dc": (-0.0015, 0, 0)},      # โหนกแก้มไม่ยื่นข้าง (หน้ารูปไข่)
                    "head_base": {"sec": [("a", [(1.548, 1.04), (1.570, 1.06), (1.600, 1.04), (1.640, 1.0)])]}})
        return _fx(E, _eyes(dx=0.0012), _chin(0.0015), _mouth(dy=0.0004, dz=-0.0010, sx=1.03), _ears(0.88, -0.0020, -12.0))
    return _fx(E, _eyes(dx=0.0012), _chin(0.0040), _mouth(dy=0.0012, dz=-0.0010, sx=0.95), _ears(0.88, -0.0020, -12.0))


def _face_f2():
    # โหนกแก้มกว้างสูง ตากลมโตห่างกัน ปากอิ่ม จมูกกว้างพอดี กรามนุ่ม หูเล็ก
    E = {"head_base": {"sec": [("a", [(1.548, 0.90), (1.556, 0.92), (1.570, 0.95), (1.585, 0.96), (1.600, 0.97),
                                      (1.620, 1.0), (1.640, 1.03), (1.660, 1.01)])]},
         "cheekbone_L": {"sr": (1.16, 1.12, 1.18), "dc": (0.0035, 0.0012, 0.0012)},
         "cheek_fill_L": {"sr": (0.92, 0.92, 0.95)},
         "buccal_L": {"sr": (0.90, 0.92, 0.90)},
         "chin_soft": {"sr": (0.86, 0.90, 0.90), "dc": (0, 0.0010, -0.0008)},
         "brow_L": {"sr": (0.92, 0.82, 0.50), "dc": (0, 0.0006, -0.0028)},
         "glabella": {"sr": (0.75, 0.75, 0.45), "dc": (0, 0, -0.0024)},
         "nose_bridge": {"srr": 0.90, "db": (0, 0.0, -0.0022)},
         "nose_body": {"sr": (1.18, 0.95, 0.95), "dc": (0, 0.0, -0.0012)},
         "nose_tip": {"sr": (1.12, 1.0, 1.0), "dc": (0, 0.0004, -0.0018)},
         "nose_ala_L": {"sr": (1.18, 1.12, 1.15), "dc": (0.0024, 0.0004, -0.0006)},
         "columella": {"srr": 1.05, "da": (0, 0.0004, -0.0018)},
         "lip_upper": {"srt": 1.30}, "lip_lower": {"srt": 1.34},
         "mouth_mound": {"sr": (1.04, 1.05, 1.05)},
         "eye_open_L": {"set": {"hu": 0.0066, "hw": 0.0154, "hl": 0.0050, "tilt": 6.0}}}
    return _fx(E, _eyes(dx=0.0020), _mouth(dz=-0.0008, sx=1.02), _ears(0.94, -0.0010, -16.0))


def _face_m2():
    # กรามกว้าง คางเหลี่ยมยาว จมูกกว้าง ปากอิ่ม คิ้วหนาสันคิ้วเด่น ตาเล็กห่าง โหนกแก้มต่ำ
    E = {"head_base": {"sec": [("a", [(1.548, 1.06), (1.556, 1.07), (1.570, 1.075), (1.585, 1.075), (1.600, 1.065),
                                      (1.620, 1.04), (1.640, 1.02), (1.660, 1.0)])]},
         "chin_soft": {"sr": (1.30, 1.05, 1.05)},
         "submental": {"sr": (1.15, 1.05, 1.05)},
         "nose_bridge": {"srr": 1.10, "db": (0, -0.0004, -0.0018)},
         "nose_body": {"sr": (1.32, 1.0, 1.0), "dc": (0, -0.0004, -0.0010)},
         "nose_tip": {"sr": (1.20, 1.06, 1.05), "dc": (0, -0.0006, -0.0016)},
         "nose_ala_L": {"sr": (1.25, 1.18, 1.20), "dc": (0.0032, -0.0002, -0.0008)},
         "columella": {"srr": 1.10, "da": (0, -0.0006, -0.0016)},
         "lip_upper": {"srt": 1.30}, "lip_lower": {"srt": 1.32},
         "mouth_mound": {"sr": (1.06, 1.05, 1.08)},
         "brow_L": {"sr": (1.06, 1.05, 1.15), "dc": (0, -0.0005, 0.0015)},
         "glabella": {"sr": (1.10, 1.0, 1.20), "dc": (0, 0, 0.0012)},
         "cheekbone_L": {"dc": (0.0010, -0.0020, 0.0)},
         "eye_open_L": {"set": {"hu": 0.0056, "hw": 0.0140, "hl": 0.0046, "tilt": 4.0}}}
    return _fx(E, _eyes(dx=0.0015), _chin(-0.0020), _mouth(dz=-0.0008, sx=1.05), _ears(1.06, 0.0005, -20.0))


def _face_m3():
    # หน้าแคบยาว คางต่ำ หน้ากลางยาว จมูกยาวตรง ปากบาง สันคิ้วเด่น ตาลึกชิดกัน หูใหญ่กาง โหนกแก้มสูง
    E = {"head_base": {"sec": [("a", [(1.548, 0.94), (1.556, 0.94), (1.570, 0.945), (1.585, 0.95), (1.600, 0.955),
                                      (1.620, 0.96), (1.640, 0.97), (1.660, 0.985), (1.680, 1.0)])]},
         "chin_soft": {"sr": (0.92, 1.08, 1.0), "dc": (0, 0.0, 0.0010)},
         "cheekbone_L": {"sr": (0.96, 1.0, 0.96), "dc": (-0.0015, 0.0022, 0)},
         "buccal_L": {"sr": (0.92, 1.0, 0.95)},
         "nose_bridge": {"srr": 0.92, "da": (0, 0.0006, 0.0004), "db": (0, -0.0030, 0.0016)},
         "nose_body": {"sr": (0.90, 1.10, 1.0), "dc": (0, -0.0024, 0.0010)},
         "nose_tip": {"sr": (0.92, 0.95, 0.95), "dc": (0, -0.0034, 0.0016)},
         "nose_ala_L": {"sr": (0.90, 0.92, 0.92), "dc": (-0.0010, -0.0026, 0.0002)},
         "columella": {"srr": 0.92, "da": (0, -0.0034, 0.0014), "db": (0, -0.0026, 0.0004)},
         "lip_upper": {"srt": 0.80}, "lip_lower": {"srt": 0.80},
         "mouth_mound": {"sr": (1.0, 1.0, 0.88)},
         "brow_L": {"sr": (1.04, 1.05, 1.20), "dc": (0, 0, 0.0015)},
         "glabella": {"sr": (1.05, 1.0, 1.15), "dc": (0, 0, 0.0012)},
         "eye_open_L": {"set": {"hu": 0.0056, "hl": 0.0046, "tilt": 3.0, "hw": 0.0144}}}
    return _fx(E, _eyes(dx=-0.0015, dz=-0.0008), _nose_base(dy=-0.0015), _mouth(dy=-0.0030, dz=-0.0008, sx=0.98),
               _chin(-0.0050), _ears(1.08, 0.0015, -26.0))


def _face_base():
    # ใหม่ 0.17 ร่างหลักตามภาพอ้างอิง: กรามกว้างเหลี่ยม คางกว้าง ตาชิดขึ้นเล็กน้อย ฐานจมูก/ปากสูงขึ้น ปากแคบอิ่ม หูเล็กลง
    E = {"head_base": {"sec": [("a", [(1.548, 1.20), (1.556, 1.25), (1.570, 1.20), (1.585, 1.14), (1.600, 1.11),
                                      (1.620, 1.06), (1.640, 1.01), (1.755, 1.01), (1.781, 1.0)])]},
         "scalp": {"sr": (1.01, 1.0, 1.0)},
         "chin_soft": {"sr": (1.25, 1.0, 1.0)},
         "nose_body": {"sr": (1.15, 1.0, 1.0)},
         "submental": {"sr": (1.12, 1.0, 1.0)},
         "nose_bridge": {"srr": 1.08, "da": (0, 0, -0.0015)},
         "nose_ala_L": {"sr": (1.08, 1.0, 1.0), "dc": (0.0008, 0, 0)},
         "lip_upper": {"srt": 1.06}, "lip_lower": {"srt": 1.06},
         "mouth_mound": {"sr": (1.0, 1.0, 0.75)},
         "eye_open_L": {"set": {"hu": 0.0050, "hl": 0.0042, "tilt": 7.0}}}
    return _fx(E, _eyes(dx=-0.0015), _nose_base(dy=0.0030), _mouth(dy=0.0030, dz=-0.0025, sx=0.95),
               _ears(0.92, -0.0010, -18.0))


# ใหม่ 0.17 (realistic): ร่างหลักตามภาพอ้างอิง (ไม่ใช่ร่างหลากหลาย: ยังมี blend shape ส่วนสูง 1.78 ม. ศีรษะไม่ขยาย)
BASE_REAL = {
    "face": _face_base(),
    "cores": {"neck_core": {"sec": [("a", [(1.455, 1.02), (1.50, 1.05), (1.60, 1.05), (1.635, 1.02)]),
                                    ("bf", [(1.455, 1.0), (1.50, 0.95), (1.60, 0.95), (1.635, 1.0)]),
                                    ("bb", [(1.455, 1.0), (1.50, 0.93), (1.60, 0.93), (1.635, 1.0)])]}},
    "muscle": {"all": 1.0, "trap": 1.25, "delt": 0.90, "farm": 0.93, "calf": 1.03},
    "face_smooth": 40.0,          # แก้ม/กรามเรียบแบบร่างหลากหลาย (ไม่เป็นคลื่นใต้ไฟบน)
    # เนินบ่า: คอลาดลงถึงปลายบ่าเป็นเส้นเดียว (ภาพอ้างอิง) ไม่เป็นชั้นไหปลาร้าแนวนอน : (ต้น, ปลาย, รัศมีต้น, รัศมีปลาย, k)
    "slope_pad": ((0.070, 1.505, -0.030), (0.170, 1.468, -0.022), 0.022, 0.014, 0.020),
}

_JUG_F = ((0.0, 1.492, 0.038), (0.013, 0.013, 0.011))      # หญิง: แอ่งเหนือกระดูกอก (เล็กลง คอมีไขมันมากขึ้นแล้ว)
_INFRA = ((0.125, 1.425, 0.058), (0.040, 0.020, 0.018), 0.020)    # หญิง: ร่องใต้ไหปลาร้า/ร่องอก-ไหล่ ใต้สายเสื้อ
_MALAR = ((0.034, 1.640, 0.082), (0.016, 0.012, 0.010), 0.020)    # หญิง: เนื้อแก้มสูง (ใต้ตา) แทนแก้มล่างอูม

VARIANTS = {
    "m2": {
        "label": "ชาย 1.86 ม. ผิวน้ำตาลเข้ม ผมเกรียนดำ กรามกว้าง ร่างใหญ่ท้องหนา",
        "label_en": "male 1.86 m, deep brown skin, black buzz cut, broad jaw, heavy build",
        "sex": "m", "stature": 1.86, "fat": 1.40,
        "muscle": {"all": 1.10, "neck": 1.14, "chest": 1.12, "delt": 1.12, "arm": 1.12, "trap": 1.12},
        "fat_seg": {"trunk": 1.0},
        "blobs": [("pelvis", (0.000, 1.085, 0.105), (0.130, 0.110, 0.075), 1.80, 1.10),     # ท้อง (พุงเห็นชัด)
                  ("pelvis", (0.135, 1.095, 0.000), (0.050, 0.070, 0.095), 1.30, 1.10)]     # สีข้าง
                 + _jaw_blobs(1.0, 1.3),
        "cores": {"thorax": {"sec": [("a", [(1.18, 1.04), (1.49, 1.03)]), ("bf", [(1.18, 1.04), (1.49, 1.02)])]},
                  "abdomen": {"sec": [("a", [(0.96, 1.05), (1.225, 1.06)]), ("bf", [(0.96, 1.08), (1.225, 1.06)])]},
                  "neck_core": {"sec": [("a", [(1.455, 1.06), (1.635, 1.04)]), ("bf", [(1.455, 1.05), (1.635, 1.03)]),
                                        ("bb", [(1.455, 1.06), (1.635, 1.04)])]}},
        "face": _face_m2(),
        "skin": (0.430, 0.285, 0.205), "lip_k": (0.86, 0.74, 0.80), "lip_mix": 0.60, "iris": (0.20, 0.12, 0.08),
        "sclera": (0.76, 0.72, 0.67), "brow": (0.08, 0.065, 0.06), "palm": (0.46, 0.40, 0.36),
        "beard": 0.05, "lash": 0.35, "brow_a": 0.46,
        "brow_shape": {"dy": 0.0, "w": 0.0056, "arch": 0.0004, "taper": 0.30, "soft": 0.002, "slope": 0.0},
        "hair": {"col": (0.050, 0.044, 0.042), "cover": 0.80, "line": HL_BASE, "soft": 0.014, "thick": (1.0, 1.0, 1.0),
                 "curl": 0.0, "bun": None},
        "face_smooth": 50.0, "lowlift": 0.08, "eyelift": 0.0,
        "ranges": {"stature": (184, 189), "chest": (104, 118), "waist": (96, 110), "hips": (102, 114), "neck": (41, 47),
                   "thigh": (58, 68), "calf": (38, 44), "upper_arm": (33, 40), "forearm": (29, 34),
                   "wrist": (17.5, 19.5), "head_height": (22.5, 25.5), "head_breadth": (15.2, 16.8),
                   "foot_length": (27.0, 29.5), "shoulder_breadth": (47, 53)},
    },
    "m3": {
        "label": "ชาย 1.70 ม. ผิวขาว ผมสั้นสีน้ำตาลยกหน้า หน้าแคบยาว จมูกยาว ร่างผอมเกร็ง",
        "label_en": "male 1.70 m, light skin, short brown hair with volume, long narrow face, long nose, wiry",
        "sex": "m", "stature": 1.70, "fat": 0.80,
        "muscle": {"all": 0.80, "delt": 0.72, "chest": 0.78},
        "grooves": {"all": 0.25},
        "blobs": _jaw_blobs(1.0, 1.3),
        "cores": {"thorax": {"sec": [("a", [(1.18, 0.975), (1.49, 0.975)])]},
                  "abdomen": {"sec": [("a", [(0.96, 0.965), (1.225, 0.97)]), ("bf", [(0.96, 0.955), (1.225, 0.965)])]},
                  "neck_core": {"sec": [("a", [(1.455, 0.97), (1.635, 0.97)])]}},
        "face": _face_m3(),
        "skin": (0.900, 0.750, 0.620), "lip_k": (0.86, 0.70, 0.72), "lip_mix": 0.50, "iris": (0.40, 0.34, 0.20),
        "sclera": (0.78, 0.74, 0.70), "brow": (0.30, 0.20, 0.13), "palm": (0.06, 0.04, 0.04),
        "beard": 0.05, "lash": 0.35, "brow_a": 0.42, "ao_head": 0.93,
        "brow_shape": {"dy": 0.0006, "w": 0.0046, "arch": 0.0012, "soft": 0.002},
        "jugular_pad": ((0.0, 1.492, 0.040), (0.016, 0.016, 0.014)),   # ผอม: แอ่งเหนือกระดูกอกไม่เป็นโพรง
        "hair": {"col": (0.360, 0.245, 0.150), "cover": 0.93, "line": HL_SHORT, "soft": 0.016, "thick": (12.0, 3.0, 3.5),
                 "rise": 0.032, "curl": 0.0, "bun": None},
        "face_smooth": 70.0, "lowlift": 0.09, "eyelift": 0.03,
        "detail_head_ymax": 1.84,
        "ranges": {"stature": (168, 173), "chest": (85, 96), "waist": (71, 82), "hips": (85, 96), "neck": (34, 39),
                   "thigh": (47, 55), "calf": (32, 37), "upper_arm": (25.5, 31), "forearm": (23.5, 27.5),
                   "wrist": (15.5, 17.5), "head_height": (21.5, 24.5), "head_breadth": (14.3, 15.9),
                   "foot_length": (24.6, 26.6), "shoulder_breadth": (41.5, 47.5)},
    },
    "f1": {
        "label": "หญิง 1.60 ม. ผิวแทน หน้าแบบเอเชียตะวันออกเฉียงใต้ ผมดำตรงมวยสูง สะโพกผาย",
        "label_en": "female 1.60 m, tan skin, Southeast Asian face, straight black hair in a high bun, pear shape",
        "sex": "f", "stature": 1.60, "fat": 1.0,
        "head_k": rl(None, 1.035),      # 0.17: ศีรษะเล็กลง (ภาพอ้างอิง ~7.3 หัว) ; None = k^-0.6 (1.066)
        # 0.14 (natural): แขนท่อนล่างคงสัดส่วนเดิมกับต้นแขน (เทียบอ้างอิงหญิง)
        # 0.17 (realistic): คอ บ่า แขนเรียวลง ต้นขาบางลง ตามภาพอ้างอิง
        "muscle": {"all": 0.72, "neck": rl(0.58, 0.48), "trap": rl(0.50, 0.58), "delt": rl(0.56, 0.50), "chest": 0.60,
                   "arm": rl(0.64, 0.60), "farm": shp(0.76, rl(0.66, 0.60)),
                   "abs": 0.78, "back": 0.70, "glute": 0.86, "thigh": 0.86, "calf": 0.90, "face": 0.70},
        "fat_seg": {"thigh": rl(1.38, 1.18), "shank": 1.22, "uarm": 1.15, "farm": 1.05, "neck": rl(1.15, 1.0)},
        "fat_rseg": {"thigh": 1.12, "shank": 1.12, "uarm": 1.15, "farm": 1.10, "neck": 1.30},
        "blobs": _blob_f(1.1) + [NECK_SH] + _jaw_blobs(1.3, 1.6),
        "cores": {"thorax": {"sec": [("a", [(1.18, 0.93), (1.375, 0.93), (1.46, 0.95), (1.49, 0.97)]),
                                     ("bf", [(1.18, 0.95), (1.42, 0.95), (1.49, 0.97)]),
                                     ("bb", [(1.18, 0.96), (1.42, 0.96), (1.49, 0.98)])]},
                  "abdomen": {"sec": [("a", [(0.96, 1.03), (1.00, 1.02), (1.06, 0.97), (1.12, 0.90), (1.18, 0.90),
                                             (1.225, 0.92)]),
                                      ("bf", rl([(0.96, 1.0), (1.06, 0.98), (1.12, 0.95), (1.225, 0.95)],
                                                [(0.96, 1.0), (1.03, 0.93), (1.08, 0.92), (1.12, 0.95), (1.17, 1.0), (1.225, 1.0)]))]   # 0.17: เอวบางลง (มองข้าง) ; เหนือ 1.12 คงเดิม (เกต G12)
                                      + rl([], [("bb", [(0.96, 1.0), (1.06, 0.92), (1.14, 0.90), (1.20, 0.95), (1.225, 1.0)])])},
                  "pelvis_core": {"sec": [("a", [(0.842, 1.0), (0.93, 1.05), (0.98, 1.06), (1.03, 1.05), (1.07, 1.02)]),
                                          ("bb", rl([(0.842, 1.0), (0.93, 1.04), (1.07, 1.02)],
                                                    [(0.842, 1.0), (0.93, 0.98), (1.07, 0.97)]))]},
                  "neck_core": {"sec": [("a", [(1.455, 0.92), (1.50, 0.88), (1.60, 0.88), (1.635, 0.92)]),
                                        ("bf", rl([(1.455, 0.94), (1.50, 0.90), (1.60, 0.90), (1.635, 0.94)],
                                                  [(1.455, 0.94), (1.50, 0.80), (1.60, 0.80), (1.635, 0.94)])),
                                        ("bb", rl([(1.455, 0.94), (1.50, 0.90), (1.60, 0.90), (1.635, 0.94)],
                                                  [(1.455, 0.94), (1.50, 0.80), (1.60, 0.80), (1.635, 0.94)]))]},
                  "larynx": {"sr": (0.70, 0.75, 0.55), "dc": (0, 0, -0.0045)},
                  "upperarm_core_L": {"srr": rl(0.88, 0.85)},
                  "forearm_core_L": {"srt": rl(0.94, 0.89)},
                  "wrist_block_L": {"sr": rl((0.95, 1.0, 0.95), (0.90, 1.0, 0.92))}},
        # อกแบบเสื้อกีฬารัด: ก้มลง 15° ต่ำลง 6 มม. แบนลง ; แผ่นลาดอกบน (ไหปลาร้า -> ยอดอก เส้นตรง) ; สะพานกลางอกต่ำลง
        "breasts": {"c": (0.086, 1.292, 0.078), "r": (0.059, 0.055, 0.038), "yaw": 13.0, "pitch": -15.0, "k": 0.028,
                    "bridge": ((0.0, 1.294, 0.084), (0.040, 0.040, 0.030)),
                    "upper": ((0.075, 1.345, 0.060), (0.060, 0.030, 0.028), 0.030),
                    "lower": [((0.080, 1.226, 0.068), (0.060, 0.020, 0.032), 0.025),
                              ((0.080, 1.200, 0.064), (0.058, 0.020, 0.028), 0.025)]},
        "infraclav": _INFRA, "malar": _MALAR,
        "slope_pad": rl(None, ((0.060, 1.500, -0.028), (0.165, 1.462, -0.020), 0.017, 0.012, 0.020)),   # 0.17: บ่าลาด
        "epicanthus": ((0.0188, 1.6655, 0.0868), (0.0034, 0.0046, 0.0020), 0.004),   # รอยพับหัวตา
        "grooves": {"all": 0.35, "pe": 0.0, "sl": 0.3, "nv": 0.35},
        "pec_band": 0.0, "ra_mask": 0.45, "jugular_pad": _JUG_F,
        "top": True, "racer": True, "top_col": (0.530, 0.490, 0.350),      # เสื้อกล้ามหลังไขว้สีทรายกากี
        "face": _face_f1(),
        "skin": rl((0.800, 0.600, 0.450), (0.840, 0.660, 0.520)), "lip_k": (0.88, 0.70, 0.76), "lip_mix": 0.54,
        "iris": (0.18, 0.11, 0.07),
        "sclera": (0.77, 0.73, 0.68), "brow": (0.07, 0.06, 0.055), "palm": (0.10, 0.08, 0.07),
        "beard": 0.0, "lash": 0.32, "brow_a": rl(0.38, 0.55),
        "hair": {"col": (0.042, 0.038, 0.040), "cover": 0.96, "line": HL_FEM, "soft": 0.016, "thick": (4.5, 3.2, 4.0),
                 "rise": 0.028, "curl": 0.0,
                 # 0.17: มวยต่ำที่ท้ายทอย (ระดับหู) ตามภาพอ้างอิง ; เดิมมวยสูง
                 "bun": rl({"c": (0.0, 1.760, -0.084), "r": (0.040, 0.035, 0.033), "k": 0.012},
                           {"c": (0.0, 1.668, -0.118), "r": (0.040, 0.038, 0.034), "k": 0.012})},
        "brow_shape": rl({"dy": 0.0012, "w": 0.0045, "arch": 0.0012, "soft": 0.002},
                         {"dy": -0.0008, "w": 0.0050, "arch": 0.0008, "soft": 0.002}),      # 0.17: คิ้วต่ำลง ตรงขึ้น เข้มขึ้น
        "face_smooth": 80.0, "lowlift": 0.09, "eyelift": 0.02,
        "detail_head_zmin": -0.165, "detail_head_ymax": 1.84,
        # ใหม่ 0.14 (natural): สามเหลี่ยมเพิ่มที่มุมคอ-สายเสื้อด้านหลัง (mid: ขอบผ้า G11) และยอดมวยผม (min: ความสูง G4)
        "lod_spots": shp(None, {"mid": [((sx * 0.080, 1.492, -0.062), (0.030, 0.030, 0.035), 0.45) for sx in (1.0, -1.0)],
                                "min": [(rl((0.0, 1.796, -0.085), (0.0, 1.668, -0.150)), (0.035, 0.030, 0.035), 0.6),
                                        ((0.0, 1.450, -0.120), (0.030, 0.035, 0.030), 0.5)]}),   # + กลางหลังบน (min: สมมาตร G3)
        "lod_band": shp(None, {"mid": 0.35}),       # 0.14 (natural): mid เก็บจุดยอดตามขอบเสื้อ (คอหน้า G11)
        "ranges": {"stature": (158, 163), "chest": (80, 92), "waist": (62, 74), "hips": (88, 100), "neck": (30, 34.5),
                   "thigh": (49, 58), "calf": (31.5, 36.5), "upper_arm": (24, 30), "forearm": (20.5, 25.5),
                   "wrist": (14, 16), "head_height": (20.5, 23.5), "head_breadth": (13.8, 15.6),
                   "foot_length": (22.0, 24.8), "shoulder_breadth": (38.5, 45)},
    },
    "f2": {
        "label": "หญิง 1.73 ม. ผิวน้ำตาลเข้ม ผมหยิกฟูสีน้ำตาลดำ โหนกแก้มกว้าง ร่างนักกีฬาตรง",
        "label_en": "female 1.73 m, dark brown skin, full curly dark hair, wide cheekbones, straight athletic build",
        "sex": "f", "stature": 1.73, "fat": 0.80,
        # 0.14 (natural): แขนท่อนล่างคงสัดส่วนเดิมกับต้นแขน (เทียบอ้างอิงหญิง)
        "muscle": {"all": 0.84, "neck": 0.66, "trap": 0.62, "delt": 0.66, "chest": 0.70, "arm": 0.80, "farm": shp(0.86, 0.80),
                   "abs": 0.90, "back": 0.82, "glute": 1.0, "thigh": 1.0, "calf": 1.0, "face": 0.75},
        "lod_band": shp(None, {"hi": 0.35, "mid": 0.35}),   # 0.14 (natural): hi/mid เก็บจุดยอดตามขอบเสื้อ (ขอบผ้า G11)
        "fat_seg": {"thigh": 1.0, "shank": 1.0, "uarm": 1.0, "neck": 1.05},
        "fat_rseg": {"neck": 1.30},
        "blobs": _blob_f(0.40) + [NECK_SH] + _jaw_blobs(1.3, 1.6),
        "cores": {"thorax": {"sec": [("a", [(1.18, 0.94), (1.375, 0.94), (1.46, 0.96), (1.49, 0.97)]),
                                     ("bf", [(1.18, 0.96), (1.42, 0.96), (1.49, 0.97)]),
                                     ("bb", [(1.18, 0.97), (1.42, 0.97), (1.49, 0.98)])]},
                  "abdomen": {"sec": [("a", [(0.96, 1.03), (1.00, 1.02), (1.06, 0.99), (1.12, 0.96), (1.18, 0.96),
                                             (1.225, 0.97)]),
                                      ("bf", [(0.96, 1.0), (1.06, 0.98), (1.12, 0.96), (1.225, 0.96)])]},
                  "pelvis_core": {"sec": [("a", [(0.842, 1.0), (0.93, 1.02), (0.98, 1.02), (1.03, 1.02), (1.07, 1.01)]),
                                          ("bb", [(0.842, 1.0), (0.93, 1.02), (1.07, 1.01)])]},
                  "neck_core": {"sec": [("a", [(1.455, 0.93), (1.50, 0.89), (1.60, 0.89), (1.635, 0.93)]),
                                        ("bf", [(1.455, 0.95), (1.50, 0.91), (1.60, 0.91), (1.635, 0.95)]),
                                        ("bb", [(1.455, 0.95), (1.50, 0.91), (1.60, 0.91), (1.635, 0.95)])]},
                  "larynx": {"sr": (0.72, 0.75, 0.58), "dc": (0, 0, -0.0042)},
                  "upperarm_core_L": {"srr": 0.92},
                  "forearm_core_L": {"srt": 0.96}},
        "breasts": {"c": (0.086, 1.290, 0.076), "r": (0.0485, 0.045, 0.033), "yaw": 13.0, "pitch": -15.0, "k": 0.028,
                    "bridge": ((0.0, 1.292, 0.080), (0.034, 0.034, 0.027)),
                    "upper": ((0.075, 1.345, 0.058), (0.056, 0.028, 0.025), 0.030),
                    "lower": [((0.080, 1.232, 0.068), (0.055, 0.020, 0.032), 0.025),
                              ((0.080, 1.204, 0.064), (0.052, 0.020, 0.028), 0.025)]},
        "infraclav": ((0.125, 1.425, 0.058), (0.038, 0.019, 0.016), 0.020), "malar": _MALAR,
        "grooves": {"all": 0.45, "pe": 0.0, "sl": 0.40, "nv": 0.30},
        "pec_band": 0.0, "ra_mask": 0.55, "jugular_pad": _JUG_F,
        "top": True, "racer": True, "top_col": (0.460, 0.490, 0.330),      # เสื้อกล้ามหลังไขว้สีเขียวเสจอ่อน
        "face": _face_f2(),
        "skin": (0.520, 0.345, 0.245), "lip_k": (0.86, 0.72, 0.80), "lip_mix": 0.60, "iris": (0.20, 0.12, 0.08),
        "sclera": (0.76, 0.72, 0.67), "brow": (0.07, 0.06, 0.055), "palm": (0.38, 0.34, 0.31),
        "beard": 0.0, "lash": 0.32, "brow_a": 0.38,
        "hair": {"col": (0.100, 0.075, 0.060), "cover": 0.97, "line": HL_CURL, "soft": 0.016, "thick": (20.0, 10.0, 12.0),
                 "rise": 0.040, "curl": 2.5, "curl_shade": 0.035, "hl_jit": 0.002, "bun": None},
        "brow_shape": {"dy": 0.0008, "w": 0.0046, "arch": 0.0010, "soft": 0.002},
        "face_smooth": 80.0, "lowlift": 0.08, "eyelift": 0.0,
        "detail_head_ymax": 1.84,
        "ranges": {"stature": (171, 176), "chest": (84, 96), "waist": (68, 80), "hips": (90, 102), "neck": (31.5, 36),
                   "thigh": (50, 60), "calf": (33, 39), "upper_arm": (25, 31.5), "forearm": (22, 27),
                   "wrist": (15, 17), "head_height": (21, 24.5), "head_breadth": (14, 15.8),
                   "foot_length": (24.0, 26.4), "shoulder_breadth": (41.5, 48)},
    },
}


def cfg():
    """ชุดค่าของร่างที่กำลังสร้าง: ร่างหลากหลาย หรือร่างหลักแบบ realistic (0.17) ; ร่างหลักแบบเดิม = ว่าง"""
    if CUR is not None:
        return CUR
    return BASE_REAL if REAL else {}


def use(name):
    """เลือกร่าง (None / "" = ทหารฐาน)"""
    global CUR, NAME
    if not name:
        CUR, NAME = None, ""
        return None
    if name not in VARIANTS:
        raise SystemExit("unknown variant %r (have: %s)" % (name, ", ".join(VARIANTS)))
    CUR, NAME = VARIANTS[name], name
    return CUR


def scale():
    """k = ส่วนสูงของร่าง / 1.78 (ย่อขยายทั้งตัวตอนส่งออก)"""
    return 1.0 if CUR is None else float(CUR["stature"]) / BASE_H


def head_scale():
    """ศีรษะไม่ย่อ/ขยายเต็มตามส่วนสูง: คูณเพิ่มในกรอบฐาน f = k^-0.6 (ขนาดศีรษะจริง ∝ k^0.4)"""
    return 1.0 if CUR is None else float(CUR.get("head_k") or scale() ** -0.6)


def shapes_on():
    """ร่างหลากหลายส่งออกโดยไม่มี blend shape (เกมใช้กระดูกช่วยอย่างเดียว ประหยัดขนาด)"""
    return CUR is None


def _ss(x):
    x = np.clip(x, 0, 1)
    return x * x * (3 - 2 * x)


# ---------------- ขยายศีรษะ (หลังปั้นผิว): รอบข้อศีรษะ ไล่น้ำหนักจากคอ ----------------
HW_Y = (1.500, 0.070)     # y กรอบศีรษะ (ท่า I): ต่ำกว่า y0 ไม่ขยาย ; สูงกว่า y0 + w ขยายเต็ม


def _hw_weight(V, G):
    import rig
    M = np.linalg.inv(rig.bone_xform(G, "head"))
    yl = V @ M[1, :3] + M[1, 3]
    return _ss((yl - HW_Y[0]) / HW_Y[1])


def head_warp(V, G):
    """จุดในท่า G -> ศีรษะขยาย f รอบข้อศีรษะ (ผิว ชั้นกระดูก ชั้นกล้าม ใช้ฟังก์ชันเดียวกัน)"""
    f = head_scale()
    if abs(f - 1.0) < 1e-12:
        return V
    j = G["head"][:3, 3]
    w = _hw_weight(V, G)
    return j + (V - j) * (1.0 + (f - 1.0) * w)[:, None]


def head_unwarp(V, G, it=10):
    """ย้อน head_warp (ทำซ้ำจุดคงที่) -> พิกัดก่อนขยาย (ใช้หาบริเวณหน้า/สีบนเมชที่ขยายแล้ว)"""
    f = head_scale()
    if abs(f - 1.0) < 1e-12:
        return V
    j = G["head"][:3, 3]
    X = np.array(V, float)
    for _ in range(it):
        X = j + (V - j) / (1.0 + (f - 1.0) * _hw_weight(X, G))[:, None]
    return X


def head_pts(P, G):
    """จุดอ้างอิงบนศีรษะ (โลก ท่า G) -> ตำแหน่งหลังขยายศีรษะ"""
    return head_warp(np.atleast_2d(np.asarray(P, float)), G)


# ---------------- แก้ชิ้นกายวิภาค (ก่อนสะท้อนซ้าย-ขวา) ----------------

def _mul_sec(sec, col, knots):
    S = np.array(sec, float)
    j = {"cx": 1, "cz": 2, "a": 3, "bf": 4, "bb": 5}[col]
    ys = [y for y, _ in knots]
    ms = [m for _, m in knots]
    S[:, j] = S[:, j] * np.interp(S[:, 0], ys, ms)
    return S


def _edit(p, e):
    from sdfk import Prim
    q = {kk: (np.array(vv, float) if isinstance(vv, np.ndarray) else vv) for kk, vv in p.p.items() if kk != "_tab"}
    if "dc" in e:
        q["c"] = np.asarray(q["c"], float) + np.asarray(e["dc"], float)
    if "sr" in e:
        q["r"] = np.asarray(q["r"], float) * np.asarray(e["sr"], float)
    if "da" in e:
        q["a"] = np.asarray(q["a"], float) + np.asarray(e["da"], float)
    if "db" in e:
        q["b"] = np.asarray(q["b"], float) + np.asarray(e["db"], float)
    if "srr" in e:
        q["ra"] = q["ra"] * e["srr"]
        q["rb"] = q.get("rb", q["ra"]) * e["srr"]
    if "srt" in e:
        q["r"] = np.asarray(q["r"], float) * e["srt"]
    if "spx" in e:
        q["pts"] = np.asarray(q["pts"], float) * np.array([e["spx"], 1.0, 1.0])
    if "dpts" in e:
        q["pts"] = np.asarray(q["pts"], float) + np.asarray(e["dpts"], float)
    if "sec" in e:
        S = q["sec"]
        for col, knots in e["sec"]:
            S = _mul_sec(S, col, knots)
        q["sec"] = S
    if "secy" in e:
        # เลื่อนหน้าตัดลอฟต์ตามแนวตั้ง (คางขึ้น/ลง) ; ลำดับ y ยังเรียงเหมือนเดิม
        S = np.array(q["sec"], float)
        S[:, 0] = S[:, 0] + np.interp(S[:, 0], [y for y, _ in e["secy"]], [d for _, d in e["secy"]])
        q["sec"] = S
    for kk, vv in e.get("set", {}).items():
        q[kk] = vv
    return Prim(p.kind, p.bone, outset=p.outset, tag=p.tag, name=p.name, neg=p.neg, k=p.k, weights=p.weights, **q)


def edit_prims(prims, which):
    """which = "face" | "cores" : แก้ชิ้นตามชื่อ (ข้างซ้าย/กลางตัว ; ข้างขวาสะท้อนทีหลังใน anatomy.both)"""
    E = cfg().get(which, {})
    return [_edit(p, E[p.name]) if p.name in E else p for p in prims]


def slope_pad():
    """ใหม่ 0.17: เนินบ่า (คอ -> ปลายบ่า) ของร่างที่มี slope_pad ; คืนทั้งซ้ายและขวา"""
    import anatomy as AN
    from sdfk import Prim
    sp = cfg().get("slope_pad")
    if not sp:
        return []
    a, b, ra, rb, k = sp
    return AN.both([Prim("capsule", "clavicleL", a=np.asarray(a, float), b=np.asarray(b, float), ra=ra, rb=rb,
                         name="shoulder_slope_L", tag="pad", outset=0.0, k=k, weights={"chest": 0.6, "clavicleL": 0.4})])


def extra_prims():
    """ชิ้นเพิ่มของร่าง: เต้านม + แผ่นลาดอกบน + สะพานกลางอก (เสื้อกีฬา) + ไขมันใต้ไหปลาร้า + เนื้อแก้มสูง + รอยพับหัวตา
    + มวยผม ; คืนทั้งซ้ายและขวา"""
    import anatomy as AN
    from sdfk import Prim, rotm
    out = []
    b = CUR.get("breasts")
    if b:
        rot = rotm([0, 1, 0], b["yaw"]) @ rotm([1, 0, 0], b["pitch"])
        out.append(Prim("ellipsoid", "spine", c=np.asarray(b["c"], float), r=np.asarray(b["r"], float), rot=rot,
                        name="breast_L", tag="pad", outset=0.0, k=b["k"], weights=AN.TRUNK_W))
        if b.get("bridge"):
            # เสื้อกีฬารัดอก: เติมร่องกลางอกให้เป็นแผ่นเรียบ (ไม่เห็นเป็นสองก้อนแยก)
            bc, br = b["bridge"]
            out.append(Prim("ellipsoid", "spine", c=np.asarray(bc, float), r=np.asarray(br, float), rot=np.eye(3),
                            name="breast_bridge", tag="pad", outset=0.0, k=b["k"], weights=AN.TRUNK_W))
        if b.get("upper"):
            # ลาดอกบน: ใต้ไหปลาร้าถึงยอดอกเป็นเส้นตรง (เสื้อรัด) ไม่เป็นลูกบอล
            uc, ur, uk = b["upper"]
            out.append(Prim("ellipsoid", "spine", c=np.asarray(uc, float), r=np.asarray(ur, float), rot=np.eye(3),
                            name="breast_upper_L", tag="pad", outset=0.0, k=uk, weights=AN.TRUNK_W))
        for i, (lc, lr, lk) in enumerate(b.get("lower", [])):
            # ใต้อก: ผ้าเสื้อรัดขึงจากยอดอกลงซี่โครงเป็นแนวลาด (ไม่เป็นร่องใต้อกลึก)
            out.append(Prim("ellipsoid", "spine", c=np.asarray(lc, float), r=np.asarray(lr, float), rot=np.eye(3),
                            name="breast_lower%d_L" % i, tag="pad", outset=0.0, k=lk, weights=AN.TRUNK_W))
    jp = CUR.get("jugular_pad")
    if jp:
        # คอบาง: ไขมันบาง ๆ ที่แอ่งเหนือกระดูกอก (ไม่ให้เป็นโพรงลึกระหว่างเอ็นคอสองข้าง)
        out.append(Prim("ellipsoid", "chest", c=np.asarray(jp[0], float), r=np.asarray(jp[1], float), rot=np.eye(3),
                        name="jugular_fat", tag="pad", outset=0.0, k=0.012, weights={"chest": 0.5, "neck": 0.5}))
    ic = CUR.get("infraclav")
    if ic:
        # ร่องใต้ไหปลาร้า/ร่องอก-ไหล่ (ใต้สายเสื้อ) ไม่เป็นจุดดำ
        out.append(Prim("ellipsoid", "chest", c=np.asarray(ic[0], float), r=np.asarray(ic[1], float), rot=np.eye(3),
                        name="infraclav_pad_L", tag="pad", outset=0.0, k=ic[2], weights={"chest": 0.8, "shoulderL": 0.2}))
    for key, nm in (("malar", "malar_L"), ("epicanthus", "epicanthus_L")):
        fp = CUR.get(key)
        if fp:
            out.append(Prim("ellipsoid", "head", c=np.asarray(fp[0], float), r=np.asarray(fp[1], float), rot=np.eye(3),
                            name=nm, tag="face", outset=0.0, k=fp[2]))
    hb = CUR["hair"].get("bun")
    if hb:
        out.append(Prim("ellipsoid", "head", c=np.asarray(hb["c"], float), r=np.asarray(hb["r"], float), rot=np.eye(3),
                        name="hair_bun", tag="face", outset=0.0, k=hb["k"]))
    return AN.both(out) + slope_pad()


def muscle_k(name):
    """ระดับกล้าม (คูณความหนาท้องกล้าม) ของมัดนี้"""
    m = cfg().get("muscle", {})
    return float(m.get(M2G.get(name, ""), m.get("all", 1.0)))


# ใหม่ 0.14 (natural): ร่างหลัก lo มีจุดยอดข้างกระดูกอกเหนือรอยต่อ chest/spine (จุดลงแผลอกของเกม: กระดูกตื้น เห็นในแผล)
BASE_LOD_SPOTS = shp(None, {"lo": [((sx * 0.025, 1.402, 0.110), (0.015, 0.012, 0.030), 0.9) for sx in (1.0, -1.0)]})


def lod_spots(V, lv, G):
    """ใหม่ 0.14: น้ำหนักเก็บสามเหลี่ยมเพิ่มตอนลดระดับ lv ตาม lod_spots ของร่าง [(จุดกลาง, รัศมี, น้ำหนัก)]
    และ lod_band (ระดับ -> น้ำหนักแถบรอบขอบเสื้อ: คอ/วงแขน/สาย) ; ไม่มี = 0"""
    w = np.zeros(len(V))
    for c, r, k in ((CUR.get("lod_spots") if CUR is not None else BASE_LOD_SPOTS) or {}).get(lv, ()):
        w = np.maximum(w, k * np.exp(-np.sum(((V - np.asarray(c)) / np.asarray(r)) ** 2, axis=1)))
    kb = (CUR.get("lod_band") or {}).get(lv, 0.0) if CUR is not None else 0.0
    if kb > 0 and CUR.get("top"):
        t = top_mask(V, G, hem=False)
        w = np.maximum(w, kb * 4 * t * (1 - t))
    return w


def detail_boxes(boxes):
    """กล่องละเอียดของศีรษะ: ลึกไปหลังขึ้น (มวยผม) / สูงขึ้น (ผมฟู)"""
    z = CUR.get("detail_head_zmin")
    y = CUR.get("detail_head_ymax")
    out = []
    for n, lo, hi in boxes:
        if n == "head":
            lo = (lo[0], lo[1], lo[2] if z is None else min(lo[2], z))
            hi = (hi[0], hi[1] if y is None else max(hi[1], y), hi[2])
        out.append((n, lo, hi))
    return out


# ---------------- ไขมัน: คูณ T/R ต่อท่อน + ก้อนแบบไขมัน (หญิง: สะโพก ก้น ต้นขา ; ทุกร่าง: แก้ม/กราม) ----------------

def _blob_mult(P, G, col):
    import fatmap as FM
    out = np.ones(len(P))
    for bone, c, r, mt, mr in CUR.get("blobs", []):
        m = mt if col == "T" else mr
        if m == 1.0:
            continue
        sides = (("L", 1.0), ("R", -1.0)) if (bone.endswith("L") or c[0] != 0.0) else (("", 1.0),)
        for sd, sx in sides:
            bn = bone[:-1] + sd if bone.endswith("L") else bone
            Pl = FM._local(P, G, bn)
            cc = np.array([sx * c[0], c[1], c[2]])
            g = np.exp(-np.sum(((Pl - cc) / np.asarray(r)) ** 2, axis=1))
            out = out * (1.0 + (m - 1.0) * g)
    return out


def fat_seg(name, T, R):
    base = name[:-1] if name[-1] in "LR" else name
    return T * CUR.get("fat_seg", {}).get(base, 1.0), R * CUR.get("fat_rseg", {}).get(base, 1.0)


def fat_blobs(P, G, T, R):
    if not CUR.get("blobs"):
        return T, R
    return T * _blob_mult(P, G, "T"), R * _blob_mult(P, G, "R")


def blob_R(P, G, R):
    if not CUR.get("blobs"):
        return R
    return R * _blob_mult(P, G, "R")


def groove_k(part):
    """ร่องหน้าท้อง: part = all (ทั้งหมด คูณใน groove_scale) | pe (ใต้ขอบอก) | sl (ขอบนอกกล้ามท้อง)"""
    return float(CUR.get("grooves", {}).get(part, 1.0))


# ---------------- ผิวปั้นหลังลดสามเหลี่ยม: แก้ม/กรามเรียบ + ผ้าคลุมร่องตื้น ----------------

def lowface_w(H):
    """แก้ม กราม ใต้คาง (กรอบศีรษะ ท่า I) 0..1 ; ไม่รวมปาก จมูก ตา หู"""
    Q = np.c_[np.abs(H[:, 0]), H[:, 1], H[:, 2]]

    def g(c, r):
        return np.exp(-np.sum(((Q - np.asarray(c)) / np.asarray(r)) ** 2, axis=1))
    low = np.maximum.reduce([g((0.050, 1.600, 0.045), (0.034, 0.047, 0.042)), g((0.0, 1.556, 0.040), (0.048, 0.022, 0.042)),
                             g((0.056, 1.566, 0.000), (0.026, 0.032, 0.032))])      # + มุมกราม
    ex = np.maximum.reduce([g((0, 1.587, 0.100), (0.030, 0.016, 0.025)), g((0, 1.630, 0.105), (0.022, 0.032, 0.025)),
                            g((0.032, 1.663, 0.085), (0.022, 0.016, 0.022)), g((0.075, 1.643, -0.008), (0.018, 0.036, 0.026))])
    return np.clip(1.6 * low, 0, 1) * (1 - np.clip(1.5 * ex, 0, 1))


def shade_w(H):
    """บริเวณเกลี่ยแสงเงา (นอร์มอล/สีที่ส่งออก): แก้ม กราม ใต้คาง + โหนกแก้มถึงหน้าหู (ไม่รวมตา หู) ; ผิวปั้นใช้ lowface_w"""
    Q = np.c_[np.abs(H[:, 0]), H[:, 1], H[:, 2]]
    z = np.exp(-np.sum(((Q - np.array([0.058, 1.638, 0.030])) / np.array([0.022, 0.024, 0.036])) ** 2, axis=1))
    ex = np.maximum(np.exp(-np.sum(((Q - np.array([0.032, 1.663, 0.085])) / np.array([0.020, 0.014, 0.020])) ** 2, axis=1)),
                    np.exp(-np.sum(((Q - np.array([0.075, 1.643, -0.008])) / np.array([0.016, 0.034, 0.024])) ** 2, axis=1)))
    return np.maximum(lowface_w(H), np.clip(1.5 * z, 0, 1) * (1 - np.clip(1.5 * ex, 0, 1)))


def eye_box(H):
    """บริเวณตาสองข้าง (กรอบศีรษะ ท่า I) 0..1"""
    Q = np.c_[np.abs(H[:, 0]), H[:, 1], H[:, 2]]
    return np.exp(-np.sum(((Q - np.array([0.033, 1.664, 0.085])) / np.array([0.024, 0.016, 0.024])) ** 2, axis=1))


def smooth_lowface(V, F, pair, G, t=None):
    """เกลี่ยแบบ implicit (แก้ระบบเชิงเส้นครั้งเดียว) เฉพาะแก้ม/กราม/ใต้คาง: เนินขนาด 2-3 ซม. เรียบเป็นผิวเดียว
    (ไม่เป็นคลื่นที่ไฟบนทำให้เป็นคราบ) ; นอกหน้ากากคงที่ ; t = ระยะเวลาการแพร่ (ใหญ่ = เรียบกว้าง)"""
    import mesh as ME
    from scipy.sparse import diags
    from scipy.sparse.linalg import spsolve
    t = float(cfg().get("face_smooth", 15.0)) if t is None else float(t)
    if t <= 0:
        return V
    w = lowface_w(ME.head_local(V, G))
    M = np.nonzero(w > 0.01)[0]
    if len(M) == 0:
        return V
    A = ME.adjacency(F, len(V)).tocsr()
    X0 = np.array(V, float)
    B = np.ones(len(V), bool)
    B[M] = False
    tw = t * w[M]
    AMM = A[M][:, M]
    rhs = X0[M] + tw[:, None] * (A[M][:, B] @ X0[B])
    K = diags(1.0 + tw) - diags(tw) @ AMM
    X = X0.copy()
    X[M] = np.column_stack([spsolve(K.tocsc(), rhs[:, c]) for c in range(3)])
    return X if pair is None else ME.symmetrize(X, pair)


def cloth_bridge(V, F, pair, G, it=70, cap=0.003):
    """เสื้อรัดคลุมร่องตื้นแบบผ้า: ยกจุดที่บุ๋ม (ตามนอร์มอล) รวมไม่เกิน cap ; เฉพาะในเสื้อ (หญิง) เหนือขอบกางเกง"""
    if not CUR.get("top"):
        return V
    import mesh as ME
    m = _ss((top_sd(V, G) + 0.004) / 0.012) * _ss((V[:, 1] - ME.SHORTS_TOP - 0.02) / 0.03)
    if not np.any(m > 0):
        return V
    A = ME.adjacency(F, len(V))
    X = np.array(V, float)
    lift = np.zeros(len(V))
    for _ in range(it):
        N = ME.vnormals(X, F)
        d = np.einsum('ij,ij->i', A @ X - X, N)          # บวก = บุ๋ม (จุดรอบข้างอยู่นอกกว่า)
        step = np.minimum(np.clip(0.6 * d, 0, None) * m, cap - lift)
        X = X + N * step[:, None]
        lift = lift + step
    return ME.symmetrize(X, pair)


# ---------------- ผม: ความหนา (สนามระยะ) + สี ----------------

def _hairline(th):
    """แนวไรผมเรียบ (เฉลี่ย ±12°) + ไรผมไม่สม่ำเสมอเล็กน้อยแบบกำหนดแน่นอน (hl_jit)"""
    hc = CUR["hair"]
    th = np.asarray(th, float)
    y = sum(np.interp(np.clip(th + d, 0, 180), TH, hc["line"]) for d in (-12.0, -6.0, 0.0, 6.0, 12.0)) / 5.0
    j = hc.get("hl_jit", 0.0)
    if j > 0:
        r = np.radians(th)
        y = y + j * (0.6 * np.sin(7.3 * r + 0.6) + 0.4 * np.sin(13.1 * r + 2.1))
    return y


def hair_mask(H, ear=None, soft=None):
    """น้ำหนักผม 0..1 จากจุดในกรอบศีรษะ (ท่า I): เหนือไรผม ; ไม่คลุมหู ; soft = ระยะไล่ขอบ (ม.)"""
    hc = CUR["hair"]
    x, y, z = np.abs(H[:, 0]), H[:, 1], H[:, 2]
    th = np.degrees(np.arctan2(x, z))
    u = np.clip((y - _hairline(th)) / (hc["soft"] if soft is None else soft), 0, 1)
    m = u * u * (3 - 2 * u)
    if ear is not None:
        m = m * (1 - np.clip(ear, 0, 1))
    return m


# ลอนผมหยิก: คลื่นระนาบ 11 ทิศ (ทิศ/ความยาวคลื่นจากลำดับทองคำ กำหนดแน่นอน ไม่สุ่ม) + ก้อนใหญ่ 3 ทิศ
#   ความยาวคลื่น 20-30 มม. (ใหญ่กว่าสามเหลี่ยม hi ~8-10 มม. จึงเห็นเป็นลอน)
_GA = np.pi * (3 - np.sqrt(5))
_CD = np.array([[np.cos(_GA * i) * np.sqrt(1 - (1 - 2 * (i + 0.5) / 11) ** 2), 1 - 2 * (i + 0.5) / 11,
                 np.sin(_GA * i) * np.sqrt(1 - (1 - 2 * (i + 0.5) / 11) ** 2)] for i in range(11)])
_CL = 0.020 + 0.010 * ((np.arange(11) * 0.618034) % 1.0)
_CP = 2 * np.pi * ((np.arange(11) * 0.381966 + 0.13) % 1.0)
_LD = np.array([[0.48, 0.71, 0.51], [-0.62, 0.38, 0.69], [0.21, -0.55, 0.81]])
_LL = np.array([0.046, 0.054, 0.041])


def _curl(H):
    """ลอนผมหยิก ~ -1..1 (|x| ให้สมมาตรซ้าย-ขวา)"""
    Q = np.c_[np.abs(H[:, 0]), H[:, 1], H[:, 2]]
    s = np.zeros(len(H))
    for d, l, p in zip(_CD, _CL, _CP):
        s += np.sin(2 * np.pi * (Q @ d) / l + p)
    s = s / np.sqrt(11 / 2.0)
    big = np.zeros(len(H))
    for d, l in zip(_LD / np.linalg.norm(_LD, axis=1, keepdims=True), _LL):
        big += np.sin(2 * np.pi * (Q @ d) / l)
    return np.clip(0.75 * s + 0.35 * big / np.sqrt(1.5), -1.6, 1.6) / 1.6


def hair_thick(H, ear):
    """ความหนาผม (ม.) ในกรอบศีรษะ: บน/ข้าง/หลัง (มม.) ผสมตามทิศ ; ลอนหยิก ± curl มม. ; บางลงถึง 0 ที่ไรผมทีละน้อย (rise)"""
    hc = CUR["hair"]
    tt, ts, tb = hc["thick"]
    x, y, z = np.abs(H[:, 0]), H[:, 1], H[:, 2]
    up = np.clip((y - 1.66) / 0.10, 0, 1)
    side = np.clip(x / 0.07, 0, 1) * (1 - up)
    back = np.clip(-z / 0.08, 0, 1) * (1 - up)
    t = tt * up + ts * side + tb * back + 0.5 * (tt + ts) * np.clip(1 - up - side - back, 0, 1)
    if hc.get("curl", 0.0) > 0:
        t = t + hc["curl"] * _curl(H)
    return np.maximum(t, 0.0) * 0.001 * hair_mask(H, ear, soft=hc.get("rise", 0.022))


def _ear_w(H, prims_head):
    e = np.zeros(len(H))
    for p in prims_head:
        d, _ = p.eval_local(H.astype(np.float32))
        e = np.maximum(e, 1 - np.clip((np.asarray(d, float) - 0.003) / 0.008, 0, 1))
    return e


def add_hair(g, G):
    """ยกผิวศีรษะตามความหนาผม (สนามระยะ: ลบ = ในตัว) เฉพาะกล่องศีรษะ"""
    import rig
    import anatomy as AN
    hc = CUR.get("hair")
    if not hc or max(hc["thick"]) <= 0:
        return
    M = rig.bone_xform(G, "head")
    lo, hi = np.array([-0.11, 1.55, -0.135]), np.array([0.11, 1.84, 0.12])
    cs = np.array([[x, y, z] for x in (lo[0], hi[0]) for y in (lo[1], hi[1]) for z in (lo[2], hi[2])])
    w = cs @ M[:3, :3].T + M[:3, 3]
    sl = g.slices(w.min(0), w.max(0))
    if sl is None:
        return
    P = g.points(sl).astype(np.float64)
    Mi = np.linalg.inv(M)
    H = P @ Mi[:3, :3].T + Mi[:3, 3]
    ears = [p for p in AN.face() if p.name in ("ear_L", "ear_R")]
    t = hair_thick(H, _ear_w(H, ears))
    shp = tuple(s.stop - s.start for s in sl)
    g.F[sl] = (g.F[sl] - t.reshape(shp)).astype(g.F.dtype)


# ---------------- สี ----------------

def palette():
    """สีของร่าง (sRGB) ; ริมฝีปาก/เล็บ/รูจมูก/ตาระยะไกล คิดจากสีผิว"""
    c = CUR
    sk = np.array(c["skin"], float)
    lip = sk * np.array(c["lip_k"])
    iris = np.array(c["iris"], float)
    scl = np.array(c["sclera"], float)
    return {"SKIN": sk, "HAIR": np.array(c["hair"]["col"], float), "BROW": np.array(c["brow"], float),
            "LIP": lip, "MOUTH": sk * np.array([0.50, 0.39, 0.45]), "LASH": np.array(c["brow"], float) * 0.9 + 0.02,
            "SCLERA": scl, "IRIS": iris, "PUPIL": np.array([0.05, 0.04, 0.04]),
            "EYE_FAR": 0.35 * iris + 0.65 * scl * 0.80, "NAIL": 0.5 * sk + 0.5 * np.array([0.86, 0.72, 0.68]),
            "NOSTRIL": sk * np.array([0.43, 0.34, 0.40]), "PALM": np.array(c["palm"], float),
            "SOLE": np.array(c["palm"], float) * 0.85, "BEARD": float(c["beard"]),
            "AO_HEAD": float(c.get("ao_head", 0.90)), "LIP_MIX": float(c.get("lip_mix", 0.60)),
            "BROW_A": float(c.get("brow_a", 0.46)), "LOWLIFT": float(c.get("lowlift", 0.08)),
            "EYELIFT": float(c.get("eyelift", 0.0))}


def brow_mask(ax, y, z):
    """คิ้วของร่าง (สีวาด): dy = ยก, w = ครึ่งความหนา, arch = โค้ง, taper = เรียวหางคิ้ว, soft = ขอบไล่ ; None = คิ้วฐาน"""
    bs = CUR.get("brow_shape")
    if bs is None:
        return None
    yc = 1.6855 + bs["dy"] + bs.get("slope", 0.02) * (ax - 0.031) + bs["arch"] * np.clip(1 - ((ax - 0.040) / 0.017) ** 2, 0, 1)
    w = bs["w"] * (1 - bs.get("taper", 0.45) * np.clip((ax - 0.031) / 0.021, 0, 1))
    soft = bs.get("soft", 0.002)
    vprof = 1 - _ss((np.abs(y - yc) - (w - soft)) / soft)
    hprof = 1 - _ss((np.abs(ax - 0.0315) - 0.0155) / 0.005)
    return vprof * hprof * _ss((z - 0.072) / 0.008)


def shorts_hem(V):
    """ขากางเกง (สูตรเดียวกับ mesh.colours) 0..1"""
    import mesh as ME
    return _ss((V[:, 1] - ME.SHORTS_HEM + 0.011) / 0.022) * (np.abs(V[:, 0]) < 0.30)


def edge_band(V, G):
    """แถบรอบขอบผ้า (คอเสื้อ วงแขน ขากางเกง) 0..1 : ให้ระดับ hi/mid/lo เก็บจุดยอดถี่ขึ้นตรงขอบ"""
    h = shorts_hem(V)
    band = 4 * h * (1 - h)
    if CUR.get("top"):
        t = top_mask(V, G, hem=False)
        band = np.maximum(band, 4 * t * (1 - t))
    return np.clip(band, 0, 1)


# ---------------- ขอบผ้า: ระยะมีเครื่องหมาย (บวก = ในผ้า ; ม.) -> ตัดเมชตามเส้น 0 + ทาสีที่จุดยอดของแต่ละระดับ ----------------

def _neck_arm_sd(x, y, z):
    """คอเสื้อ (หน้า U มน / หลัง) และวงแขน (หน้า / หลังไขว้) เป็นระยะโดยประมาณ (หารด้วยความชันของเส้น -> ขอบไล่กว้างเท่ากันทุกที่)"""
    front = _ss((z + 0.01) / 0.05)
    r = np.clip(1 - (x / 0.070) ** 2, 0, 1)
    yf = 1.398 + 0.130 * (1 - np.sqrt(r))
    dyf = np.where(r > 0, 0.130 * (x / 0.0049) / np.sqrt(np.maximum(r, 1e-4)), 0.0)
    ub = np.clip((x - 0.030) / 0.040, 0, 1)
    yb = 1.425 + 0.105 * _ss(ub)
    dyb = 0.105 * 6 * ub * (1 - ub) / 0.040
    yneck = front * yf + (1 - front) * yb
    dyn = np.minimum(front * dyf + (1 - front) * dyb, 60.0)
    s_neck = (yneck - 0.008 - y) / np.sqrt(1 + dyn ** 2)
    ua = np.clip((y - 1.335) / 0.135, 0, 1)
    xof = 0.112 + 0.080 * (1 - _ss(ua))
    dxf = -0.080 * 6 * ua * (1 - ua) / 0.135
    if CUR.get("racer"):
        # หลังไขว้: สายจากบ่าเฉียงเข้าหากระดูกสันหลัง แคบสุด ~10 ซม. ที่ระดับกลางสะบัก แล้วบานออกถึงรักแร้
        u1 = np.clip((y - 1.40) / 0.08, 0, 1)
        u2 = np.clip((1.40 - y) / 0.10, 0, 1)
        xob = 0.050 + 0.062 * _ss(u1) + 0.130 * _ss(u2)
        dxb = 0.062 * 6 * u1 * (1 - u1) / 0.08 - 0.130 * 6 * u2 * (1 - u2) / 0.10
    else:
        xob, dxb = xof, dxf
    xo = front * xof + (1 - front) * xob
    dxo = front * dxf + (1 - front) * dxb
    s_arm = (xo - 0.008 - x) / np.sqrt(1 + dxo ** 2)
    return s_neck, s_arm


def top_sd(V, G, hem=True, cut=False):
    """เสื้อกล้าม: ระยะมีเครื่องหมายถึงขอบ (กรอบอก ท่า I) ; hem = รวมชายเสื้อ (ใต้ขอบเอวกางเกง)
    cut = ฟิลด์สำหรับตัดเมช (คอ + วงแขนเท่านั้น ; ใต้ขอบกางเกงไม่ตัด)"""
    import fatmap as FM
    import mesh as ME
    P = FM._local(V, G, "chest")
    sn, sa = _neck_arm_sd(np.abs(P[:, 0]), P[:, 1], P[:, 2])
    s = np.minimum(sn, sa)
    if cut:
        s = np.where(V[:, 1] < ME.SHORTS_TOP - 0.020, 0.05, s)
    elif hem:
        s = np.minimum(s, V[:, 1] - (ME.SHORTS_TOP - 0.015))
    return np.where(np.abs(V[:, 0]) < 0.30, s, -1.0)


def shorts_sd(V):
    """กางเกงขาสั้น: ระยะถึงขอบเอว/ขากางเกง (เส้นเดียวกับ mesh.colours ที่ค่า 0.5)"""
    import mesh as ME
    s = np.minimum(ME.SHORTS_TOP - V[:, 1], V[:, 1] - ME.SHORTS_HEM)
    return np.where(np.abs(V[:, 0]) < 0.30, s, -1.0)


def top_mask(V, G, hem=True):
    """เสื้อกล้ามกีฬา 0..1 (ขอบไล่ 16 มม. ตั้งฉากกับขอบทุกที่) ; ใช้กับเมชปั้น/ภาพตัวอย่างและแถบจุดยอดตามขอบ"""
    return _ss(0.5 + top_sd(V, G, hem=hem) / 0.016)


GARM_D = {"hi": 0.0025, "mid": 0.0030, "lo": 0.0050, "min": 0.0070}   # ครึ่งแถบไล่สีขอบผ้า (ม.) ต่อระดับ


def garment_masks(V, G, d=0.008):
    """(เสื้อ หรือ None, กางเกง) 0..1 ที่จุดยอด: ไล่เชิงเส้นในแถบ ±d รอบขอบ"""
    mt = np.clip(0.5 + top_sd(V, G) / (2 * d), 0, 1) if CUR.get("top") else None
    return mt, np.clip(0.5 + shorts_sd(V) / (2 * d), 0, 1)


def paint_garments(V, G, rgb, flesh, aof, d=0.008):
    """ทาเสื้อ/กางเกงที่จุดยอดของระดับ (สีผ้า × AO ที่ถ่ายจากผิวปั้น) ; กางเกงทับชายเสื้อ ; ขอบเอวเข้มขึ้นแบบไล่นุ่ม"""
    import mesh as ME
    mt, ms = garment_masks(V, G, d)
    if mt is not None:
        col = np.asarray(CUR.get("top_col", OLIVE_TOP), float)
        rgb = rgb * (1 - mt[:, None]) + col[None, :] * aof[:, None] * mt[:, None]
        flesh = flesh * (1 - 0.85 * mt)
    band = _ss((V[:, 1] - (ME.SHORTS_TOP - ME.SHORTS_BAND)) / 0.012)
    col = ME.OLIVE[None, :] * (1 - 0.14 * band[:, None])
    rgb = rgb * (1 - ms[:, None]) + col * aof[:, None] * ms[:, None]
    flesh = flesh * (1 - 0.85 * ms)
    return rgb, flesh


CUT_RESERVE = {"hi": 880, "mid": 640, "lo": 560, "min": 370}   # ลดเป้าก่อนตัดตามขอบผ้า (ผลรวมหลังตัด ~ งบเดิม)
CUT_SLACK = {"hi": 300, "mid": 200, "lo": 100, "min": 60}      # หลังตัดเกินงบเดิมได้ไม่เกินนี้ (ยังต่ำกว่างบเกม)


def _fnorm(X, F):
    return np.cross(X[F[:, 1]] - X[F[:, 0]], X[F[:, 2]] - X[F[:, 0]])


def _safe_move(V, F, tgt, mv, fracs=(1.0,)):
    """เลื่อนจุด mv ไป tgt โดยไม่ให้สามเหลี่ยมพลิก/แบน ; จุดที่ทำให้พลิกลองเลื่อนบางส่วน (fracs) ไม่ได้ก็ไม่เลื่อน"""
    N0 = _fnorm(V, F)
    n0 = np.linalg.norm(N0, axis=1)
    X = np.array(V, float)
    todo = mv.copy()
    done = np.zeros(len(V), bool)
    for fr in fracs:
        cur = todo.copy()
        for _ in range(6):
            Vn = X.copy()
            Vn[cur] = V[cur] + fr * (tgt[cur] - V[cur])
            N1 = _fnorm(Vn, F)
            bad = np.einsum('ij,ij->i', N0, N1) < 0.15 * n0 * np.linalg.norm(N1, axis=1)
            if not bad.any():
                break
            cur[np.unique(F[bad])] = False
        X[cur] = V[cur] + fr * (tgt[cur] - V[cur])
        done |= cur
        todo &= ~cur
        if not todo.any():
            break
    return X, done


def cut_along(V, F, s, snap=0.35):
    """ตัดสามเหลี่ยมตามเส้น s = 0 (s ต่อจุดยอด เชิงเส้นตามขอบ): จุดยอดที่ใกล้เส้น (< snap ของขอบ) เลื่อนลงเส้น ;
    สามเหลี่ยมที่ยังข้ามเส้นแบ่ง (จุดใหม่บนขอบใช้ร่วมกันสองฝั่ง -> ผิวปิดเหมือนเดิม) ; สมมาตรซ้าย-ขวาคงอยู่
    คืน (V, F, on) ; on = จุดยอดที่อยู่บนเส้น"""
    V = np.array(V, float)
    s = np.array(s, float)
    F = np.asarray(F, np.int64)
    n = len(V)
    E = np.unique(np.sort(np.vstack([F[:, [0, 1]], F[:, [1, 2]], F[:, [2, 0]]]), axis=1), axis=0)
    a, b = E[:, 0], E[:, 1]
    seam = np.abs(V[:, 0]) < 1e-9
    # 1) เลื่อนจุดยอดที่ใกล้เส้นลงบนเส้น (สามเหลี่ยมเพิ่มน้อย ไม่ผอม)
    cr = s[a] * s[b] < 0
    t = np.where(cr, s[a] / np.where(cr, s[a] - s[b], 1.0), 0.5)
    best = np.full(n, np.inf)
    for v, tt in ((a, t), (b, 1 - t)):
        m = cr & (tt < snap)
        np.minimum.at(best, v[m], tt[m])
    tgt = np.zeros((n, 3))
    for v, u, tt in ((a, b, t), (b, a, 1 - t)):
        m = cr & (tt < snap)
        m[m] = tt[m] == best[v[m]]
        tgt[v[m]] = V[v[m]] + tt[m][:, None] * (V[u[m]] - V[v[m]])
    V, mv = _safe_move(V, F, tgt, np.isfinite(best) & ~seam)
    s[mv] = 0.0
    on = s == 0.0
    # 2) แบ่งสามเหลี่ยมที่ข้ามเส้น
    cr = s[a] * s[b] < 0
    ce = np.nonzero(cr)[0]
    if len(ce) == 0:
        return V, F, on
    tc = s[a[ce]] / (s[a[ce]] - s[b[ce]])
    newV = V[a[ce]] + tc[:, None] * (V[b[ce]] - V[a[ce]])
    key = {int(a[e]) * n + int(b[e]): n + i for i, e in enumerate(ce)}

    def mid(i, j):
        return key[min(i, j) * n + max(i, j)]
    sg = np.sign(s)
    fk = np.sort(np.stack([F[:, [0, 1]], F[:, [1, 2]], F[:, [2, 0]]], 1), axis=2)
    hit = np.isin(fk[:, :, 0] * n + fk[:, :, 1], np.array(sorted(key.keys()), np.int64)).any(1)
    keep = F[~hit]
    add = []
    for f in F[hit]:
        z = [k for k in range(3) if sg[f[k]] == 0]
        if len(z) == 1:
            k = z[0]
            Z, P, Q = f[k], f[(k + 1) % 3], f[(k + 2) % 3]
            m = mid(P, Q)
            add += [(Z, P, m), (Z, m, Q)]
            continue
        k = [k for k in range(3) if sg[f[k]] != sg[f[(k + 1) % 3]] and sg[f[k]] != sg[f[(k + 2) % 3]]][0]
        L, P, Q = f[k], f[(k + 1) % 3], f[(k + 2) % 3]
        m1, m2 = mid(L, P), mid(L, Q)
        add.append((L, m1, m2))
        if np.linalg.norm(newV[m1 - n] - V[Q]) <= np.linalg.norm(V[P] - newV[m2 - n]):
            add += [(m1, P, Q), (m1, Q, m2)]
        else:
            add += [(m1, P, m2), (P, Q, m2)]
    return np.vstack([V, newV]), np.vstack([keep, np.array(add, np.int64)]), np.r_[on, np.ones(len(newV), bool)]


def band_rows(V, F, sfun, on, d, it=3):
    """แถวจุดยอดที่ติดเส้นขอบ (สองฝั่ง) เลื่อนตามผิวมาอยู่ที่ระยะ ±d -> แถบไล่สีกว้างเท่ากันตลอดขอบ (ไม่เพิ่มสามเหลี่ยม)"""
    import mesh as ME
    n = len(V)
    E = np.vstack([F[:, [0, 1]], F[:, [1, 2]], F[:, [2, 0]]])
    nb = np.zeros(n, bool)
    nb[E[on[E[:, 0]], 1]] = True
    nb[E[on[E[:, 1]], 0]] = True
    cand = nb & ~on
    s0 = sfun(V)
    cand &= np.abs(s0) > d
    if not cand.any():
        return V
    idx = np.nonzero(cand)[0]
    sig = np.sign(s0[idx])
    Nv = ME.vnormals(V, F)[idx]
    P = V[idx].copy()
    h = 0.0007
    for _ in range(it):
        g = np.stack([(sfun(P + h * e) - sfun(P - h * e)) / (2 * h) for e in np.eye(3)], 1)
        g = g - np.einsum('ij,ij->i', g, Nv)[:, None] * Nv         # ตามระนาบสัมผัสผิว
        gg = np.maximum(np.einsum('ij,ij->i', g, g), 1e-6)
        P = P - ((sfun(P) - sig * d) / gg)[:, None] * g
    seam = np.abs(V[idx, 0]) < 1e-9
    P[seam, 0] = 0.0
    tgt = V.copy()
    tgt[idx] = P
    mv = np.zeros(n, bool)
    mv[idx] = np.abs(sfun(P) - sig * d) < 0.5 * d                  # เลื่อนเฉพาะจุดที่หาตำแหน่งได้จริง
    V2, _ = _safe_move(V, F, tgt, mv, fracs=(1.0, 0.6, 0.35))
    return V2


def to_surface(V, idx, Vs, Ns):
    """จุด idx ฉายลงผิวปั้น (ระนาบสัมผัสของจุดผิวปั้นที่ใกล้สุด)"""
    from scipy.spatial import cKDTree
    if len(idx) == 0:
        return V
    _, j = cKDTree(Vs).query(V[idx])
    V = V.copy()
    V[idx] = V[idx] - np.einsum('ij,ij->i', V[idx] - Vs[j], Ns[j])[:, None] * Ns[j]
    return V


HAIR_D = {"hi": 0.0025, "mid": 0.0030, "lo": 0.0045, "min": 0.0060}   # ไรผม: ตัดเมชตามไรผม + แถบไล่สี ±d (ไม่เป็นหนาม)


def hair_sd(V, G):
    """ระยะ (โดยประมาณ) เหนือไรผม (บวก = ในผม) ในกรอบศีรษะก่อนขยาย ; นอกศีรษะ = ไม่มีผม"""
    import mesh as ME
    H = ME.head_local(head_unwarp(V, G), G)
    th = np.degrees(np.arctan2(np.abs(H[:, 0]), H[:, 2]))
    s = H[:, 1] - (_hairline(th) + 0.5 * CUR["hair"]["soft"])       # เส้นเดียวกับค่า 0.5 ของสีผมบนผิวปั้น (hi/mid)
    head = (np.linalg.norm(H - np.array([0, 1.69, 0.0]), axis=1) < 0.17) & (H[:, 1] > 1.55)
    return np.where(head, s, -0.05)


def paint_hair(V, G, rgb, flesh, aof, prims, d):
    """ทาผมที่จุดยอดของระดับ lo/min (ขอบอยู่บนแถวจุดยอดที่ตัดไว้) ; ไม่ทาหู ; มวยผมทั้งก้อน ; ลอนหยิกเป็นแสงเงา"""
    import mesh as ME
    import rig
    hc = CUR["hair"]
    H = ME.head_local(head_unwarp(V, G), G)
    m = np.clip(0.5 + hair_sd(V, G) / (2 * d), 0, 1)
    pm = {p.name: p for p in prims}
    V32 = head_unwarp(V, G).astype(np.float32)

    def dist(nm):
        dd, _ = pm[nm].eval(V32, rig.bone_xform(G, pm[nm].bone))
        return np.asarray(dd, float)
    ear = np.maximum(1 - _ss((dist("ear_L") - 0.002) / 0.006), 1 - _ss((dist("ear_R") - 0.002) / 0.006))
    m = m * (1 - np.clip(_ss(ear * 1.5), 0, 1))
    if "hair_bun" in pm:
        m = np.maximum(m, 1 - _ss((dist("hair_bun") - 0.002) / 0.006))
    hcol = np.tile(np.array(hc["col"], float), (len(V), 1))
    if hc.get("curl", 0.0) > 0:
        hcol = hcol + hc.get("curl_shade", 0.035) * np.clip(_curl(H), -1, 1)[:, None]
    a = hc["cover"] * m
    rgb = rgb * (1 - a[:, None]) + hcol * aof[:, None] * a[:, None]
    return rgb, flesh * (1 - 0.80 * m)


def cut_garments(V, F, G, d=0.003, Vs=None, Ns=None, hair_d=0.0, keep_mid=False):
    """ตัดเมชระดับตามขอบผ้า (ขอบเอว/ขากางเกง ; คอเสื้อ/วงแขน) + แถวจุดยอดข้างเส้นที่ ±d -> ขอบสีคมเรียบตามขอบจริง
    hair_d > 0: ตัดตามไรผมด้วย (lo/min) ; keep_mid: จุดบนแนวกลางตัวคงอยู่ที่ x = 0 หลังฉายลงผิว (ใหม่ 0.16, min)"""
    n0 = len(V)
    fields = [(shorts_sd, d)] + ([(lambda X: top_sd(X, G, cut=True), d)] if CUR.get("top") else [])
    if hair_d > 0:
        fields.append((lambda X: hair_sd(X, G), hair_d))
    V0 = np.array(V, float)
    for sf, dd in fields:
        V, F, on = cut_along(V, F, sf(V))
        V = band_rows(V, F, sf, on, dd)
    if Vs is not None:
        mid = np.abs(V[:, 0]) < 1e-9
        moved = np.nonzero(np.r_[np.linalg.norm(V[:n0] - V0, axis=1) > 1e-9, np.ones(len(V) - n0, bool)])[0]
        V = to_surface(V, moved, Vs, Ns)
        if keep_mid:
            # นอร์มอลผิวปั้นเอียงข้าง -> จุดกลางตัวหลุดจาก x = 0 ไม่มีคู่สะท้อน (f1 min 0.8 มม.) : วางกลับบนแนวกลาง
            V[mid & (np.abs(V[:, 0]) >= 1e-9), 0] = 0.0
    return V, F

