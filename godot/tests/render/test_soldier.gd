extends SceneTree
## The infantry soldier preview in the real game (scenes/main.tscn), under xvfb. The dressing room's choice
## (Figures.select "soldier") reaches the deck walker, the arena player, a campaign mission's player and the "normal" hero
## card. Checks:
##  - alone, per level (hi/mid/lo/min): one draw call and the level's triangles within the soldier budget
##    (SoldierFigure.BUDGET); a strip of the four levels is saved;
##  - foot slide <= 15 mm while planted, walking and running at the deck speeds and the arena speeds (the figure's own
##    playback-rate rule), and the measure has teeth (moving 10 % too slow slides well past the gate);
##  - the deck: the avatar becomes the soldier (egg hidden, deck speeds), W walks and Shift+W runs at the matching clip
##    rate, releasing stops processing; every level within the deck targets with no more draw calls than the egg; standing
##    on lo and on min the soldier holds a still pose, and on min nothing under the deck processes;
##  - the arena: the player is the soldier (A/D turn, no strafe), the overview within ARENA_SPEC §11.2 on every level, a
##    shot leaves a tracer from a muzzle by the hands, D turns without sliding, on min nothing processes and it is still;
##  - a campaign mission at hi and min: the player is the soldier, the overview within CAMPAIGN_SPEC §4;
##  - the campaign's "normal" hero card shows the soldier on every level within §4 with head and chest in the frame; the
##    card's clock moves it on hi/mid, and on lo/min (drawn once) its animation player does not advance;
##  - the other bodies (Figures "soldier_m2", "soldier_m3", "soldier_f1", "soldier_f2"): foot slide <= 15 mm at that
##    body's own deck speeds and at the arena speeds with its own S; on the deck at hi and min the avatar is that body,
##    takes its deck speeds and stays within the deck targets; the arena player is that body and the overview at hi
##    stays within §11.2; the "normal" hero card at hi and min shows that body lit, head and chest in the frame;
##  - English mode: the dressing room names it "Infantry (preview)" and the four other bodies by their English names,
##    and shows no Thai; the deck and the arena HUD show no Thai with the soldier or with a woman's body (f1).
## PNGs (TEST_OUT, default tests/out): soldier_levels.png, soldier_deck_<level>.png, soldier_arena_<level>.png,
## soldier_arena_front_<level>.png, soldier_mission_<level>.png, soldier_hero_<level>.png, soldier_dressing_en.png,
## soldier_<body>_deck_<hi|min>.png, soldier_<body>_hero_<hi|min>.png, soldier_<body>_arena_hi.png. Run:
##   timeout 900 xvfb-run -a -s "-screen 0 1280x720x24" <godot> --path godot --rendering-driver opengl3 \
##       --resolution 1280x720 --audio-driver Dummy -s tests/render/test_soldier.gd

const SCENE := "res://scenes/main.tscn"
const ARENA_SCREEN := "res://ui/screens/arena_screen.tscn"
const MISSION := "res://ui/screens/mission_screen.tscn"
const DRESSING := "res://ui/screens/dressing_screen.tscn"
const SCRIPT := "res://scenes/arena/soldier_figure.gd"
const DEFAULT_OUT_DIR := "res://tests/out"
const SETTINGS_FILE := "user://test_soldier_render.cfg"
const FAKE_NET := "res://tests/unit/fixtures/fake_net.gd"
const NONE_LIST := "res://tests/unit/fixtures/no_such_pack/figures.json"
const NONE_PACK := "res://tests/unit/fixtures/no_such_pack/pack.json"
const Specs := preload("res://tests/fixtures/campaign_missions/specs.gd")
const LEVELS: PackedStringArray = ["hi", "mid", "lo", "min"]
const SHIP_TARGET := {"hi": [40, 60000], "mid": [40, 50000], "lo": [35, 40000], "min": [30, 30000]}
const ARENA_OVERVIEW := {"hi": [50, 80000], "mid": [45, 60000], "lo": [35, 40000], "min": [30, 30000]}
const MISSION_OVERVIEW := {"hi": [90, 150000], "mid": [70, 100000], "lo": [50, 60000], "min": [40, 40000]}
const HERO_BUDGET := {"hi": [60, 80000], "mid": [45, 60000], "lo": [30, 35000], "min": [30, 35000]}
const HERO_SCALE := {"hi": 1.0, "mid": 0.75, "lo": 0.5, "min": 0.5}
const MAX_SLIDE_MM := 15.0
const RATE := 240.0
const WALK_TICKS := 45
const CELL := Vector2i(300, 520)
## ร่างอื่น: id ในห้องแต่งตัว -> [body id, ชื่ออังกฤษ]
const BODIES := {"soldier_m2": ["m2", "Infantry man 2 (preview)"], "soldier_m3": ["m3", "Infantry man 3 (preview)"],
	"soldier_f1": ["f1", "Infantry woman 1 (preview)"], "soldier_f2": ["f2", "Infantry woman 2 (preview)"]}

var _out_dir := DEFAULT_OUT_DIR
var _main: Node
var _started := false
var _done := false
var _passed := 0
var _failed := 0
var _thai_re := RegEx.create_from_string("[฀-๿]")
var _fake: Node
var _real_net: Node
var S: GDScript


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
	Figures.store_path = SETTINGS_FILE
	Figures.pack_list = NONE_LIST
	Figures.pack_manifest = NONE_PACK
	S = load(SCRIPT)
	_real_net = root.get_node_or_null(^"Net")
	if _real_net != null:
		_real_net.name = "NetReal"
	_fake = (load(FAKE_NET) as GDScript).new()
	_fake.name = "Net"
	root.add_child(_fake)
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
	_check(Figures.entry("soldier").get("kind", "") == "builtin", "the soldier is in the dressing room's list")
	await _alone()
	_footslide()
	await _deck()
	await _arena()
	await _mission()
	await _hero()
	await _bodies()
	await _english()
	_finish()


# ---- alone: one draw per level, triangles within the budget ----

func _alone() -> void:
	var strip := Image.create(CELL.x * LEVELS.size(), CELL.y, false, Image.FORMAT_RGBA8)
	var budget: Dictionary = S.get("BUDGET")
	for i in LEVELS.size():
		var lv := LEVELS[i]
		var vp := SubViewport.new()
		vp.size = CELL
		vp.own_world_3d = true
		vp.msaa_3d = Viewport.MSAA_DISABLED
		vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		vp.transparent_bg = false
		root.add_child(vp)
		var fig: Node3D = S.new()
		vp.add_child(fig)
		fig.call("setup", {"role": &"player", "level": lv, "seed": 0})
		fig.rotation.y = 0.45
		var cam := Camera3D.new()
		cam.fov = 30.0
		vp.add_child(cam)
		cam.current = true
		cam.transform = Transform3D(Basis.looking_at(Vector3(0, 0.93, 0) - Vector3(0, 1.2, 4.2), Vector3.UP), Vector3(0, 1.2, 4.2))
		var m := await _measure_vp(vp)
		var tris := ((S.call("body_mesh", lv) as ArrayMesh).surface_get_arrays(0)[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
		print("soldier alone %-4s draw calls %d  primitives %d  (mesh %d tris)" % [lv, m[0], m[1], tris])
		_check(m[0] == 1, "%s: the soldier is one draw call" % lv, str(m))
		_check(m[1] <= int(budget[lv]) and m[1] >= tris, "%s: %d primitives within the %d-triangle budget" % [lv, m[1], int(budget[lv])])
		await RenderingServer.frame_post_draw
		strip.blit_rect(vp.get_texture().get_image(), Rect2i(Vector2i.ZERO, CELL), Vector2i(i * CELL.x, 0))
		vp.queue_free()
		await _frames(1)
	_save_img(strip, "soldier_levels.png")


# ---- foot slide (manual clock, the figure's own rate rule) ----

func _footslide() -> void:
	var fig: Node3D = S.new()
	root.add_child(fig)
	fig.call("set_manual", true)
	fig.call("setup", {"role": &"deck", "level": "mid", "seed": 0})
	var deck: Vector2 = fig.call("deck_speeds")
	fig.queue_free()
	for c in [["deck walk", deck.x, false], ["deck run", deck.y, true], ["arena walk", float(ArenaData.PLAYER["walk"]), false],
			["arena run", float(ArenaData.PLAYER["run"]), true]]:
		var r := _slide(float(c[1]), bool(c[2]), 1.0)
		_check(float(r["mm"]) <= MAX_SLIDE_MM and int(r["plants"]) > 2,
			"%s at %.2f m/s: foot slide %.2f mm while planted (%d plants) <= %.0f mm" % [c[0], c[1], r["mm"], r["plants"], MAX_SLIDE_MM], str(r))
	var ctl := _slide(float(ArenaData.PLAYER["walk"]), false, 0.9)
	_check(float(ctl["mm"]) > 3.0 * MAX_SLIDE_MM, "control: moving 10 %% too slow slides %.1f mm (the measure has teeth)" % ctl["mm"])


## {mm, plants}: the soldier (body: "" = the base) walks at `speed` (set_move) for 3 s at 240 samples/s while its root
## moves speed × k
func _slide(speed: float, running: bool, k: float, body := "") -> Dictionary:
	var fig: Node3D = S.new()
	root.add_child(fig)
	fig.call("set_manual", true)
	fig.call("setup", {"role": &"player", "level": "mid", "seed": 0, "body": body})
	fig.call("set_move", speed, running)
	var ap: AnimationPlayer = fig.call("animation_player")
	var sk: Skeleton3D = fig.call("skeleton")
	var anchor := {}
	var worst := 0.0
	var plants := 0
	var dt := 1.0 / RATE
	for i in int(3.6 * RATE):
		fig.call("step", dt)
		fig.position.z += speed * k * dt
		if i < int(0.6 * RATE):
			continue
		var anim := ap.get_animation(ap.current_animation)
		var t := ap.current_animation_position
		for side in ["L", "R"]:
			for point in ["heel", "toe"]:
				var key: String = point + side
				if not _planted(anim, side, "heel" if point == "heel" else "ball", t):
					anchor.erase(key)
					continue
				var p := sk.global_transform * sk.get_bone_global_pose(sk.find_bone(key)).origin
				if not anchor.has(key):
					anchor[key] = p
					plants += 1
					continue
				var a: Vector3 = anchor[key]
				worst = maxf(worst, Vector2(p.x - a.x, p.z - a.z).length())
	fig.queue_free()
	return {"mm": worst * 1000.0, "plants": plants}


static func _planted(anim: Animation, side: String, point: String, t: float) -> bool:
	var key := "contact_l" if side == "L" else "contact_r"
	if anim == null or not anim.has_meta(key):
		return false
	var c: PackedStringArray = anim.get_meta(key)
	var n := c.size()
	var k0 := posmod(int(floor(t * 30.0 + 1e-6)), n)
	var k1 := posmod(k0 + 1, n)
	var want := ["heel", "flat"] if point == "heel" else ["ball", "flat"]
	return want.has(c[k0]) and want.has(c[k1])


# ---- the deck ----

func _deck() -> void:
	var menu: Node = _app().call("current")
	(menu.get_node("%PlayButton") as Button).pressed.emit()
	await _frames(3)
	var hall: Node = _app().call("current")
	var world: Node3D = hall.get("world")
	var av: Node3D = world.get("avatar")
	var rig: Node3D = world.get("camera_rig")
	var egg := av.get_node("Egg") as MeshInstance3D
	_check(av.get("figure") == null and egg.visible, "nothing chosen: the deck avatar is the egg (not the soldier)")
	Figures.select("soldier", "original")
	await _frames(2)
	var fig := av.get("figure") as Node3D
	_check(fig != null and _is_soldier(fig) and not egg.visible, "Figures.select(soldier) makes the deck avatar the soldier, egg hidden")
	if fig == null:
		return
	var sp: Vector2 = fig.call("deck_speeds")
	_check(is_equal_approx(float(av.get("walk_speed")), sp.x) and is_equal_approx(float(av.get("run_speed")), sp.y),
		"the avatar takes the soldier's deck speeds %s" % str(sp))
	var ap: AnimationPlayer = fig.call("animation_player")
	var lib: AnimationLibrary = S.call("clip_library")
	var sc := (fig.call("skeleton") as Skeleton3D).motion_scale
	rig.call("set_view", 0.0, -0.3, 5.5)
	for run in [false, true]:
		world.call("place_avatar", Vector3(2.0, 0.0, 7.0), PI)
		await _physics(4)
		var keys := [KEY_SHIFT, KEY_W] if run else [KEY_W]
		for k in keys:
			_key(k, true)
		await _physics(WALK_TICKS)
		var clip := "run" if run else "walk"
		var want := float(av.call("speed")) / (float(lib.get_animation(clip).get_meta("speed", 1.0)) * sc)
		_check(String(ap.current_animation) == "humanoid/" + clip and absf(ap.speed_scale - want) < 0.05,
			"%s: plays %s at rate %.2f for %.2f m/s (no foot slide)" % ["Shift+W" if run else "W", clip, ap.speed_scale, float(av.call("speed"))])
		for k in keys:
			_key(k, false)
		for i in 180:
			if not av.is_physics_processing():
				break
			await physics_frame
		await _physics(2)
		_check(not av.is_physics_processing(), "released: the avatar stops processing")
	# every level: within the deck targets, no more draw calls than the egg; lo/min hold a still pose
	world.call("place_avatar", Vector3(0.0, 0.0, 3.5), PI)
	rig.call("set_view", 0.0, -0.6, 9.0)
	for level in LEVELS:
		_app().call("set_gfx", level)
		hall.call("refresh")
		Figures.select("egg", "original")
		var egg_m := await _measure()
		Figures.select("soldier", "original")
		var m := await _measure()
		fig = av.get("figure") as Node3D
		print("deck level %-4s soldier: draw calls %3d  primitives %6d  (egg %d / %d)" % [level, m[0], m[1], egg_m[0], egg_m[1]])
		var t: Array = SHIP_TARGET[level]
		_check(fig != null and str(fig.get("level")) == level, "%s: the rebuilt soldier gets the app's level" % level)
		_check(m[0] <= int(t[0]) and m[1] <= int(t[1]) and m[0] <= egg_m[0],
			"%s with the soldier: %d draw calls (egg %d), %d primitives within %d / %d" % [level, m[0], egg_m[0], m[1], int(t[0]), int(t[1])])
		if level == "lo" or level == "min":
			await _frames(20)
			var fap: AnimationPlayer = fig.call("animation_player")
			_check(bool(fig.call("is_still")) and not fap.is_playing(), "%s: the standing deck soldier holds a still pose" % level)
		if level == "min":
			OS.low_processor_usage_mode = true
			await _frames(12)
			var probs := _idle_problems(hall)
			_check(probs.is_empty(), "min: after 10 idle frames nothing under the deck processes", ", ".join(probs))
	# owner pictures: hi and min, close and facing the camera
	for level in ["hi", "min"]:
		_app().call("set_gfx", level)
		hall.call("refresh")
		await _frames(3)
		world.call("place_avatar", Vector3(2.0, 0.0, 6.0), 0.0)
		rig.call("set_view", 0.35, -0.16, 4.8)
		await _frames(8)
		_save("soldier_deck_%s.png" % level)
	_app().call("set_gfx", "mid")
	hall.call("refresh")
	await _frames(2)


# ---- the arena ----

func _arena() -> void:
	var arena: Node = _app().call("push", load(ARENA_SCREEN))
	await _frames(20)
	var world: Node3D = arena.get("world")
	var player: Node3D = world.get("player")
	var fig: Node3D = player.call("figure")
	_check(fig != null and _is_soldier(fig), "the arena player is the soldier", str(fig))
	_check(not bool(player.call("strafes")), "it turns instead of strafing (H9)")
	for level in LEVELS:
		_app().call("set_gfx", level)
		arena.call("refresh")
		await _view(world, ArenaLayout.RESPAWN, 0.0, -0.1, true)
		var m := await _measure()
		print("arena soldier %-4s draw calls %4d  primitives %7d" % [level, m[0], m[1]])
		var t: Array = ARENA_OVERVIEW[level]
		_check(m[0] <= int(t[0]) and m[1] <= int(t[1]), "%s: the arena overview with the soldier, %d draws, %d primitives within %d / %d"
			% [level, m[0], m[1], int(t[0]), int(t[1])])
		var fx: Node = player.get("fx")
		fx.call("clear")
		var mp: Vector3 = player.call("_muzzle_point")
		var chest: Vector3 = player.global_position + ArenaPlayer.CHEST
		_check(mp.distance_to(chest) < 1.3 and mp.distance_to(chest) > 0.05, "%s: the muzzle is by the soldier's hands (%.2f m from the chest)" % [level, mp.distance_to(chest)])
		player.call("press", &"fire", true)
		await _physics(3)
		player.call("press", &"fire", false)
		_check(int(fx.call("alive")) > 0, "%s: firing draws a tracer from the muzzle" % level)
		if level == "hi" or level == "min":
			_save("soldier_arena_%s.png" % level)
		await _physics(30)
		var rig: Node3D = player.call("camera_rig")
		var y0 := float(rig.get("yaw"))
		var p0 := player.global_position
		_key(KEY_D, true)
		await _physics(30)
		_key(KEY_D, false)
		_check(angle_difference(y0, float(rig.get("yaw"))) < -0.8 and player.global_position.distance_to(p0) < 0.05,
			"%s: D turns the camera and the body without sliding" % level)
		await _physics(10)
		if level == "hi" or level == "min":
			await _view(world, ArenaLayout.RESPAWN + Vector3(0, 0, -3), 0.6, -0.2, false)
			rig.call("set_view", 0.6, -0.15, 2.8)
			await _frames(4)
			player.rotation.y = float(player.get("face")) + 2.6
			await _frames(6)
			_save("soldier_arena_front_%s.png" % level)
			player.rotation.y = float(player.get("face"))
		if level == "min":
			world.call("place_player", ArenaLayout.RESPAWN, PI, 0.0)
			player.call("set_mode", &"walk")
			await _physics(30)
			await _frames(50)
			var probs := _idle_problems(arena)
			_check(probs.is_empty(), "min: after idle frames nothing under the arena processes", ", ".join(probs))
			_check(bool(fig.call("is_still")) and not (fig.call("animation_player") as AnimationPlayer).is_playing(), "min: the soldier holds a still pose")
	_app().call("set_gfx", "mid")
	_app().call("pop")
	await _frames(6)


func _view(world: Node3D, foot: Vector3, yaw: float, pitch: float, shoot: bool) -> void:
	var player: Node3D = world.get("player")
	world.call("place_player", foot, yaw + PI, yaw)
	player.call("set_mode", &"shoot" if shoot else &"walk")
	var rig: Node3D = player.call("camera_rig")
	rig.call("set_view", yaw, pitch, ArenaCamera.SHOULDER_ARM if shoot else 4.5)
	await _physics(6)
	await _frames(3)


# ---- a campaign mission ----

func _mission() -> void:
	for level in ["hi", "min"]:
		_app().call("set_gfx", level)
		var ms = _app().call("push", load(MISSION))
		ms.start(Specs.make("purge", {"seed": 4040, "biome": "ruin", "faction": "traitors", "difficulty": "normal"}))
		for i in 600:
			if ms.playing():
				break
			await process_frame
		var w = ms.world()
		var fig: Node3D = w.player.call("figure") if w != null and w.player != null else null
		_check(fig != null and _is_soldier(fig), "%s: the mission's player is the soldier" % level)
		if w == null:
			continue
		w.test_god = true
		var foot: Vector3 = w.layout["player_spawn"]
		w.place_player(foot, 0.0)
		var rig: Node3D = w.player.call("camera_rig")
		rig.call("set_view", 0.0, -0.12, 3.0)
		await _physics(4)
		await _frames(4)
		var m := await _measure()
		var t: Array = MISSION_OVERVIEW[level]
		print("mission soldier %-4s draw calls %4d  primitives %7d" % [level, m[0], m[1]])
		_check(m[0] <= int(t[0]) and m[1] <= int(t[1]), "%s: the mission overview with the soldier, %d draws, %d primitives within %d / %d"
			% [level, m[0], m[1], int(t[0]), int(t[1])])
		_save("soldier_mission_%s.png" % level)
		if _app().call("current") == ms:
			_app().call("pop")
		await _frames(3)
	_app().call("set_gfx", "mid")


# ---- the campaign's "normal" hero card ----

func _hero() -> void:
	var heroes: Script = load("res://scenes/campaign/hero_loader.gd")
	heroes.set("test_dirs", PackedStringArray(["res://tests/fixtures/none"]))
	var sel := {"figure": "soldier", "scheme": "original"}
	for lv in LEVELS:
		var vp := SubViewport.new()
		vp.size = Vector2i(640, 360)
		vp.own_world_3d = true
		vp.msaa_3d = Viewport.MSAA_DISABLED
		vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
		vp.scaling_3d_scale = float(HERO_SCALE[lv])
		vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		root.add_child(vp)
		var h: Node3D = heroes.call("make", "normal")
		vp.add_child(h)
		h.call("setup", {"level": lv, "sel": sel, "aspect": 640.0 / 360.0})
		if lv != "min":
			h.call("set_active", true)
			h.call("seek", float(h.call("poster_t")))
		var fig: Node3D = h.get("figure")
		_check(fig != null and _is_soldier(fig), "%s: the normal card shows the soldier" % lv)
		# the card's clock moves the soldier on hi/mid; on lo/min the card is drawn once and the soldier does nothing
		var ap: AnimationPlayer = fig.call("animation_player") if fig != null and fig.has_method("animation_player") else null
		_check(ap != null, "%s: the soldier has its animation player" % lv)
		if ap != null:
			var p0 := ap.current_animation_position
			await _frames(20)
			var moves: bool = lv == "hi" or lv == "mid"
			var moved := absf(ap.current_animation_position - p0) > 0.0001
			_check(moved == moves, "%s: the soldier %s" % [lv, "follows the card's clock" if moves else "does nothing per frame on the card"],
				"%.4f -> %.4f" % [p0, ap.current_animation_position])
		var m := await _measure_vp(vp)
		var b: Array = HERO_BUDGET[lv]
		print("hero normal soldier %-4s: %d draws, %d primitives" % [lv, m[0], m[1]])
		_check(m[0] <= int(b[0]) and m[1] <= int(b[1]), "%s: the live card within %d draws / %d primitives" % [lv, b[0], b[1]], str(m))
		var cam := vp.get_camera_3d()
		var head: float = h.get("head")
		for pt in [["head", Vector3(0.0, head + 0.12, 0.0)], ["chest", Vector3(0.0, head - 0.35, 0.0)]]:
			var p: Vector3 = fig.position + pt[1]
			var s := cam.unproject_position(p)
			_check(not cam.is_position_behind(p) and s.x >= 0.0 and s.y >= 0.0 and s.x <= 640.0 and s.y <= 360.0, "%s: the card frames the %s" % [lv, pt[0]], str(s))
		await RenderingServer.frame_post_draw
		var img := vp.get_texture().get_image()
		_check(_lit_centre(img), "%s: the card shows a lit soldier over the dark backdrop" % lv)
		_save_img(img, "soldier_hero_%s.png" % lv)
		h.call("set_active", false)
		vp.queue_free()
		await _frames(1)


# ---- the other bodies ----

func _bodies() -> void:
	var hall: Node = _app().call("current")
	var world: Node3D = hall.get("world")
	var av: Node3D = world.get("avatar")
	var rig: Node3D = world.get("camera_rig")
	var heroes: Script = load("res://scenes/campaign/hero_loader.gd")
	heroes.set("test_dirs", PackedStringArray(["res://tests/fixtures/none"]))
	for id: String in BODIES:
		var body := str(BODIES[id][0])
		_check(Figures.entry(id).get("kind", "") == "builtin", "%s is in the dressing room's list" % id)
		# foot slide at its own deck speeds and the arena speeds (its own S in the playback rate)
		var probe: Node3D = S.new()
		root.add_child(probe)
		probe.call("set_manual", true)
		probe.call("setup", {"role": &"deck", "level": "mid", "seed": 0, "body": body})
		var deck: Vector2 = probe.call("deck_speeds")
		var sc := (probe.call("skeleton") as Skeleton3D).motion_scale
		probe.queue_free()
		for c in [["deck walk", deck.x, false], ["deck run", deck.y, true], ["arena walk", float(ArenaData.PLAYER["walk"]), false],
				["arena run", float(ArenaData.PLAYER["run"]), true]]:
			var r := _slide(float(c[1]), bool(c[2]), 1.0, body)
			_check(float(r["mm"]) <= MAX_SLIDE_MM and int(r["plants"]) > 2,
				"%s %s at %.2f m/s (S %.4f): foot slide %.2f mm while planted (%d plants)" % [body, c[0], c[1], sc, r["mm"], r["plants"]], str(r))
		# the deck at hi and min
		Figures.select(id, "original")
		for level in ["hi", "min"]:
			_app().call("set_gfx", level)
			hall.call("refresh")
			await _frames(3)
			var fig := av.get("figure") as Node3D
			_check(fig != null and _is_soldier(fig) and str(fig.get("body_id")) == body, "%s %s: the deck avatar is that body" % [body, level])
			if fig == null:
				continue
			var sp: Vector2 = fig.call("deck_speeds")
			_check(sp.is_equal_approx(deck) and is_equal_approx(float(av.get("walk_speed")), sp.x),
				"%s %s: the avatar takes its deck speeds %s" % [body, level, str(sp)])
			world.call("place_avatar", Vector3(0.0, 0.0, 3.5), PI)
			rig.call("set_view", 0.0, -0.6, 9.0)
			var m := await _measure()
			var t: Array = SHIP_TARGET[level]
			print("deck %s %-4s draw calls %3d  primitives %6d" % [body, level, m[0], m[1]])
			_check(m[0] <= int(t[0]) and m[1] <= int(t[1]), "%s %s: the deck within %d / %d (%d draws, %d primitives)"
				% [body, level, int(t[0]), int(t[1]), m[0], m[1]])
			world.call("place_avatar", Vector3(2.0, 0.0, 6.0), 0.0)
			rig.call("set_view", 0.35, -0.16, 4.8)
			await _frames(8)
			_save("soldier_%s_deck_%s.png" % [body, level])
		# the hero card at hi and min
		for lv in ["hi", "min"]:
			await _hero_card(id, body, lv)
		# the arena: the player is that body, the overview at hi within §11.2
		_app().call("set_gfx", "hi")
		var arena: Node = _app().call("push", load(ARENA_SCREEN))
		await _frames(20)
		var aw: Node3D = arena.get("world")
		var player: Node3D = aw.get("player")
		var af: Node3D = player.call("figure")
		_check(af != null and _is_soldier(af) and str(af.get("body_id")) == body, "%s: the arena player is that body" % body)
		await _view(aw, ArenaLayout.RESPAWN, 0.0, -0.1, true)
		var am := await _measure()
		var at: Array = ARENA_OVERVIEW["hi"]
		_check(am[0] <= int(at[0]) and am[1] <= int(at[1]), "%s hi: the arena overview within %d / %d (%d draws, %d primitives)"
			% [body, int(at[0]), int(at[1]), am[0], am[1]])
		await _view(aw, ArenaLayout.RESPAWN + Vector3(0, 0, -3), 0.6, -0.2, false)
		(player.call("camera_rig") as Node3D).call("set_view", 0.6, -0.15, 2.8)
		player.rotation.y = float(player.get("face")) + 2.6
		await _frames(6)
		_save("soldier_%s_arena_hi.png" % body)
		_app().call("pop")
		await _frames(6)
	Figures.select("soldier", "original")
	_app().call("set_gfx", "mid")
	hall.call("refresh")
	await _frames(2)


## the "normal" hero card with Figures id `id` (body `body`) at level lv: that body, lit, head and chest in the frame
func _hero_card(id: String, body: String, lv: String) -> void:
	var heroes: Script = load("res://scenes/campaign/hero_loader.gd")
	var vp := SubViewport.new()
	vp.size = Vector2i(640, 360)
	vp.own_world_3d = true
	vp.msaa_3d = Viewport.MSAA_DISABLED
	vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
	vp.scaling_3d_scale = float(HERO_SCALE[lv])
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(vp)
	var h: Node3D = heroes.call("make", "normal")
	vp.add_child(h)
	h.call("setup", {"level": lv, "sel": {"figure": id, "scheme": "original"}, "aspect": 640.0 / 360.0})
	if lv != "min":
		h.call("set_active", true)
		h.call("seek", float(h.call("poster_t")))
	var fig: Node3D = h.get("figure")
	_check(fig != null and _is_soldier(fig) and str(fig.get("body_id")) == body, "%s %s: the normal card shows that body" % [body, lv])
	if fig == null:
		vp.queue_free()
		return
	var m := await _measure_vp(vp)
	var b: Array = HERO_BUDGET[lv]
	_check(m[0] <= int(b[0]) and m[1] <= int(b[1]), "%s %s: the live card within %d draws / %d primitives" % [body, lv, b[0], b[1]], str(m))
	var cam := vp.get_camera_3d()
	var head: float = h.get("head")
	for pt in [["head", Vector3(0.0, head + 0.12, 0.0)], ["chest", Vector3(0.0, head - 0.35, 0.0)]]:
		var p: Vector3 = fig.position + pt[1]
		var sc := cam.unproject_position(p)
		_check(not cam.is_position_behind(p) and sc.x >= 0.0 and sc.y >= 0.0 and sc.x <= 640.0 and sc.y <= 360.0,
			"%s %s: the card frames the %s" % [body, lv, pt[0]], str(sc))
	await RenderingServer.frame_post_draw
	var img := vp.get_texture().get_image()
	_check(_lit_centre(img), "%s %s: the card shows a lit soldier over the dark backdrop" % [body, lv])
	_save_img(img, "soldier_%s_hero_%s.png" % [body, lv])
	h.call("set_active", false)
	vp.queue_free()
	await _frames(1)


# ---- English ----

func _english() -> void:
	_app().call("set_lang", "en")
	var ds: Node = _app().call("push", load(DRESSING))
	await _frames(3)
	ds.call("pick_figure", "soldier")
	ds.call("refresh")
	await _frames(4)
	var found := false
	for b: Button in ds.call("char_buttons"):
		if b.text == "Infantry (preview)":
			found = true
	_check(found, "English: the dressing room names it \"Infantry (preview)\"")
	var texts: Array = (ds.call("char_buttons") as Array).map(func(b: Button) -> String: return b.text)
	for id: String in BODIES:
		_check(texts.has(str(BODIES[id][1])), "English: the dressing room names %s \"%s\"" % [id, BODIES[id][1]], str(texts))
	var pf: Node3D = ds.call("preview_figure")
	_check(pf != null and _is_soldier(pf), "the preview is the soldier")
	_check(ds.call("swatch_buttons").all(func(b: Button) -> bool: return b.disabled), "it keeps its own colours (swatches off)")
	var thai := _thai_in(ds)
	_check(thai.is_empty(), "English mode: no Thai on the dressing screen", ", ".join(thai))
	_save("soldier_dressing_en.png")
	# a woman's body on the deck and in the arena, still no Thai
	ds.call("pick_figure", "soldier_f1")
	ds.call("refresh")
	await _frames(4)
	var pf1: Node3D = ds.call("preview_figure")
	_check(pf1 != null and _is_soldier(pf1) and str(pf1.get("body_id")) == "f1", "English: the preview of soldier_f1 is that body")
	var thai1 := _thai_in(ds)
	_check(thai1.is_empty(), "English mode: no Thai on the dressing screen with soldier_f1", ", ".join(thai1))
	ds.call("use_selection")
	await _frames(2)
	_check(str(Figures.selected()["figure"]) == "soldier_f1", "English: soldier_f1 is the selection")
	ds.call("close")
	await _frames(4)
	var hall: Node = _app().call("current")
	if hall != null and hall.has_method("refresh"):
		hall.call("refresh")
		await _frames(3)
		var th := _thai_in(hall)
		_check(th.is_empty(), "English mode: no Thai on the deck with soldier_f1", ", ".join(th))
	var arena: Node = _app().call("push", load(ARENA_SCREEN))
	await _frames(20)
	var ta := _thai_in(arena)
	_check(ta.is_empty(), "English mode: no Thai in the arena with soldier_f1", ", ".join(ta))
	var apl: Node3D = (arena.get("world") as Node3D).get("player")
	var af1: Node3D = apl.call("figure") if apl != null else null
	_check(af1 != null and str(af1.get("body_id")) == "f1", "English: the arena player is soldier_f1")
	_app().call("pop")
	await _frames(4)
	_app().call("set_lang", "th")
	Figures.select("soldier", "original")


# ---- helpers ----

func _is_soldier(n: Node) -> bool:
	return n != null and n.get_script() != null and (n.get_script() as Script).resource_path == SCRIPT


func _measure() -> Array:
	var idle := OS.low_processor_usage_mode
	OS.low_processor_usage_mode = false
	await _frames(3)
	var d := 0
	var p := 0
	for i in 4:
		await process_frame
		d = maxi(d, RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME))
		p = maxi(p, RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME))
	OS.low_processor_usage_mode = idle
	return [d, p]


func _measure_vp(vp: SubViewport) -> Array:
	await _frames(3)
	var rid := vp.get_viewport_rid()
	var d := 0
	var p := 0
	for _i in 4:
		await process_frame
		d = maxi(d, RenderingServer.viewport_get_render_info(rid, RenderingServer.VIEWPORT_RENDER_INFO_TYPE_VISIBLE,
			RenderingServer.VIEWPORT_RENDER_INFO_DRAW_CALLS_IN_FRAME))
		p = maxi(p, RenderingServer.viewport_get_render_info(rid, RenderingServer.VIEWPORT_RENDER_INFO_TYPE_VISIBLE,
			RenderingServer.VIEWPORT_RENDER_INFO_PRIMITIVES_IN_FRAME))
	return [d, p]


## the middle of the card is brighter than its corners (a lit figure over the backdrop)
func _lit_centre(img: Image) -> bool:
	var w := img.get_width()
	var h := img.get_height()
	var centre := 0.0
	for y in range(int(h * 0.3), int(h * 0.7), 4):
		for x in range(int(w * 0.4), int(w * 0.6), 4):
			centre = maxf(centre, img.get_pixel(x, y).get_luminance())
	var corner := maxf(img.get_pixel(2, 2).get_luminance(), img.get_pixel(w - 3, 2).get_luminance())
	return centre > corner + 0.1


func _idle_problems(screen: Node) -> PackedStringArray:
	var out := PackedStringArray()
	var stack: Array[Node] = [screen]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n.can_process() and (n.is_processing() or n.is_physics_processing()):
			out.append(String(n.name) + " processes")
		if n is AnimationPlayer and (n as AnimationPlayer).is_playing() and n.can_process():
			out.append(String(n.name) + " plays")
		if n is Timer and not (n as Timer).is_stopped():
			out.append(String(n.name) + " timer runs")
		stack.append_array(n.get_children())
	return out


func _thai_in(node: Node) -> PackedStringArray:
	var out := PackedStringArray()
	if node is CanvasItem and not (node as CanvasItem).is_visible_in_tree():
		return out
	if node is Label or node is Button or node is Label3D:
		for t in [str(node.get("text")), str(node.get("tooltip_text")) if not node is Label3D else ""]:
			if _thai_re.search(t) != null:
				out.append(String(node.name) + ": " + t.left(60))
	for c in node.get_children():
		out.append_array(_thai_in(c))
	return out


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
	_save_img(root.get_viewport().get_texture().get_image(), name)


func _save_img(img: Image, name: String) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_out_dir))
	var path := _out_dir + "/" + name
	var err := img.save_png(path)
	_check(err == OK, "saved " + ProjectSettings.globalize_path(path) + " " + str(img.get_size()))


func _finish() -> void:
	for k in [KEY_W, KEY_A, KEY_S, KEY_D, KEY_SHIFT]:
		_key(k, false)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var app := _app()
	app.call("set_touch", "auto")
	app.set("settings_file", str(app.get("SETTINGS_PATH")))
	Figures.store_path = ""
	Figures.pack_list = Figures.PACK_LIST
	Figures.pack_manifest = ArenaActors.PACK_MANIFEST
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SETTINGS_FILE))
	if _fake != null:
		_fake.name = "NetFake"
		_fake.queue_free()
	if _real_net != null:
		_real_net.name = "Net"
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
