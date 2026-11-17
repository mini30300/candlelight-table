extends "res://tests/fixtures/figure_pack/prim_figure.gd"
## A figure with H10 apply_scheme only (no H11): pack palettes reach it as (primary, secondary) (PACK_SPEC §10.1).

var scheme: Array = []


func apply_scheme(primary: Color, secondary: Color) -> void:
	_count("apply_scheme")
	scheme = [primary, secondary]
	team_colour = primary
	_update_material()
