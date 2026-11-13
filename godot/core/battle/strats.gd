class_name BtStrats
extends RefCounted
## กลยุทธ์ (R1_PORT_SPEC §1 strats): แต้มคำสั่ง (CP) เป็นของแต่ละที่นั่ง แต่ล็อกเป็นของทีม
## ใช้ได้ทีมละครั้งต่อเฟส ส่วนใจเหล็ก (brave) ทีมละครั้งต่อเทิร์น; ทอยใหม่ของการยิงกับการบุกใช้คีย์ rr เดียวกัน
## คีย์ล็อกเป็นสตริงแบบหน้าเก่า (stratKey) เก็บใน st.used ดูอย่างเดียว

## ราคาเป็น CP ตาม data/strats.json (ลำดับเดียวกัน) test_strats เทียบกับไฟล์ทุกครั้ง
const KEYS := ["rr", "ow", "gtg", "gren", "brave"]
const COST := {"rr": 1, "ow": 1, "gtg": 1, "gren": 1, "brave": 1}


## ราคาของกลยุทธ์ k; ไม่รู้จักคืน -1
static func cost(k: String) -> int:
	return int(COST[k]) if COST.has(k) else -1


## คีย์ล็อก (stratKey) k:ทีม:รอบ:เทิร์น:เฟส ใจเหล็กเว้นช่องเฟสว่าง
static func key(st: BattleState, k: String, team: int) -> String:
	var ph := "" if k == "brave" else st.phase_name()
	return "%s:%d:%d:%d:%s" % [k, team, st.round_no, st.turn, ph]


## ใช้ได้ไหม (canStrat): ยังไม่จบ มีที่นั่ง CP พอ และทีมยังไม่ได้ใช้ในช่วงนี้
static func can(st: BattleState, k: String, pi: int) -> bool:
	var p := st.seat(pi)
	if p == null or st.over:
		return false
	var c := cost(k)
	if c < 0:
		return false
	return p.cp >= c and not st.used.has(key(st, k, p.team))


## ใช้กลยุทธ์ (useStrat): หัก CP ของที่นั่ง ล็อกทั้งทีม บันทึก strat_used [ที่นั่ง, k, CP] และส่ง STRAT {k, team}
## ใช้ไม่ได้คืน false ไม่แตะอะไร
static func use(st: BattleState, k: String, pi: int, out: Array[Dictionary]) -> bool:
	if not can(st, k, pi):
		return false
	var p := st.seat(pi)
	var c := cost(k)
	p.cp -= c
	st.used[key(st, k, p.team)] = true
	st.say("strat_used", [pi, k, c])
	out.append(Events.make(Events.Id.STRAT, {"k": k, "team": p.team}))
	return true
