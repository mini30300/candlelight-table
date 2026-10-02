// Round 8 data and rules: the 28 new datasheets (fallen knights and daemons 'cx', the knights' chapter units, the blue-skinned
// empire's hidden mech), the new army in the picker with its 17 units, chapter headings in the knights' roster, the hidden
// unit (not listed, not in random or bot lists, until this device unlocks it; remembered), the dark pact (melee 6s hit
// twice), rules version 9 / app 9.0, and bot games with the new units played to the end without page errors.
//   node r8_rules.js [page]
const { chromium } = require('playwright');
const PAGE = require('path').resolve(process.argv[2] || process.env.PAGE || require('path').resolve(__dirname, '../../app/src/main/assets/battle-table.html')), F = 'file://' + PAGE;
const APP_VER = (require('fs').readFileSync(PAGE, 'utf8').match(/var APP_VER = '([\d.]+)'/) || [])[1];   // the version the page says it is

let pass = 0, fail = 0; const ok = (c, m, x) => { c ? pass++ : fail++; console.log((c ? 'ok   ' : 'FAIL ') + m + (x !== undefined ? '  ' + JSON.stringify(x).slice(0, 700) : '')); };
const NEW = ['cxw', 'cxb', 'cxp', 'cxr', 'cxh', 'cxc', 'cxl', 'cxs', 'cxt', 'cxd', 'dmr', 'dmp', 'dmf', 'dmc', 'dmh', 'dmg', 'dmx',
             'kna1', 'kna2', 'knb1', 'knb2', 'knc1', 'knc2', 'knd1', 'knd2', 'kne1', 'kne2', 'tagm'];
const CH = { kna1: 'ภาคีฟ้าคราม', kna2: 'ภาคีฟ้าคราม', knb1: 'ภาคีปีกโลหิต', knb2: 'ภาคีปีกโลหิต', knc1: 'ภาคีเงาเขียว', knc2: 'ภาคีเงาเขียว',
             knd1: 'ภาคีหมาป่า', knd2: 'ภาคีหมาป่า', kne1: 'ภาคีกางเขนดำ', kne2: 'ภาคีกางเขนดำ' };
const FX = ['bolter', 'hbolter', 'plasma', 'melta', 'rocket', 'sniper', 'gatling', 'cannon', 'beam', 'chain', 'power', 'hammer', 'claw', 'bite', 'warp'];
(async () => {
  const b = await chromium.launch({ executablePath: process.env.CHROMIUM_PATH || undefined, args: ['--no-sandbox'] });
  const ctx = await b.newContext({ viewport: { width: 1280, height: 860 } });
  const p = await ctx.newPage();
  const errs = []; p.on('pageerror', e => errs.push(String(e.stack || e).slice(0, 500)));
  await p.goto(F); await p.waitForFunction('window.BT && window.BT.G'); await p.waitForTimeout(200);
  const E = (f, a) => p.evaluate(f, a);
  const helpers = () => E(() => {
    window.T = {
      L(arr){ const l = new Array(BT.TYPES.length).fill(0); arr.forEach(([k, n]) => { l[BT.TYPES.findIndex(t => t.k === k)] = n; }); return l; },
      setup(A, B, o){ o = o || {}; BT.clock(false); BT.quit(); BT.setTerrain('flat'); BT.setBuildings(false); BT.size(80);
        BT.G.mode = 'pvp'; BT.G.teams = 2; BT.G.perTeam = 1; BT.G.freeFire = false; BT.G.clock = 0; BT.G.budget = 40000;
        BT.G.goal = o.goal || 'obj'; BT.G.rounds = o.rounds || 5; BT.mkPlayers();
        BT.setList(0, T.L(A)); BT.setList(1, T.L(B)); BT.players()[0].dep = [-30, 0]; BT.players()[1].dep = [30, 0];
        BT.setAuto(true); BT.start(); BT.dice([]); },
      sq(pl, k, i){ return BT.squads().filter(s => s.pl === pl && s.k === k)[i || 0]; },
      settle(){ for (let i = 0; i < 900 && (BT.walking() || BT.tray().q || (BT.tray().cur && !BT.tray().cur.settled) || BT.pend().length); i++){ BT.flush(true); BT.tick(1/30, 3); } },
      near(a, b, gap){ const m = BT.sqModels(b)[0]; BT.place(a.id, m.x - gap, m.z, Math.PI/2); },
      lastHits(){ const l = BT.log().map(x => x.t.replace(/<[^>]+>/g, '')).reverse().find(t => / — เข้า \d+\/\d+/.test(t)); const m = l && / — เข้า (\d+)\/(\d+)/.exec(l); return m ? [+m[1], +m[2]] : null; }
    }; });
  await helpers();

  console.log('# the datasheets');
  let r = await E((NEW) => { const T = BT.TYPES, keys = T.map(t => t.k), by = {}; T.forEach(t => { by[t.fac] = (by[t.fac] || 0) + 1; });
    return { n: T.length, tail: keys.slice(246), dup: keys.filter((k, i) => keys.indexOf(k) !== i), by,
      facs: [...document.querySelectorAll('#btFacs .mode')].map(b => b.dataset.f) }; }, NEW);
  ok(r.n === 274 && JSON.stringify(r.tail) === JSON.stringify(NEW) && !r.dup.length, '274 datasheets: the 28 new ones appended at the end in the plan\'s order, no key twice', { n: r.n, dup: r.dup });
  ok(r.by.cx === 17 && r.by.kn === 42 && r.by.ta === 30, '17 in the new army, 42 power-armour knights (10 in chapters), 30 of the blue-skinned empire', r.by);
  ok(r.facs.length === 15 && r.facs[14] === 'cx', 'fifteen armies in the picker, the new one last', r.facs);
  r = await E(({ NEW, CH, FX }) => { const bad = [], num = v => typeof v === 'number' && isFinite(v);
    const thai = s => typeof s === 'string' && /[฀-๿]/.test(s);
    NEW.forEach(k => { const T = BT.TYPES.find(t => t.k === k);
      ['n', 'pts', 'mv', 'T', 'sv', 'w', 'ld', 'oc'].forEach(f => { if (!num(T[f]) || T[f] < 0) bad.push(k + '.' + f); });
      if (!(T.n >= 1 && T.pts > 0 && T.mv >= 3 && T.T >= 2 && T.sv >= 2 && T.sv <= 7 && T.w >= 1 && T.ld >= 4 && T.ld <= 8)) bad.push(k + ' range');
      if (T.inv != null && !(T.inv >= 3 && T.inv <= 6)) bad.push(k + '.inv');
      if (!thai(T.nm) || !thai(T.d) || T.d.length < 20) bad.push(k + ' Thai name/description');
      if (!T.mel || !thai(T.mel.nm) || !['a', 'ws', 's', 'ap', 'd'].every(f => num(T.mel[f]))) bad.push(k + '.mel');
      if (T.gun && (!thai(T.gun.nm) || !['rng', 'a', 's', 'ap', 'd'].every(f => num(T.gun[f])) || !(T.gun.tr || num(T.gun.bs)))) bad.push(k + '.gun');
      [T.gun, T.mel].forEach(W => { if (W && W.fx != null && !FX.includes(W.fx)) bad.push(k + ' fx ' + W.fx); });
      if (k.startsWith('cx') || k.startsWith('dm')) { if (T.fac !== 'cx') bad.push(k + ' army'); }
      else if (CH[k]) { if (T.fac !== 'kn' || T.ch !== CH[k]) bad.push(k + ' chapter'); }
      else if (k === 'tagm') { if (T.fac !== 'ta' || T.lk !== 'ta' || T.sec) bad.push(k + ' hidden'); }
      if (k.startsWith('dm') && T.inv !== 5) bad.push(k + ' daemon save');
      if (k.startsWith('dm') && !T.brave) bad.push(k + ' daemon brave');
    });
    const withFx = NEW.filter(k => { const T = BT.TYPES.find(t => t.k === k); return (T.gun && T.gun.fx) || T.mel.fx; }).length;
    const tg = BT.TYPES.find(t => t.k === 'tagm'), ta = BT.TYPES.filter(t => t.fac === 'ta' && !t.lk);
    return { bad, withFx, tg: { pts: tg.pts, T: tg.T, w: tg.w, fly: tg.fly, ttn: tg.ttn, gun: tg.gun, mel: tg.mel }, taMax: Math.max(...ta.map(t => t.pts)) }; }, { NEW, CH, FX });
  ok(!r.bad.length, 'every new datasheet is complete: stats in range, Thai names and descriptions, weapons whole, the fx kinds known, army/chapter/hidden right, daemons 5++ and fearless', r.bad);
  ok(r.withFx >= 25, 'the new weapons carry an fx kind where one fits (' + r.withFx + ' of 28 units)', r.withFx);
  ok(r.tg.pts > r.taMax && r.tg.T >= 12 && r.tg.w >= 30 && r.tg.fly && r.tg.ttn && r.tg.gun.s >= 14 && r.tg.mel.s >= 14, 'the hidden mech is very strong and the dearest unit of its army (' + r.tg.pts + ' pts)', r.tg);
  // points in line with the old units: a rough value (damage dealt x wounds it takes x speed) against the points
  r = await E(() => { const wn = (S, T) => S >= 2*T ? 2 : S > T ? 3 : S === T ? 4 : 2*S <= T ? 6 : 5;
    const TG = [{ T:4, sv:3, w:2 }, { T:3, sv:5, w:1 }, { T:10, sv:3, w:12 }, { T:5, sv:2, inv:4, w:3 }];
    const dmg = (W, n, melee, t) => { if (!W) return 0; const bs = melee ? W.ws : W.bs, ph = W.tr ? 1 : Math.max(1, 7 - Math.max(2, bs))/6 + (W.su ? 1/6 : 0);
      let pw = Math.max(1, 7 - wn(W.s, t.T))/6; if (W.po && t.T <= 5 && t.w <= 3) pw = Math.max(pw, (7 - W.po)/6);
      const sv = Math.min(t.sv + (W.ap || 0), t.inv || 7), pf = sv > 6 ? 1 : (sv - 1)/6;
      return n*(W.a + (W.bl && !melee ? 1 : 0))*(W.rf ? 1.3 : 1)*ph*pw*pf*Math.min(W.d, t.w)*(W.rng ? Math.min(1.3, 0.7 + W.rng/60) : 1); };
    const val = T => { let o = 0; TG.forEach(t => { o += dmg(T.gun, T.n, false, t) + 0.8*dmg(T.mel, T.n, true, t)*(T.ca ? 1.2 : 1); }); o /= TG.length;
      const pw = Math.max(1, 7 - wn(5, T.T))/6, sv = Math.min(T.sv + 1, T.inv || 7), pf = sv > 6 ? 1 : (sv - 1)/6;
      const d = T.n*T.w/(pw*pf)*(T.st ? 1.2 : 1)*(T.hd ? 2 : 1)*(T.vsh ? 1 + T.vsh*0.1 : 1);
      return Math.sqrt(o*d)*(1 + (T.mv - 6)/24)*(T.fly ? 1.1 : 1)*(T.hero ? 1.15 : 1)*(T.aura ? 1.1 : 1)*(T.heal ? 1.2 : 1); };
    const old = BT.TYPES.slice(0, 246).filter(T => !T.sec).map(T => T.pts/val(T)), lo = Math.min(...old), hi = Math.max(...old);
    // the secret mech is priced like the secret hero (40,000), outside the normal spread
    const out = BT.TYPES.slice(246).filter(T => T.k !== 'tagm').map(T => [T.k, +(T.pts/val(T)).toFixed(2)]).filter(([k, v]) => v < lo || v > hi);
    return { lo: +lo.toFixed(2), hi: +hi.toFixed(2), out }; });
  ok(!r.out.length, 'the new units\' points per rough value sit inside the old units\' spread (' + r.lo + ' .. ' + r.hi + ')', r.out);

  // actions, fliers and squad looks (page tables outside the rules): every new key attacks as its figure was built for
  r = (() => { const src = require('fs').readFileSync(F.replace(/^file:\/\//, ''), 'utf8'), lit = (name, open, close) => { const i = src.indexOf('var ' + name + ' = ' + open);
      return eval('(' + src.slice(i + ('var ' + name + ' = ').length, src.indexOf(close, i) + close.indexOf('}') + 1) + ')'); };
    const ANIM = lit('ANIM', '{', '\n};'), FLY = lit('FLY_K', '{', '};'), VAR = lit('VARIANTS', '{', '};');
    const T = eval(src.slice(src.indexOf('var TYPES = [') + 'var TYPES = '.length, src.indexOf('\n];', src.indexOf('var TYPES = [')) + 3));
    const R = ['fire', 'turret', 'cast', 'beam', 'flame', 'spray', 'breath', 'gaze', 'throw', 'hurl', 'lob', 'bow', 'zap'], M = ['bash', 'swing', 'swing2', 'twin', 'claw', 'thrust', 'lunge'];
    const bad = [];
    NEW.forEach(k => { const A = ANIM[k], D = T.find(t => t.k === k);
      if (!A) { bad.push(k + ' no ANIM'); return; }
      if (!M.includes(A.m)) bad.push(k + ' melee ' + A.m);
      if (D.gun && !R.includes(A.r)) bad.push(k + ' shoots with ' + A.r);
      if (D.fly && !FLY[k]) bad.push(k + ' flies without FLY_K');
      if (FLY[k] && !D.fly) bad.push(k + ' FLY_K but no fly'); });
    Object.keys(VAR).forEach(k => { if (!ANIM[k]) bad.push('VARIANTS ' + k + ' without ANIM'); if (VAR[k][0] !== k) bad.push('VARIANTS ' + k + ' first look'); });
    return { bad, fly: NEW.filter(k => FLY[k]), looks: NEW.filter(k => VAR[k]) }; })();
  ok(!r.bad.length && r.fly.length === 7 && r.looks.length >= 13, 'every new key has an attack entry (' + NEW.length + '), the 7 fliers their hover, ' + r.looks.length + ' squads their mixed looks (each with an attack entry)', r);

  console.log('# version');
  r = await E(() => ({ ver: document.getElementById('btVer').textContent, v: BT.board().v }));
  ok(r.ver === 'เวอร์ชัน ' + APP_VER && r.v === 9, 'the version label matches APP_VER and the rules are version 9', r);

  console.log('# the army picker and the rosters');
  await p.click('#btNext'); await p.waitForTimeout(200);
  const roster = () => E(() => [...document.getElementById('btRoster').children].map(x => x.classList.contains('chh') ? 'H:' + x.querySelector('span').textContent
    : BT.TYPES[+x.querySelector('button[data-i]').dataset.i].k));
  await p.click('#btFacs .mode[data-f="cx"]'); await p.waitForTimeout(120);
  r = await E(() => ({ on: document.querySelector('#btFacs .mode[data-f="cx"]').classList.contains('on'), svg: !!document.querySelector('#btFacs .mode[data-f="cx"] svg path'),
    t: document.querySelector('#btFacs .mode[data-f="cx"] .t').textContent, rows: document.querySelectorAll('#btRoster .unit').length,
    heads: document.querySelectorAll('#btRoster .chh').length, wide: document.documentElement.scrollWidth - window.innerWidth }));
  let rs = await roster();
  ok(r.on && r.svg && r.t === 'อัศวินทรยศกับปีศาจ' && r.rows === 17 && JSON.stringify(rs) === JSON.stringify(NEW.slice(0, 17)) && !r.heads,
     'the new army\'s card (with its line drawing) lists its 17 units, no headings', { r, rs });
  ok(r.wide <= 1, 'the roster does not scroll sideways', r.wide);
  r = await E(() => BT.TYPES.filter(t => t.fac === 'cx').map(t => BT.abilityText(t)));
  ok(r.every(a => /สัญญาปีศาจ/.test(a)), 'every unit of the new army shows the dark pact among its abilities', r.slice(0, 2));
  await p.click('#btFacs .mode[data-f="kn"]'); await p.waitForTimeout(120);
  rs = await roster();
  const heads = rs.filter(x => x.startsWith('H:')).map(x => x.slice(2)), after = h => rs.slice(rs.indexOf('H:' + h) + 1, rs.indexOf('H:' + h) + 3);
  ok(rs.filter(x => !x.startsWith('H:')).length === 42 && JSON.stringify(heads) === JSON.stringify(['หน่วยทั่วไป', 'ภาคีฟ้าคราม', 'ภาคีปีกโลหิต', 'ภาคีเงาเขียว', 'ภาคีหมาป่า', 'ภาคีกางเขนดำ']),
     'the knights\' roster: 42 units under a heading for the common units and one for each of the five chapters', heads);
  ok(rs[0] === 'H:หน่วยทั่วไป' && JSON.stringify(after('ภาคีฟ้าคราม')) === '["kna1","kna2"]' && JSON.stringify(after('ภาคีปีกโลหิต')) === '["knb1","knb2"]' &&
     JSON.stringify(after('ภาคีเงาเขียว')) === '["knc1","knc2"]' && JSON.stringify(after('ภาคีหมาป่า')) === '["knd1","knd2"]' && JSON.stringify(after('ภาคีกางเขนดำ')) === '["kne1","kne2"]',
     'each chapter heading sits right over its two units', rs.slice(-16));
  r = await E(() => ({ bad: BT.TYPES.filter(t => t.fac === 'kn' && !t.ch).length && BT.TYPES.filter(t => t.fac === 'kn' && t.ch).some(t => BT.TYPES.indexOf(t) < 246),
    ab: BT.abilityText(BT.TYPES.find(t => t.k === 'knight')) }));
  ok(!r.bad && !/สัญญาปีศาจ/.test(r.ab), 'the old knights have no chapter and no dark pact', r);
  await p.click('#btFacs .mode[data-f="sw"]'); await p.waitForTimeout(100);
  ok(!(await E(() => document.querySelectorAll('#btRoster .chh').length)), 'an army without chapters gets no headings');
  for (const [w, h] of [[390, 844], [360, 740]]) {         // phones: the new card, the new roster and the headings fit
    const cp = await b.newContext({ viewport: { width: w, height: h } }), pp = await cp.newPage(); pp.on('pageerror', e => errs.push('phone: ' + String(e).slice(0, 300)));
    await pp.goto(F); await pp.waitForFunction('window.BT && window.BT.G'); await pp.click('#btNext'); await pp.waitForTimeout(150);
    const q = [];
    for (const f of ['cx', 'kn']) { await pp.click('#btFacs .mode[data-f="' + f + '"]'); await pp.waitForTimeout(100);
      q.push(await pp.evaluate(() => { const hs = [...document.querySelectorAll('#btRoster .chh')], R = document.getElementById('btRoster').getBoundingClientRect();
        return { wide: document.documentElement.scrollWidth - window.innerWidth, rows: document.querySelectorAll('#btRoster .unit').length,
          heads: hs.length, inside: hs.every(x => { const r = x.getBoundingClientRect(); return r.left >= R.left - 1 && r.right <= R.right + 1 && r.height < 40; }),
          card: (() => { const r = document.querySelector('#btFacs .mode[data-f="cx"]').getBoundingClientRect(); return r.right <= window.innerWidth + 1 && r.width > 100; })() }; })); }
    ok(q.every(x => x.wide <= 1 && x.inside && x.card) && q[0].rows === 17 && q[1].rows === 42 && q[1].heads === 6, w + 'x' + h + ': the new card, its roster and the chapter headings fit without sideways scrolling', q);
    await cp.close(); }

  console.log('# the hidden mech: not before it is unlocked');
  await p.click('#btFacs .mode[data-f="ta"]'); await p.waitForTimeout(120);
  r = await E(() => ({ rows: document.querySelectorAll('#btRoster .unit').length, tagm: [...document.querySelectorAll('#btRoster button[data-i]')].some(b => BT.TYPES[+b.dataset.i].k === 'tagm'),
    pal: !!document.querySelector('#btKit button[data-k="tagm"]'), pal2: !!document.querySelector('#btKit button[data-k="taguevesa"]'), ls: localStorage.getItem('bt_secret_ta') }));
  ok(r.rows === 29 && !r.tagm && !r.pal && r.pal2 && r.ls === null, 'the blue-skinned empire lists 29 units: no mech in the roster or the free-placement palette', r);
  // never in bot or random lists: seeded bots over many tables, "random" presses of the army and of everything
  const neverIn = () => E(() => { const I = BT.TYPES.findIndex(t => t.k === 'tagm'), D = BT.TYPES.findIndex(t => t.k === 'doom'); let got = 0, cx = 0, lists = 0, taL = 0;
    BT.quit(); BT.G.mode = 'spectator'; BT.G.teams = 4; BT.G.perTeam = 1;
    for (const bud of [500, 2000, 12000, 40000]) { BT.G.budget = bud;
      for (let sd = 1; sd <= 30; sd++) { BT.seed(sd * 7 + bud); BT.mkPlayers(); for (let i = 0; i < 4; i++) { BT.players()[i].bot = true; BT.autoList(i); const L = BT.players()[i].list; lists++;
        if (L[I] || L[D]) got++; if (BT.players()[i].fac === 'cx') cx++; } } }
    BT.G.mode = 'pve'; BT.G.teams = 2; BT.mkPlayers();
    for (const bud of [2000, 40000]) { BT.G.budget = bud; for (let k = 0; k < 40; k++) { BT.players()[0].fac = 'ta'; BT.autoList(0, true); taL++; if (BT.players()[0].list[I]) got++; } }
    return { got, cx, lists, taL }; });
  r = await neverIn();
  ok(r.got === 0 && r.cx > 0, 'no bot or random list ever holds the mech (or the secret hero); bots do pick the new army (' + r.cx + ' of ' + r.lists + ' bot lists)', r);
  await E(() => { BT.quit(); BT.G.mode = 'pve'; }); await p.reload(); await p.waitForFunction('window.BT && window.BT.G'); await helpers();
  await p.click('#btNext'); await p.waitForTimeout(200);
  // near misses of the unlock do nothing, and neither does another army's card
  for (let i = 0; i < 6; i++) await p.click('#btFacs .mode[data-f="ta"]');
  await p.waitForTimeout(4200);
  for (let i = 0; i < 3; i++) await p.click('#btFacs .mode[data-f="ta"]');
  for (let i = 0; i < 9; i++) await p.click('#btFacs .mode[data-f="de"]');
  r = await E(() => ({ ls: localStorage.getItem('bt_secret_ta'), rows: (document.querySelector('#btFacs .mode[data-f="ta"]').click(), document.querySelectorAll('#btRoster .unit').length) }));
  ok(r.ls === null && r.rows === 29, 'near misses of the unlock, or another army\'s card: still hidden', r);

  console.log('# unlocking it');
  await p.waitForTimeout(4100);
  for (let i = 0; i < 7; i++) await p.click('#btFacs .mode[data-f="ta"]');
  await p.waitForTimeout(150);
  r = await E(() => ({ ls: localStorage.getItem('bt_secret_ta'), toast: document.getElementById('btDice').textContent, on: document.getElementById('btDice').classList.contains('on'),
    rows: document.querySelectorAll('#btRoster .unit').length, first: BT.TYPES[+document.querySelector('#btRoster button[data-i]').dataset.i].k,
    nm: document.querySelector('#btRoster .unit .nm').textContent, pal: !!document.querySelector('#btKit button[data-k="tagm"]'), doom: localStorage.getItem('bt_secret') }));
  ok(r.ls === '1' && r.on && /ปลดล็อกหน่วยลับ/.test(r.toast) && /หุ่นรบนักบินฟ้า/.test(r.toast), 'the unlock: a toast, and the device remembers it', r);
  ok(r.rows === 30 && r.first === 'tagm' && /หน่วยลับ/.test(r.nm) && r.pal && r.doom === null, 'the mech now heads the empire\'s roster (30 units) and is in the palette; the secret hero stays hidden', r);
  r = await neverIn();
  ok(r.got === 0, 'unlocked or not, random and bot lists never take it', r);
  await E(() => { BT.quit(); }); await p.reload(); await p.waitForFunction('window.BT && window.BT.G'); await helpers();
  await p.click('#btNext'); await p.waitForTimeout(200); await p.click('#btFacs .mode[data-f="ta"]'); await p.waitForTimeout(120);
  r = await E(() => ({ rows: document.querySelectorAll('#btRoster .unit').length, first: BT.TYPES[+document.querySelector('#btRoster button[data-i]').dataset.i].k, pal: !!document.querySelector('#btKit button[data-k="tagm"]') }));
  ok(r.rows === 30 && r.first === 'tagm' && r.pal, 'after reopening the page it is still unlocked', r);
  // it can be taken like the secret hero: free of the points budget, one per player
  r = await E(() => { const i = BT.TYPES.findIndex(t => t.k === 'tagm'), plus = () => document.querySelector('#btRoster button[data-i="' + i + '"][data-v="1"]');
    plus().click(); const dis = plus().disabled; plus().click();
    return { n: BT.players()[0].list[i], used: document.getElementById('btUsedV').textContent, over: document.getElementById('btBar').classList.contains('over'),
      start: document.getElementById('btStart').disabled, dis, row: plus().closest('.unit').textContent }; });
  ok(r.n === 1 && /^0 \//.test(r.used) && !r.over && !r.start && r.dis && /หน่วยลับ ไม่นับแต้ม/.test(r.row), 'the plus button takes one into the army free of the budget, the army can be sent, and a second is refused', r);
  // on another device (a fresh browser) a list holding it still works: the datasheet is always there
  const c2 = await b.newContext({ viewport: { width: 1000, height: 700 } }); const p2 = await c2.newPage(); p2.on('pageerror', e => errs.push('B: ' + String(e).slice(0, 300)));
  await p2.goto(F); await p2.waitForFunction('window.BT && window.BT.G');
  r = await p2.evaluate(() => { const L = new Array(BT.TYPES.length).fill(0); L[BT.TYPES.findIndex(t => t.k === 'tagm')] = 3; L[BT.TYPES.findIndex(t => t.k === 'tafw')] = 1;
    BT.clock(false); BT.G.mode = 'pvp'; BT.G.budget = 2000; BT.mkPlayers(); BT.setList(0, L); BT.setList(1, L.slice());
    BT.setDep(0, -20, 0); BT.setDep(1, 20, 0); BT.start();
    return { sq: BT.squads().filter(s => s.k === 'tagm').length, ls: localStorage.getItem('bt_secret_ta'), card: (BT.select(BT.squads().find(s => s.k === 'tagm')), document.getElementById('btCard').textContent) }; });
  ok(r.sq === 2 && r.ls === null && /หน่วยลับ/.test(r.card), 'a device that never unlocked it still plays a list holding it, cut to one per player', r);
  await c2.close();

  console.log('# the dark pact: melee 6s to hit score an extra hit');
  r = await E(() => { T.setup([['cxb', 1], ['dmr', 1], ['cxw', 1]], [['kblade', 1], ['heavy', 2]]);
    const cb = T.sq(0, 'cxb'), dm = T.sq(0, 'dmr'), cw = T.sq(0, 'cxw'), kb = T.sq(1, 'kblade'), h = T.sq(1, 'heavy'), h2 = T.sq(1, 'heavy', 1);
    T.near(cb, h, 0.3); T.near(dm, h2, 0.3); T.near(kb, cw, 0.3);
    const out = { suCxb: BT.atkMath(cb.id, h.id, 'fight').su, suGun: BT.atkMath(cw.id, h.id, 'shoot').su, suFoe: BT.atkMath(kb.id, cw.id, 'fight').su };
    const six = n => new Array(n).fill(6), mix = (n, k) => new Array(n).fill(1).map((v, i) => i < k ? 6 : 2), one = n => new Array(n).fill(1);
    BT.shootAt(cb.id, h.id, { hit: mix(20, 8), wound: one(40), save: one(40) }, 'fight'); T.settle(); out.cxb = T.lastHits();
    BT.shootAt(kb.id, cw.id, { hit: mix(20, 8), wound: one(40), save: one(40) }, 'fight'); T.settle(); out.kb = T.lastHits();
    T.near(cw, h2, 10); BT.shootAt(cw.id, h2.id, { hit: mix(10, 4), wound: one(20), save: one(20) }, 'shoot'); T.settle(); out.cwShoot = T.lastHits();
    return out; });
  ok(r.suCxb === 1 && r.suGun === 0 && r.suFoe === 0, 'the new army\'s melee attacks carry the dark pact; its guns and other armies\' blades do not', r);
  ok(JSON.stringify(r.cxb) === '[16,20]' && JSON.stringify(r.kb) === '[8,20]' && JSON.stringify(r.cwShoot) === '[4,10]',
     'eight 6s out of 20 blows: the berserkers score 16 hits, the knights with blades 8; shooting 4 of 10 stays 4', r);
  r = await E(() => { const cw = T.sq(0, 'cxw'); BT.select(cw); return document.getElementById('btCard').innerHTML; });
  ok(/สัญญาปีศาจ/.test(r), 'the unit card shows the dark pact', r.slice(0, 200));
  r = await E(() => { T.setup([['kna1', 1]], [['heavy', 1]]); BT.select(T.sq(0, 'kna1')); return document.getElementById('btCard').textContent; });
  ok(/ภาคีฟ้าคราม/.test(r), 'a chapter unit\'s card names its chapter', r.slice(0, 120));

  console.log('# bot games');
  const game = (o) => E((o) => { BT.clock(false); BT.quit(); BT.setTerrain(o.ter || 'ruin'); BT.size(o.size || 80); BT.G.budget = 40000; BT.G.goal = o.goal; BT.G.rounds = o.rounds || 5;
    BT.G.mode = o.teams > 2 ? 'ffa' : 'pve'; BT.G.teams = o.teams; BT.G.perTeam = 1; BT.mkPlayers();
    o.lists.forEach((a, i) => BT.setList(i, T.L(a)));
    BT.players().forEach((P, i) => { const an = i / o.teams * Math.PI * 2; P.dep = [Math.round(Math.cos(an) * 30), Math.round(Math.sin(an) * 18)]; });
    BT.start(); BT.players().forEach(P => P.bot = true);
    let k = 0; while (!BT.G.over && k < o.steps){ BT.botStep(); BT.tick(1/30, 2); k++; }
    const seen = {}; BT.log().forEach(l => { const t = l.t.replace(/<[^>]+>/g, ''); ['หุ่นรบนักบินฟ้า', 'ราชาปีศาจปีก', 'กองเกียรติยศฟ้า', 'นักรบคลั่งเลือด', 'ปีศาจโลหิต'].forEach(n => { if (t.includes(n)) seen[n] = 1; }); });
    return { over: BT.G.over, round: BT.G.round, k, live: [0, 1, 2, 3].slice(0, o.teams).map(t => BT.live(t)), seen: Object.keys(seen), last: BT.log().slice(-1)[0].t.replace(/<[^>]+>/g, '') }; }, o);
  r = await game({ goal: 'obj', rounds: 5, teams: 2, steps: 20000, lists: [
    [['cxw', 2], ['cxb', 1], ['cxp', 1], ['cxr', 1], ['cxh', 1], ['cxc', 1], ['cxl', 1], ['cxs', 1], ['cxt', 1], ['cxd', 1], ['dmr', 1], ['dmp', 1], ['dmf', 1], ['dmc', 1], ['dmh', 1], ['dmg', 1], ['dmx', 1]],
    [['knight', 1], ['kna1', 1], ['kna2', 1], ['knb1', 1], ['knb2', 1], ['knc1', 1], ['knc2', 1], ['knd1', 1], ['knd2', 1], ['kne1', 1], ['kne2', 1], ['ktank', 1]] ] });
  ok(r.over && r.round <= 5, 'the new army against the knights\' chapters: a 5-round bot game plays to its end', r);
  r = await game({ goal: 'kill', teams: 4, steps: 30000, size: 100, lists: [
    [['cxw', 1], ['dmr', 1], ['dmg', 1], ['cxs', 1]], [['kne2', 1], ['knd1', 1], ['kna2', 1]],
    [['tagm', 1], ['tafw', 1], ['tapath', 1]], [['dewar', 1], ['dewych', 1], ['deravager', 1]] ] });
  ok(r.over, 'a four-army fight to the death (new army, chapters, the empire with its mech, dark elves) plays to its end', r);
  ok(errs.length === 0, 'no page errors', errs.slice(0, 3));
  console.log(`\n${pass}/${pass + fail} passed`);
  await b.close(); process.exit(fail ? 1 : 0);
})().catch(e => { console.error('THREW', e); process.exit(2); });
