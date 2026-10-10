#!/usr/bin/env node
// record_army_objectives.js — sample the page's army and objective functions into JSON fixtures for the Godot port
// (core/battle/army.gd BtArmy, core/battle/objectives.gd BtObjectives; R1_PORT_SPEC §1.5 and §1.6). Read-only on the page.
//
//   node godot/tools/record_army_objectives.js            write the two fixtures
//   node godot/tools/record_army_objectives.js --check    re-run and fail unless the files are byte-identical
// Environment: PAGE=<battle-table.html>  CHROMIUM_PATH=<chrome>  NODE_PATH or tests/node_modules for playwright.
//
// The functions are cut out of the page text by anchor and evaluated inside the loaded page (Chromium's V8) next to a
// world this script builds (seats, lists, props, units), so the live game is never touched. Inputs are on the v10
// integer grids (positions MI, prop rot/h Q16, scale s4), as in record_blocking.js.
//   autoList   is driven by the v10 random stream: the page's seededRoll / Math.random are replaced by a PCG32 copy of
//              core/rng.gd (stream armies:<seat> or the test's device stream), each draw mapped to the value the page
//              compares, so the faction draw is bounded(15) and each "buy" draw is bounded(20) < 9 — the list is the
//              page's algorithm on v10's dice. It runs twice: the page as it is, and with the two v10 guards
//              (out[i] < SLOT_MAX in fits, out[b] < SLOT_MAX for the upgrade target) patched in.
//   freeSpot   (deploy, placeObjectives) and depWhyNot (autoDep) are traced: a decision whose answer changes within
//              EPS of the point marks the sample fragile (the v10 grid rounding may flip it); tests assert robust
//              samples exactly and only count fragile ones (R1_PORT_SPEC §7 #2).
// Outputs:
//   godot/tests/unit/fixtures/army/page_samples.json         fitList facOf fitSkin caps pts mkPlayers autoList depCapacity
//                                                            depSlots depWhyNot autoDep deploy
//   godot/tests/unit/fixtures/objectives/page_samples.json   placeObjectives objOC objCtl scoreObjectives
'use strict';
const fs = require('fs'), path = require('path');

const ROOT = path.resolve(__dirname, '..', '..');
const PAGE = path.resolve(process.env.PAGE || path.join(ROOT, 'app/src/main/assets/battle-table.html'));
const FIX = path.join(ROOT, 'godot/tests/unit/fixtures');
const OUT_ARMY = path.join(FIX, 'army', 'page_samples.json');
const OUT_OBJ = path.join(FIX, 'objectives', 'page_samples.json');
const CHECK = process.argv.includes('--check');

function loadPlaywright(){
  try { return require('playwright'); }
  catch (e) { return require(path.join(ROOT, 'tests/node_modules/playwright')); }
}

const src = fs.readFileSync(PAGE, 'utf8');
const APP_VER = (src.match(/var APP_VER = '([^']+)'/) || [])[1] || null;
const RULES_V = +((src.match(/var RULES_V = (\d+)/) || [])[1] || 0);
function lineOf(i){ return src.slice(0, i).split('\n').length; }

// ---------- cutting page code ----------
// a function: from the anchor to the brace that closes its body; a var statement: to the ';' at bracket depth 0.
// Quoted strings and comments are skipped (none of the cut pieces holds a regex literal or a template string).
const DUPLICATES_OK = new Set(['function clamp(v,a,b){']);   // two identical copies on the page
function cut(anchor){
  const a = src.indexOf(anchor);
  if (a < 0) throw new Error('anchor not found: ' + anchor);
  if (src.indexOf(anchor, a + 1) >= 0 && !DUPLICATES_OK.has(anchor)) throw new Error('anchor not unique: ' + anchor);
  const isVar = anchor.startsWith('var ');
  let i = isVar ? a : src.indexOf('{', a), depth = 0;
  for (; i < src.length; i++){
    const c = src[i], n = src[i + 1];
    if (c === '/' && n === '/'){ i = src.indexOf('\n', i); continue; }
    if (c === '/' && n === '*'){ i = src.indexOf('*/', i) + 1; continue; }
    if (c === '"' || c === "'"){ const q = c; i++; while (src[i] !== q){ if (src[i] === '\\') i++; i++; } continue; }
    if (c === '{' || c === '(' || c === '[') depth++;
    else if (c === '}' || c === ')' || c === ']'){ depth--; if (!isVar && depth === 0) return { anchor, line: lineOf(a), text: src.slice(a, i + 1) }; }
    else if (isVar && c === ';' && depth === 0) return { anchor, line: lineOf(a), text: src.slice(a, i + 1) };
  }
  throw new Error('unterminated piece ' + anchor);
}
// replace `from` by `to` in a piece's text, exactly `times` times (fails loudly when the page changed)
function patch(text, from, to, times){
  const n = text.split(from).length - 1;
  if (n !== (times || 1)) throw new Error('patch expected ' + (times || 1) + ' x "' + from + '", found ' + n);
  return text.split(from).join(to);
}
const ANCHORS = [
  'function clamp(v,a,b){', 'function hash2(', 'function hash3(', 'function bldSize(', 'var BLOCK_R = {', 'function propBlocks(',
  'function blockAt(', 'function radOfType(', 'function TY(', 'function gx(u)', 'function gz(u)', 'function crowded(',
  'function freeSpot(', 'function roomToLand(', 'var FACS = [', 'function emptyList(', 'function fitList(', 'function facOf(',
  'var SKINS = {', 'function fitSkin(', 'function mkPlayers(', 'function teamPlayers(', 'function shareOf(', 'function depCapacity(',
  'function ptsOf(', 'function teamPts(', 'function hasUnits(', 'var CORE = {', 'var SLOT_MAX = ', 'function baseCap(){',
  'var SPEC_TOTAL = ', 'function armyCap(', 'function slotMax(', 'function autoList(', 'function formation(', 'function deploy(',
  'function resetSq(', 'function depWhyNot(', 'function depSlots(', 'function autoDep(', 'var DEP_FOE = ', 'function sqOf(',
  'var OBJ = [', 'function placeObjectives(', 'function objOC(', 'function objCtl(', 'function refreshObj(',
  'function scoreObjectives(',
];
const PIECES = ANCHORS.map(cut);
const P = {}; PIECES.forEach(p => { P[p.anchor] = p.text; });

// traced and patched copies
const OK_HEAD = 'function ok(nx, nz, crowd){';
const FS_TRACED = patch(patch(P['function freeSpot('], 'function freeSpot(', 'function freeSpotTraced('), OK_HEAD,
  OK_HEAD + ' var __b = ok0(nx, nz, crowd); __T.n++; if (!__rob3(ok0, nx, nz, crowd, __b)) __T.bad++; return __b; }\n  function ok0(nx, nz, crowd){');
let AL = patch(P['function autoList('], 'Math.random', '__RND');
AL = patch(AL, 'out[i]++;', 'out[i]++; __pk(out[i]);');
AL = patch(AL, 'out[cheap]++;', 'out[cheap]++; __pk(out[cheap]);');
AL = patch(AL, 'out[best]++;', 'out[best]++; __pk(out[best]);');
const AL_PAGE = patch(AL, 'function autoList(', 'function autoListPage(');
let AL_V10 = patch(AL, 'function autoList(', 'function autoListV10(');
AL_V10 = patch(AL_V10, 'models() + TYPES[i].n <= MAX_MODELS; }', 'models() + TYPES[i].n <= MAX_MODELS && out[i] < SLOT_MAX; }');
AL_V10 = patch(AL_V10, '<= MAX_MODELS && (best < 0 ||', '<= MAX_MODELS && out[b] < SLOT_MAX && (best < 0 ||');
let DEP = patch(P['function deploy('], 'function deploy(', 'function deployTraced(');
DEP = patch(DEP, 'freeSpot(slots[j][0], slots[j][1], null, null, null, radOfType(T))', '__fs(slots[j][0], slots[j][1], null, null, null, radOfType(T))');
DEP = patch(DEP, 'formation(T.n, cx, cz, face, radOfType(T))', '__form(T.n, cx, cz, face, radOfType(T))');
DEP = patch(DEP, 'P.dep = autoDep(pi);', 'P.dep = __adep(pi);');
const ADEP = patch(patch(P['function autoDep('], 'function autoDep(', 'function autoDepRaw('), 'depWhyNot(pi, ', '__dwn(pi, ', 3);
const PLACE = patch(patch(P['function placeObjectives('], 'function placeObjectives(', 'function placeTraced('),
  'freeSpot(p[0], p[1], null, null, null, 1.2)', '__fs(p[0], p[1], null, null, null, 1.2)');

// the lab: the page's code in its own closure over data the sampler sets; TYPES comes from the live page
const LAB = '(function(){ "use strict";\n' +
  'var TAU = Math.PI*2, SEED = 1, theme = "ruin", PROPS = [], units = [], SQ = {}, SQ_ORDER = [], DEPLOG = null, LOG = [];\n' +
  'var table = { w: 48, d: 34 }, TYPES = window.BT.TYPES;\n' +
  'var G = { mode: "pvp", teams: 2, perTeam: 1, budget: 500, players: [], vp: [], cur: 0, freeFire: false, goal: "obj" };\n' +
  'function say(t){ LOG.push(String(t)); } function TEAM(i){ return { nm: "\\u0002T" + i + "\\u0002" }; }\n' +
  'function kitScale(){ return 1; } function skinKit(){ return null; }\n' +
  // PCG32 as core/rng.gd (tools/gen_vectors.mjs holds the same reference)
  'var M64 = (1n << 64n) - 1n, M32 = (1n << 32n) - 1n;\n' +
  'function fnvStr(s){ var h = 14695981039346656037n, b = new TextEncoder().encode(s), i; for (i = 0; i < b.length; i++){ h ^= BigInt(b[i]); h = (h * 1099511628211n) & M64; } return h; }\n' +
  'function Pcg(seed, stream){ this.draws = 0; this.inc = ((fnvStr(stream) << 1n) | 1n) & M64; this.state = 0n; this.step(); this.state = (this.state + BigInt.asUintN(64, BigInt(seed))) & M64; this.step(); }\n' +
  'Pcg.prototype.step = function(){ this.state = (this.state * 6364136223846793005n + this.inc) & M64; };\n' +
  'Pcg.prototype.next = function(){ var old = this.state; this.step(); this.draws++; var xs = (((old >> 18n) ^ old) >> 27n) & M32, rot = old >> 59n; return Number(((xs >> rot) | (xs << ((32n - rot) & 31n))) & M32); };\n' +
  'Pcg.prototype.bounded = function(n){ var t = Number((4294967296n - BigInt(n)) % BigInt(n)); for (;;){ var r = this.next(); if (r >= t) return r % n; } };\n' +
  // the page's draws on the v10 stream: the first draw of a seeded list picks the army, every other one is a 9-in-20 buy
  'var __RNG = null, __FIRST = false, __PEAK = 0;\n' +
  'function __RND(){ var n = __FIRST ? FACS.length : 20; __FIRST = false; return (__RNG.bounded(n) + 0.5) / n; }\n' +
  'function seededRoll(){ return __RND(); } function __pk(v){ if (v > __PEAK) __PEAK = v; }\n' +
  // tracing
  'var __T = { n: 0, bad: 0 }, __T2 = { n: 0, bad: 0 }, EPS = 0.012, __FS = [], __FORM = [], __ADEP = [];\n' +
  'function __rob3(f, x, z, c, b){ for (var k = 0; k < 16; k++){ var a = k*Math.PI/8; if (f(x + Math.cos(a)*EPS, z + Math.sin(a)*EPS, c) !== b) return false; } return true; }\n' +
  PIECES.map(p => '// page line ' + p.line + '\n' + p.text).join('\n') + '\n' +
  FS_TRACED + '\n' + AL_PAGE + '\n' + AL_V10 + '\n' + DEP + '\n' + ADEP + '\n' + PLACE + '\n' +
  'function __fs(x, z, skip, from, maxD, rad){ __T.n = 0; __T.bad = 0; var r = freeSpotTraced(x, z, skip, from, maxD, rad);\n' +
  '  if (String(r) !== String(freeSpot(x, z, skip, from, maxD, rad))) throw new Error("traced freeSpot differs");\n' +
  '  __FS.push({ q: [x, z], r: r ? [r[0], r[1]] : null, n: __T.n, bad: __T.bad }); return r; }\n' +
  'function __form(n, cx, cz, face, r){ var sl = formation(n, cx, cz, face, r); __FORM.push({ c: [cx, cz], face: face, slots: sl }); return sl; }\n' +
  // autoDep decisions: v10 tests the page candidate rounded to the 10 MI grid (slots, axis rings and the fallback grid
  // are exactly that); a team above four turns its ring with Q16 trig, so the eight grid neighbours count too
  'function __dwn(pi, x, z){ var w = depWhyNot(pi, x, z), rx = 10*Math.round(x*100)/1000, rz = 10*Math.round(z*100)/1000, k, j, bad = false;\n' +
  '  var P = G.players[pi], m = P ? teamPlayers(P.team).length : 0; __T2.n++;\n' +
  '  if (depWhyNot(pi, rx, rz) !== w) bad = true;\n' +
  '  for (k = -1; k <= 1 && !bad && m > 4; k++) for (j = -1; j <= 1; j++) if (depWhyNot(pi, rx + k*0.01, rz + j*0.01) !== w){ bad = true; break; }\n' +
  '  if (bad) __T2.bad++; return w; }\n' +
  'function __adepT(pi){ __T2.n = 0; __T2.bad = 0; var r = autoDepRaw(pi); return { r: r, n: __T2.n, bad: __T2.bad }; }\n' +
  'function __adep(pi){ var t = __adepT(pi); __ADEP.push(t); return t.r; }\n' +
  'return {\n' +
  '  set: function(o){ SEED = o.seed; table.w = o.w; table.d = o.d; PROPS = o.props || []; units = o.units || []; SQ = o.sq || {};\n' +
  '    SQ_ORDER = Object.keys(SQ); OBJ = o.obj || []; G.mode = o.mode || "pvp"; G.teams = o.teams || 2; G.perTeam = o.perTeam || 1;\n' +
  '    G.budget = o.budget == null ? 500 : o.budget; G.players = o.players || []; G.vp = o.vp || []; LOG.length = 0; },\n' +
  '  G: function(){ return G; }, units: function(){ return units; }, SQ: function(){ return SQ; }, order: function(){ return SQ_ORDER; },\n' +
  '  OBJ: function(){ return OBJ; },\n' +
  '  rng: function(seed, name, first){ __RNG = new Pcg(seed, name); __FIRST = !!first; __PEAK = 0; }, draws: function(){ return __RNG.draws; },\n' +
  '  peak: function(){ return __PEAK; }, pcg: function(seed, name){ return new Pcg(seed, name); }, eps: function(e){ EPS = e; },\n' +
  '  logs: function(){ var o = { fs: __FS, form: __FORM, adep: __ADEP }; __FS = []; __FORM = []; __ADEP = []; return o; },\n' +
  '  emptyList: emptyList, fitList: fitList, facOf: facOf, fitSkin: fitSkin, mkPlayers: mkPlayers, shareOf: shareOf, baseCap: baseCap,\n' +
  '  armyCap: armyCap, slotMax: slotMax, ptsOf: ptsOf, teamPts: teamPts, hasUnits: hasUnits, depCapacity: depCapacity,\n' +
  '  depSlots: depSlots, depWhyNot: depWhyNot, autoDep: __adepT, autoListPage: autoListPage, autoListV10: autoListV10,\n' +
  '  deploy: deployTraced, place: placeTraced, objOC: objOC, objCtl: objCtl, refreshObj: refreshObj, scoreObjectives: scoreObjectives,\n' +
  '  bldSize: bldSize, blockAt: blockAt, roomToLand: roomToLand, radOfType: radOfType, TY: TY, FACS: FACS, CORE: CORE, SKINS: SKINS,\n' +
  '  SLOT_MAX: SLOT_MAX, SPEC_TOTAL: SPEC_TOTAL, DEP_FOE: DEP_FOE, DEP_MATE: DEP_MATE, OBJ_R: OBJ_R, VP_PER: VP_PER, VP_CAP: VP_CAP };\n' +
  '})()';

// ---------- the sampler (runs inside the page) ----------
function sampler(plan){
  var L = window.LAB, BT = window.BT, TYPES = BT.TYPES, Q = 65536;
  var mi3 = function(v){ return Math.round(v * 1e6) / 1000; };          // inches -> MI with 1/1000 MI kept
  var sparse = function(list){ var o = [], i; for (i = 0; i < list.length; i++) if (list[i]) o.push([i, list[i]]); return o; };
  var full = function(sp){ var o = L.emptyList(); sp.forEach(function(p){ o[p[0]] = p[1]; }); return o; };
  function mkProp(kind, x, z, rq, s4, hq){
    return { o: { kind: kind, x: x / 1000, z: z / 1000, rot: rq / Q, s: s4 / 10000, h: hq / Q, rad: 2.4 }, row: [kind, x, z, rq, s4, hq, 0, 0] };
  }
  // a field from the page's own genProps, snapped to the integer grids (buildings carry the page's bldSize in MI)
  var FIELDS = {};
  function field(name){
    if (FIELDS[name]) return FIELDS[name];
    var F = plan.fields[name], d, props;
    if (F.props){ props = F.props.map(function(r){ return mkProp(r[0], r[1], r[2], r[3], r[4], r[5]); }); d = F.d; }
    else {
      BT.setTheme(F.theme); BT.setTerrain(F.terrain); BT.setBuildings(F.density > 0, F.density || 1); BT.seed(F.seed); BT.size(F.w);
      d = BT.table.d;
      props = BT.props().map(function(o){ return mkProp(o.kind, Math.round(o.x*1000), Math.round(o.z*1000), Math.round(o.rot*Q), Math.round(o.s*10000), Math.round(o.h*Q)); });
    }
    L.set({ seed: F.seed, w: F.w, d: d });
    props.forEach(function(p){ if (p.o.kind !== 'building') return; L.set({ seed: F.seed, w: F.w, d: d, props: [p.o] });
      var b = L.bldSize(p.o); p.row[6] = Math.round(b[0]*1000); p.row[7] = Math.round(b[1]*1000); });
    FIELDS[name] = { seed: F.seed, w: F.w, d: d, props: props, rows: props.map(function(p){ return p.row; }) };
    return FIELDS[name];
  }
  function seatsOf(list){ return list.map(function(s, k){ return { id: k, team: s.team, nm: '\u0001S' + k + '\u0001', bot: !!s.bot, ai: !!s.ai,
    list: s.list ? full(s.list) : L.emptyList(), fac: s.fac || 'mod', dep: s.dep ? [s.dep[0] / 1000, s.dep[1] / 1000] : null, done: false, cp: 0 }; }); }
  function setWorld(f, setup, seats, us){
    L.set({ seed: f.seed, w: f.w, d: f.d, props: f.props.map(function(p){ return p.o; }), units: us || [], mode: setup.mode,
      teams: setup.teams, perTeam: setup.perTeam, budget: setup.budget, players: seatsOf(seats) });
  }
  var out = { army: {}, obj: {} }, A = out.army, O = out.obj;

  // ---- fitList / facOf (raw arrays packed: length and the entries that are not the number 0) ----
  var pack = function(raw){ var v = [], i; for (i = 0; i < raw.length; i++) if (raw[i] !== 0) v.push([i, raw[i]]); return { n: raw.length, v: v }; };
  A.fit_list = plan.fit_list.map(function(c){ return { raw: pack(c.raw), out: sparse(L.fitList(c.raw)) }; });
  A.fac_of = plan.fac_of.map(function(c){ return { raw: pack(c.raw), dflt: c.dflt, out: L.facOf(c.raw, c.dflt || undefined) }; });
  A.fit_skin = plan.fit_skin.map(function(c){ return { raw: c, out: L.fitSkin(c) }; });
  A.skins = Object.keys(L.SKINS).map(function(k){ return [k, L.SKINS[k].length]; });

  // ---- caps ----
  A.share = plan.share.map(function(c){ L.set({ seed: 1, w: 48, d: 34, budget: c[0], perTeam: c[1] }); return [c[0], c[1], L.shareOf()]; });
  A.caps = plan.caps.map(function(c){ var ps = []; for (var i = 0; i < c[1]; i++) ps.push({ id: i, team: 0, list: [] });
    L.set({ seed: 1, w: 48, d: 34, mode: c[0], players: ps }); return [c[0], c[1], L.baseCap(), L.armyCap()]; });
  A.slot_max = plan.slot_max.map(function(c){ L.set({ seed: 1, w: 48, d: 34, mode: c[0] }); return [c[0], c[1], L.slotMax(TYPES[c[1]])]; });
  A.consts = { SLOT_MAX: L.SLOT_MAX, SPEC_TOTAL: L.SPEC_TOTAL, DEP_FOE: L.DEP_FOE, DEP_MATE: L.DEP_MATE, OBJ_R: L.OBJ_R, VP_PER: L.VP_PER, VP_CAP: L.VP_CAP };

  // ---- ptsOf / teamPts / hasUnits ----
  A.pts = plan.pts.map(function(c){
    L.set({ seed: 1, w: 48, d: 34, teams: c.teams, players: seatsOf(c.seats) });
    var t, teams = []; for (t = 0; t < c.teams; t++) teams.push(L.teamPts(t));
    return { teams: c.teams, seats: c.seats, pts: c.seats.map(function(s, k){ return L.ptsOf(k); }), team_pts: teams,
      has: c.seats.map(function(s, k){ return L.hasUnits(k) ? 1 : 0; }), missing: [L.ptsOf(c.seats.length), L.hasUnits(c.seats.length) ? 1 : 0] };
  });

  // ---- mkPlayers ----
  A.mk_players = plan.mk_players.map(function(c){
    L.set({ seed: 1, w: 48, d: 34, mode: c[0], teams: c[1], perTeam: c[2] }); L.mkPlayers();
    return [c[0], c[1], c[2], L.G().players.map(function(p){ return [p.id, p.team, p.bot ? 1 : 0]; })];
  });

  // ---- autoList: the page's code on v10 draws, as it is and with the v10 SLOT_MAX guards ----
  A.pcg = plan.pcg.map(function(c){ var g = L.pcg(c[0], c[1]), o = []; for (var i = 0; i < 6; i++) o.push(g.bounded(c[2])); return [c[0], c[1], c[2], o]; });
  A.auto_list = plan.auto_list.map(function(c){
    var res = { c: { seed: c.seed, pi: c.pi, n: c.seats.length, mode: c.mode, teams: c.teams, perTeam: c.perTeam, budget: c.budget } };
    if (c.dev){ res.c.dev = c.dev; res.c.fac_in = c.fac_in; }
    ['page', 'v10'].forEach(function(variant){
      L.set({ seed: c.seed, w: 48, d: 34, mode: c.mode, teams: c.teams, perTeam: c.perTeam, budget: c.budget, players: seatsOf(c.seats) });
      var P = L.G().players[c.pi];
      if (c.dev){ P.fac = c.fac_page; L.rng(c.dev[1], c.dev[0], false); (variant === 'page' ? L.autoListPage : L.autoListV10)(c.pi, true); }
      else { L.rng(c.seed, 'armies:' + c.pi, true); (variant === 'page' ? L.autoListPage : L.autoListV10)(c.pi, false); }
      res[variant] = { list: sparse(P.list), fac: P.fac, peak: L.peak(), draws: L.draws() };
    });
    // the page as it is: kept in full only where the v10 guards changed the list
    if (JSON.stringify(res.page.list) === JSON.stringify(res.v10.list) && res.page.fac === res.v10.fac){ delete res.page.list; delete res.page.fac; }
    return res;
  });

  // ---- depCapacity / depSlots ----
  A.dep_capacity = plan.dep_capacity.map(function(c){ return [c[0], c[1], L.depCapacity(c[0], c[1])]; });
  A.dep_slots = plan.dep_slots.map(function(c){ L.set({ seed: 1, w: c[0], d: c[1] }); return [c[0], c[1], L.depSlots().map(function(p){ return [mi3(p[0]), mi3(p[1])]; })]; });

  // the two constant refusals, taken from the page itself (a point far off the table; a point under one huge building)
  L.set({ seed: 1, w: 48, d: 34, players: seatsOf([{ team: 0 }]) });
  var EDGE_MSG = L.depWhyNot(0, 1000, 0), big = mkProp('building', 0, 0, 0, 100000, 0);
  L.set({ seed: 1, w: 48, d: 34, props: [big.o], players: seatsOf([{ team: 0 }]) });
  var BLOCK_MSG = L.depWhyNot(0, 0, 0);
  if (!EDGE_MSG || !BLOCK_MSG || EDGE_MSG === BLOCK_MSG) throw new Error('could not read the two refusal messages');
  function keyOf(msg, seats){
    if (msg === '') return ['', []];
    if (msg === EDGE_MSG) return ['edge', []];
    if (msg === BLOCK_MSG) return ['blocked', []];
    var m = /\u0001S(\d+)\u0001/.exec(msg); if (m) return ['mate', [+m[1]]];
    m = /\u0002T(\d+)\u0002/.exec(msg); if (m) return ['foe', [+m[1]]];
    throw new Error('unknown refusal: ' + msg);
  }

  // ---- depWhyNot: both sides test the same grid point; only the room probes differ (v10 rounds them to whole MI),
  // so an answer that holds 1 MI around the point is robust ----
  A.dep_why_not = plan.dep_why_not.map(function(c){
    var f = field(c.field); setWorld(f, c.setup, c.seats, []);
    var rows = c.q.map(function(q){
      var w = L.depWhyNot(q[0], q[1] / 1000, q[2] / 1000), robust = 1, k, a;
      for (k = 0; k < 16; k++){ a = k*Math.PI/8; if (L.depWhyNot(q[0], q[1] / 1000 + Math.cos(a)*0.001, q[2] / 1000 + Math.sin(a)*0.001) !== w){ robust = 0; break; } }
      var kk = keyOf(w); return [q[0], q[1], q[2], kk[0], kk[1].length ? kk[1][0] : -1, robust];
    });
    return { field: c.field, setup: c.setup, seats: c.seats, q: rows };
  });

  // ---- autoDep: seats in order, each result rounded to the v10 grid and kept before the next seat asks ----
  A.auto_dep = plan.auto_dep.map(function(c){
    var f = field(c.field); setWorld(f, c.setup, c.seats, []);
    var G = L.G(), res = [];
    c.ask.forEach(function(pi){
      var t = L.autoDep(pi), x = t.r[0] * 1000, z = t.r[1] * 1000;
      res.push([pi, mi3(t.r[0]), mi3(t.r[1]), t.n, t.bad ? 0 : 1]);
      G.players[pi].dep = [10 * Math.round(x / 10) / 1000, 10 * Math.round(z / 10) / 1000];
    });
    return { field: c.field, setup: c.setup, seats: c.seats, ask: c.ask, out: res };
  });

  // ---- deploy (traced at 40 MI: v10 slots sit up to a few tens of MI from the page's raw ones) ----
  L.eps(0.04);
  A.deploy = plan.deploy.map(function(c){
    var f = field(c.field); setWorld(f, c.setup, c.seats, []); L.logs();
    L.deploy();
    var lg = L.logs(), G = L.G(), sq = L.SQ(), us = L.units();
    var fi = 0;
    var squads = L.order().map(function(id){ var s = sq[id], F = lg.form[fi++];
      return [s.id, s.k, s.side, s.pl, s.n0, s.vs, mi3(F.c[0]), mi3(F.c[1]), F.face, F.slots.map(function(p){ return [mi3(p[0]), mi3(p[1])]; })]; });
    if (fi !== lg.form.length || lg.fs.length !== us.length) throw new Error('deploy trace out of step');
    var models = us.map(function(u, i){ var t = lg.fs[i];
      if (t.r[0] !== u.x || t.r[1] !== u.z) throw new Error('deploy trace does not match the unit');
      return [u.id, u.sq, u.hp, mi3(u.x), mi3(u.z), t.n, t.bad ? 0 : 1]; });
    return { field: c.field, setup: c.setup, seats: c.seats,
      deps: G.players.map(function(p){ return p.dep ? [mi3(p.dep[0]), mi3(p.dep[1])] : null; }),
      auto: lg.adep.map(function(t){ return t.bad ? 0 : 1; }), squads: squads, models: models };
  });

  // ---- placeObjectives (after models stand on the table) ----
  L.eps(0.012);
  O.place = plan.place.map(function(c){
    var f = field(c.field), us = c.units.map(function(r, i){ return { id: 'u' + i, sq: 's', t: r[0], k: r[0], x: r[1] / 1000, z: r[2] / 1000 }; });
    setWorld(f, { mode: 'pvp', teams: 2, perTeam: 1, budget: 500 }, [], us); L.logs();
    L.place();
    var lg = L.logs();
    return { field: c.field, units: c.units, obj: L.OBJ().map(function(o, i){ var t = lg.fs[i];
      return [o.n, mi3(o.x), mi3(o.z), t.n, t.bad ? 0 : 1]; }) };
  });

  // ---- objOC / objCtl / scoreObjectives ----
  O.worlds = plan.obj_worlds.map(function(W){
    var sq = {}, us = [];
    W.squads.forEach(function(s){ sq[s[0]] = { id: s[0], k: s[1], side: s[2], pl: s[2], n0: 1, shaken: !!s[3] }; });
    W.units.forEach(function(u){ us.push({ id: u[0], sq: u[1], t: sq[u[1]].k, k: sq[u[1]].k, side: sq[u[1]].side, x: u[2] / 1000, z: u[3] / 1000 }); });
    var obj = W.obj.map(function(o){ return { n: o[0], x: o[1] / 1000, z: o[2] / 1000, owner: -1 }; });
    L.set({ seed: 1, w: 72, d: 52, units: us, sq: sq, obj: obj, teams: W.teams });
    // near: some model of that team sits within 1e-9 inch of the reach (its page answer may fall either side)
    var oc = obj.map(function(o){ var row = [], t;
      for (t = 0; t < W.teams; t++){
        var near = us.some(function(m){ if (m.side !== t || sq[m.sq].shaken) return false;
          return Math.abs(Math.hypot(m.x - o.x, m.z - o.z) - (L.OBJ_R + L.radOfType(L.TY(m.t)) + 0.001)) < 1e-9; });
        row.push([L.objOC(o, t), near ? 1 : 0]); }
      return row; });
    var ctl = obj.map(function(o){ return L.objCtl(o); });
    var vp = [], held = [], t;
    L.G().vp = [];
    for (t = 0; t < W.teams; t++){ L.scoreObjectives(t); vp.push(L.G().vp.slice());
      held.push(L.OBJ().filter(function(o){ return o.owner === t; }).map(function(o){ return o.n; })); }
    return { teams: W.teams, squads: W.squads, units: W.units, obj: W.obj, oc: oc, ctl: ctl, vp: vp, held: held };
  });
  // every field used above, as the port rebuilds it: prop rows [kind, x, z, rot_q16, s4, h_q16, bw, bd]
  out.fields = {};
  Object.keys(FIELDS).sort().forEach(function(k){ var f = FIELDS[k]; out.fields[k] = { seed: f.seed, w: f.w, d: f.d, props: f.rows }; });
  return out;
}

// ---------- the plan (seeded, Node side) ----------
function mulberry32(a){ return function(){ a |= 0; a = a + 0x6D2B79F5 | 0; var t = Math.imul(a ^ a >>> 15, 1 | a);
  t = t + Math.imul(t ^ t >>> 7, 61 | t) ^ t; return ((t ^ t >>> 14) >>> 0) / 4294967296; }; }
function makePlan(types, facs, core){
  const rnd = mulberry32(20261008), ri = (lo, hi) => lo + Math.floor(rnd() * (hi - lo + 1)), pick = a => a[ri(0, a.length - 1)];
  const N = types.length, hidden = [], open = [];
  types.forEach((T, i) => { if (T.sec || T.lk) hidden.push(i); else open.push(i); });
  const g10 = v => 10 * Math.round(v / 10);
  const depthOf = w => Math.round(w * 0.72 / 2) * 2;
  const plan = {};

  // fitList / facOf: random counts, hidden types over one, the |0 corner cases, short and long arrays
  const fl = [];
  fl.push({ raw: [] }, { raw: new Array(N).fill(0) }, { raw: [3] }, { raw: [1, 2, 3, 4, 5, 6, 7, 8, 9, 10] });
  for (let c = 0; c < 26; c++){
    const len = c % 5 === 0 ? N + ri(1, 8) : c % 7 === 0 ? ri(1, N - 1) : N, raw = new Array(len).fill(0);
    const k = ri(1, 14);
    for (let j = 0; j < k; j++) raw[ri(0, len - 1)] = pick([1, 2, 5, 9, 37, 98, 99, 100, 101, 250, -1, -7, -2147483648]);
    if (c % 3 === 0) hidden.forEach(h => { if (h < len) raw[h] = pick([1, 2, 5, 99, -3]); });
    fl.push({ raw });
  }
  const wrap = new Array(N).fill(0);
  wrap[open[0]] = 4294967297; wrap[open[1]] = -4294967295; wrap[open[2]] = 2147483648; wrap[open[3]] = 4294967395; wrap[open[4]] = 2147483647;
  wrap[open[5]] = true; wrap[open[6]] = false; wrap[hidden[0]] = 4294967298; fl.push({ raw: wrap });
  plan.fit_list = fl;
  plan.fac_of = [];
  fl.forEach((c, i) => plan.fac_of.push({ raw: c.raw, dflt: ['', 'gr', 'zz', 'mod'][i % 4] }));
  // a list of one hidden type each (sec or lk), and a hidden type before an open one
  hidden.forEach(h => { const raw = new Array(N).fill(0); raw[h] = 1; plan.fac_of.push({ raw, dflt: '' });
    const r2 = raw.slice(); r2[N - 1 > h ? N - 1 : 0] = 2; plan.fac_of.push({ raw: r2, dflt: 'el' }); });
  facs.forEach((f, i) => { const raw = new Array(N).fill(0); raw[types.findIndex(T => T.fac === f.k)] = 1 + (i % 3); plan.fac_of.push({ raw, dflt: '' }); });
  plan.fit_skin = [{}, { loki: 1 }, { loki: 2 }, { loki: 0 }, { loki: -1 }, { loki: 1, nobody: 1 }, { nobody: 3 }, { loki: true },
    { loki: false }, { loki: 4294967297 }, { loki: -4294967295 }];

  // caps
  plan.share = [];
  [-50, 0, 39, 40, 41, 79, 80, 81, 199, 200, 500, 999, 1000, 10000, 40000].forEach(b => [1, 2, 3, 4, 7].forEach(p => plan.share.push([b, p])));
  plan.caps = [];
  ['pvp', 'spectator', 'ffa', 'team'].forEach(m => { for (let n = 0; n <= 13; n++) plan.caps.push([m, n]); });
  plan.slot_max = [];
  ['pvp', 'spectator', 'team'].forEach(m => hidden.concat(open.slice(0, 3), [open[open.length - 1]]).forEach(i => plan.slot_max.push([m, i])));

  // pts
  plan.pts = [];
  for (let c = 0; c < 24; c++){
    const ns = ri(1, 8), teams = ri(1, Math.min(4, ns)), seats = [];
    for (let k = 0; k < ns; k++){
      const list = [], m = c % 6 === 0 && k === 0 ? 0 : ri(0, 6);
      for (let j = 0; j < m; j++) list.push([pick(open), ri(1, 12)]);
      if (rnd() < 0.3) list.push([pick(hidden), 1]);
      const seen = {}; seats.push({ team: k % teams, list: list.filter(p => !seen[p[0]] && (seen[p[0]] = 1)).sort((a, b) => a[0] - b[0]) });
    }
    plan.pts.push({ teams, seats });
  }

  // mkPlayers
  plan.mk_players = [];
  ['pvp', 'pve', 'ffa', 'team', 'spectator', 'custom'].forEach(m => [[2, 1], [2, 2], [3, 1], [4, 1], [2, 4], [8, 1], [1, 1], [3, 3]].forEach(tp =>
    plan.mk_players.push([m, tp[0], tp[1]])));

  // PCG sanity rows
  plan.pcg = [[1, 'armies:0', 15], [10, 'armies:1', 15], [99999, 'armies:7', 20], [3, 'dev', 20]];

  // autoList: seeded (army drawn) and device-stream lists over budgets, team sizes, seat counts and armies
  const BUD = [35, 40, 41, 120, 200, 350, 500, 750, 1000, 1500, 2000, 3500, 5000, 7500, 10000, 15000, 20000, 27000, 28000, 40000];
  const modes = ['pvp', 'pve', 'ffa', 'team', 'spectator'];
  const al = [];
  function seatList(n, teams){ const s = []; for (let k = 0; k < n; k++) s.push({ team: k % teams, bot: true, fac: 'mod' }); return s; }
  for (let c = 0; c < 170; c++){
    const teams = ri(1, 8), perTeam = ri(1, 4), n = Math.min(12, teams * perTeam), seats = seatList(n, teams), pi = ri(0, n - 1);
    if (c % 5 === 1) seats[pi].bot = false, seats[pi].ai = true;
    al.push({ seed: c < 20 ? [1, 2, 3, 7, 10, 42, 99999][c % 7] : ri(1, 99999), pi, mode: pick(modes), teams, perTeam, budget: pick(BUD), seats });
  }
  for (let c = 0; c < 190; c++){
    const teams = ri(2, 4), perTeam = ri(1, 4), n = Math.min(12, teams * perTeam), seats = seatList(n, teams), pi = ri(0, n - 1);
    const fac = c < 150 ? facs[c % facs.length].k : pick(['zz', '', 'mod', 'kn', 'sw', 'or']);
    seats[pi] = { team: seats[pi].team, bot: false, fac };
    al.push({ seed: ri(1, 99999), pi, mode: pick(modes), teams, perTeam, budget: c < 150 ? BUD[c % BUD.length] : pick(BUD), seats,
      dev: ['dev:' + c, ri(1, 99999)], fac_page: core[fac] && core[fac].length ? fac : 'mod' });
  }
  // the pinned cases: big budgets where the page's list goes past SLOT_MAX (the cheapest unit of mod, and upgrades)
  [[10, 10000], [11, 10000], [12, 27000], [13, 28000], [14, 40000], [15, 40000]].forEach(p => {
    al.push({ seed: p[0], pi: 0, mode: 'pvp', teams: 2, perTeam: 1, budget: p[1], seats: [{ team: 0, bot: false, fac: 'mod' }, { team: 1, bot: true }],
      dev: ['dev:mod', p[0]], fac_page: 'mod' });
    al.push({ seed: p[0], pi: 1, mode: 'pvp', teams: 2, perTeam: 1, budget: p[1], seats: [{ team: 0, bot: false, fac: 'mod' }, { team: 1, bot: true }] });
  });
  al.forEach(c => { if (c.dev) c.fac_in = c.seats[c.pi].fac; });
  plan.auto_list = al;

  // depCapacity / depSlots
  plan.dep_capacity = [];
  [[0, 0], [4, 4], [5, 5], [6, 6], [24, 18], [25, 18], [26, 18], [45, 32], [46, 34], [48, 34], [65, 46], [66, 48], [67, 48], [100, 72],
    [105, 76], [180, 130], [-20, -20], [1, 30]].forEach(p => plan.dep_capacity.push(p));
  plan.dep_slots = [];
  [[1, 1], [5, 5], [6, 6], [7, 9], [24, 18], [26, 18], [36, 26], [46, 34], [48, 34], [60, 44], [61, 44], [67, 48], [72, 52], [100, 72],
    [101, 73], [163, 117], [166, 120], [180, 130]].forEach(p => plan.dep_slots.push(p));

  // fields for the placement checks (the page's genProps; one hand field with no props)
  plan.fields = {
    ruin48: { seed: 1, w: 48, theme: 'ruin', terrain: 'hills', density: 1 },
    forest60: { seed: 7, w: 60, theme: 'forest', terrain: 'forest', density: 1 },
    desert72: { seed: 3, w: 72, theme: 'desert', terrain: 'flat', density: 1 },
    ice40: { seed: 9, w: 40, theme: 'ice', terrain: 'mountain', density: 1.5 },
    ruin100: { seed: 21, w: 100, theme: 'ruin', terrain: 'hills', density: 2.5 },
    open48: { seed: 5, w: 48, d: 34, props: [] },
    open24: { seed: 6, w: 24, d: 18, props: [] },
  };
  const FW = { ruin48: [48, 34], forest60: [60, depthOf(60)], desert72: [72, depthOf(72)], ice40: [40, depthOf(40)], ruin100: [100, depthOf(100)],
    open48: [48, 34], open24: [24, 18] };

  // depWhyNot: seats with deps, random grid points, points just inside/outside the table margin and the spacing rules
  plan.dep_why_not = [];
  [['ruin48', 2, 2], ['forest60', 2, 1], ['desert72', 4, 1], ['ruin100', 3, 2]].forEach(F => {
    const [w, d] = FW[F[0]], W = w * 500 - 3000, D = d * 500 - 3000, teams = F[1], perTeam = F[2], seats = [];
    for (let k = 0; k < teams * perTeam; k++){
      const s = { team: Math.floor(k / perTeam) };
      if (k % 3 !== 2) s.dep = [g10(ri(-W, W)), g10(ri(-D, D))];
      seats.push(s);
    }
    const q = [];
    for (let k = 0; k < 140; k++) q.push([ri(0, seats.length - 1), g10(ri(-W - 2000, W + 2000)), g10(ri(-D - 2000, D + 2000))]);
    [[W, 0], [W + 10, 0], [-W, D], [-W - 10, D], [0, D + 10], [0, -D]].forEach(p => q.push([0, p[0], p[1]]));
    seats.forEach((s, k) => { if (!s.dep) return;
      [[5000, 0], [4990, 0], [3000, 4000], [0, -5010], [20000, 0], [19990, 0], [12000, 16000], [-20010, 0]].forEach(o =>
        q.push([(k + 1) % seats.length, s.dep[0] + o[0], s.dep[1] + o[1]])); });
    plan.dep_why_not.push({ field: F[0], setup: { mode: 'team', teams, perTeam, budget: 500 }, seats, q });
  });

  // autoDep: every seat in order (as resolveBots does), some seats with a dep placed first
  plan.auto_dep = [];
  const AD = [['ruin48', 2, 1], ['ruin48', 2, 2], ['ruin48', 2, 4], ['forest60', 4, 1], ['desert72', 8, 1], ['ice40', 2, 3],
    ['ruin100', 3, 4], ['ruin100', 8, 1], ['open24', 4, 2], ['open24', 2, 1], ['open48', 6, 1], ['desert72', 2, 4]];
  AD.forEach((F, fi) => {
    const teams = F[1], perTeam = F[2], seats = [], [w, d] = FW[F[0]], W = w * 500 - 3000, D = d * 500 - 3000;
    for (let k = 0; k < teams * perTeam; k++) seats.push({ team: Math.floor(k / perTeam) });
    if (fi % 3 === 1) seats[seats.length - 1].dep = [g10(ri(-W, W)), g10(ri(-D, D))];
    const ask = seats.map((s, k) => k).filter(k => !seats[k].dep);
    plan.auto_dep.push({ field: F[0], setup: { mode: 'team', teams, perTeam, budget: 500 }, seats, ask });
  });
  // a room team bigger than four (players may all pick one team online): the ring turns in steps of a sixth
  {
    const seats = [];
    for (let k = 0; k < 6; k++) seats.push({ team: 0 });
    for (let k = 0; k < 4; k++) seats.push({ team: 1 });
    plan.auto_dep.push({ field: 'ruin100', setup: { mode: 'team', teams: 2, perTeam: 4, budget: 500 }, seats, ask: seats.map((s, k) => k) });
    plan.auto_dep.push({ field: 'open48', setup: { mode: 'team', teams: 2, perTeam: 4, budget: 500 }, seats, ask: seats.map((s, k) => k) });
  }
  return plan;
}

// deploy and place need lists: the v10 autoList (seeded) of each seat, made in the page by the first pass
function deployPlan(plan, lists){
  const rnd = mulberry32(20261009), ri = (lo, hi) => lo + Math.floor(rnd() * (hi - lo + 1));
  const g10 = v => 10 * Math.round(v / 10);
  let li = 0;
  const take = () => lists[li++ % lists.length];
  const D = [
    ['ruin48', 'pvp', 2, 1, 500, 'given'], ['forest60', 'team', 2, 2, 1000, 'half'], ['desert72', 'ffa', 4, 1, 2000, 'given'],
    ['ice40', 'pvp', 2, 1, 3000, 'given'], ['ruin100', 'spectator', 8, 1, 1500, 'none'], ['open48', 'pvp', 2, 1, 10000, 'given'],
    ['open24', 'pvp', 2, 1, 1000, 'centre'], ['ruin48', 'team', 2, 3, 2000, 'half'],
  ];
  plan.deploy = D.map(d => {
    const [name, mode, teams, perTeam, budget, deps] = d, seats = [];
    for (let k = 0; k < teams * perTeam; k++) seats.push({ team: Math.floor(k / perTeam), list: take(), bot: true });
    if (name === 'ruin48' && mode === 'pvp') seats[1].list = [];                       // an empty army is skipped
    return { field: name, setup: { mode, teams, perTeam, budget }, seats, deps };
  });
  return plan;
}

function stable(v){ return JSON.stringify(v); }
// one array element per line for the long lists (readable diffs), fixed key order
function serialize(head, body){
  const parts = Object.keys(head).map(k => JSON.stringify(k) + ': ' + JSON.stringify(head[k]));
  for (const k of Object.keys(body)){
    const v = body[k];
    if (Array.isArray(v) && v.length && typeof v[0] === 'object') parts.push(JSON.stringify(k) + ': [\n' + v.map(stable).join(',\n') + '\n]');
    else parts.push(JSON.stringify(k) + ': ' + JSON.stringify(v));
  }
  return '{\n' + parts.join(',\n') + '\n}\n';
}

(async function main(){
  // DUMP_LAB=<file>: write the lab source (the cut page code) and stop, to read or syntax-check it
  if (process.env.DUMP_LAB){ fs.writeFileSync(process.env.DUMP_LAB, LAB); console.log('lab written to ' + process.env.DUMP_LAB); return; }
  const { chromium } = loadPlaywright();
  const browser = await chromium.launch({ executablePath: process.env.CHROMIUM_PATH || undefined, args: ['--no-sandbox'] });
  let res, plan;
  try {
    const page = await browser.newPage({ viewport: { width: 480, height: 320 } });
    const errs = []; page.on('pageerror', e => errs.push(String(e.stack || e).slice(0, 400)));
    await page.goto('file://' + PAGE);
    await page.waitForFunction('window.BT && window.BT.G && window.BT.TYPES');
    await page.evaluate(code => { window.LAB = (0, eval)(code); }, LAB);
    const info = await page.evaluate(() => ({ types: JSON.parse(JSON.stringify(window.BT.TYPES)),
      facs: window.LAB.FACS.map(f => ({ k: f.k })), core: window.LAB.CORE }));
    plan = makePlan(info.types, info.facs, info.core);
    // the deploy armies are seeded v10 lists, made by the page's patched autoList on v10 draws
    const lists = await page.evaluate(n => { var L = window.LAB, out = [], s;
      for (s = 0; s < n; s++){ L.set({ seed: 100 + s, w: 48, d: 34, mode: 'pvp', teams: 2, perTeam: 1, budget: [500, 1000, 2000, 1500, 3000][s % 5],
        players: [{ id: 0, team: 0, bot: true, list: L.emptyList(), fac: 'mod' }] });
        L.rng(100 + s, 'armies:0', true); L.autoListV10(0, false);
        var P = L.G().players[0], sp = [], i; for (i = 0; i < P.list.length; i++) if (P.list[i]) sp.push([i, P.list[i]]); out.push(sp); }
      return out; }, 24);
    deployPlan(plan, lists);
    // deps for the deploy scenarios: given ones are the page's autoDep, rounded to 10 MI (v10 rounds at the source)
    // a dep on the table centre faces -z (the page's atan2(-0, -0)); one on an axis faces along it
    plan.deploy.forEach(c => { if (c.deps === 'centre'){ c.seats[0].dep = [0, 0]; c.seats[1].dep = [0, 5000]; } });
    const depOf = await page.evaluate(arg => { var L = window.LAB, BT = window.BT, Q = 65536, res = [];
      arg.forEach(function(c){
        var F = c.f; BT.setTheme(F.theme || 'ruin'); BT.setTerrain(F.terrain || 'flat'); BT.setBuildings((F.density || 0) > 0, F.density || 1); BT.seed(F.seed); BT.size(F.w);
        var props = F.props ? [] : BT.props().map(function(o){ return { kind: o.kind, x: Math.round(o.x*1000)/1000, z: Math.round(o.z*1000)/1000,
          rot: Math.round(o.rot*Q)/Q, s: Math.round(o.s*10000)/10000, h: Math.round(o.h*Q)/Q, rad: 2.4 }; });
        L.set({ seed: F.seed, w: F.w, d: F.props ? F.d : BT.table.d, props: props, mode: c.setup.mode, teams: c.setup.teams, perTeam: c.setup.perTeam,
          budget: c.setup.budget, players: c.seats.map(function(s, k){ return { id: k, team: s.team, nm: 'S' + k, list: [], fac: 'mod', dep: null }; }) });
        var G = L.G(), out = [];
        G.players.forEach(function(P, k){ var t = L.autoDep(k); P.dep = [10*Math.round(t.r[0]*100)/1000, 10*Math.round(t.r[1]*100)/1000];
          out.push([Math.round(P.dep[0]*1000), Math.round(P.dep[1]*1000)]); });
        res.push(out);
      });
      return res; }, plan.deploy.map(c => ({ f: plan.fields[c.field], setup: c.setup, seats: c.seats })));
    plan.deploy.forEach((c, ci) => {
      if (c.deps === 'given' || c.deps === 'half') c.seats.forEach((s, k) => { if (c.deps === 'given' || k % 2 === 0) s.dep = depOf[ci][k]; });
      delete c.deps;
    });
    // objectives: the fields with models about (some near the five spots) and one table packed round the centre
    const placeRnd = mulberry32(20261010), pri = (lo, hi) => lo + Math.floor(placeRnd() * (hi - lo + 1));
    const ptypes = info.types.filter(T => !T.sec && !T.lk).map(T => T.k);
    plan.place = ['ruin48', 'forest60', 'desert72', 'ice40', 'ruin100', 'open48', 'open24'].map((name, fi) => {
      const F = plan.fields[name], w = F.w, d = F.d || Math.round(w * 0.72 / 2) * 2, units = [];
      const spots = [[0, 0], [-w * 270, -d * 270], [w * 270, -d * 270], [-w * 270, d * 270], [w * 270, d * 270]];
      for (let k = 0; k < 30 + 10 * fi; k++){ const s = spots[k % 5];
        units.push([ptypes[pri(0, ptypes.length - 1)], 10 * Math.round((s[0] + pri(-3000, 3000)) / 10), 10 * Math.round((s[1] + pri(-3000, 3000)) / 10)]); }
      if (name === 'open24') for (let i = -4; i <= 4; i++) for (let j = -3; j <= 3; j++) units.push([ptypes[0], i * 1600, j * 1600]);
      return { field: name, units };
    });
    // oc / ctl / score worlds
    const orn = mulberry32(20261011), ori = (lo, hi) => lo + Math.floor(orn() * (hi - lo + 1));
    const R = {}; info.types.forEach(T => { R[T.k] = Math.round((T.r || 0.8) * 1000); });
    plan.obj_worlds = [];
    for (let wi = 0; wi < 40; wi++){
      const teams = ori(2, 4), obj = [], squads = [], units = [];
      for (let i = 0; i < 5; i++) obj.push([i + 1, 10 * ori(-2600, 2600), 10 * ori(-1800, 1800)]);
      const nsq = ori(3, 9);
      for (let i = 0; i < nsq; i++){
        const k = ptypes[ori(0, ptypes.length - 1)], side = i < teams ? i : ori(0, teams - 1), id = side + ':' + i;
        squads.push([id, k, side, orn() < 0.2 ? 1 : 0]);
        const o = obj[ori(0, 4)], nm = ori(1, 5);
        for (let j = 0; j < nm; j++){
          const reach = 3000 + R[k] + 1, a = orn() * Math.PI * 2, dist = orn() < 0.15 ? reach + ori(-2, 2) : ori(0, reach + 1500);
          units.push([id + '.' + j, id, o[1] + Math.round(Math.cos(a) * dist), o[2] + Math.round(Math.sin(a) * dist)]);
        }
      }
      // exact boundary pairs on an axis: the reach itself (in) and one MI more (out)
      if (wi % 4 === 0){ const s = squads[0], o = obj[0], reach = 3000 + R[s[1]] + 1;
        units.push([s[0] + '.x', s[0], o[1] + reach, o[2]], [s[0] + '.y', s[0], o[1], o[2] - reach - 1]); }
      for (let i = units.length - 1; i > 0; i--){ const j = ori(0, i); const t = units[i]; units[i] = units[j]; units[j] = t; }
      plan.obj_worlds.push({ teams, obj, squads, units });
    }
    res = await page.evaluate(sampler, plan);
    if (errs.length) console.log('page errors (ignored, the lab does not use the live game):', errs.slice(0, 3));
  } finally { await browser.close(); }
  const meta = { page: path.relative(ROOT, PAGE), app_ver: APP_VER, rules_v: RULES_V, recorder: 'godot/tools/record_army_objectives.js',
    functions: PIECES.map(p => p.anchor.replace(/[({ =\[]+$/, '').replace(/^(function|var) /, '') + '@' + p.line) };
  const A = res.army, O = res.obj;
  const files = [
    [OUT_ARMY, serialize({ about: 'generated by godot/tools/record_army_objectives.js — do not edit; positions are MI (page doubles x 1000, 1/1000 MI kept); robust = 1 when no traced decision changes within the recorder EPS', meta },
      { consts: A.consts, skins: A.skins, fit_list: A.fit_list, fac_of: A.fac_of, fit_skin: A.fit_skin, share: A.share, caps: A.caps, slot_max: A.slot_max,
        pts: A.pts, mk_players: A.mk_players, pcg: A.pcg, auto_list: A.auto_list, dep_capacity: A.dep_capacity, dep_slots: A.dep_slots,
        fields: res.fields, dep_why_not: A.dep_why_not, auto_dep: A.auto_dep, deploy: A.deploy })],
    [OUT_OBJ, serialize({ about: 'generated by godot/tools/record_army_objectives.js — do not edit; positions are MI; robust as in army/page_samples.json', meta },
      { fields: res.fields, place: O.place, worlds: O.worlds })],
  ];
  let diff = 0;
  for (const [file, text] of files){
    if (CHECK){
      const old = fs.existsSync(file) ? fs.readFileSync(file, 'utf8') : '';
      if (old !== text){ console.log('DIFFERS ' + path.relative(ROOT, file)); diff++; } else console.log('same    ' + path.relative(ROOT, file));
    } else {
      fs.mkdirSync(path.dirname(file), { recursive: true }); fs.writeFileSync(file, text);
      console.log('wrote ' + path.relative(ROOT, file) + ' (' + Buffer.byteLength(text) + ' B)');
    }
  }
  const al = A.auto_list, changed = al.filter(c => c.page.list);
  const over = al.filter(c => c.page.peak > 99).length;
  const cnt = (rows, f) => rows.reduce((n, r) => n + f(r), 0);
  console.log('autoList ' + al.length + ' (v10 guards change ' + changed.length + ', page past SLOT_MAX ' + over + ', armies drawn ' +
    new Set(al.filter(c => !c.c.dev).map(c => c.v10.fac)).size + ')');
  console.log('depWhyNot ' + cnt(A.dep_why_not, c => c.q.length) + ' (robust ' + cnt(A.dep_why_not, c => c.q.filter(q => q[5]).length) + ')' +
    ', autoDep ' + cnt(A.auto_dep, c => c.out.length) + ' (robust ' + cnt(A.auto_dep, c => c.out.filter(q => q[4]).length) + ')' +
    ', deploy models ' + cnt(A.deploy, c => c.models.length) + ' (robust ' + cnt(A.deploy, c => c.models.filter(m => m[6]).length) + ')' +
    ', objectives placed ' + cnt(O.place, c => c.obj.length) + ' (robust ' + cnt(O.place, c => c.obj.filter(o => o[4]).length) + ')' +
    ', oc worlds ' + O.worlds.length);
  if (diff) process.exit(1);
})().catch(e => { console.error(e.stack || e); process.exit(1); });
