extends SceneTree
## Renders scenes/probe.tscn and saves tests/out/probe.png (Thai) and probe_en.png (after pressing the
## language button). Needs a real display and a GPU or Mesa:
##   timeout 120 xvfb-run -a -s "-screen 0 1280x720x24" <godot> --path godot --rendering-driver opengl3 \
##       --resolution 1280x720 --audio-driver Dummy -s tests/render_probe.gd
## Run `<godot> --headless --path godot --import` first so the kits and fonts are imported.

const OUT_DIR := "res://tests/out"
const FRAMES := 3   # frames to wait before each capture

var _frame := 0
var _probe: Node
var _english_done := false


func _initialize() -> void:
	var scene: PackedScene = load("res://scenes/probe.tscn")
	if scene == null:
		print("FAIL  cannot load res://scenes/probe.tscn")
		quit(1)
		return
	_probe = scene.instantiate()
	root.add_child(_probe)
	print("adapter: " + RenderingServer.get_video_adapter_name() + " (" + RenderingServer.get_video_adapter_api_version() + ")")


func _process(_delta: float) -> bool:
	_frame += 1
	if _frame <= FRAMES:
		return false
	if not _english_done:
		print("figures: " + str(_probe.get("figure_count")) + (" from kits" if _probe.get("from_kits") else " stand-ins"))
		if not _save("probe.png"):
			return true
		# press ENGLISH like a player would, then capture again
		var button: Button = _probe.get_node("HUD").get_node("%LangButton")
		button.pressed.emit()
		_english_done = true
		_frame = 0
		return false
	var saved := _save("probe_en.png")
	quit(0 if saved else 1)
	return true


func _save(name: String) -> bool:
	var img := root.get_viewport().get_texture().get_image()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	var path := OUT_DIR + "/" + name
	var err := img.save_png(path)
	if err != OK:
		print("FAIL  could not save " + path + ": " + error_string(err))
		quit(1)
		return false
	print("ok    saved " + ProjectSettings.globalize_path(path) + " " + str(img.get_size()))
	return true
