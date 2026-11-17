extends "res://tests/testing.gd"
## MissionWaves (CAMPAIGN_SPEC §2.4, §5.4, §7 track C): totals = MissionTypes.enemy_total + bosses (+ camp guards for
## destroy_camp, cult roster), role shares (rusher 60 / gunner 25 / brute 15; gunline doubles gunners; the tomb host has no
## gunners), modifiers (horde x1.3 count, champion +1 boss, ambush first wave near), difficulty count_pct, wave timing per
## type, kits from MissionRoster, purity; and MissionRoster.stats scaling.

const Specs := preload("res://tests/fixtures/campaign_missions/specs.gd")


func test_totals_every_week_spec() -> void:
	var bad := []
	for diff in CampaignGalaxy.DIFFICULTIES:
		for s in Specs.week_specs(2967, diff):
			var p := MissionWaves.plan(s)
			var non_guard := 0
			var bosses := 0
			for w: Dictionary in p:
				if bool(w["guard"]):
					continue
				for u: Dictionary in w["units"]:
					if str(u["role"]) == "boss":
						bosses += int(u["count"])
					else:
						non_guard += int(u["count"])
			var want := MissionTypes.enemy_total(s)
			if non_guard != want or bosses != MissionTypes.boss_count(s):
				bad.append("%s %s %s: %d+%d vs %d+%d" % [s["planet"], s["primary"]["type"], diff, non_guard, bosses, want, MissionTypes.boss_count(s)])
			if MissionWaves.total(p) != want + bosses + MissionTypes.guard_count(s):
				bad.append("%s total" % s["planet"])
	assert_eq(bad, [], "every spec of week 2967 at every difficulty: plan totals = enemy_total + bosses (+ guards)")


func test_shares_and_modifiers() -> void:
	var p := MissionWaves.plan(Specs.make("purge", {"faction": "orcs", "modifier": "armoured"}))
	assert_eq(p.size(), 3, "purge: three waves")
	var r := MissionWaves.by_role(p)
	assert_eq(r["rusher"] + r["gunner"] + r["brute"], 24, "purge normal: 24 enemies")
	assert_eq(r["boss"], 1, "purge: one boss in the last wave")
	assert_true(r["gunner"] >= 4 and r["gunner"] <= 7, "about a quarter gunners (%d)" % r["gunner"])
	assert_true(r["rusher"] > r["gunner"] and r["gunner"] > 0 and r["brute"] > 0, "rushers > gunners, brutes present")
	assert_eq(int((p[0]["units"] as Array).filter(func(u: Dictionary) -> bool: return u["role"] == "brute").size()), 0, "no brutes in the first wave")
	var last: Array = p[2]["units"]
	assert_true(last.any(func(u: Dictionary) -> bool: return u["role"] == "boss" and u["kit"] == "boss"), "the orc boss kit leads the last wave")
	var gl := MissionWaves.by_role(MissionWaves.plan(Specs.make("purge", {"faction": "orcs", "modifier": "gunline"})))
	assert_true(gl["gunner"] > r["gunner"], "gunline brings more gunners (%d > %d)" % [gl["gunner"], r["gunner"]])
	var tomb := MissionWaves.by_role(MissionWaves.plan(Specs.make("purge", {"faction": "tomb", "modifier": "gunline"})))
	assert_eq(tomb["gunner"], 0, "the tomb host has no gunners")
	assert_eq(tomb["rusher"] + tomb["brute"], 24, "tomb: the gunner share goes to the rushers")
	var horde := MissionWaves.by_role(MissionWaves.plan(Specs.make("purge", {"modifier": "horde"})))
	assert_eq(horde["rusher"] + horde["gunner"] + horde["brute"], 31, "horde: 24 x 130 % = 31")
	var champ := MissionWaves.by_role(MissionWaves.plan(Specs.make("purge", {"modifier": "champion"})))
	assert_eq(champ["boss"], 2, "champion adds a boss")
	var cat := MissionWaves.by_role(MissionWaves.plan(Specs.make("purge", {"difficulty": "catastrophe"})))
	assert_eq(cat["rusher"] + cat["gunner"] + cat["brute"], 57, "catastrophe: 24 x 240 % = 57")
	var amb := MissionWaves.plan(Specs.make("purge", {"modifier": "ambush"}))
	assert_eq(str(amb[0]["spawn"]), "near", "ambush: the first wave spawns near the player")
	assert_eq(str(amb[1]["spawn"]), "edge", "ambush: later waves at the edge")


func test_timing_per_type() -> void:
	var d := MissionWaves.plan(Specs.make("defend"))
	assert_eq(d.size(), 5, "defend: five waves")
	assert_eq(d.map(func(w: Dictionary) -> float: return float(w["at_s"])), [3.0, 30.0, 62.0, 96.0, 130.0], "defend: timed waves")
	assert_false(d.any(func(w: Dictionary) -> bool: return bool(w["after_clear"])), "defend waves never wait for a clear")
	var pu := MissionWaves.plan(Specs.make("purge"))
	assert_eq([float(pu[0]["at_s"]), bool(pu[1]["after_clear"]), float(pu[1]["at_s"])], [0.0, true, -1.0], "purge: next wave after a clear")
	var re := MissionWaves.plan(Specs.make("rescue"))
	assert_eq(str(re[0]["post"]), "hostages", "rescue: the first wave guards the hostages")
	assert_eq([float(re[1]["at_s"]), bool(re[1]["after_clear"])], [90.0, true], "rescue: the second wave at 90 s or after a clear")
	var dc := MissionWaves.plan(Specs.make("destroy_camp", {"faction": "machines"}))
	assert_true(bool(dc[0]["guard"]) and str(dc[0]["post"]) == "camp", "destroy_camp: the camp guards come first")
	assert_true((dc[0]["units"] as Array).all(func(u: Dictionary) -> bool: return u["faction"] == "cult"), "the camp guards are always the dark cult")
	assert_eq(MissionWaves.total([dc[0]]), 6, "six guards on normal")
	assert_true((dc[1]["units"] as Array).all(func(u: Dictionary) -> bool: return u["faction"] == "machines"), "the invaders patrol outside the camp")
	assert_eq(var_to_str(MissionWaves.plan(Specs.make("defend", {"seed": 1}))), var_to_str(MissionWaves.plan(Specs.make("defend", {"seed": 2}))),
		"the plan does not depend on the seed (pure function of type, faction, modifier, difficulty)")


func test_roster_stats() -> void:
	var n := MissionRoster.stats(Specs.make("purge", {"modifier": "frenzied"}), "rusher")
	assert_eq(int(n["hp"]), 54, "rusher hp 60 x frenzied 90 % = 54")
	assert_within(float(n["speed"]), 3.6 * 1.2, 0.001, "frenzied rusher speed x 1.2")
	var c := MissionRoster.stats(Specs.make("purge", {"difficulty": "catastrophe", "modifier": "armoured"}), "brute")
	assert_eq(int(c["hp"]), 300 * 220 / 100 * 130 / 100, "catastrophe armoured brute hp")
	assert_eq(int(c["dmg"]), 36, "catastrophe brute dmg 18 x 200 %")
	assert_within(float(c["windup"]), 0.6 * 0.7, 0.0001, "catastrophe windup x 70 %")
	for f in MissionRoster.FACTIONS:
		for role in MissionRoster.ROLES:
			var k := MissionRoster.kit(f, role)
			if k != "":
				assert_true(KitLibrary.has_kit(k) or not KitLibrary.has_kit("warrior"), "kit %s of %s/%s exists when kits are installed" % [k, f, role])
