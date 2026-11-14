class_name MissionTypes
extends RefCounted
## ประเภทภารกิจและลักษณะพิเศษของศัตรู (CAMPAIGN_SPEC §2.4, track C เป็นเจ้าของไฟล์และปรับตัวเลข)
## ชื่อไทยมีคำแปลใน ui/i18n/campaign_mission.json · ตัวเลขเป็นจำนวนเต็ม (วินาที จำนวนตัว ร้อยละ)
## CampaignRules อ่าน par_s() ไปคิดโบนัสเวลา · หน้าการ์ดดาวอ่าน name_th() / goal_th()
## TODO(track C): ปรับตัวเลขหลังเล่นจริง (บันทึกใน CAMPAIGN_SPEC §12.C ว่าเปลี่ยนอะไร เพราะอะไร)

## par_s = เวลามาตรฐาน (0 = ไม่มีโบนัสเวลา), limit_s = หมดเวลาแล้วแพ้ (0 = ไม่มี; ป้องกันฐานชนะเมื่อครบเวลา)
## enemies = จำนวนศัตรูทั้งภารกิจที่ความยากธรรมดา (คูณ count_pct ของความยาก), waves = จำนวนระลอก
const TYPES := {
	"purge": {"th": "กวาดล้างผู้รุกราน", "goal": "กำจัดศัตรูให้หมดพื้นที่", "par_s": 240, "limit_s": 0,
		"enemies": 24, "waves": 3},
	"defend": {"th": "ป้องกันฐาน", "goal": "รักษาฐานไว้จนกว่ากำลังเสริมจะมาถึง", "par_s": 0, "limit_s": 180,
		"enemies": 30, "waves": 5, "base_hp": 1000},
	"rescue": {"th": "ช่วยตัวประกัน", "goal": "พาตัวประกันทุกคนกลับถึงจุดรับ", "par_s": 300, "limit_s": 600,
		"enemies": 18, "waves": 2, "hostages": 3},
	"destroy_camp": {"th": "ทำลายค่ายลับลัทธิมืด", "goal": "ทำลายเสาพิธีกรรมทั้งสามในค่าย", "par_s": 270,
		"limit_s": 0, "enemies": 20, "waves": 2, "pylons": 3, "pylon_hp": 400},
}

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
