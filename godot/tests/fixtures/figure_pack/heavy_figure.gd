extends "dir_figure.gd"
## The H6 fixture plus the optional H8 and H9 methods (ARENA_SPEC §9.4): begin_dodge(local_dir, duration) counts
## itself and keeps its arguments; uses_strafe() returns false, so the player turns this figure to face where it moves
## in shoot mode. Primitives only, no model files.

var last_dodge := {}


func begin_dodge(local_dir: Vector2, duration: float) -> void:
	_count("begin_dodge")
	last_dodge = {"dir": local_dir, "duration": duration}


func uses_strafe() -> bool:
	return false
