class_name HiveBeast
extends CharacterBody3D
## สัตว์รัง (ARENA_SPEC §8.5, สัญญา §12.3): ตัวชนลอยที่ y = 0 ชั้น 8 ชน 1 | 4 | 2 · มีตัวละคร (สัญญา §9.1) สมอง HiveAI
## ทางเดิน ArenaPath จากที่กันที่โลกส่งมา เขตตะปบสีแดงบนพื้นตอนง้าง และ RNG ที่ seed คงที่ (สุ่มท่าซ้ำได้ เริ่มใหม่ตอนรีเซ็ต)
## เขตตะปบ = ขอบเขตจริงของกรงเล็บ (ระยะ strike_reach มุม ±strike_half_angle ตามทิศหน้า) ขอบสว่างตลอด เนื้อในลามถึงขอบตอนง้างครบ
## _physics_process ทำงานเฉพาะตอนบอทเปิด (ยกเว้นยืนพักบนแท่นตอนผู้เล่นไม่อยู่ในห้อง) กำลังสะดุ้ง/ตี ถูกผลัก หรือกะพริบ
## บอทปิดนิ่ง ๆ ไม่มีงานต่อเฟรมเลย · moved(pos) ส่งเฉพาะเฟรมที่ตัวขยับ (โลกใช้อัปเดตเป้าเล็งแดง)
## ตัวเลขทั้งหมดจาก ArenaData · ไม่มีข้อความไทย

signal hp_changed(hp: int, hp_max: int)
signal state_changed(state: StringName)
signal damaged(info: Dictionary)
signal died()
signal struck(info: Dictionary)
## ตัวขยับ (ส่วนเสริมของสัญญา: ส่งเฉพาะเฟรมที่ขยับจริง)
signal moved(pos: Vector3)

const LAYER := 8
const MASK := 1 | 4 | 2
const MASK_DEAD := 1 | 4
const KIT_BEAST := "res://scenes/arena/kit_beast.gd"
const ACTORS := "res://scenes/arena/arena_actors.gd"
const FLASH := 0.08                 # กะพริบขาวตอนโดน (วิ)
const FLASH_GUN := 0.45             # กระสุนกะพริบเบา (ยิงรัว 8 นัด/วิ ตัวไม่ขาวทั้งตัว) หมัด/ดาบเต็มแรง; จางลงใน 0.08 วิ
const KB_STOP := 0.02               # แรงผลักต่ำกว่านี้ถือว่าหยุด (ม./วิ)
const RING_RIM := 0.12              # ความกว้างขอบเขตตะปบ (ม.)
const RING_SEG := 24
const TELEGRAPH_SHADER := "res://scenes/arena/telegraph.gdshader"
const BUSY: Array[StringName] = [&"windup", &"strike", &"recover", &"hit"]

var level := "mid"
var _world: Node3D
var _figure: Node3D
var _ai: HiveAI
var _path: ArenaPath
var _target: Node3D
var _target_in_room := false
var _hp := 300
var _hp_max := 300
var _alive := true
var _kb := Vector3.ZERO
var _flash := 0.0
var _flash_peak := 1.0
var _paused := false
var _bounds := Rect2()
var _radius := 0.6
var _height := 2.1
var _yaw := 0.0
var _seed := 0
var _state: StringName = &"dummy"
var _tele := -1.0
var _ring: MeshInstance3D
var _ring_mat: ShaderMaterial
var _shape: CollisionShape3D
var _kit_key := ""
var _strikes := 0


## opts: {"level", "seed", "spawn": Vector3, "face", "bounds": Rect2, "blockers": Array, "figure": Node3D}
## (+ ของเทส "figure_opts": ส่งต่อให้ figure.setup เช่น {"kit": "..."} บังคับไม่มีชุดโมเดล)
func setup(world: Node3D, opts: Dictionary) -> void:
	_world = world
	level = str(opts.get("level", "mid"))
	_seed = int(opts.get("seed", ArenaData.RANGE["seed"]))
	var spawn: Vector3 = opts.get("spawn", Vector3.ZERO)
	var face := float(opts.get("face", 0.0))
	_bounds = opts.get("bounds", Rect2(-10, -10, 20, 20))
	collision_layer = LAYER
	collision_mask = MASK
	motion_mode = CharacterBody3D.MOTION_MODE_FLOATING
	_figure = opts.get("figure", null)
	if _figure == null:
		var s: GDScript = load(KIT_BEAST)
		_figure = s.new()
	_figure.name = "Figure"
	add_child(_figure)
	var fo := {"role": &"enemy", "level": level, "team_colour": Color(0.54, 0.31, 0.64), "seed": _seed}
	fo.merge(opts.get("figure_opts", {}), true)
	_figure.call(&"setup", fo)
	var m: Dictionary = _figure.call(&"metrics")
	_radius = float(m.get("radius", ArenaData.BEAST["radius"]))
	_height = maxf(float(m.get("height", ArenaData.BEAST["height"])), _radius * 2.0)
	_shape = get_node_or_null("Shape") as CollisionShape3D
	if _shape == null:
		_shape = CollisionShape3D.new()
		_shape.name = "Shape"
		add_child(_shape)
	var cap := CapsuleShape3D.new()
	cap.radius = _radius
	cap.height = _height
	_shape.shape = cap
	_shape.position = Vector3(0.0, _height * 0.5, 0.0)
	_kit_key = str(_figure.call(&"kit_key")) if _figure.has_method(&"kit_key") else _pack_id()
	_path = ArenaPath.new(_bounds, opts.get("blockers", []), _radius + 0.1)
	_ai = HiveAI.new(_seed)
	_hp_max = int(ArenaData.BEAST["hp"])
	_build_ring()
	reset_to(spawn, face)


func apply_level(l: String) -> void:
	level = l
	if _figure != null:
		_figure.call(&"apply_level", l)
	_tele = -1.0
	_update_telegraph()


## เป้า: ต้องมี global_position, is_alive(), take_hit(), RADIUS · ในห้องหรือไม่ โลกบอก
func set_target(t: Node3D) -> void:
	_target = t


func set_target_in_room(on: bool) -> void:
	if on == _target_in_room:
		return
	_target_in_room = on
	_wake()


func set_bot(on: bool) -> void:
	var was := _ai.state
	_ai.set_bot(on)
	if was != _ai.state and _ai.state == HiveAI.DUMMY:
		# หยุดท่าโจมตี/สะดุ้งที่ค้าง กลับยืน
		_figure.call(&"play", &"idle")
		_figure.call(&"set_move", 0.0, false)
	_sync_state()
	_update_telegraph()
	_wake()


func bot_on() -> bool:
	return _ai.bot


## โดน: hit = {"amount", "kind", "point", "dir", "from", "knockback", "stagger"} → {"applied", "hp", "killed", "toggled"}
func take_hit(hit: Dictionary) -> Dictionary:
	if not _alive:
		return {"applied": 0, "hp": _hp, "killed": false, "toggled": false}
	var r := ArenaCombat.apply(_hp, int(hit.get("amount", 0)))
	var applied := int(r["applied"])
	var killed := bool(r["killed"])
	_hp = int(r["hp"])
	_flash = FLASH
	_flash_peak = FLASH_GUN if StringName(hit.get("kind", &"")) == &"gun" else 1.0
	_figure.call(&"set_flash", _flash_peak)
	var dir: Vector3 = hit.get("dir", Vector3.ZERO)
	_kb += ArenaCombat.knockback(dir, float(hit.get("knockback", 0.0)))
	var react := _ai.on_damage(applied, bool(hit.get("stagger", false)), killed)
	if killed:
		_alive = false
		collision_layer = 0
		collision_mask = MASK_DEAD
		_play_variant(&"die", 1.0)
	elif react == &"flinch":
		_figure.call(&"play", &"hit")
	elif react == &"flinch_heavy":
		_figure.call(&"play", &"hit_heavy")
	_update_telegraph()
	damaged.emit({"amount": applied, "point": hit.get("point", global_position), "kind": hit.get("kind", &""), "hp": _hp,
		"killed": killed})
	hp_changed.emit(_hp, _hp_max)
	if killed:
		died.emit()
	_sync_state()
	_wake()
	return {"applied": applied, "hp": _hp, "killed": killed, "toggled": false}


## คืนสภาพบนแท่น: เลือดเต็ม มีชีวิต seed เดิม · สวิตช์บอทคงตำแหน่ง
func reset_to(p: Vector3, face: float) -> void:
	_hp = _hp_max
	_alive = true
	collision_layer = LAYER
	collision_mask = MASK
	position = Vector3(p.x, 0.0, p.z)
	velocity = Vector3.ZERO
	_yaw = face
	rotation = Vector3(0.0, face, 0.0)
	_kb = Vector3.ZERO
	_flash = 0.0
	_ai.set_home(Vector2(p.x, p.z), face)
	_ai.reset(_ai.bot)
	_figure.call(&"set_flash", 0.0)
	_figure.call(&"play", &"idle")
	_figure.call(&"set_move", 0.0, false)
	_tele = -1.0
	_update_telegraph()
	hp_changed.emit(_hp, _hp_max)
	_sync_state()
	_wake()


func hp() -> int:
	return _hp


func hp_max() -> int:
	return _hp_max


func state() -> StringName:
	return _ai.state if _ai != null else &"dummy"


func is_alive() -> bool:
	return _alive


func radius() -> float:
	return _radius


func telegraph() -> float:
	return _ai.telegraph() if _ai != null else 0.0


func kit_key() -> String:
	return _kit_key


func figure() -> Node3D:
	return _figure


func ai() -> HiveAI:
	return _ai


func path_finder() -> ArenaPath:
	return _path


## จำนวนครั้งที่ตะปบลง (เทส)
func strikes() -> int:
	return _strikes


func set_paused(on: bool) -> void:
	_paused = on
	if _figure != null:
		_figure.process_mode = Node.PROCESS_MODE_DISABLED if on else Node.PROCESS_MODE_INHERIT
	if on:
		set_physics_process(false)
	else:
		_wake()


func _physics_process(delta: float) -> void:
	if _paused or _ai == null:
		set_physics_process(false)
		return
	if _flash > 0.0:
		_flash -= delta
		if _flash <= 0.0:
			_flash = 0.0
			_figure.call(&"set_flash", 0.0)
		else:
			_figure.call(&"set_flash", _flash_peak * _flash / FLASH)
	var mv := Vector2.ZERO
	if _alive:
		var me := {"pos": Vector2(position.x, position.z), "yaw": _yaw, "hp": _hp, "alive": true}
		var tgt := _target_info()
		var r := _ai.tick(delta, me, tgt)
		if bool(r["repath"]):
			_ai.set_path(_path.find(me["pos"], r["goal"]))
		_yaw = float(r["face"])
		rotation.y = _yaw
		mv = r["move"]
		for e in r["events"]:
			_on_event(e, tgt)
		if not (_ai.state in BUSY) and _ai.state != HiveAI.DEAD:
			_figure.call(&"set_move", mv.length(), bool(r["run"]))
	var v := Vector3(mv.x, 0.0, mv.y) + _kb
	if v.length_squared() > 0.000001:
		velocity = v
		move_and_slide()
		position.y = 0.0
		_leash()
		moved.emit(global_position)
	_kb = ArenaCombat.decay(_kb, float(ArenaData.BEAST["friction"]), delta)
	if _kb.length() < KB_STOP:
		_kb = Vector3.ZERO
	_sync_state()
	_update_telegraph()
	if not _needs_tick():
		set_physics_process(false)


func _target_info() -> Dictionary:
	if _target == null or not is_instance_valid(_target):
		return {"pos": Vector2(position.x, position.z), "alive": false, "in_room": false, "r": 0.35}
	var tp := _target.global_position
	var r: Variant = _target.get("RADIUS")
	return {"pos": Vector2(tp.x, tp.z), "alive": bool(_target.call(&"is_alive")) if _target.has_method(&"is_alive") else true,
		"in_room": _target_in_room, "r": float(r) if r != null else 0.35}


func _on_event(e: StringName, tgt: Dictionary) -> void:
	match e:
		&"windup":
			_play_variant(&"attack", float(ArenaData.BEAST["attack_clip_speed"]))
		&"strike":
			_strikes += 1
			var landed := false
			var applied := 0
			if _ai.strike_hit and _target != null and is_instance_valid(_target) and _target.has_method(&"take_hit"):
				var tp := _target.global_position
				var dir := Vector3(tp.x - position.x, 0.0, tp.z - position.z)
				dir = dir.normalized() if dir.length_squared() > 0.000001 else Vector3(sin(_yaw), 0.0, cos(_yaw))
				var res: Variant = _target.call(&"take_hit", {"amount": int(ArenaData.BEAST["strike_damage"]), "kind": &"claw",
					"point": tp + Vector3(0.0, 1.2, 0.0), "dir": dir, "from": global_position, "knockback": 0.0, "stagger": false})
				landed = true
				applied = int((res as Dictionary).get("applied", 0)) if res is Dictionary else 0
			struck.emit({"hit": landed, "amount": applied})
		&"recovered":
			_figure.call(&"play", &"idle")


func _play_variant(logical: StringName, speed: float) -> void:
	if _figure.has_method(&"set_variant"):
		_figure.call(&"set_variant", _ai.variant)
	_figure.call(&"play", logical, speed)


## ไม่ออกนอกห้อง (ขอบในหดด้วยรัศมีตัว)
func _leash() -> void:
	var x0 := _bounds.position.x + _radius
	var x1 := _bounds.end.x - _radius
	var z0 := _bounds.position.y + _radius
	var z1 := _bounds.end.y - _radius
	position.x = clampf(position.x, x0, x1)
	position.z = clampf(position.z, z0, z1)


func _needs_tick() -> bool:
	if _paused:
		return false
	if _flash > 0.0 or _kb != Vector3.ZERO:
		return true
	if not _alive:
		return false
	if _ai.state in BUSY:
		return true
	# บอทเปิดแต่ผู้เล่นไม่อยู่ในห้อง และยืนพักบนแท่นหันหน้าเข้าทางเข้าแล้ว: หลับ (set_target_in_room ปลุก)
	if _ai.bot and _ai.state == HiveAI.IDLE and not _target_in_room and _at_home():
		return false
	return _ai.bot


func _at_home() -> bool:
	return Vector2(position.x, position.z).distance_to(_ai.home) <= HiveAI.HOME_R + 0.01 \
		and absf(angle_difference(_yaw, _ai.home_face)) < 0.001


func _wake() -> void:
	if not _paused and _needs_tick() and is_inside_tree():
		set_physics_process(true)
	elif not _needs_tick():
		set_physics_process(false)


func _sync_state() -> void:
	var s := _ai.state
	if s == _state:
		return
	var was := _state
	_state = s
	# สะดุ้งจบ: กลับท่าวน
	if was == HiveAI.HIT and s != HiveAI.DEAD:
		_figure.call(&"play", &"idle")
	state_changed.emit(s)


func _update_telegraph() -> void:
	var busy := _alive and _ai != null and (_ai.state == HiveAI.WINDUP or _ai.state == HiveAI.STRIKE)
	var t := telegraph() if busy else 0.0
	var key := t + (2.0 if busy else 0.0)
	if is_equal_approx(key, _tele):
		return
	_tele = key
	if _ring != null:
		_ring.visible = busy
		if busy:
			_ring_mat.set_shader_parameter(&"fill", t)
	if _figure != null:
		_figure.call(&"set_telegraph", t if level != "min" else 0.0)


## ขอบเขตของเขตตะปบ: ระยะ (ม. จากกลางตัวถึงกลางเป้า) และครึ่งมุม (องศา) = ค่าที่ AI ใช้ตัดสินว่าโดน
static func telegraph_shape() -> Dictionary:
	return {"reach": float(ArenaData.BEAST["strike_reach"]), "half_angle_deg": float(ArenaData.BEAST["strike_half_angle_deg"])}


## เขตตะปบบนพื้น: เมชเดียว (หนึ่ง draw) วาดเฉพาะตอนง้าง/ตี · พัดเนื้อใน (UV.y 0) + ขอบโค้งและขอบสองข้าง (UV.y 1)
func _build_ring() -> void:
	if _ring != null:
		return
	_ring = MeshInstance3D.new()
	_ring.name = "Telegraph"
	var shape := telegraph_shape()
	var reach := float(shape["reach"])
	var half := deg_to_rad(float(shape["half_angle_deg"]))
	var inner := reach - RING_RIM
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_normal(Vector3.UP)
	var dir := func(a: float) -> Vector3: return Vector3(sin(a), 0.0, cos(a))
	for i in RING_SEG:
		var a0 := -half + 2.0 * half * i / RING_SEG
		var a1 := -half + 2.0 * half * (i + 1) / RING_SEG
		var d0: Vector3 = dir.call(a0)
		var d1: Vector3 = dir.call(a1)
		# เนื้อใน: จากกลางตัวถึงขอบใน
		for v in [[Vector3.ZERO, 0.0], [d0 * inner, 1.0], [d1 * inner, 1.0]]:
			st.set_uv(Vector2(v[1], 0.0))
			st.add_vertex(v[0])
		# ขอบโค้ง
		for v in [d0 * inner, d0 * reach, d1 * reach, d0 * inner, d1 * reach, d1 * inner]:
			st.set_uv(Vector2(1.0, 1.0))
			st.add_vertex(v)
	# ขอบสองข้างตามแนวรัศมี
	for a in [-half, half]:
		var d: Vector3 = dir.call(a)
		var side := Vector3(d.z, 0.0, -d.x) * (RING_RIM * 0.5)
		for v in [-side, d * reach - side, d * reach + side, -side, d * reach + side, side]:
			st.set_uv(Vector2(1.0, 1.0))
			st.add_vertex(v)
	_ring.mesh = st.commit()
	_ring_mat = ShaderMaterial.new()
	_ring_mat.shader = load(TELEGRAPH_SHADER)
	_ring_mat.set_shader_parameter(&"fill", 0.0)
	_ring.material_override = _ring_mat
	_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_ring.position = Vector3(0.0, 0.025, 0.0)
	_ring.visible = false
	add_child(_ring)


func _pack_id() -> String:
	if ResourceLoader.exists(ACTORS):
		var s: Script = load(ACTORS)
		if s != null:
			var id: Variant = s.call(&"pack_id")
			if id is String and id != "":
				return id
	return "pack"
