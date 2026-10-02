// Round 5a: a lowered render scale while moving, one full-resolution frame once the table stands still, back to the
// lowered scale when it moves again; the far-figure pictures are not remade when the render scale changes.
//   node r5_sharp.js [page]
const { chromium } = require('playwright');
const PAGE = process.argv[2] || process.env.PAGE || require('path').resolve(__dirname, '../../../app/src/main/assets/battle-table.html');
let pass = 0, fail = 0; const ok = (c, m, x) => { if (c) pass++; else fail++; console.log((c ? '  ok    ' : '  FAIL  ') + m + (x !== undefined ? '  ' + JSON.stringify(x) : '')); };
(async () => {
  const b = await chromium.launch({ executablePath: process.env.CHROMIUM_PATH || undefined, args: ['--no-sandbox'] });
  for (const [nm, opt] of [['desk', { viewport: { width: 1366, height: 700 }, deviceScaleFactor: 1 }], ['phone', { viewport: { width: 390, height: 844 }, deviceScaleFactor: 3, isMobile: true, hasTouch: true }]]) {
    const ctx = await b.newContext(opt), p = await ctx.newPage(); const errs = []; p.on('pageerror', e => errs.push(String(e)));
    await p.goto('file://' + PAGE); await p.waitForFunction('window.BT && window.BT.G'); await p.waitForTimeout(400);
    await p.evaluate(() => { BT.setTheme('desert'); BT.setTerrain('flat'); BT.size(94); BT.setBuildings(true, 1); BT.G.budget = 2000; BT.mkPlayers();
      const L = (arr) => { const l = new Array(BT.TYPES.length).fill(0); arr.forEach(s => { const [k, n] = s.split(':'); l[BT.TYPES.findIndex(t => t.k === k)] = +n; }); return l; };
      BT.setList(0, L(['infantry:6','heavy:3','enemy:3','mech:1','tank:1','flamer:2','cmdr:1']));
      BT.setList(1, L(['hoplite:6','archer:3','spartan:2','cavalry:2','centaur:1','achil:1','cyclops:1']));
      BT.setDep(0, -30, 0); BT.setDep(1, 30, 0); BT.start(); BT.fit(); });
    await p.waitForTimeout(700);
    const cvw = () => p.evaluate(() => { const c = document.getElementById('btCv'), r = c.getBoundingClientRect(); return { w: c.width, css: Math.round(r.width), dpr0: Math.min(2, devicePixelRatio), s: BT.sprites() }; });
    const full = await cvw();
    ok(Math.abs(full.w - full.css * full.dpr0) <= 1, `${nm}: at full scale the canvas has the screen's pixels`, full);
    // far view: pictures made; a render-scale change must not remake them
    const n0 = (await cvw()).s.n;
    await p.evaluate(() => { BT.renderScale(0.55); BT.renderScale(null); });    // as the frame loop would after slow frames
    await p.waitForTimeout(120);
    const low = await cvw();
    ok(low.s.rs === 0.55 && low.w < full.w * 0.6 && !low.s.sharp, `${nm}: while moving, the table draws into fewer pixels`, { w: low.w, rs: low.s.rs, sharp: low.s.sharp });
    ok(n0 > 0 && low.s.n === n0, `${nm}: the far-figure pictures are kept when the render scale changes (${n0} -> ${low.s.n})`);
    await p.waitForTimeout(700);                                              // standing still: one full-resolution frame
    const still = await cvw();
    ok(still.s.sharp && Math.abs(still.w - full.w) <= 1 && still.s.rs === 0.55, `${nm}: standing still, it is drawn once at full resolution`, { w: still.w, full: full.w, sharp: still.s.sharp, rs: still.s.rs });
    const r0 = await p.evaluate(() => BT.redraws()); await p.waitForTimeout(500); const r1 = await p.evaluate(() => BT.redraws());
    ok(r1 === r0, `${nm}: and then not again while nothing moves (${r0} -> ${r1})`);
    await p.evaluate(() => { BT.cam.yaw += 0.02; BT.fit(); });                  // moving again
    await p.waitForTimeout(100);
    const again = await cvw();
    ok(!again.s.sharp && again.w < full.w * (again.s.rs + 0.05), `${nm}: moving again goes back to the lowered scale`, { w: again.w, rs: again.s.rs, sharp: again.s.sharp });
    await p.evaluate(() => BT.renderScale(1)); await p.waitForTimeout(100);
    const back = await cvw();
    ok(Math.abs(back.w - full.w) <= 1 && !back.s.sharp, `${nm}: at scale 1 there is no extra still frame to draw`, { w: back.w, sharp: back.s.sharp });
    ok(errs.length === 0, `${nm}: no page errors`, errs.slice(0, 2));
    await ctx.close();
  }
  await b.close(); console.log(`${pass} passed, ${fail} failed`); process.exit(fail ? 1 : 0);
})().catch(e => { console.error('THREW', e); process.exit(1); });
