extends "res://tests/testing.gd"
## CampaignRules (CAMPAIGN_SPEC §2.5–§2.7): the difficulty table, the score of a mission result, coins and grades.

func _spec(diff: String, ptype := "purge", featured := false) -> Dictionary:
	return {"difficulty": diff, "primary": {"type": ptype, "idx": 0}, "featured": featured}


func test_difficulty_table() -> void:
	var ids := ["normal", "hard", "veryhard", "catastrophe"]
	assert_eq(Array(CampaignGalaxy.DIFFICULTIES), ids, "four difficulties in order")
	var x := []
	var rev := []
	for id in ids:
		x.append(CampaignRules.difficulty(id)["score_x10"])
		rev.append(CampaignRules.difficulty(id)["revives"])
	assert_eq(x, [10, 15, 25, 40], "score multipliers x1, x1.5, x2.5, x4")
	assert_eq(rev, [2, 1, 1, 0], "revives 2, 1, 1, 0")
	for k in ["count_pct", "hp_pct", "dmg_pct", "speed_pct"]:
		for i in range(1, 4):
			assert_true(int(CampaignRules.difficulty(ids[i])[k]) > int(CampaignRules.difficulty(ids[i - 1])[k]), "%s rises with %s" % [k, ids[i]])
	assert_eq([CampaignRules.mult_text("normal"), CampaignRules.mult_text("hard"), CampaignRules.mult_text("veryhard"),
		CampaignRules.mult_text("catastrophe")], ["×1", "×1.5", "×2.5", "×4"], "multiplier text")
	assert_eq(CampaignRules.difficulty("bogus")["id"], "normal", "an unknown id reads as normal")


func test_score_win() -> void:
	var r := {"outcome": "win", "time_s": 200.0, "kills": {"rusher": 20, "gunner": 5, "brute": 3, "boss": 1}, "shots": 100,
		"hits": 60, "damage_taken": 120, "downs": 0, "secondary_done": [true, false]}
	var s := CampaignRules.score(_spec("hard"), r)
	# kills 200 + 100 + 120 + 150 = 570; accuracy 60 % -> 3600 * 500 / 10000 = 180; time (240 - 200) * 4 = 160;
	# primary 1000; secondary 300; damage -120; no-down 500 -> raw 2590
	var by := {}
	for l: Dictionary in s["lines"]:
		by[l["key"]] = l["value"]
	assert_eq(by, {"kills": 570, "accuracy": 180, "time": 160, "primary": 1000, "secondary": 300, "damage": -120, "no_down": 500}, "score lines")
	assert_eq(s["raw"], 2590, "raw score")
	assert_eq(s["total"], 3885, "x1.5 on hard")
	assert_eq(s["coins"], 97, "coins = total / 40")
	assert_eq(s["grade"], "A", "grade A from the raw score")
	assert_eq(s["acc_pct"], 60, "accuracy 60 %")
	assert_true(s["win"], "win")


func test_score_fail_and_edges() -> void:
	var r := {"outcome": "fail", "time_s": 90.0, "kills": {"rusher": 8}, "shots": 10, "hits": 9, "damage_taken": 999, "downs": 3}
	var s := CampaignRules.score(_spec("catastrophe"), r)
	assert_eq(s["raw"], 0, "kills 80, no accuracy under 15 shots, damage capped at -400: raw never below 0")
	assert_eq([s["coins"], s["grade"], s["win"]], [0, "-", false], "a failed mission: no grade, coins = total / 160")
	var w := {"outcome": "win", "time_s": 999.0, "kills": {}, "shots": 0, "hits": 0, "damage_taken": 0, "downs": 1}
	var base := CampaignRules.score(_spec("normal"), w)
	assert_eq(base["raw"], 1000, "a bare win: primary only (no time bonus past par, no no-down bonus)")
	assert_eq(base["coins"], 25, "1000 / 40")
	assert_eq(CampaignRules.score(_spec("normal", "purge", true), w)["coins"], 37, "featured planet x1.5")
	assert_eq(CampaignRules.score(_spec("normal"), w, {"repeat": true})["coins"], 6, "a repeat clear pays 25 %")
	var d := {"outcome": "win", "time_s": 180.0, "kills": {}, "base_hp_pct": 80, "downs": 0}
	var ds := CampaignRules.score(_spec("normal", "defend"), d)
	assert_eq(ds["raw"], 1000 + 400 + 500, "defend: no time bonus (par 0), base 80 % = 400, no-down 500")
	var h := {"outcome": "win", "time_s": 300.0, "kills": {}, "hostages_saved": 3, "hits": 5, "shots": 2, "downs": 1}
	assert_eq(CampaignRules.score(_spec("normal", "rescue"), h)["raw"], 1300, "rescue: 3 hostages = 300; hits are clamped to shots")
	var tiny := {"outcome": "win", "time_s": 999.0, "kills": {}, "downs": 1, "damage_taken": 400}
	assert_eq(CampaignRules.score(_spec("normal"), tiny)["coins"], 15, "a win with the damage cap reached still pays (1000 - 400) / 40")
	assert_true(CampaignRules.COIN_MIN_WIN <= 15, "the minimum win payout never exceeds the worst real win")
