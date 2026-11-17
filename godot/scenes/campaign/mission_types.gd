class_name MissionTypes
extends RefCounted
## ประเภทภารกิจและลักษณะพิเศษของศัตรู (CAMPAIGN_SPEC §2.4, track C เป็นเจ้าของไฟล์และปรับตัวเลข)
## ชื่อไทยมีคำแปลใน ui/i18n/campaign_mission.json · ตัวเลขเป็นจำนวนเต็ม (วินาที จำนวนตัว ร้อยละ)
## CampaignRules อ่าน par_s() ไปคิดโบนัสเวลา · หน้าการ์ดดาวอ่าน name_th() / goal_th()
## ตัวเลขที่ปรับแล้วบันทึกใน CAMPAIGN_SPEC §12.C

## par_s = เวลามาตรฐาน (0 = ไม่มีโบนัสเวลา), limit_s = หมดเวลาแล้วแพ้ (0 = ไม่มี; ป้องกันฐานชนะเมื่อครบเวลา)
## enemies = จำนวนศัตรูทั้งภารกิจที่ความยากธรรมดา (คูณ count_pct ของความยาก), waves = จำนวนระลอก
## bosses = หัวหน้าที่มาเพิ่มในระลอกสุดท้าย (champion เพิ่มอีก 1) · guards = ยามค่ายลัทธิ (ไม่นับใน enemies)
## extract = ทำเป้าหมายครบแล้วต้องเดินกลับวงจุดรับจึงชนะ · wave_at = วินาทีที่ระลอกเริ่ม (−1 = รอเคลียร์ระลอกก่อน)
const TYPES := {
	"purge": {"th": "กวาดล้างผู้รุกราน", "goal": "กำจัดศัตรูให้หมดพื้นที่", "par_s": 240, "limit_s": 0,
		"enemies": 24, "waves": 3, "bosses": 1, "wave_at": [0, -1, -1]},
	"defend": {"th": "ป้องกันฐาน", "goal": "รักษาฐานไว้จนกว่ากำลังเสริมจะมาถึง", "par_s": 0, "limit_s": 180,
		"enemies": 30, "waves": 5, "base_hp": 1000, "bosses": 1, "wave_at": [3, 30, 62, 96, 130]},
	"rescue": {"th": "ช่วยตัวประกัน", "goal": "พาตัวประกันทุกคนกลับถึงจุดรับ", "par_s": 300, "limit_s": 600,
		"enemies": 18, "waves": 2, "hostages": 3, "bosses": 0, "wave_at": [0, 90], "extract": true},
	"destroy_camp": {"th": "ทำลายค่ายลับลัทธิมืด", "goal": "ทำลายเสาพิธีกรรมทั้งสามในค่าย", "par_s": 270,
		"limit_s": 0, "enemies": 20, "waves": 2, "pylons": 3, "pylon_hp": 400, "bosses": 1, "guards": 6,
		"wave_at": [0, 120], "extract": true},
}
## ตัวประกัน: พลังชีวิต, เวลากดปล่อย (ยืนในวง), รัศมีวงปล่อย / วงจุดรับ / วงสัญญาณ (ม.)
const HOSTAGE := {"hp": 120, "free_s": 1.5, "free_r": 1.6, "follow_gap": 1.4, "speed": 4.2}
const PICKUP_R := 2.6
const BEACON_R := 2.4
## ฐาน (ป้องกันฐาน): รัศมีที่ศัตรูตีโดน (ม.) · ความเสียหายต่อฐานคูณจากดาเมจศัตรู (ร้อยละ)
const BASE_R := 2.2
const BASE_DMG_PCT := 150
## ร้อยละของศัตรูที่อ้อมโอบแทนเดินตรงเข้ามา (ตามความยาก)
const FLANK_PCT := {"normal": 10, "hard": 25, "veryhard": 40, "catastrophe": 55}
## ศัตรูที่ยังมีชีวิตพร้อมกันได้ไม่เกิน (ตามระดับกราฟิก; จำนวนทั้งภารกิจไม่เปลี่ยน ระลอกเติมเมื่อมีตัวตาย)
const ALIVE_CAP := {"hi": 14, "mid": 10, "lo": 7, "min": 5}
## ตัวละครมีโครง (skinned) บนจอได้ไม่เกิน (ผู้เล่น + ตัวประกัน + ศัตรู + ศพที่ยังไม่หาย) ตาม test_budgets
const SKINNED_CAP := {"hi": 24, "mid": 16, "lo": 10, "min": 8}

## เป้าหมายรอง (เหตุการณ์อื่นบนดาวเดียวกัน) แบบย่อในแผนที่เดียวกัน
const SECONDARY := {
	"purge": {"th": "สังหารศัตรูให้ได้ 75 %", "kill_pct": 75},
	"defend": {"th": "ยึดสัญญาณไว้ 30 วินาที", "hold_s": 30},
	"rescue": {"th": "ช่วยตัวประกันที่ถูกขังไว้ 1 คน", "hostages": 1},
	"destroy_camp": {"th": "ทำลายเสาพิธีกรรม 1 ต้น", "pylons": 1},
}

## ผลของลักษณะพิเศษ (ร้อยละของค่าหลังคูณความยาก)
const MODIFIERS := {
	"armoured": {"hp_pct": 130},
	"frenzied": {"speed_pct": 120, "hp_pct": 90},
	"gunline": {"gunner_share_pct": 200},
	"horde": {"count_pct": 130, "hp_pct": 80},
	"champion": {"extra_boss": 1},
	"ambush": {"spawn_near": true},
}


static func name_th(t: String) -> String:
	return str(TYPES.get(t, {}).get("th", ""))


static func goal_th(t: String) -> String:
	return str(TYPES.get(t, {}).get("goal", ""))


static func secondary_th(t: String) -> String:
	return str(SECONDARY.get(t, {}).get("th", ""))


## ข้อมูลของประเภท (สำเนา) หรือ {}
static func type_row(t: String) -> Dictionary:
	return (TYPES.get(t, {}) as Dictionary).duplicate(true)


static func extracts(t: String) -> bool:
	return bool(TYPES.get(t, {}).get("extract", false))


## จำนวนหัวหน้าทั้งภารกิจ (ประเภท + champion)
static func boss_count(spec: Dictionary) -> int:
	var t := str((spec.get("primary", {}) as Dictionary).get("type", ""))
	var n := int(TYPES.get(t, {}).get("bosses", 0))
	n += int(MODIFIERS.get(str(spec.get("modifier", "")), {}).get("extra_boss", 0))
	return n


## จำนวนยามค่ายลัทธิ (ทำลายค่าย) หลังคูณจำนวนของความยาก
static func guard_count(spec: Dictionary) -> int:
	var t := str((spec.get("primary", {}) as Dictionary).get("type", ""))
	var g := int(TYPES.get(t, {}).get("guards", 0))
	if g <= 0:
		return 0
	return maxi(g * int((spec.get("diff", {}) as Dictionary).get("count_pct", 100)) / 100, 1)


static func flank_pct(difficulty: String) -> int:
	return int(FLANK_PCT.get(difficulty, 10))


static func alive_cap(level: String) -> int:
	return int(ALIVE_CAP.get(level, ALIVE_CAP["mid"]))


static func skinned_cap(level: String) -> int:
	return int(SKINNED_CAP.get(level, SKINNED_CAP["mid"]))


static func par_s(t: String) -> int:
	return int(TYPES.get(t, {}).get("par_s", 0))


static func limit_s(t: String) -> int:
	return int(TYPES.get(t, {}).get("limit_s", 0))


## จำนวนศัตรูทั้งภารกิจหลังคูณความยากและลักษณะพิเศษ (ปัดลง อย่างน้อย 1)
static func enemy_total(spec: Dictionary) -> int:
	var t := str((spec.get("primary", {}) as Dictionary).get("type", ""))
	var base := int(TYPES.get(t, {}).get("enemies", 0))
	var d: Dictionary = spec.get("diff", {})
	var n := base * int(d.get("count_pct", 100)) / 100
	n = n * int(MODIFIERS.get(str(spec.get("modifier", "")), {}).get("count_pct", 100)) / 100
	return maxi(n, 1)
