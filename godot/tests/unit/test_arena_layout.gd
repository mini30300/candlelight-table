extends "res://tests/testing.gd"
## ArenaLayout (scenes/arena/arena_layout.gd, ARENA_SPEC §4, §13.2): the weapons arena's plan, pure data.
## Interior, corridor and arch dimensions; pillars, stands and stations inside the room and apart; the centre lane stays
## clear; a flood fill (0.25 m grid, avatar radius) from SPAWN reaches every station trigger, the beast pad's edge and all
## four quadrants; lines of sight from the shoot line; mode hysteresis; leaving the arena; signs, lights and blockers.
## Headless and display-free (it also runs inside the exported game).

const GRID := 0.25
const R := 0.35


func test_dimensions() -> void:
	var rr := ArenaLayout.room_rect()
	assert_within(rr.size.x, 20.0, 0.001, "the room is 20 m wide")
	assert_within(rr.size.y, 24.0, 0.001, "the room is 24 m deep")
	assert_within(ArenaLayout.CORR_Z0 - ArenaLayout.CORR_Z1, 10.0, 0.001, "the corridor is 10 m long")
	assert_within(ArenaLayout.CORR_X * 2.0, 2.6, 0.001, "the corridor is 2.6 m wide")
	assert_within(ArenaLayout.CORR_Z1 - ArenaLayout.ROOM_MAX.y, ArenaLayout.WALL_T, 0.001, "the near wall is 0.5 m thick")
	var a: Dictionary = ArenaLayout.ARCH
	assert_within(float(a["x1"]) - float(a["x0"]), 2.0, 0.001, "the arch is 2 m wide")
	assert_true(float(a["apex"]) - float(a["spring"]) > (float(a["x1"]) - float(a["x0"])) * 0.5, "rise > half width: the arch is pointed")
	assert_true(float(a["apex"]) < ArenaLayout.CORR_H, "the arch fits under the corridor ceiling")
	assert_true(ArenaLayout.LINTEL_Y > float(a["spring"]) and ArenaLayout.LINTEL_Y < float(a["apex"]), "the lintel collider sits inside the arch's curve")
	assert_true(ArenaLayout.CEIL_Y < ArenaLayout.ROOM_H, "the invisible ceiling is under the drawn one")
	assert_true(ArenaLayout.in_corridor(Vector2(0.0, -10.25)), "the arch passage counts as corridor")
	assert_false(ArenaLayout.in_room(Vector2(0.0, -10.25)), "the arch passage is not the room")


func test_things_inside_and_apart() -> void:
	var circles: Array = []
	for p in ArenaLayout.PILLARS:
		circles.append([p, ArenaLayout.PILLAR_R, "pillar %s" % str(p)])
	for p in ArenaLayout.STANDS:
		circles.append([p, ArenaLayout.STAND_R, "stand %s" % str(p)])
	for id in ArenaLayout.IDS:
		var s: Dictionary = ArenaLayout.STATIONS[id]
		var h: Vector2 = s["h"]
		circles.append([s["c"], maxf(float(s["r"]), h.length()), id])
	var rr := ArenaLayout.room_rect()
	var bad := []
	for c in circles:
		var p: Vector2 = c[0]
		var r: float = c[1]
		if not rr.grow(-r).has_point(p):
			bad.append(str(c[2]) + " leaves the room")
	for i in circles.size():
		for j in range(i + 1, circles.size()):
			var a: Array = circles[i]
			var b: Array = circles[j]
			if (a[0] as Vector2).distance_to(b[0]) <= float(a[1]) + float(b[1]) + 0.5:
				bad.append(str(a[2]) + " is too close to " + str(b[2]))
	assert_eq(bad, [], "pillars, stands and stations sit in the room, apart")
	# the centre lane |x| < 2.4 stays clear from the shoot line to the pad
	var lane := []
	for p in ArenaLayout.PILLARS:
		if absf(p.x) - ArenaLayout.PILLAR_R < ArenaLayout.LANE_X:
			lane.append(str(p))
	assert_eq(lane, [], "no pillar enters the lane |x| < 2.4")
	var pad := Vector2(ArenaLayout.BEAST_SPAWN.x, ArenaLayout.BEAST_SPAWN.z)
	var near := INF
	for p in ArenaLayout.PILLARS:
		near = minf(near, p.distance_to(pad))
	assert_true(near >= 5.0, "the beast pad is %.2f m from the nearest pillar" % near)
	assert_false(ArenaLayout.blocked(pad, 0.6), "the beast fits on its pad")
	assert_false(ArenaLayout.blocked(Vector2(ArenaLayout.RESPAWN.x, ArenaLayout.RESPAWN.z), R), "the respawn spot is free")
	assert_eq(ArenaLayout.station_at(Vector2(ArenaLayout.RESPAWN.x, ArenaLayout.RESPAWN.z)), "", "the respawn spot is in no trigger")
	for id in ArenaLayout.IDS:
		var f: Vector2 = ArenaLayout.STATIONS[id]["front"]
		assert_eq(ArenaLayout.station_at(f), id, "the %s front ring is inside its trigger" % id)
		assert_false(ArenaLayout.blocked(f, R), "the avatar fits on the %s ring" % id)
		for o in ArenaLayout.IDS:
			if o != id:
				assert_true(ArenaLayout.dist_to_station(f, o) > float(ArenaLayout.STATIONS[o]["reach"]), "the %s ring is outside the %s trigger" % [id, o])


func _cell(i: int, k: int, origin: Vector2) -> Vector2:
	return origin + Vector2((i + 0.5) * GRID, (k + 0.5) * GRID)


func test_flood_fill_from_spawn() -> void:
	var origin := Vector2(ArenaLayout.ROOM_MIN.x, ArenaLayout.ROOM_MIN.y)
	var nx := int((ArenaLayout.ROOM_MAX.x - ArenaLayout.ROOM_MIN.x) / GRID)
	var nz := int((ArenaLayout.CORR_Z0 - ArenaLayout.ROOM_MIN.y) / GRID)
	var free := PackedByteArray()
	free.resize(nx * nz)
	for k in nz:
		for i in nx:
			free[k * nx + i] = 0 if ArenaLayout.blocked(_cell(i, k, origin), R) else 1
	var s := Vector2(ArenaLayout.SPAWN.x, ArenaLayout.SPAWN.z)
	var si := int((s.x - origin.x) / GRID)
	var sk := int((s.y - origin.y) / GRID)
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
	var quads := {}
	var pad := false
	var pc := Vector2(ArenaLayout.BEAST_SPAWN.x, ArenaLayout.BEAST_SPAWN.z)
	var room_c := ArenaLayout.room_rect().get_center()
	for c in queue:
		var p := _cell(c % nx, c / nx, origin)
		var at := ArenaLayout.station_at(p)
		if at != "":
			reached[at] = true
		if ArenaLayout.in_room(p):
			quads["%d%d" % [int(p.x > room_c.x), int(p.y > room_c.y)]] = true
		if absf(p.distance_to(pc) - ArenaLayout.PAD_R) < GRID:
			pad = true
	for id in ArenaLayout.IDS:
		assert_true(reached.has(id), "the flood fill from SPAWN reaches the %s trigger" % id)
	assert_true(pad, "the flood fill reaches the beast pad's edge")
	assert_eq(quads.size(), 4, "the flood fill reaches all four quadrants of the room")
	var free_n := 0
	for c in free.size():
		free_n += free[c]
	assert_true(queue.size() > free_n * 0.95, "almost every free cell is connected to the spawn (%d of %d)" % [queue.size(), free_n])


## a segment from a to b (3D) passes no shell or prop blocker (sampled every 5 cm)
func _clear(a: Vector3, b: Vector3) -> bool:
	var n := int(a.distance_to(b) / 0.05)
	for i in range(1, n):
		var p := a.lerp(b, float(i) / n)
		if ArenaLayout.inside_solid(p, 0.0):
			return false
	return true


func test_lines_of_sight() -> void:
	var eye := Vector3(0.0, 1.5, ArenaLayout.SHOOT_Z)
	var plate: Vector3 = ArenaLayout.STATIONS["switch"]["plate"]
	# stop just in front of the plate (the post itself is a blocker)
	var to_plate := plate - (plate - eye).normalized() * (float(ArenaLayout.STATIONS["switch"]["plate_r"]) + 0.05)
	assert_true(_clear(eye, to_plate), "the shoot line sees the switch plate")
	var b: Dictionary = ArenaLayout.BOARD
	var c: Vector3 = b["c"]
	var eye2 := Vector3(0.0, 1.5, -12.0)
	for sx in [-1.0, 1.0]:
		for sy in [-1.0, 1.0]:
			var corner := Vector3(c.x + sx * float(b["w"]) * 0.5, c.y + sy * float(b["h"]) * 0.5, ArenaLayout.ROOM_MIN.y + 0.06)
			assert_true(_clear(eye2, corner), "(0, 1.5, -12) sees the board corner %s" % str(corner))


func test_modes_and_leaving() -> void:
	assert_eq(ArenaLayout.mode_for(-11.2, &"walk"), &"walk", "-11.2 stays walk")
	assert_eq(ArenaLayout.mode_for(-11.4, &"walk"), &"shoot", "-11.4 switches to shoot")
	assert_eq(ArenaLayout.mode_for(-11.0, &"shoot"), &"shoot", "-11.0 stays shoot")
	assert_eq(ArenaLayout.mode_for(-10.7, &"shoot"), &"walk", "-10.7 switches back to walk")
	assert_true(ArenaLayout.SHOOT_Z < ArenaLayout.WALK_Z, "0.5 m of hysteresis between the lines")
	assert_true(ArenaLayout.leaving(-0.9, &"walk"), "walk mode at z -0.9 leaves")
	assert_false(ArenaLayout.leaving(-0.9, &"shoot"), "shoot mode never leaves")
	assert_false(ArenaLayout.leaving(-1.0, &"walk"), "z -1.0 does not leave")
	# SPAWN moved from z -2.2 to -3.6 at integration (ARENA_SPEC §17): at -2.2 the deck door cut the walk camera's arm
	# to about 1.6 m and the opaque egg filled the screen; at -3.6 the arm is about 3.2 m
	assert_within(ArenaLayout.LEAVE_Z - ArenaLayout.SPAWN.z, 2.65, 0.001, "SPAWN is 2.65 m from the leave line")
	var dc: Vector2 = ArenaLayout.DOOR_BACK["c"]
	var dh: Vector2 = ArenaLayout.DOOR_BACK["h"]
	var stop := dc.y - dh.y - R
	assert_within(stop, -0.65, 0.001, "DOOR_BACK stops the avatar at z -0.65")
	assert_true(stop >= ArenaLayout.LEAVE_Z, "the avatar stopped at the door is past LEAVE_Z")
	assert_false(ArenaLayout.blocked(Vector2(0.0, stop - 0.01), R), "the avatar can stand against the door")
	assert_true(ArenaLayout.blocked(Vector2(0.0, stop + 0.05), R), "the door box blocks beyond that")
	assert_eq(ArenaLayout.mode_for(ArenaLayout.SPAWN.z, &"walk"), &"walk", "the spawn is in walk mode")
	assert_eq(ArenaLayout.mode_for(ArenaLayout.RESPAWN.z, &"walk"), &"shoot", "the respawn spot is past the shoot line")


func test_signs_lights_flames() -> void:
	for id in ArenaLayout.IDS:
		var s: Dictionary = ArenaLayout.STATIONS[id]
		var p: Vector3 = s["sign"]
		assert_true(p.y > float(s["height"]) + 0.3, "the %s sign floats above its blocker" % id)
		assert_eq((ArenaLayout.SIGNS[id]["p"] as Vector3), p, "SIGNS.%s matches the station" % id)
	for id in ArenaLayout.SIGNS:
		var p: Vector3 = ArenaLayout.SIGNS[id]["p"]
		var q := Vector2(p.x, p.z)
		assert_true(ArenaLayout.in_room(q) or ArenaLayout.in_corridor(q), "sign %s is inside the room or corridor" % id)
		assert_false(ArenaLayout.inside_solid(p, 0.0), "sign %s is not inside a solid" % id)
	for l in ArenaLayout.LIGHTS:
		var p: Vector3 = l["p"]
		var q := Vector2(p.x, p.z)
		assert_true(float(l["k"]) > 0.0 and float(l["d"]) > 0.0, "light %s has k > 0 and D > 0" % str(p))
		assert_true((ArenaLayout.in_room(q) and p.y <= ArenaLayout.ROOM_H) or (ArenaLayout.in_corridor(q) and p.y <= ArenaLayout.CORR_H),
			"light %s is inside the room or corridor" % str(p))
	var f := ArenaLayout.flames()
	assert_eq(f.size(), 2, "two stand flames")
	for p in f:
		assert_true(p.y > ArenaLayout.STAND_H, "flame %s sits on its stand" % str(p))


func test_blockers_format() -> void:
	var hall := HallLayout.blockers()
	var box_keys := ["c", "h", "kind", "tag"]
	var cyl_keys := ["c", "kind", "r", "tag", "y0", "y1"]
	var tags := {}
	var bad := []
	for b in ArenaLayout.blockers():
		var keys := b.keys()
		keys.erase("layer")
		keys.sort()
		var want := box_keys if str(b["kind"]) == "box" else cyl_keys
		if keys != want:
			bad.append(str(b["tag"]) + " keys " + str(keys))
		if not ["shell", "prop"].has(str(b.get("layer", ""))):
			bad.append(str(b["tag"]) + " has no layer")
		tags[str(b["tag"])] = str(b.get("layer", ""))
	assert_eq(bad, [], "every blocker has HallLayout's format plus a layer")
	assert_true(str(hall[0]["kind"]) == "box" and (hall[0] as Dictionary).has("h"), "HallLayout's format for reference")
	for t in ["wall_far", "wall_left", "wall_right", "wall_near_left", "wall_near_right", "lintel", "ceiling", "corr_left",
			"corr_right", "corr_ceiling", "door_back", "pillar_0", "pillar_3"]:
		assert_eq(tags.get(t, ""), "shell", "blocker %s is shell" % t)
	for t in ["stand_0", "stand_1", "switch", "reset"]:
		assert_eq(tags.get(t, ""), "prop", "blocker %s is prop" % t)
	assert_true(ArenaLayout.inside_solid(Vector3(0.0, 6.6, -20.0)), "above y 6.5 in the room is solid")
	assert_true(ArenaLayout.inside_solid(Vector3(0.0, 4.7, -5.0)), "above y 4.6 in the corridor is solid")
	assert_true(ArenaLayout.inside_solid(Vector3(0.0, 3.6, -10.25)), "the lintel over the arch is solid")
	assert_false(ArenaLayout.inside_solid(Vector3(0.0, 2.0, -10.25)), "the arch passage is free")
	assert_true(ArenaLayout.inside_solid(Vector3(4.5, 2.0, -18.5)), "inside a pillar is solid")
	assert_true(ArenaLayout.inside_solid(Vector3(5.0, 2.0, -5.0)), "beside the corridor is solid")
	assert_false(ArenaLayout.inside_solid(Vector3(0.0, 1.6, -20.0)), "the open floor is free")
	assert_eq(ArenaLayout.blocker_at(Vector2(4.5, -17.5), R), "pillar_1", "the avatar against a pillar names it")
