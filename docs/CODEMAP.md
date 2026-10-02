# Candlelight Table — code map for agents

Navigation map of the `candlelight-table` repo for AI coding agents (OpenAI Codex, Claude) arriving with no context.
The **rules** (branches, PRs, hard rules, review checklist) are in `AGENTS.md`; this file says **where things are**.
Mapped at commit `e556889` · battle table `APP_VER` **9.4** · rules version **9** · 274 unit types in 15 armies.

**Anchors, not line numbers.** Every location below is an exact string that occurs **once** in its file (otherwise
marked "first of N"); line numbers drift with every edit. Search with fixed strings, e.g.
`grep -nF 'function drawScene(' app/src/main/assets/battle-table.html`. The two big pages are hand-written single
files (no build step, no libraries, comments mostly Thai): edit them surgically, never reformat or reorder them.

## 1. Repository layout

| Path | What it is | Who loads / runs it |
| --- | --- | --- |
| `app/src/main/assets/battle-table.html` | โต๊ะรบ, the battle table: one self-contained page, ~35.7k lines, 3.3 MB | Android `TabletopScreen` from `file://` (offline); desktop start page iframe (offline; CI copies it in); the server embeds it (`/tabletop/battle-table`) and the web app `/app` shows it in an iframe `srcdoc` (online: browser, Android WebView, .exe); `tests/` from `file://` |
| `app/src/main/assets/board.html` | 3D D&D board, ~2k lines | server embeds it (`/board`); the web app puts it in iframes with an injected `window.Android` bridge. The Android app no longer loads it directly |
| `app/src/main/java/dev/mini/candlelight/` | Android app (Kotlin, Compose): login / splash / offline screens, WebView shell of `/app`, bundled battle table | Gradle module `:app` |
| `app/build.gradle.kts`, `build.gradle.kts`, `settings.gradle.kts`, `gradle.properties` | AGP 8.5, Kotlin 2.0, SDK 34 (min 26), JDK 17. **No Gradle wrapper**: CI uses Gradle 8.9 | CI, local `gradle` |
| `desktop/dist/index.html` | Windows start page: online → server `/app`; offline → `battle-table.html` in an iframe | Tauri window (`url: index.html`) |
| `desktop/src-tauri/` | Tauri 2 shell: `main.rs` (no IPC), `tauri.conf.json` (NSIS installer, CSP off), icons | `npx @tauri-apps/cli@2 build` (Windows only) |
| `desktop/make-icons.py`, `desktop/README.md` | icon generator (no deps); Thai README (online → `/app`, offline → bundled battle table) | by hand |
| `web/สิ่งที่เปลี่ยน-*.md` | Thai release notes, one per release (latest `…1ต.ค.69-รุ่น9.4-…`): what changed, tests, merge order | the owner |
| `web/อ่านก่อน-วิธีทำ.md`, `web/วิธีใช้-Claude-กับ-Codex-ทำงานคู่กัน.md` | original technique notes + hard-won constraints (Canvas 2D only, self-sizing canvas); owner's guide to two agents | humans |
| `web/harness.js`, `h3.js`, `sync_baked.js`, `bt_walk.js` | node harnesses: slice the MODULES block out of the page, measure gait / foot slide | `node web/harness.js` |
| `web/dice-core.js`, `web/dice-check.js` | master copy of the dice physics; check that both pages embed it byte-identically | `node web/dice-check.js` |
| `web/armor.js`, `kits.js`, `ctrl4.js` | stand-alone legacy copies of rig code from a removed page; nothing loads them | reference only |
| `tests/` | Playwright suites driving `window.BT` + the desktop start page (`tests/README.md`) | `bash tests/run.sh [quick or full or <suite>]` |
| `.github/workflows/build.yml` | PR: debug APK + Windows build check; push to `main` / manual: signed APK + .exe, GitHub release `build-N` | Actions |
| `.github/workflows/tests.yml` | quick test set on every PR (full on demand) | Actions |
| `AGENTS.md`, `CLAUDE.md`, `.github/pull_request_template.md` | agent rules (CLAUDE.md imports AGENTS.md), PR template | agents |
| `../candlelight-server` (sibling repo) | Cloudflare Worker `worker.js` (API, rooms, Claude's MCP tools, embedded pages), web app `app.html`, `embed.py` | deploys itself on merge to its `main` |

## 2. `battle-table.html` — โต๊ะรบ

### 2.1 Shape of the file

- Starts with `<meta charset="utf-8">`: no `<!doctype>`, `<html>` or `<body>`, so it renders in quirks mode when opened
  directly (Android, desktop, tests) but in standards mode inside the web app's `srcdoc` iframe; check CSS in both.
  Then `<style>` (every rule scoped under `#bt`), the markup `<div id="bt">`, and **one** `<script>`.
- Script order: `// ==MODULES-BEGIN==` → `var SKRIG` (rig, ~570 lines) → `var MINI` (every figure, ~28k lines) → `var WALKER`
  → `// ==MODULES-END==` → `// ==DICE-BEGIN==` … `// ==DICE-END==` → the game IIFE (`"use strict"`, ~6.3k lines, first
  line `var TAU = Math.PI*2, DEG = Math.PI/180;`) → `window.BT = {` → init calls.
- MINI and the game IIFE are each **one function scope**: a second `function name(` silently replaces the first
  (hoisting; a live case is in §7). Before adding a top-level function run `grep -c '^function name(' <file>`.
- Redraw on demand: `frame()` draws only when `dirty` is true, so set `dirty = true` after any visible change. Nothing
  animates while idle (keeps phones cool).

### 2.2 Markup and UI ids

| Banner anchor | Panel | Key ids (prefix `bt`) | Painted / handled by |
| --- | --- | --- | --- |
| `<canvas id="btCv">` | board | `btHud`, `btTurn` (turn bar), `btDice` (pop-up), `btTray` (+`btTrayCv`, `btRoll`, `btAuto`, `btAimX`, `btTrayX`) | `drawScene`, `hud`, `popDice`, `paintTray` |
| `<!-- ══════════ ตั้งสนาม ══════════ -->` | `scSetup` | `btMaps` (data-t theme), `btSize`, `btNew`, `btTer` (data-r terrain), `btBld`/`btDens`, `btModes` (data-g pve/pvp/team/ffa/custom/spectator), `btPerTeam`, `btFfaN`, `btSpecN`/`btSpecOwn`/`btSpecDep`, `btPtsPick`, `btGoal`, `btRounds`, `btFire`, `btClock`, `btName`/`btHost`/`btJoinCode`/`btJoin`, `btNext` | `syncSetupUI`, `syncRulesUI`, `applyMode`, `paintMapCards` |
| `<!-- ══════════ จัดกองทัพ ══════════ -->` | `scArmy` | `btPts`, `btWho`, `btFacs` (data-f army code), `btRandU`/`btRandA`, `btUsedV`, `btRoster`, `btDetail`, `btStart` | `paintRoster` |
| `<!-- ══════════ ล็อบบี้ ══════════ -->` | `scLobby` | `btRoomCard`, `btSeats`, `btLeave`, `btLobbyGo` | `paintLobby` |
| `<!-- ══════════ เลือกจุดลงสนาม ══════════ -->` | `scDeploy` | `btDepWho`, `btDepAuto`, `btDepAll`, `btDepGo` | `paintDeploy`, `tapDeploy` |
| `<!-- ══════════ เล่น ══════════ -->` | `scPlay` | `btCard`, `btAct` (data-a per phase), `btGroup`, `btEnd`, `btSpec` (`btPause`, `btSpd`, `btStep`, `btAgain`), `btDone`, `btLog`, `btQuit` | `paintPlay`, `paintActs`, `sqCard`, `paintSpec`, `paintLog` |
| `<!-- ══════════ กำหนดเอง (แซนด์บ็อกซ์เดิม) ══════════ -->` | `scCustom` (sandbox) | `btMode` (look/place/measure/erase), `btKit` | `paintKitPal` |
| `<!-- ══════════ กล้อง (ทุกหน้า) ══════════ -->` | always shown | `btPan`/`btTop`/`btEye`/`btFit`, `btSnd`, `btMusSt`, `btVol`, `btGfx` (data-g hi/mid/lo/min), `btLang` (data-l th/en), `btVer` | `paintSnd`, `paintGfx`, BT_I18N |
| `<div class="pvov hide" id="btPv"` | unit preview dialog | `btPvN`, `btPvC` (canvas), `btPvV`, `btPvS`, `btPvX` | `openPreview`, `pvDraw` |

`show(id)` switches the six `sc*` panels. `#bt .hide{display:none !important}`; the two-column layout is under
`@media (min-width:900px) and (min-height:560px)` (first of 2).

### 2.3 Modules block (pure JS; node harnesses `new Function()` it)

| Anchor | What lives there | Gotchas |
| --- | --- | --- |
| `// ==MODULES-BEGIN==` … `// ==MODULES-END==` | SKRIG + MINI + WALKER, sliced out by `web/*.js` harnesses | must stay DOM-free (no `document`, `window`, `localStorage`); markers unique |
| `var SKRIG = (function(){` | skeleton rig: quaternions, `// ---- skeleton: +Y up, figure faces +Z` (1 unit = 1 m), gait generator, attack pose, `function Controller(` (one travel speed, planted feet pinned to the ground, leg IK), `idlePose`, `fk` | 0 mm planted-foot slide is what the harnesses measure |
| `Controller.prototype.thinBody` | 9.4 "thin walk": advances gait state (phase, feet, travel) without building the body pose; `Controller.prototype.repose` builds it when needed (`ctl.stale`) | must advance exactly the state `body()` would, so positions stay identical on every device and level |
| `var MINI = (function(){` | every figure (§2.4); exports `build`, `pose`, `kitInfo`, `KITS`, `SOLID` | ~1,700 functions in one scope |
| `var WALKER = (function(){` | walks a piece to a table point with the rig's own gait; turns pivot on the planted foot | constants `C` come from `web/bt_walk.js` sweeps |
| `// ==DICE-BEGIN==` | shared dice physics: `DICE.roll(kind, value, seed)` replays a seeded throw that lands on `value` | byte-identical in both pages and `web/dice-core.js` |

### 2.4 Figures: MINI kits

- Building blocks, in order: `// ---------- armour: real geometry anchored to joint frames` (MINI's own
  `var FACES = [], FACE_POOL = [];`, `armQuad`, `armTube`), `var SOLID = {` (palettes),
  `// ---------- kits: whole figures built from primitives`, `// ---------- the horse (for the cavalry)`,
  `// ---------- actions (aim, draw, throw, thrust, brace)`, `// ---------- the kit registry: every figure the table can draw ----------`.
- A figure = `SOLID.<k> = { plate:[r,g,b], … }` + `kit('<k>', { build(Wd, mo), hold or pose(P), scale, h, mount, creature, mouth })`
  (`var KITS = {};`, `function kit(k, def)`). `hold` is 'gun', 'shield' or 'bow'; `mo` = `{ travel, v, act, rider, fly }`.
  Palette keys listed in `var NATURAL = {` (game script) keep their colour; the rest are dyed with the team colour.
- `function kitInfo(k)` falls back to `KITS.heavy` for an unknown key. `MINI.build(kit, Wd, lod)` sets `LODK`
  (`LODS` = 1, 0.65, 0.45, 0.3); army helpers drop facets and small details by `LODK`. MINI returns its **own** face
  pool: copy or draw it before building the next piece.
- Army blocks follow, each with its own helper prefix (a new helper needs a unique name; prefix it):

| Banner anchor | Prefix | Banner anchor | Prefix |
| --- | --- | --- | --- |
| `// ════════ รอบ 3 · อัศวินเกราะพลัง` | `kn_` (+ the walker) | `// ════════ รอบ 6 · อัศวินเกราะพลัง ครบกองทัพ` | `ka_`, then `kb_` … `ke_` |
| `// ════════ รอบ 3 · ฝูงสัตว์ต่างดาว` | `sw_` | `// ════════ รอบ 6 · ฝูงสัตว์ต่างดาว: หน่วยที่เหลือ` | `sa_`, `sb_` |
| `// ════════ รอบ 3 · หุ่นยนต์โลหะโบราณ` | `rb_` | `// ════════ รอบ 6 · หุ่นยนต์โลหะโบราณ ชุดเสริม` | `ra_`, `rc_`, then `dm_` |
| `// ════════ รอบ 3 · ออร์คเขียว` | `or_` | `// ════════ รอบ 7 · ออร์คเขียว: วีรบุรุษ` | `ora_` … `ord_` |
| `// ════════ รอบ 3 · วีรบุรุษกับอสูรกรีก` | `gm_` | `// ════════ รอบ 7 · เอลฟ์อวกาศ (space elves) — style lead` | `ela_` (`elb_` … `ele_` later) |
| `// ════════ รอบ 3 · ม้าไม้` | `gx_` | `// ════════ รอบ 7 · เอลฟ์มืด (dark elves) — style lead` | `dea_` (`deb_` … `dee_` later) |
| `// ════════ รอบ 3 · ตำนานสยาม` | `th_` | `// ════════ รอบ 7 · จักรวรรดิผิวฟ้า (the blue-skinned empire, style lead` | `taa_` (`tab_` … `taf_` later) |
| `// ════════ รอบ 3 · ซามูไร` | `lg_` | `// ==KITS-EXTRA==` | harness splice point (§7) |
| `// ════════ รอบ 4 · ญี่ปุ่น` | `jp_` | `// ════════ รอบ 8 · อัศวินทรยศ ทหารราบ` | `cxa_`, `cxb_` |
| `// ════════ รอบ 4 · นักรบนอร์ส` / `// ════════ รอบ 4 · เทพนอร์ส` | `na_` / `nb_` | `// ════════ รอบ 8 · ปีศาจ (daemons)` | `dma_` + two big daemons |
| `// ════════ รอบ 4 · อียิปต์: เทพเจ้า` / `// ════════ รอบ 4 · อียิปต์ (Egypt)` | `ea_` / `eb_` | `// ════════ รอบ 8 · ภาคีของอัศวินเกราะพลัง` | `kca_`, `kcb_`, then one last block before WALKER |
| `// ════════ รอบ 4 · ทหารราบยุคกลาง` / `// ════════ รอบ 4 · อัศวินยุคกลาง` | `ma_` / `mb_` | | |

### 2.5 Game script, in file order

| Anchor | What lives there (key names) | Gotchas |
| --- | --- | --- |
| `var TAU = Math.PI*2, DEG = Math.PI/180;` | start of the game IIFE; `$`, clamp, lerp | |
| `// ---------- deterministic noise ----------` | `var SEED = 1;`, `hash2`, `vnoise`, `fbm` | SEED (1–99999) drives terrain, props, objectives, bot and Claude armies |
| `var THEMES = {` | maps ruin/forest/desert/ice (colours, relief, sky); `var TERRAINS = {` flat/hills/mountain/forest; `buildings`, `density` | server allowlists the names (`BT_THEMES`, `BT_TERRAINS`) |
| `function buildTerrain(){` | heightfield `HG` over `table` {w, d} (1 game inch = 1 m; d = round(w·0.72/2)·2); `function heightAt(x, z)` | always followed by `genProps()` (it levels ground under buildings) |
| `function canvasSize(){` | camera `cam`, self-sizing canvas, `resize`, `setupCam`, `function proj(p)`, `function groundHit(sx, sy)` | a WebView reports 0 px at load: keep the re-measure |
| `var GFX_OPT = {` | graphics levels (§2.10), `GFX`, `gfx()`, `function adaptScale(ms){`, `function slowStep(){` | |
| `var FACES = [], LIGHT` | the scene's face list: `function face(pts, col, opt)` (project, cull, shade), `function shade(col, n, amb)`, `box`, `prism`, `bigBase` | not MINI's `FACES` |
| `function drawGround(step)` | ground mesh, `function drawRails()` | |
| `function genProps(){` | scatter terrain: `var PROPS = [];`, `var STRUCT = {`, `var PROP_CAP = 480;`, `levelUnder`, `woods`, `building`, `drawProp`, `propSimple` | output must be identical on every device |
| `// ---------- miniatures: each piece is the rig in its armour kit` | `teamTint`, `var UNIT_COL = {`, `colOf`, `var units = [];`, `var LODS = [1, 0.65, 0.45, 0.3];`, `var VARIANTS = {` (per-model looks), `var SKINS = {`, `kitOf`, `function kitScale(k)`, `rigFaces` (idle cache → frozen rest pose → live pose) | `units` is exposed as `BT.units`: mutate in place, never reassign |
| `function stepUnits(dt){` | `unitGoTo` (sets `gx`/`gz`), `unitStop`, thin-walk switch `u.ctl.thin = POT`, snap to `gx`/`gz` on arrival | |
| `var FLY_K = {` | fliers: hover height, wing beats, `flyStep`, `stepFlight`, `flyFaces`, `unitY`, `airborne` | flight is cosmetic: rules see the base |
| `function drawUnit(u){` | `var NATURAL = {`, `rigPal`, `drawRig`, `planLod` (LOD from on-screen height), `tuneLod` (FACE_BUDGET), drawUnit (base, shadow, sprite or full rig, rings) | |
| `// ---------- far figures as pictures ----------` | sprites: `var SPR = {}, SPR_N = 0`, `spriteUnit`, `spriteMake` (cache 700, ≤ 24 new per frame) | |
| `var SKY = {` | sky and far skyline per map: `PANO`, `panoOf`, `DUST`, `drawBackdrop` (screen space, no facets) | |
| `function drawScene(){` | per frame: backdrop → `planLod` → ground, rails → props → units + `FALLEN` → rings, rulers → `fxDraw` → `gameOverlay` → `function sortFaces(){` (typed-array sort) → fills batched by colour → `OVER` callbacks → `hud` | neighbours with the same `fill` share one path |
| `// ═══════════════════ เกม ═══════════════════` | Thai summary of the rules, then `var TYPES = [` (§2.6) | |
| `var FACS = [` | the 15 armies; `fitList`, `facOf`, `function TY(k)`, `var ENGAGE = 1;`, `var CHARGE_R = 12;`, `maxRound`, `var PHASES = [`, `var TEAMS = [` (8 colours) | |
| `var G = { on:false` | match state (§2.7); `var SPEC = { speed:1`, `mkPlayers`, `canTarget`, `depCapacity`, `var DQ = [];` + `function d6(){`, `function gx(u)`, `ptsOf`, `teamPts`, `liveOf` | `d6()` is Math.random unless a test queued dice |
| `var SQ = {}, SQ_ORDER = [];` | squads: `sqModels`, `sqAlive`, `sqList`, `sqEdge`, `engagedWith`, `isEngaged`, `sqHalf` | ids: squad `<player>:<i>`, model `<squad>.<j>` |
| `function seededRoll(n){` | army building: `var CORE = {` (bot pools per army), `var SLOT_MAX = 99;`, `function baseCap(){`, `var SPEC_TOTAL = 3000;`, `armyCap`, `slotMax`, `function autoList(s, free)`, `formation`, `function deploy(){`, `depWhyNot`, `autoDep` | bot and Claude seats get armies from SEED + CORE on every device |
| `var BLOCK_R = {` | where a base may stand: `propBlocks`, `blockAt`, `crowded`, `function freeSpot(` | |
| `var LOG = [];` | battle log `say()`, `paintLog`; `popDice` pop-ups | text is translated by BT_I18N |
| `function atkMath(s, t, how){` | attack maths: `woundNeed`, `INF`, `shootersOf`, `var AURA_R = 6;`, `painOn`, `pactOn`, `marked`, `inAura`, `rollN`; legality `function shotWhyNot(s, t)`, `function chargeWhyNot(s, t)`, `healWhyNot`, `grenWhyNot` | hit modifiers capped at ±1; WhyNot messages need English entries |
| `var STRATS = {` | command-point stratagems rr, ow, gtg, gren, brave; `canStrat`, `useStrat` | once per team per phase (brave: per turn) |
| `var PEND = [];` | pending rolls and decisions: `var AUTO = (function(){`, `mkAtk`, `applyHit`, `applyWnd`, `applySav`, `dealDamage`, `finishAtk`, `applyShock`, `applyCharge`, `applyGren`, `applyHeal`, `applyRez`, `rollerOf`, `iRollFor`, `function myRoll(){`, `function doRoll(r, opt)`, `flushPend`, `botChoice` | `apply*` pad a short dice array with local `d6()` (desync if an act arrives short) |
| `var TRAY = { q:[], cur:null, t:0 };` | the dice tray on screen: `STAGE_NM`, `seedOf`, `trayThrow`, `trayTick`, `paintTray`, `drawTray` | |
| `var ANIM = {` | attack animation per unit (ranged style, gun, melee style, shield), `TRACER`, `FLAME`, `var ACT_FN = {`, `die8`, `actTick` | visuals only (Math.random allowed) |
| `function startAttack(u, tgt, P, hits)` | shots and blows timed by the tray: `onThrowStart`, `onThrowSettle`, `GUN_T`, `fxDraw`, `drawFx`, `drawFx8` | |
| `var FXS = {` | weapon effect kinds, `FX_GUN`, `fxOf`, `MACH8` (machines explode), particles `var PT8 = [], PT8_N = 0`, `glowOn`, shake `SHK8`, `blast8`, titan stomp | per-level tables (§7) |
| `var SND = (function(){` | sound and music (§2.11) | |
| `var OBJ = [], OBJ_R = 3` | five objectives: `placeObjectives`, `objCtl`, `scoreObjectives` (5 VP each from round 2, ≤ 15 a turn) | |
| `function startTurn(){` | turn engine: `finishCommand`, `nextPhase`, `startFight`, `scheduleFight`, `prunePend`, `function advance(){`, `playerDone`, `startClock`, `pushBoard`, `function boardState(){`, `var RULES_V = 9;`, `var APP_VER = '9.4';`, `endTurn`, `finish`, `checkOver`, `endRoundCheck` | |
| `function planMove(s, x, z)` | moving squads: `moveRange`, `spotFree`, `applySMove`, `tryMoveSq`; group move `function groupMove(x, z)` | deterministic: Claude's moves send only x, z |
| `function tapGame(p)` | `canAct`, `selectUnit`, `aimAt`, `doCharge` | |
| `function botStep(){` | bots: `expDmg`, `botSkip`, `function botTick(dt, step)` | in a room only the owner runs bots |
| `function paintRoster(){` | screens: `show`, `var CHAPTERS = {`, `paintPlay`, `abilityText`, `sqCard`, `paintActs`, `paintSpec`, `paintDone` | hidden units are filtered here |
| `function gameOverlay(){` | pins (`pinAt`), `depOverlay`, `drawObjectives`, `fireLine`; `paintMapCards` | |
| `function frame(ts){` | `simStep` (walks × spectator speed, `botTick`, `clockTick`, `trayTick`, `actTick`), redraw if dirty, `adaptScale`, `sharpFrame` | `CLOCK_STOP` (tests) |
| `// ---------- input ----------` | pan / pinch / right-drag / WASD; camera helpers `panScreen`, `fitTable` above it | |
| `// ---------- ปุ่ม ----------` | `applyTheme`, `setTerrain`, `quantDens`, `setBuildings`, `syncSetupUI` | |
| `var NET = { on:false` | rooms (§2.9): `var SERVER = (function(){`, `netPost`, `function curSetup(){`, `netStart`, `function netPoll(){`, `function netSend(act){`, `function adoptRoom(R){` | |
| `function netAct(a){` | applies one remote act; `applyWhole`, `rollFor`, `function applyAct(a){`, `adoptRoster`, `netPhase`, `resolveBots` | |
| `function paintLobby(){` | lobby, `applyMode`, `growTableFor`, `var BUDGETS = (function(){`, `setBudget`, `setMode`, `syncRulesUI`, `function netJoin(raw)`, `function joinFromOutside(code, nm)`, `newField`, `randomArmy`, `function openPreview(i)` | |
| `function startMatch(){` | `toDeploy`, `paintDeploy`, `tapDeploy`, `startMatch`; play-screen buttons (`btAct`, `btEnd`, `btRoll`, `btAuto`, `btDone`) | |
| `function quitGame(){` | quit; spectator `function spectate(){`, `specPlace`, `spectateBuilt` | |
| `function setGfx(v){` | graphics buttons; `var BT_LANG = (function(){`, `var BT_I18N = (function(){`, `BT_I18N.start();`; spectator buttons; `function paintKitPal(){`; first draw; `$('btVer').textContent` | |
| `window.BT = {` | test hook (§2.12); then `paintSnd` and the init calls | |

### 2.6 Datasheets: how a unit is defined (`var TYPES = [`)

**Order is protocol.** An army list is an array of squad counts indexed by TYPES position; it travels between devices
and to the server. Append new types at the end; never insert, reorder or delete.

| Field | Meaning |
| --- | --- |
| `k` | unique key; also the MINI kit key and the server's `BT2` key |
| `fac` | army code (table below); `'*'` = usable by every army |
| `nm`, `d` | Thai name, Thai description (both need English entries) |
| `n`, `pts` | models per squad, points per squad |
| `mv`, `T`, `sv`, `inv`, `w`, `ld`, `oc` | move ("), toughness, save (n+), invulnerable save, wounds per model, leadership (2d6 ≥ ld), objective control |
| `r` | base radius in inches (default 0.8) |
| `gun`, `mel` | ranged weapon (or `null` = must charge), melee weapon |
| flags | `hero`; `brave` (always passes nerve); `aoc` (incoming AP −1); `aura` 'hit'/'ld'/'bless'/'rez'/'veil' within 6"; `ac` (charge after advancing); `ca` (+1 attack after charging); `fly`; `st` (−1 to be hit by shooting); `rez` (self-repair n+); `wind` (stands up next command phase); `spawn` {k, n} (carried inside); `heel` (wound roll 6 kills); `heal` (heals friends within n"); `veh`; `ttn` (titanic: shoots while engaged, acts after falling back); `vsh` (shield layers); `gk` (heals by kills); `hd` (damage taken halved); `ch` (chapter heading, knights) |
| `sec`, `lk` | hidden units: free of the points budget, 1 per player outside spectator mode (`slotMax`). Hidden units exist; their unlock is intentionally undocumented |

Weapon fields: `nm`, `rng` ("), `a` (attacks per model), `bs`/`ws` (to hit n+), `s`, `ap`, `d`; optional `rf` (extra attacks
within half range), `as` (shoots after advancing), `pi` (shoots while engaged), `hv` (+1 to hit if the squad stood still),
`su` (hit roll 6 = extra hits), `tr` (hits automatically), `lh` (hit roll 6 wounds automatically), `dw` (wound roll 6 =
damage that ignores saves), `bl` (+1 attack per 5 target models), `po` (wounds infantry on po+), `mk` (a hit marks the
target: friendly shooting +1 to hit this turn), `la` (melee: +1 to wound after charging), `fx` (effect kind in `FXS`), `trail`.

| Code | Army (FACS) | Server English (`BT_ARMY_EN`) | Types | Army-wide rule in code |
| --- | --- | --- | --- | --- |
| `gr` | กองทัพกรีก | Greek | 13 | — |
| `mod` | กองทหาร | soldiers | 11 | default army (`facOf`) |
| `kn` | อัศวินเกราะพลัง | power-armour knights | 42 | five chapters: `ch` + `var CHAPTERS = {` |
| `sw` | ฝูงสัตว์ต่างดาว | alien swarm | 21 | — |
| `rb` | หุ่นยนต์โลหะโบราณ | ancient metal robots | 22 | (many `rez` units) |
| `or` | ออร์คเขียว | green orcs | 25 | (many `ca` units) |
| `th`, `jp`, `nr`, `eg`, `md` | ตำนานสยาม, ญี่ปุ่น, ตำนานนอร์ส, อียิปต์, อัศวินยุคกลาง | Siam legends, Japan, Norse legends, Egypt, medieval knights | 6, 7, 9, 9, 10 | — |
| `el` | เอลฟ์อวกาศ | space elves | 24 | may shoot after advancing (`shotWhyNot`) |
| `de` | เอลฟ์มืด | dark elves | 27 | `painOn`: from round 3, +1 to hit in melee and charge after advancing |
| `ta` | จักรวรรดิผิวฟ้า | blue-skinned empire | 30 | designators (`mk` weapons) |
| `cx` | อัศวินทรยศกับปีศาจ | fallen knights and daemons | 17 | `pactOn`: melee hit roll 6 = extra hit |

Points and caps: `G.budget` is per **team** (`shareOf()` splits it among team-mates; slider `BUDGETS` 200–40,000);
`function ptsOf(pi)` skips hidden units; models per player `baseCap()` = min(250, 500 / players); spectator mode allows
`SPEC_TOTAL` 3,000 models and starting over budget; `function fitList(L)` clamps incoming lists identically everywhere.

### 2.7 Match flow and turn engine

- Offline: `scSetup` → `btNext` → `scArmy` (one player at a time, `G.cur`) → `btStart` → `toDeploy`/`scDeploy` (tap a
  point; `depWhyNot`: ≥ `DEP_FOE` 20" from other teams, ≥ 5" from mates) → `startMatch()` → `scPlay`. In a room the
  owner moves everyone through lobby → army → deploy → play with `/state`; `netPhase()` follows on each device.
- `G`: `mode` (pve, pvp, team, ffa, custom, spectator), `teams`, `perTeam`, `budget`, `freeFire`, `clock` (0/25/50 s a
  phase), `goal` ('obj' or 'kill'), `rounds` (3–10), `turn` (team), `round`, `phase`, `sel`, `act`, `multi`,
  `players[]` ({id, pid, team, nm, bot, ai, list, fac, skin, dep, done, cp}), `mePl` (my seat in a room), `vp`, `used`,
  `fights`, `over`. `mkPlayers()` builds the seats (pve: other teams are bots; spectator: all bots).
- A team's turn runs `PHASES`: **cmd** (+1 CP each; nerve test 2d6 ≥ ld for squads below half; `rez`/`wind` rolls; carried
  units come out from round 2; objectives scored from round 2) → **move** (move, advance +d6, stay, fall back) → **shoot**
  → **charge** (≤ 12", 2d6 ≥ gap, the target may fire overwatch hitting on 6s) → **fight** (squads that charged first,
  then alternating from the side not in turn) → `endTurn()` (next team still alive; `round++` on wrap).
- `advance()` is the automatic engine: called after **every** action on **every** device; it finishes the command
  phase when tests are done, runs the fight order and ends the turn. Humans end phases with `btEnd` → `playerDone`.
- End: `checkOver()` (one team left) or `endRoundCheck()` after `maxRound()` (VP; ties broken by surviving points) →
  `finish(w, why)`. Goal 'kill' has no objectives and caps at 30 rounds.

### 2.8 Squads, combat maths and the dice tray

- A squad (`SQ[id]`) holds the turn flags (`moved`, `adv`, `fell`, `still`, `shot`, `charged`, `chDone`, `fought`,
  `shaken`, `vs`…); its models are entries of `units` with `sq`, `t` (type key), `k` (kit), `hp`, `x`/`z` (drawn),
  `gx`/`gz` (rules position while walking), `rot`, `scale`, `skn`.
- An attack: `mkAtk` → `PEND` entry (stages hit → wound → save) → `applyHit` / `applyWnd` / `applySav` →
  `dealDamage` (hurt models first, then the nearest) → `finishAtk`. `atkMath()` gives shots, to-hit, to-wound, save,
  damage. Other PEND kinds: `shock`, `adv`, `chg` (overwatch decision, roll, re-roll, move), `gren`, `heal`, `rez`.
- Who rolls: `rollerOf` (attacker rolls hit and wound; defender rolls saves and decides overwatch); `iRollFor` (this device
  rolls for its own seat; bots and Claude seats only offline or on the room owner's device; the owner rolls for a silent
  player after `OWNER_WAIT` 25 s). `AUTO` (`btAuto`) rolls instantly for you; `AIM` = target chosen but not yet rolled.
- The tray replays every result with `DICE.roll(6, value, seedOf(...))` keyed by attacker, target, round, turn and
  stage, so every screen shows the same tumble. Animations (`startAttack`) start and land on tray events.
- Bots (`botStep`): one action per call — move toward objectives or the nearest enemy (`planMove`), shoot the target with
  the best expected damage (`expDmg`), charge when worth it. `botTick` paces them, waits for the tray, and in a room runs
  only on the owner's device; their acts travel like a human's.

### 2.9 Network rooms and determinism

- `SERVER` = the page's own origin over http(s), else the workers.dev URL; the web app calls `BT.setServer()`.
  Endpoints under `/api/bt/rooms`: POST `''` (create with `curSetup()`), `/:code/join` {nm, v}, GET
  `/:code?since=<seq>&pid=` (polled every 1.5 s), POST `/:code/act`, `/list`, `/dep`, `/state`, `/team`, `/leave`,
  `/board` (owner sends `boardState()` so Claude can read the table).
- The room is the truth: `adoptRoom(R)` overwrites setup and seats on every poll (rebuilds terrain if the setup
  changed; empty or dropped seats become bots). Acts: `netSend(act)` (in order) → server adds `seq` → other devices
  poll → `applyAct(a)` (skips its own) → `netAct(a)` → `advance()`.
- Act codes: `smove`, `stay`, `skip`, `adv`, `atk`, `wnd`, `sav`, `rr`, `shoot` (a whole attack: Claude, tests),
  `shock`, `rez`, `chg`, `ow`, `chr`, `cmove`, `gren`, `heal`, `done`, `endph`; server-made `owner`, `state`.
- Determinism rules: (1) everything a device computes alone comes from the setup (SEED, theme, terrain, buildings,
  density, size, mode, budget, goal, rounds), the army lists and the ordered acts; (2) a random number is drawn on
  exactly **one** device (the roller; the owner for bots, Claude seats and timeouts) and travels in the act; (3) rules
  distances use `gx`/`gz`, never the walking `x`/`z`; moves travel as explicit points rounded to 0.01; walks snap to
  `gx`/`gz` on arrival; (4) visuals and sounds may use `Math.random` but must never feed rules state;
  (5) `tests/battle/net_sync*.js` replay one device's captured acts on another and compare `BT.board()`.
- The server sanitises acts (§4): an unknown act code gets HTTP 400, unknown fields are silently dropped, dice arrays
  are cut to 60 and move point lists to 40.

### 2.10 Renderer and graphics levels

| Level (`btGfx`) | dpr | render scale max/min | face budget | LOD factor | sharp when idle | potato |
| --- | --- | --- | --- | --- | --- | --- |
| hi สูง | 2 | 1 / 0.7 | 16000 | 1 | yes | |
| mid กลาง | 2 | 1 / 0.55 | 9000 | 1 | yes | |
| lo ต่ำ | 1 | 0.8 / 0.45 | 4500 | 1.6 | no | |
| min ต่ำสุด | 1 | 0.7 / 0.4 | 2500 | 2.4 | no | yes |

- First run guesses from `navigator.deviceMemory` (≤ 2 GB min, ≤ 4 GB lo, else mid); the choice is stored in
  localStorage `bt_gfx` (shared with the web app's settings). `adaptScale` lowers/raises the render scale from frame
  time; `slowStep` steps the level down once after a long run of > 60 ms frames (never up); `setGfx(v)` applies at once.
- Potato path (`gfx().potato`, first of 6): 10 light steps in `shade()` so neighbouring facets batch; coarser ground;
  props simplified sooner without shadows; far pieces (`lod` ≥ 2) without shadow, with a one-face base, drawn as
  sprites even while walking, and walking "thin" (`u.ctl.thin`); destination rings only for the selection; pins from
  cached pictures; at most ~30 drawn frames a second (`frame()`).
- Sprites: a small piece is drawn once into a picture per kit, team palette, 16 facings and camera angle bucket, then
  blitted in painter's order. `BT.sprites(false)` disables them for comparisons.

### 2.11 Sound, music · spectator · English · versions

- **Sound** (`var SND = (function(){`): synthesised with WebAudio, no audio files; starts after the first tap (`SND.unlock`).
  Effects: `var DEF = {` entries `{ gap ms, v, f(t, v, pan) }`, played by `SND.at(kind, point)` (panned, rate-limited,
  ≤ 22 voices); weapons map to sounds through `FXS[kind].snd` and `var LZ_SND`. Music lives inside SND too (there is no
  separate MUSIC object): map moods, `var SONGS = {` (three new songs) plus the older music, style 'mix'/'epic'/'old'
  (`btMusSt`), intensity follows the battle. Settings: localStorage `bt_snd`. `SND.probe(kind, cb, op)` renders offline.
- **Spectator** (`G.mode` 'spectator', card ผู้ชม): every seat a bot; `SPEC` {speed 1/2/4, paused}; `btStep` = one bot
  action, `btAgain` = again on a new field; `btSpecN` 2–8 sides, `btSpecOwn` (viewer builds armies), `btSpecDep` (viewer
  places deployment) → `spectate` / `spectateBuilt` / `specPlace`. Local only (`curSetup()` would report it as 'team').
- **English** (9.4, `// ---- ภาษา: เลือก English`): `BT_LANG` is 'en' only when localStorage `cl_lang` is 'en' (same key
  as the web app and the desktop start page); `btLang` stores it and reloads. `BT_I18N.start()` walks the DOM, watches it
  with `new MutationObserver`, and patches canvas `fillText`/`strokeText`/`measureText`, `alert` and `confirm`. The
  dictionary is one long line, `var EN = {"โต๊ะรบ":"Battle Table"` (~1,550 pairs, valid JSON). `tr()` tries the whole
  whitespace-normalised string, then fragments (longest key first); if any Thai is left the whole string stays Thai.
  Typed text and player names are left as typed (placeholders are translated).
- **Versions**: `var APP_VER = '9.4';` is shown in `btVer`; the server reads it with the regex `var APP_VER = '([^']+)'`
  for the web app's home page, so keep that exact form. `var RULES_V = 9;` travels in `curSetup().v`, the join request
  and `boardState()`; the server refuses a join whose version differs from the room's.

### 2.12 `window.BT` test hook (anchor `window.BT = {`)

Used by `tests/` (and `setServer`/`join` by the web app). Squad arguments accept a squad, a model or an id.

- **State**: `G`, `units` (live array), `TYPES`, `cam`, `table`, `NET`, `spec` (SPEC), `snd` (SND).
- **Field**: `seed(n)` sets SEED and rebuilds · `size(w)` · `setTheme(t)` · `setTerrain(r)` · `setBuildings(on, dens)` ·
  `props()` · `heightAt(x, z)` · `blockAt(x, z)` · `curSetup()` · `seedOf()` / `themeOf()` / `terrainOf()` / `buildingsOf()`.
- **Seats and armies**: `mkPlayers()` (set `G.mode`/`teams`/`perTeam` first) · `players()` · `setList(pi, arr)`
  (TYPES-indexed counts) · `autoList` · `armyCap()` · `teamPts(t)` · `setDep(pi, x, z)` · `autoDep` · `depWhyNot` ·
  `depCapacity` · `deploy()` · `depLog()` · `applyMode()`.
- **Match**: `start()` · `quit()` · `phase()` / `setPhase(ph)` · `nextPhase()` · `endTurn()` · `advance()` ·
  `done(pi, ph)` · `vp()` · `obj()` · `cp(pi, v)` · `fights()` · `live(team)` · `log()` · `board()` (state snapshot).
- **Orders**: `squads()` · `sq(id)` · `sqOf(model)` · `sqModels(s)` · `select(u)` / `pick(i)` / `act(a)` · `move(u, x, z)` ·
  `group(ids or 'all')` + `groupMove(x, z)` · `place(id, x, z, face)` (teleport a squad into formation) ·
  `shootAt(u, t, R, how)` (whole attack, optional fixed dice `{hit, wound, save}`) · `charge(u, t)` · `engaged(u)` ·
  `canAct(u)` · `canTarget` · `why(kind, u, t)` · `stratOk(k, pi)` · `inAura(u, kind)` · `fell` / `advd` / `charged(u, v)`.
- **Dice**: `dice([…])` queues the next d6 results · `diceLeft()` · `atkMath(u, t, how)` · `woundNeed(S, T)` ·
  `rollFor(u, t, how)` · `tray()` · `pend()` · `aim(u, t, kind)` · `myRoll()` · `roll(opts)` · `flush(force)` ·
  `setAuto(v)` · `trayHold(on)` · `trayTop()`.
- **Time and bots**: `clock(false)` stops the frame-driven simulation · `tick(dt, n)` steps it n times and draws ·
  `botStep()` one bot action (flushes dice) · `spectate(n)`.
- **Network**: `netPoll` · `applyAct(a)` · `adoptRoom(R)` · `capture(true)` records every act this device sends (also
  offline; returns them) · `server()` / `setServer(url)` · `join(code, name)`. Do not rename `setServer` or `join`.
- **Rendering**: `draw()` · `faces()` · `redraws()` · `renderScale(v)` · `adapt(ms)` · `gfx(level)` · `sprites(on)` ·
  `screen(x, z, up)` (table → screen px) · `tap(x, z)` · `pan` · `panBy` · `fit`.
- **Figures and effects**: `add(k, x, z)` · `goTo(i, x, z)` / `stop(i)` / `walking()` · `kitFaces(k, L)` · `kitInfo(k)` ·
  `kitOf(u)` · `flyK(u)` · `animate(i, j, melee, n)` · `brace(i, j)` · `acts()` · `kill8` · `hurt8` · `fx()` / `fx8(o)` ·
  `fxKind(k, melee)` / `fxKinds()` / `fxAt(kind)` · `blast(x, z, s)` · `vshield(i)` · `aimPoint` · `fallen()` ·
  `blessed()` · `abilityText(T)` · `wpnLine(W, melee)`.

## 3. `board.html` — the 3D D&D board

Has a real `<!doctype html>`. The web app (server `app.html`) fetches `/board`, inserts a `<script>` defining
`window.Android = { move, tapToken, floor, ready, log }` right after `<meta charset="utf-8">` (the page reads it in its
first lines), and sets it as an iframe `srcdoc` (same origin, so it can call `parent`). Coordinates: 1 unit ≈ 5 ft.

| Anchor | What lives there |
| --- | --- |
| `var B_EN = (function(){` | English flag from localStorage `cl_lang`; every board string is `B_EN ? "English" : "ไทย"` (toasts, storyteller hint, dice toast) |
| `// ==DICE-BEGIN==` | the shared dice block (same as the battle table) |
| `const bridge = window.Android` | the bridge, with a no-op fallback (`move`, `ready`, `tapToken`, `log`; `floor` is optional and type-checked before use) |
| `// ---------- canvas / camera ----------` | self-sizing canvas, camera, `proj`, `function screenToFloor(sx, sy)`, fog |
| `function emitHair(og, A)`, `function emitOutfit(og, A)` | character looks; `const BODIES = {`, `const FACE_SHAPES = {`, `function clothesOf(look)` |
| `// ---------- scenes ----------` | `function firePit(g, k)`, `function dais(g, keep)`, `const S = {` (preview, tavern, forest, cave, ruins, field, village, dungeon, mountain, camp, campfire, road), `function buildScene(name, time)` |
| `function drawPawn(g, p, t, now)` | pawns; name plates `function drawLabels(now)`, `function drawCampLabels(now)` |
| `window.showRoll = function(seq, who, die, value, mine)` | shared dice throw seeded by the room-log `seq` (d4–d20; d100 only as a toast) |
| `let me = null, board = null, control = "tap"` | page state; storyteller state `let dmPick = null, dmSel = null;` |
| `window.setBoard = function(json)` | the room's board: scene, time, tokens, combat order (you may move only on your combat turn) |
| `window.setPreview = function(json, opts)` | character-creator dais (opts `{focus: "full" or "head", spin}`) |
| `window.setMe = function(id)`, `window.setControl = function(mode)`, `window.focusMe = function()`, `window.setInset = function(px)` | which token is mine; 'tap' or 'joystick'; centre on me; bottom inset for the joystick |
| `window.setDmPick = function(on, what, label)` | 9.4 storyteller pick mode ('place' or 'move'): shows `#dmhint`; a floor tap calls `bridge.floor(x, z)` (rounded to 0.1) instead of moving, ignoring turn and range |
| `window.setDmSel = function(id)` | 9.4: amber ring under the storyteller's selected token |
| `window.setCampfire = function(json)` | campfire lobby `{players:[{id, name, look, ready}], you}`: pawns on a ring round the fire, updated in place |
| `function tap(cx, cy)` | token hit → `bridge.tapToken(best.t.id)` (own token only in pick mode); pick mode → `bridge.floor`; else tap-to-move within 6 units (30 ft) of the turn start → `bridge.move(x, z)` |
| `function frame(now)` | render loop; the script ends with `bridge.ready();` |

The web app calls `setBoard`, `setMe`, `setControl`, `showRoll`, `setDmPick`, `setDmSel`, `setCampfire`, `setPreview`
through its `frameCall`; renaming any of them breaks `/app`.

## 4. Android app, desktop app, CI and release

**Android** (`app/src/main/java/dev/mini/candlelight/`, native screens are Thai only):
- `Api.kt`: `const val SERVER` (workers.dev), `const val WEB_APP` (= SERVER/app), `object Api` (Google login, guest,
  pairing-code claim, `me`, logout).
- `MainActivity.kt`: `class Session(` (SharedPreferences token), `fun App(session: Session)` = the screen machine:
  `fun SplashScreen(` (checks the token) → web app; no token → `fun LoginScreen(` (Google via Credential Manager,
  guest, `private fun PairClaim(`); no network → `fun OfflineScreen(` → `fun TabletopScreen(onBack` →
  `fun AssetPage(asset` loads `file:///android_asset/battle-table.html` in a WebView with **no** JS bridge.
- `WebAppScreen.kt`: `fun WebAppScreen(` loads `WEB_APP#t=<token>`; `class CLHost(` is exposed as `window.CLHost`
  (`signedOut`, `deviceKind`) and must never be named `Android` (board.html owns that name); `private class AppChrome`
  (own alert/confirm dialogs, fullscreen view); `private class AppClient` (token hand-off check `TOOK_TOKEN`, outside
  links to the browser, offline and crash handling); the back button asks `window.clBack()`.
- `Illustrations.kt`: line-art drawings shared with the web app. `versionCode`/`versionName` in `app/build.gradle.kts`
  are separate from `APP_VER`.

**Desktop** (`desktop/`): `desktop/dist/index.html` → `function tryOnline()` (fetch `SERVER/app`, 6 s timeout, then
`location.replace`) or `function offline()` → `$('play').onclick` puts `battle-table.html` in the iframe; follows
`cl_lang`. `desktop/dist/battle-table.html` is **not** in git: CI copies it from `app/src/main/assets/` before
`tauri build` (copy it yourself for a local build; `.gitignore` keeps the copy out of git). `tauri.conf.json` version 1.0.0, NSIS
per-user installer.

**CI and release**: `build.yml` jobs `check` (PR: `gradle assembleDebug`), `windows-check` (PR: Tauri build),
`build` (main/manual: `assembleRelease` signed with `KEYSTORE_*` secrets, release `build-<run_number>`),
`windows-release` (after `build`: attaches the .exe and setup to that release). `tests.yml` runs `tests/run.sh quick`
on PRs. Online players get both pages from the **server**; the APK/.exe copies matter only offline. So: merge the
server PR first (it deploys itself), then this repo.

**Server touch points** (`../candlelight-server`; anchors in `worker.js` unless noted):

| Anchor | Why you care |
| --- | --- |
| `embed.py` (file) | re-embeds `board.html` → `const BOARD_HTML = ` and `battle-table.html` (found next to it) → `const TABLETOP_HTML = `; run `python3 embed.py` after changing either page |
| `const BT_RULES = 9;`, `function btVer(v)`, `function btVerErr(room, v)` | rules-version gate (must equal `RULES_V`); a mismatched join gets HTTP 409 and a Thai message |
| `function btSetup(raw)` | clamps every setup value (theme, terrain, mode, size, budget by version, clock, goal, rounds) |
| `const BT2 = {` | server copy of every TYPES entry keyed by `k` (stats identical, weapon names in English) for Claude's tools; `function bt2Abilities(T)`; `const BT_ARMY_EN = {`; `const BT_LIST_LEN = 512;` (longest army list kept) |
| `if (raw.a === "smove")` | inside the act allowlist of `async function btPost(`: add any new act code or field here |
| `var APP_VER = '([^']+)'` | regex that reads the page's version for the web app (`%%APP_VER%%` in `app.html`, first of 2) |
| `var BRIDGE = '<script>window.Android={'` (app.html) | the board bridge injected into the srcdoc |
| `async function openTt(joinCode)` (app.html) | fetches `/tabletop/battle-table`, makes the srcdoc iframe, calls `BT.setServer` and `BT.join` |

## 5. Common changes and where to make them

| Change | In this repo | Also | Versions |
| --- | --- | --- | --- |
| Add a unit | append to `var TYPES = [`; figure `SOLID.<k>` + `kit('<k>', …)` in its army block (unique helper prefix); `var ANIM = {` entry (else infantry); optional `var FLY_K = {`, `var VARIANTS = {`, `var MACH8 = {`, weapon `fx`; `var CORE = {` if bots and Claude should field it; English for `nm`, `d`, weapon names | server `BT2` entry (same stats), `bt2Abilities` for a new flag, re-embed; tests `rules_data`, `smoke_bot_games` | rules version (both sides), `APP_VER`, Thai note |
| Change stats or points | the TYPES entry | the same values in server `BT2` | rules version, `APP_VER` |
| Add or change a rule | `atkMath`, the `*WhyNot` checks, `apply*`, `startTurn`/`advance`; teach `botStep`/`expDmg`; `abilityText` + English; a new act needs `netSend` + `netAct` | server allowlist for new acts; `bt_look` rules text and `BT2` if Claude must know; tests `rules_*`, `net_sync*` | rules version, `APP_VER` |
| Add an army | `var FACS = [`, a `btFacs` button (data-f), `CORE[code]`, units, army rule hook (like `painOn`/`pactOn`), English names | server `BT_ARMY_EN`, `BT2`; check names against AGENTS.md rule 1 | rules version |
| New map theme or terrain | `THEMES`/`TERRAINS`, `btMaps`/`btTer` buttons, `SKY`, `DUST`, music mood, English | server `BT_THEMES`/`BT_TERRAINS` | rules version (generation) |
| Add UI text | Thai in markup/JS + a pair in `var EN = {` (exact string, or every fragment it is built from); board: `B_EN ? … : …` | web app strings: `EN` in server `app.html`; `tests/battle/english.js` | `APP_VER` |
| Graphics or speed | `GFX_OPT`, `drawScene`, `planLod`/`tuneLod`, `drawUnit`, sprites, every `gfx().potato` site, `frame()` | measure on `min` with a slowed CPU; `graphics_spectator` | `APP_VER` |
| Figure looks, animation, effects | MINI block / `SOLID` / `ANIM` / `FXS` (visual only) | `smoke_bot_games` (every LOD), `fx_anims` | `APP_VER` |
| Add a sound | a `var DEF = {` entry inside SND; trigger `SND.at('<kind>', point)` or map it from `FXS[kind].snd` | `fx_anims`, legacy `r6_snd` | `APP_VER` |
| board.html | the page + `B_EN` strings | re-embed; `app.html` if its API changes | Thai note (the board has no version label) |
| Bump the version | `var APP_VER = '9.4';` (keep the format); `var RULES_V = 9;` only when devices must agree on new rules or data, together with `BT_RULES` | Thai note `web/สิ่งที่เปลี่ยน-<date>-รุ่น<ver>-<topic>.md` | |
| Android shell | `MainActivity.kt`, `WebAppScreen.kt`, `Api.kt`; version in `app/build.gradle.kts` | CI compile | release `build-N` |

## 6. Invariants that must not break

1. **Determinism across devices.** Same setup + army lists + ordered acts ⇒ the same battle everywhere. What each device
   computes for itself uses seeded randomness only (`SEED` hashes, `seededRoll`; `seedOf` for dice tumbles); real dice
   are drawn on one device and travel in acts; rules use `gx`/`gz`; `advance()` after every applied act. Any change to
   terrain/props/objective/deploy generation, `CORE`/`autoList`, TYPES order or values, or rules maths is a rules-version change.
2. **Old clients in the same room.** `RULES_V` (page) and `BT_RULES` (server) move together; rooms remember their
   version and refuse other versions. Within one version every change must be compatible both ways (9.4's thin walk
   kept positions identical). Ship the server first.
3. **Thai stays the default.** English only when `cl_lang` is 'en'; every new Thai string gets an English entry;
   Thai mode must look exactly as before; never translate what players type.
4. **No Games Workshop / Warhammer or Gundam names or marks anywhere** — unit names, descriptions, English strings,
   insignia drawn on figures, comments, notes, commits, PRs. Use descriptive names (see AGENTS.md rule 1).
5. **Potato mode stays fast.** Add no per-frame work to `min`; keep redraw-on-demand (no idle animation), the ~30 fps
   cap, sprites for far pieces and the thin walk.
6. **Works offline from `file://`.** One self-contained file: no external scripts, fonts, images or fetches besides
   the optional room API; Canvas 2D only (WebGL/Three.js renders black on the owner's phone); the canvas re-measures
   itself; every `localStorage` access stays in try/catch.
7. **Contracts**: TYPES order; unique, DOM-free `MODULES` markers; identical `DICE` blocks; the `APP_VER` line format;
   `BT.setServer`/`BT.join` and the board's `window.set*` functions; the `window.Android` / `window.CLHost` names.
8. **Hidden units stay hidden**: never document or demonstrate how they are unlocked.

## 7. Known issues and doubts found while mapping (not fixed)

- **Duplicate `baseCap`.** The game IIFE declares `function baseCap(cx, cy, cz, r, n, col, rotY, alpha)` (draw a
  one-face base) and later `function baseCap(){` (models per player). The later declaration wins for the whole scope,
  so the potato branch of `drawUnit` (`else if (PT) baseCap(u.x, y, u.z, br, 6`) draws nothing: far pieces on `min` have no base.
  Fix by renaming the drawing helper (visual only, no rules bump).
- **`min` missing from effect tables.** `glowOn()` only switches glow off on 'lo'; `PT8_CAP`/`PT8_K` have no `min`
  key, so `ptCap8()` falls back to 420 particles (mid is 300, lo 110) and density 0.7; brass casings are thinned only
  on 'lo'. Effects on `min` are therefore heavier than on `lo` — probably unintended.
- `// ==KITS-EXTRA==` now sits before the round-8 blocks, so kits a harness splices there override only earlier kits.
- Server caps per act (60 dice, 40 points) vs. receivers padding short dice arrays with local rolls: keep any single
  roll ≤ 60 dice when designing units.
- `web/อ่านก่อน-วิธีทำ.md` names pages that are no longer in the repo.
- Some older internal identifiers and code comments still use genre words; user-visible names and the English
  dictionary are clean. Renaming a TYPES `k` touches the server `BT2`, tests and the army-list protocol.
