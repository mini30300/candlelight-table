extends "res://tests/testing.gd"
## TableView.effective_style() (review of 12 Nov): a saved "kit" style with no kits on disk falls back to the egg
## placeholders, also through build_battle (counts().style), and comes back to "kit" when kits exist. Builds a small
## battle table headless under the running tree (no rendering needed).

const TABLE_SCENE := "res://scenes/battle_table.tscn"


func test_kit_without_kits_falls_back_to_eggs() -> void:
	var tv := (load(TABLE_SCENE) as PackedScene).instantiate()
	tv.set("auto_build", false)
	(Engine.get_main_loop() as SceneTree).root.add_child(tv)
	tv.set("figure_style", "kit")
	tv.set("_kits_on_disk", 0)
	assert_eq(str(tv.call("effective_style")), "egg", "kit style with no kits on disk falls back to egg")
	var c := SeatPlan.defaults(77)
	c["size"] = "s"
	c["budget"] = 300
	c["seats"] = [{"fac": "kn", "human": false}, {"fac": "or", "human": false}]
	var r := MatchRunner.new(SeatPlan.build(c))
	r.start()
	tv.call("build_battle", r.st)
	var counts: Dictionary = tv.call("counts")
	assert_eq(str(counts.get("style", "")), "egg", "build_battle draws eggs when the kits are missing")
	assert_eq(int(counts.get("figures", -1)), r.st.units.size(), "one egg per unit (%d units)" % r.st.units.size())
	assert_eq(int(counts.get("skinned", -1)), 0, "no skinned figure in the fallback")
	tv.set("_kits_on_disk", 3)
	assert_eq(str(tv.call("effective_style")), "kit", "with kits on disk the kit style stays kit")
	tv.set("figure_style", "egg")
	assert_eq(str(tv.call("effective_style")), "egg", "egg style is egg")
	tv.call("end_battle")
	tv.get_parent().remove_child(tv)
	tv.free()
