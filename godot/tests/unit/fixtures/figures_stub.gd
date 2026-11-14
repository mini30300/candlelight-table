extends RefCounted
## A stand-in for the Figures API (app/figures.gd, PACK_SPEC §9.6) used by the dressing-room tests while that file is
## absent, or when DRESS_STUB=1: three neutral test figures (the egg, a paintable primitive with H10, a primitive that
## keeps its own colours), four schemes, three slots, and the selection kept in a ConfigFile at `path` so a new stub
## reading the same file is a "reload". Same method names and shapes as the real API.

const SCHEME_FIG := "res://tests/unit/fixtures/scheme_figure.gd"
const PLAIN_FIG := "res://tests/fixtures/figure_pack/prim_figure.gd"
const LIST: Array = [
	{"id": "egg", "name": {"th": "ไข่", "en": "Egg"}, "kind": "egg", "schemes": false},
	{"id": "paint_dummy", "name": {"th": "หุ่นทดสอบทาสีได้", "en": "Paintable test dummy"}, "kind": "pack", "schemes": true},
	{"id": "plain_dummy", "name": {"th": "หุ่นทดสอบสีเดิม", "en": "Plain test dummy"}, "kind": "kit", "kit": "test",
		"schemes": false},
]

var path := "user://test_figures_stub.cfg"
var selects := 0


func list() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for e: Dictionary in LIST:
		out.append(e.duplicate(true))
	return out


func entry(id: StringName) -> Dictionary:
	for e: Dictionary in LIST:
		if str(e["id"]) == str(id):
			return e.duplicate(true)
	return {}


func make(id: StringName, level: StringName) -> Node3D:
	var e := entry(id)
	if e.is_empty() or str(e["kind"]) == "egg":
		return null
	var fig := (load(SCHEME_FIG if bool(e["schemes"]) else PLAIN_FIG) as GDScript).new() as Node3D
	fig.set("level", str(level))
	return fig


func schemes() -> Array[Dictionary]:
	return [
		{"id": "blue", "name": {"th": "น้ำเงิน", "en": "Blue"}, "primary": Color(0.16, 0.3, 0.75), "secondary": Color(0.85, 0.85, 0.9)},
		{"id": "pink", "name": {"th": "ชมพู", "en": "Pink"}, "primary": Color(0.92, 0.45, 0.7), "secondary": Color(0.3, 0.1, 0.2)},
		{"id": "red", "name": {"th": "แดง", "en": "Red"}, "primary": Color(0.75, 0.12, 0.1), "secondary": Color(0.1, 0.1, 0.1)},
		{"id": "white", "name": {"th": "ขาว", "en": "White"}, "primary": Color(0.92, 0.92, 0.9), "secondary": Color(0.2, 0.3, 0.6)},
	]


func selected() -> Dictionary:
	var c := _cfg()
	return {"figure": StringName(str(c.get_value("dress", "figure", "egg"))),
		"scheme": StringName(str(c.get_value("dress", "scheme", "blue")))}


func select(figure_id: StringName, scheme_id: StringName) -> void:
	selects += 1
	var c := _cfg()
	c.set_value("dress", "figure", str(figure_id))
	c.set_value("dress", "scheme", str(scheme_id))
	c.save(path)


func slots() -> Array:
	var c := _cfg()
	var out := []
	for i in 3:
		var f := str(c.get_value("dress", "slot%d_figure" % i, ""))
		out.append({} if f == "" else {"figure": StringName(f), "scheme": StringName(str(c.get_value("dress", "slot%d_scheme" % i, "")))})
	return out


func save_slot(i: int, figure_id: StringName, scheme_id: StringName) -> void:
	var c := _cfg()
	c.set_value("dress", "slot%d_figure" % i, str(figure_id))
	c.set_value("dress", "slot%d_scheme" % i, str(scheme_id))
	c.save(path)


func _cfg() -> ConfigFile:
	var c := ConfigFile.new()
	c.load(path)
	return c
