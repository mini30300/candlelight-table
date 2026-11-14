extends "res://tests/testing.gd"
## Round E, friends in other houses over a VPN (CAMPAIGN_SPEC §6.2, NET_SPEC §18): NetSession.vpn_from on fake interface
## lists (Hamachi 25.x and Radmin VPN 26.x on any card; Tailscale 100.64/10 on its own adapter but never on a mobile-data
## or Wi-Fi card, where that range is the carrier's NAT), vpn_ips through itfs_override, join refusals no_vpn / not_lan /
## bad_ip before any socket, peer_ok (the host's address gate) and host() allowed with only a VPN address.
## No packet is ever sent to a VPN or public address: the accept path of join() is checked through peer_ok, which is
## the exact test join() uses. host() opens a test port on 0.0.0.0: skipped in the exported self-test.

var _tree: SceneTree
var _base := 0
var _made: Array[NetSession] = []

const HAMACHI_PC := [{"name": "{guid-1}", "friendly": "Wi-Fi", "addresses": ["192.168.1.40", "fe80::2"]},
	{"name": "{guid-2}", "friendly": "Hamachi", "addresses": ["25.33.44.55", "2620:9b::1921:2c37"]},
	{"name": "lo", "friendly": "lo", "addresses": ["127.0.0.1"]}]


func setup() -> void:
	_tree = Engine.get_main_loop() as SceneTree
	_base = 34000 + (OS.get_process_id() % 3000) * 2


func _cfg(name: String) -> String:
	var dir := OS.get_environment("TEST_OUT")
	if dir == "":
		dir = ProjectSettings.globalize_path("res://tests/out")
	DirAccess.make_dir_recursive_absolute(dir)
	return dir.path_join("net_vpn_%s_%d.cfg" % [name, OS.get_process_id()])


## a session not in the tree (join refusals never touch a socket)
func _bare(itfs: Array) -> NetSession:
	var n := NetSession.new()
	n.make_link = false
	n.cfg_file = _cfg("bare")
	n.itfs_override = itfs
	return n


func test_vpn_from_fake_interfaces() -> void:
	var itfs := [{"name": "rmnet_data0", "friendly": "rmnet_data0", "addresses": ["100.70.1.2"]},
		{"name": "tun0", "friendly": "tun0", "addresses": ["100.88.7.6"]},
		{"name": "{guid-h}", "friendly": "Hamachi", "addresses": ["25.1.2.3"]},
		{"name": "ham0", "friendly": "ham0", "addresses": ["25.4.5.6"]},
		{"name": "{guid-r}", "friendly": "Radmin VPN", "addresses": ["26.10.0.5"]},
		{"name": "wlan0", "friendly": "wlan0", "addresses": ["192.168.1.37", "100.64.9.9"]},
		{"name": "ccmni1", "addresses": ["100.100.1.1"]},
		{"name": "tailscale0", "friendly": "tailscale0", "addresses": ["100.101.102.103", "fd7a:115c:a1e0::1"]},
		{"name": "utun4", "friendly": "utun4", "addresses": ["100.90.0.1"]},
		{"name": "{guid-t}", "friendly": "Tailscale", "addresses": ["100.65.0.2"]},
		{"name": "{guid-e}", "friendly": "Ethernet", "addresses": ["100.66.0.3"]},
		{"name": "lo", "addresses": ["127.0.0.1", "::1"]}]
	var got := NetSession.vpn_from(itfs)
	var ips := []
	for v: Dictionary in got:
		ips.append(str(v["ip"]))
	assert_eq(ips, ["100.88.7.6", "25.1.2.3", "25.4.5.6", "26.10.0.5", "100.101.102.103", "100.90.0.1", "100.65.0.2"],
		"VPN addresses in card order: rmnet / ccmni 100.x skipped, Wi-Fi and Ethernet 100.64.x (carrier NAT) skipped, "
		+ "Android tun0, Hamachi, ham0, Radmin VPN, tailscale0, utun and the Windows Tailscale adapter kept")
	# "cgnat" added in the round E fix: rows now say whether a Tailscale address shares 100.64/10 with the carrier
	assert_eq(got[1], {"ip": "25.1.2.3", "vpn": "hamachi", "name": "Hamachi", "cgnat": false},
		"a row carries the range and the card's friendly name")
	assert_true(bool(got[0]["cgnat"]), "tun0 100.88.x next to a carrier 100.70.x on rmnet is flagged cgnat")
	assert_eq(str(got[3]["vpn"]), "radmin", "26.x is Radmin VPN")
	assert_eq(str(got[0]["vpn"]), "tailscale", "100.88.x on tun0 is Tailscale")
	assert_eq(NetSession.vpn_from([{"name": "v4-rmnet_data0", "addresses": ["25.1.1.1"]}]).size(), 1,
		"25.x counts on any card (no carrier hands out 25/8)")
	assert_eq(NetSession.vpn_from([{"name": "clat4", "addresses": ["100.64.0.4"]}, {"name": "pdp0", "addresses": ["100.64.0.5"]},
		{"name": "wwan0", "addresses": ["100.64.0.6"]}, {"name": "ppp0", "addresses": ["100.64.0.7"]}]).size(), 0,
		"100.64/10 on clat / pdp / wwan / ppp cards is never Tailscale")
	assert_eq(NetSession.vpn_from([]), [], "no cards, no VPN")


## review fix: a phone on carrier NAT (100.64/10 on rmnet) with a VPN on tun0 must not accept its carrier neighbours
func test_cgnat_phone_gate() -> void:
	var n := _bare([{"name": "rmnet_data0", "addresses": ["100.70.1.2"]}, {"name": "wlan0", "addresses": ["192.168.1.5"]},
		{"name": "tun0", "addresses": ["100.88.7.6"]}])
	assert_eq(n.vpn_ips(), PackedStringArray(["100.88.7.6"]), "the Tailscale address is still listed (it can join out)")
	assert_eq(n.vpn_ips(true), PackedStringArray(), "but it is not part of the host's gate")
	assert_false(n.peer_ok("100.70.9.9"), "a carrier neighbour 100.70.x is refused")
	assert_false(n.peer_ok("100.88.1.1"), "so is any 100.64/10 address while the carrier is on carrier NAT")
	assert_true(n.peer_ok("192.168.1.9"), "the Wi-Fi friend still passes")
	var g := NetGate.check_hello({"g": NetProto.GAME}, 1, 4, "100.70.9.9", false, false, n.vpn_ips(true))
	assert_eq(str(g["key"]), "not_lan", "the hello gate stops the carrier neighbour at not_lan")
	# join() tests exactly this before opening a socket (no packet is sent here)
	assert_true(NetGate.peer_allowed("100.101.1.1", n.vpn_ips()), "joining a Tailscale friend (outbound) is allowed")
	# the same phone on a carrier that hands out 10.x keeps Tailscale in the gate
	n.itfs_override = [{"name": "rmnet_data0", "addresses": ["10.20.30.40"]}, {"name": "tun0", "addresses": ["100.88.7.6"]}]
	assert_eq(n.vpn_ips(true), PackedStringArray(["100.88.7.6"]), "no carrier NAT: Tailscale stays in the gate")
	assert_true(n.peer_ok("100.101.1.1"), "and a tailnet friend passes")
	# Hamachi / Radmin are unaffected by carrier NAT
	n.itfs_override = [{"name": "rmnet_data0", "addresses": ["100.70.1.2"]}, {"name": "ham0", "addresses": ["25.1.1.1"]}]
	assert_eq(n.vpn_ips(true), PackedStringArray(["25.1.1.1"]), "Hamachi on a carrier-NAT phone stays in the gate")
	n.free()


func test_vpn_ips_through_override() -> void:
	var n := _bare(HAMACHI_PC)
	assert_eq(n.vpn_ips(), PackedStringArray(["25.33.44.55"]), "a PC on Wi-Fi and Hamachi reports its Hamachi IPv4 only")
	assert_eq(n.local_ips(), PackedStringArray(["192.168.1.40"]), "and its LAN IP list is unchanged (no 25.x in it)")
	assert_true(n.has_lan(), "it has a LAN")
	n.itfs_override = [{"name": "ham0", "addresses": ["25.1.1.1"]}, {"name": "{x}", "friendly": "Hamachi", "addresses": ["25.1.1.1"]}]
	assert_eq(n.vpn_ips(), PackedStringArray(["25.1.1.1"]), "the same address on two cards is listed once")
	n.free()


func test_join_refusals() -> void:
	var n := _bare([{"name": "wlan0", "addresses": ["192.168.1.37"]}])
	var got: Array = []
	n.refused.connect(func(k: String, a: Dictionary) -> void: got.append([k, a]))
	assert_eq(n.join("25.1.2.3"), ERR_UNAUTHORIZED, "a Hamachi IP without Hamachi on this device is refused")
	assert_eq(n.join("26.0.0.9:24680"), ERR_UNAUTHORIZED, "a Radmin VPN IP (with a port) too")
	assert_eq(n.join("100.64.0.1"), ERR_UNAUTHORIZED, "a Tailscale IP too")
	assert_eq(n.join("8.8.8.8"), ERR_UNAUTHORIZED, "a public IP is refused")
	assert_eq(n.join("25.1.2"), ERR_INVALID_PARAMETER, "a broken IP is a bad ip")
	assert_eq(got, [["no_vpn", {"vpn": "Hamachi"}], ["no_vpn", {"vpn": "Radmin VPN"}], ["no_vpn", {"vpn": "Tailscale"}],
		["not_lan", {}], ["bad_ip", {}]], "no_vpn names the program; public stays not_lan")
	assert_eq(str(n.state()), "off", "no refusal changes the state")
	# on Hamachi, a Radmin VPN address is still no_vpn, and a Hamachi address passes the gate
	n.itfs_override = HAMACHI_PC
	got.clear()
	assert_eq(n.join("26.0.0.9"), ERR_UNAUTHORIZED, "on Hamachi only, a Radmin VPN IP is refused")
	assert_eq(got, [["no_vpn", {"vpn": "Radmin VPN"}]], "with no_vpn Radmin VPN")
	assert_true(n.peer_ok("25.1.2.3"), "on Hamachi a 25.x host passes join's address test (peer_ok)")
	assert_true(n.peer_ok("192.168.1.9"), "a LAN host still passes")
	assert_false(n.peer_ok("8.8.8.8"), "a public host never passes")
	n.free()


func test_host_gate_peer_ok() -> void:
	var n := _bare(HAMACHI_PC)
	assert_true(n.peer_ok("25.200.1.1"), "a host on Hamachi lets a 25.x friend knock")
	assert_false(n.peer_ok("26.1.1.1"), "but not a Radmin VPN address")
	assert_false(n.peer_ok("100.64.1.1"), "nor a Tailscale address")
	assert_true(n.peer_ok("10.0.0.9"), "a LAN friend always")
	n.itfs_override = [{"name": "wlan0", "addresses": ["192.168.1.37"]}]
	assert_false(n.peer_ok("25.200.1.1"), "a host without Hamachi refuses 25.x (not_lan)")
	n.free()


func test_host_with_vpn_only() -> void:
	if OS.has_feature("template"):
		print("skip  socket test in the exported self-test")
		return
	# Tailscale on a phone with mobile data only: no LAN, but a VPN address → hosting is allowed
	var ts := [{"name": "rmnet_data0", "addresses": ["10.20.30.40"]}, {"name": "tun0", "addresses": ["100.88.1.2"]}]
	var h := _mk("VpnHost", ts)
	var got: Array = []
	h.refused.connect(func(k: String, a: Dictionary) -> void: got.append([k, a]))
	assert_false(h.has_lan(), "the fake phone has no LAN")
	var e := FAILED
	for i: int in 20:
		h.ports = {"game": _base, "disc": _base + 1}
		e = h.host()
		if e == OK:
			break
		_base += 2
		got.clear()
	assert_eq(e, OK, "host() works with only a VPN address (%s)" % str(got))
	assert_eq(str(h.state()), "hosting", "and the room is open")
	h.leave()
	# mobile data only (carrier NAT 100.x on rmnet): still no_lan
	var m := _mk("NoLan", [{"name": "rmnet_data0", "addresses": ["100.70.1.1"]}])
	got.clear()
	m.refused.connect(func(k: String, a: Dictionary) -> void: got.append([k, a]))
	assert_eq(m.host(), ERR_UNCONFIGURED, "mobile data only cannot host")
	assert_eq(got, [["no_lan", {}]], "with no_lan")
	_cleanup()


func _mk(name: String, itfs: Array) -> NetSession:
	var n := NetSession.new()
	n.name = name
	n.make_link = false
	n.cfg_file = _cfg(name)
	n.itfs_override = itfs
	n.probe = PackedStringArray(["127.0.0.1"])
	_tree.set_multiplayer(SceneMultiplayer.new(), NodePath("/root/" + name))
	_tree.root.add_child(n)
	_made.append(n)
	return n


func _cleanup() -> void:
	for n: NetSession in _made.duplicate():
		if is_instance_valid(n):
			n.leave()
	for n: NetSession in _made.duplicate():
		DirAccess.remove_absolute(n.cfg_file)
		var path := n.get_path()
		if n.is_inside_tree():
			_tree.root.remove_child(n)
		n.free()
		_tree.set_multiplayer(null, path)
	_made.clear()
	DirAccess.remove_absolute(_cfg("bare"))
