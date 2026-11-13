class_name BtObjectives
extends RefCounted
## จุดยึดกับแต้มชัย (R1_PORT_SPEC หัวข้อ objectives.gd) ตามหน้าเก่า 33922–33940: ห้าจุด กลางโต๊ะกับสี่ทิศเฉียง
## ค่าคุมจุด (OC) ของทีม = ผลรวม oc ของโมเดลที่ฐานอยู่ในระยะ OBJ_R ของจุด (หมู่ขวัญเสียไม่นับ)
## เจ้าของจุดไม่เก็บไว้ คิดใหม่ทุกครั้งที่ใช้ (กระดาน บอท นับแต้ม); ไม่มีการสุ่ม

## ฐานที่ใช้หาที่ว่างให้จุดยึด (MI)
const SPOT_R := 1200
## ระยะของจุดเฉียงจากกลางโต๊ะ: 270 ส่วนพันของกว้าง/ลึก (w, d เป็นนิ้ว ได้ MI พอดี)
const SPREAD := 270


## วางจุดยึด (placeObjectives) หลัง deploy: [0,0] [-rx,-rz] [rx,-rz] [-rx,rz] [rx,rz] เลขจุด 1..5
## แต่ละจุดเลื่อนไปที่ว่างที่ใกล้ที่สุด (free_spot ฐาน 1200 MI ไม่ทับโมเดลที่ยืนอยู่)
static func place(st: BattleState) -> void:
	# จุดยึดไม่มีดัชนีให้ดูแล ล้างแล้ววางใหม่ได้ เหมือนหน้าเก่า OBJ = []
	st.objs.clear()
	var rx := st.w * SPREAD
	var rz := st.d * SPREAD
	var spots := [[0, 0], [-rx, -rz], [rx, -rz], [-rx, rz], [rx, rz]]
	var none := PackedInt64Array()
	for i: int in spots.size():
		var p: Array = spots[i]
		var sp := BtBlocking.free_spot(st, int(p[0]), int(p[1]), null, none, 0, SPOT_R)
		st.add_obj(i + 1, sp[0], sp[1])


## ค่า oc ของชนิด (หน้าเก่า TY(คีย์ที่ไม่รู้จัก) ได้ชนิดแรกของ TYPES)
static func _oc_of(ti: int) -> int:
	var types := GameData.types()
	if types.is_empty():
		return 0
	var t: Dictionary = types[ti] if ti >= 0 and ti < types.size() else types[0]
	return int(t.get("oc", 0))


## ค่าคุมจุดของทีม (objOC): โมเดลตามลำดับ units ของทีมนั้น หมู่ไม่ขวัญเสีย
## ระยะกลางฐานถึงจุดไม่เกิน OBJ_R + รัศมีฐาน + 1 MI (หนึ่งในพันนิ้วของหน้าเก่า)
static func oc(st: BattleState, o: BattleState.Obj, team: int) -> int:
	if o == null:
		return 0
	var reach := GameData.const_int("OBJ_R", 3) * 1000 + 1
	var n := 0
	for m: BattleState.Unit in st.units:
		if m.side != team:
			continue
		var s := st.squad(m.sq)
		if s == null or s.shaken:
			continue
		var lim := reach + BtSquads.radius_of(m.ti)
		if Fx.dist2(m.x, m.z, o.x, o.z) <= lim * lim:
			n += _oc_of(m.ti)
	return n


## เจ้าของจุด (objCtl): ทีมที่ OC มากที่สุด ไล่ทีม 0.. ทีมหลังที่มากกว่าล้างการเสมอ
## มากสุดเสมอกัน หรือไม่มีใครเลย = -1
static func ctl(st: BattleState, o: BattleState.Obj) -> int:
	var best := -1
	var bn := 0
	var tie := false
	for t: int in st.teams:
		var n := oc(st, o, t)
		if n > bn:
			bn = n
			best = t
			tie = false
		elif n != 0 and n == bn:
			tie = true
	return -1 if tie else best


## นับแต้มชัยของทีม (scoreObjectives): VP_PER ต่อจุดที่คุม ไม่เกิน VP_CAP ต่อครั้ง
## บันทึก obj_score [ทีม, จำนวนจุด, แต้มที่ได้, แต้มรวม, เลขจุดที่คุม...] และส่ง LOG_LINE เดียวกัน
## ทีมนอกช่วงของ vp ไม่ได้แต้ม (หน้าเก่าไม่เคยเรียกแบบนั้น)
static func score(st: BattleState, team: int, out: Array[Dictionary]) -> void:
	var held: Array = []
	for o: BattleState.Obj in st.objs:
		if ctl(st, o) == team:
			held.append(o.n)
	var got := mini(GameData.const_int("VP_CAP", 15), held.size() * GameData.const_int("VP_PER", 5))
	var total := got
	if team >= 0 and team < st.vp.size():
		st.vp[team] += got
		total = st.vp[team]
	var args: Array = [team, held.size(), got, total]
	args.append_array(held)
	st.say("obj_score", args)
	out.append(Events.make(Events.Id.LOG_LINE, {"key": "obj_score", "args": args.duplicate()}))
