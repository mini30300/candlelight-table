#!/usr/bin/env node
// record_act_edges.js — edge-act recordings for the v10 act dispatcher (godot/tests/oracle/test_oracle_edges.gd).
// The oracle recordings (record_oracle.js) only hold the acts the page itself sends in a normal game. This tool takes a
// recorded game, replays its acts on one page (the joiner, page B of record_oracle.js) and slips seeded "edge" acts in
// between: acts a receiver must survive although no honest sender makes them (a stage that does not match, a squad
// that already acted or is dead, a phase end with another phase's name, a stratagem without CP, an unknown squad,
// legacy codes, a done with another pid, acts after the end of the game, explicit move points, …). Every act goes
// through the Worker's btPost sanitiser first (copied below), as in a real room. After every act the page's board and
// its PEND queue are written; the Godot test replays the same acts through Battle.apply and compares both.
// A page act that pads short dice with d6() (Math.random on the page, fallback:<seq> in v10, §7 #6) cannot be compared:
// the recording stops before the first such act.
//
//   node godot/tools/record_act_edges.js            write godot/tests/oracle/edges/<base>__<seed>.json.gz
//   node godot/tools/record_act_edges.js --check    re-record and compare byte for byte
// Environment: PAGE=<battle-table.html>  CHROMIUM_PATH=<chrome>;  NODE_PATH or tests/node_modules for playwright.
'use strict';
const fs = require('fs'), path = require('path'), zlib = require('zlib');

const ROOT = path.resolve(__dirname, '..', '..');
const PAGE = path.resolve(process.env.PAGE || path.join(ROOT, 'app/src/main/assets/battle-table.html'));
const ORACLE_DIR = path.join(ROOT, 'godot/tests/oracle');
const OUT_DIR = process.env.EDGE_OUT ? path.resolve(process.env.EDGE_OUT) : path.join(ORACLE_DIR, 'edges');
const FORMAT = 1;
// [base recording, fuzz seed, edge acts per recorded act, first recorded act that may be followed by edge acts]
const RUNS = [
  ['two_human_heal_grenade_knights_vs_orcs_kill_ice_flat_30', 1, 0.25, 4],
  ['two_human_heal_grenade_knights_vs_orcs_kill_ice_flat_30', 2, 0.15, 30],
  ['two_human_charge_keep_manual_dice_norse_vs_greek_kill_forest_flat_44', 3, 0.2, 10],
  ['two_human_charge_keep_manual_dice_norse_vs_greek_kill_forest_flat_44', 4, 0.1, 120],
  ['two_human_staged_shots_manual_dice_medieval_vs_swarm_obj_desert_hills_54', 5, 0.2, 8],
  ['two_siam_vs_japan_obj_ice_forest_36', 6, 0.2, 6],
  ['two_greek_vs_soldiers_obj_ruin_hills_48', 7, 0.15, 20],
  ['team_2v2_knights_soldiers_vs_elves_dark_elves_obj_freefire_forest_hills_70', 8, 0.15, 12],
  ['two_fallen_knights_vs_chapter_knights_kill_ice_mountain_56', 9, 0.12, 40],
  ['two_human_idle_timeout_clock_25_medieval_vs_swarm_obj_ruin_hills_26', 10, 0.3, 2],
  ['two_norse_vs_egypt_kill_loki_skin_ruin_hills_80_no_buildings', 525, 0.4, 2],
  ['two_titans_hound_walker_vs_empire_colossus_kill_ruin_flat_104', 530, 0.4, 2],
  ['two_alien_swarm_vs_ancient_robots_kill_desert_mountain_72_sparse', 537, 0.6, 40],
  ['two_dark_elves_vs_blue_empire_obj_hidden_units_forest_hills_90', 547, 0.6, 40],
  ['two_human_claude_form_moves_soldiers_vs_orcs_obj_ruin_hills_50', 542, 0.6, 40],
];
// EDGE_RUNS='[[base, seed, rate, from], …]' records other runs (exploration; the committed set is RUNS)
if (process.env.EDGE_RUNS){ RUNS.length = 0; RUNS.push(...JSON.parse(process.env.EDGE_RUNS)); }
// edge acts after the game is over (page parity: they are applied, advance returns at once)
const AFTER_OVER = 12;

function loadPlaywright(){
  try { return require('playwright'); }
  catch (e) { return require(path.join(ROOT, 'tests/node_modules/playwright')); }
}
function readRecording(file){
  const buf = fs.readFileSync(file);
  return JSON.parse((file.endsWith('.gz') ? zlib.gunzipSync(buf) : buf).toString('utf8'));
}
// record_oracle.js's in-page library (window.ORACLE), taken from its source so both tools set a page up the same way
function pageLibSource(){
  const src = fs.readFileSync(path.join(__dirname, 'record_oracle.js'), 'utf8');
  const a = src.indexOf('function pageLib(){'), b = src.indexOf('\n  return true;\n}\n', a);
  if (a < 0 || b < 0) throw new Error('pageLib not found in record_oracle.js');
  return src.slice(a, b + '\n  return true;\n}\n'.length);
}

// ---------- the Worker's act sanitiser (candlelight-server worker.js, btPost action "act") ----------
function clampStr(s, n){ return String(s ?? '').slice(0, n); }
function workerAct(raw){
  const num = v => Math.max(-9999, Math.min(9999, Number(v) || 0));
  const dice = v => (Array.isArray(v) ? v.slice(0, 60).map(x => Math.max(1, Math.min(6, Math.round(Number(x)) || 1))) : []);
  const one = v => Math.max(1, Math.min(6, Math.round(Number(v)) || 1));
  const id = v => clampStr(v, 20);
  const pts = v => (Array.isArray(v) ? v.slice(0, 40).map(q => Array.isArray(q) ? [num(q[0]), num(q[1])] : [0, 0]) : []);
  const ph = v => (['cmd', 'move', 'shoot', 'charge', 'fight'].includes(v) ? v : '');
  const how = v => (['shoot', 'fight', 'ow'].includes(v) ? v : 'shoot');
  let act = null;
  if (raw.a === 'move')    act = { a: 'move', u: id(raw.u), x: num(raw.x), z: num(raw.z) };
  if (raw.a === 'endturn') act = { a: 'endturn' };
  if (raw.a === 'shoot')   act = { a: 'shoot', u: id(raw.u), t: id(raw.t), how: how(raw.how), hit: dice(raw.hit), wound: dice(raw.wound), save: dice(raw.save) };
  if (raw.a === 'atk')     act = { a: 'atk', u: id(raw.u), t: id(raw.t), how: how(raw.how), hit: dice(raw.hit) };
  if (raw.a === 'wnd')     act = { a: 'wnd', u: id(raw.u), t: id(raw.t), wound: dice(raw.wound) };
  if (raw.a === 'sav')     act = { a: 'sav', u: id(raw.u), t: id(raw.t), save: dice(raw.save), gtg: raw.gtg ? 1 : 0 };
  if (raw.a === 'heal')    act = { a: 'heal', u: id(raw.u), t: id(raw.t), roll: one(raw.roll) };
  if (raw.a === 'skip')    act = { a: 'skip', u: id(raw.u), ph: ph(raw.ph) };
  if (raw.a === 'done')    act = { a: 'done', ph: ph(raw.ph) };
  if (raw.a === 'smove')   act = { a: 'smove', u: id(raw.u), how: ['move', 'adv', 'fb'].includes(raw.how) ? raw.how : 'move',
                                   ...(Array.isArray(raw.to) ? { to: pts(raw.to) } : { x: num(raw.x), z: num(raw.z) }) };
  if (raw.a === 'stay')    act = { a: 'stay', u: id(raw.u) };
  if (raw.a === 'adv')     act = { a: 'adv', u: id(raw.u), roll: one(raw.roll) };
  if (raw.a === 'rr')      act = { a: 'rr', u: id(raw.u), t: id(raw.t), v: one(raw.v) };
  if (raw.a === 'shock')   act = { a: 'shock', u: id(raw.u), roll: dice(raw.roll).slice(0, 2), brave: raw.brave ? 1 : 0 };
  if (raw.a === 'chg')     act = { a: 'chg', u: id(raw.u), t: id(raw.t) };
  if (raw.a === 'ow')      act = { a: 'ow', u: id(raw.u), t: id(raw.t), use: raw.use ? 1 : 0 };
  if (raw.a === 'chr')     act = { a: 'chr', u: id(raw.u), t: id(raw.t), roll: dice(raw.roll).slice(0, 2), rr: raw.rr ? 1 : 0, keep: raw.keep ? 1 : 0 };
  if (raw.a === 'cmove')   act = { a: 'cmove', u: id(raw.u), t: id(raw.t), to: pts(raw.to) };
  if (raw.a === 'gren')    act = { a: 'gren', u: id(raw.u), t: id(raw.t), roll: dice(raw.roll).slice(0, 6) };
  if (raw.a === 'rez')     act = { a: 'rez', u: id(raw.u), roll: dice(raw.roll).slice(0, 10) };
  if (raw.a === 'endph')   act = { a: 'endph', ph: ph(raw.ph) };
  return act;
}

// ---------- seeded edge acts ----------
function xs(seed){ let x = (seed >>> 0) || 1; return () => { x ^= x << 13; x >>>= 0; x ^= x >>> 17; x ^= x << 5; x >>>= 0; return x; }; }
function edgeMaker(seed){
  const r = xs(seed * 2654435761 ^ 0x51ED270B), n = k => r() % k, pick = a => a[n(a.length)], chance = p => (r() % 1000000) / 1000000 < p;
  const dice = k => { const o = []; for (let i = 0; i < k; i++) o.push(1 + n(6)); return o; };
  const PH = ['', 'cmd', 'move', 'shoot', 'charge', 'fight', 'nope'];
  // a point on the 0.01" grid within the table
  const pt = (x, z, w, d, spread) => {
    const W = w / 2 - 0.6, D = d / 2 - 0.6, c = (v, L) => Math.max(-L, Math.min(L, v));
    return [Math.round(c(x + (n(2001) - 1000) / 1000 * spread, W) * 100) / 100, Math.round(c(z + (n(2001) - 1000) / 1000 * spread, D) * 100) / 100]; };
  return function make(S){
    // S = { phase, over, w, d, alive: [{id, side, pl}], ids: [every squad id seen], pend: [{kind,u,t,stage}], units: [{id, sq, x, z}] }
    const sq = () => chance(0.85) && S.alive.length ? pick(S.alive).id : chance(0.7) ? pick(S.ids) : pick(['', 'zz', '0:99']);
    const pts = (u, spread) => { const ms = S.units.filter(m => m.sq === u), o = [];
      if (chance(0.1)) return o;
      const k = chance(0.8) ? ms.length : n(ms.length + 3);
      for (let i = 0; i < k; i++){ const m = ms.length ? ms[i % ms.length] : { x: 0, z: 0 }; o.push(pt(m.x, m.z, S.w, S.d, spread)); }
      return o; };
    if (S.pend.length && chance(0.4)){
      const P = pick(S.pend), u = P.u, t = P.t || sq();
      if (P.kind === 'atk') return pick([
        () => ({ a: 'atk', u, t, how: pick(['shoot', 'fight', 'ow', 'x']), hit: dice(60) }),
        () => ({ a: 'wnd', u, t, wound: dice(60) }),
        () => ({ a: 'sav', u, t, save: dice(60), gtg: n(2) }),
        () => ({ a: 'rr', u, t, v: 1 + n(6) }),
        () => ({ a: 'wnd', u, wound: dice(60) }),           // no t: the page's pendAt takes any target
      ])();
      if (P.kind === 'chg') return pick([
        () => ({ a: 'ow', u, t, use: n(2) }),
        () => ({ a: 'chr', u, t, roll: dice(2), rr: chance(0.3) ? 1 : 0, keep: chance(0.3) ? 1 : 0 }),
        () => ({ a: 'cmove', u, t, to: pts(u, 3) }),
        () => ({ a: 'chg', u, t }),
      ])();
      if (P.kind === 'shock') return { a: 'shock', u, roll: dice(2), brave: n(2) };
      if (P.kind === 'rez') return { a: 'rez', u, roll: dice(10) };
    }
    const u = sq(), t = sq();
    return pick([
      () => ({ a: 'stay', u }),
      () => ({ a: 'skip', u, ph: pick(PH) }),
      () => ({ a: 'adv', u, roll: 1 + n(6) }),
      () => ({ a: 'atk', u, t, how: pick(['shoot', 'fight', 'ow']), hit: dice(60) }),
      () => ({ a: 'shoot', u, t, how: pick(['shoot', 'fight']), hit: dice(60), wound: dice(60), save: dice(60) }),
      () => ({ a: 'wnd', u, t, wound: dice(60) }),
      () => ({ a: 'sav', u, t, save: dice(60), gtg: n(2) }),
      () => ({ a: 'rr', u, t, v: 1 + n(6) }),
      () => ({ a: 'shock', u, roll: dice(2), brave: n(2) }),
      () => ({ a: 'rez', u, roll: dice(10) }),
      () => ({ a: 'chg', u, t }),
      () => ({ a: 'ow', u, t, use: n(2) }),
      () => ({ a: 'chr', u, t, roll: dice(2), rr: n(2), keep: n(2) }),
      () => ({ a: 'cmove', u, t, to: pts(u, 2) }),
      () => ({ a: 'gren', u, t, roll: dice(6) }),
      () => ({ a: 'heal', u, t, roll: 1 + n(6) }),
      () => ({ a: 'done', ph: pick(PH), pid: pick(['A', 'C']) }),
      () => ({ a: 'endph', ph: pick(PH) }),
      () => ({ a: 'endturn' }),
      () => ({ a: 'move', u, x: n(20) - 10, z: n(20) - 10 }),
      () => ({ a: 'smove', u, to: pts(u, 4), how: pick(['move', 'adv', 'fb', 'run']) }),
      () => ({ a: 'smove', u, to: [], how: 'move' }),
    ])();
  };
}

// ---------- page side ----------
function edgeLib(){
  var BT = window.BT, E = window.EDGE = {};
  E.state = function(){ var G = BT.G, b = BT.board();
    return { phase: G.phase, over: !!G.over, w: BT.table.w, d: BT.table.d,
      alive: BT.squads().map(function(s){ return { id: s.id, side: s.side, pl: s.pl }; }),
      ids: b.squads.map(function(s){ return s.id; }),
      pend: BT.tray().pend.map(function(P){ return { kind: P.kind, u: P.u, t: P.t || '', stage: P.stage }; }),
      units: b.units.map(function(u){ return { id: u.id, sq: u.sq, x: u.x, z: u.z }; }) }; };
  // apply one act as a room act; null when the page padded dice (d6 drew from the queue) — not comparable
  E.apply = function(a){ var SENT = 400, q = [], i; for (i = 0; i < SENT; i++) q.push(1 + (i % 6));
    BT.dice(q); BT.applyAct(a); var padded = BT.diceLeft() !== SENT; BT.dice([]);
    if (padded) return null;
    return { board: BT.board(), pend: BT.tray().pend.map(function(P){ return { kind: P.kind, u: P.u, t: P.t || '', stage: P.stage,
      hits: P.hits | 0, wounds: P.wounds | 0 }; }) }; };
  return true;
}

function serialize(rec){
  const parts = [];
  for (const k of Object.keys(rec)){
    const v = rec[k];
    if (Array.isArray(v) && v.length && typeof v[0] === 'object') parts.push(JSON.stringify(k) + ': [\n' + v.map(x => JSON.stringify(x)).join(',\n') + '\n]');
    else parts.push(JSON.stringify(k) + ': ' + JSON.stringify(v));
  }
  return '{\n' + parts.join(',\n') + '\n}\n';
}

async function recordRun(browser, libSrc, run){
  const [base, seed, rate, from] = run;
  const rec = readRecording(path.join(ORACLE_DIR, base + '.json.gz'));
  const B = await browser.newPage({ viewport: { width: 480, height: 320 } });
  const errs = []; B.on('pageerror', e => errs.push(String(e.stack || e).slice(0, 400)));
  try {
    await B.goto('file://' + PAGE); await B.waitForFunction('window.BT && window.BT.G');
    await B.evaluate('(function(){\n' + libSrc + '\nreturn pageLib();\n})()'); await B.evaluate(edgeLib);
    const sb = await B.evaluate(([s, d]) => ORACLE.setup(s, 'B', d), [rec.scenario_def, rec.deps]);
    if (JSON.stringify(sb.board0) !== JSON.stringify(rec.board0)) throw new Error('board0 differs from the base recording');
    const make = edgeMaker(seed), pickR = xs(seed * 40503 + 7), coin = p => (pickR() % 1000000) / 1000000 < p;
    const out = { format: FORMAT, base, seed, rate, from, acts: [], edge: [], boards: [], pend: [], stop: '' };
    const step = async (raw, isEdge) => {
      const a = workerAct(raw); if (!a) throw new Error('the Worker refuses ' + JSON.stringify(raw));
      a.pid = raw.a === 'done' && raw.pid ? raw.pid : 'A';
      const r = await B.evaluate(([x]) => EDGE.apply(x), [a]);
      if (errs.length) throw new Error('page error after ' + JSON.stringify(a) + ': ' + errs[0]);
      if (!r) return false;
      out.acts.push(a); out.edge.push(isEdge ? 1 : 0); out.boards.push(r.board); out.pend.push(r.pend);
      return true;
    };
    let i;
    for (i = 0; i < rec.acts.length; i++){
      if (i >= from){
        while (coin(rate)){
          const S = await B.evaluate(() => EDGE.state());
          const e = make(S);
          if (!(await step(e, true))){ out.stop = 'edge act ' + out.acts.length + ' pads dice: ' + JSON.stringify(e).slice(0, 120); break; }
        }
        if (out.stop) break;
      }
      if (!(await step(rec.acts[i], false))){ out.stop = 'recorded act ' + i + ' pads dice after the edge acts'; break; }
    }
    if (!out.stop){
      for (let k = 0; k < AFTER_OVER; k++){
        const S = await B.evaluate(() => EDGE.state());
        const e = make(S);
        if (!(await step(e, true))){ out.stop = 'edge act after the end pads dice'; break; }
      }
      if (!out.stop) out.stop = 'end';
    }
    out.recorded = i;
    return out;
  } finally { await B.close(); }
}

(async () => {
  const check = process.argv.includes('--check');
  const { chromium } = loadPlaywright();
  const browser = await chromium.launch({ executablePath: process.env.CHROMIUM_PATH || undefined, args: ['--no-sandbox'] });
  const libSrc = pageLibSource();
  let bad = 0;
  fs.mkdirSync(OUT_DIR, { recursive: true });
  try {
    for (const run of RUNS){
      const name = run[0] + '__' + run[1];
      const out = await recordRun(browser, libSrc, run);
      const text = Buffer.from(serialize(out), 'utf8');
      const file = path.join(OUT_DIR, name + '.json.gz');
      const edges = out.edge.reduce((s, v) => s + v, 0), last = out.boards.length ? out.boards[out.boards.length - 1] : null;
      const info = `${out.acts.length} acts (${edges} edge acts, ${out.recorded} recorded), over ${last ? last.over : '-'} :: ${out.stop}`;
      if (check){
        const same = fs.existsSync(file) && zlib.gunzipSync(fs.readFileSync(file)).equals(text);
        console.log((same ? 'identical ' : 'DIFFERS   ') + name + ': ' + info); if (!same) bad++;
      } else {
        fs.writeFileSync(file, zlib.gzipSync(text, { level: 9 }));
        console.log('wrote ' + name + ': ' + info + ', ' + (fs.statSync(file).size / 1024).toFixed(0) + ' KB');
      }
    }
  } finally { await browser.close(); }
  process.exit(bad ? 1 : 0);
})().catch(e => { console.error('THREW', e); process.exit(1); });
