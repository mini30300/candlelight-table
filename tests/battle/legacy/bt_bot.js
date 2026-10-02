// Play a whole PvE game: the human side acts through the same code a tap would call,
// the bot answers on its own timer, and the match has to actually reach a result.
const { chromium } = require('playwright');
const F = 'file://' + (process.env.PAGE || require('path').resolve(__dirname, '../../../app/src/main/assets/battle-table.html'));
const fail = [];
const ok = (c, m) => { console.log((c ? '  ok   ' : '  FAIL ') + m); if (!c) fail.push(m); };

(async () => {
  const b = await chromium.launch({ executablePath: process.env.CHROMIUM_PATH || undefined, args: ['--no-sandbox'] });
  const p = await b.newPage({ viewport: { width: 1100, height: 760 }, deviceScaleFactor: 1 });
  const errs = []; p.on('pageerror', e => errs.push(String(e)));
  p.on('console', m => { if (m.type() === 'error') errs.push('console: ' + m.text()); });
  await p.goto(F);
  await p.waitForFunction('window.BT && window.BT.G');
  await p.waitForTimeout(700);

  // PvE is the default mode; keep the table small so the two sides actually meet
  // my saves roll themselves (the "ออโต้" switch): nobody is here to tap the tray's button
  await p.evaluate(() => { BT.setAuto(true); BT.size(36); BT.setList(0, [1,3,1,0]); BT.setList(1, [0,3,0,2]); BT.start(); });
  await p.waitForTimeout(900);
  ok(await p.evaluate(() => BT.G.mode === 'pve'), 'PvE is the default mode');
  ok(await p.evaluate(() => BT.live(0) === 23 && BT.live(1) === 25 && BT.squads().length === 10), 'both armies on the table as squads');

  let rounds = 0, botActs = 0;
  for (let step = 0; step < 40; step++) {
    const st = await p.evaluate(() => ({ turn: BT.G.turn, over: BT.G.over, round: BT.G.round, n: BT.log().length, a: BT.live(0), b: BT.live(1) }));
    if (st.over) break;
    if (st.turn === 0) {
      // my turn, phase by phase: every squad heads for the nearest enemy squad, fires what it can, then charges if close
      await p.waitForFunction(() => BT.phase() === 'move' || BT.G.over || BT.G.turn !== 0, null, { timeout: 20000 }).catch(() => {});
      await p.evaluate(() => {
        const ctr = s => { const ms = BT.sqModels(s); return { x: ms.reduce((n, m) => n + m.x, 0)/ms.length, z: ms.reduce((n, m) => n + m.z, 0)/ms.length }; };
        const near = s => { const c = ctr(s); let best = null, bd = 1e9; BT.squads().filter(q => q.side === 1).forEach(f => { const d = Math.hypot(ctr(f).x - c.x, ctr(f).z - c.z); if (d < bd) { bd = d; best = f; } }); return [best, bd]; };
        if (BT.G.over || BT.G.turn !== 0 || BT.phase() !== 'move') return;
        BT.squads().filter(s => s.side === 0).forEach(s => { const [f, d] = near(s); if (!f) return; const T = BT.TYPES.find(t => t.k === s.k), c = ctr(s), fc = ctr(f);
          const reach = T.gun ? T.gun.rng : 4; if (d <= reach*0.8) return;
          const k = Math.min(T.mv, d - reach*0.6) / d; for (let a = 0; a < 6; a++){ if (BT.move(s, c.x + (fc.x - c.x)*k + a*0.7, c.z + (fc.z - c.z)*k)) break; } });
        BT.flush(true); BT.nextPhase();
        BT.squads().filter(s => s.side === 0).forEach(s => { const [f] = near(s); if (f && BT.TYPES.find(t => t.k === s.k).gun) BT.shootAt(s, f); });
        BT.flush(true); BT.nextPhase();
        BT.squads().filter(s => s.side === 0 && s.k === 'hoplite').forEach(s => { const [f] = near(s); if (f) BT.charge(s, f); BT.flush(true); });
        BT.flush(true); BT.nextPhase();
      });
      await p.waitForFunction(() => BT.G.turn !== 0 || BT.G.over, null, { timeout: 60000 }).catch(() => {});
      rounds++;
      await p.waitForTimeout(250);
    } else {
      const n0 = await p.evaluate(() => BT.log().length);
      // the bot rolls real dice in the tray and waits for my saves: let its whole turn play out
      await p.waitForFunction(() => BT.G.turn === 0 || BT.G.over, null, { timeout: 120000 }).catch(() => {});
      const n1 = await p.evaluate(() => BT.log().length);
      if (n1 > n0) botActs++;
    }
  }
  const end = await p.evaluate(() => ({ over: BT.G.over, round: BT.G.round, a: BT.live(0), b: BT.live(1), last: BT.log().slice(-3).map(l => l.t) }));
  ok(botActs > 0, 'the bot takes its own turns (' + botActs + ' bot turns logged)');
  ok(end.over === true, 'the match reaches a result');
  ok(end.a === 0 || end.b === 0 || /ครบ 5 รอบ/.test(end.last.join(' ')), 'it ends by wipe-out or on victory points after five rounds');
  console.log('  final: round', end.round, '·', end.a, 'vs', end.b);
  console.log('  last lines:'); end.last.forEach(l => console.log('    ' + l.replace(/<[^>]+>/g, '')));
  await p.screenshot({ path: (process.env.TEST_OUT || require('os').tmpdir()) + '/shots/bt/v2-pve-end.png' });
  await b.close();
  console.log(errs.length ? '\nPAGE ERRORS:\n' + errs.join('\n') : '\nno page errors');
  if (errs.length) fail.push('page errors');
  console.log(fail.length ? '\n' + fail.length + ' FAILED' : '\nall checks passed');
  process.exit(fail.length ? 1 : 0);
})().catch(e => { console.error(e); process.exit(1); });
