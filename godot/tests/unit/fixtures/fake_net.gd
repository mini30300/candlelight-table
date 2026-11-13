extends Node
## A duck-typed stand-in for NetSession (NET_SPEC §11.3) for the deck and airlock tests: the same signals and methods,
## no sockets. Tests set its fields (state, slot, members, found rows, setup seats, IPs) and emit its signals; every
## call the screens make is recorded in `calls` as [method, args...]. host() / join() / leave() move the state the way
## the real session does, so the lobby screen can be driven through its buttons.

signal state_changed(state: StringName)
signal members_changed()
signal found_changed()
signal message(from_slot: int, kind: int, body: Dictionary)
signal pose(slot: int, pose: Dictionary)
signal refused(key: String, args: Dictionary)
signal lost(key: String)
signal reconnected()

const PORTS := {"game": 24680, "disc": 24681}
const MAX_PLAYERS := 6

var ports: Dictionary = PORTS.duplicate()
var probe: PackedStringArray = []
var cfg_file := "user://fake_net.cfg"
var max_players := MAX_PLAYERS
var hello_extra: Dictionary = {}

var st: StringName = &"off"
var slot := -1
var nm := ""
var host_flag := false
var finding := false
var found_rows: Array[Dictionary] = []
var member_list: Array[Dictionary] = []
var room_st := "deck"
var seats: Array[Dictionary] = []
var ips: PackedStringArray = PackedStringArray(["192.168.1.20"])
## has_lan() answer (false = this device has no Wi-Fi / LAN, only mobile data)
var lan := true
var disc := true
## join() answers: "" = goes to connecting, a key = refused at once (like bad_ip)
var join_refuse := ""
var host_refuse := ""
var calls: Array = []


func state() -> StringName:
	return st


func is_online() -> bool:
	return st == &"hosting" or st == &"joined" or st == &"reconnecting"


func is_host() -> bool:
	return host_flag and is_online()


func my_slot() -> int:
	return slot if is_online() else -1


func my_name() -> String:
	return nm


func set_my_name(n: String) -> String:
	var clean := " ".join(n.strip_edges().split(" ", false)).left(20)
	nm = clean
	calls.append(["set_my_name", clean])
	return clean


func host() -> Error:
	calls.append(["host"])
	if host_refuse != "":
		refused.emit(host_refuse, {"port": ports["game"]})
		return ERR_CANT_CREATE
	host_flag = true
	slot = 0
	member_list = [{"slot": 0, "nm": nm, "where": "deck", "pick": "", "here": true}]
	_set_state(&"hosting")
	members_changed.emit()
	return OK


func join(ip: String, port: int = 0) -> Error:
	calls.append(["join", ip, port])
	if join_refuse != "":
		refused.emit(join_refuse, {})
		return ERR_INVALID_PARAMETER if join_refuse == "bad_ip" else ERR_CANT_CONNECT
	host_flag = false
	_set_state(&"connecting")
	return OK


## Test helper: the host answered WELCOME (slot, members).
func welcome(my: int, list: Array[Dictionary]) -> void:
	slot = my
	member_list = list
	_set_state(&"joined")
	members_changed.emit()


func leave() -> void:
	calls.append(["leave"])
	host_flag = false
	slot = -1
	member_list = []
	room_st = "deck"
	seats = []
	_set_state(&"finding" if finding else &"off")
	members_changed.emit()


func find(on: bool) -> void:
	calls.append(["find", on])
	finding = on
	if not is_online() and st != &"connecting":
		_set_state(&"finding" if on else &"off")


func found() -> Array[Dictionary]:
	return found_rows


func discovery_on() -> bool:
	return disc


func members() -> Array[Dictionary]:
	return member_list


func member(s: int) -> Dictionary:
	for m in member_list:
		if int(m.get("slot", -1)) == s:
			return m
	return {}


func room_state() -> String:
	return room_st


func setup_seats() -> Array[Dictionary]:
	return seats if room_st == "setup" else ([] as Array[Dictionary])


func claim(k: int) -> void:
	calls.append(["claim", k])


func local_ips() -> PackedStringArray:
	return ips


func has_lan() -> bool:
	return lan


func send(kind: int, body: Dictionary, to_slot: int = -1) -> bool:
	calls.append(["send", kind, body, to_slot])
	return is_online()


func send_pose(p: Dictionary, stop: bool) -> void:
	calls.append(["send_pose", p, stop])


func set_where(where: StringName) -> void:
	calls.append(["set_where", String(where)])


func set_pick(fac: String) -> void:
	calls.append(["set_pick", fac])
	for m in member_list:
		if int(m.get("slot", -1)) == slot:
			m["pick"] = fac


func poll() -> void:
	pass


## Test helper: the calls of one method, in order.
func calls_of(method: String) -> Array:
	var out := []
	for c: Array in calls:
		if c[0] == method:
			out.append(c)
	return out


func _set_state(s: StringName) -> void:
	if s == st:
		return
	st = s
	state_changed.emit(s)
