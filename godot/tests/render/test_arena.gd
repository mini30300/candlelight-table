extends SceneTree
## The weapons arena (ARENA_SPEC §4, §7, §10, §11, §13.4) inside scenes/main.tscn, entered from the warship deck's
## arena door (E at its ring). Entry: the arena screen is pushed (depth 3) with its contract nodes, the deck and the
## battle table are hidden and stopped, the arena camera is current; the build time is printed (asserted <= 2000 ms).
## Per level (hi/mid/lo/min): counts() and the §11.1 table (sides, two flames, flicker and beacon spin only on hi/mid,
## the effects additive only on hi/mid, sign outlines only on hi/mid), no shader using TIME under the arena on lo/min
## (shader code is scanned), and the three budget views of §11.2 printed and asserted: the overview (desktop, shoot mode
## at (0, 0, -12.5)), the corridor (20:9, touch on, walk mode at SPAWN) and the phone worst view (20:9, touch on, hint,
## firing, four damage numbers, the red hurt edge, the beast winding up, a toast and the use button, at the switch
## looking across the room). The switch sign's lowest line stays above the beacon in Thai and English, keyboard and touch. No holes into the void: with a magenta background no magenta pixel shows from 3 corridor and 6 arena spots
## x 4 yaws x 2 pitches in both camera framings on mid, the walk framing on min (640x360). The camera never enters a
## solid (ArenaLayout.inside_solid, 0.1 m) on corridor walks with orbits, through the arch, beside each pillar and in the
## four corners in shoot mode. The board and the signs in Thai and in English (no Thai left in English); the pause
## panel, the toast and the use button pass the layout rules at 640x360, 1280x720 and 1280x576. The fade: hi uses a
## Tween and ends clear, min creates none. min: after 10 idle frames with the bot off nothing under the arena screen
## processes, in the corridor and in the arena. Saves arena_<level>.png, arena_corridor.png, arena_board_th.png,
## arena_board_en.png, arena_pause.png and arena_phone_worst_<level>.png. Run:
##   timeout 900 nice -n 10 xvfb-run -a -s "-screen 0 1280x720x24" <godot> --path godot --rendering-driver opengl3 \
##       --resolution 1280x720 --audio-driver Dummy -s tests/render/test_arena.gd
## TEST_OUT (an absolute folder) in the environment replaces tests/out. Exit code 1 on any failure.

const SCENE := "res://scenes/main.tscn"
const ARENA_SCREEN := "res://ui/screens/arena_screen.tscn"
const DEFAULT_OUT_DIR := "res://tests/out"
const SETTINGS_FILE := "user://test_arena.cfg"
const SIZES: Array[Vector2i] = [Vector2i(1280, 720), Vector2i(640, 360), Vector2i(1280, 576)]
const PHONE := Vector2i(1600, 720)
const SETTLE := 6
const MIN_TARGET := 44.0
const LEVELS: PackedStringArray = ["hi", "mid", "lo", "min"]
const CONTRACT: PackedStringArray = ["LobbyButton", "SettingsButton", "UseButton", "Toast", "PausePanel", "ResumeButton",
	"PauseLobbyButton", "PauseSettingsButton", "Fade"]
## [draw calls, primitives] per level (ARENA_SPEC §11.2)
const OVERVIEW := {"hi": [50, 80000], "mid": [45, 60000], "lo": [35, 40000], "min": [30, 30000]}
const WORST := {"hi": [70, 80000], "mid": [60, 60000], "lo": [45, 40000], "min": [40, 30000]}
const CORRIDOR := {"hi": [50, 80000], "mid": [45, 60000], "lo": [35, 40000], "min": [30, 30000]}
## §11.1: sides, flicker, beacon spin (while on), fx additive, outlines
const TABLE := {"hi": [14, true, true, true, true], "mid": [12, true, true, true, true], "lo": [10, false, false, false, false],
	"min": [8, false, false, false, false]}
const CORRIDOR_SPOTS: Array[Vector3] = [Vector3(0.0, 0.0, -2.2), Vector3(0.0, 0.0, -6.0), Vector3(0.0, 0.0, -9.6)]
const ARENA_SPOTS: Array[Vector3] = [Vector3(0.0, 0.0, -12.5), Vector3(-8.5, 0.0, -12.0), Vector3(8.5, 0.0, -33.0),
	Vector3(-8.5, 0.0, -33.0), Vector3(0.0, 0.0, -21.5), Vector3(6.0, 0.0, -24.5)]
const VOID_SIZE := Vector2i(640, 360)
const MAGENTA := Color(1.0, 0.0, 1.0)

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
	var scene: PackedScene = load(SCENE)
	if scene == null:
		print("FAIL  cannot load " + SCENE)
		quit(1)
		return
	_main = scene.instantiate()
	_main.set("first_run_guess", false)
	root.add_child(_main)
	print("adapter: " + RenderingServer.get_video_adapter_name() + " (" + RenderingServer.get_video_adapter_api_version() + ")")


func _process(_delta: float) -> bool:
	if not _started:
		_started = true
		_run()
	return _done


func _run() -> void:
	await _frames(4)
	var arena := await _enter()
	if arena == null:
		_finish()
		return
	var world: Node3D = arena.get("world")
	for step in [_check_levels, _check_corridor, _check_phone_worst, _check_void, _check_camera, _check_texts, _check_idle]:
		if not is_instance_valid(arena) or _app().call("current") != arena:
			_check(false, "the arena screen is still open before %s" % step.get_method())
			_finish()
			return
		await step.call(arena, world)
	await _check_fade(arena)
	_check(_machine_settings() == _machine_cfg, "this machine's settings.cfg was not touched")
	_finish()


## Main menu -> the deck -> E at the arena door -> the arena screen (depth 3).
func _enter() -> Node:
	var menu: Node = _app().call("current")
	if menu == null or menu.get_node_or_null("%PlayButton") == null:
		_check(false, "main.tscn opens the main menu")
		return null
	menu.get_node("%PlayButton").pressed.emit()
	await _frames(4)
	var hall: Node = _app().call("current")
	_check(hall != null and hall.has_method("enter_arena"), "เล่นกับบอท opens the deck")
	if hall == null:
		return null
	var hw: Node3D = hall.get("world")
	var f: Vector2 = HallLayout.STATIONS["arena"]["front"]
	hw.call("place_avatar", Vector3(f.x, 0.0, f.y), PI)
	await _physics(4)
	_check(str(hall.call("station")) == "arena", "the avatar stands at the arena door")
	var longest := 0
	var last := Time.get_ticks_msec()
	_key(KEY_E, true)
	await _frames(1)
	_key(KEY_E, false)
	for i in 120:
		await process_frame
		var now := Time.get_ticks_msec()
		longest = maxi(longest, now - last)
		last = now
		if int(_app().call("depth")) == 3:
			break
	await _frames(2)
	var arena: Node = _app().call("current")
	_check(int(_app().call("depth")) == 3 and arena != null and arena.scene_file_path == ARENA_SCREEN, "E at the arena door pushes the arena screen (depth 3)")
	print("arena build: the longest frame while entering took %d ms (target <= 150 ms of CPU on the test machine)" % longest)
	_check(longest <= 2000, "the arena builds in at most 2000 ms (%d ms)" % longest)
	if arena == null or arena.scene_file_path != ARENA_SCREEN:
		return null
	var missing := PackedStringArray()
	for n in CONTRACT:
		if arena.get_node_or_null("%" + n) == null:
			missing.append(n)
	_check(missing.is_empty(), "the arena screen carries every contract node", str(missing))
	var world: Node3D = arena.get("world")
	_check(world != null and world.name == &"ArenaWorld" and world.is_in_group("gfx_level"), "its world is the ArenaWorld child, in the gfx_level group")
	_check(not (hall as CanvasItem).visible and not hw.visible and hw.process_mode == Node.PROCESS_MODE_DISABLED, "the deck is hidden and stopped")
	var table := get_first_node_in_group("table_view") as Node3D
	_check(table == null or (not table.visible and table.process_mode == Node.PROCESS_MODE_DISABLED), "the battle table stays hidden and disabled")
	var cam: Camera3D = world.call("camera")
	_check(cam != null and cam.current, "the arena camera is current")
	_check(str(world.call("mode")) == "walk" and str(world.call("station")) == "", "the arena starts in walk mode at the spawn, in no station")
	var st: Dictionary = world.call("stats")
	_check(not bool(st["bot_on"]) and int(st["hits"]) == 0 and int(st["damage"]) == 0, "fresh range: bot off, counters 0", str(st))
	await _frames(20)
	return arena


# ---- views ----

## Puts the player (or, without one, the fallback camera) at foot, camera yaw / pitch; shoot = the shoulder framing.
func _view(world: Node3D, foot: Vector3, yaw: float, pitch: float, shoot: bool) -> void:
	var player: Node3D = world.get("player")
	if player != null and player.has_method("place"):
		world.call("place_player", foot, yaw + PI, yaw)
		if player.has_method("set_mode"):
			player.call("set_mode", &"shoot" if shoot else &"walk")
		var rig: Node3D = player.call("camera_rig")
		if rig != null and rig.has_method("set_view"):
			rig.call("set_view", yaw, pitch, ArenaCamera.SHOULDER_ARM if shoot else 4.5)
		await _physics(6)
		await _frames(3)
		return
	var cam: Camera3D = world.get_node("FallbackCamera")
	cam.make_current()
	var b := Basis.from_euler(Vector3(pitch, yaw, 0.0))
	var right := Vector3(cos(yaw), 0.0, -sin(yaw))
	var pivot := foot + (ArenaCamera.SHOULDER_HEAD + right * ArenaCamera.SHOULDER_RIGHT if shoot else Vector3(0.0, 1.3, 0.0))
	var arm := ArenaCamera.SHOULDER_ARM if shoot else 4.5
	var t := 0.0
	while t < arm and not ArenaLayout.inside_solid(pivot + b.z * (t + 0.05), 0.3):
		t += 0.05
	cam.global_transform = Transform3D(b, pivot + b.z * t)
	await _frames(3)


func _measure() -> Vector2i:
	var idle := OS.low_processor_usage_mode
	OS.low_processor_usage_mode = false   # draw every frame while measuring
	await _frames(3)
	var draws := 0
	var prims := 0
	for i in 4:
		await process_frame
		draws = maxi(draws, RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME))
		prims = maxi(prims, RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME))
	OS.low_processor_usage_mode = idle
	return Vector2i(draws, prims)


func _check_levels(arena: Node, world: Node3D) -> void:
	for level in LEVELS:
		_app().call("set_gfx", level)
		arena.call("refresh")
		await _view(world, ArenaLayout.RESPAWN, 0.0, -0.1, true)
		var m := await _measure()
		var c: Dictionary = world.call("counts")
		print("arena overview %-4s draw calls %4d  primitives %7d  %s" % [level, m.x, m.y, str(c)])
		var t: Array = OVERVIEW[level]
		_check(m.x <= int(t[0]) and m.y <= int(t[1]), "%s: the arena overview, %d draw calls, %d primitives within %d / %d" % [level, m.x, m.y, int(t[0]), int(t[1])])
		var row: Array = TABLE[level]
		_check(int(c["sides"]) == int(row[0]) and int(c["static_meshes"]) <= 2 and int(c["flames"]) == 2 and bool(c["flicker"]) == bool(row[1]),
			"%s: %d sides, at most 2 static meshes, 2 flames, flicker %s" % [level, int(c["sides"]), str(row[1])], str(c))
		_check(bool(c["fx_additive"]) == bool(row[3]), "%s: effects additive %s" % [level, str(row[3])], str(c))
		_check(int(c["signs"]) == 6 and int(c["pillars"]) == 4 and int(c["blockers"]) >= 19, "%s: 6 signs, 4 pillars, every blocker built" % level, str(c))
		# the beacon spins (shader) only on hi/mid and only while the bot is on
		world.call("toggle_bot", &"use")
		await _frames(2)
		var on: Dictionary = world.call("counts")
		_check(bool(on["beacon_spin"]) == bool(row[2]) and bool(world.call("beacon_lit")), "%s: with the bot on the beacon is lit, spinning %s" % [level, str(row[2])])
		await _physics(int(Engine.physics_ticks_per_second * 1.05))
		world.call("toggle_bot", &"use")
		await _frames(2)
		_check(not bool((world.call("counts") as Dictionary)["beacon_spin"]) and not bool(world.call("beacon_lit")), "%s: with the bot off the beacon is dark and still" % level)
		await _physics(int(Engine.physics_ticks_per_second * 1.05))
		var wrong := PackedStringArray()
		for l: Label3D in world.call("labels"):
			if (l.outline_size > 0) != bool(row[4]):
				wrong.append("%s %d" % [l.name, l.outline_size])
		_check(wrong.is_empty(), "%s: sign outlines %s" % [level, "on" if bool(row[4]) else "off"], ", ".join(wrong))
		if level == "lo" or level == "min":
			var timed := _time_shaders(arena)
			_check(timed.is_empty(), "%s: no shader under the arena uses TIME" % level, ", ".join(timed))
		_check(OS.low_processor_usage_mode == (level == "lo" or level == "min"), "%s: low-processor mode follows the table's level" % level)
		_save("arena_%s.png" % level)
	_app().call("set_gfx", "mid")
	arena.call("refresh")


func _check_corridor(arena: Node, world: Node3D) -> void:
	var size0 := root.size
	_app().call("set_touch", "on")
	await _resize(PHONE)
	for level in LEVELS:
		_app().call("set_gfx", level)
		arena.call("refresh")
		await _view(world, ArenaLayout.SPAWN, 0.0, -0.2, false)
		var m := await _measure()
		print("arena corridor %-4s draw calls %4d  primitives %7d" % [level, m.x, m.y])
		var t: Array = CORRIDOR[level]
		_check(m.x <= int(t[0]) and m.y <= int(t[1]), "%s: the corridor view (20:9, touch), %d draw calls, %d primitives within %d / %d" % [level, m.x, m.y, int(t[0]), int(t[1])])
		if level == "mid":
			_save("arena_corridor.png")
	_app().call("set_gfx", "mid")
	_app().call("set_touch", "off")
	arena.call("refresh")
	await _resize(size0)


func _check_phone_worst(arena: Node, world: Node3D) -> void:
	var size0 := root.size
	_app().call("set_touch", "on")
	await _resize(PHONE)
	var player: Node3D = world.get("player")
	var enemy: Node3D = world.get("enemy")
	var front: Vector2 = ArenaLayout.STATIONS["switch"]["front"]
	var foot := Vector3(front.x, 0.0, front.y)
	var yaw := atan2(foot.x - ArenaLayout.BEAST_SPAWN.x, foot.z - ArenaLayout.BEAST_SPAWN.z)   # looking towards the pad and the board
	for level in LEVELS:
		_app().call("set_gfx", level)
		arena.call("refresh")
		await _view(world, foot, yaw, -0.08, true)
		var hud: Control = arena.get("hud")
		var hint: CanvasItem = hud.get_node_or_null("Hint") if hud != null else null
		if hint != null:
			hint.visible = true
			hint.modulate = Color.WHITE
		arena.call("show_toast", "รีเซ็ตแล้ว")
		# the beast close in front, the bot on: it winds up
		if enemy != null and enemy.has_method("reset_to"):
			var fwd := Vector3(-sin(yaw), 0.0, -cos(yaw))
			enemy.call("reset_to", foot + fwd * 2.0, yaw)
			if not bool(world.get("state").get("bot_on")):
				world.call("toggle_bot", &"use")
			for i in 240:
				await physics_frame
				if enemy.has_method("state") and str(enemy.call("state")) == "windup":
					break
		if player != null:
			# four numbers alive: mixed kinds (rifle hits on one target within 0.3 s merge into one number since integration)
			var kinds := [&"gun", &"punch", &"sword", &"punch"]
			for i in 4:
				player.emit_signal("hit_landed", {"point": foot + Vector3(-1.5 - i * 0.4, 1.5, 0.0), "amount": 12 + i * 10, "target": &"beast", "kind": kinds[i], "killed": false})
			# the red hurt edge (the player just clawed); held on for the measured frames
			player.emit_signal("hurt", {"amount": 18, "from": foot + Vector3(0.0, 0.0, -2.0)})
			if hud != null:
				hud.set("_hurt", 5.0)
			if player.has_method("press"):
				player.call("press", &"fire", true)
		if hud != null:
			_check(int(hud.call("numbers_alive")) == 4 and (hud.get_node("Hurt") as CanvasItem).visible,
				"%s: the phone worst view has four damage numbers and the hurt edge (%d)" % [level, int(hud.call("numbers_alive"))])
		var m := await _measure()
		# where the draw calls go: the 3D world alone, and the world with the screen's own nodes but no HUD
		var safe := arena.get_node("Safe") as CanvasItem
		if hud != null:
			hud.visible = false
		var no_hud := await _measure()
		safe.visible = false
		var world_only := await _measure()
		safe.visible = true
		if hud != null:
			hud.visible = true
		print("arena phone worst %-4s breakdown: 3D world %d draws; + screen buttons, toast, use %d; + HUD and touch %d" % [level, world_only.x, no_hud.x, m.x])
		if player != null and player.has_method("press"):
			player.call("press", &"fire", false)
		var use: Button = arena.get_node("%UseButton")
		print("arena phone worst %-4s draw calls %4d  primitives %7d  (beast %s, use button %s)" % [level, m.x, m.y,
			str(enemy.call("state")) if enemy != null and enemy.has_method("state") else "-", str(use.visible)])
		var t: Array = WORST[level]
		_check(m.x <= int(t[0]) and m.y <= int(t[1]), "%s: the phone worst view, %d draw calls, %d primitives within %d / %d" % [level, m.x, m.y, int(t[0]), int(t[1])])
		await _frames(2)   # the last measured frame had the screen hidden: draw the full view again before saving it
		_save("arena_phone_worst_%s.png" % level)
		if bool(world.get("state").get("bot_on")):
			await _physics(int(Engine.physics_ticks_per_second * 1.05))
			world.call("toggle_bot", &"use")
		world.call("reset_range")
		await _physics(int(Engine.physics_ticks_per_second * 1.05))
	_app().call("set_gfx", "mid")
	_app().call("set_touch", "off")
	arena.call("refresh")
	await _resize(size0)


## The switch sign sits on the beacon: its lowest line stays above the lamp's top (review: the wrapped English sign and
## the Thai touch sign covered the bot ON/OFF lamp), keyboard and touch texts.
func _check_switch_sign(arena: Node, world: Node3D, lang: String) -> void:
	var sign: Label3D = world.get_node("Signs/Sign_switch")
	var beacon: Vector3 = ArenaLayout.STATIONS["switch"]["beacon"]
	for touch in ["off", "on"]:
		_app().call("set_touch", touch)
		arena.call("refresh")
		await _frames(3)
		var low := sign.global_position.y + sign.get_aabb().position.y * sign.global_basis.get_scale().y
		_check(low >= beacon.y + 0.16, "%s %s: the switch sign (%s) stays above the beacon (lowest %.2f m >= %.2f)" % [lang,
			"touch" if touch == "on" else "keys", sign.text, low, beacon.y + 0.16])
	_app().call("set_touch", "off")
	arena.call("refresh")


# ---- no holes into the void ----

func _check_void(arena: Node, world: Node3D) -> void:
	var cam: Camera3D = world.call("camera")
	var env: Environment = cam.environment
	var bg := env.background_color
	await _resize(VOID_SIZE)
	var hud: CanvasItem = arena.get("hud")
	var safe := arena.get_node("Safe") as CanvasItem
	safe.visible = false
	env.background_color = MAGENTA
	for level in ["mid", "min"]:
		_app().call("set_gfx", level)
		arena.call("refresh")
		safe.visible = false
		var bad := PackedStringArray()
		var n := 0
		var spots: Array[Vector3] = []
		spots.append_array(CORRIDOR_SPOTS)
		spots.append_array(ARENA_SPOTS)
		var idle := OS.low_processor_usage_mode
		OS.low_processor_usage_mode = false
		for spot in spots:
			for shoot in [false, true]:
				if level == "min" and shoot:
					continue
				for yaw in [0.0, PI * 0.5, PI, PI * 1.5]:
					for pitch in [-0.1, -0.5]:
						await _view(world, spot, yaw, pitch, shoot)
						n += 1
						var px := _magenta_pixels(root.get_viewport().get_texture().get_image())
						if px > 0:
							bad.append("%s %s yaw %d pitch %.2f: %d px" % [str(spot), "shoot" if shoot else "walk", int(round(rad_to_deg(yaw))), pitch, px])
							if bad.size() == 1:
								_save("arena_void_%s.png" % level)
		OS.low_processor_usage_mode = idle
		_check(bad.is_empty(), "%s: no hole into the void in %d views (magenta background, %dx%d)" % [level, n, VOID_SIZE.x, VOID_SIZE.y], "\n".join(bad))
	env.background_color = bg
	_check(env.background_color == ArenaWorld.BG, "the arena's background colour is restored")
	safe.visible = true
	if hud != null:
		hud.visible = true
	_app().call("set_gfx", "mid")
	arena.call("refresh")
	await _resize(SIZES[0])


static func _magenta_pixels(img: Image) -> int:
	var n := 0
	for y in img.get_height():
		for x in img.get_width():
			var c := img.get_pixel(x, y)
			if c.r > 0.75 and c.b > 0.75 and c.g < 0.3:
				n += 1
	return n


# ---- the real camera never inside a solid ----

func _check_camera(_arena: Node, world: Node3D) -> void:
	var player: Node3D = world.get("player")
	if player == null or not player.has_method("set_stick"):
		_check(false, "the arena has its player (ArenaPlayer) to drive the camera checks")
		return
	var rig: Node3D = player.call("camera_rig")
	var cam: Camera3D = player.call("camera")
	# [start, stick, ticks, yaw, orbit per tick, name]
	var walks := [
		[ArenaLayout.SPAWN, Vector2(0.0, 1.0), 240, 0.0, 0.02, "down the corridor through the arch with orbits"],
		[Vector3(0.0, 0.0, -12.0), Vector2(0.0, -0.8), 100, 0.0, 0.02, "back up through the arch with orbits"],
		[Vector3(-6.2, 0.0, -16.0), Vector2(0.0, 1.0), 120, 0.0, 0.0, "beside the pillar at (-4.5, -18.5)"],
		[Vector3(6.2, 0.0, -16.0), Vector2(0.0, 1.0), 120, 0.0, 0.0, "beside the pillar at (4.5, -18.5)"],
		[Vector3(-1.4, 0.0, -21.0), Vector2(0.0, 1.0), 120, 0.0, 0.0, "beside the pillar at (-3.2, -24.5)"],
		[Vector3(1.4, 0.0, -21.0), Vector2(0.0, 1.0), 120, 0.0, 0.0, "beside the pillar at (3.2, -24.5)"],
		[Vector3(-8.0, 0.0, -13.0), Vector2(-0.7, 0.7), 120, PI * 0.25, 0.03, "into the near-left corner"],
		[Vector3(8.0, 0.0, -13.0), Vector2(0.7, 0.7), 120, -PI * 0.25, 0.03, "into the near-right corner"],
		[Vector3(-8.0, 0.0, -32.0), Vector2(-0.7, 0.7), 120, PI * 0.75, 0.03, "into the far-left corner"],
		[Vector3(8.0, 0.0, -32.0), Vector2(0.7, 0.7), 120, -PI * 0.75, 0.03, "into the far-right corner"]]
	for w in walks:
		world.call("place_player", w[0], float(w[3]) + PI, float(w[3]))
		await _physics(8)
		player.call("set_stick", w[1])
		var inside := ""
		for i in int(w[2]):
			await physics_frame
			if not is_instance_valid(player) or int(_app().call("depth")) != 3:
				inside = "the arena closed during the walk"
				break
			# the orbit swings the view +-0.4 rad around the start (movement is camera-relative, so the walk keeps its way)
			var swing := float(w[4]) * cos(i * 0.05)
			if swing != 0.0 and rig.has_method("orbit") and str(player.call("mode")) == "walk":
				rig.call("orbit", swing, 0.0)
			elif swing != 0.0 and rig.has_method("look"):
				rig.call("look", swing, 0.0)
			await process_frame
			var cp := cam.global_position
			if inside == "" and ArenaLayout.inside_solid(cp, 0.1):
				inside = "camera %s with the player at %s (%s)" % [str(cp.snapped(Vector3.ONE * 0.01)), str(player.global_position.snapped(Vector3.ONE * 0.01)), str(player.call("mode"))]
		if not is_instance_valid(player):
			_check(false, "walking %s the camera never enters a solid" % w[5], inside)
			return
		player.call("set_stick", Vector2.ZERO)
		await _physics(30)
		_check(inside == "", "walking %s the camera never enters a solid" % w[5], inside)
	world.call("place_player", ArenaLayout.SPAWN, ArenaLayout.SPAWN_FACE, ArenaLayout.SPAWN_YAW)
	await _physics(10)


# ---- text ----

func _check_texts(arena: Node, world: Node3D) -> void:
	var i18n := root.get_node(^"I18n")
	for lang in ["th", "en"]:
		_app().call("set_lang", lang)
		arena.call("refresh")
		await _frames(2)
		var title := str(world.call("sign_text", "board_title"))
		var body := str(world.call("sign_text", "board_body"))
		if lang == "en":
			var thai := _thai_in(arena, ["LangButton"])
			_check(thai.is_empty(), "en: no Thai on screen or on the 3D signs", ", ".join(thai))
			_check(body.begins_with("Bot: OFF") and body.contains("HP 300/300") and body.contains("0 hits"), "en: the board body reads %s" % body.replace("\n", " | "))
			_check(str(world.call("sign_text", "door_back")) == "Back to the Warship Deck", "en: the deck door's sign")
		else:
			_check(body.begins_with("บอท: ปิด") and body.contains("พลังชีวิต 300/300"), "th: the board body reads %s" % body.replace("\n", " | "))
			_check(_thai_re.search(title) != null, "th: the board title is Thai (%s)" % title)
			_check(str(world.call("sign_text", "switch")) == str(i18n.call("t", "สวิตช์บอท · ยิงหรือกด E")), "th: the switch sign names E (keyboard)")
		await _check_switch_sign(arena, world, lang)
		await _view(world, Vector3(0.0, 0.0, -22.5), 0.0, 0.05, true)
		_save("arena_board_%s.png" % lang)
		# the pause panel, a toast and the use button at three sizes
		world.call("place_player", Vector3(-5.3, 0.0, -13.5), -PI * 0.5, PI * 0.5)
		await _physics(4)
		_check(str(world.call("station")) == "reset" and (arena.get_node("%UseButton") as Button).visible, "%s: at the reset pedestal the use button shows" % lang)
		arena.call("show_toast", "บอทเปิด — {name}ไล่ตามคุณแล้ว", {"name": ""})
		arena.call("open_pause")
		for sz in SIZES:
			await _resize(sz)
			var lay := _layout_problems(arena.get_node("Safe/Layer/PausePanel"))
			lay.append_array(_layout_problems(arena.get_node("%Toast")))
			lay.append_array(_layout_problems(arena.get_node("%UseButton")))
			lay.append_array(_layout_problems(arena.get_node("%LobbyButton")))
			lay.append_array(_layout_problems(arena.get_node("%SettingsButton")))
			_check(lay.is_empty(), "%s %dx%d: the pause panel, toast, use, lobby and settings buttons fit" % [lang, sz.x, sz.y], ", ".join(lay))
			var toast_r := (arena.get_node("%Toast") as Control).get_global_rect()
			var use_r := (arena.get_node("%UseButton") as Control).get_global_rect()
			var pause_r := (arena.get_node("%PausePanel") as Control).get_global_rect()
			_check(not toast_r.intersects((arena.get_node("%LobbyButton") as Control).get_global_rect())
				and not use_r.intersects(pause_r), "%s %dx%d: the toast clears the lobby button, the use button clears the pause panel" % [lang, sz.x, sz.y])
			if lang == "th" and sz == SIZES[0]:
				_save("arena_pause.png")
		await _resize(SIZES[0])
		_check(bool(arena.call("handle_back")) and not bool(arena.call("paused")), "%s: back closes the pause panel (resume)" % lang)
		_check(bool(arena.call("handle_back")) and bool(arena.call("paused")) and _app().call("current") == arena, "%s: back again opens it and stays in the arena" % lang)
		arena.call("close_pause")
	_app().call("set_lang", "th")
	arena.call("refresh")
	world.call("place_player", ArenaLayout.SPAWN, ArenaLayout.SPAWN_FACE, ArenaLayout.SPAWN_YAW)
	await _physics(4)


# ---- idle and fade ----

func _check_idle(arena: Node, world: Node3D) -> void:
	_app().call("set_gfx", "min")
	arena.call("refresh")
	for spot in [[ArenaLayout.SPAWN, "the corridor (walk mode)"], [ArenaLayout.RESPAWN, "the arena (shoot mode)"]]:
		world.call("place_player", spot[0], PI, 0.0)
		await _physics(30)
		await _frames(40)
		await _frames(10)
		var probs := _idle_problems(arena)
		_check(probs.is_empty(), "min: after 10 idle frames with the bot off nothing under the arena processes in %s" % spot[1], ", ".join(probs))
		var enemy: Node3D = world.get("enemy")
		var playing := PackedStringArray()
		for n in (enemy.find_children("*", "AnimationPlayer", true, false) if enemy != null else []):
			if (n as AnimationPlayer).is_playing():
				playing.append(String(n.name))
		_check(playing.is_empty(), "min: the idle beast holds a still pose (no AnimationPlayer playing)", ", ".join(playing))
	_app().call("set_gfx", "mid")
	arena.call("refresh")


func _check_fade(arena: Node) -> void:
	# leave through the lobby button on mid (a Tween), then enter again from the deck on hi and on min
	(arena.get_node("%LobbyButton") as Button).pressed.emit()
	await _frames_until(func() -> bool: return int(_app().call("depth")) == 2, 120)
	var hall: Node = _app().call("current")
	_check(int(_app().call("depth")) == 2 and hall != null and hall.has_method("enter_arena"), "‹ lobby returns to the deck")
	await _frames_until(func() -> bool: return not bool(hall.call("fading")), 120)
	for level in ["hi", "min"]:
		_app().call("set_gfx", level)
		hall.call("refresh")
		hall.call("enter_arena")
		await _frames_until(func() -> bool: return int(_app().call("depth")) == 3, 120)
		var a: Node = _app().call("current")
		var fade := a.get_node("%Fade") as ColorRect
		var tween_seen := false
		for i in 60:
			var tw: Variant = a.get("_fade_tween")
			if tw != null and (tw as Tween).is_valid():
				tween_seen = true
			if not bool(a.call("fading")):
				break
			await process_frame
		await _frames(2)
		_check(tween_seen == (level == "hi"), "%s: the arena's fade-in %s" % [level, "is a Tween" if level == "hi" else "creates no Tween"])
		_check(not fade.visible and fade.mouse_filter == Control.MOUSE_FILTER_IGNORE, "%s: the fade ends clear and lets taps through" % level)
		(a.get_node("%LobbyButton") as Button).pressed.emit()
		await _frames_until(func() -> bool: return int(_app().call("depth")) == 2, 120)
		await _frames_until(func() -> bool: return not bool(hall.call("fading")), 120)
		_check(int(_app().call("depth")) == 2, "%s: back on the deck" % level)
	_app().call("set_gfx", "mid")
	hall.call("refresh")


# ---- helpers (as in test_hall) ----

## Shader code under the node that uses TIME (lo/min must have none).
func _time_shaders(node: Node) -> PackedStringArray:
	var out := PackedStringArray()
	var stack: Array[Node] = [node]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		var mats: Array = []
		if n is GeometryInstance3D:
			mats.append((n as GeometryInstance3D).material_override)
			if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
				for s in (n as MeshInstance3D).mesh.get_surface_count():
					mats.append((n as MeshInstance3D).get_active_material(s))
		if n is CanvasItem:
			mats.append((n as CanvasItem).material)
		for m in mats:
			var mm: Material = m
			while mm != null:
				if mm is ShaderMaterial and (mm as ShaderMaterial).shader != null and (mm as ShaderMaterial).shader.code.contains("TIME"):
					out.append("%s (%s)" % [n.name, (mm as ShaderMaterial).shader.resource_path])
				mm = mm.next_pass
		stack.append_array(n.get_children())
	return out


func _idle_problems(screen: Node) -> PackedStringArray:
	var out := PackedStringArray()
	var stack: Array[Node] = [screen]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n.can_process() and (n.is_processing() or n.is_physics_processing()):
			out.append(String(n.name) + " processes")
		if n is Timer and not (n as Timer).is_stopped():
			out.append(String(n.name) + " timer runs")
		stack.append_array(n.get_children())
	return out


func _layout_problems(screen: Node) -> PackedStringArray:
	var out := PackedStringArray()
	var vis := root.get_visible_rect()
	_walk(screen, func(c: Control) -> void:
		var r := c.get_global_rect()
		if r.position.x < vis.position.x - 1.0 or r.position.y < vis.position.y - 1.0 or r.end.x > vis.end.x + 1.0 or r.end.y > vis.end.y + 1.0:
			out.append("%s outside the canvas %s" % [c.name, str(r)])
		var p := c.get_parent() as Control
		if p != null and not p is ScrollContainer and c != screen:
			var pr := p.get_global_rect()
			if r.position.x < pr.position.x - 1.0 or r.position.y < pr.position.y - 1.0 or r.end.x > pr.end.x + 1.0 or r.end.y > pr.end.y + 1.0:
				out.append("%s outside its parent %s: %s in %s" % [c.name, p.name, str(r), str(pr)])
		if c is Button and (r.size.x < MIN_TARGET - 0.5 or r.size.y < MIN_TARGET - 0.5):
			out.append("%s smaller than 44x44 %s" % [c.name, str(r.size)])
		if c is Label and (c as Label).autowrap_mode != TextServer.AUTOWRAP_OFF and (c as Label).get_line_count() > (c as Label).get_visible_line_count():
			out.append("%s cuts its text (%d of %d lines)" % [c.name, (c as Label).get_visible_line_count(), (c as Label).get_line_count()]))
	return out


func _walk(node: Node, f: Callable) -> void:
	if node is CanvasItem and not (node as CanvasItem).is_visible_in_tree():
		return
	if node is Control:
		f.call(node)
	for c in node.get_children():
		_walk(c, f)


func _thai_in(node: Node, exempt: Array) -> PackedStringArray:
	var out := PackedStringArray()
	_scan(node, exempt, out)
	return out


func _scan(node: Node, exempt: Array, out: PackedStringArray) -> void:
	if node is CanvasItem and not (node as CanvasItem).is_visible_in_tree():
		return
	if node is Node3D and not (node as Node3D).is_visible_in_tree():
		return
	if not exempt.has(String(node.name)):
		var texts := PackedStringArray()
		if node is Label or node is Button:
			texts.append(str(node.get("text")))
		if node is Label3D:
			texts.append((node as Label3D).text)
		for t in texts:
			if _thai_re.search(t) != null:
				out.append(String(node.name) + ": " + t.left(60))
	for c in node.get_children():
		_scan(c, exempt, out)


func _frames_until(cond: Callable, n: int) -> void:
	for i in n:
		if cond.call():
			return
		await process_frame


func _machine_settings() -> String:
	var p := "user://settings.cfg"
	return "%d:%s" % [FileAccess.get_modified_time(p), FileAccess.get_file_as_string(p)] if FileAccess.file_exists(p) else "none"


func _resize(sz: Vector2i) -> void:
	root.size = sz
	await _frames(SETTLE)


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _physics(n: int) -> void:
	for i in n:
		await physics_frame


func _key(code: Key, pressed: bool) -> void:
	var ev := InputEventKey.new()
	ev.physical_keycode = code
	ev.keycode = code
	ev.pressed = pressed
	Input.parse_input_event(ev)
	Input.flush_buffered_events()


func _app() -> Node:
	return root.get_node(^"App")


func _save(name: String) -> void:
	var img := root.get_viewport().get_texture().get_image()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_out_dir))
	var path := _out_dir + "/" + name
	var err := img.save_png(path)
	_check(err == OK, "saved " + ProjectSettings.globalize_path(path) + " " + str(img.get_size()))


func _finish() -> void:
	for k in [KEY_W, KEY_A, KEY_S, KEY_D, KEY_SHIFT, KEY_E]:
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
