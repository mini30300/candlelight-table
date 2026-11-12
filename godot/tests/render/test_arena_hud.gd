extends SceneTree
## The arena's shooter HUD and controls (ARENA_SPEC §5, §6.4–6.6, §13.4 PLAYER), on the real arena screen (pushed straight
## onto the main scene's stack; the hive beast is used when its scene exists, the HUD works without it).
## Contract: the screen's Hud is an ArenaHud with Ammo, Hint, Hurt, Downed and Touch (Stick, AimPad, FireButton,
## MeleeButton, ReloadButton, WeaponButton); the player is an ArenaPlayer with an EggGunner figure.
## Walk mode at the spawn: corridor hint, no ammo line, no shooter buttons, mouse visible. Shoot mode (placed past the
## shoot line): the rifle is drawn, ammo 30 / 30, the crosshair rect is centred on the viewport (±1 px), the mouse is
## captured (desktop), the keyboard hint shows. Holding the fire action 1 s fires 8 ± 1 shots (tracers alive), the ammo
## line follows, R shows the reloading line, 2 switches to the saw sword (ammo line = its name, weapon button = the rifle),
## Esc pauses (mouse visible), resume (the free cursor does not aim), the next left click only re-captures; captured
## mouse look reads screen pixels (screen_relative). Back in the corridor: walk mode, weapon none,
## mouse visible. Layout at 640x360, 1280x720 and 1280x576, Thai and English, walk and shoot, desktop and touch: no
## overflow, buttons >= 44 px, nothing of the HUD overlaps the screen's own nodes, no Thai in English mode. Touch: every
## shooter button centre within 290 px of the bottom-right safe corner at 1280 and 1600 widths and clear of %UseButton;
## the stick strafes, a 100 px aim-pad drag turns the camera 0.6 rad, holding FireButton 1 s fires 8 ± 1 shots, a drag
## that starts on it also aims, MeleeButton punches, WeaponButton switches, ReloadButton reloads. The shoulder camera sits
## 0.55 m right of the egg and is never inside a solid in orbit sweeps by walls, corners and pillars; the egg fades when
## the arm is squeezed against a wall. Min: an idle player (no fire, no move) stops processing.
## Saves arena_hud_th.png, arena_hud_en.png, arena_touch.png, arena_touch_20x9.png, arena_sword.png, arena_hud_fire.png.
##   timeout 900 xvfb-run -a -s "-screen 0 1280x720x24" <godot> --path godot --rendering-driver opengl3 \
##       --resolution 1280x720 --audio-driver Dummy -s tests/render/test_arena_hud.gd

const SCENE := "res://scenes/main.tscn"
const ARENA_SCREEN := "res://ui/screens/arena_screen.tscn"
const DEFAULT_OUT_DIR := "res://tests/out"
const SETTINGS_FILE := "user://test_arena_hud.cfg"
const SIZES: Array[Vector2i] = [Vector2i(1280, 720), Vector2i(640, 360), Vector2i(1280, 576)]
const MIN_TARGET := 44.0
const HUD_NAMES: PackedStringArray = ["Ammo", "Hint", "Hurt", "Downed", "Touch"]
const TOUCH_NAMES: PackedStringArray = ["Stick", "AimPad", "FireButton", "MeleeButton", "ReloadButton", "WeaponButton"]
const SCREEN_NODES: PackedStringArray = ["LobbyButton", "SettingsButton", "UseButton", "Toast", "PausePanel"]
const SHOOT_AT := Vector3(0.0, 0.0, -12.5)
const REACH := 290.0

var _out_dir := DEFAULT_OUT_DIR
var _main: Node
var _started := false
var _done := false
var _passed := 0
var _failed := 0
var _thai_re := RegEx.create_from_string("[฀-๿]")
var _machine_cfg := ""


func _initialize() -> void:
	var env := OS.get_environment("TEST_OUT")
	if env != "" and env.is_absolute_path():
		_out_dir = env
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SETTINGS_FILE))
	_machine_cfg = _machine_settings()
	var app := _app()
	app.set("settings_file", SETTINGS_FILE)   # never write this machine's settings.cfg from a test
	app.call("set_lang", "th")
	app.call("set_gfx", "mid")
	app.call("set_fig", "egg")
	app.call("set_touch", "off")
	_main = (load(SCENE) as PackedScene).instantiate()
	_main.set("first_run_guess", false)
	root.add_child(_main)


func _process(_delta: float) -> bool:
	if not _started:
		_started = true
		_run()
	return _done


func _run() -> void:
	await _frames(4)
	var screen: Node = _app().call("push", load(ARENA_SCREEN))
	await _frames(6)
	var world: Node3D = screen.get("world")
	var hud: Control = screen.get("hud")
	var player: Node3D = world.get("player") if world != null else null
	_check(hud != null and _script_is(hud, "res://ui/widgets/arena_hud.gd") and hud.name == &"Hud", "the arena screen carries an ArenaHud named Hud")
	_check(player != null and _script_is(player, "res://scenes/arena/arena_player.gd"), "its world spawned the ArenaPlayer")
	if hud == null or player == null:
		_finish()
		return
	var missing := PackedStringArray()
	for n in HUD_NAMES:
		if hud.get_node_or_null(n) == null:
			missing.append(n)
	for n in TOUCH_NAMES:
		if hud.get_node_or_null("Touch/" + n) == null:
			missing.append("Touch/" + n)
	_check(missing.is_empty(), "the HUD carries every contract node", str(missing))
	var fig: Node3D = player.call("figure")
	_check(fig != null and _script_is(fig, "res://scenes/arena/egg_gunner.gd"), "the default player figure is the EggGunner")
	_check(_camera(player).current, "the player's camera is current")
	await _check_walk(screen, hud, player)
	await _check_shoot(screen, hud, player)
	await _check_layout(screen, hud, player)
	await _check_touch(screen, hud, player)
	await _check_camera(screen, hud, player)
	await _check_idle(screen, player)
	await _check_leave(screen, player)
	_check(_machine_settings() == _machine_cfg, "this machine's settings.cfg was not touched")
	_finish()


func _check_walk(_screen: Node, hud: Control, player: Node3D) -> void:
	_check(player.call("mode") == &"walk" and player.call("weapon") == &"none", "at the spawn: walk mode, no weapon")
	var hint := hud.get_node("Hint") as Label
	_check(hint.visible and hint.text == "เดินเข้าอารีน่าแล้วจะถือปืน", "the corridor hint shows", hint.text)
	_check(not (hud.get_node("Ammo") as Control).visible, "no ammo line in walk mode")
	_check(Input.mouse_mode != Input.MOUSE_MODE_CAPTURED, "the mouse is free in walk mode")
	_check(not bool(hud.call("drawn_rects")["EnemyBar"].has_area()), "no enemy bar in walk mode")


func _check_shoot(screen: Node, hud: Control, player: Node3D) -> void:
	var world: Node3D = screen.get("world")
	world.call("place_player", SHOOT_AT, PI, 0.0)
	await _frames(20)
	_check(player.call("mode") == &"shoot", "past the shoot line: shoot mode")
	await _physics(20)
	_check(player.call("weapon") == &"gun" and player.call("ammo") == Vector2i(30, 30), "the rifle is drawn with 30 / 30")
	_check(bool(player.call("aim_active")), "aim is active")
	var rects: Dictionary = hud.call("drawn_rects")
	var vc := root.get_visible_rect().get_center()
	var cr: Rect2 = rects["Crosshair"]
	_check(cr.get_center().distance_to(vc) <= 1.0, "the crosshair is centred on the viewport (±1 px)", str([cr.get_center(), vc]))
	_check(bool(player.call("mouse_captured")), "the mouse is captured on entering shoot mode")
	var hint := hud.get_node("Hint") as Label
	_check(hint.visible and hint.text.begins_with("คลิกซ้ายยิง"), "the keyboard shooter hint shows", hint.text)
	var ammo := hud.get_node("Ammo") as Label
	_check(ammo.visible and ammo.text == "30 / 30 · ปืนไรเฟิล", "the ammo line reads 30 / 30 · ปืนไรเฟิล", ammo.text)
	await _settle()
	_save("arena_hud_th.png")
	# ยิงค้าง 1 วิ ผ่าน action fire (คลิกซ้าย)
	var fx: Node = player.get("fx")
	_mouse_button(MOUSE_BUTTON_LEFT, true)
	await _physics(2)
	_check(int(fx.call("alive")) > 0, "a tracer and the muzzle flash are alive while firing")
	await _frames(1)
	_save("arena_hud_fire.png")
	await _physics(58)
	_mouse_button(MOUSE_BUTTON_LEFT, false)
	await _physics(2)
	var shots := 30 - (player.call("ammo") as Vector2i).x
	_check(absi(shots - 8) <= 1, "holding the left button 1 s fires 8 ± 1 shots", str(shots))
	_check(ammo.text == "%d / 30 · ปืนไรเฟิล" % (30 - shots), "the ammo line follows the shots", ammo.text)
	_check(not hint.visible or hint.modulate.a < 1.0 or bool(hud.call("hint_done")), "the first shot dismisses the shooter hint")
	await _press(KEY_R)
	_check(ammo.text == "กำลังบรรจุกระสุน…", "R shows the reloading line", ammo.text)
	await _physics(100)
	_check(player.call("ammo") == Vector2i(30, 30) and ammo.text.begins_with("30 / 30"), "after 1.6 s the magazine is full again", ammo.text)
	await _press(KEY_2)
	await _physics(25)
	_check(player.call("weapon") == &"sword", "2 switches to the saw sword")
	_check(ammo.text == "ดาบเลื่อย", "the ammo line shows the saw sword's name", ammo.text)
	var wb := hud.get_node("Touch/WeaponButton") as Button
	_check(wb.text == "ปืนไรเฟิล", "the weapon button offers the rifle", wb.text)
	var fbtn := hud.get_node("Touch/FireButton") as Button
	_check(fbtn.text == "ฟัน", "with the saw sword the fire button reads ฟัน (it swings)", fbtn.text)
	_mouse_button(MOUSE_BUTTON_LEFT, true)
	await _physics(4)
	_mouse_button(MOUSE_BUTTON_LEFT, false)
	await _frames(3)
	_save("arena_sword.png")
	await _physics(30)
	await _press(KEY_1)
	await _physics(25)
	_check(player.call("weapon") == &"gun", "1 switches back to the rifle")
	_check(fbtn.text == "ยิง", "with the rifle the fire button reads ยิง again", fbtn.text)
	# Esc: หยุด เมาส์หลุด; เล่นต่อแล้วคลิกแรกแค่จับเมาส์
	_check(bool(screen.call("handle_back")), "Esc is swallowed by the arena screen (pause)")
	await _frames(2)
	_check(bool(player.call("paused")) and not bool(player.call("mouse_captured")), "paused: the player is frozen and the mouse visible")
	_check(Input.mouse_mode != Input.MOUSE_MODE_CAPTURED, "…the OS cursor is free")
	screen.call("close_pause")
	await _frames(2)
	# review: moving the still-free cursor after resume (e.g. back from the Resume button) spun the aim
	var rig: Node3D = player.call("camera_rig")
	var yaw0 := float(rig.get("yaw"))
	_mouse_motion(Vector2(200, 0), Vector2(200, 0))
	await _frames(2)
	_check(absf(float(rig.get("yaw")) - yaw0) < 0.0001, "after resume the free cursor does not turn the aim before the click")
	var before := (player.call("ammo") as Vector2i).x
	_mouse_button(MOUSE_BUTTON_LEFT, true)
	await _physics(3)
	_mouse_button(MOUSE_BUTTON_LEFT, false)
	await _physics(2)
	_check((player.call("ammo") as Vector2i).x == before and bool(player.call("mouse_captured")), "after resume the next click only re-captures the mouse")
	# captured mouse look reads screen pixels (screen_relative), not canvas units: the same hand movement turns the
	# same at any window size (here the canvas would see 400 px, as a window half the canvas size scales it)
	yaw0 = float(rig.get("yaw"))
	_mouse_motion(Vector2(400, 0), Vector2(200, 0))
	await _frames(2)
	var turned := float(rig.get("yaw")) - yaw0
	_check(absf(turned + 200.0 * ArenaCamera.LOOK_SPEED) < 0.002, "captured mouse look: 200 screen px turn %.3f rad (-0.5), whatever the canvas scale" % turned)
	_mouse_motion(Vector2(-400, 0), Vector2(-200, 0))
	await _frames(2)
	# English
	_app().call("set_lang", "en")
	screen.call("refresh")
	await _frames(3)
	var thai := _thai_in(hud)
	_check(thai.is_empty(), "English: no Thai left in the HUD", str(thai))
	_check((hud.get_node("Ammo") as Label).text == "30 / 30 · Rifle", "English ammo line", (hud.get_node("Ammo") as Label).text)
	# review: "Saw Sword" shrank to 13 px on one line; it now splits into two lines at >= 16 px
	var wl: Dictionary = (hud.get_node("Touch") as Node).call("label_layout", "WeaponButton")
	_check((hud.get_node("Touch/WeaponButton") as Button).text == "Saw Sword" and (wl["lines"] as PackedStringArray).size() == 2 and int(wl["fs"]) >= 16,
		"English: the weapon button's Saw Sword label splits into two lines at %d px" % int(wl["fs"]), str(wl))
	await _settle()
	_save("arena_hud_en.png")
	_app().call("set_lang", "th")
	screen.call("refresh")
	await _frames(2)


func _check_layout(screen: Node, hud: Control, player: Node3D) -> void:
	var world: Node3D = screen.get("world")
	var size0 := root.size
	for touch in [false, true]:
		_app().call("set_touch", "on" if touch else "off")
		for lang in ["th", "en"]:
			_app().call("set_lang", lang)
			for sz in SIZES:
				await _resize(sz)
				for m in [&"walk", &"shoot"]:
					world.call("place_player", SHOOT_AT if m == &"shoot" else Vector3(0.0, 0.0, -3.0), PI, 0.0)
					await _frames(4)
					screen.call("refresh")
					await _frames(3)
					var probs := _layout_problems(hud)
					probs.append_array(_overlaps(screen, hud))
					_check(probs.is_empty(), "%s %s %dx%d %s: HUD layout clean, nothing over the screen's nodes" % [
						"touch" if touch else "desktop", lang, sz.x, sz.y, m], str(probs))
					if lang == "en":
						var thai := _thai_in(hud)
						_check(thai.is_empty(), "…and no Thai in English", str(thai))
	_app().call("set_lang", "th")
	_app().call("set_touch", "off")
	screen.call("refresh")
	await _resize(size0)
	_check(player != null, "layout sweep done")


func _check_touch(screen: Node, hud: Control, player: Node3D) -> void:
	var world: Node3D = screen.get("world")
	var rig: Node3D = player.call("camera_rig")
	var size0 := root.size
	_app().call("set_touch", "on")
	screen.call("refresh")
	world.call("place_player", SHOOT_AT, PI, 0.0)
	await _frames(6)
	_check(not bool(player.call("mouse_captured")), "touch mode never captures the mouse")
	for sz in [Vector2i(1280, 720), Vector2i(1280, 576)]:
		await _resize(sz)
		screen.call("refresh")
		await _frames(3)
		var corner := hud.get_global_rect().end
		var use := screen.get_node_or_null("%UseButton") as Control
		for n in ["FireButton", "MeleeButton", "ReloadButton", "WeaponButton"]:
			var b := hud.get_node("Touch/" + n) as Button
			var r := b.get_global_rect()
			_check(b.is_visible_in_tree() and r.size.x >= MIN_TARGET and r.size.y >= MIN_TARGET, "%d wide: %s shows, at least 44 px" % [root.get_visible_rect().size.x, n])
			_check(r.get_center().distance_to(corner) <= REACH, "…its centre within 290 px of the bottom-right safe corner (%.0f)" % r.get_center().distance_to(corner))
			if use != null:
				var ur := use.get_global_rect()
				_check(not r.intersects(ur), "…and clear of %UseButton (even when it shows)")
		if sz == Vector2i(1280, 720):
			await _settle()
			_save("arena_touch.png")
		else:
			await _settle()
			_save("arena_touch_20x9.png")
	await _resize(Vector2i(1280, 720))
	screen.call("refresh")
	await _frames(3)
	var tch := hud.get_node("Touch")
	# จอย: ดันขวา = เดินไปทางขวาของกล้อง (สไลด์ข้าง ตัวยังหันตามกล้อง)
	var stick := tch.get_node("Stick") as Control
	var sc := stick.get_global_rect().get_center()
	var p0: Vector3 = player.global_position
	var yaw0 := float(rig.get("yaw"))
	_touch(1, sc, true)
	_drag(1, sc + Vector2(60.0, 0.0), Vector2(60.0, 0.0))
	await _physics(30)
	_touch(1, sc + Vector2(60.0, 0.0), false)
	await _physics(30)
	var moved: Vector3 = player.global_position - p0
	var right: Vector3 = rig.call("right_flat")
	_check(moved.dot(right) > 0.5 and absf(float(rig.get("yaw")) - yaw0) < 0.001, "the stick strafes right (%.2f m) without turning the camera" % moved.dot(right))
	# AimPad: ลาก 100 px = หมุน 0.6 เรเดียน
	var pad := tch.get_node("AimPad") as Control
	var pc := pad.get_global_rect().get_center()
	yaw0 = float(rig.get("yaw"))
	_touch(2, pc, true)
	_drag(2, pc + Vector2(-50.0, 0.0), Vector2(-50.0, 0.0))
	_drag(2, pc + Vector2(-100.0, 0.0), Vector2(-50.0, 0.0))
	_touch(2, pc + Vector2(-100.0, 0.0), false)
	await _frames(2)
	_check(absf(wrapf(float(rig.get("yaw")) - yaw0, -PI, PI) - 0.6) < 0.01, "a 100 px aim-pad drag turns the camera 0.6 rad (%.3f)" % wrapf(float(rig.get("yaw")) - yaw0, -PI, PI))
	# ยิงค้าง 1 วิ ด้วย FireButton และลากจากปุ่มก็เล็ง
	var fire := tch.get_node("FireButton") as Control
	var fc := fire.get_global_rect().get_center()
	var a0 := (player.call("ammo") as Vector2i).x
	yaw0 = float(rig.get("yaw"))
	_touch(3, fc, true)
	await _physics(30)
	_drag(3, fc + Vector2(20.0, 0.0), Vector2(20.0, 0.0))
	await _physics(30)
	_touch(3, fc + Vector2(20.0, 0.0), false)
	await _physics(2)
	var fired := a0 - (player.call("ammo") as Vector2i).x
	_check(absi(fired - 8) <= 1, "holding FireButton 1 s fires 8 ± 1 shots", str(fired))
	_check(absf(wrapf(float(rig.get("yaw")) - yaw0, -PI, PI) + 0.12) < 0.01, "a drag that starts on FireButton also aims")
	await _physics(110)
	# หมัด
	var fig: Node3D = player.call("figure")
	var melee := tch.get_node("MeleeButton") as Control
	_touch(4, melee.get_global_rect().get_center(), true)
	await _physics(2)
	_check(str(fig.call("clip")) == "punch", "MeleeButton punches", str(fig.call("clip")))
	_touch(4, melee.get_global_rect().get_center(), false)
	await _physics(40)
	# บรรจุ
	var reload := tch.get_node("ReloadButton") as Control
	_touch(5, reload.get_global_rect().get_center(), true)
	_touch(5, reload.get_global_rect().get_center(), false)
	await _physics(2)
	var ammo_full := (player.call("ammo") as Vector2i).x == 30
	_check(ammo_full or bool((player.get("weapons") as Object).call("reloading")), "ReloadButton reloads (or the magazine is already full)")
	await _physics(100)
	# เปลี่ยนอาวุธ
	var wbtn := tch.get_node("WeaponButton") as Button
	_touch(6, wbtn.get_global_rect().get_center(), true)
	_touch(6, wbtn.get_global_rect().get_center(), false)
	await _physics(25)
	_check(player.call("weapon") == &"sword" and wbtn.text == "ปืนไรเฟิล", "WeaponButton switches to the saw sword and then offers the rifle", wbtn.text)
	_touch(6, wbtn.get_global_rect().get_center(), true)
	_touch(6, wbtn.get_global_rect().get_center(), false)
	await _physics(25)
	_app().call("set_touch", "off")
	screen.call("refresh")
	await _resize(size0)


func _check_camera(screen: Node, _hud: Control, player: Node3D) -> void:
	var world: Node3D = screen.get("world")
	var rig: Node3D = player.call("camera_rig")
	var cam := _camera(player)
	world.call("place_player", Vector3(0.0, 0.0, -14.0), PI, 0.0)
	await _physics(10)
	var right: Vector3 = rig.call("right_flat")
	var rel := cam.global_position - player.global_position
	# 0.9 m (was 0.55): the shoulder framing tuned at integration (ARENA_SPEC §17), so the egg no longer covers the crosshair
	_check(absf(rel.dot(right) - 0.9) < 0.05, "the shoulder camera sits 0.9 m right of the egg (%.3f)" % rel.dot(right))
	var lay: Script = load("res://scenes/arena/arena_layout.gd")
	var spots := [Vector3(0.0, 0.0, -11.8), Vector3(-9.4, 0.0, -11.1), Vector3(9.4, 0.0, -33.9), Vector3(-9.4, 0.0, -33.9),
		Vector3(4.5, 0.0, -17.4), Vector3(-3.2, 0.0, -25.6), Vector3(0.0, 0.0, -33.9)]
	var worst := ""
	for p in spots:
		world.call("place_player", p, PI, 0.0)
		await _physics(4)
		for i in 16:
			rig.call("look", TAU / 16.0, 0.0)
			player.call("_on_look")
			for k in 3:
				await physics_frame
				await process_frame
				if lay != null and bool(lay.call("inside_solid", cam.global_position, 0.1)) and worst == "":
					worst = "%s yaw %.2f cam %s" % [str(p), float(rig.get("yaw")), str(cam.global_position.snapped(Vector3.ONE * 0.01))]
	_check(worst == "", "orbit sweeps by walls, corners and pillars never put the camera inside a solid", worst)
	world.call("place_player", Vector3(0.0, 0.0, -34.0), 0.0, PI)
	await _physics(30)
	_check(float(player.call("figure_alpha")) < 1.0, "with the arm squeezed against the far wall the egg fades (%.2f)" % float(player.call("figure_alpha")))
	world.call("place_player", SHOOT_AT, PI, 0.0)
	await _physics(30)
	_check(float(player.call("figure_alpha")) >= 0.999, "with room again the egg is opaque")


func _check_idle(_screen: Node, player: Node3D) -> void:
	_app().call("set_gfx", "min")
	_screen.call("refresh")
	await _physics(80)
	await _frames(12)
	var busy := PackedStringArray()
	var stack: Array[Node] = [player]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n.is_processing() or n.is_physics_processing():
			busy.append(String(n.name))
		stack.append_array(n.get_children())
	_check(busy.is_empty(), "min, idle in shoot mode: nothing under the player processes", str(busy))
	_app().call("set_gfx", "mid")
	_screen.call("refresh")


func _check_leave(screen: Node, player: Node3D) -> void:
	var world: Node3D = screen.get("world")
	world.call("place_player", Vector3(0.0, 0.0, -6.0), PI, 0.0)
	await _physics(10)
	_check(player.call("mode") == &"walk" and player.call("weapon") == &"none", "back in the corridor: walk mode, weapon none")
	_check(not bool(player.call("mouse_captured")) and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED, "…and the mouse is visible")
	world.call("place_player", SHOOT_AT, PI, 0.0)
	await _physics(10)
	_app().call("pop")
	await _frames(4)
	_check(Input.mouse_mode != Input.MOUSE_MODE_CAPTURED, "leaving the arena screen frees the mouse")


# ---- helpers ----

func _overlaps(screen: Node, hud: Control) -> PackedStringArray:
	var out := PackedStringArray()
	var mine: Dictionary = {}
	var rects: Dictionary = hud.call("drawn_rects")
	for k in rects:
		if (rects[k] as Rect2).has_area() and k != "Crosshair":
			mine[k] = rects[k]
	for n in ["Ammo", "Hint"]:
		var c := hud.get_node(n) as Control
		if c.is_visible_in_tree():
			mine[n] = c.get_global_rect()
	var tch := hud.get_node("Touch") as Control
	if tch.is_visible_in_tree():
		for n in TOUCH_NAMES:
			var c := tch.get_node(n) as Control
			if c.is_visible_in_tree() and n != "AimPad":
				mine["Touch/" + n] = c.get_global_rect()
	for s in SCREEN_NODES:
		var node := screen.get_node_or_null("%" + s) as Control
		if node == null or not node.is_visible_in_tree():
			continue
		var r := node.get_global_rect()
		for k in mine:
			if (mine[k] as Rect2).intersection(r).get_area() > 1.0:
				out.append("%s overlaps %s" % [k, s])
	var keys := mine.keys()
	for i in keys.size():
		for j in range(i + 1, keys.size()):
			if (mine[keys[i]] as Rect2).intersection(mine[keys[j]]).get_area() > 1.0:
				out.append("%s overlaps %s" % [keys[i], keys[j]])
	return out


func _layout_problems(node: Node) -> PackedStringArray:
	var out := PackedStringArray()
	var vis := root.get_visible_rect()
	_walk(node, func(c: Control) -> void:
		var r := c.get_global_rect()
		if r.position.x < vis.position.x - 1.0 or r.position.y < vis.position.y - 1.0 or r.end.x > vis.end.x + 1.0 or r.end.y > vis.end.y + 1.0:
			out.append("%s outside the canvas %s" % [c.name, str(r)])
		if c is Button and (r.size.x < MIN_TARGET - 0.5 or r.size.y < MIN_TARGET - 0.5):
			out.append("%s smaller than 44x44 %s" % [c.name, str(r.size)])
		if c is Label and (c as Label).clip_text == false and (c as Label).autowrap_mode == TextServer.AUTOWRAP_OFF:
			var l := c as Label
			var w := l.get_theme_font(&"font").get_string_size(l.text, HORIZONTAL_ALIGNMENT_LEFT, -1, l.get_theme_font_size(&"font_size")).x
			if w > r.size.x + 1.0:
				out.append("%s text wider than its box (%.0f > %.0f)" % [c.name, w, r.size.x]))
	return out


func _walk(node: Node, f: Callable) -> void:
	if node is CanvasItem and not (node as CanvasItem).is_visible_in_tree():
		return
	if node is Control:
		f.call(node)
	for c in node.get_children():
		_walk(c, f)


func _thai_in(node: Node) -> PackedStringArray:
	var out := PackedStringArray()
	var stack: Array[Node] = [node]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is CanvasItem and not (n as CanvasItem).is_visible_in_tree():
			continue
		if (n is Label or n is Button) and _thai_re.search(str(n.get("text"))) != null:
			out.append(String(n.name) + ": " + str(n.get("text")))
		stack.append_array(n.get_children())
	return out


## Class names of the arena scripts are not used here: they read the I18n autoload, which a SceneTree script cannot
## see at compile time; the script path is checked instead.
func _script_is(n: Object, path: String) -> bool:
	var sc: Script = n.get_script()
	return sc != null and sc.resource_path == path


func _camera(player: Node3D) -> Camera3D:
	return player.call("camera")


func _mouse_motion(rel: Vector2, screen_rel: Vector2) -> void:
	var ev := InputEventMouseMotion.new()
	ev.relative = rel
	ev.screen_relative = screen_rel
	var at := _to_window(root.get_visible_rect().get_center())
	ev.position = at
	ev.global_position = at
	Input.parse_input_event(ev)
	Input.flush_buffered_events()


func _mouse_button(b: MouseButton, pressed: bool) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = b
	ev.pressed = pressed
	var at := _to_window(root.get_visible_rect().get_center())
	ev.position = at
	ev.global_position = at
	Input.parse_input_event(ev)
	Input.flush_buffered_events()


func _key(code: Key, pressed: bool) -> void:
	var ev := InputEventKey.new()
	ev.physical_keycode = code
	ev.pressed = pressed
	Input.parse_input_event(ev)
	Input.flush_buffered_events()


func _press(code: Key) -> void:
	_key(code, true)
	await _frames(1)
	_key(code, false)
	await _frames(2)


func _touch(index: int, canvas_pos: Vector2, pressed: bool) -> void:
	var t := InputEventScreenTouch.new()
	t.index = index
	t.position = _to_window(canvas_pos)
	t.pressed = pressed
	Input.parse_input_event(t)
	Input.flush_buffered_events()


func _drag(index: int, canvas_pos: Vector2, canvas_rel: Vector2) -> void:
	var d := InputEventScreenDrag.new()
	d.index = index
	d.position = _to_window(canvas_pos)
	d.relative = canvas_rel * (_to_window(Vector2.ONE) - _to_window(Vector2.ZERO))
	Input.parse_input_event(d)
	Input.flush_buffered_events()


func _to_window(p: Vector2) -> Vector2:
	return root.get_final_transform() * p


func _settle() -> void:
	await _physics(4)
	await _frames(2)


func _machine_settings() -> String:
	var p := "user://settings.cfg"
	return "%d:%s" % [FileAccess.get_modified_time(p), FileAccess.get_file_as_string(p)] if FileAccess.file_exists(p) else "none"


func _resize(sz: Vector2i) -> void:
	root.size = sz
	await _frames(6)


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _physics(n: int) -> void:
	for i in n:
		await physics_frame


func _app() -> Node:
	return root.get_node(^"App")


func _save(name: String) -> void:
	var img := root.get_viewport().get_texture().get_image()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_out_dir))
	var path := _out_dir + "/" + name
	var err := img.save_png(path)
	_check(err == OK, "saved " + ProjectSettings.globalize_path(path) + " " + str(img.get_size()))


func _finish() -> void:
	for k in [KEY_W, KEY_A, KEY_S, KEY_D, KEY_SHIFT]:
		_key(k, false)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var app := _app()
	app.call("set_lang", "th")
	app.call("set_touch", "auto")
	app.set("settings_file", str(app.get("SETTINGS_PATH")))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SETTINGS_FILE))
	print("%s  %d passed, %d failed" % ["PASS " if _failed == 0 else "FAIL ", _passed, _failed])
	_done = true
	quit(0 if _failed == 0 else 1)


func _check(cond: bool, msg: String, detail: String = "") -> void:
	if cond:
		_passed += 1
		print("ok    " + msg)
	else:
		_failed += 1
		print("FAIL  " + msg + ("" if detail == "" else " " + detail.left(1500)))
