extends SceneTree
## Budget gate for a pack room (PACK_SPEC §9, the deck's limits of LOBBY_SPEC §2.6): opens the first valid room under
## --root in a PackRoomScreen and, at each graphics level, measures draw calls / primitives (RenderingServer, 4 frames,
## low-processor mode off, as test_hall.gd) in the spawn overview, in front of every station, and in the phone worst
## view (20:9, touch on, first-entry hint showing, at the station farthest from spawn, looking back at the far corner).
## One line per view, then PASS or FAIL. PNGs of the overview and the phone view go to --png (default $TEST_OUT).
## test_pack_room.gd calls measure() on its own screen; the personal build runs this file as its budget gate:
##   xvfb-run -a -s "-screen 0 1280x720x24" <godot> --path godot --rendering-driver opengl3 --resolution 1280x720 \
##     --audio-driver Dummy -s res://tests/render/room_budget.gd -- --root res://packs/rooms --out <file>
## Not picked up by run.sh on its own (its name does not start with test_).

const SCREEN := "res://ui/screens/pack_room_screen.tscn"
const BUDGET := {"hi": [140, 250000], "mid": [100, 150000], "lo": [60, 80000], "min": [40, 40000]}
const LEVELS: PackedStringArray = ["hi", "mid", "lo", "min"]
const PHONE := Vector2i(1600, 720)

var _done := false


func _initialize() -> void:
	_run.call_deferred()


func _process(_delta: float) -> bool:
	return _done


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var room_root := _arg(args, "--root", PackRooms.ROOT)
	var out := _arg(args, "--out", "")
	var png := _arg(args, "--png", OS.get_environment("TEST_OUT"))
	var app := root.get_node_or_null(^"App")
	if app != null:
		app.set("settings_file", "user://room_budget.cfg")
	Features.set_flag(&"online", true)
	var rooms := PackRooms.list(room_root)
	var lines: Array[String] = []
	var ok := false
	if rooms.is_empty():
		lines.append("FAIL  no valid room under " + room_root)
	else:
		var screen: Node = app.call("push", load(SCREEN)) if app != null else null
		if screen == null or not screen.call("open", rooms[0], ""):
			lines.append("FAIL  the room %s does not open" % str(rooms[0]["id"]))
		else:
			await process_frame
			var res: Dictionary = await measure(self, screen, png)
			lines.append_array(res["lines"])
			ok = bool(res["ok"])
	lines.append("PASS" if ok else "FAIL")
	for l in lines:
		print(l)
	if out != "":
		var f := FileAccess.open(out, FileAccess.WRITE)
		if f != null:
			f.store_string("\n".join(lines) + "\n")
	_done = true
	quit(0 if ok else 1)


## Measures every view of an open PackRoomScreen at every level; returns {"lines": [...], "ok": bool, "worst": {level: [d, p]}}.
## Leaves the screen at mid, touch off, the original window size, standing at spawn.
static func measure(tree: SceneTree, screen: Node, png_dir: String = "") -> Dictionary:
	var app := tree.root.get_node(^"App")
	var world: Node3D = screen.get("world")
	var lay: RoomLayout = world.get("layout")
	var rig: Node3D = world.get("camera_rig")
	var hint := screen.get_node("%Hint") as CanvasItem
	var lines: Array[String] = []
	var worst := {}
	var ok := true
	var size0 := tree.root.size
	var gfx0 := str(app.get("gfx"))
	var touch0 := str(app.get("touch"))
	# สถานีที่ไกลจุดเกิดที่สุด และมุมห้องฝั่งตรงข้าม (มุมมองแย่สุดบนมือถือ)
	var far_id := ""
	var far_d := -1.0
	for id in lay.ids:
		var f: Vector2 = lay.stations[id]["front"]
		var d := f.distance_to(Vector2(lay.spawn.x, lay.spawn.z))
		if d > far_d:
			far_d = d
			far_id = id
	var ff: Vector2 = lay.stations[far_id]["front"]
	var corner := Vector2(-signf(ff.x) * lay.half.x if ff.x != 0.0 else lay.half.x, -signf(ff.y) * lay.half.y if ff.y != 0.0 else lay.half.y)
	var to_c := corner - ff
	var corner_yaw := atan2(-to_c.x, -to_c.y)
	for level in LEVELS:
		app.call("set_gfx", level)
		screen.call("refresh")
		var lw := [0, 0]
		var views: Array = [["overview", Vector3(lay.spawn.x, 0.0, lay.spawn.z), lay.spawn_yaw, -0.3, 9.0, false]]
		for id in lay.ids:
			var f: Vector2 = lay.stations[id]["front"]
			var c: Vector2 = lay.stations[id]["c"]
			var dv := c - f
			views.append(["at " + id, Vector3(f.x, 0.0, f.y), atan2(-dv.x, -dv.y), -0.35, 6.5, false])
		views.append(["phone worst", Vector3(ff.x, 0.0, ff.y), corner_yaw, -0.3, 9.0, true])
		for v: Array in views:
			if bool(v[5]):
				app.call("set_touch", "on")
				screen.call("refresh")
				tree.root.size = PHONE
				hint.visible = true
				hint.modulate = Color.WHITE
				for _i in 3:
					await tree.process_frame
			world.call("place_avatar", v[1], float(v[2]) + PI)
			rig.call("set_view", float(v[2]), float(v[3]), float(v[4]))
			var m: Array = await _measure(tree)
			var b: Array = BUDGET[level]
			var pass_ := int(m[0]) <= int(b[0]) and int(m[1]) <= int(b[1])
			ok = ok and pass_
			lw = [maxi(lw[0], int(m[0])), maxi(lw[1], int(m[1]))]
			lines.append("%s  %-4s %-16s draw calls %4d  primitives %7d  (limit %d / %d)" % ["ok  " if pass_ else "FAIL",
				level, str(v[0]), int(m[0]), int(m[1]), int(b[0]), int(b[1])])
			if png_dir != "" and (str(v[0]) == "overview" or bool(v[5])):
				_save(tree, png_dir, "pack_room_%s_%s.png" % [str(v[0]).replace(" ", "_"), level])
			if bool(v[5]):
				app.call("set_touch", "off")
				tree.root.size = size0
				screen.call("refresh")
				for _i in 3:
					await tree.process_frame
		worst[level] = lw
	app.call("set_gfx", gfx0 if gfx0 != "" else "mid")
	app.call("set_touch", touch0 if touch0 != "" else "auto")
	screen.call("refresh")
	world.call("place_avatar", Vector3(lay.spawn.x, 0.0, lay.spawn.z), lay.spawn_yaw + PI)
	rig.call("set_view", lay.spawn_yaw, -0.45, 6.5)
	return {"lines": lines, "ok": ok, "worst": worst}


static func _measure(tree: SceneTree) -> Array:
	var idle := OS.low_processor_usage_mode
	OS.low_processor_usage_mode = false
	for _i in 4:
		await tree.process_frame
	var draws := 0
	var prims := 0
	for _i in 4:
		await tree.process_frame
		draws = maxi(draws, RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME))
		prims = maxi(prims, RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME))
	OS.low_processor_usage_mode = idle
	return [draws, prims]


static func _save(tree: SceneTree, dir: String, name: String) -> void:
	var img := tree.root.get_viewport().get_texture().get_image()
	DirAccess.make_dir_recursive_absolute(dir)
	img.save_png(dir.path_join(name))


static func _arg(args: PackedStringArray, key: String, fallback: String) -> String:
	var i := args.find(key)
	return args[i + 1] if i >= 0 and i + 1 < args.size() else fallback
