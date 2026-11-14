extends SceneTree
## Campaign missions end to end (CAMPAIGN_SPEC §1.6, §5.4, §5.5, §7 track C), headless, min level, Thai, egg figure, touch
## off, a test settings file, scenes/main.tscn underneath. The mission screen is pushed over the main menu like CampaignFlow
## does (App.push + start(spec)); the player is scripted through the world's public API (hit_target / take_hit for shots,
## use_station for E, place_player for walking) and the world is fast-forwarded with MissionWorld.simulate():
##  1. each mission type (with secondaries) to a WIN: the intro banner names the mission, where = arena, the music mood is
##     battle, the world waits for the banner before spawning; purge kills every wave, defend holds 180 s, rescue frees the
##     three hostages (hold E in the ring) and walks them to the pickup, destroy_camp destroys three pylons and extracts;
##     finished fires exactly once with a valid MissionResult (exact §5.5 keys, outcome win, kills/shots/hits consistent,
##     secondary_done in spec order, rescue/defend extras), CampaignRules.score accepts it (win, primary 1000);
##  2. each type to a FAIL: purge on normal (two revives: the player is re-placed at the checkpoint, the third down fails),
##     defend (the base falls), rescue (every hostage dies), destroy_camp on catastrophe (no revive: the first down fails);
##  3. pause: Esc opens the pause panel, the world stops processing and its clock stands still; settings pushes over it and
##     comes back paused; resume; quit asks to confirm, cancel keeps playing, confirm finishes once with outcome quit;
##  4. seeded repeatability: the same spec gives the same first-wave spawn positions and enemy kits in two fresh worlds;
##     another seed gives other positions;
##  5. a real week spec from CampaignGalaxy.mission_spec starts and plays 20 s without errors.
## Run:
##   timeout 600 <godot> --headless --path godot --audio-driver Dummy -s tests/flow/test_mission_flow.gd
## Exit code 1 on any failure; the last line is PASS or FAIL.

const SCENE := "res://scenes/main.tscn"
const MISSION := "res://ui/screens/mission_screen.tscn"
const SETTINGS := "res://ui/screens/settings.tscn"
const SETTINGS_FILE := "user://test_mission_flow.cfg"
const Specs := preload("res://tests/fixtures/campaign_missions/specs.gd")
const RESULT_KEYS: PackedStringArray = ["v", "outcome", "time_s", "kills", "shots", "hits", "damage_taken", "downs", "secondary_done"]

var _main: Node
var _started := false
var _done := false
var _passed := 0
var _failed := 0
var _finished: Array[Dictionary] = []


func _initialize() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SETTINGS_FILE))
	var app := _app()
	app.set("settings_file", SETTINGS_FILE)
	app.call("set_gfx", "min")
	app.call("set_lang", "th")
	app.call("set_fig", "egg")
	app.call("set_touch", "off")
	var scene: PackedScene = load(SCENE)
	_main = scene.instantiate()
	_main.set("first_run_guess", false)
	root.add_child(_main)


func _process(_delta: float) -> bool:
	if not _started:
		_started = true
		_run()
	return _done


func _run() -> void:
	await _frames(3)
	# 1. wins
	await _win("purge", ["rescue"])
	await _win("defend", ["defend"])
	await _win("rescue", ["destroy_camp", "purge"])
	await _win("destroy_camp", ["rescue"])
	# 1b. the real rifle and fist against a mission enemy
	await _real_weapons()
	# 2. fails
	await _fail("purge", "normal")
	await _fail("defend", "normal")
	await _fail("rescue", "normal")
	await _fail("destroy_camp", "catastrophe")
	# 3. pause / settings / quit
	await _pause_and_quit()
	# 4. repeatability
	await _repeatable()
	# 5. a real spec of this week
	await _real_spec()
	_finish()


## Push a mission screen and wait for the intro to end.
func _open(spec: Dictionary):
	_finished.clear()
	var ms = _app().call("push", load(MISSION))
	ms.finished.connect(func(r: Dictionary) -> void: _finished.append(r))
	ms.start(spec)
	await _frames(2)
	var w = ms.world()
	_check(ms.banner_text() == _t(MissionTypes.name_th(str(spec["primary"]["type"]))),
		"%s: the intro banner names the mission (%s)" % [spec["primary"]["type"], ms.banner_text()])
	_check(w.spawned() == 0 and not w.is_physics_processing(), "%s: nothing spawns before the banner ends" % spec["primary"]["type"])
	for i in 400:
		if ms.playing():
			break
		await process_frame
	_check(ms.playing() and w.is_physics_processing(), "%s: playing after the intro" % spec["primary"]["type"])
	return ms


func _close(ms) -> void:
	for i in 600:
		if not _finished.is_empty():
			break
		await process_frame
	await _frames(3)
	if _app().call("current") == ms:
		_app().call("pop")
	await _frames(2)


func _win(ptype: String, sec: Array) -> void:
	var spec := Specs.make(ptype, {"seed": 9100 + ptype.length(), "biome": "desert", "faction": "orcs", "secondary": sec})
	var ms = await _open(spec)
	var w = ms.world()
	var net := root.get_node_or_null(^"Net")
	if net != null:
		_check(str(net.get("_where")) == "arena", "%s: friends see 'arena' during the mission" % ptype)
	var music := root.get_node_or_null(^"Music")
	if music != null and "mood" in music:
		_check(str(music.get("mood")) == "battle", "%s: battle music" % ptype)
	w.test_god = true
	var pts: Dictionary = w.layout["points"]
	match ptype:
		"purge":
			# rescue secondary first (one enemy kept alive so the purge is not won before): free the caged hostage, walk it home
			await _rescue(w, [0], true)
			for i in 200:
				if w.is_ended():
					break
				_kill_all(w)
				w.simulate(0.5)
				await process_frame
		"defend":
			# beacon secondary: E in the ring, stand 30 s
			w.place_player(pts["beacon"], 0.0)
			await _frames(1)
			_check(w.station() == "beacon", "defend: the beacon ring offers its use")
			w.use_station()
			for i in 220:
				if w.is_ended():
					break
				_kill_all(w)
				w.simulate(1.0)
				await process_frame
				if i == 40:
					w.place_player(pts["base"] + Vector3(0.0, 0.0, 3.0), 0.0)
		"rescue":
			for p in w.pylons():
				_shoot(w, p, 99999)
			await _rescue(w, [0, 1, 2])
			for i in 60:
				if w.is_ended():
					break
				_kill_all(w)
				w.simulate(0.5)
				await process_frame
		"destroy_camp":
			await _rescue(w, [0])
			w.place_player(pts["camp"], 0.0)
			w.simulate(0.2)
			for p in w.pylons():
				_shoot(w, p, 99999)
			_check(bool(w.objective_state()["primary"]["extract"]), "destroy_camp: three pylons down -> extract")
			_check(not w.is_ended(), "destroy_camp: not won before reaching the pickup")
			w.place_player(pts["pickup"], 0.0)
			w.simulate(0.2)
	await _frames(2)
	_check(w.is_ended() and w.result()["outcome"] == "win", "%s: won (%s)" % [ptype, str(w.objective_state()["primary"])])
	await _close(ms)
	_check(_finished.size() == 1, "%s: finished fired exactly once" % ptype)
	if _finished.is_empty():
		return
	var r: Dictionary = _finished[0]
	_check_result(r, spec, "win")
	var sc := CampaignRules.score(spec, r)
	_check(bool(sc["win"]) and sc["lines"].any(func(l: Dictionary) -> bool: return l["key"] == "primary" and int(l["value"]) == 1000),
		"%s: CampaignRules.score takes the result (raw %d, grade %s)" % [ptype, int(sc["raw"]), str(sc["grade"])])
	_check(r["secondary_done"] == sec.map(func(_s: Variant) -> bool: return true) or ptype == "rescue",
		"%s: secondary objectives done %s" % [ptype, str(r["secondary_done"])])


## Free the hostages with these indices (stand in the ring, E, wait) and walk to the pickup with them.
func _rescue(w, idx: Array, keep_one := false) -> void:
	var pts: Dictionary = w.layout["points"]
	for i: int in idx:
		var h = w.hostages()[i]
		w.place_player(h.position + Vector3(0.6, 0.0, 0.0), 0.0)
		await _frames(1)
		_check(w.station() == "hostage", "hostage %d: the ring offers 'free the hostage'" % i)
		w.use_station()
		_check(w.freeing() >= 0.0, "hostage %d: freeing started" % i)
		w.simulate(float(MissionTypes.HOSTAGE["free_s"]) + 0.2)
		await _frames(1)
		_check(w.obj.hostage_state(i) == MissionObjectives.FOLLOW and not h.caged(), "hostage %d: freed, the cage opened, following" % i)
	# walk to the pickup in small steps so the hostages follow the trail
	var from: Vector3 = w.player.global_position
	var to: Vector3 = pts["pickup"]
	for k in 40:
		w.place_player(from.lerp(to, float(k + 1) / 40.0), 0.0)
		_kill_all(w, keep_one)
		w.simulate(0.25)
		await process_frame
	w.simulate(3.0)
	for i: int in idx:
		_check(w.obj.hostage_state(i) == MissionObjectives.SAVED or w.is_ended(), "hostage %d reached the pickup (%s, hp %d)" % [i, w.obj.hostage_state(i), w.hostages()[i].hp()])


## The player's own rifle (aim ray from the camera, SHOT_MASK) hits a MissionEnemy: the crosshair turns red (id beast),
## shots and hits are counted from ammo_changed / hit_landed, the enemy loses HP; a punch in reach lands too.
func _real_weapons() -> void:
	var spec := Specs.make("purge", {"seed": 4321, "biome": "ruin", "faction": "orcs"})
	var ms = await _open(spec)
	var w = ms.world()
	w.test_god = true
	for i in 60:
		if not w.enemies().is_empty():
			break
		w.simulate(0.1)
	var e = w.enemies()[0]
	var foot := Vector3(0.0, 0.0, 10.0)
	w.place_player(foot, 0.0)
	e.global_position = foot + Vector3(0.0, 0.0, -6.0)
	e.set_paused(true)
	w.set_physics_process(false)
	var rig = w.player.call("camera_rig")
	var chest: Vector3 = e.chest()
	for k in 3:
		var o: Vector3 = rig.call("aim_origin")
		var d := chest - o
		rig.call("set_view", atan2(-d.x, -d.z), asin(clampf(d.y / d.length(), -1.0, 1.0)), 3.0)
		w.player.call("refresh_aim")
		await _physics(3)
	_check(bool(w.player.call("aim_on_beast")), "the crosshair turns red on a mission enemy")
	var hp0: int = e.hp()
	var shots0: int = w.obj.shots
	w.player.call("press", &"fire", true)
	await _physics(20)
	w.player.call("press", &"fire", false)
	await _physics(2)
	_check(w.obj.shots > shots0 and w.obj.hits > 0 and e.hp() < hp0,
		"the rifle hits it: %d shots, %d hits, HP %d -> %d" % [w.obj.shots - shots0, w.obj.hits, hp0, e.hp()])
	_check(w.obj.hits <= w.obj.shots, "hits never exceed shots")
	if e.is_alive():
		e.global_position = foot + Vector3(0.0, 0.0, -1.2)
		var hp1: int = e.hp()
		await _physics(2)
		w.player.call("press", &"melee", true)
		await _physics(30)
		_check(e.hp() < hp1 or not e.is_alive(), "a punch lands on it (HP %d -> %d)" % [hp1, e.hp()])
	ms.quit_mission()
	await _close(ms)


func _fail(ptype: String, diff: String) -> void:
	var spec := Specs.make(ptype, {"seed": 7300 + ptype.length(), "biome": "ice", "faction": "cult", "difficulty": diff})
	var ms = await _open(spec)
	var w = ms.world()
	match ptype:
		"purge":
			var cp: Vector3 = w.layout["player_spawn"]
			for down in 3:
				w.place_player(Vector3(0.0, 0.0, 0.0), 0.0)
				w.player.call("take_hit", {"amount": 999, "kind": &"claw"})
				await _frames(1)
				if down < 2:
					_check(not w.is_ended() and int(w.obj.revives_left) == 1 - down, "purge: down %d -> revive (%d left)" % [down + 1, w.obj.revives_left])
					for i in 300:
						if bool(w.player.call("is_alive")):
							break
						await physics_frame
					_check(Vector2(w.player.global_position.x, w.player.global_position.z).distance_to(Vector2(cp.x, cp.z)) < 0.6,
						"purge: revived at the mission checkpoint, not the arena spawn")
					await _frames(int(ArenaData.PLAYER["invuln"] * 60.0) + 4)
		"defend":
			w._apply_damage({"kind": "base"}, 100000, Vector3.ZERO, &"claw")
		"rescue":
			for h in w.hostages():
				w.obj.free_hostage(h.index)
				h.set_freed()
			for h in w.hostages():
				w._apply_damage({"kind": "hostage", "i": h.index}, 100000, Vector3.ZERO, &"claw")
		"destroy_camp":
			w.player.call("take_hit", {"amount": 999, "kind": &"claw"})
	await _frames(2)
	_check(w.is_ended() and w.result()["outcome"] == "fail", "%s (%s): failed" % [ptype, diff])
	await _close(ms)
	_check(_finished.size() == 1, "%s fail: finished fired exactly once" % ptype)
	if not _finished.is_empty():
		_check_result(_finished[0], spec, "fail")
		var sc := CampaignRules.score(spec, _finished[0])
		_check(not bool(sc["win"]) and str(sc["grade"]) == "-", "%s fail: scored as a loss" % ptype)


func _pause_and_quit() -> void:
	var spec := Specs.make("purge", {"seed": 55, "biome": "volcanic", "faction": "daemons"})
	var ms = await _open(spec)
	var w = ms.world()
	await _physics(10)
	_app().call("back")
	await _frames(2)
	_check(ms.paused() and w.paused() and not w.is_physics_processing(), "Esc opens the pause panel and stops the world")
	var t0 := float(w.obj.t)
	await _physics(20)
	_check(is_equal_approx(float(w.obj.t), t0), "the mission clock stands still while paused")
	var depth := int(_app().call("depth"))
	ms.pause_settings_button.pressed.emit()
	await _frames(3)
	_check(int(_app().call("depth")) == depth + 1, "settings opens over the mission")
	_app().call("pop")
	await _frames(3)
	_check(ms.paused() and not w.is_physics_processing(), "back from settings: still paused")
	ms.resume_button.pressed.emit()
	await _physics(5)
	_check(not ms.paused() and w.is_physics_processing(), "resume: playing again")
	_app().call("back")
	await _frames(1)
	ms.quit_button.pressed.emit()
	await _frames(1)
	_check(ms.confirm_panel.visible, "quit asks for confirmation")
	ms.confirm_no.pressed.emit()
	await _frames(1)
	_check(not ms.confirm_panel.visible and ms.paused() and _finished.is_empty(), "cancel keeps the mission")
	ms.quit_button.pressed.emit()
	ms.confirm_yes.pressed.emit()
	ms.confirm_yes.pressed.emit()
	await _close(ms)
	_check(_finished.size() == 1, "quit: finished fired exactly once")
	if not _finished.is_empty():
		_check_result(_finished[0], spec, "quit")


func _repeatable() -> void:
	var spec := Specs.make("purge", {"seed": 31337, "biome": "toxic", "faction": "raiders", "modifier": "ambush"})
	var a := _first_wave(spec)
	var b := _first_wave(spec.duplicate(true))
	var c := _first_wave(Specs.make("purge", {"seed": 31338, "biome": "toxic", "faction": "raiders", "modifier": "ambush"}))
	_check(a.size() > 0 and var_to_str(a) == var_to_str(b), "the same spec spawns the same first wave (%d enemies)" % a.size())
	_check(var_to_str(a) != var_to_str(c), "another seed spawns elsewhere")
	await _guards_spread()
	await _frames(2)


## review fix: camp guards get distinct posts (no two merged into one figure), and idle guards leave room for the hunters
func _guards_spread() -> void:
	for lv in ["hi", "min"]:
		var spec := Specs.make("destroy_camp", {"seed": 777, "biome": "desert", "faction": "orcs", "difficulty": "catastrophe"})
		var w = (load("res://scenes/campaign/mission_world.tscn") as PackedScene).instantiate()
		root.add_child(w)
		w.setup(spec, lv, false)
		w.test_god = true
		w.begin()
		w.set_physics_process(false)
		w.simulate(6.0)
		var pos: Array = []
		for e in w.enemies():
			if bool(e.get_meta("posted", false)):
				pos.append(Vector2(e.global_position.x, e.global_position.z))
		var closest := INF
		for i in pos.size():
			for j in range(i + 1, pos.size()):
				closest = minf(closest, (pos[i] as Vector2).distance_to(pos[j]))
		_check(pos.size() >= 2 and closest > 0.3, "camp guards %s: %d guards, none on top of another (closest %.2f m)" % [lv, pos.size(), closest])
		var cap: int = w.alive_cap()
		_check(w.posted_alive() <= maxi(cap - w.HUNT_RESERVE, 1), "camp guards %s: idle guards leave %d slots for hunters (%d of %d)" % [lv, w.HUNT_RESERVE, w.posted_alive(), cap])
		# the first hunting wave arrives while guards still stand
		var hunters := 0
		for _i in 40:
			w.simulate(1.0)
			hunters = w.enemies().filter(func(e) -> bool: return e.is_alive() and not bool(e.get_meta("posted", false))).size()
			if hunters > 0:
				break
		_check(hunters > 0 and w.posted_alive() > 0, "camp guards %s: the invaders' wave spawns while guards stand (%d hunters)" % [lv, hunters])
		w.queue_free()
		await _frames(1)


func _first_wave(spec: Dictionary) -> Array:
	var w = (load("res://scenes/campaign/mission_world.tscn") as PackedScene).instantiate()
	root.add_child(w)
	w.setup(spec, "min", false)
	w.begin()
	w.set_physics_process(false)
	w.simulate(2.5)
	var out: Array = []
	for e in w.enemies():
		out.append([e.name, e.kit_key(), e.role(), snapped(e.global_position.x, 0.01), snapped(e.global_position.z, 0.01)])
	w.queue_free()
	return out


func _real_spec() -> void:
	var w = 2967
	var p: Dictionary = CampaignGalaxy.week(w)["planets"][7]
	var spec := CampaignGalaxy.mission_spec(w, str(p["id"]), 0, "hard")
	var ms = await _open(spec)
	ms.world().simulate(20.0)
	await _frames(2)
	_check(ms.world().spawned() > 0, "a real week spec (%s %s) spawns enemies" % [spec["planet"], spec["primary"]["type"]])
	ms.quit_mission()
	await _close(ms)


func _check_result(r: Dictionary, spec: Dictionary, outcome: String) -> void:
	var t := str(spec["primary"]["type"])
	var keys := PackedStringArray(RESULT_KEYS)
	var has_h := t == "rescue" or (spec["secondary"] as Array).any(func(e: Dictionary) -> bool: return e["type"] == "rescue")
	if has_h:
		keys.append_array(["hostages_saved", "hostages_total"])
	if t == "defend":
		keys.append("base_hp_pct")
	var got := PackedStringArray(r.keys())
	got.sort()
	keys.sort()
	_check(got == keys, "%s %s: result keys exactly §5.5 %s" % [t, outcome, str(got)])
	_check(int(r["v"]) == 1 and str(r["outcome"]) == outcome and float(r["time_s"]) >= 0.0, "%s %s: outcome and time (%.1f s)" % [t, outcome, float(r["time_s"])])
	var k: Dictionary = r["kills"]
	_check(k.keys() == ["rusher", "gunner", "brute", "boss", "structure"], "%s %s: kills by role" % [t, outcome])
	_check(int(r["hits"]) <= int(r["shots"]) and int(r["downs"]) >= 0 and int(r["damage_taken"]) >= 0, "%s %s: hits <= shots" % [t, outcome])
	_check((r["secondary_done"] as Array).size() == (spec["secondary"] as Array).size(), "%s %s: secondary_done in spec order" % [t, outcome])


## Scripted gun shots: through hit_target like the player's rifle.
func _shoot(w, collider: Object, amount: int) -> void:
	var t: Dictionary = w.hit_target(collider)
	if t.is_empty():
		return
	(t["node"] as Object).call("take_hit", {"amount": amount, "kind": &"gun", "dir": Vector3.FORWARD, "knockback": 0.0, "stagger": false})
	w.obj.shot()
	w.obj.hit()


func _kill_all(w, keep_one := false) -> void:
	var es: Array = w.enemies()
	for i in es.size():
		if keep_one and i == 0:
			continue
		_shoot(w, es[i], 99999)


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _physics(n: int) -> void:
	for i in n:
		await physics_frame


func _app() -> Node:
	return root.get_node(^"App")


func _t(s: String) -> String:
	return str(root.get_node(^"I18n").call("t", s))


func _finish() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var app := _app()
	app.call("set_touch", "auto")
	app.set("settings_file", str(app.get("SETTINGS_PATH")))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SETTINGS_FILE))
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
