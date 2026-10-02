// The phone bug: with no viewport tag the WebView lays out at 980 CSS px, which
// tripped the wide-screen layout and shrank the whole page to a strip. Prove the
// layout now picks the right shape at each real size, and that nothing is off-screen.
const { chromium } = require('playwright');
const fail = [];
const ok = (c, m) => { console.log((c ? '  ok   ' : '  FAIL ') + m); if (!c) fail.push(m); };

const SIZES = [
  { w: 412, h: 860, want: 'column', name: 'phone upright' },
  { w: 360, h: 740, want: 'column', name: 'small phone' },
  { w: 900, h: 412, want: 'column', name: 'phone sideways' },
  { w: 1366, h: 768, want: 'row', name: 'laptop' },
];

(async () => {
  const b = await chromium.launch({ executablePath: process.env.CHROMIUM_PATH || undefined, args: ['--no-sandbox'] });
  for (const S of SIZES) {
    const p = await b.newPage({ viewport: { width: S.w, height: S.h }, deviceScaleFactor: 2 });
    const errs = []; p.on('pageerror', e => errs.push(String(e)));
    await p.goto('file://' + (process.env.PAGE || require('path').resolve(__dirname, '../../../app/src/main/assets/battle-table.html')));
    await p.waitForFunction('window.BT && window.BT.G');
    await p.waitForTimeout(700);
    const m = await p.evaluate(() => {
      const sh = getComputedStyle(document.querySelector('#bt .shell')).flexDirection;
      const cv = document.querySelector('#btCv').getBoundingClientRect();
      const nx = document.querySelector('#btNext').getBoundingClientRect();
      const maps = document.querySelector('#btMaps').getBoundingClientRect();
      return { dir: sh, cvW: Math.round(cv.width), cvH: Math.round(cv.height),
        nextW: Math.round(nx.width), mapsW: Math.round(maps.width),
        overflowX: document.documentElement.scrollWidth - document.documentElement.clientWidth,
        vw: innerWidth };
    });
    console.log(`\n== ${S.name} ${S.w}x${S.h} ==`, JSON.stringify(m));
    ok(m.dir === (S.want === 'row' ? 'row' : 'column'), `layout is ${S.want}`);
    ok(m.cvW > S.w * 0.4, `board is a real size (${m.cvW}x${m.cvH} px)`);
    ok(m.cvH > 120, 'board is not a thin strip');
    ok(m.nextW > 80 && m.mapsW > 120, 'the controls are laid out, not collapsed');
    ok(m.overflowX <= 1, `no sideways scroll (${m.overflowX} px)`);
    ok(errs.length === 0, 'no JS errors');
    await p.screenshot({ path: __dirname + `/../shots/bt/fit-${S.w}x${S.h}.png` });
    await p.close();
  }
  await b.close();
  console.log(fail.length ? '\n' + fail.length + ' FAILED' : '\nall checks passed');
  process.exit(fail.length ? 1 : 0);
})().catch(e => { console.error(e); process.exit(1); });
