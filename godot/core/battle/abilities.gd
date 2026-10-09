class_name BtAbilities
extends RefCounted
## ทะเบียนความสามารถ (R1_PORT_SPEC §1 abilities): ธงของหน่วย คำของอาวุธ ชนิดออร่า และกฎทั้งกองทัพ
## แต่ละชื่อชี้ไปยังฟังก์ชันกติกาที่ใช้มัน ("Class.func" คั่นด้วย ", " เมื่อมีหลายที่) หรือ "none" = ไม่มีผลต่อกติกา
## ตัวอ่าน (ty, flag, num, text, gun, mel, wnum, wflag) อ่าน GameData อย่างเดียว ไม่แก้อะไร ความจริงเท็จแบบหน้าเก่า
## test_abilities.gd ตรวจว่าทุกช่องใน types.json อยู่ในทะเบียน และตัวจัดการที่มีแล้วทุกตัวมีการทดสอบพฤติกรรม

## ช่องค่าพื้นฐานของหน่วย (ไม่ใช่ธง)
const STATS := ["k", "fac", "nm", "d", "n", "pts", "mv", "T", "sv", "w", "ld", "oc", "gun", "mel"]
## ช่องค่าพื้นฐานของอาวุธ
const WEAPON_STATS := ["nm", "a", "s", "ap", "d", "rng", "bs", "ws"]

## ธงของหน่วย -> ตัวจัดการ
const FLAGS := {
	"ac": "BtCombat.charge_why_not",
	"aoc": "BtCombat.atk_math",
	"aura": "BtCombat.in_aura",
	"brave": "BtTurn.start_turn",
	"ca": "BtCombat.atk_math",
	"ch": "none",
	"fly": "BtCombat.shot_why_not, BtCombat.charge_why_not",
	"gk": "BtPend.finish_atk, BtAbilities.glory_heal",
	"hd": "BtPend.deal_damage",
	"heal": "BtCombat.can_heal, BtCombat.heal_why_not",
	"heel": "BtCombat.atk_math, BtPend.apply_wnd",
	"hero": "none",
	"inf": "BtCombat.inf",
	"inv": "BtCombat.atk_math",
	"lk": "BtArmy.fit_list, BtArmy.pts_of, BtArmy.slot_max",
	"r": "BtSquads.radius_of",
	"rez": "BtTurn.start_turn, BtPend.apply_rez",
	"sec": "BtArmy.fit_list, BtArmy.fac_of, BtArmy.pts_of, BtArmy.slot_max",
	"spawn": "BtTurn.start_turn, BtAbilities.after_kills, BtAbilities.spawn_from",
	"st": "BtCombat.atk_math",
	"ttn": "BtCombat.shot_why_not, BtCombat.charge_why_not",
	"veh": "none",
	"vsh": "BtArmy.deploy, BtAbilities.refill_shields",
	"wind": "BtPend.deal_damage, BtAbilities.wind_turn",
}
# ac บุกได้แม้วิ่งมา · aoc ค่าเจาะที่โดนลดหนึ่ง · brave ผ่านทดสอบขวัญเสมอ · ca บุกเข้ามาตีเพิ่มตัวละหนึ่ง
# ch หัวข้อภาคี (จอ) · fly/ttn ถอยแล้วยังยิงและบุกได้ ttn ติดประชิดก็ยิงได้ · gk ฆ่าแล้วฟื้นแผล · hd ดาเมจที่โดนลดครึ่ง
# heal ระยะรักษา · heel เจาะได้หกตายทันที · hero ตัวเอก (จอ) · inf ทหารเดินเท้า (ช่องที่ส่งออกมา) · inv เซฟพิเศษ
# lk/sec หน่วยลับ · r รัศมีฐาน (GameData เก็บเป็น r_mi) · rez ซ่อมตัวเอง · spawn หน่วยที่ซ่อนอยู่ข้างใน
# st พรางตัว โดนยิงเข้ายากขึ้นหนึ่ง · veh ผลมีแค่ผ่าน inf · vsh ชั้นโล่ · wind ลมพัดมาชุบชีวิต

## คำของอาวุธ -> ตัวจัดการ
const WEAPON_KEYS := {
	"rf": "BtCombat.atk_math",
	"as": "BtCombat.shot_why_not",
	"pi": "BtCombat.shot_why_not",
	"hv": "BtCombat.atk_math",
	"su": "BtCombat.atk_math, BtPend.count_hits",
	"tr": "BtCombat.atk_math, BtPend.count_hits, BtPend.apply_hit, BtPend.apply_reroll",
	"lh": "BtCombat.atk_math, BtPend.count_hits",
	"dw": "BtCombat.atk_math, BtPend.apply_wnd",
	"bl": "BtCombat.atk_math",
	"po": "BtCombat.atk_math",
	"mk": "BtCombat.atk_math, BtPend.mark_hit",
	"la": "BtCombat.atk_math",
	"fx": "none",
	"trail": "none",
}
# rf ครึ่งระยะยิงเพิ่ม rf นัด · as วิ่งแล้วยิงได้ · pi ปืนพก ยิงหน่วยที่ประชิดได้ · hv ยืนนิ่งเข้าเป้าง่ายขึ้นหนึ่ง
# su ได้หกนับเข้าเพิ่ม · tr พ่น โดนอัตโนมัติ ทอยใหม่ไม่ได้ · lh เข้าได้หกเจาะเลย · dw เจาะได้หกเป็นแผลตรง
# bl เป้าทุกห้าตัวยิงเพิ่มหนึ่ง · po พิษ ทหารเดินเท้าเจาะได้ตั้งแต่ po · mk ชี้เป้า · la บุกเข้ามาเจาะง่ายขึ้นหนึ่ง
# fx/trail เอฟเฟกต์ (จอ)

## ชนิดออร่า (ค่าของธง aura) -> ตัวจัดการ: พวกเดียวกันในระยะ AURA_R
const AURAS := {
	"hit": "BtCombat.atk_math",
	"veil": "BtCombat.atk_math",
	"bless": "BtCombat.atk_math",
	"ld": "BtTurn.start_turn",
	"rez": "BtTurn.start_turn",
}
# hit เข้าเป้าง่ายขึ้นหนึ่ง · veil โดนยิงเข้ายากขึ้นหนึ่ง · bless เซฟพิเศษ BLESS_INV · ld ไม่ต้องทดสอบขวัญ
# rez ซ่อมตัวเองได้ที่ REZ_AURA

## กฎทั้งกองทัพ (โค้ด ไม่ใช่ข้อมูล) -> ตัวจัดการ ตามรหัสกองทัพใน facs.json
const ARMIES := {
	"gr": "none",
	"mod": "none",
	"kn": "none",
	"sw": "none",
	"rb": "none",
	"or": "none",
	"th": "none",
	"jp": "none",
	"nr": "none",
	"eg": "none",
	"md": "none",
	"el": "BtCombat.shot_why_not",
	"de": "BtCombat.pain_on, BtCombat.atk_math, BtCombat.charge_why_not",
	"ta": "none",
	"cx": "BtCombat.pact_on, BtCombat.atk_math",
}
# el ยิงได้แม้วิ่งมา · de ตั้งแต่รอบ PAIN_ROUND ตีประชิดเข้าเป้าง่ายขึ้นหนึ่งและวิ่งแล้วบุกได้
# cx ตีประชิดได้หกนับเข้าเพิ่มหนึ่ง · ta ตัวชี้เป้าเป็นคำ mk ของอาวุธ · kn ภาคีเป็นธง ch (จอ)


## รายชื่อตัวจัดการของรายการหนึ่งในทะเบียน ("none" หรือว่าง = ไม่มี)
static func handlers(entry: String) -> PackedStringArray:
	var out := PackedStringArray()
	if entry == "" or entry == "none":
		return out
	for h: String in entry.split(", "):
		out.append(h)
	return out


# ---------------------------------------------------------------- ตัวอ่านข้อมูล
## ข้อมูลหน่วยตามตำแหน่งใน TYPES (TY); นอกตาราง = {} (หน้าเก่าไม่มีคีย์แปลก: ตัดตั้งแต่จัดทัพ)
static func ty(ti: int) -> Dictionary:
	if ti < 0 or ti >= GameData.count():
		return {}
	return GameData.types()[ti]


## ธงจริงไหมแบบ JavaScript (ไม่มี/null/0/false/"" = เท็จ)
static func flag(ti: int, name: String) -> bool:
	return _truthy(ty(ti).get(name, null))


## ค่าจำนวนเต็มของช่อง (ไม่มีหรือไม่ใช่ตัวเลข = 0)
static func num(ti: int, name: String) -> int:
	return _int(ty(ti).get(name, null))


## ค่าข้อความของช่อง (aura, fac; ไม่มี = "")
static func text(ti: int, name: String) -> String:
	var v: Variant = ty(ti).get(name, null)
	return str(v) if typeof(v) == TYPE_STRING else ""


## อาวุธยิง (null ของหน้าเก่า = {}); ห้ามแก้ค่าที่ได้ เป็นของ GameData
static func gun(ti: int) -> Dictionary:
	var v: Variant = ty(ti).get("gun", null)
	return v if v is Dictionary else {}


## อาวุธประชิด ({} = ไม่มี); ห้ามแก้ค่าที่ได้
static func mel(ti: int) -> Dictionary:
	var v: Variant = ty(ti).get("mel", null)
	return v if v is Dictionary else {}


## ค่าจำนวนเต็มของช่องอาวุธ (ไม่มี = 0)
static func wnum(w: Dictionary, name: String) -> int:
	return _int(w.get(name, null))


## คำของอาวุธจริงไหม
static func wflag(w: Dictionary, name: String) -> bool:
	return _truthy(w.get(name, null))


static func _truthy(v: Variant) -> bool:
	match typeof(v):
		TYPE_NIL:
			return false
		TYPE_BOOL:
			return bool(v)
		TYPE_INT:
			return int(v) != 0
		TYPE_STRING:
			return str(v) != ""
	# ออบเจกต์และอาร์เรย์จริงเสมอเหมือน JavaScript
	return true


static func _int(v: Variant) -> int:
	if typeof(v) == TYPE_INT:
		return int(v)
	if typeof(v) == TYPE_BOOL:
		return 1 if bool(v) else 0
	return 0


# ---------------------------------------------------------------- ตัวจัดการ (ฟื้น ลม ม้าไม้ โล่)
## ระยะที่ตัวชุบลงข้างตัวแรกที่ยังอยู่ (1800 MI)
const REVIVE_DX := 1800
## ระยะจากม้าไม้ถึงจุดกลางของหน่วยที่ออกมา (2600 MI)
const SPAWN_OUT := 2600


static func _say(st: BattleState, out: Array[Dictionary], key: String, args: Array) -> void:
	st.say(key, args)
	out.append(Events.make(Events.Id.LOG_LINE, {"key": key, "args": args.duplicate()}))


## gloryHeal: ฆ่าได้ n ตัว ฟื้นแผลทีละหนึ่ง ให้ตัวที่แผลเหลือน้อยสุดก่อน (ตัวแรกเมื่อเท่ากัน) ไม่เกินแผลเต็ม คืนแผลที่ฟื้น
static func glory_heal(st: BattleState, s: BattleState.Squad, n: int, out: Array[Dictionary]) -> int:
	if s == null:
		return 0
	var w := num(s.ti, "w")
	var got := 0
	var left := n
	while left > 0:
		var m: BattleState.Unit = null
		for q: BattleState.Unit in s.models:
			if q.hp < w and (m == null or q.hp < m.hp):
				m = q
		if m == null:
			break
		m.hp += 1
		left -= 1
		got += 1
		out.append(Events.make(Events.Id.HEAL, {"uid": m.id, "hp": m.hp}))
	if got != 0:
		_say(st, out, "glory_heal", [s.id, got])
	return got


## reviveOne: ชุบตัวแรกที่หายไป (เลข i < n0 ที่ไม่มี <t>.<i> ยังอยู่) แผล 1 ต่อท้าย units ข้างตัวแรกที่ยังอยู่ (+1800 MI แกน x
## แล้ว free_spot) ไม่มีใครเหลือเลยคืน null; ร่างรอลมที่เลขเดียวกันหายไปด้วย (หน้าเก่าเอาออกจาก FALLEN)
static func revive_one(st: BattleState, t: BattleState.Squad, out: Array[Dictionary]) -> BattleState.Unit:
	if t == null or t.models.is_empty():
		return null
	var near: BattleState.Unit = t.models[0]
	for i: int in t.n0:
		var id := "%s.%d" % [t.id, i]
		if st.unit(id) != null:
			continue
		var sp := BtBlocking.free_spot(st, near.x + REVIVE_DX, near.z, null, PackedInt64Array(), 0, BtSquads.radius(t))
		var m := st.add_unit(id, t, 1, sp[0], sp[1])
		for b: BattleState.Unit in st.bodies:
			if b.id == id:
				st.take_body(b)
				break
		out.append(Events.make(Events.Id.REZ, {"uid": id}))
		return m
	return null


## windFall: ลูกพระพายล้ม นับครั้งที่ล้มแล้วนอนรอลม (ต้อง remove_unit แล้ว)
static func wind_fall(st: BattleState, m: BattleState.Unit) -> void:
	var s := st.squad(m.sq)
	if s == null:
		return
	s.wind_n += 1
	st.add_body(m)


## windUp: ร่างที่รอลมลุกขึ้นแผลเต็ม ที่ว่างใกล้ตำแหน่งกติกาตอนล้ม ต่อท้าย units; ไม่มีร่างคืน null
static func wind_up(st: BattleState, s: BattleState.Squad, out: Array[Dictionary]) -> BattleState.Unit:
	if s == null:
		return null
	var b := st.body_of(s.id)
	if b == null:
		return null
	st.take_body(b)
	var sp := BtBlocking.free_spot(st, b.x, b.z, null, PackedInt64Array(), 0, BtSquads.radius(s))
	var m := st.add_unit(b.id, s, num(s.ti, "w"), sp[0], sp[1])
	out.append(Events.make(Events.Id.REZ, {"uid": b.id}))
	return m


## windGone: ลมไม่มา ร่างหายไปจริง
static func wind_gone(st: BattleState, s: BattleState.Squad, out: Array[Dictionary]) -> void:
	if s == null:
		return
	var b := st.body_of(s.id)
	if b == null:
		return
	st.take_body(b)
	out.append(Events.make(Events.Id.DEATH, {"uid": b.id}))


## windTurn: ต้นเฟสคำสั่งของทีม ทุกหมู่ตามลำดับที่สร้าง (รวมหมู่ที่ตายหมด) ของทีมในตา ที่เป็นลูกพระพายและมีร่างรอ:
## ล้มครั้งแรกลุกเลย ครั้งต่อไปรอทอย rez ลูกเดียว ต้องได้ wind
static func wind_turn(st: BattleState, out: Array[Dictionary]) -> void:
	for s: BattleState.Squad in st.squads:
		if s.side != st.turn or not flag(s.ti, "wind") or st.body_of(s.id) == null:
			continue
		if s.wind_n <= 1:
			if wind_up(st, s, out) != null:
				_say(st, out, "wind_up", [s.id])
		else:
			var p := BattleState.Pend.new()
			p.kind = BattleState.K_REZ
			p.stage = BattleState.S_REZ
			p.u = s.id
			p.att = s.pl
			p.need = num(s.ti, "wind")
			p.n = 1
			p.wind = true
			# ต่อท้ายคิวตรง ๆ (mkPend): abilities อยู่ซ้ายของ pend จึงไม่เรียก BtPend
			st.pend.append(p)


## spawnFrom: เปิดท้องม้า (ครั้งเดียว) หมู่ใหม่ <s>x ชนิด spawn.k จำนวน spawn.n (ไม่มีใช้ n ของชนิด) ไม่มีโล่
## ม้ายังอยู่: ฐานคือตัวแรกที่ยังอยู่ หันตามทิศของหมู่ · ม้าพังแล้ว: ฐาน (x, z) ตำแหน่งกติกาที่ล้ม หัน (0, 1000)
## จุดกลาง = ฐาน + ทิศ x 2600 MI แล้ววางแถว formation + free_spot แผลเต็ม ต่อท้าย; ไม่มี spawn หรือเปิดแล้วคืน null
static func spawn_from(st: BattleState, s: BattleState.Squad, x: int, z: int, out: Array[Dictionary]) -> BattleState.Squad:
	if s == null or s.opened:
		return null
	var h: Variant = ty(s.ti).get("spawn", null)
	if not (h is Dictionary):
		return null
	var hd: Dictionary = h
	var k := str(hd.get("k", ""))
	var ti := GameData.index_of(k)
	if ti < 0:
		return null
	s.opened = true
	var n := _int(hd.get("n", null))
	if n == 0:
		n = num(ti, "n")
	var bx := x
	var bz := z
	var fx := 0
	var fz := 1000
	if not s.models.is_empty():
		bx = s.models[0].x
		bz = s.models[0].z
		fx = s.fx
		fz = s.fz
	var q := st.add_squad(s.id + "x", k, s.side, s.pl, n, 0)
	if q == null:
		return null
	q.fx = fx
	q.fz = fz
	var r := BtSquads.radius(q)
	var cx := bx + Fx.js_round(fx * SPAWN_OUT, 1000)
	var cz := bz + Fx.js_round(fz * SPAWN_OUT, 1000)
	var slots := BtSquads.formation(n, cx, cz, fx, fz, r)
	var w := num(ti, "w")
	for j: int in n:
		var sp := BtBlocking.free_spot(st, slots[j][0], slots[j][1], null, PackedInt64Array(), 0, r)
		st.add_unit("%s.%d" % [q.id, j], q, w, sp[0], sp[1])
	_say(st, out, "spawn_open", [s.id, q.id, n])
	return q


## afterKills: ม้าไม้ที่พังก่อนเปิด ทหารข้างในออกมาจากตำแหน่งกติกาของตัวที่ล้ม
static func after_kills(st: BattleState, killed: Array[BattleState.Unit], out: Array[Dictionary]) -> void:
	for m: BattleState.Unit in killed:
		var q := st.squad(m.sq)
		if q != null and flag(q.ti, "spawn") and not q.opened:
			spawn_from(st, q, m.x, m.z, out)


## โล่พลังงานกลับมาครบ vsh ชั้น ต้นเทิร์น: หมู่ที่ยังอยู่ของทีมในตาที่ชั้นเหลือน้อยกว่า vsh
static func refill_shields(st: BattleState, out: Array[Dictionary]) -> void:
	for s: BattleState.Squad in st.alive_squads():
		var v := num(s.ti, "vsh")
		if s.side != st.turn or v == 0 or s.vs >= v:
			continue
		s.vs = v
		_say(st, out, "shields_up", [s.id, v])

