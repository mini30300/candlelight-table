class_name MissionBrief
extends PanelContainer
## บรีฟภารกิจ (CAMPAIGN_SPEC §1.5): ชื่อภารกิจ เป้าหมายหลัก เป้าหมายรอง (เหตุการณ์อื่นบนดาวเดียวกัน) ผู้รุกราน ความยาก
## ตัวคูณ รางวัลประมาณ · "ออกรบ" = launch_pressed (GalaxyScreen ทำจอมืดแล้วเรียก CampaignFlow.launch) · ‹ กลับ = back_pressed
## ไม่มีงานต่อเฟรม

signal launch_pressed
signal back_pressed

const TITLE := "บรีฟภารกิจ"
const BACK_TEXT := "‹ กลับ"
const LAUNCH := "ออกรบ"
const MAIN := "เป้าหมายหลัก"
const SIDE := "เป้าหมายรอง: {goal}"
const NO_SIDE := "ไม่มีเป้าหมายรอง"
const INVADERS := "ผู้รุกราน: {faction} · {modifier}"
const DIFF := "ความยาก: {name} {mult}"
const REWARD := "รางวัลประมาณ {n} เหรียญ"
const FEATURED := "ดาวเด่นสัปดาห์นี้ · เหรียญ ×1.5"

var spec: Dictionary = {}

var _icon: PlanetCard.Icon
## ชื่อภารกิจ + "เป้าหมายหลัก" / รายละเอียดทั้งหมด: ข้อความหลายสีสองก้อน (draw call น้อย)
var _head: RichTextLabel
var _body: RichTextLabel
var _side: PackedStringArray = []
var _back: Button
var _launch: Button


func _ready() -> void:
	CandleStyle.panel(self)
	var col := VBoxContainer.new()
	col.add_theme_constant_override(&"separation", 8)
	add_child(col)
	var top := HBoxContainer.new()
	top.add_theme_constant_override(&"separation", 10)
	col.add_child(top)
	_icon = PlanetCard.Icon.new()
	_icon.custom_minimum_size = Vector2(60, 60)
	_icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	top.add_child(_icon)
	# หัวบรีฟ: "บรีฟภารกิจ" ดาว ชื่อภารกิจ เป้าหมายหลัก ในข้อความเดียว
	_head = PlanetCard.rich(22)
	_head.name = "Head"
	_head.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_head.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_head.add_theme_font_override(&"normal_font", CandleStyle.BOLD)
	top.add_child(_head)
	# ปุ่มกลับแบบตัวอักษรอย่างเดียว (draw call น้อย) ยังกดง่าย 52 px
	_back = Button.new()
	_back.name = "BriefBack"
	_back.flat = true
	_back.custom_minimum_size = Vector2(110, 52)
	_back.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	_back.focus_mode = Control.FOCUS_NONE
	_back.add_theme_font_override(&"font", CandleStyle.BOLD)
	_back.add_theme_font_size_override(&"font_size", 22)
	for k in [&"font_color", &"font_hover_color", &"font_pressed_color", &"font_hover_pressed_color"]:
		_back.add_theme_color_override(k, CandleStyle.GOLD)
	_back.pressed.connect(func() -> void: back_pressed.emit())
	top.add_child(_back)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(scroll)
	_body = PlanetCard.rich(20)
	_body.name = "Body"
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_body)
	_launch = Button.new()
	_launch.name = "LaunchButton"
	CandleStyle.button(_launch, true)
	_launch.custom_minimum_size.y = 64
	_launch.add_theme_font_size_override(&"font_size", 26)
	_launch.focus_mode = Control.FOCUS_NONE
	_launch.pressed.connect(func() -> void: launch_pressed.emit())
	col.add_child(_launch)


func show_spec(s: Dictionary) -> void:
	spec = s
	refresh()


func launch_button() -> Button:
	return _launch


## เป้าหมายรองที่โชว์อยู่ (ข้อความ) สำหรับเทส
func side_lines() -> PackedStringArray:
	return _side


## ข้อความทั้งหมดของบรีฟ (เทส)
func text() -> String:
	return _head.get_parsed_text() + "\n" + _body.get_parsed_text()


func refresh() -> void:
	if _head == null or spec.is_empty():
		return
	_back.text = I18n.t(BACK_TEXT)
	_launch.text = I18n.t(LAUNCH)
	var p := CampaignGalaxy.planet(str(spec["planet"]))
	var biome := I18n.t(str(CampaignGalaxy.BIOMES.get(str(p.get("biome", "")), "")))
	var t := str(spec["primary"]["type"])
	_icon.type = t
	_icon.col = CandleStyle.GOLD
	_icon.queue_redraw()
	# ขนาดเดียว แบบอักษรเดียว (แผ่นอักษรเดียว = draw call เดียว) แยกด้วยสี
	_head.text = "%s\n%s\n%s\n%s" % [PlanetCard.colour(I18n.t(TITLE), CandleStyle.GOLD),
		PlanetCard.colour(I18n.t(str(p.get("th", ""))) + " · " + biome, CandleStyle.MUTED),
		PlanetCard.colour(I18n.t(MissionTypes.name_th(t)), Color.WHITE), PlanetCard.colour(I18n.t(MAIN), CandleStyle.MUTED)]
	var lines := PackedStringArray([PlanetCard.esc(I18n.t(MissionTypes.goal_th(t)))])
	_side = PackedStringArray()
	var sec: Array = spec.get("secondary", [])
	if sec.is_empty():
		_side.append(I18n.t(NO_SIDE))
	for e: Dictionary in sec:
		_side.append(I18n.t(SIDE).format({"goal": I18n.t(MissionTypes.secondary_th(str(e["type"])))}))
	for l in _side:
		lines.append(PlanetCard.colour(l, CandleStyle.MUTED if sec.is_empty() else CandleStyle.TEXT))
	var f := CampaignGalaxy.faction(str(spec["faction"]))
	lines.append(PlanetCard.colour(I18n.t(INVADERS).format({"faction": I18n.t(str(f.get("th", ""))),
		"modifier": I18n.t(str(CampaignGalaxy.modifier(str(spec["modifier"])).get("th", "")))}),
		Color(str(f.get("col", "888888"))).lightened(0.3)))
	var d := CampaignRules.difficulty(str(spec["difficulty"]))
	lines.append(PlanetCard.esc(I18n.t(DIFF).format({"name": I18n.t(str(d["th"])), "mult": CampaignRules.mult_text(str(d["id"]))})))
	var rw := I18n.t(REWARD).format({"n": CampaignRules.estimate_coins(spec, CampaignSave.is_repeat(spec))})
	if bool(spec.get("featured", false)):
		rw += "  ·  " + I18n.t(FEATURED)
	lines.append(PlanetCard.colour(rw, GalaxyMap.GOLD))
	_body.text = "\n".join(lines)
