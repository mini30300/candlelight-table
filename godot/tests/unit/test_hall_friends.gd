extends "res://tests/testing.gd"
## Friends on the warship deck (NET_SPEC §6.1, §6.2, §12.2 DECK): HallFriends.interp renders 100 ms behind the newest
## sample (stamped with local arrival time) with linear position and shortest-arc yaw, extrapolates past the newest
## sample with its speed for at most 150 ms and then holds, and is `done` once settled; a jump of more than 3 m snaps;
## spawn_for(0..5) are free spots (HallLayout.blocked at r 0.35) at least 0.8 m apart; set / remove keep the eggs
## MultiMesh's visible count and the Rings in step; the deck's ring capacity is 1 + IDS + 2 + MAX = 16; processing stops
## within 10 frames of the last (stop) sample. Fake time only: step(now_ms) is called directly, nothing waits.

const FRAME_MS := 16


func _s(x: float, z: float, yaw: float, sp: float, t: int) -> Dictionary:
	return {"x": x, "z": z, "yaw": yaw, "sp": sp, "t": t}


func _pose(x_m: float, z_m: float, yaw: float, sp: float) -> Dictionary:
	return {"x": roundi(x_m * 100.0), "z": roundi(z_m * 100.0), "yaw": roundi(yaw * 1000.0), "sp": roundi(sp * 100.0), "run": false, "t": 0}


func test_interp_delay_and_linear() -> void:
	var s := [_s(0.0, 0.0, 0.0, 1.0, 1000), _s(1.0, 0.0, 0.0, 1.0, 1100), _s(2.0, 0.0, 0.0, 1.0, 1200)]
	var r := HallFriends.interp(s, 1150)
	assert_within(float(r["x"]), 0.5, 0.0001, "100 ms behind: at 1150 ms the render time 1050 is half way between the first two samples")
	r = HallFriends.interp(s, 1275)
	assert_within(float(r["x"]), 1.75, 0.0001, "at 1275 ms: three quarters of the way from the second to the newest sample")
	assert_false(bool(r["done"]), "between samples the friend is not settled")
	assert_true(bool(r["moving"]), "a friend with speed is moving (bobs on hi/mid)")
	r = HallFriends.interp(s, 900)
	assert_within(float(r["x"]), 0.0, 0.0001, "before the first sample the friend holds at it")
	assert_eq(HallFriends.DELAY_MS, 100, "the render delay is 100 ms")


func test_interp_shortest_arc_yaw() -> void:
	var a := PI - 0.1
	var b := -PI + 0.1
	var s := [_s(0.0, 0.0, a, 0.5, 0), _s(0.0, 0.0, b, 0.5, 100)]
	var r := HallFriends.interp(s, 150)
	assert_within(absf(wrapf(float(r["yaw"]), -PI, PI)), PI, 0.001, "half way across +pi / -pi turns through pi, not through 0 (%.3f)" % float(r["yaw"]))


func test_interp_extrapolation_cap_and_hold() -> void:
	# moving along +x (yaw pi/2) at 2 m/s
	var s := [_s(0.0, 0.0, PI * 0.5, 2.0, 0), _s(0.2, 0.0, PI * 0.5, 2.0, 100)]
	var r := HallFriends.interp(s, 250)
	assert_within(float(r["x"]), 0.2 + 2.0 * 0.05, 0.0001, "50 ms past the newest sample: extrapolated with its speed and facing")
	assert_false(bool(r["done"]), "still extrapolating")
	r = HallFriends.interp(s, 100 + 100 + 150)
	assert_within(float(r["x"]), 0.2 + 2.0 * 0.15, 0.0001, "150 ms past the newest sample: the cap")
	assert_true(bool(r["done"]), "at the cap the friend is settled")
	var r2 := HallFriends.interp(s, 2000)
	assert_within(float(r2["x"]), float(r["x"]), 0.0001, "after the cap it holds (no endless drift)")
	assert_false(bool(r2["moving"]), "and stops bobbing")
	# a stop sample (sp 0): no extrapolation, settled once the render time passes it
	var st := [_s(0.0, 0.0, 0.0, 1.0, 0), _s(0.1, 0.0, 0.0, 0.0, 100)]
	var r3 := HallFriends.interp(st, 260)
	assert_within(float(r3["x"]), 0.1, 0.0001, "past a stop sample the friend stays on it")
	assert_true(bool(r3["done"]), "a stop sample settles at once")
	assert_eq(HallFriends.EXTRAP_MS, 150, "extrapolation is capped at 150 ms")


func test_spawn_spots() -> void:
	var bad := []
	for slot in 6:
		var p := HallFriends.spawn_for(slot)
		if HallLayout.blocked(Vector2(p.x, p.z), 0.35):
			bad.append("%d at %s" % [slot, str(p)])
		for other in range(slot + 1, 6):
			if p.distance_to(HallFriends.spawn_for(other)) < 0.8:
				bad.append("%d and %d closer than 0.8 m" % [slot, other])
	assert_eq(bad, [], "spawn_for(0..5) are free (r 0.35) and at least 0.8 m apart")
	assert_true(HallFriends.spawn_for(0).is_equal_approx(Vector3(-2.25, 0.0, 5.0)) and HallFriends.spawn_for(5).is_equal_approx(Vector3(2.25, 0.0, 5.0)),
		"the spots run from x -2.25 to 2.25 at z 5 (%s .. %s)" % [str(HallFriends.spawn_for(0)), str(HallFriends.spawn_for(5))])


func test_ring_capacity() -> void:
	assert_eq(HallWorld.ring_capacity(), 1 + HallLayout.IDS.size() + 2 + HallFriends.MAX, "the deck's Rings hold the avatar, the stations, two spares and every friend")
	assert_eq(HallWorld.ring_capacity(), 16, "16 rings")
	assert_eq(HallFriends.MAX, 5, "room for five friends (six players)")


func test_set_remove_keeps_eggs_and_rings_in_step() -> void:
	var rings: Rings = Rings.new()
	rings.setup(HallWorld.ring_capacity())
	var base := rings.count()
	var f := HallFriends.new()
	f.setup(null, rings)
	f.apply_level("min")
	assert_false(f.visible, "no friends: the node is hidden (no draw call)")
	for slot in [1, 2, 3, 4, 5]:
		f.set_friend(slot, "friend %d" % slot, HallWorld.slot_colour(slot))
	var c := f.counts()
	assert_eq(int(c["friends"]), 5, "five friends")
	assert_eq(int(c["capacity"]), HallFriends.MAX, "one MultiMesh with room for five eggs")
	var eggs := f.get_node_or_null("Eggs") as MultiMeshInstance3D
	assert_true(eggs != null and eggs.multimesh.visible_instance_count == 5 and f.visible, "five eggs drawn, the node visible")
	assert_eq(rings.count() - base, 5, "five friend rings in the deck's Rings")
	f.set_friend(6, "one too many", Color.WHITE)
	assert_eq(f.friend_count(), 5, "a sixth friend is refused (MAX 5)")
	f.remove_friend(3)
	assert_true(eggs.multimesh.visible_instance_count == 4 and rings.count() - base == 4, "removing one: four eggs and four rings")
	assert_false(f.has_friend(3), "slot 3 is gone")
	f.set_friend(3, "back", HallWorld.slot_colour(3))
	assert_true(eggs.multimesh.visible_instance_count == 5 and rings.count() - base == 5, "back again: five and five")
	var heads := f.heads()
	assert_eq(heads.size(), 5, "a head point per friend")
	assert_within((heads[0]["pos"] as Vector3).y, HallFriends.EGG_H + HallFriends.HEAD_UP, 0.001, "the name sits 0.35 m above the egg's top")
	assert_true((heads[0]["pos"] as Vector3).x < (heads[4]["pos"] as Vector3).x, "heads come in slot order")
	f.clear()
	assert_true(f.friend_count() == 0 and rings.count() == base and not f.visible, "clear: no friends, no rings, hidden")
	f.free()
	rings.free()


func test_poses_snap_settle_and_sleep() -> void:
	var rings: Rings = Rings.new()
	rings.setup(HallWorld.ring_capacity())
	var f := HallFriends.new()
	f.setup(null, rings)
	f.set_friend(2, "walker", HallWorld.slot_colour(2))
	var start := HallFriends.spawn_for(2)
	assert_true(f.friend_pos(2).is_equal_approx(start), "a new friend stands at its slot's spawn spot")
	# walk +z at 2 m/s, one pose every 100 ms
	var t := 10000
	var p := start
	for i in 5:
		p += Vector3(0.0, 0.0, 0.2)
		f.push_pose(2, _pose(p.x, p.z, 0.0, 2.0), t)
		for k in 6:
			f.step(t + k * FRAME_MS)
		t += 100
	assert_true(f.is_processing(), "while samples keep coming the friend processes")
	assert_true(f.friend_pos(2).z > start.z + 0.4 and f.friend_pos(2).z < p.z + 0.01, "it follows behind the newest pose (%.2f of %.2f)" % [f.friend_pos(2).z, p.z])
	# the stop pose: settled and asleep within 10 frames
	f.push_pose(2, _pose(p.x, p.z, 0.0, 0.0), t)
	var frames := 0
	while f.is_processing() and frames < 30:
		frames += 1
		f.step(t + frames * FRAME_MS)
	assert_false(f.is_processing(), "after the stop pose the friend stops processing")
	assert_true(frames <= 10, "within 10 frames of the last sample (%d)" % frames)
	assert_true(f.friend_pos(2).distance_to(p) < 0.01, "and stands on the stop pose")
	# a jump of more than 3 m (arena return, teleport) snaps at once
	var far := p + Vector3(4.0, 0.0, 0.0)
	f.push_pose(2, _pose(far.x, far.z, PI, 0.0), t + 1000)
	assert_true(f.friend_pos(2).distance_to(far) < 0.01, "a 4 m jump snaps to the new pose")
	# a pose that arrives before the member is a friend is kept for its first spot
	f.push_pose(4, _pose(1.0, 2.0, 0.0, 0.0), t + 2000)
	assert_false(f.has_friend(4), "a pose of an unknown slot draws nothing")
	f.set_friend(4, "late", HallWorld.slot_colour(4))
	assert_true(f.friend_pos(4).is_equal_approx(Vector3(1.0, 0.0, 2.0)), "set_friend places it at the pose that came first")
	f.clear()
	f.free()
	rings.free()
