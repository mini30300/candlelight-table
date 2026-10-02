// Round 4 smoke: the page loads, 89 datasheets in 11 armies, every kit builds at every level, bots play games with the new armies
const { chromium } = require('playwright');
const PAGE = process.env.PAGE || require('path').resolve(__dirname, '../../../app/src/main/assets/battle-table.html');
(async () => {
  const b = await chromium.launch({ executablePath: process.env.CHROMIUM_PATH || undefined, args: ['--no-sandbox'] });
  const p = await b.newPage({ viewport: { width: 1000, height: 700 } });
  const errs = []; p.on('pageerror', e => errs.push(String(e.stack || e).slice(0, 300)));
  await p.goto('file://' + PAGE); await p.waitForFunction('window.BT && window.BT.G'); await p.waitForTimeout(300);
  const info = await p.evaluate(() => { const by = {}; BT.TYPES.forEach(t => by[t.fac] = (by[t.fac] || 0) + 1);
    const bad = []; BT.TYPES.forEach(t => { for (let L = 0; L < 4; L++){ try { const n = BT.kitFaces(t.k, L); if (!(n > 20)) bad.push(t.k + ':' + L + '=' + n); } catch (e){ bad.push(t.k + ' ' + e.message); } } });
    ['samurai_nb'].forEach(k => { try { BT.kitFaces(k, 0); } catch (e){ bad.push(k + ' ' + e.message); } });
    return { n: BT.TYPES.length, by, bad }; });
  console.log('types', info.n, JSON.stringify(info.by), 'kit problems', info.bad.length ? info.bad.slice(0, 8) : 'none');
  // every unit and every per-model variant has its own figure registered in the page source (no stand-in left)
  const src = require('fs').readFileSync(PAGE, 'utf8');
  const keys = (await p.evaluate(() => BT.TYPES.map(t => t.k))).concat(['samurai_nb', 'levy_axe', 'levy_club', 'pike_halb', 'pike_bill', 'maa_mace', 'maa_hammer', 'maa_axe', 'maa_flail']);
  const own = keys.filter(k => src.indexOf("kit('" + k + "'") >= 0), miss = keys.filter(k => own.indexOf(k) < 0);
  console.log('own figures', own.length + '/' + keys.length, miss.length ? 'missing: ' + miss.join(',') : '', src.indexOf('stand-ins for the Round 4') >= 0 ? '· stand-in block still in' : '· no stand-in block');
  const facs = ['jp', 'nr', 'eg', 'md'];
  for (const [i, pair] of [['jp', 'md'], ['nr', 'eg'], ['md', 'nr'], ['eg', 'jp']].entries()) {
    const r = await p.evaluate(([A, B, seed]) => { BT.clock(false); BT.setTerrain('hills'); BT.seed(seed); BT.G.budget = 1000; BT.mkPlayers();
      const L = f => { const l = new Array(BT.TYPES.length).fill(0); BT.TYPES.forEach((t, j) => { if (t.fac === f) l[j] = t.n >= 5 ? 1 : 1; }); return l; };
      BT.setList(0, L(A)); BT.setList(1, L(B)); BT.setDep(0, -18, 0); BT.setDep(1, 18, 0); BT.start();
      BT.players().forEach(P => P.bot = true);
      let k = 0; while (!BT.G.over && k < 6000){ BT.botStep(); BT.tick(1/30, 2); k++; }
      return { over: BT.G.over, round: BT.G.round, k, log: BT.log().slice(-1)[0].t.replace(/<[^>]+>/g, '') }; }, [pair[0], pair[1], 11 + i]);
    console.log(pair.join(' vs '), JSON.stringify(r));
  }
  console.log('errors', errs.length ? errs.slice(0, 4) : 'none');
  await b.close(); process.exit(errs.length ? 1 : 0);
})().catch(e => { console.error('THREW', e); process.exit(1); });
