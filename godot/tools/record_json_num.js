#!/usr/bin/env node
// record_json_num.js — sample how numbers cross the wire in the room protocol, for the Godot net layer
// (godot/net/json_num.gd JsonNum; ARCHITECTURE §5, R1_PORT_SPEC §2 "wire points" and §4). Read-only on the page and on
// the Worker.
//
//   node godot/tools/record_json_num.js            write the fixture
//   node godot/tools/record_json_num.js --check    re-run and fail unless the file is byte-identical
// Environment: PAGE=<battle-table.html>  WORKER=<candlelight-server/worker.js>  CHROMIUM_PATH=<chrome>
//              NODE_PATH or tests/node_modules for playwright.
//
// Page (loaded headless in Chromium, run in its V8):
//   points  JSON.stringify(+(mi/1000).toFixed(2)) — how the page writes every act point (chargeSpots 31870, planMove
//           34158) — for a sweep of MI and the x.xx5 steps up to the Worker's ±9999" cap;
//   bodies  JSON.stringify({pid, act}) — netSend's POST body — for acts the page really sent in the oracle recordings
//           (up to four of each code, every Claude-form smove {x, z});
//   setups  JSON.stringify(BT.curSetup()) after the page's own setters (setBuildings quantises the density).
// Worker (functions cut from worker.js and run in Node): btSetup (the room setup every device reads back), btList and
// btSkins (the /list payload), the /dep clamp — so the net layer is checked against every shape the server stores.
//
// Output: godot/tests/unit/fixtures/json_num/page_samples.json
'use strict';
const fs = require('fs'), path = require('path'), zlib = require('zlib'), vm = require('vm');

const ROOT = path.resolve(__dirname, '..', '..');
const PAGE = path.resolve(process.env.PAGE || path.join(ROOT, 'app/src/main/assets/battle-table.html'));
const ORACLE = path.join(ROOT, 'godot/tests/oracle');
const OUT = path.join(ROOT, 'godot/tests/unit/fixtures/json_num/page_samples.json');
const CHECK = process.argv.includes('--check');

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
function loadPlaywright(){
  try { return require('playwright'); }
  catch (e) { return require(path.join(ROOT, 'tests/node_modules/playwright')); }
}

const src = fs.readFileSync(PAGE, 'utf8');
const APP_VER = (src.match(/var APP_VER = '([^']+)'/) || [])[1] || null;
const RULES_V = +((src.match(/var RULES_V = (\d+)/) || [])[1] || 0);

// ---------- the Worker's pieces ----------
const wsrc = fs.readFileSync(findWorker(), 'utf8');
// a function from its anchor to the brace closing its body (quoted strings skipped)
function cutFn(anchor){
  const a = wsrc.indexOf(anchor);
  if (a < 0 || wsrc.indexOf(anchor, a + 1) >= 0) throw new Error('worker anchor missing or not unique: ' + anchor);
  let i = wsrc.indexOf('{', a), depth = 0;
  for (; i < wsrc.length; i++){
    const c = wsrc[i];
    if (c === '"' || c === "'"){ const q = c; i++; while (wsrc[i] !== q){ if (wsrc[i] === '\\') i++; i++; } continue; }
    if (c === '{') depth++;
    else if (c === '}' && --depth === 0) return wsrc.slice(a, i + 1);
  }
  throw new Error('unterminated ' + anchor);
}
function cutConst(name){
  const m = wsrc.match(new RegExp('(?:^|[\\s,])' + name + ' = ([^,;]+)[,;]', 'm'));
  if (!m) throw new Error('worker const missing: ' + name);
  return 'const ' + name + ' = ' + m[1] + ';';
}
function cutDep(){
  const a = wsrc.indexOf('const dep = Array.isArray(body.dep)');
  const b = wsrc.indexOf(': null;', a);
  if (a < 0 || b < 0) throw new Error('worker /dep clamp not found');
  return wsrc.slice(a, b + 7);
}
const W_SRC = [cutConst('BT_RULES'), cutConst('BT_LIST_LEN'), cutConst('BT_SLOT_MAX'), 'const BT_MODES = ' +
  wsrc.match(/const BT_MODES = (\[[^\]]*\]);/)[1] + ';', 'const BT_THEMES = ' + wsrc.match(/const BT_THEMES = (\[[^\]]*\]);/)[1] + ';',
  'const BT_TERRAINS = ' + wsrc.match(/const BT_TERRAINS = (\[[^\]]*\]);/)[1] + ';',
  cutFn('function btDens('), cutFn('function btList('), cutFn('function btSkins('), cutFn('function btVer('),
  cutFn('function btSetup('), 'function depOf(body){ ' + cutDep() + ' return dep; }'].join('\n');
const W = vm.runInNewContext(W_SRC + '\n({ btSetup, btList, btSkins, depOf, BT_RULES, BT_LIST_LEN, BT_SLOT_MAX })', {});

const WORKER_SETUPS = [
  {},
  { theme: 'forest', terrain: 'mountain', buildings: false, density: 0.05, seed: 99999, w: 180, mode: 'ffa', teams: 8,
    budget: 40000, freeFire: true, clock: 50, goal: 'kill', rounds: 10, v: 9 },
  { theme: 'ice', terrain: 'flat', density: 2.5, seed: 1, w: 24, mode: 'team', perTeam: 4, budget: 200, clock: 0, rounds: 3, v: 9 },
  { theme: 'desert', terrain: 'forest', density: 0.37, seed: 4242.4, w: 77.6, mode: 'pvp', budget: 1234.5, clock: 25, v: 7 },
  { density: 1.13, w: 63, mode: 'pve', v: 2 },
  { density: '', seed: 'x', w: null, mode: 'bogus', teams: 99, v: '9' },
  { density: 1.874, w: 130, mode: 'ffa', teams: 3, budget: 39999.5, rounds: 7.5, v: 9 },
];
const WORKER_LISTS = [
  { list: [1, 2, 3], sk: { loki: 1 } },
  { list: [0, 99, 100, -3, 2.5, 7.49, '4', null], sk: { loki: 1.4, Bad: 2, x: 0, y: 10, ok_1: 9 } },
  { list: null, sk: [] },
  { list: Array.from({ length: 600 }, (_, i) => i % 101), sk: null },
];
const WORKER_DEPS = [[12.34, -5.5], [-200, 200], [250, -999], null, [1], [0, 0], [-0.004, 0.01]];

// ---------- oracle acts (page-sent) ----------
function oracleActs(){
  const files = fs.readdirSync(ORACLE).filter(f => f.endsWith('.json.gz')).sort();
  const per = {}, out = [];
  for (const f of files){
    const rec = JSON.parse(zlib.gunzipSync(fs.readFileSync(path.join(ORACLE, f))).toString('utf8'));
    rec.acts.forEach((a, i) => {
      const claude = a.a === 'smove' && !Array.isArray(a.to);
      const n = per[a.a] || 0;
      if (claude ? n >= 10 : n >= 4) return;
      per[a.a] = n + 1;
      out.push({ scenario: rec.scenario, i, act: a });
    });
  }
  return out;
}

// ---------- what runs in the page ----------
function pageRun(args){
  var BT = window.BT, out = {}, mi, t = [];
  var pt = function(m){ return JSON.stringify(+(m / 1000).toFixed(2)); };
  for (mi = args.points.from; mi <= args.points.to; mi++) t.push(pt(mi));
  out.points = t.join(',');
  out.points_extra = args.points.extra.map(function(m){ return [m, pt(m)]; });
  out.bodies = args.acts.map(function(c, k){ var pid = 'b' + (1000 + k * 37).toString(36);
    return { pid: pid, text: JSON.stringify({ pid: pid, act: c.act }) }; });
  out.setups = args.setups.map(function(s){
    var G = BT.G;
    BT.setTheme(s.theme); BT.setTerrain(s.terrain); BT.setBuildings(s.buildings, s.density);
    G.mode = s.mode; G.teams = s.teams; G.perTeam = s.perTeam; G.budget = s.budget; G.freeFire = s.freeFire;
    G.clock = s.clock; G.goal = s.goal; G.rounds = s.rounds;
    return JSON.stringify(BT.curSetup());
  });
  return out;
}
const PAGE_SETUPS = [
  { theme: 'ruin', terrain: 'hills', buildings: true, density: 1, mode: 'pvp', teams: 2, perTeam: 1, budget: 500, freeFire: false, clock: 0, goal: 'obj', rounds: 5 },
  { theme: 'forest', terrain: 'mountain', buildings: false, density: 0.05, mode: 'ffa', teams: 8, perTeam: 1, budget: 40000, freeFire: true, clock: 50, goal: 'kill', rounds: 10 },
  { theme: 'desert', terrain: 'flat', buildings: true, density: 0.37, mode: 'team', teams: 2, perTeam: 4, budget: 2000, freeFire: false, clock: 25, goal: 'obj', rounds: 3 },
  { theme: 'ice', terrain: 'forest', buildings: true, density: 2.4, mode: 'custom', teams: 2, perTeam: 3, budget: 750, freeFire: false, clock: 25, goal: 'obj', rounds: 7 },
  { theme: 'ruin', terrain: 'hills', buildings: true, density: 1.13, mode: 'spectator', teams: 3, perTeam: 1, budget: 3000, freeFire: true, clock: 0, goal: 'kill', rounds: 4 },
  { theme: 'desert', terrain: 'hills', buildings: true, density: 0.951, mode: 'pve', teams: 2, perTeam: 1, budget: 200, freeFire: false, clock: 50, goal: 'obj', rounds: 6 },
];

function serialize(obj){
  const parts = [];
  for (const k of Object.keys(obj)){
    const v = obj[k];
    if (Array.isArray(v) && v.length && typeof v[0] === 'object') parts.push(JSON.stringify(k) + ': [\n' + v.map(x => JSON.stringify(x)).join(',\n') + '\n]');
    else parts.push(JSON.stringify(k) + ': ' + JSON.stringify(v));
  }
  return '{\n' + parts.join(',\n') + '\n}\n';
}

(async function main(){
  const acts = oracleActs();
  const points = { from: -2600, to: 2600, extra: [] };
  for (let k = 0; k <= 9999; k += k < 200 ? 7 : 997) [5, 15, 995, 4, 6, 125, 875].forEach(r => points.extra.push(k * 1000 + r, -(k * 1000 + r)));
  points.extra.push(9999000, -9999000, 9998995, 180000, -180000);
  const { chromium } = loadPlaywright();
  const browser = await chromium.launch({ executablePath: process.env.CHROMIUM_PATH || undefined, args: ['--no-sandbox'] });
  let res;
  try {
    const p = await browser.newPage({ viewport: { width: 480, height: 320 } });
    const errs = []; p.on('pageerror', e => errs.push(String(e.stack || e).slice(0, 400)));
    await p.goto('file://' + PAGE);
    await p.waitForFunction('window.BT && window.BT.G && window.BT.curSetup');
    res = await p.evaluate(pageRun, { points, acts, setups: PAGE_SETUPS });
    if (errs.length) throw new Error('page errors:\n' + errs.join('\n'));
  } finally { await browser.close(); }

  const fix = {
    about: 'generated by godot/tools/record_json_num.js — do not edit; points = the page\'s JSON.stringify(+(mi/1000).toFixed(2)) for mi from..to (comma-joined) and extra [mi, text]; bodies = netSend\'s POST text for acts the page sent (oracle recordings); setups = JSON.stringify(curSetup()); worker_* = the Worker\'s btSetup / btList+btSkins / dep clamp in = what a client posted, out = what the room stores (JSON text)',
    page: { app_ver: APP_VER, rules_v: RULES_V },
    worker: { bt_rules: W.BT_RULES, list_len: W.BT_LIST_LEN, slot_max: W.BT_SLOT_MAX },
    points: { from: points.from, to: points.to, text: res.points },
    points_extra: res.points_extra,
    bodies: res.bodies.map((b, i) => ({ scenario: acts[i].scenario, i: acts[i].i, pid: b.pid, text: b.text })),
    setups: res.setups.map(t => ({ text: t })),
    worker_setups: WORKER_SETUPS.map(s => ({ in: JSON.stringify(s), out: JSON.stringify(W.btSetup(s)) })),
    worker_lists: WORKER_LISTS.map(s => ({ in: JSON.stringify(s), out: JSON.stringify({ list: W.btList(s.list), sk: W.btSkins(s.sk) }) })),
    worker_deps: WORKER_DEPS.map(d => ({ in: JSON.stringify(d), out: JSON.stringify(W.depOf({ dep: d })) })),
  };
  const text = serialize(fix);
  if (CHECK){
    const old = fs.existsSync(OUT) ? fs.readFileSync(OUT, 'utf8') : '';
    console.log((old === text ? 'same    ' : 'DIFFERS ') + path.relative(ROOT, OUT));
    if (old !== text) process.exit(1);
  } else {
    fs.mkdirSync(path.dirname(OUT), { recursive: true }); fs.writeFileSync(OUT, text);
    console.log('wrote ' + path.relative(ROOT, OUT) + ' (' + Buffer.byteLength(text) + ' B): points ' +
      (points.to - points.from + 1) + ' + ' + points.extra.length + ', bodies ' + acts.length + ', setups ' + PAGE_SETUPS.length);
  }
})().catch(e => { console.error(e.stack || e); process.exit(1); });
