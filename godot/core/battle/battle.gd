class_name Battle
extends Table
## โต๊ะรบ (R1_PORT_SPEC หัวข้อ battle.gd): Table ที่ถือ BattleState ทุกการเปลี่ยนกติกา (แตะของเครื่องนี้ บอท ลูกเต๋า
## act จากห้อง) ผ่าน apply → _on_act (BtActs.apply) → advance เหมือนกันหมด (ARCHITECTURE §3)
## เริ่มนัดด้วย start() (ไม่บันทึก act) · ฟิกซ์เจอร์ของ oracle/เทสต์: props ที่ใส่เอง จุดยึด และตำแหน่งวางกองของหน้าเก่า

var st: BattleState


## สร้างโต๊ะจาก setup แบบห้อง ที่นั่งตามลำดับ mkPlayers และฟิกซ์เจอร์ (ไม่ได้ใส่ = {})
## seats[k] = {team, bot, ai, pid, nm, list (PackedInt32Array ตาม TYPES หรือ Array ที่ผ่าน fit_list), fac, skin,
## dep ([x, z] MI หรือว่าง), cp, done}
## fixture: props (Array ของชิ้นที่เตรียมแล้วจาก BtBlocking.prep_one; มีคีย์นี้ = ใส่เอง แม้ว่าง) ไม่มีก็สร้างจาก setup
## · objectives [{n, x, z}] (มี = ไม่วางจุดเอง) · units0 [{id, x, z, rot}] ตำแหน่งวางกองดิบของหน้าเก่า:
## วางกองที่นี่เลย (deploy ของ v10) แล้วทับตำแหน่งทุกตัวตาม id และหันหมู่ตาม rot ของโมเดลตัวแรกของหมู่
## (start_match เห็นกองที่วางแล้วจึงไม่วางซ้ำ) id ไม่ตรงกัน last_error = "bad_units0"
static func make(setup: Dictionary, seats: Array[Dictionary], fixture: Dictionary) -> Battle:
	var b := Battle.new()
	b.st = BattleState.make(setup)
	b.seed = b.st.seed
	for sd: Dictionary in seats:
		_add_seat(b.st, sd)
	if fixture.has("props") and typeof(fixture["props"]) == TYPE_ARRAY:
		var items: Array[Dictionary] = []
		for o: Variant in fixture["props"]:
			if typeof(o) == TYPE_DICTIONARY:
				items.append(o)
		b.st.set_props(items, true)
	else:
		var f := FieldTerrain.make(b.st.w, b.st.d, b.st.theme, b.st.terrain, b.st.seed)
		var fp := FieldProps.generate(f, b.st.buildings, b.st.density_h * 10)
		b.st.set_props(BtBlocking.prep_field(fp), false)
	if typeof(fixture.get("objectives")) == TYPE_ARRAY:
		for o: Variant in fixture["objectives"]:
			if typeof(o) == TYPE_DICTIONARY:
				var od: Dictionary = o
				b.st.add_obj(int(od.get("n", b.st.objs.size())), int(od.get("x", 0)), int(od.get("z", 0)))
	var u0: Array = fixture["units0"] if typeof(fixture.get("units0")) == TYPE_ARRAY else []
	if not u0.is_empty() and not _apply_units0(b.st, u0):
		b.last_error = "bad_units0"
	b._sync()
	return b


static func _add_seat(st0: BattleState, sd: Dictionary) -> void:
	var p := st0.add_seat(int(sd.get("team", 0)), str(sd.get("pid", "")), bool(sd.get("bot", false)),
		bool(sd.get("ai", false)), str(sd.get("nm", "")))
	var lv: Variant = sd.get("list")
	if typeof(lv) == TYPE_PACKED_INT32_ARRAY:
		var l: PackedInt32Array = lv
		for i: int in mini(l.size(), p.list.size()):
			p.list[i] = l[i]
	elif typeof(lv) == TYPE_ARRAY:
		p.list = BtArmy.fit_list(lv)
	p.fac = str(sd.get("fac", "mod"))
	if typeof(sd.get("skin")) == TYPE_DICTIONARY:
		p.skin = (sd["skin"] as Dictionary).duplicate(true)
	var dv: Variant = sd.get("dep")
	var tp := typeof(dv)
	if tp == TYPE_ARRAY or tp == TYPE_PACKED_INT64_ARRAY or tp == TYPE_PACKED_INT32_ARRAY:
		var dep := Array(dv)
		if dep.size() >= 2 and typeof(dep[0]) == TYPE_INT and typeof(dep[1]) == TYPE_INT:
			p.has_dep = true
			p.dep_x = int(dep[0])
			p.dep_z = int(dep[1])
	p.cp = int(sd.get("cp", 0)) if typeof(sd.get("cp")) == TYPE_INT else 0
	p.done = bool(sd.get("done", false))


## วางกองแบบ v10 (กองว่างได้กองผูก seed ก่อน เหมือน start_match) แล้วทับตำแหน่งด้วย units0 · คืน false ถ้า id ไม่ครบ/ไม่ตรง
static func _apply_units0(st0: BattleState, u0: Array) -> bool:
	for p: BattleState.Seat in st0.seats:
		if not BtArmy.has_units(st0, p.id):
			BtArmy.auto_list(st0, p.id, null)
	var none: Array[Dictionary] = []
	BtArmy.deploy(st0, none)
	var ok := u0.size() == st0.units.size()
	var faced := {}
	for i: int in u0.size():
		if typeof(u0[i]) != TYPE_DICTIONARY:
			ok = false
			continue
		var e: Dictionary = u0[i]
		var m := st0.unit(str(e.get("id", "")))
		if m == null:
			ok = false
			continue
		if i < st0.units.size() and st0.units[i] != m:
			ok = false
		m.x = int(e.get("x", m.x))
		m.z = int(e.get("z", m.z))
		var s := st0.squad(m.sq)
		if s != null and not faced.has(s.id) and typeof(e.get("rot")) == TYPE_INT:
			# มุมหันของหน้าเก่า face → (sin, cos) ยาว 1000
			faced[s.id] = true
			var rot: int = e["rot"]
			s.fx = Fx.js_round(FieldProps.sin_q(rot) * 1000, 65536)
			s.fz = Fx.js_round(FieldProps.cos_q(rot) * 1000, 65536)
	return ok


## เริ่มนัด: BtTurn.start_match แล้ว advance (ไม่บันทึก act)
func start() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	BtTurn.start_match(st, out)
	out.append_array(advance())
	return out


func codes() -> PackedStringArray:
	return PackedStringArray(BtActs.CODES)


## act ที่บันทึกแล้ว: seq ของมันเป็นชื่อสตรีม fallback · ผ่านตัวกรองแบบเซิร์ฟเวอร์อีกครั้ง (ไม่เปลี่ยน act ที่กรองแล้ว)
## act ของเครื่องนี้จึงได้ผลเดียวกับ act ที่ห้องส่งกลับมา
func _on_act(act: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	st.act_seq = int(act.get("seq", 0))
	var a := BtActs.sanitize(act)
	if not a.is_empty():
		BtActs.apply(st, a, out)
	_sync()
	return out


## advance ของหน้าเก่า: ทิ้งของค้างครั้งเดียว ตรวจจบ แล้ววน advance_step ไม่เกิน ADVANCE_GUARD
func advance() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	BtPend.prune(st, out)
	BtTurn.check_over(st, out)
	var guard := 0
	while guard < BtTurn.ADVANCE_GUARD and BtTurn.advance_step(st, out):
		guard += 1
	if guard >= BtTurn.ADVANCE_GUARD:
		out.append(Events.make(Events.Id.LOG_LINE, {"key": "advance_guard", "args": [guard]}))
	_sync()
	return out


## เลขสถานะ: ของ Table (turn/round/phase/over ตรงกับ st เสมอ) ต่อด้วยของ BattleState
func state_ints() -> PackedInt64Array:
	_sync()
	var v := super()
	v.append_array(st.state_ints())
	return v


func snapshot() -> Dictionary:
	_sync()
	var d := super()
	d["battle"] = st.snapshot(st.props_injected)
	return d


## คืนค่าทั้งสองชั้น: ตรวจ BattleState ในสำเนาก่อน (props ของเครื่องนี้ใช้ได้ถ้าแฮชตรง) แล้วจึงแตะของจริง
func restore(d: Dictionary) -> bool:
	if typeof(d.get("battle")) != TYPE_DICTIONARY:
		last_error = "bad_snapshot"
		return false
	var f := BattleState.new()
	f.set_props(st.props, st.props_injected)
	if not f.restore(d["battle"]):
		last_error = "bad_snapshot"
		return false
	# ชั้น Table กับ BattleState ต้องเล่าเรื่องเดียวกัน
	var want := [f.turn, f.round_no, f.phase, 1 if f.over else 0, f.seed]
	var got := [d.get("turn"), d.get("round"), d.get("phase"), d.get("over"), d.get("seed")]
	for i: int in want.size():
		if typeof(got[i]) != TYPE_INT or int(got[i]) != int(want[i]):
			last_error = "bad_snapshot"
			return false
	if not super(d):
		return false
	st = f
	_sync()
	return true


func board() -> Dictionary:
	return BtBoard.board(st, false)


## BT.botStep ของหน้าเก่า: บอทฝ่ายที่ถึงตาส่ง act (stay/skip ทีละอันแล้วถามต่อ) จนถึงการกระทำจริงหนึ่งอย่าง
## ลูกเต๋าจาก bot:<ที่นั่งของหมู่ที่ทำ> แล้วทอยของที่ค้างทั้งหมดบนเครื่องนี้ (ออฟไลน์ทอยให้ทุกคน)
## คืน "move" (เดิน) "shoot" (ยิง ตี รักษา ระเบิดมือ ประกาศบุก ตามหน้าเก่า) หรือ "" (บอทไม่มีอะไรทำในเฟสนี้)
## การจบเฟสของทีมบอท (BtBot.finished_act) เป็นงานของผู้เรียก เหมือนหน้าเก่า
func bot_step() -> String:
	var what := ""
	for guard: int in 2000:
		var s := BtBot.acting_squad(st)
		if s == null:
			break
		var a := BtBot.next_act(st, st.rng("bot:%d" % s.pl))
		if a.is_empty():
			break
		a["pid"] = ""
		apply(a)
		if last_error != "":
			break
		var code := str(a["a"])
		if code == "stay" or code == "skip":
			continue
		what = "move" if code == "smove" else "shoot"
		break
	flush(true, {"online": false})
	return what


## flushPend: ทอยทุกรายการที่เครื่องนี้เป็นคนทอย (force = ออฟไลน์ ทอยให้ทุกคน) ทีละ act ผ่าน apply
## ทางเลือกจาก BtBot.choice (คนจริงที่ทอยอัตโนมัติไม่ใช้ CP) ลูกเต๋าจาก dice:<ที่นั่ง> หรือ bot:<ที่นั่ง> (§3)
## act ของคนจริงถือ pid ของที่นั่ง ของบอทถือ "" · คืนจำนวน act ที่ใช้
func flush(force: bool, here: Dictionary) -> int:
	var h := here.duplicate()
	h["force"] = force
	var n := 0
	for guard: int in 400:
		var p := BtRoller.flush_plan(st, h)
		if p == null:
			break
		var dice := st.rng(BtRoller.stream_name(st, p, h))
		var acts := BtRoller.roll(st, p, BtBot.choice(st, p), dice)
		if acts.is_empty():
			break
		var q := st.seat(BtPend.roller_of(p))
		var pid := q.pid if q != null and not q.bot and not q.ai else ""
		for a: Dictionary in acts:
			a["pid"] = pid
			apply(a)
			if last_error != "":
				return n
			n += 1
	return n


## ค่าของ Table ตามสถานะจริง
func _sync() -> void:
	if st == null:
		return
	turn = st.turn
	round_no = st.round_no
	phase = st.phase
	over = 1 if st.over else 0
