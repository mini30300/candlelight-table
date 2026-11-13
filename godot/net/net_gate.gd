class_name NetGate
extends RefCounted
## ประตูรุ่นของห้อง LAN (NET_SPEC §3 และ §10): ล้วน static ไม่มีสถานะ ไม่มีข้อความไทย
## ทุกเครื่องในห้องต้องมี APP_VER, RULES_V, DATA_HASH และ NetProto.VERSION เท่ากัน (กติกาข้อ 5)
## args ของเหตุผล: host = ค่าของเจ้าห้อง, mine = ค่าของเครื่องที่ขอเข้า

## คีย์ของประตู ตามลำดับที่ตรวจ (อันแรกที่ไม่ผ่านชนะ)
const KEYS := ["not_lan", "wrong_game", "wrong_net", "wrong_app", "wrong_rules", "full", "closing"]
## คีย์ความล้มเหลวในเครื่อง (ไม่ผ่านประตู)
const LOCAL_KEYS := ["port_busy", "no_lan", "bad_ip", "timeout", "host_left", "bad_message", "reconnect_failed"]
const DATA_SHORT := 12


## ตรวจ HELLO ของเครื่องที่ขอเข้า: {key, args} (key "" = ผ่าน)
## closing: ส่ง true ตอนเจ้าห้องกำลังปิดห้อง · known_nid: nid นี้มีที่นั่งค้างอยู่ (ต่อใหม่) จึงไม่นับว่าเต็ม
static func check_hello(hello: Dictionary, n_members: int, max_players: int, remote_ip: String, known_nid: bool,
		closing: bool = false) -> Dictionary:
	if not is_private(remote_ip):
		return _no("not_lan")
	if hello.is_empty() or str(hello.get("g", "")) != NetProto.GAME or typeof(hello.get("g")) != TYPE_STRING:
		return _no("wrong_game")
	var np: Variant = hello.get("np")
	if typeof(np) != TYPE_INT or int(np) != NetProto.VERSION:
		return _no("wrong_net", {"host": NetProto.VERSION, "mine": int(np) if typeof(np) == TYPE_INT else -1})
	var app: Variant = hello.get("app")
	if typeof(app) != TYPE_STRING or str(app) != Version.APP_VER:
		return _no("wrong_app", {"host": Version.APP_VER, "mine": str(app) if typeof(app) == TYPE_STRING else ""})
	var rules: Variant = hello.get("rules")
	var data: Variant = hello.get("data")
	if typeof(rules) != TYPE_INT or int(rules) != Version.RULES_V or typeof(data) != TYPE_STRING \
			or str(data) != Version.DATA_HASH:
		return _no("wrong_rules", {"host": Version.RULES_V, "mine": int(rules) if typeof(rules) == TYPE_INT else -1})
	# ชื่อและ nid ต้องเป็นรูปที่ถูก (ชื่อหลังทำความสะอาดยาว 1-20, nid ฐานสิบหก 16 ตัว)
	var nm: Variant = hello.get("nm")
	var nid: Variant = hello.get("nid")
	if typeof(nm) != TYPE_STRING or NetProto.clean_name(nm).is_empty() or typeof(nid) != TYPE_STRING \
			or not NetProto.is_hex(nid, 16):
		return _no("wrong_game")
	if not known_nid and n_members >= max_players:
		return _no("full", {"n": n_members, "max": max_players})
	if closing:
		return _no("closing")
	return {"key": "", "args": {}}


## ตรวจบีคอนของห้องที่พบ (ฝั่งคนหาห้อง): {key, args} เหมือน check_hello
static func check_beacon(b: Dictionary) -> Dictionary:
	if str(b.get("g", NetProto.GAME)) != NetProto.GAME:
		return _no("wrong_game")
	if int(b.get("np", -1)) != NetProto.VERSION:
		return _no("wrong_net", {"host": int(b.get("np", -1)), "mine": NetProto.VERSION})
	if str(b.get("app", "")) != Version.APP_VER:
		return _no("wrong_app", {"host": str(b.get("app", "")), "mine": Version.APP_VER})
	if int(b.get("rules", -1)) != Version.RULES_V or str(b.get("data", "")) != Version.DATA_HASH.left(DATA_SHORT):
		return _no("wrong_rules", {"host": int(b.get("rules", -1)), "mine": Version.RULES_V})
	if int(b.get("n", 0)) >= int(b.get("max", 0)):
		return _no("full", {"n": int(b.get("n", 0)), "max": int(b.get("max", 0))})
	return {"key": "", "args": {}}


static func _no(key: String, args: Dictionary = {}) -> Dictionary:
	return {"key": key, "args": args}


## ที่อยู่ในวงส่วนตัว: IPv4 10/8 172.16/12 192.168/16 169.254/16 127/8; IPv6 ::1 fe80::/10 fc00::/7
## (และ IPv4 ที่ห่อใน ::ffff:) · 100.64/10 ของผู้ให้บริการไม่นับ · รูปผิด = ไม่ใช่
static func is_private(ip: String) -> bool:
	var s := ip.strip_edges().to_lower()
	if s.begins_with("::ffff:") and s.count(".") == 3:
		s = s.trim_prefix("::ffff:")
	var v4 := _v4(s)
	if v4.size() == 4:
		var a := v4[0]
		var b := v4[1]
		return a == 10 or a == 127 or (a == 172 and b >= 16 and b <= 31) or (a == 192 and b == 168) \
			or (a == 169 and b == 254)
	if not s.contains(":") or not s.is_valid_ip_address():
		return false
	if s == "::1":
		return true
	var head := s.get_slice(":", 0)
	if head.is_empty() or head.length() > 4 or not head.is_valid_hex_number():
		return false
	var w := head.hex_to_int()
	return (w & 0xFFC0) == 0xFE80 or (w & 0xFE00) == 0xFC00


## IPv4 จุดสี่ช่องเป็นเลข 0-255 (ตัวเลขล้วน 1-3 หลัก); ผิดได้อาร์เรย์ว่าง
static func _v4(s: String) -> PackedInt32Array:
	var parts := s.split(".")
	if parts.size() != 4:
		return PackedInt32Array()
	var out := PackedInt32Array()
	for p: String in parts:
		if p.is_empty() or p.length() > 3:
			return PackedInt32Array()
		for i: int in p.length():
			var c := p.unicode_at(i)
			if c < 48 or c > 57:
				return PackedInt32Array()
		var n := p.to_int()
		if n > 255:
			return PackedInt32Array()
		out.append(n)
	return out


## ข้อความในช่อง IP: IPv4 จุดสี่ช่อง กับ :พอร์ต ได้ (1-65535) ไม่รับชื่อโฮสต์ (จึงไม่มี DNS จากข้อความที่พิมพ์)
## คืน {ip, port} (port 0 = ใช้ค่าตั้งต้น) หรือ {}
static func parse_ip(text: String) -> Dictionary:
	var s := text.strip_edges()
	var port := 0
	if s.count(":") == 1:
		var ps := s.get_slice(":", 1)
		s = s.get_slice(":", 0)
		if ps.is_empty() or ps.length() > 5:
			return {}
		for i: int in ps.length():
			var c := ps.unicode_at(i)
			if c < 48 or c > 57:
				return {}
		port = ps.to_int()
		if port < 1 or port > 65535:
			return {}
	elif s.contains(":"):
		return {}
	var v4 := _v4(s)
	if v4.size() != 4:
		return {}
	return {"ip": "%d.%d.%d.%d" % [v4[0], v4[1], v4[2], v4[3]], "port": port}
