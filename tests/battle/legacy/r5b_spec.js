// Round 5b: spectator mode, armies built by the viewer. "จัดเอง" leads to the army page once per bot (with the random and
// preview buttons), the last bot's button starts the watching, the bots bring exactly the lists built, "ดูอีกรอบ" keeps
// them, and "สุ่มให้" still goes straight to the table. node r5b_spec.js   (PAGE=... for another page)
const { chromium } = require('playwright');
const F = 'file://' + (process.env.PAGE || require('path').resolve(__dirname, '../../../app/src/main/assets/battle-table.html'));
let pass = 0, fail = 0; const ok = (c, m, x) => { c ? pass++ : fail++; console.log((c ? 'ok   ' : 'FAIL ') + m + (x !== undefined ? '  ' + JSON.stringify(x) : '')); };
(async () => {
  const b = await chromium.launch({ executablePath: process.env.CHROMIUM_PATH || undefined, args: ['--no-sandbox'] });
  for (const [nm, opt] of [['desk', { viewport: { width: 1366, height: 768 } }], ['phone', { viewport: { width: 390, height: 844 }, deviceScaleFactor: 2, isMobile: true, hasTouch: true }]]) {
    const ctx = await b.newContext(opt), p = await ctx.newPage(); const errs = []; p.on('pageerror', e => errs.push(String(e.stack || e).slice(0, 400)));
    await p.goto(F); await p.waitForFunction('window.BT && window.BT.G'); await p.waitForTimeout(300);
    const click = async sel => { if (opt.hasTouch) await p.tap(sel); else await p.click(sel); await p.waitForTimeout(80); };
    const vis = id => p.evaluate(id => !document.getElementById(id).classList.contains('hide'), id);
    await click('#btModes .mode[data-g="spectator"]');
    ok(await vis('btSpecOpt') && await p.evaluate(() => document.querySelector('#btSpecOwn .on').dataset.o === '0'), `${nm}: spectator setup offers "random / build" with random first`);
    await click('#btSpecOwn button[data-o="1"]');
    ok(/จัดกองทัพให้บอท/.test(await p.textContent('#btNext')), `${nm}: with "build" the next button says it goes to the bots' armies`, await p.textContent('#btNext'));
    await click('#btNext');
    let s = await p.evaluate(() => ({ army: !document.getElementById('scArmy').classList.contains('hide'), cur: BT.G.cur, who: BT.players()[BT.G.cur].nm, bots: BT.players().every(x => x.bot) }));
    ok(s.army && s.cur === 0 && /บอท 1/.test(s.who) && s.bots, `${nm}: the army page opens for bot 1`, s);
    // bot 1: Japan, built by hand: three samurai squads
    await click('#btFacs .mode[data-f="jp"]');
    const si = await p.evaluate(() => BT.TYPES.findIndex(t => t.k === 'samurai'));
    for (let k = 0; k < 3; k++) await click(`#btRoster button[data-i="${si}"][data-v="1"]`);
    const r1 = await p.evaluate(() => { const P = BT.players()[0]; return { fac: P.fac, n: P.list[BT.TYPES.findIndex(t => t.k === 'samurai')] }; });
    await click('#btStart');
    s = await p.evaluate(() => ({ cur: BT.G.cur, who: BT.players()[BT.G.cur].nm, btn: document.getElementById('btStart').textContent }));
    ok(s.cur === 1 && /บอท 2/.test(s.who) && /เริ่มดูบอทตีกัน/.test(s.btn), `${nm}: then bot 2, whose button starts the watching`, s);
    // bot 2: the random button twice gives lists (from any dice, not the seeded bot pick every time)
    const lists = [];
    for (let k = 0; k < 4; k++){ await click('#btRandA'); lists.push(await p.evaluate(() => BT.players()[1].fac + ':' + BT.players()[1].list.join(''))); }
    ok(new Set(lists).size > 1, `${nm}: "random whole army" for a bot gives different armies each press (${new Set(lists).size} of 4)`);
    const want2 = await p.evaluate(() => BT.players()[1].list.slice());
    await click('#btStart'); await p.waitForTimeout(400);
    s = await p.evaluate(() => { const byTeam = t => { const c = {}; BT.units.filter(u => u.side === t).forEach(u => c[u.k] = (c[u.k] || 0) + 1); return c; };
      return { play: !document.getElementById('scPlay').classList.contains('hide'), on: BT.G.on, spec: !document.getElementById('btSpec').classList.contains('hide'),
               t0: byTeam(0), t1: byTeam(1), deploy: !document.getElementById('scDeploy').classList.contains('hide') }; });
    const expect1 = await p.evaluate((want) => { const c = {}; want.forEach((n, i) => { if (n) c[BT.TYPES[i].k] = n*BT.TYPES[i].n; }); return c; }, want2);
    ok(s.play && s.on && s.spec && !s.deploy, `${nm}: the bots go straight onto the table and the watching starts`, { play: s.play, spec: s.spec });
    ok(JSON.stringify(s.t0) === JSON.stringify({ samurai: 15 }), `${nm}: bot 1 brings exactly the three samurai squads built for it`, s.t0);
    ok(JSON.stringify(s.t1) === JSON.stringify(expect1), `${nm}: bot 2 brings its random list`, { got: s.t1, want: expect1 });
    await p.evaluate(() => { BT.tick(1/30, 60); });
    await click('#btAgain'); await p.waitForTimeout(300);
    const again = await p.evaluate(() => { const c = {}; BT.units.filter(u => u.side === 0).forEach(u => c[u.k] = (c[u.k] || 0) + 1); return c; });
    ok(JSON.stringify(again) === JSON.stringify({ samurai: 15 }), `${nm}: "watch again" keeps the armies the viewer built`, again);
    ok(errs.length === 0, `${nm}: no page errors`, errs.slice(0, 2));
    await ctx.close();
  }
  // random still works the old way
  const p = await b.newPage({ viewport: { width: 1200, height: 760 } }); await p.goto(F); await p.waitForFunction('window.BT && window.BT.G');
  await p.click('#btModes .mode[data-g="spectator"]'); await p.click('#btNext'); await p.waitForTimeout(300);
  const q = await p.evaluate(() => ({ play: !document.getElementById('scPlay').classList.contains('hide'), army: !document.getElementById('scArmy').classList.contains('hide'), n: BT.units.length }));
  ok(q.play && !q.army && q.n > 4, '"random" (the default) still goes straight to the table with the bots\' own armies', q);
  console.log(`${pass} passed, ${fail} failed`); await b.close(); process.exit(fail ? 1 : 0);
})().catch(e => { console.error('THREW', e); process.exit(1); });
