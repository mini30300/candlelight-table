extends "res://tests/testing.gd"
## Ragdoll deaths (ใหม่ 0.14 item 3, ARENA_SPEC §9.8): scenes/arena/soldier_ragdoll.gd on the soldier figure, hi and
## mid, with real Jolt physics. The physics tests await frames (tests/run_tests.gd and tests/selftest.gd wait for
## them); to keep the run short the clock runs 4x (physics_ticks_per_second 240 with time_scale 4, so every step is
## still 1/60 s of game time, as in the game) and is put back after each test.
##  - built: 15 capsules on hi, 13 on mid, fitted from body_lo (radii, lengths, a 40–100 kg total); prebuilt inactive
##    for the player (simulator off, no body simulating, top level); none on lo, min or a manual (hero card) figure;
##    limits copied from rig.py LIMITS (checked against the file when tools/ is there), the right side mirrored, mid
##    merging spine into chest and neck into head, none past ±150°;
##  - 8 push directions (two waves of four, the hi cap): each falls toward its push (pelvis >= 0.4 m along it), settles
##    or is frozen within 4 s with no physical bone left simulating and its floor gone, peak body speed <= 12 m/s (a body toppling with the push; an explosion is far faster), pelvis
##    travel <= 2.5 m, joints held (no bone more than 4 cm from where its parent puts it), knees and elbows bend only
##    their own way and every joint stays within its limits + 25°, no capsule more than 4 cm under the ground while
##    falling (impacts, the feet under the body's weight) or 1.5 cm at rest, the figure (the game position) unmoved;
##  - wound_point follows the ragdoll: it moves with the physics pose during the fall and lies low after it;
##  - mid: six deaths at once, never more than two falling, exactly two fell, the other four played their clip;
##  - the m2 and f1 bodies fall and settle within the same bounds;
##  - 0.14 review: every elbow and knee keeps a bend of at least 8° after the fall (the ragdoll's own 10° stop), and
##    three front hits (seeds) end in different poses (trunk roll spread > 20° or a knee bent > 30°), none laid out
##    straight (both arms along the trunk, both knees straight, the feet together);
##  - the hand-over runs on physics ticks: two figures of the same seed killed the same way start the fall identically;
##  - getting up (play idle) during the fall stops it at once: nothing simulating, the live count back down.

const SCRIPT := "res://scenes/arena/soldier_figure.gd"
const RIG_PY := "../tools/soldier/generator/src/py/rig.py"
const DIRS := [Vector3(0, 0, -1), Vector3(1, 0, -1), Vector3(1, 0, 0), Vector3(1, 0, 1), Vector3(0, 0, 1),
	Vector3(-1, 0, 1), Vector3(-1, 0, 0), Vector3(-1, 0, -1)]
const PUSH := 2.4
const SPACING := 12.0
const STEP := 1.0 / 60.0          # game time of one physics step while _fast(true)
const SIM := ["spine", "chest", "neck", "head", "shoulderL", "elbowL", "shoulderR", "elbowR", "hipL", "kneeL",
	"ankleL", "hipR", "kneeR", "ankleR"]

var S: GDScript
var _ticks := 60
var _scale := 1.0


func _tree() -> SceneTree:
	return Engine.get_main_loop() as SceneTree


func _fast(on: bool) -> void:
	if on:
		_ticks = Engine.physics_ticks_per_second
		_scale = Engine.time_scale
		Engine.physics_ticks_per_second = 240
		Engine.time_scale = 4.0
	else:
		Engine.physics_ticks_per_second = _ticks
		Engine.time_scale = _scale


func _new_fig(level: String, seed_v: int, pos: Vector3, body := "", extra := {}) -> Node3D:
	S = load(SCRIPT)
	var f: Node3D = S.new()
	_tree().root.add_child(f)
	f.global_position = pos
	var o := {"role": &"player", "level": level, "seed": seed_v}
	if body != "":
		o["body"] = body
	o.merge(extra, true)
	f.call("setup", o)
	return f


func _kill(f: Node3D, dir: Vector3) -> void:
	f.call("set_hit_from", -dir)
	f.call("set_hit_push", dir * PUSH)
	f.call("play", &"die", 1.0)


## Physics steps until every figure's ragdoll started and stopped (or limit s of game time). Per figure: started (s),
## lasted (s from start to stop, -1 = still falling), peak speed, travel (pelvis body from the figure, m), dip (deepest
## capsule under the floor, m) and dip_by (that body), wp_moved (largest move of wound_point(0) while falling, m),
## p_start (the pelvis body from the figure on the first physics frame of the fall); plus "live" (most at once).
func _watch(figs: Array, limit := 4.5) -> Dictionary:
	var st := []
	for f: Node3D in figs:
		st.append({"started": -1.0, "lasted": -1.0, "peak": 0.0, "travel": 0.0, "dip": 0.0, "dip_by": "", "wp0": Vector3.INF,
			"wp_moved": 0.0, "pos": f.global_position, "p_start": Vector3.INF})
	var t := 0.0
	var live := 0
	while t < limit:
		await _tree().physics_frame
		t += STEP
		live = maxi(live, SoldierRagdoll.live_count())
		var busy := false
		for i in figs.size():
			var f: Node3D = figs[i]
			var s: Dictionary = st[i]
			var rag: SoldierRagdoll = f.call("ragdoll")
			var falling := rag != null and rag.is_falling()
			if falling and float(s["started"]) < 0.0:
				s["started"] = t
				s["p_start"] = rag.bodies()[0].global_position - f.global_position
			if float(s["started"]) >= 0.0 and float(s["lasted"]) < 0.0 and not falling:
				s["lasted"] = t - float(s["started"])
				s["peak"] = rag.peak_speed() if rag != null else 0.0
			if float(s["lasted"]) < 0.0 and (float(s["started"]) < 0.0 or falling):
				busy = busy or t < 0.6 or falling
			if not falling:
				continue
			var floor_y := f.global_position.y
			for pb: PhysicalBone3D in rag.bodies():
				var cap := (pb.get_child(0) as CollisionShape3D).shape as CapsuleShape3D
				var ax := pb.global_transform.basis.y.normalized() * (cap.height * 0.5 - cap.radius)
				var low := minf((pb.global_position + ax).y, (pb.global_position - ax).y) - cap.radius
				if floor_y - low > float(s["dip"]):
					s["dip"] = floor_y - low
					s["dip_by"] = String(pb.bone_name)
			var pel := rag.bodies()[0].global_position - f.global_position
			s["travel"] = maxf(float(s["travel"]), Vector2(pel.x, pel.z).length())
			if int(f.call("wound_count")) > 0:
				var wp: Vector3 = f.call("wound_point", 0)
				if s["wp0"] == Vector3.INF:
					s["wp0"] = wp
				s["wp_moved"] = maxf(float(s["wp_moved"]), wp.distance_to(s["wp0"]))
		if not busy and t > 0.6:
			break
	return {"st": st, "live": live}


## Local rotation of a bone as LIMITS reads it: x and z from the swing, y the twist about the bone (degrees)
func _angles(q: Quaternion) -> Vector3:
	if q.w < 0.0:
		q = -q
	var tw := Quaternion(0.0, q.y, 0.0, q.w)
	tw = Quaternion.IDENTITY if tw.length_squared() < 1e-12 else tw.normalized()
	var sw := q * tw.inverse()
	if sw.w < 0.0:
		sw = -sw
	var rv := sw.get_axis() * sw.get_angle() if sw.get_angle() > 1e-6 else Vector3.ZERO
	var ty := tw.get_axis().y * tw.get_angle() if tw.get_angle() > 1e-6 else 0.0
	return Vector3(rad_to_deg(rv.x), rad_to_deg(ty), rad_to_deg(rv.z))


## After the fall: [worst stretch (m), worst limit overshoot (deg), knee/elbow wrong-way detail ("" = none),
## least elbow/knee bend (deg)]
func _pose_report(f: Node3D, level: String) -> Array:
	var sk: Skeleton3D = f.call("skeleton")
	var stretch := 0.0
	var over := 0.0
	var wrong := ""
	var bend := 999.0
	for b: String in SIM:
		var bi := sk.find_bone(b)
		if bi < 0 or (level == "mid" and (b == "spine" or b == "neck")):
			continue
		stretch = maxf(stretch, sk.get_bone_pose_position(bi).distance_to(sk.get_bone_rest(bi).origin))
		var a := _angles(sk.get_bone_pose_rotation(bi))
		var lim := SoldierRagdoll.limits_for(b, level)
		for k in 3:
			var ax: String = ["x", "y", "z"][k]
			var rg: Array = lim[ax]
			over = maxf(over, maxf(float(rg[0]) - a[k], a[k] - float(rg[1])))
		if b.begins_with("knee") and a.x < -20.0:
			wrong += "%s bent backward %.0f; " % [b, a.x]
		if b.begins_with("elbow") and a.x > 20.0:
			wrong += "%s bent backward %.0f; " % [b, a.x]
		if b.begins_with("knee"):
			bend = minf(bend, a.x)
		elif b.begins_with("elbow"):
			bend = minf(bend, -a.x)
	return [stretch, over, wrong, bend]


## Lying pose: [trunk roll (deg: the shoulder line against the floor), the most bent knee (deg), laid out straight
## (both arms within 25° of the trunk, both knees under 15°, the ankles under 0.3 m apart)]
func _lying(f: Node3D) -> Array:
	var sk: Skeleton3D = f.call("skeleton")
	var at := func(n: String) -> Vector3: return sk.global_transform * sk.get_bone_global_pose(sk.find_bone(n)).origin
	var across: Vector3 = at.call("shoulderL") - at.call("shoulderR")
	var roll := rad_to_deg(asin(clampf(across.normalized().y, -1.0, 1.0)))
	var down: Vector3 = (at.call("hipL") + at.call("hipR")) * 0.5 - at.call("neck")
	var arms := true
	var knee := 0.0
	var straight := true
	for sd: String in ["L", "R"]:
		var arm: Vector3 = at.call("wrist" + sd) - at.call("shoulder" + sd)
		arms = arms and rad_to_deg(arm.angle_to(down)) < 25.0
		var k := rad_to_deg((at.call("knee" + sd) - at.call("hip" + sd) as Vector3).angle_to(at.call("ankle" + sd) - at.call("knee" + sd)))
		knee = maxf(knee, k)
		straight = straight and k < 15.0
	var together := (at.call("ankleL") - at.call("ankleR") as Vector3).length() < 0.3
	return [roll, knee, arms and straight and together]


## Deepest capsule point under the figure's ground after the fall (m; the bodies stay where they froze)
func _rest_dip(f: Node3D) -> float:
	var rag: SoldierRagdoll = f.call("ragdoll")
	var dip := -1.0
	for pb: PhysicalBone3D in rag.bodies():
		var cap := (pb.get_child(0) as CollisionShape3D).shape as CapsuleShape3D
		var ax := pb.global_transform.basis.y.normalized() * (cap.height * 0.5 - cap.radius)
		dip = maxf(dip, f.global_position.y - (minf((pb.global_position + ax).y, (pb.global_position - ax).y) - cap.radius))
	return dip


func _settled_ok(f: Node3D) -> bool:
	var rag: SoldierRagdoll = f.call("ragdoll")
	if rag == null or rag.is_falling() or rag.active or rag.get_node_or_null("RagdollFloor") != null:
		return false
	for pb: PhysicalBone3D in rag.bodies():
		if pb.is_simulating_physics():
			return false
	return true


func _free_all(figs: Array) -> void:
	for f: Node3D in figs:
		if is_instance_valid(f):
			f.free()


# ---- built, not running ----

func test_built_inactive_and_limits() -> void:
	var hi := _new_fig("hi", 3, Vector3(0, 0, 40))
	var mid := _new_fig("mid", 3, Vector3(12, 0, 40))
	var lo := _new_fig("lo", 3, Vector3(24, 0, 40))
	var mn := _new_fig("min", 3, Vector3(36, 0, 40))
	var hero := _new_fig("hi", 3, Vector3(48, 0, 40), "", {"manual": true})
	var rh: SoldierRagdoll = hi.call("ragdoll")
	var rm: SoldierRagdoll = mid.call("ragdoll")
	assert_true(rh != null and rh.bodies().size() == 15, "hi: the player's ragdoll is prebuilt with 15 bodies",
		rh.bodies().size() if rh != null else -1)
	assert_true(rm != null and rm.bodies().size() == 13, "mid: 13 bodies", rm.bodies().size() if rm != null else -1)
	assert_true(lo.call("ragdoll") == null and mn.call("ragdoll") == null and hero.call("ragdoll") == null,
		"lo, min and a manual (hero card) figure have no ragdoll")
	if rh != null:
		var idle := not rh.active and not rh.is_falling() and not rh.is_physics_processing()
		var mass := 0.0
		var shapes := ""
		for pb: PhysicalBone3D in rh.bodies():
			idle = idle and not pb.is_simulating_physics() and pb.top_level
			idle = idle and pb.collision_layer == SoldierRagdoll.LAYER and pb.collision_mask == SoldierRagdoll.FLOOR_LAYER
			mass += pb.mass
			var cap := (pb.get_child(0) as CollisionShape3D).shape as CapsuleShape3D
			if cap.radius < 0.025 or cap.radius > 0.2 or cap.height < 0.08 or cap.height > 0.6:
				shapes += "%s r %.3f h %.3f; " % [pb.bone_name, cap.radius, cap.height]
		assert_true(idle, "hi: prebuilt inactive (simulator off, no body simulating, top level, layer 32, mask 64)")
		assert_true(shapes == "", "the capsules from body_lo have plausible sizes", shapes)
		assert_true(mass > 40.0 and mass < 100.0, "the body weighs %.1f kg in all" % mass)
	var l := SoldierRagdoll.limits_for("elbowL", "hi")
	var r := SoldierRagdoll.limits_for("elbowR", "hi")
	assert_true(r["x"] == l["x"] and r["y"] == [-float(l["y"][1]), -float(l["y"][0])] and r["z"] == [-float(l["z"][1]),
		-float(l["z"][0])], "the right side mirrors the left (x kept, y and z negated)", [l, r])
	var cm := SoldierRagdoll.limits_for("chest", "mid")
	assert_eq(cm["x"], [-45.0, 80.0], "mid: the chest joint carries spine + chest flexion")
	var sh := SoldierRagdoll.limits_for("shoulderL", "hi")
	assert_eq(sh["x"], [-150.0, 50.0], "the shoulder's 180° is capped at 150°")
	var path := ProjectSettings.globalize_path("res://").path_join(RIG_PY)
	if FileAccess.file_exists(path):
		var txt := FileAccess.get_file_as_string(path)
		var bad := ""
		var re := RegEx.create_from_string('"(\\w+)": \\{"x": \\[(-?\\d+), (-?\\d+)\\], "y": \\[(-?\\d+), (-?\\d+)\\], "z": \\[(-?\\d+), (-?\\d+)\\]')
		var seen := 0
		for m in re.search_all(txt):
			var k := m.get_string(1)
			if not SoldierRagdoll.LIMITS.has(k):
				continue
			seen += 1
			var want: Dictionary = SoldierRagdoll.LIMITS[k]
			var got := {"x": [int(m.get_string(2)), int(m.get_string(3))], "y": [int(m.get_string(4)), int(m.get_string(5))],
				"z": [int(m.get_string(6)), int(m.get_string(7))]}
			if str(got) != str(want):
				bad += "%s rig.py %s ragdoll %s; " % [k, got, want]
		assert_true(seen == SoldierRagdoll.LIMITS.size() and bad == "", "the joint limits match rig.py LIMITS (%d bones)" % seen, bad)
	else:
		print("info  tools/ is not here (exported build): the rig.py LIMITS comparison is skipped")
	_free_all([hi, mid, lo, mn, hero])


# ---- falling ----

func test_eight_directions_follow_the_push() -> void:
	_fast(true)
	var figs := []
	for i in DIRS.size():
		figs.append(_new_fig("hi", 21 + i, Vector3(SPACING * i, 0, 0)))
	await _tree().process_frame
	var res := []
	for wave in 2:
		var w := []
		for k in 4:
			var i: int = wave * 4 + k
			w.append(figs[i])
			_kill(figs[i], (DIRS[i] as Vector3).normalized())
		var out: Dictionary = await _watch(w)
		assert_true(int(out["live"]) <= 4, "hi: never more than 4 falling at once (%d)" % int(out["live"]))
		res.append_array(out["st"])
	await _tree().process_frame
	for i in DIRS.size():
		var f: Node3D = figs[i]
		var s: Dictionary = res[i]
		var d := (DIRS[i] as Vector3).normalized()
		var sk: Skeleton3D = f.call("skeleton")
		var pel := sk.global_transform * sk.get_bone_global_pose(sk.find_bone("pelvis")).origin - f.global_position
		var along := Vector2(pel.x, pel.z).dot(Vector2(d.x, d.z))
		var tag := "push %s" % str(DIRS[i])
		assert_true(float(s["started"]) > 0.0 and float(s["lasted"]) > 0.0 and float(s["lasted"]) <= 4.0 and _settled_ok(f),
			"%s: settles or is frozen within 4 s (%.2f s), no physical bone left simulating" % [tag, float(s["lasted"])])
		assert_true(along >= 0.4, "%s: the body falls toward the push (pelvis %.2f m along it)" % [tag, along])
		var rest := _rest_dip(f)
		assert_true(float(s["peak"]) <= 12.0 and float(s["travel"]) <= 2.5 and float(s["dip"]) <= 0.04 and rest <= 0.015,
			"%s: peak %.2f m/s, travel %.2f m, under the floor %.3f m falling (%s) and %.3f m at rest" % [tag, float(s["peak"]),
			float(s["travel"]), float(s["dip"]), s["dip_by"], rest])
		var rep := _pose_report(f, "hi")
		assert_true(float(rep[0]) <= 0.04 and float(rep[1]) <= 25.0 and str(rep[2]) == "",
			"%s: joints held (%.3f m), within limits + 25° (worst %.1f°), knees and elbows bend their own way" % [tag,
			float(rep[0]), float(rep[1])], rep[2])
		assert_true(float(rep[3]) >= 8.0, "%s: every elbow and knee keeps a bend (least %.1f°)" % [tag, float(rep[3])])
		assert_true(f.global_position.distance_to(s["pos"]) < 1e-6 and pel.y < 0.5,
			"%s: the figure (game position) did not move; the pelvis lies at %.2f m" % [tag, pel.y])
	_fast(false)
	_free_all(figs)


func test_wound_point_follows() -> void:
	_fast(true)
	var f := _new_fig("hi", 9, Vector3(0, 0, -30))
	await _tree().process_frame
	_kill(f, Vector3(0, 0, -1))
	var out: Dictionary = await _watch([f])
	var s: Dictionary = out["st"][0]
	var n := int(f.call("wound_count"))
	assert_true(n >= 2 and float(s["wp_moved"]) > 0.25,
		"wound_point follows the physics pose during the fall (moved %.2f m, %d wounds)" % [float(s["wp_moved"]), n])
	await _tree().process_frame
	var high := 0.0
	for i in n:
		high = maxf(high, (f.call("wound_point", i) as Vector3).y - f.global_position.y)
	assert_true(n > 0 and high < 0.6, "after the fall every wound lies low (highest %.2f m)" % high)
	_fast(false)
	f.free()


func test_mid_cap_six_deaths() -> void:
	_fast(true)
	var figs := []
	for i in 6:
		figs.append(_new_fig("mid", 40 + i, Vector3(SPACING * i, 0, 30)))
	await _tree().process_frame
	for i in 6:
		_kill(figs[i], (DIRS[i] as Vector3).normalized())
	var out: Dictionary = await _watch(figs)
	var fell := 0
	var clip := 0
	for i in 6:
		if float(out["st"][i]["started"]) > 0.0:
			fell += 1
		elif str((figs[i].call("animation_player") as AnimationPlayer).assigned_animation).contains("/die"):
			clip += 1
	assert_true(int(out["live"]) <= 2 and fell == 2 and clip == 4,
		"mid: six deaths at once, at most two falling (%d), two fell (%d), four played the clip (%d)" % [int(out["live"]), fell, clip])
	_fast(false)
	_free_all(figs)


func test_other_bodies() -> void:
	_fast(true)
	var figs := [_new_fig("hi", 5, Vector3(0, 0, -60), "m2"), _new_fig("hi", 6, Vector3(SPACING, 0, -60), "f1")]
	await _tree().process_frame
	_kill(figs[0], Vector3(0, 0, -1))
	_kill(figs[1], Vector3(1, 0, 0))
	var out: Dictionary = await _watch(figs)
	await _tree().process_frame
	for i in 2:
		var s: Dictionary = out["st"][i]
		var rep := _pose_report(figs[i], "hi")
		var tag: String = ["m2", "f1"][i]
		var rag: SoldierRagdoll = figs[i].call("ragdoll")
		assert_true(rag != null and rag.bodies().size() == 15 and float(s["lasted"]) > 0.0 and float(s["lasted"]) <= 4.0
			and _settled_ok(figs[i]), "%s: its own ragdoll settles within 4 s (%.2f s)" % [tag, float(s["lasted"])])
		assert_true(float(s["peak"]) <= 12.0 and float(s["travel"]) <= 2.5 and float(s["dip"]) <= 0.04
			and _rest_dip(figs[i]) <= 0.015 and float(rep[0]) <= 0.04 and float(rep[1]) <= 25.0 and str(rep[2]) == "",
			"%s: within the bounds (peak %.2f, travel %.2f, dip %.3f %s, stretch %.3f, limits + %.1f°)" % [tag,
			float(s["peak"]), float(s["travel"]), float(s["dip"]), s["dip_by"], float(rep[0]), float(rep[1])], rep[2])
		assert_true(float(rep[3]) >= 8.0, "%s: every elbow and knee keeps a bend (least %.1f°)" % [tag, float(rep[3])])
	_fast(false)
	_free_all(figs)


## ใหม่ 0.14 review: the front hit (the commonest kill) folds differently per seed and is never laid out straight;
## the same seed hands over the same way: killed at once after setup (the same start pose), a later figure of seed 61
## on the same spot starts its fall exactly as the first did, whatever the frame timing in between (physics ticks)
func test_front_hits_differ() -> void:
	_fast(true)
	var seeds := [61, 62, 63]
	var figs := []
	for i in seeds.size():
		figs.append(_new_fig("hi", seeds[i], Vector3(SPACING * i, 0, 60)))
		_kill(figs[i], Vector3(0, 0, -1))
	var out: Dictionary = await _watch(figs)
	await _tree().process_frame
	var rolls := []
	var knee := 0.0
	var laid := ""
	for i in 3:
		var ly := _lying(figs[i])
		print("info  front hit seed %d: roll %.1f°, most bent knee %.1f°, laid out %s, lasted %.2f s" % [seeds[i],
			float(ly[0]), float(ly[1]), str(ly[2]), float(out["st"][i]["lasted"])])
		rolls.append(float(ly[0]))
		knee = maxf(knee, float(ly[1]))
		if bool(ly[2]):
			laid += "seed %d; " % seeds[i]
		assert_true(_settled_ok(figs[i]), "front hit seed %d: settled or frozen" % seeds[i])
	var spread := float(rolls.max()) - float(rolls.min())
	assert_true(spread > 20.0 or knee > 30.0, "front hit, 3 seeds: the end poses differ (trunk roll spread %.1f°, most bent knee %.1f°)"
		% [spread, knee])
	assert_true(laid == "", "front hit: no pose laid out straight (both arms along the trunk, both legs straight together)", laid)
	var p0 := _pelvis(figs[0])
	var s0: Vector3 = out["st"][0]["p_start"]
	var t0 := float(out["st"][0]["lasted"])
	_free_all(figs)
	for i in 3:
		await _tree().process_frame
	var f := _new_fig("hi", 61, Vector3(0, 0, 60))
	_kill(f, Vector3(0, 0, -1))
	var again: Dictionary = await _watch([f])
	await _tree().process_frame
	var p1 := _pelvis(f)
	var s1: Vector3 = again["st"][0]["p_start"]
	var t1 := float(again["st"][0]["lasted"])
	# the hand-over itself is exact (one physics step in); the landing is not compared (the solver saw 3 ragdolls, then 1)
	assert_true(s0.distance_to(s1) < 0.001, "the same seed and push hand over the same way (pelvis %.5f m apart a step in)"
		% s0.distance_to(s1))
	print("info  same seed alone: landed %.3f m from the first, lasted %.2f / %.2f s" % [p0.distance_to(p1), t0, t1])
	_fast(false)
	f.free()


func _pelvis(f: Node3D) -> Vector3:
	var sk: Skeleton3D = f.call("skeleton")
	return sk.global_transform * sk.get_bone_global_pose(sk.find_bone("pelvis")).origin - Vector3(0, 0, 60)


func test_revive_stops_the_fall() -> void:
	_fast(true)
	var f := _new_fig("hi", 2, Vector3(0, 0, -90))
	await _tree().process_frame
	var before := SoldierRagdoll.live_count()
	_kill(f, Vector3(1, 0, 0))
	var rag: SoldierRagdoll = f.call("ragdoll")
	var t := 0.0
	while t < 1.0 and not rag.is_falling():
		await _tree().physics_frame
		t += STEP
	var was := rag.is_falling() and SoldierRagdoll.live_count() == before + 1
	f.call("play", &"idle", 1.0)
	var none := true
	for pb: PhysicalBone3D in rag.bodies():
		none = none and not pb.is_simulating_physics()
	assert_true(was and not rag.is_falling() and not rag.active and none and SoldierRagdoll.live_count() == before
		and str(f.call("playing_clip")).ends_with("/idle"), "getting up during the fall stops the ragdoll at once",
		[was, rag.is_falling(), rag.active, none, SoldierRagdoll.live_count(), before, f.call("playing_clip")])
	_fast(false)
	f.free()
