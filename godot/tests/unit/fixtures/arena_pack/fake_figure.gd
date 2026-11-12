extends Node3D
## A pack figure for test_arena_actors: every method of the figure contract (ARENA_SPEC §9.1), doing nothing.

signal clip_event(kind: StringName)


func setup(_opts: Dictionary) -> void:
	pass


func metrics() -> Dictionary:
	return {"height": 2.0, "radius": 0.5, "eye": 1.7, "shoulder": 1.5}


func clip_names() -> Dictionary:
	return {}


func play(_logical: StringName, _speed: float = 1.0) -> float:
	return 0.0


func set_move(_speed: float, _running: bool) -> void:
	pass


func set_aim(_pitch: float) -> void:
	pass


func set_weapon(_id: StringName) -> void:
	pass


func set_flash(_a: float) -> void:
	pass


func set_telegraph(_a: float) -> void:
	pass


func muzzle() -> Node3D:
	return null


func anchor(_name: StringName) -> Node3D:
	return null


func apply_level(_l: String) -> void:
	pass
