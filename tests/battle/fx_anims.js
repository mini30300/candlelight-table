// Round 8 (A): attack animation, visual effects and sound effects.
//   node r8_fx.js <page> [basePage [ticks]]
// Every weapon in TYPES fires and strikes without errors and makes effects; every sound kind renders offline without
// clipping and the new ones vary from play to play; an explicit fx on a weapon wins over the guess and an unknown one
// falls back; the particle pool holds its cap at every graphics level and low makes far fewer and draws no glow; the
// deaths, the stagger, the exploding wreck and the camera shake run clean. With a base page: an 8-army bot battle on
// the same seed, frame times before (base) and after (page), interleaved.
const { chromium } = require('playwright');
const path = require('path');
const PAGE = path.resolve(process.argv[2] || process.env.PAGE || require('path').resolve(__dirname, '../../app/src/main/assets/battle-table.html')), BASE = process.argv[3] ? path.resolve(process.argv[3]) : null, TICKS = +(process.argv[4] || 1500);
let pass = 0, fail = 0; const ok = (c, m, x) => { c ? pass++ : fail++; console.log((c ? 'ok   ' : 'FAIL ') + m + (x !== undefined ? '  ' + JSON.stringify(x) : '')); };
const NEW = ['bolter', 'hbolter', 'plasma', 'melta', 'rocket', 'sniper', 'gatling', 'cannon', 'beam', 'chain', 'power', 'hammer', 'claw', 'bite', 'warp'];
const EXE = process.env.CHROMIUM_PATH || undefined;
const ARMIES = [
  ['heavy:1', 'infantry:2', 'hmg:1', 'sniper:1', 'flamer:1', 'mortar:1', 'tank:1'],
  ['knight:2', 'kheavy:1', 'kassault:1', 'kterm:1', 'kdread:1', 'ktank:1'],
  ['gaunt:2', 'warrior:1', 'hound:1', 'spitter:1', 'brute:1', 'swexo:1'],
  ['rwar:2', 'rimm:1', 'rguard:1', 'rscarab:1', 'rspider:1', 'rbdstalk:1'],
  ['boy:2', 'loota:1', 'nob:1', 'grot:1', 'oburna:1', 'owagon:1'],
  ['elguard:2', 'eldire:1', 'elreaper:1', 'eldragon:1', 'elwguard:1', 'elprism:1'],
  ['dewar:2', 'dewych:1', 'deincubi:1', 'detrue:1', 'descourge:1', 'deravager:1'],
  ['tafw:2', 'tabreach:1', 'tapath:1', 'tacrisis:1', 'tabroad:1', 'tahammer:1'] ];
async function battle(b, page, n){
  const p = await b.newPage({ viewport: { width: 1366, height: 800 }, deviceScaleFactor: 1 });
  const errs = []; p.on('pageerror', e => errs.push(String(e).slice(0, 300)));
  await p.goto('file://' + page); await p.waitForFunction('window.BT && window.BT.G'); await p.waitForTimeout(300);
  await p.evaluate((A) => { BT.gfx('mid'); BT.clock(false); BT.quit(); BT.setTheme('ruin'); BT.setTerrain('hills'); BT.seed(71); BT.size(120); BT.setBuildings(true, 1);
    BT.G.mode = 'ffa'; BT.G.teams = 8; BT.G.perTeam = 1; BT.G.budget = 40000; BT.G.goal = 'kill'; BT.mkPlayers(); BT.players().forEach(P => P.bot = true);
    const L = (arr) => { const l = new Array(BT.TYPES.length).fill(0); arr.forEach(s => { const [k, m] = s.split(':'); const i = BT.TYPES.findIndex(t => t.k === k); if (i >= 0) l[i] = +m; }); return l; };
    A.forEach((a, i) => BT.setList(i, L(a))); BT.players().forEach((P, i) => { const a = i/8*Math.PI*2; P.dep = [Math.round(Math.cos(a)*44), Math.round(Math.sin(a)*30)]; });
    BT.setAuto(true); { let x = 12345; BT.dice(Array.from({ length: 60000 }, () => { x = (x*1103515245 + 12345) & 0x7fffffff; return 1 + (x >>> 16) % 6; })); }   // the same dice on both pages
    BT.start(); BT.renderScale(1); BT.fit(); for (let i = 0; i < 20; i++) BT.draw(); }, ARMIES);
  const r = await p.evaluate((N) => { const ms = []; let pk = 0;
    for (let i = 0; i < N && !BT.G.over; i++){ const t0 = performance.now(); BT.tick(1/30, 1); ms.push(performance.now() - t0); if (BT.fx8){ const q = BT.fx8().n; if (q > pk) pk = q; } }
    const s = ms.slice().sort((a, c) => a - c), q = (k) => +s[Math.min(s.length - 1, Math.floor(s.length*k))].toFixed(2);
    return { steps: ms.length, mean: +(ms.reduce((a, c) => a + c, 0)/ms.length).toFixed(2), median: q(0.5), p90: q(0.9), p99: q(0.99), round: BT.G.round, lines: BT.log().length, alive: BT.units.length, peakParticles: pk }; }, n);
  await p.close(); return { ...r, errors: errs.length };
}
(async () => {
  const b = await chromium.launch({ executablePath: EXE, args: ['--no-sandbox'] });
  const p = await b.newPage({ viewport: { width: 1200, height: 760 }, deviceScaleFactor: 1 });
  const errs = []; p.on('pageerror', e => errs.push(String(e.stack || e).slice(0, 400)));
  await p.goto('file://' + PAGE); await p.waitForFunction('window.BT && window.BT.G && window.BT.fx8'); await p.waitForTimeout(300);

  // ---- sounds ----
  const kinds = await p.evaluate(() => BT.snd.kinds());
  ok(NEW.concat(['stomp', 'quake', 'ricochet', 'debris']).every(k => kinds.includes(k)), 'every new sound kind is defined', NEW.filter(k => !kinds.includes(k)));
  let worst = 0, bad = [];
  for (const k of kinds){ for (let i = 0; i < (NEW.includes(k) ? 4 : 1); i++){
    const r = await p.evaluate((k) => new Promise(res => BT.snd.probe(k, res)), k);
    if (!r || r.err || r.nan || !(r.peak < 1) || !(r.peak > 0.02) || !(r.rms > 0.0005)) bad.push(k + ':' + JSON.stringify(r)); else worst = Math.max(worst, r.peak); } }
  ok(bad.length === 0, 'every sound kind renders offline: peak under 1, not silent, no NaN (new kinds four times each)', { bad: bad.slice(0, 4), loudest: worst });
  const vary = await p.evaluate(async (NEW) => { const out = [];
    for (const k of NEW){ const a = await new Promise(r => BT.snd.probe(k, r, { raw:true, sr:22050 })), c = await new Promise(r => BT.snd.probe(k, r, { raw:true, sr:22050 }));
      if (a.pcm === c.pcm) out.push(k); } return out; }, NEW);
  ok(vary.length === 0, 'each new kind sounds a little different every time it plays', vary);
  const unk = await p.evaluate(() => { try { BT.snd.at('nosuchkind', [0, 0, 0]); BT.snd.at(undefined); return BT.snd.stats().ask.nosuchkind === 1; } catch (e){ return String(e); } });
  ok(unk === true, 'an unknown sound kind is asked for without an error and stays silent', unk);

  // ---- which effect kind each weapon gets ----
  const map = await p.evaluate(() => { const K = BT.fxKinds(), bad = [], by = {}; let n = 0;
    BT.TYPES.forEach(T => [false, true].forEach(m => { const W = m ? T.mel : T.gun; if (!W) return; const k = BT.fxKind(T.k, m); n++;
      if (k !== null && !K.includes(k)) bad.push(T.k + (m ? ':m' : ':r') + '=' + k); by[k] = (by[k] || 0) + 1; }));
    return { n, bad, by }; });
  ok(map.bad.length === 0 && map.n > 300, 'every weapon maps to a known effect kind or to the old look (null)', map);
  const spot = await p.evaluate(() => ({ knight: BT.fxKind('knight'), kheavy: BT.fxKind('kheavy'), elreaper: BT.fxKind('elreaper'), ksnipe: BT.fxKind('ksnipe'), tank: BT.fxKind('tank'),
    kdread: BT.fxKind('kdread'), eldragon: BT.fxKind('eldragon'), ktank: BT.fxKind('ktank'), klib: BT.fxKind('klib'), kassaultM: BT.fxKind('kassault', true),
    kbladeM: BT.fxKind('kblade', true), ktermM: BT.fxKind('kterm', true), swlictorM: BT.fxKind('swlictor', true), spitterM: BT.fxKind('spitter', true), infantry: BT.fxKind('infantry') }));
  ok(spot.knight === 'bolter' && spot.kheavy === 'plasma' && spot.elreaper === 'rocket' && spot.ksnipe === 'sniper' && spot.tank === 'cannon' && spot.kdread === 'gatling' &&
     spot.eldragon === 'melta' && spot.ktank === 'beam' && spot.klib === 'warp' && spot.kassaultM === 'chain' && spot.kbladeM === 'power' && spot.ktermM === 'hammer' &&
     spot.swlictorM === 'claw' && spot.spitterM === 'bite' && spot.infantry === null, 'the guesses: bolter, plasma, rocket, sniper, cannon, gatling, melta, beam, warp, chain, power, hammer, claw, bite; a plain rifle keeps the old look', spot);
  const over = await p.evaluate(() => { const T = BT.TYPES.find(t => t.k === 'infantry'), g0 = T.gun, m0 = T.mel, out = {};
    T.gun = Object.assign({}, g0, { fx:'warp' }); out.warp = BT.fxKind('infantry');
    T.gun = Object.assign({}, g0, { fx:'nosuchkind' }); out.unknown = BT.fxKind('infantry');
    T.mel = Object.assign({}, m0, { fx:'claw' }); out.claw = BT.fxKind('infantry', true);
    T.gun = g0; T.mel = m0; return out; });
  ok(over.warp === 'warp' && over.unknown === null && over.claw === 'claw', 'an explicit fx on a weapon wins over the guess; an unknown one falls back to the old look', over);

  // ---- every weapon: fire and strike ----
  const all = await p.evaluate(() => { const out = { r:0, m:0, quiet:[], errs:[] }; BT.clock(false); BT.setTerrain('flat'); BT.setBuildings(false); BT.size(40);
    const ask0 = BT.snd.stats().ask;
    for (const T of BT.TYPES){ for (const melee of [false, true]){ if (!(melee ? T.mel : T.gun)) continue;
      try { BT.units.length = 0; BT.fallen().length = 0; BT.fx8({ clear:1 }); const d = melee ? 1.1 : 6; BT.add(T.k, -d, 0); BT.add('heavy', d, 0);
        BT.units[0].rot = Math.PI/2; BT.units[1].rot = -Math.PI/2; Object.assign(BT.cam, { tx:0, tz:0, dist:14, pitch:0.4 });
        if (!BT.animate(0, 1, melee, 3)){ out.quiet.push(T.k + (melee ? ':m' : ':r') + ' no action'); continue; }
        let fx = 0; for (let i = 0; i < 150 && (BT.units[0].act || i < 20); i++){ BT.tick(1/30, 1); fx = Math.max(fx, BT.fx().length); }
        const st = BT.fx8(); if (!(fx > 0 || st.made > 0)) out.quiet.push(T.k + (melee ? ':m' : ':r')); else out[melee ? 'm' : 'r']++;
      } catch (e){ out.errs.push(T.k + (melee ? ':m ' : ':r ') + e.message); } } }
    const ask = BT.snd.stats().ask; out.ask = {}; ['bolter', 'hbolter', 'plasma', 'melta', 'rocket', 'sniper', 'gatling', 'cannon', 'beam', 'warp', 'chain', 'power', 'hammer', 'claw', 'bite'].forEach(k => out.ask[k] = (ask[k] || 0) - (ask0[k] || 0));
    return out; });
  ok(all.errs.length === 0 && errs.length === 0, 'every weapon in TYPES fires / strikes without an error', { errs: all.errs.slice(0, 4), page: errs.slice(0, 2) });
  ok(all.quiet.length === 0 && all.r > 180 && all.m > 230, 'and every one of them makes effects (' + all.r + ' guns, ' + all.m + ' melee weapons)', all.quiet.slice(0, 8));
  ok(Object.values(all.ask).every(n => n > 0), 'the weapons asked for the new sound kinds', all.ask);

  // ---- each kind looks like itself (an explicit fx on the knight's bolter and the sword knight's blade) ----
  const look = await p.evaluate(() => { const want = { bolter:'bolt8', hbolter:'bolt8', gatling:'tracer', sniper:'streak', cannon:'boom', rocket:'rocket', plasma:'orb', melta:'melta', beam:'beam', warp:'orb', nosuch:'tracer' },
      wantM = { chain:'grind', power:'arc', hammer:'ring', claw:'swoosh', warp:'lite', bite:'!swoosh' }, out = { miss:[] };
    const T = BT.TYPES.find(t => t.k === 'knight'), g0 = T.gun, S = BT.TYPES.find(t => t.k === 'kblade'), m0 = S.mel;
    function run(k, melee){ BT.units.length = 0; BT.fallen().length = 0; BT.fx8({ clear:1 }); const d = melee ? 1.1 : 6; BT.add(melee ? 'kblade' : 'knight', -d, 0); BT.add('heavy', d, 0);
      BT.units[0].rot = Math.PI/2; BT.units[1].rot = -Math.PI/2; BT.animate(0, 1, melee, 3); const seen = {};
      for (let i = 0; i < 150; i++){ BT.tick(1/30, 1); BT.fx().forEach(f => seen[f] = 1); } return seen; }
    for (const k in want){ T.gun = Object.assign({}, g0, { fx:k }); const s = run(k, false); if (!s[want[k]]) out.miss.push(k + '→' + want[k] + ' saw ' + Object.keys(s).join(',')); }
    for (const k in wantM){ S.mel = Object.assign({}, m0, { fx:k }); const s = run(k, true), w = wantM[k];
      if (w[0] === '!' ? s[w.slice(1)] : !s[w]) out.miss.push('melee ' + k + '→' + w + ' saw ' + Object.keys(s).join(',')); }
    T.gun = g0; S.mel = m0; return out; });
  ok(look.miss.length === 0, 'each kind draws its own look: bolts, tracers, sniper streak, shell burst, rocket, plasma orb, melta beam, beam, warp orb; chain sparks, power arc, hammer ring, claw rake, bite without a trail', look.miss);

  // ---- particles: the cap at every level, low makes far fewer and draws no glow ----
  const caps = await p.evaluate(() => { const out = {};
    for (const g of ['hi', 'mid', 'lo']){ BT.gfx(g); BT.units.length = 0; BT.fx8({ clear:1 }); let over = 0;
      for (let i = 0; i < 40; i++){ BT.blast((i % 8) - 4, Math.floor(i/8) - 2, 1.6); const s = BT.fx8(); if (s.n > s.cap) over++; BT.tick(1/30, 1); if (BT.fx8().n > BT.fx8().cap) over++; }
      const s = BT.fx8(); out[g] = { cap: s.cap, peak: s.peak, drop: s.drop, over }; }
    BT.gfx('mid'); return out; });
  ok(['hi', 'mid', 'lo'].every(g => caps[g].over === 0 && caps[g].peak <= caps[g].cap && caps[g].drop > 0) && caps.lo.cap < caps.mid.cap && caps.mid.cap < caps.hi.cap,
    'forty big explosions at once: the particle pool never passes its cap (hi > mid > lo) and drops the rest', caps);
  const lo = await p.evaluate(() => { const out = {}, cv = document.getElementById('btCv'), cx = cv.getContext('2d');
    const d = Object.getOwnPropertyDescriptor(CanvasRenderingContext2D.prototype, 'globalCompositeOperation'); let lighter = 0;
    Object.defineProperty(cx, 'globalCompositeOperation', { configurable: true, get(){ return d.get.call(this); }, set(v){ if (v === 'lighter') lighter++; d.set.call(this, v); } });
    for (const g of ['hi', 'lo']){ BT.gfx(g); BT.units.length = 0; BT.fx8({ clear:1 }); Object.assign(BT.cam, { tx:0, tz:0, dist:16, pitch:0.4 });
      lighter = 0; for (let i = 0; i < 5; i++) BT.blast(i*1.5 - 3, 0, 1); BT.add('kheavy', -5, 3); BT.add('heavy', 5, 3); BT.animate(0, 1, false, 2);
      let peak = 0; for (let i = 0; i < 40; i++){ BT.tick(1/30, 1); peak = Math.max(peak, BT.fx8().n); } out[g] = { made: BT.fx8().made, peak, lighter }; }
    delete cx.globalCompositeOperation; BT.gfx('mid'); return out; });
  ok(lo.lo.made < lo.hi.made*0.5 && lo.lo.lighter === 0 && lo.hi.lighter > 0, 'low graphics: under half the particles of high, and no glow (no additive light) at all', lo);

  // ---- deaths, stagger, the exploding wreck, the camera shake ----
  const dies = await p.evaluate(() => { const out = { left:[], fx:{} };
    for (const v of ['back', 'fwd', 'spin', 'kneel', 'drop', 'blown', 'side', 'topple']){ BT.units.length = 0; BT.fallen().length = 0; BT.fx8({ clear:1 });
      BT.add(v === 'side' ? 'hound' : v === 'topple' ? 'cyclops' : 'knight', 0, 0); BT.add('heavy', 4, 0); const got = BT.kill8(0, v, 0);
      for (let i = 0; i < 150; i++) BT.tick(1/30, 1); if (got !== v || BT.fallen().length) out.left.push(v); }
    BT.units.length = 0; BT.fallen().length = 0; BT.fx8({ clear:1 }); BT.add('tank', 0, 0); BT.add('heavy', 6, 0); Object.assign(BT.cam, { tx:0, tz:0, dist:14 });
    out.tank = BT.kill8(0, null, 1); const seen = {}; let shake = 0;
    for (let i = 0; i < 90; i++){ BT.tick(1/30, 1); BT.fx().forEach(f => seen[f] = 1); shake = Math.max(shake, BT.fx8().shake); }
    out.fx = Object.keys(seen); out.shake = shake; for (let i = 0; i < 240; i++) BT.tick(1/30, 1); out.after = BT.fx8().shake; out.cam = [BT.cam.tx, BT.cam.tz, BT.cam.dist];
    BT.units.length = 0; BT.fallen().length = 0; BT.add('knight', 0, 0); BT.add('heavy', 3, 0);
    out.hurt = [BT.hurt8(0, 1, 1), BT.acts().map(a => a.kind).join(), BT.hurt8(0, 1, 4, 'rocket')]; for (let i = 0; i < 40; i++) BT.tick(1/30, 1); out.still = BT.acts().length;
    return out; });
  ok(dies.left.length === 0, 'every way of falling plays through and the body is cleared (back, forward, spin, kneel, drop, blown away, beast on its side, giant topple)', dies.left);
  ok(dies.tank === 'boom' && ['boom', 'burn', 'ring', 'scorch'].every(k => dies.fx.includes(k)) && dies.shake > 0 && dies.after === 0 && dies.cam[2] === 14,
    'a tank explodes (fireball, blast ring, scorch, burning wreck), shakes the camera for a moment, and the camera itself never moves', dies);
  ok(dies.hurt[0] && dies.hurt[1] === 'flinch' && dies.hurt[2] && dies.still === 0, 'a hit staggers (harder hits knock back) and settles', dies.hurt);

  // ---- a titan close to the camera: its base is under the bottom edge of the screen, its body fills the view ----
  const tall = await p.evaluate(() => { BT.clock(false); BT.setTerrain('flat'); BT.setBuildings(false); BT.size(60); BT.units.length = 0; BT.fallen().length = 0; BT.fx8({ clear:1 });
    const H = document.getElementById('btCv').getBoundingClientRect().height; let tz = null;
    for (let z = -32; z <= -10 && tz === null; z += 0.25){ Object.assign(BT.cam, { tx:0, tz:z, dist:30, pitch:0.1, yaw:0 }); const a = BT.screen(0, 0, 0); if (a[1] > H + 260 && a[1] < H + 2000) tz = z; }
    if (tz === null) return { view: false };
    Object.assign(BT.cam, { tx:0, tz, dist:30, pitch:0.1, yaw:0 }); BT.draw(); const f0 = BT.faces(); BT.add('ktwarlord', 0, 0); BT.draw(); BT.draw();
    const f1 = BT.faces(); BT.units.length = 0; BT.cam.tz = 0; BT.cam.dist = 14; return { view: true, tz, without: f0, with: f1 }; });
  ok(tall.view && tall.with > tall.without + 50, 'a titan whose base is under the screen while its body fills the view is still drawn (not culled by its base)', tall);
  // titans stomp in melee (ttn walkers whose melee is not a weapon swing); the others keep their own blow
  const st = await p.evaluate(() => {
    const out = { kinds:{}, rise:{}, fx:[], quake:0, shake:0 }, ask0 = BT.snd.stats().ask.quake || 0;
    for (const k of ['ktwarhound', 'ktwarlord', 'ktimperator', 'ogork', 'tataunar', 'kgcastellan', 'tasurge', 'elwknight', 'tagm', 'kgwarden', 'kgpaladin', 'swhiero', 'rbmono', 'detantalus', 'dmg', 'dmx', 'knight']){
      if (!BT.TYPES.find(t => t.k === k)) continue;
      BT.units.length = 0; BT.fallen().length = 0; BT.fx8({ clear:1 });
      BT.add(k, -3, 0); BT.units[0].rot = Math.PI/2; BT.add('heavy', 3, 0); BT.units[1].rot = -Math.PI/2;
      BT.animate(0, 1, true, 2); BT.tick(1/60, 1); const u = BT.units[0]; out.kinds[k] = u.act ? u.act.kind : null;
      if (out.kinds[k] !== 'stomp') continue;
      let y0 = null, top = 0; const seen = {};
      for (let i = 0; i < 240; i++){ BT.tick(1/60, 1); const a = u.act;
        if (a && a.W && a.W.ankleL){ const lo = Math.min(a.W.ankleL.p[1], a.W.ankleR.p[1]), hi = Math.max(a.W.ankleL.p[1], a.W.ankleR.p[1]); if (y0 === null) y0 = lo; top = Math.max(top, hi - y0); }
        BT.fx().forEach(f => seen[f] = 1); out.shake = Math.max(out.shake, BT.fx8().shake); }
      out.rise[k] = +top.toFixed(2); out.fx = [...new Set(out.fx.concat(Object.keys(seen)))]; }
    out.quake = (BT.snd.stats().ask.quake || 0) - ask0; BT.units.length = 0; BT.fallen().length = 0; BT.fx8({ clear:1 }); return out; });
  const tw = ['ktwarhound', 'ktwarlord', 'ktimperator', 'ogork', 'tataunar', 'kgcastellan'].filter(k => k in st.kinds);
  ok(tw.length >= 5 && tw.every(k => st.kinds[k] === 'stomp' && st.rise[k] > 0.15) && ['tagm', 'kgwarden', 'kgpaladin', 'swhiero', 'rbmono', 'detantalus', 'dmg', 'dmx', 'knight'].every(k => !(k in st.kinds) || st.kinds[k] !== 'stomp')
     && st.fx.includes('ring') && st.quake > 0 && st.shake > 0, 'titans stomp in melee: a leg lifts high and slams down (shock ring, dust, shake, quake sound); weapon swingers keep their blow', st);

  ok(errs.length === 0, 'no page errors', errs.slice(0, 3));
  await p.close();

  // ---- an 8-army bot battle: frame times before and after, same seed, interleaved ----
  if (BASE){
    const A = [], B = [];
    for (let k = 0; k < 2; k++){ A.push(await battle(b, BASE, TICKS)); B.push(await battle(b, PAGE, TICKS)); }
    const avg = (arr, f) => +(arr.reduce((s, r) => s + r[f], 0)/arr.length).toFixed(2);
    const before = { mean: avg(A, 'mean'), median: avg(A, 'median'), p90: avg(A, 'p90'), p99: avg(A, 'p99') }, after = { mean: avg(B, 'mean'), median: avg(B, 'median'), p90: avg(B, 'p90'), p99: avg(B, 'p99') };
    console.log('battle runs  before', JSON.stringify(A)); console.log('             after ', JSON.stringify(B));
    ok(B.every(r => r.errors === 0) && A[0].steps === B[0].steps && A[0].lines === B[0].lines, 'the same seed plays the same battle on both pages (steps, log lines)', { before: A.map(r => r.lines), after: B.map(r => r.lines) });
    ok(after.median <= before.median*1.1 && after.mean <= before.mean*1.1, '8-army bot battle frame times (ms, sim + draw per frame): after no slower than before', { before, after });
  }
  console.log(pass + ' passed, ' + fail + ' failed'); await b.close(); process.exit(fail ? 1 : 0);
})();
