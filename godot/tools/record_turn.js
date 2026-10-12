#!/usr/bin/env node
// record_turn.js — sample the page's turn and phase functions into a JSON fixture for the Godot port
// (core/battle/turn.gd BtTurn, R1_PORT_SPEC §1.12). Read-only on the page.
//
//   node godot/tools/record_turn.js            write the fixture
//   node godot/tools/record_turn.js --check    re-run and fail unless the file is byte-identical
// Environment: PAGE=<battle-table.html>  CHROMIUM_PATH=<chrome>  NODE_PATH or tests/node_modules for playwright.
//
// As tools/record_pend.js: the functions are cut from the page text by name and evaluated in the page's own browser
// next to a hand-built world (units, SQ, SQ_ORDER, PEND, FALLEN, G with players, the live BT.TYPES). Log, sound, clock,
// board push and paint are stubbed. In startTurn windTurn and spawnFrom are recorders (no wind bodies are planted, so
// windTurn would do nothing; spawn positions are tested in test_abilities.gd), in endTurn startTurn and endRoundCheck
// are recorders, in endRoundCheck finish is a recorder. Worlds come from a fixed seed, so a re-run is byte-identical.
//
// Output: godot/tests/unit/fixtures/turn/page_samples.json
//   start_turn   world -> every original squad's flags and shields, the PEND entries, seats' cp/done, the spawn calls
//   fights       world (phase fight) -> startFight's order, fightTarget of every living squad
//   end_turn     world -> the turn and round after, and which of startTurn / endRoundCheck ran
//   end_round    world (vp, units, wind bodies) -> the team finish() got (-1 = draw) and the round after
// Positions are MI ints on the 10 MI grid (the page gets inches = MI / 1000).
'use strict';
const fs = require('fs'), path = require('path');

const ROOT = path.resolve(__dirname, '..', '..');
const PAGE = path.resolve(process.env.PAGE || path.join(ROOT, 'app/src/main/assets/battle-table.html'));
const OUT = path.join(ROOT, 'godot/tests/unit/fixtures/turn/page_samples.json');
const CHECK = process.argv.includes('--check');

function loadPlaywright(){
  try { return require('playwright'); }
  catch (e) { return require(path.join(ROOT, 'tests/node_modules/playwright')); }
}

const src = fs.readFileSync(PAGE, 'utf8');
function lineOf(i){ return src.slice(0, i).split('\n').length; }

// the full text of `function NAME(...){ ... }` (first declaration at the start of a line), as in record_pend.js
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
function num(re, what){ const m = re.exec(src); if (!m) throw new Error(what + ' not found on the page'); return m.slice(1).map(Number); }

const FUNCS = ['clamp', 'gx', 'gz', 'dist2', 'radOfType', 'TY', 'maxRound', 'sqById', 'sqModels', 'sqAlive', 'sqList',
  'sqDist', 'mEdge', 'sqEdge', 'realFoes', 'engagedWith', 'isEngaged', 'sqHalf', 'inAura', 'resetSq', 'teamPlayers',
  'liveOf', 'mkPend', 'startTurn', 'startFight', 'fightTarget', 'endTurn', 'endRoundCheck'];
const cuts = FUNCS.map(cutFunction);
const C = {};
[C.ENGAGE] = num(/^var ENGAGE = ([0-9.]+);/m, 'ENGAGE');
[C.AURA_R] = num(/^var AURA_R = ([0-9.]+);/m, 'AURA_R');
[C.REZ_AURA] = num(/REZ_AURA = ([0-9.]+);/m, 'REZ_AURA');
[C.MAX_ROUND, C.KILL_ROUNDS] = num(/^var MAX_ROUND = (\d+), KILL_ROUNDS = (\d+);/m, 'MAX_ROUND');

// ---------- what runs in the page ----------
function pageRun(args){
  var BT = window.BT, C = args.C;
  var factory = new Function('TYPES', 'C',
    'var units = [], SQ = {}, SQ_ORDER = [], PEND = [], FALLEN = [], G = { freeFire:false, teams:2, round:1, turn:0, players:[], vp:[], goal:"obj", rounds:5 };\n' +
    'var ENGAGE = C.ENGAGE, AURA_R = C.AURA_R, REZ_AURA = C.REZ_AURA, MAX_ROUND = C.MAX_ROUND, KILL_ROUNDS = C.KILL_ROUNDS;\n' +
    'var AIM = null, dirty = false, SPAWNS = [], WIND = [], CALLS = [], FIN = [];\n' +
    'var SND = { at:function(){} };\n' +
    'function say(){} function paintPlay(){} function pushBoard(){} function sqLabel(){ return ""; } function now(){ return 0; }\n' +
    'function TEAM(){ return { nm:"" }; } function esc(s){ return s; }\n' +
    'function windTurn(){ WIND.push(G.turn); }\n' +
    'function spawnFrom(s){ SPAWNS.push(s.id); s.opened = true; return null; }\n' +
    'function teamIsBot(){ return false; }\n' +
    args.code + '\n' +
    'var realStartTurn = startTurn, realEndRoundCheck = endRoundCheck;\n' +
    'function finish(w){ FIN.push(w); G.over = true; }\n' +
    'return { setWorld:function(W){ units.length = 0; SQ = {}; SQ_ORDER = []; PEND.length = 0; FALLEN.length = 0;\n' +
    '    SPAWNS.length = 0; WIND.length = 0; CALLS.length = 0; FIN.length = 0;\n' +
    '    W.squads.forEach(function(s){ SQ[s.id] = s; SQ_ORDER.push(s.id); }); W.units.forEach(function(u){ units.push(u); });\n' +
    '    W.fallen.forEach(function(u){ FALLEN.push(u); });\n' +
    '    G.round = W.g.round; G.turn = W.g.turn; G.teams = W.g.teams; G.goal = W.g.goal; G.rounds = W.g.rounds; G.vp = W.g.vp.slice();\n' +
    '    G.players = W.seats; G.over = false; G.on = true; G.phase = W.g.phase; G.fights = []; G.fightAt = 0; G.botTimer = 0; },\n' +
    '  G:G, PEND:PEND, SPAWNS:SPAWNS, WIND:WIND, CALLS:CALLS, FIN:FIN, SQ:function(){ return SQ; }, order:function(){ return SQ_ORDER; },\n' +
    '  sqList:sqList, startTurn:realStartTurn, startFight:startFight, fightTarget:fightTarget, endRoundCheck:realEndRoundCheck,\n' +
    '  endTurn:function(){ startTurn = function(){ CALLS.push("start"); }; endRoundCheck = function(){ CALLS.push("round:" + G.round); };\n' +
    '    try { endTurn(); } finally { startTurn = realStartTurn; endRoundCheck = realEndRoundCheck; } } };');
  var S = factory(BT.TYPES, C), plan = args.plan;
  function setW(W){
    var sqs = W.squads.map(function(s){ return { id:s.id, k:s.k, side:s.side, pl:s.pl, n0:s.n0, vs:s.vs, windN:0,
      moved:!!s.f[0], adv:!!s.f[1], fell:!!s.f[2], still:!!s.f[3], shot:!!s.f[4], charged:!!s.f[5], fought:!!s.f[6],
      chDone:!!s.f[7], shaken:!!s.f[8], owUsed:!!s.f[9], opened:!!s.f[10], chTgt:s.ct || null, advR:s.ar }; });
    var us = W.units.map(function(u){ return { id:u[0], sq:u[1], t:u[2], k:u[2], side:u[3], pl:u[4], hp:u[5], x:u[6]/1000, z:u[7]/1000 }; });
    var fl = W.fallen.map(function(u){ return { id:u[0], sq:u[1], t:u[2], k:u[2], side:u[3], pl:u[4], hp:0, x:0, z:0, windWait:true }; });
    var seats = W.seats.map(function(p, i){ return { id:i, team:p[0], bot:!!p[1], cp:p[2], done:!!p[3] }; });
    S.setWorld({ squads:sqs, units:us, fallen:fl, seats:seats, g:W.g });
  }
  function flagsOf(s){ return [s.moved, s.adv, s.fell, s.still, s.shot, s.charged, s.fought, s.chDone, s.shaken, s.owUsed, s.opened]
    .map(function(b){ return b ? 1 : 0; }); }
  var out = { start_turn: [], fights: [], end_turn: [], end_round: [] };
  plan.start_turn.forEach(function(W){
    setW(W); var ids = S.order().slice();
    S.startTurn();
    var SQ = S.SQ();
    out.start_turn.push({
      squads: ids.map(function(id){ var s = SQ[id]; return [id, flagsOf(s), s.chTgt || '', s.advR || 0, s.vs || 0]; }),
      pend: S.PEND.map(function(P){ return [P.kind, P.u, P.att, P.need, P.n || 0, P.stage]; }),
      seats: S.G.players.map(function(p){ return [p.cp, p.done ? 1 : 0]; }),
      spawns: S.SPAWNS.slice(), wind: S.WIND.slice(), phase: S.G.phase, cmd_wait: S.G.cmdWait ? 1 : 0 });
  });
  plan.fights.forEach(function(W){
    setW(W);
    S.startFight();
    var SQ = S.SQ();
    out.fights.push({ order: S.G.fights.slice(),
      fought: S.order().map(function(id){ return SQ[id].fought ? 1 : 0; }),
      targets: S.sqList().map(function(s){ var t = S.fightTarget(s); return [s.id, t ? t.id : null]; }) });
  });
  plan.end_turn.forEach(function(W){
    setW(W);
    S.endTurn();
    out.end_turn.push({ turn: S.G.turn, round: S.G.round, calls: S.CALLS.slice(),
      done: S.G.players.map(function(p){ return p.done ? 1 : 0; }) });
  });
  plan.end_round.forEach(function(W){
    setW(W);
    S.endRoundCheck();
    out.end_round.push({ fin: S.FIN.slice(), round: S.G.round });
  });
  return out;
}

// ---------- the plan (Node, seeded) ----------
function makePlan(types){
  let seed = 20261010;
  const rnd = () => { seed = (seed * 1103515245 + 12345) % 2147483648; return seed / 2147483648; };
  const ri = (a, b) => a + Math.floor(rnd() * (b - a + 1));
  const pick = a => a[ri(0, a.length - 1)];
  const grid10 = v => Math.round(v / 10) * 10;
  // hidden types never appear in a fixture; wind heroes are left out (their bodies are tested in test_abilities.gd)
  const open = types.filter(T => !T.sec && !T.lk && !T.wind);
  const has = f => open.filter(f);
  const pools = {
    rez: has(T => T.rez), ld: has(T => T.aura === 'ld'), rezA: has(T => T.aura === 'rez'), brave: has(T => T.brave),
    vsh: has(T => T.vsh), spawn: has(T => T.spawn), multi: has(T => T.n >= 3), any: open };
  for (const k of Object.keys(pools)) if (!pools[k].length) throw new Error('empty pool ' + k);
  const typeFor = () => { const x = rnd();
    return x < 0.2 ? pick(pools.rez) : x < 0.3 ? pick(pools.ld) : x < 0.37 ? pick(pools.rezA) : x < 0.47 ? pick(pools.brave) :
      x < 0.52 ? pick(pools.vsh) : x < 0.57 ? pick(pools.spawn) : x < 0.8 ? pick(pools.multi) : pick(pools.any); };
  // one world: teams x squads, models of a squad around a centre near its team's cluster
  function world(o){
    const teams = o.teams, per = o.per, seats = [], squads = [], units = [], fallen = [];
    for (let t = 0; t < teams; t++) for (let i = 0; i < per; i++) seats.push([t, rnd() < 0.3 ? 1 : 0, ri(0, 4), rnd() < 0.5 ? 1 : 0]);
    const spread = o.spread;
    for (let pi = 0; pi < seats.length; pi++){
      const team = seats[pi][0], ns = ri(o.sq[0], o.sq[1]);
      const cx = grid10(ri(-spread, spread)), cz = grid10(ri(-spread, spread));
      for (let j = 0; j < ns; j++){
        const T = o.type ? o.type() : typeFor(), id = pi + ':' + j, r = Math.round((T.r || 0.8) * 1000);
        const x = rnd(), alive = o.dead && rnd() < o.dead ? 0 : x < 0.35 ? ri(0, Math.max(0, Math.floor((T.n - 1) / 2))) : ri(1, T.n);
        const f = []; for (let b = 0; b < 11; b++) f.push(rnd() < 0.4 ? 1 : 0);
        squads.push({ id, k: T.k, side: team, pl: pi, n0: T.n, vs: T.vsh ? ri(0, T.vsh) : (rnd() < 0.05 ? ri(1, 2) : 0), f,
          ct: '', ar: f[1] ? ri(1, 6) : 0 });
        const sx = cx + grid10(ri(-o.jit, o.jit)), sz = cz + grid10(ri(-o.jit, o.jit)), gap = 2 * r + 200;
        for (let m = 0; m < alive; m++){
          const hp = T.n === 1 && rnd() < 0.5 ? ri(1, T.w) : T.w;
          units.push([id + '.' + m, id, T.k, team, pi, hp, sx + (m % 5) * gap, sz + Math.floor(m / 5) * gap]);
        }
      }
    }
    // charge targets: some squads name another squad (living or not)
    squads.forEach(s => { if (rnd() < o.ct) s.ct = pick(squads).id; });
    for (let i = units.length - 1; i > 0; i--){ const j = ri(0, i); const q = units[i]; units[i] = units[j]; units[j] = q; }
    const vp = []; for (let t = 0; t < teams; t++) vp.push(o.vp ? ri(0, 3) * 5 : 0);
    const g = { round: o.round(), turn: ri(0, teams - 1), teams, goal: rnd() < (o.kill || 0) ? 'kill' : 'obj', rounds: pick([0, 3, 5, 7, 10]), vp, phase: o.phase };
    return { g, seats, squads, units, fallen };
  }
  const start_turn = [];
  for (let c = 0; c < 100; c++)
    start_turn.push(world({ teams: ri(2, 4), per: ri(1, 2), sq: [1, 5], spread: 6000 + ri(0, 20000), jit: ri(500, 9000), ct: 0.3,
      round: () => ri(1, 4), phase: 'fight', dead: 0.1 }));
  const fights = [];
  for (let c = 0; c < 100; c++){
    const W = world({ teams: ri(2, 3), per: ri(1, 2), sq: [1, 4], spread: ri(800, 4000), jit: ri(300, 4000), ct: 0.5,
      round: () => ri(1, 5), phase: 'fight', dead: 0.1 });
    fights.push(W);
  }
  const end_turn = [];
  for (let c = 0; c < 100; c++){
    const W = world({ teams: ri(2, 5), per: 1, sq: [1, 1], spread: 20000, jit: 0, ct: 0, round: () => ri(1, 11), phase: 'fight',
      dead: rnd() < 0.5 ? 0.5 : 0, kill: 0.15, type: () => pick(pools.multi) });
    end_turn.push(W);
  }
  const end_round = [];
  for (let c = 0; c < 100; c++){
    const W = world({ teams: ri(2, 4), per: ri(1, 2), sq: [1, 3], spread: 30000, jit: 3000, ct: 0, round: () => 6, phase: 'fight',
      dead: rnd() < 0.4 ? 0.6 : 0.1, kill: 0.2, vp: true });
    if (c % 3 === 0){ // equal armies on two teams: the points tie too (unless deaths differ)
      const a = W.seats.findIndex(p => p[0] === 0), b = W.seats.findIndex(p => p[0] === 1);
      const mine = W.squads.filter(s => s.pl === a), keep = W.squads.filter(s => s.pl !== b);
      const copies = mine.map((s, j) => Object.assign({}, s, { id: b + ':c' + j, side: 1, pl: b }));
      const cu = W.units.filter(u => mine.some(s => s.id === u[1])).map(u => {
        const j = mine.findIndex(s => s.id === u[1]); return [b + ':c' + j + u[0].slice(u[0].indexOf('.')), b + ':c' + j, u[2], 1, b, u[5], -u[6], -u[7]]; });
      W.squads = keep.concat(copies); W.units = W.units.filter(u => keep.some(s => s.id === u[1])).concat(cu);
      W.g.vp[1] = W.g.vp[0];
    }
    if (c % 5 === 1){ // a team held only by a wind body
      const t = W.g.teams - 1, gone = W.squads.filter(s => s.side === t);
      W.units = W.units.filter(u => u[3] !== t);
      const hero = types.find(T => T.wind);
      if (hero && gone.length){ W.fallen.push([gone[0].id + '.w', gone[0].id, hero.k, t, gone[0].pl]); }
      W.g.vp[t] = Math.max.apply(null, W.g.vp);
    }
    end_round.push(W);
  }
  return { start_turn, fights, end_turn, end_round };
}

function stable(v){ return JSON.stringify(v); }
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
  let res, plan, types;
  const browser = await chromium.launch({ executablePath: process.env.CHROMIUM_PATH || undefined, args: ['--no-sandbox'] });
  try {
    const p = await browser.newPage({ viewport: { width: 480, height: 320 } });
    const errs = []; p.on('pageerror', e => errs.push(String(e.stack || e).slice(0, 400)));
    await p.goto('file://' + PAGE);
    await p.waitForFunction('window.BT && window.BT.G && window.BT.TYPES');
    types = await p.evaluate(() => JSON.parse(JSON.stringify(window.BT.TYPES)));
    plan = makePlan(types);
    res = await p.evaluate(pageRun, { code: cuts.map(c => c.text).join('\n'), C, plan });
    if (errs.length) throw new Error('page errors:\n' + errs.join('\n'));
  } finally { await browser.close(); }
  const appVer = (/var APP_VER = '([^']+)'/.exec(src) || [])[1], rulesV = +((/var RULES_V = (\d+)/.exec(src) || [])[1] || 0);
  const head = { about: 'generated by godot/tools/record_turn.js — do not edit; positions are MI ints; world squads have ' +
      'f = [moved, adv, fell, still, shot, charged, fought, chDone, shaken, owUsed, opened], ct = chTgt, ar = advR; units are ' +
      '[id, sq, k, side, pl, hp, x, z]; seats [team, bot, cp, done]; fallen wind bodies [id, sq, k, side, pl]; ' +
      'start_turn pend [kind, u, att, need, n, stage]',
    page: { app_ver: appVer, rules_v: rulesV, consts: C, functions: cuts.map(c => c.name + '@' + c.line) } };
  const pair = (ins, outs) => ins.map((x, i) => ({ in: x, out: outs[i] }));
  const text = serialize(head, { start_turn: pair(plan.start_turn, res.start_turn), fights: pair(plan.fights, res.fights),
    end_turn: pair(plan.end_turn, res.end_turn), end_round: pair(plan.end_round, res.end_round) });
  if (CHECK){
    const old = fs.existsSync(OUT) ? fs.readFileSync(OUT, 'utf8') : '';
    console.log((old === text ? 'same    ' : 'DIFFERS ') + path.relative(ROOT, OUT));
    if (old !== text) process.exit(1);
  } else {
    fs.mkdirSync(path.dirname(OUT), { recursive: true }); fs.writeFileSync(OUT, text);
    console.log('wrote ' + path.relative(ROOT, OUT) + ' (' + Buffer.byteLength(text) + ' B)');
  }
  // coverage of the sampled branches
  const cov = {}, inc = k => { cov[k] = (cov[k] || 0) + 1; };
  res.start_turn.forEach(r => { r.pend.forEach(P => inc('pend_' + P[0])); if (r.spawns.length) inc('spawn');
    if (r.squads.some(s => s[4] > 0)) inc('shields'); });
  plan.start_turn.forEach((W, i) => { const r = res.start_turn[i];
    W.squads.forEach(s => { const T = types.find(q => q.k === s.k); if (T.rez && r.pend.some(P => P[0] === 'rez' && P[1] === s.id && P[3] < T.rez)) inc('rez_aura'); }); });
  res.fights.forEach(r => { inc(r.order.length ? 'fight_order' : 'fight_none'); if (r.targets.some(t => t[1])) inc('fight_target'); });
  plan.fights.forEach((W, i) => { const r = res.fights[i];
    r.targets.forEach(t => { const s = W.squads.find(q => q.id === t[0]); if (t[1] && s.ct === t[1]) inc('target_chtgt'); }); });
  res.end_turn.forEach(r => inc(r.calls.length ? r.calls[0].split(':')[0] : 'none'));
  plan.end_turn.forEach((W, i) => { const r = res.end_turn[i]; if (r.round > W.g.round) inc('wrap'); });
  res.end_round.forEach(r => inc(r.fin[0] === -1 ? 'draw' : 'win'));
  console.log(Object.keys(cov).sort().map(k => k + ' ' + cov[k]).join(', '));
})().catch(e => { console.error(e.stack || e); process.exit(1); });
