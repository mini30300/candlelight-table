// Round 5a: the typed-array face sort, taken out of the page and run on made-up faces: far first, equal depths in the
// order they were drawn, a NaN depth kept in the list (as depth 0), the big-list fallback, and the same order as before.
const fs = require('fs');
const src = fs.readFileSync(process.argv[2] || process.env.PAGE || require('path').resolve(__dirname, '../../../app/src/main/assets/battle-table.html'), 'utf8');
const a = src.indexOf('var SORT_K = new Float64Array'), b = src.indexOf('function rulerLine', a);
let FACES = [];
const body = src.slice(a, b);
eval(body.replace('var SORT_K', 'globalThis.SORT_K').replace('function sortFaces', 'globalThis.sortFaces = function'));
let pass = 0, fail = 0; const ok = (c, m, x) => { if (c) pass++; else fail++; console.log((c ? '  ok    ' : '  FAIL  ') + m + (x !== undefined ? '  ' + JSON.stringify(x) : '')); };
const run = (list) => { FACES = list.map((d, i) => ({ d, i })); eval('sortFaces()'); return FACES; };
let r = run([3, 9, 1, 9, 5, 9, 0.5]);
ok(r.map(f => f.d).join() === '9,9,9,5,3,1,0.5' && r.filter(f => f.d === 9).map(f => f.i).join() === '1,3,5', 'far first; equal depths keep the drawing order', r.map(f => f.i));
r = run([2, NaN, 7, -1]);
ok(r.length === 4 && r.every(Boolean) && r.map(f => f.i).join() === '2,0,1,3', 'a NaN depth stays in the list (sorted as 0), nothing is lost', r.map(f => f && f.i));
let rnd = 7; const R = () => (rnd = (rnd * 16807) % 2147483647) / 2147483647;
const big = Array.from({ length: 20000 }, () => Math.round(R() * 150 * 1000) / 1000);
r = run(big); const ref = big.map((d, i) => ({ d, i })).sort((x, y) => y.d - x.d);
ok(r.every((f, k) => f.i === ref[k].i), 'the same order as the old comparator sort on 20,000 faces');
const huge = Array.from({ length: 70000 }, (_, i) => i % 97);
r = run(huge); ok(r.length === 70000 && r[0].d === 96 && r[69999].d === 0, 'over 65,536 faces it falls back to the comparator sort');
console.log(`${pass} passed, ${fail} failed`); process.exit(fail ? 1 : 0);
