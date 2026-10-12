# Candlelight Table on Godot 4 — delivery plan R0..R6

Companion to `ARCHITECTURE.md`. Every task below is self-contained: an orchestrator can hand it to one agent with the
file paths as written. Tracks are the ownership areas of ARCHITECTURE §1; one PR touches one track plus its tests.

## Cadence and team shape

- 3–5 agents in parallel, one task per branch and draft PR, quick CI suite on every PR, `main` merges attach a build to
  the `build-N` release automatically. **Every week from week 1 something new is installable on the owner's phone**
  (the "look track" runs beside the headless rules port from week 2).
- Calendar estimates assume 4 agents and prompt owner gates (screenshots, one game played). "Alone" means one agent.
- Owner gates are concrete and short: a screenshot, a typed Thai name, one game played, a yes/no on how it looks.
- Order of merges when the server is involved: candlelight-server PR first, then candlelight-table; both descriptions
  say so (AGENTS.md).

| Milestone | Calendar (4 agents) | Agent sessions | Owner sees |
| --- | --- | --- | --- |
| R0 scaffold, CI, look build | weeks 1–2 | 6–8 | a real field with ~400 figures and team rings on their phone and PC |
| R1 rules core v10 (+ look track) | weeks 2–5 | 15–20 | weekly: terrain per theme, walking figures, army picker |
| R2 first playable vs bots, offline | weeks 5–8 | 15–20 | a full game against bots on the phone, all four graphics levels |
| R3 online on the existing server, Claude | weeks 8–10 | 8–10 | rooms with friends and Claude; both apps side by side |
| R4 D&D table: human DM + generated maps | weeks 10–14 | 12–16 | running a session as DM from the phone |
| R5 roguelike survival + bestiary | weeks 14–20 | 15–25 | a hardcore solo run, 60+ monsters |
| R6 catch-up, co-op, retire old apps | weeks 20–24 | 6–10 | one app per platform |
| R7 collection: painter, display boxes, campaign rewards | weeks 24–30 | 10–15 | painting their own models, a shelf of boxes, a campaign that pays for pulls |

Roughly double if one agent works alone.

---

## R0 — Scaffold, toolchain, CI exports, look build (weeks 1–2)

**Goal.** Retire the big risks first: the renderer on the owner's real devices, the kit import, the CI export and
signing path, Thai text, the determinism toolbox. Builds on PR #27 (`claude/new-session-fsucoo`), which the owner
merges first.

**Deliverables.** `godot/` in the target layout; integer maths + RNG + hash + digest with tests and the purity lint;
merged-surface kit import with team tint and impostor baking proven on all 312 kits; a look build (terrain, ~400
figures with team rings, pan/pinch, Thai HUD, GPU-check screen) as APK + exe on the `build-N` release; CI with x86 + arm64
tests, Windows smoke, signed APK on main; the oracle recordings from the old page; `docs/GODOT.md`.

**Tasks (parallel).**

- **R0-A · layout + runner** (track tools/tests). Fold PR #27 into ARCHITECTURE §1: `godot/scripts/i18n.gd` →
  `godot/ui/i18n.gd` (autoload `I18n`, add `ui/i18n_extra.json` lookup after `data/i18n_en.json`);
  `scripts/orbit_camera.gd` → `table/camera_rig.gd`; `scripts/kit_lineup.gd` → `table/figures/kit_library.gd`;
  probe scripts → `scenes/probe/`; `assets/theme/` → `ui/theme/`; new `app/app.gd` (settings in
  `user://settings.cfg`, ScreenStack router), `app/log.gd`, `app/clock.gd` autoloads. Make `tests/run_tests.gd`
  discover `tests/unit/**` and `tests/golden/test_golden.gd`; add `tests/run.sh [quick|full|<suite>]` with `TEST_OUT`;
  write `docs/GODOT.md` (module map, ownership tracks, invariants) and update `godot/README.md`. Done when the existing
  tests pass from the new paths and the probe still renders under xvfb.
- **R0-B · determinism toolbox** (track core). `core/version.gd` (RULES_V 10, APP_VER), `core/fx.gd` (idiv, imod,
  isqrt, dist, dist2, norm1000, js_round, to_fixed_1/2, stable_sort), `core/rng.gd` (PCG32 streams, bounded, d6),
  `core/hash.gd` (ihash2/ihash3, FNV-1a 64), `core/events.gd`, `core/actlog.gd`, `core/table.gd` (apply/advance/
  digest/snapshot skeleton). Tests: `tests/unit/test_fx.gd` against vectors from `tools/gen_vectors.mjs` (node computes
  JS Math.round/toFixed semantics and isqrt truth), `test_rng.gd` (PCG32 known-answer vectors, d6 histogram, stream
  independence), `test_hash.gd`, `test_core_purity.gd` (scans `godot/core/**` for the forbidden tokens of ARCHITECTURE
  §2; a planted `float` in a fixture must fail). Done when all pass headless.
- **R0-C · CI and exports** (track CI). Extend `.github/workflows/godot.yml`: `kits` job runs `godot/tools/kits.sh`
  (export kits, bake impostors under xvfb, bake clips when R1-V2 lands) with `actions/cache` keyed by
  `sha256(app/src/main/assets/battle-table.html, godot/tools/*)`; add `test-arm` (ubuntu-24.04-arm: import + unit +
  golden); `windows` zips the exe with the ANGLE/Mesa fallback folder + Thai README; add `windows-smoke`
  (windows-latest runs `CandlelightTable.exe --headless -s res://tests/selftest.gd`); `android` on main runs
  `--export-release` with `GODOT_ANDROID_KEYSTORE_RELEASE_PATH/_USER/_PASSWORD` from the existing `KEYSTORE_BASE64`,
  `KEY_ALIAS`, `KEYSTORE_PASSWORD` secrets (decode to `$RUNNER_TEMP`, delete at job end), `version/code` from
  `github.run_number`, `aapt dump badging` + size gate (fail > 120 MB); `release` job attaches
  `candlelight-table-godot-<run>.apk` and `-windows.zip` to `build-${{ github.run_number }}` via
  `softprops/action-gh-release@v2`. Set `package/unique_name = dev.mini.candlelight.table` in `export_presets.cfg`; add
  a step that greps the repo for `keystore/release=` values and `.jks` files. Done when a PR run is green and a main
  run attaches both files.
- **R0-D · kit import, paint shader, impostors** (track table/figures). `assets/kits_import/kit_post_import.gd`
  (EditorScenePostImport: merge surfaces → one ArrayMesh surface, `COLOR` = palette colour, `CUSTOM0` = tint flag +
  palette index, skin kept, indexed where normals agree) applied through `[importer_defaults]`; `assets/shaders/
  figure.gdshader` (paint table per ARCHITECTURE §7 — no team dye; `paint_row` uniform for skinned, `INSTANCE_CUSTOM.x`
  for MultiMesh; per-vertex shading define); `tools/bake_impostors.gd` (16 yaw x 2 pitch per kit →
  `assets/impostors/<kit>.png` + `_m.png`); `assets/kits/CONTRACT.md`; `tests/render/test_lineup.gd` (every kit: 23
  joints for skinned kits, every material maps to a palette key with a tint flag, scale sane; one PNG line-up per army;
  one kit drawn twice with a paint row proves the override; in the line-up scene draw calls == figures). Done when 312
  kits import and the test passes under xvfb.
- **R0-E · the look build** (track table + ui). `scenes/main.tscn`, `scenes/battle_table.tscn`, `table/table_view.gd`,
  `table/terrain_mesh.gd` (from a provisional heightfield; swaps to `core/field` in R1-V1), `table/props_layer.gd`
  (placeholder MultiMesh props), `table/figures/figure_pool.gd` v1 (skinned near + rigid MultiMesh far, kit colours),
  `table/rings.gd` (one MultiMesh of ground rings: team colour under every figure, selection/destination/objective
  later), `table/camera_rig.gd` touch + mouse, `ui/screens/gpu_check.tscn` (adapter, GL version, fps, draw calls,
  memory, 400-rigid + 100-skinned stress, graphics level picker with render scale and shadows per ARCHITECTURE §6 —
  the owner's Mali-G52 phone ran the probe at 21 fps with shadows at full resolution, so lo must be the phone default —
  Thai LineEdit for the IME check), Thai HUD through `I18n`. `tests/render/test_budgets.gd` skeleton printing counters
  per level for the 400-figure scene. Done when APK and exe show ~400 figures with team rings on a terrain,
  pan/pinch/orbit work, and counters print in CI.
- **R0-F · data schemas and lint** (track tools). `data/schema/*.json` (unit, weapon, army, theme, ability, i18n,
  map_layout, monster stub), `data/version.json`, `tools/validate_data.py` (schema, banned names of AGENTS rule 1 over
  `godot/`, Thai→English completeness for `ui/` and `data/`, `types.json` order append-only vs the previous commit, dice
  per roll ≤ 60), `tools/gen_bt_data.py --snapshot` (reads `../candlelight-server/worker.js` locally for `BT_RULES` and
  the datasheet table into `data/bt2_snapshot.json`), and the design notes in `docs/GODOT.md`: layout-JSON schema and
  the DM-act vocabulary (ARCHITECTURE §9). Done when the lint runs in the `test` job and a planted banned word fails it.
- **R0-G · oracle recorder** (track tools). `tools/record_oracle.js` (Playwright on `battle-table.html` via
  `window.BT`: seed/size/setList/setDep/start/dice/clock(false)/tick/botStep/capture(true)/board()/log()/props()) with
  20 scenario definitions in `tests/oracle/scenarios.json` (all 15 armies, 2–8 teams, obj/kill, hidden units, every act
  code) writing `tests/oracle/<name>.json` (setup, lists, skins, props, deps, acts, board after every act); a histogram
  check that all 18 act codes occur; `tests/oracle/README.md` with the format. Done when recordings exist and the
  histogram is complete (consumed by R1-E).
- **R0-H · owner gate** (lead). Point the owner at the `build-N` release; collect GPU-check screenshots from the old
  PC and two phones, a Thai name typed in the LineEdit, and a yes/no on the figures; write the Thai note
  `web/สิ่งที่เปลี่ยน-<วัน><เดือน>69-รุ่นใหม่0.1-แอปใหม่โครงแรก.md`.

**Acceptance tests.** CI jobs `test`, `test-arm`, `windows`, `windows-smoke`, `android` green; `tests/unit` passes
including `test_core_purity`, `test_fx`, `test_rng`; `test_lineup` passes on 312 kits; probe PNGs show Thai without
boxes in Thai and English; the owner reports the GPU check draws on the phones and the PC; the data lint runs in CI.

**Effort.** 1.5–2 weeks with 4 agents (6–8 sessions); 3–4 weeks alone.

---

## R1 — Deterministic rules core v10, headless, plus the look track (weeks 2–5)

**Goal.** Port the page's game script (~6,300 lines of JS) into `core/` as integer rules, proven by goldens on three
platforms and by the page oracle; ship a weekly look build meanwhile.

**Deliverables.** `core/field`, `core/battle` complete; `tools/make_golden.gd` and `tests/golden/*.json`; the oracle
suite green with an allowlist; 30-game bot smoke; perf budget test; `docs/GODOT.md` lists the intentional v10
differences; decision recorded: v10 ships. Look track: terrain per theme, baked walk proof, walking figures with tiers,
army picker screen — four builds on `build-N`.

**Tasks (parallel; core tracks must not touch each other's files, integration by R1-E).**

- **R1-A · field** (track core/field). `core/field/noise.gd` (Q16.16 vnoise/fbm over `Hash.ihash2`, 1024-entry sine
  table), `terrain.gd` (HG in MI, heightAt, `d = ((w*36+50)/100)*2`), `props.gd` (genProps with STRUCT kinds, PROP_CAP
  480, levelUnder, blockAt, crowded, freeSpot), `offsets.gd` (literal tables) + `tools/gen_offsets.gd` that re-derives
  them, `objectives.gd` (placeObjectives, objCtl, VP_PER/VP_CAP/OBJ_R). Tests: `tests/unit/test_noise_field.gd`
  (fixed heights and prop lists per seed/theme/terrain/density, two Field instances identical, freeSpot/blockAt cases,
  offsets re-derived equal). Source: the page at CODEMAP anchors `function buildTerrain(`, `function genProps(`,
  `function placeObjectives(`.
- **R1-B · data, state, army** (track core/battle data). `core/data.gd` (typed loading of `data/*.json`, TY(k), facOf,
  order list, hidden fields opaque), `core/battle/state.gd`, `squads.gd` (sqModels/sqAlive/sqEdge/sqCenter/engagedWith/
  isEngaged/formation integer/spotFree), `army.gd` (autoList from CORE pools on the `armies` stream, armyCap, baseCap,
  SPEC_TOTAL, ptsOf, teamPts, fitList, slotMax, deploy, autoDep, depWhyNot, depCapacity, fitSkin). Tests: `test_data.gd`
  (re-run `tools/export_data.js` and diff; TYPES order append-only; `RULES_V` vs `data/bt2_snapshot.json`),
  `test_army.gd` (caps, fitList, autoList fixed per seed, hidden units free of the budget and capped at one — without
  describing the unlock), `test_squads.gd`.
- **R1-C · combat** (track core/battle combat). `core/battle/combat.gd` (atkMath, woundNeed, INF, shootersOf, auras,
  painOn, pactOn, marked, shotWhyNot/chargeWhyNot/healWhyNot/grenWhyNot returning message keys), `abilities.gd`
  (registry, one handler per flag and weapon keyword from `data/README.md`), `pend.gd` (all stages and apply* functions,
  dealDamage, nextVictim by index, gloryHeal, rollerOf, prunePend, applyWhole, the ≤ 60 dice + fallback-stream rule),
  `strats.gd`. Tests: `test_combat.gd` (atkMath tables for representative pairs, modifiers capped ±1, poison, marker,
  pain from round 3, pact sixes, aoc, bless, heel, dw/lh/su/tr/bl/rf/hv), `test_abilities.gd` (one test per flag),
  `test_pend.gd` (hit→wound→save, fallback padding, overwatch, charge 2d6, re-rolls, stratagem once per phase),
  `test_strats.gd`.
- **R1-D · engine, acts, bots** (track core/battle engine). `core/battle/turn.gd` (startTurn, finishCommand, nextPhase,
  startFight, scheduleFight, advance guard 60, playerDone, endTurn, finish, checkOver, endRoundCheck), `moves.gd`
  (moveRange, nearFoe, planMove integer slot search, applySMove, groupMove, declareCharge, keepCharge), `acts.gd` (codec
  + allowlist mirror + caps), `board.gd` (board_state 0.1" js_round shape of the Worker's btBoard; digest), `bot.gd`,
  `battle.gd` (extends Table). `tools/make_golden.gd` and `tests/golden/*.json` (every army, 2–8 teams, obj/kill),
  `tests/golden/test_golden.gd` (act by act and in batches), `tests/unit/test_smoke_bots.gd` (30 games < 2 min, legality
  checks). Tests: `test_turn.gd`, `test_moves.gd`, `test_acts.gd`, `test_board.gd`, `test_bot.gd`.
- **R1-E · oracle, perf, integration** (track tests; integrator). `tests/oracle/test_oracle.gd` (build the v10 match
  from a recording with the page's props and deps injected as fixtures, replay acts, compare per act exactly / within
  0.05", print the first difference), `tests/oracle/allowlist.json` (each entry: scenario, act seq, field, reason),
  `tests/unit/test_perf_core.gd` (20-model squad move < 150 ms on a 500-model field; 30 bot games < 2 min), the
  integration PR wiring A–D into `battle.gd`, the intentional-differences section of `docs/GODOT.md`, and the decision
  memo at the end (`docs/GODOT.md` "v10 gate": oracle + arm64 goldens green → ship).
- **R1-V · look track, one build a week** (track table + ui, 1 agent):
  V1 `table/terrain_mesh.gd` from `core/field` heights with theme colours, `props_layer.gd` from `core/field/props`,
  `table/sky.gd` per theme → build. V2 `tools/bake_anim.js` + `bake_anim.gd`: bake **one humanoid walk, one horse, one
  walker** first, `tests/render/test_anim_footslide.gd` (≤ 15 mm), then the full humanoid library → build with figures
  walking in a loop. V3 `figure_pool.gd` three tiers + `impostors.gd` per-battle atlas + `walker.gd` → build.
  V4 `ui/screens/army.tscn` (roster from `data/types.json`, datasheets, random, preview turntable) in Thai/English with
  `ui/i18n_extra.json` entries → build.
  V5 **gothic ruin set for the ruin theme** (owner wish, 7 Oct, with reference photos of tabletop ruins): our own
  modular low-poly kit in `assets/props/ruin/` — wall panels with pointed-arch and rose windows, fluted pillars with
  bands, broken jagged tops, upper floor plates on beams, buttresses, stairs, rubble piles with fallen pillar drums,
  robed guardian statues, rust-red industrial panels and pipes; weathered stone, verdigris and brass palette. Each
  rules kind keeps its footprint (`building` = two- or three-storey ruin, `wall` = broken wall run, `tower` = ruined
  spire, `rubble`, `barricade` = broken balustrade, `pipe`), pieces merge into one mesh per kind (MultiMesh), and lo/min
  get simpler variants inside the §6 budgets. **No emblems, logos, skulls-with-wings or other marks of any game
  company** (AGENTS rule 1); the reference photos are not copied into the repo. Standing on upper floors is a rules
  change for later (needs a design note and a rules-version bump), not part of V5. One sample building goes to the
  owner as a screenshot before the full set.

**Acceptance tests.** `godot --headless` plays complete bot games of all 15 armies in seconds; `tests/golden` digests
identical on ubuntu-latest, ubuntu-24.04-arm and the Windows exe; `test_oracle` passes all 20 recordings with only
allowlisted divergences and every reason reviewed; `test_smoke_bots` legality checks pass; `test_perf_core` within
budget; purity lint green; `test_data` parity 100 % with the server snapshot; four look builds on `build-N` with owner
screenshots.

**Effort.** 3 weeks with 5 agents (15–20 sessions); 6–8 weeks alone. This is the long pole; expect two rounds of subtle
divergences (ordering, rounding, key order) found by the oracle.

---

## R2 — First playable against bots, offline, on the phone (weeks 5–8)

**Goal.** The whole battle table plays offline on all four graphics levels within the budget table, looks like real
models with natural motion, Thai and English complete.

**Deliverables.** `table/` complete (tiers, LOD, fx, dice tray, picking, rings, event player), `ui/` screens complete,
graphics levels with adaptive scale and idle mode, sound, perf and screenshot suites, APK < 90 MB.

**Tasks (parallel).**

- **R2-A · figures** (track table/figures). `figure_pool.gd` full: hysteresis re-tiering every 0.25 s, per-level skinned
  caps (min: selected squad + ≤ 8 walkers; lo 24; mid 80; hi 160), promotion of walking squads, LOD switch by on-screen
  height, blob shadows MultiMesh, `kit_library.gd` lazy `load_threaded_request`, per-battle impostor atlas. Tests:
  `tests/render/test_budgets.gd` asserting the ARCHITECTURE §6 table per level on the 400-figure / 480-prop / 8-team
  scene (draw calls, primitives, VRAM).
- **R2-B · animation** (track table/figures anim). AnimationTree (idle/walk/run blend by speed, one-shot actions on tray
  events), `walker.gd` final (clip speed ↔ travel, snap on arrival, thin on min), flyers hover from `data/fly.json`,
  cavalry bob + rider seat, deaths and fallen pieces, unskinned kits' procedural motion (bob/hover/stomp). Tests:
  `test_anim_footslide.gd` on the full library; a headless scene test that every unit type spawns, walks, attacks and
  dies at every tier.
- **R2-C · table systems** (track table). `camera_rig.gd` final (tap-vs-drag, pinch, twist orbit, WASD, fit),
  `picking.gd` (float unproject → MI before any act; destination ring previews integer planMove), `rings.gd`,
  `fx/` per level (tracers MultiMesh quads, blasts, flames, casings; nothing on min beyond quads), `dice/dice_tray`
  (SubViewport on hi/mid, 2D result tray on lo/min, 24 baked tumbles from `web/dice-core.js` chosen by seedOf),
  `event_player.gd` mapping every event of `core/events.gd`. Tests: event→visual mapping smoke; dice tray determinism
  (same seedOf → same clip).
- **R2-D · UI** (track ui). `ui/screens/` setup, deploy, play_hud, custom, spectator, settings, preview + widgets
  (squad_card with abilityText port, datasheet, log_view capped 200 lines, turn_bar with clock, camera_bar);
  `ui/i18n_extra.json` complete. Tests: `tests/render/test_screens.gd` (every screen Thai + English at 640x360,
  960x540, 1280x800, 2560x1080; no overflow/overlap; no Thai in English mode through a whole bot game; baselines),
  `tests/unit/test_i18n.gd` static completeness.
- **R2-E · levels, sound, perf on min** (track app + table). Graphics levels data table, first-run guess from memory +
  2-second benchmark, `adaptScale`/`slowStep`, `low_processor_usage_mode` idle rule, `Engine.max_fps` per level,
  `tools/bake_sfx.js` (page `SND.probe` → `assets/sfx/*.ogg`, three music loops), `app/audio.gd`, `tools/perf_scene.gd`
  counters as a CI artifact, GPU-check screen final. Owner gate: a full game on a phone on `min`.

**Acceptance tests.** `test_budgets` passes all four levels; `test_screens` green in both languages at four
resolutions; `test_anim_footslide` ≤ 15 mm; a headless pve game through the real UI buttons finishes; APK < 90 MB;
owner plays a full game against bots on a phone on `min` and on Windows.

**Effort.** 3–4 weeks with 5 agents (15–20 sessions); ~3 months alone.

---

## R3 — Online on the existing server, Claude as a player, release side by side (weeks 8–10)

**Goal.** New clients play together through the existing Worker at rules version 10; Claude joins via `bt_sit`
unchanged; old v9 clients keep their own rooms; the owner can switch between apps.

**Deliverables.** `net/` complete; lobby and join flow; owner duties; resync; mock Worker and net tests; the server PR;
Thai release note; both apps on `build-N`.

**Tasks (parallel; R3-S1 merges first).**

- **R3-S1 · server PR** (candlelight-server, merge first). `worker.js`: `BT_RULES = 10`, `btVer` accepts 2..10 (v9 rooms
  stay joinable by v9 pages), `btBoard` accepts `digest` (string ≤ 32) and `snap` (JSON ≤ 64 KB, clamped), datasheets for
  v ≥ 10 from `bt_data.json` generated by `godot/tools/gen_bt_data.py` (shipped in the PR), `app.html` gets a
  "เปิดในแอปใหม่" button with deep link `candlelight://bt/<CODE>`; server tests updated; PR text states the merge order.
- **R3-A · room client + lobby** (track net + ui). `net/room_client.gd` (create/join/poll/act/list/dep/state/team/
  leave/board, ordered send queue, adoptRoom, backoff, Thai status line), `net/server.gd` (URL from Settings, deep link
  parsing, Android intent filter + Windows registry entry in the presets), `net/json_num.gd`, act log + pid + code
  persisted in `user://rooms/<code>.json`, rejoin after restart, desync alarm vs the owner's `digest`, resync from `snap`;
  `ui/screens/lobby.tscn` (room card, seats, teams, leave, start) and join-code entry on setup.
- **R3-B · owner duties** (track net). Bots on the owner only, OWNER_WAIT 25 s rolls for silent players, clock `endph`,
  resolveBots + `/state` roster, `/board` push each turn with `digest` + `snap`, `owner` act hand-over, BT_GONE_MS
  behaviour; Claude seat handling (`ai` players: `bt_move` x,z → integer planMove; `atk` with hit dice).
- **R3-C · net tests** (track tests). `tools/mock_worker.mjs` (bt endpoints + the Worker's sanitiser: 60 dice, 40
  points, ids ≤ 20, 400 on unknown codes), `tests/net/test_net_sync.gd` (two headless instances: owner plays bots, joiner
  polls; digests equal after every batch; dropped-owner failover; late joiner from `snap`), optional `WORKER_URL` to
  run against `npx wrangler dev` in `../candlelight-server` locally; `test_data` asserts `RULES_V == BT_RULES` of the
  refreshed snapshot.
- **R3-D · release** (track docs + app). `app/selftest.gd` screen (replay digests + fps on min), crash log viewer with
  "copy log", `core/version.gd` bump, Thai note `web/สิ่งที่เปลี่ยน-…-รุ่นใหม่1.0-เล่นออนไลน์.md` with a 5-line owner
  checklist, README for the owner (install both apps, which to use when).

**Acceptance tests.** `test_net_sync` green in CI; two phones + one PC + Claude (`bt_sit`) play one room to the end with
the desync alarm silent (owner gate); a v9 page joining a v10 room gets the existing 409 Thai message and v9 rooms still
work; kill the app mid-game and rejoin the seat; the spectator 8-team room runs; both APK and exe on `build-N`.

**Effort.** 2 weeks with 3 agents (8–10 sessions); 4 weeks alone.

---

## R4 — D&D table with a human DM and generated maps (weeks 10–14)

**Goal.** A human runs a full session as DM from the phone or PC with a generated map; players on the web app or the
new app see the same board; Claude-as-DM via MCP keeps working and can co-narrate.

**Deliverables.** `net/dnd_client.gd`, campfire + character creator, `table/board3d`, DM panel, `core/dnd/mapgen`,
layout schema in use, server PR R4-S1, tests and screenshot goldens per biome.

**Tasks (parallel).**

- **R4-A · client, login, lobby** (track net + ui). `net/dnd_client.gd` (`/api/auth/guest`, `pair/claim`, `/api/me`,
  `/api/rooms` create/join/poll since seq/act/roll/hp/move/look/leave/reroll/ready, the `dm` action), `ui/screens/
  dnd_camp.tscn` (campfire ring, ready), character sheet/creator reusing the board's look data; token persisted in
  `user://`. Tests: headless board-state application from recorded room JSON.
- **R4-B · board and tokens** (track table/board3d). `scenes/dnd_table.tscn`, `table/board3d/` tile scenes for the
  page's scene list, tokens as figures with name plates and HP bars, tap-to-move within 6 units on your turn, shared
  dice (`showRoll` semantics), combat order display. Tests: screenshot per scene; token placement determinism.
- **R4-C · DM panel** (track ui). `ui/screens/dm_panel.tscn` tabs Story / Board / Fight / Map / Players (ARCHITECTURE §9),
  every action an act (`core/dnd/dm_acts.gd`), undo as reverse act, large touch controls, monster/NPC picker from
  `data/dnd/monsters/*.json` stubs. Tests: DM flows headless; English sweep.
- **R4-D · map generator + renderer + server PR** (track core/dnd + table/board3d). `core/dnd/mapgen/` (dungeon BSP,
  cave CA, ruins/town grid, wilderness noise) emitting the layout JSON of `data/schema/map_layout.json`;
  `tests/unit/test_mapgen.gd` over 200 seeds (connectivity, min spawn distance, doors on walls, size); tile MultiMesh
  renderer ≤ 12 draw calls, fog of war, light radius; minimap PNG for the DM; **R4-S1 server PR** (merge first):
  `board.map {seed, kind, ver, edits[]}`, token clamp by layout size, text map summary in `read_room`.

**Acceptance tests.** 200 seeds valid in CI; the same seed renders identically on two devices (digest of the layout);
`test_budgets` on min holds for the map scene; the owner runs a session as DM with two players (one on the web app) and
Claude co-narrating (owner gate); five of five random dungeons acceptable to the owner.

**Effort.** 3–4 weeks with 4 agents (12–16 sessions).

---

## R5 — Roguelike / hardcore survival and the bestiary (weeks 14–20)

**Goal.** A complete, replayable solo survival run from the campfire to death or escape, with 60+ monsters on day one
from existing kits and a pipeline for more. Starts with a one-week design round with the owner (and GPT) whose output is
data files, not code.

**Deliverables.** `core/dnd/` rules on the Table base, `data/dnd/survival.json`, bestiary data + creature rig + clips,
encounter generator tied to mapgen, run save/replay, UI for meters/injuries/inventory, Claude summaries.

**Tasks (parallel).**

- **R5-A · survival rules + goldens** (track core/dnd). Characters with occupations as mechanics, meters (hunger,
  thirst, fatigue, sanity, light) from `data/dnd/survival.json`, limb injuries, permadeath + corpse runs, brutal checks,
  status effects via the abilities registry, rest/camp events, depth/era escalation, difficulty presets. Tests: unit per
  system; `tests/golden/rogue_*.json` replays with digests on x86 + arm64.
- **R5-B · bestiary + encounters** (track data + table/figures). `data/dnd/monsters/*.json` (stats, behaviours as AI
  profiles, loot, fear), kit mapping via palette/scale/part swaps, a quadruped/creature skeleton + clip set for new
  monsters, `core/dnd/encounter.gd` (initiative, attacks, conditions) tied to spawns from mapgen. Tests: every monster
  spawns, acts, dies, drops loot in a headless smoke; banned-name lint over the bestiary.
- **R5-C · UI** (track ui). Character sheet, inventory, meters, injuries, death screen, run summary, Thai + English with
  `i18n_extra.json`. Tests: English sweep, layout at four resolutions.
- **R5-D · run save, replay, Claude** (track app + net). Run = seed + act-log checkpoints in `user://runs/`, replay from
  seed + log, Claude/human narrator overlay via the room log, `read_room` summaries of meters and threats (server PR
  only if a field is missing).

**Acceptance tests.** A complete solo run replays bit-identically from seed + log on CI; 60+ monsters pass the smoke;
balance knobs are JSON only; the owner finishes (or dies in) one run and signs off on the feel.

**Effort.** 5–6 weeks with 3–4 agents (15–25 sessions) after the design week; content-heavy and open-ended.

---

## R6 — Catch-up, co-op, polish, retire the old apps (weeks 20–24)

**Goal.** One app per platform. Remaining parity and polish items, co-op roguelike, natural-animation polish, the
package-id takeover, the old shells removed from CI.

**Tasks (parallel).**

- **R6-A · co-op rooms** (server + net). **R6-S1 server PR**: a generic act-log room kind (`kind: "rl"`, same
  create/join/poll/act shape, per-kind allowlist); `net/room_client.gd` generalised; co-op run client.
- **R6-B · animation polish + parity backlog** (track table). `IKModifier3D`/`SkeletonIK3D` foot pins and
  `LookAtModifier3D` heads for ≤ 8 near figures on mid/hi, turn-in-place polish, music styles, skins and chapters UI,
  preview gallery; a feature checklist against CODEMAP §2 closed.
- **R6-C · packaging and sign-in** (track CI + app). Switch `package/unique_name` to `dev.mini.candlelight` with the same
  keystore and a higher `version/code` in one reviewed PR (in-place update over the old app); Google sign-in via a Godot
  Android plugin (never a web view); Windows installer optional.
- **R6-D · docs and retirement** (track docs). Rewrite `docs/CODEMAP.md` for the new app, keep `tests/` for the old pages
  only while the server still serves them, remove the WebView shell and Tauri jobs from `build.yml` when the owner says
  so, archive `app/src/main/assets/*.html`.

**Acceptance tests.** Co-op run with two devices through `test_net_sync` (rl kind); the new APK updates over the old
app on the owner's phone; all suites green; Thai docs current.

**Effort.** 4–8 agent sessions.

---

## R7 — Collection: model painter, display boxes, campaign rewards (weeks 24–30)

**Goal (owner wishes of 7 Oct).** The owner wants the models to be a collection: paint your own models, decorate them,
keep them in boxes on a shelf or a table you tap to open, and a campaign mode that earns in-game money spent on random
model pulls. Design week with the owner (and GPT for opinions) before any code, like R5. Never real money: pulls cost
campaign coins only, and the odds are shown in Thai on the pull screen.

**Deliverables.** `ui/screens/painter.tscn` (pick a model, tap a palette slot, pick a colour; the paint table of
ARCHITECTURE §7; undo; save to `user://paint/<kit>.json`; paint travels with the army list as ints so friends see it);
`ui/screens/shelf.tscn` (boxes per army on a 3D shelf or table, tap a box to open it, turntable preview with the kit's
real animations); `core/collection.gd` (owned kits, coins, pull tables as JSON in `data/collection/`, seeded pulls from
a stream so a replayed act log gives the same pull); campaign hooks (coins from won battles and survival runs, R5);
decorations (banners, bases, trophies as extra palette slots or small attachments on the mount points of
`kits.json`). Tests: paint round-trip, pull determinism, a shelf render test, i18n of every new string.

**Open questions for the design week.** Which kits are owned from the start (all of them for the battle table, so no
one is locked out of a fair game; collection affects only looks?); whether the painter edits per model or per squad;
how much of this is visible to online opponents on v10 rooms (paint as ints is cheap; decorations need a cap).

**Effort.** 10–15 agent sessions after R6, or in parallel with R5 if the owner prefers it earlier.

---

## Risk register

| # | Risk | Early signal | Retirement action | When |
| --- | --- | --- | --- | --- |
| 1 | The owner's old PC (2 GB) lacks OpenGL 3.3 and Godot 4 will not start | GPU-check exe shows a GL 2.x adapter or a black window | R0-E ships the GPU-check exe with ANGLE (D3D11) fallback and a Mesa software `opengl32.dll` folder as plan C; owner screenshots the adapter line; decide Mesa-only build vs keeping the HTML table for that PC before any rendering work | R0 |
| 2 | Cheap Android phones: GLES3 driver bugs, skinning cost, thermal throttling | GPU-check fps/draw-call numbers; a black phone screen (WebGL already rendered black there) | R0-E stress screen on two cheap phones; per-level skinned caps are data; startup benchmark picks the level; `slowStep` never goes up | R0/R2 |
| 3 | Determinism leak into `core/` (float, trig, engine RNG, Node order, `/` truncation) | purity lint fails; goldens differ between x86 and arm64 | R0-B purity test, int-only `Fx`, PCG32 vectors; goldens on x86 + arm64 + Windows exe on every PR from R1; `desync` event + alarm in R3 | R0–R3 |
| 4 | Rules fidelity: v10 plays differently from the rules Claude's `bt_look` text and the datasheets describe | oracle differences outside the allowlist; win rates by army drift | R0-G recordings, R1-E oracle with injected props/deps and a reviewed allowlist; abilities registry with one test per flag; datasheets extracted, never retyped | R1 |
| 5 | Kit pipeline drift (joint names, tint flags, scale, 52 unrigged kits) | `test_lineup` fails; impostors blank | R0-D contract test on all 312 kits and `CONTRACT.md`; whole-mesh motion for unrigged kits until R5 rigs | R0 |
| 6 | Baked clips look robotic on turns and slopes (wish 2) | foot-slide metric > 15 mm; owner video gate | R1-V2 bakes one walk + horse + walker first and measures; AnimationTree blend by actual speed; IK pins for near figures in R6 | R1/R2 |
| 7 | GDScript too slow in `planMove`/bots on 500-model fields | `test_perf_core` over budget | typed core, bounded searches, spatial grid wrapping predicates only; GDExtension as the measured-only escape hatch | R1 |
| 8 | Protocol coupling: `BT_MAX_ACTS = 500` blocks late join; a v10 client is refused until the server bumps | 409 on join; a rejoin after 500 acts fails | `snap` + `digest` in the R3-S1 server PR (first merge of R3); act log persisted locally; `test_data` fails if `RULES_V != BT_RULES` | R3 |
| 9 | Silent divergence between devices (the server stores acts, does not simulate) | owner's `digest` differs from a device | desync alarm from R3 with the first differing unit in the log; `test_net_sync` through the mock Worker; later a hash echo in the poll | R3 |
| 10 | CI cost and drift: 1.2 GB templates, SDK versions, Godot point releases changing import output | long runs; cache misses; baseline diffs | pinned 4.7.1 with sha256 in `tools/godot.sh`, caches keyed by version and page hash, `paths` filter, quick vs full, 60-min cap; engine upgrade only in a dedicated PR | R0 |
| 11 | Thai text, IME, safe areas on phones | boxes in the probe PNG; the owner cannot type Thai | Sarabun is the theme font (done); R0-E LineEdit on the probe build; `test_screens` at four resolutions | R0 |
| 12 | Two agents collide in one file; untestable claims | overlapping PRs; "works on my machine" | ownership tracks per folder, small PRs, `docs/GODOT.md` like CODEMAP, every milestone has a CI acceptance test and a Thai note; the old apps keep shipping until R3 | all |
| 13 | Hidden units or banned names leaking into a new codebase | lint hit; a PR text explains an unlock | `tools/validate_data.py` in CI over `godot/`; `sec`/`lk` opaque; unlock logic in code only; PR text discipline | R0 |
| 14 | Memory on 2 GB devices with 312 kits | RSS > 350 MB on the GPU-check screen | lazy per-kit loading, per-battle impostor atlas, flat colours, RSS printed in the perf harness | R2 |
| 15 | Login and platform services (Google sign-in needs a native plugin; deep links need manifest entries) | the pairing flow is the only login | guest + pairing code first (both exist on the Worker); Google via a Godot plugin in R6, never a web view; deep link registered in R3 | R4/R6 |
| 16 | Scope creep from the D&D wishes starving the battle path | D&D code before R3 is green | R0 lays schema + docs only; D&D code starts after the R3 owner gate; content is JSON authored in parallel | R0–R3 |
| 17 | Secrets misuse during release signing or the package-id switch | a `keystore/release=` value in a preset | env-var signing only, CI grep for presets and `.jks`, keystore in `$RUNNER_TEMP` deleted at job end; the id switch in one reviewed PR with the proven flow | R0/R6 |
