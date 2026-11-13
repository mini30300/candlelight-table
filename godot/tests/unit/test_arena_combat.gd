extends "res://tests/testing.gd"
## ArenaData + ArenaCombat (ui/arena/, ARENA_SPEC §6.1, §6.2, §13.2): the arena's number table and its pure combat math.


func _has_thai(s: String) -> bool:
	for i in s.length():
		var c := s.unicode_at(i)
		if c >= 0x0E00 and c <= 0x0E7F:
			return true
	return false


func test_weapon_entries() -> void:
	var common := ["th", "kind", "slot", "damage", "knockback", "stagger"]
	var by_kind := {"hitscan": ["rate", "mag", "reload", "range"], "melee": ["active", "cooldown", "reach", "half_angle_deg"]}
	assert_eq(ArenaData.WEAPONS.keys().size(), 3, "three weapons: gun, sword, punch")
	for id in ["gun", "sword", "punch"]:
		var w: Dictionary = ArenaCombat.weapon(id)
		assert_false(w.is_empty(), "weapon %s exists" % id)
		var need: Array = common + by_kind.get(str(w.get("kind", "")), ["?"])
		var missing := []
		var bad := []
		for f in need:
			if not w.has(f):
				missing.append(f)
			elif f not in ["th", "kind", "stagger", "slot"] and float(w[f]) <= 0.0:
				bad.append(f)
		assert_eq(missing, [], "weapon %s has every field of its kind" % id)
		assert_eq(bad, [], "weapon %s numbers are positive" % id)
	assert_eq(ArenaCombat.weapon("nope"), {}, "an unknown weapon is {}")
	var slots := []
	for id in ArenaData.WEAPONS:
		slots.append(int(ArenaData.WEAPONS[id]["slot"]))
	slots.sort()
	assert_eq(slots, [0, 1, 2], "slots 0 punch, 1 gun, 2 sword are unique")


func test_tables_positive() -> void:
	for table in [ArenaData.PLAYER, ArenaData.BEAST, ArenaData.RANGE, ArenaData.NUMBERS]:
		var bad := []
		for k in table:
			if typeof(table[k]) in [TYPE_INT, TYPE_FLOAT] and float(table[k]) <= 0.0:
				bad.append(k)
		assert_eq(bad, [], "every number is positive in %s" % str(table.keys().slice(0, 3)))
	assert_eq(str(ArenaData.BEAST["kit"]), "warrior", "the public build's beast kit is warrior")
	assert_true(float(ArenaData.BEAST["run"]) > float(ArenaData.PLAYER["walk"]) and
		float(ArenaData.BEAST["run"]) < float(ArenaData.PLAYER["run"]), "the beast chases faster than walking, slower than running")
	assert_true(float(ArenaData.BEAST["strike_reach"]) > float(ArenaData.BEAST["attack_range"]),
		"the claw reaches past the distance that starts a wind-up")


func test_fire_timing() -> void:
	assert_within(ArenaCombat.fire_interval("gun"), 0.125, 0.000001, "fire_interval(gun) = 0.125")
	assert_within(ArenaCombat.fire_interval("punch"), 0.55, 0.000001, "fire_interval(punch) = its cooldown")
	assert_within(ArenaCombat.fire_interval("sword"), 0.8, 0.000001, "fire_interval(sword) = its cooldown")
	assert_true(ArenaCombat.can_fire(1.125, 1.0, "gun"), "the rifle fires again after 0.125 s")
	assert_false(ArenaCombat.can_fire(1.1, 1.0, "gun"), "not after 0.1 s")
	assert_true(ArenaCombat.can_fire(0.0, -INF, "sword"), "the first swing is always allowed")
	assert_false(ArenaCombat.can_fire(0.5, 0.0, "punch"), "a punch waits 0.55 s")
	assert_eq(ArenaCombat.after_shot(30), 29, "a shot spends one round")
	assert_eq(ArenaCombat.after_shot(0), 0, "never below 0")
	assert_true(ArenaCombat.needs_reload(0), "an empty magazine needs a reload")
	assert_false(ArenaCombat.needs_reload(1), "one round left does not")
	assert_eq(ArenaCombat.full_mag("gun"), 30, "the rifle's magazine is 30")
	assert_eq(ArenaCombat.full_mag("sword"), 0, "the sword has no magazine")


func test_apply() -> void:
	var r := ArenaCombat.apply(300, 12)
	assert_eq(r, {"hp": 288, "applied": 12, "killed": false}, "300 - 12")
	r = ArenaCombat.apply(12, 12)
	assert_eq(r, {"hp": 0, "applied": 12, "killed": true}, "exactly to 0 kills")
	r = ArenaCombat.apply(5, 45)
	assert_eq(r, {"hp": 0, "applied": 5, "killed": true}, "overkill clamps the applied amount to the hp left")
	r = ArenaCombat.apply(13, 12)
	assert_false(bool(r["killed"]), "1 hp left is alive")
	r = ArenaCombat.apply(0, 12)
	assert_eq(r, {"hp": 0, "applied": 0, "killed": false}, "an already dead target is not killed again")
	r = ArenaCombat.apply(50, -5)
	assert_eq(int(r["applied"]), 0, "negative damage applies nothing")


func test_in_cone() -> void:
	var o := Vector2.ZERO
	# yaw 0 looks +z
	assert_true(ArenaCombat.in_cone(o, 0.0, Vector2(0, 2), 0.3, 2.0, 50.0), "straight ahead inside reach")
	assert_true(ArenaCombat.in_cone(o, 0.0, Vector2(0, 2.25), 0.3, 2.0, 50.0), "the target's radius counts towards reach")
	assert_false(ArenaCombat.in_cone(o, 0.0, Vector2(0, 2.4), 0.3, 2.0, 50.0), "beyond reach + radius")
	assert_false(ArenaCombat.in_cone(o, 0.0, Vector2(0, -1), 0.3, 2.0, 50.0), "behind")
	var a40 := deg_to_rad(40.0)
	var a60 := deg_to_rad(60.0)
	assert_true(ArenaCombat.in_cone(o, 0.0, Vector2(sin(a40), cos(a40)) * 1.5, 0.3, 2.0, 50.0), "40° off inside a 50° half angle")
	assert_false(ArenaCombat.in_cone(o, 0.0, Vector2(sin(a60), cos(a60)) * 1.5, 0.3, 2.0, 50.0), "60° off outside a 50° half angle")
	assert_true(ArenaCombat.in_cone(o, PI / 2.0, Vector2(1.5, 0), 0.3, 2.0, 50.0), "yaw π/2 looks +x")
	assert_true(ArenaCombat.in_cone(o, 0.0, Vector2(0.1, -0.1), 0.3, 2.0, 50.0), "a target overlapping the origin always counts")
	assert_true(ArenaCombat.in_cone(Vector2(3, 3), PI, Vector2(3, 1.5), 0.6, 1.6, 50.0), "works away from the origin")
	assert_true(ArenaCombat.melee_hits("punch", o, 0.0, Vector2(0, 2.1), 0.6), "a punch reaches a beast whose edge is 1.5 m away")
	assert_false(ArenaCombat.melee_hits("punch", o, 0.0, Vector2(0, 2.3), 0.6), "not one whose edge is 1.7 m away")
	assert_true(ArenaCombat.melee_hits("sword", o, 0.0, Vector2(0, 2.8), 0.6), "the sword reaches further (2.3 m)")
	assert_true(ArenaCombat.melee_hits("sword", o, 0.0, Vector2(sin(deg_to_rad(70)), cos(deg_to_rad(70))) * 1.5, 0.6),
		"and wider (75°)")
	assert_false(ArenaCombat.melee_hits("punch", o, 0.0, Vector2(sin(deg_to_rad(70)), cos(deg_to_rad(70))) * 1.5, 0.6),
		"than a punch (50°)")
	assert_false(ArenaCombat.melee_hits("gun", o, 0.0, Vector2(0, 1), 0.6), "the rifle is not a melee weapon")


func test_reaction_knockback_decay() -> void:
	assert_eq(ArenaCombat.reaction(12, false), &"none", "a bullet (12, no stagger) never flinches")
	assert_eq(ArenaCombat.reaction(25, true), &"flinch", "a punch (25 + stagger) flinches")
	assert_eq(ArenaCombat.reaction(45, true), &"flinch_heavy", "a sword swing (45) staggers heavily")
	assert_eq(ArenaCombat.reaction(40, true), &"flinch_heavy", "heavy_at 40 is heavy")
	assert_eq(ArenaCombat.reaction(39, true), &"flinch", "39 is a plain flinch")
	assert_eq(ArenaCombat.reaction(100, false), &"none", "no stagger, no reaction, however much")
	var k := ArenaCombat.knockback(Vector3(3, 2, 4), 3.0)
	assert_within(k.y, 0.0, 0.000001, "knockback is horizontal")
	assert_within(k.length(), 3.0, 0.00001, "knockback has the asked strength")
	assert_within(k.normalized().dot(Vector3(0.6, 0, 0.8)), 1.0, 0.00001, "along the horizontal direction")
	assert_eq(ArenaCombat.knockback(Vector3(0, 1, 0), 3.0), Vector3.ZERO, "a vertical direction gives none")
	var v := Vector3(4, 0, 0)
	var f := float(ArenaData.BEAST["friction"])
	assert_within(ArenaCombat.decay(v, f, log(2.0) / f).x, 2.0, 0.00001, "decay halves at ln 2 / friction")
	assert_within(ArenaCombat.decay(v, f, 0.0).x, 4.0, 0.00001, "no time, no decay")
	# punch slide: 3.0 m/s with friction 8 integrates to 0.375 m (§13.3 step 8)
	var pos := 0.0
	var vel := Vector3(float(ArenaData.WEAPONS["punch"]["knockback"]), 0, 0)
	for i in 120:
		pos += vel.x / 60.0
		vel = ArenaCombat.decay(vel, f, 1.0 / 60.0)
	assert_within(pos, 0.375, 0.03, "a punch slides the beast about 0.375 m")


func test_number_style_and_yaw() -> void:
	assert_eq(ArenaCombat.number_style(12), &"normal", "12 is a normal number")
	assert_eq(ArenaCombat.number_style(24), &"normal", "24 is normal")
	assert_eq(ArenaCombat.number_style(25), &"heavy", "25 is heavy")
	assert_eq(ArenaCombat.number_style(45), &"heavy", "45 is heavy")
	var a := Vector3(1, 0, 2)
	for b in [Vector3(1, 0, 5), Vector3(4, 0, 2), Vector3(-2, 3, -1), Vector3(1.5, 0, 1.0)]:
		var want := atan2(b.x - a.x, b.z - a.z)
		assert_within(ArenaCombat.yaw_to(a, b), want, 0.000001, "yaw_to matches HallAvatar's atan2(x, z) for %s" % str(b))
	assert_within(ArenaCombat.yaw_to(Vector3.ZERO, Vector3(0, 0, 1)), 0.0, 0.000001, "+z is yaw 0")
	assert_within(ArenaCombat.yaw_to(Vector3.ZERO, Vector3(0, 0, -1)), PI, 0.000001, "-z is yaw π")


func test_labels_are_keys() -> void:
	var labels := [str(ArenaData.BEAST["th"])]
	for id in ["gun", "sword", "punch"]:
		labels.append(str(ArenaData.WEAPONS[id]["th"]))
	assert_eq(labels, ["สัตว์รัง", "ปืนไรเฟิล", "ดาบเลื่อย", "หมัด"], "the four Thai labels of §1")
	# 13 Nov: the dodge button's label (ArenaData.DODGE.th) joined them on purpose (owner asked for a dodge)
	labels.append(str(ArenaData.DODGE["th"]))
	assert_eq(labels[4], "หลบ", "the dodge label is หลบ")
	for th in labels:
		var en := I18n.lookup(th)
		assert_true(en != "" and not _has_thai(en), "label %s has an English entry without Thai" % th, en)
	var frag := I18n.load_json_dict("res://ui/i18n/arena_data.json")
	var keys := frag.keys()
	keys.sort()
	var want := labels.duplicate()
	want.sort()
	assert_eq(keys, want, "arena_data.json holds exactly the five labels")


func test_time_to_kill() -> void:
	var hp := int(ArenaData.BEAST["hp"])
	var counts := {}
	for id in ["gun", "punch", "sword"]:
		var h := hp
		var n := 0
		while h > 0 and n < 1000:
			h = int(ArenaCombat.apply(h, int(ArenaData.WEAPONS[id]["damage"]))["hp"])
			n += 1
		counts[id] = n
	assert_eq(counts["gun"], 25, "25 rifle hits kill the beast")
	assert_eq(counts["punch"], 12, "12 punches kill it")
	assert_eq(counts["sword"], 7, "7 saw sword swings kill it")
	assert_true(counts["gun"] <= ArenaCombat.full_mag("gun"), "one magazine is enough")
	assert_within(float(counts["gun"] - 1) * ArenaCombat.fire_interval("gun"), 3.0, 0.1, "about 3 s of steady fire")
	var claws := ceili(float(ArenaData.PLAYER["hp"]) / float(ArenaData.BEAST["strike_damage"]))
	assert_eq(claws, 6, "six claws down the player")
	assert_within(float(ArenaData.PLAYER["walk"]) * float(ArenaData.BEAST["windup"]), 1.8, 0.0001,
		"stepping back during the wind-up covers 1.8 m")
