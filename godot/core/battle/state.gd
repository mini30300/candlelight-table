class_name BattleState
extends RefCounted
## สถานะทั้งหมดของการรบหนึ่งนัด (R1_PORT_SPEC §1, §5): ค่าตั้งโต๊ะ ที่นั่ง หมู่ โมเดล จุดยึด คิวรอทอย แต้ม บันทึก
## เก็บเป็นจำนวนเต็มล้วน ตำแหน่งเป็น MI (ตำแหน่งกติกา = gx/gz ของหน้าเก่า การเดินบนจอเป็นเรื่องของฝั่งภาพ)
## หมู่และโมเดลเรียงตามลำดับที่สร้าง (ลำดับนี้เป็นกติกา: ใครโดนก่อน ลำดับต่อสู้) ดัชนี id -> ตำแหน่ง ดูแลให้ตรงเสมอ
## แก้รายการหมู่/โมเดลผ่าน add_squad / add_unit / remove_unit / add_body / take_body เท่านั้น ดัชนีจึงไม่หลุด
## snapshot() เป็น Dictionary ที่มีแต่ int, String, Array, Dictionary (ไม่มีค่าจริง) และ digest() เทียบข้ามเครื่องได้
## เลข 64 บิต (แฮช สถานะสตรีมสุ่ม) เขียนเป็นฐานสิบหก เพราะ JSON อ่านเลขเกิน 2^53 ไม่ตรง

# ---------------------------------------------------------------- ค่าคงที่
const PH_CMD := 0
const PH_MOVE := 1
const PH_SHOOT := 2
const PH_CHARGE := 3
const PH_FIGHT := 4
## ชื่อเฟสบนสาย (ลำดับเดียวกับ data/phases.json)
const PHASES := ["cmd", "move", "shoot", "charge", "fight"]

const GOAL_OBJ := 0
const GOAL_KILL := 1
const GOALS := ["obj", "kill"]
const MAX_ROUND := 5
const KILL_ROUNDS := 30

## ยังไม่จบ / เสมอ (winner เป็นเลขทีมเมื่อมีผู้ชนะ)
const NO_WINNER := -2
const DRAW := -1

## วิธีโจมตี (how ของ act atk/shoot)
const HOW_SHOOT := 0
const HOW_FIGHT := 1
const HOW_OW := 2
const HOWS := ["shoot", "fight", "ow"]

## ชนิดของรายการรอทอย (PEND.kind)
const K_ATK := 0
const K_CHG := 1
const K_SHOCK := 2
const K_REZ := 3
const K_ADV := 4
const K_GREN := 5
const K_HEAL := 6
const KINDS := ["atk", "chg", "shock", "rez", "adv", "gren", "heal"]

## ขั้นของรายการรอทอย (PEND.stage)
const S_HIT := 0
const S_WOUND := 1
const S_SAVE := 2
const S_DONE := 3
const S_OW := 4
const S_OWATK := 5
const S_CHARGE := 6
const S_CHRR := 7
const S_MOVE := 8
const S_SHOCK := 9
const S_REZ := 10
const S_ADV := 11
const S_GREN := 12
const S_HEAL := 13
const STAGES := ["hit", "wound", "save", "done", "ow", "owatk", "charge", "chrr", "move", "shock", "rez", "adv", "gren", "heal"]

## บิตธงของหมู่ (snapshot/digest)
const F_MOVED := 1
const F_ADV := 2
const F_FELL := 4
const F_STILL := 8
const F_SHOT := 16
const F_CHARGED := 32
const F_FOUGHT := 64
const F_CH_DONE := 128
const F_SHAKEN := 256
const F_OW_USED := 512
const F_OPENED := 1024

## บิตธงของรายการรอทอย
const P_MELEE := 1
const P_OW := 2
const P_MK := 4
const P_TR := 8
const P_LH := 16
const P_DW := 32
const P_HEEL := 64
const P_RR := 128
const P_GTG := 256
const P_OK := 512
const P_WIND := 1024

## บรรทัดบันทึกที่เก็บไว้ (ของเก่าทิ้ง)
const LOG_CAP := 200
## ค่าเฝ้าระยะที่ไกลกว่าโต๊ะใด ๆ (MI^2)
const FAR2 := 1152921504606846976


# ---------------------------------------------------------------- ชนิดข้อมูล
## ที่นั่งหนึ่งที่ (G.players[i]): id = ตำแหน่งใน seats เสมอ
class Seat extends RefCounted:
	var id: int = 0
	var pid: String = ""
	var team: int = 0
	## ชื่อบนจอ (ไม่ใช่กติกา ไม่เข้า digest)
	var nm: String = ""
	var bot: bool = false
	var ai: bool = false
	## จำนวนหมู่ต่อชนิดตามลำดับ TYPES
	var list: PackedInt32Array = PackedInt32Array()
	var fac: String = "mod"
	## สกินที่เลือก {คีย์หน่วย: เลขสกิน} (ภาพเท่านั้น)
	var skin: Dictionary = {}
	var has_dep: bool = false
	var dep_x: int = 0
	var dep_z: int = 0
	var done: bool = false
	var cp: int = 0


## โมเดลหนึ่งตัว (units[i]): ตำแหน่ง x/z คือตำแหน่งกติกา (MI)
class Unit extends RefCounted:
	var id: String = ""
	var sq: String = ""
	## ตำแหน่งหมู่ใน squads
	var sqi: int = -1
	## คีย์ชนิด (u.t ของหน้าเก่า) และตำแหน่งใน TYPES
	var t: String = ""
	var ti: int = -1
	var side: int = 0
	var pl: int = 0
	var hp: int = 0
	var x: int = 0
	var z: int = 0
	## ร่างที่รอลม (windWait): อยู่ใน bodies ไม่อยู่ใน units
	var wait: bool = false


## หมู่หนึ่งหมู่ (SQ[id]): ไม่ถูกลบแม้ตายหมด
class Squad extends RefCounted:
	var id: String = ""
	## ตำแหน่งใน squads (= ลำดับ SQ_ORDER)
	var idx: int = -1
	var k: String = ""
	var ti: int = -1
	var side: int = 0
	var pl: int = 0
	var n0: int = 0
	## ชั้นโล่ที่เหลือ
	var vs: int = 0
	var moved: bool = false
	var adv: bool = false
	var fell: bool = false
	var still: bool = true
	var shot: bool = false
	var charged: bool = false
	var fought: bool = false
	var ch_done: bool = false
	var shaken: bool = false
	var ow_used: bool = false
	var opened: bool = false
	## เป้าที่บุกใส่ ("" = ไม่มี)
	var ch_tgt: String = ""
	var adv_r: int = 0
	## ถูกชี้เป้าเมื่อ mark_key() นี้ (-1 = ไม่เคย)
	var mk: int = -1
	var wind_n: int = 0
	## ทิศหันของหมู่ตามกติกา (ยาว 1000) แทน rot ที่เป็นภาพของหน้าเก่า
	var fx: int = 0
	var fz: int = 1000
	## โมเดลที่ยังอยู่ ตามลำดับใน units (คำนวณจาก units ไม่เข้า snapshot)
	var models: Array[Unit] = []

	## ล้างธงต้นเทิร์น (resetSq)
	func reset_turn() -> void:
		moved = false
		adv = false
		fell = false
		still = true
		shot = false
		charged = false
		ch_tgt = ""
		fought = false
		adv_r = 0
		ch_done = false

	func flags() -> int:
		var f := 0
		if moved: f |= F_MOVED
		if adv: f |= F_ADV
		if fell: f |= F_FELL
		if still: f |= F_STILL
		if shot: f |= F_SHOT
		if charged: f |= F_CHARGED
		if fought: f |= F_FOUGHT
		if ch_done: f |= F_CH_DONE
		if shaken: f |= F_SHAKEN
		if ow_used: f |= F_OW_USED
		if opened: f |= F_OPENED
		return f

	func set_flags(f: int) -> void:
		moved = (f & F_MOVED) != 0
		adv = (f & F_ADV) != 0
		fell = (f & F_FELL) != 0
		still = (f & F_STILL) != 0
		shot = (f & F_SHOT) != 0
		charged = (f & F_CHARGED) != 0
		fought = (f & F_FOUGHT) != 0
		ch_done = (f & F_CH_DONE) != 0
		shaken = (f & F_SHAKEN) != 0
		ow_used = (f & F_OW_USED) != 0
		opened = (f & F_OPENED) != 0


## จุดยึด (OBJ[i]): เจ้าของคิดใหม่ทุกครั้ง ไม่เก็บ
class Obj extends RefCounted:
	var n: int = 0
	var x: int = 0
	var z: int = 0


## รายการรอทอยหนึ่งรายการ (PEND[i]) ทุกชนิดใช้คลาสเดียว ช่องที่ไม่ใช้เป็นศูนย์
class Pend extends RefCounted:
	var kind: int = K_ATK
	var stage: int = S_HIT
	var u: String = ""
	var t: String = ""
	## ที่นั่งผู้โจมตีและผู้ป้องกัน (-1 = ไม่มี)
	var att: int = -1
	var def: int = -1
	var how: int = HOW_SHOOT
	var melee: bool = false
	var ow: bool = false
	var mk: bool = false
	var tr: bool = false
	var lh: bool = false
	var dw: bool = false
	var heel: bool = false
	var rr: bool = false
	var gtg: bool = false
	var ok: bool = false
	var wind: bool = false
	var shots: int = 0
	var need: int = 0
	var wneed: int = 0
	var sv: int = 7
	var dmg: int = 1
	var su: int = 0
	var hits: int = 0
	var lethal: int = 0
	var wounds: int = 0
	var mortal: int = 0
	var slay: int = 0
	var saved: int = 0
	## จำนวนลูกฟื้น (rez)
	var n: int = 0
	var hit_r: PackedInt32Array = PackedInt32Array()
	var wound_r: PackedInt32Array = PackedInt32Array()
	var save_r: PackedInt32Array = PackedInt32Array()
	var roll: PackedInt32Array = PackedInt32Array()

	func flags() -> int:
		var f := 0
		if melee: f |= P_MELEE
		if ow: f |= P_OW
		if mk: f |= P_MK
		if tr: f |= P_TR
		if lh: f |= P_LH
		if dw: f |= P_DW
		if heel: f |= P_HEEL
		if rr: f |= P_RR
		if gtg: f |= P_GTG
		if ok: f |= P_OK
		if wind: f |= P_WIND
		return f

	func set_flags(f: int) -> void:
		melee = (f & P_MELEE) != 0
		ow = (f & P_OW) != 0
		mk = (f & P_MK) != 0
		tr = (f & P_TR) != 0
		lh = (f & P_LH) != 0
		dw = (f & P_DW) != 0
		heel = (f & P_HEEL) != 0
		rr = (f & P_RR) != 0
		gtg = (f & P_GTG) != 0
		ok = (f & P_OK) != 0
		wind = (f & P_WIND) != 0


# ---------------------------------------------------------------- ค่าตั้งโต๊ะ (setup)
var seed: int = 1
var w: int = 48
var d: int = 34
var theme: String = "ruin"
var terrain: String = "hills"
var buildings: bool = true
## ความหนาแน่นสิ่งก่อสร้างเป็นส่วนร้อย (100 = x1)
var density_h: int = 100
var mode: String = "pvp"
var teams: int = 2
var per_team: int = 1
var budget: int = 500
var free_fire: bool = false
## วินาทีต่อเฟส (0 = ไม่จับเวลา)
var clock: int = 0
var goal: int = GOAL_OBJ
var rounds: int = 5

# ---------------------------------------------------------------- สถานะการรบ
var on: bool = false
var over: bool = false
var round_no: int = 1
var turn: int = 0
var phase: int = PH_CMD
var winner: int = NO_WINNER
## รอผลทดสอบขวัญ/ซ่อมก่อนจบเฟสคำสั่ง
var cmd_wait: bool = false
## แต้มชัยต่อทีม
var vp: PackedInt64Array = PackedInt64Array()
## กลยุทธ์ที่ใช้แล้ว: คีย์ stratKey -> true (ดูอย่างเดียว ไม่วนลูป)
var used: Dictionary = {}
## ลำดับต่อสู้ (id หมู่) และ fights_null = ยังไม่ได้จัด (G.fights === null)
var fights: PackedStringArray = PackedStringArray()
var fights_null: bool = false
var fight_at: int = 0

var seats: Array[Seat] = []
var squads: Array[Squad] = []
var units: Array[Unit] = []
## ร่างที่รอลม ตามลำดับที่ล้ม
var bodies: Array[Unit] = []
var objs: Array[Obj] = []
var pend: Array[Pend] = []
## สิ่งกีดขวางพร้อมใช้ (BtBlocking.prep): Dictionary ที่มีแต่ int กับ String
var props: Array[Dictionary] = []
## แฮชของ props (คิดตอน set_props) และ props มาจากภายนอก (oracle) ไม่ใช่จาก setup
var props_hash: int = 0
var props_injected: bool = false
## บันทึก {key, args}
var log_lines: Array[Dictionary] = []
## สตรีมสุ่มของเครื่องนี้ (bot:<seat>, dice:<seat>) ไม่เข้า digest เพราะทอยแค่เครื่องเดียว
var rngs: Dictionary = {}
## seq ของ act ที่กำลังใช้ (ชื่อสตรีม fallback:<seq>:<stage>)
var act_seq: int = 0

var _sq_index: Dictionary = {}
var _unit_index: Dictionary = {}
var _bad := false


# ---------------------------------------------------------------- สร้าง
## สร้างจาก setup แบบห้อง (คีย์ของ curSetup: theme, seed, w, d, terrain, buildings, density_h, mode, teams,
## perTeam, budget, freeFire, clock, goal, rounds) ค่าที่ไม่มีใช้ค่าตั้งต้น; bool รับทั้ง bool และ 0/1
static func make(setup: Dictionary) -> BattleState:
	var st := BattleState.new()
	st._apply_setup(setup)
	return st


func _apply_setup(s: Dictionary) -> void:
	seed = _opt_int(s, "seed", 1)
	w = _opt_int(s, "w", 48)
	d = _opt_int(s, "d", FieldTerrain.depth_for(w))
	theme = str(s.get("theme", "ruin"))
	terrain = str(s.get("terrain", "hills"))
	buildings = _opt_bool(s, "buildings", true)
	density_h = _opt_int(s, "density_h", 100)
	mode = str(s.get("mode", "pvp"))
	teams = maxi(1, _opt_int(s, "teams", 2))
	per_team = maxi(1, _opt_int(s, "perTeam", 1))
	budget = _opt_int(s, "budget", 500)
	free_fire = _opt_bool(s, "freeFire", false)
	clock = _opt_int(s, "clock", 0)
	goal = GOAL_KILL if str(s.get("goal", "obj")) == "kill" else GOAL_OBJ
	# หน้าเก่า: clamp(rounds || 5, 3, 10) — ศูนย์คือค่าตั้งต้น 5 ไม่ใช่ 3
	var rd := _opt_int(s, "rounds", MAX_ROUND)
	rounds = Fx.clampi(rd if rd != 0 else MAX_ROUND, 3, 10)
	vp = PackedInt64Array()
	vp.resize(teams)


static func _opt_int(s: Dictionary, k: String, dflt: int) -> int:
	return int(s[k]) if s.has(k) and typeof(s[k]) == TYPE_INT else dflt


static func _opt_bool(s: Dictionary, k: String, dflt: bool) -> bool:
	if not s.has(k):
		return dflt
	if typeof(s[k]) == TYPE_BOOL:
		return bool(s[k])
	if typeof(s[k]) == TYPE_INT:
		return int(s[k]) != 0
	return dflt


## setup เป็น Dictionary (int ล้วน ยกเว้นชื่อ)
func setup_dict() -> Dictionary:
	return {
		"theme": theme, "seed": seed, "w": w, "d": d, "terrain": terrain, "buildings": 1 if buildings else 0,
		"density_h": density_h, "mode": mode, "teams": teams, "perTeam": per_team, "budget": budget,
		"freeFire": 1 if free_fire else 0, "clock": clock, "goal": GOALS[goal], "rounds": rounds,
	}


# ---------------------------------------------------------------- ที่นั่ง
func add_seat(team_i: int, pid: String, bot: bool, ai: bool, nm: String) -> Seat:
	var p := Seat.new()
	p.id = seats.size()
	p.team = team_i
	p.pid = pid
	p.bot = bot
	p.ai = ai
	p.nm = nm
	p.list = PackedInt32Array()
	p.list.resize(GameData.count())
	seats.append(p)
	return p


func seat(i: int) -> Seat:
	return seats[i] if i >= 0 and i < seats.size() else null


## ที่นั่งแรกที่ pid ตรง (pidIndex) ไม่มีคืน -1
func pid_index(pid: String) -> int:
	for p: Seat in seats:
		if p.pid == pid:
			return p.id
	return -1


## ที่นั่งของทีม ตามลำดับที่นั่ง (teamPlayers)
func team_seats(team_i: int) -> Array[Seat]:
	var out: Array[Seat] = []
	for p: Seat in seats:
		if p.team == team_i:
			out.append(p)
	return out


# ---------------------------------------------------------------- หมู่และโมเดล
## เพิ่มหมู่ท้ายรายการ (ธงตั้งต้นแบบ resetSq); id ซ้ำคืน null
func add_squad(id: String, k: String, side: int, pl: int, n0: int, vs: int) -> Squad:
	if _sq_index.has(id):
		return null
	var s := Squad.new()
	s.id = id
	s.idx = squads.size()
	s.k = k
	s.ti = GameData.index_of(k)
	s.side = side
	s.pl = pl
	s.n0 = n0
	s.vs = vs
	s.reset_turn()
	squads.append(s)
	_sq_index[id] = s.idx
	return s


func squad(id: String) -> Squad:
	return squads[int(_sq_index[id])] if _sq_index.has(id) else null


func squad_index(id: String) -> int:
	return int(_sq_index.get(id, -1))


## เพิ่มโมเดลท้าย units (ชนิด ฝ่าย ที่นั่ง เอาจากหมู่); id ซ้ำหรือไม่มีหมู่คืน null
func add_unit(id: String, s: Squad, hp: int, x: int, z: int) -> Unit:
	if s == null or _unit_index.has(id):
		return null
	var u := Unit.new()
	u.id = id
	u.sq = s.id
	u.sqi = s.idx
	u.t = s.k
	u.ti = s.ti
	u.side = s.side
	u.pl = s.pl
	u.hp = hp
	u.x = x
	u.z = z
	_unit_index[id] = units.size()
	units.append(u)
	s.models.append(u)
	return u


## เอาโมเดลออกจาก units (ตาย) คืนตำแหน่งเดิม หรือ -1 ถ้าไม่อยู่
func remove_unit(u: Unit) -> int:
	if u == null or not _unit_index.has(u.id):
		return -1
	var i := int(_unit_index[u.id])
	units.remove_at(i)
	_unit_index.erase(u.id)
	for j: int in range(i, units.size()):
		_unit_index[units[j].id] = j
	var s := squads[u.sqi]
	s.models.erase(u)
	return i


func unit(id: String) -> Unit:
	return units[int(_unit_index[id])] if _unit_index.has(id) else null


func unit_index(id: String) -> int:
	return int(_unit_index.get(id, -1))


## โมเดลที่ยังอยู่ของหมู่ ตามลำดับใน units (sqModels)
func squad_models(id: String) -> Array[Unit]:
	var s := squad(id)
	if s != null:
		return s.models
	var none: Array[Unit] = []
	return none


func squad_alive(s: Squad) -> int:
	return s.models.size() if s != null else 0


## หมู่ที่ยังมีโมเดล ตามลำดับที่สร้าง (sqList)
func alive_squads() -> Array[Squad]:
	var out: Array[Squad] = []
	for s: Squad in squads:
		if not s.models.is_empty():
			out.append(s)
	return out


## เก็บร่างที่รอลม (โมเดลต้องถูก remove_unit แล้ว)
func add_body(u: Unit) -> void:
	u.wait = true
	bodies.append(u)


## ร่างแรกที่รอลมของหมู่ (windBody) ไม่มีคืน null
func body_of(sq_id: String) -> Unit:
	for b: Unit in bodies:
		if b.sq == sq_id and b.wait:
			return b
	return null


## เอาร่างออกจากรายการรอ (ลุกหรือหายไป)
func take_body(b: Unit) -> void:
	b.wait = false
	bodies.erase(b)


## จำนวนโมเดลที่ยังนับว่าอยู่ของทีม รวมร่างที่รอลม (liveOf)
func live_of(team_i: int) -> int:
	var n := 0
	for u: Unit in units:
		if u.side == team_i:
			n += 1
	for b: Unit in bodies:
		if b.side == team_i and b.wait:
			n += 1
	return n


# ---------------------------------------------------------------- อื่น ๆ
func add_obj(n: int, x: int, z: int) -> Obj:
	var o := Obj.new()
	o.n = n
	o.x = x
	o.z = z
	objs.append(o)
	return o


## ใส่สิ่งกีดขวาง (รูปของ BtBlocking.prep) แล้วคิดแฮชไว้ครั้งเดียว
func set_props(items: Array[Dictionary], injected: bool) -> void:
	props = []
	for o: Dictionary in items:
		props.append(o.duplicate(true))
	props_injected = injected
	props_hash = _props_hash(props)


## รอบสุดท้าย (maxRound)
func max_round() -> int:
	return KILL_ROUNDS if goal == GOAL_KILL else Fx.clampi(rounds, 3, 10)


func phase_name() -> String:
	return PHASES[phase] if phase >= 0 and phase < PHASES.size() else ""


## เลขของ (รอบ, เทิร์น) สำหรับการชี้เป้า (markKey)
func mark_key() -> int:
	return round_no * 16 + turn


## เพิ่มบรรทัดบันทึก (key แปลด้วย i18n ฝั่ง UI)
func say(key: String, args: Array) -> void:
	log_lines.append({"key": key, "args": args.duplicate(true)})
	if log_lines.size() > LOG_CAP:
		log_lines.remove_at(0)


## สตรีมสุ่มของเครื่องนี้ตามชื่อ (สร้างครั้งแรกจาก seed ของโต๊ะ)
func rng(name: String) -> Rng:
	if not rngs.has(name):
		rngs[name] = Rng.make(name, seed)
	return rngs[name]


## สตรีมเติมลูกเต๋าของ act นี้ (ใหม่ทุกครั้ง ทุกเครื่องได้ค่าเดียวกัน)
func fallback(stage: String) -> Rng:
	return Rng.make("fallback:%d:%s" % [act_seq, stage], seed)


# ---------------------------------------------------------------- snapshot / restore
## ภาพสถานะแบบมาตรฐาน: คีย์เรียงตายตัว ไม่มีค่าจริง; with_props = false ตัด props ออก (ส่งทางเน็ต)
func snapshot(with_props: bool = true) -> Dictionary:
	var ps: Array = []
	for p: Seat in seats:
		var lst: Array = []
		for i: int in p.list.size():
			if p.list[i] != 0:
				lst.append([i, p.list[i]])
		var sk := {}
		var keys: Array = p.skin.keys()
		keys.sort()
		for k: Variant in keys:
			sk[str(k)] = int(p.skin[k])
		ps.append({"pid": p.pid, "team": p.team, "nm": p.nm, "bot": 1 if p.bot else 0, "ai": 1 if p.ai else 0,
			"list": lst, "fac": p.fac, "skin": sk, "dep": [p.dep_x, p.dep_z] if p.has_dep else [],
			"done": 1 if p.done else 0, "cp": p.cp})
	var sqs: Array = []
	for s: Squad in squads:
		sqs.append([s.id, s.k, s.side, s.pl, s.n0, s.vs, s.flags(), s.ch_tgt, s.adv_r, s.mk, s.wind_n, s.fx, s.fz])
	var us: Array = []
	for u: Unit in units:
		us.append([u.id, u.sq, u.hp, u.x, u.z])
	var bs: Array = []
	for b: Unit in bodies:
		bs.append([b.id, b.sq, b.hp, b.x, b.z])
	var os: Array = []
	for o: Obj in objs:
		os.append([o.n, o.x, o.z])
	var pe: Array = []
	for q: Pend in pend:
		pe.append({"kind": q.kind, "stage": q.stage, "u": q.u, "t": q.t, "att": q.att, "def": q.def, "how": q.how,
			"f": q.flags(), "shots": q.shots, "need": q.need, "wneed": q.wneed, "sv": q.sv, "dmg": q.dmg, "su": q.su,
			"hits": q.hits, "lethal": q.lethal, "wounds": q.wounds, "mortal": q.mortal, "slay": q.slay,
			"saved": q.saved, "n": q.n, "hit_r": Array(q.hit_r), "wound_r": Array(q.wound_r),
			"save_r": Array(q.save_r), "roll": Array(q.roll)})
	var ukeys: Array = used.keys()
	ukeys.sort()
	var rs := {}
	var rnames: Array = rngs.keys()
	rnames.sort()
	for nm: Variant in rnames:
		var r: Rng = rngs[nm]
		var rst := r.state()
		rs[str(nm)] = [Hash.hex64(int(rst["s"])), Hash.hex64(int(rst["inc"])), int(rst["draws"])]
	var lg: Array = []
	for l: Dictionary in log_lines:
		lg.append({"key": l["key"], "args": (l["args"] as Array).duplicate(true)})
	var out := {
		"v": Version.RULES_V,
		"setup": setup_dict(),
		"match": {"on": 1 if on else 0, "over": 1 if over else 0, "round": round_no, "turn": turn, "phase": phase,
			"winner": winner, "cmd_wait": 1 if cmd_wait else 0, "vp": Array(vp), "used": ukeys,
			"fights": Array(fights), "fights_null": 1 if fights_null else 0, "fight_at": fight_at,
			"act_seq": act_seq},
		"seats": ps, "squads": sqs, "units": us, "bodies": bs, "objs": os, "pend": pe,
		"props_hash": Hash.hex64(props_hash), "props_injected": 1 if props_injected else 0,
		"rngs": rs, "log": lg,
	}
	if with_props:
		var pr: Array = []
		for o: Dictionary in props:
			pr.append(o.duplicate(true))
		out["props"] = pr
	return out


## คืนค่าจาก snapshot(): ตรวจครบก่อน ผิดรูปคืน false และไม่แก้ของเดิม
## ถ้าไม่มี props ใน snapshot ใช้ props ที่มีอยู่ แต่แฮชต้องตรง
func restore(snap: Dictionary) -> bool:
	var f := BattleState.new()
	if not f._load(snap, props):
		return false
	_take(f)
	return true


func _load(snap: Dictionary, keep_props: Array[Dictionary]) -> bool:
	_bad = false
	if _gi(snap, "v") != Version.RULES_V:
		return false
	var su := _gd(snap, "setup")
	var ma := _gd(snap, "match")
	if _bad:
		return false
	for k: String in ["seed", "w", "d", "density_h", "teams", "perTeam", "budget", "clock", "rounds", "buildings", "freeFire"]:
		_gi(su, k)
	for k: String in ["theme", "terrain", "mode", "goal"]:
		_gs(su, k)
	if _bad:
		return false
	_apply_setup(su)
	on = _gi(ma, "on") != 0
	over = _gi(ma, "over") != 0
	round_no = _gi(ma, "round")
	turn = _gi(ma, "turn")
	phase = _gi(ma, "phase")
	winner = _gi(ma, "winner")
	cmd_wait = _gi(ma, "cmd_wait") != 0
	vp = PackedInt64Array(_ints(_ga(ma, "vp")))
	used = {}
	for k: Variant in _ga(ma, "used"):
		if typeof(k) != TYPE_STRING:
			_bad = true
		else:
			used[k] = true
	fights = PackedStringArray()
	for k: Variant in _ga(ma, "fights"):
		if typeof(k) != TYPE_STRING:
			_bad = true
		else:
			fights.append(k)
	fights_null = _gi(ma, "fights_null") != 0
	fight_at = _gi(ma, "fight_at")
	act_seq = _gi(ma, "act_seq")
	if _bad:
		return false
	for pv: Variant in _ga(snap, "seats"):
		if not _load_seat(pv):
			return false
	for row: Variant in _ga(snap, "squads"):
		if not _load_squad(row):
			return false
	for row: Variant in _ga(snap, "units"):
		var r := _row(row, 5)
		if _bad:
			return false
		var s := squad(str(r[1]))
		if s == null or add_unit(str(r[0]), s, r[2], r[3], r[4]) == null:
			return false
	for row: Variant in _ga(snap, "bodies"):
		var r := _row(row, 5)
		if _bad:
			return false
		var s := squad(str(r[1]))
		if s == null:
			return false
		var b := Unit.new()
		b.id = r[0]
		b.sq = s.id
		b.sqi = s.idx
		b.t = s.k
		b.ti = s.ti
		b.side = s.side
		b.pl = s.pl
		b.hp = r[2]
		b.x = r[3]
		b.z = r[4]
		add_body(b)
	for row: Variant in _ga(snap, "objs"):
		var r := _row(row, 3)
		if _bad:
			return false
		add_obj(r[0], r[1], r[2])
	for pv: Variant in _ga(snap, "pend"):
		if not _load_pend(pv):
			return false
	var want_hash := _hex(_gs(snap, "props_hash"))
	var inj := _gi(snap, "props_injected") != 0
	if _bad:
		return false
	if snap.has("props"):
		var items: Array[Dictionary] = []
		for o: Variant in _ga(snap, "props"):
			if typeof(o) != TYPE_DICTIONARY or not _flat(o):
				return false
			items.append(o)
		set_props(items, inj)
	else:
		set_props(keep_props, inj)
	if props_hash != want_hash:
		return false
	var rs := _gd(snap, "rngs")
	if _bad:
		return false
	for nm: Variant in rs:
		var r: Variant = rs[nm]
		if typeof(r) != TYPE_ARRAY or (r as Array).size() != 3 or typeof(r[0]) != TYPE_STRING \
				or typeof(r[1]) != TYPE_STRING or typeof(r[2]) != TYPE_INT:
			return false
		var g := Rng.new()
		g.stream = str(nm)
		g.seed_value = seed
		if not g.restore({"s": _hex(r[0]), "inc": _hex(r[1]), "draws": r[2]}):
			return false
		rngs[str(nm)] = g
	for l: Variant in _ga(snap, "log"):
		if typeof(l) != TYPE_DICTIONARY or typeof(l.get("key")) != TYPE_STRING or typeof(l.get("args")) != TYPE_ARRAY \
				or not _clean(l["args"]):
			return false
		log_lines.append({"key": l["key"], "args": (l["args"] as Array).duplicate(true)})
	return not _bad


func _load_seat(pv: Variant) -> bool:
	if typeof(pv) != TYPE_DICTIONARY:
		return false
	var p: Dictionary = pv
	var s := add_seat(_gi(p, "team"), _gs(p, "pid"), _gi(p, "bot") != 0, _gi(p, "ai") != 0, _gs(p, "nm"))
	for pair: Variant in _ga(p, "list"):
		var r := _row(pair, 2)
		if _bad or r[0] < 0 or r[0] >= s.list.size():
			return false
		s.list[r[0]] = r[1]
	s.fac = _gs(p, "fac")
	var sk := _gd(p, "skin")
	for k: Variant in sk:
		if typeof(k) != TYPE_STRING or typeof(sk[k]) != TYPE_INT:
			return false
		s.skin[k] = int(sk[k])
	var dep := _ga(p, "dep")
	if dep.size() == 2:
		var r := _row(dep, 2)
		s.has_dep = true
		s.dep_x = r[0]
		s.dep_z = r[1]
	elif dep.size() != 0:
		return false
	s.done = _gi(p, "done") != 0
	s.cp = _gi(p, "cp")
	return not _bad


func _load_squad(row: Variant) -> bool:
	if typeof(row) != TYPE_ARRAY or (row as Array).size() != 13:
		return false
	var r: Array = row
	for i: int in 13:
		var want := TYPE_STRING if i == 0 or i == 1 or i == 7 else TYPE_INT
		if typeof(r[i]) != want:
			return false
	var s := add_squad(r[0], r[1], r[2], r[3], r[4], r[5])
	if s == null:
		return false
	s.set_flags(r[6])
	s.ch_tgt = r[7]
	s.adv_r = r[8]
	s.mk = r[9]
	s.wind_n = r[10]
	s.fx = r[11]
	s.fz = r[12]
	return true


func _load_pend(pv: Variant) -> bool:
	if typeof(pv) != TYPE_DICTIONARY:
		return false
	var p: Dictionary = pv
	var q := Pend.new()
	q.kind = _gi(p, "kind")
	q.stage = _gi(p, "stage")
	q.u = _gs(p, "u")
	q.t = _gs(p, "t")
	q.att = _gi(p, "att")
	q.def = _gi(p, "def")
	q.how = _gi(p, "how")
	q.set_flags(_gi(p, "f"))
	q.shots = _gi(p, "shots")
	q.need = _gi(p, "need")
	q.wneed = _gi(p, "wneed")
	q.sv = _gi(p, "sv")
	q.dmg = _gi(p, "dmg")
	q.su = _gi(p, "su")
	q.hits = _gi(p, "hits")
	q.lethal = _gi(p, "lethal")
	q.wounds = _gi(p, "wounds")
	q.mortal = _gi(p, "mortal")
	q.slay = _gi(p, "slay")
	q.saved = _gi(p, "saved")
	q.n = _gi(p, "n")
	q.hit_r = PackedInt32Array(_ints(_ga(p, "hit_r")))
	q.wound_r = PackedInt32Array(_ints(_ga(p, "wound_r")))
	q.save_r = PackedInt32Array(_ints(_ga(p, "save_r")))
	q.roll = PackedInt32Array(_ints(_ga(p, "roll")))
	if _bad or q.kind < 0 or q.kind >= KINDS.size() or q.stage < 0 or q.stage >= STAGES.size():
		return false
	pend.append(q)
	return true


## ย้ายทุกอย่างจากสถานะที่โหลดเสร็จแล้วมาไว้ที่ตัวนี้
func _take(f: BattleState) -> void:
	seed = f.seed
	w = f.w
	d = f.d
	theme = f.theme
	terrain = f.terrain
	buildings = f.buildings
	density_h = f.density_h
	mode = f.mode
	teams = f.teams
	per_team = f.per_team
	budget = f.budget
	free_fire = f.free_fire
	clock = f.clock
	goal = f.goal
	rounds = f.rounds
	on = f.on
	over = f.over
	round_no = f.round_no
	turn = f.turn
	phase = f.phase
	winner = f.winner
	cmd_wait = f.cmd_wait
	vp = f.vp
	used = f.used
	fights = f.fights
	fights_null = f.fights_null
	fight_at = f.fight_at
	seats = f.seats
	squads = f.squads
	units = f.units
	bodies = f.bodies
	objs = f.objs
	pend = f.pend
	props = f.props
	props_hash = f.props_hash
	props_injected = f.props_injected
	log_lines = f.log_lines
	rngs = f.rngs
	act_seq = f.act_seq
	_sq_index = f._sq_index
	_unit_index = f._unit_index


func _gi(m: Dictionary, k: String) -> int:
	if not m.has(k) or typeof(m[k]) != TYPE_INT:
		_bad = true
		return 0
	return int(m[k])


func _gs(m: Dictionary, k: String) -> String:
	if not m.has(k) or typeof(m[k]) != TYPE_STRING:
		_bad = true
		return ""
	return str(m[k])


func _ga(m: Dictionary, k: String) -> Array:
	if not m.has(k) or typeof(m[k]) != TYPE_ARRAY:
		_bad = true
		return []
	return m[k]


func _gd(m: Dictionary, k: String) -> Dictionary:
	if not m.has(k) or typeof(m[k]) != TYPE_DICTIONARY:
		_bad = true
		return {}
	return m[k]


## แถวของ int ยาว n (คอลัมน์ 0 และ 1 เป็น String ได้สำหรับ id); ผิดรูปตั้ง _bad
func _row(v: Variant, n: int) -> Array:
	if typeof(v) != TYPE_ARRAY or (v as Array).size() != n:
		_bad = true
		return []
	var r: Array = v
	for i: int in n:
		var t := typeof(r[i])
		if t != TYPE_INT and not (t == TYPE_STRING and i < 2 and n == 5):
			_bad = true
			return []
	return r


func _ints(a: Array) -> Array:
	for v: Variant in a:
		if typeof(v) != TYPE_INT:
			_bad = true
			return []
	return a


## ฐานสิบหก 16 ตัว (Hash.hex64) กลับเป็น int64; ผิดรูปตั้ง _bad
func _hex(h: String) -> int:
	if h.length() != 16:
		_bad = true
		return 0
	var v := 0
	for c: String in h:
		var k := Hash.HEX.find(c)
		if k < 0:
			_bad = true
			return 0
		v = (v << 4) | k
	return v


## props: ค่าเป็น int หรือ String เท่านั้น
static func _flat(o: Dictionary) -> bool:
	for k: Variant in o:
		if typeof(k) != TYPE_STRING or (typeof(o[k]) != TYPE_INT and typeof(o[k]) != TYPE_STRING):
			return false
	return true


static func _clean(v: Variant) -> bool:
	match typeof(v):
		TYPE_INT, TYPE_BOOL, TYPE_STRING:
			return true
		TYPE_ARRAY:
			for x: Variant in v:
				if not _clean(x):
					return false
			return true
		TYPE_DICTIONARY:
			for k: Variant in v:
				if typeof(k) != TYPE_STRING or not _clean(v[k]):
					return false
			return true
	return false


static func _props_hash(items: Array[Dictionary]) -> int:
	var v := PackedInt64Array([items.size()])
	for o: Dictionary in items:
		var keys: Array = o.keys()
		keys.sort()
		for k: Variant in keys:
			v.append(Hash.fnv1a64_str(str(k)))
			var x: Variant = o[k]
			v.append(Hash.fnv1a64_str(x) if typeof(x) == TYPE_STRING else int(x))
	return Hash.fnv1a64(v)


# ---------------------------------------------------------------- digest
## สถานะกติกาเป็นอาร์เรย์ int ลำดับตายตัว (ไม่รวมชื่อบนจอ บันทึก สตรีมสุ่มของเครื่อง; รวม pid ของที่นั่ง)
## หมู่และโมเดลเรียงตามลำดับในรายการ (ลำดับเป็นกติกา) ไม่ได้เรียงตาม id
func state_ints() -> PackedInt64Array:
	var v := PackedInt64Array([Version.RULES_V, seed, w, d, teams, per_team, goal, rounds, 1 if free_fire else 0,
		1 if on else 0, 1 if over else 0, round_no, turn, phase, winner, 1 if cmd_wait else 0,
		1 if fights_null else 0, fight_at, props_hash])
	v.append(vp.size())
	v.append_array(vp)
	v.append(fights.size())
	for id: String in fights:
		v.append(Hash.fnv1a64_str(id))
	var ukeys: Array = used.keys()
	ukeys.sort()
	v.append(ukeys.size())
	for k: Variant in ukeys:
		v.append(Hash.fnv1a64_str(str(k)))
	v.append(seats.size())
	for p: Seat in seats:
		# pid เป็นกติกา: act done หาที่นั่งจาก pid
		v.append_array(PackedInt64Array([Hash.fnv1a64_str(p.pid), p.team, 1 if p.bot else 0, 1 if p.ai else 0,
			1 if p.done else 0, p.cp, 1 if p.has_dep else 0, p.dep_x, p.dep_z]))
	v.append(squads.size())
	for s: Squad in squads:
		v.append_array(PackedInt64Array([Hash.fnv1a64_str(s.id), s.ti, s.side, s.pl, s.n0, s.vs, s.flags(),
			Hash.fnv1a64_str(s.ch_tgt), s.adv_r, s.mk, s.wind_n, s.fx, s.fz]))
	v.append(units.size())
	for u: Unit in units:
		v.append_array(PackedInt64Array([Hash.fnv1a64_str(u.id), u.sqi, u.hp, u.x, u.z]))
	v.append(bodies.size())
	for b: Unit in bodies:
		v.append_array(PackedInt64Array([Hash.fnv1a64_str(b.id), b.sqi, b.hp, b.x, b.z]))
	v.append(objs.size())
	for o: Obj in objs:
		v.append_array(PackedInt64Array([o.n, o.x, o.z]))
	v.append(pend.size())
	for q: Pend in pend:
		v.append_array(PackedInt64Array([q.kind, q.stage, Hash.fnv1a64_str(q.u), Hash.fnv1a64_str(q.t), q.att,
			q.def, q.how, q.flags(), q.shots, q.need, q.wneed, q.sv, q.dmg, q.su, q.hits, q.lethal, q.wounds,
			q.mortal, q.slay, q.saved, q.n]))
		for arr: PackedInt32Array in [q.hit_r, q.wound_r, q.save_r, q.roll]:
			v.append(arr.size())
			for x: int in arr:
				v.append(x)
	return v


## FNV-1a 64 ของ state_ints() เป็นฐานสิบหก 16 ตัว
func digest() -> String:
	return Hash.digest_hex(state_ints())
