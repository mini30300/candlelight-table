// Round 7.1: the graphics setting (high / medium / low, remembered, on every screen) and spectator mode with the viewer
// placing each bot army's deployment point.   node r71_test.js [page]
const { chromium } = require('playwright');
const F = 'file://' + require('path').resolve(process.argv[2] || process.env.PAGE || require('path').resolve(__dirname, '../../app/src/main/assets/battle-table.html'));
let pass = 0, fail = 0; const ok = (c, m, x) => { c ? pass++ : fail++; console.log((c ? 'ok   ' : 'FAIL ') + m + (x !== undefined ? '  ' + JSON.stringify(x) : '')); };
(async () => {
  const b = await chromium.launch({ executablePath: process.env.CHROMIUM_PATH || undefined, args: ['--no-sandbox'] });
  const ctx = await b.newContext({ viewport: { width: 1280, height: 860 }, deviceScaleFactor: 2 });
  const p = await ctx.newPage(); const errs = []; p.on('pageerror', e => errs.push(String(e)));
  await p.goto(F); await p.waitForFunction('window.BT && window.BT.G'); await p.waitForTimeout(300);
  let r = await p.evaluate(() => ({ g: BT.gfx(), on: document.querySelector('#btGfx .on').dataset.g, vis: !!document.querySelector('#btGfx').offsetParent, ver: (document.getElementById('btVer') || {}).textContent }));
  ok(r.g.g === 'mid' && r.on === 'mid' && r.vis && r.g.dpr === 2, 'the first screen shows the graphics row with medium on (pixel ratio 2)', r);
  ok(parseFloat((r.ver || '').replace(/[^\d.]/g, '')) >= 8.1, 'the version label reads 8.1 or later', r.ver);
  await p.click('#btGfx button[data-g="lo"]'); await p.waitForTimeout(200);
  r = await p.evaluate(() => ({ g: BT.gfx(), on: document.querySelector('#btGfx .on').dataset.g, ls: localStorage.getItem('bt_gfx'), cw: document.getElementById('btCv').width, css: document.getElementById('btCv').clientWidth }));
  ok(r.g.g === 'lo' && r.on === 'lo' && r.ls === 'lo' && r.g.dpr === 1 && r.g.face === 4500 && r.g.lod >= 1.6 && r.g.rs <= 0.8, 'low: pixel ratio 1, render scale at most 0.8, a smaller facet budget, far figures simpler sooner, remembered', r);
  ok(r.cw <= r.css + 1, 'low: the canvas has no more pixels than its size on screen', { cw: r.cw, css: r.css });
  await p.reload(); await p.waitForFunction('window.BT && window.BT.G'); await p.waitForTimeout(300);
  r = await p.evaluate(() => ({ g: BT.gfx(), on: document.querySelector('#btGfx .on').dataset.g }));
  ok(r.g.g === 'lo' && r.on === 'lo', 'after reopening, low is still on', r);
  // a still table on low is not redrawn sharp; on medium it is
  r = await p.evaluate(async () => { BT.renderScale(null); const s0 = BT.sprites(); await new Promise(res => setTimeout(res, 1200)); return BT.sprites(); });
  ok(!r.sharp, 'low: a still table is not redrawn at full sharpness', r);
  await p.click('#btGfx button[data-g="hi"]'); await p.waitForTimeout(150);
  r = await p.evaluate(() => BT.gfx());
  ok(r.g === 'hi' && r.face === 16000 && r.rsMin === 0.7, 'high: a bigger facet budget and render scale never under 0.7', r);
  await p.click('#btGfx button[data-g="mid"]'); await p.waitForTimeout(150);
  r = await p.evaluate(() => BT.gfx());
  ok(r.g === 'mid' && r.face === 9000 && r.rsMin === 0.55 && r.dpr === 2, 'medium: back to the Round 7 behaviour', r);

  // spectator: random armies, place the ground yourself
  await p.click('#btModes .mode[data-g="spectator"]'); await p.waitForTimeout(120);
  await p.click('#btSpecDep button[data-d="1"]'); await p.waitForTimeout(80);
  ok(/วางจุดลงสนาม/.test(await p.textContent('#btNext')), 'spectator + "place myself": the next button says it goes to the deployment points', await p.textContent('#btNext'));
  await p.click('#btNext'); await p.waitForTimeout(300);
  r = await p.evaluate(() => ({ dep: !document.getElementById('scDeploy').classList.contains('hide'), all: !document.getElementById('btDepAll').classList.contains('hide'),
    who: document.getElementById('btDepWho').textContent, n: BT.players().length, on: BT.G.on }));
  ok(r.dep && r.all && /กองนี้/.test(r.who) && r.n === 2 && !r.on, 'the deployment screen opens for the first bot, with "the rest pick their own ground"', r);
  // place bot 1 by tapping the table left of centre, then bot 2 on the right
  const box = await p.locator('#btCv').boundingBox();
  const tapAt = async (fx, fy) => { await p.mouse.click(box.x + box.width*fx, box.y + box.height*fy); await p.waitForTimeout(150); };
  await tapAt(0.3, 0.55); r = await p.evaluate(() => BT.players()[0].dep);
  ok(Array.isArray(r), 'tapping the table places bot 1', r);
  const dep0 = r;
  await p.click('#btDepGo'); await p.waitForTimeout(150);
  await tapAt(0.72, 0.5); r = await p.evaluate(() => BT.players()[1].dep);
  ok(Array.isArray(r), 'then bot 2', r);
  const dep1 = r;
  ok(/เริ่มดูบอทตีกัน/.test(await p.textContent('#btDepGo')), 'the last button starts the bots\' fight', await p.textContent('#btDepGo'));
  await p.click('#btDepGo'); await p.waitForTimeout(400);
  r = await p.evaluate(() => { const c = [0, 1].map(pl => { const ms = BT.units.filter(u => u.pl === pl); const x = ms.reduce((s, u) => s + u.x, 0)/ms.length, z = ms.reduce((s, u) => s + u.z, 0)/ms.length; return [x, z]; });
    return { on: BT.G.on, watching: BT.players().every(P => P.bot), c }; });
  const near = (c, d) => Math.hypot(c[0] - d[0], c[1] - d[1]) < 8;
  ok(r.on && r.watching && near(r.c[0], dep0) && near(r.c[1], dep1), 'the fight starts with each army standing where it was placed', { c: r.c, dep0, dep1 });
  // spectator: build armies, place the ground, and hand the rest to the bots
  await p.evaluate(() => BT.quit()); await p.waitForTimeout(200);
  await p.click('#btModes .mode[data-g="spectator"]'); await p.waitForTimeout(100);
  await p.click('#btSpecOwn button[data-o="1"]'); await p.click('#btSpecDep button[data-d="1"]');
  await p.click('#btNext'); await p.waitForTimeout(200);
  await p.click('#btStart'); await p.waitForTimeout(150); await p.click('#btStart'); await p.waitForTimeout(250);
  r = await p.evaluate(() => !document.getElementById('scDeploy').classList.contains('hide'));
  ok(r, 'with armies built by the viewer, "place myself" also opens the deployment screen');
  await tapAt(0.35, 0.5);
  await p.click('#btDepAll'); await p.waitForTimeout(400);
  r = await p.evaluate(() => ({ on: BT.G.on, n: BT.units.length, deps: BT.players().map(P => !!P.dep) }));
  ok(r.on && r.n > 0, '"the rest pick their own ground" starts at once', r);
  ok(errs.length === 0, 'no page errors', errs.slice(0, 3));
  console.log(`\n${pass}/${pass + fail} passed`);
  await b.close(); process.exit(fail ? 1 : 0);
})().catch(e => { console.error('THREW', e); process.exit(2); });
