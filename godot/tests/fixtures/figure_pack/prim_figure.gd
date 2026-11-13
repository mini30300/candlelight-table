extends Node3D
## A primitive figure for the figure-pack tests (PACK_SPEC §6): one capsule (1 draw), clips built in code, every method
## of the figure contract (ARENA_SPEC §9.1) plus the optional set_fade and deck_speeds, and plain fields the tests read
## (role, level, weapon, fade, last_move = (speed, running), zero_moves, calls = method -> count). No model files.
## set_move picks idle / walk / run from the speed alone and plays walk / run at speed / the clip's "speed" meta; on min,
## and on lo for the deck role (PACK_SPEC §3.2), the idle clip is paused on its first frame at once (a still pose).

signal clip_event(kind: StringName)

const HEIGHT := 1.7
const RADIUS := 0.3
const SPEEDS := Vector2(1.5, 4.0)          # walk, run (m/s) the walk and run clips were made for
const LIB := "prim"
const LOOPS := {"idle": 2.0, "walk": 0.8, "run": 0.5}
const CLIPS := {"fire": 0.1, "reload": 1.6, "punch": 0.25, "swing": 0.3, "hit": 0.25, "die": 0.6, "attack": 0.6,
	"hit_heavy": 0.5}
const BASE := Vector3(0.0, HEIGHT * 0.5, 0.0)

static var _mesh: CapsuleMesh
static var _lib: AnimationLibrary
static var _mats: Dictionary = {}          # team colour -> opaque material (shared by every instance)

var role: StringName = &"player"
var level := "mid"
var weapon: StringName = &"none"
var fade := 1.0
var flash := 0.0
var telegraph := 0.0
var team_colour := Color(0.28, 0.52, 0.84)
var last_move := Vector2(-1.0, 0.0)
var zero_moves := 0
var loop: StringName = &"idle"
var calls: Dictionary = {}

var body: MeshInstance3D
var ap: AnimationPlayer
var muzzle_node: Marker3D
var _anchors: Dictionary = {}
var _oneshot: StringName = &""
var _rate := 1.0
var _dead := false
var _fx_mat: StandardMaterial3D


func _init() -> void:
	body = MeshInstance3D.new()
	body.name = "Body"
	body.mesh = _capsule()
	body.position = BASE
	body.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(body)
	muzzle_node = Marker3D.new()
	muzzle_node.name = "Muzzle"
	muzzle_node.position = Vector3(-0.35, 1.2, 0.45)
	add_child(muzzle_node)
	for a in [[&"head", Vector3(0.0, 1.55, 0.0)], [&"chest", Vector3(0.0, 1.15, 0.0)], [&"hand_r", Vector3(-0.35, 1.0, 0.15)],
			[&"hand_l", Vector3(0.35, 1.0, 0.15)]]:
		var m := Marker3D.new()
		m.name = "Anchor_" + String(a[0])
		m.position = a[1]
		add_child(m)
		_anchors[a[0]] = m
	ap = AnimationPlayer.new()
	ap.name = "AnimationPlayer"
	ap.add_animation_library(LIB, _library())
	ap.animation_finished.connect(_on_finished)
	add_child(ap)
	_update_material()


func setup(opts: Dictionary) -> void:
	_count("setup")
	role = StringName(str(opts.get("role", "player")))
	team_colour = opts.get("team_colour", team_colour)
	_update_material()
	apply_level(str(opts.get("level", level)))


func metrics() -> Dictionary:
	_count("metrics")
	return {"height": HEIGHT, "radius": 0.55 if role == &"enemy" else RADIUS, "eye": 1.5, "shoulder": 1.3}


func clip_names() -> Dictionary:
	var out := {}
	for k in LOOPS.keys() + CLIPS.keys():
		out[k] = PackedStringArray([k])
	return out


func play(logical: StringName, speed: float = 1.0) -> float:
	_count("play")
	var k := String(logical)
	speed = maxf(speed, 0.01)
	if LOOPS.has(k):
		_dead = false
		_oneshot = &""
		loop = logical
		_rate = speed
		_start_loop()
		return float(LOOPS[k]) / speed
	if not CLIPS.has(k) or (_dead and k != "die"):
		return 0.0
	_oneshot = logical
	ap.play(LIB + "/" + k)
	ap.speed_scale = speed
	if k == "fire":
		clip_event.emit(&"shot")
	return float(CLIPS[k]) / speed


func set_move(speed: float, running: bool) -> void:
	_count("set_move")
	last_move = Vector2(speed, 1.0 if running else 0.0)
	if speed == 0.0 and not running:
		zero_moves += 1
	if _dead:
		return
	loop = &"idle" if speed < 0.05 else (&"run" if speed > (SPEEDS.x + SPEEDS.y) * 0.5 else &"walk")
	_rate = 1.0 if loop == &"idle" else speed / float(_library().get_animation(String(loop)).get_meta("speed", 1.0))
	if _oneshot == &"":
		_start_loop()


func set_aim(_pitch: float) -> void:
	_count("set_aim")


func set_weapon(id: StringName) -> void:
	_count("set_weapon")
	weapon = id


func set_flash(a: float) -> void:
	_count("set_flash")
	flash = clampf(a, 0.0, 1.0)
	_update_material()


func set_telegraph(a: float) -> void:
	_count("set_telegraph")
	telegraph = clampf(a, 0.0, 1.0)
	_update_material()


func set_fade(a: float) -> void:
	_count("set_fade")
	fade = clampf(a, 0.0, 1.0)
	_update_material()


func deck_speeds() -> Vector2:
	_count("deck_speeds")
	return SPEEDS


func muzzle() -> Node3D:
	return muzzle_node


func anchor(n: StringName) -> Node3D:
	return _anchors.get(n)


func apply_level(l: String) -> void:
	_count("apply_level")
	level = l
	if _oneshot == &"" and not _dead:
		_start_loop()


func _start_loop() -> void:
	var name := LIB + "/" + String(loop)
	if loop == &"idle" and (level == "min" or (level == "lo" and role == &"deck")):
		if ap.assigned_animation != name:
			ap.play(name)
		ap.seek(0.0, true)
		ap.pause()
		ap.speed_scale = 1.0
		return
	if ap.current_animation != name or not ap.is_playing():
		ap.play(name)
	ap.speed_scale = _rate


func _on_finished(_name: StringName) -> void:
	if _oneshot == &"die":
		_dead = true
		clip_event.emit(&"thud")
		return
	_oneshot = &""
	_start_loop()


func _count(m: String) -> void:
	calls[m] = int(calls.get(m, 0)) + 1


func _update_material() -> void:
	if fade >= 0.999 and flash <= 0.001 and telegraph <= 0.001:
		body.material_override = _opaque(team_colour)
		return
	if _fx_mat == null:
		_fx_mat = _opaque(team_colour).duplicate() as StandardMaterial3D
	var c := team_colour.lerp(Color.WHITE, flash * 0.6).lerp(Color(0.9, 0.1, 0.05), telegraph * 0.5)
	_fx_mat.albedo_color = Color(c.r, c.g, c.b, fade)
	_fx_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA if fade < 0.999 else BaseMaterial3D.TRANSPARENCY_DISABLED
	body.material_override = _fx_mat


static func _opaque(c: Color) -> StandardMaterial3D:
	var key := c.to_html(false)
	if not _mats.has(key):
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.albedo_color = c
		_mats[key] = m
	return _mats[key]


static func _capsule() -> CapsuleMesh:
	if _mesh == null:
		_mesh = CapsuleMesh.new()
		_mesh.radius = RADIUS
		_mesh.height = HEIGHT
		_mesh.radial_segments = 12
		_mesh.rings = 4
	return _mesh


## idle / walk / run loops (walk and run carry the "speed" meta) and the one-shots, each a position and a rotation
## track on Body
static func _library() -> AnimationLibrary:
	if _lib != null:
		return _lib
	_lib = AnimationLibrary.new()
	var up := BASE + Vector3(0.0, 0.03, 0.0)
	var hop := BASE + Vector3(0.0, 0.08, 0.0)
	var keys := {
		"idle": [[BASE, up, BASE], [Vector3.ZERO, Vector3.ZERO]],
		"walk": [[BASE, up, BASE, up, BASE], [Vector3(0.05, 0, 0.06), Vector3(0.05, 0, -0.06), Vector3(0.05, 0, 0.06)]],
		"run": [[BASE, hop, BASE, hop, BASE], [Vector3(0.2, 0, 0.1), Vector3(0.2, 0, -0.1), Vector3(0.2, 0, 0.1)]],
		"fire": [[BASE + Vector3(0, 0, -0.05), BASE], [Vector3.ZERO, Vector3.ZERO]],
		"reload": [[BASE, BASE], [Vector3.ZERO, Vector3(0.3, 0, 0), Vector3.ZERO]],
		"punch": [[BASE, BASE + Vector3(0, 0, 0.2), BASE], [Vector3.ZERO, Vector3.ZERO]],
		"swing": [[BASE, BASE], [Vector3(0, -0.6, 0), Vector3(0, 0.6, 0), Vector3.ZERO]],
		"hit": [[BASE, BASE], [Vector3.ZERO, Vector3(-0.25, 0, 0), Vector3.ZERO]],
		"die": [[BASE, Vector3(0.0, RADIUS, 0.0)], [Vector3.ZERO, Vector3(0, 0, 1.45)]],
		"attack": [[BASE, BASE + Vector3(0, 0, 0.3), BASE], [Vector3(-0.3, 0, 0), Vector3(0.4, 0, 0), Vector3.ZERO]],
		"hit_heavy": [[BASE, BASE + Vector3(0, 0, -0.2), BASE], [Vector3.ZERO, Vector3(-0.5, 0, 0), Vector3.ZERO]],
	}
	for k: String in keys:
		var looped := LOOPS.has(k)
		var a := Animation.new()
		a.length = float(LOOPS[k]) if looped else float(CLIPS[k])
		a.loop_mode = Animation.LOOP_LINEAR if looped else Animation.LOOP_NONE
		var tp := a.add_track(Animation.TYPE_POSITION_3D)
		a.track_set_path(tp, NodePath("Body"))
		var tr := a.add_track(Animation.TYPE_ROTATION_3D)
		a.track_set_path(tr, NodePath("Body"))
		var pos: Array = keys[k][0]
		var rot: Array = keys[k][1]
		for i in pos.size():
			a.position_track_insert_key(tp, a.length * i / (pos.size() - 1), pos[i])
		for i in rot.size():
			a.rotation_track_insert_key(tr, a.length * i / (rot.size() - 1), Quaternion.from_euler(rot[i]))
		if k == "walk":
			a.set_meta("speed", SPEEDS.x)
		elif k == "run":
			a.set_meta("speed", SPEEDS.y)
		_lib.add_animation(k, a)
	return _lib
