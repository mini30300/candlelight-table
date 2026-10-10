extends RefCounted
## Exact integer replica of the old page's hash2/hash3 (battle-table.html, `function hash2` / `function hash3`), for the
## oracle fixtures (R1_PORT_SPEC §6 step 4, §9 D17): building depths of injected page props come from it.
##
## The page computes in doubles:
##   h = (ix|0)*374761393 + (iy|0)*668265263 + SEED*1274126177; h = (h ^ (h>>>13))*1274126177; h = h ^ (h>>>16);
##   return ((h>>>0) % 65536) / 65536
## Every product and sum is an exact integer rounded to the nearest double (53 significant bits, ties to even), and the
## bit operators take that double modulo 2^32 (ToInt32 / ToUint32). The second multiply (int32 x 1274126177, up to
## 2^61) is where V8's rounding changes the result in practice; this file rounds every step the same way, so it also
## matches seeds and coordinates that make the first line exceed 2^53.
##
## hash2_q / hash3_q return q = value * 65536 (an int 0..65535; the page's value is exactly q / 65536).
## Test-side helper (not core): bld_*_mi use doubles the way the page does.

const TWO32 := 4294967296
const TWO31 := 2147483648
const TWO53 := 9007199254740992


## The double nearest to the integer v (ties to even), as an int. |v| must stay below 2^63.
static func dbl(v: int) -> int:
	var a := absi(v)
	if a <= TWO53:
		return v
	var bits := 0
	var t := a
	while t > 0:
		bits += 1
		t >>= 1
	var sh := bits - 53
	var q := a >> sh
	var r := a - (q << sh)
	var half := 1 << (sh - 1)
	if r > half or (r == half and (q & 1) == 1):
		q += 1
	var out := q << sh
	return -out if v < 0 else out


## ToUint32 of an integer-valued double.
static func u32(v: int) -> int:
	return v & (TWO32 - 1)


## ToInt32 of an integer-valued double.
static func i32(v: int) -> int:
	var u := u32(v)
	return u - TWO32 if u >= TWO31 else u


## page hash2(ix, iy) with SEED = seed, times 65536.
static func hash2_q(seed: int, ix: int, iy: int) -> int:
	var a := dbl(i32(ix) * 374761393)
	var b := dbl(i32(iy) * 668265263)
	var c := dbl(seed * 1274126177)
	var h := dbl(dbl(a + b) + c)
	var h1 := i32(h) ^ (u32(h) >> 13)
	var h2 := dbl(h1 * 1274126177)
	var h3 := i32(h2) ^ (u32(h2) >> 16)
	return u32(h3) % 65536


## page hash3(ix, iy, k) = hash2(ix*3 + k*7919, iy*5 - k*104729), times 65536 (integer ix, iy, k).
static func hash3_q(seed: int, ix: int, iy: int, k: int) -> int:
	var x := dbl(dbl(ix * 3) + dbl(k * 7919))
	var y := dbl(dbl(iy * 5) - dbl(k * 104729))
	return hash2_q(seed, x, y)


## JavaScript Math.round for the doubles of a fixture (half up, also for negatives).
static func js_roundf(v: float) -> int:
	return int(floor(v + 0.5))


## The page's bldSize depth (4.5 + hash3(h*131|0, 2, 61)*6)*s in MI, rounded like Math.round(x*1000); h >= 0.
static func bld_depth_mi(seed: int, h: float, s: float) -> int:
	var ih := int(h * 131.0)   # |0 truncates; h >= 0
	var hv := float(hash3_q(seed, ih, 2, 61)) / 65536.0
	return js_roundf((4.5 + hv * 6.0) * s * 1000.0)


## The page's bldSize width (5 + h*7)*s in MI, rounded like Math.round(x*1000).
static func bld_width_mi(h: float, s: float) -> int:
	return js_roundf((5.0 + h * 7.0) * s * 1000.0)
