# Weapons arena off the warship deck (ใหม่ 0.4) — build spec

Written 13 Nov 2026 for the new app (`godot/`, branch `claude/new-session-fsucoo`, draft PR #27), on top of commit
ae0f490 (ใหม่ 0.3, the warship deck). Three builders follow this file in parallel, in the same checkout, each on its own
files (§12). It is the single source of truth for names, paths, numbers and contracts. Builders read it but do not edit
it; a needed change goes back to whoever runs the workflow, and differences found while building go into §17 (as built)
at integration.

Everything in `SHIP_LOBBY_SPEC.md` (the deck) and `LOBBY_SPEC.md` (flow, avatar, camera, HUD, touch, i18n §0.7, test
rules §7.1) still holds unless a section below changes it by name.

**The owner's request (12 Nov, before going to sleep), in short:** another room off the lobby, reached by a corridor: an
arena that is not a campaign but a test range for trying weapons. When his character walks in it switches to holding a
gun and the game becomes a third-person shooter. That needs an attack system: a saw-blade sword would be nice, or just
punching plus shooting for now. The arena must hold one alien creature as the enemy, and the room needs a button (shoot
it, or anything) that works as an on/off switch for that enemy's bot. (He named a franchise creature; this repo is
public, so the creature gets our own neutral name, §1.)

**For the owner, in Thai:** ที่มุมหน้าซ้ายของดาดฟ้ายานรบมีประตูโค้งบานใหม่ "อารีน่าทดสอบอาวุธ" มองเข้าไปเห็นทางเดินสั้น ๆ
เดินเข้าประตู (หรือกด E) จอจะมืดแวบหนึ่งแล้วเราอยู่ในทางเดินยาวราว 10 เมตร เดินสุดทางเดินเข้าห้องอารีน่าเมื่อไร
ไข่ของเราจะชักปืนออกมาทันทีและเกมเปลี่ยนเป็นยิงมุมมองบุคคลที่สาม (กล้องข้ามไหล่ มีเป้าเล็งกลางจอ)
คลิกซ้ายยิง คลิกขวาหรือ F ต่อย R บรรจุกระสุน 1/2 สลับปืนกับดาบเลื่อย บนมือถือมีจอยซ้าย ลากจอขวาเล็ง และปุ่มยิง/หมัด/อาวุธ/บรรจุ
ที่ขวาล่าง ในห้องมี "สัตว์รัง" ตัวหนึ่ง (สัตว์ประหลาดต่างดาวจากโมเดล 312 ตัวเดิม ขยับด้วยท่าที่อบไว้) ยืนเป็นเป้านิ่งอยู่ก่อน
ยิงหรือกด E ที่ "สวิตช์บอท" แล้วมันจะเริ่มไล่ตามและตะปบเรา (ง้างให้เห็นก่อนตีทุกครั้ง หลบทันได้) กระดานบนผนังบอกบอทเปิด/ปิด
พลังชีวิตของมัน โดนกี่ครั้ง ความเสียหายรวม ปุ่ม "รีเซ็ต" คืนทุกอย่าง เดินกลับออกทางเดินก็กลับดาดฟ้า ตัวละครกับศัตรู
ถอดเปลี่ยนได้ ภายหลังใส่โมเดลของมินิเองจากที่เก็บส่วนตัวได้โดยไม่ต้องแก้โค้ด

## 0. Decisions this spec fixes (do not re-decide)

| Topic | Decision |
| --- | --- |
| Where | A new doorway in the deck's **front wall, left of the exit** (x ∈ [−10.8, −8.8]), a deck station `arena` with a sign, and a short corridor stub drawn behind it (§2). The arena itself is a **separate screen** with its own 3D world, entered with a short fade (§3). |
| Seamless or fade | **Fade** (§3 gives the budget reasons). The deck stays exactly as fast as today in every view it already had. |
| Names on screen | **อารีน่าทดสอบอาวุธ / Weapons Arena** (deck station, door signs). Enemy **สัตว์รัง / Hive Beast**. Weapons **ปืนไรเฟิล / Rifle**, **หมัด / Punch**, **ดาบเลื่อย / Saw Sword**. Bot switch **สวิตช์บอท / Bot switch**, **รีเซ็ต / Reset**. |
| Names in code | Folder `scenes/arena/`, screen `ui/screens/arena_screen.*`, pure data and math `ui/arena/`. No file is called `lobby*` (reserved for the online room screen). The deck code keeps the name **hall**. |
| AGENTS rule 1 | No franchise names, marks or jargon anywhere (code, strings, comments, file names, commits, docs, PNG names). The data lint scans every file under `godot/`. The sword is always the **saw sword** (ดาบเลื่อย), never a franchise weapon name. The gun and the egg's gauntlets are our own design; the only emblem is our candle. |
| Enemy model (public build) | The existing kit **`warrior`** (นักรบฝูง of the alien swarm army: skinned, 23 bones, 882 triangles, 2.14 m tall, kit scale 1.3) playing the baked clips of `assets/anim/humanoid.res` (§8.1). If kits are not on disk, a code-built **beast egg** stands in with the same AI (§8.2). |
| Player figure (public build) | The deck's **egg** in the team colour with two floating gauntlets, holding our own rifle or saw sword (§6.6). |
| Owner's own figures | Later, from a private repo, through a **pack** (`res://packs/arena/pack.json`, git-ignored here) that swaps the player and enemy figure scenes behind the figure contract (§9). Nothing of the pack is in this repo. |
| Lights | As on the deck: **no dynamic lights, no shadows** on any level; light baked into vertex colours (`HallBuilder.bake`); unshaded materials. The kit uses its own shader light (`figure.gdshader` uniforms, no `TIME`). |
| Per-frame work | The deck gains **nothing** per frame. In the arena, per-frame work runs only while something moves (§11.3); on min an idle arena (bot off, player still, no effect alive) processes nothing. Motion-only touches (flame flicker, beacon spin, additive effects, camera shake, tweens) on hi/mid only. |
| Randomness | Local single-player mode, so AGENTS rule 5 does not bind it, but every random choice (attack and death variants, spark directions) uses a `RandomNumberGenerator` with a fixed seed from `ArenaData.RANGE.seed`, re-seeded on reset, so tests repeat. No global `randf()` / `randi()`; game logic uses accumulated `delta`, never `Time` (only measurements read `Time`). |
| Sound | Out of scope this round (the `snd` setting exists; hooks are the `clip_event` / `shot` events, §9). |
| Release | `APP_VER` "ใหม่ 0.3" → **"ใหม่ 0.4"**, a Thai note in `web/`; godot-only change, **no candlelight-server PR** (§15). |

## 1. Names and every new string

Thai first, an English pair for every new Thai string (AGENTS rule 4). `I18n.t` matches **whole strings only**:
translate the template, then `.format()` it. Every key below was checked on 13 Nov against `data/i18n_en.json`,
`ui/i18n_extra.json`, `I18n.EN` and the three fragments: the "new" ones do not exist yet, the "reuse" ones do (never add a
reused key again: a duplicate across sources fails `test_i18n_fragments`). Each new key lives in exactly one fragment;
other builders may use the same literal (it is still a whole key once the owning fragment has it).

New fragments (flat Thai → English objects, two-space indent, one pair per line), added to `I18n.FRAGMENTS` by ROOM in
step R0 (§12.1): `ui/i18n/arena.json` (ROOM), `ui/i18n/arena_hud.json` (PLAYER), `ui/i18n/arena_data.json` (ENEMY).

| Thai | English | Fragment (owner) | Used by |
| --- | --- | --- | --- |
| อารีน่าทดสอบอาวุธ | Weapons Arena | `hall.json` (ROOM) | deck `NAMES.arena`, `SIGNS.arena`; arena sign `door_arena` |
| สวิตช์บอท | Bot switch | `arena.json` (ROOM) | prompt name |
| สวิตช์บอท · ยิงหรือกด E | Bot switch · shoot it or press E | `arena.json` | sign `switch`, keyboard mode |
| สวิตช์บอท · ยิงหรือแตะใช้ | Bot switch · shoot it or tap use | `arena.json` | sign `switch`, touch mode |
| รีเซ็ต | Reset | `arena.json` | prompt name and sign `reset` |
| กลับดาดฟ้ายานรบ | Back to the Warship Deck | `arena.json` | sign `door_back` (over the corridor's deck door) |
| บอท: เปิด | Bot: ON | `arena.json` | board, line 1 |
| บอท: ปิด | Bot: OFF | `arena.json` | board, line 1 |
| พลังชีวิต {hp}/{max} | HP {hp}/{max} | `arena.json` | board line 2; HUD bars (PLAYER reuses the literal) |
| โดน {n} ครั้ง · ความเสียหายรวม {d} | {n} hits · {d} damage dealt | `arena.json` | board line 3 |
| ล้มแล้ว · กดรีเซ็ต | Down · press reset | `arena.json` | board line 2 while the beast is dead |
| บอทเปิด — สัตว์รังไล่ตามคุณแล้ว | Bot ON — the hive beast is coming for you | `arena.json` | toast |
| บอทปิด — ยืนเป็นเป้านิ่ง | Bot OFF — it stands still as a target | `arena.json` | toast |
| รีเซ็ตแล้ว | Reset done | `arena.json` | toast |
| หยุดชั่วคราว | Paused | `arena.json` | pause panel title |
| เดินเข้าอารีน่าแล้วจะถือปืน | Walk into the arena to draw your gun | `arena_hud.json` (PLAYER) | corridor hint |
| คลิกซ้ายยิง · คลิกขวาหรือ F ต่อย · R บรรจุกระสุน · 1 / 2 เปลี่ยนอาวุธ · Esc หยุด | Left click to fire · right click or F to punch · R to reload · 1 / 2 to switch weapons · Esc to pause | `arena_hud.json` | shooter hint, keyboard |
| ลากจอด้านขวาเพื่อเล็ง · ปุ่มยิง หมัด และอาวุธอยู่ขวาล่าง | Drag the right side to aim · fire, punch and weapon buttons are at the bottom right | `arena_hud.json` | shooter hint, touch |
| กำลังบรรจุกระสุน… | Reloading… | `arena_hud.json` | ammo line while reloading |
| บรรจุ | Reload | `arena_hud.json` | touch button |
| คุณล้ม! กำลังลุกขึ้น… | You're down! Getting up… | `arena_hud.json` | downed overlay |
| สัตว์รัง | Hive Beast | `arena_data.json` (ENEMY) | `ArenaData.BEAST.th`; board title; HUD enemy bar |
| ปืนไรเฟิล | Rifle | `arena_data.json` | `ArenaData.WEAPONS.gun.th`; HUD; weapon button |
| หมัด | Punch | `arena_data.json` | `ArenaData.WEAPONS.punch.th`; touch melee button |
| ดาบเลื่อย | Saw Sword | `arena_data.json` | `ArenaData.WEAPONS.sword.th`; HUD; weapon button |
| เล่นต่อ · กลับล็อบบี้ · ตั้งค่า · ‹ ล็อบบี้ · {name} · กด E · {name} · แตะเพื่อใช้ · ยิง | (existing) | reuse | pause panel, top bar, prompts, touch fire button |

- Thai literals live only under `ui/` (the lint checks every one of them is a whole key): `hall_screen.gd`,
  `arena_screen.gd/.tscn`, `arena_hud.gd`, `arena_touch.gd`, `ui/arena/arena_data.gd`. Scripts under `scenes/arena/`
  carry **no Thai**; 3D labels get their text from the arena screen (`ArenaWorld.set_sign_text`), as on the deck.
- Numbers on screen (ammo "24 / 30", damage numbers) are plain digits, no key needed.
- A pack may carry its own enemy display name (§9.3); that text comes from the pack, never from this repo.

## 2. The deck: the arena door (ROOM)

### 2.1 Where and why there

| Item | Value |
| --- | --- |
| Station id | `arena`, appended: `HallLayout.IDS` = `["battle", "army", "settings", "online", "adventure", "exit", "vault", "arena"]` |
| Footprint | centre (−9.8, 7.9), half (1.0, 0.2), not round (a blocker box like the exit door's: the avatar stops at z 7.35) |
| Reach / height | 1.4 / 3.8 |
| Front ring | (−9.8, 6.95) |
| Sign | (−9.8, 4.3, 7.62), face π (towards −z), text `SIGNS.arena` = อารีน่าทดสอบอาวุธ |
| Drawn opening | `HallLayout.ARENA_DOOR = {"x0": -10.8, "x1": -8.8, "spring": 2.5, "apex": 3.8, "stub": 2.5}`: a pointed arch from the floor (rise 1.3 > half width 1.0, so really pointed) cut into the drawn front wall |
| Collider | **unchanged**: the front wall body stays whole (the opening is a hole in the drawn wall only, as the viewport lancets are); the station's own box blocks the doorway, so the avatar and camera never leave the 24 × 16 m box and `room_clear` / `inside_solid` stay valid |
| Auto entry | `HallLayout.in_arena_doorway(p: Vector2) -> bool`: `abs(p.x + 9.8) <= 0.75 and p.y >= 7.7 - AVATAR_R - ARENA_AUTO` with `ARENA_AUTO := 0.12` (z ≥ 7.23): walking into the doorway enters (§2.3) |
| Return spot | `HallLayout.ARENA_RETURN := Vector3(-9.8, 0.0, 5.2)`, face π (looking −z), camera yaw 0, pitch −0.45, arm 6.5: free, in no trigger, arm ≈ 2.6 m (the egg stays opaque) |

Why the front-left: (1) the front wall carries only panels, the exit door and two banners, so nothing moves; (2) none of
today's measured views sees it: the overview looks −z, and the phone layout's worst view looks from the war table
towards the back-right (yaw 1.75π) and the **front-right** (yaw 1.25π) corners, where the deck already measures 29 draw
calls on min against its target of 30, so a door sign there would leave no margin; (3) every distance clears:

- front ring → adventure table rect 3.5 m (> its 1.5 reach); → pillar (−8.5, 5.5) 1.95 m; → exit rect 8.6 m;
- footprint → pillar (−8.5, 5.5) 2.2 m, → stand (−11.3, 3.0) 4.7 m; the left wall's amber screen (x −12, z 6.75) is
  on the other wall, 1.2 m past the door's left jamb;
- return spot → pillar 1.33 m (> 0.45 + 0.35), → stand 2.66 m, → army rect 3.7 m, → adventure rect 3.5 m;
- the corner test's start (−10.8, 6.9) lies outside the auto zone (x < −10.55) and walks away from it (S+A);
- the door box's front face (z 7.7) equals the exit door's, so the camera pushed off the front wall (z ≤ 7.55) behaves
  exactly as at the exit door.

### 2.2 Look (our design; all in `Static/Shell`, so **no new draw call** except the sign)

- **Cut** the drawn front wall around the opening: the base plate, the 2 × 1.5 m panels and the wainscot follow the
  `_subtract` / window-cut pattern of `_back_wall`. Reveals (jambs and the arch soffit) over the wall's 0.5 m depth
  (z 8.0 to 8.5), so you never see into the wall.
- **Frame**: a bronze pointed-arch frame 0.18 m wide standing 0.25 m into the room (inside the station box below 3.8 m;
  above that the deck's protrusion rule, ≤ 0.2 m), hazard chevrons on the floor at the sill
  (`_chevrons(g, Vector3(-9.8, 0.014, 7.58), Vector3.RIGHT, 1.0, 0.11)`), a small amber lamp in the frame's apex
  (unbaked glow, like the exit lamp).
- **Corridor stub** behind it, z 8.5 to 11.0 (`stub` 2.5 m), x ∈ [−10.8, −8.8]: deck-plate floor with a grating strip,
  steel side walls with one rib frame at z 9.75, a pointed barrel ceiling continuing the arch profile, an amber strip
  light under the ridge, cable tray on one side. It ends in a **closed pressure door** at z 11.0: two steel leaves with
  bronze trim and hazard chevrons, the transom above closed in steel, an amber lamp over it (the same door is the
  corridor's deck end in the arena, §4). Closed geometry everywhere: the void test (§13.3) must find no magenta.
- **Light**: the stub's geometry is built in its own `Geo` and baked with no flames and one local light
  `HallLayout.ARENA_STUB_LIGHT := {"p": Vector3(-9.8, 3.2, 9.8), "k": 0.9, "d": 3.0, "col": SCREEN_AMBER}`, then appended
  to the Shell (it is outside the room, so it is **not** in `COOL_LIGHTS`, whose test wants every light inside). One cool
  light joins `COOL_LIGHTS` at the mouth: `{"p": Vector3(-9.8, 2.6, 7.6), "k": 0.35, "d": 2.5, "col": SCREEN_AMBER}`.
- Budget: the Shell grows by at most **800 triangles** (Shell triangles are drawn in every view, so deck primitives rise
  by that much everywhere; all deck targets keep room: min overview measured 12,956 of 30k).

### 2.3 Behaviour (`ui/screens/hall_screen.gd`, surgical)

- `NAMES.arena` and `SIGNS.arena` = "อารีน่าทดสอบอาวุธ"; `use_station()` gets `"arena": enter_arena()`.
- **Walk-in**: in the existing `_on_avatar_moved(p)` (a signal, no new per-frame work): when
  `world.station() == "arena"`, `HallLayout.in_arena_doorway(Vector2(p.x, p.z))` and the player is actively moving
  (`world.avatar.input_vector() != Vector2.ZERO`), call `enter_arena()`.
- `enter_arena()`: once (guard `_entering`), `world.avatar.halt()`, `stick.release()`, `close_soon()`, then the fade out
  (§10.2), then `App.push(load(ARENA_SCREEN))` with `ARENA_SCREEN := "res://ui/screens/arena_screen.tscn"`, and remember
  `_from_arena = true`.
- **Coming back**: when the hall shows again (`_activate(true)`) and `_from_arena` is set: clear it,
  `world.place_avatar(HallLayout.ARENA_RETURN, PI)`, `world.camera_rig.set_view(0.0, -0.45, 6.5)`, then the fade in.
- New node in `hall_screen.tscn`: `%Fade` (ColorRect, black, full rect, hidden, `mouse_filter` IGNORE; STOP while a fade
  runs so no tap leaks through). `handle_back()` returns true (swallows) while a fade runs.
- Nothing else in the hall changes: controls, camera, spawn, prompts, timers, the other stations.

## 3. Seamless or a fade: decision and budget reasons

Chosen: **a separate arena screen with a short fade** at the deck door; the corridor and the arena are one seamless world
inside that screen (the gun is drawn without any cut when you cross into the room).

1. **The deck's budget has no room.** The phone layout's worst view measures 38 / 38 / 30 / 29 draw calls (hi / mid / lo /
   min) against the targets 40 / 40 / 35 / 30. A seamless arena adds at least: arena shell and props (2–3 meshes), the
   enemy (1 skinned draw), the player's weapon and gauntlets (2), effects (1), the beacon (1), six labels (board, switch,
   reset, door signs) and the combat HUD (bars, crosshair, ammo, numbers: 4–6). The Compatibility renderer culls per
   instance by the frustum only (no occlusion by walls), so every deck view that looks towards the doorway would pay for
   the arena behind the wall: 10–15 more draw calls, far beyond 30 on min.
2. **Per-frame work.** The arena needs AI, a shooter camera, aiming and effects. Inside the deck world that work (or the
   visibility switching that hides it) would run in the deck; on a separate screen it simply stops when the screen is
   hidden or freed (the screen-stack rule of LOBBY §1), and the deck keeps nothing processing while idle.
3. **The deck's camera math is a box.** `HallLayout.room_clear`, `inside_solid`, `camera_clear` and `blocked` (and 264
   `test_hall` checks, 31 `test_hall_reach` checks) assume the 24 × 16 m box. Walking into a real corridor would need a
   new room model in code that is finished and reviewed. With the door box closing the doorway the model stays true.
4. **Memory and start-up.** The kit, its 0.6 MB clip library and the arena meshes load only on entry and are freed on
   leaving (`App.pop` frees the screen; the meshes stay cached per level like the deck's).
5. **Cost of the fade**: 0.25 s out + build + 0.25 s in on hi/mid; a cut on lo/min (§10.2). The build target is
   ≤ 150 ms of CPU on the test machine (printed by `test_arena`, asserted ≤ 2,000 ms so slow CI never flakes).

## 4. The arena world (ROOM): `ArenaLayout`, `scenes/arena/arena_layout.gd`

`class_name ArenaLayout extends RefCounted`: pure data, no Node, no Thai, floats allowed; the same conventions as
`HallLayout` (metres, y up, x/z footprints, `Vector2(x, z)`). The world is its own frame: the corridor starts at the deck
door at z = 0 and runs towards −z, so the camera starts at **yaw 0 looking −z**, as on the deck.

### 4.1 Plan

```
 z = 0      ┌──┐  pressure door "to the deck" (blocker), sign door_back
            │  │  corridor 2.6 m wide, 4.6 m high, 10 m long (ribs every 2 m, amber strips)
 z = -10.0  │  │  arena near wall (0.5 m) with the arch 2.0 m wide; sign door_arena on the corridor side
 z = -10.5 ┌┘  └────────────────────┐
           │ st  ═════════════  st   │  shoot line z -11.3 (hazard stripe x ∈ [-2, 2]); candle stands (±2.4, -11.2)
           │reset             switch │  reset (-6.5, -13.5)   bot switch (6.5, -13.5)
           │                         │  range lines every 5 m: z -16.3, -21.3, -26.3, -31.3 (|x| ≤ 2)
           │   P             P       │  pillars (±4.5, -18.5)
           │      P       P          │  pillars (±3.2, -24.5)
           │          (●)            │  beast pad (0, -29), r 1.6, hazard ring
           │       [ BOARD ]         │  status board on the far wall, centre (0, 4.6)
 z = -34.5 └─────────────────────────┘  x ∈ [-10, 10]
```

| Constant | Value |
| --- | --- |
| `ROOM_MIN`, `ROOM_MAX` | (−10, −34.5), (10, −10.5): 20 × 24 m interior |
| `ROOM_H`, `CEIL_Y` | 7.0 drawn ceiling; invisible ceiling collider at 6.5 (the camera never goes higher) |
| `WALL_T` | 0.5 (walls outside the interior, as on the deck) |
| `CORR_X`, `CORR_Z0`, `CORR_Z1`, `CORR_H` | half width 1.3; floor from z 0 to −10; ceiling 4.6 (drawn and collider) |
| `DOOR_BACK` | blocker box centre (0, −0.15), half (1.3, 0.15), height 4.6: the corridor's deck end (the pressure door of §2.2, seen from the other side) |
| `ARCH` | `{"x0": -1.0, "x1": 1.0, "spring": 2.8, "apex": 4.0}` in the near wall (z −10.0 to −10.5); colliders: the near wall either side of the opening, and a lintel box over x ∈ [−1, 1] from y 3.4 up, approximating the arch (a walk-mode camera behind the avatar passes at y ≤ 3.2 near x 0; the void and camera checks of §13.4 cover the arch's corners) |
| `SPAWN`, `SPAWN_FACE`, `SPAWN_YAW` | (0, 0, −2.2); figure face π (looking −z); camera yaw 0, pitch −0.35, arm 4.5 |
| `LEAVE_Z` | −0.95: in walk mode, an avatar centre at z ≥ −0.95 leaves (the door box stops it at −0.65) |
| `SHOOT_Z`, `WALK_Z` | −11.3 / −10.8: centre z < −11.3 switches to shoot mode; back above −10.8 switches to walk mode (0.5 m hysteresis) |
| `RESPAWN` | (0, 0, −12.5), face π, camera yaw 0: where a downed player gets up |
| `BEAST_SPAWN`, `BEAST_FACE`, `PAD_R` | (0, 0, −29), face 0 (towards +z, the entry), pad radius 1.6 (paint only, not a blocker) |
| `PILLAR_R`, `PILLAR_H`, `PILLARS` | 0.8, 4.0, (−4.5, −18.5), (4.5, −18.5), (−3.2, −24.5), (3.2, −24.5): octagonal cover; the lane \|x\| < 2.4 stays clear from the shoot line to the pad |
| `STANDS` | (−2.4, −11.2), (2.4, −11.2): deck candle stands (r 0.28, h 1.72), one flame each |
| `STATIONS.switch` | round post c (6.5, −13.5), r 0.35, height 2.4, reach 1.5, front (5.3, −13.5); `plate` (6.5, 2.1, −13.5), `plate_r` 0.45; sign (6.5, 2.95, −13.5), face −π/2 (towards −x); beacon (6.5, 2.7, −13.5) |
| `STATIONS.reset` | box c (−6.5, −13.5), half (0.35, 0.35), height 1.1, reach 1.5, front (−5.3, −13.5); button top (−6.5, 1.18, −13.5); sign (−6.5, 1.95, −13.5), face π/2 |
| `BOARD` | plate centre (0, 4.6, −34.45), 6.4 × 3.0 m (in the Shell); `BOARD_TITLE` (0, 5.65, −34.38), `BOARD_BODY` (0, 4.3, −34.38), face 0 |
| `SIGNS` | `door_back` (0, 3.3, −0.32) face π; `door_arena` (0, 4.25, −9.97) face 0; `switch`, `reset` from the stations |
| `LIGHTS` (cool, baked) | floods (±5, 6.6, −15), (±5, 6.6, −22), (±5, 6.6, −29): k 0.55, D 40, #dfe8ff; corridor strips (0, 4.3, z) for z −2, −4.5, −7, −9.5: k 0.45, D 3, `SCREEN_AMBER`; board (0, 4.6, −33.8): k 0.4, D 6, `SCREEN_GREEN`; pad (0, 0.3, −29): k 0.3, D 3, `HAZARD` |
| `flames()` | the two stand flames at (±2.4, 1.98, −11.2) (warm bake and the flame MultiMesh) |

Checked: shoot line → switch plate has a clear line of sight (all pillars lie at z ≤ −18.5); the board's corners are seen
from (0, 1.5, −12) between the inner pillars (the sight lines pass x = ±1.8 at z −24.5; pillar edges at ±2.4); every
station front ring is free and inside its own trigger only; the beast pad is 5.5 m from the nearest pillar.

### 4.2 Functions (pure)

`blockers() -> Array[Dictionary]` in `HallLayout.blockers()` format plus a `"layer"` key (`"shell"` / `"prop"`): the room's
four walls (the near wall split around the arch, plus the lintel), the corridor's two walls, `DOOR_BACK`, both ceilings,
pillars (`shell`: the shooter camera's arm collides with them), stands, the switch post and the reset pedestal (`prop`).
`station_at(p)` (nearest wins, as on the deck), `in_room(p)`, `in_corridor(p)`, `blocked(p, r)`,
`inside_solid(p: Vector3, margin)`, `mode_for(z: float, current: StringName) -> StringName` (hysteresis),
`leaving(z: float, mode: StringName) -> bool`, `room_rect() -> Rect2`, `flames() -> PackedVector3Array`.

### 4.3 Physics layers (arena only; the deck and the table are disabled while the arena screen shows)

| Value | What | Collides with (mask) |
| --- | --- | --- |
| 1 `SHELL` | walls, ceilings, `DOOR_BACK`, lintel, **pillars** | — |
| 2 `PLAYER` | the player's capsule (r 0.35, h 1.75) | 1, 4, 8 |
| 4 `PROP` | stands, switch post, reset pedestal (walk-blocking; the camera arm ignores them) | — |
| 8 `BEAST` | the beast's capsule (its hurt box too); 0 while dead | 1, 4, 2 |
| 16 `TARGET` | the switch plate (sphere r 0.45), shots only | — |

Shot rays use mask 1 | 4 | 8 | 16 and exclude the player. The shooter camera's spring arm uses mask 1.

### 4.4 Look and build (`ArenaBuilder`, `scenes/arena/arena_builder.gd`)

Our own design in the deck's language, built with `PropsLayer.Geo` and the deck's helpers (`HallBuilder.lathe`, `tube`,
`bake`, `append`, `material`, `arch_outline`, `flame_mesh`; HallBuilder's palette constants), seeded RNG only:

- **Corridor**: deck-plate floor with a centre grating strip, steel walls with rib frames every 2 m (0.12 m deep, inside
  the protrusion rule), a cable tray, amber strip lights under the flat steel ceiling, the pressure door at z 0 (as §2.2),
  the arch at the far end with hazard chevrons on its sill.
- **Arena**: dark deck plates; the shoot-line stripe and the range lines in dim `HAZARD`; steel wall panels with a bronze
  wainscot (as the deck), pilasters every 4 m (≤ 0.2 m), a deep-beamed steel ceiling at 7.0 with six floodlight fixtures
  (bright unbaked quads), the beast pad (dark disc, hazard ring with chevrons), the status board's dark plate with a
  bronze frame, the octagonal pillars with bronze bands, the switch post (steel post, hazard-striped collar, the round
  plate), the reset pedestal (octagonal brass pedestal, yellow mushroom button), the two candle stands with our candle
  banner on each side of the arch (one banner each, `HallBuilder._banner` style, built locally).
- **Meshes**: `Static/Shell` (corridor + room + board plate + pillars), `Static/Props` (stands, switch post, reset
  pedestal, banners, candle bodies): at most **2 static meshes**, cached per `sides` (14 / 12 / 10 / 8). Estimated
  ≤ 9k + 2k triangles. `SwitchHead` (the plate, one unshaded `StandardMaterial3D` whose colour changes on a toggle: red
  #d8463c off, green #5fe08a on), `Beacon` (amber dome over the switch: `beacon.gdshader` spin on hi/mid while the bot is
  on; plain material lo/min, lit only while on), `Flames` (MultiMesh, the deck's flame shader on hi/mid, plain lo/min).
- **Environment** on the arena camera (no `WorldEnvironment`): background #05060a, ambient black, linear tone map.

## 5. Modes, controls and camera (PLAYER)

### 5.1 Modes

| Mode | Where | Body | Camera | Input |
| --- | --- | --- | --- | --- |
| `walk` | corridor (and the first 0.8 m of the room) | the egg, no weapon (`set_weapon(&"none")`), turns to face its movement like the deck avatar | **follow**: like `HallCamera` (pivot + 1.3, arm 4.5 in [2.5, 6], pitch −0.35 in [−1.0, −0.1], LMB/RMB drag or one-finger drag orbits, wheel / pinch zooms) | deck controls: WASD / arrows camera-relative, Shift run, E use, stick on touch |
| `shoot` | inside the room past the shoot line | the egg **draws the rifle** (§6.6), always faces the camera's yaw (strafing) | **shoulder** (§5.4) | §5.2 / §5.3 |

`ArenaWorld` listens to `player.moved(pos)` and calls `player.set_mode(ArenaLayout.mode_for(pos.z, player.mode()))`;
entering `shoot` draws the gun (a 0.2 s scale-in on hi/mid, instant on lo/min), blends the camera (0.3 s tween on hi/mid,
instant on lo/min), shows the crosshair and the shooter HUD, captures the mouse on desktop, and the first time shows the
shooter hint (5 s, or until the first shot). Back in `walk` the gun is holstered, the mouse released, the follow camera
restored behind the avatar.

### 5.2 Desktop controls in `shoot` mode

| Input | Action | Input map |
| --- | --- | --- |
| W A S D / arrows | move, camera-relative (strafe; the body keeps facing the camera yaw) | existing `move_*` |
| mouse motion | look / aim: yaw and pitch at `LOOK_SPEED` 0.0025 rad per pixel; pitch in [−0.9, 0.6] | — (captured motion) |
| left button (hold) | fire the current weapon: rifle full-auto, saw sword swings (repeats while held at its cooldown) | **new** `fire` (mouse button 1) |
| right button or F | punch | **new** `melee` (mouse button 2, physical F 70) |
| Shift | run | existing `run` |
| 1 / 2, wheel | rifle / saw sword; the wheel cycles | **new** `weapon_1` (physical 49), `weapon_2` (physical 50); wheel read in code (press-only events) |
| R | reload | **new** `reload` (physical 82) |
| E | use the switch or the reset button in reach | existing `interact` |
| Esc | release the mouse and open the pause panel (§10.3) | existing `back` |

- Mouse capture: entering `shoot` on desktop sets `Input.mouse_mode = MOUSE_MODE_CAPTURED`; `walk`, the pause panel,
  leaving, hiding the screen and focus loss (`NOTIFICATION_APPLICATION_FOCUS_OUT`) set `MOUSE_MODE_VISIBLE`. After
  "เล่นต่อ" the next left click only re-captures (it does not fire). Look works whenever the mode is `shoot` and the game is
  not paused, captured or not (headless tests cannot capture).
- `fire` / `melee` are read in `_unhandled_input`, so a click on a HUD button never fires. Mouse events emulated from
  touch (`DEVICE_ID_EMULATION`) are ignored, as on the deck.
- Weapon switch: holster 0.15 s + draw 0.2 s (no firing meanwhile); a running reload is cancelled.
- An empty magazine reloads by itself on the next fire press; R reloads at any time below a full magazine.

### 5.3 Touch controls (`App.touch_active()`; re-read on every show)

Logical canvas 1280 × 720 (also 640 × 360 windows) or 1600 × 720 at 20:9; positions from the safe-area corner
(`CandleStyle.safe_margins`, 16 px gutter). All buttons are real `Button` nodes (round `StyleBoxFlat`, corner radius =
half the size), `focus_mode` none, at least 44 × 44.

| Node (under `Hud/Touch`) | Shape | Centre, from the bottom-right safe corner (dx, dy) | Behaviour |
| --- | --- | --- | --- |
| `Stick` | the existing `TouchStick` (instanced, not edited) | bottom-left, as on the deck (180 × 180) | move; past 0.85 runs |
| `FireButton` | circle r 62, text "ยิง" | (−106, −116) | hold = fire; a drag that starts on it also aims (one thumb shoots and steers) |
| `MeleeButton` | circle r 46, text "หมัด" | (−234, −60) | punch |
| `ReloadButton` | circle r 38, text "บรรจุ" | (−218, −198) | reload |
| `WeaponButton` | circle r 38, text = the *other* weapon's name ("ดาบเลื่อย" / "ปืนไรเฟิล", font auto-fit) | (−84, −256) | switch weapon |
| `AimPad` | invisible Control over the right half (x ≥ 50 % of the width), below the buttons in the tree | — | a one-finger drag aims at `TOUCH_LOOK` 0.006 rad per logical px |

At 1280 × 720 the centres are fire (1158, 588), melee (1030, 644), reload (1046, 506), weapon (1180, 448): all within
**290 px of the bottom-right safe corner** (thumb reach), no two buttons closer than their radii + 20 px, and clear of the
screen's `%UseButton` (bottom centre, 500 × 80) at both 1280 and 1600 widths (checked in §13.4). In `walk` mode only the
stick and the deck-style orbit drag show; the four shooter buttons hide.

### 5.4 The shoulder camera (`ArenaCamera`, `scenes/arena/arena_camera.gd`)

- Pivot = player position + (0, 1.55, 0) + `right_flat() × 0.55`; arm **2.6 m** straight back along the view (no zoom);
  FOV 62 (walk mode 60); near 0.05, far 80.
- `SpringArm3D`: sphere r 0.25, margin 0.05, mask 1 (shell + pillars). Pulls in at once, extends back at most 4 m/s (the
  deck's rule, so a pillar passing behind does not make it jump back and forth). Under 1.2 m of arm the egg fades
  (alpha down to 0.35 at 0.6 m, the deck's fade mechanism).
- Yaw convention as `HallCamera`: `forward_flat() = (−sin yaw, 0, −cos yaw)`, `right_flat() = (cos yaw, 0, −sin yaw)`.
- **Aim**: the crosshair sits at the exact viewport centre. `aim_ray()`: from the camera through the centre, 80 m,
  mask 1 | 4 | 8 | 16, excluding the player → the aim point (or the far end). The shot then runs from the muzzle to the aim
  point with the same mask; its first hit is the real target (a pillar beside the muzzle can block a shot the crosshair
  showed clear — honest cover).
- `_process` / `_physics_process` only while blending, following a moving player, or the arm is not settled (the deck's
  settle rule); otherwise off.
- Camera shake on melee hits (0.1 s, 0.04 m) on hi/mid only.

### 5.5 HUD (`ArenaHud`, `ui/widgets/arena_hud.gd`, built in code)

The screen creates it at runtime (`load(ARENA_HUD).new()`, named `Hud`, full rect inside `Safe/Layer`, mouse ignore except
its touch buttons). One custom `_draw()` paints the crosshair, both bars and the floating numbers (redrawn only when
something changes; while numbers live it redraws each frame for their lifetime only).

| Node / drawn item | Where | Content |
| --- | --- | --- |
| `Crosshair` (drawn) | exact centre | four short bars + dot; a hit marker (X) for 0.12 s when a shot lands; red tint while the aim point is the beast |
| `EnemyBar` (drawn) | top centre, 480 × 22, below y 16 | "สัตว์รัง" (or the pack's name) + bar + "220/300"; shown in shoot mode while the beast is alive or in its death clip |
| `PlayerBar` (drawn) | top left, under `%LobbyButton` (y 84), 320 × 24 | "พลังชีวิต {hp}/{max}" + bar |
| `Ammo` (Label) | desktop bottom right (16 px in); touch: above `WeaponButton` | "24 / 30 · ปืนไรเฟิล", "กำลังบรรจุกระสุน…" with a thin progress line, or the sword's name |
| `Numbers` (drawn) | at the projected hit point | white 26 px, or amber 34 px for ≥ 25 (`ArenaCombat.number_style`); rise 0.6 m and fade over 0.8 s on hi/mid; shown still for 0.6 s on lo/min; a pool of 8 |
| `Hint` (Label, deck style) | top centre under the enemy bar | corridor hint in walk mode, shooter hint (keyboard / touch) in shoot mode |
| `Hurt` (ColorRect) | full screen | red edge flash 0.2 s when the player is hit (tween hi/mid, step lo/min) |
| `Downed` (Label + dim) | centre | "คุณล้ม! กำลังลุกขึ้น…" for the 2 s down time |
| `Touch` (`ArenaTouch`, `ui/widgets/arena_touch.gd`) | §5.3 | stick, aim pad, four buttons |

Everything stays inside the safe area; nothing overlaps the screen's own nodes (`%LobbyButton`, `%SettingsButton`,
`%UseButton`, `%Toast`, `%PausePanel`).

## 6. Combat (ENEMY owns the table and the math; PLAYER the weapons that use them)

### 6.1 The data table: `ArenaData` (`ui/arena/arena_data.gd`)

`class_name ArenaData extends RefCounted`, constants only (it lives under `ui/` because it carries Thai labels; the lint
checks them). Every number of the arena lives here; nothing else hard-codes a combat number.

```gdscript
const WEAPONS := {
	"gun": {"th": "ปืนไรเฟิล", "kind": "hitscan", "slot": 1, "damage": 12, "rate": 8.0, "mag": 30, "reload": 1.6,
		"range": 60.0, "knockback": 0.4, "stagger": false},
	"sword": {"th": "ดาบเลื่อย", "kind": "melee", "slot": 2, "damage": 45, "active": 0.18, "cooldown": 0.8,
		"reach": 2.3, "half_angle_deg": 75.0, "knockback": 2.0, "stagger": true},
	"punch": {"th": "หมัด", "kind": "melee", "slot": 0, "damage": 25, "active": 0.12, "cooldown": 0.55,
		"reach": 1.6, "half_angle_deg": 50.0, "knockback": 3.0, "stagger": true},
}
const PLAYER := {"hp": 100, "walk": 3.0, "run": 5.0, "accel": 12.0, "radius": 0.35, "invuln": 0.4, "down_time": 2.0,
	"holster": 0.15, "draw": 0.2}
const BEAST := {"th": "สัตว์รัง", "kit": "warrior", "hp": 300, "radius": 0.6, "height": 2.1, "walk": 1.5, "run": 3.7,
	"turn": 6.0, "attack_range": 2.2, "windup": 0.6, "attack_clip_speed": 0.6, "strike_damage": 18, "strike_reach": 2.6,
	"strike_half_angle_deg": 70.0, "recover": 0.7, "flinch": 0.35, "flinch_heavy": 0.8, "heavy_at": 40,
	"friction": 8.0, "think_hz": 10.0, "repath": 0.4, "grace": 3.0, "home_speed": 1.5}
const RANGE := {"seed": 4404, "switch_cooldown": 1.0}
const NUMBERS := {"heavy_at": 25, "life": 0.8, "rise": 0.6, "still": 0.6, "pool": 8}
```

Feel, for the owner: the rifle kills the beast with 25 hits (about 3 s of steady fire, one magazine); 12 punches or 7
sword swings. Its claw takes 18 of the player's 100 HP after a 0.6 s wind-up that can be dodged by stepping back
(walk 3 m/s × 0.6 s = 1.8 m), and it chases at 3.7 m/s: faster than walking, slower than running.

### 6.2 The math: `ArenaCombat` (`ui/arena/arena_combat.gd`)

`class_name ArenaCombat extends RefCounted`, static and pure (no Node, no physics, no Thai). Facing convention as the deck
avatar: a figure's face yaw 0 looks +z, `yaw_to(a, b) = atan2(b.x − a.x, b.z − a.z)`, forward = (sin yaw, cos yaw).

```gdscript
static func weapon(id: String) -> Dictionary
static func fire_interval(id: String) -> float                          # 1 / rate (0.125 s for the rifle)
static func can_fire(now: float, last: float, id: String) -> bool       # now - last >= interval (cooldown for melee)
static func after_shot(in_mag: int) -> int                              # max(in_mag - 1, 0)
static func needs_reload(in_mag: int) -> bool
static func full_mag(id: String) -> int
static func in_cone(origin: Vector2, face_yaw: float, target: Vector2, target_r: float, reach: float, half_angle_deg: float) -> bool
static func melee_hits(id: String, origin: Vector2, face_yaw: float, target: Vector2, target_r: float) -> bool
static func apply(hp: int, amount: int) -> Dictionary                   # {"hp", "applied" (<= hp), "killed"}
static func reaction(amount: int, stagger: bool) -> StringName          # &"none" | &"flinch" | &"flinch_heavy" (heavy_at)
static func knockback(dir: Vector3, strength: float) -> Vector3          # horizontal impulse, y = 0
static func decay(v: Vector3, friction: float, dt: float) -> Vector3     # v * exp(-friction * dt)
static func number_style(amount: int) -> StringName                     # &"normal" | &"heavy"
static func yaw_to(from: Vector3, to: Vector3) -> float
```

`in_cone` counts a target whose circle (centre, radius) is within `reach` of the origin and whose centre lies within the
half angle of the facing (a target overlapping the origin always counts).

### 6.3 Hits (the shared dictionary)

```
hit = {"amount": int, "kind": &"gun" | &"punch" | &"sword" | &"claw", "point": Vector3, "dir": Vector3 (unit, y 0 for
       melee), "from": Vector3, "knockback": float (m/s), "stagger": bool}
take_hit(hit) -> {"applied": int, "hp": int, "killed": bool, "toggled": bool (switch only)}
```

- Rifle: each shot spends one round and casts the aim and muzzle rays (§5.4); on a target it calls `take_hit`.
- Punch and sword: at their `active` time after the press, `world.melee_targets()` lists `{"node", "id", "pos": Vector2,
  "r": float}` (the beast while alive, the switch post); every target for which `ArenaCombat.melee_hits` holds gets
  `take_hit` with `dir` from the player to the target. The beast's capsule radius comes from its metrics (§9).
- Every landed hit emits `player.hit_landed` (HUD numbers, hit marker) and is tallied by the world for the board.

### 6.4 Gun effects (`ArenaFx`, `scenes/arena/arena_fx.gd`, PLAYER)

One `MultiMeshInstance3D` (one draw call) holding tracers (thin quads 0.03 m wide from the muzzle to the hit point, alive
0.06 s), the muzzle flash (two crossed quads, 0.05 s) and impact sparks (tiny quads flying out for 0.15 s: 8 on hi, 5 on
mid, 3 on lo; min shows one impact quad for 0.1 s). Additive unshaded `StandardMaterial3D` (`blend_add`) on hi/mid;
opaque unshaded on lo/min. Positions come from the seeded fx RNG. `_process` runs only while an effect is alive.

### 6.5 Hit feedback

- Beast: a white flash for 0.08 s on every hit (`figure.set_flash`; an additive overlay material, a transient extra draw),
  the damage number, knockback impulse (decays with `friction`), and the reaction of `ArenaCombat.reaction` (bullets
  never flinch it: 12 < `heavy_at` and the rifle has no stagger; a punch flinches it 0.35 s; a sword swing staggers it
  0.8 s). A flinch during the wind-up **cancels the strike**.
- Player: red edge flash, the egg's flash, 0.4 s of invulnerability, HP bar; at 0 HP the player is **downed** for 2 s,
  then gets up at `RESPAWN` with full HP; the beast goes idle for `grace` 3 s.

### 6.6 The player's weapons and figure (`EggGunner`, `scenes/arena/egg_gunner.gd`, PLAYER)

The default player figure (a script-built Node3D implementing the figure contract, §9.1):

- **Egg**: `HallBuilder.avatar_mesh(team_colour, sides)` (the deck's egg, nub showing its front), bob on hi/mid only.
- **Gauntlets**: two bronze octagonal "fists" (r 0.11) floating at the egg's sides (local (±0.42, 1.0, 0.18)), in one
  2-instance MultiMesh (one draw). The right one holds the weapon, the left one steadies the rifle's barrel and throws the
  **punch** (0.9 m out and back in 0.25 s, the egg leaning 0.15 rad into it).
- **Rifle** (ours): brass receiver 0.5 × 0.12 × 0.09 m, steel barrel (0.45 m, r 0.025) inside a slotted cooling shroud,
  a short box magazine, a skeletal stock with our candle-flame emblem in brass; `Muzzle` (Marker3D) at the barrel's end.
  Recoil kick 6 cm per shot; reload = the rifle tips down and the magazine drops and returns over 1.6 s.
- **Saw sword** (ours): a 1.0 m steel blade with 18 triangular teeth along one edge, a boxy motor housing with brass
  vents and our candle emblem, a grip; swing arc from upper right to lower left in 0.25 s; the teeth do not animate.
- The weapon and the right gauntlet follow the aim pitch (`set_aim`); the egg leans ±0.15 rad with it.
- Procedural clips (an `AnimationPlayer` with animations built in code, or tweens): `idle`, `walk`, `run`, `fire`,
  `reload`, `punch`, `swing`, `hit`, `die` (the egg tips over 0.6 s). `play()` returns each clip's length. Draw calls:
  egg 1 + gauntlets 1 + weapon 1.

## 7. The switch, the reset button and the board (ROOM)

`ArenaState` (`scenes/arena/arena_state.gd`, `class_name ArenaState extends RefCounted`, pure): `bot_on`, `hits`,
`damage`, `last_toggle`; `toggle(now: float) -> bool` (refused within `RANGE.switch_cooldown` 1.0 s of the last toggle, so
a burst toggles once), `record_hit(applied: int)`, `reset()` (counters to 0; **the switch keeps its position**, so a reset
with the bot on starts a fresh fight at once, and the board says which), `stats(beast: Dictionary) -> Dictionary`.

- **Bot switch**: `E` / use in reach, any gun hit on the plate, or a punch / sword swing that reaches the post toggles it
  (`world.take_hit` with id `switch`). On a toggle: the plate turns green / red, the beacon lights (and spins on hi/mid
  while on), `enemy.set_bot(on)`, the toast (§1) for 2 s, the board line 1.
- **Reset**: `E` / use in reach only (never by shooting). It calls `enemy.reset_to(BEAST_SPAWN, BEAST_FACE)` (full HP,
  alive, back on the pad, seeded RNG re-seeded), `player.heal_full()` (HP and a full magazine), `state.reset()`, toast
  "รีเซ็ตแล้ว".
- **Board** (two Label3D on the far wall, screen green on the dark plate, the deck's font size 88 with a larger pixel
  size so they read from the shoot line: title 0.010, body 0.008, tuned by the PNG): title = the enemy's name; body lines
  "บอท: เปิด|ปิด", "พลังชีวิต {hp}/{max}" (or "ล้มแล้ว · กดรีเซ็ต" while dead), "โดน {n} ครั้ง · ความเสียหายรวม {d}".
  Updated on `stats_changed` only.
- Station rings (the deck's `Rings`, one draw) at the two front rings, gold while in reach; the player's own team ring
  follows it (set on `moved` only).

## 8. The hive beast (ENEMY)

### 8.1 Model and clips (public build: `KitBeast`, `scenes/arena/kit_beast.gd`)

- Kit `warrior` from `res://assets/kits/warrior.glb` (`KitLibrary.kit_path`), imported as `<kit>` > `Skeleton3D` >
  `<kit>_mesh`; one surface, one draw. `Skeleton3D.motion_scale = 1.3` (kits.json `scale`). Its own colours (purple
  carapace, bone claws, amber eyes); no team tint (team colour is the ring rule).
- Material: a **duplicate** of `figure_material.tres` (never change the shared one, which the battle uses) with
  `per_vertex` true on lo/min (false on hi/mid), `sun_dir` (0.2, 1.0, 0.3), `sun_colour` (0.62, 0.64, 0.68),
  `ambient_colour` (0.34, 0.36, 0.42): overhead floods. No `TIME` in it on any level.
- An `AnimationPlayer` child with `root_node = ".."` holding `humanoid.res` (`humanoid/<clip>`), as
  `test_anim_footslide.gd` builds it. Clip map (logical → clips; variants picked with the seeded RNG):

| Logical | Clips | Notes |
| --- | --- | --- |
| `idle` | `idle` (8.4 s loop) | hi/mid/lo; on min the dummy holds a still pose (§11.3) |
| `walk` | `walk` (1.15 m/s × 1.3) | homing; playback speed = speed / (clip speed × 1.3), so feet do not slide |
| `run` | `run` (2.868 m/s × 1.3 = 3.73) | chase at 3.7 m/s (playback 0.99) |
| `attack` | `claw_0`, `claw_1`, `claw_2` | warrior's melee kind in `data/anim.json` is `claw`; played from the start of the wind-up at `attack_clip_speed` 0.6, so the blow (clip event `shot` at 0.433 s) lands 0.72 s after the wind-up began (§8.3) |
| `hit` | `flinch` | 0.5 s clip, cut to `flinch` 0.35 s |
| `hit_heavy` | `flinch_heavy` | 1.03 s clip, cut to 0.8 s |
| `die` | `die_fwd`, `die_back`, `die_topple` | the last frame is held (a still pose) until reset |

- **Holds** (`clips.json` `holds.warrior`): the kit's hunch over the clips, as `test_anim_footslide.apply_holds()`
  (copy it): mode `all` on locomotion, `undriven` on actions. The hold's weight eases over 0.15 s between clips so the
  hunch never pops when a claw (which drives the spine and arms) starts or ends — the beast rearing up during the strike
  reads as part of the telegraph. The hold's `root` lowering (−0.067 rig m) and its leg `ik` are **skipped** this round
  (no runtime IK yet): the beast stands about 9 cm taller than the page's crouch, feet on the floor.
- Metrics: height 2.14 (kits.json bbox), capsule radius 0.6 (`BEAST.radius`), chest anchor at y 1.4, head 1.9.
- Not faithful on its own skeleton (CLIPS.md §5): `claw` on crouching kits. The PNG contact sheet (§13.5) is reviewed; if
  `claw_*` reads badly on this kit, `bash_0..2` (faithful on humanoids) may replace it, recorded in §17.

### 8.2 Fallback without kits (`KitBeast` builds it when `KitLibrary.has_kit("warrior")` is false or the kit fails to load)

A **beast egg**: a 2.0 m egg lathe (`HallBuilder.lathe`) in carapace purple (#8a4ea2) with a bone-white crest, two forward
claws (bone prisms on floating "arms") and amber eye dots; the same figure contract with procedural clips (bob, lean
forward for run, claws rear back for the wind-up and slash, a back-step flinch, tip over to die). `kit_key()` returns
`"egg"`. Used in tests only when the kits are absent; CI and local runs have the kits.

### 8.3 AI: `HiveAI` (`scenes/arena/hive_ai.gd`, pure) driven by `HiveBeast` (`scenes/arena/hive_beast.gd`)

`class_name HiveAI extends RefCounted`; no Node, no physics; tested with fake time. States:

| State | Entered when | Does | Leaves to |
| --- | --- | --- | --- |
| `dummy` | bot off (start, toggle off, reset with bot off) | stands; faces where it was; slides only from knockback | `idle` when the bot turns on; `hit`/`dead` on damage |
| `idle` | bot on, target not in the room (corridor, downed) or in `grace` | walks home to the pad at `home_speed`, then faces +z | `chase` when the target is in the room and grace is over |
| `chase` | bot on, target in the room | follows the path (§8.4) at `run`, turning at `turn` rad/s; never leaves the room (the beast is leashed to `ROOM_MIN..ROOM_MAX`) | `windup` when centre distance ≤ `attack_range` 2.2 and the target is within 35° of its facing |
| `windup` | — | stops; plays `attack` from the start at 0.6 speed; the telegraph rises 0 → 1 over **0.6 s** (red floor ring under it grows 0.6 → 1.0 and brightens; on hi/mid/lo the figure tints red ×0.4 via `set_telegraph`); keeps turning towards the target at half `turn` | `strike` at 0.6 s; `hit`/`dead` on a stagger or death (the strike is cancelled) |
| `strike` | wind-up done (0.6 s) | the telegraph stays at 1; at the clip's `shot` event (0.72 s after the wind-up began) one hit if the target's centre is within `strike_reach` 2.6 and inside `strike_half_angle_deg` 70° of its facing: `target.take_hit({"amount": 18, "kind": &"claw", ...})`; no turning in this state | `recover` after the event |
| `recover` | — | stands for `recover` 0.7 s (the clip finishes) | `chase` (or `idle` / `dummy` per the bot and the target) |
| `hit` | a hit whose `reaction` is flinch / flinch_heavy | plays `hit` / `hit_heavy`; knockback slides it | the state it would choose next (`chase` / `dummy` / `idle`) after 0.35 / 0.8 s |
| `dead` | HP 0 from any state | plays `die`; collision layer 0 (shots and the player pass); the last frame is held | `dummy` / `idle` only on `reset` |

- `tick(dt, me, target) -> {"move": Vector2 (m/s), "face": float, "run": bool, "events": Array[StringName]}` with
  `me = {"pos": Vector2, "yaw": float, "hp": int, "alive": bool}` and `target = {"pos": Vector2, "alive": bool,
  "in_room": bool, "r": float}`; events `&"windup"`, `&"strike"`, `&"recovered"`, `&"died"`. Thinking (state choice,
  path refresh every `repath` 0.4 s) at `think_hz` 10 Hz from accumulated delta; movement integrates every physics frame
  while it moves. `on_damage(amount, stagger, killed)`, `set_bot(on)`, `reset(bot_on)`, `set_path(points)`,
  `telegraph() -> float`.
- Switching the bot off in any live state goes to `dummy` at once (a strike already landed stays landed). Switching it
  on while dead changes the flag only (it applies after the reset).

### 8.4 Steering: `ArenaPath` (`scenes/arena/arena_path.gd`, pure)

`class_name ArenaPath extends RefCounted`: `_init(bounds: Rect2, blockers: Array, radius: float, cell := 0.5)` builds a
grid (40 × 48 over the room) of cells free for a circle of `radius` (the beast's 0.6 + 0.1) against the blockers the
world passes in (`ArenaLayout.blockers()` format; ENEMY never references `ArenaLayout` directly); `find(from: Vector2,
to: Vector2) -> PackedVector2Array` (A* on 8 neighbours, then string-pulled with `clear_line`), a straight line when
`clear_line(from, to)`; `clear_line(a, b) -> bool`. Deterministic (fixed neighbour order and tie-break), ≤ 2 ms per query
on the test machine. A target inside a blocked cell resolves to the nearest free cell.

### 8.5 The actor: `HiveBeast` (`scenes/arena/hive_beast.tscn` + `.gd`, CharacterBody3D, layer 8, mask 1 | 4 | 2)

Floating motion mode at y = 0; capsule from the figure's metrics; owns its figure (passed in, §9), the `HiveAI`, an
`ArenaPath` built from `opts.blockers` and `opts.bounds`, the telegraph ring (a small unshaded annulus MeshInstance,
visible only during the wind-up and the strike), the seeded RNG. Contract in §12.3.

## 9. Swappable actors and the private pack (ROOM owns the loader; PLAYER and ENEMY own the default figures)

### 9.1 The figure contract (duck-typed `Node3D`)

Every player or enemy figure — `EggGunner`, `KitBeast`, any pack figure — provides exactly this; actors never reach
inside a figure.

```gdscript
const FIGURE_API := ["setup", "metrics", "clip_names", "play", "set_move", "set_aim", "set_weapon", "set_flash",
	"set_telegraph", "muzzle", "anchor", "apply_level"]
signal clip_event(kind: StringName)                  # &"shot" (a shot leaves / a blow lands), &"thud" (a fall lands)
func setup(opts: Dictionary) -> void                 # {"role": &"player" | &"enemy", "level": String, "team_colour": Color, "seed": int}
func metrics() -> Dictionary                         # {"height": float, "radius": float, "eye": float, "shoulder": float}
func clip_names() -> Dictionary                      # logical -> PackedStringArray of clips (§8.1 table; player: §6.6)
func play(logical: StringName, speed: float = 1.0) -> float   # starts it (one-shots return to the loop); returns its length, 0 if none
func set_move(speed: float, running: bool) -> void   # m/s along its facing: picks idle / walk / run and their playback rate
func set_aim(pitch: float) -> void                   # radians; no-op for enemies
func set_weapon(id: StringName) -> void              # &"none", &"gun", &"sword"; no-op for enemies
func set_flash(a: float) -> void                     # 0..1 hit flash
func set_telegraph(a: float) -> void                 # 0..1 wind-up tint; no-op for players
func muzzle() -> Node3D                              # shot origin (player); null for enemies
func anchor(name: StringName) -> Node3D              # &"head", &"chest", &"hand_r", &"hand_l"; null when missing
func apply_level(l: String) -> void                  # per-level look (§11.1)
```

Logical clips: `idle`, `walk`, `run`, `attack`, `hit`, `hit_heavy`, `die` (enemy); `idle`, `walk`, `run`, `fire`,
`reload`, `punch`, `swing`, `hit`, `die` (player). A missing optional clip makes `play` return 0 and the actor uses its
timer (the gameplay timing comes from `ArenaData`, never from clip lengths, so a pack cannot change the balance).

### 9.2 The loader: `ArenaActors` (`scenes/arena/arena_actors.gd`, ROOM)

```gdscript
class_name ArenaActors extends RefCounted
const PACK_MANIFEST := "res://packs/arena/pack.json"
const DEFAULT := {"player": "res://scenes/arena/egg_gunner.gd", "enemy": "res://scenes/arena/kit_beast.gd"}
static func resolve(role: String, manifest: String = PACK_MANIFEST) -> String     # the pack's path when valid, else DEFAULT[role]
static func make_figure(role: String, manifest: String = PACK_MANIFEST) -> Node3D  # .tscn -> instantiate(), .gd -> new(); validated
static func missing_api(fig: Object) -> PackedStringArray                         # names of FIGURE_API it lacks
static func enemy_name(manifest: String = PACK_MANIFEST) -> Dictionary           # {"th", "en"} from the pack, or {}
```

A figure that fails to load or lacks any method of `FIGURE_API` is freed and replaced by the default, with one
`push_warning` naming what was missing. `ArenaWorld` makes both figures and passes them in `setup(opts.figure)`.

### 9.3 The pack (absent from this repo)

`res://packs/arena/pack.json` — `{"format": 1, "id": "<pack id>", "player": "<path>", "enemy": "<path>",
"enemy_name": {"th": "...", "en": "..."}}` (all keys but `format` optional). Paths must lie inside the manifest's own
folder. `godot/.gitignore` gains `packs/` so private files can never be committed here. The private repo copies its pack
into `godot/packs/arena/` before its own export; it does not run this repo's data lint. Nothing in this repo names or
describes the owner's private figures.

Extended by `PACK_SPEC.md` (12 Nov): an optional `deck` key for the warship deck's figure, the reserved `army` key, the
public presets' `exclude_filter="packs/*"` and the primitive fixture pack `tests/fixtures/figure_pack/`.

## 10. Screens, flow and transitions (ROOM)

### 10.1 Flow

```
Main menu ─เล่นกับบอท─▶ Deck (hall, depth 2) ─[walk into the arena door, or E]─ fade ─▶ Arena screen (depth 3)
   corridor (walk mode) ─cross the shoot line─▶ arena (shoot mode) ─cross back─▶ corridor ─walk into the deck door─ fade ─▶ Deck
   (at ARENA_RETURN)        ‹ ล็อบบี้ or pause ▸ กลับล็อบบี้ ─ fade ─▶ Deck          pause ▸ ตั้งค่า ─▶ Settings (depth 4) ─back─▶ arena
```

The arena screen is entered fresh every time (beast full HP, bot off, counters 0, magazine full, walk mode at `SPAWN`).

### 10.2 Fades

- hi / mid: a black `%Fade` ColorRect tweened 0 → 1 in 0.25 s before the push / pop and 1 → 0 in 0.25 s after the new
  screen shows. lo / min: no tween (the deck's hint rule): black for one frame, switch, clear on the next frame.
- While fading: input disabled (`player.set_input_enabled(false)`, the hall avatar halted), `handle_back()` swallows.

### 10.3 Arena screen (`ui/screens/arena_screen.tscn` + `.gd`)

| Node | What |
| --- | --- |
| `ArenaWorld` | the 3D world child (instanced in the tscn) |
| `Safe/Layer/Hud` | PLAYER's `ArenaHud`, created at runtime with `load(ARENA_HUD).new()` |
| `%LobbyButton` | top left, "‹ ล็อบบี้": leave (fade → pop) |
| `%SettingsButton` | top right, "ตั้งค่า": push Settings (the screen pauses, §10.4) |
| `%UseButton` | bottom centre, like the deck: "{name} · กด E" / "{name} · แตะเพื่อใช้" for `switch` / `reset` |
| `%Toast` | top centre under the hint, 2 s, mouse ignore |
| `%PausePanel` | centred `PanelContainer`: "หยุดชั่วคราว", `%ResumeButton` "เล่นต่อ", `%PauseLobbyButton` "กลับล็อบบี้", `%PauseSettingsButton` "ตั้งค่า" |
| `%Fade` | §10.2 |

Back / Esc (`handle_back() -> bool`, always true in this screen): fading → swallow; pause panel open → close it (resume);
otherwise → release the mouse and open the pause panel (Android back does the same). Only "‹ ล็อบบี้", "กลับล็อบบี้" and
walking into the deck door leave. `interact` (E) → `world.use_station()`. The screen hides and disables the
`table_view` node like the hall (`_hide_table`), and the deck is hidden and disabled by the stack.

### 10.4 Pause, hide, focus

`world.set_paused(true)` freezes the player, the beast, the fx and the camera (process disabled on those nodes;
colliders stay) and releases the mouse; resume re-enables them (the mouse re-captures on the next click). When a pushed
screen (Settings) hides the arena: `world.set_active(false)` (hidden, disabled, camera released, mouse visible); on show:
`refresh()` re-reads `App.gfx`, `App.lang`, `App.touch` and the pause panel stays open. Focus loss on desktop opens the
pause panel in shoot mode.

## 11. Per graphics level, budgets and idle rules

### 11.1 `ArenaWorld.apply_level(l)` (also applies `TableView.LEVELS[l]` globals, exactly as `HallWorld.apply_level`)

| Level | Sides | Flames (flicker) | Beacon | Fx material | Sparks | Beast idle | Kit `per_vertex` | Egg bob | Numbers | Shake | Sign outlines |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| hi | 14 | 2 (yes) | spins (shader, while on) | additive | 8 | `idle` loop | false | yes | rise + fade tween | yes | yes |
| mid | 12 | 2 (yes) | spins (shader, while on) | additive | 5 | `idle` loop | false | yes | rise + fade tween | yes | yes |
| lo | 10 | 2 (no) | static colour | opaque | 3 | `idle` loop | true | no | still 0.6 s | no | no |
| min | 8 | 2 (no) | static colour | opaque | 0 (one impact quad) | still pose while a dummy / idle at home | true | no | still 0.6 s | no | no |

On lo and min no shader under `ArenaWorld` uses `TIME` (the kit's `figure.gdshader` has none; the flame and beacon
shaders are hi/mid only).

### 11.2 Budgets (asserted in `test_arena`)

Measured as `test_hall` does: the maximum of `RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME` /
`RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME` over 4 frames with low-processor mode off. Draw calls / primitives:

| View | hi | mid | lo | min |
| --- | --- | --- | --- | --- |
| **Arena overview**: player at (0, 0, −12.5) in shoot mode, yaw 0, pitch −0.1 (room, beast, board, switch, pillars in view), touch off, 1280 × 720 | ≤ 50 / 80k | ≤ 45 / 60k | ≤ 35 / 40k | **≤ 30 / 30k** |
| **Arena phone worst view**: 20:9 window (1600 × 720 logical), touch on, shooter hint showing, firing (tracer + flash), 4 damage numbers alive, the beast in its wind-up (ring + tint), a toast and the use button showing, standing at the switch's front ring looking across the room at the beast and the board | ≤ 70 / 80k | ≤ 60 / 60k | ≤ 45 / 40k | **≤ 40 / 30k** |
| **Corridor**: player at `SPAWN`, walk mode, yaw 0 (looking down the corridor into the room), touch on, 20:9 | ≤ 50 / 80k | ≤ 45 / 60k | ≤ 35 / 40k | ≤ 30 / 30k |
| **Deck, unchanged views** (overview, phone worst view of `SHIP_LOBBY_SPEC` §6 / §12) | deck targets 40 / 40 / 35 / 30 still hold; their draw calls may not rise (the door and its sign are out of those views); primitives rise by ≤ 800 (the stub in the Shell) |
| **Deck, the door view** (new): avatar at the arena front ring, camera yaw π, pitch −0.3, arm 6.5, desktop and the phone layout (20:9, touch, hint) | within the deck targets ≤ 40 / 40 / 35 / **30** |

Estimated arena overview on min: 2 static meshes + flames + switch head + beacon + rings + 6 labels (in view) + egg +
gauntlets + weapon + beast ≈ 16, plus the desktop HUD (lobby and settings buttons, bars and crosshair in one draw, ammo)
≈ 6: about 22 of 30. Draw-call savers if a level misses: the HUD's single `_draw`, labels without outlines on lo/min, the
2-instance gauntlet MultiMesh, no separate mesh per pillar.

### 11.3 Idle rules (min and everywhere)

- The deck: unchanged (nothing processes after 10 idle frames; `test_hall` still checks it).
- The arena, any level: after 10 idle frames with the bot **off**, the player still, no effect or number alive and no
  fade running, nothing under the arena screen processes (`_process` / `_physics_process` off on the player, camera,
  spring arm, beast, fx, HUD, touch, screen) and on **min** the beast's `AnimationPlayer` is not playing (a still pose).
  The same in the corridor in walk mode.
- With the bot on, the beast thinks at 10 Hz and moves every physics frame while it moves; at home and idle on min it
  holds a still pose as above.

## 12. Files, owners and contracts (three builders in parallel, never the same file)

### 12.1 Ground rules (as LOBBY_SPEC §0, restated where they differ)

1. Each builder edits only the files it owns below. A failing check in another builder's file is reported, not fixed.
2. **First steps**, each said aloud in the builder's notes with the time when done:
   - **R0 (ROOM, ≤ 10 min)**: `ui/i18n.gd` `FRAGMENTS` += `res://ui/i18n/arena.json`, `res://ui/i18n/arena_hud.json`,
     `res://ui/i18n/arena_data.json` (in that order, after `battle.json`); create `arena_hud.json` and `arena_data.json`
     as `{}` (from then on PLAYER and ENEMY own them) and `arena.json`; update `test_i18n_fragments.gd`'s expected list
     (reason: three arena fragments added on purpose); refresh the import cache. Check: `grep -q arena_data godot/ui/i18n.gd`.
   - **E0 (ENEMY, ≤ 20 min, right after R0)**: `ui/arena/arena_data.gd` and `ui/arena/arena_combat.gd` with the exact
     API of §6.1–§6.2, their four labels in `arena_data.json`, `tests/unit/test_arena_combat.gd`; refresh the import
     cache. Check: `test -f godot/ui/arena/arena_combat.gd`. Until then PLAYER builds the camera, controller and HUD.
3. **Cross-references**: another builder's scenes and scripts only through `load(PATH)` at use time with the paths of
   §12.2 (never `preload`, never their `class_name`), **except** `ArenaData` and `ArenaCombat`, which everyone may use by
   class name once E0 is in. The finished deck classes (`HallLayout`, `HallBuilder`, `HallAvatar`, `HallCamera`,
   `TouchStick`, `CandleStyle`, `Rings`, `PropsLayer`, `KitLibrary`) may be used by anyone; only ROOM edits `HallLayout`,
   `HallBuilder`, `hall_screen.*`.
4. No commits, pushes or PR changes; leave everything in the working tree. Do not touch the old app, `core/` (apart from
   ROOM's `APP_VER` line), `data/**` (a new file there would change `DATA_HASH`), `assets/**`, `scenes/probe/**`,
   `table/**`, the deck files not listed for ROOM, `ui/widgets/touch_stick.gd`, or this spec.
5. Godot `~/godot-bin/godot` (4.7.1). Four shared CPUs: never `pkill` / `killall` or kill by name or pattern, only PIDs
   you started; `nice -n 10` for render and full runs. Imports under the shared lock:
   `flock <scratchpad>/godot-arena/import.lock timeout 600 ~/godot-bin/godot --headless --path godot --import`.
   Test output: `TEST_OUT=<scratchpad>/godot-arena/out-<builder>`; scratch scenes and scripts only under
   `<scratchpad>/godot-arena/`, never in the repo. Tests never write the machine's `user://settings.cfg`.
6. AGENTS hard rules: rule 1 (§0), Thai first + English (§1), min stays fast (§11), surgical edits (no re-formatting or
   re-ordering of existing files), short Thai code comments like the surrounding code, never delete / skip / loosen a
   test (a changed expectation says why in a comment and in the final report).

### 12.2 Ownership

| Builder | Owns (new unless marked edit) |
| --- | --- |
| **ROOM** (deck doorway, corridor, arena world, props, transitions, screen, release line) | edit `scenes/hall/hall_layout.gd` (`IDS` + `arena`, `STATIONS.arena`, `ARENA_DOOR`, `ARENA_RETURN`, `ARENA_AUTO`, `ARENA_STUB_LIGHT`, one `COOL_LIGHTS` entry, `in_arena_doorway`), edit `scenes/hall/hall_builder.gd` (front wall cut, `_arena_door`: frame, reveals, stub, pressure door), edit `ui/screens/hall_screen.gd` + `.tscn` (`NAMES` / `SIGNS.arena`, `enter_arena`, return, `%Fade`), edit `ui/i18n/hall.json`, edit `ui/i18n.gd` (`FRAGMENTS` only); `scenes/arena/arena_layout.gd`, `arena_builder.gd`, `arena_world.tscn` + `.gd`, `arena_state.gd`, `arena_actors.gd`, `beacon.gdshader`; `ui/screens/arena_screen.tscn` + `.gd`; `ui/i18n/arena.json`; edit `godot/.gitignore` (`packs/`); edit `core/version.gd` (the `APP_VER` line only); tests: new `tests/unit/test_arena_layout.gd`, `test_arena_state.gd`, `test_arena_actors.gd` (+ `tests/unit/fixtures/arena_pack/pack.json`, `fake_figure.gd`), `test_arena_text.gd`, `tests/flow/test_arena_flow.gd`, `tests/render/test_arena.gd`; edit `tests/unit/test_hall_layout.gd`, `test_menu_text.gd`, `test_i18n_fragments.gd`, `tests/flow/test_hall_reach.gd`, `tests/flow/test_lobby_flow.gd` (its `RECTS` table only), `tests/render/test_hall.gd` |
| **PLAYER** (shooter controller, cameras, input, rifle / punch / saw sword, effects, HUD, touch) | `scenes/arena/arena_player.tscn` + `arena_player.gd` (`ArenaPlayer`), `arena_camera.gd` (`ArenaCamera`), `arena_weapons.gd` (`ArenaWeapons`: the weapon state machine over `ArenaCombat`, pure enough to unit-test with fake time), `arena_fx.gd` (`ArenaFx`), `egg_gunner.gd` (`EggGunner`, the default player figure); `ui/widgets/arena_hud.gd` (`ArenaHud`), `ui/widgets/arena_touch.gd` (`ArenaTouch`); `ui/i18n/arena_hud.json` (after R0); edit `project.godot` (`[input]`: `fire`, `melee`, `reload`, `weapon_1`, `weapon_2`, written the way the editor writes them); tests: edit `tests/unit/test_input_map.gd` (+ five actions, mouse buttons included; reason: the shooter controls), new `tests/unit/test_arena_weapons.gd`, `test_arena_hud_text.gd`, `tests/render/test_arena_hud.gd` |
| **ENEMY** (hive beast actor, AI, steering, combat math, data table) | `ui/arena/arena_data.gd` (`ArenaData`), `ui/arena/arena_combat.gd` (`ArenaCombat`), `ui/i18n/arena_data.json` (after R0); `scenes/arena/hive_beast.tscn` + `hive_beast.gd` (`HiveBeast`), `hive_ai.gd` (`HiveAI`), `arena_path.gd` (`ArenaPath`), `kit_beast.gd` (`KitBeast`, the default enemy figure and the beast-egg fallback); tests: new `tests/unit/test_arena_combat.gd`, `test_hive_ai.gd`, `test_arena_path.gd`, `tests/render/test_hive_beast.gd` |
| **Integration** (whoever runs the workflow, after all three) | the full run, `docs/GODOT.md` §1.3 rows, `godot/README.md`, `godot/docs/STATUS.md`, one pointer line in `SHIP_LOBBY_SPEC.md` §2.2, §17 of this file, the Thai note (§15) |

**Scene and script paths** (constants in the callers; `load(PATH)` at use time):

| Constant | Path | Owner |
| --- | --- | --- |
| `ARENA_SCREEN` | `res://ui/screens/arena_screen.tscn` | ROOM |
| `PLAYER_SCENE` | `res://scenes/arena/arena_player.tscn` | PLAYER |
| `BEAST_SCENE` | `res://scenes/arena/hive_beast.tscn` | ENEMY |
| `ARENA_HUD` | `res://ui/widgets/arena_hud.gd` | PLAYER |
| `DEFAULT.player` / `DEFAULT.enemy` | `res://scenes/arena/egg_gunner.gd` / `res://scenes/arena/kit_beast.gd` | PLAYER / ENEMY |
| `PACK_MANIFEST` | `res://packs/arena/pack.json` (absent here) | private |

### 12.3 Contracts (exact; duck-typed; signals and methods by these names)

**`ArenaWorld`** (`scenes/arena/arena_world.gd`, Node3D, group `gfx_level`; ROOM)

```gdscript
signal mode_changed(mode: StringName)            # &"walk" / &"shoot"
signal station_changed(id: String)               # "", "switch", "reset"
signal stats_changed(stats: Dictionary)          # {"bot_on", "hp", "hp_max", "hits", "damage", "state": StringName, "dead"}
signal bot_toggled(on: bool, how: StringName)    # &"use" / &"shot" / &"melee"
signal reset_done()
signal leave_requested()                         # walked back into the deck door (walk mode, once per arming)
var player: Node3D                               # the ArenaPlayer
var enemy: Node3D                                # the HiveBeast
var level := ""
func apply_level(l: String) -> void
func set_active(on: bool) -> void
func set_paused(on: bool) -> void
func set_sign_text(id: String, text: String) -> void   # "switch", "reset", "door_back", "door_arena", "board_title", "board_body"
func station() -> String
func use_station() -> void                       # toggle or reset, per the station in reach
func toggle_bot(how: StringName) -> bool         # false inside the cooldown
func reset_range() -> void
func stats() -> Dictionary
func mode() -> StringName
func place_player(p: Vector3, face: float, cam_yaw: float) -> void
func hit_target(collider: Object) -> Dictionary  # {"node": Node (has take_hit), "id": &"beast" | &"switch"} or {}
func melee_targets() -> Array[Dictionary]        # [{"node", "id", "pos": Vector2, "r": float}]
func take_hit(hit: Dictionary) -> Dictionary     # the switch's hits (id switch): toggles through toggle_bot
func counts() -> Dictionary                      # {"level", "static_meshes", "static_tris", "flames", "signs", "blockers", "pillars", "enemy_kit", "fx_additive": bool, "beacon_spin": bool}
```

**`ArenaPlayer`** (`scenes/arena/arena_player.gd`, CharacterBody3D, layer 2, mask 1 | 4 | 8; PLAYER)

```gdscript
signal moved(pos: Vector3)
signal mode_changed(mode: StringName)
signal weapon_changed(id: StringName)            # &"none", &"gun", &"sword"
signal ammo_changed(in_mag: int, mag_size: int)
signal reload_changed(on: bool, seconds: float)
signal hp_changed(hp: int, hp_max: int)
signal hit_landed(info: Dictionary)              # {"point", "amount", "target": &"beast" | &"switch", "kind", "killed"}
signal hurt(info: Dictionary)                    # {"amount", "from": Vector3}
signal downed()
signal revived()
const RADIUS := 0.35
func setup(world: Node3D, opts: Dictionary) -> void   # {"level", "team_colour", "touch": bool, "figure": Node3D}
func apply_level(l: String) -> void
func camera() -> Camera3D
func camera_rig() -> Node3D                      # the ArenaCamera (yaw, pitch, forward_flat(), right_flat(), set_view())
func set_mode(m: StringName) -> void
func mode() -> StringName
func set_stick(v: Vector2) -> void
func aim_drag(rel: Vector2) -> void              # touch, logical px
func press(action: StringName, on: bool) -> void # &"fire", &"melee", &"reload", &"weapon"
func set_input_enabled(on: bool) -> void
func set_paused(on: bool) -> void
func place(p: Vector3, face: float, cam_yaw: float) -> void
func take_hit(hit: Dictionary) -> Dictionary     # {"applied", "hp", "killed" (= downed)}
func heal_full() -> void
func is_alive() -> bool
func hp() -> int
func weapon() -> StringName
func ammo() -> Vector2i                          # (in_mag, mag_size)
func aim_ray() -> Dictionary                     # {"from", "to", "point", "collider"}
func aim_active() -> bool                        # shoot mode, not paused (mouse look accepted)
func figure() -> Node3D
func input_vector() -> Vector2
```

**`HiveBeast`** (`scenes/arena/hive_beast.gd`, CharacterBody3D, layer 8, mask 1 | 4 | 2; ENEMY)

```gdscript
signal hp_changed(hp: int, hp_max: int)
signal state_changed(state: StringName)          # §8.3 names
signal damaged(info: Dictionary)                 # {"amount", "point", "kind", "hp", "killed"}
signal died()
signal struck(info: Dictionary)                  # {"hit": bool, "amount": int}
func setup(world: Node3D, opts: Dictionary) -> void   # {"level", "seed", "spawn": Vector3, "face": float, "bounds": Rect2, "blockers": Array, "figure": Node3D}
func apply_level(l: String) -> void
func set_target(t: Node3D) -> void               # needs global_position, is_alive(), take_hit(), RADIUS; the world says whether it is in the room
func set_target_in_room(on: bool) -> void
func set_bot(on: bool) -> void
func bot_on() -> bool
func take_hit(hit: Dictionary) -> Dictionary
func reset_to(p: Vector3, face: float) -> void
func hp() -> int
func hp_max() -> int
func state() -> StringName
func is_alive() -> bool
func radius() -> float
func telegraph() -> float
func kit_key() -> String                         # "warrior", "egg" or the pack id
func figure() -> Node3D
func set_paused(on: bool) -> void
```

**`ArenaHud`** (`ui/widgets/arena_hud.gd`, Control; PLAYER): `bind(world: Node3D)` (connects to the world, its player
and enemy), `refresh(touch: bool)` (texts in the current language, shows / hides `Touch`), `set_paused(on)`,
`hint_done() -> bool`, `numbers_alive() -> int`, child names `Ammo`, `Hint`, `Hurt`, `Downed`, `Touch` (with `Stick`,
`AimPad`, `FireButton`, `MeleeButton`, `ReloadButton`, `WeaponButton`), and `drawn_rects() -> Dictionary` with the
rects of `Crosshair`, `EnemyBar`, `PlayerBar` for the layout tests.

## 13. Tests

Rules of LOBBY_SPEC §7.1 (sizes 640 × 360, 1280 × 720, 1280 × 576; no overflow, no overlap, buttons ≥ 44 px; no Thai
in English mode except `LangButton`, Label3D included; whole-key test per builder) apply to every new suite.

### 13.1 Changed expectations (behaviour changed on purpose; the reason goes in a comment in the test too)

| Test | Today | Becomes | Why |
| --- | --- | --- | --- |
| `test_hall_layout.test_stations_are_the_seven_of_the_spec` | seven ids | renamed `…_the_eight_of_the_spec`, eight with `arena` | the arena door station |
| `test_hall_layout.test_flood_fill_reaches_every_station` | count 7 | 8 | as above |
| `test_hall_layout.test_station_at_samples` | — | + (−9.8, 6.95) → `arena`, + (−9.8, 5.2) → "" | door and return spot |
| `test_hall_layout.test_blockers_and_flames` | tags without `arena` | + `arena` | the door box |
| `test_hall_reach` | 7 stations | 8; at the arena door it stops on the prompt and asserts the depth stays 2 (no auto entry from the trigger's edge) | new station |
| `test_hall` run header and `_check_texts` | 9 signs | 10 (8 stations + title + name tag) | the door sign |
| `test_hall._check_stations` | online / adventure / vault panels | + `arena`: E pushes the arena screen (depth 3); its `%LobbyButton` returns to the hall at `ARENA_RETURN`, hall active, camera current | new station |
| `test_hall` `VOID_SPOTS` | 4 spots | + (−9.8, 0, 5.2) | look into the doorway and stub from close |
| `test_lobby_flow` `RECTS` | no arena | + `"arena": [-9.8, 7.9, 1.0, 0.2]` | its hand-copied blocker table follows the deck |
| `test_menu_text` (version) | "0.3" | "0.4" | APP_VER bump |
| `test_i18n_fragments` | three fragments | six, in the §12.1 order | arena fragments |
| `test_input_map` | seven actions | twelve (+ `fire`, `melee`, `reload`, `weapon_1`, `weapon_2`; mouse buttons checked as `InputEventMouseButton`) | shooter controls |

Unchanged and must stay green: every other unit suite, `test_lobby_flow` (W to the war table and the bot game),
`test_settings_flow`, `test_budgets`, `test_main_screens`, `test_menu_screens`, `test_army_screen`,
`test_battle_screen`, `test_field_look`, `test_lineup`, `test_anim_footslide`, the render probe, the data lint, and in
`test_hall` the deck's measured views and their targets, the camera corners and walks, the min idle rule.

### 13.2 Unit (headless; they also run in the exported game)

- **ROOM** `test_arena_layout.gd`: interior, corridor and arch dimensions; pillars, stands and stations inside the room,
  not overlapping, the lane |x| < 2.4 clear from the shoot line to the pad; a flood fill (0.25 m grid, radius 0.35) from
  `SPAWN` reaches every station trigger, the pad's edge and all four quadrants; line of sight from (0, 1.5, −11.3) to the
  switch plate and to the board's four corners; `mode_for` hysteresis (−11.2 stays walk, −11.4 → shoot, −11.0 stays
  shoot, −10.7 → walk); `leaving` only in walk mode at z ≥ −0.95, and `SPAWN` is 1.25 m from it; `DOOR_BACK` stops the
  avatar at −0.65 (≥ `LEAVE_Z`); every sign above its blocker; every light inside the room or corridor with k > 0;
  `blockers()` format matches `HallLayout`'s and every entry has a layer.
- **ROOM** `test_hall_layout.gd` additions: the opening lies inside the front wall and clears the exit door by ≥ 7 m;
  rise > half width (pointed); `ARENA_RETURN` is free (radius 0.35) and in no trigger, and its camera arm along yaw 0
  (`room_clear`) is ≥ 2.4 m; `in_arena_doorway` is true only inside the `arena` trigger, reachable (the avatar's
  furthest z at the door, 7.35, ≥ 7.23), false at the corner test's start (−10.8, 6.9) and along the front-wall camera
  walk (z 6.6); the arena footprint's front − `CAM_PAD` ≥ `HALF.y` − `HallCamera.WALL_PAD` (same as the exit door);
  `ARENA_STUB_LIGHT` is not in `COOL_LIGHTS`.
- **ROOM** `test_arena_state.gd`: toggle cooldown (a burst of 8 shots in 1 s toggles once; a second toggle after 1.0 s);
  `record_hit` sums; `reset` zeroes counters and keeps the switch; `stats` shape.
- **ROOM** `test_arena_actors.gd`: no manifest → defaults; the fixture pack (`tests/unit/fixtures/arena_pack/`) swaps
  the enemy figure for `fake_figure.gd` and returns its `enemy_name`; a manifest whose path leaves its folder, a missing
  file, or a figure lacking `set_flash` → default + warning; `missing_api` lists exactly the absent names; both default
  figures pass `missing_api` (instanced headless).
- **ROOM** `test_arena_text.gd`: whole keys of `arena_screen.gd/.tscn` and the hall additions; every board template's
  English has the same `{placeholders}`; no Thai under `scenes/arena/`.
- **PLAYER** `test_arena_weapons.gd` (fake time): rifle 8 shots in 1.0 s held (±1), 30 then empty, auto reload on the
  next press, reload 1.6 s, R mid-magazine, switch cancels reload, holster + draw 0.35 s with no shot; punch cooldown
  0.55 s, its hit at 0.12 s; sword cooldown 0.8 s, hit at 0.18 s; melee cone through `ArenaCombat`; shoulder camera
  math: the camera point is 0.55 m right of the pivot line, the aim ray passes through the viewport centre.
- **PLAYER** `test_arena_hud_text.gd`: whole keys of `arena_hud.gd` and `arena_touch.gd`; both hints and every button
  have English without Thai.
- **PLAYER** `test_input_map.gd`: §13.1 row.
- **ENEMY** `test_arena_combat.gd`: every weapon entry has its fields with positive numbers; `fire_interval("gun")` =
  0.125; `apply` clamps and kills exactly at 0; `in_cone` inside / outside the angle and reach, target radius counted,
  overlap always counts; `reaction` (12 none, 25 + stagger flinch, 45 heavy); `knockback` is horizontal; `decay`
  halves at ln 2 / friction; `number_style` threshold 25; `yaw_to` matches `HallAvatar`'s `atan2(x, z)`; labels are
  I18n keys with English; TTK numbers of §6.1 (25 rifle hits, 12 punches, 7 swings).
- **ENEMY** `test_hive_ai.gd`: off stays `dummy` and never moves over 10 s; on + target in room → `chase`; in range and
  facing → `windup` → `strike` exactly once at 0.72 s with the hit only inside reach and cone (a target that stepped to
  2.7 m or behind it at the event is missed) → `recover` 0.7 s → `chase`; stagger during wind-up cancels the strike;
  bullets never flinch; HP 0 from every state → `dead`, which ignores everything but `reset`; off during `chase` → `dummy`
  at once; target in the corridor → `idle` walking home; grace 3 s after the player is downed; the same seed gives the
  same attack and death variants.
- **ENEMY** `test_arena_path.gd`: paths around each pillar never come closer than the radius to a blocker; a clear line
  returns two points; unreachable or blocked targets resolve to the nearest free cell; the same query gives the same
  path; 200 random queries under 2 ms each on average.

### 13.3 Flow (headless, quick run): `tests/flow/test_arena_flow.gd` (ROOM; needs all three parts)

Min level, Thai, egg figures, touch off, a test settings file. Input through `Input.parse_input_event` (keys with
`keycode` and `physical_keycode`, mouse buttons, relative mouse motion computed from `LOOK_SPEED`):

1. Main menu → เล่นกับบอท → the deck (depth 2).
2. Stick-walk from the spawn to the arena door along a free grid path (as `test_hall_reach`): the prompt names
   อารีน่าทดสอบอาวุธ; keep walking into the doorway → the arena screen is current (depth 3), mode `walk`, the deck hidden
   and disabled, the arena camera current, no Tween created on min.
3. Hold W down the corridor: at z < −11.3 mode `shoot`, weapon `gun`, ammo (30, 30), `aim_active()`.
4. Aim at the beast's chest and hold the left button: shots land; after 30 the magazine reloads on the next press (and
   R works); the beast dies: `state` `dead`, 25 hits, damage 300, the board body shows "ล้มแล้ว · กดรีเซ็ต", numbers
   appeared, no shot hit a pillar.
5. Walk to the reset front, E: the beast is alive with 300 HP on the pad, counters 0, toast "รีเซ็ตแล้ว".
6. Aim at the switch plate, a 0.5 s burst: the bot turns on exactly once (toast, board "บอท: เปิด", beacon lit).
7. Stand still: the beast reaches the player within 8 s, stays in `windup` ≥ 0.5 s before the player's HP drops by 18,
   then 0.4 s of invulnerability.
8. F while it is in range: a punch lands, the beast slides ≥ 0.25 m away within 0.4 s (3.0 m/s ÷ friction 8 = 0.375 m
   expected) and enters `hit`.
9. Weapon 2, left button: a sword swing lands for 45.
10. Walk to the switch, E: the bot is off; after its current action the beast moves < 0.05 m over 1 s.
11. Back across the shoot line: mode `walk`, weapon `none`, mouse visible; up the corridor into the deck door → the deck
    (depth 2), the avatar at `ARENA_RETURN`, station "", deck camera current, egg opaque, the arena screen freed.
12. Enter the arena again: fresh state (bot off, 300 HP, counters 0, full magazine). "‹ ล็อบบี้" returns. Esc in the deck →
    the main menu. This machine's settings untouched.

### 13.4 Render (xvfb, `nice -n 10`)

- **ROOM** `test_arena.gd`: entry from the deck (E at the door) and timing print; per level `counts()` and the §11.1
  table (flames, flicker, beacon spin, fx additive, sides), no `TIME` shader under the world on lo/min (scan shader code,
  not just the class), the three budget views of §11.2 printed and asserted for all four levels; **no holes into the
  void** (magenta background): corridor 3 spots and arena 6 spots × 4 yaws × 2 pitches in both camera modes on mid, the
  widest set on min, 640 × 360, zero pixels; the camera never inside a solid (`ArenaLayout.inside_solid` with 0.1 m)
  during corridor walks with orbits, the arch passage, sweeps beside each pillar and in the four corners in shoot mode;
  board and signs in Thai and English (English has no Thai); the pause panel, toast and use button at the three sizes
  pass the layout checks; fade: hi uses a Tween and ends clear, min creates none; the min idle rule of §11.3 in the
  corridor and in the arena; PNGs `arena_<level>.png` (overview), `arena_corridor.png`, `arena_board_th.png`,
  `arena_board_en.png`, `arena_pause.png`, `arena_phone_worst_<level>.png`.
- **ROOM** `test_hall.gd` additions: the door view budget (desktop and phone layout) within the deck targets on all four
  levels; a camera walk "along the front wall past the arena door, camera between the avatar and the wall" (start
  (−6.5, 0, 6.6), stick (−0.8, 0), yaw 0): arm change ≤ 0.5 m a frame, never in a blocker, passes within 0.5 m of the
  `arena` footprint, no auto entry; walking into the doorway on hi fades and pushes the arena; PNGs `hall_arena_door.png`
  (from the return spot, yaw π) and `hall_arena_door_min.png`.
- **PLAYER** `test_arena_hud.gd`: the HUD in walk and shoot mode at the three sizes, Thai and English: no overflow, no
  overlap with the screen's nodes, buttons ≥ 44 px, every touch button centre within 290 px of the bottom-right safe
  corner at 1280 and 1600 widths and clear of `%UseButton`; the crosshair rect centred on the viewport (±1 px); the ammo
  line and weapon button text follow switches and reloads; the shooter hint per input mode; mouse captured on entering
  shoot mode and visible after Esc, in walk mode and after leaving; touch: the stick strafes, an aim-pad drag of 100 px
  turns the camera 0.6 rad, holding `FireButton` fires 8 ± 1 shots in 1 s, a drag starting on it also aims, `MeleeButton`
  punches, `WeaponButton` switches, `ReloadButton` reloads; the shoulder camera sits right of the egg and never inside a
  solid in orbit sweeps by walls and pillars, the egg fades when squeezed; PNGs `arena_hud_th.png`, `arena_hud_en.png`,
  `arena_touch.png`, `arena_touch_20x9.png`, `arena_sword.png`.
- **ENEMY** `test_hive_beast.gd`: the `warrior` kit loads skinned with 23 bones and its `motion_scale` 1.3; every logical
  clip resolves to existing clips and moves bones away from the rest pose; no bone turns more than 25° between two
  frames across a clip change (the hold easing); while chasing at 3.7 m/s the planted-foot slide stays ≤ 25 mm (the
  footslide measure on `run`); the telegraph ring shows only in wind-up / strike and the wind-up lasts ≥ 0.5 s before the
  `shot` event; a hit flashes for 0.08 s; per level `per_vertex` and the min still pose (its `AnimationPlayer` not playing
  after 10 frames as a dummy); with `opts` forcing a missing kit the beast egg stands in with the same API; PNGs
  `hive_beast_clips.png` (contact sheet: idle, walk, run, attack wind-up / blow, hit, hit_heavy, die),
  `hive_beast_<level>.png`, `hive_beast_fallback.png`.

### 13.5 How to run, and the review before hand-off

```bash
G=~/godot-bin/godot; T=<scratchpad>/godot-arena/out-<builder>
flock <scratchpad>/godot-arena/import.lock timeout 600 $G --headless --path godot --import   # after new class_name scripts / shaders
timeout 600 $G --headless --path godot -s tests/run_tests.gd -- test_arena                    # unit suites by name
TEST_OUT=$T timeout 600 $G --headless --path godot --audio-driver Dummy -s tests/flow/test_arena_flow.gd
TEST_OUT=$T timeout 900 nice -n 10 xvfb-run -a -s "-screen 0 1280x720x24" $G --path godot --rendering-driver opengl3 \
  --resolution 1280x720 --audio-driver Dummy -s tests/render/test_arena.gd
python3 godot/tools/validate_data.py
TEST_OUT=$T nice -n 10 bash godot/tests/run.sh full        # once, at the end, after all three builders are done
```

Review: every PNG at full size (the arena reads as our gothic warship's test range; the beast is recognisable and
menacing, its wind-up visible; the rifle and saw sword are clearly ours with no third-party marks; Thai and English
readable; nothing clips through the egg); the data lint; the deck's measured numbers unchanged within noise.

## 14. What the owner will see (ใหม่ 0.4)

1. On the deck, a new pointed doorway in the front-left corner, "อารีน่าทดสอบอาวุธ", with an amber-lit corridor behind it.
2. Walk in (or press E): a short fade, a 10 m corridor, and into the arena: the egg draws its rifle and the camera goes
   over the shoulder with a crosshair.
3. Shoot, punch, switch to the saw sword; damage numbers, the beast's health bar, the board on the far wall.
4. Shoot (or press E at) the bot switch: the hive beast hunts him, rears up before each claw, can be dodged, punched back
   and staggered with the sword; switch it off again or press reset.
5. Walk back out to the deck. Settings (graphics levels, language, touch controls) work in the arena too.

## 15. Release (integration step)

- `APP_VER` "ใหม่ 0.3" → **"ใหม่ 0.4"** (ROOM edits the line; `test_menu_text` expects "0.4"). User-visible change, no rules
  change: `RULES_V`, `DATA_HASH`, `PROTO` untouched.
- Godot-only change: no `battle-table.html` / `board.html` edit, so **no candlelight-server re-embed PR**; merge order is
  PR #27 alone.
- Thai note `web/สิ่งที่เปลี่ยน-13พ.ย.69-รุ่นใหม่0.4-อารีน่าทดสอบอาวุธ.md` (the date the round finishes; already 13 Nov in
  Bangkok), the structure of the 0.3 note:
  1. `# สิ่งที่เปลี่ยน 13 พ.ย. 69 — แอปใหม่ รุ่นใหม่ 0.4 อารีน่าทดสอบอาวุธ` and one paragraph with the owner's request in
     plain words (with the neutral enemy name, never the franchise word);
  2. `## มินิทำอะไรได้แล้วในรุ่นนี้`: the door and corridor, the switch to the shooter, the controls (keyboard and phone),
     rifle / punch / saw sword, the hive beast and how it attacks, the switch, reset and board, walking back; that the
     player figure and the enemy can be swapped later for his own models through a private pack, without code changes;
  3. `## วิธีลอง`: open the app → เล่นกับบอท → front-left door → … ; try ต่ำสุด in Settings (no flicker, no spinning lamp,
     weak phones stay fast);
  4. `## ยังไม่มีในรุ่นนี้` (§16) and questions for him: the beast's toughness and speed, whether the reset should also turn
     the bot off, button positions on his phone, which model to use for the beast if `warrior` is not the one;
  5. `## ทดสอบแล้ว`: unit / flow / render numbers of the full run, the budgets per level (arena and deck), "ไม่มีช่องโหว่มองทะลุ";
  6. `## ลำดับการรวม`: godot-only, PR 27 only, no server PR.
- Docs: `docs/GODOT.md` §1.3 title "(… APP_VER ใหม่ 0.4; the arena: `godot/docs/ARENA_SPEC.md`)" and rows for every new
  file of §12.2 with search anchors; `godot/README.md` row for `scenes/arena/`; `godot/docs/STATUS.md` entry
  "13 Nov: weapons arena (ใหม่ 0.4)" with the test numbers; `SHIP_LOBBY_SPEC.md` §2.2 one line: "0.4: station `arena`
  (the arena door, front wall left) — see `ARENA_SPEC.md` §2."

## 16. Out of scope now

Sound and music; more enemies, waves, scores or a timer; aim assist, gamepads, hit zones (head shots); ragdolls and
runtime IK (the hold's leg IK); online play in the arena; saving anything; the reward system (the deck's treasure
chest); the owner's private figures themselves (only the swap point is built); a camera that tilts up to the deck's vault.

## 17. As built (filled at integration)

Integration (13 Nov) walked the whole path (boot → menu → deck → corridor → arena → shoot, punch, saw sword → bot switch →
the beast chases and claws → kill → reset → walk out → deck → Esc). A three-lens review (game feel and rules, phones and
performance, correctness and tests) followed; every must-fix and should-fix was fixed with a test, plus the clearly-right
suggestions. Where the build now differs from the sections above:

| Spec | As built | Why |
| --- | --- | --- |
| §4.1 `SPAWN` (0, 0, −2.2), pitch −0.35 | `SPAWN` (0, 0, −3.6); the spawn view uses `SPAWN_PITCH` −0.25 (`ArenaWorld._ready` sets it after placing the player) | at −2.2 the deck door cut the walk arm to 1.6 m and the egg filled the screen (now ≈ 3.2 m); at −0.35 the arena door's sign sat just above the view (review) |
| §5.2 "an empty magazine reloads by itself on the next fire press" | it reloads by itself as soon as it runs dry with fire still held; an empty magazine whose reload was cancelled (weapon switch) still reloads on the next press | with fire held (always on a phone) the silent gun felt jammed (review); `test_arena_weapons` and the flow test changed on purpose |
| §5.2 "look works whenever the mode is shoot and not paused, captured or not" | mouse look only while the mouse is captured (`ArenaPlayer._captured`, which headless runs set too), reading `InputEventMouseMotion.screen_relative`; touch aim keeps canvas units (`aim_drag`) | after resume the still-free cursor spun the aim; with `canvas_items` stretch, `relative` made a big window aim 1.5–3× slower (review) |
| §5.3 `ReloadButton` (−218, −198) | (−206, −190) | the spec's own spot was 294 px from the corner, over its 290 px rule (builder) |
| §5.3 buttons as round `Button` StyleBoxes; texts "ยิง", the other weapon's name (auto-fit) | stick and the four buttons drawn by `ArenaTouch._draw` from a 2-sprite circle atlas (one draw) plus one draw of labels; the real Buttons and the `TouchStick` stay for input, layout and `.text` with `modulate` alpha 0; Fire reads "ฟัน" / "Swing" while the saw sword is in hand (new key in `arena_hud.json`); a label that would shrink below 16 px splits into two lines ("Saw / Sword" at 20 px); the stick knob follows the finger inside the dead zone | the StyleBox buttons cost 13 draw calls in the phone worst view (67 on min against 40); the label review items |
| §5.4 pivot +1.55 m, 0.55 m right, arm 2.6 m, FOV 62 | +1.8 m, 0.9 m right, arm 3.0 m, FOV 65 | the 0.86 m wide egg sat over the crosshair and hid the beast at melee range; the egg now stands in the lower-left third with the rifle beside it |
| §5.4 shake on melee hits only | plus a kick per rifle shot (1.2 cm, 0.05 s), hi/mid only | the rifle felt weightless |
| §5.4 settle rule | the arm counts as settled within 2 cm (was 1 mm) | an arm resting on a wall or door jitters about 1 cm and never stopped processing, which broke the min idle rule |
| §5.5 `Hurt` (ColorRect) | a plain Control whose four edges are `draw_primitive` quads (one draw) | the polygons cost 4 draws plus a transparent full-screen rect; the phone worst view now measures the hurt edge too (review) |
| §5.5 crosshair | 1 px dark outline under the bars (same batch); the red tint is re-checked on every shot (the aim ray is cast anyway) and, event-driven, when the beast moves, changes state, dies or the range resets (`ArenaPlayer.refresh_aim`, `HiveBeast.moved`) | contrast over the pale beast while it flashes; the tint stayed red over a fallen beast and did not turn red when the beast walked into a still crosshair (review) |
| §5.5 numbers at the hit point | consecutive numbers fan out over five screen offsets (≥ 52 px apart horizontally or ≥ 34 px vertically); rifle hits on the same target within 0.3 s merge into the newest number, which keeps the rifle's white style whatever the total | "12 12" read as "12.12" and full-auto stacked into a blob (review) |
| §5.5 one `_draw()` | one `_draw()` grouped by texture: all rects (crosshair, bars, hit X as rotated rects), then text outlines, then text; damage numbers at one font size scaled by a transform | the HUD went from 28 to about 7 draws |
| §6.1 `BEAST` | + `"strike_at": 0.72` (the claw clip's `shot` event 0.433 s ÷ `attack_clip_speed` 0.6), + `"poise": 1.2` | the AI times the blow from the data table, not the clip; poise below |
| §6.5 "a flinch during the wind-up cancels the strike"; a punch flinches 0.35 s, a sword swing 0.8 s | still true, except with the bot on during a flinch and for `poise` 1.2 s after it: hits then do damage, knockback and flash but do not flinch it again (a dummy, bot off, flinches on every punch) | punches every 0.67 s or a held saw sword (a swing every 0.8 s against a 0.8 s heavy flinch) kept it flinching for ever, so it never clawed back (review) |
| §6.5 "a white flash for 0.08 s on every hit" | rifle hits flash at 45 %, punch and sword at full, every flash fades out over its 0.08 s | at 8 shots/s the full flash kept the beast white about 64 % of the time |
| §6.6 gauntlets at (±0.42, 1.0, 0.18) | the right grip raised to (−0.44, 1.24, 0.18) | the rifle reads from the shoulder camera |
| §7 "refused within 1.0 s of the last toggle, so a burst toggles once" | E keeps that rule; shots and melee on the plate count in bursts (hits less than a second apart): a burst toggles once, at its first hit past the toggle cooldown, and never again (`ArenaState.plate_hit`) | a burst of 1 s or more turned the bot on and then off again, and a held saw sword toggled it every swing (review) |
| §7 sign `switch` at (6.5, 2.95, −13.5), centred | the same point, bottom-aligned: extra lines grow upwards | the wrapped English sign and the Thai touch sign covered the bot's beacon (review) |
| §1 toast "บอทเปิด — สัตว์รังไล่ตามคุณแล้ว" | template "บอทเปิด — {name}ไล่ตามคุณแล้ว" / "Bot ON — {name} is coming for you" with the enemy's name (the pack's when it has one); + "บอทเปิด — มีผลหลังรีเซ็ต" / "Bot ON — takes effect after reset" while the beast is down | the toast named the hive beast under a pack's own enemy, and said it was chasing while it lay dead (review) |
| §8.3 "red floor ring grows 0.6 → 1.0" (r 1.4 m) | the telegraph is the claw's real reach: a sector of `strike_reach` 2.6 m and ±`strike_half_angle_deg` 70° in front, one mesh with `telegraph.gdshader` (no time uniform, every level): a bright rim at the reach, a see-through fill growing from the beast to the rim as the wind-up ends | the 1.4 m ring was smaller than the 2.6 m reach: a player standing outside it still got clawed (review) |
| §8.3 / §12.3 "the world says whether the target is in the room" (`in_room`) | in the room **and** in shoot mode | in the band between the room edge (z −10.5) and the shoot line the player is in walk mode with the gun holstered, and the beast still clawed it (review) |
| §8.5 / §11.3 "with the bot on, the beast thinks at 10 Hz" | with the bot on it sleeps (no physics processing) while it stands on its pad facing the entry and the player is out of the room; `set_target_in_room` wakes it; `HiveBeast` emits `moved(pos)` only on frames it moves | it ran its AI every tick at home while the player stood in the corridor (review) |
| §8.1 clips | as specified: `claw_0..2` read well on the `warrior` kit (contact sheet reviewed), so `bash_*` was not needed | — |
| §10.4 "focus loss on desktop opens the pause panel in shoot mode" | focus loss or `NOTIFICATION_APPLICATION_PAUSED` opens it in shoot mode on every input mode | on a phone a call or an app switch let the fight run on with the bot on (review) |
| §3 / §10 build ≤ 150 ms target | reaching the arena door on the deck starts loading the arena screen, the player and beast scenes, the clip library, the `warrior` kit and both figure scripts on a thread (`HallScreen.preload_arena`, kept for later entries); the longest frame on entering measured 206 ms in the final full run (was 364–447) on the test machine; the black fade hides it | the whole build ran in one main-thread frame: about 0.4 s here, likely 1.5–2 s on a weak phone (review) |
| §9.3 the pack drives the arena only | `PACK_SPEC.md` H1–H4: the deck avatar takes the pack's `deck` figure (`HallWorld.set_figure` → `HallAvatar.set_figure`, optional `deck_speeds()`, `set_fade`), the arena door preloads the pack's player and enemy figures, both public presets exclude `packs/*` and the data lint fails without it; with no pack nothing changes on screen | the owner tries his own figures in a private build (figure packs) |
| §11.2 budgets | measured, all within the limits: overview 25 / 25 / 21 / 21 draw calls (hi / mid / lo / min); corridor 29 / 29 / 22 / 22; phone worst view, now with four damage numbers **and** the red hurt edge, 38 / 38 / 35 / 34 (limits 70 / 60 / 45 / 40); the deck's views unchanged | the HUD and touch batching above |

Questions left for the owner (also in the Thai note): the beast's toughness and speed (steady rifle fire kills it in about
3.1 s, before its 4.8 s charge from the pad arrives, unless the player misses), whether reset should also turn the bot
off, the button positions on his phone, and which model to use for the beast if `warrior` is not the one.
