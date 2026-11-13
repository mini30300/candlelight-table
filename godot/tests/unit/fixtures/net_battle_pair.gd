extends RefCounted
## In-memory lockstep room for the BATTLE tests (NET_SPEC §12.2 test_lockstep, §12.4 battle screen): one host
## NetMatchRunner and client runners joined by a transport that delivers in order. Every message goes through
## NetProto.encode → decode first (so every body the battle code sends passes NET-CORE's schema). Hooks: `cut` (slots
## whose messages are dropped both ways), `tamper` (Callable(to_slot, kind, body) -> body, before delivery).
## No sockets, no Node.

var host: NetMatchRunner
var clients: Dictionary = {}        # slot -> NetMatchRunner
var plan: Dictionary = {}           # host plan (NetSeats.build)
var wire_plan: Dictionary = {}      # START.plan after encode/decode
var owners: Array = []
var gen := 1
var queue: Array = []               # [to_slot, from_slot, kind, body]
var cut: Dictionary = {}
var tamper: Callable
var bad: Array = []                 # [kind, error] of messages that failed the codec
var log: Array = []                 # [from, to, kind, body] of every delivered message
var host_states: Dictionary = {}
var events: Dictionary = {}         # slot -> every event the client's step() handed out


## members: [{slot, nm}] (slot 0 = host); choice: NetSeats choice with owners; dice: slot -> dice seed
func make(choice: Dictionary, members: Array, dice: Dictionary, p_gen: int = 1) -> bool:
	gen = p_gen
	plan = NetSeats.build(choice, members)
	if not (plan["errors"] as PackedStringArray).is_empty():
		bad.append(["plan", str(plan["errors"])])
		return false
	owners = plan["owners"]
	var start_body := {"gen": gen, "plan": Lockstep.plan_wire(plan), "owners": owners}
	var m := NetProto.decode(NetProto.encode(NetProto.START, start_body))
	if m.has("error"):
		bad.append([NetProto.START, str(m["error"])])
		return false
	wire_plan = m["body"]["plan"]
	host = NetMatchRunner.host(plan, Lockstep.new(sender(0), true, 0, gen, owners), int(dice.get(0, 0)))
	host.start()
	for mem: Dictionary in members:
		var s := int(mem["slot"])
		if s == 0:
			continue
		add_client(s, int(dice.get(s, 0)))
	return true


## A client runner for slot s (seat from owners, -1 = spectator), built from the START plan and started.
## started = false: built like NetBattleLink does for a RESYNC (a rejoin): not started, the RESYNC rebuilds it.
func add_client(s: int, dice_seed: int, started: bool = true) -> NetMatchRunner:
	var c := NetMatchRunner.client(wire_plan, owners.find(s), Lockstep.new(sender(s), false, s, gen, owners), dice_seed)
	if started:
		c.start()
	clients[s] = c
	return c


func sender(from_slot: int) -> Callable:
	return func(kind: int, body: Dictionary, to_slot: int) -> void: post(from_slot, kind, body, to_slot)


func post(from_slot: int, kind: int, body: Dictionary, to_slot: int) -> void:
	var bytes := NetProto.encode(kind, body)
	if bytes.is_empty():
		bad.append([kind, "encode " + str(NetProto.check(kind, body).get("error", ""))])
		return
	var m := NetProto.decode(bytes)
	if m.has("error"):
		bad.append([kind, str(m["error"])])
		return
	var b: Dictionary = m["body"]
	if from_slot == 0:
		var targets: Array = clients.keys() if to_slot < 0 else [to_slot]
		for t: int in targets:
			queue.append([t, 0, kind, b.duplicate(true)])
	else:
		queue.append([0, from_slot, kind, b])


## Delivers every queued message in order (messages sent while delivering are delivered too). Returns the count.
func deliver() -> int:
	var n := 0
	while not queue.is_empty():
		var q: Array = queue.pop_front()
		var to: int = q[0]
		var from: int = q[1]
		if cut.has(to) or cut.has(from):
			continue
		var body: Dictionary = q[3]
		if tamper.is_valid():
			body = tamper.call(to, int(q[2]), body)
		log.append([from, to, int(q[2]), body])
		if to == 0:
			host.receive(int(q[2]), body, from)
		elif clients.has(to):
			(clients[to] as NetMatchRunner).receive(int(q[2]), body, 0)
		n += 1
	return n


## Pumps everyone until the host's game is over and every connected client is over (or stopped by a desync), or
## until `stop` returns true, or max_rounds rounds pass. Returns "over" | "stop" | "rounds".
func run(max_rounds: int = 20000, stop: Callable = Callable()) -> String:
	for i: int in max_rounds:
		var moved := false
		for j: int in 50:
			var r := host.step()
			var st := str(r["state"])
			host_states[st] = int(host_states.get(st, 0)) + 1
			if st != "acted":
				break
			moved = true
		if deliver() > 0:
			moved = true
		for s: int in clients:
			if cut.has(s):
				continue
			var c: NetMatchRunner = clients[s]
			for j: int in 20:
				var n0 := c.acts().size()
				var r := c.step()
				if not events.has(s):
					events[s] = []
				(events[s] as Array).append_array(r["events"])
				if str(r["state"]) != "acted" and c.acts().size() == n0:
					break
				moved = true
			if deliver() > 0:
				moved = true
		if stop.is_valid() and stop.call():
			return "stop"
		if host.is_over() and queue.is_empty():
			var all_done := true
			for s: int in clients:
				var c: NetMatchRunner = clients[s]
				if not cut.has(s) and not c.is_over() and c.sync_state() != &"desync_final":
					all_done = false
			if all_done:
				return "over"
		if not moved and str(host.step()["state"]) == "stuck":
			return "stuck"
	return "rounds"


## Messages of one kind that were delivered (optionally only those to slot `to`).
func delivered(kind: int, to: int = -2) -> Array:
	var out: Array = []
	for e: Array in log:
		if int(e[2]) == kind and (to == -2 or int(e[1]) == to):
			out.append(e[3])
	return out
