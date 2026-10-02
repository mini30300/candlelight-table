const { chromium } = require('playwright');
const F = 'file://' + (process.env.PAGE || require('path').resolve(__dirname, '../../../app/src/main/assets/battle-table.html'));
(async () => {
  const b = await chromium.launch({ executablePath: process.env.CHROMIUM_PATH || undefined, args: ['--no-sandbox'] });
  const p = await b.newPage({ viewport: { width: 1366, height: 768 } });
  const errs = []; p.on('pageerror', e => errs.push(String(e)));
  await p.goto(F); await p.waitForFunction('window.BT && window.BT.G');
  let tot = 0, solid = 0, stack = 0, cross = 0;
  for (let i = 0; i < 10; i++) {
    const r = await p.evaluate(() => {
      if (BT.G.on) BT.quit();
      document.getElementById('btNew').click();
      document.getElementById('btNext').click();
      BT.setList(0, [3,1,2,2]); BT.setList(1, [3,1,1,3]); BT.start();
      let inSolid = 0, stacked = 0, wrongHalf = 0;
      BT.units.forEach((u, i) => {
        if (BT.blockAt(u.x, u.z)) inSolid++;
        BT.units.forEach((q, j) => { if (j > i && Math.hypot(q.x-u.x, q.z-u.z) < 1.5) stacked++; });
        if (u.side === 0 && u.z > 0) wrongHalf++;
        if (u.side === 1 && u.z < 0) wrongHalf++;
      });
      return { n: BT.units.length, inSolid, stacked, wrongHalf, props: BT.props().length };
    });
    tot += r.n; solid += r.inSolid; stack += r.stacked; cross += r.wrongHalf;
    console.log(`map ${i}: ${r.props} props -> ${r.inSolid} in solid terrain, ${r.stacked} stacked, ${r.wrongHalf} on the wrong half`);
  }
  console.log(`TOTAL of ${tot} models: ${solid} inside terrain, ${stack} overlapping, ${cross} across the midline`);
  console.log(errs.length ? 'ERRORS ' + errs.join(' | ') : 'no js errors');
  await b.close();
})().catch(e => { console.error(e.message); process.exit(1); });
