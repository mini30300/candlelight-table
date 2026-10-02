// Round 5a: several squads picked and sent to one spot keep their shape, each within its own move, none on another
const { chromium } = require('playwright');
const F = 'file://' + (process.env.PAGE || require('path').resolve(__dirname, '../../../app/src/main/assets/battle-table.html'));
let pass = 0, fail = 0; const ok = (c, m) => { c ? pass++ : fail++; console.log((c ? 'ok   ' : 'FAIL ') + m); };
(async () => {
  const b = await chromium.launch({ executablePath: process.env.CHROMIUM_PATH || undefined, args: ['--no-sandbox'] });
  const p = await b.newPage({ viewport: { width: 1200, height: 760 } });
  const errs = []; p.on('pageerror', e => errs.push(String(e.stack || e).slice(0, 500)));
  await p.goto(F); await p.waitForFunction('window.BT && window.BT.G');
  await p.evaluate(() => { window.T = {
    setup(A, B){ BT.clock(false); BT.quit(); BT.setTerrain('flat'); BT.setBuildings(false); BT.size(60);
      BT.G.mode = 'pvp'; BT.G.teams = 2; BT.G.perTeam = 1; BT.G.freeFire = false; BT.G.clock = 0; BT.mkPlayers();
      const L = (arr) => { const l = new Array(BT.TYPES.length).fill(0); arr.forEach(([k, n]) => { l[BT.TYPES.findIndex(t => t.k === k)] = n; }); return l; };
      BT.setList(0, L(A)); BT.setList(1, L(B)); BT.players()[0].dep = [-20, 0]; BT.players()[1].dep = [20, 0];
      BT.setAuto(true); BT.start(); BT.dice([]); },
    settle(){ for (let i = 0; i < 600 && BT.walking(); i++) BT.tick(1/30, 3); },
    centers(){ return BT.squads().filter(s => s.side === 0).map(s => { const ms = BT.sqModels(s); return { id: s.id, k: s.k, mv: BT.TYPES.find(t => t.k === s.k).mv,
      x: ms.reduce((a, m) => a + m.x, 0)/ms.length, z: ms.reduce((a, m) => a + m.z, 0)/ms.length, moved: !!s.moved }; }); },
    models(){ return BT.units.map(u => ({ x: u.x, z: u.z, r: u.t, side: u.side })); }
  }; });
  const E = (f, a) => p.evaluate(f, a);

  // 1. every squad at once, a short hop: all move by the same vector, the army's shape kept
  await E(() => { T.setup([['infantry', 2], ['heavy', 1], ['hmg', 1]], [['boy', 1]]); BT.setPhase('move'); });
  const c0 = await E(() => T.centers());
  const ids = await E(() => BT.group('all'));
  ok(ids.length === 4, 'pick all: the four squads that can move (' + ids.length + ')');
  const cx = c0.reduce((a, c) => a + c.x, 0)/c0.length, cz = c0.reduce((a, c) => a + c.z, 0)/c0.length;
  const went = await E(([x, z]) => BT.groupMove(x, z), [cx + 4, cz + 1]);
  await E(() => T.settle());
  const c1 = await E(() => T.centers());
  const dv = c1.map((c, i) => [c.x - c0[i].x, c.z - c0[i].z]);
  const spread = Math.max(...dv.map(d => Math.hypot(d[0] - dv[0][0], d[1] - dv[0][1])));
  ok(went && c1.every(c => c.moved), 'the whole group moved and is marked as moved');
  ok(dv.every(d => Math.abs(Math.hypot(d[0], d[1]) - Math.hypot(4, 1)) < 1.2) && spread < 1.5,
     'each squad moved about the same 4.1" the same way: the shape is kept (' + dv.map(d => Math.hypot(d[0], d[1]).toFixed(1)).join(',') + ', spread ' + spread.toFixed(2) + ')');
  const ov = await E(() => { const u = BT.units, bad = []; for (let i = 0; i < u.length; i++) for (let j = i + 1; j < u.length; j++) if (Math.hypot(u[i].x - u[j].x, u[i].z - u[j].z) < 1.2) bad.push([u[i].t, u[j].t]); return bad; });
  ok(ov.length === 0, 'no two models end on top of each other (' + ov.length + ')');

  // 2. a far spot: each goes only as far as its own move (the slow heavy gun lags behind, nothing teleports)
  await E(() => { T.setup([['infantry', 1], ['hmg', 1]], [['boy', 1]]); BT.setPhase('move'); });
  const d0 = await E(() => T.centers());
  await E(() => BT.group('all')); await E(() => BT.groupMove(0, 0)); await E(() => T.settle());
  const d1 = await E(() => T.centers());
  const far = d1.map((c, i) => ({ k: c.k, went: Math.hypot(c.x - d0[i].x, c.z - d0[i].z), mv: c.mv }));
  ok(far.every(f => f.went <= f.mv + 1.0 && f.went >= f.mv - 1.6), 'a far spot: each squad goes about its own move and no further ' + JSON.stringify(far.map(f => f.k + ' ' + f.went.toFixed(1) + '/' + f.mv)));
  // 3. one pick at a time through the buttons and taps: the group row shows in the movement phase only
  await E(() => { T.setup([['infantry', 2], ['heavy', 1]], [['boy', 1]]); BT.setPhase('move'); });
  const vis = await E(() => !document.getElementById('btGroup').classList.contains('hide'));
  ok(vis, 'the group buttons show in the movement phase');
  await p.click('#btGroup button[data-g="pick"]');
  const box = await p.locator('#btCv').boundingBox();
  const tapAt = async (sx, sy) => { await p.mouse.click(box.x + sx, box.y + sy); await p.waitForTimeout(80); };
  const q2 = await E(() => BT.squads().filter(s => s.side === 0).slice(0, 2).map(s => { const m = BT.sqModels(s)[0]; return { id: s.id, pt: BT.screen(m.x, m.z, 0.9) }; }));
  for (const q of q2) await tapAt(q.pt[0], q.pt[1]);
  const g = await E(() => BT.G.multi);
  ok(Array.isArray(g) && g.length === 2 && q2.every(q => g.includes(q.id)), 'tapping two of our squads puts both in the group (' + JSON.stringify(g) + ')');
  await tapAt(q2[0].pt[0], q2[0].pt[1]);
  const g1 = await E(() => BT.G.multi.slice());
  ok(g1.length === 1 && g1[0] === q2[1].id, 'tapping one again takes it out (' + JSON.stringify(g1) + ')');
  await tapAt(q2[0].pt[0], q2[0].pt[1]);
  const before = await E(() => T.centers());
  const gp = await E(() => { const c = BT.squads().filter(s => s.side === 0).slice(0, 2).map(s => BT.sqModels(s)[0]); const x = Math.max(...BT.units.filter(u => u.side === 0).map(u => u.x)) + 4, z = (c[0].z + c[1].z)/2; return BT.screen(x, z, 0); });
  await tapAt(gp[0], gp[1]);
  await E(() => T.settle());
  const after = await E(() => T.centers());
  const movedIds = after.filter((c, i) => Math.hypot(c.x - before[i].x, c.z - before[i].z) > 1).map(c => c.id).sort();
  ok(JSON.stringify(movedIds) === JSON.stringify(q2.map(q => q.id).sort()), 'a tap on the ground sends exactly the two picked squads (' + JSON.stringify(movedIds) + ')');
  const cleared = await E(() => BT.G.multi == null && !BT.units.some(u => u.sel));
  ok(cleared, 'after the move the group is done and nothing stays highlighted');
  await E(() => BT.setPhase('shoot'));
  const hidden = await E(() => document.getElementById('btGroup').classList.contains('hide') && BT.G.multi == null);
  ok(hidden, 'out of the movement phase the group row hides and the group is dropped');
  // 4. squads that cannot move are left out: one already moved, one engaged
  await E(() => { T.setup([['infantry', 2]], [['boy', 1]]); BT.setPhase('move'); });
  const left = await E(() => { const q = BT.squads().filter(s => s.side === 0); BT.move(q[0], BT.sqModels(q[0])[0].x + 2, BT.sqModels(q[0])[0].z); return BT.group('all').length; });
  ok(left === 1, 'a squad that already moved is not picked by "all" (' + left + ')');
  ok(errs.length === 0, 'no page errors' + (errs.length ? ': ' + errs.slice(0, 2).join(' | ') : ''));
  console.log(pass + ' passed, ' + fail + ' failed'); await b.close(); process.exit(fail ? 1 : 0);
})().catch(e => { console.error('THREW', e); process.exit(1); });
