extends "res://tests/fixtures/figure_pack/prim_figure.gd"
## The primitive test figure plus H10 apply_scheme and H11 apply_palette (PACK_SPEC §10.1, tests only): the capsule takes
## the primary colour; `scheme` keeps the last (primary, secondary) pair and `palette` the last palette dictionary.

var scheme: Array = []
var palette: Dictionary = {}


func apply_scheme(primary: Color, secondary: Color) -> void:
	_count("apply_scheme")
	scheme = [primary, secondary]
	team_colour = primary
	_update_material()


func apply_palette(p: Dictionary) -> void:
	_count("apply_palette")
	palette = p.duplicate(true)
	scheme = [p.get("primary", team_colour), p.get("secondary", p.get("primary", team_colour))]
	team_colour = scheme[0]
	_update_material()
