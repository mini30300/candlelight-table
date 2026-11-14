# Campaign (round E) — build spec

Written 14–15 Nov 2026 on top of commit 4b9e600 (ใหม่ 0.11, round D) on branch `t2-campaign`. Owner request of
15 Nov 2026 (paraphrased): a campaign in both apps — pick a difficulty on cards that each show a scene, pick a planet in
a spiral galaxy whose events reroll every week (the same for everyone), play a walk-and-shoot mission with the
dressing-room figure, get a report with a score and coins; plus "how do I play with friends in other houses through
Hamachi, like Minecraft". Four builders work from this file in parallel (tracks A–D, §5), each on its own files.

Everything in `ARENA_SPEC.md`, `PACK_SPEC.md`, `SHIP_LOBBY_SPEC.md` and `NET_SPEC.md` still holds unless a section below
changes it by name. Line numbers drift; quoted names are the anchors. AGENTS.md rules apply everywhere: no franchise
names (write "dark cult", "traitor knights", "alien swarm", "green orcs" …), Thai first with an English entry for every
string, comments short and in Thai, surgical edits, determinism, nothing extra per frame on `min`.

**For the owner, in Thai:** รอบนี้เพิ่ม "แคมเปญ" ทั้งแอปปกติและแอปส่วนตัว: เดินไปที่โต๊ะแคมเปญบนดาดฟ้า (แอปปกติ) หรือโต๊ะ
โฮโลแกรม/ยานลงจอดในลานปล่อยยาน (แอปส่วนตัว) → เลือกความยาก 4 ระดับ (การ์ดมีฉากโชว์) → เลือกดาวในกาแล็กซีก้นหอย
44 ดวง แต่ละดวงมีศัตรูบุกไม่ซ้ำกันและมีเหตุการณ์ 1–3 อย่าง เปลี่ยนทุกวันจันทร์ 7 โมงเช้า (เวลาไทย) ทุกเครื่องเห็นเหมือนกัน
→ ออกรบแบบเดินยิงเหมือนห้องทดลองอาวุธ → หน้าสรุปผล (สังหาร ความแม่นยำ เวลา ความเสียหาย) → คะแนน → เหรียญ (เก็บในเครื่อง
ก่อน รอบหน้าย้ายขึ้นเซิร์ฟเวอร์กันโกง) และเล่นกับเพื่อนต่างบ้านผ่าน Hamachi / Radmin VPN / Tailscale ได้

---

## 0. Decisions this spec fixes (do not re-decide)

| Topic | Decision |
| --- | --- |
| Entry, public app | A new deck station **`campaign`** "โต๊ะแคมเปญ" / "Campaign Table": a star-chart projector at (5.5, −5.5) in the back-right of the nave (§1.2). |
| Entry, private app | New pack-room action **`campaign`** for a station **and** for a card. The launch bay's holo-table card "แคมเปญ" and the dropship both use it and open the **same** campaign flow (no separate "launch" semantics: one entry, one flow, §1.3). |
| One flow | `CampaignFlow.start(from)` is the only way in; difficulty → galaxy (planet card + brief inside) → mission → report → galaxy or back to where you came from (§1.1). |
| Galaxy | 44 fixed planets (4 arms × 11) with our own Thai + English names; 8 invader factions × 6 weekly modifiers = 48 invaders, so no two planets share an invader in a week (§2.1–§2.2). |
| Week | Week number = Monday-based weeks since 1 Jan 1970 in **UTC** (`CampaignWeek.week_of`); reroll at Monday 00:00 UTC = 07:00 Bangkok. Wall-clock time is read in one place only (`CampaignWeek.now_unix`) (§2.3). |
| Weekly roll | A pure function of the week number using the core's `Rng` (PCG32, `Rng.make("campaign_week", week)`, `bounded()` only) — the engine-independent generator the battle rules use, so every device and every future Godot version rolls the same galaxy. Golden digests in `test_campaign_galaxy.gd` (§2.4). |
| Missions | Single player in this round. Mission logic uses one `RandomNumberGenerator` seeded with `spec.seed` (never `randomize()`, `randf()` globals, `Time`), so layout and waves are pure functions of the spec. Real-time combat is not compared between devices. |
| Several events on a planet | The chosen event is the **primary** objective (required to win); the planet's other events become **secondary** objectives in the same map (optional, +300 each) (§2.4). |
| Difficulty | ธรรมดา / ยาก / ยากมาก / ภัยพิบัติ, score ×1 / ×1.5 / ×2.5 / ×4, integer percent table in `CampaignRules.DIFFICULTY` (§2.5). |
| Coins | Local only, in `user://campaign.json` (versioned), never in `data/` (DATA_HASH unchanged) and never in `settings.cfg` (§2.8). A later round moves coins and items to the server. |
| Hero scenes | Contract shared with Team 1 (private versions): `res://packs/campaign/hero_<id>.gd`, then `res://packs/arena/campaign/hero_<id>.gd`, else the built-in `res://scenes/campaign/hero_<id>.gd` (§3). |
| Online | Campaign is offline-only; while in a mission `where` is sent as `"arena"` (an existing `NetProto.WHERES` value): **no protocol change**, `NetProto.VERSION` unchanged. |
| VPN joins | Typed join-by-IP and the host's gate accept Hamachi 25/8, Radmin 26/8 and Tailscale 100.64/10 **only when this device itself has an address in the same range**; LAN discovery stays private-only (§6). |
| Versions | No `APP_VER` bump and no Thai release note in the tracks: final integration does both. No rules change (`RULES_V` stays 10). |
| Project settings | No track edits `project.godot` (no autoload, no input action: missions reuse `interact`, `fire`, `melee`, `reload`, `back`, the move actions, `run`). |

## 1. Flow and screens

### 1.1 Flow and the screen stack

```
Deck (hall, depth 2) ─E at "campaign"─┐
Pack room (depth 3) ─E at a "campaign" station / tap a "campaign" card─┤
                                       ▼
            CampaignFlow.start(from)  (remembers base_depth = App.depth(), from = "deck" | "room")
                                       ▼ push
            DifficultyScreen  ── chosen(id) ──▶ App.replace ▶ GalaxyScreen (planet card + brief are panels in it)
                 ‹ / Esc = pop (back where you came from)        │ "ออกรบ" (fade)
                                                                 ▼ push
                                                           MissionScreen ── finished(result) ──▶ App.replace ▶ ReportScreen
                                                                                                   │ "เล่นอีกครั้ง" → replace ▶ MissionScreen (same spec)
                                                                                                   │ "กลับแผนที่กาแล็กซี" / Esc → pop ▶ GalaxyScreen
                                                                                                   │ "กลับยาน" → CampaignFlow.leave()
            GalaxyScreen: ‹ / Esc → CampaignFlow.leave() (pops to base_depth) · "เปลี่ยนความยาก" → replace ▶ DifficultyScreen
```

- The screens under the top one are hidden by `App.push` (the deck and the room already stop their worlds when hidden).
- `CampaignFlow` (`app/campaign_flow.gd`, static) owns every push/replace/pop of the campaign; the screens never pop
  each other. The skeleton in this commit is the reference; track A completes it (fades, double-tap guards, music,
  `where`).
- Music (`/root/Music`, moods `menu`/`deck`/`battle`): difficulty, galaxy and report keep `deck`; the mission sets
  `battle` and the report sets `deck` again. The catastrophe card plays its own track (§3.3) and lowers nothing else.

### 1.2 Public entry: the deck station `campaign` (track A)

A free spot on the deck: the back-right of the nave, in front of the right lancet of the great viewport (the planet of
the viewport is on the left, so nothing important is hidden).

| Key | Value |
| --- | --- |
| id | `"campaign"`, appended to `HallLayout.IDS` (after `"arena"`) |
| Form (our design) | Star-chart projector: an octagonal two-step steel dais (r 1.0), a brass pedestal with a dark glass bowl, above it a flat holographic spiral galaxy disc (r 0.8, visual only, holo green-blue like the war table's holo layer, `HallBuilder` kit), 4 small brass struts, a ring of amber status lamps; our candle emblem on the pedestal front |
| Footprint | `c` (5.5, −5.5), `h` (1.0, 1.0), `round` true, `height` 1.6 (the disc top, so the camera arm collides with it) |
| Reach / front | `reach` 1.5, `front` (5.5, −3.9) (0.6 m from the edge, facing −z) |
| Sign | `sign` (5.5, 2.75, −5.5), `face` 0 (faces +z, toward the spawn) |
| Names (hall_screen.gd) | `NAMES.campaign` "โต๊ะแคมเปญ" / "Campaign Table"; `SIGNS.campaign` "โต๊ะแคมเปญ · แผนที่ดวงดาว" / "Campaign Table · Star Map" (keys in `ui/i18n/hall.json`) |
| Use | `use_station()` `"campaign"` → `CampaignFlow.start("deck")`; null (screens missing) → the soon panel with "แคมเปญ — ยังไม่พร้อม" / "Campaign — not ready yet" |
| Online | Works while online (friends see you "on the deck" until the mission sets `where = arena`). Clients may play the campaign too; it does not touch the room. |
| Cost | Geometry inside the existing `Static/Props` meshes (no new draw call) + 1 sign `Label3D` + 1 ring in the existing `Rings`; ≤ +1.5k primitives. The holo disc animates only on hi/mid in a vertex shader (`TIME`); lo/min static, no `TIME`. |

Checked distances (track A asserts them in `test_hall_layout`): pillar (8.5, −5) → footprint gap 1.73 m; candle stand
(4, −7.5) → 1.22 m; back wall → 1.5 m; battle table rect (x ≤ 3) → 1.5 m; the front ring is 2.5 m from the battle table's
rect (> its reach 1.6) and inside only its own trigger; spawn → edge 11.9 m; the flood fill from the spawn reaches it;
no friend spawn (`HallFriends.spawn_for`) is in its reach. `tests/flow/test_lobby_flow.gd` keeps a hand-copied blocker
table (`RECTS`): add the projector there (its checks are unchanged). `test_hall_reach` walks to it as to the other stations.

### 1.3 Private entry: pack-room action `campaign` (track A)

- `PackRooms.ACTIONS` += `"campaign"`; `PackRooms.CARD_ACTIONS` += `"campaign"`. A `campaign` station or card needs no
  extra keys; any number of them may exist (the launch bay has two: the dropship station and the holo card).
  Validation messages: the card error becomes "card action must be soon, online or campaign".
- `PackRoomScreen.use_station()` `"campaign"` and `_use_card()` `"campaign"` → new `open_campaign() -> Node`: close
  cards and soon panel, release the stick, halt the avatar, `CampaignFlow.start("room")`; null → `show_note(CAMPAIGN_NOT_READY)`
  ("แคมเปญ — ยังไม่พร้อม", same key as the deck). Returning from the campaign shows the room as it was (avatar where it stood).
- New fixture `tests/fixtures/pack_rooms_campaign/camp_room/` (copy of `test_room` + a `campaign` station on its right
  wall + its cards station gets a third card with action `campaign`) and a broken case
  `tests/fixtures/pack_rooms_bad/card_bad_action` stays failing with the new message.
- **Private repo follow-up (Team 1 / integration, not this repo):** in `pack/rooms/launch_bay/room.json` the dropship
  becomes `"action": "campaign"` (drop its `soon`) and the holo card "แคมเปญ" becomes `"action": "campaign"` with text
  "ออกรบตามภารกิจ ได้เหรียญ" / "Fight missions, earn coins". Optional: in `.github/workflows/personal-build.yml` (step
  "Copy the pack") add `if [ -d public/godot/packs/arena/campaign ]; then mv public/godot/packs/arena/campaign public/godot/packs/campaign; fi`
  (the loader finds both places, §3.1). **Order: the public PR merges first**; a room.json with action `campaign` on an
  older public `main` fails `PackRooms.validate` and the whole launch bay disappears.

### 1.4 Difficulty screen (track B, `ui/screens/difficulty_screen.*`)

- Title "เลือกความยาก" / "Choose the difficulty", "‹ กลับ" top left. Four cards in the order normal, hard, veryhard,
  catastrophe; each card: the hero scene (§3) on top, name (`CampaignRules.difficulty(id).th` through `I18n.t`), blurb,
  "คะแนน {x}" with `CampaignRules.mult_text(id)`, revives line ("ลุกได้ {n} ครั้ง" / "ล้มแล้วจบ" for 0). The card of
  `ctx.last` starts selected (outline); tap/click a card = select it (its scene goes live); a second tap or the card's
  "เลือก" button = `chosen.emit(id)`. Keyboard: ←/→ (or A/D) moves the selection, E / Enter chooses.
- Layout: wide (≥ 1100 logical px): 4 cards in a row, each 16:9-ish scene area; narrow / phone portrait: 2 × 2 grid or
  a horizontal scroller with tall scenes (the hero must frame for both aspects, §3.2). Buttons ≥ 44 px, safe margins,
  no overflow in English.
- Scenes: one live hero at a time (the selected card); the other three show a still frame rendered once at open
  (§3.4). On `min` all four are stills and nothing runs per frame after the stills are made.

### 1.5 Galaxy screen (track A, `ui/screens/galaxy_screen.*`)

- Top bar: "‹ ยาน" (= leave), title "กาแล็กซี · สัปดาห์ {label}" (`CampaignWeek.iso_label`), countdown
  "เหตุการณ์ใหม่ในอีก {d} วัน {h} ชม." (refreshed by a 30 s `Timer`, not per frame), coins "เหรียญ {n}", the difficulty chip
  "ความยาก: {name} {mult}" (tap = "เปลี่ยนความยาก").
- Map (`GalaxyMap`, `ui/campaign/galaxy_map.gd`, a `Control` that draws in `_draw`): a dark disc with a spiral glow and
  stars baked once into an `ImageTexture` (fixed seed, `Hash` only; texture size 1024 hi / 768 mid / 512 lo and min);
  planets at `CampaignGalaxy.position(i)` as filled circles in the biome colour with a ring in the invader's faction
  colour (`FACTIONS[].col`), a gold star on featured planets, a check mark on events cleared this week at the chosen
  difficulty (`CampaignSave.is_repeat`). Drag = pan, wheel / pinch = zoom 1×–3×, tap (hit radius ≥ 22 logical px) =
  planet card. Redraws only on input, resize or data change.
- Planet card (panel: right side on wide screens, bottom sheet on narrow): planet name, biome, "ผู้รุกราน: {faction} · {modifier}",
  featured badge "ดาวเด่นสัปดาห์นี้ · เหรียญ ×1.5", one row per event: mission name (`MissionTypes.name_th`), goal
  (`goal_th`), "รางวัลประมาณ {n} เหรียญ" (`CampaignRules.estimate_coins(spec)`, track A adds it:
  `(PRIMARY + NO_DOWN + SECONDARY × n_secondary) × score_x10 / 10 / COIN_DIV_WIN`, then the featured and repeat
  factors), "ผ่านแล้ว" when cleared. Tap a row = the brief.
- Brief (panel): mission name and goal, "เป้าหมายรอง: …" lines (`MissionTypes.secondary_th`), invader and modifier, the
  difficulty and its multiplier, "ออกรบ" (fade, `CampaignFlow.launch(CampaignGalaxy.mission_spec(week, planet, idx, difficulty))`)
  and "‹ กลับ" (back to the card).
- The galaxy keeps the week it opened with (`ctx.week`). On every show it compares `CampaignWeek.current()`; when the
  week moved it reloads and shows the note "เหตุการณ์สัปดาห์ใหม่มาแล้ว".

### 1.6 Mission screen (track C, `ui/screens/mission_screen.*`)

- `start(spec)` builds `MissionWorld` from the spec; the screen is like the arena screen (ARENA_SPEC §10.3): HUD,
  "‹ หยุด" top left (opens the pause panel), use button, toast, pause panel ("หยุดชั่วคราว": "เล่นต่อ", "ตั้งค่า",
  "ออกจากภารกิจ" with a confirm "ออกจากภารกิจ? ผลจะนับเป็นแพ้"), fade. Esc / Android back = pause panel (always
  handled). Settings pushes over it and pauses like the arena.
- Start: fade in, a 2 s banner with the mission name and goal, then play. End: freeze input, banner
  "ภารกิจสำเร็จ" / "ภารกิจล้มเหลว" for 1.5 s, fade out, `finished.emit(result)` exactly once (also for "quit").
- `where` = `"arena"` on start (existing value), music mood `battle`.

### 1.7 Report screen (track A, `ui/screens/report_screen.*`)

- `open({"spec", "result", "score", "coins"})`. Title "ภารกิจสำเร็จ" / "ภารกิจล้มเหลว" (+ "ออกจากภารกิจ" for quit), the
  planet and mission names, the stats row (kills total, accuracy %, time m:ss, damage taken, downs), then one line per
  `score.lines` entry (label via `I18n.t(line.th)`, value), "รวมก่อนคูณ {raw}", "× {mult}", "คะแนน {total}", the grade
  (big letter, "-" on a fail), "+{coins} เหรียญ" and "เหรียญทั้งหมด {n}". hi/mid count the numbers up with one tween
  (≤ 1.2 s); lo/min show the final numbers at once.
- Buttons: "เล่นอีกครั้ง" (`CampaignFlow.retry()`), "กลับแผนที่กาแล็กซี" (pop), "กลับยาน" (`CampaignFlow.leave()`).
  Esc = back to the galaxy.

## 2. Data

### 2.1 Galaxy layout (`CampaignGalaxy`, `app/campaign_galaxy.gd`, done in this commit)

- `PLANETS`: 44 entries `{id "p00".."p43", th, biome}` in a fixed order (arm = index / 11, slot = index % 11, inner to
  outer). English names live in `ui/i18n/campaign.json` (`I18n.t(th)`). **The order and ids are part of the shared
  contract**: changing them changes every device's galaxy (golden digests fail).
- `BIOMES`: `ruin` ซากเมือง, `forest` ป่าดงดิบ, `desert` ทะเลทราย, `ice` ทุ่งน้ำแข็ง, `volcanic` ภูเขาไฟ, `toxic` หนองพิษ.
  Track C maps each biome to a mission palette and prop set.
- `position(i)`: a 4-arm spiral, `ang = arm·τ/4 + slot·0.42 + 0.35`, `r = 0.18 + slot·0.074`, plus a fixed hash jitter
  (≤ 0.0175); visual only.

### 2.2 Factions and the enemy roster

- `CampaignGalaxy.FACTIONS` (identity, track A): `swarm` ฝูงเอเลี่ยน, `orcs` ออร์คเขียว, `cult` ลัทธิมืด, `traitors`
  อัศวินทรยศ, `machines` เครื่องจักรโบราณ, `raiders` โจรเงา, `daemons` กองทัพปีศาจ, `tomb` กองทัพสุสาน, each with a map colour.
- `CampaignGalaxy.MODIFIERS`: `armoured` เกราะหนา, `frenzied` คลุ้มคลั่ง, `gunline` แนวปืน, `horde` ฝูงมหึมา, `champion`
  มีหัวหน้าคุมทัพ, `ambush` ซุ่มโจมตี; their effects are in `MissionTypes.MODIFIERS` (track C).
- `MissionRoster` (`scenes/campaign/mission_roster.gd`, track C): per faction a `style` (`beast` = KitBeast claw clips,
  `fighter` = humanoid with weapon clips) and one battle-table kit per role `rusher` / `gunner` / `brute` / `boss`
  (skinned 23-bone kits only), `ROLE_STATS` per role, `SHARE` of the roles per wave. Fallbacks: no kits on disk → the
  KitBeast egg tinted in the faction colour; faction `swarm`, role `brute` → the pack's enemy figure
  (`ArenaActors.make_figure("enemy")`) when a pack exists (the existing arena beast mapping); `tomb` has no gunner (its
  share goes to rushers). The hidden/secret unit kit is never used (AGENTS rule 3).
- `destroy_camp`: the camp's guards are always the `cult` roster; the invaders patrol outside the camp.

### 2.3 Week (`CampaignWeek`, `app/campaign_week.gd`, done)

`week_of(unix) = floor((floor(unix / 86400) + 3) / 7)` (week 0 starts Mon 29 Dec 1969); `start_unix(w) = (7w − 3)·86400`;
`seconds_to_reroll(unix)`; `iso_label(w)` ("2026-W46"); `split(seconds)` → `{d, h, m}`; `now_unix()` reads
`Time.get_unix_time_from_system()` unless `test_now ≥ 0`. 14 Nov 2026 is week 2967; the reroll is every Monday
00:00 UTC (07:00 in Thailand). A device with a wrong clock sees another week — accepted (local coins only; the server
round will give the week).

### 2.4 Weekly roll, mission types and combined events (`CampaignGalaxy.week(w)`, done)

Exact algorithm (all draws from one `Rng.make("campaign_week", w)`, `bounded(n)` = 0..n−1):

1. Build the 48 pairs `[faction, modifier]` faction-major in table order; Fisher–Yates shuffle with
   `j = bounded(i + 1)` for `i` from 47 down to 1; planet `k` gets `pairs[k]`.
2. For each planet in order: `n = 1 + (bounded(100) < 45) + (bounded(100) < 15)`; then `n` times pick
   `k = bounded(left.size())` from a fresh copy of `TYPES = ["purge", "defend", "rescue", "destroy_camp"]`, append
   `{type, idx}` (idx 0..n−1) and remove it.
3. Featured: draw `bounded(44)` until 3 distinct planets are flagged.

Result: `{"week", "label", "planets": [{id, faction, modifier, events: [{type, idx}], featured}]}` (cached per week).
`digest(w)` hashes it (golden values for weeks 2967/2968 in `test_campaign_galaxy.gd`). About 1.6 events per planet.

Mission types (`MissionTypes.TYPES`, numbers are track C's to tune, recorded in §12.C):

| type | Primary objective | Win | Fail (besides the player's last down) | par_s | limit_s | base enemies |
| --- | --- | --- | --- | --- | --- | --- |
| `purge` กวาดล้างผู้รุกราน | kill every enemy of all waves | last enemy dead | — | 240 | — | 24 in 3 waves |
| `defend` ป้องกันฐาน | keep the base (HP 1000) alive until the timer ends | timer (180 s) ends with base HP > 0 | base HP 0 | 0 (no time bonus) | 180 | 30 in 5 waves |
| `rescue` ช่วยตัวประกัน | free 3 hostages (E at each) and walk them to the pickup ring | every living hostage at the pickup, at least 1 | all hostages dead, or 600 s pass | 300 | 600 | 18 in 2 waves |
| `destroy_camp` ทำลายค่ายลับลัทธิมืด | destroy 3 ritual pylons (HP 400 each, shootable) | third pylon down | — | 270 | — | 20 in 2 waves + camp guards |

Secondary objectives (`MissionTypes.SECONDARY`, one per other event, in `spec.secondary` order): purge → kill 75 % of
all enemies; defend → hold a beacon ring 30 s in total (E starts it, standing in the ring counts); rescue → free 1 caged
hostage and bring it to the pickup; destroy_camp → destroy 1 pylon. They never block the win; the result reports
`secondary_done` as bools in `spec.secondary` order. Enemy totals: `MissionTypes.enemy_total(spec)` = base ×
`count_pct` × modifier `count_pct` (floor, ≥ 1); bosses come extra (last wave; `champion` adds one).

### 2.5 Difficulty (`CampaignRules.DIFFICULTY`, done)

| id | Thai | count | hp | dmg | speed | windup | revives | score |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `normal` | ธรรมดา | 100 % | 100 % | 100 % | 100 % | 100 % | 2 | ×1 |
| `hard` | ยาก | 140 % | 130 % | 130 % | 110 % | 90 % | 1 | ×1.5 |
| `veryhard` | ยากมาก | 180 % | 170 % | 160 % | 120 % | 80 % | 1 | ×2.5 |
| `catastrophe` | ภัยพิบัติ | 240 % | 220 % | 200 % | 130 % | 70 % | 0 | ×4 |

"Aggression" = speed and windup (a shorter windup strikes sooner) plus, in track C's AI, the share of enemies that
flank instead of queueing (normal 10 %, hard 25 %, very hard 40 %, catastrophe 55 %; `MissionTypes`). Revives: the
player is downed by `ArenaPlayer` (`downed`); with revives left the mission waits for `revived` and re-places the
player at the last checkpoint; the down after the last revive ends the mission as a fail. Concurrency caps (§4) limit
how many enemies are alive at once on weak phones; totals never change with the graphics level.

### 2.6 Scoring (`CampaignRules.score(spec, result, opts)`, done)

Integer lines (`KILL_POINTS` rusher 10, gunner 20, brute 40, boss 150, structure 50):

| line | value |
| --- | --- |
| kills | Σ points × kills per role |
| accuracy | only with ≥ 15 shots: `acc² × 500 / 10000` (acc in %, max 500) |
| time | win and par > 0: `max(par − time_s, 0) × 4` |
| primary | win: 1000 |
| secondary | 300 per done secondary |
| hostages | 100 per hostage saved (rescue, when the result has the key) |
| base | 5 per % of base HP left (defend, when the result has the key) |
| damage | `−min(damage_taken, 400)` |
| no_down | win with 0 downs: 500 |

`raw = max(Σ, 0)`, `total = raw × score_x10 / 10`, grade from raw on a win (S ≥ 3000, A ≥ 2200, B ≥ 1500, C ≥ 800, D),
"-" on a fail. Returned: `{win, lines: [{key, th, value}], raw, mult_x10, total, coins, grade, acc_pct}`.

### 2.7 Coins

Win: `max(total / 40, 10)`; fail or quit: `total / 160`; featured planet × 150 %; a repeat clear (the same planet, event
and difficulty already won this week, `CampaignSave.is_repeat`) × 25 %. All integer floor.

### 2.8 Local save (`CampaignSave`, `app/campaign_save.gd`, done; track A owns it)

`user://campaign.json`, `{"v": 1, "coins", "last_difficulty", "weeks": {"<week>": {"best": {key: total}, "clears": {key: true}}}, "history": [≤ 20]}`,
key `"<planet>:<event idx>:<difficulty>"`, only the newest 2 weeks kept. A broken file, another version or wrong types
start fresh with a warning. Tests set `CampaignSave.path`. Coins are not protected against editing this round (the
server round replaces them).

## 3. Hero scenes (track B; contract shared with Team 1)

### 3.1 The contract (`CampaignHeroes`, `scenes/campaign/hero_loader.gd`, done)

- A pack may provide `res://packs/campaign/hero_<id>.gd` (private repo path `pack/campaign/hero_<id>.gd`; the personal
  build copies `pack/` to `res://packs/arena/`, so the loader also looks in `res://packs/arena/campaign/`), `id` ∈
  `normal | hard | veryhard | catastrophe`.
- The script `extends Node3D` and has `func setup(ctx: Dictionary) -> void` and `func set_active(on: bool) -> void`.
  `ctx = {"level": "hi"|"mid"|"lo"|"min", "sel": Figures.selected()}` plus optional keys a hero may ignore (the stage
  passes `"aspect"`: width / height of its viewport). `setup` builds everything, including its own `Camera3D`
  (`current = true`) and lights / environment; `set_active(false)` stops every process, tween, animation and sound
  (no per-frame work while inactive); `set_active(true)` resumes. Optional: `set_aspect(a: float)` (called on resize).
- On `min` a hero shows a single still pose (the stage renders it once, §3.4). A hero never touches `App`, `Net`, files
  or other nodes outside itself, and declares no `class_name`.
- `CampaignHeroes.make(id)`: the first existing pack script that instantiates as a `Node3D` with both methods, else the
  built-in one (a warning names the missing methods); `pack_path`, `builtin_path`, `is_pack`, `missing_api`,
  `music_path()` (`catastrophe.ogg` in the same folders). Tests set `CampaignHeroes.test_dirs`.
- Team 1 is adding an optional figure hook H11 `apply_palette(p: Dictionary)` on its own branch: **do not depend on it**.

### 3.2 Framing

Each card's scene must read in a 16:9 card and in a tall phone card (about 9:16). The stage gives `"aspect"`; heroes
use `Camera3D.keep_aspect = KEEP_HEIGHT` when aspect ≥ 1 and `KEEP_WIDTH` below, and keep the subjects inside the
central square.

### 3.3 Built-in public fallbacks (`scenes/campaign/hero_<id>.gd`, stubs in this commit)

All built-ins run in their own `World3D` (the stage's `SubViewport.own_world_3d = true`), use the kit shader's light
(`figure.gdshader` uniforms `sun_dir`, `sun_colour`, `ambient_colour`, set on the figure's duplicated material by a
helper `HeroLight.apply(node, sun_dir, sun, ambient)` in `scenes/campaign/hero_light.gd` that walks the meshes; pack
figures with their own light ignore it) and a background quad / `Environment` colour. No kits on disk → the KitBeast egg
stand-ins (still readable as figures).

| id | Scene |
| --- | --- |
| `normal` | The player's own figure: `ArenaActors.player_figure(ctx.sel)` set up with role `player` and dressed with `ArenaActors.scheme_of(ctx.sel)` (H10 when the entry has schemes) — the same factory the arena uses. Upper body close-up (camera at chest height, FOV ≈ 28°), facing the camera, idle clip slowed to 0.6 on hi/mid, still on lo/min. Background: black to dark grey vertical gradient; light from straight above the head (`sun_dir` (0, 1, 0.15), warm white, ambient 0.12). |
| `hard` | Three kits `knight`, `kcapt`, `kblade` (KitWalker, armour-like knights) in the blue scheme (`Figures.scheme("blue")`: 2f5fb0 / d6d8de), standing in a staggered line (centre forward, the sides 0.8 m back, turned 20° in), low camera looking slightly up, cool side light. Idle on hi/mid, still on lo/min. |
| `veryhard` | A knight with a polearm: kit `pike_halb` (halberd; fallback `naginata`, then `kblade`) in a silver scheme (primary c9ccd4, secondary 3b4250). 3–4 small aliens (`hound`, fallback `gaunt`) run in from the sides; at contact he spins (whole node 360° in 0.45 s with a `Tween` while playing `swing_1`), they play `die_*` and fade; loop every ~4 s. On min: one still at the moment of the cut. |
| `catastrophe` | The battle table's fallen knights and daemons in a row, appearing one by one (0.35 s apart) like an anime recall of every enemy a fighter has faced: `dmc`, `cxp`, `cxb`, `cxl` (centre, forward), `cxs`, `cxw`, `dmr`; dark red light from behind and above (`sun_dir` (0, 0.6, −1), `sun_colour` deep red, ambient 0.06), fog in the `Environment` on hi/mid (none on lo/min), an `AudioStreamPlayer` that plays `CampaignHeroes.music_path()` when it exists (looping, bus `Music`, stops in `set_active(false)`). On min: the full row, still, no fog, no music autoplay. |

### 3.4 The stage (`HeroStage`, `scenes/campaign/hero_stage.gd`, track B)

`HeroStage extends SubViewportContainer`: `show_hero(id: String, ctx: Dictionary) -> void`, `set_live(on: bool) -> void`,
`snapshot() -> Texture2D`, `hero() -> Node3D`, `counts() -> Dictionary` (`{"live", "draws_hint", "level"}` for tests).
Viewport scale: hi 1.0, mid 0.75, lo 0.5, min 0.5 of the card size. Live = `UPDATE_ALWAYS` (lo: the stage caps it at
30 fps by toggling `UPDATE_ONCE` on a 33 ms `Timer`); still = render once (`UPDATE_ONCE`), copy into an `ImageTexture`,
free the hero (on min the four stills are made one per frame, then nothing processes).

## 4. Budgets per graphics level

Measured like `test_hall`/`test_arena`: max of `RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME` / `…_PRIMITIVES_IN_FRAME` over
4 frames, low-processor mode off, 1280 × 720 and the phone layout (20:9, touch on). Idle = after 10 frames without
input or animation.

| View | hi | mid | lo | min | Idle rule |
| --- | --- | --- | --- | --- | --- |
| Deck, every existing view + the projector view (avatar at its front ring, yaw π) | deck targets 40 / 40 / 35 / 30 hold | | | | as the deck (nothing after 10 idle frames on lo/min) |
| Difficulty screen (one live hero, three stills) | ≤ 90 / 120k | ≤ 70 / 90k | ≤ 45 / 50k | ≤ 30 / 30k (four stills, no live viewport) | min: nothing processes once the stills exist; lo: live hero ≤ 30 fps |
| A live hero alone (inside its viewport) | ≤ 60 / 80k | ≤ 45 / 60k | ≤ 30 / 35k | — (still) | inactive = no processing |
| Galaxy screen | ≤ 40 / 60k | ≤ 30 / 40k | ≤ 20 / 20k | ≤ 15 / 10k | redraw only on input/resize/data; the countdown `Timer` 30 s; hi/mid may twinkle in a shader, lo/min no `TIME` |
| Report screen | ≤ 30 / 20k | ≤ 30 / 20k | ≤ 25 / 15k | ≤ 20 / 10k | lo/min no tween |
| Mission overview (player at spawn, all alive enemies of the first wave in view) | ≤ 90 / 150k | ≤ 70 / 100k | ≤ 50 / 60k | ≤ 40 / 40k | — |
| Mission phone worst view (firing, numbers, telegraphs, hostages following) | ≤ 100 / 150k | ≤ 80 / 100k | ≤ 55 / 60k | ≤ 45 / 40k | — |
| Mission: enemies alive at once | 14 | 10 | 7 | 5 | waves top up as enemies die |
| Mission: skinned figures on screen | ≤ 24 | ≤ 16 | ≤ 10 | ≤ 8 (as `test_budgets` SKINNED_CAP min) | min: figures farther than 25 m hold a still pose |

Per-frame rules in missions: AI thinks at 10 Hz with the enemies spread over frames (≤ 2 repaths per physics frame,
one shared `ArenaPath` grid per world); only moving enemies run `_physics_process`; on min no telegraph shader (one
shared flat red material shown only during a windup), no damage-number tweens (still 0.6 s like the arena), no sparks,
no shake; lo/min no `TIME` shaders. A paused mission processes nothing.

## 5. Tracks: files, classes and interfaces

### 5.1 Shared files and conflict rules (all tracks)

| Shared thing | Rule |
| --- | --- |
| i18n | One fragment per track, already registered in `I18n.FRAGMENTS` and `test_i18n_fragments` by this commit: **A** `ui/i18n/campaign.json` (+ the deck station keys in `ui/i18n/hall.json`), **B** `ui/i18n/campaign_hero.json`, **C** `ui/i18n/campaign_mission.json`, **D** the existing `ui/i18n/online.json`. A key lives in exactly one file; before adding a key, `grep` the others and `data/i18n_en.json` and reuse an existing key instead. Never edit `ui/i18n.gd` or another track's fragment. |
| Thai literals | Thai on screen only in `ui/**` and `app/**` scripts (the data lint checks them) or in tables read through `I18n.t` (`MissionTypes`, `MissionRoster` in `scenes/campaign/`, checked by `test_campaign_text`). |
| `tests/run.sh` / CI | No edits needed: unit scripts are discovered under `tests/unit/**/test_*.gd`, flow tests are `tests/flow/test_*.gd`, render tests `tests/render/test_*.gd` (globs). Name new files with your track's prefix (below) so they never collide. |
| `project.godot`, `export_presets.cfg`, `core/version.gd`, `app/app.gd`, `app/figures.gd`, `scenes/arena/*`, `ui/widgets/arena_hud.gd` | Nobody edits them this round. Missions use the arena classes through their public API only. |
| This spec | Each track writes only its own "as built" subsection (§12.A–§12.D) and may fix a typo in its own section; a contract change is written in the owning track's section and announced in its PR. |
| `docs/STATUS.md`, `web/` notes, `APP_VER` | Final integration only. |
| Fixtures | Each track's own folder under `tests/fixtures/` (A `pack_rooms_campaign/`, B `campaign_pack/` (exists), C `campaign_missions/`, D none). |

### 5.2 Track A — core, galaxy, planet card, brief, report, deck station, pack-room action

Owns: `app/campaign*.gd` (`CampaignWeek`, `CampaignGalaxy`, `CampaignRules`, `CampaignSave`, `CampaignFlow` — the first
four are complete in this commit, A keeps them green and adds `estimate_coins`), `ui/screens/galaxy_screen.{gd,tscn}`
(`GalaxyScreen`), `ui/screens/report_screen.{gd,tscn}` (`ReportScreen`), `ui/campaign/galaxy_map.gd` (`GalaxyMap`),
`ui/campaign/planet_card.gd` (`PlanetCard`, panel), `ui/campaign/mission_brief.gd` (`MissionBrief`, panel), `ui/i18n/campaign.json`,
the deck station (`scenes/hall/hall_layout.gd`, `hall_builder.gd`, `hall_world.gd` if needed, `ui/screens/hall_screen.gd`,
`ui/i18n/hall.json`), the pack-room action (`scenes/hall/pack_rooms.gd`, `ui/screens/pack_room_screen.gd`), their tests
and fixtures, `tests/unit/test_campaign_{week,galaxy,rules,save,text}.gd` (exist), `tests/flow/test_campaign_flow.gd`,
`tests/render/test_campaign_galaxy.gd`, `tests/render/test_campaign_report.gd`, the changed hall / pack-room tests.

```gdscript
# app/campaign_week.gd  (static)        class_name CampaignWeek
static var test_now := -1
static func now_unix() -> int
static func week_of(unix_s: int) -> int
static func current() -> int
static func start_unix(week: int) -> int
static func seconds_to_reroll(unix_s: int) -> int
static func iso_label(week: int) -> String
static func split(seconds: int) -> Dictionary            # {d, h, m}

# app/campaign_galaxy.gd  (static)      class_name CampaignGalaxy
const TYPES, DIFFICULTIES, BIOMES, PLANETS, FACTIONS, MODIFIERS, ARMS, PER_ARM, FEATURED
static func planet(id) -> Dictionary                     # + index, arm, slot
static func faction(id) -> Dictionary
static func modifier(id) -> Dictionary
static func position(index: int) -> Vector2              # unit disc, visual only
static func week(w: int) -> Dictionary                   # §2.4
static func planet_week(w: int, id: String) -> Dictionary
static func digest(w: int) -> String
static func mission_seed(w, planet_id, event_idx, difficulty) -> int
static func mission_spec(w, planet_id, event_idx, difficulty) -> Dictionary   # §5.4; {} when invalid

# app/campaign_rules.gd  (static)       class_name CampaignRules
const DIFFICULTY, KILL_POINTS, LINE_TH, GRADES, PRIMARY, SECONDARY, NO_DOWN, COIN_DIV_WIN, …
static func difficulty(id: String) -> Dictionary         # copy + "id"; unknown → normal
static func mult_text(id: String) -> String              # "×1.5"
static func score(spec: Dictionary, result: Dictionary, opts := {}) -> Dictionary   # §2.6; opts {"repeat": bool}
static func estimate_coins(spec: Dictionary, repeat := false) -> int               # A adds (§1.5)

# app/campaign_save.gd  (static)        class_name CampaignSave
static var path := "user://campaign.json"
static func data() -> Dictionary
static func coins() -> int
static func last_difficulty() -> String
static func set_last_difficulty(id: String) -> void
static func event_key(spec) -> String
static func is_repeat(spec) -> bool
static func record(spec: Dictionary, score: Dictionary) -> void
static func reset() -> void

# app/campaign_flow.gd  (static)        class_name CampaignFlow
static var from, base_depth, difficulty, spec
static func start(from: String) -> Node                  # "deck" | "room"; null when screens are missing
static func launch(spec: Dictionary) -> Node             # from the brief
static func retry() -> Node                              # A adds: replace the report with a new MissionScreen(spec)
static func change_difficulty() -> Node                  # A adds: replace the galaxy with DifficultyScreen
static func leave() -> void                              # pop to base_depth

# ui/screens/galaxy_screen.gd           class_name GalaxyScreen extends Control
const SCENE := "res://ui/screens/galaxy_screen.tscn"
func open(ctx: Dictionary) -> void                       # {"difficulty": String, "week": int}
func select_planet(id: String) -> void                   # opens the card (tests)
func open_brief(event_idx: int) -> void                  # opens the brief (tests)
func launch() -> Node                                    # = CampaignFlow.launch(current spec)
func handle_back() -> bool                               # brief → card → map → leave
# ui/screens/report_screen.gd           class_name ReportScreen extends Control
const SCENE := "res://ui/screens/report_screen.tscn"
func open(ctx: Dictionary) -> void                       # {"spec", "result", "score", "coins": int}
func handle_back() -> bool
```

Hall wiring: `HallLayout.IDS` += `"campaign"` and its `STATIONS` entry (§1.2); `HallBuilder` draws the projector into
the static meshes and its holo disc into the holo layer; `hall_screen.gd` `NAMES`/`SIGNS`, `use_station()` case,
`CAMPAIGN_NOT_READY`. Pack rooms: §1.3.

### 5.3 Track B — difficulty screen and hero scenes

Owns: `ui/screens/difficulty_screen.{gd,tscn}` (skeleton exists), `scenes/campaign/hero_*.gd`
(`hero_loader.gd` done, `hero_stage.gd`, `hero_light.gd`, `hero_normal.gd`, `hero_hard.gd`, `hero_veryhard.gd`,
`hero_catastrophe.gd` stubs exist), `ui/i18n/campaign_hero.json`, `tests/fixtures/campaign_pack/**`,
`tests/unit/test_campaign_heroes.gd` (exists), `tests/unit/test_difficulty_text.gd`, `tests/flow/test_difficulty_flow.gd`,
`tests/render/test_campaign_heroes.gd`, `tests/render/test_difficulty_screen.gd`.

```gdscript
# ui/screens/difficulty_screen.gd       class_name DifficultyScreen extends Control
signal chosen(difficulty: StringName)                    # "normal" | "hard" | "veryhard" | "catastrophe"
const SCENE := "res://ui/screens/difficulty_screen.tscn"
func open(ctx: Dictionary) -> void                       # {"last": String ("" = none), "from": "deck" | "room"}; call right after App.push
func choose(id: StringName) -> void                      # emits chosen (cards, keys, tests)
func select(id: StringName) -> void                      # B adds: highlight + make that card's hero live
func selected() -> StringName                            # B adds
func stages() -> Array                                   # B adds: the four HeroStage nodes (tests)
func handle_back() -> bool                               # false → App pops (back where you came from)

# scenes/campaign/hero_loader.gd        class_name CampaignHeroes (static)   — §3.1
const IDS, PACK_DIRS, API, MUSIC
static var test_dirs: PackedStringArray
static func make(id: String) -> Node3D
static func pack_path(id) -> String;  static func builtin_path(id) -> String
static func is_pack(node) -> bool;    static func missing_api(n) -> PackedStringArray
static func music_path() -> String

# scenes/campaign/hero_stage.gd         class_name HeroStage extends SubViewportContainer   — §3.4
func show_hero(id: String, ctx: Dictionary) -> void
func set_live(on: bool) -> void
func snapshot() -> Texture2D
func hero() -> Node3D
func counts() -> Dictionary

# scenes/campaign/hero_light.gd         class_name HeroLight (static)
static func apply(root: Node, sun_dir: Vector3, sun: Color, ambient: Color) -> int   # materials changed

# scenes/campaign/hero_<id>.gd          extends Node3D, no class_name — the §3.1 contract
func setup(ctx: Dictionary) -> void
func set_active(on: bool) -> void
func set_aspect(a: float) -> void                        # optional
```

### 5.4 Track C — missions and enemy AI

Owns: `scenes/campaign/mission_*` (`mission_types.gd` and `mission_roster.gd` exist with starting numbers;
`mission_world.{gd,tscn}`, `mission_layout.gd`, `mission_waves.gd`, `mission_ai.gd`, `mission_enemy.{gd,tscn}`,
`mission_hostage.gd`, `mission_objectives.gd`, `mission_builder.gd`), `ui/screens/mission_screen.{gd,tscn}` (skeleton
exists), `ui/campaign/mission_hud.gd`, `ui/i18n/campaign_mission.json`, `tests/fixtures/campaign_missions/**`,
`tests/unit/test_mission_*.gd`, `tests/flow/test_mission_flow.gd`, `tests/render/test_mission.gd`.

**MissionSpec** (A → C, made by `CampaignGalaxy.mission_spec`; C never builds one except in tests):

```gdscript
{
  "v": 1, "week": int, "planet": "p12", "biome": "forest",
  "faction": "orcs", "modifier": "horde", "featured": bool,
  "primary": {"type": "rescue", "idx": 0},
  "secondary": [{"type": "purge", "idx": 1}, …],          # the planet's other events, in event order
  "difficulty": "hard",
  "diff": {"id", "th", "blurb", "count_pct", "hp_pct", "dmg_pct", "speed_pct", "windup_pct", "revives", "score_x10"},
  "seed": int                                             # RandomNumberGenerator.seed for everything random in the mission
}
```

```gdscript
# ui/screens/mission_screen.gd          class_name MissionScreen extends Control
signal finished(result: Dictionary)                      # once, after the end fade (win, fail or quit)
const SCENE := "res://ui/screens/mission_screen.tscn"
func start(spec: Dictionary) -> void                     # right after App.push
func finish(result: Dictionary) -> void                  # emits once (the world's end, quit, tests)
func world() -> MissionWorld                             # C adds (tests)
func handle_back() -> bool                               # always true: pause panel

# scenes/campaign/mission_world.gd      class_name MissionWorld extends Node3D (group gfx_level)
#   duck-typed like ArenaWorld where ArenaPlayer / ArenaHud need it
signal objective_changed(state: Dictionary)              # {"primary": {type, done, progress, total}, "secondary": [...], "timer_s", "base_pct", "hostages": {freed, saved, alive, total}}
signal ended(outcome: String)                            # "win" | "fail"
signal stats_changed(stats: Dictionary)                  # kills, shots, hits, damage_taken, downs, alive
var player: Node3D                                       # ArenaPlayer (arena_player.tscn), setup exactly as ArenaWorld._spawn_actors
var enemy: Node3D = null                                 # the focus enemy for ArenaHud's bar (or null)
func setup(spec: Dictionary, level: String, touch: bool) -> void
func apply_level(l: String) -> void
func set_active(on: bool) -> void
func set_paused(on: bool) -> void
func station() -> String;  func use_station() -> void    # free a hostage, start the beacon
func hit_target(collider: Object) -> Dictionary          # {"node", "id": &"enemy" | &"pylon"} or {}
func melee_targets() -> Array[Dictionary]                # [{"node", "id", "pos": Vector2, "r": float}]
func result() -> Dictionary                              # §5.5 so far
func counts() -> Dictionary                              # {"level", "alive", "alive_cap", "skinned", "static_meshes", "static_tris", "telegraph_shader": bool}

# scenes/campaign/mission_layout.gd     class_name MissionLayout (static, pure)
static func build(spec: Dictionary) -> Dictionary        # {"half": Vector2, "blockers": [HallLayout.blockers() format], "player_spawn": Vector3,
                                                         #  "spawns": [Vector3], "points": {"base", "pickup", "beacon", "camp", "hostages": [], "pylons": []}}
# scenes/campaign/mission_waves.gd      class_name MissionWaves (static, pure)
static func plan(spec: Dictionary) -> Array[Dictionary]  # [{"at_s": float | -1, "after_clear": bool, "units": [{"role", "kit", "count"}]}]
# scenes/campaign/mission_ai.gd         class_name MissionAI extends RefCounted (pure state machine like HiveAI)
func _init(seed: int, role: String, stats: Dictionary) -> void
func tick(dt: float, me: Dictionary, targets: Array[Dictionary]) -> Dictionary   # {"move": Vector2, "face": float, "event": StringName}
# scenes/campaign/mission_enemy.gd      class_name MissionEnemy extends CharacterBody3D (layer 8, mask 1 | 4 | 2)
signal died(info: Dictionary)                            # {"role", "kit", "by": StringName}
func setup(world: Node3D, opts: Dictionary) -> void      # {"level", "seed", "role", "faction", "kit", "style", "stats", "spawn", "path": ArenaPath}
func take_hit(hit: Dictionary) -> Dictionary             # the ArenaPlayer contract: {"applied", "hp", "killed"}
func is_alive() -> bool;  func hp() -> int;  func hp_max() -> int;  func role() -> String
```

Rules for C: reuse `ArenaPlayer`, `ArenaPath`, `ArenaFx`, `KitBeast`/`KitWalker`/`KitFighter`, `HallBuilder` and
`PropsLayer.Geo` through their public functions only; physics layers as the arena (shell 1, props 4, player 2, enemies
and shootable structures 8). After `revived` re-place the player at the checkpoint (`ArenaPlayer` respawns at the arena
spawn by itself). Shots for accuracy = decreases of `ammo_changed`'s `in_mag` while not reloading; hits = `hit_landed`
with `kind == &"gun"`; melee kills count as kills (not in accuracy). Map: a bounded ground ≤ 48 × 48 m per biome
palette, cover blocks, cliffs as walls; everything random comes from one `RandomNumberGenerator` seeded with
`spec.seed` (sub-streams by `seed ^ fixed salts`), so `MissionLayout.build` and `MissionWaves.plan` are pure and tested.

### 5.5 MissionResult (C → A)

```gdscript
{
  "v": 1,
  "outcome": "win" | "fail" | "quit",
  "time_s": float,                                        # play time, pauses excluded
  "kills": {"rusher": int, "gunner": int, "brute": int, "boss": int, "structure": int},
  "shots": int, "hits": int,                              # gun only (§5.4)
  "damage_taken": int, "downs": int,
  "secondary_done": [bool, …],                            # spec.secondary order
  "hostages_saved": int, "hostages_total": int,           # rescue only (or a rescue secondary)
  "base_hp_pct": int                                      # defend only
}
```

Missing optional keys simply give no line in the score. `CampaignRules.score` clamps every number.

### 5.6 Track D — friends in other houses over a VPN

Owns: `net/net_gate.gd`, `net/net_session.gd`, `ui/screens/lobby.{gd,tscn}`, `ui/online_text.gd`, `ui/i18n/online.json`,
`tests/unit/fixtures/fake_net.gd`, `docs/NET_SPEC.md` (new §18), `tests/unit/test_net_gate.gd` (added checks),
`tests/unit/test_net_vpn.gd` (new), `tests/unit/test_online_text.gd`, the lobby render test checks. Interfaces in §6.

## 6. Track D: VPN ranges (Hamachi, Radmin VPN, Tailscale)

Mini plays Minecraft with friends through Hamachi; the same works here once the game accepts the VPN's addresses.

### 6.1 Gate (`NetGate`, static, no Thai)

```gdscript
const VPN_RANGES := [{"id": "hamachi", "name": "Hamachi", "a": 25, "bits": 8},
	{"id": "radmin", "name": "Radmin VPN", "a": 26, "bits": 8},
	{"id": "tailscale", "name": "Tailscale", "a": 100, "b": 64, "bits": 10}]
static func vpn_range(ip: String) -> String              # "hamachi" | "radmin" | "tailscale" | "" (IPv4 and ::ffff:v4 only)
static func is_vpn(ip: String) -> bool
static func vpn_name(id: String) -> String               # "Hamachi" …
static func peer_allowed(remote_ip: String, my_ips: PackedStringArray) -> bool
	# is_private(remote) or (vpn_range(remote) != "" and some my_ip has the same vpn_range)
static func check_hello(hello, n_members, max_players, remote_ip, known_nid, closing := false,
	my_ips := PackedStringArray()) -> Dictionary         # not_lan when not peer_allowed (new optional last parameter)
```

`is_private` is **unchanged** (25/8, 26/8 and 100.64/10 are not private; the discovery socket keeps ignoring them).

### 6.2 Session (`NetSession`)

- `vpn_ips() -> PackedStringArray`: IPv4 addresses of this device in a VPN range, from `vpn_from(IP.get_local_interfaces())`.
  `static func vpn_from(itfs: Array) -> Array` → `[{"ip", "vpn": id, "name": iface}]`: 25/8 and 26/8 on any interface;
  100.64/10 only on interfaces **not** named like a mobile-data card (`rmnet`, `v4-rmnet`, `rev_rmnet`, `ccmni`, `pdp`,
  `clat`, `wwan`, `seth_`, `radio`) — carrier NAT uses the same range on mobile data, while Tailscale's own adapter
  (`tailscale0`, `Tailscale`, `utun*`, Android `tun0`) counts. Tests inject interfaces (`var itfs_override: Array`).
- `host()`: `no_lan` only when `not has_lan() and vpn_ips().is_empty()` (a PC on Hamachi without Wi-Fi can host).
- `join(ip)`: private → as before; `is_vpn(ip)` and this device has an address in the same range → connect;
  `is_vpn(ip)` without one → `refused("no_vpn", {"vpn": vpn_name(range)})`, `ERR_UNAUTHORIZED`; else `not_lan`.
- `_on_authenticating` (host): `NetGate.peer_allowed(ip, vpn_ips())` instead of `is_private(ip)`; `check_hello` gets
  `my_ips = vpn_ips()`. Discovery (`NetDiscovery`) is untouched: LAN rooms only.
- `NetGate.LOCAL_KEYS` and `OnlineText.LOCAL_KEYS` += `"no_vpn"`.

### 6.3 Lobby and texts (`lobby.gd`, `online_text.gd`, `online.json`)

| Where | Thai | English |
| --- | --- | --- |
| reason `not_lan` (replaces the old text) | เข้าได้เฉพาะเครื่องใน Wi-Fi เดียวกัน หรือ VPN เดียวกัน (Hamachi, Radmin VPN, Tailscale) | Only devices on the same Wi-Fi or the same VPN (Hamachi, Radmin VPN, Tailscale) can join |
| reason `no_vpn` | เครื่องนี้ยังไม่ได้ต่อ {vpn} — เปิดโปรแกรมแล้วเข้าเครือข่ายเดียวกับเจ้าห้องก่อน | This device is not on {vpn} — open it and join the host's network first |
| host, in a room, under "IP ของเครื่องนี้" | IP VPN ของเครื่องนี้ ({vpn}): {ips} | This device's VPN IP ({vpn}): {ips} |
| button next to it | คัดลอก IP VPN | Copy VPN IP |
| help line (finding state, replaces `T_HELP`) | ต้องอยู่ Wi-Fi เดียวกัน หรือ VPN เดียวกัน · Windows: ถ้ามีหน้าต่างไฟร์วอลล์ ให้กดอนุญาต (ถ้าใช้ VPN ติ๊กทั้งส่วนตัวและสาธารณะ) | Same Wi-Fi or the same VPN · Windows: if a firewall window appears, allow it (with a VPN, tick both private and public) |
| help line 2 | เล่นกับเพื่อนต่างบ้าน: ทุกคนเปิด Hamachi / Radmin VPN / Tailscale เข้าเครือข่ายเดียวกัน แล้วใส่ IP VPN ของเจ้าห้อง | Friends in other houses: everyone joins the same Hamachi / Radmin VPN / Tailscale network, then types the host's VPN IP |

The VPN line shows only when `vpn_ips()` is not empty (one line per range, first IP of each; the copy button copies
the first VPN IP and then reads "คัดลอกแล้ว"). The IP field still accepts only a dotted IPv4 (+ `:port`). When a text is replaced, its
old key leaves `online.json` (keep the fragment free of unused keys).

### 6.4 Security and docs

NET_SPEC §10 gains: "VPN ranges are accepted only when the host itself is on the same VPN; anyone in that VPN network can
join (as on a café Wi-Fi) — share the Hamachi network password only with friends." Hamachi's 25/8 is not private
address space (it belongs to someone else on the internet); because the host must have its own 25.x address and the
ENet port is not forwarded, an outside 25.x machine cannot reach it through a home router. Write NET_SPEC §18 "Round E:
friends in other houses over a VPN" (ranges, gate, UI, tests) and give integration a short Thai how-to for Mini
(install Hamachi on both PCs → create/join one network → host presses เปิดห้อง → copy the VPN IP → friend pastes it in
"ใส่ IP ของเจ้าห้อง" → ต่อด้วย IP; allow the firewall prompt for public networks too). Android: Tailscale works the same;
Hamachi/Radmin are PC programs.

## 7. Tests per track

Every check is new unless marked "changed"; a changed expectation says why in a comment (AGENTS: never loosen a test).
Quick run = `GODOT=/root/godot-bin/godot bash godot/tests/run.sh` (import, unit, flow); full adds render under xvfb.

**Already in this commit (all pass):** `test_campaign_week` (week math, ISO labels, countdown, test clock),
`test_campaign_galaxy` (layout, roll rules for 5 weeks, purity + golden digests 2967/2968, spread over 52 weeks, mission
spec), `test_campaign_rules` (difficulty table, score lines, fail/edge cases, coins), `test_campaign_save` (record,
reload, repeat, pruning, history cap, broken files), `test_campaign_heroes` (built-in contract incl. own camera and no
processing while inactive, pack lookup order, fallback for a broken pack scene), `test_campaign_text` (every Thai name
translated, English without Thai, unique English planet names, roster/modifier/type tables cover the galaxy's ids),
`test_i18n_fragments` (changed: 12 fragments, the three campaign fragments last).

**A:** unit `test_campaign_rules` + `estimate_coins`; `test_campaign_flow_unit` (CampaignFlow with stub screens: start →
chosen → galaxy, launch → finished → report with the score recorded once, retry, leave pops to the base depth from the
deck and from a room); `test_hall_layout` (changed: `IDS` with `campaign`; footprint, reach, front ring, distances of
§1.2, flood fill); `test_hall_text` (station name/sign TH/EN); `test_pack_rooms` (changed: `campaign` station and card
accepted, the bad-card message, the fixture room); flow `test_campaign_flow.gd` (headless: main menu → deck → walk to
the projector → E → choose hard with a stub/real difficulty screen → galaxy → planet card → brief → launch with a stub
mission that finishes with a scripted result → report numbers → back to galaxy → leave lands on the deck at the
projector's front; again from the fixture pack room via the station and via the card; Esc paths); `test_hall_reach`
(changed: the projector is reached by the stick walk); `test_lobby_flow` (changed: `RECTS` gains the projector);
render `test_hall` (changed: deck budgets with the projector, the projector view, its sign and prompt; holo disc static
on lo/min), `test_campaign_galaxy` (TH/EN, desktop and phone, every level within §4, no per-frame work on min after
10 idle frames, tap a planet opens the card, PNGs), `test_campaign_report` (win and fail layouts TH/EN, phone, no
overflow), `test_pack_room` (changed: campaign station and card open the flow and return to the room).

**B:** unit `test_campaign_heroes` (extend: stage scale per level, stills on min, music lookup with a fixture
`catastrophe.ogg` stand-in, `HeroLight.apply` counts), `test_difficulty_text` (every string TH/EN, revives line);
flow `test_difficulty_flow.gd` (keys and taps select / choose, `chosen` once, back pops, `ctx.last` preselected);
render `test_campaign_heroes` (each built-in hero on hi/mid/lo/min within §4, 16:9 and 9:16 framing: the subject's
screen box inside the frame, the normal hero shows the selected figure (egg / a kit / the fixture pack figure), the
catastrophe row has 7 figures, no processing while inactive, PNGs to `TEST_OUT`), `test_difficulty_screen` (4 cards
TH/EN, desktop and phone, one live viewport at most, min = four stills and zero processing nodes after the stills, budget).

**C:** unit `test_mission_layout` (pure: same spec → same layout, 50 seeds × 6 biomes × 4 types: player spawn,
every objective point and spawn reachable by flood fill, nothing inside a blocker, inside the bounds),
`test_mission_waves` (pure: totals = `MissionTypes.enemy_total` + bosses, role shares, modifiers, tomb without gunners,
champion boss), `test_mission_ai` (fake time like `test_hive_ai`: rusher chase/strike timing scaled by windup_pct,
gunner keeps range and fires bolts, brute telegraph, target choice base/hostage/player seeded), `test_mission_rules`
(objective state machines: purge, defend timer and base HP, rescue free/follow/save/die, camp pylons, secondaries,
revives and the last down, quit, result dict exactly §5.5); flow `test_mission_flow.gd` (headless: start a spec per type
with a scripted player (hit_target calls) to a win and to a fail; `finished` once with a valid result; pause, settings
and quit; `where` arena; seeded repeatability: the same spec gives the same first-wave positions); render
`test_mission` (overview and phone worst view per level within §4, alive and skinned caps, idle rules, telegraph shader
absent on min, PNGs per biome).

**D:** unit `test_net_gate` (changed: `vpn_range` vectors 25.1.2.3 / 26.10.0.5 / 100.64.0.1 / 100.127.255.254 → ranges;
100.63.255.255, 100.128.0.0, 24.255.255.255, 27.0.0.1, "25.0.0", "" → ""; `::ffff:25.1.2.3` → hamachi; `is_private`
unchanged for them; `peer_allowed` table; `check_hello` with `my_ips`); `test_net_vpn` (`vpn_from` with fake
interfaces: rmnet 100.70.x skipped, tun0 100.88.x kept, "Hamachi" 25.x kept, "ham0" kept, "Radmin VPN" 26.x kept;
`join` refusals `no_vpn` / `not_lan` with `itfs_override`; `host` allowed with VPN only); `test_net_discovery`
(changed: a 25.x beacon is still ignored); `test_online_text` (new keys TH/EN, `no_vpn` formats `{vpn}`); render
`test_lobby` (changed: host card shows the VPN line and copy button with a fake net that reports `vpn_ips`, TH/EN,
phone); `test_lan_flow` and `test_friends_flow` unchanged and green (loopback is private).

## 8. Out of scope now

Co-op missions online; server-side coins, items and anti-cheat (next round; NET_SPEC §14 has the signed-item design);
spending coins (the reward dais stays "coming soon"); mission progression between planets; voice lines; Mini's
catastrophe music (the slot exists: `catastrophe.ogg`); internet relay play (NET_SPEC §13).

## 12. As built (each track fills only its own subsection)

### 12.A Core, galaxy, report, entries

As built on `t2-campaign` (track A, 15 Nov 2026). Everything in §1.1–§1.3, §1.5, §1.7 and §5.2 holds except the
points marked **changed**.

- **CampaignFlow** (`app/campaign_flow.gd`): `start`, `change_difficulty`, `launch`, `retry`, `back_to_galaxy` (new,
  the report's "กลับแผนที่กาแล็กซี" and its Esc), `leave`, `is_top(kind)`, `running()`. Every screen it opens carries
  the meta `campaign_screen` = `difficulty|galaxy|mission|report`; double presses are ignored (`start` while a campaign
  screen is on top returns it; `launch` while the mission is on top returns null; `chosen` from a screen that is no
  longer on top is ignored; `finished` is connected one-shot). `_on_finished` records the score once, sets
  `where = deck` and music `deck`, pops anything pushed over the mission (settings) and replaces the mission with the
  report; `score.repeat` (bool) is added for the report's note. `_start_mission` sets `where = arena` (C may set it
  too; same value). Tests point the screens elsewhere with `CampaignFlow.test_scenes`.
- **CampaignRules.estimate_coins(spec, repeat)** = `max((1000 + 500 + 300 × n_secondary) × score_x10 / 10 / 40, 10)`,
  then featured ×150 % and repeat ×25 % — equal to the coins of a clean win with every secondary and no kill/time bonus.
- **CampaignSave** now checks every field it reads (unknown difficulty, non-numeric weeks, non-number bests, non-true
  clears and non-dictionary history entries are dropped; the good parts are kept).
- **GalaxyScreen** (`ui/screens/galaxy_screen.*`): top bar (‹ ยาน, one rich text with title + coins + countdown, the
  difficulty chip = change difficulty), `GalaxyMap`, `PlanetCard`, `MissionBrief`, a note toast and a fade. Wide: the
  card/brief is a right panel (≤ 470 px) and the map sits left; narrow or portrait: a bottom sheet (42 % of the
  height) and the map above. Esc: brief → card → map → leave. **Changed:** back from a mission the brief closes and
  the planet's card shows (refreshed, the event marked cleared). The week check and the coins refresh on every show.
  Test hooks: `map() card() brief() card_open() brief_open() current_spec() countdown_text() coins_text() narrow()`.
- **GalaxyMap** (`ui/campaign/galaxy_map.gd`): background baked once per size with `GalaxyMap.bake` (arm light at
  256², cubic upscale, then 700–2600 hashed stars; cached in a static), markers and every icon drawn as **one triangle
  array** (`GalaxyMap.Pen` → `RenderingServer.canvas_item_add_triangle_array`) = one draw call for all 44 planets.
  Marker = faction-colour ring, dark gap, biome-colour core; gold star = featured; green check = cleared at this
  difficulty; small dots under a planet = its number of events. Drag pans (tap slop 12 px), wheel / pinch / magnify
  zooms 1×–3× around the pointer, tap radius ≥ 22 px. Redraws only on input, resize or data (`draws()` for tests).
- **PlanetCard / MissionBrief**: the planet name, biome, invaders (in the faction colour), featured line, "รีเซ็ตใน {d}
  วัน {h} ชม." and the events heading are one RichTextLabel; all event rows (background, border, icon, three text
  lines) are one `EventList` control (triangles + `TextParagraph`, bold pass then regular pass); the brief is an icon,
  one bold header text, one body text and ออกรบ. Close/back buttons on the panels are gold text only. This keeps the
  galaxy screen at ≤ 15 draw calls on min with the card or the brief open (measured 15; map alone 9).
- **ReportScreen** (`ui/screens/report_screen.*`): **changed title texts** "ผลภารกิจ: สำเร็จ / ล้มเหลว / ถอนตัว" (the
  plain "ภารกิจสำเร็จ / ภารกิจล้มเหลว" belong to track C's mission banner; a key may live in one fragment only).
  Six stat boxes (one control), the score lines as one rich text with a tab-stop value column, raw and multiplier,
  score, grade, +coins, featured / repeat notes, wallet. hi/mid count up with one Tween (1.0 s), lo/min none. On min
  the two secondary buttons are gold text only. Measured 19 draw calls (hi/mid/lo), 16 (min).
- **Deck station** as §1.2; the holo disc (core, four arms, rim, 44 amber planet dots) is drawn into `HallBuilder.holo_mesh`
  (no new mesh) and spins only on hi/mid in `holo.gdshader` (a vertex rotation for vertices above 1.4 m within 0.85 m
  of (5.5, −5.5)); lo/min use the plain holo material (no `TIME`). One soft holo `COOL_LIGHTS` entry at the disc.
  The deck's ring capacity is 17 (was 16). **Changed checks:** the spawn is 10.9 m from the projector's edge (the
  11.9 m of §1.2 is to its centre); camera for the projector view is yaw 0 (it stands toward −z).
- **Pack rooms**: `campaign` in `ACTIONS` and `CARD_ACTIONS`; `PackRoomScreen.open_campaign()`; campaign cards are
  primary (amber) buttons like online cards. PACK_SPEC §9.7 documents it.
- **i18n**: all new keys in `ui/i18n/campaign.json` (36) and `hall.json` (3); reused: "‹ กลับ", "เล่นอีกครั้ง",
  "ความแม่นยำ", "เป้าหมายหลัก", "สังหารศัตรู", "ความเสียหายที่ได้รับ".
- **Tests** (all new unless marked): unit `test_campaign_flow_unit` (stub screens in `tests/fixtures/campaign_flow/`),
  `test_campaign_rules` (+ estimate_coins), `test_campaign_save` (+ field checks), `test_hall_layout` (changed: nine
  ids, + `test_campaign_table`), `test_hall_text` (+ campaign), `test_hall_friends` (changed: 17 rings),
  `test_pack_rooms` (+ `test_campaign_action`, + `card_bad_action`); flow `test_campaign_flow` (deck → table → hard →
  galaxy → tap p00 → tap the event row → brief → ออกรบ → stub mission → report → Esc paths → deck; English; the fixture
  room's card and dropship), `test_hall_reach` and `test_lobby_flow` (changed: nine stations, the projector blocker);
  render `test_campaign_galaxy`, `test_campaign_report`, `test_hall` (changed: 11 labels, + the projector view).

### 12.B Difficulty screen and heroes

Built on branch `t2-hero` (from `t2-campaign` dbeb4f3).

- **Files.** `ui/screens/difficulty_screen.gd` (UI in code, `.tscn` unchanged); `scenes/campaign/hero_stage.gd`
  (`HeroStage`), `hero_light.gd` (`HeroLight`), `hero_kit.gd` (`HeroKit`: shared helpers of the built-ins: camera framing
  for 16:9 and tall cards, backdrop, glows, rim light, kit figures stepped by the scene), `hero_base.gd` (no class_name:
  the four built-ins extend it by path), `hero_normal|hard|veryhard|catastrophe.gd`, shaders `hero_backdrop`
  (screen-space gradient + glow), `hero_glow` (additive disc / light shaft / mist band / ring), `hero_rim` (rim light as
  `material_overlay`), `hero_shade` (top-light shading overlay for unshaded figures such as the egg). No `TIME` in any of
  them. `hero_loader.gd` gained `make_builtin(id)`. Fixtures: `tests/fixtures/campaign_pack/arena/campaign/catastrophe.ogg`
  (0.3 s silent stand-in) and `campaign_pack/broken/` (no camera, not a Node3D, setup that errors half-way).
- **Screen.** Wide (canvas width ≥ 1100 and landscape; the project stretches `canvas_items`/`expand` from 1280×720, so
  every landscape window, the 20:9 phone included, is wide): 4 cards in a row. Portrait windows: one card at a time with
  4 tabs, ‹ › buttons and left/right swipes (touch arrives as emulated mouse). Card = hero stage, name + score badge
  (bold, one size), blurb, what-changes line (`ศัตรู ×1.4 · ทน ×1.3 · แรง ×1.3 · เร็ว ×1.1`, computed from
  `CampaignRules.DIFFICULTY`; normal says `ศัตรูค่าปกติ ไม่มีตัวคูณ`), revives line (`ลุกได้ {n} ครั้ง` / `ลุกได้ 1 ครั้ง` /
  `ล้มแล้วจบ` in red), and the `เลือก` button **on the selected card only** (decision: keeps `min` at 23–24 draw calls
  against the §4 limit of 30; a tap selects any card, a second tap or the button confirms). Info boxes are evened so
  all scenes are the same height. `chosen` fires at most once per frame (`choose` re-arms on the next idle frame, so a
  key and a button in the same frame do not double-fire). Buttons use `FOCUS_NONE`; keys come through
  `_unhandled_input` (`move_left/right`, `ui_left/right`, `interact`, `ui_accept`).
- **Stage.** `SubViewportContainer` (stretch) + own-world `SubViewport`; 3D resolution through
  `scaling_3d_scale` (bilinear; measured to work in Compatibility) = hi 1 / mid .75 / lo .5 / min .5. Live = hero
  `set_active(true)`, viewport `UPDATE_WHEN_VISIBLE` (lo: `UPDATE_ONCE` from a 33 ms `Timer`; a hero whose optional
  `animated()` says false is drawn once). Still = build, wait 2 frames, `UPDATE_ONCE`, read the texture on
  `frame_post_draw` (headless: no read, the card shows a dark placeholder), keep an `ImageTexture`, free the hero **and
  the viewport**. Stills are made one at a time (the screen chains them on `still_ready`; a hidden card defers its
  still until shown). Deselecting a card re-shows its cached poster (re-rendered only if the card's shape changed by
  > 15 %). A pack hero that sets up no camera of its own (wrong script, runtime error in `setup`) is freed and the
  built-in one is used (`fell_back`).
- **Built-ins.** All four step their kit figures manually (`KitBeast` `manual`), so an inactive hero has no
  per-frame work at all; `seek(t)` replays the timeline from 0 in 1/30 s steps (stills and tests get the same pose every
  time); `poster_t()` is the still; `set_active(true)` restarts the scene (`start_t()`). Optional extras on the contract:
  `animated()`, `seek()`, `poster_t()` (the stage only uses `animated()`, and only when present).
  - normal: `ArenaActors.player_figure(sel)` + `Figures.dress(scheme_of(sel))`, turned 0.42 rad (a shield or rifle held
    across the body would hide the face at 0), head from the skeleton's rest `head` bone; egg / unskeletoned figures are
    framed whole. Top light (`sun_dir` (0, 1, 0.15)), cool rim, faint light shaft, grey glow above the head on black.
    hi/mid idle at 0.6 and a slow 3.5 % camera push.
  - hard: knight / kcapt / kblade (KitWalker) in `Figures.scheme("blue")`, captain in front, sides 0.8 m back turned
    20° in (tall cards: closer and deeper), low camera, cool key from the right, blue rim from the left, blue floor pool
    and mist; hi/mid idle with offset phases and a slow camera sway.
  - veryhard: pike_halb (KitFighter) — **secondary colour 8f97a8 instead of 3b4250** (the pike_halb kit is nearly all
    cloth, so the spec's dark secondary made it read as a robed soldier, not a silver knight); 4 hounds (3 on lo) run in
    from the sides, the knight spins 360° in 0.45 s on the scene's own timeline (not a Tween, so it can be seeked) with
    `swing_1`, an additive blade-trail arc and a ground shock ring; the aliens flash white, play `die_*` at 1.5×, slide
    back, sink and the loop restarts every 4.0 s. Still = mid-spin (t 1.6).
  - catastrophe: dmc cxp cxb cxl cxs cxw dmr, appearing outside-in (cxl last) 0.35 s apart: light ramps up from a black
    silhouette, the red rim flashes, a red light pillar fades; red back light, red horizon glow, fog on hi/mid
    (exponential 0.035), drifting mist bands; holds to 8 s, fades and replays every 9.2 s. Music: `AudioStreamPlayer`
    with `CampaignHeroes.music_path()` (duplicated stream, `loop` on, bus `Music`), plays on `set_active(true)` except
    on min, stops on `set_active(false)`.
- **Measured** (xvfb, llvmpipe; live hero alone at its poster pose): normal 7 draws / ≤ 1k prims, hard 10 / 6.7k,
  veryhard 15 / 7k, catastrophe 19 / 15k (all levels). Whole screen: hi 30–33 / ≤ 10k, mid 32 / 7k, lo 36 / 10k,
  min 23–24 / ≤ 3.2k.
- **Tests.** unit `test_campaign_heroes` (extended), `test_difficulty_text`; flow `test_difficulty_flow`; render
  `test_campaign_heroes`, `test_difficulty_screen`.
- **Open.** Mini's catastrophe music overlaps the deck music (spec §1.1 says the card lowers nothing); integration may
  want to duck `/root/Music` while the catastrophe card is live. The public app's default figure is the egg, so most
  public players see the egg in the normal card.

### 12.C Missions

**For the owner, in Thai:** ภารกิจเดินยิงใช้ระบบเดียวกับห้องทดลองอาวุธ (ตัวที่แต่งในห้องแต่งตัว กล้องข้ามไหล่ ปืน หมัด ดาบเลื่อย พุ่งหลบ)
สนามรบ 44 × 44 ม. สุ่มจากดวงดาว (ซากเมือง ป่าดงดิบ ทะเลทราย ทุ่งน้ำแข็ง ภูเขาไฟ หนองพิษ) ทุกเครื่องได้สนามเดียวกันเมื่อเป็นภารกิจเดียวกัน
ศัตรูมาเป็นระลอกตามฝ่ายที่บุกดาว (ฝูงเอเลี่ยน ออร์คเขียว ลัทธิมืด อัศวินทรยศ เครื่องจักรโบราณ โจรเงา กองทัพปีศาจ กองทัพสุสาน)
วิ่งเข้าฟัน ยิงกระสุนช้าที่หลบได้ อ้อมโอบ หลบหลังของบัง สะดุ้งเมื่อโดน · มุมขวาบนบอกเป้าหมายหลัก/รอง เวลา ฐาน ตัวประกัน
และจำนวนครั้งที่ลุกได้ · ระลอกใหม่มา = พลังชีวิตเต็ม · จบแล้วส่งผล (สังหาร ความแม่นยำ เวลา ความเสียหาย การล้ม เป้าหมายรอง) ให้หน้าสรุปผล

**Files.** `scenes/campaign/`: `mission_types.gd` (tuned table), `mission_roster.gd` (+ `stats()`), `mission_layout.gd`,
`mission_waves.gd`, `mission_ai.gd`, `mission_objectives.gd`, `mission_builder.gd`, `mission_enemy.gd`, `mission_hostage.gd`,
`mission_pylon.gd`, `mission_world.gd` + `.tscn`; `ui/screens/mission_screen.gd` + `.tscn`; `ui/campaign/mission_hud.gd`;
`ui/i18n/campaign_mission.json` (+34 keys); tests `tests/unit/test_mission_{layout,waves,ai,rules,text}.gd`,
`tests/flow/test_mission_flow.gd`, `tests/render/test_mission.gd`, fixture `tests/fixtures/campaign_missions/specs.gd`.
No shared file outside track C was edited.

**As built (decisions and changes against §2.4/§5.4, all inside track C):**

| Topic | Built |
| --- | --- |
| Field | `MissionLayout.build(spec)`: 44 × 44 m (x, z in ±22), cliffs as 4 shell walls; player spawn (x ±4, z 18.5; defend z 9.5) facing −z (camera yaw 0); pickup (z 15); base (z 1–4, a blocker core r 1.2 that the camera collides with); beacon (x ±11–15); camp (z −10.5…−12.5) with a stake palisade r 8.5 (three gaps); 3 rescue hostages in the north third (shuffled columns); the caged secondary hostage and the outside pylon on the far side from the beacon; 9 edge spawns (5 north, 4 sides), 4 ambush spawns 9–14 m from the player, 8 camp guard posts. Cover per biome (18–28 pieces: rocks, boulders, low/high walls, crates, trees, spires, barrels), axis-aligned, ≥ 2.4 m apart, kept off every key point; taller than 1.8 m = shell layer (the camera arm collides), lower = prop layer. Reachability is checked on a 1 m grid with 0.6 m clearance (the same rule as the world's `ArenaPath(bounds, blockers, 0.5, 1.0)`); an unreachable key point removes the cover piece nearest to it (deterministic). Gunner cover posts = 1 m behind each low cover piece. Decor (visual only) is drawn after the blockers from the same RNG. |
| Meshes | `MissionBuilder.meshes`: ground (12 × 12 colour grid + decor) and props (cliffs, cover, palisade, base, pickup pad, beacon mast, ritual circle) = 2 draw calls, vertex colours with baked sun shading, `HallBuilder.material()`. Sides hi 10 / mid 8 / lo 6 / min 5; static ≈ 1.8–3k triangles. Pylons (`pylon_mesh` / `rubble_mesh`) and cages are their own small meshes. No `TIME` shader anywhere. |
| Waves | `MissionWaves.plan`: weights 2, 3, 4… per wave, remainder in the last; no brutes in the first wave of a multi-wave mission; bosses per type (purge 1, defend 1, rescue 0, destroy_camp 1) + champion 1, in the last wave; gunline doubles the gunner share; factions without gunners give the share to rushers; camp guards (6 × count_pct, 30 % gunners, always `cult`) are a first entry with post `camp` (not in `enemy_total`); rescue's first wave guards the hostages (post `hostages`); ambush: the first wave uses the near spawns. Timing: purge after each clear; defend 3/30/62/96/130 s; rescue 0 and 90 s or after a clear; destroy_camp 0 and 120 s or after a clear. Guards (posts) stand until the player comes within 13 m or they are hit. |
| AI | `MissionAI` (pure, seeded per enemy = `spec.seed ^ salt ^ n·7919`): idle 0.2–0.7 s, chase on the path, rushers/brutes/bosses wind up (`windup × windup_pct`) then strike (±70° cone, reach + target radius), recover 0.6 s; gunners aim (`windup`) and fire a slow bolt (12 m/s, dodgeable, blocked by cover rays), cool 1–1.6 s with a side-step, back off under 5 m, walk in without line of sight, prefer a cover post that still reaches the target. Flank share per difficulty (10/25/40/55 %): flankers aim 5 m beside the target while farther than 7 m. Flinch: light roles on 50 % of gun hits and every melee hit, heavy roles on melee only; poise 1 s / 2.5 s. Target choice weighted player 6 / base 4 / following hostage 2.5, re-rolled every 4 s or when the target dies. |
| Enemies | `MissionEnemy`: layer 8, mask **1 \| 2 \| 4 \| 8** (changed from §5.4's 1 \| 4 \| 2: enemies also collide with each other and with pylons, so a swarm does not merge into one body). Figures: `fighter` factions → `KitFighter` (gunners hold the aim pose and recoil), `beast` factions → `KitBeast` claw clips; the attack clip speed is set so the blow lands at the end of the windup; no kits → the KitBeast egg tinted in the faction colour and scaled per role; swarm brute → the pack enemy when a pack exists. The world steps every living enemy from its own `_physics_process` (enemies have none), ≤ 2 repaths per physics frame in rotation, corpses removed after 3 / 2.5 / 1.8 / 1.2 s. Telegraph: the arena's `telegraph.gdshader` (no `TIME`) on hi/mid/lo, one shared flat red material on min, shown only while winding up. min: figures farther than 25 m from the camera stop animating. `hit_target` returns id **`&"beast"`** for enemies (so `ArenaPlayer`'s red crosshair works unchanged) and `&"pylon"` for pylons. |
| Caps | Alive at once = min(`ALIVE_CAP` 14/10/7/5, `SKINNED_CAP` 24/16/10/8 − player − living hostages − corpses): with three hostages on min only 4 enemies live at once; totals never change. |
| Objectives | `MissionObjectives` (pure): purge = every planned enemy (bosses included) dead; defend = 180 s with the base above 0 (base takes enemy damage × 150 %); rescue = free each hostage by standing in its 1.6 m ring for 1.5 s after E (leaving the ring cancels), they follow the player's trail (4.2 m/s, 1.4 m apart, no collision, 120 HP, enemies may target them), a hostage inside the 2.6 m pickup ring is saved; win when every living primary hostage is saved (≥ 1), fail when all die or after 600 s. **destroy_camp needs extraction** (the owner's request: "destroy the shrine objects, then extract"): after the three pylons (400 × hp_pct) fall, walk into the pickup ring to win. Secondaries: kill ⌈75 %⌉ of the whole plan (guards included); the beacon (E inside its 2.4 m ring, then 30 s inside in total); the caged hostage brought to the pickup; the outside pylon. |
| Player | `ArenaPlayer` set up exactly like `ArenaWorld._spawn_actors` (dressing-room figure + scheme), always in shoot mode. Downed with revives left → it gets up after 2 s and is moved to the checkpoint (the player spawn; the last freed hostage's spot in rescue); the down after the last revive fails. Each new wave (after the first) heals a standing player to full and refills the rifle (there are no pickups on the field). Shots = drops of `in_mag` while not reloading; hits = `hit_landed` with kind `gun`; damage taken = `hurt` amounts. |
| Screen | Fade in → banner (mission name + goal) 2 s, the world starts only then (nothing spawns before) → play → win/fail banner 1.5 s → fade → `finished(result)` once. `‹ หยุด`, Esc / back and losing focus open the pause panel (resume / settings / leave the mission with a confirm). `where = arena`, music `battle`. HUD: `ArenaHud` (crosshair, HP, ammo, numbers, touch buttons; `world.enemy` = null so its single-enemy bar stays hidden) + `MissionHud` (objective panel top right, boss bar top centre, hostage-freeing bar, banners). Toasts: wave incoming (+ health restored), boss, freed, saved, hostage killed, pylon destroyed, extract, base under attack (≤ 1 per 6 s), revive left, last life, secondary done, beacon on. |
| Test hooks | `MissionWorld.simulate(seconds, dt)` steps the whole world synchronously; `test_god` makes the player immune to enemies (scripted wins). |

**Budgets measured** (`tests/render/test_mission.gd`, xvfb + Mesa, kits installed, `kit_kblade` as the figure):

| View | hi | mid | lo | min |
| --- | --- | --- | --- | --- |
| Overview (catastrophe horde, capped first wave in view) | 32 / 15.8k | 28 / 12.1k | 25 / 9.5k | 23 / 7.9k |
| Phone worst (20:9, touch, 3 hostages following, firing, numbers, toast) | 37 / 14.7k | 37 / 14.5k | 34 / 13.1k | 28 / 9.6k |
| Alive / skinned at most | 14 / 15 | 10 / 11 | 7 / 10 | 5 / 8 |

**Tests.** Unit: `test_mission_layout` (purity; 50 seeds × 6 biomes × 4 types, secondaries on every 4th seed: bounds,
outside blockers, reachable; ArenaPath agrees on a sample), `test_mission_waves` (every spec of week 2967 at all 4
difficulties: totals = `enemy_total` + bosses (+ guards); shares, gunline, tomb, horde, champion, catastrophe, ambush,
timing per type, `MissionRoster.stats`), `test_mission_ai` (chase/windup/strike timing incl. catastrophe 70 %, brute
telegraph, gunner range/fire/cooldown/back-off/line of sight/cover post, flinch and poise, weighted seeded targets, guards,
flankers, strike cone, determinism), `test_mission_rules` (all objective machines, secondaries, revives, quit, §5.5 keys),
`test_mission_text` (every Thai string TH/EN, HUD lines in both languages). Flow: `test_mission_flow` (each type to a win
and to a fail; the real rifle and fist against an enemy; pause, settings, quit with confirm; `finished` once; result
keys exactly §5.5 and `CampaignRules.score` accepts them; the same spec spawns the same first wave). Render: `test_mission`
(per level overview + phone worst within §4, caps, no `TIME` on lo/min, no telegraph shader on min, far figures still on
min, paused = nothing processes, English HUD without Thai, a PNG per biome).

**Open points.** Enemy art comes from the battle-table kits only (no private-pack enemies except the swarm brute's
existing arena mapping); the fighter kits' melee uses the swing clips at a scaled speed (fine at a distance, not
synchronised per kit); bolts are simple glowing boxes; hostages pass through cover while following (they walk the
player's trail); online co-op missions are out of scope (§8).

### 12.D VPN joins
