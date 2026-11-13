extends Node3D
## A broken deck figure for test_figure_pack and test_hall (PACK_SPEC §1 step 5): it has only part of the figure
## contract, so ArenaActors frees it and the deck keeps its egg.


func setup(_opts: Dictionary) -> void:
	pass


func play(_logical: StringName, _speed: float = 1.0) -> float:
	return 0.0


func set_move(_speed: float, _running: bool) -> void:
	pass
