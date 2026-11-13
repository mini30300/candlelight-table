extends "res://tests/fixtures/pack_rooms/test_room/room.gd"
## Tests only: the neutral test room whose script puts a crate on the spawn. room.json passes PackRooms.validate (it
## checks only the station footprints), PackRoomWorld.open refuses the room, so the deck's fallback (lobby, then the
## ROOM_FAILED note) runs.


func blockers() -> Array:
	_note("blockers")
	return [{"kind": "cyl", "c": Vector2(0.0, 6.0), "r": 0.6, "y0": 0.0, "y1": 1.2, "tag": "crate"}]
