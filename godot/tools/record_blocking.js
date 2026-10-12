#!/usr/bin/env node
// record_blocking.js — sample the old page's geometry for the v10 rules core (R1_PORT_SPEC §1.2 offsets, §1.3 blocking).
// The page's own functions (hash2, hash3, bldSize, BLOCK_R, propBlocks, blockAt, radOfType, TY, gx, gz, crowded,
// freeSpot, roomToLand) are cut out of battle-table.html as text and run inside the loaded page (Playwright, Chromium's
// V8) on data this script chooses, so nothing of the live game is touched. Writes:
//   godot/tests/unit/fixtures/offsets/page.json    the page's ring/rotation expressions rounded the v10 way
//   godot/tests/unit/fixtures/blocking/page.json   propBlocks / blockAt / roomToLand / crowded / freeSpot samples
//   node godot/tools/record_blocking.js            (re-running gives the same bytes: every input is seeded)
// Environment: PAGE=<battle-table.html>  CHROMIUM_PATH=<chrome>  NODE_PATH or tests/node_modules for playwright.
//
// Inputs are on the v10 integer grids (positions MI, rot and h Q16, scale s4 = s x 10^4), so the page computes with
// the same numbers the port gets. Every sample carries a `robust` flag: 1 when the page gives the same answer at 16
// points 12 MI around the query (for freeSpot: at every candidate it tried), i.e. the answer cannot flip by the v10
// rounding of a probe (grid 10 MI, Q16 trig). Tests assert robust samples exactly and only count the others.
'use strict';
const fs = require('fs'), path = require('path');

const ROOT = path.resolve(__dirname, '..', '..');
const PAGE = path.resolve(process.env.PAGE || path.join(ROOT, 'app/src/main/assets/battle-table.html'));
const OUT_OFF = path.join(ROOT, 'godot/tests/unit/fixtures/offsets/page.json');
const OUT_BLK = path.join(ROOT, 'godot/tests/unit/fixtures/blocking/page.json');

function loadPlaywright(){
  try { return require('playwright'); }
  catch (e) { return require(path.join(ROOT, 'tests/node_modules/playwright')); }
}

const src = fs.readFileSync(PAGE, 'utf8');
const APP_VER = (src.match(/var APP_VER = '([^']+)'/) || [])[1] || null;
const RULES_V = +((src.match(/var RULES_V = (\d+)/) || [])[1] || 0);

// ---------- cutting page code ----------
// from `anchor` to the brace that closes the first `{` after it (// comments and quoted strings skipped), plus a `;`
// right after it (the `var BLOCK_R = {...};` statement)
function cut(anchor, from){
  const a = src.indexOf(anchor, from || 0);
  if (a < 0) throw new Error('anchor not found: ' + anchor);
  let i = src.indexOf('{', a), depth = 0;
  while (i < src.length){
    const c = src[i];
    if (c === '/' && src[i + 1] === '/'){ i = src.indexOf('\n', i); continue; }
    if (c === "'" || c === '"'){ const q = c; i++; while (src[i] !== q){ if (src[i] === '\\') i++; i++; } i++; continue; }
    if (c === '{') depth++;
    else if (c === '}'){ depth--; if (depth === 0) break; }
    i++;
  }
  let end = i + 1;
  if (src[end] === ';') end++;
  return { text: src.slice(a, end), line: src.slice(0, a).split('\n').length };
}
const PIECES = [
  ['function hash2('], ['function hash3('], ['function bldSize('], ['var BLOCK_R = {'], ['function propBlocks('],
  ['function blockAt('], ['function radOfType('], ['function TY('], ['function gx(u)'], ['function gz(u)'],
  ['function crowded('], ['function freeSpot('], ['function roomToLand('],
].map(p => Object.assign({ anchor: p[0] }, cut(p[0])));
// freeSpot with its inner ok() traced: every call counts, and a call whose answer differs 12 MI away marks it fragile
const FS = PIECES.find(p => p.anchor === 'function freeSpot(');
const OK_HEAD = 'function ok(nx, nz, crowd){';
if (FS.text.indexOf(OK_HEAD) < 0) throw new Error('freeSpot has no ' + OK_HEAD);
const FS_TRACED = FS.text.replace('function freeSpot(', 'function freeSpotTraced(').replace(OK_HEAD,
  OK_HEAD + ' var __b = ok0(nx, nz, crowd); __T.n++; if (!__rob3(ok0, nx, nz, crowd, __b)) __T.bad++; return __b; }\n  function ok0(nx, nz, crowd){');

// the lab: the page's code in its own closure, bound to data this script sets (TYPES comes from the live page)
const LAB = '(function(){ "use strict";\n' +
  'var TAU = Math.PI*2, SEED = 1, PROPS = [], units = [], table = { w: 48, d: 34 }, TYPES = window.BT.TYPES, __T = { n: 0, bad: 0 }, EPS = 0.012;\n' +
  PIECES.map(p => '// page line ' + p.line + '\n' + p.text).join('\n') + '\n' + FS_TRACED + '\n' +
  'function __rob2(f, x, z, b){ for (var k = 0; k < 16; k++){ var a = k*Math.PI/8; if (f(x + Math.cos(a)*EPS, z + Math.sin(a)*EPS) !== b) return false; } return true; }\n' +
  'function __rob3(f, x, z, c, b){ for (var k = 0; k < 16; k++){ var a = k*Math.PI/8; if (f(x + Math.cos(a)*EPS, z + Math.sin(a)*EPS, c) !== b) return false; } return true; }\n' +
  'return { set: function(seed, w, d, props, us){ SEED = seed; table.w = w; table.d = d; PROPS = props; units = us; },\n' +
  '  hash3: hash3, bldSize: bldSize, propBlocks: propBlocks, blockAt: blockAt, crowded: crowded, freeSpot: freeSpot, roomToLand: roomToLand,\n' +
  '  freeSpotTraced: function(x, z, skip, from, maxD, rad){ __T.n = 0; __T.bad = 0; var r = freeSpotTraced(x, z, skip, from, maxD, rad); return { r: r, n: __T.n, bad: __T.bad }; },\n' +
  '  rob2: __rob2, radOfType: radOfType, TY: TY, gx: gx, gz: gz, TAU: TAU };\n})()';

// ---------- the sampler (runs inside the page) ----------
function sampler(){
  var L = window.LAB, TYPES = window.BT.TYPES;
  function xs(seed){ var x = (seed >>> 0) || 1; return function(){ x ^= x << 13; x >>>= 0; x ^= x >>> 17; x ^= x << 5; x >>>= 0; return x; }; }
  var R = xs(0x5EED1A2B);
  function ri(lo, hi){ return lo + (R() % (hi - lo + 1)); }          // integer lo..hi
  var Q = 65536, TWO_PI_Q = 411774;
  // a prop on the v10 grids: page doubles from the integers, and the integers the port gets
  function mkProp(kind, x, z, rq, s4, hq){
    return { o: { kind: kind, x: x / 1000, z: z / 1000, rot: rq / Q, s: s4 / 10000, h: hq / Q, rad: 2.4 }, row: [kind, x, z, rq, s4, hq, 0, 0] };
  }
  function bwbd(p){ if (p.o.kind !== 'building') return; var b = L.bldSize(p.o); p.row[6] = Math.round(b[0]*1000); p.row[7] = Math.round(b[1]*1000); }
  // the page answer at (x, z) MI and whether it is the same 12 MI around
  function blockRow(x, z){ var b = L.blockAt(x/1000, z/1000); return [x, z, b ? 1 : 0, L.rob2(L.blockAt, x/1000, z/1000, b) ? 1 : 0]; }
  function reachOf(o){ var S = o.s;
    if (o.kind === 'building') return Math.hypot((5 + o.h*7)*S/2 + 0.7, (4.5 + 6)*S/2 + 0.7);
    if (o.kind === 'wall') return Math.hypot((3 + Math.round(o.h*3))*1.2*S + 0.6, 0.9*S + 0.6);
    if (o.kind === 'pillars') return 4.5*S;
    return 3.2*S + 0.6; }

  // ---- 1. one prop at a time: every kind, rotations, scales (generated s = permille, injected s = any s4) ----
  var KINDS = ['building', 'wall', 'pillars', 'rubble', 'barricade', 'log', 'pipe', 'tower', 'boulder', 'iceslab',
    'obelisk', 'buried', 'tree', 'deadtree', 'pine', 'crater', 'arch', 'bush', 'statue'];
  var single = [], seedS = 7;
  KINDS.forEach(function(kind, ki){
    for (var v = 0; v < 6; v++){
      var s4 = v % 2 ? ri(7500, 14500) : ri(750, 1450)*10, rq = ri(0, TWO_PI_Q - 1), hq = ri(0, Q - 1);
      if (v === 0) rq = 0;
      if (v === 1) rq = 102944;                       // a quarter turn (Q16 of pi/2)
      var p = mkProp(kind, ri(-6000, 6000), ri(-4000, 4000), rq, s4, hq);
      L.set(seedS, 48, 34, [p.o], []); bwbd(p);
      var reach = reachOf(p.o), pts = [], k;
      for (k = 0; k < 90; k++) pts.push(blockRow(p.row[1] + ri(-Math.ceil(reach*1300), Math.ceil(reach*1300)),
                                                 p.row[2] + ri(-Math.ceil(reach*1300), Math.ceil(reach*1300))));
      // along the prop's own axes, just inside and just outside its half extents (world = local turned by rot)
      var c = Math.cos(p.o.rot), sn = Math.sin(p.o.rot), S = p.o.s, hx = 0, hz = 0;
      if (kind === 'building'){ hx = (5 + p.o.h*7)*S/2 + 0.7; hz = L.bldSize(p.o)[1]/2 + 0.7; }
      else if (kind === 'wall'){ hx = (3 + Math.round(p.o.h*3))*1.2*S + 0.6; hz = 0.9*S + 0.6; }
      if (hx){ [-1, 1].forEach(function(sg){ [hx - 0.03, hx + 0.03].forEach(function(e){
        var lx = sg*e, lz = 0.2*hz;                    // local -> world: (lx c + lz sn, -lx sn + lz c)
        pts.push(blockRow(p.row[1] + Math.round((lx*c + lz*sn)*1000), p.row[2] + Math.round((-lx*sn + lz*c)*1000)));
        lx = 0.2*hx; lz = sg*(e - hx + hz);
        pts.push(blockRow(p.row[1] + Math.round((lx*c + lz*sn)*1000), p.row[2] + Math.round((-lx*sn + lz*c)*1000))); }); }); }
      pts.push(blockRow(p.row[1], p.row[2]));          // the prop's centre
      single.push({ prop: p.row, pts: pts });
    }
  });

  // ---- 2. real fields from the page's genProps, snapped to the integer grids ----
  function pageField(seed, w, theme, terrain, dens){
    var BT = window.BT; BT.setTheme(theme); BT.setTerrain(terrain); BT.setBuildings(dens > 0, dens || 1); BT.seed(seed); BT.size(w);
    var d = BT.table.d, props = BT.props().map(function(o){
      return mkProp(o.kind, Math.round(o.x*1000), Math.round(o.z*1000), Math.round(o.rot*Q), Math.round(o.s*10000), Math.round(o.h*Q)); });
    L.set(seed, w, d, props.map(function(p){ return p.o; }), []);
    props.forEach(bwbd);
    return { seed: seed, w: w, d: d, theme: theme, terrain: terrain, density: dens, props: props.map(function(p){ return p.row; }), _o: props.map(function(p){ return p.o; }) };
  }
  var FIELDS = [[1, 48, 'ruin', 'hills', 1], [7, 60, 'forest', 'forest', 1], [3, 72, 'desert', 'flat', 1], [9, 40, 'ice', 'mountain', 1.5],
    [21, 100, 'ruin', 'hills', 2.5]];
  var fields = FIELDS.map(function(F){
    var f = pageField(F[0], F[1], F[2], F[3], F[4]), W = f.w*500, D = f.d*500, k, x, z;
    f.block = [];
    for (k = 0; k < 1200; k++) f.block.push(blockRow(ri(-W, W), ri(-D, D)));
    for (k = 0; k < 40; k++){ x = ri(-W, W); z = ri(-D, D);                // table edges at 0.8 in
      f.block.push(blockRow(W - 800 + ri(-3, 3), z)); f.block.push(blockRow(x, -(D - 800) + ri(-3, 3))); }
    // roomToLand: robust only when the point and each of its 24 probes are robust on their own
    f.room = [];
    for (k = 0; k < 300; k++){
      x = ri(-W, W); z = ri(-D, D);
      var pts = [[x/1000, z/1000]], r, a, ok = true;
      for (r = 1.25; r <= 2.5; r += 1.25) for (a = 0; a < 12; a++) pts.push([x/1000 + Math.cos(a*L.TAU/12)*r, z/1000 + Math.sin(a*L.TAU/12)*r]);
      pts.forEach(function(p){ if (!L.rob2(L.blockAt, p[0], p[1], L.blockAt(p[0], p[1]))) ok = false; });
      f.room.push([x, z, L.roomToLand(x/1000, z/1000) ? 1 : 0, ok ? 1 : 0]);
    }
    delete f._o;
    return f;
  });

  // ---- 3. crowded: bases of many sizes, with and without skip / r ----
  var withR = TYPES.filter(function(T){ return T.r; }), plain = TYPES.filter(function(T){ return !T.r; });
  function someType(){ return R() % 3 ? withR[R() % withR.length].k : plain[R() % plain.length].k; }
  function mkUnits(n, W, D){ var us = [], i; for (i = 0; i < n; i++) us.push({ id: 'u' + i, t: someType(), x: ri(-W, W)/1000, z: ri(-D, D)/1000 }); return us; }
  function unitRows(us){ return us.map(function(u){ return [u.t, Math.round(u.x*1000), Math.round(u.z*1000)]; }); }
  var crowd = [];
  [[40, 9000, 7000], [120, 20000, 14000]].forEach(function(C, ci){
    var us = mkUnits(C[0], C[1], C[2]), q = [], k;
    L.set(1, 48, 34, [], us);
    for (k = 0; k < 400; k++){
      var x = ri(-C[1], C[1]), z = ri(-C[2], C[2]), sk = R() % 3 ? -1 : R() % us.length, rr = [-1, -1, 0, 800, 1250, 2600][R() % 6];
      var skip = sk < 0 ? null : us[sk], rv = rr < 0 ? null : rr/1000, me = rv != null ? rv : skip ? L.radOfType(L.TY(skip.t)) : 0.8;
      var m = 1e9; us.forEach(function(u){ if (u === skip) return; m = Math.min(m, Math.abs(Math.hypot(u.x - x/1000, u.z - z/1000) - me - L.radOfType(L.TY(u.t)))); });
      q.push([x, z, sk, rr, L.crowded(x/1000, z/1000, skip, rv) ? 1 : 0, m > 1e-5 ? 1 : 0]);
    }
    crowd.push({ units: unitRows(us), q: q });
  });

  // ---- 4. freeSpot on page fields with models standing about ----
  function fsRow(x, z, sk, us, from, maxD, rad){
    var skip = sk < 0 ? null : us[sk], fr = from ? [from[0]/1000, from[1]/1000] : null;
    var t = L.freeSpotTraced(x/1000, z/1000, skip, fr, maxD == null ? null : maxD/1000, rad/1000);
    var plain = L.freeSpot(x/1000, z/1000, skip, fr, maxD == null ? null : maxD/1000, rad/1000);
    if (String(plain) !== String(t.r)) throw new Error('traced freeSpot differs');
    return { q: [x, z, sk, from ? from[0] : 0, from ? from[1] : 0, from ? 1 : 0, maxD == null ? -1 : maxD, rad],
             r: t.r ? [t.r[0], t.r[1]] : null, n: t.n, robust: t.bad ? 0 : 1 };
  }
  var spots = [];
  // a: a ruin field with a few dozen models, deploy-like (no limit) and move-like (from, maxD) queries
  (function(){
    var f = pageField(1, 48, 'ruin', 'hills', 1), us = mkUnits(60, 22000, 15000), out = [], k;
    L.set(1, f.w, f.d, f._o, us);
    for (k = 0; k < 160; k++){
      var x = ri(-2300, 2300)*10, z = ri(-1600, 1600)*10, sk = R() % 4 ? -1 : R() % us.length, lim = R() % 5 < 2;
      var from = lim ? [x + ri(-300, 300)*10, z + ri(-300, 300)*10] : null, maxD = lim ? ri(100, 800)*10 : null;
      out.push(fsRow(x, z, sk, us, from, maxD, [800, 1100, 1500, 2200][R() % 4]));
    }
    delete f._o; spots.push({ name: 'ruin_48_models', field: f, units: unitRows(us), q: out });
  })();
  // b: a packed block of models round the centre: the near rings are all taken, the wide pass (r >= 11) finds room
  (function(){
    var f = pageField(5, 48, 'forest', 'flat', 0), us = [], i, j, out = [];
    for (i = -8; i <= 8; i++) for (j = -8; j <= 8; j++) us.push({ id: 'p' + i + '_' + j, t: plain[0].k, x: i*1.6, z: j*1.6 });
    L.set(5, f.w, f.d, f._o, us);
    for (i = 0; i < 12; i++) out.push(fsRow(ri(-300, 300)*10, ri(-300, 300)*10, i % 3 ? -1 : (R() % us.length), us, null, null, 800));
    delete f._o; spots.push({ name: 'forest_48_packed', field: f, units: unitRows(us), q: out });
  })();
  // c: a small table covered with models: no free base anywhere, the crowd-off pass picks the first open ground
  (function(){
    var f = pageField(11, 24, 'desert', 'flat', 1), us = [], i, j, out = [];
    for (i = -7; i <= 7; i++) for (j = -5; j <= 5; j++) us.push({ id: 'c' + i + '_' + j, t: plain[0].k, x: i*1.6, z: j*1.6 });
    L.set(11, f.w, f.d, f._o, us);
    for (i = 0; i < 6; i++) out.push(fsRow(ri(-800, 800)*10, ri(-600, 600)*10, -1, us, null, null, 800));
    delete f._o; spots.push({ name: 'desert_24_covered', field: f, units: unitRows(us), q: out });
  })();
  // d: one huge building over the whole table: nothing is free, freeSpot gives back the point (or null with a limit)
  (function(){
    var big = mkProp('building', 0, 0, 0, 100000, 0), f = { seed: 2, w: 40, d: 28, theme: 'ruin', terrain: 'flat', density: 1 }, out = [];
    L.set(2, f.w, f.d, [big.o], []); bwbd(big); f.props = [big.row];
    out.push(fsRow(1230, -4560, -1, [], null, null, 800));
    out.push(fsRow(-3000, 2000, -1, [], [-3000, 2000], 5000, 800));
    out.push(fsRow(0, 0, -1, [], [0, 0], 1000, 1100));
    spots.push({ name: 'ruin_40_all_blocked', field: f, units: [], q: out });
  })();
  // e: a very big turned building on a big table: the first free ring is far out (r ~ 15..45), Q16 trig at range
  [[100, 80000, 30000], [180, 140000, 70000]].forEach(function(C){
    var big = mkProp('building', ri(-200, 200)*10, ri(-200, 200)*10, C[2], C[1], ri(0, 20000)), out = [], i;
    var f = { seed: 4, w: C[0], d: Math.round(C[0]*0.72/2)*2, theme: 'ruin', terrain: 'flat', density: 1 };
    L.set(4, f.w, f.d, [big.o], []); bwbd(big); f.props = [big.row];
    for (i = 0; i < 6; i++) out.push(fsRow(big.row[1] + ri(-1500, 1500)*10, big.row[2] + ri(-1500, 1500)*10, -1, [], null, null, 800));
    spots.push({ name: 'ruin_' + C[0] + '_big_house', field: f, units: [], q: out });
  });
  // ---- 5. the wide search's ring count, Math.ceil(Math.hypot(w, d) / 1.25), for page-sized and odd tables ----
  var far = [], w2, d2;
  for (w2 = 4; w2 <= 240; w2 += 2){ d2 = Math.round(w2*0.72/2)*2; far.push([w2, d2, Math.ceil(Math.hypot(w2, d2)/1.25)]); }
  [[3, 4], [30, 40], [48, 36], [60, 80], [75, 100], [5, 5], [1, 1], [7, 24], [20, 21], [9, 40]].forEach(function(p){
    far.push([p[0], p[1], Math.ceil(Math.hypot(p[0], p[1])/1.25)]); });
  return { single: single, fields: fields, crowded: crowd, free_spot: spots, far: far };
}

// the page's ring and rotation expressions, rounded the way v10 stores them (godot/tools/gen_offsets.gd)
function offsetsInPage(){
  var TAU = Math.PI*2, out = { near: [], room: [], plan: [[0, 0]], charge: [], side: [], ring_n: [] }, r, a, k, an;
  for (r = 1; r <= 10; r++) for (a = 0; a < 14; a++){ an = a*TAU/14 + r*0.41;
    out.near.push([10*Math.round(Math.cos(an)*r*1.25*100), 10*Math.round(Math.sin(an)*r*1.25*100)]); }
  for (r = 1.25; r <= 2.5; r += 1.25) for (a = 0; a < 12; a++)
    out.room.push([Math.round(Math.cos(a*TAU/12)*r*1000), Math.round(Math.sin(a*TAU/12)*r*1000)]);
  for (k = 1; k <= 6; k++) for (a = 0; a < 10; a++){ an = a*TAU/10 + k*0.37;
    out.plan.push([10*Math.round(Math.cos(an)*k*0.8*100), 10*Math.round(Math.sin(an)*k*0.8*100)]); }
  for (k = 1; k <= 4; k++){ out.charge.push([Math.round(Math.cos(k*0.55)*65536), Math.round(Math.sin(k*0.55)*65536)]);
    out.side.push([Math.round(Math.cos(k*0.4)*65536), Math.round(Math.sin(k*0.4)*65536)]); }
  for (r = 1; r <= 400; r++) out.ring_n.push(Math.max(14, Math.round(r*1.25*TAU/1.2)));
  out.dep_ang_step = Math.round(0.7*65536); out.fs_ang_step = Math.round(0.41*65536);
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
  try {
    const page = await browser.newPage({ viewport: { width: 480, height: 320 } });
    const errors = [];
    page.on('pageerror', e => errors.push(String(e)));
    await page.goto('file://' + PAGE);
    await page.waitForFunction('window.BT && window.BT.G && window.BT.TYPES');
    await page.evaluate(code => { window.LAB = (0, eval)(code); }, LAB);
    const meta = { page: path.relative(ROOT, PAGE), app_ver: APP_VER, rules_v: RULES_V, recorder: 'godot/tools/record_blocking.js',
      sources: PIECES.map(p => p.anchor.replace(/[({ =]+$/, '').replace(/^(function|var) /, '') + ':' + p.line) };
    const off = await page.evaluate(offsetsInPage);
    const blk = await page.evaluate(sampler);
    if (errors.length) console.log('page errors (ignored, the lab does not use the live game):', errors.slice(0, 3));
    fs.mkdirSync(path.dirname(OUT_OFF), { recursive: true });
    fs.mkdirSync(path.dirname(OUT_BLK), { recursive: true });
    fs.writeFileSync(OUT_OFF, serialize(Object.assign({ meta }, off)));
    fs.writeFileSync(OUT_BLK, serialize(Object.assign({ meta: Object.assign({ eps_mi: 12 }, meta) }, blk)));
    const count = (a, f) => a.reduce((n, x) => n + f(x), 0);
    const singles = count(blk.single, s => s.pts.length), fieldPts = count(blk.fields, f => f.block.length + f.room.length);
    const fs_q = count(blk.free_spot, s => s.q.length), fs_r = count(blk.free_spot, s => count(s.q, q => q.robust));
    console.log('offsets: ' + path.relative(ROOT, OUT_OFF));
    console.log('blocking: ' + path.relative(ROOT, OUT_BLK) + ' — ' + singles + ' single-prop points, ' + fieldPts + ' field points, ' +
      count(blk.crowded, c => c.q.length) + ' crowded queries, ' + fs_q + ' freeSpot queries (' + fs_r + ' robust)');
  } finally { await browser.close(); }
})().catch(e => { console.error(e); process.exit(1); });
