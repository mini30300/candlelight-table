// Terrain types, the buildings switch and density, and deployment on crowded tables.
const { chromium } = require('playwright');
const F = 'file://' + (process.env.PAGE || require('path').resolve(__dirname, '../../../app/src/main/assets/battle-table.html'));
let pass = 0, fail = 0;
const ok = (c, m) => { c ? pass++ : fail++; console.log((c ? '  ok  ' : '  FAIL') + '  ' + m); };
const THEMES = ['ruin', 'forest', 'desert', 'ice'], TERR = ['flat', 'hills', 'mountain', 'forest'];
(async () => {
  const b = await chromium.launch({ executablePath: process.env.CHROMIUM_PATH || undefined, args: ['--no-sandbox'] });
  const p = await b.newPage({ viewport: { width: 1366, height: 768 } });
  const errs = []; p.on('pageerror', e => errs.push(String(e)));
  await p.goto(F); await p.waitForFunction('window.BT && window.BT.G'); await p.waitForTimeout(400);
  // a stub room sets theme/seed/size/terrain/buildings/density in one go, exactly as a guest's device does
  await p.evaluate(() => {
    window.field = (th, tr, on, dn, seed, w) => BT.adoptRoom({ setup: { theme: th, seed: seed, w: w || 48, terrain: tr, buildings: on, density: dn,
      mode: 'pve', teams: 2, perTeam: 1, budget: 150, freeFire: false, clock: 0 }, players: [] });
    window.STR = { building:1, wall:1, tower:1, barricade:1, pipe:1, obelisk:1, pillars:1, arch:1, buried:1 };
    // catch any NaN/Infinity reaching the canvas: a bad colour is silently ignored, a bad coordinate draws nothing
    const c = document.getElementById('btCv').getContext('2d'), P = CanvasRenderingContext2D.prototype;
    const fs = Object.getOwnPropertyDescriptor(P, 'fillStyle');
    window.bad = 0;
    Object.defineProperty(c, 'fillStyle', { set(v) { if (/NaN|Infinity/.test(String(v))) window.bad++; fs.set.call(this, v); }, get() { return fs.get.call(this); } });
    ['moveTo', 'lineTo'].forEach(k => { const o = c[k].bind(c); c[k] = (x, y) => { if (!isFinite(x) || !isFinite(y)) window.bad++; o(x, y); }; });
  });

  console.log('\n-- every terrain type on every theme --');
  const H = await p.evaluate(([THEMES, TERR]) => {
    const out = {};
    for (const tr of TERR) { out[tr] = { lo: 1e9, hi: -1e9, nan: 0, bad: 0, faces: 0 };
      for (const th of THEMES) for (const seed of [11, 202, 3003]) for (const w of [24, 48, 120]) {
        field(th, tr, true, 1, seed, w);
        const W = BT.table.w, D = BT.table.d;
        for (let x = -W/2; x <= W/2; x += W/40) for (let z = -D/2; z <= D/2; z += D/30) {
          const h = BT.heightAt(x, z); if (!isFinite(h)) out[tr].nan++; else { out[tr].lo = Math.min(out[tr].lo, h); out[tr].hi = Math.max(out[tr].hi, h); } }
        window.bad = 0; BT.fit(); BT.draw(); out[tr].bad += window.bad; out[tr].faces = Math.max(out[tr].faces, BT.faces());
      } }
    return out;
  }, [THEMES, TERR]);
  const range = { flat: [-1.5, 1.5], hills: [-11, 11], mountain: [-10, 22], forest: [-11, 11] };
  for (const tr of TERR) { const r = H[tr];
    ok(r.nan === 0 && r.bad === 0, `${tr}: no NaN in heights or on the canvas (${r.nan} / ${r.bad}), up to ${r.faces} faces`);
    ok(r.lo >= range[tr][0] && r.hi <= range[tr][1], `${tr}: heights ${r.lo.toFixed(1)}..${r.hi.toFixed(1)} inside ${range[tr].join('..')}`); }
  ok(H.mountain.hi - H.mountain.lo > 2 * (H.hills.hi - H.hills.lo) * 0.6 && H.mountain.hi > 10, `mountain is clearly higher than hills (${(H.mountain.hi-H.mountain.lo).toFixed(1)} vs ${(H.hills.hi-H.hills.lo).toFixed(1)} m span)`);
  ok(H.flat.hi - H.flat.lo < 2.5, `flat is flat (${(H.flat.hi-H.flat.lo).toFixed(2)} m span)`);

  const lvl = await p.evaluate(() => {   // houses on a mountain stand on level ground
    let worst = 0, n = 0; const falls = [];
    for (const seed of [5, 77, 901, 4242]) { field('ruin', 'mountain', true, 2.5, seed, 60);
      BT.props().filter(o => o.kind === 'building').forEach(o => { n++;
        const bw = (5 + o.h*7)*o.s, bd = (4.5 + 0)*o.s, c = Math.cos(o.rot), s = Math.sin(o.rot); let lo = 1e9, hi = -1e9;
        for (const [a, e] of [[0,0],[bw/2,bd/2],[-bw/2,bd/2],[bw/2,-bd/2],[-bw/2,-bd/2]]) { const h = BT.heightAt(o.x + a*c + e*s, o.z - a*s + e*c); lo = Math.min(lo, h); hi = Math.max(hi, h); }
        worst = Math.max(worst, hi - lo); falls.push(hi - lo); }); }
    falls.sort((a, b) => a - b);
    return { worst, n, p90: falls[Math.floor(falls.length * 0.9)], med: falls[falls.length >> 1] };
  });
  // two houses closer than a cell on a steep slope cannot both be flat: the first one levelled keeps its pad
  ok(lvl.n > 5 && lvl.p90 < 0.35 && lvl.worst < 1.5, `ground under ${lvl.n} mountain houses is level (median ${lvl.med.toFixed(2)}, 90% ${lvl.p90.toFixed(2)}, worst ${lvl.worst.toFixed(2)} m fall)`);
  const raw = await p.evaluate(() => { let worst = 0;   // for scale: how steep those spots are before levelling
    for (const seed of [5, 77, 901, 4242]) { BT.adoptRoom({ setup: { theme:'ruin', seed, w:60, terrain:'mountain', buildings:false, density:1, mode:'pve', teams:2, perTeam:1, budget:150, freeFire:false, clock:0 }, players: [] });
      for (let x = -25; x < 25; x += 3) for (let z = -18; z < 18; z += 3) { const a = [BT.heightAt(x-5,z-3), BT.heightAt(x+5,z-3), BT.heightAt(x-5,z+3), BT.heightAt(x+5,z+3)]; worst = Math.max(worst, Math.max(...a) - Math.min(...a)); } }
    return worst; });
  console.log(`   (unlevelled mountain ground falls up to ${raw.toFixed(1)} m across a 10x6 m footprint)`);

  console.log('\n-- buildings off --');
  const off = await p.evaluate(([THEMES, TERR]) => { let props = 0, st = 0, kinds = {};
    for (const th of THEMES) for (const tr of TERR) for (const seed of [3, 44, 555]) { field(th, tr, false, 2.5, seed, 60);
      BT.props().forEach(o => { props++; if (STR[o.kind]) { st++; kinds[o.kind] = 1; } }); }
    return { props, st, kinds: Object.keys(kinds) }; }, [THEMES, TERR]);
  ok(off.st === 0 && off.props > 100, `buildings off: ${off.props} natural props, ${off.st} structures ${off.kinds.join(',')}`);
  const offUI = await p.evaluate(() => { BT.setBuildings(true, 1); document.querySelector('#btBld button[data-b="0"]').click();
    return { on: BT.buildingsOf().on, sliderOff: document.getElementById('btDens').disabled, st: BT.props().filter(o => STR[o.kind]).length }; });
  ok(!offUI.on && offUI.sliderOff && offUI.st === 0, 'the ปิด button turns them off and greys the slider');
  await p.evaluate(() => document.querySelector('#btBld button[data-b="1"]').click());

  console.log('\n-- density few <-> many --');
  const dens = await p.evaluate(([THEMES]) => { const out = {};
    function blocked() { let n = 0, t = 0; const W = BT.table.w, D = BT.table.d;
      for (let x = -W/2 + 0.5; x < W/2; x += 1) for (let z = -D/2 + 0.5; z < D/2; z += 1) { t++; if (BT.blockAt(x, z)) n++; } return n / t; }
    for (const th of THEMES) { out[th] = {};
      for (const dn of [0.25, 1, 2.5]) { let st = 0, all = 0, bl = 0;
        for (const seed of [1, 2, 3, 4, 5, 6]) { field(th, 'hills', true, dn, seed * 101, 48); const P = BT.props(); all += P.length; st += P.filter(o => STR[o.kind]).length; bl += blocked(); }
        out[th][dn] = { st: st / 6, all: all / 6, bl: bl / 6 }; } }
    return out; }, [THEMES]);
  for (const th of THEMES) { const d = dens[th];
    console.log(`   ${th.padEnd(6)} structures ${d[0.25].st.toFixed(1)} / ${d[1].st.toFixed(1)} / ${d[2.5].st.toFixed(1)}  ·  blocked ${Math.round(d[0.25].bl*100)}% / ${Math.round(d[1].bl*100)}% / ${Math.round(d[2.5].bl*100)}%`);
    ok(d[0.25].st <= d[1].st && d[1].st < d[2.5].st, `${th}: fewer at น้อย, more at มาก`);
    ok(d[2.5].st >= 1.5 * Math.max(d[1].st, 3), `${th}: มาก does not saturate (${d[2.5].st.toFixed(1)} vs ${d[1].st.toFixed(1)} structures)`);
    ok(d[2.5].bl < 0.75, `${th}: มาก still leaves a quarter of the table to stand on (${Math.round(d[2.5].bl*100)}% blocked)`); }
  const slider = await p.evaluate(() => { const s = document.getElementById('btDens'); s.value = 2.5; s.dispatchEvent(new Event('input'));
    const a = BT.buildingsOf().density; s.value = 0.25; s.dispatchEvent(new Event('input')); return [a, BT.buildingsOf().density, document.getElementById('btDensV').textContent]; });
  ok(slider[0] === 2.5 && slider[1] === 0.25 && slider[2] === '×0.25', `the slider sets the density (${slider.join(' ')})`);

  console.log('\n-- deployment never lands inside a prop --');
  const dep = await p.evaluate(([THEMES]) => { let models = 0, inside = 0, stacked = 0, maps = 0, ms = 0; const bad = [];
    const cfgs = [['ffa', 8, 1, 300], ['team', 2, 4, 400], ['pvp', 2, 1, 600]];
    for (const th of THEMES) for (const tr of ['hills', 'mountain', 'forest']) for (const dn of [1, 2.5]) {
      const c = cfgs[(maps++) % cfgs.length];
      BT.quit(); field(th, tr, true, dn, 7 + maps * 131, c[1] * c[2] > 4 ? 90 : 48);
      BT.G.mode = c[0]; BT.G.teams = c[1]; BT.G.perTeam = c[2]; BT.G.budget = c[3]; BT.G.clock = 0;
      BT.mkPlayers(); BT.G.players.forEach((x, i) => { x.bot = true; x.list = [3, 4, 2, 3]; x.dep = null; });
      const t0 = performance.now(); BT.start(); ms = Math.max(ms, performance.now() - t0);
      BT.units.forEach((u, i) => { models++; if (BT.blockAt(u.x, u.z)) { inside++; bad.push(th + '/' + tr + '/' + dn); }
        BT.units.forEach((q, j) => { if (j > i && Math.hypot(q.x-u.x, q.z-u.z) < 1.5) stacked++; }); });
      BT.G.over = true; }
    BT.quit(); return { models, inside, stacked, maps, ms, bad: bad.slice(0, 5) }; }, [THEMES]);
  ok(dep.models >= 200, `${dep.models} models deployed over ${dep.maps} tables (every theme, hills/mountain/forest, density 1 and 2.5)`);
  ok(dep.inside === 0, `none inside a prop (${dep.inside}) ${dep.bad.join(' ')}`);
  ok(dep.stacked === 0, `none stacked on another (${dep.stacked})`);
  console.log(`   slowest deploy: ${dep.ms.toFixed(0)} ms`);
  const why = await p.evaluate(() => { field('ruin', 'hills', true, 2.5, 99, 48); BT.G.mode = 'pvp'; BT.G.teams = 2; BT.G.perTeam = 1; BT.mkPlayers();
    const o = BT.props().find(q => q.kind === 'building' && q.s > 1.1); if (!o) return null;
    return BT.depWhyNot(0, o.x, o.z); });
  ok(why && /สิ่งกีดขวาง/.test(why), 'a landing point in the middle of a house is refused: ' + why);

  ok(errs.length === 0, errs.length ? 'JS ERRORS: ' + errs.join(' | ') : 'no JS errors');
  console.log(`\n${pass} passed, ${fail} failed`);
  await b.close(); process.exit(fail ? 1 : 0);
})().catch(e => { console.error(e); process.exit(1); });
