extends "res://tests/testing.gd"
## KitLibrary (table/figures/kit_library.gd): picking the probe's figures and spacing them, with and without a kits folder.

const KitLibraryScript := preload("res://table/figures/kit_library.gd")


func test_names_from_files_handles_exported_builds() -> void:
	var files := PackedStringArray(["heavy.glb", "heavy.glb.import", "tank.glb.remap", "kits.json", ".gitignore", "a.txt"])
	assert_eq(Array(KitLibraryScript.names_from_files(files)), ["heavy", "tank"], "strips .import/.remap and keeps only .glb names, sorted, no duplicates")


func test_pick_prefers_the_wanted_kits_then_fills_up() -> void:
	var available := PackedStringArray(["archer", "boss", "dmg", "grot", "heavy", "yumi"])
	var picked := KitLibraryScript.pick(available, KitLibraryScript.PREFERRED, 12)
	assert_eq(Array(picked), ["heavy", "boss", "dmg", "archer", "grot", "yumi"], "preferred order first, then the rest by name")
	assert_eq(Array(KitLibraryScript.pick(available, KitLibraryScript.PREFERRED, 2)), ["heavy", "boss"], "max_count caps the row")
	assert_eq(KitLibraryScript.pick(PackedStringArray(), KitLibraryScript.PREFERRED, 12).size(), 0, "no kits: nothing picked (the scene shows stand-ins)")


func test_row_positions_are_centred_and_spaced_by_base_radius() -> void:
	var xs := KitLibraryScript.row_positions(PackedFloat32Array([1.0, 1.0, 2.0]), 0.5)
	assert_true(absf(xs[0] + xs[2]) < 0.001 and absf(xs[1] - xs[0] - 2.5) < 0.001 and absf(xs[2] - xs[1] - 3.5) < 0.001, "three figures: gaps of r1+gap+r2, row centred on 0", xs)
	assert_eq(KitLibraryScript.row_positions(PackedFloat32Array()).size(), 0, "empty row")


func test_manifest_and_folder_if_present() -> void:
	var kits := KitLibraryScript.list_kits()
	var manifest: Dictionary = KitLibraryScript.load_manifest()
	if kits.is_empty():
		print("ok    (kits folder empty here: run node godot/tools/export_kits.js to test the real set)")
		assert_eq(manifest.size(), 0, "no kits: no manifest either")
		return
	assert_true(kits.size() >= 12, "kits folder has at least 12 kits: " + str(kits.size()))
	assert_true(manifest.size() >= kits.size(), "kits.json lists every kit on disk (%d listed, %d files)" % [manifest.size(), kits.size()])
	var picked := KitLibraryScript.pick(kits, KitLibraryScript.PREFERRED, 12)
	assert_eq(Array(picked), Array(KitLibraryScript.PREFERRED), "the probe line-up is the full preferred set")
	assert_true(KitLibraryScript.base_radius(manifest, "dmg") > KitLibraryScript.base_radius(manifest, "archer"), "the titan has a wider base than the archer")
	assert_eq(KitLibraryScript.base_radius(manifest, "no-such-kit"), KitLibraryScript.DEFAULT_BASE_R, "unknown kit uses the default base radius")
