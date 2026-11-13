# Where the game work stands (13 Nov 2569)

The owner paused the game on 9 Oct to work on another project and resumed it on 12 Nov with the front page and the
walkable lobby (below). Everything here is what a later session needs to pick up.

## 13 Nov: ใหม่ 0.6 (sounds, battle animations, arena dodge, online only in the personal build)
- Sounds: the old page's 42 `DEF` sounds and 5 music loops baked by `tools/bake_sfx.js` into `assets/sfx/` (git-ignored,
  CI-built with the kits); autoloads `Sfx` and `Music`; settings sliders. Battle: `scenes/battle/battle_fx.gd` plays the
  old page's attack/death clips, tracers, flames, blasts and fallen figures from the event stream (visual only; digests
  unchanged, tested). Arena: dash-dodge on Space / the touch button; the private power-armour figure has its own dodge
  clips and no strafe walk (strafe stays for other figures).
- Online is hidden in the public app (`app/features.gd`, PACK_SPEC §5.1); the private build turns it on with
  `res://packs/features.json`. Next (owner, 13 Nov): a separate launch-bay room in the personal app (ship to campaigns,
  holo table to pick a mode, a random-parts robot) where online moves.
- Open: no walk/run clips while figures move on the battle table (needs position interpolation in table_view /
  figure_pool); grenade/heal/rez/save-spark effects; BattleFx reads private FigurePool members (add accessors).

## On this branch (claude/new-session-fsucoo, draft PR #27), CI green
- R0 complete. R1 so far: `godot/docs/R1_PORT_SPEC.md` (the contract, waves 0–6, lead decisions at the end of §9),
  `core/battle/state.gd`, `core/field/*`, rules-core waves 1–2 (offsets, blocking, squads, strats, data exports, army,
  objectives, combat, abilities registry, moves), field look (V1), sample gothic ruin (V5, waiting for the owner's
  verdict before the full set), army picker (V4), 79 baked animation clips (V2). 2,097 unit checks, render suites,
  exported-game self-test (`windows-smoke`, also reproducible locally with a `--export-pack` + linux template).

## Done but not yet on this branch (cancelled by the owner on 12 Nov)
- **Rule-1 fix of the old page (battle table 9.5)** — the owner cancelled this item on 12 Nov; do not redo it unless he
  asks again. The record below is kept for history only: commit `ec4608f` on local branch `rule1-port`
  (worktree `.claude/worktrees/wf_563738c7-976-26`; same change as `cda0135`). Redesigns the confirmed marks:
  the secret giant mech's V antenna and V skirt mark, knb1's red saltire, the medic's red cross (now a white cross on
  green), the doom glyph; comments only for code-text names. The independent check step never ran (session limit):
  review it, re-run the page suites, then cherry-pick, and open the candlelight-server re-embed PR
  (`python3 embed.py`). Merge order then: candlelight-server first. Verdicts: workflow run `wf_563738c7-976` journal.

## 10 Oct: wave 3 landed
Pend queue + ability handlers, board + act codec, oracle harness (24 recordings, page hash), deploy speed (unit grid),
reviewed (one grid bug in spawn_from fixed). 2,569 unit checks. Open for wave 5: the dispatcher maps act t "" to no
match for targeted codes; Battle.make applies fixture units0 itself; the caller runs BtTurn.check_over after every
pend applier and prune. New log keys (atk_done, dice_short, shock_*, chg_*, heal_roll, rez_roll, wind_*, …) need I18n.

## 10 Oct: wave 4 landed
Turn (start_match, start_turn, phases, fights, end of round), roller (tray scheduler), bot (all phases), net/json_num
(wire numbers). 400 + bot page samples match; 12 bot-vs-bot games finish; 3,299 unit checks. Open for wave 5: Battle.advance
runs BtPend.prune once then BtTurn.advance_step up to ADVANCE_GUARD; start_match needs an undeployed state; bot_step should
give next_act the bot:<seat> stream of the squad that acts (the test helper uses the team's first bot seat); new turn log
keys (match_start, turn_start, fight_*, seat_done, over_*) need I18n.

## 10 Oct: wave 5 landed — a full game runs
acts dispatcher + Battle; the oracle replays all 24 recorded page games to the end (23 clean, 1 with two §7 #7 spawn-facing
entries); 8 goldens (2–4 teams, 2v2, obj/kill) with a grid check after every act; 30 smoke bot games with legality checks;
perf (crowded bot turn 31.6 s → 1.2 s); bot/roller differential and act-edge differential. 3,881 unit checks.
Open: the UI must call Battle.flush before sending `done` (page playerDone rolls pending dice first); new log keys need I18n;
oracle README still says the allowlist is empty.

## Cloudflare account subdomain: renamed on 12 Oct, renamed back on 9 Nov (no client change needed)
On 12 Oct the owner renamed the account subdomain from `mini3030023450` to `rbppc` for the boat booking site, which cut
every game client off. On 9 Nov the owner renamed it back: `https://candlelight-table.mini3030023450.workers.dev/app`
answers 200 again, so the clients' address is right and nothing in this repo needs changing. The booking site now lives at
`boat-booking.mini3030023450.workers.dev`. (Players whose DNS cached the failure may need `ipconfig /flushdns` or ~30 min.)

## 9 Nov: the rule-1 fix above is lost
Its commits (`ec4608f`, `cda0135`) were never pushed and the container was replaced; they no longer exist. On 12 Nov
the owner cancelled the item, so it is not redone.

## 12 Nov: front page, walkable lobby and games against bots (`docs/LOBBY_SPEC.md`), APP_VER ใหม่ 0.2
The owner asked for the front page and the lobby first ("a lobby you can walk around in with WASD"), egg-shaped placeholder
figures before the real models, the old models kept, and play against bots first (online later). Three builders worked
in parallel from LOBBY_SPEC, each on its own files (§6):
- **menu**: the main menu is the first screen (title art drawn from shapes: table, five candles, flicker on a ≤ 6 Hz Timer on
  hi/mid only); Settings (language, graphics level, figure style egg/kit — kit disabled without kits on disk — touch
  controls auto/on/off, and the GPU check, which now lives here); `App.fig`, `App.touch`, `touch_active()`, `replace()`,
  `settings_file` (tests never write the machine's settings.cfg), `back()` asks `handle_back()` first, Esc is the `back`
  action; a physical-key `[input]` map (WASD/arrows, Shift, E, Esc — works with a Thai layout);
  `include_text_server_data`; i18n fragments `ui/i18n/{menu,hall,battle}.json` (I18n, lint and `test_i18n_fragments`);
  `CandleStyle`; `run.sh` and CI run every `tests/render/test_*.gd` and a headless `tests/flow/` stage.
  `main.tscn`'s demo table no longer builds at startup (hidden, processing off until the GPU check or a battle needs
  it), so `test_main_screens` and `test_army_screen` now walk menu → Settings → GPU check (an intended change; no check
  was dropped).
- **lobby**: the hall (`scenes/hall/`, `ui/screens/hall_screen.tscn`, `ui/widgets/touch_stick.gd`) — §2.
- **battle**: egg figures (`table/figures/egg_shapes.gd`, FigurePool/TableView switch), setup, `MatchRunner`, battle
  screen and end panel (`ui/battle/`, `ui/screens/battle_setup.tscn`, `battle_screen.tscn`) — §3–4.
Full run (`run.sh full`, 12 Nov 12:13, all three tracks in): 4,557 unit checks, oracle 155, the flow test 25 (menu → hall →
W to the war table → E → setup → bot game to the end panel → back → Esc), render probe and 9 render suites, data lint — all pass.
Out of scope this round (§8): online rooms, the adventure table, real models, figure animation, a 3D dice tray, sound,
deploy by hand, custom lists for the human seat, saving a game.

**Integration (12 Nov, after the three tracks).** The whole flow was walked end to end and wired: boot → main menu →
เล่นกับบอท → hall → walk to the war table → E (or the big use button on a phone) → setup → START → a bot game with egg
figures and team rings (or with you in one seat; "ให้บอทเล่นแทน" can always finish it) → end panel → กลับล็อบบี้ → hall →
Esc → main menu. Settings changes (language, graphics level, eggs / old models, touch controls) reach every screen when it
shows again. Fixes made while integrating:
- the hall spawn moved from z 6 to z 5: at z 6 the front wall pushed the camera arm down to about 1.5 m and the first view
  of the lobby was a giant see-through egg (`HallLayout.SPAWN`; `test_hall_layout` now expects 3.4 m to the war table's
  trigger and still checks ≥ 3 m; LOBBY_SPEC §2.1 updated);
- the battle log cut long attack lines (many dice) mid-number at the panel edge; they now end in "…"
  (`battle_screen.gd`; checked in `test_battle_screen`);
- the setup screen's "สุ่มใหม่" button text touched its border (min width 120).
- New `tests/flow/test_settings_flow.gd` (30 checks): Settings from the hall → English, lo, touch on, old models → the
  hall's signs, prompt, stick and level, setup, the battle's figure style and level, the end panel, then back to Thai /
  mid / eggs, every change saved to a test settings file.
Final full run after integration (`run.sh full`, 12 Nov 12:36–12:39 Bangkok, exit 0): unit 4,558 checks in 51 scripts,
flow `test_lobby_flow` 25 (W reaches the war table in 1.3 s, 3.6 m) and `test_settings_flow` 30, oracle 155, render probe,
render suites anim_footslide 54, army_screen 62, battle_screen 106, budgets 112, field_look 213, hall 147, lineup 29,
main_screens 40, menu_screens 118; data lint PASS. Owner media (stills and an 8 s walk clip) are in the session
scratchpad `godot-lobby/media/`, not in the repo.

**Review fixes (12 Nov, before the commit).** A three-lens review (correctness, rules, mobile/perf) found these; all
fixed with a test each:
- *Charge gate (must fix)*: the human seat could not charge with `ac` units after advancing, dark elves after advancing
  from round 3, or flyers/titans after falling back, although the core allows it (and the bot did it). The UI now asks
  the core: new `BtCombat.charge_gate(st, s)` (the target-free part of `charge_why_not_with`, which now calls it; same
  results, so RULES_V stays 10), `MatchRunner.can_select` and `select_why` use it, and a refused tap shows the core's
  reason. `test_match_runner` charges with all three after advancing / falling back.
- *Hall camera*: a pillar, stand or shelf between the camera and the avatar snapped the arm up to 6.4 m in one frame
  (walks to the lectern and the army display). Props moved to their own physics layer (`PropBlockers`, value 4; the
  avatar still collides) and the spring arm sees walls and ceiling only; `HallLayout.camera_clear` pulls the camera only
  when its point would be inside a prop (to the nearer side), the arm extends back at most 4 m/s and never through a
  prop, and the camera point is re-checked after the pivot moves in `_process`. `test_hall` walks spawn → lectern,
  spawn → army display and past two pillars (arm change ≤ 0.5 m a frame, measured 0.07 m; camera never in a blocker);
  `test_hall_layout` covers the ray math (400 random rays).
- *Held keys*: leaving a battle while holding W made the next battle's camera pan by itself. `CameraRig` now forgets
  keys, fingers and drags on `NOTIFICATION_DISABLED` (`reset_input`) and gives up the current camera; the main menu also
  drops any 3D camera, so nothing 3D draws behind it. `test_lobby_flow` (33 checks) holds W while leaving, plays a
  second game and checks its camera does not drift; the flow tests now send `keycode` and `physical_keycode`.
- *Setup*: the army dropdown's popup rows were 31.5 px; `CandleStyle.popup` gives the candle theme and 48 px rows
  (scrolls when longer than the screen), checked in `test_battle_screen`. The setup screen now reopens with the last
  game's choices (`App.last_choice`, memory only, new seed).
- *Stuck game*: the toast said "press back to lobby" with no button on screen; a stuck game now shows the end panel with
  a stuck title and กลับล็อบบี้.
- *i18n*: the lint counted every `ui/i18n/*.json` while `I18n` loads only `FRAGMENTS`; the lint now reads `FRAGMENTS`
  from `ui/i18n.gd`, fails on an unlisted or missing fragment, and requires every Thai literal under `ui/` and `app/` to
  be a whole key (`I18n.t` matches whole strings only); new fixtures `fail_i18n_fragment` and `fail_i18n_joined`;
  `test_i18n_fragments` checks the folder holds exactly `FRAGMENTS`; ARCHITECTURE §8 and §13.4 corrected.
- *Small*: with touch controls the battle log uses 18 px text in 6 lines (was 15 px, 8 lines); `test_table_style`
  covers "saved kit style with no kits on disk falls back to eggs"; LOBBY_SPEC is committed with session paths replaced
  by `<scratchpad>`.
- Left for the owner: the stick and use-button positions on the phone (spec §2.5 puts the use button at bottom centre;
  a floating stick or a bottom-right button needs his choice).
Full run after the review fixes (`run.sh full`, 12 Nov 13:56–14:00 Bangkok, exit 0): unit 4,592 checks in 52 scripts,
flow `test_lobby_flow` 33 and `test_settings_flow` 30, oracle 155, render probe, render suites anim_footslide 54,
army_screen 62, battle_screen 120, budgets 112, field_look 213, hall 155, lineup 29, main_screens 40, menu_screens 118;
data lint PASS (15 fixture checks).

## 12 Nov: warship deck lobby (`docs/SHIP_LOBBY_SPEC.md`), APP_VER ใหม่ 0.3
The owner asked for the lobby aboard a gothic starship and plans random rewards (gun parts, decorations) later. The
walkable hall became **ดาดฟ้ายานรบ / Warship Deck**, our own design (no franchise names or marks; the only emblem is our
candle): pointed vault with ribs and cables, clustered steel columns, deck plating, pipes, green / amber wall screens,
three pointed viewport lancets onto a space dome (nebula, stars, planet, moon, our own ships drifting on hi/mid, parked
on lo, absent on min), the title plaque. Stations keep their jobs: holo war table (setup), armoury (army picker),
command console (settings), docking airlock on the right wall (online, coming soon), adventure table (coming soon), blast
door (exit) and the new **vault**, a treasure chest at (5, 4) that only shows "หีบสมบัติ — เร็วๆ นี้: สุ่มรับชิ้นส่วนปืนและ
ของตกแต่ง" (no reward code yet). Controls, camera, spawn, HUD and flows are unchanged. Built in two parts (world;
screen + release); where the build differs from the spec, its §12 records why (lancet springs, airlock depth, ship
places, holo grid, a cool fill light, moved test starts).
- New: `scenes/hall/hall_space.gd`, `holo.gdshader`, `ship_drift.gdshader` (hi/mid only), `tests/unit/test_hall_space.gd`,
  `tests/flow/test_hall_reach.gd` (walks from the spawn to all 7 stations with the real colliders, then the chest's panel).
- Measured before the review (`test_hall` overview only: avatar (0, 0, 3.5), yaw 0, pitch −0.6, arm 9, touch off,
  1280×720): 20 draw calls on every level; primitives hi 16,279, mid 15,094, lo 13,734, min 13,012; no ShaderMaterial on
  lo/min; no hole into the void (magenta background: 64 views on mid, 32 on min, zero pixels). The phone layout was not
  measured then (the review found 41 draw calls on min there), and the two "vault / airlock" camera walks kept the camera
  at the front wall, so they tested neither; both are fixed below.
- Runs (12 Nov 17:30–18:00 Bangkok): unit 4,769 checks in 53 scripts; flow `test_lobby_flow` 33, `test_settings_flow`
  30, `test_hall_reach` 31; render `test_hall` 243; data lint PASS.
- Integration (12 Nov, 17:40–18:05 Bangkok): the whole flow walked by script under xvfb (menu → เล่นกับบอท → the deck →
  on foot to all 7 stations and used each: armoury and console open and return, airlock / adventure / chest panels, the
  blast door to the menu → back → W to the war table → setup → a bot game to the end → กลับล็อบบี้ (same spot, table
  hidden) → Esc → menu), 44 checks, no failure. `HallBuilder.bake` now reads the cool lights from packed arrays: the
  meshes are byte-identical and the deck builds in about half the time. `run.sh full` PASS: unit 4,769 in 53 scripts,
  flow 31 / 33 / 30, oracle 155, render probe, anim_footslide 54, army_screen 62, battle_screen 120, budgets 112,
  field_look 213, hall 243, lineup 29, main_screens 40, menu_screens 118; data lint PASS.
- Review fixes (12 Nov, three reviews: look and rules, phones and performance, correctness and tests; no must-fix):
  window sill 0.18 → 0.06 m (`HallLayout.SILL_DEPTH`, unit check ≤ 0.08: it cut through an egg standing at the
  viewport); the chest no longer clips to (255, 193, 82) (vault light k 0.6 → 0.25, darker bronze: about (170, 115, 50));
  viewport mullions in dark steel (they read as wooden window frames); darker holo-table glass; the moon with the planet's
  segments and a blue-grey night side; sign outlines only on hi/mid (`HallWorld.LEVELS[l].outline`) and the touch
  stick's arcs without anti-aliasing; the title plaque on the signs' font size 88 with a smaller pixel size (no extra
  4 MB of glyph pages); the drifting ships' culling box covers the dome (a ship in view could be culled with its node);
  `%SoonPanel` ignores the mouse (it swallowed camera drags on touch); `HallBuilder.bake` caches the light per vertex
  position (the deck builds in 60–70 ms of CPU per level instead of 120–170, bit-identical: a new unit check compares
  every vertex with `lit_cool(glow, cool_at)`); camera walks get their own yaw, the airlock walk runs along its front with
  the camera between the avatar and the right wall (passes 0.25 m from it, arm change 0.00 m a frame), and a unit check
  guards airlock front − `CAM_PAD` > `HALF.x` − `HallCamera.WALL_PAD`. New `test_hall` checks: the phone layout's worst
  view (20:9, touch on, first-entry hint showing, at the war table looking to a back corner) within the deck targets on
  every level, outlines per level, the plaque's font size, the ships' culling box, a drag on the open panel orbits.
  Measured: overview hi 21 / mid 21 / lo 16 / min 16 draw calls (primitives 16,647 / 15,382 / 13,678 / 12,956); phone
  worst view hi 38 / mid 38 / lo 30 / min 29 (targets 40 / 40 / 35 / 30). Owner stills and the walk clip re-rendered.
  Not done: letting the camera tilt up to the vault (the spec fixes the camera; the Thai note asks the owner) and
  building the deck's meshes ahead of the tap from the main menu (optional).
- Full run after the review fixes (12 Nov): `run.sh full` PASS: unit 4,775 in 53 scripts, flow `test_hall_reach` 31,
  `test_lobby_flow` 33, `test_settings_flow` 30, oracle 155, render probe, anim_footslide 54, army_screen 62,
  battle_screen 120, budgets 112, field_look 213, hall 264, lineup 29, main_screens 40, menu_screens 118; data lint PASS.

## 13 Nov: weapons arena (ใหม่ 0.4, `docs/ARENA_SPEC.md`)
The owner asked (12 Nov, before going to sleep) for another room off the lobby, reached by a corridor: a weapons test
range, not a campaign, where his character draws a gun and the game becomes a third-person shooter, with an attack
system (punch, rifle, a saw sword), one alien enemy, and a switch (shoot it or press) for that enemy's bot. Built by
three builders in parallel from ARENA_SPEC (room, player, enemy), then integrated and reviewed:
- **Deck**: a new station `arena`, a pointed doorway in the front wall left of the exit with a corridor stub; walking
  into it (or E) fades and pushes the arena screen; coming back places the avatar at `ARENA_RETURN`. The deck's views and
  budgets are unchanged; reaching the door starts loading the arena's heavy files on a thread (`preload_arena`).
- **Arena** (`scenes/arena/`, `ui/screens/arena_screen.*`, `ui/widgets/arena_hud.gd`, `arena_touch.gd`, `ui/arena/`):
  a 10 m corridor (walk mode) into a 20 × 24 m range; past the shoot line the egg draws our rifle and the shoulder camera
  takes over (crosshair, mouse look while captured, or touch: stick, aim pad, four round buttons); rifle (30 rounds,
  8/s, reloads by itself when it runs dry with fire held), punch, saw sword; the hive beast (สัตว์รัง: the `warrior` kit
  playing the baked clips) as a dummy until the bot switch (shoot it, melee the post, or E; once per burst) turns it on:
  it chases round the pillars (A*), shows the claw's real reach as a red sector filling to its rim during the 0.6 s
  wind-up, claws for 18 at 0.72 s, flinches (with 1.2 s of poise so melee spam cannot lock it) and dies on 300 damage;
  reset, board, downed and respawn, pause on Esc / focus loss / the app going to the background. Player and enemy are
  swappable figures behind a contract, loaded from a private pack (`packs/`, git-ignored) when present.
- Where the build differs from the spec (camera framing, spawn, poise, plate bursts, telegraph sector, HUD batching, …):
  ARENA_SPEC §17. APP_VER ใหม่ 0.4; RULES_V, DATA_HASH, PROTO untouched (local single-player, seeded RNG for tests).
- Review (13 Nov, three lenses: game feel and rules, phones and performance, correctness and tests): one must-fix (the
  Thai note and the docs) and 13 should-fixes, all fixed with tests, plus most suggestions (§17 lists them). Left as
  questions for the owner: the beast's toughness and speed, whether reset should turn the bot off, the phone button
  positions, the beast's model.
- Full run after the review fixes (`run.sh full`, 13 Nov Bangkok, exit 0): unit 5,584 checks in 62 scripts; flow `test_arena_flow` 49, `test_hall_reach` 35, `test_lobby_flow` 33, `test_settings_flow` 30; oracle 155; render probe; render suites anim_footslide 54, arena 122, arena_hud 122, army_screen 62, battle_screen 120, budgets 112, field_look 213, hall 305, hive_beast 92, lineup 29, main_screens 40, menu_screens 118; data lint PASS.
- Measured (draw calls hi / mid / lo / min): arena overview 25 / 25 / 21 / 21, corridor 29 / 29 / 22 / 22, phone worst view (with four damage
  numbers and the hurt edge) 38 / 38 / 35 / 34; the longest frame entering the arena 206 ms (was 364–447 before the preload).
  Owner media (stills, a 13 s play clip) are in the session scratchpad `godot-arena/fix/media/`, not in the repo.

## 13 Nov: play with friends, round 1 (ใหม่ 0.5, `docs/NET_SPEC.md`)
The owner asked for play with friends "like Minecraft": one player hosts, friends join directly, the server only for
items later. Round 1 is LAN only and uses no server: the docking airlock opens the play-with-friends screen (host, room
list by UDP discovery, join by IP, room card, seat claims); friends walk on the deck as eggs with name tags and rings
(pose sync with interpolation, visual only); the battle with friends and bots runs in lockstep over the integer core
(only acts travel, the host sequences, digest checks every 8 seqs, a desync is loud and repaired by a resync); a dropped
friend's seat is played by the host with that seat's pid until they come back. Built by three builders (NET-CORE, DECK,
BATTLE), integrated with a two-process flow test, reviewed through three lenses (determinism, security and repo rules,
phones and UX) and fixed: NET_SPEC §17 lists the integration fixes, every review fix and what stays open (discovery on a
real phone; an in-process ENet reconnect during a battle is unit-tested only). Round 2 (internet through a relay room on
the existing Worker) and R7 (server-signed items that work on the LAN) are designed in NET_SPEC §13–§14. APP_VER
ใหม่ 0.5 (the lead sets the final number at merge); RULES_V, DATA_HASH and the core untouched; no server PR.
- Full run after the review fixes: `run.sh full` exit 0 (13 Nov Bangkok): unit 6,499 checks in 74 scripts; flow `test_friends_flow` 88 (two processes; 91 with media), `test_lan_flow` 24, `test_arena_flow` 49, `test_hall_reach` 38, `test_lobby_flow` 33, `test_settings_flow` 30; oracle 155; render probe; render suites anim_footslide 54, arena 122, arena_hud 122, army_screen 62, battle_screen 234, budgets 112, field_look 213, hall 399, hive_beast 92, lineup 29, lobby 328, main_screens 40, menu_screens 125; data lint PASS. Deck online with 5 friends (draw calls hi / mid / lo / min): overview 21 / 21 / 17 / 17, phone worst view 38 / 38 / 31 / 30 (two of the names with emoji). Owner media are in the session scratchpad `friends-r1/fix/media/`, not in the repo.

## Next steps, in order
1. Owner feedback on ใหม่ 0.4 (the arena: the beast's toughness and speed, reset and the bot, phone buttons, the beast's
   model), ใหม่ 0.3 (the warship deck on his phone; where the chest stands; what the random rewards should
   hold) and on ใหม่ 0.2 (one bot game, eggs vs old models), then online rooms (R3: the room
   screen is `ui/screens/lobby.tscn`, distinct from the walkable hall) and the human turn UI polish (a custom army list
   for the human seat, deploy by hand, healing and grenades by tap, flyers lifted by `fly.json`).
2. Wave 6: reviewed allowlist, v10 gate memo (`docs/GODOT.md` now maps the lobby files; keep it current).
3. R1-V3: play the baked clips on the figures (AnimationTree), ruin full set after the owner approves the sample.
4. Owner gates: R0-H (APK GPU-check screenshot, now under Settings), ruin sample verdict, R7 collection design week.

(The rule-1 redesign of the old page, formerly step 1, was cancelled by the owner on 12 Nov.)

## Budget rule agreed with the owner (8 Oct)
Run one workflow at a time (parallel runs hit the 5-hour limit and lose half-finished agents); Opus for builders.
Near the weekly reset the owner may say "use it all".
