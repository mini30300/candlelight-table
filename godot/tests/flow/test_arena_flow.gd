extends SceneTree
## The weapons arena end to end (ARENA_SPEC §13.3), headless, min level, Thai, egg figures, touch off, a test settings
## file. Input goes through Input.parse_input_event (keys with keycode and physical_keycode, mouse buttons, relative
## mouse motion computed from ArenaCamera.LOOK_SPEED):
##  1. main menu -> เล่นกับบอท -> the deck (depth 2);
##  2. stick-walk from the spawn to the arena door along a free grid path: the prompt names อารีน่าทดสอบอาวุธ; walking on
##     into the doorway pushes the arena screen (depth 3), walk mode, the deck hidden and stopped, the arena camera
##     current, no Tween created on min;
##  3. hold W down the corridor: past z -11.3 shoot mode, the rifle, ammo (30, 30), aim_active(), the mouse captured;
##     the app going to the background pauses the fight, resume and one click re-captures;
## 3b. (ARENA_SPEC §9.4, H6) at (0, -14): holding D, S and A in shoot mode tells the egg it moves right, back and left
##     (move_dir() x > 0.9, y < -0.9, x < -0.9); standing again gives (0, 0) and nothing processes on min;
##  4. aim at the beast's chest and hold the left button: shots land, the beast dies after 25 hits and 300 damage (5
##     rounds left: no shot missed), the board says ล้มแล้ว · กดรีเซ็ต, the HUD showed the rifle's merged damage number;
##     the empty magazine reloads by itself with the button still held, R reloads a part-used one;
##  5. E at the reset pedestal: the beast is back on its pad with 300 HP, counters 0, toast รีเซ็ตแล้ว;
##  6. a 1.5 s burst at the switch plate turns the bot on exactly once (toast, board บอท: เปิด, beacon lit);
##  7. standing still, the beast reaches the player within 8 s and winds up for >= 0.5 s before the player loses 18 HP,
##     then 0.4 s of invulnerability;
##  8. F with the beast in reach: a punch lands, it slides >= 0.25 m within 0.4 s and flinches (state hit);
##  9. weapon 2 (the egg hears begin_switch(sword) while the rifle is still in hand, H7) and the left button: a
##     saw-sword swing lands for 45;
## 10a. walk mode at the room's edge (z -10.75, gun holstered): the beast stops chasing and never claws;
## 10b. downed (HP 0): the Downed overlay, no movement, fire ignored, the beast idle through the grace; after 2 s the
##      player gets up at RESPAWN with 100 HP, shoot mode, a full magazine, the overlay hidden, the beast still idle;
## 10c. downed at the reset pedestal, E: the reset revives the player in place and input works again;
## 10. E at the switch: the bot is off; after its current action the beast moves < 0.05 m over 1 s;
## 11. back across the shoot line: walk mode, weapon none, mouse not captured; up the corridor into the deck door -> the
##     deck (depth 2), the avatar at ARENA_RETURN, station "", the deck camera current, the egg opaque, the arena screen
##     freed; W walks the avatar away from the door on the deck (depth stays 2);
## 12. enter again: a fresh range (bot off, 300 HP, counters 0, full magazine); ‹ ล็อบบี้ returns; Esc on the deck -> the
##     main menu; this machine's settings untouched.
## Run:
##   timeout 600 <godot> --headless --path godot --audio-driver Dummy -s tests/flow/test_arena_flow.gd
## Exit code 1 on any failure; the last line is PASS or FAIL.

const SCENE := "res://scenes/main.tscn"
const ARENA_SCREEN := "res://ui/screens/arena_screen.tscn"
const SETTINGS_FILE := "user://test_arena_flow.cfg"
const GRID := 0.25
const PAD := 0.12
const STICK := 0.84
const NEAR := 0.3
const LOOK_SPEED := 0.0025       # ArenaCamera.LOOK_SPEED (rad per pixel)

var _main: Node
var _started := false
var _done := false
var _passed := 0
var _failed := 0
var _machine_cfg := ""
var _tweens := 0


func _initialize() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SETTINGS_FILE))
	_machine_cfg = _machine_settings()
	var app := _app()
	app.set("settings_file", SETTINGS_FILE)   # never write this machine's settings.cfg from a test
	app.call("set_gfx", "min")
	app.call("set_lang", "th")
	app.call("set_fig", "egg")
	app.call("set_touch", "off")
	var scene: PackedScene = load(SCENE)
	if scene == null:
		print("FAIL  cannot load " + SCENE)
		quit(1)
		return
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
	# 1
	var menu: Node = _app().call("current")
	_check(menu != null and menu.get_node_or_null("%PlayButton") != null, "1. main.tscn opens the main menu")
	if menu == null or menu.get_node_or_null("%PlayButton") == null:
		_finish()
		return
	menu.get_node("%PlayButton").pressed.emit()
	await _frames(3)
	var hall: Node = _app().call("current")
	_check(hall != null and hall.has_method("enter_arena") and int(_app().call("depth")) == 2, "1. เล่นกับบอท opens the deck (depth 2)")
	if hall == null or not hall.has_method("enter_arena"):
		_finish()
		return
	# 2
	var arena := await _walk_in(hall)
	if arena == null:
		_finish()
		return
	var world: Node3D = arena.get("world")
	var player: Node3D = world.get("player")
	var enemy: Node3D = world.get("enemy")
	if player == null or enemy == null or not player.has_method("aim_ray") or not enemy.has_method("state"):
		_check(false, "the arena has its player (ArenaPlayer) and its beast (HiveBeast)", "player %s, beast %s" % [str(player), str(enemy)])
		_finish()
		return
	# 3
	_key(KEY_W, true)
	for i in 600:
		await physics_frame
		if player.global_position.z < ArenaLayout.SHOOT_Z - 0.4:
			break
	_key(KEY_W, false)
	await _physics(30)
	_check(str(world.call("mode")) == "shoot" and str(player.call("weapon")) == "gun" and player.call("ammo") == Vector2i(30, 30)
		and bool(player.call("aim_active")) and bool(player.call("mouse_captured")),
		"3. past the shoot line: shoot mode, the rifle, ammo 30 / 30, aiming, the mouse captured (z %.2f)" % player.global_position.z)
	# review: on a phone a call or an app switch let the fight run on; the app going to the background now pauses it
	arena.notification(Node.NOTIFICATION_APPLICATION_PAUSED)
	_check(bool(arena.call("paused")) and bool(player.call("paused")), "3. the app going to the background pauses the fight")
	arena.call("close_pause")
	await _physics(2)
	_mouse(MOUSE_BUTTON_LEFT, true)
	await _physics(2)
	_mouse(MOUSE_BUTTON_LEFT, false)
	await _physics(2)
	_check(not bool(arena.call("paused")) and bool(player.call("mouse_captured")) and player.call("ammo") == Vector2i(30, 30),
		"3. resumed: the first click only re-captures the mouse (no shot)")
	await _physics(20)
	# 3b: H6, moving while aiming tells the figure its own move direction
	var p3 := player.global_position
	world.call("place_player", Vector3(0.0, 0.0, -14.0), PI, 0.0)
	await _physics(6)
	var fig3: Node3D = player.call("figure")
	var dirs := {}
	for k: Array in [[KEY_D, "D"], [KEY_S, "S"], [KEY_A, "A"]]:
		_key(k[0], true)
		await _physics(int(0.4 * Engine.physics_ticks_per_second))
		dirs[k[1]] = fig3.call("move_dir") if fig3 != null and fig3.has_method("move_dir") else Vector2.ZERO
		_key(k[0], false)
		await _physics(int(0.3 * Engine.physics_ticks_per_second))
	_check((dirs["D"] as Vector2).x > 0.9 and (dirs["S"] as Vector2).y < -0.9 and (dirs["A"] as Vector2).x < -0.9 and str(world.call("mode")) == "shoot",
		"3b. shoot mode: D, S and A tell the egg it moves right, back and left", str(dirs))
	await _physics(int(0.5 * Engine.physics_ticks_per_second))
	await _frames(12)
	# move_dir() is an extra of the egg (not in FIGURE_API): read it once, guarded, so a figure without it fails the check
	var md3: Vector2 = fig3.call("move_dir") if fig3 != null and fig3.has_method("move_dir") else Vector2(9, 9)
	_check(fig3 != null and md3 == Vector2.ZERO and not player.is_physics_processing() and not fig3.is_processing(),
		"3b. standing again: direction (0, 0), and on min neither the player nor the egg processes",
		"%s, player %s, egg %s" % [str(md3), str(player.is_physics_processing()), str(fig3 != null and fig3.is_processing())])
	world.call("place_player", p3, PI, 0.0)
	await _physics(6)
	# 4
	await _aim_at(player, enemy.global_position + Vector3(0.0, 1.4, 0.0))
	var hp0 := int(enemy.call("hp"))
	var hud: Node = arena.get("hud")
	_mouse(MOUSE_BUTTON_LEFT, true)
	var died_at := -1
	var nums := 0
	var red_alive := false
	for i in 600:
		await physics_frame
		if hud != null:
			nums = maxi(nums, int(hud.call("numbers_alive")))
		red_alive = red_alive or (bool(enemy.call("is_alive")) and bool(player.call("aim_on_beast")))
		if died_at < 0 and not bool(enemy.call("is_alive")):
			died_at = (player.call("ammo") as Vector2i).x
		if (player.call("ammo") as Vector2i).x == 0:
			break
	await _physics(1)
	var auto_reload: bool = (player.get("weapons") as ArenaWeapons).reloading()
	_mouse(MOUSE_BUTTON_LEFT, false)
	await _physics(10)
	var st: Dictionary = world.call("stats")
	_check(hp0 == 300 and str(enemy.call("state")) == "dead" and int(st["hits"]) == 25 and int(st["damage"]) == 300,
		"4. the beast dies after 25 hits and 300 damage", str(st))
	_check(died_at == 5, "4. it died with 5 rounds left: every shot landed (%d left)" % died_at)
	_check(str(world.call("sign_text", "board_body")).contains("ล้มแล้ว · กดรีเซ็ต"), "4. the board says ล้มแล้ว · กดรีเซ็ต")
	# review: the red "on target" crosshair stayed red over the fallen beast until the mouse moved
	_check(red_alive and not bool(player.call("aim_on_beast")) and (hud == null or not bool(hud.call("crosshair_hot"))),
		"4. the crosshair was red on the living beast and is no longer red once it is down (aim not moved)")
	# sampled while firing (the numbers live 0.6 s on min); rifle hits on one target merge into one number
	_check(hud != null and nums >= 1 and nums <= 2, "4. the HUD showed the damage number while firing, rifle hits merged (up to %d at once)" % nums)
	# changed on purpose at integration (ARENA_SPEC §17): the empty magazine reloads by itself while fire is held
	_check(auto_reload, "4. the empty magazine started reloading by itself with the button still held")
	await _physics(int(1.8 * Engine.physics_ticks_per_second))
	_check(player.call("ammo") == Vector2i(30, 30), "4. …and is full again 1.6 s later (%s)" % str(player.call("ammo")))
	# review: switching the bot on over the fallen beast said it was chasing; it now says it takes effect after reset
	world.call("toggle_bot", &"use")
	await _physics(2)
	_check((arena.get_node("%Toast") as Label).text == "บอทเปิด — มีผลหลังรีเซ็ต" and bool((world.call("stats") as Dictionary)["bot_on"]) and str(enemy.call("state")) == "dead",
		"4. the bot switched on over the fallen beast: the toast says it takes effect after reset", (arena.get_node("%Toast") as Label).text)
	await _physics(int(1.05 * Engine.physics_ticks_per_second))
	world.call("toggle_bot", &"use")
	_mouse(MOUSE_BUTTON_LEFT, true)
	await _physics(int(0.3 * Engine.physics_ticks_per_second))
	_mouse(MOUSE_BUTTON_LEFT, false)
	await _physics(4)
	var part := (player.call("ammo") as Vector2i).x
	await _press(KEY_R)
	await _physics(int(1.8 * Engine.physics_ticks_per_second))
	_check(part < 30 and player.call("ammo") == Vector2i(30, 30), "4. R reloads a part-used magazine (%d -> 30)" % part)
	# 5
	var rf: Vector2 = ArenaLayout.STATIONS["reset"]["front"]
	world.call("place_player", Vector3(rf.x, 0.0, rf.y), -PI * 0.5, PI * 0.5)
	await _physics(6)
	_check(str(world.call("station")) == "reset", "5. the player stands at the reset pedestal")
	await _press(KEY_E)
	await _physics(4)
	st = world.call("stats")
	var pad := Vector2(ArenaLayout.BEAST_SPAWN.x, ArenaLayout.BEAST_SPAWN.z)
	_check(bool(enemy.call("is_alive")) and int(enemy.call("hp")) == 300 and Vector2(enemy.global_position.x, enemy.global_position.z).distance_to(pad) < 0.1
		and int(st["hits"]) == 0 and int(st["damage"]) == 0, "5. reset: the beast is back on its pad with 300 HP, counters 0", str(st))
	_check((arena.get_node("%Toast") as Label).visible and (arena.get_node("%Toast") as Label).text == "รีเซ็ตแล้ว", "5. toast รีเซ็ตแล้ว")
	# 6
	world.call("place_player", Vector3(0.0, 0.0, -12.5), PI, 0.0)
	await _physics(10)
	var plate: Vector3 = ArenaLayout.STATIONS["switch"]["plate"]
	await _aim_at(player, plate)
	var toggles := [0]
	var cb := func(_on: bool, _how: StringName) -> void: toggles[0] += 1
	world.connect("bot_toggled", cb)
	# a burst longer than the 1 s cooldown (review: holding fire on the plate turned the bot on and then off again)
	_mouse(MOUSE_BUTTON_LEFT, true)
	await _physics(int(1.5 * Engine.physics_ticks_per_second))
	_mouse(MOUSE_BUTTON_LEFT, false)
	await _physics(4)
	world.disconnect("bot_toggled", cb)
	_check(toggles[0] == 1 and bool((world.call("stats") as Dictionary)["bot_on"]) and bool(world.call("beacon_lit")),
		"6. a 1.5 s burst at the plate turns the bot on exactly once (%d toggles), the beacon lit" % toggles[0])
	_check((arena.get_node("%Toast") as Label).text == "บอทเปิด — สัตว์รังไล่ตามคุณแล้ว" and str(world.call("sign_text", "board_body")).begins_with("บอท: เปิด"),
		"6. toast and board say the bot is on", (arena.get_node("%Toast") as Label).text + " | " + str(world.call("sign_text", "board_body")))
	# 7
	var hp_p := int(player.call("hp"))
	var reached := false
	var windup_t := 0.0
	var hit_after := -1.0
	for i in int(10.0 * Engine.physics_ticks_per_second):
		await physics_frame
		var s := str(enemy.call("state"))
		if s == "windup" or s == "strike":
			reached = true
			windup_t += 1.0 / Engine.physics_ticks_per_second
		if int(player.call("hp")) < hp_p:
			hit_after = windup_t
			break
	_check(reached and hit_after >= 0.5 and hp_p - int(player.call("hp")) == 18,
		"7. the beast reaches the player and winds up for %.2f s before the claw takes 18 HP (%d -> %d)" % [hit_after, hp_p, int(player.call("hp"))])
	var hp_after := int(player.call("hp"))
	var res: Dictionary = player.call("take_hit", {"amount": 18, "kind": &"claw", "point": player.global_position, "dir": Vector3.BACK,
		"from": enemy.global_position, "knockback": 0.0, "stagger": false})
	_check(int(res.get("applied", -1)) == 0 and int(player.call("hp")) == hp_after, "7. 0.4 s of invulnerability after the hit")
	# 8
	for i in int(3.0 * Engine.physics_ticks_per_second):
		var d := Vector2(enemy.global_position.x - player.global_position.x, enemy.global_position.z - player.global_position.z).length()
		if d <= 1.6 + float(enemy.call("radius")) - 0.1 and str(enemy.call("state")) != "strike":
			break
		await physics_frame
	await _aim_at(player, enemy.global_position + Vector3(0.0, 1.2, 0.0))
	var e0 := enemy.global_position
	await _press(KEY_F)
	var slid := 0.0
	var flinched := false
	for i in int(0.4 * Engine.physics_ticks_per_second):
		await physics_frame
		slid = maxf(slid, Vector2(enemy.global_position.x - e0.x, enemy.global_position.z - e0.z).length())
		flinched = flinched or str(enemy.call("state")) == "hit"
	_check(slid >= 0.25 and flinched, "8. the punch knocks the beast back %.2f m and makes it flinch" % slid)
	# 9
	var fig9: Node3D = player.call("figure")
	await _press(KEY_2)
	# last_switch() is an extra of the egg (not in FIGURE_API), guarded so a figure without it fails this check instead of
	# stopping the run; the weapon in hand is the player's (ArenaWeapons.current: still the rifle until the swap point)
	var has9 := fig9 != null and fig9.has_method("last_switch")
	var heard := [fig9.call("last_switch"), player.call("weapon")] if has9 else []
	await _physics(int(0.4 * Engine.physics_ticks_per_second))
	var fw9: StringName = fig9.call("weapon") if has9 and fig9.has_method("weapon") else player.call("weapon")
	_check(has9 and heard == [&"sword", &"gun"] and player.call("weapon") == &"sword" and fw9 == &"sword",
		"9. weapon 2: the egg hears begin_switch(sword) with the rifle still in hand, then set_weapon(sword)", str(heard))
	await _aim_at(player, enemy.global_position + Vector3(0.0, 1.2, 0.0))
	var amounts: Array = []
	var cb2 := func(info: Dictionary) -> void: amounts.append(int(info.get("amount", 0)))
	enemy.connect("damaged", cb2)
	_mouse(MOUSE_BUTTON_LEFT, true)
	await _physics(int(0.4 * Engine.physics_ticks_per_second))
	_mouse(MOUSE_BUTTON_LEFT, false)
	await _physics(int(0.3 * Engine.physics_ticks_per_second))
	enemy.disconnect("damaged", cb2)
	_check(str(player.call("weapon")) == "sword" and amounts.has(45), "9. a saw-sword swing lands for 45 (%s)" % str(amounts))
	# 10a: walk mode at the room's edge, the gun holstered: the beast must not hunt a player who cannot fight back
	world.call("place_player", Vector3(0.0, 0.0, -10.75), PI, 0.0)
	await _physics(6)
	var hp_edge := int(player.call("hp"))
	var hunted := ""
	for i in int(4.0 * Engine.physics_ticks_per_second):
		await physics_frame
		var es := str(enemy.call("state"))
		if i > int(1.5 * Engine.physics_ticks_per_second) and hunted == "" and es in ["chase", "windup", "strike"]:
			hunted = "%s at %.2f s" % [es, float(i) / Engine.physics_ticks_per_second]
	_check(str(world.call("mode")) == "walk" and str(player.call("weapon")) == "none" and int(player.call("hp")) == hp_edge and hunted == "",
		"10a. walk mode at the room's edge (z -10.75, gun holstered): the beast stops hunting and never claws (HP %d -> %d)" % [hp_edge, int(player.call("hp"))], hunted)
	# 10b: downed, then up again at RESPAWN
	world.call("place_player", Vector3(0.0, 0.0, -14.0), PI, 0.0)
	await _physics(6)
	await _down(player)
	var downed_ui: CanvasItem = hud.get_node("Downed") if hud != null else null
	_check(bool(player.call("is_downed")) and int(player.call("hp")) == 0 and downed_ui != null and downed_ui.visible,
		"10b. at 0 HP the player is downed and the Downed overlay shows")
	var p_down := player.global_position
	_key(KEY_W, true)
	await _physics(10)
	var still: bool = player.global_position.distance_to(p_down) < 0.01 and player.call("input_vector") == Vector2.ZERO
	_key(KEY_W, false)
	_mouse(MOUSE_BUTTON_LEFT, true)
	await _physics(2)
	var trigger_on: bool = (player.get("weapons") as ArenaWeapons).trigger
	_mouse(MOUSE_BUTTON_LEFT, false)
	_check(still and not trigger_on, "10b. while downed W does not move it and fire is ignored")
	var hunting_down := ""
	var t_down := 12
	while bool(player.call("is_downed")) and t_down < int(3.0 * Engine.physics_ticks_per_second):
		await physics_frame
		t_down += 1
		var es := str(enemy.call("state"))
		if t_down > int(1.2 * Engine.physics_ticks_per_second) and hunting_down == "" and es != "idle":
			hunting_down = "%s at %.2f s" % [es, float(t_down) / Engine.physics_ticks_per_second]
	_check(hunting_down == "", "10b. the beast goes idle while the player is down (grace)", hunting_down)
	await _physics(2)
	var rs := ArenaLayout.RESPAWN
	_check(not bool(player.call("is_downed")) and int(player.call("hp")) == 100 and Vector2(player.global_position.x, player.global_position.z).distance_to(Vector2(rs.x, rs.z)) < 0.05
		and str(world.call("mode")) == "shoot" and player.call("ammo") == Vector2i(30, 30) and not downed_ui.visible,
		"10b. after %.2f s the player gets up at RESPAWN: 100 HP, shoot mode, 30 / 30, the overlay hidden" % (float(t_down) / Engine.physics_ticks_per_second))
	await _physics(int(0.3 * Engine.physics_ticks_per_second))
	_check(str(enemy.call("state")) == "idle", "10b. the beast is still idle in the rest of its grace (%s)" % str(enemy.call("state")))
	# 10c: downed at the reset pedestal, E revives in place
	var rf2: Vector2 = ArenaLayout.STATIONS["reset"]["front"]
	world.call("place_player", Vector3(rf2.x, 0.0, rf2.y), -PI * 0.5, PI * 0.5)
	await _physics(6)
	await _down(player)
	var p_reset := player.global_position
	_check(bool(player.call("is_downed")) and str(world.call("station")) == "reset", "10c. downed at the reset pedestal")
	await _press(KEY_E)
	await _physics(2)
	_check(not bool(player.call("is_downed")) and int(player.call("hp")) == 100 and not downed_ui.visible and player.global_position.distance_to(p_reset) < 0.05,
		"10c. E resets the range: the player gets up in place with 100 HP, the overlay hidden")
	var p_up := player.global_position
	_key(KEY_S, true)
	await _physics(20)
	_key(KEY_S, false)
	await _physics(6)
	_check(player.global_position.distance_to(p_up) > 0.3, "10c. …and input works again (moved %.2f m)" % player.global_position.distance_to(p_up))
	# 10
	var sf: Vector2 = ArenaLayout.STATIONS["switch"]["front"]
	world.call("place_player", Vector3(sf.x, 0.0, sf.y), PI * 0.5, -PI * 0.5)
	await _physics(6)
	await _press(KEY_E)
	_check(not bool((world.call("stats") as Dictionary)["bot_on"]), "10. E at the switch turns the bot off")
	await _physics(int(1.5 * Engine.physics_ticks_per_second))
	var b0 := enemy.global_position
	await _physics(int(1.0 * Engine.physics_ticks_per_second))
	_check(enemy.global_position.distance_to(b0) < 0.05 and str(enemy.call("state")) == "dummy", "10. the beast stands still as a target (%.3f m in 1 s)" % enemy.global_position.distance_to(b0))
	# 11
	world.call("place_player", Vector3(0.0, 0.0, -12.0), PI, 0.0)
	await _physics(6)
	_key(KEY_S, true)
	# checked on every frame between the lines, reported once
	var walk_frames := 0
	var walk_bad := ""
	for i in 600:
		await physics_frame
		if int(_app().call("depth")) != 3:
			break
		if str(world.call("mode")) == "walk" and player.global_position.z > -10.4 and player.global_position.z < -9.8:
			walk_frames += 1
			# headless never really captures the OS cursor: the player's own flag is the check
			if walk_bad == "" and not (str(player.call("weapon")) == "none" and not bool(player.call("mouse_captured")) and Input.mouse_mode == Input.MOUSE_MODE_VISIBLE):
				walk_bad = "weapon %s, captured %s, mouse mode %d at z %.2f" % [str(player.call("weapon")), str(player.call("mouse_captured")), Input.mouse_mode, player.global_position.z]
	_key(KEY_S, false)
	_check(walk_frames > 0 and walk_bad == "", "11. back in walk mode: weapon none, the mouse not captured (%d frames)" % walk_frames, walk_bad)
	await _frames_until(func() -> bool: return _app().call("current") == hall and not bool(hall.call("fading")), 120)
	var hw: Node3D = hall.get("world")
	var av: Node3D = hw.get("avatar")
	await _physics(6)
	_check(int(_app().call("depth")) == 2 and av.global_position.distance_to(HallLayout.ARENA_RETURN) < 0.01 and str(hall.call("station")) == ""
		and (hw.get("camera_rig").get("camera") as Camera3D).current and float(hw.call("avatar_alpha")) >= 0.999,
		"11. up the corridor into the deck door: the deck at ARENA_RETURN, no station, its camera current, the egg opaque")
	_check(not is_instance_valid(arena) or arena.is_queued_for_deletion(), "11. the arena screen is freed")
	var a0 := av.global_position
	_key(KEY_W, true)
	await _physics(30)
	_key(KEY_W, false)
	await _physics(10)
	_check(av.global_position.distance_to(a0) > 0.3 and int(_app().call("depth")) == 2 and not bool(hall.call("fading")),
		"11. on the deck W walks the avatar away from the door again (%.2f m, depth %d)" % [av.global_position.distance_to(a0), int(_app().call("depth"))])
	# 12
	hall.call("enter_arena")
	await _frames_until(func() -> bool: return int(_app().call("depth")) == 3, 120)
	var a2: Node = _app().call("current")
	await _frames(4)
	var w2: Node3D = a2.get("world") if a2 != null else null
	var ok2 := w2 != null
	if ok2:
		var s2: Dictionary = w2.call("stats")
		var p2: Node3D = w2.get("player")
		ok2 = not bool(s2["bot_on"]) and int(s2["hp"]) == 300 and int(s2["hits"]) == 0 and int(s2["damage"]) == 0 and p2 != null and p2.call("ammo") == Vector2i(30, 30)
	_check(ok2, "12. entering again gives a fresh range: bot off, 300 HP, counters 0, full magazine")
	if a2 != null:
		(a2.get_node("%LobbyButton") as Button).pressed.emit()
	await _frames_until(func() -> bool: return _app().call("current") == hall and not bool(hall.call("fading")), 120)
	_check(_app().call("current") == hall, "12. ‹ ล็อบบี้ returns to the deck")
	await _press(KEY_ESCAPE)
	var m2: Node = _app().call("current")
	_check(m2 != null and m2.get_node_or_null("%PlayButton") != null and int(_app().call("depth")) == 1, "12. Esc on the deck returns to the main menu")
	_check(_tweens == 0, "no Tween was created by the fades on min (%d)" % _tweens)
	_check(_machine_settings() == _machine_cfg, "12. this machine's settings.cfg was not touched")
	_finish()


## Step 2: stick-walk from the spawn to the arena door's ring, then on into the doorway.
func _walk_in(hall: Node) -> Node:
	var world: Node3D = hall.get("world")
	var av := world.get("avatar") as Node3D
	var rig: Node3D = world.get("camera_rig")
	rig.call("set_view", 0.0, -0.45, 6.5)
	world.call("place_avatar", HallLayout.SPAWN, PI)
	await _physics(4)
	var goal: Vector2 = HallLayout.STATIONS["arena"]["front"]
	var path := _path(HallLayout.spawn_xz(), goal)
	_check(not path.is_empty(), "2. a free path leads from the spawn to the arena door")
	var k := 0
	var ticks := 0
	while str(hall.call("station")) != "arena" and ticks < 1500 and not path.is_empty():
		var p := Vector2(av.global_position.x, av.global_position.z)
		var far := k
		for j in range(k + 1, mini(k + 24, path.size())):
			if _line_free(p, path[j]):
				far = j
		k = far
		while k < path.size() - 1 and p.distance_to(path[k]) < NEAR:
			k += 1
		var d := path[k] - p
		var dir := Vector3(d.x, 0.0, d.y).normalized() if d.length() > 0.01 else Vector3.ZERO
		world.call("set_stick", Vector2(dir.dot(rig.call("right_flat")), dir.dot(rig.call("forward_flat"))) * STICK)
		await physics_frame
		ticks += 1
	var use: Button = hall.get_node("%UseButton")
	_check(str(hall.call("station")) == "arena" and use.visible and use.text.contains("อารีน่าทดสอบอาวุธ"), "2. at the door the prompt names อารีน่าทดสอบอาวุธ (%s)" % use.text)
	_check(int(_app().call("depth")) == 2, "2. the prompt alone does not enter")
	# keep walking straight into the doorway (+z)
	var t0 := get_frame()
	for i in 240:
		var p := Vector2(av.global_position.x, av.global_position.z)
		var dir := Vector3(goal.x - p.x, 0.0, 1.0).normalized()
		world.call("set_stick", Vector2(dir.dot(rig.call("right_flat")), dir.dot(rig.call("forward_flat"))) * STICK)
		await physics_frame
		if int(_app().call("depth")) == 3:
			break
	world.call("set_stick", Vector2.ZERO)
	await _frames(4)
	var arena: Node = _app().call("current")
	_check(int(_app().call("depth")) == 3 and arena != null and arena.scene_file_path == ARENA_SCREEN,
		"2. walking on into the doorway pushes the arena screen (depth 3, %d frames)" % (get_frame() - t0))
	if arena == null or arena.scene_file_path != ARENA_SCREEN:
		return null
	var aw: Node3D = arena.get("world")
	_check(str(aw.call("mode")) == "walk" and not (hall as CanvasItem).visible and not world.visible and world.process_mode == Node.PROCESS_MODE_DISABLED
		and (aw.call("camera") as Camera3D).current, "2. walk mode, the deck hidden and stopped, the arena camera current")
	_check(hall.get("_fade_tween") == null and arena.get("_fade_tween") == null, "2. no Tween created on min")
	if hall.get("_fade_tween") != null or arena.get("_fade_tween") != null:
		_tweens += 1
	await _frames(4)
	return arena


## Claws the player (18 a hit, past the 0.4 s invulnerability) until it is downed.
func _down(player: Node3D) -> void:
	for i in 12:
		if bool(player.call("is_downed")):
			return
		player.call("take_hit", {"amount": 18, "kind": &"claw", "point": player.global_position + Vector3(0.0, 1.2, 0.0),
			"dir": Vector3.BACK, "from": player.global_position + Vector3(0.0, 0.0, -1.5), "knockback": 0.0, "stagger": false})
		if bool(player.call("is_downed")):
			return
		await _physics(int(0.45 * Engine.physics_ticks_per_second))


## Turns the shoulder camera onto the point t with relative mouse motion (LOOK_SPEED rad per pixel), twice to settle.
func _aim_at(player: Node3D, t: Vector3) -> void:
	var rig: Node3D = player.call("camera_rig")
	var cam: Camera3D = player.call("camera")
	for n in 3:
		await _physics(3)
		await _frames(1)
		var c := cam.global_position
		var d := t - c
		var want_yaw := atan2(-d.x, -d.z)
		var want_pitch := atan2(d.y, Vector2(d.x, d.z).length())
		var dy := wrapf(want_yaw - float(rig.get("yaw")), -PI, PI)
		var dp := want_pitch - float(rig.get("pitch"))
		# relative motion arrives in window pixels; the viewport divides it by the stretch scale (headless windows are small).
		# The player aims with screen_relative (screen pixels, the same speed at any window size): no scale there.
		var ev := InputEventMouseMotion.new()
		ev.relative = Vector2(-dy, -dp) / LOOK_SPEED * root.get_final_transform().get_scale()
		ev.screen_relative = Vector2(-dy, -dp) / LOOK_SPEED
		ev.position = root.get_visible_rect().get_center()
		Input.parse_input_event(ev)
		Input.flush_buffered_events()
	await _physics(4)


func _path(a: Vector2, b: Vector2) -> PackedVector2Array:
	var nx := int(HallLayout.HALF.x * 2.0 / GRID)
	var nz := int(HallLayout.HALF.y * 2.0 / GRID)
	var free := PackedByteArray()
	free.resize(nx * nz)
	for k in nz:
		for i in nx:
			free[k * nx + i] = 0 if HallLayout.blocked(_cell(i, k), HallLayout.AVATAR_R + PAD) else 1
	var s := _index(a, nx)
	var g := -1
	var best := INF
	for c in free.size():
		var dd := _cell(c % nx, c / nx).distance_to(b)
		if free[c] == 1 and dd < best:
			best = dd
			g = c
	if g == -1 or best > 0.6 or free[s] == 0:
		return PackedVector2Array()
	var prev := PackedInt32Array()
	prev.resize(nx * nz)
	prev.fill(-1)
	prev[s] = s
	var queue := PackedInt32Array([s])
	var head := 0
	while head < queue.size() and prev[g] == -1:
		var c := queue[head]
		head += 1
		var ci := c % nx
		var ck := c / nx
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1)]:
			var ii: int = ci + d.x
			var kk: int = ck + d.y
			if ii < 0 or kk < 0 or ii >= nx or kk >= nz:
				continue
			var n := kk * nx + ii
			if free[n] == 0 or prev[n] != -1:
				continue
			if d.x != 0 and d.y != 0 and (free[ck * nx + ii] == 0 or free[kk * nx + ci] == 0):
				continue
			prev[n] = c
			queue.append(n)
	if prev[g] == -1:
		return PackedVector2Array()
	var rev := PackedVector2Array([b])
	var c2 := prev[g]
	while c2 != s:
		rev.append(_cell(c2 % nx, c2 / nx))
		c2 = prev[c2]
	rev.append(a)
	rev.reverse()
	return rev


func _line_free(a: Vector2, b: Vector2) -> bool:
	var n := maxi(int(a.distance_to(b) / 0.1), 1)
	for i in n + 1:
		if HallLayout.blocked(a.lerp(b, float(i) / n), HallLayout.AVATAR_R + PAD * 0.5):
			return false
	return true


func _cell(i: int, k: int) -> Vector2:
	return Vector2(-HallLayout.HALF.x + (i + 0.5) * GRID, -HallLayout.HALF.y + (k + 0.5) * GRID)


func _index(p: Vector2, nx: int) -> int:
	var i := clampi(int((p.x + HallLayout.HALF.x) / GRID), 0, nx - 1)
	var k := clampi(int((p.y + HallLayout.HALF.y) / GRID), 0, int(HallLayout.HALF.y * 2.0 / GRID) - 1)
	return k * nx + i


func _press(code: Key) -> void:
	_key(code, true)
	await _frames(1)
	await _physics(1)
	_key(code, false)
	await _frames(2)


func _key(code: Key, pressed: bool) -> void:
	var ev := InputEventKey.new()
	ev.keycode = code
	ev.physical_keycode = code
	ev.pressed = pressed
	Input.parse_input_event(ev)
	Input.flush_buffered_events()


func _mouse(button: MouseButton, pressed: bool) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = button
	ev.pressed = pressed
	ev.position = root.get_visible_rect().get_center()
	ev.global_position = ev.position
	Input.parse_input_event(ev)
	Input.flush_buffered_events()


func _frames_until(cond: Callable, n: int) -> void:
	for i in n:
		if cond.call():
			return
		await process_frame


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _physics(n: int) -> void:
	for i in n:
		await physics_frame


func _app() -> Node:
	return root.get_node(^"App")


func _machine_settings() -> String:
	var p := "user://settings.cfg"
	return "%d:%s" % [FileAccess.get_modified_time(p), FileAccess.get_file_as_string(p)] if FileAccess.file_exists(p) else "none"


func _finish() -> void:
	for k in [KEY_W, KEY_A, KEY_S, KEY_D, KEY_SHIFT, KEY_E, KEY_F, KEY_R]:
		_key(k, false)
	_mouse(MOUSE_BUTTON_LEFT, false)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var app := _app()
	app.call("set_lang", "th")
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
