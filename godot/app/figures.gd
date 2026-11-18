class_name Figures
extends RefCounted
## ห้องแต่งตัว (PACK_SPEC §10): รายชื่อตัวที่ออกมาเดินบนดาดฟ้า ชุดสีสำเร็จรูป ตัวที่เลือก และช่องบันทึก 3 ช่อง
## ตัวละคร: ไข่ (ของ HallAvatar เอง: make คืน null) · ชุดโมเดลเดิมของโต๊ะรบ (KitWalker) · ตัวละครชุดเสริม (res://packs/figures.json)
## · ตัวในแอปที่มีไฟล์ของตัวเอง (BUILTINS, kind builtin: ทหารราบรุ่นทดลอง)
## เก็บในไฟล์ตั้งค่าของแอป (App.settings_file หมวด "figure") ไม่ใช่ data/*.json (ไม่แตะ DATA_HASH) · ไม่แตะกติกาหรือเครือข่าย

const SECTION := "figure"
const SLOTS := 3
const EGG := "egg"
const DEFAULT_SCHEME := "original"
const PACK_LIST := "res://packs/figures.json"
const DECK_API: PackedStringArray = ["setup", "set_weapon", "play", "set_move", "apply_level"]
const ID_RE := "^[a-z][a-z0-9_]{0,23}$"
## ชุดโมเดลที่เดินได้: ทหารเดินเท้า มีโครง 23 กระดูก ไม่ขี่ ไม่ใช่สัตว์ สูง 1.5–2.3 ม. กองทัพละตัว (ชื่อตามชื่อหน่วยเดิม)
const KITS: Array[Dictionary] = [
	{"kit": "kblade", "th": "อัศวินดาบโล่", "en": "Sword-and-shield knight"},
	{"kit": "warrior", "th": "นักรบฝูง", "en": "Swarm warrior"},
	{"kit": "nob", "th": "ออร์คหัวโจก", "en": "Orc ringleader"},
	{"kit": "elguard", "th": "องครักษ์เอลฟ์", "en": "Elf guard"},
	{"kit": "dewar", "th": "นักรบเอลฟ์มืด", "en": "Dark elf warrior"},
	{"kit": "maa", "th": "อัศวินเกราะ", "en": "Armoured knight"},
	{"kit": "samurai", "th": "ซามูไร", "en": "Samurai"},
	{"kit": "viking", "th": "ไวกิ้ง", "en": "Viking"},
	{"kit": "jackal", "th": "นักรบหัวหมาใน", "en": "Jackal warrior"},
	{"kit": "spartan", "th": "สปาร์ตัน", "en": "Spartan"},
	{"kit": "infantry", "th": "ทหารราบ", "en": "Infantry soldier"},
	{"kit": "rwar", "th": "ทหารโครงเหล็ก", "en": "Steel-frame warrior"},
	{"kit": "tafw", "th": "นักรบปืนพัลส์", "en": "Pulse gun warrior"},
	{"kit": "dabsong", "th": "ทหารดาบสองมือ", "en": "Twin-sword fighter"},
	{"kit": "cxw", "th": "ทหารทรยศ", "en": "Traitor trooper"},
]
## ตัวในแอปที่มีไฟล์ของตัวเอง (assets/figures/<id>/): สคริปต์ตัวละครสัญญาเต็ม (FIGURE_API) ใช้ทั้งดาดฟ้าและห้องทดลอง
## ไม่รับชุดสี · ไม่เป็นตัวเริ่มต้น · ขึ้นในรายชื่อเมื่อมีทั้งสคริปต์และไฟล์ที่ needs ชี้ · body = ร่าง (body_id ของสคริปต์)
const BUILTINS: Array[Dictionary] = [
	{"id": "soldier", "th": "ทหารราบ (ทดลอง)", "en": "Infantry (preview)", "figure": "res://scenes/arena/soldier_figure.gd",
		"needs": "res://assets/figures/soldier/rig.tscn"},
	{"id": "soldier_m2", "th": "ทหารราบ ชาย 2 (ทดลอง)", "en": "Infantry man 2 (preview)", "body": "m2",
		"figure": "res://scenes/arena/soldier_figure.gd", "needs": "res://assets/figures/soldier_m2/rig.tscn"},
	{"id": "soldier_m3", "th": "ทหารราบ ชาย 3 (ทดลอง)", "en": "Infantry man 3 (preview)", "body": "m3",
		"figure": "res://scenes/arena/soldier_figure.gd", "needs": "res://assets/figures/soldier_m3/rig.tscn"},
	{"id": "soldier_f1", "th": "ทหารราบ หญิง 1 (ทดลอง)", "en": "Infantry woman 1 (preview)", "body": "f1",
		"figure": "res://scenes/arena/soldier_figure.gd", "needs": "res://assets/figures/soldier_f1/rig.tscn"},
	{"id": "soldier_f2", "th": "ทหารราบ หญิง 2 (ทดลอง)", "en": "Infantry woman 2 (preview)", "body": "f2",
		"figure": "res://scenes/arena/soldier_figure.gd", "needs": "res://assets/figures/soldier_f2/rig.tscn"},
]
## ชุดสีสำเร็จรูป: primary = เกราะ/ตัว, secondary = ผ้า/ชุดใน (สี sRGB) · original = สีเดิมของตัว (ไม่ทา H10; สีในปุ่มใช้วาดเท่านั้น)
const SCHEMES: Array[Dictionary] = [
	{"id": "original", "th": "สีเดิม", "en": "Original", "p": "4a4540", "s": "c9a23a", "original": true},
	{"id": "blue", "th": "น้ำเงิน", "en": "Blue", "p": "2f5fb0", "s": "d6d8de"},
	{"id": "red", "th": "แดง", "en": "Red", "p": "a8262b", "s": "2a2a2e"},
	{"id": "green", "th": "เขียว", "en": "Green", "p": "2f7a3a", "s": "c9b47a"},
	{"id": "pink", "th": "ชมพู", "en": "Pink", "p": "e07aa8", "s": "f4e6ee"},
	{"id": "black", "th": "ดำ", "en": "Black", "p": "26262b", "s": "8a8e96"},
	{"id": "white", "th": "ขาว", "en": "White", "p": "e8e8ec", "s": "3b5ba0"},
	{"id": "purple", "th": "ม่วง", "en": "Purple", "p": "6a3a9a", "s": "d8c98e"},
	{"id": "gold", "th": "ทอง", "en": "Gold", "p": "c9a23a", "s": "5a2a1e"},
]

## ชุดสีหลายส่วน (H11 apply_palette, PACK_SPEC §10.1): ส่วนที่ตัวละครชุดเสริมระบุสีได้ใน figures.json "palettes"
const PAL_KEYS: PackedStringArray = ["primary", "secondary", "trim", "metal", "lens", "helmet", "arm_l", "accent"]
const PAL_METALLIC: PackedStringArray = ["primary", "helmet", "arm_l"]
const PAL_MAX := 64

## เทสชี้ที่อื่น: ไฟล์เก็บ ("" = App.settings_file), รายชื่อตัวชุดเสริม, pack.json ของอารีน่า (ทางสำรอง deck)
static var store_path := ""
static var pack_list := PACK_LIST
static var pack_manifest := ArenaActors.PACK_MANIFEST


## ทุกตัวที่เลือกได้: [{id, name {th, en}, kind egg|builtin|kit|pack, kit (kind kit), schemes}]
## ชุดเสริมก่อน แล้วไข่ แล้วตัวในแอป แล้วชุดโมเดล
static func list() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for p in _packs():
		out.append({"id": p["id"], "name": p["name"], "kind": "pack", "schemes": p["schemes"]})
	out.append({"id": EGG, "name": {"th": "ตัวไข่", "en": "Egg"}, "kind": "egg", "schemes": false})
	for b in BUILTINS:
		if ResourceLoader.exists(str(b["figure"])) and ResourceLoader.exists(str(b["needs"])):
			out.append({"id": b["id"], "name": {"th": b["th"], "en": b["en"]}, "kind": "builtin", "schemes": false})
	for k in KITS:
		if KitLibrary.has_kit(str(k["kit"])):
			out.append({"id": "kit_" + str(k["kit"]), "name": {"th": k["th"], "en": k["en"]}, "kind": "kit", "kit": k["kit"],
				"schemes": true})
	return out


## รายการของ id ({} ไม่มี)
static func entry(id: String) -> Dictionary:
	for e in list():
		if str(e["id"]) == id:
			return e
	return {}


## ตัวละครเดินบนดาดฟ้าของ id (ไข่หรือไม่มี = null: HallAvatar ใช้ไข่ของตัวเอง) ยังไม่ setup: set_figure ทำต่อ
static func make(id: StringName, level: StringName = &"mid") -> Node3D:
	var e := entry(String(id))
	match str(e.get("kind", "")):
		"kit":
			var w := KitWalker.new()
			w.walk_kit = str(e["kit"])
			w.gfx = String(level)
			return w
		"pack":
			for p in _packs():
				if p["id"] == e["id"]:
					return _instance(str(p["figure"]))
		"builtin":
			return make_builtin(str(e["id"]))
	return null


## ทางไฟล์ตัวละครของตัวชุดเสริม id ("" ไม่มี) · อารีน่าใช้ตัวเดียวกันนี้เป็นตัวผู้เล่น (ArenaActors.player_figure)
static func pack_figure(id: String) -> String:
	for p in _packs():
		if p["id"] == id:
			return str(p["figure"])
	return ""


## ทางไฟล์สคริปต์ของตัวในแอป id ("" ไม่มี) · ดาดฟ้าและอารีน่าใช้สคริปต์เดียวกัน
static func builtin_figure(id: String) -> String:
	for b in BUILTINS:
		if b["id"] == id:
			return str(b["figure"])
	return ""


## ตัวในแอป id ยังไม่ setup: สคริปต์ของรายการ + ร่าง ("body" ของรายการลง body_id) · ดาดฟ้า ห้องแต่งตัว อารีน่าใช้ร่วม · null = ไม่มี
static func make_builtin(id: String) -> Node3D:
	for b in BUILTINS:
		if b["id"] == id:
			var f := _instance(str(b["figure"]))
			if f != null and b.has("body"):
				f.set("body_id", str(b["body"]))
			return f
	return null


## ทาชุดสีบนตัวที่ติดตั้งแล้ว: ชุดสำเร็จรูปหรือชุดของตัวนั้น (figure_id; ว่าง = หาในทุกตัว) ผ่าน apply_entry
static func dress(fig: Node, scheme_id: String, figure_id: String = "") -> void:
	apply_entry(fig, palette(scheme_id, figure_id))


## ทาชุดสี s (รายการจาก palettes): H11 apply_palette(colours) ถ้าตัวนั้นมี ไม่งั้น H10 apply_scheme(primary, secondary)
## สีเดิมหรือตัวที่ไม่มีทั้งสอง = ไม่ทำอะไร
static func apply_entry(fig: Node, s: Dictionary) -> void:
	if fig == null or s.is_empty() or bool(s.get("original", false)):
		return
	if fig.has_method("apply_palette"):
		var c: Dictionary = s.get("colours", {"primary": s["primary"], "secondary": s["secondary"]})
		fig.call("apply_palette", c.duplicate(true))
	elif fig.has_method("apply_scheme"):
		fig.call("apply_scheme", s["primary"], s["secondary"])


## ชุดสีของตัว figure_id: ชุดสำเร็จรูปทั้ง 9 (ทุกตัว) แล้วชุดของตัวชุดเสริมนั้นเอง (figures.json "palettes")
## [{id, name {th, en}, primary, secondary, original, pack, colours {ส่วน: Color, metallic: [ส่วน]}}]
static func palettes(figure_id: String) -> Array[Dictionary]:
	var out := schemes()
	for s in out:
		s["pack"] = false
		s["colours"] = {"primary": s["primary"], "secondary": s["secondary"]}
	for p in _packs():
		if p["id"] == figure_id and bool(p["schemes"]):
			for q: Dictionary in p["palettes"]:
				out.append(q.duplicate(true))
	return out


## ชุดสี id ของตัว figure_id (ว่าง = ชุดสำเร็จรูป แล้วชุดของตัวชุดเสริมทุกตัว) ไม่มี = ชุดเริ่มต้น
static func palette(id: String, figure_id: String = "") -> Dictionary:
	if figure_id != "":
		var all := palettes(figure_id)
		for s in all:
			if s["id"] == id:
				return s
		return all[0]
	for s in schemes():
		if s["id"] == id:
			return _preset_entry(s)
	for p in _packs():
		for q: Dictionary in p["palettes"]:
			if q["id"] == id:
				return q.duplicate(true)
	return _preset_entry(schemes()[0])


static func schemes() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for s in SCHEMES:
		out.append({"id": s["id"], "name": {"th": s["th"], "en": s["en"]}, "primary": Color(str(s["p"])),
			"secondary": Color(str(s["s"])), "original": bool(s.get("original", false))})
	return out


## ชุดสีของ id (ไม่มี = ชุดเริ่มต้น)
static func scheme(id: String) -> Dictionary:
	var all := schemes()
	for s in all:
		if s["id"] == id:
			return s
	return all[0]


## ตัวที่เลือกอยู่ {figure, scheme}: ค่าที่เก็บไว้ถ้ายังมีตัวนั้น ไม่งั้นตัวชุดเสริมตัวแรก หรือไข่
static func selected() -> Dictionary:
	var cfg := _cfg()
	return _valid(str(cfg.get_value(SECTION, "figure", "")), str(cfg.get_value(SECTION, "scheme", "")))


## เลือกตัวและชุดสี (id ที่ไม่มีใช้ค่าเริ่มต้น) เก็บลงไฟล์ แล้วแจ้ง App.figure_changed
static func select(figure_id: String, scheme_id: String) -> void:
	var v := _valid(figure_id, scheme_id)
	var cfg := _cfg()
	cfg.set_value(SECTION, "figure", v["figure"])
	cfg.set_value(SECTION, "scheme", v["scheme"])
	_save(cfg)
	var app := _app()
	if app != null and app.has_signal("figure_changed"):
		app.emit_signal("figure_changed")


## ช่องบันทึก 3 ช่อง: {} ว่าง หรือ {figure, scheme} (ตัวที่หายไปแล้วกลายเป็นช่องว่าง)
static func slots() -> Array:
	var cfg := _cfg()
	var out := []
	for i in SLOTS:
		var v: Variant = cfg.get_value(SECTION, "slot%d" % i, {})
		var d: Dictionary = v if v is Dictionary else {}
		if d.is_empty() or entry(str(d.get("figure", ""))).is_empty():
			out.append({})
		else:
			out.append(_valid(str(d["figure"]), str(d.get("scheme", ""))))
	return out


## บันทึกตัวลงช่อง i (0..2); id ที่ไม่มีไม่บันทึก
static func save_slot(i: int, figure_id: String, scheme_id: String) -> void:
	if i < 0 or i >= SLOTS or entry(figure_id).is_empty():
		return
	var cfg := _cfg()
	cfg.set_value(SECTION, "slot%d" % i, _valid(figure_id, scheme_id))
	_save(cfg)


## ค่าเริ่มต้น: ตัวชุดเสริมตัวแรก ไม่มีก็ไข่
static func default_figure() -> String:
	var p := _packs()
	return str(p[0]["id"]) if not p.is_empty() else EGG


# ---- ภายใน ----

static func _valid(figure_id: String, scheme_id: String) -> Dictionary:
	var f := figure_id if not entry(figure_id).is_empty() else default_figure()
	var s := scheme_id if palettes(f).any(func(x: Dictionary) -> bool: return x["id"] == scheme_id) else DEFAULT_SCHEME
	return {"figure": f, "scheme": s}


static func _preset_entry(s: Dictionary) -> Dictionary:
	var d := s.duplicate()
	d["pack"] = false
	d["colours"] = {"primary": s["primary"], "secondary": s["secondary"]}
	return d


## ชุดสีของตัวชุดเสริม: [{id, name {th, en}, primary "#rrggbb", ส่วนอื่นตาม PAL_KEYS, metallic [ส่วน]}] ไม่เกิน PAL_MAX
## id ซ้ำ/ชนกับชุดสำเร็จรูป/ผิดรูปแบบ ชื่อไม่ครบ สีผิด = ข้ามรายการนั้น (เตือน) · ไม่มี secondary = ใช้สีหลัก (H10)
static func _parse_palettes(v: Variant, fig_id: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if v == null:
		return out
	if not v is Array:
		push_warning("figures: %s palettes is not a list" % fig_id)
		return out
	var re := RegEx.create_from_string(ID_RE)
	var thai := RegEx.create_from_string("[\u0E00-\u0E7F]")
	var seen := {}
	for s in SCHEMES:
		seen[s["id"]] = true
	for q in v:
		if out.size() >= PAL_MAX:
			push_warning("figures: %s has more than %d palettes" % [fig_id, PAL_MAX])
			break
		if not q is Dictionary:
			continue
		var id := str(q.get("id", ""))
		var nm: Variant = q.get("name")
		var why := ""
		var cols := {}
		for k in PAL_KEYS:
			if q.has(k):
				if q[k] is String and Color.html_is_valid(q[k]):
					cols[k] = Color.html(q[k])
				else:
					why = "bad colour " + k
		if re.search(id) == null or seen.has(id):
			why = "bad, repeated or preset id"
		elif not (nm is Dictionary and str(nm.get("th", "")) != "" and str(nm.get("en", "")) != "") or thai.search(str(nm.get("en", ""))) != null:
			why = "name needs th and en (en without Thai)"
		elif why == "" and not cols.has("primary"):
			why = "no primary colour"
		if why != "":
			push_warning("figures: %s palette %s skipped: %s" % [fig_id, id, why])
			continue
		seen[id] = true
		var mt: Variant = q.get("metallic", [])
		cols["metallic"] = Array(mt).map(func(x: Variant) -> String: return str(x)).filter(func(x: String) -> bool: return PAL_METALLIC.has(x)) if mt is Array else []
		out.append({"id": id, "name": {"th": str(nm["th"]), "en": str(nm["en"])}, "primary": cols["primary"],
			"secondary": cols.get("secondary", cols["primary"]), "original": false, "pack": true, "colours": cols})
	return out


static func _path() -> String:
	if store_path != "":
		return store_path
	var app := _app()
	return str(app.get("settings_file")) if app != null else "user://settings.cfg"


static func _cfg() -> ConfigFile:
	var cfg := ConfigFile.new()
	cfg.load(_path())
	return cfg


static func _save(cfg: ConfigFile) -> void:
	var err := cfg.save(_path())
	if err != OK:
		push_warning("figures: cannot write " + _path() + ": " + error_string(err))


static func _app() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	return tree.root.get_node_or_null(^"App") if tree != null else null


## ตัวชุดเสริม: figures.json [{id, name {th, en}, figure, schemes}] ทางไฟล์อยู่ในโฟลเดอร์ของรายชื่อ ไม่มี ".."
## ไม่มีรายชื่อแต่ pack.json มี "deck" = ตัวเดียวชื่อ "pack" (ชุดเสริมก่อนห้องแต่งตัว)
static func _packs() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if not FileAccess.file_exists(pack_list):
		var deck := ArenaActors.resolve("deck", pack_manifest)
		if deck != "":
			out.append({"id": "pack", "name": {"th": "ตัวละครชุดเสริม", "en": "Pack figure"}, "figure": deck, "schemes": false,
				"palettes": [] as Array[Dictionary]})
		return out
	var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(pack_list))
	if not d is Array:
		push_warning("figures: %s is not a list" % pack_list)
		return out
	var dir := pack_list.get_base_dir() + "/"
	var re := RegEx.create_from_string(ID_RE)
	var thai := RegEx.create_from_string("[\u0E00-\u0E7F]")
	var seen := {}
	for v in d:
		if not v is Dictionary:
			continue
		var id := str(v.get("id", ""))
		var nm: Variant = v.get("name")
		var path := str(v.get("figure", ""))
		if not path.begins_with("res://"):
			path = dir + path
		var why := ""
		if re.search(id) == null or seen.has(id) or id == EGG or id.begins_with("kit_") or builtin_figure(id) != "":
			why = "bad or repeated id"
		elif not (nm is Dictionary and str(nm.get("th", "")) != "" and str(nm.get("en", "")) != "") or thai.search(str(nm.get("en", ""))) != null:
			why = "name needs th and en (en without Thai)"
		elif not path.begins_with(dir) or path.contains("..") or not (path.ends_with(".gd") or path.ends_with(".tscn") or path.ends_with(".scn")):
			why = "figure must be a .gd/.tscn/.scn inside " + dir
		elif not ResourceLoader.exists(path):
			why = "no file " + path
		if why != "":
			push_warning("figures: entry %s skipped: %s" % [id, why])
			continue
		seen[id] = true
		out.append({"id": id, "name": {"th": str(nm["th"]), "en": str(nm["en"])}, "figure": path,
			"schemes": bool(v.get("schemes", false)), "palettes": _parse_palettes(v.get("palettes"), id)})
	return out


## .gd → new(), ฉาก → instantiate(); ไม่ใช่ Node3D หรือขาดเมธอดของดาดฟ้า = null (ไข่)
static func _instance(path: String) -> Node3D:
	var res: Resource = load(path)
	var obj: Object = null
	if res is GDScript:
		obj = (res as GDScript).new()
	elif res is PackedScene:
		obj = (res as PackedScene).instantiate()
	var miss := PackedStringArray()
	for m in DECK_API:
		if obj == null or not obj.has_method(m):
			miss.append(m)
	if obj is Node3D and miss.is_empty():
		return obj
	push_warning("figures: %s is not a deck figure (%s)" % [path, ", ".join(miss)])
	if obj is Node:
		(obj as Node).free()
	return null
