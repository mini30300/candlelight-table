class_name FieldTerrain
extends RefCounted
## พื้นสนามแบบจำนวนเต็ม (MI) ตามสูตร buildTerrain ของหน้าเก่า: กริดทุก CELL นิ้ว ความสูงจากนอยส์หลายชั้น
## ภูเขาใช้สันเขา ทะเลทรายมีสันเนินทราย ซากเมืองมีถนนเรียบพาดกลางโต๊ะ; ความสูงใช้กับภาพ กติกาใช้ตำแหน่งบนพื้นราบ

var w_in := 48
var d_in := 34
var cell_mi := 2000
var hw := 24
var hd := 17
var theme := "ruin"
var terrain := "hills"
var seed_value := 1
## ความสูงที่จุดกริด (hw+1) x (hd+1) แถวละ j
var hg := PackedInt64Array()
## ความสูงสูงสุดแบบค่าสัมบูรณ์ (MI)
var span_mi := 0


## ความลึกโต๊ะตามความกว้าง (นิ้ว): ปัด w x 36/100 แล้วคูณสอง แบบหน้าเก่า
static func depth_for(w: int) -> int:
	return Fx.idiv(w * 36 + 50, 100) * 2


## ขนาดช่องกริด (MI): ครึ่งนิ้วที่ใกล้ w/42 ที่สุด แต่ไม่ต่ำกว่า 2 นิ้ว
static func cell_for(w: int) -> int:
	return maxi(2000, Fx.idiv(2 * w + 21, 42) * 500)


static func make(w: int, d: int, theme_name: String, terrain_name: String, seed_v: int) -> FieldTerrain:
	var f := FieldTerrain.new()
	f.w_in = w
	f.d_in = d
	f.theme = theme_name
	f.terrain = terrain_name
	f.seed_value = seed_v
	f.build()
	return f


func build() -> void:
	cell_mi = cell_for(w_in)
	hw = Fx.idiv(2 * w_in * 1000 + cell_mi, 2 * cell_mi)
	hd = Fx.idiv(2 * d_in * 1000 + cell_mi, 2 * cell_mi)
	var th := GameData.theme_mi(theme)
	var rel: int = th.get("relief_mi", 3000)
	var rough: int = th.get("rough_mi", 1000)
	var dune := 900
	if terrain == "flat":
		rel = 350
		rough = 450
		dune = 250
	elif terrain == "mountain":
		rel = 11000
		rough = 1300
	hg = PackedInt64Array()
	hg.resize((hw + 1) * (hd + 1))
	span_mi = 0
	for j: int in hd + 1:
		for i: int in hw + 1:
			var x := -w_in * 500 + i * cell_mi
			var z := -d_in * 500 + j * cell_mi
			var h := point(x, z, rel, rough, dune)
			hg[j * (hw + 1) + i] = h
			span_mi = maxi(span_mi, absi(h))


## ความสูงที่จุด (x, z) เป็น MI (สูตรของหน้าเก่า คูณสัมประสิทธิ์เป็นส่วนพัน)
func point(x: int, z: int, rel: int, rough: int, dune: int) -> int:
	var s := seed_value
	var fine := _n(x, z, 4500, 2500, 6500, 2) * rough * 500 + _n(x, z, 1600, 0, 0, 2) * rough * 160
	var acc := 0
	if terrain == "mountain":
		var rg := FieldNoise.ridge(FieldNoise.at(x, 22000, 5300), FieldNoise.at(z, 22000, -7900), 3, s)
		acc = rg * rel * 1350 + _n(x, z, 40000, 3700, -1100, 2) * rel * 550 - FieldNoise.ONE * rel * 420 + fine
	else:
		acc = _n(x, z, 34000, 3700, -1100, 2) * rel * 1000 + _n(x, z, 12000, 9100, 4400, 2) * rel * 420 + fine
	var h := Fx.idiv(acc, 1000 * FieldNoise.ONE)
	if theme == "desert":
		# สันเนินทราย: คลื่นไซน์ตาม x (ร้อยละ 18 เรเดียนต่อนิ้ว) บวกนอยส์คูณ 22 ส่วน 10 สูงเท่า dune
		var ang := Fx.idiv(x * 18 * FieldNoise.ONE, 100000) + Fx.idiv(_n(x, z, 40000, 0, 0, 2) * 22, 10)
		h += Fx.idiv(Fx.isin_q16(ang) * dune, FieldNoise.ONE)
	if theme == "ruin":
		# ถนนกลางเมือง: แนวคดเคี้ยวตามนอยส์ กว้างห้านิ้วสองข้าง ความสูงลดลงเหลือ 35 ถึง 100 เปอร์เซ็นต์
		var wob := FieldNoise.fbm(FieldNoise.at(x, 18000, 21100), FieldNoise.HALF, 2, s)
		var band := absi(z + Fx.idiv(wob * 5000, FieldNoise.ONE))
		if band < 5000:
			h = Fx.idiv(h * (350 * 5000 + 650 * band), 5000000)
	return h


func _n(x: int, z: int, scale_mi: int, ox: int, oz: int, oct: int) -> int:
	return FieldNoise.fbm(FieldNoise.at(x, scale_mi, ox), FieldNoise.at(z, scale_mi, oz), oct, seed_value)


## ความสูงที่จุดกริด
func height(i: int, j: int) -> int:
	return hg[clampi(j, 0, hd) * (hw + 1) + clampi(i, 0, hw)]


## ความสูงที่ตำแหน่งใดก็ได้ (MI) แบบสองเส้นตรงตามหน้าเก่า ตัดขอบโต๊ะ
func height_at(x: int, z: int) -> int:
	var fx := clampi(x + w_in * 500, 0, hw * cell_mi)
	var fz := clampi(z + d_in * 500, 0, hd * cell_mi)
	var i := mini(Fx.idiv(fx, cell_mi), hw - 1)
	var j := mini(Fx.idiv(fz, cell_mi), hd - 1)
	var u := fx - i * cell_mi
	var v := fz - j * cell_mi
	var top := height(i, j) * (cell_mi - u) + height(i + 1, j) * u
	var bottom := height(i, j + 1) * (cell_mi - u) + height(i + 1, j + 1) * u
	return Fx.idiv(top * (cell_mi - v) + bottom * v, cell_mi * cell_mi)


func digest() -> String:
	return Hash.digest_hex(hg)
