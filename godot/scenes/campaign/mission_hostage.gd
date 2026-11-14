class_name MissionHostage
extends Node3D
## ตัวประกันหนึ่งคน (CAMPAIGN_SPEC §2.4, track C): ยืนในกรง → ผู้เล่นยืนในวงปล่อย (กด E) ครบเวลา → เดินตามรอยเท้าผู้เล่น
## → ถึงวงจุดรับ = รอด · ศัตรูตีได้ตอนเดินตาม (พลังชีวิต MissionTypes.HOSTAGE.hp) · ไม่มีตัวชน (เดินตามรอยที่ผู้เล่นเดินผ่านมาแล้ว
## จึงไม่ทะลุของ) กระสุนผู้เล่นไม่โดน · ตัวละคร KitWalker ชุดแรกที่มีใน MissionRoster.HOSTAGE_KITS ไม่มีเลย = ไข่ของดาดฟ้า
## โลกเรียก step() เฉพาะตอนเดินตาม · ไม่มีข้อความไทย

signal hp_changed(hp: int, hp_max: int)

var index := 0
var primary := true
var level := "mid"
var _figure: Node3D
var _cage: MeshInstance3D
var _hp := 100
var _hp_max := 100
var _alive := true
var _yaw := 0.0
var _moving := false
var _skinned := false


## opts: {"index", "primary", "level", "pos": Vector3, "cage": ArrayMesh, "seed"}
func setup(opts: Dictionary) -> void:
	index = int(opts.get("index", 0))
	primary = bool(opts.get("primary", true))
	level = str(opts.get("level", "mid"))
	_hp_max = int(MissionTypes.HOSTAGE["hp"])
	_hp = _hp_max
	var p: Vector3 = opts.get("pos", Vector3.ZERO)
	position = Vector3(p.x, 0.0, p.z)
	var kit := ""
	for k in MissionRoster.HOSTAGE_KITS:
		if KitLibrary.has_kit(k):
			kit = k
			break
	var kw := KitWalker.new()
	kw.walk_kit = kit
	kw.name = "Figure"
	add_child(kw)
	kw.call(&"setup", {"role": &"deck", "level": level, "seed": int(opts.get("seed", 1))})
	_figure = kw
	_skinned = kit != ""
	_yaw = float(opts.get("yaw", PI))
	rotation.y = _yaw
	var cm: Variant = opts.get("cage")
	if cm is ArrayMesh:
		_cage = MeshInstance3D.new()
		_cage.name = "Cage"
		_cage.mesh = cm
		_cage.material_override = HallBuilder.material()
		_cage.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(_cage)


func apply_level(l: String) -> void:
	level = l
	if _figure != null and _figure.has_method(&"apply_level"):
		_figure.call(&"apply_level", l)


func hp() -> int:
	return _hp


func is_alive() -> bool:
	return _alive


func skinned() -> bool:
	return _skinned


func caged() -> bool:
	return _cage != null and _cage.visible


## ปล่อยแล้ว: กรงหาย
func set_freed() -> void:
	if _cage != null:
		_cage.visible = false


## โดนศัตรู: คืน true เมื่อเพิ่งตาย
func take_damage(amount: int) -> bool:
	if not _alive or amount <= 0:
		return false
	_hp = maxi(_hp - amount, 0)
	hp_changed.emit(_hp, _hp_max)
	if _figure != null and _figure.has_method(&"set_flash"):
		_figure.call(&"set_flash", 0.8)
		get_tree().create_timer(0.08).timeout.connect(func() -> void:
			if is_instance_valid(_figure):
				_figure.call(&"set_flash", 0.0))
	if _hp <= 0:
		_alive = false
		if _figure != null:
			_figure.call(&"play", &"die", 1.0)
		return true
	return false


## เดินไปหาจุด goal (รอยของผู้เล่น) ด้วยความเร็วคงที่ หยุดเมื่อใกล้กว่า stop
func step(dt: float, goal: Vector3, stop: float) -> void:
	if not _alive:
		return
	var d := Vector3(goal.x - position.x, 0.0, goal.z - position.z)
	var dist := d.length()
	var spd := 0.0
	if dist > stop:
		spd = minf(float(MissionTypes.HOSTAGE["speed"]), (dist - stop) / maxf(dt, 0.0001))
		position += d / dist * spd * dt
		_yaw = atan2(d.x, d.z)
		rotation.y = _yaw
	var moving := spd > 0.05
	if moving or moving != _moving:
		if _figure != null:
			_figure.call(&"set_move", spd, spd > 3.0)
	_moving = moving


func set_paused(on: bool) -> void:
	if _figure != null:
		_figure.process_mode = Node.PROCESS_MODE_DISABLED if on else Node.PROCESS_MODE_INHERIT
