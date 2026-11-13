extends SceneTree
## Generates the literal tables of core/battle/offsets.gd (BtOffsets, R1_PORT_SPEC §1.2). Tools may use floating-point
## trig: every table is computed with the page's own expression (same operation order, so the same doubles as V8) and
## then rounded the way v10 stores it. The block between BEGIN and END in offsets.gd is exactly render(); the unit test
## tests/unit/test_offsets.gd calls the static functions below and checks every entry and the block text.
##   <godot> --headless --path godot -s tools/gen_offsets.gd                print the block
##   <godot> --headless --path godot -s tools/gen_offsets.gd -- --write     rewrite the block in core/battle/offsets.gd
##   <godot> --headless --path godot -s tools/gen_offsets.gd -- --check     exit 1 when offsets.gd holds another block
## Page sources (battle-table.html, APP_VER 9.4): freeSpot near rings 31326-31329 and wide rings 31330-31333,
## roomToLand 31219-31223, planMove ring 34143-34146 and side steps 34152-34155, chargeSpots 31662-31682, deploy 31197.

const TARGET := "res://core/battle/offsets.gd"
const BEGIN := "# >>> gen_offsets"
const END := "# <<< gen_offsets"


## JavaScript Math.round: the nearest integer, an exact half goes towards +infinity (x - floor(x) is exact here).
static func js_round_f(x: float) -> int:
	var f := floorf(x)
	return int(f) + (1 if x - f >= 0.5 else 0)


## A page offset in inches -> MI on the 0.01 inch grid (v10 positions are multiples of 10 MI).
static func grid10(inches: float) -> int:
	return 10 * js_round_f(inches * 100.0)


## Q16 of a real number (65536 = 1).
static func q16(x: float) -> int:
	return js_round_f(x * 65536.0)


## freeSpot near rings: r = 1..10 (outer loop), a = 0..13; an = a*TAU/14 + r*0.41, offset (cos, sin)(an) * r * 1.25 in.
static func freespot_near() -> Array:
	var out: Array = []
	for r: int in range(1, 11):
		for a: int in 14:
			var an: float = a * TAU / 14 + r * 0.41
			out.append([grid10(cos(an) * r * 1.25), grid10(sin(an) * r * 1.25)])
	return out


## roomToLand probes: r = 1.25 then 2.5 in (the page's r += 1.25 loop), a = 0..11 at TAU/12; exact Math.round in MI
## (probes, not positions, so not on the 10 MI grid).
static func room_to_land() -> Array:
	var out: Array = []
	var r := 1.25
	while r <= 2.5:
		for a: int in 12:
			out.append([js_round_f(cos(a * TAU / 12) * r * 1000.0), js_round_f(sin(a * TAU / 12) * r * 1000.0)])
		r += 1.25
	return out


## planMove ring: k = 0 gives the slot itself; k = 1..6, a = 0..9: an = a*TAU/10 + k*0.37, offset cos -> x, sin -> z,
## radius k * 0.8 in, on the 10 MI grid.
static func plan_ring() -> Array:
	var out: Array = [[0, 0]]
	for k: int in range(1, 7):
		for a: int in 10:
			var an: float = a * TAU / 10 + k * 0.37
			out.append([grid10(cos(an) * k * 0.8), grid10(sin(an) * k * 0.8)])
	return out


## Q16 [cos, sin] of k * step for k = 1..4 (the page's Math.ceil(tries / 2) * step).
static func rot_table(step: float) -> Array:
	var out: Array = []
	for k: int in range(1, 5):
		var an: float = k * step
		out.append([q16(cos(an)), q16(sin(an))])
	return out


## chargeSpots: base angle +- k * 0.55 rad.
static func charge_rot() -> Array:
	return rot_table(0.55)


## planMove fallback side steps: base angle +- k * 0.4 rad.
static func sidestep_rot() -> Array:
	return rot_table(0.4)


## Scalars: Q16 of the deploy ring step (0.7 rad) and the freeSpot ring step (0.41 rad); FS_RING_K = 10^6 * 1.25 * TAU
## / 1.2, so that max(14, js_round(r * FS_RING_K, 10^6)) is the page's Math.max(14, Math.round(r * 1.25 * TAU / 1.2)).
static func scalars() -> Dictionary:
	return {"DEP_ANG_STEP": q16(0.7), "FS_ANG_STEP": q16(0.41), "FS_RING_K": js_round_f(1.25 * TAU / 1.2 * 1000000.0)}


## Every table by its constant name, in the order render() writes them.
static func tables() -> Dictionary:
	return {"FREESPOT_NEAR": freespot_near(), "ROOM_TO_LAND": room_to_land(), "PLAN_RING": plan_ring(),
		"CHARGE_ROT": charge_rot(), "SIDESTEP_ROT": sidestep_rot()}


## The comment line above each constant (Thai, like the rest of core/).
const NOTES := {
	"DEP_ANG_STEP": "## มุมที่วงลงสนามหมุนเพิ่มต่อวง (Q16 ของเจ็ดในสิบเรเดียน)",
	"FS_ANG_STEP": "## มุมที่วงหาที่ว่างหมุนเพิ่มต่อวง (Q16 ของสี่สิบเอ็ดในร้อยเรเดียน; free_spot ปัดผลคูณ r ทีละวงเอง)",
	"FS_RING_K": "## จำนวนจุดต่อวงของการหาที่ว่างแบบกว้าง x ล้าน (ดู fs_ring_n)",
	"FREESPOT_NEAR": "## freeSpot สิบวงแรก วงละสิบสี่จุด ห่างวงละหนึ่งนิ้วกับหนึ่งในสี่ (MI บนกริดสิบ)",
	"ROOM_TO_LAND": "## roomToLand จุดลองรอบจุดลงสนาม สองวง วงละสิบสองจุด (MI ปัดตรง ไม่อยู่บนกริด)",
	"PLAN_RING": "## planMove ช่องเดิมแล้วหกวงรอบช่อง วงละสิบจุด ห่างวงละแปดในสิบนิ้ว (MI บนกริดสิบ)",
	"CHARGE_ROT": "## chargeSpots มุมเบี่ยงทีละห้าสิบห้าในร้อยเรเดียน: [cos, sin] แบบ Q16 ของ k = 1..4",
	"SIDESTEP_ROT": "## planMove ทางเลี่ยงเฉียงทีละสี่ในสิบเรเดียน: [cos, sin] แบบ Q16 ของ k = 1..4",
}


static func _pair_line(rows: Array, from: int, to: int) -> String:
	var parts := PackedStringArray()
	for i: int in range(from, to):
		var p: Array = rows[i]
		parts.append("[%d, %d]" % [int(p[0]), int(p[1])])
	return "\t" + ", ".join(parts) + ","


## The generated block, BEGIN and END lines included, ending with a newline.
static func render() -> String:
	var lines := PackedStringArray()
	lines.append(BEGIN + " (สร้างด้วย tools/gen_offsets.gd ห้ามแก้มือ)")
	var sc := scalars()
	for name: String in ["DEP_ANG_STEP", "FS_ANG_STEP", "FS_RING_K"]:
		lines.append(NOTES[name])
		lines.append("const %s := %d" % [name, int(sc[name])])
	var tb := tables()
	# half a ring per line (lines stay short): freeSpot 7 of 14 points, roomToLand 6 of 12, planMove 1 then 5 of 10
	var widths := {"FREESPOT_NEAR": [7], "ROOM_TO_LAND": [6], "PLAN_RING": [1, 5], "CHARGE_ROT": [4], "SIDESTEP_ROT": [4]}
	for name: String in tb:
		var rows: Array = tb[name]
		var ws: Array = widths[name]
		lines.append(NOTES[name])
		lines.append("const %s := [" % name)
		var i := 0
		var wi := 0
		while i < rows.size():
			var wd: int = ws[mini(wi, ws.size() - 1)]
			lines.append(_pair_line(rows, i, mini(i + wd, rows.size())))
			i += wd
			wi += 1
		lines.append("]")
	lines.append(END)
	return "\n".join(lines) + "\n"


## The block currently inside a source text (BEGIN line through END line plus its newline), or "" when missing.
static func block_of(text: String) -> String:
	var a := text.find(BEGIN)
	var b := text.find(END)
	if a < 0 or b < a:
		return ""
	var e := text.find("\n", b)
	return text.substr(a, (e + 1 if e >= 0 else text.length()) - a)


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var block := render()
	if args.has("--write") or args.has("--check"):
		var path := ProjectSettings.globalize_path(TARGET)
		var text := FileAccess.get_file_as_string(path)
		var old := block_of(text)
		if old == "":
			printerr("gen_offsets: no %s ... %s block in %s" % [BEGIN, END, TARGET])
			quit(2)
			return
		if args.has("--check"):
			print("gen_offsets: " + ("up to date" if old == block else "DIFFERS from the generator"))
			quit(0 if old == block else 1)
			return
		var f := FileAccess.open(path, FileAccess.WRITE)
		f.store_string(text.replace(old, block))
		f.close()
		print("gen_offsets: wrote " + TARGET)
		quit(0)
		return
	print(block)
	quit(0)
