extends Control
## หน้าล็อบบี้ "ดาดฟ้ายานรบ" (ล็อบบี้ที่เดินได้, LOBBY_SPEC §2.5, SHIP_LOBBY_SPEC): ปุ่มและข้อความบนห้อง 3 มิติ (HallWorld)
## ข้อความไทยทั้งหมดของล็อบบี้อยู่ในไฟล์นี้ (ป้าย 3 มิติรวมป้ายชื่อสถานที่ "title" รับข้อความผ่าน world.set_sign_text)
## เดินถึงสถานีแล้วกด E หรือแตะ %UseButton: โต๊ะรบโฮโลแกรม → ตั้งเกม, คลังแสง → หน้าจัดกองทัพ, คอนโซล → ตั้งค่า,
## ประตูเทียบยาน → หน้าเล่นกับเพื่อน (lobby.tscn, NET_SPEC §7), โต๊ะผจญภัย / โต๊ะทำงาน → แผง "เร็วๆ นี้",
## ประตูทางออก (หรือ ‹ หน้าแรก) → กลับหน้าแรก
## ออนไลน์ (NET_SPEC §6): ส่งท่าตัวเองผ่าน Net (≤ 1 ครั้ง / 100 มิลลิวิ ตอนเดิน + ท่าหยุดหนึ่งครั้ง) ไข่เพื่อนบนดาดฟ้า
## ป้ายชื่อและบรรทัดสถานะใน %FriendTags แผง "เร็วๆ นี้" ใช้แจ้งเพื่อนเข้า/ออก · ออฟไลน์ทุกอย่างเหมือนเดิม
## ประตูอารีน่า (เดินเข้าช่องประตูหรือกด E) → จอมืดแวบหนึ่งแล้วเปิดหน้าอารีน่า; กลับมายืนที่ ARENA_RETURN (ARENA_SPEC §2.3)
## เดินถึงประตูอารีน่า: เริ่มโหลดไฟล์หนักของอารีน่าในเธรด (หน้า ตัวผู้เล่น สัตว์รัง ท่าทาง โมเดล) ตอนจอมืดเหลือแค่สร้างฉาก
## เก็บไว้ในหน้านี้ให้รอบต่อไปเข้าเร็ว (ไม่ใช่งานต่อเฟรม)
## ถูกหน้าอื่นทับ: ซ่อนห้อง หยุดงาน คืนกล้อง; กลับมาโชว์: อ่าน App.gfx / lang / touch ใหม่ทุกครั้ง
## งานต่อเฟรม: ไม่มี (ข้อความเปลี่ยนตามสัญญาณ แผง "เร็วๆ นี้" ปิดด้วย Timer)
## ห้องเสริม (PACK_SPEC §9): ชุดเสริมมีห้องของประตูเทียบยานและสวิตช์ online เปิด → เดินเข้าประตู/กด E = จอมืดแล้วเปิดห้อง
## กลับมายืนที่ AIRLOCK_RETURN · เพื่อนที่ท่าอยู่ในแถบห้อง (PackRooms.in_band) ไม่วาดบนดาดฟ้า
## ไม่มีห้อง (แอปสาธารณะ): ประตูเทียบยานเป็นแค่ฉาก ไม่มีวง · เล่นกับเพื่อนเปิดจากปุ่มออนไลน์หน้าแรก เพื่อนอยู่บนดาดฟ้า
## เพื่อน (ไม่ใช่เจ้าห้อง) ที่โต๊ะรบตอนเจ้าห้องตั้งเกม = เปิดหน้าเล่นกับเพื่อนเลือกที่นั่ง
## ห้องที่มีประตูอารีน่า (action arena): ประตูอารีน่าบนดาดฟ้าปิด (ไม่มีวง ไม่มีปุ่ม เดินเข้าไม่ได้ บานปิดทึบ)

signal station_changed(id: String)

const BATTLE_SETUP := "res://ui/screens/battle_setup.tscn"
const ARMY := "res://ui/screens/army.tscn"
const SETTINGS_SCREEN := "res://ui/screens/settings.tscn"
const ARENA_SCREEN := "res://ui/screens/arena_screen.tscn"
const LOBBY_SCREEN := "res://ui/screens/lobby.tscn"
const PACK_ROOM_SCREEN := "res://ui/screens/pack_room_screen.tscn"
const FADE_TIME := 0.25
## ไฟล์ที่โหลดล่วงหน้าตอนถึงประตูอารีน่า (+ โมเดลของสัตว์รัง KitLibrary.kit_path(ArenaData.BEAST.kit))
const ARENA_PRELOAD: PackedStringArray = ["res://ui/screens/arena_screen.tscn", "res://scenes/arena/arena_player.tscn",
	"res://scenes/arena/hive_beast.tscn", "res://assets/anim/humanoid.res", "res://scenes/arena/egg_gunner.gd",
	"res://scenes/arena/kit_beast.gd"]
## ชื่อสถานีบนปุ่มใช้งาน
const NAMES := {
	"battle": "โต๊ะรบ",
	"army": "คลังแสงกองทัพ",
	"settings": "ตั้งค่า",
	"online": "ประตูเทียบยาน",
	"adventure": "โต๊ะผจญภัย",
	"exit": "ทางออก",
	"vault": "โต๊ะทำงาน",
	"arena": "อารีน่าทดสอบอาวุธ",
}
## ป้าย 3 มิติเหนือสถานี
const SIGNS := {
	"battle": "โต๊ะรบ",
	"army": "คลังแสงกองทัพ",
	"settings": "ตั้งค่า",
	"online": "ประตูเทียบยาน · เล่นกับเพื่อน",
	"adventure": "โต๊ะผจญภัย · เร็วๆ นี้",
	"exit": "ทางออก",
	"vault": "โต๊ะทำงาน · คลังของ",
	"arena": "อารีน่าทดสอบอาวุธ",
}
## แผง "เร็วๆ นี้" ของสถานีที่ยังไม่เปิด (โต๊ะทำงาน = คลังของจากแคมเปญและของรางวัลสุ่มรอบหน้า ตอนนี้ยังไม่มีของจริง)
## ประตูเทียบยานเปิดแล้ว (NET_SPEC §7.1): ไม่อยู่ในนี้
const SOON := {
	"adventure": "โต๊ะผจญภัย — เร็วๆ นี้",
	"vault": "โต๊ะทำงาน — เร็วๆ นี้: เก็บของจากแคมเปญและของรางวัลสุ่ม",
}
## แอปสาธารณะ (ไม่มีสวิตช์ online ใน res://packs/features.json): ประตูเทียบยานกลับเป็น "เร็วๆ นี้"
const SIGN_SOON_ONLINE := "ประตูเทียบยาน · เร็วๆ นี้"
const SOON_ONLINE := "ประตูเทียบยาน — เร็วๆ นี้: ลานปล่อยยานและเล่นกับเพื่อน"
## ชื่อสถานที่บนแผ่นป้ายใต้หน้าต่างกลาง
const PLACE := "ดาดฟ้ายานรบ"
const YOU := "คุณ"
const MENU_TEXT := "‹ หน้าแรก"
const SETTINGS_TEXT := "ตั้งค่า"
const PROMPT_KEYS := "{name} · กด E"
const PROMPT_TOUCH := "{name} · แตะเพื่อใช้"
const HINT_KEYS := "WASD หรือลูกศร เดิน · Shift วิ่ง · ลากเมาส์หมุนกล้อง"
const HINT_TOUCH := "ใช้ปุ่มซ้ายล่างเดิน · ลากจอหมุนกล้อง"
const SOON_SECONDS := 2.5
## ตอนออนไลน์ (NET_SPEC §7.1): โต๊ะรบบนเครื่องเพื่อน, เพื่อนเข้า/ออก, เจ้าห้องเปิดหน้าตั้งเกม
const CLIENT_TABLE := "เจ้าห้องเป็นคนตั้งเกม — รอเจ้าห้องกดเริ่ม"
const JOINED := "{name} เข้าห้องแล้ว"
const LEFT := "{name} ออกจากห้อง"
const DROPPED := "{name} หลุดจากห้อง — รอต่อใหม่"
const BACK := "{name} กลับมาแล้ว"
const SETUP_OPEN := "เจ้าห้องกำลังตั้งเกม — เลือกที่นั่งได้ที่โต๊ะรบ"
## มีห้องเสริม: บอกที่เลือกที่นั่งเป็นชื่อสถานีในห้อง ({place} จาก room.json) · เปิดห้องไม่ได้ = เปิดหน้าเล่นกับเพื่อนแทน
const SETUP_OPEN_AT := "เจ้าห้องกำลังตั้งเกม — เลือกที่นั่งได้ที่{place}"
const ROOM_FAILED := "เปิดห้องไม่ได้ — เปิดหน้าเล่นกับเพื่อนแทน"
const POSE_MS := 100          # ส่งท่าตอนเดินไม่ถี่กว่านี้
const MAX_PLAYERS := 6        # NetSession.MAX_PLAYERS
const USE_H := 64.0
const USE_H_TOUCH := 80.0
const STEP_WALK := 1.15       # ระยะต่อก้าว (ม.) ของเสียงเท้าตอนเดิน / วิ่ง
const STEP_RUN := 1.7

@onready var world: HallWorld = $HallWorld
@onready var margin: MarginContainer = $Safe
@onready var use_button: Button = %UseButton
@onready var stick: TouchStick = %Stick
@onready var menu_button: Button = %MenuButton
@onready var settings_button: Button = %SettingsButton
@onready var soon_panel: PanelContainer = %SoonPanel
@onready var soon_label: Label = %SoonLabel
@onready var hint: Label = %Hint
@onready var soon_timer: Timer = %SoonTimer
@onready var fade: ColorRect = %Fade
@onready var tags: FriendTags = %FriendTags
@onready var pose_timer: Timer = %PoseTimer

var touch_mode := false
var active := false

var _hint_done := false
var _soon := ""
var _hint_tween: Tween
var _entering := false
var _from_arena := false
var _from_room := false              # อยู่ในห้องเสริม (หน้าห้องทับอยู่): ไม่ส่งท่าของดาดฟ้า
var _room_failed := false            # เปิดห้องไม่ได้: แจ้งเมื่อกลับมาบนดาดฟ้า
## รากของห้องเสริม (เทสชี้ไปที่ห้องทดสอบได้)
var rooms_root := PackRooms.root()
var _away: Dictionary = {}           # slot → ท่าล่าสุดของเพื่อนอยู่ในแถบห้องเสริม (ไม่วาดบนดาดฟ้า)
var _band_pose: Dictionary = {}      # slot → ท่าล่าสุดในแถบห้อง (ส่งต่อให้ห้องตอนเราเข้า)
var _fading := false
var _fade_tween: Tween
var _arena_res: Dictionary = {}      # path → Resource ที่โหลดแล้ว (null = ขอโหลดในเธรดอยู่)
## manifest ของชุดเสริมที่ preload_arena อ่าน (เทสชี้ไปที่ชุดทดสอบได้)
var pack_manifest := ArenaActors.PACK_MANIFEST
## ระบบออนไลน์ (autoload Net; เทสใส่ของปลอมผ่าน use_net) · null = ไม่มี ออฟไลน์เสมอ
var net: Node

var _note := ""                      # แผง "เร็วๆ นี้" ที่ใช้แจ้งเรื่องออนไลน์ (คีย์ไทย + ตัวแปร)
var _note_args: Dictionary = {}
var _members: Dictionary = {}        # slot → ชื่อ ของสมาชิกที่รู้จักล่าสุด (แจ้งเข้า/ออก)
var _here: Dictionary = {}           # slot → here ล่าสุด (แจ้งหลุด/กลับมา)
var _members_known := false
var _setup_open := false
var _pose_ms := -100000
var _net_state := &"off"             # สถานะ Net ล่าสุด (เข้าห้องใหม่ ≠ ต่อกลับ)
var _step_d := 0.0                    # ระยะเดินสะสมของเสียงเท้า
var _step_p := Vector3.INF


func _ready() -> void:
	CandleStyle.button(menu_button)
	CandleStyle.button(settings_button)
	CandleStyle.button(use_button, true)
	CandleStyle.panel(soon_panel)
	CandleStyle.text(soon_label, 24)
	CandleStyle.text(hint, 19)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(CandleStyle.PANEL, 0.78)
	sb.set_corner_radius_all(10)
	sb.set_content_margin_all(10.0)
	sb.content_margin_left = 18.0
	sb.content_margin_right = 18.0
	hint.add_theme_stylebox_override(&"normal", sb)
	for b: Button in [menu_button, settings_button, use_button]:
		b.focus_mode = Control.FOCUS_NONE
	menu_button.pressed.connect(_go_menu)
	settings_button.pressed.connect(_open_settings)
	use_button.pressed.connect(use_station)
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
	use_button.hide()
	visibility_changed.connect(_on_visibility)
	get_viewport().size_changed.connect(_on_resize)
	use_net(net if net != null else get_node_or_null(^"/root/Net"))
	if online():
		world.place_avatar(HallFriends.spawn_for(_my_slot()), PI)
	_activate(is_visible_in_tree())


## อ่านตั้งค่าใหม่ (ระดับกราฟิก ภาษา ปุ่มบนจอ) แล้ววาดข้อความทั้งหมด
func refresh() -> void:
	touch_mode = App.touch_active()
	world.apply_level(App.gfx)
	stick.visible = touch_mode
	use_button.custom_minimum_size.y = USE_H_TOUCH if touch_mode else USE_H
	use_button.add_theme_font_size_override(&"font_size", 26 if touch_mode else 22)
	menu_button.text = I18n.t(MENU_TEXT)
	settings_button.text = I18n.t(SETTINGS_TEXT)
	var room := door_room()
	# ไม่มีห้องเสริม (แอปสาธารณะ): ประตูเทียบยานเป็นแค่ฉาก · ห้องมีประตูอารีน่า: ประตูอารีน่าบนดาดฟ้าปิด ป้ายว่าง
	var shut := arena_moved()
	world.set_station_enabled("online", not room.is_empty())
	world.set_station_enabled("arena", not shut)
	for id in SIGNS:
		world.set_sign_text(id, PackRooms.text(room["door_sign"]) if id == "online" and not room.is_empty() else I18n.t(sign_of(id)))
	if shut:
		world.set_sign_text("arena", "")
	world.set_sign_text("title", I18n.t(PLACE))
	world.set_sign_text("you", I18n.t(YOU))
	hint.text = I18n.t(HINT_TOUCH if touch_mode else HINT_KEYS)
	hint.visible = not _hint_done
	if _soon != "":
		soon_label.text = I18n.t(soon_of(_soon))
	elif _note != "":
		soon_label.text = I18n.t(_note).format(_note_args)
	_update_prompt()
	CandleStyle.safe_margins(margin)
	sync_online()


## สถานีที่ตัวผู้เล่นเอื้อมถึงตอนนี้ ("" = ไม่มี)
func station() -> String:
	return world.station()


## ใช้สถานีตรงหน้า (เหมือนกด E หรือแตะปุ่มใช้งาน)
func use_station() -> void:
	if not active:
		return
	_sfx(&"heal")   # เสียงติ๊งตอนใช้สถานี
	match station():
		"battle":
			# ออนไลน์บนเครื่องเพื่อน: เจ้าห้องเป็นคนตั้งเกม (NET_SPEC §7.1) · ไม่มีห้องเสริม + กำลังตั้งเกม = เลือกที่นั่ง
			if online() and not bool(net.call("is_host")):
				if _setup_open and door_room().is_empty():
					open_online()
				else:
					show_note(CLIENT_TABLE)
			else:
				_push(BATTLE_SETUP)
		"army":
			_push(ARMY)
		"settings":
			_push(SETTINGS_SCREEN)
		"online":
			if not door_room().is_empty():
				enter_room()
			else:
				open_online()
		"adventure", "vault":
			show_soon(station())
		"exit":
			_go_menu()
		"arena":
			enter_arena()


## แผง "เร็วๆ นี้" ของสถานีที่ยังไม่เปิด ปิดเองใน 2.5 วิ เมื่อเดิน หรือเมื่อกดย้อนกลับ
func show_soon(id: String) -> void:
	if soon_of(id) == "":
		return
	_soon = id
	_note = ""
	soon_label.text = I18n.t(soon_of(id))
	soon_panel.show()
	soon_timer.start(SOON_SECONDS)


## ข้อความไทยของแผง "เร็วๆ นี้" ("" = สถานีนี้เปิดแล้ว)
static func soon_of(id: String) -> String:
	if id == "online" and not Features.on(&"online"):
		return SOON_ONLINE
	return str(SOON.get(id, ""))


## ป้าย 3 มิติของสถานี (ประตูเทียบยานขึ้นกับสวิตช์ online)
static func sign_of(id: String) -> String:
	if id == "online" and not Features.on(&"online"):
		return SIGN_SOON_ONLINE
	return str(SIGNS.get(id, ""))


## แจ้งเรื่องออนไลน์ในแผงเดียวกัน (key = ข้อความไทยทั้งก้อน แปลแล้วค่อยเติม args) ปิดเองใน 2.5 วิ
func show_note(key: String, args: Dictionary = {}) -> void:
	_soon = ""
	_note = key
	_note_args = args
	soon_label.text = I18n.t(key).format(args)
	soon_panel.show()
	soon_timer.start(SOON_SECONDS)


func close_soon() -> void:
	soon_timer.stop()
	soon_panel.hide()
	_soon = ""
	_note = ""


## ปุ่มย้อนกลับ / Esc: ปิดแผง "เร็วๆ นี้" ก่อน ไม่มีแผงก็ให้ App ถอยกลับหน้าแรก
func handle_back() -> bool:
	if _fading or _entering:
		return true
	if soon_panel.visible:
		close_soon()
		return true
	return false


func _unhandled_input(event: InputEvent) -> void:
	if not active or _fading or not InputMap.has_action(&"interact"):
		return
	if event.is_action_pressed(&"interact"):
		get_viewport().set_input_as_handled()
		use_station()


# ---- ภายใน ----

func _activate(on: bool) -> void:
	active = on
	world.set_active(on)
	if on:
		_hide_table()
		refresh()
		if _from_arena:
			_from_arena = false
			world.place_avatar(HallLayout.ARENA_RETURN, PI)
			world.camera_rig.set_view(0.0, -0.45, 6.5)
			_fade_in_back()
		elif _from_room:
			_from_room = false
			world.place_avatar(HallLayout.AIRLOCK_RETURN, -PI * 0.5)
			world.camera_rig.set_view(PI * 0.5, -0.45, 6.5)
			_fade_in_back()
		if _room_failed:
			_room_failed = false
			show_note(ROOM_FAILED)
		# กลับมาบนดาดฟ้า: บอกห้องว่าอยู่ที่ไหน (ออฟไลน์ Net จำไว้ใช้ตอนเปิดห้อง) แล้วส่งท่ายืนหนึ่งครั้ง (NET_SPEC §6.1)
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
	if is_visible_in_tree() != active:
		_activate(is_visible_in_tree())


func _on_resize() -> void:
	if active:
		CandleStyle.safe_margins(margin)
		_place_status.call_deferred()


func _on_station(id: String) -> void:
	_update_prompt()
	if id != "" and active:
		_sfx(&"ui")
	if id == "arena":
		preload_arena()
	station_changed.emit(id)


func _update_prompt() -> void:
	var id := world.station()
	use_button.visible = active and id != ""
	if id != "":
		var room := door_room() if id == "online" else {}
		var nm := PackRooms.text(room["title"]) if not room.is_empty() else I18n.t(NAMES[id])
		use_button.text = I18n.t(PROMPT_TOUCH if touch_mode else PROMPT_KEYS).format({"name": nm})


## ผู้เล่นเริ่มเดิน (มีคำสั่งเดินจริง ไม่ใช่แค่ชะลอตัว): ซ่อนคำแนะนำครั้งแรก และปิดแผง "เร็วๆ นี้"
## ออนไลน์: ส่งท่าทุกการขยับ (รวมตอนชะลอ) ไม่ถี่กว่า 100 มิลลิวิ แล้วท่าหยุดเมื่อนิ่งครบ 0.25 วิ
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
	if world.station() == "arena" and HallLayout.in_arena_doorway(Vector2(p.x, p.z)):
		enter_arena()
		return
	if world.station() == "online" and HallLayout.in_airlock(Vector2(p.x, p.z)) and not door_room().is_empty():
		enter_room()
		return
	if soon_panel.visible:
		close_soon()
	if not _hint_done:
		_hint_done = true
		if App.gfx == "min" or App.gfx == "lo":
			hint.hide()
		else:
			_hint_tween = create_tween()
			_hint_tween.tween_property(hint, ^"modulate:a", 0.0, 0.4)
			_hint_tween.tween_callback(hint.hide)
		_place_status.call_deferred()


## เสียงเท้าบนดาดฟ้า: ทุกระยะหนึ่งก้าว (วิ่งก้าวยาวกว่า) เสียงกระทืบเบา ๆ แหลมขึ้นนิด ตามจุดที่ยืน
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


func hint_done() -> bool:
	return _hint_done


## เข้าอารีน่า (ครั้งเดียวต่อการกด): หยุดตัวผู้เล่น จอมืด แล้วเปิดหน้าอารีน่าทับ (hi/mid ค่อย ๆ มืด lo/min ตัดภาพ)
func enter_arena() -> void:
	if not active or _entering or _fading:
		return
	_entering = true
	preload_arena()
	_set_where(&"arena")
	world.avatar.halt()
	world.avatar.process_mode = Node.PROCESS_MODE_DISABLED
	stick.release()
	close_soon()
	await _fade_to(1.0)
	_entering = false
	_from_arena = true
	var ps := _arena_scene()
	if not active or ps == null or App.push(ps) == null:
		_from_arena = false
		world.avatar.process_mode = Node.PROCESS_MODE_INHERIT
		await _fade_to(0.0)


func fading() -> bool:
	return _fading or _entering


## ห้องเสริมของประตูเทียบยาน ({} = ไม่มี หรือสวิตช์ online ปิด: ดาดฟ้าเหมือนเดิม)
func door_room() -> Dictionary:
	return PackRooms.for_door("online", rooms_root)


## อารีน่าย้ายไปอยู่ในห้องเสริม (ห้องมีสถานี action arena): ประตูอารีน่าบนดาดฟ้าปิด
func arena_moved() -> bool:
	return PackRooms.arena_station(door_room()) != ""


## เข้าห้องเสริม: instant = เปิดทันทีหน้าสถานีที่พาไปเล่นกับเพื่อน (หน้าแรก → ออนไลน์) คืนหน้าห้อง
## ไม่งั้นหยุดตัวผู้เล่น จอมืด แล้วเปิดห้องที่จุดเกิด (คืน null; หน้าห้องเปิดหลังจอมืด) · เปิดไม่ได้ = หน้าเล่นกับเพื่อน
func enter_room(instant := false) -> Node:
	if not active or _entering or _fading or door_room().is_empty():
		return null
	if instant:
		return _open_room(PackRooms.online_station(door_room()))
	_enter_room_faded()
	return null


func _enter_room_faded() -> void:
	_entering = true
	world.avatar.halt()
	world.avatar.process_mode = Node.PROCESS_MODE_DISABLED
	stick.release()
	close_soon()
	await _fade_to(1.0)
	_entering = false
	if not active or _open_room("") == null:
		world.avatar.process_mode = Node.PROCESS_MODE_INHERIT
		if fade.visible and not _fading:
			await _fade_to(0.0)


## เปิดหน้าห้องทับดาดฟ้า (คืนหน้าห้อง) · เปิดไม่ได้: ปิดหน้าห้อง จอสว่าง แล้วเปิดหน้าเล่นกับเพื่อนแทน (คืนหน้านั้น)
func _open_room(at_station: String) -> Node:
	var room := door_room()
	if not active or room.is_empty() or not ResourceLoader.exists(PACK_ROOM_SCREEN):
		return null
	_from_room = true
	var screen := App.push(load(PACK_ROOM_SCREEN))
	if screen != null:
		screen.set("hall", self)
	if screen != null and screen.call("open", room, at_station):
		screen.call("seed_poses", _band_pose.duplicate())
		return screen
	push_warning("hall: the pack room %s did not open" % str(room.get("id", "")))
	if screen != null and App.current() == screen:
		App.pop()
	_from_room = false
	world.avatar.process_mode = Node.PROCESS_MODE_INHERIT
	if _fade_tween != null:
		_fade_tween.kill()
	_fading = false
	fade.hide()
	fade.color.a = 0.0
	fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var lobby := open_online()
	if lobby == null:
		show_note(ROOM_FAILED)
	else:
		_room_failed = true
	return lobby


## เริ่มโหลดไฟล์ของอารีน่าในเธรด (ครั้งเดียวต่อไฟล์; เรียกซ้ำได้)
func preload_arena() -> void:
	var paths := Array(ARENA_PRELOAD)
	paths.append(KitLibrary.kit_path(str(ArenaData.BEAST["kit"])))
	# ตัวละครชุดเสริม (PACK_SPEC §4 H3): ไม่มีชุดเสริม = ทางเดิมใน ARENA_PRELOAD (ข้ามเพราะซ้ำ)
	paths.append(ArenaActors.resolve("player", pack_manifest))
	paths.append(ArenaActors.resolve("enemy", pack_manifest))
	for p: String in paths:
		if _arena_res.has(p) or not ResourceLoader.exists(p):
			continue
		if ResourceLoader.load_threaded_request(p) == OK:
			_arena_res[p] = null


## ฉากของหน้าอารีน่า (ห้องเสริมที่มีประตูอารีน่าเรียกใช้)
func arena_scene() -> PackedScene:
	return _arena_scene()


## ไฟล์ที่ขอไว้ทั้งหมด (รอให้เสร็จถ้ายังโหลดอยู่) แล้วคืนฉากของหน้าอารีน่า
func _arena_scene() -> PackedScene:
	for p: String in _arena_res.keys():
		if _arena_res[p] == null:
			_arena_res[p] = ResourceLoader.load_threaded_get(p)
	var ps := _arena_res.get(ARENA_SCREEN) as PackedScene
	if ps == null and ResourceLoader.exists(ARENA_SCREEN):
		ps = load(ARENA_SCREEN) as PackedScene
	return ps


## จำนวนไฟล์ของอารีน่าที่ขอโหลด/โหลดแล้ว (เทส)
func arena_preloaded() -> Dictionary:
	var done := 0
	for p in _arena_res:
		if _arena_res[p] != null or ResourceLoader.load_threaded_get_status(p) == ResourceLoader.THREAD_LOAD_LOADED:
			done += 1
	return {"requested": _arena_res.size(), "loaded": done}


## กลับจากอารีน่า: จอค่อย ๆ สว่าง แล้วค่อยให้เดินได้
func _fade_in_back() -> void:
	await _fade_to(0.0)
	world.avatar.process_mode = Node.PROCESS_MODE_INHERIT


## จอมืด (alpha 1) หรือสว่าง (alpha 0): hi/mid ใช้ Tween 0.25 วิ, lo/min มืดหนึ่งเฟรมแล้วเปลี่ยน (ไม่สร้าง Tween)
## ระหว่างนั้นกันการแตะ (STOP) และปุ่มย้อนกลับ
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


func _go_menu() -> void:
	if active:
		App.pop()


func _open_settings() -> void:
	_push(SETTINGS_SCREEN)


func _push(path: String) -> Node:
	if not ResourceLoader.exists(path):
		push_warning("hall: no screen at " + path)
		return null
	match path:
		BATTLE_SETUP:
			_set_where(&"setup")
		ARMY:
			_set_where(&"army")
		SETTINGS_SCREEN:
			_set_where(&"settings")
	return App.push(load(path))


# ---- ออนไลน์ (NET_SPEC §6, §7.1) ----

## เปิดหน้าเล่นกับเพื่อนทับห้องโถง (ทุกแอป; แอปสาธารณะเล่นกันบนดาดฟ้า)
func open_online() -> Node:
	if not active:
		return null
	return _push(LOBBY_SCREEN)


## ยืนหน้าประตูเทียบยาน หันเข้าประตู กล้องอยู่ข้างหลัง (หน้าแรก → ออนไลน์)
func enter_airlock() -> void:
	var f: Vector2 = HallLayout.STATIONS["online"]["front"]
	world.place_avatar(Vector3(f.x, 0.0, f.y), PI * 0.5)
	world.camera_rig.set_view(-PI * 0.5, -0.35, 5.5)


## ต่อกับระบบออนไลน์ n (autoload Net หรือของปลอมในเทส; null = ออฟไลน์) แล้ววาดสถานะใหม่
func use_net(n: Node) -> void:
	var handlers := {"members_changed": _on_members, "state_changed": _on_net_state, "pose": _on_pose,
		"message": _on_net_message, "reconnected": _on_reconnected}
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
	if is_node_ready():
		sync_online()


func online() -> bool:
	return net != null and is_instance_valid(net) and bool(net.call("is_online"))


## เพื่อนบนดาดฟ้า สีของตัวเอง ป้ายชื่อ และบรรทัดสถานะตามรายชื่อในห้อง; ออฟไลน์ล้างทั้งหมด (หน้าตาเหมือนเดิม)
func sync_online() -> void:
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
			if str(m.get("where", "")) == "deck" and bool(m.get("here", true)) and not bool(_away.get(s, false)):
				world.friends.set_friend(s, nm, HallWorld.slot_colour(s))
			else:
				world.friends.remove_friend(s)
	for s in world.friends.slots():
		if not seen.has(s):
			world.friends.remove_friend(s)
	var fresh := false
	if on and _members_known:
		for s in seen:
			if not _members.has(s):
				fresh = true
	if on and _members_known and active:
		for s in seen:
			if not _members.has(s):
				show_note(JOINED, {"name": seen[s]})
		for s in _members:
			if not seen.has(s):
				show_note(LEFT, {"name": _members[s]})
		# หลุดตอนนี้ (ช่องยังเก็บไว้ 60 วินาที) / กลับมาแล้ว
		for s in here:
			if _here.has(s) and bool(_here[s]) != bool(here[s]):
				show_note(BACK if bool(here[s]) else DROPPED, {"name": seen[s]})
	_members = seen
	_here = here
	_members_known = on
	if not on:
		_setup_open = false
		_away.clear()
		_band_pose.clear()
	else:
		# ช่องที่ไม่อยู่ในรายชื่อแล้ว: ลืมท่าในห้องเสริม (คนใหม่ที่ได้ช่องนี้เริ่มที่ดาดฟ้า)
		for s in _away.keys():
			if not seen.has(s):
				_away.erase(s)
		for s in _band_pose.keys():
			if not seen.has(s):
				_band_pose.erase(s)
	# คนใหม่เข้าห้อง: ส่งท่ายืนของเราอีกครั้งให้เขารู้ว่าเรายืนตรงไหน
	if fresh and active:
		_send_pose(true)
	var with_friends := on and world.friends.friend_count() > 0
	world.set_you_tag_visible(not with_friends)
	tags.set_you(I18n.t(YOU) if with_friends else "")
	tags.set_status(_status_text() if on else "")
	_place_status()
	tags.refresh()


func _status_text() -> String:
	# หลุดจากเจ้าห้องอยู่: บรรทัดสถานะบอกค้างไว้จนต่อได้หรือเลิก (ไม่ใช่แค่ป้าย 2.5 วินาที)
	if str(net.call("state")) == "reconnecting":
		return I18n.t(OnlineText.REASONS["reconnecting"])
	var host := net.call("member", 0) as Dictionary
	var n := (net.call("members") as Array).size()
	var cap: Variant = net.get("max_players")
	return OnlineText.status(str(host.get("nm", "")) if host != null else "", n, int(cap) if cap != null else MAX_PLAYERS)


## บรรทัดสถานะ: ระหว่างปุ่มบนสุดถ้าพอ ไม่งั้นใต้ปุ่ม (และใต้คำแนะนำครั้งแรกถ้ายังโชว์)
func _place_status() -> void:
	var text := tags.status_text()
	if text == "":
		return
	var origin := tags.get_global_rect().position
	var left := menu_button.get_global_rect()
	var right := settings_button.get_global_rect()
	var w := CandleStyle.BOLD.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, FriendTags.FONT_SIZE).x
	var line_h := CandleStyle.BOLD.get_height(FriendTags.FONT_SIZE)
	var centre := tags.size.x * 0.5
	if centre - w * 0.5 >= left.end.x - origin.x + 12.0 and centre + w * 0.5 <= right.position.x - origin.x - 12.0:
		tags.status_y = left.position.y - origin.y + (left.size.y - line_h) * 0.5
	else:
		var below := left.end.y
		if hint.visible:
			below = maxf(below, hint.get_global_rect().end.y)
		tags.status_y = below - origin.y + 6.0
	tags.refresh()


func _my_slot() -> int:
	return int(net.call("my_slot")) if net != null else -1


func _set_where(w: StringName) -> void:
	if net != null and is_instance_valid(net):
		net.call("set_where", w)


## ท่าของตัวเอง (ซม. มิลลิเรเดียน ซม./วิ) ไปให้ห้อง; stop = ท่าหยุด (ส่งแบบไม่หาย)
func _send_pose(stop: bool) -> void:
	if not online() or _from_room:
		return
	var av := world.avatar
	var p := av.global_position
	var pose := {"x": clampi(roundi(p.x * 100.0), -5000, 5000), "z": clampi(roundi(p.z * 100.0), -5000, 5000),
		"yaw": roundi(wrapf(av.face, -PI, PI) * 1000.0), "sp": 0 if stop else clampi(roundi(av.speed() * 100.0), 0, 2000),
		"run": false if stop else av.running(), "t": Time.get_ticks_msec()}
	net.call("send_pose", pose, stop)


func _on_members() -> void:
	sync_online()


func _on_net_state(_state: StringName) -> void:
	sync_online()
	var st := str(_state)
	# เพิ่งเข้าห้องเพื่อน (ไม่ใช่ต่อกลับ): ยืนที่จุดของช่องตัวเองบนดาดฟ้า หันไปทางโต๊ะรบ (NET_SPEC §6.1) ไม่ซ้อนกับใคร
	if st == "joined" and _net_state == &"connecting":
		world.place_avatar(HallFriends.spawn_for(_my_slot()), PI)
		world.camera_rig.set_view(HallLayout.SPAWN_YAW, -0.45, 6.5)
	_net_state = _state
	# เพิ่งเปิดห้อง/เข้าห้อง (หน้าเล่นกับเพื่อนอาจบังอยู่): ส่งท่ายืนตอนนี้ให้ห้องเห็นตัวเราทันที
	if st == "hosting" or st == "joined":
		_send_pose(true)
	if active and st == "reconnecting":
		show_note(OnlineText.REASONS["reconnecting"])


func _on_reconnected() -> void:
	if active:
		show_note(OnlineText.REASONS["reconnected"])


func _on_pose(slot: int, pose: Dictionary) -> void:
	if slot == _my_slot():
		return
	# ท่าในแถบห้องเสริม: เพื่อนอยู่ในห้อง ไม่วาดบนดาดฟ้า (จำท่าไว้ให้ห้องตอนเราเข้า)
	var away := PackRooms.in_band(pose)
	if away:
		_band_pose[slot] = pose
	else:
		_band_pose.erase(slot)
	if away != bool(_away.get(slot, false)):
		_away[slot] = away
		sync_online()
	if not away:
		world.friends.push_pose(slot, pose, Time.get_ticks_msec())


## ท่าล่าสุดของเพื่อนที่อยู่ในห้องเสริม (slot → pose ในแถบห้อง)
func band_poses() -> Dictionary:
	return _band_pose.duplicate()


## เจ้าห้องเปิดหน้าตั้งเกม: บอกเพื่อนบนดาดฟ้าว่าไปเลือกที่นั่งได้ที่ประตูเทียบยาน (ครั้งเดียวต่อการเปิด)
func _on_net_message(_from: int, kind: int, body: Dictionary) -> void:
	if kind != NetProto.SETUP:
		return
	var open := bool(body.get("open", false))
	if open and not _setup_open and active and online() and not bool(net.call("is_host")):
		var room := door_room()
		if room.is_empty():
			show_note(SETUP_OPEN)
		else:
			show_note(SETUP_OPEN_AT, {"place": PackRooms.setup_place(room)})
	_setup_open = open


func _on_view() -> void:
	if tags.visible:
		tags.refresh()


## โต๊ะรบ (โลกเดียวกัน) ต้องซ่อนและหยุดเสมอขณะห้องโถงอยู่บนสุด
func _hide_table() -> void:
	var t := get_tree().get_first_node_in_group("table_view") as Node3D
	if t != null:
		t.visible = false
		t.process_mode = Node.PROCESS_MODE_DISABLED
