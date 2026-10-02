// 8.2: แผงข้างตอนดูบอทตีกัน — ปุ่มไม่ทับกันทั้งหน้าต่างเตี้ย (โปรแกรมบนจอ 768) จอสูง และมือถือ · เปลี่ยนหน้าแล้วแผงกลับไปหัว
const { chromium } = require('playwright');
const F = 'file://' + require('path').resolve(process.argv[2] || process.env.PAGE || require('path').resolve(__dirname, '../../app/src/main/assets/battle-table.html'));
const SHOT = process.argv[3];
let pass = 0, fail = 0; const ok = (c, m, x) => { c ? pass++ : fail++; console.log((c ? 'ok   ' : 'FAIL ') + m + (x !== undefined ? '  ' + JSON.stringify(x) : '')); };
(async () => {
  const b = await chromium.launch({ executablePath: process.env.CHROMIUM_PATH || undefined, args: ['--no-sandbox'] });
  const errs = [];
  for (const [w, h, nm] of [[1345, 654, 'window 1345x654'], [1366, 900, 'desktop 1366x900'], [390, 844, 'phone 390x844']]) {
    const p = await b.newPage({ viewport: { width: w, height: h } }); p.on('pageerror', e => errs.push(String(e)));
    await p.goto(F); await p.waitForFunction('window.BT && window.BT.snd');
    // เลื่อนแผงหน้าตั้งสนามลงไปก่อน แล้วเริ่มดูบอท: หน้าเล่นต้องเริ่มที่หัวแผง
    await p.evaluate(() => { const pn = document.querySelector('#bt .panel'); pn.scrollTop = 400; });
    await p.click('#btModes .mode[data-g="spectator"]'); await p.waitForTimeout(100);
    await p.click('#btNext'); await p.waitForTimeout(600);
    let r = await p.evaluate(() => ({ play: !document.getElementById('scPlay').classList.contains('hide'), st: document.querySelector('#bt .panel').scrollTop }));
    ok(r.play && r.st === 0, nm + ': spectator game starts with the panel at its top', r);
    await p.evaluate(() => { const pn = document.querySelector('#bt .panel'); pn.scrollTop = pn.scrollHeight; window.scrollTo(0, document.body.scrollHeight); });
    await p.waitForTimeout(150);
    r = await p.evaluate(() => {
      const R = (el) => { const q = el.getBoundingClientRect(); return { t: q.top, b: q.bottom, l: q.left, r: q.right, h: q.height }; };
      const log = R(document.getElementById('btLog')), quit = R(document.getElementById('btQuit'));
      const camRow = document.getElementById('btPan').closest('.row'), camH = R(camRow.previousElementSibling), cam = R(camRow);
      const bs = [...document.querySelectorAll('#bt .panel button, #bt .panel h3, #bt .panel .log')].filter(e => e.offsetParent && e.getBoundingClientRect().height > 0);
      const hits = [];
      for (let i = 0; i < bs.length; i++) for (let j = i + 1; j < bs.length; j++) {
        if (bs[i].contains(bs[j]) || bs[j].contains(bs[i])) continue;
        const a = bs[i].getBoundingClientRect(), c = bs[j].getBoundingClientRect();
        const ix = Math.min(a.right, c.right) - Math.max(a.left, c.left), iy = Math.min(a.bottom, c.bottom) - Math.max(a.top, c.top);
        if (ix > 1 && iy > 1) hits.push([(bs[i].id || bs[i].textContent).slice(0, 14), (bs[j].id || bs[j].textContent).slice(0, 14)]);
      }
      return { log, quit, camH, cam, hits, logH: log.h };
    });
    ok(r.hits.length === 0, nm + ': no buttons, headings or the log overlap anywhere in the panel', r.hits.slice(0, 4));
    ok(r.log.b <= r.quit.t && r.quit.b <= r.camH.t && r.camH.b <= r.cam.t && r.quit.h >= 30, nm + ': log, then "ออกจากการรบ", then the camera heading and buttons, in order', { log: r.log.b, quit: [r.quit.t, r.quit.b], camH: [r.camH.t, r.camH.b], cam: r.cam.t });
    if (nm.startsWith('desktop')) ok(r.logH > 150, nm + ': with room to spare the log still stretches to fill the panel', r.logH);
    if (nm.startsWith('window') && SHOT) {
      await p.evaluate(() => { const q = document.getElementById('btLog').getBoundingClientRect(); const pn = document.querySelector('#bt .panel'); pn.scrollTop += q.top - 140; });
      await p.waitForTimeout(100);
      const pb = await p.evaluate(() => { const q = document.querySelector('#bt .panel').getBoundingClientRect(); return { x: q.left, y: q.top, width: q.width, height: q.height }; });
      await p.screenshot({ path: SHOT, clip: { x: Math.max(0, pb.x - 8), y: pb.y, width: pb.width + 16, height: pb.height } });
    }
    await p.close();
  }
  ok(errs.length === 0, 'no page errors', errs.slice(0, 3));
  console.log(pass + ' passed, ' + fail + ' failed'); await b.close(); process.exit(fail ? 1 : 0);
})();
