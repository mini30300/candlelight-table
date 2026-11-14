extends "res://tests/fixtures/figure_pack/prim_figure.gd"
## The primitive test figure plus H10 apply_scheme (PACK_SPEC §9.6, tests only): the body takes the primary colour,
## `scheme` keeps the last (primary, secondary) pair the dressing room or the room screen sent.

var scheme: Array = []


func apply_scheme(primary: Color, secondary: Color) -> void:
	_count("apply_scheme")
	scheme = [primary, secondary]
	team_colour = primary
	_update_material()
