// Two devices, one game: page A plays a whole bot game and records every act it sends; page B only applies those acts.
// After every batch the two boards must be identical (who is where, wounds, phase, VP, CP) — the rules are deterministic
// given the acts, which is what a room relies on.
const { chromium } = require('playwright');
const F = 'file://' + (process.env.PAGE || require('path').resolve(__dirname, '../../../app/src/main/assets/battle-table.html'));
let pass = 0, fail = 0; const ok = (c, m) => { c ? pass++ : fail++; console.log((c ? 'ok   ' : 'FAIL ') + m); };
(async () => {
  const b = await chromium.launch({ executablePath: process.env.CHROMIUM_PATH || undefined, args: ['--no-sandbox'] });
  const A = await b.newPage({ viewport: { width: 900, height: 700 } }), B = await b.newPage({ viewport: { width: 900, height: 700 } });
  const errs = []; [A, B].forEach((p, i) => p.on('pageerror', e => errs.push((i ? 'B: ' : 'A: ') + String(e.stack || e).slice(0, 400))));
  for (const p of [A, B]) { await p.goto(F); await p.waitForFunction('window.BT && window.BT.G'); }
  const teams = +(process.argv[2] || 2);
  for (const p of [A, B]) await p.evaluate((n) => { BT.clock(false); BT.setTerrain('hills'); BT.spectate(n); BT.spec.speed = 4; }, teams);
  await B.evaluate(() => { BT.NET.on = true; BT.NET.owner = false; BT.NET.pid = 'B'; BT.NET.code = 'TEST'; });
  await A.evaluate(() => { BT.NET.on = true; BT.NET.owner = true; BT.NET.pid = 'A'; BT.NET.code = 'TEST'; BT.setServer('http://127.0.0.1:9'); BT.capture(true); });
  const same0 = JSON.stringify(await A.evaluate(() => BT.board())) === JSON.stringify(await B.evaluate(() => BT.board()));
  ok(same0, 'both devices deploy the same armies on the same field');
  let acts = 0, diffs = 0, firstDiff = null, i;
  const norm = (bd) => JSON.stringify({ ...bd, units: bd.units.slice().sort((x, y) => x.id < y.id ? -1 : 1) });
  for (i = 0; i < 2000; i++) {
    const st = await A.evaluate(() => { BT.tick(1/30, 15); return { over: BT.G.over, sent: BT.capture(true) }; });
    if (st.sent.length) { acts += st.sent.length;
      await B.evaluate((list) => { list.forEach(a => { a.pid = 'A'; BT.applyAct(a); }); }, st.sent);
      await B.evaluate(() => BT.tick(1/30, 1));
      const [ba, bb] = [await A.evaluate(() => BT.board()), await B.evaluate(() => BT.board())];
      if (norm(ba) !== norm(bb)) { diffs++; if (!firstDiff) firstDiff = { at: i, a: ba, b: bb, sent: st.sent }; } }
    if (st.over || errs.length) break;
  }
  const endA = await A.evaluate(() => ({ over: BT.G.over, vp: BT.vp(), log: BT.log().slice(-1)[0].t.replace(/<[^>]+>/g, '') }));
  const endB = await B.evaluate(() => ({ over: BT.G.over, vp: BT.vp(), log: BT.log().slice(-1)[0].t.replace(/<[^>]+>/g, '') }));
  console.log('acts', acts, 'steps', i, 'A:', endA.log); console.log('                 B:', endB.log);
  if (firstDiff) {
    const a = firstDiff.a, bb = firstDiff.b; console.log('first difference at step', firstDiff.at, 'after', JSON.stringify(firstDiff.sent).slice(0, 300));
    ['turn','round','phase','over'].forEach(k => { if (a[k] !== bb[k]) console.log('  ', k, a[k], bb[k]); });
    if (JSON.stringify(a.vp) !== JSON.stringify(bb.vp)) console.log('   vp', a.vp, bb.vp);
    if (JSON.stringify(a.cp) !== JSON.stringify(bb.cp)) console.log('   cp', a.cp, bb.cp);
    const ua = Object.fromEntries(a.units.map(u => [u.id, u])), ub = Object.fromEntries(bb.units.map(u => [u.id, u]));
    Object.keys({ ...ua, ...ub }).forEach(id => { const x = JSON.stringify(ua[id]), y = JSON.stringify(ub[id]); if (x !== y) console.log('   unit', id, x, y); });
    const sa = Object.fromEntries(a.squads.map(u => [u.id, u])), sb = Object.fromEntries(bb.squads.map(u => [u.id, u]));
    Object.keys({ ...sa, ...sb }).forEach(id => { const x = JSON.stringify(sa[id]), y = JSON.stringify(sb[id]); if (x !== y) console.log('   squad', id, x, '\n        ', y); });
    if (JSON.stringify(a.obj) !== JSON.stringify(bb.obj)) console.log('   obj', JSON.stringify(a.obj), JSON.stringify(bb.obj));
  }
  ok(endA.over && endB.over, 'the game ends on both devices');
  ok(diffs === 0, `after each of the ${acts} acts both boards match (${diffs} mismatching checks)`);
  ok(JSON.stringify(endA.vp) === JSON.stringify(endB.vp) && endA.log === endB.log, 'same score and same result on both');
  ok(errs.length === 0, 'no page errors' + (errs.length ? ': ' + errs.slice(0, 2).join(' | ') : ''));
  console.log(pass + ' passed, ' + fail + ' failed');
  await b.close(); process.exit(fail ? 1 : 0);
})().catch(e => { console.error('THREW', e); process.exit(1); });
