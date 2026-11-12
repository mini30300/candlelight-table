extends SceneTree
## Every station of the warship deck (SHIP_LOBBY_SPEC §2.2, §9) is reachable on foot from the spawn, with the real
## colliders, headless: main menu → เล่นกับบอท → the lobby; for each of the seven stations the avatar starts at the spawn
## and the on-screen stick steers it along a free path (grid search over HallLayout with the avatar's radius) until the
## station's prompt shows; on the way the avatar never enters a blocker (HallLayout.blocker_at). Then the treasure chest
## (vault, the future random rewards): its prompt in Thai and English, E opens the one-line coming-soon panel and stays
## in the lobby, Esc closes the panel first, a second Esc returns to the main menu. Graphics level min, test settings
## file (never this machine's settings.cfg). Run:
##   timeout 600 <godot> --headless --path godot --audio-driver Dummy -s tests/flow/test_hall_reach.gd
## Exit code 1 on any failure; the last line is PASS or FAIL.

const SCENE := "res://scenes/main.tscn"
const SETTINGS_FILE := "user://test_hall_reach.cfg"
const GRID := 0.25
const PAD := 0.12           # the path keeps this much more than the avatar's radius from every blocker
const STICK := 0.84         # just under the run threshold (0.85): walk
const TICK_CAP := 1500      # physics frames per station (25 s)
const NEAR := 0.3           # a waypoint counts as reached this close

var _main: Node
var _started := false
var _done := false
var _passed := 0
var _failed := 0


func _initialize() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SETTINGS_FILE))
	var app := _app()
	app.set("settings_file", SETTINGS_FILE)   # never write this machine's settings.cfg from a test
	app.call("set_gfx", "min")
	app.call("set_lang", "th")
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


func _process(_delta: float) -> bool:
	if not _started:
		_started = true
		_run()
	return _done


func _run() -> void:
	await _frames(3)
	var menu: Node = _app().call("current")
	_check(menu != null and menu.get_node_or_null("%PlayButton") != null, "main.tscn opens the main menu")
	if menu == null or menu.get_node_or_null("%PlayButton") == null:
		_finish()
		return
	menu.get_node("%PlayButton").pressed.emit()
	await _frames(3)
	var hall: Node = _app().call("current")
	_check(hall != null and hall.has_method("station") and hall.get("world") != null, "เล่นกับบอท opens the lobby")
	if hall == null or not hall.has_method("station") or hall.get("world") == null:
		_finish()
		return
	var world: Node3D = hall.get("world")
	var names: Dictionary = (hall.get_script() as Script).get_script_constant_map()["NAMES"]
	var use: Button = hall.get_node("%UseButton")
	_check(HallLayout.IDS.size() == 7 and HallLayout.IDS.has("vault"), "seven stations, the vault included")
	for id in HallLayout.IDS:
		var t0 := Time.get_ticks_msec()
		var res := await _walk_to(world, hall, id)
		var p: Vector3 = (world.get("avatar") as Node3D).global_position
		_check(str(hall.call("station")) == id, "from the spawn the avatar walks to %s (%s, %.1f m of path, %d ms)" % [id, _xz(p), float(res["len"]), Time.get_ticks_msec() - t0], str(res["why"]))
		_check(str(res["inside"]) == "", "on the way to %s the avatar never enters a blocker" % id, str(res["inside"]))
		var want := str(root.get_node(^"I18n").call("t", str(names[id])))
		_check(use.visible and use.text.contains(want), "at %s the prompt names it: %s" % [id, use.text])
	await _check_vault(world, hall)
	_finish()


## Walks from the spawn to the station's front ring along a free grid path; returns {len, inside, why}.
func _walk_to(world: Node3D, hall: Node, id: String) -> Dictionary:
	var av := world.get("avatar") as Node3D
	var rig: Node3D = world.get("camera_rig")
	rig.call("set_view", 0.0, -0.45, 6.5)
	world.call("place_avatar", HallLayout.SPAWN, PI)
	await _physics(4)
	var goal: Vector2 = HallLayout.STATIONS[id]["front"]
	var path := _path(HallLayout.spawn_xz(), goal)
	var out := {"len": 0.0, "inside": "", "why": ""}
	if path.is_empty():
		out["why"] = "no free path on the grid"
		return out
	for i in range(1, path.size()):
		out["len"] = float(out["len"]) + path[i - 1].distance_to(path[i])
	var k := 0
	var ticks := 0
	while str(hall.call("station")) != id and ticks < TICK_CAP:
		var p := Vector2(av.global_position.x, av.global_position.z)
		# skip ahead to the farthest waypoint in a straight free line, then drop the ones already passed
		var far := k
		for j in range(k + 1, mini(k + 24, path.size())):
			if _line_free(p, path[j]):
				far = j
		k = far
		while k < path.size() - 1 and p.distance_to(path[k]) < NEAR:
			k += 1
		var d := path[k] - p
		var dir := Vector3(d.x, 0.0, d.y).normalized() if d.length() > 0.01 else Vector3.ZERO
		var right: Vector3 = rig.call("right_flat")
		var fwd: Vector3 = rig.call("forward_flat")
		world.call("set_stick", Vector2(dir.dot(right), dir.dot(fwd)) * STICK)
		await physics_frame
		ticks += 1
		var q := av.global_position
		var hit := HallLayout.blocker_at(Vector2(q.x, q.z), HallLayout.AVATAR_R - 0.02)
		if hit != "" and str(out["inside"]) == "":
			out["inside"] = "%s at %s" % [hit, _xz(q)]
	world.call("set_stick", Vector2.ZERO)
	for i in 180:
		if not av.is_physics_processing():
			break
		await physics_frame
	if str(hall.call("station")) != id:
		out["why"] = "stopped at %s after %d ticks (waypoint %d of %d)" % [_xz(av.global_position), ticks, k, path.size()]
	return out


## The treasure chest: prompt in Thai and English, E → coming-soon panel (stays), Esc closes it, Esc again → main menu.
func _check_vault(world: Node3D, hall: Node) -> void:
	var soon: Control = hall.get_node("%SoonPanel")
	var label: Label = hall.get_node("%SoonLabel")
	var use: Button = hall.get_node("%UseButton")
	for lang in ["th", "en"]:
		_app().call("set_lang", lang)
		hall.call("refresh")
		world.call("place_avatar", Vector3(3.15, 0.0, 4.0), -PI * 0.5)
		await _physics(4)
		await _frames(2)
		var prompt := "หีบสมบัติ · กด E" if lang == "th" else "Treasure Chest · press E"
		_check(str(hall.call("station")) == "vault" and use.visible and use.text == prompt, "%s: the chest's prompt is %s" % [lang, use.text])
		await _press(KEY_E)
		var line := "หีบสมบัติ — เร็วๆ นี้: สุ่มรับชิ้นส่วนปืนและของตกแต่ง" if lang == "th" else "Treasure chest — coming soon: win random gun parts and decorations"
		_check(soon.visible and label.text == line and _app().call("current") == hall and int(_app().call("depth")) == 2,
			"%s: E at the chest shows the coming-soon panel and stays in the lobby (%s)" % [lang, label.text])
		await _press(KEY_ESCAPE)
		_check(not soon.visible and _app().call("current") == hall, "%s: Esc closes the chest's panel first" % lang)
	_app().call("set_lang", "th")
	hall.call("refresh")
	await _press(KEY_ESCAPE)
	var menu: Node = _app().call("current")
	_check(menu != hall and menu != null and menu.get_node_or_null("%PlayButton") != null and int(_app().call("depth")) == 1,
		"a second Esc returns to the main menu")


## Shortest 8-way path on the GRID from a to b through cells where the avatar (plus PAD) fits; corners are not cut.
## Returns the cell centres from a to b (a and b themselves at the ends), or [] if b cannot be reached.
func _path(a: Vector2, b: Vector2) -> PackedVector2Array:
	var nx := int(HallLayout.HALF.x * 2.0 / GRID)
	var nz := int(HallLayout.HALF.y * 2.0 / GRID)
	var free := PackedByteArray()
	free.resize(nx * nz)
	for k in nz:
		for i in nx:
			free[k * nx + i] = 0 if HallLayout.blocked(_cell(i, k), HallLayout.AVATAR_R + PAD) else 1
	var s := _index(a, nx)
	# the goal cell: the free cell nearest to b (b itself may sit closer than PAD to its station)
	var g := -1
	var best := INF
	for c in free.size():
		var dd := _cell(c % nx, c / nx).distance_to(b)
		if free[c] == 1 and dd < best:
			best = dd
			g = c
	if g == -1 or best > 0.6 or free[s] == 0:
		return PackedVector2Array()
	var prev := PackedInt32Array()
	prev.resize(nx * nz)
	prev.fill(-1)
	prev[s] = s
	var queue := PackedInt32Array([s])
	var head := 0
	while head < queue.size() and prev[g] == -1:
		var c := queue[head]
		head += 1
		var ci := c % nx
		var ck := c / nx
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1)]:
			var ii: int = ci + d.x
			var kk: int = ck + d.y
			if ii < 0 or kk < 0 or ii >= nx or kk >= nz:
				continue
			var n := kk * nx + ii
			if free[n] == 0 or prev[n] != -1:
				continue
			if d.x != 0 and d.y != 0 and (free[ck * nx + ii] == 0 or free[kk * nx + ci] == 0):
				continue
			prev[n] = c
			queue.append(n)
	if prev[g] == -1:
		return PackedVector2Array()
	var rev := PackedVector2Array([b])
	var c2 := prev[g]
	while c2 != s:
		rev.append(_cell(c2 % nx, c2 / nx))
		c2 = prev[c2]
	rev.append(a)
	rev.reverse()
	return rev


func _line_free(a: Vector2, b: Vector2) -> bool:
	var n := maxi(int(a.distance_to(b) / 0.1), 1)
	for i in n + 1:
		if HallLayout.blocked(a.lerp(b, float(i) / n), HallLayout.AVATAR_R + PAD * 0.5):
			return false
	return true


func _cell(i: int, k: int) -> Vector2:
	return Vector2(-HallLayout.HALF.x + (i + 0.5) * GRID, -HallLayout.HALF.y + (k + 0.5) * GRID)


func _index(p: Vector2, nx: int) -> int:
	var i := clampi(int((p.x + HallLayout.HALF.x) / GRID), 0, nx - 1)
	var k := clampi(int((p.y + HallLayout.HALF.y) / GRID), 0, int(HallLayout.HALF.y * 2.0 / GRID) - 1)
	return k * nx + i


func _press(code: Key) -> void:
	_key(code, true)
	await _frames(1)
	_key(code, false)
	await _frames(3)


func _key(code: Key, pressed: bool) -> void:
	var ev := InputEventKey.new()
	ev.keycode = code
	ev.physical_keycode = code
	ev.pressed = pressed
	Input.parse_input_event(ev)
	Input.flush_buffered_events()


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _physics(n: int) -> void:
	for i in n:
		await physics_frame


func _app() -> Node:
	return root.get_node(^"App")


static func _xz(p: Vector3) -> String:
	return "(%.2f, %.2f)" % [p.x, p.z]


func _finish() -> void:
	var app := _app()
	app.call("set_lang", "th")
	app.call("set_touch", "auto")
	app.set("settings_file", str(app.get("SETTINGS_PATH")))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SETTINGS_FILE))
	print("%s  %d passed, %d failed" % ["PASS " if _failed == 0 and _passed > 0 else "FAIL ", _passed, _failed])
	_done = true
	quit(0 if _failed == 0 and _passed > 0 else 1)


func _check(cond: bool, msg: String, detail: String = "") -> void:
	if cond:
		_passed += 1
		print("ok    " + msg)
	else:
		_failed += 1
		print("FAIL  " + msg + ("" if detail == "" else " " + detail.left(1500)))
