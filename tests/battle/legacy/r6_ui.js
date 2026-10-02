// Round 6 screens: game size ladder and presets, goal and rounds, the secret hero, skins, a kill-mode start
const { chromium } = require('playwright');
const PAGE = process.argv[2] || process.env.PAGE || require('path').resolve(__dirname, '../../../app/src/main/assets/battle-table.html'), OUT = process.argv[3] || (process.env.TEST_OUT || require('os').tmpdir());
let pass = 0, fail = 0; const ok = (c, m, x) => { if (c){ pass++; console.log('ok  ', m); } else { fail++; console.log('FAIL', m, x !== undefined ? JSON.stringify(x) : ''); } };
(async () => {
  const b = await chromium.launch({ executablePath: process.env.CHROMIUM_PATH || undefined, args: ['--no-sandbox'] });
  for (const vp of [{ width: 1280, height: 860, nm: 'desk' }, { width: 390, height: 844, nm: 'phone' }]){
    const p = await b.newPage({ viewport: { width: vp.width, height: vp.height } });
    const errs = []; p.on('pageerror', e => errs.push(String(e)));
    await p.goto('file://' + PAGE); await p.waitForFunction('window.BT && window.BT.G'); await p.waitForTimeout(300);
    await p.evaluate(() => { try { localStorage.removeItem('bt_secret'); } catch (e) {} });
    await p.click('#btPtsPick button[data-p="40000"]');
    let r = await p.evaluate(() => ({ b: BT.G.budget, lab: document.getElementById('btSpecPtsV').textContent }));
    ok(r.b === 40000 && r.lab === '40,000', vp.nm + ': the 40,000 preset sets the game size', r);
    await p.evaluate(() => { const el = document.getElementById('btSpecPts'); el.value = 0; el.dispatchEvent(new Event('input')); });
    r = await p.evaluate(() => BT.G.budget); ok(r === 200, vp.nm + ': the slider bottom is 200', r);
    await p.evaluate(() => { const el = document.getElementById('btSpecPts'); el.value = el.max; el.dispatchEvent(new Event('input')); });
    r = await p.evaluate(() => BT.G.budget); ok(r === 40000, vp.nm + ': the slider top is 40,000', r);
    await p.click('#btPtsPick button[data-p="2000"]');
    await p.click('#btGoal button[data-g="kill"]');
    r = await p.evaluate(() => ({ g: BT.G.goal, hid: document.getElementById('btRoundsRow').classList.contains('hide') }));
    ok(r.g === 'kill' && r.hid, vp.nm + ': kill mode hides the rounds', r);
    await p.click('#btGoal button[data-g="obj"]');
    await p.evaluate(() => { const el = document.getElementById('btRounds'); el.value = 7; el.dispatchEvent(new Event('input')); });
    r = await p.evaluate(() => ({ g: BT.G.goal, n: BT.G.rounds, lab: document.getElementById('btRoundsV').textContent }));
    ok(r.g === 'obj' && r.n === 7 && r.lab === '7 รอบ', vp.nm + ': objectives with 7 rounds', r);
    const wide = await p.evaluate(() => document.documentElement.scrollWidth - window.innerWidth);
    ok(wide <= 1, vp.nm + ': the setup screen does not scroll sideways', wide);
    await p.screenshot({ path: OUT + '/r6_setup_' + vp.nm + '.png', fullPage: true });
    await p.click('#btNext'); await p.waitForTimeout(200);
    // the hidden hero's unlock
    r = await p.evaluate(() => document.getElementById('btRoster').textContent.includes('ดูม'));
    ok(!r, vp.nm + ': the secret hero is hidden at first');
    for (let i = 0; i < 7; i++) await p.click('#btFacsH');
    r = await p.evaluate(() => { const first = document.querySelector('#btRoster .unit'); return first && first.textContent; });
    ok(r && r.includes('ดูม') && r.includes('ไม่นับแต้ม'), vp.nm + ': after the unlock ดูม is at the top of the roster', r && r.slice(0, 60));
    const di = await p.evaluate(() => BT.TYPES.findIndex(t => t.k === 'doom'));
    const before = await p.evaluate(() => document.getElementById('btUsedV').textContent);
    await p.click('#btRoster button[data-i="' + di + '"][data-v="1"]');
    r = await p.evaluate((di) => ({ n: BT.G.players[BT.G.cur].list[di], used: document.getElementById('btUsedV').textContent,
      dis: document.querySelector('#btRoster button[data-i="' + di + '"][data-v="1"]').disabled }), di);
    ok(r.n === 1 && r.used === before && r.dis, vp.nm + ': ดูม joins free of the budget, one per player', Object.assign({ before }, r));
    // another army keeps him
    await p.click('#btFacs .mode[data-f="nr"]');
    r = await p.evaluate((di) => BT.G.players[BT.G.cur].list[di], di); ok(r === 1, vp.nm + ': changing army keeps ดูม', r);
    // Loki's skin
    const li = await p.evaluate(() => BT.TYPES.findIndex(t => t.k === 'loki'));
    await p.click('#btRoster button[data-pv="' + li + '"]'); await p.waitForTimeout(150);
    r = await p.evaluate(() => Array.from(document.querySelectorAll('#btPvV button[data-sk]')).map(b => b.textContent));
    ok(r.length === 2 && r[1] === 'ร่างหญิง', vp.nm + ': the preview offers Loki\'s skins', r);
    await p.click('#btPvV button[data-sk="1"]'); await p.waitForTimeout(150);
    r = await p.evaluate(() => ({ sk: BT.G.players[BT.G.cur].skin, row: document.getElementById('btRoster').textContent.includes('สกินร่างหญิง') }));
    ok(r.sk && r.sk.loki === 1 && r.row, vp.nm + ': picking the skin marks the roster', r);
    await p.screenshot({ path: OUT + '/r6_preview_' + vp.nm + '.png' });
    await p.keyboard.press('Escape');
    // the unlock again hides it, but the one already in the list stays shown
    for (let i = 0; i < 7; i++) await p.click('#btFacsH');
    r = await p.evaluate(() => document.getElementById('btRoster').textContent.includes('ดูม'));
    ok(r, vp.nm + ': a ดูม already in the list stays after hiding the secret');
    ok(errs.length === 0, vp.nm + ': no page errors', errs.slice(0, 3));
    await p.close();
  }
  // a kill-mode game: no objectives, no round limit shown, bots fight to the end
  const p = await b.newPage({ viewport: { width: 1100, height: 760 } });
  const errs = []; p.on('pageerror', e => errs.push(String(e)));
  await p.goto('file://' + PAGE); await p.waitForFunction('window.BT && window.BT.G');
  const r = await p.evaluate(() => { BT.setTerrain('flat'); BT.size(48); BT.G.goal = 'kill'; BT.G.budget = 500; BT.mkPlayers();
    BT.players().forEach(P => P.bot = true); BT.setDep(0, -16, 0); BT.setDep(1, 16, 0);
    const L = (arr) => { const l = new Array(BT.TYPES.length).fill(0); arr.forEach(s => { const [k, n] = s.split(':'); l[BT.TYPES.findIndex(t => t.k === k)] = +n; }); return l; };
    BT.setList(0, L(['infantry:2', 'heavy:1'])); BT.setList(1, L(['hoplite:2', 'archer:1']));
    BT.start(); BT.clock(false);
    const obj = BT.obj().length, turnTxt = document.getElementById('btTurn').textContent;
    let k = 0; while (!BT.G.over && k < 6000){ BT.botStep(); BT.tick(1/10, 1); k++; }
    return { obj, turnTxt: turnTxt.slice(0, 60), over: BT.G.over, round: BT.G.round, k };
  });
  ok(r.obj === 0, 'kill mode places no objectives', r);
  ok(!/รอบ 1\//.test(r.turnTxt), 'kill mode shows no round limit', r.turnTxt);
  ok(r.over, 'kill mode plays to the end', r);
  ok(errs.length === 0, 'kill game: no page errors', errs.slice(0, 3));
  console.log(pass + ' passed, ' + fail + ' failed');
  await b.close(); process.exit(fail ? 1 : 0);
})();
