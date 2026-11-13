extends "res://tests/testing.gd"
## Sound (godot/audio): the baked manifest and files (tools/bake_sfx.js; CI's kits job makes them), the per-kind gap and
## the voice cap of Sfx (like the old page's SND.at), the weapon → sound map, the music's heat and level steps, the bus
## layout, the volume settings' round trip through App, and the tree-level button click. Runs under the Dummy driver:
## Sfx keeps its bookkeeping without players. Fresh instances are used so the live autoloads keep their state.

const SfxScript := preload("res://audio/sfx.gd")
const MusicScript := preload("res://audio/music.gd")
const AppScript := preload("res://app/app.gd")
const MANIFEST := "res://assets/sfx/sfx.json"
## every effect of the old page's DEF table (battle-table.html, var SND → var DEF)
const PAGE_KINDS: PackedStringArray = ["shot", "heavy", "laser", "zap", "flame", "bow", "bolt", "catapult", "throw", "swing",
	"hit", "clang", "boom", "die", "dice", "charge", "saw", "vshield", "wind", "heal", "turn", "end", "bolter", "hbolter",
	"gatling", "sniper", "cannon", "rocket", "plasma", "melta", "beam", "warp", "chain", "power", "hammer", "claw", "bite",
	"stomp", "quake", "ricochet", "debris", "ui"]
const TEST_DIR := "user://tests"


func _root() -> Window:
	return (Engine.get_main_loop() as SceneTree).root


func _fresh_sfx() -> Node:
	var s: Node = SfxScript.new()
	_root().add_child(s)
	s.set("now_override", 1000)
	s.call("reset")
	return s


func test_manifest_lists_every_page_sound() -> void:
	assert_true(FileAccess.file_exists(MANIFEST), "the sound bake is present (" + MANIFEST + "; bash godot/tools/kits.sh makes it)")
	var m: Variant = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST))
	assert_true(m is Dictionary, "sfx.json parses")
	if not m is Dictionary:
		return
	var kinds: Dictionary = (m as Dictionary)["kinds"]
	var missing: PackedStringArray = []
	for k in PAGE_KINDS:
		if not kinds.has(k):
			missing.append(k)
	assert_eq(missing, PackedStringArray(), "every DEF sound of the old page is baked")
	assert_eq(int((m as Dictionary)["max_voices"]), 22, "the old page's voice cap")
	assert_eq([int(kinds["shot"]["gap"]), float(kinds["shot"]["v"]), int(kinds["dice"]["gap"]), int(kinds["end"]["gap"])], [26, 0.45, 160, 3000],
		"gap and volume come from the page (shot 26 ms / 0.45, dice 160 ms, end 3000 ms)")
	var bad: PackedStringArray = []
	for k: String in kinds:
		for f: Variant in kinds[k]["files"]:
			var st := load("res://assets/sfx/" + str(f)) as AudioStreamWAV
			if st == null or st.format != AudioStreamWAV.FORMAT_QOA or st.get_length() < 0.01:
				bad.append(str(f))
	assert_eq(bad, PackedStringArray(), "every take imports as a QOA-compressed AudioStreamWAV")
	var music: Dictionary = (m as Dictionary)["music"]
	assert_eq(music.keys().size(), 5, "five music loops: menu, deck, battle_1..3")
	var loops_ok := true
	for n: String in music:
		var st := load("res://assets/sfx/" + str(music[n]["file"])) as AudioStreamWAV
		loops_ok = loops_ok and st != null and st.loop_mode == AudioStreamWAV.LOOP_FORWARD and st.format == AudioStreamWAV.FORMAT_QOA \
			and absf(st.get_length() - float(music[n]["seconds"])) < 0.05
	assert_true(loops_ok, "every music file imports looping (smpl chunk) and QOA, with the manifest's length")
	var b1: Dictionary = music["battle_1"]
	assert_true(b1["bar"] == music["battle_3"]["bar"] and b1["samples"] == music["battle_3"]["samples"],
		"the three battle levels share tempo and length (they play in sync and crossfade)")


func test_weapon_sounds() -> void:
	var s := _fresh_sfx()
	assert_eq([s.call("weapon_kind", "bolter"), s.call("weapon_kind", "chain"), s.call("weapon_kind", "stormgun"), s.call("weapon_kind", "lascan")],
		[&"bolter", &"chain", &"bolter", &"beam"], "FXS kinds and FX_GUN guns map to the page's sounds")
	assert_eq([s.call("weapon_kind", "boom"), s.call("weapon_kind", "glow"), s.call("weapon_kind", "no-such")], [&"boom", &"heal", &""],
		"FX_SND effects have their own sound; an unknown kind is silent")
	var fxs: Dictionary = s.get("fxs")
	var unknown: PackedStringArray = []
	for k: String in fxs:
		if not bool(s.call("has", StringName(str(fxs[k]["snd"])))):
			unknown.append(k)
	assert_eq(unknown, PackedStringArray(), "every FXS kind's sound is baked")
	s.free()


func test_gap_rate_limit() -> void:
	var s := _fresh_sfx()
	assert_true(bool(s.get("quiet")), "the Dummy driver makes Sfx quiet (no players)")
	assert_true(bool(s.call("play", &"shot")), "a first shot plays")
	s.set("now_override", 1010)
	assert_false(bool(s.call("play", &"shot")), "a second shot 10 ms later is dropped (gap 26 ms)")
	assert_true(bool(s.call("play", &"bolter")), "another kind is not held back by that gap")
	s.set("now_override", 1027)
	assert_true(bool(s.call("play", &"shot")), "27 ms after the first shot it plays again")
	assert_false(bool(s.call("play", &"no-such-sound")), "an unknown kind is silent")
	var st: Dictionary = s.get("stats")
	assert_eq([int(st["n"]), int(st["drop"]), int(st["ask"]["shot"])], [3, 1, 3], "stats count played, dropped and asked")
	assert_eq(_root().get_child_count() > 0 and s.get_child_count() == 0, true, "quiet: no player nodes were made")
	s.free()


func test_voice_cap() -> void:
	var s := _fresh_sfx()
	var played := 0
	for k in PAGE_KINDS:
		if bool(s.call("play", StringName(k), Vector3(1, 0, 2))):
			played += 1
	assert_eq(played, SfxScript.MAX_VOICES, "at most 22 sounds at once (42 kinds asked in the same millisecond)")
	assert_eq(int(s.call("live_voices")), SfxScript.MAX_VOICES, "22 voices are live")
	s.set("now_override", 1000 + 10000)
	assert_eq(int(s.call("live_voices")), 0, "ten seconds later every voice has ended")
	assert_true(bool(s.call("play", &"boom")), "and a new sound plays")
	s.free()


func test_mute_and_volume_zero_silence() -> void:
	var s := _fresh_sfx()
	var snd: bool = App.snd
	var vol: float = App.sfx_vol
	App.snd = false
	assert_false(bool(s.call("play", &"hit")), "muted: nothing plays")
	App.snd = true
	App.sfx_vol = 0.0
	assert_false(bool(s.call("play", &"hit")), "effects volume 0: nothing plays")
	App.sfx_vol = 0.5
	assert_true(bool(s.call("play", &"hit")), "effects volume 0.5: it plays")
	App.snd = snd
	App.sfx_vol = vol
	s.free()


func test_loops_follow_their_owner() -> void:
	var s := _fresh_sfx()
	var owner := Node.new()
	_root().add_child(owner)
	var id := int(s.call("loop", &"saw", owner))
	assert_true(id > 0 and int(s.call("loop_count")) == 1, "a loop starts and returns an id")
	owner.free()
	assert_eq(int(s.call("loop_count")), 0, "the loop ends when its owner leaves the tree")
	var o2 := Node.new()
	_root().add_child(o2)
	var id2 := int(s.call("loop", &"saw", o2))
	s.call("stop_loop", id2)
	assert_eq(int(s.call("loop_count")), 0, "stop_loop ends it")
	assert_eq(o2.tree_exiting.get_connections().size(), 0, "stop_loop disconnects from the owner (no pile-up per sword draw)")
	o2.free()
	s.free()


func test_bus_layout_and_volumes() -> void:
	for b in ["Effects", "Music", "UI"]:
		assert_true(AudioServer.get_bus_index(b) > 0, "bus " + b + " exists")
	assert_true(AudioServer.get_bus_effect_count(0) > 0 and AudioServer.get_bus_effect(0, 0) is AudioEffectCompressor,
		"Master has the old page's compressor")
	var keep := [App.sfx_vol, App.mus_vol, App.snd]
	App.sfx_vol = 0.5
	App.mus_vol = 0.25
	App.snd = false
	Sfx.apply_settings()
	assert_within(AudioServer.get_bus_volume_db(AudioServer.get_bus_index("Effects")), linear_to_db(0.5), 0.01, "effects volume → Effects bus")
	assert_within(AudioServer.get_bus_volume_db(AudioServer.get_bus_index("Music")), linear_to_db(0.25), 0.01, "music volume → Music bus")
	assert_true(AudioServer.is_bus_mute(0), "mute → Master muted")
	App.sfx_vol = keep[0]
	App.mus_vol = keep[1]
	App.snd = keep[2]
	Sfx.apply_settings()
	assert_false(AudioServer.is_bus_mute(0), "unmuted again")


func test_volume_settings_round_trip() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(TEST_DIR))
	var path := TEST_DIR + "/settings_audio.cfg"
	var a: Node = AppScript.new()
	a.reset_settings()
	assert_eq([a.sfx_vol, a.mus_vol, a.snd], [AppScript.DEFAULT_SFX_VOL, AppScript.DEFAULT_MUS_VOL, true], "volume defaults")
	a.set_sfx_vol(1.7)
	a.set_mus_vol(0.35)
	a.snd = false
	assert_eq(a.sfx_vol, 1.0, "a volume above 1 is clamped")
	assert_true(a.save_settings(path), "save")
	var b: Node = AppScript.new()
	assert_true(b.load_settings(path), "load")
	assert_eq([b.sfx_vol, b.mus_vol, b.snd], [1.0, 0.35, false], "effects volume, music volume and mute survive the round trip")
	var cfg := ConfigFile.new()
	cfg.set_value("app", "sfx_vol", "loud")
	cfg.set_value("app", "mus_vol", -3)
	cfg.save(path)
	assert_true(b.load_settings(path), "a file with bad volumes loads")
	assert_eq([b.sfx_vol, b.mus_vol], [AppScript.DEFAULT_SFX_VOL, 0.0], "a non-number falls back to the default, a negative one clamps to 0")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	a.free()
	b.free()


func test_music_heat_and_levels() -> void:
	var m: Node = MusicScript.new()
	_root().add_child(m)
	m.set("now_override", 100.0)
	assert_eq([MusicScript.level_for(0.0), MusicScript.level_for(8.5), MusicScript.level_for(23.0)], [1, 2, 3], "the page's thresholds (8, 22)")
	m.call("heat", &"die")
	m.call("heat", &"die")
	assert_within(float(m.call("heat_value")), 3.0, 0.001, "the same kind counts once per 0.25 s (die = 3)")
	m.set("now_override", 100.3)
	m.call("heat", &"die")
	m.call("heat", &"boom")
	m.call("heat", &"charge")
	m.call("heat", &"ui")
	assert_within(float(m.call("heat_value")), 3.0 * exp(-0.3 / 6.0) + 3.0 + 2.5 + 4.0, 0.01, "die + boom + charge add up; ui adds nothing")
	m.set("now_override", 130.0)
	assert_true(float(m.call("heat_value")) < 1.0, "the heat fades within seconds")
	m.set("now_override", 200.0)
	for i in 12:
		m.set("now_override", 200.0 + i * 0.3)
		m.call("heat", &"die")
	assert_eq(MusicScript.level_for(float(m.call("heat_value"))), 3, "a bloody fight reaches level 3")
	assert_eq([m.call("next_level", 1, 1), m.call("next_level", 2, 1)], [1, 3], "a rise waits for an even bar")
	m.set("now_override", 260.0)
	assert_eq([m.call("next_level", 6, 3), m.call("next_level", 8, 3)], [3, 2], "a fall waits for every fourth bar and goes one step")
	m.call("set_intensity", 1.0)
	assert_eq(int(m.call("next_level", 8, 2)), 3, "set_intensity(1) is a floor of level 3 (the last round)")
	m.call("set_mood", &"battle")
	assert_eq([m.get("mood"), m.get("level")], [&"battle", 3], "battle mood starts at the floor level")
	m.call("set_mood", &"deck")
	assert_eq([m.get("floor_level"), m.get("level")], [1, 1], "leaving battle clears the last round's floor")
	m.call("set_mood", &"battle")
	assert_eq(m.get("level"), 1, "the next battle starts at level 1, not the last battle's top level")
	m.call("set_intensity", 1.0)
	m.call("reset_battle")
	assert_eq(m.get("floor_level"), 1, "reset_battle (a new battle) clears the floor")
	m.call("set_mood", &"nonsense")
	assert_eq(m.get("mood"), &"", "an unknown mood means silence")
	m.free()


func test_buttons_click_through_one_tree_hook() -> void:
	var st: Dictionary = Sfx.stats
	var before := int((st["ask"] as Dictionary).get("ui", 0))
	var b := Button.new()
	_root().add_child(b)
	b.pressed.emit()
	assert_eq(int((Sfx.stats["ask"] as Dictionary).get("ui", 0)), before + 1, "a new button anywhere in the tree clicks (ui) when pressed")
	b.free()
