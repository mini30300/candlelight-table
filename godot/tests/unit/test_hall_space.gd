extends "res://tests/testing.gd"
## HallSpace (scenes/hall/hall_space.gd, SHIP_LOBBY_SPEC §4, §6): the space seen through the warship deck's viewport.
## Per level: star count, dome and planet segments (checked through the exact triangle count), the mesh is cached;
## every vertex is behind the back wall (z < -8.5), inside the dome and finite; the planet and moon are inside the dome
## and no star sits in front of their discs; the farthest dome point is inside the camera's far plane; ship counts per
## level and every ship vertex stays inside the dome at both ends of its drift; from the spawn view the planet's lit limb
## shows through the lower half of the centre lancet and inside the field of view.
## Also the bake of HallBuilder (§7): with no cool lights it gives exactly lit(); cool lights only add light; with the
## deck's cool lights every vertex equals lit_cool(glow, cool_at) bit for bit, shared positions included (the bake
## caches the light per position and reads the cool lights from packed arrays).
## Headless and display-free (it also runs inside the exported game).

const LEVELS: PackedStringArray = ["hi", "mid", "lo", "min"]


func test_counts_per_level_and_cache() -> void:
	var stars := {"hi": 700, "mid": 500, "lo": 320, "min": 180}
	var dome := {"hi": Vector2i(24, 12), "mid": Vector2i(20, 10), "lo": Vector2i(16, 8), "min": Vector2i(12, 6)}
	var planet := {"hi": Vector2i(16, 10), "mid": Vector2i(16, 10), "lo": Vector2i(10, 6), "min": Vector2i(10, 6)}
	for l in LEVELS:
		assert_eq(int(HallSpace.STARS[l]), int(stars[l]), "%s: %d stars" % [l, int(stars[l])])
		assert_eq(HallSpace.DOME_SEGS[l], dome[l], "%s: dome segments" % l)
		assert_eq(HallSpace.PLANET_SEGS[l], planet[l], "%s: planet segments" % l)
		var d: Vector2i = dome[l]
		var p: Vector2i = planet[l]
		# review of 12 Nov: the moon uses the planet's segments (it was 4 fewer each way, its day/night edge looked jagged)
		var m := p
		# dome: one fan row + quads; spheres: two fan rows + quads; each star is a 2-triangle diamond
		var want := d.x * (2 * d.y - 1) + p.x * (2 * p.y - 2) + m.x * (2 * m.y - 2) + 2 * int(stars[l])
		var mesh := HallSpace.mesh(l)
		assert_eq(HallBuilder.tris(mesh), want, "%s: the space mesh has exactly the dome, planet, moon and %d stars" % [l, int(stars[l])])
		assert_true(HallSpace.mesh(l) == mesh, "%s: the space mesh is cached" % l)
	assert_true(int(HallSpace.STARS["min"]) * 2 + 600 < 2000, "min stays light")


func test_everything_is_behind_the_wall_and_inside_the_dome() -> void:
	for l in LEVELS:
		var arr := HallSpace.mesh(l).surface_get_arrays(0)
		var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var cols: PackedColorArray = arr[Mesh.ARRAY_COLOR]
		var bad := 0
		var nan := 0
		var far := 0.0
		for i in verts.size():
			var v := verts[i]
			if not (v.z < HallSpace.WALL_Z) or v.distance_to(HallSpace.DOME_C) > HallSpace.DOME_R + 0.01:
				bad += 1
			if is_nan(v.x) or is_nan(v.y) or is_nan(v.z) or is_nan(cols[i].r) or is_nan(cols[i].g) or is_nan(cols[i].b):
				nan += 1
			for cx in [-12.0, 12.0]:
				for cy in [0.0, 6.0]:
					for cz in [-8.0, 8.0]:
						far = maxf(far, v.distance_to(Vector3(cx, cy, cz)))
		assert_eq(bad, 0, "%s: every space vertex has z < -8.5 and lies within the dome" % l)
		assert_eq(nan, 0, "%s: no NaN position or colour" % l)
		assert_true(far < 85.0, "%s: the farthest space vertex from the room's corners is %.1f m (< 85, camera far 90)" % [l, far])


func test_planet_moon_and_stars() -> void:
	assert_true(HallSpace.PLANET_C.distance_to(HallSpace.DOME_C) + HallSpace.PLANET_R < HallSpace.DOME_R, "the planet is inside the dome")
	assert_true(HallSpace.MOON_C.distance_to(HallSpace.DOME_C) + HallSpace.MOON_R < HallSpace.DOME_R, "the moon is inside the dome")
	assert_true(HallSpace.PLANET_C.z + HallSpace.PLANET_R < HallSpace.WALL_Z and HallSpace.MOON_C.z + HallSpace.MOON_R < HallSpace.WALL_Z,
		"planet and moon are behind the back wall")
	# star vertices are the ones near the star shell (r 41); none may lie in the planet's or moon's disc seen from the dome centre
	var arr := HallSpace.mesh("hi").surface_get_arrays(0)
	var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var n := 0
	var hidden := 0
	for v in verts:
		var r := v.distance_to(HallSpace.DOME_C)
		if absf(r - HallSpace.STAR_R) > 0.5:
			continue
		n += 1
		var d := (v - HallSpace.DOME_C).normalized()
		for body in [[HallSpace.PLANET_C, HallSpace.PLANET_R], [HallSpace.MOON_C, HallSpace.MOON_R]]:
			var q: Vector3 = body[0]
			var t := (q - HallSpace.DOME_C).dot(d)
			if t > 0.0 and (HallSpace.DOME_C + d * t).distance_to(q) < float(body[1]):
				hidden += 1
	assert_true(n >= 700 * 4, "the hi mesh has its star vertices (%d)" % n)
	assert_eq(hidden, 0, "no star lies inside the planet's or the moon's disc")


func test_ships_per_level_stay_inside_the_dome() -> void:
	var want := {"hi": 5, "mid": 3, "lo": 3, "min": 0}
	var ship := HallSpace.ship_mesh()
	var sv: PackedVector3Array = ship.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	assert_true(HallBuilder.tris(ship) <= 48, "a ship is about 40 triangles (%d)" % HallBuilder.tris(ship))
	for l in LEVELS:
		var list := HallSpace.ship_instances(l)
		assert_eq(list.size(), int(want[l]), "%s: %d ships" % [l, int(want[l])])
		var bad := 0
		for d in list:
			assert_true(float(d["span"]) > 10.0 and float(d["speed"]) > 0.0, "%s: every ship drifts over a real span" % l)
			for s in [0.0, float(d["span"]), float(d["phase"])]:
				var xf := HallSpace.ship_transform(d, HallSpace.ship_pos(d, s))
				for v in sv:
					var w := xf * v
					if w.distance_to(HallSpace.DOME_C) >= HallSpace.DOME_R or w.z >= HallSpace.WALL_Z:
						bad += 1
					if w.distance_to(HallSpace.PLANET_C) < HallSpace.PLANET_R:
						bad += 1
		assert_eq(bad, 0, "%s: at both ends of its drift (and parked) every ship vertex is inside the dome and outside the planet" % l)


func test_spawn_view_sees_the_planet_through_the_centre_lancet() -> void:
	var pitch := -0.45
	var head := HallLayout.SPAWN + Vector3(0.0, 1.3, 0.0)
	var back := Vector3(0.0, -sin(pitch), cos(pitch))
	var arm := minf(6.5, HallLayout.room_clear(head, back, 0.45))
	var cam := head + back * arm
	assert_within(cam.y, 2.53, 0.05, "spawn camera height")
	assert_within(cam.z, 7.55, 0.05, "spawn camera depth")
	var limb := HallSpace.PLANET_C + HallSpace.PLANET_R * Vector3(sqrt(0.5), sqrt(0.5), 0.0)
	assert_true(Vector3(sqrt(0.5), sqrt(0.5), 0.0).dot(HallSpace.SUN) > 0.5, "that limb point faces the sun (lit)")
	var t := (-HallLayout.HALF.y - cam.z) / (limb.z - cam.z)
	var hit := cam + (limb - cam) * t
	var w: Dictionary = HallLayout.WINDOWS[0]
	assert_true(absf(hit.x) < float(w["x1"]) and hit.y > float(w["sill"]) and hit.y < float(w["spring"]),
		"the line to the lit limb crosses the back wall inside the centre lancet (%.2f, %.2f)" % [hit.x, hit.y])
	assert_true(hit.y < (float(w["sill"]) + float(w["apex"])) * 0.5, "it crosses the lower half of the lancet")
	var elev := atan2(limb.y - cam.y, Vector2(limb.x - cam.x, limb.z - cam.z).length())
	assert_true(elev < pitch + deg_to_rad(30.0) and elev > pitch - deg_to_rad(30.0),
		"the lit limb is inside the 60-degree field of view (elevation %.1f deg, top %.1f deg)" % [rad_to_deg(elev), rad_to_deg(pitch) + 30.0])


func test_bake_without_cool_lights_is_lit() -> void:
	var g := PropsLayer.Geo.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	for i in 60:
		var p := Vector3(rng.randf_range(-12, 12), rng.randf_range(0, 10), rng.randf_range(-8, 8))
		g.poly([p, p + Vector3(0.3, 0, 0), p + Vector3(0, 0.3, 0)], Color(rng.randf(), rng.randf(), rng.randf()), Vector3.BACK)
	var lights := HallLayout.flames()
	var src := g.c.duplicate()
	var want := PackedColorArray()
	for i in g.v.size():
		want.append(HallBuilder.lit(src[i], HallBuilder.glow(g.v[i], lights)))
	HallBuilder.bake(g, lights, [])
	var same := true
	for i in want.size():
		same = same and g.c[i].to_rgba32() == want[i].to_rgba32() and g.c[i] == want[i]
	assert_true(same, "bake with an empty cool list gives exactly lit() (byte-identical)")
	assert_true(HallBuilder.lit_cool(Color(0.5, 0.5, 0.5), 1.0, Color(0, 0, 0)) == HallBuilder.lit(Color(0.5, 0.5, 0.5), 1.0),
		"lit_cool with no cool light is lit()")
	var c := HallBuilder.cool_at(Vector3(0.0, 1.4, -2.0), HallLayout.COOL_LIGHTS)
	assert_true(c.g > c.r and c.g > 0.5, "over the war table the holo light is green-cyan and strong")
	var top := HallBuilder.COOL_MAX + 0.00001   # Color is float32
	assert_true(c.r <= top and c.g <= top and c.b <= top, "cool light is clamped")


func test_bake_with_cool_lights_matches_cool_at() -> void:
	# quads share corners, so positions repeat (the bake's per-position cache is exercised); bake with and without the
	# deck's cool lights and compare with the reference maths per vertex, bit for bit
	var lights := HallLayout.flames()
	for cool in [HallLayout.COOL_LIGHTS, []]:
		var g := PropsLayer.Geo.new()
		var rng := RandomNumberGenerator.new()
		rng.seed = 7
		for i in 300:
			var p := Vector3(rng.randf_range(-12, 12), rng.randf_range(0, 10), rng.randf_range(-8, 8))
			var col := Color(rng.randf(), rng.randf(), rng.randf())
			g.poly([p, p + Vector3(0.4, 0, 0), p + Vector3(0.4, 0.4, 0), p + Vector3(0, 0.4, 0)], col, Vector3.BACK)
			g.poly([p, p + Vector3(0, 0, 0.4), p + Vector3(0, 0.4, 0.4), p + Vector3(0, 0.4, 0)], col * 0.7, Vector3.LEFT)
		var src := g.c.duplicate()
		var unique := {}
		for v in g.v:
			unique[v] = true
		HallBuilder.bake(g, lights, cool)
		var diff := 0
		for i in g.v.size():
			var b := HallBuilder.glow(g.v[i], lights)
			var want := HallBuilder.lit(src[i], b) if cool.is_empty() else HallBuilder.lit_cool(src[i], b, HallBuilder.cool_at(g.v[i], cool))
			if g.c[i] != want or g.c[i].to_rgba32() != want.to_rgba32():
				diff += 1
		assert_true(unique.size() * 2 <= g.v.size(), "the test mesh repeats positions (%d unique of %d)" % [unique.size(), g.v.size()])
		assert_eq(diff, 0, "bake with %d cool lights equals the reference per vertex (%d vertices)" % [cool.size(), g.v.size()])
