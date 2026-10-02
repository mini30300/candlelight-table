// Round 6: the new effects. Doom's saw-shield flies out spinning and comes back to his hand right as the throw ends;
// a void shield shimmers when it swallows a hit.   node r6_fx.js [page] [outdir]
const { chromium } = require('playwright');
const PAGE = process.argv[2] || process.env.PAGE || require('path').resolve(__dirname, '../../../app/src/main/assets/battle-table.html'), OUT = process.argv[3] || (process.env.TEST_OUT || require('os').tmpdir());
let pass = 0, fail = 0; const ok = (c, m, x) => { c ? pass++ : fail++; console.log((c ? 'ok   ' : 'FAIL ') + m + (x !== undefined ? '  ' + JSON.stringify(x) : '')); };
(async () => {
  const b = await chromium.launch({ executablePath: process.env.CHROMIUM_PATH || undefined, args: ['--no-sandbox'] });
  const p = await b.newPage({ viewport: { width: 1100, height: 700 } });
  const errs = []; p.on('pageerror', e => errs.push(String(e.stack || e).slice(0, 400)));
  await p.goto('file://' + PAGE); await p.waitForFunction('window.BT && window.BT.G');
  let r = await p.evaluate(() => { BT.clock(false); BT.setTerrain('flat'); BT.setBuildings(false); BT.size(40);
    BT.units.length = 0; BT.add('doom', -5, 0); BT.add('heavy', 7, 0); BT.units[0].rot = Math.PI/2; BT.units[1].rot = -Math.PI/2;
    Object.assign(BT.cam, { tx:1, tz:0, dist:17, pitch:0.42, yaw:0.25 }); BT.draw();
    const u = BT.units[0]; BT.animate(0, 1, false, 3); const a = u.act;
    return { kind: a && a.kind, proj: a && a.proj, shots: a && a.shots.length, dur: a && +a.dur.toFixed(2) }; });
  ok(r.kind === 'throw' && r.proj === 'saw' && r.shots === 1, 'Doom throws his saw-shield once', r);
  const snaps = [];
  for (const [i, dt] of [[0, 0.62], [1, 0.25], [2, 0.3], [3, 0.3]]) {
    const s = await p.evaluate((dt) => { BT.tick(1/30, Math.round(dt*30)); const f = BT.fxAt('saw'); const u = BT.units[0];
      return { saw: f ? +(f.t / f.dur).toFixed(2) : null, act: !!u.act, gone: !!(u.act && u.act.gear && u.act.gear.javGone) }; }, dt);
    snaps.push(s); await p.screenshot({ path: OUT + '/r6_saw_' + i + '.png' });
  }
  ok(snaps[0].saw != null && snaps[0].saw < 1 && snaps[0].gone, 'the shield is in the air, off his arm', snaps[0]);
  ok(snaps.some(s => s.saw != null && s.saw > 1), 'it turns and comes back', snaps);
  r = await p.evaluate(() => { let k = 0; while (BT.units[0].act && k < 200){ BT.tick(1/30, 1); k++; }
    return { left: BT.fx().filter(k => k === 'saw').length, k }; });
  ok(r.left === 0, 'the shield is home when the throw ends (none left flying)', r);
  // the void shield shimmer
  r = await p.evaluate(() => { BT.units.length = 0; BT.add('heavy', 0, 0); Object.assign(BT.cam, { tx:0, tz:0, dist:10 }); BT.vshield(0); BT.tick(0.12, 1); return BT.fx().filter(k => k === 'vshield').length; });
  ok(r === 1, 'a void shield flash is drawn', r);
  await p.screenshot({ path: OUT + '/r6_vshield.png' });
  ok(errs.length === 0, 'no page errors', errs.slice(0, 3));
  console.log(pass + ' passed, ' + fail + ' failed'); await b.close(); process.exit(fail ? 1 : 0);
})();
