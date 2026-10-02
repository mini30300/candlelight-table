// Round 6 smoke: every kit builds at every detail level, every new unit (and the sniper-scout look and Loki's skin) goes
// through its ranged and melee actions and a walk without errors, every unit has its own figure, and bots play games with
// the new armies.   PAGE=... node r6_smoke.js
const { chromium } = require('playwright');
const PAGE = process.env.PAGE || require('path').resolve(__dirname, '../../../app/src/main/assets/battle-table.html');
(async () => {
  const b = await chromium.launch({ executablePath: process.env.CHROMIUM_PATH || undefined, args: ['--no-sandbox'] });
  const p = await b.newPage({ viewport: { width: 1000, height: 700 } });
  const errs = []; p.on('pageerror', e => errs.push(String(e.stack || e).slice(0, 300)));
  await p.goto('file://' + PAGE); await p.waitForFunction('window.BT && window.BT.G'); await p.waitForTimeout(300);
  const info = await p.evaluate(() => { const by = {}; BT.TYPES.forEach(t => by[t.fac] = (by[t.fac] || 0) + 1);
    const bad = []; BT.TYPES.concat([{ k: 'kscout_sn' }, { k: 'loki_f' }]).forEach(t => { for (let L = 0; L < 4; L++){ try { const n = BT.kitFaces(t.k, L); if (!(n > 20)) bad.push(t.k + ':' + L + '=' + n); } catch (e){ bad.push(t.k + ' ' + e.message); } } });
    return { n: BT.TYPES.length, by, bad }; });
  console.log('types', info.n, JSON.stringify(info.by), 'kit problems', info.bad.length ? info.bad.slice(0, 8) : 'none');
  const src = require('fs').readFileSync(PAGE, 'utf8');
  const news = await p.evaluate(() => BT.TYPES.slice(89).map(t => t.k).concat(['kscout_sn', 'loki_f']));
  const miss = news.filter(k => src.indexOf("kit('" + k + "'") < 0 || /stand-ins for the Round 6/.test(src) && new RegExp('[{ ,]' + k + ":\\[").test(src.slice(src.indexOf('stand-ins for the Round 6'), src.indexOf('==KITS-EXTRA=='))));
  console.log('own figures', (news.length - miss.length) + '/' + news.length, miss.length ? 'still stand-ins: ' + miss.join(',') : '· none left');
  // every new unit: shoot, strike, walk (with its own look, the sniper scout's and Loki's skin too)
  const act = await p.evaluate((news) => { const out = []; BT.clock(false); BT.setTerrain('flat'); BT.setBuildings(false); BT.size(60);
    for (const k of news){ try { BT.units.length = 0; const kk = k === 'kscout_sn' ? 'kscout' : k === 'loki_f' ? 'loki' : k;
        BT.add(kk, -6, 0); BT.add('heavy', 6, 0); const u = BT.units[0]; if (k === 'kscout_sn') u.id = 'x.1'; if (k === 'loki_f') u.skn = 'loki_f';
        BT.animate(0, 1, false, 3); for (let i = 0; i < 90 && u.act; i++) BT.tick(1/30, 1);
        BT.animate(0, 1, true, 3); for (let i = 0; i < 90 && u.act; i++) BT.tick(1/30, 1);
        BT.goTo(0, -2, 3); for (let i = 0; i < 40; i++) BT.tick(1/30, 1); BT.draw();
      } catch (e){ out.push(k + ': ' + e.message); } }
    return out; }, news);
  console.log('actions', act.length ? act.slice(0, 8) : 'all ok');
  for (const [i, pair] of [['kn', 'sw'], ['rb', 'kn'], ['sw', 'rb']].entries()) {
    const r = await p.evaluate(([A, B, seed]) => { BT.clock(false); BT.quit(); BT.setTerrain('hills'); BT.seed(seed); BT.size(90); BT.G.budget = 40000; BT.G.goal = 'kill'; BT.mkPlayers();
      const L = f => { const l = new Array(BT.TYPES.length).fill(0); BT.TYPES.forEach((t, j) => { if (t.fac === f && j >= 89 && t.pts < 2000) l[j] = 1; }); return l; };
      BT.setList(0, L(A)); BT.setList(1, L(B)); BT.setDep(0, -30, 0); BT.setDep(1, 30, 0); BT.start();
      BT.players().forEach(P => P.bot = true);
      let k = 0; while (!BT.G.over && k < 9000){ BT.botStep(); BT.tick(1/30, 2); k++; }
      return { units: BT.units.length, over: BT.G.over, round: BT.G.round, k, log: BT.log().slice(-1)[0].t.replace(/<[^>]+>/g, '') }; }, [pair[0], pair[1], 11 + i]);
    console.log(pair.join(' vs '), JSON.stringify(r));
  }
  console.log('errors', errs.length ? errs.slice(0, 4) : 'none');
  await b.close(); process.exit(errs.length || info.bad.length || act.length ? 1 : 0);
})();
