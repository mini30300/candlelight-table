extends SceneTree
## ประกอบชั้นในของทหาร (บาดแผล: เนื้อ/กระดูก) เป็นทรัพยากร Godot (รันแบบ headless หลัง assemble.gd)
## อ่าน out/data/inner_bone.bin + inner_flesh.bin (จาก src/py/inner_layers.py) -> out/godot/inner_bone.res + inner_flesh.res
## 1 พื้นผิวต่อชั้น ผูกกับ skin.res ชุดเดียวกับผิว (bind ตามชื่อ) ; วัสดุ soldier_inner.gdshader ฝังในเมช (ค่าต่างกันต่อชั้น)

const DATA := "res://out/data/"
const OUT := "res://out/godot/"
const SHADER := "res://src/gd/soldier_inner.gdshader"
const ASM := preload("res://src/gd/assemble.gd")     # read_bin / v3
## ค่าของวัสดุแต่ละชั้น (uniform ของ soldier_inner.gdshader)
const LAYER := {
	"flesh": {"base_colour": Vector3(0.50, 0.07, 0.06), "inner_colour": Vector3(0.13, 0.015, 0.012), "core": 0.55,
		"keep": 1.2, "fat_band": 1.0, "wet": 0.5},
	"bone": {"base_colour": Vector3(0.90, 0.86, 0.76), "inner_colour": Vector3(0.42, 0.07, 0.05), "core": 0.0,
		"keep": 1.0, "fat_band": 0.0, "wet": 0.12},
}


func _initialize() -> void:
	var sh := load(SHADER) as Shader
	if sh == null:
		push_error("no shader at " + SHADER)
		quit(1)
		return
	var report := {}
	for lv in ["bone", "flesh"]:
		var path := DATA + "inner_%s.bin" % lv
		if not FileAccess.file_exists(path):
			push_error("missing " + path + " (run src/py/inner_layers.py)")
			quit(1)
			return
		var d: Dictionary = ASM.read_bin(path)
		var arr := []
		arr.resize(Mesh.ARRAY_MAX)
		arr[Mesh.ARRAY_VERTEX] = ASM.v3(d["pos"])
		arr[Mesh.ARRAY_NORMAL] = ASM.v3(d["nrm"])
		arr[Mesh.ARRAY_BONES] = d["bones"]
		arr[Mesh.ARRAY_WEIGHTS] = d["weights"]
		arr[Mesh.ARRAY_INDEX] = d["idx"]
		var am := ArrayMesh.new()
		am.resource_name = "soldier_inner_" + lv
		am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		var mat := ShaderMaterial.new()
		mat.shader = sh
		mat.resource_name = "soldier_inner_" + lv
		mat.render_priority = -1      # วาดหลังผิว: ส่วนที่ผิวบังถูกตัดทิ้งก่อนคิดสี
		for k in LAYER[lv]:
			mat.set_shader_parameter(k, LAYER[lv][k])
		am.surface_set_material(0, mat)
		var outp := OUT + "inner_%s.res" % lv
		ResourceSaver.save(am, outp, ResourceSaver.FLAG_COMPRESS)
		var meta: Dictionary = d["meta"]
		report[lv] = {"verts": int(meta["verts"]), "tris": int(meta["tris"]), "bytes": FileAccess.get_file_as_bytes(outp).size()}
		print("inner_%s: %d verts %d tris %d bytes" % [lv, meta["verts"], meta["tris"], report[lv]["bytes"]])
	var fo := FileAccess.open(DATA + "godot_inner.json", FileAccess.WRITE)
	fo.store_string(JSON.stringify(report, " "))
	quit()
