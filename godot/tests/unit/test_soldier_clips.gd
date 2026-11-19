extends "res://tests/testing.gd"
## The infantry soldier's own clip library (assets/figures/soldier/clips.res, made by tools/soldier/bake_clips.sh)
## and how SoldierFigure plays it. Library: the source tag, 26 clips, rotation tracks only on the 23 game bones (face
## bones stay free), the loops (idle walk jog run turn_l turn_r) loop, one-shots do not; the request map (clip_map) from
## the kind / from metadata, hits and falls ordered front / back / left / right (die: back, fwd, spin, knees, so the old
## set_variant 0..2 keep their meaning); foot contacts (one flag per key, heel / flat / ball / "", the gait loops strike
## right at 0 and left at half the cycle, idle and reload stand on both feet); event times within 0.02 s of the game
## values (ArenaData.WEAPONS punch and sword `active`, the fist at full reach near the punch's shot, fire's shot at 0.02
## with key 0 = the aim pose, reload = the gun's reload time with mag_out < mag_in < ready); one thud per fall, every
## fall ends still and lying, die_min_* still from key 6; wrists (wrist × hand) twist and bend <= 45.5° and every joint
## inside rig.py LIMITS (+0.5°, the decomposition of limits_check.py); clips.res <= 1 MB.
## Runtime (manual clock): the walk / jog / run ladder with 5 % hysteresis keeps the step phase; step rates on all five
## bodies (arena W and Shift 150-210 steps/min, deck walk <= 130); melee at rate 1.0 with the shot at the game's active
## time; reload returns the reload time, layers the upper body over a moving gait (legs keep the gait), emits mag_out /
## mag_in / ready, stops at once on play(idle) or a death, fades out for a hit and back in, and does nothing on min; hit
## side from set_hit_from in the figure's frame (min: hit_front only); falls by side (front die_back, back die_fwd, side
## die_spin, a seeded die_knees, the same picks per seed); turning on the spot plays turn_l / turn_r at yaw rate / 2.618
## rad/s (player and enemy) and stops back to idle (none on min, none for the deck figure, none on a jump); min holds
## still within 10 frames after idle and after a death (die_min_*). Fallback: with own_clips_path
## pointing nowhere the figure uses the humanoid.res copy (PLAYER_CLIPS, 1.8x melee, no reload clip, walk at 3 m/s, deck
## speeds = clip speed × S × 1.4); that copy keeps every mapped clip's events and speed with eased wrists and leaves
## humanoid.res untouched (the checks tests/unit/test_soldier.gd makes when no clips.res exists). The shot origin:
## muzzle() is 0.13's standing-aim point on each body (pitched by set_aim) in every state, on every level and without
## clips.res (game logic does not follow the clip pose).

const SCRIPT := "res://scenes/arena/soldier_figure.gd"
const OWN := "res://assets/figures/soldier/clips.res"
const NOWHERE := "res://tests/fixtures/none/clips.res"
const HUMANOID := "res://assets/anim/humanoid.res"
const DT := 1.0 / 30.0
const MAX_BYTES := 1000000
const LOOPS := ["idle", "walk", "jog", "run", "turn_l", "turn_r"]
const TOL_T := 0.02
## the bodies (body id -> S) and the step-rate guard (steps per minute)
const BODIES := {"": 1.1125, "m2": 1.1625, "m3": 1.0625, "f1": 1.0, "f2": 1.08125}
const ARENA_SPM := Vector2(150.0, 210.0)
const DECK_SPM_MAX := 130.0
## tools/soldier/generator/src/py/rig.py LIMITS (degrees, the decomposition of limits_check.py angles())
const LIMITS := {"spine": [[-25, 50], [-15, 15], [-25, 25]], "chest": [[-20, 30], [-35, 35], [-20, 20]],
	"neck": [[-50, 40], [-60, 60], [-35, 35]], "head": [[-25, 20], [-10, 10], [-8, 8]],
	"shoulder": [[-180, 50], [-90, 70], [-40, 180]], "elbow": [[-145, 5], [-80, 80], [-5, 5]],
	"wrist": [[-70, 75], [-10, 10], [-30, 20]], "hand": [[-10, 10], [-5, 5], [-10, 10]],
	"hip": [[-120, 25], [-40, 45], [-30, 45]], "knee": [[-5, 140], [-10, 10], [-3, 3]],
	"ankle": [[-25, 50], [-10, 10], [-20, 25]], "toe": [[-60, 35], [-5, 5], [-5, 5]]}
const BALL := ["shoulder", "hip", "spine", "chest", "neck", "head"]
const LIMIT_PAD := 0.5
const WRIST_MAX := 45.5

var _events: Array = []
var _clock := 0.0


func _tree() -> SceneTree:
	return Engine.get_main_loop() as SceneTree


func _fig(role: StringName, level: String, body := "", seed_v := 7) -> Node3D:
	var f: Node3D = (load(SCRIPT) as GDScript).new()
	_tree().root.add_child(f)
	f.call("set_manual", true)
	f.call("setup", {"role": role, "level": level, "seed": seed_v, "body": body})
	return f


func _steps(f: Node3D, n: int, dt := DT) -> void:
	for i in n:
		_clock += dt
		f.call("step", dt)


func _on_event(kind: StringName) -> void:
	_events.append([kind, _clock])


func _lib() -> AnimationLibrary:
	return load(OWN) as AnimationLibrary


func _cur(f: Node3D) -> String:
	return String((f.call("animation_player") as AnimationPlayer).current_animation).trim_prefix("humanoid/")


## largest angle (degrees) between two figures' shoulders and elbows
func _arms_off(a: Node3D, b: Node3D) -> float:
	var ska: Skeleton3D = a.call("skeleton")
	var skb: Skeleton3D = b.call("skeleton")
	var out := 0.0
	for bn in ["shoulderL", "elbowL", "shoulderR", "elbowR"]:
		out = maxf(out, rad_to_deg(ska.get_bone_pose_rotation(ska.find_bone(bn)).angle_to(skb.get_bone_pose_rotation(skb.find_bone(bn)))))
	return out


func test_library() -> void:
	var lib := _lib()
	assert_true(lib != null, "clips.res loads (tools/soldier/bake_clips.sh)")
	if lib == null:
		return
	assert_eq(str(lib.get_meta("source", "")), "soldier clips 0.14", "the library's source tag")
	assert_eq(lib.get_animation_list().size(), 26, "26 clips")
	var stray := []
	var missing := []
	for n in lib.get_animation_list():
		var a := lib.get_animation(n)
		assert_eq(str(a.get_meta("set", "")), "soldier", "%s: set soldier" % n)
		for t in a.get_track_count():
			var p := String(a.track_get_path(t))
			if not p.begins_with("Skeleton3D:") or not SoldierFigure.GAME_BONES.has(p.substr(11)):
				stray.append("%s:%s" % [n, p])
		for b in SoldierFigure.GAME_BONES:
			if a.find_track(NodePath("Skeleton3D:" + b), Animation.TYPE_ROTATION_3D) < 0:
				missing.append("%s:%s" % [n, b])
		var keys := a.track_get_key_count(a.find_track(NodePath("Skeleton3D:pelvis"), Animation.TYPE_ROTATION_3D))
		if String(n) in LOOPS:
			assert_true(a.loop_mode == Animation.LOOP_LINEAR and absf(a.length - keys / 30.0) < 0.001,
				"%s: a loop, %d keys = %.3f s" % [n, keys, a.length])
		else:
			assert_true(a.loop_mode == Animation.LOOP_NONE and absf(a.length - maxi(keys - 1, 1) / 30.0) < 0.001,
				"%s: a one-shot, %d keys = %.3f s" % [n, keys, a.length])
	assert_eq(stray, [], "tracks only on the 23 game bones (face bones stay free)")
	assert_eq(missing, [], "a rotation track on every game bone of every clip")
	var fa := FileAccess.open(OWN, FileAccess.READ)
	var size := fa.get_length() if fa != null else -1
	assert_true(size > 0 and size <= MAX_BYTES, "clips.res is %d bytes (<= 1 MB)" % size)


func test_map() -> void:
	var S: GDScript = load(SCRIPT)
	assert_true(bool(S.call("own_clips")) and str(S.call("clip_source")) == OWN, "the figure plays the own clips.res")
	var m: Dictionary = S.call("clip_map", false)
	var want := {"idle": ["idle"], "walk": ["walk"], "jog": ["jog"], "run": ["run"], "turn": ["turn_l", "turn_r"],
		"turn_l": ["turn_l"], "turn_r": ["turn_r"], "aim": ["aim"], "fire": ["fire"], "reload": ["reload"],
		"punch": ["punch_0", "punch_1", "punch_2"], "swing": ["swing_0", "swing_1", "swing_2"],
		"hit": ["hit_front", "hit_back", "hit_left", "hit_right"], "hit_heavy": ["hit_heavy"],
		"die": ["die_back", "die_fwd", "die_spin", "die_knees"], "die_min": ["die_min_back", "die_min_fwd"]}
	for k in want:
		assert_eq(m.get(k, []), want[k], "player request %s -> %s" % [k, str(want[k])])
	assert_eq(m.size(), want.size(), "no other requests (%s)" % str(m.keys()))
	var e: Dictionary = S.call("clip_map", true)
	assert_eq(e.get("attack", []), want["punch"], "enemy attack = the punches")
	for k in ["idle", "walk", "jog", "run", "hit", "hit_heavy", "die", "die_min"]:
		assert_eq(e.get(k, []), want[k], "enemy request " + k)
	assert_false(e.has("fire") or e.has("punch") or e.has("swing"), "the enemy map keeps ENEMY_CLIPS' requests")
	var lib := _lib()
	for k in m:
		for n in m[k]:
			assert_true(lib.has_animation(n), "%s names an existing clip %s" % [k, n])
	var f := _fig(&"player", "mid")
	var cn: Dictionary = f.call("clip_names")
	for k in ["idle", "walk", "run", "fire", "punch", "swing", "hit", "die"]:
		assert_true(cn.has(k) and (cn[k] as PackedStringArray).size() > 0, "clip_names has " + k)
	f.free()


func test_contacts() -> void:
	var lib := _lib()
	var ok := ["heel", "flat", "ball", ""]
	for n in lib.get_animation_list():
		var a := lib.get_animation(n)
		var keys := a.track_get_key_count(a.find_track(NodePath("Skeleton3D:pelvis"), Animation.TYPE_ROTATION_3D))
		for side in ["contact_l", "contact_r"]:
			var c: PackedStringArray = a.get_meta(side, PackedStringArray())
			var bad := 0
			for v in c:
				if not ok.has(v):
					bad += 1
			assert_true(c.size() == keys and bad == 0, "%s: one %s flag per key (%d / %d), all known" % [n, side, c.size(), keys])
	for n in ["walk", "jog", "run"]:
		var a := lib.get_animation(n)
		var l: PackedStringArray = a.get_meta("contact_l")
		var r: PackedStringArray = a.get_meta("contact_r")
		var k := l.size()
		var h := ceili(k / 2.0)
		assert_true(r[0] != "" and r[k - 1] == "", "%s: the right foot strikes at t = 0" % n)
		assert_true(l[h] != "" and l[h - 1] == "", "%s: the left foot strikes at half the cycle (key %d)" % [n, h])
	for n in ["idle", "reload"]:
		var a := lib.get_animation(n)
		var both := true
		for i in (a.get_meta("contact_l") as PackedStringArray).size():
			both = both and (a.get_meta("contact_l") as PackedStringArray)[i] != "" and (a.get_meta("contact_r") as PackedStringArray)[i] != ""
		assert_true(both, "%s stands on both feet the whole clip" % n)


func test_event_times() -> void:
	var lib := _lib()
	for pair in [["punch", "punch"], ["swing", "sword"]]:
		var active := float(ArenaData.WEAPONS[pair[1]]["active"])
		var cd := float(ArenaData.WEAPONS[pair[1]]["cooldown"])
		for i in 3:
			var a := lib.get_animation("%s_%d" % [pair[0], i])
			var ev: Array = a.get_meta("events", [])
			assert_true(ev.size() == 1 and str(ev[0]["kind"]) == "shot" and absf(float(ev[0]["t"]) - active) <= TOL_T,
				"%s_%d: shot at %s (the %s's active %.2f s ± %.2f)" % [pair[0], i, str(ev), pair[1], active, TOL_T])
			assert_true(a.length <= cd, "%s_%d: %.3f s, within the %.2f s cooldown" % [pair[0], i, a.length, cd])
	var fire := lib.get_animation("fire")
	var fev: Array = fire.get_meta("events", [])
	assert_true(fev.size() == 1 and absf(float(fev[0]["t"]) - 0.02) < 0.001, "fire: one shot at 0.02 s (aim time 0)")
	var aim := lib.get_animation("aim")
	var same := true
	for b in SoldierFigure.AIM_BONES:
		var qa := aim.rotation_track_interpolate(aim.find_track(NodePath("Skeleton3D:" + b), Animation.TYPE_ROTATION_3D), 0.0)
		var qf := fire.rotation_track_interpolate(fire.find_track(NodePath("Skeleton3D:" + b), Animation.TYPE_ROTATION_3D), 0.0)
		same = same and qa.is_equal_approx(qf)
	assert_true(same, "fire key 0 = the aim pose")
	var rl := lib.get_animation("reload")
	var want := float(ArenaData.WEAPONS["gun"]["reload"])
	assert_within(rl.length, want, 0.001, "reload lasts the gun's reload time %.2f s" % want)
	var kinds := []
	var last := -1.0
	var ordered := true
	for e in rl.get_meta("events", []):
		kinds.append(str(e["kind"]))
		ordered = ordered and float(e["t"]) > last and float(e["t"]) < rl.length
		last = float(e["t"])
	assert_true(kinds == ["mag_out", "mag_in", "ready"] and ordered, "reload events mag_out < mag_in < ready (%s)" % str(kinds))
	# the fist lands at the shot: the punching arm is straightest (least elbow bend after the chamber) within the window
	for i in 3:
		var a := lib.get_animation("punch_%d" % i)
		var elbow := "elbow" + str(a.get_meta("hand", "R"))
		var f := _fig(&"player", "mid")
		var sk: Skeleton3D = f.call("skeleton")
		f.call("set_variant", i)
		f.call("play", &"punch", 1.0)
		var bend := PackedFloat32Array()
		var t := 0.0
		while t < a.length * 0.5:
			f.call("step", 1.0 / 240.0)
			t += 1.0 / 240.0
			bend.append(rad_to_deg(sk.get_bone_pose_rotation(sk.find_bone(elbow)).get_angle()))
		f.free()
		var chamber := 0
		for k in mini(bend.size(), 24):
			if bend[k] > bend[chamber]:
				chamber = k
		var ext := chamber
		for k in range(chamber, bend.size()):
			if bend[k] < bend[ext]:
				ext = k
		var at := (ext + 1) / 240.0
		var active := float(ArenaData.WEAPONS["punch"]["active"])
		assert_true(absf(at - active) <= TOL_T, "punch_%d: the arm is straightest at %.3f s (%.0f° after a %.0f° chamber; active %.2f ± %.2f)"
			% [i, at, bend[ext], bend[chamber], active, TOL_T])


func test_falls() -> void:
	var lib := _lib()
	for n in ["die_back", "die_fwd", "die_spin", "die_knees", "die_min_back", "die_min_fwd"]:
		var a := lib.get_animation(n)
		var thuds := []
		for e in a.get_meta("events", []):
			if str(e["kind"]) == "thud":
				thuds.append(float(e["t"]))
		assert_true(thuds.size() == 1 and thuds[0] < a.length, "%s: one thud (%s)" % [n, str(thuds)])
		# ends still: the keys after the last moving key are equal on every track, and it lies on the ground
		var keys := a.track_get_key_count(0)
		var first_still := keys - 1
		while first_still > 0 and _keys_equal(a, first_still - 1, first_still):
			first_still -= 1
		var still_keys := keys - first_still
		var want_still := 3 if n.begins_with("die_min") else 5
		assert_true(still_keys >= want_still, "%s: ends still (%d equal keys from key %d)" % [n, still_keys, first_still])
		if n.begins_with("die_min"):
			assert_true(first_still <= 6 and keys <= 9, "%s: %d keys, still from key %d (within 10 frames)" % [n, keys, first_still])
		var tp := a.find_track(NodePath("Skeleton3D:pelvis"), Animation.TYPE_POSITION_3D)
		var y0 := (a.track_get_key_value(tp, 0) as Vector3).y
		var y1 := (a.track_get_key_value(tp, a.track_get_key_count(tp) - 1) as Vector3).y
		assert_true(y1 < y0 * 0.45, "%s: lies on the ground at the end (pelvis %.2f -> %.2f rig m)" % [n, y0, y1])
		assert_true(thuds.size() == 1 and thuds[0] <= first_still / 30.0 + 0.001, "%s: the thud comes before it lies still" % n)
	var kn: Array = lib.get_animation("die_knees").get_meta("events", [])
	assert_true(kn.size() == 2 and str(kn[0]["kind"]) == "knees" and float(kn[0]["t"]) < float(kn[1]["t"]), "die_knees: knees, then the thud")


func _keys_equal(a: Animation, k0: int, k1: int) -> bool:
	for t in a.get_track_count():
		if a.track_get_key_count(t) <= k1:
			continue
		var v0: Variant = a.track_get_key_value(t, k0)
		var v1: Variant = a.track_get_key_value(t, k1)
		if v0 is Quaternion and not (v0 as Quaternion).is_equal_approx(v1):
			return false
		if v0 is Vector3 and (v0 as Vector3).distance_to(v1) > 1e-5:
			return false
	return true


func test_wrists_and_limits() -> void:
	var lib := _lib()
	var worst_tw := 0.0
	var worst_sw := 0.0
	var over := {}
	for n in lib.get_animation_list():
		var a := lib.get_animation(n)
		for sd in ["L", "R"]:
			var tw := a.find_track(NodePath("Skeleton3D:wrist" + sd), Animation.TYPE_ROTATION_3D)
			var th := a.find_track(NodePath("Skeleton3D:hand" + sd), Animation.TYPE_ROTATION_3D)
			for k in a.track_get_key_count(tw):
				var q := ((a.track_get_key_value(tw, k) as Quaternion) * (a.track_get_key_value(th, k) as Quaternion)).normalized()
				var t := SoldierFigure.twist_deg(q)
				worst_tw = maxf(worst_tw, absf(t))
				worst_sw = maxf(worst_sw, SoldierFigure.turn_deg(q * Quaternion(Vector3.UP, deg_to_rad(t)).inverse()))
		for b in SoldierFigure.GAME_BONES:
			if b == "pelvis" or b.begins_with("heel"):
				continue
			var base: String = b.left(b.length() - 1) if b.ends_with("L") or b.ends_with("R") else b
			if not LIMITS.has(base):
				continue
			var tr := a.find_track(NodePath("Skeleton3D:" + b), Animation.TYPE_ROTATION_3D)
			for k in a.track_get_key_count(tr):
				var ang := _angles(b, base, a.track_get_key_value(tr, k))
				for ax in 3:
					var lim: Array = LIMITS[base][ax]
					var o := maxf(maxf(float(lim[0]) - ang[ax], ang[ax] - float(lim[1])), 0.0)
					var key := "%s.%s" % [base, "xyz"[ax]]
					if o > float(over.get(key, [0.0])[0]):
						over[key] = [o, "%s %s key %d: %.1f° vs %s" % [n, b, k, ang[ax], str(lim)]]
	assert_true(worst_tw <= WRIST_MAX and worst_sw <= WRIST_MAX,
		"wrists (wrist × hand): twist %.1f°, bend %.1f° (<= %.1f°)" % [worst_tw, worst_sw, WRIST_MAX])
	var bad := []
	for key in over:
		if float(over[key][0]) > LIMIT_PAD:
			bad.append("%s +%.2f° (%s)" % [key, float(over[key][0]), over[key][1]])
	assert_eq(bad, [], "every joint of every clip inside rig.py LIMITS (+%.1f°)" % LIMIT_PAD)


## limits_check.py angles(): ball joints = swing (rotation vector x, z) + twist about y; others the rotation vector;
## the right side mirrors y and z
func _angles(bone: String, base: String, q: Quaternion) -> Vector3:
	var sx := -1.0 if bone.ends_with("R") else 1.0
	var v := Vector3.ZERO
	if base in BALL:
		var tw := Quaternion(0.0, q.y, 0.0, q.w)
		tw = Quaternion.IDENTITY if tw.length_squared() < 1e-12 else tw.normalized()
		var sw := _rotvec(q * tw.inverse())
		v = Vector3(sw.x, _rotvec(tw).y, sw.z)
	else:
		v = _rotvec(q)
	return Vector3(v.x, v.y * sx, v.z * sx)


func _rotvec(q: Quaternion) -> Vector3:
	if q.w < 0.0:
		q = -q
	var s := sqrt(maxf(0.0, 1.0 - q.w * q.w))
	if s <= 1e-9:
		return Vector3.ZERO
	return Vector3(q.x, q.y, q.z) / s * rad_to_deg(2.0 * acos(clampf(q.w, -1.0, 1.0)))


func test_ladder_and_phase() -> void:
	var f := _fig(&"player", "mid")
	var ap: AnimationPlayer = f.call("animation_player")
	var s := 1.1125
	# up: walk below 2.0 x 1.05, jog to 3.6 x 1.05, run above · down: the same lines / 1.05
	for c in [[1.95, "walk"], [2.05, "walk"], [2.15, "jog"], [3.7, "jog"], [3.8, "run"], [3.5, "run"], [3.4, "jog"], [1.92, "jog"], [1.88, "walk"]]:
		f.call("set_move", float(c[0]) * s, false)
		_steps(f, 2)
		var want := float(_lib().get_animation(str(c[1])).get_meta("speed"))
		assert_true(_cur(f) == str(c[1]) and absf(ap.speed_scale - float(c[0]) / want) < 0.001,
			"%.2f rig m/s: %s at rate %.3f (hysteresis 5 %%)" % [float(c[0]), _cur(f), ap.speed_scale])
	# a switch keeps the phase of the step cycle (every gait strikes right at 0, left at half)
	f.call("set_move", 1.5 * s, false)
	_steps(f, 13)
	var ph := ap.current_animation_position / ap.current_animation_length
	f.call("set_move", 3.0 * s, false)
	var ph2 := ap.current_animation_position / ap.current_animation_length
	assert_true(_cur(f) == "jog" and absf(ph - ph2) < 0.001, "walk -> jog keeps the phase (%.3f -> %.3f)" % [ph, ph2])
	_steps(f, 7)
	ph = ap.current_animation_position / ap.current_animation_length
	f.call("set_move", 4.5 * s, false)
	ph2 = ap.current_animation_position / ap.current_animation_length
	assert_true(_cur(f) == "run" and absf(ph - ph2) < 0.001, "jog -> run keeps the phase (%.3f -> %.3f)" % [ph, ph2])
	# backwards stays the walk played in reverse (no running backwards)
	f.call("set_move_dir", Vector2(0, -1), 3.0, false)
	_steps(f, 2)
	assert_true(_cur(f) == "walk" and ap.speed_scale < 0.0, "backwards at 3 m/s: the walk in reverse (%.3f)" % ap.speed_scale)
	f.free()


func test_step_rates() -> void:
	for body: String in BODIES:
		var f := _fig(&"player", "mid", body)
		var ap: AnimationPlayer = f.call("animation_player")
		var sc := (f.call("skeleton") as Skeleton3D).motion_scale
		assert_within(sc, float(BODIES[body]), 0.0001, "body '%s': S %.5f" % [body, sc])
		for c in [["W", float(ArenaData.PLAYER["walk"]), false], ["Shift", float(ArenaData.PLAYER["run"]), true]]:
			f.call("set_move", float(c[1]), bool(c[2]))
			_steps(f, 2)
			var spm := 120.0 * absf(ap.speed_scale) / ap.current_animation_length
			assert_true(spm >= ARENA_SPM.x and spm <= ARENA_SPM.y, "body '%s' arena %s %.1f m/s: %s at %.1f steps/min (%d-%d)"
				% [body, c[0], float(c[1]), _cur(f), spm, int(ARENA_SPM.x), int(ARENA_SPM.y)])
		f.free()
		var d := _fig(&"deck", "mid", body)
		var dap: AnimationPlayer = d.call("animation_player")
		var sp: Vector2 = d.call("deck_speeds")
		var hum := load(HUMANOID) as AnimationLibrary
		assert_true(absf(sp.x - float(hum.get_animation(&"walk").get_meta("speed")) * sc * 1.4) < 0.001
			and absf(sp.y - float(hum.get_animation(&"run").get_meta("speed")) * sc * 1.4) < 0.001,
			"body '%s': deck speeds %s = humanoid walk / run speed × S × 1.4 (gameplay values, unchanged)" % [body, str(sp)])
		d.call("set_move", sp.x, false)
		_steps(d, 2)
		var dspm := 120.0 * absf(dap.speed_scale) / dap.current_animation_length
		assert_true(_cur(d) == "walk" and dspm > 60.0 and dspm <= DECK_SPM_MAX, "body '%s' deck walk %.2f m/s: %s at %.1f steps/min (<= %d)"
			% [body, sp.x, _cur(d), dspm, int(DECK_SPM_MAX)])
		d.free()


func test_melee_and_reload() -> void:
	var f := _fig(&"player", "mid")
	var ap: AnimationPlayer = f.call("animation_player")
	f.connect("clip_event", _on_event)
	for c in [["punch", "punch"], ["swing", "sword"]]:
		_events.clear()
		_clock = 0.0
		var d := float(f.call("play", StringName(c[0]), 1.0))
		var want := _lib().get_animation(str(c[0]) + "_0").length
		assert_true(absf(d - want) < 0.001 and is_equal_approx(ap.get_playing_speed(), 1.0), "%s plays at rate 1.0 (%.3f s)" % [c[0], d])
		_steps(f, int(ceil(d * 120.0)) + 4, 1.0 / 120.0)
		var shot := -1.0
		for e in _events:
			if e[0] == &"shot":
				shot = float(e[1])
		var active := float(ArenaData.WEAPONS[c[1]]["active"])
		assert_true(absf(shot - active) <= TOL_T, "%s: the shot event at %.3f s (the game's active %.2f)" % [c[0], shot, active])
	f.free()
	# reload: the upper body over a moving gait; a twin without reload has the same legs
	var a := _fig(&"player", "mid")
	var b := _fig(&"player", "mid")
	a.connect("clip_event", _on_event)
	for x in [a, b]:
		x.call("set_weapon", &"gun")
		x.call("set_move", 3.0, false)
	_steps(a, 3)
	_steps(b, 3)
	_events.clear()
	_clock = 0.0
	var rl := float(a.call("play", &"reload", 1.0))
	assert_within(rl, float(ArenaData.WEAPONS["gun"]["reload"]), 0.001, "play(reload) returns the gun's reload time")
	_steps(a, 24, 1.0 / 30.0)
	_steps(b, 24, 1.0 / 30.0)
	var ska: Skeleton3D = a.call("skeleton")
	var skb: Skeleton3D = b.call("skeleton")
	var legs_same := true
	for bn in ["pelvis", "hipL", "kneeL", "ankleL", "hipR", "kneeR", "ankleR", "spine"]:
		legs_same = legs_same and ska.get_bone_pose_rotation(ska.find_bone(bn)).is_equal_approx(skb.get_bone_pose_rotation(skb.find_bone(bn)))
	var arm := 0.0
	for bn in ["shoulderL", "elbowL", "shoulderR", "elbowR"]:
		arm = maxf(arm, rad_to_deg(ska.get_bone_pose_rotation(ska.find_bone(bn)).angle_to(skb.get_bone_pose_rotation(skb.find_bone(bn)))))
	assert_true(_cur(a) == "jog" and legs_same, "reloading while moving: the legs keep the jog (%s)" % _cur(a))
	assert_true(arm > 5.0, "reloading: the arms take the reload pose (%.1f° from the plain jog)" % arm)
	_clock = 24.0 / 30.0
	_steps(a, 30, 1.0 / 30.0)
	_steps(b, 30, 1.0 / 30.0)
	var kinds := []
	for e in _events:
		kinds.append(String(e[0]))
	assert_eq(kinds, ["mag_out", "mag_in", "ready"], "reload emits mag_out, mag_in, ready")
	var back := 0.0
	for bn in ["shoulderL", "elbowL", "shoulderR", "elbowR"]:
		back = maxf(back, rad_to_deg(ska.get_bone_pose_rotation(ska.find_bone(bn)).angle_to(skb.get_bone_pose_rotation(skb.find_bone(bn)))))
	assert_true(back < 0.5, "after the reload the arms are back on the gait's aim pose (%.2f°)" % back)
	a.free()
	b.free()
	# a reload cancelled 0.2 s in (before mag_out) by play(&"idle") (ArenaPlayer's reload_cancel) or by a death: the
	# layer goes at once (the arms match a twin that never reloaded) and no mag event follows
	for stop in [&"idle", &"die"]:
		var c := _fig(&"player", "mid")
		var d := _fig(&"player", "mid")
		c.connect("clip_event", _on_event)
		for x in [c, d]:
			x.call("set_weapon", &"gun")
			_steps(x, 3)
		c.call("play", &"reload", 1.0)
		_steps(c, 6)
		_steps(d, 6)
		_events.clear()
		for x in [c, d]:
			x.call("play", stop, 1.0)
			_steps(x, 9)
		var off := _arms_off(c, d)
		_steps(c, 45)
		var mags := []
		for e in _events:
			if String(e[0]) in ["mag_out", "mag_in", "ready"]:
				mags.append(String(e[0]))
		assert_true(off < 0.5 and mags.is_empty(), "reload cancelled by play(%s): no layer (%.2f° from the twin), no mag events %s" % [stop, off, str(mags)])
		c.free()
		d.free()
	# a hit 0.2 s into a reload: the arms leave the reload pose for the hit (the layer fades out) and take it again
	# while reload time remains; the reload's clock runs on, so all three mag events still come
	var h := _fig(&"player", "mid")
	var k := _fig(&"player", "mid")
	h.connect("clip_event", _on_event)
	for x in [h, k]:
		x.call("set_weapon", &"gun")
		_steps(x, 3)
	_events.clear()
	h.call("play", &"reload", 1.0)
	_steps(h, 6)
	_steps(k, 6)
	var hd := 0.0
	for x in [h, k]:
		hd = float(x.call("play", &"hit", 1.0))
		_steps(x, 6)
	var in_hit := _arms_off(h, k)
	var n_back := int(ceil(hd / DT)) + 1
	for x in [h, k]:
		_steps(x, n_back)
	var after := _arms_off(h, k)
	var t_c := 0.4 + n_back * DT
	assert_true(t_c + 0.15 < 1.6, "the hit (%.2f s) ends with reload time left (checked at %.2f s of 1.6)" % [hd, t_c])
	assert_true(in_hit < 0.5 and after > 5.0, "a hit during the reload: the arms leave the reload pose (%.2f°) and take it again after the hit (%.1f°)" % [in_hit, after])
	_steps(h, 50 - 6 - n_back)
	var kinds2 := []
	for e in _events:
		if String(e[0]) in ["mag_out", "mag_in", "ready"]:
			kinds2.append(String(e[0]))
	assert_eq(kinds2, ["mag_out", "mag_in", "ready"], "a hit during the reload: mag_out, mag_in, ready still come")
	h.free()
	k.free()
	# min: the same return value, no layer, nothing per frame
	var m := _fig(&"player", "min")
	m.connect("clip_event", _on_event)
	_steps(m, 10)
	_events.clear()
	assert_within(float(m.call("play", &"reload", 1.0)), 1.6, 0.001, "min: play(reload) returns the same time")
	_steps(m, 60)
	assert_true(_events.is_empty() and bool(m.call("is_still")) and not (m.call("animation_player") as AnimationPlayer).is_playing(),
		"min: no reload layer, still, no events")
	m.free()


func test_hit_sides() -> void:
	var f := _fig(&"player", "hi")
	f.rotation.y = 0.7
	var fwd := f.global_basis.z
	var left := f.global_basis.x
	for c in [[fwd, "hit_front"], [-fwd, "hit_back"], [left, "hit_left"], [-left, "hit_right"], [fwd * 0.6 + left, "hit_left"]]:
		f.call("set_hit_from", c[0])
		f.call("play", &"hit", 1.0)
		assert_eq(_cur(f), str(c[1]), "hit from %s (figure frame) plays %s" % [str(c[0]), c[1]])
		_steps(f, 20)
	f.call("play", &"hit", 1.0)
	assert_eq(_cur(f), "hit_front", "no side known: hit_front")
	f.free()
	var m := _fig(&"player", "min")
	for d in [Vector3(0, 0, -1), Vector3(1, 0, 0)]:
		m.call("set_hit_from", d)
		m.call("play", &"hit", 1.0)
		assert_eq(_cur(m), "hit_front", "min: hit_front only (from %s)" % str(d))
		_steps(m, 20)
	m.free()


func test_falls_by_side() -> void:
	var seen := {}
	for seed_v in range(1, 25):
		var picks := []
		for run in 2:
			var f := _fig(&"player", "mid", "", seed_v)
			var got := []
			for c in [[Vector3(0, 0, 1), "die_back"], [Vector3(0, 0, -1), "die_fwd"], [Vector3(1, 0, 0), "die_spin"], [Vector3(-1, 0, 0), "die_spin"]]:
				f.call("set_hit_from", c[0])
				f.call("play", &"die", 1.0)
				var n := _cur(f)
				got.append(n)
				seen[n] = true
				if run == 0:
					assert_true(n == str(c[1]) or n == "die_knees", "seed %d: hit from %s falls %s (%s or die_knees)" % [seed_v, str(c[0]), n, c[1]])
				f.call("play", &"idle", 1.0)
			picks.append(got)
			f.free()
		assert_eq(picks[0], picks[1], "seed %d: the same falls again (seeded)" % seed_v)
	assert_true(seen.has("die_knees") and seen.has("die_back") and seen.has("die_fwd") and seen.has("die_spin"),
		"over 24 seeds every fall shows up (%s)" % str(seen.keys()))
	# min: die_min_* by side, still within 10 frames, then nothing moves
	for c in [[Vector3(0, 0, 1), "die_min_back"], [Vector3(0, 0, -1), "die_min_fwd"]]:
		var m := _fig(&"player", "min")
		var ap: AnimationPlayer = m.call("animation_player")
		var sk: Skeleton3D = m.call("skeleton")
		_steps(m, 10)
		m.call("set_hit_from", c[0])
		m.call("play", &"die", 1.0)
		assert_eq(_cur(m), str(c[1]), "min: hit from %s falls %s" % [str(c[0]), c[1]])
		var n := 0
		while n < 10 and ap.is_playing():
			m.call("step", DT)
			n += 1
		var p0 := sk.get_bone_pose_position(sk.find_bone("pelvis"))
		var q0 := sk.get_bone_pose_rotation(sk.find_bone("spine"))
		_steps(m, 10)
		assert_true(not ap.is_playing() and n <= 10 and sk.get_bone_pose_position(sk.find_bone("pelvis")).is_equal_approx(p0)
			and sk.get_bone_pose_rotation(sk.find_bone("spine")).is_equal_approx(q0), "min: still within 10 frames after the fall (%d)" % n)
		assert_false(m.is_processing() or m.is_physics_processing(), "min: no _process on the figure")
		m.free()


func test_turns() -> void:
	var f := _fig(&"player", "mid")
	var ap: AnimationPlayer = f.call("animation_player")
	_steps(f, 3)
	var rate := deg_to_rad(150.0)
	var p0 := f.position
	for i in 30:
		f.rotation.y += rate * DT
		f.call("step", DT)
	assert_true(_cur(f) == "turn_l" and absf(ap.speed_scale - 1.0) < 0.05, "turning left at 150°/s: turn_l at rate %.3f" % ap.speed_scale)
	for i in 30:
		f.rotation.y -= rate * 0.75 * DT
		f.call("step", DT)
	assert_true(_cur(f) == "turn_r" and absf(ap.speed_scale - 0.75) < 0.05, "turning right at 112°/s: turn_r at rate %.3f" % ap.speed_scale)
	_steps(f, 15)
	assert_eq(_cur(f), "idle", "stopped turning: back to idle")
	assert_true(f.position.is_equal_approx(p0), "turning does not move the figure")
	f.call("set_move", 0.0, false)
	f.rotation.y += 1.0
	_steps(f, 6)
	assert_eq(_cur(f), "idle", "a jump of the yaw (placing the figure) is not a turn")
	# a quick snap under the jump size (0.3 rad in one 60 fps frame = 18 rad/s: a respawn place() or entering shoot
	# mode) is a placement too
	f.rotation.y += 0.3
	_steps(f, 12, 1.0 / 60.0)
	assert_eq(_cur(f), "idle", "a 0.3 rad snap in one 60 fps frame is not a turn")
	# a level change restarts the yaw watch: no turn carried over hi -> min -> mid
	for i in 10:
		f.rotation.y += rate * DT
		f.call("step", DT)
	f.call("apply_level", "min")
	f.call("apply_level", "mid")
	_steps(f, 2)
	assert_eq(_cur(f), "idle", "after a level change the figure is not left turning (%s)" % _cur(f))
	f.free()
	# the enemy role turns as well (_turn_ok: every role but the deck figure; the enemy map carries turn_l / turn_r)
	var en := _fig(&"enemy", "mid")
	var eap: AnimationPlayer = en.call("animation_player")
	_steps(en, 3)
	for i in 30:
		en.rotation.y += rate * DT
		en.call("step", DT)
	assert_true(_cur(en) == "turn_l" and absf(eap.speed_scale - 1.0) < 0.05, "enemy turning left at 150°/s: turn_l at rate %.3f (%s)" % [eap.speed_scale, _cur(en)])
	for i in 30:
		en.rotation.y -= rate * DT
		en.call("step", DT)
	assert_eq(_cur(en), "turn_r", "enemy turning right at 150°/s: turn_r")
	en.free()
	for c in [[&"player", "min"], [&"enemy", "min"], [&"deck", "mid"]]:
		var g := _fig(c[0], c[1])
		var gap: AnimationPlayer = g.call("animation_player")
		_steps(g, 12)
		for i in 30:
			g.rotation.y += rate * DT
			g.call("step", DT)
		assert_true(not _cur(g).begins_with("turn"), "%s on %s: no turn clip (%s)" % [c[0], c[1], _cur(g)])
		if c[1] == "min":
			assert_true(bool(g.call("is_still")) and not gap.is_playing(), "min: turning keeps the still pose")
		g.free()


func test_min_idle_still() -> void:
	var f := _fig(&"player", "min")
	var ap: AnimationPlayer = f.call("animation_player")
	f.call("set_move", 3.0, false)
	_steps(f, 3)
	assert_true(_cur(f) == "jog" and ap.is_playing(), "min: the loops play while moving (%s)" % _cur(f))
	f.call("set_move", 0.0, false)
	var n := 0
	while n < 10 and not bool(f.call("is_still")):
		f.call("step", DT)
		n += 1
	assert_true(bool(f.call("is_still")) and not ap.is_playing(), "min: still within 10 frames of stopping (%d)" % n)
	f.free()


## the shot origin (0.14 must-fix: game logic must not follow the clip pose; ArenaPlayer._fire_gun casts the hit ray
## from muzzle()). The reference is 0.13's (bfc8217) muzzle on the humanoid copy, standing with the gun, figure at the
## origin, the mean over the copy's whole 8.4 s idle loop (review014/r2/probe_muzzle.gd's method: one step per 60 fps
## frame; the old point swayed with the idle by up to 2 cm), per body and aim pitch -0.3 / 0 / +0.3
const MUZZLE_REF := {
	"": [Vector3(-0.0621, 1.3766, 0.8679), Vector3(-0.0621, 1.4977, 0.8729), Vector3(-0.0621, 1.6164, 0.8489)],
	"f1": [Vector3(-0.0558, 1.2374, 0.8155), Vector3(-0.0558, 1.3462, 0.8200), Vector3(-0.0558, 1.4530, 0.7985)],
	"f2": [Vector3(-0.0604, 1.3380, 0.8533), Vector3(-0.0604, 1.4556, 0.8582), Vector3(-0.0604, 1.5710, 0.8349)],
	"m2": [Vector3(-0.0649, 1.4385, 0.8911), Vector3(-0.0649, 1.5650, 0.8964), Vector3(-0.0649, 1.6891, 0.8713)],
	"m3": [Vector3(-0.0593, 1.3148, 0.8446), Vector3(-0.0593, 1.4304, 0.8494), Vector3(-0.0593, 1.5438, 0.8265)],
}
const MUZZLE_PITCH := [-0.3, 0.0, 0.3]


func test_muzzle() -> void:
	var base_p := Vector3.INF
	for body in MUZZLE_REF:
		var f := _fig(&"player", "mid", body)
		f.call("set_weapon", &"gun")
		_steps(f, 3)
		var worst := 0.0
		for i in MUZZLE_PITCH.size():
			f.call("set_aim", MUZZLE_PITCH[i])
			var p: Vector3 = (f.call("muzzle") as Node3D).global_position
			worst = maxf(worst, p.distance_to(MUZZLE_REF[body][i]))
			if body == "" and i == 2:
				base_p = p
		assert_true(worst < 0.002, "%s: the muzzle is 0.13's standing aim at pitch 0 / ±0.3 (worst %.2f mm)" % [body if body != "" else "base", worst * 1000.0])
		f.free()
	# not the pose: the same point standing, jogging, running, hit and reloading on every level (base body, pitch +0.3)
	for lv in ["hi", "mid", "lo", "min"]:
		var g := _fig(&"player", lv)
		g.call("set_weapon", &"gun")
		g.call("set_aim", 0.3)
		var worst := 0.0
		for st in [[0.0, false, &""], [3.0, false, &""], [5.0, true, &""], [0.0, false, &"hit"], [0.0, false, &"reload"]]:
			g.call("set_move", st[0], st[1])
			if st[2] != &"":
				g.call("play", st[2], 1.0)
			for i in 12:
				_steps(g, 1)
				worst = maxf(worst, (g.call("muzzle") as Node3D).global_position.distance_to(base_p))
		assert_true(worst < 0.00001, "%s: the muzzle does not follow the clips (standing, jog, run, hit, reload: %.3f mm)" % [lv, worst * 1000.0])
		g.free()
	# in the world: the point turns and moves with the figure
	var w := _fig(&"player", "mid")
	w.call("set_weapon", &"gun")
	w.call("set_aim", 0.3)
	w.position = Vector3(2.0, 0.5, -3.0)
	w.rotation.y = 1.0
	_steps(w, 2)
	var wp: Vector3 = (w.call("muzzle") as Node3D).global_position
	assert_true(wp.distance_to(w.global_transform * base_p) < 0.00002, "the muzzle turns and moves with the figure", str(wp))
	w.free()
	# without clips.res (the humanoid copy) the same point; the own clips are restored before the assertion
	var S: GDScript = load(SCRIPT)
	S.set("own_clips_path", NOWHERE)
	S.call("reload_clips")
	var fb := _fig(&"player", "mid")
	fb.call("set_weapon", &"gun")
	fb.call("set_aim", 0.3)
	_steps(fb, 3)
	var fp: Vector3 = (fb.call("muzzle") as Node3D).global_position
	fb.free()
	S.set("own_clips_path", OWN)
	S.call("reload_clips")
	assert_true(fp.distance_to(base_p) < 0.00001, "without clips.res: the same muzzle", str(fp))


func test_fallback() -> void:
	# the figure is switched to the humanoid copy only inside _fallback_facts (no assertions there); the own clips are
	# restored right after it, before any assertion, so an error cannot leave later suites on the fallback
	var S: GDScript = load(SCRIPT)
	S.set("own_clips_path", NOWHERE)
	S.call("reload_clips")
	var got := _fallback_facts(S)
	S.set("own_clips_path", OWN)
	S.call("reload_clips")
	assert_true(bool(S.call("own_clips")), "restored: the own clips again")
	assert_false(bool(got.get("own", true)), "no clips.res: the humanoid.res copy")
	assert_true(bool(got.get("map_is_player", false)), "no clips.res: PLAYER_CLIPS")
	assert_within(float(got.get("punch", -1.0)), float(got.get("punch_want", -2.0)), 0.001, "fallback: bash_0 at 1.8x (%.3f s)" % float(got.get("punch", -1.0)))
	assert_eq(float(got.get("reload", -1.0)), 0.0, "fallback: no reload clip")
	assert_eq(str(got.get("at_3ms", "")), "walk", "fallback: 3 m/s walks (no jog)")
	assert_within(float(got.get("deck_walk", -1.0)), float(got.get("deck_walk_want", -2.0)), 0.001, "fallback: deck walk speed formula")
	assert_within(float(got.get("deck_run", -1.0)), float(got.get("deck_run_want", -2.0)), 0.001, "fallback: deck run speed formula")
	assert_false(str(got.get("turning", "turn")).begins_with("turn"), "fallback: no turn clips")
	# the soldier's copy of humanoid.res (clip_library() without clips.res): every mapped clip keeps its events and speed,
	# its wrists are eased (wrist and hand twist and bend <= 45.5°, the hand still, no wrist / hand position tracks), and
	# the shared humanoid.res itself is untouched (bash_0's fist still turns past 120°)
	var clips: Dictionary = got.get("clips", {})
	assert_true(clips.size() >= 10, "fallback copy: %d mapped clips checked" % clips.size())
	for n in clips:
		var c: Dictionary = clips[n]
		assert_true(bool(c.get("events_kept", false)) and bool(c.get("speed_kept", false)), "%s: events and speed kept" % n)
		assert_true(float(c.get("twist", 99.0)) <= 45.5 and float(c.get("bend", 99.0)) <= 45.5 and float(c.get("hand", 99.0)) < 0.01,
			"%s: wrists eased (twist %.0f°, bend %.0f°, hand %.1f°)" % [n, float(c.get("twist", 99.0)), float(c.get("bend", 99.0)), float(c.get("hand", 99.0))])
		assert_eq(int(c.get("pos_tracks", -1)), 0, "%s: no wrist / hand position tracks" % n)
	assert_true(float(got.get("bash0_hand", 0.0)) > 120.0, "humanoid.res itself is untouched (bash_0 hand still turns %.0f°)" % float(got.get("bash0_hand", 0.0)))


## everything test_fallback checks, gathered while the figure plays the humanoid copy (no assertions here)
func _fallback_facts(S: GDScript) -> Dictionary:
	var got := {"own": bool(S.call("own_clips")), "map_is_player": S.call("clip_map", false) == S.get("PLAYER_CLIPS")}
	var lib: AnimationLibrary = S.call("clip_library")
	var src := load(HUMANOID) as AnimationLibrary
	if lib == null or src == null:
		return got
	var f := _fig(&"player", "mid")
	f.call("set_variant", 0)
	got["punch"] = float(f.call("play", &"punch", 1.0))
	got["punch_want"] = lib.get_animation(&"bash_0").length / float(S.get("MELEE_RATE"))
	got["reload"] = float(f.call("play", &"reload", 1.0))
	_steps(f, 20)
	f.call("set_move", 3.0, false)
	_steps(f, 2)
	got["at_3ms"] = _cur(f)
	var sp: Vector2 = f.call("deck_speeds")
	got["deck_walk"] = sp.x
	got["deck_walk_want"] = float(lib.get_animation(&"walk").get_meta("speed")) * 1.1125 * 1.4
	got["deck_run"] = sp.y
	got["deck_run_want"] = float(lib.get_animation(&"run").get_meta("speed")) * 1.1125 * 1.4
	for i in 30:
		f.call("set_move", 0.0, false)
		f.rotation.y += deg_to_rad(150.0) * DT
		f.call("step", DT)
	got["turning"] = _cur(f)
	f.free()
	var names := {}
	for m in [S.get("PLAYER_CLIPS"), S.get("ENEMY_CLIPS")]:
		for k in m:
			for n in m[k]:
				names[n] = true
	var clips := {}
	for n in names:
		if not lib.has_animation(n) or not src.has_animation(n):
			clips[n] = {}
			continue
		var a := lib.get_animation(n)
		var o := src.get_animation(n)
		var c := {"events_kept": a.get_meta("events", []) == o.get_meta("events", []),
			"speed_kept": float(a.get_meta("speed", 0.0)) == float(o.get_meta("speed", 0.0)),
			"twist": 0.0, "bend": 0.0, "hand": 0.0, "pos_tracks": 0}
		for sd in ["L", "R"]:
			var tw := a.find_track(NodePath("Skeleton3D:wrist" + sd), Animation.TYPE_ROTATION_3D)
			for k in a.track_get_key_count(tw):
				var q: Quaternion = a.track_get_key_value(tw, k)
				var t := float(S.call("twist_deg", q))
				c["twist"] = maxf(float(c["twist"]), absf(t))
				c["bend"] = maxf(float(c["bend"]), float(S.call("turn_deg", q * Quaternion(Vector3.UP, deg_to_rad(t)).inverse())))
			var th := a.find_track(NodePath("Skeleton3D:hand" + sd), Animation.TYPE_ROTATION_3D)
			for k in a.track_get_key_count(th):
				c["hand"] = maxf(float(c["hand"]), float(S.call("turn_deg", a.track_get_key_value(th, k))))
			for b in ["wrist" + sd, "hand" + sd]:
				if a.find_track(NodePath("Skeleton3D:" + b), Animation.TYPE_POSITION_3D) >= 0:
					c["pos_tracks"] = int(c["pos_tracks"]) + 1
		clips[n] = c
	got["clips"] = clips
	var b0 := src.get_animation(&"bash_0")
	var hr := b0.find_track(NodePath("Skeleton3D:handR"), Animation.TYPE_ROTATION_3D)
	var big := 0.0
	for k in b0.track_get_key_count(hr):
		big = maxf(big, float(S.call("turn_deg", b0.track_get_key_value(hr, k))))
	got["bash0_hand"] = big
	return got
