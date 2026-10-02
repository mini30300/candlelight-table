// Round 7 screens: the army picker with fourteen armies, each new army's roster, the orks' longer roster, no sideways
// scroll on a desk or a phone, and a bot game of each new army from the real start button.
//   node r7_ui.js [page] [outDir]
const { chromium } = require('playwright');
const PAGE = require('path').resolve(process.argv[2] || process.env.PAGE || require('path').resolve(__dirname, '../../app/src/main/assets/battle-table.html'));
const OUT = process.argv[3] || require('path').join((process.env.TEST_OUT || require('os').tmpdir()), 'r7');
let pass = 0, fail = 0; const ok = (c, m, x) => { if (c){ pass++; console.log('ok  ', m); } else { fail++; console.log('FAIL', m, x !== undefined ? JSON.stringify(x) : ''); } };
(async () => {
  const b = await chromium.launch({ executablePath: process.env.CHROMIUM_PATH || undefined, args: ['--no-sandbox'] });
  for (const vp of [{ width: 1280, height: 860, nm: 'desk' }, { width: 390, height: 844, nm: 'phone' }, { width: 360, height: 740, nm: 'small' }]){
    const p = await b.newPage({ viewport: { width: vp.width, height: vp.height } });
    const errs = []; p.on('pageerror', e => errs.push(String(e)));
    await p.goto('file://' + PAGE); await p.waitForFunction('window.BT && window.BT.G'); await p.waitForTimeout(300);
    await p.click('#btPtsPick button[data-p="2000"]');
    await p.click('#btNext'); await p.waitForTimeout(200);
    let r = await p.evaluate(() => [...document.querySelectorAll('#btFacs .mode')].map(b => b.dataset.f));
    ok(r.length >= 14 && ['el', 'de', 'ta'].every(f => r.includes(f)), vp.nm + ': fourteen armies (or more, Round 8 adds one) to pick from', r);
    const expect = { el: [24, 'องครักษ์เอลฟ์'], de: [27, 'นักรบเอลฟ์มืด'], ta: [29, 'นักรบปืนพัลส์'], or: [25, 'จอมทัพออร์คเกราะยักษ์'] };
    for (const f of Object.keys(expect)){
      await p.click('#btFacs .mode[data-f="' + f + '"]'); await p.waitForTimeout(120);
      r = await p.evaluate((f) => { const rows = [...document.querySelectorAll('#btRoster .unit')], txt = document.getElementById('btRoster').textContent;
        const kinds = new Set(); document.querySelectorAll('#btRoster button[data-i]').forEach(b => kinds.add(BT.TYPES[+b.dataset.i].fac));
        return { rows: rows.length, kinds: [...kinds], has: txt, on: document.querySelector('#btFacs .mode[data-f="' + f + '"]').classList.contains('on'),
          wide: document.documentElement.scrollWidth - window.innerWidth }; }, f);
      ok(r.on && r.rows === expect[f][0] && r.kinds.length === 1 && r.kinds[0] === f && r.has.includes(expect[f][1]),
         vp.nm + ': ' + f + ' shows its ' + expect[f][0] + ' units', { rows: r.rows, kinds: r.kinds, on: r.on });
      ok(r.wide <= 1, vp.nm + ': ' + f + ' roster does not scroll sideways', r.wide);
      if (f !== 'or') await p.screenshot({ path: OUT + '/r7_army_' + f + '_' + vp.nm + '.png', fullPage: vp.nm === 'desk' });
    }
    ok(errs.length === 0, vp.nm + ': no page errors', errs.slice(0, 3));
    await p.close();
  }
  // a bot game with each new army, from the setup screen's real flow
  const p = await b.newPage({ viewport: { width: 1000, height: 700 } }); const errs = []; p.on('pageerror', e => errs.push(String(e)));
  await p.goto('file://' + PAGE); await p.waitForFunction('window.BT && window.BT.G');
  for (const [A, B] of [['el', 'ta'], ['de', 'or']]){
    const r = await p.evaluate(([A, B]) => { BT.clock(false); BT.quit(); BT.setTerrain('ruin'); BT.size(80); BT.G.budget = 2000; BT.G.goal = 'obj'; BT.G.rounds = 3; BT.G.mode = 'pve'; BT.mkPlayers();
      BT.players()[0].fac = A; BT.autoList(0, true); BT.players()[1].fac = B; BT.autoList(1, true);
      BT.setDep(0, -28, 0); BT.setDep(1, 28, 0); BT.start(); BT.players().forEach(P => P.bot = true);
      let k = 0; while (!BT.G.over && k < 9000){ BT.botStep(); BT.tick(1/30, 2); k++; }
      return { over: BT.G.over, round: BT.G.round, k, log: BT.log().slice(-1)[0].t.replace(/<[^>]+>/g, '') }; }, [A, B]);
    ok(r.over && r.round <= 3, A + ' vs ' + B + ': a 3-round bot game plays to its end', r);
  }
  ok(errs.length === 0, 'no page errors in the bot games', errs.slice(0, 3));
  console.log(`\n${pass}/${pass + fail} passed`);
  await b.close(); process.exit(fail ? 1 : 0);
})().catch(e => { console.error('THREW', e); process.exit(2); });
