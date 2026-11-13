#!/usr/bin/env node
// bake_sfx.js — runs battle-table.html headlessly and renders the page's own synthesized sounds to WAV files for the new
// app, through the page's test hook SND.probe (an OfflineAudioContext replay of the same code that plays them live):
//   - every effect in SND's DEF table → godot/assets/sfx/<kind>_<n>.wav, VARIANTS takes each (the page detunes every
//     shot a little, so a burst never repeats one sample; the app picks a take at random)
//   - the music as seamless loops → godot/assets/sfx/music/<name>.wav (a "smpl" loop chunk, so Godot imports them looping):
//       menu        the page's older song at the menu level (what the page plays on its menu in the default "mix" style)
//       deck        the epic song at level 0 (calm: choir and bass)
//       battle_1..3 the epic song at levels 1, 2, 3; the three share their chords bar by bar (the chord picks come from
//                   their own seeded stream), so the app can crossfade between them as the battle heats up, like the page
//                   moves between its levels
//     A loop is one 16-bar take; its ringing tail (reverb, delays) is folded back onto the start, so the seam is inaudible.
//     The page opens a battle song with a cymbal and a low boom (its level rise); the loops keep it as their downbeat.
//   - godot/assets/sfx/sfx.json: the manifest (kinds with gap ms, volume, takes, lengths; the weapon → sound maps FXS[kind].snd,
//     FX_GUN, LZ_SND, FX_SND; the music heat weights HK and each kind's heat alias h; the loops with tempo and bar length).
// Math.random is seeded for every take, so a bake is reproducible. Nothing in the page is modified.
//
//   CHROMIUM_PATH=$(ls -d /opt/pw-browsers/chromium-*/chrome-linux*/chrome | head -1) node godot/tools/bake_sfx.js
//   options: --out DIR (default godot/assets/sfx)  --page FILE  --no-music  --check [DIR] (validate an existing bake, exit)
'use strict';
const fs = require('fs'), path = require('path');
const ROOT = path.resolve(__dirname, '..', '..');
const ARGS = parseArgs(process.argv.slice(2));
const PAGE = path.resolve(ROOT, ARGS.page || 'app/src/main/assets/battle-table.html');
const OUT = path.resolve(ROOT, ARGS.out || 'godot/assets/sfx');
const FORMAT = 1;
const SFX_SR = 32000, MUS_SR = 24000, VARIANTS = 3, BARS = 16, THEME = 'ruin';
// name, style, level (the page's 0..3)
const LOOPS = [
  { name: 'menu', style: 'old', level: 0 },
  { name: 'deck', style: 'epic', level: 0 },
  { name: 'battle_1', style: 'epic', level: 1 },
  { name: 'battle_2', style: 'epic', level: 2 },
  { name: 'battle_3', style: 'epic', level: 3 }
];
const SEED = 7001, PROG_SEED = 9203;

function parseArgs(a){ const o = {}; for (let i = 0; i < a.length; i++){ const m = /^--([\w-]+)$/.exec(a[i]); if (!m) continue;
  if (m[1] === 'no-music') o.noMusic = true;
  else if (m[1] === 'check') o.check = (a[i + 1] && !a[i + 1].startsWith('--')) ? a[++i] : true;
  else o[m[1]] = a[++i]; } return o; }

// ---------- WAV ----------
function wav(int16, sr, loop){
  const data = Buffer.from(int16.buffer, int16.byteOffset, int16.byteLength);
  const smpl = loop ? 36 + 24 : 0, size = 36 + 8 + data.length + (loop ? 8 + smpl : 0);
  const b = Buffer.alloc(8 + size - 0); let o = 0;
  const s4 = s => { b.write(s, o, 'ascii'); o += 4; }, u32 = v => { b.writeUInt32LE(v >>> 0, o); o += 4; }, u16 = v => { b.writeUInt16LE(v, o); o += 2; };
  s4('RIFF'); u32(size); s4('WAVE');
  s4('fmt '); u32(16); u16(1); u16(1); u32(sr); u32(sr*2); u16(2); u16(16);
  if (loop){   // smpl: one forward loop over the whole file (Godot's importer reads it with loop mode "detect")
    s4('smpl'); u32(smpl); u32(0); u32(0); u32(Math.round(1e9/sr)); u32(60); u32(0); u32(0); u32(0); u32(1); u32(0);
    u32(0); u32(0); u32(0); u32(int16.length - 1); u32(0); u32(0); }
  s4('data'); u32(data.length); data.copy(b, o); o += data.length;
  return b.subarray(0, o); }
function readWavInfo(file){ const b = fs.readFileSync(file);
  if (b.toString('ascii', 0, 4) !== 'RIFF' || b.toString('ascii', 8, 12) !== 'WAVE') return null;
  let o = 12, sr = 0, n = 0, loop = false, peak = 0;
  while (o + 8 <= b.length){ const id = b.toString('ascii', o, o + 4), len = b.readUInt32LE(o + 4);
    if (id === 'fmt ') sr = b.readUInt32LE(o + 12);
    if (id === 'smpl') loop = true;
    if (id === 'data'){ n = len/2; for (let i = 0; i < n; i++) peak = Math.max(peak, Math.abs(b.readInt16LE(o + 8 + i*2))); }
    o += 8 + len + (len & 1); }
  return { sr, n, loop, peak: peak/32767 }; }
function toInt16(f32){ const u = new Int16Array(f32.length);
  for (let i = 0; i < f32.length; i++){ const a = Math.max(-1, Math.min(1, f32[i])); u[i] = Math.round(a*32767); } return u; }
function fromB64(b64){ const by = Buffer.from(b64, 'base64'), n = by.length/2, f = new Float32Array(n);
  for (let i = 0; i < n; i++) f[i] = by.readInt16LE(i*2)/32767; return f; }

// ---------- in the page ----------
// installs a seeded Math.random only while the probe schedules its notes (all synchronous), then restores it.
// progSeed: the music's chord picks (the only Math.random call made directly by SND's step()) draw from a stream of their
// own, so takes at different levels pick the same chords although the other draws differ in number
function pageProbe(arg){
  return new Promise(res => {
    const R = Math.random, lim = Error.stackTraceLimit;
    const mk = seed => { let s = seed >>> 0; return () => { s = (s + 0x6D2B79F5) >>> 0; let t = s; t = Math.imul(t ^ (t >>> 15), t | 1);
      t ^= t + Math.imul(t ^ (t >>> 7), t | 61); return ((t ^ (t >>> 14)) >>> 0)/4294967296; }; };
    const main = mk(arg.seed), prog = arg.progSeed ? mk(arg.progSeed) : null;
    Math.random = prog ? function(){ const st = new Error().stack.split('\n')[2] || ''; return /at step \(/.test(st) ? prog() : main(); } : main;
    if (prog) Error.stackTraceLimit = 3;
    try { window.BT.snd.probe(arg.kind, r => res(r), arg.op); } catch (e){ res({ err: String(e) }); }
    finally { Math.random = R; Error.stackTraceLimit = lim; } }); }

// gap, v and h of each DEF entry, and the music's heat weights HK, read from the page source (they live in SND's closure)
function sourceTables(src){
  const a = src.indexOf('var SND = (function(){'), d = src.indexOf('var DEF = {', a), e = src.indexOf('\n  };', d);
  if (a < 0 || d < 0 || e < 0) throw new Error('cannot find SND/DEF in ' + PAGE);
  const body = src.slice(d, e), def = {}, re = /^\s{4}(\w+):\s*\{\s*gap:(\d+),\s*v:([\d.]+)(?:,\s*h:(?:'(\w+)'|null))?/mg; let m;
  while ((m = re.exec(body))) def[m[1]] = { gap: +m[2], v: +m[3], h: m[4] || (/h:null/.test(m[0]) ? null : undefined) };
  const hk = /HK = \{([^}]*)\}/.exec(src.slice(a, a + 40000)), HK = {};
  if (hk) hk[1].split(',').forEach(p => { const q = p.split(':'); if (q.length === 2) HK[q[0].trim()] = +q[1]; });
  const mt = /ruin:\s*\{ k:(\d+), bpm:(\d+)/.exec(src.slice(a, a + 40000)), om = /OMT = \{ ruin:\{ root:\d+, sc:\[[^\]]*\], bpm:(\d+)/.exec(src.slice(a, a + 40000));
  // weapon → sound: FXS[kind].snd (m:1 = a melee kind), FX_GUN (gun → FXS kind), LZ_SND (laser-sounding guns), FX_SND
  const blk = (start) => { const i = src.indexOf(start); if (i < 0) throw new Error('cannot find ' + start); return src.slice(i, src.indexOf('};', i)); };
  const fxs = {}, fxGun = {}, fxSnd = {};
  for (const m2 of blk('var FXS = {').matchAll(/^\s+(\w+):\s*\{\s*snd:'(\w+)'([^\n]*)/mg)) fxs[m2[1]] = { snd: m2[2], melee: /\bm:1\b/.test(m2[3]) };
  for (const m2 of blk('var FX_GUN = {').slice(14).matchAll(/(\w+):'(\w+)'/g)) fxGun[m2[1]] = m2[2];
  const lzm = /var LZ_SND = \/\^\(([\w|]+)\)\$\/, FX_SND = \{([^}]*)\}/.exec(src);
  if (!lzm) throw new Error('cannot find LZ_SND / FX_SND');
  for (const m2 of lzm[2].matchAll(/(\w+):'(\w+)'/g)) fxSnd[m2[1]] = m2[2];
  return { def, HK, fxs, fxGun, lz: lzm[1].split('|'), fxSnd, bpm: { epic: mt ? +mt[2] : 100, old: om ? +om[1] : 84 } }; }

// trims leading/trailing silence (−80 dB), 4 ms fade-out
function trim(f, sr){ let a = 0, b = f.length - 1; const th = 1e-4;
  while (a < f.length && Math.abs(f[a]) < th) a++; while (b > a && Math.abs(f[b]) < th) b--;
  a = Math.max(0, a - Math.round(sr*0.001)); b = Math.min(f.length - 1, b + Math.round(sr*0.02));
  const o = f.slice(a, b + 1), fade = Math.min(o.length, Math.round(sr*0.004));
  for (let i = 0; i < fade; i++) o[o.length - 1 - i] *= i/fade;
  return o; }

function check(dir){
  const errs = [], mf = path.join(dir, 'sfx.json');
  if (!fs.existsSync(mf)) return ['missing ' + mf];
  let M; try { M = JSON.parse(fs.readFileSync(mf, 'utf8')); } catch (e){ return ['sfx.json does not parse: ' + e]; }
  if (M.format !== FORMAT) errs.push('format ' + M.format + ' != ' + FORMAT);
  const kinds = Object.keys(M.kinds || {});
  if (kinds.length < 30) errs.push('only ' + kinds.length + ' kinds');
  for (const k of kinds){ const K = M.kinds[k];
    if (!(K.gap > 0) || !(K.v > 0) || !Array.isArray(K.files) || !K.files.length) { errs.push(k + ': bad entry'); continue; }
    for (const f of K.files){ const w = readWavInfo(path.join(dir, f)); if (!w || w.n < 100 || w.peak < 0.005) errs.push(k + ': ' + f + ' empty or unreadable'); } }
  for (const [fx, e] of Object.entries(M.fxs || {})) if (e.snd && !M.kinds[e.snd]) errs.push('fx ' + fx + ' → unknown sound ' + e.snd);
  for (const [n, L] of Object.entries(M.music || {})){ const w = readWavInfo(path.join(dir, L.file));
    if (!w || !w.loop || w.n !== L.samples || w.peak < 0.01) errs.push('music ' + n + ': bad loop file'); }
  return errs; }

async function main(){
  if (ARGS.check){ const dir = ARGS.check === true ? OUT : path.resolve(ROOT, ARGS.check), e = check(dir);
    if (e.length){ console.error('bake_sfx --check: ' + e.join('\n  ')); process.exit(1); } console.log('bake_sfx --check: ok (' + dir + ')'); return; }
  const t0 = Date.now(), src = fs.readFileSync(PAGE, 'utf8'), T = sourceTables(src);
  let pw; try { pw = require(path.join(ROOT, 'tests/node_modules/playwright')); } catch (e){ pw = require('playwright'); }
  const browser = await pw.chromium.launch({ executablePath: process.env.CHROMIUM_PATH || undefined, args: ['--no-sandbox', '--autoplay-policy=no-user-gesture-required'] });
  const page = await (await browser.newContext({ viewport: { width: 800, height: 600 } })).newPage();
  page.on('pageerror', e => console.error('page error: ' + e.message));
  await page.goto('file://' + PAGE);
  await page.waitForFunction(() => window.BT && window.BT.snd && window.BT.snd.probe, null, { timeout: 120000 });
  const info = { kinds: await page.evaluate(() => window.BT.snd.kinds()) };
  fs.mkdirSync(path.join(OUT, 'music'), { recursive: true });
  for (const f of fs.readdirSync(OUT)) if (/\.wav$/.test(f)) fs.unlinkSync(path.join(OUT, f));
  const M = { format: FORMAT, generated_by: 'godot/tools/bake_sfx.js', page: path.relative(ROOT, PAGE), sample_rate: SFX_SR,
    max_voices: 22, kinds: {}, fxs: T.fxs, fx_gun: T.fxGun, lz_snd: T.lz, fx_snd: T.fxSnd, heat: T.HK, music: {} };
  let bytes = 0;
  for (const k of info.kinds){
    const D = T.def[k]; if (!D){ console.error('no gap/v for ' + k + ' in the source'); process.exit(1); }
    const files = [], lens = [];
    for (let n = 0; n < VARIANTS; n++){
      const r = await page.evaluate(pageProbe, { kind: k, seed: 1000 + n*7919 + k.length*31, op: { sr: SFX_SR, ch: 1, raw: true } });
      if (!r || r.err || !r.pcm){ console.error('probe ' + k + ' failed: ' + JSON.stringify(r && r.err)); process.exit(1); }
      const f = trim(fromB64(r.pcm), SFX_SR), name = k + '_' + n + '.wav', buf = wav(toInt16(f), SFX_SR, false);
      fs.writeFileSync(path.join(OUT, name), buf); bytes += buf.length; files.push(name); lens.push(+(f.length/SFX_SR).toFixed(3));
    }
    M.kinds[k] = { gap: D.gap, v: D.v, h: D.h === undefined ? k : D.h, files, len: lens };
  }
  console.log('bake_sfx: ' + info.kinds.length + ' kinds × ' + VARIANTS + ' takes, ' + (bytes/1048576).toFixed(2) + ' MB PCM');
  if (!ARGS.noMusic){
    for (const L of LOOPS){
      const bpm = L.style === 'old' ? T.bpm.old*(L.level ? 1 : 0.85) : T.bpm.epic*(L.level ? 1 : 0.84);
      const step = 60/bpm/4, segS = BARS*16*step, seg = Math.round(segS*MUS_SR), off = Math.round(0.05*MUS_SR);
      const loop = new Float32Array(seg);
      const r = await page.evaluate(pageProbe, { kind: 'music', seed: SEED, progSeed: PROG_SEED, op: { sr: MUS_SR, ch: 1, raw: true, sec: segS + 3.4,
        levels: new Array(BARS).fill(L.level), style: L.style, theme: THEME } });
      if (!r || r.err || !r.pcm){ console.error('music ' + L.name + ' failed: ' + JSON.stringify(r && r.err)); process.exit(1); }
      const f = fromB64(r.pcm);
      for (let j = off; j < f.length; j++) loop[(j - off) % seg] += f[j];   // the ringing tail wraps onto the start
      let pk = 0; for (const a of loop) pk = Math.max(pk, Math.abs(a)); const g = pk > 0.98 ? 0.98/pk : 1;
      if (g < 1) for (let i = 0; i < loop.length; i++) loop[i] *= g;
      const file = 'music/' + L.name + '.wav', buf = wav(toInt16(loop), MUS_SR, true);
      fs.writeFileSync(path.join(OUT, file), buf); bytes += buf.length;
      M.music[L.name] = { file, style: L.style, level: L.level, bpm: +bpm.toFixed(3), bar: +(16*step).toFixed(5), bars: BARS,
        samples: loop.length, sample_rate: MUS_SR, seconds: +(loop.length/MUS_SR).toFixed(2), gain: +g.toFixed(3) };
      console.log('bake_sfx: music ' + L.name + ' ' + M.music[L.name].seconds + ' s' + (g < 1 ? ' (scaled ' + g.toFixed(2) + ')' : ''));
    }
  }
  fs.writeFileSync(path.join(OUT, 'sfx.json'), JSON.stringify(M, null, 1) + '\n');
  await browser.close();
  const e = check(OUT); if (e.length){ console.error('bake_sfx: the bake does not validate:\n  ' + e.join('\n  ')); process.exit(1); }
  console.log('bake_sfx: done in ' + ((Date.now() - t0)/1000).toFixed(1) + ' s, ' + (bytes/1048576).toFixed(2) + ' MB of WAV in ' + path.relative(ROOT, OUT));
}
main().catch(e => { console.error(e); process.exit(1); });
