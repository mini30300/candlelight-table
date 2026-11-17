extends SceneTree
## ส่งออกท่าของเกม (godot/assets/anim/humanoid.res) เป็น clips.json ให้เครื่องมือปั้นทหาร (tools/soldier/generator)
## รันในโปรเจกต์เกม: <godot> --headless --path godot -s ../tools/soldier/gd/export_clips.gd -- <out.json>
## รูปแบบเดียวกับ clips.json ของ tools/bake_anim.js (CLIPS.md §2) เฉพาะช่องที่เครื่องมือปั้นใช้: joints, clips[ชื่อ]
## {loop, fps, frames, length, q[กระดูก][เฟรม] (x, y, z, w), t[กระดูก][เฟรม] (เมตรของโครง 1.6 ม.), speed, turn,
## contact {L, R}, events, drives, holds} · ค่าคีย์อ่านตรงจากแทร็ก (ไม่ประมาณค่า) จึงตรงกับ clips.json เดิม

const LIB := "res://assets/anim/humanoid.res"
const JOINTS: PackedStringArray = ["pelvis", "spine", "chest", "neck", "head", "shoulderL", "elbowL", "wristL", "handL",
	"shoulderR", "elbowR", "wristR", "handR", "hipL", "kneeL", "ankleL", "toeL", "heelL", "hipR", "kneeR", "ankleR", "toeR", "heelR"]


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty():
		printerr("usage: -s export_clips.gd -- <out.json>")
		quit(2)
		return
	var lib := load(LIB) as AnimationLibrary
	if lib == null:
		printerr("no " + LIB + " (run godot/tools/kits.sh)")
		quit(1)
		return
	var joints: PackedStringArray = lib.get_meta("joints", JOINTS)
	var clips := {}
	for name in lib.get_animation_list():
		clips[String(name)] = _clip(lib.get_animation(name))
	var out := {"format": 1, "fps": 30, "source": str(lib.get_meta("source", "")), "generator": "tools/soldier/gd/export_clips.gd",
		"joints": joints, "clips": clips}
	var f := FileAccess.open(args[0], FileAccess.WRITE)
	f.store_string(JSON.stringify(out))
	f.close()
	print("wrote %d clips to %s" % [clips.size(), args[0]])
	quit(0)


func _clip(a: Animation) -> Dictionary:
	var q := {}
	var t := {}
	var frames := 0
	for i in a.get_track_count():
		var path := String(a.track_get_path(i))
		if not path.begins_with("Skeleton3D:"):
			continue
		var bone := path.substr(11)
		var keys := []
		for k in a.track_get_key_count(i):
			var v: Variant = a.track_get_key_value(i, k)
			if v is Quaternion:
				keys.append([v.x, v.y, v.z, v.w])
			elif v is Vector3:
				keys.append([v.x, v.y, v.z])
		match a.track_get_type(i):
			Animation.TYPE_ROTATION_3D:
				q[bone] = keys
				frames = maxi(frames, keys.size())
			Animation.TYPE_POSITION_3D:
				t[bone] = keys
	var c := {"loop": a.loop_mode != Animation.LOOP_NONE, "fps": 30, "frames": frames, "length": a.length, "q": q, "t": t,
		"speed": float(a.get_meta("speed", 0.0)), "turn": float(a.get_meta("turn", 0.0)), "events": a.get_meta("events", []),
		"drives": Array(a.get_meta("drives", PackedStringArray())), "holds": str(a.get_meta("hold_mode", "all"))}
	if a.has_meta("contact_l") or a.has_meta("contact_r"):
		c["contact"] = {"L": Array(a.get_meta("contact_l", PackedStringArray())), "R": Array(a.get_meta("contact_r", PackedStringArray()))}
	if a.has_meta("travel"):
		c["travel"] = Array(a.get_meta("travel"))
	return c
