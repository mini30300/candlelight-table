extends "res://tests/testing.gd"
## CampaignSave (CAMPAIGN_SPEC §2.8): the local, versioned campaign file in user:// (never data/), coins, repeat clears,
## week pruning, history cap and broken files.

const TEST_PATH := "user://test_campaign_save.json"


func _fresh() -> void:
	CampaignSave.path = TEST_PATH
	if FileAccess.file_exists(TEST_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_PATH))
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
