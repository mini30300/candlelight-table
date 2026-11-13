extends SceneTree
## Battle animations and weapon effects on the real table (scenes/battle/battle_fx.gd), under xvfb:
## a 4-army bot fight (budget 2000 each, the large table) fed step by step into BattleFx, for eggs and (when the kits
## exist) the kit figures, on every graphics level: the ARCHITECTURE §6 draw-call and triangle budgets hold on every
## frame while the effects play (the same numbers as test_budgets.gd), clips play on skinned figures, effects spawn and
## free themselves, fallen figures stay on hi and never on min, nothing processes once the effects are over.
## PNGs: battle_fx_<style>_<level>.png (camera on the shooter, mid-attack).
##   xvfb-run -a -s "-screen 0 1280x720x24" <godot> --path godot --rendering-driver opengl3 --resolution 1280x720 \
##       --audio-driver Dummy -s tests/render/test_battle_fx.gd

const SCENE := "res://scenes/battle_table.tscn"
const DEFAULT_OUT_DIR := "res://tests/out"
const LEVELS: PackedStringArray = ["hi", "mid", "lo", "min"]
## [draw calls, primitives] per level (ARCHITECTURE §6, = test_budgets.gd)
const BUDGET := {"hi": [600, 1500000], "mid": [350, 800000], "lo": [200, 400000], "min": [120, 250000]}
const ATTACKS := 4          # การโจมตีที่ดูต่อระดับ
const FRAME_CAP := 240

var _out_dir := DEFAULT_OUT_DIR
var _started := false
var _done := false
var _passed := 0
var _failed := 0


func _initialize() -> void:
	var env := OS.get_environment("TEST_OUT")
	if env != "" and env.is_absolute_path():
		_out_dir = env
	print("adapter: " + RenderingServer.get_video_adapter_name() + " (" + RenderingServer.get_video_adapter_api_version() + ")")


func _process(_delta: float) -> bool:
	if not _started:
		_started = true
		_run()
	return _done


func _run() -> void:
	var styles := ["egg"]
	if KitLibrary.list_kits().size() > 0 and ResourceLoader.exists("res://assets/anim/humanoid.res"):
		styles.append("kit")
	else:
		print("note  no kits or clips on disk: the kit phase is skipped")
	for style in styles:
		await _phase(style)
	print("%s  %d passed, %d failed" % ["PASS " if _failed == 0 else "FAIL ", _passed, _failed])
	_done = true
	quit(0 if _failed == 0 else 1)


func _phase(style: String) -> void:
	var c := SeatPlan.defaults(4242)
	c["teams"] = 4
	c["per_team"] = 1
	c["size"] = "l"
	c["goal"] = "kill"
	c["budget"] = 2000
	var facs := GameData.factions()
	c["seats"] = [{"fac": "kn", "human": false}, {"fac": "or", "human": false}, {"fac": facs[2], "human": false},
		{"fac": facs[3], "human": false}]
	var plan := SeatPlan.build(c)
	var runner := MatchRunner.new(plan)
	runner.start()
	var table: Node3D = (load(SCENE) as PackedScene).instantiate()
	table.set("auto_build", false)
	table.set("figure_style", style)
	root.add_child(table)
	await process_frame
	table.call("build_battle", runner.st)
	table.call("set_measuring", true)
	var fx := BattleFx.new()
	fx.name = "BattleFx"
	table.add_child(fx)
	fx.allowed = true
	fx.enabled = true
	fx.begin(table, runner.st)
	print("%s: %d models" % [style, runner.st.units.size()])
	var shot_saved := false
	for level in LEVELS:
		table.call("apply_level", level)
		fx.set_level(level)
		var peak_dc := 0
		var peak_pr := 0
		var seen := 0
		var steps := 0
		var s0: Dictionary = fx.stats.duplicate()
		while seen < ATTACKS and steps < 3000 and not runner.is_over():
			var r := runner.step()
			steps += 1
			var evs: Array = r["events"]
			var atk := {}
			for e: Dictionary in evs:
				if Events.id_of(e) == Events.Id.ATTACK_STAGE and str(e.get("stage", "")) == "hit":
					atk = e
					break
			if evs.is_empty():
				continue
			table.call("sync_battle", runner.st)
			fx.feed(evs, runner.st)
			if atk.is_empty():
				continue
			seen += 1
			_aim(table, runner.st, str(atk["p"]))
			var frames := 0
			var busiest := 0
			while (fx.busy_left() > 0.0 or fx.active()) and frames < FRAME_CAP:
				await process_frame
				frames += 1
				peak_dc = maxi(peak_dc, RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME))
				peak_pr = maxi(peak_pr, RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME))
				var cn := fx.counts()
				var busy := (int(cn["shots"]) + int(cn["beams"])) * 10 + int(cn["puffs"]) + int(cn["sparks"])
				if busy > busiest and frames > 2:
					busiest = busy
					if seen == ATTACKS - 1 or not shot_saved:
						_save("battle_fx_%s_%s" % [style, level])
						shot_saved = true
		var d := {}
		for k in fx.stats:
			d[k] = int(fx.stats[k]) - int(s0.get(k, 0))
		print("%s %s: %d attacks, peak %d draw calls / %d primitives, %s, %s" % [style, level, seen, peak_dc, peak_pr, str(d), str(fx.counts())])
		_check(seen > 0, "%s %s: attacks were drawn (%d)" % [style, level, seen])
		_check(int(d["shots"]) > 0, "%s %s: shots / blows were drawn (%d)" % [style, level, int(d["shots"])])
		_check(peak_dc <= int(BUDGET[level][0]), "%s %s: draw calls within budget while the effects play (%d <= %d)" % [style, level, peak_dc, int(BUDGET[level][0])])
		_check(peak_pr <= int(BUDGET[level][1]), "%s %s: primitives within budget (%d <= %d)" % [style, level, peak_pr, int(BUDGET[level][1])])
		if style == "kit" and level in ["hi", "mid"]:
			_check(int(d["clips"]) > 0, "%s %s: clips play on the skinned figures (%d)" % [style, level, int(d["clips"])])
		if level == "min":
			_check(int(fx.counts()["fallen"]) == 0 and int(d["peak_sparks"]) == 0, "%s min: no fallen figures and no particles" % style)
		else:
			_check(int(fx.counts()["fallen"]) <= int(BattleFx.LV[level]["fallen"]), "%s %s: fallen figures within the cap (%d)" % [style, level, int(fx.counts()["fallen"])])
	# ไล่จนมีตัวตายบนระดับ hi: ร่างล้มค้างบนสนาม
	table.call("apply_level", "hi")
	fx.set_level("hi")
	var steps2 := 0
	while int(fx.counts()["fallen"]) == 0 and steps2 < 4000 and not runner.is_over():
		var r2 := runner.step()
		steps2 += 1
		if (r2["events"] as Array).is_empty():
			continue
		table.call("sync_battle", runner.st)
		fx.feed(r2["events"], runner.st)
		var f2 := 0
		while fx.active() and f2 < FRAME_CAP:
			await process_frame
			f2 += 1
	_check(int(fx.counts()["fallen"]) > 0, "%s hi: a killed model lies on the field (%d fallen)" % [style, int(fx.counts()["fallen"])])
	var f3 := 0
	while fx.active() and f3 < FRAME_CAP * 2:
		await process_frame
		f3 += 1
	var cn2 := fx.counts()
	_check(not bool(cn2["processing"]) and int(cn2["shots"]) == 0 and int(cn2["puffs"]) == 0 and int(cn2["actors"]) == 0,
		"%s: effects free themselves and processing stops (%s)" % [style, str(cn2)])
	if style == "kit":
		_rigid_after_rebuild(table, fx, runner.st)
	fx.clear()
	table.call("end_battle")
	table.queue_free()
	await process_frame
	await process_frame


## kit style: the table rebuilds its figures on every sync (twice in one frame here); a rigid (far, MultiMesh) model must
## still be found by name (Kit_<kit>), or it never recoils, lunges or flinches again
func _rigid_after_rebuild(table: Node3D, fx: BattleFx, st: BattleState) -> void:
	table.call("sync_battle", st)
	table.call("sync_battle", st)
	var pool: FigurePool = table.get("figures")
	var found := false
	var detail := "no rigid model on the table"
	for u in st.units:
		var fi := int(table.call("unit_fig", str(u.id)))
		if fi < 0 or fi >= pool.figures.size() or pool.figures[fi].skinned:
			continue
		var f: FigurePool.Figure = pool.figures[fi]
		var a := {"uid": u.id, "node": null, "mm": null, "mmi": null, "cur": ""}
		var ok := bool(fx.call("_resolve", a))
		var mmi: Variant = a.get("mmi")
		found = ok and mmi != null and str((mmi as Node).name) == "Kit_" + f.kit
		detail = "%s → %s %s" % [str(u.id), str(ok), str((mmi as Node).name) if mmi != null else "null"]
		break
	_check(found, "kit: a rigid model is still found after two table rebuilds in one frame", detail)


## กล้องเล็งระหว่างหมู่ผู้ยิงกับเป้า
func _aim(table: Node3D, st: BattleState, key: String) -> void:
	var p := key.split(">")
	var a := Vector3.INF
	var b := Vector3.INF
	for u in st.units:
		if u.sq == p[0] and a == Vector3.INF:
			a = Vector3(u.x / 1000.0, 0.5, u.z / 1000.0)
		if p.size() > 1 and u.sq == p[1] and b == Vector3.INF:
			b = Vector3(u.x / 1000.0, 0.5, u.z / 1000.0)
	if a == Vector3.INF:
		return
	if b == Vector3.INF:
		b = a
	var rig: Node = table.get("camera_rig")
	rig.set("target", (a + b) * 0.5)
	rig.set("distance", clampf(a.distance_to(b) * 0.9, 6.0, 24.0))
	rig.set("pitch", -0.85)
	rig.call("_apply")


func _save(name: String) -> void:
	var img := root.get_viewport().get_texture().get_image()
	if img == null:
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_out_dir))
	img.save_png(ProjectSettings.globalize_path(_out_dir.path_join(name + ".png")))


func _check(cond: bool, msg: String, detail: String = "") -> void:
	if cond:
		_passed += 1
		print("ok    " + msg)
	else:
		_failed += 1
		print("FAIL  " + msg + ("" if detail == "" else " " + detail.left(1500)))
