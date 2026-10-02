// The rules the owner chose, checked one at a time.
const { chromium } = require('playwright');
const F = 'file://' + (process.env.PAGE || require('path').resolve(__dirname, '../../../app/src/main/assets/battle-table.html'));
let pass = 0, fail = 0;
const ok = (c, m) => { c ? pass++ : fail++; console.log((c ? '  ok  ' : '  FAIL') + '  ' + m); };

(async () => {
  const b = await chromium.launch({ executablePath: process.env.CHROMIUM_PATH || undefined, args: ['--no-sandbox'] });
  const p = await b.newPage({ viewport: { width: 1366, height: 768 } });
  const errs = []; p.on('pageerror', e => errs.push(String(e)));
  await p.goto(F); await p.waitForFunction('window.BT && window.BT.G'); await p.waitForTimeout(400);

  // ── 2v2 ────────────────────────────────────────────────────────────────
  await p.click('#btModes .mode[data-g="team"]'); await p.waitForTimeout(200);
  ok(await p.isVisible('#btTeamOpt'), 'ทีม mode reveals the team-size picker');
  const r1 = await p.evaluate(() => ({ teams: BT.G.teams, per: BT.G.perTeam }));
  ok(r1.teams === 2 && r1.per === 2, `2v2 = 2 teams of 2 (got ${r1.teams}x${r1.per})`);

  await p.click('#btNext'); await p.waitForTimeout(300);
  const pl = await p.evaluate(() => BT.players().map(x => ({ t: x.team, n: x.nm, pts: BT.teamPts(x.team) })));
  ok(pl.length === 4, `four players built (got ${pl.length})`);
  ok(pl[0].t === 0 && pl[1].t === 0 && pl[2].t === 1 && pl[3].t === 1, 'players split 2 per team');

  const share = await p.evaluate(() => ({ share: BT.G.budget / BT.G.perTeam, p0: BT.G.players[0].list.reduce((a, b, i) => a + b * BT.TYPES[i].pts, 0) }));
  ok(share.p0 <= share.share, `each player spends only their own share (${share.p0} <= ${share.share})`);
  const tp = await p.evaluate(() => BT.teamPts(0));
  ok(tp > share.share, `team total combines both lists (${tp} > ${share.share})`);

  // ── deployment distances ───────────────────────────────────────────────
  await p.click('#btStart'); await p.click('#btStart'); await p.click('#btStart'); await p.click('#btStart');
  await p.waitForTimeout(300);
  ok(await p.isVisible('#scDeploy'), 'after the last player we reach the deployment page');

  const d = await p.evaluate(() => {
    BT.setDep(0, -18, -12);
    return { mate: BT.depWhyNot(1, -15, -12), foe: BT.depWhyNot(2, -10, -12), fine: BT.depWhyNot(2, 18, 12) };
  });
  ok(!!d.mate, 'a team-mate 3" away is refused: ' + (d.mate || '(allowed!)'));
  ok(!!d.foe, 'an enemy 8" away is refused: ' + (d.foe || '(allowed!)'));
  ok(!d.fine, 'a spot far from everyone is allowed');
  const mateOk = await p.evaluate(() => BT.depWhyNot(1, -12, -12));
  ok(!mateOk, 'a team-mate 6" away is allowed (only 5" needed)');

  // ── play: team turn, friendly fire, done buttons ───────────────────────
  await p.evaluate(() => { BT.players().forEach((x, i) => { x.dep = null; }); BT.players().forEach((x, i) => { x.dep = BT.autoDep(i); }); BT.start(); });
  await p.waitForTimeout(900);
  const g = await p.evaluate(() => ({ n: BT.units.length, t0: BT.live(0), t1: BT.live(1), turn: BT.G.turn,
    owners: Array.from(new Set(BT.units.map(u => u.pl))).sort() }));
  ok(g.n > 0 && g.t0 > 0 && g.t1 > 0, `both teams on the table (${g.t0} vs ${g.t1})`);
  ok(g.owners.length === 4, `every player's models are on the table (${g.owners.join(',')})`);

  const ff = await p.evaluate(() => {
    const a = BT.units.find(u => u.side === 0), mate = BT.units.find(u => u.side === 0 && u.pl !== a.pl), foe = BT.units.find(u => u.side === 1);
    return { mate: BT.canTarget(a, mate), foe: BT.canTarget(a, foe), self: BT.canTarget(a, a) };
  });
  ok(ff.mate === false, 'cannot target a team-mate with free fire off');
  ok(ff.foe === true, 'can target the other team');
  ok(ff.self === false, 'cannot target itself');

  const doneFlow = await p.evaluate(() => {
    const before = BT.G.turn + ':' + BT.phase();
    BT.done(0);
    const mid = { turn: BT.G.turn + ':' + BT.phase(), p0done: BT.G.players[0].done };
    const mine = BT.units.find(u => u.pl === 0);
    const locked = !BT.canAct(mine);
    BT.done(1);
    return { before, mid, locked, after: BT.G.turn + ':' + BT.phase() };
  });
  ok(doneFlow.mid.turn === doneFlow.before, 'one player finishing does not end the team\'s phase');
  ok(doneFlow.locked, 'that player\'s models lock once they finish');
  ok(doneFlow.after !== doneFlow.before, 'the phase moves on once every player on the team has finished (' + doneFlow.before + ' → ' + doneFlow.after + ')');

  // ── free fire on ───────────────────────────────────────────────────────
  const ffOn = await p.evaluate(() => { BT.G.freeFire = true;
    const a = BT.units.find(u => u.side === 0), mate = BT.units.find(u => u.side === 0 && u.pl !== a.pl);
    const r = BT.canTarget(a, mate); BT.G.freeFire = false; return r; });
  ok(ffOn === true, 'free fire lets you shoot your own team');

  // ── free-for-all grows the table ───────────────────────────────────────
  await p.evaluate(() => BT.quit());
  await p.click('#btModes .mode[data-g="ffa"]'); await p.waitForTimeout(150);
  await p.evaluate(() => { document.getElementById('btFfaN').value = 8;
    document.getElementById('btFfaN').dispatchEvent(new Event('input')); });
  await p.waitForTimeout(300);
  const ffa = await p.evaluate(() => ({ teams: BT.G.teams, w: BT.table.w, d: BT.table.d, cap: BT.depCapacity(BT.table.w, BT.table.d), warn: document.getElementById('btRoom').textContent }));
  ok(ffa.teams === 8, `8-player free-for-all makes 8 teams (got ${ffa.teams})`);
  ok(ffa.cap >= 8, `the table was grown to hold 8 landing spots (${ffa.w}x${ffa.d}, holds ${ffa.cap})`);
  ok(/ขยายโต๊ะ/.test(ffa.warn), 'and it says why it grew the table');

  ok(errs.length === 0, errs.length ? 'JS ERRORS: ' + errs.join(' | ') : 'no JS errors');
  console.log(`\n${pass} passed, ${fail} failed`);
  await b.close();
  process.exit(fail ? 1 : 0);
})().catch(e => { console.error(e.message); process.exit(1); });
