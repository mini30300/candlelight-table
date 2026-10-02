// Round 4 rules and looks, one scenario at a time with forced dice: node r4_rules.js
const { chromium } = require('playwright');
const F = 'file://' + (process.env.PAGE || require('path').resolve(__dirname, '../../../app/src/main/assets/battle-table.html'));
let pass = 0, fail = 0; const ok = (c, m) => { c ? pass++ : fail++; console.log((c ? 'ok   ' : 'FAIL ') + m); };
(async () => {
  const b = await chromium.launch({ executablePath: process.env.CHROMIUM_PATH || undefined, args: ['--no-sandbox'] });
  const p = await b.newPage({ viewport: { width: 1200, height: 760 } });
  const errs = []; p.on('pageerror', e => errs.push(String(e.stack || e).slice(0, 500)));
  await p.goto(F); await p.waitForFunction('window.BT && window.BT.G');
  await p.evaluate(() => {
    window.T = {
      setup(A, B){ BT.clock(false); BT.quit(); BT.setTerrain('flat'); BT.setBuildings(false); BT.size(60);
        BT.G.mode = 'pvp'; BT.G.teams = 2; BT.G.perTeam = 1; BT.G.freeFire = false; BT.G.clock = 0; BT.G.budget = 2000; BT.mkPlayers();
        const L = (arr) => { const l = new Array(BT.TYPES.length).fill(0); arr.forEach(([k, n]) => { l[BT.TYPES.findIndex(t => t.k === k)] = n; }); return l; };
        BT.setList(0, L(A)); BT.setList(1, L(B)); BT.players()[0].dep = [-20, 0]; BT.players()[1].dep = [20, 0];
        BT.setAuto(true); BT.start(); BT.dice([]); },
      sq(pl, k, i){ return BT.squads().filter(s => s.pl === pl && s.k === k)[i || 0]; },
      settle(){ for (let i = 0; i < 600 && (BT.walking() || BT.tray().q || (BT.tray().cur && !BT.tray().cur.settled)); i++) BT.tick(1/30, 3); },
      alive(s){ return BT.sqModels(s).length; }
    };
  });
  const E = (f, a) => p.evaluate(f, a);

  // 1. eleven armies: world legends split up, Thor pricier, Odin the most expensive unit of all
  let r = await E(() => { const f = {}; BT.TYPES.forEach(t => f[t.k] = t.fac);
    return { n: BT.TYPES.length, facs: [...new Set(BT.TYPES.map(t => t.fac))].join(','),
      moved: ['samurai', 'ninja', 'viking', 'thunder', 'mummy', 'dragon'].map(k => f[k]).join(','),
      thor: BT.TYPES.find(t => t.k === 'thunder'), odin: BT.TYPES.find(t => t.k === 'odin').pts, max: Math.max(...BT.TYPES.slice(0, 89).map(t => t.pts)) }; });   // (Round 6 added titans and a 40,000-point hero after the first 89)
  // (Round 7 added three more armies: the eleven of Round 4 must all still be there)
  ok(r.n >= 89 && ['gr','mod','kn','sw','rb','or','th','jp','nr','eg','md'].every(f => r.facs.split(',').includes(f)) && !/\blg\b/.test(r.facs) && r.moved === 'jp,jp,nr,nr,eg,md',
     `89+ units, the 11 Round 4 armies all there (${r.facs}); legends moved to ${r.moved}`);
  ok(r.thor.nm === 'ทอร์' && r.thor.pts > 120 && r.odin === r.max, `Thor is ${r.thor.pts} pts (was 120); Odin at ${r.odin} is the most expensive of the Round 4 units`);

  // 2. the Templars' blessing: friends within 6" get 5++, farther ones don't, the Templars keep their own 4++
  r = await E(() => { T.setup([['mech', 1]], [['templar', 1], ['infantry', 2]]); const a = T.sq(0, 'mech'), tp = T.sq(1, 'templar'),
      near = T.sq(1, 'infantry', 0), far = T.sq(1, 'infantry', 1);
    BT.place(a.id, -10, 0, Math.PI/2); BT.place(tp.id, 10, 0, -Math.PI/2); BT.place(near.id, 10, 4, -Math.PI/2); BT.place(far.id, 10, -18, -Math.PI/2);
    const bl = BT.blessed() || {};
    return { near: BT.atkMath(a, near).sv, far: BT.atkMath(a, far).sv, tp: BT.atkMath(a, tp).sv, ringNear: !!bl[near.id], ringFar: !!bl[far.id], ringTp: !!bl[tp.id] }; });
  ok(r.near === 5 && r.far === 7 && r.tp === 4, `blessing vs AP3: infantry near the Templars save on 5++, far ones have none (${r.far}), the Templars on 4++`);
  ok(r.ringNear && r.ringTp && !r.ringFar, 'the blessed squads get the gold ring, the far one does not');

  // 3. Anubis: fallen mummies near him stand up on 4+, the ones far away still need 5+
  r = await E(() => { T.setup([['mummy', 2], ['anubis', 1]], [['heavy', 1]]); const m1 = T.sq(0, 'mummy', 0), m2 = T.sq(0, 'mummy', 1),
      an = T.sq(0, 'anubis'), e = T.sq(1, 'heavy');
    BT.place(m1.id, -8, 0, Math.PI/2); BT.place(an.id, -12, 2, Math.PI/2); BT.place(m2.id, -8, -20, Math.PI/2); BT.place(e.id, 6, 0, -Math.PI/2);
    [m1, m2].forEach(m => { const c = BT.sqModels(m)[0]; BT.place(e.id, c.x + 8, c.z, -Math.PI/2);
      BT.shootAt(e, m, { hit:[6,6,6,6,6,6], wound:[6,6,6,6,6,6], save:[1,1,1,1,1,1] }); T.settle(); });
    BT.place(e.id, 20, 10); const lost = [T.alive(m1), T.alive(m2)];
    BT.dice([]); BT.endTurn(); BT.flush(true); T.settle();
    // both squads are below half: their two battle-shock tests (2D6 each) are rolled first, then the two reanimations (3 dice each)
    BT.dice([4,4, 4,4, 4,4,4, 4,4,4]); BT.endTurn();
    const P = BT.pend().filter(q => q.kind === 'rez'); const need = id => (P.find(q => q.u === id) || {}).need;
    const res = { lost, near: need(m1.id), far: need(m2.id) }; BT.flush(true); T.settle(); res.after = [T.alive(m1), T.alive(m2)]; return res; });
  ok(r.near === 4 && r.far === 5 && r.after[0] > r.lost[0] && r.after[1] === r.lost[1],
     `Anubis: the near mummies reanimate on 4+ (rolled 4s: ${r.lost[0]} → ${r.after[0]}), the far ones need 5+ (${r.lost[1]} → ${r.after[1]})`);

  // 4. a squad mixes looks: samurai with and without the back banner, knights with different weapons
  r = await E(() => { T.setup([['samurai', 1], ['maa', 1], ['pike', 1], ['levy', 1]], [['infantry', 1]]);
    const kits = k => BT.sqModels(T.sq(0, k)).map(m => BT.kitOf(m)).join(',');
    return { samurai: kits('samurai'), maa: kits('maa'), pike: kits('pike'), levy: kits('levy') }; });
  ok(r.samurai === 'samurai,samurai_nb,samurai,samurai_nb,samurai', `samurai banners: ${r.samurai}`);
  ok(new Set(r.maa.split(',')).size === 5 && new Set(r.pike.split(',')).size === 3 && new Set(r.levy.split(',')).size === 3,
     `every man-at-arms carries his own weapon: ${r.maa} · pikes: ${r.pike} · levy: ${r.levy}`);

  // 5. what flies: crossbow bolts (no muzzle flash), the ballista's giant bolt, the catapult's stone, Odin's spear, the giant's ice
  const shotKinds = async (att, def, dice) => E(([att, def, dice]) => { T.setup([[att, 1]], [[def, 1]]); const a = T.sq(0, att), e = T.sq(1, def);
    BT.place(a.id, -8, 0, Math.PI/2); BT.place(e.id, 8, 0, -Math.PI/2); BT.shootAt(a, e, dice); const seen = new Set();
    for (let i = 0; i < 160; i++){ BT.tick(1/30, 1); BT.fx().forEach(k => seen.add(k)); } T.settle(); return [...seen].sort().join(','); }, [att, def, dice]);
  const xb = await shotKinds('xbow', 'infantry', { hit:[6,6,6,6,6], wound:[1,1,1,1,1], save:[] });
  ok(/\bbolt\b/.test(xb) && !/tracer|flash/.test(xb), `crossbows loose bolts, no flash or tracer (${xb})`);
  const bal = await shotKinds('ballista', 'heavy', { hit:[6], wound:[1], save:[] });
  ok(/bigbolt/.test(bal) && !/tracer/.test(bal), `the ballista looses a giant bolt (${bal})`);
  const cat = await shotKinds('catapult', 'heavy', { hit:[6,6], wound:[1,1], save:[] });
  ok(/boulder/.test(cat) && /boom/.test(cat), `the catapult's stone arcs over and lands with a crash (${cat})`);
  const od = await shotKinds('odin', 'heavy', { hit:[], wound:[1,1], save:[] });
  ok(/gungnir/.test(od), `Odin throws Gungnir (${od})`);
  const ice = await shotKinds('frostg', 'heavy', { hit:[6,6], wound:[1,1], save:[] });
  ok(/\bice\b/.test(ice), `frost giants hurl ice (${ice})`);
  r = await E(() => { T.setup([['odin', 1]], [['heavy', 1]]); return BT.atkMath(T.sq(0, 'odin'), T.sq(1, 'heavy')); });
  ok(r.tr && r.need === 0, 'Gungnir never misses: automatic hits');

  // 6. bots play the four new armies to the end
  r = await E(() => { const res = [];
    for (const [A, B, seed] of [['jp', 'md', 5], ['nr', 'eg', 7], ['md', 'nr', 9], ['eg', 'jp', 13]]){
      BT.clock(false); BT.quit(); BT.seed(seed); BT.setTerrain('flat'); BT.setBuildings(false); BT.size(60);
      BT.G.mode = 'pvp'; BT.G.teams = 2; BT.G.perTeam = 1; BT.G.budget = 1000; BT.mkPlayers();
      const L = f => { const l = new Array(BT.TYPES.length).fill(0); BT.TYPES.forEach((t, j) => { if (t.fac === f) l[j] = 1; }); return l; };
      BT.setList(0, L(A)); BT.setList(1, L(B)); BT.players()[0].dep = [-20, 0]; BT.players()[1].dep = [20, 0]; BT.players().forEach(P => P.bot = true);
      BT.start(); let g = 0; while (!BT.G.over && g++ < 6000){ BT.botStep(); BT.tick(1/30, 2); }
      res.push({ over: BT.G.over, round: BT.G.round, m: A + '/' + B }); }
    return res; });
  ok(r.every(x => x.over), 'bot games with the new armies finish: ' + r.map(x => x.m + ' r' + x.round + (x.over ? '' : ' (stuck)')).join(' · '));

  ok(!errs.length, 'no page errors' + (errs.length ? ': ' + errs.slice(0, 3).join(' | ') : ''));
  console.log(`\n${pass} passed, ${fail} failed`);
  await b.close(); process.exit(fail ? 1 : 0);
})();
