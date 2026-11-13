class_name BattleFx
extends Node3D
## ภาพการรบของหน้าเดิมบนโต๊ะ: ท่าโจมตี/สะดุ้ง/ล้ม (คลิปใน humanoid.res) เส้นกระสุน แสงปากกระบอก ไฟพ่น ระเบิด
## เครื่องจักรระเบิด กล้องสั่น และร่างที่ล้มค้างบนสนาม (FALLEN) · อ่านจากเหตุการณ์ของ core หลังแต่ละก้าว (feed)
## ภาพล้วน: ไม่เขียนอะไรกลับไปที่กติกา สุ่มแบบไม่มี seed ได้ · ว่างงาน = ไม่มี _process เลย
## ตามระดับ (เหมือนตารางต่อระดับของหน้าเดิม): min = ท่าของตัวที่ยิง + เส้นกระสุนเส้นเดียว ไม่มีอนุภาค ไม่สั่น ไม่มีร่าง

const LIB_PATH := "res://assets/anim/humanoid.res"
const LV := {
	"hi": {"models": 5, "pt": 500, "glow": true, "shake": true, "fallen": 40, "skin_fallen": 12, "smoke": true, "puffs": 160},
	"mid": {"models": 4, "pt": 300, "glow": true, "shake": true, "fallen": 24, "skin_fallen": 6, "smoke": true, "puffs": 100},
	"lo": {"models": 3, "pt": 110, "glow": false, "shake": true, "fallen": 12, "skin_fallen": 0, "smoke": false, "puffs": 40},
	"min": {"models": 1, "pt": 0, "glow": false, "shake": false, "fallen": 0, "skin_fallen": 0, "smoke": false, "puffs": 0},
}
const FEED_MAX := 4.0          # การโจมตีในก้าวเดียวเริ่มไม่ช้ากว่านี้ (วินาที)
const ATTACK_GAP := 0.45       # การโจมตีถัดไปในก้าวเดียวกันเริ่มหลังอันก่อน
const NO_PAINT := Color(-1.0, 0.0, 0.0, 0.0)
const UP := Vector3.UP

## เปิดได้ไหม (headless = ไม่ · เทสตั้งเองได้) · enabled = หน้าการรบตั้งตามความเร็ว (ทันที = ปิด)
var allowed := true
var enabled := true
var time_scale := 1.0
var level := "mid"
var table: Node3D
## นับไว้ให้เทส (ไม่ใช่กติกา)
var stats := {"attacks": 0, "shots": 0, "clips": 0, "deaths": 0, "flinches": 0, "blasts": 0, "fallen": 0, "sounds": 0,
	"impacts": 0, "peak_sparks": 0, "peak_puffs": 0}

var _t := 0.0
var _q: Array = []             # [เวลา, Callable] เรียงตามเวลา
var _shots: Array = []
var _beams: Array = []
var _puffs: Array = []
var _sparks: Array = []
var _actors: Dictionary = {}   # uid → ท่าที่กำลังเล่น
var _fallen: Array = []        # ร่างที่ล้ม (เก่าสุดก่อน)
var _falling: Array = []       # ร่างแข็งที่กำลังล้ม
var _corpse_mm: Dictionary = {}  # คีย์เมช → MultiMeshInstance3D ของร่างแข็ง
var _cache: Dictionary = {}    # uid → {k, sq, side, pos, yaw, r, h}
var _sq_end: Dictionary = {}   # หมู่ → เวลาที่นัดสุดท้ายถึง
var _sq_hit: Dictionary = {}   # หมู่ที่โดน → [fk, melee, จุดของผู้โจมตี]
var _phase := ""
var _busy := 0.0
var _shake := 0.0
var _rng := RandomNumberGenerator.new()
var _mesh: ImmediateMesh
var _mi: MeshInstance3D
var _mat_add: StandardMaterial3D
var _mat_mix: StandardMaterial3D
var _lib: AnimationLibrary
var _holds: Dictionary = {}
var _manifest: Dictionary = {}
var _by_pos: Dictionary = {}


func _ready() -> void:
	_rng.randomize()
	set_process(false)
	allowed = DisplayServer.get_name() != "headless"
	enabled = allowed


# ---- API ----

## เริ่มนัดใหม่บนโต๊ะ t: ล้างของเก่าแล้วจำตำแหน่งโมเดล
func begin(t: Node3D, st: BattleState) -> void:
	table = t
	clear()
	if table != null:
		level = str(table.get("level"))
	if not LV.has(level):
		level = "mid"
	_phase = st.phase_name() if st != null else ""
	snapshot(st)


func set_level(l: String) -> void:
	level = l if LV.has(l) else "mid"
	if LV[level]["fallen"] == 0:
		_clear_fallen()


## ล้างทุกอย่าง (ท่า เอฟเฟกต์ ร่าง) คืนท่ายืนให้ฟิกเกอร์
func clear() -> void:
	for uid in _actors.keys():
		_end_actor(_actors[uid])
	_actors.clear()
	_q.clear()
	_shots.clear()
	_beams.clear()
	_puffs.clear()
	_sparks.clear()
	_falling.clear()
	_sq_end.clear()
	_sq_hit.clear()
	_clear_fallen()
	_busy = _t
	_shake = 0.0
	_cam_offset(0.0, 0.0)
	if _mesh != null:
		_mesh.clear_surfaces()
	if _mi != null:
		_mi.visible = false
	set_process(false)


## เวลาจริง (วินาที) ที่ภาพของก้าวล่าสุดยังเล่นอยู่ (หน้าการรบรอก่อนก้าวต่อ)
func busy_left() -> float:
	return maxf(0.0, (_busy - _t) / maxf(0.01, time_scale))


func active() -> bool:
	return not (_q.is_empty() and _shots.is_empty() and _beams.is_empty() and _puffs.is_empty() and _sparks.is_empty()
		and _actors.is_empty() and _falling.is_empty() and _shake <= 0.0)


func counts() -> Dictionary:
	return {"actors": _actors.size(), "shots": _shots.size(), "beams": _beams.size(), "puffs": _puffs.size(),
		"sparks": _sparks.size(), "fallen": _fallen.size(), "queued": _q.size(), "processing": is_processing(),
		"corpse_mm": _corpse_mm.size()}


## จำตำแหน่ง/ชนิดของทุกโมเดล (ตัวที่ตายในก้าวถัดไปยังหาเจอ)
func snapshot(st: BattleState) -> void:
	_cache.clear()
	if st == null or table == null:
		return
	var terrain: Node = table.get("terrain")
	for u in st.units:
		var s := st.squad(u.sq)
		var x := u.x / 1000.0
		var z := u.z / 1000.0
		var y := float(terrain.call("height_at", x, z)) if terrain != null else 0.0
		_cache[u.id] = {"k": u.t, "sq": u.sq, "side": u.side, "pos": Vector3(x, y, z),
			"yaw": atan2(float(s.fx), float(s.fz)) if s != null else 0.0, "r": EggShapes.base_r(u.t), "h": _height(u.t)}


## เหตุการณ์ของหนึ่งก้าว (หลัง sync_battle ของโต๊ะ) → ตั้งเวลาท่าและเอฟเฟกต์ แล้วจำตำแหน่งใหม่
func feed(evs: Array, st: BattleState) -> void:
	if st == null:
		return
	if not enabled or table == null or evs.is_empty():
		for e: Variant in evs:
			if e is Dictionary and Events.id_of(e) == Events.Id.PHASE:
				_phase = str(e.get("ph", ""))
		snapshot(st)
		return
	var hitn := {}
	for e: Variant in evs:
		if e is Dictionary and Events.id_of(e) == Events.Id.HIT:
			hitn[str(e.get("p", ""))] = int(e.get("n", 0))
	var t0 := clampf(_busy - 0.2, _t, _t + 1.0)
	var t_cur := t0
	for e: Variant in evs:
		if not e is Dictionary:
			continue
		var ev: Dictionary = e
		match Events.id_of(ev):
			Events.Id.PHASE:
				_phase = str(ev.get("ph", ""))
			Events.Id.ATTACK_STAGE:
				if str(ev.get("stage", "")) == "hit":
					var end := _attack(ev, int(hitn.get(str(ev.get("p", "")), -1)), st, t_cur)
					if end > t_cur:
						t_cur = minf(t_cur + ATTACK_GAP + (end - t_cur) * 0.35, t0 + FEED_MAX)
			Events.Id.DAMAGE:
				_hurt(str(ev.get("uid", "")), false, st)
			Events.Id.DEATH:
				_hurt(str(ev.get("uid", "")), true, st)
			Events.Id.CHARGE:
				var c: Dictionary = _first_of(str(ev.get("sid", "")))
				if not c.is_empty():
					_at(t_cur, _snd.bind(&"charge", c["pos"] + UP))
	snapshot(st)
	_wake()


# ---- การโจมตี ----

## การโจมตีหนึ่งครั้ง (ขั้นทอยเข้าเป้า): แบ่งลูกเต๋าให้ผู้ยิงไม่เกิน LV.models ตัว คืนเวลาที่นัดสุดท้ายถึง
func _attack(ev: Dictionary, n_hits: int, st: BattleState, t0: float) -> float:
	var p := str(ev.get("p", "")).split(">")
	if p.size() < 2:
		return t0
	var sid := p[0]
	var tid := p[1]
	var melee := _phase == "fight"
	var dice: Array = Array(ev.get("dice", []))
	var flags := []
	if dice.is_empty():
		for i in maxi(1, n_hits):
			flags.append(true)
	else:
		var idx := range(dice.size())
		idx.sort_custom(func(a: int, b: int) -> bool: return int(dice[a]) > int(dice[b]))
		flags.resize(dice.size())
		for i in idx.size():
			flags[idx[i]] = (i < n_hits) if n_hits >= 0 else int(dice[idx[i]]) >= 4
	var shooters := _models_of(sid, st)
	var targets := _cached_of(tid)
	if shooters.is_empty() or targets.is_empty():
		return t0
	var centre := Vector3.ZERO
	for tm: Dictionary in targets:
		centre += tm["pos"]
	centre /= float(targets.size())
	shooters.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return (a["pos"] as Vector3).distance_squared_to(centre) < (b["pos"] as Vector3).distance_squared_to(centre))
	var cap: int = LV[level]["models"]
	if shooters.size() > cap:
		shooters = shooters.slice(0, cap)
	stats["attacks"] += 1
	var per := maxi(1, ceili(float(flags.size()) / float(shooters.size())))
	var last := t0
	var fk_any := ""
	for k in shooters.size():
		var mine := flags.slice(k * per, (k + 1) * per)
		if mine.is_empty():
			continue
		var m: Dictionary = shooters[k]
		var tm := _nearest(targets, m["pos"])
		var pl := BattleFxRules.plan(str(m["k"]), melee, mine, _rng)
		fk_any = str(pl["fk"])
		_act(str(m["uid"]), t0, pl["clips"], float(pl["dur"]), tm["pos"], "lunge" if melee else "recoil", pl["shots"])
		for s: Dictionary in pl["shots"]:
			var ts := t0 + float(s["t"])
			if melee:
				_at(ts, _blow.bind(m, tm, pl, bool(s["hit"])))
				last = maxf(last, ts + 0.05)
			else:
				_at(ts, _fire.bind(m, tm, pl, bool(s["hit"])))
				last = maxf(last, ts + _flight(m["pos"], tm["pos"], pl))
		_busy = maxf(_busy, t0 + float(pl["dur"]))
	_sq_end[tid] = maxf(float(_sq_end.get(tid, 0.0)), last)
	_sq_hit[tid] = [fk_any, melee, (shooters[0] as Dictionary)["pos"]]
	_busy = maxf(_busy, last + 0.15)
	# โล่: ยกรับตั้งแต่เริ่มจนนัดสุดท้ายถึง (brace ค้างที่ raised)
	for tm: Dictionary in targets:
		if BattleFxRules.shielded(str(tm["k"])) and _alive(str(tm["uid"])):
			_act(str(tm["uid"]), t0, [{"t": 0.0, "c": "brace"}], last - t0 + 0.4, (shooters[0] as Dictionary)["pos"], "",
				[], [0.2, last - t0])
	return last


## เวลาที่กระสุนบินจากผู้ยิงถึงเป้า
func _flight(a: Vector3, b: Vector3, pl: Dictionary) -> float:
	var d := a.distance_to(b)
	var proj := str(pl["proj"])
	if proj in ["arrow", "jav", "boulder", "shell"]:
		return clampf(d / 18.0, 0.3, 1.2)
	if proj == "flame":
		return clampf(d / 16.0, 0.18, 0.8)
	var spd := float(BattleFxRules.fxs(str(pl["fk"])).get("spd", 60))
	if spd <= 0.0:
		return 0.05
	return clampf(d / spd, 0.05, 0.8)


## หนึ่งนัด: แสงปากกระบอก เสียง กระสุน (บิน/ลำแสง/โค้ง/ไฟ) แล้วจุดโดน
func _fire(m: Dictionary, tm: Dictionary, pl: Dictionary, hit: bool) -> void:
	stats["shots"] += 1
	var lv: Dictionary = LV[level]
	var mp: Vector3 = _pos_now(str(m["uid"]), m["pos"])
	var tp: Vector3 = _pos_now(str(tm["uid"]), tm["pos"])
	var dir := Vector3(tp.x - mp.x, 0.0, tp.z - mp.z).normalized()
	var mz := mp + UP * float(m["h"]) * 0.62 + dir * float(m["r"]) * 0.9
	var end := tp + UP * float(tm["h"]) * _rng.randf_range(0.35, 0.7)
	if not hit:
		var side := dir.cross(UP)
		end = tp + side * _rng.randf_range(-1.6, 1.6) + dir * _rng.randf_range(0.4, 1.4)
		end.y = tp.y + 0.05
	var fk := str(pl["fk"])
	var fx := BattleFxRules.fxs(fk)
	var big := bool(pl["hv"])
	var style := BattleFxRules.tracer_style(fk, str(pl["gun"]))
	var core := BattleFxRules.colour(style[0])
	var halo := BattleFxRules.colour(style[1])
	var w := float(style[2]) * 0.035
	var proj := str(pl["proj"])
	_snd(_weapon_snd(pl), mz)
	if level != "min":
		_puff(mz, Vector3.ZERO, 0.15, 0.5 * (1.6 if big else 1.0), 0.14, core, halo, true)
		if lv["smoke"]:
			_puff(mz, UP * 0.4, 0.1, 0.4, 0.8, Color(0.69, 0.67, 0.65, 0.35), Color(0.69, 0.67, 0.65, 0.0), false)
	var cb := _impact.bind(tm, hit, pl)
	if proj == "flame":
		var fc := BattleFxRules.flame_style(str(pl["gun"]))
		var dur := clampf(mz.distance_to(end) / 16.0, 0.18, 0.8)
		if level == "min":
			_beams.append({"a": mz, "b": end, "t": 0.0, "life": dur, "w": 0.12, "core": BattleFxRules.colour(fc[0]), "halo": BattleFxRules.colour(fc[1], 0.5)})
		else:
			for i in 7:
				var f := float(i) / 6.0
				_at(_t + dur * f * 0.8, _puff.bind(mz.lerp(end, f), (end - mz).normalized() * 2.0 + UP * 0.6, 0.15 + f * 0.25,
					0.4 + f * 0.6, 0.45, BattleFxRules.colour(fc[2], 0.9), BattleFxRules.colour(fc[1], 0.0), true))
		_at(_t + dur, cb.bind(end))
		return
	var spd := float(fx.get("spd", 60 if proj == "" else 30))
	var pr := str(fx.get("pr", "tracer"))
	if proj in ["arrow", "jav", "boulder", "shell"]:
		var d := mz.distance_to(end)
		var arc := d * (0.3 if proj in ["boulder", "shell"] else 0.12)
		_shots.append({"a": mz, "b": end, "t": 0.0, "dur": clampf(d / 18.0, 0.3, 1.2), "h": arc, "w": w * (2.5 if proj == "boulder" else 1.0),
			"len": 0.5, "core": core, "halo": halo, "cb": cb.bind(end), "orb": proj in ["boulder", "shell"]})
	elif spd <= 0.0 or pr in ["streak", "beam", "melta"]:
		var thick := 2.4 if pr in ["beam", "melta"] else 1.0
		_beams.append({"a": mz, "b": end, "t": 0.0, "life": 0.3 if thick > 1.0 else 0.2, "w": w * thick, "core": core, "halo": halo})
		_at(_t + 0.03, cb.bind(end))
	else:
		var dur2 := clampf(mz.distance_to(end) / spd, 0.05, 0.8)
		_shots.append({"a": mz, "b": end, "t": 0.0, "dur": dur2, "h": 0.0, "w": w, "len": clampf(spd * 0.03, 0.4, 2.4),
			"core": core, "halo": halo, "cb": cb.bind(end), "orb": pr in ["orb", "shell8", "rocket"]})
		if pr == "rocket" and lv["smoke"]:
			for i in 4:
				_at(_t + dur2 * float(i) / 4.0, _puff.bind(mz.lerp(end, float(i) / 4.0), UP * 0.3, 0.1, 0.35, 0.7,
					Color(0.7, 0.68, 0.66, 0.3), Color(0.7, 0.68, 0.66, 0.0), false))


## กระสุนถึง: โดน = แสง/ประกายตามชนิด (FXS.hit) ระเบิดถ้าเป็นปืนใหญ่ · พลาด = ฝุ่นที่พื้น
## (bind ซ้อน: จุดที่ถึงมาก่อน)
func _impact(at: Vector3, tm: Dictionary, hit: bool, pl: Dictionary) -> void:
	stats["impacts"] += 1
	var fk := str(pl["fk"])
	var fx := BattleFxRules.fxs(fk)
	var kind := str(fx.get("hit", "pop"))
	var style := BattleFxRules.tracer_style(fk, str(pl["gun"]))
	var halo := BattleFxRules.colour(style[1], 0.8)
	if kind == "blast" or str(pl["proj"]) in ["boulder", "shell"]:
		_blast(at, 1.1 if bool(pl["hv"]) else 0.7)
		return
	if level == "min":
		return
	if not hit:
		_puff(at, UP * 0.5, 0.1, 0.45, 0.6, Color(0.6, 0.55, 0.47, 0.45), Color(0.6, 0.55, 0.47, 0.0), false)
		_spark_burst(at, Color(0.9, 0.85, 0.75), 3, 2.0)
		return
	_snd(&"hit", at)
	_puff(at, Vector3.ZERO, 0.08, 0.32, 0.16, Color(1, 0.95, 0.8, 0.9), halo, true)
	match kind:
		"dust":
			_puff(at, UP * 0.4, 0.1, 0.4, 0.5, Color(0.6, 0.55, 0.47, 0.4), Color(0.6, 0.55, 0.47, 0.0), false)
		"splash", "melt", "burn", "warp":
			_puff(at, Vector3.ZERO, 0.15, 0.55, 0.35, halo, Color(halo.r, halo.g, halo.b, 0.0), true)
	_spark_burst(at, Color(1.0, 0.5, 0.2), 6, 3.0)


## หนึ่งครั้งที่ตี: เสียงอาวุธ ประกายตามสีของอาวุธ (FXS.tr) ที่เป้า
func _blow(m: Dictionary, tm: Dictionary, pl: Dictionary, hit: bool) -> void:
	stats["shots"] += 1
	var fx := BattleFxRules.fxs(str(pl["fk"]))
	var tp: Vector3 = _pos_now(str(tm["uid"]), tm["pos"]) + UP * float(tm["h"]) * 0.55
	var mp: Vector3 = _pos_now(str(m["uid"]), m["pos"])
	var front := tp + (mp - tp).normalized() * float(tm["r"]) * 0.5
	_snd(_weapon_snd(pl) if not fx.is_empty() else (&"stomp" if str(pl["kind"]) == "stomp" else &"swing"), front)
	if str(pl["kind"]) == "stomp":
		_blast(Vector3(tp.x, tp.y - float(tm["h"]) * 0.5, tp.z), 0.6, false)
	if not hit or level == "min":
		return
	_snd(&"hit", front)
	var c := BattleFxRules.colour(fx.get("tr", "255,236,205")) if fx.get("tr") != null else Color(1, 0.9, 0.8)
	_puff(front, Vector3.ZERO, 0.06, 0.28, 0.14, Color(c.r, c.g, c.b, 0.9), Color(c.r, c.g, c.b, 0.0), true)
	_spark_burst(front, c, 7, 3.2)


## ระเบิด (blast8): ลูกไฟ ควัน ประกาย กล้องสั่น เสียงตูม · min = ไม่มีอะไร (เส้นกระสุนพอ)
func _blast(p: Vector3, sz: float, sound: bool = true) -> void:
	stats["blasts"] += 1
	if sound:
		_snd(&"boom", p)
	if level == "min":
		return
	var lv: Dictionary = LV[level]
	_puff(p, Vector3.ZERO, 0.3 * sz, 1.6 * sz, 0.45, Color(1.0, 0.85, 0.5, 1.0), Color(1.0, 0.35, 0.05, 0.0), true)
	_puff(p, UP * 0.6, 0.2 * sz, 1.0 * sz, 0.3, Color(1.0, 0.95, 0.8, 0.9), Color(1.0, 0.6, 0.2, 0.0), true)
	if lv["smoke"]:
		for i in 3:
			var off := Vector3(_rng.randf_range(-0.4, 0.4), 0.0, _rng.randf_range(-0.4, 0.4)) * sz
			_puff(p + off, UP * _rng.randf_range(0.6, 1.2), 0.4 * sz, 1.4 * sz, 1.6, Color(0.3, 0.28, 0.27, 0.55),
				Color(0.3, 0.28, 0.27, 0.0), false)
	_spark_burst(p, Color(1.0, 0.65, 0.25), int(10 * sz), 5.0 * sqrt(sz))
	if lv["shake"]:
		_shake = minf(0.5, _shake + 0.12 * sz)


# ---- ถูกยิง / ตาย ----

## โดนแผล = สะดุ้ง · ตาย = ล้ม (คลิป die_*) แล้วค้างเป็นร่าง หรือระเบิดถ้าเป็นเครื่องจักร · ตั้งเวลาหลังนัดสุดท้ายถึง
func _hurt(uid: String, dead: bool, _st: BattleState) -> void:
	var c: Dictionary = _cache.get(uid, {})
	if c.is_empty():
		return
	var sq := str(c["sq"])
	var at := maxf(_t, float(_sq_end.get(sq, _t)))
	var info: Array = _sq_hit.get(sq, ["", false, c["pos"]])
	var data := c.duplicate()
	data["uid"] = uid
	if dead:
		_busy = maxf(_busy, at + 0.3)
		_at(at, _die.bind(data, str(info[0]), bool(info[1]), info[2] as Vector3))
	else:
		_at(at, _flinch.bind(data, str(info[0]), info[2] as Vector3))


func _flinch(c: Dictionary, fk: String, from: Vector3) -> void:
	stats["flinches"] += 1
	var uid := str(c["uid"])
	if not _alive(uid):
		return
	var p: Vector3 = c["pos"]
	var to := (from - p)
	var local := to.rotated(UP, -float(c["yaw"]))
	var side := "front"
	if absf(local.x) > absf(local.z):
		side = "left" if local.x > 0.0 else "right"
	elif local.z < 0.0:
		side = "back"
	var heavy := fk in ["cannon", "rocket", "hammer"]
	_act(uid, _t, [{"t": 0.0, "c": BattleFxRules.flinch_clip(side, heavy)}], 0.6, Vector3.INF, "flinch", [{"t": 0.0}])


func _die(c: Dictionary, fk: String, melee: bool, from: Vector3) -> void:
	stats["deaths"] += 1
	var k := str(c["k"])
	var p: Vector3 = c["pos"]
	var h := float(c["h"])
	var v := BattleFxRules.death_of(k, fk, melee, 1, h, _rng.randf())
	_snd(&"die", p + UP * 0.5)
	if v == "boom":
		_blast(p + UP * h * 0.4, clampf(h / 2.0, 0.8, 3.0))
		_snd(&"debris", p)
	_corpse(c, v, from)


## ร่างที่ล้มค้างบนสนาม: ชุดโมเดล skinned เล่นคลิปล้ม (ไม่เกิน skin_fallen) ที่เหลือเป็นเมชแข็งล้มลง (MultiMesh ต่อเมช)
func _corpse(c: Dictionary, v: String, from: Vector3) -> void:
	var lv: Dictionary = LV[level]
	var cap: int = lv["fallen"]
	if cap <= 0:
		return
	var pool: FigurePool = table.get("figures") if table != null else null
	if pool == null:
		return
	while _fallen.size() >= cap:
		_drop_corpse(_fallen.pop_front())
	var k := str(c["k"])
	var p: Vector3 = c["pos"]
	var away := Vector3(p.x - from.x, 0.0, p.z - from.z)
	if away.length() < 0.01:
		away = Vector3(0, 0, 1).rotated(UP, float(c["yaw"]))
	away = away.normalized()
	var clip := str(BattleFxRules.DIE_CLIP.get(v, "die_back"))
	var skinned := 0
	for f: Dictionary in _fallen:
		if f.has("node"):
			skinned += 1
	if pool.style == "kit" and pool.kit_is_skinned(k) and clip != "" and skinned < int(lv["skin_fallen"]) and _library() != null:
		var kd: FigurePool.KitData = pool.call("_kit", k)
		var node := kd.scene.instantiate() as Node3D
		if node != null:
			if not bool(pool.get("_material_is_shader")):
				_override_material(node, pool.call("_figure_material"))
			# หันหน้าเข้าหาผู้ยิง: ท่าล้มหงายไปทางตรงข้าม
			node.transform = Transform3D(Basis(UP, atan2(-away.x, -away.z)), p)
			add_child(node)
			var ap := _ap_for(node, k)
			if ap != null:
				ap.play("humanoid/" + clip)
				stats["clips"] += 1
				ap.animation_finished.connect(func(_n: StringName) -> void: ap.queue_free(), CONNECT_ONE_SHOT)
			_fallen.append({"node": node})
			stats["fallen"] += 1
			return
	# เมชแข็ง: ตัวไข่ หรือ LOD ของชุดโมเดล
	var key := ""
	var mesh: Mesh
	var scale := 1.0
	if pool.style == "egg" or not pool.kit_available(k):
		var cls := EggShapes.class_of(k)
		key = "egg:" + cls
		mesh = EggShapes.mesh(cls, level == "lo" or level == "min")
		scale = float(c["r"])
	else:
		var kd2: FigurePool.KitData = pool.call("_kit", k)
		var li := mini(int(FigurePool.RIGID_LOD.get(level, 0)), kd2.lods.size() - 1)
		key = "kit:%s:%d" % [k, li]
		mesh = kd2.lods[li]
	var mmi: MultiMeshInstance3D = _corpse_mm.get(key)
	if mmi == null or not is_instance_valid(mmi):
		mmi = MultiMeshInstance3D.new()
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.use_custom_data = true
		mm.mesh = mesh
		mm.instance_count = cap
		mm.visible_instance_count = 0
		mmi.multimesh = mm
		mmi.material_override = pool.call("_figure_material")
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mmi)
		_corpse_mm[key] = mmi
	var mm2 := mmi.multimesh
	var slot := _free_slot(key, mm2)
	var base := Transform3D(Basis(UP, float(c["yaw"])).scaled(Vector3.ONE * scale), p)
	mm2.set_instance_transform(slot, base)
	mm2.set_instance_color(slot, Color.WHITE)
	mm2.set_instance_custom_data(slot, NO_PAINT)
	var f2 := {"mm": mm2, "key": key, "slot": slot, "base": base, "axis": away.cross(UP).normalized() * -1.0,
		"t": 0.0, "dur": minf(0.9, float(BattleFxRules.DIE_T.get(v, 1.4)) * 0.5), "tip": 0.25 if v == "boom" else 1.45,
		"sink": float(c["h"]) * (0.2 if v == "boom" else 0.05), "p": p}
	_fallen.append(f2)
	_falling.append(f2)
	stats["fallen"] += 1


func _free_slot(key: String, mm: MultiMesh) -> int:
	var used := {}
	for f: Dictionary in _fallen:
		if str(f.get("key", "")) == key:
			used[int(f["slot"])] = true
	for i in mm.instance_count:
		if not used.has(i):
			mm.visible_instance_count = maxi(mm.visible_instance_count, i + 1)
			return i
	return 0


func _drop_corpse(f: Dictionary) -> void:
	if f.has("node"):
		var n: Node = f["node"]
		if is_instance_valid(n):
			n.queue_free()
	elif f.has("mm"):
		var mm: MultiMesh = f["mm"]
		mm.set_instance_transform(int(f["slot"]), Transform3D(Basis().scaled(Vector3.ZERO), Vector3.ZERO))
		_falling.erase(f)


func _clear_fallen() -> void:
	for f: Dictionary in _fallen:
		_drop_corpse(f)
	_fallen.clear()
	_falling.clear()
	for key in _corpse_mm:
		var n: Node = _corpse_mm[key]
		if is_instance_valid(n):
			n.queue_free()
	_corpse_mm.clear()


# ---- ท่าของโมเดลบนโต๊ะ ----

## ท่าของโมเดล uid ตั้งแต่ t0: คลิปตามเวลา (ฟิกเกอร์ skinned) หรือขยับเมชแข็ง/ตัวไข่ (ถอย/พุ่ง/สะดุ้ง) · หันหาเป้า
func _act(uid: String, t0: float, clips: Array, dur: float, face: Vector3, pose: String, pulses: Array, hold: Array = []) -> void:
	if _actors.has(uid):
		_end_actor(_actors[uid])
	_actors[uid] = {"uid": uid, "t0": t0, "clips": clips, "dur": dur, "face": face, "pose": pose, "pulses": pulses,
		"hold": hold, "cur": "", "node": null, "mm": null, "idx": -1, "base": Transform3D()}


func _drive_actor(a: Dictionary, el: float) -> void:
	if el < 0.0:
		return
	if not _resolve(a):
		return
	var base: Transform3D = a["base"]
	var xf := base
	var face: Vector3 = a["face"]
	if face.is_finite():
		var d := face - base.origin
		if Vector2(d.x, d.z).length() > 0.05:
			var s := base.basis.get_scale()
			xf.basis = Basis(UP, atan2(d.x, d.z)).scaled(s)
	var node: Node3D = a["node"]
	if node != null:
		node.transform = xf
		var ap := _ap_for(node, _kit_of(str(a["uid"])))
		if ap == null:
			return
		var cur := {}
		for c: Dictionary in a["clips"]:
			if float(c["t"]) <= el:
				cur = c
		if cur.is_empty():
			return
		var name := "humanoid/" + str(cur["c"])
		if not ap.has_animation(name):
			return
		var local := el - float(cur["t"])
		var hold: Array = a["hold"]
		if hold.size() == 2 and local > float(hold[0]):
			local = float(hold[0]) if local < float(hold[1]) else float(hold[0]) + (local - float(hold[1]))
		if str(a["cur"]) != name:
			a["cur"] = name
			ap.play(name, 0.08)
			stats["clips"] += 1
		ap.seek(local, true)
	else:
		# เมชแข็ง/ตัวไข่: ถอยตอนยิง พุ่งตอนตี โยกตอนโดน
		var off := 0.0
		var tilt := 0.0
		for pz: Dictionary in a["pulses"]:
			var x := el - float(pz["t"])
			if x < 0.0:
				continue
			var k := x / 0.08 if x < 0.08 else exp(-(x - 0.08) * 7.0)
			match str(a["pose"]):
				"recoil":
					off -= 0.05 * k
				"lunge":
					off += 0.3 * k
				"flinch":
					off -= 0.12 * k
					tilt -= 0.25 * k
		var fwd := xf.basis.z.normalized()
		xf.origin += fwd * off * (xf.basis.get_scale().x if a.get("egg", false) else 1.0)
		if tilt != 0.0:
			xf.basis = xf.basis.rotated(xf.basis.x.normalized(), tilt)
		(a["mm"] as MultiMesh).set_instance_transform(int(a["idx"]), xf)


## หาโหนด/ช่องของโมเดลบนโต๊ะ (หลังโต๊ะวาดใหม่ก็หาใหม่) · false = ไม่เจอ (ตายแล้ว หรือไม่ได้วาด)
func _resolve(a: Dictionary) -> bool:
	var node: Variant = a["node"]
	if node != null and is_instance_valid(node) and not (node as Node).is_queued_for_deletion():
		return true
	var mmv: Variant = a["mm"]
	if mmv != null and a.get("mmi") != null and is_instance_valid(a["mmi"]) and not (a["mmi"] as Node).is_queued_for_deletion():
		return true
	a["node"] = null
	a["mm"] = null
	a["cur"] = ""
	var pool: FigurePool = table.get("figures") if table != null else null
	if pool == null:
		return false
	var fi := int(table.call("unit_fig", str(a["uid"])))
	if fi < 0 or fi >= pool.figures.size():
		return false
	var f: FigurePool.Figure = pool.figures[fi]
	if f.skinned:
		var nv: Variant = _by_pos.get(f.pos)
		if nv == null or not is_instance_valid(nv) or (nv as Node).is_queued_for_deletion():
			_by_pos.clear()
			for c: Variant in pool.get("_near"):
				if is_instance_valid(c) and not (c as Node).is_queued_for_deletion():
					_by_pos[(c as Node3D).position] = c
			nv = _by_pos.get(f.pos)
		if nv == null or not is_instance_valid(nv):
			return false
		var n := nv as Node3D
		a["node"] = n
		a["base"] = n.transform
		return true
	var nm := ("Egg_" + EggShapes.class_of(f.kit)) if pool.style == "egg" else ("Kit_" + f.kit)
	var mmi := pool.get_node_or_null(NodePath(nm)) as MultiMeshInstance3D
	if mmi == null or mmi.is_queued_for_deletion() or mmi.multimesh == null:
		return false
	var mm := mmi.multimesh
	for i in mm.instance_count:
		var xf := mm.get_instance_transform(i)
		if xf.origin.is_equal_approx(f.pos):
			a["mm"] = mm
			a["mmi"] = mmi
			a["idx"] = i
			a["base"] = xf
			a["egg"] = pool.style == "egg"
			return true
	return false


## จบท่า: คืนท่ายืนและทิศเดิม
func _end_actor(a: Dictionary) -> void:
	var node: Variant = a["node"]
	if node != null and is_instance_valid(node):
		var n := node as Node3D
		n.transform = a["base"]
		var ap := n.get_node_or_null(^"FxAnim")
		if ap != null:
			(ap as AnimationPlayer).stop()
			ap.queue_free()
		var sk := _skeleton(n)
		if sk != null:
			sk.reset_bone_poses()
	var mmi: Variant = a.get("mmi")
	if a["mm"] != null and mmi != null and is_instance_valid(mmi) and not (mmi as Node).is_queued_for_deletion():
		var mm: MultiMesh = a["mm"]
		if int(a["idx"]) < mm.instance_count:
			mm.set_instance_transform(int(a["idx"]), a["base"])


func _ap_for(node: Node3D, k: String) -> AnimationPlayer:
	var ap := node.get_node_or_null(^"FxAnim") as AnimationPlayer
	if ap != null:
		return ap
	if _library() == null:
		return null
	var sk := _skeleton(node)
	if sk == null:
		return null
	var entry: Variant = _manifest.get(k, {})
	if entry is Dictionary:
		sk.motion_scale = float((entry as Dictionary).get("scale", 1.0))
	ap = AnimationPlayer.new()
	ap.name = "FxAnim"
	node.add_child(ap)
	ap.root_node = NodePath("..")
	ap.add_animation_library("humanoid", _lib)
	var hold: Dictionary = _holds.get(k, {})
	if not hold.is_empty():
		ap.mixer_applied.connect(_apply_holds.bind(ap, sk, hold))
	return ap


func _library() -> AnimationLibrary:
	if _lib == null and ResourceLoader.exists(LIB_PATH):
		_lib = load(LIB_PATH) as AnimationLibrary
		if _lib != null:
			_holds = _lib.get_meta("holds", {})
			_manifest = KitLibrary.load_manifest()
	return _lib


func _skeleton(n: Node) -> Skeleton3D:
	var sk := n.get_node_or_null(^"Skeleton3D") as Skeleton3D
	if sk != null:
		return sk
	for c in n.get_children():
		if c is Skeleton3D:
			return c
	return null


## ท่าโพสของชุดทับคลิป (เหมือน apply_holds ของ test_anim_footslide)
func _apply_holds(ap: AnimationPlayer, sk: Skeleton3D, hold: Dictionary) -> void:
	if not is_instance_valid(ap) or not is_instance_valid(sk) or ap.current_animation == "":
		return
	var anim := ap.get_animation(ap.current_animation)
	if anim == null:
		return
	var mode := String(anim.get_meta("hold_mode", "all"))
	if mode == "none" or not (hold.get("joints") is Dictionary):
		return
	var drives: PackedStringArray = anim.get_meta("drives", PackedStringArray())
	var joints: Dictionary = hold["joints"]
	for j in joints.keys():
		var v: Variant = joints[j]
		if not (v is Dictionary) or (mode == "undriven" and drives.has(String(j))):
			continue
		var b := sk.find_bone(String(j))
		if b < 0:
			continue
		var q := sk.get_bone_pose_rotation(b)
		if v.has("C"):
			q = q.slerp(v["C"], float(v["w"]))
		elif v.has("mul"):
			q = q * (v["mul"] as Quaternion)
		elif v.has("pre"):
			q = (v["pre"] as Quaternion) * q
		sk.set_bone_pose_rotation(b, q.normalized())


func _override_material(n: Node, m: Material) -> void:
	if n is MeshInstance3D:
		(n as MeshInstance3D).material_override = m
	for c in n.get_children():
		_override_material(c, m)


# ---- อนุภาค ----

func _puff(p: Vector3, v: Vector3, r0: float, r1: float, life: float, c: Color, e: Color, add: bool) -> void:
	if level == "min" or _puffs.size() >= int(LV[level]["puffs"]):
		return
	_puffs.append({"p": p, "v": v, "r0": r0, "r1": r1, "life": life, "t": 0.0, "c": c, "e": e, "add": add})
	stats["peak_puffs"] = maxi(int(stats["peak_puffs"]), _puffs.size())
	_wake()


func _spark_burst(p: Vector3, c: Color, n: int, spd: float) -> void:
	var cap: int = LV[level]["pt"]
	n = int(n * (1.0 if level == "hi" else 0.7 if level == "mid" else 0.3))
	for i in n:
		if _sparks.size() >= cap:
			return
		var d := Vector3(_rng.randf_range(-1, 1), _rng.randf_range(0.2, 1.2), _rng.randf_range(-1, 1)).normalized()
		_sparks.append({"p": p, "v": d * spd * _rng.randf_range(0.4, 1.0), "life": _rng.randf_range(0.25, 0.5), "t": 0.0, "c": c})
	stats["peak_sparks"] = maxi(int(stats["peak_sparks"]), _sparks.size())


# ---- เวลา ----

func _at(t: float, cb: Callable) -> void:
	var i := _q.size()
	while i > 0 and float(_q[i - 1][0]) > t:
		i -= 1
	_q.insert(i, [t, cb])
	_wake()


func _wake() -> void:
	if not is_processing() and active():
		set_process(true)


func _process(delta: float) -> void:
	var dt := delta * time_scale
	_t += dt
	while not _q.is_empty() and float(_q[0][0]) <= _t:
		var item: Array = _q.pop_front()
		(item[1] as Callable).call()
	for uid in _actors.keys():
		var a: Dictionary = _actors[uid]
		var el := _t - float(a["t0"])
		if el > float(a["dur"]):
			_end_actor(a)
			_actors.erase(uid)
		else:
			_drive_actor(a, el)
	var i := 0
	while i < _shots.size():
		var s: Dictionary = _shots[i]
		s["t"] = float(s["t"]) + dt
		if float(s["t"]) >= float(s["dur"]):
			_shots.remove_at(i)
			(s["cb"] as Callable).call()
		else:
			i += 1
	_age(_beams, dt)
	for p: Dictionary in _puffs:
		p["p"] = (p["p"] as Vector3) + (p["v"] as Vector3) * dt
	_age(_puffs, dt)
	for s2: Dictionary in _sparks:
		var v: Vector3 = s2["v"]
		v.y -= 9.8 * dt
		s2["v"] = v
		s2["p"] = (s2["p"] as Vector3) + v * dt
	_age(_sparks, dt)
	i = 0
	while i < _falling.size():
		var f: Dictionary = _falling[i]
		f["t"] = float(f["t"]) + dt
		var k := clampf(float(f["t"]) / float(f["dur"]), 0.0, 1.0)
		k = k * k
		var base: Transform3D = f["base"]
		var xf := base
		xf.basis = Basis(f["axis"], float(f["tip"]) * k) * base.basis
		xf.origin = base.origin - UP * float(f["sink"]) * k
		(f["mm"] as MultiMesh).set_instance_transform(int(f["slot"]), xf)
		if k >= 1.0:
			_falling.remove_at(i)
		else:
			i += 1
	if _shake > 0.0:
		_shake = maxf(0.0, _shake - dt * 1.2)
		_cam_offset(_rng.randf_range(-1, 1) * _shake * 0.4, _rng.randf_range(-1, 1) * _shake * 0.4)
	_draw_fx()
	if not active():
		_cam_offset(0.0, 0.0)
		if _mesh != null:
			_mesh.clear_surfaces()
		if _mi != null:
			_mi.visible = false
		set_process(false)


func _age(list: Array, dt: float) -> void:
	var i := 0
	while i < list.size():
		var d: Dictionary = list[i]
		d["t"] = float(d["t"]) + dt
		if float(d["t"]) >= float(d["life"]):
			list.remove_at(i)
		else:
			i += 1


func _cam_offset(h: float, v: float) -> void:
	if table == null:
		return
	var rig: Node = table.get("camera_rig")
	var cam := rig.get_node_or_null(^"Camera3D") as Camera3D if rig != null else null
	if cam != null:
		cam.h_offset = h
		cam.v_offset = v


# ---- วาด (ImmediateMesh เดียว: เส้น/ลูกไฟแบบบวกแสง + ควันแบบผสม) ----

func _ensure_mesh() -> void:
	if _mesh != null:
		return
	_mesh = ImmediateMesh.new()
	_mi = MeshInstance3D.new()
	_mi.name = "FxMesh"
	_mi.mesh = _mesh
	_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_mi.extra_cull_margin = 16384.0
	add_child(_mi)
	_mat_add = _material(BaseMaterial3D.BLEND_MODE_ADD)
	_mat_mix = _material(BaseMaterial3D.BLEND_MODE_MIX)


static func _material(blend: int) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.vertex_color_use_as_albedo = true
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = blend
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	m.no_depth_test = false
	return m


func _draw_fx() -> void:
	_ensure_mesh()
	_mesh.clear_surfaces()
	var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
	if cam == null:
		_mi.visible = false
		return
	var eye := cam.global_position
	var right := cam.global_basis.x
	var up := cam.global_basis.y
	var any := false
	if level == "min":
		# เส้นกระสุนเส้นเดียว (ไม่มีอนุภาค)
		if not _shots.is_empty() or not _beams.is_empty():
			_mesh.surface_begin(Mesh.PRIMITIVE_LINES, _mat_add)
			for s: Dictionary in _shots:
				var seg := _seg(s)
				_mesh.surface_set_color(s["core"])
				_mesh.surface_add_vertex(seg[0])
				_mesh.surface_add_vertex(seg[1])
			for b: Dictionary in _beams:
				_mesh.surface_set_color(b["core"])
				_mesh.surface_add_vertex(b["a"])
				_mesh.surface_add_vertex(b["b"])
			_mesh.surface_end()
			any = true
		_mi.visible = any
		return
	var glow: bool = LV[level]["glow"]
	var adds := 0
	for p: Dictionary in _puffs:
		if p["add"]:
			adds += 1
	if not _shots.is_empty() or not _beams.is_empty() or not _sparks.is_empty() or adds > 0:
		_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES, _mat_add)
		for s: Dictionary in _shots:
			var seg := _seg(s)
			var w := float(s["w"])
			if s["orb"]:
				if glow:
					_fan(seg[1], w * 4.0, s["halo"], Color(s["halo"].r, s["halo"].g, s["halo"].b, 0.0), right, up)
				_fan(seg[1], w * 1.6, s["core"], Color(s["core"].r, s["core"].g, s["core"].b, 0.2), right, up)
			if glow:
				_ribbon(seg[0], seg[1], w * 2.6, Color(s["halo"].r, s["halo"].g, s["halo"].b, 0.0), s["halo"], eye)
			_ribbon(seg[0], seg[1], w, Color(s["core"].r, s["core"].g, s["core"].b, 0.0), s["core"], eye)
		for b: Dictionary in _beams:
			var k := 1.0 - float(b["t"]) / float(b["life"])
			var c: Color = b["core"]
			var h: Color = b["halo"]
			if glow:
				_ribbon(b["a"], b["b"], float(b["w"]) * 3.0, Color(h.r, h.g, h.b, h.a * k), Color(h.r, h.g, h.b, h.a * k), eye)
			_ribbon(b["a"], b["b"], float(b["w"]), Color(c.r, c.g, c.b, k), Color(c.r, c.g, c.b, k), eye)
		for s2: Dictionary in _sparks:
			var k2 := 1.0 - float(s2["t"]) / float(s2["life"])
			var c2: Color = s2["c"]
			var a2: Vector3 = s2["p"]
			_ribbon(a2 - (s2["v"] as Vector3) * 0.035, a2, 0.03, Color(c2.r, c2.g, c2.b, 0.0), Color(c2.r, c2.g, c2.b, k2), eye)
		for p: Dictionary in _puffs:
			if p["add"]:
				_puff_fan(p, right, up)
		_mesh.surface_end()
		any = true
	if adds < _puffs.size():
		_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES, _mat_mix)
		for p: Dictionary in _puffs:
			if not p["add"]:
				_puff_fan(p, right, up)
		_mesh.surface_end()
		any = true
	_mi.visible = any


## [หาง, หัว] ของกระสุนที่บิน (โค้งถ้ามี h)
func _seg(s: Dictionary) -> Array:
	var k := clampf(float(s["t"]) / float(s["dur"]), 0.0, 1.0)
	var a: Vector3 = s["a"]
	var b: Vector3 = s["b"]
	var head := a.lerp(b, k)
	var h := float(s["h"])
	if h > 0.0:
		head.y += 4.0 * h * k * (1.0 - k)
	var d := a.distance_to(b)
	var kt := maxf(0.0, k - float(s["len"]) / maxf(0.01, d))
	var tail := a.lerp(b, kt)
	if h > 0.0:
		tail.y += 4.0 * h * kt * (1.0 - kt)
	return [tail, head]


func _puff_fan(p: Dictionary, right: Vector3, up: Vector3) -> void:
	var k := float(p["t"]) / float(p["life"])
	var r := lerpf(float(p["r0"]), float(p["r1"]), sqrt(k))
	var c: Color = p["c"]
	var e: Color = p["e"]
	c.a *= 1.0 - k
	_fan(p["p"], r, c, e, right, up)


func _fan(p: Vector3, r: float, c: Color, e: Color, right: Vector3, up: Vector3) -> void:
	const N := 8
	for i in N:
		var a0 := TAU * float(i) / N
		var a1 := TAU * float(i + 1) / N
		_mesh.surface_set_color(c)
		_mesh.surface_add_vertex(p)
		_mesh.surface_set_color(e)
		_mesh.surface_add_vertex(p + (right * cos(a0) + up * sin(a0)) * r)
		_mesh.surface_add_vertex(p + (right * cos(a1) + up * sin(a1)) * r)


func _ribbon(a: Vector3, b: Vector3, w: float, ca: Color, cb: Color, eye: Vector3) -> void:
	var side := (b - a).cross(eye - (a + b) * 0.5)
	if side.length_squared() < 1e-10:
		return
	side = side.normalized() * w * 0.5
	_mesh.surface_set_color(ca)
	_mesh.surface_add_vertex(a - side)
	_mesh.surface_add_vertex(a + side)
	_mesh.surface_set_color(cb)
	_mesh.surface_add_vertex(b + side)
	_mesh.surface_set_color(ca)
	_mesh.surface_add_vertex(a - side)
	_mesh.surface_set_color(cb)
	_mesh.surface_add_vertex(b + side)
	_mesh.surface_add_vertex(b - side)


# ---- ช่วย ----

func _snd(kind: StringName, at: Variant = null) -> void:
	var s := get_node_or_null(^"/root/Sfx")
	if s == null or kind == &"":
		return
	if s.has_method("has") and not bool(s.call("has", kind)):
		return
	s.call("play", kind, at)
	stats["sounds"] += 1


func _weapon_snd(pl: Dictionary) -> StringName:
	var kind := str(pl["kind"])
	match kind:
		"bow":
			return &"bow"
		"throw", "hurl":
			return &"throw"
		"flame", "spray", "breath":
			return &"flame"
		"zap", "cast", "gaze", "beam":
			if str(pl["fk"]) == "":
				return &"zap"
	if BattleFxRules.BOLT_GUNS.has(str(pl["gun"])):
		return &"catapult" if str(BattleFxRules.BOLT_GUNS[pl["gun"]]) == "boulder" else &"bolt"
	var s := get_node_or_null(^"/root/Sfx")
	var key := str(pl["fk"]) if str(pl["fk"]) != "" else str(pl["gun"])
	if s != null and s.has_method("weapon_kind"):
		var w: Variant = s.call("weapon_kind", key)
		if str(w) != "":
			return StringName(str(w))
	var fx := BattleFxRules.fxs(str(pl["fk"]))
	if fx.has("snd"):
		return StringName(str(fx["snd"]))
	return &"swing" if kind in ["swing", "swing2", "thrust", "lunge", "bash", "claw", "twin"] else &"shot"


func _height(k: String) -> float:
	if table != null:
		var pool: FigurePool = table.get("figures")
		if pool != null and pool.style == "kit":
			if _manifest.is_empty():
				_manifest = KitLibrary.load_manifest()
			var bb := KitLibrary.bounds(_manifest, k)
			if bb.size.y > 0.0:
				return bb.size.y
	return EggShapes.size_of(k).y


func _kit_of(uid: String) -> String:
	return str((_cache.get(uid, {}) as Dictionary).get("k", ""))


func _alive(uid: String) -> bool:
	return table != null and int(table.call("unit_fig", uid)) >= 0


## ตำแหน่งตอนนี้ของโมเดล (ฟิกเกอร์บนโต๊ะ) ไม่มีแล้ว = ที่จำไว้
func _pos_now(uid: String, fallback: Vector3) -> Vector3:
	var fi := int(table.call("unit_fig", uid)) if table != null else -1
	var pool: FigurePool = table.get("figures") if table != null else null
	if fi >= 0 and pool != null and fi < pool.figures.size():
		return pool.figures[fi].pos
	return fallback


## โมเดลที่ยังอยู่ของหมู่ sid (ตำแหน่งปัจจุบัน)
func _models_of(sid: String, st: BattleState) -> Array:
	var out := []
	var terrain: Node = table.get("terrain")
	for u in st.units:
		if u.sq != sid:
			continue
		var c: Dictionary = _cache.get(u.id, {})
		var x := u.x / 1000.0
		var z := u.z / 1000.0
		out.append({"uid": u.id, "k": u.t, "pos": Vector3(x, float(terrain.call("height_at", x, z)) if terrain != null else 0.0, z),
			"r": EggShapes.base_r(u.t), "h": float(c.get("h", _height(u.t)))})
	return out


## โมเดลของหมู่ tid ก่อนก้าวนี้ (รวมตัวที่เพิ่งตาย)
func _cached_of(tid: String) -> Array:
	var out := []
	for uid in _cache:
		var c: Dictionary = _cache[uid]
		if str(c["sq"]) == tid:
			var d := c.duplicate()
			d["uid"] = uid
			out.append(d)
	return out


func _first_of(sid: String) -> Dictionary:
	for uid in _cache:
		if str(_cache[uid]["sq"]) == sid:
			return _cache[uid]
	return {}


func _nearest(list: Array, p: Vector3) -> Dictionary:
	var best: Dictionary = list[0]
	var bd := INF
	for c: Dictionary in list:
		var d := (c["pos"] as Vector3).distance_squared_to(p)
		if d < bd:
			bd = d
			best = c
	return best
