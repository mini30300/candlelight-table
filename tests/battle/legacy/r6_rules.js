// Round 6 rules: blast, void shields (and their return), half damage, glory heal, titanic, the veil aura, the secret hero
// (free, one per player), 99 of a kind, the army cap, a fight to the death, the rounds of an objectives game, skins.
//   node r6_rules.js [page]
const { chromium } = require('playwright');
const F = 'file://' + (process.argv[2] || process.env.PAGE || require('path').resolve(__dirname, '../../../app/src/main/assets/battle-table.html'));
let pass = 0, fail = 0; const ok = (c, m, x) => { c ? pass++ : fail++; console.log((c ? 'ok   ' : 'FAIL ') + m + (x !== undefined ? '  ' + JSON.stringify(x) : '')); };
(async () => {
  const b = await chromium.launch({ executablePath: process.env.CHROMIUM_PATH || undefined, args: ['--no-sandbox'] });
  const p = await b.newPage({ viewport: { width: 1200, height: 760 } });
  const errs = []; p.on('pageerror', e => errs.push(String(e.stack || e).slice(0, 500)));
  await p.goto(F); await p.waitForFunction('window.BT && window.BT.G');
  await p.evaluate(() => {
    window.T = {
      L(arr){ const l = new Array(BT.TYPES.length).fill(0); arr.forEach(([k, n]) => { l[BT.TYPES.findIndex(t => t.k === k)] = n; }); return l; },
      setup(A, B, o){ o = o || {}; BT.clock(false); BT.quit(); BT.setTerrain('flat'); BT.setBuildings(false); BT.size(80);
        BT.G.mode = 'pvp'; BT.G.teams = 2; BT.G.perTeam = 1; BT.G.freeFire = false; BT.G.clock = 0; BT.G.budget = 40000;
        BT.G.goal = o.goal || 'obj'; BT.G.rounds = o.rounds || 5; BT.mkPlayers();
        BT.setList(0, T.L(A)); BT.setList(1, T.L(B)); BT.players()[0].dep = [-30, 0]; BT.players()[1].dep = [30, 0];
        if (o.skin) BT.players()[0].skin = o.skin;
        BT.setAuto(true); BT.start(); BT.dice([]); },
      sq(pl, k, i){ return BT.squads().filter(s => s.pl === pl && s.k === k)[i || 0]; },
      hp(s){ return BT.sqModels(s).reduce((n, m) => n + m.hp, 0); },
      settle(){ for (let i = 0; i < 900 && (BT.walking() || BT.tray().q || (BT.tray().cur && !BT.tray().cur.settled) || BT.pend().length); i++){ BT.flush(true); BT.tick(1/30, 3); } },
      near(a, b, gap){ const m = BT.sqModels(b)[0]; BT.place(a.id, m.x - gap, m.z, Math.PI/2); },
      hitAll(a, b, n, how){ const six = new Array(n || 60).fill(6), one = new Array(n || 60).fill(1);
        BT.shootAt(a.id, b.id, { hit:six, wound:six, save:one }, how); T.settle(); }
    };
  });
  const E = (f, a) => p.evaluate(f, a);

  console.log('# blast');
  let r = await E(() => { T.setup([['kgpaladin', 1], ['heavy', 1]], [['gaunt', 1], ['heavy', 1]]);
    const pal = T.sq(0, 'kgpaladin'), g = T.sq(1, 'gaunt'), h = T.sq(1, 'heavy'); T.near(pal, g, 20);
    const vg = BT.atkMath(pal.id, g.id, 'shoot'), vh = BT.atkMath(pal.id, h.id, 'shoot');
    return { gaunts: BT.sqModels(g).length, vsGaunts: vg && vg.shots, vsHeavy: vh && vh.shots, a: BT.TYPES.find(t => t.k === 'kgpaladin').gun.a }; });
  ok(r.vsGaunts === r.a + Math.floor(r.gaunts / 5) && r.vsHeavy === r.a, 'a blast weapon fires one more shot per 5 models in the target', r);

  console.log('# void shields');
  r = await E(() => { T.setup([['heavy', 3]], [['ktwarhound', 1]]); const h = T.sq(0, 'heavy'), t = T.sq(1, 'ktwarhound');
    T.near(h, t, 12); const w0 = T.hp(t), vs0 = t.vs; T.hitAll(h, t, 60, 'shoot');
    return { vs0, vs1: t.vs, w0, w1: T.hp(t), fx: BT.fx().includes('vshield') || true, log: BT.log().slice(-6).map(l => l.t.replace(/<[^>]+>/g, '')).join(' | ') }; });
  const T0 = await E(() => BT.TYPES.find(t => t.k === 'ktwarhound')), d0 = await E(() => BT.TYPES.find(t => t.k === 'heavy').gun.d);
  ok(r.vs0 === T0.vsh && r.vs1 === 0, `a titan starts with its ${T0.vsh} void shields and a volley strips them`, r);
  ok(r.w0 - r.w1 > 0 && r.w0 - r.w1 <= (6 - T0.vsh) * d0 * 3, 'the shields swallowed whole hits: less damage got through than the failed saves carried', { lost: r.w0 - r.w1 });
  r = await E(() => { const t = T.sq(1, 'ktwarhound'); for (let k = 0; k < 4 && BT.G.turn !== 1; k++){ BT.endTurn(); BT.flush(true); T.settle(); }
    return { turn: BT.G.turn, vs: t.vs, log: BT.log().slice(-8).map(l => l.t.replace(/<[^>]+>/g, '')).filter(t => /โล่พลังงาน/.test(t)) }; });
  ok(r.turn === 1 && r.vs === T0.vsh && r.log.length, 'at its side\'s command phase the shields come back', r);

  console.log('# Doom: half damage, glory, one per player, free');
  r = await E(() => { T.setup([['sniper', 1]], [['doom', 3], ['gaunt', 1]]); const s = T.sq(0, 'sniper'), d = T.sq(1, 'doom');
    const n = BT.squads().filter(q => q.k === 'doom').length; T.near(s, d, 20); const w0 = T.hp(d); T.hitAll(s, d, 1, 'shoot');
    return { n, w0, w1: T.hp(d), dd: BT.TYPES.find(t => t.k === 'sniper').gun.d, pts: BT.teamPts(1), gauntPts: BT.TYPES.find(t => t.k === 'gaunt').pts }; });
  ok(r.n === 1, 'three in a list make one: the secret hero comes once per player', r.n);
  ok(r.w0 - r.w1 === Math.ceil(r.dd / 2), `a hit of ${r.dd} damage costs him ${Math.ceil(r.dd / 2)}`, r);
  ok(r.pts === r.gauntPts, 'he is free: the side\'s points are only its other units', { pts: r.pts, gaunts: r.gauntPts });
  r = await E(() => { T.setup([['gaunt', 1]], [['doom', 1]]); const g = T.sq(0, 'gaunt'), d = T.sq(1, 'doom'); const m = BT.sqModels(d)[0];
    m.hp = 40; T.near(d, g, 1.5); const k0 = BT.sqModels(g).length; T.hitAll(d, g, 20, 'fight');
    return { before: 40, after: m.hp, killed: k0 - BT.sqModels(g).length, W: BT.TYPES.find(t => t.k === 'doom').w }; });
  ok(r.killed > 0 && r.after === Math.min(r.W, 40 + r.killed), 'glory: each model he kills in melee heals him one wound', r);

  console.log('# titanic');
  r = await E(() => { T.setup([['ktwarlord', 1], ['heavy', 1]], [['gaunt', 2]]); const t = T.sq(0, 'ktwarlord'), h = T.sq(0, 'heavy'), g = T.sq(1, 'gaunt'), g2 = T.sq(1, 'gaunt', 1);
    BT.setPhase('shoot'); T.near(g, t, 0.2); T.near(g2, h, 0.2);
    const eT = BT.engaged(t.id), eH = BT.engaged(h.id), wT = BT.why('shoot', t.id, g.id), wH = BT.why('shoot', h.id, g2.id);
    BT.fell(t.id, true); const fT = BT.why('shoot', t.id, g.id); BT.fell(h.id, true); const fH = BT.why('shoot', h.id, g2.id);
    const mt = BT.sqModels(t)[0]; BT.place(g.id, mt.x + 14, mt.z); BT.place(g2.id, mt.x + 14, mt.z + 30); BT.setPhase('charge');
    const eT2 = BT.engaged(t.id), cT = BT.why('chg', t.id, g.id); BT.fell(h.id, true); BT.place(h.id, mt.x - 10, mt.z + 30); const hm = BT.sqModels(h)[0];
    BT.place(g2.id, hm.x + 5, hm.z); const cH = BT.why('chg', h.id, g2.id);
    return { eT, eH, wT, wH: !!wH, fT, fH: !!fH, eT2, cT, cH }; });
  ok(r.eT && r.wT === '' && r.eH && r.wH, 'a titan in melee still shoots; a common squad in melee cannot', r);
  ok(r.fT === '' && r.fH, 'a titan that fell back still shoots; a common squad cannot', r);
  ok(!r.eT2 && r.cT === '' && /ถอย/.test(r.cH || ''), 'and a titan that fell back may still charge; a common squad cannot', { cT: r.cT, cH: r.cH });

  console.log('# the veil');
  r = await E(() => { T.setup([['heavy', 1]], [['swvenom', 1], ['gaunt', 2]]); const h = T.sq(0, 'heavy'), v = T.sq(1, 'swvenom'), g = T.sq(1, 'gaunt'), far = T.sq(1, 'gaunt', 1);
    const mv = BT.sqModels(v)[0]; BT.place(g.id, mv.x - 3, mv.z); BT.place(far.id, mv.x + 0, mv.z + 20); BT.place(h.id, mv.x - 20, mv.z + 8, Math.PI/2);
    const a = BT.atkMath(h.id, g.id, 'shoot'), c = BT.atkMath(h.id, far.id, 'shoot');
    return { near: BT.inAura(g.id, 'veil'), far: BT.inAura(far.id, 'veil'), modNear: a && a.mod, modFar: c && c.mod }; });
  ok(r.near && !r.far && r.modNear === r.modFar - 1, 'friendly squads within 6" of the venom beast are harder to hit (-1)', r);

  console.log('# 99 of a kind, the army cap');
  r = await E(() => { T.setup([['gaunt', 150]], [['heavy', 1]]); const cap = BT.armyCap();
    const four = (() => { BT.quit(); BT.G.mode = 'ffa'; BT.G.teams = 4; BT.mkPlayers(); return BT.armyCap(); })();
    const eight = (() => { BT.quit(); BT.G.teams = 8; BT.mkPlayers(); return BT.armyCap(); })();
    return { cap, four, eight }; });
  const listed = await E(() => { BT.quit(); BT.G.mode = 'pvp'; BT.G.teams = 2; BT.mkPlayers(); BT.setList(0, T.L([['gaunt', 150]])); return BT.players()[0].list[BT.TYPES.findIndex(t => t.k === 'gaunt')]; });
  ok(listed === 99, 'a list holds at most 99 of a kind', listed);
  ok(r.cap === 250 && r.four === 125 && r.eight === 62, 'the model cap: 250 each for two players, 125 for four, 62 for eight', r);

  console.log('# a fight to the death / the rounds of an objectives game');
  r = await E(() => { T.setup([['heavy', 1]], [['heavy', 1]], { goal: 'kill' });
    for (let k = 0; k < 14; k++){ BT.endTurn(); BT.flush(true); T.settle(); }
    return { over: BT.G.over, round: BT.G.round, obj: BT.obj().length, vp: BT.vp() }; });
  ok(!r.over && r.round >= 7 && r.obj === 0, 'a fight to the death is not over after round 5 and has no objectives', r);
  r = await E(() => { T.setup([['heavy', 1]], [['heavy', 1]], { goal: 'obj', rounds: 3 });
    const seen = []; for (let k = 0; k < 10 && !BT.G.over; k++){ BT.endTurn(); BT.flush(true); T.settle(); seen.push(BT.G.round); }
    return { over: BT.G.over, round: BT.G.round, seen, obj: BT.obj().length, last: BT.log().slice(-1)[0].t.replace(/<[^>]+>/g, '') }; });
  ok(r.over && r.obj === 5 && Math.max(...r.seen) <= 4, 'an objectives game set to 3 rounds ends after round 3', r);

  console.log('# skins');
  r = await E(() => { T.setup([['loki', 1]], [['heavy', 1]], { skin: { loki: 1 } }); const u = BT.units.find(u => u.k === 'loki');
    return { skn: u && u.skn, kit: u && BT.kitOf(u), plain: (() => { T.setup([['loki', 1]], [['heavy', 1]]); const v = BT.units.find(u => u.k === 'loki'); return v && BT.kitOf(v); })() }; });
  ok(r.skn === 'loki_f' && r.kit === 'loki_f' && r.plain === 'loki', 'Loki wears the skin his owner picked (and the old look without one)', r);
  r = await E(() => { const R = { code: 'SKN01', ownerPid: 'p1', state: 'lobby', seats: 2, seq: 0, acts: [], setup: Object.assign(BT.curSetup(), { mode: 'pvp' }),
      players: [{ pid: 'p1', team: 0, nm: 'a', owner: true, list: T.L([['loki', 1]]), sk: { loki: 1, bogus: 3, heavy: 1 } }, { pid: 'p2', team: 1, nm: 'b', list: T.L([['heavy', 1]]), sk: { loki: 9 } }] };
    BT.adoptRoom(R); return BT.players().map(P => P.skin); });
  ok(JSON.stringify(r[0]) === JSON.stringify({ loki: 1 }) && JSON.stringify(r[1]) === '{}', 'a room\'s skins are taken only for units that have them, and only a skin that exists', r);
  ok(errs.length === 0, 'no page errors', errs.slice(0, 3));
  console.log(pass + ' passed, ' + fail + ' failed'); await b.close(); process.exit(fail ? 1 : 0);
})();
