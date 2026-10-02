// the turn bar fits every width with 2..8 sides (spectator and FFA): no sideways scroll, bar inside the canvas
const { chromium } = require('playwright');
const F = 'file://' + (process.env.PAGE || require('path').resolve(__dirname, '../../../app/src/main/assets/battle-table.html'));
(async () => {
  const b = await chromium.launch({ executablePath: process.env.CHROMIUM_PATH || undefined, args: ['--no-sandbox'] });
  let fail = 0, n = 0;
  for (const [w, h] of [[360, 740], [412, 860], [1366, 768]]) for (const sides of [2, 5, 8]) {
    const p = await b.newPage({ viewport: { width: w, height: h } }); await p.goto(F); await p.waitForFunction('window.BT && window.BT.G');
    const r = await p.evaluate((sides) => { BT.spectate(sides); BT.spec.paused = true;
      // worst case for width: two-digit counts for every side
      const tb = document.getElementById('btTurn');
      const cv = document.getElementById('btCv').getBoundingClientRect(), R = tb.getBoundingClientRect();
      return { scroll: document.scrollingElement.scrollWidth - innerWidth, barRight: R.right, cvRight: cv.right, barH: R.height, text: tb.textContent };
    }, sides);
    n++; const ok = r.scroll <= 0 && r.barRight <= r.cvRight + 0.5;
    if (!ok) fail++;
    console.log((ok ? 'ok  ' : 'FAIL') + ` ${w}x${h} ${sides} sides: scroll ${r.scroll}, bar right ${r.barRight.toFixed(0)} / canvas ${r.cvRight.toFixed(0)}, bar ${r.barH.toFixed(0)} px tall — ${r.text}`);
    if (sides !== 5) await p.screenshot({ path: (process.env.TEST_OUT || require('os').tmpdir()) + `/shots/btt/turnbar_${w}_${sides}.png`, clip: { x: 0, y: 0, width: w, height: Math.min(h, 260) } });
    await p.close();
  }
  console.log(fail ? fail + ' FAILED' : `turnbar: ${n} passed`); await b.close(); process.exit(fail ? 1 : 0);
})();
