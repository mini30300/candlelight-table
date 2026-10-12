extends "res://tests/testing.gd"
## core/field/terrain.gd (FieldTerrain) and Fx.isin_q16: the table grid sizes of the page, every height against the
## page's buildTerrain formula evaluated in floating point on the same noise values (so the integer port of the
## composition is faithful), bilinear height_at, ranges per terrain type, and pinned digests that the x86-64 and
## arm64 CI jobs must both reproduce.

const ONE := 65536.0


func test_isin() -> void:
	var worst := 0
	for k in range(-2000, 2001):
		var th := k * 331          # about -10..10 radians
		worst = maxi(worst, absi(Fx.isin_q16(th) - int(round(sin(th / ONE) * ONE))))
	assert_true(worst <= 4, "isin within 4/65536 of sin over -10..10 rad (worst %d)" % worst)
	assert_eq(Fx.isin_q16(0), 0, "sin 0 = 0")
	assert_true(absi(Fx.isin_q16(Fx.HALF_PI_Q16) - 65536) <= 2, "sin pi/2 = 1")
	var odd := 0
	for k in 500:
		odd = maxi(odd, absi(Fx.isin_q16(k * 977) + Fx.isin_q16(-k * 977)))
	assert_true(odd <= 1, "sin is odd (worst %d)" % odd)


func test_grid_sizes_like_the_page() -> void:
	assert_eq(FieldTerrain.depth_for(48), 34, "48-inch table is 34 deep (the default)")
	assert_eq(FieldTerrain.depth_for(100), 72, "100 -> 72")
	assert_eq(FieldTerrain.depth_for(26), 18, "26 -> 18")
	assert_eq(FieldTerrain.cell_for(48), 2000, "cell 2 in on a 48 table")
	assert_eq(FieldTerrain.cell_for(100), 2500, "cell 2.5 in on a 100 table")
	assert_eq(FieldTerrain.cell_for(180), 4500, "cell 4.5 in on a 180 table")
	var f := FieldTerrain.make(100, 72, "ruin", "hills", 1)
	assert_eq([f.hw, f.hd], [40, 29], "a 100 x 72 table has a 40 x 29 grid like the page")
	assert_eq(f.hg.size(), 41 * 30, "one height per grid point")


func _page_height(f: FieldTerrain, x: int, z: int) -> float:
	var s := f.seed_value
	var n := func(sc: int, ox: int, oz: int, oct: int) -> float:
		return FieldNoise.fbm(FieldNoise.at(x, sc, ox), FieldNoise.at(z, sc, oz), oct, s) / ONE
	var th := GameData.theme_mi(f.theme)
	var rel: float = th["relief_mi"] / 1000.0
	var rough: float = th["rough_mi"] / 1000.0
	var dune := 0.9
	if f.terrain == "flat":
		rel = 0.35
		rough = 0.45
		dune = 0.25
	elif f.terrain == "mountain":
		rel = 11.0
		rough = 1.3
	var h: float
	if f.terrain == "mountain":
		var rg := FieldNoise.ridge(FieldNoise.at(x, 22000, 5300), FieldNoise.at(z, 22000, -7900), 3, s) / ONE
		h = rg * rel * 1.35 + n.call(40000, 3700, -1100, 2) * rel * 0.55 - rel * 0.42 + n.call(4500, 2500, 6500, 2) * 0.5 * rough + n.call(1600, 0, 0, 2) * 0.16 * rough
	else:
		h = n.call(34000, 3700, -1100, 2) * rel + n.call(12000, 9100, 4400, 2) * rel * 0.42 + n.call(4500, 2500, 6500, 2) * 0.5 * rough + n.call(1600, 0, 0, 2) * 0.16 * rough
	if f.theme == "desert":
		h += sin(x / 1000.0 * 0.18 + n.call(40000, 0, 0, 2) * 2.2) * dune
	if f.theme == "ruin":
		var wob := FieldNoise.fbm(FieldNoise.at(x, 18000, 21100), FieldNoise.HALF, 2, s) / ONE
		var band := absf(z / 1000.0 + wob * 5.0)
		if band < 5.0:
			h *= 0.35 + 0.65 * (band / 5.0)
	return h * 1000.0


func test_heights_follow_the_page_formula() -> void:
	for cfg in [[48, "ruin", "hills", 1], [60, "desert", "flat", 7], [100, "forest", "mountain", 3], [72, "ice", "hills", 9], [80, "desert", "mountain", 5]]:
		var f := FieldTerrain.make(cfg[0], FieldTerrain.depth_for(cfg[0]), cfg[1], cfg[2], cfg[3])
		var worst := 0.0
		for j in range(0, f.hd + 1, 2):
			for i in range(0, f.hw + 1, 2):
				var x := -f.w_in * 500 + i * f.cell_mi
				var z := -f.d_in * 500 + j * f.cell_mi
				worst = maxf(worst, absf(f.height(i, j) - _page_height(f, x, z)))
		assert_true(worst <= 3.0, "%s/%s %d: heights within 3 MI of the page formula (worst %.2f)" % [cfg[1], cfg[2], cfg[0], worst])


func test_ranges_per_terrain() -> void:
	var flat := FieldTerrain.make(60, 44, "ruin", "flat", 2)
	var hills := FieldTerrain.make(60, 44, "forest", "hills", 2)
	var mount := FieldTerrain.make(60, 44, "ice", "mountain", 2)
	assert_true(flat.span_mi <= 1000, "flat stays within 1 in (%d MI)" % flat.span_mi)
	assert_true(hills.span_mi > flat.span_mi, "hills are higher than flat (%d > %d)" % [hills.span_mi, flat.span_mi])
	assert_true(mount.span_mi > 4000, "mountains rise over 4 in (%d MI)" % mount.span_mi)


func test_height_at_is_bilinear() -> void:
	var f := FieldTerrain.make(48, 34, "ruin", "hills", 4)
	var x0 := -24000 + 5 * f.cell_mi
	var z0 := -17000 + 7 * f.cell_mi
	assert_eq(f.height_at(x0, z0), f.height(5, 7), "on a grid point height_at is the grid height")
	var mid := f.height_at(x0 + f.cell_mi / 2, z0)
	var a := f.height(5, 7)
	var b := f.height(6, 7)
	assert_true(absi(mid - (a + b) / 2) <= 1, "halfway between two points is their mean")
	assert_eq(f.height_at(-999999, -999999), f.height(0, 0), "outside the table clamps to the corner")


func test_seeds_and_pins() -> void:
	var a := FieldTerrain.make(48, 34, "ruin", "hills", 1)
	var b := FieldTerrain.make(48, 34, "ruin", "hills", 1)
	var c := FieldTerrain.make(48, 34, "ruin", "hills", 2)
	assert_eq(a.digest(), b.digest(), "the same seed builds the same field")
	assert_ne(a.digest(), c.digest(), "another seed builds another field")
	var got := [a.digest(), FieldTerrain.make(60, 44, "desert", "flat", 7).digest(),
		FieldTerrain.make(100, 72, "forest", "mountain", 3).digest(), FieldTerrain.make(72, 52, "ice", "hills", 9).digest()]
	assert_eq(got, PIN, "pinned field digests (identical on every platform; re-pin only when the field changes on purpose)")
	assert_eq(GameData.terrain_names(), PackedStringArray(["flat", "hills", "mountain", "forest"]), "the four terrain types")
	assert_eq(GameData.theme_names().size(), 4, "four themes")
	assert_eq(GameData.theme_mi("ruin"), {"relief_mi": 3400, "rough_mi": 1200}, "ruin relief 3.4 in, rough 1.2 in")


const PIN := ["fb8f73e0257d436f", "5d728e39c87efd35", "413261960e766805", "aa18c23af690e2dd"]
