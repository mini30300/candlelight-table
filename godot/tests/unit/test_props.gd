extends "res://tests/testing.gd"
## core/field/props.gd (FieldProps): the page's genProps rules hold on the integer port — kinds per theme, density 0
## leaves only nature, the cap, everything on the table, minimum spacing, houses never cross each other (checked with
## an independent floating-point separating-axis test), nothing stands inside a house, houses stand on levelled ground,
## and pinned digests of the props and of the levelled field for three setups.

const CONFIGS := [[48, "ruin", "hills", 1, 1000], [100, "forest", "forest", 3, 1000], [120, "ruin", "mountain", 5, 2500],
	[60, "desert", "flat", 7, 0], [72, "ice", "hills", 9, 1500]]
const WOOD_KINDS := ["tree", "pine", "bush", "deadtree"]

var made: Array = []


func setup() -> void:
	for c in CONFIGS:
		var f := FieldTerrain.make(c[0], FieldTerrain.depth_for(c[0]), c[1], c[2], c[3])
		made.append(FieldProps.generate(f, c[4] > 0, c[4]))


func _kinds_of(theme: String) -> Array:
	var out := WOOD_KINDS.duplicate()
	for row in FieldProps.THEME_KIND[theme] + FieldProps.EXTRA_KIND[theme]:
		out.append(row[1])
	return out


func test_kinds_counts_and_bounds() -> void:
	for n in made.size():
		var p: FieldProps = made[n]
		var tag := "%s/%s %d" % [p.theme, p.terrain_kind, p.field.w_in]
		assert_true(p.items.size() > 5, tag + ": props were placed (%d)" % p.items.size())
		assert_true(p.items.size() <= FieldProps.PROP_CAP, tag + ": at most the cap")
		var allowed := _kinds_of(p.theme)
		var bad := []
		for o in p.items:
			if not allowed.has(o["kind"]):
				bad.append(o["kind"])
			if absi(o["x"]) > p.field.w_in * 470 or absi(o["z"]) > p.field.d_in * 470:
				bad.append("outside %s" % o["kind"])
		assert_eq(bad, [], tag + ": only the theme's kinds, all on the table")
	var none := 0
	for o in made[3].items:
		if FieldProps.STRUCT.has(o["kind"]):
			none += 1
	assert_eq(none, 0, "buildings off (density 0): no structures")
	assert_true(made[0].count_kind("building") > 0, "a ruined city has buildings")
	assert_true(made[1].count_kind("tree") + made[1].count_kind("pine") > 50, "dense forest grows woods")


func test_spacing() -> void:
	for p: FieldProps in made:
		var worst := 1 << 40
		for i in p.items.size():
			for j in range(i + 1, p.items.size()):
				var a: Dictionary = p.items[i]
				var b: Dictionary = p.items[j]
				var dd := Fx.isqrt(Fx.dist2(a["x"], a["z"], b["x"], b["z"]))
				worst = mini(worst, dd - int(a["rad"]))
		assert_true(worst >= 299, "%s/%s: every later piece keeps at least 0.3 in past an earlier one's radius (worst %d MI)" % [p.theme, p.terrain_kind, worst])


func _sat_apart(p: FieldProps, a: Dictionary, b: Dictionary, lane: float) -> bool:
	var A := p.bld_size(a)
	var B := p.bld_size(b)
	var ra := float(a["rot"]) / 65536.0
	var rb := float(b["rot"]) / 65536.0
	var axes := [[cos(ra), -sin(ra)], [sin(ra), cos(ra)], [cos(rb), -sin(rb)], [sin(rb), cos(rb)]]
	var dx := float(b["x"] - a["x"])
	var dz := float(b["z"] - a["z"])
	for ax in axes:
		var pa: float = A[0] / 2.0 * absf(cos(ra) * ax[0] - sin(ra) * ax[1]) + A[1] / 2.0 * absf(sin(ra) * ax[0] + cos(ra) * ax[1])
		var pb: float = B[0] / 2.0 * absf(cos(rb) * ax[0] - sin(rb) * ax[1]) + B[1] / 2.0 * absf(sin(rb) * ax[0] + cos(rb) * ax[1])
		if absf(dx * ax[0] + dz * ax[1]) > pa + pb + lane:
			return true
	return false


func test_houses_never_cross() -> void:
	for p: FieldProps in made:
		var houses := []
		for o in p.items:
			if o["kind"] == "building":
				houses.append(o)
		var crossing := 0
		for i in houses.size():
			for j in range(i + 1, houses.size()):
				if not _sat_apart(p, houses[i], houses[j], 900.0):
					crossing += 1
		assert_eq(crossing, 0, "%s/%s: %d houses, none crossing another (float SAT, 0.9 in lane)" % [p.theme, p.terrain_kind, houses.size()])


func test_nothing_inside_a_house() -> void:
	for p: FieldProps in made:
		var inside := []
		for o in p.items:
			if o["kind"] != "building":
				continue
			for q in p.items:
				if q["kind"] != "building" and p.in_foot(o, q["x"], q["z"], 0):
					inside.append(q["kind"])
		assert_eq(inside, [], "%s/%s: no piece stands inside a house" % [p.theme, p.terrain_kind])


func test_houses_stand_level() -> void:
	var worst := 0
	var total := 0
	for p: FieldProps in made:
		for o in p.items:
			if o["kind"] != "building":
				continue
			total += 1
			var b := p.bld_size(o)
			worst = maxi(worst, p.foot_range(o, {"hx": b[0] / 2, "hz": b[1] / 2, "r": 0}))
	assert_true(total > 10, "enough houses to judge (%d)" % total)
	assert_true(worst <= 50, "every house's walls stand level within 0.05 in, even next to another house's pad (worst %d MI)" % worst)


func test_deterministic_and_pinned() -> void:
	var f2 := FieldTerrain.make(48, 34, "ruin", "hills", 1)
	var again := FieldProps.generate(f2, true, 1000)
	assert_eq(again.digest(), made[0].digest(), "the same setup places the same props")
	assert_eq(f2.digest(), made[0].field.digest(), "and levels the same ground")
	var f3 := FieldTerrain.make(48, 34, "ruin", "hills", 2)
	assert_ne(FieldProps.generate(f3, true, 1000).digest(), made[0].digest(), "another seed places other props")
	var got := [made[0].digest(), made[0].field.digest(), made[1].digest(), made[1].field.digest(), made[2].digest(), made[2].field.digest()]
	assert_eq(got, PIN, "pinned props and levelled-field digests (identical on every platform; re-pin only on purpose)")


const PIN := ["a9e19287d374454a", "f5c2e2de1b4dbf42", "2b8afdbf6d5053ea", "42efeef360b9b796", "83f4975e562b6de8", "00f10e87e0867627"]
