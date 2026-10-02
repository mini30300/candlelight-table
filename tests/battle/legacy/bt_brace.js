// A hoplite shot at twice in a row: the shield comes up with the first attack, stays up through the second,
// turns to face the second shooter, then comes down once the last dice stop. Held still, it costs no redraws.
const { chromium } = require('playwright');
const F = 'file://' + (process.env.PAGE || require('path').resolve(__dirname, '../../../app/src/main/assets/battle-table.html'));
let pass = 0, fail = 0; const ok = (c, m) => { c ? pass++ : fail++; console.log((c ? 'ok   ' : 'FAIL ') + m); };
(async () => {
  const b = await chromium.launch({ executablePath: process.env.CHROMIUM_PATH || undefined, args: ['--no-sandbox'] });
  const p = await b.newPage({ viewport: { width: 1000, height: 700 } });
  const errs = []; p.on('pageerror', e => errs.push(String(e)));
  await p.goto(F); await p.waitForFunction('window.BT && window.BT.G');
  await p.evaluate(() => {
    BT.clock(true); BT.quit(); BT.setTerrain('flat'); BT.setBuildings(false); BT.size(40); BT.mkPlayers();
    const L0 = new Array(12).fill(0), L1 = new Array(12).fill(0); L0[1] = 2; L1[2] = 1;          // two rifle squads, one hoplite squad
    BT.setList(0, L0); BT.setList(1, L1); BT.start(); BT.clock(false);
    const us = BT.squads().filter(s => s.side === 0), ds = BT.squads().find(s => s.side === 1);
    BT.place(ds.id, 0, 0, 0); BT.place(us[0].id, -8, 7, 2.3); BT.place(us[1].id, 8, 7, -2.3);
    const d = BT.sqModels(ds)[2];                                                                  // the middle hoplite
    window.__d = d; window.__ds = ds; window.__u = us;
    // every shot hits and wounds, every save holds: the hoplites live through both volleys
    const n0 = BT.atkMath(us[0], ds).shots, n1 = BT.atkMath(us[1], ds).shots, six = n => new Array(n).fill(6);
    BT.shootAt(us[0], ds, { hit:six(n0), wound:six(n0), save:six(n0) });
    BT.shootAt(us[1], ds, { hit:six(n1), wound:six(n1), save:six(n1) });
  });
  const samples = [];
  for (let i = 0; i < 160; i++) {                     // 16 s of play, 0.1 s a sample
    await p.evaluate(() => BT.tick(1/60, 6));
    samples.push(await p.evaluate(() => { const a = BT.acts().find(x => x.id === window.__d.id); const d = window.__d;
      return { t: 0, kind: a ? a.kind : null, up: a ? a.up : null, rot: d.rot, tray: BT.tray ? BT.tray() : null }; }));
  }
  const firstUp = samples.findIndex(s => s.kind === 'brace' && s.up >= 1), lastBrace = samples.map(s => s.kind === 'brace').lastIndexOf(true);
  ok(firstUp >= 0 && firstUp <= 6, 'shield is fully up within 0.6 s of the first attack (sample ' + firstUp + ')');
  const between = samples.slice(firstUp, Math.max(firstUp, lastBrace - 4));
  const dips = between.filter(s => s.kind !== 'brace' || s.up < 1).length;
  ok(between.length > 20 && dips === 0, 'shield stays fully up from the first attack through the second (' + between.length + ' samples, ' + dips + ' dips)');
  ok(lastBrace > 0 && lastBrace < 150, 'shield comes down after the last dice stop (last braced sample ' + lastBrace + ')');
  ok(samples.slice(lastBrace + 1).every(s => s.kind === null), 'no action left on the hoplite afterwards');
  const rotA = samples[firstUp + 3].rot, rotB = samples[lastBrace - 2].rot;
  const [ca, cb, cd] = await p.evaluate(() => [window.__u[0], window.__u[1], window.__ds].map(s => { const ms = BT.sqModels(s); return [ms.reduce((n, m) => n + m.x, 0)/ms.length, ms.reduce((n, m) => n + m.z, 0)/ms.length]; }));
  const dm = await p.evaluate(() => [window.__d.x, window.__d.z]);
  const toA = Math.atan2(ca[0] - dm[0], ca[1] - dm[1]), toB = Math.atan2(cb[0] - dm[0], cb[1] - dm[1]);
  const near = (x, y) => Math.abs(Math.atan2(Math.sin(x - y), Math.cos(x - y))) < 0.15;
  ok(near(rotA, toA), 'faces the first shooter while braced (' + rotA.toFixed(2) + ' vs ' + toA.toFixed(2) + ')');
  ok(near(rotB, toB), 'turns to face the second shooter (' + rotB.toFixed(2) + ' vs ' + toB.toFixed(2) + ')');
  // held still: a human's attack waiting on its wound roll keeps the shield up, and a steady shield asks for no redraws
  const held = await p.evaluate(() => {
    BT.setAuto(false); const d = window.__d, a = window.__u[0];
    a.shot = false; Math.random = () => 0.99;                         // every die a 6: the shot hits
    const aimed = BT.aim(a, window.__ds), rolled = BT.roll();   // the hit roll; the wound roll now waits for the player
    for (let i = 0; i < 40; i++) BT.tick(1/60, 6);                     // 4 s: the hit dice land and settle
    const x = BT.acts().find(z => z.id === d.id);
    return { my: BT.myRoll(), act: x || null, aimed, rolled, over: BT.G.over, turn: BT.G.turn, side: BT.G.side, log: (BT.log().slice(-2).map(l => l.t.replace(/<[^>]+>/g, ''))) };
  });
  ok(held.my === 'wound:human', 'the wound roll waits for the player (' + held.my + ')');
  ok(held.act && held.act.kind === 'brace' && held.act.up === 1, 'the shield stays up while the player decides (' + JSON.stringify(held.act) + ')');
  ok(held.act && held.act.still, 'a steady raised shield is not redrawn every frame');
  ok(errs.length === 0, 'no page errors' + (errs.length ? ': ' + errs.slice(0, 2).join(' | ') : ''));
  console.log(pass + ' passed, ' + fail + ' failed');
  await b.close(); process.exit(fail ? 1 : 0);
})().catch(e => { console.error('THREW', e); process.exit(1); });
