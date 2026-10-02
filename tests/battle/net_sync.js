// Round 8: two devices, one game, with the new army of fallen knights and daemons (its dark pact: melee 6s hit twice),
// the knights' chapter units and the blue-skinned empire's hidden mech in play. Page A plays a whole bot game and records
// every act it sends; page B only applies those acts. After every batch the two boards must be identical.
//   PAGE=<page> node r8_net.js <scenario 1..3>
const { chromium } = require('playwright');
const F = 'file://' + (process.env.PAGE || require('path').resolve(__dirname, '../../app/src/main/assets/battle-table.html'));
let pass = 0, fail = 0; const ok = (c, m) => { c ? pass++ : fail++; console.log((c ? 'ok   ' : 'FAIL ') + m); };
const SC = {
  1: { goal: 'kill', teams: 2, seed: 71, lists: [
        [['cxw', 2], ['cxb', 1], ['cxr', 1], ['cxh', 1], ['cxc', 1], ['cxl', 1], ['cxs', 1], ['cxt', 1], ['cxd', 1], ['dmr', 1], ['dmh', 1], ['dmg', 1]],
        [['kna1', 1], ['kna2', 1], ['knb1', 1], ['knb2', 1], ['knc1', 1], ['knc2', 1], ['knd1', 1], ['knd2', 1], ['kne1', 1], ['kne2', 1]] ] },
  2: { goal: 'obj', rounds: 4, teams: 2, seed: 83, lists: [
        [['cxp', 1], ['dmp', 1], ['dmf', 1], ['dmc', 1], ['dmx', 1], ['cxc', 2], ['cxw', 1]],
        [['tagm', 1], ['tafw', 2], ['tapath', 1], ['tacrisis', 1], ['tadrone', 1]] ] },
  3: { goal: 'kill', teams: 4, seed: 97, lists: [
        [['cxw', 1], ['dmr', 1], ['dmc', 1]], [['kne2', 1], ['knd1', 1], ['kna2', 1]],
        [['tagm', 1], ['tafw', 1]], [['dewar', 1], ['dewych', 1], ['desucc', 1]] ] },
};
(async () => {
  const sc = SC[+(process.argv[2] || 1)];
  const b = await chromium.launch({ executablePath: process.env.CHROMIUM_PATH || undefined, args: ['--no-sandbox'] });
  const A = await b.newPage({ viewport: { width: 900, height: 700 } }), B = await b.newPage({ viewport: { width: 900, height: 700 } });
  const errs = []; [A, B].forEach((p, i) => p.on('pageerror', e => errs.push((i ? 'B: ' : 'A: ') + String(e.stack || e).slice(0, 400))));
  for (const p of [A, B]) { await p.goto(F); await p.waitForFunction('window.BT && window.BT.G'); }
  for (const p of [A, B]) await p.evaluate((sc) => { BT.clock(false); BT.quit(); BT.setTerrain('hills'); BT.seed(sc.seed); BT.size(90);
    BT.G.mode = sc.teams > 2 ? 'ffa' : 'pvp'; BT.G.teams = sc.teams; BT.G.perTeam = 1; BT.G.budget = 40000; BT.G.goal = sc.goal; BT.G.rounds = sc.rounds || 5;
    BT.mkPlayers(); BT.players().forEach(P => P.bot = true);
    const L = (arr) => { const l = new Array(BT.TYPES.length).fill(0); arr.forEach(([k, n]) => { l[BT.TYPES.findIndex(t => t.k === k)] = n; }); return l; };
    sc.lists.forEach((a, i) => BT.setList(i, L(a)));
    const R = sc.teams > 2 ? 30 : 34; BT.players().forEach((P, i) => { const a = i / sc.teams * Math.PI * 2; P.dep = [Math.round(Math.cos(a) * R), Math.round(Math.sin(a) * R * 0.6)]; });
    if (sc.skin) BT.players()[0].skin = sc.skin;
    BT.setAuto(true); BT.start(); }, sc);
  const armies = await A.evaluate(() => BT.players().map(p => BT.TYPES.filter((T, i) => p.list[i]).map(T => T.k + (p.list[BT.TYPES.indexOf(T)] > 1 ? '×' + p.list[BT.TYPES.indexOf(T)] : '')).join('+')));
  console.log('armies', armies.join(' | '), '· goal', sc.goal, sc.rounds || '');
  await B.evaluate(() => { BT.NET.on = true; BT.NET.owner = false; BT.NET.pid = 'B'; BT.NET.code = 'TEST'; });
  await A.evaluate(() => { BT.NET.on = true; BT.NET.owner = true; BT.NET.pid = 'A'; BT.NET.code = 'TEST'; BT.setServer('http://127.0.0.1:9'); BT.capture(true); });
  const norm = (bd) => JSON.stringify({ ...bd, units: bd.units.slice().sort((x, y) => x.id < y.id ? -1 : 1) });
  ok(norm(await A.evaluate(() => BT.board())) === norm(await B.evaluate(() => BT.board())), 'both devices deploy the same armies on the same field');
  const skins = p => p.evaluate(() => BT.units.filter(u => u.skn).map(u => u.id + ':' + u.skn).join(','));
  const sA = await skins(A), sB = await skins(B);
  ok(sA === sB && (!sc.skin || sA.length > 0), 'the same skins on both devices (' + (sA || 'none') + ')');
  let acts = 0, diffs = 0, firstDiff = null, i; const seen = {};
  for (i = 0; i < 6000; i++) {
    const st = await A.evaluate(() => { BT.tick(1/30, 15); return { over: BT.G.over, sent: BT.capture(true) }; });
    if (st.sent.length) { acts += st.sent.length; st.sent.forEach(a => { seen[a.a] = (seen[a.a] || 0) + 1; });
      await B.evaluate((list) => { list.forEach(a => { a.pid = 'A'; BT.applyAct(a); }); }, st.sent);
      await B.evaluate(() => BT.tick(1/30, 1));
      const [ba, bb] = [await A.evaluate(() => BT.board()), await B.evaluate(() => BT.board())];
      if (norm(ba) !== norm(bb)) { diffs++; if (!firstDiff) firstDiff = { at: i, a: ba, b: bb, sent: st.sent }; } }
    if (st.over || errs.length) break;
  }
  const endOf = p => p.evaluate(() => ({ over: BT.G.over, round: BT.G.round, vp: BT.vp(), log: BT.log().slice(-1)[0].t.replace(/<[^>]+>/g, ''),
    shields: BT.log().filter(l => /โล่พลังงาน/.test(l.t)).length, glory: BT.log().filter(l => /ฟื้น/.test(l.t)).length,
    vs: BT.squads().filter(s => s.vs != null).map(s => s.id + ':' + s.vs).join(',') }));
  const endA = await endOf(A), endB = await endOf(B);
  console.log('acts', acts, 'steps', i, 'round', endA.round, '· A:', endA.log); console.log('act kinds', JSON.stringify(seen)); console.log('                 B:', endB.log);
  console.log('void-shield lines', endA.shields, '/', endB.shields, '· heal lines', endA.glory, '/', endB.glory);
  if (firstDiff) {
    const a = firstDiff.a, bb = firstDiff.b; console.log('first difference at step', firstDiff.at, 'after', JSON.stringify(firstDiff.sent).slice(0, 300));
    ['turn','round','phase','over'].forEach(k => { if (a[k] !== bb[k]) console.log('  ', k, a[k], bb[k]); });
    const ua = Object.fromEntries(a.units.map(u => [u.id, u])), ub = Object.fromEntries(bb.units.map(u => [u.id, u]));
    Object.keys({ ...ua, ...ub }).forEach(id => { const x = JSON.stringify(ua[id]), y = JSON.stringify(ub[id]); if (x !== y) console.log('   unit', id, x, y); });
  }
  ok(endA.over && endB.over, 'the game ends on both devices');
  if (sc.goal === 'obj') ok(endA.round <= (sc.rounds || 5), `an objectives game of ${sc.rounds} rounds ends by round ${sc.rounds} (${endA.round})`);
  ok(diffs === 0, `after each of the ${acts} acts both boards match (${diffs} mismatching checks)`);
  ok(JSON.stringify(endA.vp) === JSON.stringify(endB.vp) && endA.log === endB.log && endA.shields === endB.shields && endA.glory === endB.glory && endA.vs === endB.vs,
     'same score, same result on both');
  ok(errs.length === 0, 'no page errors' + (errs.length ? ': ' + errs.slice(0, 2).join(' | ') : ''));
  console.log(pass + ' passed, ' + fail + ' failed');
  await b.close(); process.exit(fail ? 1 : 0);
})().catch(e => { console.error('THREW', e); process.exit(1); });
