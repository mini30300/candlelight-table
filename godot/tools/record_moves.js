#!/usr/bin/env node
// record_moves.js — sample the old page's move rules for the v10 port (R1_PORT_SPEC §1.11, core/battle/moves.gd BtMoves):
// moveRange, nearFoe, spotFree, planMove, applySMove, tryMoveSq, canGroup / groupAll, groupMove, chargeSpots.
// The page's own functions are cut out of battle-table.html as text and run inside the loaded page (Playwright,
// Chromium's V8) over worlds this script builds: props from the page's genProps snapped to the v10 integer grids
// (positions MI, rot and h Q16, scale s4 = s x 10^4), squads placed with the page's formation + freeSpot and snapped to
// the 10 MI grid, so the page computes with the same numbers the port gets. Nothing of the live game is touched, except
// one live cross-check (a started match: BT.move / BT.groupMove with BT.capture) proving the cut code is the running code.
//   node godot/tools/record_moves.js            write godot/tests/unit/fixtures/moves/page.json
//   node godot/tools/record_moves.js --check    re-run and fail unless the file is byte-identical
// Environment: PAGE=<battle-table.html>  CHROMIUM_PATH=<chrome>  NODE_PATH or tests/node_modules for playwright.
//
// planMove / tryMoveSq / groupMove / chargeSpots samples carry `robust`: 1 when no decision the page took on the way
// (range and table-margin tests, spotFree / blockAt / crowded / nearFoe / freeSpot answers, the nearest-slot and
// nearest-target choices, the sidestep comparisons, the group sort, the 0.3-inch "anyone moved" tests) could flip if
// the candidate moved by EPS (50 MI; sidestep candidates 50 MI + 2 MI per inch of move range). That is the most the
// v10 integer candidates (10 MI grid, norm1000 facings, Q16 turns) differ from the page's doubles (R1_PORT_SPEC §7
// #2-#4). A decision is fragile only when flipping its fragile parts could change it (a candidate that fails a robust
// test elsewhere is not fragile). The test asserts robust samples and only counts the others. Each sample also keeps
// the page's decision path, so a failure names the step: plan [slot, kind, a, b] with kind 0 ring (a = PLAN_RING
// index), 1 straight back (a = k), 2 sidestep (a, b = k), 3 stays; charge [target model index, kind, try] with kind 0
// a try round the target, 1 freeSpot, 2 own spot, 3 no target model.
'use strict';
const fs = require('fs'), path = require('path');

const ROOT = path.resolve(__dirname, '..', '..');
const PAGE = path.resolve(process.env.PAGE || path.join(ROOT, 'app/src/main/assets/battle-table.html'));
const OUT = path.join(ROOT, 'godot/tests/unit/fixtures/moves/page.json');
const CHECK = process.argv.includes('--check');
const EPS = 0.05;

function loadPlaywright(){
  try { return require('playwright'); }
  catch (e) { return require(path.join(ROOT, 'tests/node_modules/playwright')); }
}

const src = fs.readFileSync(PAGE, 'utf8');
const APP_VER = (/var APP_VER = '([^']+)'/.exec(src) || [])[1] || null;
const RULES_V = +((/var RULES_V = (\d+)/.exec(src) || [])[1] || 0);
function lineOf(i){ return src.slice(0, i).split('\n').length; }

// the full text of `function NAME(...){ ... }` (first declaration at the start of a line): braces counted, strings and
// comments skipped (none of the cut functions holds a regex literal)
function cutFunction(name){
  const re = new RegExp('^function ' + name + '\\(', 'm'), m = re.exec(src);
  if (!m) throw new Error('function not found on the page: ' + name);
  let i = src.indexOf('{', m.index), depth = 0;
  for (; i < src.length; i++){
    const c = src[i], n = src[i + 1];
    if (c === '/' && n === '/'){ i = src.indexOf('\n', i); continue; }
    if (c === '/' && n === '*'){ i = src.indexOf('*/', i) + 1; continue; }
    if (c === '"' || c === "'" || c === '`'){ const q = c; i++; while (src[i] !== q){ if (src[i] === '\\') i++; i++; } continue; }
    if (c === '{') depth++;
    else if (c === '}'){ depth--; if (depth === 0) return { name, line: lineOf(m.index), text: src.slice(m.index, i + 1) }; }
  }
  throw new Error('unterminated function ' + name);
}
// `var NAME = <value>;` up to the first semicolon (BLOCK_R's object literal holds none)
function cutVar(name){
  const re = new RegExp('^var ' + name + ' = ', 'm'), m = re.exec(src);
  if (!m) throw new Error('var not found on the page: ' + name);
  const end = src.indexOf(';', m.index);
  return { name, line: lineOf(m.index), text: src.slice(m.index, end + 1) };
}

const FUNCS = ['clamp', 'hash2', 'hash3', 'bldSize', 'propBlocks', 'blockAt', 'radOfType', 'TY', 'gx', 'gz', 'dist2',
  'crowded', 'freeSpot', 'crowdedBy', 'sqModels', 'sqAlive', 'sqList', 'sqById', 'sqCenter', 'mEdge', 'sqEdge', 'realFoes',
  'engagedWith', 'isEngaged', 'formation', 'unitGoTo', 'moveRange', 'nearFoe', 'spotFree', 'planMove', 'applySMove',
  'tryMoveSq', 'canGroup', 'groupAll', 'groupMove', 'chargeSpots'];
const cuts = FUNCS.map(cutFunction).concat(['BLOCK_R', 'ENGAGE'].map(cutVar));
const textOf = name => cuts.find(c => c.name === name).text;

// exactly one occurrence of `a` replaced by `b`
function sub(t, a, b, label){
  const i = t.indexOf(a);
  if (i < 0 || t.indexOf(a, i + 1) >= 0) throw new Error(label + ': expected exactly one "' + a + '"');
  return t.slice(0, i) + b + t.slice(i + a.length);
}

// ---------- traced copies (the page's text with each decision wrapped; outputs must equal the plain function's) ----------
let PLAN_T = textOf('planMove').replace('function planMove(', 'function planMoveT(');
PLAN_T = sub(PLAN_T, 'Math.hypot(x - c.x, z - c.z) > 0.3 ?', '__gt(Math.hypot(x - c.x, z - c.z), 0.3, __EPS) ?', 'planMove');
PLAN_T = sub(PLAN_T, 'if (d < bd){ bd = d; best = j; }', 'if (__lt(d, bd, __EPS)){ bd = d; best = j; }', 'planMove');
PLAN_T = sub(PLAN_T, 'used.push(best);', 'used.push(best); __P = null;', 'planMove');
PLAN_T = sub(PLAN_T,
  'if (Math.hypot(px - gx(m), pz - gz(m)) > R + 0.001) continue;\n' +
  '      if (Math.abs(px) > table.w/2 - 1.2 || Math.abs(pz) > table.d/2 - 1.2) continue;\n' +
  '      if (spotFree(s, px, pz, r, chosen)) spot = [px, pz]; }',
  'if (__and([__notGt(Math.hypot(px - gx(m), pz - gz(m)), R + 0.001, __EPS), __notGt(Math.abs(px), table.w/2 - 1.2, __EPS),' +
  ' __notGt(Math.abs(pz), table.d/2 - 1.2, __EPS), __sfF(s, px, pz, r, chosen, __EPS)])){ spot = [px, pz]; __P = [0, k ? 1 + (k - 1)*10 + a : 0]; } }',
  'planMove');
PLAN_T = sub(PLAN_T, 'if (spotFree(s, qx, qz, r, chosen)) spot = [qx, qz]; }',
  'if (__and([__sfF(s, qx, qz, r, chosen, __EPS)])){ spot = [qx, qz]; __P = [1, k]; } }', 'planMove');
PLAN_T = sub(PLAN_T, 'var bd2 = L - 0.3, a0 = Math.atan2(dx, dz);', 'var bd2 = L - 0.3, a0 = Math.atan2(dx, dz), __E2 = __EPS + R*0.002;', 'planMove');
PLAN_T = sub(PLAN_T, 'if (d2 < bd2 && spotFree(s, qx2, qz2, r, chosen)){ bd2 = d2; spot = [qx2, qz2]; }',
  'if (__and([__isLt(d2, bd2, __E2), __sfF(s, qx2, qz2, r, chosen, __E2)])){ bd2 = d2; spot = [qx2, qz2]; __P = [2, a, k]; }', 'planMove');
PLAN_T = sub(PLAN_T, 'if (!spot) spot = [gx(m), gz(m)]; }', 'if (!spot){ spot = [gx(m), gz(m)]; __P = [3]; } }', 'planMove');
PLAN_T = sub(PLAN_T, 'chosen.push(spot);', 'chosen.push(spot); __PATH.push([__T.bad, best].concat(__P));', 'planMove');

let TRY_T = textOf('tryMoveSq').replace('function tryMoveSq(', 'function tryMoveSqT(');
TRY_T = sub(TRY_T, 'if (d > R + 2.5){', 'if (__gt(d, R + 2.5, __EPS)){', 'tryMoveSq');
TRY_T = sub(TRY_T, 'if (blockAt(x, z)){', 'if (__bl(x, z, __EPS)){', 'tryMoveSq');
TRY_T = sub(TRY_T, 'var to = planMove(s, x, z),', 'var to = planMoveT(s, x, z),', 'tryMoveSq');
TRY_T = sub(TRY_T, 'for (i=0;i<ms.length;i++) if (Math.hypot(to[i][0] - gx(ms[i]), to[i][1] - gz(ms[i])) > 0.3) moved++;',
  'moved = __movedCount(to, ms);', 'tryMoveSq');
TRY_T = sub(TRY_T, 'nearFoe(s, x, z, radOfType(TY(s.k)))', '__nf(s, x, z, radOfType(TY(s.k)), __EPS)', 'tryMoveSq');
TRY_T = sub(TRY_T, 'if (eng && to.some(function(p, k){ return nearFoe(s, p[0], p[1], radOfType(TY(ms[k].t))); })){',
  'if (eng && __someNear(s, to, ms)){', 'tryMoveSq');

let GROUP_T = textOf('groupMove').replace('function groupMove(', 'function groupMoveT(');
GROUP_T = sub(GROUP_T, 'if (L < 0.3) return false;', 'if (__lt(L, 0.3, __EPS)) return false;', 'groupMove');
GROUP_T = sub(GROUP_T, 'return (cb.x*fx + cb.z*fz) - (ca.x*fx + ca.z*fz); });', 'return __cmp((cb.x*fx + cb.z*fz) - (ca.x*fx + ca.z*fz)); });', 'groupMove');
GROUP_T = sub(GROUP_T, 'var to = planMove(q, tx, tz),', 'var to = planMoveT(q, tx, tz),', 'groupMove');
GROUP_T = sub(GROUP_T, 'for (i=0;i<ms.length;i++) if (Math.hypot(to[i][0] - gx(ms[i]), to[i][1] - gz(ms[i])) > 0.3) any = true;',
  'any = __movedCount(to, ms) > 0;', 'groupMove');
GROUP_T = sub(GROUP_T, 'if (!any) return;', '__GB.push([q.id, any ? 1 : 0, __T.bad]); if (!any) return;', 'groupMove');

let CHG_T = textOf('chargeSpots').replace('function chargeSpots(', 'function chargeSpotsT(');
CHG_T = sub(CHG_T, 'if (d < bd){ bd = d; best = q; }', 'if (__lt(d, bd, __EPS)){ bd = d; best = q; }', 'chargeSpots');
CHG_T = sub(CHG_T, 'if (!best){ out.push([gx(m), gz(m)]); continue; }', 'if (!best){ out.push([gx(m), gz(m)]); __PATH.push([__T.bad, -1, 3]); continue; }', 'chargeSpots');
CHG_T = sub(CHG_T, 'var spot = null, tries;', 'var spot = null, tries; __P = null;', 'chargeSpots');
CHG_T = sub(CHG_T,
  'if (Math.hypot(x - gx(m), z - gz(m)) > dist + 0.001 || blockAt(x, z)) continue;\n' +
  '      if (taken.some(function(p){ return Math.hypot(p[0] - x, p[1] - z) < radOfType(TY(m.t))*2; })) continue;\n' +
  '      if (crowdedBy(x, z, m, taken)) continue;\n' +
  '      spot = [x, z]; }',
  'if (!__and([__notGt(Math.hypot(x - gx(m), z - gz(m)), dist + 0.001, __EPS), __notF(__blF(x, z, __EPS)),' +
  ' __takenF(taken, x, z, radOfType(TY(m.t))*2, __EPS), __notF(__cbF(x, z, m, taken, __EPS))])) continue;\n' +
  '      spot = [x, z]; __P = [0, tries]; }', 'chargeSpots');
CHG_T = sub(CHG_T, 'var fs = freeSpot(', 'var fs = __fs(', 'chargeSpots');
CHG_T = sub(CHG_T, 'spot = fs || [gx(m), gz(m)]; }', 'spot = fs || [gx(m), gz(m)]; __P = fs ? [1] : [2]; }', 'chargeSpots');
CHG_T = sub(CHG_T, 'taken.push(spot); out.push(spot); }', 'taken.push(spot); out.push(spot); __PATH.push([__T.bad, ts.indexOf(best)].concat(__P)); }', 'chargeSpots');

// freeSpot with its inner ok() traced (as tools/record_blocking.js): a call whose answer differs EPS away marks it fragile
const FS_HEAD = 'function ok(nx, nz, crowd){';
let FS_T = textOf('freeSpot');
if (FS_T.indexOf(FS_HEAD) < 0) throw new Error('freeSpot has no ' + FS_HEAD);
FS_T = FS_T.replace('function freeSpot(', 'function __fs(').replace(FS_HEAD,
  FS_HEAD + ' var __b = ok0(nx, nz, crowd); if (!__rob(function(px, pz){ return ok0(px, pz, crowd); }, nx, nz, __b, __EPS)) __T.bad++; __T.n++; return __b; }\n  function ok0(nx, nz, crowd){');

// ---------- the lab: the cut page code in its own closure, over worlds this script sets ----------
const LAB = '(function(){ "use strict";\n' +
  'var TAU = Math.PI*2, SEED = 1, PROPS = [], units = [], SQ = {}, SQ_ORDER = [], table = { w: 48, d: 34 }, TYPES = window.BT.TYPES;\n' +
  'var G = { turn: 0, act: null, sel: null, multi: null, freeFire: false }, AIM = null, dirty = false, WALKER = { goTo: function(){} };\n' +
  'var SENT = [], POPS = [], LOGT = [], __T = { n: 0, bad: 0 }, __P = null, __PATH = [], __GB = [], __EPS = ' + EPS + ';\n' +
  'function flyK(){ return null; } function say(t){ LOGT.push(String(t)); } function sqLabel(s){ return s.id; } function paintPlay(){}\n' +
  'function popDice(t){ POPS.push(String(t)); } function netSend(a){ SENT.push(JSON.parse(JSON.stringify(a))); } function selectUnit(){}\n' +
  'function markGroup(){} function canAct(){ return true; }\n' +
  cuts.map(c => '// page line ' + c.line + '\n' + c.text).join('\n') + '\n' +
  PLAN_T + '\n' + TRY_T + '\n' + GROUP_T + '\n' + CHG_T + '\n' + FS_T + '\n' + `
// ---- decision tracing ----
function __mark(f){ __T.n++; if (f) __T.bad++; }
function __gt(a, b, e){ __mark(Math.abs(a - b) < e); return a > b; }
function __lt(a, b, e){ __mark(Math.abs(a - b) < e); return a < b; }
function __cmp(v){ __mark(Math.abs(v) < __EPS); return v; }
// one part of an "all must pass" decision: { v: passes, f: could flip }
function __notGt(a, b, e){ return { v: !(a > b), f: Math.abs(a - b) < e }; }
function __isLt(a, b, e){ return { v: a < b, f: Math.abs(a - b) < e }; }
function __notF(p){ return { v: !p.v, f: p.f }; }
// a predicate at (x, z) and 16 points e away plus 8 points e/2 away: true when all agree with b
function __rob(f, x, z, b, e){ var k, a;
  for (k = 0; k < 16; k++){ a = k*Math.PI/8; if (f(x + Math.cos(a)*e, z + Math.sin(a)*e) !== b) return false; }
  for (k = 0; k < 8; k++){ a = k*Math.PI/4 + 0.3; if (f(x + Math.cos(a)*e/2, z + Math.sin(a)*e/2) !== b) return false; }
  return true; }
function __sfF(s, x, z, r, chosen, e){ var v = spotFree(s, x, z, r, chosen);
  return { v: v, f: !__rob(function(px, pz){ return spotFree(s, px, pz, r, chosen); }, x, z, v, e) }; }
function __blF(x, z, e){ var v = blockAt(x, z); return { v: v, f: !__rob(blockAt, x, z, v, e) }; }
function __cbF(x, z, m, taken, e){ var v = crowdedBy(x, z, m, taken);
  return { v: v, f: !__rob(function(px, pz){ return crowdedBy(px, pz, m, taken); }, x, z, v, e) }; }
function __takenF(taken, x, z, lim, e){ var v = true, f = false;
  taken.forEach(function(p){ var d = Math.hypot(p[0] - x, p[1] - z); if (d < lim) v = false; if (Math.abs(d - lim) < e) f = true; });
  return { v: v, f: f }; }
// all parts pass; fragile when every part could be made to pass and some part could flip
function __and(parts){ var v = true, robustFail = false, f = false;
  parts.forEach(function(p){ if (!p.v){ v = false; if (!p.f) robustFail = true; } if (p.f) f = true; });
  __mark(v ? f : (!robustFail && f)); return v; }
function __bl(x, z, e){ var p = __blF(x, z, e); __mark(p.f); return p.v; }
function __nf(s, x, z, r, e){ var v = nearFoe(s, x, z, r); __mark(!__rob(function(px, pz){ return nearFoe(s, px, pz, r); }, x, z, v, e)); return v; }
// how many models the plan moves over 0.3 inch: fragile when the zero / non-zero answer could flip
function __movedCount(to, ms){ var n = 0, sure = false, maybe = false, i;
  for (i = 0; i < ms.length; i++){ var d = Math.hypot(to[i][0] - gx(ms[i]), to[i][1] - gz(ms[i]));
    if (d > 0.3) n++; if (d > 0.3 + __EPS) sure = true; else if (Math.abs(d - 0.3) < __EPS) maybe = true; }
  __mark(!sure && maybe); return n; }
function __someNear(s, to, ms){ var any = false, sure = false, maybe = false;
  to.forEach(function(p, k){ var r = radOfType(TY(ms[k].t)), v = nearFoe(s, p[0], p[1], r), rb = __rob(function(px, pz){ return nearFoe(s, px, pz, r); }, p[0], p[1], v, __EPS);
    if (v) any = true; if (v && rb) sure = true; if (!rb) maybe = true; });
  __mark(!sure && maybe); return any; }
function __start(){ __T.n = 0; __T.bad = 0; __P = null; __PATH = []; __GB = []; SENT.length = 0; POPS.length = 0; LOGT.length = 0; }
// ---- worlds ----
// W: { seed, w, d, turn, props: page objects, squads: [[id, k, side, pl, n0, adv, advR, moved, fx, fz]], units: [[id, sq, hp, x, z]] (MI) }
function setWorld(W){
  SEED = W.seed; table.w = W.w; table.d = W.d; PROPS = W.props; units.length = 0; SQ = {}; SQ_ORDER.length = 0;
  W.squads.forEach(function(r){ var s = { id: r[0], k: r[1], side: r[2], pl: r[3], n0: r[4], adv: !!r[5], advR: r[6], moved: !!r[7],
    still: true, fell: false, shot: false, charged: false, chDone: false, fx: r[8], fz: r[9] }; SQ[s.id] = s; SQ_ORDER.push(s.id); });
  W.units.forEach(function(r){ var s = SQ[r[1]]; units.push({ id: r[0], sq: r[1], t: s.k, k: s.k, side: s.side, pl: s.pl, hp: r[2],
    x: r[3]/1000, z: r[4]/1000, rot: Math.atan2(s.fx, s.fz) }); });
  G.turn = W.turn || 0; G.multi = null; G.act = null; G.sel = null; AIM = null;
}
// a raw page world (live check): props as they are, units with rules positions, squads with their flags
function setRaw(seed, w, d, turn, props, us, sqs){
  SEED = seed; table.w = w; table.d = d; PROPS = props; units.length = 0; SQ = {}; SQ_ORDER.length = 0;
  sqs.forEach(function(s){ SQ[s.id] = s; SQ_ORDER.push(s.id); }); us.forEach(function(u){ units.push(u); });
  G.turn = turn; G.multi = null; G.act = null; G.sel = null; AIM = null;
}
function mi(v){ return Math.round(v*1000); }
function pts(a){ return a.map(function(p){ return [mi(p[0]), mi(p[1])]; }); }
return {
  setWorld: setWorld, setRaw: setRaw, start: __start, T: function(){ return { n: __T.n, bad: __T.bad }; }, path: function(){ return __PATH.slice(); }, steps: function(){ return __GB.slice(); },
  units: function(){ return units; }, SQ: function(){ return SQ; }, G: G, sent: function(){ return SENT.slice(); }, pops: function(){ return POPS.slice(); },
  logs: function(){ return LOGT.slice(); }, mi: mi, pts: pts,
  hash3: hash3, bldSize: bldSize, blockAt: blockAt, radOfType: radOfType, TY: TY, gx: gx, gz: gz, freeSpot: freeSpot, crowded: crowded,
  sqModels: sqModels, sqCenter: sqCenter, sqEdge: sqEdge, realFoes: realFoes, isEngaged: isEngaged, formation: formation, sqById: sqById,
  moveRange: moveRange, nearFoe: nearFoe, spotFree: spotFree, planMove: planMove, planMoveT: planMoveT, applySMove: applySMove,
  tryMoveSq: tryMoveSq, tryMoveSqT: tryMoveSqT, canGroup: canGroup, groupAll: groupAll, groupMove: groupMove, groupMoveT: groupMoveT,
  chargeSpots: chargeSpots, chargeSpotsT: chargeSpotsT, ENGAGE: ENGAGE };
})()`;

// ---------- the sampler (runs inside the page) ----------
function sampler(EPS){
  var L = window.LAB, BT = window.BT, TYPES = BT.TYPES;
  function xs(seed){ var x = (seed >>> 0) || 1; return function(){ x ^= x << 13; x >>>= 0; x ^= x >>> 17; x ^= x << 5; x >>>= 0; return x; }; }
  var R = xs(0x40E5A11C);
  function ri(lo, hi){ return lo + (R() % (hi - lo + 1)); }
  function pick(a){ return a[R() % a.length]; }
  function g10(v){ return 10*Math.round(v/10); }
  var Q = 65536, mi = L.mi;
  var OPEN = TYPES.filter(function(T){ return !T.sec && !T.lk; }), MULTI = OPEN.filter(function(T){ return T.n >= 3; });
  // exact unit facings (length 1000), so the page's rot and the port's (fx, fz) are the same direction
  var FACES = [[0, 1000], [1000, 0], [0, -1000], [-1000, 0], [600, 800], [-800, 600], [-600, -800], [800, -600]];
  function radMi(k){ return Math.round(L.radOfType(L.TY(k))*1000); }

  // a prop on the v10 grids: page doubles from the integers, and the integer row the port gets
  function mkProp(kind, x, z, rq, s4, hq){
    return { o: { kind: kind, x: x/1000, z: z/1000, rot: rq/Q, s: s4/10000, h: hq/Q, rad: 2.4 }, row: [kind, x, z, rq, s4, hq, 0, 0] };
  }
  function pageField(seed, w, theme, terrain, dens){
    BT.setTheme(theme); BT.setTerrain(terrain); BT.setBuildings(dens > 0, dens || 1); BT.seed(seed); BT.size(w);
    var d = BT.table.d, props = BT.props().map(function(o){
      return mkProp(o.kind, Math.round(o.x*1000), Math.round(o.z*1000), Math.round(o.rot*Q), Math.round(o.s*10000), Math.round(o.h*Q)); });
    return { seed: seed, w: w, d: d, theme: theme, terrain: terrain, density: dens, props: props };
  }
  // the world as the lab and as the fixture (props rows get bw / bd from the page's bldSize under this seed)
  function lab(W){ L.setWorld({ seed: W.seed, w: W.w, d: W.d, turn: W.turn, props: W.propsO, squads: W.squads, units: W.units }); }
  function emit(W){ return { name: W.name, seed: W.seed, w: W.w, d: W.d, turn: W.turn, props: W.props, squads: W.squads, units: W.units }; }

  // ---- worlds: a field, two or three sides, squads set down like deploy (formation + freeSpot), some locked in melee ----
  var FIELDS = [['ruin48', [1, 48, 'ruin', 'hills', 1]], ['forest60', [7, 60, 'forest', 'forest', 1]], ['desert72', [3, 72, 'desert', 'flat', 1]],
    ['ice40', [9, 40, 'ice', 'mountain', 1.5]], ['ruin48dense', [5, 48, 'ruin', 'flat', 2]], ['open36', null]];
  function mkWorld(name, F, wi){
    var f = F ? pageField(F[0], F[1], F[2], F[3], F[4]) : { seed: 2, w: 36, d: 26, props: [] };
    var W = { name: name, seed: f.seed, w: f.w, d: f.d, turn: 0, propsO: f.props.map(function(p){ return p.o; }), squads: [], units: [] };
    lab(W);
    f.props.forEach(function(p){ if (p.o.kind === 'building'){ var b = L.bldSize(p.o); p.row[6] = Math.round(b[0]*1000); p.row[7] = Math.round(b[1]*1000); } });
    W.props = f.props.map(function(p){ return p.row; });
    var sides = 2 + (wi % 2), Wm = f.w*500 - 4000, Dm = f.d*500 - 4000, live = L.units();
    for (var side = 0; side < sides; side++){
      var nsq = ri(3, 5);
      for (var i = 0; i < nsq; i++){
        var T = R() % 5 < 3 ? pick(MULTI) : pick(OPEN), id = side + ':' + i, n = T.n, face = pick(FACES), r = L.radOfType(T);
        if (n > 1 && R() % 5 === 0) n = ri(1, n - 1);                     // some losses
        var adv = R() % 5 === 0, advR = adv ? ri(1, 6) : 0, moved = R() % 10 === 0 ? 1 : 0;
        W.squads.push([id, T.k, side, side, T.n, adv ? 1 : 0, advR, moved, face[0], face[1]]);
        lab(W);
        // a centre: anywhere, or (later sides) next to a squad of side 0 so that some squads start locked in melee
        var cx = ri(-Wm, Wm), cz = ri(-Dm, Dm), near = side > 0 && R() % 3 === 0;
        if (near){
          var mates = W.units.filter(function(u){ return u[1].charAt(0) === '0'; });
          if (mates.length){ var u0 = pick(mates), an = ri(0, 359)*Math.PI/180, dd = r*1000 + 800 + ri(200, 1600);
            cx = u0[3] + Math.round(Math.sin(an)*dd); cz = u0[4] + Math.round(Math.cos(an)*dd); }
        }
        var sl = L.formation(n, cx/1000, cz/1000, Math.atan2(face[0], face[1]), r);
        for (var j = 0; j < n; j++){
          var p = near && j === 0 ? sl[j] : (L.freeSpot(sl[j][0], sl[j][1], null, null, null, r) || sl[j]);
          var x = Math.max(-f.w*500 + 900, Math.min(f.w*500 - 900, g10(p[0]*1000))), z = Math.max(-f.d*500 + 900, Math.min(f.d*500 - 900, g10(p[1]*1000)));
          W.units.push([id + '.' + j, id, ri(1, T.w || 1), x, z]);
          live.push({ id: id + '.' + j, sq: id, t: T.k, k: T.k, side: side, pl: side, hp: 1, x: x/1000, z: z/1000 });
        }
      }
    }
    // units order is creation order with deaths spliced out: shuffle a little by moving a few to the back
    for (var q = 0; q < 3; q++){ var k2 = ri(0, W.units.length - 1); W.units.push(W.units.splice(k2, 1)[0]); }
    return W;
  }
  var worlds = FIELDS.map(function(F, wi){ return mkWorld(F[0], F[1], wi); });

  // engagement at the page's ENGAGE + 0.001 must not sit on a double-rounding edge (the port compares exactly)
  var engNear = 0;
  worlds.forEach(function(W){ lab(W); var sqs = Object.keys(L.SQ()).map(function(k){ return L.SQ()[k]; });
    sqs.forEach(function(a){ sqs.forEach(function(b){ if (a.side !== b.side && L.sqModels(a).length && L.sqModels(b).length && Math.abs(L.sqEdge(a, b) - (L.ENGAGE + 0.001)) < 1e-6) engNear++; }); }); });

  // ---- samples (each one on a fresh copy of its world; squads are looked up again after every reset) ----
  function aliveIds(W){ lab(W); return W.squads.map(function(r){ return r[0]; }).filter(function(id){ return L.sqModels(L.sqById(id)).length > 0; }); }
  function fresh(W, id){ lab(W); return L.sqById(id); }
  function targetFor(W, s, kind){
    var c = L.sqCenter(s), Rr = L.moveRange(s), an = ri(0, 3599)*Math.PI/1800, d;
    if (kind === 0) d = 0.4 + (R() % 1000)/1000*(Rr + 2);                   // a normal order
    else if (kind === 1) d = (R() % 250)/1000;                              // a short nudge: the squad's own facing
    else if (kind === 2) d = Rr + 2.5 + (R() % 4000)/1000;                   // too far for tryMoveSq, plan stops at range
    else if (kind === 3 && W.propsO.length){ var o = pick(W.propsO); return [g10(o.x*1000), g10(o.z*1000)]; }   // into a prop
    else if (kind === 4){ var foes = L.units().filter(function(u){ return u.side !== s.side; });                   // next to a foe
      if (foes.length){ var u = pick(foes); return [g10(L.gx(u)*1000 + ri(-2500, 2500)), g10(L.gz(u)*1000 + ri(-2500, 2500))]; } d = 3; }
    else d = 1 + (R() % 6000)/1000;
    return [g10(c.x*1000 + Math.sin(an)*d*1000), g10(c.z*1000 + Math.cos(an)*d*1000)];
  }
  var plan = [], tries = [], groups = [], charges = [], smoves = [], near = [], free = [], gall = [];
  // the traced path entries are [fragile decisions so far, ...decision]: the decisions, and how many lead without a fragile one
  function dec(p){ return p.map(function(e){ return e.slice(1); }); }
  function lead(p){ var n = 0; while (n < p.length && p[n][0] === 0) n++; return n; }
  worlds.forEach(function(W, wi){
    var all = aliveIds(W);
    // planMove
    for (var k = 0; k < 44; k++){
      var s = fresh(W, pick(all)), t = targetFor(W, s, k % 6);
      var plain = L.planMove(s, t[0]/1000, t[1]/1000);
      L.start(); var traced = L.planMoveT(s, t[0]/1000, t[1]/1000), T = L.T();
      if (JSON.stringify(plain) !== JSON.stringify(traced)) throw new Error('traced planMove differs');
      var P1 = L.path(); plan.push({ w: wi, u: s.id, x: t[0], z: t[1], to: L.pts(plain), path: dec(P1), ok_n: lead(P1), robust: T.bad ? 0 : 1 });
    }
    // tryMoveSq (fall back pressed on about half the orders; it only matters to engaged squads)
    for (k = 0; k < 40; k++){
      var id2 = pick(all), s2 = fresh(W, id2), t2 = targetFor(W, s2, k % 6), fb = R() % 2 === 0;
      L.G.act = fb ? 'fb' : 'move';
      L.start(); var ok = L.tryMoveSq(s2, t2[0]/1000, t2[1]/1000), sent = L.sent(), pops = L.pops();
      s2 = fresh(W, id2); L.G.act = fb ? 'fb' : 'move';
      L.start(); var okT = L.tryMoveSqT(s2, t2[0]/1000, t2[1]/1000), T2 = L.T();
      if (ok !== okT || JSON.stringify(sent) !== JSON.stringify(L.sent()) || JSON.stringify(pops) !== JSON.stringify(L.pops())) throw new Error('traced tryMoveSq differs');
      tries.push({ w: wi, u: id2, x: t2[0], z: t2[1], fb: fb ? 1 : 0, ok: ok ? 1 : 0, pop: pops.length ? pops[0] : '',
        act: sent.length ? { u: sent[0].u, how: sent[0].how, to: L.pts(sent[0].to) } : null, path: dec(L.path()), robust: T2.bad ? 0 : 1 });
    }
    // groupMove: two to five squads of one side, picked in a random order
    for (k = 0; k < 30; k++){
      lab(W); var side = k % 2, mine = all.filter(function(id){ return L.sqById(id).side === side; });
      var ids = [], m;
      for (m = 0; m < Math.min(mine.length, ri(2, 5)); m++){ var id = pick(mine); if (ids.indexOf(id) < 0) ids.push(id); }
      if (!ids.length) continue;
      var c0 = L.sqCenter(L.sqById(ids[0])), an2 = ri(0, 359)*Math.PI/180, dd2 = [3, 7, 14, 5, 0.2, 10][k % 6];
      var gxv = g10(c0.x*1000 + Math.sin(an2)*dd2*1000), gzv = g10(c0.z*1000 + Math.cos(an2)*dd2*1000);
      L.G.multi = ids.slice(); L.start(); var gok = L.groupMove(gxv/1000, gzv/1000), gsent = L.sent();
      lab(W); L.G.multi = ids.slice(); L.start(); var gokT = L.groupMoveT(gxv/1000, gzv/1000), T3 = L.T();
      if (gok !== gokT || JSON.stringify(gsent) !== JSON.stringify(L.sent())) throw new Error('traced groupMove differs');
      var GS = L.steps(), gn = 0; while (gn < GS.length && GS[gn][2] === 0) gn++;
      groups.push({ w: wi, ids: ids, x: gxv, z: gzv, acts: gsent.map(function(a){ return { u: a.u, how: a.how, to: L.pts(a.to) }; }),
        steps: GS.map(function(e){ return [e[0], e[1]]; }), ok_n: gn, robust: T3.bad ? 0 : 1 });
    }
    // chargeSpots: a squad onto a foe squad (mostly the nearest), the roll's sum in inches
    for (k = 0; k < 24; k++){
      var s3 = fresh(W, pick(all)), foes3 = all.map(L.sqById).filter(function(q){ return q.side !== s3.side; });
      if (!foes3.length) continue;
      foes3.sort(function(a, b){ return L.sqEdge(s3, a) - L.sqEdge(s3, b); });
      var t3 = k % 3 ? foes3[0] : pick(foes3), dist = ri(2, 12);
      var cplain = L.chargeSpots(s3, t3, dist);
      L.start(); var ctr = L.chargeSpotsT(s3, t3, dist), T4 = L.T();
      if (JSON.stringify(cplain) !== JSON.stringify(ctr)) throw new Error('traced chargeSpots differs');
      var P4 = L.path(); charges.push({ w: wi, u: s3.id, t: t3.id, dist: dist, to: L.pts(cplain), path: dec(P4), ok_n: lead(P4), robust: T4.bad ? 0 : 1 });
    }
    // applySMove: hand-made point lists (some nudges under 50 MI, some past the table edge, short and long lists)
    for (k = 0; k < 10; k++){
      var s4 = fresh(W, pick(all)), ms = L.sqModels(s4), how = pick(['move', 'adv', 'fb']), to = [], j;
      var nto = k % 4 === 3 ? Math.max(1, ms.length - 1) : ms.length + (k % 5 === 4 ? 1 : 0);
      for (j = 0; j < nto; j++){ var mm = ms[j % ms.length], kind = (j + k) % 4, ox, oz;
        if (kind === 0){ ox = ri(-3, 3)*10; oz = ri(-3, 3)*10; }                      // a nudge: at most 42 MI
        else if (kind === 1){ ox = ri(-600, 600)*10; oz = ri(-600, 600)*10; }
        else if (kind === 2){ ox = (R() % 2 ? 1 : -1)*W.w*600; oz = ri(-100, 100)*10; }  // off the table: clamped
        else { ox = 60; oz = 0; }
        to.push([mi(L.gx(mm)) + ox, mi(L.gz(mm)) + oz]); }
      var before = ms.map(function(u){ return [mi(L.gx(u)), mi(L.gz(u))]; });
      L.start(); L.applySMove(s4, to.map(function(p){ return [p[0]/1000, p[1]/1000]; }), how);
      var after = L.sqModels(s4).map(function(u){ return [mi(L.gx(u)), mi(L.gz(u))]; });
      smoves.push({ w: wi, u: s4.id, how: how, to: to, before: before, after: after, moved: s4.moved ? 1 : 0, still: s4.still ? 1 : 0,
        fell: s4.fell ? 1 : 0, log: L.logs()[0] || '' });
    }
    // nearFoe and spotFree at points round the squads (exact integer inputs: robust unless a test sits on its edge)
    for (k = 0; k < 60; k++){
      var s5 = fresh(W, pick(all)), c5 = L.sqCenter(s5), px = g10(c5.x*1000 + ri(-6000, 6000)), pz = g10(c5.z*1000 + ri(-6000, 6000));
      var r5 = [radMi(s5.k), 800, 1250, 2600][k % 4], nf = L.nearFoe(s5, px/1000, pz/1000, r5/1000), edge = false;
      L.units().forEach(function(q){ if (q.side !== s5.side && Math.abs(Math.hypot(L.gx(q) - px/1000, L.gz(q) - pz/1000) - r5/1000 - L.radOfType(L.TY(q.t)) - 1.05) < 1e-9) edge = true; });
      near.push([wi, s5.id, px, pz, r5, nf ? 1 : 0, edge ? 0 : 1]);
      var chosen = [], nc = k % 3;
      for (j = 0; j < nc; j++) chosen.push([g10(px + ri(-2500, 2500)), g10(pz + ri(-2500, 2500))]);
      var ch = chosen.map(function(p){ return [p[0]/1000, p[1]/1000]; }), sf = L.spotFree(s5, px/1000, pz/1000, r5/1000, ch);
      var rob = true, e = 0.012;
      for (j = 0; j < 16 && rob; j++){ var a5 = j*Math.PI/8; if (L.spotFree(s5, px/1000 + Math.cos(a5)*e, pz/1000 + Math.sin(a5)*e, r5/1000, ch) !== sf) rob = false; }
      free.push([wi, s5.id, px, pz, r5, chosen, sf ? 1 : 0, rob ? 1 : 0]);
    }
    // canGroup and groupAll for each side in turn
    for (var turn = 0; turn < 3; turn++){ lab(W); L.G.turn = turn;
      gall.push({ w: wi, turn: turn, all: L.groupAll(), can: W.squads.map(function(r){ return L.canGroup(L.SQ()[r[0]]) ? 1 : 0; }) }); }
  });
  // moveRange of every open datasheet, walking and after an advance of 1..6
  var mr = OPEN.map(function(T){ var row = [T.k]; for (var a = 0; a <= 6; a++) row.push(Math.round(L.moveRange({ k: T.k, adv: a > 0, advR: a })*1000)); return row; });
  return { worlds: worlds.map(emit), move_range: mr, near_foe: near, spot_free: free, plan: plan, try: tries, group: groups, charge: charges,
    smove: smoves, group_all: gall, eng_near: engNear };
}

// ---------- live cross-check: a started match, BT.move / BT.groupMove captured, against the cut code on a copy ----------
function live(){
  var L = window.LAB, BT = window.BT, G = BT.G, i, out = [];
  BT.clock(false); BT.quit(); BT.setTheme('ruin'); BT.setTerrain('hills'); BT.setBuildings(true, 1); BT.seed(13); BT.size(48);
  G.mode = 'pvp'; G.teams = 2; G.perTeam = 1; G.budget = 2000; G.freeFire = false; G.goal = 'obj'; G.rounds = 5;
  BT.mkPlayers();
  var want = [['infantry', 2], ['heavy', 1], ['cavalry', 1]], want2 = [['hoplite', 2], ['archer', 1], ['peltast', 1]];
  function list(w){ var L0 = []; for (i = 0; i < BT.TYPES.length; i++){ var c = 0; w.forEach(function(p){ if (BT.TYPES[i].k === p[0]) c = p[1]; }); L0.push(c); } return L0; }
  BT.setList(0, list(want)); BT.setList(1, list(want2));
  BT.players().forEach(function(P, k){ P.bot = true; var d = BT.autoDep(k); BT.setDep(k, d[0], d[1]); });
  BT.start(); BT.setPhase('move');
  // human seats from here on: groupMove's canGroup asks canAct, which refuses bot seats (no frame runs in between)
  BT.players().forEach(function(P){ P.bot = false; });
  function copyWorld(){
    var us = BT.units.map(function(u){ return { id: u.id, sq: u.sq, t: u.t, k: u.k, side: u.side, pl: u.pl, hp: u.hp,
      x: u.gx != null ? u.gx : u.x, z: u.gz != null ? u.gz : u.z, rot: u.rot }; });
    var sqs = BT.squads().map(function(s){ return JSON.parse(JSON.stringify(s)); });
    L.setRaw(BT.seedOf(), BT.table.w, BT.table.d, G.turn, BT.props().map(function(o){ return { kind: o.kind, x: o.x, z: o.z, rot: o.rot, s: o.s, h: o.h, rad: o.rad }; }), us, sqs);
  }
  var mine = BT.squads().filter(function(s){ return s.side === G.turn; });
  mine.slice(0, 3).forEach(function(s, k){
    var ms = BT.sqModels(s), cx = 0, cz = 0;
    ms.forEach(function(m){ cx += m.x; cz += m.z; }); cx /= ms.length; cz /= ms.length;
    // the first open ground of a few offsets (a target inside a prop is only refused)
    var offs = [[3.5, 2.75], [-2.25, 4.5], [1, -3], [-3, -1.5], [2.5, 0.5], [0.75, 3.25]], tx = 0, tz = 0, o;
    for (o = k; o < k + offs.length; o++){ tx = +(cx + offs[o % offs.length][0]).toFixed(2); tz = +(cz + offs[o % offs.length][1]).toFixed(2);
      if (!BT.blockAt(tx, tz)) break; }
    copyWorld(); L.start(); L.G.act = BT.engaged(s.id) ? 'fb' : 'move'; L.tryMoveSq(L.sqById(s.id), tx, tz); var labSent = L.sent();
    BT.capture(true); BT.move(s.id, tx, tz); var liveSent = BT.capture(false);
    out.push({ what: 'move ' + s.id + (labSent.length ? '' : ' (' + (L.pops()[0] || '').slice(0, 20) + ')'),
      same: JSON.stringify(labSent) === JSON.stringify(liveSent), n: liveSent.length });
  });
  var rest = BT.squads().filter(function(s){ return s.side === G.turn && !s.moved; }).map(function(s){ return s.id; });
  if (rest.length){
    var c0 = BT.sqModels(BT.sq(rest[0]))[0], gx = +(c0.x + 5).toFixed(2), gz = +(c0.z - 3).toFixed(2);
    copyWorld(); L.start(); L.G.multi = rest.slice(); L.groupMove(gx, gz); var labG = L.sent();
    BT.group(rest); BT.capture(true); BT.groupMove(gx, gz); var liveG = BT.capture(false);
    out.push({ what: 'group ' + rest.join(','), same: JSON.stringify(labG) === JSON.stringify(liveG), n: liveG.length });
  }
  BT.quit();
  return out;
}

// one element per line for the long arrays, so a diff reads sample by sample
function serialize(o){
  return '{\n' + Object.keys(o).map(k => {
    const v = o[k];
    if (Array.isArray(v) && v.length && typeof v[0] === 'object') return JSON.stringify(k) + ': [\n' + v.map(x => JSON.stringify(x)).join(',\n') + '\n]';
    return JSON.stringify(k) + ': ' + JSON.stringify(v);
  }).join(',\n') + '\n}\n';
}

(async () => {
  const { chromium } = loadPlaywright();
  const browser = await chromium.launch({ executablePath: process.env.CHROMIUM_PATH || undefined, args: ['--no-sandbox'] });
  let res, lv;
  try {
    const page = await browser.newPage({ viewport: { width: 480, height: 320 } });
    const errors = [];
    page.on('pageerror', e => errors.push(String(e)));
    await page.goto('file://' + PAGE);
    await page.waitForFunction('window.BT && window.BT.G && window.BT.TYPES');
    await page.evaluate(code => { window.LAB = (0, eval)(code); }, LAB);
    res = await page.evaluate(sampler, EPS);
    lv = await page.evaluate(live);
    if (errors.length) console.log('page errors (ignored, the lab does not use the live game):', errors.slice(0, 3));
  } finally { await browser.close(); }
  const bad = lv.filter(x => !x.same || !x.n);
  if (bad.length || lv.length < 4) throw new Error('the cut code differs from the live page: ' + JSON.stringify(lv));
  if (res.eng_near) throw new Error(res.eng_near + ' squad pairs sit on the engagement edge; change the world seed');
  const meta = { page: path.relative(ROOT, PAGE), app_ver: APP_VER, rules_v: RULES_V, recorder: 'godot/tools/record_moves.js',
    eps_mi: Math.round(EPS*1000), sources: cuts.map(c => c.name + ':' + c.line), live_check: lv };
  delete res.eng_near;
  const text = serialize(Object.assign({ meta }, res));
  if (CHECK){
    const old = fs.existsSync(OUT) ? fs.readFileSync(OUT, 'utf8') : '';
    console.log((old === text ? 'same    ' : 'DIFFERS ') + path.relative(ROOT, OUT));
    if (old !== text) process.exit(1);
  } else {
    fs.mkdirSync(path.dirname(OUT), { recursive: true });
    fs.writeFileSync(OUT, text);
    console.log('wrote ' + path.relative(ROOT, OUT) + ' (' + Buffer.byteLength(text) + ' B)');
  }
  const rob = a => a.filter(s => s.robust).length;
  console.log('plan ' + res.plan.length + ' (' + rob(res.plan) + ' robust), try ' + res.try.length + ' (' + rob(res.try) + '), group ' +
    res.group.length + ' (' + rob(res.group) + '), charge ' + res.charge.length + ' (' + rob(res.charge) + '), smove ' + res.smove.length +
    ', near_foe ' + res.near_foe.length + ', spot_free ' + res.spot_free.length + ', live ' + lv.length + ' same');
  const kinds = {}; res.plan.forEach(s => s.path.forEach(p => { kinds[p[1]] = (kinds[p[1]] || 0) + 1; }));
  const ck = {}; res.charge.forEach(s => s.path.forEach(p => { ck[p[1]] = (ck[p[1]] || 0) + 1; }));
  const pops = {}; res.try.forEach(s => { const k = s.ok ? 'ok' : s.pop.slice(0, 12); pops[k] = (pops[k] || 0) + 1; });
  console.log('plan decisions by kind ' + JSON.stringify(kinds) + ', charge ' + JSON.stringify(ck) + ', try ' + JSON.stringify(pops));
  const lead = a => a.reduce((n, s) => n + s.ok_n, 0) + ' of ' + a.reduce((n, s) => n + (s.path || s.steps).length, 0);
  console.log('decisions ahead of the first fragile one: plan models ' + lead(res.plan) + ', charge models ' + lead(res.charge) + ', group squads ' + lead(res.group));
})().catch(e => { console.error(e.stack || e); process.exit(1); });
