class_name KitLibrary
extends RefCounted
## คลังชุดโมเดล (kits) จาก res://assets/kits: หารายชื่อ อ่าน kits.json เลือกและจัดแถว — ฟังก์ชันล้วน ไม่แตะฉาก ทดสอบง่าย
## (R0-D/R1 เพิ่มการโหลดทีละชุดและ LOD ที่นี่)

const KITS_DIR := "res://assets/kits"
const MANIFEST := KITS_DIR + "/kits.json"
## ชุดที่อยากเห็นก่อนในฉากทดสอบ (ครบทุกแบบ: ทหาร ม้า หุ่น มังกร บอส ไททัน รถถัง)
const PREFERRED: PackedStringArray = ["heavy", "hoplite", "cavalry", "mech", "dragon", "boss",
	"knight", "dmg", "archer", "spartan", "infantry", "tank"]
const DEFAULT_BASE_R := 0.62
const GAP := 0.6


## ชื่อ kit ทั้งหมดในโฟลเดอร์ (เรียงตามชื่อ) — ในแอปที่ export แล้ว DirAccess อาจเห็น "x.glb.import"
## หรือ "x.glb.remap" แทนไฟล์จริง จึงตัดท้ายออกแล้วตัดซ้ำ
static func list_kits(dir_path: String = KITS_DIR) -> PackedStringArray:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return PackedStringArray()
	return names_from_files(dir.get_files())


static func names_from_files(files: PackedStringArray) -> PackedStringArray:
	var seen := {}
	for f in files:
		var name := f
		if name.ends_with(".import") or name.ends_with(".remap"):
			name = name.get_basename()
		if name.get_extension() != "glb":
			continue
		seen[name.get_basename()] = true
	var out := PackedStringArray(seen.keys())
	out.sort()
	return out


## เลือกไม่เกิน max_count ตัว: เอาตามลำดับ preferred ที่มีจริงก่อน แล้วเติมด้วยตัวอื่นตามชื่อ
static func pick(available: PackedStringArray, preferred: PackedStringArray = PREFERRED, max_count: int = 12) -> PackedStringArray:
	var out := PackedStringArray()
	for name in preferred:
		if out.size() >= max_count:
			break
		if available.has(name) and not out.has(name):
			out.append(name)
	for name in available:
		if out.size() >= max_count:
			break
		if not out.has(name):
			out.append(name)
	return out


## อ่าน kits.json (ส่วน "kits"); ไม่มีไฟล์ก็คืน {} — รัศมีฐานใช้เว้นระยะในแถว
static func load_manifest(path: String = MANIFEST) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var text := FileAccess.get_file_as_string(path)
	var data: Variant = JSON.parse_string(text)
	if data is Dictionary and data.has("kits") and data["kits"] is Dictionary:
		return data["kits"]
	return {}


static func base_radius(manifest: Dictionary, name: String) -> float:
	var kit: Variant = manifest.get(name)
	if kit is Dictionary and kit.has("baseR"):
		return float(kit["baseR"])
	return DEFAULT_BASE_R


## ที่อยู่ไฟล์ของชุด (โหลดด้วย load(); ในแอปที่ export แล้วก็ใช้ชื่อเดิม)
static func kit_path(name: String) -> String:
	return KITS_DIR + "/" + name + ".glb"


static func has_kit(name: String) -> bool:
	return name != "" and ResourceLoader.exists(kit_path(name))


## กล่องขอบเขตของเมช (เมตร) จาก bbox ใน kits.json; ไม่มีก็คืน AABB ว่าง (size = 0)
static func bounds(manifest: Dictionary, name: String) -> AABB:
	var kit: Variant = manifest.get(name)
	if not (kit is Dictionary) or not (kit.get("bbox") is Array) or (kit["bbox"] as Array).size() != 2:
		return AABB()
	var lo: Variant = kit["bbox"][0]
	var hi: Variant = kit["bbox"][1]
	if not (lo is Array and hi is Array and (lo as Array).size() == 3 and (hi as Array).size() == 3):
		return AABB()
	var a := Vector3(float(lo[0]), float(lo[1]), float(lo[2]))
	var b := Vector3(float(hi[0]), float(hi[1]), float(hi[2]))
	return AABB(a, b - a).abs()


## สีหลักสองสีของชุด (ป้ายสีบนการ์ดหน่วย): ชิ้น plate/trim ก่อน แล้วชิ้นที่ทาสีได้ตัวแรก ๆ ตามลำดับใน kits.json
static func kit_colours(manifest: Dictionary, name: String) -> Array[Color]:
	var out: Array[Color] = []
	var kit: Variant = manifest.get(name)
	if not (kit is Dictionary) or not (kit.get("materials") is Array):
		return out
	var mats: Array = kit["materials"]
	var order: Array = []
	for want in ["plate", "trim"]:
		for m in mats:
			if m is Dictionary and str(m.get("key", "")) == want:
				order.append(m)
	for m in mats:
		if m is Dictionary and bool(m.get("tint", false)) and not order.has(m):
			order.append(m)
	for m in mats:
		if m is Dictionary and not order.has(m):
			order.append(m)
	for m in order:
		var rgb: Variant = (m as Dictionary).get("rgb")
		if rgb is Array and (rgb as Array).size() == 3:
			out.append(Color8(int(rgb[0]), int(rgb[1]), int(rgb[2])))
		if out.size() == 2:
			break
	return out


## ตำแหน่ง x ของแต่ละตัวในแถว (กึ่งกลางแถวอยู่ที่ 0) จากรัศมีฐาน
static func row_positions(radii: PackedFloat32Array, gap: float = GAP) -> PackedFloat32Array:
	var xs := PackedFloat32Array()
	var x := 0.0
	for i in radii.size():
		if i > 0:
			x += radii[i - 1] + gap + radii[i]
		xs.append(x)
	var half := x * 0.5
	for i in xs.size():
		xs[i] -= half
	return xs
