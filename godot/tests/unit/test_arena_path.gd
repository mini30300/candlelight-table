extends "res://tests/testing.gd"
## ArenaPath (scenes/arena/arena_path.gd, ARENA_SPEC §8.4, §13.2): the hive beast's grid A* with string pulling over the
## arena's blockers (ArenaLayout.blockers() format). The world passes the blockers in; here they come from ArenaLayout
## when it exists, else from a copy of the spec's room (so this suite does not depend on ROOM's progress).

const RADIUS := 0.7     # BEAST.radius 0.6 + 0.1
const BOUNDS := Rect2(Vector2(-10.0, -34.5), Vector2(20.0, 24.0))
const PILLARS: PackedVector2Array = [Vector2(-4.5, -18.5), Vector2(4.5, -18.5), Vector2(-3.2, -24.5), Vector2(3.2, -24.5)]

var _path: ArenaPath
var _blockers: Array = []


func setup() -> void:
	_blockers = _room_blockers()
	_path = ArenaPath.new(BOUNDS, _blockers, RADIUS)


## ArenaLayout.blockers() when ROOM's layout is in, else the spec's room by hand (§4.1)
static func _room_blockers() -> Array:
	var lay := "res://scenes/arena/arena_layout.gd"
	if ResourceLoader.exists(lay):
		var s: Script = load(lay)
		if s != null and s.can_instantiate():
			var b: Variant = s.call("blockers")
			if b is Array and not (b as Array).is_empty():
				return b
	var out: Array = []
	out.append({"kind": "box", "c": Vector3(0, 3.5, -34.75), "h": Vector3(10.5, 3.5, 0.25), "tag": "wall_far"})
	out.append({"kind": "box", "c": Vector3(-10.25, 3.5, -22.5), "h": Vector3(0.25, 3.5, 12.5), "tag": "wall_left"})
	out.append({"kind": "box", "c": Vector3(10.25, 3.5, -22.5), "h": Vector3(0.25, 3.5, 12.5), "tag": "wall_right"})
	out.append({"kind": "box", "c": Vector3(-5.75, 3.5, -10.25), "h": Vector3(4.75, 3.5, 0.25), "tag": "wall_near_left"})
	out.append({"kind": "box", "c": Vector3(5.75, 3.5, -10.25), "h": Vector3(4.75, 3.5, 0.25), "tag": "wall_near_right"})
	out.append({"kind": "box", "c": Vector3(0, 5.2, -10.25), "h": Vector3(1.0, 1.8, 0.25), "tag": "lintel"})
	out.append({"kind": "box", "c": Vector3(0, 7.25, -22.5), "h": Vector3(10.5, 0.25, 12.5), "tag": "ceiling"})
	for i in PILLARS.size():
		out.append({"kind": "cyl", "c": PILLARS[i], "r": 0.8, "y0": 0.0, "y1": 4.0, "tag": "pillar_%d" % i})
	out.append({"kind": "cyl", "c": Vector2(-2.4, -11.2), "r": 0.28, "y0": 0.0, "y1": 1.72, "tag": "stand_0"})
	out.append({"kind": "cyl", "c": Vector2(2.4, -11.2), "r": 0.28, "y0": 0.0, "y1": 1.72, "tag": "stand_1"})
	out.append({"kind": "cyl", "c": Vector2(6.5, -13.5), "r": 0.35, "y0": 0.0, "y1": 2.4, "tag": "switch"})
	out.append({"kind": "box", "c": Vector3(-6.5, 0.55, -13.5), "h": Vector3(0.35, 0.55, 0.35), "tag": "reset"})
	return out


## The smallest distance from the path (sampled every 2 cm) to any blocker footprint.
func _min_clearance(pts: PackedVector2Array) -> float:
	var d := INF
	for i in range(1, pts.size()):
		var a := pts[i - 1]
		var b := pts[i]
		var n := maxi(int(ceil(a.distance_to(b) / 0.02)), 1)
		for k in n + 1:
			d = minf(d, _path.clearance(a.lerp(b, float(k) / n)))
	return d


func _length(pts: PackedVector2Array) -> float:
	var l := 0.0
	for i in range(1, pts.size()):
		l += pts[i - 1].distance_to(pts[i])
	return l


func test_grid() -> void:
	assert_eq(Vector2i(_path.cols, _path.rows), Vector2i(40, 48), "a 40 x 48 grid of 0.5 m cells over the room")
	var n_free := 0
	for v in _path.free:
		n_free += int(v)
	assert_true(n_free > 1200 and n_free < 1920, "most cells are free (%d of 1920)" % n_free)
	for p in PILLARS:
		assert_false(_path.is_free(_path.cell_of(p)), "the cell of pillar %s is blocked" % str(p))
	assert_true(_path.is_free(_path.cell_of(Vector2(0, -29))), "the beast's pad is free")
	assert_false(_path.is_free(_path.cell_of(Vector2(-9.9, -20))), "the cells along the wall are blocked for the beast's radius")


func test_paths_around_pillars() -> void:
	for p in PILLARS:
		# straight through the pillar, from one side to the other
		var a := p + Vector2(0, 3.0)
		var b := p + Vector2(0, -3.0)
		assert_false(_path.clear_line(a, b), "no straight line through pillar %s" % str(p))
		var path := _path.find(a, b)
		assert_true(path.size() >= 3, "the path around pillar %s bends (%d points)" % [str(p), path.size()])
		assert_eq(path[0], a, "it starts at the start")
		assert_eq(path[path.size() - 1], b, "it ends at the goal")
		var c := _min_clearance(path)
		assert_true(c >= RADIUS - 0.005, "the path round pillar %s keeps %.3f m >= the radius %.2f from every blocker" % [str(p), c, RADIUS])
		var l := _length(path)
		assert_true(l < 6.0 + 2.5, "and is short (%.2f m for a 6 m gap)" % l)
		var ok := true
		for i in range(1, path.size()):
			ok = ok and _path.clear_line(path[i - 1], path[i])
		assert_true(ok, "every leg of the pulled path is a clear line")
	# the long way: from the shoot line's corner to the far right corner behind the pillars
	var long := _path.find(Vector2(-8.5, -12.0), Vector2(8.5, -33.0))
	assert_true(_min_clearance(long) >= RADIUS - 0.005, "a long diagonal path keeps its clearance (%.3f m)" % _min_clearance(long))


func test_clear_line() -> void:
	var a := Vector2(0, -28)
	var b := Vector2(0, -13)
	assert_true(_path.clear_line(a, b), "the centre lane |x| < 2.4 is clear from the pad to the shoot line")
	var p := _path.find(a, b)
	assert_eq(p.size(), 2, "a clear line returns two points")
	assert_eq(p, PackedVector2Array([a, b]), "the start and the goal")
	assert_false(_path.clear_line(Vector2(-4.5, -16), Vector2(-4.5, -21)), "through a pillar is not clear")
	assert_false(_path.clear_line(Vector2(-3.5, -16), Vector2(-3.5, -21)), "brushing a pillar closer than the radius is not clear")
	assert_true(_path.clear_line(Vector2(-2.9, -16), Vector2(-2.9, -21)), "passing 0.8 m beside the pillar's edge is clear")
	assert_false(_path.clear_line(Vector2(-6.5, -12.0), Vector2(-6.5, -15.0)), "through the reset pedestal is not clear")
	assert_false(_path.clear_line(Vector2(0, -20), Vector2(0, -34.4)), "a line ending inside the wall's margin is not clear")


func test_blocked_targets() -> void:
	# a goal inside a pillar resolves to the nearest free cell
	var p := _path.find(Vector2(0, -29), PILLARS[3])
	var end := p[p.size() - 1]
	assert_true(_path.is_free(_path.cell_of(end)), "a goal inside a pillar ends on a free cell")
	assert_true(end.distance_to(PILLARS[3]) < 0.8 + RADIUS + 0.8, "next to that pillar (%.2f m from its centre)" % end.distance_to(PILLARS[3]))
	# a goal in the corner the beast cannot reach (by the wall)
	var q := _path.find(Vector2(0, -29), Vector2(-9.9, -34.4))
	var qe := q[q.size() - 1]
	assert_true(_path.is_free(_path.cell_of(qe)), "a goal in the wall's margin ends on a free cell")
	# free cell centres keep radius + 0.1 = 0.8 m from both walls: the nearest is (-8.75, -33.25), 1.63 m away
	assert_true(qe.distance_to(Vector2(-9.9, -34.4)) < 1.7, "the nearest one (%.2f m away)" % qe.distance_to(Vector2(-9.9, -34.4)))
	# a start that slid into a blocked cell still finds its way
	var r := _path.find(Vector2(-4.5, -17.3), Vector2(-4.5, -20.5))
	assert_true(r.size() >= 2, "a start next to a pillar still gets a path (%d points)" % r.size())


func test_deterministic_and_fast() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 4404
	var queries := []
	for i in 200:
		queries.append([Vector2(rng.randf_range(-9.5, 9.5), rng.randf_range(-34, -11)), Vector2(rng.randf_range(-9.5, 9.5), rng.randf_range(-34, -11))])
	var first := []
	var t0 := Time.get_ticks_usec()
	for q in queries:
		first.append(_path.find(q[0], q[1]))
	var us := float(Time.get_ticks_usec() - t0) / queries.size()
	var same := true
	for i in queries.size():
		same = same and _path.find(queries[i][0], queries[i][1]) == first[i]
	assert_true(same, "the same query gives the same path (200 queries twice)")
	var p2 := ArenaPath.new(BOUNDS, _blockers, RADIUS)
	var same2 := true
	for i in 50:
		same2 = same2 and p2.find(queries[i][0], queries[i][1]) == first[i]
	assert_true(same2, "a second ArenaPath built from the same blockers gives the same paths")
	print("      ArenaPath.find: %.0f us per query on average (200 random queries)" % us)
	assert_true(us < 2000.0, "200 random queries under 2 ms each on average (%.2f ms)" % (us / 1000.0))
	var bad := 0
	for i in queries.size():
		var p: PackedVector2Array = first[i]
		if p.size() >= 2 and _path.point_free(queries[i][0], RADIUS + 0.1) and _path.point_free(queries[i][1], RADIUS + 0.1):
			if _min_clearance(p) < RADIUS - 0.005:
				bad += 1
	assert_eq(bad, 0, "no path between free points comes closer than the radius to a blocker")
