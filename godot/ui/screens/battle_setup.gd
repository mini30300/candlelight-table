extends Node2D
## หน้าตั้งเกม (LOBBY_SPEC §3): ซ้าย = ที่นั่ง (จำนวนทีม ขนาดทีม แถวละที่นั่ง: สีทีม กองทัพจาก 15 + สุ่ม คุณ/บอท)
## ขวา = โต๊ะ (ขนาด ฉาก ภูมิประเทศ เป้าหมาย/จำนวนรอบ แต้มต่อทีม เลขสนาม) · ล่าง = ‹ ล็อบบี้, ข้อผิดพลาด, เริ่มรบ ›
## ตัวเลือกอยู่ใน choice (แบบ SeatPlan) → SeatPlan.build → App.replace(หน้ารบ) แล้ว begin(plan)
## ทึบเต็มจอ ไม่มีงานต่อเฟรม · ข้อความทุกอันแปลทั้งประโยคตอนวาด (refresh)
## รากเป็น Node2D (ยังซ่อน/โชว์ได้แบบ CanvasItem) เพราะ API set_size / set_theme ในสัญญาชนชื่อกับ Control;
## หน้าจริงคือ Control ลูกชื่อ Page ยึดขอบตามจอ

const BATTLE_SCREEN := "res://ui/screens/battle_screen.tscn"
const TITLE := "ตั้งเกม"
const T_TEAMS := "จำนวนทีม"
const T_PER_TEAM := "ขนาดทีม"
const T_SIZE := "ขนาดโต๊ะ"
const T_THEME := "ฉาก"
const T_TERRAIN := "ภูมิประเทศ"
const T_GOAL := "เป้าหมาย"
const T_POINTS := "แต้มต่อทีม"
const T_ROUNDS := "{n} รอบ"
const T_LONG := "เกมอาจยาว"
const T_SEED := "เลขสนาม {seed}"
const T_REROLL := "สุ่มใหม่"
const T_RANDOM := "สุ่ม"
const T_YOU := "คุณ"
const T_BOT := "บอท"
const T_BACK := "‹ ล็อบบี้"
const T_START := "เริ่มรบ ›"
const T_WATCH := "ไม่มีที่นั่งของคุณ — ดูบอทเล่นกันเอง"
const THEME_NAMES := {"ruin": "เมืองพัง", "forest": "ป่าไม้", "desert": "ทะเลทราย", "ice": "ทุ่งหิมะ"}
const TERRAIN_NAMES := {"flat": "ราบ", "hills": "เนิน", "mountain": "ภูเขา", "forest": "ป่าทึบ"}
const GOAL_NAMES := {"obj": "ยึดจุด", "kill": "ตีกันจนตาย"}
const T_NET_HINT := "แตะเพื่อสลับ: บอท · คุณ · เพื่อน"
const NET_LINK := ^"/root/Net/NetBattleLink"
const TEAMS_PATH := "res://data/teams.json"
const CHIP_H := 48.0
const LABEL_W := 150.0

## ตัวเลือกปัจจุบัน (รูปเดียวกับ SeatPlan.defaults)
var choice: Dictionary = {}

var _teams_data: Array = []
var _chips: Dictionary = {}          # ชื่อกลุ่ม → {ค่า: Button}
var _seat_rows: Array = []           # [{row, swatch, team, army, who}]
var _seats_box: VBoxContainer
var _rounds_box: HBoxContainer
var _rounds_label: Label
var _long_hint: Label
var _seed_label: Label
var _errors: Label
var _start: Button
var _back: Button
var _title: Label
var _notice := ""
var _building := false
var _to_own: Array[Node] = []
var _page: Control
## ออนไลน์ (NET_SPEC §5.1): เจ้าห้องที่มีเพื่อนในห้อง · ที่นั่งมี owner (ช่องของสมาชิก หรือ -1 บอท)
var online := false
## Net หรือของปลอมในเทส (API แบบ NetSession)
var net: Node = null
var _sent_seats: Array = []
var _setup_sent := false


func _ready() -> void:
	var t: Variant = _json(TEAMS_PATH)
	_teams_data = t if t is Array else []
	if net == null:
		net = get_node_or_null(^"/root/Net")
	online = net != null and bool(net.call("is_host")) and (net.call("members") as Array).size() >= 2
	if online:
		# ตัวเลือกออนไลน์ล่าสุด (ในหน่วยความจำ) ไม่งั้นที่นั่งตามสมาชิก
		var mem: Array = net.call("members")
		choice = NetSeats.defaults(mem, _new_seed()) if NetSeats.last.is_empty() else SeatPlan.with_seed(NetSeats.last, _new_seed())
		NetSeats.fit(choice)
		NetSeats.drop_gone(choice, mem)
		net.connect(&"message", _on_net_message)
		net.connect(&"members_changed", _on_members)
	else:
		# เปิดด้วยตัวเลือกของเกมก่อน (เลขสนามใหม่) ถ้ามี ไม่งั้นค่าเริ่มต้น
		choice = SeatPlan.defaults(_new_seed()) if App.last_choice.is_empty() else SeatPlan.with_seed(App.last_choice, _new_seed())
	_build()
	_fit_page()
	get_viewport().size_changed.connect(_fit_page)
	refresh()
	visibility_changed.connect(func() -> void:
		if is_visible_in_tree():
			refresh())


# ---- API (เทสและหน้าอื่นเรียก) ----

func set_teams(n: int) -> void:
	if n * int(choice["per_team"]) > SeatPlan.MAX_SEATS:
		_notice = SeatPlan.error_text("seats", choice)
		refresh()
		return
	choice["teams"] = clampi(n, SeatPlan.MIN_TEAMS, SeatPlan.MAX_TEAMS)
	_after_seats()


func set_per_team(n: int) -> void:
	if n * int(choice["teams"]) > SeatPlan.MAX_SEATS:
		_notice = SeatPlan.error_text("seats", choice)
		refresh()
		return
	choice["per_team"] = clampi(n, 1, SeatPlan.MAX_PER_TEAM)
	_after_seats()


## ที่นั่ง i: กองทัพ fac ("" = สุ่ม) และเป็นคุณไหม (เลือกคุณที่แถวอื่น แถวเดิมกลายเป็นบอท)
func set_seat(i: int, fac: String, human: bool) -> void:
	var seats: Array = choice["seats"]
	if i < 0 or i >= seats.size():
		return
	(seats[i] as Dictionary)["fac"] = fac
	if online:
		pass   # ออนไลน์ เจ้าของที่นั่งเปลี่ยนด้วย set_seat_owner เท่านั้น
	elif human:
		for k in seats.size():
			(seats[k] as Dictionary)["human"] = k == i
	else:
		(seats[i] as Dictionary)["human"] = false
	_notice = ""
	refresh()


func set_size(s: String) -> void:
	if SeatPlan.SIZES.has(s):
		choice["size"] = s
	_notice = ""
	refresh()


func set_theme(k: String) -> void:
	choice["theme"] = k
	refresh()


func set_terrain(k: String) -> void:
	choice["terrain"] = k
	refresh()


func set_goal(g: String) -> void:
	choice["goal"] = g
	refresh()


func set_rounds(n: int) -> void:
	choice["rounds"] = clampi(n, 3, 10)
	refresh()


func set_budget(n: int) -> void:
	choice["budget"] = n
	refresh()


func set_seed(n: int) -> void:
	choice["seed"] = clampi(n, 1, 99999)
	refresh()


## ออนไลน์: เจ้าของที่นั่ง i (ช่องของสมาชิก -1 = บอท 0 = คุณ)
func set_seat_owner(i: int, slot: int) -> void:
	NetSeats.set_owner(choice, i, slot)
	_notice = ""
	refresh()


## ออนไลน์: ปุ่มเจ้าของของแถว i (บอท → คุณ → เพื่อนที่ยังไม่มีที่นั่ง → บอท)
func cycle_owner(i: int) -> void:
	set_seat_owner(i, NetSeats.next_owner(choice, i, net.call("members")))


## รหัสข้อผิดพลาดของตัวเลือก (ว่าง = เริ่มได้)
func errors() -> PackedStringArray:
	if online:
		return NetSeats.validate(choice, net.call("members"))
	return SeatPlan.validate(choice)


func _on_net_message(from_slot: int, kind: int, body: Dictionary) -> void:
	if kind == NetProto.CLAIM and online and is_visible_in_tree():
		if NetSeats.claim(choice, from_slot, int(body.get("k", -2))):
			refresh()


func _on_members() -> void:
	if not online:
		return
	if NetSeats.drop_gone(choice, net.call("members")):
		refresh()
	elif is_inside_tree():
		refresh()


## ส่ง SETUP เมื่อที่นั่งเปลี่ยน (เปิดหน้า เปลี่ยนตัวเลือก) · open = false ตอนปิดหรือเริ่ม
func _send_setup(open: bool) -> void:
	if not online or net == null:
		return
	var seats := NetSeats.seats_body(choice) if open else []
	if open and _setup_sent and seats == _sent_seats:
		return
	if not open and not _setup_sent:
		return
	_setup_sent = open
	_sent_seats = seats
	net.call("send", NetProto.SETUP, {"open": open, "seats": seats}, -1)


func _exit_tree() -> void:
	_send_setup(false)


## เหมือนกด เริ่มรบ ›: หน้ารบแทนที่หน้านี้ (ห้องโถงไม่โผล่ระหว่างนั้น) แล้วเริ่มนัด
func start() -> bool:
	if not errors().is_empty():
		refresh()
		return false
	if online:
		return _start_online()
	var plan := SeatPlan.build(choice)
	if not (plan["errors"] as PackedStringArray).is_empty() or not ResourceLoader.exists(BATTLE_SCREEN):
		return false
	App.last_choice = choice.duplicate(true)
	var scr: Node = App.replace(load(BATTLE_SCREEN))
	if scr != null and scr.has_method("begin"):
		scr.call("begin", plan)
		return true
	return false


## ออนไลน์: แผนพร้อมเจ้าของที่นั่ง → START ถึงทุกคน → หน้ารบแทนที่หน้านี้ด้วยตัวคุมเกมของเจ้าห้อง
func _start_online() -> bool:
	var plan := NetSeats.build(choice, net.call("members"))
	var link := net.get_node_or_null(^"NetBattleLink")
	if not (plan["errors"] as PackedStringArray).is_empty() or link == null or not ResourceLoader.exists(BATTLE_SCREEN):
		return false
	NetSeats.last = choice.duplicate(true)
	_send_setup(false)
	var r: Variant = link.call("start_host", plan)
	var scr: Node = App.replace(load(BATTLE_SCREEN))
	if scr != null and scr.has_method("begin"):
		scr.call("begin", plan, r)
		return true
	return false


func handle_back() -> bool:
	_send_setup(false)
	return false   # ถอยกลับห้องโถง (App.pop)


# ---- ภายใน ----

func _after_seats() -> void:
	if online:
		NetSeats.fit(choice)
	SeatPlan.fit_seats(choice)
	_notice = ""
	_rebuild_seat_rows()
	refresh()


func _new_seed() -> int:
	return randi_range(1, 99999)   # เลขสนามของ UI (กติกา seed จากเลขนี้)


## วาดข้อความและสถานะปุ่มทั้งหน้าใหม่ตามภาษาและตัวเลือก
func refresh() -> void:
	if _title == null:
		return
	_building = true
	for n in _all_text_nodes(self):
		n.set("text", I18n.t(str(n.get_meta("th"))))
	_pick("teams", int(choice["teams"]))
	_pick("per_team", int(choice["per_team"]))
	_pick("size", str(choice["size"]))
	_pick("theme", str(choice["theme"]))
	_pick("terrain", str(choice["terrain"]))
	_pick("goal", str(choice["goal"]))
	_pick("budget", int(choice["budget"]))
	var obj := str(choice["goal"]) == "obj"
	_rounds_box.visible = obj
	_long_hint.visible = not obj
	_rounds_label.text = I18n.t(T_ROUNDS).format({"n": int(choice["rounds"])})
	_seed_label.text = I18n.t(T_SEED).format({"seed": int(choice["seed"])})
	var seats: Array = choice["seats"]
	if _seat_rows.size() != seats.size():
		_rebuild_seat_rows()
	var any_human := false
	for k in _seat_rows.size():
		var r: Dictionary = _seat_rows[k]
		var sd: Dictionary = seats[k]
		var team := SeatPlan.team_of(choice, k)
		(r["swatch"] as ColorRect).color = _team_colour(team)
		(r["team"] as Label).text = I18n.t(_team_th(team))
		var ob := r["army"] as OptionButton
		_fill_armies(ob)
		var fac := str(sd.get("fac", ""))
		var idx := GameData.factions().find(fac)
		ob.select(idx + 1 if idx >= 0 else 0)
		var who := r["who"] as Button
		var human := bool(sd.get("human", false))
		any_human = any_human or human
		who.button_pressed = human
		who.text = I18n.t(T_YOU if human else T_BOT)
		if online:
			var o := int(sd.get("owner", -1))
			who.button_pressed = o >= 0
			who.clip_text = true
			who.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
			who.custom_minimum_size.x = 140.0
			who.text = I18n.t(T_BOT) if o < 0 else (I18n.t(T_YOU) if o == 0 else str((net.call("member", o) as Dictionary).get("nm", "?")))
	var errs := errors()
	var msgs := PackedStringArray()
	for code in errs:
		msgs.append(NetSeats.error_text(code, choice) if online else SeatPlan.error_text(code, choice))
	if _notice != "":
		msgs.append(_notice)
	if msgs.is_empty() and online:
		_errors.text = I18n.t(T_NET_HINT)
		_errors.add_theme_color_override(&"font_color", CandleStyle.MUTED)
	elif msgs.is_empty() and not any_human:
		_errors.text = I18n.t(T_WATCH)
		_errors.add_theme_color_override(&"font_color", CandleStyle.MUTED)
	else:
		_errors.text = " · ".join(msgs)
		_errors.add_theme_color_override(&"font_color", CandleStyle.DANGER)
	_start.disabled = not errs.is_empty()
	_building = false
	if online and is_inside_tree():
		_send_setup(true)


func _pick(group: String, value: Variant) -> void:
	var g: Dictionary = _chips.get(group, {})
	for v in g:
		(g[v] as Button).set_pressed_no_signal(v == value)


func _team_th(team: int) -> String:
	if team >= 0 and team < _teams_data.size() and _teams_data[team] is Dictionary:
		return str((_teams_data[team] as Dictionary).get("nm", ""))
	return "ทีม"


func _team_colour(team: int) -> Color:
	if team >= 0 and team < _teams_data.size() and _teams_data[team] is Dictionary:
		var rgb: Variant = (_teams_data[team] as Dictionary).get("rgb")
		if rgb is Array and (rgb as Array).size() >= 3:
			return Color8(int(rgb[0]), int(rgb[1]), int(rgb[2]))
	return Color.WHITE


func _fill_armies(ob: OptionButton) -> void:
	var facs := GameData.factions()
	if ob.item_count != facs.size() + 1:
		ob.clear()
		ob.add_item("")
		for f in facs:
			ob.add_item("")
	ob.set_item_text(0, I18n.t(T_RANDOM))
	for i in facs.size():
		ob.set_item_text(i + 1, I18n.t(str(GameData.faction(facs[i]).get("nm", facs[i]))))


static func _all_text_nodes(n: Node) -> Array[Node]:
	var out: Array[Node] = []
	if n.has_meta("th"):
		out.append(n)
	for c in n.get_children():
		out.append_array(_all_text_nodes(c))
	return out


static func _json(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		return null
	return JSON.parse_string(FileAccess.get_file_as_string(path))


# ---- สร้างหน้า ----

func _build() -> void:
	var page := Control.new()
	page.name = "Page"
	add_child(page)
	_own(page)
	_page = page
	var bg := ColorRect.new()
	bg.color = CandleStyle.BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	page.add_child(bg)
	var margin := MarginContainer.new()
	margin.name = "Margin"
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	page.add_child(margin)
	CandleStyle.safe_margins(margin)
	var col := VBoxContainer.new()
	col.add_theme_constant_override(&"separation", 10)
	margin.add_child(col)
	_title = _label(TITLE, 0)
	CandleStyle.title(_title, 34)
	col.add_child(_title)
	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override(&"separation", 16)
	col.add_child(body)
	# ซ้าย: ที่นั่ง
	var left := PanelContainer.new()
	left.name = "SeatsPanel"
	CandleStyle.panel(left)
	left.custom_minimum_size.x = 500.0
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.size_flags_stretch_ratio = 0.72
	body.add_child(left)
	var lv := VBoxContainer.new()
	lv.add_theme_constant_override(&"separation", 8)
	left.add_child(lv)
	lv.add_child(_chip_row("TeamCount", T_TEAMS, "teams", [[2, "2"], [3, "3"], [4, "4"]], func(v: Variant) -> void: set_teams(int(v))))
	lv.add_child(_chip_row("PerTeam", T_PER_TEAM, "per_team", [[1, "1"], [2, "2"]], func(v: Variant) -> void: set_per_team(int(v))))
	_seats_box = VBoxContainer.new()
	_seats_box.name = "Seats"
	_seats_box.add_theme_constant_override(&"separation", 6)
	lv.add_child(_seats_box)
	_own(_seats_box)
	# ขวา: โต๊ะ
	var right := PanelContainer.new()
	right.name = "TablePanel"
	CandleStyle.panel(right)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(right)
	var rv := VBoxContainer.new()
	rv.add_theme_constant_override(&"separation", 8)
	right.add_child(rv)
	var sizes: Array = []
	for s in SeatPlan.SIZE_ORDER:
		sizes.append([s, str(SeatPlan.SIZE_NAMES[s])])
	rv.add_child(_chip_row("Size", T_SIZE, "size", sizes, func(v: Variant) -> void: set_size(str(v))))
	rv.add_child(_chip_row("Theme", T_THEME, "theme", _pairs(SeatPlan.THEMES, THEME_NAMES), func(v: Variant) -> void: set_theme(str(v))))
	rv.add_child(_chip_row("Terrain", T_TERRAIN, "terrain", _pairs(SeatPlan.TERRAINS, TERRAIN_NAMES), func(v: Variant) -> void: set_terrain(str(v))))
	var goal_row := _chip_row("Goal", T_GOAL, "goal", _pairs(SeatPlan.GOALS, GOAL_NAMES), func(v: Variant) -> void: set_goal(str(v)))
	rv.add_child(goal_row)
	# จำนวนรอบ (ยึดจุด) หรือคำเตือนเกมยาว (ตีกันจนตาย)
	var rounds_row := HBoxContainer.new()
	rounds_row.add_theme_constant_override(&"separation", 8)
	var spacer := Control.new()
	spacer.custom_minimum_size.x = LABEL_W
	rounds_row.add_child(spacer)
	_rounds_box = HBoxContainer.new()
	_rounds_box.name = "Rounds"
	_rounds_box.add_theme_constant_override(&"separation", 8)
	var minus := _button("−")
	minus.name = "RoundsLess"
	minus.custom_minimum_size.x = 56.0
	minus.pressed.connect(func() -> void: set_rounds(int(choice["rounds"]) - 1))
	_rounds_label = Label.new()
	_rounds_label.name = "RoundsLabel"
	_rounds_label.custom_minimum_size.x = 96.0
	_rounds_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_rounds_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	CandleStyle.text(_rounds_label, 20)
	var plus := _button("+")
	plus.name = "RoundsMore"
	plus.custom_minimum_size.x = 56.0
	plus.pressed.connect(func() -> void: set_rounds(int(choice["rounds"]) + 1))
	_rounds_box.add_child(minus)
	_rounds_box.add_child(_rounds_label)
	_rounds_box.add_child(plus)
	rounds_row.add_child(_rounds_box)
	_long_hint = _label(T_LONG, 18, true)
	_long_hint.name = "LongHint"
	_long_hint.custom_minimum_size.y = CHIP_H
	_long_hint.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	rounds_row.add_child(_long_hint)
	rv.add_child(rounds_row)
	var pts: Array = []
	for b in SeatPlan.BUDGETS:
		pts.append([b, str(b)])
	rv.add_child(_chip_row("Points", T_POINTS, "budget", pts, func(v: Variant) -> void: set_budget(int(v))))
	var seed_row := HBoxContainer.new()
	seed_row.add_theme_constant_override(&"separation", 8)
	var sp2 := Control.new()
	sp2.custom_minimum_size.x = LABEL_W
	seed_row.add_child(sp2)
	_seed_label = Label.new()
	_seed_label.name = "SeedLabel"
	_seed_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_seed_label.custom_minimum_size.y = CHIP_H
	CandleStyle.text(_seed_label, 20, true)
	seed_row.add_child(_seed_label)
	var reroll := _button(T_REROLL)
	reroll.name = "RerollButton"
	reroll.custom_minimum_size.x = 120.0   # ข้อความไม่ชิดขอบปุ่ม
	reroll.pressed.connect(func() -> void: set_seed(_new_seed()))
	seed_row.add_child(reroll)
	rv.add_child(seed_row)
	# ล่าง
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override(&"separation", 12)
	col.add_child(bar)
	_back = _button(T_BACK)
	_back.name = "BackButton"
	_back.custom_minimum_size = Vector2(170, 56)
	_back.pressed.connect(func() -> void: App.pop())
	bar.add_child(_back)
	_errors = Label.new()
	_errors.name = "Errors"
	_errors.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_errors.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_errors.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_errors.max_lines_visible = 2
	CandleStyle.text(_errors, 18)
	bar.add_child(_errors)
	_start = _button(T_START, true)
	_start.name = "StartButton"
	_start.custom_minimum_size = Vector2(220, 56)
	_start.pressed.connect(func() -> void: start())
	bar.add_child(_start)
	for n in [_seed_label, _errors, _start, _back, _rounds_label]:
		_own(n)
	for n in _to_own:
		n.unique_name_in_owner = true
		n.owner = self
	_to_own.clear()
	_rebuild_seat_rows()


## หน้าเต็มจอ: ใต้ Node2D ยึดขอบไม่ได้ จึงตั้งขนาดตามจอเอง (ตอนเริ่มและเมื่อจอเปลี่ยนขนาด)
func _fit_page() -> void:
	if _page == null:
		return
	_page.position = Vector2.ZERO
	_page.size = get_viewport().get_visible_rect().size
	var m := _page.get_node_or_null(^"Margin") as MarginContainer
	if m != null:
		CandleStyle.safe_margins(m)


func _pairs(keys: PackedStringArray, names: Dictionary) -> Array:
	var out: Array = []
	for k in keys:
		out.append([k, str(names[k])])
	return out


## แถว: ป้ายซ้าย + ปุ่มเลือกได้ทีละอัน (กลุ่ม group) · node ชื่อ name (ชื่อเฉพาะ %name)
func _chip_row(node_name: String, th: String, group: String, items: Array, on_pick: Callable) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 8)
	var l := _label(th, 20)
	l.custom_minimum_size = Vector2(LABEL_W, CHIP_H)
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	row.add_child(l)
	var box := HBoxContainer.new()
	box.name = node_name
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override(&"separation", 6)
	row.add_child(box)
	_own(box)
	var g := ButtonGroup.new()
	g.allow_unpress = false
	var map := {}
	for it in items:
		var v: Variant = it[0]
		var b := _button(str(it[1]))
		b.name = "%s_%s" % [node_name, str(v)]
		b.toggle_mode = true
		b.button_group = g
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.pressed.connect(func() -> void:
			if not _building:
				on_pick.call(v))
		box.add_child(b)
		map[v] = b
	_chips[group] = map
	return row


func _rebuild_seat_rows() -> void:
	for r in _seat_rows:
		(r["row"] as Node).queue_free()
	_seat_rows.clear()
	if _seats_box == null:
		return
	for k in (choice["seats"] as Array).size():
		var row := HBoxContainer.new()
		row.name = "Seat%d" % k
		row.add_theme_constant_override(&"separation", 8)
		var sw := ColorRect.new()
		sw.custom_minimum_size = Vector2(12, CHIP_H)
		sw.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(sw)
		var team := Label.new()
		team.custom_minimum_size = Vector2(118, CHIP_H)
		team.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		team.clip_text = true
		CandleStyle.text(team, 18)
		row.add_child(team)
		var army := OptionButton.new()
		army.name = "Army%d" % k
		army.custom_minimum_size = Vector2(160, CHIP_H)
		army.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		army.clip_text = true
		army.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		_style(army)
		CandleStyle.popup(army.get_popup())
		_fill_armies(army)
		var idx := k
		army.item_selected.connect(func(i: int) -> void:
			if _building:
				return
			var sd: Dictionary = choice["seats"][idx]
			set_seat(idx, "" if i <= 0 else GameData.factions()[i - 1], bool(sd.get("human", false))))
		row.add_child(army)
		var who := _button(T_BOT)
		who.name = "Who%d" % k
		who.toggle_mode = true
		who.custom_minimum_size = Vector2(96, CHIP_H)
		who.pressed.connect(func() -> void:
			if _building:
				return
			if online:
				cycle_owner(idx)
				return
			var sd: Dictionary = choice["seats"][idx]
			set_seat(idx, str(sd.get("fac", "")), not bool(sd.get("human", false))))
		row.add_child(who)
		_seats_box.add_child(row)
		_seat_rows.append({"row": row, "swatch": sw, "team": team, "army": army, "who": who})


func _label(th: String, size: int, muted := false) -> Label:
	var l := Label.new()
	l.set_meta("th", th)
	l.text = th
	if size > 0:
		CandleStyle.text(l, size, muted)
	return l


func _button(th: String, primary := false) -> Button:
	var b := Button.new()
	b.set_meta("th", th)
	b.text = th
	_style(b, primary)
	return b


## สไตล์ปุ่มเทียน ขนาดชิป (สูง 48 ตัว 18 ขอบข้างแคบ) ปุ่มที่เลือกอยู่สีอำพัน
func _style(b: Button, primary := false) -> void:
	CandleStyle.button(b, primary)
	b.custom_minimum_size.y = CHIP_H
	b.add_theme_font_size_override(&"font_size", 18)
	for state in [&"normal", &"hover", &"pressed", &"hover_pressed", &"disabled"]:
		var sb := b.get_theme_stylebox(state)
		if sb is StyleBoxFlat:
			var c := (sb as StyleBoxFlat).duplicate() as StyleBoxFlat
			c.content_margin_left = 8.0
			c.content_margin_right = 8.0
			if state == &"pressed" or state == &"hover_pressed":
				c.bg_color = Color("7a4a1c")   # ปุ่มที่เลือกอยู่: สีอำพัน
			b.add_theme_stylebox_override(state, c)


## ให้ %ชื่อ ใช้ได้ (ชื่อเฉพาะในหน้า; ตั้ง owner ตอนสร้างเสร็จ เมื่ออยู่ใต้หน้านี้แล้ว)
func _own(n: Node) -> void:
	_to_own.append(n)
