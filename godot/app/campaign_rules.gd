class_name CampaignRules
extends RefCounted
## ตัวเลขของแคมเปญ (CAMPAIGN_SPEC §2.5–§2.7): ตารางความยาก คะแนนจากผลภารกิจ เหรียญ และเกรด
## เลขจำนวนเต็มล้วน (ร้อยละ / สิบเท่า) ผลเท่ากันทุกเครื่อง · ข้อความไทยทุกตัวมีคำแปลใน ui/i18n/campaign.json
## ผลภารกิจ (result) มาจาก MissionScreen.finished ตามรูปแบบใน CAMPAIGN_SPEC §5.5

## ความยาก: count/hp/dmg/speed = ร้อยละของค่าปกติ, windup = ร้อยละของเวลาง้าง (น้อย = ตีไวขึ้น),
## revives = ลุกได้กี่ครั้ง, score_x10 = ตัวคูณคะแนน × 10
const DIFFICULTY := {
	"normal": {"th": "ธรรมดา", "blurb": "เหมาะกับการเริ่มต้น", "count_pct": 100, "hp_pct": 100, "dmg_pct": 100,
		"speed_pct": 100, "windup_pct": 100, "revives": 2, "score_x10": 10},
	"hard": {"th": "ยาก", "blurb": "ศัตรูมากขึ้นและแรงขึ้น", "count_pct": 140, "hp_pct": 130, "dmg_pct": 130,
		"speed_pct": 110, "windup_pct": 90, "revives": 1, "score_x10": 15},
	"veryhard": {"th": "ยากมาก", "blurb": "ศัตรูดุ เร็ว และไม่ค่อยพลาด", "count_pct": 180, "hp_pct": 170, "dmg_pct": 160,
		"speed_pct": 120, "windup_pct": 80, "revives": 1, "score_x10": 25},
	"catastrophe": {"th": "ภัยพิบัติ", "blurb": "ล้มแล้วไม่มีโอกาสลุก — สำหรับผู้กล้าเท่านั้น", "count_pct": 240, "hp_pct": 220,
		"dmg_pct": 200, "speed_pct": 130, "windup_pct": 70, "revives": 0, "score_x10": 40},
}

## แต้มต่อการสังหารตามบทบาท (MissionRoster.ROLES) และต่อสิ่งก่อสร้างที่ทำลาย
const KILL_POINTS := {"rusher": 10, "gunner": 20, "brute": 40, "boss": 150, "structure": 50}
const ACC_MIN_SHOTS := 15        # ยิงน้อยกว่านี้ไม่คิดโบนัสความแม่นยำ
const ACC_MAX := 500             # โบนัสความแม่นยำสูงสุด (แม่น 100 %)
const TIME_PER_S := 4            # แต้มต่อวินาทีที่เร็วกว่าเวลามาตรฐาน (ชนะเท่านั้น)
const PRIMARY := 1000
const SECONDARY := 300
const PER_HOSTAGE := 100
const BASE_PER_PCT := 5          # ป้องกันฐาน: แต้มต่อร้อยละของฐานที่เหลือ
const DAMAGE_CAP := 400          # หักแต้มตามความเสียหายที่ได้รับ ไม่เกินนี้
const NO_DOWN := 500             # ชนะโดยไม่ล้มเลย
## เหรียญ: ชนะ = คะแนนรวม / 40 (อย่างน้อย 10), แพ้/ออกกลางคัน = คะแนนรวม / 160
const COIN_DIV_WIN := 40
const COIN_DIV_FAIL := 160
const COIN_MIN_WIN := 10
const FEATURED_PCT := 150        # ดาวเด่นประจำสัปดาห์
const REPEAT_PCT := 25           # เล่นเหตุการณ์เดิมที่ความยากเดิมซ้ำในสัปดาห์เดียวกัน
## เกรดจากคะแนนก่อนคูณ (ชนะเท่านั้น; แพ้ = "-")
const GRADES := [["S", 3000], ["A", 2200], ["B", 1500], ["C", 800], ["D", 0]]

## ชื่อบรรทัดในหน้าสรุปผล (key → ข้อความไทย)
const LINE_TH := {
	"kills": "สังหารศัตรู",
	"accuracy": "ความแม่นยำ",
	"time": "เร็วกว่าเวลามาตรฐาน",
	"primary": "เป้าหมายหลัก",
	"secondary": "เป้าหมายรอง",
	"hostages": "ตัวประกันที่รอด",
	"base": "ฐานที่เหลือ",
	"damage": "ความเสียหายที่ได้รับ",
	"no_down": "ไม่ล้มเลย",
}


## แถวความยาก (สำเนา) พร้อม "id" · id ผิด = ธรรมดา
static func difficulty(id: String) -> Dictionary:
	var key := id if DIFFICULTY.has(id) else "normal"
	var d: Dictionary = DIFFICULTY[key].duplicate()
	d["id"] = key
	return d


## ตัวคูณคะแนนเป็นข้อความ "×1.5"
static func mult_text(id: String) -> String:
	var x := int(difficulty(id)["score_x10"])
	return "×%d" % (x / 10) if x % 10 == 0 else "×%d.%d" % [x / 10, x % 10]


## คะแนนของภารกิจ: spec = CampaignGalaxy.mission_spec, result = MissionScreen.finished, opts {"repeat": bool}
## คืน {"win", "lines": [{key, th, value}], "raw", "mult_x10", "total", "coins", "grade", "acc_pct"}
static func score(spec: Dictionary, result: Dictionary, opts: Dictionary = {}) -> Dictionary:
	var win := str(result.get("outcome", "")) == "win"
	var lines: Array[Dictionary] = []
	var kills := 0
	var kd: Dictionary = result.get("kills", {})
	for role in KILL_POINTS:
		kills += int(KILL_POINTS[role]) * maxi(int(kd.get(role, 0)), 0)
	_line(lines, "kills", kills)
	var shots := maxi(int(result.get("shots", 0)), 0)
	var hits := clampi(int(result.get("hits", 0)), 0, shots)
	var acc_pct := (hits * 100) / shots if shots > 0 else 0
	if shots >= ACC_MIN_SHOTS:
		_line(lines, "accuracy", acc_pct * acc_pct * ACC_MAX / 10000)
	var ptype := str((spec.get("primary", {}) as Dictionary).get("type", ""))
	var par := MissionTypes.par_s(ptype)
	if win and par > 0:
		_line(lines, "time", maxi(par - int(float(result.get("time_s", 0.0))), 0) * TIME_PER_S)
	if win:
		_line(lines, "primary", PRIMARY)
	var sec: Array = result.get("secondary_done", [])
	var n_sec := 0
	for done: Variant in sec:
		if bool(done):
			n_sec += 1
	if n_sec > 0:
		_line(lines, "secondary", n_sec * SECONDARY)
	if result.has("hostages_saved"):
		_line(lines, "hostages", maxi(int(result["hostages_saved"]), 0) * PER_HOSTAGE)
	if result.has("base_hp_pct"):
		_line(lines, "base", clampi(int(result["base_hp_pct"]), 0, 100) * BASE_PER_PCT)
	_line(lines, "damage", -mini(maxi(int(result.get("damage_taken", 0)), 0), DAMAGE_CAP))
	if win and int(result.get("downs", 0)) == 0:
		_line(lines, "no_down", NO_DOWN)
	var raw := 0
	for l in lines:
		raw += int(l["value"])
	raw = maxi(raw, 0)
	var mx := int(difficulty(str(spec.get("difficulty", "normal")))["score_x10"])
	var total := raw * mx / 10
	var coins := maxi(total / COIN_DIV_WIN, COIN_MIN_WIN) if win else total / COIN_DIV_FAIL
	if bool(spec.get("featured", false)):
		coins = coins * FEATURED_PCT / 100
	if bool(opts.get("repeat", false)):
		coins = coins * REPEAT_PCT / 100
	var grade := "-"
	if win:
		for g: Array in GRADES:
			if raw >= int(g[1]):
				grade = str(g[0])
				break
	return {"win": win, "lines": lines, "raw": raw, "mult_x10": mx, "total": total, "coins": coins, "grade": grade,
		"acc_pct": acc_pct}


static func _line(lines: Array[Dictionary], key: String, value: int) -> void:
	lines.append({"key": key, "th": str(LINE_TH[key]), "value": value})


## เหรียญโดยประมาณบนการ์ดดาว (CAMPAIGN_SPEC §1.5): ชนะเป้าหมายหลัก + ไม่ล้ม + ทำเป้าหมายรองครบ คูณความยาก
## แล้วคิดแบบเดียวกับ score(): อย่างน้อย COIN_MIN_WIN, ดาวเด่น × FEATURED_PCT, เล่นซ้ำ × REPEAT_PCT (ไม่รวมแต้มสังหาร/เวลา)
static func estimate_coins(spec: Dictionary, repeat := false) -> int:
	if spec.is_empty():
		return 0
	var n_sec := (spec.get("secondary", []) as Array).size()
	var mx := int(difficulty(str(spec.get("difficulty", "normal")))["score_x10"])
	var coins := maxi((PRIMARY + NO_DOWN + SECONDARY * n_sec) * mx / 10 / COIN_DIV_WIN, COIN_MIN_WIN)
	if bool(spec.get("featured", false)):
		coins = coins * FEATURED_PCT / 100
	if repeat:
		coins = coins * REPEAT_PCT / 100
	return coins
