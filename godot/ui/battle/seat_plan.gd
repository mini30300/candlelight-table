class_name SeatPlan
extends RefCounted
## ตัวเลือกบนหน้าตั้งเกม → setup และที่นั่งของ Battle.make ตรงตามแกน (LOBBY_SPEC §3.1) ไม่มี Node
## กองทัพทุกที่นั่ง (คนหรือบอท) จัดบนสถานะทดลองด้วย BtArmy.auto_list (เหมือน make_golden.seats_of) จึงส่งรายชื่อเสมอ
## (รายชื่อว่างทำให้ start_match สุ่มกองทัพเอง) · กองทัพ "สุ่ม" เลือกจากสตรีม lobby:fac:<ที่นั่ง> ของ seed เล่นซ้ำได้
## ไม่ส่ง "d" (Battle และ TableView ใช้ FieldTerrain.depth_for(w) ทั้งคู่)

## ขนาดโต๊ะ (นิ้ว)
const SIZES := {"s": 36, "m": 48, "l": 72}
const SIZE_ORDER: PackedStringArray = ["s", "m", "l"]
const SIZE_NAMES := {"s": "เล็ก 36 นิ้ว", "m": "กลาง 48 นิ้ว", "l": "ใหญ่ 72 นิ้ว"}
const THEMES: PackedStringArray = ["ruin", "forest", "desert", "ice"]
const TERRAINS: PackedStringArray = ["flat", "hills", "mountain", "forest"]
const GOALS: PackedStringArray = ["obj", "kill"]
const BUDGETS: PackedInt32Array = [300, 500, 1000, 1500]
const MAX_SEATS := 6
const MIN_TEAMS := 2
const MAX_TEAMS := 4
const MAX_PER_TEAM := 2
## ความกว้างโต๊ะอย่างน้อย 24 + 6 ต่อที่นั่ง (นิ้ว)
const MIN_W := 24
const W_PER_SEAT := 6
const DEFAULT_ROUNDS := 5

## ข้อผิดพลาด (รหัส → ข้อความไทย คีย์ของ I18n)
const ERROR_TEXT := {
	"humans": "เป็นคุณได้ที่นั่งเดียว",
	"seats": "ที่นั่งรวมไม่เกิน 6 ที่",
	"teams": "จำนวนทีมต้องเป็น 2 ถึง 4",
	"per_team": "ทีมละ 1 หรือ 2 ที่นั่ง",
	"small": "โต๊ะเล็กไปสำหรับ {n} ที่นั่ง เลือกขนาด {size} ขึ้นไป",
	"army": "ไม่รู้จักกองทัพที่เลือก",
	"theme": "ไม่รู้จักฉากที่เลือก",
	"terrain": "ไม่รู้จักภูมิประเทศที่เลือก",
	"goal": "ไม่รู้จักเป้าหมายที่เลือก",
	"budget": "แต้มต่อทีมต้องมากกว่าศูนย์",
}


## ตัวเลือกเริ่มต้น: 2 ทีม × 1 ที่นั่ง 0 เป็นคุณกับกองทัพแรก ที่นั่ง 1 บอทกองทัพสุ่ม โต๊ะกลาง เมืองพัง เนิน ยึดจุด 5 รอบ 500 แต้ม
static func defaults(seed_v: int = 1) -> Dictionary:
	var facs := GameData.factions()
	return {
		"teams": 2, "per_team": 1,
		"seats": [{"fac": facs[0] if facs.size() > 0 else "", "human": true}, {"fac": "", "human": false}],
		"size": "m", "theme": "ruin", "terrain": "hills", "goal": "obj", "rounds": DEFAULT_ROUNDS, "budget": 500,
		"seed": clampi(seed_v, 1, 99999),
	}


## จำนวนที่นั่งของตัวเลือก
static func seat_count(choice: Dictionary) -> int:
	return int(choice.get("teams", 2)) * int(choice.get("per_team", 1))


## ทีมของที่นั่ง k (เรียงทีมก่อน: ที่นั่ง k อยู่ทีม k / ขนาดทีม)
static func team_of(choice: Dictionary, k: int) -> int:
	return k / maxi(1, int(choice.get("per_team", 1)))


## ปรับรายการที่นั่งให้ยาวเท่าจำนวนที่นั่ง (ที่นั่งใหม่เป็นบอทกองทัพสุ่ม) และคุณได้ไม่เกินหนึ่งที่
static func fit_seats(choice: Dictionary) -> void:
	var n := clampi(seat_count(choice), 0, MAX_TEAMS * MAX_PER_TEAM)
	var seats: Array = choice.get("seats", [])
	while seats.size() < n:
		seats.append({"fac": "", "human": false})
	if seats.size() > n:
		seats.resize(n)
	choice["seats"] = seats


## กองทัพของที่นั่ง k: ที่เลือก หรือสุ่มจากสตรีม lobby:fac:<k> ของ seed (ผลเดิมทุกครั้ง)
static func fac_of(choice: Dictionary, k: int) -> String:
	var seats: Array = choice.get("seats", [])
	var fac := str((seats[k] as Dictionary).get("fac", "")) if k < seats.size() else ""
	if fac != "":
		return fac
	return random_fac(k, int(choice.get("seed", 1)))


static func random_fac(k: int, seed_v: int) -> String:
	var facs := GameData.factions()
	if facs.is_empty():
		return "mod"
	return facs[Rng.make("lobby:fac:%d" % k, seed_v).bounded(facs.size())]


## ขนาดเล็กสุดที่พอสำหรับ n ที่นั่ง ("" = ไม่มีขนาดไหนพอ)
static func size_for(n: int) -> String:
	for sz in SIZE_ORDER:
		if int(SIZES[sz]) >= MIN_W + W_PER_SEAT * n:
			return sz
	return ""


## รหัสข้อผิดพลาดของตัวเลือก (ว่าง = เริ่มได้): humans seats teams per_team small army theme terrain goal budget
static func validate(choice: Dictionary) -> PackedStringArray:
	var out := PackedStringArray()
	var teams := int(choice.get("teams", 0))
	var per := int(choice.get("per_team", 0))
	if teams < MIN_TEAMS or teams > MAX_TEAMS:
		out.append("teams")
	if per < 1 or per > MAX_PER_TEAM:
		out.append("per_team")
	var n := teams * per
	if n > MAX_SEATS:
		out.append("seats")
	var humans := 0
	var facs := GameData.factions()
	var bad_army := false
	for sd: Variant in choice.get("seats", []):
		if not sd is Dictionary:
			bad_army = true
			continue
		if bool((sd as Dictionary).get("human", false)):
			humans += 1
		var f := str((sd as Dictionary).get("fac", ""))
		if f != "" and not facs.has(f):
			bad_army = true
	if humans > 1:
		out.append("humans")
	var w := int(SIZES.get(str(choice.get("size", "")), 0))
	if n <= MAX_SEATS and w < MIN_W + W_PER_SEAT * n:
		out.append("small")
	if bad_army:
		out.append("army")
	if not THEMES.has(str(choice.get("theme", ""))):
		out.append("theme")
	if not TERRAINS.has(str(choice.get("terrain", ""))):
		out.append("terrain")
	if not GOALS.has(str(choice.get("goal", ""))):
		out.append("goal")
	if int(choice.get("budget", 0)) <= 0:
		out.append("budget")
	return out


## ข้อความของรหัสข้อผิดพลาดตามภาษาที่เลือก (แปลผ่าน DatasheetText: สคริปต์ -s อ้างคลาสนี้ได้ก่อน autoload ลงทะเบียน)
static func error_text(code: String, choice: Dictionary) -> String:
	var th := str(ERROR_TEXT.get(code, ""))
	if th == "":
		return code
	var n := seat_count(choice)
	var sz := size_for(n)
	return DatasheetText.tf(th, {"n": n, "size": DatasheetText.tl(str(SIZE_NAMES.get(sz, SIZE_NAMES["l"])))})


## ตัวเลือก → {setup, seats (Array[Dictionary] แบบมีชนิด), human (ที่นั่งของคุณ, -1 = ดูบอทเล่น), errors, choice}
## มีข้อผิดพลาดก็ยังคืน setup/seats เท่าที่ทำได้ (ผู้เรียกไม่เริ่มเกม)
static func build(choice: Dictionary) -> Dictionary:
	var errors := validate(choice)
	var teams := clampi(int(choice.get("teams", 2)), 1, MAX_TEAMS)
	var per := clampi(int(choice.get("per_team", 1)), 1, MAX_PER_TEAM)
	var n := teams * per
	var seed_v := clampi(int(choice.get("seed", 1)), 1, 99999)
	var goal := str(choice.get("goal", "obj"))
	if not GOALS.has(goal):
		goal = "obj"
	var setup := {
		"seed": seed_v, "w": int(SIZES.get(str(choice.get("size", "m")), 48)), "teams": teams, "perTeam": per,
		"goal": goal, "budget": maxi(1, int(choice.get("budget", 500))),
		"theme": str(choice.get("theme", "ruin")), "terrain": str(choice.get("terrain", "hills")),
		"buildings": 1, "density_h": 100,
		"mode": "pvp" if teams == 2 and per == 1 else ("team" if per > 1 else "ffa"), "freeFire": 0,
	}
	if goal == "obj":
		setup["rounds"] = clampi(int(choice.get("rounds", DEFAULT_ROUNDS)), 3, 10)
	var picks: Array = choice.get("seats", [])
	var human := -1
	var facs := PackedStringArray()
	for k in n:
		var f := fac_of(choice, k)
		if not GameData.factions().has(f):
			f = random_fac(k, seed_v)
		facs.append(f)
		if k < picks.size() and picks[k] is Dictionary and bool((picks[k] as Dictionary).get("human", false)) and human < 0:
			human = k
	# กองทัพทุกที่นั่งบนสถานะทดลอง (ใส่ที่นั่งครบก่อน: เพดานตัวหมากขึ้นกับจำนวนที่นั่ง)
	var tmp := BattleState.make(setup)
	for k in n:
		tmp.add_seat(k / per, "", true, false, "")
	var seats: Array[Dictionary] = []
	for k in n:
		var own: Variant = (picks[k] as Dictionary).get("list") if k < picks.size() and picks[k] is Dictionary else null
		var list := PackedInt32Array()
		if own is PackedInt32Array and not (own as PackedInt32Array).is_empty():
			list = own   # กองที่จัดเองจากหน้าจัดกองทัพ
		else:
			tmp.seats[k].fac = facs[k]
			BtArmy.auto_list(tmp, k, Rng.make("lobby:%d" % k, tmp.seed))
			list = tmp.seats[k].list
		seats.append({"team": k / per, "bot": k != human, "pid": "", "fac": facs[k], "nm": "", "list": list})
	return {"setup": setup, "seats": seats, "human": human, "errors": errors, "choice": choice.duplicate(true)}


## แผนเดิมกับ seed ใหม่ (เล่นอีกครั้ง): ตัวเลือกเดิมทุกอย่าง กองทัพสุ่มสุ่มใหม่ตาม seed
static func with_seed(choice: Dictionary, seed_v: int) -> Dictionary:
	var c := choice.duplicate(true)
	c["seed"] = clampi(seed_v, 1, 99999)
	return c
