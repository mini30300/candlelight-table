# R1 port spec — the battle rules core v10 (`godot/core/battle/`)

Status: authoritative contract for the R1 rules-core agents (PLAN.md R1-A…E). Written by the R1 architect from the old
page `app/src/main/assets/battle-table.html` (APP_VER 9.4, RULES_V 9; line numbers of this checkout, they drift — grep the
function name), ARCHITECTURE.md §2–§5 and §10, CODEMAP.md §2.5–§2.9, `godot/data/README.md`, the Worker
(`../candlelight-server/worker.js`, `btPost` act sanitiser and `btBoard`) and four area reports (army/squads,
combat/pend, turn/moves/bots, net/acts/hook). Where this file and ARCHITECTURE.md disagree, this file wins for R1 and
the difference is listed in §7 or in the decisions table (§9) so `docs/GODOT.md` can carry it.

`core/battle/state.gd` (`BattleState`) and `tests/unit/test_state.gd` exist already (wave 0). Everything else in §1 is
to be written.

Contents: §0 conventions · §1 module map · §2 integer conventions · §3 RNG · §4 act codec · §5 board state ·
§6 oracle replay · §7 intentional v10 differences · §8 implementation order · §9 decisions and open questions.

---

## 0. Conventions used in this file

- **MI** = 1/1000 inch (int64). **Q16** = 65536 per unit (fractions and radians). `d2` = squared distance in MI²
  (`Fx.dist2`). **The page's `dist2(a,b)` (31076) is a plain distance (`Math.hypot`)**, not a square: never port it as
  `Fx.dist2`.
- Page `gx(u)`/`gz(u)` = the rules position. In v10 `BattleState.Unit.x/z` **is** the rules position; walking is a view
  matter (`table/figures/walker.gd`). The page's drawn `x/z` and `rot` have no counterpart in core.
- In the signatures below `Squad`, `Unit`, `Pend`, `Seat`, `Obj` stand for `BattleState.Squad`, `BattleState.Unit`,
  `BattleState.Pend`, `BattleState.Seat`, `BattleState.Obj` (write them qualified in code); `Ev` stands for
  `Array[Dictionary]` (the events out-parameter, always last; events are `Events.make(...)`); `P2` stands for
  `PackedInt64Array` of length 2 (`[x, z]` in MI). Every module is `class_name Bt<Module> extends RefCounted` with
  `static func`s only and takes `st: BattleState` first. snake_case names, ints only.
- "≤ X + 0.001" on the page becomes `d2 <= (X_mi + 1)²`: the page's 0.001" **is** 1 MI, so these are exact
  translations, not a tolerance change. A strict `<` stays strict.
- Every "best" scan keeps the page's rule: strict comparison, the first index wins ties. Every JS `sort` becomes
  `Fx.stable_sort` with an index tie-break. There is no `for…in` over rules state in the ported range (the only one,
  `fitSkin` 29978, builds a set).
- Thai strings never live in rules code: a "why not" or a log line is a message key plus int/String args
  (`{"key": "…", "args": [...]}`, `""` = allowed). The UI maps keys to the page's Thai text and `I18n` gives English.

---

## 1. Module map

Dependency order (an arrow points to what a module may call):
`state ← offsets ← blocking ← squads ← {army, objectives, combat, strats, abilities} ← pend ← moves ← turn ← board ←
acts ← {roller, bot} ← battle`. No module calls one to its right; `abilities` may call `blocking` and `squads`;
`pend` calls `abilities` handlers; `turn` calls `pend`, `abilities`, `objectives`, `army`. Nodes, floats, trig and
engine RNG are forbidden everywhere (purity lint); `GameData` is the only data access.

ARCHITECTURE §1 put `offsets.gd` and `objectives.gd` under `core/field/`. They move to `core/battle/` (as does
`blocking.gd`): all three need the battle's units (`crowded`), and `core/field` stays unit-free. `FieldProps`
keeps generation only; `BtBlocking` turns its items into the blocking shape.

### 1.1 `state.gd` — `BattleState` (exists)

The data model; no rules. Read the file: typed inner classes `Seat`, `Unit`, `Squad` (all turn flags, `vs`, `mk`,
`wind_n`, `opened`, rules facing `fx/fz`, derived `models` in units order), `Obj`, `Pend` (one class for every PEND
kind; stage/kind ints with name tables `KINDS`, `STAGES`, `HOWS`, `PHASES`, `GOALS`). Setup fields (`seed, w, d,
theme, terrain, buildings, density_h, mode, teams, per_team, budget, free_fire, clock, goal, rounds`), match fields
(`on, over, round_no, turn, phase, winner, cmd_wait, vp, used, fights, fights_null, fight_at`), lists (`seats,
squads, units, bodies, objs, pend, props, log_lines`), device streams `rngs`, `act_seq`.

Mutators that keep the indexes true (the only way to change the lists): `add_seat`, `add_squad`, `add_unit`,
`remove_unit`, `add_body`, `take_body`, `add_obj`, `set_props`. Accessors: `seat`, `pid_index`, `team_seats`,
`squad`, `squad_index`, `unit`, `unit_index`, `squad_models`, `squad_alive`, `alive_squads` (= `sqList`), `body_of`
(= `windBody`), `live_of` (= `liveOf` incl. wind bodies), `max_round`, `phase_name`, `mark_key`, `say`, `rng(name)`,
`fallback(stage)`. `snapshot(with_props)` / `restore(snap)` / `state_ints()` / `digest()`.

Invariants every module relies on: `units` is creation order with deaths spliced out and revives/risers/spawns
appended (the page's order; victim choice and `smove` zipping depend on it); `Squad.models` is `units` filtered by
squad in the same order; squads are never removed (`sqById` of a dead squad works); seat `id` = index.

Tests (exist, 115 checks): construction and clamps (`rounds: 0` → 5, the page's `rounds || 5`), seats, index
consistency through death/revive/wipe, bodies and `live_of`, flag bitmasks, `mark_key` uniqueness, streams, snapshot
int-only and round trip (also through JSON text), lean snapshot without props, rejection of 7 malformed snapshots
without side effects, digest stability and sensitivity to 18 rules fields (including the seat `pid`, which `done`
resolves through) and insensitivity to names/log/device streams.

### 1.2 `offsets.gd` — `BtOffsets` (+ `godot/tools/gen_offsets.gd`)

Literal integer tables, generated once by `tools/gen_offsets.gd` (outside core, may use float trig: `10 *
roundi(cos(an) * r * 125)` etc.) and committed; `tests/unit/test_offsets.gd` re-runs the generator function and
compares every entry.

| Constant | Page source | Content |
| --- | --- | --- |
| `FREESPOT_NEAR` (140 × 2) | freeSpot near rings 31326–31329 | r = 1..10 (outer), a = 0..13: angle `a·2π/14 + 0.41r`, radius `1.25r"`; `[10·round(cos·r·125), 10·round(sin·r·125)]`. Starts `[1150,500],[820,950],[330,1210],[-230,1230]`; r = 2 starts `[1710,1830],[740,2390]` |
| `ROOM_TO_LAND` (24 × 2) | roomToLand 31219–31223 | r ∈ {1.25, 2.5}, a = 0..11 at 30°: `[1250,0],[1083,625],[625,1083],[0,1250],[-625,1083],[-1083,625],[-1250,0],[-1083,-625],[-625,-1083],[0,-1250],[625,-1083],[1083,-625],[2500,0],[2165,1250],[1250,2165],[0,2500],[-1250,2165],[-2165,1250],[-2500,0],[-2165,-1250],[-1250,-2165],[0,-2500],[1250,-2165],[2165,-1250]]` (exact `Math.round` in MI, not on the 10 grid: these are probes, not positions) |
| `PLAN_RING` (61 × 2) | planMove 34143–34146 | k = 0: `[0,0]`; k = 1..6, a = 0..9: angle `a·2π/10 + 0.37k`, radius `0.8k"`, **cos → x, sin → z**, rounded to 10 MI. Starts `[0,0],[750,290],[430,670],[-40,800],[-510,620],[-770,200],[-750,-290],[-430,-670]` |
| `CHARGE_ROT` (4 × 2) | chargeSpots 31662–31682 | Q16 `[cos, sin]` of δk = 0.55k: `[55871,34255],[29727,58406],[-5185,65331],[-38568,52986]` |
| `SIDESTEP_ROT` (4 × 2) | planMove fallback 2, 34152–34155 | Q16 `[cos, sin]` of 0.4k: `[60363,25521],[45659,47013],[23747,61082],[-1914,65508]` |
| `DEP_ANG_STEP` 45875, `FS_ANG_STEP` 26870 | deploy 31197, freeSpot 31331 | Q16 of 0.7 and 0.41 rad |
| `FS_RING_K` 6544985 | freeSpot 31330 | `n = max(14, js_round(r·6544985, 10^6))` = page `max(14, round(r·1.25·2π/1.2))` (equal for r ≤ 400) |

Angles in Q16 use `FieldProps.TWO_PI` (411774) and `Fx.HALF_PI_Q16` everywhere (one value repo-wide; the 0.83 Q16
difference from the nearest value is irrelevant). The wide freeSpot search (up to ~104k points) and the deploy ring use
`Fx.isin_q16` at run time, not tables.

Tests: re-derive every table; spot values above; `FS_RING_K` equality for r = 1..400.

### 1.3 `blocking.gd` — `BtBlocking`

| Page | Lines | Signature |
| --- | --- | --- |
| prop shape prep (bldSize 29687, BLOCK_R 31278) | — | `static func prep_field(fp: FieldProps) -> Array[Dictionary]` (from generated items: `s4 = s·10`, `bw/bd` from `fp.bld_size`) |
| | | `static func prep_one(kind: String, x: int, z: int, rot_q16: int, s4: int, h_q16: int, bw: int, bd: int) -> Dictionary` (oracle fixtures: bw/bd from the page formula, §6) |
| `propBlocks(o, x, z)` | 31281–31301 | `static func prop_blocks(o: Dictionary, x: int, z: int) -> bool` |
| `blockAt(x, z)` | 31302–31306 | `static func block_at(st: BattleState, x: int, z: int) -> bool` |
| `crowded(x, z, skip, r)` | 31308–31314 | `static func crowded(st: BattleState, x: int, z: int, skip: Unit, r_mi: int) -> bool` (`r_mi < 0` = page `r == null`: radius of `skip`'s type, else 800) |
| `crowdedBy` | 31683 | not ported (ignores `taken`; callers use `crowded`) |
| `freeSpot(x, z, skip, from, maxD, rad)` | 31318–31339 | `static func free_spot(st: BattleState, x: int, z: int, skip: Unit, from: P2, max_d: int, rad: int) -> P2` (`from` empty = no limit; returns empty for the page's `null`) |
| `roomToLand(x, z)` | 31219–31223 | `static func room_to_land(st: BattleState, x: int, z: int) -> bool` |

Prepared prop (stored in `st.props` by `st.set_props`): `kind, x, z` (MI), `c, sn` (Q16 cos/sin of rot), `s4` (scale ×
10⁴: generated `s‰·10`, injected `round(s·10⁴)`), `h` (Q16), `bb` (bounding radius MI for a quick reject), plus per
kind: building `bw, bd` (full footprint MI as drawn); wall `segs = 3 + js_round(3h, 65536)` (matches `Math.round` at
the exact half); pillars `p0x,p0z … p3x,p3z` (post offsets MI: `js_round(ck·3200·s4, 65536·10⁴)` with the quarter-turn
vectors `(c,sn), (−sn,c), (−c,−sn), (sn,−c)`); disc kinds `rb` = BLOCK_R in MI.

`BLOCK_R_MI`: crater 0, arch 0, bush 0, rubble 1500, barricade 1500, log 1100, pipe 1900, tower 3000, boulder 2200,
iceslab 2200, obelisk 1800, buried 1600, tree 1100, deadtree 1100, pine 1200; unknown kind 2000.

Integer tests (with `dx = x − o.x`, `dz = z − o.z`, `ax = dx·c − dz·sn`, `az = dx·sn + dz·c`, all Q16·MI):
- building: `|2·ax| < (bw + 1400)·65536 and |2·az| < (bd + 1400)·65536` (page `bw/2 + 0.7`).
- wall: `|ax|·10⁴ < (segs·1200·s4 + 600·10⁴)·65536 and |az|·10⁴ < (900·s4 + 600·10⁴)·65536`.
- pillars: any post with `((dx−pkx)² + (dz−pkz)²)·10⁸ < (1300·s4)²` (no +0.6, as the page).
- disc: `rb > 0 and (dx² + dz²)·10⁸ < (rb·s4 + 600·10⁴)²` (largest term ≈ 4.9e18 < 2⁶³; reject with `bb` first anyway).
- `block_at`: `|x| > w·500 − 800 or |z| > d·500 − 800` → true; else any prop, `st.props` order (boolean, order-free).
  A uniform grid over props is allowed later (ARCHITECTURE §4) and never changes a result.
- `crowded`: any `q` in `units` order, `q != skip`, with `d2 < (me + r_q)²`.
- `free_spot`: `ok(nx, nz, crowd)` = `|nx| ≤ w·500 − 1200`, `|nz| ≤ d·500 − 1200`, (if `from`) `d2(n, from) ≤ (max_d + 1)²`,
  `not block_at`, `not (crowd and crowded(n, skip, rad))`. Order: the point itself; `FREESPOT_NEAR` (crowd on); if
  `from` → empty; wide pass 0 (r = 11..far, crowd on) then pass 1 (r = 1..far, crowd off) with `n = max(14,
  js_round(r·FS_RING_K, 10⁶))`, `θ = idiv(a·TWO_PI, n) + r·FS_ANG_STEP`, offset `10·js_round(cos_q(θ)·r·125, 65536)`
  (z with `sin_q`); `far = cdiv(isqrt_ceil((w² + d²)·10⁶), 1250)`; finally the point itself. Every candidate is on the
  10 MI grid when `(x, z)` is.
- `room_to_land`: `not block_at(x, z)` or any of `ROOM_TO_LAND` offsets not blocked.

Also adds to `fx.gd` (same agent, tests in `test_fx.gd`): `Fx.cdiv(a, b)` (ceil division = `-idiv(-a, b)`) and
`Fx.isqrt_ceil(n)`.

Tests (`test_blocking.gd`): one hand case per kind inside/outside each edge (building corners rotated, wall end, between
pillars free, crater/arch/bush free); table-edge margins 800/1200; `free_spot` returns the point itself when free, the
first near-ring offset when the point is blocked, empty with `from` when boxed in, a wide-ring point on a crowded
table; grid invariant (all results on 10 MI for on-grid input); `prep_field` of seed 1/48 ruin equals a pinned digest.

### 1.4 `squads.gd` — `BtSquads`

| Page | Lines | Signature |
| --- | --- | --- |
| `radOfType(TY(k))` | 31012 | `static func radius(s: Squad) -> int` / `static func radius_of(ti: int) -> int` (`GameData.base_r_mi`, 800 default) |
| `canTarget(a, b)` | 31064 | `static func can_target(st: BattleState, a: Squad, b: Squad) -> bool` (`a != b` and (`free_fire` or other side)) |
| `sqCenter(s)` | 31101–31102 | `static func center(s: Squad) -> P2` (`js_round(Σx, n)` per axis; empty → `[0, 0]`) |
| `sqDist(a, b)` | 31105–31106 | `static func dist2_min(a: Squad, b: Squad) -> int` (min over model pairs; `BattleState.FAR2` when a side is empty) |
| | | `static func dist_min(a: Squad, b: Squad) -> int` (`isqrt`, display and bots only) |
| `mEdge`, `sqEdge(a, b)` | 31107–31109 | `static func edge(a: Squad, b: Squad) -> int` (`isqrt(dist2_min) − ra − rb`; `FAR2` sentinel when empty) |
| | | `static func edge_within(a: Squad, b: Squad, lim_mi: int) -> bool` (exact: `dist2_min ≤ (ra + rb + lim)²`, false if that sum < 0) |
| `foesOf(s)` | 31110 | `static func foes_of(st: BattleState, s: Squad) -> Array[Squad]` (alive, other side or (`free_fire` and not s)) |
| `realFoes(s)` | 31111 | `static func real_foes(st: BattleState, s: Squad) -> Array[Squad]` |
| `engagedWith(s)` | 31113 | `static func engaged_with(st: BattleState, s: Squad) -> Array[Squad]` (`edge_within(s, q, 1001)`; squads order) |
| `isEngaged(s)` | 31114 | `static func is_engaged(st: BattleState, s: Squad) -> bool` (early exit) |
| `sqHalf(s)` | 31115 | `static func half(s: Squad) -> bool` (`alive·2 < n0 or (n0 == 1 and m0.hp·2 < w)`) |
| `formation(n, cx, cz, face, r)` | 31176–31183 | `static func formation(n: int, cx: int, cz: int, fx: int, fz: int, r: int) -> Array[P2]` |

`formation`: `gap = max(1700, 2r + 350)`; `per = n ≤ 3 ? n : n == 4 ? 2 : 3`; `rows = cdiv(n, per)`; for i: `row =
i / per`, `in_row = min(per, n − row·per)`, `col = i − row·per`, `o2 = (2col − in_row + 1)·gap`, `b20 = (2row − rows +
1)·gap·9`; `dx = 10·js_round(fz·o2·10 − fx·b20, 200000)`, `dz = 10·js_round(−fx·o2·10 − fz·b20, 200000)` with `(fx, fz)`
of length 1000; slot = `[cx + dx, cz + dz]`. `n == 0` → `[]`. Row 0 is the front.

Tests: centre rounding (negative halves), dist/edge vs hand values, `edge_within` at exactly 1" and 1"+1 MI, engaged
order follows squads, free fire in `foes_of` only, `half` for 1-model squads, formation slots for n = 1..10 facing the
four axes and a diagonal (symmetric, on the 10 MI grid, row 0 in front).

### 1.5 `army.gd` — `BtArmy`

| Page | Lines | Signature |
| --- | --- | --- |
| `mkPlayers()` | 31046–31055 | `static func mk_players(st: BattleState) -> void` (offline seats; pve: other teams bot; spectator: all bot, nm `บอท n` is UI) |
| `emptyList`, `fitList(L)` | 31008–31010 | `static func fit_list(raw: Array) -> PackedInt32Array` (clamp 0..99, hidden types 0..1; length = `GameData.count()`) |
| `facOf(L, dflt)` | 31011 | `static func fac_of(list: PackedInt32Array, dflt: String) -> String` (first non-`sec` type with a count; `lk` counts) |
| `fitSkin(o)` | 29978–29979 | `static func fit_skin(raw: Dictionary) -> Dictionary` (keys in `skins.json`, 1 ≤ i < variants) |
| `shareOf()` | 31062 | `static func share_of(st: BattleState) -> int` (`max(40, budget / max(1, per_team))`) |
| `baseCap()` (the rules one) | 31142 | `static func base_cap(st: BattleState) -> int` (`min(250, 500 / max(1, seats or 2))`) |
| `armyCap()`, `slotMax(T)` | 31145–31146 | `static func army_cap(st: BattleState) -> int`, `static func slot_max(st: BattleState, ti: int) -> int` (UI gating) |
| `ptsOf(pi)`, `teamPts(t)`, `hasUnits(pi)` | 31077–31081 | `static func pts_of(st: BattleState, pi: int) -> int`, `team_pts(st, t) -> int`, `has_units(st, pi) -> bool` |
| `autoList(s, free)` | 31147–31174 | `static func auto_list(st: BattleState, pi: int, dev: Rng) -> void` (`dev == null` = seeded) |
| `deploy()` | 31186–31213 | `static func deploy(st: BattleState, out: Ev) -> void` |
| `depWhyNot(pi, x, z)` | 31225–31237 | `static func dep_why_not(st: BattleState, pi: int, x: int, z: int) -> Dictionary` (`{key: ""\|"edge"\|"blocked"\|"mate"\|"foe", args: [seat or team]}`) |
| `depSlots()` | 31241–31248 | `static func dep_slots(st: BattleState) -> Array[P2]` |
| `depCapacity(w, d)` | 31066–31068 | `static func dep_capacity(w: int, d: int) -> int` (UI; keeps the page's `w−5` formula) |
| `autoDep(pi)` | 31249–31272 | `static func auto_dep(st: BattleState, pi: int) -> P2` |

`auto_list` with `dev == null` is the seeded form (the page's `!free && (bot || ai)`; v10 also uses it for every
seat still empty at match start, §7 #12, and in `resolveBots`): `rng = Rng.make("armies:%d" % pi, st.seed)` fresh per
call (the page restarts `tick` per call, so the list is a pure function) and the faction is drawn,
`factions()[rng.bounded(15)]` (draw 0). With a `dev` stream (the UI's "random army" or the army screen's default list,
which then travels in `/list`) the faction is the seat's `fac` (unknown or empty pool → `mod`) and draws come from
`dev`. Then exactly as the page: `MAX = min(base_cap,
max(6, cdiv(40, max(1, per_team)), js_round(share, 25)))` (**`base_cap`, not `army_cap`, even for spectators**);
`order` = pool keys → TYPES index; `cheap` = first strict minimum of `pts`; `fits(i)` = `pts ≤ left and models + n ≤
MAX`; pass 0 `fits(i) and (2·pts ≤ left or k < 2)`; passes 1–2 draw **only when `fits(i)`**: `rng.bounded(20) < 9`
(45 %); fill with `cheap` while it fits; the upgrade loop runs **only if `models + n(cheap) ≤ MAX` after the fill**
(page `up` guard, 31166: a list full of models is never upgraded), then while `5·left > share` and the previous sweep
changed something: for `a` in `order` with `out[a] > 0`, `b` = first strict maximum of `pts[b]` over `order` with `0 <
pts[b] − pts[a] ≤ left` and `models − n(a) + n(b) ≤ MAX`; swap one `a` for one `b` and restart the sweep;
`models == 0` → `out[cheap] = 1`.
**v10 adds `out[i] < SLOT_MAX` to `fits`** (§7 #13). Writes `list` and `fac`.

`deploy`: for each seat in order with a non-empty list: `dep` from `auto_dep` if missing (writes the seat; later seats
see it); facing `Fx.norm1000(−dep_x, −dep_z)`, zero vector → `(0, −1000)` (page `atan2(−0, −0) = −π`); squads in TYPES
order × count, squad `i` (index in that row) at the centre for i = 0, else ring `R = 1 + (i−1)/6`, `k6 = (i−1) % 6`,
`θ = idiv(k6·TWO_PI, 6) + R·DEP_ANG_STEP`, `dx = 10·js_round(cos_q(θ)·R·520, 65536)` (z with `sin_q`); id
`"<seat>:<i>"`, `n0 = T.n`, `vs = T.vsh or 0`, squad facing = the seat facing; models `"<sq>.<j>"` at
`free_spot(slot_j, null, [], 0, r)` with `hp = T.w`. Deps are rounded to 10 MI at the source (§7 #14), so every deploy
position is on the 10 MI grid. Events: one `LOG_LINE` per placed seat.

`dep_why_not` order: edge (`|x| > w·500 − 3000`, same for z) → blocked (`not room_to_land`) → for every other seat with
a dep in seat order: mate (same team, `d2 < 5000²`) or foe (`d2 < 20000²`), first failure wins.

`dep_slots`: `W = w·500 − 3000`, `nx = idiv(2W, 20000) + 1`, `x = −W + (nx > 1 ? 10·js_round(ix·2W, 10·(nx−1)) : 0)`;
iz-major. The single-column quirk (x = −W) is kept (§9).

`auto_dep`: `c = slots[imod(js_round(team·L, max(1, teams)), L)]`; `k` = index of the seat in `team_seats(team)`; k ==
0 and ok → `c`; ring search r = 9500 (+5000 after every 8th try), 32 tries, `dir = [(1,0),(0,1),(−1,0),(0,−1)][(k+i) %
4]` when `max(4, team size) == 4` (always, per_team ≤ 4), clamped to `±W/±D`, rounded to 10 MI; fallback grid z-outer
x-inner step 1500 MI from `−W/−D`, `Fx.stable_sort` by `d2` to `c` (insertion order on ties); else `c`.

Tests (`test_army.gd`): caps for 1..8 seats and spectator; `fit_list` clamps (hidden types to 1, 99, negative, short and
long input); `fac_of` skips `sec` but not `lk`; `auto_list` is a pure function of (seed, seat, setup) and pinned for 3
seeds × 3 armies; the cheapest-unit table per army equals the reader's list (gr archer, mod medic, kn knd2, sw swripper,
rb rscarab, or grot, th musket, jp yumi, nr viking, eg mummy, md pike, el elranger, de desyren, ta tadrone, cx cxc);
no slot above 99 (seed 10, budget 10000, 2×1, mod: the page gave 220); hidden types never appear in a bot list
(described only as "hidden types", never how they are reached); `deploy` ids, counts, facing, grid invariant, no two
bases overlapping; `dep_why_not` each code; `auto_dep` for 2/4/8 teams × 1–4 per team gives legal deps.

### 1.6 `objectives.gd` — `BtObjectives`

| Page | Lines | Signature |
| --- | --- | --- |
| `placeObjectives()` | 33922–33925 | `static func place(st: BattleState) -> void` (after `deploy`; spots `[0,0], [−rx,−rz], [rx,−rz], [−rx,rz], [rx,rz]` with `rx = w·270`, `rz = d·270`, each `free_spot(p, null, [], 0, 1200)`) |
| `objOC(o, team)` | 33926–33929 | `static func oc(st: BattleState, o: Obj, team: int) -> int` (units order; skip shaken squads; `d2 ≤ (3000 + r + 1)²`; `+= T.oc`) |
| `objCtl(o)` | 33930–33932 | `static func ctl(st: BattleState, o: Obj) -> int` (team scan; top tie → −1; later higher clears the tie; all zero → −1) |
| `scoreObjectives(team)` | 33934–33940 | `static func score(st: BattleState, team: int, out: Ev) -> void` (`min(15, held·5)`; log `obj_score`) |

`refreshObj`/`o.owner` is not stored: `ctl` is computed where needed (board, bots, scoring). No RNG (the `objectives`
stream stays unused).

Tests: placement order and the free-spot shift, OC with shaken squads and per-type `oc`, the tie rules, the VP cap.

### 1.7 `combat.gd` — `BtCombat`

| Page | Lines | Signature |
| --- | --- | --- |
| `woundNeed(S, T)`, `clampNeed(n)` | 31367–31368 | `static func wound_need(s: int, t: int) -> int`, `static func clamp_need(n: int) -> int` |
| `INF(k)` | 31369 | `static func inf(ti: int) -> bool` (data field `inf`, §8 wave 1 data task) |
| `shootersOf(s, t, W)` | 31371–31373 | `static func shooters_of(s: Squad, t: Squad, gun: Dictionary) -> Array[PackedInt64Array]` (`[unit index in s.models, best d2]`; `best2 ≤ (rng + 1)²`, centre to centre) |
| `painOn(A)`, `pactOn(A)` | 31380–31382 | `static func pain_on(st: BattleState, ti: int) -> bool` (`fac == "de"` and `round ≥ PAIN_ROUND`), `static func pact_on(ti: int) -> bool` |
| `marked(t)` | 31384–31385 | `static func marked(st: BattleState, t: Squad) -> bool` (`t.mk == st.mark_key()`) |
| `inAura(s, kind)` | 31386 | `static func in_aura(st: BattleState, s: Squad, kind: String) -> bool` (alive squads of the same side incl. s, `dist2_min ≤ 6001²`) |
| `atkMath(s, t, how)` | 31387–31405 | `static func atk_math(st: BattleState, s: Squad, t: Squad, how: int) -> Dictionary` (`{}` = no weapon) |
| `shotWhyNot(s, t)` | 31411–31424 | `static func shot_why_not(st: BattleState, s: Squad, t: Squad) -> Dictionary` |
| `canHeal`, `healWhyNot` | 31425–31432 | `static func can_heal(st, s, t) -> bool`, `static func heal_why_not(st, s, t) -> Dictionary` |
| `chargeWhyNot(s, t)` | 31433–31441 | `static func charge_why_not(st: BattleState, s: Squad, t: Squad) -> Dictionary` |
| `grenWhyNot(s, t)` | 31443–31451 | `static func gren_why_not(st: BattleState, s: Squad, t: Squad) -> Dictionary` |
| `count`, `sum` | 31406–31407 | `static func count_at_least(d: PackedInt32Array, need: int) -> int`, `static func total(d: PackedInt32Array) -> int` |

`atk_math` returns `{melee, shots, need, wneed, mod, sv, dmg, su, tr, lh, dw, heel, mk, who: PackedStringArray, d2}`
exactly as the page (combat report §3): melee = every model (`a + fury`, fury = `ca` and charged); ranged/ow =
`shooters_of` with `blast = bl ? alive(t) / 5 : 0` and `+rf` when `best2 ≤ (rng·500 + 1)²` (half range in MI plus the
page's 0.001"; `rng` are whole inches, so odd ranges give x.5" exactly); `mod` clamped ±1 (hv+still, aura hit,
pain melee, marked shoot; minus st/veil for shoot only); `need = tr ? 0 : ow ? 6 : clamp(bs|ws − mod)`; `wneed` with
`la`+charged and `po` vs INF; `ap − aoc` ≥ 0; `inv = min(T.inv or 7, bless ? 5 : 7)`; `sv = min(D.sv + ap, inv)`; `su =
W.su or (melee and pact ? 1 : 0)`. `mk = how == shoot and W.mk`.

Why-not keys and args (UI maps to the page's Thai): shoot `no_gun`, `own_side`, `already_shot`, `fell_back`,
`advanced`, `engaged` [pistol 0/1], `target_engaged`, `too_far` [dist_mi, rng_in]; heal `already_acted`,
`nobody_hurt`, `too_far` [heal_in]; charge `enemies_only`, `charge_done`, `advanced`, `fell_back`, `engaged`,
`too_far` [edge_mi] (`not edge_within(s, t, 12001)`); grenade `not_infantry`, `already_shot`, `moved_fast`,
`engaged`, `enemies_only`, `too_far` (`dist2_min > 8001²`). Check orders are the page's.

Tests (`test_combat.gd`): the wound table; atk_math for pairs covering every modifier (hv, hit/veil/bless auras, st,
pain from round 3 only, marked, poison vs INF and non-INF, la, aoc floor, inv vs ap, torrent need 0, overwatch 6s, rf
inside/outside half range, blast per 5, pact su, fury); each why-not in page order; centre-vs-edge range on a boundary.

### 1.8 `strats.gd` — `BtStrats`

| Page | Lines | Signature |
| --- | --- | --- |
| `stratKey(k, team)` | 31456 | `static func key(st: BattleState, k: String, team: int) -> String` (`k:team:round:turn:phase`, phase part empty for `brave`) |
| `canStrat(k, pi)` | 31457–31458 | `static func can(st: BattleState, k: String, pi: int) -> bool` (`not over`, seat exists, `cp ≥ 1`, key unused) |
| `useStrat(k, pi)` | 31459–31461 | `static func use(st: BattleState, k: String, pi: int, out: Ev) -> bool` (`cp −= 1`, `used[key] = true`, `STRAT {k, team}` event) |

CP is per seat, the lock per team. `rr` is shared by hit and charge re-rolls (same key). Costs from `strats.json`
(all 1). Tests: once per team per phase; brave once per turn; a team-mate cannot reuse a team's key; CP never negative.

### 1.9 `abilities.gd` — `BtAbilities`

Registry + the handlers that are more than a one-line check.

| Item | Page lines | Signature |
| --- | --- | --- |
| registry | data/README flags | `const FLAGS := {...}` flag → `"module.function"` that applies it; `const WEAPON_KEYS := {...}`; `static func flag(ti: int, name: String) -> bool`; `static func num(ti: int, name: String) -> int`; `static func gun(ti: int) -> Dictionary`; `static func mel(ti: int) -> Dictionary` |
| `gloryHeal(s, n)` | 31567–31570 | `static func glory_heal(st: BattleState, s: Squad, n: int, out: Ev) -> int` |
| `reviveOne(t)` | 31721–31730 | `static func revive_one(st: BattleState, t: Squad, out: Ev) -> Unit` (null when no model of `t` lives; else the first `i < n0` whose id `<t>.<i>` is not alive, at `free_spot(m0 + [1800, 0], null, [], 0, r)` with `m0` = first living model, hp 1, appended; callers set hp = w for rez) |
| `windFall(m)` | 31734 | `static func wind_fall(st: BattleState, m: Unit) -> void` (`wind_n += 1`, `st.add_body(m)`) |
| `windUp(s, lying)` | 31736–31745 | `static func wind_up(st: BattleState, s: Squad, out: Ev) -> Unit` (`take_body`, hp = w, `free_spot` from the body's rules position, appended) |
| `windGone(s)` | 31746 | `static func wind_gone(st: BattleState, s: Squad, out: Ev) -> void` |
| `windTurn()` | 31751–31755 | `static func wind_turn(st: BattleState, out: Ev) -> void` (**all** squads in creation order, dead included (SQ_ORDER, not `sqList`), but only those with `side == turn`, a `wind` type and a waiting body (`body_of`); `wind_n ≤ 1` rises free (`wind_up`), else push a `rez` pend `{u, att: pl, need: T.wind, n: 1, wind: true}`) |
| `spawnFrom(s, x, z)` | 31780–31792 | `static func spawn_from(st: BattleState, s: Squad, x: int, z: int, out: Ev) -> Squad` (null if `s` has no `spawn` or is `opened`; sets `opened`; id `<s>x`, type `H.k`, `n0 = H.n or T.n`, `vs = 0`, flags as `resetSq`, `moved = false`; if a model of `s` lives: base `m0` (first living model) and `f` = the **squad facing** of `s`; else base `(x, z)` (the dead carrier's rules position) and `f = (0, 1000)` (page `face = 0`); centre `base + js_round(f·2600, 1000)`; `formation(n, centre, f, r)` + `free_spot(slot, null, [], 0, r)`, hp `T.w`, appended; new squad facing = `f`) |
| `afterKills(P)` | 31794–31797 | `static func after_kills(st: BattleState, killed: Array[Unit], out: Ev) -> void` (rules position of each dead model) |
| shield refill | 33948 | `static func refill_shields(st: BattleState, out: Ev) -> void` |

Flags with no rules effect (`hero`, `ch`, `fly` beyond the two why-nots, `veh` beyond INF, `fx`, `trail`) are
registered with handler `"none"` so `test_abilities.gd` can assert full coverage: every flag and weapon keyword in
`types.json` has an entry, and each entry with a handler has one behavioural test.

### 1.10 `pend.gd` — `BtPend`

The PEND queue and every applier. Appliers never draw dice: a short array is padded by `pad`.

| Page | Lines | Signature |
| --- | --- | --- |
| `pendOf`, `pendAt` | 31479–31480 | `static func pend_at(st: BattleState, u: String, t: String, kind: int) -> Pend` (`t == ""` = any target; first match, any stage) |
| `unPend`, `mkPend` | 31481, 31866 | `static func remove(st: BattleState, p: Pend) -> void`, `static func push(st: BattleState, p: Pend) -> void` |
| padding (new) | — | `static func pad(st: BattleState, dice: Array, n: int, stage: String, out: Ev) -> PackedInt32Array` (§3) |
| `mkAtk(s, t, how)` | 31485–31492 | `static func mk_atk(st: BattleState, s: Squad, t: Squad, how: int) -> Pend` (null when no weapon or 0 shots; pushed last) |
| `markHit`, `countHits` | 31494–31496 | `static func mark_hit(st, p) -> void`, `static func count_hits(p: Pend) -> void` |
| `applyHit(P, hitR)` | 31497–31509 | `static func apply_hit(st: BattleState, p: Pend, dice: Array, out: Ev) -> void` |
| `applyReroll(P, v)` | 31511–31519 | `static func apply_reroll(st: BattleState, p: Pend, v: int, out: Ev) -> void` (guards stage wound, not `rr`, not `tr`; lowest failed hit die, first index on ties; no failed die → nothing changes (the act handler has already spent the CP, as the page); `v` 0 → `pad` one die, stage `rr`) |
| `woundDice`, `saveDice` | 31522–31523 | `static func wound_dice(p: Pend) -> int`, `static func save_dice(p: Pend) -> int` |
| `applyWnd(P, woundR)` | 31524–31535 | `static func apply_wnd(st, p, dice: Array, out) -> void` |
| `applySav(P, saveR, gtg)` | 31536–31544 | `static func apply_sav(st, p, dice: Array, gtg: bool, out) -> void` (gtg: `sv − 1` only if ranged and `sv > 3`) |
| `nextVictim(t, from)` | 31546–31551 | `static func next_victim(t: Squad, from: Squad) -> Unit` (first hurt; else nearest to `from`'s centre by `(n·mx − Sx)² + (n·mz − Sz)²`, strict; `from == null` → first; `from` with no living model → nearest to `(0, 0)` by `mx² + mz²` (page `sqCenter` of an empty squad is `{0, 0}`), never "first") |
| `dealDamage(...)` | 31552–31565 | `static func deal_damage(st: BattleState, t: Squad, from: Squad, n: int, dmg: int, spill: bool, out: Ev) -> Array[Unit]` (killed, in order; `hd` halves `(dmg+1)/2` below 999; one shield layer stops one whole hit; wind types → `wind_fall`) |
| `finishAtk(P)` | 31573–31598 | `static func finish_atk(st: BattleState, p: Pend, out: Ev) -> void` (slay 999 → mortal spill → normal; `after_kills`; gk; `BtTurn.check_over`) |
| `applyShock(P, roll, brave)` | 31603–31616 | `static func apply_shock(st, p, dice: Array, brave: bool, out) -> void` |
| `applyAdv(P, roll)` | 31618–31627 | `static func apply_adv(st: BattleState, s: Squad, roll: int, out: Ev) -> void` (transient: no PEND entry) |
| `owOk(t, s)` | 31629 | `static func ow_ok(st: BattleState, t: Squad, s: Squad) -> bool` (edge range, as the page) |
| `declareCharge(s, t)` | 31630–31637 | `static func declare_charge(st: BattleState, s: Squad, t: Squad, out: Ev) -> Pend` (`need = max(2, cdiv(isqrt_ceil(d2min) − ra − rb − 1000, 1000))`) |
| `applyOw(P, use)` | 31638–31644 | `static func apply_ow(st, p, use: bool, out) -> void` (the ow attack is inserted **before** P) |
| `chgReady(P)` | 34982 | `static func chg_ready(st: BattleState, p: Pend) -> void` |
| `applyCharge(P, roll, rr)` | 31645–31660 | `static func apply_charge(st, p, dice: Array, rerolled: bool, out) -> void` |
| `keepCharge(P)` | 31867 | `static func keep_charge(st, p, out) -> void` |
| `applyCMove(P, to)` | 31684–31692 | `static func apply_cmove(st: BattleState, p: Pend, to: Array, out: Ev) -> void` (zip the charger's models `s.models` with `to`, clamp to `±w·500/±d·500`, no 0.05 threshold; sets charged/chTgt/moved/still; squad facing = charger centre → target centre) |
| `applyGren(P, roll)` | 31694–31705 | `static func apply_gren(st, s, t, dice: Array, out) -> void` (`s.shot = true`; 6 dice, each 4+ one mortal wound: `deal_damage(t, s, n, 1, spill = true)`; `after_kills`; `check_over`) |
| `applyHeal(P, roll)` | 31708–31720 | `static func apply_heal(st, s, t, roll: int, out) -> void` (`s.shot = true`; `roll ≥ HEAL_ON`: first hurt model (units order) +1 hp, else `revive_one`) |
| `applyRez(P, roll)` | 31757–31777 | `static func apply_rez(st, p, dice: Array, out) -> void` |
| `rollerOf(P)` | 31801 | `static func roller_of(p: Pend) -> int` (atk at save and chg at ow → `def`, else `att`) |
| `prunePend()` | 34013–34020 | `static func prune(st: BattleState, out: Ev) -> void` (+ v10: promote `owatk → charge` via `chg_ready` for every chg, §7 #9) |
| `applyWhole(s,t,R,how)` | 34984–34989 | `static func apply_whole(st, s, t, hit: Array, wound: Array, save: Array, how: int, out) -> Pend` |

Tests (`test_pend.gd`): hit→wound→save with fixed dice; lethal-only skips wound dice; torrent ignores sent dice; su
extra hits still wound; slay at most one; mortal spill vs normal no-spill; shields; hd; victim order (hurt first,
then nearest to the attacker's centre, then index); re-roll lowest failed die, CP spent even with nothing to re-roll;
gtg rules; overwatch inserted before its charge and promotion after it resolves; charge 2d6 / chrr / keep; cmove
zipping; grenade; heal and revive appends; wind rise free then by roll; spawn from round 2 and on death; padding uses
`fallback:<seq>:<stage>` and logs `dice_short` only for a sender bug (> 60 needed is normal).

### 1.11 `moves.gd` — `BtMoves`

| Page | Lines | Signature |
| --- | --- | --- |
| `moveRange(s)` | 34124 | `static func move_range(s: Squad) -> int` (`(mv + (adv ? adv_r : 0))·1000`) |
| `nearFoe(s, x, z, r)` | 34125–34128 | `static func near_foe(st: BattleState, s: Squad, x: int, z: int, r: int) -> bool` (`d2 ≤ (r + r_q + 1050)²`, units of other sides) |
| `spotFree(s, x, z, r, chosen)` | 34129–34134 | `static func spot_free(st: BattleState, s: Squad, x: int, z: int, r: int, chosen: Array[P2]) -> bool` (false if `block_at` or `near_foe`; false if any unit not of `s` has `d2 < (r + r_q)²`; false if any chosen point has `d2 < (2r)²`) |
| `planMove(s, x, z)` | 34135–34160 | `static func plan_move(st: BattleState, s: Squad, x: int, z: int) -> Array[P2]` |
| `unitGoTo` (rules part) | 30012 | `static func go_to(st: BattleState, u: Unit, x: int, z: int) -> void` (clamp `±w·500/±d·500`) |
| `applySMove(s, to, how)` | 34161–34170 | `static func apply_smove(st: BattleState, s: Squad, to: Array, how: String, out: Ev) -> void` (move if `d2 > 2500`; `still = false` if any moved; `fb` → fell; facing = old centre → new centre when it moved > 300 MI) |
| `tryMoveSq(s, x, z)` | 34171–34187 | `static func try_move(st: BattleState, s: Squad, x: int, z: int, fall_back: bool) -> Dictionary` (`{key, args, act}`: the act to send, nothing applied; keys in page order: `already_moved`; `engaged_need_fb` (engaged and not `fall_back`); `too_far` [dist_mi, R_in] when the target is more than `R + 2.5"` from the centre; `blocked` (`block_at` the target); after `plan_move`, if no model would move more than 0.3" (`d2 > 300²`): `cant_fall_back` (engaged) / `near_foe` (`near_foe(target, r)`) / `no_room`; engaged and any planned point `near_foe` → `fb_not_clear`; else `""` and `act = {a: smove, u, to, how: fb (engaged) / adv / move}`) |
| `canGroup`, `groupAll` | 34192–34194 | `static func can_group(st, s) -> bool`, `static func group_all(st) -> PackedStringArray` |
| `groupMove(x, z)` | 34195–34215 | `static func group_move(st: BattleState, ids: PackedStringArray, x: int, z: int) -> Array[Dictionary]` (acts in order; each later plan sees earlier ones **applied**: the caller applies each act before asking for the next, so this returns one act per call — see signature note) |
| `chargeSpots(s, t, dist)` | 31662–31682 | `static func charge_spots(st: BattleState, s: Squad, t: Squad, dist_mi: int) -> Array[P2]` |

`group_move` note: the page plans squad k+1 after squad k's `smove` is applied. Implement as
`group_plan(st, ids, x, z) -> Array` that returns the sorted squad order and per-squad targets, and let the caller
(UI or `Battle.group_move`) loop `plan_move` → act → `apply` per squad. Page rules (34195–34215): the squads are the
picked ids that `can_group` (alive, not moved, not engaged; the UI adds `canAct`); `C` = mean of their centres; `(dx,
dz) = target − C`, nothing if `|d| < 0.3"`; sort by the projection of each centre on `d`, largest first (stable); per
squad `k = min(|d|, move_range)`, target `centre + d·k/|d|` clamped to `±(w·500 − 1200)` / `±(d·500 − 1200)`, `how =
adv ? adv : move`; a squad whose plan moves nobody more than 0.3" sends nothing.

`plan_move`: as the page (turn/moves report §4) with every candidate on the 10 MI grid: facing `norm1000(target −
centre)` when `d2 > 300²`, else the **squad facing**; `formation(models.size(), x, z, …)`; slot pick by strict `d2`;
`PLAN_RING` (skip `d2 > (R + 1)²` and the 1.2" table margin); with `d = slot − m`, `Le = isqrt(d²)` (1000 when 0,
page `|| 1`) and `F = min(R, Le)`: fallback 1 straight back `k = 10..1` with `q = m + 10·js_round(d·F·k, Le·100)`
(no range or margin check, as the page); fallback 2 sidestep, `a = 1..8` × `k = 5..1` (all 40 tried, no early exit):
direction = `norm1000(d)` (basis `(0, 1000)` for a zero vector) rotated by `SIDESTEP_ROT[ceil(a/2) − 1]` (`+` for odd
a), `q = m + 10·js_round(dir·R·k, 5·10⁴)`, keep the strict closest to the slot with `d2(slot, q) < (Le − 300)²`; last
resort the model's own position.
Output = checked points (already on the grid).

`charge_spots`: as the combat report §9 with `CHARGE_ROT`, per model `m` in squad order: `best` = nearest target
model (strict, first wins; none → `m`'s own spot), base direction `norm1000(m − best)` (zero → `(0, 1000)`), `rr = r_m +
r_best + 300`, tries 0..8 at angle offsets `0, +δ1, −δ1, +δ2, −δ2, … , −δ4` (`δk = 0.55k`, `CHARGE_ROT[k−1]`), candidate
`best + 10·js_round(v·rr, 10000)`, reject beyond `dist + 1` from `m`, `block_at`, within `2·r_m` (strict `<`) of a
taken spot, or `crowded(…, m, −1)` (radius of `m`'s type; the page's `crowdedBy` ignores `taken`); fallback: `L =
isqrt(|best − m|²)` (1000 when 0), `go = max(0, min(dist, L − rr))`, `p = m + 10·js_round((best − m)·go, L·10)`,
`free_spot(p, m, m, dist, r_m)` or the model's own spot; every result is appended to `taken`. `dist` = the charge
roll's sum × 1000.

Tests (`test_moves.gd`): range with advance; near-foe margin 1050 vs 1049/1051; plan_move on an open table (formation
kept, nobody beyond range), with a wall in the way (sidestep), boxed in (stays), all on grid; apply_smove thresholds
(49/50/51 MI), fall back sets `fell`, an empty `to` leaves `moved` false (handled in acts); charge spots legal and
within the roll; a time budget: 20-model squad on a 500-model field < 150 ms (ARCHITECTURE §4).

### 1.12 `turn.gd` — `BtTurn`

| Page | Lines | Signature |
| --- | --- | --- |
| `teamPlayers`, `teamIsBot`, `allDone`, `teamsAlive` | 31056–31060, 31085–31088 | `static func team_is_bot(st, t) -> bool`, `static func all_done(st, t) -> bool`, `static func teams_alive(st) -> PackedInt32Array` |
| `startMatch()` (rules part) | 35409–35428 | `static func start_match(st: BattleState, out: Ev) -> void` (state reset, cp 1, seeded `auto_list` for empty seats, vp, `deploy`, objectives unless kill or injected, `check_over`, first live team, `start_turn`; `Battle` then runs `advance`) |
| `startTurn()` | 33945–33967 | `static func start_turn(st: BattleState, out: Ev) -> void` (order is protocol: `ow_used = false` on **every** alive squad + `reset_turn` and `shaken = false` on the side in turn → shields (own side, alive, `vs < vsh`) → every seat `done = false` → phase cmd, `fights = []`, `fight_at = 0` → cp +1 for each seat of the team → shocks (alive own squads with `half`, not `brave`, not in an `ld` aura; pend `{need: ld}`) → rez (alive own squads with `rez` and losses; `need = min(rez, REZ_AURA)` in a `rez` aura; `n = min(10, n0 − alive)`) → `wind_turn` → spawns from round 2 (alive own squads with `spawn`, not opened) → `cmd_wait = true`) |
| `finishCommand()` | 33968–33974 | `static func finish_command(st, out) -> void` |
| `nextPhase()` | 33975–33985 | `static func next_phase(st, out) -> void` (fight or cmd → `end_turn`) |
| `startFight()` | 33987–33995 | `static func start_fight(st, out) -> void` |
| `fightTarget(s)` | 33996–34001 | `static func fight_target(st: BattleState, s: Squad) -> Squad` (chTgt if engaged; else min `(edge, squad index)`) |
| `scheduleFight()` | 34003–34009 | `static func schedule_fight(st, out) -> bool` |
| `advance()` loop body | 34022–34033 | `static func advance_step(st: BattleState, out: Ev) -> bool` (one iteration; true = continue) |
| `playerDone(pi, ph)` | 34034–34043 | `static func player_done(st: BattleState, pi: int, ph: String, out: Ev) -> void` (rules part; the sender's `flushPend` is the roller's job before it sends `done`) |
| `endTurn()` | 34081–34092 | `static func end_turn(st, out) -> void` |
| `finish(w, why)` | 34093–34099 | `static func finish(st: BattleState, w: int, why: String, out: Ev) -> void` (`over`, `winner`, PEND cleared, `OVER` event) |
| `checkOver()` | 34100–34105 | `static func check_over(st, out) -> void` |
| `endRoundCheck()` | 34106–34118 | `static func end_round_check(st, out) -> void` (candidates: teams with `live_of > 0` (wind bodies count); top VP, then surviving points of **living units only** `Σ pts·(30/n)` exact (30 = lcm of every `n` in today's data, asserted in a test); `round_no = max_round()`; one best → winner else draw) |

The clock (`startClock`/`clockTick`, 34045–34062) is not core: the Clock autoload on the owner sends `endph` when time
runs out with no pending roll.

Tests (`test_turn.gd`): start-of-turn order and PEND order (shocks, rez, wind), cp per seat, shields refill own team
only, scoring from round 2, phase chain, fight order (chargers, then alternating others / rest), fight target choice,
end_turn skipping dead teams and wrapping rounds, kill vs obj end, VP tie broken by points, `done` with mixed teams.

### 1.13 `acts.gd` — `BtActs`

| Page | Lines | Signature |
| --- | --- | --- |
| act table | §4 | `const CODES := [...]` (19 rules codes + legacy `endturn`, `move`) |
| Worker sanitiser mirror | worker.js `btPost` act | `static func sanitize(raw: Dictionary) -> Dictionary` (core form in, core form out; `{}` = refused like HTTP 400) |
| wire ↔ core | — | `static func to_wire(act: Dictionary) -> Dictionary` (MI → hundredths ints for `to`, `x`, `z`); the inverse lives in `net/json_num.gd` (floats are not allowed in core) |
| `netAct(a)` | 34950–34980 | `static func apply(st: BattleState, act: Dictionary, out: Ev) -> void` |
| `applyWhole`, `rollFor` | 34984–34990 | apply_whole is in pend; `rollFor` belongs to the roller |

Tests (`test_acts.gd`): every code round-trips through `sanitize`/`to_wire`; caps (61 dice → 60, 41 points → 40,
id 21 chars → 20, bad `how`/`ph` defaults); each handler's guard (e.g. `smove` on a moved squad, `chg` on a charged
squad, `gren` without CP is ignored, `rr` spends CP before its own guards); unknown codes are refused by `Table`.

### 1.14 `board.gd` — `BtBoard`

| Page | Lines | Signature |
| --- | --- | --- |
| `boardState()` | 34068–34077 | `static func board(st: BattleState, raw: bool) -> Dictionary` (§5) |
| `+v.toFixed(1)` | — | `static func tenths(mi: int) -> int` (`Fx.to_fixed_1` semantics, `-0` → 0) |
| JSON | — | `static func to_json(b: Dictionary) -> String` (tenths printed as `12`, `12.3`, `-0.5`) |

Tests: shape and key order, tenths at every rounding edge (x.x5 with binary-double behaviour), dead units and squads
absent, `engaged` and objective owners, `to_json` byte-exact against strings produced by the page for the 20 oracle
`board0`s.

### 1.15 `roller.gd` — `BtRoller` (new; the page's tray scheduler)

Not listed in ARCHITECTURE §1; it is the page's `myRoll`/`doRoll`/`flushPend` (31811–31886) without the tray, needed
headless for goldens, offline play and the owner's duties. It reads state and **returns acts**; it never mutates.

| Page | Lines | Signature |
| --- | --- | --- |
| `iRollFor(pi, P)` | 31804–31808 | `static func rolls_here(st: BattleState, pi: int, here: Dictionary) -> bool` (`here = {online, owner, pid, since_ok}` from Net) |
| `myRoll()` | 31811–31826 | `static func next(st: BattleState, here: Dictionary) -> Pend` (first PEND entry this device rolls, strict order; no side effects: the page's side effects are in `prune`) |
| `doRoll(r, opt)` | 31828–31865 | `static func roll(st: BattleState, p: Pend, opt: Dictionary, dice: Rng) -> Array[Dictionary]` (the act(s) for that entry: `atk/wnd/sav/rr/shock/rez/ow/chr/cmove`; ≤ 60 dice per array; `cmove` points from `BtMoves.charge_spots`) |
| `flushPend(force)` | 31876–31886 | `static func flush_plan(st: BattleState, here: Dictionary) -> Pend` (helper; the loop of roll → apply lives in `Battle.flush`) |
| `sendCMove(P)` | 31869–31871 | part of `roll` for a chg entry at stage `move`: `cmove {u, t, to: charge_spots(s, t, Σroll·1000)}` |
| `botChoice(P)` | 31888–31895 | the `opt` of `roll` for bot/ai/timeout entries comes from `BtBot.choice` |
| `rollFor(s, t, how)` | 34990 | `static func roll_whole(st, s, t, how: int, dice: Rng) -> Dictionary` (for `shoot` tests) |

`roll` returns **one act per call** whenever the next act depends on the state the previous one leaves (the page
sent them back to back): `chr` then, once applied and at stage `move`, `cmove`; `ow {use: 1}` then the inserted ow
`atk` (its own entry, rolled by the same seat); `doCharge` = the UI's `chg` act, then `chr` from `next`. A `chrr`
entry gives `chr {rr: 1, roll}` when `opt.yes` (CP is spent by the handler, never by the roller) else `chr {keep: 1,
roll: p.roll}`; `sav` carries `gtg: opt.gtg` and `shock` `brave: opt.brave` with no dice (`roll: []`). The page's
`P.since` (owner takes over after `OWNER_WAIT` 25 s) is device time and stays in Net: it keys entries by `(index,
kind, u, t, stage)` and passes `since_ok`. The page's forced `owatk → charge` in `flushPend(true)` is unreachable
offline (the ow attack sits before its charge and is rolled first; with none left `prune` promotes) and is not
ported.

### 1.16 `bot.gd` — `BtBot`

| Page | Lines | Signature |
| --- | --- | --- |
| `botChoice(P)` | 31888–31895 | `static func choice(st: BattleState, p: Pend) -> Dictionary` (`{yes, gtg, brave}`) |
| `botSquads()` | 34289 | `static func squads(st: BattleState) -> Array[Squad]` |
| `expDmg(s, t, how)` | 34290–34296 | `static func exp_dmg(st: BattleState, s: Squad, t: Squad, how: int) -> PackedInt64Array` (`[num, den]`, exact rational; compare by cross products) |
| `melee(s)`, `botSkip(s)` | 34297–34299 | `static func melee(s: Squad) -> bool`; skip is an act built in `next_act` |
| `botStep()` | 34300–34357 | `static func next_act(st: BattleState, dice: Rng) -> Dictionary` (one act; `{}` = this bot team has nothing left; `stay`/`skip` acts come one per call, the real action ends the step) |
| `botTick` rules part | 34358–34378 | `static func finished_act(st: BattleState) -> Dictionary` (`endph {ph}` when the team in turn has at least one bot seat, `next_act` is empty and `all_done` (every **non-bot** seat of the team is done; a team of bots only is always done); else `{}`. The page also set `done = true` on the bot seats, on the owner's device only; core never does (no rule reads a bot's `done`, `nextPhase` clears it), §7 #17) |

Decision rules to keep (34300–34357; inches, compare in MI/MI²; `melee(s)` = no gun or gun `rng ≤ 12`; `fd` =
`dist_min` to the nearest real foe, sorted by `dist_min` with an index tie-break; distances to objectives from the
squad centre): **move** — no foes → `skip`; engaged: fall back (`smove fb` towards `centre + mv·(centre −
foe centre)/|…|`, `plan_move`) only if not melee and the engaged foe's fight `exp_dmg` on us > ours on it, else `stay`;
on an objective (`d ≤ 3"`) and not (melee and `fd ≤ 14`) → `stay`; `goal` = the nearest objective not controlled by
our side; `for_obj = goal and gd ≤ 2·mv + 3 and not (melee and fd < 9)`; if not `for_obj` and (melee or no goal or `fd
< 0.7·gd`) the goal becomes the nearest foe's centre; not `for_obj`, not melee, with a gun: `stay` when `fd ≤ 0.85·rng`
and `hv`, or `fd ≤ 0.6·rng`; `gd −= 1.2` when `for_obj`; `want = max(0, gd − (for_obj ? 0 : melee ? 7 : 1.5))`; `want
< 0.8` → `stay`; else `smove` to `centre + dir·min(mv, want)` via `plan_move`. **shoot** — a healer heals the first
squad (creation order, itself included) that `can_heal`; no gun → `skip`; best real foe by strict `exp_dmg` among
those with an empty `shot_why_not`; none → grenade on the first real foe with an empty `gren_why_not` when the seat
has `cp ≥ 2` and `can("gren")`, else `skip`; `mk_atk` empty → `skip`. **charge** — skip squads that `ch_done`, `adv`,
`fell` or are engaged; target = least `edge` among real foes with an empty `charge_why_not`; charge when `melee or
exp_dmg(fight) > 1.2·exp_dmg(shoot)` and `edge ≤ (melee ? 11 : 7)"`, else `skip`. Bot dice (heal, gren, atk, chr)
come from `bot:<seat>`.

Tests (`test_bot.gd`): one decision per phase on hand-built boards (fall back when outmatched, hold an objective, go
for the closest objective, shoot the best target by exact expected damage, grenade fallback with CP ≥ 2, charge only
when worth it); bots never send an illegal act (`*_why_not` empty); `test_smoke_bots.gd` (30 games, wave 5).

### 1.17 `battle.gd` — `Battle extends Table`

```gdscript
class_name Battle
extends Table
var st: BattleState
static func make(setup: Dictionary, seats: Array[Dictionary], fixture: Dictionary) -> Battle   # §6 for fixture keys
func start() -> Array[Dictionary]                       # BtTurn.start_match + advance; logs no act
func codes() -> PackedStringArray                       # BtActs.CODES
func _on_act(act: Dictionary) -> Array[Dictionary]      # st.act_seq = act.seq; BtActs.apply
func advance() -> Array[Dictionary]                     # BtPend.prune once, then BtTurn.advance_step up to 60 times
func state_ints() -> PackedInt64Array                   # super() + st.state_ints(); keeps Table.turn/round_no/phase/over in sync
func snapshot() -> Dictionary                           # super() + {"battle": st.snapshot(st.props_injected)}
func restore(d: Dictionary) -> bool
func board() -> Dictionary                              # BtBoard.board(st, false)
func bot_step() -> String                               # page BT.botStep(): bot acts until a real one, then flush
func flush(force: bool, here: Dictionary) -> int        # roll every entry this device rolls (force = offline: all)
```

Every rules change, including the device's own taps, bots and rolls, goes through `apply` (ARCHITECTURE §3).

### 1.18 Page functions with no core module of their own

Every function in the ported ranges (30998–31897, 33921–34394, 34855–35043) is either in a table above or here.

| Page function(s) | Lines | Where it goes |
| --- | --- | --- |
| `sqOf`, `sqById`, `sqModels`, `sqAlive`, `sqList`, `sqT`, `sqOwner`, `unitById`, `pidIndex`, `teamPlayers`, `markKey`, `maxRound`, `liveOf`, `windBody`, `say` | 31082–31117, 31345, 31384, 31735, 35019 | `BattleState` accessors (`squad`, `squad_models`, `squad_alive`, `alive_squads`, `unit`, `pid_index`, `team_seats`, `mark_key`, `max_round`, `live_of`, `body_of`, `say`) |
| `emptyList`, `TY`, `radOfType`, `dist2`, `gx`, `gz`, `count`, `sum`, `rollN`, `d6` | 31008–31076, 31406–31408 | `GameData` / `BtSquads.radius_of` / `Fx.dist2` on `Unit.x/z` / `BtCombat.count_at_least`, `total` / dice only in the roller and bots (`Rng.d6` on the streams of §3) |
| `take` (inside `finishAtk`) | 31577 | `BtPend.finish_atk` |
| `canAct` | 34225–34234 | UI gate (`ui/battle`): side in turn, seat not bot/ai/done, phase rules (move: not moved; shoot: not shot and has gun or heal; charge: not `ch_done`/`adv`/`fell`/engaged; never in cmd/fight), own seat online. Not a receiver check |
| `aimAt`, `selectUnit`, `tapGame`, `markGroup`, `humanTurn`, `watching`, `isMine`, `isHumanHere`, `waitingOn` | 31809, 34193–34277 | UI; `aimAt` adds "not enough CP" for a grenade (`BtStrats.can`) on top of `gren_why_not`. `isHumanHere` → the roller's `here` |
| `stayPut`, `startAdvance`, `doCharge`, `btAct skip` | 34216–34221, 34279–34285, 35433 | UI → acts `stay`, `adv {roll from dice:<seat>}` (UI guard: not moved, not advanced, not engaged), `chg` (after `charge_why_not`), `skip {ph}` |
| `isBotUnit` | 31061 | `BtBot.squads` (seat `bot` flag) |
| `curSetup` | 34865–34869 | `BattleState.setup_dict` + RoomClient: the room setup sends `mode: team` for custom/spectator |
| `adoptRoom` | 34906–34947 | RoomClient, lobby only (seats frozen in play, §7 #10) |
| `adoptRoster`, `netPhase`, `resolveBots` | 35001–35041 | RoomClient builds the seats for `Battle.make` from the room `state: play` act: roster seats by pid (team, `fit_list(list)`, `fac_of(list, old fac)`, `fit_skin(sk)`, dep); seats without a pid take `bots[k]` in seat order (team, `fit_list`, `fac_of(list)`, dep). The owner fills `bots` (`resolveBots`): seeded `BtArmy.auto_list` for empty lists, `auto_dep` for missing deps. `netPhase(army)` gives the own seat a `dev` default list when it has none |
| `pushBoard` | 34063–34066 | Net (owner posts `BtBoard.board(st, false)` after phase/turn changes) |
| `netUrl`, `netPost`, `netNote`, `myName`, `netStop`, `netStart`, `netPoll`, `netSend`, `applyAct`, `netFirstMine` | 34856–34904, 34992–35000, 35042 | `net/room_client.gd`; `applyAct`'s "skip my own act" disappears (the device applies its own act once, through `apply`, before sending) |
| `say` text, `paintLog`, `popDice`, `tickDice`, `winPop`, `markFinal`, `sqLabel`, `sqName`, `TEAM`, `fmtPts`, `goalName`, `chapHead`, `show`, `vshieldFx`, `windFx`, `trayThrow` callers | various | view/UI from events and log keys |
| `startClock`, `clockTick` | 34045–34062 | Clock autoload (owner sends `endph` on time-out with nothing pending) |
| `crowdedBy` | 31683 | not ported (`crowded`) |
| `depCapacity`, `armyCap`, `slotMax`, `ptsOf`, `teamPts`, `hasUnits`, `shareOf`, `fitList`, `facOf`, `mkPlayers`, `seededRoll`, `formation`, `resetSq` | 31008–31183, 31215 | `BtArmy` / `BtSquads` / `Squad.reset_turn` (`seededRoll` → `armies:<seat>`, §3) |

---

## 2. Integer conventions

- **Lengths** MI (int64). Table ≤ 180" ⇒ |coord| ≤ 90,000; d2 ≤ 4.9e10. Products allowed up to ~4.6e18; the largest in
  this spec: disc block test `d2·10⁸` (≤ 4.9e18, only after the `bb` reject), `exp_dmg` cross products (≤ 1e11·1e3).
  State the bound in a comment wherever a product exceeds 1e15.
- **Angles and trig** only through Q16: `Fx.isin_q16`, `FieldProps.sin_q/cos_q`, the `BtOffsets` rotation tables.
  No `sin(`, `cos(`, `atan2(` anywhere in core (lint).
- **Directions** = `Fx.norm1000(dx, dz)` (length 1000, `js_round` per axis). A zero vector returns `[0, 0]`; every
  caller names its default (deploy `(0, −1000)`, chargeSpots `(0, 1000)`, sidestep basis `(0, 1)`, planMove → squad
  facing). The page's `face` angle maps to `(fx, fz) = (sin face, cos face)` (the `atan2(dx, dz)` convention).
- **Rotation of a vector by a table angle**: `+δ → (x·c + z·s, z·c − x·s) >> 16`, `−δ → (x·c − z·s, z·c + x·s) >> 16`
  (the page's `sin/cos(a0 ± δ)` with a0 from `atan2(dx, dz)`); use `Fx.js_round(…, 65536)` instead of `>> 16` where the
  result is a position.
- **Rounding**: `Fx.js_round(num, den)` = `Math.round(num/den)` (half up). Floor division `Fx.idiv`, ceil `Fx.cdiv`;
  plain `/` only when both operands are known non-negative (say so in a comment). `%` only through `Fx.imod`.
- **Ranges** compare squares: `dist ≤ R + 0.001"` → `d2 ≤ (R + 1)²`; `dist < R` → `d2 < R²`; edge tests add the radii
  inside the square (`edge_within`). A displayed distance is `isqrt` (floor); a rules threshold never uses a rounded
  distance except where the page's value is itself rounded (charge need: `isqrt_ceil`, exact, see `declare_charge`).
- **Rule margins kept as on the page**: `ENGAGE + 0.05` in `near_foe` (1050 MI) and the move threshold `0.05"`
  (`d2 > 2500`) in `apply_smove`. ARCHITECTURE §4's "the +0.05" tolerance is dropped" is superseded: these are margins
  of the rules, not float tolerances (§9 D4).
- **The 10 MI grid**: deploy slots, `free_spot` results (for on-grid input), `plan_move`, `charge_spots`, `revive_one`,
  `wind_up`, `spawn_from` and every wire point are multiples of 10 MI (0.01"). Wire points cross as `MI/10` hundredths
  (exact both ways); `json_num.gd` prints `"%.2f"`-free decimal text from the int (never a float). A test asserts the
  grid invariant after every act of every golden.
- **Mean positions** (`center`) are `js_round(Σ, n)` per axis. Where the page compares distances to a mean, use the
  exact form without division (`next_victim`: `(n·mx − Sx)² + (n·mz − Sz)²`).
- **Board rounding** is `Fx.to_fixed_1` (the page's `toFixed(1)`, binary-double tie behaviour), not `js_round`
  (ARCHITECTURE §4 superseded; they differ at x.x5).
- **Props**: `x, z` MI, `rot` Q16 rad, `h` Q16, scale `s4` (×10⁴). Generated props have `s4 = s‰·10` (exact);
  injected page props `s4 = round(s·10⁴)` (≤ 0.0005" error at the largest radius).
- **Expected damage, survivor points, VP**: exact rationals or common denominators (`exp_dmg` `[num, den]`;
  survivors `Σ pts·(30/n)`); never a rounded quotient in a comparison.
- **Strings in state**: ids (protocol), type keys, kinds as ints; `used` keys are the page's `stratKey` strings (only
  looked up; sorted for snapshot/digest).

---

## 3. RNG: which draws map to which stream

Rule: **real dice come only from acts.** Core appliers never roll; the only draws inside `apply` are the fallback pads.
Streams are `Rng.make(name, st.seed)` (PCG32, one per purpose; adding a consumer never shifts another).

| Page draw | Page site | v10 stream | Who draws | In digest |
| --- | --- | --- | --- | --- |
| `seededRoll(s·97 + tick)` | `autoList` for bot/ai seats (31152) | `armies:<seat>`, fresh per `auto_list` call | every device (startMatch) / owner (`resolveBots`) | result only (list) |
| `Math.random` in `autoList` (human, free, "random army"; `netPhase(army)` default list) | 31152, 35024 | the UI's device stream (`dev`); the list travels in `/list` | that device | result only |
| `Math.random` faction of `randomArmy(true)` | 35264 | `dev.bounded(15)` in the UI, written to the seat's `fac` before `auto_list(…, dev)` | that device | result only |
| `autoList` for a seat still empty at match start | startMatch 35415 | `armies:<seat>` (seeded for **every** empty seat, §7 #12) | every device | result only |
| `d6()` / `rollN` by the roller, human seat | doRoll, startAdvance, doReroll, doCharge | `dice:<seat>` in `st.rngs`; offline and goldens seeded from `st.seed`; online the host seeds it from device entropy (Godot RNG outside core) so dice are not predictable | the human's device | no |
| `d6()` / `rollN` for a bot, an ai seat or a timeout | botStep heal/gren/atk, doRoll on the owner | `bot:<seat>` (seat = `roller_of` the entry; owner device) | owner | no |
| `d6()` padding a short array | applyHit/Wnd/Sav/Shock/Charge/Gren/Rez, `|| d6()` in Reroll | `fallback:<seq>:<stage>` (`st.fallback(stage)`, fresh), stages `hit wound save rr shock chr gren rez`; `seq` = core act seq | every device, identically | via state |
| dice beyond the 60th of a stage | the Worker's cut | the same fallback stream, **also on the roller**: the roller sends ≤ 60, receivers and roller pad identically, no `dice_short` log | every device | via state |
| Worker `d6()` (Claude seats) | worker.js | — (travels in the act) | server | — |
| `hash2/hash3` (SEED) | terrain, props, building depth | `FieldNoise`/`FieldProps` over `Hash.ihash2/ihash3` (no Rng stream) | every device | props hash |
| visual randomness (`vshieldFx`, `endBlows`, `kill8`, tray `seedOf`) | — | Godot RNG in `table/` | view only | — |

- `adv` and `heal` acts with a missing roll keep the page's `roll|0 || 1` (= 1, never a draw); the Worker always sends
  1..6, so this is only reachable from a buggy sender (§9 D11).
- The streams `terrain`, `props`, `objectives`, `deploy` named in ARCHITECTURE §4 stay reserved and unused: those parts
  are hash-based or deterministic searches.
- Owner failover: a new owner continues with its own `bot:<seat>` streams (never advanced on that device). Since bot
  dice travel in acts, sync is unaffected; goldens are single-device.
- `act_seq` is the core `ActLog` seq (rules acts only, continuous on every device), not the room seq (which also counts
  `join/leave/team/setup/list/dep/state/owner`). `net/room_client.gd` maps room seq ↔ core seq.

---

## 4. Act codec

Core acts are the Worker's sanitised acts with points in MI and every number an int. `Table.apply` adds `seq` and needs
`pid` (String; the server's pid online; offline the seat's local pid, §9 D8). Caps are the Worker's (`btPost`):
`dice` ≤ 60 values clamped 1..6 (non-numbers → 1), `one` = one die 1..6, `id` ≤ 20 chars, `pts` ≤ 40 points each
clamped ±9999" (±9,999,000 MI; a non-array point → `[0, 0]`), `ph` ∈ phases else `""`, `how` defaults below.
`smove` keeps `to` (possibly empty) when the raw `to` is an array, else carries `x, z` with a missing value → 0
(the Worker's `num(undefined)`: an `smove` with neither becomes a plan to the table centre, page parity). `chr` always
carries `rr` and `keep` (0/1). Legacy `move {u, x, z}` and `endturn {}` pass the sanitiser.

| Code | Fields (core types) | Caps / defaults | Sent by (v10) | Handler (page `netAct` 34950–34980) |
| --- | --- | --- | --- | --- |
| `smove` | `u: String`, `how: String`, `to: Array[[int,int]]` **or** `x: int, z: int` | how ∈ move/adv/fb else move; to ≤ 40 | try_move, group_move, bot (move, fb), server `bt_move` (x, z at 0.1") | `s and not s.moved`: `to` non-empty → `apply_smove`; else x/z → `plan_move` on every device → `apply_smove`; else nothing (moved stays false) |
| `stay` | `u` | — | stay button, bot, server | `s.moved = true` (no phase/turn guard) |
| `skip` | `u`, `ph: String` | ph ∈ phases or "" | skip button (shoot/charge), bot | `ph or phase`: shoot → shot, charge → ch_done, else moved |
| `adv` | `u`, `roll: int` | one 1..6 | advance button, server (Claude) | `not s.adv` → `apply_adv(roll in 1..6 ? roll : 1)` |
| `atk` | `u`, `t`, `how: String`, `hit: Array[int]` | how ∈ shoot/fight/ow else shoot; hit ≤ 60 | roller (aim shot, fight, ow), bot, server `bt_shoot` | `s and t`: `pend_at(u,t,atk)` at stage hit, else a new `mk_atk(how)` (page behaviour, logged `atk_new`); `apply_hit` |
| `wnd` | `u`, `t`, `wound` | ≤ 60 | roller | `pend_at` → `apply_wnd` (stage check inside) |
| `sav` | `u`, `t`, `save`, `gtg: int` | ≤ 60; gtg 0/1 | roller (defender) | stage save → `apply_sav(save, gtg and use("gtg", def))` |
| `rr` | `u`, `t`, `v: int` | one 1..6 | roller (human re-roll) | stage wound, not rr, `use("rr", att)` → `apply_reroll(v)` |
| `shoot` | `u`, `t`, `how`, `hit`, `wound`, `save` | each ≤ 60 | tests, old Claude | `apply_whole` (no gtg) |
| `shock` | `u`, `roll`, `brave: int` | roll ≤ 2 | roller | `pend_at(u,"",shock)` → `apply_shock(roll, brave and use("brave", att))` |
| `rez` | `u`, `roll` | ≤ 10 | roller | `pend_at(u,"",rez)` → `apply_rez` |
| `chg` | `u`, `t` | — | charge order, bot, server `bt_charge` | `s and t and not s.ch_done` → `declare_charge` (no why-not on receive) |
| `ow` | `u` (charger), `t`, `use: int` | 0/1 | roller (defender decision) | `pend_at(u,t,chg)` → `apply_ow` |
| `chr` | `u`, `t`, `roll`, `rr: int`, `keep: int` | roll ≤ 2; rr/keep 0/1 (Worker always adds both) | roller, charge order | `chg_ready`; keep → `keep_charge`; rr → stage chrr and `use("rr")` → `apply_charge(…, true)`; else `apply_charge` |
| `cmove` | `u`, `t`, `to` | ≤ 40 | roller after a successful `chr` (charger or owner) | `pend_at(u,t,chg)` → `apply_cmove` (no validation) |
| `gren` | `u`, `t`, `roll` | ≤ 6 | aim gren, bot, server | `s and t and use("gren", s.pl)` → `apply_gren` (no why-not; whole act ignored without CP) |
| `heal` | `u`, `t`, `roll: int` | one 1..6 | aim heal, bot, server | `s and t` → `apply_heal(roll in 1..6 ? roll : 1)` (no can-heal) |
| `done` | `ph`, `pid` | ph ∈ phases or "" | online end-phase button (`btEnd`/`btDone`), offline per-seat `btDone` (local pid, §7 #11), server `bt_end_turn` | `pi = pid_index(pid) ≥ 0` → `player_done(pi, ph)` |
| `endph` | `ph` | ph ∈ phases or "" | owner clock timeout, bot team finished (`BtBot.finished_act`), offline `btEnd` (the page called `nextPhase` for the whole team, §7 #11) | `ph == "" or ph == phase` → `next_phase` (from cmd this ends the turn, as the page) |
| `endturn` (legacy v1) | — | — | nobody | phase not cmd/fight → `next_phase` |
| `move` (legacy v1) | `u, x, z` | — | nobody | no-op |

After every act `Battle.advance()` runs (page `applyAct` 34992). Acts after `over` are applied (advance returns at
once), as the page. Server-made `owner/state/join/leave/team/setup/list/dep` never reach core: `RoomClient` handles
them (`state` → seats frozen → `Battle.make` + `start`).

Dice per stage (pad target): hit `shots`, wound `hits − lethal`, save `wounds − mortal − slay`, shock/chr 2, gren 6,
rez `n` (≤ 10, wind 1), rr/adv/heal 1. Today's data peaks at exactly 60 (a 10-model pact squad's 30 sixes → 60 hits);
shots peak at 40 (melee) — tests pin both.

---

## 5. Board state (`BtBoard.board`) — the page's `boardState()` / `BT.board()`

Key order and content exactly as the page (34068–34077); the Worker's `btBoard` accepts it unchanged **once its
`BT_RULES` gate (worker.js, today 9) admits `v: 10`**: with `v > BT_RULES` it keeps only the version-1 fields (turn,
round, over, units) and Claude loses phase, VP, CP, objectives and squads. Raising `BT_RULES` (and `btVerErr`) is part
of the v10 server PR. The Worker clamps (hp ≤ 999, |x|, |z| ≤ 200, ≤ 600 units, ≤ 300 squads, turn ≤ 7), all inside the
table limits.

```
{ v: Version.RULES_V, turn, round, phase: PHASES[phase], over: bool, vp: [per team], goal: "obj"|"kill",
  rounds: max_round(), cp: [per seat, cp],
  obj:    [{ n, x, z, owner: BtObjectives.ctl }]                       (OBJ order; [] for kill)
  squads: [{ id, pl, team: side, k, n: alive, n0, x, z (center), moved, adv, fell, shot, chDone, charged,
             shaken, engaged: is_engaged }]                            (alive squads, creation order)
  units:  [{ id, sq, pl, team: side, k: type key, hp, x, z }]          (units order, living only) }
```

- `raw = false`: `x`/`z` are `tenths(mi)` ints (page `+v.toFixed(1)`, so `-0.0` → `0`); `to_json` prints a tenths int
  `t` as `t/10` with one decimal unless it is whole (`120` → `12`, `-5` → `-0.5`), byte-equal to the page's JSON.
- `raw = true`: `x`/`z` in MI (oracle and tests). Squad centres are `center()` (`js_round` mean) in both forms.
- Not in a board (so the oracle sees their divergence only later): PEND, `still/fought/adv_r/ch_tgt/ow_used/vs/mk/
  opened/wind_n`, `used`, `fights`, `cmd_wait`, wind bodies, facing. The digest covers them.

---

## 6. Oracle replay plan (`tests/oracle/test_oracle.gd`)

Inputs: `tests/oracle/*.json.gz` (20 recordings, format in `tests/oracle/README.md`). Test-side helpers may use floats
(they are not core) but must hand core ints only.

1. **Read** the gzip JSON (`FileAccess` + `decompress_dynamic(…, GZIP)`), convert numbers with an intify pass that
   keeps raw doubles for `props`, `deps`, `obj` and act points.
2. **Setup**: `BattleState` setup from `rec.setup` (`density` → `density_h = round(density·100)`; `v` ignored; `d`
   given).
3. **Seats** k = 0..teams·perTeam−1 (mkPlayers order): `team = rec.seats[k].team`, `bot = rec.seats[k].bot`, `ai =
   false`, `pid = bot ? "" : "A"`, `list = fit_list` of `rec.lists[k]` (keys → TYPES index; hidden entries appear by key),
   `fac = fac_of(list, "mod")` (assert `== rec.seats[k].fac`), `skin = scenario_def.seats[k].skin or {}`, `dep =
   10·js_round(dep·100)` MI each axis (§7 #14; page deps are raw `autoDep` doubles such as `-21.000000000000004`, so
   report the largest rounding error per scenario; it is ≤ 5 MI), `cp = 0`, `done = false`.
4. **Fixture** (`Battle.make(setup, seats, fixture)`):
   - `props`: each recorded prop → `BtBlocking.prep_one(kind, round(x·1000), round(z·1000), round(rot·65536),
     round(s·10⁴), round(h·65536), bw, bd)` with `bw = round((5 + h·7)·s·1000)` and `bd = round((4.5 +
     page_hash3(⌊h·131⌋, 2, 61)·6)·s·1000)` from `tests/oracle/page_hash.gd`: an exact integer replica of the page's
     `hash2/hash3` (29402–29403) including V8's double rounding of the second multiply (round the int64 product to 53
     significant bits, ties to even, then ToInt32) and the recorded `setup.seed`. `set_props(…, injected = true)`.
   - `objectives`: `rec.obj` → `add_obj(n, round(x·1000), round(z·1000))`; `start_match` skips `place` when the fixture
     has objectives (kill: none).
   - `deployment`: v10 `deploy` runs with the injected deps and props (it is exercised, not replaced). If the recorder
     gains `units0` (raw positions, recommended, §9 Q1), the fixture overrides every unit position after `deploy` and
     asserts the ids and order match.
5. **board0**: `compare(battle.board_raw(), rec.board0)`.
6. **Acts**, for i in order:
   - assert `(turn, round, phase)` == `rec.acts_meta[i]` (catches drift one act early); optionally assert the roller of
     the PEND entry the act resolves == `acts_meta[i].seat`.
   - convert to core form: points `10·js_round(x·100)` MI, `x/z` likewise, all other numbers int; add `pid = "A"` (what
     page B saw; `done` then resolves to the human seat); then pass it through `BtActs.sanitize` as the Worker would
     (recordings hold the acts as `netSend` got them: `chr` without `keep`, `rr` only when set). The 20 recordings
     hold all 19 codes (counts: skip 1391, endph 1075, atk 804, wnd 737, smove 682, sav 495, stay 426, chr 269, chg
     222, cmove 188, shock 95, ow 83, done 18, heal 14, adv 11, rez 11, gren 4, rr 2, shoot 1).
   - `battle.apply(act)`; assert no `BAD_ACT`, no `dice_short` (no recording was ever padded).
   - `compare(board_raw, rec.boards[i])`; stop at the first act with a non-allowlisted difference and print it like
     `tests/battle/net_sync.js` (scenario, act index, act, field path, port value, page value, the last 5 log keys).
7. **Final**: `over, round, turn, phase, vp, cp`, `alive` (= `teams_alive`, wind bodies included), unit count.

**Compare rules.**
- Exact: `turn, round, phase, over, vp, cp, goal, rounds`; obj `n, owner`; squads: the **sequence** of ids and `pl,
  team, k, n, n0` and the 8 flags; units: the **sequence** of ids (this pins victim order and the append order of
  revives, risers and spawns) and `sq, pl, team, k, hp`.
- Positions: port MI `p` vs page tenths value `q` (inches): `|p − 1000·q| ≤ 60` for units and squad centres (50 for the
  page's own rounding + 10 for the v10 grid), `≤ 51` for objectives (injected exactly). After a model's first `smove`
  / `cmove` its position is the act's point on both sides; before that it is the v10 deploy.
- `v` ignored (9 vs 10); `phase` compared as the string.
- `tests/oracle/allowlist.json`: `[{scenario, act: int|"*", path: "units[3].x"|"squads.*.engaged"|…, reason}]`; every
  entry needs a reason that names a §7 item. Expected entries: deploy placement near props (§7 #2, until `units0`),
  facing-dependent spawns (`three_ffa_…_40`, troy) (§7 #7), `planMove` on Claude `x/z` acts (none recorded).
- Coverage gaps of the recordings (no `chr keep`, no Claude-form `smove`, one `shoot`, no staged human shot / heal /
  gren because of the recorder's `BT.aim` id bug) are covered by unit tests in `test_acts.gd`/`test_pend.gd` until the
  recorder is fixed and re-run (§9 Q2).

---

## 7. Intentional v10 differences (for `docs/GODOT.md` and the allowlist)

1. Integer field: fixed-point noise and props, `ihash2/ihash3` instead of the page's hash (new terrain, props and
   building depths per seed). Oracle props are injected, so only goldens see this.
2. Integer search tables and formation: `free_spot`, `room_to_land`, `plan_move`, `charge_spots`, deploy rings and
   `formation` use the committed `BtOffsets` tables / `isin_q16`, every point rounded to 0.01" (10 MI). Positions may
   differ by ≤ 0.005" and a borderline candidate may flip to the next ring.
3. Checked point = emitted point: `plan_move` and `charge_spots` check candidates already on the 10 MI grid (the page
   checks the unrounded point and sends `toFixed(2)`).
4. Exact geometry: squared-distance comparisons, `js_round` mean centres, exact `next_victim` (no division),
   `isqrt`-based edges with an index tie-break for `fight_target`/bot sorting, exact charge need, exact rational
   `exp_dmg` and survivor points. Near-ties within 1 MI may resolve differently from V8 doubles.
5. Bot and Claude armies from PCG32 `armies:<seat>` (fresh per call, `bounded(15)` faction, `bounded(20) < 9`) instead
   of `Math.sin`-based `seededRoll`: every bot army differs from v9 (oracle lists are injected).
6. Dice padding and the 60-dice cut come from `fallback:<seq>:<stage>` on every device (the page padded with each
   device's `Math.random`: a desync).
7. Rules facing per squad (`fx, fz`): set at deploy (towards the table centre), copied by spawns, updated by `smove`
   (old → new centre, if > 0.3") and `cmove` (towards the target). It replaces the page's visual `rot` in `plan_move`'s
   short-move facing and `spawn_from`'s exit point while a carrier model lives (the page read a per-frame animation
   value: a v9 desync). A carrier that died opens towards `(0, 1000)` as on the page (`face = 0`).
8. Rules state the page kept in visual lists: wind bodies live in `st.bodies` (the page's `FALLEN` was pruned by tray
   timing); `after_kills` spawns from the dead model's rules position (the page used the drawn position).
9. `owatk → charge` is promoted deterministically in `BtPend.prune` after every act (the page promoted it in the
   frame-driven `myRoll`, so PEND stages differed between devices between acts).
10. Seats, `cp`, `bot` flags and lists are frozen when play starts; room polls during play change only owner and
    display names (the page's `adoptRoom` rebuilt seats without `cp` every 1.5 s, wiping CP online — a desync — and
    a mid-game `/leave` shifted seat indexes).
11. Phase ends always travel as acts. Offline `btEnd` (one device plays the whole team) sends `endph {ph}` — the page
    called `nextPhase` directly, so a hot-seat team of two humans ended together; a `done` with one seat's pid would
    wait for the other. Offline per-seat `btDone` sends `done {ph, pid}` with that seat's local pid (page:
    `playerDone`). Online both send `done` as before. Offline act logs were incomplete on the page.
12. Any seat whose list is still empty at match start gets the seeded `armies:<seat>` list on every device (the page
    used `Math.random` for a human seat: a desync).
13. `auto_list` never puts more than `SLOT_MAX` (99) squads of one type in a list (the page's fill loop could reach 220).
14. Deployment points are rounded to 0.01" where they are made (tap and `auto_dep`), so the sender and receivers hold the
    same value the wire carries.
15. `inf` (foot soldier) is a data field exported from the page's kit info, not computed from kit scale at run time
    (same values: 166 foot, 108 not).
16. Board positions use `toFixed(1)` semantics (`Fx.to_fixed_1`), not `js_round` (ARCHITECTURE §4 corrected; this is
    page parity, listed so nobody "fixes" it).
17. Bot seats' `done` is never set in core. The page set it in `botTick` on the owner's device only, so it differed
    between devices; no rule reads it (`allDone` skips bots, `nextPhase`/`startTurn` clear it), and in v10 it would
    otherwise split the digest.

Not differences (kept on purpose, page parity): receivers do not re-validate `chg`, `heal`, `gren`, `cmove`, `atk`
(the sender is trusted; a mismatched `atk` stage creates a new attack as on the page, logged `atk_new`); `gtg` spends CP
even when it cannot help; overwatch is offered on edge range even with 0 shooters in centre range; `endph ""` in `cmd`
ends the turn; `canAct`/bots never use the "charge after advancing / falling back" abilities (only Claude can);
revived wind squads keep stale flags; `depCapacity` vs `depSlots` at odd widths; `TY(unknown)`: core refuses unknown
type keys at list fitting, so it cannot arise.

---

## 8. Implementation order and parallel pairs

Each line of a wave is one agent / branch / PR; agents of a wave touch disjoint files. A wave starts when the
previous wave's modules are merged (later modules call earlier ones for real; tests do not stub).

| Wave | Agent A | Agent B | Agent C |
| --- | --- | --- | --- |
| 0 (done) | `state.gd` + `test_state.gd` + this spec | — | — |
| 1 | `offsets.gd`, `tools/gen_offsets.gd`, `blocking.gd`, `Fx.cdiv/isqrt_ceil` (+ `test_offsets`, `test_blocking`, `test_fx` additions) | `squads.gd`, `strats.gd` (+ `test_squads`, `test_strats`) | data: `tools/export_data.js` adds `inf` per type and `GREN_R`, `HEAL_ON`, `PAIN_ROUND` to `constants.json`; `GameData.is_inf`; `test_data` drift; `Version.DATA_HASH` |
| 2 | `army.gd`, `objectives.gd` (+ tests) | `combat.gd`, `abilities.gd` registry + accessors (handlers that need `pend` come in wave 3) (+ `test_combat`) | `moves.gd` (`plan_move`, `apply_smove`, `charge_spots`, `try_move`, group plan) (+ `test_moves`, perf budget) |
| 3 | `pend.gd` + the `abilities.gd` handlers (glory, revive, wind, spawn, after_kills, shields) (+ `test_pend`, `test_abilities`) | `board.gd` + `acts.gd` codec part (`CODES`, `sanitize`, `to_wire`) (+ `test_board`, codec half of `test_acts`) | oracle harness: `tests/oracle/page_hash.gd` (+ its own tests vs page values sampled in Node), `test_oracle.gd` loader/fixture/compare written against §5–§6 (skips until `Battle` exists), `allowlist.json` (empty) |
| 4 | `turn.gd` (+ `test_turn`) | `roller.gd`, `bot.gd` (+ `test_bot`) | `net/json_num.gd` wire numbers (+ tests) — outside core, disjoint |
| 5 | `acts.gd` dispatcher + `battle.gd` (+ handler half of `test_acts`, `test_battle`) | `tools/make_golden.gd`, `tests/golden/*.json`, `test_golden.gd` (x86 + arm64 in CI) | `test_smoke_bots.gd` (30 games, legality checks), `test_perf_core.gd` |
| 6 | integration: oracle green with a reviewed allowlist, `docs/GODOT.md` (code map, invariants, §7 list), decision memo "v10 gate" | — | — |

Parallel pairs inside one wave share no file: wave 1 A touches `core/battle/{offsets,blocking}.gd`, `core/fx.gd`,
`tools/gen_offsets.gd`, `tests/unit/test_{offsets,blocking,fx}.gd`; B `core/battle/{squads,strats}.gd` + their tests;
C `tools/export_data.js`, `data/*.json` (regenerated), `core/data.gd`, `core/version.gd`, `tests/unit/test_data.gd`.
`abilities.gd` is split across waves 2 (B) and 3 (A) on purpose; the wave-3 agent owns the file from then on.
`state.gd` is frozen: a module that needs a new field asks the lead, who adds it (one small PR) so parallel agents
do not collide in it.

---

## 9. Decisions taken here and open questions

**Decided (reader questions settled in this spec):**

- D1 `seededRoll` → PCG `armies:<seat>`, fresh per call (§3, §7 #5).
- D2 Wind bodies in core state (`bodies`), counted by `live_of` (§7 #8).
- D3 `auto_list` clamps at SLOT_MAX (§7 #13).
- D4 Margins 1050 MI (`near_foe`) and 50 MI (`apply_smove`) kept; tolerances `+0.001"` = `+1 MI` (§2).
- D5 Rules facing per squad (§7 #7), not per model: the only readers use model 0 of a squad, which changes on deaths.
- D6 `center` = `js_round`; `edge` = `isqrt` value with an index tie-break; charge need exact via `isqrt_ceil`.
- D7 Board rounding `to_fixed_1`; oracle compares unrounded MI against the page's tenths with 60 MI (§6).
- D8 Offline act pids: each non-bot seat gets a local pid (`"L<seat>"`) at match start; per-seat `done` carries it,
  the team-wide offline end is `endph` (§7 #11). Online the server's pid. Bot acts carry `""`. `Table`/`ActLog`
  already accept any String pid. The seat `pid` is in the digest.
- D9 `act_seq` = core act-log seq, not the room seq (§3).
- D10 Overwatch range (edge), `gtg` permissiveness, receivers trusting senders, `atk` re-creation, `endph ""` from cmd,
  acts after `over`: mirror the page (convergent across devices; logged where odd).
- D11 Missing `adv`/`heal` roll → 1 as the page (unreachable through the Worker).
- D12 `inf` exported as data (§7 #15); `GREN_R`, `HEAL_ON`, `PAIN_ROUND` exported to `constants.json`.
- D13 Stratagem lock keys stay the page's strings (looked up only; sorted in snapshot and digest).
- D14 `mk` stored as `mark_key()` int (`round·16 + turn`), side-agnostic as the page.
- D15 Spawned squads get `vs = 0`; revived models carry no skin in core (the view picks the seat's skin).
- D16 Snapshot: compact rows for squads/units, bools as 0/1, 64-bit values as 16-hex strings (JSON-safe), props
  optional (`snapshot(false)` for the wire; restore keeps local props when the hash matches). Digest covers units in
  list order (stronger than ARCHITECTURE's "sorted by id": order is rules state).
- D17 Oracle building depths from an exact integer replica of the page hash in `tests/oracle/page_hash.gd`; injected
  prop scale `s4` = ×10⁴.

**Open — need the lead or the owner:**

- Q1 Re-record the oracle with `units0` (raw deployed positions and the page's `rot`)? Without it, unmoved squads differ
  from the page by the v10 deploy (≤ 0.005" plus occasional ring flips near props) and range/engagement/objective
  checks can flip at boundaries until a squad first moves. Recommended: yes, together with Q2 (recorder change, no
  page change).
- Q2 Fix the recorder's `BT.aim` id bug (pass `BT.sq(id)`) and add scenarios for `chr keep`, a Claude-form `smove {x,z}`
  and a human staged shot/heal/grenade, then re-record all 20 (`--check` stays byte-stable)?
- Q3 Online human dice: seeding `dice:<seat>` from device entropy keeps dice unpredictable but makes an online game
  non-reproducible from its setup alone (the act log still replays it). Accept? (Offline and goldens stay seeded.)
- Q4 Mixed human/bot teams: a human's `done` ends the phase even if the team's bot squads have not acted (page parity,
  `all_done` ignores bots). Keep, or make the owner finish the team's bots first (a rules change → RULES_V note)?
- Q5 Charge after advancing/falling back (`ac`, dark-elf pain, `fly`, `ttn`) is legal in the rules but blocked by the
  page's UI gate and bots; only Claude uses it. Keep the gate in the v10 UI and bots, or open it (behaviour change)?
- Q6 Spectator mode: `auto_list` uses `base_cap` (250/players), not the spectator cap (3000/players), and `fit_list`
  clamps hidden types to 1 even for spectators. Kept for parity; the owner may want bigger spectator bot armies.
- Q7 Odd table widths: keep the `dep_slots` single-column quirk (corner, not centre) and the `dep_capacity` mismatch at
  w ≡ 5 (mod 20)? They only arise from a raw room setup or tests (the slider uses even widths).
- Q8 Wall block zone is symmetric while the page draws walls shifted by half a segment: the v10 renderer should draw
  the rules shape (props_layer track), confirm.
- Q9 Is the room `state` act the right moment to freeze seats (§7 #10)? A seat that drops during play becomes a bot
  only for the owner's bot driver (which then plays it); its flags in core stay as frozen. Confirm with the net track.

**Lead decisions on Q1–Q9 (7 Oct):**

- Q1, Q2 yes: the wave-3 oracle agent changes the recorder only (`units0` with the page's raw deployed positions and
  `rot`, the `BT.aim` id fix, the four extra scenarios) and re-records all 20; the page is not touched.
- Q3 accepted: online human dice come from device entropy and travel in the acts; offline, bots and goldens stay seeded.
- Q4, Q5, Q6, Q7 keep page parity in R1. Each one is a possible later rules change, listed for the owner in the R1
  Thai note; none of them changes RULES_V now.
- Q8 yes: the renderer draws the rules shape of a wall (props_layer track).
- Q9 yes: seats freeze at the room `state` act; a dropped seat is played by the owner's bot driver.
- Offline team end of phase stays `endph` (critic's open point); the per-seat button sends `done`.
