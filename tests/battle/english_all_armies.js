// English mode across every army: bot games (one of each unit) collect any Thai left in the log, HUD or cards
const { chromium } = require('playwright');
const fs = require('fs');
const PAGE = require('path').resolve(process.argv[2] || process.env.PAGE || require('path').resolve(__dirname, '../../app/src/main/assets/battle-table.html')), OUT = process.argv[3];
(async () => {
  const b = await chromium.launch({ executablePath: process.env.CHROMIUM_PATH || undefined, args: ['--no-sandbox'] });
  const c = await b.newContext({ viewport: { width: 1100, height: 700 } });
  await c.addInitScript(() => { try { localStorage.setItem('cl_lang', 'en'); localStorage.setItem('bt_gfx', 'min'); localStorage.setItem('bt_secret_ta', '1'); } catch (e) {} });
  const p = await c.newPage(); const errs = []; p.on('pageerror', e => errs.push(String(e).slice(0, 200)));
  await p.goto('file://' + PAGE); await p.waitForFunction('window.BT && window.BT.G'); await p.waitForTimeout(300);
  const facs = await p.evaluate(() => [...new Set(BT.TYPES.map(t => t.fac))].filter(Boolean));
  const scan = () => p.evaluate(() => { const TH = /[฀-๿]/, out = new Set(); const w = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT); let n;
    while ((n = w.nextNode())) { const el = n.parentElement; if (!el || /^(SCRIPT|STYLE|TEXTAREA)$/.test(el.tagName)) continue; const v = n.nodeValue.trim(); if (TH.test(v) && !/^ไทย/.test(v)) out.add(v.slice(0, 200)); }
    document.querySelectorAll('[title],[aria-label]').forEach(e => ['title', 'aria-label'].forEach(a => { const v = e.getAttribute(a); if (v && TH.test(v)) out.add('@' + v.slice(0, 200)); }));
    return [...out]; });
  const left = new Set(), games = [];
  for (let i = 0; i < facs.length; i += 2) {
    const A = facs[i], B = facs[(i + 1) % facs.length];
    await p.evaluate(([A, B, seed]) => { BT.clock(false); BT.quit(); BT.setTerrain('hills'); BT.seed(seed); BT.size(70); BT.G.budget = 40000; BT.G.goal = 'kill'; BT.mkPlayers();
      const L = f => { const l = new Array(BT.TYPES.length).fill(0); BT.TYPES.forEach((t, j) => { if (t.fac === f && t.pts < 900) l[j] = 1; }); return l; };
      BT.setList(0, L(A)); BT.setList(1, L(B)); BT.setDep(0, -24, 0); BT.setDep(1, 24, 0); BT.start(); BT.players().forEach(P => P.bot = true); BT.setAuto(true); }, [A, B, 7 + i]);
    let r = { k: 0, over: false };
    for (let ch = 0; ch < 40 && !r.over; ch++) {
      r = await p.evaluate((k0) => { let k = k0, j = 0; for (; j < 200 && !BT.G.over; j++, k++){ BT.botStep(); BT.tick(1/30, 2); } return { k, over: !!BT.G.over, n: BT.units.length, log: BT.log().length }; }, r.k);
      await p.waitForTimeout(15); (await scan()).forEach(x => left.add(x));
      if (ch % 5 === 0) { await p.evaluate(() => { const n = BT.units.length; for (let q = 0; q < n; q += 7) BT.pick(q); }); await p.waitForTimeout(15); (await scan()).forEach(x => left.add(x)); }
    }
    games.push(A + ' vs ' + B + ': ' + r.k + ' steps, ' + r.log + ' log lines, over ' + r.over);
  }
  console.log(games.join('\n'));
  console.log('Thai left:', left.size); [...left].slice(0, 80).forEach(x => console.log('  ', x));
  console.log('page errors:', errs.length, errs.slice(0, 3));
  if (OUT) fs.writeFileSync(OUT, JSON.stringify([...left], null, 0));
  await b.close(); process.exit(left.size || errs.length ? 1 : 0);
})();
