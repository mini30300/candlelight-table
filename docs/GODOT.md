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
| `project.godot` | Godot 4.7 project: `gl_compatibility` on desktop and mobile, 1280×720 `canvas_items`/`expand`, landscape, Sarabun theme, **autoloads in the order App, I18n, Log, Clock, Net**; an `[input]` map on **physical** keys (`move_forward/back/left/right` = WASD + arrows, `run` = Shift, `interact` = E, `back` = Esc), so WASD works with a Thai keyboard layout; `include_text_server_data` (Thai line breaks in exports) | `[autoload]` · `[input]` · `run/main_scene` (`scenes/main.tscn`) · `[importer_defaults]` (the kit post-import) | tools/tests |
| `export_presets.cfg` | "Windows Desktop" (x86_64) and "Android" (arm64-v8a + armeabi-v7a, min SDK 24); keystore fields EMPTY on purpose — release signing comes from `GODOT_ANDROID_KEYSTORE_RELEASE_*` env vars in CI | `[preset.0]`, `[preset.1]` | CI (R0-C) |
| `icon.svg`, `README.md` | app icon; the Thai README: setup, tests, render probe, exports | — | tools/tests |
| `app/app.gd` | **`App`** autoload: settings `gfx` (hi/mid/lo/min), `lang` (th/en), `snd`, `server`, `fig` (egg/kit figure style), `touch` (auto/on/off on-screen controls) in `settings_file` (default `user://settings.cfg`; tests point it at their own file; ConfigFile, section `app`, defaults when the file is missing or corrupt); `last_choice` (the last battle setup, in memory only; the setup screen reopens with it and a new seed); the ScreenStack router (`push`, `pop`, `replace` = swap the top screen without showing the one below); Android back / Esc (`back` action): asks the top screen's `handle_back()` first, then pops, quits at depth 1 | `func load_settings(`, `func save_settings(`, `func set_lang(`, `func set_fig(`, `func touch_active(`, `func push(`, `func replace(`, `func pop(`, `func current(`, `func back(` | ui/ (owner), app/ |
| `app/log.gd` | **`Log`** autoload: ring buffer of the last 500 lines, `info/warn/error`, `dump()` for the "copy log" button; `echo = false` silences the console (tests) | `const CAPACITY := 500`, `func dump(` | app/ |
| `app/clock.gd` | **`Clock`** autoload: the one tick source for view timers; `now_ms()`, `frozen`, `step(ms)`; no signal, no per-frame work (computed on read from `Time.get_ticks_msec()`) | `func now_ms(`, `func set_frozen(` | app/ |
| `ui/i18n.gd` | **`I18n`** autoload: Thai keys → English; lookup order `EN` (in the script) → `ui/i18n_extra.json` (+ the fragments `ui/i18n/{menu,hall,battle}.json`, merged after it without overwriting a key) → `data/i18n_en.json`; `t(th)`, `lookup`, `has_key`, `missing(keys)`; dictionaries load in `_init()`; `t` matches whole strings only (translate the template, then `format`); only files listed in `FRAGMENTS` load, and the lint and `test_i18n_fragments` fail on any other file in `ui/i18n/` | `const EN`, `const FRAGMENTS`, `func t(`, `func lookup(` | ui/ |
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
| `tools/validate_data.py` | the data lint CI runs: schemas, banned names of AGENTS rule 1 over `godot/` (legacy tokens hashed in `data/schema/legacy_tokens.sha1`), Thai→English in `ui/**` and `app/**` (every Thai literal a whole key; a `ui/i18n/*.json` not in `I18n.FRAGMENTS` fails), TYPES append-only, dice ≤ 60, secrets guard; `--fixtures`, `--write-version` | `def check_schema(`, `def banned_hits(`, `def thai_display_strings(` | tools |
| `tools/gen_bt_data.py`, `docs/DATA.md` | datasheet payload for the server; the layout-JSON schema and the DM act vocabulary | — | tools |
| `tools/record_oracle.js`, `tests/oracle/` | Playwright recorder of the old page (`window.BT`), 20 gzipped recordings, `check_oracle.mjs`, format in `tests/oracle/README.md` | `function writeRecording(`, `function pageActCodes(` | tools |
| `tools/godot.sh`, `tools/kits.sh`, `tests/selftest.gd` | pinned Godot download with SHA-512 checks; one command for kits + bakes; the self-test the Windows smoke job runs inside the exported exe (`override.cfg` → `run/main_loop_type="SelfTest"`) | `sha512_for()`, `func _run(` | CI |
| `assets/kits_import/kit_post_import.gd` | EditorScenePostImport applied through `[importer_defaults]`: one merged surface per kit, `COLOR` = kit colour, `CUSTOM0` = (paintable flag, palette index), skin kept; contract in `assets/kits/CONTRACT.md` | `func _post_import(`, `func _merge(`, `func _flatten(` | table/figures |
| `assets/shaders/figure.gdshader`, `figure_material.tres` | the figure material: kit colours, optional paint table (`paint_tex` rows, `paint_row` or `INSTANCE_CUSTOM.x`), per-vertex shading switch, `mask_out` for the impostor bake; no team dye (team = ring) | `uniform sampler2D paint_tex`, `uniform int paint_row`, `uniform bool per_vertex` | table/figures |
| `tools/bake_impostors.gd`, `assets/impostors/` (generated) | 16 yaw × 2 pitch per kit into `<kit>.png` + `<kit>_m.png` + `impostors.json` (15 s for 312 kits) | `func _bake_kit(` | table/figures |
| `tools/bake_anim.js` → `assets/anim/clips.json` (generated) | Playwright on the old page: samples SKRIG.Controller / idlePose / WALKER and the battle table's actions (window.BT) at 30 Hz into clips (local rotation of all 23 joints + pelvis translation per frame, contact flags, speed, travel, turn, events); fits the gear the page turns by itself into the hand / forearm bones; per-kit `holds`; measures every clip against the page's own drawing (`fidelity`); ride walk / run of the rigged mounts (legs re-solved onto planted hooves, loop cross-faded); `--check` validates | `function pageLib(`, `function cycle(`, `function gearFix(`, `function holds(`, `function fidelityOf(`, `async function rideClips(`, `function validate(` | tools |
| `tools/mount_rig.js` | shared by export_kits.js and bake_anim.js: finds the parts of a mount the page moves with travel (rigid groups of faces, pivots, the tree, the legs, the page's stride and leg phases), the gait plan and the two-bone IK | `function findParts(`, `function buildTree(`, `function buildRig(`, `function planGait(`, `function ik2(` | tools |
| `tools/bake_anim.gd` → `assets/anim/humanoid.res` (generated) | clips.json → one `AnimationLibrary` (tracks `Skeleton3D:<bone>`; metadata per clip; library meta `holds`, `proofs`); `assets/anim/CLIPS.md` is the contract | `static func build_library(`, `static func clip_to_animation(` | tools |
| `scenes/main.tscn` + `main.gd` | the root: World + UI ScreenStack + Overlay; first-run level guess (mobile → lo, ≤ 2 GB → min); pushes the main menu (`ui/screens/main_menu.tscn`) as the first screen. The World's `BattleTable` has `auto_build = false` and stays hidden with processing disabled until the GPU check or a battle shows it | `static func guess_level(`, `const MAIN_MENU` | table + ui |
| `scenes/battle_table.tscn`, `table/table_view.gd` | the battle table look: camera rig, sun, environment, terrain, props, figures, rings; applies the graphics level. The field comes from `core/field` for a setup (`DEFAULT_SETUP`: seed 1, 48", ruin, hills, buildings, density x1): `FieldTerrain.make` → `FieldProps.generate` (it levels the ground, so props before the mesh) → terrain mesh → props; `rebuild(setup)` builds another setup; `counts()` has `props` (drawn) and `field_props` (rules). Battle mode (the marked block `# ---- โต๊ะรบจริง (LOBBY_SPEC §4) ----` at the end): `build_battle(st)` builds the rules' field and one figure per `st.units` entry with its team ring and owner-tinted objective rings, `sync_battle(st)` redraws figures and rings from `st` (kits at most every 250 ms), `fig_unit`/`unit_fig`, `show_selection`, `show_dest`, `end_battle`; `figure_style` ("" = follow `App.fig`) and `effective_style()` (kit falls back to egg without kits on disk); `signal picked(fig, ground)` from taps | `const DEFAULT_SETUP`, `func build_look(`, `func rebuild(`, `func setup(`, `func apply_level(`, `func set_stress(`, `func counts(`, `func build_battle(`, `func sync_battle(`, `func effective_style(`, `signal picked(` | table |
| `table/terrain_mesh.gd` | the field mesh from `FieldTerrain.hg` after levelling (MI/1000 = metres, 1 game inch = 1 m; vertices on the rules grid every `cell_mi`, clipped to the table edge), one ArrayMesh with vertex colours per theme (`themes.json`), height and slope, plus rails that follow the edge profile and a dark skirt; `height_at` is the rules' bilinear in floats; grid step 2 on min | `func build(`, `func height_at(`, `static func axis_nodes(`, `func _rails(` | table |
| `table/props_layer.gd` | `FieldProps.items` drawn as one MultiMesh per kind (x, z, `rot`/65536 rad, `s`/1000, on the levelled ground); low-poly meshes built from the rules footprints (`bld_size` for buildings, `foot_of` where defined, `rad_of` otherwise; `footprint()`), cached per kind and detail; `blocked_at` uses the same footprints; simplified meshes on lo/min | `static func footprint(`, `static func kind_mesh(`, `func blocked_at(`, `func multimesh_of(`, `func set_simplified(` | table |
| `table/sky.gd`, `assets/shaders/sky.gdshader` | `TableSky`: the background per theme from `data/sky.json`: a flat gradient sky shader (sky, plain in haze below the horizon, sun glow); the skyline (city, treeline, dunes, peaks; the page's `panoOf`) as a 720x1 height texture on mid/hi only; lo has no skyline; min is one flat colour (no sky pass) | `func apply(`, `static func pano(`, `uniform bool skyline_on` | table |
| `table/rings.gd` | ONE MultiMesh of ground rings: the team ring under every figure, selection/destination/objective rings by kind | `func add_ring(`, `func set_colour(`, `func add_kind(` | table |
| `table/figures/figure_pool.gd` | tiers: skinned kit scenes near, per-kit MultiMesh (merged mesh, white instance colours, custom x = paint row) elsewhere; per-level skinned caps and runtime LODs on lo/min. Style switch `STYLES` = egg / kit: in egg mode `build()` makes one MultiMesh per egg size class (`Egg_<class>`, yaw + uniform R scale, the shared figure material, nothing skinned) and the kit path is untouched | `static func make(`, `func build(`, `func apply_level(`, `func set_style(`, `func _build_eggs(`, `_figure_material` | table/figures |
| `tools/ruin_kit.gd` | R1-V5 gothic ruin kit, our own design (no model files, textures or marks): low-poly pieces with vertex colours into ONE SurfaceTool (one surface = one draw call); lod 0 = hi (cut-out pointed-arch windows via Geometry2D strips, rose window, fluted pillars with brass bands, hood mouldings, masonry blocks), lod 1 = lo (solid walls with dark window quads, fewer flutes and pieces); per-piece seeds so hi and lo share the outline | `func wall(`, `func arch_hole(`, `func steps(`, `func rose(`, `func pillar(`, `func slab(`, `func stair(`, `func rubble(`, `func statue(`, `func panel(`, `func pipe(` | table (props) |
| `tools/ruin_sample.gd`, `assets/props/ruin/sample_building_hi.res` + `_lo.res` | the ONE sample building for the owner: two storeys inside `FieldProps.bld_size` (s = 1000, h = 45000, field seed 30 → 9.81 × 8.04 m) + the 0.6 m pad, hi ≤ 6,000 / lo ≤ 1,500 triangles; saves both meshes and renders `tests/out/ruin_sample_{front,corner,top,lo}.png` under xvfb with the app's Sun and ruin sky (`--headless`: build + save only); `tests/unit/test_ruin_kit.gd` checks budgets, footprint, determinism and that the committed `.res` match | `static func build_mesh(`, `static func assemble(`, `static func footprint(`, `const SHOTS` | table (props) |
| `table/camera_rig.gd` | `CameraRig`: pan / pinch / orbit / wheel / WASD, fit-table, pitch clamps, tap-vs-drag; when the table is disabled (`NOTIFICATION_DISABLED`) it forgets held keys, fingers and drags (`reset_input`) and gives up the current camera | `class_name CameraRig`, `func reset_input(` | table |
| `ui/screens/gpu_check.tscn` + `.gd` | the GPU-check screen, reached from Settings (`%GpuCheckButton`): adapter, GL version, fps, draw calls, primitives, memory, level picker (render scale + shadows live), stress toggle, Thai LineEdit for the IME, copy button, Thai/English, "‹ กลับ", the "จัดกองทัพ ›" button (`army_requested`, connected by Settings to push the army picker); on open it rebuilds the demo table at the user's level and shows it, on exit hides and disables it again | `func refresh(`, `func _on_level(`, `func _on_copy(`, `signal army_requested` | ui |
| `ui/screens/army.tscn` + `army.gd` | the army picker (R1-V4), pushed by the deck's armoury station, by Settings → GPU check → "จัดกองทัพ ›" and by `scenes/main.gd` `open_army()`: 15 army buttons, a datasheet card per listed unit (stats boxes, weapon table, keywords, abilities, knight chapter headings), −/+ per squad, budget stepper over `BUDGETS`, points bar and status, random army, preview turntable, Thai/English; hides the 3D table while open; no `_process` | `func select_army(`, `func select_unit(`, `func add_unit(`, `func random_army(`, `func listed_units(` | ui |
| `ui/screens/army_roster.gd` | `ArmyRoster` (RefCounted): squads per TYPES slot (the wire list), army, budget; `units_of(fac)` never lists a hidden unit; the simple seeded pick on the `armies` stream from `GameData.pool` (not the rules' autoList, which comes with `core/battle/army.gd`) | `static func units_of(`, `func random_fill(`, `func points(`, `static func budgets(` | ui |
| `ui/widgets/datasheet_text.gd` | `DatasheetText`: every text of a datasheet card in the page's wording (`abilityText`, `wpnLine`), translated as whole sentences then filled (`tf`); reaches I18n through the tree so `-s` scripts can use it | `static func stats(`, `static func weapon_row(`, `static func abilities(`, `static func tf(` | ui |
| `ui/widgets/kit_turntable.gd` | `KitTurntable` (SubViewportContainer, own World3D): one kit in its own colours on a plinth, slow spin, drag to turn; on min no spin and one redraw per change | `func show_kit(`, `func set_level(`, `const SPIN` | ui |
| `tests/render/test_lineup.gd`, `test_budgets.gd`, `test_main_screens.gd`, `test_field_look.gd`, `test_army_screen.gd` | xvfb suites: every kit imported right + one draw call per figure + paint override; the §6 budgets per level on the 400-figure scene, for the default field and for the densest one (`DENSE_SETUP`, 480 props = `PROP_CAP`); the main screens in Thai and English (no Thai left in English mode); the field look: 4 themes x 4 terrains at 640x360 (`field_<theme>_<terrain>.png`) + a low sky view per theme, drawn props == `FieldProps.items`, mesh heights == field heights at the grid points, props at their rules spot/rot/scale, meshes fill their footprints, the default setup's digests == `core/field`'s; the army picker for all 15 armies in Thai and English (no hidden unit, points, seeded random, turntable, 44 px targets; `army_<fac>_th.png`, `army_en.png`) | `func _render_army(`, `func _check(`, `func _thai_in(`, `func _check_field(`, `func _check_heights(`, `func _check_every_army(` | table + ui |
| `tests/unit/test_army_roster.gd` | headless: rosters per army without hidden units, points and budget steps, the seeded pick, English for every datasheet text, every Thai literal of the army screen files a whole I18n key | `func test_` | ui |
| `tests/render/test_anim_footslide.gd` | the clips on imported kits moving at the clip's speed (motion_scale = kit scale): planted-foot slide ≤ 15 mm on the humanoid, the page's walker and the biggest walker, the horse's hooves and every other ride clip (mount bones in the skeleton, loops close), wrong-speed controls, the holds; with a display `tests/out/anim_walk_*.png` strips and `anim_actions_*.png` sheets; `apply_holds` is the reference of the holds layer | `func slide(`, `func mount_slide(`, `func _ride_loops(`, `static func apply_holds(`, `static func planted(` | tools + table/figures |

Still planned (ARCHITECTURE §1): `core/field/`, `core/battle/` (R1), the Worker room client in `net/` (R3; the LAN room is in, §1.4), `app/audio.gd` (R2), `app/selftest.gd` screen (R1), `tests/golden/`, `tests/net/`, `core/dnd/` (R4+).

### 1.3 Front page, walkable lobby and games against bots (12 Nov 2026, `godot/docs/LOBBY_SPEC.md`, APP_VER ใหม่ 0.4; the deck: `godot/docs/SHIP_LOBBY_SPEC.md`; the arena: `godot/docs/ARENA_SPEC.md`)

Flow: `main.tscn` → main menu → เล่นกับบอท → the lobby **hall** (walk with WASD / arrows, Shift runs; an on-screen stick
on phones) → walk to a station and press E (or tap the use button) → battle setup → START (`App.replace`) → the battle
with egg placeholders → end panel → กลับล็อบบี้ (`App.pop`) → the hall. In code the walkable lobby is called **hall**; the
name `ui/screens/lobby.tscn` stays reserved for the online room screen (R3). Screens covered by a push hide their 3D,
disable processing and give up the camera on `visibility_changed`, and re-read `App.gfx` / `lang` / `touch` / `fig`
when shown again, so Settings never reaches into a live 3D scene. Cross-screen references use `load(PATH)` at use time.

| File | What | Anchors | Track |
| --- | --- | --- | --- |
| `ui/theme/candle_style.gd` | `CandleStyle`: the candle-lit palette (BG, PANEL, EDGE, GOLD, TEXT, MUTED, DANGER), buttons, panels, titles, toggle groups, safe-area margins, dropdown popups with rows of at least 48 px (`popup`) | `static func button(`, `static func popup(`, `static func toggle_group(`, `static func safe_margins(` | ui |
| `ui/widgets/title_art.gd` | `TitleArt`: the main menu's art drawn from shapes (gradient, wooden table, five candles, layered flames, glow; our own design); flicker on a Timer ≤ 6 Hz on hi/mid only, drawn once on lo/min | `func set_level(`, `func set_active(` | ui |
| `ui/screens/main_menu.tscn` + `.gd` | the first screen: `%PlayButton` (pushes the hall), `%OnlineButton` (the deck at the docking airlock, then the play-with-friends screen, §1.4), `%SettingsButton`, `LangButton`, `%QuitButton` (desktop only), `%VersionLabel`; Back/Esc opens the quit confirm; re-applies the level's frame cap and idle mode on show | `func open_hall(`, `func handle_back(`, `static func version_text(` | ui |
| `ui/screens/settings.tscn` + `.gd` | Settings: language, graphics level (`%GfxHi/Mid/Lo/Min`), figure style (`%FigEgg` / `%FigKit`, kit disabled without kits on disk), touch controls (`%TouchAuto/On/Off`), `%GpuCheckButton`; every change calls the App setter and saves | `func set_fig(`, `func set_touch(`, `func open_gpu_check(` | ui |
| `ui/i18n/menu.json`, `hall.json`, `battle.json` | the English of every new Thai string, one fragment per screen group (flat Thai → English); a key may live in one source only (`test_i18n_fragments`) | — | ui |
| `scenes/hall/hall_layout.gd` | `HallLayout` (pure data, no Thai): the 24 × 16 m warship deck (ใหม่ 0.3), 8 station rects + reach (`battle`, `army`, `settings`, `online` on the right wall, `adventure`, `exit`, `vault`, and since 0.4 `arena`, the arena door in the front wall left of the exit: `ARENA_DOOR`, `ARENA_RETURN`, `in_arena_doorway`), pillars, candle stands, banners, the viewport `WINDOWS`, `VAULT_PROFILE`, wall `SCREENS`, `COOL_LIGHTS`, `TITLE_SIGN`, flames (26 / 12 on min), spawn (0, 0, 5), `station_at` (nearest wins), blockers (walls/ceiling on `SHELL_LAYER`, props on `PROP_LAYER`), the camera's clearance along its ray (`room_clear`, `camera_clear`) | `const STATIONS`, `const WINDOWS`, `const COOL_LIGHTS`, `const SPAWN`, `static func station_at(`, `static func blockers(`, `static func camera_clear(` | lobby |
| `scenes/hall/hall_builder.gd` | `HallBuilder`: the deck's static geometry in 3 ArrayMeshes (shell with vaults, ribs, viewport lancets and reveals; furniture: holo war table, armoury, console, chart table, treasure chest; cloth), unshaded vertex colours with candle and cool glow baked in once (`bake`; empty cool list = `lit()`), `holo_mesh(level)`, the flame mesh, the avatar egg mesh, `StaticBody3D` colliders from `HallLayout` | `static func meshes(`, `static func bake(`, `static func holo_mesh(`, `static func avatar_mesh(`, `static func build_colliders(` | lobby |
| `scenes/hall/hall_space.gd` | `HallSpace` (pure meshes, no Node, no Thai): the space seen through the viewport: dome (r 42) with nebula, stars, planet and moon with baked sunlight as one static mesh per level (cached), our own distant-ship mesh and `ship_instances(level)` (5 / 3 / 3 / 0); `holo.gdshader` and `ship_drift.gdshader` move things on hi/mid only | `static func mesh(`, `static func ship_mesh(`, `static func ship_instances(` | lobby |
| `scenes/hall/hall_world.tscn` + `hall_world.gd` | `HallWorld`: the deck's 3D root (group `gfx_level`): 4 static meshes (`Shell`, `Furniture`, `Cloth`, `Space`), avatar, camera rig, flames MultiMesh (`flame.gdshader` flicker on hi/mid), `Holo` (flicker shader on hi/mid, plain on lo/min), `Ships` MultiMesh (drift on hi/mid, parked on lo, hidden on min), Label3D signs (7 stations + `title`), rings, an `Environment` on the hall camera (no lights, no shadows); `apply_level`, `set_active`, `set_sign_text`, `station()`, `counts()`; fades the avatar while the camera arm is squeezed | `func apply_level(`, `func set_active(`, `func set_sign_text(`, `func counts(` | lobby |
| `scenes/hall/hall_avatar.gd` | `HallAvatar` (CharacterBody3D, floating): walk 3 m/s, run 6 m/s, camera-relative, `move_and_slide`; `_physics_process` only while moving or easing to a stop | `func input_vector(`, `func set_stick(`, `func place(` | lobby |
| `scenes/hall/hall_camera.gd` | `HallCamera`: follows the avatar with a `SpringArm3D` on walls and ceiling only; props pull the camera only when its point would be inside one (`HallLayout.camera_clear`), the arm extends back at most 4 m/s; mouse/touch orbit, wheel/pinch zoom; `_process` only while easing | `func set_view(`, `func clear_at(`, `func forward_flat(`, `func right_flat(` | lobby |
| `ui/screens/hall_screen.tscn` + `.gd` | the hall HUD (root ignores the mouse so drags reach the camera): `%MenuButton`, `%SettingsButton`, `%UseButton` ("{name} · กด E" / "{name} · แตะเพื่อใช้"), `%Hint`, `%SoonPanel`, `%Stick`; `use_station()` pushes setup / the army picker / Settings or shows coming soon (airlock, adventure table, and the vault: the treasure chest for the future random rewards, no reward logic yet); `PLACE` goes to the title plaque; every hall Thai string lives here; the arena door: walking into the doorway or E fades and pushes the arena screen (`enter_arena`), reaching the door starts loading the arena's heavy files on a thread (`preload_arena`, kept for later entries), coming back places the avatar at `ARENA_RETURN` | `func use_station(`, `func refresh(`, `func handle_back(`, `signal station_changed(`, `func enter_arena(`, `func preload_arena(` | lobby |
| `ui/widgets/touch_stick.gd` | `TouchStick`: the on-screen stick (base 90 px, dead zone 0.15, past 0.85 runs), own finger index, `changed(v)`; nothing per frame | `signal changed(`, `func release(` | lobby |
| `table/figures/egg_shapes.gd` | `EggShapes`: the placeholder figures: base radius R as the kit exporter's `baseR`, 7 size classes from `data/types.json` (titan, giant, vehicle, infantry, big, cavalry, walker), a lathe egg per class with a facing nub, simple (≤ 64 tris) and full (≤ 160) meshes cached | `static func base_r(`, `static func class_of(`, `static func mesh(` | battle |
| `ui/battle/seat_plan.gd` | `SeatPlan` (pure): setup choices → the exact `Battle.make` setup + typed seats (every seat's list from `BtArmy.auto_list` on a scratch state; a random army from the `lobby:fac:<k>` stream), validation codes and their text, `with_seed` for เล่นอีกครั้ง | `static func build(`, `static func validate(`, `static func error_text(` | battle |
| `ui/battle/match_runner.gd` | `MatchRunner`: the only bridge from the screen to the rules: `Rec` catches every event, `step()` pumps bots / pending / phase ends, the human's acts (`move`, `advance`, `stay`, `skip`, `shoot`, `charge`, `end_phase`) go through `Battle.apply`; the charge gate is the core's `BtCombat.charge_gate` and `select_why` gives the core's reason for a refused tap; `auto_step()` plays the human seat with the bot's own policy; `run_to_end` for tests | `func step(`, `func can_select(`, `func end_phase(`, `func auto_step(`, `func replayed_digest(` | battle |
| `ui/battle/battle_text.gd` | `BattleText`: why-not keys, log lines (dice as digits, deaths per step), turn label, end titles and reasons, in Thai and English | `static func why(`, `static func lines(`, `static func end_title(` | battle |
| `ui/screens/battle_setup.tscn` + `.gd` | battle setup (root is a `Node2D`, because `set_size` / `set_theme` would clash with Control's own methods): teams 2–4 × 1–2 seats (≤ 6), army per seat (15 + random), you / bot (one human seat), table size, theme, terrain, goal (objectives with 3–10 rounds, or to the last team), points, seed; START is disabled while there are errors | `func set_seat(`, `func set_size(`, `func errors(`, `func start(` | battle |
| `ui/screens/battle_screen.tscn` + `.gd` | the battle: the shared table in battle mode, a Timer-paced `runner.step()` (stops while waiting for the human, so nothing runs per frame), HUD (turn label, VP chips, squad card, hints, action buttons, `%DoneButton`, `%AutoButton` ให้บอทเล่นแทน, speed, 8-line log), tap logic, leave confirm, end panel (กลับล็อบบี้ / เล่นอีกครั้ง / ดูสนาม) | `func begin(`, `func set_speed(`, `func is_over(`, `func handle_back(` | battle |
| `tests/flow/test_lobby_flow.gd`, `test_settings_flow.gd`, `test_hall_reach.gd` | headless flows across all screens: menu → hall → hold W to the war table → E → setup → bot game with eggs → end → hall → Esc; Settings from the hall (English, lo, touch on, old models) reaching the hall, setup, battle and end panel, then back to Thai / mid / eggs; and every one of the deck's 7 stations reached on foot from the spawn with the real colliders (stick steered along a free grid path), then the treasure chest's coming-soon panel in Thai / English and Esc | `func _run(` | tests |
| `tests/unit/test_i18n_fragments.gd`, `test_input_map.gd`, `test_menu_text.gd`, `test_hall_layout.gd`, `test_hall_space.gd`, `test_hall_text.gd`, `test_egg_shapes.gd`, `test_seat_plan.gd`, `test_match_runner.gd`, `test_battle_text.gd`, `test_table_style.gd` | unit suites of the new modules (`test_table_style`: a saved kit style with no kits on disk falls back to eggs), including a whole-key test per track (every Thai literal of its files is an I18n key) | `func test_` | per track |
| `tests/render/test_menu_screens.gd`, `test_hall.gd`, `test_battle_screen.gd` (+ egg phases in `test_budgets.gd`) | xvfb suites: the screens at 640x360 / 1280x720 / 1280x576 in Thai and English (no overflow, no overlap, 44 px targets, no Thai in English mode), movement and walls, camera inside the hall, stations (the vault panel in Thai / English, Esc, walk away, touch use button), touch stick, per-level budgets (hall on min ≤ 40 draw calls / 40k primitives, deck target ≤ 30 / 30k, also in the phone layout's worst view), ships / holo / stars per level, no ShaderMaterial on lo/min, no hole into the void (magenta background, 96 views), nothing processing while idle on min, a bot game and a human game with eggs, kits when `App.fig` is kit | `func _check(` | per track |

**Weapons arena (13 Nov 2026, ใหม่ 0.4, `godot/docs/ARENA_SPEC.md`; as built in its §17).** A separate screen pushed from
the deck's arena door with a short fade: a 10 m corridor (walk mode, deck controls) into a 20 × 24 m test range where the
egg draws its rifle and the game becomes a third-person shooter (shoulder camera, crosshair, rifle / punch / saw sword),
one enemy, the hive beast (สัตว์รัง, the `warrior` kit with its baked clips), a bot switch (shoot it or E), a reset button
and a status board. Player and enemy figures are swappable through a private pack (`res://packs/arena/pack.json`,
git-ignored) behind the figure contract (§9.1). Local single-player: seeded RNG for repeatable tests, not a rules change.

| File | What | Anchors | Track |
| --- | --- | --- | --- |
| `scenes/arena/arena_layout.gd` | `ArenaLayout` (pure data, no Thai): corridor, arch, room, pillars, stands, stations (`switch`, `reset`), board, signs, cool lights, `SPAWN` / `RESPAWN` / `BEAST_SPAWN`, blockers with a `shell` / `prop` layer, `mode_for` (walk ↔ shoot with hysteresis), `leaving`, `in_room`, `inside_solid` | `const STATIONS`, `const SIGNS`, `static func blockers(`, `static func mode_for(`, `static func in_room(` | arena |
| `scenes/arena/arena_builder.gd` | `ArenaBuilder`: the corridor and room in the deck's language (2 static meshes cached per side count, baked vertex light), the switch plate, the beacon dome | `static func meshes(`, `static func plate_mesh(`, `static func beacon_mesh(` | arena |
| `scenes/arena/arena_world.tscn` + `arena_world.gd` | `ArenaWorld` (group `gfx_level`): meshes, flames, switch head, beacon (`beacon.gdshader` spin on hi/mid), colliders, signs (text from the screen), rings; spawns the player and the beast (`ArenaActors.make_figure`), walk/shoot mode from the player's position, the beast hunts only a player in the room in shoot mode, `toggle_bot` (E: 1 s cooldown; plate hits: once per burst via `ArenaState.plate_hit`), `reset_range`, `hit_target`, `melee_targets`, `stats`, `counts`; re-checks the red crosshair when the beast moves, changes state or the range resets | `func toggle_bot(`, `func reset_range(`, `func hit_target(`, `func _update_target(`, `func counts(` | arena |
| `scenes/arena/arena_state.gd` | `ArenaState` (pure): bot switch, hit / damage counters, `toggle` (cooldown), `plate_hit` (a quiet second between bursts), `reset` (keeps the switch), `stats` | `func toggle(`, `func plate_hit(`, `func stats(` | arena |
| `scenes/arena/arena_actors.gd` | `ArenaActors`: the private pack loader (`resolve`, `make_figure`, `missing_api`, `enemy_name`, `pack_id`); a missing or broken pack falls back to the default figures with one warning | `static func make_figure(`, `static func missing_api(`, `static func enemy_name(` | arena |
| `scenes/arena/arena_player.tscn` + `arena_player.gd` | `ArenaPlayer` (CharacterBody3D, layer 2): walk / shoot modes, desktop input (mouse look while captured, `screen_relative`; fire, melee, reload, weapons) and touch (`set_stick`, `aim_drag`, `press`), the rifle's aim ray and muzzle ray, melee through `ArenaCombat`, damage, downed and revive, `refresh_aim`; physics only while something moves or counts down | `func set_mode(`, `func press(`, `func aim_ray(`, `func take_hit(`, `func refresh_aim(` | arena |
| `scenes/arena/arena_camera.gd` | `ArenaCamera`: follow camera in walk mode, shoulder camera in shoot mode (pivot +1.8 m, 0.9 m right, arm 3.0 m, FOV 65), spring arm on the shell, blend on hi/mid, kick and shake on hi/mid; settles within 2 cm | `static func shoulder_pivot(`, `func set_shoulder(`, `func set_view(`, `func look(` | arena |
| `scenes/arena/arena_weapons.gd` | `ArenaWeapons` (pure, fake time): rifle full-auto (reloads by itself when it runs dry with fire held), punch, saw sword, holster / draw, reload, events | `func tick(`, `func set_trigger(`, `func switch_to(`, `func held(` | arena |
| `scenes/arena/arena_fx.gd` | `ArenaFx`: tracers, muzzle flash and sparks in one MultiMesh (additive on hi/mid), seeded | `func shot(`, `func impact(` | arena |
| `scenes/arena/egg_gunner.gd` | `EggGunner`: the default player figure (team-colour egg, two floating gauntlets, our rifle and saw sword with the candle emblem), procedural clips | `func play(`, `func set_weapon(`, `func set_aim(` | arena |
| `ui/arena/arena_data.gd`, `ui/arena/arena_combat.gd` | `ArenaData`: every arena number (weapons, player, beast incl. `strike_at` and `poise`, range seed, numbers); `ArenaCombat`: the pure combat math (cones, damage, reactions, knockback) | `const WEAPONS`, `const BEAST`, `static func in_cone(`, `static func reaction(` | arena |
| `scenes/arena/hive_beast.tscn` + `hive_beast.gd`, `hive_ai.gd`, `arena_path.gd`, `kit_beast.gd`, `telegraph.gdshader` | `HiveBeast` (CharacterBody3D, layer 8) driving `HiveAI` (pure states: dummy, idle, chase, windup, strike, recover, hit with poise, dead), `ArenaPath` (A* on a 0.5 m grid, string-pulled), `KitBeast` (the `warrior` kit with the baked clips and the kit's hunch held, or a code-built beast egg); the telegraph is the claw's real reach (sector 2.6 m, ±70°) filling to its rim as the wind-up ends; asleep on its pad while the player is out of the room | `func take_hit(`, `func tick(`, `func on_damage(`, `func find(`, `static func telegraph_shape(` | arena |
| `ui/screens/arena_screen.tscn` + `.gd` | the arena screen: `%LobbyButton`, `%SettingsButton`, `%UseButton`, `%Toast`, `%PausePanel`, `%Fade`, the sign and board texts, toasts with the enemy's name, pause on Esc / focus loss / app paused; every arena-screen Thai string lives here | `func refresh(`, `func board_body(`, `func show_toast(`, `func handle_back(` | arena |
| `ui/widgets/arena_hud.gd`, `ui/widgets/arena_touch.gd` | `ArenaHud`: one batched `_draw` (crosshair with outline, bars, damage numbers: rifle hits merged, offsets fanned), `Ammo`, `Hint`, `Hurt` (edges in one draw), `Downed`; `ArenaTouch`: stick and four round buttons drawn from a 2-sprite atlas (Fire reads ยิง / ฟัน), invisible real Buttons for input | `func bind(`, `func numbers_alive(`, `func drawn_rects(`, `func update_weapon(` | arena |
| `ui/i18n/arena.json`, `arena_hud.json`, `arena_data.json` | the English of every arena Thai string (screen, HUD and touch, data labels) | — | arena |
| `tests/unit/test_arena_*.gd`, `test_hive_ai.gd` | layout, state (plate bursts), actors and packs, text (whole keys, no Thai under `scenes/arena/`), weapons (fake time), HUD text, combat, path, AI (poise) | `func test_` | arena |
| `tests/flow/test_arena_flow.gd` | menu → deck → walk into the arena door → corridor → shoot mode → kill the beast → reset → bot switch by a 1.5 s burst → the beast's claw → punch, saw sword → walk mode at the room edge is safe → downed and up, reset while downed → bot off → walk out → deck → enter again → back → Esc | `func _run(` | arena |
| `tests/render/test_arena.gd`, `test_arena_hud.gd`, `test_hive_beast.gd` | xvfb: entry timing, per-level table and budgets (overview, corridor, phone worst with numbers and the hurt edge), no void, camera never in a solid, signs (the switch sign above its beacon), fade, idle on min; the HUD and touch layout and input; the kit, clips, foot slide, telegraph shape and timing, reset during a wind-up, sleep on the pad, flash, death, levels, fallback | `func _check_` | arena |

### 1.4 Play with friends on the LAN (13 Nov 2026, `godot/docs/NET_SPEC.md`, APP_VER ใหม่ 0.5)

One player hosts on the local network, friends join by discovery or IP; friends walk on the deck; the battle runs in
lockstep over the deterministic core (only acts travel, digest checks, a bot plays a dropped seat). No server.

| File | What | Anchors | Track |
| --- | --- | --- | --- |
| `net/net_session.gd` | `NetSession` = autoload `Net`: the only socket owner (ENet server/client bound to IPv4, slots, members, HB, reconnect, version gate, rate limits, direction check before decoding, seated slots kept during a battle) | `func host(`, `func join(`, `func _host_auth(`, `func _pick_slot(`, `func _host_packet(`, `static func lan_addresses(` | net |
| `net/net_proto.gd`, `net/net_gate.gd`, `net/net_discovery.gd` | the message codec (kinds, schemas, caps, `clean_name`), the version gate and private-address check, UDP discovery (≤ 16 rows) | `static func decode(`, `static func from_member_ok(`, `static func check_hello(`, `func poll(` | net |
| `ui/battle/net_match_runner.gd`, `lockstep.gd`, `net_battle_link.gd`, `net_seats.gd` | the online runner (host sequencer, one-entry rolls for silent/gone friends, request budgets), the lockstep (gate, ACT queue, digests, desync), the link (START/RESYNC → battle screen, seat gone/back, `LEAVE`, wake Timer), seats and owners | `class NetRec`, `func _host_step(`, `static func gate(`, `func _on_members(`, `func client_left(` | battle |
| `ui/screens/lobby.tscn` + `.gd`, `ui/online_text.gd`, `ui/widgets/friend_tags.gd`, `scenes/hall/hall_friends.gd` | the airlock screen (host / list / IP / room card / seats), reason texts, name tags (glyphs the font lacks skipped), friends' eggs with interpolation | `func host_room(`, `func join_ip(`, `func _drawable(`, `static func interp(` | deck |
| `tests/flow/test_friends_flow.gd` + `tests/net/friends_peer.gd`; `test_lan_flow.gd` + `lan_peer.gd` | two Godot processes: the whole flow with the real UI; the session layer | `func _run(` | tests |

## 2. Autoloads — the only global state

Registered in `project.godot` in this order (an autoload's `_init()` runs in this order too): **`App`** (`app/app.gd`),
**`I18n`** (`ui/i18n.gd`), **`Log`** (`app/log.gd`), **`Clock`** (`app/clock.gd`), **`Net`** (`net/net_session.gd`, LAN
rooms, §1.4). ARCHITECTURE §3 adds `Audio` (R2). Nothing else is global; `core/` never touches them.

| Autoload | Read | Write / call |
| --- | --- | --- |
| `App` | `App.gfx`, `App.lang`, `App.snd`, `App.server`, `App.fig`, `App.touch`, `App.touch_active()`, `App.settings_file`, `App.current()`, `App.depth()` | `App.set_gfx("min")`, `App.set_lang("en")` (also sets `I18n.english`), `App.set_server(url)`, `App.set_fig("egg"\|"kit")`, `App.set_touch("auto"\|"on"\|"off")`, `App.save_settings()`, `App.push(packed_scene)` (hides the screen below), `App.replace(packed_scene)` (swaps the top screen; the one below never shows), `App.pop()`, `App.back()` (Android back / Esc: the top screen's `handle_back()` first, then pop, or quit at the first screen), `App.set_screen_root(node)` (main.tscn) |
| `I18n` | `I18n.english`, `I18n.t(th)`, `I18n.has_key(th)`, `I18n.missing(keys)` | `I18n.english = true` (prefer `App.set_lang`) |
| `Log` | `Log.lines()`, `Log.dump()`, `Log.size()` | `Log.info(msg)`, `Log.warn(msg)`, `Log.error(msg)`, `Log.clear()`, `Log.echo` |
| `Clock` | `Clock.now_ms()`, `Clock.frozen` | `Clock.frozen = true`, `Clock.step(ms)` (tests), never from rules code |
| `Net` | `Net.state()`, `Net.is_online()`, `Net.is_host()`, `Net.my_slot()`, `Net.members()`, `Net.found()`, `Net.local_ips()`, `Net.has_lan()`; signals `state_changed`, `members_changed`, `found_changed`, `message`, `pose`, `refused`, `lost`, `reconnected` | `Net.host()`, `Net.join(ip)`, `Net.leave()`, `Net.find(on)`, `Net.send(kind, body, to_slot)`, `Net.send_pose(p, stop)`, `Net.set_where(w)`, `Net.set_pick(fac)`, `Net.claim(k)`; idle offline (no socket, no Timer) |

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
bash godot/tests/run.sh                              # quick: --import + unit tests + the headless flow tests (tests/flow/test_*.gd)
bash godot/tests/run.sh full                         # quick + the oracle replay (ORACLE=all) + the render probe and every tests/render/test_*.gd under xvfb
bash godot/tests/run.sh i18n                         # unit scripts whose path contains the word (e.g. unit/core)
GODOT=$G TEST_OUT=/tmp/out bash godot/tests/run.sh   # the binary and the output folder (default godot/tests/out)

$G --headless --path godot --import                                  # after a checkout or an asset change
$G --headless --path godot -s tests/run_tests.gd [-- <word>]         # the unit + golden runner by itself
timeout 180 xvfb-run -a -s "-screen 0 1280x720x24" $G --path godot --rendering-driver opengl3 \
  --resolution 1280x720 --audio-driver Dummy -s tests/render_probe.gd   # the render probe by itself
... -s tests/render/test_<name>.gd                                       # any render suite by itself (run.sh full runs every one, sorted)
$G --headless --path godot --audio-driver Dummy -s tests/flow/test_lobby_flow.gd   # a flow test by itself (also test_settings_flow.gd)
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
- **Flow.** `tests/flow/test_*.gd` are `SceneTree` scripts that drive `scenes/main.tscn` headless through the real
  screens with `Input.parse_input_event` (physical keys) and button signals; they use a test settings file and print
  `PASS`/`FAIL` lines like the render suites. `run.sh` runs them in quick and full, CI in its own step.
- **Render.** `tests/render_probe.gd` and every suite under `tests/render/` need a display: xvfb + Mesa llvmpipe
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
