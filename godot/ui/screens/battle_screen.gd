extends Control
## หน้ารบกับบอท (LOBBY_SPEC §4.3): โต๊ะ 3 มิติ (โหนดกลุ่ม table_view หรือโต๊ะของตัวเองตอนเทสเดี่ยว) + HUD บาง ๆ
## ทุกการเปลี่ยนกติกาผ่าน MatchRunner (Battle.apply / bot_step / flush) · หน้าจอไม่คิดกติกาและไม่แตะ BattleState
## จังหวะ: Timer เรียก runner.step() (ปกติ 0.3 วิ เร็ว 0.08 วิ ทันที = วนจนใช้ 12 มิลลิวิของเฟรม) ไม่มี _process
## รอคน (wait_human) = หยุด Timer ไม่มีงานต่อเฟรมเลยทุกระดับ · แตะโต๊ะ (TableView.picked): เลือกหมู่ เดิน ยิง บุก
## จบเกม: แผงผล (ชนะ/แพ้/เสมอ เหตุผล แต้มชัย รอบ) กลับล็อบบี้ (pop) เล่นอีกครั้ง (seed ใหม่) ดูสนาม

const TABLE_SCENE := "res://scenes/battle_table.tscn"
const SPEEDS := {"normal": 0.3, "fast": 0.08, "instant": 0.01}
const INSTANT_BUDGET_USEC := 12000
const LOG_LINES := 8
const LOG_LINES_TOUCH := 6            # มือถือ: ตัวใหญ่ขึ้น บรรทัดน้อยลง (ผลลูกเต๋าอ่านออก)
const LOG_FONT := 15
const LOG_FONT_TOUCH := 18
const TOAST_SECONDS := 2.5
const T_QUIT := "‹ ออก"
const T_AUTO := "ให้บอทเล่นแทน"
const T_FAST := "เร็ว"
const T_NORMAL := "ปกติ"
const T_ADVANCE := "วิ่ง"
const T_STAY := "อยู่กับที่"
const T_FALL_BACK := "ถอย"
const T_SKIP := "ข้าม"
const T_DONE := "จบเฟส ›"
const T_HINT_MOVE := "แตะหน่วยของคุณ แล้วแตะพื้นเพื่อเดิน"
const T_HINT_SHOOT := "แตะหน่วยของคุณ แล้วแตะศัตรูเพื่อยิง"
const T_HINT_CHARGE := "แตะหน่วยของคุณ แล้วแตะศัตรูเพื่อบุก"
const T_HINT_FB := "ถอย: แตะพื้นที่จะถอยไป"
const T_HINT_BOTS := "บอทกำลังเล่น…"
const T_HINT_AUTO := "บอทเล่นแทนคุณอยู่"
const T_HINT_WATCH := "ดูบอทเล่นกันเอง"
const T_CARD := "เหลือ {n}/{n0} ตัว · แผล {hp}"
const T_VP := "{vp}"
const T_LEAVE := "ออกจากการรบ? เกมนี้จะไม่ถูกบันทึก"
const T_LEAVE_YES := "ออกจากการรบ"
const T_LEAVE_NO := "เล่นต่อ"
const T_LOBBY := "กลับล็อบบี้"
const T_AGAIN := "เล่นอีกครั้ง"
const T_LOOK := "ดูสนาม"
const T_RESULT := "ผลการรบ"
const T_STATS_ROUNDS := "เล่นไป {r} รอบ"
const T_STATS_VP := "{team} · แต้มชัย {vp}"
const T_STUCK := "เกมติด — กดกลับล็อบบี้"

var runner: MatchRunner
var plan: Dictionary = {}
var table: Node3D
var speed := "normal"

var _own_table := false
var _timer: Timer
var _toast_timer: Timer
var _waiting := false
var _sel: BattleState.Squad = null
var _fall_back := false
var _log := PackedStringArray()
var _log_steps: Array = []          # เหตุการณ์ทีละก้าวที่ขึ้นบันทึก (วาดใหม่เมื่อเปลี่ยนภาษา)
var _log_english := false
var _ended := false
var _stuck := false
var _log_max := LOG_LINES
var _to_own: Array[Node] = []

var _turn_label: Label
var _vp_box: HBoxContainer
var _card: PanelContainer
var _card_name: Label
var _card_info: Label
var _hint: Label
var _log_text: Label
var _toast: PanelContainer
var _toast_text: Label
var _actions: HBoxContainer
var _advance: Button
var _stay: Button
var _fb: Button
var _skip: Button
var _done: Button
var _auto: Button
var _speed: Button
var _quit: Button
var _end_panel: PanelContainer
var _end_title: Label
var _end_reason: Label
var _end_stats: Label
var _lobby: Button
var _again: Button
var _look: Button
var _result: Button
var _leave: PanelContainer
var _log_panel: PanelContainer


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_timer = Timer.new()
	_timer.name = "StepTimer"
	_timer.one_shot = false
	_timer.timeout.connect(_on_timer)
	add_child(_timer)
	_toast_timer = Timer.new()
	_toast_timer.one_shot = true
	_toast_timer.timeout.connect(func() -> void: _toast.visible = false)
	add_child(_toast_timer)
	_build()
	visibility_changed.connect(_on_visibility)


func _exit_tree() -> void:
	_timer.stop()
	if table != null and is_instance_valid(table):
		if table.has_signal(&"picked") and table.is_connected(&"picked", _on_picked):
			table.disconnect(&"picked", _on_picked)
		if table.has_method("end_battle"):
			table.call("end_battle")
		if not _own_table:
			table.visible = false
			table.process_mode = Node.PROCESS_MODE_DISABLED


# ---- API ----

## เริ่มนัดจากแผน (SeatPlan.build): ตัวคุมเกม เริ่มนัด วาดสนามและฟิกเกอร์จากกติกา แล้วเริ่ม Timer
func begin(p: Dictionary) -> void:
	plan = p
	_ensure_table()
	runner = MatchRunner.new(plan)
	var evs := runner.start()
	runner.take_events()
	_ended = false
	_stuck = false
	_waiting = false
	_sel = null
	_fall_back = false
	_log = PackedStringArray()
	_log_steps = []
	_log_text.text = ""
	_end_panel.visible = false
	_result.visible = false
	_leave.visible = false
	_auto.set_pressed_no_signal(false)
	_show_table()
	table.call("build_battle", runner.st)
	_add_log(evs)
	_refresh()
	_set_speed_timer()
	_timer.start()


## normal | fast | instant
func set_speed(s: String) -> void:
	if not SPEEDS.has(s):
		return
	speed = s
	_speed.set_pressed_no_signal(s != "normal")
	_speed.text = I18n.t(T_NORMAL if s == "normal" else T_FAST)
	_set_speed_timer()


func is_over() -> bool:
	return runner != null and runner.is_over()


func is_waiting() -> bool:
	return _waiting


func selected() -> BattleState.Squad:
	return _sel


## ย้อนกลับ/Esc: แผงผลอยู่ = กลับห้องโถง · กล่องถามเปิด = ปิด · กำลังเล่น = ถามก่อนออก
func handle_back() -> bool:
	if _ended or _stuck:
		return false
	if _leave.visible:
		_close_leave()
		return true
	_open_leave()
	return true


func refresh() -> void:
	_refresh()


# ---- จังหวะเกม ----

func _set_speed_timer() -> void:
	if _timer != null:
		_timer.wait_time = float(SPEEDS[speed])


func _on_timer() -> void:
	if runner == null or _leave.visible:
		return
	var t0 := Time.get_ticks_usec()
	var grew := false
	var stuck_now := false
	while true:
		var n0 := runner.acts().size()
		var r := runner.step()
		_add_log(r["events"])
		if runner.acts().size() != n0:
			grew = true
		var state := str(r["state"])
		if state == "wait_human":
			_timer.stop()
			_waiting = true
			_auto_select()
			break
		if state == "over":
			_timer.stop()
			break
		if state == "stuck":
			_timer.stop()
			_stuck = true
			stuck_now = true
			break
		if speed != "instant" or Time.get_ticks_usec() - t0 >= INSTANT_BUDGET_USEC:
			break
	if stuck_now:
		_show_stuck()
	if grew:
		table.call("sync_battle", runner.st)
	if runner.is_over():
		_show_end()
	_refresh()


## หลังคำสั่งของคุณ: วาดใหม่ แล้วเดินปั๊มต่อ (ลูกเต๋าที่ค้าง เพื่อนบอท) จนรอคุณอีกหรือมีอะไรให้ดู
func _after_human() -> void:
	_waiting = false
	var r := runner.step()
	_add_log(r["events"])
	table.call("sync_battle", runner.st)
	var state := str(r["state"])
	if state == "wait_human":
		_waiting = true
		_auto_select()
	elif state == "over":
		_show_end()
	else:
		_timer.start()
	_refresh()


# ---- แตะโต๊ะ ----

func _on_picked(fig: int, ground: Vector3) -> void:
	if runner == null or not _waiting or _ended or _leave.visible:
		return
	var st := runner.st
	if fig >= 0 and _sel != null and st.phase == BattleState.PH_MOVE:
		# เลือกหมู่ไว้แล้วในเฟสเดิน: แตะพื้นใกล้ ๆ ฟิกเกอร์ (ไม่ใช่ที่ตัวมัน) คือเดิน ไม่ใช่เลือกใหม่
		var f: Object = (table.get("figures").get("figures") as Array)[fig]
		var fp: Vector3 = f.get("pos")
		if Vector2(fp.x - ground.x, fp.z - ground.z).length() > float(f.get("radius")) + 0.4:
			fig = -1
	var uid := str(table.call("fig_unit", fig)) if fig >= 0 else ""
	var u := st.unit(uid) if uid != "" else null
	var s: BattleState.Squad = st.squad(u.sq) if u != null else null
	if s != null and s.pl == runner.human:
		if runner.can_select(s):
			_select(s)
			_refresh()
			return
		if _sel == null or st.phase != BattleState.PH_MOVE:
			_say(BattleText.why(runner.select_why(s), [], _ctx()))
			return
	if _sel == null:
		_say(BattleText.why("select_first"))
		return
	var why := ""
	match st.phase:
		BattleState.PH_MOVE:
			if not ground.is_finite():
				return
			why = runner.move(_sel, roundi(ground.x * 1000.0), roundi(ground.z * 1000.0), _fall_back)
		BattleState.PH_SHOOT:
			if s == null or s.side == _sel.side:
				_say(BattleText.why("own_side" if s != null else "select_first", [], "shoot"))
				return
			why = runner.shoot(_sel, s)
		BattleState.PH_CHARGE:
			if s == null or s.side == _sel.side:
				_say(BattleText.why("enemies_only", [], "charge"))
				return
			why = runner.charge(_sel, s)
		_:
			return
	if why != "":
		_say(BattleText.why(why, runner.why_args, _ctx()))
		return
	_fall_back = false
	_after_human()


func _ctx() -> String:
	match runner.st.phase:
		BattleState.PH_MOVE:
			return "move"
		BattleState.PH_SHOOT:
			return "shoot"
		BattleState.PH_CHARGE:
			return "charge"
	return "other"


func _select(s: BattleState.Squad) -> void:
	_sel = s
	_fall_back = false
	var ids := PackedStringArray()
	if s != null:
		for m in s.models:
			ids.append(m.id)
	table.call("show_selection", ids)
	if s != null and runner.st.phase == BattleState.PH_MOVE and not BtSquads.is_engaged(runner.st, s):
		var c := BtSquads.center(s)
		table.call("show_dest", Vector3(c[0] / 1000.0, 0.0, c[1] / 1000.0), BtMoves.move_range(s) / 1000.0)
	else:
		table.call("show_dest", Vector3.INF)


## เริ่มเฟสของคุณ: เลือกหมู่แรกที่ยังสั่งได้ให้เลย (แตะหมู่อื่นเพื่อเปลี่ยน)
func _auto_select() -> void:
	if runner == null or runner.auto_human:
		return
	if _sel != null and runner.can_select(_sel):
		_select(_sel)
		return
	var mine := runner.selectable()
	_select(mine[0] if not mine.is_empty() else null)


# ---- ปุ่ม ----

func _on_advance() -> void:
	if not _waiting or _sel == null:
		return
	var why := runner.advance(_sel)
	if why != "":
		_say(BattleText.why(why, runner.why_args, "move"))
		return
	_after_human()


func _on_stay() -> void:
	if not _waiting or _sel == null:
		return
	var why := runner.stay(_sel)
	if why != "":
		_say(BattleText.why(why, runner.why_args, "move"))
		return
	_after_human()


func _on_fall_back() -> void:
	if not _waiting or _sel == null:
		return
	_fall_back = not _fall_back
	_refresh()


func _on_skip() -> void:
	if not _waiting or _sel == null:
		return
	var why := runner.skip(_sel)
	if why != "":
		_say(BattleText.why(why, runner.why_args, _ctx()))
		return
	_after_human()


func _on_done() -> void:
	if not _waiting:
		return
	var why := runner.end_phase()
	if why != "":
		_say(BattleText.why(why, runner.why_args, _ctx()))
		return
	_select(null)
	_after_human()


func _on_auto(on: bool) -> void:
	if runner == null:
		return
	runner.auto_human = on
	if on:
		_select(null)
		if _waiting and not _ended:
			_waiting = false
			_timer.start()
	_refresh()


func _on_speed(on: bool) -> void:
	set_speed("fast" if on else "normal")


func _open_leave() -> void:
	_leave.visible = true
	_timer.stop()


func _close_leave() -> void:
	_leave.visible = false
	if runner != null and not _waiting and not _ended and not _stuck:
		_timer.start()


func _on_lobby() -> void:
	_timer.stop()
	App.pop()


func _on_again() -> void:
	var c: Dictionary = plan.get("choice", {})
	if c.is_empty():
		return
	var seed_v := int(c.get("seed", 1)) % 99999 + 1
	var p := SeatPlan.build(SeatPlan.with_seed(c, seed_v))
	if (p["errors"] as PackedStringArray).is_empty():
		begin(p)


func _on_look() -> void:
	_end_panel.visible = false
	_result.visible = true
	_refresh()


func _on_result() -> void:
	_end_panel.visible = true
	_result.visible = false
	_refresh()


# ---- โต๊ะ ----

func _ensure_table() -> void:
	if table != null and is_instance_valid(table):
		return
	table = get_tree().get_first_node_in_group("table_view") as Node3D
	if table == null:
		var ps := load(TABLE_SCENE) as PackedScene
		table = ps.instantiate() as Node3D
		table.set("auto_build", false)
		add_child(table)
		_own_table = true
	if not table.is_connected(&"picked", _on_picked):
		table.connect(&"picked", _on_picked)


func _show_table() -> void:
	if table == null:
		return
	table.visible = true
	table.process_mode = Node.PROCESS_MODE_INHERIT
	var app := get_node_or_null(^"/root/App")
	if app != null:
		table.call("apply_level", str(app.get("gfx")))
	var rig: Node = table.get("camera_rig")
	if rig != null:
		(rig.get("camera") as Camera3D).make_current()


func _on_visibility() -> void:
	if runner == null or table == null or not is_instance_valid(table):
		return
	if is_visible_in_tree():
		_show_table()
		table.call("build_battle", runner.st)
		_select(_sel if _sel != null and runner.can_select(_sel) else null)
		_refresh()
		if not _waiting and not _ended and not _stuck and not _leave.visible:
			_timer.start()
	else:
		_timer.stop()
		table.call("end_battle")
		table.visible = false
		table.process_mode = Node.PROCESS_MODE_DISABLED


# ---- HUD ----

func _show_end() -> void:
	_ended = true
	_waiting = false
	_timer.stop()
	_select(null)
	_end_texts()
	_end_panel.visible = true
	_result.visible = false
	_leave.visible = false


## เกมไปต่อไม่ได้ (ไม่ควรเกิด): แผงผลพร้อมปุ่มกลับล็อบบี้ หัวข้อบอกว่าเกมติด
func _show_stuck() -> void:
	_waiting = false
	_timer.stop()
	_select(null)
	_end_texts()
	_end_panel.visible = true
	_result.visible = false
	_leave.visible = false


func _end_texts() -> void:
	var st := runner.st
	if _stuck and not runner.is_over():
		_end_title.text = I18n.t(T_STUCK)
		_end_reason.text = ""
	else:
		_end_title.text = BattleText.end_title(runner.winner(), runner.human_team())
		_end_reason.text = BattleText.reason(runner.over_why())
	var parts := PackedStringArray([I18n.t(T_STATS_ROUNDS).format({"r": mini(st.round_no, st.max_round())})])
	if st.goal == BattleState.GOAL_OBJ:
		for t in st.teams:
			parts.append(I18n.t(T_STATS_VP).format({"team": BattleText.team_name(t), "vp": int(st.vp[t]) if t < st.vp.size() else 0}))
	_end_stats.text = "\n".join(parts)


func _say(msg: String) -> void:
	if msg == "":
		return
	_toast_text.text = msg
	_toast.visible = true
	_toast_timer.start(TOAST_SECONDS)


## เหตุการณ์ของหนึ่งก้าวเข้าบันทึก (เก็บเหตุการณ์ไว้ วาดเป็นข้อความตามภาษาปัจจุบัน 8 บรรทัดล่าสุด)
func _add_log(evs: Array) -> void:
	if runner == null or evs.is_empty():
		return
	var lines := BattleText.lines(evs, runner.st)
	if lines.is_empty():
		return
	_log_steps.append(evs)
	_log.append_array(lines)
	if _log.size() > _log_max:
		_log = _log.slice(_log.size() - _log_max)
	while _log_steps.size() > _log_max:
		_log_steps.pop_front()
	_log_english = I18n.english
	_log_text.text = "\n".join(_log)


## วาดบันทึกใหม่ทั้งหมดในภาษาปัจจุบัน
func _redo_log() -> void:
	_log = PackedStringArray()
	for evs in _log_steps:
		_log.append_array(BattleText.lines(evs, runner.st))
	if _log.size() > _log_max:
		_log = _log.slice(_log.size() - _log_max)
	_log_english = I18n.english
	_log_text.text = "\n".join(_log)


func _refresh() -> void:
	if _turn_label == null:
		return
	for n in _text_nodes(self):
		n.set("text", I18n.t(str(n.get_meta("th"))))
	_speed.text = I18n.t(T_NORMAL if speed == "normal" else T_FAST)
	if runner == null:
		return
	var st := runner.st
	if _log_english != I18n.english:
		_redo_log()
	if _ended or _stuck:
		_end_texts()
	_turn_label.text = BattleText.turn_label(st)
	# แต้มชัยต่อทีม (ยึดจุด)
	var obj := st.goal == BattleState.GOAL_OBJ
	_vp_box.visible = obj
	if obj:
		while _vp_box.get_child_count() < st.teams:
			var chip := HBoxContainer.new()
			chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
			chip.add_theme_constant_override(&"separation", 4)
			var sw := ColorRect.new()
			sw.custom_minimum_size = Vector2(14, 28)
			sw.mouse_filter = Control.MOUSE_FILTER_IGNORE
			chip.add_child(sw)
			var l := Label.new()
			CandleStyle.text(l, 20)
			chip.add_child(l)
			_vp_box.add_child(chip)
		for t in _vp_box.get_child_count():
			var chip := _vp_box.get_child(t) as Control
			chip.visible = t < st.teams
			if t < st.teams:
				(chip.get_child(0) as ColorRect).color = table.call("team_colour", t)
				(chip.get_child(1) as Label).text = I18n.t(T_VP).format({"vp": int(st.vp[t]) if t < st.vp.size() else 0})
	var mine := runner.is_human_turn() and _waiting and not runner.auto_human
	# การ์ดหมู่ที่เลือก
	_card.visible = _sel != null
	if _sel != null:
		var hp := 0
		for m in _sel.models:
			hp += m.hp
		_card_name.text = DatasheetText.name_of(GameData.ty(_sel.k))
		_card_info.text = I18n.t(T_CARD).format({"n": _sel.models.size(), "n0": _sel.n0, "hp": hp})
	# คำแนะนำ
	var hint := ""
	if runner.human < 0:
		hint = T_HINT_WATCH
	elif runner.auto_human:
		hint = T_HINT_AUTO
	elif mine:
		match st.phase:
			BattleState.PH_MOVE:
				hint = T_HINT_FB if _fall_back else T_HINT_MOVE
			BattleState.PH_SHOOT:
				hint = T_HINT_SHOOT
			BattleState.PH_CHARGE:
				hint = T_HINT_CHARGE
	elif not st.over:
		hint = T_HINT_BOTS
	_hint.text = I18n.t(hint) if hint != "" else ""
	_hint.visible = hint != "" and not _ended
	# ปุ่มคำสั่ง
	var move := mine and st.phase == BattleState.PH_MOVE
	var engaged := _sel != null and BtSquads.is_engaged(st, _sel)
	_advance.visible = move
	_advance.disabled = _sel == null or _sel.adv or engaged
	_stay.visible = move
	_stay.disabled = _sel == null
	_fb.visible = move and engaged
	_fb.set_pressed_no_signal(_fall_back)
	_skip.visible = mine and (st.phase == BattleState.PH_SHOOT or st.phase == BattleState.PH_CHARGE)
	_skip.disabled = _sel == null
	_log_panel.visible = not _end_panel.visible   # แผงผลบังบันทึกพอดี: ซ่อนไว้ ดูสนามแล้วโชว์อีก
	_done.visible = runner.human >= 0 and not _ended
	_done.disabled = not (mine and st.pend.is_empty())
	_auto.visible = runner.human >= 0 and not _ended
	_actions.visible = not _ended


static func _text_nodes(n: Node) -> Array[Node]:
	var out: Array[Node] = []
	if n.has_meta("th"):
		out.append(n)
	for c in n.get_children():
		out.append_array(_text_nodes(c))
	return out


# ---- สร้างหน้า ----

func _build() -> void:
	var margin := MarginContainer.new()
	margin.name = "Margin"
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(margin)
	CandleStyle.safe_margins(margin)
	var col := VBoxContainer.new()
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_theme_constant_override(&"separation", 8)
	margin.add_child(col)
	# แถบบน
	var top := PanelContainer.new()
	top.name = "TopBar"
	CandleStyle.panel(top)
	_tight(top, 6.0)
	col.add_child(top)
	var tb := HBoxContainer.new()
	tb.add_theme_constant_override(&"separation", 10)
	top.add_child(tb)
	_quit = _button("QuitButton", T_QUIT)
	_quit.custom_minimum_size.x = 110.0
	_quit.pressed.connect(_open_leave)
	tb.add_child(_quit)
	_turn_label = Label.new()
	_turn_label.name = "TurnLabel"
	_turn_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_turn_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_turn_label.clip_text = true
	_turn_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	CandleStyle.title(_turn_label, 22)
	tb.add_child(_turn_label)
	_own(_turn_label)
	_vp_box = HBoxContainer.new()
	_vp_box.name = "VpBox"
	_vp_box.add_theme_constant_override(&"separation", 12)
	tb.add_child(_vp_box)
	_own(_vp_box)
	_speed = _button("SpeedButton", T_NORMAL)
	_speed.toggle_mode = true
	_speed.custom_minimum_size.x = 96.0
	_speed.toggled.connect(_on_speed)
	tb.add_child(_speed)
	_auto = _button("AutoButton", T_AUTO)
	_auto.toggle_mode = true
	_auto.toggled.connect(_on_auto)
	tb.add_child(_auto)
	# กลาง: ว่าง (แตะโต๊ะได้) + บันทึกด้านขวา
	var mid := HBoxContainer.new()
	mid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(mid)
	var gap := Control.new()
	gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mid.add_child(gap)
	var log_col := VBoxContainer.new()
	log_col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mid.add_child(log_col)
	var log_panel := PanelContainer.new()
	_log_panel = log_panel
	log_panel.name = "LogPanel"
	CandleStyle.panel(log_panel)
	_tight(log_panel, 8.0)
	log_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	log_panel.self_modulate = Color(1, 1, 1, 0.85)
	log_col.add_child(log_panel)
	var touch := App.touch_active()
	_log_max = LOG_LINES_TOUCH if touch else LOG_LINES
	var log_font := LOG_FONT_TOUCH if touch else LOG_FONT
	_log_text = Label.new()
	_log_text.name = "LogText"
	_log_text.custom_minimum_size = Vector2(420 if touch else 380, _log_max * (log_font + 6))
	_log_text.clip_text = true
	_log_text.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS   # บรรทัดยาว (ลูกเต๋าเยอะ) ตัดท้ายเป็น … ไม่ล้นแผง
	_log_text.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	_log_text.max_lines_visible = _log_max
	CandleStyle.text(_log_text, log_font)
	log_panel.add_child(_log_text)
	_own(_log_text)
	# ล่าง: การ์ด + คำแนะนำ ซ้าย, ปุ่มคำสั่ง ขวา
	var bottom := HBoxContainer.new()
	bottom.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bottom.add_theme_constant_override(&"separation", 10)
	col.add_child(bottom)
	var info := VBoxContainer.new()
	info.mouse_filter = Control.MOUSE_FILTER_IGNORE
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.alignment = BoxContainer.ALIGNMENT_END
	bottom.add_child(info)
	_card = PanelContainer.new()
	_card.name = "SquadCard"
	CandleStyle.panel(_card)
	_tight(_card, 8.0)
	_card.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	info.add_child(_card)
	_own(_card)
	var cv := VBoxContainer.new()
	cv.add_theme_constant_override(&"separation", 2)
	_card.add_child(cv)
	_card_name = Label.new()
	CandleStyle.title(_card_name, 20)
	cv.add_child(_card_name)
	_card_info = Label.new()
	CandleStyle.text(_card_info, 17)
	cv.add_child(_card_info)
	_hint = Label.new()
	_hint.name = "Hint"
	CandleStyle.text(_hint, 18)
	_hint.add_theme_color_override(&"font_outline_color", Color(0, 0, 0, 0.9))
	_hint.add_theme_constant_override(&"outline_size", 6)
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.add_child(_hint)
	_own(_hint)
	_actions = HBoxContainer.new()
	_actions.name = "Actions"
	_actions.alignment = BoxContainer.ALIGNMENT_END
	_actions.add_theme_constant_override(&"separation", 8)
	_actions.size_flags_vertical = Control.SIZE_SHRINK_END
	bottom.add_child(_actions)
	_own(_actions)
	_advance = _button("AdvanceButton", T_ADVANCE)
	_advance.pressed.connect(_on_advance)
	_stay = _button("StayButton", T_STAY)
	_stay.pressed.connect(_on_stay)
	_fb = _button("FallBackButton", T_FALL_BACK)
	_fb.toggle_mode = true
	_fb.pressed.connect(_on_fall_back)
	_skip = _button("SkipButton", T_SKIP)
	_skip.pressed.connect(_on_skip)
	_done = _button("DoneButton", T_DONE, true)
	_done.custom_minimum_size.x = 150.0
	_done.pressed.connect(_on_done)
	for b in [_advance, _stay, _fb, _skip, _done]:
		_actions.add_child(b)
	# ป้ายเตือน (เหตุผลที่สั่งไม่ได้)
	_toast = PanelContainer.new()
	_toast.name = "Toast"
	CandleStyle.panel(_toast)
	_toast.visible = false
	_toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toast.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_toast.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_toast.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_toast.offset_top = -170.0
	_toast.offset_bottom = -110.0
	add_child(_toast)
	_own(_toast)
	_toast_text = Label.new()
	CandleStyle.text(_toast_text, 20)
	_toast_text.add_theme_color_override(&"font_color", CandleStyle.GOLD)
	_toast.add_child(_toast_text)
	# แผงจบเกม
	_end_panel = _centre_panel("EndPanel")
	var ev := VBoxContainer.new()
	ev.add_theme_constant_override(&"separation", 10)
	ev.alignment = BoxContainer.ALIGNMENT_CENTER
	_end_panel.add_child(ev)
	_end_title = Label.new()
	_end_title.name = "EndTitle"
	_end_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	CandleStyle.title(_end_title, 44)
	ev.add_child(_end_title)
	_own(_end_title)
	_end_reason = Label.new()
	_end_reason.name = "EndReason"
	_end_reason.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	CandleStyle.text(_end_reason, 22)
	ev.add_child(_end_reason)
	_own(_end_reason)
	_end_stats = Label.new()
	_end_stats.name = "EndStats"
	_end_stats.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	CandleStyle.text(_end_stats, 18, true)
	ev.add_child(_end_stats)
	_own(_end_stats)
	var eb := HBoxContainer.new()
	eb.alignment = BoxContainer.ALIGNMENT_CENTER
	eb.add_theme_constant_override(&"separation", 10)
	ev.add_child(eb)
	_lobby = _button("LobbyButton", T_LOBBY, true)
	_lobby.pressed.connect(_on_lobby)
	_again = _button("AgainButton", T_AGAIN)
	_again.pressed.connect(_on_again)
	_look = _button("LookButton", T_LOOK)
	_look.pressed.connect(_on_look)
	for b in [_lobby, _again, _look]:
		(b as Button).custom_minimum_size.y = 56.0
		eb.add_child(b)
	_end_panel.visible = false
	_result = _button("ResultButton", T_RESULT)
	_result.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_result.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_result.offset_top = 84.0
	_result.offset_bottom = 132.0
	_result.pressed.connect(_on_result)
	_result.visible = false
	add_child(_result)
	# กล่องถามก่อนออก
	_leave = _centre_panel("LeaveConfirm")
	var lv := VBoxContainer.new()
	lv.add_theme_constant_override(&"separation", 14)
	_leave.add_child(lv)
	var lt := Label.new()
	lt.set_meta("th", T_LEAVE)
	lt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	CandleStyle.text(lt, 22)
	lv.add_child(lt)
	var lb := HBoxContainer.new()
	lb.alignment = BoxContainer.ALIGNMENT_CENTER
	lb.add_theme_constant_override(&"separation", 10)
	lv.add_child(lb)
	var yes := _button("LeaveYes", T_LEAVE_YES)
	yes.pressed.connect(_on_lobby)
	var no := _button("LeaveNo", T_LEAVE_NO, true)
	no.pressed.connect(_close_leave)
	lb.add_child(yes)
	lb.add_child(no)
	_leave.visible = false
	for n in _to_own:
		n.unique_name_in_owner = true
		n.owner = self
	_to_own.clear()
	_refresh()


func _centre_panel(node_name: String) -> PanelContainer:
	var p := PanelContainer.new()
	p.name = node_name
	CandleStyle.panel(p)
	p.set_anchors_preset(Control.PRESET_CENTER)
	p.grow_horizontal = Control.GROW_DIRECTION_BOTH
	p.grow_vertical = Control.GROW_DIRECTION_BOTH
	p.custom_minimum_size = Vector2(560, 0)
	var sb := p.get_theme_stylebox(&"panel")
	if sb is StyleBoxFlat:
		var c := (sb as StyleBoxFlat).duplicate() as StyleBoxFlat
		c.bg_color = Color(CandleStyle.PANEL, 0.97)
		c.set_content_margin_all(24.0)
		p.add_theme_stylebox_override(&"panel", c)
	add_child(p)
	_own(p)
	return p


func _tight(p: PanelContainer, m: float) -> void:
	var sb := p.get_theme_stylebox(&"panel")
	if sb is StyleBoxFlat:
		var c := (sb as StyleBoxFlat).duplicate() as StyleBoxFlat
		c.set_content_margin_all(m)
		p.add_theme_stylebox_override(&"panel", c)


func _button(node_name: String, th: String, primary := false) -> Button:
	var b := Button.new()
	b.name = node_name
	b.set_meta("th", th)
	b.text = th
	CandleStyle.button(b, primary)
	b.custom_minimum_size.y = 48.0
	b.add_theme_font_size_override(&"font_size", 18)
	for state in [&"normal", &"hover", &"pressed", &"hover_pressed", &"disabled"]:
		var sb := b.get_theme_stylebox(state)
		if sb is StyleBoxFlat:
			var c := (sb as StyleBoxFlat).duplicate() as StyleBoxFlat
			c.content_margin_left = 12.0
			c.content_margin_right = 12.0
			c.content_margin_top = 4.0
			c.content_margin_bottom = 4.0
			if b.toggle_mode or state == &"pressed" or state == &"hover_pressed":
				if state == &"pressed" or state == &"hover_pressed":
					c.bg_color = Color("7a4a1c")
			b.add_theme_stylebox_override(state, c)
	_own(b)
	return b


func _own(n: Node) -> void:
	_to_own.append(n)
