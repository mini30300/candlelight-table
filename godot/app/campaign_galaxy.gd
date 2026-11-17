class_name CampaignGalaxy
extends RefCounted
## กาแล็กซีของแคมเปญ (CAMPAIGN_SPEC §2.1–§2.4): ดาว 44 ดวงบนแขนก้นหอย 4 แขน (ตำแหน่งตายตัว) ฝ่ายผู้รุกราน 8 ฝ่าย
## ลักษณะพิเศษ 6 แบบ · เหตุการณ์ประจำสัปดาห์สุ่มจากเลขสัปดาห์อย่างเดียว (Rng ของ core: ทุกเครื่องได้ผลเดียวกัน)
## ชื่อไทยทุกชื่อในไฟล์นี้มีคำแปลใน ui/i18n/campaign.json (โชว์ด้วย I18n.t) · ไม่มีชื่อแฟรนไชส์ (AGENTS ข้อ 1)
## ไม่อ่านนาฬิกาเอง: รับเลขสัปดาห์จาก CampaignWeek · ไม่แตะ data/*.json

const FORMAT := 1
const ARMS := 4
const PER_ARM := 11
## ประเภทภารกิจ (ลำดับนี้ใช้ตอนสุ่ม ห้ามสลับ) — ชื่อและตัวเลขอยู่ใน MissionTypes (scenes/campaign/mission_types.gd)
const TYPES: PackedStringArray = ["purge", "defend", "rescue", "destroy_camp"]
const DIFFICULTIES: PackedStringArray = ["normal", "hard", "veryhard", "catastrophe"]
## โอกาส (ร้อยละ) ของเหตุการณ์ที่ 2 และที่ 3 บนดาวดวงเดียว
const SECOND_EVENT_PCT := 45
const THIRD_EVENT_PCT := 15
## ดาวเด่นประจำสัปดาห์ (เหรียญ × CampaignRules.FEATURED_PCT)
const FEATURED := 3
const STREAM := "campaign_week"

## สภาพดาว: ซากเมือง ป่าดงดิบ ทะเลทราย ทุ่งน้ำแข็ง ภูเขาไฟ หนองพิษ
const BIOMES := {
	"ruin": "ซากเมือง",
	"forest": "ป่าดงดิบ",
	"desert": "ทะเลทราย",
	"ice": "ทุ่งน้ำแข็ง",
	"volcanic": "ภูเขาไฟ",
	"toxic": "หนองพิษ",
}

## ดาว 44 ดวง: แขนละ 11 ดวง เรียงจากในออกนอก (ลำดับและ id ตายตัว ห้ามสลับ: เปลี่ยน = ทุกเครื่องเห็นคนละแบบ)
const PLANETS: Array[Dictionary] = [
	{"id": "p00", "th": "ดาวศิลาแดง", "biome": "desert"},
	{"id": "p01", "th": "ดาวทรายคราม", "biome": "desert"},
	{"id": "p02", "th": "ดาวเถ้าลอย", "biome": "volcanic"},
	{"id": "p03", "th": "ดาวน้ำแข็งเงิน", "biome": "ice"},
	{"id": "p04", "th": "ดาวป่าหมอก", "biome": "forest"},
	{"id": "p05", "th": "ดาวเหล็กร้าง", "biome": "ruin"},
	{"id": "p06", "th": "ดาวบึงอสรพิษ", "biome": "toxic"},
	{"id": "p07", "th": "ดาวภูเขาไฟคู่", "biome": "volcanic"},
	{"id": "p08", "th": "ดาวหอระฆัง", "biome": "ruin"},
	{"id": "p09", "th": "ดาวทุ่งอำพัน", "biome": "desert"},
	{"id": "p10", "th": "ดาวผาลม", "biome": "ice"},
	{"id": "p11", "th": "ดาวหิมะดำ", "biome": "ice"},
	{"id": "p12", "th": "ดาวสวนแก้ว", "biome": "forest"},
	{"id": "p13", "th": "ดาวเมืองจม", "biome": "ruin"},
	{"id": "p14", "th": "ดาวหุบเขาเงา", "biome": "forest"},
	{"id": "p15", "th": "ดาวฝนกรด", "biome": "toxic"},
	{"id": "p16", "th": "ดาวเนินกระดูก", "biome": "desert"},
	{"id": "p17", "th": "ดาวไฟนิรันดร์", "biome": "volcanic"},
	{"id": "p18", "th": "ดาวป่ายักษ์", "biome": "forest"},
	{"id": "p19", "th": "ดาวธารน้ำแข็ง", "biome": "ice"},
	{"id": "p20", "th": "ดาวป้อมโบราณ", "biome": "ruin"},
	{"id": "p21", "th": "ดาวลมทราย", "biome": "desert"},
	{"id": "p22", "th": "ดาวเพลิงใต้พิภพ", "biome": "volcanic"},
	{"id": "p23", "th": "ดาวหนองเขียว", "biome": "toxic"},
	{"id": "p24", "th": "ดาวหอเทียน", "biome": "ruin"},
	{"id": "p25", "th": "ดาวผลึกขาว", "biome": "ice"},
	{"id": "p26", "th": "ดาวป่ากระซิบ", "biome": "forest"},
	{"id": "p27", "th": "ดาวโรงหลอม", "biome": "volcanic"},
	{"id": "p28", "th": "ดาวทะเลทรายแก้ว", "biome": "desert"},
	{"id": "p29", "th": "ดาวหมอกเหลือง", "biome": "toxic"},
	{"id": "p30", "th": "ดาวยอดเขาหิมะ", "biome": "ice"},
	{"id": "p31", "th": "ดาวลาวาเงียบ", "biome": "volcanic"},
	{"id": "p32", "th": "ดาวสะพานหิน", "biome": "ruin"},
	{"id": "p33", "th": "ดาวโอเอซิส", "biome": "desert"},
	{"id": "p34", "th": "ดาวต้นไม้เรืองแสง", "biome": "forest"},
	{"id": "p35", "th": "ดาวเมืองเหล็ก", "biome": "ruin"},
	{"id": "p36", "th": "ดาวหินอัคนี", "biome": "volcanic"},
	{"id": "p37", "th": "ดาวบึงเงา", "biome": "toxic"},
	{"id": "p38", "th": "ดาวน้ำแข็งร้าว", "biome": "ice"},
	{"id": "p39", "th": "ดาวท่าเรือเก่า", "biome": "ruin"},
	{"id": "p40", "th": "ดาวผืนทรายร้อน", "biome": "desert"},
	{"id": "p41", "th": "ดาวป่าเถาวัลย์", "biome": "forest"},
	{"id": "p42", "th": "ดาวควันพิษ", "biome": "toxic"},
	{"id": "p43", "th": "ดาวประภาคาร", "biome": "ice"},
]

## ฝ่ายผู้รุกราน (ตัวละครของแต่ละฝ่ายอยู่ใน MissionRoster) · col = สีบนแผนที่ (sRGB)
const FACTIONS: Array[Dictionary] = [
	{"id": "swarm", "th": "ฝูงเอเลี่ยน", "col": "9a5bd0"},
	{"id": "orcs", "th": "ออร์คเขียว", "col": "5f9e3a"},
	{"id": "cult", "th": "ลัทธิมืด", "col": "b8323a"},
	{"id": "traitors", "th": "อัศวินทรยศ", "col": "7a2430"},
	{"id": "machines", "th": "เครื่องจักรโบราณ", "col": "3fbf9f"},
	{"id": "raiders", "th": "โจรเงา", "col": "5a5fa8"},
	{"id": "daemons", "th": "กองทัพปีศาจ", "col": "e0603a"},
	{"id": "tomb", "th": "กองทัพสุสาน", "col": "c9b06a"},
]

## ลักษณะพิเศษประจำสัปดาห์ของผู้รุกราน (ผลจริงอยู่ใน MissionTypes.MODIFIERS)
const MODIFIERS: Array[Dictionary] = [
	{"id": "armoured", "th": "เกราะหนา"},
	{"id": "frenzied", "th": "คลุ้มคลั่ง"},
	{"id": "gunline", "th": "แนวปืน"},
	{"id": "horde", "th": "ฝูงมหึมา"},
	{"id": "champion", "th": "มีหัวหน้าคุมทัพ"},
	{"id": "ambush", "th": "ซุ่มโจมตี"},
]

static var _cache: Dictionary = {}     # week → ผลสุ่มของสัปดาห์นั้น


## ดาวตาม id ({} ไม่มี) พร้อม arm / slot / index
static func planet(id: String) -> Dictionary:
	for i in PLANETS.size():
		if str(PLANETS[i]["id"]) == id:
			var p: Dictionary = PLANETS[i].duplicate()
			p["index"] = i
			p["arm"] = i / PER_ARM
			p["slot"] = i % PER_ARM
			return p
	return {}


static func faction(id: String) -> Dictionary:
	for f in FACTIONS:
		if str(f["id"]) == id:
			return f
	return {}


static func modifier(id: String) -> Dictionary:
	for m in MODIFIERS:
		if str(m["id"]) == id:
			return m
	return {}


## ตำแหน่งดาวบนแผนที่ (หน่วย: รัศมีกาแล็กซี = 1, กลาง = 0,0) — ภาพอย่างเดียว ไม่มีผลกับกติกา
static func position(index: int) -> Vector2:
	var arm := index / PER_ARM
	var slot := index % PER_ARM
	var ang := float(arm) * TAU / ARMS + float(slot) * 0.42 + 0.35
	var r := 0.18 + float(slot) * 0.074
	# ขยับนิดหน่อยแบบตายตัวจากแฮช ไม่ให้เรียงเป็นเส้นเป๊ะ
	var jx := float(Hash.ihash2(arm, slot, 71) % 1000) / 1000.0 - 0.5
	var jy := float(Hash.ihash2(arm, slot, 113) % 1000) / 1000.0 - 0.5
	return Vector2(cos(ang), sin(ang)) * r + Vector2(jx, jy) * 0.035


## ผลสุ่มของสัปดาห์: {"week", "label", "planets": [{id, faction, modifier, events: [{type, idx}], featured}]}
## (planets เรียงตาม PLANETS) — ฟังก์ชันล้วนของเลขสัปดาห์: ทุกเครื่องได้เท่ากันทุกตัว
static func week(w: int) -> Dictionary:
	if _cache.has(w):
		return _cache[w]
	var rng := Rng.make(STREAM, w)
	# คู่ (ฝ่าย, ลักษณะพิเศษ) 48 คู่ สับแล้วแจกดาวละคู่: ไม่มีดาวสองดวงเจอศัตรูแบบเดียวกันในสัปดาห์เดียว
	var pairs: Array = []
	for f in FACTIONS:
		for m in MODIFIERS:
			pairs.append([str(f["id"]), str(m["id"])])
	for i in range(pairs.size() - 1, 0, -1):
		var j := rng.bounded(i + 1)
		var t: Variant = pairs[i]
		pairs[i] = pairs[j]
		pairs[j] = t
	var out: Array[Dictionary] = []
	for i in PLANETS.size():
		var n := 1
		if rng.bounded(100) < SECOND_EVENT_PCT:
			n += 1
		if rng.bounded(100) < THIRD_EVENT_PCT:
			n += 1
		# สำเนาใหม่ทุกดวง (Array(const) อาจเป็นก้อนเดียวกันทุกครั้ง)
		var left: Array = []
		for t in TYPES:
			left.append(t)
		var events: Array[Dictionary] = []
		for e in n:
			var k := rng.bounded(left.size())
			events.append({"type": str(left[k]), "idx": e})
			left.remove_at(k)
		out.append({"id": str(PLANETS[i]["id"]), "faction": pairs[i][0], "modifier": pairs[i][1], "events": events,
			"featured": false})
	var picked := 0
	while picked < FEATURED:
		var k := rng.bounded(out.size())
		if not out[k]["featured"]:
			out[k]["featured"] = true
			picked += 1
	var res := {"week": w, "label": CampaignWeek.iso_label(w), "planets": out}
	_cache[w] = res
	return res


## ข้อมูลของดาว id ในสัปดาห์ w ({} ไม่มี)
static func planet_week(w: int, id: String) -> Dictionary:
	for p: Dictionary in week(w)["planets"]:
		if str(p["id"]) == id:
			return p
	return {}


## แฮชย่อของทั้งสัปดาห์ (เทสทองคำ: เปลี่ยนกติกาสุ่ม = แฮชเปลี่ยน)
static func digest(w: int) -> String:
	var ints := PackedInt64Array([w])
	for p: Dictionary in week(w)["planets"]:
		ints.append(_find(FACTIONS, str(p["faction"])) * 10 + _find(MODIFIERS, str(p["modifier"])))
		for e: Dictionary in p["events"]:
			ints.append(TYPES.find(str(e["type"])))
		ints.append(1 if p["featured"] else 0)
	return Hash.hex64(Hash.fnv1a64(ints))


## seed ของภารกิจ (RandomNumberGenerator.seed ของฝั่งภารกิจ): สัปดาห์ ดาว เหตุการณ์ ความยาก
static func mission_seed(w: int, planet_id: String, event_idx: int, difficulty: String) -> int:
	return Hash.fnv1a64_str("m:%d:%s:%d:%s" % [w, planet_id, event_idx, difficulty]) & 0x7FFFFFFFFFFFFFFF


## ข้อมูลภารกิจที่ส่งให้หน้าภารกิจ (MissionScreen.start) — รูปแบบใน CAMPAIGN_SPEC §5.4 · {} เมื่อ id ผิด
## เหตุการณ์ที่เลือก = เป้าหมายหลัก · เหตุการณ์อื่นบนดาวเดียวกัน = เป้าหมายรอง (ไม่บังคับ ได้คะแนนเพิ่ม)
static func mission_spec(w: int, planet_id: String, event_idx: int, difficulty: String) -> Dictionary:
	var pw := planet_week(w, planet_id)
	if pw.is_empty() or not DIFFICULTIES.has(difficulty):
		return {}
	var events: Array = pw["events"]
	if event_idx < 0 or event_idx >= events.size():
		return {}
	var secondary: Array[Dictionary] = []
	for e: Dictionary in events:
		if int(e["idx"]) != event_idx:
			secondary.append({"type": str(e["type"]), "idx": int(e["idx"])})
	var p := planet(planet_id)
	return {
		"v": FORMAT,
		"week": w,
		"planet": planet_id,
		"biome": str(p["biome"]),
		"faction": str(pw["faction"]),
		"modifier": str(pw["modifier"]),
		"featured": bool(pw["featured"]),
		"primary": {"type": str(events[event_idx]["type"]), "idx": event_idx},
		"secondary": secondary,
		"difficulty": difficulty,
		"diff": CampaignRules.difficulty(difficulty),
		"seed": mission_seed(w, planet_id, event_idx, difficulty),
	}


static func _find(list: Array[Dictionary], id: String) -> int:
	for i in list.size():
		if str(list[i]["id"]) == id:
			return i
	return -1
