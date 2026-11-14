class_name CampaignSave
extends RefCounted
## ที่เก็บของแคมเปญในเครื่อง (CAMPAIGN_SPEC §2.8): เหรียญ ความยากล่าสุด คะแนนดีสุดและเหตุการณ์ที่ผ่านแล้วของสัปดาห์
## ไฟล์ user://campaign.json (มีเลขรุ่น "v") · ไม่ใช่ data/*.json (DATA_HASH ไม่เปลี่ยน) · ไม่ใช่ settings.cfg
## รอบหน้าเหรียญย้ายไปเซิร์ฟเวอร์ (กันโกง): ไฟล์นี้จะเหลือแค่ความยากล่าสุดกับประวัติ
## เทสชี้ไฟล์อื่นด้วย CampaignSave.path · ไฟล์เสีย/รุ่นไม่รู้จัก = เริ่มใหม่ (คำเตือน ไม่ล่ม)
## ค่าที่อ่านมาตรวจทุกช่อง (ชนิด ช่วง): ส่วนที่ผิดถูกทิ้ง ส่วนที่ถูกเก็บไว้

const PATH := "user://campaign.json"
const VERSION := 1
const HISTORY := 20              # เก็บผลล่าสุดกี่รายการ
const KEEP_WEEKS := 2            # เก็บ best/clears ของสัปดาห์นี้กับสัปดาห์ก่อน
const COIN_CAP := 1_000_000_000  # เพดานเหรียญ (กันเลขล้น)

static var path := PATH
static var _data: Dictionary = {}
static var _loaded := false


static func blank() -> Dictionary:
	return {"v": VERSION, "coins": 0, "last_difficulty": "", "weeks": {}, "history": []}


## ข้อมูลทั้งหมด (อ่านไฟล์ครั้งแรก)
static func data() -> Dictionary:
	if not _loaded:
		load_file()
	return _data


static func load_file() -> void:
	_loaded = true
	_data = blank()
	if not FileAccess.file_exists(path):
		return
	var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not d is Dictionary or int((d as Dictionary).get("v", 0)) != VERSION:
		# เก็บไฟล์เสีย/รุ่นใหม่กว่าไว้ข้างๆ ก่อนจะถูกเขียนทับ
		var v := int((d as Dictionary).get("v", 0)) if d is Dictionary else 0
		var keep := path + (".v%d" % v if v > VERSION else ".bad")
		DirAccess.copy_absolute(ProjectSettings.globalize_path(path), ProjectSettings.globalize_path(keep))
		push_warning("campaign save: %s is unreadable or of another version; kept as %s, starting fresh" % [path, keep])
		return
	var ld: Variant = (d as Dictionary).get("last_difficulty", "")
	if ld is String and CampaignGalaxy.DIFFICULTIES.has(ld):
		_data["last_difficulty"] = ld
	_data["weeks"] = _clean_weeks((d as Dictionary).get("weeks", {}))
	var h: Variant = (d as Dictionary).get("history", [])
	if h is Array:
		for e: Variant in h:
			var he := _clean_entry(e)
			if not he.is_empty() and (_data["history"] as Array).size() < HISTORY:
				(_data["history"] as Array).append(he)
	# JSON อ่านเลขเป็น float
	var c: Variant = (d as Dictionary).get("coins", 0)
	_data["coins"] = clampi(int(c), 0, COIN_CAP) if c is float or c is int else 0


## รายการประวัติที่อ่านมา: ช่องครบและชนิดถูก ไม่งั้น {}
static func _clean_entry(e: Variant) -> Dictionary:
	if not e is Dictionary:
		return {}
	var x := e as Dictionary
	for k: String in ["week", "total", "coins"]:
		if not (x.get(k) is float or x.get(k) is int):
			return {}
	if not x.get("key") is String or not x.get("grade") is String:
		return {}
	return {"week": int(x["week"]), "key": str(x["key"]), "total": maxi(int(x["total"]), 0),
		"coins": clampi(int(x["coins"]), 0, COIN_CAP), "grade": str(x["grade"])}


## weeks ที่อ่านมา: คีย์เป็นเลขสัปดาห์ best = {key: เลข ≥ 0}, clears = {key: true} · ที่เหลือทิ้ง
static func _clean_weeks(w: Variant) -> Dictionary:
	var out := {}
	if not w is Dictionary:
		return out
	for wk: Variant in w:
		var v: Variant = w[wk]
		if not str(wk).is_valid_int() or not v is Dictionary:
			continue
		var best := {}
		var clears := {}
		var b: Variant = (v as Dictionary).get("best", {})
		if b is Dictionary:
			for k: Variant in b:
				if b[k] is float or b[k] is int:
					best[str(k)] = maxi(int(b[k]), 0)
		var cl: Variant = (v as Dictionary).get("clears", {})
		if cl is Dictionary:
			for k: Variant in cl:
				if cl[k] is bool and cl[k]:
					clears[str(k)] = true
		out[str(int(str(wk)))] = {"best": best, "clears": clears}
	return out


## เขียนไฟล์ชั่วคราวให้เสร็จก่อนแล้วค่อยย้ายทับ (แอปถูกปิดกลางทาง ไฟล์เดิมยังอยู่ครบ)
static func save() -> bool:
	var tmp := path + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		push_warning("campaign save: cannot write %s" % tmp)
		return false
	f.store_string(JSON.stringify(data(), "  "))
	var err := f.get_error()
	f.close()
	if err != OK:
		push_warning("campaign save: writing %s failed (%d)" % [tmp, err])
		return false
	if DirAccess.rename_absolute(ProjectSettings.globalize_path(tmp), ProjectSettings.globalize_path(path)) != OK:
		push_warning("campaign save: cannot replace %s" % path)
		return false
	return true


static func reset() -> void:
	_loaded = true
	_data = blank()


static func coins() -> int:
	return int(data()["coins"])


static func last_difficulty() -> String:
	return str(data()["last_difficulty"])


static func set_last_difficulty(id: String) -> void:
	data()["last_difficulty"] = id
	save()


## คีย์ของเหตุการณ์ในสัปดาห์: "<planet>:<event idx>:<difficulty>"
static func event_key(spec: Dictionary) -> String:
	return "%s:%d:%s" % [str(spec.get("planet", "")), int((spec.get("primary", {}) as Dictionary).get("idx", 0)),
		str(spec.get("difficulty", ""))]


## ชนะเหตุการณ์นี้ที่ความยากนี้ไปแล้วในสัปดาห์ของ spec ไหม (เหรียญรอบถัดไปเหลือ REPEAT_PCT)
static func is_repeat(spec: Dictionary) -> bool:
	var wk: Dictionary = data()["weeks"].get(str(int(spec.get("week", 0))), {})
	return (wk.get("clears", {}) as Dictionary).has(event_key(spec))


## บันทึกผล (score = CampaignRules.score): เพิ่มเหรียญ คะแนนดีสุด เหตุการณ์ที่ผ่าน ประวัติ แล้วเขียนไฟล์
static func record(spec: Dictionary, score: Dictionary) -> void:
	var d := data()
	d["coins"] = mini(int(d["coins"]) + clampi(int(score.get("coins", 0)), 0, COIN_CAP), COIN_CAP)
	var wkey := str(int(spec.get("week", 0)))
	var weeks: Dictionary = d["weeks"]
	if not weeks.has(wkey):
		weeks[wkey] = {"best": {}, "clears": {}}
	var wk: Dictionary = weeks[wkey]
	var key := event_key(spec)
	wk["best"][key] = maxi(int(wk["best"].get(key, 0)), int(score.get("total", 0)))
	if bool(score.get("win", false)):
		wk["clears"][key] = true
	# เก็บแค่สัปดาห์ล่าสุด KEEP_WEEKS สัปดาห์
	var ks: Array = weeks.keys()
	ks.sort_custom(func(a: Variant, b: Variant) -> bool: return int(a) > int(b))
	for i in range(KEEP_WEEKS, ks.size()):
		weeks.erase(ks[i])
	var h: Array = d["history"]
	h.push_front({"week": int(spec.get("week", 0)), "key": key, "total": int(score.get("total", 0)),
		"coins": int(score.get("coins", 0)), "grade": str(score.get("grade", "-"))})
	while h.size() > HISTORY:
		h.pop_back()
	save()
