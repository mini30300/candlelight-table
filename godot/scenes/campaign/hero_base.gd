extends Node3D
## ฐานร่วมของฉากโชว์ในตัว 4 ฉาก (CAMPAIGN_SPEC §3): เวลาในฉาก t เดินด้วย _process เฉพาะตอน active และฉากนั้นขยับได้
## ตัวละครเดินท่าเอง (manual) ฉากเรียก step ทีละเฟรม จึงหยุดหมดเมื่อ set_active(false) · ภาพนิ่ง (โปสเตอร์) = seek(poster_t())
## seek เดินเวลาจาก 0 ทีละ 1/30 วิ: ท่าเดียวกันทุกครั้ง ทุกเครื่อง · ไม่มี class_name (สัญญาฉาก) · ไม่แตะ App / Net / ไฟล์

var level := "mid"
var active := false
var camera: Camera3D
var aspect := 16.0 / 9.0
var sel: Dictionary = {}
## เวลาในฉาก (วิ)
var t := 0.0
## ตัวที่ฉากเดินท่าให้ (step)
var figs: Array[Node3D] = []


func setup(ctx: Dictionary) -> void:
	level = str(ctx.get("level", "mid"))
	if not ["hi", "mid", "lo", "min"].has(level):
		level = "mid"
	var s: Variant = ctx.get("sel")
	sel = s if s is Dictionary else Figures.selected()
	aspect = maxf(float(ctx.get("aspect", 16.0 / 9.0)), 0.2)
	set_process(false)
	_build()
	_layout()
	seek(poster_t())


## เล่น/หยุด: เล่นแล้วเริ่มท่าของฉากใหม่จากต้น (start_t) · หยุด = ไม่มีงานต่อเฟรมเลย
func set_active(on: bool) -> void:
	if on == active:
		return
	active = on
	var run := on and animated()
	if run:
		seek(start_t())
	set_process(run)
	_on_active(on)


func set_aspect(a: float) -> void:
	aspect = maxf(a, 0.2)
	_layout()


## ฉากนี้ขยับไหมในระดับนี้ (เวทีใช้: ไม่ขยับ = วาดครั้งเดียวแม้เลือกอยู่)
func animated() -> bool:
	return level != "min" and _moves()


## เดินเวลาไปที่ time จาก 0 (ท่าเดียวกันทุกครั้ง)
func seek(time: float) -> void:
	_reset()
	t = 0.0
	var guard := 0
	while t < time - 0.0001 and guard < 2000:
		_advance(minf(HeroKit.STEP, time - t))
		guard += 1
	_advance(0.0)


func _process(delta: float) -> void:
	_advance(minf(delta, 0.1))


func _advance(dt: float) -> void:
	t += dt
	_tick(dt)
	for f in figs:
		if is_instance_valid(f) and f.has_method("step"):
			f.call("step", dt)


# ---- ให้ฉากลูกเขียนทับ ----

func _build() -> void:
	camera = HeroKit.camera(self, 30.0)


func _layout() -> void:
	pass


func _reset() -> void:
	pass


func _tick(_dt: float) -> void:
	pass


func _on_active(_on: bool) -> void:
	pass


func _moves() -> bool:
	return level == "hi" or level == "mid"


func poster_t() -> float:
	return 0.0


func start_t() -> float:
	return 0.0
