extends "res://tests/testing.gd"
## MissionLayout (CAMPAIGN_SPEC §5.4, §7 track C): a pure function of the spec. Same spec -> same layout (deep compare);
## 50 seeds x 6 biomes x 4 types (with the other three types as secondaries on every 4th seed): every key point and enemy
## spawn is inside the 44 x 44 m bounds, outside every blocker and reachable from the player spawn by the flood fill; the
## world's real ArenaPath (cell 1 m, radius 0.5) agrees on a sample; the hostages/pylons lists follow the spec; a
## different seed gives a different layout; blockers use the HallLayout.blockers() format with a layer.

const Specs := preload("res://tests/fixtures/campaign_missions/specs.gd")
const BIOMES: PackedStringArray = ["ruin", "forest", "desert", "ice", "volcanic", "toxic"]
const TYPES: PackedStringArray = ["purge", "defend", "rescue", "destroy_camp"]


func test_pure() -> void:
	var s := Specs.make("rescue", {"seed": 777, "biome": "forest", "secondary": ["destroy_camp", "defend"]})
	var a := MissionLayout.build(s)
	var b := MissionLayout.build(s.duplicate(true))
	assert_eq(var_to_str(a), var_to_str(b), "the same spec builds the same layout")
	var c := MissionLayout.build(Specs.make("rescue", {"seed": 778, "biome": "forest", "secondary": ["destroy_camp", "defend"]}))
	assert_ne(var_to_str(a["blockers"]), var_to_str(c["blockers"]), "another seed builds other blockers")
	assert_eq((a["points"]["hostages"] as Array).size(), 3, "rescue primary: three hostages")
	assert_eq((a["points"]["pylons"] as Array).size(), 1, "a destroy_camp secondary: one extra pylon")
	var d := MissionLayout.build(Specs.make("destroy_camp", {"seed": 5, "secondary": ["rescue"]}))
	assert_eq((d["points"]["pylons"] as Array).size(), 3, "destroy_camp primary: three pylons")
	assert_eq((d["points"]["hostages"] as Array).size(), 1, "a rescue secondary: one caged hostage")
	var e := MissionLayout.build(Specs.make("purge", {"seed": 5}))
	assert_eq((e["points"]["hostages"] as Array).size() + (e["points"]["pylons"] as Array).size(), 0, "purge alone: no hostages, no pylons")
	var stake := 0
	for bl: Dictionary in d["blockers"]:
		if str(bl["tag"]).begins_with("stake_"):
			stake += 1
	assert_true(stake >= 6, "the dark cult camp has its palisade stakes (%d)" % stake)


func test_many_layouts() -> void:
	var bad := []
	var n := 0
	var tags_ok := true
	var bounds := MissionLayout.bounds()
	for biome in BIOMES:
		for ti in TYPES.size():
			for seed_i in 50:
				var sec: Array = []
				if seed_i % 4 == 0:
					for t2 in TYPES:
						if t2 != TYPES[ti]:
							sec.append(t2)
				var s := Specs.make(TYPES[ti], {"seed": 1000 + seed_i * 7919 + ti, "biome": biome, "secondary": sec})
				var l := MissionLayout.build(s)
				n += 1
				var blockers: Array = l["blockers"]
				for bl: Dictionary in blockers:
					if not (bl.has("kind") and bl.has("tag") and (str(bl.get("layer", "")) in ["shell", "prop"])):
						tags_ok = false
				var g := MissionLayout.grid(blockers)
				var seen := MissionLayout.flood(g, l["player_spawn"])
				for kp: Array in MissionLayout.key_points(l):
					var p: Vector3 = kp[1]
					var nm := "%s/%s/%d %s" % [biome, TYPES[ti], seed_i, kp[0]]
					if not bounds.grow(-0.5).has_point(Vector2(p.x, p.z)):
						bad.append(nm + " out of bounds")
					var inside := MissionLayout.inside_blocker(blockers, p, 0.35)
					if inside != "":
						bad.append(nm + " inside " + inside)
					if kp[0] != "player_spawn" and not MissionLayout.reached(g, seen, p):
						bad.append(nm + " unreachable")
				if str(l["type"]) == "defend":
					var bp: Vector3 = l["points"]["base"] + Vector3(0.0, 0.0, MissionLayout.BASE_CORE_R + 1.4)
					if not MissionLayout.reached(g, seen, bp):
						bad.append("%s/defend/%d base unreachable" % [biome, seed_i])
	assert_eq(n, 1200, "built 50 seeds x 6 biomes x 4 types")
	assert_true(tags_ok, "every blocker has kind, tag and layer shell|prop")
	assert_eq(bad.slice(0, 12), [], "every key point inside the bounds, outside the blockers and reachable (%d problems)" % bad.size())


## The world paths with ArenaPath(bounds, blockers, 0.5, 1.0): its A* finds a way to every key point too.
func test_arena_path_agrees() -> void:
	var bad := []
	for i in 12:
		var s := Specs.make(TYPES[i % 4], {"seed": 31 + i * 101, "biome": BIOMES[i % 6], "secondary": ["purge"] if i % 4 != 0 else []})
		var l := MissionLayout.build(s)
		var ap := ArenaPath.new(MissionLayout.bounds(), l["blockers"], 0.5, 1.0)
		var from: Vector3 = l["player_spawn"]
		for kp: Array in MissionLayout.key_points(l):
			var p: Vector3 = kp[1]
			if kp[0] == "player_spawn":
				continue
			var path := ap.find(Vector2(from.x, from.z), Vector2(p.x, p.z))
			if path.size() < 2 or path[path.size() - 1].distance_to(Vector2(p.x, p.z)) > 1.5:
				bad.append("%d %s" % [i, kp[0]])
	assert_eq(bad, [], "ArenaPath reaches every key point from the player spawn")


func test_cover_and_layers() -> void:
	var l := MissionLayout.build(Specs.make("purge", {"seed": 99, "biome": "ruin"}))
	var tall := 0
	var low := 0
	for bl: Dictionary in l["blockers"]:
		var top := float(bl["y1"]) if str(bl["kind"]) == "cyl" else (bl["c"] as Vector3).y + (bl["h"] as Vector3).y
		if str(bl["tag"]).begins_with("cliff"):
			continue
		if str(bl["layer"]) == "shell":
			tall += 1
			if top <= MissionLayout.TALL:
				assert_true(false, "a shell blocker is taller than %.1f m (%s)" % [MissionLayout.TALL, bl["tag"]])
		else:
			low += 1
	assert_true(tall > 0 and low > 0, "ruins have tall (camera-blocking) and low cover (%d / %d)" % [tall, low])
	assert_true((l["posts"]["cover"] as Array).size() > 0, "gunners get cover posts behind low cover")
	assert_eq((l["spawns"] as Array).size(), 9, "nine edge spawns")
	assert_eq((l["near_spawns"] as Array).size(), 4, "four ambush spawns near the player")
