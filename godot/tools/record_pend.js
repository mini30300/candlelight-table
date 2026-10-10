#!/usr/bin/env node
// record_pend.js — sample the page's pending-queue appliers into a JSON fixture for the Godot port
// (core/battle/pend.gd BtPend and the glory heal of core/battle/abilities.gd; R1_PORT_SPEC §1.9, §1.10). Read-only on
// the page.
//
//   node godot/tools/record_pend.js            write the fixture
//   node godot/tools/record_pend.js --check    re-run and fail unless the file is byte-identical
// Environment: PAGE=<battle-table.html>  CHROMIUM_PATH=<chrome>  NODE_PATH or tests/node_modules for playwright.
//
// The functions live inside the page's game IIFE, so their source is cut from the page text by name and evaluated in the
// page's own browser (Chromium V8) next to a hand-built world (units, SQ, SQ_ORDER, PEND, FALLEN, G, the live
// BT.TYPES), as tools/record_combat.js does. The tray, the log, sound and effects are stubbed out (trayThrow, say,
// markFinal, paintPlay, vshieldFx, checkOver, owOk); afterKills only records the dead ids (spawn positions are a v10
// difference, R1_PORT_SPEC §7 #2) and d6 throws, so every sampled stage gets exactly the dice it needs (padding is a
// v10 rule of its own). Worlds and dice come from a fixed seed, so a re-run is byte-identical.
//
// Output: godot/tests/unit/fixtures/pend/page_samples.json
//   attacks   whole attacks: world, the hand-made attack entry, the dice of every stage, the entry after every stage
//             and the world after finishAtk (units in order with hp, shields left, wind falls, marks, flags, gk heal)
//   victims   nextVictim(t, from) with from null, empty or standing
//   damage    dealDamage(t, from, n, dmg, spill): killed in order, units after, shields left
//   glory     gloryHeal(s, n)
//   charge    the need of declareCharge(s, t)
// Positions are MI ints on the 10 MI grid (the page gets inches = MI / 1000).
'use strict';
const fs = require('fs'), path = require('path');

const ROOT = path.resolve(__dirname, '..', '..');
const PAGE = path.resolve(process.env.PAGE || path.join(ROOT, 'app/src/main/assets/battle-table.html'));
const OUT = path.join(ROOT, 'godot/tests/unit/fixtures/pend/page_samples.json');
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

const FUNCS = ['gx', 'gz', 'dist2', 'radOfType', 'TY', 'sqById', 'sqModels', 'sqAlive', 'sqCenter', 'mEdge', 'sqEdge',
  'markKey', 'count', 'sum', 'unPend', 'markHit', 'countHits', 'applyHit', 'applyReroll', 'woundDice', 'saveDice',
  'applyWnd', 'applySav', 'nextVictim', 'dealDamage', 'gloryHeal', 'finishAtk', 'windFall', 'declareCharge'];
const cuts = FUNCS.map(cutFunction);
const C = {};
[C.ENGAGE] = num(/^var ENGAGE = ([0-9.]+);/m, 'ENGAGE');

// ---------- what runs in the page ----------
function pageRun(args){
  var BT = window.BT, C = args.C;
  var factory = new Function('TYPES', 'C',
    'var units = [], SQ = {}, SQ_ORDER = [], PEND = [], FALLEN = [], G = { freeFire:false, teams:2, round:1, turn:0, sel:null }, dirty = false;\n' +
    'var ENGAGE = C.ENGAGE, KILLS = [];\n' +
    'function d6(){ throw new Error("d6 called: a stage was given too few dice"); }\n' +
    'function trayThrow(){} function say(){} function markFinal(){} function paintPlay(){} function vshieldFx(){} function checkOver(){}\n' +
    'function owOk(){ return false; } function sqLabel(){ return ""; } function now(){ return 0; } function TEAM(){ return { nm:"" }; } function esc(s){ return s; }\n' +
    'function afterKills(P){ KILLS.push((P && P.killed || []).slice()); }\n' +
    args.code + '\n' +
    'return { setWorld:function(us, sqs, g){ units.length = 0; SQ = {}; SQ_ORDER = []; PEND.length = 0; FALLEN.length = 0; KILLS.length = 0;\n' +
    '    sqs.forEach(function(s){ SQ[s.id] = s; SQ_ORDER.push(s.id); }); us.forEach(function(u){ units.push(u); });\n' +
    '    G.round = g.round; G.turn = g.turn; G.sel = null; },\n' +
    '  units:function(){ return units; }, PEND:PEND, FALLEN:FALLEN, KILLS:KILLS, SQ:function(){ return SQ; },\n' +
    '  f:{ sqById:sqById, sqModels:sqModels, markKey:markKey, countHits:countHits, applyHit:applyHit, applyReroll:applyReroll,\n' +
    '      woundDice:woundDice, saveDice:saveDice, applyWnd:applyWnd, applySav:applySav, nextVictim:nextVictim,\n' +
    '      dealDamage:dealDamage, gloryHeal:gloryHeal, declareCharge:declareCharge } };');
  var S = factory(BT.TYPES, C), F = S.f, plan = args.plan;
  // the world in page form: inches from MI
  function setW(W){
    var sqs = W.squads.map(function(s){ return { id:s.id, k:s.k, side:s.side, pl:s.pl, n0:s.n0, vs:s.vs, windN:s.wn,
      moved:false, adv:false, fell:false, still:true, shot:false, charged:false, chTgt:null, fought:false, advR:0, chDone:false }; });
    var us = W.units.map(function(u){ return { id:u[0], sq:u[1], t:u[2], k:u[2], side:u[3], pl:u[3], hp:u[4], x:u[5]/1000, z:u[6]/1000 }; });
    S.setWorld(us, sqs, W.g);
  }
  function unitsNow(){ return S.units().map(function(u){ return [u.id, u.hp]; }); }
  function fallen(){ return S.FALLEN.filter(function(m){ return m.windWait; }).map(function(m){ return m.id; }); }
  function rng(seed){ var a = seed >>> 0; return function(){ a = (a + 0x6D2B79F5) >>> 0; var t = a; t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61); return ((t ^ (t >>> 14)) >>> 0) / 4294967296; }; }
  var STAGES = ['hit', 'wound', 'save', 'done'];
  function snap(P){ return [STAGES.indexOf(P.stage), P.hits, P.lethal || 0, P.wounds, P.mortal || 0, P.slay || 0, P.saved, P.sv,
    P.rr ? 1 : 0, P.gtg ? 1 : 0, (P.hitR || []).slice()]; }
  var out = { attacks: [], victims: [], damage: [], glory: [], charge: [] };
  plan.attacks.forEach(function(A, ci){
    setW(A.w);
    var r = rng(1000 + ci), d = function(n, extra){ var a = [], k; for (k=0;k<n + extra;k++) a.push(1 + Math.floor(r()*6)); return a; };
    var E = A.p, P = { kind:'atk', how:E.how, u:E.u, t:E.t, side:0, tside:1, att:0, def:1, anm:'', dnm:'', melee:E.how === 'fight',
      ow:E.how === 'ow', d:0, shots:E.shots, who:[], need:E.need, wneed:E.wneed, sv:E.sv, dmg:E.dmg, su:E.su, tr:!!E.tr, lh:!!E.lh,
      dw:!!E.dw, heel:!!E.heel, mk:!!E.mk, hitR:null, woundR:null, saveR:null, hits:0, lethal:0, wounds:0, mortal:0, slay:0,
      saved:0, stage:'hit', since:0 };
    S.PEND.push(P);
    var rec = { dice: {}, steps: [] };
    var hd = P.tr ? d(0, E.extra) : d(P.shots, E.extra); rec.dice.hit = hd;
    F.applyHit(P, hd); rec.steps.push(snap(P));
    if (P.stage === 'wound' && E.rr){ var v = 1 + Math.floor(r()*6); rec.dice.rr = v; F.applyReroll(P, v); rec.steps.push(snap(P)); }
    if (P.stage === 'wound'){ var wd = d(F.woundDice(P), 0); rec.dice.wound = wd; F.applyWnd(P, wd); rec.steps.push(snap(P)); }
    if (P.stage === 'save'){ var sd = d(F.saveDice(P), 0); rec.dice.save = sd; rec.dice.gtg = E.gtg; F.applySav(P, sd, !!E.gtg); rec.steps.push(snap(P)); }
    var t = F.sqById(P.t), s = F.sqById(P.u);
    rec.end = { units: unitsNow(), vs: t.vs || 0, wn: t.windN || 0, fallen: fallen(), kills: S.KILLS.slice(),
      mk: t.mk === F.markKey() ? 1 : 0, shot: s.shot ? 1 : 0, fought: s.fought ? 1 : 0, pend: S.PEND.length };
    out.attacks.push(rec);
  });
  plan.victims.forEach(function(V){
    setW(V.w); var t = F.sqById(V.t), from = V.from == null ? null : F.sqById(V.from), m = F.nextVictim(t, from);
    out.victims.push(m ? m.id : null);
  });
  plan.damage.forEach(function(D){
    setW(D.w); var t = F.sqById(D.t), from = F.sqById(D.from), R = {};
    var n = F.dealDamage(t, from, D.n, D.dmg, !!D.spill, R);
    out.damage.push({ n: n, killed: R.killed, hurt: R.hurt, sh: R.sh, units: unitsNow(), vs: t.vs || 0, fallen: fallen(), wn: t.windN || 0 });
  });
  plan.glory.forEach(function(Q){
    setW(Q.w); var s = F.sqById(Q.s), got = F.gloryHeal(s, Q.n);
    out.glory.push({ got: got, units: unitsNow() });
  });
  plan.charge.forEach(function(Q){
    setW(Q.w); var P = F.declareCharge(F.sqById(Q.s), F.sqById(Q.t)); S.PEND.length = 0;
    out.charge.push(P.need);
  });
  return out;
}

// ---------- the plan (Node, seeded) ----------
function makePlan(types){
  let seed = 20261009;
  const rnd = () => { seed = (seed * 1103515245 + 12345) % 2147483648; return seed / 2147483648; };
  const ri = (a, b) => a + Math.floor(rnd() * (b - a + 1));
  const pick = a => a[ri(0, a.length - 1)];
  const grid10 = v => Math.round(v / 10) * 10;
  const open = types.filter(T => !T.sec && !T.lk);
  const byK = k => { const T = open.find(q => q.k === k); if (!T) throw new Error('type missing: ' + k); return T; };
  const special = open.filter(T => T.hd || T.vsh || T.wind || T.heel || T.w > 2);
  const multi = open.filter(T => T.n >= 3);
  const gk = open.filter(T => T.gk);
  if (!special.length || !multi.length || !gk.length) throw new Error('empty pool');
  ['hanu', 'rbctan', 'achil', 'infantry', 'heavy', 'rwar'].forEach(byK);
  // squad s with alive models around (cx, cz); hurt models at random
  function squad(id, T, side, cx, cz, alive, hurtP){
    const r = Math.round((T.r || 0.8) * 1000), sp = 2 * r + 1500, us = [];
    for (let j = 0; j < alive; j++){
      const hp = rnd() < hurtP ? ri(1, T.w) : T.w;
      us.push([id + '.' + j, id, T.k, side, hp, cx + grid10(ri(-sp, sp)), cz + grid10(ri(-sp, sp))]);
    }
    return { sq: { id, k: T.k, side, pl: side, n0: T.n, vs: T.vsh ? ri(0, T.vsh) : (rnd() < 0.1 ? ri(1, 3) : 0), wn: T.wind ? ri(0, 2) : 0 }, us };
  }
  function world(A, Tt, aliveA, aliveT, hurtT){
    const a = squad('0:0', A, 0, grid10(ri(-20000, 20000)), grid10(ri(-15000, 15000)), aliveA, 0.4);
    const t = squad('1:0', Tt, 1, grid10(ri(-20000, 20000)), grid10(ri(-15000, 15000)), aliveT, hurtT);
    const us = a.us.concat(t.us);
    for (let i = us.length - 1; i > 0; i--){ const j = ri(0, i); const q = us[i]; us[i] = us[j]; us[j] = q; }
    return { g: { round: ri(1, 5), turn: ri(0, 1) }, squads: [a.sq, t.sq], units: us };
  }
  const attacks = [];
  for (let c = 0; c < 320; c++){
    const A = rnd() < 0.15 ? pick(gk) : pick(open), x = rnd(), Tt = x < 0.1 ? byK('hanu') : x < 0.5 ? pick(special) : x < 0.75 ? pick(multi) : pick(open);
    const w = world(A, Tt, ri(1, A.n), rnd() < 0.05 ? 0 : ri(1, Tt.n), rnd() < 0.3 ? 0.5 : 0);
    const how = pick(['shoot', 'shoot', 'fight', 'ow']);
    const tr = how !== 'fight' && rnd() < 0.12;
    const p = { how, u: '0:0', t: '1:0', shots: ri(1, rnd() < 0.2 ? 40 : 12), need: tr ? 0 : how === 'ow' ? 6 : ri(2, 6), wneed: ri(2, 6),
      sv: ri(2, 7), dmg: rnd() < 0.1 ? ri(5, 12) : ri(1, 4), su: rnd() < 0.15 ? 1 : 0, tr, lh: rnd() < 0.2, dw: rnd() < 0.2,
      heel: rnd() < 0.15 || !!Tt.heel, mk: how === 'shoot' && rnd() < 0.2, rr: rnd() < 0.3, gtg: rnd() < 0.3, extra: rnd() < 0.15 ? ri(1, 4) : 0 };
    attacks.push({ w, p });
  }
  const victims = [];
  for (let c = 0; c < 240; c++){
    const Tt = pick(multi), A = pick(open), mode = c % 4;
    const w = world(A, Tt, mode === 1 ? 0 : ri(1, A.n), ri(1, Tt.n), mode === 2 ? 0.3 : 0);
    if (mode === 3){ // ties: target models on a circle about the attacker's single model
      w.units = w.units.filter(u => u[1] !== '0:0'); w.units.unshift(['0:0.0', '0:0', A.k, 0, A.w, 1000, -2000]);
      const R = 5000; let j = 0;
      w.units.forEach(u => { if (u[1] === '1:0'){ const q = [[R, 0], [0, R], [-R, 0], [0, -R], [3000, 4000], [-4000, 3000]][j++ % 6];
        u[4] = Tt.w; u[5] = 1000 + q[0]; u[6] = -2000 + q[1]; } });
    }
    victims.push({ w, t: '1:0', from: mode === 0 && c % 8 === 0 ? null : '0:0' });
  }
  const damage = [];
  for (let c = 0; c < 200; c++){
    const x = rnd(), Tt = x < 0.15 ? byK('hanu') : x < 0.55 ? pick(special) : pick(multi), A = pick(open);
    const w = world(A, Tt, rnd() < 0.1 ? 0 : ri(1, A.n), ri(1, Tt.n), 0.3);
    damage.push({ w, t: '1:0', from: '0:0', n: ri(1, 8), dmg: rnd() < 0.1 ? 999 : ri(1, 6), spill: rnd() < 0.5 ? 1 : 0 });
  }
  const glory = [];
  for (let c = 0; c < 80; c++){
    const T = rnd() < 0.5 ? pick(gk) : pick(multi.filter(q => q.w > 1).concat(gk));
    const w = world(T, byK('infantry'), ri(1, T.n), 1, 0);
    w.units.forEach(u => { if (u[1] === '0:0') u[4] = ri(1, T.w); });
    glory.push({ w, s: '0:0', n: ri(0, 12) });
  }
  const charge = [];
  for (let c = 0; c < 200; c++){
    const A = pick(open), Tt = pick(open), w = world(A, Tt, ri(1, A.n), ri(1, Tt.n), 0);
    if (c % 3 === 0){ // the nearest pair at a whole inch of edge (+-1 grid step): ceil boundaries
      const ra = Math.round((A.r || 0.8) * 1000), rb = Math.round((Tt.r || 0.8) * 1000), L = ra + rb + ri(1, 12) * 1000 + pick([-10, 0, 10]);
      let ka = 0, kb = 0;
      w.units.forEach(u => { if (u[1] === '0:0'){ u[5] = -2000 * ka++; u[6] = 0; } else { u[5] = L + 2000 * kb++; u[6] = 0; } });
    }
    charge.push({ w, s: '0:0', t: '1:0' });
  }
  return { attacks, victims, damage, glory, charge };
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
  let res, plan;
  const browser = await chromium.launch({ executablePath: process.env.CHROMIUM_PATH || undefined, args: ['--no-sandbox'] });
  try {
    const p = await browser.newPage({ viewport: { width: 480, height: 320 } });
    const errs = []; p.on('pageerror', e => errs.push(String(e.stack || e).slice(0, 400)));
    await p.goto('file://' + PAGE);
    await p.waitForFunction('window.BT && window.BT.G && window.BT.TYPES');
    plan = makePlan(await p.evaluate(() => JSON.parse(JSON.stringify(window.BT.TYPES))));
    res = await p.evaluate(pageRun, { code: cuts.map(c => c.text).join('\n'), C, plan });
    if (errs.length) throw new Error('page errors:\n' + errs.join('\n'));
  } finally { await browser.close(); }
  const appVer = (/var APP_VER = '([^']+)'/.exec(src) || [])[1], rulesV = +((/var RULES_V = (\d+)/.exec(src) || [])[1] || 0);
  const head = { about: 'generated by godot/tools/record_pend.js — do not edit; positions are MI ints; attack steps are ' +
      '[stage (0 hit, 1 wound, 2 save, 3 done), hits, lethal, wounds, mortal, slay, saved, sv, rr, gtg, hitR]',
    page: { app_ver: appVer, rules_v: rulesV, consts: C, functions: cuts.map(c => c.name + '@' + c.line) } };
  const pair = (ins, outs) => ins.map((x, i) => ({ in: x, out: outs[i] }));
  const text = serialize(head, { attacks: pair(plan.attacks, res.attacks), victims: pair(plan.victims, res.victims),
    damage: pair(plan.damage, res.damage), glory: pair(plan.glory, res.glory), charge: pair(plan.charge, res.charge) });
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
  res.attacks.forEach((A, i) => { const last = A.steps[A.steps.length - 1]; inc('end_after_' + A.steps.length);
    if (last[5]) inc('slay'); if (last[4]) inc('mortal'); if (last[2]) inc('lethal'); if (last[8]) inc('rr'); if (last[9]) inc('gtg');
    if (A.end.fallen.length) inc('wind_fall'); if (A.end.mk) inc('marked'); if (A.end.units.length < plan.attacks[i].w.units.length) inc('kills');
    if (A.dice.hit.length > plan.attacks[i].p.shots) inc('extra_dice'); });
  res.damage.forEach(D => { if (D.sh) inc('dmg_shield'); if (D.killed.length) inc('dmg_kill'); if (D.fallen.length) inc('dmg_wind'); });
  res.victims.forEach(v => inc(v ? 'victim' : 'victim_none'));
  console.log(Object.keys(cov).sort().map(k => k + ' ' + cov[k]).join(', '));
})().catch(e => { console.error(e.stack || e); process.exit(1); });
