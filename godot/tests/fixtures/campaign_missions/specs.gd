extends RefCounted
## MissionSpec builders for the track C tests (CAMPAIGN_SPEC §5.4): the same shape CampaignGalaxy.mission_spec returns,
## with every field chosen by the test (type, biome, secondary types, faction, modifier, difficulty, seed).


static func make(ptype: String, opts: Dictionary = {}) -> Dictionary:
	var diff := str(opts.get("difficulty", "normal"))
	var sec: Array = []
	var idx := 1
	for s in opts.get("secondary", []):
		sec.append({"type": str(s), "idx": idx})
		idx += 1
	return {
		"v": 1, "week": int(opts.get("week", 2967)), "planet": str(opts.get("planet", "p00")),
		"biome": str(opts.get("biome", "ruin")), "faction": str(opts.get("faction", "swarm")),
		"modifier": str(opts.get("modifier", "armoured")), "featured": bool(opts.get("featured", false)),
		"primary": {"type": ptype, "idx": 0}, "secondary": sec, "difficulty": diff,
		"diff": CampaignRules.difficulty(diff), "seed": int(opts.get("seed", 12345)),
	}


## Every real spec of a week (all planets, all events) at one difficulty.
static func week_specs(w: int, diff: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for p: Dictionary in CampaignGalaxy.week(w)["planets"]:
		for e: Dictionary in p["events"]:
			out.append(CampaignGalaxy.mission_spec(w, str(p["id"]), int(e["idx"]), diff))
	return out
