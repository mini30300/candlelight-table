extends SceneTree
## The hive beast (ARENA_SPEC §8, §13.4): scenes/arena/hive_beast.tscn with its default figure KitBeast (the warrior kit
## playing the baked clips of assets/anim/humanoid.res, the kit's hunch held over them) and the code-built beast egg
## when the kit is missing. Checks: the kit loads skinned with 23 bones and motion_scale 1.3; every logical clip
## resolves to baked clips that move bones away from the rest pose; across clip changes no bone turns more than 25°
## between two 60 Hz frames (blend + hold easing); chasing at 3.7 m/s the planted-foot slide stays <= 25 mm; the
## telegraph ring shows only in wind-up / strike and the wind-up lasts >= 0.5 s before the claw's shot event; the
## telegraph is the claw's real reach (a sector of strike_reach and +-strike_half_angle, its fill reaching the rim as the
## wind-up ends); a reset during the wind-up cancels the claw; with the bot on but the player out of the room it sleeps
## on its pad (no physics work) and set_target_in_room wakes it; the AI
## chases round a pillar with real colliders and never enters it; a hit flashes for 0.08 s; death drops the collision
## layer and holds the last frame until reset; per level the kit material's per_vertex, and on min the idle dummy
## holds a still pose (AnimationPlayer not playing, no physics processing) after 10 frames; with the kit forced missing
## the beast egg stands in with the same API. With a display it saves hive_beast_clips.png (contact sheet: idle, walk,
## run, wind-up, blow, hit, hit_heavy, die), hive_beast_<level>.png and hive_beast_fallback.png.
##   TEST_OUT=<dir> timeout 600 nice -n 10 xvfb-run -a -s "-screen 0 1280x720x24" <godot> --path godot \
##     --rendering-driver opengl3 --resolution 1280x720 --audio-driver Dummy -s tests/render/test_hive_beast.gd
## Headless runs measure only. TEST_OUT (absolute) replaces tests/out.

const BEAST_SCENE := "res://scenes/arena/hive_beast.tscn"
const KIT_BEAST := "res://scenes/arena/kit_beast.gd"
const LAYOUT := "res://scenes/arena/arena_layout.gd"
const DEFAULT_OUT_DIR := "res://tests/out"
const BOUNDS := Rect2(Vector2(-10.0, -34.5), Vector2(20.0, 24.0))
const FIGURE_API: PackedStringArray = ["setup", "metrics", "clip_names", "play", "set_move", "set_aim", "set_weapon", "set_flash",
	"set_telegraph", "muzzle", "anchor", "apply_level"]
const LOGICAL: PackedStringArray = ["idle", "walk", "run", "attack", "hit", "hit_heavy", "die"]
const MAX_TURN_DEG := 25.0
const MAX_SLIDE_MM := 25.0
const LEVELS: PackedStringArray = ["hi", "mid", "lo", "min"]
const TARGET_SRC := """extends Node3D
const RADIUS := 0.35
var hp := 100
var hits: Array = []
func is_alive() -> bool:
	return hp > 0
func take_hit(h: Dictionary) -> Dictionary:
	hits.append(h)
	var a: int = mini(int(h.get("amount", 0)), hp)
	hp -= a
	return {"applied": a, "hp": hp, "killed": hp <= 0}
"""

var _out_dir := DEFAULT_OUT_DIR
var _headless := false
var _passed := 0
var _failed := 0
var _stage: Node3D
var _cam: Camera3D
var _target_script: GDScript
var _blockers: Array = []


func _initialize() -> void:
	var env := OS.get_environment("TEST_OUT")
	if env != "" and env.is_absolute_path():
		_out_dir = env
	_headless = DisplayServer.get_name() == "headless"
	_run()


func _run() -> void:
	await process_frame
	_target_script = GDScript.new()
	_target_script.source_code = TARGET_SRC
	_target_script.reload()
	_blockers = _room_blockers()
	_stage = Node3D.new()
	_stage.name = "Stage"
	root.add_child(_stage)
	_build_stage()
	_ok(ResourceLoader.exists(BEAST_SCENE), "the beast scene exists: " + BEAST_SCENE)
	await _check_kit()
	_check_clips_move()
	_check_clip_changes()
	_check_footslide()
	await _check_telegraph_and_strike()
	await _check_telegraph_shape()
	await _check_reset_during_windup()
	await _check_sleeps_at_home()
	await _check_chase_round_pillar()
	await _check_flash_and_death()
	await _check_levels_and_still()
	await _check_fallback()
	if _headless:
		print("headless: no PNGs (run under xvfb for hive_beast_*.png)")
	else:
		await _pngs()
	_finish()


func _finish() -> void:
	print("%s  %d passed, %d failed (test_hive_beast)" % ["PASS " if _failed == 0 else "FAIL ", _passed, _failed])
	quit(1 if _failed > 0 else 0)


func _ok(cond: bool, msg: String, detail: Variant = null) -> void:
	if cond:
		_passed += 1
		print("ok    " + msg)
	else:
		_failed += 1
		print("FAIL  " + msg + ("" if detail == null else " " + str(detail).left(1500)))


func _abs(p: String) -> String:
	return ProjectSettings.globalize_path(p) if p.begins_with("res://") else p


func _physics(n: int) -> void:
	for i in n:
		await physics_frame


func _frames(n: int) -> void:
	for i in n:
		await process_frame


static func _room_blockers() -> Array:
	if ResourceLoader.exists(LAYOUT):
		var s: Script = load(LAYOUT)
		if s != null and s.can_instantiate():
			var b: Variant = s.call("blockers")
			if b is Array and not (b as Array).is_empty():
				return b
	var out: Array = []
	for p in [Vector2(-4.5, -18.5), Vector2(4.5, -18.5), Vector2(-3.2, -24.5), Vector2(3.2, -24.5)]:
		out.append({"kind": "cyl", "c": p, "r": 0.8, "y0": 0.0, "y1": 4.0, "tag": "pillar"})
	out.append({"kind": "box", "c": Vector3(0, 3.5, -34.75), "h": Vector3(10.5, 3.5, 0.25), "tag": "wall_far"})
	out.append({"kind": "box", "c": Vector3(-10.25, 3.5, -22.5), "h": Vector3(0.25, 3.5, 12.5), "tag": "wall_left"})
	out.append({"kind": "box", "c": Vector3(10.25, 3.5, -22.5), "h": Vector3(0.25, 3.5, 12.5), "tag": "wall_right"})
	out.append({"kind": "box", "c": Vector3(0, 3.5, -10.25), "h": Vector3(10.5, 3.5, 0.25), "tag": "wall_near"})
	return out


## Floor, a dark backdrop, the blockers as colliders (layer 1) and a few visible pillars; one camera.
func _build_stage() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("05060a")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color.BLACK
	_cam = Camera3D.new()
	_cam.environment = env
	_cam.fov = 50.0
	_stage.add_child(_cam)
	_cam.current = true
	var floor_mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(40, 40)
	floor_mi.mesh = pm
	var fm := StandardMaterial3D.new()
	fm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fm.albedo_color = Color("2b2f35")
	floor_mi.material_override = fm
	floor_mi.position = Vector3(0, 0, -22)
	_stage.add_child(floor_mi)
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	_stage.add_child(body)
	var pmat := StandardMaterial3D.new()
	pmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	pmat.albedo_color = Color("4a4f55")
	for b in _blockers:
		var cs := CollisionShape3D.new()
		if str(b["kind"]) == "box":
			var bs := BoxShape3D.new()
			bs.size = (b["h"] as Vector3) * 2.0
			cs.shape = bs
			cs.position = b["c"]
		else:
			var cy := CylinderShape3D.new()
			cy.radius = float(b["r"])
			cy.height = float(b["y1"]) - float(b["y0"])
			cs.shape = cy
			var c: Vector2 = b["c"]
			cs.position = Vector3(c.x, (float(b["y1"]) + float(b["y0"])) * 0.5, c.y)
			if str(b.get("tag", "")).begins_with("pillar"):
				var mi := MeshInstance3D.new()
				var cm := CylinderMesh.new()
				cm.top_radius = float(b["r"])
				cm.bottom_radius = float(b["r"])
				cm.height = cy.height
				cm.radial_segments = 8
				mi.mesh = cm
				mi.material_override = pmat
				mi.position = cs.position
				_stage.add_child(mi)
		body.add_child(cs)


func _make_beast(opts: Dictionary = {}) -> Node3D:
	var ps: PackedScene = load(BEAST_SCENE)
	var b: Node3D = ps.instantiate()
	_stage.add_child(b)
	var o := {"level": "mid", "seed": 4404, "spawn": Vector3(0, 0, -29), "face": 0.0, "bounds": BOUNDS, "blockers": _blockers}
	o.merge(opts, true)
	b.call("setup", _stage, o)
	return b


func _make_target(p: Vector3) -> Node3D:
	var t := Node3D.new()
	t.set_script(_target_script)
	_stage.add_child(t)
	t.global_position = p
	return t


## A figure alone, stepped by hand (AnimationPlayer in manual mode).
func _manual_figure(opts: Dictionary = {}) -> Node3D:
	var s: GDScript = load(KIT_BEAST)
	var f: Node3D = s.new()
	_stage.add_child(f)
	var o := {"role": &"enemy", "level": "mid", "seed": 4404, "manual": true}
	o.merge(opts, true)
	f.call("setup", o)
	return f


# ---- the kit ----

func _check_kit() -> void:
	var b := _make_beast()
	var f: Node3D = b.call("figure")
	_ok(str(b.call("kit_key")) == "warrior", "the public build's beast is the warrior kit (kit_key %s)" % b.call("kit_key"))
	var sk: Skeleton3D = f.call("skeleton")
	_ok(sk != null and sk.get_bone_count() == 23, "skinned with 23 bones (%d)" % (sk.get_bone_count() if sk != null else -1))
	_ok(sk != null and absf(sk.motion_scale - 1.3) < 0.001, "Skeleton3D.motion_scale is the kit scale 1.3 (%.3f)" % (sk.motion_scale if sk != null else 0.0))
	var miss := PackedStringArray()
	for m in FIGURE_API:
		if not f.has_method(m):
			miss.append(m)
	_ok(miss.is_empty() and f.has_signal("clip_event"), "KitBeast has the whole figure contract (+ clip_event)", miss)
	var m: Dictionary = f.call("metrics")
	_ok(absf(float(m["height"]) - 2.14) < 0.05 and absf(float(m["radius"]) - 0.6) < 0.001, "metrics: height %.2f m, radius %.2f m" % [m["height"], m["radius"]])
	_ok(f.call("muzzle") == null, "an enemy has no muzzle")
	for a in [&"head", &"chest", &"hand_r", &"hand_l"]:
		var n: Node3D = f.call("anchor", a)
		_ok(n != null, "anchor %s exists" % a)
	await _physics(2)
	var head: Node3D = f.call("anchor", &"head")
	_ok(head != null and head.global_position.y > 1.4 and head.global_position.y < 2.4, "the head anchor sits at %.2f m" % (head.global_position.y if head != null else -1.0))
	_ok(b.collision_layer == 8 and b.collision_mask == 7, "collision layer 8, mask 1 | 2 | 4")
	_ok(not b.is_physics_processing(), "a fresh dummy with the bot off does no physics work")
	b.queue_free()
	await _frames(1)


func _check_clips_move() -> void:
	var f := _manual_figure()
	var sk: Skeleton3D = f.call("skeleton")
	var ap: AnimationPlayer = f.call("animation_player")
	var names: Dictionary = f.call("clip_names")
	for lg in LOGICAL:
		var list: PackedStringArray = names.get(lg, PackedStringArray())
		var exist := not list.is_empty()
		for c in list:
			exist = exist and ap.has_animation("humanoid/" + c)
		_ok(exist, "logical %s -> %s, all baked" % [lg, ",".join(list)])
		var worst := 0.0
		for i in list.size():
			f.call("set_variant", i)
			var len := float(f.call("play", StringName(lg)))
			f.call("step", 0.2)
			f.call("step", maxf(len * 0.5 - 0.2, 0.0))
			worst = maxf(worst, _max_from_rest(sk))
		_ok(worst > 10.0, "%s moves bones away from the rest pose (up to %.0f°)" % [lg, worst])
	f.queue_free()


static func _max_from_rest(sk: Skeleton3D) -> float:
	var w := 0.0
	for i in sk.get_bone_count():
		var q := sk.get_bone_pose_rotation(i)
		var r := sk.get_bone_rest(i).basis.get_rotation_quaternion()
		w = maxf(w, rad_to_deg(q.angle_to(r)))
	return w


## A sequence of clip changes at 60 Hz: idle, walk, run, the claw (at the attack speed), a flinch, run, a heavy flinch,
## idle, death; the biggest change of any bone's local rotation between two frames.
func _check_clip_changes() -> void:
	var f := _manual_figure()
	var sk: Skeleton3D = f.call("skeleton")
	var seq := [["move", 0.0, false, 1.0], ["move", 1.5, false, 1.0], ["move", 3.7, true, 1.0], ["play", "attack", 0.6, 1.4],
		["move", 3.7, true, 0.6], ["play", "hit", 1.0, 0.35], ["move", 3.7, true, 0.8], ["play", "hit_heavy", 1.0, 0.8],
		["play", "idle", 1.0, 0.0], ["move", 0.0, false, 1.0], ["play", "attack", 0.6, 0.5], ["play", "die", 1.0, 2.8]]
	var prev: Array[Quaternion] = []
	var worst := 0.0
	var where := ""
	for s in seq:
		if s[0] == "move":
			f.call("set_move", s[1], s[2])
		else:
			f.call("play", StringName(s[1]), s[2])
		var n := int(round(float(s[3]) * 60.0))
		for i in n:
			f.call("step", 1.0 / 60.0)
			var cur: Array[Quaternion] = []
			for b in sk.get_bone_count():
				cur.append(sk.get_bone_pose_rotation(b))
			if prev.size() == cur.size():
				for b in cur.size():
					# the hands carry the bake's gear fit (a blade turned 97-174° between two keys of claw_*): the clips' own motion
					if sk.get_bone_name(b) in ["handL", "handR"]:
						continue
					var d := rad_to_deg(prev[b].angle_to(cur[b]))
					if d > worst:
						worst = d
						where = "%s at %s frame %d (%s)" % [sk.get_bone_name(b), str(s[1]), i, f.call("playing_clip")]
			prev = cur
	_ok(worst <= MAX_TURN_DEG, "across clip changes no bone (but the hands) turns more than %.0f° between two frames (worst %.1f°)" % [MAX_TURN_DEG, worst], where)
	print("      worst frame-to-frame turn: %.1f° (%s)" % [worst, where])
	f.queue_free()


## Chasing at 3.7 m/s: the run clip at playback 3.7 / (2.868 x 1.3); planted heel / ball points (the clip's contact
## flags) measured on the ground at 240 samples a second, three cycles, with the kit's hold on.
func _check_footslide() -> void:
	var f := _manual_figure()
	var sk: Skeleton3D = f.call("skeleton")
	var ap: AnimationPlayer = f.call("animation_player")
	f.call("set_move", 3.7, true)
	for i in 30:
		f.call("step", 1.0 / 60.0)     # past the blend from idle
	var anim := ap.get_animation(ap.current_animation)
	var rate := 240.0
	var span := anim.length * 3.0 / ap.speed_scale
	var anchor := {}
	var worst := 0.0
	var plants := 0
	var where := ""
	var z := 0.0
	for i in int(span * rate):
		f.call("step", 1.0 / rate)
		z += 3.7 / rate
		f.position = Vector3(0, 0, z)
		var tc := fmod(ap.current_animation_position, anim.length)
		for side in ["L", "R"]:
			for point in ["heel", "toe"]:
				var key: String = point + side
				if not _planted(anim, side, "heel" if point == "heel" else "ball", tc):
					anchor.erase(key)
					continue
				var p := sk.global_transform * sk.get_bone_global_pose(sk.find_bone(key)).origin
				if not anchor.has(key):
					anchor[key] = p
					plants += 1
					continue
				var a: Vector3 = anchor[key]
				var d := Vector2(p.x - a.x, p.z - a.z).length()
				if d > worst:
					worst = d
					where = "%s at %.3f s" % [key, tc]
	_ok(plants > 4, "the run plants its feet (%d plants)" % plants)
	_ok(worst * 1000.0 <= MAX_SLIDE_MM, "chasing at 3.7 m/s (playback %.3f) the planted-foot slide is %.1f mm <= %.0f mm" % [ap.speed_scale, worst * 1000.0, MAX_SLIDE_MM], where)
	f.queue_free()


static func _planted(anim: Animation, side: String, point: String, t: float) -> bool:
	var key := "contact_l" if side == "L" else "contact_r"
	if not anim.has_meta(key):
		return false
	var c: PackedStringArray = anim.get_meta(key)
	var n := c.size()
	var k0 := posmod(int(floor(t * 30.0 + 1e-6)), n)
	var k1 := posmod(k0 + 1, n)
	var want := ["heel", "flat"] if point == "heel" else ["ball", "flat"]
	return want.has(c[k0]) and want.has(c[k1])


# ---- the actor ----

func _check_telegraph_and_strike() -> void:
	var b := _make_beast({"spawn": Vector3(0, 0, -20)})
	var t := _make_target(Vector3(0, 0, -18.0))
	b.call("set_target", t)
	b.call("set_target_in_room", true)
	var f: Node3D = b.call("figure")
	var shots := []
	f.connect("clip_event", func(k: StringName) -> void: shots.append([k, Time.get_ticks_msec()]))
	var ring: MeshInstance3D = b.get_node("Telegraph")
	b.call("set_bot", true)
	var ring_bad := []
	var t_wind := -1.0
	var t_shot := -1.0
	var t_strike := -1.0
	var ring_seen := false
	var tint_seen := false
	var clock := 0.0
	for i in 240:
		await physics_frame
		clock += 1.0 / Engine.physics_ticks_per_second
		var st: StringName = b.call("state")
		var busy := st == &"windup" or st == &"strike"
		if ring.visible != busy and st != &"recover":
			ring_bad.append("%s ring %s" % [st, ring.visible])
		if st == &"recover" and ring.visible:
			ring_bad.append("recover ring on")
		if st == &"windup" and t_wind < 0.0:
			t_wind = clock
		if busy:
			ring_seen = ring_seen or ring.visible
			var mi: MeshInstance3D = f.find_children("*", "MeshInstance3D", true, false)[0]
			tint_seen = tint_seen or mi.material_overlay != null
		if t_shot < 0.0 and not shots.is_empty() and t_wind >= 0.0:
			t_shot = clock
		if t_strike < 0.0 and int(b.call("strikes")) > 0:
			t_strike = clock
		if t_strike > 0.0 and clock > t_strike + 0.3:
			break
	_ok(t_wind >= 0.0, "with the bot on and the target 2 m ahead it winds up (%.2f s)" % t_wind)
	_ok(ring_seen and ring_bad.is_empty(), "the telegraph ring shows only in wind-up / strike", ring_bad)
	_ok(tint_seen, "the figure tints red during the wind-up (mid)")
	_ok(t_shot > 0.0 and t_shot - t_wind >= 0.5, "the wind-up lasts %.2f s >= 0.5 s before the claw clip's shot event" % (t_shot - t_wind))
	_ok(t_strike > 0.0 and absf(t_strike - t_wind - 0.72) <= 0.04, "the blow lands %.2f s after the wind-up began (0.72)" % (t_strike - t_wind))
	var hits: Array = t.get("hits")
	_ok(hits.size() == 1 and int(hits[0]["amount"]) == 18 and hits[0]["kind"] == &"claw", "the target took one claw of 18", hits)
	b.call("set_bot", false)
	_ok(b.call("state") == &"dummy", "bot off -> dummy at once")
	var p0: Vector3 = b.global_position
	await _physics(60)
	_ok(b.global_position.distance_to(p0) < 0.05, "and it stands still (%.3f m in 1 s)" % b.global_position.distance_to(p0))
	b.queue_free()
	t.queue_free()
	await _frames(1)


## The red zone on the floor is the claw's real reach: a sector of strike_reach (2.6 m) and +-strike_half_angle (70°)
## in front, so a player outside it is safe (review: the old 1.4 m ring was smaller than the 2.6 m reach).
func _check_telegraph_shape() -> void:
	var b := _make_beast({"spawn": Vector3(0, 0, -20)})
	var ring: MeshInstance3D = b.get_node("Telegraph")
	var shape: Dictionary = b.call("telegraph_shape")
	var reach := float(ArenaData.BEAST["strike_reach"])
	var half := float(ArenaData.BEAST["strike_half_angle_deg"])
	_ok(absf(float(shape["reach"]) - reach) < 0.001 and absf(float(shape["half_angle_deg"]) - half) < 0.001,
		"the telegraph shape is the claw's reach and cone (%.2f m, %.0f°)" % [float(shape["reach"]), float(shape["half_angle_deg"])])
	var far := 0.0
	var widest := 0.0
	var arrays := ring.mesh.surface_get_arrays(0)
	for v: Vector3 in arrays[Mesh.ARRAY_VERTEX]:
		var r := Vector2(v.x, v.z).length()
		far = maxf(far, r)
		if r > 0.5:
			widest = maxf(widest, rad_to_deg(absf(atan2(v.x, v.z))))
	_ok(far >= reach - 0.001 and far <= reach + 0.07, "the zone's outer edge lies at the claw's reach (%.3f m >= %.2f)" % [far, reach])
	_ok(widest >= half - 0.5, "the zone covers the claw's cone (+-%.1f° >= %.0f°)" % [widest, half])
	_ok(ring.scale.is_equal_approx(Vector3.ONE), "the zone is never scaled down (its edge always shows the real reach)")
	var mat := ring.material_override as ShaderMaterial
	_ok(mat != null and mat.shader != null and not mat.shader.code.contains("TIME"), "the zone's shader uses no TIME (every level)")
	b.queue_free()
	await _frames(1)


## A reset in the middle of a wind-up: idle on its pad, the zone hidden, no telegraph, no claw in the next second.
func _check_reset_during_windup() -> void:
	var b := _make_beast({"spawn": Vector3(0, 0, -20)})
	var t := _make_target(Vector3(0, 0, -18.0))
	b.call("set_target", t)
	b.call("set_target_in_room", true)
	b.call("set_bot", true)
	var ring: MeshInstance3D = b.get_node("Telegraph")
	for i in 240:
		await physics_frame
		if b.call("state") == &"windup":
			break
	await _physics(12)
	_ok(b.call("state") == &"windup" and ring.visible, "it winds up at the target (zone showing)")
	var s0 := int(b.call("strikes"))
	b.call("set_target_in_room", false)
	b.call("reset_to", Vector3(0, 0, -29), 0.0)
	_ok(b.call("state") == &"idle" and not ring.visible and float(b.call("telegraph")) == 0.0,
		"reset during the wind-up: idle (bot on), zone hidden, telegraph 0 (%s)" % str(b.call("state")))
	await _physics(60)
	_ok(int(b.call("strikes")) == s0 and (t.get("hits") as Array).is_empty(), "no claw lands in the second after the reset")
	b.queue_free()
	t.queue_free()
	await _frames(1)


## With the bot on and the player out of the room, the beast stands on its pad facing the entry and does no physics work;
## the player stepping into the room wakes it (review: it used to think every tick at home).
func _check_sleeps_at_home() -> void:
	var b := _make_beast({"spawn": Vector3(0, 0, -29)})
	var t := _make_target(Vector3(0, 0, -12.0))
	b.call("set_target", t)
	b.call("set_target_in_room", false)
	b.call("set_bot", true)
	await _physics(10)
	_ok(b.call("state") == &"idle" and not b.is_physics_processing(), "bot on, player out of the room, beast on its pad: idle and asleep")
	b.call("set_target_in_room", true)
	await _physics(30)
	_ok(b.call("state") == &"chase" and b.is_physics_processing(), "the player stepping into the room wakes it: it chases (%s)" % str(b.call("state")))
	b.call("set_target_in_room", false)
	for i in 900:
		await physics_frame
		if not b.is_physics_processing():
			break
	var p: Vector3 = b.global_position
	_ok(not b.is_physics_processing() and Vector2(p.x, p.z).distance_to(Vector2(0, -29)) <= 0.2,
		"the player gone again: it walks home and falls asleep on its pad (%.2f m from it)" % Vector2(p.x, p.z).distance_to(Vector2(0, -29)))
	b.queue_free()
	t.queue_free()
	await _frames(1)


func _check_chase_round_pillar() -> void:
	var b := _make_beast({"spawn": Vector3(-4.5, 0, -23.5), "face": PI})
	var t := _make_target(Vector3(-4.5, 0, -13.5))
	b.call("set_target", t)
	b.call("set_target_in_room", true)
	b.call("set_bot", true)
	var closest := INF
	var reached := -1.0
	var max_speed := 0.0
	var prev: Vector3 = b.global_position
	for i in 600:
		await physics_frame
		var p: Vector3 = b.global_position
		closest = minf(closest, Vector2(p.x, p.z).distance_to(Vector2(-4.5, -18.5)))
		max_speed = maxf(max_speed, (p - prev).length() * Engine.physics_ticks_per_second)
		prev = p
		if b.call("state") == &"windup":
			reached = i / float(Engine.physics_ticks_per_second)
			break
	_ok(reached > 0.0 and reached < 8.0, "it runs round the pillar to the target and winds up within 8 s (%.2f s)" % reached)
	_ok(closest >= 0.8 + 0.6 - 0.05, "it never enters the pillar (closest centre distance %.2f m)" % closest)
	_ok(max_speed <= 3.7 * 1.05, "it chases at most at 3.7 m/s (%.2f)" % max_speed)
	b.queue_free()
	t.queue_free()
	await _frames(1)


func _check_flash_and_death() -> void:
	var b := _make_beast()
	var f: Node3D = b.call("figure")
	var mi: MeshInstance3D = f.find_children("*", "MeshInstance3D", true, false)[0]
	var hit := {"amount": 12, "kind": &"gun", "point": Vector3(0, 1.4, -29), "dir": Vector3(0, 0, -1), "from": Vector3(0, 1.5, -12),
		"knockback": 0.4, "stagger": false}
	var r: Dictionary = b.call("take_hit", hit)
	_ok(int(r["applied"]) == 12 and int(r["hp"]) == 288 and not bool(r["killed"]), "a rifle hit takes 12 (288 left)")
	_ok(mi.material_overlay != null, "a hit flashes the figure")
	_ok(b.call("state") == &"dummy", "a bullet does not flinch it")
	var t0 := Time.get_ticks_usec()
	await _physics(3)
	_ok(mi.material_overlay != null, "still flashing after 0.05 s")
	await _physics(3)
	_ok(mi.material_overlay == null, "the flash is over after 0.1 s (0.08 s)")
	await _physics(30)
	_ok(not b.is_physics_processing(), "the knockback settled: no physics work again")
	r = b.call("take_hit", {"amount": 25, "kind": &"punch", "point": Vector3(0, 1.4, -29), "dir": Vector3(0, 0, -1),
		"from": Vector3(0, 1, -27.5), "knockback": 3.0, "stagger": true})
	_ok(b.call("state") == &"hit", "a punch flinches it")
	var p0: Vector3 = b.global_position
	await _physics(24)
	var slid := b.global_position.distance_to(p0)
	_ok(slid >= 0.25 and slid <= 0.45, "the punch slides it %.3f m (0.375 expected)" % slid)
	_ok(b.call("state") == &"dummy", "after 0.35 s it is a dummy again")
	var hp := int(b.call("hp"))
	var n := 0
	while bool(b.call("is_alive")) and n < 100:
		b.call("take_hit", hit)
		n += 1
	_ok(n == int(ceil(hp / 12.0)) and int(b.call("hp")) == 0, "%d more rifle hits kill it" % n)
	_ok(b.call("state") == &"dead" and b.collision_layer == 0, "dead: state dead, collision layer 0 (shots and the player pass)")
	var ap: AnimationPlayer = f.call("animation_player")
	_ok(String(ap.current_animation).begins_with("humanoid/die_"), "it plays a death clip (%s)" % ap.current_animation)
	await _physics(200)
	_ok(not ap.is_playing(), "the death clip ended and its last frame is held")
	var r2: Dictionary = b.call("take_hit", hit)
	_ok(int(r2["applied"]) == 0, "a dead beast takes no damage")
	b.call("reset_to", Vector3(0, 0, -29), 0.0)
	_ok(bool(b.call("is_alive")) and int(b.call("hp")) == 300 and b.collision_layer == 8 and b.call("state") == &"dummy",
		"reset: alive, 300 HP, layer 8, a dummy again")
	b.queue_free()
	await _frames(1)


func _check_levels_and_still() -> void:
	var b := _make_beast()
	var f: Node3D = b.call("figure")
	var mi: MeshInstance3D = f.find_children("*", "MeshInstance3D", true, false)[0]
	var mat := mi.material_override as ShaderMaterial
	_ok(mat != null and mat != load("res://assets/shaders/figure_material.tres"), "the kit uses its own copy of figure_material")
	for l in LEVELS:
		b.call("apply_level", l)
		var pv: Variant = mat.get_shader_parameter("per_vertex") if mat != null else null
		_ok(bool(pv) == (l == "lo" or l == "min"), "%s: per_vertex %s" % [l, pv])
		_ok(mat != null and not mat.shader.code.contains("TIME"), "%s: no TIME in the kit's shader" % l)
	var ap: AnimationPlayer = f.call("animation_player")
	b.call("apply_level", "min")
	await _frames(12)
	_ok(not ap.is_playing() and not b.is_physics_processing(), "min: the idle dummy holds a still pose after 10 frames (AnimationPlayer playing: %s)" % ap.is_playing())
	b.call("take_hit", {"amount": 25, "kind": &"punch", "point": Vector3(0, 1.4, -29), "dir": Vector3(0, 0, -1), "knockback": 3.0, "stagger": true})
	await _physics(60)
	await _frames(12)
	_ok(not ap.is_playing() and not b.is_physics_processing(), "min: still again after a flinch")
	b.call("apply_level", "mid")
	await _frames(3)
	_ok(ap.is_playing(), "mid: the idle loop plays")
	b.call("set_paused", true)
	_ok(f.process_mode == Node.PROCESS_MODE_DISABLED and not b.is_physics_processing(), "paused: the figure is disabled, no physics work")
	b.call("set_paused", false)
	b.queue_free()
	await _frames(1)


func _check_fallback() -> void:
	var b := _make_beast({"figure_opts": {"kit": "no_such_kit"}})
	var f: Node3D = b.call("figure")
	_ok(str(b.call("kit_key")) == "egg", "with the kit missing the beast egg stands in (kit_key %s)" % b.call("kit_key"))
	var miss := PackedStringArray()
	for m in FIGURE_API:
		if not f.has_method(m):
			miss.append(m)
	_ok(miss.is_empty(), "the egg has the same figure contract", miss)
	var lens := []
	for lg in LOGICAL:
		lens.append(snappedf(float(f.call("play", StringName(lg))), 0.01))
	_ok(lens.all(func(x: float) -> bool: return x > 0.0), "every logical clip plays on the egg: %s" % str(lens))
	f.call("play", &"idle")
	var t := _make_target(Vector3(0, 0, -27.0))
	b.call("set_target", t)
	b.call("set_target_in_room", true)
	b.call("set_bot", true)
	await _physics(90)
	_ok(int(b.call("strikes")) >= 1 or b.call("state") in [&"windup", &"strike", &"recover"], "the egg winds up and strikes like the kit (state %s)" % b.call("state"))
	b.call("set_bot", false)
	while bool(b.call("is_alive")):
		b.call("take_hit", {"amount": 45, "kind": &"sword", "point": Vector3(0, 1, -29), "dir": Vector3(0, 0, -1), "knockback": 2.0, "stagger": true})
	_ok(b.call("state") == &"dead", "and dies")
	b.queue_free()
	t.queue_free()
	await _frames(1)


# ---- PNGs ----

func _pngs() -> void:
	DirAccess.make_dir_recursive_absolute(_abs(_out_dir))
	# contact sheet: eight figures posed by hand, in a row
	var poses := [["idle", "idle", 2.0, 1.0], ["walk", "walk", 0.3, 1.0], ["run", "run", 0.2, 1.0], ["wind-up", "attack", 0.3, 1.0],
		["blow", "attack", 0.4333, 1.0], ["hit", "hit", 0.12, 1.0], ["hit_heavy", "hit_heavy", 0.2, 1.0], ["die", "die", 3.0, 1.0]]
	var figs := []
	for i in poses.size():
		var f := _manual_figure({"level": "hi"})
		f.position = Vector3(-5.6 + i * 1.6, 0, -6.0)
		f.rotation.y = 0.5
		f.call("set_variant", 0)
		if poses[i][1] in ["walk", "run"]:
			f.call("set_move", 1.5 if poses[i][1] == "walk" else 3.7, poses[i][1] == "run")
			f.call("step", 0.4)
		else:
			f.call("play", StringName(poses[i][1]))
		f.call("step", 0.001)
		f.call("step", poses[i][2])
		if poses[i][0] == "wind-up":
			f.call("set_telegraph", 0.5)
		var lab := Label3D.new()
		lab.text = poses[i][0]
		lab.font_size = 48
		lab.pixel_size = 0.004
		lab.position = Vector3(-5.6 + i * 1.6, 2.5, -6.0)
		lab.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		_stage.add_child(lab)
		figs.append(f)
		figs.append(lab)
	_cam.position = Vector3(0, 1.3, -0.9)
	_cam.look_at(Vector3(0, 1.1, -6.0))
	await _save("hive_beast_clips.png", Vector2i(1280, 400))
	for n in figs:
		n.queue_free()
	await _frames(1)
	# per level: the beast in its wind-up, seen from the shoot line
	var b := _make_beast({"spawn": Vector3(0, 0, -20)})
	var t := _make_target(Vector3(0, 0, -18.2))
	b.call("set_target", t)
	b.call("set_target_in_room", true)
	_cam.position = Vector3(1.5, 1.7, -13.5)
	_cam.look_at(Vector3(0, 1.1, -20))
	for l in LEVELS:
		b.call("apply_level", l)
		b.call("reset_to", Vector3(0, 0, -20), 0.0)
		b.call("set_bot", true)
		for i in 120:
			await physics_frame
			if b.call("state") == &"windup" and float(b.call("telegraph")) > 0.6:
				break
		await _save("hive_beast_%s.png" % l, Vector2i(800, 600))
		b.call("set_bot", false)
	b.queue_free()
	await _frames(1)
	var e := _make_beast({"spawn": Vector3(0, 0, -20), "figure_opts": {"kit": "no_such_kit"}})
	e.call("set_target", t)
	e.call("set_target_in_room", true)
	e.call("set_bot", true)
	for i in 120:
		await physics_frame
		if e.call("state") == &"windup" and float(e.call("telegraph")) > 0.6:
			break
	await _save("hive_beast_fallback.png", Vector2i(800, 600))
	e.queue_free()
	t.queue_free()


func _save(name: String, size: Vector2i) -> void:
	root.size = size
	await _frames(4)
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	var path := _abs(_out_dir).path_join(name)
	var err := img.save_png(path)
	_ok(err == OK, "saved " + name)
	print("      " + path)
