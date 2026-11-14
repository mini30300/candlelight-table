extends "res://tests/testing.gd"
## Round D (owner, 14 Nov; ARENA_SPEC §9.5–§9.6): the weapons arena plays the figure picked in the dressing room.
## Selection -> figure (ArenaActors.player_figure / scheme_of / player_preload): the egg -> EggGunner, a battle-table kit
## -> KitFighter on that kit, a pack figure -> that entry's script dressed with the chosen scheme after setup (H10), a
## pack entry without schemes stays in its own colours, a deck-only pack figure falls back to the default player.
## The non-strafing controls: A/D or the stick's x turn the body and the camera at 150 deg/s with no sideways motion,
## W/S walk forward/back along the way it faces (legs (0, 1) / (0, -1)), a dodge goes forward/back or backwards, the
## egg still strafes. KitFighter: the arena contract, its weapon's fire clip (fire / fire_heavy / pistol), its sword
## clips, the aim layer, the muzzle in front of a hand, the reversed walk, the dodge lean, the paint table, and on min a
## still pose with no processing.

const STORE := "user://test_arena_selection.cfg"
const PAINT_LIST := "res://tests/fixtures/figure_pack_paint/figures.json"
const PAINT := "res://tests/fixtures/figure_pack_paint/paint_figure.gd"
const NONE_LIST := "res://tests/unit/fixtures/no_such_pack/figures.json"
const NONE_PACK := "res://tests/unit/fixtures/no_such_pack/pack.json"
const EGG := "res://scenes/arena/egg_gunner.gd"
const HEAVY := "res://tests/fixtures/figure_pack/heavy_figure.gd"
const PLAYER_SCENE := "res://scenes/arena/arena_player.tscn"
const DT := 1.0 / 60.0


func _use(list: String) -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(STORE))
	Figures.store_path = STORE
	Figures.pack_list = list
	Figures.pack_manifest = NONE_PACK


func _restore() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(STORE))
	Figures.store_path = ""
	Figures.pack_list = Figures.PACK_LIST
	Figures.pack_manifest = ArenaActors.PACK_MANIFEST


func _script_of(n: Object) -> String:
	if n == null or n.get_script() == null:
		return ""
	return (n.get_script() as Script).resource_path


func _first_kit() -> String:
	for e in Figures.list():
		if str(e["kind"]) == "kit":
			return str(e["id"])
	return ""


func test_selection_to_figure() -> void:
	_use(PAINT_LIST)
	var egg := ArenaActors.player_figure({"figure": "egg", "scheme": "pink"})
	assert_eq(_script_of(egg), EGG, "the egg -> the egg gunner")
	assert_eq(ArenaActors.scheme_of({"figure": "egg", "scheme": "pink"}), "original", "the egg takes no scheme")
	assert_eq(ArenaActors.player_preload({"figure": "egg"}), "", "nothing extra to preload for the egg")
	egg.free()
	var kid := _first_kit()
	if kid != "":
		var k := ArenaActors.player_figure({"figure": kid, "scheme": "red"})
		assert_true(k is KitFighter and str(k.get("walk_kit")) == kid.trim_prefix("kit_"), "a kit -> KitFighter on that kit", kid)
		assert_eq(ArenaActors.missing_api(k), PackedStringArray(), "KitFighter has the whole arena contract")
		assert_eq(ArenaActors.scheme_of({"figure": kid, "scheme": "red"}), "red", "a kit keeps its scheme")
		assert_eq(ArenaActors.player_preload({"figure": kid}), KitLibrary.kit_path(kid.trim_prefix("kit_")), "the door preloads the kit model")
		k.free()
	var p := ArenaActors.player_figure({"figure": "painted", "scheme": "pink"})
	assert_eq(_script_of(p), PAINT, "a pack figure -> its own script")
	assert_eq(ArenaActors.scheme_of({"figure": "painted", "scheme": "pink"}), "pink", "…with the chosen scheme")
	assert_eq(ArenaActors.player_preload({"figure": "painted"}), PAINT, "the door preloads the pack figure")
	p.free()
	assert_eq(ArenaActors.scheme_of({"figure": "plain", "scheme": "pink"}), "original", "a pack entry without schemes stays original")
	var d := ArenaActors.player_figure({"figure": "deck_only", "scheme": "pink"})
	assert_eq(_script_of(d), str(ArenaActors.DEFAULT["player"]), "a deck-only pack figure falls back to the default player")
	d.free()
	var u := ArenaActors.player_figure({"figure": "no_such", "scheme": "pink"})
	assert_eq(_script_of(u), str(ArenaActors.DEFAULT["player"]), "an unknown id -> the default player")
	u.free()
	_restore()


func _player(fig: Node3D, level: String, scheme: String = "original") -> Node3D:
	var tree := Engine.get_main_loop() as SceneTree
	var p: Node3D = (load(PLAYER_SCENE) as PackedScene).instantiate()
	tree.root.add_child(p)
	p.call("setup", null, {"figure": fig, "level": level, "scheme": scheme})
	p.call("place", Vector3(0, 0, 40), 0.0, PI)
	return p


func _free(p: Node3D) -> void:
	p.get_parent().remove_child(p)
	p.free()


func _ticks(p: Node3D, n: int) -> void:
	for i in n:
		p.call("_physics_process", DT)


func _fwd(p: Node3D) -> Vector3:
	var f := float(p.get("face"))
	return Vector3(sin(f), 0, cos(f))


func _cam_fwd(p: Node3D) -> Vector3:
	var y := float((p.call("camera_rig") as Node).get("yaw")) + PI
	return Vector3(sin(y), 0, cos(y))


func test_scheme_after_setup() -> void:
	if not ResourceLoader.exists(PLAYER_SCENE):
		return
	var pink: Dictionary = Figures.scheme("pink")
	var fig: Node3D = (load(PAINT) as Script).new()
	var p := _player(fig, "mid", "pink")
	assert_eq(fig.get("scheme_colors"), [pink["primary"], pink["secondary"]], "setup dresses the figure with the scheme (H10)")
	assert_true(int((fig.get("calls") as Dictionary).get("setup", 0)) == 1, "…after the figure's own setup")
	_free(p)
	var fig2: Node3D = (load(PAINT) as Script).new()
	var p2 := _player(fig2, "mid", "original")
	assert_eq(fig2.get("scheme_colors"), [], "the original scheme paints nothing")
	_free(p2)


func test_turn_controls() -> void:
	if not ResourceLoader.exists(PLAYER_SCENE):
		return
	for level in ["mid", "min"]:
		var fig: Node3D = (load(HEAVY) as Script).new()
		var p := _player(fig, level)
		var rig: Node = p.call("camera_rig")
		for m: StringName in [&"walk", &"shoot"]:
			p.call("set_mode", m)
			_ticks(p, 30)
			var y0 := float(rig.get("yaw"))
			p.call("set_stick", Vector2(1, 0))
			_ticks(p, 60)
			var turned := angle_difference(y0, float(rig.get("yaw")))
			assert_within(turned, -deg_to_rad(150.0), 0.02, "%s %s: D / stick right turns the camera right 150 deg in 1 s" % [level, m])
			assert_true(_fwd(p).dot(_cam_fwd(p)) > 0.999, "%s %s: …and the body with it" % [level, m])
			assert_true((p.get("_vel") as Vector3).length() < 0.01, "%s %s: …without moving sideways" % [level, m], p.get("_vel"))
			assert_eq(fig.get("last_dir"), Vector2.ZERO, "%s %s: …legs still" % [level, m])
			assert_true(p.is_physics_processing(), "%s %s: turning keeps the player awake" % [level, m])
			y0 = float(rig.get("yaw"))
			p.call("set_stick", Vector2(-1, 0))
			_ticks(p, 30)
			assert_within(angle_difference(y0, float(rig.get("yaw"))), deg_to_rad(75.0), 0.02, "%s %s: A / stick left turns left" % [level, m])
			# forward and back along the facing
			# (the unit runner has no physics step: the velocity is checked, the flow test walks it for real)
			p.call("set_stick", Vector2(0, -1))
			var f := _fwd(p)
			_ticks(p, 40)
			var d: Vector3 = p.get("_vel")
			assert_true(d.dot(f) < -0.5 and absf(d.cross(f).y) < 0.01, "%s %s: S walks straight back" % [level, m], d)
			assert_eq(fig.get("last_dir"), Vector2(0, -1), "%s %s: …on backward legs" % [level, m])
			# diagonal stick: forward only while turning
			p.call("set_stick", Vector2(0.7, 0.7))
			_ticks(p, 40)
			assert_eq(fig.get("last_dir"), Vector2(0, 1), "%s %s: diagonal -> forward legs while turning" % [level, m])
			assert_true((p.get("_vel") as Vector3).normalized().dot(_fwd(p)) > 0.9, "%s %s: …moving about the way it faces" % [level, m])
			p.call("set_stick", Vector2.ZERO)
			_ticks(p, 120)
			assert_false(p.is_physics_processing(), "%s %s: released, nothing processes" % [level, m])
		# keys: D turns too
		p.call("set_mode", &"walk")
		var y1 := float(rig.get("yaw"))
		Input.action_press(&"move_right")
		_ticks(p, 30)
		Input.action_release(&"move_right")
		assert_within(angle_difference(y1, float(rig.get("yaw"))), -deg_to_rad(75.0), 0.02, "%s: the D key turns right" % level)
		_ticks(p, 120)
		# a dodge with the stick sideways goes backwards (no side dash); forward with W
		_ticks(p, 60)
		p.call("set_stick", Vector2(1, 0))
		assert_true(bool(p.call("dodge")), "%s: a dodge with the stick sideways" % level)
		var dd: Vector3 = p.get("_dodge_dir")
		assert_true(dd.dot(_fwd(p)) < -0.99, "%s: …dashes backwards" % level, dd)
		assert_eq((fig.get("last_dodge") as Dictionary).get("dir"), Vector2(0, -1), "%s: …with backward legs" % level)
		p.call("set_stick", Vector2.ZERO)
		_ticks(p, 80)
		p.call("set_stick", Vector2(0.3, 1))
		assert_true(bool(p.call("dodge")), "%s: a dodge with W" % level)
		dd = p.get("_dodge_dir")
		assert_true(dd.dot(_fwd(p)) > 0.99, "%s: …dashes forward" % level, dd)
		p.call("set_stick", Vector2.ZERO)
		_ticks(p, 120)
		_free(p)
	# the egg keeps strafing and never turns from the stick
	var egg: Node3D = (load(EGG) as Script).new()
	var pe := _player(egg, "mid")
	var re: Node = pe.call("camera_rig")
	var ye := float(re.get("yaw"))
	pe.call("set_stick", Vector2(1, 0))
	_ticks(pe, 40)
	assert_within(float(re.get("yaw")), ye, 1e-6, "the egg: the stick does not turn the camera")
	assert_true((pe.get("_vel") as Vector3).dot(re.call("right_flat")) > 2.5, "the egg: it side-steps right", pe.get("_vel"))
	pe.call("set_stick", Vector2.ZERO)
	_ticks(pe, 120)
	_free(pe)


func test_kit_fighter() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	for kit: String in ["infantry", "kblade", "cxw", "samurai"]:
		if not KitLibrary.has_kit(kit):
			continue
		var k := KitFighter.new()
		k.walk_kit = kit
		tree.root.add_child(k)
		k.setup({"role": &"player", "level": "mid", "manual": true})
		var c: Dictionary = k.clip_names()
		var want := {"infantry": "fire", "kblade": "fire_pistol_r", "cxw": "fire_heavy", "samurai": "fire_pistol_r"}
		assert_eq(k.weapon_clip(), str(want[kit]), "%s fires with %s" % [kit, want[kit]])
		assert_eq(c.get("fire"), PackedStringArray([want[kit]]), "%s: clip_names lists it" % kit)
		for lg in ["idle", "walk", "run", "punch", "swing", "hit", "die"]:
			assert_true((c.get(lg, PackedStringArray()) as PackedStringArray).size() > 0, "%s: a %s clip" % [kit, lg])
		if kit == "samurai":
			assert_true(str(c["swing"][0]).begins_with("swing2_"), "the samurai swings two-handed")
		assert_false(k.uses_strafe(), "%s: no strafe (H9)" % kit)
		assert_within(float(k.metrics()["radius"]), float(ArenaData.PLAYER["radius"]), 1e-6, "%s: the player's radius" % kit)
		# aim layer
		assert_false(k.aiming(), "%s: no aim with nothing in hand" % kit)
		k.set_weapon(&"gun")
		assert_true(k.aiming(), "%s: the gun in hand aims" % kit)
		var hand: Node3D = k.anchor(&"hand_r")
		k.step(0.2)
		k.set_aim(0.5)
		k.step(0.05)
		assert_true(k.skeleton().get_bone_pose_rotation(k.skeleton().find_bone("chest")) != Quaternion.IDENTITY, "%s: aiming poses the chest" % kit)
		assert_within(k.play(&"fire"), KitFighter.RECOIL_T, 1e-6, "%s: a shot is a short recoil" % kit)
		assert_eq(k.playing_clip(), "humanoid/idle", "%s: …the legs keep their clip" % kit)
		k.step(0.05)
		var m := k.muzzle()
		assert_true(m != null and m.is_inside_tree(), "%s: a muzzle node" % kit)
		if m != null and hand != null:
			assert_true(m.global_position.z > hand.global_position.z - 0.5 and m.global_position.y > 0.6, "%s: the muzzle is up front by the hands" % kit, m.global_position)
		k.set_aim(0.0)
		k.set_weapon(&"sword")
		assert_false(k.aiming(), "%s: the sword does not aim" % kit)
		assert_true(k.play(&"swing") > 0.0, "%s: a sword swing plays" % kit)
		assert_true(k.playing_clip().contains(str(c["swing"][0]).left(5)), "%s: …its own swing clip" % kit, k.playing_clip())
		k.step(1.0)
		# backward walk
		k.set_move_dir(Vector2(0, -1), 1.5, false)
		assert_true(k.moving_back() and k.playing_clip() == "humanoid/walk", "%s: backwards = the walk clip reversed" % kit)
		k.set_move_dir(Vector2(0, 1), 1.5, false)
		assert_false(k.moving_back(), "%s: forward again" % kit)
		k.set_move_dir(Vector2.ZERO, 0.0, false)
		k.begin_dodge(Vector2(0, -1), 0.3)
		assert_true(k.dodging() and k.last_dodge() == Vector2(0, -1), "%s: the dodge leans (H8)" % kit)
		k.apply_scheme(Color("e07aa8"), Color("f4e6ee"))
		assert_eq(k.scheme(), [Color("e07aa8"), Color("f4e6ee")], "%s: the paint table takes the scheme (H10)" % kit)
		assert_eq(k.play(&"reload"), 0.0, "%s: no reload clip" % kit)
		tree.root.remove_child(k)
		k.free()
	# min: still pose, nothing processes, aiming still sets the pose once
	if KitLibrary.has_kit("infantry"):
		var km := KitFighter.new()
		km.walk_kit = "infantry"
		tree.root.add_child(km)
		km.setup({"role": &"player", "level": "min"})
		km.set_move_dir(Vector2.ZERO, 0.0, false)
		await_still(km)
		assert_true(km.is_still() and not km.animation_player().is_playing(), "min: a still pose")
		var sk := km.skeleton()
		var before := sk.get_bone_pose_rotation(sk.find_bone("shoulderR"))
		km.set_weapon(&"gun")
		assert_true(sk.get_bone_pose_rotation(sk.find_bone("shoulderR")) != before, "min: drawing the gun poses the arms once")
		assert_true(km.is_still() and not km.animation_player().is_playing(), "min: …and stays still")
		km.play(&"fire")
		assert_eq(float(km.get("_recoil")), -1.0, "min: no recoil animation")
		tree.root.remove_child(km)
		km.free()


## min goes still after the idle blend (deferred): settle it at once
func await_still(k: KitFighter) -> void:
	if not k.is_still():
		k.call("_go_still")
