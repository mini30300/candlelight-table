extends SceneTree
## Difficulty screen flow, headless (CAMPAIGN_SPEC §1.4, track B). A plain base screen stands in for the deck.
## CampaignFlow.start("deck") opens the screen with the saved difficulty preselected and its chosen signal wired; Esc
## pops back to the base. On the screen itself: ←/→ and A/D move the selection (clamped at the ends), E / Enter choose,
## chosen fires once per press even when two inputs land in the same frame, a tap selects and a second tap chooses, the
## card's เลือก button chooses, one live hero at most (the selected card) and the others become stills; on lo the live
## hero is paced by a timer; on min every card is a still and nothing under the screen processes after the stills; the
## narrow layout shows one card with tabs, the ‹ › arrows and swipes.
## Run: <godot> --headless --path godot --audio-driver Dummy -s tests/flow/test_difficulty_flow.gd

const SETTINGS_FILE := "user://test_difficulty_flow.cfg"
const SAVE_FILE := "user://test_difficulty_flow.json"
const DS_PATH := "res://ui/screens/difficulty_screen.tscn"

var _started := false
var _done := false
var _passed := 0
var _failed := 0
var _t0 := 0
var _chosen: Array = []
## โหลดตอนรัน (สคริปต์ -s คอมไพล์ก่อนมี autoload App)
var DS: Script
var STAGE: Script
var FLOW: Script
var SAVE: Script
var HEROES: Script


func _initialize() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SETTINGS_FILE))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_FILE))
	var app := _app()
	app.set("settings_file", SETTINGS_FILE)
	app.call("load_settings")
	app.call("set_lang", "th")
	app.call("set_gfx", "mid")
	app.call("set_touch", "off")
	DS = load("res://ui/screens/difficulty_screen.gd")
	STAGE = load("res://scenes/campaign/hero_stage.gd")
	FLOW = load("res://app/campaign_flow.gd")
	SAVE = load("res://app/campaign_save.gd")
	HEROES = load("res://scenes/campaign/hero_loader.gd")
	SAVE.set("path", SAVE_FILE)
	HEROES.set("test_dirs", PackedStringArray(["res://tests/fixtures/none"]))


func _process(_delta: float) -> bool:
	if not _started:
		_started = true
		_t0 = Time.get_ticks_msec()
		_run()
	elif not _done and Time.get_ticks_msec() - _t0 > 240000:
		_check(false, "the walk finished within 240 s (a script error stops it)")
		_finish()
	return _done


func _run() -> void:
	var app := _app()
	var base := Control.new()
	base.name = "BaseScreen"
	var ps := PackedScene.new()
	ps.pack(base)
	var b: Node = app.call("push", ps)
	base.free()
	var depth0: int = app.call("depth")
	await _flow_entry(b, depth0)
	await _screen_keys_and_taps()
	await _lo_and_min()
	await _narrow()
	_finish()


func _flow_entry(base: Node, depth0: int) -> void:
	SAVE.call("set_last_difficulty", "veryhard")
	var ds: Node = FLOW.call("start", "deck")
	await _frames(3)
	var ok: bool = ds != null and ds.get_script() == DS
	_check(ok and _app().call("current") == ds, "CampaignFlow.start opens the difficulty screen")
	if not ok:
		return
	_check(_app().call("depth") == depth0 + 1 and not (base as CanvasItem).visible, "pushed over the base screen (base hidden)")
	_check(ds.selected() == &"veryhard", "the saved difficulty is preselected", str(ds.selected()))
	_check(not ds.get_signal_connection_list(&"chosen").is_empty(), "chosen is wired to the flow")
	_check(ds.stages().size() == 4 and ds.stages().all(func(s: Node) -> bool: return s.get_script() == STAGE), "four hero stages")
	await _frames(30)
	_check(_live_count(ds) == 1 and bool(ds.stages()[2].counts()["live"]), "one live hero: the selected card")
	_check(_still_done(ds, 2), "the other three became stills (no scene, no viewport left)", _stage_info(ds))
	await _press(KEY_ESCAPE)
	await _frames(2)
	_check(_app().call("current") == base and _app().call("depth") == depth0 and (base as CanvasItem).visible,
		"Esc pops back to where the campaign started")


func _screen_keys_and_taps() -> void:
	var ds: Node = _push({"last": "", "from": "room"})
	await _frames(3)
	_check(ds.selected() == &"normal", "no saved difficulty: normal is selected")
	await _press(KEY_D)
	_check(ds.selected() == &"hard", "D moves right", str(ds.selected()))
	await _press(KEY_RIGHT)
	await _press(KEY_RIGHT)
	await _press(KEY_RIGHT)
	_check(ds.selected() == &"catastrophe", "→ stops at the last card", str(ds.selected()))
	await _press(KEY_A)
	await _press(KEY_LEFT)
	_check(ds.selected() == &"hard", "A and ← move left", str(ds.selected()))
	await _frames(20)
	_check(_live_count(ds) <= 1 and bool(ds.stages()[1].counts()["live"]), "the newly selected card is the live one")
	await _press(KEY_E)
	_check(_chosen == [&"hard"], "E chooses the selected card once", str(_chosen))
	_chosen.clear()
	await _frames(2)
	ds.choose(&"veryhard")
	ds.choose(&"veryhard")
	_check(_chosen == [&"veryhard"], "two chooses in one frame emit chosen once", str(_chosen))
	_chosen.clear()
	await _frames(2)
	ds.choose(&"easy")
	_check(_chosen.is_empty(), "an unknown id is ignored")
	_tap(ds, "normal")
	await _frames(2)
	_check(ds.selected() == &"normal" and _chosen.is_empty(), "a tap on another card selects it", str(_chosen))
	_tap(ds, "normal")
	await _frames(2)
	_check(_chosen == [&"normal"], "a second tap on the selected card chooses it", str(_chosen))
	_chosen.clear()
	(ds.card("catastrophe")["button"] as Button).pressed.emit()
	await _frames(2)
	_check(_chosen == [&"catastrophe"] and ds.selected() == &"catastrophe", "the card's เลือก button chooses that card", str(_chosen))
	_check((ds.card("catastrophe")["button"] as Button).text == "เลือก", "the button says เลือก")
	_check(not ds.handle_back(), "handle_back is false (App pops)")
	_chosen.clear()
	_app().call("pop")
	await _frames(2)


func _lo_and_min() -> void:
	_app().call("set_gfx", "lo")
	var ds: Node = _push({"last": "veryhard"})
	await _frames(30)
	var st: Node = ds.stages()[2]
	_check(bool(st.get("live")) and st.get_node_or_null("LoFrame") is Timer, "lo: the live hero is paced by a 33 ms timer")
	_check(st.viewport() != null and st.viewport().render_target_update_mode != SubViewport.UPDATE_ALWAYS,
		"lo: the live viewport is not drawn every frame")
	_app().call("pop")
	await _frames(2)
	_app().call("set_gfx", "min")
	ds = _push({"last": "hard"})
	await _frames(40)
	_check(_live_count(ds) == 0, "min: no live hero")
	_check(ds.stages().all(func(s: Node) -> bool: return not s.busy() and s.viewport() == null and s.hero() == null),
		"min: four stills, no scene or viewport left", _stage_info(ds))
	await _frames(10)
	var busy := _idle_problems(ds)
	_check(busy.is_empty(), "min: nothing under the screen processes after the stills", ", ".join(busy))
	await _press(KEY_D)
	await _frames(20)
	_check(ds.selected() == &"veryhard" and _live_count(ds) == 0, "min: moving the selection keeps every card still")
	_check(_idle_problems(ds).is_empty(), "min: still idle after moving the selection")
	_app().call("pop")
	await _frames(2)
	_app().call("set_gfx", "mid")


func _narrow() -> void:
	var size0 := root.size
	root.size = Vector2i(700, 1000)
	await _frames(2)
	var ds: Node = _push({"last": "hard"})
	await _frames(20)
	_check(bool(ds.get("narrow")), "a portrait window uses the narrow layout")
	var tabs: Array = ds.tab_buttons()
	_check(tabs.size() == 4 and (tabs[0] as Control).is_visible_in_tree(), "four tabs are shown")
	var shown: Array = ["normal", "hard", "veryhard", "catastrophe"].filter(func(id: String) -> bool: return (ds.card(id)["panel"] as Control).visible)
	_check(shown == ["hard"], "one card (the selected one) is shown", str(shown))
	(tabs[3] as Button).pressed.emit()
	await _frames(2)
	_check(ds.selected() == &"catastrophe" and (ds.card("catastrophe")["panel"] as Control).visible
		and not (ds.card("hard")["panel"] as Control).visible, "a tab switches the shown card")
	_swipe(ds, "catastrophe", 160.0)
	await _frames(2)
	_check(ds.selected() == &"veryhard", "swiping right shows the card before", str(ds.selected()))
	_swipe(ds, "veryhard", -160.0)
	await _frames(2)
	_check(ds.selected() == &"catastrophe", "swiping left shows the card after", str(ds.selected()))
	(ds.get_node("Safe").find_child("Prev", true, false) as Button).pressed.emit()
	await _frames(2)
	_check(ds.selected() == &"veryhard", "‹ shows the card before")
	_check(_chosen.is_empty(), "swipes and arrows never choose")
	await _frames(20)
	_check(_live_count(ds) <= 1, "narrow: one live hero at most")
	_app().call("pop")
	root.size = size0
	await _frames(2)


# ---- helpers ----

func _push(c: Dictionary) -> Node:
	var ds: Node = _app().call("push", load(DS_PATH))
	ds.call("open", c)
	ds.connect(&"chosen", func(id: StringName) -> void: _chosen.append(id))
	return ds


func _tap(ds: Node, id: String) -> void:
	for p in [true, false]:
		var ev := InputEventMouseButton.new()
		ev.button_index = MOUSE_BUTTON_LEFT
		ev.pressed = p
		ev.position = Vector2(50.0, 50.0)
		ds.call("_on_card_input", ev, id)


func _swipe(ds: Node, id: String, dx: float) -> void:
	for p in [true, false]:
		var ev := InputEventMouseButton.new()
		ev.button_index = MOUSE_BUTTON_LEFT
		ev.pressed = p
		ev.position = Vector2(300.0 + (dx if not p else 0.0), 200.0)
		ds.call("_on_card_input", ev, id)


func _live_count(ds: Node) -> int:
	return ds.stages().filter(func(s: Node) -> bool: return bool(s.counts()["live"])).size()


func _still_done(ds: Node, live_i: int) -> bool:
	for i in 4:
		var s: Node = ds.stages()[i]
		if i != live_i and (s.busy() or s.viewport() != null or s.hero() != null or str(s.get("id")) == ""):
			return false
	return true


func _stage_info(ds: Node) -> String:
	return str(ds.stages().map(func(s: Node) -> Dictionary: return s.counts()))


func _idle_problems(n0: Node) -> PackedStringArray:
	var out := PackedStringArray()
	var stack: Array[Node] = [n0]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n.can_process() and (n.is_processing() or n.is_physics_processing()):
			out.append(String(n.name) + " processes")
		if n is AnimationPlayer and (n as AnimationPlayer).is_playing() and n.can_process() \
				and (n as AnimationPlayer).callback_mode_process != AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL:
			out.append(String(n.name) + " plays")
		if n is Timer and not (n as Timer).is_stopped():
			out.append(String(n.name) + " ticks")
		stack.append_array(n.get_children())
	return out


func _press(code: Key) -> void:
	for p in [true, false]:
		var ev := InputEventKey.new()
		ev.physical_keycode = code
		ev.keycode = code
		ev.pressed = p
		Input.parse_input_event(ev)
		Input.flush_buffered_events()
		await _frames(2)


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _app() -> Node:
	return root.get_node(^"App")


func _finish() -> void:
	HEROES.set("test_dirs", PackedStringArray())
	SAVE.set("path", SAVE.get("PATH") if SAVE.get("PATH") != null else "user://campaign.json")
	var app := _app()
	app.call("set_lang", "th")
	app.call("set_gfx", "mid")
	app.call("set_touch", "auto")
	app.set("settings_file", str(app.get("SETTINGS_PATH")))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SETTINGS_FILE))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_FILE))
	print("%s  %d passed, %d failed" % ["PASS " if _failed == 0 else "FAIL ", _passed, _failed])
	_done = true
	quit(0 if _failed == 0 else 1)


func _check(cond: bool, msg: String, detail: String = "") -> void:
	if cond:
		_passed += 1
		print("ok    " + msg)
	else:
		_failed += 1
		print("FAIL  " + msg + ("" if detail == "" else " " + detail.left(1500)))
