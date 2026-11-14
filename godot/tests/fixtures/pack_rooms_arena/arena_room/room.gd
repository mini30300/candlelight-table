extends Node3D
## A neutral test room for the pack-room hook (PACK_SPEC §9, tests only; this copy also has an arena door): primitives from PropsLayer.Geo baked with
## HallBuilder.bake (two lights), one static mesh with HallBuilder.material() (1 draw call), one small "anim part" cube
## that bobs in _process on hi/mid only (still on lo/min and while inactive), one extra crate blocker. Every call the
## public side makes is recorded in `calls` (method -> list of arguments) for the tests.

const LIGHTS: PackedVector3Array = [Vector3(-3.0, 2.5, -3.0), Vector3(3.0, 2.5, 2.0)]
const CRATE := Vector2(-4.5, 4.0)
const CRATE_R := 0.5
const CRATE_H := 1.2

var calls: Dictionary = {}
var level := ""
var active := true
var ctx: Dictionary = {}
var static_mesh: MeshInstance3D
var anim_part: MeshInstance3D
var _t := 0.0
var _half := Vector2(6.0, 8.0)
var _ceil := 5.0


func _note(m: String, args: Array = []) -> void:
	if not calls.has(m):
		calls[m] = []
	(calls[m] as Array).append(args)


func setup(c: Dictionary) -> void:
	_note("setup", [c])
	ctx = c
	var data: Dictionary = c.get("data", {})
	var h: Array = data.get("half", [6.0, 8.0])
	_half = Vector2(float(h[0]), float(h[1]))
	_ceil = float(data.get("ceil", 5.0))
	static_mesh = MeshInstance3D.new()
	static_mesh.name = "Static"
	static_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	static_mesh.material_override = HallBuilder.material()
	add_child(static_mesh)
	anim_part = MeshInstance3D.new()
	anim_part.name = "AnimPart"
	anim_part.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	anim_part.material_override = HallBuilder.material()
	var g := PropsLayer.Geo.new()
	g.box(Vector3.ZERO, Vector3(0.15, 0.15, 0.15), HallBuilder.HOLO)
	anim_part.mesh = g.mesh()
	anim_part.position = Vector3(-3.0, 1.6, -3.0)
	add_child(anim_part)
	set_process(false)


func apply_level(l: String) -> void:
	_note("apply_level", [l])
	level = l
	var g := PropsLayer.Geo.new()
	var hx := _half.x
	var hz := _half.y
	g.box(Vector3(0.0, -0.05, 0.0), Vector3(hx, 0.05, hz), HallBuilder.DECK)
	g.box(Vector3(0.0, _ceil * 0.5, -hz - 0.1), Vector3(hx, _ceil * 0.5, 0.1), HallBuilder.STEEL)
	g.box(Vector3(0.0, _ceil * 0.5, hz + 0.1), Vector3(hx, _ceil * 0.5, 0.1), HallBuilder.STEEL)
	g.box(Vector3(-hx - 0.1, _ceil * 0.5, 0.0), Vector3(0.1, _ceil * 0.5, hz), HallBuilder.STEEL_DARK)
	g.box(Vector3(hx + 0.1, _ceil * 0.5, 0.0), Vector3(0.1, _ceil * 0.5, hz), HallBuilder.STEEL_DARK)
	g.box(Vector3(-3.0, 0.5, -3.0), Vector3(0.6, 0.5, 0.6), HallBuilder.BRASS)
	var sides := {"hi": 14, "mid": 12, "lo": 10, "min": 8}.get(l, 12) as int
	g.prism(3.0, 0.0, -3.0, 0.8, 1.0, sides, HallBuilder.BRONZE)
	g.prism(CRATE.x, 0.0, CRATE.y, CRATE_R, CRATE_H, sides, HallBuilder.IRON)
	# กรอบประตูกลับดาดฟ้า
	g.box(Vector3(-1.35, 1.6, 7.85), Vector3(0.15, 1.6, 0.15), HallBuilder.STEEL)
	g.box(Vector3(1.35, 1.6, 7.85), Vector3(0.15, 1.6, 0.15), HallBuilder.STEEL)
	g.box(Vector3(0.0, 3.3, 7.85), Vector3(1.5, 0.15, 0.15), HallBuilder.STEEL)
	g.box(Vector3(0.0, 1.6, 7.95), Vector3(1.2, 1.6, 0.05), HallBuilder.AIRLOCK_GLOW)
	HallBuilder.bake(g, LIGHTS)
	static_mesh.mesh = g.mesh()
	_sync_process()


func blockers() -> Array:
	_note("blockers")
	return [{"kind": "cyl", "c": CRATE, "r": CRATE_R, "y0": 0.0, "y1": CRATE_H, "tag": "crate"}]


func station_near(id: String) -> void:
	_note("station_near", [id])


func station_used(id: String) -> void:
	_note("station_used", [id])


func set_active(on: bool) -> void:
	_note("set_active", [on])
	active = on
	_sync_process()


func set_english(on: bool) -> void:
	_note("set_english", [on])


func counts() -> Dictionary:
	return {"static_meshes": 1, "static_tris": HallBuilder.tris(static_mesh.mesh as ArrayMesh) if static_mesh.mesh != null else 0,
		"anim_parts": 1, "shaders": 0}


func _sync_process() -> void:
	var on := active and (level == "hi" or level == "mid")
	set_process(on)
	if not on and anim_part != null:
		anim_part.position.y = 1.6


func _process(delta: float) -> void:
	_t += delta
	anim_part.position.y = 1.6 + sin(_t * 2.0) * 0.1
