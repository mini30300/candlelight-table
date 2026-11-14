class_name MissionLayout
extends RefCounted
## ผังสนามรบของภารกิจ (CAMPAIGN_SPEC §5.4, track C): ฟังก์ชันล้วนของ spec (seed, ชีวนิเวศ, ประเภท, เป้าหมายรอง)
## RNG ตัวเดียว seed = spec.seed ^ SALT สุ่มตามลำดับคงที่ จึงได้ผังเดิมทุกเครื่องทุกครั้ง · ไม่มีโหนด ไม่มีฟิสิกส์ ไม่อ่านนาฬิกา
## พื้นที่ 44 × 44 ม. (x, z ใน ±22) ล้อมด้วยหน้าผา (ชั้น shell) · ของบัง: หินเตี้ย/กำแพงเตี้ย (ชั้น prop) ของสูง (ชั้น shell
## แขนกล้องชน) · ทุกจุดสำคัญ (จุดเกิด จุดรับ ฐาน สัญญาณ ตัวประกัน เสาพิธี จุดเกิดศัตรู) เดินถึงได้จากจุดเกิดผู้เล่น
## (ตรวจด้วยตารางเดียวกับ ArenaPath: ช่อง 1 ม. ระยะเผื่อ 0.6 ม.) ถ้าไม่ถึงก็ถอดของบังที่ใกล้จุดนั้นออกทีละชิ้น
## ที่กันใช้รูปแบบ HallLayout.blockers() ({kind box/cyl, c, h | r y0 y1, tag, layer "shell" | "prop"})

const HALF := Vector2(22.0, 22.0)
const WALL_T := 2.0
const WALL_H := 6.0
const SALT := 0x51A7E
## ตารางตรวจทางเดิน (เท่ากับ ArenaPath ของโลก: radius 0.5 + CELL_PAD 0.1)
const CELL := 1.0
const CLEAR := 0.6
## ช่องว่างขั้นต่ำระหว่างของบัง (ม.) ศัตรูตัวใหญ่ (r 0.75) ยังเดินลอดได้
const GAP := 2.4
## สูงเกินนี้ = ของสูง (ชั้น shell)
const TALL := 1.8
const N_COVER := {"ruin": 26, "forest": 28, "desert": 18, "ice": 22, "volcanic": 22, "toxic": 24}
## ชนิดของบัง: [รูปร่าง, ขนาดต่ำ, ขนาดสูง, สูงต่ำ, สูงสูง] (box: ขนาด = ความยาว, หนา 0.5–0.6 / cyl: ขนาด = รัศมี)
const PIECES := {
	"rock": ["cyl", 0.8, 1.5, 1.0, 1.6],
	"boulder": ["cyl", 1.6, 2.3, 2.2, 3.4],
	"wall_low": ["box", 2.2, 4.0, 1.1, 1.2],
	"wall_high": ["box", 2.6, 5.0, 3.0, 3.6],
	"crate": ["box", 1.0, 1.4, 1.0, 1.4],
	"tree": ["cyl", 0.35, 0.5, 6.0, 7.0],
	"spire": ["cyl", 0.5, 0.8, 3.0, 5.0],
	"barrel": ["cyl", 0.42, 0.5, 1.1, 1.2],
}
## น้ำหนักการสุ่มชนิดต่อชีวนิเวศ (ลำดับคงที่)
const BIOME_PIECES := {
	"ruin": [["wall_low", 3], ["wall_high", 3], ["crate", 2], ["rock", 1], ["spire", 1]],
	"forest": [["tree", 5], ["rock", 2], ["boulder", 1], ["wall_low", 1]],
	"desert": [["rock", 3], ["boulder", 2], ["wall_low", 1], ["crate", 1]],
	"ice": [["spire", 3], ["rock", 2], ["boulder", 2], ["wall_low", 1]],
	"volcanic": [["spire", 2], ["boulder", 3], ["rock", 3]],
	"toxic": [["barrel", 3], ["wall_low", 2], ["crate", 2], ["wall_high", 1], ["rock", 1]],
}
const STAKES := 12               # หลักรั้วรอบค่าย (เว้นช่องทางเข้า 3 ช่อง)
const STAKE_R := 0.55
const CAMP_R := 8.5
const BASE_CORE_R := 1.2
const N_DECOR := 46


## ผังของ spec: {"half", "biome", "blockers", "player_spawn", "player_yaw", "spawns", "near_spawns", "posts": {"camp", "cover"},
## "points": {"base", "pickup", "beacon", "camp", "hostages", "pylons"}, "decor": [{kind, pos, s}]}
## hostages / pylons: ของเป้าหมายหลักก่อน (3) แล้วของเป้าหมายรอง (1) · จุดที่ภารกิจนี้ไม่ใช้ก็คิดไว้ (ไม่มีผลกับที่กัน)
static func build(spec: Dictionary) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(spec.get("seed", 0)) ^ SALT
	var ptype := str((spec.get("primary", {}) as Dictionary).get("type", "purge"))
	var sec_types := PackedStringArray()
	for e: Dictionary in spec.get("secondary", []):
		sec_types.append(str(e.get("type", "")))
	var biome := str(spec.get("biome", "ruin"))
	if not BIOME_PIECES.has(biome):
		biome = "ruin"
	# จุดคงที่ (สุ่มตามลำดับเดิมเสมอ ไม่ขึ้นกับประเภท)
	var spawn_z := 9.5 if ptype == "defend" else 18.5
	var player_spawn := Vector3(rng.randf_range(-4.0, 4.0), 0.0, spawn_z)
	var pickup := Vector3(rng.randf_range(-8.0, 8.0), 0.0, 15.0)
	var base := Vector3(rng.randf_range(-3.0, 3.0), 0.0, rng.randf_range(1.0, 4.0))
	var camp := Vector3(rng.randf_range(-8.0, 8.0), 0.0, rng.randf_range(-12.5, -10.5))
	var side := 1.0 if rng.randf() < 0.5 else -1.0
	var beacon := Vector3(side * rng.randf_range(11.0, 15.0), 0.0, rng.randf_range(-5.0, 5.0))
	var cage := Vector3(-side * rng.randf_range(11.0, 15.0), 0.0, rng.randf_range(-2.0, 8.0))
	var extra_pylon := Vector3(-side * rng.randf_range(9.0, 14.0), 0.0, rng.randf_range(-9.0, -4.0))
	var cols := [-11.0, 0.0, 11.0]
	for i in range(cols.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var t: float = cols[i]
		cols[i] = cols[j]
		cols[j] = t
	var hostages: Array[Vector3] = []
	var hz := [rng.randf_range(-18.0, -9.0), rng.randf_range(-18.0, -9.0), rng.randf_range(-18.0, -9.0)]
	var hx := [rng.randf_range(-3.5, 3.5), rng.randf_range(-3.5, 3.5), rng.randf_range(-3.5, 3.5)]
	if ptype == "rescue":
		for i in 3:
			hostages.append(Vector3(float(cols[i]) + float(hx[i]), 0.0, float(hz[i])))
	if sec_types.has("rescue"):
		hostages.append(cage)
	var pylons: Array[Vector3] = []
	var a0 := rng.randf_range(0.0, TAU)
	if ptype == "destroy_camp":
		for i in 3:
			var a := a0 + i * TAU / 3.0
			pylons.append(camp + Vector3(cos(a), 0.0, sin(a)) * 4.5)
	if sec_types.has("destroy_camp"):
		pylons.append(extra_pylon)
	var spawns: Array[Vector3] = []
	for i in 5:
		spawns.append(Vector3(-16.0 + i * 8.0 + rng.randf_range(-1.5, 1.5), 0.0, -19.5))
	for s2 in [-1.0, 1.0]:
		for _k in 2:
			spawns.append(Vector3(s2 * 19.5, 0.0, rng.randf_range(-13.0, -1.0)))
	var near_spawns: Array[Vector3] = []
	for d: Vector2 in [Vector2(-10.0, -5.0), Vector2(10.0, -5.0), Vector2(-6.0, -12.0), Vector2(6.0, -12.0)]:
		near_spawns.append(Vector3(clampf(player_spawn.x + d.x + rng.randf_range(-1.0, 1.0), -19.0, 19.0), 0.0,
			clampf(player_spawn.z + d.y, -19.0, 19.0)))
	var camp_posts: Array[Vector3] = []
	for i in 8:
		var a := rng.randf_range(0.0, TAU)
		camp_posts.append(camp + Vector3(cos(a), 0.0, sin(a)) * rng.randf_range(2.0, 6.5))
	# ที่กัน: หน้าผา 4 ด้าน
	var blockers: Array[Dictionary] = []
	var hx2 := HALF.x + WALL_T
	var wy := WALL_H * 0.5
	blockers.append({"kind": "box", "c": Vector3(0.0, wy, -HALF.y - WALL_T * 0.5), "h": Vector3(hx2, wy, WALL_T * 0.5), "tag": "cliff_n", "layer": "shell"})
	blockers.append({"kind": "box", "c": Vector3(0.0, wy, HALF.y + WALL_T * 0.5), "h": Vector3(hx2, wy, WALL_T * 0.5), "tag": "cliff_s", "layer": "shell"})
	blockers.append({"kind": "box", "c": Vector3(-HALF.x - WALL_T * 0.5, wy, 0.0), "h": Vector3(WALL_T * 0.5, wy, HALF.y + WALL_T), "tag": "cliff_w", "layer": "shell"})
	blockers.append({"kind": "box", "c": Vector3(HALF.x + WALL_T * 0.5, wy, 0.0), "h": Vector3(WALL_T * 0.5, wy, HALF.y + WALL_T), "tag": "cliff_e", "layer": "shell"})
	var fixed := blockers.size()
	if ptype == "defend":
		blockers.append({"kind": "cyl", "c": Vector2(base.x, base.z), "r": BASE_CORE_R, "y0": 0.0, "y1": 2.6, "tag": "base_core", "layer": "shell"})
	if ptype == "destroy_camp":
		# รั้วหลักรอบค่าย เว้นช่องทางเข้า 3 ช่อง (หลักที่ 0, 4, 8 ถอดออก)
		var ga := rng.randf_range(0.0, TAU)
		for i in STAKES:
			if i % 4 == 0:
				continue
			var a := ga + i * TAU / STAKES
			var p := Vector2(camp.x + cos(a) * CAMP_R, camp.z + sin(a) * CAMP_R)
			if absf(p.x) > HALF.x - 1.5 or absf(p.y) > HALF.y - 1.5:
				continue
			var near := false
			for q: Vector3 in spawns + near_spawns + hostages + pylons + [beacon, pickup]:
				if p.distance_to(Vector2(q.x, q.z)) < 3.2:
					near = true
			if near:
				continue
			blockers.append({"kind": "cyl", "c": p, "r": STAKE_R, "y0": 0.0, "y1": 2.6, "tag": "stake_%d" % i, "layer": "shell"})
	var keep := blockers.size()    # ที่กันก่อนหน้านี้ห้ามถอดตอนแก้ทางตัน
	# จุดที่ของบังต้องเว้น: [จุด, รัศมี]
	var avoid: Array = [[player_spawn, 4.5], [pickup, MissionTypes.PICKUP_R + 1.6], [beacon, MissionTypes.BEACON_R + 1.4]]
	if ptype == "defend":
		avoid.append([base, 5.5])
	if ptype == "destroy_camp":
		avoid.append([camp, CAMP_R - 1.0])
	for h in hostages:
		avoid.append([h, 3.0])
	for p in pylons:
		avoid.append([p, 2.6])
	for s3 in spawns:
		avoid.append([s3, 2.6])
	for s4 in near_spawns:
		avoid.append([s4, 1.8])
	var want := int(N_COVER[biome])
	var table: Array = BIOME_PIECES[biome]
	var wsum := 0
	for e: Array in table:
		wsum += int(e[1])
	var placed := 0
	var tries := 0
	while placed < want and tries < want * 10:
		tries += 1
		var pick := rng.randi_range(1, wsum)
		var kind := str(table[0][0])
		for e: Array in table:
			pick -= int(e[1])
			if pick <= 0:
				kind = str(e[0])
				break
		var pc: Array = PIECES[kind]
		var size := rng.randf_range(float(pc[1]), float(pc[2]))
		var height := rng.randf_range(float(pc[3]), float(pc[4]))
		var x := rng.randf_range(-HALF.x + 2.0, HALF.x - 2.0)
		var z := rng.randf_range(-HALF.y + 2.0, HALF.y - 2.0)
		var along_x := rng.randf() < 0.5
		var b := {}
		if str(pc[0]) == "box":
			var thick := 0.3 if kind.begins_with("wall") else size * 0.5
			var hl := size * 0.5
			var h3 := Vector3(hl if along_x else thick, height * 0.5, thick if along_x else hl)
			b = {"kind": "box", "c": Vector3(x, height * 0.5, z), "h": h3}
		else:
			b = {"kind": "cyl", "c": Vector2(x, z), "r": size, "y0": 0.0, "y1": height}
		b["tag"] = "%s_%d" % [kind, placed]
		b["layer"] = "shell" if height > TALL else "prop"
		var fr := footprint(b)
		var ok := fr.position.x > -HALF.x + 1.0 and fr.end.x < HALF.x - 1.0 and fr.position.y > -HALF.y + 1.0 \
			and fr.end.y < HALF.y - 1.0
		if ok:
			for av: Array in avoid:
				var ap: Vector3 = av[0]
				if _rect_dist(fr, Vector2(ap.x, ap.z)) < float(av[1]):
					ok = false
					break
		if ok:
			var grown := fr.grow(GAP)
			for k in range(fixed, blockers.size()):
				if grown.intersects(footprint(blockers[k])):
					ok = false
					break
		if not ok:
			continue
		blockers.append(b)
		placed += 1
	# ทางเดิน: ทุกจุดสำคัญต้องถึงได้ ไม่ถึงก็ถอดของบังที่ใกล้จุดนั้นสุด (ไม่ถอดหน้าผา ฐาน รั้ว)
	var targets: Array[Vector3] = [pickup, beacon]
	targets.append_array(hostages)
	targets.append_array(pylons)
	targets.append_array(spawns)
	targets.append_array(near_spawns)
	if ptype == "defend":
		targets.append(base + Vector3(0.0, 0.0, BASE_CORE_R + 1.4))
	if ptype == "destroy_camp":
		targets.append(camp)
		targets.append_array(camp_posts)
	for guard in 60:
		var g := grid(blockers)
		var seen := flood(g, player_spawn)
		var bad := Vector3.INF
		for t in targets:
			if not reached(g, seen, t):
				bad = t
				break
		if bad == Vector3.INF:
			break
		var best := -1
		var best_d := INF
		for k in range(keep, blockers.size()):
			var d := _rect_dist(footprint(blockers[k]), Vector2(bad.x, bad.z))
			if d < best_d:
				best_d = d
				best = k
		if best < 0:
			break
		blockers.remove_at(best)
	# จุดหลบของมือปืน: ด้านหลังของบังเตี้ย (ฝั่งเหนือ = ฝั่งศัตรู) ที่ยังอยู่ในพื้นที่
	var cover: Array[Vector3] = []
	for k in range(keep, blockers.size()):
		var b: Dictionary = blockers[k]
		if str(b["layer"]) != "prop":
			continue
		var fr := footprint(b)
		var p := Vector3(fr.get_center().x, 0.0, fr.position.y - 1.0)
		if p.z > -HALF.y + 1.5:
			cover.append(p)
	# ของตกแต่ง (ภาพล้วน ไม่มีตัวชน) สุ่มหลังที่กันเสมอ ที่กันจึงไม่ขึ้นกับจำนวนของตกแต่ง
	var decor: Array[Dictionary] = []
	for i in N_DECOR:
		var p := Vector3(rng.randf_range(-HALF.x + 0.6, HALF.x - 0.6), 0.0, rng.randf_range(-HALF.y + 0.6, HALF.y - 0.6))
		decor.append({"kind": i % 3, "pos": p, "s": rng.randf_range(0.5, 1.2), "yaw": rng.randf_range(0.0, TAU)})
	return {
		"half": HALF, "biome": biome, "type": ptype, "blockers": blockers, "player_spawn": player_spawn, "player_yaw": 0.0,
		"spawns": spawns, "near_spawns": near_spawns, "posts": {"camp": camp_posts, "cover": cover},
		"points": {"base": base, "pickup": pickup, "beacon": beacon, "camp": camp, "hostages": hostages, "pylons": pylons},
		"decor": decor,
	}


## รอยพื้น (x, z) ของที่กัน (ทรงกระบอก = กล่องล้อม)
static func footprint(b: Dictionary) -> Rect2:
	if str(b.get("kind", "")) == "box":
		var c: Vector3 = b["c"]
		var h: Vector3 = b["h"]
		return Rect2(c.x - h.x, c.z - h.z, h.x * 2.0, h.z * 2.0)
	var c2: Vector2 = b["c"]
	var r := float(b["r"])
	return Rect2(c2.x - r, c2.y - r, r * 2.0, r * 2.0)


## พื้นที่เดิน (ขอบในหน้าผา)
static func bounds() -> Rect2:
	return Rect2(-HALF, HALF * 2.0)


## ตารางช่องว่าง (ช่อง CELL ม.): ช่องที่จุดกลางห่างที่กันทุกชิ้นอย่างน้อย CLEAR และอยู่ในขอบ · วาดที่กันลงตาราง (เร็ว)
static func grid(blockers: Array) -> Dictionary:
	var cols := int(round(HALF.x * 2.0 / CELL))
	var rows := int(round(HALF.y * 2.0 / CELL))
	var free := PackedByteArray()
	free.resize(cols * rows)
	free.fill(1)
	for j in rows:
		for i in cols:
			var p := _centre(i, j)
			if p.x < -HALF.x + CLEAR or p.x > HALF.x - CLEAR or p.y < -HALF.y + CLEAR or p.y > HALF.y - CLEAR:
				free[j * cols + i] = 0
	for b in blockers:
		if str(b.get("kind", "")) == "box" and (b["c"] as Vector3).y - (b["h"] as Vector3).y >= ArenaPath.GROUND_Y:
			continue
		var fr := footprint(b).grow(CLEAR)
		var i0 := maxi(int(floor((fr.position.x + HALF.x) / CELL)), 0)
		var i1 := mini(int(ceil((fr.end.x + HALF.x) / CELL)), cols - 1)
		var j0 := maxi(int(floor((fr.position.y + HALF.y) / CELL)), 0)
		var j1 := mini(int(ceil((fr.end.y + HALF.y) / CELL)), rows - 1)
		for j in range(j0, j1 + 1):
			for i in range(i0, i1 + 1):
				if _blocks(b, _centre(i, j), CLEAR):
					free[j * cols + i] = 0
	return {"cols": cols, "rows": rows, "free": free}


## ช่องที่ถึงได้จากจุด p (เดิน 4 ทิศในช่องว่าง; เริ่มในช่องตันก็ใช้ช่องว่างที่ใกล้สุด)
static func flood(g: Dictionary, p: Vector3) -> PackedByteArray:
	var cols := int(g["cols"])
	var rows := int(g["rows"])
	var free: PackedByteArray = g["free"]
	var seen := PackedByteArray()
	seen.resize(cols * rows)
	var s := _nearest(g, cell_of(p))
	if s < 0:
		return seen
	var q := PackedInt32Array([s])
	seen[s] = 1
	var head := 0
	while head < q.size():
		var c := q[head]
		head += 1
		var ci := c % cols
		var cj := c / cols
		for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var ni := ci + d.x
			var nj := cj + d.y
			if ni < 0 or nj < 0 or ni >= cols or nj >= rows:
				continue
			var n := nj * cols + ni
			if free[n] == 1 and seen[n] == 0:
				seen[n] = 1
				q.append(n)
	return seen


## จุด p ถึงได้ไหม (ช่องของมัน หรือช่องว่างที่ใกล้สุดภายใน 1 ช่อง ถูกเดินถึง)
static func reached(g: Dictionary, seen: PackedByteArray, p: Vector3) -> bool:
	var cols := int(g["cols"])
	var rows := int(g["rows"])
	var c := cell_of(p)
	for dj in range(-1, 2):
		for di in range(-1, 2):
			var i := c.x + di
			var j := c.y + dj
			if i >= 0 and j >= 0 and i < cols and j < rows and seen[j * cols + i] == 1:
				return true
	return false


static func cell_of(p: Vector3) -> Vector2i:
	var cols := int(round(HALF.x * 2.0 / CELL))
	var rows := int(round(HALF.y * 2.0 / CELL))
	return Vector2i(clampi(int(floor((p.x + HALF.x) / CELL)), 0, cols - 1), clampi(int(floor((p.z + HALF.y) / CELL)), 0, rows - 1))


## จุด (x, z) รัศมี r ชนที่กันชิ้นไหนไหม (เทส: ไม่มีจุดสำคัญอยู่ในที่กัน)
static func inside_blocker(blockers: Array, p: Vector3, r: float) -> String:
	for b in blockers:
		if _blocks(b, Vector2(p.x, p.z), r):
			return str(b.get("tag", "?"))
	return ""


## ทุกจุดสำคัญของผังเป็นรายการเดียว [ชื่อ, จุด] (เทส)
static func key_points(l: Dictionary) -> Array:
	var out: Array = [["player_spawn", l["player_spawn"]]]
	var pts: Dictionary = l["points"]
	out.append(["pickup", pts["pickup"]])
	out.append(["beacon", pts["beacon"]])
	for i in (pts["hostages"] as Array).size():
		out.append(["hostage_%d" % i, pts["hostages"][i]])
	for i in (pts["pylons"] as Array).size():
		out.append(["pylon_%d" % i, pts["pylons"][i]])
	for i in (l["spawns"] as Array).size():
		out.append(["spawn_%d" % i, l["spawns"][i]])
	for i in (l["near_spawns"] as Array).size():
		out.append(["near_%d" % i, l["near_spawns"][i]])
	if str(l["type"]) == "destroy_camp":
		out.append(["camp", pts["camp"]])
		for i in (l["posts"]["camp"] as Array).size():
			out.append(["post_%d" % i, l["posts"]["camp"][i]])
	return out


# ---- ภายใน ----

static func _centre(i: int, j: int) -> Vector2:
	return Vector2(-HALF.x + (i + 0.5) * CELL, -HALF.y + (j + 0.5) * CELL)


static func _blocks(b: Dictionary, p: Vector2, r: float) -> bool:
	if str(b.get("kind", "")) == "box":
		var fr := footprint(b)
		var q := Vector2(clampf(p.x, fr.position.x, fr.end.x), clampf(p.y, fr.position.y, fr.end.y))
		return p.distance_squared_to(q) < r * r
	var c: Vector2 = b["c"]
	var rr := float(b["r"]) + r
	return p.distance_squared_to(c) < rr * rr


static func _rect_dist(r: Rect2, p: Vector2) -> float:
	var q := Vector2(clampf(p.x, r.position.x, r.end.x), clampf(p.y, r.position.y, r.end.y))
	return p.distance_to(q)


static func _nearest(g: Dictionary, c: Vector2i) -> int:
	var cols := int(g["cols"])
	var rows := int(g["rows"])
	var free: PackedByteArray = g["free"]
	for ring in range(0, 4):
		for dj in range(-ring, ring + 1):
			for di in range(-ring, ring + 1):
				var i := c.x + di
				var j := c.y + dj
				if i >= 0 and j >= 0 and i < cols and j < rows and free[j * cols + i] == 1:
					return j * cols + i
	return -1
