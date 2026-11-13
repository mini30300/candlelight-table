extends "res://tests/testing.gd"
## Figure packs (PACK_SPEC §1, §2, §4.1, §6): the deck role of ArenaActors and the primitive fixture pack
## (tests/fixtures/figure_pack/). No manifest or a pack without a "deck" key -> make_figure("deck") is null (the deck
## keeps its egg); the fixture pack names prim_figure.gd for the deck, the player and the enemy, all three pass the
## figure contract, its enemy name is read and the reserved "army" key does not break format 1; the real manifest is
## still absent. Then the fixture figure itself, so it stays a fair stand-in for a pack figure: set_move picks walk and
## run from the speed with the playback rate from the clip's speed meta, returns to idle, holds a still pose on min,
## one-shots return to the loop, set_fade(1) is opaque, deck_speeds() is (1.5, 4.0), one mesh (1 draw); as the deck
## figure it also holds still on lo (PACK_SPEC §3.2). A deck entry that leaves the pack folder, names a missing file or
## a half-contract script gives null (the deck keeps its egg).

const FIX := "res://tests/fixtures/figure_pack/pack.json"
const PRIM := "res://tests/fixtures/figure_pack/prim_figure.gd"
const ARENA_FIX := "res://tests/unit/fixtures/arena_pack/pack.json"
const NONE := "res://tests/unit/fixtures/no_such_pack/pack.json"
const BAD_HALF := "res://tests/fixtures/figure_pack_bad/pack.json"
const BAD_MISSING := "res://tests/fixtures/figure_pack_bad/missing.json"
const BAD_ESCAPE := "res://tests/fixtures/figure_pack_bad/escape.json"


func _script_of(n: Object) -> String:
	if n == null or n.get_script() == null:
		return ""
	return (n.get_script() as Script).resource_path


func _tree() -> SceneTree:
	return Engine.get_main_loop() as SceneTree


func test_deck_role_without_a_pack() -> void:
	assert_false(FileAccess.file_exists(ArenaActors.PACK_MANIFEST), "no pack is in this repo (git-ignored packs/)")
	assert_false(ArenaActors.DEFAULT.has("deck"), "the deck has no default figure in ArenaActors (the egg is HallAvatar's own)")
	assert_eq(ArenaActors.resolve("deck", NONE), "", "no manifest -> no deck figure path")
	assert_true(ArenaActors.make_figure("deck", NONE) == null, "no manifest -> make_figure(\"deck\") is null")
	assert_true(ArenaActors.make_figure("deck") == null, "the real (absent) pack -> make_figure(\"deck\") is null")
	assert_true(ArenaActors.make_figure("deck", ARENA_FIX) == null, "a pack without a deck key -> null (the egg stays)")


func test_broken_deck_entries_keep_the_egg() -> void:
	# PACK_SPEC §1 steps 3-5: a deck path that leaves the folder, a missing file or a half contract -> null, no fallback
	assert_eq(ArenaActors.resolve("deck", BAD_ESCAPE), "", "a deck path leaving the pack folder is refused")
	assert_true(ArenaActors.make_figure("deck", BAD_ESCAPE) == null, "a deck path leaving the pack folder -> null (the egg stays)")
	assert_eq(ArenaActors.resolve("deck", BAD_MISSING), "", "a deck file that is not there resolves to nothing")
	assert_true(ArenaActors.make_figure("deck", BAD_MISSING) == null, "a missing deck file -> null (the egg stays)")
	assert_eq(ArenaActors.resolve("deck", BAD_HALF), BAD_HALF.get_base_dir() + "/half_figure.gd", "the half-contract deck file resolves")
	assert_true(ArenaActors.make_figure("deck", BAD_HALF) == null, "a deck figure lacking contract methods is freed -> null (the egg stays)")
	assert_eq(ArenaActors.resolve("player", BAD_HALF), ArenaActors.DEFAULT["player"], "a pack with only a deck key leaves the arena figures public")


func test_fixture_pack_names_every_role() -> void:
	for role in ["deck", "player", "enemy"]:
		assert_eq(ArenaActors.resolve(role, FIX), PRIM, "the fixture pack names prim_figure.gd for the %s" % role)
		var fig := ArenaActors.make_figure(role, FIX)
		assert_eq(_script_of(fig), PRIM, "the %s figure is the fixture's primitive figure" % role)
		assert_eq(ArenaActors.missing_api(fig), PackedStringArray(), "the %s figure has the whole contract" % role)
		assert_true(fig != null and fig.has_method("set_fade") and fig.has_method("deck_speeds") and fig.has_signal(&"clip_event"),
			"the %s figure also has set_fade, deck_speeds and the clip_event signal" % role)
		if fig != null:
			fig.free()
	assert_eq(ArenaActors.enemy_name(FIX), {"th": "หุ่นทดสอบ", "en": "Test dummy"}, "the fixture pack names its enemy in Thai and English")
	assert_eq(ArenaActors.pack_id(FIX), "prim_test", "the pack id is read")
	var m: Variant = JSON.parse_string(FileAccess.get_file_as_string(FIX))
	assert_true(m is Dictionary and (m as Dictionary).has("army"), "the fixture carries the reserved army key")
	assert_eq(ArenaActors.resolve("player", FIX), PRIM, "an unknown (reserved) key does not break a format 1 manifest")


func test_fixture_figure_moves_like_a_pack_figure() -> void:
	var fig := ArenaActors.make_figure("deck", FIX)
	if fig == null:
		assert_true(false, "the fixture deck figure is made")
		return
	_tree().root.add_child(fig)
	fig.call("setup", {"role": &"deck", "level": "mid", "team_colour": Color(0.2, 0.5, 0.8), "seed": 0})
	assert_eq(str(fig.get("role")), "deck", "setup stores the deck role")
	assert_eq(fig.call("deck_speeds"), Vector2(1.5, 4.0), "deck_speeds() is (1.5, 4.0)")
	var ap: AnimationPlayer = fig.get("ap")
	fig.call("play", &"idle", 1.0)
	assert_true(ap.is_playing() and ap.current_animation == "prim/idle", "mid: idle plays as a loop")
	fig.call("set_move", 1.0, false)
	assert_true(ap.is_playing() and ap.current_animation == "prim/walk", "set_move(1.0, false) plays the walk clip (%s)" % ap.current_animation)
	assert_within(ap.speed_scale, 1.0 / 1.5, 0.001, "walk at 1.0 m/s plays at 1.0 / 1.5 (the walk clip's speed meta)")
	fig.call("set_move", 4.5, true)
	assert_true(ap.current_animation == "prim/run", "set_move(4.5, true) plays the run clip (%s)" % ap.current_animation)
	assert_within(ap.speed_scale, 4.5 / 4.0, 0.001, "run at 4.5 m/s plays at 4.5 / 4.0 (the run clip's speed meta)")
	fig.call("set_move", 4.5, false)
	assert_true(ap.current_animation == "prim/run", "the clip follows the speed, not the run flag")
	assert_eq(fig.get("last_move"), Vector2(4.5, 0.0), "last_move records (speed, running)")
	fig.call("set_move", 0.0, false)
	assert_true(ap.is_playing() and ap.current_animation == "prim/idle", "set_move(0, false) returns to the idle loop on mid")
	assert_within(ap.speed_scale, 1.0, 0.001, "idle plays at rate 1")
	var len := float(fig.call("play", &"reload", 2.0))
	assert_within(len, 0.8, 0.001, "play(reload, 2) returns the clip's length / speed")
	assert_true(ap.current_animation == "prim/reload", "the one-shot plays")
	fig.call("set_move", 1.5, false)
	assert_true(ap.current_animation == "prim/reload", "moving during a one-shot does not cut it")
	ap.animation_finished.emit(&"prim/reload")
	assert_true(ap.current_animation == "prim/walk" and absf(ap.speed_scale - 1.0) < 0.001, "after the one-shot the walk loop returns at its rate")
	fig.call("set_move", 0.0, false)
	fig.call("apply_level", "min")
	assert_false(ap.is_playing(), "min: idle holds a still pose (AnimationPlayer paused)")
	assert_eq(ap.assigned_animation, &"prim/idle", "min: the still pose is the idle clip's first frame")
	assert_false(fig.is_processing() or fig.is_physics_processing(), "the figure runs no _process of its own")
	fig.call("set_move", 1.5, false)
	assert_true(ap.is_playing() and ap.current_animation == "prim/walk", "min: walking still plays the walk clip")
	fig.call("set_move", 0.0, false)
	assert_false(ap.is_playing(), "min: stopping returns to the still pose at once")
	fig.call("apply_level", "hi")
	assert_true(ap.is_playing() and ap.current_animation == "prim/idle", "hi: the idle loop plays again")
	var calls: Dictionary = fig.get("calls")
	assert_true(int(calls.get("set_move", 0)) == 8 and int(calls.get("apply_level", 0)) == 3 and int(calls.get("play", 0)) == 2,
		"the call counters count every call (%s)" % str(calls))
	# PACK_SPEC §3.2: lo is a low-processor level too, so the deck figure holds still there; arena roles may loop
	fig.call("apply_level", "lo")
	assert_false(ap.is_playing(), "lo, deck role: idle holds a still pose (the deck draws nothing while it stands)")
	fig.call("set_move", 1.5, false)
	assert_true(ap.is_playing() and ap.current_animation == "prim/walk", "lo, deck role: walking plays the walk clip")
	fig.call("set_move", 0.0, false)
	assert_false(ap.is_playing(), "lo, deck role: stopping returns to the still pose")
	fig.call("setup", {"role": &"player", "level": "lo", "team_colour": Color(0.2, 0.5, 0.8), "seed": 0})
	assert_true(ap.is_playing() and ap.current_animation == "prim/idle", "lo, arena player role: the idle loop may keep playing")
	fig.queue_free()
	fig.get_parent().remove_child(fig)


func test_fixture_figure_look() -> void:
	var fig := ArenaActors.make_figure("player", FIX)
	if fig == null:
		assert_true(false, "the fixture player figure is made")
		return
	_tree().root.add_child(fig)
	fig.call("setup", {"role": &"player", "level": "lo", "team_colour": Color(0.8, 0.3, 0.2), "seed": 1})
	var meshes := 0
	for c in fig.get_children():
		if c is GeometryInstance3D:
			meshes += 1
	assert_eq(meshes, 1, "one mesh (1 draw call)")
	var body: MeshInstance3D = fig.get("body")
	var mat := body.material_override as StandardMaterial3D
	assert_true(mat != null and mat.shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED and mat.transparency == BaseMaterial3D.TRANSPARENCY_DISABLED,
		"an unshaded opaque material (no lights on the deck or in the arena)")
	var aabb := body.get_aabb()
	assert_within(aabb.size.y, 1.7, 0.01, "the capsule is 1.7 m tall")
	assert_within(body.position.y - aabb.size.y * 0.5, 0.0, 0.01, "its feet are at the origin")
	fig.call("set_fade", 0.5)
	mat = body.material_override as StandardMaterial3D
	assert_true(mat.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA and absf(mat.albedo_color.a - 0.5) < 0.01, "set_fade(0.5) draws it half transparent")
	fig.call("set_fade", 1.0)
	mat = body.material_override as StandardMaterial3D
	assert_true(mat.transparency == BaseMaterial3D.TRANSPARENCY_DISABLED, "set_fade(1.0) is opaque again (no transparent pass)")
	assert_true(fig.call("muzzle") is Marker3D and fig.call("anchor", &"head") is Node3D and fig.call("anchor", &"nope") == null,
		"muzzle and anchors are markers, an unknown anchor is null")
	var shots: Array[StringName] = []
	fig.connect(&"clip_event", func(k: StringName) -> void: shots.append(k))
	fig.call("play", &"fire", 1.0)
	assert_eq(shots, [&"shot"] as Array[StringName], "fire emits clip_event(&\"shot\")")
	assert_eq(float(fig.call("play", &"no_such_clip", 1.0)), 0.0, "a clip it lacks returns 0")
	var names: Dictionary = fig.call("clip_names")
	for k in ["idle", "walk", "run", "fire", "reload", "punch", "swing", "hit", "die", "attack", "hit_heavy"]:
		assert_true(names.has(k), "clip_names lists %s" % k)
	fig.queue_free()
	fig.get_parent().remove_child(fig)
