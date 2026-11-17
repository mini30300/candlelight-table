extends SceneTree
## Campaign missions on screen (CAMPAIGN_SPEC §4, §7 track C) inside scenes/main.tscn with a battle-table kit as the
## dressing-room figure (Figures.select, test settings file). Per level (hi/mid/lo/min):
##  - the mission overview (a catastrophe horde purge: the first wave is capped; player at the spawn looking down the
##    field) within §4 (90/150k, 70/100k, 50/60k, 40/40k), alive enemies <= MissionTypes.ALIVE_CAP, skinned figures <= cap
##    (24/16/10/8), the static field in 2 meshes;
##  - the phone worst view (20:9, touch on, rescue with three hostages following, firing, damage numbers, enemies winding
##    up next to the player, a toast) within §4 (100/150k, 80/100k, 55/60k, 45/40k);
##  - no shader using TIME under the mission on lo/min, the telegraph shader absent on min (counts().telegraph_shader);
##  - paused: after the toast and the numbers end nothing under the mission screen processes and no timer runs;
##  - min: figures farther than 25 m hold a still pose (their figure node does not process).
## Plus one PNG per biome (mid, desktop) and the overview / phone views per level; the HUD in English has no Thai.
## Run:
##   timeout 900 nice -n 10 xvfb-run -a -s "-screen 0 1280x720x24" <godot> --path godot --rendering-driver opengl3 \
##       --resolution 1280x720 --audio-driver Dummy -s tests/render/test_mission.gd
## TEST_OUT (an absolute folder) in the environment replaces tests/out. Exit code 1 on any failure.

const SCENE := "res://scenes/main.tscn"
const MISSION := "res://ui/screens/mission_screen.tscn"
const DEFAULT_OUT_DIR := "res://tests/out"
const SETTINGS_FILE := "user://test_mission.cfg"
const Specs := preload("res://tests/fixtures/campaign_missions/specs.gd")
const LEVELS: PackedStringArray = ["hi", "mid", "lo", "min"]
const DESKTOP := Vector2i(1280, 720)
const PHONE := Vector2i(1600, 720)
const OVERVIEW := {"hi": [90, 150000], "mid": [70, 100000], "lo": [50, 60000], "min": [40, 40000]}
const WORST := {"hi": [100, 150000], "mid": [80, 100000], "lo": [55, 60000], "min": [45, 40000]}
const SKINNED := {"hi": 24, "mid": 16, "lo": 10, "min": 8}
const BIOMES: PackedStringArray = ["ruin", "forest", "desert", "ice", "volcanic", "toxic"]
const FACTIONS := {"ruin": "traitors", "forest": "orcs", "desert": "tomb", "ice": "machines", "volcanic": "daemons", "toxic": "swarm"}

var _out_dir := DEFAULT_OUT_DIR
var _main: Node
var _started := false
var _done := false
var _passed := 0
var _failed := 0
var _thai_re := RegEx.create_from_string("[฀-๿]")


func _initialize() -> void:
	var env := OS.get_environment("TEST_OUT")
	if env != "" and env.is_absolute_path():
		_out_dir = env
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SETTINGS_FILE))
	var app := _app()
	app.set("settings_file", SETTINGS_FILE)
	app.call("set_lang", "th")
	app.call("set_gfx", "mid")
	app.call("set_touch", "off")
	Figures.select("kit_kblade", "blue")
	var scene: PackedScene = load(SCENE)
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
	for level in LEVELS:
		await _overview(level)
		await _phone_worst(level)
	await _biomes()
	await _english_and_idle()
	_finish()


func _open(spec: Dictionary, level: String, touch: bool, size: Vector2i):
	_app().call("set_gfx", level)
	_app().call("set_touch", "on" if touch else "off")
	root.size = size
	var ms = _app().call("push", load(MISSION))
	ms.start(spec)
	for i in 600:
		if ms.playing():
			break
		await process_frame
	return ms


func _close(ms) -> void:
	if _app().call("current") == ms:
		_app().call("pop")
	await _frames(3)


## Camera at the player's shoulder: yaw 0 looks down the field (-z).
func _look(w, foot: Vector3, yaw: float, pitch: float) -> void:
	w.place_player(foot, yaw)
	var rig: Node3D = w.player.call("camera_rig")
	rig.call("set_view", yaw, pitch, 3.0)
	await _physics(4)
	await _frames(3)


func _overview(level: String) -> void:
	var spec := Specs.make("purge", {"seed": 4040, "biome": "forest", "faction": "orcs", "modifier": "horde", "difficulty": "catastrophe"})
	var ms = await _open(spec, level, false, DESKTOP)
	var w = ms.world()
	w.test_god = true
	w.simulate(6.0)
	var cap := MissionTypes.alive_cap(level)
	var c: Dictionary = w.counts()
	_check(int(c["alive"]) == cap and int(c["queue"]) > 0, "%s: the horde's first wave is capped at %d alive (queue %d)" % [level, cap, int(c["queue"])])
	# pull the living enemies into a loose arc in front of the player so all are in view
	var es: Array = w.enemies()
	var foot: Vector3 = w.layout["player_spawn"]
	for i in es.size():
		var a := -0.9 + 1.8 * float(i) / maxf(float(es.size() - 1), 1.0)
		es[i].global_position = foot + Vector3(sin(a) * 9.0, 0.0, -cos(a) * 9.0 - 3.0)
	await _look(w, foot, 0.0, -0.12)
	var m := await _measure()
	c = w.counts()
	print("mission overview %-4s draw calls %4d  primitives %7d  %s" % [level, m.x, m.y, str(c)])
	var t: Array = OVERVIEW[level]
	_check(m.x <= int(t[0]) and m.y <= int(t[1]), "%s: mission overview %d draws, %d primitives within %d / %d" % [level, m.x, m.y, int(t[0]), int(t[1])])
	_check(int(c["skinned"]) <= int(SKINNED[level]), "%s: skinned figures %d <= %d" % [level, int(c["skinned"]), int(SKINNED[level])])
	_check(int(c["static_meshes"]) == 2, "%s: the field is 2 static meshes (%d tris)" % [level, int(c["static_tris"])])
	if level == "lo" or level == "min":
		var ts := _time_shaders(ms)
		_check(ts.is_empty(), "%s: no shader using TIME under the mission" % level, str(ts))
	_save("mission_%s.png" % level)
	# keep killing for a while: the cap holds as waves top up
	var worst := 0
	for k in 20:
		var alive: Array = w.enemies()
		if not alive.is_empty():
			alive[0].take_hit({"amount": 99999, "kind": &"gun"})
		w.simulate(0.5)
		worst = maxi(worst, int(w.counts()["alive"]))
	_check(worst <= cap, "%s: waves top up but never above the cap (max %d)" % [level, worst])
	if level == "min":
		# figures beyond 25 m hold a still pose
		var far := 0
		var far_still := 0
		var cam_p: Vector3 = w.camera().global_position
		w.simulate(0.6)
		for e in w.enemies():
			if Vector2(e.global_position.x - cam_p.x, e.global_position.z - cam_p.z).length() > 27.0:
				far += 1
				if e.figure().process_mode == Node.PROCESS_MODE_DISABLED:
					far_still += 1
		_check(far == far_still, "min: %d of %d far figures hold a still pose" % [far_still, far])
	await _close(ms)


func _phone_worst(level: String) -> void:
	var spec := Specs.make("rescue", {"seed": 5150, "biome": "ruin", "faction": "traitors", "secondary": ["purge"]})
	var ms = await _open(spec, level, true, PHONE)
	var w = ms.world()
	w.test_god = true
	var foot := Vector3(0.0, 0.0, 6.0)
	for h in w.hostages():
		w.obj.free_hostage(h.index)
		h.set_freed()
	# walk a little so the hostages line up behind
	for k in 12:
		w.place_player(foot + Vector3(0.0, 0.0, 6.0 - k * 0.5), 0.0)
		w.simulate(0.2)
	for h in w.hostages():
		h.position = foot + Vector3(-1.0 + h.index, 0.0, 2.0 + h.index * 0.8)
	w.simulate(3.0)
	var es: Array = w.enemies()
	for i in es.size():
		es[i].global_position = foot + Vector3(-3.0 + i * 1.2, 0.0, -2.2 - (i % 2) * 1.5)
	w.simulate(0.4)
	ms.show_toast(ms.TOASTS["freed"])
	await _look(w, foot, 0.0, -0.15)
	w.player.call("press", &"fire", true)
	await _physics(10)
	var m := await _measure()
	w.player.call("press", &"fire", false)
	var c: Dictionary = w.counts()
	var tele := 0
	for e in w.enemies():
		if e.telegraph_visible():
			tele += 1
	print("mission phone worst %-4s draw calls %4d  primitives %7d  telegraphs %d  %s" % [level, m.x, m.y, tele, str(c)])
	var t: Array = WORST[level]
	_check(m.x <= int(t[0]) and m.y <= int(t[1]), "%s: phone worst view %d draws, %d primitives within %d / %d" % [level, m.x, m.y, int(t[0]), int(t[1])])
	_check(int(c["skinned"]) <= int(SKINNED[level]), "%s: phone view skinned figures %d <= %d" % [level, int(c["skinned"]), int(SKINNED[level])])
	_check(int(c["alive"]) <= int(w.alive_cap()) and int(w.alive_cap()) <= MissionTypes.alive_cap(level),
		"%s: with three hostages on screen the alive cap shrinks to %d" % [level, int(w.alive_cap())])
	if level == "min":
		_check(not bool(c["telegraph_shader"]), "min: no telegraph shader (flat red only)")
	else:
		_check(bool(c["telegraph_shader"]), "%s: the telegraph shader" % level)
	_save("mission_phone_worst_%s.png" % level)
	await _close(ms)


func _biomes() -> void:
	for b in BIOMES:
		var t: String = ["purge", "defend", "rescue", "destroy_camp"][BIOMES.find(b) % 4]
		var spec := Specs.make(t, {"seed": 777 + BIOMES.find(b), "biome": b, "faction": FACTIONS[b], "secondary": ["defend"] if t != "defend" else []})
		var ms = await _open(spec, "mid", false, DESKTOP)
		var w = ms.world()
		w.test_god = true
		w.simulate(5.0)
		var foot: Vector3 = w.layout["player_spawn"]
		var look_at: Vector3 = w.layout["points"]["camp"] if t == "destroy_camp" else (w.layout["points"]["base"] if t == "defend" else Vector3(0, 0, -8))
		var es: Array = w.enemies()
		for i in es.size():
			es[i].global_position = foot.lerp(look_at, 0.55) + Vector3(-4.0 + i * 1.6, 0.0, (i % 3) * 1.2)
		w.simulate(0.3)
		var d := look_at - foot
		await _look(w, foot, atan2(-d.x, -d.z), -0.16)
		await _frames(4)
		_save("mission_biome_%s.png" % b)
		await _close(ms)


func _english_and_idle() -> void:
	_app().call("set_lang", "en")
	var spec := Specs.make("destroy_camp", {"seed": 99, "biome": "volcanic", "faction": "machines", "secondary": ["defend", "rescue"]})
	var ms = await _open(spec, "min", false, DESKTOP)
	var w = ms.world()
	await _frames(3)
	var texts := PackedStringArray(ms.mhud.panel_lines())
	texts.append(ms.pause_button.text)
	_check(_thai_re.search(" ".join(texts)) == null, "English: the mission HUD has no Thai (%s)" % " | ".join(texts))
	_save("mission_hud_en.png")
	ms.open_pause()
	for i in 200:
		await process_frame
	var p := _idle_problems(ms)
	_check(p.is_empty(), "paused: nothing under the mission screen processes", str(p))
	_save("mission_pause_en.png")
	_app().call("set_lang", "th")
	ms.close_pause()
	await _close(ms)


func _measure() -> Vector2i:
	var idle := OS.low_processor_usage_mode
	OS.low_processor_usage_mode = false
	await _frames(3)
	var draws := 0
	var prims := 0
	for i in 4:
		await process_frame
		draws = maxi(draws, RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME))
		prims = maxi(prims, RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME))
	OS.low_processor_usage_mode = idle
	return Vector2i(draws, prims)


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


func _save(name: String) -> void:
	var img := root.get_viewport().get_texture().get_image()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_out_dir))
	var path := _out_dir + "/" + name
	var err := img.save_png(path)
	_check(err == OK, "saved " + ProjectSettings.globalize_path(path) + " " + str(img.get_size()))


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _physics(n: int) -> void:
	for i in n:
		await physics_frame


func _app() -> Node:
	return root.get_node(^"App")


func _finish() -> void:
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
