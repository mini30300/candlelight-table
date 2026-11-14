extends Node3D
## A deck-only pack figure (PACK_SPEC §10): the deck methods but not the arena contract, so the arena falls back to the
## pack's player figure (or the egg) when it is selected.

func setup(_opts: Dictionary) -> void:
	pass


func set_weapon(_id: StringName) -> void:
	pass


func play(_logical: StringName, _speed: float = 1.0) -> float:
	return 0.0


func set_move(_speed: float, _running: bool) -> void:
	pass


func apply_level(_l: String) -> void:
	pass
