// Round 5b: fliers fly. They hover at their height, glide (no walker) and land on the exact spot, hold their wings still
// when nothing moves (no redraws), come down to fight when locked in combat and go back up after, drop when they die,
// and get shot at up there. node r5b_fly.js   (PAGE=... for another page)
const { chromium } = require('playwright');
const F = 'file://' + (process.env.PAGE || require('path').resolve(__dirname, '../../../app/src/main/assets/battle-table.html'));
let pass = 0, fail = 0; const ok = (c, m, x) => { c ? pass++ : fail++; console.log((c ? 'ok   ' : 'FAIL ') + m + (x !== undefined ? '  ' + JSON.stringify(x) : '')); };
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
      air(s){ return BT.sqModels(s).map(m => +(m.alt || 0).toFixed(2)); }
    };
  });
  const E = (f, a) => p.evaluate(f, a);
  let r = await E(() => { T.setup([['valkyrie', 1], ['dragon', 1]], [['infantry', 1]]); BT.tick(1/30, 60);
    const v = T.sq(0, 'valkyrie'), d = T.sq(0, 'dragon'), e = T.sq(1, 'infantry');
    return { v: T.air(v), d: T.air(d), e: T.air(e) }; });
  ok(r.v.every(a => a === 1.45) && r.d[0] === 2.4 && r.e.every(a => a === 0), 'at the start the valkyries hover at 1.45 m and the dragon at 2.4 m; the infantry stands on the ground', r);

  // standing still: wings held out, nothing redrawn
  r = await E(() => { BT.tick(1/30, 60); const v = T.sq(0, 'valkyrie'); return { fph: BT.sqModels(v).map(m => m.fph == null ? null : m.fph) }; });
  ok(r.fph.every(f => f === null), 'hovering still, the wings are held out in a glide (no beat)', r);
  await p.waitForTimeout(300);
  const r0 = await E(() => BT.redraws()); await p.waitForTimeout(700); const r1 = await E(() => BT.redraws());
  ok(r1 === r0, `and the table is not redrawn while nothing moves (${r0} -> ${r1})`);

  // a move: gliding, no walker, wings beating, landing exactly on the mark
  r = await E(() => { const v = T.sq(0, 'valkyrie'), m = BT.sqModels(v)[0], i = BT.units.indexOf(m), tx = m.x + 4, tz = m.z + 2;
    BT.goTo(i, tx, tz); BT.tick(1/30, 8);
    const mid = { fm: !!m.fm, ctl: !!m.ctl, fph: m.fph, alt: m.alt, mv: !!m.mv };
    for (let k = 0; k < 200 && m.mv; k++) BT.tick(1/30, 1);
    const end = { x: m.x, z: m.z, tx, tz, mv: !!m.mv, alt: m.alt, beat: m.fph != null };
    BT.tick(1/30, 60); end.still = m.fph == null; return { mid, end }; });
  ok(r.mid.fm && !r.mid.ctl && r.mid.fph != null && r.mid.mv, 'moving, a valkyrie glides with its wings beating, and no walking gait is used', r.mid);
  ok(Math.hypot(r.end.x - r.end.tx, r.end.z - r.end.tz) < 1e-9 && !r.end.mv && Math.abs(r.end.alt - 1.45) < 0.01, 'it arrives exactly on the mark and hovers on', r.end);
  ok(r.end.beat && r.end.still, 'its wings beat a moment after it stops, then are held still again');

  // locked in combat: down on the ground; free again: back up
  r = await E(() => { const v = T.sq(0, 'valkyrie'), e = T.sq(1, 'infantry'); BT.place(v.id, 0, 0, Math.PI/2); BT.place(e.id, 1.9, 0, -Math.PI/2);
    const eng = BT.engaged(v); BT.tick(1/30, 120); const down = T.air(v);
    BT.place(e.id, 20, 10, -Math.PI/2); BT.tick(1/30, 120); return { eng, down, up: T.air(v) }; });
  ok(r.eng && r.down.every(a => a < 0.02), 'locked in combat, the valkyries come down to fight on the ground', r);
  ok(r.up.every(a => Math.abs(a - 1.45) < 0.02), 'out of combat, they fly back up', r.up);

  // shot at up there: the shots go to the figure in the air, not its base
  r = await E(() => { const v = T.sq(0, 'valkyrie'), m = BT.sqModels(v)[0], aim = BT.aimPoint ? BT.aimPoint(m) : null;
    const g = BT.heightAt(m.x, m.z); return { aimY: aim && aim[1], ground: g }; });
  ok(r.aimY != null && r.aimY - r.ground > 1.45 + 0.8, 'shots aim at the figure up in the air', r);

  // the fall: a dead flier drops to the ground (watched frame by frame until its body fades away)
  r = await E(() => { const v = T.sq(0, 'valkyrie'), e = T.sq(1, 'infantry'), c = BT.sqModels(v)[0], id = c.id;
    BT.place(e.id, c.x + 8, c.z, -Math.PI/2);
    BT.shootAt(e, v, { hit:[6,6,6,6,6,6,6,6,6,6], wound:[6,6,6,6,6,6,6,6,6,6], save:[1,1,1,1,1,1,1,1,1,1] });
    const seen = []; let t = 0;
    for (let k = 0; k < 900; k++){ BT.tick(1/30, 1); const f = BT.fallen().find(u => u.id === id); if (f){ seen.push(+(f.alt || 0).toFixed(2)); } else if (seen.length) break; }
    return { dead: !BT.units.some(u => u.id === id), first: seen[0], last: seen[seen.length - 1], frames: seen.length, hitGround: seen.indexOf(0) }; });
  ok(r.dead && r.first > 1 && r.last === 0 && r.hitGround > 0 && r.hitGround < 30, 'a valkyrie that dies drops to the ground, in under a second', r);

  // the dragon lands and takes off the same way, and far away it still flies (a picture at its height)
  r = await E(() => { const d = T.sq(0, 'dragon'), m = BT.sqModels(d)[0]; BT.cam.tx = 0; BT.cam.tz = 0; BT.cam.dist = 160; BT.cam.pitch = 0.5; BT.tick(1/30, 2); BT.draw(); BT.draw();
    return { alt: m.alt, lod: m.lod, px: m.px }; });
  ok(r.alt === 2.4, 'far away the dragon is still up at its height', r);
  ok(errs.length === 0, 'no page errors', errs.slice(0, 3));
  console.log(`${pass} passed, ${fail} failed`); await b.close(); process.exit(fail ? 1 : 0);
})().catch(e => { console.error('THREW', e); process.exit(1); });
