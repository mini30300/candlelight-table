# Figure packs — spec (player figure, enemy figure, deck figure)

Written 12 Nov 2026 on top of commit a8bbd31 (ใหม่ 0.4, the weapons arena; branch `claude/new-session-fsucoo`, draft
PR #27). It extends `ARENA_SPEC.md` §9 (the figure contract and the `ArenaActors` loader) from the arena to the warship
deck, and reserves a key for the army display. Everything in `ARENA_SPEC.md` still holds unless a section below changes
it by name. Line numbers are at a8bbd31 and drift; the quoted names are the anchors.

Words: this file says **figure pack**, **player figure**, **enemy figure**, **deck figure**. A pack is private and lives
outside this repo. Nothing here, in code, tests, commits or PR text, names or describes any private figure (AGENTS
rule 1; `ARENA_SPEC.md` §9.3). The fixture pack used by the tests is built from primitive shapes only.

**For the owner, in Thai:** เกมรุ่นสาธารณะเหมือนเดิมทุกอย่าง (ไข่บนดาดฟ้า ไข่ถือปืนในอารีน่า สัตว์รังจากชุดโมเดล).
ไฟล์นี้บอกว่า "ชุดตัวละครเสริม" (figure pack) ต้องหน้าตาแบบไหนถึงจะเสียบเข้าเกมได้ เกมรุ่นนี้จะเพิ่มแค่ "ช่องเสียบ"
เล็ก ๆ บนดาดฟ้า (ให้ตัวเดินบนดาดฟ้าเปลี่ยนได้ เหมือนที่อารีน่าเปลี่ยนได้แล้ว) และกันไม่ให้ไฟล์ส่วนตัวหลุดเข้าแอปสาธารณะ
ตัวละครจริงของมินิอยู่ใน repo ส่วนตัวเท่านั้น แล้วประกอบเป็นแอปรุ่นส่วนตัวแยกต่างหาก

---

## 0. Decisions this spec fixes

| Topic | Decision |
| --- | --- |
| Public builds | With no pack, every screen behaves exactly as at a8bbd31: egg on the deck, egg gunner and kit beast in the arena, kit files in the army display. Every existing test keeps its expectation (none is loosened). |
| Where a pack lives | One pack at a time, in **`res://packs/arena/`** with its manifest `res://packs/arena/pack.json` (`ArenaActors.PACK_MANIFEST`). For format 1 the folder name `arena` is part of the contract (the `<id>` folder of the lookup is always `arena`); the manifest's `id` names the pack. A second folder under `res://packs/` is ignored. Scanning several folders would change `ArenaActors` and its tests for no gain while only one pack exists. |
| What reads the pack | `ArenaActors` only (static, `RefCounted`). New callers: `HallWorld` (deck figure) and, optionally later, `KitTurntable` (army display). |
| Shipping | `godot/.gitignore` already ignores `packs/`, so a public checkout never has one. The public export presets also **exclude** `packs/*` (§5), so even a local public export from a tree that happens to hold a pack cannot carry it. Only a private build rewrites that filter. |
| Light | No lights are added anywhere (deck and arena keep black ambient and no `Light3D`). A pack figure brings its own unshaded material with its own light maths (§3.4). |
| Contract | The arena's twelve-method `FIGURE_API` is the only contract; the deck uses a subset of it plus the optional `set_fade` (§3). No new required method. |
| Format | Stays **1**. New keys are optional and a format-1 reader ignores keys it does not know, so old builds read new manifests safely. |
| Tests | A primitive fixture pack under `godot/tests/fixtures/figure_pack/` (§6) drives the new tests. Public tests never run with a real pack in the tree (they fail by design: three of them assert the public figures, §7). |

## 1. Lookup order

For each role the game asks `ArenaActors` once, when the scene that needs the figure is built:

| Role | Manifest key | Asked by | Fallback (no pack, no key, bad path, missing file, failed contract) |
| --- | --- | --- | --- |
| player figure | `player` | `ArenaWorld` (`arena_world.gd:138`) | `res://scenes/arena/egg_gunner.gd` (`ArenaActors.DEFAULT`) |
| enemy figure | `enemy` | `ArenaWorld` (`arena_world.gd:153`) | `res://scenes/arena/kit_beast.gd` |
| deck figure | `deck` | `HallWorld._ready` (new, §4 H2) | none: `make_figure("deck")` returns `null` (no `DEFAULT` entry) and `HallAvatar` keeps its egg |
| army display (reserved) | `army` → `{kit key: path}` | `KitTurntable.show_kit` (optional H5) | `KitLibrary.kit_path(kit)` (`res://assets/kits/<kit>.glb`) |

Steps, in order (`arena_actors.gd` `resolve` / `make_figure`, unchanged):

1. `res://packs/arena/pack.json` exists, parses as a JSON object and has `"format": 1`; else every role falls back.
2. The role's key is present; else that role falls back.
3. The path resolves inside `res://packs/arena/` (relative paths join the manifest's folder; `..` or a path leaving the
   folder is refused with one warning).
4. `ResourceLoader.exists(path)`; a missing file falls back with one warning. This lets a manifest name files that a
   build has not delivered yet.
5. The instance is a `Node3D` (`.tscn`/`.scn` → `instantiate()`, `.gd` → `new()`) with every method of `FIGURE_API`;
   else it is freed and the fallback is used, with one warning naming the missing methods.

"Bundled at export": whatever lies under `res://packs/` when a **private** build exports ships with it (§5); the public
presets exclude the folder.

## 2. `pack.json` (format 1, extended)

```json
{
  "format": 1,
  "id": "my_pack",
  "player": "player/figure.gd",
  "enemy": "enemy/figure.gd",
  "deck": "player/figure.gd",
  "enemy_name": {"th": "ชื่อไทย", "en": "English name"},
  "army": {"<kit key>": "army/<kit key>.tscn"}
}
```

| Key | Type | Since | Meaning |
| --- | --- | --- | --- |
| `format` | int, required | ARENA_SPEC §9.3 | must be `1` |
| `id` | string | §9.3 | the pack's name (`[a-z0-9_]`, ≤ 32 chars): world stats, logs, smoke reports |
| `player` | path | §9.3 | the arena's player figure (`.gd` or `.tscn`/`.scn`) |
| `enemy` | path | §9.3 | the arena's enemy figure |
| `enemy_name` | `{"th", "en"}` | §9.3 | both non-empty or it is ignored (AGENTS rule 4); board title, HUD bar, toast |
| `deck` | path | **this spec** | the deck figure. May be the same file as `player`: each call makes its own instance |
| `army` | object kit key → path | **this spec, reserved** | a display scene per unit kit key for the army screen's turntable. Ignored until the optional hook H5 lands |

Unknown keys are ignored. Every path follows the same folder rule. The figure script itself may `preload` anything
inside the pack; only the manifest's entry paths are checked by the loader.

## 3. The figure contract on the deck

The deck figure is a normal `FIGURE_API` figure (`ARENA_SPEC.md` §9.1). The deck calls only part of it:

| When | Call (by `HallAvatar` / `HallWorld`) |
| --- | --- |
| built (`HallWorld._ready`) | `setup({"role": &"deck", "level": l, "team_colour": c, "seed": 0})`, `set_weapon(&"none")`, `play(&"idle")` |
| every graphics change | `apply_level(l)` (`HallWorld.apply_level`) |
| every physics frame while the avatar moves | `set_move(speed, running)`: speed = horizontal speed in m/s (deck walk 3.0, run 6.0; `HallAvatar.WALK` / `RUN`), running = the run input |
| the avatar stops, `halt()`, `place()` | `set_move(0.0, false)` once |
| the camera arm is squeezed by a wall | `set_fade(a)` with a in [0.35, 1] when the figure has it (optional) |

Never called on the deck: `set_aim`, `set_flash`, `set_telegraph`, `muzzle`, `anchor`, `metrics` (the deck's capsule
stays r 0.35 × h 1.75, `hall_world.tscn`). `clip_event` is not listened to. A figure that does not know `&"deck"` must
treat every role other than `&"enemy"` as the player.

Optional, deck only: `deck_speeds() -> Vector2` (walk, run in m/s). When the deck figure has it, `HallAvatar` uses those
two speeds instead of `WALK` / `RUN`, each clamped to [0.5, 6.0], so a figure whose walk and run cycles were made for
slower speeds can show them without foot slide. The deck is not a balanced game space; the arena's speeds (`ArenaData`)
are never taken from a figure.

### 3.1 Conventions (all figures)

- Faces **+Z** at yaw 0; its right hand is **−X**; origin at the feet, floor at y = 0; metres. The owner node (`HallAvatar`,
  `ArenaPlayer`, `HiveBeast`) sets the figure's rotation; scale and offset baked into the figure root survive.
- Heights that frame well with the fixed capsules and cameras: player and deck figure 1.5–2.0 m (deck camera head 1.3 m,
  arena camera heads 1.3 / 1.8 m); enemy figure 1.8–2.4 m with `metrics().radius` 0.5–0.7 (the arena path grid needs
  radius + 0.1 between pillars).
- Gameplay timing never comes from clip lengths (`ArenaData`); a clip only has to look right at the times listed in
  `ARENA_SPEC.md` §6.6 and §8.1.
- `set_move` carries speed only. The figure picks idle / walk / run **from the speed it gets** and sets the playback rate
  so feet do not slide; the deck runs at 6.0 m/s, the arena at 5.0 m/s, so a fixed walk/run flag is not enough.

### 3.2 Per-frame and idle rules

- The deck and an idle arena process nothing after 10 idle frames (`SHIP_LOBBY_SPEC`, `ARENA_SPEC.md` §11.3). After
  `set_move(0.0, false)` an arena figure may keep an idle loop on hi / mid / lo; on **min** it must hold a still pose
  within 10 frames (`AnimationPlayer` paused or stopped, no `_process` / `_physics_process` left on).
- The **deck** figure (role `&"deck"`) holds that still pose within 10 frames on **lo and min**. Both levels run
  `low_processor_usage_mode` (`TableView.LEVELS` `"idle": true`), where the egg deck redraws nothing while the player
  stands; an idle loop would redraw the whole deck at 30 fps for as long as the player stands, on the level most phones
  get (`scenes/main.gd` `guess_level()`: lo). The arena is not affected: its public enemy's idle loop already keeps it
  drawing on lo (`ARENA_SPEC.md` §11.1).
- Any helper that follows the skeleton (attachments, secondary motion) runs from the `AnimationPlayer`'s
  `mixer_applied` signal (as `KitBeast._on_applied` does), never from an unconditional `_process`.
- When the deck is hidden under the arena screen it is disabled by the screen stack (`process_mode`), so the deck figure
  stops with it. Both the deck figure and the arena's player figure exist at the same time: cache meshes and materials
  in static variables of the figure script (as `EggGunner._mesh_cache`), never per instance.

### 3.3 Fade

`set_fade(1.0)` must leave the figure fully opaque with its opaque materials (no transparent pass at 1.0).
`HallWorld.avatar_alpha()` keeps its meaning (the value last computed in `_on_arm`, egg or figure), so
`test_arena_flow.gd:349-361` (`avatar_alpha() >= 0.999` after returning from the arena) stays as it is.

### 3.4 Look without lights

Deck and arena have black ambient and no `Light3D` (`hall_world.gd:100-105`, `arena_world.gd:106-111`). A lit
material renders black. A pack figure uses an **unshaded** material that computes its own light, like
`assets/shaders/figure.gdshader` (lambert sun + ambient, sRGB, no `TIME`, per-vertex on lo / min). To match the kit
beast in the arena use `KitBeast.SUN_DIR` (0.2, 1.0, 0.3), `SUN_COLOUR` (0.62, 0.64, 0.68), `AMBIENT` (0.34, 0.36, 0.42).
The compatibility renderer shows `ALBEDO` as is (no sRGB conversion) and ignores subsurface scattering. Hit flash and
telegraph tint should be one shader uniform, not a material swap per part.

### 3.5 Budgets a pack figure must fit

The public budgets stay as they are and a pack must fit inside them (`ARENA_SPEC.md` §11.2; deck targets
40 / 40 / 35 / 30 draws). The public figures cost 3 draws (player) + 1 draw (enemy) and a few thousand triangles. Targets
for one pack figure, to keep the measured headroom (arena overview on min measured at 21 of 30 draws):

| Level | Player / deck figure: draws, triangles (weapon included) | Enemy figure: draws, triangles |
| --- | --- | --- |
| hi | ≤ 4, ≤ 30k | ≤ 3, ≤ 25k |
| mid | ≤ 3, ≤ 20k | ≤ 2, ≤ 15k |
| lo | ≤ 3, ≤ 12k | ≤ 2, ≤ 9k |
| min | ≤ 3, ≤ 7k | ≤ 1–2, ≤ 5k |

In practice that means one skinned mesh per level baked offline into Godot resources (`.res`), materials merged, and
no geometry generated at run time. A muzzle flash is quads only, never an `OmniLight3D` (in the compatibility renderer
every omni light draws each lit mesh again).

## 4. Public code hooks (track PUBLIC-HOOKS)

All neutral; with no pack each hook is a no-op. Surgical edits only.

| # | File | Change |
| --- | --- | --- |
| H1 | `scenes/hall/hall_avatar.gd` | `var figure: Node3D` and `func set_figure(fig: Node3D, opts: Dictionary = {}) -> void`: `null` frees any previous figure and shows `$Egg`; otherwise hides `$Egg`, adds `fig` as child `Figure` (position and rotation zero), calls `setup` with `opts` + `"role": &"deck"`, `set_weapon(&"none")`, `play(&"idle")`, and reads the optional `deck_speeds()` (§3) into the walk and run speeds used by `_physics_process` (default `WALK` / `RUN`). In `_physics_process` call `figure.set_move(speed(), running())` instead of the egg bob when a figure is set (the bob stays for the egg). `_reset_pose()` (used by the stop branch, `halt()` and `place()`) calls `figure.set_move(0.0, false)`. |
| H2 | `scenes/hall/hall_world.gd` | After `avatar.moved.connect(...)` (`:109`): `avatar.set_figure(ArenaActors.make_figure("deck"), {"level": <the app's gfx level, as read for apply_level at :112>, "team_colour": team_colour, "seed": 0})`, through a new `HallWorld.set_figure(fig)` (it also applies the current fade; the render test swaps the fixture figure in and out with it). `apply_level` forwards `apply_level(l)` to `avatar.figure` when set. `_on_arm` computes `_alpha` exactly as now; with a figure it calls `set_fade(a)` when the figure has it, and touches the egg material only when there is no figure. |
| H3 | `ui/screens/hall_screen.gd` | `preload_arena` (`:289-296`) also appends `ArenaActors.resolve("player")` and `ArenaActors.resolve("enemy")`, so a pack figure loads on the thread at the door. Without a pack these are the default paths already in `ARENA_PRELOAD` and are skipped as duplicates. Both read `HallScreen.pack_manifest` (default `ArenaActors.PACK_MANIFEST`), which tests point at the fixture. |
| H4 | `export_presets.cfg` (both presets) and `tools/validate_data.py` | `exclude_filter="packs/*"` on Windows and Android. The data lint (which already checks the keystore fields of this file) fails when either preset's `exclude_filter` lacks `packs/*`, with a failing fixture `tests/data_fixtures/fail_pack_filter/` like the existing ones. |
| H5 (optional, not this round) | `scenes/arena/arena_actors.gd`, `ui/widgets/kit_turntable.gd` | `static func army_path(kit: String, manifest := PACK_MANIFEST) -> String`: the pack's display scene for a kit key (same folder rule, `PackedScene` only) or `""`. `KitTurntable.show_kit` tries it before `KitLibrary.kit_path`, frames a pack scene by its mesh box, and gets a `pack_manifest` variable that tests can point at the fixture. The battle table (`figure_pool.gd`) is never hooked. |
| H6 (optional; specified 13 Nov) | `scenes/arena/arena_player.gd`, `scenes/arena/egg_gunner.gd` | Optional `set_move_dir(local_dir: Vector2, speed: float, running: bool)`, called **instead of** `set_move` when the figure has it, so a player figure can choose side-step and back-step cycles in shoot mode. Exact rules: `ARENA_SPEC.md` §9.4 (with H7 `begin_switch` and the melee timing). |
| H8, H9 (optional; 13 Nov, H9 changed 14 Nov) | `scenes/arena/arena_player.gd`, `scenes/arena/egg_gunner.gd` | `begin_dodge(local_dir: Vector2, duration: float)`: called once when a dodge (Space / หลบ button) starts, direction in the figure's frame, `duration` 0.3 s; `uses_strafe() -> bool` (default true): every body faces the camera's yaw in both modes and is never turned toward its movement; false = the figure's legs get (0, 1) for forward and sideways movement and (0, −1) backwards (`ArenaCombat.leg_dir`, through H6 `set_move_dir` and H8 `begin_dodge`), so it walks forward while sliding sideways and backward when backing; true (the egg) gets the real direction and side-steps. Both checked once in `setup`. Exact rules: `ARENA_SPEC.md` §9.5. |
| H10 (optional; round C, 14 Nov) | any deck figure (pack figures, `scenes/hall/kit_walker.gd`) | `apply_scheme(primary: Color, secondary: Color) -> void`: the dressing room's colour scheme (§10). Called by `Figures.dress` after `setup` (the hall and pack-room worlds) and by the dressing screen's preview; a figure may also get it before `setup` and must keep it. Fixed-colour parts (weapons, gold trim, lenses, a special arm) are the figure's business and ignore it. A figure without it keeps its own colours; set `"schemes": true` in `figures.json` only when it has it. |

Spec cross-reference: one line under `ARENA_SPEC.md` §9.3 ("extended by `PACK_SPEC.md`"), and §17 (as built) notes H1–H4.
No `APP_VER` bump is needed for H1–H4 alone (nothing changes on screen without a pack); if it ships with other visible
changes, the usual Thai note in `web/` mentions "ช่องเสียบตัวละครเสริมบนดาดฟ้า (ไม่มีผลกับแอปปกติ)".

### 4.1 Tests for the hooks (same PR)

| Test | Checks |
| --- | --- |
| `tests/unit/test_figure_pack.gd` (new) | `make_figure("deck", NONE) == null`; with the arena fixture pack (no `deck` key) still `null`; with the figure fixture pack the deck figure is `prim_figure.gd` and passes `FIGURE_API`; the fixture's player and enemy resolve too; `enemy_name` reads its `{th, en}`; unknown keys (`army`) do not break format 1; the real manifest is still absent. Runs headless and inside the exported game (selftest). |
| `tests/unit/test_figure_pack.gd` (same file) | The fixture figure's own behaviour, so the fixture stays a fair stand-in: `set_move(1.0, false)` plays its walk clip, `set_move(4.5, true)` its run clip with a speed scale from the clip's `speed` meta, `set_move(0, false)` returns to idle and, after `apply_level("min")`, holds a still pose; as the deck figure it holds still on lo too, as an arena player it may loop there (§3.2). With the fixture's `deck_speeds()` = (1.5, 4.0) a deck walk reaches about 1.5 m/s and a run about 4.0 m/s (render test below). |
| `tests/unit/test_figure_pack.gd` (same file) | Broken deck entries (`tests/fixtures/figure_pack_bad/`: `pack.json` names a half-contract script, `missing.json` a file that is not there, `escape.json` a path leaving the folder): `make_figure("deck", X) == null` for each, so the deck keeps its egg; a pack with only a `deck` key leaves the arena figures public. |
| `tests/render/test_hall.gd` (added checks, no changed expectation) | Public deck: `avatar.figure == null` and `$Egg` visible on every level; `set_figure(make_figure("deck", <half-contract fixture>))` keeps the egg and the 3.0 / 6.0 speeds. Then `avatar.set_figure(ArenaActors.make_figure("deck", FIX), ...)`: the egg hides, the figure is a child of the avatar; walking with W calls `set_move` with speeds near the fixture's `deck_speeds()` walk 1.5 and Shift+W near its run 4.0; releasing sends one `set_move(0, false)`; `world.apply_level("min")` reaches the figure; a squeezed arm calls `set_fade(a < 1)` and a free arm `set_fade(1)` while `avatar_alpha()` follows the same numbers; standing on lo no `AnimationPlayer` under the avatar plays; after 10 idle frames on min nothing under the avatar processes; the deck budgets of the existing views still hold with the fixture figure (it is 1 draw). `set_figure(null)` restores the egg and the 3.0 / 6.0 speeds. |
| `tests/flow/test_hall_reach.gd` or `test_lobby_flow.gd` (added check) | The deck still enters, walks and leaves with no pack (`figure == null`), and `preload_arena` requests no extra path without a pack; with `pack_manifest` at the fixture it requests one more (the fixture's single figure script) and loads it on the thread. |
| `tools/validate_data.py` self-test | the `fail_pack_filter` fixture fails with the new message; the real presets pass. |

Unchanged on purpose (they guard the public build and must keep passing): `test_arena_actors.gd` (no pack in the repo,
fixture swaps), `test_arena_hud.gd:90` (the player is the egg gunner), `test_arena.gd` budgets, `test_hall.gd` budgets,
`test_arena_flow.gd` `avatar_alpha`.

## 5. Export: the pack ships only in a private build

| Preset field | Public value (this repo) | Private build (patched by its own CI before the import) |
| --- | --- | --- |
| `export_filter` | `all_resources` | same |
| `include_filter` | `assets/kits/kits.json, assets/sfx/sfx.json` | `assets/kits/kits.json, assets/sfx/sfx.json, packs/*` (raw files a pack reads with `FileAccess` ship too) |
| `exclude_filter` | **`packs/*`** (H4) | `""` |

How the filters work in Godot 4.7: `export_filter="all_resources"` collects every file the editor recognises under
`res://` (scripts, scenes, `.res`, imported meshes and textures, `.json`); `include_filter` adds matching non-resource
files; `exclude_filter` then removes matches, both checked against the path with and without `res://`, and `*`
matches across `/`. So `packs/*` covers every file of every pack folder.

Rules for a pack's files:
- Prefer baked Godot resources (`.res`, `.tscn`, imported `.glb`/`.png`) loaded with `load()`; they ship under
  `all_resources`. Raw files read with `FileAccess` ship only with the private `include_filter`.
- The scene post-import (`assets/kits_import/kit_post_import.gd`) returns any file outside `res://assets/kits/`
  untouched, so pack `.glb` files import raw (no LOD, no shadow mesh). Do not put a `.gdignore` in a pack.
- A pack declares no `class_name`, or prefixes it so it cannot clash with the public global classes.
- The data lint scans every file under `godot/`, `packs/` included when present. That is on purpose: a pack is never
  placed in the public working tree (§7).

### 5.1 Feature switches: `res://packs/features.json` (0.6)

Some features ship only in the private build. A private build drops one more file next to the pack folder:
`res://packs/features.json`, a JSON object of booleans, read once by `Features.on(name)` (`godot/app/features.gd`).

| Key | Off (the public app: no file) | On |
| --- | --- | --- |
| `online` | the main menu's online button is hidden; the deck's docking airlock is a coming-soon station again (sign "ประตูเทียบยาน · เร็วๆ นี้" / "Docking Airlock · Coming soon", its panel names the launch bay and play with friends; 0.8: decoration only, no ring, no prompt, no panel, the sign stays); `hall.open_online()` returns `null` | the online button and the airlock open the play-with-friends screen (NET_SPEC §7); 0.7: with a pack room for the airlock (§9) the airlock is a walk-in door into that room instead, and the online button lands in the room with host/join on top |

- Unknown keys and non-boolean values are ignored; a broken file is the same as no file (a warning, never a crash).
- Only the entry points are switched. The network code (`net/`, the `Net` autoload, lockstep, discovery) is unchanged and
  still fully tested: the friends tests (`tests/flow/test_friends_flow.gd`, `tests/net/friends_peer.gd`) and the render
  tests of the menu and the deck turn the switch on with `Features.set_flag(&"online", true)`.
- The private repo keeps the file at its root (`features.json`), its CI copies it to `public/godot/packs/features.json`
  beside `packs/arena/`, and its pack smoke checks `Features.on(&"online")`. The public tree never has `packs/`
  (`.gitignore`), so the public build can never turn a switch on by accident.
- Why online moved to the private build (owner, 13 Nov 2026): the online room is redesigned as a separate launch-bay room
  in the personal app, so it can be made to look right without worrying about the public build.
- Round B (owner, 14 Nov 2026): play with friends is back in the public app, on the deck only. The online button shows
  in every app and `hall.open_online()` / `main_menu.open_online()` no longer read the switch; `online` now only lets a
  pack room load (`PackRooms.for_door`). With no pack room the airlock has no ring in any app (SHIP_LOBBY_SPEC round B).

## 6. The fixture pack (primitives only)

`godot/tests/fixtures/figure_pack/` (a new shared folder: unit, flow and render tests all use it; it is outside
`tests/unit/`, so the runner does not mistake it for tests; it ships in the export like the other fixtures so the
selftest can read it):

| File | What |
| --- | --- |
| `pack.json` | `{"format": 1, "id": "prim_test", "player": "prim_figure.gd", "enemy": "prim_figure.gd", "deck": "prim_figure.gd", "enemy_name": {"th": "หุ่นทดสอบ", "en": "Test dummy"}, "army": {"warrior": "missing.tscn"}}` |
| `prim_figure.gd` | `extends Node3D`, no `class_name`, about 270 lines: one `MeshInstance3D` with a `CapsuleMesh` (1.7 m) and an unshaded `StandardMaterial3D` in `team_colour` (1 draw); a `Marker3D` muzzle at the right hand; an `AnimationPlayer` with an `AnimationLibrary` built in code (`idle` loop; `walk` loop with meta `speed` 1.5; `run` loop with meta `speed` 4.0; short `fire reload punch swing hit die attack hit_heavy` clips, each a position or rotation track on the capsule); all twelve `FIGURE_API` methods plus `set_fade` and `deck_speeds()` = (1.5, 4.0); and plain fields the tests read (`role`, `level`, `weapon`, `fade`, `last_move: Vector2(speed, running)`, `calls: Dictionary` name → count). |

`godot/tests/fixtures/figure_pack_bad/` holds three broken manifests for the deck fallback (§4.1): `pack.json` →
`half_figure.gd` (a `Node3D` with only `setup`, `play` and `set_move`), `missing.json` → `nobody.gd`, `escape.json` →
`../figure_pack/prim_figure.gd`.

No model files, no textures, no names of anything real.

## 7. Working with a real pack (any agent, any machine)

- Never copy a pack into this checkout's `godot/packs/`. Copy `godot/` to a scratch folder and put the pack there. The
  public tests fail with a pack present by design (`test_arena_actors.gd:24` and `:27`, `test_arena_hud.gd:90`, and the
  no-pack checks of `test_figure_pack.gd`, `test_hall.gd` and `test_hall_reach.gd`), and renders would hold private
  figures.
- Imports of such a copy run one at a time (a `flock` on a lock file next to it), `nice -n 10` for heavy runs.
- The private build runs its own smoke script and may run `tests/render/test_arena.gd` as a budget gate (that test
  asserts no figure type, only draws and primitives). `tests/render/test_hall.gd` cannot be that gate: it asserts the egg.
- Nothing from a private build (renders, logs, APKs, exe) goes into this repo, its CI, its releases or a public PR.

## 8. Tracks (three in all; none edits a file another owns)

| Track | Repo | Owns | Done when |
| --- | --- | --- | --- |
| **PUBLIC-HOOKS** | this repo | `scenes/hall/hall_avatar.gd`, `scenes/hall/hall_world.gd`, `ui/screens/hall_screen.gd`, `export_presets.cfg`, `tools/validate_data.py`, `tests/data_fixtures/fail_pack_filter/`, `tests/fixtures/figure_pack/**`, `tests/fixtures/figure_pack_bad/**`, `tests/unit/test_figure_pack.gd`, the added checks in `tests/render/test_hall.gd` and one flow test, the §9.3 pointer in `ARENA_SPEC.md` | H1–H4 with their tests; `bash godot/tests/run.sh full` green; draft PR on top of PR #27 |
| **Private tracks** (two: the player and deck figure; the enemy figure) | private | everything inside the pack and the private build | the private repo's own plan |

The two private tracks never touch this repo, and this repo never names them. The private pack's manifest can name
every role from the start: until a file exists, step 4 of §1 falls back to the public figure.

## 9. Pack rooms (0.7, 13 Nov 2026)

A pack may put one walk-in room behind a door of the deck. v1 has one door: the docking airlock (`"online"`). The room is
used only when `Features.on(&"online")` is on **and** a valid room exists; otherwise the deck is exactly as before.

- **Where**: `res://packs/rooms/<id>/room.json` (format 1) + one GDScript room script in the same folder.
  `PackRooms` (`scenes/hall/pack_rooms.gd`) lists and validates them (`list`, `for_door`, `validate`, `missing_api`);
  an invalid room is skipped with a warning, never a crash. Tests point the root elsewhere (`PackRooms.test_root`,
  `hall_screen.rooms_root`).
- **`room.json`**: `format` 1; `id` (`^[a-z][a-z0-9_]{0,23}$`, the folder name); `door` (`"online"`); `title` ≤ 40 and
  `door_sign` ≤ 48 as `{th, en}` (`en` without Thai letters); `script` (relative `.gd` inside the folder, no `..`);
  `half` `[x, z]` with x in [4, 15], z in [4, 20]; `ceil` in [3.5, 14] (invisible collision ceiling); `spawn`
  `[x, z, camera yaw]` (clear, in no station's reach); optional `bg` (6 hex); `stations`: 1–8 with unique ids and exactly
  one `"back"`. A station has `name {th, en}` ≤ 32, `c`, `h`, `round`, `height` 0.1–14, `reach` 0.8–2.5 (as
  `HallLayout.STATIONS`; the footprint may reach into the wall, never past it), `front` (clear, within reach), optional
  `sign [x, y, z]` + `face`, `action` = `soon` (`soon {th, en}` ≤ 120) / `cards` (1–4 cards: `title` ≤ 24, `text` ≤ 80,
  `action` `soon` + `soon`, or `online`) / `online` / `back`; `walk_in` (only on `back`: walking into it leaves);
  `solid` false = the footprint adds no blocker. Unknown keys are ignored. The test room
  `tests/fixtures/pack_rooms/test_room/room.json` is a complete example.
- **Room script contract** (`extends Node3D`, no `class_name`): required `setup(ctx)` (once, before the first frame;
  `ctx = {data, dir, level, english, team_colour}`; build meshes here, no lights, shadows, physics bodies, UI, network,
  `App`/`Net` calls), `apply_level(l)` (after setup and on every graphics change), `blockers() -> Array` (extra props
  in the `HallLayout.blockers()` format, room-local, inside the room, each with a non-empty String `tag` that is never
`wall_*` / `ceiling`, box `h` > 0 on every axis; one bad entry drops the whole list with a warning; if the list covers
the spawn or a station front the room is refused at open, `RoomLayout.clear_problems()`). Optional:
  `station_near(id)`, `station_used(id)`, `set_active(on)` (stop all processing while off; also called before the
  room is freed), `set_english(on)`, `counts()` (`static_meshes`, `static_tris`, `anim_parts`, `shaders`).
- **Stable public kit** (guarded by `test_pack_rooms.gd`): `HallBuilder.material()`, `bake(geo, lights, cool)`,
  `lit(col, b)`, `glow(p, lights)`, `tube(geo, a, b, r, sides, col)`, `tris(mesh)`, `arch_pts(a, spring, apex, k)`, the
  `HallBuilder` colour constants (incl. `BANNER_COLS`), `append(a, b)`, `flame_mesh()`, `flame_plain_material()`,
  `res://scenes/hall/flame.gdshader`, `PropsLayer.Geo` (`box`, `prism`, `band`, `poly`, `mesh`), `HallLayout.AVATAR_R`,
  `HallLayout.COOL_LIGHTS`, `HallWorld.FADE_*`. Anything else of the public code is not a contract.
- **Public side**: `PackRoomScreen` (`ui/screens/pack_room_screen.gd`) pushed over the deck with the deck's fade;
  `PackRoomWorld` (`scenes/hall/pack_room_world.gd`) instances the script and draws collision (`RoomLayout`), rings,
  signs, the deck figure (H1/H2), friends and the camera from `room.json`; the screen draws the prompt, use button,
  stick, coming-soon panel and the cards panel; `‹ ดาดฟ้า`, Esc or the `walk_in` door go back to the deck at
  `HallLayout.AIRLOCK_RETURN` facing −x. Main menu "online" lands in the room in front of its play-with-friends station
  with host/join on top. Camera rule: as on the deck the camera never ends inside a blocker; in a room a big blocker
  (half-size ≥ `RoomLayout.OCCLUDE_HALF` = 0.75 m on both floor axes, or radius ≥ 0.75 m) that only hides the line also
  pulls it to its front, so it never parks behind a booth next to a wall.
- **Presence without a protocol change**: in the room `where` stays `"deck"` and poses are sent with x + 30 m
  (`PackRooms.to_band`); a pose with x ≥ 13.5 m is "in the room": the deck hides that friend and the room draws it at
  x − 30. `NetProto` and its `VERSION` are unchanged; `APP_VER` moved to ใหม่ 0.7 so the `wrong_app` gate keeps 0.6
  out of a 0.7 room. A newcomer gets everyone's standing pose (each screen re-sends its stop pose when a member joins);
  a slot that leaves the member list forgets its room pose, so a reused slot starts on the deck. A friend already in
  the room when you enter is drawn at once (`seed_poses` from the deck's `band_poses`). The host's SETUP-open note also
  shows in the room, naming `PackRooms.setup_place(room)`.
- **Failure paths**: a room that does not open (bad script, blocked spawn/front) pops at once and the deck opens host/join
  instead, then shows `ROOM_FAILED` on return. A screen pushed during the leave fade (a net battle starting) leaves the
  room flagged: when that screen closes the room pops itself and the deck shows, never a black room.
- **Budgets**: the deck's limits for every room, measured by `tests/render/room_budget.gd` (spawn overview, in front of
  each station, phone worst view): hi 140 / 250k, mid 100 / 150k, lo 60 / 80k, min 40 / 40k draw calls / primitives;
  on min and lo nothing under the room processes after 10 idle frames and no `TIME` shader; hi/mid may animate.
  The private build runs `room_budget.gd -- --root res://packs/rooms` under xvfb as its gate.
- **Tests**: `tests/unit/test_pack_rooms.gd` (listing, 13 broken cases under `tests/fixtures/pack_rooms_bad/`,
  `RoomLayout` incl. blocker checks and `clear_problems`, `bg` hex, pose band, kit, airlock return),
  `tests/render/test_pack_room.gd` (the whole walk with the test room, a second visit, the failure paths with
  `tests/fixtures/pack_rooms_refused/`),
  added checks in `tests/flow/test_hall_reach.gd`.

### 9.5 Arena door in a pack room (round B, 14 Nov 2026)

Owner, 14 Nov: "move the test room (arena) into the launch bay". A room may declare the way to the arena itself:

- A station with `"action": "arena"` (usual `id`, `name` {th, en}, `c`, `h`, `front`, `sign`, `face`, `height`, `reach`)
  is a walk-in door to the arena screen: always walk-in (`RoomLayout` sets `walk_in` for it; `"walk_in": true` is also
  accepted on it and still refused on any action but `back` and `arena`); at most one per room
  ("at most one station may have action arena"). `PackRooms.arena_station(room)` gives its id or "".
- Walking into it or E: the room screen stops the avatar, sends `where = arena`, fades (same fade as the deck's arena
  door) and pushes the arena screen. The arena files are preloaded on a thread when the station comes in reach, through
  the deck screen that opened the room (`PackRoomScreen.hall` → `hall_screen.preload_arena` / `arena_scene`, the same
  cache as the deck door). Coming back: the avatar stands on the station's `front` facing away from the door, the camera
  behind it, the fade clears, then it can walk.
- If the loaded pack room has such a station, the deck's arena door is shut (`hall_screen.arena_moved()`): no ring, no
  prompt, no walk-in, empty sign, closed leaves drawn (SHIP_LOBBY_SPEC round B). Without one the deck door is unchanged.
- Fixtures: `tests/fixtures/pack_rooms_arena/arena_room` (test_room plus an `arena_door` station on its left wall) and
  `tests/fixtures/pack_rooms_bad/two_arena`. Checks: `test_pack_rooms.test_arena_station`, the broken-case table, and
  `test_pack_room` (`_check_arena_door`).

### 9.6 Dressing station (round C, 14 Nov 2026)

- A station with `"action": "dressing"` (no extra keys) pushes `DressingScreen` (`ui/screens/dressing_screen.*`) over the
  room: one button per `Figures.list()` entry, a turntable preview (`Figures.make` + `setup` role deck + H10), one swatch
  per scheme (disabled, with "ตัวนี้ใช้สีของตัวเอง", for a figure whose `schemes` is false), three slots (load / บันทึก),
  "ใช้ตัวนี้" = `Figures.select` and close; ‹ กลับ / Esc close without a change. Wide screens: preview, swatches and
  ใช้ตัวนี้ left, the scrolling list and slots right; narrow: top to bottom. On min the preview never spins and redraws
  only on a change or a drag (no per-frame work). Texts: `ui/i18n/dressing.json`. No `Figures` file = a not-ready note.
- After ใช้ตัวนี้ the room's avatar is rebuilt by `PackRoomWorld.refresh_figure` (`App.figure_changed`); the room screen
  rebuilds it itself only if nothing did (a stand-in API in tests). `DressingScreen.api` / `.path` point tests elsewhere.
- Fixture `tests/fixtures/pack_rooms_dressing/dress_room` (test_room with a `wardrobe` station). Tests:
  `tests/flow/test_dressing_flow.gd` (headless) and `tests/render/test_dressing.gd` (TH/EN, desktop and phone, preview
  within the §3.5 figure budget), both from `tests/flow/dressing_steps.gd`; `DRESS_STUB=1` runs them against
  `tests/unit/fixtures/figures_stub.gd` (adds the fixed-colour and H10 checks).

## 10. Dressing room: figures, schemes, slots (round C, 14 Nov 2026)

Owner, 14 Nov: choose which character comes out and walks on the deck and in pack rooms, in a preset colour scheme, with
three saved characters. The public code is the registry and the walkers; the dressing screen opens only from a pack room
station (`"action": "dressing"`), so the public app shows nothing new. Friends online still see eggs (no protocol change).

- **Registry** `app/figures.gd` (`class_name Figures`, static): `list()` → `[{id, name {th, en}, kind "egg"|"kit"|"pack",
  kit (kind kit), schemes}]` (pack figures first, then the egg, then the kits); `entry(id)`; `make(id, level)` → a deck
  walker (not yet set up; `HallAvatar.set_figure` does that) or **`null` for the egg** (the avatar keeps its own egg) and
  for an unknown id or a pack figure that lacks the deck API (`setup`, `set_weapon`, `play`, `set_move`, `apply_level`);
  `dress(fig, scheme_id)` (H10 when the figure has it); `schemes()` → `[{id, name, primary, secondary, original}]`
  (original, blue, red, green, pink, black, white, purple, gold; sRGB; `original` = the figure's own colours: `dress`
  and the dressing screen never call H10 for it, its colours only draw the swatch); `scheme(id)`; `selected()` → `{figure, scheme}`; `select(figure_id,
  scheme_id)` (unknown ids fall back to the defaults, writes, emits `App.figure_changed`); `slots()` → 3 × `{}` or
  `{figure, scheme}` (a figure that no longer exists reads as `{}`); `save_slot(i, figure_id, scheme_id)`.
- **Default**: the first pack figure, else the egg; scheme original (a figure looks as before until the owner picks).
- **Storage**: section `[figure]` (`figure`, `scheme`, `slot0..2`) of the app's settings file (`App.settings_file`; tests
  point it, or `Figures.store_path`, elsewhere); `App.save_settings` keeps other sections. Never `godot/data/*.json`
  (that would change `DATA_HASH`, the online gate).
- **Pack figures** `res://packs/figures.json` (absent = none; tests set `Figures.pack_list`):
  `[{"id", "name": {"th", "en"}, "figure": "<path>", "schemes": bool}]`. `id` matches `^[a-z][a-z0-9_]{0,23}$`, is
  unique, not `egg`, not `kit_*`; `en` has no Thai; `figure` is a `.gd` (`new()`) or `.tscn`/`.scn` (`instantiate()`)
  inside the folder of `figures.json` (relative or `res://`, no `..`); `schemes` defaults to false. A broken entry is
  skipped with a warning. Without `figures.json` an old `pack.json` `"deck"` entry is listed as one figure `"pack"`, so a
  pack made before the dressing room keeps its deck figure as the default.
- **Kit walkers** (`scenes/hall/kit_walker.gd`, `KitWalker extends KitBeast`): one per army, chosen by data
  (`Figures.KITS`: skinned 23-bone foot figures with their own palette, no mount, no creature, 1.5–2.3 m tall; names are
  the existing neutral unit names). The humanoid idle / walk / run clips of `assets/anim/humanoid.res`, `motion_scale`
  = the kit's scale, the kit's pose holds; `deck_speeds()` = clip speed × scale × 1.4 (about 1.6 / 4.0 m/s), and the
  playback rate follows the speed, so feet do not slide. Scheme: one row of the kit paint table (`paint_tex`,
  `paint_row` 0; `assets/kits/CONTRACT.md` §3): armour slots primary, cloth slots (`KitWalker.SECONDARY_KEYS`)
  secondary, and weapons, lenses, trim (`FIXED_KEYS`) and every natural slot keep their colours. Cost: one draw call,
  about 1k triangles, per-vertex light on lo/min; standing on **lo and min** the `AnimationPlayer` holds a still pose
  (PACK_SPEC §3.2); no `set_fade` (the walker stays opaque when the arm is squeezed).
- **Worlds**: `HallWorld.refresh_figure()` and `PackRoomWorld.refresh_figure()` build `Figures.make(selected)`, set it on
  the avatar and dress it; both run at build and on every `App.figure_changed`.
- **Budgets** (measured by `tests/render/test_kit_walker.gd`, deck overview with kblade): hi 19 draws / 18.4k
  primitives, mid 19 / 17.1k, lo 15 / 15.5k, min 15 / 14.8k — the same draw calls as the egg, about +900 primitives.
- **Tests**: `tests/unit/test_figures.gd` (registry, kit choice by data, schemes, persistence, slots, pack list with
  `tests/fixtures/figure_pack/figures.json` and `figure_pack_bad/figures.json`, make, the paint table, still pose),
  `tests/render/test_kit_walker.gd` (select → rebuild, walk/run rates, every level within the deck targets, still on
  lo/min, eight kits in eight schemes, back to the egg).

- Round D (14 Nov): the weapons arena plays the selected figure too (ARENA_SPEC §9.6): a pack figure from `figures.json`
  is used as the arena player when it has the whole arena contract (`ArenaActors.FIGURE_API`) and is dressed with the
  chosen scheme after `setup` (H10, only when its entry has `"schemes": true`); a deck-only figure falls back to the
  pack's `player`. Battle-table kits play through `KitFighter`; the egg stays the egg gunner. A pack figure whose H9
  `uses_strafe()` is false is turned by A/D (no side-walking).
