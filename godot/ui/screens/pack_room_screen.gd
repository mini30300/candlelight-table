class_name PackRoomScreen
extends Control
## หน้าห้องเสริมหลังประตูบนดาดฟ้า (PACK_SPEC §9): เปิดทับหน้าดาดฟ้า ภาพของห้องมาจากชุดเสริม ปุ่มและข้อความเป็นของแอป
## สถานีจาก room.json: soon → แผง "เร็วๆ นี้", cards → แผงการ์ดเลือกโหมด, online → หน้าเล่นกับเพื่อน, back → กลับดาดฟ้า
## arena → เดินเข้าประตู/กด E = จอมืดแล้วเปิดหน้าอารีน่า กลับมายืนหน้าประตูหันออก (ไฟล์อารีน่าโหลดล่วงหน้าผ่านหน้าดาดฟ้า)
## เดินเข้าประตู (walk_in) หรือ ‹ ดาดฟ้า / Esc → จอมืดแวบหนึ่งแล้วกลับดาดฟ้า (ไม่กลับหน้าแรก)
## ออนไลน์: ห้องนี้เป็นส่วนหนึ่งของยาน (where = deck) ส่งท่าในแถบห้อง x + 30 ม. (PackRooms.to_band) เห็นเพื่อนที่อยู่ในห้อง
## ถูกหน้าอื่นทับ: หยุดห้องและสคริปต์ของห้อง; กลับมาโชว์: อ่านกราฟิก/ภาษา/ปุ่มบนจอใหม่
## งานต่อเฟรม: ไม่มี (ข้อความเปลี่ยนตามสัญญาณ แผงปิดด้วย Timer)

signal station_changed(id: String)

const SETTINGS_SCREEN := "res://ui/screens/settings.tscn"
const LOBBY_SCREEN := "res://ui/screens/lobby.tscn"
const ARENA_SCREEN := "res://ui/screens/arena_screen.tscn"
const FADE_TIME := 0.25
const BACK_TEXT := "‹ ดาดฟ้า"
const CLOSE_TEXT := "ปิดแผงนี้"
const SETTINGS_TEXT := "ตั้งค่า"
const YOU := "คุณ"
## ข้อความเดียวกับดาดฟ้า (คีย์เดิมใน ui/i18n/hall.json)
const PROMPT_KEYS := "{name} · กด E"
const PROMPT_TOUCH := "{name} · แตะเพื่อใช้"
const HINT_KEYS := "WASD หรือลูกศร เดิน · Shift วิ่ง · ลากเมาส์หมุนกล้อง"
const HINT_TOUCH := "ใช้ปุ่มซ้ายล่างเดิน · ลากจอหมุนกล้อง"
const JOINED := "{name} เข้าห้องแล้ว"
const LEFT := "{name} ออกจากห้อง"
const DROPPED := "{name} หลุดจากห้อง — รอต่อใหม่"
const BACK := "{name} กลับมาแล้ว"
const SETUP_OPEN_AT := "เจ้าห้องกำลังตั้งเกม — เลือกที่นั่งได้ที่{place}"
const SOON_SECONDS := 2.5
const POSE_MS := 100
const MAX_PLAYERS := 6
const USE_H := 64.0
const USE_H_TOUCH := 80.0
const CARD_H := 76.0
const STEP_WALK := 1.15
const STEP_RUN := 1.7

@onready var world: PackRoomWorld = $PackRoomWorld
@onready var margin: MarginContainer = $Safe
@onready var use_button: Button = %UseButton
@onready var stick: TouchStick = %Stick
@onready var back_button: Button = %BackButton
@onready var settings_button: Button = %SettingsButton
@onready var soon_panel: PanelContainer = %SoonPanel
@onready var soon_label: Label = %SoonLabel
@onready var cards_panel: PanelContainer = %CardsPanel
@onready var cards_title: Label = %CardsTitle
@onready var cards_box: VBoxContainer = %CardsBox
@onready var close_button: Button = %CloseButton
@onready var hint: Label = %Hint
@onready var soon_timer: Timer = %SoonTimer
@onready var pose_timer: Timer = %PoseTimer
@onready var fade: ColorRect = %Fade
@onready var tags: FriendTags = %FriendTags

var touch_mode := false
var active := false
var room: Dictionary = {}
var net: Node
## หน้าดาดฟ้าที่เปิดห้องนี้ (โหลดไฟล์อารีน่าล่วงหน้าและจำไว้) · null = โหลดตอนเข้า
var hall: Node

var _opened := false
var _hint_done := false
var _soon: Variant = null             # คู่ {th, en} ที่แผง "เร็วๆ นี้" โชว์อยู่
var _note := ""
var _note_args: Dictionary = {}
var _cards := ""                      # สถานีของแผงการ์ดที่เปิดอยู่
var _leaving := false
var _entering := false                # กำลังจอมืดเข้าอารีน่า
var _from_arena := ""                 # สถานีประตูอารีน่าที่เข้าไป: กลับมายืนหน้าประตูนี้
var _pop_when_shown := false          # หน้าอื่นทับระหว่างจอมืดตอนออก: ปิดหน้านี้เมื่อกลับมาโชว์
var _setup_open := false
var _fading := false
var _fade_tween: Tween
var _members: Dictionary = {}
var _here: Dictionary = {}
var _members_known := false
var _in: Dictionary = {}              # slot → ท่าล่าสุดอยู่ในแถบห้อง
var _pose_ms := -100000
var _step_d := 0.0
var _step_p := Vector3.INF


func _ready() -> void:
	CandleStyle.button(back_button)
	CandleStyle.button(settings_button)
	CandleStyle.button(use_button, true)
	CandleStyle.button(close_button)
	CandleStyle.panel(soon_panel)
	CandleStyle.panel(cards_panel)
	CandleStyle.text(soon_label, 24)
	CandleStyle.text(cards_title, 26)
	CandleStyle.text(hint, 19)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(CandleStyle.PANEL, 0.78)
	sb.set_corner_radius_all(10)
	sb.set_content_margin_all(10.0)
	sb.content_margin_left = 18.0
	sb.content_margin_right = 18.0
	hint.add_theme_stylebox_override(&"normal", sb)
	for b: Button in [back_button, settings_button, use_button, close_button]:
		b.focus_mode = Control.FOCUS_NONE
	back_button.pressed.connect(leave)
	settings_button.pressed.connect(_open_settings)
	use_button.pressed.connect(use_station)
	close_button.pressed.connect(close_cards)
	stick.changed.connect(world.set_stick)
	soon_timer.timeout.connect(close_soon)
	world.station_changed.connect(_on_station)
	world.avatar.moved.connect(_on_avatar_moved)
	tags.bind(world)
	world.friends.moved.connect(tags.refresh)
	world.camera_rig.view_changed.connect(_on_view)
	pose_timer.one_shot = true
	pose_timer.timeout.connect(_send_pose.bind(true))
	soon_panel.hide()
	cards_panel.hide()
	use_button.hide()
	visibility_changed.connect(_on_visibility)
	get_viewport().size_changed.connect(_on_resize)
	world.set_active(false)


## เปิดห้อง room (จาก PackRooms) ยืนที่จุดเกิด หรือหน้าสถานี at_station แล้วจอค่อย ๆ สว่าง · คืน false = เปิดไม่ได้
func open(r: Dictionary, at_station := "") -> bool:
	if _opened or not world.open(r):
		return false
	room = r
	_opened = true
	use_net(net if net != null else get_node_or_null(^"/root/Net"))
	var lay := world.layout
	if at_station != "" and lay.stations.has(at_station):
		var f: Vector2 = lay.stations[at_station]["front"]
		var d: Vector2 = (lay.stations[at_station]["c"] as Vector2) - f
		var yaw := atan2(d.x, d.y)
		world.place_avatar(Vector3(f.x, 0.0, f.y), yaw)
		world.camera_rig.set_view(yaw + PI, -0.4, 5.5)
	elif online():
		# ออนไลน์: จุดเกิดของแต่ละช่องห่างกัน 0.9 ม. (เหมือน HallFriends.spawn_for) ไม่ซ้อนกัน
		var p := lay.spawn + Vector3((float(maxi(_my_slot(), 0)) - 2.5) * HallFriends.SLOT_GAP, 0.0, 0.0)
		if lay.blocked(Vector2(p.x, p.z), HallLayout.AVATAR_R):
			p = lay.spawn
		world.place_avatar(p, lay.spawn_yaw + PI)
	fade.show()
	fade.color.a = 1.0
	_activate(is_visible_in_tree())
	_fade_to(0.0)
	return true


## เพื่อนที่อยู่ในห้องก่อนเราเข้า: ท่าล่าสุดในแถบห้องจากหน้าดาดฟ้า (slot → pose)
func seed_poses(poses: Dictionary) -> void:
	for s: int in poses:
		_on_pose(s, poses[s])


func room_id() -> String:
	return str(room.get("id", ""))


func station() -> String:
	return world.station()


func fading() -> bool:
	return _fading or _leaving or _entering


func cards_open() -> bool:
	return cards_panel.visible


func refresh() -> void:
	touch_mode = App.touch_active()
	world.apply_level(App.gfx)
	world.refresh_text()
	stick.visible = touch_mode
	use_button.custom_minimum_size.y = USE_H_TOUCH if touch_mode else USE_H
	use_button.add_theme_font_size_override(&"font_size", 26 if touch_mode else 22)
	back_button.text = I18n.t(BACK_TEXT)
	settings_button.text = I18n.t(SETTINGS_TEXT)
	close_button.text = I18n.t(CLOSE_TEXT)
	world.set_you_text(I18n.t(YOU))
	hint.text = I18n.t(HINT_TOUCH if touch_mode else HINT_KEYS)
	hint.visible = not _hint_done
	if _soon != null:
		soon_label.text = PackRooms.text(_soon)
	elif _note != "":
		soon_label.text = I18n.t(_note).format(_note_args)
	if _cards != "":
		_fill_cards(_cards)
	_update_prompt()
	CandleStyle.safe_margins(margin)
	sync_online()


## ใช้สถานีตรงหน้า (E / แตะ / ปุ่มใช้งาน): บอกสคริปต์ของห้องก่อน แล้วทำตาม action ใน room.json
func use_station() -> void:
	if not active or fading():
		return
	var id := station()
	if id == "":
		return
	_sfx(&"heal")
	if world.script_node != null and world.script_node.has_method("station_used"):
		world.script_node.call("station_used", id)
	var s := world.station_data(id)
	match str(s.get("action", "")):
		"soon":
			show_soon(s.get("soon"))
		"cards":
			open_cards(id)
		"online":
			open_online()
		"back":
			leave()
		"arena":
			enter_arena()


func show_soon(pair: Variant) -> void:
	if not pair is Dictionary:
		return
	_soon = pair
	_note = ""
	soon_label.text = PackRooms.text(pair)
	soon_panel.show()
	soon_timer.start(SOON_SECONDS)


func show_note(key: String, args: Dictionary = {}) -> void:
	_soon = null
	_note = key
	_note_args = args
	soon_label.text = I18n.t(key).format(args)
	soon_panel.show()
	soon_timer.start(SOON_SECONDS)


func close_soon() -> void:
	soon_timer.stop()
	soon_panel.hide()
	_soon = null
	_note = ""


## แผงการ์ดของสถานี id (โมดัลเหนือห้อง): ปล่อยจอย หยุดตัวผู้เล่น · เดินแล้วแผงปิด
func open_cards(id: String) -> void:
	close_soon()
	_cards = id
	_fill_cards(id)
	stick.release()
	world.avatar.halt()
	cards_panel.show()
	# แผงการ์ดบังคำแนะนำครั้งแรกกับปุ่มใช้งาน: ซ่อนไว้
	if not _hint_done:
		_hint_done = true
		hint.hide()
	_update_prompt()


func close_cards() -> void:
	cards_panel.hide()
	_cards = ""
	_update_prompt()


## ปุ่มการ์ดทั้งหมดของแผงที่เปิดอยู่ (ชื่อการ์ดตามลำดับใน room.json)
func card_buttons() -> Array[Button]:
	var out: Array[Button] = []
	for c in cards_box.get_children():
		if c is Button and not c.is_queued_for_deletion():
			out.append(c)
	return out


## เปิดหน้าเล่นกับเพื่อนทับห้องนี้ (ย้อนกลับ = กลับมาที่ห้อง) · null เมื่อออนไลน์ปิด
func open_online() -> Node:
	if not Features.on(&"online") or not ResourceLoader.exists(LOBBY_SCREEN):
		return null
	close_cards()
	close_soon()
	return App.push(load(LOBBY_SCREEN))


## เข้าอารีน่าจากประตูในห้อง (ครั้งเดียวต่อการกด): หยุดตัว จอมืด แล้วเปิดหน้าอารีน่าทับ · เปิดไม่ได้ = จอสว่างเดินต่อ
func enter_arena() -> void:
	var id := PackRooms.arena_station(room)
	if not active or fading() or id == "":
		return
	_entering = true
	preload_arena()
	_set_where(&"arena")
	close_cards()
	close_soon()
	stick.release()
	world.avatar.halt()
	world.avatar.process_mode = Node.PROCESS_MODE_DISABLED
	pose_timer.stop()
	await _fade_to(1.0)
	_entering = false
	var ps := _arena_scene()
	if active and ps != null:
		_from_arena = id
		if App.push(ps) != null:
			return
		_from_arena = ""
	world.avatar.process_mode = Node.PROCESS_MODE_INHERIT
	_set_where(&"deck")
	await _fade_to(0.0)


## เริ่มโหลดไฟล์อารีน่าในเธรด (ผ่านหน้าดาดฟ้า เรียกซ้ำได้)
func preload_arena() -> void:
	if hall != null and is_instance_valid(hall) and hall.has_method("preload_arena"):
		hall.call("preload_arena")


func _arena_scene() -> PackedScene:
	if hall != null and is_instance_valid(hall) and hall.has_method("arena_scene"):
		return hall.call("arena_scene") as PackedScene
	return load(ARENA_SCREEN) as PackedScene if ResourceLoader.exists(ARENA_SCREEN) else null


## กลับจากอารีน่า: ยืนหน้าประตู หันออกจากประตู กล้องอยู่หลังตัว จอค่อย ๆ สว่างแล้วค่อยเดินได้
func _back_from_arena(id: String) -> void:
	var lay := world.layout
	if lay.stations.has(id):
		var f: Vector2 = lay.stations[id]["front"]
		var d: Vector2 = f - (lay.stations[id]["c"] as Vector2)
		var yaw := atan2(d.x, d.y)
		world.place_avatar(Vector3(f.x, 0.0, f.y), yaw)
		world.camera_rig.set_view(yaw + PI, -0.45, 6.5)
	await _fade_to(0.0)
	world.avatar.process_mode = Node.PROCESS_MODE_INHERIT


## กลับดาดฟ้า (ครั้งเดียว): หยุดตัวผู้เล่น จอมืด แล้วปิดหน้านี้ (ดาดฟ้ามาวางตัวที่หน้าประตูเอง)
func leave() -> void:
	if not active or _leaving:
		return
	_leaving = true
	close_cards()
	close_soon()
	stick.release()
	world.avatar.halt()
	world.avatar.process_mode = Node.PROCESS_MODE_DISABLED
	pose_timer.stop()
	await _fade_to(1.0)
	_activate(false)
	if App.current() == self:
		App.pop()
	else:
		# หน้าอื่นถูกเปิดทับระหว่างจอมืด (เช่นเพื่อนเริ่มรบออนไลน์): ปิดหน้านี้ตอนหน้านั้นปิด ไม่ค้างจอดำ
		_pop_when_shown = true


## ย้อนกลับ / Esc: ปิดแผงการ์ด แล้วแผง "เร็วๆ นี้" แล้วค่อยกลับดาดฟ้า (ไม่ถอยไปหน้าแรก)
func handle_back() -> bool:
	if fading():
		return true
	if cards_panel.visible:
		close_cards()
		return true
	if soon_panel.visible:
		close_soon()
		return true
	leave()
	return true


func hint_done() -> bool:
	return _hint_done


func _unhandled_input(event: InputEvent) -> void:
	if not active or fading() or not InputMap.has_action(&"interact"):
		return
	if event.is_action_pressed(&"interact"):
		get_viewport().set_input_as_handled()
		if cards_panel.visible:
			return
		use_station()


# ---- ภายใน ----

func _activate(on: bool) -> void:
	if not _opened:
		return
	active = on
	world.set_active(on)
	if on:
		refresh()
		if _from_arena != "":
			var back_id := _from_arena
			_from_arena = ""
			_back_from_arena(back_id)
		_set_where(&"deck")
		_send_pose(true)
		var music := get_node_or_null(^"/root/Music")
		if music != null:
			music.call("set_mood", &"deck")
	else:
		pose_timer.stop()
		stick.release()
		close_soon()
		use_button.hide()


func _on_visibility() -> void:
	if _pop_when_shown and is_visible_in_tree():
		_pop_when_shown = false
		_pop_self.call_deferred()
		return
	if is_visible_in_tree() != active and not (_leaving and is_visible_in_tree()):
		_activate(is_visible_in_tree())


func _pop_self() -> void:
	if App.current() == self:
		App.pop()


func _on_resize() -> void:
	if active:
		CandleStyle.safe_margins(margin)


func _on_station(id: String) -> void:
	_update_prompt()
	if id != "" and str(world.station_data(id).get("action", "")) == "arena":
		preload_arena()
	if id != "" and active:
		_sfx(&"ui")
	station_changed.emit(id)


func _update_prompt() -> void:
	var id := world.station()
	use_button.visible = active and id != "" and not _leaving and not cards_panel.visible
	if id != "":
		var nm := PackRooms.text(world.station_data(id).get("name"))
		use_button.text = I18n.t(PROMPT_TOUCH if touch_mode else PROMPT_KEYS).format({"name": nm})


func _on_avatar_moved(p: Vector3) -> void:
	if online():
		var now := Time.get_ticks_msec()
		if now - _pose_ms >= POSE_MS:
			_pose_ms = now
			_send_pose(false)
		pose_timer.start()
		if tags.visible:
			tags.refresh()
	if world.avatar.input_vector() == Vector2.ZERO:
		_step_p = Vector3.INF
		return
	_footstep(p)
	var id := world.station()
	if id != "" and bool(world.layout.stations[id]["walk_in"]) and world.layout.in_walk_in(id, Vector2(p.x, p.z)):
		if str(world.layout.stations[id]["action"]) == "arena":
			enter_arena()
		else:
			leave()
		return
	if soon_panel.visible:
		close_soon()
	if cards_panel.visible:
		close_cards()
	if not _hint_done:
		_hint_done = true
		if App.gfx == "min" or App.gfx == "lo":
			hint.hide()
		else:
			var tw := create_tween()
			tw.tween_property(hint, ^"modulate:a", 0.0, 0.4)
			tw.tween_callback(hint.hide)


func _fill_cards(id: String) -> void:
	var s := world.station_data(id)
	cards_title.text = PackRooms.text(s.get("name"))
	for c in cards_box.get_children():
		cards_box.remove_child(c)
		c.queue_free()
	var i := 0
	for card: Dictionary in s.get("cards", []):
		var b := Button.new()
		b.name = "Card%d" % i
		b.text = PackRooms.text(card.get("title")) + "\n" + PackRooms.text(card.get("text"))
		b.custom_minimum_size = Vector2(0.0, CARD_H)
		b.focus_mode = Control.FOCUS_NONE
		b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		CandleStyle.button(b, str(card.get("action", "")) == "online")
		b.pressed.connect(_use_card.bind(card))
		cards_box.add_child(b)
		i += 1


func _use_card(card: Dictionary) -> void:
	if not active or fading():
		return
	_sfx(&"heal")
	close_cards()
	match str(card.get("action", "")):
		"soon":
			show_soon(card.get("soon"))
		"online":
			open_online()


func _footstep(p: Vector3) -> void:
	if _step_p != Vector3.INF:
		_step_d += Vector2(p.x - _step_p.x, p.z - _step_p.z).length()
	_step_p = p
	var stride := STEP_RUN if world.avatar.running() else STEP_WALK
	if _step_d < stride:
		return
	_step_d = fmod(_step_d, stride)
	var sfx := get_node_or_null(^"/root/Sfx")
	if sfx != null:
		sfx.call("play", &"stomp", p, 0.3, randf_range(1.55, 1.75))


func _sfx(kind: StringName) -> void:
	var sfx := get_node_or_null(^"/root/Sfx")
	if sfx != null:
		sfx.call("play_ui", kind)


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


func _open_settings() -> void:
	if not active or fading() or not ResourceLoader.exists(SETTINGS_SCREEN):
		return
	_set_where(&"settings")
	App.push(load(SETTINGS_SCREEN))


func _on_view() -> void:
	if tags.visible:
		tags.refresh()


# ---- ออนไลน์: เพื่อนในห้องนี้ (แถบห้อง PackRooms.in_band) ----

func use_net(n: Node) -> void:
	var handlers := {"members_changed": sync_online, "state_changed": _on_net_state, "pose": _on_pose,
		"reconnected": _on_reconnected, "message": _on_net_message}
	if net != null and is_instance_valid(net):
		for sig: String in handlers:
			if net.has_signal(sig) and net.is_connected(sig, handlers[sig]):
				net.disconnect(sig, handlers[sig])
	net = n
	if net != null:
		for sig: String in handlers:
			if net.has_signal(sig) and not net.is_connected(sig, handlers[sig]):
				net.connect(sig, handlers[sig])
	_members_known = false
	if is_node_ready() and _opened:
		sync_online()


func online() -> bool:
	return net != null and is_instance_valid(net) and bool(net.call("is_online"))


## เพื่อนในห้องนี้: where = deck, อยู่ในห้องจริง (here) และท่าล่าสุดอยู่ในแถบห้อง
func sync_online() -> void:
	if not _opened:
		return
	var on := online()
	var me := _my_slot() if on else -1
	world.set_slot_colour(HallWorld.slot_colour(maxi(me, 0)))
	var seen := {}
	var here := {}
	if on:
		for m: Dictionary in net.call("members"):
			var s := int(m.get("slot", -1))
			if s < 0 or s == me:
				continue
			var nm := str(m.get("nm", ""))
			seen[s] = nm
			here[s] = bool(m.get("here", true))
			if str(m.get("where", "")) == "deck" and bool(m.get("here", true)) and bool(_in.get(s, false)):
				world.friends.set_friend(s, nm, HallWorld.slot_colour(s))
			else:
				world.friends.remove_friend(s)
	for s in world.friends.slots():
		if not seen.has(s):
			world.friends.remove_friend(s)
	var fresh := false
	if on and _members_known and active:
		for s in seen:
			if not _members.has(s):
				show_note(JOINED, {"name": seen[s]})
				fresh = true
		for s in _members:
			if not seen.has(s):
				show_note(LEFT, {"name": _members[s]})
		for s in here:
			if _here.has(s) and bool(_here[s]) != bool(here[s]):
				show_note(BACK if bool(here[s]) else DROPPED, {"name": seen[s]})
	_members = seen
	_here = here
	_members_known = on
	# ออฟไลน์ล้างหมด · ช่องที่ไม่อยู่ในรายชื่อแล้วลืมท่าเดิม (คนใหม่ที่ได้ช่องนี้เริ่มที่ดาดฟ้า)
	if not on:
		_in.clear()
		_setup_open = false
	else:
		for s in _in.keys():
			if not seen.has(s):
				_in.erase(s)
	# คนใหม่เข้าห้อง: ส่งท่ายืนของเราอีกครั้งให้เขารู้ว่าเราอยู่ในห้องนี้
	if fresh:
		_send_pose(true)
	var with_friends := on and world.friends.friend_count() > 0
	world.set_you_tag_visible(not with_friends)
	tags.set_you(I18n.t(YOU) if with_friends else "")
	tags.set_status(_status_text() if on else "")
	tags.status_y = back_button.get_global_rect().end.y - tags.get_global_rect().position.y + 6.0
	tags.refresh()


func _status_text() -> String:
	if str(net.call("state")) == "reconnecting":
		return I18n.t(OnlineText.REASONS["reconnecting"])
	var host := net.call("member", 0) as Dictionary
	var n := (net.call("members") as Array).size()
	var cap: Variant = net.get("max_players")
	return OnlineText.status(str(host.get("nm", "")) if host != null else "", n, int(cap) if cap != null else MAX_PLAYERS)


func _my_slot() -> int:
	return int(net.call("my_slot")) if net != null and is_instance_valid(net) else -1


func _set_where(w: StringName) -> void:
	if net != null and is_instance_valid(net):
		net.call("set_where", w)


## ท่าของตัวเองในแถบห้อง (x + 30 ม.) · stop = ท่าหยุด
func _send_pose(stop: bool) -> void:
	if not online() or not _opened:
		return
	var av := world.avatar
	var p := av.global_position
	var pose := {"x": clampi(roundi(PackRooms.to_band(p.x) * 100.0), -5000, 5000), "z": clampi(roundi(p.z * 100.0), -5000, 5000),
		"yaw": roundi(wrapf(av.face, -PI, PI) * 1000.0), "sp": 0 if stop else clampi(roundi(av.speed() * 100.0), 0, 2000),
		"run": false if stop else av.running(), "t": Time.get_ticks_msec()}
	net.call("send_pose", pose, stop)


func _on_net_state(state: StringName) -> void:
	sync_online()
	var st := str(state)
	if st == "hosting" or st == "joined":
		_send_pose(true)
	if active and st == "reconnecting":
		show_note(OnlineText.REASONS["reconnecting"])


func _on_reconnected() -> void:
	if active:
		show_note(OnlineText.REASONS["reconnected"])


## เจ้าห้องเปิดหน้าตั้งเกม: บอกเพื่อนในห้องนี้ว่าไปเลือกที่นั่งได้ที่สถานีไหน (ครั้งเดียวต่อการเปิด เหมือนดาดฟ้า)
func _on_net_message(_from: int, kind: int, body: Dictionary) -> void:
	if kind != NetProto.SETUP:
		return
	var open_now := bool(body.get("open", false))
	if open_now and not _setup_open and active and online() and not bool(net.call("is_host")):
		show_note(SETUP_OPEN_AT, {"place": PackRooms.setup_place(room)})
	_setup_open = open_now


## ท่าของเพื่อน: ในแถบห้อง = วาดในห้องที่ x − 30 ม.; นอกแถบ = เพื่อนอยู่บนดาดฟ้า ไม่วาดที่นี่
func _on_pose(slot: int, pose: Dictionary) -> void:
	if slot == _my_slot():
		return
	var inside := PackRooms.in_band(pose)
	if inside != bool(_in.get(slot, false)):
		_in[slot] = inside
		sync_online()
	if inside:
		var p := pose.duplicate()
		p["x"] = int(pose.get("x", 0)) - roundi(PackRooms.POSE_X * 100.0)
		world.friends.push_pose(slot, p, Time.get_ticks_msec())
