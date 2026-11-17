extends "res://tests/testing.gd"
## CampaignSave (CAMPAIGN_SPEC §2.8): the local, versioned campaign file in user:// (never data/), coins, repeat clears,
## week pruning, history cap and broken files.

const TEST_PATH := "user://test_campaign_save.json"


func _fresh() -> void:
	CampaignSave.path = TEST_PATH
	for suffix: String in ["", ".tmp", ".bad", ".v2", ".v99"]:
		if FileAccess.file_exists(TEST_PATH + suffix):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_PATH + suffix))
	CampaignSave._loaded = false


func _spec(w: int, planet := "p01", idx := 0, diff := "normal") -> Dictionary:
	return {"week": w, "planet": planet, "primary": {"type": "purge", "idx": idx}, "difficulty": diff}


func test_record_and_reload() -> void:
	_fresh()
	assert_eq(CampaignSave.coins(), 0, "a new save has no coins")
	assert_false(CampaignSave.is_repeat(_spec(2967)), "nothing cleared yet")
	CampaignSave.record(_spec(2967), {"win": true, "total": 1500, "coins": 37, "grade": "B"})
	assert_eq(CampaignSave.coins(), 37, "coins added")
	assert_true(CampaignSave.is_repeat(_spec(2967)), "the same event at the same difficulty is now a repeat")
	assert_false(CampaignSave.is_repeat(_spec(2967, "p01", 0, "hard")), "another difficulty is not")
	assert_false(CampaignSave.is_repeat(_spec(2968)), "the next week is not")
	CampaignSave.record(_spec(2967, "p02"), {"win": false, "total": 300, "coins": 1, "grade": "-"})
	assert_false(CampaignSave.is_repeat(_spec(2967, "p02")), "a failed mission is no clear")
	CampaignSave.set_last_difficulty("veryhard")
	CampaignSave._loaded = false
	assert_eq(CampaignSave.coins(), 38, "coins survive a reload")
	assert_eq(CampaignSave.last_difficulty(), "veryhard", "the last difficulty survives a reload")
	assert_true(CampaignSave.is_repeat(_spec(2967)), "clears survive a reload")
	assert_eq(int(CampaignSave.data()["v"]), CampaignSave.VERSION, "the file carries its version")
	assert_true(TEST_PATH.begins_with("user://") and CampaignSave.PATH.begins_with("user://"), "the save lives in user://, never data/")


func test_pruning_and_history() -> void:
	_fresh()
	for w in range(2960, 2968):
		CampaignSave.record(_spec(w), {"win": true, "total": 100, "coins": 1, "grade": "D"})
	var weeks: Dictionary = CampaignSave.data()["weeks"]
	assert_eq(weeks.size(), CampaignSave.KEEP_WEEKS, "only the last two weeks are kept")
	assert_true(weeks.has("2967") and weeks.has("2966"), "the newest weeks stay")
	for i in 30:
		CampaignSave.record(_spec(2967, "p03"), {"win": true, "total": i, "coins": 0, "grade": "D"})
	assert_eq((CampaignSave.data()["history"] as Array).size(), CampaignSave.HISTORY, "history keeps 20 entries")
	assert_eq(int(CampaignSave.data()["weeks"]["2967"]["best"]["p03:0:normal"]), 29, "best keeps the highest total")


func test_broken_files() -> void:
	_fresh()
	for text in ["not json", "[1, 2]", "{\"v\": 99, \"coins\": 500}"]:
		var f := FileAccess.open(TEST_PATH, FileAccess.WRITE)
		f.store_string(text)
		f = null
		CampaignSave._loaded = false
		assert_eq(CampaignSave.coins(), 0, "a broken or foreign file starts fresh: " + text)
	var g := FileAccess.open(TEST_PATH, FileAccess.WRITE)
	g.store_string("{\"v\": 1, \"coins\": -40, \"weeks\": [], \"history\": {}}")
	g = null
	CampaignSave._loaded = false
	assert_eq(CampaignSave.coins(), 0, "negative coins read as 0")
	assert_true(CampaignSave.data()["weeks"] is Dictionary and CampaignSave.data()["history"] is Array, "wrong types are ignored")
	_fresh()
	CampaignSave.path = CampaignSave.PATH
	CampaignSave._loaded = false


## track A: every field read back is checked; wrong parts are dropped, good parts are kept
func test_field_checks() -> void:
	_fresh()
	var f := FileAccess.open(TEST_PATH, FileAccess.WRITE)
	f.store_string(JSON.stringify({"v": 1, "coins": 12.0, "last_difficulty": "impossible",
		"weeks": {"2967": {"best": {"p01:0:hard": 900.0, "bad": "x"}, "clears": {"p01:0:hard": true, "p02:0:hard": "yes"}},
			"abc": {"best": {}}, "2966": [1, 2]},
		"history": [{"week": 2967}, 5, "x", {"week": 2967, "key": "p01:0:hard", "total": 900.0, "coins": 22.0, "grade": "B"}]}))
	f = null
	CampaignSave._loaded = false
	assert_eq(CampaignSave.coins(), 12, "coins read as an int")
	assert_eq(CampaignSave.last_difficulty(), "", "an unknown difficulty is dropped")
	var weeks: Dictionary = CampaignSave.data()["weeks"]
	assert_eq(weeks.keys(), ["2967"], "only a numeric week holding a dictionary is kept")
	assert_eq(weeks["2967"]["best"], {"p01:0:hard": 900}, "best keeps numbers only")
	assert_eq(weeks["2967"]["clears"], {"p01:0:hard": true}, "clears keeps true only")
	# review fix: history entries are now checked field by field (the partial {"week"} entry is dropped too)
	assert_eq(CampaignSave.data()["history"], [{"week": 2967, "key": "p01:0:hard", "total": 900, "coins": 22, "grade": "B"}],
		"history keeps complete entries only, numbers as ints")
	assert_true(CampaignSave.is_repeat({"week": 2967, "planet": "p01", "primary": {"idx": 0}, "difficulty": "hard"}), "the kept clear still counts")
	_fresh()
	CampaignSave.path = CampaignSave.PATH
	CampaignSave._loaded = false


## review fix: a cut-off or newer-version file is kept beside the save before anything overwrites it; saves are atomic
func test_truncated_and_future_files_kept() -> void:
	_fresh()
	var full := JSON.stringify({"v": 1, "coins": 500, "last_difficulty": "hard", "weeks": {}, "history": []})
	var f := FileAccess.open(TEST_PATH, FileAccess.WRITE)
	f.store_string(full.substr(0, 20))
	f = null
	CampaignSave._loaded = false
	assert_eq(CampaignSave.coins(), 0, "a cut-off file starts fresh")
	assert_true(FileAccess.file_exists(TEST_PATH + ".bad"), "but it is kept as .bad")
	CampaignSave.set_last_difficulty("normal")
	assert_eq(FileAccess.get_file_as_string(TEST_PATH + ".bad"), full.substr(0, 20), "the next write leaves .bad untouched")
	assert_false(FileAccess.file_exists(TEST_PATH + ".tmp"), "no temporary file is left after a save")
	var g := FileAccess.open(TEST_PATH, FileAccess.WRITE)
	g.store_string("{\"v\": 2, \"coins\": 900}")
	g = null
	CampaignSave._loaded = false
	assert_eq(CampaignSave.coins(), 0, "a newer version is not read")
	assert_true(FileAccess.file_exists(TEST_PATH + ".v2"), "and is kept as .v2 for the newer app")
	CampaignSave.record(_spec(2967), {"win": true, "total": 10, "coins": 3, "grade": "D"})
	assert_true(FileAccess.get_file_as_string(TEST_PATH + ".v2").contains("900"), "the kept copy still holds its 900 coins")
	CampaignSave._loaded = false
	assert_eq(CampaignSave.coins(), 3, "the fresh save reloads")
	_fresh()
	CampaignSave.path = CampaignSave.PATH
	CampaignSave._loaded = false


## review fix: coins are capped so a huge (edited) number cannot overflow to negative
func test_coin_cap() -> void:
	_fresh()
	var f := FileAccess.open(TEST_PATH, FileAccess.WRITE)
	f.store_string(JSON.stringify({"v": 1, "coins": 9.2e18}))
	f = null
	CampaignSave._loaded = false
	assert_eq(CampaignSave.coins(), CampaignSave.COIN_CAP, "a huge coin count reads as the cap")
	CampaignSave.record(_spec(2967), {"win": true, "total": 10, "coins": 1000000000000000000, "grade": "D"})
	assert_eq(CampaignSave.coins(), CampaignSave.COIN_CAP, "adding stays at the cap, never negative")
	_fresh()
	CampaignSave.path = CampaignSave.PATH
	CampaignSave._loaded = false
