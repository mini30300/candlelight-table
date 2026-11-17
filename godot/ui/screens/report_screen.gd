class_name ReportScreen
extends Control
## หน้าสรุปผลภารกิจ (CAMPAIGN_SPEC §1.7): ผล (สำเร็จ / ล้มเหลว / ถอนตัว) ดาว ภารกิจ ความยาก
## แถวสถิติ: สังหาร ความแม่นยำ เวลา ความเสียหาย จำนวนครั้งที่ล้ม เป้าหมายที่ทำได้ · บรรทัดคะแนน (CampaignRules.score)
## รวมก่อนคูณ ตัวคูณความยาก คะแนน เกรด เหรียญที่ได้ โบนัส (ดาวเด่น / เล่นซ้ำ) และเหรียญทั้งหมด (บันทึกในเครื่องแล้ว)
## hi/mid นับเลขขึ้นด้วย Tween เดียว (≤ 1.2 วิ) · lo/min โชว์เลขสุดท้ายทันที ไม่มี Tween
## ข้อความรวมเป็นก้อนน้อยก้อน (กล่องสถิติวาดในโหนดเดียว บรรทัดคะแนนเป็นตารางเดียว) draw call น้อยบนเครื่องอ่อน
## ปุ่ม: เล่นอีกครั้ง (CampaignFlow.retry) · กลับแผนที่กาแล็กซี (Esc) · กลับยาน (CampaignFlow.leave)

const SCENE := "res://ui/screens/report_screen.tscn"
const WIN := "ผลภารกิจ: สำเร็จ"
const FAIL := "ผลภารกิจ: ล้มเหลว"
const QUIT := "ผลภารกิจ: ถอนตัว"
const KILLS := "สังหารศัตรู"
const ACCURACY := "ความแม่นยำ"
const TIME := "เวลาที่ใช้"
const DAMAGE := "ความเสียหายที่ได้รับ"
const DOWNS := "จำนวนครั้งที่ล้ม"
const OBJECTIVES := "เป้าหมายที่ทำได้"
const RAW := "รวมก่อนคูณ {raw}"
const MULT := "ตัวคูณความยาก {name} {mult}"
const TOTAL := "คะแนน {total}"
const GRADE := "เกรด"
const EARNED := "+{coins} เหรียญ"
const WALLET := "เหรียญทั้งหมด {n}"
const FEATURED := "โบนัสดาวเด่น ×1.5"
const REPEAT := "เล่นซ้ำในสัปดาห์นี้ · เหรียญ 25 %"
const RETRY := "เล่นอีกครั้ง"
const TO_GALAXY := "กลับแผนที่กาแล็กซี"
const TO_SHIP := "กลับยาน"
const COUNT_TIME := 1.0
const MAX_W := 1000.0
const WIDE := 900.0

var spec: Dictionary = {}
var result: Dictionary = {}
var score: Dictionary = {}
var wallet := 0
var level := "mid"
## ความคืบหน้าของการนับเลข 0..1 (Tween ตั้งค่านี้)
var progress := 1.0:
	set(v):
		progress = clampf(v, 0.0, 1.0)
		_apply_numbers()

var _margin: MarginContainer
var _title: Label
var _sub: Label
var _tiles: Tiles
var _body: BoxContainer
var _lines: RichTextLabel
var _total: Label
## "เกรด" + ตัวอักษรเกรดใหญ่
var _grade: RichTextLabel
var _reward: RichTextLabel
var _retry: Button
var _galaxy: Button
var _ship: Button
var _tween: Tween
var _shown := {}
var _lines_w := 0.0


## กล่องสถิติทั้งหมดในโหนดเดียว: พื้นกล่องเป็นสามเหลี่ยมชุดเดียว ชื่อ (ตัวธรรมดา) แล้วตัวเลข (ตัวหนา)
class Tiles:
	extends Control
	const W := 150.0
	const H := 86.0
	const GAP := 10.0
	## [[ชื่อ, ค่า]]
	var data: Array = []

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		resized.connect(_reflow)

	func set_data(d: Array) -> void:
		data = d
		_reflow()

	func _per_row() -> int:
		return maxi(int((size.x + GAP) / (W + GAP)), 1)

	func _reflow() -> void:
		var rows := ceili(float(data.size()) / _per_row())
		custom_minimum_size.y = maxf(rows * (H + GAP) - GAP, 0.0)
		queue_redraw()

	func box(i: int) -> Rect2:
		var n := _per_row()
		return Rect2((i % n) * (W + GAP), (i / n) * (H + GAP), W, H)

	func _draw() -> void:
		if data.is_empty():
			return
		var pen := GalaxyMap.Pen.new()
		var bg := Color(0.17, 0.115, 0.08, 0.95)
		for i in data.size():
			var r := box(i)
			var tr := r.position + Vector2(r.size.x, 0)
			var bl := r.position + Vector2(0, r.size.y)
			pen.tri(r.position, tr, r.end, bg)
			pen.tri(r.position, r.end, bl, bg)
			for e: Array in [[r.position, tr], [bl, r.end], [r.position, bl], [tr, r.end]]:
				pen.line(e[0], e[1], 1.5, CandleStyle.EDGE)
		pen.draw(self)
		var font := get_theme_default_font()
		for i in data.size():
			var r := box(i)
			draw_string(font, r.position + Vector2(10, 26), str(data[i][0]), HORIZONTAL_ALIGNMENT_LEFT, W - 16, 15, CandleStyle.MUTED)
		for i in data.size():
			var r := box(i)
			draw_string(CandleStyle.BOLD, r.position + Vector2(10, 70), str(data[i][1]), HORIZONTAL_ALIGNMENT_LEFT, W - 16, 30, CandleStyle.TEXT)


func _ready() -> void:
	level = App.gfx
	_build()
	get_viewport().size_changed.connect(_layout)
	resized.connect(_layout)
	_layout()


## เรียกหลัง App.replace ทันที: ctx = {"spec", "result", "score" (CampaignRules.score), "coins" (เหรียญทั้งหมดหลังบันทึก)}
func open(ctx: Dictionary) -> void:
	spec = ctx.get("spec", {})
	result = ctx.get("result", {})
	score = ctx.get("score", {})
	wallet = int(ctx.get("coins", 0))
	refresh()
	if level == "hi" or level == "mid":
		progress = 0.0
		_tween = create_tween()
		_tween.tween_property(self, ^"progress", 1.0, COUNT_TIME).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	else:
		progress = 1.0


## นับเลขจบทันที (เทส / แตะข้าม)
func finish_count() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	progress = 1.0


func counting() -> bool:
	return _tween != null and _tween.is_valid() and _tween.is_running()


func refresh() -> void:
	if _title == null:
		return
	var outcome := str(result.get("outcome", ""))
	_title.text = I18n.t(WIN if outcome == "win" else (QUIT if outcome == "quit" else FAIL))
	_title.add_theme_color_override(&"font_color", CandleStyle.GOLD if outcome == "win" else CandleStyle.DANGER)
	var p := CampaignGalaxy.planet(str(spec.get("planet", "")))
	var t := str((spec.get("primary", {}) as Dictionary).get("type", ""))
	var d := CampaignRules.difficulty(str(spec.get("difficulty", "normal")))
	_sub.text = "%s · %s · %s %s" % [I18n.t(str(p.get("th", ""))), I18n.t(MissionTypes.name_th(t)), I18n.t(str(d["th"])),
		CampaignRules.mult_text(str(d["id"]))]
	_tiles.set_data(_tile_data())
	_grade.text = "[center][font_size=22]%s[/font_size]\n[font_size=96]%s[/font_size][/center]" % [PlanetCard.colour(I18n.t(GRADE), CandleStyle.MUTED),
		PlanetCard.colour(str(score.get("grade", "-")), CandleStyle.GOLD)]
	_retry.text = I18n.t(RETRY)
	_galaxy.text = I18n.t(TO_GALAXY)
	_ship.text = I18n.t(TO_SHIP)
	_apply_numbers()


## ข้อความทั้งหมดที่โชว์ (เทส): {"title", "sub", "tiles": [[ชื่อ, ค่า]], "lines": [[ชื่อ, ค่า]], "raw", "mult", "total",
## "grade", "earned", "wallet", "notes"}
func shown() -> Dictionary:
	var out := _shown.duplicate()
	out["title"] = _title.text
	out["sub"] = _sub.text
	out["tiles"] = _tiles.data
	out["total"] = _total.text
	out["grade"] = str(score.get("grade", "-")) if _grade.get_parsed_text().ends_with(str(score.get("grade", "-"))) else _grade.get_parsed_text()
	return out


func buttons() -> Array[Button]:
	return [_retry, _galaxy, _ship]


func narrow() -> bool:
	return _body != null and _body.vertical


func retry() -> void:
	CampaignFlow.retry()


func to_galaxy() -> void:
	CampaignFlow.back_to_galaxy()


func to_ship() -> void:
	CampaignFlow.leave()


## Esc / ปุ่มย้อนกลับ = กลับแผนที่กาแล็กซี
func handle_back() -> bool:
	to_galaxy()
	return true


# ---- ภายใน ----

## ครั้งนี้เป็นการเล่นซ้ำ (เหรียญ 25 %): CampaignFlow ใส่ score.repeat ไว้ก่อนบันทึก
func _was_repeat() -> bool:
	return bool(score.get("repeat", false))


func _tile_data() -> Array:
	var kills := 0
	for k: Variant in (result.get("kills", {}) as Dictionary).values():
		kills += maxi(int(k), 0)
	var shots := int(result.get("shots", 0))
	var acc := "-" if shots <= 0 else "%d %%" % int(score.get("acc_pct", 0))
	var ts := maxi(int(float(result.get("time_s", 0.0))), 0)
	var done := (1 if str(result.get("outcome", "")) == "win" else 0)
	for s: Variant in (result.get("secondary_done", []) as Array):
		if bool(s):
			done += 1
	var total_obj := 1 + (spec.get("secondary", []) as Array).size()
	return [[I18n.t(KILLS), str(kills)], [I18n.t(ACCURACY), acc], [I18n.t(TIME), "%d:%02d" % [ts / 60, ts % 60]],
		[I18n.t(DAMAGE), str(maxi(int(result.get("damage_taken", 0)), 0))],
		[I18n.t(DOWNS), str(maxi(int(result.get("downs", 0)), 0))], [I18n.t(OBJECTIVES), "%d/%d" % [done, total_obj]]]


## เลขตามความคืบหน้าของการนับ (progress 1 = เลขจริง): ตารางคะแนน คะแนนรวม เหรียญ
func _apply_numbers() -> void:
	if _reward == null:
		return
	var p := progress
	var rows := []
	# คอลัมน์ตัวเลขชิดขวาของกล่อง (tab stop ตามความกว้างตอนนี้)
	var stop := maxi(int(_lines.size.x) - 90, 260)
	var bb := ""
	for line: Dictionary in score.get("lines", []):
		var v := int(line["value"])
		var n := roundi(v * p)
		var vt := ("+%d" % n) if n > 0 else str(n)
		var name := I18n.t(str(line["th"]))
		rows.append([name, vt])
		bb += "[p tab_stops=%d]%s\t%s[/p]" % [stop, PlanetCard.esc(name),
			PlanetCard.colour(vt, CandleStyle.DANGER if v < 0 else CandleStyle.TEXT)]
	var d := CampaignRules.difficulty(str(spec.get("difficulty", "normal")))
	var raw_t := I18n.t(RAW).format({"raw": roundi(int(score.get("raw", 0)) * p)})
	var mult_t := I18n.t(MULT).format({"name": I18n.t(str(d["th"])), "mult": CampaignRules.mult_text(str(d["id"]))})
	_lines.text = bb + "\n" + PlanetCard.colour(raw_t, CandleStyle.MUTED) + "\n" + PlanetCard.colour(mult_t, CandleStyle.MUTED)
	_total.text = I18n.t(TOTAL).format({"total": roundi(int(score.get("total", 0)) * p)})
	var c := int(score.get("coins", 0))
	var earned := I18n.t(EARNED).format({"coins": roundi(c * p)})
	var wal := I18n.t(WALLET).format({"n": wallet - c + roundi(c * p)})
	var notes := PackedStringArray()
	if bool(spec.get("featured", false)):
		notes.append(I18n.t(FEATURED))
	if _was_repeat():
		notes.append(I18n.t(REPEAT))
	var rb := "[center]" + PlanetCard.colour(earned, GalaxyMap.GOLD)
	for nt in notes:
		rb += "\n" + PlanetCard.colour(nt, CandleStyle.MUTED)
	rb += "\n" + PlanetCard.esc(wal) + "[/center]"
	_reward.text = rb
	_grade.modulate.a = 1.0 if p >= 1.0 else p * 0.6
	_shown = {"lines": rows, "raw": raw_t, "mult": mult_t, "earned": earned, "wallet": wal, "notes": "\n".join(notes)}


## ความกว้างของตารางคะแนนเปลี่ยน: คอลัมน์ตัวเลขย้ายตาม (ความสูงเปลี่ยนอย่างเดียวไม่ต้องทำ)
func _on_lines_resized() -> void:
	if absf(_lines.size.x - _lines_w) > 1.0:
		_lines_w = _lines.size.x
		_apply_numbers()


func _build() -> void:
	var bg := ColorRect.new()
	bg.color = CandleStyle.BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var scroll := ScrollContainer.new()
	scroll.name = "Scroll"
	scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	_margin = MarginContainer.new()
	_margin.name = "Safe"
	_margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_margin.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.add_child(_margin)
	var col := VBoxContainer.new()
	col.add_theme_constant_override(&"separation", 14)
	_margin.add_child(col)
	_title = Label.new()
	_title.name = "Title"
	_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	CandleStyle.title(_title, 38)
	col.add_child(_title)
	_sub = Label.new()
	_sub.name = "Sub"
	_sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	CandleStyle.text(_sub, 22, true)
	col.add_child(_sub)
	_tiles = Tiles.new()
	_tiles.name = "Stats"
	col.add_child(_tiles)
	_body = BoxContainer.new()
	_body.name = "Body"
	_body.add_theme_constant_override(&"separation", 14)
	col.add_child(_body)
	var left := PanelContainer.new()
	left.name = "Score"
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	CandleStyle.panel(left)
	_body.add_child(left)
	var lv := VBoxContainer.new()
	lv.add_theme_constant_override(&"separation", 6)
	left.add_child(lv)
	_lines = PlanetCard.rich(20)
	_lines.name = "Lines"
	_lines.resized.connect(_on_lines_resized)
	lv.add_child(_lines)
	_total = Label.new()
	_total.name = "Total"
	CandleStyle.title(_total, 30)
	lv.add_child(_total)
	var right := PanelContainer.new()
	right.name = "Reward"
	right.custom_minimum_size.x = 300
	CandleStyle.panel(right)
	_body.add_child(right)
	var rv := VBoxContainer.new()
	rv.add_theme_constant_override(&"separation", 4)
	right.add_child(rv)
	_grade = PlanetCard.rich(22)
	_grade.name = "Grade"
	_grade.add_theme_font_override(&"normal_font", CandleStyle.BOLD)
	rv.add_child(_grade)
	_reward = PlanetCard.rich(22)
	_reward.name = "RewardText"
	rv.add_child(_reward)
	var btns := HFlowContainer.new()
	btns.name = "Buttons"
	btns.add_theme_constant_override(&"h_separation", 12)
	btns.add_theme_constant_override(&"v_separation", 10)
	col.add_child(btns)
	_retry = _button(btns, "RetryButton", false, retry)
	_galaxy = _button(btns, "GalaxyButton", true, to_galaxy)
	_ship = _button(btns, "ShipButton", false, to_ship)


## ปุ่ม: ปุ่มหลักกรอบเทียนทุกระดับ · ปุ่มรองบน min เป็นตัวอักษรทองอย่างเดียว (draw call น้อยลง)
func _button(parent: Control, n: String, primary: bool, cb: Callable) -> Button:
	var b := Button.new()
	b.name = n
	if primary or level != "min":
		CandleStyle.button(b, primary)
	else:
		b.flat = true
		b.add_theme_font_override(&"font", CandleStyle.BOLD)
		b.add_theme_font_size_override(&"font_size", 22)
		for k in [&"font_color", &"font_hover_color", &"font_pressed_color", &"font_hover_pressed_color"]:
			b.add_theme_color_override(k, CandleStyle.GOLD)
	b.custom_minimum_size = Vector2(220, 60)
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(cb)
	parent.add_child(b)
	return b


func _layout() -> void:
	if _margin == null:
		return
	var inset := CandleStyle.safe_insets(self)
	var w := size.x
	var side := maxf((w - MAX_W) * 0.5, 0.0)
	var m := CandleStyle.GUTTER
	_margin.add_theme_constant_override(&"margin_left", int(m + inset.position.x + side))
	_margin.add_theme_constant_override(&"margin_right", int(m + inset.size.x + side))
	_margin.add_theme_constant_override(&"margin_top", int(m + inset.position.y))
	_margin.add_theme_constant_override(&"margin_bottom", int(m + inset.size.y))
	# จอแคบหรือแนวตั้ง: คะแนนกับรางวัลเรียงบนลงล่าง
	_body.vertical = w < WIDE or size.y > w * 1.3
