// The countdown the owner asked for: it starts when one team-mate is done and ends the turn.
const { chromium } = require('playwright');
const F = 'file://' + (process.env.PAGE || require('path').resolve(__dirname, '../../../app/src/main/assets/battle-table.html'));
let pass = 0, fail = 0;
const ok = (c, m) => { c ? pass++ : fail++; console.log((c ? '  ok  ' : '  FAIL') + '  ' + m); };
(async () => {
  const b = await chromium.launch({ executablePath: process.env.CHROMIUM_PATH || undefined, args: ['--no-sandbox'] });
  const p = await b.newPage({ viewport: { width: 1366, height: 768 } });
  const errs = []; p.on('pageerror', e => errs.push(String(e)));
  await p.goto(F); await p.waitForFunction('window.BT && window.BT.G');

  // 2v2 with a 25s clock
  await p.evaluate(() => { BT.G.mode = 'team'; BT.G.teams = 2; BT.G.perTeam = 2; BT.G.clock = 25;
    BT.mkPlayers(); BT.G.players.forEach(x => { x.list = [1,2,1,1]; x.dep = null; });
    BT.G.players.forEach((x, i) => { x.dep = BT.autoDep(i); }); BT.start(); });
  await p.waitForTimeout(600);
  ok(await p.evaluate(() => BT.G.timeLeft === 0), 'no countdown while nobody has finished');
  await p.evaluate(() => BT.done(0));
  await p.waitForTimeout(400);
  const t1 = await p.evaluate(() => BT.G.timeLeft);
  ok(t1 > 0 && t1 <= 25, `the countdown starts when the first team-mate finishes (${t1.toFixed(1)}s left)`);
  ok(/วิ/.test(await p.textContent('#btTurn')), 'the turn bar shows the seconds');
  await p.waitForTimeout(1200);
  const t2 = await p.evaluate(() => BT.G.timeLeft);
  ok(t2 < t1, `it counts down (${t1.toFixed(1)} -> ${t2.toFixed(1)})`);
  // run it out
  const before = await p.evaluate(() => BT.G.turn + ':' + BT.phase());
  await p.evaluate(() => { BT.G.timeLeft = 0.2; });
  await p.waitForTimeout(900);
  const after = await p.evaluate(() => ({ turn: BT.G.turn + ':' + BT.phase(), left: BT.G.timeLeft, log: BT.log().map(l => l.base || l.t).join('|') }));
  ok(after.turn !== before, 'running out ends the team\'s phase even though one player never finished (' + before + ' → ' + after.turn + ')');
  ok(/หมดเวลา/.test(after.log), 'and the log says why');

  // a lone player (free-for-all) gets a clock from the start of their turn
  await p.evaluate(() => { BT.quit(); BT.G.mode = 'ffa'; BT.G.teams = 3; BT.G.perTeam = 1; BT.G.clock = 25;
    BT.mkPlayers(); BT.G.players.forEach(x => { x.list = [1,2,1,1]; x.dep = null; });
    BT.G.players.forEach((x, i) => { x.dep = BT.autoDep(i); }); BT.start(); });
  await p.waitForTimeout(500);
  const solo = await p.evaluate(() => BT.G.timeLeft);
  ok(solo > 0, `a lone player is on the clock from the start of the turn (${solo.toFixed(1)}s)`);

  // clock off means no clock
  await p.evaluate(() => { BT.quit(); BT.G.clock = 0; BT.mkPlayers();
    BT.G.players.forEach(x => { x.list = [1,2,1,1]; x.dep = null; });
    BT.G.players.forEach((x, i) => { x.dep = BT.autoDep(i); }); BT.start(); });
  await p.waitForTimeout(500);
  ok(await p.evaluate(() => BT.G.timeLeft === 0), 'with the clock off nothing counts down');

  ok(errs.length === 0, errs.length ? 'JS ERRORS: ' + errs.join(' | ') : 'no JS errors');
  console.log(`\n${pass} passed, ${fail} failed`);
  await b.close(); process.exit(fail ? 1 : 0);
})().catch(e => { console.error(e.message); process.exit(1); });
