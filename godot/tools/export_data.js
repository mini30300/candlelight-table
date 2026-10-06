#!/usr/bin/env node
// export_data.js — pull the battle table's data tables out of battle-table.html into godot/data/*.json
// for the Godot 4 port. Read-only on the page. Run:  node godot/tools/export_data.js
//   PAGE=<battle-table.html>  another copy of the page (default app/src/main/assets/battle-table.html)
//   CHROMIUM_PATH=<chrome>    the browser Playwright should use (BT.TYPES is read from the live page)
// Two sources: `window.BT.TYPES` from the running page (Playwright), and the literals of the tables that live
// inside the game IIFE, cut from the source text and evaluated in a `vm` sandbox (unknown helpers are stubbed).
'use strict';
const fs = require('fs'), path = require('path'), vm = require('vm');

const ROOT = path.resolve(__dirname, '..', '..');
const PAGE = path.resolve(process.env.PAGE || path.join(ROOT, 'app/src/main/assets/battle-table.html'));
const OUT = path.join(ROOT, 'godot/data');
const { chromium } = require(path.join(ROOT, 'tests/node_modules/playwright'));

const src = fs.readFileSync(PAGE, 'utf8');
const lines = src.split('\n');
const report = { files: [], stubs: {}, fnKeys: {}, missing: [], notes: [] };

// ---------- cutting a literal out of the source ----------
// index of an anchor; the first occurrence after `after` (an index). Fails loudly when it is not there.
function at(anchor, after){ const i = src.indexOf(anchor, after || 0); if (i < 0) throw new Error('anchor not found: ' + anchor); return i; }
function lineOf(i){ return src.slice(0, i).split('\n').length; }

// scan one expression from `from`: stops at `;` or `,` at depth 0. Strings, template strings, comments and
// regex literals are skipped so braces inside them do not count.
function scanExpr(from){
  let i = from, depth = 0, last = '';                       // last = previous significant char (for regex detection)
  while (i < src.length){
    const c = src[i], n = src[i + 1];
    if (c === '/' && n === '/'){ i = src.indexOf('\n', i); if (i < 0) i = src.length; continue; }
    if (c === '/' && n === '*'){ i = src.indexOf('*/', i) + 2; continue; }
    if (c === '"' || c === "'" || c === '`'){
      i++; while (i < src.length && src[i] !== c){ if (src[i] === '\\') i++; i++; } i++; last = c; continue; }
    if (c === '/' && /^[(,=:[!&|?{};]?$/.test(last)){     // a regex literal, not a division
      i++; let cls = false; while (i < src.length){ const r = src[i]; if (r === '\\'){ i += 2; continue; }
        if (cls){ if (r === ']') cls = false; } else if (r === '[') cls = true; else if (r === '/') break; i++; }
      i++; while (/[a-z]/.test(src[i] || '')) i++; last = '/'; continue; }
    if (c === '{' || c === '[' || c === '(') depth++;
    else if (c === '}' || c === ']' || c === ')') depth--;
    else if (depth === 0 && (c === ';' || c === ',')) return { text: src.slice(from, i), end: i };
    if (!/\s/.test(c)) last = c;
    i++;
  }
  throw new Error('unterminated expression at ' + from);
}

// the initializer of `name` in the statement that starts at `anchor` (`var A = …, B = …;` works for B too)
function initOf(anchor, name, after){
  const a = at(anchor, after), n = name || anchor.replace(/^var\s+/, '').replace(/\s*=.*$/, '');
  const re = new RegExp('\\b' + n + '\\s*=\\s*'), m = re.exec(src.slice(a, a + 200000));
  if (!m) throw new Error('no initializer for ' + n + ' after ' + anchor);
  const from = a + m.index + m[0].length, r = scanExpr(from);
  return { text: r.text, line: lineOf(a), end: r.end, name: n };
}

// evaluate a literal in a bare vm context; any identifier it reaches for is stubbed and recorded
function evalLit(text, label){
  const ctx = vm.createContext({});
  const code = '(function(){ var __stubs = [];\n' +
    'var __S = new Proxy({}, { has: function(t, k){ return typeof k === "string" && !(k in globalThis); },\n' +
    '  get: function(t, k){ if (k === Symbol.unscopables) return undefined; if (__stubs.indexOf(k) < 0) __stubs.push(k); return function(){ return 0; }; } });\n' +
    'var __v = (function(){ with (__S) { return (\n' + text + '\n); } })();\nreturn { v: __v, stubs: __stubs }; })()';   // `return` reaches no identifier through the `with`
  const r = vm.runInContext(code, ctx, { filename: label });
  if (r.stubs.length) report.stubs[label] = r.stubs;
  return JSON.parse(JSON.stringify(r.v, (k, v) => typeof v === 'function' ? '__FN__' : v));
}
function lit(anchor, name, after){ const d = initOf(anchor, name, after); return { v: evalLit(d.text, d.name), line: d.line }; }

// drop function-valued keys (marked by evalLit) and remember where they were
function dataOnly(obj, label, p){
  if (Array.isArray(obj)) return obj.map((x, i) => dataOnly(x, label, (p || '') + '[' + i + ']'));
  if (obj && typeof obj === 'object'){ const o = {}; for (const k in obj){
    if (obj[k] === '__FN__'){ (report.fnKeys[label] = report.fnKeys[label] || []).push((p ? p + '.' : '') + k); continue; }
    o[k] = dataOnly(obj[k], label, (p ? p + '.' : '') + k); } return o; }
  return obj;
}

function write(name, data){
  const text = JSON.stringify(data, null, 2) + '\n', fp = path.join(OUT, name);
  fs.writeFileSync(fp, text);
  if (JSON.stringify(JSON.parse(text)) !== JSON.stringify(data)) throw new Error(name + ' does not round-trip');   // JSON round-trip
  report.files.push({ name, bytes: Buffer.byteLength(text) });
}
function opt(fn, what){ try { return fn(); } catch (e){ report.missing.push(what + ': ' + e.message); return undefined; } }

// ---------- BT.TYPES from the live page ----------
async function pageTypes(){
  const b = await chromium.launch({ executablePath: process.env.CHROMIUM_PATH || undefined, args: ['--no-sandbox'] });
  try {
    const p = await b.newPage({ viewport: { width: 1280, height: 800 } });
    p.on('pageerror', e => console.error('page error:', e.message));
    await p.goto('file://' + PAGE);
    await p.waitForFunction('window.BT && window.BT.G');
    await p.waitForTimeout(300);
    return await p.evaluate(() => ({ types: JSON.parse(JSON.stringify(window.BT.TYPES)), n: window.BT.TYPES.length,
      ver: (document.getElementById('btVer') || {}).textContent || '' }));
  } finally { await b.close(); }
}

(async function main(){
  fs.mkdirSync(OUT, { recursive: true });
  const game = at('var TAU = Math.PI*2, DEG = Math.PI/180;');            // start of the game IIFE: every anchor is after it

  // -- TYPES: the page's array is the contract; the source literal is a cross-check
  const pg = await pageTypes();
  const tyLit = lit('var TYPES = [', 'TYPES', game);
  if (tyLit.v.length !== pg.n) throw new Error('TYPES literal has ' + tyLit.v.length + ' entries, page has ' + pg.n);
  const diff = [];
  pg.types.forEach((T, i) => { if (JSON.stringify(T) !== JSON.stringify(tyLit.v[i])) diff.push(T.k); });
  if (diff.length) report.notes.push('TYPES entries changed at runtime (page differs from the literal): ' + diff.join(', '));
  write('types.json', pg.types);

  // -- the IIFE tables
  const FACS = lit('var FACS = [', 'FACS', game).v;                write('facs.json', FACS);
  const CORE = lit('var CORE = {', 'CORE', game).v;                write('core.json', CORE);
  write('themes.json', lit('var THEMES = {', 'THEMES', game).v);
  write('terrains.json', lit('var TERRAINS = {', 'TERRAINS', game).v);
  write('teams.json', lit('var TEAMS = [', 'TEAMS', game).v);
  write('phases.json', { order: lit('var PHASES = [', 'PHASES', game).v, nm: lit('var PHASE_NM = {', 'PHASE_NM', game).v });
  write('chapters.json', lit('var CHAPTERS = {', 'CHAPTERS', game).v);
  write('variants.json', lit('var VARIANTS = {', 'VARIANTS', game).v);
  write('skins.json', lit('var SKINS = {', 'SKINS', game).v);
  write('fly.json', lit('var FLY_K = {', 'FLY_K', game).v);
  write('strats.json', dataOnly(lit('var STRATS = {', 'STRATS', game).v, 'STRATS'));
  write('anim.json', {
    anim: dataOnly(lit('var ANIM = {', 'ANIM', game).v, 'ANIM'),
    tracer: dataOnly(lit('var TRACER = {', 'TRACER', game).v, 'TRACER'),
    flame: dataOnly(lit('var FLAME = {', 'FLAME', game).v, 'FLAME') });
  const fxAt = at('var FXS = {', game);
  write('fx.json', {
    fxs: dataOnly(lit('var FXS = {', 'FXS', game).v, 'FXS'),
    fx_st: lit('var FX_ST = {', 'FX_ST', fxAt).v,
    fx_gun: lit('var FX_GUN = {', 'FX_GUN', fxAt).v,
    fx_generic: lit('var FX_GENERIC = {', 'FX_GENERIC', fxAt).v,
    mach8: lit('var MACH8 = {', 'MACH8', fxAt).v,
    beast8: lit('var MACH8 = {', 'BEAST8', fxAt).v });
  write('natural.json', lit('var NATURAL = {', 'NATURAL', game).v);
  write('unit_colours.json', lit('var UNIT_COL = {', 'UNIT_COL', game).v);
  write('sky.json', lit('var SKY = {', 'SKY', game).v);
  write('dust.json', lit('var DUST = {', 'DUST', game).v);
  const BUDGETS = dataOnly(lit('var BUDGETS = (function(){', 'BUDGETS', game).v, 'BUDGETS');

  // -- constants: the ones asked for, plus the siblings declared on the same lines (optional ones only warn)
  const C = {};
  const need = [['ENGAGE', 'var ENGAGE = '], ['CHARGE_R', 'var CHARGE_R = '], ['AURA_R', 'var AURA_R = '], ['OBJ_R', 'var OBJ = [], OBJ_R = '],
    ['SLOT_MAX', 'var SLOT_MAX = '], ['SPEC_TOTAL', 'var SPEC_TOTAL = '], ['PROP_CAP', 'var PROP_CAP = '], ['RULES_V', 'var RULES_V = '], ['APP_VER', 'var APP_VER = ']];
  for (const [n, a] of need) C[n] = lit(a, n, game).v;
  const extra = [['VP_PER', 'var OBJ = [], OBJ_R = '], ['VP_CAP', 'var OBJ = [], OBJ_R = '], ['MAX_ROUND', 'var MAX_ROUND = '], ['KILL_ROUNDS', 'var MAX_ROUND = '],
    ['DEP_FOE', 'var DEP_FOE = '], ['DEP_MATE', 'var DEP_FOE = '], ['BLESS_INV', 'var BLESS_INV = '], ['REZ_AURA', 'var BLESS_INV = '],
    ['FLY_V', 'var FLY_V = '], ['FLY_A', 'var FLY_V = '], ['LODS', 'var LODS = '], ['PANO_N', 'var PANO = {}, PANO_N = '], ['SEED', 'var SEED = '],
    ['theme', 'var theme = '], ['terrain', 'var terrain = '], ['buildings', 'var buildings = '], ['density', 'var buildings = '], ['table', 'var table = ']];
  for (const [n, a] of extra){ const v = opt(() => lit(a, n, game).v, n); if (v !== undefined) C[n] = v; }
  C.BUDGETS = BUDGETS;
  write('constants.json', C);

  // -- English dictionary
  const i18n = at('var BT_I18N = (function(){', game);
  const EN = lit('var EN = {', 'EN', i18n).v;
  write('i18n_en.json', EN);

  // -- rules legend: the Thai comment block before TYPES, then the ability comments inside TYPES (verbatim)
  const rs = lineOf(at('// ═══════════════════ เกม ═══════════════════', game)), ts = lineOf(at('var TYPES = [', game));
  let tEnd = ts; while (!/^\];/.test(lines[tEnd - 1] || '')) tEnd++;            // the `];` closing TYPES
  const legend = lines.slice(rs - 1, ts - 1), inner = [];
  for (let i = ts; i < tEnd; i++) if (/^  \/\/ /.test(lines[i])) inner.push({ line: i + 1, text: lines[i] });
  let md = '# Battle table rules legend (Thai, verbatim from `battle-table.html`)\n\n' +
    'Copied by `godot/tools/export_data.js` from the Thai rules summary and datasheet field legend that sit between the anchor\n' +
    '`// ═══════════════════ เกม ═══════════════════` and `var TYPES = [` (CODEMAP §2.5/§2.6, lines ' + rs + '–' + (ts - 1) + '), then every explanatory\n' +
    'comment line inside the `TYPES` array (lines ' + ts + '–' + tEnd + '). Nothing here says how a hidden unit is unlocked; keep it that way.\n\n' +
    '## 1. Rules summary and datasheet field legend (lines ' + rs + '–' + (ts - 1) + ')\n\n```text\n' + legend.join('\n') + '\n```\n\n' +
    '## 2. Comments inside `var TYPES = [` (unit abilities and weapon keywords, by round)\n\n```text\n' +
    inner.map(x => x.text).join('\n') + '\n```\n';
  fs.writeFileSync(path.join(OUT, 'rules_summary.md'), md);
  report.files.push({ name: 'rules_summary.md', bytes: Buffer.byteLength(md) });

  // ---------- validation ----------
  const T = pg.types, keys = new Set(), facs = new Set(FACS.map(F => F.k)), problems = [];
  T.forEach(t => { if (keys.has(t.k)) problems.push('duplicate type key ' + t.k); keys.add(t.k);
    if (t.fac !== '*' && !facs.has(t.fac)) problems.push('type ' + t.k + ' has unknown army ' + t.fac); });
  FACS.forEach(F => { if (!T.some(t => t.fac === F.k)) problems.push('army ' + F.k + ' has no types'); });
  for (const f in CORE){ if (!facs.has(f)) problems.push('CORE army ' + f + ' not in FACS');
    CORE[f].forEach(k => { if (!keys.has(k)) problems.push('CORE ' + f + ': unknown unit ' + k); }); }
  if (problems.length) throw new Error('validation failed:\n  ' + problems.join('\n  '));
  const hidden = T.filter(t => t.sec || t.lk);
  const counts = { types: T.length, armies: FACS.length, hidden: hidden.length, hiddenKeys: hidden.map(t => t.k + (t.sec ? ' (sec)' : '') + (t.lk ? ' (lk:' + t.lk + ')' : '')),
    strings: Object.keys(EN).length, core_units: Object.values(CORE).reduce((a, l) => a + l.length, 0), budgets: BUDGETS.length,
    app_ver: C.APP_VER, rules_v: C.RULES_V, page_ver: pg.ver.trim() };
  const perArmy = {}; T.forEach(t => { perArmy[t.fac] = (perArmy[t.fac] || 0) + 1; });

  // ---------- report ----------
  console.log('== files (' + OUT + ')');
  report.files.forEach(f => console.log('  ' + f.name.padEnd(20) + String(f.bytes).padStart(9) + ' B'));
  console.log('== counts', JSON.stringify(counts, null, 2));
  console.log('== types per army', JSON.stringify(perArmy));
  console.log('== function-valued keys dropped', JSON.stringify(report.fnKeys));
  console.log('== helpers stubbed while evaluating literals', JSON.stringify(report.stubs));
  if (report.missing.length) console.log('== optional constants not found\n  ' + report.missing.join('\n  '));
  if (report.notes.length) console.log('== notes\n  ' + report.notes.join('\n  '));
  console.log('OK');
})().catch(e => { console.error(e.stack || e); process.exit(1); });
