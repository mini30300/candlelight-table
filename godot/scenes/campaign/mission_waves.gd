class_name MissionWaves
extends RefCounted
## ระลอกศัตรูของภารกิจ (CAMPAIGN_SPEC §2.4, §5.4, track C): ฟังก์ชันล้วนของ spec ไม่สุ่ม ไม่มีโหนด
## จำนวนทั้งภารกิจ = MissionTypes.enemy_total(spec) แบ่งให้ระลอกตามน้ำหนัก 2, 3, 4, … (ระลอกหลังหนักกว่า) เศษไปไว้ระลอกท้าย
## แต่ละระลอกแบ่งบทบาทตาม MissionRoster.SHARE (gunline มือปืน ×2 · ฝ่ายที่ไม่มีมือปืนยกให้ rusher) · หัวหน้ามาเพิ่มในระลอกท้าย
## ทำลายค่าย: ยามค่าย (ฝ่าย cult เสมอ) เป็นรายการแรก post "camp" ไม่นับใน enemy_total · ช่วยตัวประกัน: ระลอกแรกเฝ้าตัวประกัน
## ambush: ระลอกแรกเกิดที่จุดใกล้ผู้เล่น (spawn "near")
## รายการ: {"at_s": วิ (−1 = ไม่มีเวลา), "after_clear": รอระลอกก่อนตายหมด, "spawn": "edge" | "near" | "camp", "post": "" | "camp" | "hostages",
##   "guard": bool, "units": [{"role", "kit", "count", "faction"}]} · ระลอกเริ่มเมื่อถึงเวลา หรือ (after_clear และระลอกก่อนหน้าตายหมด)


static func plan(spec: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var ptype := str((spec.get("primary", {}) as Dictionary).get("type", "purge"))
	var row: Dictionary = MissionTypes.TYPES.get(ptype, MissionTypes.TYPES["purge"])
	var faction := str(spec.get("faction", "swarm"))
	var mod := str(spec.get("modifier", ""))
	var guards := MissionTypes.guard_count(spec)
	if guards > 0:
		var gg := guards * 30 / 100
		var gu: Array[Dictionary] = []
		_add(gu, "rusher", "cult", guards - gg)
		_add(gu, "gunner", "cult", gg)
		out.append({"at_s": 0.0, "after_clear": false, "spawn": "camp", "post": "camp", "guard": true, "units": gu})
	var total := MissionTypes.enemy_total(spec)
	var n := maxi(int(row.get("waves", 1)), 1)
	var at: Array = row.get("wave_at", [])
	var wsum := 0
	for i in n:
		wsum += i + 2
	var left := total
	for i in n:
		var cnt := total * (i + 2) / wsum if i < n - 1 else left
		left -= cnt
		var units: Array[Dictionary] = []
		var gshare := int(MissionRoster.SHARE["gunner"])
		if MissionTypes.MODIFIERS.get(mod, {}).has("gunner_share_pct"):
			gshare = gshare * int(MissionTypes.MODIFIERS[mod]["gunner_share_pct"]) / 100
		if MissionRoster.kit(faction, "gunner") == "":
			gshare = 0
		var bshare := int(MissionRoster.SHARE["brute"]) if i > 0 or n == 1 else 0
		var g := cnt * gshare / 100
		var b := cnt * bshare / 100
		_add(units, "rusher", faction, cnt - g - b)
		_add(units, "gunner", faction, g)
		_add(units, "brute", faction, b)
		if i == n - 1:
			_add(units, "boss", faction, MissionTypes.boss_count(spec))
		var a := float(at[i]) if i < at.size() else -1.0
		var w := {"at_s": a, "after_clear": i > 0 and (a < 0.0 or ptype != "defend"),
			"spawn": "near" if i == 0 and mod == "ambush" else "edge",
			"post": "hostages" if i == 0 and ptype == "rescue" else "", "guard": false, "units": units}
		if i == 0 and a < 0.0:
			w["at_s"] = 0.0
		out.append(w)
	return out


## จำนวนศัตรูทั้งแผน (รวมยามและหัวหน้า)
static func total(p: Array) -> int:
	var n := 0
	for w: Dictionary in p:
		for u: Dictionary in w["units"]:
			n += int(u["count"])
	return n


## จำนวนต่อบทบาท (ไม่รวมยามเมื่อ guards = false)
static func by_role(p: Array, guards := true) -> Dictionary:
	var out := {"rusher": 0, "gunner": 0, "brute": 0, "boss": 0}
	for w: Dictionary in p:
		if bool(w.get("guard", false)) and not guards:
			continue
		for u: Dictionary in w["units"]:
			out[str(u["role"])] = int(out.get(str(u["role"]), 0)) + int(u["count"])
	return out


static func _add(units: Array[Dictionary], role: String, faction: String, count: int) -> void:
	if count <= 0:
		return
	units.append({"role": role, "kit": MissionRoster.kit(faction, role), "count": count, "faction": faction})
