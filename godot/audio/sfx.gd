extends Node
## Sfx (autoload): เสียงเอฟเฟกต์จากหน้าเก่า (SND ของ battle-table.html) อัดเป็น WAV ด้วย tools/bake_sfx.js
## ชื่อเสียง = ชื่อใน DEF ของหน้าเก่าตรงตัว (assets/sfx/sfx.json) · หนึ่งชนิดมีหลายเทค สุ่มเล่น ยิงรัวแล้วไม่ซ้ำเสียงเดียว
## กันเสียงถี่: ชนิดเดียวกันห่างกันอย่างน้อย gap มิลลิวิ และเล่นพร้อมกันไม่เกิน MAX_VOICES เสียง (เหมือนหน้าเก่า)
## เสียงเป็นภาพอย่างเดียว: สุ่มแบบไม่มีเมล็ดได้ ห้ามป้อนค่ากลับเข้ากติกา
## ไดรเวอร์เสียง Dummy (เทส headless): ไม่สร้างตัวเล่นเลย แต่ยังนับ gap / จำนวนเสียงเหมือนเดิม ให้เทสตรวจได้
## ปุ่มทุกปุ่มในแอปมีเสียง "ui" ตอนกด (ต่อที่ต้นไม้ครั้งเดียว ไม่ต้องใส่ทีละหน้า)

const MANIFEST := "res://assets/sfx/sfx.json"
const DIR := "res://assets/sfx/"
const MAX_VOICES := 22
const BUSES: PackedStringArray = ["Effects", "Music", "UI"]
const POOL_2D := 8
const POOL_3D := 14

## เทสบังคับเวลาได้ (มิลลิวิ; -1 = นาฬิกาจริง)
var now_override := -1
## true = ไม่มีลำโพง (ไดรเวอร์ Dummy) เล่นเงียบ ๆ
var quiet := false
## ระยะ (เมตร) ที่เสียงสามมิติยังดังเต็ม
var unit_size_3d := 10.0

var kinds: Dictionary = {}          # ชนิด → {gap, v, h, files, len}
var fxs: Dictionary = {}            # ชนิดเอฟเฟกต์อาวุธ → {snd, melee}
var fx_gun: Dictionary = {}         # ปืน → ชนิดเอฟเฟกต์
var fx_snd: Dictionary = {}         # เอฟเฟกต์ → เสียง
var lz_snd: Dictionary = {}         # ปืนเสียงแสง
var heat: Dictionary = {}           # น้ำหนักความดุของเพลง
var stats := {"n": 0, "drop": 0, "by": {}, "ask": {}}

var _streams: Dictionary = {}       # ชนิด → Array[AudioStream] (โหลดเมื่อใช้ครั้งแรก)
var _last: Dictionary = {}          # ชนิด → เวลาเล่นล่าสุด (ms)
var _last_take: Dictionary = {}
var _voices: Array[int] = []        # เวลาที่แต่ละเสียงจบ (ms)
var _pool2: Array[AudioStreamPlayer] = []
var _pool3: Array[AudioStreamPlayer3D] = []
var _loops: Dictionary = {}         # id → {player, kind}
var _loop_id := 0


func _ready() -> void:
	quiet = AudioServer.get_driver_name() == "Dummy" and Engine.get_write_movie_path() == ""   # Movie Maker ใช้ Dummy แต่อัดเสียงได้
	process_mode = Node.PROCESS_MODE_ALWAYS
	ensure_buses()
	load_manifest()
	apply_settings()
	get_tree().node_added.connect(_on_node_added)


## อ่าน sfx.json (ไม่มีไฟล์ = ยังไม่ได้อัดเสียง: ทุกอย่างเงียบ ไม่พัง)
func load_manifest(path: String = MANIFEST) -> bool:
	kinds = {}
	_streams = {}
	if not FileAccess.file_exists(path):
		return false
	var m: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not m is Dictionary:
		push_warning("sfx: cannot parse " + path)
		return false
	kinds = (m as Dictionary).get("kinds", {})
	fxs = (m as Dictionary).get("fxs", {})
	fx_gun = (m as Dictionary).get("fx_gun", {})
	fx_snd = (m as Dictionary).get("fx_snd", {})
	heat = (m as Dictionary).get("heat", {})
	lz_snd = {}
	for g: Variant in (m as Dictionary).get("lz_snd", []):
		lz_snd[str(g)] = true
	return true


## ช่องเสียง Master / Effects / Music / UI (มีในไฟล์ audio/bus_layout.tres แล้ว; ไม่มีก็สร้าง)
static func ensure_buses() -> void:
	for b in BUSES:
		if AudioServer.get_bus_index(b) < 0:
			AudioServer.add_bus()
			var i := AudioServer.bus_count - 1
			AudioServer.set_bus_name(i, b)
			AudioServer.set_bus_send(i, &"Master")


## ความดังจากตั้งค่าของ App: เสียงเอฟเฟกต์ เพลง และปิดเสียงทั้งหมด
func apply_settings() -> void:
	var app := get_node_or_null(^"/root/App")
	var fx := 0.8
	var mus := 0.6
	var on := true
	if app != null:
		fx = float(app.get("sfx_vol"))
		mus = float(app.get("mus_vol"))
		on = bool(app.get("snd"))
	_set_bus("Effects", fx)
	_set_bus("UI", fx)
	_set_bus("Music", mus)
	AudioServer.set_bus_mute(0, not on)


func _set_bus(name: String, v: float) -> void:
	var i := AudioServer.get_bus_index(name)
	if i < 0:
		return
	AudioServer.set_bus_mute(i, v <= 0.001)
	AudioServer.set_bus_volume_db(i, linear_to_db(maxf(v, 0.001)))


func has(kind: StringName) -> bool:
	return kinds.has(String(kind))


## เสียงของอาวุธ: ชนิดเอฟเฟกต์ (FXS) → ชื่อเสียง · ชื่อปืน (FX_GUN) → ชนิดเอฟเฟกต์ → ชื่อเสียง
## ปืนแสง (LZ_SND) → laser · เอฟเฟกต์ที่มีเสียงของตัวเอง (FX_SND) · ไม่รู้จัก = &""
func weapon_kind(fx_kind: String) -> StringName:
	if fxs.has(fx_kind):
		return StringName(str((fxs[fx_kind] as Dictionary).get("snd", "")))
	if fx_gun.has(fx_kind) and fxs.has(str(fx_gun[fx_kind])):
		return StringName(str((fxs[str(fx_gun[fx_kind])] as Dictionary).get("snd", "")))
	if lz_snd.has(fx_kind):
		return &"laser"
	if fx_snd.has(fx_kind):
		return StringName(str(fx_snd[fx_kind]))
	return &""


## เล่นเสียงหนึ่งครั้ง · at: จุดในโลก (Vector3, เสียงสามมิติ) หรือ null (ไม่มีทิศ)
## gain คูณความดัง (เหมือน k ของ SND.at) · pitch 1 = ตามเดิม · คืน true เมื่อได้เล่น (หรือจะได้เล่นถ้ามีลำโพง)
func play(kind: StringName, at: Variant = null, gain: float = 1.0, pitch: float = 1.0) -> bool:
	return _play(kind, at, gain, pitch, &"Effects")


## เสียงหน้าจอ (ไม่มีทิศ ช่อง UI)
func play_ui(kind: StringName) -> void:
	_play(kind, null, 1.0, 1.0, &"UI")


func _play(kind: StringName, at: Variant, gain: float, pitch: float, bus: StringName) -> bool:
	var k := String(kind)
	var ask: Dictionary = stats["ask"]
	ask[k] = int(ask.get(k, 0)) + 1
	var music := get_node_or_null(^"/root/Music")
	if music != null and kinds.has(k):
		var h: Variant = (kinds[k] as Dictionary).get("h", k)
		if h != null:
			music.call("heat", StringName(str(h)))   # ความดุของสนามนับแม้ปิดเสียงเอฟเฟกต์ (เหมือนหน้าเก่า)
	if not kinds.has(k) or not _effects_on():
		return false
	var d: Dictionary = kinds[k]
	var now := _now()
	if (_last.has(k) and now - int(_last[k]) < int(d.get("gap", 0))) or live_voices(now) >= MAX_VOICES:
		stats["drop"] = int(stats["drop"]) + 1
		return false
	_last[k] = now
	var take := _pick_take(k, d)
	var lens: Array = d.get("len", [])
	var sec: float = float(lens[take]) if take < lens.size() else 0.5
	_voices.append(now + int(sec * 1000.0 / maxf(pitch, 0.1)) + 1)
	stats["n"] = int(stats["n"]) + 1
	var by: Dictionary = stats["by"]
	by[k] = int(by.get(k, 0)) + 1
	if quiet:
		return true
	var stream := _stream(k, take)
	if stream == null:
		return true
	var db := linear_to_db(maxf(gain, 0.001))
	if at is Vector3:
		var p3 := _free3()
		p3.stream = stream
		p3.global_position = at
		p3.volume_db = db
		p3.pitch_scale = pitch
		p3.play()
	else:
		var p2 := _free2()
		p2.stream = stream
		p2.bus = bus
		p2.volume_db = db
		p2.pitch_scale = pitch
		p2.play()
	return true


## เสียงวนจนกว่าจะสั่งหยุด หรือ owner ออกจากต้นไม้ (เช่นดาบเลื่อยตอนถือ) · คืนเลขไว้ส่ง stop_loop (0 = ไม่ได้เล่น)
func loop(kind: StringName, owner_node: Node, at: Variant = null) -> int:
	var k := String(kind)
	if not kinds.has(k) or owner_node == null:
		return 0
	_loop_id += 1
	var id := _loop_id
	var stop_cb := stop_loop.bind(id)
	var entry := {"kind": k, "player": null, "owner": owner_node, "cb": stop_cb}
	_loops[id] = entry
	owner_node.tree_exiting.connect(stop_cb, CONNECT_ONE_SHOT)
	if quiet:
		return id
	var stream := _stream(k, 0)
	if stream == null:
		return id
	var p: Node
	if at is Vector3:
		var p3 := AudioStreamPlayer3D.new()
		p3.bus = &"Effects"
		p3.unit_size = unit_size_3d
		p3.panning_strength = 0.6
		add_child(p3)
		p3.global_position = at
		p3.stream = stream
		p3.finished.connect(p3.play)
		p3.play()
		p = p3
	else:
		var p2 := AudioStreamPlayer.new()
		p2.bus = &"Effects"
		add_child(p2)
		p2.stream = stream
		p2.finished.connect(p2.play)
		p2.play()
		p = p2
	entry["player"] = p
	return id


func stop_loop(id: int) -> void:
	if not _loops.has(id):
		return
	var e: Dictionary = _loops[id]
	var p: Variant = e.get("player")
	_loops.erase(id)
	# หยุดเองก่อน owner ออก: ถอดสายสัญญาณออก ไม่สะสม
	var o: Variant = e.get("owner")
	if o is Node and is_instance_valid(o) and (o as Node).tree_exiting.is_connected(e["cb"]):
		(o as Node).tree_exiting.disconnect(e["cb"])
	if p is Node and is_instance_valid(p):
		(p as Node).queue_free()


func loop_count() -> int:
	return _loops.size()


## เสียงที่ยังดังอยู่ตอนนี้ (นับจากเวลาจบที่จดไว้ ใช้ได้แม้ไม่มีลำโพง)
func live_voices(now: int = -1) -> int:
	if now < 0:
		now = _now()
	var keep: Array[int] = []
	for e in _voices:
		if e > now:
			keep.append(e)
	_voices = keep
	return _voices.size()


## ล้างตัวนับ (เทส)
func reset() -> void:
	_last = {}
	_voices = []
	stats = {"n": 0, "drop": 0, "by": {}, "ask": {}}


func _effects_on() -> bool:
	var app := get_node_or_null(^"/root/App")
	return app == null or (bool(app.get("snd")) and float(app.get("sfx_vol")) > 0.001)


func _now() -> int:
	return now_override if now_override >= 0 else Time.get_ticks_msec()


func _pick_take(k: String, d: Dictionary) -> int:
	var n: int = (d.get("files", []) as Array).size()
	if n <= 1:
		return 0
	var t := randi() % n          # ภาพ/เสียงล้วน สุ่มไม่มีเมล็ดได้
	if t == int(_last_take.get(k, -1)):
		t = (t + 1) % n
	_last_take[k] = t
	return t


func _stream(k: String, take: int) -> AudioStream:
	if not _streams.has(k):
		var list: Array = []
		for f: Variant in (kinds[k] as Dictionary).get("files", []):
			var path := DIR + str(f)
			list.append(load(path) if ResourceLoader.exists(path) else null)
		_streams[k] = list
	var l: Array = _streams[k]
	return l[take] as AudioStream if take < l.size() else null


func _free2() -> AudioStreamPlayer:
	for p in _pool2:
		if not p.playing:
			return p
	if _pool2.size() < POOL_2D:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_pool2.append(p)
		return p
	var oldest: AudioStreamPlayer = _pool2.pop_front()   # เต็มแล้ว: ใช้ตัวที่เล่นนานที่สุด
	_pool2.append(oldest)
	return oldest


func _free3() -> AudioStreamPlayer3D:
	for p in _pool3:
		if not p.playing:
			return p
	if _pool3.size() < POOL_3D:
		var p := AudioStreamPlayer3D.new()
		p.bus = &"Effects"
		p.unit_size = unit_size_3d
		p.panning_strength = 0.6
		p.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		add_child(p)
		_pool3.append(p)
		return p
	var oldest: AudioStreamPlayer3D = _pool3.pop_front()
	_pool3.append(oldest)
	return oldest


## ปุ่มทุกปุ่มที่เข้ามาในต้นไม้: กดแล้วมีเสียง ui (เหมือนหน้าเก่าที่ฟัง click ของทุก button)
func _on_node_added(n: Node) -> void:
	if n is BaseButton and not (n as BaseButton).pressed.is_connected(_click):
		(n as BaseButton).pressed.connect(_click)


func _click() -> void:
	play_ui(&"ui")
