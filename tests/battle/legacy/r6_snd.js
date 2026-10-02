// Round 6: sound. Silent until the first tap; then effects play from the fight (shots, blows, dice, deaths, the turn horn)
// and music runs; the effects and the music turn off separately, the choice and the volume are remembered.
//   node r6_snd.js [page]
const { chromium } = require('playwright');
const PAGE = process.argv[2] || process.env.PAGE || require('path').resolve(__dirname, '../../../app/src/main/assets/battle-table.html');
let pass = 0, fail = 0; const ok = (c, m, x) => { c ? pass++ : fail++; console.log((c ? 'ok   ' : 'FAIL ') + m + (x !== undefined ? '  ' + JSON.stringify(x) : '')); };
(async () => {
  const b = await chromium.launch({ executablePath: process.env.CHROMIUM_PATH || undefined, args: ['--no-sandbox'] });
  const ctx = await b.newContext({ viewport: { width: 1100, height: 760 } });
  const p = await ctx.newPage();
  const errs = []; p.on('pageerror', e => errs.push(String(e.stack || e).slice(0, 400)));
  await p.goto('file://' + PAGE); await p.waitForFunction('window.BT && window.BT.G');
  let r = await p.evaluate(() => BT.snd.state());
  ok(r.ctx === 'none' && !r.music, 'silent before the first tap (no audio started)', r);
  await p.mouse.click(300, 300); await p.waitForTimeout(300);
  r = await p.evaluate(() => BT.snd.state());
  ok(r.ctx === 'running' && r.music, 'the first tap starts the audio and the music', r);
  // a quick fight with guns, blades, flame, a titan and Doom: the effects follow what happens
  r = await p.evaluate(() => { BT.quit(); BT.setTerrain('flat'); BT.setBuildings(false); BT.size(48); BT.G.goal = 'kill'; BT.G.budget = 40000; BT.mkPlayers();
    BT.players().forEach(P => P.bot = true); BT.setDep(0, -14, 0); BT.setDep(1, 14, 0);
    const L = (arr) => { const l = new Array(BT.TYPES.length).fill(0); arr.forEach(s => { const [k, n] = s.split(':'); l[BT.TYPES.findIndex(t => t.k === k)] = +n; }); return l; };
    BT.setList(0, L(['infantry:2', 'heavy:1', 'kassault:1', 'doom:1'])); BT.setList(1, L(['hoplite:2', 'archer:1', 'swgaunt:0', 'ktwarhound:1']));
    BT.setAuto(true); BT.start(); BT.clock(true); return true; });
  // in real time (the sound's own clock has to move): the page's loop runs the bots
  for (let i = 0; i < 40; i++){ await p.waitForTimeout(1000); const d = await p.evaluate(() => BT.G.over || BT.snd.stats().n > 60); if (d) break; }
  r = await p.evaluate(() => ({ over: BT.G.over, round: BT.G.round, st: BT.snd.stats(), live: BT.snd.state().live }));
  const by = r.st.by || {};
  ok(r.st.n > 10, 'the bots\' fight is heard', { over: r.over, round: r.round, n: r.st.n });
  ok(by.shot > 0 && by.dice > 0 && by.turn > 0, 'shots, dice and the turn horn were heard', by);
  ok(r.live <= 30, 'the number of live effect voices stays small', r.live);
  // effects off: nothing more is played; music stays on
  await p.click('#btSnd button[data-s="sfx"]');
  r = await p.evaluate(() => { BT.clock(false); const n0 = BT.snd.stats().n; BT.quit(); BT.mkPlayers(); BT.players().forEach(P => P.bot = true); BT.start(); let k = 0;
    while (!BT.G.over && k < 300){ BT.botStep(); BT.tick(1/30, 2); k++; }
    return { st: BT.snd.state(), more: BT.snd.stats().n - n0, pressed: document.querySelector('#btSnd button[data-s="sfx"]').getAttribute('aria-pressed') }; });
  ok(!r.st.sfx && r.st.mus && r.more <= 1 && r.pressed === 'false', 'effects off: silent effects, the music keeps playing', r);
  await p.click('#btSnd button[data-s="mus"]');
  r = await p.evaluate(() => BT.snd.state()); ok(!r.mus && !r.music, 'music off stops the music', r);
  await p.fill('#btVol', '35'); await p.dispatchEvent('#btVol', 'input');
  r = await p.evaluate(() => ({ v: BT.snd.state().vol, lab: document.getElementById('btVolV').textContent }));
  ok(Math.abs(r.v - 0.35) < 0.001 && r.lab === '35%', 'the volume slider sets the volume', r);
  await p.reload(); await p.waitForFunction('window.BT && window.BT.G');
  r = await p.evaluate(() => ({ st: BT.snd.state(), a: document.querySelector('#btSnd button[data-s="sfx"]').classList.contains('on'), vol: document.getElementById('btVol').value }));
  ok(!r.st.sfx && !r.st.mus && Math.abs(r.st.vol - 0.35) < 0.001 && !r.a && r.vol === '35', 'the choices and the volume are remembered after a reload', r);
  // hidden page: the audio pauses
  await p.click('#btSnd button[data-s="mus"]'); await p.mouse.click(300, 300); await p.waitForTimeout(200);
  r = await p.evaluate(async () => { Object.defineProperty(document, 'hidden', { configurable: true, get: () => true }); document.dispatchEvent(new Event('visibilitychange'));
    await new Promise(r => setTimeout(r, 300)); const h = BT.snd.state().ctx;
    Object.defineProperty(document, 'hidden', { configurable: true, get: () => false }); document.dispatchEvent(new Event('visibilitychange'));
    await new Promise(r => setTimeout(r, 300)); return { hidden: h, back: BT.snd.state().ctx }; });
  ok(r.hidden === 'suspended' && r.back === 'running', 'switching away pauses the audio, coming back resumes it', r);
  // the panel does not scroll sideways on a phone
  await p.setViewportSize({ width: 390, height: 800 });
  const wide = await p.evaluate(() => document.documentElement.scrollWidth - window.innerWidth);
  ok(wide <= 1, 'phone: the panel does not scroll sideways', wide);
  ok(errs.length === 0, 'no page errors', errs.slice(0, 3));
  console.log(pass + ' passed, ' + fail + ' failed'); await b.close(); process.exit(fail ? 1 : 0);
})();
