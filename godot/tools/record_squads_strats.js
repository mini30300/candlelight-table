#!/usr/bin/env node
// record_squads_strats.js — sample the page's squad and stratagem functions into JSON fixtures for the Godot port
// (core/battle/squads.gd BtSquads, core/battle/strats.gd BtStrats; R1_PORT_SPEC §1.4 and §1.8). Read-only on the page.
//
//   node godot/tools/record_squads_strats.js            write the two fixtures
//   node godot/tools/record_squads_strats.js --check    re-run and fail unless the files are byte-identical
// Environment: PAGE=<battle-table.html>  CHROMIUM_PATH=<chrome>  NODE_PATH or tests/node_modules for playwright.
//
// The functions live inside the page's game IIFE, so their source is cut from the page text by name and evaluated in the
// page's own browser (Chromium V8) next to a hand-built world (units, SQ, SQ_ORDER, G, the live BT.TYPES). One live
// cross-check proves the cut source is the running code: BT.place (which calls the page's own formation) on a started
// match must give byte-identical slots. Worlds and operation lists come from a fixed seed, so a re-run is identical.
//
// Outputs:
//   godot/tests/unit/fixtures/squads/page_samples.json   radOfType, canTarget, sqCenter, sqDist, sqEdge, foesOf, realFoes,
//                                                         engagedWith, isEngaged, sqHalf, formation
//   godot/tests/unit/fixtures/strats/page_samples.json   stratKey, canStrat, useStrat (operation sequences)
'use strict';
const fs = require('fs'), path = require('path');

const ROOT = path.resolve(__dirname, '..', '..');
const PAGE = path.resolve(process.env.PAGE || path.join(ROOT, 'app/src/main/assets/battle-table.html'));
const FIX = path.join(ROOT, 'godot/tests/unit/fixtures');
const CHECK = process.argv.includes('--check');

function loadPlaywright(){
  try { return require('playwright'); }
  catch (e) { return require(path.join(ROOT, 'tests/node_modules/playwright')); }
}

const src = fs.readFileSync(PAGE, 'utf8');
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
// `var NAME = <object literal>;` on one statement
function cutVar(name){
  const re = new RegExp('^var ' + name + ' = ', 'm'), m = re.exec(src);
  if (!m) throw new Error('var not found on the page: ' + name);
  const end = src.indexOf(';', m.index);
  return { name, line: lineOf(m.index), text: src.slice(m.index, end + 1) };
}

const FUNCS = ['gx', 'gz', 'dist2', 'radOfType', 'TY', 'sqModels', 'sqAlive', 'sqList', 'sqCenter', 'sqDist', 'mEdge',
  'sqEdge', 'foesOf', 'realFoes', 'engagedWith', 'isEngaged', 'sqHalf', 'canTarget', 'formation', 'stratKey', 'canStrat',
  'useStrat'];
const cuts = FUNCS.map(cutFunction).concat([cutVar('STRATS')]);
const engage = (/^var ENGAGE = ([0-9.]+);/m.exec(src) || [])[1];
if (engage == null) throw new Error('ENGAGE not found');

// ---------- what runs in the page ----------
// args: { code, engage, plan } — plan holds the worlds, formation cases and strat sequences made in Node
function pageRun(args){
  var BT = window.BT;
  // the sandbox: the cut page functions over our own world (no page state is touched)
  var factory = new Function('TYPES', 'ENGAGE',
    'var units = [], SQ = {}, SQ_ORDER = [], G = { freeFire:false, round:1, turn:0, phase:"cmd", over:false, used:{}, players:[] };\n' +
    'var LOG = []; function say(t){ LOG.push(String(t)); } function esc(s){ return String(s); }\n' +
    args.code + '\n' +
    'return { setWorld:function(us, sqs, ff){ units.length = 0; SQ = {}; SQ_ORDER = [];\n' +
    '    sqs.forEach(function(s){ SQ[s.id] = s; SQ_ORDER.push(s.id); }); us.forEach(function(u){ units.push(u); }); G.freeFire = !!ff; },\n' +
    '  setG:function(o){ for (var k in o) G[k] = o[k]; }, G:function(){ return G; }, log:function(){ return LOG; },\n' +
    '  f:{ radOfType:radOfType, TY:TY, sqCenter:sqCenter, sqDist:sqDist, sqEdge:sqEdge, foesOf:foesOf, realFoes:realFoes,\n' +
    '      engagedWith:engagedWith, isEngaged:isEngaged, sqHalf:sqHalf, canTarget:canTarget, formation:formation,\n' +
    '      stratKey:stratKey, canStrat:canStrat, useStrat:useStrat, sqList:sqList, STRATS:STRATS } };');
  var S = factory(BT.TYPES, args.engage), F = S.f, plan = args.plan, out = { squads: {}, strats: {} };
  var ids = function(list){ return list.map(function(q){ return q.id; }); };
  var NEAR = 1e-9;

  // radOfType of every datasheet (in MI, the page's value times 1000 rounded: radii are whole tenths of an inch)
  out.squads.radius = BT.TYPES.map(function(T){ return [T.k, Math.round(F.radOfType(T) * 1000)]; });
  out.squads.radius_unknown = Math.round(F.radOfType(F.TY('no-such-unit')) * 1000);

  // worlds
  out.squads.worlds = plan.worlds.map(function(W){
    var res = { squads: [], pairs: [] };
    [false, true].forEach(function(ff){
      var sqs = W.squads.map(function(s){ return { id: s.id, k: s.k, side: s.side, pl: s.pl, n0: s.n0 }; });
      var us = W.units.map(function(u){ return { id: u.id, sq: u.sq, k: u.t, t: u.t, side: u.side, pl: u.pl, hp: u.hp, x: u.x / 1000, z: u.z / 1000 }; });
      S.setWorld(us, sqs, ff);
      sqs.forEach(function(s, i){
        var row = ff ? res.squads[i] : (res.squads[i] = {});
        if (!ff){ var c = F.sqCenter(s); row.cx = c.x; row.cz = c.z; row.half = F.sqHalf(s); row.real = ids(F.realFoes(s));
          row.engaged = ids(F.engagedWith(s)); row.is_engaged = F.isEngaged(s); row.foes = ids(F.foesOf(s)); }
        else row.foes_ff = ids(F.foesOf(s));
      });
      // pairs: [a, b, sqDist, sqEdge, bits] bits 1 canTarget, 2 canTarget (free fire), 4 edge <= 1.001, 8 edge <= 12.001,
      // 16 edge <= 24.001, 32 dist <= 6.001, 64 within 1e-9" of one of those thresholds (compare exactly only when clear)
      sqs.forEach(function(a, i){ sqs.forEach(function(b, j){
        var k = i * sqs.length + j;
        if (ff){ if (F.canTarget(a, b)) res.pairs[k][4] |= 2; return; }
        var d = F.sqDist(a, b), e = F.sqEdge(a, b), bits = 0, L1 = args.engage + 0.001;
        if (F.canTarget(a, b)) bits |= 1;
        if (e <= L1) bits |= 4;
        if (e <= 12 + 0.001) bits |= 8;
        if (e <= 24 + 0.001) bits |= 16;
        if (d <= 6 + 0.001) bits |= 32;
        if (Math.abs(e - L1) < NEAR || Math.abs(e - 12.001) < NEAR || Math.abs(e - 24.001) < NEAR || Math.abs(d - 6.001) < NEAR) bits |= 64;
        res.pairs[k] = [i, j, d, e, bits];
      }); });
    });
    return res;
  });

  // formation: slots relative to the centre in MI, rounded the v10 way (10 MI) in JS with tie flags
  out.squads.formation = plan.formation.map(function(c){
    var sl = F.formation(c.n, c.cx / 1000, c.cz / 1000, c.face, c.r / 1000);
    var grid = function(v, base){ var off = v * 1000 - base, t = off / 10, fl = Math.floor(t);
      return [base + 10 * Math.round(t), Math.abs(t - fl - 0.5) < 1e-6 ? 1 : 0, base + 10 * fl]; };
    // per slot and axis [page value to the 10 MI grid, 1 = the page value sits on a half step (either neighbour is
    // exact), the grid step below]; the raw doubles are not kept
    return { n: c.n, cx: c.cx, cz: c.cz, face: c.face, f: c.f, r: c.r,
      slots: sl.map(function(p){ return [grid(p[0], c.cx), grid(p[1], c.cz)]; }) };
  });

  // live cross-check: a started match, BT.place runs the page's own formation on real squads
  var G = BT.G, i;
  BT.clock(false); BT.quit(); BT.seed(7); BT.size(48);
  G.mode = 'pvp'; G.teams = 2; G.perTeam = 1; G.budget = 2000; G.freeFire = false; G.goal = 'obj'; G.rounds = 5;
  BT.mkPlayers();
  var L0 = [], L1 = [];
  for (i = 0; i < BT.TYPES.length; i++){ L0.push(BT.TYPES[i].k === 'infantry' ? 1 : 0); L1.push(BT.TYPES[i].k === 'heavy' ? 1 : 0); }
  BT.setList(0, L0); BT.setList(1, L1);
  BT.players().forEach(function(P, k){ P.bot = true; var d = BT.autoDep(k); BT.setDep(k, d[0], d[1]); });
  BT.start();
  var live = [];
  [['0:0', 3.21, -4.56, 0], ['0:0', -7.5, 2.25, Math.PI / 2], ['1:0', 10, 10, Math.atan2(0.6, 0.8)], ['1:0', -2.5, -12.75, 2.2]].forEach(function(q){
    var s = BT.sq(q[0]); BT.place(q[0], q[1], q[2], q[3]);
    var got = BT.sqModels(s).map(function(m){ return [m.x, m.z]; });
    var cut = F.formation(got.length, q[1], q[2], q[3] || 0, F.radOfType(F.TY(s.k)));
    live.push({ id: q[0], n: got.length, same: JSON.stringify(got) === JSON.stringify(cut) });
  });
  BT.quit();
  out.live = live;

  // strats: operation sequences over G.players / G.used
  out.strats.costs = Object.keys(F.STRATS).map(function(k){ return [k, F.STRATS[k].cp]; });
  out.strats.seqs = plan.strats.map(function(seq){
    S.setG({ round: seq.g.round, turn: seq.g.turn, phase: seq.g.phase, over: false, used: {},
      players: seq.seats.map(function(p, k){ return { id: k, team: p.team, cp: p.cp, nm: 'P' + k }; }) });
    var nUsed = 0, seen = [];
    var steps = seq.ops.map(function(op){
      var g = S.G(), r = null;
      if (op[0] === 'use') r = F.useStrat(op[1], op[2]);
      else if (op[0] === 'can') r = F.canStrat(op[1], op[2]);
      else if (op[0] === 'key') r = F.stratKey(op[1], op[2]);
      else if (op[0] === 'set') S.setG(op[1]);
      else if (op[0] === 'cp') g.players[op[1]].cp = op[2];
      // [result, cp per seat, the lock key this step added or ""]
      var keys = Object.keys(g.used), add = keys.length > nUsed ? keys.filter(function(x){ return seen.indexOf(x) < 0; }) : [];
      nUsed = keys.length; seen = keys.slice();
      if (add.length > 1) throw new Error('one step added two locks');
      return [r, g.players.map(function(p){ return p.cp; }), add.length ? add[0] : ''];
    });
    return { g: seq.g, seats: seq.seats, ops: seq.ops, steps: steps, used: Object.keys(S.G().used).sort() };
  });
  return out;
}

// ---------- the plan (seeded, Node side) ----------
function mulberry32(a){ return function(){ a |= 0; a = a + 0x6D2B79F5 | 0; var t = Math.imul(a ^ a >>> 15, 1 | a);
  t = t + Math.imul(t ^ t >>> 7, 61 | t) ^ t; return ((t ^ t >>> 14) >>> 0) / 4294967296; }; }
function makePlan(types){
  const rnd = mulberry32(20261007), ri = (lo, hi) => lo + Math.floor(rnd() * (hi - lo + 1));
  const open = types.filter(T => !T.sec && !T.lk);
  // a spread of base radii: every distinct r once, then random ones
  const byR = {}; open.forEach(T => { const r = T.r || 0.8; if (!byR[r]) byR[r] = T; });
  const pool = Object.values(byR);
  const grid10 = v => 10 * Math.round(v / 10);
  const worlds = [];
  for (let w = 0; w < 30; w++){
    const nsq = ri(2, 7), sides = ri(2, 3), spread = w < 18 ? 6000 : 14000, squads = [], units = [];
    for (let i = 0; i < nsq; i++){
      const T = (i + w) % 3 === 0 ? pool[ri(0, pool.length - 1)] : open[ri(0, open.length - 1)];
      const side = i < sides ? i : ri(0, sides - 1), id = side + ':' + i;
      const alive = rnd() < 0.12 ? 0 : ri(1, T.n), cx = grid10(ri(-spread, spread)), cz = grid10(ri(-spread, spread));
      squads.push({ id, k: T.k, side, pl: side, n0: T.n });
      for (let j = 0; j < alive; j++){
        const hp = ri(1, T.w);
        units.push({ id: id + '.' + j, sq: id, t: T.k, side, pl: side, hp, x: cx + grid10(ri(-2600, 2600)), z: cz + grid10(ri(-2600, 2600)) });
      }
    }
    for (let i = units.length - 1; i > 0; i--){ const j = ri(0, i); const t = units[i]; units[i] = units[j]; units[j] = t; }   // units order is not squad order
    worlds.push({ squads, units });
  }
  const faces = [[0, [0, 1000]], [Math.PI / 2, [1000, 0]], [Math.PI, [0, -1000]], [-Math.PI / 2, [-1000, 0]],
    [Math.atan2(0.6, 0.8), [600, 800]], [Math.atan2(-0.8, 0.6), [-800, 600]], [Math.atan2(-0.6, -0.8), [-600, -800]]];
  const formation = [];
  const radii = [800, 1000, 1300, 1800, 2600, 8000];
  for (let n = 0; n <= 12; n++) faces.forEach((F, fi) => {
    const r = radii[(n + fi) % radii.length], c = (n + fi) % 2 ? [12340, -5670] : [0, 0];
    formation.push({ n, cx: c[0], cz: c[1], face: F[0], f: F[1], r });
  });
  [20, 10, 5].forEach(n => formation.push({ n, cx: -30000, cz: 20010, face: 0, f: [0, 1000], r: 800 }));
  // strats: one hand sequence (the locks), then seeded random ones
  const K = ['rr', 'ow', 'gtg', 'gren', 'brave'], PH = ['cmd', 'move', 'shoot', 'charge', 'fight'];
  const strats = [{ g: { round: 1, turn: 0, phase: 'shoot' }, seats: [{ team: 0, cp: 2 }, { team: 0, cp: 1 }, { team: 1, cp: 0 }, { team: 1, cp: 3 }],
    ops: [['key', 'rr', 0], ['key', 'brave', 1], ['can', 'rr', 0], ['use', 'rr', 0], ['can', 'rr', 1], ['use', 'rr', 1], ['use', 'gtg', 1],
      ['use', 'rr', 2], ['use', 'rr', 3], ['use', 'rr', 3], ['use', 'brave', 0], ['use', 'brave', 0], ['set', { phase: 'charge' }],
      ['can', 'rr', 0], ['use', 'rr', 0], ['can', 'brave', 1], ['use', 'brave', 1], ['set', { phase: 'fight' }], ['use', 'brave', 3],
      ['set', { turn: 1, phase: 'cmd' }], ['use', 'brave', 3], ['use', 'brave', 2], ['cp', 2, 1], ['use', 'brave', 2], ['use', 'brave', 3],
      ['set', { round: 2, turn: 0 }], ['use', 'brave', 0], ['can', 'ow', 9], ['can', 'ow', -1], ['set', { over: true }], ['can', 'gren', 3],
      ['use', 'gren', 3], ['key', 'gren', 3]] }];
  for (let q = 0; q < 16; q++){
    const ns = ri(1, 8), teams = ri(1, Math.min(4, ns)), seats = [];
    for (let i = 0; i < ns; i++) seats.push({ team: i % teams, cp: ri(0, 3) });
    const ops = [];
    for (let o = 0; o < 36; o++){
      const x = rnd(), k = K[ri(0, K.length - 1)], pi = ri(0, ns - 1);
      if (x < 0.45) ops.push(['use', k, pi]);
      else if (x < 0.65) ops.push(['can', k, pi]);
      else if (x < 0.75) ops.push(['key', k, ri(0, teams - 1)]);
      else if (x < 0.85) ops.push(['set', { phase: PH[ri(0, 4)] }]);
      else if (x < 0.9) ops.push(['set', { turn: ri(0, teams - 1) }]);
      else if (x < 0.93) ops.push(['set', { round: ri(1, 6) }]);
      else ops.push(['cp', pi, ri(0, 4)]);
    }
    if (q % 6 === 5) ops.push(['set', { over: true }], ['use', 'rr', 0], ['can', 'rr', 0]);
    strats.push({ g: { round: ri(1, 5), turn: ri(0, teams - 1), phase: PH[ri(0, 4)] }, seats, ops });
  }
  return { worlds, formation, strats };
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
  let res, plan;
  try {
    const p = await browser.newPage({ viewport: { width: 480, height: 320 } });
    const errs = []; p.on('pageerror', e => errs.push(String(e.stack || e).slice(0, 400)));
    await p.goto('file://' + PAGE);
    await p.waitForFunction('window.BT && window.BT.G && window.BT.TYPES');
    plan = makePlan(await p.evaluate(() => JSON.parse(JSON.stringify(window.BT.TYPES))));
    res = await p.evaluate(pageRun, { code: cuts.map(c => c.text).join('\n'), engage: +engage, plan });
    if (errs.length) throw new Error('page errors:\n' + errs.join('\n'));
  } finally { await browser.close(); }
  const bad = res.live.filter(x => !x.same);
  if (bad.length) throw new Error('the cut formation differs from the live page: ' + JSON.stringify(bad));
  const appVer = (/var APP_VER = '([^']+)'/.exec(src) || [])[1], rulesV = +((/var RULES_V = (\d+)/.exec(src) || [])[1] || 0);
  const head = { about: 'generated by godot/tools/record_squads_strats.js — do not edit; sampled distances, edges and centres are the page\'s raw doubles (inches); radius_mi, worlds_in and formation slots are MI ints',
    page: { app_ver: appVer, rules_v: rulesV, engage: +engage, functions: cuts.map(c => c.name + '@' + c.line) }, live_check: res.live };
  const files = [
    [path.join(FIX, 'squads', 'page_samples.json'), serialize(head, { radius_mi: res.squads.radius, radius_unknown_mi: res.squads.radius_unknown,
      worlds_in: plan.worlds, worlds: res.squads.worlds, formation: res.squads.formation })],
    [path.join(FIX, 'strats', 'page_samples.json'), serialize(head, { costs: res.strats.costs, seqs: res.strats.seqs })],
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
  const W = res.squads.worlds, pairs = W.reduce((a, w) => a + w.pairs.length, 0), cnt = b => W.reduce((a, w) => a + w.pairs.filter(p => p[4] & b).length, 0);
  console.log('worlds ' + W.length + ', pairs ' + pairs + ' (engaged ' + cnt(4) + ', in 12" ' + cnt(8) + ', aura ' + cnt(32) + ', near ' + cnt(64) + ')' +
    ', formation cases ' + res.squads.formation.length + ', strat sequences ' + res.strats.seqs.length + ', live check ' + res.live.length + ' same');
  if (diff) process.exit(1);
})().catch(e => { console.error(e.stack || e); process.exit(1); });
