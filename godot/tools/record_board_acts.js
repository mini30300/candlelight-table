#!/usr/bin/env node
// record_board_acts.js — sample the page's board picture and the Worker's act sanitiser into JSON fixtures for the
// Godot port (core/battle/board.gd BtBoard, the codec half of core/battle/acts.gd BtActs; R1_PORT_SPEC §1.13, §1.14,
// §4, §5). Read-only on the page and on the Worker.
//
//   node godot/tools/record_board_acts.js            write the two fixtures
//   node godot/tools/record_board_acts.js --check    re-run and fail unless the files are byte-identical
// Environment: PAGE=<battle-table.html>  WORKER=<candlelight-server/worker.js>  CHROMIUM_PATH=<chrome>
//              NODE_PATH or tests/node_modules for playwright.
//
// Board: boardState() and what it calls (refreshObj, objCtl, objOC, sqList, sqCenter, isEngaged, maxRound, gx/gz, ...)
// are cut from the page text by anchor and run inside the loaded page (Chromium's V8) over worlds this script builds:
// MI integer positions (half on the 10 MI grid, some next to the toFixed(1) steps x.x5), squads with every flag,
// shaken squads, dead squads and models, drawn positions apart from the rules ones (gx/gz), objectives near models,
// both goals, 1-4 teams, seats with and without cp. Each world's page answer is JSON.stringify(boardState()), the
// exact text the owner posts. A world is drawn again when a model sits within 1e-7" of the engagement or objective
// reach (the page's double may fall either side there; BtSquads/BtObjectives pin the integer rule) or when a squad's
// exact mean centre sits within 1 MI of a toFixed(1) half step (D6/D7: the port rounds the integer js_round centre).
// Two hand worlds put centres exactly on such steps on purpose; their squads are listed in "tie" (±1 tenth).
// A live check runs the cut boardState over a started bot match and must equal BT.board() byte for byte.
// Also: +(mi/1000).toFixed(1) as tenths for a sweep, JSON.stringify of awkward strings, and JSON.stringify of
// board0 and the last board of each oracle recording (godot/tests/oracle/*.json.gz) for to_json.
//
// Acts: the "act" branch of btPost is cut from worker.js and run in Node on wire acts (inches, as a client posts
// them): hand-made cases plus up to three acts of each code the page really sent in the oracle recordings (with the
// pid "A" page B saw). The core form of a wire act turns to/x/z numbers into MI (10·Math.round(v·100), the oracle's conversion,
// §6); every other number in a case is an integer. want = the core form of the Worker's answer plus the pid the core
// keeps (the Worker adds it from the session). Cases where the core form cannot mirror JS (numeric strings, one-element
// arrays as numbers, an id cut inside a surrogate pair) are not recorded: test_acts.gd pins them by hand.
//
// Outputs:
//   godot/tests/unit/fixtures/board/page_samples.json    worlds + page board JSON, live check, tenths, strings, oracle
//   godot/tests/unit/fixtures/acts/worker_samples.json   sanitiser cases (wire, Worker answer, core, want, key order)
'use strict';
const fs = require('fs'), path = require('path'), zlib = require('zlib'), crypto = require('crypto');

const ROOT = path.resolve(__dirname, '..', '..');
const PAGE = path.resolve(process.env.PAGE || path.join(ROOT, 'app/src/main/assets/battle-table.html'));
const FIX = path.join(ROOT, 'godot/tests/unit/fixtures');
const ORACLE = path.join(ROOT, 'godot/tests/oracle');
const OUT_BOARD = path.join(FIX, 'board', 'page_samples.json');
const OUT_ACTS = path.join(FIX, 'acts', 'worker_samples.json');
const CHECK = process.argv.includes('--check');

// the Worker next to this checkout (a git worktree sits deeper: walk up until a sibling candlelight-server appears)
function findWorker(){
  if (process.env.WORKER) return path.resolve(process.env.WORKER);
  let d = ROOT;
  for (let i = 0; i < 6; i++){
    const f = path.join(path.dirname(d), 'candlelight-server', 'worker.js');
    if (fs.existsSync(f)) return f;
    d = path.dirname(d);
  }
  throw new Error('worker.js not found: set WORKER=<candlelight-server/worker.js>');
}
const WORKER = findWorker();

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
const DUPLICATES_OK = new Set(['function clamp(v,a,b){']);   // identical copies on the page
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
const ANCHORS = ['function clamp(v,a,b){', 'var RULES_V = ', 'var MAX_ROUND = ', 'function maxRound(', 'function radOfType(',
  'function TY(', 'var ENGAGE = ', 'function gx(u)', 'function gz(u)', 'function dist2(', 'function sqOf(', 'function sqModels(',
  'function sqAlive(', 'function sqList(', 'function sqCenter(', 'function mEdge(', 'function sqEdge(', 'function realFoes(',
  'function engagedWith(', 'function isEngaged(', 'var OBJ = [', 'function objOC(', 'function objCtl(', 'function refreshObj(',
  'function boardState('];
const PIECES = ANCHORS.map(cut);
// the lab: the page's code in its own closure over a world the sampler sets; TYPES comes from the live page
const LAB = '(function(){ "use strict";\n' +
  'var units = [], SQ = {}, SQ_ORDER = [], TYPES = window.BT.TYPES;\n' +
  'var G = { turn: 0, round: 1, phase: "cmd", over: false, vp: [], goal: "obj", rounds: 5, teams: 2, players: [], freeFire: false };\n' +
  PIECES.map(p => '// page line ' + p.line + '\n' + p.text).join('\n') + '\n' +
  'return { set: function(w){ units = w.units; SQ = w.SQ; SQ_ORDER = w.order; OBJ = w.obj; G = w.G; },\n' +
  '  board: function(){ return boardState(); } };\n})()';

// ---------- what runs in the page ----------
// args: { lab, worlds, flags, tenths, strings, oracle, live }
function pageRun(args){
  var BT = window.BT, L = (0, eval)(args.lab), out = {};
  // a fixture world as the page holds it: positions in inches, drawn x/z apart from the rules gx/gz on some models,
  // false flags either false or missing
  function build(W){
    var SQ = {}, order = [];
    W.squads.forEach(function(r){ var s = { id: r[0], k: r[1], side: r[2], pl: r[3], n0: r[4] };
      args.flags.forEach(function(f, b){ if (r[5] & (1 << b)) s[f] = true; else if (r[6] & (1 << b)) s[f] = false; });
      SQ[s.id] = s; order.push(s.id); });
    var units = W.units.map(function(r){ var s = SQ[r[1]], u = { id: r[0], sq: r[1], t: s.k, side: s.side, pl: s.pl, hp: r[2] };
      if (r[5]){ u.gx = r[3] / 1000; u.gz = r[4] / 1000; u.x = (r[3] + r[5]) / 1000; u.z = (r[4] - r[5]) / 1000; }
      else { u.x = r[3] / 1000; u.z = r[4] / 1000; }
      return u; });
    var obj = W.objs.map(function(o){ return { n: o[0], x: o[1] / 1000, z: o[2] / 1000, owner: -1 }; });
    var G = { turn: W.turn, round: W.round, phase: W.phase, over: W.over, vp: W.vp.slice(), goal: W.goal, rounds: W.rounds,
      teams: W.teams, freeFire: W.ff, players: W.seats.map(function(p, k){ var P = { id: k, team: p[0], nm: 'P' + k };
        if (p[1] >= 0) P.cp = p[1]; return P; }) };
    return { units: units, SQ: SQ, order: order, obj: obj, G: G };
  }
  out.worlds = args.worlds.map(function(W){ L.set(build(W)); return JSON.stringify(L.board()); });

  // +(mi/1000).toFixed(1) as tenths (Math.round of a one-decimal double times ten is exact; -0 prints as 0)
  var t = [], mi;
  for (mi = args.tenths.from; mi <= args.tenths.to; mi++) t.push(Math.round(+(mi / 1000).toFixed(1) * 10));
  out.tenths = t.join(',');
  out.tenths_extra = args.tenths.extra.map(function(m){ return [m, Math.round(+(m / 1000).toFixed(1) * 10)]; });
  out.strings = args.strings.map(function(s){ return [s, JSON.stringify(s)]; });
  out.oracle = args.oracle.map(function(b){ return JSON.stringify(b); });

  // live check: the cut boardState over a started bot match equals the page's own BT.board()
  var G = BT.G, i, live = [];
  BT.clock(false); BT.quit(); BT.seed(5); BT.size(48);
  G.mode = 'pvp'; G.teams = 2; G.perTeam = 1; G.budget = 5000; G.freeFire = false; G.goal = 'obj'; G.rounds = 5;
  BT.mkPlayers();
  var L0 = [], L1 = [];
  for (i = 0; i < BT.TYPES.length; i++){ var k = BT.TYPES[i].k;
    L0.push(args.live[0].indexOf(k) >= 0 ? 1 : 0); L1.push(args.live[1].indexOf(k) >= 0 ? 1 : 0); }
  BT.setList(0, L0); BT.setList(1, L1);
  BT.players().forEach(function(P, k){ P.bot = true; var d = BT.autoDep(k); BT.setDep(k, d[0], d[1]); });
  var x = 0x2545F491;
  var dice = function(n){ var q = [], j; for (j = 0; j < n; j++){ x ^= x << 13; x >>>= 0; x ^= x >>> 17; x ^= x << 5; x >>>= 0; q.push(1 + x % 6); } return q; };
  BT.dice(dice(4000));
  BT.start();
  var check = function(step){
    var live_w = { units: BT.units, SQ: {}, order: [], obj: BT.obj(), G: G };
    BT.squads().forEach(function(s){ live_w.SQ[s.id] = s; live_w.order.push(s.id); });
    L.set(live_w);
    var a = JSON.stringify(L.board()), b = JSON.stringify(BT.board());
    live.push({ step: step, same: a === b, units: BT.units.length, squads: BT.squads().length, round: G.round, phase: G.phase });
  };
  check(0);
  for (i = 1; i <= 160 && !G.over; i++){
    BT.botStep(); BT.tick(1 / 30, 4);
    if (i % 40 === 0) check(i);
  }
  BT.quit();
  out.live = live;
  return out;
}

// ---------- the plan (seeded, Node side) ----------
function mulberry32(a){ return function(){ a |= 0; a = a + 0x6D2B79F5 | 0; var t = Math.imul(a ^ a >>> 15, 1 | a);
  t = t + Math.imul(t ^ t >>> 7, 61 | t) ^ t; return ((t ^ t >>> 14) >>> 0) / 4294967296; }; }
const FLAGS = ['moved', 'adv', 'fell', 'shot', 'chDone', 'charged', 'shaken'];
const PH = ['cmd', 'move', 'shoot', 'charge', 'fight'];

function makeWorlds(types){
  const rnd = mulberry32(20261008), ri = (lo, hi) => lo + Math.floor(rnd() * (hi - lo + 1)), pick = a => a[ri(0, a.length - 1)];
  const open = types.filter(T => !T.sec && !T.lk);
  const TY = k => types.find(T => T.k === k), rOf = k => (TY(k).r || 0.8);
  const EDGES = [50, -50, 49, -49, 51, -51];
  const worlds = [];
  let rejected = 0;
  while (worlds.length < 36){
    const wi = worlds.length, teams = wi === 0 ? 1 : ri(2, 4), per = ri(1, 2), grid = wi % 2 === 0;
    const seats = [];
    for (let t = 0; t < teams; t++) for (let k = 0; k < per; k++) seats.push([t, rnd() < 0.15 ? -1 : ri(0, 4)]);
    const goal = wi % 4 === 3 ? 'kill' : 'obj';
    const W = { name: 'w' + wi, teams, goal, rounds: pick([0, 2, 3, 4, 5, 7, 10, 12]), ff: rnd() < 0.2, turn: ri(0, teams - 1),
      round: ri(1, 6), phase: pick(PH), over: rnd() < 0.15, vp: [], seats, squads: [], units: [], objs: [], tie: [] };
    for (let t = 0; t < teams; t++) W.vp.push(ri(0, 30));
    const nsq = ri(1, 9), centres = [];
    for (let i = 0; i < nsq; i++){
      const T = pick(open), side = i < teams ? i : ri(0, teams - 1), seat = side * per + ri(0, per - 1), id = seat + ':' + i;
      let fl = 0, no = 0;
      for (let b = 0; b < FLAGS.length; b++){ if (rnd() < 0.3) fl |= 1 << b; else if (rnd() < 0.5) no |= 1 << b; }
      W.squads.push([id, T.k, side, seat, T.n, fl, no]);
      const alive = rnd() < 0.15 ? 0 : ri(1, T.n);
      let cx, cz;
      if (centres.length && rnd() < 0.45){ const c = pick(centres); cx = c[0] + ri(-3500, 3500); cz = c[1] + ri(-3500, 3500); }
      else { cx = ri(-40000, 40000); cz = ri(-28000, 28000); }
      centres.push([cx, cz]);
      const spread = Math.round(rOf(T.k) * 2200) + 600;
      for (let j = 0; j < alive; j++){
        let x = cx + ri(-spread, spread), z = cz + ri(-spread, spread);
        if (grid){ x = 10 * Math.round(x / 10); z = 10 * Math.round(z / 10); }
        if (rnd() < 0.2) x = 100 * Math.round(x / 100) + pick(EDGES);
        if (rnd() < 0.2) z = 100 * Math.round(z / 100) + pick(EDGES);
        const drawn = rnd() < 0.25 ? (ri(-900, 900) || 7) : 0;
        W.units.push([id + '.' + j, id, ri(1, TY(T.k).w), x, z, drawn]);
      }
    }
    for (let i = W.units.length - 1; i > 0; i--){ const j = ri(0, i), t = W.units[i]; W.units[i] = W.units[j]; W.units[j] = t; }
    if (goal === 'obj'){
      const no = ri(0, 5);
      for (let i = 0; i < no; i++){
        const base = W.units.length && rnd() < 0.7 ? pick(W.units) : null;
        W.objs.push([i + 1, base ? base[3] + ri(-4200, 4200) : ri(-40000, 40000), base ? base[4] + ri(-4200, 4200) : ri(-28000, 28000)]);
      }
    }
    if (nearThreshold(W, rOf) || nearCentre(W)){ rejected++; continue; }
    worlds.push(W);
  }
  // hand world: single-model squads on every toFixed(1) edge (a lone model's centre is its position on both sides)
  const ek = open[0].k, edgeVals = [0, 1, -1, 49, -49, 50, -50, 51, -51, 250, -250, 350, -350, 1050, -1050, 1150, -1150,
    2675, -2675, 44950, -44950, 89999, -89999];
  const E = { name: 'edges', teams: 2, goal: 'obj', rounds: 5, ff: false, turn: 1, round: 2, phase: 'shoot', over: false, vp: [5, 0],
    seats: [[0, 1], [1, 2]], squads: [], units: [], objs: [], tie: [] };
  edgeVals.forEach((v, i) => { const id = (i % 2) + ':' + i; E.squads.push([id, ek, i % 2, i % 2, 1, 0, 0]);
    E.units.push([id + '.0', id, 1, v, edgeVals[(i * 7 + 3) % edgeVals.length] + 4000 * (i % 3), 0]); });
  edgeVals.slice(0, 8).forEach((v, i) => E.objs.push([i + 1, v, -v]));
  // hand worlds: squad x centres exactly on a toFixed(1) half step (n >= 2): the page's double mean and the port's
  // js_round centre print neighbouring tenths for most of these (R1_PORT_SPEC D6, D7); z is one value per squad (exact)
  const tk = open.find(T => T.n >= 3).k;
  const tieOf = us => us.length > 1 && [3, 4].some(c => { const S = Math.abs(us.reduce((a, u) => a + u[c], 0)), n = us.length;
    return Math.abs((S % (100 * n)) - 50 * n) <= n; });
  const tieW = (name, sets) => { const Wt = { name, teams: 2, goal: 'kill', rounds: 5, ff: false, turn: 0, round: 1, phase: 'move',
    over: false, vp: [0, 0], seats: [[0, 0], [1, 0]], squads: [], units: [], objs: [], tie: [] };
    sets.forEach((xs, i) => { const id = (i % 2) + ':' + i; Wt.squads.push([id, tk, i % 2, i % 2, TY(tk).n, 0, 0]);
      xs.forEach((x, j) => Wt.units.push([id + '.' + j, id, 1, x, 3000 * i + 300, 0]));
      if (tieOf(Wt.units.filter(u => u[1] === id))) Wt.tie.push(id); });
    return Wt; };
  const hand = [];
  hand.push(tieW('ties_a', [[10, 90], [140, 160], [-70, 570], [970, 1130], [930, 1370], [-90, -10], [-160, -140], [1100, 1200]]));
  hand.push(tieW('ties_b', [[-50, 50, 150], [250, 350, 450], [1050, 1150, 1250], [-450, -350, -250], [1000, 1100, 1200]]));
  hand.push(E);
  for (const H of hand){
    if (nearThreshold(H, rOf)) throw new Error('hand world ' + H.name + ' sits on a threshold');
    if (!H.tie.length && nearCentre(H)) throw new Error('hand world ' + H.name + ' has a centre on a half step');
    if (H.tie.length && !nearCentre(H)) throw new Error('tie world ' + H.name + ' has no tie');
    worlds.push(H);
  }
  return { worlds, rejected };
}
// a model within 1e-7" of a page threshold (engagement 1.001", objective reach 3 + r + 0.001"); a squad of two or more
// whose exact mean centre is within 1 MI of a toFixed(1) half step (a lone model's centre is exact on both sides)
function nearThreshold(W, rOf){
  const sq = {}; W.squads.forEach(r => { sq[r[0]] = r; });
  const NEAR = 1e-7;
  for (let i = 0; i < W.units.length; i++){
    const a = W.units[i], sa = sq[a[1]];
    for (let j = i + 1; j < W.units.length; j++){
      const b = W.units[j], sb = sq[b[1]];
      if (sa[2] === sb[2]) continue;
      const e = Math.hypot((a[3] - b[3]) / 1000, (a[4] - b[4]) / 1000) - rOf(sa[1]) - rOf(sb[1]);
      if (Math.abs(e - 1.001) < NEAR) return true;
    }
    for (const o of W.objs){
      const d = Math.hypot(a[3] / 1000 - o[1] / 1000, a[4] / 1000 - o[2] / 1000);
      if (Math.abs(d - (3 + rOf(sa[1]) + 0.001)) < NEAR) return true;
    }
  }
  return false;
}
function nearCentre(W){
  for (const r of W.squads){
    const us = W.units.filter(u => u[1] === r[0]), n = us.length;
    if (n < 2) continue;
    for (const c of [3, 4]){ const S = Math.abs(us.reduce((a, u) => a + u[c], 0)); if (Math.abs((S % (100 * n)) - 50 * n) <= n) return true; }
  }
  return false;
}

// oracle boards for to_json: board0 (the deployment) and the last board (game over, dead models gone) of each recording
function oracleBoards(){
  const out = [];
  for (const f of fs.readdirSync(ORACLE).filter(f => f.endsWith('.json.gz')).sort()){
    const rec = JSON.parse(zlib.gunzipSync(fs.readFileSync(path.join(ORACLE, f))).toString('utf8'));
    const n = rec.boards.length;
    out.push({ scenario: rec.scenario, which: 'board0', b: rec.board0 });
    out.push({ scenario: rec.scenario, which: 'boards[' + (n - 1) + ']', b: rec.boards[n - 1] });
  }
  return out;
}

const STRINGS = ['', 'plain', '0:1.2', 'a"b', 'back\\slash', 'line\nbreak', 'tab\there', '\b\f\r', '\u0001\u001f\u007f',
  'ไทย ทหาร', 'emoji 😀 ok', '  ', '/slash/', '<b>&amp;</b>'];

// ---------- the Worker's sanitiser (Node) ----------
const wsrc = fs.readFileSync(WORKER, 'utf8');
const W_START = '    const raw = body.act && typeof body.act === "object" ? body.act : {};';
const W_END = '    if (!act) return R({ error: "act" }, 400);';
const ws = wsrc.indexOf(W_START), we = wsrc.indexOf(W_END, ws);
if (ws < 0 || we < 0 || wsrc.indexOf(W_START, ws + 1) >= 0) throw new Error('btPost act branch not found once in ' + WORKER);
const W_CUT = wsrc.slice(ws, we);
const W_CLAMP = (/^function clampStr\(s, n\) \{[^\n]*\}$/m.exec(wsrc) || [])[0];
if (!W_CLAMP) throw new Error('clampStr not found in ' + WORKER);
const BT_RULES = +((/^const BT_RULES = (\d+);/m.exec(wsrc) || [])[1] || 0);
const workerSanitize = new Function('body', W_CLAMP + '\n' + W_CUT + '\nreturn act;');
const W_CODES = []; { const re = /raw\.a === "(\w+)"/g; let m; while ((m = re.exec(W_CUT))) W_CODES.push(m[1]); }

const MI = v => 10 * Math.round(v * 100);
// wire act -> core form: to/x/z numbers to MI, every other number must be an integer already
function toCore(a){
  if (a == null) return {};
  const out = {};
  for (const k of Object.keys(a)){
    const v = a[k];
    if (k === 'to' && Array.isArray(v)) out[k] = v.map(q => Array.isArray(q) ? q.map(c => typeof c === 'number' ? MI(c) : c) : q);
    else if ((k === 'x' || k === 'z') && typeof v === 'number') out[k] = MI(v);
    else out[k] = v;
  }
  return out;
}
function ints(v, where){
  if (typeof v === 'number'){ if (!Number.isInteger(v)) throw new Error('non-integer core number in ' + where + ': ' + v); return; }
  if (Array.isArray(v)) v.forEach(x => ints(x, where));
  else if (v && typeof v === 'object') Object.keys(v).forEach(k => ints(v[k], where));
}

function actCases(){
  const d60 = n => Array.from({ length: n }, (_, i) => 1 + (i * 5) % 6);
  const pts = n => Array.from({ length: n }, (_, i) => [i * 1.25 - 20, 3.5 - i * 0.75]);
  const C = [];
  const add = (name, act) => C.push({ name, act });
  // every code, the plain form a client posts
  add('smove to', { a: 'smove', u: '0:1', how: 'move', to: [[1.25, -3.5], [2.5, 0]] });
  add('smove x z (Claude)', { a: 'smove', u: '0:1', how: 'move', x: 12.3, z: -4.5 });
  add('stay', { a: 'stay', u: '1:0' });
  add('skip', { a: 'skip', u: '1:0', ph: 'shoot' });
  add('adv', { a: 'adv', u: '0:2', roll: 4 });
  add('atk', { a: 'atk', u: '0:2', t: '1:0', how: 'shoot', hit: [1, 6, 3] });
  add('wnd', { a: 'wnd', u: '0:2', t: '1:0', wound: [2, 5] });
  add('sav', { a: 'sav', u: '0:2', t: '1:0', save: [3], gtg: 1 });
  add('rr', { a: 'rr', u: '0:2', t: '1:0', v: 5 });
  add('shoot', { a: 'shoot', u: '0:2', t: '1:0', how: 'fight', hit: [6, 6], wound: [4, 1], save: [2] });
  add('shock', { a: 'shock', u: '1:3', roll: [3, 4], brave: 1 });
  add('rez', { a: 'rez', u: '1:3', roll: [5, 6, 1] });
  add('chg', { a: 'chg', u: '0:1', t: '1:2' });
  add('ow', { a: 'ow', u: '0:1', t: '1:2', use: 1 });
  add('chr', { a: 'chr', u: '0:1', t: '1:2', roll: [2, 5] });
  add('chr rr', { a: 'chr', u: '0:1', t: '1:2', roll: [4, 4], rr: 1 });
  add('chr keep', { a: 'chr', u: '0:1', t: '1:2', roll: [1, 2], keep: 1 });
  add('cmove', { a: 'cmove', u: '0:1', t: '1:2', to: [[10.01, -2.37], [-0.03, 0.05]] });
  add('gren', { a: 'gren', u: '0:4', t: '1:2', roll: [1, 2, 3, 4, 5, 6] });
  add('heal', { a: 'heal', u: '0:5', t: '0:1', roll: 6 });
  add('done', { a: 'done', ph: 'move', pid: 'A' });
  add('endph', { a: 'endph', ph: 'charge' });
  add('legacy move', { a: 'move', u: '0:0', x: 1.5, z: -2 });
  add('legacy endturn', { a: 'endturn', ph: 'move', u: 'x' });
  // caps
  add('atk 61 dice', { a: 'atk', u: '0:2', t: '1:0', hit: d60(61) });
  add('shoot 70/61/65 dice', { a: 'shoot', u: '0:2', t: '1:0', hit: d60(70), wound: d60(61), save: d60(65) });
  add('wnd 60 dice', { a: 'wnd', u: '0:2', t: '1:0', wound: d60(60) });
  add('smove 41 points', { a: 'smove', u: '0:1', how: 'adv', to: pts(41) });
  add('cmove 45 points', { a: 'cmove', u: '0:1', t: '1:2', to: pts(45) });
  add('shock 5 dice', { a: 'shock', u: '1:3', roll: [1, 2, 3, 4, 5] });
  add('chr 3 dice', { a: 'chr', u: '0:1', t: '1:2', roll: [6, 5, 4] });
  add('gren 8 dice', { a: 'gren', u: '0:4', t: '1:2', roll: [6, 5, 4, 3, 2, 1, 6, 6] });
  add('rez 12 dice', { a: 'rez', u: '1:3', roll: d60(12) });
  add('id 21 chars', { a: 'stay', u: 'abcdefghijklmnopqrstu' });
  add('id 25 Thai chars', { a: 'chg', u: 'กขคฆงจฉชซฌญฎฏฐฑฒณดตถทธนบป', t: '1:0' });
  add('id astral, no split', { a: 'stay', u: 'abcdefghijklmnopqr😀z' });
  add('coords clamp', { a: 'smove', u: '0:1', to: [[10000, -12345.678], [9999.004, -9998.996], [-0.004, 0.005]] });
  add('x z clamp', { a: 'smove', u: '0:1', x: 99999, z: -10000.5 });
  // defaults and JS conversions the core form mirrors
  add('dice values', { a: 'atk', u: '0:2', t: '1:0', hit: [0, 7, -2, 3, null, 'x', true, false, {}, [], 6, 1] });
  add('one values', { a: 'adv', u: '0:2', roll: 0 });
  add('one 9', { a: 'heal', u: '0:5', t: '0:1', roll: 9 });
  add('one -3', { a: 'rr', u: '0:2', t: '1:0', v: -3 });
  add('one null', { a: 'adv', u: '0:2', roll: null });
  add('one missing', { a: 'heal', u: '0:5', t: '0:1' });
  add('one bool', { a: 'rr', u: '0:2', t: '1:0', v: true });
  add('one string', { a: 'adv', u: '0:2', roll: 'six' });
  add('dice not array', { a: 'wnd', u: '0:2', t: '1:0', wound: 5 });
  add('dice missing', { a: 'sav', u: '0:2', t: '1:0' });
  add('ids of other types', { a: 'chg', u: 12345, t: true });
  add('ids null and object', { a: 'ow', u: null, t: {}, use: 0 });
  add('id array', { a: 'stay', u: [1, [2, 3], null, 'x'] });
  add('id false and 0', { a: 'chg', u: false, t: 0 });
  add('ids missing', { a: 'atk', hit: [3] });
  add('how bad', { a: 'atk', u: '0:2', t: '1:0', how: 'melee', hit: [2] });
  add('how ow', { a: 'atk', u: '0:2', t: '1:0', how: 'ow', hit: [6] });
  add('how number', { a: 'shoot', u: '0:2', t: '1:0', how: 5 });
  add('smove how fb', { a: 'smove', u: '0:1', how: 'fb', to: [[0, 0]] });
  add('smove how bad', { a: 'smove', u: '0:1', how: 'run', to: [] });
  add('smove empty to', { a: 'smove', u: '0:1', to: [] });
  add('smove to not array', { a: 'smove', u: '0:1', to: 'nope', x: 3, z: 4 });
  add('smove to object', { a: 'smove', u: '0:1', to: { 0: [1, 2] }, x: -3.333 });
  add('smove x only', { a: 'smove', u: '0:1', x: 12.3 });
  add('smove nothing', { a: 'smove', u: '0:1' });
  add('smove x bool z null', { a: 'smove', u: '0:1', x: true, z: null });
  add('points odd shapes', { a: 'cmove', u: '0:1', t: '1:2', to: [[5], [], null, {}, 'p', [true, false], [1, 2, 3], [-0.004, -0.006]] });
  add('cmove to not array', { a: 'cmove', u: '0:1', t: '1:2', to: { a: 1 } });
  add('ph bad', { a: 'skip', u: '1:0', ph: 'deploy' });
  add('ph upper', { a: 'endph', ph: 'MOVE' });
  add('ph null', { a: 'done', ph: null, pid: 'b9' });
  add('ph number', { a: 'skip', u: '1:0', ph: 3 });
  add('ph fight', { a: 'endph', ph: 'fight' });
  add('ph cmd', { a: 'done', ph: 'cmd' });
  add('truthy 1', { a: 'sav', u: '0:2', t: '1:0', save: [4], gtg: 1 });
  add('truthy -1', { a: 'ow', u: '0:1', t: '1:2', use: -1 });
  add('truthy string', { a: 'shock', u: '1:3', roll: [1], brave: 'yes' });
  add('truthy "0"', { a: 'sav', u: '0:2', t: '1:0', gtg: '0' });
  add('falsy ""', { a: 'shock', u: '1:3', roll: [1], brave: '' });
  add('truthy []', { a: 'ow', u: '0:1', t: '1:2', use: [] });
  add('truthy {}', { a: 'chr', u: '0:1', t: '1:2', roll: [3, 3], rr: {}, keep: 0 });
  add('falsy null', { a: 'chr', u: '0:1', t: '1:2', roll: [3, 3], rr: null, keep: false });
  add('truthy true', { a: 'chr', u: '0:1', t: '1:2', roll: [3, 3], keep: true });
  // extra fields are dropped; the core keeps a String / int pid, never seq or ts
  add('extra fields', { a: 'atk', u: '0:2', t: '1:0', hit: [5], x: 3, seq: 99, ts: 123456, pid: 'A', junk: { y: 1 } });
  add('pid int', { a: 'stay', u: '0:1', pid: 7 });
  add('pid bool dropped', { a: 'stay', u: '0:1', pid: true });
  // refused like HTTP 400
  add('unknown code', { a: 'fly', u: '0:1' });
  add('code upper', { a: 'SMOVE', u: '0:1', x: 1, z: 1 });
  add('code number', { a: 5 });
  add('no code', { u: '0:1' });
  add('room action', { a: 'board' });
  add('server-made state', { a: 'state', state: 'play' });
  add('server-made join', { a: 'join', nm: 'x' });
  add('server-made owner', { a: 'owner' });
  // acts the page really sent: the first three of each code over the oracle recordings, with the pid page B saw (§6)
  const per = {};
  for (const f of fs.readdirSync(ORACLE).filter(f => f.endsWith('.json.gz')).sort()){
    const rec = JSON.parse(zlib.gunzipSync(fs.readFileSync(path.join(ORACLE, f))).toString('utf8'));
    rec.acts.forEach((a, i) => { per[a.a] = per[a.a] || 0; if (per[a.a] < 3){ per[a.a]++;
      add('oracle ' + a.a + ' (' + rec.scenario.slice(0, 24) + ' #' + i + ')', Object.assign({}, a, { pid: 'A' })); } });
  }
  if (Object.keys(per).length !== 19) throw new Error('the oracle recordings hold ' + Object.keys(per).length + ' codes, not 19');
  return C.map(c => {
    const out = workerSanitize({ act: c.act });
    const core = toCore(c.act), want = toCore(out);
    if (out && (typeof core.pid === 'string' || Number.isInteger(core.pid))) want.pid = core.pid;
    ints(core, c.name); ints(want, c.name);
    return { name: c.name, wire: c.act, out: out, core: core, want: want, want_keys: Object.keys(want) };
  });
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
  const { chromium } = loadPlaywright();
  const browser = await chromium.launch({ executablePath: process.env.CHROMIUM_PATH || undefined, args: ['--no-sandbox'] });
  const orc = oracleBoards();
  const tenths = { from: -2600, to: 2600, extra: [] };
  for (let k = 0; k <= 180; k += 7) [k * 1000 + 50, k * 1000 + 150, k * 1000 + 950, k * 1000 + 49, k * 1000 + 51].forEach(m => tenths.extra.push(m, -m));
  let res, plan;
  try {
    const p = await browser.newPage({ viewport: { width: 480, height: 320 } });
    const errs = []; p.on('pageerror', e => errs.push(String(e.stack || e).slice(0, 400)));
    await p.goto('file://' + PAGE);
    await p.waitForFunction('window.BT && window.BT.G && window.BT.TYPES');
    const types = await p.evaluate(() => JSON.parse(JSON.stringify(window.BT.TYPES)));
    plan = makeWorlds(types);
    const open = types.filter(T => !T.sec && !T.lk), liveKeys = [open.slice(0, 3).map(T => T.k), open.slice(3, 6).map(T => T.k)];
    res = await p.evaluate(pageRun, { lab: LAB, worlds: plan.worlds, flags: FLAGS, tenths, strings: STRINGS,
      oracle: orc.map(o => o.b), live: liveKeys });
    if (errs.length) throw new Error('page errors:\n' + errs.join('\n'));
  } finally { await browser.close(); }
  const bad = res.live.filter(x => !x.same);
  if (bad.length) throw new Error('the cut boardState differs from the live page: ' + JSON.stringify(bad));
  const acts = actCases();

  const headB = { about: 'generated by godot/tools/record_board_acts.js — do not edit; world positions are MI ints, json is the page\'s JSON.stringify(boardState()) (x/z in inches to one decimal)',
    page: { app_ver: APP_VER, rules_v: RULES_V, functions: PIECES.map(p => p.anchor.replace(/^(function |var )/, '').replace(/[ ({=[].*$/, '') + '@' + p.line) },
    flags: FLAGS, rejected_worlds: plan.rejected, live_check: res.live };
  const bodyB = {
    tenths: { from: tenths.from, to: tenths.to, t: res.tenths, extra: res.tenths_extra },
    strings: res.strings,
    worlds: plan.worlds.map((W, i) => Object.assign({}, W, { json: res.worlds[i] })),
    oracle: orc.map((o, i) => ({ scenario: o.scenario, which: o.which, json: res.oracle[i] })),
  };
  const headA = { about: 'generated by godot/tools/record_board_acts.js — do not edit; wire = the act a client posts (inches), out = the Worker\'s btPost answer (null = HTTP 400), core/want = the same in the core form (MI ints), want_keys = the answer\'s key order',
    worker: { bt_rules: BT_RULES, cut_sha1: crypto.createHash('sha1').update(W_CLAMP + '\n' + W_CUT).digest('hex').slice(0, 16), codes: W_CODES } };
  const files = [[OUT_BOARD, serialize(headB, bodyB)], [OUT_ACTS, serialize(headA, { cases: acts })]];
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
  console.log('worlds ' + plan.worlds.length + ' (' + plan.rejected + ' redrawn near a threshold), live checks ' + res.live.length +
    ', oracle boards ' + orc.length + ', act cases ' + acts.length + ' (' + acts.filter(c => !c.out).length + ' refused), worker codes ' + W_CODES.length);
  if (diff) process.exit(1);
})().catch(e => { console.error(e.stack || e); process.exit(1); });
