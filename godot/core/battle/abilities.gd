class_name BtAbilities
extends RefCounted
## ทะเบียนความสามารถ (R1_PORT_SPEC §1 abilities): ธงของหน่วย คำของอาวุธ ชนิดออร่า และกฎทั้งกองทัพ
## แต่ละชื่อชี้ไปยังฟังก์ชันกติกาที่ใช้มัน ("Class.func" คั่นด้วย ", " เมื่อมีหลายที่) หรือ "none" = ไม่มีผลต่อกติกา
## ตัวอ่าน (ty, flag, num, text, gun, mel, wnum, wflag) อ่าน GameData อย่างเดียว ไม่แก้อะไร ความจริงเท็จแบบหน้าเก่า
## test_abilities.gd ตรวจว่าทุกช่องใน types.json อยู่ในทะเบียน และตัวจัดการที่มีแล้วทุกตัวมีการทดสอบพฤติกรรม

## ช่องค่าพื้นฐานของหน่วย (ไม่ใช่ธง)
const STATS := ["k", "fac", "nm", "d", "n", "pts", "mv", "T", "sv", "w", "ld", "oc", "gun", "mel"]
## ช่องค่าพื้นฐานของอาวุธ
const WEAPON_STATS := ["nm", "a", "s", "ap", "d", "rng", "bs", "ws"]

## ธงของหน่วย -> ตัวจัดการ
const FLAGS := {
	"ac": "BtCombat.charge_why_not",
	"aoc": "BtCombat.atk_math",
	"aura": "BtCombat.in_aura",
	"brave": "BtTurn.start_turn",
	"ca": "BtCombat.atk_math",
	"ch": "none",
	"fly": "BtCombat.shot_why_not, BtCombat.charge_why_not",
	"gk": "BtPend.finish_atk, BtAbilities.glory_heal",
	"hd": "BtPend.deal_damage",
	"heal": "BtCombat.can_heal, BtCombat.heal_why_not",
	"heel": "BtCombat.atk_math, BtPend.apply_wnd",
	"hero": "none",
	"inf": "BtCombat.inf",
	"inv": "BtCombat.atk_math",
	"lk": "BtArmy.fit_list, BtArmy.pts_of, BtArmy.slot_max",
	"r": "BtSquads.radius_of",
	"rez": "BtTurn.start_turn, BtPend.apply_rez",
	"sec": "BtArmy.fit_list, BtArmy.fac_of, BtArmy.pts_of, BtArmy.slot_max",
	"spawn": "BtTurn.start_turn, BtAbilities.after_kills, BtAbilities.spawn_from",
	"st": "BtCombat.atk_math",
	"ttn": "BtCombat.shot_why_not, BtCombat.charge_why_not",
	"veh": "none",
	"vsh": "BtArmy.deploy, BtAbilities.refill_shields",
	"wind": "BtPend.deal_damage, BtAbilities.wind_turn",
}
# ac บุกได้แม้วิ่งมา · aoc ค่าเจาะที่โดนลดหนึ่ง · brave ผ่านทดสอบขวัญเสมอ · ca บุกเข้ามาตีเพิ่มตัวละหนึ่ง
# ch หัวข้อภาคี (จอ) · fly/ttn ถอยแล้วยังยิงและบุกได้ ttn ติดประชิดก็ยิงได้ · gk ฆ่าแล้วฟื้นแผล · hd ดาเมจที่โดนลดครึ่ง
# heal ระยะรักษา · heel เจาะได้หกตายทันที · hero ตัวเอก (จอ) · inf ทหารเดินเท้า (ช่องที่ส่งออกมา) · inv เซฟพิเศษ
# lk/sec หน่วยลับ · r รัศมีฐาน (GameData เก็บเป็น r_mi) · rez ซ่อมตัวเอง · spawn หน่วยที่ซ่อนอยู่ข้างใน
# st พรางตัว โดนยิงเข้ายากขึ้นหนึ่ง · veh ผลมีแค่ผ่าน inf · vsh ชั้นโล่ · wind ลมพัดมาชุบชีวิต

## คำของอาวุธ -> ตัวจัดการ
const WEAPON_KEYS := {
	"rf": "BtCombat.atk_math",
	"as": "BtCombat.shot_why_not",
	"pi": "BtCombat.shot_why_not",
	"hv": "BtCombat.atk_math",
	"su": "BtCombat.atk_math, BtPend.count_hits",
	"tr": "BtCombat.atk_math, BtPend.count_hits, BtPend.apply_hit, BtPend.apply_reroll",
	"lh": "BtCombat.atk_math, BtPend.count_hits",
	"dw": "BtCombat.atk_math, BtPend.apply_wnd",
	"bl": "BtCombat.atk_math",
	"po": "BtCombat.atk_math",
	"mk": "BtCombat.atk_math, BtPend.mark_hit",
	"la": "BtCombat.atk_math",
	"fx": "none",
	"trail": "none",
}
# rf ครึ่งระยะยิงเพิ่ม rf นัด · as วิ่งแล้วยิงได้ · pi ปืนพก ยิงหน่วยที่ประชิดได้ · hv ยืนนิ่งเข้าเป้าง่ายขึ้นหนึ่ง
# su ได้หกนับเข้าเพิ่ม · tr พ่น โดนอัตโนมัติ ทอยใหม่ไม่ได้ · lh เข้าได้หกเจาะเลย · dw เจาะได้หกเป็นแผลตรง
# bl เป้าทุกห้าตัวยิงเพิ่มหนึ่ง · po พิษ ทหารเดินเท้าเจาะได้ตั้งแต่ po · mk ชี้เป้า · la บุกเข้ามาเจาะง่ายขึ้นหนึ่ง
# fx/trail เอฟเฟกต์ (จอ)

## ชนิดออร่า (ค่าของธง aura) -> ตัวจัดการ: พวกเดียวกันในระยะ AURA_R
const AURAS := {
	"hit": "BtCombat.atk_math",
	"veil": "BtCombat.atk_math",
	"bless": "BtCombat.atk_math",
	"ld": "BtTurn.start_turn",
	"rez": "BtTurn.start_turn",
}
# hit เข้าเป้าง่ายขึ้นหนึ่ง · veil โดนยิงเข้ายากขึ้นหนึ่ง · bless เซฟพิเศษ BLESS_INV · ld ไม่ต้องทดสอบขวัญ
# rez ซ่อมตัวเองได้ที่ REZ_AURA

## กฎทั้งกองทัพ (โค้ด ไม่ใช่ข้อมูล) -> ตัวจัดการ ตามรหัสกองทัพใน facs.json
const ARMIES := {
	"gr": "none",
	"mod": "none",
	"kn": "none",
	"sw": "none",
	"rb": "none",
	"or": "none",
	"th": "none",
	"jp": "none",
	"nr": "none",
	"eg": "none",
	"md": "none",
	"el": "BtCombat.shot_why_not",
	"de": "BtCombat.pain_on, BtCombat.atk_math, BtCombat.charge_why_not",
	"ta": "none",
	"cx": "BtCombat.pact_on, BtCombat.atk_math",
}
# el ยิงได้แม้วิ่งมา · de ตั้งแต่รอบ PAIN_ROUND ตีประชิดเข้าเป้าง่ายขึ้นหนึ่งและวิ่งแล้วบุกได้
# cx ตีประชิดได้หกนับเข้าเพิ่มหนึ่ง · ta ตัวชี้เป้าเป็นคำ mk ของอาวุธ · kn ภาคีเป็นธง ch (จอ)


## รายชื่อตัวจัดการของรายการหนึ่งในทะเบียน ("none" หรือว่าง = ไม่มี)
static func handlers(entry: String) -> PackedStringArray:
	var out := PackedStringArray()
	if entry == "" or entry == "none":
		return out
	for h: String in entry.split(", "):
		out.append(h)
	return out


# ---------------------------------------------------------------- ตัวอ่านข้อมูล
## ข้อมูลหน่วยตามตำแหน่งใน TYPES (TY); นอกตาราง = {} (หน้าเก่าไม่มีคีย์แปลก: ตัดตั้งแต่จัดทัพ)
static func ty(ti: int) -> Dictionary:
	if ti < 0 or ti >= GameData.count():
		return {}
	return GameData.types()[ti]


## ธงจริงไหมแบบ JavaScript (ไม่มี/null/0/false/"" = เท็จ)
static func flag(ti: int, name: String) -> bool:
	return _truthy(ty(ti).get(name, null))


## ค่าจำนวนเต็มของช่อง (ไม่มีหรือไม่ใช่ตัวเลข = 0)
static func num(ti: int, name: String) -> int:
	return _int(ty(ti).get(name, null))


## ค่าข้อความของช่อง (aura, fac; ไม่มี = "")
static func text(ti: int, name: String) -> String:
	var v: Variant = ty(ti).get(name, null)
	return str(v) if typeof(v) == TYPE_STRING else ""


## อาวุธยิง (null ของหน้าเก่า = {}); ห้ามแก้ค่าที่ได้ เป็นของ GameData
static func gun(ti: int) -> Dictionary:
	var v: Variant = ty(ti).get("gun", null)
	return v if v is Dictionary else {}


## อาวุธประชิด ({} = ไม่มี); ห้ามแก้ค่าที่ได้
static func mel(ti: int) -> Dictionary:
	var v: Variant = ty(ti).get("mel", null)
	return v if v is Dictionary else {}


## ค่าจำนวนเต็มของช่องอาวุธ (ไม่มี = 0)
static func wnum(w: Dictionary, name: String) -> int:
	return _int(w.get(name, null))


## คำของอาวุธจริงไหม
static func wflag(w: Dictionary, name: String) -> bool:
	return _truthy(w.get(name, null))


static func _truthy(v: Variant) -> bool:
	match typeof(v):
		TYPE_NIL:
			return false
		TYPE_BOOL:
			return bool(v)
		TYPE_INT:
			return int(v) != 0
		TYPE_STRING:
			return str(v) != ""
	# ออบเจกต์และอาร์เรย์จริงเสมอเหมือน JavaScript
	return true


static func _int(v: Variant) -> int:
	if typeof(v) == TYPE_INT:
		return int(v)
	if typeof(v) == TYPE_BOOL:
		return 1 if bool(v) else 0
	return 0


# ---------------------------------------------------------------- ตัวจัดการที่ต้องใช้ pend (wave 3 เขียนต่อตรงนี้)
# glory_heal, revive_one, wind_fall, wind_up, wind_gone, wind_turn, spawn_from, after_kills, refill_shields
