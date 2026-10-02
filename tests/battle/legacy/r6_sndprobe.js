// every sound, and eight beats of the music, rendered offline: each makes a real sound (not silent), none clips or breaks
const { chromium } = require('playwright');
const PAGE = process.argv[2] || process.env.PAGE || require('path').resolve(__dirname, '../../../app/src/main/assets/battle-table.html');
let pass = 0, fail = 0; const ok = (c, m, x) => { c ? pass++ : fail++; console.log((c ? 'ok   ' : 'FAIL ') + m + (x !== undefined ? '  ' + JSON.stringify(x) : '')); };
(async () => {
  const b = await chromium.launch({ executablePath: process.env.CHROMIUM_PATH || undefined, args: ['--no-sandbox'] });
  const p = await b.newPage(); const errs = []; p.on('pageerror', e => errs.push(String(e)));
  await p.goto('file://' + PAGE); await p.waitForFunction('window.BT && window.BT.snd');
  const kinds = await p.evaluate(() => BT.snd.kinds().concat(['music']));
  const res = {};
  for (const k of kinds) res[k] = await p.evaluate((k) => new Promise(r => BT.snd.probe(k, r)), k);
  for (const k of kinds){ const r = res[k];
    ok(r && !r.err && !r.nan && r.peak > 0.02 && r.peak < 1.0 && r.rms > 0.0005, k + ': sounds, and does not clip', r); }
  ok(errs.length === 0, 'no page errors', errs.slice(0, 3));
  console.log(pass + ' passed, ' + fail + ' failed'); await b.close(); process.exit(fail ? 1 : 0);
})();
