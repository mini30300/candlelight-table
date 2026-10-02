// The defender rolls their own saves: the bot shoots at my heavy armour, my screen asks me to roll the save.
const { chromium } = require('playwright');
const F = 'file://' + (process.env.PAGE || require('path').resolve(__dirname, '../../../app/src/main/assets/battle-table.html'));
const OUT = require('path').join((process.env.TEST_OUT || require('os').tmpdir()), 'shots/dice');
let pass = 0, fail = 0;
const ok = (c, m) => { c ? pass++ : fail++; console.log((c ? '  ok  ' : '  FAIL') + '  ' + m); };
const sleep = ms => new Promise(r => setTimeout(r, ms));
(async () => {
  const b = await chromium.launch({ executablePath: process.env.CHROMIUM_PATH || undefined, args: ['--no-sandbox'] });
  const ctx = await b.newContext({ viewport: { width: 1280, height: 760 } });
  await ctx.addInitScript(() => { try { localStorage.removeItem('bt.autoDice'); } catch (e) {} });
  const p = await ctx.newPage(); const errs = []; p.on('pageerror', e => errs.push(String(e)));
  await p.goto(F); await p.waitForFunction('window.BT && window.BT.G');
  let saw = null;
  for (let attempt = 0; attempt < 6 && !saw; attempt++) {
    await p.evaluate(() => { BT.quit(); BT.setTerrain('flat'); BT.setBuildings(false); BT.size(30);
      BT.mkPlayers(); BT.setList(0, [3,0,0,0]); BT.setList(1, [0,0,0,0,0,0,0,0,0,2]); BT.start();   // my heavy armour vs two heavy machine guns
      const mine = BT.squads().filter(q => q.side === 0), foes = BT.squads().filter(q => q.side === 1);
      mine.forEach((s, i) => BT.place(s.id, -7 + i*7, 0, 0));
      foes.forEach((f, i) => BT.place(f.id, -4 + i*8, 14, Math.PI));
      BT.cam.tx = 0; BT.cam.tz = 6; BT.cam.dist = 30; BT.cam.pitch = 0.7;
      BT.endTurn(); });                                       // straight to the bot's turn
    // the bot shoots; wait until the save is mine to roll (or the bot's shots all missed)
    const t0 = Date.now();
    while (Date.now() - t0 < 25000) {
      const s = await p.evaluate(() => ({ my: BT.myRoll(), tray: BT.tray(), turn: BT.G.turn,
        btn: document.getElementById('btRoll').classList.contains('hide') ? '' : document.getElementById('btRoll').textContent,
        wait: document.getElementById('btTraySt').textContent }));
      if (s.my === 'save:human' && s.btn) { saw = s; break; }
      if (s.turn === 0) break;
      await sleep(250);
    }
  }
  ok(!!saw, 'the bot hit and wounded; my screen asks me to roll the save' + (saw ? ' (' + saw.btn + ')' : ''));
  if (saw) {
    await sleep(300);
    await p.screenshot({ path: `${OUT}/save-1-ask.png` });
    const el = await p.$('#btTray'); if (el) await el.screenshot({ path: `${OUT}/save-1-tray.png` });
    ok(/ทอย.*เซฟ/.test(saw.btn), 'the button says roll the save');
    ok(await p.evaluate(() => BT.G.turn === 1), 'it is still the bot\'s turn while it waits for my save');
    await sleep(1500);
    ok(await p.evaluate(() => BT.tray().pend.length === 1), 'the bot does not carry on until I have rolled');
    await p.click('#btRoll');
    await p.waitForFunction(() => { const t = BT.tray(); return !t.pend.length && t.cur && t.cur.stage === 'save' && t.cur.settled; }, null, { timeout: 6000 });
    await sleep(200);
    if (el) await el.screenshot({ path: `${OUT}/save-2-rolled.png` });
    const r = await p.evaluate(() => ({ cur: BT.tray().cur, last: BT.log().slice(-1)[0].t.replace(/<[^>]+>/g, '') }));
    ok(r.cur.stage === 'save' && !!r.cur.final, 'my save dice settled and the result is shown: ' + r.cur.final + ' — ' + r.last);
  }
  ok(errs.length === 0, errs.length ? 'JS ERRORS: ' + errs.join(' | ') : 'no JS errors');
  console.log(`\n${pass} passed, ${fail} failed`);
  await b.close(); process.exit(fail ? 1 : 0);
})().catch(e => { console.error('THREW', e); process.exit(1); });
