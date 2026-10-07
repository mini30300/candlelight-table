#!/usr/bin/env node
// check_oracle.mjs — sanity check of the oracle recordings in this folder (no browser needed):
// every scenario of scenarios.json has a recording that parses, carries the required keys, has one board per act,
// ended by itself (not at the step cap), and whose seats and armies match the scenario; all 15 armies, 2 to 8 teams
// and both goals are covered over the set. Exit code 1 on any problem.   node godot/tests/oracle/check_oracle.mjs
import fs from 'node:fs';
import path from 'node:path';
import zlib from 'node:zlib';
import { fileURLToPath } from 'node:url';

const DIR = path.dirname(fileURLToPath(import.meta.url));
const REQUIRED = ['format', 'page', 'scenario', 'setup', 'seats', 'lists', 'deps', 'skins', 'props', 'board0', 'acts', 'acts_meta', 'boards', 'log', 'final'];
const ARMIES = (() => { try { return JSON.parse(fs.readFileSync(path.join(DIR, '../../data/facs.json'), 'utf8')).map(f => f.k); }
  catch (e) { return ['gr', 'mod', 'kn', 'sw', 'rb', 'or', 'th', 'jp', 'nr', 'eg', 'md', 'el', 'de', 'ta', 'cx']; } })();

let bad = 0; const fail = (m) => { bad++; console.log('FAIL ' + m); };
const scen = JSON.parse(fs.readFileSync(path.join(DIR, 'scenarios.json'), 'utf8'));
const seen = { armies: new Set(), teams: new Set(), goals: new Set(), codes: {} };
let files = 0, acts = 0, bytes = 0;

for (const sc of scen.scenarios){
  const file = [sc.name + '.json.gz', sc.name + '.json'].map(f => path.join(DIR, f)).find(f => fs.existsSync(f));
  if (!file){ fail(sc.name + ': no recording'); continue; }
  let rec;
  try { const buf = fs.readFileSync(file); bytes += buf.length; rec = JSON.parse((file.endsWith('.gz') ? zlib.gunzipSync(buf) : buf).toString('utf8')); }
  catch (e){ fail(sc.name + ': does not parse: ' + e.message); continue; }
  files++;
  const missing = REQUIRED.filter(k => !(k in rec)); if (missing.length) fail(sc.name + ': missing keys ' + missing.join(', '));
  if (rec.scenario !== sc.name) fail(sc.name + ': recording says scenario ' + rec.scenario);
  if (!Array.isArray(rec.acts) || !Array.isArray(rec.boards) || rec.boards.length !== rec.acts.length) fail(sc.name + ': boards.length ' + (rec.boards || []).length + ' != acts.length ' + (rec.acts || []).length);
  if (!Array.isArray(rec.acts_meta) || rec.acts_meta.length !== rec.acts.length) fail(sc.name + ': acts_meta.length != acts.length');
  if (!rec.acts.length) fail(sc.name + ': no acts');
  if (!rec.final || !rec.final.over || rec.final.capped) fail(sc.name + ': the game did not end by itself (over ' + (rec.final && rec.final.over) + ', capped ' + (rec.final && rec.final.capped) + ')');
  if (rec.seats.length !== sc.seats.length) fail(sc.name + ': ' + rec.seats.length + ' seats recorded, scenario has ' + sc.seats.length);
  if (rec.lists.length !== sc.seats.length || rec.deps.length !== sc.seats.length) fail(sc.name + ': lists/deps do not match the seats');
  if (rec.setup.teams !== sc.teams || rec.setup.goal !== (sc.goal === 'kill' ? 'kill' : 'obj') || rec.setup.seed !== sc.seed || rec.setup.w !== sc.size)
    fail(sc.name + ': setup differs from the scenario: ' + JSON.stringify(rec.setup));
  if (rec.setup.v !== rec.page.rules_v) fail(sc.name + ': rules version mismatch ' + rec.setup.v + ' vs ' + rec.page.rules_v);
  sc.seats.forEach((S, i) => {
    // the plain entries must match exactly; a "hidden:<flag>" entry shows up as one extra key the scenario did not name
    const want = S.list.filter(e => !e[0].startsWith('hidden:')).map(e => e[0] + '×' + e[1]).sort();
    const got = (rec.lists[i] || []).map(e => e[0] + '×' + e[1]);
    const plain = got.filter(x => want.includes(x)).sort(), extra = got.filter(x => !want.includes(x));
    const hidden = S.list.filter(e => e[0].startsWith('hidden:')).length;
    if (plain.join(' ') !== want.join(' ') || extra.length !== hidden) fail(sc.name + ' seat ' + i + ': list ' + got.join(' ') + ' vs scenario ' + want.join(' ') + (hidden ? ' + ' + hidden + ' hidden' : ''));
    if (rec.seats[i] && typeof rec.seats[i].fac === 'string') seen.armies.add(rec.seats[i].fac);
    if (rec.seats[i] && rec.seats[i].bot === (sc.human && sc.human.seat === i)) fail(sc.name + ' seat ' + i + ': bot flag ' + rec.seats[i].bot);
  });
  const human = sc.human ? sc.human.seat : -1;
  rec.acts.forEach((a, i) => { seen.codes[a.a] = (seen.codes[a.a] || 0) + 1;
    const m = rec.acts_meta[i]; if (m && a.a === 'done' && m.seat !== human) fail(sc.name + ': a done act not from the human seat'); });
  seen.teams.add(rec.setup.teams); seen.goals.add(rec.setup.goal); acts += rec.acts.length;
}
for (const f of fs.readdirSync(DIR)) if (/\.json(\.gz)?$/.test(f) && f !== 'scenarios.json' && f !== 'allowlist.json' && !scen.scenarios.some(s => f === s.name + '.json' || f === s.name + '.json.gz'))
  fail('recording without a scenario: ' + f);
const noArmy = ARMIES.filter(a => !seen.armies.has(a)); if (noArmy.length) fail('armies never fielded: ' + noArmy.join(', '));
for (let t = 2; t <= 8; t++) if (!seen.teams.has(t)) fail('no scenario with ' + t + ' teams');
for (const g of ['obj', 'kill']) if (!seen.goals.has(g)) fail('no scenario with goal ' + g);
if (!scen.scenarios.some(s => s.seats.some(S => S.list.some(e => e[0].startsWith('hidden:'))))) fail('no scenario fields a hidden unit');
if (!scen.scenarios.some(s => s.human && s.auto === false) || !scen.scenarios.some(s => s.human && s.auto !== false)) fail('need one human seat with manual dice and one with auto dice');
if (!scen.scenarios.some(s => s.human && s.human.policy === 'idle' && s.clock)) fail('need one time-out scenario (idle human with a clock)');
console.log(`${files}/${scen.scenarios.length} recordings, ${acts} acts, ${(bytes / 1024).toFixed(0)} KB on disk · armies ${seen.armies.size}/${ARMIES.length} · teams ${[...seen.teams].sort((a, b) => a - b).join(',')} · goals ${[...seen.goals].join(',')}`);
console.log('act codes: ' + Object.keys(seen.codes).sort().map(c => c + ' ' + seen.codes[c]).join(', '));
console.log(bad ? bad + ' problem(s)' : 'ok');
process.exit(bad ? 1 : 0);
