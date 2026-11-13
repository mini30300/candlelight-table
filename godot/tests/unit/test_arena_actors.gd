extends "res://tests/testing.gd"
## ArenaActors (scenes/arena/arena_actors.gd, ARENA_SPEC §9, §13.2): the figure loader behind the swap point for the
## owner's private models. No manifest -> the default figures; the fixture pack (tests/unit/fixtures/arena_pack/) swaps
## the enemy for fake_figure.gd and names it; a path leaving the pack's folder, a missing file or a figure lacking part
## of the contract -> the default (with a warning); missing_api lists exactly the absent names; both default figures
## (EggGunner, KitBeast) pass the contract when instanced headless.

const FIX := "res://tests/unit/fixtures/arena_pack/pack.json"
const FAKE := "res://tests/unit/fixtures/arena_pack/fake_figure.gd"
const BAD := "res://tests/unit/fixtures/arena_pack_bad/pack.json"
const ESCAPE := "res://tests/unit/fixtures/arena_pack_escape/pack.json"
const MISSING := "res://tests/unit/fixtures/arena_pack_missing/pack.json"
const NONE := "res://tests/unit/fixtures/no_such_pack/pack.json"


func _script_of(n: Object) -> String:
	if n == null or n.get_script() == null:
		return ""
	return (n.get_script() as Script).resource_path


func test_no_manifest_gives_defaults() -> void:
	assert_eq(ArenaActors.PACK_MANIFEST, "res://packs/arena/pack.json", "the pack lives at res://packs/arena/pack.json")
	assert_false(FileAccess.file_exists(ArenaActors.PACK_MANIFEST), "no pack is in this repo (git-ignored packs/)")
	for role in ["player", "enemy"]:
		assert_eq(ArenaActors.resolve(role, NONE), str(ArenaActors.DEFAULT[role]), "no manifest -> the default %s" % role)
		assert_eq(ArenaActors.resolve(role), str(ArenaActors.DEFAULT[role]), "the real (absent) pack -> the default %s" % role)
	assert_eq(ArenaActors.enemy_name(NONE), {}, "no manifest -> no enemy name")


func test_fixture_pack_swaps_the_enemy() -> void:
	assert_eq(ArenaActors.resolve("enemy", FIX), FAKE, "the fixture pack names fake_figure.gd (relative to its folder)")
	assert_eq(ArenaActors.resolve("player", FIX), str(ArenaActors.DEFAULT["player"]), "a role the pack leaves out stays default")
	var fig := ArenaActors.make_figure("enemy", FIX)
	assert_true(fig != null, "the pack's enemy figure is made")
	assert_eq(_script_of(fig), FAKE, "the enemy figure is the pack's fake figure")
	assert_eq(ArenaActors.missing_api(fig), PackedStringArray(), "the fake figure has the whole contract")
	if fig != null:
		fig.free()
	assert_eq(ArenaActors.enemy_name(FIX), {"th": "ตัวทดสอบ", "en": "Test figure"}, "the pack names its enemy")
	assert_eq(ArenaActors.pack_id(FIX), "test_pack", "the pack id is read")


func test_bad_packs_fall_back() -> void:
	assert_eq(ArenaActors.resolve("enemy", ESCAPE), str(ArenaActors.DEFAULT["enemy"]), "a path leaving the pack's folder -> default")
	assert_eq(ArenaActors.resolve("enemy", MISSING), str(ArenaActors.DEFAULT["enemy"]), "a missing file -> default")
	var fig := ArenaActors.make_figure("enemy", BAD)
	assert_ne(_script_of(fig), "res://tests/unit/fixtures/arena_pack_bad/half_figure.gd", "a figure lacking set_flash is not used")
	if ResourceLoader.exists(str(ArenaActors.DEFAULT["enemy"])):
		assert_eq(_script_of(fig), str(ArenaActors.DEFAULT["enemy"]), "it is replaced by the default enemy figure")
	if fig != null:
		fig.free()


func test_missing_api_lists_exactly_the_absent() -> void:
	var half: Node3D = (load("res://tests/unit/fixtures/arena_pack_bad/half_figure.gd") as Script).new()
	var miss := ArenaActors.missing_api(half)
	var want := ArenaActors.FIGURE_API.duplicate()
	want.remove_at(want.find("setup"))
	want.remove_at(want.find("metrics"))
	assert_eq(miss, want, "missing_api names exactly the ten absent methods")
	assert_true(miss.has("set_flash"), "set_flash is among them")
	half.free()
	assert_eq(ArenaActors.FIGURE_API.size(), 12, "the contract has twelve methods")


func test_default_figures_pass_the_contract() -> void:
	for role in ["player", "enemy"]:
		var path := str(ArenaActors.DEFAULT[role])
		assert_true(ResourceLoader.exists(path), "the default %s figure exists at %s" % [role, path])
		if not ResourceLoader.exists(path):
			continue
		var fig := ArenaActors.make_figure(role, NONE)
		assert_true(fig != null, "the default %s figure instances headless" % role)
		assert_eq(ArenaActors.missing_api(fig), PackedStringArray(), "the default %s figure has the whole contract" % role)
		assert_true(fig != null and fig.has_signal(&"clip_event"), "the default %s figure has the clip_event signal" % role)
		if fig != null:
			fig.free()
