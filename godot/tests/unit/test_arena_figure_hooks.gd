extends "res://tests/testing.gd"
## The optional figure methods of ARENA_SPEC §9.4 (H6 set_move_dir, H7 begin_switch) and the default figure's melee
## clips. ArenaPlayer.local_dir turns the body's velocity into the figure's own frame (x = its right, the -X side;
## y = its forward, +Z) for two facings, zero below 0.05 m/s; ArenaPlayer.move_figure sends set_move to a figure without
## H6 (the primitive fixture) and set_move_dir instead of it to one with H6 (dir_figure.gd); a real ArenaPlayer caches
## the check in setup and drives both through _physics_process. EggGunner: on mid the lean follows the direction (the
## top tips toward the side it moves to, backwards leans back, (0, 1) is exactly set_move's pose), on min nothing new
## processes; the swing is 0.45 s with two alternating arcs whose blade points straight ahead at 0.18 s (A right to
## left, B left to right, A again after a 1.2 s gap; without the test clock it reads game time, so two swings in one
## physics tick alternate) and whose grip never enters the egg; the punch peaks at 0.12 s; a punch cutting a swing (or a
## swing cutting a punch) after its hit starts from the pose on screen and blends into its own pose within 0.08 s;
## the rifle slung on the back shows with the sword on hi / mid / lo only, never inside the egg; H7 shrinks the held
## weapon on hi and does nothing on min. The contract (FIGURE_API) still has twelve names.

const PRIM := "res://tests/fixtures/figure_pack/prim_figure.gd"
const DIR_FIG := "res://tests/fixtures/figure_pack/dir_figure.gd"
const EGG := "res://scenes/arena/egg_gunner.gd"
const PLAYER_SCENE := "res://scenes/arena/arena_player.tscn"
const DT := 1.0 / 120.0


func _new(path: String) -> Node3D:
	return (load(path) as Script).new()


func _egg(level: String, weapon: StringName = &"none") -> Node3D:
	var e := _new(EGG)
	e.call("setup", {"role": &"player", "level": level})
	if weapon != &"none":
		e.call("set_weapon", weapon)
		_step(e, 0.3)
	return e


func _step(e: Node3D, secs: float) -> void:
	var n := int(round(secs / DT))
	for i in n:
		if e.is_processing():
			e.call("_process", DT)


## the blade's horizontal yaw (0 = straight ahead, + = toward the figure's left, +X)
func _blade_yaw(e: Node3D) -> float:
	var b := ((e.get("weapon_root") as Node3D).transform.basis.z).normalized()
	return atan2(b.x, b.z)


## the egg's radius at height y (HallBuilder.lathe of avatar_mesh: 1.75 m tall, 0.43 m at the widest)
func _egg_r(y: float) -> float:
	var q := y / 1.75
	var prof := HallBuilder.EGG_PROFILE
	if q <= 0.0 or q >= 1.0:
		return 0.0
	for i in prof.size() - 1:
		if q <= prof[i + 1].x:
			var f := (q - prof[i].x) / (prof[i + 1].x - prof[i].x)
			return lerpf(prof[i].y, prof[i + 1].y, f) * 0.43
	return 0.0


func test_local_dir() -> void:
	var cases := [[Vector3(0, 0, 3), Vector2(0, 1)], [Vector3(-3, 0, 0), Vector2(1, 0)], [Vector3(3, 0, 0), Vector2(-1, 0)],
		[Vector3(0, 0, -3), Vector2(0, -1)]]
	for c in cases:
		var got := ArenaPlayer.local_dir(c[0], 0.0)
		assert_true(got.distance_to(c[1]) < 1e-5, "facing yaw 0: velocity %s is %s in the figure's frame" % [str(c[0]), str(c[1])], got)
		var flipped := ArenaPlayer.local_dir(c[0], PI)
		assert_true(flipped.distance_to(-(c[1] as Vector2)) < 1e-5, "facing yaw PI: velocity %s is %s" % [str(c[0]), str(-(c[1] as Vector2))], flipped)
	var diag := ArenaPlayer.local_dir(Vector3(-2, 0, 2), 0.0)
	assert_within(diag.length(), 1.0, 1e-5, "the direction has length 1")
	assert_true(diag.x > 0.7 and diag.y > 0.7, "forward-right is (0.71, 0.71)", diag)
	assert_eq(ArenaPlayer.local_dir(Vector3(0.03, 0, 0), 0.0), Vector2.ZERO, "below 0.05 m/s the direction is zero")
	assert_eq(ArenaPlayer.local_dir(Vector3(0, 5, 0), 1.0), Vector2.ZERO, "vertical speed does not count")


func test_move_figure_dispatch() -> void:
	ArenaPlayer.move_figure(null, true, Vector2(1, 0), 3.0, false)   # no crash
	var prim := _new(PRIM)
	assert_false(prim.has_method("set_move_dir"), "the primitive fixture has no set_move_dir (a figure without H6)")
	ArenaPlayer.move_figure(prim, false, Vector2(1, 0), 3.0, true)
	var pc: Dictionary = prim.get("calls")
	assert_eq(int(pc.get("set_move", 0)), 1, "without H6 the figure gets one set_move")
	assert_eq(prim.get("last_move"), Vector2(3.0, 1.0), "with the speed and the run flag")
	prim.free()
	var df := _new(DIR_FIG)
	assert_true(df.has_method("set_move_dir"), "dir_figure.gd has set_move_dir")
	ArenaPlayer.move_figure(df, true, Vector2(-1, 0), 3.0, false)
	var dc: Dictionary = df.get("calls")
	assert_eq(int(dc.get("set_move_dir", 0)), 1, "with H6 the figure gets one set_move_dir")
	assert_eq(int(dc.get("set_move", 0)), 0, "…and no set_move")
	assert_eq(df.get("last_dir"), Vector2(-1, 0), "…with the direction")
	assert_eq(df.get("last_move"), Vector2(3.0, 0.0), "…and the speed and run flag (its movement logic ran)")
	assert_eq(df.get("loop"), &"run", "3 m/s picks the fixture's run loop")
	df.call("set_move", 1.0, false)
	assert_eq(df.get("last_dir"), Vector2(0, 1), "set_move resets the stored direction to (0, 1)")
	df.free()


func test_contract_unchanged() -> void:
	assert_eq(ArenaActors.FIGURE_API.size(), 12, "FIGURE_API still has twelve names")
	assert_false(ArenaActors.FIGURE_API.has("set_move_dir") or ArenaActors.FIGURE_API.has("begin_switch"),
		"the H6 / H7 methods are optional, not in FIGURE_API")
	for path: String in [EGG, DIR_FIG]:
		var f := _new(path)
		assert_eq(ArenaActors.missing_api(f), PackedStringArray(), "%s has the whole contract" % path.get_file())
		f.free()
	var e := _new(EGG)
	assert_true(e.has_method("set_move_dir") and e.has_method("begin_switch"), "the default figure has both optional methods")
	e.free()


func test_player_caches_and_dispatches() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or not ResourceLoader.exists(PLAYER_SCENE):
		assert_true(false, "the arena player scene loads")
		return
	for path: String in [DIR_FIG, PRIM]:
		var p: Node3D = (load(PLAYER_SCENE) as PackedScene).instantiate()
		tree.root.add_child(p)
		var fig := _new(path)
		p.call("setup", null, {"figure": fig, "level": "min"})
		var has_dir := path == DIR_FIG
		assert_eq(bool(p.get("_fig_dir")), has_dir, "%s: setup cached set_move_dir = %s" % [path.get_file(), str(has_dir)])
		assert_false(bool(p.get("_fig_switch")), "%s: no begin_switch" % path.get_file())
		p.call("set_mode", &"shoot")
		p.call("place", Vector3(0, 0, 40), 0.0, PI)      # far from everything
		(fig.get("calls") as Dictionary).clear()
		p.call("set_stick", Vector2(1, 0))
		for i in 30:
			p.call("_physics_process", 1.0 / 60.0)
		var c: Dictionary = fig.get("calls")
		if has_dir:
			assert_true(int(c.get("set_move_dir", 0)) == 30 and int(c.get("set_move", 0)) == 0,
				"with H6 the player calls set_move_dir instead of set_move every tick", c)
			assert_true((fig.get("last_dir") as Vector2).x > 0.9, "the stick to the right strafes: local_dir x > 0.9", fig.get("last_dir"))
		else:
			assert_true(int(c.get("set_move", 0)) == 30, "without H6 the player calls set_move every tick as before", c)
			assert_true((fig.get("last_move") as Vector2).x > 2.0, "…with the speed", fig.get("last_move"))
		p.call("set_stick", Vector2.ZERO)
		p.call("set_mode", &"walk")
		tree.root.remove_child(p)
		p.free()
	# H7 through press(): the egg hears begin_switch before set_weapon
	var p2: Node3D = (load(PLAYER_SCENE) as PackedScene).instantiate()
	tree.root.add_child(p2)
	var egg := _new(EGG)
	p2.call("setup", null, {"figure": egg, "level": "mid"})
	assert_true(bool(p2.get("_fig_dir")) and bool(p2.get("_fig_switch")), "the egg: setup cached both optional methods")
	p2.call("set_mode", &"shoot")
	for i in 30:
		p2.call("_physics_process", 1.0 / 60.0)
	assert_eq(egg.call("weapon"), &"gun", "shoot mode draws the rifle")
	p2.call("press", &"weapon_2", true)
	assert_true(egg.call("last_switch") == &"sword" and egg.call("weapon") == &"gun",
		"weapon 2: begin_switch(sword) arrives at once, the rifle still in hand", [egg.call("last_switch"), egg.call("weapon")])
	for i in 12:
		p2.call("_physics_process", 1.0 / 60.0)
	assert_eq(egg.call("weapon"), &"sword", "0.2 s later set_weapon(sword) followed")
	egg.set("_last_switch", &"")
	p2.call("press", &"weapon_2", true)
	assert_eq(egg.call("last_switch"), &"", "pressing the weapon already being drawn starts nothing")
	p2.call("press", &"weapon_1", true)
	assert_eq(egg.call("last_switch"), &"gun", "turning back to the rifle mid-switch tells the figure again")
	p2.call("set_mode", &"walk")
	tree.root.remove_child(p2)
	p2.free()


func test_egg_lean_follows_direction() -> void:
	var e := _egg("mid", &"gun")
	e.call("set_move_dir", Vector2(1, 0), 3.0, false)
	assert_eq(e.call("move_dir"), Vector2(1, 0), "move_dir() records the direction")
	assert_true(e.is_processing(), "moving on mid processes (bob and lean, as before)")
	_step(e, 0.2)
	var body := e.get("egg") as Node3D
	var up := body.transform.basis.y
	assert_true(up.dot(Vector3(-1, 0, 0)) > 0.02, "strafing right (the -X side) tips the egg's top toward it", up)
	e.call("set_move_dir", Vector2(-1, 0), 3.0, false)
	_step(e, 0.1)
	assert_true(body.transform.basis.y.dot(Vector3(1, 0, 0)) > 0.02, "strafing left tips it toward +X", body.transform.basis.y)
	e.call("set_move_dir", Vector2(0, -1), 3.0, false)
	_step(e, 0.1)
	var back := body.rotation.x
	e.call("set_move_dir", Vector2(0, 1), 3.0, false)
	_step(e, 0.1)
	var fwd := body.rotation.x
	assert_true(back < 0.0 and fwd > 0.0, "walking backwards leans back, forwards leans forward (%.3f, %.3f)" % [back, fwd])
	e.call("set_move", 3.0, false)
	assert_eq(e.call("move_dir"), Vector2(0, 1), "set_move resets the direction to (0, 1)")
	e.free()
	# (0, 1) is exactly set_move's pose
	var a := _egg("mid", &"gun")
	var b := _egg("mid", &"gun")
	a.call("set_move", 3.0, false)
	b.call("set_move_dir", Vector2(0, 1), 3.0, false)
	_step(a, 0.25)
	_step(b, 0.25)
	var ra := (a.get("egg") as Node3D).rotation
	var rb := (b.get("egg") as Node3D).rotation
	assert_true(ra.distance_to(rb) < 1e-6 and (a.get("egg") as Node3D).position.distance_to((b.get("egg") as Node3D).position) < 1e-6,
		"set_move_dir((0, 1)) gives exactly set_move's pose", [ra, rb])
	a.free()
	b.free()
	# min: nothing new runs, the pose is set_move's
	var m := _egg("min", &"gun")
	var m2 := _egg("min", &"gun")
	m.call("set_move", 3.0, false)
	m2.call("set_move_dir", Vector2(1, 0), 3.0, false)
	assert_false(m.is_processing() or m2.is_processing(), "min: moving starts no _process, with or without the direction")
	assert_true((m.get("egg") as Node3D).rotation.distance_to((m2.get("egg") as Node3D).rotation) < 1e-6,
		"min: the direction changes nothing on screen")
	assert_eq(m2.call("move_dir"), Vector2(1, 0), "min: the direction is still stored")
	m.free()
	m2.free()


func test_egg_swing_arcs() -> void:
	var e := _egg("mid", &"sword")
	e.set("clock", 10.0)
	assert_within(float(e.call("play", &"swing", 1.0)), 0.45, 1e-6, "play(swing) returns 0.45 s")
	assert_eq(e.call("swing_arc"), &"a", "the first swing is arc A")
	var res := _sweep(e, 1.0)
	assert_true(absf(float(res["cross"]) - 0.18) <= 0.02, "arc A: the blade points straight ahead at %.3f s (0.18 ± 0.02)" % float(res["cross"]))
	assert_true(float(res["y10"]) < -1.0 and float(res["y26"]) > 1.0, "arc A sweeps right to left (yaw %.2f at 0.10 s, %.2f at 0.26 s)" % [float(res["y10"]), float(res["y26"])])
	assert_true(bool(res["named"]), "clip() is swing for the whole arc, then the loop")
	assert_true(float(res["min_r"]) >= 0.48, "arc A: the grip stays outside the egg (closest %.3f m from its axis)" % float(res["min_r"]))
	assert_true(float(res["min_tip"]) >= 0.05, "arc A: the blade tip stays above the floor (lowest %.3f m)" % float(res["min_tip"]))
	e.set("clock", 10.8)
	e.call("play", &"swing", 1.0)
	assert_eq(e.call("swing_arc"), &"b", "a swing 0.8 s later is arc B")
	res = _sweep(e, -1.0)
	assert_true(absf(float(res["cross"]) - 0.18) <= 0.02, "arc B: the blade points straight ahead at %.3f s (0.18 ± 0.02)" % float(res["cross"]))
	assert_true(float(res["y10"]) > 1.0 and float(res["y26"]) < -1.0, "arc B sweeps left to right (yaw %.2f at 0.10 s, %.2f at 0.26 s)" % [float(res["y10"]), float(res["y26"])])
	assert_true(float(res["min_r"]) >= 0.48, "arc B: the grip stays outside the egg (closest %.3f m)" % float(res["min_r"]))
	assert_true(float(res["min_tip"]) >= 0.05, "arc B: the blade tip stays above the floor (lowest %.3f m)" % float(res["min_tip"]))
	e.set("clock", 11.6)
	e.call("play", &"swing", 1.0)
	assert_eq(e.call("swing_arc"), &"a", "the third swing in a row is arc A")
	_step(e, 0.5)
	e.set("clock", 11.6 + 1.3)
	e.call("play", &"swing", 1.0)
	assert_eq(e.call("swing_arc"), &"a", "after a 1.3 s gap it starts with arc A again")
	_step(e, 0.5)
	e.set("clock", 12.9 + 0.8)
	e.call("play", &"swing", 1.0)
	assert_eq(e.call("swing_arc"), &"b", "…and alternates again")
	e.free()
	# lo and min play the same clip (the one-shot _process that runs for any clip)
	var lo := _egg("min", &"sword")
	lo.set("clock", 1.0)
	lo.call("play", &"swing", 1.0)
	assert_true(lo.is_processing(), "min: the swing plays (one-shot clip)")
	var r2 := _sweep(lo, 1.0)
	assert_true(absf(float(r2["cross"]) - 0.18) <= 0.02, "min: the same arc, straight ahead at %.3f s" % float(r2["cross"]))
	_step(lo, 0.1)
	assert_false(lo.is_processing(), "min: after the swing nothing processes")
	lo.free()


## steps one swing; dir +1 looks for the yaw going from < 0 to >= 0 (arc A), -1 the other way (arc B)
func _sweep(e: Node3D, dir: float) -> Dictionary:
	var out := {"cross": -1.0, "y10": 0.0, "y26": 0.0, "named": true, "min_r": INF, "min_tip": INF}
	var prev := _blade_yaw(e) * dir
	var t := 0.0
	var root := e.get("weapon_root") as Node3D
	while t < 0.6:
		e.call("_process", DT)
		t += DT
		var y := _blade_yaw(e)
		if out["cross"] < 0.0 and prev < 0.0 and y * dir >= 0.0:
			out["cross"] = t
		prev = y * dir
		if absf(t - 0.10) < DT * 0.5:
			out["y10"] = y
		if absf(t - 0.26) < DT * 0.5:
			out["y26"] = y
		if t < 0.45 - DT and str(e.call("clip")) != "swing":
			out["named"] = false
		if t > 0.46 and str(e.call("clip")) != "":
			out["named"] = false
		var g := root.transform.origin
		out["min_r"] = minf(float(out["min_r"]), Vector2(g.x, g.z).length())
		var tip := g + root.transform.basis.z.normalized() * 1.23
		out["min_tip"] = minf(float(out["min_tip"]), tip.y)
	return out


## a one-shot that cuts a swing or a punch (allowed once its hit is decided, ARENA_SPEC §9.4) starts from the pose on
## screen, not from the guard, and is at its own pose after the 0.08 s blend
func test_egg_cut_blends() -> void:
	for level: String in ["mid", "min"]:
		var e := _egg(level, &"sword")
		var root := e.get("weapon_root") as Node3D
		var body := e.get("egg") as Node3D
		e.set("clock", 5.0)
		e.call("play", &"swing", 1.0)
		_step(e, 0.26)
		var g0 := root.transform.origin
		var tw0 := body.rotation.y
		var fresh := _egg(level, &"sword")
		fresh.call("play", &"punch", 1.0)
		var guard := (fresh.get("weapon_root") as Node3D).transform.origin
		assert_true(g0.distance_to(guard) > 0.2, "%s: at 0.26 s the swing's grip is far from the guard (%.2f m)" % [level, g0.distance_to(guard)])
		e.call("play", &"punch", 1.0)
		assert_true(root.transform.origin.distance_to(g0) < 0.005 and absf(body.rotation.y - tw0) < 0.005,
			"%s: a punch cutting the swing starts from the swing's grip and twist (moved %.4f m, %.4f rad)" % [level,
			root.transform.origin.distance_to(g0), absf(body.rotation.y - tw0)])
		_step(e, 0.1)
		_step(fresh, 0.1)
		var fr := fresh.get("weapon_root") as Node3D
		assert_true(root.transform.origin.distance_to(fr.transform.origin) < 1e-4 and absf(body.rotation.y - (fresh.get("egg") as Node3D).rotation.y) < 1e-4,
			"%s: 0.1 s later it is exactly the punch's own pose" % level)
		e.free()
		fresh.free()
		# a swing cutting a punch at full reach: the left gauntlet does not snap back
		var p := _egg(level, &"sword")
		var hand := p.call("anchor", &"hand_l") as Node3D
		p.call("play", &"punch", 1.0)
		_step(p, 0.12)
		var l0 := hand.position
		p.set("clock", 9.0)
		p.call("play", &"swing", 1.0)
		assert_true(hand.position.distance_to(l0) < 0.005, "%s: a swing cutting the punch keeps the left gauntlet where it was (moved %.4f m)" % [level, hand.position.distance_to(l0)])
		_step(p, 0.1)
		var f2 := _egg(level, &"sword")
		f2.set("clock", 9.0)
		f2.call("play", &"swing", 1.0)
		_step(f2, 0.1)
		assert_true(hand.position.distance_to((f2.call("anchor", &"hand_l") as Node3D).position) < 1e-4, "%s: …and 0.1 s later it is the swing's own pose" % level)
		_step(p, 0.5)
		_step(f2, 0.5)
		assert_false(p.is_processing() or f2.is_processing(), "%s: after the clip nothing processes" % level)
		p.free()
		f2.free()
	# no test clock: game time (physics frames); two swings in the same tick alternate A, B
	var g := _egg("mid", &"sword")
	g.call("play", &"swing", 1.0)
	var a1: StringName = g.call("swing_arc")
	g.call("play", &"swing", 1.0)
	assert_eq([a1, g.call("swing_arc")], [&"a", &"b"], "without the test clock the arcs follow game time (A then B in one tick)")
	g.free()


func test_egg_punch_peak() -> void:
	var e := _egg("mid", &"gun")
	e.call("play", &"punch", 1.0)
	var hand := e.call("anchor", &"hand_l") as Node3D     # the left gauntlet's position (the headless MultiMesh keeps none)
	var best := -INF
	var at := 0.0
	var t := 0.0
	while t < 0.3:
		e.call("_process", DT)
		t += DT
		var z := hand.position.z
		if z > best:
			best = z
			at = t
	assert_true(absf(at - 0.12) <= 0.02, "the punch reaches furthest at %.3f s (ArenaData punch active 0.12 ± 0.02)" % at)
	assert_within(float(ArenaData.WEAPONS["punch"]["active"]), 0.12, 1e-6, "the punch lands 0.12 s after the press")
	assert_within(float(ArenaData.WEAPONS["sword"]["active"]), 0.18, 1e-6, "the saw sword lands 0.18 s after the press")
	e.free()


func test_egg_slung_rifle() -> void:
	for level: String in ["hi", "mid", "lo", "min"]:
		var e := _egg(level, &"sword")
		var st := e.get("stowed") as MeshInstance3D
		assert_true(st != null and st.name == &"Stowed" and st.get_parent() == e.get("egg"), "%s: the slung rifle is a child of the egg" % level)
		assert_eq(st.visible, level != "min", "%s: with the sword the rifle on the back shows = %s" % [level, str(level != "min")])
		assert_true(st.mesh == EggGunner.rifle_mesh(true), "%s: it is the rifle mesh" % level)
		e.call("set_weapon", &"gun")
		assert_false(st.visible, "%s: with the rifle in hand it is hidden" % level)
		e.call("set_weapon", &"none")
		assert_false(st.visible, "%s: with no weapon it is hidden" % level)
		e.free()
	# never inside the egg, the stock above 0.55 m
	var e2 := _egg("hi", &"sword")
	var st2 := e2.get("stowed") as MeshInstance3D
	var verts: PackedVector3Array = st2.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var inside := 0
	var low := INF
	for v in verts:
		var p := st2.transform * v
		low = minf(low, p.y)
		if Vector2(p.x, p.z).length() < _egg_r(p.y) - 0.005:
			inside += 1
	assert_eq(inside, 0, "no vertex of the slung rifle is inside the egg")
	assert_true(low >= 0.55, "its lowest point is above 0.55 m (%.3f)" % low)
	var front := 0
	for v in verts:
		if (st2.transform * v).z > 0.0:
			front += 1
	assert_eq(front, 0, "it is all behind the egg (z < 0)")
	e2.free()


func test_egg_begin_switch() -> void:
	var e := _egg("hi", &"gun")
	var root := e.get("weapon_root") as Node3D
	assert_within(root.transform.basis.x.length(), 1.0, 1e-4, "hi: the drawn rifle is full size")
	e.call("begin_switch", &"sword", 0.15, 0.2)
	assert_eq(e.call("last_switch"), &"sword", "last_switch() records the weapon being drawn")
	assert_true(e.is_processing(), "hi: the holster shrink processes")
	_step(e, 0.1)
	assert_true(root.transform.basis.x.length() < 0.6, "hi: 0.1 s into the holster the rifle has shrunk (%.2f)" % root.transform.basis.x.length())
	e.call("set_weapon", &"sword")
	_step(e, 0.3)
	assert_within(root.transform.basis.x.length(), 1.0, 1e-4, "hi: set_weapon grows the sword to full size")
	assert_true((e.get("stowed") as Node3D).visible, "hi: the rifle is now on the back")
	e.call("begin_switch", &"gun", 0.15, 0.2)
	assert_false((e.get("stowed") as Node3D).visible, "hi: the slung rifle leaves the back when the switch to it starts")
	_step(e, 0.05)
	var mid_k := root.transform.basis.x.length()
	e.call("begin_switch", &"sword", 0.15, 0.2)
	var after_k := root.transform.basis.x.length()
	_step(e, DT)
	assert_true(absf(root.transform.basis.x.length() - mid_k) < 0.08 and mid_k < 0.99, "turning back mid-holster has no size jump (%.2f -> %.2f)" % [mid_k, after_k])
	_step(e, 0.3)
	assert_within(root.transform.basis.x.length(), 1.0, 1e-4, "…and the sword grows back to full size")
	assert_false(e.is_processing(), "…then nothing processes")
	e.free()
	var m := _egg("min", &"gun")
	m.call("begin_switch", &"sword", 0.15, 0.2)
	assert_eq(m.call("last_switch"), &"sword", "min: the call is recorded")
	assert_false(m.is_processing(), "min: begin_switch starts nothing")
	assert_within((m.get("weapon_root") as Node3D).transform.basis.x.length(), 1.0, 1e-4, "min: the rifle keeps its size")
	m.free()
