extends SceneTree
## The walkable lobby (LOBBY_SPEC §2, §7.3), since 0.3 the warship deck of SHIP_LOBBY_SPEC (§9.1, §9.3), inside
## scenes/main.tscn, reached from the main menu's %PlayButton.
## Entry: the table_view node stays hidden and disabled, the hall camera is current.
## Movement by simulated physical keys: W follows the camera's forward, D its right, Shift+W covers >= 1.6x the walk
## distance in the same physics frames, after a 90-degree mouse orbit W follows the new forward, and walking into the
## back wall, a pillar and the war table stops at the surface (the avatar never enters a blocker).
## Camera: in each corner, orbiting, tilting and zooming out keeps the camera inside the hall (0.1 m in), in no blocker
## and below the ceiling (y = 6); six walks (past pillars and stands, from the spawn to the vault, and along the airlock
## with the camera between the avatar and the right wall, where it must come within 0.5 m of the airlock's face) move
## the arm by at most 0.5 m a frame. Stations: each prompt shows its translated name, E at the armoury and the console opens the army
## picker / settings and their back buttons return to an active hall, the docking airlock (right wall), the adventure
## table and the vault (treasure chest) show %SoonPanel and stay; the vault in Thai and English: prompt, panel text, Esc
## and walking away close it, the touch use button opens it; the exit door, %MenuButton and Esc return to the main menu.
## Touch: with App.touch "on" %Stick and the touch prompt show, simulated screen touches on the stick walk (past 0.85
## run), "off" hides it. Thai and English at 640x360, 1280x720 and 1280x576 with the 3D signs included; layout rules of
## §7.1, with the adventure and the vault coming-soon panels open too (vault line: one line in Thai, at most two in
## English). Levels: ships, drift, holo flicker and stars per SHIP_LOBBY_SPEC §6, no ShaderMaterial under the hall on
## lo/min, Ships hidden on min, the Space mesh shown on every level. min: after 10 idle frames nothing under the hall
## processes and the spring arm sleeps; draw calls and primitives are printed for all four levels and checked against
## §2.6 (min <= 40 / 40k) and the deck targets of SHIP_LOBBY_SPEC §6 (min <= 30 / 30k), in the overview and again in the
## phone layout's worst view (20:9 window, touch on, first-entry hint showing, at the war table looking across the deck);
## sign outlines only on hi/mid, the title plaque on the signs' font size, the drifting ships' culling box covers the
## dome. No holes into the void: with a magenta background no magenta pixel shows in 64 views on mid and 32 on min.
## Saves hall_th.png, hall_en.png, hall_min.png, hall_touch.png (_<w>x<h> added for the other sizes), hall_viewport.png,
## hall_vault.png, hall_vault_en.png and hall_deck_<level>.png. Run:
##   timeout 900 xvfb-run -a -s "-screen 0 1280x720x24" <godot> --path godot --rendering-driver opengl3 \
##       --resolution 1280x720 --audio-driver Dummy -s tests/render/test_hall.gd
## TEST_OUT (an absolute folder) in the environment replaces tests/out. Exit code 1 on any failure.

const SCENE := "res://scenes/main.tscn"
const HALL_SCREEN := "res://ui/screens/hall_screen.tscn"
const BATTLE_SETUP := "res://ui/screens/battle_setup.tscn"
const DEFAULT_OUT_DIR := "res://tests/out"
const SETTINGS_FILE := "user://test_hall.cfg"
const SIZES: Array[Vector2i] = [Vector2i(1280, 720), Vector2i(640, 360), Vector2i(1280, 576)]
const SETTLE := 6
const MIN_TARGET := 44.0
const HALL_NAMES: PackedStringArray = ["UseButton", "Stick", "MenuButton", "SettingsButton", "SoonPanel", "Hint"]
## [draw calls, primitives] per level (LOBBY_SPEC §2.6)
const BUDGET := {"hi": [140, 250000], "mid": [100, 150000], "lo": [60, 80000], "min": [40, 40000]}
## tighter targets of the warship deck (SHIP_LOBBY_SPEC §6), asserted as well
const SHIP_TARGET := {"hi": [40, 60000], "mid": [40, 50000], "lo": [35, 40000], "min": [30, 30000]}
## [ships, ships drift, holo flickers, stars] per level (SHIP_LOBBY_SPEC §6)
const DECK := {"hi": [5, true, true, 700], "mid": [3, true, true, 500], "lo": [3, false, false, 320], "min": [0, false, false, 180]}
## the vault's coming-soon line: lines allowed in Thai / English (SHIP_LOBBY_SPEC §5)
const VAULT_LINES := {"th": 1, "en": 2}
## no holes into the void: spots the camera looks from (SHIP_LOBBY_SPEC §9.3)
const VOID_SPOTS: Array[Vector3] = [Vector3(0.0, 0.0, 5.0), Vector3(0.0, 0.0, -6.5), Vector3(-10.0, 0.0, 6.0), Vector3(9.5, 0.0, 4.5)]
const VOID_SIZE := Vector2i(640, 360)
const MAGENTA := Color(1.0, 0.0, 1.0)
const LEVELS: PackedStringArray = ["hi", "mid", "lo", "min"]
const WALK_TICKS := 45

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
	var menu: Node = _app().call("current")
	var hall := await _enter(menu)
	if hall == null:
		_finish()
		return
	var world: Node3D = hall.get("world")
	var missing := PackedStringArray()
	for n in HALL_NAMES:
		if hall.get_node_or_null("%" + n) == null:
			missing.append(n)
	_check(missing.is_empty(), "the hall screen carries every contract node", str(missing))
	_check(world != null and world.name == &"HallWorld" and world.is_in_group("gfx_level"), "its world is the HallWorld child, in the gfx_level group")
	var c: Dictionary = world.call("counts")
	print("hall counts: " + str(c))
	# 0.3 (SHIP_LOBBY_SPEC §9.1): two vault candles (24 -> 26 flames), the vault sign and the title plaque (7 -> 9 labels),
	# the space mesh behind the viewport (3 -> 4 static meshes)
	_check(int(c["flames"]) == 26 and int(c["signs"]) == 9 and int(c["static_meshes"]) <= 4 and int(c["blockers"]) >= 20,
		"mid: 26 flames, 7 station signs + the title plaque + the name tag, at most 4 static meshes, every blocker built", str(c))
	var table := get_first_node_in_group("table_view") as Node3D
	_check(table == null or (not table.visible and table.process_mode == Node.PROCESS_MODE_DISABLED), "the battle table stays hidden and disabled under the hall")
	_check(_camera(world).current, "the hall camera is current")
	_check(_avatar(world).global_position.distance_to(HallLayout.SPAWN) < 0.01 and str(hall.call("station")) == "",
		"the avatar starts at the spawn, in no station")

	await _check_texts(hall)
	await _check_movement(hall)
	await _check_walls(hall)
	await _check_camera(hall)
	await _check_camera_walks(hall)
	await _check_stations(hall)
	await _check_touch(hall)
	await _check_levels(hall)
	await _check_touch_budget(hall)
	await _check_void(hall)
	await _check_ways_out(hall)
	_check(_machine_settings() == _machine_cfg, "this machine's settings.cfg was not touched")
	_finish()


## Main menu -> %PlayButton -> hall (depth 2).
func _enter(menu: Node) -> Node:
	var play: Button = menu.get_node_or_null("%PlayButton") if menu != null else null
	_check(play != null, "the main menu offers %PlayButton")
	if play != null:
		play.pressed.emit()
	else:
		_app().call("push", load(HALL_SCREEN))
	await _frames(3)
	var hall: Node = _app().call("current")
	_check(hall != null and hall.has_method("use_station") and hall.has_method("station") and hall.has_signal("station_changed"),
		"the play button opens the hall screen")
	_check(int(_app().call("depth")) == 2, "the hall sits on top of the main menu (depth 2)")
	if hall == null or not hall.has_method("use_station"):
		return null
	return hall


# ---- text and layout ----

func _check_texts(hall: Node) -> void:
	var world: Node3D = hall.get("world")
	world.call("place_avatar", _front("battle"), PI)
	await _settle()
	_check(str(hall.call("station")) == "battle", "standing in front of the war table makes it the station")
	for sz in SIZES:
		await _resize(sz)
		for lang in ["th", "en"]:
			_app().call("set_lang", lang)
			hall.call("refresh")
			await _frames(3)
			var tag := "%s %dx%d" % [lang, sz.x, sz.y]
			var use: Button = hall.get_node("%UseButton")
			_check(use.visible, tag + ": the use button shows at the war table")
			var lay := _layout_problems(hall)
			_check(lay.is_empty(), tag + ": nothing sticks out, no buttons overlap, targets >= 44 px", ", ".join(lay))
			var thai := _thai_in(hall, [])
			if lang == "en":
				_check(thai.is_empty(), tag + ": no Thai on screen or on the 3D signs", ", ".join(thai))
				_check(use.text == "Battle Table · press E", tag + ": English prompt " + use.text)
			else:
				var signs := 0
				for l: Label3D in world.call("labels"):
					if _thai_re.search(l.text) != null:
						signs += 1
				# 0.3: seven station signs, the title plaque and the name tag (was six signs + the name tag)
				_check(signs == 9, tag + ": the seven station signs, the title plaque and the name tag are Thai (%d)" % signs)
				_check(str(world.call("sign_text", "title")) == "ดาดฟ้ายานรบ", tag + ": the title plaque reads ดาดฟ้ายานรบ")
				_check(use.text == "โต๊ะรบ · กด E", tag + ": Thai prompt " + use.text)
				_check(_thai_re.search((hall.get_node("%MenuButton") as Button).text) != null, tag + ": the menu button is Thai")
				_check((hall.get_node("%Hint") as Label).visible and _thai_re.search((hall.get_node("%Hint") as Label).text) != null,
					tag + ": the first-entry hint shows in Thai")
			if sz == SIZES[0] or lang == "th":
				_save("hall_%s%s.png" % [lang, _suffix(sz)])
			hall.call("show_soon", "adventure")
			await _frames(2)
			lay = _layout_problems(hall)
			_check(lay.is_empty(), tag + ": the coming-soon panel fits too", ", ".join(lay))
			if lang == "en":
				thai = _thai_in(hall, [])
				_check(thai.is_empty(), tag + ": the coming-soon panel is English", ", ".join(thai))
				_check(str(world.call("sign_text", "title")) == "Warship Deck", tag + ": the title plaque reads Warship Deck")
			hall.call("close_soon")
			# 0.3: the vault's longer line (SHIP_LOBBY_SPEC §5, panel 760 x 120)
			hall.call("show_soon", "vault")
			await _frames(2)
			var label: Label = hall.get_node("%SoonLabel")
			lay = _layout_problems(hall)
			_check(lay.is_empty(), tag + ": the vault coming-soon panel fits too", ", ".join(lay))
			_check(label.get_line_count() <= int(VAULT_LINES[lang]) and label.get_visible_line_count() == label.get_line_count(),
				tag + ": the vault line takes %d line(s), at most %d, all shown" % [label.get_line_count(), int(VAULT_LINES[lang])])
			if lang == "en":
				thai = _thai_in(hall, [])
				_check(thai.is_empty() and label.text.begins_with("Treasure chest"), tag + ": the vault panel is English (%s)" % label.text, ", ".join(thai))
			else:
				_check(label.text.begins_with("หีบสมบัติ"), tag + ": the vault panel is Thai (%s)" % label.text)
			hall.call("close_soon")
	await _resize(SIZES[0])
	_app().call("set_lang", "th")
	hall.call("refresh")
	await _frames(2)


# ---- movement ----

func _check_movement(hall: Node) -> void:
	var world: Node3D = hall.get("world")
	var av := _avatar(world)
	var rig: Node3D = world.get("camera_rig")
	rig.call("set_view", 0.0, -0.45, 6.5)
	# 0.3: the starts moved from x 4 to x 2: the treasure chest (r 1.2 at (5, 4)) now stands in the old walk lines
	world.call("place_avatar", Vector3(2.0, 0.0, 6.5), PI)
	await _settle()
	var d := await _hold([KEY_W], WALK_TICKS)
	var fwd: Vector3 = rig.call("forward_flat")
	_check(d.length() > 1.0 and d.normalized().dot(fwd) > 0.98, "W walks along the camera's forward (%s, %.2f m)" % [str(d.snapped(Vector3.ONE * 0.01)), d.length()])
	_check(not (hall.get_node("%Hint") as Label).visible or (hall.get_node("%Hint") as Label).modulate.a < 1.0 or bool(hall.call("hint_done")),
		"the first move hides the hint")
	await _until_still(av)
	_check(not av.is_physics_processing(), "after the keys are released the avatar stops processing")
	world.call("place_avatar", Vector3(2.0, 0.0, 6.5), PI)
	await _settle()
	d = await _hold([KEY_D], 30)
	var right: Vector3 = rig.call("right_flat")
	_check(d.length() > 0.5 and d.normalized().dot(right) > 0.98, "D walks to the camera's right (%s)" % str(d.snapped(Vector3.ONE * 0.01)))
	_check(absf(wrapf(float(av.get("face")) - atan2(right.x, right.z), -PI, PI)) < 0.35, "the avatar turns to face where it walks")
	await _until_still(av)
	# the same physics frames with and without Shift
	world.call("place_avatar", Vector3(2.0, 0.0, 7.0), PI)
	await _settle()
	var walk := (await _hold([KEY_W], WALK_TICKS)).length()
	await _until_still(av)
	world.call("place_avatar", Vector3(2.0, 0.0, 7.0), PI)
	await _settle()
	var run := (await _hold([KEY_SHIFT, KEY_W], WALK_TICKS)).length()
	await _until_still(av)
	_check(run >= walk * 1.6, "Shift+W covers %.2f m against %.2f m walking (x%.2f >= 1.6)" % [run, walk, run / maxf(walk, 0.001)])
	# arrows walk like WASD
	world.call("place_avatar", Vector3(2.0, 0.0, 6.5), PI)
	await _settle()
	d = await _hold([KEY_UP], 30)
	_check(d.normalized().dot(fwd) > 0.98 and d.length() > 0.5, "the Up arrow walks forward too")
	await _until_still(av)
	# a 90-degree orbit by right-mouse drag, then W follows the new forward
	world.call("place_avatar", Vector3(4.0, 0.0, 2.0), PI)
	await _settle()
	var yaw0 := float(rig.get("yaw"))
	await _mouse_drag(MOUSE_BUTTON_RIGHT, Vector2(-(PI * 0.5) / 0.006, 0.0))
	var yaw1 := float(rig.get("yaw"))
	_check(absf(wrapf(yaw1 - yaw0 - PI * 0.5, -PI, PI)) < 0.02, "a right-mouse drag orbits the camera 90 degrees (%.3f -> %.3f)" % [yaw0, yaw1])
	fwd = rig.call("forward_flat")
	d = await _hold([KEY_W], 30)
	_check(d.length() > 0.5 and d.normalized().dot(fwd) > 0.98, "after the orbit W follows the new forward %s (%s)" % [str(fwd.snapped(Vector3.ONE * 0.01)), str(d.snapped(Vector3.ONE * 0.01))])
	await _until_still(av)
	rig.call("set_view", 0.0, -0.45, 6.5)


func _check_walls(hall: Node) -> void:
	var world: Node3D = hall.get("world")
	var av := _avatar(world)
	var rig: Node3D = world.get("camera_rig")
	rig.call("set_view", 0.0, -0.45, 6.5)
	# [start, keys, name, check(final) -> bool]
	var cases := [
		[Vector3(-6.0, 0.0, -5.6), [KEY_W], "the back wall (viewport)", func(p: Vector3) -> bool: return p.z >= -HallLayout.HALF.y + HallLayout.AVATAR_R - 0.02 and p.z < -7.5],
		[Vector3(8.5, 0.0, -2.6), [KEY_W], "a pillar", func(p: Vector3) -> bool: return Vector2(p.x, p.z).distance_to(HallLayout.PILLARS[1]) >= HallLayout.PILLAR_R + HallLayout.AVATAR_R - 0.02 and p.z < -3.9],
		[Vector3(0.0, 0.0, 2.6), [KEY_W], "the war table", func(p: Vector3) -> bool: return p.z >= HallLayout.AVATAR_R - 0.02 and p.z < 0.5],
	]
	for cs in cases:
		world.call("place_avatar", cs[0], PI)
		await _settle()
		var worst := await _hold_tracking(cs[1], 110, av)
		var p := av.global_position
		_check((cs[3] as Callable).call(p), "walking into %s stops at its surface (%s)" % [cs[2], str(p.snapped(Vector3.ONE * 0.01))])
		_check(worst == "", "the avatar never enters a blocker on the way to %s" % cs[2], worst)
		await _until_still(av)


func _check_camera(hall: Node) -> void:
	var world: Node3D = hall.get("world")
	var av := _avatar(world)
	var rig: Node3D = world.get("camera_rig")
	var cam := _camera(world)
	var corners := [[Vector3(-10.8, 0, -6.9), [KEY_W, KEY_A]], [Vector3(10.8, 0, -6.9), [KEY_W, KEY_D]],
		[Vector3(-10.8, 0, 6.9), [KEY_S, KEY_A]], [Vector3(10.8, 0, 6.9), [KEY_S, KEY_D]]]
	var bad := PackedStringArray()
	var n := 0
	for cn in corners:
		rig.call("set_view", 0.0, -0.45, 6.5)
		world.call("place_avatar", cn[0], PI)
		await _settle()
		await _hold(cn[1], 50)
		await _until_still(av)
		for i in 8:
			for pv in [[-0.15, 9.0], [-0.45, 6.5], [-1.2, 9.0]]:
				rig.call("set_view", i * PI / 4.0, pv[0], pv[1])
				await _physics(4)
				n += 1
				var p := cam.global_position
				if HallLayout.inside_solid(p, 0.1) or p.y >= HallLayout.CEIL_Y:
					bad.append("%s yaw %d pitch %.2f: camera %s" % [str(cn[0]), i * 45, pv[0], str(p.snapped(Vector3.ONE * 0.01))])
	_check(bad.is_empty(), "in all four corners the camera stays inside the hall, out of every blocker, below y = 6 (%d views)" % n, "\n".join(bad))
	rig.call("set_view", 0.0, -0.45, 6.5)
	await _physics(4)


## Natural walks past pillars and stands (review of 12 Nov): the camera glides (the spring arm's hit length changes by at
## most 0.5 m a physics frame, against 5.4 m before props left the arm's mask) and never enters a blocker.
## Each walk: start, stick, name, camera yaw, and optionally a station whose footprint the camera must pass within 0.5 m.
func _check_camera_walks(hall: Node) -> void:
	var world: Node3D = hall.get("world")
	var rig: Node3D = world.get("camera_rig")
	var arm: SpringArm3D = rig.get("arm")
	var cam := _camera(world)
	var av := _avatar(world)
	# 0.3: the lectern is the console and the army display the armoury (names only); two walks added around the vault
	# and the moved airlock (SHIP_LOBBY_SPEC §9.3). Review of 12 Nov: with yaw 0 the old "past the vault to the airlock"
	# walk kept the camera at the front wall (never closer than 2.9 m to the airlock), so the airlock walk now runs along
	# its front with the camera between the avatar and the right wall. The vault walk is a smoke walk: the chest's padded
	# top (1.55 m) stays under the camera (>= 1.75 m unless a wall shortens the arm, and the chest is >= 6 m from walls).
	var walks := [[Vector3(0.0, 0, 5.0), Vector2(0.8, 0.6), "spawn -> the console", 0.0], [Vector3(0.0, 0, 5.0), Vector2(-0.8, 0.6), "spawn -> the armoury", 0.0],
		[Vector3(5.0, 0, -3.5), Vector2(1.0, 0.0), "past the pillar at (8.5, 0.5)", 0.0], [Vector3(-11.0, 0, 3.0), Vector2(1.0, 0.0), "across the hall at z 3", 0.0],
		[Vector3(0.0, 0, 5.0), Vector2(0.9, 0.2), "spawn -> the vault", 0.0],
		[Vector3(9.5, 0, 0.2), Vector2(-1.0, 0.0), "along the airlock, camera between the avatar and the right wall", PI * 0.5, "online"]]
	for w in walks:
		rig.call("set_view", float(w[3]), -0.45, 6.5)
		world.call("place_avatar", w[0], PI)
		await _physics(10)
		world.call("set_stick", w[1])
		var last := arm.get_hit_length()
		var worst := 0.0
		var inside := ""
		var near := INF
		for i in 200:
			await physics_frame
			var l := arm.get_hit_length()
			worst = maxf(worst, absf(l - last))
			last = l
			var cp := cam.global_position
			if inside == "" and HallLayout.inside_solid(cp, 0.1):
				inside = "camera %s with the avatar at %s" % [str(cp.snapped(Vector3.ONE * 0.01)), str(av.global_position.snapped(Vector3.ONE * 0.01))]
			if w.size() > 4:
				near = minf(near, HallLayout.dist_to_rect(Vector2(cp.x, cp.z), HallLayout.rect_of(str(w[4]))))
		world.call("set_stick", Vector2.ZERO)
		await _until_still(av)
		_check(worst <= 0.5, "walking %s the camera arm changes by at most 0.5 m a frame (%.2f m)" % [w[2], worst])
		_check(inside == "", "walking %s the camera never enters a blocker" % w[2], inside)
		if w.size() > 4:
			_check(near <= 0.5, "walking %s the camera passes within 0.5 m of the %s footprint (%.2f m)" % [w[2], str(w[4]), near])
	rig.call("set_view", 0.0, -0.45, 6.5)
	await _physics(4)


# ---- stations ----

func _check_stations(hall: Node) -> void:
	var world: Node3D = hall.get("world")
	var names: Dictionary = (hall.get_script() as Script).get_script_constant_map()["NAMES"]
	var use: Button = hall.get_node("%UseButton")
	for id in HallLayout.IDS:
		world.call("place_avatar", _front(id), PI)
		await _settle()
		_check(str(hall.call("station")) == id and use.visible and use.text.contains(str(root.get_node(^"I18n").call("t", str(names[id])))),
			"at %s the prompt names it: %s" % [id, use.text])
	# 0.3: the airlock moved to the right wall (SHIP_LOBBY_SPEC §2.2): its prompt shows over there
	world.call("place_avatar", _front("online"), PI)
	await _settle()
	_check(_avatar(world).global_position.x > 10.0 and str(hall.call("station")) == "online", "the docking airlock is on the right wall (avatar at x %.2f)" % _avatar(world).global_position.x)
	# the armoury and the console open their screens; back returns to an active hall
	for pair in [["army", "the army picker", "listed_units"], ["settings", "the settings screen", "refresh"]]:
		world.call("place_avatar", _front(pair[0]), PI)
		await _settle()
		await _press(KEY_E)
		var screen: Node = _app().call("current")
		_check(screen != hall and screen != null and screen.has_method(pair[2]), "E at %s opens %s" % [pair[0], pair[1]])
		_check(not (hall as CanvasItem).visible and not world.visible and world.process_mode == Node.PROCESS_MODE_DISABLED and not _camera(world).current,
			"the hall is hidden, stopped and gives up the camera under %s" % pair[1])
		var back: Button = screen.get_node_or_null("%BackButton") if screen != null else null
		_check(back != null, "%s has a back button" % pair[1])
		if back != null:
			back.pressed.emit()
		else:
			_app().call("pop")
		await _frames(3)
		_check(_app().call("current") == hall and (hall as CanvasItem).visible and world.visible
			and world.process_mode == Node.PROCESS_MODE_INHERIT and _camera(world).current,
			"back from %s: the hall is visible, active and owns the camera again" % pair[1])
		var table := get_first_node_in_group("table_view") as Node3D
		_check(table == null or not table.visible, "the battle table is still hidden after %s" % pair[1])
	# online, adventure and (0.3) the vault show the coming-soon panel and stay
	var soon: Control = hall.get_node("%SoonPanel")
	var soon_texts: Dictionary = (hall.get_script() as Script).get_script_constant_map()["SOON"]
	for id in ["online", "adventure", "vault"]:
		world.call("place_avatar", _front(id), PI)
		await _settle()
		await _press(KEY_E)
		_check(soon.visible and _app().call("current") == hall and int(_app().call("depth")) == 2, "E at %s shows the coming-soon panel and stays in the hall" % id)
		_check((hall.get_node("%SoonLabel") as Label).text == str(soon_texts[id]), "the %s panel shows its own line" % id)
		var timer: Timer = hall.get_node("%SoonTimer")
		_check(not timer.is_stopped() and timer.wait_time <= 2.6, "the panel closes itself after 2.5 s")
		await _press(KEY_ESCAPE)
		_check(not soon.visible and _app().call("current") == hall, "Esc closes the %s panel first and stays in the hall" % id)
	world.call("place_avatar", _front("online"), PI)
	await _settle()
	hall.call("use_station")
	await _frames(1)
	await _hold([KEY_S], 6)
	_check(not soon.visible, "walking away closes the coming-soon panel")
	await _until_still(_avatar(world))
	await _check_vault(hall)
	# the war table opens the battle setup once the battle track has built it
	if ResourceLoader.exists(BATTLE_SETUP):
		world.call("place_avatar", _front("battle"), PI)
		await _settle()
		await _press(KEY_E)
		var setup: Node = _app().call("current")
		_check(setup != hall and setup != null and setup.scene_file_path == BATTLE_SETUP, "E at the war table opens the battle setup")
		_app().call("pop")
		await _frames(3)
		_check(_app().call("current") == hall and world.visible, "popping the setup returns to the hall")
	else:
		print("note  %s is not built yet; the flow test covers the war table" % BATTLE_SETUP)


## The treasure chest (SHIP_LOBBY_SPEC §5): the station for the future random rewards only says "coming soon" in Thai
## and English; Esc (App.back) closes the panel first, walking away closes it, nothing is pushed.
func _check_vault(hall: Node) -> void:
	var world: Node3D = hall.get("world")
	var soon: Control = hall.get_node("%SoonPanel")
	var label: Label = hall.get_node("%SoonLabel")
	var use: Button = hall.get_node("%UseButton")
	var rig: Node3D = world.get("camera_rig")
	for lang in ["th", "en"]:
		_app().call("set_lang", lang)
		hall.call("refresh")
		world.call("place_avatar", _front("vault"), PI)
		rig.call("set_view", PI * 0.5, -0.35, 5.5)   # from behind the chest, so the PNG shows it under the panel
		await _settle()
		var want_prompt := "หีบสมบัติ · กด E" if lang == "th" else "Treasure Chest · press E"
		_check(str(hall.call("station")) == "vault" and use.visible and use.text == want_prompt, "%s: at the chest the prompt is %s" % [lang, use.text])
		var sign_text := str(world.call("sign_text", "vault"))
		_check(sign_text == ("หีบสมบัติ · เร็วๆ นี้" if lang == "th" else "Treasure Chest · Coming soon"), "%s: the chest's sign reads %s" % [lang, sign_text])
		await _press(KEY_E)
		var want := "หีบสมบัติ — เร็วๆ นี้: สุ่มรับชิ้นส่วนปืนและของตกแต่ง" if lang == "th" else "Treasure chest — coming soon: win random gun parts and decorations"
		_check(soon.visible and label.text == want and _app().call("current") == hall and int(_app().call("depth")) == 2,
			"%s: E at the chest opens the coming-soon panel (%s) and stays in the hall" % [lang, label.text])
		if lang == "en":
			var thai := _thai_in(hall, [])
			_check(thai.is_empty(), "en: no Thai at the chest with its panel open", ", ".join(thai))
		var lay := _layout_problems(hall)
		_check(lay.is_empty(), "%s: the chest's panel fits the screen" % lang, ", ".join(lay))
		_save("hall_vault%s.png" % ("" if lang == "th" else "_en"))
		_app().call("back")
		await _frames(2)
		_check(not soon.visible and _app().call("current") == hall and int(_app().call("depth")) == 2, "%s: back (Esc) closes the chest's panel first and stays in the hall" % lang)
		await _press(KEY_E)
		_check(soon.visible, "%s: E opens it again" % lang)
		await _hold([KEY_S], 6)
		_check(not soon.visible, "%s: walking away from the chest closes its panel" % lang)
		await _until_still(_avatar(world))
	_app().call("set_lang", "th")
	hall.call("refresh")
	rig.call("set_view", 0.0, -0.45, 6.5)
	await _settle()


func _check_touch(hall: Node) -> void:
	var world: Node3D = hall.get("world")
	var av := _avatar(world)
	var stick: Control = hall.get_node("%Stick")
	var use: Button = hall.get_node("%UseButton")
	_app().call("set_touch", "on")
	hall.call("refresh")
	await _frames(2)
	world.call("place_avatar", _front("army"), PI)
	await _settle()
	_check(stick.visible, "touch on: the stick shows")
	_check(use.visible and use.text.ends_with("· แตะเพื่อใช้") and use.size.y >= 64.0, "touch on: the big touch prompt (%s, %.0f px)" % [use.text, use.size.y])
	_check(stick.get_global_rect().intersection(use.get_global_rect()).get_area() < 1.0, "the stick and the use button do not overlap")
	# 0.3: the touch use button opens the chest's coming-soon panel too
	world.call("place_avatar", _front("vault"), PI)
	await _settle()
	_check(use.visible and use.text == "หีบสมบัติ · แตะเพื่อใช้", "touch on: the chest's prompt is %s" % use.text)
	use.pressed.emit()
	await _frames(2)
	_check((hall.get_node("%SoonPanel") as Control).visible and _app().call("current") == hall, "tapping the use button at the chest opens its coming-soon panel")
	# review of 12 Nov: the panel has nothing to tap, so a one-finger drag that starts on it still orbits the camera
	var rig: Node3D = world.get("camera_rig")
	var on_panel := (hall.get_node("%SoonPanel") as Control).get_global_rect().get_center()
	var yaw_p := float(rig.get("yaw"))
	_touch(1, on_panel, true)
	_drag(1, on_panel + Vector2(-100.0, 0.0), Vector2(-100.0, 0.0))
	_touch(1, on_panel + Vector2(-100.0, 0.0), false)
	await _frames(2)
	_check(absf(float(rig.get("yaw")) - yaw_p - 100.0 * 0.006) < 0.01 and (hall.get_node("%SoonPanel") as Control).visible,
		"a one-finger drag that starts on the open coming-soon panel orbits the camera (%.3f -> %.3f)" % [yaw_p, float(rig.get("yaw"))])
	hall.call("close_soon")
	rig.call("set_view", 0.0, -0.45, 6.5)
	# 0.3: start at x 2, not 4: running forward from (4, 7) now reaches the treasure chest at (5, 4)
	world.call("place_avatar", Vector3(2.0, 0.0, 7.0), PI)
	await _settle()
	var centre := stick.get_global_rect().get_center()
	var p0 := av.global_position
	_touch(0, centre, true)
	await _frames(1)
	_drag(0, centre + Vector2(0.0, -60.0), Vector2(0.0, -60.0))
	await _physics(30)
	var walked := av.global_position - p0
	var v: Vector2 = stick.get("value")
	_check(walked.length() > 0.5 and walked.normalized().dot(rig.call("forward_flat")) > 0.98 and v.y > 0.6,
		"pushing the stick up walks forward (%.2f m, stick %s)" % [walked.length(), str(v)])
	_check(float(av.call("speed")) <= HallAvatar.WALK + 0.01, "two thirds of the stick walks (%.2f m/s)" % float(av.call("speed")))
	_drag(0, centre + Vector2(0.0, -88.0), Vector2(0.0, -28.0))
	await _physics(30)
	_check(float(av.call("speed")) > HallAvatar.WALK + 0.5 and bool(stick.call("running")), "past 0.85 it runs (%.2f m/s)" % float(av.call("speed")))
	_save("hall_touch.png")
	_touch(0, centre + Vector2(0.0, -88.0), false)
	await _frames(1)
	_check((stick.get("value") as Vector2) == Vector2.ZERO, "lifting the finger centres the stick")
	await _until_still(av)
	_check(not av.is_physics_processing(), "and the avatar comes to a stop")
	# one finger on empty screen orbits the camera; the stick stays centred
	var yaw0 := float(rig.get("yaw"))
	var free := root.get_visible_rect().get_center() + Vector2(260.0, -60.0)
	_touch(1, free, true)
	_drag(1, free + Vector2(-100.0, 0.0), Vector2(-100.0, 0.0))
	_touch(1, free + Vector2(-100.0, 0.0), false)
	await _frames(2)
	_check(absf(float(rig.get("yaw")) - yaw0 - 100.0 * 0.006) < 0.01 and (stick.get("value") as Vector2) == Vector2.ZERO,
		"a one-finger drag on empty screen orbits the camera (%.3f -> %.3f), not the stick" % [yaw0, float(rig.get("yaw"))])
	var arm0 := float(rig.get("arm_length"))
	var wheel := InputEventMouseButton.new()
	wheel.button_index = MOUSE_BUTTON_WHEEL_UP
	wheel.pressed = true
	wheel.position = _to_window(free)
	Input.parse_input_event(wheel)
	Input.flush_buffered_events()
	await _frames(2)
	_check(float(rig.get("arm_length")) < arm0 - 0.1, "the mouse wheel zooms in (%.2f -> %.2f)" % [arm0, float(rig.get("arm_length"))])
	rig.call("set_view", 0.0, -0.45, 6.5)
	_app().call("set_touch", "off")
	hall.call("refresh")
	await _frames(2)
	_check(not stick.visible, "touch off: the stick is hidden")
	world.call("place_avatar", _front("army"), PI)
	await _settle()
	_check(use.text.ends_with("· กด E"), "touch off: the keyboard prompt is back (%s)" % use.text)


# ---- graphics levels ----

func _check_levels(hall: Node) -> void:
	var world: Node3D = hall.get("world")
	var rig: Node3D = world.get("camera_rig")
	# review of 12 Nov: a 72 px plaque font allocated two more glyph caches (about 4 MB); it now reuses the signs' size
	var title := world.get_node("Signs/Sign_title") as Label3D
	_check(title.font_size == HallWorld.SIGN_FONT_SIZE and absf(title.pixel_size * title.font_size - HallWorld.SIGN_PIXEL * 72.0) < 0.000001,
		"the title plaque uses the signs' font size %d (no extra glyph cache) and is drawn as large as size 72" % title.font_size)
	world.call("place_avatar", Vector3(0.0, 0.0, 3.5), PI)
	rig.call("set_view", 0.0, -0.6, 9.0)
	for level in LEVELS:
		_app().call("set_gfx", level)
		hall.call("refresh")
		var idle := OS.low_processor_usage_mode
		OS.low_processor_usage_mode = false   # draw every frame while measuring
		await _frames(4)
		var draws := 0
		var prims := 0
		for i in 4:
			await process_frame
			draws = maxi(draws, RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME))
			prims = maxi(prims, RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME))
		OS.low_processor_usage_mode = idle
		var c: Dictionary = world.call("counts")
		print("hall level %-4s draw calls %4d  primitives %7d  (flames %d, sides %d, static tris %d, space tris %d, stars %d, ships %d)" % [level, draws, prims,
			int(c["flames"]), int(c["sides"]), int(c["static_tris"]), int(c["space_tris"]), int(c["stars"]), int(c["ships"])])
		var b: Array = BUDGET[level]
		_check(draws <= int(b[0]) and prims <= int(b[1]), "%s: %d draw calls, %d primitives within %d / %d" % [level, draws, prims, int(b[0]), int(b[1])])
		var t: Array = SHIP_TARGET[level]
		_check(draws <= int(t[0]) and prims <= int(t[1]), "%s: within the deck target %d / %d too" % [level, int(t[0]), int(t[1])])
		# 0.3: the two vault candles light on hi/mid/lo (24 -> 26); min keeps its 12
		_check(int(c["flames"]) == (12 if level == "min" else 26), "%s: %d flames" % [level, int(c["flames"])])
		var dk: Array = DECK[level]
		_check(int(c["ships"]) == int(dk[0]) and bool(c["ship_drift"]) == bool(dk[1]) and bool(c["holo_flicker"]) == bool(dk[2]) and int(c["stars"]) == int(dk[3]),
			"%s: %d ships (drift %s), holo flicker %s, %d stars" % [level, int(c["ships"]), str(c["ship_drift"]), str(c["holo_flicker"]), int(c["stars"])])
		var ships := world.get_node("Ships") as GeometryInstance3D
		var space := world.get_node("Static/Space") as MeshInstance3D
		_check(ships.visible == (level != "min"), "%s: the distant ships are %s" % [level, "hidden" if level == "min" else "shown"])
		# review of 12 Nov: the shader moves the ships far from their instance points, so the culling box covers the dome
		if bool(dk[1]):
			var box := ships.custom_aabb
			var outside := 0
			for d in HallSpace.ship_instances(level):
				for at in [0.0, float(d["span"])]:
					if not box.has_point(HallSpace.ship_pos(d, at)):
						outside += 1
			_check(box.size.x > 0.0 and outside == 0, "%s: the drifting ships' culling box %s holds both ends of every drift" % [level, str(box)])
		# sign outlines cost one draw call per sign: only on hi/mid
		var with_outline := level == "hi" or level == "mid"
		var wrong := PackedStringArray()
		for l: Label3D in world.call("labels"):
			if (l.outline_size > 0) != with_outline:
				wrong.append("%s %d" % [l.name, l.outline_size])
		_check(wrong.is_empty(), "%s: sign outlines %s" % [level, "on" if with_outline else "off"], ", ".join(wrong))
		_check(space.visible and space.mesh != null and int(c["space_tris"]) > 0, "%s: the space behind the viewport is drawn (%d triangles)" % [level, int(c["space_tris"])])
		if level == "lo" or level == "min":
			var shaders := _shader_materials(world)
			_check(shaders.is_empty(), "%s: no ShaderMaterial under the hall (no TIME work)" % level, ", ".join(shaders))
		_save("hall_deck_%s.png" % level)
		var flicker := (world.get_node("Flames") as GeometryInstance3D).material_override is ShaderMaterial
		_check(flicker == (level == "hi" or level == "mid"), "%s: flames flicker only on hi/mid" % level)
		_check(bool(world.get("avatar").get("bob")) == (level == "hi" or level == "mid"), "%s: the avatar bobs only on hi/mid" % level)
		_check(OS.low_processor_usage_mode == (level == "lo" or level == "min"), "%s: low-processor mode follows the table's level" % level)
	# min: 10 idle frames, then nothing under the hall runs per frame
	_check(str(_app().get("gfx")) == "min", "the last level is min")
	await _frames(10)
	var probs := _idle_problems(hall)
	_check(probs.is_empty(), "min: after 10 idle frames nothing under the hall processes (avatar, camera, screen, stick)", ", ".join(probs))
	var arm := rig.get_node("Arm")
	_check(not arm.can_process(), "min: the camera's spring arm sleeps while idle")
	_save("hall_min.png")
	_app().call("set_gfx", "mid")
	hall.call("refresh")
	rig.call("set_view", 0.0, -0.45, 6.5)
	await _frames(2)


## Review of 12 Nov: the phone layout's worst view stays within the §2.6 budget and the deck target on every level:
## a 20:9 window (2400x1080 is 1600x720 logical), touch on (%Stick and the big prompt), the first-entry hint showing
## (it hides on the first step, but the camera can orbit before that), the avatar at the war table's ring, the camera
## looking across the deck towards either back corner (the most signs and HUD in view: about 40 draw calls before the
## stick's arcs lost their anti-aliasing and lo/min lost the sign outlines). Saves hall_touch_worst_<level>.png.
func _check_touch_budget(hall: Node) -> void:
	var world: Node3D = hall.get("world")
	var rig: Node3D = world.get("camera_rig")
	var hint := hall.get_node("%Hint") as CanvasItem
	var hint_visible := hint.visible
	var hint_modulate := hint.modulate
	var size0 := root.size
	_app().call("set_touch", "on")
	hall.call("refresh")
	await _resize(Vector2i(1600, 720))
	world.call("place_avatar", Vector3(0.0, 0.0, 0.85), PI)
	for level in LEVELS:
		_app().call("set_gfx", level)
		hall.call("refresh")
		hint.visible = true
		hint.modulate = Color.WHITE
		var idle := OS.low_processor_usage_mode
		OS.low_processor_usage_mode = false   # draw every frame while measuring
		var draws := 0
		var prims := 0
		for yaw in [PI * 1.75, PI * 1.25]:
			rig.call("set_view", yaw, -0.3, 9.0)
			await _frames(4)
			for i in 3:
				await process_frame
				draws = maxi(draws, RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME))
				prims = maxi(prims, RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME))
		rig.call("set_view", PI * 1.75, -0.3, 9.0)
		await _frames(3)
		_save("hall_touch_worst_%s.png" % level)
		OS.low_processor_usage_mode = idle
		print("hall touch worst view %-4s draw calls %4d  primitives %7d" % [level, draws, prims])
		var b: Array = BUDGET[level]
		var t: Array = SHIP_TARGET[level]
		_check(draws <= int(b[0]) and prims <= int(b[1]) and draws <= int(t[0]) and prims <= int(t[1]),
			"%s, phone layout worst view (20:9, touch, hint): %d draw calls, %d primitives within the deck target %d / %d" % [level, draws, prims, int(t[0]), int(t[1])])
	hint.visible = hint_visible
	hint.modulate = hint_modulate
	_app().call("set_gfx", "mid")
	_app().call("set_touch", "off")
	hall.call("refresh")
	await _resize(size0)
	rig.call("set_view", 0.0, -0.45, 6.5)
	await _frames(2)


# ---- no holes into the void ----

## SHIP_LOBBY_SPEC §9.3: with the background pure magenta, nothing of it may show: the vault closes the top, the reveals
## close the window sides and the space dome fills every window. 4 spots x 4 yaws x 2 pitches x 2 arms on mid, the
## widest half (arm 9) on min (fewer dome segments). Also saves hall_viewport.png (spawn, pitch -0.15) on mid.
func _check_void(hall: Node) -> void:
	var world: Node3D = hall.get("world")
	var rig: Node3D = world.get("camera_rig")
	var env: Environment = _camera(world).environment
	var bg := env.background_color
	world.call("place_avatar", HallLayout.SPAWN, PI)
	rig.call("set_view", 0.0, -0.15, 6.5)
	await _settle()
	await _frames(3)
	_save("hall_viewport.png")
	await _resize(VOID_SIZE)
	var hint := hall.get_node("%Hint") as CanvasItem
	var hint_was := hint.visible
	hint.visible = false
	env.background_color = MAGENTA
	for level in ["mid", "min"]:
		_app().call("set_gfx", level)
		hall.call("refresh")
		var idle := OS.low_processor_usage_mode
		OS.low_processor_usage_mode = false
		var bad := PackedStringArray()
		var n := 0
		for spot in VOID_SPOTS:
			world.call("place_avatar", spot, PI)
			await _physics(2)
			for yaw in [0.0, PI * 0.5, PI, PI * 1.5]:
				for pitch in [-0.15, -0.45]:
					for arm in [6.5, 9.0]:
						if level == "min" and arm < 9.0:
							continue
						rig.call("set_view", yaw, pitch, arm)
						await _physics(3)
						await _frames(3)
						n += 1
						var m := _magenta_pixels(root.get_viewport().get_texture().get_image())
						if m > 0:
							bad.append("%s yaw %d pitch %.2f arm %.1f: %d px" % [str(spot), int(round(rad_to_deg(yaw))), pitch, arm, m])
							if bad.size() == 1:
								_save("hall_void_%s.png" % level)
		OS.low_processor_usage_mode = idle
		_check(bad.is_empty(), "%s: no hole into the void in %d views (magenta background, %dx%d)" % [level, n, VOID_SIZE.x, VOID_SIZE.y], "\n".join(bad))
	env.background_color = bg
	_check(env.background_color == HallWorld.BG, "the hall's background colour is restored")
	hint.visible = hint_was
	_app().call("set_gfx", "mid")
	hall.call("refresh")
	await _resize(SIZES[0])
	world.call("place_avatar", HallLayout.SPAWN, PI)
	rig.call("set_view", 0.0, -0.45, 6.5)
	await _settle()


## Pixels that are still the magenta background (a hole); bilinear upscaling on min may blend an edge, so near-magenta
## counts too.
static func _magenta_pixels(img: Image) -> int:
	var n := 0
	for y in img.get_height():
		for x in img.get_width():
			var c := img.get_pixel(x, y)
			if c.r > 0.75 and c.b > 0.75 and c.g < 0.3:
				n += 1
	return n


## GeometryInstance3D nodes under the hall that carry a ShaderMaterial (override, overlay, surface override or mesh).
func _shader_materials(node: Node) -> PackedStringArray:
	var out := PackedStringArray()
	var stack: Array[Node] = [node]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		stack.append_array(n.get_children())
		if not n is GeometryInstance3D:
			continue
		var g := n as GeometryInstance3D
		var mats: Array = [g.material_override, g.material_overlay]
		if g is MeshInstance3D and (g as MeshInstance3D).mesh != null:
			var mi := g as MeshInstance3D
			for i in mi.mesh.get_surface_count():
				mats.append(mi.get_surface_override_material(i))
				mats.append(mi.mesh.surface_get_material(i))
		if g is MultiMeshInstance3D and (g as MultiMeshInstance3D).multimesh != null and (g as MultiMeshInstance3D).multimesh.mesh != null:
			var mm := (g as MultiMeshInstance3D).multimesh.mesh
			for i in mm.get_surface_count():
				mats.append(mm.surface_get_material(i))
		for m in mats:
			if m is ShaderMaterial:
				out.append(String(g.name))
				break
	return out


# ---- ways out ----

func _check_ways_out(hall: Node) -> void:
	var world: Node3D = hall.get("world")
	world.call("place_avatar", _front("exit"), PI)
	await _settle()
	await _press(KEY_E)
	var menu: Node = _app().call("current")
	_check(menu != null and menu.get_node_or_null("%PlayButton") != null and int(_app().call("depth")) == 1, "E at the exit door returns to the main menu")
	hall = await _enter(menu)
	if hall == null:
		return
	(hall.get_node("%MenuButton") as Button).pressed.emit()
	await _frames(3)
	_check(_app().call("current") == menu and int(_app().call("depth")) == 1, "the ‹ menu button returns to the main menu")
	hall = await _enter(menu)
	if hall == null:
		return
	await _press(KEY_ESCAPE)
	_check(_app().call("current") == menu and int(_app().call("depth")) == 1, "Esc in the hall returns to the main menu")


# ---- input helpers ----

## Holds the keys for n physics frames; returns the avatar's displacement.
func _hold(keys: Array, n: int) -> Vector3:
	var av := _avatar(_world())
	var p0 := av.global_position
	for k in keys:
		_key(k, true)
	await _physics(n)
	var d := av.global_position - p0
	for k in keys:
		_key(k, false)
	return Vector3(d.x, 0.0, d.z)


## Like _hold, but checks the avatar against every blocker on each physics frame; returns the first problem or "".
func _hold_tracking(keys: Array, n: int, av: Node3D) -> String:
	var worst := ""
	for k in keys:
		_key(k, true)
	for i in n:
		await physics_frame
		var p := av.global_position
		var hit := HallLayout.blocker_at(Vector2(p.x, p.z), HallLayout.AVATAR_R - 0.02)
		if hit != "" and worst == "":
			worst = "%s at %s" % [hit, str(p.snapped(Vector3.ONE * 0.001))]
	for k in keys:
		_key(k, false)
	return worst


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
	await _frames(3)


func _mouse_drag(button: MouseButton, rel: Vector2) -> void:
	var at := _to_window(root.get_visible_rect().get_center() + Vector2(0, 40))
	var b := InputEventMouseButton.new()
	b.button_index = button
	b.pressed = true
	b.position = at
	b.global_position = at
	Input.parse_input_event(b)
	var m := InputEventMouseMotion.new()
	m.position = at + rel
	m.global_position = at + rel
	m.relative = rel
	m.button_mask = MOUSE_BUTTON_MASK_RIGHT if button == MOUSE_BUTTON_RIGHT else MOUSE_BUTTON_MASK_LEFT
	Input.parse_input_event(m)
	var u := InputEventMouseButton.new()
	u.button_index = button
	u.pressed = false
	u.position = at + rel
	u.global_position = at + rel
	Input.parse_input_event(u)
	Input.flush_buffered_events()
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


## Canvas (logical) coordinates -> window pixels, the space Input.parse_input_event expects.
func _to_window(p: Vector2) -> Vector2:
	return root.get_final_transform() * p


## Waits until the avatar has eased to a stop (or 3 s of physics frames).
func _until_still(av: Node) -> void:
	for i in 180:
		if not av.is_physics_processing():
			break
		await physics_frame
	await _physics(2)


func _settle() -> void:
	await _physics(4)
	await _frames(1)


func _front(id: String) -> Vector3:
	var f: Vector2 = HallLayout.STATIONS[id]["front"]
	return Vector3(f.x, 0.0, f.y)


func _world() -> Node3D:
	var hall: Node = _app().call("current")
	return hall.get("world") if hall != null else null


func _avatar(world: Node3D) -> Node3D:
	return world.get("avatar")


func _camera(world: Node3D) -> Camera3D:
	return world.get("camera_rig").get("camera")


# ---- shared checks (as in test_menu_screens) ----

## Nodes under a screen that would run every frame: _process / _physics_process on, or a running Timer.
func _idle_problems(screen: Node) -> PackedStringArray:
	var out := PackedStringArray()
	var stack: Array[Node] = [screen]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n.is_processing() or n.is_physics_processing():
			out.append(String(n.name) + " processes")
		if n is Timer and not (n as Timer).is_stopped():
			out.append(String(n.name) + " timer runs")
		stack.append_array(n.get_children())
	return out


## Layout rules of LOBBY_SPEC §7.1 for every visible Control under the screen.
func _layout_problems(screen: Node) -> PackedStringArray:
	var out := PackedStringArray()
	var vis := root.get_visible_rect()
	_walk(screen, func(c: Control) -> void:
		var r := c.get_global_rect()
		if r.position.x < vis.position.x - 1.0 or r.position.y < vis.position.y - 1.0 or r.end.x > vis.end.x + 1.0 or r.end.y > vis.end.y + 1.0:
			out.append("%s outside the canvas %s" % [c.name, str(r)])
		var p := c.get_parent() as Control
		if p != null and not p is ScrollContainer:
			var pr := p.get_global_rect()
			if r.position.x < pr.position.x - 1.0 or r.position.y < pr.position.y - 1.0 or r.end.x > pr.end.x + 1.0 or r.end.y > pr.end.y + 1.0:
				out.append("%s outside its parent %s: %s in %s" % [c.name, p.name, str(r), str(pr)])
		if c is Button and (r.size.x < MIN_TARGET - 0.5 or r.size.y < MIN_TARGET - 0.5):
			out.append("%s smaller than 44x44 %s" % [c.name, str(r.size)])
		var buttons: Array[Control] = []
		for s in c.get_children():
			if s is Button and (s as Control).is_visible_in_tree():
				buttons.append(s)
		for i in buttons.size():
			for j in range(i + 1, buttons.size()):
				if buttons[i].get_global_rect().intersection(buttons[j].get_global_rect()).get_area() > 1.0:
					out.append("%s overlaps %s" % [buttons[i].name, buttons[j].name]))
	return out


func _walk(node: Node, f: Callable) -> void:
	if node is CanvasItem and not (node as CanvasItem).is_visible_in_tree():
		return
	if node is Control:
		f.call(node)
	for c in node.get_children():
		_walk(c, f)


## Every visible text (Label, Button, OptionButton items, LineEdit placeholder, tooltip, Label3D) still in Thai.
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
		if node is OptionButton:
			for i in (node as OptionButton).item_count:
				texts.append((node as OptionButton).get_item_text(i))
		if node is LineEdit:
			texts.append((node as LineEdit).placeholder_text)
		if node is Label3D:
			texts.append((node as Label3D).text)
		if node is Control and (node as Control).tooltip_text != "":
			texts.append((node as Control).tooltip_text)
		for t in texts:
			if _thai_re.search(t) != null:
				out.append(String(node.name) + ": " + t.left(60))
	for c in node.get_children():
		_scan(c, exempt, out)


func _machine_settings() -> String:
	var p := "user://settings.cfg"
	return "%d:%s" % [FileAccess.get_modified_time(p), FileAccess.get_file_as_string(p)] if FileAccess.file_exists(p) else "none"


func _resize(sz: Vector2i) -> void:
	root.size = sz
	await _frames(SETTLE)


func _suffix(sz: Vector2i) -> String:
	return "" if sz == SIZES[0] else "_%dx%d" % [sz.x, sz.y]


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
	_check(_mean_luma(img) > 0.02, name + " is not black")


func _finish() -> void:
	for k in [KEY_W, KEY_A, KEY_S, KEY_D, KEY_SHIFT, KEY_UP]:
		_key(k, false)
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


static func _mean_luma(img: Image) -> float:
	var sum := 0.0
	var n := 0
	var size := img.get_size()
	var x := 7
	while x < size.x:
		var y := 5
		while y < size.y:
			sum += img.get_pixel(x, y).get_luminance()
			n += 1
			y += 29
		x += 31
	return sum / maxf(n, 1)
