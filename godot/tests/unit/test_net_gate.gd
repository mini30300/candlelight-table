extends "res://tests/testing.gd"
## NetGate (NET_SPEC §3, §10): the version-gate matrix (each key alone, priority order, a reconnecting nid is never
## full), is_private on every range plus public, carrier-NAT and malformed addresses, parse_ip, check_beacon.
## Review: NetSession's LAN detection from a list of interfaces (mobile data, VPN skipped; Wi-Fi first; carrier NAT is
## not a LAN), pure.
## Round E (CAMPAIGN_SPEC §6.1): the VPN ranges (Hamachi 25/8, Radmin VPN 26/8, Tailscale 100.64/10) by vector, is_private
## unchanged for them, peer_allowed (a VPN peer only when this device is on the same VPN) and check_hello's my_ips.


func _hello() -> Dictionary:
	return {"g": "candlelight", "np": NetProto.VERSION, "app": Version.APP_VER, "rules": Version.RULES_V,
		"data": Version.DATA_HASH, "nm": "เพื่อน", "nid": "0123456789abcdef"}


func _key(h: Dictionary, n := 1, mx := 6, ip := "192.168.1.20", known := false, closing := false) -> String:
	return str(NetGate.check_hello(h, n, mx, ip, known, closing)["key"])


func test_pass() -> void:
	assert_eq(NetGate.check_hello(_hello(), 1, 6, "192.168.1.20", false), {"key": "", "args": {}}, "a matching hello passes")
	assert_eq(_key(_hello(), 1, 6, "127.0.0.1"), "", "loopback is private")


func test_each_key_alone() -> void:
	assert_eq(_key(_hello(), 1, 6, "8.8.8.8"), "not_lan", "public address")
	var h := _hello()
	h["g"] = "other"
	assert_eq(_key(h), "wrong_game", "another game")
	assert_eq(_key({}), "wrong_game", "a hello that did not decode")
	h = _hello()
	h["np"] = 2
	var r := NetGate.check_hello(h, 1, 6, "10.0.0.2", false)
	assert_eq(r, {"key": "wrong_net", "args": {"host": NetProto.VERSION, "mine": 2}}, "another protocol version")
	h = _hello()
	h["app"] = "x"
	r = NetGate.check_hello(h, 1, 6, "10.0.0.2", false)
	assert_eq(r, {"key": "wrong_app", "args": {"host": Version.APP_VER, "mine": "x"}}, "another app version, both strings")
	h = _hello()
	h["rules"] = Version.RULES_V + 1
	r = NetGate.check_hello(h, 1, 6, "10.0.0.2", false)
	assert_eq(r, {"key": "wrong_rules", "args": {"host": Version.RULES_V, "mine": Version.RULES_V + 1}}, "another rules version")
	h = _hello()
	h["data"] = "f".repeat(64)
	assert_eq(_key(h), "wrong_rules", "another data hash")
	h = _hello()
	h["nid"] = "XYZ"
	assert_eq(_key(h), "wrong_game", "a malformed nid")
	h = _hello()
	h["nm"] = " \n "
	assert_eq(_key(h), "wrong_game", "an empty name")
	r = NetGate.check_hello(_hello(), 6, 6, "10.0.0.2", false)
	assert_eq(r, {"key": "full", "args": {"n": 6, "max": 6}}, "a full room")
	assert_eq(_key(_hello(), 1, 6, "10.0.0.2", false, true), "closing", "the host is closing")


func test_priority_and_reconnect() -> void:
	var h := _hello()
	h["np"] = 9
	h["app"] = "x"
	h["rules"] = 1
	assert_eq(_key(h, 6, 6, "8.8.8.8"), "not_lan", "not_lan wins over everything")
	assert_eq(_key(h, 6, 6), "wrong_net", "then the protocol")
	h["np"] = NetProto.VERSION
	assert_eq(_key(h, 6, 6), "wrong_app", "then the app")
	h["app"] = Version.APP_VER
	assert_eq(_key(h, 6, 6), "wrong_rules", "then the rules")
	assert_eq(_key(_hello(), 6, 6, "10.0.0.2", false, true), "full", "full before closing")
	assert_eq(_key(_hello(), 6, 6, "10.0.0.2", true), "", "a reconnecting nid is never full")
	assert_eq(NetGate.KEYS, ["not_lan", "wrong_game", "wrong_net", "wrong_app", "wrong_rules", "full", "closing"], "KEYS in check order")


func test_is_private() -> void:
	var yes := ["10.0.0.1", "10.255.255.255", "172.16.0.1", "172.31.255.254", "192.168.0.1", "192.168.255.255",
		"169.254.1.1", "127.0.0.1", "127.8.9.10", "::1", "fe80::1", "FE80::abcd:1", "febf::1", "fc00::1", "fd12:3456::1",
		"::ffff:192.168.1.5", " 192.168.1.5 "]
	var no := ["8.8.8.8", "172.15.255.255", "172.32.0.1", "192.169.0.1", "100.64.0.1", "100.127.255.255", "11.0.0.1",
		"192.0.2.2", "2001:db8::1", "fec0::1", "::ffff:8.8.8.8", "", "localhost", "256.1.1.1", "1.2.3", "a.b.c.d",
		"192.168.1.5.6", "-1.0.0.0", "10.0.0.01x", "::g", "example.com"]
	var bad := []
	for ip: String in yes:
		if not NetGate.is_private(ip):
			bad.append(ip)
	assert_eq(bad, [], "every private range of §10 is private")
	bad = []
	for ip: String in no:
		if NetGate.is_private(ip):
			bad.append(ip)
	assert_eq(bad, [], "public, carrier-NAT, documentation and malformed addresses are not")


func test_parse_ip() -> void:
	assert_eq(NetGate.parse_ip("192.168.1.5"), {"ip": "192.168.1.5", "port": 0}, "plain address")
	assert_eq(NetGate.parse_ip("192.168.1.5:24680"), {"ip": "192.168.1.5", "port": 24680}, "with a port")
	assert_eq(NetGate.parse_ip("  10.0.0.7  "), {"ip": "10.0.0.7", "port": 0}, "spaces around are trimmed")
	for t: String in ["999.1.1.1", "a.b.c.d", "example.com", "192.168.1.5:0", "192.168.1.5:70000", "192.168.1.5:",
			"192.168.1", "192.168.1.5:80:80", "192.168. 1.5", "::1", "", "1.2.3.4/24", "+1.2.3.4", "192.168.1.5:8a"]:
		assert_eq(NetGate.parse_ip(t), {}, "refused: '%s'" % t)


func test_check_beacon() -> void:
	var b := {"g": "candlelight", "np": NetProto.VERSION, "app": Version.APP_VER, "rules": Version.RULES_V,
		"data": Version.DATA_HASH.left(12), "n": 2, "max": 6}
	assert_eq(NetGate.check_beacon(b)["key"], "", "a matching beacon is ok")
	var c := b.duplicate()
	c["np"] = 2
	assert_eq(NetGate.check_beacon(c)["key"], "wrong_net", "protocol")
	c = b.duplicate()
	c["app"] = "ใหม่ 0.1"
	assert_eq(NetGate.check_beacon(c), {"key": "wrong_app", "args": {"host": "ใหม่ 0.1", "mine": Version.APP_VER}}, "app")
	c = b.duplicate()
	c["data"] = "000000000000"
	assert_eq(NetGate.check_beacon(c)["key"], "wrong_rules", "data")
	c = b.duplicate()
	c["n"] = 6
	assert_eq(NetGate.check_beacon(c), {"key": "full", "args": {"n": 6, "max": 6}}, "full")


func test_lan_detection_from_interfaces() -> void:
	var phone_wifi := [{"name": "rmnet_data0", "friendly": "rmnet_data0", "addresses": ["10.12.3.4"]},
		{"name": "wlan0", "friendly": "wlan0", "addresses": ["192.168.1.37", "fe80::1"]},
		{"name": "lo", "friendly": "lo", "addresses": ["127.0.0.1"]}]
	var a := NetSession.lan_from(phone_wifi)
	assert_eq(NetSession.private_ips(a), PackedStringArray(["192.168.1.37"]), "a phone on Wi-Fi lists its Wi-Fi IP, not the mobile-data 10.x")
	assert_true(NetSession.lan_ok(a), "and has a LAN")
	var phone_data := [{"name": "rmnet_data0", "addresses": ["10.12.3.4"]}, {"name": "v4-rmnet_data0", "addresses": ["192.0.0.4"]},
		{"name": "ccmni1", "addresses": ["100.70.1.2"]}]
	a = NetSession.lan_from(phone_data)
	assert_eq(NetSession.private_ips(a), PackedStringArray(), "mobile data only: no IP to show")
	assert_false(NetSession.lan_ok(a), "and no LAN (no_lan)")
	assert_false(NetSession.lan_ok(NetSession.lan_from([{"name": "wlan0", "addresses": ["100.64.9.9"]}])), "carrier NAT on Wi-Fi is not a LAN")
	var pc := [{"name": "{guid-1}", "friendly": "vEthernet (WSL)", "addresses": ["172.28.0.1"]},
		{"name": "{guid-2}", "friendly": "Wi-Fi", "addresses": ["192.168.0.12"]},
		{"name": "tun0", "friendly": "tun0", "addresses": ["10.8.0.2"]}]
	assert_eq(NetSession.private_ips(NetSession.lan_from(pc)), PackedStringArray(["192.168.0.12", "172.28.0.1"]),
		"a PC lists its Wi-Fi first, the virtual adapter after, the VPN not at all")
	assert_true(NetSession.lan_ok(NetSession.lan_from([{"name": "eth0", "addresses": ["192.0.2.2"]}])), "a public-range LAN still counts as a LAN (the sandbox)")


func test_vpn_range_vectors() -> void:
	var want := {"25.1.2.3": "hamachi", "25.0.0.0": "hamachi", "25.255.255.255": "hamachi", "26.10.0.5": "radmin",
		"100.64.0.1": "tailscale", "100.127.255.254": "tailscale", "100.100.100.100": "tailscale",
		"::ffff:25.1.2.3": "hamachi", " 26.0.0.1 ": "radmin", "::FFFF:100.64.0.1": "tailscale",
		"100.63.255.255": "", "100.128.0.0": "", "24.255.255.255": "", "27.0.0.1": "", "25.0.0": "", "": "",
		"25.1.2.256": "", "025.1.2.3.4": "", "192.168.1.2": "", "10.25.0.1": "", "8.8.8.8": "", "fe80::25": "",
		"25.a.b.c": "", "::ffff:8.8.8.8": ""}
	var bad := []
	for ip: String in want:
		if NetGate.vpn_range(ip) != want[ip]:
			bad.append("%s -> %s (want %s)" % [ip, NetGate.vpn_range(ip), want[ip]])
		if NetGate.is_vpn(ip) != (want[ip] != ""):
			bad.append("is_vpn " + ip)
	assert_eq(bad, [], "vpn_range sorts every vector into its range")
	for ip in ["25.1.2.3", "26.10.0.5", "100.64.0.1", "100.127.255.254", "::ffff:25.1.2.3"]:
		assert_false(NetGate.is_private(ip), "is_private is unchanged: %s is not private (discovery keeps ignoring it)" % ip)
	assert_eq(NetGate.vpn_name("hamachi"), "Hamachi", "Hamachi's name")
	assert_eq(NetGate.vpn_name("radmin"), "Radmin VPN", "Radmin VPN's name")
	assert_eq(NetGate.vpn_name("tailscale"), "Tailscale", "Tailscale's name")
	assert_eq(NetGate.vpn_name("x"), "", "an unknown range has no name")
	assert_eq(NetGate.VPN_RANGES.size(), 3, "three VPN ranges")
	assert_true(NetGate.LOCAL_KEYS.has("no_vpn"), "no_vpn is a local key")


func test_peer_allowed() -> void:
	var none := PackedStringArray()
	var ham := PackedStringArray(["25.9.9.9"])
	var both := PackedStringArray(["26.1.1.1", "100.80.0.2"])
	# [remote, my_ips, allowed]
	var rows := [["192.168.1.20", none, true], ["10.0.0.2", ham, true], ["127.0.0.1", none, true],
		["25.1.2.3", none, false], ["25.1.2.3", ham, true], ["25.1.2.3", both, false],
		["26.4.4.4", ham, false], ["26.4.4.4", both, true], ["100.64.0.1", both, true], ["100.64.0.1", ham, false],
		["8.8.8.8", ham, false], ["8.8.8.8", both, false], ["100.63.0.1", both, false], ["::ffff:25.1.2.3", ham, true],
		["", ham, false], ["25.1.2", ham, false]]
	var bad := []
	for r: Array in rows:
		if NetGate.peer_allowed(str(r[0]), r[1]) != bool(r[2]):
			bad.append("%s with %s" % [r[0], str(r[1])])
	assert_eq(bad, [], "peer_allowed: private always; a VPN address only when this device is on the same VPN; public never")


func test_check_hello_with_vpn() -> void:
	var ham := PackedStringArray(["25.9.9.9"])
	assert_eq(NetGate.check_hello(_hello(), 1, 6, "25.1.2.3", false, false, ham), {"key": "", "args": {}},
		"a Hamachi friend passes when the host is on Hamachi")
	assert_eq(str(NetGate.check_hello(_hello(), 1, 6, "25.1.2.3", false)["key"]), "not_lan",
		"without my_ips (old callers) a Hamachi address is still not_lan")
	assert_eq(str(NetGate.check_hello(_hello(), 1, 6, "26.1.2.3", false, false, ham)["key"]), "not_lan",
		"a Radmin address is not_lan for a host on Hamachi only")
	var h := _hello()
	h["app"] = "x"
	assert_eq(str(NetGate.check_hello(h, 1, 6, "25.1.2.3", false, false, ham)["key"]), "wrong_app",
		"past the address gate, a VPN friend meets the same version gate")
	assert_eq(str(NetGate.check_hello(_hello(), 6, 6, "25.1.2.3", false, false, ham)["key"]), "full", "and the same full room")
