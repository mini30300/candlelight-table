extends "res://tests/testing.gd"
## Battle-track text (LOBBY_SPEC §4.3, §7.4): every Thai literal of the setup screen, the battle screen, BattleText,
## SeatPlan and MatchRunner is a whole key of I18n (I18n.t matches whole strings only); every why-not key the rules
## core can return (BtMoves.try_move, BtCombat.*_why_not) and every OVER reason has Thai and English text; the event
## lines read as expected in both languages, with dice as digits and deaths summed. Pure (no display).

const SCRIPTS: PackedStringArray = ["res://ui/screens/battle_setup.gd", "res://ui/screens/battle_screen.gd",
	"res://ui/battle/battle_text.gd", "res://ui/battle/seat_plan.gd", "res://ui/battle/match_runner.gd",
	"res://ui/screens/battle_setup.tscn", "res://ui/screens/battle_screen.tscn"]
const CORE_WHY: PackedStringArray = ["res://core/battle/moves.gd", "res://core/battle/combat.gd"]
const OVER_WHY: PackedStringArray = ["over_last", "over_rounds", "over_kill_rounds"]

var thai_re := RegEx.create_from_string("[฀-๿]")
var _was_english := false


func setup() -> void:
	_was_english = I18n.english


func test_every_thai_literal_is_a_whole_key() -> void:
	var lit_re := RegEx.create_from_string("\"((?:[^\"\\\\\\n]|\\\\.)*)\"")
	var missing := []
	var n := 0
	for path in SCRIPTS:
		var lits := PackedStringArray()
		if path.ends_with(".tscn"):
			var ps := load(path) as PackedScene
			assert_true(ps != null, "load " + path)
			if ps != null:
				var st := ps.get_state()
				for i in st.get_node_count():
					for j in st.get_node_property_count(i):
						var v: Variant = st.get_node_property_value(i, j)
						if v is String:
							lits.append(v)
		else:
			var src := FileAccess.get_file_as_string(path)
			assert_true(src != "", "read " + path)
			for line in src.split("\n"):
				if line.strip_edges().begins_with("#"):
					continue
				for m in lit_re.search_all(line):
					lits.append(m.get_string(1).replace("\\\"", "\""))
		for lit in lits:
			if thai_re.search(lit) == null:
				continue
			n += 1
			if not I18n.has_key(lit):
				missing.append(path.get_file() + ": " + lit)
	assert_true(n >= 80, "found %d Thai literals in the battle-track files" % n)
	assert_eq(missing, [], "every Thai literal is a whole key of the dictionaries")


## why-not keys returned by the rules core: the first argument of every _why("...") in moves.gd and combat.gd
func _core_why_keys() -> PackedStringArray:
	var re := RegEx.create_from_string("_why\\(\"([a-z_]*)\"")
	var out := PackedStringArray()
	for path in CORE_WHY:
		var src := FileAccess.get_file_as_string(path)
		assert_true(src != "", "read " + path)
		for m in re.search_all(src):
			var k := m.get_string(1)
			if k != "" and not out.has(k):
				out.append(k)
	return out


func test_every_core_why_key_has_thai_and_english() -> void:
	var keys := _core_why_keys()
	assert_true(keys.size() >= 20, "found %d why-not keys in the rules core" % keys.size())
	var thai_left := []
	var english_left := []
	I18n.english = false
	for k in keys:
		for ctx in ["move", "shoot", "charge", ""]:
			var th := BattleText.why(k, [3500, 6], ctx)
			if th == "" or thai_re.search(th) == null or th == BattleText.why("refused"):
				thai_left.append("%s (%s): %s" % [k, ctx, th])
	I18n.english = true
	for k in keys:
		for ctx in ["move", "shoot", "charge", ""]:
			var en := BattleText.why(k, [3500, 6], ctx)
			if en == "" or thai_re.search(en) != null:
				english_left.append("%s (%s): %s" % [k, ctx, en])
	for k in ["not_now", "refused", "select_first"]:
		if thai_re.search(BattleText.why(k)) != null:
			english_left.append(k)
	I18n.english = _was_english
	assert_eq(thai_left, [], "every core why-not key has its own Thai text in every phase")
	assert_eq(english_left, [], "every core why-not key has English text in every phase")


func test_why_texts_carry_their_numbers() -> void:
	I18n.english = false
	assert_eq(BattleText.why("too_far", [9000, 6], "move"), "ไกลเกินระยะเดิน 6 นิ้ว", "move too_far names the move range")
	assert_eq(BattleText.why("too_far", [30500, 24], "shoot"), "อยู่นอกระยะยิง 24 นิ้ว (ห่าง 30.5 นิ้ว)", "shoot too_far names range and distance")
	assert_eq(BattleText.why("too_far", [14200], "charge"), "ไกลเกินระยะบุก 12 นิ้ว (ขอบห่าง 14.2 นิ้ว)", "charge too_far names the charge range")
	assert_eq(BattleText.why("engaged", [1], "shoot"), "ติดประชิดอยู่ — ปืนพกยิงได้แค่ศัตรูที่ประชิด", "engaged with a pistol")
	assert_eq(BattleText.why("engaged", [0], "shoot"), "ติดประชิดอยู่ ยิงไม่ได้", "engaged without a pistol")
	assert_eq(BattleText.why("advanced", [], "charge"), "วิ่งมา บุกไม่ได้ในเทิร์นนี้", "advanced in the charge phase")
	assert_eq(BattleText.why(""), "", "no key, no text")
	I18n.english = true
	assert_eq(BattleText.why("too_far", [9000, 6], "move"), "Beyond the 6\" move range", "English move too_far")
	assert_eq(BattleText.why("already_moved"), "This unit has already moved this turn", "English already_moved (page key)")
	I18n.english = _was_english


func test_over_reasons_and_titles() -> void:
	for k in OVER_WHY:
		I18n.english = false
		var th := BattleText.reason(k)
		I18n.english = true
		var en := BattleText.reason(k)
		assert_true(thai_re.search(th) != null and en != "" and thai_re.search(en) == null, "%s: Thai '%s' and English '%s'" % [k, th, en])
	I18n.english = false
	assert_eq(BattleText.end_title(0, 0), "คุณชนะ!", "a human win")
	assert_eq(BattleText.end_title(1, 0), "คุณแพ้", "a human loss")
	assert_eq(BattleText.end_title(BattleState.DRAW, 0), "เสมอ", "a draw with a human seat")
	assert_eq(BattleText.end_title(1, -1), "ทีมแดง ชนะ!", "bots only: the winning team")
	assert_eq(BattleText.end_title(BattleState.DRAW, -1), "เสมอ", "bots only: a draw")
	I18n.english = true
	assert_eq(BattleText.end_title(0, 0), "You win!", "English human win")
	assert_eq(BattleText.end_title(1, 0), "You lose", "English human loss")
	assert_eq(BattleText.end_title(1, -1), "Red Team wins!", "English team win")
	assert_eq(BattleText.end_title(BattleState.DRAW, -1), "Draw", "English draw")
	I18n.english = _was_english


func test_event_lines_in_both_languages() -> void:
	var plan := SeatPlan.build(SeatPlan.defaults(4242))
	var r := MatchRunner.new(plan)
	r.start()
	var st := r.st
	var s0: BattleState.Squad = st.squads[0]
	var s1: BattleState.Squad = null
	for s in st.squads:
		if s.side != s0.side:
			s1 = s
			break
	var evs: Array = [
		Events.make(Events.Id.TURN, {"team": 1, "round": 2}),
		Events.make(Events.Id.PHASE, {"ph": "shoot"}),
		Events.make(Events.Id.PHASE, {"ph": "cmd"}),
		Events.make(Events.Id.ATTACK_STAGE, {"p": "%s>%s" % [s0.id, s1.id], "stage": "hit", "dice": [6, 5, 3, 1]}),
		Events.make(Events.Id.ATTACK_STAGE, {"p": "%s>%s" % [s0.id, s1.id], "stage": "wound", "dice": [4, 2]}),
		Events.make(Events.Id.ATTACK_STAGE, {"p": "%s>%s" % [s0.id, s1.id], "stage": "save", "dice": [1]}),
		Events.make(Events.Id.DEATH, {"uid": "x"}),
		Events.make(Events.Id.DEATH, {"uid": "y"}),
		Events.make(Events.Id.CHARGE, {"sid": s0.id, "tid": s1.id}),
		Events.make(Events.Id.SHOCK, {"sid": s1.id, "pass": false}),
		Events.make(Events.Id.MOVE_STEP, {"uid": "x", "gx": 0, "gz": 0}),
		Events.make(Events.Id.LOG_LINE, {"key": "nop", "args": []}),
		Events.make(Events.Id.OVER, {"result": 1, "why": "over_last"}),
	]
	I18n.english = false
	var th := BattleText.lines(evs, st)
	var a := DatasheetText.name_of(GameData.ty(s0.k))
	var t := DatasheetText.name_of(GameData.ty(s1.k))
	assert_eq(th, PackedStringArray(["รอบ 2 · ตาของทีมแดง", "— เฟสยิง —", "%s → %s · ทอยโดน: 6 5 3 1" % [a, t],
		"ทอยเจาะ: 4 2", "ทอยเซฟ: 1", "%s บุกเข้าใส่ %s" % [a, t], "%s เสียขวัญ" % t, "จบเกม — เหลือทีมเดียว", "ล้ม 2 ตัว"]),
		"Thai lines: turn, phase (not cmd), dice as digits, charge, shock, over, deaths summed; unknown events hidden")
	I18n.english = true
	var en := BattleText.lines(evs, st)
	var left := []
	for line in en:
		if thai_re.search(line) != null:
			left.append(line)
	assert_eq(left, [], "English lines have no Thai")
	assert_eq(en[0], "Round 2 · Red Team's turn", "English turn line")
	assert_eq(en[8], "2 fell", "English deaths line")
	assert_eq(BattleText.dice_text(range(1, 16)), "1 2 3 4 5 6 7 8 9 10 11 12 …", "long dice lists are cut at 12")
	var label := BattleText.turn_label(st)
	assert_true(label.begins_with("Round 1 / 5 · Blue Team's turn"), "English turn label (%s)" % label)
	I18n.english = false
	assert_true(BattleText.turn_label(st).begins_with("รอบ 1 / 5 · ตาของทีมน้ำเงิน · เฟส"), "Thai turn label (%s)" % BattleText.turn_label(st))
	I18n.english = _was_english


func test_seat_plan_errors_in_english() -> void:
	I18n.english = true
	var c := SeatPlan.defaults(1)
	var left := []
	for code in SeatPlan.ERROR_TEXT:
		var msg := SeatPlan.error_text(code, c)
		if thai_re.search(msg) != null:
			left.append(code + ": " + msg)
	I18n.english = _was_english
	assert_eq(left, [], "every setup error has English text")
