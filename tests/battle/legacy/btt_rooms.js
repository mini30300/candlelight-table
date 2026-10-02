// Rooms carry terrain/buildings/density (guests must build the same map), and BT.join(code, name) builds the right
// request. No server needed: fetch is stubbed and adoptRoom gets stub rooms.
const { chromium } = require('playwright');
const F = 'file://' + (process.env.PAGE || require('path').resolve(__dirname, '../../../app/src/main/assets/battle-table.html'));
// the rules version the page sends when it joins (read from the page, so a new round doesn't need this test edited)
const RULES_V = +(/var RULES_V = (\d+)/.exec(require('fs').readFileSync(F.replace('file://', ''), 'utf8')) || [])[1];
let pass = 0, fail = 0;
const ok = (c, m) => { c ? pass++ : fail++; console.log((c ? '  ok  ' : '  FAIL') + '  ' + m); };
const ROOM = (over) => Object.assign({ code: 'ABC12', ownerPid: 'p1', state: 'lobby', seats: 4, seq: 0, acts: [],
  setup: { theme: 'desert', seed: 4242, w: 60, d: 44, terrain: 'mountain', buildings: true, density: 1.75,
           mode: 'team', teams: 2, perTeam: 2, budget: 200, freeFire: false, clock: 0 },
  players: [{ pid: 'p1', team: 0, nm: 'เจ้าของ', owner: true }, { pid: 'p2', team: 1, nm: 'สมชาย' }] }, over || {});
const shot = (p) => p.evaluate(() => ({ fp: BT.props().map(o => o.kind + o.x.toFixed(3) + ',' + o.z.toFixed(3)).join(';'),
  h: [[-20, -10], [0, 0], [13, 7], [25, 18]].map(([x, z]) => BT.heightAt(x, z).toFixed(4)).join(','), seed: BT.seedOf(), theme: BT.themeOf(),
  terrain: BT.terrainOf(), b: BT.buildingsOf(), w: BT.table.w, d: BT.table.d }));
(async () => {
  const b = await chromium.launch({ executablePath: process.env.CHROMIUM_PATH || undefined, args: ['--no-sandbox'] });
  const open = async () => { const p = await b.newPage({ viewport: { width: 1366, height: 768 } }); p.errs = [];
    p.on('pageerror', e => p.errs.push(String(e))); await p.goto(F); await p.waitForFunction('window.BT && window.BT.G'); return p; };
  const p = await open(), q = await open();

  console.log('\n-- curSetup --');
  await p.click('#btTer .ter[data-r="mountain"]');
  await p.click('#btBld button[data-b="0"]');
  let cs = await p.evaluate(() => BT.curSetup());
  ok(cs.terrain === 'mountain' && cs.buildings === false && cs.density === 1, 'terrain + buildings off go into the setup: ' + JSON.stringify({ t: cs.terrain, b: cs.buildings, d: cs.density }));
  await p.click('#btBld button[data-b="1"]');
  await p.evaluate(() => { const s = document.getElementById('btDens'); s.value = 1.75; s.dispatchEvent(new Event('input')); });
  await p.click('#btModes .mode[data-g="spectator"]');
  cs = await p.evaluate(() => BT.curSetup());
  ok(cs.buildings === true && cs.density === 1.75, 'density from the slider: ' + cs.density);
  ok(cs.mode === 'team', 'spectator is offline-only, a room would get team (' + cs.mode + ')');
  await p.click('#btModes .mode[data-g="pve"]');

  console.log('\n-- adoptRoom: a guest builds the same map --');
  await q.evaluate((R) => BT.adoptRoom(R), ROOM());
  const g = await shot(q);
  ok(g.theme === 'desert' && g.terrain === 'mountain' && g.b.on === true && g.b.density === 1.75 && g.seed === 4242 && g.w === 60 && g.d === 44,
     `room settings adopted: ${g.theme}/${g.terrain}/${g.b.on ? 'on' : 'off'} x${g.b.density} #${g.seed} ${g.w}x${g.d}`);
  // the host's own device, built from its own controls
  await p.evaluate(() => { BT.setTheme('desert'); BT.size(60); });
  await p.evaluate(() => { BT.adoptRoom({ setup: Object.assign(BT.curSetup(), { seed: 4242, d: 44 }), players: [] }); });
  const h = await shot(p);
  ok(h.fp === g.fp && h.h === g.h, `host and guest have the same props (${g.fp.split(';').length}) and the same ground`);
  const ui = await q.evaluate(() => ({ ter: document.querySelector('#btTer .ter.on').dataset.r, map: document.querySelector('#btMaps .map.on').dataset.t,
    dens: document.getElementById('btDens').value, bld: document.querySelector('#btBld button.on').dataset.b,
    seed: document.getElementById('btSeed').textContent, size: document.getElementById('btSize').value }));
  ok(ui.ter === 'mountain' && ui.map === 'desert' && ui.dens === '1.75' && ui.bld === '1' && ui.seed === 'สนาม #4242' && ui.size === '60',
     'the setup screen shows the room\'s settings: ' + JSON.stringify(ui));
  for (const [k, v] of [['terrain', 'forest'], ['buildings', false], ['density', 0.5]]) {
    await q.evaluate(([R, k, v]) => { R.setup[k] = v; BT.adoptRoom(R); }, [ROOM(), k, v]);
    const s2 = await shot(q);
    ok(s2.fp !== g.fp, `a room that changes only ${k} rebuilds the map`);
  }
  // a room from a server that does not know the new fields yet
  const legacy = ROOM(); delete legacy.setup.terrain; delete legacy.setup.buildings; delete legacy.setup.density;
  await q.evaluate((R) => BT.adoptRoom(R), legacy);
  const l = await shot(q);
  await p.evaluate(() => { BT.setTerrain('hills'); BT.setBuildings(true, 1); BT.adoptRoom({ setup: Object.assign(BT.curSetup(), { seed: 4242, w: 60, d: 44, theme: 'desert' }), players: [] }); });
  const l2 = await shot(p);
  ok(l.terrain === 'hills' && l.b.on && l.b.density === 1 && l.fp === l2.fp, 'an old room without the fields gets hills / on / x1 — the table as it was');

  console.log('\n-- BT.join(code, name) --');
  const j = await open();
  await j.evaluate((R) => {
    window.calls = []; window.reply = R;
    window.fetch = (url, opt) => { calls.push({ url, method: (opt && opt.method) || 'GET', body: opt && opt.body ? JSON.parse(opt.body) : null });
      const bad = /ZZZZZ/.test(url);
      const body = bad ? { error: 'ไม่พบห้อง ZZZZZ' } : /\/join$/.test(url) ? { pid: 'p2', room: reply } : Object.assign({}, reply, { acts: [] });
      return Promise.resolve({ ok: !bad, status: bad ? 404 : 200, json: () => Promise.resolve(body) }); };
    BT.setServer('https://stub.test');
  }, ROOM());
  await j.click('#btModes .mode[data-g="spectator"]');     // the join row must work from any mode
  const r1 = await j.evaluate(() => BT.join('zz', 'x'));
  const n1 = await j.evaluate(() => ({ note: document.getElementById('btNetNote').textContent, calls: calls.length, vis: !document.getElementById('btNetBox').classList.contains('hide') }));
  ok(r1 === false && /5 ตัว/.test(n1.note) && n1.calls === 0 && n1.vis, 'a short code is refused before any request, and the note is visible: ' + n1.note);
  const r2 = await j.evaluate(() => BT.join('zzzzz', 'x'));
  const n2 = await j.evaluate(() => ({ note: document.getElementById('btNetNote').textContent, setup: !document.getElementById('scSetup').classList.contains('hide'), on: BT.NET.on }));
  ok(r2 === false && /ไม่พบห้อง ZZZZZ/.test(n2.note) && n2.setup && !n2.on, 'an unknown code resolves false and says why: ' + n2.note);
  await j.evaluate(() => { calls.length = 0; });
  const r3 = await j.evaluate(() => BT.join(' abc-12 ', '  สมชาย  '));
  const c = await j.evaluate(() => calls[0]);
  ok(r3 === true, 'a good code resolves true');
  ok(c && c.url === 'https://stub.test/api/bt/rooms/ABC12/join' && c.method === 'POST' && c.body && c.body.nm === 'สมชาย' && c.body.v === RULES_V && Object.keys(c.body).length === 2,
     'request: ' + (c ? c.method + ' ' + c.url + ' ' + JSON.stringify(c.body) : 'none'));
  const st = await j.evaluate(() => ({ on: BT.NET.on, code: BT.NET.code, pid: BT.NET.pid, lobby: !document.getElementById('scLobby').classList.contains('hide'),
    name: document.getElementById('btName').value, card: document.getElementById('btRoomCard').textContent, terrain: BT.terrainOf(), mode: BT.G.mode }));
  ok(st.on && st.code === 'ABC12' && st.pid === 'p2' && st.lobby, `in the room: ${st.code} as ${st.pid}, lobby showing`);
  ok(st.name === 'สมชาย', 'the name is kept for the lobby and later rooms');
  ok(st.terrain === 'mountain' && /สูง/.test(st.card) && /สิ่งก่อสร้าง ×1.75/.test(st.card) && st.mode === 'team', 'the lobby card shows the room\'s terrain and buildings: ' + st.card.replace(/\s+/g, ' ').slice(0, 120));
  await j.waitForTimeout(1700);
  const poll = await j.evaluate(() => calls.filter(x => x.method === 'GET').map(x => x.url));
  ok(poll.length >= 1 && /\/api\/bt\/rooms\/ABC12\?since=0&pid=p2$/.test(poll[0]), 'then it polls the room: ' + poll[0]);

  console.log('\n-- hosting sends the new fields --');
  await j.evaluate(() => { BT.quit(); calls.length = 0; BT.setTerrain('forest'); BT.setBuildings(false); });
  await j.click('#btModes .mode[data-g="pve"]');
  await j.click('#btHost'); await j.waitForTimeout(200);
  const host = await j.evaluate(() => calls.find(x => x.method === 'POST'));
  ok(host && host.url === 'https://stub.test/api/bt/rooms' && host.body.setup.terrain === 'forest' && host.body.setup.buildings === false && host.body.setup.density === 1.75,
     'POST /api/bt/rooms setup: ' + (host ? JSON.stringify({ terrain: host.body.setup.terrain, buildings: host.body.setup.buildings, density: host.body.setup.density }) : 'none'));

  for (const x of [p, q, j]) ok(x.errs.length === 0, x.errs.length ? 'JS ERRORS: ' + x.errs.join(' | ') : 'no JS errors');
  console.log(`\n${pass} passed, ${fail} failed`);
  await b.close(); process.exit(fail ? 1 : 0);
})().catch(e => { console.error(e); process.exit(1); });
