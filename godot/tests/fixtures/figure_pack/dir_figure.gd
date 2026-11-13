extends "prim_figure.gd"
## The primitive figure with the optional H6 method (ARENA_SPEC §9.4): set_move_dir(local_dir, speed, running) counts
## itself in `calls`, keeps the direction in last_dir and runs the parent's movement logic without counting a set_move;
## set_move (the deck's call) resets last_dir to (0, 1) as §9.4 says. Primitives only, no model files.

var last_dir := Vector2(0.0, 1.0)


func set_move_dir(local_dir: Vector2, speed: float, running: bool) -> void:
	_count("set_move_dir")
	last_dir = local_dir
	_move(speed, running)


func set_move(speed: float, running: bool) -> void:
	_count("set_move")
	last_dir = Vector2(0.0, 1.0)
	_move(speed, running)


## the parent's set_move without its count
func _move(speed: float, running: bool) -> void:
	super.set_move(speed, running)
	calls["set_move"] = int(calls.get("set_move", 0)) - 1
	if int(calls["set_move"]) <= 0:
		calls.erase("set_move")
