// Round 5b: Hanuman, son of the wind. He falls and his body stays, pale; his team is not beaten while he waits; at his
// team's next command phase the wind brings him back where he fell with all his wounds (the first time for sure);
// later times a D6 on 4+ (the rez act), and when the wind does not come the body fades and the game can end.
//   node r5b_wind.js   (PAGE=... for another page)
const { chromium } = require('playwright');
const F = 'file://' + (process.env.PAGE || require('path').resolve(__dirname, '../../../app/src/main/assets/battle-table.html'));
let pass = 0, fail = 0; const ok = (c, m, x) => { c ? pass++ : fail++; console.log((c ? 'ok   ' : 'FAIL ') + m + (x !== undefined ? '  ' + JSON.stringify(x) : '')); };
(async () => {
  const b = await chromium.launch({ executablePath: process.env.CHROMIUM_PATH || undefined, args: ['--no-sandbox'] });
  const p = await b.newPage({ viewport: { width: 1200, height: 760 } });
  const errs = []; p.on('pageerror', e => errs.push(String(e.stack || e).slice(0, 500)));
  await p.goto(F); await p.waitForFunction('window.BT && window.BT.G');
  await p.evaluate(() => {
    window.T = {
      setup(A, B){ BT.clock(false); BT.quit(); BT.setTerrain('flat'); BT.setBuildings(false); BT.size(60);
        BT.G.mode = 'pvp'; BT.G.teams = 2; BT.G.perTeam = 1; BT.G.freeFire = false; BT.G.clock = 0; BT.G.budget = 2000; BT.mkPlayers();
        const L = (arr) => { const l = new Array(BT.TYPES.length).fill(0); arr.forEach(([k, n]) => { l[BT.TYPES.findIndex(t => t.k === k)] = n; }); return l; };
        BT.setList(0, L(A)); BT.setList(1, L(B)); BT.players()[0].dep = [-20, 0]; BT.players()[1].dep = [20, 0];
        BT.setAuto(true); BT.start(); BT.dice([]); },
      sq(pl, k, i){ return BT.squads().filter(s => s.pl === pl && s.k === k)[i || 0]; },
      settle(){ for (let i = 0; i < 600 && (BT.walking() || BT.tray().q || (BT.tray().cur && !BT.tray().cur.settled)); i++) BT.tick(1/30, 3); },
      kill(h){ const e = T.sq(1, 'heavy'), m = BT.units.find(u => u.id === h); BT.place(e.id, m.x + 9, m.z, -Math.PI/2);
        const six = new Array(20).fill(6), one = new Array(20).fill(1);
        BT.shootAt(e, BT.sqOf(m), { hit:six, wound:six, save:one }); T.settle(); BT.tick(1/30, 90); },
      hanu(){ const u = BT.units.find(u => u.k === 'hanu'), f = BT.fallen().find(u => u.k === 'hanu');
        return { alive: !!u, hp: u ? u.hp : null, body: !!f, wait: f ? !!f.windWait : null, alpha: f && f.act && f.act.xf ? +f.act.xf.alpha.toFixed(2) : null,
                 act: u && u.act ? u.act.kind : null, over: BT.G.over, turn: BT.G.turn, x: (u || f) ? +(u || f).x.toFixed(2) : null }; },
      toTurn(side){ const r0 = BT.G.round, t0 = BT.G.turn;        // on to this side's next turn (its command phase runs on the way)
        for (let k = 0; k < 12; k++){ BT.endTurn(); BT.flush(true); T.settle(); if (BT.G.over || (BT.G.turn === side && (BT.G.round !== r0 || t0 !== side))) break; } }
    };
  });
  const E = (f, a) => p.evaluate(f, a);
  const info = await E(() => { const T0 = BT.TYPES.find(t => t.k === 'hanu'); return { pts: T0.pts, wind: T0.wind, fly: T0.fly }; });
  ok(info.pts === 150 && info.wind === 4 && info.fly === 1, 'Hanuman: 150 points, son of the wind (4+ after the first time), flies', info);

  // A. alone on his side: he falls, the body stays, his side is not beaten; his next command phase brings him back
  let r = await E(() => { T.setup([['hanu', 1]], [['heavy', 2]]); const h = BT.units.find(u => u.k === 'hanu').id; const x0 = BT.units.find(u => u.k === 'hanu').x;
    T.kill(h); const dead = T.hanu(); BT.tick(1/30, 120); const later = T.hanu(); return { dead, later, x0 }; });
  ok(!r.dead.alive && r.dead.body && r.dead.wait, 'he falls: his body stays on the table, waiting for the wind', r.dead);
  ok(r.later.body && r.later.alpha === 0.35 && !r.later.over, 'four seconds on it is still there, pale, and his side is not beaten (the game goes on)', r.later);
  r = await E(() => { T.toTurn(0); const s = T.hanu(); const log = BT.log().slice(-12).map(l => l.t.replace(/<[^>]+>/g, '')).join(' | '); return { s, wind: /ลมพัดมาชุบชีวิต/.test(log) }; });
  ok(r.s.alive && r.s.hp === 6 && r.s.act === 'rise' && r.wind, 'at his side\'s command phase the wind brings him back, all 6 wounds, standing up', r);
  r = await E(() => { const u = BT.units.find(u => u.k === 'hanu'), a0 = u.alt; BT.tick(1/30, 12); const a1 = u.alt, k1 = u.act && u.act.kind; BT.tick(1/30, 120);
    return { rising: a0, whileRise: a1, kind: k1, after: +u.alt.toFixed(2) }; });
  ok(r.rising === 0 && r.whileRise === 0 && r.after === 1.3, 'he gets up on the ground, then takes to the air again', r);

  // B. the second fall: a die this time, 4+ he comes back
  r = await E(() => { const h = BT.units.find(u => u.k === 'hanu').id; T.kill(h); const dead = T.hanu();
    BT.dice([5]); T.toTurn(0); T.settle(); const s = T.hanu(); const log = BT.log().slice(-12).map(l => l.t.replace(/<[^>]+>/g, '')).join(' | ');
    return { dead, s, rolled: /ลูกพระพาย — ทอย 5/.test(log) }; });
  ok(r.dead.body && r.dead.wait && r.rolled && r.s.alive && r.s.hp === 6, 'the second time a die is rolled: a 5 brings him back again', r);

  // C. the third fall and a 2: the wind does not come, the body fades and, alone on his side, the game ends
  r = await E(() => { const h = BT.units.find(u => u.k === 'hanu').id; T.kill(h); BT.dice([2]); T.toTurn(0); T.settle(); BT.tick(1/30, 60);
    const log = BT.log().slice(-12).map(l => l.t.replace(/<[^>]+>/g, '')).join(' | ');
    return { s: T.hanu(), none: /ลมไม่มา/.test(log), over: BT.G.over }; });
  ok(!r.s.alive && !r.s.body && r.none && r.over, 'a 2: the wind does not come, his body fades away and his side is beaten', r);

  // D. the ability is on the roster card
  r = await E(() => { const T0 = BT.TYPES.find(t => t.k === 'hanu'); return BT.abilityText ? BT.abilityText(T0) : null; });
  ok(typeof r === 'string' && /ลูกพระพาย/.test(r) && /4\+/.test(r), 'the roster lists "son of the wind" (4+ after the first time)', r);
  ok(errs.length === 0, 'no page errors', errs.slice(0, 3));
  console.log(`${pass} passed, ${fail} failed`); await b.close(); process.exit(fail ? 1 : 0);
})().catch(e => { console.error('THREW', e); process.exit(1); });
