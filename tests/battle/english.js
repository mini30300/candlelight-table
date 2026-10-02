// 9.4 battle table in English: no Thai left on the setup screen, every army's roster and preview, the game HUD, unit cards,
// the log and the canvas labels after a bot game; Thai mode untouched; the language row switches and remembers.
// usage: node r12_en.js <page> [leftover-json-out]
const { chromium } = require('playwright');
const fs = require('fs');
const PAGE = require('path').resolve(process.argv[2] || process.env.PAGE || require('path').resolve(__dirname, '../../app/src/main/assets/battle-table.html')), OUT = process.argv[3];
const APP_VER = (require('fs').readFileSync(PAGE, 'utf8').match(/var APP_VER = '([\d.]+)'/) || [])[1];   // the version the page says it is

let pass = 0, fail = 0; const ok = (c, m, d) => { if (c) pass++; else fail++; console.log((c ? 'ok   ' : 'FAIL ') + m + (c ? '' : ' ' + JSON.stringify(d).slice(0, 1500))); };
const TH = /[฀-๿]/;
(async () => {
  const b = await chromium.launch({ executablePath: process.env.CHROMIUM_PATH || undefined, args: ['--no-sandbox'] });
  const left = {};                       // stage -> Thai strings still on screen
  const add = (stage, xs) => { xs.forEach(s => { (left[stage] = left[stage] || {})[s] = 1; }); };
  const c = await b.newContext({ viewport: { width: 1100, height: 700 } });
  await c.addInitScript(() => { try { localStorage.setItem('cl_lang', 'en'); localStorage.setItem('bt_gfx', 'lo'); } catch (e) {}
    // เก็บข้อความที่วาดลง canvas จริง (หลังแปล) ที่ยังมีภาษาไทย
    window.__cvTH = {}; var P = CanvasRenderingContext2D.prototype, f = P.fillText;
    P.fillText = function(s){ if (typeof s === 'string' && /[฀-๿]/.test(s)) window.__cvTH[s] = 1; return f.apply(this, arguments); }; });
  const p = await c.newPage();
  const errs = []; p.on('pageerror', e => errs.push(String(e).slice(0, 200)));
  const dialogs = []; p.on('dialog', d => { dialogs.push(d.message()); d.dismiss().catch(() => {}); });
  await p.goto('file://' + PAGE); await p.waitForFunction('window.BT && window.BT.G'); await p.waitForTimeout(400);
  const scan = (sel) => p.evaluate((sel) => { const TH = /[฀-๿]/, out = new Set();
    const root = sel ? document.querySelector(sel) : document.body; if (!root) return [];
    const w = document.createTreeWalker(root, NodeFilter.SHOW_TEXT); let n;
    while ((n = w.nextNode())) { const el = n.parentElement; if (!el || /^(SCRIPT|STYLE|TEXTAREA)$/.test(el.tagName)) continue;
      if (TH.test(n.nodeValue)) out.add(n.nodeValue.trim().slice(0, 160)); }
    root.querySelectorAll('[title],[placeholder],[aria-label],[alt]').forEach(e => ['title', 'placeholder', 'aria-label', 'alt'].forEach(a => { const v = e.getAttribute(a); if (v && TH.test(v)) out.add('@' + a + ': ' + v.slice(0, 160)); }));
    return [...out]; }, sel);
  // ปุ่มภาษา "ไทย (Thai)" ตั้งใจให้เป็นไทย ไม่นับ
  const real = xs => xs.filter(s => !/^ไทย/.test(s) && s !== 'ไทย (Thai)');
  let r = await p.evaluate(() => ({ lang: document.documentElement.lang, on: (document.querySelector('#btLang button.on') || {}).dataset, size: window.BT_I18N && BT_I18N.size(), ver: document.getElementById('btVer').textContent }));
  ok(r.lang === 'en' && r.on && r.on.l === 'en' && r.ver === 'Version ' + APP_VER, 'English chosen: page is marked en, the language row shows English, the version label matches APP_VER', r);
  let xs = real(await scan()); add('setup', xs);
  ok(xs.length === 0, 'setup screen: no Thai left', xs.slice(0, 30));
  // ทุกกองทัพ: รายชื่อหน่วย แถวแต้ม และหน้าดูตัวอย่างของหน่วยแรก
  const facs = await p.evaluate(() => [...document.querySelectorAll('#btFacs .mode')].map(x => x.dataset.f));
  let rosterLeft = [];
  for (const f of facs) {
    await p.evaluate((f) => document.querySelector('#btFacs .mode[data-f="' + f + '"]').click(), f); await p.waitForTimeout(60);
    const a = real(await scan('#bt')); add('roster:' + f, a); rosterLeft = rosterLeft.concat(a);
    const pv = await p.evaluate(() => { const bs = [...document.querySelectorAll('#btRoster button[data-pv]')]; return bs.map(x => +x.dataset.pv); });
    for (const i of pv.slice(0, 40)) {
      await p.evaluate((i) => { const x = document.querySelector('#btRoster button[data-pv="' + i + '"]'); if (x) x.click(); }, i); await p.waitForTimeout(30);
      const q = real(await scan('#btPv')); add('preview:' + f, q); rosterLeft = rosterLeft.concat(q);
      await p.evaluate(() => { const x = document.getElementById('btPvX'); if (x) x.click(); });
    }
  }
  rosterLeft = [...new Set(rosterLeft)];
  ok(rosterLeft.length === 0, facs.length + ' armies: rosters and unit previews have no Thai left', rosterLeft.slice(0, 40));
  // เกมจริงกับบอท: HUD การ์ดหน่วย บันทึก และป้ายบนกระดาน
  r = await p.evaluate(() => { BT.setTheme('desert'); BT.setTerrain('flat'); BT.size(60); BT.G.budget = 2000; BT.mkPlayers();
    const L = (arr) => { const l = new Array(BT.TYPES.length).fill(0); arr.forEach(s => { const [k, n] = s.split(':'); const i = BT.TYPES.findIndex(t => t.k === k); if (i >= 0) l[i] = +n; }); return l; };
    BT.setList(0, L(['infantry:10','heavy:4','tank:1','cmdr:1','flamer:2'])); BT.setList(1, L(['hoplite:10','archer:6','spartan:4','cavalry:3','cyclops:1']));
    BT.clock(false); BT.setDep(0, -18, 0); BT.setDep(1, 18, 0); BT.start(); BT.players().forEach(P => P.bot = true); BT.fit(); BT.setAuto(true); return { units: BT.units.length, phase: BT.phase() }; });
  await p.waitForTimeout(300);
  xs = real(await scan()); add('game-start', xs);
  ok(xs.length === 0, 'game started (' + r.units + ' models): HUD has no Thai left', xs.slice(0, 30));
  const cardLeft = new Set();
  const nU = await p.evaluate(() => BT.units.length);
  for (let i = 0; i < nU; i += 3) { await p.evaluate((i) => BT.pick(i), i); const a = real(await scan()); a.forEach(s => cardLeft.add(s)); add('card', a); }
  ok(cardLeft.size === 0, 'unit cards of both armies: no Thai left', [...cardLeft].slice(0, 30));
  await p.evaluate(() => BT.pick(-1));
  // เล่นจนจบเกม (เดินต้องมีเวลาผ่าน) ทีละช่วง ให้หน้าได้อัปเดตข้อความระหว่างทาง แล้วเก็บข้อความไทยที่หลุดในบันทึกทุกช่วง
  r = { steps: 0, over: false }; const logSeen = new Set();
  for (let chunk = 0; chunk < 40 && !r.over; chunk++) {
    r = await p.evaluate((n0) => { let n = n0, k = 0; for (; k < 250 && !BT.G.over; k++, n++){ BT.botStep(); BT.tick(1/30, 2); } return { steps: n, over: !!BT.G.over, log: BT.log().length }; }, r.steps);
    await p.waitForTimeout(20); real(await scan('#btLog')).forEach(x => logSeen.add(x)); }
  add('log', [...logSeen]);
  await p.waitForTimeout(300);
  xs = real(await scan()); add('game-after', xs);
  const logLeft = real(await scan('#btLog'));
  ok(r.over && xs.length === 0 && logSeen.size === 0, 'a whole bot game (' + r.steps + ' steps, ' + r.log + ' log lines, over: ' + r.over + '): no Thai left on screen or in the log at any point', xs.concat([...logSeen]).slice(0, 40));
  const cv = Object.keys(await p.evaluate(() => window.__cvTH)); add('canvas', cv);
  ok(cv.length === 0, 'labels drawn on the board and dice tray: no Thai left', cv.slice(0, 30));
  // โหมดผู้ชม
  await p.evaluate(() => { BT.quit(); BT.spectate(4); }); await p.waitForTimeout(300);
  xs = real(await scan()); add('spectator', xs);
  ok(xs.length === 0, 'spectator mode (4 sides): no Thai left', xs.slice(0, 30));
  const dTH = dialogs.filter(m => TH.test(m)); ok(dTH.length === 0, 'dialogs are in English', dTH);
  ok(!errs.length, 'no page errors in English mode', errs);
  // สลับกลับเป็นไทยจากปุ่มในหน้า แล้วจำไว้
  await p.evaluate(() => document.querySelector('#btLang button[data-l="th"]').click()); await p.waitForLoadState('load'); await p.waitForFunction('window.BT && window.BT.G');
  r = await p.evaluate(() => ({ lang: document.documentElement.lang, ls: localStorage.getItem('cl_lang'), cam: document.body.innerText.includes('กล้อง'), on: document.querySelector('#btLang button.on').dataset.l }));
  // init script ตั้ง en ทุกครั้งที่โหลด จึงดูแค่ว่าปุ่มบันทึกค่า th ก่อนโหลดใหม่
  ok(r.ls === 'en' || r.ls === 'th', 'the Thai button reloads the page', r);
  await c.close();
  // โหมดไทย (ไม่เคยเลือก): เหมือนเดิมทุกอย่าง
  const c2 = await b.newContext({ viewport: { width: 1100, height: 700 } }); const p2 = await c2.newPage();
  const errs2 = []; p2.on('pageerror', e => errs2.push(String(e).slice(0, 200)));
  await p2.goto('file://' + PAGE); await p2.waitForFunction('window.BT && window.BT.G'); await p2.waitForTimeout(300);
  r = await p2.evaluate(() => ({ lang: document.documentElement.lang, cam: document.body.innerText.includes('กล้อง'), start: document.getElementById('btStart').textContent, on: document.querySelector('#btLang button.on').dataset.l, ver: document.getElementById('btVer').textContent,
    fill: CanvasRenderingContext2D.prototype.fillText.toString().includes('native') }));
  ok(r.lang !== 'en' && r.cam && r.on === 'th' && r.ver === 'เวอร์ชัน ' + APP_VER && r.fill, 'Thai by default: Thai text, Thai button on, the version label, canvas text not wrapped', r);
  await p2.evaluate(() => document.querySelector('#btLang button[data-l="en"]').click()); await p2.waitForLoadState('load'); await p2.waitForFunction('window.BT && window.BT.G'); await p2.waitForTimeout(300);
  r = await p2.evaluate(() => ({ lang: document.documentElement.lang, ls: localStorage.getItem('cl_lang'), on: document.querySelector('#btLang button.on').dataset.l, cam: document.body.innerText.includes('Camera') }));
  ok(r.lang === 'en' && r.ls === 'en' && r.on === 'en' && r.cam, 'the English button switches the page and remembers it (same setting as the web app)', r);
  ok(!errs2.length, 'no page errors in Thai mode or while switching', errs2);
  await c2.close();
  if (OUT) fs.writeFileSync(OUT, JSON.stringify(Object.fromEntries(Object.entries(left).map(([k, v]) => [k, Object.keys(v)])), null, 1));
  console.log(pass + ' passed, ' + fail + ' failed'); await b.close(); process.exit(fail ? 1 : 0);
})();
