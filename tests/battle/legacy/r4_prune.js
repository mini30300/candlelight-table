// Two devices, one charge: the target's overwatch kills the charger. The owner's device drops the dead charge when its
// dice stop; the other device must drop it at the same point in the acts, not when its own dice stop, or it starts the
// fight phase later with a different fight order. Device B never ticks here, so only the acts move it.
const { chromium } = require('playwright');
const F = 'file://' + (process.env.PAGE || require('path').resolve(__dirname, '../../../app/src/main/assets/battle-table.html'));
let pass = 0, fail = 0; const ok = (c, m) => { c ? pass++ : fail++; console.log((c ? 'ok   ' : 'FAIL ') + m); };
(async () => {
  const b = await chromium.launch({ executablePath: process.env.CHROMIUM_PATH || undefined, args: ['--no-sandbox'] });
  const A = await b.newPage({ viewport: { width: 900, height: 700 } }), B = await b.newPage({ viewport: { width: 900, height: 700 } });
  const errs = []; [A, B].forEach((p, i) => p.on('pageerror', e => errs.push((i ? 'B: ' : 'A: ') + String(e.stack || e).slice(0, 300))));
  for (const p of [A, B]) { await p.goto(F); await p.waitForFunction('window.BT && window.BT.G'); }
  const setup = () => { BT.clock(false); BT.quit(); BT.setTerrain('flat'); BT.setBuildings(false); BT.size(60);
    BT.G.mode = 'pvp'; BT.G.teams = 2; BT.G.perTeam = 1; BT.G.freeFire = false; BT.G.clock = 0; BT.G.budget = 2000; BT.mkPlayers();
    const L = (arr) => { const l = new Array(BT.TYPES.length).fill(0); arr.forEach(([k, n]) => { l[BT.TYPES.findIndex(t => t.k === k)] = n; }); return l; };
    BT.setList(0, L([['sniper', 1], ['infantry', 1]])); BT.setList(1, L([['flamer', 1], ['hmg', 1]]));
    BT.players()[0].dep = [-20, 0]; BT.players()[1].dep = [20, 0]; BT.start(); BT.dice([]);
    BT.players().forEach(P => { P.bot = true; P.cp = 3; });
    const sq = (pl, k) => BT.squads().find(s => s.pl === pl && s.k === k);
    BT.place(sq(0, 'sniper').id, 0, 0, Math.PI/2); BT.place(sq(1, 'flamer').id, 6, 0, -Math.PI/2);
    BT.place(sq(0, 'infantry').id, 0, -14, Math.PI/2); BT.place(sq(1, 'hmg').id, 1.6, -14, -Math.PI/2);   // already locked in melee
    BT.G.turn = 0; BT.setPhase('charge');
    return { phase: BT.phase(), eng: BT.engaged(sq(0, 'infantry')) }; };
  const sa = await A.evaluate(setup), sb = await B.evaluate(setup);
  ok(sa.phase === 'charge' && sa.eng && JSON.stringify(sa) === JSON.stringify(sb), 'both devices: charge phase, a second pair already in melee ' + JSON.stringify(sa));
  await B.evaluate(() => { BT.NET.on = true; BT.NET.owner = false; BT.NET.pid = 'B'; BT.NET.code = 'TEST'; });
  await A.evaluate(() => { BT.NET.on = true; BT.NET.owner = true; BT.NET.pid = 'A'; BT.NET.code = 'TEST'; BT.setServer('http://127.0.0.1:9'); BT.capture(true); });
  // A: the sniper charges the flamers; they fire overwatch (a torrent, it hits by itself) and burn him down
  const ra = await A.evaluate(() => { const sq = (pl, k) => BT.squads().find(s => s.pl === pl && s.k === k);
    const why = BT.charge(sq(0, 'sniper'), sq(1, 'flamer'));
    BT.dice([6,6,6,6,6,6,6,6,6,6, 1,1,1,1,1,1,1,1,1,1]);
    BT.roll({ yes: true }); BT.flush(true);
    const acts = BT.capture(true); BT.nextPhase();                      // the owner ends the charge phase (its bot sends endph)
    return { why, acts, alive: BT.squads().some(s => s.k === 'sniper'), phase: BT.phase(), pend: BT.pend(), fights: BT.fights().length }; });
  ok(ra.why === '' && !ra.alive, `A: the charger dies to overwatch (${ra.acts.map(a => a.a).join(',')})`);
  // B: the same acts, then the owner's end of phase, with no tick in between
  const rb = await B.evaluate((acts) => { acts.forEach(a => { a.pid = 'A'; BT.applyAct(a); });
    BT.applyAct({ a: 'endph', ph: 'charge', pid: 'A' });
    return { alive: BT.squads().some(s => s.k === 'sniper'), phase: BT.phase(), pend: BT.pend(), fights: BT.fights().length }; }, ra.acts);
  console.log('A', JSON.stringify({ phase: ra.phase, pend: ra.pend, fights: ra.fights }));
  console.log('B', JSON.stringify({ phase: rb.phase, pend: rb.pend, fights: rb.fights }));
  ok(!rb.alive && rb.phase === ra.phase, 'B: the charger is dead there too, same phase (' + rb.phase + ')');
  ok(JSON.stringify(rb.pend) === JSON.stringify(ra.pend), 'B: nothing left waiting that A dropped (A ' + JSON.stringify(ra.pend) + ' · B ' + JSON.stringify(rb.pend) + ')');
  ok(rb.fights === ra.fights, `B: the same fights still to come (A ${ra.fights} · B ${rb.fights})`);
  ok(!errs.length, 'no page errors' + (errs.length ? ': ' + errs.slice(0, 2).join(' | ') : ''));
  console.log(pass + ' passed, ' + fail + ' failed');
  await b.close(); process.exit(fail ? 1 : 0);
})().catch(e => { console.error('THREW', e); process.exit(1); });
