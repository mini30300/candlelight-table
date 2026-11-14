extends "res://tests/testing.gd"
## CampaignGalaxy (CAMPAIGN_SPEC §2.1–§2.4): the fixed 44-planet layout, factions and modifiers, the weekly roll (a pure
## function of the week number, core Rng only), the golden digest every device must reproduce, and the mission spec.

## Golden digests of the weekly roll. A change here means every device sees another galaxy: only on purpose, with a
## CAMPAIGN_SPEC note (the roll is part of the shared contract like the rules digests).
const GOLDEN := {2967: "b9733269b81914b4", 2968: "543c35302362b6de"}


func test_layout() -> void:
	assert_eq(CampaignGalaxy.PLANETS.size(), CampaignGalaxy.ARMS * CampaignGalaxy.PER_ARM, "4 arms x 11 planets")
	assert_true(CampaignGalaxy.PLANETS.size() >= 40 and CampaignGalaxy.PLANETS.size() <= 48, "40-48 planets")
	var ids := {}
	var bad := []
	for i in CampaignGalaxy.PLANETS.size():
		var p: Dictionary = CampaignGalaxy.PLANETS[i]
		if str(p["id"]) != "p%02d" % i or not CampaignGalaxy.BIOMES.has(str(p["biome"])) or ids.has(p["id"]):
			bad.append(p["id"])
		ids[p["id"]] = true
	assert_eq(bad, [], "ids p00..p43 in order, unique, each with a known biome")
	var p7 := CampaignGalaxy.planet("p07")
	assert_eq([p7["index"], p7["arm"], p7["slot"]], [7, 0, 7], "planet() adds index, arm and slot")
	assert_eq(CampaignGalaxy.planet("p99"), {}, "an unknown planet is {}")
	var near := INF
	for i in CampaignGalaxy.PLANETS.size():
		var a := CampaignGalaxy.position(i)
		assert_true(a.length() <= 1.0, "planet %d inside the galaxy disc" % i)
		for j in range(i + 1, CampaignGalaxy.PLANETS.size()):
			near = minf(near, a.distance_to(CampaignGalaxy.position(j)))
	assert_true(near > 0.03, "no two planets overlap on the map (closest %.3f)" % near)
	assert_eq(CampaignGalaxy.FACTIONS.size(), 8, "eight invader factions")
	assert_eq(CampaignGalaxy.MODIFIERS.size(), 6, "six weekly modifiers")
	assert_true(CampaignGalaxy.FACTIONS.size() * CampaignGalaxy.MODIFIERS.size() >= CampaignGalaxy.PLANETS.size(),
		"enough (faction, modifier) pairs for a different invader on every planet")


func test_week_roll_rules() -> void:
	for w in [0, 1, 2967, 2968, 4000]:
		var wk := CampaignGalaxy.week(w)
		var pairs := {}
		var featured := 0
		var bad := []
		for p: Dictionary in wk["planets"]:
			var key := str(p["faction"]) + "/" + str(p["modifier"])
			if pairs.has(key) or CampaignGalaxy.faction(str(p["faction"])).is_empty() \
					or CampaignGalaxy.modifier(str(p["modifier"])).is_empty():
				bad.append(p["id"])
			pairs[key] = true
			var ev: Array = p["events"]
			var types := {}
			for i in ev.size():
				var t := str(ev[i]["type"])
				if not CampaignGalaxy.TYPES.has(t) or types.has(t) or int(ev[i]["idx"]) != i:
					bad.append(p["id"])
				types[t] = true
			if ev.size() < 1 or ev.size() > 3:
				bad.append(p["id"])
			featured += 1 if p["featured"] else 0
		assert_eq(bad, [], "week %d: every planet a different invader, 1-3 distinct events indexed 0.." % w)
		assert_eq(featured, CampaignGalaxy.FEATURED, "week %d: exactly %d featured planets" % [w, CampaignGalaxy.FEATURED])
		assert_eq((wk["planets"] as Array).size(), CampaignGalaxy.PLANETS.size(), "week %d: one entry per planet" % w)


func test_week_roll_is_pure() -> void:
	var a := CampaignGalaxy.digest(2967)
	CampaignGalaxy._cache.clear()
	assert_eq(CampaignGalaxy.digest(2967), a, "the same week rolls the same galaxy after the cache is cleared")
	assert_ne(CampaignGalaxy.digest(2968), a, "the next week rolls another galaxy")
	for w in GOLDEN:
		if str(GOLDEN[w]) != "":
			assert_digest(CampaignGalaxy.digest(w), str(GOLDEN[w]), "golden digest of week %d" % w)
	print("      digests: 2967 %s, 2968 %s" % [CampaignGalaxy.digest(2967), CampaignGalaxy.digest(2968)])
	var src := FileAccess.get_file_as_string("res://app/campaign_galaxy.gd")
	for word in ["Time.", "randomize", "randf", "randi(", "RandomNumberGenerator.new", "OS.get"]:
		assert_false(src.contains(word), "campaign_galaxy.gd never uses %s (the week is its only input)" % word)


func test_week_spread() -> void:
	var count := {}
	var events := 0
	for t in CampaignGalaxy.TYPES:
		count[t] = 0
	for w in range(2960, 3012):
		for p: Dictionary in CampaignGalaxy.week(w)["planets"]:
			for e: Dictionary in p["events"]:
				count[str(e["type"])] += 1
				events += 1
	var per := float(events) / (52.0 * CampaignGalaxy.PLANETS.size())
	assert_true(per > 1.4 and per < 1.9, "about 1.6 events per planet over a year (%.2f)" % per)
	for t in count:
		assert_true(int(count[t]) > events / 6, "mission type %s is common (%d of %d)" % [t, count[t], events])


func test_mission_spec() -> void:
	var pw := CampaignGalaxy.planet_week(2967, "p12")
	var s := CampaignGalaxy.mission_spec(2967, "p12", 0, "hard")
	assert_eq(s["v"], 1, "spec format 1")
	assert_eq([s["week"], s["planet"], s["difficulty"], s["biome"]], [2967, "p12", "hard", "forest"], "spec names its week, planet, difficulty, biome")
	assert_eq([s["faction"], s["modifier"], s["featured"]], [pw["faction"], pw["modifier"], pw["featured"]], "spec carries the planet's invader")
	assert_eq(s["primary"]["type"], pw["events"][0]["type"], "the chosen event is the primary objective")
	assert_eq((s["secondary"] as Array).size(), (pw["events"] as Array).size() - 1, "the other events are secondary objectives")
	assert_eq(s["diff"]["score_x10"], 15, "the resolved difficulty row rides along")
	assert_eq(s["seed"], CampaignGalaxy.mission_seed(2967, "p12", 0, "hard"), "mission seed is stable")
	assert_ne(s["seed"], CampaignGalaxy.mission_seed(2967, "p12", 0, "normal"), "the seed differs per difficulty")
	assert_true(int(s["seed"]) >= 0, "the seed is non-negative")
	assert_eq(CampaignGalaxy.mission_spec(2967, "p12", 9, "hard"), {}, "an event index that does not exist gives {}")
	assert_eq(CampaignGalaxy.mission_spec(2967, "p12", 0, "easy"), {}, "an unknown difficulty gives {}")
	assert_eq(CampaignGalaxy.mission_spec(2967, "zz", 0, "hard"), {}, "an unknown planet gives {}")
