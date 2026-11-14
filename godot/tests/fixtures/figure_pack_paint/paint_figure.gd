extends "res://tests/fixtures/figure_pack/heavy_figure.gd"
## The dressed pack figure of round D (ARENA_SPEC §9.6): the H6/H8/H9 heavy fixture plus H10 apply_scheme, which keeps
## the two colours and paints the capsule with the primary one (so a render shows the scheme). Primitives only.

var scheme_colors: Array = []


func apply_scheme(primary: Color, secondary: Color) -> void:
	_count("apply_scheme")
	scheme_colors = [primary, secondary]
	team_colour = primary
	_update_material()
