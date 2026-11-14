extends Control
## Stand-in DifficultyScreen for CampaignFlow tests (track A): records open(ctx); tests emit `chosen` by hand.

signal chosen(difficulty: StringName)

var ctx: Dictionary = {}
var opened := 0


func open(c: Dictionary) -> void:
	ctx = c
	opened += 1


func choose(id: StringName) -> void:
	chosen.emit(id)


func handle_back() -> bool:
	return false
