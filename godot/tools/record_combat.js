#!/usr/bin/env node
// record_combat.js — sample the page's combat functions into a JSON fixture for the Godot port
// (core/battle/combat.gd BtCombat, R1_PORT_SPEC §1.7; the registry tests in test_abilities.gd read it too). Read-only on
// the page.
//
//   node godot/tools/record_combat.js            write the fixture
//   node godot/tools/record_combat.js --check    re-run and fail unless the file is byte-identical
// Environment: PAGE=<battle-table.html>  CHROMIUM_PATH=<chrome>  NODE_PATH or tests/node_modules for playwright.
//
// The functions live inside the page's game IIFE, so their source is cut from the page text by name and evaluated in the
// page's own browser (Chromium V8) next to a hand-built world, as tools/record_squads_strats.js does. INF needs the
// figure kits (isBeast, kitScale), so the page is loaded from a temporary copy that hands INF to window right after its
// one-line declaration (as tools/export_data.js does) and the cut functions call that live INF. The why-not functions
// return Thai HTML; each message is matched exactly against the page's text and stored as the port's key plus args.
// Live cross-check: on a started match with squads placed close together, BT.atkMath, BT.why and BT.inAura must equal
// the cut functions run on a copy of the same world. Worlds come from a fixed seed, so a re-run is byte-identical.
//
// Output: godot/tests/unit/fixtures/combat/page_samples.json
//   wound_need (S, T = 1..24), clamp_need (-3..10), count/sum samples, inf and army rules (painOn, pactOn) per datasheet,
//   worlds_in (squads with flags, units in MI on the 10 MI grid) and per world: per squad inAura bits and marked, per
//   ordered pair atkMath for shoot/fight/ow, shootersOf, shotWhyNot, canHeal, healWhyNot, chargeWhyNot, grenWhyNot.
'use strict';
const fs = require('fs'), os = require('os'), path = require('path');

const ROOT = path.resolve(__dirname, '..', '..');
const PAGE = path.resolve(process.env.PAGE || path.join(ROOT, 'app/src/main/assets/battle-table.html'));
const OUT = path.join(ROOT, 'godot/tests/unit/fixtures/combat/page_samples.json');
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
function num(re, what){ const m = re.exec(src); if (!m) throw new Error(what + ' not found on the page'); return m.slice(1).map(Number); }

const FUNCS = ['gx', 'gz', 'dist2', 'radOfType', 'TY', 'sqModels', 'sqAlive', 'sqList', 'sqDist', 'mEdge', 'sqEdge',
  'foesOf', 'realFoes', 'engagedWith', 'isEngaged', 'canTarget', 'woundNeed', 'clampNeed', 'shootersOf', 'painOn',
  'pactOn', 'markKey', 'marked', 'inAura', 'atkMath', 'count', 'sum', 'shotWhyNot', 'canHeal', 'healWhyNot',
  'chargeWhyNot', 'grenWhyNot'];
const cuts = FUNCS.map(cutFunction);
const C = {};
[C.ENGAGE] = num(/^var ENGAGE = ([0-9.]+);/m, 'ENGAGE');
[C.CHARGE_R] = num(/^var CHARGE_R = ([0-9.]+);/m, 'CHARGE_R');
[C.AURA_R] = num(/^var AURA_R = ([0-9.]+);/m, 'AURA_R');
[C.BLESS_INV, C.REZ_AURA] = num(/^var BLESS_INV = ([0-9.]+), REZ_AURA = ([0-9.]+);/m, 'BLESS_INV');
[C.PAIN_ROUND] = num(/^var PAIN_ROUND = ([0-9.]+);/m, 'PAIN_ROUND');
[C.GREN_R] = num(/^var GREN_R = ([0-9.]+);/m, 'GREN_R');

// a temporary copy of the page that hands INF to window (the page itself is never written)
const INF_ANCHOR = 'function INF(k){';
function infCopy(){
  const i = src.indexOf(INF_ANCHOR), eol = src.indexOf('\n', i);
  if (i <= 0 || src[i - 1] !== '\n') throw new Error('INF is not declared at the start of a line');
  if (eol < 0 || src.indexOf(INF_ANCHOR, i + 1) >= 0) throw new Error('INF must be declared exactly once, on one line');
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'bt-record-combat-')), copy = path.join(dir, 'battle-table.html');
  fs.writeFileSync(copy, src.slice(0, eol + 1) + 'window.__recINF = INF;\n' + src.slice(eol + 1));
  return { dir, copy };
}

// ---------- what runs in the page ----------
// args: { code, C, plan } — plan holds the worlds and the small tables made in Node
function pageRun(args){
  var BT = window.BT, INF = window.__recINF, C = args.C;
  var factory = new Function('TYPES', 'C', 'INF',
    'var units = [], SQ = {}, SQ_ORDER = [], G = { freeFire:false, round:1, turn:0 };\n' +
    'var ENGAGE = C.ENGAGE, CHARGE_R = C.CHARGE_R, AURA_R = C.AURA_R, BLESS_INV = C.BLESS_INV, REZ_AURA = C.REZ_AURA,\n' +
    '  PAIN_ROUND = C.PAIN_ROUND, GREN_R = C.GREN_R;\n' +
    args.code + '\n' +
    'return { setWorld:function(us, sqs, g){ units.length = 0; SQ = {}; SQ_ORDER = [];\n' +
    '    sqs.forEach(function(s){ SQ[s.id] = s; SQ_ORDER.push(s.id); }); us.forEach(function(u){ units.push(u); });\n' +
    '    G.freeFire = !!g.ff; G.round = g.round; G.turn = g.turn; },\n' +
    '  f:{ TY:TY, sqModels:sqModels, sqDist:sqDist, sqEdge:sqEdge, woundNeed:woundNeed, clampNeed:clampNeed,\n' +
    '      shootersOf:shootersOf, painOn:painOn, pactOn:pactOn, markKey:markKey, marked:marked, inAura:inAura,\n' +
    '      atkMath:atkMath, count:count, sum:sum, shotWhyNot:shotWhyNot, canHeal:canHeal, healWhyNot:healWhyNot,\n' +
    '      chargeWhyNot:chargeWhyNot, grenWhyNot:grenWhyNot } };');
  var S = factory(BT.TYPES, C, INF), F = S.f, plan = args.plan, out = {};
  var SPAN = '<br><span style="font-size:12px">', END = '</span>';
  // the page's exact messages -> the port's keys (dynamic ones rebuilt from the same values; anything else throws)
  function whyShot(msg, s, t){
    var W = F.TY(s.k).gun;
    var fixed = {
      'หน่วยนี้ไม่มีอาวุธยิง': 'no_gun', 'ยิงพวกเดียวกันไม่ได้': 'own_side', 'หน่วยนี้ยิงไปแล้วในเทิร์นนี้': 'already_shot',
      'ถอยออกจากการประชิดมา ยิงไม่ได้ในเทิร์นนี้': 'fell_back', 'วิ่งมา ยิงไม่ได้': 'advanced',
      'เป้าติดประชิดกับพวกเรา': 'target_engaged' };
    var tails = { no_gun: SPAN + 'ต้องบุกเข้าประชิดในเฟสบุก' + END, own_side: SPAN + 'เปิดโหมดฟรีฟายได้ที่หน้าตั้งสนาม' + END,
      advanced: SPAN + '(เว้นอาวุธที่ยิงได้แม้วิ่ง)' + END, target_engaged: SPAN + 'ยิงไม่ได้ เดี๋ยวโดนพวกเดียวกัน' + END };
    if (msg === '') return [''];
    for (var head in fixed){ var k = fixed[head]; if (msg === head + (tails[k] || '')) return [k]; }
    if (W && msg === 'ติดประชิดอยู่ ยิงไม่ได้') return ['engaged', 0];
    if (W && msg === 'ติดประชิดอยู่ ยิงไม่ได้' + SPAN + 'ปืนพกยิงได้แค่หน่วยที่ประชิดอยู่' + END) return ['engaged', 1];
    var d = F.sqDist(s, t);
    if (W && msg === 'ไกลเกินไป<br><b>' + d.toFixed(1) + '"</b> / ยิงได้ ' + W.rng + '"') return ['too_far', d, W.rng];
    throw new Error('unknown shotWhyNot message: ' + msg);
  }
  function whyHeal(msg, s, t){
    if (msg === '') return [''];
    if (msg === 'หน่วยนี้ใช้การกระทำไปแล้วในเทิร์นนี้') return ['already_acted'];
    if (msg === 'หน่วยนี้ไม่มีใครเจ็บ') return ['nobody_hurt'];
    var h = F.TY(s.k).heal;
    if (msg === 'ไกลเกินไป<br>รักษาได้ในระยะ ' + h + '"') return ['too_far', h == null ? 0 : h];
    throw new Error('unknown healWhyNot message: ' + msg);
  }
  function whyChg(msg, s, t){
    var fixed = { 'บุกได้แค่ศัตรู': 'enemies_only', 'หน่วยนี้บุกไปแล้วในเทิร์นนี้': 'charge_done',
      'วิ่งมา บุกไม่ได้ในเทิร์นนี้': 'advanced', 'ถอยมา บุกไม่ได้ในเทิร์นนี้': 'fell_back', 'ติดประชิดอยู่แล้ว': 'engaged', '': '' };
    if (msg in fixed) return [fixed[msg]];
    var d = F.sqEdge(s, t);
    if (msg === 'ไกลเกินไป<br><b>' + d.toFixed(1) + '"</b> / บุกได้ ' + C.CHARGE_R + '"') return ['too_far', d];
    throw new Error('unknown chargeWhyNot message: ' + msg);
  }
  function whyGren(msg){
    var fixed = { 'หน่วยนี้ไม่มีระเบิดมือ': 'not_infantry', 'หน่วยนี้ยิงไปแล้วในเทิร์นนี้': 'already_shot',
      'วิ่งหรือถอยมา ใช้ไม่ได้': 'moved_fast', 'ติดประชิดอยู่': 'engaged', 'ปาได้แค่ศัตรู': 'enemies_only', '': '' };
    fixed['ไกลเกินไป<br>ปาได้ ' + C.GREN_R + '"'] = 'too_far';
    if (msg in fixed) return [fixed[msg]];
    throw new Error('unknown grenWhyNot message: ' + msg);
  }
  // atkMath as an array: [shots, who, need, wneed, mod, sv, dmg, su, bits, d]; bits 1 tr, 2 lh, 4 dw, 8 heel,
  // 16 mk (mkAtk: how is shoot and the weapon has mk), 32 melee
  function enc(M, how){
    if (!M) return null;
    var bits = (M.tr ? 1 : 0) | (M.lh ? 2 : 0) | (M.dw ? 4 : 0) | (M.heel ? 8 : 0) |
      (how === 'shoot' && !!(M.W && M.W.mk) ? 16 : 0) | (M.melee ? 32 : 0);
    return [M.shots, M.who, M.need, M.wneed, M.mod, M.sv, M.dmg, M.su, bits, M.d];
  }
  var KINDS = ['hit', 'ld', 'bless', 'rez', 'veil'], HOWS = ['shoot', 'fight', 'ow'];
  function mkOf(code, g){ return code === 'cur' ? g.round + '.' + g.turn : code === 'old' ? (g.round - 1) + '.' + g.turn : undefined; }
  function build(W){
    var sqs = W.squads.map(function(s){ return { id: s.id, k: s.k, side: s.side, pl: s.pl, n0: s.n0, moved: !!s.f[0],
      adv: !!s.f[1], fell: !!s.f[2], still: !!s.f[3], shot: !!s.f[4], charged: !!s.f[5], chDone: !!s.f[6], mk: mkOf(s.mk, W.g) }; });
    var us = W.units.map(function(u){ return { id: u.id, sq: u.sq, k: u.t, t: u.t, side: u.side, pl: u.pl, hp: u.hp,
      x: u.x / 1000, z: u.z / 1000 }; });
    S.setWorld(us, sqs, W.g);
    return sqs;
  }
  function sample(sqs){
    var res = { aura: [], pairs: [] };
    sqs.forEach(function(s){ var bits = 0;
      KINDS.forEach(function(k, i){ if (F.inAura(s, k)) bits |= 1 << i; });
      if (F.marked(s)) bits |= 32;
      res.aura.push(bits); });
    sqs.forEach(function(a, i){ sqs.forEach(function(b, j){
      var A = F.TY(a.k), ms = F.sqModels(a);
      var atk = HOWS.map(function(h){ return enc(F.atkMath(a, b, h), h); });
      var sh = A.gun ? F.shootersOf(a, b, A.gun).map(function(x){ return [ms.indexOf(x.m), x.d]; }) : null;
      res.pairs.push([i, j, atk, sh, whyShot(F.shotWhyNot(a, b), a, b), F.canHeal(a, b) ? 1 : 0,
        whyHeal(F.healWhyNot(a, b), a, b), whyChg(F.chargeWhyNot(a, b), a, b), whyGren(F.grenWhyNot(a, b))]);
    }); });
    return res;
  }

  // small tables
  out.wound_need = [];
  for (var S1 = 1; S1 <= 24; S1++) for (var T1 = 1; T1 <= 24; T1++) out.wound_need.push(F.woundNeed(S1, T1));
  out.clamp_need = []; for (var n = -3; n <= 10; n++) out.clamp_need.push([n, F.clampNeed(n)]);
  out.count_sum = plan.dice.map(function(d){ return [d.arr, d.need, F.count(d.arr, d.need), F.sum(d.arr)]; });
  out.inf = BT.TYPES.map(function(T){ return [T.k, INF(T.k) ? 1 : 0]; });
  // painOn at rounds 1..5 as bits 1..16, pactOn as bit 32
  out.army = BT.TYPES.map(function(T){ var bits = 0;
    for (var r = 1; r <= 5; r++){ S.setWorld([], [], { ff: 0, round: r, turn: 0 }); if (F.painOn(T)) bits |= 1 << (r - 1); }
    if (F.pactOn(T)) bits |= 32;
    return [T.k, bits]; });
  out.worlds = plan.worlds.map(function(W){ return sample(build(W)); });

  // live cross-check: a started match, squads placed close together, flags and a mark set, round 3 (pain on)
  var G = BT.G, i, live = { pairs: 0, atk: 0, why: 0, aura: 0, bad: [] };
  BT.clock(false); BT.quit(); BT.seed(11); BT.size(48);
  G.mode = 'pvp'; G.teams = 2; G.perTeam = 1; G.budget = 5000; G.freeFire = false; G.goal = 'obj'; G.rounds = 5;
  BT.mkPlayers();
  var L0 = [], L1 = [];
  for (i = 0; i < BT.TYPES.length; i++){
    L0.push(plan.live[0].indexOf(BT.TYPES[i].k) >= 0 ? 1 : 0); L1.push(plan.live[1].indexOf(BT.TYPES[i].k) >= 0 ? 1 : 0); }
  BT.setList(0, L0); BT.setList(1, L1);
  BT.players().forEach(function(P, k){ P.bot = true; var d = BT.autoDep(k); BT.setDep(k, d[0], d[1]); });
  BT.start();
  var live_sq = BT.squads();
  live_sq.forEach(function(s, k){ var p = plan.live_at[k % plan.live_at.length]; BT.place(s.id, p[0], p[1], p[2]); });
  G.round = 3;
  live_sq.forEach(function(s, k){ s.still = k % 3 !== 1; s.adv = k % 5 === 2; s.fell = k % 7 === 3; s.charged = k % 2 === 0;
    s.shot = false; s.chDone = false; if (k === 1) s.mk = G.round + '.' + G.turn; });
  var copyU = BT.units.map(function(u){ return { id: u.id, sq: u.sq, k: u.t, t: u.t, side: u.side, pl: u.pl, hp: u.hp,
    x: u.gx != null ? u.gx : u.x, z: u.gz != null ? u.gz : u.z }; });
  var copyS = live_sq.map(function(s){ return { id: s.id, k: s.k, side: s.side, pl: s.pl, n0: s.n0, moved: s.moved, adv: s.adv,
    fell: s.fell, still: s.still, shot: s.shot, charged: s.charged, chDone: s.chDone, mk: s.mk }; });
  S.setWorld(copyU, copyS, { ff: G.freeFire, round: G.round, turn: G.turn });
  var strip = function(M){ if (!M) return 'null'; var o = {}; Object.keys(M).sort().forEach(function(k){ if (k !== 'W') o[k] = M[k]; });
    return JSON.stringify(o) + '|' + (M.W ? M.W.nm : ''); };
  live_sq.forEach(function(a, ia){ live_sq.forEach(function(b, ib){
    live.pairs++;
    HOWS.forEach(function(h){ live.atk++;
      if (strip(BT.atkMath(a.id, b.id, h)) !== strip(F.atkMath(copyS[ia], copyS[ib], h))) live.bad.push(['atk', a.id, b.id, h]); });
    [['shoot', F.shotWhyNot], ['chg', F.chargeWhyNot], ['heal', F.healWhyNot]].forEach(function(q){ live.why++;
      if (BT.why(q[0], a.id, b.id) !== q[1](copyS[ia], copyS[ib])) live.bad.push(['why', q[0], a.id, b.id]); });
  }); });
  live_sq.forEach(function(s, k){ KINDS.forEach(function(kind){ live.aura++;
    if (BT.inAura(s.id, kind) !== F.inAura(copyS[k], kind)) live.bad.push(['aura', s.id, kind]); }); });
  // what the live world exercised (shows the cross-check is not all "too far")
  live.in_range = 0; live.engaged = 0;
  live_sq.forEach(function(a, ia){ live_sq.forEach(function(b, ib){
    var M = F.atkMath(copyS[ia], copyS[ib], 'shoot'); if (M && M.shots) live.in_range++;
    if (F.chargeWhyNot(copyS[ia], copyS[ib]) === 'ติดประชิดอยู่แล้ว') live.engaged++; }); });
  live.squads = live_sq.length;
  BT.quit();
  out.live = live;
  return out;
}

// ---------- the plan (seeded, Node side) ----------
function mulberry32(a){ return function(){ a |= 0; a = a + 0x6D2B79F5 | 0; var t = Math.imul(a ^ a >>> 15, 1 | a);
  t = t + Math.imul(t ^ t >>> 7, 61 | t) ^ t; return ((t ^ t >>> 14) >>> 0) / 4294967296; }; }
function makePlan(types){
  const rnd = mulberry32(20261007 + 2), ri = (lo, hi) => lo + Math.floor(rnd() * (hi - lo + 1)), pick = a => a[ri(0, a.length - 1)];
  const grid10 = v => 10 * Math.round(v / 10);
  const open = types.filter(T => !T.sec && !T.lk);
  const g = (T, f) => !!(T.gun && T.gun[f]), m = (T, f) => !!(T.mel && T.mel[f]);
  // one pool per rule the port must match; worlds draw from them so every branch shows up many times
  const pools = {
    rf: open.filter(T => g(T, 'rf')), bl: open.filter(T => g(T, 'bl')), hv: open.filter(T => g(T, 'hv')),
    as: open.filter(T => g(T, 'as')), pi: open.filter(T => g(T, 'pi')), tr: open.filter(T => g(T, 'tr')),
    po: open.filter(T => g(T, 'po') || m(T, 'po')), mk: open.filter(T => g(T, 'mk')), su: open.filter(T => g(T, 'su')),
    lh: open.filter(T => g(T, 'lh') || m(T, 'lh')), dw: open.filter(T => g(T, 'dw') || m(T, 'dw')), la: open.filter(T => m(T, 'la')),
    hit: open.filter(T => T.aura === 'hit'), veil: open.filter(T => T.aura === 'veil'), bless: open.filter(T => T.aura === 'bless'),
    ld: open.filter(T => T.aura === 'ld'), rez: open.filter(T => T.aura === 'rez'), st: open.filter(T => T.st),
    aoc: open.filter(T => T.aoc), inv: open.filter(T => T.inv), heel: open.filter(T => T.heel), ca: open.filter(T => T.ca),
    fly: open.filter(T => T.fly), ttn: open.filter(T => T.ttn), ac: open.filter(T => T.ac), heal: open.filter(T => T.heal),
    de: open.filter(T => T.fac === 'de'), cx: open.filter(T => T.fac === 'cx'), el: open.filter(T => T.fac === 'el'),
    melee: open.filter(T => !T.gun), big: open.filter(T => T.n >= 10),
  };
  const names = Object.keys(pools);
  names.forEach(k => { if (!pools[k].length) throw new Error('empty pool ' + k); });
  const worlds = [];
  for (let w = 0; w < 48; w++){
    const sides = ri(2, 3), nsq = ri(3, 7), mode = w % 4;
    const spread = mode === 0 ? 2500 : mode === 1 ? 7000 : mode === 2 ? 12000 : 20000;
    const gw = { round: ri(1, 5), turn: ri(0, sides - 1), ff: rnd() < 0.25 ? 1 : 0 };
    const squads = [], units = [];
    for (let i = 0; i < nsq; i++){
      const x = rnd(), T = x < 0.12 ? pick(pools.heal) : x < 0.24 ? pick(pools[pick(['hit', 'veil', 'bless', 'ld', 'rez'])]) :
        x < 0.7 ? pick(pools[pick(names)]) : pick(open);
      const side = i < sides ? i : ri(0, sides - 1), id = side + ':' + i, r = Math.round((T.r || 0.8) * 1000);
      const alive = rnd() < 0.08 ? 0 : ri(1, T.n);
      const f = [rnd() < 0.3, rnd() < 0.25, rnd() < 0.2, rnd() < 0.6, rnd() < 0.15, rnd() < 0.35, rnd() < 0.15].map(b => b ? 1 : 0);
      const mk = rnd() < 0.3 ? 'cur' : rnd() < 0.2 ? 'old' : '';
      squads.push({ id, k: T.k, side, pl: side, n0: T.n, f, mk, r, rng: T.gun ? T.gun.rng : 0, rf: g(T, 'rf') ? 1 : 0, heal: T.heal || 0,
        aura: T.aura ? 1 : 0 });
      const cx = grid10(ri(-spread, spread)), cz = grid10(ri(-spread, spread)), sp = 2 * r + 1500;
      for (let j = 0; j < alive; j++){
        const hp = rnd() < 0.5 ? T.w : ri(1, T.w);
        units.push({ id: id + '.' + j, sq: id, t: T.k, side, pl: side, hp, x: cx + grid10(ri(-sp, sp)), z: cz + grid10(ri(-sp, sp)) });
      }
    }
    // boundary pairs: lay squad a out on a line towards -x and squad b towards +x so that their nearest models stand
    // exactly at a rules threshold, one grid step inside or outside it (thresholds are whole MI: the page's +0.001");
    // first a healer and then an aura bearer with a squad of their own side when the world has them, then any pair
    const used = {};
    const standing = () => squads.filter(s => !used[s.id] && units.some(u => u.sq === s.id));
    const mate = (a) => standing().filter(s => s !== a && s.side === a.side);
    for (let q = 0; q < 4; q++){
      let a = null, b = null, L = 0;
      if (q === 0 || q === 1){
        const cand = standing().filter(s => (q === 0 ? s.heal : s.aura) && mate(s).length);
        if (!cand.length) continue;
        a = pick(cand); b = pick(mate(a));
        L = q === 0 ? a.heal * 1000 : C.AURA_R * 1000;
      } else {
        if (w % 2) break;
        const st = standing();
        if (st.length < 2) break;
        a = pick(st); b = pick(st.filter(s => s !== a));
        const th = [];
        if (a.rng) th.push(a.rng * 1000);
        if (a.rf) th.push(a.rng * 500);
        if (a.heal) th.push(a.heal * 1000);
        th.push(C.AURA_R * 1000, C.GREN_R * 1000, C.CHARGE_R * 1000 + a.r + b.r, C.ENGAGE * 1000 + a.r + b.r);
        L = pick(th);
      }
      used[a.id] = used[b.id] = 1;
      L += pick([-10, 0, 0, 10]);
      const ax = grid10(ri(-15000, 15000)), az = grid10(ri(-15000, 15000));
      let ka = 0, kb = 0;
      units.forEach(u => { if (u.sq === a.id){ u.x = ax - 2000 * ka++; u.z = az; } else if (u.sq === b.id){ u.x = ax + L + 2000 * kb++; u.z = az; } });
    }
    for (let i = units.length - 1; i > 0; i--){ const j = ri(0, i); const t = units[i]; units[i] = units[j]; units[j] = t; }
    worlds.push({ g: gw, squads: squads.map(s => ({ id: s.id, k: s.k, side: s.side, pl: s.pl, n0: s.n0, f: s.f, mk: s.mk })), units });
  }
  const dice = [];
  for (let q = 0; q < 24; q++){ const n = ri(0, 12), arr = []; for (let i = 0; i < n; i++) arr.push(ri(1, 6)); dice.push({ arr, need: ri(1, 7) }); }
  // live check lists (one squad per key) and the places they are set down (inches, face)
  const live = [['infantry', 'kcapt', 'flamer', 'sniper', 'templar', 'medic', 'boy'], ['ninja', 'archer', 'swvenom', 'hmg', 'dewar', 'cavalry', 'peltast']];
  live.flat().forEach(k => { if (!types.some(T => T.k === k)) throw new Error('live check key missing: ' + k); });
  const live_at = [[-6, -3, 0], [6, 5, Math.PI], [-1, -3.5, 0], [1, 1, Math.PI], [4, -4, 0], [-3, 3, Math.PI], [8, -2, 0],
    [-8, 1.5, Math.PI], [0, 6, Math.PI], [2.5, -6.5, 0], [-5, 6.5, Math.PI], [9, 4, Math.PI], [-9, -6, 0], [3, 2.6, Math.PI]];
  return { worlds, dice, live, live_at };
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
  const tmp = infCopy();
  let res, plan;
  try {
    const browser = await chromium.launch({ executablePath: process.env.CHROMIUM_PATH || undefined, args: ['--no-sandbox'] });
    try {
      const p = await browser.newPage({ viewport: { width: 480, height: 320 } });
      const errs = []; p.on('pageerror', e => errs.push(String(e.stack || e).slice(0, 400)));
      await p.goto('file://' + tmp.copy);
      await p.waitForFunction('window.BT && window.BT.G && window.BT.TYPES && window.__recINF');
      plan = makePlan(await p.evaluate(() => JSON.parse(JSON.stringify(window.BT.TYPES))));
      res = await p.evaluate(pageRun, { code: cuts.map(c => c.text).join('\n'), C, plan });
      if (errs.length) throw new Error('page errors:\n' + errs.join('\n'));
    } finally { await browser.close(); }
  } finally { fs.rmSync(tmp.dir, { recursive: true, force: true }); }
  if (res.live.bad.length) throw new Error('the cut functions differ from the live page: ' + JSON.stringify(res.live.bad.slice(0, 10)));
  const appVer = (/var APP_VER = '([^']+)'/.exec(src) || [])[1], rulesV = +((/var RULES_V = (\d+)/.exec(src) || [])[1] || 0);
  const head = { about: 'generated by godot/tools/record_combat.js — do not edit; distances (atk d, shooters, too_far args) are the page\'s raw doubles in inches; worlds_in positions are MI ints',
    page: { app_ver: appVer, rules_v: rulesV, consts: C, functions: cuts.map(c => c.name + '@' + c.line) },
    live_check: res.live };
  const text = serialize(head, { wound_need: res.wound_need, clamp_need: res.clamp_need, count_sum: res.count_sum, inf: res.inf,
    army: res.army, worlds_in: plan.worlds, worlds: res.worlds });
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
  res.worlds.forEach(W => {
    W.aura.forEach(b => { ['hit', 'ld', 'bless', 'rez', 'veil'].forEach((k, i) => { if (b & (1 << i)) inc('aura_' + k); }); if (b & 32) inc('marked'); });
    W.pairs.forEach(P => {
      P[2].forEach((M, h) => { if (!M) return; inc('atk_' + ['shoot', 'fight', 'ow'][h]); if (M[0]) inc('shots_' + ['shoot', 'fight', 'ow'][h]);
        inc('mod' + M[4]); });
      inc('shot:' + P[4][0]); inc('heal:' + P[6][0]); inc('chg:' + P[7][0]); inc('gren:' + P[8][0]); if (P[5]) inc('can_heal');
    });
  });
  console.log('worlds ' + res.worlds.length + ', pairs ' + res.worlds.reduce((a, w) => a + w.pairs.length, 0) +
    ', live check ' + JSON.stringify({ pairs: res.live.pairs, in_range: res.live.in_range, engaged: res.live.engaged }));
  console.log(Object.keys(cov).sort().map(k => k + ' ' + cov[k]).join(', '));
})().catch(e => { console.error(e.stack || e); process.exit(1); });
