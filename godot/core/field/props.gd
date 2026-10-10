class_name FieldProps
extends RefCounted
## สิ่งของบนสนามแบบจำนวนเต็ม ตามสูตร genProps ของหน้าเก่า: จุดสุ่มรวมเป็นกระจุก ชนิดตามฉาก ระยะห่างขั้นต่ำ
## ตึกตั้งบนที่ราบพอ ไม่ทับกัน ไม่ทับสิ่งก่อสร้าง ป่าทึบปลูกดงไม้ แล้วปรับพื้นใต้ของให้ราบ (ตึกก่อน)
## หน่วย: ตำแหน่งและรัศมีเป็น MI, มุม rot เป็นเรเดียน Q16, ขนาด s เป็นส่วนพัน, h เป็นเศษ Q16 (0..65535)
## รุ่นสิบใช้การตรวจทุกข้อทุกแบบ (หน้าเก่าข้ามการตรวจในแบบเนิน x1 เพื่อให้ตรงกับแอปรุ่นเก่า)

const ONE := 65536
const HALF := 32768
const TWO_PI := 411774
## เพดานจำนวนชิ้น (ของชุดพื้นฐานไม่นับ)
const PROP_CAP := 480
## ชนิดที่เป็นสิ่งก่อสร้าง (ความหนาแน่นมีผล และตึกห้ามทับ)
const STRUCT := ["building", "wall", "tower", "barricade", "pipe", "obelisk", "pillars", "arch", "buried"]
## ชนิดตามฉาก: [เกณฑ์ส่วนพัน, ชนิด] ไล่จากน้อยไปมาก ตัวสุดท้ายคือที่เหลือ
const THEME_KIND := {
	"ruin": [[400, "building"], [520, "wall"], [620, "tower"], [740, "rubble"], [850, "barricade"], [940, "crater"], [1000, "pipe"]],
	"forest": [[340, "tree"], [580, "pine"], [700, "boulder"], [800, "log"], [940, "bush"], [1000, "wall"]],
	"desert": [[160, "obelisk"], [400, "pillars"], [580, "buried"], [800, "boulder"], [940, "arch"], [1000, "deadtree"]],
	"ice": [[340, "iceslab"], [540, "boulder"], [700, "pine"], [860, "wall"], [1000, "crater"]],
}
## ชนิดของที่เพิ่มเมื่อความหนาแน่นเกินหนึ่ง (มีแต่สิ่งก่อสร้าง)
const EXTRA_KIND := {
	"ruin": [[300, "building"], [520, "wall"], [660, "tower"], [880, "barricade"], [1000, "pipe"]],
	"forest": [[400, "building"], [800, "wall"], [1000, "tower"]],
	"desert": [[220, "obelisk"], [520, "pillars"], [780, "buried"], [1000, "arch"]],
	"ice": [[360, "building"], [740, "wall"], [1000, "barricade"]],
}

var seed_value := 1
var theme := "ruin"
var terrain_kind := "hills"
var buildings := true
## ความหนาแน่นเป็นส่วนพัน (1000 = x1)
var density_pm := 1000
var field: FieldTerrain
var items: Array[Dictionary] = []


static func generate(f: FieldTerrain, has_buildings: bool, density_permille: int) -> FieldProps:
	var p := FieldProps.new()
	p.field = f
	p.seed_value = f.seed_value
	p.theme = f.theme
	p.terrain_kind = f.terrain
	p.buildings = has_buildings
	p.density_pm = density_permille
	p.build()
	return p


## ค่าสุ่ม 0..65535 ของชิ้นที่ k (แทน hash3 ของหน้าเก่า)
func u(k: int, a: int, b: int) -> int:
	return (Hash.ihash3(k, a, b, seed_value) >> 16) & 65535


static func sin_q(a: int) -> int:
	return Fx.isin_q16(a)


static func cos_q(a: int) -> int:
	return Fx.isin_q16(a + Fx.HALF_PI_Q16)


## ค่าสุ่มแปลงเป็นช่วงกึ่งกลางศูนย์: (u - ครึ่ง) x span
static func spread(v: int, span_mi: int) -> int:
	return Fx.idiv((v - HALF) * span_mi, ONE)


static func pick(table: Array, v: int) -> String:
	for row: Array in table:
		if v * 1000 < int(row[0]) * ONE:
			return row[1]
	return table[table.size() - 1][1]


static func rad_of(kind: String) -> int:
	match kind:
		"building":
			return 7000
		"wall", "pillars":
			return 4500
		"crater":
			return 3500
	return 2400


## ขนาดตึก (กว้าง ลึก) เป็น MI ตามที่วาด
func bld_size(o: Dictionary) -> PackedInt64Array:
	var hk: int = (int(o["h"]) * 131) >> 16
	var bw := Fx.idiv((5000 + ((int(o["h"]) * 7000) >> 16)) * int(o["s"]), 1000)
	var bd := Fx.idiv((4500 + ((u(hk, 2, 61) * 6000) >> 16)) * int(o["s"]), 1000)
	return PackedInt64Array([bw, bd])


## รอยเท้าที่ต้องตั้งบนพื้นราบ: {hx, hz, r} เป็น MI หรือ {} ถ้าไม่ต้อง
func foot_of(o: Dictionary) -> Dictionary:
	var s: int = o["s"]
	match str(o["kind"]):
		"building":
			var b := bld_size(o)
			return {"hx": b[0] / 2 + 600, "hz": b[1] / 2 + 600, "r": 0}
		"barricade":
			return {"hx": 33 * s / 10, "hz": 16 * s / 10, "r": 0}
		"log":
			return {"hx": 34 * s / 10, "hz": 5 * s / 10, "r": 0}
		"arch":
			return {"hx": 34 * s / 10, "hz": 8 * s / 10, "r": 0}
	var r: int = {"tower": 2900, "crater": 3700, "pipe": 2600, "buried": 3200, "obelisk": 1600, "rubble": 1800}.get(str(o["kind"]), 0)
	return {"hx": 0, "hz": 0, "r": Fx.idiv(int(r) * s, 1000)} if int(r) > 0 else {}


## พื้นต่างระดับมากแค่ไหนใต้รอยเท้า (มุมทั้งสี่กับกลาง)
func foot_range(o: Dictionary, f: Dictionary) -> int:
	var c := cos_q(o["rot"])
	var sn := sin_q(o["rot"])
	var ex: int = int(f["hx"]) + int(f["r"])
	var ez: int = int(f["hz"]) + int(f["r"])
	var lo := 1 << 50
	var hi := -(1 << 50)
	for pt: Array in [[0, 0], [ex, ez], [-ex, ez], [ex, -ez], [-ex, -ez]]:
		var px: int = pt[0]
		var pz: int = pt[1]
		var wx: int = int(o["x"]) + ((px * c + pz * sn) >> 16)
		var wz: int = int(o["z"]) + ((-px * sn + pz * c) >> 16)
		var h := field.height_at(wx, wz)
		lo = mini(lo, h)
		hi = maxi(hi, h)
	return hi - lo


## จุด (x, z) อยู่ในรอยตึก o ที่ขยายออก m หรือไม่
func in_foot(o: Dictionary, x: int, z: int, m: int) -> bool:
	var b := bld_size(o)
	var c := cos_q(o["rot"])
	var sn := sin_q(o["rot"])
	var dx: int = x - int(o["x"])
	var dz: int = z - int(o["z"])
	return absi(dx * c - dz * sn) < (b[0] / 2 + m) * ONE and absi(dx * sn + dz * c) < (b[1] / 2 + m) * ONE


func in_house(x: int, z: int, m: int) -> bool:
	for o: Dictionary in items:
		if o["kind"] == "building" and in_foot(o, x, z, m):
			return true
	return false


## ของที่ตึกใหม่จะทับ: null ถ้าทับสิ่งก่อสร้าง (วางไม่ได้) ไม่งั้นคือรายการของที่ต้องรื้อ (ต้นไม้ หิน ซาก)
func under_house(o: Dictionary) -> Variant:
	var out: Array[int] = []
	for q: int in items.size():
		var p := items[q]
		if p["kind"] == "building" or not in_foot(o, p["x"], p["z"], Fx.idiv(int(p["rad"]) * 6, 10)):
			continue
		if STRUCT.has(p["kind"]):
			return null
		out.append(q)
	return out


## ตึกสองหลังไม่ทับกัน (แกนแยก บนรอยเท้าที่หมุน) เว้นทาง m
func houses_clear(o: Dictionary, m: int) -> bool:
	var a := bld_size(o)
	var ca := cos_q(o["rot"])
	var sa := sin_q(o["rot"])
	for p: Dictionary in items:
		if p["kind"] != "building":
			continue
		var b := bld_size(p)
		var cb := cos_q(p["rot"])
		var sb := sin_q(p["rot"])
		var dx: int = int(p["x"]) - int(o["x"])
		var dz: int = int(p["z"]) - int(o["z"])
		var apart := false
		for ax: Array in [[ca, -sa], [sa, ca], [cb, -sb], [sb, cb]]:
			var lx: int = ax[0]
			var lz: int = ax[1]
			var ra := (a[0] / 2) * absi((ca * lx - sa * lz) >> 16) + (a[1] / 2) * absi((sa * lx + ca * lz) >> 16)
			var rb := (b[0] / 2) * absi((cb * lx - sb * lz) >> 16) + (b[1] / 2) * absi((sb * lx + cb * lz) >> 16)
			if absi(dx * lx + dz * lz) > ra + rb + m * ONE:
				apart = true
				break
		if not apart:
			return false
	return true


func room_for(x: int, z: int, gap: int) -> bool:
	for o: Dictionary in items:
		var r: int = int(o["rad"]) + gap
		if Fx.dist2(o["x"], o["z"], x, z) < r * r:
			return false
	return true


func build() -> void:
	items.clear()
	var w := field.w_in
	var d := field.d_in
	var area := w * d
	var base := Fx.idiv(2 * area + 28, 56)
	var dens := density_pm if buildings else 0
	var count := Fx.idiv(2 * base * maxi(1000, dens) + 1000, 2000)
	var gap := 1200 - Fx.idiv(900 * clampi(Fx.idiv((dens - 1000) * 1000, 1500), 0, 1000), 1000)
	var cls: Array = []
	for i: int in 5:
		cls.append([spread(u(i, 71, 3), w * 800), spread(u(i, 73, 5), d * 780)])
	for i: int in base:
		_place(i, base, dens, gap, cls)
	if terrain_kind == "forest":
		_woods()
	for i: int in range(base, count):
		if items.size() >= PROP_CAP:
			break
		_place(i, base, dens, gap, cls)
	# ตึกก่อน: เอียงแล้วเห็นชัดที่สุด ของเล็กปรับรอบ ๆ ทีหลัง
	var lock := PackedByteArray()
	lock.resize(field.hg.size())
	for pass_no: int in 2:
		for o: Dictionary in items:
			if (o["kind"] == "building") != (pass_no == 0):
				continue
			var f := foot_of(o)
			if not f.is_empty():
				level_under(o, f, lock)


func _spot(k: int, cls: Array) -> PackedInt64Array:
	var w := field.w_in
	var d := field.d_in
	if u(k, 11, 15) * 100 < 62 * ONE:
		var c: Array = cls[(u(k, 13, 17) * 5) >> 16]
		var rr := 5000 + ((u(k, 15, 19) * 11000) >> 16)
		var aa := (u(k, 17, 21) * TWO_PI) >> 16
		return PackedInt64Array([
			clampi(int(c[0]) + ((cos_q(aa) * rr) >> 16), -w * 460, w * 460),
			clampi(int(c[1]) + ((sin_q(aa) * rr) >> 16), -d * 460, d * 460)])
	return PackedInt64Array([spread(u(k, 7, 11), w * 920), spread(u(k, 9, 13), d * 900)])


func _place(i: int, base: int, dens: int, gap: int, cls: Array) -> void:
	var p := _spot(i, cls)
	var x := p[0]
	var z := p[1]
	var r := u(i, 3, 17)
	var kind := pick(THEME_KIND.get(theme, THEME_KIND["ruin"]), r) if i < base else pick(EXTRA_KIND.get(theme, EXTRA_KIND["ruin"]), r)
	if STRUCT.has(kind):
		if i * 1000 >= base * dens:
			return
	elif i >= base:
		return
	if not room_for(x, z, gap):
		return
	var o := {"kind": kind, "x": x, "z": z, "rot": (u(i, 4, 19) * TWO_PI) >> 16,
		"s": 750 + ((u(i, 5, 23) * 700) >> 16), "rad": rad_of(kind), "h": u(i, 6, 29)}
	# ตึก หอคอย เสาหิน ตั้งได้เฉพาะที่ลาดไม่มาก (บนภูเขาคือในหุบ)
	if kind == "building" or kind == "tower" or kind == "obelisk":
		if foot_range(o, foot_of(o)) > (4500 if kind == "building" else 3000):
			return
	if kind != "building":
		if in_house(x, z, Fx.idiv(int(o["rad"]) * 6, 10)):
			return
	else:
		var cut: Variant = under_house(o)
		if cut == null or not houses_clear(o, 1000):
			return
		var cut_list: Array[int] = cut
		for k: int in range(cut_list.size() - 1, -1, -1):
			items.remove_at(cut_list[k])
	items.append(o)


## ป่าทึบ: ดงไม้หนาเป็นหย่อม กับที่โล่งระหว่างดง ชนิดไม้ตามฉาก
func _woods() -> void:
	var w := field.w_in
	var d := field.d_in
	var n := Fx.idiv(2 * w * d + 9, 18)
	var ng := maxi(4, Fx.idiv(2 * w * d + 240, 480))
	var gs: Array = []
	for i: int in ng:
		gs.append([spread(u(i, 171, 3), w * 860), spread(u(i, 173, 5), d * 840), 5000 + ((u(i, 175, 7) * 7000) >> 16)])
	for i: int in n:
		if items.size() >= PROP_CAP:
			break
		var g: Array = gs[(u(i, 177, 9) * ng) >> 16]
		var rr := (Fx.isqrt(u(i, 179, 11) << 16) * int(g[2])) >> 16
		var aa := (u(i, 181, 13) * TWO_PI) >> 16
		var x := clampi(int(g[0]) + ((cos_q(aa) * rr) >> 16), -w * 470, w * 470)
		var z := clampi(int(g[1]) + ((sin_q(aa) * rr) >> 16), -d * 470, d * 470)
		var r := u(i, 183, 15)
		var kind := ""
		if theme == "ice":
			kind = "pine" if r * 100 < 82 * ONE else "deadtree"
		elif theme == "desert":
			kind = "tree" if r * 100 < 42 * ONE else ("deadtree" if r * 100 < 72 * ONE else "bush")
		else:
			kind = "tree" if r * 100 < 42 * ONE else ("pine" if r * 100 < 80 * ONE else "bush")
		if not room_for(x, z, 600) or in_house(x, z, 1400):
			continue
		items.append({"kind": kind, "x": x, "z": z, "rot": (u(i, 185, 17) * TWO_PI) >> 16,
			"s": 800 + ((u(i, 187, 19) * 550) >> 16), "rad": 2400, "h": u(i, 189, 21)})


## ปรับพื้นใต้ของให้ราบเท่าความสูงที่กลาง แล้วค่อย ๆ กลับเข้าเนินภายในหนึ่งช่องครึ่ง; lock กันไม่ให้ชิ้นหลังเอียงพื้นที่ราบแล้ว
func level_under(o: Dictionary, f: Dictionary, lock: PackedByteArray) -> void:
	var cell := field.cell_mi
	var h0 := field.height_at(o["x"], o["z"])
	var c := cos_q(o["rot"])
	var sn := sin_q(o["rot"])
	var core := cell
	var fade := Fx.idiv(cell * 3, 2)
	var hx: int = f["hx"]
	var hz: int = f["hz"]
	var fr: int = f["r"]
	var reach := Fx.isqrt(hx * hx + hz * hz) + fr + core + fade
	var ox: int = o["x"]
	var oz: int = o["z"]
	var half_w := field.w_in * 500
	var half_d := field.d_in * 500
	var i0 := maxi(0, Fx.idiv(ox - reach + half_w, cell))
	var i1 := mini(field.hw, -Fx.idiv(-(ox + reach + half_w), cell))
	var j0 := maxi(0, Fx.idiv(oz - reach + half_d, cell))
	var j1 := mini(field.hd, -Fx.idiv(-(oz + reach + half_d), cell))
	# รุ่นสิบ: ถ้าแกนราบของชิ้นนี้ทับลานที่ราบแล้วของชิ้นก่อน ใช้ระดับของลานนั้น (หน้าเก่าปล่อยให้ตึกหลังเอียง)
	var locked_sum := 0
	var locked_n := 0
	for j: int in range(j0, j1 + 1):
		for i: int in range(i0, i1 + 1):
			var k := j * (field.hw + 1) + i
			if lock[k] != 0 and _pad_dist(-half_w + i * cell - ox, -half_d + j * cell - oz, c, sn, hx, hz, fr) <= core:
				locked_sum += field.hg[k]
				locked_n += 1
	if locked_n > 0:
		h0 = Fx.idiv(locked_sum, locked_n)
	for j: int in range(j0, j1 + 1):
		for i: int in range(i0, i1 + 1):
			var k := j * (field.hw + 1) + i
			if lock[k] != 0:
				continue
			var dd := _pad_dist(-half_w + i * cell - ox, -half_d + j * cell - oz, c, sn, hx, hz, fr)
			var wq := ONE
			if dd >= core + fade:
				continue
			if dd > core:
				wq = ONE - Fx.idiv((dd - core) * ONE, fade)
			wq = (((wq * wq) >> 16) * (3 * ONE - 2 * wq)) >> 16
			field.hg[k] = field.hg[k] + (((h0 - field.hg[k]) * wq + HALF) >> 16)
			if dd <= core:
				lock[k] = 1


## ระยะจากจุด (dx, dz) ถึงรอยเท้าที่หมุน (ศูนย์เมื่ออยู่ข้างใน) เป็น MI
static func _pad_dist(dx: int, dz: int, c: int, sn: int, hx: int, hz: int, fr: int) -> int:
	var lx := (dx * c - dz * sn) >> 16
	var lz := (dx * sn + dz * c) >> 16
	var ex := maxi(0, absi(lx) - hx)
	var ez := maxi(0, absi(lz) - hz)
	return Fx.isqrt(ex * ex + ez * ez) - fr


func count_kind(kind: String) -> int:
	var n := 0
	for o: Dictionary in items:
		if o["kind"] == kind:
			n += 1
	return n


func digest() -> String:
	var v := PackedInt64Array()
	for o: Dictionary in items:
		v.append(Hash.fnv1a64_str(str(o["kind"])))
		v.append_array(PackedInt64Array([o["x"], o["z"], o["rot"], o["s"], o["rad"], o["h"]]))
	return Hash.digest_hex(v)
