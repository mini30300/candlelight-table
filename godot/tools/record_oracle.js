#!/usr/bin/env node
// record_oracle.js — record reference games from the old page (battle-table.html) for the Godot rules port.
// Each scenario of godot/tests/oracle/scenarios.json is played on page A (bots, plus one scripted human seat when the
// scenario has one) while page B only replays the acts A sent, one by one, and gives the board after every act — the
// same two-device check as tests/battle/net_sync.js. The result is godot/tests/oracle/<name>.json (or .json.gz).
//
//   node godot/tools/record_oracle.js                 record every scenario
//   node godot/tools/record_oracle.js --only a,b      only these scenarios (repeatable)
//   node godot/tools/record_oracle.js --check         re-record into a temp folder and diff byte for byte (determinism)
//   node godot/tools/record_oracle.js --histogram     count act codes over the recordings; fail unless every code occurs
//   --gzip / --plain   write .json.gz (default when scenarios.json says "gzip": true) or plain .json
//   --out <dir>        write somewhere else (the check uses this)      --cap <n>  step cap override
// Environment: PAGE=<battle-table.html>  CHROMIUM_PATH=<chrome>  (as tests/run.sh);  NODE_PATH or tests/node_modules for playwright.
//
// Determinism: the page draws its dice from BT.dice()'s queue, which this script keeps filled from its own seeded
// generator, so a re-run of a scenario is byte-identical (see README.md). No wall-clock value enters a recording.
'use strict';
const fs = require('fs'), path = require('path'), os = require('os'), zlib = require('zlib');

const ROOT = path.resolve(__dirname, '..', '..');
const PAGE = path.resolve(process.env.PAGE || path.join(ROOT, 'app/src/main/assets/battle-table.html'));
const ORACLE_DIR = path.join(ROOT, 'godot/tests/oracle');
const SCEN_FILE = path.join(ORACLE_DIR, 'scenarios.json');
// the server checkout next to this repo (or next to the main checkout when this is a git worktree under .claude/)
const WORKER = [process.env.WORKER, path.join(ROOT, '..', 'candlelight-server', 'worker.js'),
  path.join(ROOT, '..', '..', '..', '..', 'candlelight-server', 'worker.js')].filter(Boolean).find(f => fs.existsSync(f)) || '';

function loadPlaywright(){
  try { return require('playwright'); }
  catch (e) { return require(path.join(ROOT, 'tests/node_modules/playwright')); }
}

// ---------- command line ----------
const argv = process.argv.slice(2), opt = { only: [], check: false, histogram: false, gzip: null, out: null, cap: null };
for (let i = 0; i < argv.length; i++){
  const a = argv[i];
  if (a === '--only') opt.only.push(...String(argv[++i] || '').split(',').filter(Boolean));
  else if (a.startsWith('--only=')) opt.only.push(...a.slice(7).split(',').filter(Boolean));
  else if (a === '--check') opt.check = true;
  else if (a === '--histogram') opt.histogram = true;
  else if (a === '--gzip') opt.gzip = true;
  else if (a === '--plain') opt.gzip = false;
  else if (a === '--out') opt.out = path.resolve(argv[++i]);
  else if (a === '--cap') opt.cap = +argv[++i];
  else { console.error('unknown argument ' + a); process.exit(2); }
}

// ---------- files ----------
function readRecording(file){
  const buf = fs.readFileSync(file);
  return JSON.parse((file.endsWith('.gz') ? zlib.gunzipSync(buf) : buf).toString('utf8'));
}
function listRecordings(dir){
  return fs.readdirSync(dir).filter(f => /\.json(\.gz)?$/.test(f) && f !== 'scenarios.json' && f !== 'allowlist.json').sort()
    .map(f => path.join(dir, f));
}
// one element per line for the long arrays, so a diff reads act by act; key order is insertion order (fixed)
function serialize(rec){
  const parts = [];
  for (const k of Object.keys(rec)){
    const v = rec[k];
    if (Array.isArray(v) && v.length && typeof v[0] === 'object') parts.push(JSON.stringify(k) + ': [\n' + v.map(x => JSON.stringify(x)).join(',\n') + '\n]');
    else parts.push(JSON.stringify(k) + ': ' + JSON.stringify(v));
  }
  return '{\n' + parts.join(',\n') + '\n}\n';
}
function writeRecording(dir, name, rec, gz){
  fs.mkdirSync(dir, { recursive: true });
  const text = Buffer.from(serialize(rec), 'utf8');
  const file = path.join(dir, name + (gz ? '.json.gz' : '.json'));
  fs.writeFileSync(file, gz ? zlib.gzipSync(text, { level: 9 }) : text);   // node's gzip header carries no time stamp
  return { file, bytes: fs.statSync(file).size, raw: text.length };
}
const pageSrc = fs.readFileSync(PAGE, 'utf8');
const APP_VER = (pageSrc.match(/var APP_VER = '([^']+)'/) || [])[1] || null;
const RULES_V = +((pageSrc.match(/var RULES_V = (\d+)/) || [])[1] || 0);
// every act code the page itself sends (netSend({ a:'…' })) — the set the histogram must cover
function pageActCodes(){
  const out = new Set(); const re = /netSend\(\{ a:'([a-z]+)'/g; let m;
  while ((m = re.exec(pageSrc))) out.add(m[1]);
  return [...out].sort();
}
// what the Worker accepts (candlelight-server/worker.js, `raw.a === "…"`), when that checkout is next to this repo
function workerActCodes(){
  if (!fs.existsSync(WORKER)) return null;
  const out = new Set(); const re = /raw\.a === "([a-z]+)"/g; let m; const src = fs.readFileSync(WORKER, 'utf8');
  while ((m = re.exec(src))) out.add(m[1]);
  return [...out].sort();
}

// ---------- the code that runs inside the page ----------
// Installed as window.ORACLE on both pages. Everything the scenario needs from the page goes through window.BT
// (docs/CODEMAP.md §2.12) or the real buttons; nothing here touches the page's own state directly except G's setup
// fields, exactly as tests/battle/net_sync.js does.
function pageLib(){
  var BT = window.BT, O = window.ORACLE = { H: null };
  function xs(seed){ var x = (seed >>> 0) || 1; return function(){ x ^= x << 13; x >>>= 0; x ^= x >>> 17; x ^= x << 5; x >>>= 0; return x; }; }
  O.dice = function(n){ var out = [], i; for (i = 0; i < n; i++) out.push(1 + (O.rngD() % 6)); return out; };
  O.rnd = function(){ return (O.rngH() % 1000000) / 1000000; };
  O.typeOf = function(k){ for (var i = 0; i < BT.TYPES.length; i++) if (BT.TYPES[i].k === k) return BT.TYPES[i]; return null; };
  // a list entry is [unit key, count]; "hidden:<flag>" picks the first datasheet carrying that flag (sec, lk)
  O.resolveList = function(entries){
    var l = [], i; for (i = 0; i < BT.TYPES.length; i++) l.push(0);
    entries.forEach(function(e){ var key = e[0], n = e[1] | 0, idx = -1;
      if (key.indexOf('hidden:') === 0){ var flag = key.slice(7); for (var j = 0; j < BT.TYPES.length; j++) if (BT.TYPES[j][flag]){ idx = j; break; } }
      else for (var q = 0; q < BT.TYPES.length; q++) if (BT.TYPES[q].k === key){ idx = q; break; }
      if (idx < 0) throw new Error('unknown unit in list: ' + key);
      l[idx] += n; });
    return l; };
  O.keysOf = function(list){ var out = [], i; for (i = 0; i < list.length; i++) if (list[i]) out.push([BT.TYPES[i].k, list[i]]); return out; };
  O.setup = function(sc, role, deps){
    var G = BT.G, h = sc.human ? sc.human.seat : -1, i;
    BT.clock(false); BT.quit();
    BT.setTheme(sc.theme || 'ruin'); BT.setTerrain(sc.terrain || 'hills'); BT.setBuildings(sc.buildings !== false, sc.density != null ? sc.density : 1);
    BT.seed(sc.seed); BT.size(sc.size || 48);
    G.mode = sc.mode || 'pvp'; G.teams = sc.teams; G.perTeam = sc.perTeam || 1; G.budget = sc.budget || 40000; G.freeFire = !!sc.freeFire;
    G.clock = sc.clock || 0; G.goal = sc.goal === 'kill' ? 'kill' : 'obj'; G.rounds = sc.rounds || 5;
    BT.mkPlayers();
    var ps = BT.players();
    if (ps.length !== sc.seats.length) throw new Error('scenario has ' + sc.seats.length + ' seats, the page made ' + ps.length);
    ps.forEach(function(P, k){ var S = sc.seats[k]; P.bot = k !== h; P.ai = false; if (k === h) P.pid = 'A';
      BT.setList(k, O.resolveList(S.list)); if (S.skin) P.skin = S.skin; });
    var net = h >= 0 || role === 'B';      // B never rolls or runs bots: it is a joiner that only applies acts
    BT.NET.on = net; BT.NET.owner = role === 'A'; BT.NET.pid = role; BT.NET.code = 'ORACLE'; BT.NET.room = null;
    if (net && role === 'A') BT.setServer('http://127.0.0.1:9');
    G.mePl = role === 'A' ? h : -1;
    BT.setAuto(sc.auto !== false);
    O.H = h >= 0 ? { seat: h, policy: (sc.human && sc.human.policy) || 'scripted', tries: {} } : null;
    O.rngD = xs((sc.seed * 2654435761) ^ 0x9E3779B9); O.rngH = xs(((sc.seed + 1) * 40503) ^ 0x7F4A7C15);
    // deployment points: given (B gets A's), explicit, or the page's own autoDep in seat order
    var out = [];
    for (i = 0; i < ps.length; i++){ var S2 = sc.seats[i], d = deps ? deps[i] : (S2.dep && S2.dep !== 'auto') ? S2.dep : BT.autoDep(i);
      var why = BT.depWhyNot(i, d[0], d[1]); if (why && !deps && S2.dep && S2.dep !== 'auto') throw new Error('seat ' + i + ' deployment rejected: ' + why.replace(/<[^>]+>/g, ' '));
      BT.setDep(i, d[0], d[1]); out.push([d[0], d[1]]); }
    BT.capture(true); BT.start(); var leak = BT.capture(true);
    if (leak.length) throw new Error('start() sent acts: ' + JSON.stringify(leak).slice(0, 200));
    var skins = {}; BT.units.forEach(function(u){ if (u.skn) skins[u.id] = u.skn; });
    var setup = BT.curSetup(); setup.d = BT.table.d;
    var ptsOf = function(L){ var p = 0, q; for (q = 0; q < L.length; q++) if (L[q] && !BT.TYPES[q].sec && !BT.TYPES[q].lk) p += BT.TYPES[q].pts * L[q]; return p; };
    return { setup: setup, deps: out, lists: ps.map(function(P){ return O.keysOf(P.list); }),
      seats: ps.map(function(P){ return { team: P.team, bot: !!P.bot, fac: P.fac, pts: ptsOf(P.list) }; }),
      skins: skins, props: BT.props(), obj: BT.obj().map(function(o){ return { n: o.n, x: o.x, z: o.z }; }), board0: BT.board() };
  };
  O.center = function(s){ var ms = BT.sqModels(s), x = 0, z = 0; ms.forEach(function(m){ x += m.gx != null ? m.gx : m.x; z += m.gz != null ? m.gz : m.z; });
    return { x: x / (ms.length || 1), z: z / (ms.length || 1) }; };
  O.dist = function(a, b){ var ca = O.center(a), cb = O.center(b); return Math.hypot(ca.x - cb.x, ca.z - cb.z); };
  O.clickAct = function(a){ var host = document.getElementById('btAct'), b = document.createElement('button'); b.dataset.a = a; host.appendChild(b); b.click(); b.remove(); };
  O.clickTray = function(x){ var host = document.getElementById('btTrayX'), b = document.createElement('button'); b.dataset.x = x; host.appendChild(b); b.click(); b.remove(); };
  O.clickEnd = function(){ document.getElementById('btEnd').click(); };
  // the human seat's choices on the tray (manual dice path): stratagems when the seat can pay for them
  O.humanOpts = function(r){
    var seat = O.H.seat, p = O.rnd();
    if (r === 'wound:human'){ if (p < 0.6 && BT.stratOk('rr', seat)) O.clickTray('rr'); return {}; }
    if (r === 'save:human') return { gtg: p < 0.7 && BT.stratOk('gtg', seat) };
    if (r === 'shock.shock:human') return { brave: p < 0.7 && BT.stratOk('brave', seat) };
    if (r === 'chg.ow:human') return { yes: p < 0.85 && BT.stratOk('ow', seat) };
    if (r === 'chg.chrr:human') return { yes: p < 0.8 && BT.stratOk('rr', seat) };
    return {};
  };
  // roll everything that waits, in the page's own order: the human's with the policy's choices, the bots' with botChoice
  O.drain = function(){ var guard = 0, r; while (guard++ < 120 && (r = BT.myRoll())){ var human = r === 'aim' || /:human$/.test(r); BT.roll(human ? O.humanOpts(r) : undefined); } };
  O.myTurn = function(){ var G = BT.G, P = BT.players()[O.H.seat]; return !G.over && G.turn === P.team && !P.done && (G.phase === 'move' || G.phase === 'shoot' || G.phase === 'charge'); };
  // one order of the scripted human seat per step; pressing "end" when nothing is left
  O.humanOrder = function(){
    var G = BT.G, P = BT.players()[O.H.seat], mine = BT.squads().filter(function(s){ return s.pl === P.id && BT.canAct(s.id); });
    if (!mine.length){ O.clickEnd(); return 'end'; }
    var s = mine[0], key = G.phase + ':' + G.round + ':' + s.id, tries = O.H.tries; tries[key] = (tries[key] || 0) + 1;
    var T = O.typeOf(s.k), foes = BT.squads().filter(function(q){ return q.side !== s.side; }), c = O.center(s);
    foes.sort(function(a, b){ return O.dist(s, a) - O.dist(s, b); });
    var W = BT.table.w / 2 - 1.5, D = BT.table.d / 2 - 1.5, clampX = function(x){ return Math.max(-W, Math.min(W, x)); }, clampZ = function(z){ return Math.max(-D, Math.min(D, z)); };
    if (tries[key] > 3){ BT.select(s.id); O.clickAct(G.phase === 'move' ? 'stay' : 'skip'); if (BT.canAct(s.id)){ O.clickEnd(); return 'end'; } return 'forced'; }
    if (G.phase === 'move'){
      if (!foes.length){ BT.select(s.id); O.clickAct('stay'); return 'stay'; }
      var f = O.center(foes[0]), d = Math.hypot(f.x - c.x, f.z - c.z);
      if (BT.engaged(s.id)){
        if (O.rnd() < 0.5){ var L = d || 1, ax = clampX(c.x + (c.x - f.x) / L * T.mv), az = clampZ(c.z + (c.z - f.z) / L * T.mv);
          BT.act('fb'); if (BT.move(s.id, ax, az)) return 'fb'; }
        BT.select(s.id); O.clickAct('stay'); return 'stay'; }
      if (T.gun && d <= T.gun.rng * 0.7 && O.rnd() < 0.5){ BT.select(s.id); O.clickAct('stay'); return 'stay'; }
      BT.select(s.id);
      if (O.rnd() < 0.35) O.clickAct('adv');                     // advance: the page rolls the die and sends 'adv'
      var R = T.mv + (s.adv ? s.advR : 0), want = Math.max(0, d - 2.5), step = Math.min(R, want), L2 = d || 1;
      var k; for (k = 1; k >= 0.25; k /= 2){ var tx = clampX(c.x + (f.x - c.x) / L2 * step * k), tz = clampZ(c.z + (f.z - c.z) / L2 * step * k);
        if (step * k > 0.5 && BT.move(s.id, tx, tz)) return s.adv ? 'adv-move' : 'move'; }
      var px = clampX(c.x + (f.z - c.z) / L2 * Math.min(R, 4)), pz = clampZ(c.z - (f.x - c.x) / L2 * Math.min(R, 4));
      if (BT.move(s.id, px, pz)) return 'side-move';
      BT.select(s.id); O.clickAct('stay'); return 'stay';
    }
    if (G.phase === 'shoot'){
      if (T.heal){ var pat = BT.squads().filter(function(q){ return q.side === s.side && q.id !== s.id && !BT.why('heal', s.id, q.id); })[0];
        if (pat){ BT.aim(s.id, pat.id, 'heal'); BT.roll({}); return 'heal'; } }
      var tg = foes.filter(function(q){ return !BT.why('shoot', s.id, q.id); });
      if (tg.length && O.rnd() < 0.15 && foes.length && BT.aim(s.id, foes[0].id, 'gren')){ BT.roll({}); return 'gren'; }
      if (!tg.length){ if (foes.length && BT.aim(s.id, foes[0].id, 'gren')){ BT.roll({}); return 'gren'; }
        BT.select(s.id); O.clickAct('skip'); return 'skip'; }
      var t = tg[Math.floor(O.rnd() * Math.min(2, tg.length))];
      if (O.rnd() < 0.3){ if (BT.shootAt(s.id, t.id, undefined, 'shoot')) return 'shoot'; }
      if (BT.aim(s.id, t.id, 'atk')){ BT.roll({}); return 'atk'; }
      BT.select(s.id); O.clickAct('skip'); return 'skip';
    }
    if (G.phase === 'charge'){
      var ct = foes.filter(function(q){ return !BT.why('chg', s.id, q.id); })[0];
      if (ct && BT.charge(s.id, ct.id) === '') return 'charge';
      BT.select(s.id); O.clickAct('skip'); return 'skip';
    }
    return null;
  };
  // one step of page A: fill the dice queue, act, let the simulation run, hand over what was sent
  O.stepA = function(sc){
    var G = BT.G, did = null;
    BT.dice(O.dice(sc.diceBatch || 1200));
    if (!O.H){ did = BT.botStep(); BT.tick(1 / 30, sc.stepTicks || 4); }
    else { O.drain(); if (O.H.policy === 'scripted' && O.myTurn()) did = O.humanOrder(); BT.tick(1 / 30, sc.stepTicks || 15); }
    return { sent: BT.capture(true), over: !!G.over, diceLeft: BT.diceLeft(), did: did, round: G.round, turn: G.turn, phase: G.phase, log: BT.log() };
  };
  // page B: apply the acts one by one, the board after each, and who sent each (read before applying): the seat that
  // rolled or decided — the defender for saves and the overwatch decision, the human for 'done', nobody for 'endph'
  O.applyB = function(acts, human){
    var G = BT.G, boards = [], meta = [];
    acts.forEach(function(a){ var who = (a.a === 'sav' || a.a === 'ow') ? a.t : a.u, s = who != null ? BT.sq(who) : null;
      meta.push({ seat: s ? s.pl : (a.a === 'done' ? human : null), turn: G.turn, round: G.round, phase: G.phase });
      a.pid = 'A'; BT.applyAct(a); boards.push(BT.board()); });
    BT.tick(1 / 30, 1);
    return { boards: boards, meta: meta };
  };
  O.final = function(){ var G = BT.G, t, alive = []; for (t = 0; t < G.teams; t++) if (BT.live(t)) alive.push(t);
    var L = BT.log(), last = L.length ? L[L.length - 1].t.replace(/<[^>]+>/g, '') : '';
    return { over: !!G.over, round: G.round, turn: G.turn, phase: G.phase, vp: BT.vp(), cp: BT.players().map(function(P){ return P.cp || 0; }),
      alive: alive, units: BT.units.length, result: last }; };
  return true;
}

// ---------- the log: the page keeps its last 80 lines, so merge after every step ----------
function mergeLog(full, prev, cur){
  if (!prev.length){ full.push(...cur.map(x => ({ ...x }))); return cur; }
  let m = Math.min(prev.length, cur.length), found = -1;
  for (; m >= 1; m--){ let ok = true;
    for (let i = 0; i < m; i++){ const a = prev[prev.length - m + i], b = cur[i]; if (a.base !== b.base || a.c !== b.c || (i < m - 1 && a.n !== b.n)){ ok = false; break; } }
    if (ok){ found = m; break; } }
  if (found < 0){ full.push({ t: '… (log gap: more than 80 lines in one step)', base: '', c: '', n: 1 }); full.push(...cur.map(x => ({ ...x }))); return cur; }
  const lastSeen = cur[found - 1]; Object.assign(full[full.length - 1], lastSeen);       // the merged "×n" count of the last line
  full.push(...cur.slice(found).map(x => ({ ...x })));
  return cur;
}
const norm = bd => JSON.stringify({ ...bd, units: bd.units.slice().sort((x, y) => x.id < y.id ? -1 : 1) });
function firstDiff(a, b){
  const out = [];
  ['turn', 'round', 'phase', 'over', 'vp', 'cp'].forEach(k => { if (JSON.stringify(a[k]) !== JSON.stringify(b[k])) out.push(k + ' ' + JSON.stringify(a[k]) + ' vs ' + JSON.stringify(b[k])); });
  const ua = Object.fromEntries(a.units.map(u => [u.id, u])), ub = Object.fromEntries(b.units.map(u => [u.id, u]));
  Object.keys({ ...ua, ...ub }).forEach(id => { const x = JSON.stringify(ua[id]), y = JSON.stringify(ub[id]); if (x !== y) out.push('unit ' + id + ' ' + x + ' vs ' + y); });
  const sa = Object.fromEntries(a.squads.map(s => [s.id, s])), sb = Object.fromEntries(b.squads.map(s => [s.id, s]));
  Object.keys({ ...sa, ...sb }).forEach(id => { const x = JSON.stringify(sa[id]), y = JSON.stringify(sb[id]); if (x !== y) out.push('squad ' + id + ' ' + x + ' vs ' + y); });
  return out.slice(0, 6).join('\n    ');
}

// ---------- one scenario ----------
async function record(browser, sc){
  const t0 = Date.now();
  const A = await browser.newPage({ viewport: { width: 480, height: 320 } }), B = await browser.newPage({ viewport: { width: 480, height: 320 } });
  const errs = []; [A, B].forEach((p, i) => p.on('pageerror', e => errs.push((i ? 'B: ' : 'A: ') + String(e.stack || e).slice(0, 400))));
  // page A talks to a room when it has a human seat; answer it like the Worker would, so nothing waits on the network
  await A.route(url => url.href.startsWith('http://127.0.0.1:9/'), route => route.fulfill({ status: 200, contentType: 'application/json',
    headers: { 'access-control-allow-origin': '*', 'access-control-allow-headers': '*' }, body: '{"ok":true,"seq":0}' }));
  try {
    for (const p of [A, B]){ await p.goto('file://' + PAGE); await p.waitForFunction('window.BT && window.BT.G'); await p.evaluate(pageLib); }
    const human = sc.human ? sc.human.seat : -1;
    const sa = await A.evaluate(([s]) => ORACLE.setup(s, 'A', null), [sc]);
    const sb = await B.evaluate(([s, d]) => ORACLE.setup(s, 'B', d), [sc, sa.deps]);
    if (norm(sa.board0) !== norm(sb.board0)) throw new Error('A and B deploy differently:\n    ' + firstDiff(sa.board0, sb.board0));
    if (JSON.stringify(sa.skins) !== JSON.stringify(sb.skins) || JSON.stringify(sa.props) !== JSON.stringify(sb.props)) throw new Error('A and B differ in skins or props');
    if (sc.seats.some(S => S.skin) && !Object.keys(sa.skins).length) throw new Error('the scenario asks for a skin but no unit carries one');
    const rec = { format: 1, page: { app_ver: APP_VER, rules_v: RULES_V }, scenario: sc.name, scenario_def: sc, setup: sa.setup, seats: sa.seats,
      lists: sa.lists, deps: sa.deps, skins: sa.skins, props: sa.props, obj: sa.obj, board0: sa.board0, acts: [], acts_meta: [], boards: [], log: [], final: null };
    const cap = opt.cap || sc.maxSteps || 15000, stall = sc.stallSteps || 1500, hist = {};
    let steps = 0, idle = 0, prevLog = [], over = false, lastDid = null;
    while (steps < cap){
      const st = await A.evaluate(([s]) => ORACLE.stepA(s), [sc]); steps++;
      if (st.diceLeft === 0) throw new Error('dice queue exhausted in step ' + steps + ' (raise diceBatch)');
      prevLog = mergeLog(rec.log, prevLog, st.log);
      if (st.sent.length){
        idle = 0;
        const rb = await B.evaluate(([acts, h]) => ORACLE.applyB(acts, h), [st.sent, human]);
        const ba = await A.evaluate(() => BT.board());
        st.sent.forEach(a => { hist[a.a] = (hist[a.a] || 0) + 1; });
        rb.meta.forEach(m => { m.step = steps; });
        rec.acts.push(...st.sent); rec.acts_meta.push(...rb.meta); rec.boards.push(...rb.boards);
        if (norm(ba) !== norm(rb.boards[rb.boards.length - 1]))
          throw new Error('B diverges from A after act ' + rec.acts.length + ' (' + JSON.stringify(st.sent).slice(0, 160) + '):\n    ' + firstDiff(ba, rb.boards[rb.boards.length - 1]));
      } else if (++idle > stall) throw new Error('stalled: ' + stall + ' steps without an act in round ' + st.round + ' phase ' + st.phase + ' turn ' + st.turn + ' (last order ' + lastDid + ')');
      if (st.did) lastDid = st.did;
      if (errs.length) throw new Error('page error: ' + errs[0]);
      if (st.over){ over = true; break; }
    }
    rec.final = await A.evaluate(() => ORACLE.final());
    const fb = await B.evaluate(() => ORACLE.final());
    if (JSON.stringify(rec.final) !== JSON.stringify(fb)) throw new Error('A and B end differently: ' + JSON.stringify(rec.final) + ' vs ' + JSON.stringify(fb));
    rec.final.steps = steps; rec.final.acts = rec.acts.length; rec.final.capped = !over; rec.final.hist = hist;
    if (!over) throw new Error('step cap ' + cap + ' reached in round ' + rec.final.round + ' (' + rec.acts.length + ' acts) — the recording is not complete');
    if (errs.length) throw new Error('page error: ' + errs[0]);
    return { rec, secs: Math.round((Date.now() - t0) / 1000) };
  } finally { await A.close(); await B.close(); }
}

async function recordAll(scenarios, outDir, gz){
  const { chromium } = loadPlaywright();
  const browser = await chromium.launch({ executablePath: process.env.CHROMIUM_PATH || undefined, args: ['--no-sandbox'] });
  const results = []; let failed = 0;
  try {
    for (const sc of scenarios){
      process.stdout.write(sc.name + ' … ');
      try {
        const { rec, secs } = await record(browser, sc);
        const w = writeRecording(outDir, sc.name, rec, gz);
        console.log(`ok  ${rec.acts.length} acts, round ${rec.final.round}, ${secs}s, ${(w.bytes / 1024).toFixed(0)} KB${gz ? ' (' + (w.raw / 1024).toFixed(0) + ' KB raw)' : ''} :: ${rec.final.result}`);
        results.push({ name: sc.name, file: w.file, acts: rec.acts.length, hist: rec.final.hist });
      } catch (e){ failed++; console.log('FAIL ' + (e && e.message || e)); results.push({ name: sc.name, error: String(e && e.message || e) }); }
    }
  } finally { await browser.close(); }
  return { results, failed };
}

function histogram(dir, print){
  const files = listRecordings(dir), counts = {}, perFile = {};
  for (const f of files){ const rec = readRecording(f); const h = {}; rec.acts.forEach(a => { h[a.a] = (h[a.a] || 0) + 1; counts[a.a] = (counts[a.a] || 0) + 1; }); perFile[path.basename(f)] = h; }
  const need = pageActCodes(), worker = workerActCodes();
  const missing = need.filter(c => !counts[c]);
  if (print){
    console.log('act code histogram over ' + files.length + ' recordings (' + dir + ')');
    for (const c of need) console.log('  ' + c.padEnd(7) + String(counts[c] || 0).padStart(7) + (counts[c] ? '' : '   MISSING'));
    const extra = Object.keys(counts).filter(c => !need.includes(c)); if (extra.length) console.log('  codes not in the page\'s netSend set: ' + extra.join(', '));
    if (worker){ const legacy = worker.filter(c => !need.includes(c)); console.log('  Worker allowlist: ' + worker.length + ' codes; known to the Worker but never sent by this page (older rules versions): ' + (legacy.join(', ') || 'none')); }
    else console.log('  (candlelight-server/worker.js not found next to this repo: Worker allowlist not cross-checked)');
    console.log(missing.length ? 'MISSING act codes: ' + missing.join(', ') : 'every act code the page sends occurs at least once (' + need.length + ' codes)');
  }
  return { counts, missing, need, worker, perFile };
}

(async () => {
  // --histogram on its own counts what is already recorded; together with --only it records first, then counts
  if (opt.histogram && !opt.check && !opt.only.length){
    const h = histogram(opt.out || ORACLE_DIR, true); process.exit(h.missing.length ? 1 : 0); }
  const all = JSON.parse(fs.readFileSync(SCEN_FILE, 'utf8')), gzDefault = !!all.gzip;
  const gz = opt.gzip != null ? opt.gzip : gzDefault;
  let scenarios = all.scenarios;
  const names = new Set(scenarios.map(s => s.name)); if (names.size !== scenarios.length) { console.error('duplicate scenario names'); process.exit(2); }
  if (opt.only.length){ const bad = opt.only.filter(n => !names.has(n)); if (bad.length){ console.error('no such scenario: ' + bad.join(', ')); process.exit(2); }
    scenarios = scenarios.filter(s => opt.only.includes(s.name)); }
  if (opt.check){
    // determinism: record again into a temp folder and compare with what is committed, byte for byte (after inflating)
    const pick = opt.only.length ? scenarios : scenarios.slice(0, 3);
    const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'oracle-check-'));
    console.log('re-recording ' + pick.length + ' scenario(s) into ' + tmp);
    const { results, failed } = await recordAll(pick, tmp, gz);
    let bad = failed;
    for (const r of results){ if (r.error) continue;
      const base = path.basename(r.file), ref = [path.join(ORACLE_DIR, base), path.join(ORACLE_DIR, base.replace(/\.gz$/, '')), path.join(ORACLE_DIR, base + '.gz')].find(f => fs.existsSync(f));
      if (!ref){ console.log('MISSING reference recording for ' + r.name); bad++; continue; }
      const inflate = f => f.endsWith('.gz') ? zlib.gunzipSync(fs.readFileSync(f)) : fs.readFileSync(f);
      const a = inflate(r.file), b = inflate(ref);
      if (a.equals(b)) console.log('identical  ' + r.name + ' (' + a.length + ' bytes' + (r.file.endsWith('.gz') && ref.endsWith('.gz') && fs.readFileSync(r.file).equals(fs.readFileSync(ref)) ? ', gzip bytes identical too' : '') + ')');
      else { bad++; const la = a.toString('utf8').split('\n'), lb = b.toString('utf8').split('\n'); let i = 0; while (i < la.length && i < lb.length && la[i] === lb[i]) i++;
        console.log('DIFFERS    ' + r.name + ' at line ' + (i + 1) + ':\n    new: ' + (la[i] || '').slice(0, 200) + '\n    ref: ' + (lb[i] || '').slice(0, 200)); } }
    console.log(bad ? bad + ' scenario(s) not reproducible' : 'all ' + results.length + ' re-recordings byte-identical');
    process.exit(bad ? 1 : 0);
  }
  const outDir = opt.out || ORACLE_DIR;
  const { results, failed } = await recordAll(scenarios, outDir, gz);
  const total = listRecordings(outDir).reduce((n, f) => n + fs.statSync(f).size, 0);
  console.log(`${results.length - failed} recorded, ${failed} failed · ${(total / 1024 / 1024).toFixed(2)} MB in ${outDir}`);
  let code = failed ? 1 : 0;
  if (opt.histogram){ const h = histogram(outDir, true); if (h.missing.length) code = 1; }
  process.exit(code);
})().catch(e => { console.error('THREW', e); process.exit(1); });
