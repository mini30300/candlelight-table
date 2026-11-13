# DATA.md — the data contract of `godot/`: schemas, the data lint, the server data generator, the D&D layout JSON and the DM act vocabulary

Companion of `docs/GODOT.md` (module map) and `godot/data/README.md` (what each exported table means). Everything here
is R0-F of `docs/PLAN.md`; ARCHITECTURE §4 (data), §9 (D&D side) and §13 (hard rules) are the contract this file spells out.

## 1. What lives where

| Path | What | Written by |
| --- | --- | --- |
| `data/*.json`, `data/rules_summary.md` | the battle table's tables, cut out of `battle-table.html`; `types.json` also carries `inf` (the page's `INF(k)`) on every datasheet | `tools/export_data.js` (never by hand); `node godot/tools/export_data.js --check` compares a fresh export with `data/` byte for byte (local only: needs Node, Playwright and Chromium) |
| `data/schema/*.json` | one JSON Schema (draft 2020-12 vocabulary) per table shape: `unit.json`, `weapon.json`, `army.json` (+ `$defs/core`), `theme.json` (+ `$defs/table`), `ability.json`, `i18n.json`, `map_layout.json`, `monster.json`, `tables.json` (every other table, `version`, `bt2_snapshot`, `bt_data`) | by hand; every field a table carries must be in its schema (`additionalProperties: false` everywhere) |
| `data/schema/legacy_tokens.sha1` | SHA-1 baseline of the old identifiers that carry a word of AGENTS.md rule 1 | `validate_data.py --write-legacy`, in a dedicated PR only |
| `data/version.json` | `rules_ver` 10 (the new app), the page's `APP_VER`/`RULES_V` the export came from, `data_hash` = sha256 of every `data/*.json` except itself, concatenated in sorted file-name order | `validate_data.py --write-version` |
| `data/bt2_snapshot.json` | the Worker's `BT_RULES`, `BT2` (its copy of every datasheet, keyed by unit key, weapon names in English), `BT_ARMY_EN`, `BT_THEMES`, `BT_TERRAINS`, `BT_LIST_LEN`, `BT_MAX_ACTS`, `BT_MAX_PLAYERS` and the sha256 of the worker file | `gen_bt_data.py --worker PATH` |
| `data/bt_data.json` | the payload the new app will want from the server: datasheets with English names and ability text, English army names, themes, terrains, phases, stratagems, the ability registry | `gen_bt_data.py --snapshot` |
| `tests/data_fixtures/` | planted inputs for the lint and the generator (see its README) | by hand |

Values: every rules number is an integer. The only floats in a datasheet are the base radius `r` (converted once to MI by
`core/data.gd`) and, outside the rules, the visual tables (theme relief, flight heights, tracer widths, sky angles).
A JSON `2.0` is **not** an integer for the lint: the rules core never sees a float.

## 2. The lint: `tools/validate_data.py`

```bash
python3 godot/tools/validate_data.py                 # all checks, < 10 s, exit 1 on any failure (CI runs this)
python3 godot/tools/validate_data.py --fixtures      # only the planted fixtures
python3 godot/tools/validate_data.py --write-version # after any change under data/: rewrites version.json (+ core/version.gd DATA_HASH)
python3 godot/tools/validate_data.py --base origin/main   # compare the types.json order against another revision
```

| Check | What fails | How to fix |
| --- | --- | --- |
| `schema` | a table that has no schema, a field the schema does not know, a float where an integer belongs, a value out of range; cross-table: a `fac`/`spawn.k`/`lk`/`ch`/`fx` that points nowhere, a bot pool with an unknown or hidden unit, a kit key with no unit, a Thai display string (unit/weapon/army names and blurbs, theme, terrain, team, phase, stratagem, chapter, skin names) that is not a key of `i18n_en.json`, an English value that still contains Thai (the language name `ไทย` is the one allowed exception) | fix the page and re-export, or extend the schema in the same PR when the shape really changed |
| `names` | a name from AGENTS.md rule 1 anywhere under `godot/` (text files and file names; case-insensitive; the distinctive names as substrings, the ones that are also ordinary English words — the orcs' old spelling, the blue-skinned empire's old name, the faction word, the titan/knight class words — whole-word only). Godot's upper-case 2π constant is not a hit. `.md` files may name the companies to restate the rule. The seven legacy tokens in the baseline (old unit keys such as the titan classes, and two weapon names in the server's `BT2`) are allowed only inside `data/*.json`, `data/schema/` and `tests/` | rename; never add a new one. The baseline is a hash list so the file does not spell the words; regenerate it only in a renaming PR |
| `i18n` | a Thai string literal in `ui/**` or `app/**` (`.gd`, `.tscn`; comments skipped) that neither `ui/i18n_extra.json` nor `data/i18n_en.json` (nor a `const EN` dictionary in `ui/i18n.gd`) covers. A literal passes when it is a key as a whole, or when removing every known key (longest first, like `BT_I18N.tr`) and the `{n}`/`%d` placeholders leaves no Thai character | add the pair to `ui/i18n_extra.json` (new-app strings) — page strings get added in the page and re-exported |
| `order` | `data/types.json` whose key sequence is not the previous commit's sequence plus appended entries (compared with `HEAD`, or `HEAD~1` when the working file equals `HEAD`'s; in a PR run `HEAD~1` is the base branch) | append only; the array index is the army-list protocol |
| `dice` | a datasheet that could need more than 60 dice in one roll, or a non-integer dice count. Worst case per weapon = models × (`a` + `rf` + 1 if `ca` and melee + ⌊largest squad ÷ 5⌋ if `bl`) hit dice; ×2 for the wound roll when `su` or the fallen knights' pact (`cx`, melee) can turn a 6 into an extra hit; saves never exceed wounds. Today's worst is exactly 60 (`dmc` melee: 10 × 3 × 2) | the Worker cuts dice arrays to 60 and the fallback stream fills the rest deterministically (ARCHITECTURE §4), but a datasheet must never rely on that |
| `secrets` | private-key blocks, GitHub/AWS/Google/Slack/API tokens, JWTs, `api_key = "…"`-style assignments, a non-empty `keystore/*` field in `export_presets.cfg`, or a `.jks`/`.keystore`/`.p12`/`.pem`/`.key` file | remove it; keys live only in GitHub Actions secrets (AGENTS.md rule 2) |
| `version` | `data/version.json` missing or stale, or `core/version.gd` `DATA_HASH`/`RULES_V` disagreeing | `--write-version`, commit the result |
| `fixtures` | a planted fixture that does not fail, a good sample that does, or `gen_bt_data.py --self-test` failing | see `tests/data_fixtures/README.md` |

CI: the `test` job of `.github/workflows/godot.yml` runs `python3 godot/tools/validate_data.py` before the unit tests
(no Godot needed). `--root DIR` lints another `godot/`-shaped folder (the fixtures use it internally).

## 3. The server data generator: `tools/gen_bt_data.py`

```bash
python3 godot/tools/gen_bt_data.py --worker ../candlelight-server/worker.js   # Worker -> data/bt2_snapshot.json
python3 godot/tools/gen_bt_data.py --snapshot                                  # data/*.json -> data/bt_data.json
python3 godot/tools/gen_bt_data.py --self-test                                 # the fake worker fixture
```

The Worker's tables are JavaScript literals (bare keys, single quotes, trailing commas, comments), so the script carries
a small literal parser; anchors are matched only at the start of a declaration line and outside strings, because the
Worker also embeds the whole web pages as one-line string constants. `BT2` is compared with `types.json` field by
field (`--strict` turns differences into errors); the Worker does not carry the page-only fields `veh`, `ch`, `sec`,
`lk`, nor the exporter's derived `inf`, which are skipped. After a datasheet change the order is: page → `export_data.js` → `--write-version` → server
PR (`BT2`, `BT_RULES`) → `gen_bt_data.py --worker` → commit the snapshot; **candlelight-server merges first**.

`bt_data.json` is what a future server endpoint would serve the new app (R3): `armies[]` (English names from
`bt2_snapshot.json`'s `BT_ARMY_EN`, else from `i18n_en.json`), `order[]` (the protocol), `types[]` (each datasheet plus
`en`, `d_en`, weapon `en`, `abilities` in English like the Worker's `bt2Abilities` and `abilities_th` like the page's
`abilityText`), `abilities[]` (the registry below), `themes`, `terrains`, `phases`, `strats`. Hidden units are carried
as-is with their opaque flags.

### The ability registry (`schema/ability.json`)

One entry per unit flag, aura kind (`aura:hit`, `aura:ld`, `aura:bless`, `aura:rez`, `aura:veil`), weapon keyword
(`as hv rf pi su tr bl mk` on guns, `la` on melee, `lh dw po fx trail` on both), army-wide rule (`el de cx ta kn`)
and hidden flag (`sec`, `lk`): `key`, `kind`, `value` (`flag`/`int`/`string`/`object`), optional `applies`, `th`, `en`
with `{v}` for the value. `core/battle/abilities.gd` maps every key to a handler and has one unit test per key.

## 4. The D&D layout JSON (`schema/map_layout.json`, ARCHITECTURE §9)

Produced by `core/dnd/mapgen/` from `(seed, kind, size)` with integer generators, so every device regenerates the same
map; the server stores only `board.map = {seed, kind, ver, edits[]}`. Coordinates are cells (1 cell = 1 unit = 5 ft),
`x` east and `z` south from the north-west corner, all integers; `v` is the format version (1).

| Field | Type | Meaning |
| --- | --- | --- |
| `seed` | int 1..99999 | generator seed (same range as the battle table) |
| `kind` | `dungeon` `cave` `ruins` `town` `wild` `scene` | BSP rooms + corridors + loops; cellular automata; grid with yards; noise with rivers and paths; a prefab scene from the page's `SCENES` |
| `size` | `[w, h]` 4..256 | cells |
| `tiles` | RLE `[[id, run], …]` | tile per cell, row-major: 0 void, 1 floor, 2 wall, 3 water, 4 pit, 5 door, 6 stairs; runs add up to `w*h` |
| `heights` | RLE | height step per cell 0..15 (half a unit each); walls take their floor's step |
| `layers.fog` | RLE | 0 unexplored, 1 revealed, 2 revealed and lit; the DM's `dm.reveal` writes here |
| `layers.light`, `layers.mark` | RLE, optional | cached light level 0..15 (derived, visual); DM marks 0 none 1 danger 2 loot 3 note |
| `rooms[]` | `{id, kind, rect:[x,z,w,h], tags[]}` | kinds `room hall vault lair shrine cell yard cavern clearing camp entry boss`; tags are generator words (`start`, `dark`, `flooded`, `trapped`, `locked`) |
| `corridors[]` | `{id, path:[[x,z]…], width 1..3}` | cell centres in walking order |
| `doors[]` | `{x, z, state, dir 0..3, room}` | `open closed locked secret broken`; dir 0 N 1 E 2 S 3 W |
| `props[]` | `{id, k, x, z, rot 0..3, h}` | prop kind from `assets/props`, quarter turns, height-step override; at most 480 (PROP_CAP) |
| `lights[]` | `{id, x, z, r 1..32, col:[r,g,b], flicker 0/1}` | at most 64 |
| `spawns[]` | `{kind, x, z, group, key}` | `party monster boss npc loot trap`; the party's entry is group 0; `key` fixes a monster or item |
| `exits[]` | `{x, z, kind, to}` | `stairs_down stairs_up door edge portal`; `to` = depth or scene index, `null` = unknown yet |
| `labels[]` | `{x, z, th, en}` | every Thai label carries its English pair (rule 4) |
| `edits[]` | `{seq, a, …}` | the DM's deltas replayed in `seq` order: `tile`/`height` (x z v), `fog` (x z w h v), `door` (x z state), `prop` (id k x z rot), `prop_del` (id), `light` (id x z r col), `light_del` (id), `label` (x z th en) |

Tested on 200 seeds in CI (R4): connectivity of every floor cell to the party spawn, minimum spawn distance, doors on
room edges, runs adding up. `tests/data_fixtures/ok/data/map_layout_sample.json` is a complete 8×6 example.

## 5. The DM act vocabulary (ARCHITECTURE §9)

Every DM action is an act in the room's act log — `{seq, pid, a, …}` as in ARCHITECTURE §4 — so it replays, logs and
can be undone with a reverse act. Positions in acts are integers: cells when the room has a layout, otherwise tenths
of a board unit (−200..200) that map exactly to the Worker's 0.1-rounded board coordinates (±20). Strings are capped
as the Worker caps them. The existing Worker (R4) already accepts the tools marked *Worker*, through the room's `dm`
action (owner only, room created with `setup.dm = "host"`; the same tools Claude uses over MCP); the rest are carried
in the act log and need the server work noted (R4-S1).

| Act | Fields | Who | Validation | Transport |
| --- | --- | --- | --- | --- |
| `dm.narrate` | `text` (1..600), `choices[]` (≤4 × ≤80) | the DM (owner, or Claude via MCP) | text not empty | Worker `narrate` |
| `dm.scene` | `scene` (`tavern forest cave ruins field village dungeon mountain camp road`), `time` (`day dusk night`), `map` `{seed, kind, size}` optional | DM | scene in the list; `map` only with a layout-capable client | Worker `set_scene` (scene, time); `map` → `board.map` (R4-S1) |
| `dm.place` | `id` (optional: edit that token), `name` (≤40), `kind` (`npc enemy object`), `x`, `z`, `hp`, `maxHp` (1..999), `look` (the Worker's look keys) | DM | never a player token; ≤40 non-player tokens; `0 ≤ hp ≤ maxHp`; unknown look values fall back to the first value | Worker `place_token` |
| `dm.move` | `id`, `x`, `z` | DM (any token, players included: the DM moves the party) | token exists; in combat a player token moves only on its turn unless the DM moves it | Worker `move_token` |
| `dm.remove` | `id` | DM | not a player token | Worker `remove_token` |
| `dm.combat_start` | `order[]` of `{id, init}` | DM | every id exists; at least one; `init` int | Worker `start_combat` → `board.mode = combat`, `combat = {order, turn 0, round 1}` |
| `dm.combat_next` | — | DM | in combat | Worker `next_turn` (wraps turn, bumps round) |
| `dm.combat_end` | — | DM | in combat | Worker `end_combat` → `mode = explore`, `combat = null` |
| `dm.roll_ask` | `who` (pid or `all`), `die` (4 6 8 10 12 20 100), `reason` (≤80), `dc` optional | DM | die in the list | act log only; the Worker relays it as a `sys` line (R4-S1) |
| `dm.hp` | `id`, `hp`, `maxHp` optional | DM | `0 ≤ hp ≤ maxHp` | Worker `place_token` with id + hp for non-player tokens; player tokens need the host-DM path (R4-S1) |
| `dm.reveal` | `x`, `z`, `w`, `h`, `v` (0 1 2) | DM | inside the layout | layout edit `fog` (R4-S1) |
| `dm.map_edit` | one `edits[]` entry of §4 | DM | per the edit's required fields | `board.map.edits[]` (R4-S1) |
| `dm.undo` | `seq` | DM, own acts only | the act exists and is the DM's; the core builds the inverse from the state before `seq` | the inverse act is sent as a normal act |

Player acts mirror the Worker's player actions and are listed for completeness: `pc.say` (`text` ≤600, `rolls[]` ≤10),
`pc.roll` (`die`), `pc.hp` (own token), `pc.move` (own token, on its turn in combat), `pc.look` (`name` ≤24, `look`),
`pc.ready`, `pc.reroll` (`race cls stats all`, at the campfire), `pc.leave`.

The board JSON both apps render is the Worker's: `{scene, time, tokens: {id: {id, name, kind, x, z, hp, maxHp, look}},
mode: explore|combat, combat: {order[{id, init}], turn, round} | null, seq}` with `kind` `player npc enemy object` and
`look` keys `hair hat faceShape face body clothes race weapon cloak` plus the colours `hairColor skin tunic cloakColor
accent` (`#RRGGBB` or null).

## 6. The bestiary stub (`schema/monster.json`, R5)

`{k, nm{th,en}, d{th,en}, kit, scale %, palette{material: rgb}, stats (the `unit.json` stats block: n mv T sv inv w ld oc r
gun mel + flags), tags[], ai (ambusher stalker brute swarm caster), cr, loot}`. Fields may be added in R5, never renamed;
`tests/data_fixtures/ok/data/monster_sample.json` is the reference example. Content is designed with the owner first.
