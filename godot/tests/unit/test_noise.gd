extends "res://tests/testing.gd"
## core/field/noise.gd: the fixed-point fade/mix/vnoise/fbm against the same formulas in floating point (a faithful
## port of the page's noise), value ranges, continuity, independence of salts, and a pinned digest of a grid so the
## x86-64 and arm64 CI jobs prove they compute the same field.

const ONE := 65536


func _fade_f(t: float) -> float:
	return t * t * t * (t * (t * 6.0 - 15.0) + 10.0)


func _vnoise_f(x: float, y: float, salt: int) -> float:
	var ix := floori(x)
	var iy := floori(y)
	var u := _fade_f(x - ix)
	var v := _fade_f(y - iy)
	var h := func(a: int, b: int) -> float: return FieldNoise.lattice(a, b, salt) / 65536.0
	var top: float = lerpf(h.call(ix, iy), h.call(ix + 1, iy), u)
	var bottom: float = lerpf(h.call(ix, iy + 1), h.call(ix + 1, iy + 1), u)
	return lerpf(top, bottom, v) * 2.0 - 1.0


func _fbm_f(x: float, y: float, oct: int, salt: int) -> float:
	var s := 0.0
	var n := 0.0
	var a := 1.0
	var f := 1.0
	for i in oct:
		s += a * _vnoise_f(x * f, y * f, salt)
		n += a
		a *= 0.5
		f *= 2.0
	return s / n


func test_fade_and_mix() -> void:
	assert_eq(FieldNoise.fade_q(0), 0, "fade(0) = 0")
	assert_eq(FieldNoise.fade_q(ONE), ONE, "fade(1) = 1")
	assert_eq(FieldNoise.fade_q(ONE / 2), ONE / 2, "fade(1/2) = 1/2")
	var worst := 0
	var mono := true
	var prev := -1
	for t in range(0, ONE + 1, 97):
		var got := FieldNoise.fade_q(t)
		worst = maxi(worst, absi(got - int(round(_fade_f(t / 65536.0) * 65536.0))))
		if got < prev:
			mono = false
		prev = got
	assert_true(worst <= 2, "fade matches 6t^5-15t^4+10t^3 within 2/65536 (worst %d)" % worst)
	assert_true(mono, "fade never goes down")
	assert_eq(FieldNoise.mix_q(100, 300, ONE / 2), 200, "mix halfway")
	assert_eq(FieldNoise.mix_q(-50, 50, 0), -50, "mix at 0 is a")


func test_vnoise_matches_the_float_formula() -> void:
	var worst := 0
	var lo := ONE
	var hi := -ONE
	for j in 40:
		for i in 40:
			var x := i * 13107 - 200000    # 0.2 steps across negative and positive coordinates
			var y := j * 9830 - 150000
			var got := FieldNoise.vnoise(x, y, 7)
			var want := int(round(_vnoise_f(x / 65536.0, y / 65536.0, 7) * 65536.0))
			worst = maxi(worst, absi(got - want))
			lo = mini(lo, got)
			hi = maxi(hi, got)
	assert_true(worst <= 8, "vnoise equals the float formula within 8/65536 (worst %d)" % worst)
	assert_true(lo >= -ONE and hi <= ONE, "vnoise stays in -1..1 (%d..%d)" % [lo, hi])
	assert_true(hi - lo > ONE, "vnoise spans a real range (%d)" % (hi - lo))


func test_fbm_matches_the_float_formula() -> void:
	var worst := 0
	var sum := 0
	var count := 0
	for j in 32:
		for i in 32:
			var x := i * 21845 + 5000
			var y := j * 17476 - 90000
			for oct in [1, 2, 3]:
				var got := FieldNoise.fbm(x, y, oct, 11)
				var want := int(round(_fbm_f(x / 65536.0, y / 65536.0, oct, 11) * 65536.0))
				worst = maxi(worst, absi(got - want))
			sum += FieldNoise.fbm(x, y, 2, 11)
			count += 1
	assert_true(worst <= 16, "fbm equals the float formula within 16/65536 (worst %d)" % worst)
	assert_true(absi(sum / count) < ONE / 4, "fbm averages near zero (%d)" % (sum / count))


func test_continuity_and_salts() -> void:
	var jump := 0
	for i in 2000:
		var x := i * 655 - 600000
		jump = maxi(jump, absi(FieldNoise.vnoise(x + 655, 12345, 3) - FieldNoise.vnoise(x, 12345, 3)))
	assert_true(jump < ONE / 8, "a 1/100 step never jumps more than 1/8 (worst %d)" % jump)
	var same := 0
	for i in 200:
		if FieldNoise.vnoise(i * 40000, i * 30000, 1) == FieldNoise.vnoise(i * 40000, i * 30000, 2):
			same += 1
	assert_true(same < 20, "two salts give different fields (%d equal of 200)" % same)
	var r := FieldNoise.ridge(123456, -654321, 3, 5)
	assert_true(r >= 0 and r <= ONE, "ridge stays in 0..1 (%d)" % r)


func test_at_mi_scales_like_the_page() -> void:
	# page: fbm(x/34 + 3.7, ...) with x in inches; here x in MI and the offset in MI
	assert_eq(FieldNoise.at_mi(34000, 34, 0), ONE, "34 inches at scale 34 is 1.0")
	assert_eq(FieldNoise.at_mi(0, 34, 3700), int(3.7 * 65536), "the offset 3.7 is added in noise units")
	assert_eq(FieldNoise.at_mi(-17000, 34, 0), -ONE / 2, "negative coordinates work")


func test_pinned_grid() -> void:
	var vals := PackedInt64Array()
	for j in 24:
		for i in 32:
			vals.append(FieldNoise.fbm(i * 30000 - 400000, j * 25000 - 300000, 3, 1))
			vals.append(FieldNoise.ridge(i * 30000, j * 25000, 3, 2))
	var got := Hash.digest_hex(vals)
	assert_eq(got, "701222df94eabe78", "noise grid digest (identical on every platform; re-pin only when the noise changes on purpose)")
