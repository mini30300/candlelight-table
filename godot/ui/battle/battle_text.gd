class_name BattleText
extends RefCounted
## ข้อความของหน้ารบ (LOBBY_SPEC §4.3): เหตุการณ์ของกติกาเป็นบรรทัดบันทึก เหตุผลที่สั่งไม่ได้ ป้ายตา/เฟส ผลจบเกม
## แปลทั้งประโยคก่อนแล้วค่อยใส่ตัวเลข (I18n หาทีละประโยค) ผ่าน DatasheetText.tl/tf · ลูกเต๋าเป็นตัวเลข ไม่มีถาดลูกเต๋า
## เหตุการณ์ที่ไม่รู้จักไม่แสดง · ไม่อ่านหรือเขียนอะไรนอกจากที่ได้รับ

## เหตุผลที่สั่งไม่ได้ (รหัสจาก BtMoves.try_move / BtCombat.*_why_not / MatchRunner) ที่เหมือนกันทุกเฟส
const WHY := {
	"no_squad": "แตะหน่วยของเราก่อน แล้วค่อยแตะพื้น",
	"already_moved": "หน่วยนี้เดินไปแล้วในเทิร์นนี้",
	"engaged_need_fb": "ติดประชิดอยู่ — กด ถอย ก่อนแล้วแตะพื้น",
	"blocked": "ตรงนั้นมีสิ่งกีดขวาง — เลือกที่โล่ง",
	"cant_fall_back": "ถอยไม่ได้ — ไม่มีทางออกจากการประชิด",
	"near_foe": "ใกล้ศัตรูเกินไป — ต้องบุกในเฟสบุก",
	"no_room": "ตรงนั้นไม่มีที่ว่างพอ",
	"fb_not_clear": "ถอยแล้วยังใกล้ศัตรู — แตะให้ไกลกว่านี้",
	"no_gun": "หน่วยนี้ไม่มีอาวุธยิง",
	"own_side": "ยิงพวกเดียวกันไม่ได้",
	"already_shot": "หน่วยนี้ยิงไปแล้วในเทิร์นนี้",
	"target_engaged": "ยิงไม่ได้ เดี๋ยวโดนพวกเดียวกัน",
	"enemies_only": "บุกได้แค่ศัตรู",
	"charge_done": "หน่วยนี้บุกไปแล้วในเทิร์นนี้",
	"nobody_hurt": "ไม่มีใครบาดเจ็บ",
	"already_acted": "หน่วยนี้ใช้การกระทำไปแล้วในเทิร์นนี้",
	"not_infantry": "ปาระเบิดได้แค่ทหารเดินเท้า",
	"moved_fast": "วิ่งหรือถอยมา ปาระเบิดไม่ได้",
	"not_now": "ตอนนี้สั่งหน่วยนี้ไม่ได้",
	"refused": "คำสั่งนี้ใช้ไม่ได้",
	"select_first": "แตะหน่วยของเราก่อน แล้วค่อยแตะพื้น",
}
## เหตุผลที่ข้อความต่างกันตามเฟส (ctx = move / shoot / charge)
const WHY_CTX := {
	"too_far|move": "ไกลเกินระยะเดิน {mv} นิ้ว",
	"too_far|shoot": "อยู่นอกระยะยิง {rng} นิ้ว (ห่าง {d} นิ้ว)",
	"too_far|charge": "ไกลเกินระยะบุก {r} นิ้ว (ขอบห่าง {d} นิ้ว)",
	"too_far|other": "ไกลเกินไป",
	"advanced|shoot": "วิ่งมา ยิงไม่ได้",
	"advanced|charge": "วิ่งมา บุกไม่ได้ในเทิร์นนี้",
	"fell_back|shoot": "ถอยออกจากการประชิดมา ยิงไม่ได้ในเทิร์นนี้",
	"fell_back|charge": "ถอยมา บุกไม่ได้ในเทิร์นนี้",
	"engaged|shoot": "ติดประชิดอยู่ ยิงไม่ได้",
	"engaged|pistol": "ติดประชิดอยู่ — ปืนพกยิงได้แค่ศัตรูที่ประชิด",
	"engaged|charge": "ติดประชิดอยู่แล้ว",
}
## ผลจบเกมจาก OVER why
const REASON := {
	"over_last": "เหลือทีมเดียว",
	"over_rounds": "ครบรอบ — แต้มชัยสูงสุด",
	"over_kill_rounds": "ครบ 30 รอบ",
}
## แม่แบบบรรทัดบันทึกและป้าย
const T_TURN := "รอบ {r} · ตาของ{team}"
const T_PHASE := "— เฟส{phase} —"
const T_HIT := "{a} → {t} · ทอยโดน: {dice}"
const T_RR := "ทอยใหม่: {dice}"
const T_WOUND := "ทอยเจาะ: {dice}"
const T_SAVE := "ทอยเซฟ: {dice}"
const T_FELL := "ล้ม {n} ตัว"
const T_CHARGE := "{a} บุกเข้าใส่ {t}"
const T_SHOCK_OK := "{a} ผ่านทดสอบขวัญ"
const T_SHOCK_BAD := "{a} เสียขวัญ"
const T_OVER := "จบเกม — {why}"
const T_LABEL := "รอบ {r} / {n} · ตาของ{team} · เฟส{phase}"
const T_WIN := "{team} ชนะ!"
const YOU_WIN := "คุณชนะ!"
const YOU_LOSE := "คุณแพ้"
const DRAW := "เสมอ"
const PHASES_PATH := "res://data/phases.json"
const TEAMS_PATH := "res://data/teams.json"
const MAX_SHOWN_DICE := 12

static var _phase_nm: Dictionary = {}
static var _team_nm: PackedStringArray = []


## ข้อความเหตุผลที่สั่งไม่ได้ (args ตามรหัสของแกน) · ctx = move / shoot / charge
static func why(key: String, args: Array = [], ctx: String = "") -> String:
	if key == "":
		return ""
	if key == "engaged" and ctx == "shoot" and not args.is_empty() and int(args[0]) == 1:
		return DatasheetText.tl(WHY_CTX["engaged|pistol"])
	var ck := "%s|%s" % [key, ctx]
	if WHY_CTX.has(ck):
		var a := {}
		match ck:
			"too_far|move":
				a = {"mv": int(args[1]) if args.size() > 1 else 0}
			"too_far|shoot":
				a = {"d": _inch(args[0]) if args.size() > 0 else 0, "rng": int(args[1]) if args.size() > 1 else 0}
			"too_far|charge":
				a = {"d": _inch(args[0]) if args.size() > 0 else 0, "r": GameData.const_int("CHARGE_R", 12)}
		return DatasheetText.tf(WHY_CTX[ck], a)
	if WHY.has(key):
		return DatasheetText.tl(WHY[key])
	# รหัสที่ต่างตามเฟสแต่ไม่ได้บอกเฟส: ใช้ของเฟสบุก/ยิงที่มี
	for c in ["charge", "shoot", "other"]:
		if WHY_CTX.has("%s|%s" % [key, c]):
			return why(key, args, c)
	return DatasheetText.tl(WHY["refused"])


## MI เป็นนิ้วทศนิยมหนึ่งตำแหน่ง ("12.5")
static func _inch(mi: Variant) -> String:
	var v := int(mi)
	return "%d.%d" % [v / 1000, absi(v % 1000) / 100]


## ชื่อทีม (teams.json nm แปลแล้ว)
static func team_name(team: int) -> String:
	if _team_nm.is_empty():
		var t: Variant = _json(TEAMS_PATH)
		if t is Array:
			for e: Variant in t:
				_team_nm.append(str((e as Dictionary).get("nm", "")) if e is Dictionary else "")
	if team < 0 or _team_nm.is_empty():
		return ""
	return DatasheetText.tl(_team_nm[team % _team_nm.size()])


## ชื่อเฟส (phases.json nm แปลแล้ว)
static func phase_name(ph: String) -> String:
	if _phase_nm.is_empty():
		var p: Variant = _json(PHASES_PATH)
		if p is Dictionary and (p as Dictionary).get("nm") is Dictionary:
			_phase_nm = (p as Dictionary)["nm"]
	return DatasheetText.tl(str(_phase_nm.get(ph, ph)))


## ป้ายบนสุด: รอบ r / n · ตาของทีม · เฟส
static func turn_label(st: BattleState) -> String:
	return DatasheetText.tf(T_LABEL, {"r": mini(st.round_no, st.max_round()), "n": st.max_round(),
		"team": team_name(st.turn), "phase": phase_name(st.phase_name())})


## หัวข้อแผงจบ: มีที่นั่งของคุณ = คุณชนะ! / คุณแพ้ / เสมอ ไม่มี = {ทีม} ชนะ! / เสมอ
static func end_title(winner: int, human_team: int) -> String:
	if winner < 0:
		return DatasheetText.tl(DRAW)
	if human_team >= 0:
		return DatasheetText.tl(YOU_WIN if winner == human_team else YOU_LOSE)
	return DatasheetText.tf(T_WIN, {"team": team_name(winner)})


static func reason(why_key: String) -> String:
	return DatasheetText.tl(str(REASON.get(why_key, ""))) if REASON.has(why_key) else ""


## ชื่อหน่วยของหมู่ (ชื่อบนการ์ดข้อมูล แปลแล้ว)
static func squad_name(st: BattleState, sid: String) -> String:
	var s := st.squad(sid) if st != null else null
	if s == null:
		return sid
	return DatasheetText.name_of(GameData.ty(s.k))


## เหตุการณ์ของหนึ่งก้าวเป็นบรรทัด (ล้มรวมเป็นบรรทัดเดียวท้ายก้าว)
static func lines(evs: Array, st: BattleState) -> PackedStringArray:
	var out := PackedStringArray()
	var fell := 0
	for e: Variant in evs:
		if not e is Dictionary:
			continue
		var ev: Dictionary = e
		var line := ""
		match Events.id_of(ev):
			Events.Id.TURN:
				line = DatasheetText.tf(T_TURN, {"r": int(ev.get("round", 0)), "team": team_name(int(ev.get("team", 0)))})
			Events.Id.PHASE:
				var ph := str(ev.get("ph", ""))
				if ph != "cmd":
					line = DatasheetText.tf(T_PHASE, {"phase": phase_name(ph)})
			Events.Id.ATTACK_STAGE:
				line = _stage(ev, st)
			Events.Id.DEATH:
				fell += 1
			Events.Id.CHARGE:
				line = DatasheetText.tf(T_CHARGE, {"a": squad_name(st, str(ev.get("sid", ""))), "t": squad_name(st, str(ev.get("tid", "")))})
			Events.Id.SHOCK:
				line = DatasheetText.tf(T_SHOCK_OK if bool(ev.get("pass", false)) else T_SHOCK_BAD, {"a": squad_name(st, str(ev.get("sid", "")))})
			Events.Id.OVER:
				var r := reason(str(ev.get("why", "")))
				if r != "":
					line = DatasheetText.tf(T_OVER, {"why": r})
		if line != "":
			out.append(line)
	if fell > 0:
		out.append(DatasheetText.tf(T_FELL, {"n": fell}))
	return out


static func _stage(ev: Dictionary, st: BattleState) -> String:
	var dice := dice_text(ev.get("dice", []))
	match str(ev.get("stage", "")):
		"hit":
			var p := str(ev.get("p", "")).split(">")
			var a := squad_name(st, p[0]) if p.size() > 0 else ""
			var t := squad_name(st, p[1]) if p.size() > 1 else ""
			return DatasheetText.tf(T_HIT, {"a": a, "t": t, "dice": dice})
		"rr":
			return DatasheetText.tf(T_RR, {"dice": dice})
		"wound":
			return DatasheetText.tf(T_WOUND, {"dice": dice})
		"save":
			return DatasheetText.tf(T_SAVE, {"dice": dice})
	return ""


## ลูกเต๋าเป็นตัวเลขเว้นวรรค ไม่เกิน MAX_SHOWN_DICE ลูก ("6 5 3 1 …")
static func dice_text(d: Variant) -> String:
	var parts := PackedStringArray()
	var arr: Array = Array(d) if (d is Array or d is PackedInt32Array or d is PackedInt64Array) else []
	for i in mini(arr.size(), MAX_SHOWN_DICE):
		parts.append(str(int(arr[i])))
	if arr.size() > MAX_SHOWN_DICE:
		parts.append("…")
	return "-" if parts.is_empty() else " ".join(parts)


static func _json(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		return null
	return JSON.parse_string(FileAccess.get_file_as_string(path))
