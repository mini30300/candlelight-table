class_name MissionRoster
extends RefCounted
## ตัวละครศัตรูของแต่ละฝ่าย (CAMPAIGN_SPEC §2.2, track C เป็นเจ้าของ): บทบาท → ชุดโมเดลของโต๊ะรบ (KitLibrary)
## ทุกชุดในตารางมีโครง 23 กระดูก (skinned) · style beast = ท่ากรงเล็บของ KitBeast, fighter = ท่าคนถืออาวุธ
## ไม่มีชุดโมเดลบนเครื่อง (เทส/แอปที่ยังไม่โหลดชุด) = ไข่สัตว์รังของ KitBeast ย้อมสี col ของฝ่าย
## ฝ่าย swarm: บทบาท brute ใช้ศัตรูของชุดเสริม (ArenaActors.make_figure("enemy")) เมื่อมี ไม่งั้นชุด warrior
## ค่ายลับ (destroy_camp): ยามในค่ายเป็นฝ่าย cult เสมอ ส่วนศัตรูรอบนอกเป็นผู้รุกรานของดาว
## ค่าต่อบทบาทหลังคูณความยากและลักษณะพิเศษ: stats(spec, role) (ศัตรูทุกตัวใช้ค่านี้ ไม่คิดเองที่อื่น)

const ROLES: PackedStringArray = ["rusher", "gunner", "brute", "boss"]
## สัดส่วน (ร้อยละ) ของศัตรูทั่วไปในแต่ละระลอก; boss มาแยก (ระลอกสุดท้าย หรือ champion)
const SHARE := {"rusher": 60, "gunner": 25, "brute": 15}

## ค่าพื้นฐานต่อบทบาทที่ความยากธรรมดา (ก่อนคูณ hp_pct / dmg_pct / speed_pct / windup_pct) เทียบกับ ArenaData:
## ปืนไรเฟิล 12 × 8 นัด/วิ · hp = พลังชีวิต, speed = ม./วิ ตอนไล่, dmg = ต่อครั้ง, windup = วิ ก่อนโดน,
## reach = ระยะตี (ม.), range = ระยะยิงของ gunner (ม.), bolt = ความเร็วกระสุนช้าที่หลบได้ (ม./วิ), radius = รัศมีชน
const ROLE_STATS := {
	"rusher": {"hp": 60, "speed": 3.6, "dmg": 8, "windup": 0.45, "reach": 1.8, "radius": 0.45},
	"gunner": {"hp": 80, "speed": 2.6, "dmg": 10, "windup": 0.8, "range": 14.0, "bolt": 12.0, "radius": 0.45},
	"brute": {"hp": 300, "speed": 2.4, "dmg": 18, "windup": 0.6, "reach": 2.6, "radius": 0.6},
	"boss": {"hp": 900, "speed": 2.6, "dmg": 26, "windup": 0.7, "reach": 3.0, "radius": 0.75},
}

const FACTIONS := {
	"swarm": {"style": "beast", "rusher": "hound", "gunner": "spitter", "brute": "warrior", "boss": "swlord",
		"pack_brute": true},
	"orcs": {"style": "fighter", "rusher": "boy", "gunner": "loota", "brute": "nob", "boss": "boss"},
	"cult": {"style": "fighter", "rusher": "cxc", "gunner": "cxc_b", "brute": "dmc", "boss": "cxs"},
	"traitors": {"style": "fighter", "rusher": "cxb", "gunner": "cxw", "brute": "cxp", "boss": "cxl"},
	"machines": {"style": "fighter", "rusher": "rbskorp", "gunner": "rwar", "brute": "rguard", "boss": "rlord"},
	"raiders": {"style": "fighter", "rusher": "dewych", "gunner": "dewar", "brute": "deincubi", "boss": "dearchon"},
	"daemons": {"style": "beast", "rusher": "dmr", "gunner": "dmf", "brute": "dmp", "boss": "dmc_b"},
	"tomb": {"style": "fighter", "rusher": "mummy", "gunner": "", "brute": "sobek", "boss": "anubis"},
}


## ตัวประกัน (ชุดแรกที่มีบนเครื่อง ไม่มีเลย = ไข่ของดาดฟ้า)
const HOSTAGE_KITS: PackedStringArray = ["cmdr", "levy", "infantry"]
## ไม่มีชุดโมเดลบนเครื่อง: ไข่ของ KitBeast ใหญ่/เล็กตามบทบาท
const EGG_SCALE := {"rusher": 0.8, "gunner": 0.85, "brute": 1.15, "boss": 1.5}


## ค่าของบทบาทหลังคูณ: hp × hp_pct ของความยาก × hp_pct ของลักษณะพิเศษ, dmg × dmg_pct, speed × speed_pct (× ของลักษณะ),
## windup × windup_pct · จำนวนเต็มคิดแบบปัดลง (hp อย่างน้อย 1)
static func stats(spec: Dictionary, role: String) -> Dictionary:
	var base: Dictionary = (ROLE_STATS.get(role, ROLE_STATS["rusher"]) as Dictionary).duplicate()
	var d: Dictionary = spec.get("diff", {})
	var m: Dictionary = MissionTypes.MODIFIERS.get(str(spec.get("modifier", "")), {})
	base["hp"] = maxi(int(base["hp"]) * int(d.get("hp_pct", 100)) / 100 * int(m.get("hp_pct", 100)) / 100, 1)
	base["dmg"] = maxi(int(base["dmg"]) * int(d.get("dmg_pct", 100)) / 100, 1)
	base["speed"] = float(base["speed"]) * float(d.get("speed_pct", 100)) / 100.0 * float(m.get("speed_pct", 100)) / 100.0
	base["windup"] = float(base["windup"]) * float(d.get("windup_pct", 100)) / 100.0
	base["role"] = role
	return base


## ชุดโมเดลของบทบาท ("" = ฝ่ายนี้ไม่มีบทบาทนี้: แบ่งสัดส่วนให้ rusher)
static func kit(faction: String, role: String) -> String:
	return str(FACTIONS.get(faction, {}).get(role, ""))


static func style(faction: String) -> String:
	return str(FACTIONS.get(faction, {}).get("style", "beast"))
