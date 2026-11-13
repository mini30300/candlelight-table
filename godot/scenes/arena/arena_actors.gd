class_name ArenaActors
extends RefCounted
## ตัวโหลดตัวละครของอารีน่า (ARENA_SPEC §9.2): ตัวผู้เล่นกับศัตรูเปลี่ยนได้ผ่านชุดเสริม (pack) ที่ไม่อยู่ใน repo นี้
## ชุดเสริม = res://packs/arena/pack.json {"format": 1, "id", "player", "enemy", "enemy_name": {"th", "en"}}
## ทางไฟล์ต้องอยู่ในโฟลเดอร์ของ pack.json เอง · ตัวละครที่โหลดไม่ได้หรือขาดเมธอดของ FIGURE_API ใช้ตัวเริ่มต้นแทน (เตือนครั้งเดียว)

const PACK_MANIFEST := "res://packs/arena/pack.json"
const DEFAULT := {"player": "res://scenes/arena/egg_gunner.gd", "enemy": "res://scenes/arena/kit_beast.gd"}
const FIGURE_API: PackedStringArray = ["setup", "metrics", "clip_names", "play", "set_move", "set_aim", "set_weapon", "set_flash",
	"set_telegraph", "muzzle", "anchor", "apply_level"]
const FORMAT := 1


## ทางไฟล์ตัวละครของ role ("player" / "enemy"): ของชุดเสริมเมื่อถูกต้อง ไม่งั้นตัวเริ่มต้น
static func resolve(role: String, manifest: String = PACK_MANIFEST) -> String:
	var fallback := str(DEFAULT.get(role, ""))
	var m := _manifest(manifest)
	if m.is_empty() or not m.has(role):
		return fallback
	var path := _abs(str(m[role]), manifest)
	if path == "":
		push_warning("arena pack: %s path leaves the pack folder: %s" % [role, str(m[role])])
		return fallback
	if not ResourceLoader.exists(path):
		push_warning("arena pack: no %s figure at %s" % [role, path])
		return fallback
	return path


## สร้างตัวละครของ role: .tscn → instantiate(), .gd → new(); ตรวจ FIGURE_API แล้วถอยไปตัวเริ่มต้นถ้าขาด
static func make_figure(role: String, manifest: String = PACK_MANIFEST) -> Node3D:
	var fallback := str(DEFAULT.get(role, ""))
	var path := resolve(role, manifest)
	var fig := _instance(path)
	if path != fallback:
		if fig == null:
			push_warning("arena pack: the %s figure at %s did not load" % [role, path])
		else:
			var miss := missing_api(fig)
			if not miss.is_empty():
				push_warning("arena pack: the %s figure at %s lacks %s" % [role, path, ", ".join(miss)])
				fig.free()
				fig = null
		if fig == null:
			fig = _instance(fallback)
	return fig


## ชื่อเมธอดของ FIGURE_API ที่ fig ไม่มี
static func missing_api(fig: Object) -> PackedStringArray:
	var out := PackedStringArray()
	for m in FIGURE_API:
		if fig == null or not fig.has_method(m):
			out.append(m)
	return out


## ชื่อศัตรูจากชุดเสริม {"th", "en"} หรือ {} เมื่อไม่มี
static func enemy_name(manifest: String = PACK_MANIFEST) -> Dictionary:
	var m := _manifest(manifest)
	var n: Variant = m.get("enemy_name")
	if n is Dictionary and str((n as Dictionary).get("th", "")) != "" and str((n as Dictionary).get("en", "")) != "":
		return {"th": str(n["th"]), "en": str(n["en"])}
	return {}


## id ของชุดเสริม ("" ไม่มี)
static func pack_id(manifest: String = PACK_MANIFEST) -> String:
	return str(_manifest(manifest).get("id", ""))


static func _manifest(manifest: String) -> Dictionary:
	if manifest == "" or not FileAccess.file_exists(manifest):
		return {}
	var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(manifest))
	if not d is Dictionary or int((d as Dictionary).get("format", 0)) != FORMAT:
		push_warning("arena pack: %s is not a format %d manifest" % [manifest, FORMAT])
		return {}
	return d


## ทางไฟล์เต็มของ p (เทียบโฟลเดอร์ของ manifest เมื่อไม่ขึ้นต้นด้วย res://) · ออกนอกโฟลเดอร์คืน ""
static func _abs(p: String, manifest: String) -> String:
	var dir := manifest.get_base_dir()
	var full := p if p.begins_with("res://") else dir.path_join(p)
	full = full.simplify_path()
	if not full.begins_with(dir + "/") or full.contains(".."):
		return ""
	return full


static func _instance(path: String) -> Node3D:
	if path == "" or not ResourceLoader.exists(path):
		return null
	var res: Resource = load(path)
	var obj: Object = null
	if res is PackedScene:
		obj = (res as PackedScene).instantiate()
	elif res is Script and (res as Script).can_instantiate():
		obj = (res as Script).new()
	if obj is Node3D:
		return obj
	if obj is Node:
		(obj as Node).free()
	return null
