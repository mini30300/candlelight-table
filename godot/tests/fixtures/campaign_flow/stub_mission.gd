extends Control
## Stand-in MissionScreen for CampaignFlow tests (track A): records start(spec); finish(result) emits `finished` once.

signal finished(result: Dictionary)

var spec: Dictionary = {}
var started := 0
var _done := false


func start(s: Dictionary) -> void:
	spec = s
	started += 1


func finish(result: Dictionary) -> void:
	if _done:
		return
	_done = true
	finished.emit(result)


func handle_back() -> bool:
	return true
