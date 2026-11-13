class_name NetSeats
extends RefCounted
## ที่นั่งของเกมออนไลน์ (NET_SPEC §5.1) ไม่มี Node: ตัวเลือกแบบ SeatPlan + owner ต่อที่นั่ง (ช่องของสมาชิก หรือ -1 = บอท)
## สร้างแผนด้วย SeatPlan.build ที่ทุกที่นั่งเป็นบอท (ไม่ติดกฎคุณได้ที่เดียว) แล้วให้ที่นั่งของสมาชิก bot = false
## pid "n<ช่อง>" และชื่อ ก่อน Battle.make ทุกเครื่องจึงได้ pid เดียวกันใน digest · ตัวเลือกล่าสุดอยู่ในหน่วยความจำ (last)

const ERROR_TEXT := {
	"member_twice": "เพื่อนคนหนึ่งนั่งได้ที่เดียว",
	"member_gone": "เพื่อนคนนี้ออกจากห้องไปแล้ว",
}

## ตัวเลือกออนไลน์ล่าสุด (ไม่ใช่ App.last_choice: หน้าตั้งเกมออฟไลน์ไม่เปลี่ยน)
static var last: Dictionary = {}


static func pid_of(slot: int) -> String:
	return "n%d" % slot


## ช่องของสมาชิกทั้งหมดตามลำดับ
static func _slots(members: Array) -> PackedInt32Array:
	var out := PackedInt32Array()
	for m: Variant in members:
		if m is Dictionary:
			out.append(int((m as Dictionary).get("slot", -1)))
	out.sort()
	return out


static func _member(members: Array, slot: int) -> Dictionary:
	for m: Variant in members:
		if m is Dictionary and int((m as Dictionary).get("slot", -1)) == slot:
			return m
	return {}


## เจ้าของที่นั่ง k (-1 = บอท)
static func owner_of(choice: Dictionary, k: int) -> int:
	var seats: Array = choice.get("seats", [])
	if k < 0 or k >= seats.size() or not seats[k] is Dictionary:
		return -1
	return int((seats[k] as Dictionary).get("owner", -1))


## ตัวเลือกเริ่มต้น: ทีม = จำนวนสมาชิก (2–4) ทีมละ 1 · 5–6 คน 3 ทีม ทีมละ 2 · ที่นั่ง k เป็นของสมาชิกคนที่ k ที่เหลือบอท
## กองทัพ = ที่สมาชิกอยากใช้ ไม่งั้นค่าเริ่มต้นแบบออฟไลน์
static func defaults(members: Array, seed_v: int) -> Dictionary:
	var c := SeatPlan.defaults(seed_v)
	var slots := _slots(members)
	var n := slots.size()
	# 5–6 คน: 3 ทีม × 2 (4 × 2 เกินหกที่นั่ง)
	c["teams"] = 3 if n > SeatPlan.MAX_TEAMS else clampi(n, SeatPlan.MIN_TEAMS, SeatPlan.MAX_TEAMS)
	c["per_team"] = 2 if n > SeatPlan.MAX_TEAMS else 1
	var base: Array = c["seats"]
	var seats: Array = []
	for k: int in SeatPlan.seat_count(c):
		var fac := str((base[k] as Dictionary).get("fac", "")) if k < base.size() else ""
		var own := int(slots[k]) if k < n else -1
		if own >= 0:
			var pick := str(_member(members, own).get("pick", ""))
			if pick != "" and GameData.factions().has(pick):
				fac = pick
		seats.append({"fac": fac, "human": own == 0, "owner": own})
	c["seats"] = seats
	var size := SeatPlan.size_for(seats.size())
	if int(SeatPlan.SIZES.get(str(c["size"]), 0)) < SeatPlan.MIN_W + SeatPlan.W_PER_SEAT * seats.size() and size != "":
		c["size"] = size
	return c


## ปรับจำนวนที่นั่งตามทีม × ขนาดทีม (ที่นั่งใหม่เป็นบอท) และเติม owner ให้ครบ
static func fit(choice: Dictionary) -> void:
	SeatPlan.fit_seats(choice)
	for sd: Variant in choice["seats"]:
		var d: Dictionary = sd
		if not d.has("owner"):
			d["owner"] = 0 if bool(d.get("human", false)) else -1
		d["human"] = int(d["owner"]) == 0


## ตั้งเจ้าของที่นั่ง k (เจ้าห้องกดปุ่ม) · สมาชิกคนนั้นนั่งที่อื่นอยู่: ที่เดิมกลายเป็นบอท
static func set_owner(choice: Dictionary, k: int, slot: int) -> void:
	var seats: Array = choice.get("seats", [])
	if k < 0 or k >= seats.size():
		return
	if slot >= 0:
		for i: int in seats.size():
			if i != k and int((seats[i] as Dictionary).get("owner", -1)) == slot:
				(seats[i] as Dictionary)["owner"] = -1
				(seats[i] as Dictionary)["human"] = false
	(seats[k] as Dictionary)["owner"] = slot
	(seats[k] as Dictionary)["human"] = slot == 0


## ปุ่มเจ้าของของแถว k: บอท → คุณ (ช่อง 0) → สมาชิกที่ยังไม่มีที่นั่งทีละคน → บอท
static func next_owner(choice: Dictionary, k: int, members: Array) -> int:
	var cur := owner_of(choice, k)
	var order: Array[int] = [-1, 0]
	for s: int in _slots(members):
		if s > 0:
			order.append(s)
	var i := order.find(cur)
	for step: int in range(1, order.size() + 1):
		var cand: int = order[(i + step) % order.size()]
		if cand <= 0:
			return cand
		# สมาชิกที่นั่งที่อื่นอยู่แล้วข้ามไป
		var seated := false
		var seats: Array = choice.get("seats", [])
		for j: int in seats.size():
			if j != k and int((seats[j] as Dictionary).get("owner", -1)) == cand:
				seated = true
		if not seated:
			return cand
	return -1


## คำขอที่นั่งจากสมาชิก (CLAIM): k = ที่นั่งบอท → ของสมาชิกนั้น (ที่เดิมเป็นบอท) · k = -1 ลุก · อื่น ๆ ไม่สน
## คืน true ถ้าตัวเลือกเปลี่ยน
static func claim(choice: Dictionary, slot: int, k: int) -> bool:
	if slot <= 0:
		return false
	var seats: Array = choice.get("seats", [])
	if k == -1:
		var changed := false
		for sd: Variant in seats:
			if int((sd as Dictionary).get("owner", -1)) == slot:
				(sd as Dictionary)["owner"] = -1
				(sd as Dictionary)["human"] = false
				changed = true
		return changed
	if k < 0 or k >= seats.size() or int((seats[k] as Dictionary).get("owner", -1)) != -1:
		return false
	set_owner(choice, k, slot)
	return true


## สมาชิกที่ออกจากห้อง: ที่นั่งของเขากลายเป็นบอท · คืน true ถ้าเปลี่ยน
static func drop_gone(choice: Dictionary, members: Array) -> bool:
	var slots := _slots(members)
	var changed := false
	for sd: Variant in choice.get("seats", []):
		var o := int((sd as Dictionary).get("owner", -1))
		if o > 0 and not slots.has(o):
			(sd as Dictionary)["owner"] = -1
			(sd as Dictionary)["human"] = false
			changed = true
	return changed


## รายการที่นั่งของข้อความ SETUP: [{team, owner, fac}]
static func seats_body(choice: Dictionary) -> Array:
	var out: Array = []
	var seats: Array = choice.get("seats", [])
	for k: int in seats.size():
		var sd: Dictionary = seats[k]
		out.append({"team": SeatPlan.team_of(choice, k), "owner": int(sd.get("owner", -1)), "fac": str(sd.get("fac", ""))})
	return out


## ตัวเลือกที่ทุกที่นั่งเป็นบอท (ให้ SeatPlan ตรวจและสร้างโดยไม่นับคนจริง)
static func _all_bots(choice: Dictionary) -> Dictionary:
	var c := choice.duplicate(true)
	for sd: Variant in c.get("seats", []):
		if sd is Dictionary:
			(sd as Dictionary)["human"] = false
	return c


## รหัสข้อผิดพลาด: ของ SeatPlan (ไม่นับ humans) + member_twice (สมาชิกนั่งสองที่) + member_gone (เจ้าของไม่อยู่ในห้อง)
static func validate(choice: Dictionary, members: Array) -> PackedStringArray:
	var out := SeatPlan.validate(_all_bots(choice))
	var slots := _slots(members)
	var seen := {}
	var twice := false
	var gone := false
	for sd: Variant in choice.get("seats", []):
		if not sd is Dictionary:
			continue
		var o := int((sd as Dictionary).get("owner", -1))
		if o < 0:
			continue
		if seen.has(o):
			twice = true
		seen[o] = true
		if not slots.has(o):
			gone = true
	if twice:
		out.append("member_twice")
	if gone:
		out.append("member_gone")
	return out


## แผนของเกม: SeatPlan.build (ทุกที่นั่งบอท) แล้วที่นั่งของสมาชิก bot = false pid = "n<ช่อง>" nm = ชื่อ
## + owners (ช่องหรือ -1 ต่อที่นั่ง) + human = ที่นั่งของเจ้าห้อง (ช่อง 0) หรือ -1 · errors ตาม validate
static func build(choice: Dictionary, members: Array) -> Dictionary:
	var plan := SeatPlan.build(_all_bots(choice))
	var owners: Array = []
	var human := -1
	var seats: Array = plan["seats"]
	for k: int in seats.size():
		var o := owner_of(choice, k)
		var sd: Dictionary = seats[k]
		if o >= 0:
			sd["bot"] = false
			sd["pid"] = pid_of(o)
			sd["nm"] = NetProto.clean_name(str(_member(members, o).get("nm", "")))
			if o == 0 and human < 0:
				human = k
		else:
			sd["bot"] = true
			sd["pid"] = ""
			sd["nm"] = ""
		owners.append(o)
	plan["owners"] = owners
	plan["human"] = human
	plan["errors"] = validate(choice, members)
	plan["choice"] = choice.duplicate(true)
	return plan


## ข้อความของรหัส (ของออนไลน์จาก online_battle.json ที่เหลือของ SeatPlan)
static func error_text(code: String, choice: Dictionary) -> String:
	if ERROR_TEXT.has(code):
		return DatasheetText.tl(str(ERROR_TEXT[code]))
	return SeatPlan.error_text(code, choice)
