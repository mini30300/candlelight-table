class_name DressingScreen
extends Control
## ห้องแต่งตัว (PACK_SPEC §9 สถานี "dressing"; มีแค่ในแอปส่วนตัวที่มีห้องเสริม): เลือกตัวที่ออกมาเดิน ชุดสีสำเร็จรูป
## บันทึก 3 ช่อง · ข้อมูลทั้งหมดมาจาก Figures (app/figures.gd: list, entry, make, schemes, selected, select, slots, save_slot)
## ภาพตัวอย่างหมุนในโลกของตัวเอง (SubViewport) · min: ไม่หมุนเอง วาดใหม่เฉพาะตอนเปลี่ยนหรือถูกลาก ไม่มีงานต่อเฟรม
## "ใช้ตัวนี้" = Figures.select แล้วปิด (closed(true)) ห้องที่เปิดมาสร้างตัวผู้เล่นใหม่ · ‹ กลับ / Esc = ปิดเฉย ๆ
## จอกว้าง: ซ้าย = ภาพ ชุดสี ปุ่มใช้ตัวนี้ (เห็นเสมอ) ขวา = รายชื่อตัวละคร (เลื่อนได้) กับช่องบันทึก · จอแคบ/แนวตั้ง: บนลงล่าง

signal closed(used: bool)

const FIGURES := "res://app/figures.gd"
const SLOTS := 3
const TITLE := "ห้องแต่งตัว"
const BACK_TEXT := "‹ กลับ"
const CHARS := "ตัวละคร"
const SCHEMES := "ชุดสี"
const OWN_COLOURS := "ตัวนี้ใช้สีของตัวเอง"
const SLOTS_TEXT := "ช่องบันทึก"
const SLOT := "ช่อง {n}"
const EMPTY := "ว่าง"
const SAVE := "บันทึก"
const SAVED := "บันทึกช่อง {n} แล้ว"
const USE := "ใช้ตัวนี้"
const DRAG := "ลากเพื่อหมุน"
const ORIGINAL := "เดิม"
const SPIN := 0.35
const DRAG_TURN := 0.012
const FOV := 30.0
const BG := Color(0.075, 0.066, 0.09)
const SWATCH := 58.0
const SIDE_W := 600.0
const NARROW := 820.0

## เทสใส่ Figures ตัวแทนได้ (null = ไฟล์ที่ path) · path ชี้ไฟล์ที่ไม่มี = ห้องแต่งตัวยังไม่พร้อม
static var api: Object = null
static var path := FIGURES

var level := "mid"
var touch_mode := false
var figure_id := ""
var scheme_id := ""
var spinning := false

var _api: Object
var _list: Array = []
var _schemes: Array = []
var _used := false
var _closing := false
var _note := ""
var _note_n := 0
var _yaw := 0.55
var _dragging := false

var _margin: MarginContainer
var _back: Button
var _title: Label
var _body: BoxContainer
var _left: VBoxContainer
var _view: SubViewportContainer
var _vp: SubViewport
var _cam: Camera3D
var _pivot: Node3D
var _fig: Node3D
var _drag_label: Label
var _side: PanelContainer
var _chars_label: Label
var _chars: GridContainer
var _scheme_label: Label
var _swatches: HFlowContainer
var _own_label: Label
var _slots_label: Label
var _slot_box: VBoxContainer
var _note_label: Label
var _use: Button


## Figures ที่ใช้อยู่ (ตัวแทนของเทส หรือ app/figures.gd) · null = ยังไม่มีไฟล์
static func figures_api() -> Object:
	if api != null:
		return api
	return load(path) if ResourceLoader.exists(path) else null


## ทาชุดสีที่เลือกให้ตัว fig (H10 apply_scheme ถ้ามีและตัวนั้นรับชุดสี) ชิ้นสีตายตัวเป็นเรื่องของตัวนั้นเอง
static func paint(fig: Node, f: Object, fig_id: String, sch_id: String) -> void:
	if fig == null or f == null or not fig.has_method("apply_scheme"):
		return
	var e: Variant = f.call("entry", StringName(fig_id))
	if not e is Dictionary or not bool((e as Dictionary).get("schemes", false)):
		return
	for s: Dictionary in f.call("schemes"):
		if str(s.get("id", "")) == sch_id:
			if not bool(s.get("original", false)):
				fig.call("apply_scheme", s["primary"], s["secondary"])
			return


func _ready() -> void:
	_api = figures_api()
	level = App.gfx
	touch_mode = App.touch_active()
	_build()
	if _api != null:
		_list = _api.call("list")
		_schemes = _api.call("schemes")
		var sel: Dictionary = _api.call("selected")
		figure_id = str(sel.get("figure", ""))
		scheme_id = str(sel.get("scheme", ""))
	if _index(figure_id) < 0 and not _list.is_empty():
		figure_id = str(_list[0]["id"])
	if scheme_id == "" and not _schemes.is_empty():
		scheme_id = str(_schemes[0]["id"])
	spinning = level != "min"
	_fill_chars()
	_fill_swatches()
	refresh()
	_show_figure()
	get_viewport().size_changed.connect(_layout)
	visibility_changed.connect(_apply_mode)
	_layout()


## อ่านภาษาใหม่แล้ววาดข้อความทั้งหมด
func refresh() -> void:
	_back.text = I18n.t(BACK_TEXT)
	_title.text = I18n.t(TITLE)
	_chars_label.text = I18n.t(CHARS)
	_slots_label.text = I18n.t(SLOTS_TEXT)
	_own_label.text = I18n.t(OWN_COLOURS)
	_use.text = I18n.t(USE)
	_drag_label.text = I18n.t(DRAG)
	for b: Button in char_buttons():
		b.text = PackRooms.text(_list[int(b.get_meta(&"i"))]["name"])
		b.set_pressed_no_signal(str(b.get_meta(&"id")) == figure_id)
	var fixed := not _takes_schemes()
	for b: Button in swatch_buttons():
		b.disabled = fixed
		b.tooltip_text = PackRooms.text(_scheme(str(b.get_meta(&"id"))).get("name"))
		if bool(_scheme(str(b.get_meta(&"id"))).get("original", false)):
			b.text = I18n.t(ORIGINAL)
		b.set_pressed_no_signal(str(b.get_meta(&"id")) == scheme_id)
	_own_label.visible = fixed
	var sn := PackRooms.text(_scheme(scheme_id).get("name"))
	_scheme_label.text = I18n.t(SCHEMES) + ("" if fixed or sn == "" else " · " + sn)
	_fill_slots()
	_note_label.text = I18n.t(_note).format({"n": _note_n}) if _note != "" else ""
	_use.disabled = _api == null or figure_id == ""


# ---- การกด (เทสเรียกตรงได้) ----

func pick_figure(id: String) -> void:
	if _index(id) < 0 or id == figure_id and _fig != null:
		return
	figure_id = id
	_note = ""
	refresh()
	_show_figure()


func pick_scheme(id: String) -> void:
	if _scheme(id).is_empty() or not _takes_schemes():
		return
	scheme_id = id
	_note = ""
	refresh()
	_repaint()


func save_slot(i: int) -> void:
	if _api == null or i < 0 or i >= SLOTS or figure_id == "":
		return
	_api.call("save_slot", i, StringName(figure_id), StringName(scheme_id))
	_note = SAVED
	_note_n = i + 1
	refresh()


## โหลดช่อง i (ว่างหรือตัวที่ไม่มีแล้ว = ไม่ทำอะไร)
func load_slot(i: int) -> void:
	var s := _slot(i)
	if s.is_empty() or _index(str(s.get("figure", ""))) < 0:
		return
	if not _scheme(str(s.get("scheme", ""))).is_empty():
		scheme_id = str(s["scheme"])
	_note = ""
	var same := str(s["figure"]) == figure_id
	figure_id = str(s["figure"])
	refresh()
	if same:
		_repaint()
	else:
		_show_figure()


## ทาชุดสีใหม่ให้ตัวอย่าง · สีเดิม = สร้างตัวใหม่ (ล้างสีที่ทาไว้)
func _repaint() -> void:
	if bool(_scheme(scheme_id).get("original", false)):
		_show_figure()
	else:
		paint(_fig, _api, figure_id, scheme_id)
		_redraw()


## ใช้ตัวนี้: บันทึกการเลือก (Figures ส่ง App.figure_changed) แล้วปิดหน้า
func use_selection() -> void:
	if _api == null or figure_id == "" or _closing:
		return
	_api.call("select", StringName(figure_id), StringName(scheme_id))
	_used = true
	close()


func close() -> void:
	if _closing:
		return
	_closing = true
	_clear_figure()
	closed.emit(_used)
	if App.current() == self:
		App.pop()


func handle_back() -> bool:
	close()
	return true


func used() -> bool:
	return _used


func char_buttons() -> Array[Button]:
	return _buttons(_chars)


func swatch_buttons() -> Array[Button]:
	return _buttons(_swatches)


## ปุ่มโหลด (ซ้าย) ของแต่ละช่อง
func slot_buttons() -> Array[Button]:
	var out: Array[Button] = []
	for row in _slot_box.get_children():
		out.append(row.get_child(0) as Button)
	return out


func save_buttons() -> Array[Button]:
	var out: Array[Button] = []
	for row in _slot_box.get_children():
		out.append(row.get_child(1) as Button)
	return out


func preview_figure() -> Node3D:
	return _fig


func preview_viewport() -> SubViewport:
	return _vp


func use_button() -> Button:
	return _use


func narrow() -> bool:
	return _body != null and _body.vertical


# ---- ภายใน ----

func _build() -> void:
	var bg := ColorRect.new()
	bg.color = CandleStyle.BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	_margin = MarginContainer.new()
	_margin.name = "Safe"
	_margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_margin)
	var col := VBoxContainer.new()
	col.add_theme_constant_override(&"separation", 12)
	_margin.add_child(col)
	var top := HBoxContainer.new()
	top.add_theme_constant_override(&"separation", 16)
	col.add_child(top)
	_back = Button.new()
	_back.name = "BackButton"
	_back.custom_minimum_size = Vector2(140.0, 56.0)
	CandleStyle.button(_back)
	_back.pressed.connect(close)
	top.add_child(_back)
	_title = Label.new()
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	CandleStyle.title(_title, 34)
	top.add_child(_title)
	_body = BoxContainer.new()
	_body.name = "Body"
	_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_body.add_theme_constant_override(&"separation", 14)
	col.add_child(_body)
	_left = VBoxContainer.new()
	_left.name = "Left"
	_left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_left.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_left.add_theme_constant_override(&"separation", 10)
	_body.add_child(_left)
	_build_preview()
	_scheme_label = _label(_left, 24)
	_swatches = HFlowContainer.new()
	_swatches.name = "Swatches"
	_swatches.add_theme_constant_override(&"h_separation", 10)
	_swatches.add_theme_constant_override(&"v_separation", 10)
	_left.add_child(_swatches)
	_own_label = _label(_left, 19, true)
	_use = Button.new()
	_use.name = "UseButton"
	CandleStyle.button(_use, true)
	_use.pressed.connect(use_selection)
	_left.add_child(_use)
	_side = PanelContainer.new()
	_side.name = "Side"
	CandleStyle.panel(_side)
	_body.add_child(_side)
	var box := VBoxContainer.new()
	box.add_theme_constant_override(&"separation", 10)
	_side.add_child(box)
	_chars_label = _label(box, 24)
	var scroll := ScrollContainer.new()
	scroll.name = "CharScroll"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(scroll)
	_chars = GridContainer.new()
	_chars.name = "Chars"
	_chars.columns = 2
	_chars.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_chars.add_theme_constant_override(&"h_separation", 8)
	_chars.add_theme_constant_override(&"v_separation", 8)
	scroll.add_child(_chars)
	_slots_label = _label(box, 24)
	_slot_box = VBoxContainer.new()
	_slot_box.name = "Slots"
	_slot_box.add_theme_constant_override(&"separation", 8)
	box.add_child(_slot_box)
	for i in SLOTS:
		var row := HBoxContainer.new()
		row.add_theme_constant_override(&"separation", 8)
		_slot_box.add_child(row)
		var ld := Button.new()
		ld.name = "Slot%d" % i
		ld.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		ld.clip_text = true
		ld.alignment = HORIZONTAL_ALIGNMENT_LEFT
		CandleStyle.button(ld)
		ld.pressed.connect(load_slot.bind(i))
		row.add_child(ld)
		var sv := Button.new()
		sv.name = "Save%d" % i
		CandleStyle.button(sv)
		sv.pressed.connect(save_slot.bind(i))
		row.add_child(sv)
	_note_label = _label(box, 19, true)
	for b: Button in [_back, _use]:
		b.focus_mode = Control.FOCUS_NONE


func _label(parent: Control, size: int, muted := false) -> Label:
	var l := Label.new()
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	CandleStyle.text(l, size, muted)
	parent.add_child(l)
	return l


func _build_preview() -> void:
	_view = SubViewportContainer.new()
	_view.name = "Preview"
	_view.stretch = true
	_view.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_view.mouse_filter = Control.MOUSE_FILTER_STOP
	_view.gui_input.connect(_on_view_input)
	_view.resized.connect(_frame)
	_left.add_child(_view)
	_vp = SubViewport.new()
	_vp.own_world_3d = true
	_vp.msaa_3d = Viewport.MSAA_DISABLED
	_vp.handle_input_locally = false
	_vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	_view.add_child(_vp)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = BG
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.55, 0.55, 0.6)
	var we := WorldEnvironment.new()
	we.environment = env
	_vp.add_child(we)
	# ไฟดวงเดียวให้วัสดุแบบมีแสง (ตัวชุดเสริมคำนวณแสงเอง ไม่สนไฟนี้)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(deg_to_rad(-55.0), deg_to_rad(35.0), 0.0)
	_vp.add_child(sun)
	_cam = Camera3D.new()
	_cam.fov = FOV
	_cam.current = true
	_vp.add_child(_cam)
	_pivot = Node3D.new()
	_pivot.name = "Pivot"
	_vp.add_child(_pivot)
	var disc := CylinderMesh.new()
	disc.top_radius = 0.75
	disc.bottom_radius = 0.75
	disc.height = 0.07
	disc.radial_segments = 32
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.2, 0.185, 0.23)
	disc.material = mat
	var mi := MeshInstance3D.new()
	mi.mesh = disc
	mi.position.y = -0.035
	_vp.add_child(mi)
	_drag_label = Label.new()
	CandleStyle.text(_drag_label, 17, true)
	_drag_label.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT, Control.PRESET_MODE_KEEP_SIZE, 10)
	_drag_label.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_drag_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_view.add_child(_drag_label)


func _fill_chars() -> void:
	var group := ButtonGroup.new()
	for i in _list.size():
		var b := Button.new()
		b.name = "Char_" + str(_list[i]["id"])
		b.toggle_mode = true
		b.button_group = group
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.clip_text = true
		b.focus_mode = Control.FOCUS_NONE
		b.set_meta(&"i", i)
		b.set_meta(&"id", str(_list[i]["id"]))
		CandleStyle.button(b)
		b.add_theme_font_size_override(&"font_size", 19)
		b.pressed.connect(pick_figure.bind(str(_list[i]["id"])))
		_chars.add_child(b)


func _fill_swatches() -> void:
	var group := ButtonGroup.new()
	for s: Dictionary in _schemes:
		var b := Button.new()
		b.name = "Scheme_" + str(s["id"])
		b.toggle_mode = true
		b.button_group = group
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(SWATCH, SWATCH)
		b.set_meta(&"id", str(s["id"]))
		b.add_theme_font_size_override(&"font_size", 15)
		var p: Color = s["primary"]
		var q: Color = s["secondary"]
		# สีหลักเต็มปุ่ม ขอบเป็นสีรอง · เลือกอยู่ = ขอบทองหนา
		b.add_theme_stylebox_override(&"normal", _swatch_box(p, q, 4))
		b.add_theme_stylebox_override(&"hover", _swatch_box(p, CandleStyle.TEXT, 4))
		b.add_theme_stylebox_override(&"pressed", _swatch_box(p, CandleStyle.GOLD, 7))
		b.add_theme_stylebox_override(&"hover_pressed", _swatch_box(p, CandleStyle.GOLD, 7))
		b.add_theme_stylebox_override(&"disabled", _swatch_box(Color(p, 0.3), Color(q, 0.3), 4))
		b.pressed.connect(pick_scheme.bind(str(s["id"])))
		_swatches.add_child(b)


func _swatch_box(fill: Color, edge: Color, w: int) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = fill
	sb.border_color = edge
	sb.set_border_width_all(w)
	sb.set_corner_radius_all(int(SWATCH * 0.5))
	return sb


func _fill_slots() -> void:
	var sl := slot_buttons()
	var sv := save_buttons()
	for i in SLOTS:
		var s := _slot(i)
		var nm := I18n.t(EMPTY)
		if not s.is_empty() and _index(str(s.get("figure", ""))) >= 0:
			nm = PackRooms.text(_list[_index(str(s["figure"]))]["name"])
			var sn := PackRooms.text(_scheme(str(s.get("scheme", ""))).get("name"))
			if sn != "" and bool(_list[_index(str(s["figure"]))].get("schemes", false)):
				nm += " · " + sn
		sl[i].text = I18n.t(SLOT).format({"n": i + 1}) + ": " + nm
		sl[i].disabled = s.is_empty()
		sv[i].text = I18n.t(SAVE)
		sv[i].disabled = _api == null or figure_id == ""


func _slot(i: int) -> Dictionary:
	if _api == null:
		return {}
	var all: Array = _api.call("slots")
	return all[i] if i < all.size() and all[i] is Dictionary else {}


func _index(id: String) -> int:
	for i in _list.size():
		if str(_list[i]["id"]) == id:
			return i
	return -1


func _scheme(id: String) -> Dictionary:
	for s: Dictionary in _schemes:
		if str(s["id"]) == id:
			return s
	return {}


func _takes_schemes() -> bool:
	var i := _index(figure_id)
	return i >= 0 and bool(_list[i].get("schemes", false))


func _buttons(parent: Node) -> Array[Button]:
	var out: Array[Button] = []
	for c in parent.get_children():
		if c is Button:
			out.append(c)
	return out


## สร้างตัวอย่างใหม่จาก Figures.make (null = ไข่สีทีม)
func _show_figure() -> void:
	_clear_figure()
	if _api == null or figure_id == "":
		_redraw()
		return
	var team := HallWorld.slot_colour(0)
	var fig: Variant = _api.call("make", StringName(figure_id), StringName(level))
	if fig is Node3D:
		_fig = fig
		_pivot.add_child(_fig)
		if _fig.has_method("setup"):
			_fig.call("setup", {"role": &"deck", "level": level, "team_colour": team, "seed": 0})
			_fig.call("set_weapon", &"none")
			_fig.call("play", &"idle", 1.0)
			_fig.call("set_move", 0.0, false)
		paint(_fig, _api, figure_id, scheme_id)
	else:
		var egg := MeshInstance3D.new()
		egg.name = "Egg"
		egg.mesh = HallBuilder.avatar_mesh(team, 24)
		egg.material_override = HallBuilder.material()
		_fig = egg
		_pivot.add_child(_fig)
	_frame()


func _clear_figure() -> void:
	if _fig != null:
		_fig.get_parent().remove_child(_fig)
		_fig.queue_free()
		_fig = null


## กล้องเห็นทั้งตัว (กล่องของเมช ไม่เจอใช้ 1.8 ม.)
func _frame() -> void:
	if _cam == null:
		return
	var box := _box(_fig) if _fig != null else AABB()
	if box.size.y < 0.3:
		box = AABB(Vector3(-0.4, 0.0, -0.4), Vector3(0.8, 1.8, 0.8))
	var half := box.size * 0.5
	var aspect := _view.size.x / _view.size.y if _view.size.y > 0.0 else 1.0
	var tan_v := tan(deg_to_rad(FOV * 0.5))
	var foot := maxf(0.5, Vector2(half.x, half.z).length())
	var dist := maxf((half.y + 0.15) / tan_v, foot / (tan_v * maxf(aspect, 0.2))) * 1.15 + foot
	var look := Vector3(0.0, box.position.y + half.y, 0.0)
	var eye := look + Vector3(0.0, sin(0.25), cos(0.25)) * dist
	_cam.transform = Transform3D(Basis.looking_at(look - eye, Vector3.UP), eye)
	_cam.far = dist * 4.0 + 10.0
	_pivot.rotation.y = _yaw
	_redraw()


static func _box(root: Node3D) -> AABB:
	var out := AABB()
	var first := true
	var stack: Array = [[root, Transform3D.IDENTITY]]
	while not stack.is_empty():
		var it: Array = stack.pop_back()
		var n: Node = it[0]
		var t: Transform3D = it[1]
		if n is Node3D and n != root:
			t = t * (n as Node3D).transform
		if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
			var b: AABB = t * (n as MeshInstance3D).get_aabb()
			out = b if first else out.merge(b)
			first = false
		for c in n.get_children():
			stack.append([c, t])
	return out


func _layout() -> void:
	if not is_inside_tree():
		return
	CandleStyle.safe_margins(_margin)
	var vs := get_viewport_rect().size
	_body.vertical = vs.x < NARROW or vs.x < vs.y * 1.1
	_view.custom_minimum_size = Vector2(0.0, vs.y * (0.3 if _body.vertical else 0.25))
	_side.custom_minimum_size = Vector2(0.0, vs.y * 0.4) if _body.vertical else Vector2(minf(SIDE_W, vs.x * 0.42), 0.0)
	_side.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var h := 64.0 if touch_mode else 56.0
	for b: Button in char_buttons() + slot_buttons() + save_buttons() + [_use]:
		b.custom_minimum_size.y = h
	_apply_mode()


func _apply_mode() -> void:
	if _vp == null:
		return
	var run := spinning and is_visible_in_tree()
	set_process(run)
	if run:
		_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	elif is_visible_in_tree():
		_vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	else:
		_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED


func _redraw() -> void:
	if _vp != null and not (spinning and is_visible_in_tree()):
		_vp.render_target_update_mode = SubViewport.UPDATE_ONCE


func _process(delta: float) -> void:
	_yaw = fmod(_yaw + SPIN * delta, TAU)
	_pivot.rotation.y = _yaw


func _on_view_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		_dragging = (event as InputEventMouseButton).pressed
	elif event is InputEventScreenTouch:
		_dragging = (event as InputEventScreenTouch).pressed
	elif (event is InputEventMouseMotion or event is InputEventScreenDrag) and _dragging:
		var rel: Vector2 = event.get("relative")
		_yaw = fmod(_yaw + rel.x * DRAG_TURN, TAU)
		_pivot.rotation.y = _yaw
		_redraw()
