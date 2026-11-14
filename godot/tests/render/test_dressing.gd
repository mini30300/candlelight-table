extends "res://tests/flow/dressing_steps.gd"
## Dressing room under xvfb (PACK_SPEC §9.6): the walk of tests/flow/dressing_steps.gd plus Thai and English screenshots
## on desktop (1280×720) and phone (1600×720, touch), the room after ใช้ตัวนี้, draw calls of the dressing screen on min and
## hi within the deck's limits. Run:
##   xvfb-run -a -s "-screen 0 1280x720x24" <godot> --path godot --rendering-driver opengl3 --resolution 1280x720 \
##     --audio-driver Dummy -s tests/render/test_dressing.gd
## Exit code 1 on any failure; the last line is PASS or FAIL. PNGs in $TEST_OUT (default godot/tests/out).


func _initialize() -> void:
	RENDER = true
	super()
