extends Node3D
## ฉากทดสอบ: โต๊ะ 40×30 ม. กับแถวฟิกเกอร์จาก res://assets/kits (ไม่มีก็วางกล่องสีแทน)

const MAX_FIGURES := 12
const STAND_INS := 8
const STAND_IN_GAP := 2.5

@onready var figures: Node3D = $Figures
@onready var hud: CanvasLayer = $HUD

var figure_count := 0
var from_kits := false


func _ready() -> void:
	var names := KitLibrary.pick(KitLibrary.list_kits(), KitLibrary.PREFERRED, MAX_FIGURES)
	if names.is_empty() or not _place_kits(names):
		_place_stand_ins()
	hud.set_figures(figure_count, from_kits)


## วางชุดโมเดลเรียงแถวตามรัศมีฐานใน kits.json; exporter อบ scale ลงในเมชแล้ว จึงวางที่ scale 1
func _place_kits(names: PackedStringArray) -> bool:
	var manifest := KitLibrary.load_manifest()
	var scenes: Array[PackedScene] = []
	var radii := PackedFloat32Array()
	for name in names:
		var res: Resource = load(KitLibrary.KITS_DIR + "/" + name + ".glb")
		if res is PackedScene:
			scenes.append(res)
			radii.append(KitLibrary.base_radius(manifest, name))
		else:
			push_warning("kit not loadable: " + name)
	if scenes.is_empty():
		return false
	var xs := KitLibrary.row_positions(radii)
	for i in scenes.size():
		var inst := scenes[i].instantiate()
		if inst is Node3D:
			(inst as Node3D).position = Vector3(xs[i], 0.0, 0.0)
		figures.add_child(inst)
	figure_count = scenes.size()
	from_kits = true
	return true


## ไม่มีชุดโมเดล: กล่องสี 8 ใบขนาดคน
func _place_stand_ins() -> void:
	var half := (STAND_INS - 1) * STAND_IN_GAP * 0.5
	for i in STAND_INS:
		var mesh := BoxMesh.new()
		mesh.size = Vector3(0.7, 1.75, 0.7)
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color.from_hsv(float(i) / STAND_INS, 0.65, 0.85)
		mesh.material = mat
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		mi.position = Vector3(i * STAND_IN_GAP - half, mesh.size.y * 0.5, 0.0)
		figures.add_child(mi)
	figure_count = STAND_INS
	from_kits = false
