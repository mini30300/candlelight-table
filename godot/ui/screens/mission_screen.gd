class_name MissionScreen
extends Control
## หน้าภารกิจ เดินและยิงมุมมองบุคคลที่สาม (CAMPAIGN_SPEC §1.6, §5.4, track C เป็นเจ้าของ)
## start(spec) สร้าง MissionWorld (ผู้เล่น ArenaPlayer ตัวที่แต่งในห้องแต่งตัว) + ArenaHud + MissionHud แล้ว: จอสว่าง → ป้ายชื่อภารกิจ
## กับเป้าหมาย 2 วิ → เริ่มเล่น · จบ (ชนะ/แพ้): หยุดอินพุต ป้าย "ภารกิจสำเร็จ"/"ภารกิจล้มเหลว" 1.5 วิ → จอมืด → finished(result)
## ครั้งเดียว · ออกกลางคัน (ยืนยันแล้ว) = ผล quit · หน้านี้ไม่ปิดตัวเอง CampaignFlow แทนที่ด้วยหน้าสรุปผล
## Esc / ปุ่มย้อนกลับ = แผงหยุดชั่วคราว (เล่นต่อ / ตั้งค่า / ออกจากภารกิจ) จัดการเองเสมอ · ระหว่างภารกิจบอกเพื่อนว่าอยู่ "arena"
## ข้อความไทยของหน้านี้อยู่ในไฟล์นี้ (คำแปลใน ui/i18n/campaign_mission.json) · งานต่อเฟรม: ไม่มี (Timer/สัญญาณ)

signal finished(result: Dictionary)

const SCENE := "res://ui/screens/mission_screen.tscn"
const WORLD_SCENE := "res://scenes/campaign/mission_world.tscn"
const SETTINGS_SCREEN := "res://ui/screens/settings.tscn"
const ARENA_HUD := "res://ui/widgets/arena_hud.gd"
const FADE_TIME := 0.25
const INTRO_S := 2.0
const OUTRO_S := 1.5
const TOAST_SECONDS := 2.2
const PAUSE_TEXT := "‹ หยุด"
const PAUSE_TITLE := "หยุดชั่วคราว"
const RESUME_TEXT := "เล่นต่อ"
const SETTINGS_TEXT := "ตั้งค่า"
const QUIT_TEXT := "ออกจากภารกิจ"
const CONFIRM_TEXT := "ออกจากภารกิจ? ผลจะนับเป็นแพ้"
const CONFIRM_YES := "ออก"
const CONFIRM_NO := "ยกเลิก"
const WIN_TEXT := "ภารกิจสำเร็จ"
const FAIL_TEXT := "ภารกิจล้มเหลว"
const PROMPT_KEYS := "{name} · กด E"
const PROMPT_TOUCH := "{name} · แตะเพื่อใช้"
const NAMES := {"hostage": "ปล่อยตัวประกัน", "beacon": "เปิดสัญญาณ"}
const TOASTS := {
	"wave": "ระลอก {n}/{of} กำลังมา! · พลังชีวิตเต็มแล้ว",
	"boss": "หัวหน้าศัตรูปรากฏตัว!",
	"freed": "ปล่อยตัวประกันแล้ว — พาไปที่จุดรับ",
	"saved": "ตัวประกันถึงจุดรับแล้ว",
	"hostage_dead": "ตัวประกันเสียชีวิต",
	"pylon": "ทำลายเสาพิธีกรรมแล้ว",
	"extract": "ทำลายครบแล้ว — ไปที่จุดรับเพื่อถอนตัว",
	"base_hit": "ฐานถูกโจมตี!",
	"revive": "ลุกขึ้นแล้ว · ลุกได้อีก {left} ครั้ง",
	"last_life": "ลุกขึ้นแล้ว · ล้มอีกครั้งภารกิจจะล้มเหลว",
	"secondary": "เป้าหมายรองสำเร็จ!",
	"beacon_on": "เปิดสัญญาณแล้ว — ยืนในวงให้ครบเวลา",
}
const BASE_TOAST_GAP := 6.0      # ข้อความฐานถูกโจมตีไม่ถี่กว่านี้ (วิ)
const USE_H := 64.0
const USE_H_TOUCH := 80.0

@onready var margin: MarginContainer = $Safe
@onready var layer: Control = $Safe/Layer
@onready var pause_button: Button = %PauseButton
@onready var use_button: Button = %UseButton
@onready var toast: Label = %Toast
@onready var toast_timer: Timer = %ToastTimer
@onready var pause_panel: PanelContainer = %PausePanel
@onready var pause_title: Label = %PauseTitle
@onready var resume_button: Button = %ResumeButton
@onready var pause_settings_button: Button = %PauseSettingsButton
@onready var quit_button: Button = %QuitButton
@onready var confirm_panel: PanelContainer = %ConfirmPanel
@onready var confirm_label: Label = %ConfirmLabel
@onready var confirm_yes: Button = %ConfirmYes
@onready var confirm_no: Button = %ConfirmNo
@onready var fade: ColorRect = %Fade

var spec: Dictionary = {}
var hud: Control
var mhud: MissionHud
var touch_mode := false
var active := false
var _world: MissionWorld
var _done := false
var _ending := false
var _fading := false
var _playing := false
var _fade_tween: Tween
var _toast_key := ""
var _toast_args := {}
var _base_toast_t := -100.0
var _result: Dictionary = {}


func _ready() -> void:
	for b: Button in [pause_button, resume_button, pause_settings_button, quit_button, confirm_yes, confirm_no]:
		CandleStyle.button(b)
		b.focus_mode = Control.FOCUS_NONE
	CandleStyle.button(use_button, true)
	use_button.focus_mode = Control.FOCUS_NONE
	CandleStyle.panel(pause_panel)
	CandleStyle.panel(confirm_panel)
	CandleStyle.title(pause_title, 34)
	CandleStyle.text(confirm_label, 22)
	CandleStyle.text(toast, 22)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(CandleStyle.PANEL, 0.82)
	sb.set_corner_radius_all(10)
	sb.set_content_margin_all(10.0)
	sb.content_margin_left = 18.0
	sb.content_margin_right = 18.0
	toast.add_theme_stylebox_override(&"normal", sb)
	pause_button.pressed.connect(open_pause)
	resume_button.pressed.connect(close_pause)
	pause_settings_button.pressed.connect(_open_settings)
	quit_button.pressed.connect(_ask_quit)
	confirm_yes.pressed.connect(quit_mission)
	confirm_no.pressed.connect(_close_confirm)
	use_button.pressed.connect(_use)
	toast_timer.timeout.connect(_hide_toast)
	pause_panel.hide()
	confirm_panel.hide()
	use_button.hide()
	toast.hide()
	fade.show()
	fade.color.a = 1.0
	visibility_changed.connect(_on_visibility)
	get_viewport().size_changed.connect(_on_resize)


## เรียกหลัง App.push ทันที: สร้างโลกจาก spec แล้วเริ่มลำดับเปิดภารกิจ
func start(s: Dictionary) -> void:
	spec = s
	var ws: PackedScene = load(WORLD_SCENE)
	_world = ws.instantiate() as MissionWorld
	_world.name = "MissionWorld"
	add_child(_world)
	move_child(_world, 0)
	touch_mode = App.touch_active()
	_world.setup(s, App.gfx, touch_mode)
	_world.station_changed.connect(func(_id: String) -> void: _update_prompt())
	_world.event.connect(_on_world_event)
	_world.ended.connect(_on_world_ended)
	_make_huds()
	_set_where(&"arena")
	var music := get_node_or_null(^"/root/Music")
	if music != null and music.has_method(&"set_mood"):
		music.call(&"set_mood", &"battle")
	_activate(is_visible_in_tree())
	_intro()


## จบภารกิจ (ครั้งเดียว): result ตาม CAMPAIGN_SPEC §5.5
func finish(result: Dictionary) -> void:
	if _done:
		return
	_done = true
	_result = result
	finished.emit(result)


func world() -> MissionWorld:
	return _world


func result() -> Dictionary:
	return _result


func playing() -> bool:
	return _playing


func fading() -> bool:
	return _fading


func paused() -> bool:
	return pause_panel.visible


func banner_text() -> String:
	return mhud.banner_text() if mhud != null else ""


## Esc / ย้อนกลับ: จอมืดหรือกำลังจบ = กลืน · ยืนยันออกเปิดอยู่ = ปิด · แผงหยุดเปิดอยู่ = เล่นต่อ · ไม่งั้นเปิดแผงหยุด
func handle_back() -> bool:
	if _fading or _ending or _done:
		return true
	if confirm_panel.visible:
		_close_confirm()
	elif pause_panel.visible:
		close_pause()
	else:
		open_pause()
	return true


func open_pause() -> void:
	if pause_panel.visible or _ending or _world == null:
		return
	pause_panel.show()
	_world.set_paused(true)
	if hud != null and hud.has_method(&"set_paused"):
		hud.call(&"set_paused", true)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func close_pause() -> void:
	if not pause_panel.visible:
		return
	pause_panel.hide()
	confirm_panel.hide()
	if _playing:
		_world.set_paused(false)
	if hud != null and hud.has_method(&"set_paused"):
		hud.call(&"set_paused", false)


## ออกจากภารกิจ (ยืนยันแล้ว): ผล quit → จอมืด → finished
func quit_mission() -> void:
	if _ending or _done or _world == null:
		return
	_ending = true
	_playing = false
	confirm_panel.hide()
	pause_panel.hide()
	_world.quit()
	var r := _world.result()
	await _fade_to(1.0)
	finish(r)


## แสดงแจ้งเตือนกลางจอ (key = ข้อความไทย)
func show_toast(key: String, args: Dictionary = {}) -> void:
	_toast_key = key
	_toast_args = args
	toast.text = I18n.t(key).format(args) if not args.is_empty() else I18n.t(key)
	toast.show()
	toast_timer.start(TOAST_SECONDS)


func toast_text() -> String:
	return toast.text if toast.visible else ""


## อ่านตั้งค่าใหม่ (ภาษา ระดับกราฟิก ปุ่มบนจอ)
func refresh() -> void:
	touch_mode = App.touch_active()
	if _world != null:
		_world.apply_level(App.gfx)
		if _world.player != null and _world.player.has_method(&"set_touch"):
			_world.player.call(&"set_touch", touch_mode)
	use_button.custom_minimum_size.y = USE_H_TOUCH if touch_mode else USE_H
	use_button.add_theme_font_size_override(&"font_size", 26 if touch_mode else 22)
	pause_button.text = I18n.t(PAUSE_TEXT)
	pause_title.text = I18n.t(PAUSE_TITLE)
	resume_button.text = I18n.t(RESUME_TEXT)
	pause_settings_button.text = I18n.t(SETTINGS_TEXT)
	quit_button.text = I18n.t(QUIT_TEXT)
	confirm_label.text = I18n.t(CONFIRM_TEXT)
	confirm_yes.text = I18n.t(CONFIRM_YES)
	confirm_no.text = I18n.t(CONFIRM_NO)
	if _toast_key != "":
		toast.text = I18n.t(_toast_key).format(_toast_args) if not _toast_args.is_empty() else I18n.t(_toast_key)
	_update_prompt()
	if hud != null and hud.has_method(&"refresh"):
		hud.call(&"refresh", touch_mode)
	if mhud != null:
		mhud.refresh(touch_mode)
	CandleStyle.safe_margins(margin)


func _unhandled_input(event: InputEvent) -> void:
	if not active or not _playing or _fading or _ending or pause_panel.visible or not InputMap.has_action(&"interact"):
		return
	if event.is_action_pressed(&"interact"):
		get_viewport().set_input_as_handled()
		_world.use_station()


## หน้าต่างหลุดโฟกัส / แอปถูกพักไปเบื้องหลังระหว่างเล่น = หยุดชั่วคราว
func _notification(what: int) -> void:
	if (what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_APPLICATION_PAUSED) and active and _playing \
			and not _ending:
		open_pause()


# ---- ภายใน ----

func _make_huds() -> void:
	if ResourceLoader.exists(ARENA_HUD):
		var s: Script = load(ARENA_HUD)
		if s != null and s.can_instantiate():
			hud = s.new() as Control
	if hud != null:
		hud.name = "Hud"
		hud.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
		layer.add_child(hud)
		layer.move_child(hud, 0)
		if hud.has_method(&"bind"):
			hud.call(&"bind", _world)
	mhud = MissionHud.new()
	mhud.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.add_child(mhud)
	layer.move_child(mhud, 1 if hud != null else 0)
	mhud.bind(_world, spec)


## เปิดภารกิจ: จอสว่าง (อินพุตปิด) → ป้ายชื่อ + เป้าหมาย 2 วิ → เริ่มเล่น
func _intro() -> void:
	_set_input(false)
	var t := str((spec.get("primary", {}) as Dictionary).get("type", ""))
	mhud.show_banner(I18n.t(MissionTypes.name_th(t)), I18n.t(MissionTypes.goal_th(t)))
	await _fade_to(0.0)
	await get_tree().create_timer(INTRO_S).timeout
	if _ending or _done or not is_instance_valid(_world):
		return
	mhud.show_banner("")
	_playing = true
	_set_input(true)
	_world.begin()
	if pause_panel.visible:
		_world.set_paused(true)
	_update_prompt()


func _on_world_ended(outcome: String) -> void:
	if _ending or _done:
		return
	_ending = true
	_playing = false
	pause_panel.hide()
	confirm_panel.hide()
	use_button.hide()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	mhud.show_banner(I18n.t(WIN_TEXT if outcome == "win" else FAIL_TEXT))
	var r := _world.result()
	await get_tree().create_timer(OUTRO_S).timeout
	await _fade_to(1.0)
	finish(r)


func _on_world_event(kind: StringName, info: Dictionary) -> void:
	var k := String(kind)
	if not TOASTS.has(k):
		return
	if kind == &"base_hit":
		var now := _world.obj.t if _world != null and _world.obj != null else 0.0
		if now - _base_toast_t < BASE_TOAST_GAP:
			return
		_base_toast_t = now
	show_toast(TOASTS[k], info.duplicate())


func _set_input(on: bool) -> void:
	if _world != null and _world.player != null and _world.player.has_method(&"set_input_enabled"):
		_world.player.call(&"set_input_enabled", on)


func _activate(on: bool) -> void:
	active = on
	if _world != null:
		_world.set_active(on)
	if on:
		_hide_table()
		refresh()
		if pause_panel.visible and _world != null:
			_world.set_paused(true)
	else:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		use_button.hide()


func _on_visibility() -> void:
	if is_visible_in_tree() != active and _world != null:
		_activate(is_visible_in_tree())


func _on_resize() -> void:
	if active:
		CandleStyle.safe_margins(margin)


func _update_prompt() -> void:
	var id := _world.station() if _world != null else ""
	use_button.visible = active and _playing and id != "" and NAMES.has(id)
	if use_button.visible:
		use_button.text = I18n.t(PROMPT_TOUCH if touch_mode else PROMPT_KEYS).format({"name": I18n.t(NAMES[id])})


func _use() -> void:
	if active and _playing and not _fading and not pause_panel.visible:
		_world.use_station()


func _ask_quit() -> void:
	if _ending:
		return
	confirm_panel.show()


func _close_confirm() -> void:
	confirm_panel.hide()


func _hide_toast() -> void:
	toast.hide()
	_toast_key = ""


func _open_settings() -> void:
	if not active or _fading or _ending:
		return
	if not ResourceLoader.exists(SETTINGS_SCREEN):
		return
	open_pause()
	App.push(load(SETTINGS_SCREEN))


## จอมืด (1) หรือสว่าง (0): hi/mid Tween 0.25 วิ, lo/min เปลี่ยนในเฟรมถัดไป (ไม่สร้าง Tween) · ระหว่างนั้นกันการแตะ
func _fade_to(alpha: float) -> void:
	_fading = true
	fade.show()
	fade.mouse_filter = Control.MOUSE_FILTER_STOP
	if App.gfx == "hi" or App.gfx == "mid":
		if _fade_tween != null:
			_fade_tween.kill()
		_fade_tween = create_tween()
		_fade_tween.tween_property(fade, ^"color:a", alpha, FADE_TIME)
		await _fade_tween.finished
	else:
		await get_tree().process_frame
		fade.color.a = alpha
	_fading = false
	if alpha <= 0.0:
		fade.hide()
		fade.mouse_filter = Control.MOUSE_FILTER_IGNORE


func _set_where(w: StringName) -> void:
	var net := get_node_or_null(^"/root/Net")
	if net != null and net.has_method(&"set_where"):
		net.call(&"set_where", w)


## โต๊ะรบ (โลกเดียวกัน) ต้องซ่อนและหยุดเสมอขณะหน้านี้อยู่บนสุด
func _hide_table() -> void:
	var t := get_tree().get_first_node_in_group("table_view") as Node3D
	if t != null:
		t.visible = false
		t.process_mode = Node.PROCESS_MODE_DISABLED
