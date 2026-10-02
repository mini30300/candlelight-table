// desktop start page: no network → the offline battle table in a frame (and back); network → straight on to /app
const { chromium } = require('playwright');
const DIR = process.argv[2], SERVER = 'https://candlelight-table.mini3030023450.workers.dev';
let pass = 0, fail = 0; const ok = (c, m, d) => { if (c) pass++; else fail++; console.log((c ? 'ok   ' : 'FAIL ') + m + (c ? '' : ' ' + JSON.stringify(d))); };
(async () => {
  const b = await chromium.launch({ executablePath: process.env.CHROMIUM_PATH || undefined, args: ['--no-sandbox'] });
  const c = await b.newContext({ viewport: { width: 1180, height: 780 } }); const p = await c.newPage();
  const errs = []; p.on('pageerror', e => errs.push(String(e).slice(0, 200)));
  await c.route(SERVER + '/**', r => r.abort('internetdisconnected'));
  await p.goto(DIR + '/index.html');
  await p.waitForSelector('#off:not([hidden])', { timeout: 10000 });
  ok(await p.isVisible('#play'), 'with no connection the start page offers the offline battle table');
  await p.click('#play'); const fr = p.frameLocator('#fr');
  await p.waitForFunction(() => { const f = document.getElementById('fr'); return f.contentWindow && f.contentWindow.BT && f.contentWindow.BT.G; }, null, { timeout: 30000 });
  ok(await p.isVisible('#tt') && !(await p.isVisible('#home')), 'the battle table opens inside the app window, with a back bar');
  await p.click('#back'); ok(await p.isVisible('#home') && await p.isVisible('#play'), 'back returns to the start page, the game kept for a second tap');
  await c.unroute(SERVER + '/**'); await c.route(SERVER + '/**', r => r.fulfill({ status: 200, contentType: 'text/html', body: '<title>app</title>ONLINE' }));
  await p.click('#retry'); await p.waitForURL(SERVER + '/app', { timeout: 10000 });
  ok(p.url() === SERVER + '/app', 'with a connection it goes straight on to /app on the server', p.url());
  ok(!errs.length, 'no page errors', errs);
  console.log(pass + ' passed, ' + fail + ' failed'); await b.close(); process.exit(fail ? 1 : 0);
})();
