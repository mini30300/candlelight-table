# Play with friends on the local network (ใหม่ 0.5) — build spec

Written 13 Nov 2026 for the new app (`godot/`), on branch `claude/multiplayer-wip` at 8509d88 (same tree as draft PR #27,
ใหม่ 0.4, the weapons arena). This branch is merged into `claude/new-session-fsucoo` by the lead later. Three builders
follow this file in parallel, in the same checkout, each on its own files (§11). It is the single source of truth for
names, paths, numbers, messages and contracts. Builders read it but do not edit it; a needed change goes back to whoever
runs the workflow, and differences found while building go into §17 (as built) at integration.

Everything in `LOBBY_SPEC.md` (flow, i18n §0.7, test rules §7.1), `SHIP_LOBBY_SPEC.md` (the deck), `ARENA_SPEC.md`
(the arena, the fade, §12.1 ground rules) and `R1_PORT_SPEC.md` (act codec §4, RNG streams §3, D8–D10) still holds unless
a section below changes it by name. `PLAN.md` R3 (online through the existing Worker) stays the plan for Claude seats and
for rooms shared with the old page; this round is a different, server-free path (§13.4).

**The owner's request (13 Nov), in short:** "ทำระบบเล่นกับเพื่อนเอาไว้เลยนะครับ" and, earlier, play with friends like
Minecraft: one player opens a room, friends join directly (on the same Wi-Fi no internet is needed); depend on an
outside server as little as possible, only for items later (accounts, inventory: R7). Today he asked whether the parts
can be built at the same time: yes, three builders in parallel (§11).

**For the owner, in Thai:** ที่ดาดฟ้ายานรบ เดินไปที่ "ประตูเทียบยาน" (หรือกดปุ่ม ออนไลน์ ที่หน้าแรก) จะเปิดหน้า "เล่นกับเพื่อน"
ใส่ชื่อตัวเอง แล้วเลือกได้สองทาง: กด "เปิดห้อง" เป็นเจ้าห้อง หรือรอให้รายชื่อห้องของเพื่อนที่อยู่ Wi-Fi เดียวกันขึ้นมาเองแล้วกด
"เข้าร่วม" (ถ้าห้องไม่ขึ้น ใส่ IP ที่หน้าจอของเจ้าห้องบอกไว้ได้) ไม่ต้องใช้อินเทอร์เน็ตและไม่ผ่านเซิร์ฟเวอร์ของเรา เข้าห้องแล้ว
จะเห็นไข่ของเพื่อนเดินอยู่บนดาดฟ้า มีชื่อลอยเหนือหัวและวงแหวนสีประจำตัว เจ้าห้องเดินไปโต๊ะรบ ตั้งเกมได้เหมือนเดิม แต่ละที่นั่ง
เลือกได้ว่าเป็นตัวเอง เพื่อนคนไหน หรือบอท กดเริ่มแล้วทุกเครื่องเข้าสนามพร้อมกัน แต่ละคนสั่งหน่วยของตัวเองในตาของทีมตัวเอง
บอทเล่นอยู่บนเครื่องเจ้าห้อง ทุกเครื่องคิดผลการรบเองจากคำสั่งชุดเดียวกัน และตรวจกันตลอดว่าผลตรงกัน ถ้าไม่ตรงจะขึ้นเตือนชัด ๆ
ไม่ปล่อยเงียบ ถ้าเพื่อนหลุด บอทจะเล่นแทนที่นั่งนั้นจนเขาต่อกลับเข้ามา ถ้าเจ้าห้องออก เกมจบสำหรับทุกคน แอปต้องเป็นรุ่นเดียวกัน
ทุกเครื่อง ไม่งั้นจะขึ้นบอกว่ารุ่นไม่ตรงกัน รอบนี้ยังไม่มีเล่นผ่านอินเทอร์เน็ตและยังไม่มีอารีน่าเล่นด้วยกัน (รอบหน้า §13–§14)

## 0. Decisions this spec fixes (do not re-decide)

| Topic | Decision |
| --- | --- |
| Model | **Host-authoritative peer group on the LAN.** One app is the host (ENet server); friends join it directly (ENet clients). No outside server, no internet needed. Up to **6 players** in a room (host + 5), the battle's `SeatPlan.MAX_SEATS`. |
| Transport | `ENetMultiplayerPeer` under the tree's `SceneMultiplayer`, **raw `send_bytes` messages with our own codec** (§2), never RPC (no node paths, no remote method calls). Version gate in `SceneMultiplayer`'s authentication phase (§3). |
| Finding rooms | **Query → beacon**: the joiner broadcasts a small UDP query from a spare port; each host answers to the sender's address with a beacon that carries name, size and versions (§1.4). Manual IP entry always works; the host shows its LAN IPs. |
| Battle | **Lockstep over the existing deterministic core**: only acts travel; every device runs `Battle.apply` on the same act list. The host orders every act (sequencer) and checks requests; bots run on the host and their acts travel like humans'. Digest checks at least every 8 acts; a mismatch is a loud error, a log line and a resync, never silent (§4). |
| Core and rules | **No change** to `core/` (apart from the `APP_VER` line), to `MatchRunner`, to act codes or to `RULES_V`/`DATA_HASH`/`PROTO`. The host's roller context comes from overriding `flush` in a `Battle` subclass (§4.10). |
| Disconnect | The host plays a dropped seat **with that seat's pid** (seat stays `bot = false`), and gives it back when the same player reconnects (§4.8). No new act code. |
| Host leaves | The game ends for everyone with a clear message; no host migration in round 1. |
| Deck presence | Visual only. Friends are **eggs** in their slot colour (one `MultiMesh` for all friends), rings in the existing `Rings` MultiMesh, names in **one 2D overlay** that also takes over the local "you" tag while online. Net cost +1 draw call; the deck targets stay 40 / 40 / 35 / **30** (§6.3). |
| Airlock | The docking airlock station (`online`, "ประตูเทียบยาน") opens the new online screen `ui/screens/lobby.tscn` (the name `LOBBY_SPEC` reserved for it). The main-menu Online button opens the deck and that screen. Neither says "เร็วๆ นี้" any more. |
| Arena | **Not online** in this round. A friend in the arena is shown as "อยู่ในอารีน่า" in the room list and is not drawn on the deck. |
| Chat | None in round 1. |
| Strings | Thai first, English pair for every new Thai string; Thai literals only under `ui/` (the lint scans `ui/` and `app/`); **no Thai under `net/`** (§7.3). |
| Release | `APP_VER` "ใหม่ 0.4" → **"ใหม่ 0.5"**, Thai note in `web/`; godot-only change, **no candlelight-server PR** in this round (§15). |

## 1. Architecture

### 1.1 Pieces and where they run

```
            ┌───────────── host device ─────────────┐        ┌──────── friend device ────────┐
 airlock UI │ lobby.tscn ─┐                         │        │ lobby.tscn ─┐                 │
 deck       │ hall_screen ─┼─► Net (NetSession) ◄────┼─ENet──►│ Net ◄──────┼─ hall_screen    │
 battle     │ battle_screen┘   │  NetDiscovery ◄─────┼─UDP────┤ NetDiscovery└─ battle_screen │
            │   NetMatchRunner(host) ─ Lockstep(host)│        │ NetMatchRunner(client)        │
            │   Battle.apply  (bots run here)        │        │ Battle.apply (no bots)        │
            └────────────────────────────────────────┘        └───────────────────────────────┘
```

- `Net` (autoload, `net/net_session.gd`, `class_name NetSession`): the only owner of sockets. States, members, names,
  versions, the codec, discovery, heartbeats. Knows nothing about rules or screens.
- The deck (`hall_screen`, `HallFriends`, `FriendTags`) sends and draws poses through `Net`.
- The battle (`NetBattleLink`, `NetMatchRunner`, `Lockstep`, `NetSeats`) sends and applies acts through `Net`.
- Clients talk only to the host (slot 0); the host relays poses and member lists. `SceneMultiplayer.server_relay = false`.

### 1.2 `NetSession` (autoload `Net`)

| Item | Value |
| --- | --- |
| Registration | `project.godot` `[autoload]` `Net="*res://net/net_session.gd"` (after `Clock`). Scripts that may run before autoloads (`-s` runners) reach it with `get_node_or_null(^"/root/Net")` and work without it. |
| Idle cost | Offline it does nothing: `set_process(false)`, no socket, no Timer. While online, the ENet poll is engine-side (`SceneTree` polls the multiplayer each frame); discovery and heartbeats run on one child `Timer` (0.25 s), never `_process`. |
| States (`StringName`) | `&"off"`, `&"finding"` (join list open, no connection), `&"connecting"`, `&"hosting"`, `&"joined"`, `&"reconnecting"`. A refusal or loss returns to `&"off"` (or `&"finding"` while the join list is open) after emitting `refused` / `lost`. |
| Slots | Slot 0 = host. The host gives slots 1..5 in join order and keeps a member's slot for the session by its `nid` (reconnect gets the same slot). Every message names members by slot, never by ENet peer id. |
| Member record | `{slot: int, nm: String, where: StringName, pick: String, here: bool}`; `where` ∈ `deck setup battle arena army settings menu`; `pick` = faction key the member would like ("" = host chooses); `here` false while a member is reconnecting (slot kept 60 s). |
| Identity | `nid`: 16 random hex chars made on first use, stored with the name in `user://net.cfg` (section `net`, keys `nm`, `nid`; tests point `cfg_file` elsewhere). Not a secret, not an account; only used to give a reconnecting player the same slot. |
| Name | 1–20 characters after cleaning (`NetProto.clean_name`: strip control characters, newlines, direction controls and `{` `}`; trim, collapse spaces). Empty → the online screen fills a default (`ผู้เล่น {n}` / `Player {n}`, `n` = 100–999 from `randi`); if `Net` needs a name before the screen gave one, it uses the bare number. Names that come from the host (`WELCOME`, `MEMBERS`) are cleaned again on the client. Never translated. |
| Keep awake | While online, `DisplayServer.screen_set_keep_on(true)`; at `off` back to the value it had before going online (the project default keeps the screen on; offline games must not start to dim). |
| LAN detection | `lan_addresses()` reads `IP.get_local_interfaces()` and skips mobile-data, VPN and dummy interfaces (`rmnet*`, `v4-rmnet*`, `ccmni*`, `pdp*`, `clat*`, `wwan*`, `ppp*`, `tun*`, …). `local_ips()` = their private IPv4 addresses, Wi-Fi/hotspot/Ethernet first (`wlan`, `swlan`, `ap`, `wl`, `eth`, `en`, Windows "Wi-Fi"/"Ethernet"), shown on the host card. `has_lan()` = any IPv4 there that is not carrier NAT (100.64/10); false → `no_lan` on hosting and in the friend's empty room list. |
| Background | `NOTIFICATION_APPLICATION_PAUSED` closes the discovery socket (releases the Android multicast lock); `RESUMED` opens it again. The room itself stays. |
| Test hooks | `ports`, `probe`, `cfg_file`, `max_players`, `hello_extra` (merged into the next hello, to fake versions), `clock_skew_ms` (shifts this instance's clock: heartbeats and timeouts without waiting), `make_link` (false = no `NetBattleLink` child; set before `add_child`), `poll()` (one manual poll of the peer and discovery: synchronous unit tests). Several `NetSession` instances may live in one process (each uses its node's `multiplayer`); no static state. |

### 1.3 Transport

- Host: `set_bind_ip("0.0.0.0")` (IPv4 only; Godot's `"*"` is dual-stack and would let any global IPv6 address reach the
  ENet handshake before the `not_lan` check) then `ENetMultiplayerPeer.create_server(ports.game, max_players + 1)` (two
  spare peers so a refused joiner still connects and hears its `REFUSE` reason); client: `create_client(ip, port)`. Default
  channel count on both ends (check in `test_net_loopback`). Every `ENetPacketPeer` gets `set_timeout(32, 3000, 8000)`:
  a silent peer is dropped after 3–8 s.
- `SceneMultiplayer` settings: `server_relay = false`, `allow_object_decoding = false` (default), `auth_timeout = 5.0`,
  `auth_callback` = the gate (§3).
- Messages: `multiplayer.send_bytes(bytes, to_peer, mode, channel)`; received through `peer_packet(id, bytes)`.
  Channel 0 `TRANSFER_MODE_RELIABLE` for everything except poses; channel 1 `TRANSFER_MODE_UNRELIABLE_ORDERED` for poses.
- Heartbeat `HB` every 2 s each way while online (§2.2). Members that miss ENet's timeout are gone (§4.8, §9).
- After a loss a client tries to reconnect to the same ip:port every 3 s for 60 s (`&"reconnecting"`), then `lost`.

### 1.4 Discovery (`net/net_discovery.gd`, `class_name NetDiscovery`, RefCounted, polled by `Net`'s Timer)

| Side | What it does |
| --- | --- |
| Host | `PacketPeerUDP.bind(ports.disc, "0.0.0.0")` (IPv4 only), `set_broadcast_enabled(true)` (Android: needed for the multicast lock, §8). On each packet: ignore unless it is a valid query (below) from a private address (§10); answer one beacon to the sender's ip:port. Closed when hosting stops. A second host on the same machine fails to bind: hosting still works (manual IP), the screen says discovery is off. |
| Joiner | While the join list is open: `bind(0, "0.0.0.0")` (spare port), `set_broadcast_enabled(true)`, send a query every 1.0 s to `255.255.255.255:ports.disc` and to each address in `probe` (tests: `["127.0.0.1"]`; the app adds the last host IP it joined). Read beacons, keep one entry per host token `t` (the same host can answer from 127.0.0.1 and a LAN IP: dedupe by token, keep the first non-loopback IP). Entries not seen for 4 s drop out; at most 16 rows (a device spraying beacons with random tokens cannot grow the list). |

Packets are UTF-8 JSON objects, **≤ 512 bytes**, anything else ignored without a log line per packet (one warning per
minute at most):

- query: `{"g":"candlelight","k":"q","np":1,"n":"<8 hex nonce>"}` (`n` is informational only and not checked: the beacon
  goes back to the asker's ip:port anyway)
- beacon: `{"g":"candlelight","k":"b","np":<NetProto.VERSION>,"app":"<APP_VER>","rules":<RULES_V>,"data":"<DATA_HASH first 12>",
  "port":<ports.game>,"nm":"<host name>","n":<members>,"max":<max_players>,"st":"deck|setup|battle","t":"<8 hex host token>"}`

The joiner marks a beacon `ok = false` with the gate's reason key (§3) when `np`, `app`, `rules` or `data` differ or
`n >= max`, and shows that entry greyed with the reason; tapping it shows the reason, never connects.

### 1.5 Ports

`NetSession.PORTS := {"game": 24680, "disc": 24681}` (UDP both). Overridable: the `ports` var (tests), and user args
`--net-port=<game>` (disc = game + 1) read from `OS.get_cmdline_user_args()` at `_ready` (the second test process).
Unit and flow tests pick a pair from `30000 + (OS.get_process_id() % 4000) * 2` and retry the next pair on
`ERR_CANT_CREATE`, so two runs on one machine never collide.

## 2. Messages (`net/net_proto.gd`, `class_name NetProto`, static, pure)

### 2.1 Framing and limits

- A message = `[kind: u8] + var_to_bytes(body)`, `body` a `Dictionary` with String keys. Decoding: check the total size
  against the kind's cap **before** decoding, then `bytes_to_var` (never `bytes_to_var_with_objects`, never `str_to_var`,
  `Expression`, `load` or a path from the wire), then the kind's schema.
- Allowed values: `int`, `bool`, `String`, `Array`, `Dictionary` (String keys), `PackedInt32Array`, `PackedInt64Array`.
  **No floats anywhere** (positions are centimetres, angles milliradians, acts are core-form ints: `ActLog._clean`
  refuses floats anyway). Depth ≤ 8; arrays ≤ 4096 items (acts in `RESYNC` ≤ 6000); strings ≤ 256 characters unless the
  table says less.
- Caps: every message ≤ **64 KiB**, `POSE` ≤ 96 bytes, `RESYNC` ≤ **1 MiB** (a 6-seat game is ≈ 750 acts ≈ 72 KB).
- **Direction before decoding:** the host looks at the kind byte and size first and disconnects a member that sends a
  host-only kind (`DIR` "h"), `HELLO` after authentication, or more than 64 KiB (`NetProto.from_member_ok`), so a member
  can never use `RESYNC`'s 1 MiB or `INTS`'s 256 KiB cap; a client leaves with `bad_message` on a client-only kind from
  the host (`NetProto.from_host_ok`).
- A peer that sends an invalid or oversize message is logged once and disconnected by the host; a client receiving an
  invalid message from the host logs it and leaves with `lost("bad_message")`. Rate limit on the host per member and 1 s
  window: more than 60 messages of kinds < 20 (poses included), or more than 600 of the battle kinds ≥ 20 (requests run
  at the host's answer pace) → disconnect. Heavy requests also have a per-member budget per game (§4.3).
- `NetProto.VERSION := 1`; any change to a kind or a field bumps it (the gate refuses mixed versions).

### 2.2 Message kinds (reliable on channel 0 unless marked)

| Id | Name | Direction | Body | Notes |
| --- | --- | --- | --- | --- |
| 1 | `HELLO` | client → host (auth) | `{g: "candlelight", np, app, rules, data, nm, nid}` | `data` = full `DATA_HASH`; `nm` ≤ 64 on the wire, cleaned to ≤ 20; `nid` 16 hex |
| 2 | `WELCOME` | host → client (auth) | `{slot, host_nm, room_st, members}` | then both sides `complete_auth` |
| 3 | `REFUSE` | host → client (auth) | `{key, args}` | §3 keys; host disconnects 0.3 s later |
| 10 | `MEMBERS` | host → all | `{list: [member records], room_st: "deck"\|"setup"\|"battle", gen}` | on every change |
| 11 | `WHERE` | client → host | `{where}` | host folds it into `MEMBERS` |
| 12 | `PICK` | client → host | `{fac}` | "" or a `GameData.factions()` key |
| 13 | `POSE` | client → host → others (channel 1, unreliable ordered) | `{x, z, yaw, sp, run, t}` + host adds `s` (slot) when relaying | cm, cm, mrad, cm/s, bool, sender ms |
| 14 | `POSE_STOP` | as `POSE`, reliable | same fields, `sp = 0` | the last pose when the avatar stops |
| 15 | `HB` | both ways every 2 s | host: `{seq, dg, gen}` during a battle else `{}`; client: `{seq, gen}` | `seq` = last applied act; an HB of another `gen` is ignored |
| 16 | `BYE` | either | `{key}`: `leave`, `host_closed`, `kicked` (reserved) | then disconnect |
| 20 | `SETUP` | host → all | `{open: bool, seats: [{team, owner, fac}]}` | the host is on the battle setup screen; sent on open, on every change of the choice, and `open: false` on close or start; `owner` = slot or −1 (bot) |
| 21 | `CLAIM` | client → host | `{k}` | "seat claim": the member asks for seat `k` (−1 = leave my seat) while the setup is open (§5.1) |
| 22 | `START` | host → all | `{gen, plan: {setup, seats}, owners: [slot or -1 per seat]}` | §4.2 |
| 23 | `ACT_REQ` | client → host | `{gen, base, act}` | `base` = client's last applied seq |
| 24 | `ACT` | host → all | `{gen, seq, act, dg?}` | `act` = the canonical logged act (`ActLog.at(seq)`); `dg` = host digest after it (§4.7) |
| 25 | `ACT_NO` | host → requester | `{gen, base, key}` | `stale`, `not_yours`, `not_now`, `refused`, `gone_seat` |
| 26 | `RESEND` | client → host | `{gen, from}` | host answers with `ACT`s `from..last` |
| 27 | `RESYNC_REQ` | client → host | `{gen, why}` | `desync` (`rejoin` reserved: the host resyncs a returning seat itself) |
| 28 | `RESYNC` | host → one client | `{gen, plan, owners, acts, seq, dg}` | full act log (§4.8) |
| 29 | `SEAT` | host → all | `{gen, k, on: "gone"\|"back"\|"left"}` | a seat played by the host or returned |
| 30 | `DESYNC` | client → host | `{gen, seq, dg, n}` | `n` = 1 first mismatch, 2 after a resync |
| 31 | `INTS_REQ` | client → host | `{gen}` | debug after a second mismatch |
| 32 | `INTS` | host → client | `{gen, seq, ints: PackedInt64Array}` | the client logs the first differing index of `state_ints()` |
| 33 | `END` | host → all | `{gen, why}`: `host_left_battle`, `host_closed` | the battle stops for everyone |
| 34 | `LEAVE` | client → host | `{gen}` | the member left the battle screen of game `gen` on purpose → `SEAT left` (§4.8); a LEAVE of another `gen` is ignored |

### 2.3 Field checks (in `NetProto.decode`, before anything else sees the body)

Every field of the table has a type and range check; extra keys are dropped. Ints: `slot` 0..5, `seq`/`base`/`from`
0..100000, `gen` 0..65535, `k` −1..5, `owner` −1..5, `x`/`z` −5000..5000 (cm; the deck is 24 × 16 m), `yaw`
−7000..7000, `sp` 0..2000, `t` any non-negative int; `dg` 16 lowercase hex; `SETUP.seats` ≤ 6 entries; `where`, `key`, `on`, `why`, `room_st` from their fixed lists; `plan.seats` ≤ 6
dictionaries with `team` int 0..3, `bot` bool, `ai` false, `pid` String ≤ 20, `nm` String ≤ 20, `fac` String ≤ 24,
`list` PackedInt32Array ≤ 512; `plan.setup` keys of `SeatPlan.build`'s setup only. `act` must pass
`ActLog._clean`-style typing (ints/bools/strings/arrays/dicts) and have `a` in `BtActs.CODES`; its rules check is the
host's job (§4.5).

## 3. Version gate (`net/net_gate.gd`, `class_name NetGate`, static, pure; no Thai)

The host's `auth_callback(peer_id, bytes)` decodes `HELLO` and checks, in this order (first failure wins):

| Key | When | args |
| --- | --- | --- |
| `not_lan` | the peer's remote address is not private (§10) | `{}` |
| `wrong_game` | `g` ≠ "candlelight" or the hello does not decode | `{}` |
| `wrong_net` | `np` ≠ `NetProto.VERSION` | `{host, mine}` |
| `wrong_app` | `app` ≠ `Version.APP_VER` | `{host, mine}` (the two APP_VER strings) |
| `wrong_rules` | `rules` ≠ `Version.RULES_V` or `data` ≠ `Version.DATA_HASH` | `{host, mine}` (the RULES_V numbers) |
| `full` | members already `max_players` (a reconnecting `nid` is never "full") | `{n, max}` |
| `closing` | the host is closing the room | `{}` |

Pass → `WELCOME` + `complete_auth`. Fail → `REFUSE {key, args}` with `send_auth`, then `disconnect_peer` 0.3 s later. The
client shows the reason in Thai or English (§7.3) and goes back to the join list. The client also checks the host's
beacon before connecting (§1.4) and its own side of `WELCOME` (a host that answers with another `np` is refused locally
with `wrong_net`). Other local failure keys (no gate involved): `port_busy {port}` (hosting could not bind), `no_lan`
(no IPv4 address on a Wi-Fi/hotspot/Ethernet interface: mobile data, VPN and carrier NAT do not count, §1.2), `bad_ip` (manual entry did not parse), `timeout` (no answer in 5 s),
`host_left`, `bad_message`, `reconnect_failed`.

All of APP_VER, RULES_V, DATA_HASH and NetProto.VERSION must be equal: two devices with the same app build always
compute the same battle; different builds never meet (rule 5).

## 4. Lockstep battle on the existing core

### 4.1 Model

- **The host is the sequencer.** Every act enters the game through `Battle.apply` on the host first (its own human acts,
  bot acts, rolls it makes, accepted client requests). The host broadcasts each logged act as `ACT {seq, act}` where `act`
  is `b.actlog.at(seq)` (canonical form, with `seq` and `pid`).
- **Clients apply only `ACT`s from the host, in seq order.** A client's own act is sent as `ACT_REQ` and applied only
  when its echo arrives as an `ACT`. Duplicates (`seq <= last`) are ignored; a gap (`seq > last + 1`) is buffered and a
  `RESEND {from: last + 1}` sent (with a reliable ordered channel a gap means a bug: log it).
- A client applies `{seq, pid, a, …}` with `b.apply(act)`; `ActLog.append` checks `seq == last_seq + 1`. If the core
  refuses an act the host accepted, that is a desync (§4.7).
- Messages are handled on the main thread in arrival order, so a `START` is always processed before the acts of that
  game; acts that arrive while the client's battle screen is still loading are applied by its runner at once (the runner
  is pure, §4.4), the screen catches up on its next pump.
- **Trust:** like the Worker, the sender's dice are trusted (friends on one Wi-Fi). The host checks *who* may act and
  *when* (§4.5) and the core checks the act; nothing else.

### 4.2 Seats, pids and `START`

- The host builds the plan with `NetSeats.build(choice, members)` (§5.1): `SeatPlan.build` with every seat built as a bot
  (so its one-human check does not apply), then for each seat `k` owned by member slot `s`: `bot = false`,
  `pid = "n%d" % s`, `nm` = the member's name. Bot seats keep `pid = ""`, `nm = ""`. The pids exist **before**
  `Battle.make`, so `BtTurn.start_match` never gives the local `"L<seat>"` pids (`core/battle/turn.gd:81`) and every device
  has the same seat pids in its digest.
- `owners[k]` = slot or −1. `START {gen, plan: {setup, seats}, owners}` goes to all members (seated or not). Each device
  sets `plan.human` = the seat whose owner is its own slot, or −1 (a spectator), and builds its runner (§4.3, §4.4);
  everyone then calls `start()` once (not logged; same on every device).
- `gen` = game number in this room, +1 per `START`; every battle message carries it and stale ones are dropped.

### 4.3 The host's runner (`NetMatchRunner`, host mode)

`NetMatchRunner extends MatchRunner`; in `_init` it calls `super(plan)` and swaps `b` for a `NetRec` (extends
`MatchRunner.Rec`) holding the same `st` and `seed` before `start()` (the act log is still empty, so nothing is lost).

`NetRec` overrides:

- `apply(act)`: `super(act)`; if the act was logged (`last_error == ""` and the log grew), hand `actlog.at(seq)` to the
  `Lockstep` (it queues the `ACT`, with `dg` when `seq % 8 == 0`). This catches every path: the host's taps, `bot_step`,
  `flush`, `BtBot.finished_act`, played gone seats.
- `flush(force, here)`: ignores both arguments. It loops: `super(false, net_here())` with
  `net_here() = {online: true, owner: true, pid: <host seat pid or "">, since_ok: false}` rolls what the host always
  rolls (bots, its own seat; `BtRoller.rolls_here`, streams from `BtRoller.stream_name`, pids from `Battle.flush`), then
  the first live pending entry left (`Lockstep.first_live`) is checked with `_host_rolls_for(p)`: it belongs to a remote
  human seat (owner slot > 0) that is **gone**, or has waited ≥ `Lockstep.ROLL_WAIT_MS` = 15000 ms since it became first
  (`Time.get_ticks_msec()` in the runner, outside core). Then the host rolls **exactly that one entry** from `bot:<k>`
  with the seat's pid and loops again. (A first version passed `since_ok` once for the whole `Battle.flush`, so after one
  gone or silent seat the host also rolled the next live friend's saves from `bot:<k>`.) `Battle.bot_step`'s internal
  `flush(true, {"online": false})` lands here too. `_since_ok()` runs on every flush (a new first entry restarts its
  clock; none clears it).

Host `step()` (replaces `MatchRunner.step` in host mode; same result shape `{state, events}`), in order:

1. Over → `over`.
2. Pending entries: `b.flush(false, …)`; acted if the log grew.
3. `b.bot_step()` (bot seats only) **only when no live pending entry is left** (`Lockstep.first_live(st) == null`): while a
   friend's roll waits, bots wait too, as the old page's `botTick` (waits on `PEND`) and offline `MatchRunner` (flushes
   everything first) do; acted if it returned a code or the log grew.
4. **Gone seats**: for the first gone seat whose team is in turn, in a human phase and not `done` → `play_seat(k)`: one act
   by the `auto_step` policy with that seat's index and pid (implemented by setting `human`/`pid` to seat `k`, calling
   `auto_step()`, restoring them); acted.
5. The host's own seat: as `MatchRunner` (`wait_human`, or `auto_step` when `auto_human`).
6. `BtBot.finished_act(st)` (only when every non-bot seat of the team is `done`) → apply with pid ""; acted.
7. `b.flush` again; acted if the log grew.
8. Nothing moved: if a connected remote human must act or roll → **`wait_remote`**; if a remote entry is waiting for
   its 15 s → `wait_remote` with `next_wake_ms()` set; otherwise `stuck` (a real stuck game, as today).

After every `step()` and every handled request the runner calls `lockstep.end_burst(b)`: the last queued `ACT` gets `dg`
(the digest of the current state) and the queue is sent. A host `step()` that returns `wait_remote` emits `waiting`; the
link then sets its one-shot wake Timer to `next_wake_ms()` (§5.2) — the common wait (the host shot a friend's squad and
waits for the save) produces no `changed`, so the Timer must not depend on it.

**Heavy requests** (`NetMatchRunner.ASK_MAX`, per member per game): `RESYNC_REQ` 4, `INTS_REQ` 2, `RESEND` 16,
`DESYNC` 8. Over budget → ignored with one log line; a 5th `RESYNC_REQ` makes the host play that seat to the end
(`seat_gone(k, "desync")`, loud). A `RESEND` that goes back more than 64 acts is answered with one `RESYNC` (counted as
a `RESYNC_REQ`). `Lockstep.log_lines` keeps the last 200 lines; refused requests are logged at most 20 times per game.

### 4.4 A client's runner (`NetMatchRunner`, client mode)

Never calls `bot_step`, `BtBot.finished_act`, `Battle.flush` or `MatchRunner.step`. `NetRec.flush` returns 0 and does
nothing in client mode (so `MatchRunner.shoot/charge/end_phase/auto_step`, which call `b.flush(true, HERE)` after a
human act, are safe). `_human_act(a)` sets `a.pid = pid`, sends `ACT_REQ {gen, base: last_seq, act: a}`, sets
`in_flight = true` and returns "" (or `"busy"` if one is already in flight). When `Net.send` returns false (the client is
reconnecting) nothing is in flight and it returns `not_now`; on `Net.reconnected` the link clears `in_flight` (a request
sent just before the drop may be lost). `can_select(s)` is false while `in_flight`. While the host plays this device's
seat (`lockstep.gone[human]`, from `SEAT` or an `ACT_NO gone_seat`), `is_human_turn()` and `can_select` are false, `step()`
returns `wait_remote` and nothing is sent; the screen says a bot plays for you.

Client `step()`:

1. Over → `over`; `in_flight`, a desync, an `END`, a spectator or a seat the host plays → `wait_remote`.
2. My pending roll: `p := BtRoller.next(st, here)` with `here = {online: true, owner: false, pid: my pid}`; if
   `p != null`, `acts := BtRoller.roll(st, p, BtBot.choice(st, p), st.rng("dice:%d" % human))` and send `acts[0]` as a
   request (one act at a time, exactly the offline `flush` order); `wait_remote`.
3. `is_human_turn()`: no squads left → `end_phase()`; `auto_human` → `auto_step()` (sends one act); else `wait_human`.
4. Else `wait_remote` (someone else's turn, a bot, the host).

`ACT_NO` clears `in_flight` only when its `base` is the last request's base (a late answer to an older request does not
clear a newer one): `stale` → step again after catching up (toast); `not_yours`/`not_now`/`refused` → log a warning (a
client gate bug); `gone_seat` → the host plays this seat: mark it gone locally and say so (§4.8).

A spectator (`human = −1`) only applies acts and checks digests.

### 4.5 The host's request gate (`Lockstep.gate(st, seat, act) -> String`, static, pure)

On `ACT_REQ` from slot `s`: drop if `gen` differs; `seat` = the seat owned by `s` (none → `not_yours`); the seat is gone →
`gone_seat`; `base != b.actlog.last_seq()` → `stale`; then **overwrite `act.pid` with the seat's pid** (never trust the
field) and check:

- **Roll answers** (`wnd`, `sav`, `rr`, `shock`, `rez`, `ow`, `chr`, `cmove`, and `atk` while the first live pending entry
  is a hit roll of the same `u`/`t`): the first live pending entry's roller (`BtPend.roller_of`) is `seat`, and the act's
  `a`/`u`/`t` match that entry; else `not_now`.
- **Actions** (`smove`, `stay`, `skip`, `adv`, `atk`, `shoot`, `chg`, `gren`, `heal`, `done`): no live pending entry; the
  seat's team is in turn; phase is move/shoot/charge; the seat is not `done`; the act's squad `u` (if any) has
  `pl == seat`; `done.ph` equals the current phase name; else `not_now` / `not_yours`.
- `endph`, `endturn`, `move` and anything else: `not_yours` (host only).

Pass → `b.apply(act)`; refused by the core → `ACT_NO {key: "refused"}` (nothing logged, nothing broadcast). Accepted →
broadcast through `NetRec.apply` as every other act.

### 4.6 Dice streams (R1_PORT_SPEC §3)

- A human's dice come from that player's own device: `dice:<seat>`. Online the stream is seeded from device entropy:
  right after `start()` the runner sets `st.rngs["dice:%d" % human] = Rng.make("dice:%d" % human, randi() | 1)` (device
  state, not rules state: `st.rngs` is outside the digest). Tests pass a fixed `dice_seed` instead. A rejoined client
  (runner built from a `RESYNC`, never `start()`ed) seeds the stream the same way in `_rebuild`, never from the table
  seed that every device knows.
- Bots, gone seats and silent humans: `bot:<seat>` on the host. Padding: `fallback:<seq>:<stage>` on every device. Dice
  always travel inside acts; receivers never roll.

### 4.7 Digests and desync

- The host attaches `dg = b.digest()` (0.7 ms for 6 seats / 173 units on the study machine) to: every act with
  `seq % 8 == 0`, the last act of every burst (§4.3), the act that ends the game, and every `HB` during a battle.
- A client compares after applying the act carrying `dg` (and on `HB` when its `seq` equals the host's). Equal → count a
  check. Different, or the core refused a host act → **desync**:
  1. emit `Events.Id.DESYNC {seq, local_digest, remote_digest}` into the runner's event queue (the screen shows the loud
     panel, §5.3), `Log.error("desync gen=%d seq=%d local=%s host=%s")`, send `DESYNC {n: 1}`, set state `desync`;
  2. send `RESYNC_REQ {why: "desync"}`; on `RESYNC` rebuild: `Battle.make(plan.setup, plan.seats, {})` → `start()` →
     `replay(acts)`, keep the device dice stream, compare with `RESYNC.dg`; equal → back to play, the panel says it was
     repaired and closes after 3 s;
  3. different again (the resync itself, or a new mismatch within 2 digest intervals = 16 seqs after a repair; a later
     one counts as a first mismatch again) → `DESYNC {n: 2}`, `INTS_REQ`, log the first differing index of `state_ints()` with both values,
     state `desync_final`: the panel stays with only "ออกจากการรบ" (leave); the host shows "เครื่องของ {name} ไม่ตรงกัน" and
     plays that seat (§4.8). Never continue silently.
- The host logs every `DESYNC` it receives with the member's name, seq and both digests.

### 4.8 Disconnect → bot, reconnect, rejoin

- A seated member's peer disconnects (ENet timeout, app killed, Wi-Fi off, `BYE`) → the host marks the seat **gone**,
  broadcasts `SEAT {k, on: "gone"}` and plays it (§4.3 step 4; its rolls one entry at a time from `bot:<k>`). The seat stays `bot = false`, the
  pid stays, every act is an ordinary act: the digest and the act protocol do not change.
- The member reconnects within the session (same `nid` → same slot): the host answers `WELCOME`, then (game running and
  the member owns a seat) `RESYNC {plan, owners, acts, seq, dg}`, then `SEAT {k, on: "back"}` and stops playing it. The
  member's app opens the battle screen with a client runner rebuilt from the resync (§4.7 step 2 path). Cost measured: a
  746-act replay takes 0.27 s on the study machine. If the new connection arrives before the host's ENet noticed the old
  one died (a fast Wi-Fi blip), the host first drops the old peer as a disconnect (`here = false`, seat gone), then
  admits the new one (`here = true`, seat back with `RESYNC`): never a silent swap. A reconnect keeps the member's
  `where`. A member who reopens the app after the 60 s slot expiry gets its seat back the same way.
- During a battle the slots that own a seat in it are kept for their owners (`NetSession._battle_owners` from `START`):
  a newcomer gets another slot and is a spectator of the deck only (not sent into the running game; the host can seat it
  in the next game), so it can never inherit a dropped player's seat.
- A seated member who leaves the battle on purpose (leave dialog, "กลับล็อบบี้") sends `LEAVE {gen}` → `SEAT {on: "left"}`:
  the host plays the seat to the end of that game; the member stays in the room and is seated again only by the next
  `START`. (A first version guessed this from `where` battle → deck; a `WHERE` crossing the next `START` then marked the
  new game's seat as left.) A `LEAVE` of an older `gen` is ignored.

### 4.9 Ending, play again, leaving

- Game over: every device shows its end panel. Only the host has "เล่นอีกครั้ง" (a new `START`, `gen + 1`, new seed,
  same choice; seats of members who left the room become bots first, any other error shows as a toast); clients see
  "รอเจ้าห้องเริ่มเกมใหม่" and "กลับล็อบบี้" (back to the deck, still in the room).
- The host leaves the battle (leave dialog, back, app closes) → `END {why: "host_left_battle"}`: clients show
  "เจ้าห้องออกจากการรบ เกมนี้จบแล้ว" with one button back to the deck.
- The host closes the room or disconnects → clients get `END {why: "host_closed"}` / `lost("host_left")`; a battle on
  screen ends with the same panel; the deck drops the friends; the client is offline. A client whose own connection could
  not come back (`lost("reconnect_failed")` / `bad_message`) ends with "การเชื่อมต่อหลุด — เกมนี้จบสำหรับเครื่องนี้", not
  "the host left".

### 4.10 Why no core or rules change

| Need | How, without touching `core/` or `match_runner.gd` |
| --- | --- |
| Host rolls only what it should | `NetRec.flush` override (GDScript methods are virtual: `MatchRunner` and `Battle.bot_step` calls land there). `MatchRunner.HERE` stays a const. |
| Clients never roll for others | client `NetRec.flush` = no-op; client `step()` rolls its own entries through `BtRoller.next` + `roll` |
| Same pids everywhere | pids set by the host before `Battle.make` (§4.2) |
| Dropped player | the host plays the seat with its pid (no `bot` flip, no new act code, no server PR, no RULES_V bump: `../docs/GODOT.md` §4.2) |
| Desync alarm | the existing `Events.Id.DESYNC` |
| Rejoin | `Battle.make` + `start` + `replay` (the path `MatchRunner.replayed_digest` already uses) |

`test_golden`, `test_match_runner` and every core suite must stay byte-identical; `test_net_match_runner` proves that a
host with no remote players produces the same act log as `MatchRunner` (§12.2).

## 5. Battle setup and battle screen (BATTLE track)

### 5.1 Battle setup in online mode (`ui/screens/battle_setup.gd`, `ui/battle/net_seats.gd`)

- Online mode = `Net.is_host()` and at least 2 members. Clients who use the war table get a message instead (§7.1).
- On open, and on every change of the choice, the host sends `SETUP {open: true, seats}` (`open: false` on close or
  start). Default choice when online: `NetSeats.defaults(members, seed)`: teams = clamp(members, 2, 4), per_team = 1
  (2 when members > 4), seat `k` owned by the k-th member in slot order, the other seats bots; each seat's faction = the
  member's `pick` if set, else the offline default. The last online choice is kept in memory in `NetSeats.last` (not in
  `App.last_choice`, so the offline setup is unchanged).
- Each seat row's owner button cycles **บอท → คุณ → each member not yet seated (by name) → บอท** (offline it stays the
  two-way คุณ/บอท toggle). Members who leave the room while seated in the choice turn their seat back to a bot.
- **Seat claims:** `CLAIM {k}` from a member while the setup is open: `NetSeats.claim(choice, slot, k)` gives seat `k` to
  that member when it is a bot seat (the member's previous seat becomes a bot), `k = −1` frees the member's seat; any
  other claim is ignored. The host's rows update at once (and a new `SETUP` goes out); the host can still change any seat.
  Members claim from the airlock screen (§7.2 state 3).
- `NetSeats.validate(choice, members)`: `SeatPlan.validate` without `humans`, plus `member_twice` (a member on two seats)
  and `member_gone` (an owner no longer in the room).
- Start (host): `NetSeats.build` → `START` → `App.replace(BATTLE_SCREEN)` → `begin(plan, NetMatchRunner.host(...))`.

### 5.2 Client entry (`ui/battle/net_battle_link.gd`, `class_name NetBattleLink extends Node`)

`Net` creates one `NetBattleLink` as its child at `_ready` with `load("res://ui/battle/net_battle_link.gd")` when that
file exists (cross-track by path, at use time). The link listens to `Net.message` for battle kinds and:

- `START` on a client: builds `NetMatchRunner.client(plan, my_seat, lockstep)`, then pushes the battle screen on top of
  whatever screen is current (`App.push(load(BATTLE_SCREEN))` then `begin(plan, runner)`); a battle screen already on top
  is replaced. Spectators get the same screen in watch mode.
- Routes `ACT`, `ACT_NO`, `RESYNC`, `SEAT`, `END`, `INTS`, `HB` to the current runner; on the host routes `ACT_REQ`,
  `RESEND`, `RESYNC_REQ`, `DESYNC`, `INTS_REQ`, `LEAVE`, and `Net.members_changed` (member gone/back →
  `runner.seat_gone(k)` / `seat_back(k)`; leaving on purpose is `LEAVE`, never guessed from `where`).
- `client_left()` (battle screen, client leaving a running game) sends `LEAVE {gen}`; `host_left()` sends `END`.
- `Net.state_changed` → `runner.link_state` (the client screen shows "กำลังต่อใหม่…" while reconnecting);
  `Net.reconnected` → clear `in_flight`; `Net.lost(key)` → `ended_why` = `host_closed` for `host_left`, else `lost`.
- Owns the one-shot `Timer` for `runner.next_wake_ms()` (§4.3 step 8), set on the runner's `waiting` (and `changed`);
  once the roll is overdue and the wake fired it is not re-armed (no 1 ms timer every frame when the host's screen is not
  pumping). If the battle screen could not open, the link `start()`s the runner itself. Emits nothing per frame.

### 5.3 Battle screen (`ui/screens/battle_screen.gd`, surgical)

- `begin(p: Dictionary, r: MatchRunner = null)`: `runner = r if r != null else MatchRunner.new(plan)`.
- `_on_timer`: new state `wait_remote` stops the timer like `wait_human` and shows the banner "รอ {name}…" (names from
  `runner.waiting_for()`; the host is named "เจ้าห้อง"); the runner's `changed` signal (an act arrived, a wake fired)
  restarts the pump. States `desync` / `desync_final` stop the timer and show `%DesyncPanel`.
- Online leave dialog: client "ออกจากการรบ? บอทจะเล่นแทนคุณจนจบเกมนี้"; host "ออกจากการรบ? เกมนี้จะจบสำหรับทุกคน".
- End panel: "เล่นอีกครั้ง" only on the host; clients get "รอเจ้าห้องเริ่มเกมใหม่" in its place.
- Toasts: seat gone / back / left, "บอทเล่นแทนคุณอยู่ตอนนี้" when the host plays your seat (also the banner), stale
  request, the host's desync notice. Banner "การเชื่อมต่อหลุด — กำลังต่อใหม่…" on a client while reconnecting. End panel
  "การเชื่อมต่อหลุด — เกมนี้จบสำหรับเครื่องนี้" when this device's connection was lost for good.
- The speed buttons change only the local pump; "ให้บอทเล่นแทน" works online for your own seat (acts go as requests).
- `%DesyncPanel` (new node, built in code like the other panels): red-edged centred panel, title, body, one button.
- Offline behaviour unchanged (every current `test_battle_screen` check stays green).

## 6. Deck presence (DECK track; visual only)

### 6.1 Sending and receiving

- Send: `hall_screen` connects `world.avatar.moved(pos)`; at most one `POSE` per 100 ms while moving
  (`{x: cm, z: cm, yaw: avatar.face in mrad, sp: avatar.speed() cm/s, run: avatar.running(), t: ticks_msec}`), and one
  reliable `POSE_STOP` when a 0.25 s one-shot Timer (restarted on every `moved`) fires. One `POSE_STOP` also goes out on
  arriving on the deck. Nothing is sent while standing still: the host keeps the last pose of every member and sends them
  to a newcomer right after its `WELCOME`.
- `WHERE` on every screen change: deck (hall visible), setup, battle, arena, army, settings, menu.
- Receive: `Net.pose(slot, pose)` → `HallFriends.push_pose(slot, pose, now_ms)`; only members with `where == deck` are
  drawn; a member leaving the deck disappears at once.
- Interpolation (`HallFriends.interp`, pure): keep the last 3 samples per friend stamped with **local arrival time**;
  render 100 ms behind the newest; linear position, shortest-arc yaw; past the newest sample extrapolate with its speed
  for at most 150 ms, then hold; snap when the error is > 3 m (teleport, spawn, arena return). `HallFriends` processes
  only while some friend is between samples or extrapolating, then sleeps (the `HallAvatar` pattern).
- Friends have no collision bodies (walk through each other; zero physics cost).
- Spawn: online, each player places itself at `HallFriends.spawn_for(my_slot)` = `HallLayout.SPAWN +
  Vector3((slot - 2.5) * 0.9, 0, 0)` (x −2.25 … 2.25 at z 5; each spot free with radius 0.35, `HallLayout.blocked`).

### 6.2 Look

- **Eggs:** one `MultiMeshInstance3D` `Friends/Eggs` (capacity 5) with `HallBuilder.avatar_mesh` built in white at the
  level's `sides`, per-instance colour = the member's slot colour (`data/teams.json[slot].rgb`, the `Rings` trick: unshaded
  material with vertex colour as albedo), no shadows. Bob on hi/mid only while moving (transform offset). Pack figures are
  for the local player only; friends are always eggs in round 1.
- **Rings:** friends' rings in the existing `Rings` MultiMesh: `rings.setup(1 + HallLayout.IDS.size() + 2 + HallFriends.MAX)`
  (capacity 16), radius `AVATAR_RING_R`, slot colour, moved with `set_ring` (zero extra draw calls).
- **Local colour online:** the local egg and ring take `teams[my_slot]`; offline they keep `teams[0]` (unchanged).
- **Names:** `FriendTags` (`ui/widgets/friend_tags.gd`, a full-rect `Control` under the hall screen's layer,
  `mouse_filter` IGNORE) draws every friend's name **and the local player's "คุณ"/name tag** in one `_draw()`: one font,
  **one font size (22)**, no outline; legibility from a 1 px dark copy of the same glyphs underneath (same texture, same
  batch). Positions from `camera.unproject_position(head)` (head = egg top + 0.35 m); behind the camera → skipped. While
  online with at least one friend on the deck, the world's `you` Label3D is hidden (`HallWorld.set_you_tag_visible(false)`)
  and its text is drawn by `FriendTags`. The online status line "ออนไลน์ · ห้องของ {name} · {n}/{max} คน" is drawn by the
  same `_draw()` at the top centre (same size); while this device reconnects it reads "การเชื่อมต่อหลุด — กำลังต่อใหม่…".
  Characters the bundled font lacks (emoji, CJK) are not drawn: Sarabun's system fallback is another texture and broke
  the single batch (+≈4 draw calls per emoji name, measured), and the phone worst view on min has zero margin.
- **Redraw** only on events: a friend moved (`HallFriends.moved`), the local avatar moved, the camera changed (new
  `HallCamera.view_changed` signal, emitted where the camera's transform is updated), a member list change, resize.

### 6.3 Budgets (asserted in `test_hall`, measured the `test_hall` way: max over 4 frames, low-processor mode off)

| View | hi | mid | lo | min |
| --- | --- | --- | --- | --- |
| Deck, every offline view of today (overview, phone worst view, door view, walks) | unchanged: targets 40 / 40 / 35 / 30, draw calls equal to before (no friend node exists offline) |
| **Deck online, 5 friends**: overview with the 5 friends standing in view at their spawn spots, names and status line drawn | ≤ 40 / 60k | ≤ 40 / 50k | ≤ 35 / 40k | **≤ 30 / 30k** |
| **Deck online, phone worst view**: the 0.3 worst view (20:9, touch on, first-walk hint showing, at the war table looking to a back corner) with the 5 friends standing around the war table in view, names and status line | ≤ 40 / 60k | ≤ 40 / 50k | ≤ 35 / 40k | **≤ 30 / 30k** |

Plan: eggs MultiMesh **+1**, `FriendTags` **+1**, `you` Label3D hidden **−1**, rings **+0** ⇒ net **+1** (the 0.3 phone
worst view measured 38 / 38 / 30 / 29 ⇒ 39 / 39 / 31 / 30). Primitives: + ≤ 2,500 at hi (5 eggs at 14 sides). The margin
on min is zero, so **step D1 measures this before the rest of the deck work** (§11.1). If min reads 31: while online on
min, `FriendTags` also draws the first-walk hint text and the hint `Label` hides (−1); if still over, report back — the
targets are never raised.

### 6.4 Idle rules

- Offline: nothing changes (the deck's 10-idle-frame rule holds; `test_hall` still checks it).
- Online, everyone still: after 10 idle frames nothing under the hall screen processes (friends hold, `FriendTags`
  redraws nothing, `Net` uses its Timer only). A moving friend makes only `HallFriends` process (and `FriendTags` redraw)
  until it settles. No shader with `TIME` is added; the eggs MultiMesh has no per-frame script.

## 7. The airlock: online screen and strings (DECK track)

### 7.1 Entry points and flow

- Deck: `use_station()` `"online"` → `open_online()` = `_push(LOBBY_SCREEN)` (`res://ui/screens/lobby.tscn`); `SIGNS.online`
  = "ประตูเทียบยาน · เล่นกับเพื่อน"; `SOON.online` removed (adventure and vault keep "เร็วๆ นี้").
- Main menu: the Online button (badge hidden) → `open_hall()` then the hall's `open_online()` with the avatar placed at
  the airlock's front ring (10.6, 0, 3.0), facing the airlock: depth 3, back returns to the deck at the airlock.
- War table on a client while online: the soon panel shows "เจ้าห้องเป็นคนตั้งเกม — รอเจ้าห้องกดเริ่ม" (the host walks
  there and gets the setup as usual).
- Deck toasts (soon panel reused): "{name} เข้าห้องแล้ว", "{name} ออกจากห้อง", "{name} หลุดจากห้อง — รอต่อใหม่" (at the
  drop, slot kept) and "{name} กลับมาแล้ว", and on `SETUP open` (members) "เจ้าห้องกำลังตั้งเกม — เลือกที่นั่งได้ที่ประตูเทียบยาน".
- Main menu Back while hosting: "ออกจากเกม? ห้องจะปิด เพื่อนทุกคนจะหลุดจากห้อง".
- Round B (14 Nov 2026): every app has the online button; with no pack room it opens host/join on top of the deck at the
  spawn (the airlock is no station without a room), a friend's war table opens host/join while the setup is open, and
  the setup note reads "… เลือกที่นั่งได้ที่โต๊ะรบ" (SHIP_LOBBY_SPEC round B). The network code is unchanged.

### 7.2 `ui/screens/lobby.tscn` + `lobby.gd` (built like the other screens: `CandleStyle`, safe margins, `handle_back()`)

The screen reads `Net` through `var net: Node` (default `/root/Net`; render tests assign a duck-typed stub with the
`NetSession` API, `tests/unit/fixtures/fake_net.gd`). States:

1. **Offline / finding** (opening the screen starts `net.find(true)`; leaving stops it): title "เล่นกับเพื่อน"; name field
   "ชื่อของคุณ" (`LineEdit`, 20 chars, saved on change); primary button "เปิดห้อง"; right under it the IP row:
   `LineEdit` placeholder "ใส่ IP ของเจ้าห้อง" (`virtual_keyboard_type` URL: digits and dots, not the Thai letters) +
   button "ต่อด้วย IP", and the reason line; then the section "ห้องที่พบใน Wi-Fi เดียวกัน" with rows "ห้องของ {name}" ·
   "{n}/{max} คน" · "เข้าร่วม" (mismatched rows greyed with the reason line); while empty "กำลังค้นหาห้อง…" then after
   4 s "ยังไม่พบห้อง — ให้เพื่อนกดเปิดห้อง หรือใส่ IP ของเจ้าห้องด้านบน"; with no Wi-Fi on this device (`has_lan()` false)
   the empty list says `no_lan` instead; help "ต้องอยู่ Wi-Fi เดียวกัน · Windows: ถ้ามีหน้าต่างไฟร์วอลล์ ให้กดอนุญาต
   (เครือข่ายส่วนตัว)".
2. **Connecting**: "กำลังเชื่อมต่อ…" + "ยกเลิก" (existing key if present, else new).
3. **In a room** (hosting or joined): card "ห้องของ {name}"; host only: "IP ของเครื่องนี้: {ips}" (28 px, readable across a
   table) with "คัดลอก IP" (copies the first IP; the button then reads "คัดลอกแล้ว") and "ให้เพื่อนที่อยู่ Wi-Fi
   เดียวกันกดประตูเทียบยานแล้วเลือกห้องนี้ หรือใส่ IP นี้"; members list "คนในห้อง": name + "(เจ้าห้อง)"/"(คุณ)" + where
   line; "กองทัพที่อยากใช้: {army}" cycle button (members; "ให้เจ้าห้องเลือก" = ""); while `room_state() == "setup"`
   (members only) a section "ที่นั่ง" lists `setup_seats()` as rows "ทีม {n} · {owner} · {army}" (`owner` = member name,
   "บอท" or "(คุณ)") with "นั่งที่นี่" on bot seats and "ลุกจากที่นั่ง" on your own (`net.claim(k)`); buttons "กลับดาดฟ้า"
   (pop, stay online) and "ออกจากห้อง" (member) / "ปิดห้อง" (host, with the confirm "ปิดห้อง? เพื่อนทุกคนจะหลุดจากห้อง").
4. **Refused / lost**: the reason (§7.3) in the list area, back to state 1.

Layout rules of LOBBY_SPEC §7.1 (three sizes, no overflow or overlap, buttons ≥ 44 px, English without Thai except
player names). The virtual keyboard on phones: the IP field sits near the top (under the name row) so the on-screen
keyboard of a landscape phone does not cover it; `follow_focus` keeps a focused field in view.

### 7.3 Every new string

Thai first, English pair for every one. Whole keys only (`I18n.t` then `.format()`). New fragments
`ui/i18n/online.json` (DECK) and `ui/i18n/online_battle.json` (BATTLE), added to `I18n.FRAGMENTS` by DECK in step D0.
Before adding a key, check it is not already in `data/i18n_en.json`, `ui/i18n_extra.json`, `I18n.EN` or another fragment
(a duplicate fails `test_i18n_fragments`); reuse such keys instead (`บอท`, `คุณ`, `เล่นต่อ`, `ออกจากการรบ`, `กลับล็อบบี้`,
`ประตูเทียบยาน`, `เร็วๆ นี้` exist). Player names and typed IPs are never translated.

| Thai | English | Fragment | Used by |
| --- | --- | --- | --- |
| ประตูเทียบยาน · เล่นกับเพื่อน | Docking Airlock · Play with friends | `hall.json` | deck sign |
| เจ้าห้องเป็นคนตั้งเกม — รอเจ้าห้องกดเริ่ม | The host sets up the game — wait for the host to start | `hall.json` | war table on a client |
| {name} เข้าห้องแล้ว | {name} joined | `hall.json` | deck toast |
| {name} ออกจากห้อง | {name} left | `hall.json` | deck toast |
| เจ้าห้องกำลังตั้งเกม — เลือกที่นั่งได้ที่ประตูเทียบยาน | The host is setting up a game — pick a seat at the docking airlock | `hall.json` | deck toast |
| ที่นั่ง | Seats | `online.json` | lobby seat section |
| ทีม {n} · {owner} · {army} | Team {n} · {owner} · {army} | `online.json` | seat row |
| นั่งที่นี่ | Sit here | `online.json` | seat claim |
| ลุกจากที่นั่ง | Leave this seat | `online.json` | seat claim −1 |
| ออนไลน์ · ห้องของ {name} · {n}/{max} คน | Online · {name}'s room · {n}/{max} players | `online.json` | `FriendTags` status |
| เล่นกับเพื่อน | Play with friends | `online.json` | lobby title |
| ชื่อของคุณ | Your name | `online.json` | name field |
| ผู้เล่น {n} | Player {n} | `online.json` | default name |
| เปิดห้อง | Host a room | `online.json` | button |
| ห้องที่พบใน Wi-Fi เดียวกัน | Rooms on this Wi-Fi | `online.json` | section |
| กำลังค้นหาห้อง… | Looking for rooms… | `online.json` | empty list |
| ยังไม่พบห้อง — ให้เพื่อนกดเปิดห้อง หรือใส่ IP ของเจ้าห้องด้านบน | No rooms yet — ask a friend to host, or enter the host's IP above | `online.json` | empty list after 4 s |
| คัดลอก IP | Copy IP | `online.json` | host card |
| คัดลอกแล้ว | Copied | (`ui/i18n_extra.json`, reused) | host card |
| {name} หลุดจากห้อง — รอต่อใหม่ | {name} dropped out — waiting for them to reconnect | `online.json` | deck toast |
| ออกจากเกม? ห้องจะปิด เพื่อนทุกคนจะหลุดจากห้อง | Quit the game? Your room closes and all friends are disconnected | `online.json` | main menu quit while hosting |
| ห้องของ {name} | {name}'s room | `online.json` | list row, card |
| {n}/{max} คน | {n}/{max} players | `online.json` | list row |
| เข้าร่วม | Join | `online.json` | list row |
| ใส่ IP ของเจ้าห้อง | Host's IP address | `online.json` | IP placeholder |
| ต่อด้วย IP | Join by IP | `online.json` | IP button |
| ต้องอยู่ Wi-Fi เดียวกัน · Windows: ถ้ามีหน้าต่างไฟร์วอลล์ ให้กดอนุญาต (เครือข่ายส่วนตัว) | Be on the same Wi-Fi · Windows: if a firewall window appears, allow it (private networks) | `online.json` | help |
| กำลังเชื่อมต่อ… | Connecting… | `online.json` | state 2 |
| IP ของเครื่องนี้: {ips} | This device's IP: {ips} | `online.json` | host card |
| ให้เพื่อนที่อยู่ Wi-Fi เดียวกันกดประตูเทียบยานแล้วเลือกห้องนี้ หรือใส่ IP นี้ | Friends on the same Wi-Fi open the docking airlock and pick this room, or type this IP | `online.json` | host card |
| คนในห้อง | In this room | `online.json` | members |
| (เจ้าห้อง) | (host) | `online.json` | members |
| (คุณ) | (you) | `online.json` | members |
| อยู่บนดาดฟ้า · กำลังตั้งเกม · กำลังรบ · อยู่ในอารีน่า · จัดกองทัพ · ดูตั้งค่า · อยู่หน้าแรก | On the deck · Setting up a game · In battle · In the arena · Building an army · In settings · On the main menu | `online.json` (seven keys) | where line |
| กองทัพที่อยากใช้: {army} | Army I'd like: {army} | `online.json` | pick button |
| ให้เจ้าห้องเลือก | Let the host choose | `online.json` | pick "" |
| กลับดาดฟ้า | Back to the deck | `online.json` | button |
| ออกจากห้อง | Leave the room | `online.json` | button |
| ปิดห้อง | Close the room | `online.json` | button |
| ปิดห้อง? เพื่อนทุกคนจะหลุดจากห้อง | Close the room? Everyone will be disconnected | `online.json` | confirm |
| รุ่นแอปไม่ตรงกัน: เจ้าห้อง {host} · คุณ {mine} — อัปเดตให้เป็นรุ่นเดียวกันก่อน | App versions differ: host {host} · you {mine} — update both to the same version first | `online.json` | `wrong_app` |
| กติกาหรือข้อมูลเกมไม่ตรงกัน (รุ่นกติกา {host} กับ {mine}) — อัปเดตให้เป็นรุ่นเดียวกันก่อน | Game rules or data differ (rules {host} vs {mine}) — update both to the same version first | `online.json` | `wrong_rules` |
| ระบบเล่นกับเพื่อนคนละรุ่นกัน — อัปเดตให้เป็นรุ่นเดียวกันก่อน | Different play-with-friends versions — update both to the same version first | `online.json` | `wrong_net` |
| ห้องเต็มแล้ว ({n}/{max} คน) | The room is full ({n}/{max} players) | `online.json` | `full` |
| เข้าได้เฉพาะเครื่องในวง Wi-Fi เดียวกัน | Only devices on the same Wi-Fi can join | `online.json` | `not_lan` |
| เครื่องนั้นไม่ใช่ห้องโต๊ะเทียน | That device is not a Candlelight Table room | `online.json` | `wrong_game`, `bad_message` |
| เจ้าห้องกำลังปิดห้อง | The host is closing the room | `online.json` | `closing` |
| เปิดห้องไม่ได้: พอร์ต {port} ถูกใช้อยู่ (เปิดแอปซ้อนกันอยู่หรือเปล่า) | Can't host: port {port} is in use (is the app open twice?) | `online.json` | `port_busy` |
| ไม่พบ Wi-Fi — ต่อ Wi-Fi ก่อนแล้วลองใหม่ | No Wi-Fi found — connect to Wi-Fi and try again | `online.json` | `no_lan` |
| IP ไม่ถูกต้อง | That IP address is not valid | `online.json` | `bad_ip` |
| ต่อไม่ได้ — เช็กว่าอยู่ Wi-Fi เดียวกันและเจ้าห้องยังเปิดห้องอยู่ | Could not connect — check you are on the same Wi-Fi and the room is still open | `online.json` | `timeout` |
| ค้นหาห้องอัตโนมัติไม่ได้บนเครื่องนี้ — เพื่อนใส่ IP แทนได้ | Automatic room finding is off on this device — friends can type the IP instead | `online.json` | host card when discovery could not bind |
| เจ้าห้องปิดห้องแล้ว | The host closed the room | `online.json` | `host_left` |
| การเชื่อมต่อหลุด — กำลังต่อใหม่… | Connection lost — reconnecting… | `online.json` | `reconnecting` |
| ต่อใหม่ไม่สำเร็จ — กลับมาเล่นคนเดียว | Could not reconnect — back to playing alone | `online.json` | `reconnect_failed` |
| ต่อใหม่ได้แล้ว | Reconnected | `online.json` | toast |
| เพื่อนคนหนึ่งนั่งได้ที่เดียว | Each friend can take only one seat | `online_battle.json` | `member_twice` |
| เพื่อนคนนี้ออกจากห้องไปแล้ว | That friend has left the room | `online_battle.json` | `member_gone` |
| แตะเพื่อสลับ: บอท · คุณ · เพื่อน | Tap to switch: bot · you · friends | `online_battle.json` | setup hint (online) |
| รอ {name}… | Waiting for {name}… | `online_battle.json` | `wait_remote` banner |
| เจ้าห้อง | Host | `online_battle.json` | banner name for the host |
| ดูอยู่ (ไม่มีที่นั่ง) | Watching (no seat) | `online_battle.json` | spectator banner |
| บอทเล่นแทน {name} (หลุดจากห้อง) | A bot is playing for {name} (disconnected) | `online_battle.json` | `SEAT gone` |
| บอทเล่นแทน {name} จนจบเกมนี้ | A bot plays for {name} until this game ends | `online_battle.json` | `SEAT left` |
| {name} กลับมาแล้ว | {name} is back | `online_battle.json` | `SEAT back` |
| ทำไม่ได้ตอนนี้ — เกมขยับไปแล้ว | Not now — the game moved on | `online_battle.json` | `ACT_NO` toast |
| ออกจากการรบ? บอทจะเล่นแทนคุณจนจบเกมนี้ | Leave the battle? A bot will play your seat until this game ends | `online_battle.json` | client leave dialog |
| ออกจากการรบ? เกมนี้จะจบสำหรับทุกคน | Leave the battle? This game ends for everyone | `online_battle.json` | host leave dialog |
| เจ้าห้องออกจากการรบ เกมนี้จบแล้ว | The host left the battle — this game is over | `online_battle.json` | `END` panel |
| รอเจ้าห้องเริ่มเกมใหม่ | Waiting for the host to start a new game | `online_battle.json` | client end panel |
| เกมไม่ตรงกับเจ้าห้อง — กำลังโหลดเกมใหม่จากเจ้าห้อง… | Out of sync with the host — reloading the game from the host… | `online_battle.json` | desync panel (1st) |
| ซ่อมแล้ว เกมตรงกับเจ้าห้องแล้ว | Repaired — the game matches the host again | `online_battle.json` | desync panel after resync |
| เกมไม่ตรงกับเจ้าห้อง — บันทึกไว้ในล็อกแล้ว ต้องออกจากเกมนี้ | Out of sync with the host — written to the log; this game has to stop | `online_battle.json` | desync panel (final) |
| เครื่องของ {name} ไม่ตรงกัน — กำลังส่งเกมให้ใหม่ | {name}'s game is out of sync — resending it | `online_battle.json` | host toast |
| การเชื่อมต่อหลุด — เกมนี้จบสำหรับเครื่องนี้ | Connection lost — the game ended on this device | `online_battle.json` | client end panel after `reconnect_failed` / `bad_message` |
| บอทเล่นแทนคุณอยู่ตอนนี้ | A bot is playing your seat for now | `online_battle.json` | toast + banner when the host plays your seat |

## 8. Android and Windows

- Android preset (`export_presets.cfg`, the Android `[preset.N.options]`): add `permissions/change_wifi_multicast_state=true`
  and `permissions/access_wifi_state=true` next to `permissions/internet=true` and `permissions/access_network_state=true`
  (both already true). Keystore fields stay empty (rule 2; CI greps them); `exclude_filter="packs/*"` stays (lint).
  Godot's multicast lock (`GodotNetUtils`) checks only `CHANGE_WIFI_MULTICAST_STATE`; `ACCESS_WIFI_STATE` is a harmless
  normal permission kept until discovery is tried on a device, then dropped if the room list works without it.
- `target_sdk` is the default today. Android has announced a local-network permission for later target SDKs: re-check
  LAN play (discovery and joining by IP) whenever `target_sdk` is raised.
- Discovery on phones: the host needs to *receive* broadcasts (multicast lock: Godot takes it when broadcast is enabled
  on a socket and the permission is present — set `set_broadcast_enabled(true)` on the receiving socket too). The joiner
  only sends a broadcast and receives a unicast beacon. **Not verified on a device in this round**: the Thai note asks
  the owner to try; manual IP entry with the IP shown on the host's card is the path that always works.
- Phones: a backgrounded app stops answering; ENet drops it after ≤ 8 s (a client becomes a gone seat; a host's friends
  all go to "reconnecting" — e.g. the host switching to a chat app for more than ~8 s to send the IP). The discovery
  socket closes while in the background (§1.2). The screen is kept on while online (§1.2).
- Windows: no preset change. The first "เปิดห้อง" triggers the Windows Firewall prompt for the exe; the player must allow
  private networks (help line, Thai note).
- Hotspot play (one phone shares its Wi-Fi): works like any LAN (addresses are private ranges).

## 9. Failure cases

| Case | Host sees | Friend sees | State after |
| --- | --- | --- | --- |
| Friend's Wi-Fi drops / app killed / phone sleeps | toast "{name} หลุดจากห้อง — รอต่อใหม่" at once ("{name} ออกจากห้อง" when the slot expires after 60 s); in battle `SEAT gone` and the host plays the seat | "การเชื่อมต่อหลุด — กำลังต่อใหม่…" on the deck status line and the battle banner for up to 60 s, then "ต่อใหม่ไม่สำเร็จ — กลับมาเล่นคนเดียว" (a battle ends with "การเชื่อมต่อหลุด — เกมนี้จบสำหรับเครื่องนี้") | slot kept 60 s (during a battle a seated slot is kept for its owner even after that); same `nid` gets it back with a resync |
| Host's Wi-Fi drops | every member drops; in battle the host's bots play all friends' seats | as above; if the host returns in 60 s they rejoin | — |
| Host closes the room / leaves the app | — | "เจ้าห้องปิดห้องแล้ว"; a battle shows the `END` panel | everyone offline |
| Host leaves the battle | — | `END` panel "เจ้าห้องออกจากการรบ เกมนี้จบแล้ว" | room stays, back to the deck |
| Wrong version | — | greyed row with the reason; manual IP → refused with the reason | not connected |
| Room full | — | `full` reason | not connected |
| Port in use (app opened twice) | `port_busy` reason, not hosting | — | offline |
| Discovery port in use | hosting works; card says discovery is off | rows do not appear; IP entry works | — |
| No Wi-Fi (mobile data only) | `no_lan` on "เปิดห้อง" | `no_lan` in the empty room list | offline |
| Café / hotel / guest Wi-Fi that isolates devices | hosting works, nobody can join | rows may not appear; `timeout` on join | use one phone's hotspot instead (Thai note) |
| Bad IP typed | — | `bad_ip` under the field | — |
| No answer at the IP | — | `timeout` after 5 s | — |
| Desync | toast with the friend's name; plays the seat on a final desync | loud panel, resync, or final panel | §4.7 |
| Stale or forged act | `ACT_NO`, warning in the log | toast "ทำไม่ได้ตอนนี้ — เกมขยับไปแล้ว" (stale only) | game continues |
| Oversize / junk message | sender disconnected, one log line | `bad_message` if from the host | — |
| Friend silent on a roll (app stuck) | after 15 s the host rolls that one entry (`bot:<seat>`, the seat's pid); the wake Timer is set by the host's own wait | — | — |
| A member floods heavy requests | answers stop at the per-game budget (§4.3), one log line | — | a 5th `RESYNC_REQ` → the host plays that seat |

## 10. Security basics

- **LAN only.** Nothing listens until the player taps "เปิดห้อง"; closing the room or leaving the screen state closes every
  socket. No UPnP, no port forwarding, no outside address. The host disconnects any peer whose
  `ENetPacketPeer.get_remote_address()` is not private, before authentication, and the discovery socket ignores and never
  answers non-private sources. Private = IPv4 `10/8`, `172.16/12`, `192.168/16`, `169.254/16`, `127/8`; IPv6 `::1`,
  `fe80::/10`, `fc00::/7` (`NetGate.is_private(ip)`). Carrier NAT `100.64/10` is not private. Both sockets bind IPv4 only
  (`0.0.0.0`): a phone or PC with a public IPv6 address is not reachable from the internet at the ENet level.
- **Private is not trusted:** café, hotel and school Wi-Fi also use private ranges; anyone there sees the host's name in
  the beacon and can join (round 1 has no approval or kick). The Thai note tells the owner to host on home Wi-Fi or his
  own hotspot.
- **Limits:** message caps, direction and size checks before decoding (§2.1), rate limits, per-game budgets for heavy
  requests (§4.3), at most 16 discovery rows, auth timeout 5 s, names cleaned to plain text (again on the client for names
  that come from the host)
  (Labels and `draw_string` only, no BBCode/`RichTextLabel`), the IP field accepts only a dotted IPv4 address with an
  optional `:port` (no host names, so no DNS lookups from typed text).
- **No code execution from the wire:** `bytes_to_var` without objects, no `str_to_var`/`Expression`/`load`/paths/URLs from
  messages, no RPC.
- **Authority:** the host decides order and seat ownership (§4.5) and overwrites `pid`; clients never accept acts from
  anyone but the host. Dice are trusted (friends; same as the Worker).
- **No secrets:** round 1 has no keys, tokens or accounts. `nid` is random and not secret; logs never print the
  `net.cfg` contents. (R7's signing key lives only in the Worker's secrets, §14.)

## 11. Files, owners and contracts (three builders in parallel, never the same file)

### 11.1 Ground rules (ARENA_SPEC §12.1 restated where they differ)

1. Each builder edits only the files it owns below. A failing check in another builder's file is reported, not fixed.
2. **Work only in `/home/user/candlelight-table-mp`** (branch `claude/multiplayer-wip`). Never touch
   `/home/user/candlelight-table` (another workflow edits it). No commits, pushes or PR changes; leave everything in the
   working tree for the lead.
3. **First steps**, each said aloud in the builder's notes with the time when done:
   - **N0 (NET-CORE, ≤ 20 min)**: `net/net_proto.gd` with every kind id and name of §2.2 and `NetProto.VERSION`;
     `net/net_session.gd` skeleton with the exact public API of §11.3 (methods may return `ERR_UNAVAILABLE` until built,
     signals declared); the `Net` autoload line in `project.godot`; import refresh. Check:
     `grep -q 'Net="\*res://net/net_session.gd"' godot/project.godot`. Until then DECK and BATTLE build against the
     contract with `get_node_or_null(^"/root/Net")` guarded.
   - **D0 (DECK, ≤ 10 min)**: `ui/i18n.gd` `FRAGMENTS` += `res://ui/i18n/online.json`, `res://ui/i18n/online_battle.json`
     (in that order, after `arena_data.json`); create both files (`online_battle.json` as `{}`: from then on BATTLE owns
     it); update `test_i18n_fragments.gd`'s expected list (reason: two online fragments added on purpose). Check:
     `grep -q online_battle godot/ui/i18n.gd`.
   - **D1 (DECK, right after D0, ≤ 45 min)**: the eggs MultiMesh + `FriendTags` + hidden `you` tag with 5 fake friends, and
     the two §6.3 online views measured on all four levels; write the numbers in the notes before building the lobby
     screen. Over target → apply the §6.3 fallback, measure again, report.
   - **B0 (BATTLE, ≤ 30 min)**: `ui/battle/lockstep.gd` and `ui/battle/net_match_runner.gd` with the §11.3 API and the
     in-memory pair used by `test_lockstep` (no sockets); `test_net_match_runner`'s host-equivalence check green.
4. **Cross-references:** another builder's scripts only through `load(PATH)` at use time or the autoload `Net`, never
   `preload` and never their `class_name`, **except** `NetProto` (kind ids) and `NetGate` (reason keys), which everyone may
   use by class name once N0 is in. The finished classes (`MatchRunner`, `SeatPlan`, `Battle`, `BtRoller`, `BtBot`,
   `HallLayout`, `HallBuilder`, `HallAvatar`, `Rings`, `CandleStyle`, `GameData`) may be used by anyone; only their
   owners below edit them.
5. Do not touch the old app, `core/` (apart from DECK's `APP_VER` line), `data/**` (a new file there changes `DATA_HASH`),
   `assets/**`, `ui/battle/match_runner.gd`, `ui/battle/seat_plan.gd`, `scenes/arena/**`, `ui/screens/arena_screen.*`,
   or this spec.
6. Godot `~/godot-bin/godot` (4.7.1); render tests under `xvfb-run`. Four CPUs shared with another workflow: `nice -n 10`
   for render and full runs; never `pkill`/`killall` or kill by name or pattern, only PIDs you started (the flow test
   kills only the PID it created). Imports only under the shared lock:
   `flock <scratchpad>/friends-r1/import.lock timeout 600 ~/godot-bin/godot --headless --path godot --import`, where
   `<scratchpad>` = `/tmp/claude-0/-home-user-candlelight-table/14efda3d-1836-580a-86e4-aead22ae2e85/scratchpad`.
   Test output: `TEST_OUT=<scratchpad>/friends-r1/out-<track>`; scratch files only under `<scratchpad>/friends-r1/`.
   Tests never write the machine's `user://settings.cfg` or `user://net.cfg` (use `App.settings_file` / `Net.cfg_file`).
   Every test that opens a socket uses the §1.5 test ports.
7. AGENTS hard rules: rule 1 (no franchise names anywhere, including test names and PNGs), rule 2 (no secrets), rule 4
   (Thai + English, §7.3), rule 5 (§4: nothing random or time-based enters `Battle.apply` except through acts), rule 6
   (§6.3–§6.4), surgical edits (no re-formatting or re-ordering), short Thai code comments like the surrounding code,
   never delete / skip / loosen a test (a changed expectation says why in a comment and in the final report).

### 11.2 Ownership

| Track | Owns (new unless marked edit) |
| --- | --- |
| **NET-CORE** (session, transport, discovery, codec, version gate, flow test) | `net/net_session.gd` (`NetSession`, autoload `Net`), `net/net_proto.gd` (`NetProto`), `net/net_discovery.gd` (`NetDiscovery`), `net/net_gate.gd` (`NetGate`); edit `project.godot` (`[autoload]` `Net` only); edit `export_presets.cfg` (the two Android permission lines only); tests: `tests/unit/test_net_proto.gd`, `test_net_gate.gd`, `test_net_discovery.gd`, `test_net_loopback.gd`, `tests/flow/test_lan_flow.gd`, `tests/net/lan_peer.gd` (the second process; not matched by `run.sh`'s `tests/flow/test_*.gd` glob); edit any existing test that lists autoloads or preset permissions (reason: the `Net` autoload / LAN permissions) |
| **DECK** (presence, friends on the deck, airlock screen, strings, version line) | `scenes/hall/hall_friends.gd` (`HallFriends`); `ui/widgets/friend_tags.gd` (`FriendTags`); `ui/screens/lobby.tscn` + `lobby.gd`; `ui/online_text.gd` (`OnlineText`: reason key → Thai template + args, where → Thai); `ui/i18n/online.json`; edit `ui/i18n.gd` (`FRAGMENTS` only), `ui/i18n/hall.json`, `ui/i18n/menu.json` (only if a menu key changes); edit `scenes/hall/hall_world.gd` (rings capacity, `friends` child, `set_you_tag_visible`, `set_slot_colour`), `scenes/hall/hall_camera.gd` (`signal view_changed` only), `ui/screens/hall_screen.gd` + `.tscn` (online station, `open_online`, `SIGNS.online`, `SOON` without online, pose sending, `WHERE`, toasts, `%FriendTags`), `ui/screens/main_menu.gd` + `.tscn` (Online button opens the deck + lobby; badge hidden); edit `core/version.gd` (the `APP_VER` line only); tests: new `tests/unit/test_hall_friends.gd`, `test_online_text.gd`, `tests/unit/fixtures/fake_net.gd`, `tests/render/test_lobby.gd`; edit `tests/unit/test_hall_text.gd`, `test_menu_text.gd`, `test_i18n_fragments.gd`, `tests/render/test_hall.gd`, `tests/render/test_menu_screens.gd` |
| **BATTLE** (lockstep driver, seats, digest checks, disconnect → bot, setup and battle screen changes) | `ui/battle/net_match_runner.gd` (`NetMatchRunner`, inner `NetRec`), `ui/battle/lockstep.gd` (`Lockstep`), `ui/battle/net_seats.gd` (`NetSeats`), `ui/battle/net_battle_link.gd` (`NetBattleLink`); `ui/i18n/online_battle.json` (after D0); edit `ui/screens/battle_setup.gd` (+ `.tscn` if a node is needed), `ui/screens/battle_screen.gd` (+ `.tscn` if needed); tests: new `tests/unit/test_lockstep.gd`, `test_net_seats.gd`, `test_net_match_runner.gd`, `test_online_battle_text.gd`; edit `tests/render/test_battle_screen.gd` (online states added; offline checks untouched) |
| **Integration** (the lead, after all three) | the full run; `docs/GODOT.md` §1.3 rows + the `Net` line; `godot/README.md` (`net/` row); `godot/docs/STATUS.md`; one line in `PLAN.md` R3 (§13.4); `ARCHITECTURE.md` §3 `Net` paragraph; §17 of this file; the Thai note (§15) |

**Paths** (constants in the callers; `load(PATH)` at use time):

| Constant | Path | Owner |
| --- | --- | --- |
| `LOBBY_SCREEN` | `res://ui/screens/lobby.tscn` | DECK |
| `BATTLE_SCREEN` | `res://ui/screens/battle_screen.tscn` (existing) | BATTLE edits |
| `NET_BATTLE_LINK` | `res://ui/battle/net_battle_link.gd` | BATTLE (loaded by `Net`) |
| `ONLINE_TEXT` | `res://ui/online_text.gd` | DECK (used by BATTLE only through `load`) |

### 11.3 Contracts (exact; signals and methods by these names)

**`NetSession`** (`net/net_session.gd`, autoload `Net`, `extends Node`; NET-CORE)

```gdscript
signal state_changed(state: StringName)            # §1.2 states
signal members_changed()                           # MEMBERS applied (host: after any change)
signal found_changed()                             # discovery list changed
signal message(from_slot: int, kind: int, body: Dictionary)   # validated messages of kinds 20–33 (SETUP, CLAIM, battle)
signal pose(slot: int, pose: Dictionary)           # POSE / POSE_STOP of another member (host relays)
signal refused(key: String, args: Dictionary)      # §3 keys and local failure keys
signal lost(key: String)                           # host_left, timeout, bad_message, reconnect_failed
signal reconnected()
const PORTS := {"game": 24680, "disc": 24681}
const MAX_PLAYERS := 6
var ports: Dictionary = PORTS.duplicate()
var probe: PackedStringArray = []
var cfg_file := "user://net.cfg"
var max_players := MAX_PLAYERS
var hello_extra: Dictionary = {}                   # tests only
func state() -> StringName
func is_online() -> bool                           # hosting, joined or reconnecting
func is_host() -> bool
func my_slot() -> int                              # -1 offline
func my_name() -> String
func set_my_name(nm: String) -> String             # cleaned; saved in cfg_file; returns the cleaned name
func host() -> Error                               # OK, or ERR_CANT_CREATE (refused("port_busy")) / ERR_UNCONFIGURED (refused("no_lan"))
func join(ip: String, port: int = 0) -> Error      # ERR_INVALID_PARAMETER → refused("bad_ip")
func leave() -> void                               # BYE; host: closes the room (END to a running battle first)
func find(on: bool) -> void                        # join list open/closed (queries + beacons)
func found() -> Array[Dictionary]                  # [{t, ip, port, nm, n, max, st, app, rules, ok: bool, why: String}]
func discovery_on() -> bool                        # host: false when the discovery port could not bind
func members() -> Array[Dictionary]                # member records (§1.2), slot order
func member(slot: int) -> Dictionary               # {} when absent
func room_state() -> String                        # "deck" / "setup" / "battle"
func setup_seats() -> Array[Dictionary]            # seats of the last SETUP while open: [{team, owner, fac}], else []
func claim(k: int) -> void                         # CLAIM (members only, while the setup is open)
func local_ips() -> PackedStringArray              # private IPv4 of this device, loopback excluded
func send(kind: int, body: Dictionary, to_slot: int = -1) -> bool   # -1: client → host, host → all; false if invalid/offline
func send_pose(p: Dictionary, stop: bool) -> void
func set_where(where: StringName) -> void
func set_pick(fac: String) -> void
func poll() -> void                                # tests: one manual poll
```

**`NetProto`** (static): `const VERSION := 1`; kind constants `HELLO … END` with the ids of §2.2; `static func encode(kind:
int, body: Dictionary) -> PackedByteArray` (empty on an invalid body); `static func decode(bytes: PackedByteArray) ->
Dictionary` → `{kind, body}` or `{error: String}`; `static func clean_name(s: String) -> String`; `CAPS`.

**`NetGate`** (static): `static func check_hello(hello: Dictionary, n_members: int, max_players: int, remote_ip: String,
known_nid: bool) -> Dictionary` → `{key, args}` (`key` "" = pass); `static func check_beacon(b: Dictionary) -> Dictionary`;
`static func is_private(ip: String) -> bool`; `static func parse_ip(text: String) -> Dictionary` → `{ip, port}` or `{}`;
`const KEYS` (every key of §3).

**`NetDiscovery`** (RefCounted): `func start_host(port: int, beacon: Callable) -> bool`, `func start_find(port: int,
probe: PackedStringArray) -> bool`, `func stop() -> void`, `func poll(now_ms: int) -> bool` (true when the list changed),
`func found() -> Array[Dictionary]`, `static func make_beacon(info: Dictionary) -> PackedByteArray`,
`static func parse(bytes: PackedByteArray, ip: String) -> Dictionary`.

**`HallWorld` additions** (DECK): `var friends: HallFriends` (created in `_ready`, empty and hidden offline);
`func set_you_tag_visible(on: bool) -> void`; `func set_slot_colour(c: Color) -> void` (local egg + ring);
`func head_point() -> Vector3` (local egg top for `FriendTags`).

**`HallFriends`** (`scenes/hall/hall_friends.gd`, Node3D; DECK)

```gdscript
signal moved()                                     # some friend moved this frame
const MAX := 5
func setup(world: Node3D, rings: Rings) -> void
func apply_level(l: String) -> void
func set_friend(slot: int, nm: String, colour: Color) -> void
func remove_friend(slot: int) -> void
func clear() -> void
func push_pose(slot: int, pose: Dictionary, now_ms: int) -> void
func friend_count() -> int
func friend_pos(slot: int) -> Vector3
func heads() -> Array[Dictionary]                  # [{slot, nm, pos: Vector3}]
func counts() -> Dictionary                        # {"friends", "eggs_visible", "processing": bool}
static func spawn_for(slot: int) -> Vector3
static func interp(samples: Array, now_ms: int) -> Dictionary   # pure: {x, z, yaw, sp, moving: bool, done: bool}
```

**`FriendTags`** (`ui/widgets/friend_tags.gd`, Control; DECK): `bind(world: Node3D)`, `set_status(text: String)`,
`set_you(text: String)`, `set_hint(text: String)` (§6.3 fallback), `refresh()`, `drawn() -> Array[Dictionary]`
(`[{text, pos: Vector2}]` of the last draw, for tests), `const FONT_SIZE := 22`.

**`NetMatchRunner`** (`ui/battle/net_match_runner.gd`, `extends MatchRunner`; BATTLE). The battle screen keeps using only
the `MatchRunner` API plus:

```gdscript
signal changed()                                   # an act arrived, a request was answered, a wake fired
static func host(plan: Dictionary, link: Lockstep, dice_seed: int = 0) -> NetMatchRunner
static func client(plan: Dictionary, my_seat: int, link: Lockstep, dice_seed: int = 0) -> NetMatchRunner
var lockstep: Lockstep
func online() -> bool                              # true
func is_net_host() -> bool
func waiting_for() -> PackedStringArray            # seat names the game waits for ("" names → "เจ้าห้อง" in the screen)
func next_wake_ms() -> int                         # 0 = none
func seat_gone(k: int) -> void                     # host
func seat_back(k: int) -> void                     # host
func gone_seats() -> PackedInt32Array
func checks() -> int                               # digest checks passed on this device
func sync_state() -> StringName                    # &"ok", &"desync", &"desync_final"
func receive(kind: int, body: Dictionary, from_slot: int) -> void
```

**`Lockstep`** (`ui/battle/lockstep.gd`, RefCounted, pure, transport-agnostic; BATTLE): `const DIGEST_EVERY := 8`,
`const ROLL_WAIT_MS := 15000`; `func _init(send: Callable, is_host: bool, my_slot: int, gen: int, owners: Array)`
(`send.call(kind, body, to_slot)`); `static func gate(st: BattleState, seat: int, act: Dictionary) -> String`;
`func host_logged(act: Dictionary, b: Battle) -> void`; `func end_burst(b: Battle) -> void`;
`func host_request(from_slot: int, body: Dictionary, b: Battle) -> String`; `func client_act(body: Dictionary, b: Battle)
-> Array[Dictionary]` (events, DESYNC included); `func resync_body(plan: Dictionary, b: Battle) -> Dictionary`;
`static func rebuild(body: Dictionary) -> Battle`.

**`NetSeats`** (static; BATTLE): `defaults(members, seed_v) -> Dictionary`, `claim(choice, slot, k) -> bool` (changed?),
`seats_body(choice) -> Array` (the `SETUP.seats` list), `validate(choice, members) -> PackedStringArray`,
`build(choice, members) -> Dictionary` (plan + `owners`), `error_text(code, choice) -> String` (Thai keys of
`online_battle.json`), `pid_of(slot: int) -> String` (`"n%d"`).

**`NetBattleLink`** (Node; BATTLE): created by `Net`; `func current_runner() -> NetMatchRunner`; no per-frame work.

**Contract between DECK and NET-CORE for the screen states:** the lobby screen shows exactly the `found()` rows, the
`members()` list and the `refused`/`lost` keys; it never opens sockets itself. **Between BATTLE and NET-CORE:** battle
messages only through `Net.send` / `Net.message`; slots, not peer ids.

## 12. Tests

Rules of LOBBY_SPEC §7.1 apply to every new screen check. Every socket test uses the §1.5 test ports and cleans up
(`leave()`, sockets closed) even on failure.

### 12.1 Changed expectations (behaviour changed on purpose; the reason goes in a comment in the test too)

| Test | Today | Becomes | Why |
| --- | --- | --- | --- |
| `test_hall_text` (`:58-60`) | three coming-soon stations (online, adventure, vault) | two (adventure, vault); `online` has the sign "ประตูเทียบยาน · เล่นกับเพื่อน" | the airlock opens the online screen |
| `test_hall` `_check_stations` (`:436-455`) | online / adventure / vault show the soon panel | `online` pushes the lobby screen (depth 3), back returns to the deck at the airlock with the camera current; adventure and vault unchanged; the walk-away check uses the adventure front | same |
| `test_menu_screens` (`:215-222`), and any other test that asserts the Online badge or toast | Online shows the "เร็วๆ นี้" toast | Online opens the deck and the lobby screen (depth 3); no badge | same |
| `test_menu_text` (version) | "0.4" | "0.5" | APP_VER bump |
| `test_i18n_fragments` | six fragments | eight, in the D0 order | online fragments |
| autoload / preset listing tests, if any | — | + `Net`; + two Android permissions | NET-CORE |

Unchanged and must stay green: every core, golden and oracle suite (byte-identical), `test_match_runner`,
`test_seat_plan`, `test_lobby_flow`, `test_hall_reach`, `test_settings_flow`, `test_arena_flow`, `test_budgets`, the
deck's offline views and idle rule, the arena suites, the data lint.

### 12.2 Unit (headless; they also run in the exported game unless they open sockets — socket suites skip themselves in
the exported self-test)

- **NET-CORE** `test_net_proto.gd`: round trip of every kind with a valid body (ints stay `int`, `PackedInt32Array`
  survives, nested acts equal after `ActLog.canon`); floats refused anywhere; an object payload made with
  `var_to_bytes_with_objects` refused; oversize refused **before** decoding (a 2 MiB buffer returns `{error}` without
  allocating it as a Variant); unknown kind, bad types, out-of-range ints, long strings, deep nesting, too many items
  refused; extra keys dropped; `clean_name` (control characters, newlines, 40 characters → 20, empty).
- **NET-CORE** `test_net_gate.gd`: the §3 matrix (each key alone, priority order when several fail, a reconnecting `nid`
  is never `full`); `is_private` on every range of §10 plus public, CGNAT and malformed addresses; `parse_ip` ("192.168.1.5",
  "192.168.1.5:24680", spaces, "999.1.1.1", "a.b.c.d", "example.com", ports 0 and 70000 → `{}`).
- **NET-CORE** `test_net_discovery.gd`: `make_beacon` ≤ 512 bytes with a 20-character Thai name; `parse` ignores junk,
  oversize, wrong `g`, non-private sources; mismatched versions give `ok = false` with the right key; dedupe by token
  (127.0.0.1 and a LAN address → one row, the LAN IP kept); loopback: a host `NetDiscovery` on the test disc port answers
  a query sent to `probe = ["127.0.0.1"]` within 200 ms of polling; entries expire after 4 s (fake `now_ms`).
- **NET-CORE** `test_net_loopback.gd`: two `NetSession` nodes under `/root/Host` and `/root/Cli`, each with its own
  `SceneMultiplayer` (`get_tree().set_multiplayer(SceneMultiplayer.new(), path)`), driven from `_process` with the manual
  poll loop (`poll(); OS.delay_msec(1)`, verified pattern): join 127.0.0.1 → `WELCOME`, slot 1, both member lists equal;
  `hello_extra = {"app": "x"}` → `refused("wrong_app", {host, mine})` and the peer disconnected; `max_players = 1` →
  `full`; a raw `send_bytes` before authentication is dropped; an oversize message disconnects the sender; a `POSE`
  relayed by the host reaches a second client with `s`; `leave()` on a client → host `members_changed`; `leave()` on the
  host → client `lost("host_left")`; a second host on the same game port → `ERR_CANT_CREATE` + `refused("port_busy")`;
  the same `nid` reconnecting gets the same slot; `HB` keeps members alive; no `Net` processing offline
  (`is_processing()` false, no Timer child).
- **DECK** `test_hall_friends.gd`: `interp` (100 ms delay, linear position, shortest-arc yaw across ±π, 150 ms
  extrapolation cap then hold, snap above 3 m, `done` when settled); `spawn_for(0..5)` free (`HallLayout.blocked` with
  0.35) and ≥ 0.8 m apart; set/remove friends keeps the MultiMesh visible count and the rings in step; capacity
  `1 + IDS.size() + 2 + MAX`; processing stops 10 frames after the last sample.
- **DECK** `test_online_text.gd`: whole keys of `lobby.gd/.tscn`, `friend_tags.gd`, `online_text.gd` and the hall
  additions; every `NetGate.KEYS` and local failure key has a Thai template and an English pair with the same
  `{placeholders}`; no Thai under `net/`.
- **BATTLE** `test_lockstep.gd` (pure; host `NetMatchRunner` + two client runners joined by an in-memory transport that
  delivers in order, with optional drop/tamper hooks; 2 teams × 2 seats: host seat, two client seats, one bot; small
  table; clients use `auto_human` with fixed `dice_seed`s): play to the end; after every delivered act each client's
  digest equals the host's at that seq; acts with `dg` at least every 8 seqs; every act's `pid` matches its seat (bots
  ""); a client never applies its own act before the echo; **stale** `base` → `ACT_NO stale` and the game continues;
  **forged** pid / another seat's squad / `endph` from a client → `not_yours`, nothing logged; a roll answer for an entry
  that is not the client's → `not_now`; **disconnect**: drop client 2 mid-game → `SEAT gone`, the host plays its seat
  with pid `"n2"` to the end, rolls with `bot:<seat>`; **reconnect**: rebuild client 2 from `resync_body` → digest equal,
  `SEAT back`, it plays on; **desync**: tamper one delivered act (a die value) → the client raises `DESYNC` within 8 acts
  (event in its queue, `Log` error line with seq and both digests, `sync_state() == &"desync"`), resync repairs it
  (digest equal, `&"ok"`); tamper the resync too → `&"desync_final"` and the first differing `state_ints()` index logged;
  a spectator (no seat) ends with the same digest.
- **BATTLE** `test_net_match_runner.gd`: **host equivalence**: a host `NetMatchRunner` with no remote humans (one host
  seat on `auto_human`, the rest bots) and `dice_seed` = the table seed produces the **same act log and digest** as
  `MatchRunner` on the same plan (proves the `flush` override changes nothing offline-like); a client runner never calls
  `bot_step` (spy subclass), its `flush` returns 0 and leaves the log unchanged; `can_select` false while in flight;
  `wait_remote` states and `waiting_for()` names; `next_wake_ms()` set when a remote roll waits, and after 15 s of fake
  time the host rolls that entry (`bot:<seat>`, the seat's pid).
- **BATTLE** `test_net_seats.gd`: defaults for 1–6 members; owner cycling order; `claim` (a bot seat is taken and the
  previous seat freed; a seat owned by someone else, the host's seat or an out-of-range `k` is ignored; −1 frees);
  `member_twice`, `member_gone`; `build`
  gives `bot = false`, `pid = "n<slot>"`, `nm` for owned seats and `""` for bots, the same lists as `SeatPlan.build` for
  the same seed, `owners` per seat.
- **BATTLE** `test_online_battle_text.gd`: whole keys of the online parts of `battle_setup.gd`, `battle_screen.gd`,
  `net_seats.gd`; English pairs with the same placeholders.

### 12.3 Flow (headless, quick run): `tests/flow/test_lan_flow.gd` + `tests/net/lan_peer.gd` (NET-CORE; needs all three)

As built, the UI flow below is `tests/flow/test_friends_flow.gd` + `tests/net/friends_peer.gd` (integration; it also
covers a rejoin after the app is reopened and a refused older app); `test_lan_flow.gd` + `lan_peer.gd` cover the session
layer between two processes. The review round added unit checks for its fixes in `test_lockstep`, `test_net_loopback`,
`test_net_proto`, `test_net_discovery` and `test_net_battle_link`, and render checks in `test_hall`, `test_lobby` and
`test_battle_screen`.

Host = this process with the real UI (min level, Thai, egg figures, touch off, test settings and net cfg files, test
ports). Peer = a second Godot process started with
`OS.create_process(OS.get_executable_path(), ["--headless", "--path", ProjectSettings.globalize_path("res://"),
"--audio-driver", "Dummy", "-s", "tests/net/lan_peer.gd", "--", "--net-port=<P>", "--status=<file>", "--name=เพื่อน"])`;
the peer runs the real UI too and appends status lines (`see_host x z`, `battle seat=1`, `over seq=<n> dg=<hex>
checks=<n>`, …) to `<file>` under `TEST_OUT`; the host polls that file. The host kills **only that PID** with
`OS.kill(pid)`, also in its failure path. Target ≤ 300 s.

1. Main menu → Online → the deck and the lobby screen (depth 3); name "เจ้าห้อง"; "เปิดห้อง" → hosting; the card lists the
   device's private IPs (or none in a sandbox) and discovery on.
2. Start the peer: it opens its lobby screen with `probe = ["127.0.0.1"]`, finds the host's row (versions ok), taps
   "เข้าร่วม" → joined as slot 1. The host's members list shows "เพื่อน"; a deck toast "เพื่อน เข้าห้องแล้ว".
3. Both back to the deck. The peer walks 2 m forward with the stick: on the host `world.friends.friend_count() == 1`, the
   friend converges to within 0.3 m of the peer's reported position, `FriendTags.drawn()` holds "เพื่อน" and the host's
   own tag, the `you` Label3D is hidden; the peer reports `see_host`. Both stop: after 10 frames the host's hall
   processes nothing.
4. The host walks to the war table → setup in online mode: 2 teams × 2 seats, seat 0 host, seats 1–3 bots, small table,
   300 points, fixed seed. The peer gets the deck toast, opens its airlock screen, sees the seat list and taps "นั่งที่นี่"
   on seat 1 (`CLAIM`): the host's seat 1 row shows "เพื่อน". Start → both on the battle screen (`battle seat=1`).
5. Both turn on "ให้บอทเล่นแทน" at instant speed: the game ends on both; the peer's `over` line has the host's final seq
   and digest, `checks ≥ seq / 8`, no DESYNC on either side; every act of seat 1 carries pid "n1".
6. Host "เล่นอีกครั้ง" (gen 2): after ≥ 20 acts the host kills the peer: within 10 s the host shows
   "บอทเล่นแทน เพื่อน (หลุดจากห้อง)", the game reaches the end, seat 1's later acts carry pid "n1".
7. Back to the deck → airlock → "ปิดห้อง" → offline; binding the test game port again succeeds (sockets closed); this
   machine's settings and `net.cfg` untouched.

### 12.4 Render (xvfb, `nice -n 10`)

- **DECK** `test_hall.gd` additions: 5 fake friends (`world.friends.set_friend` + `push_pose`, no sockets) + `FriendTags`
  + online look; the two §6.3 online views printed and asserted on all four levels; the offline views unchanged; the
  idle rule with friends standing still; a walking friend makes only `HallFriends` process; names in English mode are
  the players' names (no translation) and the status line is English; PNGs `hall_friends_<level>.png`,
  `hall_friends_phone_min.png`.
- **DECK** `test_lobby.gd`: every §7.2 state through `fake_net.gd` (empty list, 2 found rows with one greyed mismatch,
  connecting, hosting card with 2 IPs and discovery off, joined card with 6 members and long names, the setup seat list
  with 6 seats and both claim buttons, each refused key) at
  the three sizes, Thai and English: no overflow or overlap, buttons ≥ 44 px, no Thai in English mode except player
  names; IP field validation; PNGs `lobby_find_th.png`, `lobby_find_en.png`, `lobby_room_th.png`, `lobby_refused.png`.
- **BATTLE** `test_battle_screen.gd` additions (in-memory host + client runners, no sockets): the client screen in
  `wait_remote` (banner "รอ {name}…"), a spectator, seat-gone toast, the desync panel in both stages, client and host leave
  dialogs, client end panel without "เล่นอีกครั้ง"; three sizes, Thai and English; offline checks untouched; PNGs
  `battle_online_wait.png`, `battle_desync.png`.

### 12.5 How to run

```bash
G=~/godot-bin/godot; S=/tmp/claude-0/-home-user-candlelight-table/14efda3d-1836-580a-86e4-aead22ae2e85/scratchpad
T=$S/friends-r1/out-<track>; cd /home/user/candlelight-table-mp
flock $S/friends-r1/import.lock timeout 600 $G --headless --path godot --import     # after new class_name scripts
timeout 600 $G --headless --path godot -s tests/run_tests.gd -- test_net             # unit suites by name fragment
TEST_OUT=$T timeout 600 $G --headless --path godot --audio-driver Dummy -s tests/flow/test_lan_flow.gd
TEST_OUT=$T timeout 900 nice -n 10 xvfb-run -a -s "-screen 0 1280x720x24" $G --path godot --rendering-driver opengl3 \
  --resolution 1280x720 --audio-driver Dummy -s tests/render/test_hall.gd
python3 godot/tools/validate_data.py
TEST_OUT=$T nice -n 10 bash godot/tests/run.sh full        # once, at the end, after all three tracks are done
```

## 13. Round 2 (design only): internet play through a small relay room

### 13.1 What exists on the server (the private server repo, read-only this round)

The Worker binds D1 only (no WebSocket, no Durable Object). Battle rooms live in D1 and the old page polls them; the
server caps a room's act log below what a 6-seat game needs (≈ 750 acts) and its rules gate refuses a v10 client today.
It already has sessions (Google, guest and pairing sign-in) that a relay could reuse. (This public spec names no file
lines or commits of the private repo.)

### 13.2 Relay room

- **One Durable Object per room code** (`RelayRoom`, SQLite-backed class so it fits the free plan:
  `[[durable_objects.bindings]]` + `[[migrations]] new_sqlite_classes`), using the **WebSocket hibernation API** so idle
  rooms cost nothing. Check Cloudflare's current Durable Object and WebSocket limits and pricing before building.
- `POST /api/relay` → `{code, host_key}` (5-letter room code; `host_key` random, returned once, kept only in the DO);
  `GET /api/relay/<CODE>` with `Upgrade: websocket`. The host proves itself with `host_key` in a handshake header
  (`WebSocketPeer.handshake_headers`, e.g. `X-Relay-Key`) or in its first frame — **never in the URL query**, which ends up
  in Worker, CDN and proxy request logs (rule 2). Host = peer 1; others get 2..6.
- The DO **forwards opaque binary frames** and keeps only membership: no game state, no act log, no simulation, no
  parsing beyond a 1-byte target header (`0` = to host, `1..6` = to that peer, `255` = to all but sender; the DO rewrites it
  to the sender's id on delivery). Caps: ≤ 6 peers, frame ≤ 16 KiB (`RESYNC` is chunked by the client), ≤ 30 frames/s
  per socket (poses at ~5 Hz over the internet), close after 10 min with no frames, close everyone when the host leaves.
- Optional sign-in to create rooms (the existing session token) to cap abuse; joining needs only the code.

### 13.3 Client

`net/relay_peer.gd extends MultiplayerPeerExtension` wrapping `WebSocketPeer` (binary frames, wss through `App.server`).
`NetSession` uses it in place of `ENetMultiplayerPeer`; the codec, lockstep and presence run unchanged (that is why
round 1 uses `send_bytes` and slots). The auth gate needs a **relay variant**: today `_on_authenticating` / `_host_auth`
call ENet-only `get_peer(id).get_remote_address()` and `set_timeout`, and `NetGate` refuses non-private addresses
(`not_lan`), which would refuse every relay peer. Relay mode skips the address check and ENet timeouts (the DO and the
room code are the boundary; liveness = `HB` silence), and keeps every other check (game, `np`, `APP_VER`, `RULES_V`,
`DATA_HASH`, full, closing). Godot's own `WebSocketMultiplayerPeer` cannot be used: its server side
must be a Godot instance. The airlock gets "เล่นผ่านอินเทอร์เน็ต" with "สร้างห้อง" (shows the code) and "ใส่รหัสห้อง".
Rejoin works as on the LAN (plan + acts from the host), so `BT_MAX_ACTS` never matters. Server PR first, then the app;
merge order written in both PRs.

### 13.4 Relation to PLAN R3

R3's Worker path (D1 rooms, 1.5 s polling, `bt_sit` for Claude) stays the way Claude joins a battle and the way the new
app could share rooms with the old page. Friends-only games of the new app use LAN (round 1) and the relay (round 2), so
the server is needed only for the relay socket and, later, items. A relay room has no Claude seat unless a later bridge
is built. Integration adds one line to `PLAN.md` R3 saying so.

## 14. R7 (design only): server-signed items that work on the LAN without the server

- The server rolls pulls and owns the inventory (new D1 table keyed by the account `sub`); clients only request a pull
  and read their items (owner decisions of 12 Nov, `PLAN.md` R7).
- Each owned item reaches the device as a **certificate** `{v: 1, kid, sub, item, set_v, stats: {…ints}, serial, iat, exp}`
  in canonical JSON, signed by the Worker with a private key held only as a Worker secret (`wrangler secret put`, never in
  a repo, chat, PR or log: rule 2). The app ships the matching **public** key(s) by `kid` (a new data file: it changes
  `DATA_HASH`, which item sets do anyway). **RSA-2048 PKCS#1 v1.5 + SHA-256**: WebCrypto signs it in Workers, Godot
  checks it with `Crypto.verify(HashingContext.HASH_SHA256, sha256, signature, public_key)`. The R7 PR proves it with a
  key pair generated inside the test (`Crypto.generate_rsa(2048)`) and a fixture certificate signed in the test — never a
  real key.
- **Device-key binding is mandatory** (a LAN `HELLO` carries no authenticated identity, so "`sub` matches the sender's
  account" cannot be checked offline on its own; anyone could claim a friend's `sub` and replay copied certificates).
  Each device makes a key pair once (`Crypto.generate_rsa`, private key only in `user://`, never sent); signing in, the
  server signs `{sub, device_pub, kid, exp}` (a device certificate) and every item certificate names that `sub`.
- At game setup each player sends its device certificate and item certificates (`PICK` grows a `certs` field;
  `NetProto.VERSION` bump). The host sends a fresh random nonce per member (in `WELCOME` or a new message); the member
  signs `nonce | slot | gen` with its device private key (`Crypto.sign`) and every peer verifies, **offline**: the device
  certificate's signature (server key by `kid`), the nonce signature (the device's public key), each item certificate's
  signature, `kid`, `exp`, `sub` equal to the device certificate's `sub`, and `set_v` equal to this build's item set. Only
  then do the item effects become ints in the seat dictionary before `Battle.make`, so they are in the digest. No server
  call during a LAN game; a device that never goes online keeps playing with the items it last synced until `exp`.
- Each new item set is a rules change: `RULES_V` bump (the gate refuses mixed versions), capped bonuses, seeded bot
  tournaments before shipping. Copying a friend's certificates gives nothing without the friend's device private key.
- Never write how hidden or secret units unlock in item data, notes or PRs (rule 3).

## 15. What the owner will see (ใหม่ 0.5) and release

1. On the deck the airlock's sign reads "ประตูเทียบยาน · เล่นกับเพื่อน"; the main-menu Online button has no "เร็วๆ นี้".
2. The online screen: name, "เปิดห้อง", the list of rooms on the same Wi-Fi, IP entry, the room card with members.
3. Friends' eggs walk on the deck with names and coloured rings.
4. The host sets up a battle with friends and bots; everyone fights on their own device; a dropped friend is played by a
   bot until they come back; "รุ่นไม่ตรงกัน" when versions differ.
5. The Thai note says: host on home Wi-Fi or his own phone's hotspot (café/hotel/guest Wi-Fi may block devices from each
   other, and anyone on a public Wi-Fi could join); switching apps for more than ~8 s while hosting drops everyone into
   "กำลังต่อใหม่".

Release (integration):

- `APP_VER` "ใหม่ 0.4" → **"ใหม่ 0.5"** (DECK edits the line; `test_menu_text` expects "0.5"). `RULES_V`, `DATA_HASH`,
  `PROTO` untouched.
- Godot-only change, no `battle-table.html` / `board.html` edit: **no candlelight-server PR** this round; merge order: this
  branch into `claude/new-session-fsucoo` (PR #27) by the lead.
- Thai note `web/สิ่งที่เปลี่ยน-<วัน><เดือน>69-รุ่นใหม่0.5-เล่นกับเพื่อน.md` (date of the finished round, the 0.4 note's
  structure): the request in plain words; `## มินิทำอะไรได้แล้วในรุ่นนี้` (open a room, join, deck, battle with friends and
  bots, dropped friend → bot, version check); `## วิธีลอง` (two devices on one Wi-Fi, same version; Windows: allow the
  firewall on private networks; if the room does not appear, type the IP from the host's card; try ต่ำสุด on a phone);
  `## ยังไม่มีในรุ่นนี้` (§16) and questions: does the room list appear on his phone (multicast check), max 6 players OK,
  should a friend who joins mid-battle be able to take a bot's seat; `## ทดสอบแล้ว` (unit / flow / render numbers, the
  deck budgets with friends); `## ลำดับการรวม` (godot only, no server PR).

## 16. Out of scope now

Internet play (round 2, §13); items and accounts (R7, §14); chat and emotes; arena co-op; pack figures for friends;
host migration; joining a running battle as a player; a turn clock or kicking players; Claude seats in LAN rooms;
playing against the old battle-table page; voice; IPv6-only networks without IPv4.

## 17. As built (filled at integration)

Round 1 as merged into `claude/multiplayer-wip`, including the integration fixes and the review round.

- **Integration (three tracks wired):** the joiner is placed at `HallFriends.spawn_for(slot)` on its first join (the host
  is not moved); the lobby's empty-list Timer is not started while the screen leaves the tree; `start_host` marks seats
  whose owner is away as gone right after `START`; a member who is here gets a gone seat back on any member update (also
  after the 60 s slot expiry). Flow test: `tests/flow/test_friends_flow.gd` + `tests/net/friends_peer.gd` (two Godot
  processes, real UI: host, discovery join, deck walking both ways, seat claim, three games incl. a kill mid-game and an
  app-reopen rejoin, a refused older app, close).
- **Review fixes, determinism and seats:** fast reconnect = drop + return (never a silent peer swap) and `where` kept
  (§4.8); `LEAVE {gen}` replaces guessing "left" from `where` (a `WHERE` crossing a `START` no longer marks the new
  game's seat); seated slots kept for their owners during a battle; the host rolls for a silent/gone friend one entry at
  a time (it no longer rolls the next live friend's dice); bots wait while a friend's roll is pending; the 15 s wake
  Timer is set by the host's own wait and not re-armed every frame once overdue; a rejoined client seeds its dice on the
  device; a client whose seat the host plays sends nothing and says so; a request that could not be sent is not left in
  flight; `ACT_NO` clears only its own request; `HB` carries `gen`; a desync long after a repair counts as a first one
  again; "เล่นอีกครั้ง" turns seats of members who left into bots (or says why it cannot start).
- **Review fixes, security:** direction and size checked on the kind byte before decoding (both sides); per-game budgets
  for `RESYNC_REQ` / `INTS_REQ` / `RESEND` / `DESYNC`, a far `RESEND` answered with one `RESYNC`, capped log lines;
  ENet and discovery bind IPv4 only; at most 16 discovery rows; names cleaned again on the client and `{` `}` stripped.
- **Review fixes, phones and UX:** `FriendTags` skips glyphs the font lacks (emoji names keep the min phone worst view at
  30 / 30, asserted in `test_hall`); the screen's keep-on setting is restored on leaving; LAN detection skips mobile-data
  and VPN interfaces and lists Wi-Fi first; a friend without Wi-Fi sees `no_lan`; a lost connection ends the battle with
  its own reason; the deck status line and the battle banner say "กำลังต่อใหม่…" while reconnecting; drop/return toasts
  on the deck; the IP field moved under the name row with a URL keyboard; the host's IP is large with "คัดลอก IP";
  discovery closes while the app is in the background; the main menu warns a host before quitting.
- **Departures from this spec's first text:** `create_server(…, max_players + 1)`; two rate limits (60/s and 600/s);
  `HELLO.nm` ≤ 64 on the wire; `NetProto` has 25 kinds (`LEAVE`) with `NetProto.VERSION` still 1 (no build with the
  earlier table was ever released).
- **Still open:** discovery on a real phone (multicast lock) is unverified; an ENet reconnect inside one process during a
  battle is covered by unit tests (`test_net_loopback`, `test_lockstep`), not end to end; RESYNC does not carry the list
  of gone seats (a rejoined client may name the wrong players in "รอ …"); a rejoin builds the field twice.
