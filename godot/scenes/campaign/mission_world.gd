class_name MissionWorld
extends Node3D
## โลก 3 มิติของภารกิจ (CAMPAIGN_SPEC §1.6, §5.4, track C): สนามจาก MissionLayout + MissionBuilder (เมชนิ่ง 2 ชิ้น) ตัวชน
## ผู้เล่น ArenaPlayer (ตัวที่แต่งในห้องแต่งตัว ตั้งค่าแบบ ArenaWorld._spawn_actors) ศัตรูตาม MissionWaves (จำกัดจำนวนที่มีชีวิต
## พร้อมกันตามระดับ MissionTypes.ALIVE_CAP ระลอกเติมเมื่อมีตัวตาย) ตัวประกัน เสาพิธี ฐาน สัญญาณ จุดรับ (วงบนพื้นใน Rings เดียว)
## กระสุนช้าของมือปืนใน MultiMesh เดียว · เป้าหมายและสถิติใน MissionObjectives · สุ่มทุกอย่างจาก spec.seed (RNG แยกตามเกลือ)
## เป็ดไทป์แบบ ArenaWorld ให้ ArenaPlayer / ArenaHud (player, enemy = null, hit_target, melee_targets, camera)
## งานต่อเฟรม: _physics_process ตอนเล่นอยู่เท่านั้น (เวลา ระลอก ศัตรู กระสุน ตัวประกัน) หยุดชั่วคราว/จบแล้ว = ไม่มีงาน
## ไม่มีข้อความไทย (หน้าภารกิจกับ MissionHud แปลงสถานะเป็นข้อความ)

signal objective_changed(state: Dictionary)
signal ended(outcome: String)
signal stats_changed(stats: Dictionary)
## เหตุการณ์สำหรับข้อความแจ้งเตือน: &"wave" {n, of}, &"boss", &"freed", &"saved", &"hostage_dead", &"pylon", &"base_hit",
## &"revive" {left}, &"last_life", &"secondary" {i}, &"extract", &"beacon_on"
signal event(kind: StringName, info: Dictionary)
signal station_changed(id: String)

const PLAYER_SCENE := "res://scenes/arena/arena_player.tscn"
const PLAYER_R := 0.35
const SALT_ENEMY := 0xE11E
const SALT_SPAWN := 0x5A57
const SPAWN_GAP := 0.35          # วิระหว่างศัตรูเกิดแต่ละตัว
const HUNT_RESERVE := 2          # ช่องที่ยามประจำจุด (ค่าย/ตัวประกัน) ห้ามใช้ ระลอกที่ไล่ล่าเกิดได้เสมอ
const SPAWN_MIN_D := 12.0        # จุดเกิดขอบห่างผู้เล่นอย่างน้อย
const REPATHS := 2               # คิดทางใหม่ได้กี่ตัวต่อเฟรมฟิสิกส์
const CORPSE := {"hi": 3.0, "mid": 2.5, "lo": 1.8, "min": 1.2}
const AGGRO := 13.0              # ยามค่าย/ยามตัวประกันตื่นเมื่อผู้เล่นใกล้กว่านี้
const TRAIL_STEP := 0.5
const TRAIL_MAX := 64
const OBJ_EVERY := 0.25          # ส่งสถานะเป้าหมายให้ HUD ทุกกี่วิ (นอกเหนือจากตอนมีเหตุการณ์)
const BOLT_CAP := 24
const BOLT_LIFE := 2.5
const BOLT_R := 0.45
const RING_R := 0.68
const BASE_RING_R := 3.4
const TEAM := Color(0.28, 0.52, 0.84)
const RING_PICKUP := Color(0.36, 0.86, 0.5)
const RING_HOSTAGE := Color(1.0, 0.78, 0.34)
const RING_BEACON := Color(0.45, 0.72, 1.0)
const RING_BASE := Color(0.28, 0.52, 0.84)
const RING_ACTIVE := Color(1.0, 0.95, 0.6)
const PLAYER_W := 6.0
const BASE_W := 4.0
const HOSTAGE_W := 2.5
const LEVELS: PackedStringArray = ["hi", "mid", "lo", "min"]

@onready var static_root: Node3D = $Static
@onready var blockers_body: StaticBody3D = $Blockers
@onready var props_body: StaticBody3D = $PropBlockers
@onready var rings: Rings = $Rings
@onready var bolts_node: MultiMeshInstance3D = $Bolts
@onready var fallback_camera: Camera3D = $FallbackCamera

var player: Node3D
var enemy: Node3D = null
var spec: Dictionary = {}
var level := "mid"
var touch := false
var active := true
var layout: Dictionary = {}
var plan: Array[Dictionary] = []
var obj: MissionObjectives
var path: ArenaPath
## เทส: ผู้เล่นไม่เสียเลือดจากศัตรู (ชนะได้ด้วยสคริปต์)
var test_god := false

var _static: Array[MeshInstance3D] = []
var _env: Environment
var _paused := false
var _ended := false
var _setup_done := false
var _running := false
var _enemies: Array[MissionEnemy] = []
var _queue: Array[Dictionary] = []
var _wave_started: Array[bool] = []
var _wave_alive: Array[int] = []
var _spawn_t := 0.0
var _spawned := 0
var _rng_spawn := RandomNumberGenerator.new()
var _camp_left: Array = []      # จุดยามค่ายที่ยังไม่ถูกใช้ (แจกแบบไม่ซ้ำจนหมดรอบ)
var _enemy_seq := 0
var _repath_from := 0
var _targets: Array[Dictionary] = []
var _target_meta: Array[Dictionary] = []
var _hostages: Array[MissionHostage] = []
var _pylons: Array[StaticBody3D] = []
var _pylon_mesh: ArrayMesh
var _rubble_mesh: ArrayMesh
var _bolts: Array[Dictionary] = []
var _bolt_mat: StandardMaterial3D
var _trail: Array[Vector3] = []
var _freeing := -1
var _free_t := 0.0
var _station := ""
var _station_idx := -1
var _rings_hostage: Array[int] = []
var _ring_player := -1
var _ring_pickup := -1
var _ring_beacon := -1
var _ring_base := -1
var _last_in_mag := -1
var _reloading := false
var _obj_t := 0.0
var _obj_sig := ""
var _checkpoint := Vector3.ZERO
var _boss: MissionEnemy
var _sec_done: Array = []
var _kits: Array[Resource] = []
var _team_colour := TEAM
var _built_level := ""


func _ready() -> void:
	add_to_group("gfx_level")
	for n in ["Ground", "Props"]:
		var mi := MeshInstance3D.new()
		mi.name = n
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.material_override = HallBuilder.material()
		static_root.add_child(mi)
		_static.append(mi)
	_env = Environment.new()
	_env.background_mode = Environment.BG_COLOR
	_env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	_env.ambient_light_color = Color.BLACK
	_env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	fallback_camera.environment = _env
	set_physics_process(false)


## สร้างภารกิจจาก spec (เรียกครั้งเดียวหลังเข้าต้นไม้)
func setup(p_spec: Dictionary, p_level: String, p_touch: bool) -> void:
	spec = p_spec
	touch = p_touch
	level = p_level if LEVELS.has(p_level) else "mid"
	layout = MissionLayout.build(spec)
	plan = MissionWaves.plan(spec)
	obj = MissionObjectives.new(spec, MissionWaves.total(plan))
	_sec_done = obj.secondary_done()
	_rng_spawn.seed = int(spec.get("seed", 0)) ^ SALT_SPAWN
	_camp_left.clear()
	_wave_started.resize(plan.size())
	_wave_started.fill(false)
	_wave_alive.resize(plan.size())
	_wave_alive.fill(0)
	_env.background_color = MissionBuilder.sky(str(layout["biome"]))
	path = ArenaPath.new(MissionLayout.bounds(), layout["blockers"], 0.5, MissionLayout.CELL)
	_build_colliders()
	_preload_kits()
	var ptype := str(obj.ptype)
	var pts: Dictionary = layout["points"]
	_checkpoint = layout["player_spawn"]
	# วงบนพื้น: ผู้เล่น จุดรับ สัญญาณ ฐาน ตัวประกัน
	rings.setup(4 + (pts["hostages"] as Array).size())
	_ring_player = rings.add_ring(_checkpoint, Vector3.UP, RING_R, _team_colour)
	if MissionTypes.extracts(ptype) or obj.hostages.size() > 0:
		_ring_pickup = rings.add_ring(pts["pickup"], Vector3.UP, MissionTypes.PICKUP_R, RING_PICKUP)
	if obj.secondary.has("defend"):
		_ring_beacon = rings.add_ring(pts["beacon"], Vector3.UP, MissionTypes.BEACON_R, RING_BEACON)
	if ptype == "defend":
		_ring_base = rings.add_ring(pts["base"], Vector3.UP, BASE_RING_R, RING_BASE)
	_spawn_hostages()
	_spawn_pylons()
	_spawn_player()
	apply_level(level)
	_setup_done = true
	_emit_objectives(true)
	stats_changed.emit(stats())
	if active and is_inside_tree():
		_make_current()


## เริ่มนับเวลา (หน้าภารกิจเรียกหลังป้ายชื่อภารกิจหายไป)
func begin() -> void:
	if not _setup_done or _ended:
		return
	_running = true
	set_physics_process(not _paused)


func apply_level(l: String) -> void:
	if not LEVELS.has(l):
		l = "mid"
	level = l
	var tv: Dictionary = HallWorld.table_levels().get(l, {})
	var vp := get_viewport()
	if vp != null and not tv.is_empty():
		vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
		vp.scaling_3d_scale = float(tv["scale"])
		vp.msaa_3d = Viewport.MSAA_DISABLED
	if not tv.is_empty():
		Engine.max_fps = int(tv["fps"])
		OS.low_processor_usage_mode = bool(tv["idle"])
	if not layout.is_empty() and l != _built_level:
		_built_level = l
		var ms := MissionBuilder.meshes(layout, l, int(spec.get("seed", 0)))
		for i in ms.size():
			_static[i].mesh = ms[i]
		var sides := int(MissionBuilder.SIDES[l])
		_pylon_mesh = MissionBuilder.pylon_mesh(sides)
		_rubble_mesh = MissionBuilder.rubble_mesh(sides)
		for i in _pylons.size():
			var mi := _pylons[i].get_node("Mesh") as MeshInstance3D
			mi.mesh = _rubble_mesh if int(obj.pylons[i]["hp"]) <= 0 else _pylon_mesh
	for e in _enemies:
		e.apply_level(l)
	for h in _hostages:
		h.apply_level(l)
	if player != null and player.has_method(&"apply_level"):
		player.call(&"apply_level", l)


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


## หยุดชั่วคราว: เวลา ศัตรู กระสุน ตัวประกัน ผู้เล่นหยุดหมด (ไม่มีงานต่อเฟรม)
func set_paused(on: bool) -> void:
	_paused = on
	if player != null and player.has_method(&"set_paused"):
		player.call(&"set_paused", on)
	for e in _enemies:
		e.set_paused(on)
	for h in _hostages:
		h.set_paused(on)
	set_physics_process(not on and _setup_done and not _ended and _begun())
	if on:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func paused() -> bool:
	return _paused


func is_ended() -> bool:
	return _ended


func camera() -> Camera3D:
	if player != null and player.has_method(&"camera"):
		var c: Variant = player.call(&"camera")
		if c is Camera3D:
			return c
	return fallback_camera


func mode() -> StringName:
	return StringName(player.call(&"mode")) if player != null and player.has_method(&"mode") else &"shoot"


func station() -> String:
	return _station


## ใช้จุดตรงหน้า: ตัวประกัน = เริ่มปล่อย (ยืนในวงครบเวลา) · สัญญาณ = เปิด
func use_station() -> void:
	if _ended or _paused:
		return
	match _station:
		"hostage":
			if _freeing < 0 and obj.hostage_state(_station_idx) == MissionObjectives.CAPTIVE:
				_freeing = _station_idx
				_free_t = 0.0
				_emit_objectives(true)
		"beacon":
			if obj.beacon_start():
				rings.set_colour(_ring_beacon, RING_ACTIVE)
				event.emit(&"beacon_on", {})
				_emit_objectives(true)
				_update_station()


## ความคืบหน้าการปล่อยตัวประกัน 0..1 (−1 = ไม่ได้ปล่อยอยู่)
func freeing() -> float:
	if _freeing < 0:
		return -1.0
	return clampf(_free_t / float(MissionTypes.HOSTAGE["free_s"]), 0.0, 1.0)


## ตัวที่กระสุนโดน: ศัตรู = id &"beast" (เป้าเล็งแดงของ ArenaPlayer) · เสาพิธี = &"pylon"
func hit_target(collider: Object) -> Dictionary:
	if collider == null:
		return {}
	if collider is MissionEnemy and (collider as MissionEnemy).is_alive():
		return {"node": collider, "id": &"beast"}
	for p in _pylons:
		if collider == p:
			return {"node": p, "id": &"pylon"} if int(obj.pylons[int(p.get_meta("i"))]["hp"]) > 0 else {}
	return {}


## เป้าของหมัด/ดาบ: ศัตรูที่ยังมีชีวิตใกล้ผู้เล่น และเสาพิธีที่ยังไม่พัง
func melee_targets() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var pp := player.global_position if player != null else Vector3.ZERO
	for e in _enemies:
		if e.is_alive() and e.global_position.distance_to(pp) < 6.0:
			out.append({"node": e, "id": &"beast", "pos": Vector2(e.global_position.x, e.global_position.z), "r": e.radius()})
	for p in _pylons:
		var i := int(p.get_meta("i"))
		if int(obj.pylons[i]["hp"]) > 0:
			out.append({"node": p, "id": &"pylon", "pos": Vector2(p.global_position.x, p.global_position.z), "r": 0.6})
	return out


## โดนเสาพิธี (เรียกจาก MissionPylon.take_hit)
func pylon_hit(p: StaticBody3D, hit: Dictionary) -> Dictionary:
	var i := int(p.get_meta("i"))
	var r := obj.damage_pylon(i, int(hit.get("amount", 0)))
	if bool(r["killed"]):
		(p.get_node("Mesh") as MeshInstance3D).mesh = _rubble_mesh
		p.collision_layer = 0
		_sfx(&"die", p.global_position + Vector3(0.0, 1.5, 0.0), 1.4, 0.5)
		event.emit(&"pylon", {"left": obj.pylons_left(true), "primary": bool(obj.pylons[i]["primary"])})
		if obj.extract_ready():
			event.emit(&"extract", {})
		_after_event()
	return {"applied": int(r["applied"]), "hp": int(r["hp"]), "killed": bool(r["killed"])}


func result() -> Dictionary:
	return obj.result() if obj != null else {}


func objective_state() -> Dictionary:
	return obj.state() if obj != null else {}


func stats() -> Dictionary:
	if obj == null:
		return {}
	return {"kills": obj.killed, "shots": maxi(obj.shots - obj.structure_shots, 0), "hits": obj.hits, "damage_taken": obj.damage_taken, "downs": obj.downs,
		"alive": alive_count(), "revives": obj.revives_left}


func alive_count() -> int:
	var n := 0
	for e in _enemies:
		if e.is_alive():
			n += 1
	return n


## ศัตรูที่มีชีวิตได้พร้อมกันตอนนี้: ตามระดับ แต่ไม่ให้ตัวละครมีโครงบนจอ (ผู้เล่น ตัวประกัน ศพ) เกิน SKINNED_CAP
func alive_cap() -> int:
	var cap := MissionTypes.alive_cap(level)
	var extra := 1
	for h in _hostages:
		if h.is_alive() and h.skinned():
			extra += 1
	for e in _enemies:
		if not e.is_alive() and e.skinned():
			extra += 1
	return clampi(MissionTypes.skinned_cap(level) - extra, 1, cap)


func enemies() -> Array[MissionEnemy]:
	var out: Array[MissionEnemy] = []
	for e in _enemies:
		if e.is_alive():
			out.append(e)
	return out


func hostages() -> Array[MissionHostage]:
	return _hostages


func pylons() -> Array[StaticBody3D]:
	return _pylons


func boss() -> MissionEnemy:
	return _boss if _boss != null and is_instance_valid(_boss) and _boss.is_alive() else null


func queued() -> int:
	return _queue.size()


func spawned() -> int:
	return _spawned


func counts() -> Dictionary:
	var tris := 0
	for mi in _static:
		if mi.mesh != null:
			tris += MissionBuilder.tris(mi.mesh as ArrayMesh)
	var skinned := 0
	var tele := false
	for e in _enemies:
		if e.skinned() and e.visible:
			skinned += 1
		if e.telegraph_uses_shader():
			tele = true
	for h in _hostages:
		if h.skinned() and h.visible:
			skinned += 1
	if player != null:
		var f: Variant = player.call(&"figure") if player.has_method(&"figure") else null
		if f is KitBeast and str((f as KitBeast).kit_key()) not in ["", "egg"]:
			skinned += 1
	return {"level": level, "alive": alive_count(), "alive_cap": alive_cap(), "skinned": skinned, "static_meshes": _static.size(),
		"static_tris": tris, "telegraph_shader": tele, "bolts": _bolts.size(), "queue": _queue.size(), "spawned": _spawned,
		"enemies_nodes": _enemies.size(), "processing": is_physics_processing()}


## วางผู้เล่น (เทส/ลุกขึ้น) หันกล้อง cam_yaw
func place_player(p: Vector3, cam_yaw: float) -> void:
	if player != null and player.has_method(&"place"):
		player.call(&"place", p, PI, cam_yaw)


## เทส: เดินโลกไปข้างหน้า seconds วิทีละ dt ทันที (ทั้งศัตรู กระสุน ตัวประกัน เวลา) หยุดเมื่อจบภารกิจ
func simulate(seconds: float, dt: float = 1.0 / 30.0) -> void:
	var t := 0.0
	while t < seconds and not _ended:
		_step(dt)
		t += dt


## เทส/หน้าภารกิจ: ออกกลางคัน
func quit() -> void:
	if obj != null:
		obj.quit()
	_finish_world("")


# ---- ต่อเฟรม ----

func _physics_process(delta: float) -> void:
	if _paused or _ended or not _running:
		set_physics_process(false)
		return
	_step(delta)


func _step(dt: float) -> void:
	if _ended:
		return
	obj.tick(dt)
	_waves()
	_spawn_from_queue(dt)
	_build_targets()
	var cam := camera()
	var cam_pos := cam.global_position if cam != null else Vector3.ZERO
	var budget := REPATHS
	var n := _enemies.size()
	var corpse := float(CORPSE.get(level, 2.0))
	var gone: Array[MissionEnemy] = []
	for k in n:
		var e := _enemies[(k + _repath_from) % n]
		if e.step(dt, _targets, budget > 0, cam_pos):
			budget -= 1
		if not e.is_alive() and e.dead_t > corpse:
			gone.append(e)
	_repath_from += 1
	for e in gone:
		_enemies.erase(e)
		e.queue_free()
	_step_bolts(dt)
	_step_hostages(dt)
	if obj.beacon_on and _ring_beacon >= 0 and player != null:
		obj.beacon_tick(dt, _player_xz().distance_to(_xz(layout["points"]["beacon"])) <= MissionTypes.BEACON_R)
	if (obj.extract_ready() or obj.ptype == "destroy_camp") and player != null:
		obj.set_at_pickup(_player_xz().distance_to(_xz(layout["points"]["pickup"])) <= MissionTypes.PICKUP_R)
	_obj_t -= dt
	if _obj_t <= 0.0:
		_obj_t = OBJ_EVERY
		_emit_objectives(false)
		_check_secondary()
	if obj.ended():
		_finish_world(obj.outcome())


func _waves() -> void:
	for i in plan.size():
		if _wave_started[i]:
			continue
		var w: Dictionary = plan[i]
		var go := float(w["at_s"]) >= 0.0 and obj.t >= float(w["at_s"])
		if not go and bool(w["after_clear"]):
			go = true
			for k in i:
				if not _wave_started[k] or _wave_alive[k] > 0:
					go = false
					break
		if not go:
			continue
		_wave_started[i] = true
		var n_wave := 0
		for k in range(0, i + 1):
			if not bool(plan[k].get("guard", false)):
				n_wave += 1
		for u: Dictionary in w["units"]:
			for c in int(u["count"]):
				_queue.append({"role": str(u["role"]), "kit": str(u["kit"]), "faction": str(u["faction"]),
					"spawn": str(w["spawn"]), "post": str(w["post"]), "wave": i, "guard": bool(w.get("guard", false))})
				_wave_alive[i] += 1
		if not bool(w.get("guard", false)) and n_wave > 1:
			var waves_total := plan.filter(func(x: Dictionary) -> bool: return not bool(x.get("guard", false))).size()
			# ระลอกใหม่: ผู้เล่นที่ยังยืนอยู่ได้พลังชีวิตและกระสุนเต็ม (ไม่มีของเก็บในสนาม)
			if player != null and bool(player.call(&"is_alive")) and player.has_method(&"heal_full"):
				player.call(&"heal_full")
			event.emit(&"wave", {"n": n_wave, "of": waves_total})


func _spawn_from_queue(dt: float) -> void:
	_spawn_t -= dt
	if _queue.is_empty() or _spawn_t > 0.0:
		return
	var cap := alive_cap()
	if alive_count() >= cap:
		return
	# ยามที่ยืนเฝ้าเต็มโควตาแล้ว: ข้ามไปเอาตัวที่ไล่ล่าตัวแรกในคิว (ไม่มีก็รอ)
	var idx := 0
	if str(_queue[0]["post"]) != "" and posted_alive() >= maxi(cap - HUNT_RESERVE, 1):
		idx = -1
		for i in _queue.size():
			if str(_queue[i]["post"]) == "":
				idx = i
				break
		if idx < 0:
			return
	_spawn_t = SPAWN_GAP
	var u: Dictionary = _queue.pop_at(idx)
	_spawn_enemy(u)


## ยามประจำจุด (ค่าย/ตัวประกัน) ที่ยังมีชีวิต
func posted_alive() -> int:
	var n := 0
	for e in _enemies:
		if e.is_alive() and bool(e.get_meta("posted", false)):
			n += 1
	return n


func _spawn_enemy(u: Dictionary) -> MissionEnemy:
	var role := str(u["role"])
	var faction := str(u["faction"])
	var st := MissionRoster.stats(spec, role)
	st["flank_pct"] = MissionTypes.flank_pct(str(spec.get("difficulty", "normal")))
	var post_kind := str(u["post"])
	var pos := _spawn_point(str(u["spawn"]), post_kind)
	if post_kind != "":
		st["aggro"] = AGGRO
	var post: Variant = null
	if role == "gunner":
		post = _cover_post(pos)
	var e := MissionEnemy.new()
	e.name = "Enemy%d" % _enemy_seq
	add_child(e)
	var pp := _player_xz()
	e.setup(self, {"level": level, "seed": int(spec.get("seed", 0)) ^ SALT_ENEMY ^ (_enemy_seq * 7919), "role": role,
		"faction": faction, "kit": str(u["kit"]), "style": MissionRoster.style(faction), "stats": st, "spawn": pos,
		"path": path, "post": post, "index": _enemy_seq, "bounds": MissionLayout.bounds(),
		"yaw": atan2(pp.x - pos.x, pp.y - pos.z)})
	e.set_meta("wave", int(u["wave"]))
	e.set_meta("posted", post_kind != "")
	e.died.connect(_on_enemy_died.bind(e))
	if _paused:
		e.set_paused(true)
	_enemies.append(e)
	_enemy_seq += 1
	_spawned += 1
	if role == "boss":
		_boss = e
		event.emit(&"boss", {"kit": str(u["kit"])})
		_sfx(&"charge", e.global_position + Vector3(0.0, 2.0, 0.0), 1.2, 0.6)
	return e


## จุดเกิด: ขอบ (ห่างผู้เล่น ≥ SPAWN_MIN_D) · near (ซุ่มโจมตี) · camp / hostages (ยามเฝ้า)
func _spawn_point(kind: String, post: String) -> Vector3:
	var pts: Dictionary = layout["points"]
	if post == "camp":
		# แจกจุดยามไม่ซ้ำ (สับด้วย _rng_spawn) หมดรอบค่อยสับใหม่ + เยื้อง ±0.8 ม. ไม่ให้ยืนซ้อนกัน
		if _camp_left.is_empty():
			_camp_left = (layout["posts"]["camp"] as Array).duplicate()
			for i in range(_camp_left.size() - 1, 0, -1):
				var j := _rng_spawn.randi_range(0, i)
				var tmp: Variant = _camp_left[i]
				_camp_left[i] = _camp_left[j]
				_camp_left[j] = tmp
		var cpt: Vector3 = _camp_left.pop_back()
		for _try in 4:
			var q := cpt + Vector3(_rng_spawn.randf_range(-0.8, 0.8), 0.0, _rng_spawn.randf_range(-0.8, 0.8))
			if MissionLayout.inside_blocker(layout["blockers"], q, 0.6) == "":
				return q
		return cpt
	if post == "hostages" and not (pts["hostages"] as Array).is_empty():
		var hs: Array = pts["hostages"]
		var h: Vector3 = hs[_rng_spawn.randi_range(0, hs.size() - 1)]
		for _try in 8:
			var a := _rng_spawn.randf_range(0.0, TAU)
			var p := h + Vector3(cos(a), 0.0, sin(a)) * _rng_spawn.randf_range(2.5, 5.0)
			if MissionLayout.bounds().grow(-1.0).has_point(_xz(p)) and MissionLayout.inside_blocker(layout["blockers"], p, 0.8) == "":
				return p
		return h + Vector3(0.0, 0.0, 2.0)
	var list: Array = layout["near_spawns"] if kind == "near" else layout["spawns"]
	var pp := _player_xz()
	var ok: Array = []
	for p: Vector3 in list:
		if kind == "near" or _xz(p).distance_to(pp) >= SPAWN_MIN_D:
			ok.append(p)
	if ok.is_empty():
		ok = list
	var base: Vector3 = ok[_rng_spawn.randi_range(0, ok.size() - 1)]
	return base + Vector3(_rng_spawn.randf_range(-0.8, 0.8), 0.0, _rng_spawn.randf_range(-0.8, 0.8))


func _cover_post(from: Vector3) -> Variant:
	var cover: Array = layout["posts"]["cover"]
	if cover.is_empty():
		return null
	var best: Variant = null
	var bd := INF
	var pp := _player_xz()
	for c: Vector3 in cover:
		var d := _xz(c).distance_to(_xz(from)) + absf(_xz(c).distance_to(pp) - 10.0)
		if d < bd:
			bd = d
			best = _xz(c)
	return best


func _build_targets() -> void:
	_targets.clear()
	_target_meta.clear()
	var alive := player != null and bool(player.call(&"is_alive"))
	_targets.append({"pos": _player_xz(), "alive": alive, "r": PLAYER_R, "kind": "player", "w": PLAYER_W})
	_target_meta.append({"kind": "player"})
	if obj.ptype == "defend":
		_targets.append({"pos": _xz(layout["points"]["base"]), "alive": obj.base_hp > 0, "r": MissionTypes.BASE_R, "kind": "base",
			"w": BASE_W})
		_target_meta.append({"kind": "base"})
	for h in _hostages:
		if obj.hostage_state(h.index) == MissionObjectives.FOLLOW and h.is_alive():
			_targets.append({"pos": _xz(h.position), "alive": true, "r": 0.35, "kind": "hostage", "w": HOSTAGE_W})
			_target_meta.append({"kind": "hostage", "i": h.index})


## ศัตรูฟาด: amount 0 = พลาด (เสียงวืด)
func enemy_strike(e: MissionEnemy, t: Dictionary, amount: int) -> void:
	var at := e.global_position + Vector3(0.0, 1.2, 0.0)
	if amount <= 0 or t.is_empty():
		_sfx(&"swing", at, 0.9, 0.7)
		return
	_apply_damage(t, amount, e.global_position, &"claw")
	_sfx(&"claw", at, 1.0, 0.85)


## มือปืนยิง: กระสุนช้าไปทางเป้า (หลบได้)
func enemy_fire(e: MissionEnemy, t: Dictionary) -> void:
	if _bolts.size() >= BOLT_CAP:
		return
	var from := e.chest() + Vector3(0.0, 0.1, 0.0)
	var tp: Vector2 = t.get("pos", _player_xz())
	var to := Vector3(tp.x, 1.1, tp.y)
	var spd := float(e.ai().stats.get("bolt", 12.0))
	var dir := (to - from).normalized()
	_bolts.append({"pos": from, "vel": dir * spd, "dmg": int(e.ai().stats.get("dmg", 10)), "life": BOLT_LIFE, "from": e.global_position})
	_sfx(&"shot", from, 0.55, 0.65)


func enemy_event(_e: MissionEnemy, _kind: StringName, _t: Dictionary) -> void:
	pass


# ---- ภายใน ----

func _apply_damage(t: Dictionary, amount: int, from: Vector3, kind: StringName) -> void:
	match str(t.get("kind", "")):
		"player":
			if player != null and not test_god:
				var pp := player.global_position
				var dir := Vector3(pp.x - from.x, 0.0, pp.z - from.z)
				dir = dir.normalized() if dir.length_squared() > 0.0001 else Vector3.FORWARD
				player.call(&"take_hit", {"amount": amount, "kind": kind, "point": pp + Vector3(0.0, 1.2, 0.0), "dir": dir,
					"from": from, "knockback": 0.0, "stagger": false})
		"base":
			var a := obj.base_damage(amount * MissionTypes.BASE_DMG_PCT / 100)
			if a > 0:
				event.emit(&"base_hit", {"pct": obj.base_pct()})
				_after_event()
		"hostage":
			var hi := int(t.get("i", -1))
			for h in _hostages:
				if h.index == hi and h.take_damage(amount):
					obj.hostage_died(hi)
					if hi < _rings_hostage.size() and _rings_hostage[hi] >= 0:
						rings.remove_ring(_rings_hostage[hi])
						_rings_hostage[hi] = -1
					event.emit(&"hostage_dead", {"i": hi})
					_after_event()


func _on_enemy_died(info: Dictionary, e: MissionEnemy) -> void:
	var w := int(e.get_meta("wave", 0))
	if w >= 0 and w < _wave_alive.size():
		_wave_alive[w] = maxi(_wave_alive[w] - 1, 0)
	obj.kill(str(info.get("role", "rusher")))
	_sfx(&"die", e.global_position + Vector3(0.0, 1.0, 0.0), 1.2, 0.7 if e.role() in ["brute", "boss"] else 1.0)
	_after_event()


func _after_event() -> void:
	_emit_objectives(true)
	_check_secondary()
	stats_changed.emit(stats())
	if obj.ended():
		_finish_world(obj.outcome())


func _check_secondary() -> void:
	var now := obj.secondary_done()
	for i in now.size():
		if bool(now[i]) and not bool(_sec_done[i] if i < _sec_done.size() else false):
			event.emit(&"secondary", {"i": i, "type": str(obj.secondary[i])})
	_sec_done = now


func _emit_objectives(force: bool) -> void:
	if obj == null:
		return
	var st := obj.state()
	st["freeing"] = freeing()
	var sig := var_to_str([st["primary"], st["secondary"], int(float(st["timer_s"])), st["base_pct"], st["hostages"],
		st["revives"], snappedf(float(st["freeing"]), 0.05)])
	if not force and sig == _obj_sig:
		return
	_obj_sig = sig
	objective_changed.emit(st)


func _finish_world(outcome: String) -> void:
	if _ended:
		return
	_ended = true
	set_physics_process(false)
	_bolts.clear()
	_write_bolts()
	for e in _enemies:
		e.set_paused(true)
	if player != null and player.has_method(&"set_input_enabled"):
		player.call(&"set_input_enabled", false)
	_emit_objectives(true)
	stats_changed.emit(stats())
	if outcome == "win" or outcome == "fail":
		ended.emit(outcome)


func _step_bolts(dt: float) -> void:
	if _bolts.is_empty():
		return
	var keep: Array[Dictionary] = []
	var space := get_world_3d().direct_space_state if is_inside_tree() else null
	for b in _bolts:
		var p0: Vector3 = b["pos"]
		var p1: Vector3 = p0 + (b["vel"] as Vector3) * dt
		b["life"] = float(b["life"]) - dt
		var hit := false
		for k in _targets.size():
			var t: Dictionary = _targets[k]
			if not bool(t["alive"]):
				continue
			var tp: Vector2 = t["pos"]
			var r := float(t["r"]) + (0.1 if str(t["kind"]) != "player" else BOLT_R - PLAYER_R)
			if _seg_dist2(Vector2(p0.x, p0.z), Vector2(p1.x, p1.z), tp) <= r * r and p1.y < 2.2:
				_apply_damage(t, int(b["dmg"]), b["from"], &"bolt")
				hit = true
				break
		if not hit and space != null:
			var q := PhysicsRayQueryParameters3D.create(p0, p1, 1 | 4)
			if not space.intersect_ray(q).is_empty():
				hit = true
		if not hit and float(b["life"]) > 0.0:
			b["pos"] = p1
			keep.append(b)
	_bolts = keep
	_write_bolts()


func _write_bolts() -> void:
	var mm := bolts_node.multimesh
	if mm == null:
		return
	mm.visible_instance_count = _bolts.size()
	for i in _bolts.size():
		var b: Dictionary = _bolts[i]
		var v: Vector3 = b["vel"]
		var basis := Basis.looking_at(v.normalized() if v.length_squared() > 0.0001 else Vector3.FORWARD, Vector3.UP)
		mm.set_instance_transform(i, Transform3D(basis, b["pos"]))


func _step_hostages(dt: float) -> void:
	if _hostages.is_empty() or player == null:
		return
	var pp := player.global_position
	# ปล่อยตัวประกัน: ยืนในวงจนครบเวลา ออกนอกวง = เริ่มใหม่
	if _freeing >= 0:
		var h := _hostage(_freeing)
		if h == null or _xz(h.position).distance_to(_xz(pp)) > float(MissionTypes.HOSTAGE["free_r"]) + 0.3 or not bool(player.call(&"is_alive")):
			_freeing = -1
			_emit_objectives(true)
		else:
			_free_t += dt
			if _free_t >= float(MissionTypes.HOSTAGE["free_s"]):
				var i := _freeing
				_freeing = -1
				if obj.free_hostage(i):
					h.set_freed()
					if i < _rings_hostage.size() and _rings_hostage[i] >= 0:
						rings.remove_ring(_rings_hostage[i])
						_rings_hostage[i] = -1
					_checkpoint = h.position
					event.emit(&"freed", {"i": i})
					_sfx(&"heal", h.position + Vector3(0.0, 1.0, 0.0), 1.0, 1.0)
					_update_station()
					_after_event()
	var order := 0
	var pickup: Vector3 = layout["points"]["pickup"]
	for h in _hostages:
		if obj.hostage_state(h.index) != MissionObjectives.FOLLOW or not h.is_alive():
			continue
		var gap := float(MissionTypes.HOSTAGE["follow_gap"]) * (order + 1)
		h.step(dt, _trail_point(gap), 0.4)
		order += 1
		if _xz(h.position).distance_to(_xz(pickup)) <= MissionTypes.PICKUP_R:
			if obj.save_hostage(h.index):
				event.emit(&"saved", {"i": h.index})
				_sfx(&"heal", h.position + Vector3(0.0, 1.0, 0.0), 1.2, 1.2)
				_after_event()


## จุดบนรอยเท้าผู้เล่นที่ห่างจากตัวผู้เล่นไปตามรอย dist ม.
func _trail_point(dist: float) -> Vector3:
	var pp := player.global_position
	var acc := 0.0
	var prev := pp
	for i in range(_trail.size() - 1, -1, -1):
		var q: Vector3 = _trail[i]
		var seg := prev.distance_to(q)
		if acc + seg >= dist:
			return prev.lerp(q, (dist - acc) / maxf(seg, 0.0001))
		acc += seg
		prev = q
	return prev


func _hostage(i: int) -> MissionHostage:
	for h in _hostages:
		if h.index == i:
			return h
	return null


func _spawn_player() -> void:
	if not ResourceLoader.exists(PLAYER_SCENE):
		return
	var ps: PackedScene = load(PLAYER_SCENE)
	player = ps.instantiate() as Node3D
	if player == null:
		return
	player.name = "Player"
	add_child(player)
	if player.has_method(&"setup"):
		# ตัว + ชุดสีที่เลือกในห้องแต่งตัว (เหมือน ArenaWorld._spawn_actors)
		var sel := Figures.selected()
		player.call(&"setup", self, {"level": level, "team_colour": _team_colour, "touch": touch,
			"figure": ArenaActors.player_figure(sel), "scheme": ArenaActors.scheme_of(sel)})
	var cam: Variant = player.call(&"camera") if player.has_method(&"camera") else null
	if cam is Camera3D:
		(cam as Camera3D).environment = _env
	for pair in [[&"moved", _on_player_moved], [&"ammo_changed", _on_ammo], [&"reload_changed", _on_reload],
			[&"hit_landed", _on_hit_landed], [&"hurt", _on_hurt], [&"downed", _on_downed], [&"revived", _on_revived]]:
		if player.has_signal(pair[0]):
			player.connect(pair[0], pair[1])
	place_player(_checkpoint, 0.0)
	if player.has_method(&"set_mode"):
		player.call(&"set_mode", &"shoot")
	var am: Variant = player.call(&"ammo") if player.has_method(&"ammo") else Vector2i(30, 30)
	_last_in_mag = (am as Vector2i).x if am is Vector2i else 30


func _spawn_hostages() -> void:
	var hs: Array = layout["points"]["hostages"]
	var n_primary := int(MissionTypes.TYPES["rescue"]["hostages"]) if obj.ptype == "rescue" else 0
	var cage := MissionBuilder.cage_mesh(int(MissionBuilder.SIDES.get(level, 8)))
	for i in hs.size():
		var h := MissionHostage.new()
		h.name = "Hostage%d" % i
		add_child(h)
		h.setup({"index": i, "primary": i < n_primary, "level": level, "pos": hs[i], "cage": cage, "seed": int(spec.get("seed", 0)) + i})
		_hostages.append(h)
		_rings_hostage.append(rings.add_ring(hs[i], Vector3.UP, float(MissionTypes.HOSTAGE["free_r"]), RING_HOSTAGE))


func _spawn_pylons() -> void:
	var ps: Array = layout["points"]["pylons"]
	var sides := int(MissionBuilder.SIDES.get(level, 8))
	_pylon_mesh = MissionBuilder.pylon_mesh(sides)
	_rubble_mesh = MissionBuilder.rubble_mesh(sides)
	for i in ps.size():
		var p := MissionPylon.new()
		p.name = "Pylon%d" % i
		p.world = self
		p.set_meta("i", i)
		p.collision_layer = 8
		p.collision_mask = 0
		var p3: Vector3 = ps[i]
		p.position = Vector3(p3.x, 0.0, p3.z)
		var cs := CollisionShape3D.new()
		var cyl := CylinderShape3D.new()
		cyl.radius = 0.6
		cyl.height = 3.2
		cs.shape = cyl
		cs.position = Vector3(0.0, 1.6, 0.0)
		p.add_child(cs)
		var mi := MeshInstance3D.new()
		mi.name = "Mesh"
		mi.mesh = _pylon_mesh
		mi.material_override = HallBuilder.material()
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		p.add_child(mi)
		add_child(p)
		_pylons.append(p)


## ตัวชนจากผัง: ของสูง/หน้าผา (ชั้น 1 แขนกล้องชน) ของเตี้ย (ชั้น 4)
func _build_colliders() -> void:
	blockers_body.collision_layer = 1
	blockers_body.collision_mask = 0
	props_body.collision_layer = 4
	props_body.collision_mask = 0
	var n := 0
	for b: Dictionary in layout["blockers"]:
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
		(blockers_body if str(b.get("layer", "")) == "shell" else props_body).add_child(cs)
		n += 1
	# กระสุนช้า: MultiMesh เดียว
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	var bm := BoxMesh.new()
	bm.size = Vector3(0.12, 0.12, 0.55)
	mm.mesh = bm
	mm.instance_count = BOLT_CAP
	mm.visible_instance_count = 0
	bolts_node.multimesh = mm
	_bolt_mat = StandardMaterial3D.new()
	_bolt_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_bolt_mat.albedo_color = _bolt_colour()
	bolts_node.material_override = _bolt_mat
	bolts_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _bolt_colour() -> Color:
	for f: Dictionary in CampaignGalaxy.FACTIONS:
		if str(f["id"]) == str(spec.get("faction", "")):
			return Color(str(f["col"])).lerp(Color.WHITE, 0.45)
	return Color(1.0, 0.5, 0.3)


## โหลดชุดโมเดลของแผนไว้ก่อน (ไม่สะดุดตอนระลอกใหม่เกิด)
func _preload_kits() -> void:
	var seen := {}
	for w: Dictionary in plan:
		for u: Dictionary in w["units"]:
			var k := str(u["kit"])
			if k != "" and not seen.has(k) and KitLibrary.has_kit(k):
				seen[k] = true
				_kits.append(load(KitLibrary.kit_path(k)))


func _on_player_moved(pos: Vector3) -> void:
	rings.set_ring(_ring_player, Vector3(pos.x, 0.0, pos.z), Vector3.UP, RING_R, _team_colour)
	if _trail.is_empty() or _trail.back().distance_to(pos) >= TRAIL_STEP:
		_trail.append(Vector3(pos.x, 0.0, pos.z))
		if _trail.size() > TRAIL_MAX:
			_trail.pop_front()
	_update_station()


func _update_station() -> void:
	if player == null or obj == null:
		return
	var pp := _player_xz()
	var s := ""
	var idx := -1
	for h in _hostages:
		if obj.hostage_state(h.index) == MissionObjectives.CAPTIVE and _xz(h.position).distance_to(pp) <= float(MissionTypes.HOSTAGE["free_r"]):
			s = "hostage"
			idx = h.index
			break
	if s == "" and _ring_beacon >= 0 and not obj.beacon_on and pp.distance_to(_xz(layout["points"]["beacon"])) <= MissionTypes.BEACON_R:
		s = "beacon"
	if s != _station or idx != _station_idx:
		_station = s
		_station_idx = idx
		station_changed.emit(s)


func _on_ammo(in_mag: int, _mag: int) -> void:
	if in_mag < _last_in_mag and not _reloading and obj != null and not _ended:
		for _i in _last_in_mag - in_mag:
			obj.shot()
		stats_changed.emit(stats())
	_last_in_mag = in_mag


func _on_reload(on: bool, _s: float) -> void:
	_reloading = on


func _on_hit_landed(info: Dictionary) -> void:
	if StringName(str(info.get("kind", ""))) == &"gun" and obj != null:
		# ยิงเสาพิธี (เป้าใหญ่นิ่ง) ไม่ทำให้ความแม่นยำสูงขึ้น
		if StringName(str(info.get("target", ""))) == &"pylon":
			obj.structure_shot()
		else:
			obj.hit()
		stats_changed.emit(stats())


func _on_hurt(info: Dictionary) -> void:
	if obj != null:
		obj.hurt(int(info.get("amount", 0)))
		stats_changed.emit(stats())


func _on_downed() -> void:
	if obj == null:
		return
	var r := obj.player_down()
	if r == "revive":
		event.emit(&"revive" if obj.revives_left > 0 else &"last_life", {"left": obj.revives_left})
	_after_event()


## ArenaPlayer ลุกที่จุดเกิดของอารีน่าเอง: ย้ายมาจุดเช็กพอยต์ของภารกิจ
func _on_revived() -> void:
	if _ended:
		return
	place_player(_checkpoint, 0.0)


func _make_current() -> void:
	var cam := camera()
	if cam != null:
		cam.make_current()


func _begun() -> bool:
	return _running


func _player_xz() -> Vector2:
	return _xz(player.global_position) if player != null else Vector2.ZERO


static func _xz(p: Vector3) -> Vector2:
	return Vector2(p.x, p.z)


static func _seg_dist2(a: Vector2, b: Vector2, p: Vector2) -> float:
	var ab := b - a
	var l2 := ab.length_squared()
	var t := 0.0 if l2 < 0.000001 else clampf((p - a).dot(ab) / l2, 0.0, 1.0)
	return (a + ab * t).distance_squared_to(p)


func _sfx(kind: StringName, at: Vector3, gain: float, pitch: float) -> void:
	var s := get_node_or_null(^"/root/Sfx") if is_inside_tree() else null
	if s != null and s.has_method(&"play"):
		s.call(&"play", kind, at, gain, pitch)
