// Two factions, every new unit: build both armies, play bot vs bot (spectator x4) to the end, screenshots on the way.
const { chromium } = require('playwright');
const F = 'file://' + (process.env.PAGE || require('path').resolve(__dirname, '../../../app/src/main/assets/battle-table.html'));
const OUT = (process.env.TEST_OUT || require('os').tmpdir()) + '/shots/fac'; require('fs').mkdirSync(OUT, { recursive: true });
const fail = []; const ok = (c, m) => { console.log((c ? '  ok   ' : '  FAIL ') + m); if (!c) fail.push(m); };
(async () => {
  const b = await chromium.launch({ executablePath: process.env.CHROMIUM_PATH || undefined, args: ['--no-sandbox'] });
  const p = await b.newPage({ viewport: { width: 1146, height: 705 } });
  const errs = []; p.on('pageerror', e => errs.push(String(e)));
  await p.goto(F); await p.waitForFunction('window.BT && window.BT.G'); await p.waitForTimeout(500);
  // army screen: faction tiles switch the roster
  await p.evaluate(() => { BT.mkPlayers(); });
  const kinds = await p.evaluate(() => BT.TYPES.map(t => t.k + ':' + t.fac).join(' '));
  console.log(kinds);
  // (Round 6 added 58 units and a secret hero after the first 89)
  ok((await p.evaluate(() => BT.TYPES.length >= 89 && BT.TYPES.slice(0, 89).every(t => t.fac !== '*'))), '89 unit types in eleven armies, and the ones added since');
  // spectator: every side a bot, bots pick a faction each
  await p.evaluate(() => { BT.setTerrain('hills'); BT.setBuildings(true, 1); BT.spectate(4); });
  await p.waitForTimeout(600);
  const facs = await p.evaluate(() => BT.players().map(P => P.fac + ':' + P.list.join(',')));
  console.log('bot armies', facs.join(' | '));
  const seen = await p.evaluate(() => [...new Set(BT.units.map(u => u.k))].join(','));
  console.log('on the table', seen);
  await p.evaluate(() => { BT.spec.speed = 4; BT.fit(); });
  let over = false, t0 = Date.now(), n = 0;
  while (!over && Date.now() - t0 < 150000){ await p.waitForTimeout(3000);
    over = await p.evaluate(() => BT.G.over); if (n++ % 5 === 0) await p.screenshot({ path: `${OUT}/spec-${n}.png` }); }
  ok(over, 'bot vs bot match reached a result');
  const log = await p.evaluate(() => BT.log().map(l => l.t).join('\n'));
  ok(/รักษา|ยิง|ตี/.test(log), 'log has attacks');
  console.log(log.split('\n').slice(-8).join('\n'));
  ok(!errs.length, 'no page errors ' + errs.slice(0,3).join(' | '));
  console.log(fail.length ? 'FAILURES: ' + fail.length : 'all checks passed');
  await b.close();
})();
