// Round 3 rules, one scenario at a time with forced dice: node r3_rules.js
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
      setup(A, B, n){ BT.clock(false); BT.quit(); BT.setTerrain('flat'); BT.setBuildings(false); BT.size(60);
        BT.G.mode = 'pvp'; BT.G.teams = 2; BT.G.perTeam = 1; BT.G.freeFire = false; BT.G.clock = 0; BT.G.budget = 2000; BT.mkPlayers();
        const L = (arr) => { const l = new Array(BT.TYPES.length).fill(0); arr.forEach(([k, n]) => { l[BT.TYPES.findIndex(t => t.k === k)] = n; }); return l; };
        BT.setList(0, L(A)); BT.setList(1, L(B)); BT.players()[0].dep = [-20, 0]; BT.players()[1].dep = [20, 0];
        BT.setAuto(true); BT.start(); BT.dice([]); },
      sq(pl, k, i){ return BT.squads().filter(s => s.pl === pl && s.k === k)[i || 0]; },
      settle(){ for (let i = 0; i < 600 && (BT.walking() || BT.tray().q || (BT.tray().cur && !BT.tray().cur.settled)); i++) BT.tick(1/30, 3); },
      hp(s){ return BT.sqModels(s).map(m => m.hp); },
      alive(s){ return BT.sqModels(s).length; }
    };
  });
  const E = (f, a) => p.evaluate(f, a);

  // 1. every new unit has a datasheet, a faction, a kit and an animation entry
  // (Round 8: cx · KITS_PENDING=k1,k2,… lists figures still being built, for a page that has the new datasheets but not yet their kits)
  let r = await E((pend) => { const facs = ['gr','mod','kn','sw','rb','or','th','jp','nr','eg','md','*','el','de','ta','cx'];   // (Round 6: '*' = the secret hero; Round 7: el de ta; Round 8: cx)
    const bad = BT.TYPES.filter(t => !facs.includes(t.fac) || !t.mel || (!BT.kitInfo(t.k).known && !pend.includes(t.k))).map(t => t.k);
    const per = {}; BT.TYPES.forEach(t => per[t.fac] = (per[t.fac] || 0) + 1);
    return { n: BT.TYPES.length, bad, per: JSON.stringify(per) }; }, (process.env.KITS_PENDING || '').split(',').filter(Boolean));
  ok(r.n >= 89 && !r.bad.length, `${r.n} datasheets across the armies (and the secret hero), each with a kit (${r.per}) ${r.bad.join(',')}`);

  // 2. torrent: the flamer hits automatically, no hit dice
  r = await E(() => { T.setup([['flamer', 1]], [['infantry', 1]]); const a = T.sq(0, 'flamer'), e = T.sq(1, 'infantry');
    BT.place(a.id, -4, 0, Math.PI/2); BT.place(e.id, 4, 0, -Math.PI/2);
    const M = BT.atkMath(a, e); BT.shootAt(a, e, { hit:[], wound:[1,1,1,1,1,1,1,1,1,1], save:[] }); T.settle();
    const log = BT.log().map(l => l.t).filter(t => t.includes('พลพ่นไฟ')).pop() || '';
    return { need: M.need, tr: M.tr, shots: M.shots, log }; });
  ok(r.tr && r.need === 0 && r.shots === 10 && /พ่นโดน 10/.test(r.log), `torrent: 10 automatic hits, no hit roll (${r.log.replace(/<[^>]+>/g, '')})`);

  // 3. lethal hits: 6s to hit wound without a wound roll
  r = await E(() => { T.setup([['rwar', 1]], [['heavy', 1]]); const a = T.sq(0, 'rwar'), e = T.sq(1, 'heavy');
    BT.place(a.id, -8, 0, Math.PI/2); BT.place(e.id, 7, 0, -Math.PI/2);
    const M = BT.atkMath(a, e); BT.shootAt(a, e, { hit:[6,6,6,4,4,1,1,1,1,1], wound:[1,1], save:[1,1,1] }); T.settle();
    return { shots: M.shots, lh: M.lh, alive: T.alive(e), hp: T.hp(e).join(','), left: BT.diceLeft() }; });
  ok(r.lh && r.shots === 10 && r.alive === 2 && r.hp.split(',').sort().join(',') === '1,2', `lethal hits: three 6s wound, two 4s miss on the wound roll → 3 failed saves (hp ${r.hp})`);

  // 4. devastating wounds: a 6 to wound is a mortal wound that spills over
  r = await E(() => { T.setup([['medusa', 1]], [['heavy', 1]]); const a = T.sq(0, 'medusa'), e = T.sq(1, 'heavy');
    BT.place(a.id, -6, 0, Math.PI/2); BT.place(e.id, 6, 0, -Math.PI/2);
    const M = BT.atkMath(a, e); BT.shootAt(a, e, { hit:[6,6], wound:[6,2], save:[] }); T.settle();
    return { sv: M.sv, dw: M.dw, alive: T.alive(e), hp: T.hp(e).sort().join(',') }; });
  ok(r.dw && r.alive === 2 && r.hp === '1,2', `devastating wounds: one mortal wound of 3 kills a 2-wound model and spills 1 (hp ${r.hp})`);

  // 5. Achilles' heel: a 6 to wound slays him through his 3++
  r = await E(() => { T.setup([['infantry', 1]], [['achil', 1]]); const a = T.sq(0, 'infantry'), e = T.sq(1, 'achil');
    BT.place(a.id, -6, 0, Math.PI/2); BT.place(e.id, 6, 0, -Math.PI/2);
    BT.shootAt(a, e, { hit:[6,1,1,1,1,1,1,1,1,1], wound:[5], save:[3] }); T.settle(); const safe = T.alive(e);
    BT.shootAt(a, e, { hit:[6,1,1,1,1,1,1,1,1,1], wound:[6], save:[6] }); T.settle();
    return { safe, after: T.alive(e) }; });
  ok(r.safe === 1 && r.after === 0, 'Achilles: a 5 to wound is saved on his 3++, a 6 to wound slays him outright');

  // 6. hit modifiers: stealth −1, leader aura +1, heavy +1, capped at ±1
  r = await E(() => { T.setup([['infantry', 1], ['archer', 0], ['cmdr', 1]], [['ninja', 1], ['heavy', 1]]);
    const a = T.sq(0, 'infantry'), c = T.sq(0, 'cmdr'), n = T.sq(1, 'ninja'), h = T.sq(1, 'heavy');
    BT.place(a.id, -6, 0, Math.PI/2); BT.place(c.id, -20, 12); BT.place(n.id, 6, 0); BT.place(h.id, 6, 10);
    const stealth = BT.atkMath(a, n).need, plain = BT.atkMath(a, h).need;
    BT.place(c.id, -8, 3); const aura = BT.atkMath(a, h).need, both = BT.atkMath(a, n).need, inA = BT.inAura(a, 'hit');
    return { stealth, plain, aura, both, inA }; });
  ok(r.plain === 4 && r.stealth === 5, `stealth: infantry hit the ninja on 5+ instead of 4+ (${r.stealth})`);
  ok(r.inA && r.aura === 3 && r.both === 4, `leader aura within 6": +1 to hit (3+), and it cancels stealth (${r.aura}, ${r.both})`);
  r = await E(() => { T.setup([['archer', 1], ['cmdr', 1]], [['heavy', 1]]); const a = T.sq(0, 'archer'), c = T.sq(0, 'cmdr'), h = T.sq(1, 'heavy');
    BT.place(a.id, -6, 0, Math.PI/2); BT.place(c.id, -8, 3); BT.place(h.id, 10, 0); return BT.atkMath(a, h).need; });
  ok(r === 3, `heavy standing still + leader aura stay capped at +1 (archers hit on ${r}+)`);

  // 7. armour of faith: incoming AP −1
  r = await E(() => { T.setup([['heavy', 1]], [['knight', 1], ['infantry', 1]]); const a = T.sq(0, 'heavy'), k = T.sq(1, 'knight'), i = T.sq(1, 'infantry');
    BT.place(a.id, -6, 0, Math.PI/2); BT.place(k.id, 8, 0); BT.place(i.id, 8, 10);
    return { kn: BT.atkMath(a, k).sv, inf: BT.atkMath(a, i).sv }; });
  ok(r.kn === 3 && r.inf === 6, `armour of faith: AP1 leaves the knights on 3+ (infantry 5+ → 6+) (${r.kn}, ${r.inf})`);

  // 8. fury: +1 attack on the turn the squad charged
  r = await E(() => { T.setup([['boy', 1]], [['infantry', 1]]); const a = T.sq(0, 'boy'), e = T.sq(1, 'infantry');
    BT.place(a.id, -3, 0, Math.PI/2); BT.place(e.id, 3, 0);
    const calm = BT.atkMath(a, e, 'fight').shots; BT.charged(a, true); const fury = BT.atkMath(a, e, 'fight').shots;
    return { calm, fury }; });
  ok(r.calm === 20 && r.fury === 30, `orks: 20 attacks, 30 on the turn they charged (${r.calm}, ${r.fury})`);

  // 9. advance-and-charge, fly
  r = await E(() => { T.setup([['hound', 1], ['gaunt', 1], ['gargoyle', 1], ['infantry', 1]], [['heavy', 1]]);
    const h = T.sq(0, 'hound'), g = T.sq(0, 'gaunt'), f = T.sq(0, 'gargoyle'), i = T.sq(0, 'infantry'), e = T.sq(1, 'heavy');
    BT.place(h.id, -6, -8, Math.PI/2); BT.place(g.id, -6, 8, Math.PI/2); BT.place(f.id, -6, 0, Math.PI/2); BT.place(i.id, -8, 14, Math.PI/2); BT.place(e.id, 2, 0);
    BT.advd(h, true); BT.advd(g, true); BT.fell(f, true); BT.fell(i, true);
    return { hound: BT.why('chg', h, e), gaunt: BT.why('chg', g, e), flyShot: BT.why('atk', f, e), flyChg: BT.why('chg', f, e), infShot: BT.why('atk', i, e) }; });
  ok(r.hound === '' && /วิ่งมา/.test(r.gaunt), 'hounds may charge after advancing; gaunts may not');
  ok(!/ถอย/.test(r.flyShot) && !/ถอย/.test(r.flyChg) && /ถอย/.test(r.infShot), 'fliers shoot and charge after falling back; infantry cannot');

  // 10. reanimation: fallen robots roll 5+ to stand up with full wounds in their command phase
  r = await E(() => { T.setup([['rwar', 1]], [['infantry', 1]]); const a = T.sq(0, 'rwar'), e = T.sq(1, 'infantry');
    BT.place(a.id, -5, 0, Math.PI/2); BT.place(e.id, 5, 0, -Math.PI/2);
    BT.shootAt(e, a, { hit:[6,6,6,6,6,6,6,6,6,6], wound:[6,6,6,1,1,1,1,1,1,1], save:[1,1,1] }); T.settle();
    const hurt = T.alive(a); BT.dice([]); BT.endTurn(); BT.flush(true); T.settle(); BT.dice([5,1,6]); BT.endTurn();
    const pend = BT.pend().filter(q => q.kind === 'rez').map(q => q.n).join(','); BT.flush(true); T.settle();
    return { hurt, pend, after: T.alive(a), hp: T.hp(a).join(','), log: BT.log().map(l => l.t).filter(t => t.includes('ซ่อมตัวเอง')).pop() || '', round: BT.G.round }; });
  ok(r.hurt === 7 && r.pend === '3' && r.after === 9 && r.hp === '1,1,1,1,1,1,1,1,1', `reanimation: 3 fell, three dice 5,1,6 bring 2 back (${r.hurt} → ${r.after}) ${r.log.replace(/<[^>]+>/g, '')}`);

  // 11. leader aura (ld): below half strength near a synapse warrior passes battle-shock without a roll
  r = await E(() => { T.setup([['gaunt', 2], ['warrior', 1]], [['infantry', 2]]); const g1 = T.sq(0, 'gaunt', 0), g2 = T.sq(0, 'gaunt', 1), w = T.sq(0, 'warrior'), e = T.sq(1, 'infantry');
    BT.place(g1.id, -8, -6, Math.PI/2); BT.place(g2.id, -8, 14, Math.PI/2); BT.place(w.id, -8, -12, Math.PI/2); BT.place(e.id, 6, 0);
    [g1, g2].forEach(g => { const c = BT.sqModels(g)[0]; BT.place(e.id, c.x + 8, c.z, -Math.PI/2);
      BT.shootAt(e, g, { hit:[6,6,6,6,6,6,6,6,6,6], wound:[6,6,6,6,6,6,1,1,1,1], save:[1,1,1,1,1,1] }); T.settle(); });
    BT.place(e.id, 20, 0); const a1 = T.alive(g1), a2 = T.alive(g2); BT.dice([]); BT.endTurn(); BT.flush(true); T.settle(); BT.dice([6,6, 6,6]); BT.endTurn();
    const shock = BT.pend().filter(q => q.kind === 'shock').map(q => q.u);
    const log = BT.log().map(l => l.t).filter(t => t.includes('ผู้นำอยู่ใกล้'));
    T.settle(); return { a1, a2, shock, near: g1.id, far: g2.id, log: log.length }; });
  ok(r.a1 === 4 && r.a2 === 4 && r.log === 1 && r.shock.join() === r.far, `synapse: the squad near the warrior passes battle-shock without a roll, the far one tests (${r.a1}/${r.a2} left, tests: ${r.shock.length})`);

  // 12. Trojan horse: opens in its team's command phase from round 2
  r = await E(() => { T.setup([['troy', 1]], [['infantry', 1]]); const h = T.sq(0, 'troy');
    BT.place(h.id, -10, 0, Math.PI/2);
    const before = BT.squads().filter(s => s.pl === 0).length; BT.endTurn(); T.settle(); BT.endTurn(); T.settle();
    const out = BT.sq(h.id + 'x'); return { before, after: BT.squads().filter(s => s.pl === 0).length, k: out && out.k, n: out ? T.alive(out) : 0, round: BT.G.round }; });
  ok(r.before === 1 && r.after === 2 && r.k === 'hoplite' && r.n === 5 && r.round === 2, `the Trojan horse opens in round 2: 5 hoplites come out (${r.k} ×${r.n})`);

  // 13. Trojan horse destroyed before it opens: the soldiers still come out
  r = await E(() => { T.setup([['troy', 1]], [['mech', 1]]); const h = T.sq(0, 'troy'), m = T.sq(1, 'mech');
    BT.place(h.id, -6, 0, Math.PI/2); BT.place(m.id, 8, 0, -Math.PI/2); BT.cp(1, 0);
    for (let k = 0; k < 3 && T.alive(h); k++){ BT.shootAt(m, h, { hit:[6,6,6,6], wound:[6,6,6,6], save:[1,1,1,1] }); T.settle(); }
    const out = BT.sq(h.id + 'x'); return { horse: T.alive(h), out: out ? T.alive(out) : 0, over: BT.G.over }; });
  ok(r.horse === 0 && r.out === 5 && !r.over, `a destroyed Trojan horse still lets its 5 hoplites out, and the game goes on (${r.out})`);

  // 14. no armour at all (7+): the tray skips the save
  r = await E(() => { T.setup([['infantry', 1]], [['grot', 1]]); const a = T.sq(0, 'infantry'), g = T.sq(1, 'grot');
    BT.place(a.id, -6, 0, Math.PI/2); BT.place(g.id, 6, 0); const M = BT.atkMath(a, g);
    BT.shootAt(a, g, { hit:[6,6,1,1,1,1,1,1,1,1], wound:[6,6], save:[6,6] }); T.settle(); return { sv: M.sv, alive: T.alive(g) }; });
  ok(r.sv === 7 && r.alive === 8, `grots have no save: 2 wounds kill 2 (${r.alive} left)`);

  // 15. model cap per player
  r = await E(() => { const out = []; for (const n of [2, 4, 8]){ BT.G.players = []; BT.G.mode = n === 2 ? 'pvp' : 'ffa'; BT.G.teams = n; BT.G.perTeam = 1; BT.mkPlayers(); out.push(BT.armyCap()); } return out; });
  // (Round 6 raised the cap: 500 models over the players, at most 250 each)
  ok(r.join(',') === '250,125,62', `model cap per player: 2 players 250, 4 players 125, 8 players 62 (${r.join(',')})`);

  // 16. bots of every army play a game to the end without errors
  r = await E(() => { const res = [];
    for (const seed of [11, 23, 37, 58, 71, 94]){ BT.clock(false); BT.quit(); BT.seed(seed); BT.setTerrain('flat'); BT.setBuildings(false); BT.size(60);
      BT.G.mode = 'pve'; BT.G.teams = 2; BT.G.perTeam = 1; BT.G.budget = 500; BT.mkPlayers(); BT.players().forEach(P => P.bot = true);
      BT.start(); let g = 0; while (!BT.G.over && g++ < 4000){ BT.botStep(); BT.tick(1/30, 2); }
      res.push({ over: BT.G.over, round: BT.G.round, facs: BT.players().map(P => P.fac).join('/') }); }
    return res; });
  ok(r.every(x => x.over), 'bot games finish: ' + r.map(x => x.facs + ' r' + x.round + (x.over ? '' : ' (stuck)')).join(' · '));

  ok(!errs.length, 'no page errors' + (errs.length ? ': ' + errs.slice(0, 3).join(' | ') : ''));
  console.log(`\n${pass} passed, ${fail} failed`);
  await b.close(); process.exit(fail ? 1 : 0);
})();
