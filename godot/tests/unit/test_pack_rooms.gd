extends "res://tests/testing.gd"
## Pack rooms (scenes/hall/pack_rooms.gd, room_layout.gd; PACK_SPEC §9): the public hook a personal pack uses to put a
## walk-in room behind the deck's docking airlock. No res://packs/rooms in this repo -> no room, the deck stays as it is;
## the neutral fixture room (tests/fixtures/pack_rooms/test_room) is listed and is the airlock's room only with the
## online flag on; every broken fixture (tests/fixtures/pack_rooms_bad/<case>) is refused with its own error line and
## never crashes; RoomLayout builds the shell, the station footprints and the script's crate, answers station_at /
## in_walk_in and stops camera rays at a wall and in front of the crate; the pose band (+30 m) round-trips and stays
## inside the ±50 m schema; the stable kit a room script may use exists with its arities; the airlock return spot.

const FIX := "res://tests/fixtures/pack_rooms"
const BAD := "res://tests/fixtures/pack_rooms_bad"
const ROOM := "res://tests/fixtures/pack_rooms/test_room"
## each broken case and a piece of the error line it must give
const BAD_CASES := {
	"bad_format": "format must be 1",
	"id_mismatch": "is not the folder name",
	"unknown_door": "door must be one of",
	"escape": "relative .gd path",
	"no_en": "title needs a non-empty en",
	"thai_en": "title en has Thai letters",
	"too_wide": "half must be",
	"no_back": "exactly one station must have action back (found 0)",
	"two_back": "exactly one station must have action back (found 2)",
	"bad_action": "action must be one of",
	"spawn_blocked": "spawn (",
	"half_api": "lacks apply_level, blockers",
	"missing_script": "does not exist",
}


func setup() -> void:
	PackRooms.reset()
	Features.reset()


func _room_data() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(ROOM + "/room.json"))


func test_no_rooms_in_the_repo() -> void:
	assert_false(DirAccess.dir_exists_absolute(PackRooms.ROOT), "no res://packs/rooms in this repo (git-ignored packs/)")
	assert_eq(PackRooms.list(), [] as Array[Dictionary], "list() is empty")
	Features.set_flag(&"online", true)
	assert_eq(PackRooms.for_door("online"), {}, "no room for the airlock with online on")
	Features.set_flag(&"online", false)
	assert_eq(PackRooms.for_door("online"), {}, "and with online off")
	Features.reset()


func test_fixture_room_is_listed() -> void:
	var rooms := PackRooms.list(FIX)
	assert_eq(rooms.size(), 1, "the fixture root holds one valid room")
	if rooms.is_empty():
		return
	assert_eq(str(rooms[0]["id"]), "test_room", "it is test_room")
	assert_eq(str(rooms[0]["dir"]), ROOM, "with its folder")
	Features.set_flag(&"online", false)
	assert_eq(PackRooms.for_door("online", FIX), {}, "online off: the airlock has no room")
	Features.set_flag(&"online", true)
	assert_eq(str(PackRooms.for_door("online", FIX).get("id", "")), "test_room", "online on: the airlock's room is test_room")
	assert_eq(PackRooms.for_door("arena", FIX), {}, "no other door takes a room in v1")
	assert_eq(PackRooms.online_station(rooms[0]), "cards_box", "the play-with-friends card sits at cards_box")
	PackRooms.test_root = FIX
	assert_eq(PackRooms.root(), FIX, "tests can point the root at the fixture")
	Features.reset()


func test_broken_rooms_are_refused() -> void:
	assert_eq(PackRooms.list(BAD), [] as Array[Dictionary], "no broken room is listed")
	var d := DirAccess.open(BAD)
	var found := Array(d.get_directories()) if d != null else []
	found.sort()
	var want := BAD_CASES.keys()
	want.sort()
	assert_eq(found, want, "one folder per broken case")
	for c: String in BAD_CASES:
		var dir := BAD + "/" + c
		var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(dir + "/room.json"))
		var errs := PackRooms.validate(data, dir)
		var hit := false
		for e in errs:
			if e.contains(str(BAD_CASES[c])):
				hit = true
		assert_true(hit, "%s is refused with its own line (%s)" % [c, BAD_CASES[c]], errs)
	assert_eq(PackRooms.validate(null, BAD + "/x"), PackedStringArray(["room.json is not a JSON object"]), "not an object")
	var half: Node3D = (load(BAD + "/half_api/room.gd") as Script).new()
	assert_eq(PackRooms.missing_api(half), PackedStringArray(["apply_level", "blockers"]), "half_api lacks two methods")
	half.free()
	assert_eq(PackRooms.validate(_room_data(), ROOM), PackedStringArray(), "the fixture room itself is valid")


func test_room_layout() -> void:
	var node: Node3D = (load(ROOM + "/room.gd") as Script).new()
	var extra: Array = node.call("blockers")
	node.free()
	var lay := RoomLayout.new(_room_data(), extra)
	var tags := {}
	for b in lay.blockers():
		tags[str(b["tag"])] = b
	for t in ["wall_back", "wall_front", "wall_left", "wall_right", "ceiling", "soon_box", "cards_box", "door", "crate"]:
		assert_true(tags.has(t), "blocker " + t)
	assert_eq(str(tags["cards_box"]["kind"]), "cyl", "a round station is a cylinder")
	for id in lay.ids:
		var f: Vector2 = lay.stations[id]["front"]
		assert_eq(lay.station_at(f), id, "station_at at the front of " + id)
		assert_false(lay.blocked(f, HallLayout.AVATAR_R), "the front of %s is clear" % id)
	var sp := Vector2(lay.spawn.x, lay.spawn.z)
	assert_false(lay.blocked(sp, HallLayout.AVATAR_R), "spawn is clear")
	assert_eq(lay.station_at(sp), "", "spawn is in no station's reach")
	assert_eq(lay.blocker_at(Vector2(-4.5, 4.0), HallLayout.AVATAR_R), "crate", "the script's crate blocks")
	# ประตู: ชิดกล่องกัน (กลางตัวห่างขอบ AVATAR_R) = เข้า; ถอยออกมา 0.5 ม. = ไม่เข้า
	var contact := Vector2(0.0, 7.7 - HallLayout.AVATAR_R)
	assert_true(lay.in_walk_in("door", contact), "walking into the door counts at contact")
	assert_false(lay.in_walk_in("door", contact - Vector2(0.0, 0.5)), "and not 0.5 m away")
	assert_false(lay.in_walk_in("soon_box", Vector2(0.0, 0.0)), "far from soon_box")
	# กล้อง: รังสีชนผนังด้านขวา (x 6 − r) และหยุดหน้าลังไม้
	var o := Vector3(0.0, 1.3, 4.0)
	assert_within(lay.room_clear(o, Vector3.RIGHT, 0.45), 6.0 - 0.45, 0.001, "room_clear stops at the right wall")
	assert_within(lay.room_clear(Vector3(0.0, 1.3, 0.0), Vector3.UP, 0.45), 5.0 - 0.45 - 1.3, 0.001, "and at the ceiling")
	var t := lay.camera_clear(o, Vector3.LEFT, 4.5, RoomLayout.CAM_PAD)   # จุดกล้องอยู่ในลัง
	assert_within(t, 4.5 - 0.5 - RoomLayout.CAM_PAD, 0.001, "camera_clear pulls a camera inside the crate to its front")
	assert_within(lay.camera_clear(o, Vector3.RIGHT, 3.0, RoomLayout.CAM_PAD), 3.0, 0.001, "an empty line keeps its length")
	# ของใหญ่ที่บังแนวดึงกล้องมาหน้าของ ของเล็กที่บังแนวไม่ดึง (เหมือนดาดฟ้า)
	var big := RoomLayout.new(_room_data(), [{"kind": "box", "c": Vector3(3.0, 1.5, 0.0), "h": Vector3(1.0, 1.5, 1.0), "tag": "booth"},
		{"kind": "cyl", "c": Vector2(-3.0, 0.0), "r": 0.3, "y0": 0.0, "y1": 3.0, "tag": "post"}])
	var o2 := Vector3(0.0, 1.3, 0.0)
	assert_within(big.camera_clear(o2, Vector3.RIGHT, 5.5, RoomLayout.CAM_PAD, 5.5), 2.0 - RoomLayout.CAM_PAD, 0.001,
		"a big blocker that only hides the line pulls the camera to its front")
	assert_within(big.camera_clear(o2, Vector3.LEFT, 5.5, RoomLayout.CAM_PAD, 5.5), 5.5, 0.001,
		"a thin post that only hides the line does not")
	assert_true(RoomLayout.occludes({"kind": "cyl", "r": 1.35}) and not RoomLayout.occludes({"kind": "box", "h": Vector3(0.29, 3.0, 0.42)}),
		"occludes: a big crate yes, a buttress no")
	var bad := RoomLayout.extra_problems(lay.half, [{"kind": "box", "c": Vector3(0, 1, 0), "h": Vector3(1, 1, 1), "tag": "wall_x"},
		{"kind": "cyl", "c": Vector2(5.9, 0), "r": 0.5, "y0": 0.0, "y1": 1.0, "tag": "out"}])
	assert_true(bad.size() == 2, "a shell tag and a blocker leaving the room are refused", bad)
	var bad2 := RoomLayout.extra_problems(lay.half, [{"kind": "box", "c": Vector3(0, 1, 0), "h": Vector3(1, 1, 1)},
		{"kind": "box", "c": Vector3(0, 1, 0), "h": Vector3(1, 1, 1), "tag": ""},
		{"kind": "box", "c": Vector3(0, 1, 0), "h": Vector3(1, 1, 1), "tag": 7},
		{"kind": "box", "c": Vector3(0, 1, 0), "h": Vector3(1, 0, 1), "tag": "flat"},
		{"kind": "box", "c": Vector3(0, 1, 0), "h": Vector3(-1, 1, 1), "tag": "inside_out"}])
	assert_true(bad2.size() == 5, "a missing, empty or non-text tag and a box size <= 0 are refused", bad2)
	var kept := RoomLayout.new(_room_data(), [{"kind": "box", "c": Vector3(0, 1, 0), "h": Vector3(1, 1, 1)}])
	assert_eq(kept.blocker_at(Vector2.ZERO, 0.1), "", "a script list with an untagged blocker is dropped whole (no crash)")
	assert_eq(lay.clear_problems(), PackedStringArray(), "the fixture's spawn and fronts are clear with its crate")
	var stuck := RoomLayout.new(_room_data(), [{"kind": "cyl", "c": Vector2(0.0, 6.0), "r": 0.6, "y0": 0.0, "y1": 1.2, "tag": "crate"},
		{"kind": "box", "c": Vector3(-3.0, 0.5, -1.6), "h": Vector3(0.3, 0.5, 0.3), "tag": "post"}])
	var sp_bad := stuck.clear_problems()
	assert_true(sp_bad.size() == 3, "script blockers on the spawn and on two fronts are reported", sp_bad)


func test_hex6() -> void:
	for ok in ["0a1B2c", "ffffff", "000000"]:
		assert_true(PackRooms._hex6(ok), "bg %s is a colour" % ok)
	for no in ["-12345", "+12345", "0x1234", "12345", "1234567", "12 345", "gggggg"]:
		assert_false(PackRooms._hex6(no), "bg %s is refused" % no)


func test_pose_band() -> void:
	for x in [-12.5, 0.0, 12.5]:
		assert_false(PackRooms.in_band({"x": roundi(x * 100.0)}), "a deck pose at x %.1f is not in the band" % x)
	for x in [-15.0, 0.0, 15.0]:
		var bx := PackRooms.to_band(x)
		assert_within(PackRooms.from_band(bx), x, 0.0001, "to_band/from_band round-trip at %.1f" % x)
		assert_true(PackRooms.in_band({"x": roundi(bx * 100.0)}), "a room pose at local x %.1f is in the band" % x)
		assert_true(absf(bx) <= 50.0, "and inside the schema's ±50 m (%.1f)" % bx)
	assert_true(PackRooms.MAX_HALF.x + PackRooms.POSE_X <= 50.0 and PackRooms.POSE_X - PackRooms.MAX_HALF.x >= PackRooms.BAND_X,
		"every room x maps inside [BAND_X, 50]")
	assert_true(HallLayout.HALF.x < PackRooms.BAND_X, "the deck never reaches the band")


func test_stable_kit() -> void:
	var want := {"material": 0, "bake": 3, "lit": 2, "glow": 2, "tube": 6, "tris": 1, "arch_pts": 4, "build_colliders": 3,
			"append": 2, "flame_mesh": 0, "flame_plain_material": 0}
	var have := {}
	for m: Dictionary in (load("res://scenes/hall/hall_builder.gd") as Script).get_script_method_list():
		have[str(m["name"])] = (m["args"] as Array).size()
	for m: String in want:
		assert_eq(have.get(m, -1), want[m], "HallBuilder.%s takes %d arguments" % [m, want[m]])
	var consts := (load("res://scenes/hall/hall_builder.gd") as Script).get_script_constant_map()
	for c in ["STEEL", "STEEL_DARK", "DECK", "DECK_SEAM", "GRATE", "BRONZE", "BRASS", "IRON", "HAZARD", "HAZARD_DARK",
			"LAMP_AMBER", "AIRLOCK_GLOW", "HOLO", "HOLO_AMBER", "GOLD", "WAX"]:
		assert_true(consts.get(c) is Color, "HallBuilder.%s is a colour" % c)
	assert_true(consts.get("BANNER_COLS") is Array and (consts["BANNER_COLS"] as Array).size() >= 3, "HallBuilder.BANNER_COLS")
	assert_true(HallLayout.COOL_LIGHTS is Array and not HallLayout.COOL_LIGHTS.is_empty(), "HallLayout.COOL_LIGHTS")
	assert_true(ResourceLoader.exists("res://scenes/hall/flame.gdshader"), "res://scenes/hall/flame.gdshader")
	var g := PropsLayer.Geo.new()
	var geo_min := {"poly": 3, "box": 3, "prism": 7, "band": 7, "mesh": 0}
	var geo_have := {}
	for m: Dictionary in g.get_method_list():
		geo_have[str(m["name"])] = [(m["args"] as Array).size() - (m["default_args"] as Array).size(), (m["args"] as Array).size()]
	for m: String in geo_min:
		var a: Array = geo_have.get(m, [-1, -1])
		assert_true(a[0] <= geo_min[m] and a[1] >= geo_min[m], "PropsLayer.Geo.%s takes %d arguments" % [m, geo_min[m]])
	g.box(Vector3.ZERO, Vector3.ONE, Color.WHITE)
	HallBuilder.tube(g, Vector3.ZERO, Vector3.UP, 0.1, 6, Color.WHITE)
	HallBuilder.bake(g, PackedVector3Array([Vector3.UP]))
	assert_true(HallBuilder.tris(g.mesh()) > 12, "Geo + tube + bake + mesh + tris work together")
	assert_eq(HallLayout.AVATAR_R, 0.35, "AVATAR_R")
	assert_true(HallWorld.FADE_NEAR < HallWorld.FADE_FAR, "HallWorld.FADE_*")
	for m in PackRooms.ROOM_API:
		assert_true(["setup", "apply_level", "blockers"].has(m), "ROOM_API " + m)


func test_airlock_return() -> void:
	var r := Vector2(HallLayout.AIRLOCK_RETURN.x, HallLayout.AIRLOCK_RETURN.z)
	assert_false(HallLayout.blocked(r, HallLayout.AVATAR_R), "AIRLOCK_RETURN is clear")
	assert_eq(HallLayout.station_at(r), "", "and in no station's reach")
	assert_false(HallLayout.in_airlock(r), "in_airlock is false there")
	var c: Vector2 = HallLayout.STATIONS["online"]["c"]
	var h: Vector2 = HallLayout.STATIONS["online"]["h"]
	var contact := Vector2(c.x - h.x - HallLayout.AVATAR_R, c.y)
	assert_true(HallLayout.in_airlock(contact), "in_airlock is true at contact in front of the airlock")
	assert_eq(HallLayout.station_at(contact), "online", "where the airlock station is in reach")
	assert_false(HallLayout.in_airlock(contact + Vector2(0.0, h.y)), "not beside the doorway")
