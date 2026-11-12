extends Control
## หน้าอารีน่าทดสอบอาวุธ (ARENA_SPEC §10.3): ปุ่มและข้อความบนโลก 3 มิติ (ArenaWorld) · ข้อความไทยของอารีน่าอยู่ในไฟล์นี้
## (ป้าย 3 มิติ กระดานสถานะ ปุ่มใช้ แจ้งเตือน แผงหยุดชั่วคราว) HUD การยิงสร้างตอนเปิดจาก ArenaHud (load ตอนใช้)
## เข้ามาใหม่ทุกครั้ง: สัตว์รังเลือดเต็ม บอทปิด ตัวนับศูนย์ กระสุนเต็ม โหมดเดินที่จุดเกิด
## ออก: ‹ ล็อบบี้ / กลับล็อบบี้ / เดินเข้าประตูดาดฟ้า (จอมืดแล้วปิดหน้า) · Esc/ย้อนกลับ = แผงหยุดชั่วคราว (ไม่ออก)
## งานต่อเฟรม: ไม่มี (ข้อความเปลี่ยนตามสัญญาณ แจ้งเตือนปิดด้วย Timer)

const SETTINGS_SCREEN := "res://ui/screens/settings.tscn"
const ARENA_HUD := "res://ui/widgets/arena_hud.gd"
const FADE_TIME := 0.25
const TOAST_SECONDS := 2.0
const LOBBY_TEXT := "‹ ล็อบบี้"
const SETTINGS_TEXT := "ตั้งค่า"
const PROMPT_KEYS := "{name} · กด E"
const PROMPT_TOUCH := "{name} · แตะเพื่อใช้"
const NAMES := {"switch": "สวิตช์บอท", "reset": "รีเซ็ต"}
const SIGN_SWITCH_KEYS := "สวิตช์บอท · ยิงหรือกด E"
const SIGN_SWITCH_TOUCH := "สวิตช์บอท · ยิงหรือแตะใช้"
const SIGN_RESET := "รีเซ็ต"
const SIGN_BACK := "กลับดาดฟ้ายานรบ"
const SIGN_ARENA := "อารีน่าทดสอบอาวุธ"
const BOT_ON := "บอท: เปิด"
const BOT_OFF := "บอท: ปิด"
const HP_LINE := "พลังชีวิต {hp}/{max}"
const HITS_LINE := "โดน {n} ครั้ง · ความเสียหายรวม {d}"
const DOWN_LINE := "ล้มแล้ว · กดรีเซ็ต"
const TOAST_ON := "บอทเปิด — {name}ไล่ตามคุณแล้ว"
const TOAST_ON_DEAD := "บอทเปิด — มีผลหลังรีเซ็ต"
const TOAST_OFF := "บอทปิด — ยืนเป็นเป้านิ่ง"
const TOAST_RESET := "รีเซ็ตแล้ว"
const PAUSE_TITLE := "หยุดชั่วคราว"
const RESUME_TEXT := "เล่นต่อ"
const PAUSE_LOBBY_TEXT := "กลับล็อบบี้"
const USE_H := 64.0
const USE_H_TOUCH := 80.0

@onready var world: ArenaWorld = $ArenaWorld
@onready var margin: MarginContainer = $Safe
@onready var layer: Control = $Safe/Layer
@onready var lobby_button: Button = %LobbyButton
@onready var settings_button: Button = %SettingsButton
@onready var use_button: Button = %UseButton
@onready var toast: Label = %Toast
@onready var toast_timer: Timer = %ToastTimer
@onready var pause_panel: PanelContainer = %PausePanel
@onready var pause_title: Label = %PauseTitle
@onready var resume_button: Button = %ResumeButton
@onready var pause_lobby_button: Button = %PauseLobbyButton
@onready var pause_settings_button: Button = %PauseSettingsButton
@onready var fade: ColorRect = %Fade

var hud: Control
var touch_mode := false
var active := false

var _toast_key := ""
var _toast_args := {}
var _fading := false
var _leaving := false
var _fade_tween: Tween
var _entered := false


func _ready() -> void:
	for b: Button in [lobby_button, settings_button, resume_button, pause_lobby_button, pause_settings_button]:
		CandleStyle.button(b)
		b.focus_mode = Control.FOCUS_NONE
	CandleStyle.button(use_button, true)
	use_button.focus_mode = Control.FOCUS_NONE
	CandleStyle.panel(pause_panel)
	CandleStyle.title(pause_title, 34)
	CandleStyle.text(toast, 22)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(CandleStyle.PANEL, 0.82)
	sb.set_corner_radius_all(10)
	sb.set_content_margin_all(10.0)
	sb.content_margin_left = 18.0
	sb.content_margin_right = 18.0
	toast.add_theme_stylebox_override(&"normal", sb)
	lobby_button.pressed.connect(leave)
	pause_lobby_button.pressed.connect(leave)
	settings_button.pressed.connect(_open_settings)
	pause_settings_button.pressed.connect(_open_settings)
	resume_button.pressed.connect(close_pause)
	use_button.pressed.connect(_use)
	toast_timer.timeout.connect(_hide_toast)
	world.station_changed.connect(_on_station)
	world.stats_changed.connect(_on_stats)
	world.bot_toggled.connect(_on_bot)
	world.reset_done.connect(_on_reset)
	world.leave_requested.connect(leave)
	_make_hud()
	pause_panel.hide()
	use_button.hide()
	toast.hide()
	visibility_changed.connect(_on_visibility)
	get_viewport().size_changed.connect(_on_resize)
	_activate(is_visible_in_tree())


## HUD ของการยิง (ArenaHud) สร้างตอนเปิด ใต้ปุ่มของหน้านี้
func _make_hud() -> void:
	if not ResourceLoader.exists(ARENA_HUD):
		return
	var s: Script = load(ARENA_HUD)
	if s == null or not s.can_instantiate():
		return
	hud = s.new() as Control
	if hud == null:
		return
	hud.name = "Hud"
	hud.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(hud)
	layer.move_child(hud, 0)
	if hud.has_method(&"bind"):
		hud.call(&"bind", world)


## อ่านตั้งค่าใหม่ (ระดับกราฟิก ภาษา ปุ่มบนจอ) แล้ววาดข้อความทั้งหมด
func refresh() -> void:
	touch_mode = App.touch_active()
	world.apply_level(App.gfx)
	use_button.custom_minimum_size.y = USE_H_TOUCH if touch_mode else USE_H
	use_button.add_theme_font_size_override(&"font_size", 26 if touch_mode else 22)
	lobby_button.text = I18n.t(LOBBY_TEXT)
	settings_button.text = I18n.t(SETTINGS_TEXT)
	pause_title.text = I18n.t(PAUSE_TITLE)
	resume_button.text = I18n.t(RESUME_TEXT)
	pause_lobby_button.text = I18n.t(PAUSE_LOBBY_TEXT)
	pause_settings_button.text = I18n.t(SETTINGS_TEXT)
	world.set_sign_text("switch", I18n.t(SIGN_SWITCH_TOUCH if touch_mode else SIGN_SWITCH_KEYS))
	world.set_sign_text("reset", I18n.t(SIGN_RESET))
	world.set_sign_text("door_back", I18n.t(SIGN_BACK))
	world.set_sign_text("door_arena", I18n.t(SIGN_ARENA))
	world.set_sign_text("board_title", enemy_name())
	_on_stats(world.stats())
	if _toast_key != "":
		toast.text = _toast_text()
	_update_prompt()
	if world.player != null and world.player.has_method(&"set_touch"):
		world.player.call(&"set_touch", touch_mode)
	if hud != null and hud.has_method(&"refresh"):
		hud.call(&"refresh", touch_mode)
	CandleStyle.safe_margins(margin)


## ชื่อศัตรูบนกระดาน: ของชุดเสริม (ถ้ามี) ไม่งั้น ArenaData.BEAST.th ("สัตว์รัง")
func enemy_name() -> String:
	var n := ArenaActors.enemy_name()
	if not n.is_empty():
		return str(n["en"]) if App.lang == "en" else str(n["th"])
	return I18n.t(str(ArenaData.BEAST["th"]))


## ข้อความเนื้อกระดาน 3 บรรทัด
static func board_body(st: Dictionary) -> String:
	var lines := PackedStringArray()
	lines.append(I18n.t(BOT_ON if bool(st.get("bot_on", false)) else BOT_OFF))
	if bool(st.get("dead", false)):
		lines.append(I18n.t(DOWN_LINE))
	else:
		lines.append(I18n.t(HP_LINE).format({"hp": int(st.get("hp", 0)), "max": int(st.get("hp_max", 0))}))
	lines.append(I18n.t(HITS_LINE).format({"n": int(st.get("hits", 0)), "d": int(st.get("damage", 0))}))
	return "\n".join(lines)


## แสดงแจ้งเตือนบนกลางจอ 2 วิ (key = ข้อความไทย, args = ค่าแทน {ชื่อ} ในแม่แบบ)
func show_toast(key: String, args: Dictionary = {}) -> void:
	_toast_key = key
	_toast_args = args
	toast.text = _toast_text()
	toast.show()
	toast_timer.start(TOAST_SECONDS)


## ข้อความแจ้งเตือนตามภาษาปัจจุบัน (แปลแม่แบบทั้งข้อความก่อน แล้วค่อยแทนค่า; ชื่อศัตรูแปลตามภาษาตอนนี้)
func _toast_text() -> String:
	var args := _toast_args.duplicate()
	if args.has("name"):
		args["name"] = enemy_name()
	return I18n.t(_toast_key).format(args) if not args.is_empty() else I18n.t(_toast_key)


func open_pause() -> void:
	if pause_panel.visible:
		return
	pause_panel.show()
	world.set_paused(true)
	if hud != null and hud.has_method(&"set_paused"):
		hud.call(&"set_paused", true)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func close_pause() -> void:
	if not pause_panel.visible:
		return
	pause_panel.hide()
	world.set_paused(false)
	if hud != null and hud.has_method(&"set_paused"):
		hud.call(&"set_paused", false)


func paused() -> bool:
	return pause_panel.visible


## ออกจากอารีน่า (ครั้งเดียว): จอมืดแล้วปิดหน้านี้ กลับดาดฟ้า
func leave() -> void:
	if not active or _leaving:
		return
	_leaving = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if world.player != null and world.player.has_method(&"set_input_enabled"):
		world.player.call(&"set_input_enabled", false)
	await _fade_to(1.0)
	App.pop()


## ปุ่มย้อนกลับ / Esc: จอกำลังมืด = กลืน; แผงหยุดเปิดอยู่ = เล่นต่อ; ไม่งั้นเปิดแผงหยุด (ไม่ออกจากหน้า)
func handle_back() -> bool:
	if _fading or _leaving:
		return true
	if pause_panel.visible:
		close_pause()
	else:
		open_pause()
	return true


func fading() -> bool:
	return _fading


func _unhandled_input(event: InputEvent) -> void:
	if not active or _fading or _leaving or pause_panel.visible or not InputMap.has_action(&"interact"):
		return
	if event.is_action_pressed(&"interact"):
		get_viewport().set_input_as_handled()
		world.use_station()


## หน้าต่างหลุดโฟกัส (เดสก์ท็อป) หรือแอปถูกพักไปเบื้องหลัง (มือถือ: สายเข้า สลับแอป) ตอนกำลังยิง = หยุดชั่วคราว
## กลับมาแล้วการต่อสู้ไม่เดินต่อเองทันที (บอทเปิดอยู่ก็ไม่โดนตีตอนไม่ได้ดูจอ)
func _notification(what: int) -> void:
	if (what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_APPLICATION_PAUSED) and active and world != null \
			and world.mode() == &"shoot" and not _leaving:
		open_pause()


# ---- ภายใน ----

func _activate(on: bool) -> void:
	active = on
	world.set_active(on)
	if on:
		_hide_table()
		refresh()
		if pause_panel.visible:
			world.set_paused(true)
		if not _entered:
			_entered = true
			_fade_in()
	else:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		use_button.hide()


func _fade_in() -> void:
	if world.player != null and world.player.has_method(&"set_input_enabled"):
		world.player.call(&"set_input_enabled", false)
	await _fade_to(0.0)
	if world.player != null and world.player.has_method(&"set_input_enabled") and not _leaving:
		world.player.call(&"set_input_enabled", true)


## จอมืด (1) หรือสว่าง (0): hi/mid Tween 0.25 วิ, lo/min มืดหนึ่งเฟรมแล้วเปลี่ยน (ไม่สร้าง Tween) · ระหว่างนั้นกันการแตะ
func _fade_to(alpha: float) -> void:
	_fading = true
	fade.show()
	fade.mouse_filter = Control.MOUSE_FILTER_STOP
	if App.gfx == "hi" or App.gfx == "mid":
		fade.color.a = 1.0 - alpha
		if _fade_tween != null:
			_fade_tween.kill()
		_fade_tween = create_tween()
		_fade_tween.tween_property(fade, ^"color:a", alpha, FADE_TIME)
		await _fade_tween.finished
	else:
		fade.color.a = 1.0
		await get_tree().process_frame
		fade.color.a = alpha
	_fading = false
	if alpha <= 0.0:
		fade.hide()
		fade.mouse_filter = Control.MOUSE_FILTER_IGNORE


func _on_visibility() -> void:
	if is_visible_in_tree() != active:
		_activate(is_visible_in_tree())


func _on_resize() -> void:
	if active:
		CandleStyle.safe_margins(margin)


func _on_station(_id: String) -> void:
	_update_prompt()


func _update_prompt() -> void:
	var id := world.station()
	use_button.visible = active and id != "" and NAMES.has(id)
	if use_button.visible:
		use_button.text = I18n.t(PROMPT_TOUCH if touch_mode else PROMPT_KEYS).format({"name": I18n.t(NAMES[id])})


func _use() -> void:
	if active and not _fading and not pause_panel.visible:
		world.use_station()


func _on_stats(st: Dictionary) -> void:
	world.set_sign_text("board_body", board_body(st))


func _on_bot(on: bool, _how: StringName) -> void:
	if not on:
		show_toast(TOAST_OFF)
	elif bool(world.stats().get("dead", false)):
		# ศัตรูล้มอยู่: บอทเปิดแล้วแต่จะไล่ตามหลังกดรีเซ็ต
		show_toast(TOAST_ON_DEAD)
	else:
		show_toast(TOAST_ON, {"name": ""})


func _on_reset() -> void:
	show_toast(TOAST_RESET)


func _hide_toast() -> void:
	toast.hide()
	_toast_key = ""


func _open_settings() -> void:
	if not active or _fading:
		return
	if not ResourceLoader.exists(SETTINGS_SCREEN):
		return
	open_pause()
	App.push(load(SETTINGS_SCREEN))


## โต๊ะรบ (โลกเดียวกัน) ต้องซ่อนและหยุดเสมอขณะหน้านี้อยู่บนสุด
func _hide_table() -> void:
	var t := get_tree().get_first_node_in_group("table_view") as Node3D
	if t != null:
		t.visible = false
		t.process_mode = Node.PROCESS_MODE_DISABLED
