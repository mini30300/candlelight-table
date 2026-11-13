class_name NetDiscovery
extends RefCounted
## หาห้องใน Wi-Fi เดียวกัน (NET_SPEC §1.4): คนหาห้องกระจายคำถาม UDP ทุก 1 วินาที เจ้าห้องตอบบีคอนกลับไปที่ผู้ถาม
## (n ในคำถามเป็นแค่ข้อมูล ไม่ได้ตรวจ: บีคอนตอบไปที่ IP:พอร์ตของผู้ถามอยู่แล้ว) · ไม่เกิน 16 แถว
## Net เรียก poll ด้วยตัวจับเวลาของมันเอง (ไม่มี _process) · แพ็กเก็ตเป็น JSON ไม่เกิน 512 ไบต์ อย่างอื่นทิ้งเงียบ ๆ
## ตอบ/รับเฉพาะที่อยู่ในวงส่วนตัว (NetGate.is_private) · แถวเดียวต่อโทเค็นเจ้าห้อง เก็บ IP ที่ไม่ใช่ loopback ก่อน

const MAX_BYTES := 512
const QUERY_EVERY_MS := 1000
const EXPIRE_MS := 4000
const WARN_EVERY_MS := 60000
## แถวห้องไม่เกินนี้ (เครื่องที่ส่งบีคอนโทเค็นสุ่มรัว ๆ ไม่ทำให้รายการยาวจนมือถือค้าง)
const MAX_ROWS := 16
const STS := ["deck", "setup", "battle"]

enum Mode { OFF, HOST, FIND }

var _udp: PacketPeerUDP = null
var _mode := Mode.OFF
var _beacon := Callable()
var _port := 0
var _probe := PackedStringArray()
var _next_query := 0
var _rows := {}          # โทเค็น -> แถว (มี seen = เวลาที่เห็นล่าสุด)
var _nonce := ""
var _warn_at := -WARN_EVERY_MS
## ส่งคำถามไปที่อยู่กระจายของวง /24 ของเครื่องด้วย (Windows หลายการ์ดเครือข่ายส่ง 255.255.255.255 ออกการ์ดเดียว)
var subnet_broadcast := true


## เจ้าห้อง: ฟังคำถามที่พอร์ตค้นหา; beacon.call() คืนไบต์บีคอนปัจจุบัน · ผูกพอร์ตไม่ได้ = false (เปิดห้องต่อได้ด้วย IP)
func start_host(port: int, beacon: Callable) -> bool:
	stop()
	var u := PacketPeerUDP.new()
	u.set_broadcast_enabled(true)   # Android: ขอ multicast lock ให้รับแพ็กเก็ตกระจายได้
	if u.bind(port, "0.0.0.0") != OK:   # IPv4 เท่านั้น (รอบนี้ไม่มี IPv6)
		return false
	_udp = u
	_mode = Mode.HOST
	_beacon = beacon
	return true


## คนหาห้อง: ผูกพอร์ตว่าง แล้วถามไปที่ 255.255.255.255:port และทุกที่อยู่ใน probe
func start_find(port: int, probe: PackedStringArray) -> bool:
	stop()
	var u := PacketPeerUDP.new()
	u.set_broadcast_enabled(true)
	if u.bind(0, "0.0.0.0") != OK:
		return false
	_udp = u
	_mode = Mode.FIND
	_port = port
	_probe = probe
	_next_query = 0
	_nonce = "%08x" % (randi() & 0x7FFFFFFF)
	return true


func stop() -> void:
	if _udp != null:
		_udp.close()
	_udp = null
	_mode = Mode.OFF
	_beacon = Callable()
	_rows.clear()


func is_on() -> bool:
	return _udp != null


func is_host() -> bool:
	return _mode == Mode.HOST


## อ่านแพ็กเก็ตที่ค้าง ส่งคำถามเมื่อถึงเวลา ลบแถวที่เงียบเกิน 4 วินาที · true เมื่อรายการห้องเปลี่ยน
func poll(now_ms: int) -> bool:
	if _udp == null:
		return false
	var changed := false
	if _mode == Mode.FIND and now_ms >= _next_query:
		_next_query = now_ms + QUERY_EVERY_MS
		_send_queries()
	var guard := 64
	while _udp.get_available_packet_count() > 0 and guard > 0:
		guard -= 1
		var bytes := _udp.get_packet()
		var ip := _udp.get_packet_ip()
		var port := _udp.get_packet_port()
		var p := parse(bytes, ip)
		if p.is_empty():
			_warn_junk(now_ms, ip)
			continue
		if _mode == Mode.HOST and p["k"] == "q" and _beacon.is_valid():
			var reply: PackedByteArray = _beacon.call()
			if not reply.is_empty() and reply.size() <= MAX_BYTES:
				_udp.set_dest_address(ip, port)
				_udp.put_packet(reply)
		elif _mode == Mode.FIND and p["k"] == "b":
			changed = _upsert(p, now_ms) or changed
	for t: String in _rows.keys():
		if now_ms - int(_rows[t]["seen"]) > EXPIRE_MS:
			_rows.erase(t)
			changed = true
	return changed


func _send_queries() -> void:
	var q := JSON.stringify({"g": NetProto.GAME, "k": "q", "np": NetProto.VERSION, "n": _nonce}).to_utf8_buffer()
	var dests := PackedStringArray(["255.255.255.255"])
	if subnet_broadcast:
		for ip: String in IP.get_local_addresses():
			var parts := ip.split(".")
			if parts.size() == 4 and NetGate.is_private(ip) and not ip.begins_with("127."):
				var b := "%s.%s.%s.255" % [parts[0], parts[1], parts[2]]
				if not dests.has(b):
					dests.append(b)
	for ip: String in _probe:
		if not dests.has(ip):
			dests.append(ip)
	for ip: String in dests:
		if _udp.set_dest_address(ip, _port) == OK:
			_udp.put_packet(q)   # เครือข่ายที่ส่งไม่ได้ (เช่นไม่มีเส้นทางกระจาย) ข้ามไปเงียบ ๆ


func _upsert(p: Dictionary, now_ms: int) -> bool:
	var t: String = p["t"]
	var row := {"t": t, "ip": p["ip"], "port": p["port"], "nm": p["nm"], "n": p["n"], "max": p["max"],
		"st": p["st"], "app": p["app"], "rules": p["rules"], "ok": p["ok"], "why": p["why"], "args": p["args"]}
	if _rows.has(t):
		var old: Dictionary = _rows[t]
		# โทเค็นเดียวกันตอบมาจาก loopback และ IP ในวง: เก็บ IP ที่ไม่ใช่ loopback
		if _loop(str(row["ip"])) and not _loop(str(old["ip"])):
			row["ip"] = old["ip"]
		var same := true
		for k: String in row:
			if old.get(k) != row[k]:
				same = false
				break
		row["seen"] = now_ms
		_rows[t] = row
		return not same
	if _rows.size() >= MAX_ROWS:
		return false
	row["seen"] = now_ms
	_rows[t] = row
	return true


static func _loop(ip: String) -> bool:
	return ip.begins_with("127.") or ip == "::1"


func _warn_junk(now_ms: int, ip: String) -> void:
	if now_ms - _warn_at < WARN_EVERY_MS:
		return
	_warn_at = now_ms
	var ml := Engine.get_main_loop()
	var lg: Node = (ml as SceneTree).root.get_node_or_null(^"/root/Log") if ml is SceneTree else null
	if lg != null:
		lg.call("warn", "net: ignored a discovery packet from %s" % ip)


## ห้องที่พบ เรียงตามชื่อแล้วโทเค็น: [{t, ip, port, nm, n, max, st, app, rules, ok, why, args}]
func found() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for t: String in _rows:
		var r: Dictionary = (_rows[t] as Dictionary).duplicate(true)
		r.erase("seen")
		out.append(r)
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if str(a["nm"]) != str(b["nm"]):
			return str(a["nm"]) < str(b["nm"])
		return str(a["t"]) < str(b["t"]))
	return out


## บีคอนเป็นไบต์จาก info {app, rules, data, port, nm, n, max, st, t}; data ตัดเหลือ 12 ตัว · เกิน 512 ไบต์ได้อาร์เรย์ว่าง
static func make_beacon(info: Dictionary) -> PackedByteArray:
	var d := {"g": NetProto.GAME, "k": "b", "np": NetProto.VERSION, "app": str(info.get("app", Version.APP_VER)),
		"rules": int(info.get("rules", Version.RULES_V)),
		"data": str(info.get("data", Version.DATA_HASH)).left(NetGate.DATA_SHORT),
		"port": int(info.get("port", 0)), "nm": NetProto.clean_name(str(info.get("nm", ""))),
		"n": int(info.get("n", 1)), "max": int(info.get("max", 6)), "st": str(info.get("st", "deck")),
		"t": str(info.get("t", ""))}
	var out := JSON.stringify(d).to_utf8_buffer()
	return out if out.size() <= MAX_BYTES else PackedByteArray()


## แพ็กเก็ตค้นหาเป็นข้อมูล: คำถาม {k: "q", n} หรือบีคอน {k: "b", t, ip, port, nm, n, max, st, app, rules, data, np,
## ok, why, args}; ขยะ ใหญ่เกิน ผิดเกม หรือมาจากนอกวงส่วนตัว ได้ {}
static func parse(bytes: PackedByteArray, ip: String) -> Dictionary:
	if bytes.is_empty() or bytes.size() > MAX_BYTES or not NetGate.is_private(ip):
		return {}
	var text := bytes.get_string_from_utf8()
	if text.is_empty() or not text.begins_with("{"):
		return {}
	var v: Variant = JSON.parse_string(text)
	if typeof(v) != TYPE_DICTIONARY:
		return {}
	var d: Dictionary = v
	if d.get("g") != NetProto.GAME:
		return {}
	if d.get("k") == "q":
		if typeof(d.get("n")) != TYPE_STRING or str(d["n"]).length() > 16:
			return {}
		return {"k": "q", "n": str(d["n"])}
	if d.get("k") != "b":
		return {}
	# ตัวเลขจาก JSON เป็น float: แปลงเป็น int และต้องเป็นจำนวนเต็มในช่วง
	var np := _int(d.get("np"), 0, 65535)
	var rules := _int(d.get("rules"), 0, 100000000)
	var port := _int(d.get("port"), 1, 65535)
	var n := _int(d.get("n"), 0, 64)
	var mx := _int(d.get("max"), 1, 64)
	for x: int in [np, rules, port, n, mx]:
		if x < 0:
			return {}
	for k: String in ["app", "data", "nm", "st", "t"]:
		if typeof(d.get(k)) != TYPE_STRING or str(d[k]).length() > 64:
			return {}
	var t := str(d["t"])
	if t.is_empty() or t.length() > 16 or not STS.has(str(d["st"])):
		return {}
	var b := {"k": "b", "t": t, "ip": ip, "port": port, "nm": NetProto.clean_name(str(d["nm"])), "n": n, "max": mx,
		"st": str(d["st"]), "app": str(d["app"]), "rules": rules, "data": str(d["data"]), "np": np}
	var g := NetGate.check_beacon(b)
	b["ok"] = g["key"] == ""
	b["why"] = g["key"]
	b["args"] = g["args"]
	return b


## เลขจาก JSON เป็น int ในช่วง [lo, hi]; ไม่ใช่เลข มีเศษ หรือนอกช่วง ได้ -1
static func _int(v: Variant, lo: int, hi: int) -> int:
	if typeof(v) == TYPE_INT:
		return int(v) if int(v) >= lo and int(v) <= hi else -1
	if typeof(v) != TYPE_FLOAT:
		return -1
	var f: float = v
	if f != floorf(f) or f < lo or f > hi:
		return -1
	return int(f)
