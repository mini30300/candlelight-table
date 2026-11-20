extends SceneTree
## ภาพแผ่นสรุปร่างหลากหลาย (ท่าผูก A ไฟบนของเกม = ค่าเริ่มของเชดเดอร์ผิว): FIG_DIR = ทรัพยากร (out/godot/) ;
## POSES = poses.json ของร่างนั้น ; K = ส่วนสูง/1.78 (เลื่อนกล้องหน้าตามความสูง) ; OUT_DIR ; TAG = ชื่อไฟล์นำหน้า
## ภาพ: ทั้งตัวหน้า/ข้าง/หลัง (กล้องเดียวกันทุกร่าง เทียบส่วนสูงได้) หน้าใกล้ 2 มุม + แถว LOD (hi mid lo min) ระยะเกม

const Fig := preload("res://src/gd/vfig.gd")
var OUT := ""
var TAG := ""
var K := 1.0
var HK := 1.0         # ศีรษะร่างหลากหลายขยาย k^-0.6 (กรอบภาพหน้าตามขนาดศีรษะจริง)
var cam: Camera3D
var fig: Node3D
var poses: Dictionary


func _initialize() -> void:
	OUT = OS.get_environment("OUT_DIR")
	TAG = OS.get_environment("TAG")
	K = float(OS.get_environment("K")) if OS.get_environment("K") != "" else 1.0
	HK = pow(K, -0.6)
	DirAccess.make_dir_recursive_absolute(OUT)
	RenderingServer.set_default_clear_color(Color(0.16, 0.17, 0.19))
	poses = JSON.parse_string(FileAccess.get_file_as_string(OS.get_environment("POSES")))
	cam = Camera3D.new()
	cam.fov = 24.0
	get_root().add_child(cam)
	cam.current = true
	fig = Fig.new()
	get_root().add_child(fig)
	fig.setup({"role": &"player", "level": "hi", "seed": 7})
	_run.call_deferred()


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _shot(name: String) -> void:
	await _frames(3)
	get_root().get_texture().get_image().save_png(OUT + "/" + TAG + "_" + name + ".png")


func _frame_view(centre: Vector3, height: float, yaw_deg: float, pitch_deg: float) -> void:
	var d := height / (2.0 * tan(deg_to_rad(cam.fov * 0.5))) * 1.08
	var cp := cos(deg_to_rad(pitch_deg))
	var dir := Vector3(sin(deg_to_rad(yaw_deg)) * cp, sin(deg_to_rad(pitch_deg)), cos(deg_to_rad(yaw_deg)) * cp)
	cam.position = centre + dir * d
	cam.look_at(centre, Vector3.UP)


func _pose(name: String) -> void:
	var p: Dictionary = poses[name]
	var L := {}
	for b in p["local"]:
		var q: Array = p["local"][b]
		L[b] = Quaternion(q[0], q[1], q[2], q[3])
	var pv: Array = p["pelvis"]
	fig.set_pose(L, Vector3(pv[0], pv[1], pv[2]))


func _level(lv: String) -> void:
	fig.apply_level(lv)
	fig.use_mesh(lv)
	fig.level = lv
	fig.helpers_on = true
	fig.correctives_on = true


func _run() -> void:
	var what := OS.get_environment("WHAT")
	if what == "" or what.contains("main"):
		_level("hi")
		_pose("bind")
		await _frames(2)
		_frame_view(Vector3(0, 0.92, 0), 1.98, 0.0, 0.0)
		await _shot("front")
		_frame_view(Vector3(0, 0.92, 0), 1.98, 90.0, 0.0)
		await _shot("side")
		_frame_view(Vector3(0, 0.92, 0), 1.98, 180.0, 0.0)
		await _shot("back")
		_frame_view(Vector3(0, 0.92, 0), 1.98, 30.0, 0.0)
		await _shot("front34")
		var fc := Vector3(0, 1.652 * K, 0.03 * K * HK)
		_frame_view(fc, 0.30 * K * HK, 0.0, 0.0)
		await _shot("face")
		_frame_view(fc, 0.30 * K * HK, 35.0, 0.0)
		await _shot("face34")
		_frame_view(Vector3(0, 1.645 * K, 0.0), 0.32 * K * HK, 90.0, 0.0)
		await _shot("face_side")
		_frame_view(Vector3(0, 1.20 * K, 0.02 * K), 0.70 * K, 20.0, 0.0)
		await _shot("torso")
		_pose("idle")
		await _frames(2)
		_frame_view(Vector3(0, 0.92, 0), 1.98, 25.0, 0.0)
		await _shot("idle")
	# STRIP=<json> (ชุด ใหม่ 0.14): ท่าจากคลิปของทหาร (outfits.strip_poses) มุม 3/4 ทีละท่า -> <TAG>_strip_<ท่า>.png
	if what.contains("strip"):
		var sp: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(OS.get_environment("STRIP")))
		# STRIP_LEVELS="hi lo min": ระดับอื่นได้ชื่อ strip_<ระดับ>_<ท่า>
		var sls: PackedStringArray = OS.get_environment("STRIP_LEVELS").split(" ", false)
		if sls.is_empty():
			sls = PackedStringArray(["hi"])
		for sl in sls:
			_level(sl)
			for nm in sp:
				poses[nm] = sp[nm]
				_pose(nm)
				await _frames(2)
				var pv: Array = sp[nm]["pelvis"]
				_frame_view(Vector3(pv[0], 0.92 if pv[1] > 0.7 * K else 0.55, pv[2]), 2.05, 35.0, 4.0)
				await _shot(("strip_" if sl == "hi" else "strip_%s_" % sl) + nm)
	if what == "" or what.contains("lod"):
		for l in ["hi", "mid", "lo", "min"]:
			_level(l)
			_pose("bind")
			await _frames(2)
			_frame_view(Vector3(0, 0.92, 0), 1.98, 25.0, 0.0)
			await _shot("lod_" + l)
			_frame_view(Vector3(0, 1.55 * K, 0.02), 0.62 * K, 20.0, 0.0)
			await _shot("lodc_" + l)
			_frame_view(Vector3(0, 0.90, 0), 8.5, 25.0, 8.0)
			await _shot("lodg_" + l)
			# หน้าใกล้ต่อระดับ (มือถือใช้ lo/min ทุกระยะ: ตาต้องยังเปิด)
			_frame_view(Vector3(0, 1.652 * K, 0.03 * K * HK), 0.30 * K * HK, 30.0, 0.0)
			await _shot("lodf_" + l)
			_frame_view(Vector3(0, 1.30 * K, 0.02 * K), 0.42 * K, 180.0, 5.0)
			await _shot("lodb_" + l)
	quit()
