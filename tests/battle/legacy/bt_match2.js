// Same as bt_match but letting the walk animation actually run between turns,
// which is what the real game does — a tight loop makes the bots log moves they never take.
const { chromium } = require('playwright');
const F = 'file://' + (process.env.PAGE || require('path').resolve(__dirname, '../../../app/src/main/assets/battle-table.html'));
let fail = 0;
(async () => {
  const b = await chromium.launch({ executablePath: process.env.CHROMIUM_PATH || undefined, args: ['--no-sandbox'] });
  const p = await b.newPage({ viewport: { width: 1366, height: 768 } });
  const errs = []; p.on('pageerror', e => errs.push(String(e)));
  await p.goto(F); await p.waitForFunction('window.BT && window.BT.G');

  for (const [label, mode, teams, per] of [['1v1','pvp',2,1], ['2v2','team',2,2], ['4v4','team',2,4], ['FFA 4','ffa',4,1], ['FFA 6','ffa',6,1]]) {
    await p.evaluate(([mode, teams, per]) => {
      BT.quit(); BT.G.mode = mode; BT.G.teams = teams; BT.G.perTeam = per; BT.G.clock = 0;
      BT.mkPlayers();
      BT.G.players.forEach(function (x) { x.bot = true; x.list = [1,2,1,1]; x.dep = null; });
      BT.G.players.forEach(function (x, i) { x.dep = BT.autoDep(i); });
      BT.start();
    }, [mode, teams, per]);
    const start = await p.evaluate(() => ({ n: BT.units.length, solid: BT.units.filter(u => BT.blockAt(u.x, u.z)).length }));
    let guard = 0;
    while (guard++ < 40) {
      const over = await p.evaluate(() => BT.G.over);
      if (over) break;
      await p.evaluate(() => { while (BT.botStep()); });
      await p.waitForFunction('BT.walking() === 0', null, { timeout: 8000 }).catch(() => {});
      await p.evaluate(() => BT.endTurn());
      await p.waitForTimeout(40);
    }
    const r = await p.evaluate(() => {
      const log = BT.log().map(l => l.base || l.t);
      let closest = 1e9;
      BT.units.forEach(a => BT.units.forEach(c => { if (a.side !== c.side) closest = Math.min(closest, Math.hypot(a.x-c.x, a.z-c.z)); }));
      return { left: BT.units.length, over: BT.G.over, round: BT.G.round,
               shots: log.filter(t => /ยิง |ตี /.test(t)).length,
               kills: log.filter(t => /ล้ม!/.test(t)).length,
               closest: closest > 1e8 ? -1 : Math.round(closest*10)/10,
               last: (log[log.length-1] || '').replace(/<[^>]+>/g, '') };
    });
    const good = r.over && r.shots > 0 && start.solid === 0;
    if (!good) fail++;
    console.log(`${good ? '  ok  ' : '  FAIL'}  ${label.padEnd(6)} ${start.n} models -> ${r.left} left · ${r.shots} shots · ${r.kills} kills · ended round ${r.round}`);
    console.log(`          ${r.last}`);
  }
  console.log(errs.length ? '\nJS ERRORS: ' + errs.join(' | ') : '\nno js errors');
  if (errs.length) fail++;
  await b.close(); process.exit(fail ? 1 : 0);
})().catch(e => { console.error(e.message); process.exit(1); });
