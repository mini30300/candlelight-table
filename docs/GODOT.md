# Candlelight Table on Godot — code map for agents (`godot/`)

Navigation map of the new Godot 4 app for AI coding agents (OpenAI Codex, Claude) arriving with no context. The
design and its reasons are in `godot/docs/ARCHITECTURE.md`, the milestones and task lists in `godot/docs/PLAN.md`
(R0–R6), the repository rules in `AGENTS.md`, the old pages in `docs/CODEMAP.md`. This file says **where things are**
in `godot/`, who owns which folder, and what must stay true. Update it in the same PR as any structural change
(ARCHITECTURE §12). Mapped at the R0-A layout · Godot **4.7.1** · the new app will speak rules version **10** (the old
page ships v9).

**Anchors, not line numbers.** Every location below is an exact string that occurs once in its file; search with
fixed strings, e.g. `grep -rnF 'func push(' godot/app/`. Scripts are small and typed GDScript 2 (ARCHITECTURE §2);
`.tscn`/`.tres`/`.import`/`.uid` files are written by Godot and are committed: edit them surgically or not at all.

## 1. Layout of `godot/`

What exists now. Folders that ARCHITECTURE §1 plans but no task has created yet are listed in §1.2 with the task that
creates them, so nobody invents a second place for the same thing.

### 1.1 Files in the tree

| Path | What it is | Anchor / entry point | Track |
| --- | --- | --- | --- |
| `project.godot` | Godot 4.7 project: `gl_compatibility` on desktop and mobile, 1280×720 `canvas_items`/`expand`, landscape, Sarabun theme, **autoloads in the order App, I18n, Log, Clock** | `[autoload]` · `run/main_scene` (the probe scene for now; `scenes/main.tscn` from R0-E) | tools/tests |
| `export_presets.cfg` | "Windows Desktop" (x86_64) and "Android" (arm64-v8a + armeabi-v7a, min SDK 24); keystore fields EMPTY on purpose — release signing comes from `GODOT_ANDROID_KEYSTORE_RELEASE_*` env vars in CI | `[preset.0]`, `[preset.1]` | CI (R0-C) |
| `icon.svg`, `README.md` | app icon; the Thai README: setup, tests, render probe, exports | — | tools/tests |
| `app/app.gd` | **`App`** autoload: settings `gfx` (hi/mid/lo/min), `lang` (th/en), `snd`, `server` in `user://settings.cfg` (ConfigFile, section `app`, defaults when the file is missing or corrupt); the ScreenStack router; Android back button | `func load_settings(`, `func save_settings(`, `func set_lang(`, `func push(`, `func pop(`, `func current(`, `func back(` | ui/ (owner), app/ |
| `app/log.gd` | **`Log`** autoload: ring buffer of the last 500 lines, `info/warn/error`, `dump()` for the "copy log" button; `echo = false` silences the console (tests) | `const CAPACITY := 500`, `func dump(` | app/ |
| `app/clock.gd` | **`Clock`** autoload: the one tick source for view timers; `now_ms()`, `frozen`, `step(ms)`; no signal, no per-frame work (computed on read from `Time.get_ticks_msec()`) | `func now_ms(`, `func set_frozen(` | app/ |
| `ui/i18n.gd` | **`I18n`** autoload: Thai keys → English; lookup order `EN` (in the script) → `ui/i18n_extra.json` → `data/i18n_en.json`; `t(th)`, `lookup`, `has_key`, `missing(keys)`; dictionaries load in `_init()` | `const EN`, `func t(`, `func lookup(` | ui/ |
| `ui/i18n_extra.json` | English for Thai strings that exist only in the new app (the `EN` dict's entries are mirrored here; `tests/unit/test_i18n.gd` checks they agree) — every new Thai UI string gets a pair here | — | ui/ |
| `ui/theme/default_theme.tres` | the project Theme (`gui/theme/custom`): Sarabun Regular, size 20 | `default_font` | ui/ |
| `table/camera_rig.gd` | orbit camera rig (mouse drag/wheel, one-finger drag, pinch); becomes the shared pan/pinch/orbit rig of both tables (R0-E) | `func _unhandled_input(`, `func _apply(` | table/ |
| `table/figures/kit_library.gd` | `KitLibrary` (RefCounted, pure): lists kits in `assets/kits`, reads `kits.json`, picks and spaces a line-up; lazy per-kit loading and LOD come in R0-D/R1 | `const KITS_DIR`, `static func pick(`, `static func load_manifest(`, `static func row_positions(` | table/figures |
| `scenes/probe/probe.tscn` + `probe.gd` + `hud.gd` | the line-up / GPU probe scene: 40×30 m table, sky, sun with shadows, CameraRig, up to 12 kits (coloured boxes without kits), Thai HUD with FPS/GPU/OS/screen and the ENGLISH button | `func _place_kits(`, `func _place_stand_ins(`, `func refresh(` (hud) | table/ + ui/ |
| `assets/fonts/Sarabun-*.ttf`, `OFL.txt` | the UI font (SIL OFL) | — | ui/ |
| `assets/shaders/table.gdshader` | procedural checker + noise table top (no textures) | `shader_type spatial` | table/ |
| `assets/kits/` | **generated, git-ignored**: `tools/export_kits.js` → 312 `.glb` + `kits.json` (48 MB); CI makes them in the `kits` job | — | table/figures (R0-D) |
| `data/*.json`, `data/README.md`, `data/rules_summary.md` | the page's data tables exported by `tools/export_data.js` (types in protocol order, facs, core, themes, terrains, teams, phases, chapters, variants, skins, fly, strats, anim, fx, natural, unit_colours, sky, dust, constants, 1,554 English strings) — **never hand-edited** | `data/README.md` names the page anchor of every table | tools |
| `tools/export_kits.js`, `tools/export_data.js` | Node + Playwright scripts that read the old page (`CHROMIUM_PATH` as in `tests/run.sh`) | — | tools |
| `tests/run.sh` | `bash godot/tests/run.sh [quick\|full\|<word>]` — see §5 | — | tools/tests |
| `tests/run_tests.gd` | the headless runner: recursive over `tests/unit/**/test_*.gd` plus `tests/golden/test_golden.gd`; `-- <word>` filter; runs on the first frame so every autoload is ready | `static func discover(`, `func _ensure_autoloads(` | tools/tests |
| `tests/testing.gd` | the test base: `assert_true/false/eq/ne/within/digest`, `setup()` | `func assert_digest(` | tools/tests |
| `tests/render_probe.gd` | xvfb entry: renders the probe scene to `tests/out/probe.png` and `probe_en.png` (`TEST_OUT` overrides the folder) | `const SCENE` | tools/tests |
| `tests/unit/test_app.gd`, `test_log.gd`, `test_clock.gd`, `test_i18n.gd`, `test_kit_lineup.gd` | the unit suites (one per module) | `func test_` | the module's track |
| `docs/ARCHITECTURE.md`, `docs/PLAN.md` | the decided design; the R0–R6 task list with file paths | — | lead |
| `.gitignore` | `.godot/`, `tests/out/` | — | tools/tests |

Outside `godot/`: `.github/workflows/godot.yml` (CI: `kits` → `test` (import, `tests/run_tests.gd`, `tests/render_probe.gd`
under xvfb), `windows`, `android`; extended in R0-C) and this file.

### 1.2 Planned folders (ARCHITECTURE §1) and who creates them

| Folder | Content | Created by |
| --- | --- | --- |
| `core/` | the rules core: `version.gd`, `fx.gd`, `rng.gd`, `hash.gd`, `events.gd`, `actlog.gd`, `table.gd`, `data.gd`, `field/`, `battle/`, later `dnd/` — RefCounted only, integer only | R0-B (toolbox), R1 (battle rules), R4+ (`dnd/`) |
| `data/schema/`, `data/version.json` | JSON schemas (unit, weapon, army, theme, ability, i18n, map_layout, monster), the rules/data version stamp | R0-F |
| `tools/validate_data.py`, `tools/gen_bt_data.py`, `tools/record_oracle.js`, `tools/kits.sh`, `tools/bake_impostors.gd`, `tools/mock_worker.mjs`, … | data lint, server datasheet file, oracle recorder, kit pipeline | R0-F, R0-G, R0-C, R0-D |
| `assets/kits_import/`, `assets/shaders/figure.gdshader`, `assets/impostors/` (generated) | merged-surface kit import, team-tint shader, impostor strips | R0-D |
| `table/table_view.gd`, `terrain_mesh.gd`, `props_layer.gd`, `figures/figure_pool.gd`, … | the 3D presentation of the table | R0-E, R1 |
| `ui/screens/`, `ui/widgets/` | Control scenes, Thai first (`gpu_check` first) | R0-E, R1+ |
| `scenes/main.tscn`, `scenes/battle_table.tscn` | root scene (World + UI ScreenStack + Overlay); the battle table scene | R0-E |
| `net/` | `room_client.gd`, `server.gd`, `json_num.gd`, later `dnd_client.gd` | R3, R4 |
| `tests/render/`, `tests/golden/`, `tests/oracle/`, `tests/net/`, `tests/selftest.gd` | xvfb render tests (`run_render.gd` entry), golden replays, oracle recordings, net sync, the exported-exe selftest | R0-D/E, R1, R0-G, R3, R0-C |
| `app/audio.gd`, `app/selftest.gd` | the `Audio` autoload; the in-app Selftest screen | R2, R1 |

## 2. Autoloads — the only global state

Registered in `project.godot` in this order (an autoload's `_init()` runs in this order too): **`App`** (`app/app.gd`),
**`I18n`** (`ui/i18n.gd`), **`Log`** (`app/log.gd`), **`Clock`** (`app/clock.gd`). ARCHITECTURE §3 adds `Audio` (R2) and
`Net` (R3). Nothing else is global; `core/` never touches them.

| Autoload | Read | Write / call |
| --- | --- | --- |
| `App` | `App.gfx`, `App.lang`, `App.snd`, `App.server`, `App.current()`, `App.depth()` | `App.set_gfx("min")`, `App.set_lang("en")` (also sets `I18n.english`), `App.set_server(url)`, `App.save_settings()`, `App.push(packed_scene)` (hides the screen below), `App.pop()`, `App.back()` (Android back: pop, or quit at the first screen), `App.set_screen_root(node)` (main.tscn) |
| `I18n` | `I18n.english`, `I18n.t(th)`, `I18n.has_key(th)`, `I18n.missing(keys)` | `I18n.english = true` (prefer `App.set_lang`) |
| `Log` | `Log.lines()`, `Log.dump()`, `Log.size()` | `Log.info(msg)`, `Log.warn(msg)`, `Log.error(msg)`, `Log.clear()`, `Log.echo` |
| `Clock` | `Clock.now_ms()`, `Clock.frozen` | `Clock.frozen = true`, `Clock.step(ms)` (tests), never from rules code |

Facts verified in 4.7.1 (the runner relies on them): autoloads **are** instantiated when Godot runs a `SceneTree`
script with `-s` headless; their `_init()` has run before the script's `_initialize()`, but their `_ready()` runs
after it. So every autoload builds its state in `_init()` (settings, dictionaries) and `tests/run_tests.gd` runs the
tests from its first `_process()` frame, when everything is ready. Should an autoload ever be missing, the runner
instantiates it from `project.godot` (`func _ensure_autoloads(`) and prints that it did.

## 3. Ownership tracks (ARCHITECTURE §1)

One PR touches one track plus its tests; branches `claude/…` or `codex/…`; list the open PRs of both repos first.

| Track | Folders | R0 task |
| --- | --- | --- |
| core/field | `core/field/` | R1-F |
| core/battle rules | `core/battle/{combat,pend,strats,abilities}.gd` | R1 |
| core/battle flow | `core/battle/{turn,acts,bot,board}.gd` | R1 |
| core toolbox | `core/{version,fx,rng,hash,events,actlog,table}.gd` | R0-B |
| table/figures | `table/figures/`, `assets/kits_import/`, `assets/shaders/figure.gdshader`, `tools/bake_impostors.gd` | R0-D |
| table (terrain, props, camera, fx, dice) | `table/*.gd`, `table/fx/`, `table/dice/`, `scenes/main.tscn`, `scenes/battle_table.tscn` | R0-E |
| ui/ | `ui/`, `app/app.gd` (settings + router) | R0-E (`gpu_check`), R1+ |
| net/ | `net/` | R3 |
| tools + tests + CI | `tools/`, `tests/` (runner, base, `run.sh`), `.github/workflows/godot.yml`, `docs/GODOT.md` | R0-A, R0-C, R0-F, R0-G |
| core/dnd | `core/dnd/`, `data/dnd/` | R4+ |
| table/board3d | `table/board3d/` | R4+ |

## 4. Invariants (what every PR keeps true)

1. **Core purity.** `core/` is pure GDScript, `extends RefCounted` only: no Node, no float, no literal with a decimal
   point, no `Vector2/3`, `Transform`, `sin(`, `cos(`, `atan2(`, `sqrt(`, `pow(`, `lerp(`, `randf`, `randi`,
   `randomize`, `Time.`, `OS.`, `Engine.`, `get_tree`, `await`, `signal`. Allowed: `int`, `bool`, `String`, typed
   `Array`, `Dictionary`, `PackedInt64Array`, `PackedInt32Array`, `PackedStringArray`. `tests/unit/test_core_purity.gd`
   (R0-B) scans `godot/core/**` and fails the PR. Message keys and args come out of core; the UI formats them, so core
   holds no UI text.
2. **Determinism.** Rules quantities are int64 in MI (milli-inches, 1" = 1000); random only from the seeded PCG32 streams
   of `core/rng.gd` (`terrain`, `props`, `objectives`, `armies`, `deploy`, `bot:<seat>`, `fallback:<seq>:<stage>`); rule
   positions `gx`/`gz` are authoritative, walking x/z are visual; every "nearest/best" tie breaks by index; JS `sort`
   becomes `Fx.stable_sort`; `Math.round` becomes `Fx.js_round`; no act code or field beyond the Worker allowlist
   without a server PR and a `RULES_V` bump. Goldens on x86-64, arm64 and the Windows exe prove it on every PR (R1+).
   Dice ≤ 60 per act; beyond that the fallback stream on every device.
3. **Weak phones: the `min` level budget** (ARCHITECTURE §6): ≤ 120 draw calls, ≤ 250k triangles, render scale 0.6,
   30 fps cap, no shadows, selected squad + ≤ 8 walkers skinned, ≤ 32 CPU particles, per-vertex shading, redraw only
   when something moves. **Nothing per-frame is added to `min`, ever** — `tests/render/test_budgets.gd` is the gate.
   `Clock` and `App` do no per-frame work; `hud.gd` of the probe updates its info label every 0.5 s only.
4. **Thai first, with an English pair.** Every Thai UI string goes through `I18n.t()`; a string that exists only in the
   new app gets its English in `ui/i18n_extra.json`; page strings come from `data/i18n_en.json`. `tests/unit/test_i18n.gd`
   fails on a missing pair or Thai left in an English value; `tests/render/test_screens.gd` (R1) fails if English mode
   shows Thai. Typed text and player names are never translated.
5. **No names, logos or markings from other game companies** (AGENTS.md rule 1), in files, kit keys, strings,
   comments, tests, commits and PRs. `tools/validate_data.py` (R0-F) scans `godot/` in CI.
6. **Secrets never enter the repo.** `export_presets.cfg` keeps empty keystore fields; CI greps for `keystore/release=`
   values and `.jks` files (R0-C). Never ask the owner to paste a key.
7. **Hidden units stay hidden.** `sec`/`lk` are opaque fields; how they are unlocked is never written in notes, tests,
   comments, PRs or this file.
8. **Surgical edits; generated files are never hand-edited.** `assets/kits/`, `assets/impostors/`, `assets/anim/`,
   `data/*.json` come from `tools/`; re-run the tool. Commit the `.uid` and `.import` files Godot writes; never reformat
   `.tscn`/`.tres`. Comments in game code are short and in Thai; English in tests, tools and docs.
9. **A failing test is a bug to fix**, never a test to delete, skip or loosen; add a test for what you build. A
   user-visible change bumps `core/version.gd APP_VER` and gets a Thai note in `web/`.

## 5. Tests

```bash
G=/path/to/Godot_v4.7.1-stable_linux.x86_64          # in this container: see godot/README.md; in CI ~/godot-bin/godot
bash godot/tests/run.sh                              # quick: --import + unit tests (CI runs this on every PR)
bash godot/tests/run.sh full                         # quick + the render probe under xvfb → $TEST_OUT/probe.png, probe_en.png
bash godot/tests/run.sh i18n                         # unit scripts whose path contains the word (e.g. unit/core)
GODOT=$G TEST_OUT=/tmp/out bash godot/tests/run.sh   # the binary and the output folder (default godot/tests/out)

$G --headless --path godot --import                                  # after a checkout or an asset change
$G --headless --path godot -s tests/run_tests.gd [-- <word>]         # the unit + golden runner by itself
timeout 180 xvfb-run -a -s "-screen 0 1280x720x24" $G --path godot --rendering-driver opengl3 \
  --resolution 1280x720 --audio-driver Dummy -s tests/render_probe.gd   # the render probe by itself
```

- **Discovery.** `tests/run_tests.gd` walks `tests/unit/` recursively for `test_*.gd` (sorted by path) and appends
  `tests/golden/test_golden.gd` when it exists; `-- <word>` keeps the scripts whose path relative to `tests/` contains
  the word (`test_fx`, `unit/core`, `golden`). It prints one `ok`/`FAIL` line per assertion like the Playwright suites of
  `tests/`, then `PASS`/`FAIL  N passed, M failed in K scripts`, and exits 1 on any failure or when nothing matched.
- **Writing a test.** `tests/unit/<area>/test_<module>.gd` (one file per core module, same name, ARCHITECTURE §10)
  with `extends "res://tests/testing.gd"` and `func test_*()` methods; `setup()` runs once per script. Assertions:
  `assert_true(cond, msg, detail)`, `assert_false`, `assert_eq(a, b, msg)`, `assert_ne`, `assert_within(a, b, tol, msg)`
  for floats, `assert_digest(got, expected, msg)` for digest strings (prints where they first differ). The autoloads
  are live; prefer a fresh instance (`preload("res://app/log.gd").new()`) when a test mutates state, and `free()`
  Node instances. Headless tests must not need the kits: the kit checks in `test_kit_lineup.gd` run only when
  `assets/kits/` is populated (quick set: 94 checks without kits, 98 with).
- **Render.** `tests/render_probe.gd` (CI's `godot-probe` artifact) needs a display: xvfb + Mesa llvmpipe here and in
  CI. Look at the PNGs before claiming a visual change works; Thai must not be boxes. ALSA / V-Sync warnings are
  harmless. R0-D/R0-E add `tests/render/run_render.gd` (budgets, line-up, screens).
- **CI.** `.github/workflows/godot.yml`: `kits` (export the kits with Playwright) → `test` (import, `tests/run_tests.gd`,
  `tests/render_probe.gd` under xvfb), `windows` (release .exe), `android` (debug APK). R0-C adds `test-arm`,
  `windows-smoke`, the signed APK on `main` and the `release` job.

## 6. Intentional v10 differences from v9 (ARCHITECTURE §4)

Listed here and in the oracle allowlist (`tests/oracle/allowlist.json`, R1-E) so a diff against the page is read
correctly: integer formation and search offsets rounded to 0.01"; fixed-point noise with v10's own `ihash2/ihash3`
(new terrain and prop shapes per seed); `+1 MI` instead of `+0.05"` range tolerance; the dice fallback rule past 60
dice; no other maths change. Datasheets, points, phases, stratagems, caps and the act protocol are identical; v9 pages
and the v10 app never share a room (the server's version gate).

## 7. Design notes

### 7.1 Layout JSON schema (R0-F)

_Stub — filled by R0-F (track tools) together with `data/schema/map_layout.json`._ The field list decided in
ARCHITECTURE §9: `{v, seed, kind, size:[w,h], cells (RLE tile ids: floor/wall/water/pit/door/stairs), heights,
rooms[{id, kind, rect, tags}], corridors[], doors[], props[{k, x, z, rot}], lights[], spawns[{kind, x, z, group}],
exits[], labels[], edits[]}`; the server stores only `board.map = {seed, kind, ver, edits[]}` and every device
regenerates the same map.

### 7.2 DM act vocabulary (R0-F)

_Stub — filled by R0-F (track tools) with the schema._ "DM commands are acts" (ARCHITECTURE §9): `dm.narrate`,
`dm.scene`, `dm.place`, `dm.move`, `dm.remove`, `dm.combat_start` / `dm.combat_next` / `dm.combat_end`, `dm.roll_ask`,
`dm.hp`, `dm.reveal`; every DM action replays and logs, undo is a reverse act. No D&D code before R3 is green.
