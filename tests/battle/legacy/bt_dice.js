// The dice tray: aim -> roll to hit -> roll to wound -> the bot saves; auto switch; 10 s auto-roll; phone layout.
const { chromium } = require('playwright');
const F = 'file://' + (process.env.PAGE || require('path').resolve(__dirname, '../../../app/src/main/assets/battle-table.html'));
const OUT = require('path').join((process.env.TEST_OUT || require('os').tmpdir()), 'shots/dice');
let pass = 0, fail = 0;
const ok = (c, m) => { c ? pass++ : fail++; console.log((c ? '  ok  ' : '  FAIL') + '  ' + m); };
const sleep = ms => new Promise(r => setTimeout(r, ms));
(async () => {
  const b = await chromium.launch({ executablePath: process.env.CHROMIUM_PATH || undefined, args: ['--no-sandbox'] });
  for (const [tag, vp] of [['desk', { width: 1366, height: 768 }], ['phone', { width: 390, height: 844 }]]) {
    const ctx = await b.newContext({ viewport: vp, deviceScaleFactor: tag === 'phone' ? 2 : 1, hasTouch: tag === 'phone' });
    await ctx.addInitScript(() => { try { localStorage.removeItem('bt.autoDice'); } catch (e) {} });
    const p = await ctx.newPage();
    const errs = []; p.on('pageerror', e => errs.push(String(e)));
    await p.goto(F); await p.waitForFunction('window.BT && window.BT.G');
    await p.evaluate(() => { BT.setTerrain('flat'); BT.setBuildings(false); BT.size(36);
      BT.mkPlayers(); BT.setList(0, [2,3,0,0]); BT.setList(1, [0,3,0,2]); BT.start(); BT.setPhase('shoot');
      // squads helpers: park one of mine in range of an enemy squad, standing still
      window.ctr = s => { const ms = BT.sqModels(s); return { x: ms.reduce((n, m) => n + m.x, 0)/ms.length, z: ms.reduce((n, m) => n + m.z, 0)/ms.length }; };
      // a spot in range of the enemy squad and clear of every enemy's melee range (tries a ring of spots, like a player picking one)
      window.park = (k, dx, dz) => { const s = BT.squads().find(q => q.side === 0 && !q.shot && (!k || q.k === k)), f = BT.squads().find(q => q.side === 1);
        if (!s || !f) return null; const c = ctr(f), a0 = Math.atan2(dx, dz), r0 = Math.hypot(dx, dz);
        for (let i = 0; i < 24; i++){ const a = a0 + (i % 8)*Math.PI/4, r = r0 + Math.floor(i/8)*2;
          BT.place(s.id, c.x + Math.sin(a)*r, c.z + Math.cos(a)*r, a + Math.PI);
          if (!BT.engaged(s) && BT.atkMath(s, f).shots > 0) break; }
        BT.select(s); return { u: s.id, f: f.id }; }; });
    await sleep(600);
    // park one of mine 7" from a foe, pick it, aim
    const pair = await p.evaluate(() => { const r = park('heavy', 0, 10); const c = ctr(BT.sq(r.f));
      BT.cam.tx = c.x; BT.cam.tz = c.z + 3; BT.cam.dist = 22; BT.cam.pitch = 0.6; return r; });
    const aimed = await p.evaluate(({ u, f }) => BT.aim(BT.sq(u), BT.sq(f), 'atk'), pair);
    ok(aimed === true, tag + ': tapping an enemy aims instead of rolling at once');
    await sleep(400);
    const t0 = await p.evaluate(() => ({ vis: !document.getElementById('btTray').classList.contains('hide'),
      btn: document.getElementById('btRoll').textContent, hide: document.getElementById('btRoll').classList.contains('hide'),
      head: document.getElementById('btTrayT').textContent, st: document.getElementById('btTraySt').textContent, tray: BT.tray() }));
    ok(t0.vis && !t0.hide && /ทอย.*เข้าเป้า/.test(t0.btn), tag + ': the tray shows a "roll to hit" button (' + t0.btn + ')');
    ok(/ยิง/.test(t0.head) && /ต้องได้ 3\+/.test(t0.st), tag + ': header "' + t0.head + '" / "' + t0.st + '"');
    ok(t0.tray.aim && t0.tray.pend.length === 0, tag + ': nothing rolled yet, only aimed');
    await p.screenshot({ path: `${OUT}/${tag}-1-aim.png` });
    await p.click('#btRoll');
    await sleep(250);
    const t1 = await p.evaluate(() => BT.tray());        // read before the screenshot: a screenshot can take longer than a short throw
    await p.screenshot({ path: `${OUT}/${tag}-2-rolling.png` });
    const want = await p.evaluate(({ u, f }) => BT.atkMath(BT.sq(u), BT.sq(f)).shots, pair);
    ok(t1.cur && t1.cur.stage === 'hit' && t1.cur.dice.length === want && want === 6 && !t1.cur.settled, tag + ': the whole squad fires: three heavies, six dice in the air (' + JSON.stringify(t1.cur && t1.cur.dice) + ')');
    await p.waitForFunction(() => { const t = BT.tray(); return t.cur && t.cur.settled; }, null, { timeout: 5000 });
    await sleep(200);
    await p.screenshot({ path: `${OUT}/${tag}-3-hit-settled.png` });
    const el = await p.$('#btTray'); if (el) await el.screenshot({ path: `${OUT}/${tag}-3-tray.png` });
    const t2 = await p.evaluate(() => ({ tray: BT.tray(), my: BT.myRoll(), btn: document.getElementById('btRoll').textContent, st: document.getElementById('btTraySt').textContent }));
    console.log('       after the hit roll:', JSON.stringify(t2.tray.pend), t2.my, '|', t2.st, '|', t2.btn);
    if (t2.tray.pend.length) {
      ok(t2.my === 'wound:human' && /ทอย.*เจาะเกราะ/.test(t2.btn), tag + ': my next roll is the wound roll (' + t2.btn + ')');
      await p.click('#btRoll');
      await p.waitForFunction(() => BT.tray().pend.length === 0 || BT.tray().pend[0].stage === 'save', null, { timeout: 6000 });
      const t3 = await p.evaluate(() => BT.tray());
      console.log('       after the wound roll:', JSON.stringify(t3.pend));
      // the bot rolls its own save
      await p.waitForFunction(() => BT.tray().pend.length === 0, null, { timeout: 12000 }).catch(() => {});
      const t4 = await p.evaluate(() => ({ tray: BT.tray(), last: BT.log().slice(-1)[0].t }));
      ok(t4.tray.pend.length === 0, tag + ': the attack finished: ' + t4.last.replace(/<[^>]+>/g, ''));
      await p.waitForFunction(() => { const t = BT.tray(); return t.cur && t.cur.settled; }, null, { timeout: 5000 }).catch(() => {});
      await sleep(150);
      if (el) await el.screenshot({ path: `${OUT}/${tag}-4-last.png` });
    } else ok(t2.tray.cur && /พลาดหมด/.test(t2.st + t2.tray.cur.final), tag + ': missed everything, attack over');

    // auto: a second unit rolls by itself
    await p.evaluate(() => BT.setAuto(true));
    const pair2 = await p.evaluate(() => park(null, 10, 0));
    if (pair2) {
      await p.evaluate(({ u, f }) => BT.aim(BT.sq(u), BT.sq(f), 'atk'), pair2);
      await sleep(250);
      ok(await p.evaluate(() => document.getElementById('btRoll').classList.contains('hide')), tag + ': with auto on there is no button to press');
      await p.waitForFunction((u) => { const t = BT.tray(); return !t.aim && !t.pend.some(x => x.u === u); }, pair2.u, { timeout: 15000 }).catch(() => {});
      const t5 = await p.evaluate((u) => ({ tray: BT.tray(), shot: (BT.sq(u) || {}).shot, last: BT.log().slice(-1)[0].t }), pair2.u);
      ok(!t5.tray.aim && t5.shot === true && !t5.tray.pend.length, tag + ': auto rolled every stage by itself: ' + t5.last.replace(/<[^>]+>/g, ''));
    }
    // the 10 s timeout rolls for someone who does not tap
    await p.evaluate(() => BT.setAuto(false));
    const pair3 = await p.evaluate(() => { const r = park(null, -10, 0); if (r) BT.aim(BT.sq(r.u), BT.sq(r.f), 'atk'); return r; });
    if (pair3 && tag === 'desk') {
      await p.waitForFunction(() => !document.getElementById('btRoll').classList.contains('hide'), null, { timeout: 8000 });
      await sleep(5000);
      const mid = await p.evaluate(() => ({ aim: !!BT.tray().aim, btn: document.getElementById('btRoll').textContent }));
      ok(mid.aim && /[4-6] วิ/.test(mid.btn), 'after 5 s still waiting for the tap, countdown shows (' + mid.btn + ')');
      await sleep(6500);
      const late = await p.evaluate((u) => ({ aim: !!BT.tray().aim, shot: (BT.sq(u) || {}).shot }), pair3.u);
      ok(!late.aim && late.shot === true, 'after 10 s the dice were rolled for them');
    }
    // cancel
    const pair4 = await p.evaluate(() => { const r = park(null, 0, -10); if (r) BT.aim(BT.sq(r.u), BT.sq(r.f), 'atk'); return r; });
    if (pair4) { await sleep(300);
      const vis = await p.isVisible('#btAimX'); if (vis) await p.click('#btAimX'); await sleep(200);
      ok(vis && !(await p.evaluate(() => BT.tray().aim)), tag + ': the aim can be cancelled'); }
    ok(errs.length === 0, tag + ': ' + (errs.length ? 'JS ERRORS: ' + errs.join(' | ') : 'no JS errors'));
    await ctx.close();
  }
  console.log(`\n${pass} passed, ${fail} failed`);
  await b.close(); process.exit(fail ? 1 : 0);
})().catch(e => { console.error('THREW', e); process.exit(1); });
