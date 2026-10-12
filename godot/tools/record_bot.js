#!/usr/bin/env node
// record_bot.js — sample the page's bot and dice-tray scheduler into a JSON fixture for the Godot port
// (core/battle/bot.gd BtBot and core/battle/roller.gd BtRoller, R1_PORT_SPEC §1.15–§1.16). Read-only on the page.
//
//   node godot/tools/record_bot.js            write the fixture
//   node godot/tools/record_bot.js --check    re-run and fail unless the file is byte-identical
// Environment: PAGE=<battle-table.html>  CHROMIUM_PATH=<chrome>  NODE_PATH or tests/node_modules for playwright.
//
// As tools/record_combat.js: the functions are cut from the page text by name and evaluated in the page's own browser
// next to a hand-built world; INF comes from a temporary copy of the page that hands it to window. What is sampled:
//   exp      expDmg(s, t, how) for every ordered pair of a world and how = shoot/fight/ow (the page's doubles)
//   choice   botChoice(P) for hand-made entries, seats (bot/ai/human, cp) and used stratagem keys
//   roll     myRoll() for hand-made queues, seats and NET states (the index of the entry it returns, -1 = none); all
//            entries of a queue share one age so the port's single since_ok is the page's now() - P.since > OWNER_WAIT
//   steps    a whole bot phase: botStep() called until it returns false. netSend, planMove (records its target),
//            applySMove/applyHit/applyHeal/applyGren and doCharge are stubs that only set the flags the page sets, so
//            the world does not change otherwise; d6 gives 1 (only the number of dice is compared)
// Worlds come from a fixed seed, so a re-run is byte-identical.
//
// Output: godot/tests/unit/fixtures/bot/page_samples.json (positions are MI ints on the 10 MI grid; the page gets inches)
'use strict';
const fs = require('fs'), os = require('os'), path = require('path');

const ROOT = path.resolve(__dirname, '..', '..');
const PAGE = path.resolve(process.env.PAGE || path.join(ROOT, 'app/src/main/assets/battle-table.html'));
const OUT = path.join(ROOT, 'godot/tests/unit/fixtures/bot/page_samples.json');
const CHECK = process.argv.includes('--check');

function loadPlaywright(){
  try { return require('playwright'); }
  catch (e) { return require(path.join(ROOT, 'tests/node_modules/playwright')); }
}

const src = fs.readFileSync(PAGE, 'utf8');
function lineOf(i){ return src.slice(0, i).split('\n').length; }
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
function line(re, what){ const m = re.exec(src); if (!m) throw new Error(what + ' not found on the page'); return m[0]; }

const FUNCS = ['gx', 'gz', 'dist2', 'radOfType', 'TY', 'sqOf', 'sqById', 'sqModels', 'sqAlive', 'sqList', 'sqCenter',
  'sqDist', 'mEdge', 'sqEdge', 'foesOf', 'realFoes', 'engagedWith', 'isEngaged', 'canTarget', 'woundNeed', 'clampNeed',
  'shootersOf', 'painOn', 'pactOn', 'markKey', 'marked', 'inAura', 'atkMath', 'count', 'sum', 'shotWhyNot', 'canHeal',
  'healWhyNot', 'chargeWhyNot', 'grenWhyNot', 'objOC', 'objCtl', 'stratKey', 'canStrat', 'useStrat', 'isBotUnit',
  'botSquads', 'expDmg', 'melee', 'botSkip', 'botStep', 'mkAtk', 'unPend', 'pendOf', 'rollerOf', 'iRollFor',
  'isHumanHere', 'chgReady', 'myRoll', 'botChoice'];
const cuts = FUNCS.map(cutFunction);
const C = {};
[C.ENGAGE] = num(/^var ENGAGE = ([0-9.]+);/m, 'ENGAGE');
[C.CHARGE_R] = num(/^var CHARGE_R = ([0-9.]+);/m, 'CHARGE_R');
[C.AURA_R] = num(/^var AURA_R = ([0-9.]+);/m, 'AURA_R');
[C.BLESS_INV, C.REZ_AURA] = num(/^var BLESS_INV = ([0-9.]+), REZ_AURA = ([0-9.]+);/m, 'BLESS_INV');
[C.PAIN_ROUND] = num(/^var PAIN_ROUND = ([0-9.]+);/m, 'PAIN_ROUND');
[C.GREN_R] = num(/^var GREN_R = ([0-9.]+);/m, 'GREN_R');
[C.OBJ_R] = num(/^var OBJ = \[\], OBJ_R = ([0-9.]+),/m, 'OBJ_R');
[C.OWNER_WAIT] = num(/OWNER_WAIT = ([0-9.]+),/m, 'OWNER_WAIT');
const STRATS_LINE = line(/^var STRATS = .*;$/m, 'STRATS');

const INF_ANCHOR = 'function INF(k){';
function infCopy(){
  const i = src.indexOf(INF_ANCHOR), eol = src.indexOf('\n', i);
  if (i <= 0 || src[i - 1] !== '\n') throw new Error('INF is not declared at the start of a line');
  if (eol < 0 || src.indexOf(INF_ANCHOR, i + 1) >= 0) throw new Error('INF must be declared exactly once, on one line');
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'bt-record-bot-')), copy = path.join(dir, 'battle-table.html');
  fs.writeFileSync(copy, src.slice(0, eol + 1) + 'window.__recINF = INF;\n' + src.slice(eol + 1));
  return { dir, copy };
}

// ---------- what runs in the page ----------
function pageRun(args){
  var BT = window.BT, INF = window.__recINF, C = args.C;
  var factory = new Function('TYPES', 'C', 'INF',
    'var units = [], SQ = {}, SQ_ORDER = [], PEND = [], OBJ = [], AIM = null, SENT = [], PLANS = [], NOW = 1000000;\n' +
    'var G = { freeFire:false, round:1, turn:0, teams:2, phase:"move", over:false, used:{}, players:[], act:null, sel:null };\n' +
    'var NET = { on:false, owner:false, pid:"" };\n' +
    'var ENGAGE = C.ENGAGE, CHARGE_R = C.CHARGE_R, AURA_R = C.AURA_R, BLESS_INV = C.BLESS_INV, REZ_AURA = C.REZ_AURA,\n' +
    '  PAIN_ROUND = C.PAIN_ROUND, GREN_R = C.GREN_R, OBJ_R = C.OBJ_R, OWNER_WAIT = C.OWNER_WAIT;\n' +
    args.strats + '\n' +
    'function now(){ return NOW; } function say(){} function esc(s){ return s; } function humanTurn(){ return false; }\n' +
    'function d6(){ return 1; } function rollN(n){ var a = [], i; for (i=0;i<n;i++) a.push(1); return a; }\n' +
    'function netSend(a){ SENT.push(JSON.parse(JSON.stringify(a))); }\n' +
    'function planMove(s, x, z){ PLANS.push([x, z]); return []; }\n' +
    'function applySMove(s){ s.moved = true; }\n' +
    'function applyHit(P){ var s = sqById(P.u); if (s && P.how === "shoot") s.shot = true; unPend(P); }\n' +
    'function mkPend(P){ PEND.push(P); return P; }\n' +
    'function applyHeal(P){ var s = sqById(P.u); if (s) s.shot = true; unPend(P); }\n' +
    'function applyGren(P){ var s = sqById(P.u); if (s) s.shot = true; unPend(P); }\n' +
    'function doCharge(s, t){ netSend({ a:"chg", u:s.id, t:t.id }); s.chDone = true; }\n' +
    'function finishAtk(P){ unPend(P); }\n' +
    args.code + '\n' +
    'return { setWorld:function(us, sqs, g, objs, players){ units.length = 0; SQ = {}; SQ_ORDER = []; PEND.length = 0; SENT.length = 0;\n' +
    '    PLANS.length = 0; OBJ.length = 0; AIM = null;\n' +
    '    sqs.forEach(function(s){ SQ[s.id] = s; SQ_ORDER.push(s.id); }); us.forEach(function(u){ units.push(u); });\n' +
    '    (objs || []).forEach(function(o){ OBJ.push(o); });\n' +
    '    G.freeFire = !!g.ff; G.round = g.round; G.turn = g.turn; G.teams = g.teams; G.phase = g.phase; G.over = false; G.used = {};\n' +
    '    G.players = players || []; G.act = null; },\n' +
    '  G:G, NET:NET, PEND:PEND, SENT:SENT, PLANS:PLANS, setNow:function(t){ NOW = t; },\n' +
    '  f:{ TY:TY, sqById:sqById, expDmg:expDmg, botStep:botStep, myRoll:myRoll, botChoice:botChoice, stratKey:stratKey } };');
  var S = factory(BT.TYPES, C, INF), F = S.f, plan = args.plan, out = { exp: [], choice: [], roll: [], steps: [] };
  function mkOf(code, g){ return code === 'cur' ? g.round + '.' + g.turn : code === 'old' ? (g.round - 1) + '.' + g.turn : undefined; }
  function build(W){
    var sqs = W.squads.map(function(s){ return { id: s.id, k: s.k, side: s.side, pl: s.pl, n0: s.n0, moved: !!s.f[0],
      adv: !!s.f[1], fell: !!s.f[2], still: !!s.f[3], shot: !!s.f[4], charged: !!s.f[5], chDone: !!s.f[6], shaken: !!s.f[7],
      mk: mkOf(s.mk, W.g) }; });
    var us = W.units.map(function(u){ return { id: u.id, sq: u.sq, k: u.t, t: u.t, side: u.side, pl: u.pl, hp: u.hp,
      x: u.x / 1000, z: u.z / 1000 }; });
    var objs = (W.objs || []).map(function(o){ return { n: o[0], x: o[1] / 1000, z: o[2] / 1000 }; });
    var players = (W.seats || []).map(function(p){ return { team: p.team, bot: !!p.bot, ai: !!p.ai, cp: p.cp, pid: p.pid, done: !!p.done }; });
    S.setWorld(us, sqs, W.g, objs, players);
    (W.used || []).forEach(function(u){ S.G.used[F.stratKey(u[0], u[1])] = true; });
    return sqs;
  }
  // expDmg
  plan.exp.forEach(function(W){
    var sqs = build(W), rows = [];
    sqs.forEach(function(a, i){ sqs.forEach(function(b, j){
      rows.push([i, j, F.expDmg(a, b, 'shoot'), F.expDmg(a, b, 'fight'), F.expDmg(a, b, 'ow')]); }); });
    out.exp.push(rows);
  });
  // botChoice
  plan.choice.forEach(function(Q){
    build(Q.w);
    var E = Q.p, P = { kind: E.kind, stage: E.stage, u: E.u, t: E.t, att: E.att, def: E.def, melee: !!E.melee, wounds: E.wounds,
      sv: E.sv, since: 0 };
    var r = F.botChoice(P);
    out.choice.push([r.yes ? 1 : 0, r.gtg ? 1 : 0, r.brave ? 1 : 0]);
  });
  // myRoll
  plan.roll.forEach(function(Q){
    build(Q.w);
    S.NET.on = !!Q.net[0]; S.NET.owner = !!Q.net[1]; S.NET.pid = Q.net[2];
    var orig = Q.q.map(function(E){ return { kind: E.kind, stage: E.stage, u: E.u, t: E.t, att: E.att, def: E.def, ow: !!E.ow,
      since: 1000000 - Q.age }; });
    orig.forEach(function(P){ S.PEND.push(P); });
    var r = F.myRoll();
    out.roll.push([r && r.P ? orig.indexOf(r.P) : -1, r && r.P ? (r.human ? 1 : 0) : 0]);
  });
  // whole bot phases
  plan.steps.forEach(function(W){
    build(W);
    var guard = 0, ret = [], what;
    do { what = F.botStep(); ret.push(what || false); } while (what && guard++ < 200);
    var acts = S.SENT.map(function(a){ var o = { a: a.a, u: a.u };
      if (a.t != null) o.t = a.t; if (a.how != null) o.how = a.how; if (a.ph != null) o.ph = a.ph;
      if (a.hit) o.n = a.hit.length; if (a.roll != null) o.n = Array.isArray(a.roll) ? a.roll.length : 1; return o; });
    var k = 0;
    acts.forEach(function(o){ if (o.a === 'smove'){ var p = S.PLANS[k++]; o.x = p[0]; o.z = p[1]; } });
    out.steps.push({ acts: acts, steps: ret.length });
  });
  return out;
}

// ---------- the plan (seeded, Node side) ----------
function mulberry32(a){ return function(){ a |= 0; a = a + 0x6D2B79F5 | 0; var t = Math.imul(a ^ a >>> 15, 1 | a);
  t = t + Math.imul(t ^ t >>> 7, 61 | t) ^ t; return ((t ^ t >>> 14) >>> 0) / 4294967296; }; }
function makePlan(types){
  const rnd = mulberry32(20261010), ri = (lo, hi) => lo + Math.floor(rnd() * (hi - lo + 1)), pick = a => a[ri(0, a.length - 1)];
  const grid10 = v => 10 * Math.round(v / 10);
  const open = types.filter(T => !T.sec && !T.lk);
  const g = (T, f) => !!(T.gun && T.gun[f]), m = (T, f) => !!(T.mel && T.mel[f]);
  const pools = {
    heal: open.filter(T => T.heal), melee: open.filter(T => !T.gun), short: open.filter(T => T.gun && T.gun.rng <= 12),
    hv: open.filter(T => g(T, 'hv')), long: open.filter(T => T.gun && T.gun.rng >= 24), tr: open.filter(T => g(T, 'tr')),
    lh: open.filter(T => g(T, 'lh') || m(T, 'lh')), dw: open.filter(T => g(T, 'dw') || m(T, 'dw')), heel: open.filter(T => T.heel),
    inf: open.filter(T => T.inf), pricey: open.filter(T => T.pts >= 90), big: open.filter(T => T.n >= 10),
  };
  Object.keys(pools).forEach(k => { if (!pools[k].length) throw new Error('empty pool ' + k); });
  const names = Object.keys(pools);
  const typeOf = () => rnd() < 0.6 ? pick(pools[pick(names)]) : pick(open);
  // a world: squads in clusters; some squads dead; flags per phase
  function world(o){
    const sides = o.sides, gw = { round: ri(1, 5), turn: ri(0, sides - 1), teams: sides, ff: rnd() < 0.15 ? 1 : 0, phase: o.phase || 'move' };
    const squads = [], units = [], spread = o.spread;
    const nsq = ri(o.min || 3, o.max || 7);
    for (let i = 0; i < nsq; i++){
      const T = typeOf(), side = i < sides ? i : ri(0, sides - 1), id = side + ':' + i, r = Math.round((T.r || 0.8) * 1000);
      const alive = rnd() < 0.08 ? 0 : ri(1, T.n);
      const f = [0, rnd() < 0.15, rnd() < 0.1, rnd() < 0.6, 0, rnd() < 0.2, 0, rnd() < 0.1].map(b => b ? 1 : 0);
      if (o.flags) { f[0] = rnd() < 0.2 ? 1 : 0; f[4] = rnd() < 0.2 ? 1 : 0; f[6] = rnd() < 0.2 ? 1 : 0; }
      const mk = rnd() < 0.15 ? 'cur' : '';
      squads.push({ id, k: T.k, side, pl: side, n0: T.n, f, mk });
      const cx = grid10(ri(-spread, spread)), cz = grid10(ri(-spread, spread)), sp = 2 * r + 1500;
      for (let j = 0; j < alive; j++){
        const hp = rnd() < 0.6 ? T.w : ri(1, T.w);
        units.push({ id: id + '.' + j, sq: id, t: T.k, side, pl: side, hp, x: cx + grid10(ri(-sp, sp)), z: cz + grid10(ri(-sp, sp)) });
      }
    }
    // a few close pairs so engagement, charges, grenades and heals show up
    for (let q = 0; q < 2; q++){
      const st = squads.filter(s => units.some(u => u.sq === s.id));
      if (st.length < 2) break;
      const a = pick(st), b = pick(st.filter(s => s !== a)), gap = pick([1500, 2500, 4000, 7000, 9000, 12000]);
      const ax = grid10(ri(-12000, 12000)), az = grid10(ri(-12000, 12000));
      let ka = 0, kb = 0;
      units.forEach(u => { if (u.sq === a.id){ u.x = ax - 1800 * ka++; u.z = az; } else if (u.sq === b.id){ u.x = ax + gap + 1800 * kb++; u.z = az; } });
    }
    const seats = [];
    for (let s = 0; s < sides; s++) seats.push({ team: s, bot: s === gw.turn ? 1 : (rnd() < 0.3 ? 1 : 0), ai: 0, cp: ri(0, 4), pid: 'p' + s, done: 0 });
    let objs = [];
    if (o.objs && rnd() < 0.75){
      const rx = 12960, rz = 9180;
      objs = [[1, 0, 0], [2, -rx, -rz], [3, rx, -rz], [4, -rx, rz], [5, rx, rz]];
      // sometimes a squad of the side in turn stands on one
      if (rnd() < 0.5){ const mine = squads.filter(s => s.side === gw.turn); if (mine.length){ const s = pick(mine), oo = pick(objs);
        let k = 0; units.forEach(u => { if (u.sq === s.id){ u.x = oo[1] + grid10(ri(-1500, 1500)); u.z = oo[2] + 1800 * k++ - 1800; } }); } }
    }
    const used = rnd() < 0.2 ? [[pick(['gren', 'rr', 'gtg', 'brave', 'ow']), ri(0, sides - 1)]] : [];
    return { g: gw, squads, units, objs, seats, used };
  }
  const exp = [];
  for (let w = 0; w < 16; w++) exp.push(world({ sides: 2, spread: [3000, 8000, 15000][w % 3] }));
  // botChoice
  const choice = [];
  const kinds = [['chg', 'ow'], ['chg', 'chrr'], ['chg', 'charge'], ['atk', 'save'], ['atk', 'save'], ['atk', 'save'], ['atk', 'hit'],
    ['shock', 'shock'], ['shock', 'shock'], ['rez', 'rez']];
  for (let q = 0; q < 160; q++){
    const W = world({ sides: 2, spread: 8000, min: 2, max: 4 });
    W.g.phase = pick(['move', 'shoot', 'charge', 'fight', 'cmd']);
    W.seats.forEach(p => { const x = rnd(); p.bot = x < 0.45 ? 1 : 0; p.ai = !p.bot && x < 0.6 ? 1 : 0; p.cp = ri(0, 3); });
    if (rnd() < 0.3) W.used = [[pick(['gtg', 'brave', 'rr', 'ow']), ri(0, 1)]];
    const kk = pick(kinds), a = pick(W.squads), b = pick(W.squads);
    const p = { kind: kk[0], stage: kk[1], u: rnd() < 0.05 ? 'gone' : a.id, t: b.id, att: a.pl, def: b.pl, melee: rnd() < 0.3 ? 1 : 0,
      wounds: ri(1, 8), sv: ri(2, 7) };
    if (rnd() < 0.05) p.att = 7;
    choice.push({ w: W, p });
  }
  // myRoll
  const roll = [];
  const stages = { atk: ['hit', 'wound', 'save'], chg: ['ow', 'owatk', 'charge', 'chrr', 'move'], shock: ['shock'], rez: ['rez'] };
  for (let q = 0; q < 160; q++){
    const W = world({ sides: ri(2, 3), spread: 8000, min: 2, max: 5 });
    W.seats.forEach(p => { const x = rnd(); p.bot = x < 0.3 ? 1 : 0; p.ai = !p.bot && x < 0.45 ? 1 : 0; });
    const n = ri(1, 5), qq = [];
    for (let i = 0; i < n; i++){
      const kind = pick(['atk', 'atk', 'chg', 'chg', 'shock', 'rez']), a = pick(W.squads), b = pick(W.squads);
      qq.push({ kind, stage: pick(stages[kind]), u: a.id, t: b.id, att: a.pl, def: b.pl, ow: kind === 'atk' && rnd() < 0.3 ? 1 : 0 });
    }
    // an overwatch attack aimed at a waiting charger
    if (rnd() < 0.3){ const c = qq.find(e => e.kind === 'chg'); if (c){ c.stage = 'owatk';
      if (rnd() < 0.7) qq.splice(qq.indexOf(c), 0, { kind: 'atk', stage: 'hit', u: c.t, t: c.u, att: c.def, def: c.att, ow: 1 }); } }
    const net = [rnd() < 0.6 ? 1 : 0, rnd() < 0.5 ? 1 : 0, 'p' + ri(0, W.seats.length)];
    roll.push({ w: W, q: qq, net, age: pick([1000, 26000, 25000, 25001]) });
  }
  // whole phases
  const steps = [];
  for (let w = 0; w < 90; w++){
    const W = world({ sides: ri(2, 3), spread: [6000, 12000, 18000][w % 3], objs: true, flags: w % 4 === 3, min: 4, max: 9 });
    W.g.phase = ['move', 'shoot', 'charge'][w % 3];
    if (W.g.phase !== 'move') W.squads.forEach(s => { if (rnd() < 0.5) s.f[0] = 1; });
    steps.push(W);
  }
  // grenades: our infantry squad near a foe that is engaged with another squad of ours (so it cannot be shot)
  const gunInf = pools.inf.filter(T => T.gun);
  for (let w = 0; w < 24; w++){
    const W = world({ sides: 2, spread: 20000, min: 3, max: 4 });
    W.g.phase = 'shoot'; W.objs = [];
    const me = W.g.turn, foe = 1 - me, A = pick(gunInf), B = pick(open), Cq = pick(open);
    const add = (id, T, side, x0, z0, n) => { W.squads.push({ id, k: T.k, side, pl: side, n0: T.n, f: [0, 0, 0, 1, 0, 0, 0, 0], mk: '' });
      for (let j = 0; j < n; j++) W.units.push({ id: id + '.' + j, sq: id, t: T.k, side, pl: side, hp: T.w, x: x0 + 1800 * j, z: z0 }); };
    add(foe + ':g' + w, B, foe, 40000, 0, 1);
    add(me + ':h' + w, Cq, me, 40000, 2100 + Math.round(((B.r || 0.8) + (Cq.r || 0.8)) * 1000) - 2000, 1);
    add(me + ':a' + w, A, me, 40000, -ri(3000, 7500), Math.min(2, A.n));
    W.seats[me].cp = pick([1, 2, 3]);
    steps.push(W);
  }
  return { exp, choice, roll, steps };
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
  const tmp = infCopy();
  let res, plan;
  try {
    const browser = await chromium.launch({ executablePath: process.env.CHROMIUM_PATH || undefined, args: ['--no-sandbox'] });
    try {
      const p = await browser.newPage({ viewport: { width: 480, height: 320 } });
      const errs = []; p.on('pageerror', e => errs.push(String(e.stack || e).slice(0, 400)));
      await p.goto('file://' + tmp.copy);
      await p.waitForFunction('window.BT && window.BT.G && window.BT.TYPES && window.__recINF');
      const types = await p.evaluate(() => JSON.parse(JSON.stringify(window.BT.TYPES)));
      const infs = await p.evaluate(() => window.BT.TYPES.map(T => window.__recINF(T.k) ? 1 : 0));
      types.forEach((T, i) => { T.inf = infs[i]; });
      plan = makePlan(types);
      res = await p.evaluate(pageRun, { code: cuts.map(c => c.text).join('\n'), strats: STRATS_LINE, C, plan });
      if (errs.length) throw new Error('page errors:\n' + errs.join('\n'));
    } finally { await browser.close(); }
  } finally { fs.rmSync(tmp.dir, { recursive: true, force: true }); }
  const appVer = (/var APP_VER = '([^']+)'/.exec(src) || [])[1], rulesV = +((/var RULES_V = (\d+)/.exec(src) || [])[1] || 0);
  const head = { about: 'generated by godot/tools/record_bot.js — do not edit; exp values are the page\'s doubles; step targets (x, z) are the page\'s planMove arguments in inches; world positions are MI ints',
    page: { app_ver: appVer, rules_v: rulesV, consts: C, functions: cuts.map(c => c.name + '@' + c.line) } };
  const text = serialize(head, { exp_in: plan.exp, exp: res.exp, choice_in: plan.choice, choice: res.choice, roll_in: plan.roll,
    roll: res.roll, steps_in: plan.steps, steps: res.steps });
  if (CHECK){
    const old = fs.existsSync(OUT) ? fs.readFileSync(OUT, 'utf8') : '';
    console.log((old === text ? 'same    ' : 'DIFFERS ') + path.relative(ROOT, OUT));
    if (old !== text) process.exit(1);
  } else {
    fs.mkdirSync(path.dirname(OUT), { recursive: true }); fs.writeFileSync(OUT, text);
    console.log('wrote ' + path.relative(ROOT, OUT) + ' (' + Buffer.byteLength(text) + ' B)');
  }
  const cov = {}, inc = k => { cov[k] = (cov[k] || 0) + 1; };
  res.steps.forEach(S => S.acts.forEach(a => inc(a.a + (a.how ? ':' + a.how : ''))));
  res.choice.forEach(c => { if (c[0]) inc('yes'); if (c[1]) inc('gtg'); if (c[2]) inc('brave'); });
  res.roll.forEach(r => inc(r[0] < 0 ? 'roll_none' : 'roll_' + r[0] + (r[1] ? 'h' : '')));
  console.log(Object.keys(cov).sort().map(k => k + ' ' + cov[k]).join(', '));
})().catch(e => { console.error(e.stack || e); process.exit(1); });
