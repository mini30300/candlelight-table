extends "res://tests/testing.gd"
## The input map of project.godot (LOBBY_SPEC §6.2): seven actions bound to physical keys, so WASD and the
## arrows work whatever the keyboard layout (a Thai layout included), and a parsed physical W presses
## move_forward.

const EXPECTED := {
	"move_forward": [KEY_W, KEY_UP],
	"move_back": [KEY_S, KEY_DOWN],
	"move_left": [KEY_A, KEY_LEFT],
	"move_right": [KEY_D, KEY_RIGHT],
	"run": [KEY_SHIFT],
	"interact": [KEY_E],
	"back": [KEY_ESCAPE],
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
