// Round 2 rules, one scenario at a time with forced dice: node r2_rules.js
const { chromium } = require('playwright');
const F = 'file://' + (process.env.PAGE || require('path').resolve(__dirname, '../../../app/src/main/assets/battle-table.html'));
let pass = 0, fail = 0; const ok = (c, m) => { c ? pass++ : fail++; console.log((c ? 'ok   ' : 'FAIL ') + m); };
(async () => {
  const b = await chromium.launch({ executablePath: process.env.CHROMIUM_PATH || undefined, args: ['--no-sandbox'] });
  const p = await b.newPage({ viewport: { width: 1200, height: 760 } });
  const errs = []; p.on('pageerror', e => errs.push(String(e.stack || e).slice(0, 500)));
  await p.goto(F); await p.waitForFunction('window.BT && window.BT.G');
  // helpers live in the page
  await p.evaluate(() => {
    window.T = {
      setup(A, B){ BT.clock(false); BT.quit(); BT.setTerrain('flat'); BT.setBuildings(false); BT.size(60);
        BT.G.mode = 'pvp'; BT.G.teams = 2; BT.G.perTeam = 1; BT.G.freeFire = false; BT.G.clock = 0; BT.mkPlayers();
        const L = (arr) => { const l = new Array(BT.TYPES.length).fill(0); arr.forEach(([k, n]) => { l[BT.TYPES.findIndex(t => t.k === k)] = n; }); return l; };
        BT.setList(0, L(A)); BT.setList(1, L(B)); BT.players()[0].dep = [-20, 0]; BT.players()[1].dep = [20, 0];
        BT.setAuto(true); BT.start(); BT.dice([]); },
      sq(pl, k, i){ return BT.squads().filter(s => s.pl === pl && s.k === k)[i || 0]; },
      settle(){ for (let i = 0; i < 400 && (BT.walking() || BT.tray().q || (BT.tray().cur && !BT.tray().cur.settled)); i++) BT.tick(1/30, 3); },
      hp(s){ return BT.sqModels(s).map(m => m.hp); },
      edge(a, b){ let best = 1e9; BT.sqModels(a).forEach(m => BT.sqModels(b).forEach(q => { best = Math.min(best, Math.hypot(m.x - q.x, m.z - q.z) - 0.8 - 0.8); })); return best; }
    };
  });
  const E = (f, a) => p.evaluate(f, a);

  // 1. wound table: S vs T
  const W = await E(() => [[4,4],[8,4],[5,4],[3,4],[2,4],[4,8],[9,10],[5,10],[12,10],[3,3]].map(([S, T]) => BT.woundNeed(S, T)));
  ok(JSON.stringify(W) === JSON.stringify([4,2,3,5,6,6,5,6,3,4]), 'wound roll from strength against toughness ' + W.join(','));

  // 2. squads deploy whole, every model of a squad shares it
  let r = await E(() => { T.setup([['infantry', 2], ['heavy', 1]], [['hoplite', 1]]);
    const sq = BT.squads(); return { squads: sq.length, models: BT.units.length, phase: BT.phase(),
      ok: sq.every(s => BT.sqModels(s).every(m => m.sq === s.id && m.hp === BT.TYPES.find(t => t.k === s.k).w)),
      sizes: sq.map(s => s.k + ':' + BT.sqModels(s).length).join(' ') }; });
  ok(r.squads === 4 && r.models === 18 && r.ok, 'lists deploy as squads (' + r.sizes + ')');
  ok(r.phase === 'move', 'first turn opens in the movement phase after command (' + r.phase + ')');

  // 3. a squad moves in formation, every model within its move, no two bases overlapping
  r = await E(() => { T.setup([['infantry', 1]], [['infantry', 1]]); const a = T.sq(0, 'infantry'), e = T.sq(1, 'infantry');
    BT.place(a.id, -10, 0, Math.PI/2); BT.place(e.id, 20, 0, -Math.PI/2);
    const from = BT.sqModels(a).map(m => [m.x, m.z]); BT.select(a); BT.act('move'); const moved = BT.tap(-4.5, 0); T.settle();
    const to = BT.sqModels(a).map(m => [m.x, m.z]), far = Math.max(...to.map((q, i) => Math.hypot(q[0] - from[i][0], q[1] - from[i][1])));
    let minGap = 1e9; for (let i = 0; i < to.length; i++) for (let j = i + 1; j < to.length; j++) minGap = Math.min(minGap, Math.hypot(to[i][0] - to[j][0], to[i][1] - to[j][1]));
    return { moved, far, minGap, flag: a.moved }; });
  ok(r.moved && r.flag && r.far <= 6.01 && r.minGap >= 1.59, `squad moves in formation: farthest ${r.far.toFixed(2)}" of 6", closest bases ${r.minGap.toFixed(2)}"`);

  // 4. a normal move can't end in engagement range
  r = await E(() => { T.setup([['infantry', 1]], [['infantry', 1]]); const a = T.sq(0, 'infantry'), e = T.sq(1, 'infantry');
    BT.place(a.id, -6, 0, Math.PI/2); BT.place(e.id, 1.5, 0, -Math.PI/2); BT.select(a); BT.act('move'); BT.tap(-0.5, 0); T.settle();
    return { edge: T.edge(a, e), eng: BT.engaged(a) }; });
  ok(!r.eng && r.edge > 1, `moving toward an enemy stops outside 1" (edge ${r.edge.toFixed(2)}")`);

  // 5. advance: +D6 to the move, then no shooting unless the weapon allows it
  r = await E(() => { T.setup([['infantry', 1], ['enemy', 1]], [['heavy', 1]]); const a = T.sq(0, 'infantry'), j = T.sq(0, 'enemy'), e = T.sq(1, 'heavy');
    BT.place(a.id, -16, -4, Math.PI/2); BT.place(j.id, -16, 6, Math.PI/2); BT.place(e.id, -2, 0, -Math.PI/2);
    BT.dice([4]); BT.select(a); document.querySelector('#btAct [data-a="adv"]').click();
    const adv = a.adv && a.advR === 4; BT.act('move'); BT.tap(-6.8, -4); T.settle();
    BT.dice([2]); BT.select(j); document.querySelector('#btAct [data-a="adv"]').click(); BT.act('move'); BT.tap(-8, 6); T.settle();
    BT.nextPhase();
    const c = BT.sqModels(a)[0];
    return { adv, far: c ? Math.hypot(c.x + 16, c.z + 4) : 0, phase: BT.phase(), why: BT.board && document ? '' : '',
      inf: window.BT.sq(a.id) && (function(){ return BT.atkMath(a, e) && ''; })(), whyInf: BT.aim(a, e, 'atk'), whyAs: BT.aim(j, e, 'atk') }; });
  ok(r.adv, 'advance adds the D6 to the move (rolled 4 → 10")');
  ok(r.far > 6.2, `an advancing squad goes past its 6" (${r.far.toFixed(1)}")`);
  ok(r.phase === 'shoot' && r.whyInf === false && r.whyAs === true, 'after advancing only the assault weapon may shoot');

  // 6. rapid fire at half range, heavy +1 when stationary
  r = await E(() => { T.setup([['infantry', 1], ['archer', 1]], [['heavy', 1]]); const a = T.sq(0, 'infantry'), ar = T.sq(0, 'archer'), e = T.sq(1, 'heavy');
    BT.place(e.id, 6, 0); BT.place(a.id, -4, 0, Math.PI/2); BT.place(ar.id, -12, 8, Math.PI/2);
    const near = BT.atkMath(a, e).shots; BT.place(a.id, -12, -6, Math.PI/2); const farS = BT.atkMath(a, e).shots;
    const still = BT.atkMath(ar, e).need; ar.still = false; const movedN = BT.atkMath(ar, e).need;
    return { near, farS, still, movedN }; });
  ok(r.near === 10 && r.farS === 5, `rapid fire: 10 shots inside half range, 5 beyond (${r.near}, ${r.farS})`);
  ok(r.still === 3 && r.movedN === 4, `heavy: archers hit on 3+ standing still, 4+ after moving (${r.still}, ${r.movedN})`);

  // 7. damage goes to the wounded model first; one model at a time
  r = await E(() => { T.setup([['infantry', 1]], [['heavy', 1]]); const a = T.sq(0, 'infantry'), e = T.sq(1, 'heavy');
    BT.place(a.id, -12, 0, Math.PI/2); BT.place(e.id, 8, 0, -Math.PI/2);
    const M = BT.atkMath(a, e); BT.shootAt(a, e, { hit:[6,6,6,1,1], wound:[6,6,6], save:[1,1,1] }); T.settle();
    return { shots: M.shots, wneed: M.wneed, sv: M.sv, hp: T.hp(e).sort().join(',') }; });
  ok(r.shots === 5 && r.wneed === 5 && r.sv === 3, `infantry vs heavy: 5 shots, wound 5+, save 3+ (${r.shots}, ${r.wneed}, ${r.sv})`);
  ok(r.hp === '1,2', 'three wounds on 2-wound models: one falls, the next is hurt (left ' + r.hp + ')');

  // 8. excess damage from one wound is lost
  r = await E(() => { T.setup([['sniper', 1]], [['heavy', 1]]); const a = T.sq(0, 'sniper'), e = T.sq(1, 'heavy');
    BT.place(a.id, -15, 0, Math.PI/2); BT.place(e.id, 12, 0, -Math.PI/2);
    const M = BT.atkMath(a, e); BT.shootAt(a, e, { hit:[6], wound:[6], save:[1] }); T.settle();
    return { d: M.dmg, sv: M.sv, left: BT.sqModels(e).length, hp: T.hp(e).join(',') }; });
  ok(r.d === 3 && r.sv === 5 && r.left === 2 && r.hp === '2,2', `a 3-damage shot kills one 2-wound model, the rest is lost (left ${r.left}: ${r.hp})`);

  // 9. invulnerable save ignores AP
  r = await E(() => { T.setup([['mech', 1]], [['spartan', 1]]); const a = T.sq(0, 'mech'), e = T.sq(1, 'spartan');
    BT.place(a.id, -12, 0, Math.PI/2); BT.place(e.id, 10, 0); return BT.atkMath(a, e); });
  ok(r.sv === 5 && r.wneed === 2, `mech cannon vs Spartans: S9 vs T4 wounds on 2+, save 5++ not 6+ (${r.wneed}, ${r.sv})`);

  // 10. charge: roll 2D6, run in, chargers fight first
  r = await E(() => { T.setup([['hoplite', 1]], [['infantry', 2]]); const a = T.sq(0, 'hoplite'), e = T.sq(1, 'infantry'), e2 = T.sq(1, 'infantry', 1);
    BT.place(a.id, -6, 0, Math.PI/2); BT.place(e.id, 4, 0, -Math.PI/2); BT.place(e2.id, 25, 18); BT.cp(1, 0);
    BT.setPhase('charge'); BT.dice([6, 5]); const why = BT.charge(a, e); T.settle();
    const eng = BT.engaged(a), charged = a.charged;
    BT.nextPhase(); const pend = BT.tray().pend[0];
    return { why, eng, charged, phase: BT.phase(), first: pend && pend.u === a.id && pend.stage === 'hit', edge: T.edge(a, e) }; });
  ok(r.why === '' && r.charged && r.eng, `a charge rolled high runs into base contact (edge ${r.edge.toFixed(2)}")`);
  ok(r.phase === 'fight' && r.first, 'in the fight phase the charging squad strikes first');

  // 11. the fight resolves both ways and the turn passes
  r = await E(() => { const a = T.sq(0, 'hoplite'), e = T.sq(1, 'infantry');
    const before = BT.sqModels(e).length; BT.dice([6,6,6,6,6,6,6,6,6,6, 6,6,6,6,6,6,6,6,6,6, 1,1,1,1,1,1,1,1,1,1]);
    for (let i = 0; i < 20 && BT.phase() === 'fight' && BT.tray().pend.length; i++){ BT.roll(); T.settle(); }
    return { before, after: BT.sqModels(e).length, alive: !!BT.sq(e.id) && BT.sqModels(e).length, phase: BT.phase(), turn: BT.G.turn }; });
  ok(r.after < r.before, `hoplites cut down the infantry (${r.before} → ${r.after})`);
  ok(r.turn === 1, 'after the last fight the turn passes to the other team (team ' + r.turn + ', ' + r.phase + ')');

  // 12. a failed charge can be re-rolled for 1 CP, or accepted
  r = await E(() => { T.setup([['hoplite', 2]], [['infantry', 1]]); const a = T.sq(0, 'hoplite', 0), a2 = T.sq(0, 'hoplite', 1), e = T.sq(1, 'infantry');
    BT.place(a.id, -8, -4, Math.PI/2); BT.place(a2.id, -8, 5, Math.PI/2); BT.place(e.id, 4, 0, -Math.PI/2); BT.cp(1, 0); BT.cp(0, 3);
    BT.setPhase('charge'); BT.dice([1, 1]); BT.charge(a, e); const st1 = BT.myRoll();
    BT.roll({ yes:false }); T.settle(); const stayed = !a.charged && !BT.engaged(a), cpA = BT.cp(0);
    BT.dice([1, 1, 6, 6]); BT.charge(a2, e); const st2 = BT.myRoll(); BT.roll({ yes:true }); T.settle();
    return { st1, stayed, cpA, st2, got: a2.charged && BT.engaged(a2), cpB: BT.cp(0) }; });
  ok(r.st1 === 'chg.chrr:human' && r.stayed && r.cpA === 3, 'a failed charge offers the re-roll; declining leaves the squad where it was');
  ok(r.st2 === 'chg.chrr:human' && r.got && r.cpB === 2, 'the re-roll (1 CP) turns a failed charge into a hit');

  // 13. overwatch: the target may shoot the chargers first, hitting only on 6s
  r = await E(() => { T.setup([['hoplite', 1]], [['infantry', 1]]); const a = T.sq(0, 'hoplite'), e = T.sq(1, 'infantry');
    BT.place(a.id, -6, 0, Math.PI/2); BT.place(e.id, 4, 0, -Math.PI/2); BT.cp(1, 2);
    BT.setPhase('charge'); BT.charge(a, e); const st = BT.myRoll(); const n = BT.atkMath(e, a, 'ow').shots;
    BT.dice([6, 6].concat(new Array(n - 2).fill(1), [6, 6], [1, 1], [6, 6])); BT.roll({ yes:true }); const ow = BT.tray().pend[0];
    for (let i = 0; i < 8 && BT.tray().pend.length && BT.tray().pend[0].kind === 'atk'; i++){ BT.roll(); }
    const hp = BT.sqModels(a).length; const next = BT.myRoll(); BT.roll(); T.settle();
    return { st, ow: ow && ow.kind === 'atk' && ow.u === e.id, cp: BT.cp(1), hp, next, charged: a.charged }; });
  ok(r.st === 'chg.ow:human' && r.ow && r.cp === 1, 'the charged squad is offered overwatch and fires it for 1 CP');
  ok(r.hp < 5 && r.next === 'chg.charge:human' && r.charged, `overwatch sixes drop chargers (${r.hp}/5 left) before the charge roll`);

  // 14. battle-shock: below half at its own command phase; failing makes it shaken (OC 0)
  r = await E(() => { T.setup([['infantry', 1]], [['heavy', 1]]); const a = T.sq(0, 'infantry'), e = T.sq(1, 'heavy');
    BT.place(a.id, 0, 0); BT.place(e.id, 14, 0, -Math.PI/2);
    BT.shootAt(e, a, { hit:[6,6,6,1,1,1], wound:[6,6,6], save:[1,1,1] }); T.settle();
    const left = BT.sqModels(a).length; BT.endTurn(); BT.endTurn();
    const st = BT.myRoll(); BT.dice([1, 2]); BT.roll(); T.settle();
    const o = BT.obj().find(o => o.n === 1);
    return { left, st, shaken: a.shaken, phase: BT.phase(), owner: o.owner, turn: BT.G.turn }; });
  ok(r.left === 2 && r.st === 'shock.shock:human', `a squad at ${r.left}/5 tests its nerve in its command phase`);
  ok(r.shaken && r.phase === 'move' && r.owner === -1, 'failing (1+2 vs 7) shakes it: it no longer holds the objective it stands on');

  // 15. objectives score 5 VP each from round 2
  r = await E(() => { T.setup([['infantry', 1]], [['infantry', 1]]); const a = T.sq(0, 'infantry'), e = T.sq(1, 'infantry');
    const o1 = BT.obj().find(o => o.n === 1); BT.place(a.id, o1.x, o1.z); BT.place(e.id, 25, 15);
    const r1 = BT.vp()[0]; BT.endTurn(); BT.endTurn(); return { r1, r2: BT.vp()[0], round: BT.G.round, owner: BT.obj().find(o => o.n === 1).owner }; });
  ok(r.r1 === 0 && r.r2 === 5 && r.round === 2 && r.owner === 0, `holding an objective scores 5 VP at the round-2 command phase (${r.r1} → ${r.r2})`);

  // 16. grenade: six dice, 4+ each a mortal wound, no save, 1 CP
  r = await E(() => { T.setup([['infantry', 1]], [['infantry', 1]]); const a = T.sq(0, 'infantry'), e = T.sq(1, 'infantry');
    BT.place(a.id, -4, 0, Math.PI/2); BT.place(e.id, 4, 0, -Math.PI/2); BT.setPhase('shoot'); const cp0 = BT.cp(0);
    const aimed = BT.aim(a, e, 'gren'); BT.dice([4, 5, 6, 1, 2, 3]); BT.roll(); T.settle();
    return { aimed, left: BT.sqModels(e).length, cp: cp0 - BT.cp(0), shot: a.shot }; });
  ok(r.aimed && r.left === 2 && r.cp === 1 && r.shot, `a grenade with three 4+ kills three (${r.left} left, ${r.cp} CP)`);

  // 17. go to ground: +1 to the save for 1 CP, at the save roll
  r = await E(() => { T.setup([['heavy', 1]], [['infantry', 1]]); const a = T.sq(0, 'heavy'), e = T.sq(1, 'infantry');
    BT.place(a.id, -10, 0, Math.PI/2); BT.place(e.id, 8, 0, -Math.PI/2); BT.setPhase('shoot'); BT.cp(1, 2);
    BT.aim(a, e, 'atk'); BT.dice([6,6,6,6,6,6, 6,6,6,6,6,6]); BT.roll(); BT.roll();
    const st = BT.myRoll(), sv0 = BT.tray().pend[0] && BT.tray().pend[0].stage;
    BT.dice([5,5,5,5,5,5]); BT.roll({ gtg:true }); T.settle();
    return { st, sv0, cp: BT.cp(1), left: BT.sqModels(e).length }; });
  ok(r.st === 'save:human' && r.cp === 1 && r.left === 5, `going to ground turns 5s into saves against AP1 (6+ → 5+; left ${r.left}/5, CP ${r.cp})`);

  // 18. engaged: can't shoot out (pistols excepted), and nobody shoots into our melee
  r = await E(() => { T.setup([['infantry', 1], ['heavy', 1], ['enemy', 1]], [['infantry', 1]]); const a = T.sq(0, 'infantry'), h = T.sq(0, 'heavy'), j = T.sq(0, 'enemy'), e = T.sq(1, 'infantry');
    BT.place(e.id, 0, 0, 0); BT.place(a.id, 0, 2.2, Math.PI); BT.place(h.id, -14, 0, Math.PI/2); BT.place(j.id, 0, -2.2, 0); BT.setPhase('shoot');
    return { engA: BT.engaged(a), inf: BT.aim(a, e, 'atk'), heavy: BT.aim(h, e, 'atk'), pistol: BT.aim(j, e, 'atk') }; });
  ok(r.engA && r.inf === false && r.heavy === false && r.pistol === true, 'in melee: rifles can\'t fire, nobody fires into it, pistols can');

  // 19. fall back: leave melee, then no shooting or charging this turn
  r = await E(() => { T.setup([['infantry', 1]], [['infantry', 1]]); const a = T.sq(0, 'infantry'), e = T.sq(1, 'infantry');
    BT.place(e.id, 0, 0, 0); BT.place(a.id, 0, 2.2, Math.PI);
    BT.select(a); const need = document.querySelector('#btAct [data-a="fb"]') != null; BT.act('fb'); const moved = BT.tap(0, 8); T.settle();
    BT.nextPhase(); const shoot = BT.aim(a, e, 'atk'); BT.nextPhase(); const ch = BT.charge(a, e);
    return { need, moved, fell: a.fell, eng: BT.engaged(a), shoot, ch }; });
  ok(r.need && r.moved && r.fell && !r.eng, 'an engaged squad falls back out of melee');
  ok(r.shoot === false && /ถอย/.test(r.ch), 'having fallen back it can neither shoot nor charge');

  // 20. five rounds: the most VP wins
  r = await E(() => { T.setup([['infantry', 1]], [['infantry', 1]]); BT.G.vp = [10, 20]; BT.G.round = 5; BT.G.turn = 1;
    BT.endTurn(); return { over: BT.G.over, last: BT.log().slice(-1)[0].t.replace(/<[^>]+>/g, '') }; });
  ok(r.over && /ทีมแดง ชนะ/.test(r.last), 'after round 5 the team with more VP wins: ' + r.last);

  // 21. fight order: chargers, then the other side and ours alternating
  r = await E(() => { T.setup([['hoplite', 2]], [['infantry', 2]]); const a1 = T.sq(0, 'hoplite', 0), a2 = T.sq(0, 'hoplite', 1), b1 = T.sq(1, 'infantry', 0), b2 = T.sq(1, 'infantry', 1);
    BT.place(b1.id, 0, -8, 0); BT.place(a1.id, 0, -5.8, Math.PI); BT.place(b2.id, 0, 8, 0); BT.place(a2.id, 0, 10.2, Math.PI);
    a1.charged = true; BT.setPhase('fight'); return [BT.tray().pend[0] && BT.tray().pend[0].u].concat(BT.fights()).join(' ') + ' | ' + [a1.id, b1.id, b2.id, a2.id].join(' '); });
  const [got, want] = r.split(' | ');
  ok(got.split(' ')[0] === want.split(' ')[0] && got.includes(want.split(' ')[1]), `fight order starts with the charger (${got})`);

  // 22. the charge phase can end while a charge still waits on overwatch (Claude's bt_end_turn right after bt_charge):
  //     the fight order is worked out only once that charge has landed, so the chargers still strike first
  r = await E(() => { T.setup([['hoplite', 1]], [['infantry', 2]]); const a = T.sq(0, 'hoplite'), e = T.sq(1, 'infantry'), e2 = T.sq(1, 'infantry', 1);
    BT.place(a.id, -6, 0, Math.PI/2); BT.place(e.id, 4, 0, -Math.PI/2); BT.place(e2.id, 25, 18); BT.cp(1, 2);
    BT.setPhase('charge'); BT.charge(a, e); const pending = BT.myRoll();
    BT.nextPhase(); const phase = BT.phase(), early = BT.fights().length;
    BT.roll({ yes:false }); BT.dice([6, 6]); BT.roll();
    const first = BT.tray().pend[0];
    return { pending, phase, early, eng: BT.engaged(a), first: first && first.u === a.id && first.stage === 'hit' }; });
  ok(r.pending === 'chg.ow:human' && r.phase === 'fight' && r.early === 0, 'the fight phase starts while the charge still waits on the overwatch choice');
  ok(r.eng && r.first, 'once the charge lands the chargers get the first blow');

  ok(errs.length === 0, 'no page errors' + (errs.length ? ': ' + errs.slice(0, 2).join(' | ') : ''));
  console.log(pass + ' passed, ' + fail + ' failed');
  await b.close(); process.exit(fail ? 1 : 0);
})().catch(e => { console.error('THREW', e); process.exit(1); });
