class_name MissionObjectives
extends RefCounted
## เป้าหมายและสถิติของภารกิจ (CAMPAIGN_SPEC §2.4, §5.5, track C): เครื่องสถานะล้วน ไม่มีโหนด ไม่มีข้อความไทย เทสด้วยเวลาปลอมได้
## โลกส่งเหตุการณ์เข้ามา (ฆ่า ยิง โดน ปล่อย/ส่งตัวประกัน เสาพัง ฐานโดน สัญญาณ ล้ม ถึงจุดรับ) แล้วอ่าน outcome() / state() / result()
## หลัก: purge ฆ่าครบทุกตัวของแผน · defend ฐาน (base_hp) รอดจนหมดเวลา · rescue ตัวประกันหลักที่ยังมีชีวิตถึงจุดรับครบ (อย่างน้อย 1)
## ภายใน limit_s · destroy_camp ทำลายเสาหลักครบแล้วเดินกลับวงจุดรับ · รอง (ไม่กันชนะ): ฆ่า 75 % / ยึดสัญญาณ 30 วิ / ตัวประกันในกรง
## ถึงจุดรับ / เสานอกค่ายพัง · แพ้: ล้มหลังหมดสิทธิ์ลุก · ฐานพัง · ตัวประกันหลักตายหมด · หมดเวลาช่วยตัวประกัน
## ผลจบตายตัวครั้งเดียว (เหตุการณ์หลังจบไม่มีผล)

const FORMAT := 1
## สถานะตัวประกัน
const CAPTIVE := &"captive"
const FOLLOW := &"follow"
const SAVED := &"saved"
const DEAD := &"dead"

var spec: Dictionary = {}
var ptype := "purge"
var secondary: Array = []          # ประเภทของเป้าหมายรอง ตามลำดับ spec.secondary
var t := 0.0                       # เวลาเล่น (ไม่นับตอนหยุด)
var total := 0                     # ศัตรูทั้งแผน (รวมยามและหัวหน้า)
var kills := {"rusher": 0, "gunner": 0, "brute": 0, "boss": 0, "structure": 0}
var killed := 0
var shots := 0
var hits := 0
var damage_taken := 0
var downs := 0
var revives_left := 0
var base_hp := 0
var base_max := 0
var beacon_s := 0.0
var beacon_on := false
var at_pickup := false
var hostages: Array[Dictionary] = []    # {"state", "primary": bool}
var pylons: Array[Dictionary] = []      # {"hp", "max", "primary": bool}
var _outcome := ""


## p_total = MissionWaves.total(plan) · ตัวประกัน/เสา: หลัก (3) ก่อน แล้วของเป้าหมายรอง (1) ตาม MissionLayout
func _init(p_spec: Dictionary, p_total: int) -> void:
	spec = p_spec
	ptype = str((spec.get("primary", {}) as Dictionary).get("type", "purge"))
	for e: Dictionary in spec.get("secondary", []):
		secondary.append(str(e.get("type", "")))
	total = maxi(p_total, 0)
	var d: Dictionary = spec.get("diff", {})
	revives_left = int(d.get("revives", 2))
	var row: Dictionary = MissionTypes.TYPES.get(ptype, {})
	if ptype == "defend":
		base_max = int(row.get("base_hp", 1000))
		base_hp = base_max
	if ptype == "rescue":
		for i in int(row.get("hostages", 3)):
			hostages.append({"state": CAPTIVE, "primary": true})
	if secondary.has("rescue"):
		hostages.append({"state": CAPTIVE, "primary": false})
	var php := int(row.get("pylon_hp", int(MissionTypes.TYPES["destroy_camp"]["pylon_hp"])))
	php = maxi(php * int(d.get("hp_pct", 100)) / 100, 1)
	if ptype == "destroy_camp":
		for i in int(row.get("pylons", 3)):
			pylons.append({"hp": php, "max": php, "primary": true})
	if secondary.has("destroy_camp"):
		pylons.append({"hp": php, "max": php, "primary": false})


func outcome() -> String:
	return _outcome


func ended() -> bool:
	return _outcome != ""


## เวลาผ่านไป (ไม่เรียกตอนหยุด): ป้องกันฐานนับถอยหลัง · ช่วยตัวประกันหมดเวลา = แพ้
func tick(dt: float) -> void:
	if ended() or dt <= 0.0:
		return
	t += dt
	var lim := MissionTypes.limit_s(ptype)
	if ptype == "defend" and t >= float(lim):
		t = float(lim)
		if base_hp > 0:
			_outcome = "win"
		return
	if ptype == "rescue" and lim > 0 and t >= float(lim):
		_outcome = "fail"


## เวลาที่เหลือ (ป้องกันฐาน / ช่วยตัวประกัน) หรือ −1
func timer_s() -> float:
	var lim := MissionTypes.limit_s(ptype)
	if lim <= 0:
		return -1.0
	return maxf(float(lim) - t, 0.0)


func kill(role: String) -> void:
	if ended():
		return
	kills[role] = int(kills.get(role, 0)) + 1
	killed += 1
	_check()


func shot() -> void:
	if not ended():
		shots += 1


func hit() -> void:
	if not ended():
		hits += 1


func hurt(amount: int) -> void:
	if not ended():
		damage_taken += maxi(amount, 0)


## ผู้เล่นล้ม: คืน "revive" (ยังลุกได้) หรือ "fail" (ล้มหลังหมดสิทธิ์ลุก)
func player_down() -> String:
	if ended():
		return ""
	downs += 1
	if revives_left <= 0:
		_outcome = "fail"
		return "fail"
	revives_left -= 1
	return "revive"


func quit() -> void:
	if not ended():
		_outcome = "quit"


func base_damage(amount: int) -> int:
	if ended() or ptype != "defend" or amount <= 0:
		return 0
	var a := mini(amount, base_hp)
	base_hp -= a
	if base_hp <= 0:
		_outcome = "fail"
	return a


func base_pct() -> int:
	return base_hp * 100 / base_max if base_max > 0 else 0


## โดนเสาพิธี i: {"applied", "hp", "killed"} (สัญญาเดียวกับ take_hit)
func damage_pylon(i: int, amount: int) -> Dictionary:
	if ended() or i < 0 or i >= pylons.size() or int(pylons[i]["hp"]) <= 0:
		return {"applied": 0, "hp": 0, "killed": false}
	var r := ArenaCombat.apply(int(pylons[i]["hp"]), amount)
	pylons[i]["hp"] = int(r["hp"])
	if bool(r["killed"]):
		kills["structure"] = int(kills["structure"]) + 1
		_check()
	return r


func pylons_left(primary := true) -> int:
	var n := 0
	for p in pylons:
		if bool(p["primary"]) == primary and int(p["hp"]) > 0:
			n += 1
	return n


func hostage_state(i: int) -> StringName:
	return hostages[i]["state"] if i >= 0 and i < hostages.size() else &""


func free_hostage(i: int) -> bool:
	if ended() or hostage_state(i) != CAPTIVE:
		return false
	hostages[i]["state"] = FOLLOW
	return true


func save_hostage(i: int) -> bool:
	if ended() or hostage_state(i) != FOLLOW:
		return false
	hostages[i]["state"] = SAVED
	_check()
	return true


func hostage_died(i: int) -> bool:
	if ended() or hostage_state(i) == SAVED or hostage_state(i) == DEAD or hostage_state(i) == &"":
		return false
	hostages[i]["state"] = DEAD
	_check()
	return true


func count_hostages(state: StringName, primary: Variant = null) -> int:
	var n := 0
	for h in hostages:
		if h["state"] == state and (primary == null or bool(h["primary"]) == bool(primary)):
			n += 1
	return n


## เปิดสัญญาณ (กด E ในวงครั้งแรก) แล้วยืนในวงนับเวลา
func beacon_start() -> bool:
	if ended() or not secondary.has("defend") or beacon_on:
		return false
	beacon_on = true
	return true


func beacon_tick(dt: float, inside: bool) -> void:
	if ended() or not beacon_on or not inside:
		return
	var need := float(MissionTypes.SECONDARY["defend"]["hold_s"])
	beacon_s = minf(beacon_s + dt, need)


## ผู้เล่นอยู่ในวงจุดรับ (ถอนตัวหลังทำลายค่าย)
func set_at_pickup(on: bool) -> void:
	if at_pickup == on:
		return
	at_pickup = on
	_check()


## ต้องเดินกลับจุดรับแล้ว (ทำลายค่าย: เสาหลักพังครบ)
func extract_ready() -> bool:
	return ptype == "destroy_camp" and not pylons.is_empty() and pylons_left(true) == 0


func secondary_done() -> Array:
	var out: Array = []
	for s in secondary:
		out.append(_sec_done(str(s)))
	return out


## สถานะสำหรับ HUD: {"primary": {type, done, progress, total, extract}, "secondary": [{type, done, progress, total}], "timer_s",
## "base_pct", "hostages": {freed, saved, alive, total}, "revives"}
func state() -> Dictionary:
	var prog := 0
	var tot := 1
	match ptype:
		"purge":
			prog = killed
			tot = total
		"defend":
			prog = int(t)
			tot = MissionTypes.limit_s(ptype)
		"rescue":
			prog = count_hostages(SAVED, true)
			tot = count_hostages(CAPTIVE, true) + count_hostages(FOLLOW, true) + prog
		"destroy_camp":
			prog = pylons.filter(func(p: Dictionary) -> bool: return bool(p["primary"]) and int(p["hp"]) <= 0).size()
			tot = pylons.filter(func(p: Dictionary) -> bool: return bool(p["primary"])).size()
	var sec: Array = []
	for s in secondary:
		var sp := 0
		var st := 1
		match str(s):
			"purge":
				sp = killed
				st = _kill_need()
			"defend":
				sp = int(beacon_s)
				st = int(MissionTypes.SECONDARY["defend"]["hold_s"])
			"rescue":
				sp = count_hostages(SAVED, false)
				st = 1
			"destroy_camp":
				sp = 1 - pylons_left(false)
				st = 1
		sec.append({"type": str(s), "done": _sec_done(str(s)), "progress": mini(sp, st), "total": st,
			"on": beacon_on if str(s) == "defend" else false})
	return {
		"primary": {"type": ptype, "done": _outcome == "win", "progress": prog, "total": tot, "extract": extract_ready()},
		"secondary": sec, "timer_s": timer_s(), "base_pct": base_pct() if ptype == "defend" else -1,
		"hostages": {"freed": count_hostages(FOLLOW), "saved": count_hostages(SAVED),
			"alive": hostages.size() - count_hostages(DEAD), "total": hostages.size()},
		"revives": revives_left, "outcome": _outcome,
	}


## MissionResult (CAMPAIGN_SPEC §5.5): คีย์ hostages_* เฉพาะเมื่อมีตัวประกัน, base_hp_pct เฉพาะป้องกันฐาน
func result() -> Dictionary:
	var r := {"v": FORMAT, "outcome": _outcome if _outcome != "" else "quit", "time_s": snappedf(t, 0.01),
		"kills": kills.duplicate(), "shots": shots, "hits": mini(hits, shots), "damage_taken": damage_taken, "downs": downs,
		"secondary_done": secondary_done()}
	if not hostages.is_empty():
		r["hostages_saved"] = count_hostages(SAVED)
		r["hostages_total"] = hostages.size()
	if ptype == "defend":
		r["base_hp_pct"] = base_pct()
	return r


# ---- ภายใน ----

func _kill_need() -> int:
	return maxi((total * int(MissionTypes.SECONDARY["purge"]["kill_pct"]) + 99) / 100, 1)


func _sec_done(s: String) -> bool:
	match s:
		"purge":
			return killed >= _kill_need()
		"defend":
			return beacon_s >= float(MissionTypes.SECONDARY["defend"]["hold_s"]) - 0.0001
		"rescue":
			return count_hostages(SAVED, false) > 0
		"destroy_camp":
			return pylons.size() > 0 and pylons_left(false) == 0 and pylons.any(func(p: Dictionary) -> bool: return not bool(p["primary"]))
	return false


func _check() -> void:
	if ended():
		return
	match ptype:
		"purge":
			if total > 0 and killed >= total:
				_outcome = "win"
		"rescue":
			var alive := count_hostages(CAPTIVE, true) + count_hostages(FOLLOW, true)
			var saved := count_hostages(SAVED, true)
			if alive == 0:
				_outcome = "win" if saved > 0 else "fail"
		"destroy_camp":
			if extract_ready() and at_pickup:
				_outcome = "win"
