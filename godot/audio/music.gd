extends Node
## Music (autoload): เพลงของหน้าเก่า อัดเป็นลูปวนต่อเนื่องด้วย tools/bake_sfx.js (assets/sfx/sfx.json → music)
## อารมณ์: menu เพลงเดิมช้า ๆ ของหน้าแรก · deck เพลงใหม่ขั้นเบา (คอรัสกับเบส) · battle เพลงใหม่สามขั้น 1..3
## battle เล่นสามลูปพร้อมกันตรงจังหวะ (คอร์ดตรงกันทุกห้อง) แล้วเปิดดังเฉพาะขั้นที่ใช้: เปลี่ยนขั้นตรงต้นห้องแบบหน้าเก่า
## (ขึ้นได้ทุกสองห้อง ลงทีละขั้นทุกสี่ห้อง) · ความดุของสนามมาจาก Sfx เอง (heat: เสียงตาย บุก ระเบิด จางลงใน 6 วิ)
## set_intensity เป็นพื้นขั้นต่ำ (เช่นรอบสุดท้าย = 1.0 ขั้น 3) · ไดรเวอร์ Dummy: จำสถานะอย่างเดียว ไม่สร้างตัวเล่น
## _process ทำงานเฉพาะตอนอยู่ในการรบ (ดูต้นห้อง) นอกนั้นปิด

const MOODS: PackedStringArray = ["menu", "deck", "battle"]
const LOOP_OF := {"menu": "menu", "deck": "deck"}
const BATTLE: PackedStringArray = ["battle_1", "battle_2", "battle_3"]
const FADE := 1.2
const STEP_FADE := 0.35
const HEAT_FALL := 6.0

var quiet := false
var mood: StringName = &""
var level := 1                      # ขั้นของเพลงรบที่ดังอยู่ (1..3)
var floor_level := 1                # ขั้นต่ำจาก set_intensity
var loops: Dictionary = {}          # ชื่อลูป → {file, bar, ...}
var now_override := -1.0            # เทสบังคับเวลา (วินาที)

var _heat := 0.0
var _heat_t := 0.0
var _heat_last: Dictionary = {}
var _weights: Dictionary = {}
var _players: Dictionary = {}       # ชื่อลูป → AudioStreamPlayer
var _bar := -1


func _ready() -> void:
	quiet = AudioServer.get_driver_name() == "Dummy" and Engine.get_write_movie_path() == ""   # Movie Maker ใช้ Dummy แต่อัดเสียงได้
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_process(false)
	load_manifest()


func load_manifest(path: String = "res://assets/sfx/sfx.json") -> bool:
	loops = {}
	if not FileAccess.file_exists(path):
		return false
	var m: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not m is Dictionary:
		return false
	loops = (m as Dictionary).get("music", {})
	_weights = (m as Dictionary).get("heat", {})
	return true


## เปลี่ยนอารมณ์เพลง (ค่อย ๆ จางข้ามกัน) · &"" หรือชื่อที่ไม่รู้จัก = เงียบ
func set_mood(m: StringName) -> void:
	if m == mood:
		return
	if m != &"" and not MOODS.has(String(m)):
		push_warning("music: unknown mood " + String(m))
		m = &""
	if mood == &"battle":
		reset_battle()             # ออกจากการรบ: นัดถัดไปเริ่มเบา
	mood = m
	_bar = -1
	if m == &"battle":
		level = maxi(level_for(heat_value()), floor_level)
	set_process(m == &"battle" and not quiet)
	if quiet:
		return
	var want: Dictionary = {}
	if m == &"battle":
		for i in BATTLE.size():
			want[BATTLE[i]] = 1.0 if i + 1 == level else 0.0
	elif LOOP_OF.has(String(m)):
		want[LOOP_OF[String(m)]] = 1.0
	# ลูปที่ไม่ใช้แล้วจางออก ลูปใหม่เริ่มจากต้นพร้อมกัน (สามขั้นของการรบตรงจังหวะกัน)
	for n: String in _players.keys():
		if not want.has(n):
			_fade(_players[n] as AudioStreamPlayer, 0.0, FADE, true)
			_players.erase(n)
	for n: String in want:
		var p: AudioStreamPlayer = _players.get(n)
		if p == null:
			p = _make(n)
			if p == null:
				continue
			_players[n] = p
			p.volume_db = -60.0
			p.play()
		_fade(p, float(want[n]), FADE, false)


## พื้นขั้นต่ำของเพลงรบ 0..1 (0 = ตามความดุอย่างเดียว · 0.5 = อย่างน้อยขั้น 2 · 1 = ขั้น 3)
func set_intensity(x: float) -> void:
	floor_level = 1 + clampi(roundi(clampf(x, 0.0, 1.0) * 2.0), 0, 2)


## เริ่มนัดใหม่: ล้างพื้นขั้นและความดุของนัดก่อน (ถ้ากำลังเล่นเพลงรบอยู่ ค่อย ๆ ลงขั้น 1)
func reset_battle() -> void:
	floor_level = 1
	_heat = 0.0
	_heat_last.clear()
	if level == 1:
		return
	level = 1
	if mood != &"battle":
		return
	for i in BATTLE.size():
		var q: AudioStreamPlayer = _players.get(BATTLE[i])
		if q != null:
			_fade(q, 1.0 if i == 0 else 0.0, FADE, false)


func stop() -> void:
	set_mood(&"")


## Sfx เรียกทุกครั้งที่เล่นเสียง: สะสมความดุ (ชนิดเดียวกันนับห่างกันอย่างน้อย 0.25 วิ เพดาน 60)
func heat(kind: StringName) -> void:
	var w := float(_weights.get(String(kind), 0.0))
	if w <= 0.0:
		return
	var now := _now()
	var k := String(kind)
	if _heat_last.has(k) and now - float(_heat_last[k]) < 0.25:
		return
	_heat_last[k] = now
	_heat = minf(60.0, heat_value(now) + w)
	_heat_t = now


func heat_value(now: float = -1.0) -> float:
	if now < 0.0:
		now = _now()
	return _heat * exp(-(now - _heat_t) / HEAT_FALL)


## ขั้นตามความดุ (เกณฑ์ของหน้าเก่า: เกิน 22 ขั้น 3 · เกิน 8 ขั้น 2)
static func level_for(h: float) -> int:
	return 3 if h > 22.0 else 2 if h > 8.0 else 1


## ขั้นถัดไปตอนต้นห้อง bar (กติกาของหน้าเก่า: ขึ้นได้ทุกสองห้อง ลงทีละขั้นทุกสี่ห้อง)
func next_level(bar: int, current: int) -> int:
	var nl := maxi(level_for(heat_value()), floor_level)
	if nl > current and bar % 2 == 0:
		return nl
	if nl < current and bar % 4 == 0:
		return current - 1
	return current


func _process(_delta: float) -> void:
	var p: AudioStreamPlayer = _players.get(BATTLE[0])
	if p == null or not p.playing:
		return
	var bar := int(p.get_playback_position() / float((loops[BATTLE[0]] as Dictionary).get("bar", 2.4)))
	if bar == _bar:
		return
	_bar = bar
	var nl := next_level(bar, level)
	if nl == level:
		return
	level = nl
	for i in BATTLE.size():
		var q: AudioStreamPlayer = _players.get(BATTLE[i])
		if q != null:
			_fade(q, 1.0 if i + 1 == level else 0.0, STEP_FADE, false)


func _make(n: String) -> AudioStreamPlayer:
	if not loops.has(n):
		return null
	var path := "res://assets/sfx/" + str((loops[n] as Dictionary).get("file", ""))
	if not ResourceLoader.exists(path):
		return null
	var p := AudioStreamPlayer.new()
	p.bus = &"Music"
	p.stream = load(path)
	add_child(p)
	return p


func _fade(p: AudioStreamPlayer, to: float, sec: float, free_after: bool) -> void:
	# จางใหม่ทับของเก่า (ทวีนเก่าไม่กลับมาคุมเสียงอีก)
	var old: Variant = p.get_meta(&"fade") if p.has_meta(&"fade") else null
	if old is Tween and (old as Tween).is_valid():
		(old as Tween).kill()
	var t := create_tween()
	p.set_meta(&"fade", t)
	t.tween_property(p, "volume_db", linear_to_db(maxf(to, 0.001)), sec)
	if free_after:
		t.tween_callback(p.queue_free)


func _now() -> float:
	return now_override if now_override >= 0.0 else Time.get_ticks_msec() / 1000.0
