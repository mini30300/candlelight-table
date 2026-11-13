class_name BattleFxRules
extends RefCounted
## ท่าโจมตีและเอฟเฟกต์อาวุธของหน้าเดิม (ANIM, FXS, fxOf, machOf, startAttack, deathOf8) เป็นข้อมูลภาพล้วน
## ตาราง ANIM / TRACER / FLAME / FXS / FX_ST / FX_GUN / MACH8 มาจาก data/anim.json + fx.json (tools/export_data.js)
## ที่นี่มีแค่ฟังก์ชันเล็ก ๆ ที่พอร์ตจากหน้าเดิม · ไม่เคยแตะกติกา (สุ่มได้ไม่ต้องมี seed)

const ANIM_PATH := "res://data/anim.json"
const FX_PATH := "res://data/fx.json"

## จังหวะยิง [วินาทีถึงนัดแรก, ช่วงห่าง] ตามปืน (GUN_T) แล้วตามชนิดเอฟเฟกต์ (KIND_T8)
const GUN_T := {"sniper": [0.7, 0.3], "cannon": [0.42, 0.3], "plasma": [0.4, 0.26], "deffgun": [0.42, 0.3],
	"musket": [0.55, 0.3], "rotary": [0.4, 0.08], "dakka": [0.3, 0.09], "gaussh": [0.32, 0.2], "gauss": [0.32, 0.2],
	"xbow": [0.45, 0.3]}
const KIND_T8 := {"rocket": [0.5, 0.36], "melta": [0.4, 0.3], "plasma": [0.38, 0.24], "cannon": [0.42, 0.3],
	"sniper": [0.7, 0.3], "gatling": [0.36, 0.07], "hbolter": [0.3, 0.12], "beam": [0.34, 0.22], "warp": [0.4, 0.26]}
## ปืนที่ยิงลูกดอก/ก้อนหินโค้ง (MINI.GUN[g].bolt)
const BOLT_GUNS := {"xbow": "bolt", "ballista": "bigbolt", "catapult": "boulder", "thunderf": "boulder"}
## ปืนที่ไม่มีชนิดเอฟเฟกต์: ปืนพก (ท่ายิงมือเดียว)
const PISTOLS := {"pistol": 1, "spistol": 1, "slugga": 1}
## เวลาล้มตามแบบ (DIE8_T) และชื่อคลิป
const DIE_T := {"back": 1.4, "fwd": 1.6, "spin": 1.5, "kneel": 2.0, "drop": 1.5, "blown": 1.7, "side": 1.6,
	"topple": 2.6, "boom": 3.2}
const DIE_CLIP := {"back": "die_back", "fwd": "die_fwd", "spin": "die_spin", "kneel": "die_kneel", "drop": "die_drop",
	"blown": "die_blown", "side": "die_topple", "topple": "die_topple", "boom": ""}
const STOMP_T := 0.9
## ร่างสูงเกินนี้ (เมตร) ล้มแบบโค่น
const TALL := 3.5

static var _anim: Dictionary = {}
static var _tracer: Dictionary = {}
static var _flame: Dictionary = {}
static var _fx: Dictionary = {}
static var _loaded := false


static func _load() -> void:
	if _loaded:
		return
	_loaded = true
	var a: Variant = _json(ANIM_PATH)
	if a is Dictionary:
		_anim = a.get("anim", {})
		_tracer = a.get("tracer", {})
		_flame = a.get("flame", {})
	var f: Variant = _json(FX_PATH)
	if f is Dictionary:
		_fx = f


static func _json(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		return null
	return JSON.parse_string(FileAccess.get_file_as_string(path))


## ANIM ของชุด k ({} = ไม่มี)
static func anim_of(k: String) -> Dictionary:
	_load()
	return _anim.get(k, {})


## FXS[kind] ({} = ไม่มี)
static func fxs(kind: String) -> Dictionary:
	_load()
	return (_fx.get("fxs", {}) as Dictionary).get(kind, {})


static func shielded(k: String) -> bool:
	return int(anim_of(k).get("sh", 0)) == 1


## เครื่องจักร (ระเบิดเมื่อพัง): machOf
static func mach_of(k: String) -> bool:
	_load()
	if (_fx.get("beast8", {}) as Dictionary).has(k):
		return false
	if (_fx.get("mach8", {}) as Dictionary).has(k):
		return true
	var t := GameData.ty(k)
	return _on(t, "veh") or str(anim_of(k).get("r", "")) == "turret"


## ชนิดเอฟเฟกต์ของอาวุธ (fxOf): "" = แบบเดิม (เส้นกระสุนธรรมดา ไฟ ธนู ของขว้าง)
static func fx_of(k: String, melee: bool) -> String:
	_load()
	var t := GameData.ty(k)
	var w: Variant = t.get("mel" if melee else "gun")
	if not (w is Dictionary):
		return ""
	if (w as Dictionary).has("fx"):
		var fk := str(w["fx"])
		return fk if not fxs(fk).is_empty() else ""
	return _guess_mel(w) if melee else _guess_gun(w, k)


static func _name_kind(n: String) -> String:
	if _re("จรวด|มิสไซล์", n):
		return "rocket"
	if _re("พลาสมา", n):
		return "plasma"
	if _re("หลอม|เมลต้า", n):
		return "melta"
	if _re("ซุ่มยิง", n):
		return "sniper"
	if _re("จิต|วิญญาณ|นรก|ไฟเย็น|มิติ", n):
		return "warp"
	if _re("เลเซอร์|ลำแสง", n):
		return "beam"
	return ""


static func _guess_gun(w: Dictionary, k: String) -> String:
	var a := anim_of(k)
	var g := str(a.get("g", ""))
	var r := str(a.get("r", ""))
	var n := str(w.get("nm", ""))
	if _on(w, "tr") or r in ["flame", "spray", "breath", "bow", "throw", "hurl"] or BOLT_GUNS.has(g):
		return ""
	if (_fx.get("fx_generic", {}) as Dictionary).has(g) or g == "":
		var nk := _name_kind(n)
		if nk != "":
			return nk
	var gun_map: Dictionary = _fx.get("fx_gun", {})
	if gun_map.has(g):
		return str(gun_map[g])
	var nk2 := _name_kind(n)
	if nk2 != "":
		return nk2
	if _re("ระเบิด", n):
		return "bolter"
	if _re("กลหมุน|ปืนกล", n):
		return "gatling" if int(w.get("a", 1)) >= 4 else "hbolter"
	if _re("ปืนใหญ่", n):
		return "cannon"
	return ""


static func _guess_mel(w: Dictionary) -> String:
	var n := str(w.get("nm", ""))
	if _re("เลื่อย", n):
		return "chain"
	if _re("ค้อน|กระบอง|หมัด|กำปั้น|ประแจ|เท้า|กีบ|ลูกกลิ้ง|ตีนตะขาบ|ชน|เหยียบ", n):
		return "hammer"
	if _re("ก้าม|กรงเล็บ|เล็บ|เคียว|ข่วน|ตะปบ", n):
		return "claw"
	if _re("งับ|เขี้ยว|ปาก|ขากรรไกร|จะงอย|ฉก|เหล็กใน", n):
		return "bite"
	if _re("พลังจิต|วิญญาณ|ผี|มิติ|นรก|คำสาป", n):
		return "warp"
	if _re("พลัง|สายฟ้า|ศักดิ์สิทธิ์|ราชสีห์|ราชัน", n):
		return "power"
	return ""


static var _res: Dictionary = {}


static func _re(pat: String, s: String) -> bool:
	if not _res.has(pat):
		_res[pat] = RegEx.create_from_string(pat)
	return (_res[pat] as RegEx).search(s) != null


static func _on(d: Dictionary, key: String) -> bool:
	var v: Variant = d.get(key)
	if v == null:
		return false
	if v is bool:
		return v
	if v is int or v is float:
		return v != 0
	return str(v) != "" and str(v) != "0"


## แผนการโจมตีของโมเดลหนึ่งตัว (startAttack): hits = ผลลูกเต๋าที่โมเดลนี้ได้ (true = เข้า)
## {kind, clip(s), shots: [{t, hit}], dur, gun, fk, hv, proj}
static func plan(k: String, melee: bool, hits: Array, rng: RandomNumberGenerator) -> Dictionary:
	var a := anim_of(k)
	var t := GameData.ty(k)
	var kind := str(a.get("m", "bash")) if melee else str(a.get("r", "fire"))
	if kind == "":
		kind = "bash" if melee else "fire"
	if melee:
		var big := _on(t, "ttn") and not _on(t, "fly") and (kind in ["lunge", "bash"] or not a.has("m"))
		if kind == "stomp" or big:
			kind = "stomp"
	var p := {"kind": kind, "shots": [], "dur": 1.0, "gun": str(a.get("g", "")), "fk": fx_of(k, melee),
		"hand": str(a.get("hand", "")), "clips": [], "proj": ""}
	var shots: Array = p["shots"]
	var n := 0
	if melee and kind == "stomp":
		n = mini(2, hits.size())
		var per := ceili(float(hits.size()) / maxf(1.0, float(n)))
		for i in n:
			var any := false
			for j in range(i * per, mini(hits.size(), (i + 1) * per)):
				any = any or bool(hits[j])
			shots.append({"t": 0.2 + i * STOMP_T + 0.43, "hit": any})
		p["dur"] = 0.2 + n * STOMP_T + 0.3
		p["clips"] = [{"t": 0.0, "c": "stomp"}]
	elif melee:
		n = mini(3, hits.size())
		var last := -1
		for i in n:
			var v := rng.randi_range(0, 2)
			if v == last:
				v = (v + 1 + rng.randi_range(0, 1)) % 3
			last = v
			shots.append({"t": 0.15 + i * 0.55 + 0.28, "hit": bool(hits[i])})
			(p["clips"] as Array).append({"t": 0.15 + i * 0.55 - 0.1, "c": melee_clip(kind, v)})
		p["dur"] = 0.15 + n * 0.55 + 0.25
	elif kind == "bow":
		shots.append({"t": 0.75, "hit": bool(hits[0]) if hits.size() > 0 else false})
		p["dur"] = 1.3
		p["proj"] = "arrow"
	elif kind == "throw" or kind == "hurl":
		n = mini(2, hits.size())
		for i in n:
			shots.append({"t": 0.1 + i * 0.8 + 0.35, "hit": bool(hits[i])})
		p["dur"] = 0.1 + n * 0.8 + 0.25
		p["proj"] = "jav"
	elif kind in ["flame", "spray", "breath"]:
		n = mini(6, hits.size())
		for i in n:
			shots.append({"t": 0.3 + i * 0.12, "hit": bool(hits[i])})
		p["dur"] = 0.3 + n * 0.12 + 0.75
		p["proj"] = "flame"
	elif kind in ["gaze", "cast", "zap", "beam"]:
		n = mini(4, hits.size())
		for i in n:
			shots.append({"t": 0.55 + i * 0.3, "hit": bool(hits[i])})
		p["dur"] = 0.55 + (n - 1) * 0.3 + 0.7
		p["proj"] = "orb"
	elif kind == "lob":
		n = mini(3, hits.size())
		for i in n:
			shots.append({"t": 0.45 + i * 0.5, "hit": bool(hits[i])})
		p["dur"] = 0.45 + (n - 1) * 0.5 + 0.8
		p["proj"] = "shell"
	elif kind == "turret":
		n = mini(4, hits.size())
		for i in n:
			shots.append({"t": 0.7 + i * 0.5, "hit": bool(hits[i])})
		p["dur"] = 0.7 + (n - 1) * 0.5 + 0.8
	else:
		p["kind"] = "fire"
		if str(p["gun"]) == "":
			p["gun"] = "rifle"
		n = mini(hits.size(), 8)
		var gt: Variant = GUN_T.get(p["gun"], KIND_T8.get(p["fk"]))
		var t0 := float(gt[0]) if gt != null else 0.28
		var gap := float(gt[1]) if gt != null else (0.11 if n > 3 else 0.16)
		for i in n:
			shots.append({"t": t0 + i * gap, "hit": bool(hits[i])})
		p["dur"] = t0 + (n - 1) * gap + 0.6
	if BOLT_GUNS.has(str(p["gun"])) and not melee:
		p["proj"] = "boulder" if str(BOLT_GUNS[p["gun"]]) == "boulder" else "arrow"
	var fx := fxs(str(p["fk"]))
	p["hv"] = not melee and (str(p["gun"]) == "hmg" or _on(fx, "big") or str(p["fk"]) == "gatling")
	if not melee and (p["clips"] as Array).is_empty():
		var c := ranged_clip(str(p["kind"]), str(p["gun"]), str(p["hand"]), bool(p["hv"]))
		if c != "":
			p["clips"] = [{"t": 0.0, "c": c}]
	return p


## ท่ายิงของชนิด (คลิปใน humanoid.res) "" = ไม่มีท่า (ป้อมปืน)
static func ranged_clip(kind: String, gun: String, hand: String, hv: bool) -> String:
	match kind:
		"fire":
			if gun == "sniper":
				return "fire_sniper"
			if hand == "L":
				return "fire_pistol_l"
			if hand == "R" or PISTOLS.has(gun):
				return "fire_pistol_r"
			return "fire_heavy" if hv else "fire"
		"flame", "spray", "breath":
			return "flame"
		"zap", "beam", "gaze":
			return "zap"
		"cast":
			return "cast"
		"lob":
			return "lob"
		"throw":
			return "throw"
		"hurl":
			return "hurl"
		"bow":
			return "bow"
	return ""


static func melee_clip(kind: String, v: int) -> String:
	match kind:
		"swing":
			return "swing_%d" % v
		"swing2":
			return "swing2_%d" % v
		"thrust", "lunge":
			return "thrust_%d" % v
		"claw":
			return "claw_%d" % v
		"twin":
			return "twin"
		"stomp":
			return "stomp"
	return "bash_%d" % v


## แบบการล้ม (deathOf8): r = สุ่ม 0..1 (ภาพเท่านั้น)
static func death_of(k: String, fk: String, melee: bool, dmg: int, height: float, r: float) -> String:
	if mach_of(k):
		return "boom"
	if height >= TALL:
		return "topple"
	if fk == "cannon" or fk == "rocket" or (fk == "hammer" and dmg >= 2) or (fk in ["melta", "plasma", "warp"] and r < 0.45):
		return "blown"
	if fk == "sniper":
		return "drop"
	if melee:
		return "fwd" if r < 0.3 else "kneel" if r < 0.6 else "spin" if r < 0.8 else "back"
	return "back" if r < 0.34 else "spin" if r < 0.55 else "fwd" if r < 0.72 else "kneel" if r < 0.88 else "drop"


## ท่าสะดุ้ง: side = ทิศที่โดนเทียบกับที่หัน (front/back/left/right)
static func flinch_clip(side: String, heavy: bool) -> String:
	if heavy:
		return "flinch_heavy"
	match side:
		"back":
			return "flinch_back"
		"left":
			return "flinch_left"
		"right":
			return "flinch_right"
	return "flinch"


## สีเส้นกระสุน [แกน, รัศมีรอบ, ความกว้าง px] ตามชนิดเอฟเฟกต์ (FX_ST) แล้วตามปืน (TRACER)
static func tracer_style(fk: String, gun: String) -> Array:
	_load()
	var st: Dictionary = _fx.get("fx_st", {})
	if st.has(fk):
		return st[fk]
	if _tracer.has(gun):
		return _tracer[gun]
	return _tracer.get("rifle", ["#FFF1C8", "rgba(255,200,110,0.4)", 1.8])


## สีไฟพ่น [แกน, ขอบ, กลาง] "r,g,b" (FLAME)
static func flame_style(gun: String) -> Array:
	_load()
	return _flame.get(gun, _flame.get("fire", ["255,240,170", "255,110,20", "255,190,90"]))


## สีจาก "#RRGGBB" / "rgba(r,g,b,a)" / "r,g,b"
static func colour(s: Variant, alpha: float = 1.0) -> Color:
	var t := str(s).strip_edges()
	if t.begins_with("#"):
		var c := Color.html(t)
		c.a = alpha
		return c
	if t.begins_with("rgba(") or t.begins_with("rgb("):
		t = t.substr(t.find("(") + 1).trim_suffix(")")
	var p := t.split(",")
	if p.size() < 3:
		return Color(1, 1, 1, alpha)
	var a := float(p[3]) if p.size() > 3 else alpha
	return Color(float(p[0]) / 255.0, float(p[1]) / 255.0, float(p[2]) / 255.0, a)
