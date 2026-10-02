// 9.2 lowest graphics ("ต่ำสุด"): the button, fewer facets than "ต่ำ", the step down when a phone stays slow, the first-run guess from memory
const { chromium } = require('playwright');
const PAGE = require('path').resolve(process.argv[2] || process.env.PAGE || require('path').resolve(__dirname, '../../app/src/main/assets/battle-table.html')), SHOT = process.argv[3];
const APP_VER = (require('fs').readFileSync(PAGE, 'utf8').match(/var APP_VER = '([\d.]+)'/) || [])[1];   // the version the page says it is

let pass = 0, fail = 0; const ok = (c, m, d) => { if (c) pass++; else fail++; console.log((c ? 'ok   ' : 'FAIL ') + m + (c ? '' : ' ' + JSON.stringify(d))); };
(async () => {
  const b = await chromium.launch({ executablePath: process.env.CHROMIUM_PATH || undefined, args: ['--no-sandbox'] });
  const c = await b.newContext({ viewport: { width: 900, height: 420 }, deviceScaleFactor: 2 }); await c.addInitScript(() => { try { localStorage.setItem('bt_secret_ta', '1'); } catch (e) {} }); const p = await c.newPage();
  const errs = []; p.on('pageerror', e => errs.push(String(e).slice(0, 200)));
  await p.goto('file://' + PAGE); await p.waitForFunction('window.BT && window.BT.G'); await p.waitForTimeout(300);
  let r = await p.evaluate(() => ({ btn: !!document.querySelector('#btGfx button[data-g="min"]'), g: BT.gfx().g, ver: document.getElementById('btVer').textContent }));
  ok(r.btn && r.g === 'mid' && r.ver === 'เวอร์ชัน ' + APP_VER, 'the graphics row has a lowest button; a roomy machine still starts on medium; the version label matches APP_VER', r);
  r = await p.evaluate(() => { BT.setTheme('desert'); BT.setTerrain('flat'); BT.size(94); BT.setBuildings(true, 1); BT.G.budget = 10000; BT.mkPlayers();
    const L = (arr) => { const l = new Array(BT.TYPES.length).fill(0); arr.forEach(s => { const [k, n] = s.split(':'); l[BT.TYPES.findIndex(t => t.k === k)] = +n; }); return l; };
    BT.setList(0, L(['infantry:24','heavy:8','enemy:10','mech:3','tank:2','flamer:4','cmdr:2','hmg:4'])); BT.setList(1, L(['hoplite:24','archer:10','spartan:6','cavalry:6','centaur:2','achil:1','cyclops:2']));
    BT.setDep(0, -30, 0); BT.setDep(1, 30, 0); BT.start(); BT.fit();
    const n = (g) => { BT.gfx(g); for (let i=0;i<6;i++) BT.draw(); return BT.faces(); };
    return { lo: n('lo'), min: n('min'), units: BT.units.length }; });
  ok(r.min < r.lo * 0.7, 'the lowest level draws far fewer facets than low for the same ' + r.units + ' models', r);
  {
    const shot = SHOT ? await p.screenshot({ path: SHOT }) : null; }
  r = await p.evaluate(() => { document.querySelector('#btGfx button[data-g="min"]').click(); return { g: BT.gfx().g, ls: localStorage.getItem('bt_gfx'), on: document.querySelector('#btGfx button[data-g="min"]').getAttribute('aria-pressed') }; });
  ok(r.g === 'min' && r.ls === 'min' && r.on === 'true', 'tapping it switches, marks it and remembers it', r);
  r = await p.evaluate(() => { BT.gfx('lo'); let i = 0; for (; i < 400 && BT.gfx().g === 'lo'; i++) BT.adapt(90);
    return { g: BT.gfx().g, frames: i, pop: (document.getElementById('btPop') || document.body).textContent.includes('ลดกราฟิกเป็น') }; });
  ok(r.g === 'min' && r.frames > 40 && r.pop, 'a phone that stays slow at the smallest scale is stepped down from low to lowest and told so', r);
  r = await p.evaluate(() => { BT.gfx('min'); for (let i = 0; i < 300; i++) BT.adapt(200); return BT.gfx().g; });
  ok(r === 'min', 'it never steps below the lowest', r);
  r = await p.evaluate(() => { BT.quit(); const G = BT.G; G.mode = 'spectator'; G.budget = 1000; BT.mkPlayers();
    const L = new Array(BT.TYPES.length).fill(0); L[BT.TYPES.findIndex(t => t.k === 'gaunt')] = 40; BT.setList(0, L);
    return { start: document.getElementById('btStart').disabled, note: document.getElementById('btArmyNote').textContent }; });
  ok(!r.start && /เกินงบ/.test(r.note) && /400\/1500/.test(r.note), 'spectator mode is free play: 400 models on a 1,000-point budget still starts, 1,500 a side', r);
  r = await p.evaluate(() => { const L = new Array(BT.TYPES.length).fill(0); L[BT.TYPES.findIndex(t => t.k === 'tafw')] = 1; BT.setList(0, L);
    const i = BT.TYPES.findIndex(t => t.k === 'tagm'), plus = () => document.querySelector('#btRoster button[data-i="' + i + '"][data-v="1"]');
    if (!plus()) return { none: true }; plus().click(); plus().click(); return { n: BT.players()[0].list[i] }; });
  ok(r.n === 2, 'spectator mode takes the hidden unit more than once', r);
  r = await p.evaluate(() => { const G = BT.G; G.mode = 'pvp'; BT.mkPlayers(); const L = new Array(BT.TYPES.length).fill(0); L[BT.TYPES.findIndex(t => t.k === 'gaunt')] = 40; BT.setList(0, L);
    const a = { start: document.getElementById('btStart').disabled, note: document.getElementById('btArmyNote').textContent };
    L.fill(0); L[BT.TYPES.findIndex(t => t.k === 'tafw')] = 1; BT.setList(0, L);
    const i = BT.TYPES.findIndex(t => t.k === 'tagm'), plus = () => document.querySelector('#btRoster button[data-i="' + i + '"][data-v="1"]');
    plus().click(); a.dis = plus().disabled; a.n = BT.players()[0].list[i]; return a; });
  ok(r.start && /เกินงบ/.test(r.note) && r.dis && r.n === 1, 'a normal game keeps its limits: over the budget cannot start, one hidden unit', r);
  const c2 = await b.newContext({ viewport: { width: 900, height: 420 } }); await c2.addInitScript(() => Object.defineProperty(navigator, 'deviceMemory', { get: () => 2 }));
  const p2 = await c2.newPage(); await p2.goto('file://' + PAGE); await p2.waitForFunction('window.BT && window.BT.G');
  ok(await p2.evaluate(() => BT.gfx().g) === 'min', 'a 2 GB phone that never chose starts on the lowest level');
  await c2.close();
  ok(!errs.length, 'no page errors', errs);
  console.log(pass + ' passed, ' + fail + ' failed'); await b.close(); process.exit(fail ? 1 : 0);
})();
