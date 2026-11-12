extends "res://tests/testing.gd"
## HallLayout (scenes/hall/hall_layout.gd, LOBBY_SPEC §2.1): the walkable lobby hall's plan, pure data.
## Station footprints, pillars and candle stands do not overlap and stay inside the hall; the spawn is in no trigger;
## a flood fill on a 0.25 m grid with the avatar radius reaches every station's trigger from the spawn; station_at
## gives the expected id at sample points, "" in the open, and the nearest station where two triggers meet.
## Headless and display-free (it also runs inside the exported game).

const GRID := 0.25


func _circle_rect_gap(p: Vector2, r: float, rect: Rect2) -> float:
	return HallLayout.dist_to_rect(p, rect) - r


func test_stations_are_the_six_of_the_spec() -> void:
	assert_eq(HallLayout.IDS, PackedStringArray(["battle", "army", "settings", "online", "adventure", "exit"]), "six station ids")
	for id in HallLayout.IDS:
		assert_true(HallLayout.STATIONS.has(id), "station %s has a footprint" % id)
	assert_eq(HallLayout.rect_of("battle"), Rect2(-3.0, -4.0, 6.0, 4.0), "the war table is 6 x 4 m at (0, -2)")
	assert_within(HallLayout.reach_of("online"), 1.8, 0.0001, "the online gate reaches 1.8 m")
	assert_eq(HallLayout.PILLARS.size(), 6, "six pillars")
	assert_eq(HallLayout.STANDS.size(), 6, "six candle stands")


func test_nothing_overlaps_and_everything_is_inside() -> void:
	var rects: Array[Rect2] = []
	var names := PackedStringArray()
	for id in HallLayout.IDS:
		rects.append(HallLayout.rect_of(id))
		names.append(id)
	var outer := Rect2(-HallLayout.HALF - Vector2.ONE * HallLayout.WALL_T, (HallLayout.HALF + Vector2.ONE * HallLayout.WALL_T) * 2.0)
	var inner := Rect2(-HallLayout.HALF, HallLayout.HALF * 2.0)
	var bad := []
	for i in rects.size():
		# a footprint may be set into a wall (the gate and the door) but never past the wall's outer face
		if not outer.encloses(rects[i]) or not inner.has_point(rects[i].get_center()):
			bad.append(names[i] + " outside the hall")
		for j in range(i + 1, rects.size()):
			if rects[i].intersects(rects[j]):
				bad.append(names[i] + " overlaps " + names[j])
	var circles: Array = []
	for p in HallLayout.PILLARS:
		circles.append([p, HallLayout.PILLAR_R, "pillar %s" % str(p)])
	for p in HallLayout.STANDS:
		circles.append([p, HallLayout.STAND_R, "stand %s" % str(p)])
	for c in circles:
		var p: Vector2 = c[0]
		var r: float = c[1]
		if absf(p.x) + r > HallLayout.HALF.x or absf(p.y) + r > HallLayout.HALF.y:
			bad.append(str(c[2]) + " sticks out of the hall")
		for i in rects.size():
			if _circle_rect_gap(p, r, rects[i]) <= 0.0:
				bad.append(str(c[2]) + " overlaps " + names[i])
	for i in circles.size():
		for j in range(i + 1, circles.size()):
			var a: Array = circles[i]
			var b: Array = circles[j]
			if (a[0] as Vector2).distance_to(b[0]) <= float(a[1]) + float(b[1]):
				bad.append(str(a[2]) + " overlaps " + str(b[2]))
	for p in HallLayout.stools():
		if not HallLayout.rect_of("adventure").grow(-HallLayout.STOOL_R).has_point(p):
			bad.append("stool %s leaves the adventure table's footprint" % str(p))
	assert_eq(bad, [], "station footprints, pillars and stands neither overlap nor leave the hall")


func test_spawn_is_free_and_in_no_trigger() -> void:
	var s := HallLayout.spawn_xz()
	assert_eq(HallLayout.station_at(s), "", "the spawn (0, 5) is in no trigger")
	assert_false(HallLayout.blocked(s, HallLayout.AVATAR_R), "the avatar fits at the spawn")
	var d := HallLayout.dist_to_station(s, "battle") - HallLayout.reach_of("battle")
	# 12 Nov integration: the spawn moved from z 6 to z 5 on purpose. At z 6 the front wall pushed the camera arm down to
	# about 1.5 m, so the first view of the lobby was a giant see-through egg; at z 5 the arm stays about 2.9 m (opaque egg).
	assert_within(d, 3.4, 0.01, "the war table's trigger starts 3.4 m ahead of the spawn")
	assert_true(d >= 3.0, "the walk from the spawn to the war table is still at least 3 m (the flow test walks it)")


func test_flood_fill_reaches_every_station() -> void:
	var nx := int(HallLayout.HALF.x * 2.0 / GRID)
	var nz := int(HallLayout.HALF.y * 2.0 / GRID)
	var free := PackedByteArray()
	free.resize(nx * nz)
	for k in nz:
		for i in nx:
			free[k * nx + i] = 0 if HallLayout.blocked(_cell(i, k), HallLayout.AVATAR_R) else 1
	var s := HallLayout.spawn_xz()
	var si := int((s.x + HallLayout.HALF.x) / GRID)
	var sk := int((s.y + HallLayout.HALF.y) / GRID)
	assert_true(free[sk * nx + si] == 1, "the spawn cell is free")
	var seen := PackedByteArray()
	seen.resize(nx * nz)
	var queue := PackedInt32Array([sk * nx + si])
	seen[sk * nx + si] = 1
	var head := 0
	while head < queue.size():
		var c := queue[head]
		head += 1
		var i := c % nx
		var k := c / nx
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var ii: int = i + d.x
			var kk: int = k + d.y
			if ii < 0 or kk < 0 or ii >= nx or kk >= nz:
				continue
			var n := kk * nx + ii
			if free[n] == 1 and seen[n] == 0:
				seen[n] = 1
				queue.append(n)
	var reached := {}
	var picked := {}
	var free_n := 0
	for c in queue:
		var p := _cell(c % nx, c / nx)
		for id in HallLayout.IDS:
			if HallLayout.dist_to_station(p, id) <= HallLayout.reach_of(id):
				reached[id] = true
		var at := HallLayout.station_at(p)
		if at != "":
			picked[at] = true
	for c in free.size():
		free_n += free[c]
	for id in HallLayout.IDS:
		assert_true(reached.has(id), "the flood fill from the spawn reaches the %s trigger" % id)
		assert_true(picked.has(id), "station_at gives %s somewhere the avatar can walk" % id)
	assert_true(queue.size() > free_n * 0.9, "almost every free cell is connected to the spawn (%d of %d)" % [queue.size(), free_n])


func test_station_at_samples() -> void:
	var samples := {
		Vector2(0.0, 1.0): "battle", Vector2(2.0, 0.5): "battle", Vector2(-10.0, -1.0): "army",
		Vector2(9.0, -1.0): "settings", Vector2(0.0, -6.5): "online", Vector2(-3.0, 4.0): "adventure",
		Vector2(0.0, 7.0): "exit", Vector2(0.0, 4.0): "", Vector2(6.0, 4.0): "", Vector2(-6.0, -1.0): "",
		Vector2(5.5, -6.0): "",
	}
	for p in samples:
		assert_eq(HallLayout.station_at(p), str(samples[p]), "station_at %s" % str(p))
	for id in HallLayout.IDS:
		var f: Vector2 = HallLayout.STATIONS[id]["front"]
		assert_eq(HallLayout.station_at(f), id, "the ring in front of %s is inside its trigger" % id)
		assert_false(HallLayout.blocked(f, HallLayout.AVATAR_R), "the avatar fits on the %s ring" % id)


func test_ties_go_to_the_nearest_station() -> void:
	# between the war table and the adventure table both triggers overlap; the nearer footprint wins either way
	var cases := {Vector2(-3.2, 1.3): "battle", Vector2(-3.4, 1.4): "adventure", Vector2(-3.5, 1.5): "adventure"}
	for p: Vector2 in cases:
		var db := HallLayout.dist_to_station(p, "battle")
		var da := HallLayout.dist_to_station(p, "adventure")
		assert_true(db <= HallLayout.reach_of("battle") and da <= HallLayout.reach_of("adventure"),
			"%s is in both triggers (%.2f / %.2f m)" % [str(p), db, da])
		assert_eq(HallLayout.station_at(p), str(cases[p]), "the nearer station wins at %s" % str(p))


func test_blockers_and_flames() -> void:
	var tags := {}
	for b in HallLayout.blockers():
		tags[str(b["tag"])] = true
	for t in ["wall_back", "wall_front", "wall_left", "wall_right", "ceiling", "battle", "army", "settings", "online", "adventure", "exit"]:
		assert_true(tags.has(t), "blocker " + t)
	assert_true(HallLayout.inside_solid(Vector3(0.0, 6.2, 0.0)), "above y = 6 is solid (the invisible ceiling)")
	assert_true(HallLayout.inside_solid(Vector3(0.0, 0.5, -2.0)), "inside the war table is solid")
	assert_false(HallLayout.inside_solid(Vector3(0.0, 2.0, 4.0)), "the open floor is free")
	assert_eq(HallLayout.blocker_at(Vector2(8.5, -4.3), HallLayout.AVATAR_R), "pillar_1", "the avatar against a pillar names it")
	var f := HallLayout.flames()
	var fm := HallLayout.flames(true)
	assert_eq(f.size(), HallLayout.MAX_FLAMES, "24 flames on hi/mid/lo")
	assert_eq(fm.size(), HallLayout.MAX_FLAMES_MIN, "12 flames on min")
	var same := true
	for i in fm.size():
		same = same and f[i] == fm[i]
	assert_true(same, "the 12 flames of min are the first 12 of the full set (same places)")
	var inside := true
	for p in f:
		inside = inside and absf(p.x) < HallLayout.HALF.x and absf(p.z) < HallLayout.HALF.y and p.y > 0.5 and p.y < 3.0
	assert_true(inside, "every flame is inside the hall at candle height")


func test_camera_clearance() -> void:
	# the camera ray: walls and ceiling limit it, props pull it only when the camera point itself is inside one
	var o := Vector3(0.0, 1.3, 0.0)
	assert_within(HallLayout.room_clear(o, Vector3(0, 0, 1), 0.45), HallLayout.HALF.y - 0.45, 0.001, "room_clear: the front wall along +z")
	assert_within(HallLayout.room_clear(o, Vector3(-1, 0, 0), 0.45), HallLayout.HALF.x - 0.45, 0.001, "room_clear: the left wall along -x")
	assert_within(HallLayout.room_clear(o, Vector3(0, 1, 0), 0.45), HallLayout.CEIL_Y - 0.45 - 1.3, 0.001, "room_clear: the ceiling straight up")
	var pillar := HallLayout.PILLARS[3]   # (8.5, 0.5)
	var from := Vector3(pillar.x, 1.3, pillar.y - 2.5)
	var r := HallLayout.PILLAR_R + HallLayout.CAM_PAD
	assert_within(HallLayout.camera_clear(from, Vector3(0, 0, 1), 6.5), 6.5, 0.001,
		"a pillar that only stands between the head and the camera does not pull the camera")
	assert_within(HallLayout.camera_clear(from, Vector3(0, 0, 1), 2.5), 2.5 - r, 0.001,
		"a camera point inside a pillar is pulled to its near side")
	assert_within(HallLayout.camera_clear(from, Vector3(0, 0, 1), 2.6 + r * 0.6, HallLayout.CAM_PAD, 8.0), 2.5 + r, 0.001,
		"a camera point past the pillar's middle steps out behind it when there is room (no jump as a pillar passes)")
	assert_within(HallLayout.camera_clear(from, Vector3(0, 0, 1), 2.6 + r * 0.6, HallLayout.CAM_PAD, 2.6), 2.5 - r, 0.001,
		"no room behind the pillar: the camera goes to its near side")
	var bad := 0
	var rng := RandomNumberGenerator.new()
	rng.seed = 12
	for i in 400:
		var p := Vector3(rng.randf_range(-11.5, 11.5), 1.3, rng.randf_range(-7.5, 7.5))
		if HallLayout.blocked(Vector2(p.x, p.z), HallLayout.AVATAR_R):
			continue
		var d := Vector3.FORWARD.rotated(Vector3.RIGHT, rng.randf_range(0.15, 1.2)).rotated(Vector3.UP, rng.randf_range(-PI, PI))
		var room := HallLayout.room_clear(p, d, 0.45)
		var t := HallLayout.camera_clear(p, d, minf(rng.randf_range(3.0, 9.0), room), HallLayout.CAM_PAD, room)
		if t > room + 0.001 or HallLayout.inside_solid(p + d * t, 0.1):
			bad += 1
	assert_eq(bad, 0, "400 random camera rays from free spots end inside the hall and out of every blocker")


func _cell(i: int, k: int) -> Vector2:
	return Vector2(-HallLayout.HALF.x + (i + 0.5) * GRID, -HallLayout.HALF.y + (k + 0.5) * GRID)
