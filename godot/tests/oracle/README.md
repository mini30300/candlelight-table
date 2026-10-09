# Oracle recordings — reference games from the old page

The battle table's old page (`app/src/main/assets/battle-table.html`, APP_VER 9.4, rules version 9) is the reference
for the Godot rules core (ARCHITECTURE §10.3). `godot/tools/record_oracle.js` plays the scenarios of `scenarios.json`
on that page with Playwright and writes one recording per scenario here: the whole setup, every act the page sent and
the board after every act. `test_oracle.gd` builds the same match in the port, replays the acts and compares
(R1_PORT_SPEC §5–§6); until class `Battle` exists it checks the recordings, fixtures and act conversion and prints
`SKIP` for the replay.

## Files

| File | What |
| --- | --- |
| `scenarios.json` | the 24 scenario definitions (below) and `"gzip": true` |
| `<name>.json.gz` | one recording per scenario, gzip of the JSON text (`zlib.gunzipSync` in Node, `gzip.open` in Python; the text is one top-level key per line, one act / board / log line per line) |
| `check_oracle.mjs` | `node godot/tests/oracle/check_oracle.mjs`: every recording parses, has the keys below, `boards.length == acts.length`, ended by itself, seats and armies match the scenario, `units0` matches `board0`; all 15 armies, 2–8 teams, both goals, a hidden unit, manual and auto dice, a time-out, a kept failed charge, a Claude-form `smove`, staged human shots, a human heal and a human grenade are covered |
| `test_oracle.gd` | the Godot side (run by `tests/run_tests.gd`): loader, fixture (§6), compare rules, allowlist; replays the 3 shortest recordings by default, `ORACLE=all` every one (`bash godot/tests/run.sh full` does), `ORACLE=<word>` the matching ones |
| `allowlist.json` | accepted differences `[{scenario, act: int\|"*", path, reason}]`, each reason naming an R1_PORT_SPEC §7 item; empty until the replay runs |
| `page_hash.gd`, `test_page_hash.gd`, `page_hash.json` | an exact integer replica of the page's `hash2`/`hash3` (V8's double rounding included) for the building depths of injected props, its tests, and the page values they compare with (`record_oracle.js --hash-samples`) |
| `../../tools/record_oracle.js` | the recorder (`--only`, `--check`, `--histogram`, see its header) |

The recordings are committed compressed because the plain JSON of the set is far over 4 MB (boards after every act);
gzip shrinks a recording about 60× since consecutive boards repeat. Nothing else is needed to read them.

## How a recording is made

Two pages of the same file run in one headless Chromium, as in `tests/battle/net_sync.js`:

- **Page A** plays. Every seat is a bot (`botStep`), except the one scripted human seat some scenarios have (`human`).
  All acts A sends are captured with `BT.capture(true)` after every step.
- **Page B** is a joiner (`NET.on`, not the owner): it never rolls or runs bots, it only applies A's acts one by one
  with `BT.applyAct` and gives `BT.board()` after each. After every batch A's board must equal B's board
  (`turn, round, phase, over, vp, cp, obj, squads, units`); the first difference fails the recording. So every
  recording is also a passed two-device determinism check of the page itself.
- **Dice.** The page draws every die through `d6()`, which takes the next value of the test queue `BT.dice([...])`
  before falling back to `Math.random`. The recorder refills that queue before every step from its own xorshift32
  stream seeded by the scenario's `seed`, and fails if a step ever drained it. Bots, deployment (`autoDep`),
  objectives, terrain and props are seeded by the page itself (`SEED`). The scripted human's choices come from a
  second seeded stream. No wall-clock value is used anywhere, and `BT.clock(false)` + `BT.tick(dt, n)` step the
  simulation by hand, so a re-run of a scenario produces the identical file: `record_oracle.js --check` re-records
  into a temp folder and compares byte for byte (inflated and, as it happens, the gzip bytes too).
- **Bot-only scenarios** step with `BT.botStep()` (one bot action, pending dice flushed) + `BT.tick(1/30, 4)`.
  **Human scenarios** step with `BT.tick(1/30, 15)` so the bots act through the page's own `botTick`, and before every
  step the recorder rolls what waits on the tray in the page's order (`BT.myRoll()` / `BT.roll(opts)`): the human's
  rolls with the policy's stratagem choices, the bots' with the page's `botChoice`. With `"auto": false` the human's
  dice are therefore the manual path (the tray waits for `roll`), with `"auto": true` the page's auto-dice path.
- **The scripted human seat** (`policy: "scripted"`) gives one order per step through the hook and the real buttons:
  move / advance (`adv`) / stay / fall back, whole-attack shots (`shoot` via `BT.shootAt`) or staged attacks
  (`BT.aim` → roll: `atk` → optional re-roll `rr` → `wnd`), grenades, healing (staged the same way), charges (`chg`,
  overwatch answer `ow`, `chr`, `cmove`), skips, and "end phase" (`done`, the room act). It spends command points on
  re-rolls, go-to-ground (`sav` with `gtg`), iron nerve (`shock` with `brave`), overwatch and charge re-rolls when it
  can; a failed charge it does not re-roll is kept (`chr {keep: 1}`). Healers keep near a friend that is not a healer
  and never charge. With `odds.claude` a move goes out the way Claude's moves come through the Worker: `smove {u, x, z,
  how}` with the centre point at 0.1" and no `to`, applied on page A as a room act and planned by `planMove` on every
  device. `policy: "idle"` gives no orders at all (its
  dice are still rolled with the same tray choices), so the phase clock (`clock` seconds) runs out and the page sends
  `endph` itself: the time-out path.
- A scenario fails (nothing is written) on a page error, a board mismatch, an exhausted dice queue, a stall
  (`stallSteps`, default 1500 steps without an act) or the step cap (`maxSteps`, default 15000).

## Scenario fields (`scenarios.json`)

| Field | Meaning (page value it sets) |
| --- | --- |
| `name` | file name of the recording |
| `seed` | `BT.seed(n)`: terrain, props, objectives, bot lists; also seeds the recorder's dice and policy streams |
| `size` | table width `BT.size(w)` (even, 24–180; depth `d = round(w·0.72/2)·2`). 2 seats need ≥ 26, 3–4 seats ≥ 36, 5–6 ≥ 46, 7–8 ≥ 64 (the page's own `depCapacity`; its UI grows the table the same way) |
| `theme`, `terrain`, `buildings`, `density` | `setTheme` (ruin, forest, desert, ice), `setTerrain` (flat, hills, mountain, forest), `setBuildings(on, density)` (density is quantised by the page: 0.05 steps below 1, 0.25 above) |
| `mode`, `teams`, `perTeam` | `G.mode` (pvp, ffa, team, pve), `G.teams`, `G.perTeam`; seats are `teams × perTeam` in team order |
| `budget`, `freeFire`, `clock` | `G.budget` (points per team, informational — lists are explicit), `G.freeFire`, `G.clock` (0 / 25 / 50 s per phase) |
| `goal`, `rounds` | `G.goal` (`obj` or `kill`), `G.rounds` (3–10; `kill` games cap at 30 rounds) |
| `auto` | `BT.setAuto` (default true); only matters with a human seat |
| `human` | `{ seat, policy, odds }`: the one seat played by the recorder (`scripted` or `idle`); all other seats are bots. `odds` overrides the scripted seat's chances (defaults `rr 0.6, gtg 0.7, brave 0.7, ow 0.85, chrr 0.8` for the stratagems, `hold 0.5` stay when in gun range, `adv 0.35` advance, `gren 0.15` grenade first, `shoot 0.3` whole attack instead of staged, `claude 0` Claude-form move) |
| `seats[i].list` | `[[unit key, squads], …]`; keys as in `godot/data/types.json`. `"hidden:sec"` / `"hidden:lk"` select the first datasheet carrying that flag (the two hidden units); how those are unlocked in the app is intentionally not written anywhere |
| `seats[i].dep` | `[x, z]` deployment point (checked with `depWhyNot`) or `"auto"` = the page's `autoDep` in seat order |
| `seats[i].skin` | `{ unitKey: variantIndex }` = the player's skin choice (`loki: 1` is the one skin the page has) |
| `maxSteps`, `stallSteps`, `stepTicks`, `diceBatch` | recorder limits (defaults 15000, 1500, 4 / 15, 1200) |

## Recording format, field by field

Top-level keys in this order:

- `format` — 2 (2 added `units0`).
- `page` — `{ app_ver, rules_v }` read from the page source (`var APP_VER`, `var RULES_V`). Recordings are re-made only when this changes.
- `scenario` — the scenario name; `scenario_def` — the scenario object as above.
- `setup` — `BT.curSetup()` plus `d`: `theme, seed, w, d, terrain, buildings, density, mode, teams, perTeam, budget, freeFire, clock, goal, rounds, v` (the room setup a server would store; `mode` is `team` for custom/spectator).
- `seats` — per seat `{ team, bot, fac, pts }`: team index, bot flag, army code (`facOf` the list), points of the list without hidden units (`ptsOf`).
- `lists` — per seat `[[unit key, squads], …]` in TYPES order (the hidden units appear by key).
- `deps` — per seat `[x, z]` as used by `deploy()` (floats when `autoDep` chose them).
- `skins` — `{ unitId: kitVariant }` for every model that carries a skin (`u.skn`), e.g. `"0:3.0": "loki_f"`; empty object otherwise.
- `props` — `BT.props()`: the terrain pieces `[{ kind, x, z, rot, s, rad, h }, …]` (all floats as generated). The port injects these as a fixture instead of generating its own.
- `obj` — the objectives at the start `[{ n, x, z }]` (raw floats; empty for `kill`).
- `units0` — every model right after `start()`, in `units` order: `{ id, x, z, rot }` with the raw (unrounded) rules
  position and the facing the page gave it (radians). The port's oracle fixture puts its models exactly there (R1 Q1).
- `board0` — `BT.board()` right after `start()`, before any act: the deployment.
- `acts` — every act page A sent, in order, exactly as `netSend` got it (no `pid`/`seq`; the server would add those). Codes and fields (CODEMAP §2.9, the Worker's allowlist):
  `smove {u, to:[[x,z]…], how: move|adv|fb}` · `stay {u}` · `skip {u, ph}` · `adv {u, roll}` · `atk {u, t, how: shoot|fight|ow, hit:[…]}` · `wnd {u, t, wound:[…]}` · `sav {u, t, save:[…], gtg:0|1}` · `rr {u, t, v}` · `shoot {u, t, how, hit, wound, save}` (whole attack: human/Claude path) · `shock {u, roll:[2], brave:0|1}` · `rez {u, roll:[…]}` · `chg {u, t}` · `ow {u, t, use:0|1}` · `chr {u, t, roll:[2], rr?:1, keep?:1}` · `cmove {u, t, to:[[x,z]…]}` · `gren {u, t, roll:[6]}` · `heal {u, t, roll}` · `done {ph}` · `endph {ph}`.
  Dice are 1–6 as drawn; points are the page's `toFixed(2)` numbers.
- `acts_meta` — one entry per act `{ seat, turn, round, phase, step }` read on page B just before the act was applied: `seat` is the seat that rolled or decided (the owner of `u`; for `sav` and `ow` the owner of `t`, the defender; the human seat for `done`; `null` for `endph`), `turn` the team in turn, `step` the recorder step that produced it.
- `boards` — `boards[i]` is `BT.board()` on page B after applying `acts[i]` (and the page's own `advance()`), so `boards.length == acts.length`. A board: `{ v, turn, round, phase, over, vp:[per team], goal, rounds, cp:[per seat], obj:[{ n, x, z, owner }], squads:[{ id, pl, team, k, n, n0, x, z, moved, adv, fell, shot, chDone, charged, shaken, engaged }], units:[{ id, sq, pl, team, k, hp, x, z }] }`. `x`/`z` are the rules positions (`gx`/`gz`) rounded by the page to one decimal; `squads` lists living squads, `units` living models (dead ones are gone), `n` is living models, `n0` the starting count.
- `log` — the page's log lines `{ t, base, c, n }` (HTML text, the text without the "×n" suffix, css class, repeat count), merged after every step because the page keeps only its last 80 lines. Thai, for reading a divergence.
- `final` — `{ over, round, turn, phase, vp, cp, alive:[teams with models], units, result (last log line, text only), steps, acts, capped:false, hist:{act code: count} }`, identical on both pages.

**Floats.** Values are written as the page holds them: `props` (`x, z, rot, s, h`), `deps`, `obj` and `units0` are raw doubles;
act points (`to`) have two decimals, Claude-form `x`/`z` one; board positions one decimal (so a position check needs a
tolerance: `test_oracle.gd` allows 60 MI, R1_PORT_SPEC §6 / D7). Everything else is integer or boolean.

## Scenario coverage (24)

All 15 armies (each in two or more scenarios), 2 to 8 teams (free-for-all up to 8, team games 2v2, 3v3, 4v4), `obj`
(3–5 rounds) and `kill` goals, tables from 26 to 180, every theme and terrain, buildings off and densities 0.25–2.5,
the Trojan horse (`troy`, opens from round 2), the wind unit (`hanu`), void-shield titans (`ktwarhound`, `tataunar`),
self-repair (`rwar`, `mummy`), healers, flyers, knight chapters, the fallen knights' pact, a player skin (`loki_f`),
both hidden units (`two_dark_elves_vs_blue_empire_obj_hidden_units_…`), free fire, the clock set with bots, and
three human-seat games: manual dice (`…human_manual_dice…`), auto dice in a 2v2 with a bot team-mate
(`…human_auto_dice…`) and an idle human whose phases time out (`…idle_timeout_clock_25…`). Four more human games
(R1 Q2) cover what bots never send: a human who keeps failed charges (`…charge_keep…`, `chr {keep: 1}`), Claude-form
moves (`…claude_form_moves…`, `smove {x, z}`), staged human shots only (`…staged_shots…`) and a human healing and
throwing grenades (`…heal_grenade…`).

The act histogram (`record_oracle.js --histogram`) must show every one of the 19 act codes the page sends at least
once; the Worker's allowlist additionally knows the rules-version-1 codes `move` and `endturn`, which this page never
sends, so they cannot occur. Bots never send `adv`, `shoot`, `done` or `rr`: those come from the human-seat games.

## Re-recording

```bash
cd tests && npm ci && npx playwright install chromium          # once (CHROMIUM_PATH works too, as in tests/run.sh)
node godot/tools/record_oracle.js                              # all 24, ~15 min on a small machine, writes *.json.gz here
node godot/tools/record_oracle.js --only <name>[,<name>]       # some
node godot/tools/record_oracle.js --check [--only …]           # re-record (3 by default) into a temp folder and diff byte for byte
node godot/tools/record_oracle.js --histogram                  # count act codes over the recordings here; exit 1 if one is missing
node godot/tools/record_oracle.js --hash-samples               # page hash2/hash3 samples into page_hash.json (after re-recording: it lists the recorded buildings)
node godot/tests/oracle/check_oracle.mjs                       # structure and coverage check of what is committed
```

Re-record only when the page changes its rules or data (`APP_VER` / `RULES_V` stamp in `page`), and say why in the
PR; a changed recording is a changed reference. A page that is not deterministic any more shows up as `--check`
"DIFFERS" with the first differing line.
