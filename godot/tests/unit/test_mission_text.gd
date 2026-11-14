extends "res://tests/testing.gd"
## Mission texts (CAMPAIGN_SPEC §5.1, AGENTS rule 4): every Thai string of the mission screen and the mission HUD has an
## English entry without Thai letters; MissionHud.objective_lines renders every state in Thai and in English with the
## numbers filled in and no Thai left in English; the clock format.

const Specs := preload("res://tests/fixtures/campaign_missions/specs.gd")

var thai_re := RegEx.create_from_string("[฀-๿]")


func _thai_values(script: Script) -> PackedStringArray:
	var out := PackedStringArray()
	var stack: Array = script.get_script_constant_map().values()
	while not stack.is_empty():
		var v: Variant = stack.pop_back()
		if v is String and thai_re.search(v) != null:
			out.append(v)
		elif v is Dictionary:
			stack.append_array((v as Dictionary).values())
		elif v is Array:
			stack.append_array(v)
	return out


func test_every_string_translates() -> void:
	var missing := []
	var thai := []
	for s: Script in [load("res://ui/screens/mission_screen.gd"), load("res://ui/campaign/mission_hud.gd")]:
		for th in _thai_values(s):
			var en := I18n.lookup(th)
			if en == "":
				missing.append(th)
			elif thai_re.search(en) != null:
				thai.append(th)
	assert_eq(missing, [], "every mission string has an English entry")
	assert_eq(thai, [], "no English mission string keeps Thai letters")


func test_objective_lines() -> void:
	var specs := [Specs.make("purge", {"secondary": ["defend", "rescue", "destroy_camp"]}), Specs.make("defend", {"secondary": ["purge"]}),
		Specs.make("rescue"), Specs.make("destroy_camp", {"secondary": ["defend"]})]
	var was := I18n.english
	for en in [false, true]:
		I18n.english = en
		for s: Dictionary in specs:
			var o := MissionObjectives.new(s, 12)
			o.kill("rusher")
			if s["primary"]["type"] == "rescue":
				o.free_hostage(0)
			if s["primary"]["type"] == "destroy_camp":
				for i in 3:
					o.damage_pylon(i, 9999)
			var lines := MissionHud.objective_lines(o.state())
			var texts := lines.map(func(l: Dictionary) -> String: return str(l["text"]))
			var joined := " | ".join(PackedStringArray(texts))
			assert_true(lines.size() >= 3 and not joined.contains("{"), "%s %s: lines filled in: %s" % [s["primary"]["type"], "EN" if en else "TH", joined])
			if en:
				assert_true(thai_re.search(joined) == null, "%s EN: no Thai left" % s["primary"]["type"])
			if s["primary"]["type"] == "destroy_camp":
				assert_true(lines.any(func(l: Dictionary) -> bool: return str(l["text"]) == I18n.t(MissionHud.LINE_EXTRACT)), "destroy_camp: the extract line after the pylons")
	I18n.english = was
	assert_eq([MissionHud.clock(0.0), MissionHud.clock(59.2), MissionHud.clock(180.0)], ["0:00", "1:00", "3:00"], "clock m:ss (rounded up)")
