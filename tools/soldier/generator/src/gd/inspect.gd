extends SceneTree
# ตรวจโครง infantry.glb และคลิปใน humanoid.res (อ่านอย่างเดียว จากสำเนาใน ref/)
func _initialize() -> void:
	var doc := GLTFDocument.new()
	var st := GLTFState.new()
	var err := doc.append_from_file(ProjectSettings.globalize_path("res://ref/infantry.glb"), st)
	print("gltf err ", err)
	var scn := doc.generate_scene(st)
	var sk: Skeleton3D = scn.find_child("*", true, false) as Skeleton3D
	for n in scn.find_children("*", "Skeleton3D", true, false):
		sk = n
	print("skeleton ", sk, " bones ", sk.get_bone_count())
	for i in sk.get_bone_count():
		var r := sk.get_bone_rest(i)
		print("%2d %-10s parent %2d pos %s rot %s  grest %s" % [i, sk.get_bone_name(i), sk.get_bone_parent(i), r.origin, r.basis.get_rotation_quaternion(), sk.get_bone_global_rest(i).origin])
	for n in scn.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		print("mesh ", mi.name, " aabb ", mi.get_aabb(), " skin binds ", mi.skin.get_bind_count() if mi.skin else -1)
	var lib := load("res://ref/humanoid.res") as AnimationLibrary
	var names := lib.get_animation_list()
	print("clips ", names.size())
	for nm in names:
		var a := lib.get_animation(nm)
		var pos := []
		for t in a.get_track_count():
			if a.track_get_type(t) == Animation.TYPE_POSITION_3D:
				pos.append(str(a.track_get_path(t)).get_slice(":", 1))
		print("%-16s len %.3f loop %d speed %s tracks %d pos %s events %s drives %s" % [nm, a.length, a.loop_mode, a.get_meta("speed", "-"), a.get_track_count(), pos, a.get_meta("events", []), a.get_meta("drives", PackedStringArray()).size()])
	print("lib meta ", lib.get_meta_list())
	quit()
