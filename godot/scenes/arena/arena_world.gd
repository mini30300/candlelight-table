class_name ArenaWorld
extends Node3D
## โลก 3 มิติของอารีน่าทดสอบอาวุธ (ARENA_SPEC §4, §7, §10–§12.3): เมชนิ่ง 2 ชิ้น เปลวเทียน แผ่นเป้าสวิตช์ โคมสัญญาณ
## ตัวชน ป้าย วงแหวน ตัวผู้เล่น (ArenaPlayer) กับสัตว์รัง (HiveBeast) ที่โหลดตอนใช้ · ข้อความบนป้ายมาจากหน้าอารีน่า
## (set_sign_text; ไฟล์นี้ไม่มีข้อความไทย) · ไม่มีไฟจริง ไม่มีเงา สภาพแวดล้อมตั้งบนกล้อง
## งานต่อเฟรม: ไม่มีในสคริปต์นี้ (ทุกอย่างตามสัญญาณ); โคมหมุนกับเปลวไฟไหวอยู่ใน shader บน hi/mid เท่านั้น

signal mode_changed(mode: StringName)
signal station_changed(id: String)
signal stats_changed(stats: Dictionary)
signal bot_toggled(on: bool, how: StringName)
signal reset_done()
signal leave_requested()

const PLAYER_SCENE := "res://scenes/arena/arena_player.tscn"
const BEAST_SCENE := "res://scenes/arena/hive_beast.tscn"
const TEAMS_PATH := "res://data/teams.json"
const BG := Color("05060a")
const RING_R := 0.68
const STATION_RING_R := 0.55
const RING_ACTIVE := Color(1.0, 0.78, 0.34)
const SWITCH_OFF := Color("d8463c")
const SWITCH_ON := Color("5fe08a")
const BEACON_OFF := Color(0.22, 0.16, 0.10)
const BEACON_ON := Color(1.0, 0.72, 0.30)
const BOARD_TEXT := Color("7dffa6")
## ต่อระดับกราฟิก (ARENA_SPEC §11.1): จำนวนเหลี่ยม เปลวไหว โคมหมุน ขอบป้าย
const LEVELS := {
	"hi": {"sides": 14, "flicker": true, "spin": true, "outline": true},
	"mid": {"sides": 12, "flicker": true, "spin": true, "outline": true},
	"lo": {"sides": 10, "flicker": false, "spin": false, "outline": false},
	"min": {"sides": 8, "flicker": false, "spin": false, "outline": false},
}
const SIGN_FONT_SIZE := 88
const SIGN_PIXEL := 0.005
const SIGN_WIDTH := 860.0
const BOARD_TITLE_PIXEL := 0.0075
const BOARD_BODY_PIXEL := 0.005
## ป้ายประตูในทางเดิน (กว้าง 2.6 ม.): ตัวเล็กลง ตัดบรรทัดในกว้าง 2.4 ม.
const DOOR_SIGN_PIXEL := 0.003
const DOOR_SIGN_W := 2.4
const LEAVE_REARM := 0.3         # ต้องเดินห่างประตูเกินนี้ก่อนจะขอกลับดาดฟ้าได้อีก

@onready var static_root: Node3D = $Static
@onready var flames_node: MultiMeshInstance3D = $Flames
@onready var switch_head: MeshInstance3D = $SwitchHead
@onready var beacon: MeshInstance3D = $Beacon
@onready var blockers_body: StaticBody3D = $Blockers
@onready var props_body: StaticBody3D = $PropBlockers
@onready var switch_target: StaticBody3D = $SwitchTarget
@onready var signs_root: Node3D = $Signs
@onready var rings: Rings = $Rings
@onready var fallback_camera: Camera3D = $FallbackCamera

var player: Node3D
var enemy: Node3D
var level := ""
var active := true
var team_colour := Color(0.28, 0.52, 0.84)
var state := ArenaState.new()

var _static: Array[MeshInstance3D] = []
var _signs: Dictionary = {}
var _outline: Dictionary = {}
var _sides := 0
var _blockers := 0
var _flame_shader: ShaderMaterial
var _beacon_shader: ShaderMaterial
var _beacon_plain: StandardMaterial3D
var _switch_mat: StandardMaterial3D
var _spin := false
var _flicker := false
var _env: Environment
var _mode: StringName = &"walk"
var _station := ""
var _player_ring := -1
var _station_rings: Dictionary = {}
var _leave_armed := false
var _paused := false
var _enemy_kit := ""


func _ready() -> void:
	add_to_group("gfx_level")
	var teams: Variant = JSON.parse_string(FileAccess.get_file_as_string(TEAMS_PATH)) if FileAccess.file_exists(TEAMS_PATH) else null
	if teams is Array and not (teams as Array).is_empty() and (teams[0] as Dictionary).has("rgb"):
		var rgb: Array = teams[0]["rgb"]
		team_colour = Color8(int(rgb[0]), int(rgb[1]), int(rgb[2]))
	for n in ["Shell", "Props"]:
		var mi := MeshInstance3D.new()
		mi.name = n
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.material_override = HallBuilder.material()
		static_root.add_child(mi)
		_static.append(mi)
	for mi: GeometryInstance3D in [flames_node, switch_head, beacon]:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_blockers = _build_colliders()
	_build_switch()
	_build_signs()
	rings.setup(1 + ArenaLayout.IDS.size() + 1)
	_player_ring = rings.add_ring(ArenaLayout.SPAWN, Vector3.UP, RING_R, team_colour)
	for id in ArenaLayout.IDS:
		var f: Vector2 = ArenaLayout.STATIONS[id]["front"]
		_station_rings[id] = rings.add_kind(Rings.Kind.OBJECTIVE, Vector3(f.x, 0.0, f.y), Vector3.UP, STATION_RING_R)
	_env = Environment.new()
	_env.background_mode = Environment.BG_COLOR
	_env.background_color = BG
	_env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	_env.ambient_light_color = Color.BLACK
	_env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	fallback_camera.environment = _env
	var app := get_node_or_null(^"/root/App")
	var l := str(app.get("gfx")) if app != null else "mid"
	var touch := bool(app.call("touch_active")) if app != null else false
	_spawn_actors(l, touch)
	apply_level(l)
	place_player(ArenaLayout.SPAWN, ArenaLayout.SPAWN_FACE, ArenaLayout.SPAWN_YAW)
	# มุมกล้องตอนเริ่มในทางเดิน (เงยพอเห็นป้ายประตูอารีน่า)
	var rig: Node3D = player.call(&"camera_rig") if player != null and player.has_method(&"camera_rig") else null
	if rig != null and rig.has_method(&"set_view"):
		rig.call(&"set_view", ArenaLayout.SPAWN_YAW, ArenaLayout.SPAWN_PITCH, ArenaLayout.SPAWN_ARM)
	_update_switch()
	if active:
		_make_current()


## ตัวผู้เล่นกับสัตว์รัง (โหลดฉากตอนใช้; ไม่มีฉากก็ยังเปิดโลกได้ เทสเฉพาะห้องใช้กล้องสำรอง)
func _spawn_actors(l: String, touch: bool) -> void:
	if ResourceLoader.exists(PLAYER_SCENE):
		var ps: PackedScene = load(PLAYER_SCENE)
		player = ps.instantiate() as Node3D
		if player != null:
			player.name = "Player"
			add_child(player)
			if player.has_method(&"setup"):
				player.call(&"setup", self, {"level": l, "team_colour": team_colour, "touch": touch,
					"figure": ArenaActors.make_figure("player")})
			_connect(player, &"moved", _on_player_moved)
			_connect(player, &"mode_changed", _on_player_mode)
			var cam: Variant = player.call(&"camera") if player.has_method(&"camera") else null
			if cam is Camera3D:
				(cam as Camera3D).environment = _env
	if ResourceLoader.exists(BEAST_SCENE):
		var bs: PackedScene = load(BEAST_SCENE)
		enemy = bs.instantiate() as Node3D
		if enemy != null:
			enemy.name = "Beast"
			add_child(enemy)
			if enemy.has_method(&"setup"):
				enemy.call(&"setup", self, {"level": l, "seed": seed_value(), "spawn": ArenaLayout.BEAST_SPAWN,
					"face": ArenaLayout.BEAST_FACE, "bounds": ArenaLayout.room_rect(), "blockers": ArenaLayout.blockers(),
					"figure": ArenaActors.make_figure("enemy")})
			if player != null and enemy.has_method(&"set_target"):
				enemy.call(&"set_target", player)
			for sig in [&"hp_changed", &"state_changed", &"died"]:
				_connect(enemy, sig, _on_enemy_changed)
			_connect(enemy, &"damaged", _on_enemy_damaged)
			# เป้าเล็งแดงต้องตามศัตรูที่ขยับ ล้ม หรือรีเซ็ต แม้ผู้เล่นยืนนิ่ง (ตามสัญญาณ ไม่มีงานต่อเฟรมตอนนิ่ง)
			for sig in [&"moved", &"state_changed"]:
				_connect(enemy, sig, _refresh_aim)
			_connect(self, &"reset_done", _refresh_aim)
			if enemy.has_method(&"kit_key"):
				_enemy_kit = str(enemy.call(&"kit_key"))


func _connect(node: Object, sig: StringName, cb: Callable) -> void:
	if node.has_signal(sig) and not node.is_connected(sig, cb):
		node.connect(sig, cb)


## seed ของสนาม (ArenaData.RANGE.seed)
static func seed_value() -> int:
	return int(ArenaData.RANGE["seed"])


## ใช้ระดับกราฟิก: ค่ารวมของแอปแบบ HallWorld (render scale, fps, วาดตอนนิ่ง) แล้วเมชนิ่ง เปลวไฟ โคม ขอบป้าย ตัวละคร
func apply_level(l: String) -> void:
	if not LEVELS.has(l):
		l = "mid"
	level = l
	var cfg: Dictionary = LEVELS[l]
	var tv: Dictionary = HallWorld.table_levels().get(l, {})
	var vp := get_viewport()
	if vp != null and not tv.is_empty():
		vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
		vp.scaling_3d_scale = float(tv["scale"])
		vp.msaa_3d = Viewport.MSAA_DISABLED
	if not tv.is_empty():
		Engine.max_fps = int(tv["fps"])
		OS.low_processor_usage_mode = bool(tv["idle"])
	var sides := int(cfg["sides"])
	if sides != _sides:
		_sides = sides
		var ms := ArenaBuilder.meshes(sides)
		for i in ms.size():
			_static[i].mesh = ms[i]
		beacon.mesh = ArenaBuilder.beacon_mesh(sides)
	_build_flames(bool(cfg["flicker"]))
	_spin = bool(cfg["spin"])
	_update_switch()
	for id in _signs:
		(_signs[id] as Label3D).outline_size = int(_outline[id]) if bool(cfg["outline"]) else 0
	for a in [player, enemy]:
		if a != null and a.has_method(&"apply_level"):
			a.call(&"apply_level", l)


## เปิด/ปิดโลกทั้งโลก: ซ่อน หยุดงาน (ตัวชนออกจากฟิสิกส์) คืนกล้อง ปล่อยเมาส์
func set_active(on: bool) -> void:
	active = on
	visible = on
	process_mode = Node.PROCESS_MODE_INHERIT if on else Node.PROCESS_MODE_DISABLED
	if not is_node_ready():
		return
	if on:
		_make_current()
	else:
		var cam := camera()
		if cam != null:
			cam.clear_current(false)
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


## หยุดชั่วคราว: ตัวผู้เล่น สัตว์รัง กล้องหยุด (ตัวชนยังอยู่) ปล่อยเมาส์
func set_paused(on: bool) -> void:
	_paused = on
	for a in [player, enemy]:
		if a != null and a.has_method(&"set_paused"):
			a.call(&"set_paused", on)
	if on:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func paused() -> bool:
	return _paused


func camera() -> Camera3D:
	if player != null and player.has_method(&"camera"):
		var c: Variant = player.call(&"camera")
		if c is Camera3D:
			return c
	return fallback_camera


func _make_current() -> void:
	var cam := camera()
	if cam != null:
		cam.make_current()


## ข้อความบนป้าย: "switch", "reset", "door_back", "door_arena", "board_title", "board_body"
func set_sign_text(id: String, text: String) -> void:
	var l: Label3D = _signs.get(id)
	if l != null:
		l.text = text


func sign_text(id: String) -> String:
	var l: Label3D = _signs.get(id)
	return l.text if l != null else ""


func labels() -> Array[Label3D]:
	var out: Array[Label3D] = []
	for id in _signs:
		out.append(_signs[id])
	return out


func station() -> String:
	return _station


func mode() -> StringName:
	if player != null and player.has_method(&"mode"):
		return StringName(player.call(&"mode"))
	return _mode


## ใช้จุดใช้งานตรงหน้า: สวิตช์ = สลับบอท, รีเซ็ต = คืนทุกอย่าง
func use_station() -> void:
	match _station:
		"switch":
			toggle_bot(&"use")
		"reset":
			reset_range()


## สลับสวิตช์บอท (กด E / ยิงโดน / ต่อยหรือฟันโดนเสา) คืน false เมื่อยังไม่พ้นช่วงพัก 1 วิ
## ยิงหรือฟันโดนแผ่น: สลับเฉพาะนัดแรกของชุด (ต้องเว้นไม่โดนแผ่น 1 วิก่อนชุดใหม่ ArenaState.plate_hit)
func toggle_bot(how: StringName) -> bool:
	var ok := state.toggle(game_time()) if how == &"use" else state.plate_hit(game_time())
	if not ok:
		return false
	_update_switch()
	if enemy != null and enemy.has_method(&"set_bot"):
		enemy.call(&"set_bot", state.bot_on)
	bot_toggled.emit(state.bot_on, how)
	stats_changed.emit(stats())
	return true


## รีเซ็ต (กด E ที่แท่นเท่านั้น): สัตว์รังกลับแท่นเลือดเต็ม ผู้เล่นเลือดเต็มกระสุนเต็ม ตัวนับเป็นศูนย์ สวิตช์คงเดิม
func reset_range() -> void:
	if enemy != null and enemy.has_method(&"reset_to"):
		enemy.call(&"reset_to", ArenaLayout.BEAST_SPAWN, ArenaLayout.BEAST_FACE)
	if player != null and player.has_method(&"heal_full"):
		player.call(&"heal_full")
	state.reset()
	reset_done.emit()
	stats_changed.emit(stats())


## เวลาเกมจากจำนวนเฟรมฟิสิกส์ (ไม่อ่านนาฬิกา ไม่ต้องมีงานต่อเฟรม)
func game_time() -> float:
	return float(Engine.get_physics_frames()) / float(maxi(Engine.physics_ticks_per_second, 1))


func stats() -> Dictionary:
	var b := {"hp": 0, "hp_max": 0, "state": &"dummy", "alive": true}
	if enemy != null:
		b = {"hp": int(enemy.call(&"hp")) if enemy.has_method(&"hp") else 0,
			"hp_max": int(enemy.call(&"hp_max")) if enemy.has_method(&"hp_max") else 0,
			"state": StringName(enemy.call(&"state")) if enemy.has_method(&"state") else &"dummy",
			"alive": bool(enemy.call(&"is_alive")) if enemy.has_method(&"is_alive") else true}
	return state.stats(b)


## วางตัวผู้เล่นที่ p หัน face กล้อง yaw cam_yaw
func place_player(p: Vector3, face: float, cam_yaw: float) -> void:
	if player != null and player.has_method(&"place"):
		player.call(&"place", p, face, cam_yaw)
	else:
		_on_player_moved(p)
		var pivot := p + Vector3(0.0, 1.3, 0.0)
		var b := Basis.from_euler(Vector3(ArenaLayout.SPAWN_PITCH, cam_yaw, 0.0))
		fallback_camera.global_transform = Transform3D(b, pivot + b.z * ArenaLayout.SPAWN_ARM)


## ตัวที่กระสุนโดน: {"node", "id": &"beast" | &"switch"} หรือ {}
func hit_target(collider: Object) -> Dictionary:
	if collider == null:
		return {}
	if collider == switch_target:
		return {"node": self, "id": &"switch"}
	if enemy != null and collider is Node and (collider == enemy or enemy.is_ancestor_of(collider as Node)):
		return {"node": enemy, "id": &"beast"}
	return {}


## เป้าของหมัด/ดาบ: สัตว์รัง (ตอนยังไม่ล้ม) กับเสาสวิตช์
func melee_targets() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if enemy != null and (not enemy.has_method(&"is_alive") or bool(enemy.call(&"is_alive"))):
		var ep := enemy.global_position
		var r := float(enemy.call(&"radius")) if enemy.has_method(&"radius") else 0.6
		out.append({"node": enemy, "id": &"beast", "pos": Vector2(ep.x, ep.z), "r": r})
	var s: Dictionary = ArenaLayout.STATIONS["switch"]
	out.append({"node": self, "id": &"switch", "pos": s["c"], "r": float(s["r"])})
	return out


## โดนที่สวิตช์ (id switch): ยิงหรือต่อยโดนก็สลับ (ผ่านช่วงพักของ toggle_bot)
func take_hit(hit: Dictionary) -> Dictionary:
	var kind := StringName(hit.get("kind", &"gun"))
	var toggled := toggle_bot(&"shot" if kind == &"gun" else &"melee")
	return {"applied": 0, "hp": 0, "killed": false, "toggled": toggled}


func counts() -> Dictionary:
	var tris := 0
	for mi in _static:
		if mi.mesh != null:
			tris += HallBuilder.tris(mi.mesh as ArrayMesh)
	var fx_add := false
	if player != null and player.has_method(&"counts"):
		fx_add = bool((player.call(&"counts") as Dictionary).get("fx_additive", false))
	else:
		fx_add = level == "hi" or level == "mid"
	return {"level": level, "static_meshes": _static.size(), "static_tris": tris, "flames": flames_node.multimesh.instance_count
		if flames_node.multimesh != null else 0, "flicker": _flicker, "signs": _signs.size(), "blockers": _blockers,
		"pillars": ArenaLayout.PILLARS.size(), "enemy_kit": _enemy_kit, "fx_additive": fx_add,
		"beacon_spin": beacon.material_override == _beacon_shader and _beacon_shader != null, "sides": _sides}


func rings_count() -> int:
	return rings.count()


# ---- ภายใน ----

func _on_player_moved(pos: Vector3) -> void:
	var xz := Vector2(pos.x, pos.z)
	rings.set_ring(_player_ring, Vector3(pos.x, 0.0, pos.z), Vector3.UP, RING_R, team_colour)
	# โหมดเดิน/ยิงตามเส้น (มีระยะกันสลับไปมา)
	var cur := mode()
	var want := ArenaLayout.mode_for(pos.z, cur)
	if want != cur:
		if player != null and player.has_method(&"set_mode"):
			player.call(&"set_mode", want)
		if player == null or not player.has_signal(&"mode_changed"):
			_set_mode(want)
	_update_target(xz)
	# จุดใช้งาน
	var s := ArenaLayout.station_at(xz)
	if s != _station:
		if _station != "":
			rings.set_colour(_station_rings[_station], Rings.KIND_COLOUR[Rings.Kind.OBJECTIVE])
		if s != "":
			rings.set_colour(_station_rings[s], RING_ACTIVE)
		_station = s
		station_changed.emit(s)
	# เดินกลับเข้าประตูดาดฟ้า: ขอครั้งเดียวต่อการเดินเข้า (ต้องมีคำสั่งเดินจริง ไม่ใช่การวางตัว)
	if pos.z < ArenaLayout.LEAVE_Z - LEAVE_REARM:
		_leave_armed = true
	if _leave_armed and ArenaLayout.leaving(pos.z, mode()) and _moving():
		_leave_armed = false
		leave_requested.emit()


func _moving() -> bool:
	if player != null and player.has_method(&"input_vector"):
		return Vector2(player.call(&"input_vector")) != Vector2.ZERO
	return true


func _on_player_mode(m: StringName) -> void:
	_set_mode(m)
	if player != null:
		_update_target(Vector2(player.global_position.x, player.global_position.z))


## ศัตรูไล่เฉพาะตอนผู้เล่นอยู่ในห้องและถือปืนแล้ว (โหมดยิง): ช่วงขอบห้องโหมดเดินยังเก็บปืน สู้กลับไม่ได้
func _update_target(xz: Vector2) -> void:
	if enemy != null and enemy.has_method(&"set_target_in_room"):
		enemy.call(&"set_target_in_room", ArenaLayout.in_room(xz) and mode() == &"shoot")


func _set_mode(m: StringName) -> void:
	if m == _mode:
		return
	_mode = m
	mode_changed.emit(m)


func _on_enemy_changed(_a: Variant = null, _b: Variant = null) -> void:
	stats_changed.emit(stats())


func _refresh_aim(_a: Variant = null) -> void:
	if player != null and player.has_method(&"refresh_aim"):
		player.call(&"refresh_aim")


func _on_enemy_damaged(info: Dictionary) -> void:
	state.record_hit(int(info.get("amount", 0)))
	stats_changed.emit(stats())


## สีแผ่นเป้า (แดงปิด เขียวเปิด) กับโคม: hi/mid หมุน (shader) ตอนเปิด, lo/min สีนิ่ง สว่างเฉพาะตอนเปิด
func _update_switch() -> void:
	if _switch_mat == null:
		return
	_switch_mat.albedo_color = SWITCH_ON if state.bot_on else SWITCH_OFF
	if state.bot_on and _spin:
		if _beacon_shader == null:
			_beacon_shader = ShaderMaterial.new()
			_beacon_shader.shader = load("res://scenes/arena/beacon.gdshader")
		beacon.material_override = _beacon_shader
	else:
		if _beacon_plain == null:
			_beacon_plain = StandardMaterial3D.new()
			_beacon_plain.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			_beacon_plain.cull_mode = BaseMaterial3D.CULL_DISABLED
		_beacon_plain.albedo_color = BEACON_ON if state.bot_on else BEACON_OFF
		beacon.material_override = _beacon_plain


func beacon_lit() -> bool:
	return state.bot_on


func _build_switch() -> void:
	var s: Dictionary = ArenaLayout.STATIONS["switch"]
	var plate: Vector3 = s["plate"]
	switch_head.mesh = ArenaBuilder.plate_mesh(float(s["plate_r"]))
	switch_head.position = plate
	_switch_mat = StandardMaterial3D.new()
	_switch_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_switch_mat.vertex_color_use_as_albedo = true
	switch_head.material_override = _switch_mat
	beacon.position = s["beacon"]
	switch_target.collision_layer = 16
	switch_target.collision_mask = 0
	var cs := CollisionShape3D.new()
	cs.name = "Plate"
	var sp := SphereShape3D.new()
	sp.radius = float(s["plate_r"])
	cs.shape = sp
	cs.position = plate
	switch_target.add_child(cs)


## ตัวชนจาก ArenaLayout.blockers(): เปลือก (ชั้น 1, แขนกล้องชน) / ของในห้อง (ชั้น 4)
func _build_colliders() -> int:
	blockers_body.collision_layer = 1
	blockers_body.collision_mask = 0
	props_body.collision_layer = 4
	props_body.collision_mask = 0
	var n := 0
	for b in ArenaLayout.blockers():
		var cs := CollisionShape3D.new()
		cs.name = "Shape_%s_%d" % [str(b["tag"]), n]
		if str(b["kind"]) == "box":
			var box := BoxShape3D.new()
			box.size = (b["h"] as Vector3) * 2.0
			cs.shape = box
			cs.position = b["c"]
		else:
			var cyl := CylinderShape3D.new()
			cyl.radius = float(b["r"])
			cyl.height = float(b["y1"]) - float(b["y0"])
			cs.shape = cyl
			var c2: Vector2 = b["c"]
			cs.position = Vector3(c2.x, (float(b["y0"]) + float(b["y1"])) * 0.5, c2.y)
		(blockers_body if ArenaLayout.is_shell(b) else props_body).add_child(cs)
		n += 1
	return n


## เปลวเทียนสองดวงใน MultiMesh เดียว: hi/mid shader ไหวของดาดฟ้า, lo/min วัสดุธรรมดา
func _build_flames(flicker: bool) -> void:
	var pts := ArenaLayout.flames()
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.use_custom_data = true
	mm.mesh = HallBuilder.flame_mesh()
	mm.instance_count = pts.size()
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value()
	for i in pts.size():
		mm.set_instance_transform(i, Transform3D(Basis().scaled(Vector3.ONE * rng.randf_range(0.95, 1.1)), pts[i]))
		mm.set_instance_color(i, Color.WHITE)
		mm.set_instance_custom_data(i, Color(rng.randf(), 0.0, 0.0, 0.0))
	flames_node.multimesh = mm
	if flicker:
		if _flame_shader == null:
			_flame_shader = ShaderMaterial.new()
			_flame_shader.shader = load(HallWorld.FLAME_SHADER)
		flames_node.material_override = _flame_shader
	else:
		flames_node.material_override = HallBuilder.flame_plain_material()
	_flicker = flicker


func _build_signs() -> void:
	for id in ArenaLayout.SIGNS:
		var d: Dictionary = ArenaLayout.SIGNS[id]
		var l := Label3D.new()
		l.name = "Sign_" + id
		l.font_size = SIGN_FONT_SIZE
		l.pixel_size = SIGN_PIXEL
		l.outline_size = 16
		l.modulate = Color(1.0, 0.92, 0.76)
		l.outline_modulate = Color(0.12, 0.06, 0.02)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		l.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		l.billboard = BaseMaterial3D.BILLBOARD_DISABLED
		l.double_sided = false
		l.position = d["p"]
		l.rotation.y = float(d["face"])
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.width = SIGN_WIDTH
		if id.begins_with("board"):
			l.modulate = BOARD_TEXT
			l.outline_modulate = Color(0.0, 0.08, 0.04)
			l.pixel_size = BOARD_TITLE_PIXEL if id == "board_title" else BOARD_BODY_PIXEL
			l.width = float(ArenaLayout.BOARD["w"]) / l.pixel_size * 0.92
		elif id.begins_with("door"):
			l.pixel_size = DOOR_SIGN_PIXEL
			l.width = DOOR_SIGN_W / DOOR_SIGN_PIXEL
		elif id == "switch":
			# ป้ายสวิตช์ตั้งบนโคม: ขอบล่างของข้อความอยู่ที่จุดป้าย (เหนือยอดโคม) บรรทัดที่ตัดเพิ่มงอกขึ้นข้างบน ไม่บังโคม/แผ่นเป้า
			l.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
		signs_root.add_child(l)
		_signs[id] = l
	for id in _signs:
		_outline[id] = (_signs[id] as Label3D).outline_size
