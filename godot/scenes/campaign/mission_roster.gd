class_name MissionRoster
extends RefCounted
## ตัวละครศัตรูของแต่ละฝ่าย (CAMPAIGN_SPEC §2.2, track C เป็นเจ้าของ): บทบาท → ชุดโมเดลของโต๊ะรบ (KitLibrary)
## ทุกชุดในตารางมีโครง 23 กระดูก (skinned) · style beast = ท่ากรงเล็บของ KitBeast, fighter = ท่าคนถืออาวุธ
## ไม่มีชุดโมเดลบนเครื่อง (เทส/แอปที่ยังไม่โหลดชุด) = ไข่สัตว์รังของ KitBeast ย้อมสี col ของฝ่าย
## ฝ่าย swarm: บทบาท brute ใช้ศัตรูของชุดเสริม (ArenaActors.make_figure("enemy")) เมื่อมี ไม่งั้นชุด warrior
## ค่ายลับ (destroy_camp): ยามในค่ายเป็นฝ่าย cult เสมอ ส่วนศัตรูรอบนอกเป็นผู้รุกรานของดาว
## TODO(track C): เลือกท่า/อาวุธของแต่ละชุด ปรับขนาดและรัศมีชน ตามที่เล่นจริง

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


## ชุดโมเดลของบทบาท ("" = ฝ่ายนี้ไม่มีบทบาทนี้: แบ่งสัดส่วนให้ rusher)
static func kit(faction: String, role: String) -> String:
	return str(FACTIONS.get(faction, {}).get(role, ""))


static func style(faction: String) -> String:
	return str(FACTIONS.get(faction, {}).get("style", "beast"))
