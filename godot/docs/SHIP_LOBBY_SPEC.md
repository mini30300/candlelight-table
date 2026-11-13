# Warship deck lobby (ใหม่ 0.3) — build spec

Written 12 Nov 2026 for the new app (`godot/`, branch `claude/new-session-fsucoo`, draft PR #27), on top of commit
a79ee46 (ใหม่ 0.2). It **replaces §2.1, §2.2 and §2.6 of `LOBBY_SPEC.md`** (layout, look, per-level table) and the parts
of its §7.3 named in §9 below. Everything else in `LOBBY_SPEC.md` still holds unchanged: the flow and screen stack (§1),
the avatar (§2.3), the camera (§2.4), the HUD and touch controls (§2.5), the battle track, the settings, the i18n rules
(§0.7) and the test rules (§7.1). It is a separate file because LOBBY_SPEC is the closed build record of 0.2; one pointer
line goes into LOBBY_SPEC §2 (§8.4).

**The owner's request (12 Nov):** change the lobby so that it is aboard a big starship of the gothic kind he likes, and he
plans a random-reward system later (random gun parts and decorations).

**For the owner, in Thai:** ห้องโถงหินแสงเทียนกลายเป็น "ดาดฟ้ายานรบ" บนยานอวกาศที่ออกแบบเองทั้งหมด เพดานโค้งแหลมแบบโบสถ์
เสาเหล็กเป็นกลุ่ม ท่อและสายไฟ จอเขียว/อำพัน เทียนกับธงลายเทียนของโต๊ะเทียน และหน้าต่างบานใหญ่มองออกไปเห็นดาว ดาวเคราะห์
และยานลำอื่นลอยผ่านช้า ๆ ทุกจุดยังทำงานเหมือนเดิม: โต๊ะรบกลายเป็นโต๊ะแผนที่โฮโลแกรม คลังแสงกองทัพเปิดหน้าจัดกองทัพ
คอนโซลเปิดตั้งค่า ประตูเทียบยานคือออนไลน์ (เร็วๆ นี้) โต๊ะผจญภัย (เร็วๆ นี้) และจุดใหม่ "หีบสมบัติ" สำหรับระบบสุ่มของรางวัล
ที่จะทำทีหลัง (ตอนนี้แตะแล้วขึ้นว่าเร็วๆ นี้) การเดิน กล้อง และปุ่มทั้งหมดเหมือนเดิมทุกอย่าง

## 0. Decisions this spec fixes (do not re-decide)

| Topic | Decision |
| --- | --- |
| What changes | The look of the lobby, two station positions (online, new vault), one candle stand, two banners, the new vault station, the station names and signs listed in §1, the title plaque, `APP_VER`. |
| What stays exactly | Controls (WASD / arrows, Shift, E, mouse / touch orbit, wheel / pinch, stick, use button), `HallAvatar`, `HallCamera` (spring arm on walls and ceiling only, prop clearance, start yaw 0 / pitch −0.45 / arm 6.5, limits), the HUD nodes and their behaviour, the screen stack and every flow, the room box (x ∈ [−12, 12], z ∈ [−8, 8], walls 0.5 m, invisible ceiling collider at y = 6), the spawn (0, 0, 5) facing −z, the six column positions, the war table rect, the physics layers. |
| Names in code | Still **hall** (`scenes/hall/`, `HallLayout`, `HallBuilder`, `HallWorld`, `hall_screen.*`). No file is renamed. New files: `scenes/hall/hall_space.gd` (`HallSpace`), `scenes/hall/holo.gdshader`, `scenes/hall/ship_drift.gdshader`, `tests/unit/test_hall_space.gd`. |
| Place name on screen | **ดาดฟ้ายานรบ** / **Warship Deck** (the 3D title plaque, §2.6). Buttons that say ล็อบบี้ / Lobby (e.g. "‹ ล็อบบี้", "กลับล็อบบี้") stay as they are. |
| Design ownership | Our own gothic starship: pointed arches, ribbed vaults, clustered steel columns, bronze and brass, deck plating, pipes and cables, green / amber screens, candles, and our candle emblem (a candle flame inside a circle, as on today's banners). Built in code with `PropsLayer.Geo`; no textures, no imported or third-party assets, no images. |
| AGENTS rule 1 | No franchise names anywhere (code, strings, comments, file names, commits, docs, PNG names). **No third-party emblems, marks or jargon.** The only emblem is our candle. Distant ships are our own silhouettes. The data lint scans every file under `godot/` for the banned names; the PNG review (§9.4) checks the motifs by eye. |
| Lights | Still **no dynamic lights and no shadows on any level**. Candle glow and the new cool glow (holo, screens, viewport, airlock) are baked into vertex colours once at build time. All materials are unshaded. |
| Per-frame work | Unchanged rule: on lo and min no shader uses `TIME` and nothing runs `_process` / `_physics_process` while idle. All motion on hi / mid lives in vertex shaders (`TIME`), never in GDScript. |
| Random rewards | **No reward logic in this round.** The vault station only shows the coming-soon panel (§5). |

## 1. Names and every new string

All Thai literals stay in `ui/screens/hall_screen.gd` (the whole-key rule of LOBBY_SPEC §0.7); the 3D scripts under
`scenes/hall/` keep carrying no Thai. New pairs go into `ui/i18n/hall.json` (flat Thai → English, two-space indent, one
pair per line). Checked against `data/i18n_en.json`, `ui/i18n_extra.json`, `I18n.EN` and the fragments on 12 Nov: none of
the new keys exists yet.

| Constant in `hall_screen.gd` | Thai | English | Status |
| --- | --- | --- | --- |
| `NAMES.battle`, `SIGNS.battle` | โต๊ะรบ | Battle Table | existing key (data), kept |
| `NAMES.army`, `SIGNS.army` | คลังแสงกองทัพ | Armoury | **new** (replaces ตู้โชว์กองทัพ) |
| `NAMES.settings`, `SIGNS.settings` | ตั้งค่า | Settings | existing key (menu), kept |
| `NAMES.online` | ประตูเทียบยาน | Docking Airlock | **new** (replaces ประตูออนไลน์) |
| `SIGNS.online` | ออนไลน์ · เร็วๆ นี้ | Online · Coming soon | existing, kept (0.5: "ประตูเทียบยาน · เล่นกับเพื่อน", `NET_SPEC.md` §7.1) |
| `SOON.online` | ออนไลน์กับเพื่อน — เร็วๆ นี้ | Online with friends — coming soon | existing, kept (removed in 0.5, `NET_SPEC.md` §7.1) |
| `NAMES.adventure` | โต๊ะผจญภัย | Adventure Table | existing, kept |
| `SIGNS.adventure` / `SOON.adventure` | โต๊ะผจญภัย · เร็วๆ นี้ / โต๊ะผจญภัย — เร็วๆ นี้ | (existing) | kept |
| `NAMES.exit`, `SIGNS.exit` | ทางออก | Exit | existing, kept |
| `NAMES.vault` | หีบสมบัติ | Treasure Chest | **new** |
| `SIGNS.vault` | หีบสมบัติ · เร็วๆ นี้ | Treasure Chest · Coming soon | **new** |
| `SOON.vault` | หีบสมบัติ — เร็วๆ นี้: สุ่มรับชิ้นส่วนปืนและของตกแต่ง | Treasure chest — coming soon: win random gun parts and decorations | **new** |
| `PLACE` (title plaque) | ดาดฟ้ายานรบ | Warship Deck | **new** |

- **Remove** "ตู้โชว์กองทัพ" and "ประตูออนไลน์" from `hall.json`: `test_hall_text.test_hall_fragment_is_clean_and_used`
  fails on a key the hall screen no longer uses.
- Prompts are unchanged templates: `"{name} · กด E"` / `"{name} · แตะเพื่อใช้"` give "คลังแสงกองทัพ · กด E" →
  "Armoury · press E", "หีบสมบัติ · แตะเพื่อใช้" → "Treasure Chest · tap to use".
- The hint, the menu and settings buttons and "คุณ" are unchanged.

## 2. Deck layout (metres; y up; the camera starts looking toward −z)

### 2.1 The room

- **Box**: x ∈ [−12, 12], z ∈ [−8, 8], floor y = 0; walls 0.5 m thick outside the box; invisible ceiling collider at
  y = 6 (layer 1). All unchanged.
- **Nave and aisles**: the two column rows at x = ±8.5 split a 17 m nave (|x| < 8.5) from two 3.5 m side aisles.
- **Above y = 6 is visual only**: the vaults, ribs, cables, the top of the great window and the title plaque. The camera
  never goes there (ceiling collider + `room_clear`), so nothing above 6 needs a collider.
- **Back wall (z = −8)**: the great viewport (§2.4). Its collider is unchanged: the window is a hole in the *drawn* wall
  only; the wall body still blocks the avatar and the camera arm.
- **Walk area**: the box minus the blockers of §2.3 (avatar radius 0.35). The spawn (0, 0, 5) is in no trigger, and the
  war table's trigger still starts 3.4 m ahead (the flow test walks it).

### 2.2 Stations

Footprint = centre (x, z) and half size (x, z); `round` stations use a circle of radius h.x. Reach is measured from the
footprint edge, nearest station wins (unchanged rule). Height = the blocker's height. Sign = Label3D position, face = its
yaw (0 faces +z).

| id | Ship form (our design) | Footprint | Round | Reach | Height | Front ring (x, z) | Sign pos / face | Use |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `battle` | Holographic strategy table: heavy steel table, bronze rim and corner posts, dark glass top with the miniature field, a floating holo layer, 4 candles at the corners | (0, −2), (3.0, 2.0) | no | 1.6 | 0.95 | (0, 0.85) | (0, 2.3, −3.7) / 0 | push battle setup |
| `army` | Armoury: three pointed-arch alcoves in the left wall; 15 ivory eggs on bronze plinths in 3 tiers of 5 with plain-colour pennants (no marks), a gun rack of 10 plain rifle silhouettes above | (−11.4, −1), (0.5, 2.6) | no | 1.6 | 2.6 | (−10.0, −1) | (−10.75, 3.15, −1.0) / π/2 | push the army picker |
| `settings` | Command console: octagonal brass pedestal, angled green screen with line stripes, rows of amber / red buttons, one big candle on its side | (10.0, −1), (0.4, 0.4) | no | 1.6 | 1.2 | (9.0, −1) | (10.0, 2.45, −1.0) / −π/2 | push settings |
| `online` | **Moved** to the right wall: docking airlock, a round segmented hatch (r 1.3) in a pointed-arch frame, hazard chevrons, cool blue glow, amber status lamp | (11.8, 3.0), (0.3, 1.7); as built (11.95, 3.0), (0.15, 1.7) (§12) | no | 1.8 | 5.2 | (10.6, 3.0) | (11.45, 5.55, 3.0) / −π/2 | coming-soon panel |
| `adventure` | Round steel chart table (r 1.3) with a parchment star map and a three-ring brass armillary, 4 stools | (−5, 4), (1.3, 1.3) | yes | 1.5 | 0.8 | (−2.95, 4.0) | (−5.0, 2.2, 4.0) / π/2 | coming-soon panel |
| `exit` | Pointed-arch blast door, two steel leaves with bronze trim, hazard chevrons on the sill, amber lamp above | (0, 7.9), (1.2, 0.2) | no | 1.4 | 3.2 | (0, 6.95) | (0, 3.75, 7.62) / π | pop to the main menu |
| `vault` | **New**: treasure chest on an octagonal two-step dais (r 1.2): bronze chest 1.3 × 0.75 m, iron bands, gold light leaking from the lid seam, a lock plate with our candle emblem, two candles at the dais front | (5.0, 4.0), (1.2, 1.2) | yes | 1.5 | 1.4 | (3.15, 4.0) | (5.0, 2.3, 4.0) / −π/2 | coming-soon panel |

- `HallLayout.IDS` = `["battle", "army", "settings", "online", "adventure", "exit", "vault"]` (vault appended).
- 0.4: station `arena` (the arena door, front wall left) — see `ARENA_SPEC.md` §2.
- The online gate and the vault are chosen so that no two footprints overlap, every front ring is free for the avatar
  and inside its own trigger only, and the flood fill from the spawn reaches every trigger (checked in §9).
- Checked distances: spawn → vault edge 3.8 m (> 1.5), spawn → battle trigger 3.4 m, vault front → battle 4.0 m,
  online front → settings 3.6 m, settings ↔ online footprints 2.36 m apart as built (dx 1.4, dz 1.9).

### 2.3 Blockers (all from `HallLayout`, unchanged layers)

- Walls and the ceiling: `Blockers` body, `SHELL_LAYER` 1 (unchanged).
- Props on `PROP_LAYER` 4 (the arm ignores them; `camera_clear` keeps the camera point out of them):
  - **Columns**: radius 0.45, height 6, at (±8.5, −5), (±8.5, 0.5), (±8.5, 5.5) (unchanged).
  - **Candle stands**: radius 0.28, height 1.72, at (−11.3, −6), (11.3, −6), (−11.3, 3), **(11.3, 6.0)**, (−4, −7.5),
    (4, −7.5). Only the right front one moves (from (11.3, 3), which is now inside the airlock); (11.3, 6.0) stays clear
    of the corner test's start (10.8, 6.9) by 1.03 m.
  - **Stations**: one box or cylinder each, from §2.2 (the vault is a cylinder r 1.2, height 1.4).
  - **Stools**: 4 around the adventure table (unchanged).
- **Protrusion rule** (new, for decoration that is not a blocker): it may stand out at most **0.2 m** from a wall, and
  anything standing out more than 0.08 m must sit above **1.9 m** (over the egg's head) or below 0.15 m. The window sill
  stands out 0.06 m (`HallLayout.SILL_DEPTH`, unit-checked ≤ 0.08). Bigger decoration must become a blocker in
  `HallLayout` (and pass the tests).

### 2.4 The great viewport (back wall)

Three pointed-arch lancets cut into the drawn back wall (constant `HallLayout.WINDOWS`, used by the builder and tests):

| Lancet | x range | Sill y | Spring y (arch starts) | Apex y |
| --- | --- | --- | --- | --- |
| centre | [−3.2, 3.2] | 0.9 | 6.2 (as built 5.6, §12) | 9.4 |
| left | [−7.4, −4.6] | 0.9 | 4.6 (as built 4.2, §12) | 6.0 |
| right | [4.6, 7.4] | 0.9 | 4.6 (as built 4.2, §12) | 6.0 |

- The candle stands at (±4, −7.5) stand on the piers between the lancets.
- Each opening has drawn **reveals** (jambs) over the wall's full 0.5 m depth, so you never see into the wall.
- **Tracery** (dark bronze, in the Shell mesh): centre lancet mullions at x = −1.6, 0, 1.6 (0.1 m), transoms at y 2.6 and
  4.4; an oculus ring (r 0.9) at (0, 7.6) with our candle emblem in bronze silhouette inside it. Side lancets: one centre
  mullion and a transom at 2.6. No glass is drawn (no transparency on any level).
- Interior sill ledge at y 0.9, 0.06 m deep (`SILL_DEPTH`); below it a flush brass instrument rail.
- **From the spawn view** (yaw 0, pitch −0.45; the front wall shortens the arm to about 2.9 m, camera ≈ (0, 2.6, 7.6)) the
  top of the frame reaches only about y 3.7 at the back wall. So the planet is placed low (§4.2): its lit limb must cross
  the lower half of the centre lancet in that first view (unit check in §9.2, PNG review in §9.4).

### 2.5 Ceiling (visual only)

- **Nave vault**: a pointed barrel vault along z. Profile (x, y), mirrored: (8.5, 6.0), (7.6, 7.6), (6.0, 8.9),
  (3.8, 9.9), (1.6, 10.5), (0.0, 10.8) (`HallLayout.VAULT_PROFILE`). Webbing panels dark steel with faint panel lines.
- **Ribs** (0.3 m wide, 0.25 m deep below the webbing, bronze-dark steel): transverse arches at z = −5, 0.5, 5.5 (the column
  lines) and wall ribs at z = ±7.9; diagonal ribs crossing each bay (bays z ∈ [−8, −5], [−5, 0.5], [0.5, 5.5], [5.5, 8]);
  a ridge rib along z at the apex.
- **Aisles**: flat ceilings at y 6.3 with a transverse rib at each column line.
- **Gables**: the back wall rises to the vault profile above y 6 (the centre lancet's top sits inside it); the front gable
  holds a blind rose (dark disc r 1.6 at (0, 8.2, 7.95), radial bronze tracery, our candle emblem in the middle).
- **Cables**: bundles sagging between ribs in the nave, y 6.3 to 7.2 (sag 0.5), radius 0.04, 6 segments each, 4 per bay
  side.

### 2.6 Wall dressing, banners and the title plaque

- **Columns**: clustered — an octagonal base plinth (r 0.52, 0.25 high), a core shaft (r 0.33) with four slim shafts
  (r 0.1) at 0.33 out on ±x / ±z (inside the 0.45 blocker), a bronze capital band at y 5.4–5.6 from which the ribs spring.
- **Side walls**: steel panels 2 × 1.5 m with darker seams, a dark bronze wainscot to 1.0 m (flush, as today), and per bay
  a tall pointed-arch blind panel (darker inset, 2.2 m wide, y 1.1 to 5.2). One blind panel per bay carries a wall screen
  (0.9 × 0.8 m at y 1.9–2.7, standing out 0.08 m, green or amber with 3–5 seeded line stripes; no real text).
- **Pipes**: two horizontal runs on each side wall at y 2.3 and 2.55 (r 0.06, axis 0.1 m off the wall), vertical drops at
  the bay boundaries, a few brass valve wheels (thin rings).
- **Banners** (cloth, our candle emblem, deep red / near-black / bronze): (−12, 4.3, −2.25) and (12, 4.3, −2.25) facing in;
  (−12, 4.3, 3) facing +x; **(12, 4.3, 6.0)** facing −x (moved from z 3, now the airlock); **(−4, 4.3, 8) and (4, 4.3, 8)**
  on the front wall facing −z (moved from the back wall, now the viewport). Swallowtail hem allowed.
- **Floor**: steel deck plates 1.5 × 1.0 m with dark seams and seeded shade (`RandomNumberGenerator`, fixed seed), grating
  pattern in the aisles (|x| > 8.95), bolt dots at plate corners on hi / mid only; the deep red runner with bronze edges from
  the door to the war table (z 0.35 to 7.6, as today); hazard chevrons on the exit and airlock sills.
- **Title plaque**: a bronze plate 4.0 × 0.7 m at (0, 6.45, −7.97) under the centre lancet's arch, with a Label3D
  `Sign_title` at (0, 6.45, −7.9), face 0, text from the hall screen (`PLACE`). It is seen when the camera tilts up or the
  avatar walks closer; it is flavour, not a station.

## 3. Geometry kit (`HallBuilder`, `HallSpace`)

### 3.1 Meshes and draw calls

| Node (under `HallWorld`) | What | Built by | Material |
| --- | --- | --- | --- |
| `Static/Shell` | floor, walls with the lancet holes and reveals, tracery, columns, ribs and vaults, gables, plaque plate, exit door, airlock frame and hatch, pipes, cables, wall screens | `HallBuilder._shell` | the one unshaded vertex-colour material (unchanged) |
| `Static/Furniture` | holo table body, armoury, console, chart table, vault dais and chest, candle stands, candle bodies | `HallBuilder._furniture` | same |
| `Static/Cloth` | banners | `HallBuilder._cloth` | same |
| `Static/Space` (**new**) | the space dome, stars, planet, moon (§4) | `HallSpace.mesh(level)` | same |
| `Flames` | candle flames, one MultiMesh (unchanged mechanics) | `HallWorld._build_flames` | `flame.gdshader` hi/mid, plain lo/min |
| `Holo` (**new**, MeshInstance3D) | the holo layer over the war table (§3.3) | `HallBuilder.holo_mesh(level)` | `holo.gdshader` hi/mid, plain lo/min |
| `Ships` (**new**, MultiMeshInstance3D) | distant ships (§4.3) | `HallSpace.ship_mesh()` + `ship_instances(level)` | `ship_drift.gdshader` hi/mid, plain lo, hidden on min |
| `Rings`, `Avatar/Egg`, `Signs/*`, `Avatar/NameLabel` | unchanged (8 station signs incl. the vault + `Sign_title`) | | |

- At most **4 static meshes** (`counts().static_meshes` ≤ 4). Static meshes stay cached per `sides` (`HallBuilder`) and the
  space mesh per level (`HallSpace`), built once per app run.
- Built only with `PropsLayer.Geo` (`poly`, `box`, `prism`, `xprism`, `band`, `disc`) plus `HallBuilder.lathe` / `append`
  / `bake`. Seeded `RandomNumberGenerator` only (fixed seeds), so the look is identical on every run and machine.
- Expected primitives (estimate, for orientation): Shell ≈ 9–11k triangles, Furniture ≈ 3–4k, Space ≤ 2.6k (hi), Holo ≤ 1k,
  Ships ≤ 0.4k. Today's hall measures 16 draw calls and 9.2k (min) – 10.2k (hi) primitives.

### 3.2 Palette (sRGB, before the bake)

| Name | Colour | Use |
| --- | --- | --- |
| `STEEL` | #4a4f55 | wall panels, columns |
| `STEEL_DARK` | #2b2f35 | vault webbing, insets, seams |
| `DECK` / `DECK_SEAM` / `GRATE` | #3f4348 / #1c1e22 / #2a2d31 | floor |
| `BRONZE` / `BRASS` | #8a6a3a / #b08d4a | rims, capitals, tracery, consoles |
| `GOLD` | (existing) | runner edge, emblem, chest trim |
| `CARPET` | (existing deep red) | runner |
| `SCREEN_GREEN` / `SCREEN_AMBER` | #7dffa6 / #ffbb55 | screens (not baked) |
| `HOLO` / `HOLO_AMBER` | #59f0b4 / #ffc35a | holo layer |
| `HAZARD` / `HAZARD_DARK` | #d9a521 / #18181a | chevrons |
| `BANNER_COLS` | #7f1717, #1f1c22, #8c6630 | banners (with the gold candle emblem) |
| `SPACE` / `NEBULA_A` / `NEBULA_B` | #03040a / #2c1745 / #0c3340 | dome |
| `STAR_COLS` | #f2f4ff, #b8ccff, #ffd9a0 | stars |
| `PLANET_*` | ocean #1d4b5c, land #9a6a3a, cloud #d8d2c4, night #070a10, air #8fc4ff | planet |
| `HULL` / `HULL_LIT` / `ENGINE` | #1a1c22 / #ffbf66 / #7fb8ff | ships |

### 3.3 The holo layer (war table)

- Floats over the table top (0.95 m): a grid of 12 × 8 cells over 5.4 × 3.4 m (as built 5.0 × 3.0 m, §12) at y 1.18, line width 0.035 m (hi/mid) or
  0.06 m (lo/min); a frame rectangle; 6 small holo eggs (lathe 8 sides × 4 bands, 0.35 m tall) in team blue / red, in two
  groups; 2 objective markers (hexagon outlines, amber). The table's dark glass top below keeps the green / ochre patches of
  today's miniature field, darker.
- hi / mid: `holo.gdshader` — `render_mode unshaded, blend_add, cull_disabled, depth_draw_never, fog_disabled;`
  `ALBEDO = COLOR.rgb * flicker * (1.0 + 0.6 * band)` where `flicker = 0.8 + 0.2 * sin(TIME * 3.1 + …)` and `band` is a soft
  bright stripe moving up through y (`fract(TIME * 0.4)`). One transparent draw.
- lo / min: a plain unshaded opaque `StandardMaterial3D` with vertex colours at 0.8 brightness, no `TIME`.
- No blocker (it is above the table's blocker box, inside the war table's footprint).

## 4. The space viewport (`HallSpace`, `scenes/hall/hall_space.gd`, `class_name HallSpace extends RefCounted`)

Pure mesh building, no Node, no Thai, floats allowed. Everything sits outside the room behind the back wall (z < −8.5), so
it is seen only through the lancets and never touches the camera or physics.

### 4.1 Dome and stars

- **Dome**: the inner side of a half sphere, centre `DOME_C = (0, 4, −8.5)`, radius `DOME_R = 42`, covering every direction
  with z < 0 (cut by the plane z = −8.5). Lathe segments per level (§6). Vertex colours: `SPACE`, with two or three soft
  nebula blobs (`NEBULA_A`, `NEBULA_B`, seeded directions, smooth falloff) and a faint brighter band.
- Farthest dome point from any camera position in the room ≈ 62 m, inside the camera's `far` (90). Keep `far` at 90.
- **Stars**: small diamonds (2 triangles) at radius 41 facing `DOME_C`, seeded directions (seed 4401), twice as dense in
  the nebula band, none inside the planet's or moon's disc. Count and size per level (§6); sizes stay ≥ 2 px at the level's
  render scale so they do not shimmer (no MSAA).
- No `TIME` on any level (no twinkle); the whole dome + stars + planet + moon is one static mesh.

### 4.2 Planet and moon

- **Planet**: a lathe sphere, centre `PLANET_C = (−10, −5, −32)`, radius 11 (16 × 10 segments hi/mid, 10 × 6 lo/min),
  inside the dome (distance from `DOME_C` + radius < 42). Banded ocean / land / cloud colours, lighting baked from a sun
  direction (normalised (1, 0.6, 0.3)): lit side warm, a soft day-night edge, the night side `PLANET_night`, a thin bright `air`
  rim band on the lit limb. No rings.
- **Moon**: radius 2 at (14, 9, −34), grey with baked light from the same sun.
- The planet's lit limb crosses the lower half of the centre lancet in the spawn view (§2.4).

### 4.3 Distant ships

- Our own silhouettes: a long dark wedge hull with a pointed prow, a stepped tower at the rear with tiny amber window dots
  (`HULL_LIT`), a blue engine glow plate at the stern (`ENGINE`); about 40 triangles each, no emblems, no text.
- `HallSpace.ship_instances(level)` returns fixed instances (position, heading ±x, length, speed, phase):
  A (−20, 7, −34) +x, 7 m, 0.35 m/s; B (14, 2, −28) −x, 4 m, 0.2 m/s; C (0, 12, −38) +x, 9 m, 0.12 m/s; D and E small
  escorts near A (hi only). As built, A and B moved and D / E got fixed places (§12).
- hi / mid: `ship_drift.gdshader` (unshaded) moves each instance along its heading by
  `mod(TIME * speed + phase, span) − span / 2` (speed, phase, span from `INSTANCE_CUSTOM`). Per ship
  `span = 2 × (the dome's half chord along x at the ship's y and z − its length)` (A ≈ 58 m), so a ship never leaves the
  dome; the shader scales it to zero over the first and last 8 % of the span, so it fades in and out instead of jumping.
- lo: the same MultiMesh with a plain unshaded material, ships parked at their phase positions (no `TIME`).
- min: no ships (`instance_count = 0`, node hidden, no draw call).

## 5. The vault station (future random rewards)

- Station id `vault`, form and position in §2.2. E or the use button calls `show_soon("vault")`: the existing
  `%SoonPanel` shows `SOON.vault` in one line (Thai) / at most two lines (English), closes after 2.5 s, on a move, or on
  Back; the player stays in the lobby. `use_station()` gets `"online", "adventure", "vault": show_soon(station())`.
- `%SoonPanel` grows from 560 × 100 to **760 × 120** logical px (offsets ±380 / ±60) so the vault line fits at 1280 and
  1600 logical widths; the label keeps autowrap. The layout check runs with the vault panel open (§9.3).
- **No reward code, data, RNG stream, save key or server call** in this round. Notes for the later round (owner's plan:
  random gun parts and decorations; a proposal, not yet agreed with the owner): rewards are cosmetic only and never touch the rules, points or `core/`, so every device
  in a room still computes the same battle; earned by playing (no paid random boxes); the chest opening is a separate
  screen pushed from this station.

## 6. Per graphics level (`HallWorld.apply_level(l)`)

It still applies the three globals from `TableView.LEVELS[l]` (render scale, `Engine.max_fps`, low-processor mode), plus:

| Level | Flames | Flicker | Halos | Holo | Ships | Stars (size m) | Dome segs | Planet segs | Sides | Bob | Asserted budget (LOBBY §2.6) | Ship target (new, asserted) |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| hi | 26 | yes | optional | shader | 5 drifting | 700 (0.10–0.22) | 24 × 12 | 16 × 10 | 14 | yes | ≤ 140 / 250k | ≤ 40 / 60k |
| mid | 26 | yes | no | shader | 3 drifting | 500 (0.10–0.22) | 20 × 10 | 16 × 10 | 12 | yes | ≤ 100 / 150k | ≤ 40 / 50k |
| lo | 26 | no | no | plain | 3 parked | 320 (0.14–0.28) | 16 × 8 | 10 × 6 | 10 | no | ≤ 60 / 80k | ≤ 35 / 40k |
| min | 12 | no | no | plain, thicker lines | none | 180 (0.18–0.34) | 12 × 6 | 10 × 6 | 8 | no | **≤ 40 / 40k** | **≤ 30 / 30k** |

(budgets are draw calls / primitives, measured as `test_hall` does today, and again in the phone layout's worst view:
20:9 window, touch on, first-entry hint showing, at the war table looking towards a back corner. Sign outlines are off
on lo/min, one draw call less per sign.)

- **Flames**: 26 on hi/mid/lo = 6 stands × 3 + 4 table + console + chart table + 2 vault candles; `MAX_FLAMES` 24 → 26.
  min keeps the same 12 as today (6 stand centres + 4 table + console + chart table), still the first 12 of the full list.
  The console flame keeps the old lectern flame position `(10.22, 1.62, −0.72)` (rename `LECTERN_FLAME` → `CONSOLE_FLAME`).
- **min (potato)**: no `TIME` shader anywhere under `HallWorld`, no ships node drawn, the holo opaque, nothing processing
  while idle (avatar, camera, spring arm, screen, stick — unchanged rule), no dynamic lights, no shadows, no transparency
  except the avatar fade that already exists. Expected about 20 draw calls.
- **lo**: as min but 26 flames, 3 parked ships, more stars.
- Animated touches allowed: candle flicker, the holo flicker / scan band and drifting ships on hi and mid only; the
  first-entry hint fade (existing, hi/mid). Nothing else moves.

## 7. Light and colour (the bake)

- `HallBuilder.bake` gains a cool light list. For every baked vertex:
  `warm = Σ_flames 0.85 / (1 + d²/3)` (unchanged) and `cool = Σ_i k_i / (1 + d²/D_i)` over `HallLayout.COOL_LIGHTS`;
  colour = base × (`GLOW_BASE` + warm × warm tint + cool × the light's colour), clamped (`GLOW_MAX` unchanged). With
  `cool = 0` it must equal today's `lit()` exactly (unit check).
- `COOL_LIGHTS` (pos, k, D, colour): holo (0, 1.4, −2), 1.1, 4, `HOLO`; viewport, 5 points at (x ∈ {−6, −3, 0, 3, 6}, 3.0,
  −7.4), 0.35, 6, #9fb8ff; each wall screen centre, 0.3, 1.5, its screen colour; airlock (11.4, 2.5, 3.0), 0.5, 3, #7fb8ff
  (replaces the old gate glow); vault seam (5, 1.3, 4), 0.6, 2, `GOLD`.
- Not baked (drawn at full colour like today's gate glow, via `append`): screen faces, the chest's lid seam, the airlock's
  status lamp, the exit lamp, and the whole Space mesh.
- `GLOW_BASE` may drop from 0.32 to 0.28 so the deck reads darker than the stone hall; tune by the PNGs (§9.4).
- Environment on the hall camera (unchanged mechanism): background colour #06070d (deep space navy) instead of #120c08,
  ambient black, linear tonemap, no `WorldEnvironment`, no sky resource.

## 8. Files to change (surgical edits; comments short and in Thai)

### 8.1 World (`scenes/hall/`)

- `hall_layout.gd`: `IDS` + `vault`; `STATIONS.online` and `STATIONS.vault` per §2.2; `STANDS[3]` = (11.3, 6.0); `BANNERS`
  per §2.6; `MAX_FLAMES` 26; `flames()` adds the two vault candles after the stand side flames (min list unchanged);
  new constants `WINDOWS`, `VAULT_PROFILE`, `COOL_LIGHTS`, `CONSOLE_FLAME`, `VAULT_FLAMES` = (4.05, 0.78, 3.45) and
  (4.05, 0.78, 4.55) (on the dais' top step, front side, inside the r 1.2 blocker), `TITLE_SIGN`. Header comment
  updated (deck, not hall of stone). Still pure data, no Thai.
- `hall_builder.gd`: new look per §2–§3 and §7 (`_shell`, `_furniture`, `_cloth` rewritten in place, `holo_mesh(level)`,
  `bake` with cool lights); `meshes(sides)` still returns the 3 hall meshes; `avatar_mesh`, `flame_mesh`,
  `build_colliders`, `lathe`, `material` unchanged.
- `hall_space.gd` (new, `HallSpace`): `mesh(level) -> ArrayMesh` (cached), `ship_mesh() -> ArrayMesh`,
  `ship_instances(level) -> Array[Dictionary]`, `STARS`, `DOME_SEGS`, `PLANET_SEGS`, `SHIPS` per level, `DOME_C`, `DOME_R`,
  `PLANET_C`, `PLANET_R`, `MOON_C`, `MOON_R`, `SUN`.
- `holo.gdshader`, `ship_drift.gdshader` (new): hi/mid only; header comment says so, as `flame.gdshader` does.
- `hall_world.gd`: four static meshes (`["Shell", "Furniture", "Cloth", "Space"]`); `LEVELS` gains `holo`, `ships`,
  `stars` keys and flames 26 / 12; builds `Holo` and `Ships` per level; the `title` sign (`Sign_title`) in `_signs`;
  background colour; `counts()` adds `stars`, `ships`, `ship_drift` (bool), `holo_flicker` (bool), `space_tris`.
- `hall_world.tscn`: add `Holo` (MeshInstance3D, `cast_shadow = 0`) and `Ships` (MultiMeshInstance3D, `cast_shadow = 0`).
  Camera, arm, avatar, bodies unchanged.
- After adding `HallSpace` and the two shaders, refresh the cache under the lock:
  `flock <scratchpad>/godot-ship/import.lock timeout 600 ~/godot-bin/godot --headless --path godot --import`.

### 8.2 Screen and text

- `ui/screens/hall_screen.gd`: `NAMES`, `SIGNS`, `SOON` per §1, `const PLACE := "ดาดฟ้ายานรบ"`, `refresh()` also sets
  `world.set_sign_text("title", I18n.t(PLACE))`, `use_station()` routes `vault` to `show_soon`. Header comment: the deck
  and its stations. Nothing else changes (controls, prompts, hint, timers, back handling).
- `ui/screens/hall_screen.tscn`: `%SoonPanel` offsets ±380 / ±60 (§5). No other node changes.
- The hall screen contract of LOBBY_SPEC §6.3 gains the station id `vault`; every other contract name is unchanged.
- `ui/i18n/hall.json`: add the six new pairs of §1, remove the two unused keys.

### 8.3 Version

- `core/version.gd`: the one line `const APP_VER := "ใหม่ 0.3"` (no rules change: `RULES_V`, `DATA_HASH`, `PROTO` untouched).
  The main menu then shows "แอปใหม่ รุ่น 0.3" / "New app version 0.3".

### 8.4 Docs

- `docs/GODOT.md` §1.3: title "(… APP_VER ใหม่ 0.3; the deck: `godot/docs/SHIP_LOBBY_SPEC.md`)"; rows `hall_layout.gd` (7
  stations incl. `vault`, windows, vault profile), `hall_builder.gd` (deck look, cool-light bake, holo mesh), new row
  `hall_space.gd` (dome, stars, planet, ships), `hall_world` (4 static meshes, `Holo`, `Ships`, title sign), `hall_screen`
  (vault coming soon); the `army.tscn` row says "pushed by the deck's armoury station".
- `godot/README.md` row of `scenes/hall/`: ดาดฟ้ายานรบ and its seven stations, spec link.
- `godot/docs/STATUS.md`: a "12 Nov: warship deck lobby (ใหม่ 0.3)" entry with the test numbers.
- `godot/docs/LOBBY_SPEC.md`: one line under "## 2. Lobby hall": "0.3: §2.1, §2.2 and §2.6 are replaced by
  `SHIP_LOBBY_SPEC.md` (the warship deck); §2.3–§2.5 still hold." Nothing else in that file.

### 8.5 Suggested split if two builders work in parallel

- **world**: everything in §8.1, `tests/unit/test_hall_layout.gd`, `tests/unit/test_hall_space.gd`.
- **screen + release**: §8.2–§8.4, §10, `tests/unit/test_hall_text.gd`, `tests/unit/test_menu_text.gd`,
  `tests/render/test_hall.gd`.
- Contract between them: `HallLayout.IDS` (with `vault`), the `title` sign id, the `counts()` keys of §8.1, the node names
  `Holo`, `Ships`, `Static/Space`. The full suite runs once at the end.

## 9. Tests

Run as in `LOBBY_SPEC` §7.5, with `TEST_OUT=<scratchpad>/godot-ship/out-<track>`, `nice -n 10` for render and full runs,
imports under `<scratchpad>/godot-ship/import.lock`, and never kill processes by name (only PIDs you started). Never delete,
skip or loosen a check; every changed expectation below says why, in a comment in the test too.

### 9.1 Changed expectations (behaviour changed on purpose)

| Test | Today | Becomes | Why |
| --- | --- | --- | --- |
| `test_hall_layout.test_stations_are_the_six_of_the_spec` | six ids | renamed `…_the_seven_of_the_spec`, seven ids with `vault`; `reach_of("online")` still 1.8 | the new vault station |
| `test_hall_layout.test_station_at_samples` | (0, −6.5) → online, (6, 4) → "" | (10.6, 3.0) → online, (0, −6.5) → "", (6, 4) → vault, (3.15, 4.0) → vault | online moved to the right wall, vault at (5, 4) |
| `test_hall_layout.test_blockers_and_flames` | tags without vault, 24 flames | + `vault` tag, 26 flames on hi/mid/lo, min still 12 and the first 12 | the vault and its two candles |
| `test_hall_text.test_every_station_has_thai_and_english` | soon panels of online, adventure | + vault; `SIGNS` / `NAMES` loop covers vault through `IDS` | new station |
| `test_menu_text` (version) | "0.2" | "0.3" | APP_VER bump |
| `test_hall` run header | 24 flames, 7 signs, ≤ 3 static meshes | 26 flames, 9 signs (7 stations + title + name tag), ≤ 4 static meshes | vault, title plaque, space mesh |
| `test_hall._check_texts` | "the six signs and the name tag are Thai (7)" | 9 Thai labels; the vault soon panel also checked for fit and English | as above |
| `test_hall._check_stations` | online, adventure show the panel | online, adventure, **vault** show the panel and stay | new station |
| `test_hall._check_levels` | flames 12 / 24 | 12 / 26 | vault candles |
| `test_hall._check_walls` / `_check_camera_walks` | names "the back wall", "spawn -> the lectern" | messages "the back wall (viewport)", "spawn -> the console"; positions unchanged | wording only |

Unchanged and must stay green: `test_lobby_flow` (spawn → W → war table → setup → game → back → Esc), `test_settings_flow`
(the war table's sign is still "Battle Table" / "โต๊ะรบ"), `test_budgets`, `test_menu_screens`, `test_main_screens`,
`test_army_screen`, `test_battle_screen`, every other unit suite, the data lint, the render probe.

### 9.2 New unit checks (headless, also run in the exported game)

- `test_hall_layout.gd`:
  - every station's front ring is inside its own trigger only (no other station's trigger reaches it);
  - the flood fill reaches the vault and the moved online gate (the loop over `IDS` covers it; assert the count is 7);
  - the space in front of the viewport is free: no blocker except the stands at (±4, −7.5) intersects
    x ∈ [−7.4, 7.4], z ∈ [−8, −6.9];
  - `WINDOWS` lancets lie inside the back wall (|x| < 12, sill ≥ 0.6, apex under `VAULT_PROFILE` at that x) and do not
    overlap; `VAULT_PROFILE` starts at (8.5, 6.0) and rises monotonically to the ridge;
  - every station sign sits above its blocker and inside the room; the title sign is under the centre lancet's apex;
  - `COOL_LIGHTS` are inside the room (or on the back wall plane) and every `k > 0`.
- `test_hall_space.gd` (new):
  - per level: star count, dome and planet segments as in §6; `mesh(level)` is cached (same object twice);
  - every Space vertex has z < −8.5 and lies within `DOME_R` + 0.01 of `DOME_C`; no NaN position or colour;
  - the planet and moon are inside the dome; no star inside the planet's disc;
  - the farthest dome vertex from the room box's corners is < 85 m (camera `far` 90);
  - `ship_instances`: 5 / 3 / 3 / 0 for hi / mid / lo / min; at both ends of its drift span every vertex of every ship is
    inside the dome;
  - **spawn view**: with the camera point of the spawn view (avatar (0, 0, 5) + head (0, 1.3, 0), pitch −0.45, arm length
    from `HallLayout.room_clear`, ≈ (0, 2.53, 7.55)), the segment to the lit limb point
    `PLANET_C + PLANET_R × (√½, √½, 0)` (≈ (−2.2, 2.8, −32)) crosses z = −8 inside the centre lancet (|x| < 3.2,
    0.9 < y < 6.2; ≈ (−0.9, 2.6)) and lies inside the 60° vertical field of view (elevation ≈ +0.4°, top of view ≈ +4.2°).
- `test_hall_text.gd`: the `title` text `PLACE` has Thai and an English pair without Thai; the vault soon text is a whole key
  and its English contains no `{`; the fragment has no unused key (existing test, now with the new keys).
- `HallBuilder` bake: with an empty cool list, `bake` gives byte-identical colours to today's `lit()` (a unit check in
  `test_hall_layout.gd` or a new small `test_hall_bake` section of `test_hall_space.gd`).

### 9.3 New render checks (`tests/render/test_hall.gd`)

- **Vault**: at `_front("vault")` the prompt names "หีบสมบัติ" / "Treasure Chest"; E shows `%SoonPanel` with the vault
  line and stays in the hall; Esc closes it first; walking away closes it. At the three sizes in Thai and English the open
  vault panel passes `_layout_problems` and, in English, has no Thai.
- **Online moved**: E at the new airlock front still shows the online panel (covered by the station loop; assert the
  avatar is at x > 10).
- **Per level** (in `_check_levels`): `counts().ships` and `ship_drift`, `holo_flicker`, `stars` match §6; on lo and min no
  `GeometryInstance3D` under `HallWorld` has a `ShaderMaterial` override (no `TIME` work), on min `Ships` is hidden; the
  `Static/Space` mesh is visible on every level; the existing budgets (LOBBY §2.6) **and** the ship targets of §6 hold; the
  numbers for all four levels are printed as today.
- **No holes into the void**: with the hall camera's background set to pure magenta (test only, restored after), render
  12 views (4 spots × yaw 0 / 90 / 180 / 270°, pitch −0.15 and −0.45, arm 6.5 and 9) at 640x360 and count magenta pixels:
  0 allowed. This proves the vault closes the top, the reveals close the window sides and the dome fills every window.
- **Camera inside solids**: unchanged checks (corners, walks past columns, the `camera_clear` property test) now include
  the vault and the airlock automatically; add two walks to `_check_camera_walks`: "spawn → the vault" (stick (0.9, 0.2)
  from (0, 0, 5)) and "past the vault to the airlock" (stick (1, 0) from
  (2.5, 0, 2.2)), each: arm change ≤ 0.5 m a frame and the camera never inside a blocker.
- **min idle**: unchanged (nothing processes after 10 idle frames, the spring arm sleeps).
- PNGs (for the review, not compared): `hall_th.png`, `hall_en.png`, `hall_min.png`, `hall_touch.png` (as today) plus
  `hall_viewport.png` (spawn, pitch −0.15), `hall_vault.png` (at the vault, panel open), `hall_deck_<level>.png` (from
  (0, 0, 3.5), pitch −0.6, arm 9, as `_check_levels` measures).

### 9.4 Review before hand-off

- Look at every PNG at full size: the deck reads as a gothic starship (vaults, columns, viewport with planet and stars),
  the stations are recognisable, Thai and English signs are readable, nothing floats or clips through the egg, and the
  only emblem anywhere is our candle (no third-party mark, no text but our signs).
- `python3 godot/tools/validate_data.py` (rule-1 names over every file under `godot/`, i18n schema).
- `bash godot/tests/run.sh` while working, `nice -n 10 bash godot/tests/run.sh full` once at the end; record the numbers
  in `STATUS.md` and the Thai note.

## 10. Release

- `APP_VER` "ใหม่ 0.2" → **"ใหม่ 0.3"** (§8.3). User-visible change; no rules change, so no rules version or server gate.
- Godot-only change inside this repo: no `battle-table.html` / `board.html` edit, so **no candlelight-server re-embed PR**
  and no merge order beyond PR #27 itself.
- Thai note: `web/สิ่งที่เปลี่ยน-12พ.ย.69-รุ่นใหม่0.3-ล็อบบี้บนยานรบ.md` (use the date the round is finished; if it slips
  past midnight, `13พ.ย.69`). Same structure as the 0.2 note:
  1. `# สิ่งที่เปลี่ยน 12 พ.ย. 69 — แอปใหม่ รุ่นใหม่ 0.3 ล็อบบี้บนยานรบ` and one paragraph quoting the owner's request in
     plain words;
  2. `## มินิทำอะไรได้แล้วในรุ่นนี้`: the deck (ดาดฟ้ายานรบ) and what you see out of the window; every station with its job
     (โต๊ะรบ → ตั้งเกม, คลังแสงกองทัพ → จัดกองทัพ, ตั้งค่า, ประตูเทียบยาน = ออนไลน์ เร็วๆ นี้, โต๊ะผจญภัย เร็วๆ นี้,
     หีบสมบัติ = ระบบสุ่มของรางวัล เร็วๆ นี้, ทางออก); that walking, the camera and the buttons are the same; that the design
     is our own with no names or marks of other game companies;
  3. `## วิธีลอง`: open the app → เล่นกับบอท → walk to the window and each station; try the graphics levels in Settings
     (ต่ำสุด has no moving ships or flicker, so weak phones stay fast);
  4. `## ยังไม่มีในรุ่นนี้`: the reward system itself (only the chest stands there), online, the adventure table;
  5. `## ทดสอบแล้ว`: unit / flow / render numbers from the full run, the draw calls per level, "ไม่มีช่องโหว่มองทะลุ";
  6. `## ลำดับการรวม`: godot-only change in PR 27, no server PR needed.

## 11. Out of scope now

- Any reward logic, inventory, chest-opening screen or data (later round, §5 notes).
- New figures or models (the next request from the owner is a separate task), sound and music.
- Online rooms, the adventure table, new HUD controls, camera changes, a new spawn or a bigger room.
- Real lights, shadows, post-processing, textures or imported assets.

## 12. As built (12 Nov 2026)

The deck was built in two parts (world; screen + release). Where the build differs from the text above, the build and
its tests are the record:

| Spec | As built | Why |
| --- | --- | --- |
| Lancet spring heights 6.2 (centre) / 4.6 (sides), §2.4 | 5.6 / 4.2; widths, sills and apexes (9.4, 6.0) unchanged | with the spec's numbers the rise equals half the width, which draws round arches, not pointed ones |
| Airlock footprint (11.8, 3.0), half (0.3, 1.7), §2.2 | (11.95, 3.0), half (0.15, 1.7); frame 0.2 m off the wall, hatch set shallow behind it | the 5.2 m blocker standing out 0.5 m pulled the camera in along the right wall (arm jumps of 1.34 m and 1.20 m in two `test_hall` walks); the front ring (10.6, 3.0) is still 1.2 m from the footprint, inside its 1.8 m reach |
| Ships A (−20, 7, −34), B (14, 2, −28), D / E "near A", §4.3 | A at y 8; B (14, 3, −20); D (−17, 9.6, −32.5) and E (−23, 6.6, −35.5) share A's drift span; spans by the §4.3 formula | B passed through the planet and A grazed its top; the escorts keep formation |
| Holo grid 5.4 × 3.4 m, §3.3 | 5.0 × 3.0 m | the corner candles at ±2.72 / ±1.72 stuck through the larger grid |
| `COOL_LIGHTS`, §7 | plus one deck-wide cool fill (k 0.14, D 1e6, #9fb8ff); with cool lights baked the candle light is softened and less orange (`DECK_WARM` 0.8, `DECK_TINT` 0.55); `GLOW_BASE` 0.28 | without it the deck read as warm stone, not steel; `lit()` is unchanged and the empty-list bake stays byte-identical (unit check) |
| — | `HallLayout.SCREENS` (the four wall screens; their cool lights match it); the title label is drawn as large as font size 72 in a warmer colour (font size 88 with pixel size 0.005 × 72 / 88, so it shares the station signs' glyph cache) | small additions; a real size 72 allocated two more 2 MB glyph pages |
| No holes into the void: "12 views", §9.3 | 64 views on mid (4 spots × 4 yaws × 2 pitches × 2 arms) and 32 on min (arm 9), 640×360, zero magenta pixels | the full grid the spec lists, plus min because its dome has fewer segments |
| `test_hall._check_movement` starts (4, 0, 6.5) / (4, 0, 7.0) | (2, 0, 6.5) / (2, 0, 7.0), also the touch walk | walking forward from x 4 now reaches the treasure chest (r 1.2 at (5, 4)) |
| `test_lobby_flow` unchanged, §9.1 | its checks are unchanged; only its hand-copied blocker table (`RECTS`) follows the deck: the airlock on the right wall, the chest added | the table still described the 0.2 gate on the back wall |
| — | new `tests/flow/test_hall_reach.gd` (headless, quick run): from the spawn the stick walks the avatar to each of the 7 stations along a free grid path with the real colliders, never inside a blocker; then the chest's prompt and panel in Thai / English, Esc closes it, a second Esc goes to the main menu | "every station reachable" with physics, not only the flood fill, and headless in the quick run (locally the render suites run only in `run.sh full`; CI runs them on every pull request) |
| The two vault candles | lit on hi / mid / lo; min keeps the same 12 flames as 0.2, so they are unlit there | the min list is unchanged on purpose (§6) |
| Window sill 0.18 m deep, §2.3 / §2.4 | 0.06 m (`HallLayout.SILL_DEPTH`) | review of 12 Nov: an egg standing at the viewport (z −7.65) reaches z −8.06 at sill height, so the 0.18 m ledge cut through its waist |
| Vault seam light k 0.6, §7; chest body / lid `BRONZE` × 0.85 / 0.95 | k 0.25; body and lid × 0.62, end caps × 0.56, lid underside × 0.42 | review of 12 Nov: three lights stacked on the chest clipped its red channel (255) and it read as a bright cartoon chest; now about (170, 115, 50) |
| Tracery "dark bronze", §2.4 | mullions and transoms `STEEL_DARK` × 0.8; the oculus ring and the candle emblem stay bronze | review of 12 Nov: after the bake the bronze bars read as wooden house-window frames |
| Holo table field patches × 0.4–0.5 | × 0.25–0.32 | review of 12 Nov: the "dark glass top" read as a bright board-game mat |
| Moon: 4 segments fewer than the planet, night side (0.02, 0.02, 0.025) | the planet's segments, night side `MOON_NIGHT` (0.10, 0.11, 0.14) | review of 12 Nov: a jagged day/night edge and a black blob against the nebula |
| Sign outlines on every level; touch stick arcs anti-aliased | outlines only on hi/mid (`HallWorld.LEVELS[l].outline`); the stick's three arcs without anti-aliasing | review of 12 Nov: the phone layout's worst view measured 41 (min) and 42 (mid) draw calls; now asserted in `test_hall` within the deck targets |
| `Ships` culled by its instance points | on hi/mid (drift) `custom_aabb` covers the dome half behind the back wall | review of 12 Nov: the shader moves ships up to 36 m from their instance points, so a ship in view could be culled with its node |
| `%SoonPanel` default mouse filter | `mouse_filter` ignore | review of 12 Nov: the wider panel swallowed camera drags on touch; it has nothing to tap |
| Camera walks "around the vault and to the airlock", §9.3 | each walk has its own camera yaw; the airlock walk runs along its front with the camera between the avatar and the right wall and must pass within 0.5 m of the footprint; the vault walk stays as a smoke walk; a unit check guards airlock front − `CAM_PAD` > `HALF.x` − `HallCamera.WALL_PAD` | review of 12 Nov: with yaw 0 the camera stayed at the front wall, 2.9 m from the airlock, so the walks tested nothing there; the chest's padded top (1.55 m) never reaches the camera (≥ 1.75 m) |
| — | `HallBuilder.bake` caches the light per vertex position (about two thirds of the vertices repeat a position) | the deck's meshes now build in about 60–70 ms of CPU per level (120–170 ms before, 30–60 ms for the 0.2 hall); a unit check compares every baked vertex with `lit_cool(glow, cool_at)` bit for bit |
