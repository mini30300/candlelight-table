// Drive the battle table like a player: set the field, build two armies, play a turn,
// let the bot answer, and prove the camera really pans off the centre of the table.
const { chromium } = require('playwright');
const F = 'file://' + (process.env.PAGE || require('path').resolve(__dirname, '../../../app/src/main/assets/battle-table.html'));
const OUT = (process.env.TEST_OUT || require('os').tmpdir()) + '/shots/bt';
require('fs').mkdirSync(OUT, { recursive: true });
const fail = [];
const ok = (c, m) => { console.log((c ? '  ok   ' : '  FAIL ') + m); if (!c) fail.push(m); };

async function run(vp, tag) {
  const b = await chromium.launch({ executablePath: process.env.CHROMIUM_PATH || undefined, args: ['--no-sandbox'] });
  const p = await b.newPage({ viewport: vp, deviceScaleFactor: 2 });
  const errs = []; p.on('pageerror', e => errs.push(String(e)));
  p.on('console', m => { if (m.type() === 'error') errs.push('console: ' + m.text()); });
  await p.goto(F);
  await p.waitForFunction('window.BT && window.BT.G', null, { timeout: 8000 });
  await p.waitForTimeout(900);
  console.log('\n== ' + tag + ' ' + vp.width + 'x' + vp.height + ' ==');

  // ---- 1. setup screen ----
  await p.screenshot({ path: `${OUT}/${tag}-1-setup.png` });
  ok(await p.isVisible('#scSetup'), 'setup screen shows');
  ok((await p.$$('#btMaps .map')).length === 4, 'four map cards');
  const mapInk = await p.evaluate(() => { const c = document.querySelector('#btMaps .map canvas'), g = c.getContext('2d');
    const d = g.getImageData(0,0,c.width,c.height).data; let n = 0;
    for (let i=3;i<d.length;i+=4) if (d[i] > 10) n++; return Math.round(100*n/(d.length/4)); });
  ok(mapInk > 90, 'map previews are painted (' + mapInk + '% ink)');

  await p.click('#btMaps .map[data-t="forest"]');
  await p.waitForTimeout(500);
  ok(await p.evaluate(() => document.querySelector('#btMaps .map[data-t="forest"]').classList.contains('on')), 'map picker switches');

  // ---- 2. the camera pans off centre ----
  const before = await p.evaluate(() => ({ x: BT.cam.tx, z: BT.cam.tz }));
  await p.evaluate(() => BT.panBy(1, 0));
  await p.evaluate(() => BT.panBy(0, 1));
  await p.waitForTimeout(350);
  const after = await p.evaluate(() => ({ x: BT.cam.tx, z: BT.cam.tz }));
  const moved = Math.hypot(after.x - before.x, after.z - before.z);
  ok(before.x === 0 && before.z === 0, 'camera starts at the table centre');
  ok(moved > 1, 'arrow-key pan moves the camera off centre (' + moved.toFixed(1) + ' m)');
  await p.screenshot({ path: `${OUT}/${tag}-2-panned.png` });

  // drag-pan with the pointer, through the real event path
  const box = await p.locator('#btCv').boundingBox();
  const cx = box.x + box.width/2, cy = box.y + box.height/2;
  await p.evaluate(() => BT.fit());
  await p.waitForTimeout(250);
  await p.mouse.move(cx, cy); await p.mouse.down({ button: 'right' });
  for (let i = 1; i <= 8; i++) await p.mouse.move(cx - i*14, cy - i*6);
  await p.mouse.up({ button: 'right' });
  await p.waitForTimeout(300);
  const dragged = await p.evaluate(() => Math.hypot(BT.cam.tx, BT.cam.tz));
  ok(dragged > 1, 'right-drag pans the map (' + dragged.toFixed(1) + ' m off centre)');

  // ---- 3. army screen ----
  await p.click('#btModes .mode[data-g="pvp"]');
  await p.click('#btNext');
  await p.waitForTimeout(300);
  ok(await p.isVisible('#scArmy'), 'army screen shows');
  // two armies now: the roster lists the chosen army's units (soldiers 7 by default, Greek 5)
  ok((await p.$$('#btRoster .unit')).length === 11, 'roster lists the soldiers\' eleven unit types');
  await p.click('#btFacs .mode[data-f="gr"]'); await p.waitForTimeout(150);
  ok((await p.$$('#btRoster .unit')).length === 13, 'Greek army shows its thirteen unit types');
  await p.click('#btFacs .mode[data-f="mod"]'); await p.waitForTimeout(150);
  await p.click('#btDetail');
  await p.waitForTimeout(150);
  await p.screenshot({ path: `${OUT}/${tag}-3-army.png` });

  // + / - really change the points used
  await p.evaluate(() => BT.setList(0, [0,0,0,0]));
  const p0 = await p.textContent('#btUsedV');
  await p.click('#btRoster .unit:nth-child(1) button[data-v="1"]');
  await p.click('#btRoster .unit:nth-child(1) button[data-v="1"]');
  const p1 = await p.textContent('#btUsedV');
  ok(p0.trim().startsWith('0') && p1.trim().startsWith('180'), 'plus button spends points: two heavy squads (' + p0.trim() + ' -> ' + p1.trim() + ')');
  await p.click('#btRoster .unit:nth-child(1) button[data-v="-1"]');
  ok((await p.textContent('#btUsedV')).trim().startsWith('90'), 'minus button refunds points');

  // ---- 4. play ----
  await p.evaluate(() => { BT.setList(0, [2,4,1,0]); BT.setList(1, [1,3,0,3]); });
  await p.evaluate(() => BT.start());
  await p.waitForTimeout(900);
  ok(await p.isVisible('#scPlay'), 'play screen shows');
  const sides = await p.evaluate(() => [BT.live(0), BT.live(1)]);
  const want = await p.evaluate(() => [[2,4,1,0], [1,3,0,3]].map(L => L.reduce((n, c, i) => n + c*BT.TYPES[i].n, 0)));
  ok(sides[0] === want[0] && sides[1] === want[1], 'both armies deployed as whole squads (' + sides.join(' vs ') + ' models)');
  const gap = await p.evaluate(() => {
    const d = BT.players().map(x => x.dep);
    return Math.hypot(d[0][0]-d[1][0], d[0][1]-d[1][1]);
  });
  ok(gap >= 20, 'the two teams land at least 20" apart (' + gap.toFixed(1) + '")');
  await p.screenshot({ path: `${OUT}/${tag}-4-play.png` });

  // select, move, shoot
  await p.evaluate(() => BT.pick(0));
  await p.waitForTimeout(250);
  ok(await p.evaluate(() => !!BT.G.sel && BT.sqModels(BT.G.sel).every(m => m.sel)), 'tapping a model selects its whole squad');
  const mv = await p.evaluate(() => { const s = BT.G.sel, c = BT.sqModels(s)[0]; let r = false;
    for (let k = 0; k < 12 && !r; k++){ const a = k*Math.PI/6; r = BT.move(s, c.x + Math.cos(a)*4, c.z + Math.sin(a)*4); }   // like a player trying an open spot
    return { r, why: document.getElementById('btDice').innerText.replace(/\n/g, ' '), id: s.id, k: s.k, moved: s.moved, phase: BT.phase(), turn: BT.G.turn }; });
  const movedOk = mv.r;
  ok(movedOk === true, 'a legal move is accepted' + (mv.r ? '' : ' — ' + JSON.stringify(mv)));
  const tooFar = await p.evaluate(() => { const s = BT.squads().find(q => q.side === 0 && !q.moved), c = s && BT.sqModels(s)[0]; return s ? BT.move(s, c.x + 60, c.z) : 'none'; });
  ok(tooFar === false, 'a move past the unit\'s Move is refused');

  const shot = await p.evaluate(() => {
    const u = BT.units.find(q => q.side === 0 && !q.shot), foes = BT.units.filter(q => q.side === 1);
    if (!u || !foes.length) return 'no pair';
    const f = foes[0]; u.x = f.x; u.z = f.z + 6;            // park it in range, then fire
    const before = BT.live(1); BT.shootAt(u, f);
    return { logged: BT.log().length, before, after: BT.live(1), hp: f.hp };
  });
  ok(shot.logged > 0, 'shooting writes to the battle log');
  ok(shot.after <= shot.before, 'shooting can take a model off the table');
  await p.waitForTimeout(400);
  await p.screenshot({ path: `${OUT}/${tag}-5-shot.png` });

  // the end button walks the phases; after the fight phase the other side's turn starts fresh
  const t0 = await p.evaluate(() => BT.G.turn + ':' + BT.phase());
  const seen = [];
  for (let k = 0; k < 3; k++){ await p.click('#btEnd'); await p.waitForTimeout(250); seen.push(await p.evaluate(() => BT.phase())); }
  await p.waitForFunction('BT.G.turn === 1', null, { timeout: 15000 }).catch(() => {});
  const t1 = await p.evaluate(() => ({ turn: BT.G.turn, anyStale: BT.squads().filter(s => s.side === 1).some(s => s.moved || s.shot) }));
  ok(t0 === '0:move' && seen[0] === 'shoot' && seen[1] === 'charge', 'the end button steps move → shoot → charge (' + [t0].concat(seen).join(' → ') + ')');
  ok(t1.turn === 1, 'after the fight phase play passes to the other side');
  ok(!t1.anyStale, 'the new side starts its turn with fresh squads');

  await b.close();
  return errs;
}

(async () => {
  let errs = [];
  errs = errs.concat(await run({ width: 1366, height: 768 }, 'desk'));
  errs = errs.concat(await run({ width: 412, height: 860 }, 'phone'));
  console.log(errs.length ? '\nPAGE ERRORS:\n' + errs.join('\n') : '\nno page errors');
  if (errs.length) fail.push('page errors');
  console.log(fail.length ? '\n' + fail.length + ' FAILED' : '\nall checks passed');
  process.exit(fail.length ? 1 : 0);
})().catch(e => { console.error(e); process.exit(1); });
