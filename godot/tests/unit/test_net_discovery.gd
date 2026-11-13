extends "res://tests/testing.gd"
## NetDiscovery (NET_SPEC §1.4): beacon size with a long Thai name, parse refusing junk, oversize, another game and
## public sources, mismatched versions greyed with the gate's key, dedupe by host token (the LAN IP kept), a host on
## the test discovery port answering a query sent to probe 127.0.0.1, and rows expiring after 4 s of fake time.
## Opens a UDP socket on a test port: skipped in the exported self-test.


func _info() -> Dictionary:
	return {"app": Version.APP_VER, "rules": Version.RULES_V, "data": Version.DATA_HASH, "port": 24680,
		"nm": "ก".repeat(20), "n": 2, "max": 6, "st": "deck", "t": "a1b2c3d4"}


func _sockets_ok() -> bool:
	return not OS.has_feature("template")


func test_make_beacon() -> void:
	var b := NetDiscovery.make_beacon(_info())
	assert_false(b.is_empty(), "a beacon with a 20-character Thai name is made")
	assert_true(b.size() <= 512, "and is at most 512 bytes (%d)" % b.size())
	var d: Dictionary = JSON.parse_string(b.get_string_from_utf8())
	assert_eq(d.get("data"), Version.DATA_HASH.left(12), "data carries the first 12 characters of DATA_HASH")
	assert_eq(int(d.get("np")), NetProto.VERSION, "np carries the protocol version")
	var p := NetDiscovery.parse(b, "192.168.1.9")
	assert_eq(p.get("k"), "b", "it parses as a beacon")
	assert_true(p.get("ok"), "matching versions are ok")
	assert_eq(p.get("nm"), "ก".repeat(20), "the name survives")
	assert_eq(typeof(p.get("port")), TYPE_INT, "JSON numbers become ints")
	assert_eq(p.get("ip"), "192.168.1.9", "the sender's address is the row's IP")


func test_parse_refuses() -> void:
	var good := NetDiscovery.make_beacon(_info())
	assert_eq(NetDiscovery.parse(good, "8.8.8.8"), {}, "a public source is ignored")
	assert_eq(NetDiscovery.parse(good, "100.64.0.9"), {}, "a carrier-NAT source is ignored")
	assert_eq(NetDiscovery.parse("hello".to_utf8_buffer(), "10.0.0.2"), {}, "junk is ignored")
	assert_eq(NetDiscovery.parse(PackedByteArray([255, 254, 0, 1]), "10.0.0.2"), {}, "binary junk is ignored")
	var big := ("{\"g\":\"candlelight\",\"k\":\"q\",\"n\":\"%s\"}" % "a".repeat(600)).to_utf8_buffer()
	assert_eq(NetDiscovery.parse(big, "10.0.0.2"), {}, "an oversize packet is ignored")
	var other := JSON.stringify({"g": "minecraft", "k": "q", "np": 1, "n": "00000000"}).to_utf8_buffer()
	assert_eq(NetDiscovery.parse(other, "10.0.0.2"), {}, "another game is ignored")
	var frac := JSON.stringify({"g": "candlelight", "k": "b", "np": 1, "app": "a", "rules": 10.5, "data": "d",
		"port": 24680, "nm": "x", "n": 1, "max": 6, "st": "deck", "t": "t1"}).to_utf8_buffer()
	assert_eq(NetDiscovery.parse(frac, "10.0.0.2"), {}, "a fractional number is refused")
	var q := JSON.stringify({"g": "candlelight", "k": "q", "np": 1, "n": "0badf00d"}).to_utf8_buffer()
	assert_eq(NetDiscovery.parse(q, "127.0.0.1"), {"k": "q", "n": "0badf00d"}, "a query parses")


func test_mismatch_greyed() -> void:
	var info := _info()
	info["app"] = "ใหม่ 0.1"
	var p := NetDiscovery.parse(NetDiscovery.make_beacon(info), "192.168.1.9")
	assert_false(p.get("ok"), "another app version is not ok")
	assert_eq(p.get("why"), "wrong_app", "with the gate's key")
	info = _info()
	info["rules"] = 3
	p = NetDiscovery.parse(NetDiscovery.make_beacon(info), "192.168.1.9")
	assert_eq(p.get("why"), "wrong_rules", "another rules version")
	info = _info()
	info["n"] = 6
	p = NetDiscovery.parse(NetDiscovery.make_beacon(info), "192.168.1.9")
	assert_eq(p.get("why"), "full", "a full room")


func test_dedupe_and_expiry() -> void:
	var d := NetDiscovery.new()
	var b := NetDiscovery.parse(NetDiscovery.make_beacon(_info()), "127.0.0.1")
	assert_true(d._upsert(b, 1000), "a new host is a change")
	var lan := NetDiscovery.parse(NetDiscovery.make_beacon(_info()), "192.168.1.9")
	d._upsert(lan, 1100)
	var b2 := NetDiscovery.parse(NetDiscovery.make_beacon(_info()), "127.0.0.1")
	d._upsert(b2, 1200)
	var rows := d.found()
	assert_eq(rows.size(), 1, "the same token from loopback and the LAN is one row")
	assert_eq(rows[0].get("ip"), "192.168.1.9", "the LAN address is kept")
	assert_false(rows[0].has("seen"), "rows do not leak the internal time stamp")
	var info := _info()
	info["t"] = "ffff0000"
	info["nm"] = "อีกห้อง"
	d._upsert(NetDiscovery.parse(NetDiscovery.make_beacon(info), "10.0.0.5"), 3000)
	assert_eq(d.found().size(), 2, "another token is another row")
	assert_eq(d.found().map(func(r: Dictionary) -> String: return r["t"]), ["a1b2c3d4", "ffff0000"], "rows sorted by name")
	# poll without a socket does nothing; expire by hand through a socket-less instance's poll path
	d._udp = PacketPeerUDP.new()
	d._mode = NetDiscovery.Mode.HOST
	assert_true(d.poll(5300), "rows not seen for over 4 s drop out")
	assert_eq(d.found().size(), 1, "only the fresh row is left")
	assert_eq(d.found()[0].get("t"), "ffff0000", "the one seen at 3 s")
	d._udp = null


func test_loopback_query_beacon() -> void:
	if not _sockets_ok():
		print("skip  socket test in the exported self-test")
		return
	var base := 30000 + (OS.get_process_id() % 4000) * 2
	var host := NetDiscovery.new()
	var port := base + 1
	var tries := 0
	while not host.start_host(port, func() -> PackedByteArray:
			var i := _info()
			i["port"] = port - 1
			return NetDiscovery.make_beacon(i)) and tries < 20:
		port += 2
		tries += 1
	assert_true(host.is_on(), "a host binds the test discovery port %d" % port)
	var joiner := NetDiscovery.new()
	assert_true(joiner.start_find(port, PackedStringArray(["127.0.0.1"])), "a joiner binds a spare port")
	var t0 := Time.get_ticks_msec()
	var changed := false
	while Time.get_ticks_msec() - t0 < 200 and not changed:
		host.poll(Time.get_ticks_msec())
		changed = joiner.poll(Time.get_ticks_msec())
		OS.delay_msec(1)
	assert_true(changed, "the joiner's list changed within 200 ms (%d ms)" % (Time.get_ticks_msec() - t0))
	var rows := joiner.found()
	assert_eq(rows.size(), 1, "one room found")
	if rows.size() == 1:
		assert_eq(rows[0]["t"], "a1b2c3d4", "the host's token")
		assert_eq(rows[0]["port"], port - 1, "the game port from the beacon")
		assert_true(rows[0]["ok"], "versions ok")
	var second := NetDiscovery.new()
	assert_false(second.start_host(port, func() -> PackedByteArray: return PackedByteArray()), "a second host on the same port cannot bind")
	host.stop()
	joiner.stop()
	assert_false(host.is_on() or joiner.is_on(), "stop closes both sockets")


func test_rows_are_capped() -> void:
	var d := NetDiscovery.new()
	for i in 40:
		var b := NetDiscovery.parse(NetDiscovery.make_beacon({"nm": "ห้อง %d" % i, "port": 24680, "t": "%08x" % i}), "192.168.1.%d" % (i + 2))
		d._upsert(b, 1000)
	assert_eq(d.found().size(), NetDiscovery.MAX_ROWS, "at most %d rooms are listed (random-token beacons cannot flood the list)" % NetDiscovery.MAX_ROWS)
