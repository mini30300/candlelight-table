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
| `project.godot` | Godot 4.7 project: `gl_compatibility` on desktop and mobile, 1280×720 `canvas_items`/`expand`, landscape, Sarabun theme, **autoloads in the order App, I18n, Log, Clock** | `[autoload]` · `run/main_scene` (`scenes/main.tscn`) · `[importer_defaults]` (the kit post-import) | tools/tests |
| `export_presets.cfg` | "Windows Desktop" (x86_64) and "Android" (arm64-v8a + armeabi-v7a, min SDK 24); keystore fields EMPTY on purpose — release signing comes from `GODOT_ANDROID_KEYSTORE_RELEASE_*` env vars in CI | `[preset.0]`, `[preset.1]` | CI (R0-C) |
| `icon.svg`, `README.md` | app icon; the Thai README: setup, tests, render probe, exports | — | tools/tests |
| `app/app.gd` | **`App`** autoload: settings `gfx` (hi/mid/lo/min), `lang` (th/en), `snd`, `server` in `user://settings.cfg` (ConfigFile, section `app`, defaults when the file is missing or corrupt); the ScreenStack router; Android back button | `func load_settings(`, `func save_settings(`, `func set_lang(`, `func push(`, `func pop(`, `func current(`, `func back(` | ui/ (owner), app/ |
| `app/log.gd` | **`Log`** autoload: ring buffer of the last 500 lines, `info/warn/error`, `dump()` for the "copy log" button; `echo = false` silences the console (tests) | `const CAPACITY := 500`, `func dump(` | app/ |
| `app/clock.gd` | **`Clock`** autoload: the one tick source for view timers; `now_ms()`, `frozen`, `step(ms)`; no signal, no per-frame work (computed on read from `Time.get_ticks_msec()`) | `func now_ms(`, `func set_frozen(` | app/ |
| `ui/i18n.gd` | **`I18n`** autoload: Thai keys → English; lookup order `EN` (in the script) → `ui/i18n_extra.json` → `data/i18n_en.json`; `t(th)`, `lookup`, `has_key`, `missing(keys)`; dictionaries load in `_init()` | `const EN`, `func t(`, `func lookup(` | ui/ |
| `ui/i18n_extra.json` | English for Thai strings that exist only in the new app (the `EN` dict's entries are mirrored here; `tests/unit/test_i18n.gd` checks they agree) — every new Thai UI string gets a pair here | — | ui/ |
| `ui/theme/default_theme.tres` | the project Theme (`gui/theme/custom`): Sarabun Regular, size 20 | `default_font` | ui/ |
| `table/camera_rig.gd` | orbit camera rig (mouse drag/wheel, one-finger drag, pinch); becomes the shared pan/pinch/orbit rig of both tables (R0-E) | `func _unhandled_input(`, `func _apply(` | table/ |
| `table/figures/kit_library.gd` | `KitLibrary` (RefCounted, pure): lists kits in `assets/kits`, reads `kits.json`, picks and spaces a line-up, kit path, bounds (`bbox`) and the two main kit colours; lazy per-kit loading and LOD come in R0-D/R1 | `const KITS_DIR`, `static func pick(`, `static func load_manifest(`, `static func row_positions(`, `static func bounds(`, `static func kit_colours(` | table/figures |
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

### 1.2 Modules added in R0 (search anchors; line numbers drift)

| File | What | Anchors | Track |
| --- | --- | --- | --- |
| `core/version.gd` | `Version`: `RULES_V` 10, `APP_VER`, `DATA_HASH` (filled by `tools/validate_data.py --write-version`) | `const RULES_V`, `const DATA_HASH` | core |
| `core/fx.gd` | `Fx`: milli-inch integer maths with JavaScript semantics where the page had them | `static func idiv(`, `static func imod(`, `static func isqrt(`, `static func norm1000(`, `js_round`, `to_fixed_1`, `stable_sort` | core |
| `core/rng.gd` | `Rng`: PCG32, one stream per job (terrain, props, objectives, armies, deploy, `bot:<seat>`, `fallback:<seq>:<stage>`), unbiased `bounded`, snapshots | `static func make(`, `func next_u32(`, `func bounded(`, `func d6(`, `func restore(` | core |
| `core/hash.gd` | `Hash`: 32-bit mixers for noise, FNV-1a 64 for digests | `static func ihash2(`, `static func fnv1a64(`, `static func digest_hex(` | core |
| `core/events.gd`, `core/actlog.gd`, `core/table.gd` | typed event ids; the ordered act log (ints only, JSON round-trip); the `Table` base (`apply` → events, `advance`, `digest`, `replay`) | `static func id_of(`, `func append(`, `func canon(`, `func apply(`, `func advance(`, `func replay(` | core |
| `core/data.gd` | `GameData`: loads `data/*.json` once into integers only (JSON numbers come back fractional-typed; base radius `r` becomes `r_mi`; any other fraction in the rules tables is a load problem); TYPES order kept as the cross-device contract; hidden units flagged only | `static func load_all(`, `static func ty(`, `static func index_of(`, `static func pool(`, `static func base_r_mi(`, `static func const_int(`, `static func to_mi(` | core |
| `core/field/noise.gd` | `FieldNoise`: the page's value noise and fbm in Q16 fixed point (ONE = 65536) over `Hash.ihash2`; `ridge` for mountain crests; `at_mi` maps milli-inches to noise coordinates like the page's `x/34 + 3.7`; a pinned grid digest in `tests/unit/test_noise.gd` proves x86-64 and arm64 agree | `static func vnoise(`, `static func fbm(`, `static func ridge(`, `static func fade_q(`, `static func at_mi(` | core/field |
| `core/field/terrain.gd` | `FieldTerrain`: the page's `buildTerrain` in milli-inches — grid (`cell_for`, `depth_for` as the page sizes the table), relief and roughness per theme from `GameData.theme_mi`, flat/mountain overrides, mountain crests, desert dunes through `Fx.isin_q16`, the ruin road band; bilinear `height_at`; heights are for the view (rules positions stay 2D) | `static func make(`, `func point(`, `func height_at(`, `func digest(` | core/field |
| `core/field/props.gd` | `FieldProps`: the page's `genProps` in integers — clustered spots, kinds per theme (`THEME_KIND`, `EXTRA_KIND`), density and `PROP_CAP`, spacing (`room_for`), houses only on gentle ground, never crossing (`houses_clear`, separating axes) and clearing what they stand on (`under_house`), woods for the forest terrain, then `level_under` flattens the ground (houses first) | `static func generate(`, `func _place(`, `func _woods(`, `func level_under(`, `func bld_size(`, `func foot_of(` | core/field |
| `tests/unit/test_core_purity.gd` | the purity lint over `core/**` (forbidden tokens of ARCHITECTURE §2; a planted float fixture must fail) | `fixtures/purity_bad/` | core |
| `data/schema/*.json`, `data/version.json`, `data/bt2_snapshot.json`, `data/bt_data.json` | JSON schemas of every table, the rules/data stamp, the server's datasheet snapshot and the file the server PR will take | — | tools |
| `tools/validate_data.py` | the data lint CI runs: schemas, banned names of AGENTS rule 1 over `godot/` (legacy tokens hashed in `data/schema/legacy_tokens.sha1`), Thai→English completeness in `ui/**` and `app/**`, TYPES append-only, dice ≤ 60, secrets guard; `--fixtures`, `--write-version` | `def check_schema(`, `def banned_hits(`, `def thai_display_strings(` | tools |
| `tools/gen_bt_data.py`, `docs/DATA.md` | datasheet payload for the server; the layout-JSON schema and the DM act vocabulary | — | tools |
| `tools/record_oracle.js`, `tests/oracle/` | Playwright recorder of the old page (`window.BT`), 20 gzipped recordings, `check_oracle.mjs`, format in `tests/oracle/README.md` | `function writeRecording(`, `function pageActCodes(` | tools |
| `tools/godot.sh`, `tools/kits.sh`, `tests/selftest.gd` | pinned Godot download with SHA-512 checks; one command for kits + bakes; the self-test the Windows smoke job runs inside the exported exe (`override.cfg` → `run/main_loop_type="SelfTest"`) | `sha512_for()`, `func _run(` | CI |
| `assets/kits_import/kit_post_import.gd` | EditorScenePostImport applied through `[importer_defaults]`: one merged surface per kit, `COLOR` = kit colour, `CUSTOM0` = (paintable flag, palette index), skin kept; contract in `assets/kits/CONTRACT.md` | `func _post_import(`, `func _merge(`, `func _flatten(` | table/figures |
| `assets/shaders/figure.gdshader`, `figure_material.tres` | the figure material: kit colours, optional paint table (`paint_tex` rows, `paint_row` or `INSTANCE_CUSTOM.x`), per-vertex shading switch, `mask_out` for the impostor bake; no team dye (team = ring) | `uniform sampler2D paint_tex`, `uniform int paint_row`, `uniform bool per_vertex` | table/figures |
| `tools/bake_impostors.gd`, `assets/impostors/` (generated) | 16 yaw × 2 pitch per kit into `<kit>.png` + `<kit>_m.png` + `impostors.json` (15 s for 312 kits) | `func _bake_kit(` | table/figures |
| `tools/bake_anim.js` → `assets/anim/clips.json` (generated) | Playwright on the old page: samples SKRIG.Controller / idlePose / WALKER and the battle table's actions (window.BT) at 30 Hz into clips (local rotation of all 23 joints + pelvis translation per frame, contact flags, speed, travel, turn, events); fits the gear the page turns by itself into the hand / forearm bones; per-kit `holds`; measures every clip against the page's own drawing (`fidelity`); ride walk / run of the rigged mounts (legs re-solved onto planted hooves, loop cross-faded); `--check` validates | `function pageLib(`, `function cycle(`, `function gearFix(`, `function holds(`, `function fidelityOf(`, `async function rideClips(`, `function validate(` | tools |
| `tools/mount_rig.js` | shared by export_kits.js and bake_anim.js: finds the parts of a mount the page moves with travel (rigid groups of faces, pivots, the tree, the legs, the page's stride and leg phases), the gait plan and the two-bone IK | `function findParts(`, `function buildTree(`, `function buildRig(`, `function planGait(`, `function ik2(` | tools |
| `tools/bake_anim.gd` → `assets/anim/humanoid.res` (generated) | clips.json → one `AnimationLibrary` (tracks `Skeleton3D:<bone>`; metadata per clip; library meta `holds`, `proofs`); `assets/anim/CLIPS.md` is the contract | `static func build_library(`, `static func clip_to_animation(` | tools |
| `scenes/main.tscn` + `main.gd` | the root: World + UI ScreenStack + Overlay; first-run level guess (mobile → lo, ≤ 2 GB → min) | `static func guess_level(` | table + ui |
| `scenes/battle_table.tscn`, `table/table_view.gd` | the battle table look: camera rig, sun, environment, terrain, props, figures, rings; applies the graphics level. The field comes from `core/field` for a setup (`DEFAULT_SETUP`: seed 1, 48", ruin, hills, buildings, density x1): `FieldTerrain.make` → `FieldProps.generate` (it levels the ground, so props before the mesh) → terrain mesh → props; `rebuild(setup)` builds another setup; `counts()` has `props` (drawn) and `field_props` (rules) | `const DEFAULT_SETUP`, `func build_look(`, `func rebuild(`, `func setup(`, `func apply_level(`, `func set_stress(`, `func counts(` | table |
| `table/terrain_mesh.gd` | the field mesh from `FieldTerrain.hg` after levelling (MI/1000 = metres, 1 game inch = 1 m; vertices on the rules grid every `cell_mi`, clipped to the table edge), one ArrayMesh with vertex colours per theme (`themes.json`), height and slope, plus rails that follow the edge profile and a dark skirt; `height_at` is the rules' bilinear in floats; grid step 2 on min | `func build(`, `func height_at(`, `static func axis_nodes(`, `func _rails(` | table |
| `table/props_layer.gd` | `FieldProps.items` drawn as one MultiMesh per kind (x, z, `rot`/65536 rad, `s`/1000, on the levelled ground); low-poly meshes built from the rules footprints (`bld_size` for buildings, `foot_of` where defined, `rad_of` otherwise; `footprint()`), cached per kind and detail; `blocked_at` uses the same footprints; simplified meshes on lo/min | `static func footprint(`, `static func kind_mesh(`, `func blocked_at(`, `func multimesh_of(`, `func set_simplified(` | table |
| `table/sky.gd`, `assets/shaders/sky.gdshader` | `TableSky`: the background per theme from `data/sky.json`: a flat gradient sky shader (sky, plain in haze below the horizon, sun glow); the skyline (city, treeline, dunes, peaks; the page's `panoOf`) as a 720x1 height texture on mid/hi only; lo has no skyline; min is one flat colour (no sky pass) | `func apply(`, `static func pano(`, `uniform bool skyline_on` | table |
| `table/rings.gd` | ONE MultiMesh of ground rings: the team ring under every figure, selection/destination/objective rings by kind | `func add_ring(`, `func set_colour(`, `func add_kind(` | table |
| `table/figures/figure_pool.gd` | tiers: skinned kit scenes near, per-kit MultiMesh (merged mesh, white instance colours, custom x = paint row) elsewhere; per-level skinned caps and runtime LODs on lo/min | `static func make(`, `func build(`, `func apply_level(`, `_figure_material` | table/figures |
| `tools/ruin_kit.gd` | R1-V5 gothic ruin kit, our own design (no model files, textures or marks): low-poly pieces with vertex colours into ONE SurfaceTool (one surface = one draw call); lod 0 = hi (cut-out pointed-arch windows via Geometry2D strips, rose window, fluted pillars with brass bands, hood mouldings, masonry blocks), lod 1 = lo (solid walls with dark window quads, fewer flutes and pieces); per-piece seeds so hi and lo share the outline | `func wall(`, `func arch_hole(`, `func steps(`, `func rose(`, `func pillar(`, `func slab(`, `func stair(`, `func rubble(`, `func statue(`, `func panel(`, `func pipe(` | table (props) |
| `tools/ruin_sample.gd`, `assets/props/ruin/sample_building_hi.res` + `_lo.res` | the ONE sample building for the owner: two storeys inside `FieldProps.bld_size` (s = 1000, h = 45000, field seed 30 → 9.81 × 8.04 m) + the 0.6 m pad, hi ≤ 6,000 / lo ≤ 1,500 triangles; saves both meshes and renders `tests/out/ruin_sample_{front,corner,top,lo}.png` under xvfb with the app's Sun and ruin sky (`--headless`: build + save only); `tests/unit/test_ruin_kit.gd` checks budgets, footprint, determinism and that the committed `.res` match | `static func build_mesh(`, `static func assemble(`, `static func footprint(`, `const SHOTS` | table (props) |
| `table/camera_rig.gd` | `CameraRig`: pan / pinch / orbit / wheel / WASD, fit-table, pitch clamps, tap-vs-drag | `class_name CameraRig` | table |
| `ui/screens/gpu_check.tscn` + `.gd` | the GPU-check screen: adapter, GL version, fps, draw calls, primitives, memory, level picker (render scale + shadows live), stress toggle, Thai LineEdit for the IME, copy button, Thai/English, the "จัดกองทัพ ›" button (`army_requested`, opened by `scenes/main.gd`) | `func refresh(`, `func _on_level(`, `func _on_copy(`, `signal army_requested` | ui |
| `ui/screens/army.tscn` + `army.gd` | the army picker (R1-V4), pushed by `scenes/main.gd` `open_army()`: 15 army buttons, a datasheet card per listed unit (stats boxes, weapon table, keywords, abilities, knight chapter headings), −/+ per squad, budget stepper over `BUDGETS`, points bar and status, random army, preview turntable, Thai/English; hides the 3D table while open; no `_process` | `func select_army(`, `func select_unit(`, `func add_unit(`, `func random_army(`, `func listed_units(` | ui |
| `ui/screens/army_roster.gd` | `ArmyRoster` (RefCounted): squads per TYPES slot (the wire list), army, budget; `units_of(fac)` never lists a hidden unit; the simple seeded pick on the `armies` stream from `GameData.pool` (not the rules' autoList, which comes with `core/battle/army.gd`) | `static func units_of(`, `func random_fill(`, `func points(`, `static func budgets(` | ui |
| `ui/widgets/datasheet_text.gd` | `DatasheetText`: every text of a datasheet card in the page's wording (`abilityText`, `wpnLine`), translated as whole sentences then filled (`tf`); reaches I18n through the tree so `-s` scripts can use it | `static func stats(`, `static func weapon_row(`, `static func abilities(`, `static func tf(` | ui |
| `ui/widgets/kit_turntable.gd` | `KitTurntable` (SubViewportContainer, own World3D): one kit in its own colours on a plinth, slow spin, drag to turn; on min no spin and one redraw per change | `func show_kit(`, `func set_level(`, `const SPIN` | ui |
| `tests/render/test_lineup.gd`, `test_budgets.gd`, `test_main_screens.gd`, `test_field_look.gd`, `test_army_screen.gd` | xvfb suites: every kit imported right + one draw call per figure + paint override; the §6 budgets per level on the 400-figure scene, for the default field and for the densest one (`DENSE_SETUP`, 480 props = `PROP_CAP`); the main screens in Thai and English (no Thai left in English mode); the field look: 4 themes x 4 terrains at 640x360 (`field_<theme>_<terrain>.png`) + a low sky view per theme, drawn props == `FieldProps.items`, mesh heights == field heights at the grid points, props at their rules spot/rot/scale, meshes fill their footprints, the default setup's digests == `core/field`'s; the army picker for all 15 armies in Thai and English (no hidden unit, points, seeded random, turntable, 44 px targets; `army_<fac>_th.png`, `army_en.png`) | `func _render_army(`, `func _check(`, `func _thai_in(`, `func _check_field(`, `func _check_heights(`, `func _check_every_army(` | table + ui |
| `tests/unit/test_army_roster.gd` | headless: rosters per army without hidden units, points and budget steps, the seeded pick, English for every datasheet text, every Thai literal of the army screen files a whole I18n key | `func test_` | ui |
| `tests/render/test_anim_footslide.gd` | the clips on imported kits moving at the clip's speed (motion_scale = kit scale): planted-foot slide ≤ 15 mm on the humanoid, the page's walker and the biggest walker, the horse's hooves and every other ride clip (mount bones in the skeleton, loops close), wrong-speed controls, the holds; with a display `tests/out/anim_walk_*.png` strips and `anim_actions_*.png` sheets; `apply_holds` is the reference of the holds layer | `func slide(`, `func mount_slide(`, `func _ride_loops(`, `static func apply_holds(`, `static func planted(` | tools + table/figures |

Still planned (ARCHITECTURE §1): `core/field/`, `core/battle/` (R1), `net/` (R3), `app/audio.gd` (R2), `app/selftest.gd` screen (R1), `tests/golden/`, `tests/net/`, `core/dnd/` (R4+).

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
... -s tests/render/test_lineup.gd | test_budgets.gd | test_main_screens.gd | test_army_screen.gd | test_anim_footslide.gd   # the render suites by themselves
$G --headless --path godot -s tests/selftest.gd -- --out /tmp/selftest.txt   # what the exported exe runs on windows-latest
python3 godot/tools/validate_data.py [--fixtures] [--write-version]          # the data lint (no Godot needed)
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
- **Render.** `tests/render_probe.gd` and the three suites under `tests/render/` need a display: xvfb + Mesa llvmpipe
  here and in CI (`run.sh full` runs them all; CI's `godot-probe` artifact carries every PNG). Look at the PNGs before
  claiming a visual change works; Thai must not be boxes. ALSA / V-Sync warnings are harmless. `test_budgets.gd` is
  the gate of AGENTS rule 6: the §6 draw-call and triangle budgets per level on the 400-figure scene.
- **CI.** `.github/workflows/godot.yml`: `kits` (export + bakes, cached on the page and `godot/tools`) → `test`
  (secrets guard, import, unit tests, data lint, self-test, render probe + render suites), `test-arm` (import + unit
  tests + self-test on arm64), `windows` (release .exe + Thai readme zip) → `windows-smoke` (the self-test inside the
  exe on windows-latest), `android` (debug APK on PRs; signed release APK on `main` from the existing secrets),
  `release` (main only: assets on the `build-N` release of the same commit).

## 6. Intentional v10 differences from v9 (ARCHITECTURE §4)

Listed here and in the oracle allowlist (`tests/oracle/allowlist.json`, R1-E) so a diff against the page is read
correctly: integer formation and search offsets rounded to 0.01"; fixed-point noise with v10's own `ihash2/ihash3`
(new terrain and prop shapes per seed); `+1 MI` instead of `+0.05"` range tolerance; the dice fallback rule past 60
dice; no other maths change. Datasheets, points, phases, stratagems, caps and the act protocol are identical; v9 pages
and the v10 app never share a room (the server's version gate).

Field generation (R1, `core/field/`): the page skipped the slope, house and overlap checks of `genProps` in its
default setup (hills, density ×1) to keep old APKs' props; v10 runs every check in every setup. A house pad whose
level core touches an earlier, already levelled pad takes that pad's height instead of being tilted by it (the page
let the later house lean). Rotations are Q16 radians through `Fx.isin_q16`; thresholds compare the 16-bit hash
values exactly (`u * 100 < 62 * 65536`).

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
