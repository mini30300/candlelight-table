// Round 5a UI: random army buttons and the unit preview window (desktop and phone), with screenshots
const { chromium } = require('playwright');
const OUT = process.argv[2] || require('path').join((process.env.TEST_OUT || require('os').tmpdir()), 'r5');
let pass = 0, fail = 0; const ok = (c, m) => { c ? pass++ : fail++; console.log((c ? 'ok   ' : 'FAIL ') + m); };
(async () => {
  const b = await chromium.launch({ executablePath: process.env.CHROMIUM_PATH || undefined, args: ['--no-sandbox'] });
  for (const vp of [{ w: 1366, h: 700, nm: 'desk' }, { w: 390, h: 800, nm: 'phone' }]){
    const p = await b.newPage({ viewport: { width: vp.w, height: vp.h }, deviceScaleFactor: vp.nm === 'phone' ? 2 : 1 });
    const errs = []; p.on('pageerror', e => errs.push(String(e)));
    await p.goto('file://' + (process.env.PAGE || require('path').resolve(__dirname, '../../../app/src/main/assets/battle-table.html'))); await p.waitForFunction('window.BT && window.BT.G');
    await p.click('#btNext'); await p.waitForTimeout(200);
    // random units in the chosen army
    await p.click('#btFacs .mode[data-f="md"]'); await p.waitForTimeout(100);
    await p.click('#btRandU'); await p.waitForTimeout(100);
    const r1 = await p.evaluate(() => { const P = BT.players()[BT.G.cur || 0], L = P.list, T = BT.TYPES; let pts = 0, fac = {}; L.forEach((n, i) => { if (n){ pts += n*T[i].pts; fac[T[i].fac] = 1; } });
      return { pts, facs: Object.keys(fac), used: document.getElementById('btUsedV').textContent }; });
    ok(r1.facs.length === 1 && r1.facs[0] === 'md' && r1.pts > 0, vp.nm + ': random units stay in the chosen army ' + JSON.stringify(r1));
    const share = +r1.used.split('/')[1];
    ok(r1.pts <= share && r1.pts >= share*0.6, vp.nm + ': within the budget and most of it spent (' + r1.pts + ' of ' + share + ')');
    const seen = {};
    for (let k = 0; k < 12; k++){ await p.click('#btRandA'); const f = await p.evaluate(() => { const P = BT.players()[BT.G.cur || 0]; return P.fac; }); seen[f] = 1; }
    ok(Object.keys(seen).length >= 3, vp.nm + ': "random whole army" picks different armies (' + Object.keys(seen).join(',') + ')');
    const onBtn = await p.evaluate(() => { const on = document.querySelector('#btFacs .mode.on'); return on && on.dataset.f; });
    const fac = await p.evaluate(() => BT.players()[BT.G.cur || 0].fac);
    ok(onBtn === fac, vp.nm + ': the army picker follows the random army (' + onBtn + ')');
    await p.screenshot({ path: `${OUT}/ui_${vp.nm}_roster.png`, fullPage: false });
    // the preview of a unit with variants (men-at-arms) and one without
    await p.click('#btFacs .mode[data-f="md"]'); await p.waitForTimeout(100);
    const pvBtn = await p.$('#btRoster button.pv'); ok(!!pvBtn, vp.nm + ': each unit row has a preview button');
    const maaIdx = await p.evaluate(() => BT.TYPES.findIndex(t => t.k === 'maa'));
    await p.click(`#btRoster button.pv[data-pv="${maaIdx}"]`); await p.waitForTimeout(400);
    const st = await p.evaluate(() => ({ open: !document.getElementById('btPv').classList.contains('hide'), name: document.getElementById('btPvN').textContent,
      variants: document.querySelectorAll('#btPvV button').length, focus: document.activeElement && document.activeElement.id,
      box: (() => { const r = document.querySelector('#btPv .pvbox').getBoundingClientRect(); return [r.left, r.top, r.width, r.height].map(Math.round); })() }));
    ok(st.open && st.name === 'อัศวินเกราะ' && st.variants === 5 && st.focus === 'btPvX', vp.nm + ': the preview opens on its unit with its 5 looks, focus on close ' + JSON.stringify(st));
    ok(st.box[0] >= 0 && st.box[1] >= 0 && st.box[0] + st.box[2] <= vp.w && st.box[1] + st.box[3] <= vp.h, vp.nm + ': the window fits the screen ' + JSON.stringify(st.box));
    // the picture changes as it turns (spinning) and is not blank
    const px = async () => p.evaluate(() => { const c = document.getElementById('btPvC'), g = c.getContext('2d'), d = g.getImageData(0, 0, c.width, c.height).data; let lit = 0, sum = 0;
      for (let i = 0; i < d.length; i += 16){ const v = d[i] + d[i+1] + d[i+2]; if (v > 150) lit++; sum = (sum*31 + v) % 1000003; } return { lit, sum }; });
    const a = await px(); await p.waitForTimeout(500); const bb = await px();
    ok(a.lit > 200 && a.sum !== bb.sum, vp.nm + ': the figure is drawn and turning (' + a.lit + ' lit samples)');
    await p.screenshot({ path: `${OUT}/ui_${vp.nm}_preview.png` });
    await p.click('#btPvV button[data-j="3"]'); await p.waitForTimeout(300);
    await p.screenshot({ path: `${OUT}/ui_${vp.nm}_preview_axe.png` });
    await p.keyboard.press('Escape'); await p.waitForTimeout(100);
    const closed = await p.evaluate(() => document.getElementById('btPv').classList.contains('hide'));
    ok(closed, vp.nm + ': Escape closes it');
    // a mounted unit and a big creature fit their window
    for (const k of ['mknight', 'dragon']){
      const idx = await p.evaluate(k => BT.TYPES.findIndex(t => t.k === k), k);
      await p.click(`#btRoster button.pv[data-pv="${idx}"]`); await p.waitForTimeout(300);
      await p.screenshot({ path: `${OUT}/ui_${vp.nm}_preview_${k}.png` });
      await p.click('#btPvX'); await p.waitForTimeout(100); }
    ok(errs.length === 0, vp.nm + ': no page errors' + (errs.length ? ': ' + errs.slice(0, 2).join(' | ') : ''));
    await p.close();
  }
  console.log(pass + ' passed, ' + fail + ' failed'); await b.close(); process.exit(fail ? 1 : 0);
})().catch(e => { console.error('THREW', e); process.exit(1); });
