extends "res://tests/testing.gd"
## The arena player's weapons (ARENA_SPEC §5.2, §6.1, §6.3, §13.2) on fake time (1/60 s steps): the rifle fires 8 shots
## in 1 s while held (±1), 30 then the magazine is empty and reloads by itself while the trigger is still held (an
## empty magazine also reloads on the next press, e.g. after a switch cancelled the reload), a reload takes 1.6 s,
## R reloads mid-magazine, a weapon switch cancels the reload and holster + draw take 0.35 s with no shot; the punch
## has a 0.55 s cooldown and lands 0.12 s after the press, the saw sword 0.8 s and 0.18 s; the melee cone goes through
## ArenaCombat.melee_hits. The shoulder camera: its pivot is 0.9 m right of the player, the camera point stays 0.9 m
## right of the line through the player along the view, and the aim ray is the ray through the viewport centre.

const DT := 1.0 / 60.0


func _ready_gun() -> ArenaWeapons:
	var w := ArenaWeapons.new()
	w.draw(&"gun")
	_run(w, 0.25)
	return w


## Ticks for `seconds`; returns every event with its time.
func _run(w: ArenaWeapons, seconds: float) -> Array:
	var out := []
	var n := int(round(seconds / DT))
	for i in n:
		for e in w.tick(DT):
			var d: Dictionary = e.duplicate()
			d["at"] = w.now
			out.append(d)
	return out


func _count(events: Array, type: StringName) -> int:
	return events.filter(func(e: Dictionary) -> bool: return e["type"] == type).size()


func _first(events: Array, type: StringName) -> float:
	for e in events:
		if e["type"] == type:
			return float(e["at"])
	return -1.0


func test_rifle_rate_and_magazine() -> void:
	var w := _ready_gun()
	assert_eq(w.ammo(), Vector2i(30, 30), "the rifle starts with a full 30-round magazine")
	assert_within(ArenaCombat.fire_interval("gun"), 0.125, 0.0001, "the rifle's interval comes from ArenaData (8 shots/s)")
	w.set_trigger(true)
	var ev := _run(w, 1.0)
	var shots := _count(ev, &"shot")
	assert_true(absi(shots - 8) <= 1, "held for 1.0 s the rifle fires 8 ± 1 shots", shots)
	# Changed on purpose at integration (ARENA_SPEC §17): the spec let an empty magazine go silent until the next press;
	# with fire held (the usual case on a phone) that felt like a jammed gun, so it now reloads by itself at once.
	ev = _run(w, 3.0)
	assert_eq(shots + _count(ev, &"shot"), 30, "held on, it fires exactly the 30 rounds of its magazine")
	var t_last := 0.0
	for e: Dictionary in ev:
		if e["type"] == &"shot":
			t_last = float(e["at"])
	var t_reload := _first(ev, &"reload_start")
	assert_true(t_reload > 0.0 and absf(t_reload - t_last) <= DT * 1.5, "the empty magazine starts reloading by itself with the trigger held (%.3f s after the last shot)" % (t_reload - t_last))
	assert_true(w.reloading(), "…and the rifle is reloading")
	ev = _run(w, 1.7)
	var done := _first(ev, &"reload_done")
	assert_true(done > 0.0 and absf(done - t_reload - 1.6) <= DT * 1.5, "the reload takes 1.6 s (%.3f)" % (done - t_reload))
	assert_eq(w.in_mag + _count(ev, &"shot"), 30, "after it the magazine is full (the held trigger already spent %d)" % _count(ev, &"shot"))
	assert_true(_count(ev, &"shot") >= 1, "with the trigger still held it fires again once reloaded")
	assert_true(_first(ev, &"shot") >= done, "…and never before the reload is done")
	# an empty magazine whose reload was cancelled (a weapon switch) reloads on the next press
	w.set_trigger(false)
	var w2 := _ready_gun()
	w2.set_trigger(true)
	_run(w2, 3.9)
	w2.set_trigger(false)
	assert_eq(w2.in_mag, 0, "second rifle: the magazine is empty")
	w2.switch_to(&"sword")
	_run(w2, 0.4)
	w2.switch_to(&"gun")
	_run(w2, 0.4)
	assert_true(w2.current == &"gun" and w2.in_mag == 0 and not w2.reloading(), "the switch cancelled the reload: rifle in hand, empty, not reloading")
	var press := w2.set_trigger(true)
	assert_eq(_count(press, &"reload_start"), 1, "the next press starts the reload by itself")


func test_reload_key_and_switch_cancel() -> void:
	var w := _ready_gun()
	assert_eq(w.reload(), [] as Array[Dictionary], "R with a full magazine does nothing")
	w.set_trigger(true)
	_run(w, 0.6)
	w.set_trigger(false)
	var left := w.in_mag
	assert_true(left > 0 and left < 30, "after a short burst the magazine is part-used (%d)" % left)
	var ev := w.reload()
	assert_eq(_count(ev, &"reload_start"), 1, "R reloads mid-magazine")
	_run(w, 0.8)
	assert_true(w.reloading() and absf(w.reload_progress() - 0.5) < 0.05, "half-way through after 0.8 s (%.2f)" % w.reload_progress())
	ev = w.switch_to(&"sword")
	assert_eq(_count(ev, &"reload_cancel"), 1, "switching weapons cancels the running reload")
	assert_false(w.reloading(), "…so it is no longer reloading")
	assert_eq(w.in_mag, left, "…and the magazine keeps what it had")
	_run(w, 0.5)
	assert_eq(w.current, &"sword", "the saw sword is in hand after the switch")
	assert_eq(w.reload(), [] as Array[Dictionary], "R does nothing with the sword in hand")
	w.switch_to(&"gun")
	_run(w, 0.5)
	assert_eq(w.in_mag, left, "back to the rifle: the magazine still holds what it had")


func test_switch_holster_and_draw() -> void:
	var w := _ready_gun()
	w.set_trigger(true)
	_run(w, 0.05)
	w.switch_to(&"sword")
	assert_true(w.switching(), "a switch starts")
	var ev := _run(w, 1.0)
	var swapped := _first(ev, &"weapon")
	var swing := _first(ev, &"melee_start")
	var t0 := w.now - 1.0
	assert_eq(_count(ev, &"shot"), 0, "no shot while switching")
	assert_true(absf(swapped - t0 - 0.15) <= DT * 1.5, "the holster takes 0.15 s, then the sword is in hand (%.3f)" % (swapped - t0))
	assert_true(swing - t0 >= 0.35 - 0.001 and swing - t0 <= 0.35 + DT * 1.5, "the first swing comes after holster + draw 0.35 s (%.3f)" % (swing - t0))
	w.switch_to(&"gun")
	ev = _run(w, 1.0)
	t0 = w.now - 1.0
	var shot := _first(ev, &"shot")
	assert_true(shot - t0 >= 0.35 - 0.001, "back to the rifle, the first shot waits for holster + draw (%.3f)" % (shot - t0))
	assert_eq(w.other(), &"sword", "with the rifle in hand the other weapon is the saw sword")
	w.cycle()
	assert_eq(w.other(), &"gun", "while switching to the sword the other weapon is the rifle")
	var h := w.holster()
	assert_eq(w.current, &"none", "holster puts the weapon away at once")
	assert_eq(_count(h, &"weapon"), 1, "…with one weapon event")
	assert_false(w.busy(), "nothing is left counting after a holster")


func test_punch_timing_and_cooldown() -> void:
	var w := _ready_gun()
	var ev := w.melee()
	assert_eq(_count(ev, &"melee_start"), 1, "F punches")
	var t0 := w.now
	var later := _run(w, 0.3)
	var hit := _first(later, &"melee_hit")
	assert_true(absf(hit - t0 - 0.12) <= DT * 1.5, "the punch lands 0.12 s after the press (%.3f)" % (hit - t0))
	assert_eq(_count(w.melee(), &"melee_start"), 0, "a second punch inside 0.55 s is refused")
	_run(w, 0.26)
	assert_eq(_count(w.melee(), &"melee_start"), 1, "after 0.55 s it punches again")
	var none := ArenaWeapons.new()
	assert_eq(none.melee(), [] as Array[Dictionary], "no punch with no weapon drawn (walk mode)")


func test_sword_timing_and_cooldown() -> void:
	var w := _ready_gun()
	w.switch_to(&"sword")
	_run(w, 0.5)
	w.set_trigger(true)
	var ev := _run(w, 2.0)
	var starts := ev.filter(func(e: Dictionary) -> bool: return e["type"] == &"melee_start")
	var hits := ev.filter(func(e: Dictionary) -> bool: return e["type"] == &"melee_hit")
	assert_eq(starts.size(), 3, "held for 2.0 s the saw sword swings at 0, 0.8 and 1.6 s")
	if starts.size() >= 2:
		assert_true(absf(float(starts[1]["at"]) - float(starts[0]["at"]) - 0.8) <= DT * 1.5, "its cooldown is 0.8 s")
	if not hits.is_empty() and not starts.is_empty():
		assert_true(absf(float(hits[0]["at"]) - float(starts[0]["at"]) - 0.18) <= DT * 1.5, "each swing lands 0.18 s after it starts")
	assert_eq(_count(ev, &"shot"), 0, "the saw sword never fires a shot")


func test_melee_cone_goes_through_arena_combat() -> void:
	var targets := [
		{"node": null, "id": &"beast", "pos": Vector2(0.0, 1.2), "r": 0.6},
		{"node": null, "id": &"beast", "pos": Vector2(0.0, -1.2), "r": 0.6},
		{"node": null, "id": &"beast", "pos": Vector2(0.0, 2.8), "r": 0.6},
		{"node": null, "id": &"switch", "pos": Vector2(1.6, 1.0), "r": 0.35},
	]
	for id in ["punch", "sword"]:
		var hits := ArenaWeapons.melee_targets_hit(id, Vector2.ZERO, 0.0, targets)
		var want := targets.filter(func(t: Dictionary) -> bool: return ArenaCombat.melee_hits(id, Vector2.ZERO, 0.0, t["pos"], float(t["r"])))
		assert_eq(hits, want, id + ": the targets hit are exactly those ArenaCombat.melee_hits accepts")
	var punch := ArenaWeapons.melee_targets_hit("punch", Vector2.ZERO, 0.0, targets)
	assert_true(punch.has(targets[0]) and not punch.has(targets[1]), "a punch reaches what is in front, never what is behind")
	var sword := ArenaWeapons.melee_targets_hit("sword", Vector2.ZERO, 0.0, targets)
	assert_true(sword.has(targets[2]) and not punch.has(targets[2]), "the saw sword reaches further than the punch")
	var turned := ArenaWeapons.melee_targets_hit("punch", Vector2.ZERO, PI, targets)
	assert_true(turned.has(targets[1]) and not turned.has(targets[0]), "facing the other way turns the cone")


## The shoulder framing was tuned at integration (ARENA_SPEC §17): pivot 0.9 m right (was 0.55) and 1.8 m up (was 1.55),
## arm 3.0 m (was 2.6), FOV 65 (was 62). With the spec's numbers the 0.86 m wide egg sat over the crosshair and hid the
## beast once it came close; now it stands in the lower left third with the rifle beside it.
func test_shoulder_camera_math() -> void:
	for yaw in [0.0, 0.7, -1.9, PI * 0.5, 3.0]:
		var foot := Vector3(1.5, 0.0, -14.0)
		var pivot := ArenaCamera.shoulder_pivot(foot, yaw)
		var right := ArenaCamera.flat_right(yaw)
		var fwd := ArenaCamera.flat_forward(yaw)
		var off := pivot - foot
		assert_within(Vector2(off.x, off.z).length(), 0.9, 0.0001, "yaw %.2f: the pivot is 0.9 m from the player's centre line" % yaw)
		assert_within(off.dot(right), 0.9, 0.0001, "…on the camera's right")
		assert_within(off.y, 1.8, 0.0001, "…1.8 m up")
		for pitch in [-0.6, 0.0, 0.4]:
			var cam := ArenaCamera.camera_point(pivot, yaw, pitch, ArenaCamera.SHOULDER_ARM)
			var rel := cam - foot
			assert_within(rel.dot(right), 0.9, 0.0001, "yaw %.2f pitch %.1f: the camera point is 0.9 m right of the line through the player" % [yaw, pitch])
			assert_true(rel.dot(fwd) < 0.0, "…and behind the player")
			assert_within(cam.distance_to(pivot), 3.0, 0.0001, "…on a 3.0 m arm")


func test_aim_ray_is_the_viewport_centre() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	var vp := SubViewport.new()
	vp.size = Vector2i(1280, 720)
	vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	tree.root.add_child(vp)
	var rig := ArenaCamera.new()
	vp.add_child(rig)
	rig.set_shoulder(true, true)
	rig.snap(Vector3(2.0, 0.0, -15.0))
	rig.look(0.8, 0.25)
	rig.camera.position.z = ArenaCamera.SHOULDER_ARM
	var centre := Vector2(vp.size) * 0.5
	var n := rig.camera.project_ray_normal(centre)
	var o := rig.camera.project_ray_origin(centre)
	assert_true(rig.aim_dir().angle_to(n) < 0.001, "the aim direction is the ray through the viewport centre", str([rig.aim_dir(), n]))
	assert_true(rig.aim_origin().distance_to(o) < 0.001, "…from the camera", str([rig.aim_origin(), o]))
	# 0.9 m and FOV 65: the framing tuned at integration (see test_shoulder_camera_math)
	assert_within((rig.aim_origin() - Vector3(2.0, 0.0, -15.0)).dot(rig.right_flat()), 0.9, 0.001, "the live camera sits 0.9 m right of the player's line")
	assert_within(rig.camera.fov, 65.0, 0.001, "the shoulder camera's FOV is 65")
	rig.set_shoulder(false, true)
	assert_within(rig.camera.fov, ArenaCamera.FOV_WALK, 0.001, "the walk camera's FOV is 60")
	assert_within(rig.pitch, ArenaCamera.WALK_PITCH, 0.001, "back in walk mode the follow camera pitch is −0.35")
	vp.queue_free()
