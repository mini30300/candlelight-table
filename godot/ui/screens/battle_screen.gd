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
## ออนไลน์ (NET_SPEC §5.3): รอเพื่อน ผู้ชม ที่นั่งหลุด/กลับ เกมไม่ตรงกับเจ้าห้อง ออกจากการรบ จบเกมโดยเจ้าห้อง
const T_WAIT_REMOTE := "รอ {name}…"
const T_HOST := "เจ้าห้อง"
const T_SPECTATOR := "ดูอยู่ (ไม่มีที่นั่ง)"
const T_SEAT_GONE := "บอทเล่นแทน {name} (หลุดจากห้อง)"
const T_SEAT_LEFT := "บอทเล่นแทน {name} จนจบเกมนี้"
const T_SEAT_BACK := "{name} กลับมาแล้ว"
const T_STALE := "ทำไม่ได้ตอนนี้ — เกมขยับไปแล้ว"
const T_LEAVE_CLIENT := "ออกจากการรบ? บอทจะเล่นแทนคุณจนจบเกมนี้"
const T_LEAVE_HOST := "ออกจากการรบ? เกมนี้จะจบสำหรับทุกคน"
const T_HOST_LEFT := "เจ้าห้องออกจากการรบ เกมนี้จบแล้ว"
const T_WAIT_AGAIN := "รอเจ้าห้องเริ่มเกมใหม่"
const T_DESYNC := "เกมไม่ตรงกับเจ้าห้อง — กำลังโหลดเกมใหม่จากเจ้าห้อง…"
const T_REPAIRED := "ซ่อมแล้ว เกมตรงกับเจ้าห้องแล้ว"
const T_DESYNC_FINAL := "เกมไม่ตรงกับเจ้าห้อง — บันทึกไว้ในล็อกแล้ว ต้องออกจากเกมนี้"
const T_DESYNC_HOST := "เครื่องของ {name} ไม่ตรงกัน — กำลังส่งเกมให้ใหม่"
const T_LOST := "การเชื่อมต่อหลุด — เกมนี้จบสำหรับเครื่องนี้"
const T_MINE := "บอทเล่นแทนคุณอยู่ตอนนี้"
const T_RECONNECTING := "การเชื่อมต่อหลุด — กำลังต่อใหม่…"   # = OnlineText.REASONS.reconnecting
const NET_LINK := ^"/root/Net/NetBattleLink"
const REPAIRED_SECONDS := 3.0
const FX_HOLD_MS := 3000              # ภาพของก้าวหนึ่งรอได้นานสุดเท่านี้ ก่อนก้าวต่อ (ความเร็วปกติ)
const FX_FAST := 2.2                  # ความเร็วเร็ว: ภาพเล่นเร็วขึ้น ไม่รอ

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
var _leave_text: Label
var _desync: PanelContainer
var _desync_text: Label
var _desync_btn: Button
var _desync_timer: Timer
var _remote := false               # รอเพื่อน/เจ้าห้อง (wait_remote): Timer หยุด ปั๊มต่อเมื่อ runner.changed
var _host_end := false             # เจ้าห้องจบเกม (END)
var _wait_again: Label
var _fx: BattleFx                   # ท่าโจมตี/เอฟเฟกต์ของหน้าเดิมบนโต๊ะ (ภาพล้วน)
var _fx_fed_ms := -100000


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
	_desync_timer = Timer.new()
	_desync_timer.one_shot = true
	_desync_timer.timeout.connect(func() -> void: _desync.visible = false)
	add_child(_desync_timer)
	_build()
	visibility_changed.connect(_on_visibility)


func _exit_tree() -> void:
	_timer.stop()
	if _fx != null and is_instance_valid(_fx):
		_fx.clear()
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
## r = ตัวคุมเกมออนไลน์ (NetMatchRunner) ไม่ใส่ = เล่นคนเดียวกับบอท
func begin(p: Dictionary, r: MatchRunner = null) -> void:
	plan = p
	_ensure_table()
	if runner != null and runner.has_signal(&"changed") and runner.is_connected(&"changed", _on_changed):
		runner.disconnect(&"changed", _on_changed)
	runner = r if r != null else MatchRunner.new(plan)
	var evs := runner.start()
	runner.take_events()
	if _online():
		runner.connect(&"changed", _on_changed)
		_set_where(&"battle")
	_ended = false
	_stuck = false
	_waiting = false
	_remote = false
	_host_end = false
	_desync.visible = false
	_sel = null
	_fall_back = false
	_log = PackedStringArray()
	_log_steps = []
	_log_text.text = ""
	_end_panel.visible = false
	_result.visible = false
	_leave.visible = false
	_auto.set_pressed_no_signal(false)
	var music := get_node_or_null(^"/root/Music")
	if music != null:
		music.call("reset_battle")
	_show_table()
	table.call("build_battle", runner.st)
	_fx_begin()
	_add_log(evs)
	_sound_feed(evs)          # ตาแรก: เสียง turn + ตั้งพื้นเพลง
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
	_fx_speed()


func is_over() -> bool:
	return runner != null and runner.is_over()


func is_waiting() -> bool:
	return _waiting


## ออนไลน์: รอเพื่อนหรือเจ้าห้องอยู่ (wait_remote)
func is_waiting_remote() -> bool:
	return _remote


func _online() -> bool:
	return runner != null and runner.has_method("online") and bool(runner.call("online"))


func _net_host() -> bool:
	return _online() and bool(runner.call("is_net_host"))


func _set_where(w: StringName) -> void:
	var net := get_node_or_null(^"/root/Net")
	if net != null and net.has_method("set_where") and bool(net.call("is_online")):
		net.call("set_where", w)


## ชื่อสมาชิกตามช่อง (ข้อความบนจอ) ไม่มีชื่อ = เจ้าห้อง
func _name_of_seat(k: int) -> String:
	if runner == null or k < 0 or k >= runner.st.seats.size():
		return I18n.t(T_HOST)
	var nm := runner.st.seats[k].nm
	return nm if nm != "" else I18n.t(T_HOST)


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
	if _fx_holding():
		return
	var t0 := Time.get_ticks_usec()
	var grew := false
	var stuck_now := false
	var fed: Array = []
	while true:
		var n0 := runner.acts().size()
		var r := runner.step()
		_add_log(r["events"])
		fed.append_array(r["events"])
		if runner.acts().size() != n0:
			grew = true
		var state := str(r["state"])
		if state == "wait_human":
			_timer.stop()
			_waiting = true
			_auto_select()
			break
		if state == "wait_remote":
			_timer.stop()
			_remote = true
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
	_fx_feed(fed)
	if runner.is_over():
		_show_end()
	_refresh()


## หลังคำสั่งของคุณ: วาดใหม่ แล้วเดินปั๊มต่อ (ลูกเต๋าที่ค้าง เพื่อนบอท) จนรอคุณอีกหรือมีอะไรให้ดู
func _after_human() -> void:
	_waiting = false
	var r := runner.step()
	_add_log(r["events"])
	table.call("sync_battle", runner.st)
	_fx_feed(r["events"])
	var state := str(r["state"])
	if state == "wait_human":
		_waiting = true
		_auto_select()
	elif state == "over":
		_show_end()
	elif state == "wait_remote":
		_remote = true
	else:
		_timer.start()
	_refresh()


## ออนไลน์: act มาถึง คำขอได้คำตอบ หรือถึงเวลาทอยแทน → วาดใหม่แล้วปั๊มต่อ · ป้ายที่นั่ง/เกมไม่ตรง
func _on_changed() -> void:
	if runner == null or not is_inside_tree():
		return
	for n: Dictionary in runner.call("take_notices"):
		_notice(n)
	var evs: Array = runner.take_events()
	_add_log(evs)
	if table != null and is_instance_valid(table) and table.visible:
		table.call("sync_battle", runner.st)
		_fx_feed(evs)
	if str(runner.get("ended_why")) != "" and not _ended:
		_host_end = true
		_show_end()
	elif runner.is_over() and not _ended:
		_show_end()
	_sync_panel()
	if not _ended and not _stuck and not _leave.visible and is_visible_in_tree() and runner.call("sync_state") == &"ok":
		_remote = false
		if not _waiting or not runner.is_human_turn():
			_waiting = false
			_timer.start()
	_refresh()


## ป้ายของเรื่องออนไลน์ (ที่นั่งหลุด/ออก/กลับ คำขอช้าไป เครื่องเพื่อนไม่ตรง)
func _notice(n: Dictionary) -> void:
	var key := str(n.get("key", ""))
	var nm := _name_of_seat(int(n.get("k", -1)))
	match key:
		"mine":
			_say_t(T_MINE, {})
		"gone":
			_say_t(T_SEAT_GONE, {"name": nm})
		"left":
			_say_t(T_SEAT_LEFT, {"name": nm})
		"back":
			_say_t(T_SEAT_BACK, {"name": nm})
		"stale":
			_say_t(T_STALE, {})
		"desync":
			var names: Dictionary = runner.get("names")
			var who := str(names.get(int(n.get("slot", -1)), ""))
			_say_t(T_DESYNC_HOST, {"name": who if who != "" else "?"})


## ป้ายที่แปลใหม่ได้เมื่อเปลี่ยนภาษา (เก็บคีย์ไทยกับค่าไว้)
func _say_t(th: String, args: Dictionary) -> void:
	_say(I18n.t(th).format(args))
	_toast_text.set_meta("tf", [th, args])


## แผงเกมไม่ตรงกับเจ้าห้อง: ครั้งแรกขึ้นระหว่างโหลดใหม่ (ซ่อมได้ปิดเองใน 3 วินาที) ครั้งสุดท้ายค้างไว้พร้อมปุ่มออก
func _sync_panel() -> void:
	if not _online() or _net_host():
		return
	var s: StringName = runner.call("sync_state")
	if s == &"desync":
		_timer.stop()
		_desync_text.set_meta("th", T_DESYNC)
		_desync_text.text = I18n.t(T_DESYNC)
		_desync_btn.visible = false
		_desync.visible = true
		_desync.set_meta("was", true)
	elif s == &"desync_final":
		_timer.stop()
		_desync_text.set_meta("th", T_DESYNC_FINAL)
		_desync_text.text = I18n.t(T_DESYNC_FINAL)
		_desync_btn.visible = true
		_desync.visible = true
	elif _desync.visible and _desync.get_meta("was", false):
		_desync.set_meta("was", false)
		_desync_text.set_meta("th", T_REPAIRED)
		_desync_text.text = I18n.t(T_REPAIRED)
		_desync_btn.visible = false
		_desync_timer.start(REPAIRED_SECONDS)


## สถานะของแผงเกมไม่ตรง (เทส): "" | desync | desync_final | repaired
func desync_panel_state() -> String:
	if _desync == null or not _desync.visible:
		return ""
	if _desync_btn.visible:
		return "desync_final"
	return "repaired" if _desync_text.text == I18n.t(T_REPAIRED) else "desync"


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
	_leave_text.set_meta("th", T_LEAVE if not _online() else (T_LEAVE_HOST if _net_host() else T_LEAVE_CLIENT))
	_leave_text.text = I18n.t(str(_leave_text.get_meta("th")))
	_leave.visible = true
	_timer.stop()


func _close_leave() -> void:
	_leave.visible = false
	if runner != null and not _waiting and not _ended and not _stuck:
		_timer.start()


func _on_lobby() -> void:
	_timer.stop()
	if _online():
		# เจ้าห้องออก = เกมจบทุกคน (END) · เพื่อนออก = บอทของเจ้าห้องเล่นแทนจนจบเกม (เจ้าห้องเห็นจาก where)
		var link := get_node_or_null(NET_LINK)
		if _net_host() and link != null and link.has_method("host_left"):
			link.call("host_left")
		elif link != null and link.has_method("client_left"):
			link.call("client_left")   # LEAVE ของเกมนี้: เจ้าห้องเล่นแทนจนจบเกม
		_set_where(&"deck")
	App.pop()


func _on_again() -> void:
	var c: Dictionary = plan.get("choice", {})
	if c.is_empty():
		return
	var seed_v := int(c.get("seed", 1)) % 99999 + 1
	if _online():
		# เจ้าห้อง: เกมใหม่ (gen + 1) ตัวเลือกเดิม seed ใหม่ ส่ง START ให้ทุกคน
		var link := get_node_or_null(NET_LINK)
		var net := get_node_or_null(^"/root/Net")
		if not _net_host() or link == null or net == null:
			return
		# เพื่อนที่ออกจากห้องไปแล้ว: ที่นั่งเป็นบอท (ไม่งั้นเริ่มไม่ได้แบบเงียบ ๆ) · ยังมีข้อผิดพลาด: บอกบนจอ
		var nc := SeatPlan.with_seed(c.duplicate(true), seed_v)
		var mem: Array = net.call("members")
		NetSeats.drop_gone(nc, mem)
		var np := NetSeats.build(nc, mem)
		var errs: PackedStringArray = np["errors"]
		if errs.is_empty():
			begin(np, link.call("start_host", np))
		else:
			_say(NetSeats.error_text(errs[0], nc))
		return
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

# ---- ท่าทาง/เอฟเฟกต์ (BattleFx: ภาพล้วน ไม่แตะกติกา) ----

## โหนดภาพการรบใต้โต๊ะ (สร้างครั้งแรก) แล้วเริ่มนัดใหม่
func _fx_begin() -> void:
	if table == null or runner == null:
		return
	if _fx == null or not is_instance_valid(_fx):
		_fx = table.get_node_or_null(^"BattleFx") as BattleFx
		if _fx == null:
			_fx = BattleFx.new()
			_fx.name = "BattleFx"
			table.add_child(_fx)
	_fx.begin(table, runner.st)
	_fx_speed()


func _fx_speed() -> void:
	if _fx == null:
		return
	_fx.enabled = _fx.allowed and speed != "instant"
	_fx.time_scale = 1.0 if speed == "normal" else FX_FAST
	if not _fx.enabled:
		_fx.clear()


## เหตุการณ์ของก้าวไปเป็นภาพ (หลังโต๊ะวาดตำแหน่งใหม่แล้ว)
func _fx_feed(evs: Array) -> void:
	_sound_feed(evs)
	if _fx == null or runner == null:
		return
	_fx.feed(evs, runner.st)
	if _fx.busy_left() > 0.0:
		_fx_fed_ms = Time.get_ticks_msec()


## เสียงของจังหวะเกม (หน้าเก่า: turn ตอนเริ่มตา, end ตอนจบ, dice ตอนทอย) + เพลงเข้มขึ้นสองตาสุดท้าย
## เสียงยิง/ฟัน/ตายอยู่ใน BattleFx · เสียงไม่แตะกติกา
func _sound_feed(evs: Array) -> void:
	if runner == null or speed == "instant" or not is_visible_in_tree():
		return
	var sfx := get_node_or_null(^"/root/Sfx")
	var music := get_node_or_null(^"/root/Music")
	var diced := false
	for e: Variant in evs:
		if not e is Dictionary:
			continue
		match Events.id_of(e):
			Events.Id.TURN:
				if sfx != null:
					sfx.call("play", &"turn")
				if music != null:
					var left := runner.st.max_round() - int(e.get("round", 0))
					music.call("set_intensity", 1.0 if left <= 0 else (0.5 if left == 1 else 0.0))
			Events.Id.ATTACK_STAGE:
				if not diced and sfx != null and str(e.get("stage", "")) == "hit":
					diced = true
					sfx.call("play", &"dice", null, 0.7)
			Events.Id.OVER:
				if sfx != null:
					sfx.call("play", &"end")


## ความเร็วปกติ: รอภาพของก้าวก่อนเล่นจบก่อนก้าวต่อ (ไม่เกิน FX_HOLD_MS) · ภาพไม่เคยเปลี่ยนผลของเกม
func _fx_holding() -> bool:
	if _fx == null or not _fx.enabled or speed != "normal":
		return false
	if Time.get_ticks_msec() - _fx_fed_ms > FX_HOLD_MS:
		return false
	return _fx.busy_left() > 0.0


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
	var music := get_node_or_null(^"/root/Music")
	if music != null:
		music.call("set_mood", &"battle")


func _on_visibility() -> void:
	if runner == null or table == null or not is_instance_valid(table):
		return
	if is_visible_in_tree():
		_show_table()
		table.call("build_battle", runner.st)
		_fx_begin()
		_select(_sel if _sel != null and runner.can_select(_sel) else null)
		_refresh()
		if not _waiting and not _ended and not _stuck and not _leave.visible:
			_timer.start()
	else:
		_timer.stop()
		if _fx != null:
			_fx.clear()
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
	elif _host_end and not runner.is_over():
		_end_title.text = I18n.t(T_LOST if str(runner.get("ended_why")) == "lost" else T_HOST_LEFT)
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
	_toast_text.remove_meta("tf")
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
	if _toast_text.has_meta("tf"):
		var tf: Array = _toast_text.get_meta("tf")
		_toast_text.text = I18n.t(str(tf[0])).format(tf[1])
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
	var wait_name := ""
	if _online() and not _net_host() and str(runner.get("link_state")) == "reconnecting":
		hint = T_RECONNECTING   # เพื่อน: หลุดอยู่ กำลังต่อใหม่ (คำสั่งยังส่งไม่ได้)
	elif _online() and bool(runner.call("my_seat_gone")):
		hint = T_MINE
	elif _online() and runner.human < 0:
		hint = T_SPECTATOR
	elif runner.human < 0:
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
	elif _online() and _remote and not st.over:
		hint = T_WAIT_REMOTE
		var names := PackedStringArray()
		for nm: String in runner.call("waiting_for"):
			var t := nm if nm != "" else I18n.t(T_HOST)
			if not names.has(t):
				names.append(t)
		wait_name = ", ".join(names) if not names.is_empty() else I18n.t(T_HOST)
	elif not st.over:
		hint = T_HINT_BOTS
	_hint.text = (I18n.t(hint).format({"name": wait_name}) if hint == T_WAIT_REMOTE else I18n.t(hint)) if hint != "" else ""
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
	# ออนไลน์: เล่นอีกครั้งเฉพาะเจ้าห้อง เพื่อนเห็นข้อความรอแทน · เจ้าห้องจบเกม: ปุ่มกลับอย่างเดียว
	_again.visible = not _online() or (_net_host() and not _host_end)
	_wait_again.visible = _online() and not _net_host() and not _host_end
	_look.visible = not _host_end
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
	_wait_again = Label.new()
	_wait_again.name = "WaitAgain"
	_wait_again.set_meta("th", T_WAIT_AGAIN)
	_wait_again.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_wait_again.custom_minimum_size.y = 56.0
	CandleStyle.text(_wait_again, 18, true)
	_wait_again.visible = false
	eb.add_child(_wait_again)
	_own(_wait_again)
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
	lt.name = "LeaveText"
	lt.set_meta("th", T_LEAVE)
	lt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lt.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	CandleStyle.text(lt, 22)
	lv.add_child(lt)
	_leave_text = lt
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
	# แผงเกมไม่ตรงกับเจ้าห้อง (ขอบแดง กลางจอ)
	_desync = _centre_panel("DesyncPanel")
	var dsb := _desync.get_theme_stylebox(&"panel")
	if dsb is StyleBoxFlat:
		var c := (dsb as StyleBoxFlat).duplicate() as StyleBoxFlat
		c.border_color = CandleStyle.DANGER
		c.set_border_width_all(3)
		_desync.add_theme_stylebox_override(&"panel", c)
	var dv := VBoxContainer.new()
	dv.add_theme_constant_override(&"separation", 14)
	_desync.add_child(dv)
	_desync_text = Label.new()
	_desync_text.name = "DesyncText"
	_desync_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_desync_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	CandleStyle.text(_desync_text, 22)
	_desync_text.add_theme_color_override(&"font_color", CandleStyle.DANGER)
	dv.add_child(_desync_text)
	_desync_btn = _button("DesyncLeave", T_LEAVE_YES)
	_desync_btn.pressed.connect(_on_lobby)
	_desync_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	dv.add_child(_desync_btn)
	_desync.visible = false
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
