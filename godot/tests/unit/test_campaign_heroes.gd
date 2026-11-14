extends "res://tests/testing.gd"
## CampaignHeroes (CAMPAIGN_SPEC §3): the hero-scene contract, pack lookup order with the primitive fixture pack, the
## fallback to the built-in scenes and the catastrophe music lookup.

const FIX := "res://tests/fixtures/campaign_pack/campaign"
const FIX_ARENA := "res://tests/fixtures/campaign_pack/arena/campaign"


func test_builtin_scenes_keep_the_contract() -> void:
	CampaignHeroes.test_dirs = PackedStringArray(["res://tests/fixtures/none"])
	var root: Node = (Engine.get_main_loop() as SceneTree).root
	for id in CampaignHeroes.IDS:
		var h := CampaignHeroes.make(id)
		assert_true(h != null and CampaignHeroes.missing_api(h).is_empty(), "built-in hero %s has setup and set_active" % id)
		if h == null:
			continue
		assert_false(CampaignHeroes.is_pack(h), "built-in hero %s is not a pack scene" % id)
		var vp := SubViewport.new()
		vp.own_world_3d = true
		root.add_child(vp)
		vp.add_child(h)
		h.call("setup", {"level": "min", "sel": Figures.selected(), "aspect": 16.0 / 9.0})
		var cam := vp.get_camera_3d()
		assert_true(cam != null and h.is_ancestor_of(cam), "hero %s builds its own current camera" % id)
		h.call("set_active", true)
		h.call("set_active", false)
		assert_false(h.is_processing() or h.is_physics_processing(), "hero %s does no per-frame work while inactive" % id)
		vp.free()
	assert_eq(CampaignHeroes.make("easy"), null, "an unknown id gives null")
	CampaignHeroes.test_dirs = PackedStringArray()


func test_pack_lookup() -> void:
	CampaignHeroes.test_dirs = PackedStringArray([FIX, FIX_ARENA])
	assert_eq(CampaignHeroes.pack_path("normal"), FIX + "/hero_normal.gd", "the first folder wins")
	assert_eq(CampaignHeroes.pack_path("veryhard"), FIX_ARENA + "/hero_veryhard.gd", "the second folder is searched too")
	assert_eq(CampaignHeroes.pack_path("catastrophe"), "", "no pack scene for catastrophe")
	var n := CampaignHeroes.make("normal")
	assert_true(CampaignHeroes.is_pack(n), "a valid pack scene is used")
	n.free()
	var h := CampaignHeroes.make("hard")
	assert_false(CampaignHeroes.is_pack(h), "a pack scene without set_active falls back to the built-in one")
	h.free()
	assert_eq(CampaignHeroes.music_path(), FIX_ARENA + "/catastrophe.ogg" if ResourceLoader.exists(FIX_ARENA + "/catastrophe.ogg") else "",
		"music lookup follows the same folders")
	CampaignHeroes.test_dirs = PackedStringArray()
	assert_eq(Array(CampaignHeroes.PACK_DIRS), ["res://packs/campaign", "res://packs/arena/campaign"], "public lookup order")
	assert_eq(CampaignHeroes.pack_path("normal"), "", "the public tree has no pack hero")
