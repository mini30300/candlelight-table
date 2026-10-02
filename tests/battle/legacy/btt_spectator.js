// Spectator: set it up, skip army + deploy, watch the bots fight with pause / x1 x2 x4 / step, then "ดูอีกรอบ".
const { chromium } = require('playwright');
const F = 'file://' + (process.env.PAGE || require('path').resolve(__dirname, '../../../app/src/main/assets/battle-table.html'));
const OUT = (process.env.TEST_OUT || require('os').tmpdir()) + '/shots/btt';
let pass = 0, fail = 0;
const ok = (c, m) => { c ? pass++ : fail++; console.log((c ? '  ok  ' : '  FAIL') + '  ' + m); };
const events = p => p.evaluate(() => BT.log().reduce((a, l) => a + (l.n || 1), 0));   // repeated lines merge into "×n"
(async () => {
  const b = await chromium.launch({ executablePath: process.env.CHROMIUM_PATH || undefined, args: ['--no-sandbox'] });
  const p = await b.newPage({ viewport: { width: 1366, height: 768 } });
  const errs = []; p.on('pageerror', e => errs.push(String(e)));
  await p.goto(F); await p.waitForFunction('window.BT && window.BT.G'); await p.waitForTimeout(400);
  await p.evaluate(() => { window.seen = {}; ['scArmy', 'scDeploy'].forEach(id => new MutationObserver(() => {
    if (!document.getElementById(id).classList.contains('hide')) window.seen[id] = 1; }).observe(document.getElementById(id), { attributes: true })); });

  console.log('\n-- setup --');
  await p.click('#btModes .mode[data-g="spectator"]');
  await p.evaluate(() => { const n = document.getElementById('btSpecN'); n.value = 3; n.dispatchEvent(new Event('input'));
    // (Round 6: the slider walks a ladder of budgets from 200 to 40,000; its first step is 200)
    const b = document.getElementById('btSpecPts'); b.value = 0; b.dispatchEvent(new Event('input')); });
  const s0 = await p.evaluate(() => ({ teams: BT.G.teams, budget: BT.G.budget, pts: document.getElementById('btPts').value, lab: document.getElementById('btPtsV').textContent }));
  ok(s0.teams === 3 && s0.budget === 200 && s0.pts === '0' && s0.lab === '200', `sides and budget set on the setup screen (${s0.teams} sides, ${s0.budget} pts, army slider at step ${s0.pts} = ${s0.lab})`);
  await p.click('#btNext'); await p.waitForTimeout(300);
  const s1 = await p.evaluate(() => ({ play: !document.getElementById('scPlay').classList.contains('hide'), seen: Object.keys(window.seen),
    bots: BT.players().every(x => x.bot), n: BT.players().length, units: BT.units.length,
    human: document.getElementById('btHumanCtl').classList.contains('hide'), spec: !document.getElementById('btSpec').classList.contains('hide'),
    pts: [0,1,2].map(t => BT.teamPts(t)), timer: BT.G.botTimer, clock: BT.G.timeLeft }));
  ok(s1.play && s1.seen.length === 0, 'straight to the table: no army screen, no deploy screen' + (s1.seen.length ? ' (saw ' + s1.seen + ')' : ''));
  ok(s1.bots && s1.n === 3 && s1.units > 6, `every side is a bot (${s1.n} bots, ${s1.units} models, ${s1.pts.join('/')} pts)`);
  ok(s1.pts.every(x => x > 150 && x <= 200), 'each bot army spent the chosen budget');
  ok(s1.human && s1.spec, 'move/shoot/end-turn buttons hidden, spectator controls shown');
  ok(s1.timer > 0.5 && s1.clock === 0, `a short wait before the first move (${s1.timer.toFixed(2)} s), no clock`);
  await p.waitForTimeout(700);
  await p.screenshot({ path: `${OUT}/spec-desktop.png` });

  console.log('\n-- pause / step --');
  await p.click('#btPause');
  const e0 = await events(p), t0 = await p.evaluate(() => [BT.G.turn, BT.G.round]);
  await p.waitForTimeout(1600);
  const e1 = await events(p), t1 = await p.evaluate(() => [BT.G.turn, BT.G.round]);
  ok(e1 === e0 && t1.join() === t0.join(), `paused: nothing happens for 1.6 s (${e0} -> ${e1} events)`);
  ok(/หยุดอยู่/.test(await p.textContent('#btTurn')) && /เล่นต่อ/.test(await p.textContent('#btPause')), 'turn bar says paused, the button offers เล่นต่อ');
  const steps = [];
  // a turn change runs by itself to the next team's movement phase (fight → next turn → command → movement), so it may log a few lines
  for (let k = 0; k < 4; k++) { const a = await events(p), ta = await p.evaluate(() => BT.G.turn); await p.click('#btStep'); await p.waitForTimeout(250);
    const d = (await events(p)) - a, tb = await p.evaluate(() => BT.G.turn); steps.push(d + (ta !== tb ? 't' : '')); }
  ok(steps.every(s => { const d = parseInt(s), turn = /t/.test(s); return d >= 1 && (d <= 2 || (turn && d <= 5)); }), `each step is one action or one turn change (${steps.join(', ')} log lines, t = turn changed)`);
  await p.waitForFunction('BT.walking() === 0', null, { timeout: 8000 }).catch(() => {});
  ok(await p.evaluate(() => BT.spec.paused), 'still paused after stepping');

  console.log('\n-- speed reaches the walking --');
  // same piece, already facing the mark, same 8 m trip: how long does it take at x1 and at x4?
  const walk = async (k) => {
    await p.click(`#btSpd button[data-s="${k}"]`);
    return p.evaluate(async () => {
      if (window.wi == null) { window.wi = BT.units.findIndex(u => !u.mv); const u = BT.units[wi]; window.w0 = [u.x, u.z]; }
      const u = BT.units[wi]; u.x = w0[0]; u.z = w0[1]; u.rot = Math.PI/2; u.rest = null;
      const tx = u.x + (u.x > 0 ? -8 : 8); u.rot = u.x > 0 ? -Math.PI/2 : Math.PI/2;
      BT.goTo(wi, tx, u.z); const t = performance.now();
      while (BT.units[wi].mv && performance.now() - t < 15000) await new Promise(r => setTimeout(r, 30));
      return (performance.now() - t) / 1000; });
  };
  const w1 = await walk(1), w4 = await walk(4);
  const v1 = 8 / w1, v4 = 8 / w4;
  ok(v4 > v1 * 2.5, `x4 walks faster too: an 8 m walk takes ${w1.toFixed(2)} s at x1, ${w4.toFixed(2)} s at x4`);
  ok(/on/.test(await p.getAttribute('#btSpd button[data-s="4"]', 'class')), 'x4 button lit');

  console.log('\n-- run it to a result at x4 --');
  await p.click('#btPause');
  const tStart = Date.now();
  await p.waitForFunction('BT.G.over', null, { timeout: 180000, polling: 500 }).catch(() => {});
  const end = await p.evaluate(() => ({ over: BT.G.over, round: BT.G.round, live: [0,1,2].map(t => BT.live(t)),
    shots: BT.log().filter(l => /ยิง |ตี /.test(l.base)).length, last: BT.log().slice(-1)[0].t.replace(/<[^>]+>/g, ''),
    again: document.getElementById('btAgain').classList.contains('go'), card: document.getElementById('btCard').textContent }));
  ok(end.over, `the match ends (${((Date.now() - tStart)/1000).toFixed(0)} s at x4, round ${end.round}, left ${end.live.join('/')}, ${end.shots} shot lines)`);
  console.log('   ' + end.last);
  ok(end.again && /ดูอีกรอบ/.test(end.card), 'ดูอีกรอบ is highlighted when it is over');
  await p.screenshot({ path: `${OUT}/spec-over.png` });

  console.log('\n-- ดูอีกรอบ --');
  const before = await p.evaluate(() => ({ seed: BT.seedOf(), fp: BT.props().map(o => o.kind + o.x.toFixed(1)).join() }));
  await p.click('#btSpd button[data-s="1"]'); await p.click('#btAgain'); await p.waitForTimeout(300);
  const again = await p.evaluate(() => ({ seed: BT.seedOf(), fp: BT.props().map(o => o.kind + o.x.toFixed(1)).join(), over: BT.G.over, on: BT.G.on,
    units: BT.units.length, log: BT.log().length, round: BT.G.round, mode: BT.G.mode, label: document.getElementById('btSeed').textContent }));
  console.log('   ' + JSON.stringify({ units: again.units, log: again.log, round: again.round }));
  ok(again.seed !== before.seed && again.fp !== before.fp && again.label === 'สนาม #' + again.seed, `new seed, new field (#${before.seed} -> #${again.seed})`);
  ok(again.on && !again.over && again.units > 6 && again.round === 1 && again.log <= 3 && again.mode === 'spectator', 'a fresh match starts at once');

  console.log('\n-- eight sides, eight colours --');
  await p.evaluate(() => { BT.quit(); BT.spectate(8); });
  await p.waitForTimeout(300);
  const eight = await p.evaluate(() => { const first = BT.log()[0].t; const names = first.match(/ทีม\S+/g) || [];
    const cols = Array.from(document.querySelectorAll('#btTurn span[style]')).map(s => s.style.color).filter(Boolean);
    return { teams: BT.G.teams, names, uniq: new Set(names).size, cols: new Set(cols).size, w: BT.table.w }; });
  ok(eight.teams === 8 && eight.uniq === 8, `8 sides with 8 different names (${eight.names.join(' ')})`);
  ok(eight.cols === 8, `8 different colours in the score bar (${eight.cols}), table grew to ${eight.w}`);
  await p.screenshot({ path: `${OUT}/spec-8.png` });

  console.log('\n-- free fire: bots still shoot the enemy --');
  let friendly = 0, enemy = 0;
  for (const sides of [2, 4]) {
    await p.evaluate((n) => { BT.quit(); document.querySelector('#btFire button[data-f="1"]').click(); BT.size(40); BT.spectate(n); }, sides);
    await p.click('#btSpd button[data-s="4"]');
    await p.waitForFunction('BT.G.over', null, { timeout: 180000, polling: 500 }).catch(() => {});
    const r = await p.evaluate(() => { let f = 0, e = 0;
      BT.log().forEach(l => { const m = l.base.match(/^(ทีม\S+) (?:ยิง|ตี) .*→ .*\((ทีม\S+)\)/); if (m) { if (m[1] === m[2]) f++; else e++; } });
      return { f, e, ff: BT.G.freeFire, over: BT.G.over }; });
    ok(r.ff && r.over, `${sides} sides with free fire on, match over`);
    friendly += r.f; enemy += r.e;
  }
  ok(enemy > 5 && friendly === 0, `shots at enemies ${enemy}, at team-mates ${friendly}`);

  console.log('\n-- range counts from where a walking piece is going --');
  const rg = await p.evaluate(() => {
    BT.quit(); BT.setBuildings(false); BT.G.mode = 'pvp'; BT.G.teams = 2; BT.G.perTeam = 1; BT.G.freeFire = false; BT.G.clock = 0;
    BT.mkPlayers(); BT.setList(0, [0, 1, 0, 0]); BT.setList(1, [0, 1, 0, 0]); BT.start();          // one rifle squad each (range 24")
    BT.props().length = 0;                  // rocks and trees from the last random field could shorten the move: this checks range, not terrain
    const a = BT.squads().find(s => s.side === 0), b = BT.squads().find(s => s.side === 1);
    let z0 = null; for (const z of [0, 1, -1, 2, -2, 3, -3, 4, -4]) { if (z0 !== null) break; let free = true; for (let x = -18; x <= 18; x += 0.5) for (let dz = -3; dz <= 3; dz += 1) if (BT.blockAt(x, z + dz)) free = false; if (free) z0 = z; }   // a clear band near the middle, away from the table edge
    if (z0 === null) return { skip: true };
    BT.place(a.id, -16, z0, Math.PI/2); BT.place(b.id, 15, z0, -Math.PI/2);
    const gap = () => { let d = 1e9; BT.sqModels(a).forEach(m => BT.sqModels(b).forEach(q => { d = Math.min(d, Math.hypot(m.x - q.x, m.z - q.z)); })); return d; };
    const before = gap(), moved = BT.move(a, -10, z0), mid = gap(), walking = BT.sqModels(a).some(m => m.mv), shot = BT.shootAt(a, b);
    return { moved, before: +before.toFixed(1), mid: +mid.toFixed(1), walking, shot, last: BT.log().slice(-1)[0].base };
  });
  ok(!rg.skip && rg.moved && rg.walking && rg.mid > 24 && rg.shot === true,
     `moved 6" closer, shot at once while the models are still ${rg.mid}" away on the table (range 24"): ${rg.shot ? 'allowed' : 'refused'} — ${String(rg.last).replace(/<[^>]+>/g, '').slice(0, 60)}`);
  await p.evaluate(() => { BT.quit(); BT.setBuildings(true); });

  ok(errs.length === 0, errs.length ? 'JS ERRORS: ' + errs.join(' | ') : 'no JS errors');
  console.log(`\n${pass} passed, ${fail} failed`);
  await b.close(); process.exit(fail ? 1 : 0);
})().catch(e => { console.error(e); process.exit(1); });
