// 8.3: เพลงเดิมกลับมาเล่นสลับกับเพลงใหม่ · ปุ่ม สลับเพลง / เพลงใหม่ / เพลงเดิม จำไว้ในเครื่อง
const { chromium } = require('playwright');
const F = 'file://' + require('path').resolve(process.argv[2] || process.env.PAGE || require('path').resolve(__dirname, '../../app/src/main/assets/battle-table.html'));
let pass = 0, fail = 0; const ok = (c, m, x) => { c ? pass++ : fail++; console.log((c ? 'ok   ' : 'FAIL ') + m + (x !== undefined ? '  ' + JSON.stringify(x) : '')); };
(async () => {
  const b = await chromium.launch({ executablePath: process.env.CHROMIUM_PATH || undefined, args: ['--no-sandbox'] });
  const ctx = await b.newContext({ viewport: { width: 1366, height: 900 } });
  const p = await ctx.newPage(); const errs = []; p.on('pageerror', e => errs.push(String(e)));
  await p.goto(F); await p.waitForFunction('window.BT && window.BT.snd');
  const ui = () => p.evaluate(() => ({ on: [...document.querySelectorAll('#btMusSt button.on')].map(x => x.dataset.m), n: document.querySelectorAll('#btMusSt button').length,
    st: BT.snd.state().st, ls: (JSON.parse(localStorage.getItem('bt_snd') || '{}')).st, vis: !!document.getElementById('btMusSt').offsetParent }));
  let r = await ui();
  ok(r.n === 3 && r.vis && r.on.join() === 'mix' && r.st === 'mix', 'three music buttons in the panel, "สลับเพลง" on by default', r);
  await p.click('#btMusSt button[data-m="old"]'); r = await ui();
  ok(r.on.join() === 'old' && r.st === 'old' && r.ls === 'old', 'pick "เพลงเดิม": the button lights and the choice is saved', r);
  await p.reload(); await p.waitForFunction('window.BT && window.BT.snd'); r = await ui();
  ok(r.on.join() === 'old' && r.st === 'old', 'after reopening the choice is still "เพลงเดิม"', r);
  await p.click('#btMusSt button[data-m="mix"]'); r = await ui();
  ok(r.on.join() === 'mix' && r.ls === 'mix', 'back to "สลับเพลง"', r);
  const pr = (op) => p.evaluate((op) => new Promise(res => BT.snd.probe('music', res, op)), op);
  r = await pr({ style: 'old', levels: [2, 2], trace: true });
  ok(r && !r.err && r.peak > 0.02 && r.peak < 1 && r.rms > 0.005 && r.styles === 'oo', 'old music in battle: sounds, does not clip', r);
  r = await pr({ style: 'old', levels: [0, 0], trace: true });
  ok(r && !r.err && r.peak > 0.02 && r.peak < 1 && r.styles === 'oo', 'old music in the menu: sounds, does not clip', r);
  const L1 = Array(24).fill(1);
  r = await pr({ style: 'mix', piece: [8, 8], levels: L1, trace: true, sec: 80, sr: 8000 });
  ok(r.styles === 'aaaaaaaabbbbbbbboooooooo' && r.peak < 1 && r.rms > 0.01, 'mix in battle: two new songs one after another, then the old music', r);
  r = await pr({ style: 'mix', levels: [0, 0, 0, 1, 1, 1], trace: true, sec: 30, sr: 8000 });
  ok(r.styles === 'oooaaa', 'mix: the menu plays the old music, and the new music comes in the bar the battle starts', r.styles);
  r = await pr({ style: 'mix', piece: [8, 8], levels: Array(18).fill(1).concat([3, 3, 3, 3]), trace: true, sec: 70, sr: 8000 });
  ok(r.styles === 'aaaaaaaabbbbbbbboocccc', 'mix: when the fighting reaches the peak the old music gives way at once', r.styles);
  r = await pr({ style: 'mix', piece: [8, 8], levels: [1, 1, 1, 1, 1, 1, 3, 3, 3, 3, 3, 3, 1, 1, 1, 1, 1, 1, 1, 1], trace: true, sec: 60, sr: 8000 });
  ok(r.styles === 'aaaaaaaaaaaaaaaabbbb', 'mix: the new music keeps playing through the peak instead of handing over on time', r.styles);
  r = await pr({ style: 'epic', piece: [8, 8], levels: Array(20).fill(1), trace: true, sec: 60, sr: 8000 });
  ok(r.styles === 'aaaaaaaabbbbbbbbcccc' && r.peak < 1 && r.rms > 0.01, '"เพลงใหม่" goes round the three new songs and never the old one', r);
  ok(errs.length === 0, 'no page errors', errs.slice(0, 3));
  console.log(pass + ' passed, ' + fail + ' failed'); await b.close(); process.exit(fail ? 1 : 0);
})();
