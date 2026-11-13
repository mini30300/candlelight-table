class_name NetSession
extends Node
## Net (autoload): ห้องเล่นกับเพื่อนบน LAN (NET_SPEC §1-§3) เจ้าของซ็อกเก็ตคนเดียวของแอป ไม่รู้เรื่องกติกาหรือหน้าจอ
## เจ้าห้อง = เซิร์ฟเวอร์ ENet (ช่อง 0), เพื่อน = ไคลเอนต์ (ช่อง 1-5) ส่งข้อความไบต์ของ NetProto ด้วย send_bytes ไม่มี RPC
## ตอนออฟไลน์ไม่ทำอะไรเลย: ไม่มีซ็อกเก็ต ไม่มี Timer ไม่ process · ตอนออนไลน์ ENet ถูก poll โดย SceneTree
##   ส่วนการค้นหาห้อง ชีพจร และหมดเวลา ใช้ Timer ลูก 0.25 วินาทีตัวเดียว (เทสเรียก poll() เอง)
## หลายตัวอยู่ในโปรเซสเดียวได้ (เทส): แต่ละตัวใช้ multiplayer ของโหนดตัวเอง ไม่มีสถานะ static
## ไม่มีข้อความไทยในไฟล์นี้: เหตุผลส่งเป็นคีย์ (NetGate.KEYS, LOCAL_KEYS) หน้าจอแปลเอง

signal state_changed(state: StringName)
signal members_changed()
signal found_changed()
## ข้อความที่ตรวจแล้วของชนิด 20-33 (SETUP, CLAIM และของการรบ) และ HB (15) จากสมาชิกช่อง from_slot
signal message(from_slot: int, kind: int, body: Dictionary)
signal pose(slot: int, pose: Dictionary)
signal refused(key: String, args: Dictionary)
signal lost(key: String)
signal reconnected()

const PORTS := {"game": 24680, "disc": 24681}
const MAX_PLAYERS := 6
const NET_BATTLE_LINK := "res://ui/battle/net_battle_link.gd"
const TICK_S := 0.25
const HB_MS := 2000
## สมาชิกที่เงียบเกินนี้ (ไม่มีข้อความเลยแม้ HB) ถือว่าหลุด
const SILENT_MS := 10000
const CONNECT_MS := 5000
const RETRY_MS := 3000
const RECONNECT_MS := 60000
const KEEP_SLOT_MS := 60000
const REFUSE_DROP_MS := 300
## เพดานข้อความต่อวินาทีต่อสมาชิก: ทั่วไป (รวมท่าทาง) และชนิดของการรบ (คำขอ act วิ่งตามจังหวะตอบของเจ้าห้อง)
const RATE_MAX := 60
const RATE_MAX_BATTLE := 600
const RATE_WINDOW_MS := 1000
const CH_MAIN := 0
const CH_POSE := 1
## ชื่อการ์ดเครือข่าย (ขึ้นต้น) ของเน็ตมือถือ/VPN/การ์ดหลอก: ไม่ใช้เป็น IP ของห้อง
const CELL_IFACES: PackedStringArray = ["rmnet", "v4-rmnet", "rev_rmnet", "ccmni", "pdp", "clat", "wwan", "ppp", "tun",
	"dummy", "ipsec", "seth_", "radio"]
## ชื่อการ์ด Wi-Fi/ฮอตสปอต/สายแลน (ขึ้นต้น; ชื่อเล่นของ Windows ด้วย) ขึ้นก่อนในรายการ IP
const LAN_IFACES: PackedStringArray = ["wlan", "swlan", "ap", "wl", "eth", "en", "wi-fi", "wifi", "ethernet"]

var ports: Dictionary = PORTS.duplicate()
var probe: PackedStringArray = []
var cfg_file := "user://net.cfg"
var max_players := MAX_PLAYERS
var hello_extra: Dictionary = {}                   # เทสเท่านั้น
## เทส: false = ไม่สร้าง NetBattleLink ลูก (ตั้งก่อน add_child)
var make_link := true
## เทส: เลื่อนนาฬิกาของตัวนี้ (ms) เพื่อลองชีพจรและหมดเวลาโดยไม่ต้องรอจริง
var clock_skew_ms := 0

var _state: StringName = &"off"
var _finding := false
var _mp: SceneMultiplayer = null
var _peer: ENetMultiplayerPeer = null
var _timer: Timer = null
var _disc: NetDiscovery = null
var _disc_ok := false
var _cfg_loaded := false
var _nm := ""
var _nid := ""
var _slot := -1
var _members := {}             # ช่อง -> {slot, nm, where (String), pick, here}
var _room_st := "deck"
var _mgen := 0
var _host_nm := ""
var _token := ""
var _where := "menu"
var _pick := ""
var _setup_open := false
var _setup_seats: Array = []
var _battle_gen := 0
var _hb_at := 0
var _link: Node = null
var _last_ip := ""
var _screen_held := false      # เปิดจอค้างไว้ตอนออนไลน์ (คืนค่าเดิมตอนออก)
var _screen_was_on := true
var _disc_paused := false      # แอปไปอยู่เบื้องหลัง: ปิดการค้นหาห้องไว้ (คืน multicast lock) เปิดใหม่ตอนกลับมา
# ฝั่งเจ้าห้อง
var _peer_slot := {}           # peer id -> ช่อง
var _slot_peer := {}           # ช่อง -> peer id
var _slot_nid := {}            # ช่อง -> nid (จำไว้ทั้งรอบที่เปิดห้อง)
var _pending := {}             # peer id -> {slot, nm, nid} ผ่านประตูแล้ว รอต่อเสร็จ
var _knocking := {}            # peer id -> true กำลังยืนยันตัว
var _drop_at := {}             # peer id -> เวลาที่จะตัด (หลัง REFUSE)
var _gone_at := {}             # ช่อง -> เวลาที่หลุด (เก็บช่องไว้ 60 วินาที)
var _heard := {}               # peer id -> เวลาที่ได้ยินล่าสุด
var _rate := {}                # peer id -> [เวลาข้อความทั่วไป, เวลาข้อความการรบ]
var _poses := {}               # ช่อง -> ท่าทางล่าสุด (มี s) ส่งให้คนที่เพิ่งเข้า
var _battle_owners: Array = []  # START.owners ของเกมล่าสุด: ระหว่างรบ ช่องเหล่านี้เก็บไว้ให้เจ้าของเดิม คนใหม่ได้ช่องอื่น
var _closing := false
# ฝั่งเพื่อน
var _ip := ""
var _port := 0
var _t0 := 0                   # เริ่มต่อ / เริ่มหลุด
var _next_try := 0
var _host_heard := 0
var _bye_seen := false


func _ready() -> void:
	set_process(false)
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--net-port="):
			var p := a.trim_prefix("--net-port=").to_int()
			if p > 0 and p < 65535:
				ports = {"game": p, "disc": p + 1}
	if make_link and ResourceLoader.exists(NET_BATTLE_LINK):
		var s: Variant = load(NET_BATTLE_LINK)
		if s is GDScript and (s as GDScript).can_instantiate():
			var n: Variant = (s as GDScript).new()
			if n is Node:
				_link = n
				_link.name = "NetBattleLink"
				add_child(_link)


func _exit_tree() -> void:
	if _state != &"off" and _state != &"finding":
		leave()
	elif _disc != null:
		_disc.stop()


## แอปไปอยู่เบื้องหลัง (มือถือ): ปิดซ็อกเก็ตค้นหาห้อง คืน multicast lock ประหยัดแบต · กลับมา: เปิดใหม่ (ห้องยังอยู่)
func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_PAUSED:
		if _disc != null and _disc.is_on():
			var was_finder := not _disc.is_host()
			_disc.stop()
			_disc_paused = true
			if was_finder:
				found_changed.emit()
	elif what == NOTIFICATION_APPLICATION_RESUMED and _disc_paused:
		_disc_paused = false
		if is_host() and _disc != null:
			_disc_ok = _disc.start_host(int(ports["disc"]), _beacon)
		elif _finding and not is_online() and _state != &"connecting":
			_start_find()


# ------------------------------------------------------------------------------------------------ ถามสถานะ

func state() -> StringName:
	return _state


func is_online() -> bool:
	return _state == &"hosting" or _state == &"joined" or _state == &"reconnecting"


func is_host() -> bool:
	return _state == &"hosting"


func my_slot() -> int:
	return _slot if is_online() else -1


func my_name() -> String:
	_load_cfg()
	return _nm


## ตั้งชื่อ (ทำความสะอาดแล้ว) เก็บใน cfg_file; คืนชื่อที่ได้
func set_my_name(nm: String) -> String:
	_load_cfg()
	_nm = NetProto.clean_name(nm)
	_save_cfg()
	if is_host() and _members.has(0):
		_members[0]["nm"] = _nm
		_host_nm = _nm
		_host_members_changed()
	return _nm


func found() -> Array[Dictionary]:
	if _disc == null or not _disc.is_on() or _disc.is_host():
		return [] as Array[Dictionary]
	return _disc.found()


## เจ้าห้อง: false เมื่อผูกพอร์ตค้นหาไม่ได้ (เพื่อนใส่ IP แทน) · คนหาห้อง: กำลังค้นหาอยู่ไหม
func discovery_on() -> bool:
	if is_host():
		return _disc_ok
	return _disc != null and _disc.is_on()


func members() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var keys: Array = _members.keys()
	keys.sort()
	for s: int in keys:
		out.append(_rec_out(_members[s]))
	return out


func member(slot: int) -> Dictionary:
	return _rec_out(_members[slot]) if _members.has(slot) else {}


func room_state() -> String:
	if is_host():
		return _host_room_st()
	return _room_st if is_online() else "deck"


func setup_seats() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if _setup_open and is_online():
		for s: Variant in _setup_seats:
			out.append((s as Dictionary).duplicate(true))
	return out


## IPv4 ในวงส่วนตัวของเครื่องนี้ที่เพื่อนพิมพ์ได้ (ไม่รวม loopback และเน็ตมือถือ/VPN) Wi-Fi/สายแลนก่อน
func local_ips() -> PackedStringArray:
	return private_ips(lan_addresses())


## มีเครือข่ายในบ้านไหม (Wi-Fi ฮอตสปอต หรือสายแลน): IPv4 ที่ไม่ใช่ loopback ไม่ใช่ CGNAT บนการ์ดที่ไม่ใช่เน็ตมือถือ/VPN
## ไม่มี = เปิดห้องไม่ได้ (no_lan) และหน้าค้นหาห้องบอกให้ต่อ Wi-Fi
func has_lan() -> bool:
	return lan_ok(lan_addresses())


## [[ip, ลำดับ]] ของเครื่องนี้ (lan_from ของการ์ดเครือข่ายจริง)
static func lan_addresses() -> Array:
	var itfs := IP.get_local_interfaces()
	if itfs.is_empty():
		var out: Array = []
		for ip: String in IP.get_local_addresses():
			if _ipv4(ip):
				out.append([ip, 1])
		return out
	return lan_from(itfs)


## IP ส่วนตัวจาก [[ip, ลำดับ]] เรียง Wi-Fi/สายแลนก่อน แล้วตามตัวอักษร (ไม่ซ้ำ)
static func private_ips(addrs: Array) -> PackedStringArray:
	var ranked: Array = []
	for a: Array in addrs:
		if NetGate.is_private(str(a[0])):
			ranked.append(a)
	ranked.sort_custom(func(x: Array, y: Array) -> bool:
		return int(x[1]) < int(y[1]) if int(x[1]) != int(y[1]) else str(x[0]) < str(y[0]))
	var out := PackedStringArray()
	for a: Array in ranked:
		if not out.has(str(a[0])):
			out.append(str(a[0]))
	return out


## มี IPv4 ที่ใช้เป็นห้องได้ไหม (ไม่ใช่ CGNAT ของผู้ให้บริการ)
static func lan_ok(addrs: Array) -> bool:
	for a: Array in addrs:
		if not _cgnat(str(a[0])):
			return true
	return false


## 100.64.0.0/10 ของผู้ให้บริการเน็ต (ไม่ใช่วงในบ้าน)
static func _cgnat(ip: String) -> bool:
	var v := NetGate._v4(ip)
	return v.size() == 4 and v[0] == 100 and v[1] >= 64 and v[1] <= 127


## [[ip, ลำดับ]] ของ IPv4 ที่ไม่ใช่ loopback บนการ์ดที่ไม่ใช่เน็ตมือถือ/VPN · ลำดับ 0 = Wi-Fi/ฮอตสปอต/สายแลน 1 = อื่น ๆ
## itfs แบบ IP.get_local_interfaces() (การ์ดเน็ตมือถือมักได้ 10.x หรือ 100.64.x: เพื่อนพิมพ์แล้วต่อไม่ติด จึงไม่นับ)
static func lan_from(itfs: Array) -> Array:
	var out: Array = []
	for itf: Dictionary in itfs:
		var nm := str(itf.get("name", "")).to_lower()
		var fr := str(itf.get("friendly", "")).to_lower()
		if _iface_in(nm, CELL_IFACES):
			continue
		var rank := 0 if _iface_in(nm, LAN_IFACES) or _iface_in(fr, LAN_IFACES) else 1
		for ip: Variant in itf.get("addresses", []):
			if _ipv4(str(ip)):
				out.append([str(ip), rank])
	return out


static func _ipv4(ip: String) -> bool:
	return ip.count(".") == 3 and not ip.contains(":") and not ip.begins_with("127.")


static func _iface_in(nm: String, prefixes: PackedStringArray) -> bool:
	for p: String in prefixes:
		if nm.begins_with(p):
			return true
	return false


# ------------------------------------------------------------------------------------------------ เปิด / เข้า / ออก

## เปิดห้อง: OK หรือ ERR_CANT_CREATE (refused port_busy) / ERR_UNCONFIGURED (refused no_lan)
func host() -> Error:
	if is_host():
		return OK
	if _state != &"off" and _state != &"finding":
		return ERR_ALREADY_IN_USE
	_load_cfg()
	_ensure_identity()
	if not has_lan():
		refused.emit("no_lan", {})
		return ERR_UNCONFIGURED
	var p := ENetMultiplayerPeer.new()
	# IPv4 เท่านั้น ("*" ของ Godot รวม IPv6 สาธารณะ: คนจากเน็ตต่อถึงขั้น ENet ได้ก่อนประตู not_lan)
	p.set_bind_ip("0.0.0.0")
	# ที่ว่างเผื่อสองที่: คนที่ถูกปฏิเสธ (ห้องเต็ม) ยังต่อเข้ามาฟังเหตุผลได้
	if p.create_server(int(ports["game"]), max_players + 1) != OK:
		refused.emit("port_busy", {"port": int(ports["game"])})
		return ERR_CANT_CREATE
	if _disc != null:
		_disc.stop()
	_reset_room()
	_peer = p
	_bind_mp()
	_mp.multiplayer_peer = p
	_slot = 0
	_host_nm = _nm
	_token = _hex(8)
	_members[0] = _rec(0, _nm, _where, _pick, true)
	_disc = NetDiscovery.new()
	_disc_ok = _disc.start_host(int(ports["disc"]), _beacon)
	_online_on()
	_set_state(&"hosting")
	members_changed.emit()
	_log("info", "net: hosting on port %d (discovery %s)" % [int(ports["game"]), "on" if _disc_ok else "off"])
	return OK


## เข้าห้องด้วย IP (รับ "ip:port" ได้): ERR_INVALID_PARAMETER (refused bad_ip), ERR_UNAUTHORIZED (refused not_lan)
func join(ip: String, port: int = 0) -> Error:
	if _state != &"off" and _state != &"finding":
		return ERR_ALREADY_IN_USE
	var parsed := NetGate.parse_ip(ip)
	if parsed.is_empty():
		refused.emit("bad_ip", {})
		return ERR_INVALID_PARAMETER
	if not NetGate.is_private(str(parsed["ip"])):
		refused.emit("not_lan", {})
		return ERR_UNAUTHORIZED
	_load_cfg()
	_ensure_identity()
	_reset_room()
	_ip = str(parsed["ip"])
	_port = port if port > 0 else (int(parsed["port"]) if int(parsed["port"]) > 0 else int(ports["game"]))
	var e := _connect()
	if e != OK:
		refused.emit("timeout", {})
		return e
	_t0 = _now()
	_go_timer()
	_set_state(&"connecting")
	return OK


## ออกจากห้อง: เพื่อนส่ง BYE; เจ้าห้องปิดห้อง (ส่ง END ให้การรบที่เล่นอยู่ก่อน แล้ว BYE host_closed)
func leave() -> void:
	match _state:
		&"hosting":
			_closing = true
			if _host_room_st() == "battle":
				send(NetProto.END, {"gen": _battle_gen, "why": "host_closed"})
			send(NetProto.BYE, {"key": "host_closed"})
			_quiet_close()
			_shutdown()
		&"joined":
			send(NetProto.BYE, {"key": "leave"})
			_quiet_close()
			_shutdown()
		&"connecting", &"reconnecting":
			_shutdown()


## เปิด/ปิดรายการห้อง (คำถามกระจาย + บีคอน); ไม่ค้นหาตอนอยู่ในห้องแล้ว
func find(on: bool) -> void:
	_finding = on
	if on:
		if is_online() or _state == &"connecting":
			return
		_start_find()
		if _state == &"off":
			_set_state(&"finding")
	else:
		if _disc != null and not _disc.is_host():
			var had := not _disc.found().is_empty()
			_disc.stop()
			if had:
				found_changed.emit()
		if _state == &"finding":
			_set_state(&"off")
			_idle_off()


func claim(k: int) -> void:
	if _state == &"joined" and _setup_open:
		send(NetProto.CLAIM, {"k": k})


# ------------------------------------------------------------------------------------------------ ส่ง

## ส่งข้อความ: to_slot -1 = เพื่อนส่งหาเจ้าห้อง / เจ้าห้องส่งหาทุกคน · false เมื่อข้อความผิดตารางหรือไม่ได้ออนไลน์
func send(kind: int, body: Dictionary, to_slot: int = -1) -> bool:
	if _state != &"hosting" and _state != &"joined":
		return false
	if kind == NetProto.HELLO or kind == NetProto.WELCOME or kind == NetProto.REFUSE:
		return false
	var dir: String = NetProto.DIR.get(kind, "")
	var bytes := NetProto.encode(kind, body)
	if bytes.is_empty():
		_log("warn", "net: not sending an invalid %s" % NetProto.kind_name(kind))
		return false
	if is_host():
		if dir == "c":
			return false
		var st0 := _host_room_st()
		_host_sniff(kind, body)
		if to_slot < 0:
			for s: int in _slot_peer:
				_raw(int(_slot_peer[s]), bytes, kind)
		elif _slot_peer.has(to_slot):
			_raw(int(_slot_peer[to_slot]), bytes, kind)
		else:
			return false
		if _host_room_st() != st0:
			_host_members_changed()
		return true
	if dir == "h" or to_slot > 0:
		return false
	_raw(1, bytes, kind)
	return true


## ส่งท่าทางของตัวเอง: stop = ท่าสุดท้ายตอนหยุด (ส่งแบบรับประกัน)
func send_pose(p: Dictionary, stop: bool) -> void:
	if not is_host() and _state != &"joined":
		return
	var yaw := int(p.get("yaw", 0))
	while yaw > 3142:
		yaw -= 6283
	while yaw < -3142:
		yaw += 6283
	var body := {"x": clampi(int(p.get("x", 0)), -5000, 5000), "z": clampi(int(p.get("z", 0)), -5000, 5000),
		"yaw": yaw, "sp": 0 if stop else clampi(int(p.get("sp", 0)), 0, 2000), "run": bool(p.get("run", false)),
		"t": maxi(0, int(p.get("t", Time.get_ticks_msec())))}
	var kind := NetProto.POSE_STOP if stop else NetProto.POSE
	if is_host():
		body["s"] = 0
		_poses[0] = body
	send(kind, body)


func set_where(where: StringName) -> void:
	var w := str(where)
	if not NetProto.WHERES.has(w):
		return
	_where = w
	if is_host() and _members.has(0):
		_members[0]["where"] = w
		_host_members_changed()
	elif _state == &"joined":
		send(NetProto.WHERE, {"where": w})


func set_pick(fac: String) -> void:
	if fac != "" and not GameData.factions().has(fac):
		return
	_pick = fac
	if is_host() and _members.has(0):
		_members[0]["pick"] = fac
		_host_members_changed()
	elif _state == &"joined":
		send(NetProto.PICK, {"fac": fac})


## เทส: poll หนึ่งครั้งของ multiplayer และงานตามเวลา (การค้นหา ชีพจร หมดเวลา)
func poll() -> void:
	if _mp != null and _peer != null:
		_mp.poll()
	_tick()


# ------------------------------------------------------------------------------------------------ ภายใน: ตั้งค่า

func _now() -> int:
	return Time.get_ticks_msec() + clock_skew_ms


func _log(level: String, msg: String) -> void:
	var lg := get_node_or_null(^"/root/Log")
	if lg != null:
		lg.call(level, msg)
	elif level == "error":
		push_error(msg)


func _set_state(s: StringName) -> void:
	if s == _state:
		return
	_state = s
	state_changed.emit(s)


func _load_cfg() -> void:
	if _cfg_loaded:
		return
	_cfg_loaded = true
	var cf := ConfigFile.new()
	if cf.load(cfg_file) == OK:
		_nm = NetProto.clean_name(str(cf.get_value("net", "nm", "")))
		var nid := str(cf.get_value("net", "nid", ""))
		_nid = nid if NetProto.is_hex(nid, 16) else ""


func _save_cfg() -> void:
	var cf := ConfigFile.new()
	cf.load(cfg_file)
	cf.set_value("net", "nm", _nm)
	if _nid != "":
		cf.set_value("net", "nid", _nid)
	cf.save(cfg_file)


## nid สุ่มครั้งแรกที่ใช้ และชื่อสำรอง (เลขสามหลัก) ถ้ายังไม่มีชื่อ
func _ensure_identity() -> void:
	var dirty := false
	if _nid == "":
		_nid = _hex(16)
		dirty = true
	if _nm == "":
		_nm = str(randi_range(100, 999))
		dirty = true
	if dirty:
		_save_cfg()


static func _hex(n: int) -> String:
	return Crypto.new().generate_random_bytes(n / 2).hex_encode()


func _rec(slot: int, nm: String, where: String, pick: String, here: bool) -> Dictionary:
	return {"slot": slot, "nm": nm, "where": where, "pick": pick, "here": here}


func _rec_out(r: Dictionary) -> Dictionary:
	var o := r.duplicate()
	o["where"] = StringName(str(r["where"]))
	return o


func _member_list() -> Array:
	var out: Array = []
	var keys: Array = _members.keys()
	keys.sort()
	for s: int in keys:
		out.append((_members[s] as Dictionary).duplicate())
	return out


func _host_room_st() -> String:
	if _setup_open:
		return "setup"
	return "battle" if _where == "battle" else "deck"


func _beacon() -> PackedByteArray:
	return NetDiscovery.make_beacon({"app": Version.APP_VER, "rules": Version.RULES_V, "data": Version.DATA_HASH,
		"port": int(ports["game"]), "nm": _nm, "n": _members.size() + _pending.size(), "max": max_players,
		"st": _host_room_st(), "t": _token})


func _bind_mp() -> void:
	var mp := multiplayer as SceneMultiplayer
	_mp = mp
	mp.server_relay = false
	mp.allow_object_decoding = false
	mp.auth_timeout = 5.0
	mp.auth_callback = _on_auth
	var pairs := [[mp.peer_authenticating, _on_authenticating], [mp.peer_authentication_failed, _on_auth_failed],
		[mp.peer_connected, _on_peer_connected], [mp.peer_disconnected, _on_peer_disconnected],
		[mp.peer_packet, _on_packet], [mp.connected_to_server, _on_connected],
		[mp.connection_failed, _on_connection_failed], [mp.server_disconnected, _on_server_disconnected]]
	for p: Array in pairs:
		if not (p[0] as Signal).is_connected(p[1]):
			(p[0] as Signal).connect(p[1])


func _unbind_mp() -> void:
	if _mp == null:
		return
	var mp := _mp
	var pairs := [[mp.peer_authenticating, _on_authenticating], [mp.peer_authentication_failed, _on_auth_failed],
		[mp.peer_connected, _on_peer_connected], [mp.peer_disconnected, _on_peer_disconnected],
		[mp.peer_packet, _on_packet], [mp.connected_to_server, _on_connected],
		[mp.connection_failed, _on_connection_failed], [mp.server_disconnected, _on_server_disconnected]]
	for p: Array in pairs:
		if (p[0] as Signal).is_connected(p[1]):
			(p[0] as Signal).disconnect(p[1])
	mp.auth_callback = Callable()


func _connect() -> Error:
	var p := ENetMultiplayerPeer.new()
	var e := p.create_client(_ip, _port)
	if e != OK:
		return e
	_peer = p
	_bind_mp()
	_mp.multiplayer_peer = p
	return OK


## ปิด peer ของความพยายามนี้ (ยังผูกสัญญาณไว้ ใช้ตอนต่อใหม่)
func _close_peer() -> void:
	if _peer != null:
		_peer.close()
	_peer = null
	if _mp != null:
		_mp.multiplayer_peer = OfflineMultiplayerPeer.new()


func _flush() -> void:
	if _peer != null and _peer.host != null:
		_peer.host.flush()


## ส่ง BYE ออกไปทันทีแล้วตัดแบบเงียบ (ไม่ส่งคำสั่ง disconnect ของ ENet): ถ้า BYE กับ disconnect ถึงในรอบ poll เดียวกัน
## SceneMultiplayer ทิ้งแพ็กเก็ตที่ค้างหลังหลุด อีกฝั่งจะไม่เห็น BYE (เพื่อนจะพยายามต่อใหม่แทนที่จะรู้ว่าเจ้าห้องปิดห้อง)
## BYE หายระหว่างทาง = อีกฝั่งหมดเวลาเองใน 3-8 วินาที
func _quiet_close() -> void:
	_flush()
	if _peer == null:
		return
	var ids: Array = _slot_peer.values() if is_host() else [1]
	for id: Variant in ids:
		var pp := _peer.get_peer(int(id))
		if pp != null and pp.is_active():
			pp.reset()


func _go_timer() -> void:
	if _timer != null:
		return
	_timer = Timer.new()
	_timer.name = "NetTick"
	_timer.wait_time = TICK_S
	_timer.timeout.connect(_tick)
	add_child(_timer)
	_timer.start()


func _online_on() -> void:
	_go_timer()
	_hb_at = _now()
	# จอไม่ดับระหว่างอยู่ในห้อง · จำค่าเดิมไว้คืนตอนออก (ค่าเริ่มต้นของโปรเจกต์คือเปิดค้าง ห้ามปิดให้เกมออฟไลน์)
	if not _screen_held:
		_screen_was_on = DisplayServer.screen_is_kept_on()
		_screen_held = true
	DisplayServer.screen_set_keep_on(true)


## กลับไปไม่ทำอะไร: ไม่มี Timer (ยกเว้นยังเปิดรายการห้องอยู่)
func _idle_off() -> void:
	if _finding and _disc != null and _disc.is_on():
		return
	if _timer != null:
		remove_child(_timer)
		_timer.queue_free()
		_timer = null


func _start_find() -> void:
	if _disc == null:
		_disc = NetDiscovery.new()
	if not _disc.is_on() or _disc.is_host():
		var pr := probe.duplicate()
		if _last_ip != "" and not pr.has(_last_ip):
			pr.append(_last_ip)
		_disc.start_find(int(ports["disc"]), pr)
	_go_timer()


func _reset_room() -> void:
	_members.clear()
	_peer_slot.clear()
	_slot_peer.clear()
	_slot_nid.clear()
	_pending.clear()
	_knocking.clear()
	_drop_at.clear()
	_gone_at.clear()
	_heard.clear()
	_rate.clear()
	_poses.clear()
	_battle_owners = []
	_closing = false
	_bye_seen = false
	_setup_open = false
	_setup_seats = []
	_room_st = "deck"
	_slot = -1
	_host_nm = ""
	_mgen = 0


## ปิดทุกอย่างของห้องนี้แล้วกลับเป็น off (หรือ finding ถ้ารายการห้องยังเปิด)
func _shutdown() -> void:
	_unbind_mp()
	if _peer != null:
		_peer.close()
	_peer = null
	if _mp != null:
		_mp.multiplayer_peer = OfflineMultiplayerPeer.new()
	_mp = null
	if _disc != null and _disc.is_host():
		_disc.stop()
	_disc_ok = false
	var had_members := not _members.is_empty()
	_reset_room()
	if _screen_held:
		DisplayServer.screen_set_keep_on(_screen_was_on)
		_screen_held = false
	if had_members:
		members_changed.emit()
	if _finding:
		_start_find()
		_set_state(&"finding")
	else:
		_set_state(&"off")
	_idle_off()


func _raw(peer_id: int, bytes: PackedByteArray, kind: int) -> void:
	if _mp == null:
		return
	if kind == NetProto.POSE:
		_mp.send_bytes(bytes, peer_id, MultiplayerPeer.TRANSFER_MODE_UNRELIABLE_ORDERED, CH_POSE)
	else:
		_mp.send_bytes(bytes, peer_id, MultiplayerPeer.TRANSFER_MODE_RELIABLE, CH_MAIN)


func _hb_body() -> Dictionary:
	if _link != null and _link.has_method("hb_body"):
		var b: Variant = _link.call("hb_body")
		if b is Dictionary and not NetProto.encode(NetProto.HB, b).is_empty():
			return b
	return {}


# ------------------------------------------------------------------------------------------------ ภายใน: เวลา

func _tick() -> void:
	var now := _now()
	if _disc != null and _disc.is_on():
		if _disc.poll(now) and not _disc.is_host():
			found_changed.emit()
	match _state:
		&"connecting":
			if now - _t0 > CONNECT_MS:
				_fail_join("timeout", {})
		&"reconnecting":
			if now - _t0 > RECONNECT_MS:
				_client_lost("reconnect_failed")
			elif now >= _next_try:
				_next_try = now + RETRY_MS
				_close_peer()
				if _connect() != OK:
					_close_peer()
		&"hosting":
			_host_tick(now)
		&"joined":
			if now - _host_heard > SILENT_MS:
				_start_reconnect()
			elif now - _hb_at >= HB_MS:
				_hb_at = now
				send(NetProto.HB, _hb_body())


func _host_tick(now: int) -> void:
	for id: int in _drop_at.keys():
		if now >= int(_drop_at[id]):
			_drop_at.erase(id)
			_drop_peer(id)
	var changed := false
	for s: int in _gone_at.keys():
		if now - int(_gone_at[s]) > KEEP_SLOT_MS:
			_gone_at.erase(s)
			_members.erase(s)
			changed = true
	for id: int in _peer_slot.keys():
		if now - int(_heard.get(id, now)) > SILENT_MS:
			_log("warn", "net: slot %d went silent" % int(_peer_slot[id]))
			_kick(id, true)
	if changed:
		_host_members_changed()
	if now - _hb_at >= HB_MS:
		_hb_at = now
		send(NetProto.HB, _hb_body())


# ------------------------------------------------------------------------------------------------ ภายใน: ยืนยันตัว

func _on_authenticating(id: int) -> void:
	if _peer == null:
		return
	var pp := _peer.get_peer(id)
	if pp != null:
		pp.set_timeout(32, 3000, 8000)
	if is_host():
		_knocking[id] = true
		var ip := pp.get_remote_address() if pp != null else ""
		if not NetGate.is_private(ip):
			_refuse(id, "not_lan", {})
		return
	# ฝั่งเพื่อน: ส่ง HELLO
	var hello := {"g": NetProto.GAME, "np": NetProto.VERSION, "app": Version.APP_VER, "rules": Version.RULES_V,
		"data": Version.DATA_HASH, "nm": _nm, "nid": _nid}
	var plain := NetProto.encode(NetProto.HELLO, hello)
	hello.merge(hello_extra, true)
	var bytes := NetProto.encode(NetProto.HELLO, hello)
	# ไบต์ว่างใน send_auth แปลว่า "ยืนยันเสร็จ" จึงห้ามส่งว่าง
	_mp.send_auth(id, bytes if not bytes.is_empty() else plain)


func _on_auth(id: int, data: PackedByteArray) -> void:
	if is_host():
		_host_auth(id, data)
	else:
		_client_auth(id, data)


func _host_auth(id: int, data: PackedByteArray) -> void:
	if _pending.has(id) or _drop_at.has(id) or _peer_slot.has(id):
		return
	var m := NetProto.decode(data)
	var hello: Dictionary = m["body"] if not m.has("error") and int(m["kind"]) == NetProto.HELLO else {}
	var pp := _peer.get_peer(id)
	var ip := pp.get_remote_address() if pp != null else ""
	var nid := str(hello.get("nid", ""))
	var known := false
	for s: int in _slot_nid:
		if _slot_nid[s] == nid and _members.has(s):
			known = true
	var g := NetGate.check_hello(hello, _members.size() + _pending.size(), max_players, ip, known, _closing)
	if g["key"] != "":
		_refuse(id, g["key"], g["args"])
		return
	var slot := _pick_slot(nid)
	if slot < 0:
		_refuse(id, "full", {"n": _members.size() + _pending.size(), "max": max_players})
		return
	# nid เดิมที่ยังค้างการต่อเก่าอยู่ (ต่อใหม่เร็วกว่าที่ ENet ของเจ้าห้องรู้ว่าหลุด): นับว่าหลุดก่อน (here = false)
	# แล้วอันใหม่ใช้ช่องเดิม · ตัวเชื่อมการรบจึงเห็นหลุดแล้วกลับ คืนที่นั่งพร้อม RESYNC
	if _slot_peer.has(slot):
		var old := int(_slot_peer[slot])
		_host_drop(old, true)
		_drop_peer(old)
	var nm := NetProto.clean_name(str(hello["nm"]))
	_pending[id] = {"slot": slot, "nm": nm, "nid": nid}
	_slot_nid[slot] = nid
	var list := _member_list()
	var pick := str((_members[slot] as Dictionary).get("pick", "")) if _members.has(slot) else ""
	var rec := _rec(slot, nm, _where_of(slot), pick, true)
	var replaced := false
	for i: int in list.size():
		if int(list[i]["slot"]) == slot:
			list[i] = rec
			replaced = true
	if not replaced:
		list.append(rec)
	list.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["slot"]) < int(b["slot"]))
	var welcome := {"slot": slot, "host_nm": _nm, "room_st": _host_room_st(), "members": list, "np": NetProto.VERSION}
	_mp.send_auth(id, NetProto.encode(NetProto.WELCOME, welcome))
	_mp.complete_auth(id)


## ที่อยู่เดิมของช่องที่ยังเก็บไว้ (ต่อใหม่ไม่รีเซ็ตเป็น deck; เพื่อนส่ง WHERE ของตัวเองตามมาทันที)
func _where_of(slot: int) -> String:
	return str((_members[slot] as Dictionary).get("where", "deck")) if _members.has(slot) else "deck"


func _refuse(id: int, key: String, args: Dictionary) -> void:
	_log("info", "net: refused a join (%s)" % key)
	_mp.send_auth(id, NetProto.encode(NetProto.REFUSE, {"key": key, "args": args}))
	_flush()
	_drop_at[id] = _now() + REFUSE_DROP_MS


## ช่องว่างสำหรับ nid นี้: ช่องเดิมของ nid ก่อน แล้วช่องเล็กสุดที่ไม่มีใครถือ (คนที่หลุดยังถือช่องไว้)
## ระหว่างรบ ช่องที่มีที่นั่งในเกมนี้ไม่ให้คนใหม่ (เจ้าของเดิมกลับมาได้ที่นั่งคืน คนใหม่ได้ดูอย่างเดียว §4.8)
func _pick_slot(nid: String) -> int:
	for s: int in _slot_nid:
		if _slot_nid[s] == nid and s != 0:
			var taken_by_other := false
			for id: int in _pending:
				if int(_pending[id]["slot"]) == s:
					taken_by_other = true
			if not taken_by_other:
				return s
	var taken := {}
	for s: int in _members:
		taken[s] = true
	for id: int in _pending:
		taken[int(_pending[id]["slot"])] = true
	if _host_room_st() == "battle":
		for s: Variant in _battle_owners:
			if int(s) > 0:
				taken[int(s)] = true
	for s: int in range(1, MAX_PLAYERS):
		if not taken.has(s):
			return s
	return -1


func _on_auth_failed(id: int) -> void:
	_pending.erase(id)
	_knocking.erase(id)
	_drop_at.erase(id)


func _drop_peer(id: int) -> void:
	if _mp == null or _peer == null:
		return
	var known := _knocking.has(id) or _pending.has(id) or _mp.get_peers().has(id)
	_knocking.erase(id)
	_pending.erase(id)
	if known:
		_mp.disconnect_peer(id)


func _client_auth(id: int, data: PackedByteArray) -> void:
	if id != 1:
		return
	var m := NetProto.decode(data)
	if m.has("error"):
		_log("warn", "net: bad answer from the host: %s" % m["error"])
		if _state == &"reconnecting":
			_client_lost("bad_message")
		else:
			_fail_join("bad_message", {})
		return
	var kind := int(m["kind"])
	var body: Dictionary = m["body"]
	if kind == NetProto.REFUSE:
		if _state == &"reconnecting":
			_client_lost("reconnect_failed")
		else:
			_fail_join(str(body["key"]), body["args"])
		return
	if kind != NetProto.WELCOME:
		_fail_join("bad_message", {})
		return
	if int(body.get("np", NetProto.VERSION)) != NetProto.VERSION:
		_fail_join("wrong_net", {"host": int(body["np"]), "mine": NetProto.VERSION})
		return
	_slot = int(body["slot"])
	_host_nm = NetProto.clean_name(str(body["host_nm"]))
	_room_st = str(body["room_st"])
	_apply_members(body["members"])
	_mp.complete_auth(1)


## รายชื่อจากเจ้าห้อง: ชื่อทำความสะอาดซ้ำ (เจ้าห้องที่ถูกแก้อาจส่งอักขระควบคุม/ตัวกำหนดทิศมา)
func _apply_members(list: Array) -> void:
	_members.clear()
	for r: Dictionary in list:
		var m := r.duplicate()
		m["nm"] = NetProto.clean_name(str(r["nm"]))
		_members[int(r["slot"])] = m


func _fail_join(key: String, args: Dictionary) -> void:
	_log("info", "net: join failed (%s)" % key)
	refused.emit(key, args)
	_shutdown()


func _client_lost(key: String) -> void:
	_log("warn" if key != "host_left" else "info", "net: left the room (%s)" % key)
	lost.emit(key)
	_shutdown()


func _start_reconnect() -> void:
	if _state != &"joined":
		return
	_log("warn", "net: lost the host, reconnecting")
	_t0 = _now()
	_next_try = _t0
	_set_state(&"reconnecting")   # ก่อนปิด peer: สัญญาณที่ตามมาจากการปิดจะไม่วนกลับมาที่นี่
	_close_peer()


# ------------------------------------------------------------------------------------------------ ภายใน: สัญญาณ ENet

func _on_connected() -> void:
	var again := _state == &"reconnecting"
	_host_heard = _now()
	_last_ip = _ip
	# อยู่ในห้องแล้วไม่ต้องค้นหา (ออกจากห้องแล้วรายการเปิดใหม่เองถ้ายังเปิดหน้าอยู่)
	if _disc != null and _disc.is_on() and not _disc.is_host():
		_disc.stop()
		found_changed.emit()
	_online_on()
	_set_state(&"joined")
	members_changed.emit()
	send(NetProto.WHERE, {"where": _where})
	if _pick != "":
		send(NetProto.PICK, {"fac": _pick})
	if again:
		reconnected.emit()


func _on_connection_failed() -> void:
	if _state == &"connecting":
		_fail_join("timeout", {})


func _on_server_disconnected() -> void:
	if _state == &"joined":
		if _bye_seen:
			_client_lost("host_left")
		else:
			_start_reconnect()
	elif _state == &"connecting":
		_fail_join("timeout", {})


func _on_peer_connected(id: int) -> void:
	if not is_host() or not _pending.has(id):
		return
	var p: Dictionary = _pending[id]
	_pending.erase(id)
	_knocking.erase(id)
	var slot := int(p["slot"])
	_peer_slot[id] = slot
	_slot_peer[slot] = id
	_slot_nid[slot] = p["nid"]
	_gone_at.erase(slot)
	var pick := str((_members[slot] as Dictionary).get("pick", "")) if _members.has(slot) else ""
	_members[slot] = _rec(slot, str(p["nm"]), _where_of(slot), pick, true)
	_heard[id] = _now()
	_log("info", "net: slot %d joined" % slot)
	_host_members_changed()
	for s: int in _poses:
		if s != slot:
			_raw(id, NetProto.encode(NetProto.POSE_STOP, _poses[s]), NetProto.POSE_STOP)
	if _setup_open:
		_raw(id, NetProto.encode(NetProto.SETUP, {"open": true, "seats": _setup_seats}), NetProto.SETUP)


func _on_peer_disconnected(id: int) -> void:
	if is_host():
		_host_drop(id, true)


## สมาชิกหลุด (keep = เก็บช่องไว้ให้ต่อใหม่ 60 วินาที; false = ออกจากห้องเลย)
func _host_drop(id: int, keep: bool) -> void:
	_pending.erase(id)
	_knocking.erase(id)
	_drop_at.erase(id)
	_rate.erase(id)
	_heard.erase(id)
	if not _peer_slot.has(id):
		return
	var slot := int(_peer_slot[id])
	_peer_slot.erase(id)
	if _slot_peer.get(slot, -1) == id:
		_slot_peer.erase(slot)
	_poses.erase(slot)
	if keep and not _closing and _members.has(slot):
		_members[slot]["here"] = false
		_gone_at[slot] = _now()
	else:
		_members.erase(slot)
		_gone_at.erase(slot)
	_log("info", "net: slot %d %s" % [slot, "dropped" if keep else "left"])
	_host_members_changed()


## ตัดสมาชิกเอง (ข้อความผิด ส่งถี่เกิน เงียบ): ENet ไม่ส่ง peer_disconnected ให้การตัดฝั่งเรา จึงเก็บกวาดที่นี่
func _kick(id: int, keep: bool) -> void:
	_host_drop(id, keep)
	if _mp != null and _peer != null and _mp.get_peers().has(id):
		_mp.disconnect_peer(id)


func _host_members_changed() -> void:
	if not is_host():
		return
	_mgen = (_mgen + 1) % 65536
	send(NetProto.MEMBERS, {"list": _member_list(), "room_st": _host_room_st(), "gen": _mgen})
	members_changed.emit()


func _host_sniff(kind: int, body: Dictionary) -> void:
	match kind:
		NetProto.SETUP:
			_setup_open = bool(body["open"])
			_setup_seats = (body["seats"] as Array).duplicate(true) if _setup_open else []
		NetProto.START:
			_battle_gen = int(body["gen"])
			_battle_owners = (body["owners"] as Array).duplicate()
			_setup_open = false
			_setup_seats = []


# ------------------------------------------------------------------------------------------------ ภายใน: ข้อความ

func _on_packet(id: int, bytes: PackedByteArray) -> void:
	if is_host():
		_host_packet(id, bytes)
	elif _state == &"joined":
		_client_packet(id, bytes)


func _rate_ok(id: int, kind: int, now: int) -> bool:
	if not _rate.has(id):
		_rate[id] = [PackedInt64Array(), PackedInt64Array()]
	var battle := kind >= NetProto.SETUP
	var i := 1 if battle else 0
	var times: PackedInt64Array = _rate[id][i]
	times.append(now)
	var cap := RATE_MAX_BATTLE if battle else RATE_MAX
	var ok := true
	if times.size() > cap:
		ok = now - times[0] >= RATE_WINDOW_MS
		times.remove_at(0)
	_rate[id][i] = times
	return ok


func _host_packet(id: int, bytes: PackedByteArray) -> void:
	if not _peer_slot.has(id) or bytes.is_empty():
		return
	var slot := int(_peer_slot[id])
	var now := _now()
	if not _rate_ok(id, int(bytes[0]), now):
		_log("warn", "net: slot %d sent too many messages" % slot)
		_kick(id, false)
		return
	_heard[id] = now
	# ชนิดของเจ้าห้อง/ยืนยันตัว หรือเกิน 64 KiB: ตัดก่อนถอด (ไม่ถอดข้อความใหญ่ของคนที่ส่งชนิดที่ตัวเองส่งไม่ได้)
	if not NetProto.from_member_ok(int(bytes[0]), bytes.size()):
		_log("warn", "net: bad message from slot %d: %s (%d bytes)" % [slot, NetProto.kind_name(int(bytes[0])), bytes.size()])
		_kick(id, false)
		return
	var m := NetProto.decode(bytes)
	if m.has("error"):
		_log("warn", "net: bad message from slot %d: %s" % [slot, str(m["error"])])
		_kick(id, false)
		return
	var kind := int(m["kind"])
	var body: Dictionary = m["body"]
	match kind:
		NetProto.WHERE:
			_members[slot]["where"] = body["where"]
			_host_members_changed()
		NetProto.PICK:
			var fac := str(body["fac"])
			if fac == "" or GameData.factions().has(fac):
				_members[slot]["pick"] = fac
				_host_members_changed()
		NetProto.POSE, NetProto.POSE_STOP:
			body["s"] = slot
			_poses[slot] = body
			var out := NetProto.encode(kind, body)
			for s: int in _slot_peer:
				if s != slot:
					_raw(int(_slot_peer[s]), out, kind)
			var p := body.duplicate()
			p.erase("s")
			pose.emit(slot, p)
		NetProto.BYE:
			_kick(id, false)
		NetProto.HB:
			message.emit(slot, kind, body)
		_:
			message.emit(slot, kind, body)


func _client_packet(id: int, bytes: PackedByteArray) -> void:
	if id != 1:
		return
	_host_heard = _now()
	if bytes.is_empty() or not NetProto.from_host_ok(int(bytes[0])):
		_log("error", "net: bad message from the host: %s" % (NetProto.kind_name(int(bytes[0])) if not bytes.is_empty() else "empty"))
		_client_lost("bad_message")
		return
	var m := NetProto.decode(bytes)
	if m.has("error"):
		_log("error", "net: bad message from the host: %s" % str(m["error"]))
		_client_lost("bad_message")
		return
	var kind := int(m["kind"])
	var body: Dictionary = m["body"]
	match kind:
		NetProto.MEMBERS:
			_room_st = str(body["room_st"])
			_apply_members(body["list"])
			members_changed.emit()
		NetProto.POSE, NetProto.POSE_STOP:
			var s := int(body.get("s", -1))
			if s >= 0 and s != _slot:
				var p := body.duplicate()
				p.erase("s")
				pose.emit(s, p)
		NetProto.BYE:
			_bye_seen = true
			_client_lost("host_left")
		NetProto.SETUP:
			_setup_open = bool(body["open"])
			_setup_seats = (body["seats"] as Array).duplicate(true) if _setup_open else []
			message.emit(0, kind, body)
		NetProto.START:
			_battle_gen = int(body["gen"])
			_setup_open = false
			_setup_seats = []
			message.emit(0, kind, body)
		_:
			message.emit(0, kind, body)
