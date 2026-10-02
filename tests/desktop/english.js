// desktop start page in English after the player chose English in the offline battle table
const { chromium } = require('playwright');
const APP_VER = (require('fs').readFileSync(require('path').resolve(__dirname, '../../app/src/main/assets/battle-table.html'), 'utf8').match(/var APP_VER = '([\d.]+)'/) || [])[1];   // the version the page says it is
(async () => { const b = await chromium.launch({ executablePath: process.env.CHROMIUM_PATH || undefined, args: ['--no-sandbox'] });
  const c = await b.newContext(); await c.route('https://candlelight-table.mini3030023450.workers.dev/**', r => r.abort());
  const p = await c.newPage(); const errs = []; p.on('pageerror', e => errs.push(String(e)));
  await p.goto(process.argv[2] + '/index.html'); await p.waitForSelector('#play', { state: 'visible', timeout: 15000 });
  const th = await p.evaluate(() => document.getElementById('play').textContent);
  await p.click('#play'); await p.waitForTimeout(1500);
  const fr = p.frames().find(f => /battle-table/.test(f.url())); await fr.waitForFunction('window.BT && window.BT.G');
  await fr.evaluate(() => document.querySelector('#btLang button[data-l="en"]').click()); await p.waitForTimeout(1500);
  const fr2 = p.frames().find(f => /battle-table/.test(f.url())); await fr2.waitForFunction('window.BT && window.BT.G');
  const inTable = await fr2.evaluate(() => document.getElementById('btVer').textContent);
  await p.reload(); await p.waitForSelector('#play', { state: 'visible', timeout: 15000 });
  const r = await p.evaluate(() => ({ lang: document.documentElement.lang, play: document.getElementById('play').textContent, msg: document.getElementById('msg').textContent, back: document.getElementById('back').textContent }));
  console.log(JSON.stringify({ th, inTable, r }), 'errors', errs.length);
  const ok = /ออฟไลน์/.test(th) && inTable === 'Version ' + APP_VER && r.lang === 'en' && /offline/.test(r.play) && r.msg === 'No internet' && /Back/.test(r.back) && !errs.length;
  console.log(ok ? '1 passed, 0 failed' : '0 passed, 1 failed'); await b.close(); process.exit(ok ? 0 : 1); })();
