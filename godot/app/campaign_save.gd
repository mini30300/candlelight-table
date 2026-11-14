class_name CampaignSave
extends RefCounted
## ที่เก็บของแคมเปญในเครื่อง (CAMPAIGN_SPEC §2.8): เหรียญ ความยากล่าสุด คะแนนดีสุดและเหตุการณ์ที่ผ่านแล้วของสัปดาห์
## ไฟล์ user://campaign.json (มีเลขรุ่น "v") · ไม่ใช่ data/*.json (DATA_HASH ไม่เปลี่ยน) · ไม่ใช่ settings.cfg
## รอบหน้าเหรียญย้ายไปเซิร์ฟเวอร์ (กันโกง): ไฟล์นี้จะเหลือแค่ความยากล่าสุดกับประวัติ
## เทสชี้ไฟล์อื่นด้วย CampaignSave.path · ไฟล์เสีย/รุ่นไม่รู้จัก = เริ่มใหม่ (คำเตือน ไม่ล่ม)
## TODO(track A): ตรวจค่าที่อ่านมาให้ครบ (ชนิด ช่วง) และเทสไฟล์เสียทุกแบบ

const PATH := "user://campaign.json"
const VERSION := 1
const HISTORY := 20              # เก็บผลล่าสุดกี่รายการ
const KEEP_WEEKS := 2            # เก็บ best/clears ของสัปดาห์นี้กับสัปดาห์ก่อน

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
		push_warning("campaign save: %s is unreadable or of another version; starting fresh" % path)
		return
	for k in ["last_difficulty", "weeks", "history"]:
		if (d as Dictionary).has(k) and typeof(d[k]) == typeof(_data[k]):
			_data[k] = d[k]
	# JSON อ่านเลขเป็น float
	var c: Variant = (d as Dictionary).get("coins", 0)
	_data["coins"] = maxi(int(c), 0) if c is float or c is int else 0


static func save() -> bool:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_warning("campaign save: cannot write %s" % path)
		return false
	f.store_string(JSON.stringify(data(), "  "))
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
	d["coins"] = int(d["coins"]) + maxi(int(score.get("coins", 0)), 0)
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
