extends "res://tests/testing.gd"
## The dodge (ARENA_SPEC §9.5, owner request 13 Nov): ArenaData.DODGE numbers, the pure ArenaCombat dodge checks,
## the arena sound map (ArenaData.SOUNDS → the old page's DEF kinds), and a real ArenaPlayer driven tick by tick:
## Space / press(&"dodge") dashes 3.8 m in 0.3 s (backwards with no input, toward the stick otherwise), the first
## 0.25 s are invulnerable, a second dodge waits for the 0.7 s cooldown after the dash, no dodge while down, dust on
## mid and none on min, dodge_changed says dash / cool / ready. Figure hooks H8 begin_dodge and H9 uses_strafe with
## tests/fixtures/figure_pack/heavy_figure.gd: the player faces where this figure moves in shoot mode, turns it to the
## aim while firing and for 0.6 s after, and sends begin_dodge the direction in its own frame. The egg's dodge clip.

const EGG := "res://scenes/arena/egg_gunner.gd"
const HEAVY := "res://tests/fixtures/figure_pack/heavy_figure.gd"
const PLAYER_SCENE := "res://scenes/arena/arena_player.tscn"
const DT := 1.0 / 60.0
## the old page's DEF names (audio/README.md)
const DEF_KINDS: PackedStringArray = ["shot", "heavy", "laser", "zap", "flame", "bow", "bolt", "catapult", "throw",
	"swing", "hit", "clang", "boom", "die", "dice", "charge", "saw", "vshield", "wind", "heal", "turn", "end", "bolter",
	"hbolter", "gatling", "sniper", "cannon", "rocket", "plasma", "melta", "beam", "warp", "chain", "power", "hammer",
	"claw", "bite", "stomp", "quake", "ricochet", "debris", "ui"]
const SOUND_IDS: PackedStringArray = ["gun", "reload", "empty", "punch", "punch_hit", "saw_idle", "saw_rev", "saw_hit",
	"beast_roar", "beast_strike", "beast_miss", "beast_hit", "beast_death", "switch", "reset", "dodge"]


func test_dodge_numbers() -> void:
	var d := ArenaData.DODGE
	for k in ["distance", "time", "invuln", "cooldown", "ease", "hold_aim"]:
		assert_true(d.has(k) and float(d[k]) > 0.0, "DODGE.%s is a positive number" % k, d.get(k))
	assert_true(float(d["distance"]) >= 3.5 and float(d["distance"]) <= 4.0, "the dash is 3.5–4 m", d["distance"])
	assert_within(float(d["time"]), 0.3, 0.001, "the dash takes 0.3 s")
	assert_true(float(d["invuln"]) < float(d["time"]), "invulnerable only for the first part of the dash", d["invuln"])
	assert_within(float(d["cooldown"]), 0.7, 0.001, "cooldown 0.7 s after the dash")
	assert_true(float(d["ease"]) < 1.0, "the speed never goes backwards (ease < 1)", d["ease"])
	assert_eq(str(d["th"]), "หลบ", "the button label is หลบ")
	assert_true(I18n.lookup("หลบ") == "Dodge", "…with the English entry Dodge", I18n.lookup("หลบ"))


func test_dodge_math() -> void:
	var dist := float(ArenaData.DODGE["distance"])
	var dur := float(ArenaData.DODGE["time"])
	assert_within(ArenaCombat.dodge_travel(0.0), 0.0, 1e-6, "no travel at the start")
	assert_within(ArenaCombat.dodge_travel(dur), dist, 1e-5, "the whole dash covers distance")
	assert_within(ArenaCombat.dodge_travel(dur + 1.0), dist, 1e-5, "and no more after it")
	var prev := 0.0
	var sum := 0.0
	var mono := true
	for i in 300:
		var t := dur * (i + 1) / 300.0
		var s := ArenaCombat.dodge_travel(t)
		mono = mono and s > prev
		prev = s
		sum += ArenaCombat.dodge_speed(t - dur / 600.0) * dur / 300.0
	assert_true(mono, "travel only grows")
	assert_within(sum, dist, 0.01, "the speed curve integrates to the distance")
	assert_true(ArenaCombat.dodge_speed(0.0) > ArenaCombat.dodge_speed(dur * 0.9) and ArenaCombat.dodge_speed(dur * 0.99) > 0.0,
		"fast at the start, slower but still forward at the end")
	assert_eq(ArenaCombat.dodge_speed(dur), 0.0, "zero after the dash")
	assert_eq(ArenaCombat.dodge_speed(-0.1), 0.0, "zero before it")
	assert_eq(ArenaCombat.dodge_dir(Vector2.ZERO), Vector2(0, -1), "no input: backwards")
	assert_eq(ArenaCombat.dodge_dir(Vector2(0.05, 0.0)), Vector2(0, -1), "a stick inside 0.1: backwards")
	assert_true(ArenaCombat.dodge_dir(Vector2(0.4, 0.4)).distance_to(Vector2(0.7071, 0.7071)) < 1e-3, "a direction is normalised")
	assert_true(ArenaCombat.dodge_invulnerable(0.0) and ArenaCombat.dodge_invulnerable(0.24), "invulnerable from 0 to 0.25 s")
	assert_false(ArenaCombat.dodge_invulnerable(0.25) or ArenaCombat.dodge_invulnerable(-0.01), "not after 0.25 s or before the dash")
	assert_true(ArenaCombat.can_dodge(0.7, 0.0, true, false), "ready 0.7 s after the last dash ended")
	assert_false(ArenaCombat.can_dodge(0.69, 0.0, true, false), "not before")
	assert_false(ArenaCombat.can_dodge(INF, 0.0, false, false), "never while down")
	assert_false(ArenaCombat.can_dodge(INF, 0.0, true, true), "never during a dash")
	assert_true(ArenaCombat.faces_aim(true, true, INF), "acting: face the aim even while moving")
	assert_true(ArenaCombat.faces_aim(false, false, INF), "standing: face the aim")
	assert_true(ArenaCombat.faces_aim(false, true, 0.59), "moving 0.59 s after acting: still the aim")
	assert_false(ArenaCombat.faces_aim(false, true, 0.6), "moving 0.6 s after acting: face where it moves")


func test_sound_map() -> void:
	for id in SOUND_IDS:
		var sp := ArenaSound.spec(id)
		assert_true(sp.size() == 3 and DEF_KINDS.has(str(sp[0])) and float(sp[1]) > 0.0 and float(sp[2]) > 0.0,
			"sound %s maps to a DEF kind with gain and pitch" % id, sp)
	assert_eq(ArenaData.SOUNDS.size(), SOUND_IDS.size(), "no other arena sounds")
	assert_eq(ArenaSound.spec("nope"), [], "an unknown sound is []")
	assert_false(ArenaSound.play(null, "gun"), "no node: silent, no crash")
	assert_false(ArenaSound.play(Node.new(), "gun"), "a node outside the tree: silent")
	if FileAccess.file_exists("res://assets/sfx/sfx.json"):
		var j: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://assets/sfx/sfx.json"))
		var kinds: Dictionary = (j as Dictionary).get("kinds", {}) if j is Dictionary else {}
		for id in SOUND_IDS:
			assert_true(kinds.has(str(ArenaSound.spec(id)[0])), "sound %s is baked in sfx.json" % id, ArenaSound.spec(id))


func _player(fig: Node3D, level: String) -> Node3D:
	var tree := Engine.get_main_loop() as SceneTree
	var p: Node3D = (load(PLAYER_SCENE) as PackedScene).instantiate()
	tree.root.add_child(p)
	p.call("setup", null, {"figure": fig, "level": level})
	p.call("place", Vector3(0, 0, 40), 0.0, PI)      # far from everything, facing +z
	return p


func _free(p: Node3D) -> void:
	p.get_parent().remove_child(p)
	p.free()


func _ticks(p: Node3D, n: int) -> void:
	for i in n:
		p.call("_physics_process", DT)


## the dash direction × the distance its velocity curve covers (ArenaCombat.dodge_travel), then n ticks
func _dash(p: Node3D, n: int) -> Vector3:
	var dir: Vector3 = p.get("_dodge_dir")
	_ticks(p, n)
	return dir * ArenaCombat.dodge_travel(float(ArenaData.DODGE["time"]))


func test_player_dodge() -> void:
	if not ResourceLoader.exists(PLAYER_SCENE):
		assert_true(false, "the arena player scene loads")
		return
	var egg: Node3D = (load(EGG) as Script).new()
	var p := _player(egg, "mid")
	assert_true(InputMap.has_action(&"dodge"), "the player registers a dodge action")
	var space := false
	for e in InputMap.action_get_events(&"dodge"):
		space = space or (e is InputEventKey and (e as InputEventKey).physical_keycode == KEY_SPACE)
	assert_true(space, "…on the physical Space key")
	var states: Array[StringName] = []
	p.connect("dodge_changed", func(s: StringName) -> void: states.append(s))
	assert_true(bool(p.call("strafes")), "the egg strafes (no uses_strafe)")
	assert_true(bool(p.call("dodge")), "a dodge starts")
	assert_true(bool(p.call("dodging")) and bool(egg.call("dodging")), "the player dashes and the egg plays its dodge (H8)")
	assert_true(int((p.get("fx") as Node).call("alive")) > 0, "mid: a dust puff")
	var r: Dictionary = p.call("take_hit", {"amount": 18})
	assert_true(int(r["applied"]) == 0 and bool(r.get("dodged", false)) and int(p.call("hp")) == 100, "a strike in the first 0.25 s misses", r)
	assert_false(bool(p.call("dodge")), "no second dodge during the dash")
	# (the unit runner has no physics step, so the distance is the dash velocity summed; the flow test walks it for real)
	var moved := _dash(p, 18)
	assert_within(moved.length(), float(ArenaData.DODGE["distance"]), 0.1, "the dash covers 3.8 m")
	assert_true(moved.z < -3.6 and absf(moved.x) < 0.05, "…backwards (no input), the way it faces is +z", moved)
	assert_false(bool(p.call("dodging")), "the dash is over")
	assert_false(bool(p.call("dodge")), "the cooldown blocks a new dodge")
	_ticks(p, 30)
	assert_false(bool(p.call("dodge")), "…still 0.5 s after the dash")
	_ticks(p, 13)
	assert_eq(states, [&"dash", &"cool", &"ready"] as Array[StringName], "dodge_changed: dash, cool, ready")
	assert_within(float(p.call("dodge_ready_ratio")), 1.0, 1e-4, "ready ratio 1")
	# the stick to the right in shoot mode: the dash goes to the camera's right, the egg keeps facing the camera
	p.call("set_mode", &"shoot")
	_ticks(p, 20)
	var rig: Node = p.call("camera_rig")
	var right: Vector3 = rig.call("right_flat")
	p.call("set_stick", Vector2(1, 0))
	assert_true(bool(p.call("dodge")), "a dodge with the stick")
	var m2 := _dash(p, 18)
	p.call("set_stick", Vector2.ZERO)
	assert_true(m2.dot(right) > 3.6, "…goes to the camera's right", m2.dot(right))
	assert_within(absf(angle_difference(float(p.get("face")), float(rig.get("yaw")) + PI)), 0.0, 0.01, "…and the egg still faces the aim")
	_ticks(p, 50)
	# a hit after the invulnerable part lands
	assert_true(bool(p.call("dodge")), "dodge again")
	_ticks(p, 16)
	r = p.call("take_hit", {"amount": 18})
	assert_eq(int(r["applied"]), 18, "a strike 0.27 s into the dash lands")
	_ticks(p, 60)
	# down: no dodge
	p.set("_invuln", 0.0)
	p.call("take_hit", {"amount": 1000})
	assert_true(bool(p.call("is_downed")), "a lethal hit downs the player")
	assert_false(bool(p.call("dodge")), "no dodge while down")
	p.call("heal_full")
	p.call("set_mode", &"walk")
	_free(p)
	# min: no dust
	var egg2: Node3D = (load(EGG) as Script).new()
	var pm := _player(egg2, "min")
	(pm.get("fx") as Node).call("clear")
	assert_true(bool(pm.call("dodge")), "min: a dodge")
	assert_eq(int((pm.get("fx") as Node).call("alive")), 0, "min: no dust")
	_free(pm)


func test_heavy_figure_hooks() -> void:
	if not ResourceLoader.exists(PLAYER_SCENE):
		return
	var fig: Node3D = (load(HEAVY) as Script).new()
	var p := _player(fig, "mid")
	assert_true(bool(p.get("_fig_dodge")) and not bool(p.call("strafes")), "setup cached H8 and H9 (uses_strafe false)")
	p.call("set_mode", &"shoot")
	_ticks(p, 20)
	var rig: Node = p.call("camera_rig")
	var aim := float(rig.get("yaw")) + PI
	assert_within(absf(angle_difference(float(p.get("face")), aim)), 0.0, 0.02, "standing: it faces the aim")
	p.call("set_stick", Vector2(1, 0))
	_ticks(p, 40)
	var right: Vector3 = rig.call("right_flat")
	var face := float(p.get("face"))
	assert_true(Vector3(sin(face), 0, cos(face)).dot(right) > 0.95, "moving right in shoot mode: it turns to face where it moves", face)
	assert_true((fig.get("last_dir") as Vector2).y > 0.9, "…so the figure walks forward (local_dir y > 0.9)", fig.get("last_dir"))
	p.call("press", &"fire", true)
	_ticks(p, 20)
	assert_within(absf(angle_difference(float(p.get("face")), aim)), 0.0, 0.05, "firing while moving: it turns to the aim")
	p.call("press", &"fire", false)
	_ticks(p, 24)
	assert_within(absf(angle_difference(float(p.get("face")), aim)), 0.0, 0.05, "0.4 s after firing it still holds the aim")
	_ticks(p, 40)
	face = float(p.get("face"))
	assert_true(Vector3(sin(face), 0, cos(face)).dot(right) > 0.95, "after 0.6 s it faces where it moves again")
	(fig.get("calls") as Dictionary).clear()
	assert_true(bool(p.call("dodge")), "a dodge")
	var c: Dictionary = fig.get("calls")
	var ld: Dictionary = fig.get("last_dodge")
	assert_eq(int(c.get("begin_dodge", 0)), 1, "begin_dodge is called once (H8)")
	assert_true((ld.get("dir", Vector2.ZERO) as Vector2).y > 0.95 and absf(float(ld.get("duration", 0)) - 0.3) < 1e-4,
		"…with the direction in its own frame (it turned to the dash: forward) and 0.3 s", ld)
	_ticks(p, 30)
	p.call("set_stick", Vector2.ZERO)
	_ticks(p, 60)
	assert_within(absf(angle_difference(float(p.get("face")), aim)), 0.0, 0.05, "standing again: it turns back to the aim")
	p.call("set_mode", &"walk")
	_free(p)


func test_egg_dodge_clip() -> void:
	for level in ["mid", "min"]:
		var e: Node3D = (load(EGG) as Script).new()
		e.call("setup", {"role": &"player", "level": level})
		var body := e.get("egg") as Node3D
		e.call("begin_dodge", Vector2(1, 0), 0.3)
		for i in 5:
			e.call("_process", DT)
		assert_true(body.scale.y < 0.95, "%s: the egg tucks (squashes) early in the dodge" % level, body.scale)
		for i in 7:
			e.call("_process", DT)
		assert_true(body.rotation.z > 0.25 and body.position.y < -0.05, "%s: mid-dash it leans toward the dodge and dips" % level,
			[body.rotation, body.position])
		for i in 8:
			if e.is_processing():
				e.call("_process", DT)
		assert_false(bool(e.call("dodging")), "%s: the clip ends with the dash" % level)
		assert_true(body.scale.is_equal_approx(Vector3.ONE) and absf(body.rotation.z) < 1e-4 and absf(body.position.y) < 1e-4,
			"%s: and it recovers to the stance" % level, [body.scale, body.rotation, body.position])
		assert_false(e.is_processing(), "%s: nothing processes after it" % level)
		e.free()
