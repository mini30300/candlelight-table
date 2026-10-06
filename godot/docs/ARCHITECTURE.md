# Candlelight Table on Godot 4 — final architecture

Status: decided by the lead engineer after three architect proposals ("parity", "future", "mobile") and three judge
rounds. For agents. Thai summary for the owner: `สรุปแผน.md`; milestones and task lists: `PLAN.md`.

## 0. Decision

**Base design: "mobile" — weak phones and determinism first.** All three judges chose it (51/55/53 points): its numbers
match the real kit export (312 kits, 260 skinned, 5–23 materials, ~1,200 triangles mean, 48 MB), it is the only plan
that answers `BT_MAX_ACTS = 500` (late join / resync) and the one-draw-call-per-figure problem, and its CI proof
(x86-64 + arm64 goldens, a mock Worker, no new secret) fits agents working headlessly.

**Grafted from "parity"** (the owner lens and the oracle):
1. Cadence: a look-only build on the owner's real devices in week 1–2 (terrain, ~400 kits with team rings, pan/pinch), then a
   weekly build while the rules port runs headless in parallel. The owner never waits three weeks for a screen.
2. The old page as a **fidelity oracle**: `tools/record_oracle.js` drives `window.BT` (capture / board / dice / tick) on
   `battle-table.html` and records scenarios; the v10 core replays them with the page's props and deployment injected and
   must match hp, phase, VP, CP, squad flags and victim order exactly, positions within 0.05". Tolerance-based, with an
   explicit allowlist of accepted divergences, each with a reason. Not bit-parity: v9 rooms are not shared.
3. `godot/tools/export_data.js` (already merged in PR #27) + a drift test, so datasheets, pools and English strings are
   extracted from the page, never retyped.
4. The small JS-semantics helpers that survive in an integer core (`js_round` half-up, `to_fixed`, `stable_sort`), the
   written audit rules for Dictionary order and `sort_custom` instability, the act log persisted in `user://` for seat
   rejoin, and the desync alarm against the owner's pushed `/board`.
5. The end-of-R1 gate: **v10 ships only when the oracle and the arm64 goldens are green.**

**Grafted from "future"** (the spine for wishes 3–6):
1. A thin `Table` base (state + rules + act log + bots + typed events) with an `EventPlayer` that is a no-op sink in
   headless runs. The battle table is rules set A; the D&D/roguelike table is rules set B on the same primitives.
2. An abilities registry (flag → handler, one unit test per flag), reused for D&D conditions.
3. The layout-JSON schema and "DM commands are acts" decided in R0 as schema + doc only; no D&D code before R3 is green.
4. The Worker's datasheet table (`BT2`) for v ≥ 10 generated from `godot/data` and shipped as a file in a server PR.
5. The exported Windows exe run headless on `windows-latest` to compare replay digests; the in-app Selftest screen; an
   in-app crash log with a copy button; the final package-id switch with the same keystore.

**Corrections applied to the base plan** (from the judges):
- `hash2` of the page is *not* uint32-exact in V8 (its middle product passes 2^53 and is rounded as a double). v10
  declares its own 32-bit integer hash; terrain and prop shapes differ from v9 on purpose and are documented as such.
- Kits stay generated and git-ignored (PR #27 already regenerates them in CI with Playwright); CI caches them by a key
  made from the page and the exporter, and bakes impostors and animation clips in the same job.
- The Worker's human-storyteller `dm` action already exists (`action === "dm"`, tools narrate / set_scene /
  start_combat / next_turn / end_combat / place_token / move_token / remove_token, owner only, `setup.dm === "host"`).
  R4 uses it; no server PR for basic DM operations.
- No VAT tier: rigid MultiMesh + impostors cover min/lo; skinned figures are capped per level.
- The server repo is private: CI never checks it out. CI uses `tools/mock_worker.mjs`; agents run the real
  `wrangler dev` locally (it is checked out next to this repo as `../candlelight-server`).
- Until the server bumps `BT_RULES`, a v10 client is read as version 1 and refused: **the server PR is the first merge
  of R3**, not an afterthought.

## 1. Repository layout

Same repository, folder `godot/`, building on PR #27 (`claude/new-session-fsucoo`: project scaffold, probe scene,
headless test runner, kit and data exporters, `.github/workflows/godot.yml`). `app/`, `desktop/`, `build.yml` and
`tests/` keep shipping the old apps untouched. The new APK uses application id `dev.mini.candlelight.table` so both
apps install side by side; the switch to `dev.mini.candlelight` (in-place update with the same keystore) is R6.

```
godot/
  project.godot                 gl_compatibility (desktop + mobile), landscape, 1280x720 canvas_items/expand, Sarabun theme,
                                autoloads App, I18n, Audio, Log, Clock, Net (see §3)
  export_presets.cfg            "Windows Desktop" (x86_64), "Android" (arm64-v8a + armeabi-v7a, min SDK 24, id
                                dev.mini.candlelight.table); keystore fields EMPTY — release signing comes from env vars in CI
  icon.svg · README.md          README in Thai: run, test, export (exists; keep current)
  app/                          autoload scripts (the only global state)
    app.gd                      App: settings (gfx level hi/mid/lo/min, lang th/en, sound, server URL) in user://settings.cfg via
                                ConfigFile, screen router (ScreenStack), back button, deep link candlelight://bt/<CODE>
    audio.gd                    Audio: buses, SFX/music players, voice cap 22, intensity follows events
    log.gd                      Log: ring buffer of the last 500 lines + crash/error capture; "copy log" button in Settings
    clock.gd                    Clock: the one tick source for view timers; tests freeze/step it (like BT.clock(false)/BT.tick)
    selftest.gd                 Selftest: replays tests/golden/*.json in-app and prints digests + fps on min (owner taps it)
  core/                         RULES CORE — pure GDScript, RefCounted only. No Node, no float, no engine RNG, no Vector2/3,
                                no Time/OS/Engine. Lint-enforced (tests/unit/test_core_purity.gd).
    version.gd                  const RULES_V := 10, APP_VER := "ใหม่ 0.1" (bumped per release), DATA_HASH (filled by the data lint)
    fx.gd                       fixed point: MI = milli-inch (1" = 1000); idiv (floor), imod (posmod), isqrt (Newton), dist, dist2,
                                dot, cross, norm1000 (direction vectors of length 1000), js_round, to_fixed_1/2, stable_sort
    rng.gd                      PCG32: state int64 masked to 32-bit ops; seed(stream_name, seed); next_u32, bounded(n) rejection
                                sampling, d6(); streams: terrain, props, objectives, armies, deploy, bot:<seat>, fallback:<seq>:<stage>
    hash.gd                     ihash2/ihash3 (v10's own 32-bit mixers), FNV-1a 64 over PackedInt64Array + strings
    events.gd                   enum of typed event ids and their payload shape (see §3)
    actlog.gd                   ordered acts {seq, pid, a, ...}; append, replay, snapshot/restore, persist to user://
    table.gd                    Table base: state + rules + act log + bots + events; apply(act) -> Array[Event]; advance(); digest()
    data.gd                     static loader of data/*.json into typed arrays and dictionaries; TY(k), facOf, order list
    field/
      noise.gd                  vnoise/fbm in Q16.16 over ihash2; sine table (1024 entries, int)
      terrain.gd                heightfield HG (MI), heightAt (visual only), table w/d: d = ((w*36+50)/100)*2
      props.gd                  genProps (STRUCT kinds, PROP_CAP 480, levelUnder), blockAt, crowded, freeSpot
      offsets.gd                committed literal integer offset tables: freeSpot rings (14 dirs x 10 rings), planMove (10 x 6)
      objectives.gd             placeObjectives, objCtl, scoring (VP_PER 5, VP_CAP 15, OBJ_R 3)
    battle/
      battle.gd                 extends Table: the battle table (rules set A); owns state, phases, pend, bots
      state.gd                  G, players, SQ, units: Arrays in creation order, fixed key order; ids "<player>:<i>", "<squad>.<j>"
      squads.gd                 sqModels, sqAlive, sqEdge, sqCenter, engagedWith, isEngaged, formation (integer), spotFree
      army.gd                   autoList (CORE pools + armies stream), armyCap, baseCap (min(250, 500/players)), SPEC_TOTAL 3000,
                                ptsOf, teamPts, fitList, slotMax, deploy, autoDep, depWhyNot, depCapacity, skins (fitSkin)
      combat.gd                 atkMath, woundNeed, INF, shootersOf, auras (AURA_R 6), painOn, pactOn, marked, *WhyNot (message keys)
      abilities.gd              registry flag -> handler: aura(hit/ld/bless/rez/veil), rez, wind, spawn, heel, heal, ttn, vsh, gk, hd,
                                pact, pain, ca, aoc, st, ac, brave, hero, fly, veh, chapters; weapon keywords rf as pi hv su tr lh dw bl po mk la
      pend.gd                   PEND stages: mkAtk, applyHit/Wnd/Sav/Reroll, dealDamage, nextVictim, gloryHeal, finishAtk,
                                applyShock/Charge/Ow/CMove/Gren/Heal/Rez, rollerOf, prunePend, applyWhole
      moves.gd                  moveRange, nearFoe, planMove (integer slot search), applySMove, groupMove, declareCharge, keepCharge
      strats.gd                 rr, ow, gtg, gren, brave: stratKey (once per team per phase; brave once per turn), canStrat, useStrat
      turn.gd                   startTurn, finishCommand, nextPhase, startFight, scheduleFight, advance (guard 60), playerDone,
                                endTurn, finish, checkOver, endRoundCheck, clock timeouts (as events, time comes from the act)
      acts.gd                   act codec JSON <-> typed; the Worker allowlist mirrored (codes + fields + caps); apply(act)
      board.gd                  board_state() = the Worker's btBoard shape (0.1" rounding, js_round), digest()
      bot.gd                    botStep, expDmg, target choice, move toward objectives; one action per call; bot:<seat> stream
    dnd/                        R4+: world.gd, dm_acts.gd, mapgen/ (dungeon, cave, ruins, wild), encounter.gd, survival.gd,
                                loot.gd, monster.gd — same purity rules, extends Table (rules set B)
  data/                         SOURCE DATA (exists): types.json (TYPES in protocol order), facs, core, themes, terrains, teams,
                                phases, chapters, variants, skins, fly, strats, anim, fx, natural, unit_colours, sky, dust,
                                constants, i18n_en.json, rules_summary.md — generated by tools/export_data.js, never hand-edited
    schema/                     JSON schemas: unit, weapon, army, theme, monster, item, map_layout, ability, i18n (R0)
    dnd/                        R4+: monsters/*.json, items.json, prefabs/*.json, survival.json, scenes.json
    version.json                rules_ver 10, data hash, the page's APP_VER/RULES_V the export came from
  table/                        3D PRESENTATION — reads core, never mutates it; may use floats and Godot's RNG
    table_view.tscn/.gd         Node3D root: camera rig, sun, environment, terrain, props, figures, rings, fx, picking
    camera_rig.gd               pan / pinch / orbit / WASD, fitTable, pitch 20–80°, tap-vs-drag; the same rig for both tables
    terrain_mesh.gd             one ArrayMesh from core HG (vertex colours by theme and slope), rails; grid step per level
    props_layer.gd              MultiMeshInstance3D per prop kind; simplified meshes on lo/min
    figures/figure_pool.gd      tiers: skinned near / rigid MultiMesh mid / impostor far; promotion of walkers; per-level caps
    figures/figure.tscn/.gd     Skeleton3D + MeshInstance3D (merged surface) + AnimationPlayer/Tree + Walker
    figures/walker.gd           visual x/z chase gx/gz at clip speed; snaps on arrival; "thin" on min
    figures/impostors.gd        per-battle atlas from assets/impostors for the kits in play; one MultiMesh of billboards
    figures/kit_library.gd      lazy per-kit loading (load_threaded_request), kits.json lookups, LOD pick
    event_player.gd             consumes Array[Event] per applied act and schedules visuals; no-op sink when headless
    rings.gd                    selection / destination / objective rings as MultiMesh quads
    picking.gd                  ray vs heightfield in float -> converted to MI ints before any act is built
    fx/                         tracers, blasts, flames, casings, blob shadows, CPUParticles caps per level; nothing on min beyond quads
    dice/dice_tray.tscn/.gd     SubViewport tray on hi/mid, 2D result tray on lo/min; baked tumble clips picked by seedOf
    sky.gd                      flat gradient per theme (Environment); skyline quad on mid/hi only
    board3d/                    R4+: tile builder from layout JSON (GridMap/MultiMesh), tokens, fog of war, lights
  ui/                           Control scenes, Thai first
    theme/default_theme.tres    (exists under assets/theme; move here in R0-A) Sarabun; 44 px touch targets; phone scale
    i18n.gd                     I18n autoload (exists as scripts/i18n.gd): Thai keys -> data/i18n_en.json + ui/i18n_extra.json
    i18n_extra.json             English for Thai strings that exist only in the new app (every new string needs a pair)
    screens/                    setup, army, lobby, deploy, play_hud, spectator, custom, settings, preview, gpu_check,
                                dnd_camp, dnd_table, dm_panel (R4), rogue_* (R5)
    widgets/                    squad_card, datasheet, log_view, dice_popup, roster_row, turn_bar, camera_bar
  net/
    room_client.gd              /api/bt/rooms: create/join/poll(1.5 s)/act (ordered send queue)/list/dep/state/team/leave/board;
                                adoptRoom, owner duties, pid+code+act log persisted in user://, desync alarm, backoff
    server.gd                   base URL (workers.dev or Settings), bearer token, deep-link parsing
    json_num.gd                 numbers on the wire: ints as ints, inches as "%.2f" of MI/10, dice as ints (never raw JSON.stringify floats)
    dnd_client.gd               R4: /api/auth/guest, /api/auth/pair/claim, /api/me, /api/rooms polling + board ops + dm action
  scenes/
    main.tscn                   root: World (SubViewport with the active table) + UI (ScreenStack) + Overlay (toasts, tray, log)
    battle_table.tscn           TableView + Battle sim + EventPlayer
    probe.tscn                  (exists) kept as the line-up/GPU probe scene
    dnd_table.tscn              R4
  assets/
    kits/                       GENERATED, git-ignored: tools/export_kits.js -> *.glb + kits.json (312 kits, 48 MB)
    kits_import/kit_post_import.gd   EditorScenePostImport: merge surfaces -> COLOR + CUSTOM0, keep skin, LOD (§7)
    impostors/                  GENERATED, git-ignored: <kit>.png (16 yaw x 2 pitch, RGB) + <kit>_m.png (tint mask)
    anim/                       GENERATED, git-ignored: humanoid.res AnimationLibrary baked from SKRIG (§7); creature sets later
    shaders/figure.gdshader     palette + team tint; INSTANCE_CUSTOM for MultiMesh; per-vertex shading define for lo/min
    shaders/table.gdshader      (exists) procedural table top
    fonts/Sarabun-*.ttf + OFL.txt   (exists)
    sfx/*.ogg, music/*.ogg      rendered offline from the page's WebAudio DEF table (tools/bake_sfx.js)
    props/                      flat-coloured prop meshes (ruin walls, columns, trees, rocks, crates) <= 300 tris each
  tools/                        run OUTSIDE Godot unless .gd
    export_kits.js (exists)     page -> kits/*.glb + kits.json (Playwright)
    export_data.js (exists)     page -> data/*.json
    kits.sh                     one command: export kits, bake impostors, bake clips (what CI's kits job runs)
    bake_impostors.gd           headless under xvfb: 16x2 facings per kit -> assets/impostors
    bake_anim.js + bake_anim.gd page SKRIG Controller/poses -> clips JSON -> assets/anim/humanoid.res
    bake_sfx.js                 page SND.probe offline rendering -> assets/sfx/*.ogg
    record_oracle.js            Playwright on window.BT -> tests/oracle/*.json (setup, lists, props, deps, acts, board per act)
    make_golden.gd              seeded bot games -> tests/golden/*.json (setup, roster, acts, digest_after[], final_board)
    gen_bt_data.py              data/ -> bt_data.json for the server PR (datasheets, English army names, ability text)
    validate_data.py            schema, banned names (AGENTS rule 1), Thai->English completeness, TYPES append-only, dice <= 60
    mock_worker.mjs             Node: /api/bt/rooms with the Worker's sanitiser mirrored (CI); real wrangler dev is local only
    perf_scene.gd               400-figure/480-prop/8-team scene; prints draw calls, primitives, VRAM, frame time per level
    godot.sh                    fetch pinned 4.7.1 + templates with sha256 (local + CI)
  tests/
    run.sh [quick|full|<suite>] mirrors tests/run.sh; TEST_OUT; quick on every PR, full nightly
    run_tests.gd (exists)       headless runner; made recursive over tests/unit and tests/golden in R0-A
    testing.gd (exists)         assert_true/false/eq/ne + assert_digest, assert_within
    unit/test_*.gd              one file per core module (§10)
    golden/*.json + test_golden.gd
    oracle/*.json + test_oracle.gd
    net/test_net_sync.gd        two headless instances through mock_worker.mjs
    render/run_render.gd        entry for xvfb runs: test_budgets, test_screens, test_lineup, test_anim_footslide, baselines/*.png
    selftest.gd                 what the exported exe runs on windows-latest (--headless -s res://tests/selftest.gd)
docs/GODOT.md                   the agents' code map for godot/ (anchors, invariants, ownership), kept like CODEMAP.md
.github/workflows/godot.yml     (exists) extended in R0-C (§11)
```

Ownership tracks for parallel agents (one PR touches one track plus its tests): `core/field`, `core/battle/{combat,pend,
strats,abilities}`, `core/battle/{turn,acts,bot,board}`, `table/figures`, `table/{terrain,props,camera,fx,dice}`, `ui/`,
`net/`, `tools/`+`tests/`+CI, `core/dnd`, `table/board3d`.

## 2. Language: GDScript 2, statically typed, no C#

- Every file: typed variables (`var x: int`, `:=`), typed arguments and return types, `class_name` for shared classes.
  `@warning_ignore` is never used to hide a type error.
- Why not C#: Android C# export needs the .NET SDK and the Mono templates on every runner and agent machine (none is
  installed here), bigger APK, slower cold start on 2 GB phones. Per-frame work is done by engine nodes in C++
  (Skeleton3D, MultiMesh, AnimationPlayer); rules run per act, not per frame. GDScript headless starts in ~0.3 s, which is
  the whole test harness.
- GDScript facts the core relies on (verified in 4.7.1): `int` is int64 everywhere and wraps silently; `/` on ints
  truncates toward zero (use `Fx.idiv` for floor); `%` keeps the dividend's sign (use `Fx.imod`); hex literals above
  int64 max fail to parse (write PCG constants as signed decimals); `Dictionary` keeps insertion order (V8 fronts
  integer-like keys — never rely on either: iterate explicit Arrays); `Array.sort_custom` is unstable (use
  `Fx.stable_sort`, index tie-break); `round(-2.5)` is -3 while JS gives -2 (use `Fx.js_round`); `"%.2f" % 0.125` prints
  0.12 where JS `toFixed(2)` gives 0.13 (never format rules numbers with printf; `Fx.to_fixed_*` works on ints).
- Core purity, enforced by `tests/unit/test_core_purity.gd` scanning `godot/core/**`: forbidden tokens `float`,
  a literal with a decimal point, `Vector2`, `Vector3`, `Transform`, `sin(`, `cos(`, `atan2(`, `sqrt(`, `pow(`, `lerp(`,
  `randf`, `randi`, `randomize`, `Time.`, `OS.`, `Engine.`, `Node`, `get_tree`, `await`, `signal`. Allowed types: `int`,
  `bool`, `String`, typed `Array`, `Dictionary`, `PackedInt64Array`, `PackedInt32Array`, `PackedStringArray`.
- Native code: only as a measured escape hatch (GDExtension for impostor packing or mesh merging at load time), never
  for rules. Node tooling (`tools/*.js`) stays for everything that must read the old page.

## 3. Scenes and data flow

One-way flow: **core (RefCounted) → events → table/ui (Nodes)**. Nodes never write core state. Every change — local tap,
bot, remote act — is an `Act` applied through `core/battle/acts.gd` exactly as a remote act would be, so offline and
online are one code path and tests capture acts like `BT.capture`.

- Autoloads: `App` (settings + router), `I18n`, `Audio`, `Log`, `Clock`, `Net` (room client host node). Nothing else is
  global. Settings live in `user://settings.cfg` (keys `gfx`, `lang`, `snd`, `server`), read/written with error checks;
  the app always renders without them.
- `scenes/main.tscn`: `World` (SubViewport holding the active table scene) + `UI` (ScreenStack: one screen Control at a
  time: setup, army, lobby, deploy, play_hud, spectator, custom, settings, preview, gpu_check; R4 adds dnd_camp,
  dnd_table, dm_panel) + `Overlay` (toasts, dice tray, log). The 3D table persists across setup → army → deploy → play.
- `scenes/battle_table.tscn` = `TableView` with children CameraRig, Sun (DirectionalLight3D; shadows only on hi/mid),
  WorldEnvironment (flat sky colour per theme; no glow/SSAO/fog), TerrainMesh, PropsLayer, Figures (FigurePool), Rings,
  Fx, Objectives, Picking. It owns one `Battle` (core) and one `EventPlayer`.
- `EventPlayer`: `apply(act)` returns `Array[Event]`; the player schedules visuals (walk, tray throw, tracer, flinch,
  death) and never blocks the sim. In headless runs it is a no-op sink, so bot games finish in seconds.
- Typed events (`core/events.gd`): `squad_ordered(id, path[])`, `move_step`, `attack_stage(P, stage, dice[])`,
  `dice_requested(roller, kind, n)`, `hit/wound/save`, `damage(uid, hp)`, `death(uid)`, `fallen`, `shock`, `charge`,
  `heal`, `rez`, `phase(ph)`, `turn(team, round)`, `objective(i, owner)`, `log_line(key, args[])`, `strat(k)`,
  `desync(seq, local_digest, remote_digest)`, `over(result)`.
- Figure instance (`figure.tscn`): Node3D → Skeleton3D (23 joints from the glb) → MeshInstance3D (merged surface, team
  material) → AnimationPlayer with the shared humanoid library and an AnimationTree (idle/walk/run blend by speed;
  actions as one-shots) → Walker. Rigid-tier figures are not nodes: entries in a per-kit MultiMesh with
  INSTANCE_CUSTOM (team colour, flags). Far-tier figures are entries in one impostor MultiMesh. `FigurePool` re-tiers
  every ~0.25 s from on-screen height and camera distance with hysteresis and per-level caps.
- Frame loop: `_process` only advances walkers, tray and fx. `OS.low_processor_usage_mode = true` whenever nothing
  animates, so idle screens do not redraw; `Engine.max_fps` 30 on min/lo, 60 on mid/hi.
- Test hook (`app/selftest.gd` + `tests/testing.gd`): the same verbs as `window.BT` where they make sense (seed, size,
  setList, start, move, shootAt with fixed dice, board, capture, applyAct, botStep, tick) so suites read like today's.
- R4: `scenes/dnd_table.tscn` reuses CameraRig, FigurePool (tokens with name plates and HP bars), Rings and adds
  `board3d` (tile builder from layout JSON, fog of war, lights) and the DM panel. Nothing battle-specific lives in
  `table/` shared parts.

## 4. Rules core, rules version 10

Goal: same setup + same roster + same ordered acts ⇒ bit-identical state on ARM32, ARM64 and x86-64, proven by digests.

**Numbers.** All rules quantities are int64 in MI (milli-inches, 1" = 1000). Table 180" max ⇒ coordinates ≤ 180,000,
squared distances ≤ 6.5e10. `dist = isqrt(dx*dx + dz*dz)` (Newton); range checks compare squared distances where
possible, else `d <= R + 1` MI (the page's `+0.05"` tolerance is dropped; documented as an intentional difference).
Wire points keep the page's format (inches, 2 decimals): `MI/10` both ways, exact. `board_state()` rounds to 0.1"
with `js_round` (floor(x + 50) / 100 on ints = JS `Math.round` semantics). Table depth `d = ((w*36+50)/100)*2` equals
the server's `Math.round(w*0.72/2)*2` for every w in 24..180 (no ties possible).

**No trig.** Facing = integer direction vector normalised to length 1000 by isqrt; formation slots use (fx, fz) and the
perpendicular (fz, -fx), gaps/rows in MI, results rounded to 10 MI (0.01"). Search rings (`freeSpot` 14 directions x
10 rings, `planMove` 10 x 6) are literal integer offset tables in `core/field/offsets.gd`, generated once by a script
and committed with a test that re-derives them. The desert dune sine uses a 1024-entry integer table. Division only
through `Fx.idiv`.

**Noise and field.** `ihash2/ihash3` are v10's own 32-bit integer mixers (xorshift-multiply, masked), *not* the page's
`hash2` (which V8 evaluates with a double-rounded product beyond 2^53). `fade/lerp/vnoise/fbm` in Q16.16; heights in
MI. Terrain, props (STRUCT kinds, PROP_CAP 480, levelUnder), objectives and deployment zones are functions of the setup
only (seed 1..99999, theme, terrain, buildings, density, w). Rules never read `heightAt`; it is visual.

**RNG.** `core/rng.gd` is PCG32 (64-bit state, 32-bit outputs masked; constants as signed decimals). One stream per
purpose, seeded from `setup.seed` and the stream name: `terrain`, `props`, `objectives`, `armies`, `deploy`,
`bot:<seat>`, `fallback:<seq>:<stage>`. Adding a consumer to one stream never shifts another. `d6()` = `1 +
bounded(6)` with rejection sampling.

**Dice.** Real dice are drawn on exactly one device — the roller; the owner for bots, Claude seats and timeouts — and
travel in the act. Receivers never roll. The Worker cuts dice arrays to 60: any die beyond the first 60 of a stage
comes from the `fallback:<seq>:<stage>` stream on every device *including the roller*, so arrays are never longer than
60 and devices agree. A short array from a buggy sender raises a `desync`-class log event and is padded from the same
fallback stream (deterministic; the game continues; the log shows it). Visual randomness (particles, sway, tumble
variants) uses Godot's RNG and never touches core.

**Order.** Units and squads are Arrays in creation order; ids are the page's `<player>:<i>` and `<squad>.<j>` strings;
every "nearest/best" choice breaks ties by index; `advance()` runs after every applied act on every device. Porting a JS
`for…in` over an object: write the explicit order you chose and a comment; a JS `sort` site becomes `Fx.stable_sort`.

**Table base and act log.** `Table.new(setup, roster, bots)` then `apply(act)` per act in seq order is the only way
state changes. `apply` returns `Array[Event]`; `advance()` follows. `snapshot()` is canonical JSON; `digest()` is FNV-1a
64 over a canonical PackedInt64Array (turn, round, phase, over, vp[], cp[], objectives, units sorted by id with
hp/gx/gz/flags, squads with flags, pend summary). The act log is persisted in `user://rooms/<code>.json` so a killed app
rejoins its seat and replays; past `BT_MAX_ACTS` (500) it resyncs from the owner's snapshot (§5).

**Abilities registry.** `core/battle/abilities.gd` maps every type flag and weapon keyword from `data/README.md`
(aura, rez, wind, spawn, heel, heal, ttn, vsh, gk, hd, pact, pain, ca, aoc, st, ac, brave, hero, fly, veh, ch; rf, as,
pi, hv, su, tr, lh, dw, bl, po, mk, la) to a handler with one unit test per flag. Army-wide rules stay code hooks
(`el` shoots after advancing, `de` painOn from round 3, `cx` pactOn, `ta` designators, `kn` chapters).

**Data.** `data/*.json` from `tools/export_data.js` is the source of truth; `types.json` array order is the protocol
(append-only, linted). `core/data.gd` loads it once into typed arrays. Hidden units: `sec` / `lk` are carried as opaque
fields; their budget, slot and roster behaviour is ported in code only; how they are unlocked is never written in
notes, tests, comments or PRs.

**Intentional v10 differences from v9** (listed in `docs/GODOT.md` and the oracle allowlist): integer formation and
search offsets rounded to 0.01"; fixed-point noise (new terrain and prop shapes per seed); `+1 MI` instead of `+0.05"`
range tolerance; the dice fallback rule; no other maths change. Datasheets, points, phases, stratagems, caps and the
act protocol are identical.

**Performance.** Rules run per act. `planMove`'s slot search is bounded as today; bots do one action per `botStep`;
a uniform spatial grid may wrap `blockAt`/`nearFoe` predicates but never changes candidate order. Measured in R1 with
a time-budget test: a 20-model squad move < 150 ms on a 500-model field, headless x86 (phone factor measured on device).

## 5. Netcode against the existing Worker

The client speaks the Worker's `/api/bt/rooms` protocol byte-for-byte, adding nothing but the version number.

- Endpoints (unchanged): `POST /api/bt/rooms` {nm, setup: curSetup()} → {code, pid, room}; `POST /:code/join` {nm, v}
  (409 on version mismatch, full or started); `GET /:code?since=<seq>&pid=` every 1.5 s with one request in flight →
  {code, state, setup, ownerPid, players[{pid, nm, team, list, dep, sk, bot, ai, gone, owner}], seq, board, acts[]};
  `POST /:code/act` {pid, act}; `/list` {list, sk}; `/dep`; `/team`; `/state` (owner: roster + bots); `/leave`;
  `/board` (owner: `board_state()`, so Claude's `bt_look` keeps working).
- Act codes and fields exactly as the Worker allowlist: `smove stay skip adv atk wnd sav rr shoot shock rez chg ow chr
  cmove gren heal done endph`, server-made `owner state join leave team setup list dep`. Caps mirrored client-side:
  60 dice, 40 points, ids ≤ 20 chars, list ≤ 512 slots, 99 per slot, board ≤ 600 units / 300 squads at 0.1".
- `net/room_client.gd`: ordered send queue (one POST in flight; hit must reach the room before wound); on each poll apply
  acts with `seq > local seq`, skip own `pid`, `Battle.apply` → `advance()`, then `adoptRoom` (the room is the truth:
  setup and seats overwrite local; empty or `gone` seats become bots; the owner builds bot armies and deployment and
  sends `/state`). Owner duties: run bots, clock timeouts (`endph`), roll for silent players after 25 s (OWNER_WAIT),
  post `board` each turn. `owner` act hands duties over (server failover after `BT_GONE_MS` 75 s).
- Numbers on the wire (`net/json_num.gd`): ints as ints, inches as `"%.2f"` of `MI/10`, dice as ints; never a raw
  `JSON.stringify` of a float (Godot prints 0.1+0.2 as "0.3" and 12.0 as "12.0").
- Resync: the owner's `/board` carries `digest` and a compact `snap` (≤ 64 KB) each turn (server PR); a device whose
  digest differs after a turn shows "เครื่องนี้เห็นไม่ตรงกับห้อง" with the first differing unit in the log and reloads
  from `snap`. A late joiner past 500 acts loads `snap` instead of replaying. The desync alarm is also the cross-client
  test oracle.
- Version gate: `core/version.gd RULES_V = 10` travels in `curSetup().v`, the join body and `board_state().v`. Today
  `btVer` maps anything above `BT_RULES = 9` to 1 and refuses it, so the **server PR comes first**: `BT_RULES = 10`,
  `btVer` accepts 2..10, v9 rooms stay joinable by v9 pages (rooms remember their version; the existing Thai 409 message
  tells old clients). A CI test asserts `RULES_V` equals the `BT_RULES` recorded in `data/version.json` (the snapshot is
  refreshed from `../candlelight-server` locally by `tools/gen_bt_data.py --snapshot`).
- Can a v9 page and the v10 app share a room? **No, by design.** v9 computes bot armies, formations, nearest-victim
  order and terrain in V8 double arithmetic with `Math.sin/cos/atan2/hypot/toFixed` (sin arguments up to ~4.8e7 need
  Payne–Hanek reduction to match); the gate keeps rooms apart cleanly and the old app keeps shipping at v9.
- Claude as a player: unchanged. `bt_sit` joins with the room's version; `bt_look` reads the owner's `board`; `bt_move`
  sends x,z and every device's integer `planMove` resolves identical slots; `bt_shoot` sends `atk` with hit dice; the
  server's 0.5" tolerance on the 0.1" board still holds.
- Server PRs (small, merge server first, order written in both PRs): R3-S1 `BT_RULES = 10`, `btVer` range, `btBoard`
  accepts `digest` (≤ 32 chars) and `snap` (≤ 64 KB), `BT2` for v ≥ 10 replaced by `bt_data.json` generated by
  `tools/gen_bt_data.py` (shipped as a file in the PR, no cross-repo CI write), a "เปิดในแอปใหม่" button in `app.html`
  with deep link `candlelight://bt/<CODE>`. R4-S1: `board.map {seed, kind, ver, edits[]}` on D&D rooms, token clamp by
  layout size (today `clampPos(±20)`), a text summary of the map in `read_room`. R6-S1: a generic act-log room kind for
  co-op roguelike.
- Offline: the identical code path with `Net` disabled; bots and dice local; the app starts and plays with no network.

## 6. Rendering

Renderer: `gl_compatibility` on every platform (OpenGL 3.3 desktop / GLES 3.0 mobile; verified under xvfb + Mesa
llvmpipe here). Forward+ and Mobile need Vulkan, which cheap phones and the owner's old PC may not have. The Windows
preset enables `rendering/gl_compatibility/fallback_to_angle = true` and the release zip ships a Mesa software
`opengl32.dll` folder with a Thai README as plan C.

Per-level budgets, asserted by `tests/render/test_budgets.gd` on a 400-figure / 480-prop / 8-team scene from
`RenderingServer.get_rendering_info` (deterministic on llvmpipe):

| Level | draw calls | triangles | render scale | fps cap | shadows | skinned cap | MSAA | particles |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| min (potato) | ≤ 120 | ≤ 250k | 0.6, window ≤ 1280x720 | 30 | none; blob quads | selected squad + ≤ 8 walkers | off | ≤ 32 CPU total |
| lo | ≤ 200 | ≤ 400k | 0.75 | 30 | none; blob quads | 24 | off | CPU, capped |
| mid | ≤ 350 | ≤ 800k | 1.0 | 60 | 1024 directional, near casters | 80 | off | GPU |
| hi | ≤ 600 | ≤ 1.5M | 1.0 | 60 | 2048 | 160 | 2x optional | GPU |

- min additionally: per-vertex shading (shader define), no fog/glow/SSAO (compat has none), impostors from close range,
  terrain grid step 4, simplified props, destination rings only for the selection, redraw only when something moves,
  `low_processor_usage_mode` on. **Nothing per-frame is added to min, ever** (AGENTS rule 6); the budget test is the
  enforcement.
- First run guesses from `OS.get_memory_info().physical` (≤ 2 GB min, ≤ 4 GB lo, else mid) plus a 2-second startup
  benchmark; `adaptScale` lowers `scaling_3d_scale` on frame time > 40 ms; `slowStep` drops the level once after a long
  run of slow frames, never up — the page's behaviour.
- Why tiers are mandatory: 400 figures x median 11 materials = 4,400 draw calls naively; 400 skinned x ~3,200 vertices
  = 1.3M skinned vertices per frame. So: (1) import merges each kit into one surface; (2) near tier: skinned
  MeshInstance3D, one draw call each, one shared material (a duplicate only for a repainted figure); (3) mid tier:
  per-kit MultiMeshInstance3D of rigid figures in idle pose, INSTANCE_CUSTOM.x = paint-job row (30 kit types in play =
  30 draw calls for hundreds of figures);
  (4) far tier: one MultiMesh of billboards from a per-battle atlas built at battle start from the baked impostor strips
  = 1 draw call. Walking squads are promoted to skinned (capped) or slid rigidly.
- Terrain: one ArrayMesh (~42x30 cells, ~2.5k tris, vertex colours, no textures) + rails; props as MultiMesh per kind
  (~8 draw calls); blob shadows as one MultiMesh of dark quads. Sky: flat gradient; skyline quad on mid/hi.
- **Team rings** (owner decision 7 Oct): a figure is never dyed in its team colour; the team shows as a coloured ring on
  the ground under every figure (`table/rings.gd`, one MultiMesh of flat ring quads per table, one draw call on every
  level, team RGB from `teams.json`). Selection, destination and objective rings reuse the same MultiMesh with other
  colours and radii. Figures keep their own painted colours so armies look like painted collections.
- Owner's phone (7 Oct, probe build): Android, Mali-G52 MC2, 2400x1080, 12 skinned figures with 2048 shadows at full
  resolution = 21 fps. It is a `lo` device: render scale 0.75, no shadow map. The GPU-check screen measures this and picks
  the level; hi stays opt-in on phones.
- Memory: flat colours, one ≤ 2048 impostor atlas (≤ 16 MB VRAM), fonts; kits loaded lazily per battle (~100 KB each);
  targets < 350 MB RSS on Android, < 500 MB on a 2 GB PC; APK < 90 MB (CI fails above 120 MB).
- Battery: fps caps, idle = no redraw, polls only in a room, screen on only during play.
- Measurement: `tools/perf_scene.gd` prints counters per level in CI (artifact); the in-app GPU-check screen shows
  adapter, GL version, draw calls, fps, memory, so the owner screenshots numbers from the old PC and the phones.

## 7. Assets, paint shader, animation

**Kit contract** (`tools/export_kits.js`, PR #27; `assets/kits/CONTRACT.md` restates it): one `.glb` per kit key,
metres, +Y up, faces +Z, flat shading, scale baked into the mesh (instantiate at scale 1; `baseR` from `kits.json` for
spacing), one material per palette key with `extras.tint` (NATURAL keys false), 23-joint SKRIG skeleton for the 260
skinned kits (joint names = `SKRIG.J`; local quaternions = SKRIG local pose), mounts with the rider's seated skeleton and
the mount body under the pelvis. **52 kits have zero joints** (all vehicles, titans and 50 of 51 creatures): they get
whole-mesh procedural motion (bob, hover from `fly.json`, stomp) until creature rigs arrive with the bestiary (R5).
`tests/render/test_lineup.gd` loads every kit, fails on a missing joint, a stray material, a missing tint flag or a bad
scale, and renders one line-up per army.

**Import** (`assets/kits_import/kit_post_import.gd`, EditorScenePostImport, shared `.import` preset): merge all
surfaces into one ArrayMesh surface with `COLOR` = linear palette colour, `CUSTOM0` = (tint flag, palette index, 0, 0),
indexed where face normals agree, skin kept; a second LOD exported from the page at `LODK 0.45` (the exporter already
calls `M.build(kit, Wd, lod)`), importer LOD generation for one more. The NATURAL list comes from `kits.json`.

**Paint shader** (`assets/shaders/figure.gdshader`; the page's `teamTint` dye is NOT ported — team colour is the ring of
§6): base colour = `COLOR`; an optional paint table `uniform sampler2D paint_tex` (one row per paint job, column =
palette index, ≤ 16 columns, nearest filtering, `texelFetch`) overrides the colour of slot `CUSTOM0.g`; the row comes
from `INSTANCE_CUSTOM.x` (MultiMesh tiers) or a `paint_row` uniform on a duplicated material (skinned tier); row < 0 =
kit colours. `CUSTOM0.r` (the old tint flag) now only says which slots the painter offers first (armour and cloth; skin,
wood and metal are marked natural). `#if` define for per-vertex shading on lo/min; skins/variants via the palette index.
This is the foundation of the owner's **model painter and collection** (R7): a paint job is a per-kit list of ≤ 16 RGBs
stored in `user://paint/<kit>.json` and sent with the army list as plain ints, so other screens show your paint.

**Impostors** (`tools/bake_impostors.gd`, headless under xvfb, ~2 min for 312 kits): 16 yaw x 2 pitch per kit into
`assets/impostors/<kit>.png` (RGB) + `<kit>_m.png` (tint mask R8); generated with the kits in CI, cached by the same key.

**Animation plan** (owner wish 2, natural motion):
1. Base for all tiers (R2): bake clips from the page's proven SKRIG gait generator. `tools/bake_anim.js` runs the page
   in Playwright like `export_kits.js` (or the `// ==MODULES-BEGIN==`…`END==` slice as `web/harness.js` does), drives
   `SKRIG.Controller`, `idlePose` and the attack poses and samples local joint quaternions at 30 Hz: idle (breathing
   sway), walk, run (advance), turn-in-place, aim+fire, draw+shoot (bow), throw, thrust, swing, brace/shield, flinch,
   two deaths, mounted seat. `tools/bake_anim.gd` writes one `AnimationLibrary` (`assets/anim/humanoid.res`) shared by
   all 260 skinned kits (same joint names, same convention; no retargeting). Runtime: AnimationPlayer/AnimationTree in
   C++, blend idle/walk/run by actual speed (no sliding), actions as one-shots on tray events (throw start / settle).
   **First bake one humanoid walk + one horse + one walker and measure foot slide before baking the library** (the
   page's harness measured 0 mm; `tests/render/test_anim_footslide.gd` allows ≤ 15 mm at Walker speed).
2. Near-figure polish on mid/hi (R6): `SkeletonIK3D`/`IKModifier3D` foot pins on slopes and `LookAtModifier3D` heads for
   ≤ 8 figures nearest the camera; a live GDScript port of the Controller only if the clips visibly fail on turns.
3. Not chosen: procedural IK for every figure (too slow on potato), hand-authored clips (no animator), VAT (not needed).

**Dice**: a d6 mesh + 24 baked tumble clips (6 faces x 4 variants) generated once from `web/dice-core.js` replays;
chosen by `seedOf(attacker, target, round, turn, stage)` so every screen shows the same tumble; no runtime physics.
**Props**: flat-coloured composites ≤ 300 tris in `assets/props/`. **Fonts**: Sarabun (exists). **Audio**: a handful of
small OGG effects and three music loops rendered offline from the page's `SND` definitions (`SND.probe`), no runtime
synthesis. **Size**: kits ~100 KB imported each, loaded lazily.

## 8. UI and i18n

- Thai is the source language and the key. `I18n.t(th)` looks up `data/i18n_en.json` (1,554 pairs exported from the
  page) then `ui/i18n_extra.json` (strings that exist only in the new app); whole string first, then fragments longest
  key first; if any Thai is left the whole string stays Thai (the page's `tr()` rule). Typed text and player names are
  never translated. Core emits message keys + args; the UI formats them, so `core/` holds no UI text.
- `App.lang` persisted (same meaning as the web app's `cl_lang`); switching re-applies without restart.
- Two CI tests mirror `tests/battle/english.js`: static (`tests/unit/test_i18n.gd`: every Thai literal in `.gd/.tscn/
  .json` under `ui/`, `table/`, `app/`, `core/` message keys has an English entry with no Thai left) and runtime
  (`tests/render/test_screens.gd`: every screen in English through a whole bot game; any `Label/Button/RichTextLabel/
  Tooltip` text containing U+0E00–U+0E7F fails; typed names exempt).
- Layout: landscape (`sensor_landscape`), base canvas 1280x720 with `canvas_items` stretch and `expand` aspect; 16 px
  gutters; ≥ 44 px touch targets; safe-area insets from `DisplayServer.get_display_safe_area()`; the two-column desktop
  layout above 900x560 like the page; a layout test instantiates every screen at 640x360, 960x540, 1280x800, 2560x1080
  and asserts no Control overflows its parent or overlaps the HUD.
- Screens: the page's six panels plus settings — setup (theme, size, seed, terrain, buildings/density, mode pve/pvp/
  team/ffa/custom/spectator, team sizes, budget, goal, rounds, free fire, clock, name/host/join), army (budget bar,
  army picker, roster with datasheets, random, preview turntable), lobby (room card, seats, leave, start), deploy (tap a
  point, auto, all), play HUD (turn bar with phase and clock, squad card, phase actions, group move, end phase, dice tray
  manual/auto, log, quit; spectator speed/pause/step/again), custom sandbox, settings (gfx with live counters, sound/
  music, language, server URL, GPU check, copy log). Hidden units are filtered from the roster, as today.
- Input: `InputMap` actions shared by touch and mouse. Touch: tap select/target, drag pan, pinch zoom, two-finger twist
  orbit, long-press datasheet. Mouse: left select, right-drag orbit, wheel zoom, WASD pan. Picking unprojects into the
  heightfield in float and converts to MI ints before building an act; the destination ring previews the integer
  `planMove` result before confirming.
- UI performance: no per-frame redraw of Controls (update on events), no `_process` in widgets except the clock label
  once a second, log capped at 200 lines, no shaders on Controls on lo/min.

## 9. The D&D side (R4–R5), on the same spine

Foundations laid cheaply in R0–R1 and never built on before R3 is green: the `Table` base, the int grid with A* and
line of sight (`core/field` helpers), RNG streams, `data/schema/map_layout.json`, the DM-act vocabulary (a doc +
schema: `dm.narrate`, `dm.scene`, `dm.place`, `dm.move`, `dm.remove`, `dm.combat_start/next/end`, `dm.roll_ask`,
`dm.hp`, `dm.reveal`), the Figure "token" mode (name plate, HP bar, ring), fog of war in the terrain shader, the shared
camera rig.

**R4 — human DM table** on the existing server: `net/dnd_client.gd` talks to `/api/rooms` exactly as `app.html` does
(create with era/event/difficulty, join, poll since seq, act/roll/hp/move/look/leave/reroll/ready) and to the existing
`dm` action (owner only, room created with `setup.dm = "host"`; tools narrate, set_scene, start_combat, next_turn,
end_combat, place_token, move_token, remove_token). Login: `/api/auth/guest` and the pairing flow (`pair/start` on the
web or old app → `pair/claim` in the new app); Google sign-in later via a native plugin, never a web view. The Godot
`board3d` renders the same board JSON (scene, time, tokens with look, mode, combat {order, turn}) that `board.html`
renders, so Claude-as-DM via MCP works on day one and can co-DM. Screens: campfire lobby, character sheet/creator
(reusing the board's look data), board view (tokens as figures, tap-to-move within 6 units on your turn, shared dice),
DM dashboard tabs — Story (narrate, quick prompts), Board (place/move/remove with a tap-the-floor mode, scene/time
picker, fog brush, light radius), Fight (initiative, next turn, HP taps, conditions), Map (generate: seed/size/biome/
difficulty, regenerate room, stamp prefabs, save/load layout), Players (sheets, inventory, rest). Every DM action is an
act so it replays and logs; undo is a reverse act.

**Generated maps** (wish 4, R4 second half): `core/dnd/mapgen/` emits layout JSON `{v, seed, kind, size:[w,h], cells
(RLE tile ids: floor/wall/water/pit/door/stairs), heights, rooms[{id, kind, rect, tags}], corridors[], doors[],
props[{k, x, z, rot}], lights[], spawns[{kind, x, z, group}], exits[], labels[], edits[]}` from integer generators:
dungeon (BSP rooms + corridors + loops), cave (cellular automata), ruins/town (grid with yards), wilderness (noise +
rivers/paths). Connectivity, min spawn distance and door placement are tested on 200 seeds in CI. The server stores
only `board.map = {seed, kind, ver, edits[]}`; every device regenerates the same map and applies DM edits as deltas; a
PNG minimap is rendered for the DM panel and a text summary for Claude's `read_room` (R4-S1). Rendering uses tile
MultiMeshes (≤ 12 draw calls), potato-safe. Scenes from the page's `SCENES` (tavern, forest, cave, ruins…) become
prefab sets, so "set_scene forest" from Claude yields a generated forest.

**R5 — roguelike / hardcore survival** (wishes 5–6): `core/dnd/` rules on the `Table` base — characters with mundane
occupations as mechanics, meters (hunger, thirst, fatigue, sanity, light) from `data/dnd/survival.json` thresholds,
limb injuries, permadeath and corpse runs, brutal checks, status effects as registry handlers, inventory and loot
tables, rest/camp events, depth/era escalation, difficulty presets (ง่าย/กลาง/ยาก) feeding generator and encounter
tables; a run = seed + chain of layouts, saved as an act-log checkpoint so bugs replay from seed + log. Bestiary as
datasheet-like JSON mapped to kits (the swarm, daemons, legends and creature armies give ~60 monster figures via palette,
scale and part swaps before any new model); monster behaviours as data-driven AI profiles (ambusher, stalker, brute,
swarm, caster) through the `bot.gd` pattern; a quadruped/creature skeleton and clip set for new monsters. Solo/offline
first; co-op later via the generic act-log room kind (R6). Content design is done with the owner (and GPT) before
implementation; the architecture needs no change for it.

## 10. Testing

Everything runs without a human and without a GPU. `bash godot/tests/run.sh [quick|full|<suite>]` mirrors `tests/run.sh`
(quick on every PR, full nightly / on demand, `TEST_OUT`). A failing test is a bug to fix, never a test to delete,
skip or loosen; agents add a test for what they build.

1. **Unit** (headless, seconds): `godot --headless --path godot -s tests/run_tests.gd [-- <filter>]` discovers
   `tests/unit/test_*.gd` and `tests/golden/test_golden.gd`. Suites: `test_fx` (isqrt, idiv, imod, dist, js_round,
   to_fixed vs node-generated vectors), `test_rng` (PCG32 known-answer vectors, d6 histogram, stream independence),
   `test_hash`, `test_noise_field` (fixed heights per seed, props identical across two Field instances, blockAt/
   freeSpot, offsets re-derived), `test_army`, `test_combat`, `test_abilities` (one per flag), `test_pend`,
   `test_strats`, `test_turn`, `test_moves`, `test_acts` (JSON round trip = Worker allowlist, caps), `test_board`,
   `test_bot`, `test_data` (types.json vs the exporter re-run; TYPES order append-only; `RULES_V` vs the server
   snapshot), `test_core_purity`, `test_i18n`, `test_kit_lineup` (exists).
2. **Golden replays**: `tools/make_golden.gd` plays seeded bot games (every army, 2–8 teams, obj and kill goals) and
   writes `tests/golden/<name>.json`; `test_golden.gd` replays act by act and in batches and asserts every digest. Run on
   `ubuntu-latest` (x86-64) and `ubuntu-24.04-arm` (arm64, free for this public repo), and through the exported Windows
   exe on `windows-latest` (`CandlelightTable.exe --headless -s res://tests/selftest.gd`). A rules change regenerates
   goldens in the same PR with the reason and a `RULES_V` bump.
3. **Oracle** (the page as reference): `tools/record_oracle.js` (Playwright, `CHROMIUM_PATH` as `tests/run.sh`) drives
   `window.BT` — `seed`, `size`, `setList`, `setDep`, `start`, `dice([...])`, `clock(false)`, `tick`, `botStep`,
   `capture(true)`, `board()`, `log()` — for ~20 scenarios (all 15 armies, 2–8 teams, obj/kill, hidden units, all 18
   act codes; the act histogram must contain every code) into `tests/oracle/*.json` (setup, lists, skins, `props()`,
   deps, acts, board after every act). `test_oracle.gd` builds the same match in v10 with the page's props and deployment
   injected as fixtures, replays the acts (explicit points and dice travel in them) and compares after every act: hp,
   phase, VP, CP, squad flags and victim order exactly, positions within 0.05"; the first difference is printed like
   `net_sync.js`. Divergences are accepted only through `tests/oracle/allowlist.json` with a reason. Goldens are
   re-recorded only when the page's `APP_VER` stamp in the file changes.
4. **Bot smoke**: `test_smoke_bots.gd` runs 30 full headless games (all 15 armies, random seeds) in < 2 min: every game
   ends, no squad exceeds its move, no negative hp, dice ≤ 60 per act, acts pass the sanitiser mirror.
5. **Net sync**: `tools/mock_worker.mjs` (Node, bt endpoints with the Worker's sanitiser mirrored; also runnable against
   `wrangler dev` of `../candlelight-server` locally) + `tests/net/test_net_sync.gd` launches two headless Godot
   instances (owner plays bots, joiner polls), compares digests after every batch; plus dropped-owner failover and a
   late-joiner resync from `snap`.
6. **Render** (xvfb + llvmpipe): `test_budgets.gd` (the §6 table), `test_screens.gd` (every screen, Thai and English, four
   resolutions, overflow/overlap, baselines with a perceptual tolerance; baselines are produced by the same llvmpipe in
   CI and regenerated only as an explicit PR step), `test_lineup.gd` (every army's kits in a row; an ID-colour pass
   counts visible figures and rings), `test_anim_footslide.gd`.
7. **Export smoke**: the Windows exe runs `--headless -s res://tests/selftest.gd` on `windows-latest`; the APK is checked
   with `aapt dump badging` (id, abis, permissions, size gate).
8. **Data lint** (Python, no Godot): `tools/validate_data.py` — schema, banned names (AGENTS rule 1) over `godot/`,
   Thai→English completeness, TYPES append-only vs the previous commit, dice per roll ≤ 60, `bt_data.json` in sync.
9. **Owner checks**: the Selftest screen (replay digests + fps on min) and a five-line Thai checklist in each release note.

## 11. CI and exports

`.github/workflows/godot.yml` (exists; extended in R0-C), `paths` filter on `godot/**`, concurrency per ref, 60-minute
caps. `build.yml`/`tests.yml` untouched.

- `kits`: Node 22 + Playwright Chromium; `bash godot/tools/kits.sh` exports kits, bakes impostors (xvfb) and clips;
  cached with `actions/cache` keyed by `sha256(app/src/main/assets/battle-table.html, godot/tools/*)`; uploaded as the
  `godot-kits` artifact (kits, impostors, anim) for the other jobs.
- `test` (ubuntu-latest): Godot 4.7.1 binary cached by version; `--import`; unit + golden + smoke + net (mock worker)
  + data lint; `xvfb-run -a -s "-screen 0 1280x720x24" godot --path godot --rendering-driver opengl3 --resolution
  1280x720 --audio-driver Dummy -s tests/render/run_render.gd`; uploads `TEST_OUT` (logs, PNGs, perf counters).
- `test-arm` (ubuntu-24.04-arm): import + unit + golden (the cross-architecture determinism proof).
- `windows` (ubuntu-latest, cross-export): `--export-release "Windows Desktop"`, zipped with the ANGLE/Mesa fallback
  folder and a Thai README; `windows-smoke` (windows-latest) downloads it and runs the selftest.
- `android` (ubuntu-latest): JDK 17, SDK platform 34 / build-tools 34.0.0 (as today), prebuilt templates (no Gradle);
  PR → `--export-debug` with the throwaway debug keystore made in the job; `main`/manual → `--export-release` signed
  through `GODOT_ANDROID_KEYSTORE_RELEASE_PATH` (from the existing `KEYSTORE_BASE64` decoded into `$RUNNER_TEMP`),
  `_USER` = `KEY_ALIAS`, `_PASSWORD` = `KEYSTORE_PASSWORD` — the secrets `build.yml` already uses; no new secret.
  `version/code` from `github.run_number`; `aapt` sanity + size gate.
- `release` (push to main / manual): `softprops/action-gh-release@v2` with `tag_name: build-${{ github.run_number }}`
  attaches `candlelight-table-godot-<run>.apk` and `-windows.zip` to the same release `build.yml` creates, so the owner
  finds old and new builds in one place.
- `export_presets.cfg` is committed without passwords; a CI grep fails on any `keystore/release=` value or `.jks` file;
  the keystore is written to `$RUNNER_TEMP` and deleted at job end; logs mask the env vars.
- Godot is pinned in one place (`GODOT_VERSION: '4.7.1'`); an engine upgrade is a dedicated PR that regenerates render
  baselines.

## 12. Coding conventions for agents

- **Files**: `snake_case.gd`, `snake_case.tscn/.tres`; `class_name` in PascalCase; one class per file; core classes
  `extends RefCounted`; scripts next to their scene. Commit the `.import` and `.uid` files Godot writes; `.godot/`,
  `tests/out/`, `assets/kits/`, `assets/impostors/`, `assets/anim/*.res` are git-ignored.
- **Comments**: short, in Thai, like the rest of the repo (`## ` doc comments on public functions); English is fine in
  tests, tools and docs.
- **Tests live in** `godot/tests/`: `unit/test_<core module>.gd` (one per core module, same name), `golden/`,
  `oracle/`, `net/`, `render/`. A test file `extends "res://tests/testing.gd"` and defines `func test_*()`.
- **Run headless tests** (from the repo root; `GODOT` = the 4.7.1 binary — in this container
  `/tmp/claude-0/-home-user-candlelight-table/14efda3d-1836-580a-86e4-aead22ae2e85/scratchpad/godot/Godot_v4.7.1-stable_linux.x86_64`,
  in CI `~/godot-bin/godot`):
  ```bash
  $GODOT --headless --path godot --import                                   # after a fresh checkout or asset change
  $GODOT --headless --path godot -s tests/run_tests.gd                      # all unit + golden tests
  $GODOT --headless --path godot -s tests/run_tests.gd -- test_combat       # one suite by name fragment
  bash godot/tests/run.sh quick                                             # what CI runs on a PR
  ```
- **Screenshot renders** (xvfb + Mesa, verified in this container):
  ```bash
  timeout 120 xvfb-run -a -s "-screen 0 1280x720x24" $GODOT --path godot --rendering-driver opengl3 \
    --resolution 1280x720 --audio-driver Dummy -s tests/render/run_render.gd [-- test_budgets]
  ```
  PNGs land in `godot/tests/out/`; look at them before claiming a visual change works. ALSA/V-Sync warnings are harmless.
- **Kits and data** (once, deterministic): `cd tests && npm ci && npx playwright install chromium && cd ..`, then
  `CHROMIUM_PATH=$(ls -d /opt/pw-browsers/chromium-*/chrome-linux*/chrome | head -1) bash godot/tools/kits.sh` and
  `node godot/tools/export_data.js`. Never hand-edit `assets/kits/`, `assets/impostors/`, `assets/anim/` or `data/*.json`.
- **Exports**: templates in `~/.local/share/godot/export_templates/4.7.1.stable/` (present in this container);
  `$GODOT --headless --path godot --export-release "Windows Desktop" "$PWD/dist-godot/windows/CandlelightTable.exe"`,
  `--export-debug "Android" "$PWD/dist-godot/android/candlelight-godot-debug.apk"` (needs the SDK paths in
  `~/.config/godot/editor_settings-4.7.tres`; the workflow shows the exact file).
- **Core discipline**: no Node/float/trig/engine RNG/Time in `core/` (the purity test fails the PR); every "nearest"
  tie broken by index; every JS `sort` ported as `Fx.stable_sort`; every ported `for…in` gets its order written out;
  no act field or code beyond the Worker allowlist without a server PR and a `RULES_V` bump; dice ≤ 60 per act.
- **View discipline**: read core, never write it; all per-frame work in `table/`; anything new on min needs a budget
  test proving the draw-call and triangle counts still pass.
- **PR flow** (AGENTS.md): one task → one branch `claude/…` or `codex/…` → one draft PR → watch CI → answer every
  review comment; never push to `main`; list open PRs in both repos first; start from the latest `main`; merge `main`
  into the branch, never rebase. A user-visible change bumps `core/version.gd APP_VER` and adds a Thai note
  `web/สิ่งที่เปลี่ยน-<วัน><เดือน>69-รุ่น<ver>-<หัวข้อสั้น>.md` (topic prefixed แอปใหม่). A rules or data change bumps
  `RULES_V` with the server's `BT_RULES`; the server PR merges first and both descriptions say so.
- **Docs**: `docs/GODOT.md` is the code map for `godot/` (anchors per module, invariants, ownership tracks); update it in
  the same PR as a structural change. Keep `godot/README.md` (Thai) runnable.

## 13. Hard rules from AGENTS.md, restated for `godot/`

1. **No names, iconography, logos or markings from other game companies (the list is AGENTS.md rule 1)** — not in
   file names, kit keys, scene names, strings, comments, tests, commits or PRs. Look-alike units keep their descriptive names from
   `types.json`. Old internal identifiers that carry genre words are not renamed here (renaming a unit key touches the
   server's datasheets, the tests and the army-list protocol); add no new ones. `tools/validate_data.py` scans `godot/`
   in CI.
2. **Secrets never enter the repo, chats, PRs, issues or logs.** `export_presets.cfg` keeps empty keystore fields;
   release signing only through the `GODOT_ANDROID_KEYSTORE_RELEASE_*` env vars fed from GitHub Actions secrets. Never
   ask the owner to paste a key; if a task needs one, stop and name the secret and where it goes.
3. **Hidden units stay hidden.** `sec`/`lk` are opaque fields; the unlock logic is ported in code only and never
   described in notes, PRs, issues, comments, tests or this folder's docs.
4. **Thai is the default.** Every new Thai UI string has an English pair in `ui/i18n_extra.json` (page strings come from
   `data/i18n_en.json`); `tests/render/test_screens.gd` fails if Thai is left on screen in English mode.
5. **Determinism.** `core/` is integer-only, seeded-stream-only, Node-free; no `randi()`, `randf()`, `Time` or `OS` in
   rules; rules positions (`gx`/`gz` in MI) are authoritative; walking x/z are visual. Goldens on x86-64, arm64 and the
   Windows exe check it on every PR.
6. **Weak phones.** The `min` level must stay fast: add nothing per-frame to it; the budget test is the gate.
7. **Edit surgically**: minimal replacements; never reformat, re-indent or re-order `.tscn`/`.tres`/generated JSON; never
   hand-edit generated assets or data.
8. **Comments short and in Thai** in game code; English in tests and docs. Explain results to the owner in plain Thai.
