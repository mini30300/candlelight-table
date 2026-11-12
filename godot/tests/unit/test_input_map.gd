extends "res://tests/testing.gd"
## The input map of project.godot (LOBBY_SPEC §6.2): seven actions bound to physical keys, so WASD and the
## arrows work whatever the keyboard layout (a Thai layout included), and a parsed physical W presses
## move_forward.
## 0.4 (ARENA_SPEC §5.2, §13.1): five shooter actions join them on purpose (seven become twelve): fire (left mouse
## button), melee (right mouse button or physical F), reload (R), weapon_1 / weapon_2 (1 / 2); mouse buttons are
## checked as InputEventMouseButton.

const EXPECTED := {
	"move_forward": [KEY_W, KEY_UP],
	"move_back": [KEY_S, KEY_DOWN],
	"move_left": [KEY_A, KEY_LEFT],
	"move_right": [KEY_D, KEY_RIGHT],
	"run": [KEY_SHIFT],
	"interact": [KEY_E],
	"back": [KEY_ESCAPE],
	"fire": [],
	"melee": [KEY_F],
	"reload": [KEY_R],
	"weapon_1": [KEY_1],
	"weapon_2": [KEY_2],
}
## mouse buttons of the shooter actions (ARENA_SPEC §5.2)
const MOUSE := {
	"fire": [MOUSE_BUTTON_LEFT],
	"melee": [MOUSE_BUTTON_RIGHT],
}


func test_actions_and_physical_keys() -> void:
	for action in EXPECTED:
		assert_true(InputMap.has_action(action), "action exists: " + action)
		if not InputMap.has_action(action):
			continue
		var phys := []
		var logical := []
		for ev in InputMap.action_get_events(action):
			if ev is InputEventKey:
				phys.append((ev as InputEventKey).physical_keycode)
				logical.append((ev as InputEventKey).keycode)
		phys.sort()
		var want: Array = EXPECTED[action].duplicate()
		want.sort()
		assert_eq(phys, want, action + " is bound to its physical keys")
		assert_eq(logical, logical.map(func(_k: int) -> int: return 0), action + " uses physical keycodes only (keycode 0)")


func test_events_match_whatever_the_layout() -> void:
	for action in EXPECTED:
		for code in EXPECTED[action]:
			var ev := InputEventKey.new()
			ev.physical_keycode = code
			ev.keycode = KEY_NONE
			ev.unicode = 0x0E44 if code == KEY_W else 0   # ไ: what W types on a Thai layout
			ev.pressed = true
			assert_true(ev.is_action_pressed(action), "%s: physical %s presses it" % [action, OS.get_keycode_string(code)])
	var esc := InputEventKey.new()
	esc.physical_keycode = KEY_ESCAPE
	esc.pressed = true
	assert_false(esc.is_action(&"move_forward"), "Esc is not a move key")


func test_parsed_physical_w_presses_move_forward() -> void:
	var ev := InputEventKey.new()
	ev.physical_keycode = KEY_W
	ev.pressed = true
	Input.parse_input_event(ev)
	Input.flush_buffered_events()
	assert_true(Input.is_action_pressed(&"move_forward"), "a parsed physical W holds move_forward")
	assert_true(Input.get_action_strength(&"move_forward") > 0.99, "…at full strength")
	var up := InputEventKey.new()
	up.physical_keycode = KEY_W
	up.pressed = false
	Input.parse_input_event(up)
	Input.flush_buffered_events()
	assert_false(Input.is_action_pressed(&"move_forward"), "releasing W releases move_forward")


func test_twelve_actions_and_mouse_buttons() -> void:
	assert_eq(EXPECTED.size(), 12, "twelve actions: seven of the deck + five of the arena shooter")
	for action in MOUSE:
		assert_true(InputMap.has_action(action), "action exists: " + action)
		if not InputMap.has_action(action):
			continue
		var buttons := []
		for ev in InputMap.action_get_events(action):
			if ev is InputEventMouseButton:
				buttons.append((ev as InputEventMouseButton).button_index)
		assert_eq(buttons, MOUSE[action], action + " is bound to its mouse button")
		var press := InputEventMouseButton.new()
		press.button_index = MOUSE[action][0]
		press.pressed = true
		assert_true(press.is_action_pressed(action), action + ": a press of its mouse button presses it")
	for action in ["move_forward", "interact", "reload", "weapon_1", "weapon_2"]:
		for ev in InputMap.action_get_events(action):
			assert_false(ev is InputEventMouseButton, action + " has no mouse button")
	var wheel := InputEventMouseButton.new()
	wheel.button_index = MOUSE_BUTTON_WHEEL_UP
	wheel.pressed = true
	assert_false(wheel.is_action(&"fire") or wheel.is_action(&"melee"), "the wheel is read in code, not bound to fire or melee")
