# Main menu, walkable lobby and bot games — build spec

Written 12 Nov 2026 for the new app (`godot/`, branch `claude/new-session-fsucoo`, draft PR #27). Three builders follow
this file in parallel, in the same checkout. It is the single source of truth for names, paths and contracts. Builders
read it but do not edit it; a needed change goes back to whoever runs the workflow.

**The owner's request (12 Nov):** "Let's do the game's front page and the lobby first. Before the real models go in, use
simple egg-shaped placeholder figures. Don't remove the old models." Then: "Do it now. A lobby you can walk around in:
press WASD and walk around, like that." He chose **playable against bots first; online with friends later**.

**For the owner, in Thai:** เปิดแอปแล้วเจอหน้าแรกธีมเทียน → กด "เล่นกับบอท" → เข้าห้องโถง (ล็อบบี้) ที่เดินได้ด้วย WASD
(มือถือใช้จอยสติ๊กบนจอ) → เดินไปที่โต๊ะรบแล้วกด E (มือถือแตะปุ่ม) → ตั้งเกม เลือกกองทัพจาก 15 กองทัพ จำนวนทีม คน/บอท
ฉาก โหมด → เริ่มรบกับบอท ฟิกเกอร์ทุกตัวเป็น "ตัวไข่" ขนาดตามชนิดหน่วย มีวงสีทีมใต้ตัว → เล่นจนจบ เห็นผู้ชนะ → กลับห้องโถง
โมเดลชุดเดิม 312 ตัวยังอยู่ครบ สลับกลับได้ในหน้าตั้งค่า ออนไลน์กับเพื่อนและโต๊ะผจญภัยขึ้นป้าย "เร็วๆ นี้"

## Decisions this spec fixes (do not re-decide)

| Topic | Decision |
| --- | --- |
| Name of the walkable lobby in code | **hall** (`scenes/hall/`, `ui/screens/hall_screen.*`). On screen it is "ล็อบบี้" / "Lobby". ARCHITECTURE reserves `ui/screens/lobby.tscn` for the online room screen (R3), so no new file may be called `lobby*`. |
| First screen | The new main menu. The GPU check stays, reached from Settings. |
| The demo table in `main.tscn` | It stays, but no longer builds at startup (`auto_build = false`). It is hidden and its processing is disabled until the GPU check or a battle needs it. |
| Default figure style | `egg` (App setting `fig`, values `egg` / `kit`). The kits, the impostors and the kit code stay untouched. |
| Team colour | A ring under every figure (owner decision of 7 Oct). Battle eggs stay ivory. Only the lobby avatar egg is tinted in the player's colour, and it has a ring too. |
| Human seats | At most one local human seat per game (0 = watch bots). Hot-seat and online come later. |
| Seats per team | 1 or 2. Teams 2–4. At most 6 seats in all. |
| Placeholder size | From `data/types.json` through `GameData`, never from the generated `kits.json` (§4.1). |
| Lights in the hall | No dynamic lights. Candle glow is baked into vertex colours, and materials are unshaded. Flames flicker only on hi/mid. |
| Text | Every Thai literal lives under `ui/` (the lint scans `ui/` and `app/` only). 3D signs get their text from the hall screen. |
| Cross-track references | `load(PATH)` with the paths in §6.3, never `preload` of another track's scene, and never another track's `class_name`. |

## 0. Ground rules for the three builders

1. **Ownership.** Each track edits only the paths it owns (§6). Shared files have one owner; the others only call the
   contract in §6.3. A failing check in another track's file is reported, not fixed.
2. **Order.** The menu track does **M0** (§6.2) first and keeps it small: about 15 minutes, then it says so in its
   progress notes. Until M0 is in, the lobby and battle tracks work on files that do not need it (listed per track in §6).
   To check for it: `grep -q touch_active godot/app/app.gd && test -f godot/ui/theme/candle_style.gd`.
3. **No commits, no pushes, no PR changes.** Leave everything in the working tree. Do not touch the old app (`app/`,
   `desktop/`, the root `tests/`, the old pages), `scenes/probe/`, `core/` (except the one `APP_VER` line, menu track), or
   any generated asset (`assets/kits/`, `assets/impostors/`, `assets/anim/`, `data/*.json`). Never write into the
   scratchpad figure folders (`samples/`). The third-party STL figure and real faction logos must never enter this repo.
4. **AGENTS.md hard rules.**
   - No names or marks of other game companies (rule 1) anywhere: code, file names, comments, strings, tests. The data
     lint scans every file under `godot/`.
   - Thai first, with an English pair for every new Thai string (§0.7).
   - Rules stay in `core/`. The UI never writes `BattleState` fields; every battle change goes through
     `Battle.apply` / `bot_step` / `flush`. No `randi()` or `randf()` in acts; dice come from `st.rng(...)`.
   - The `min` level gets no new per-frame work: nothing runs `_process` / `_physics_process` while idle.
   - Edit existing files surgically: minimal replacements, no re-formatting or re-ordering. Code comments are short and
     in Thai, like the surrounding code.
   - Hidden units stay hidden: never list them and never describe how one unlocks.
5. **Godot.**
   - Binary: `~/godot-bin/godot` (4.7.1). Run everything from `/home/user/candlelight-table`.
   - Software rendering for render tests: `xvfb-run -a -s "-screen 0 1280x720x24" ... --rendering-driver opengl3`.
   - The 4 cores are shared with another heavy job. Use `nice -n 10`, small renders, and your own targeted suites while
     working. The full suite runs once at the end (§7.5).
   - Check the time with `TZ=Asia/Bangkok date`.
6. **Shared cache.** All three builders use the same `godot/.godot/` folder.
   - After adding a `class_name` script, a shader or another importable resource, refresh the cache **under the lock**:
     ```bash
     flock <scratchpad>/godot-lobby/import.lock \
       timeout 600 ~/godot-bin/godot --headless --path godot --import
     ```
   - Each track writes test output only to its own folder:
     `TEST_OUT=<scratchpad>/godot-lobby/out-<track>`.
   - Scratch scripts also go under `<scratchpad>/godot-lobby/`, never into the repo.
   - Tests never write the machine's `user://settings.cfg`: point `App.settings_file` at `user://test_<suite>.cfg` first.
7. **i18n fragments.**
   - Each track adds its strings to its own file: `ui/i18n/menu.json`, `ui/i18n/hall.json`, `ui/i18n/battle.json`
     (flat Thai → English objects, two-space indent, one pair per line).
   - Nobody edits `ui/i18n_extra.json` or `data/i18n_en.json`.
   - **Reuse a key that already exists** in `data/i18n_en.json`, `ui/i18n_extra.json` or `I18n.EN`, and do not add it
     again. A fragment key that also appears in another source fails `test_i18n_fragments`.
   - Shared new words are seeded once in `menu.json` by M0 (§6.2). Before adding a key, look it up with
     `python3 -c "import json;..."` or `I18n.has_key`.
   - `I18n.t` matches **whole strings only**. Translate the template, then format it:
     `I18n.t("{name} · กด E").format({"name": I18n.t(name_th)})`. Never build Thai by joining fragments.
   - The language toggle button is always a node named `LangButton`: it shows "ENGLISH" in Thai mode and "ไทย" in English
     mode, and render scans exempt it.

## 1. Screens and flow

```
boot (main.tscn)
  └─ Main menu ──เล่นกับบอท──▶ Lobby hall (walk) ──[station: โต๊ะรบ]──▶ Battle setup ──เริ่มรบ ›──▶ Battle ──▶ End panel
        │                         │  ├─[ตู้โชว์กองทัพ]──▶ Army picker (existing screen, unchanged)        │
        │                         │  ├─[ตั้งค่า]────────▶ Settings ──▶ GPU check ──▶ Army picker            │
        │                         │  ├─[ประตูออนไลน์]─── "เร็วๆ นี้" panel, stays in the hall              │
        │                         │  ├─[โต๊ะผจญภัย]──── "เร็วๆ นี้" panel, stays in the hall               │
        │                         │  └─[ประตูทางออก] or ‹ หน้าแรก ──▶ back to the main menu                │
        ├─ออนไลน์ ("เร็วๆ นี้" badge): toast only                                                        │
        ├─ตั้งค่า ──▶ Settings                                                    กลับล็อบบี้ ◀──────────────┘
        └─ENGLISH / ไทย (LangButton), ออก (desktop only)
```

Stack mechanics (App screen stack, `App.push` / `pop` / `replace`):
- `main.gd` pushes the main menu (depth 1).
- เล่นกับบอท pushes the hall (depth 2).
- A station pushes setup, the army picker or settings (depth 3).
- Setup's START calls `App.replace(BATTLE_SCREEN)`, so the battle takes setup's place (depth 3) and the hall is never
  shown in between.
- The battle's "กลับล็อบบี้" calls `App.pop()`, and the hall shows again (depth 2).
- "เล่นอีกครั้ง" restarts in place with the same plan and a new seed.

A screen whose 3D is hidden by a push must hide its 3D world, disable its processing and give up the camera on
`visibility_changed`, then restore all three when shown again. On show it also re-reads `App.gfx`, `App.lang`,
`App.touch` and `App.fig`, so Settings never needs to reach into a live 3D scene.

**Back button (Android) and Esc (Windows).** Esc is the `back` input action; Android back arrives as
`NOTIFICATION_WM_GO_BACK_REQUEST`. Both call `App.back()`. That first asks `current().handle_back()` when the screen has
the method (true = handled), then pops; at depth 1 it quits.

| Screen | Back / Esc |
| --- | --- |
| Main menu | Opens the quit confirm ("ออกจากเกม?" with ออก / ยกเลิก). A second press closes the confirm; ออก quits. |
| Hall | Closes the "เร็วๆ นี้" panel if open, otherwise goes to the main menu (pop). |
| Battle setup | Back to the hall (pop). |
| Battle (playing) | Opens the leave confirm ("ออกจากการรบ? เกมนี้จะไม่ถูกบันทึก" with ออกจากการรบ / เล่นต่อ). Confirm goes to the hall. |
| Battle (end panel shown) | Back to the hall, the same as กลับล็อบบี้. |
| Settings, GPU check, army picker | Pop (existing behaviour for the army picker). |

Confirms and panels are plain Controls (PanelContainer) inside the screen, never `Window` / `AcceptDialog`, so they
style, scale and test like everything else.

### 1.1 Main menu (menu track)

Full-screen, opaque, 2D only (no 3D is drawn behind it).

- **Title art** is our own design, drawn by `TitleArt._draw()` from simple shapes: a dark warm gradient, a long wooden
  table silhouette, three to five candles with layered flame polygons, a soft halo, and the title "โต๊ะเทียน"
  (English "Candlelight Table") in Sarabun Bold about 72 px, with the subtitle "โต๊ะรบกับเพื่อน บอท หรือ Claude".
  - Flicker on hi/mid: a `Timer` at 6 Hz or less changes flame heights and calls `queue_redraw()`.
  - lo/min: static and drawn once.
  - No textures, no marks of any company.
- **Buttons**: a right-hand column about 420 px wide, each button at least 64 px tall, `CandleStyle.button`.
  - `%PlayButton` "เล่นกับบอท": `App.push(load(HALL_SCREEN))`.
  - `%OnlineButton` "ออนไลน์" with a small "เร็วๆ นี้" badge: shows `%Toast` "ออนไลน์กับเพื่อน เร็วๆ นี้" for 2.5 s.
  - `%SettingsButton` "ตั้งค่า": `App.push(load(SETTINGS_SCREEN))`.
  - `LangButton` (unique name `%LangButton`): `App.set_lang`, `App.save_settings()`, then redraw every text.
  - `%QuitButton` "ออก": desktop only (`not OS.has_feature("mobile")`), opens the quit confirm.
- `%VersionLabel`, bottom right: `I18n.t("แอปใหม่ รุ่น {v}").format({"v": Version.APP_VER.trim_prefix("ใหม่ ")})`. Never
  show `APP_VER` raw: it contains Thai.
- Layout:
  - Fits 1280x720 logical, which is also what 640x360 gives under `canvas_items` stretch.
  - Fits 1600x720 logical (20:9 phones such as the owner's 2400x1080).
  - 16 px gutters plus the display safe area.

### 1.2 Settings (menu track) — see §5

## 2. Lobby hall (lobby track)

0.3: §2.1, §2.2 and §2.6 are replaced by `SHIP_LOBBY_SPEC.md` (the warship deck); §2.3–§2.5 still hold.

### 2.1 Layout (world units are metres; y is up; the camera starts looking toward −z)

Interior box: x ∈ [−12, 12], z ∈ [−8, 8], floor at y = 0.
- Walls are 0.5 m thick outside the box and 6 m high.
- An invisible ceiling collider sits at y = 6 (layer 1), so the camera arm never leaves the hall.
- The ceiling is not drawn: darkness above the candles.

| id | What it is (our own design) | Footprint rect: centre (x, z), half (x, z) | Reach | Sign (from the hall screen) | Use |
| --- | --- | --- | --- | --- | --- |
| `battle` | The war table: 6 × 4 m, top at 0.95 m, a miniature field on top (green/ochre patches, a few tiny eggs), 4 candles at the corners | (0, −2), (3.0, 2.0) | 1.6 | โต๊ะรบ | push setup |
| `army` | Display shelves against the left wall: 3 tiers, 15 small ivory eggs, 15 plain-colour pennants (no emblems) | (−11.4, −1), (0.5, 2.6) | 1.6 | ตู้โชว์กองทัพ | push the army picker |
| `settings` | A lectern with an open book and one big candle | (10.0, −1), (0.4, 0.4) | 1.6 | ตั้งค่า | push settings |
| `online` | A tall arch in the back wall, closed by a grille | (0, −7.8), (1.7, 0.3) | 1.8 | ออนไลน์ · เร็วๆ นี้ | "เร็วๆ นี้" panel (superseded in 0.5: the airlock opens the play-with-friends screen, `NET_SPEC.md` §7.1) |
| `adventure` | A round table (r 1.3) with 4 stools and a rolled map | (−5, 4), (1.3, 1.3) | 1.5 | โต๊ะผจญภัย · เร็วๆ นี้ | "เร็วๆ นี้" panel |
| `exit` | The entrance door in the front wall | (0, 7.9), (1.2, 0.2) | 1.4 | ทางออก | pop to the main menu |

- **Pillars**: radius 0.45 m, 6 m tall, at (±8.5, −5), (±8.5, 0.5) and (±8.5, 5.5).
- **Candle stands**: tall stands against the walls at (±11.3, −6), (±11.3, 3) and (±4, −7.5), plus the table, lectern
  and adventure-table candles. At most 24 flames on hi/mid/lo, 12 on min.
- **Banners**: hanging cloth quads in deep red, ochre and teal, at (±6, −7.7) on the back wall and on the side walls
  between pillars. Their motif is our own: a candle flame inside a circle, built from vertex-coloured triangles.
- **Spawn**: (0, 0, 5), facing −z. From there the battle table's trigger starts about 3.4 m ahead. (Changed at
  integration from (0, 0, 6): there the front wall pushed the camera arm down to about 1.5 m and the first view was a
  giant see-through egg; at z 5 the arm stays about 2.9 m.)
- **Active station**: the avatar's centre is within `reach` of a footprint rect's edge. Ties go to the smallest distance.
  The spawn point is in no trigger.
- `HallLayout` (pure, static) holds this table: ids, rects, reach, pillars, stands, spawn and bounds. **No Thai in it.**

### 2.2 Look and cost

- **Static geometry**: floor, walls, pillars, beams, furniture, banners and candle bodies. It is built with
  `PropsLayer.Geo` (box / prism / band / disc) into **at most 3 ArrayMeshes** sharing one unshaded vertex-colour
  `StandardMaterial3D` (`vertex_color_use_as_albedo`, `vertex_color_is_srgb`).
  - The floor is a grid of 1 m stone tiles. Tile shade varies through a seeded `RandomNumberGenerator`, so the look is
    stable.
  - Candle glow is baked into vertex colours: brightness = 0.32 + Σ over flames of 0.85 / (1 + d²/3), clamped and
    tinted warm (#ffb35c).
- **Flames**: one MultiMesh of small double-cone flame meshes.
  - hi/mid: `scenes/hall/flame.gdshader` (unshaded; vertex scale wobbles with `TIME` and a per-instance phase in
    `INSTANCE_CUSTOM.x`).
  - lo/min: a plain unshaded material, no `TIME`.
  - Optional on hi: one additive halo quad per flame in the same MultiMesh pass.
- **Environment**: an `Environment` set on the hall `Camera3D.environment`, with a background colour of #120c08. **No
  `WorldEnvironment` node**, because the table in `main.tscn` already has one in the same world. No lights, no shadows.
- **Signs**: one `Label3D` per station, with billboard off, facing the walkway and fixed size. Their text comes from
  `HallWorld.set_sign_text(id, text)`, which the hall screen calls with `I18n.t(...)` on show and when the language
  changes.
- **Rings**: one `Rings` node (`table/rings.gd`, one draw call) holds the avatar's ring (radius 0.68, team-0 colour) and
  one `Kind.OBJECTIVE` ring in front of each station.

### 2.3 Avatar

- `HallAvatar extends CharacterBody3D`, `motion_mode = MOTION_MODE_FLOATING`, kept at y = 0.
- Collision: a capsule of radius 0.35 and height 1.75, collision layer 2, mask 1 + 4. Every static blocker is built
  from `HallLayout`: walls and the ceiling in the `Blockers` body (layer 1), pillars, candle stands and furniture in the
  `PropBlockers` body (value 4, layer 3; review of 12 Nov, so the camera arm does not snap at them).
- Body:
  - An egg 1.75 m tall with a widest radius of 0.43 m, made with the egg profile of §4.1 (the lobby keeps its own small
    copy of the profile table; `EggShapes` belongs to the battle track).
  - Tinted: 60 % team-0 colour (`data/teams.json[0].rgb`) mixed with ivory, top lighter (baked).
  - Unshaded vertex colours, plus a darker nub on +z to show facing.
  - Optional `Label3D` "คุณ" above it (text set by the hall screen).
- Movement:
  - Walk 3.0 m/s, run 6.0 m/s (Shift, or the stick pushed past 0.85).
  - Acceleration smoothing rate 12/s. Moves relative to the camera:
    `move = right_flat * x + forward_flat * y`.
  - Turns to face its movement with `lerp_angle`.
  - Slides along walls and furniture (`move_and_slide`).
- **Idle rule**: `_physics_process` is on only while a move action is held, the stick is off-centre, or the body is still
  easing to a stop. A move action event in `_unhandled_input` or a stick change turns it on again. Polling uses
  `Input.is_action_pressed` and `Input.get_action_strength` while on.
- Bob and lean while walking on hi/mid only. On min the avatar simply slides.

### 2.4 Camera

- `HallCamera` (Node3D) follows the avatar target (position + (0, 1.3, 0)), smoothed with `1 − exp(−10·dt)`.
- A `SpringArm3D` child with collision mask 1 (walls and ceiling only), a sphere shape of r 0.3 and margin 0.1. The
  `Camera3D` (fov 60) sits at the arm's end, **so it can never sit inside a wall, a pillar or the ceiling**:
  - Pillars, stands and furniture are not on the arm's mask (they made the arm snap 5 m in one frame when one passed
    between the camera and the avatar). Before the arm runs, `HallLayout.camera_clear` checks only the camera point:
    inside a prop (0.15 m padding) it goes to the prop's nearer side (behind it when there is room, else in front); a
    prop that only stands in the line of sight does not move the camera (it may hide the egg for a moment).
  - The arm pulls in at once and extends back out at most 4 m/s, never through a prop. The camera point is checked
    again after the pivot moves in `_process`, because a frame can come several physics steps later.
  - test_hall walks spawn → lectern, spawn → army display and past two pillars: the arm changes by at most 0.5 m a frame.
- Start values: yaw 0, pitch −0.45 rad, arm length 6.5. Arm length 3–9; pitch clamped to [−1.2, −0.15].
- Orbit:
  - Mouse: left or right drag on empty screen.
  - Touch: one-finger drag outside the stick and buttons.
  - Zoom: wheel or pinch.
  - All of it in `_unhandled_input`, ignoring emulated mouse events (`event.device == InputEvent.DEVICE_ID_EMULATION`),
    as `CameraRig` does.
- `forward_flat() = Vector3(−sin yaw, 0, −cos yaw)`, `right_flat() = Vector3(cos yaw, 0, −sin yaw)`.
- `_process` runs only while easing; it stops once within 1 cm.
- The hall does **not** use or edit `table/camera_rig.gd`.

### 2.5 Hall HUD (hall screen, a Control)

- The root Control is full-rect with `mouse_filter = MOUSE_FILTER_IGNORE`, so drags reach the camera. Panels and buttons
  use STOP.
- `%MenuButton` "‹ หน้าแรก", top left: pops to the main menu. `%SettingsButton` (gear "ตั้งค่า"), top right: pushes
  settings.
- `%UseButton`, bottom centre, at least 64 px tall, shown only when a station is active:
  - Keyboard mode: `I18n.t("{name} · กด E")`.
  - Touch mode: `I18n.t("{name} · แตะเพื่อใช้")`, as a big button.
  - Clicking or tapping it is the same as E (`use_station()`).
- `%Hint`, the first-entry hint:
  - Desktop: "WASD หรือลูกศร เดิน · Shift วิ่ง · ลากเมาส์หมุนกล้อง".
  - Touch: "ใช้ปุ่มซ้ายล่างเดิน · ลากจอหมุนกล้อง".
  - It hides on the first move (on min it simply hides; no tween).
- `%SoonPanel`: "ออนไลน์กับเพื่อน — เร็วๆ นี้" (until 0.4; superseded by `NET_SPEC.md` §7.1) or "โต๊ะผจญภัย — เร็วๆ นี้". It closes after 2.5 s (Timer), on a move, or on
  Back.
- **Touch controls**: shown when `App.touch_active()`, re-read on every show.
  - `%Stick` (`TouchStick`), bottom left: base radius 90 px, knob 40 px, dead zone 0.15, past 0.85 = run.
  - It handles `InputEventScreenTouch` / `InputEventScreenDrag` and tracks its own finger index. It also accepts
    non-emulated mouse drags, so a forced "on" can be tried with a mouse.
  - It emits `changed(v: Vector2)` (y up = forward) and processes nothing per frame.
- Everything stays inside the display safe area. Targets are at least 44 px.

### 2.6 Per graphics level (`HallWorld.apply_level(l)`)

It applies the same three globals as `TableView.apply_level` from `TableView.LEVELS[l]` (root viewport
`scaling_3d_scale`, `Engine.max_fps`, `OS.low_processor_usage_mode = idle`), plus:

| Level | Flames | Flicker | Halo quads | Avatar bob | Lathe sides | Budget (draw calls / primitives) |
| --- | --- | --- | --- | --- | --- | --- |
| hi | 24 | yes | optional | yes | 14 | ≤ 140 / 250k |
| mid | 24 | yes | no | yes | 12 | ≤ 100 / 150k |
| lo | 24 | no | no | no | 10 | ≤ 60 / 80k |
| min | 12 | no | no | no | 8 | **≤ 40 / 40k** (asserted) |

On min, nothing processes while idle: the avatar, the camera, the hall screen and the stick all have their per-frame
callbacks off.

## 3. Battle setup panel (battle track)

`ui/screens/battle_setup.tscn` is full-screen and opaque, with two columns at 1280x720 logical and no scrolling.

- **Left: seats.**
  - `%TeamCount`: 2 / 3 / 4. `%PerTeam` "ขนาดทีม" (an existing key): 1 / 2. At most 6 seats; 4 × 2 is refused with a
    message.
  - One row per seat, in team-major order (seat k is in team `k / per_team`). Each row has:
    - the team swatch and name (`data/teams.json` `nm`, translated, e.g. "ทีมน้ำเงิน" → "Blue Team");
    - the army `OptionButton`: the 15 armies in `GameData.factions()` order, named with
      `I18n.t(GameData.faction(k)["nm"])`, plus "สุ่ม" (random);
    - a who-toggle "คุณ" / "บอท".
  - At most one row is "คุณ": choosing it on another row turns the old one into a bot (radio behaviour, no error).
- **Right: table.**
  - Size: เล็ก 36 / กลาง 48 / ใหญ่ 72 inches.
  - Theme: เมืองพัง / ป่าไม้ / ทะเลทราย / ทุ่งหิมะ (`ruin` / `forest` / `desert` / `ice`).
  - Terrain: ราบ / เนิน / ภูเขา / ป่าทึบ (`flat` / `hills` / `mountain` / `forest`). Use "ภูเขา" (a new key, "Mountains"),
    not the data's "สูง": that key already means the graphics level "High".
  - Goal (เป้าหมาย): ยึดจุด with rounds 3–10 (default 5), or ตีกันจนตาย with the hint "เกมอาจยาว". Kill games always allow
    30 rounds.
  - Points per team "แต้มต่อทีม": 300 / 500 / 1000 / 1500 (default 500).
  - `%SeedLabel` "เลขสนาม {seed}" with a reroll button. The UI may use engine RNG to pick the seed; the rules are seeded
    from it.
- **Bottom bar**: `%BackButton` "‹ ล็อบบี้" (existing key), `%Errors` (a Label) and `%StartButton` "เริ่มรบ ›"
  (existing key). START is disabled while `SeatPlan.validate` returns errors.
- **Defaults**: 2 teams × 1, seat 0 is "คุณ" with the first army, seat 1 is a bot with a random army, กลาง, เมืองพัง,
  เนิน, ยึดจุด 5 rounds, 500 points.
- **Optional stretch**: "จัดกองทัพเอง ›" on the human row opens the existing army picker and, on its `tree_exiting`, reads
  `screen.roster.fac` and `screen.roster.list()` into the seat. Without it, every seat uses the auto list.
- **Public API** (used by the flow test): `choice: Dictionary`, `set_teams(n)`, `set_per_team(n)`,
  `set_seat(i: int, fac: String, human: bool)` (fac "" = random), `set_size("s"|"m"|"l")`, `set_theme(k)`,
  `set_terrain(k)`, `set_goal("obj"|"kill")`, `set_rounds(n)`, `set_budget(n)`, `set_seed(n)`, `errors() ->
  PackedStringArray`, `start() -> bool` (the same as pressing START).
  (As built: the setup root is a `Node2D` with the page as a `Control` child, because `set_size` and `set_theme` on a
  Control script collide with `Control.set_size(Vector2)` / `Control.set_theme(Theme)` and fail to parse.)

### 3.1 Mapping to the core (`ui/battle/seat_plan.gd`, `class_name SeatPlan`, pure, no Node)

`SeatPlan.build(choice) -> {"setup": Dictionary, "seats": Array[Dictionary], "human": int, "errors": PackedStringArray}`

```
setup = {"seed": seed (1..99999), "w": 36|48|72, "teams": T, "perTeam": P, "goal": "obj"|"kill",
         "rounds": clamp(r, 3, 10) (obj only), "budget": pts, "theme": "ruin"|"forest"|"desert"|"ice",
         "terrain": "flat"|"hills"|"mountain"|"forest", "buildings": 1, "density_h": 100,
         "mode": "pvp" if T == 2 and P == 1 else ("team" if P > 1 else "ffa"), "freeFire": 0}
```
- Never pass `"d"`: Battle and TableView both use `FieldTerrain.depth_for(w)`.

**Seats.** The array must be typed: `var seats: Array[Dictionary] = []`. Seat k gets
`{"team": k / P, "bot": not human_k, "pid": "", "fac": fac_k, "nm": "", "list": PackedInt32Array}`.
- A random army is picked reproducibly:
  `fac = GameData.factions()[Rng.make("lobby:fac:%d" % k, seed).bounded(15)]`.
- The list for every seat, human or bot, is built on a scratch state (the same as `make_golden.seats_of` and the smoke
  `_seats`):
  ```
  var tmp := BattleState.make(setup)
  for k in n: tmp.add_seat(k / P, "", true, false, "")
  tmp.seats[k].fac = fac_k
  BtArmy.auto_list(tmp, k, Rng.make("lobby:%d" % k, tmp.seed))
  list_k = tmp.seats[k].list
  ```
- Always pass a list: an empty list makes `start_match` pick a random faction.
- A PackedInt32Array list is used as is.
- A human seat with pid "" gets pid `"L<seat>"` at `start()`; read it back from `b.st.seats[h].pid`.

**Validation keys (Thai + English):**
- more than one human seat (cannot happen through the UI);
- more than 6 seats;
- w too small: at least 24 + 6 × seats, otherwise suggest the next size;
- unknown army, theme or terrain.

## 4. Battle with placeholders (battle track)

### 4.1 Egg figure mode (`table/figures/egg_shapes.gd`, `class_name EggShapes extends RefCounted`; floats allowed)

**Base radius R (metres = game inches).** It equals the exporter's `baseR`, so egg rings match kit rings:

```
static func base_r(k) -> float:
    var r := GameData.base_r_mi(k)
    return 0.62 if r <= 800 else roundf(r * 0.01727) / 20.0     # 0.62 … 6.9
```

**Size class** of `GameData.ty(k)`, tested in this order (counts over all 274 types):

| Class | Test | Types | Height | Widest radius | Length along z |
| --- | --- | --- | --- | --- | --- |
| `titan` | `ttn` | 15 | 3.4 R | 0.70 R | 0.70 R |
| `giant` | `gk` | 3 | 2.9 R | 0.70 R | 0.70 R |
| `vehicle` | `veh` | 6 | 1.6 R | 0.70 R | 1.0 R (low and long) |
| `infantry` | `inf` and r_mi ≤ 800 | 155 | 2.82 R (≈ 1.75 m) | 0.70 R | 0.70 R |
| `big` | `inf` | 10 | 2.75 R | 0.70 R | 0.70 R |
| `cavalry` | r_mi ≤ 1200 and w ≤ 5 | 25 | 2.0 R | 0.60 R | 1.0 R |
| `walker` | everything else | 60 | 2.55 R | 0.70 R | 0.70 R |

**Egg profile** (y / height, radius / widest), a lathe from the base up, closed by a disc at the bottom:
`[(0.00, 0.55), (0.06, 0.85), (0.18, 0.98), (0.32, 1.00), (0.50, 0.95), (0.68, 0.80), (0.84, 0.56), (0.95, 0.30), (1.00, 0.00)]`
- Long classes scale the lathe's z by length / width **inside the mesh**.
- A small darker nub on +z at 0.6 height shows facing.
- Colour: ivory `Color(0.86, 0.82, 0.74)`, nub `Color(0.55, 0.48, 0.40)`.
- The widest radius never exceeds 0.70 R, so the ring (0.814 R to 1.1 R) stays visible from above.

**`EggShapes` API:**
- `class_of(k) -> String`, `base_r(k) -> float`, `size_of(k) -> Vector3(R, height, length)`.
- `mesh(cls: String, simple: bool) -> ArrayMesh`: cached in a static dictionary, built with `PropsLayer.Geo`.
  - Simple (lo/min): 8 sides × 4 bands, ≤ 64 triangles.
  - Full (hi/mid): 14 sides × 8 bands, ≤ 160 triangles.
- `PROFILE` is a constant.

**Flyers** (optional): lift the egg by `data/fly.json` `alt`; a missing key uses the `valkyrie` entry. The ring stays on
the ground.

**`FigurePool` switch** (surgical, in `table/figures/figure_pool.gd`):
- Add `const STYLES := ["egg", "kit"]`, `var style := "kit"` and `func set_style(s: String) -> void`.
- In `build()`, right after `_clear_nodes()`: `if style == "egg": _build_eggs(); return`. The kit path below stays
  byte-identical.
- `_build_eggs()`: one `MultiMeshInstance3D` per class present, named `Egg_<cls>`, stored in `_mmis`.
  - `use_colors = true` with a white instance colour (CONTRACT §3, or the eggs render black);
    `use_custom_data = true` with `NO_PAINT`.
  - Instance transform: `Transform3D(Basis(Vector3.UP, f.yaw).scaled(Vector3.ONE * f.radius), f.pos)`, i.e. yaw plus a
    **uniform** R only. A non-uniform instance scale bends the shader's normals.
  - `material_override = _figure_material()`, so `set_lighting` and `set_per_vertex` apply as for kits.
  - `_skinned_count = 0`.
- `counts()` adds `"style"`. In egg mode, `"kits"` is the number of egg MultiMeshes (≤ 7).
- `set_stress` in egg mode adds `STRESS_RIGID + STRESS_SKINNED` eggs (all rigid) from non-hidden `GameData.types()`.

**`TableView`** (surgical, `table/table_view.gd`; new code in one block at the end of the file marked
`# ---- โต๊ะรบจริง (LOBBY_SPEC §4) ----`, plus the one-line hooks named here):
- `@export var figure_style := ""`: "" means follow `App.fig` (read like `gfx`, by `get_node_or_null(^"/root/App")`).
- `func effective_style() -> String`:
  - `kit` falls back to `egg` when `KitLibrary.list_kits()` is empty (logged once);
  - otherwise the export or the App value.
- Set the pool style before each `figures.build(...)` (one line in `build_look` and in `apply_level`'s rebuild).
- `func set_figure_style(s)`: sets the export and rebuilds the figures and rings.
- `_compose_figures()`:
  - In egg mode, the demo uses `EggShapes.base_r` and skips the kits-on-disk early return.
  - First line: `if _battle_mode: return _battle_list`.
- `signal picked(fig: int, ground: Vector3)`: emitted at the end of `_on_tapped` (fig = nearest figure within reach,
  or −1).
- `func build_battle(st: BattleState) -> void`:
  - sets `_battle_mode` and `_battle_list` from `st.units`;
  - calls `rebuild({"seed": st.seed, "w": st.w, "theme": st.theme, "terrain": st.terrain, "buildings": st.buildings,
    "density": st.density_h * 10})`;
  - adds `Kind.OBJECTIVE` rings at `st.objs` (radius 3.0, owner-tinted through `BtObjectives.ctl`).
- `func sync_battle(st: BattleState) -> void`: figures and rings from `st` again, without rebuilding the field.
- `func fig_unit(i: int) -> String`.
- `func show_selection(unit_ids: PackedStringArray)`: SELECT rings.
- `func show_dest(p: Vector3)`: a DEST ring; `Vector3.INF` hides it.
- `func end_battle()`: `_battle_mode = false`.
- Each figure: `FigurePool.make(u.t, u.side, Vector3(u.x / 1000.0, terrain.height_at(x, z), u.z / 1000.0),
  atan2(float(s.fx), float(s.fz)), EggShapes.base_r(u.t))` with `s = st.squad(u.sq)`. Its ring has radius R × 1.1 and the
  colour `team_colour(u.side)`. Deployment, spawning and rez send no per-figure events, so always rebuild from
  `st.units`.
- The default demo path (`build_look` with `_battle_mode` false) behaves exactly as before.

**Kit mode** uses the same figure list. `FigurePool.build` in kit mode instantiates skinned figures, which is heavier, so
`sync_battle` runs at most every 250 ms in kit mode. Eggs rebuild on every sync.

### 4.2 Match runner (`ui/battle/match_runner.gd`, `class_name MatchRunner extends RefCounted`, no Node)

The only bridge between the screen and the rules. Start from the probe
`<scratchpad>/godot-lobby/drive_human.gd`
(read only; it played 6 human-vs-bot games to OVER with identical replay digests).

```
class Rec extends Battle:                       # catches every event, also from bot_step/flush
    var evs: Array[Dictionary] = []
    func apply(act: Dictionary) -> Array[Dictionary]:
        var out := super(act); evs.append_array(out); return out
func _init(plan: Dictionary)                    # plan = SeatPlan.build(...); base := Battle.make(setup, seats, {});
                                                # b := Rec.new(); b.st = base.st; b.seed = base.seed
func start() -> Array[Dictionary]               # b.start() once; returns its events
func step() -> Dictionary                       # {"state": "acted"|"wait_human"|"over"|"stuck", "events": [...]}
```

`step()` is the pump from the battle map:
1. If `st.over`, return over.
2. If `st.pend` is not empty, call `flush(true, {"online": false})`; if the act log grew, return acted.
3. Let `human_turn` = the human team's turn in move / shoot / charge.
4. If `bot_step() != ""`, return acted. Bot team-mates go first.
5. If `human_turn`, then:
   - with `auto_human` on, return `auto_step()`;
   - otherwise return `wait_human`.
6. `e := BtBot.finished_act(st)`; if it is not empty, set `e.pid = ""`, apply it, and return acted.
7. Call `flush(true, …)`; if the act log did not grow, return stuck. That never happened in 36 probe games.

Human acts. Every act carries `"pid": st.seats[h].pid`; dice come from `st.rng("dice:%d" % h)` (at most 60).
- `can_select(s) -> bool`: the canAct gate (`s.side == st.turn`, the seat is human and not done, `st.pend` is empty) and,
  by phase:
  - move: `not s.moved`;
  - shoot: `not s.shot` and (`BtAbilities.gun(s.ti)` is not empty, or `BtAbilities.num(s.ti, "heal") != 0`);
  - charge: not `s.ch_done`, `s.adv` or `s.fell`, and not `BtSquads.is_engaged(st, s)`.
- `move(s, x_mi, z_mi, fall_back) -> String`: `BtMoves.try_move` returns the why-not key, or "" after applying
  `r.act`.
- `advance(s)` sends `adv` with a roll; `stay(s)`; `skip(s)` (shoot / charge).
- `shoot(s, t) -> String`:
  - `BtCombat.shot_why_not`, then `atk_math(st, s, t, BattleState.HOW_SHOOT)`;
  - apply `atk` with `"hit"` = [] when `m.tr`, else `m.shots` dice;
  - then flush.
- `charge(s, t) -> String`: `BtCombat.charge_why_not`, then `chg`, then flush (overwatch, the charge roll and the move
  into contact).
- `end_phase() -> String`:
  - only in move / shoot / charge with `st.pend` empty;
  - `flush(true, …)`, then `{"a": "done", "ph": st.phase_name(), "pid": pid}`;
  - never "" for `ph`, and never `endph` in command.
- `auto_step()` (the "ให้บอทเล่นแทน" button) takes the first human squad that still needs to act, in `st.alive_squads()`
  order, and applies:
  - move: `BtBot.move_decision(st, s)`, plus `BtMoves.plan_move` for an smove;
  - shoot: `BtBot.shoot_act(st, s, st.rng("dice:%d" % h))`;
  - charge: `BtBot.charge_act(st, s)`.

  It sets the human pid and goes through `apply`. These are the bot's own policy functions, so no rule is
  re-implemented. When nothing is left, it calls `end_phase()`.
- Helpers: `winner() -> int` (team, `BattleState.DRAW` = −1), `over_why() -> String`, `human_team() -> int`,
  `take_events() -> Array[Dictionary]`, `digest() -> String`, and `run_to_end(max_steps) -> String` (headless: auto
  everything; used by tests).
- Save, rematch and replay: `setup_dict()` + seats + `actlog.acts()` replay to the same digest. Tested; there is no save
  UI yet.

### 4.3 Battle screen (`ui/screens/battle_screen.tscn`, `class_name` not required)

- **Table.** `get_tree().get_first_node_in_group("table_view")`. If there is none (a standalone test), it instances
  `scenes/battle_table.tscn` with `auto_build = false` as its own child. On begin and show, it makes the table visible,
  sets `PROCESS_MODE_INHERIT` and makes the table camera current. On hide or exit, it hides the table, sets
  `PROCESS_MODE_DISABLED` and calls `end_battle()`.
- **API.**
  - `begin(plan: Dictionary)`: builds a `MatchRunner`, calls `start()` and `table.build_battle(st)`.
  - `set_speed("normal"|"fast"|"instant")`.
  - `is_over() -> bool`, `runner`.
- **Pacing.** A `Timer` drives `runner.step()`, never `_process`: 0.3 s normal, 0.08 s fast, and "instant" for tests
  (steps until 12 ms of the frame are used).
  - After any step that grew the act log, the screen calls `table.sync_battle(st)` and the HUD refresh.
  - On `wait_human` the Timer stops; a human act or Auto starts it again. So the screen does no per-frame work while
    waiting, on every level.
- **HUD.** The root Control uses `MOUSE_FILTER_IGNORE` (taps must reach `CameraRig`); panels use STOP.
  - `%TurnLabel`: `I18n.t("รอบ {r} / {n} · ตาของ{team} · เฟส{phase}")`. Phase names come from `data/phases.json` `nm`
    (คำสั่ง / เคลื่อนที่ / ยิง / บุก / ตะลุมบอน, all already translated); team names from `teams.json`.
  - VP chips per team in obj games: team colour + `st.vp[t]`.
  - `%SquadCard`: the selected squad's name (`DatasheetText.name_of`), models alive and wounds.
  - Phase hint on the human's turn:
    - move: "แตะหน่วยของคุณ แล้วแตะพื้นเพื่อเดิน";
    - shoot: "แตะหน่วยของคุณ แล้วแตะศัตรูเพื่อยิง";
    - charge: "แตะหน่วยของคุณ แล้วแตะศัตรูเพื่อบุก".
  - Action buttons: move phase "วิ่ง" (advance), "อยู่กับที่", and "ถอย" (when engaged: the next ground tap is a fall
    back); shoot / charge phase "ข้าม".
  - `%DoneButton` "จบเฟส ›": enabled only in move / shoot / charge, on the human's turn, with `st.pend` empty.
  - `%AutoButton` "ให้บอทเล่นแทน": a toggle; on, `MatchRunner.auto_human` plays the human seat, so a game can always
    finish.
  - `%SpeedButton` "เร็ว" / "ปกติ" and `%QuitButton` "‹ ออก" (the leave confirm).
  - `%LogText`: the last 8 lines, from events through `BattleText`:
    - TURN, PHASE;
    - ATTACK_STAGE hit / wound / save with the dice as digits ("ทอยโดน: 6 5 3 1");
    - deaths summed per step ("ล้ม {n} ตัว");
    - CHARGE, SHOCK, OVER.
    Unknown events are not shown. Dice are text only; the dice tray is out of scope.
- **Tap logic** (from `table.picked(fig, ground)`):
  - Your own selectable squad → select it (SELECT rings under its models).
  - With a selection in move → ground point to MI ints (`roundi(p.x * 1000)`), then `runner.move`.
  - In shoot / charge, an enemy figure → `runner.shoot` / `runner.charge`.
  - A non-empty why-not key shows its Thai text (`BattleText.why(key, args)`). Every key in `BtMoves.try_move`,
    `shot_why_not` and `charge_why_not` must be covered: grep `"key":` in `core/battle/moves.gd` and `combat.gd`.
  - Optional: a range ring (DEST kind, radius = `BtMoves.move_range(s) / 1000.0`) around the selected squad.
- **End panel** (`%EndPanel`, shown when the runner says over; the Timer stops):
  - `%EndTitle`: "คุณชนะ!", "คุณแพ้" or "เสมอ" with a human seat; without one, "{team} ชนะ!" or "เสมอ".
  - A reason line from OVER `why`: over_last "เหลือทีมเดียว", over_rounds "ครบรอบ — แต้มชัยสูงสุด", over_kill_rounds
    "ครบ 30 รอบ".
  - VP per team and rounds played.
  - Buttons: `%LobbyButton` "กลับล็อบบี้" (`App.pop()`), `%AgainButton` "เล่นอีกครั้ง" (same plan, new seed,
    `begin(...)`), and `%LookButton` "ดูสนาม" (hides the panel; a small "ผลการรบ" button brings it back).
- **Figure style.** It is read from `App.fig` through `TableView.effective_style()` at `build_battle`. Kit mode needs the
  generated kits; without them it falls back to eggs.

## 5. Settings additions (menu track)

`ui/screens/settings.tscn` (full-screen, opaque). Every change calls the App setter, then `App.save_settings()`. Live 3D
re-reads on show (§1).

| Row | Control (unique names) | App |
| --- | --- | --- |
| ภาษา | `LangButton` ("ENGLISH" / "ไทย") | `set_lang("th"|"en")` |
| ระดับกราฟิก | `%GfxHi` สูง · `%GfxMid` กลาง · `%GfxLo` ต่ำ · `%GfxMin` ต่ำสุด (มือถืออ่อน) (existing keys), one ButtonGroup | `set_gfx(l)` |
| รูปตัวละคร | `%FigEgg` "ตัวไข่ (ชั่วคราว)" · `%FigKit` "โมเดลชุดเดิม". Kit is disabled, with "ไม่พบชุดโมเดลในเครื่องนี้", when `KitLibrary.list_kits()` is empty | `set_fig("egg"|"kit")` |
| ปุ่มบนจอ | `%TouchAuto` "อัตโนมัติ" (existing key) · `%TouchOn` "เปิด" · `%TouchOff` "ปิด" (existing keys) | `set_touch("auto"|"on"|"off")` |
| — | `%GpuCheckButton` "ตรวจการ์ดจอ ›" pushes `ui/screens/gpu_check.tscn` and connects its `army_requested` to push the army picker | — |
| — | `%BackButton` "‹ กลับ" (existing key) | pop |

**Sound.** No sound exists yet, so no sound row. `App.snd` stays as it is.

**GPU check** (menu track adapts `gpu_check.gd`):
- On `_ready` it calls `table.rebuild(TableView.DEFAULT_SETUP)` to rebuild the demo, then shows the table, sets
  `PROCESS_MODE_INHERIT` and makes the table camera current.
- On `_exit_tree` it hides the table again and sets `PROCESS_MODE_DISABLED`.
- Its measuring and the army button are unchanged.

## 6. File ownership

### 6.1 Tracks

**menu** (main menu, app flow and screen stack, settings, shared i18n plumbing, input map, CI wiring, release
bookkeeping)
- `godot/app/app.gd`, `godot/ui/i18n.gd`, `godot/ui/i18n/menu.json` (and the two empty seed files, see M0),
  `godot/project.godot`
- `godot/ui/theme/candle_style.gd` (new), `godot/ui/widgets/title_art.gd` (new)
- `godot/ui/screens/main_menu.tscn/.gd` (new), `godot/ui/screens/settings.tscn/.gd` (new),
  `godot/ui/screens/gpu_check.gd/.tscn`
- `godot/scenes/main.gd`, `godot/scenes/main.tscn`
- `godot/core/version.gd` (the `APP_VER` line only: "ใหม่ 0.1" → "ใหม่ 0.2")
- `godot/tools/validate_data.py` (the i18n dictionary reads the fragments)
- `godot/tests/run.sh`, `.github/workflows/godot.yml` (render suites by glob; a flow stage)
- Tests: `godot/tests/unit/test_app.gd`, `test_i18n.gd`, `test_i18n_fragments.gd` (new), `test_input_map.gd` (new),
  `test_menu_text.gd` (new); `godot/tests/render/test_main_screens.gd`, `test_army_screen.gd`, `test_menu_screens.gd`
  (new); `godot/tests/flow/test_lobby_flow.gd` (new)
- Docs and notes, at the end: `godot/docs/STATUS.md`, `godot/README.md`,
  `web/สิ่งที่เปลี่ยน-12พ.ย.69-รุ่นใหม่0.2-หน้าแรกและล็อบบี้.md`

**lobby** (the walkable hall)
- `godot/scenes/hall/` (all new): `hall_world.tscn`, `hall_world.gd` (HallWorld), `hall_layout.gd` (HallLayout, pure),
  `hall_builder.gd` (HallBuilder: meshes and colliders), `hall_avatar.gd` (HallAvatar), `hall_camera.gd` (HallCamera),
  `flame.gdshader`
- `godot/ui/screens/hall_screen.tscn/.gd` (new; the only place for the hall's Thai strings)
- `godot/ui/widgets/touch_stick.gd` (new, TouchStick)
- `godot/ui/i18n/hall.json`
- Tests: `godot/tests/unit/test_hall_layout.gd`, `test_hall_text.gd`; `godot/tests/render/test_hall.gd`
- Before M0, start with: HallLayout + its test, HallBuilder, HallAvatar and HallCamera driven from a scratch scene.

**battle** (setup panel, battle screen, HUD, end panel, the placeholder figure mode)
- `godot/table/figures/egg_shapes.gd` (new), `godot/table/figures/figure_pool.gd` (surgical),
  `godot/table/table_view.gd` (surgical, the marked block)
- `godot/ui/battle/` (all new): `match_runner.gd` (MatchRunner), `seat_plan.gd` (SeatPlan), `battle_text.gd`
  (BattleText: events and why-not keys to text)
- `godot/ui/screens/battle_setup.tscn/.gd`, `godot/ui/screens/battle_screen.tscn/.gd` (new)
- `godot/ui/i18n/battle.json`
- Tests: `godot/tests/unit/test_egg_shapes.gd`, `test_seat_plan.gd`, `test_match_runner.gd`, `test_battle_text.gd`;
  `godot/tests/render/test_battle_screen.gd`; `godot/tests/render/test_budgets.gd` (egg phase; pin kit for the existing
  phases); `godot/tests/render/test_field_look.gd` (only if it needs the style pinned to stay green)
- Before M0, start with: EggShapes + its test, the FigurePool / TableView switch, SeatPlan and MatchRunner + their tests.

**Nobody edits:** `ui/screens/army.gd/.tscn`, `ui/screens/army_roster.gd`, `ui/widgets/kit_turntable.gd`,
`ui/widgets/datasheet_text.gd`, `table/camera_rig.gd`, `table/rings.gd`, `table/props_layer.gd`, `core/**` (apart from
`APP_VER`), `ui/i18n_extra.json`, `data/**`, `assets/**`, `scenes/probe/**`, `scenes/battle_table.tscn`, and this spec.

### 6.2 M0: the menu track's integration scaffolding (first, small)

1. **`app/app.gd`**:
   - Settings and helpers:
     ```
     const FIG_STYLES: PackedStringArray = ["egg", "kit"]
     const TOUCH_MODES: PackedStringArray = ["auto", "on", "off"]
     const DEFAULT_FIG := "egg"
     const DEFAULT_TOUCH := "auto"
     var fig := DEFAULT_FIG
     var touch := DEFAULT_TOUCH
     var settings_file := SETTINGS_PATH          # tests point it elsewhere
     func set_fig(s: String) -> bool
     func set_touch(m: String) -> bool
     func touch_active() -> bool                 # touch == "on" or (touch == "auto" and OS.has_feature("mobile"))
     func replace(scene: PackedScene) -> Node    # removes the top screen without showing the one below, then pushes
     ```
   - `load_settings` / `save_settings` default to `settings_file` and carry the keys `fig` and `touch` (unknown values
     → defaults). `reset_settings` covers them.
   - `back()` first calls `current().handle_back()` when the screen has it (true = handled), then pops or quits as
     today.
   - `_unhandled_input` turns the `back` action into `back()` and marks the input handled.
2. **`project.godot`**:
   - Add `[input]` with physical keycodes (layout-independent, so WASD works with a Thai keyboard), written the way the
     editor writes them (`"device": -1`, `"physical_keycode": <code>`, `"keycode": 0`):

     | Action | Keys (physical) |
     | --- | --- |
     | `move_forward` | W (87), Up (4194320) |
     | `move_back` | S (83), Down (4194322) |
     | `move_left` | A (65), Left (4194319) |
     | `move_right` | D (68), Right (4194321) |
     | `run` | Shift (4194325) |
     | `interact` | E (69) |
     | `back` | Escape (4194305) |

   - Add `internationalization/locale/include_text_server_data=true`, so exported builds wrap Thai at word breaks.
3. **`ui/i18n.gd`**:
   - `const FRAGMENTS: PackedStringArray = ["res://ui/i18n/menu.json", "res://ui/i18n/hall.json", "res://ui/i18n/battle.json"]`,
     merged into `extra` after `i18n_extra.json` in `_init`. A missing file is skipped quietly; an existing key is not
     overwritten.
   - Create `ui/i18n/hall.json` and `ui/i18n/battle.json` as `{}`. From then on they belong to the lobby and battle
     tracks.
   - Seed `ui/i18n/menu.json` with the shared new words: ตั้งค่า "Settings", ออนไลน์ "Online", เร็วๆ นี้ "Coming soon",
     คุณ "You", ล็อบบี้ "Lobby", ออก "Quit", ตกลง "OK".
4. **`tools/validate_data.py`**: `ui_dictionary()` also reads `ui/i18n/*.json` (sorted), with the same schema and
   no-Thai-in-English checks.
5. **`ui/theme/candle_style.gd`** (`class_name CandleStyle extends RefCounted`):
   - Colours:
     ```
     BG #140e0a · PANEL #231811 (alpha 0.92) · EDGE #6b4a2a · GOLD #e8b860 · TEXT #f3e6d0 · MUTED #b8a58a · DANGER #d8746a
     ```
   - `BOLD := preload("res://assets/fonts/Sarabun-Bold.ttf")`.
   - Static functions:
     - `button(b: Button, primary := false)`: StyleBoxFlat normal / hover / pressed / disabled / focus, corner 10,
       min height 56, font 22;
     - `panel(c: Control)`;
     - `title(l: Label, size := 40)`;
     - `toggle_group(buttons: Array) -> ButtonGroup`;
     - `safe_margins(m: MarginContainer)`: 16 px plus `DisplayServer.get_display_safe_area()` converted to canvas
       units.
   - The global theme `.tres` stays as it is (the army screen's layout tests depend on it).
6. Run `test_app`, `test_i18n`, `test_i18n_fragments`, `test_input_map` and the data lint, then note "M0 done" with the
   time.

### 6.3 Contracts between tracks

**Scene paths**, always referenced with `load(PATH)` at use time:

| Constant | Path | Owner |
| --- | --- | --- |
| `MAIN_MENU` | `res://ui/screens/main_menu.tscn` | menu |
| `SETTINGS_SCREEN` | `res://ui/screens/settings.tscn` | menu |
| `HALL_SCREEN` | `res://ui/screens/hall_screen.tscn` | lobby |
| `BATTLE_SETUP` | `res://ui/screens/battle_setup.tscn` | battle |
| `BATTLE_SCREEN` | `res://ui/screens/battle_screen.tscn` | battle |
| `ARMY` | `res://ui/screens/army.tscn` | existing |
| `GPU_CHECK` | `res://ui/screens/gpu_check.tscn` | existing (menu) |

**Screen contracts** (node names are unique names `%Name` on the screen root; methods are duck-typed):

| Screen | Must provide |
| --- | --- |
| Main menu | `%PlayButton`, `%OnlineButton`, `%SettingsButton`, `%LangButton` (node named `LangButton`), `%QuitButton`, `%VersionLabel`, `%Title`, `%Toast`, `%QuitConfirm`; `handle_back() -> bool`; `refresh()` |
| Settings | the names in §5; `refresh()` |
| Hall screen | `world` (the `HallWorld` child named `HallWorld`), `station() -> String`, signal `station_changed(id)`, `use_station()`, `handle_back() -> bool`, `%UseButton`, `%Stick`, `%MenuButton`, `%SettingsButton`, `%SoonPanel`, `%Hint`; station ids `battle`, `army`, `settings`, `online`, `adventure`, `exit` |
| HallWorld | `avatar` (HallAvatar), `camera_rig` (HallCamera, with `camera: Camera3D`), `apply_level(l)`, `set_active(on)`, `set_sign_text(id, text)`, `set_stick(v: Vector2)`, `station() -> String`, `counts() -> Dictionary` (`flames`, `blockers`, `signs`, `level`); joins group `gfx_level` |
| Battle setup | the API in §3; `%StartButton`, `%BackButton`, `%Errors` |
| Battle screen | `begin(plan)`, `set_speed(s)`, `is_over()`, `runner`, `handle_back()`; `%TurnLabel`, `%LogText`, `%DoneButton`, `%AutoButton`, `%SpeedButton`, `%QuitButton`, `%EndPanel`, `%EndTitle`, `%LobbyButton`, `%AgainButton` |
| TableView (battle edits) | the additions in §4.1; the group `table_view` and every existing method unchanged |

**App and I18n** (M0): `App.fig`, `App.touch`, `App.touch_active()`, `App.replace()`, `App.settings_file`,
`handle_back()` support; input actions `move_forward`, `move_back`, `move_left`, `move_right`, `run`, `interact`,
`back`; `CandleStyle`.

**Groups**:
- `table_view`: TableView (existing).
- `gfx_level`: 3D roots other than TableView that implement `apply_level(l)` (HallWorld).

Settings does not need to call into them (re-read on show); the GPU check keeps calling the table directly.

## 7. Tests

### 7.1 Rules for every new test

- **Unit tests** go in `tests/unit/test_*.gd`, extend `res://tests/testing.gd` and are discovered automatically. They
  also run inside the exported Windows exe and on arm64, so they need no display, no window and no input; a pure
  `RefCounted` or headless mesh building only.
- **Render tests** go in `tests/render/test_*.gd`: `extends SceneTree`, `first_run_guess = false`, `TEST_OUT` for PNGs,
  `PASS` / `FAIL` lines, exit 1 on failure. Model them on `test_army_screen.gd`.
  - **Sizes**: run each check at window sizes 640x360, 1280x720 and 1280x576 (20:9, logical 1600x720) by setting
    `get_root().size` and waiting about 6 frames. Verified under xvfb: 640x360 gives a logical 1280x720 canvas and
    1280x576 gives 1600x720.
  - **No overflow**: every visible Control's global rect stays inside the visible rect, and inside its parent unless that
    parent is a ScrollContainer. No two sibling buttons overlap. Every Button is at least 44 x 44 logical px.
  - **Thai and English**: in English mode no visible `Label` / `Button` / `OptionButton` item / `LineEdit` placeholder /
    `Label3D` text contains `[฀-๿]`, except the node named `LangButton`. In Thai mode the titles are Thai.
- **Whole-key literal tests**: each track has one, copying
  `test_army_roster.test_every_thai_literal_of_the_screen_is_a_whole_key`, over its own `.gd` / `.tscn` files: every Thai
  literal is a whole key of `I18n`.
- **Never** delete, skip or loosen an existing check. When a behaviour changed on purpose (the first screen, the table
  not built at startup), update the expectation in the same change and write the reason in a comment and in the final
  report.

### 7.2 menu

- `test_app.gd`:
  - the round-trip list becomes `[gfx, lang, snd, server, fig, touch]`;
  - bad values fall back to defaults;
  - `touch_active()` for auto / on / off;
  - `replace()` keeps the depth and never shows the screen below;
  - `back()` honours `handle_back()`.
- `test_i18n_fragments.gd`:
  - every fragment parses as a Thai → English object with no Thai in values;
  - no key in two fragments;
  - no fragment key is already in `I18n.EN`, `ui/i18n_extra.json` or `data/i18n_en.json`;
  - `I18n.t` finds fragment keys.
- `test_input_map.gd`: the seven actions exist with the physical keys of §6.2, and `Input.parse_input_event` of a
  physical W makes `Input.is_action_pressed("move_forward")` true.
- `test_menu_text.gd`: whole keys of `main_menu.gd/.tscn`, `settings.gd/.tscn`, `title_art.gd`, `candle_style.gd` and
  `gpu_check.gd`.
- `test_main_screens.gd` (updated, with the reason):
  - `main.tscn` opens the main menu; the table is built lazily, hidden and disabled;
  - the menu passes the Thai / English scan;
  - Settings → GPU check shows the demo table with 400 figures and 400 rings, with the style pinned by
    `App.set_fig("kit")` before `add_child` and restored after;
  - the existing table API checks still run there.
- `test_army_screen.gd` (updated): it reaches the army picker via Settings → GPU check → army button. Its table
  visibility checks follow the GPU check; every other check is unchanged.
- `test_menu_screens.gd`:
  - main menu and settings at the three sizes in Thai and English;
  - every settings control changes App and persists through a test settings file;
  - the online button shows the toast;
  - Back / Esc opens the quit confirm, and Back again closes it;
  - on min nothing processes per frame on these screens;
  - PNGs `menu_th.png`, `menu_en.png`, `settings_th.png`, `settings_en.png` (`_<w>x<h>` suffix for other sizes).
- `tests/flow/test_lobby_flow.gd` (headless; it needs all three tracks):
  1. Load `main.tscn` with gfx `min`, lang `th`, fig `egg` and a test settings file.
  2. Press `%PlayButton`. The hall is current.
  3. Hold W with `Input.parse_input_event(InputEventKey physical_keycode = KEY_W, pressed = true)` until
     `hall.station() == "battle"` (cap 15 s real time), then release it. The avatar moved at least 3 m and is in no
     blocker.
  4. Press and release E. Setup is current.
  5. Configure 2 teams × 1, both bots ("kn" and "or"), size `s`, obj, 3 rounds, 300 points, seed 4242, then `start()`.
     The battle screen is current, with egg figures (`counts().style == "egg"`, `skinned == 0`, figures ==
     `st.units.size()`).
  6. `set_speed("instant")` and wait for `is_over()` (cap 60 s). `%EndPanel` is visible and `%EndTitle` is not empty.
  7. Press `%LobbyButton`. The hall is current, its world is active and the table is hidden.
  8. Send Esc. The main menu is current. PASS.

### 7.3 lobby

- `test_hall_layout.gd` (unit, pure):
  - station rects, pillars and stands do not overlap and stay inside the hall;
  - the spawn is in no trigger;
  - on a 0.25 m grid with the avatar radius 0.35, a flood fill from the spawn reaches a point inside every station's
    trigger;
  - `station_at` gives the expected id at sample points and "" in the open;
  - ties go to the nearest station.
- `test_hall_text.gd`: whole keys of `hall_screen.gd/.tscn` and `touch_stick.gd`; every station name and sign has Thai
  and English.
- `test_hall.gd` (render):
  - **Entry**: the hall is reached from the main menu (`%PlayButton`). The `table_view` node stays hidden and disabled,
    and the hall camera is current.
  - **Movement**:
    - W moves the avatar along the camera's forward direction;
    - D moves it right;
    - Shift + W covers at least 1.6 times the walk distance in the same time;
    - after an orbit of 90°, W follows the new forward direction;
    - holding W into the back wall, a pillar and the battle table stops at the surface (the avatar never enters a
      blocker rect).
  - **Camera**: after walking into each corner and orbiting there, the camera stays inside the interior box shrunk by
    0.1 m, in no blocker, and below y = 6.
  - **Stations**:
    - each station's prompt shows its translated name;
    - E at `army` opens the army picker and Back returns, with the hall visible and active again;
    - the same for `settings`;
    - `online` and `adventure` show `%SoonPanel` and stay;
    - `exit` and `%MenuButton` return to the main menu.
  - **Touch**: with `App.set_touch("on")`, `%Stick` and the touch prompt show. Simulated `InputEventScreenTouch` /
    `ScreenDrag` on the stick moves the avatar; past 0.85 it runs. With "off" the stick is hidden.
  - **Thai and English** at the three sizes, Label3D signs included.
  - **min level**: after 10 idle frames, none of the avatar, camera, hall screen or stick is processing. Draw calls are
    at most 40 and primitives at most 40k (`RenderingServer.get_rendering_info`, as in `test_budgets`). The numbers for
    all four levels are printed, and lo is checked against §2.6.
  - PNGs `hall_th.png`, `hall_en.png`, `hall_min.png`, `hall_touch.png`.

### 7.4 battle

- `test_egg_shapes.gd` (unit):
  - `class_of` over all 274 types gives the counts 155 / 10 / 25 / 60 / 6 / 3 / 15;
  - `base_r` gives 0.62 for r_mi ≤ 800 and the formula elsewhere (largest 6.9);
  - the widest radius is ≤ 0.70 R for every class;
  - simple meshes have ≤ 64 triangles and full meshes ≤ 160;
  - meshes are cached;
  - no key has a NaN size.
- `test_seat_plan.gd` (unit):
  - modes pvp / ffa / team;
  - team-major seats;
  - at most one human;
  - every list is non-empty and within the budget (`BtArmy` points);
  - a random army is the same for the same seed;
  - every validation error key comes back for its case;
  - w even and inside 24..120, rounds clamped to 3..10, never `"d"`.
- `test_match_runner.gd` (unit, small tables of 36" and 300 points, about 0.1 s per game):
  - **Bot vs bot**: runs to over with a winner or a draw, and captures MOVE_STEP and DEATH events.
  - **A passive human** (done only) vs a bot: reaches over.
  - **An active human**:
    - `can_select` follows the gate;
    - a move to a reachable point applies;
    - a point far away gives `too_far`;
    - a shoot and a charge apply where legal;
    - `end_phase` is refused outside move / shoot / charge.
  - **Auto**: `auto_human` finishes a game.
  - **Replay**: replaying `actlog.acts()` on a fresh `Battle.make` + `start` gives the same digest.
  - Nothing writes `st` outside `apply`: the digest after replay is equal.
- `test_battle_text.gd`: whole keys of `battle_setup.*`, `battle_screen.*`, `battle_text.gd`, `seat_plan.gd` and
  `match_runner.gd`; every why-not key of moves / combat, every OVER `why` and every shown event template has Thai and
  English.
- `test_budgets.gd` (extended):
  - the existing kit phases pin `App.set_fig("kit")`;
  - a new egg phase per level, on the same 400-figure / 8-team scene: within the same per-level budgets, `skinned == 0`,
    at most 7 egg MultiMeshes, 400 rings, and on min at least 30 % fewer draw calls than the kit phase;
  - PNG `budgets_egg_<level>.png`.
- `test_battle_screen.gd` (render):
  - the setup panel at the three sizes in Thai and English, and START disabled with an error for a bad choice;
  - a 2-team bot game with eggs: every egg stands on its unit (within 1 cm on x/z), the ring count = units + objectives,
    ring colours = team colours;
  - a human game: a synthetic `picked` on the own squad selects it, a ground pick moves it (MOVE_STEP), `%DoneButton`
    ends the phase, and `%AutoButton` plays on to the end panel;
  - `%LobbyButton` pops;
  - on min nothing processes while waiting for the human (screen, table, camera rig);
  - with kits on disk, `App.set_fig("kit")` draws kits (`counts().style == "kit"`);
  - PNGs `battle_eggs_th.png`, `battle_eggs_en.png`, `battle_end.png`, `battle_kits.png`.

### 7.5 How to run

All commands run from `/home/user/candlelight-table`. `G=~/godot-bin/godot`, `T=<your TEST_OUT>` (§0.6).

```bash
# after adding class_name scripts / shaders (under the shared lock, §0.6)
flock <scratchpad>/godot-lobby/import.lock timeout 600 $G --headless --path godot --import
# one unit suite by name fragment (≤ a few s)
timeout 600 $G --headless --path godot -s tests/run_tests.gd -- test_match_runner
# one render suite
TEST_OUT=$T timeout 900 nice -n 10 xvfb-run -a -s "-screen 0 1280x720x24" $G --path godot --rendering-driver opengl3 \
  --resolution 1280x720 --audio-driver Dummy -s tests/render/test_hall.gd
# the flow test (headless)
TEST_OUT=$T timeout 600 $G --headless --path godot --audio-driver Dummy -s tests/flow/test_lobby_flow.gd
# data lint
python3 godot/tools/validate_data.py
# once, at the very end, after all three tracks are done (≈ 4 min here)
TEST_OUT=$T nice -n 10 bash godot/tests/run.sh full
```

The menu track changes the runners so that new suites run without anyone editing a list:
- `run.sh`: the render loop runs every `tests/render/test_*.gd` in sorted order. A new `== flow ==` stage runs every
  `tests/flow/test_*.gd` headless in both quick and full.
- `godot.yml`: the render step loops over `tests/render/test_*.gd` the same way, and a new step "Flow tests (headless)"
  runs `tests/flow/test_*.gd`.

The existing suites must stay green: all unit scripts (3,885 checks today), the data lint, the render probe, and
`test_lineup`, `test_budgets`, `test_main_screens`, `test_field_look`, `test_army_screen`, `test_anim_footslide`.

## 8. Out of scope now, and what the owner will see

**Not in this round:**
- online rooms and playing with friends (the gate and the menu button say "เร็วๆ นี้");
- the adventure (D&D) table;
- real models (the eggs stand in; the old kits stay switchable);
- skeletal animation on figures, walking animation (figures snap to their new positions);
- a 3D dice tray (dice show as text), sound and music;
- deploy by hand (deployment is automatic, as in bot games);
- custom army lists for the human seat (an optional stretch, §3);
- saving a game, spectator controls, hot-seat play.

**What the owner will see** (APP_VER "ใหม่ 0.2"):
1. A candle-lit main menu.
2. The lobby hall: walk with WASD or arrows, Shift to run, mouse to turn the camera; on the phone, a stick at the bottom
   left and a use button.
3. Walk to the war table, press E, set up a game with any of the 15 armies, 2–4 teams, you or bots in each seat, map
   and goal.
4. Watch or play the game with egg figures and team rings, use "ให้บอทเล่นแทน" at any time, see the winner, and come back
   to the hall.
5. Settings switch language, graphics level, egg or old models, and touch buttons.

Thai release note (menu track, at the end): `web/สิ่งที่เปลี่ยน-12พ.ย.69-รุ่นใหม่0.2-หน้าแรกและล็อบบี้.md`. It says in plain
Thai what changed, what was tested, and that no server re-embed is needed (godot-only change).
