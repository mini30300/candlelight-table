// The setup screen as drawn, at phone and desktop widths: no sideways scroll, four maps in a row, four terrain
// tiles, the buildings switch + slider, and the six modes in a 2-column grid (spectator with an eye).
const { chromium } = require('playwright');
const F = 'file://' + (process.env.PAGE || require('path').resolve(__dirname, '../../../app/src/main/assets/battle-table.html'));
const OUT = (process.env.TEST_OUT || require('os').tmpdir()) + '/shots/btt';
let pass = 0, fail = 0;
const ok = (c, m) => { c ? pass++ : fail++; console.log((c ? '  ok  ' : '  FAIL') + '  ' + m); };
(async () => {
  const b = await chromium.launch({ executablePath: process.env.CHROMIUM_PATH || undefined, args: ['--no-sandbox'] });
  for (const [w, h] of [[360, 740], [412, 860], [1366, 768]]) {
    const p = await b.newPage({ viewport: { width: w, height: h }, deviceScaleFactor: 2 });
    const errs = []; p.on('pageerror', e => errs.push(String(e)));
    await p.goto(F); await p.waitForFunction('window.BT && window.BT.G'); await p.waitForTimeout(600);
    console.log(`\n== ${w}x${h} ==`);
    const m = await p.evaluate(() => {
      const R = el => { const r = el.getBoundingClientRect(); return { x: Math.round(r.left), y: Math.round(r.top), w: Math.round(r.width), h: Math.round(r.height) }; };
      const q = s => Array.from(document.querySelectorAll(s)).map(R);
      const order = Array.from(document.querySelectorAll('#scSetup > h3, #scSetup > .hrow h3')).map(e => e.textContent.trim());
      const modes = Array.from(document.querySelectorAll('#btModes .mode')).map(e => ({ g: e.dataset.g, t: e.querySelector('.t').textContent, r: R(e),
        tOver: e.querySelector('.t').scrollWidth > e.querySelector('.t').clientWidth + 1 }));
      return { overflowX: document.documentElement.scrollWidth - document.documentElement.clientWidth,
        maps: q('#btMaps .map'), ters: q('#btTer .ter'), modes, order,
        bld: q('#btBld button'), dens: R(document.getElementById('btDens')),
        eye: !!document.querySelector('#btModes .mode[data-g="spectator"] svg circle'),
        tapMin: Math.min(...q('#btTer .ter, #btBld button, #btModes .mode').map(r => r.h)),
        mapLabelsCut: Array.from(document.querySelectorAll('#btMaps .map span')).filter(s => s.scrollWidth > s.clientWidth + 1).map(s => s.textContent) };
    });
    ok(m.overflowX <= 1, `no sideways scroll (${m.overflowX}px)`);
    ok(m.maps.length === 4 && new Set(m.maps.map(r => r.y)).size === 1, `four maps in one row (${m.maps.map(r => r.w).join(',')}px wide)`);
    ok(m.mapLabelsCut.length === 0, 'map names fit' + (m.mapLabelsCut.length ? ' — cut: ' + m.mapLabelsCut.join(',') : ''));
    ok(m.ters.length === 4 && new Set(m.ters.map(r => r.y)).size === 1, 'four terrain tiles in one row');
    ok(m.bld.length === 2 && m.dens.w > 80, `buildings off/on + a real slider (${m.dens.w}px)`);
    const cols = new Set(m.modes.map(x => x.r.x)), rows = new Set(m.modes.map(x => x.r.y));
    ok(m.modes.length === 6 && cols.size === 2 && rows.size === 3, `six modes in a 2x3 grid (${cols.size} cols, ${rows.size} rows)`);
    ok(m.modes.map(x => x.g).join(',') === 'pve,pvp,team,ffa,custom,spectator', 'modes in the drawn order: ' + m.modes.map(x => x.t).join(' / '));
    ok(m.modes.every(x => !x.tOver), 'mode titles fit their tiles');
    ok(m.eye, 'spectator tile has the eye');
    ok(m.tapMin >= 44, `tiles are at least 44px tall (${m.tapMin})`);
    console.log('   headings: ' + m.order.join(' › '));
    ok(errs.length === 0, 'no JS errors');
    // full panel screenshot: scroll the panel/page so every part gets seen
    await p.screenshot({ path: `${OUT}/layout-${w}.png`, fullPage: true });
    if (w >= 900) { await p.evaluate(() => { document.querySelector('#bt .panel').scrollTop = 520; }); await p.waitForTimeout(150); await p.screenshot({ path: `${OUT}/layout-${w}-b.png` }); }
    await p.click('#btModes .mode[data-g="spectator"]'); await p.waitForTimeout(200);
    const sp = await p.evaluate(() => ({ opt: !document.getElementById('btSpecOpt').classList.contains('hide'),
      net: document.getElementById('btNetBox').classList.contains('hide'), clock: document.getElementById('btClockRow').classList.contains('hide'),
      next: document.getElementById('btNext').textContent, ox: document.documentElement.scrollWidth - document.documentElement.clientWidth }));
    ok(sp.opt && sp.net && sp.clock, 'spectator shows sides + budget, hides the friends box and the clock');
    ok(sp.ox <= 1, 'still no sideways scroll in spectator setup');
    await p.locator('#scSetup').screenshot({ path: `${OUT}/layout-${w}-spec.png` });
    await p.click('#btNext'); await p.waitForTimeout(1500);
    const pl = await p.evaluate(() => { const r = id => document.getElementById(id).getBoundingClientRect();
      return { ox: document.documentElement.scrollWidth - document.documentElement.clientWidth,
        btns: Array.from(document.querySelectorAll('#btSpec button')).map(b => Math.round(b.getBoundingClientRect().height)),
        cut: Array.from(document.querySelectorAll('#btSpec button')).filter(b => b.scrollWidth > b.clientWidth + 1).map(b => b.textContent) }; });
    ok(pl.ox <= 1, `spectator play: no sideways scroll (${pl.ox}px)`);
    ok(pl.btns.length === 6 && Math.min(...pl.btns) >= 44 && pl.cut.length === 0, `spectator buttons fit and are 44px+ (${pl.btns.join(',')})` + (pl.cut.length ? ' cut: ' + pl.cut : ''));
    await p.screenshot({ path: `${OUT}/spec-play-${w}.png`, fullPage: w < 900 });
    await p.close();
  }
  await b.close();
  console.log(`\n${pass} passed, ${fail} failed`); process.exit(fail ? 1 : 0);
})().catch(e => { console.error(e); process.exit(1); });
