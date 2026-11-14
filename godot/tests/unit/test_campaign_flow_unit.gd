extends "res://tests/testing.gd"
## CampaignFlow (app/campaign_flow.gd, CAMPAIGN_SPEC §1.1) with stand-in difficulty and mission screens
## (tests/fixtures/campaign_flow) and the real galaxy and report screens: start → chosen → galaxy, launch → finished →
## report with the score recorded once, retry (a repeat pays 25 %), back to the galaxy, change the difficulty, leave pops
## to the base depth from the deck and from a room, double presses are ignored, missing screens give null.

const STUBS := "res://tests/fixtures/campaign_flow"
const SAVE := "user://test_campaign_flow_unit.json"
## Saturday 14 Nov 2026 12:00 UTC = week 2967
const NOW := 1794657600

var _host: Node
var _old_root: Node


func _begin() -> void:
	CampaignWeek.test_now = NOW
	CampaignSave.path = SAVE
	CampaignSave.reset()
	CampaignSave.save()
	CampaignFlow.test_scenes = {"difficulty": STUBS + "/stub_difficulty.tscn", "mission": STUBS + "/stub_mission.tscn"}
	CampaignFlow.base_depth = -1
	_old_root = App.screen_root()
	_host = Node.new()
	App.get_tree().root.add_child(_host)
	App.set_screen_root(_host)
	while App.depth() > 0:
		App.pop()
	var ps := PackedScene.new()
	var base := Control.new()
	base.name = "Base"
	ps.pack(base)
	base.free()
	App.push(ps)


func _end() -> void:
	while App.depth() > 0:
		App.pop()
	App.set_screen_root(_old_root if _old_root != App else null)
	_host.queue_free()
	CampaignFlow.test_scenes = {}
	CampaignFlow.base_depth = -1
	CampaignWeek.test_now = -1
	if FileAccess.file_exists(SAVE):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE))
	CampaignSave.path = CampaignSave.PATH
	CampaignSave._loaded = false


func _win() -> Dictionary:
	return {"v": 1, "outcome": "win", "time_s": 200.0, "kills": {"rusher": 10, "gunner": 4, "brute": 1, "boss": 0, "structure": 0},
		"shots": 40, "hits": 24, "damage_taken": 120, "downs": 0, "secondary_done": [true, false, false]}


func test_full_round_from_the_deck() -> void:
	_begin()
	assert_eq(App.depth(), 1, "the deck stand-in is the only screen")
	var ds: Node = CampaignFlow.start("deck")
	assert_true(ds != null and App.current() == ds, "start pushes the difficulty screen")
	assert_eq([CampaignFlow.base_depth, App.depth(), CampaignFlow.from], [1, 2, "deck"], "base depth 1, depth 2, from deck")
	assert_eq(ds.get("ctx"), {"last": "", "from": "deck"}, "open() gets the last difficulty and where we came from")
	assert_eq(CampaignFlow.start("deck"), ds, "a second start while open returns the same screen (double press)")
	assert_eq(App.depth(), 2, "and pushes nothing")
	ds.call("choose", &"hard")
	var gs := App.current() as GalaxyScreen
	assert_true(gs != null, "chosen replaces it with the galaxy")
	assert_eq(App.depth(), 2, "replace keeps the depth")
	assert_eq([gs.difficulty, gs.week], ["hard", 2967], "the galaxy opens at hard, week 2967")
	assert_eq(CampaignSave.last_difficulty(), "hard", "the choice is remembered")
	ds.call("choose", &"normal")
	assert_eq(App.current(), gs, "a late chosen from the freed screen changes nothing")
	gs.select_planet("p00")
	assert_true(gs.card_open(), "the planet card opens")
	gs.open_brief(0)
	assert_true(gs.brief_open() and not gs.card_open(), "the brief replaces the card")
	var spec := gs.current_spec()
	assert_eq(spec, CampaignGalaxy.mission_spec(2967, "p00", 0, "hard"), "the brief holds the mission spec")
	var ms: Node = gs.launch()
	assert_true(ms != null and App.current() == ms and App.depth() == 3, "launch pushes the mission over the galaxy")
	assert_eq(ms.get("spec"), spec, "the mission starts with the spec")
	assert_eq(CampaignFlow.launch(spec), null, "a second launch while the mission is up is ignored")
	assert_eq(App.depth(), 3, "still depth 3")
	ms.call("finish", _win())
	var rs := App.current() as ReportScreen
	assert_true(rs != null and App.depth() == 3, "finished replaces the mission with the report")
	var sc := CampaignRules.score(spec, _win())
	assert_eq(int(rs.score["total"]), int(sc["total"]), "the report shows the score")
	assert_eq(CampaignSave.coins(), int(sc["coins"]), "the coins are recorded")
	assert_eq(rs.wallet, CampaignSave.coins(), "the report gets the wallet total")
	ms.call("finish", _win())
	assert_eq(CampaignSave.coins(), int(sc["coins"]), "finished twice records once")
	assert_true(CampaignSave.is_repeat(spec), "the event counts as cleared")
	var ms2: Node = CampaignFlow.retry()
	assert_true(ms2 != null and App.current() == ms2 and App.depth() == 3, "retry replaces the report with a new mission")
	assert_eq(ms2.get("spec"), spec, "the same spec")
	ms2.call("finish", _win())
	var rs2 := App.current() as ReportScreen
	assert_true(rs2 != null and bool(rs2.score["repeat"]), "the second clear is a repeat")
	assert_eq(int(rs2.score["coins"]), int(sc["coins"]) * CampaignRules.REPEAT_PCT / 100, "and pays 25 %")
	assert_true(rs2.shown()["notes"].contains(I18n.t(ReportScreen.REPEAT)), "the report says so")
	CampaignFlow.back_to_galaxy()
	assert_eq([App.current(), App.depth()], [gs, 2], "back to the galaxy pops the report")
	var ds2: Node = CampaignFlow.change_difficulty()
	assert_true(ds2 != null and App.current() == ds2 and App.depth() == 2, "change difficulty replaces the galaxy")
	assert_eq(str((ds2.get("ctx") as Dictionary)["last"]), "hard", "with the last difficulty preselected")
	ds2.call("choose", &"catastrophe")
	var gs2 := App.current() as GalaxyScreen
	assert_true(gs2 != null and gs2.difficulty == "catastrophe", "a new galaxy at catastrophe")
	assert_eq(CampaignFlow.change_difficulty() != null, true, "change difficulty works from the galaxy")
	(App.current() as Node).call("choose", &"normal")
	CampaignFlow.leave()
	assert_eq([App.depth(), CampaignFlow.base_depth], [1, -1], "leave pops back to the deck")
	assert_eq(CampaignFlow.retry(), null, "no retry outside the report")
	assert_eq(CampaignFlow.change_difficulty(), null, "no change of difficulty outside the galaxy")
	_end()


func test_from_a_room_and_esc() -> void:
	_begin()
	# a room screen over the deck: depth 2
	var ps := PackedScene.new()
	var room := Control.new()
	ps.pack(room)
	room.free()
	App.push(ps)
	var ds: Node = CampaignFlow.start("room")
	assert_eq([CampaignFlow.base_depth, CampaignFlow.from, App.depth()], [2, "room", 3], "from a room: base depth 2")
	ds.call("choose", &"veryhard")
	var gs := App.current() as GalaxyScreen
	gs.select_planet("p05")
	gs.open_brief(0)
	assert_true(gs.handle_back() and gs.card_open() and not gs.brief_open(), "Esc: brief -> card")
	assert_true(gs.handle_back() and not gs.card_open(), "Esc: card -> map")
	assert_true(gs.handle_back(), "Esc on the map is handled")
	assert_eq(App.depth(), 2, "and leaves to the room")
	# leaving from the report goes back to the room as well
	ds = CampaignFlow.start("room")
	ds.call("choose", &"normal")
	gs = App.current() as GalaxyScreen
	gs.select_planet("p10")
	gs.open_brief(0)
	var ms: Node = gs.launch()
	ms.call("finish", {"outcome": "quit", "time_s": 12.0, "kills": {}, "shots": 0, "hits": 0, "damage_taken": 0, "downs": 0})
	var rs := App.current() as ReportScreen
	assert_eq(rs.shown()["title"], I18n.t(ReportScreen.QUIT), "a quit shows the withdrew title")
	assert_true(rs.handle_back(), "Esc on the report is handled")
	assert_true(App.current() is GalaxyScreen, "and goes back to the galaxy")
	gs = App.current() as GalaxyScreen
	gs.select_planet("p10")
	gs.open_brief(0)
	ms = gs.launch()
	ms.call("finish", _win())
	(App.current() as ReportScreen).to_ship()
	assert_eq(App.depth(), 2, "back to the ship from the report lands in the room")
	_end()


func test_missing_screens() -> void:
	_begin()
	CampaignFlow.test_scenes = {"difficulty": STUBS + "/nothing.tscn"}
	assert_eq(CampaignFlow.start("deck"), null, "no difficulty screen: start gives null")
	assert_eq([App.depth(), CampaignFlow.base_depth], [1, -1], "and changes nothing")
	CampaignFlow.test_scenes = {"difficulty": STUBS + "/stub_difficulty.tscn", "galaxy": STUBS + "/nothing.tscn"}
	var ds: Node = CampaignFlow.start("deck")
	ds.call("choose", &"hard")
	assert_eq(App.current(), ds, "no galaxy screen: the difficulty screen stays")
	ds.call("choose", &"bogus")
	assert_eq(App.current(), ds, "an unknown difficulty is ignored")
	CampaignFlow.leave()
	assert_eq(CampaignFlow.launch({}), null, "an empty spec launches nothing")
	_end()
