// The old free-placement sandbox must survive: it is now the "กำหนดเอง" mode.
const { chromium } = require('playwright');
const fail = [];
const ok = (c, m) => { console.log((c ? '  ok   ' : '  FAIL ') + m); if (!c) fail.push(m); };
(async () => {
  const b = await chromium.launch({ executablePath: process.env.CHROMIUM_PATH || undefined, args: ['--no-sandbox'] });
  const p = await b.newPage({ viewport: { width: 1100, height: 780 }, deviceScaleFactor: 2 });
  const errs = []; p.on('pageerror', e => errs.push(String(e)));
  await p.goto('file://' + (process.env.PAGE || require('path').resolve(__dirname, '../../../app/src/main/assets/battle-table.html')));
  await p.waitForFunction('window.BT && window.BT.G');
  await p.waitForTimeout(700);

  await p.click('#btModes .mode[data-g="custom"]');
  await p.click('#btNext');
  await p.waitForTimeout(400);
  ok(await p.isVisible('#scCustom'), 'custom screen shows');
  ok(!(await p.isVisible('#scPlay')), 'play screen is hidden in custom');
  ok(await p.evaluate(() => BT.G.on === false), 'no game rules running in custom');

  // place three pieces by tapping the board, the way the sandbox always worked
  await p.click('#btMode button[data-m="place"]');
  const box = await p.locator('#btCv').boundingBox();
  for (const [dx, dy] of [[-80, 40], [0, 20], [90, 50]]) {
    await p.mouse.click(box.x + box.width/2 + dx, box.y + box.height/2 + dy);
    await p.waitForTimeout(140);
  }
  const n = await p.evaluate(() => BT.units.length);
  ok(n === 3, 'tapping the board places pieces (' + n + ')');

  await p.click('#btMode button[data-m="measure"]');
  await p.mouse.click(box.x + box.width/2 - 60, box.y + box.height/2 + 30); await p.waitForTimeout(120);
  await p.mouse.click(box.x + box.width/2 + 60, box.y + box.height/2 + 40); await p.waitForTimeout(250);
  ok(await p.evaluate(() => !!(window.BT && document.querySelector('#btMode button[data-m="measure"]').classList.contains('on'))), 'measure mode selectable');
  await p.screenshot({ path: (process.env.TEST_OUT || require('os').tmpdir()) + '/shots/bt/v2-custom.png' });

  await p.click('#btMode button[data-m="erase"]');
  await p.mouse.click(box.x + box.width/2, box.y + box.height/2 + 20);
  await p.waitForTimeout(200);
  ok(await p.evaluate(() => BT.units.length) < n, 'erase removes a piece');

  await p.click('#btQuit2'); await p.waitForTimeout(300);
  ok(await p.isVisible('#scSetup'), 'back to setup from custom');

  await b.close();
  console.log(errs.length ? '\nPAGE ERRORS:\n' + errs.join('\n') : '\nno page errors');
  if (errs.length) fail.push('page errors');
  console.log(fail.length ? '\n' + fail.length + ' FAILED' : '\nall checks passed');
  process.exit(fail.length ? 1 : 0);
})().catch(e => { console.error(e); process.exit(1); });
