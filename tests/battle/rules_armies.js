// Round 7 rules: poison, designating a target, the space elves shoot after advancing, the dark elves' pain from round 3,
// the new armies in the datasheets and in the bots' lists, rules version 8.
//   node r7_rules.js [page]
const { chromium } = require('playwright');
const F = 'file://' + require('path').resolve(process.argv[2] || process.env.PAGE || require('path').resolve(__dirname, '../../app/src/main/assets/battle-table.html'));
let pass = 0, fail = 0; const ok = (c, m, x) => { c ? pass++ : fail++; console.log((c ? 'ok   ' : 'FAIL ') + m + (x !== undefined ? '  ' + JSON.stringify(x) : '')); };
(async () => {
  const b = await chromium.launch({ executablePath: process.env.CHROMIUM_PATH || undefined, args: ['--no-sandbox'] });
  const p = await b.newPage({ viewport: { width: 1200, height: 760 } });
  const errs = []; p.on('pageerror', e => errs.push(String(e.stack || e).slice(0, 500)));
  await p.goto(F); await p.waitForFunction('window.BT && window.BT.G');
  await p.evaluate(() => {
    window.T = {
      L(arr){ const l = new Array(BT.TYPES.length).fill(0); arr.forEach(([k, n]) => { l[BT.TYPES.findIndex(t => t.k === k)] = n; }); return l; },
      setup(A, B, o){ o = o || {}; BT.clock(false); BT.quit(); BT.setTerrain('flat'); BT.setBuildings(false); BT.size(80);
        BT.G.mode = 'pvp'; BT.G.teams = 2; BT.G.perTeam = 1; BT.G.freeFire = false; BT.G.clock = 0; BT.G.budget = 40000;
        BT.G.goal = o.goal || 'obj'; BT.G.rounds = o.rounds || 5; BT.mkPlayers();
        BT.setList(0, T.L(A)); BT.setList(1, T.L(B)); BT.players()[0].dep = [-30, 0]; BT.players()[1].dep = [30, 0];
        BT.setAuto(true); BT.start(); BT.dice([]); },
      sq(pl, k, i){ return BT.squads().filter(s => s.pl === pl && s.k === k)[i || 0]; },
      settle(){ for (let i = 0; i < 900 && (BT.walking() || BT.tray().q || (BT.tray().cur && !BT.tray().cur.settled) || BT.pend().length); i++){ BT.flush(true); BT.tick(1/30, 3); } },
      near(a, b, gap){ const m = BT.sqModels(b)[0]; BT.place(a.id, m.x - gap, m.z, Math.PI/2); },
      hitAll(a, b, n, how){ const six = new Array(n || 60).fill(6), one = new Array(n || 60).fill(1);
        BT.shootAt(a.id, b.id, { hit:six, wound:six, save:one }, how); T.settle(); }
    };
  });
  const E = (f, a) => p.evaluate(f, a);

  console.log('# datasheets, armies, version');
  // (Round 8 appends 28 kinds after these 246 and a new army: the first 246 must be as they were)
  let r = await E(() => { const by = {}; BT.TYPES.slice(0, 246).forEach(t => { by[t.fac] = (by[t.fac] || 0) + 1; });
    return { n: BT.TYPES.length, el: by.el, de: by.de, ta: by.ta, or: by.or, v: BT.rulesV ? BT.rulesV() : null, ver: document.getElementById('btVer') && document.getElementById('btVer').textContent,
      picker: ['el', 'de', 'ta'].map(f => !!document.querySelector('button.mode[data-f="' + f + '"]')) }; });
  ok(r.n >= 246 && r.el === 24 && r.de === 27 && r.ta === 29 && r.or === 25, '246 datasheets (and any added after them): 24 space elves, 27 dark elves, 29 of the blue empire, 25 orks', r);
  ok(r.picker.every(Boolean), 'the army picker has a button for each new army', r.picker);
  ok(parseFloat((r.ver || '').replace(/[^\d.]/g, '')) >= 8, 'the version label reads 8.x or later', r.ver);

  console.log('# poison');
  r = await E(() => { T.setup([['dewar', 1]], [['kterm', 1], ['ktank', 1], ['brute', 1], ['infantry', 1]]);
    const w = T.sq(0, 'dewar'), term = T.sq(1, 'kterm'), tank = T.sq(1, 'ktank'), brute = T.sq(1, 'brute'), inf = T.sq(1, 'infantry'); T.near(w, term, 10);
    const f = (t) => { const m = BT.atkMath(w.id, t.id, 'shoot'); return m && m.wneed; };
    return { term: f(term), tank: f(tank), brute: f(brute), inf: f(inf) }; });
  ok(r.term === 3 && r.inf === 3, 'a poisoned rifle (strength 2) wounds foot soldiers on 3+, even toughness 5', r);
  ok(r.tank === 6 && r.brute === 6, 'but not a tank or a big beast: strength 2 needs 6s there', r);

  console.log('# designating a target');
  r = await E(() => { T.setup([['tapath', 1], ['tafw', 1]], [['kgcastellan', 1]]);
    const pa = T.sq(0, 'tapath'), fw = T.sq(0, 'tafw'), h = T.sq(1, 'kgcastellan'); BT.setPhase('shoot'); T.near(pa, h, 12); T.near(fw, h, 14);
    const before = BT.atkMath(fw.id, h.id, 'shoot').mod; T.hitAll(pa, h, 20, 'shoot');
    const after = BT.atkMath(fw.id, h.id, 'shoot').mod, fightMod = BT.atkMath(fw.id, h.id, 'fight').mod;
    return { before, after, fightMod, turn: BT.G.turn }; });
  ok(r.before === 0 && r.after === 1, 'after the pathfinders hit it, the fire warriors hit the same squad at +1', r);
  ok(r.fightMod === 0, 'the mark helps shooting, not melee', r);
  r = await E(() => { const fw = T.sq(0, 'tafw'), h = T.sq(1, 'kgcastellan'); for (let k = 0; k < 4 && BT.G.turn === 0; k++){ BT.endTurn(); BT.flush(true); T.settle(); }
    return { turn: BT.G.turn, mod: BT.atkMath(fw.id, h.id, 'shoot').mod }; });
  ok(r.turn !== 0 && r.mod === 0, 'the mark is gone once the turn is over', r);
  r = await E(() => { T.setup([['tapath', 1], ['tafw', 1]], [['heavy', 1]]);
    const pa = T.sq(0, 'tapath'), fw = T.sq(0, 'tafw'), h = T.sq(1, 'heavy'); BT.setPhase('shoot'); T.near(pa, h, 12); T.near(fw, h, 14);
    const one = new Array(20).fill(1); BT.shootAt(pa.id, h.id, { hit:one, wound:one, save:one }, 'shoot'); T.settle();
    return { mod: BT.atkMath(fw.id, h.id, 'shoot').mod }; });
  ok(r.mod === 0, 'a volley that misses marks nothing', r);

  console.log('# the space elves shoot after advancing');
  r = await E(() => { T.setup([['elguard', 1], ['infantry', 1]], [['heavy', 1]]);
    const g = T.sq(0, 'elguard'), i = T.sq(0, 'infantry'), h = T.sq(1, 'heavy'); BT.setPhase('shoot'); T.near(g, h, 12); T.near(i, h, 14);
    BT.advd(g.id, true); BT.advd(i.id, true); return { el: BT.why('shoot', g.id, h.id), other: BT.why('shoot', i.id, h.id) }; });
  ok(r.el === '' && /วิ่ง/.test(r.other || ''), 'guardians that ran still shoot; soldiers that ran cannot', r);

  console.log('# the dark elves grow fiercer from round 3');
  r = await E(() => { T.setup([['dewych', 1], ['boy', 1]], [['heavy', 2]]);
    const w = T.sq(0, 'dewych'), o = T.sq(0, 'boy'), h = T.sq(1, 'heavy'), h2 = T.sq(1, 'heavy', 1); T.near(w, h, 0.3); T.near(o, h2, 0.3);
    const out = {}; [1, 2, 3, 4].forEach(rd => { BT.G.round = rd; out['r' + rd] = BT.atkMath(w.id, h.id, 'fight').mod; out['orc' + rd] = BT.atkMath(o.id, h2.id, 'fight').mod; });
    return out; });
  ok(r.r1 === 0 && r.r2 === 0 && r.r3 === 1 && r.r4 === 1, 'arena fighters hit +1 in melee from round 3', r);
  ok(r.orc3 === 0 && r.orc4 === 0, 'other armies do not', r);
  r = await E(() => { T.setup([['dewar', 1]], [['heavy', 1]]); const w = T.sq(0, 'dewar'), h = T.sq(1, 'heavy'); BT.setPhase('charge');
    const m = BT.sqModels(h)[0]; BT.place(w.id, m.x - 8, m.z, Math.PI/2); BT.advd(w.id, true);
    BT.G.round = 2; const r2 = BT.why('chg', w.id, h.id); BT.G.round = 3; const r3 = BT.why('chg', w.id, h.id); return { r2, r3 }; });
  ok(/วิ่ง/.test(r.r2 || '') && r.r3 === '', 'warriors that ran may charge from round 3, not before', r);

  console.log('# texts');
  r = await E(() => { const mk = document.createElement('div'); return {
      po: BT.wpnLine ? BT.wpnLine(BT.TYPES.find(t => t.k === 'dewar').gun, false) : null,
      mk: BT.wpnLine ? BT.wpnLine(BT.TYPES.find(t => t.k === 'tapath').gun, false) : null,
      el: BT.abilityText(BT.TYPES.find(t => t.k === 'elguard')),
      de: BT.abilityText(BT.TYPES.find(t => t.k === 'dewar')) }; });
  if (r.po !== null) ok(/พิษ/.test(r.po) && /ชี้เป้า/.test(r.mk), 'the weapon lines say poison and designate', r);
  if (r.el !== null) ok(/วิ่งแล้วยังยิงได้/.test(r.el) && /รอบ 3/.test(r.de), 'the abilities say what the armies do', r);

  console.log('# bots build lists for the new armies');
  r = await E(() => { const out = {}; ['or', 'el', 'de', 'ta'].forEach(f => { BT.quit(); BT.G.mode = 'pve'; BT.G.teams = 2; BT.G.perTeam = 1; BT.G.budget = 2000; BT.mkPlayers();
      BT.players()[0].fac = f; BT.autoList(0, true); const L = BT.players()[0].list; if (!L) { out[f] = null; return; }
      const facs = new Set(); let n = 0; L.forEach((c, i) => { if (c > 0){ facs.add(BT.TYPES[i].fac); n += c; } }); out[f] = { n, facs: [...facs] }; });
    return out; });
  if (r.el !== null) ok(['or', 'el', 'de', 'ta'].every(f => r[f] && r[f].n > 0 && r[f].facs.length === 1 && r[f].facs[0] === f), 'a random list for each of them holds only that army', r);

  ok(errs.length === 0, 'no page errors', errs.slice(0, 3));
  console.log(`\n${pass}/${pass + fail} passed`);
  await b.close(); process.exit(fail ? 1 : 0);
})().catch(e => { console.error('THREW', e); process.exit(2); });
