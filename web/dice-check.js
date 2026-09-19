// Checks the two things shared dice depend on:
//   1. the die lands reading exactly the value the server rolled, for every value of every die
//   2. the same (kind, value, seed) produces a bit-identical flight, so two phones cannot show different throws
// Run: node dice-check.js
const DICE = require('./dice-core.js');

const KINDS = [[4,1,4],[6,1,6],[8,1,8],[10,0,9],[12,1,12],[20,1,20]];
let bad = 0, total = 0, longest = 0, slowest = 0;

console.log('--- does it land on the number the server rolled? (every face, 40 seeds each) ---');
for (const [kind, lo, hi] of KINDS) {
  let miss = 0, secs = [];
  for (let value = lo; value <= hi; value++) {
    for (let s = 1; s <= 40; s++) {
      const r = DICE.roll(kind, value, s * 2654435761 + kind * 97 + value);
      total++;
      if (!r) { miss++; continue; }
      if (DICE.faceUp(r) !== value) { miss++; if (miss <= 2) console.log('   MISS d' + kind + ' wanted ' + value + ' got ' + DICE.faceUp(r) + ' seed ' + s); }
      secs.push(r.secs);
      longest = Math.max(longest, r.secs);
    }
  }
  bad += miss;
  const avg = secs.reduce((a, b) => a + b, 0) / secs.length;
  console.log('  d' + String(kind).padEnd(3), (miss ? 'FAIL ' + miss + ' wrong' : 'all ' + secs.length + ' land right').padEnd(24),
    'flight avg ' + avg.toFixed(2) + 's, longest ' + Math.max(...secs).toFixed(2) + 's');
}

console.log('\n--- is the flight identical from the same seed? (what makes it the SAME roll on every phone) ---');
{
  let diff = 0;
  for (const [kind] of KINDS) for (let s = 1; s <= 25; s++) {
    const value = kind === 10 ? 7 : 3;
    const a = DICE.roll(kind, value, s), b = DICE.roll(kind, value, s);
    if (a.frames.length !== b.frames.length) { diff++; continue; }
    for (let i = 0; i < a.frames.length; i++)
      for (let k = 0; k < 3; k++) if (a.frames[i].p[k] !== b.frames[i].p[k]) { diff++; i = a.frames.length; break; }
  }
  console.log('  ' + (diff ? 'FAIL: ' + diff + ' flights differed' : 'all 150 repeats bit-identical'));
  bad += diff;
}

console.log('\n--- do different seeds actually give different throws? (or is it the same tumble every time) ---');
{
  const seen = new Set();
  for (let s = 1; s <= 60; s++) { const r = DICE.roll(20, 11, s); seen.add(r.rest.p[0].toFixed(4) + ',' + r.rest.p[2].toFixed(4)); }
  console.log('  60 seeds -> ' + seen.size + ' distinct resting spots' + (seen.size < 40 ? '   TOO FEW' : ''));
  if (seen.size < 40) bad++;
}

console.log('\n--- cost: this runs once when a roll arrives, not per frame ---');
{
  for (const [kind] of KINDS) {
    const N = 200, t0 = process.hrtime.bigint();
    for (let i = 0; i < N; i++) DICE.roll(kind, kind === 10 ? 4 : 4, i + 1);
    const ms = Number(process.hrtime.bigint() - t0) / 1e6 / N;
    slowest = Math.max(slowest, ms);
    console.log('  d' + String(kind).padEnd(3), ms.toFixed(2) + ' ms per throw');
  }
  const t0 = process.hrtime.bigint(); DICE.shapes(); 
  console.log('  building the solids (first roll only):', (Number(process.hrtime.bigint() - t0) / 1e6).toFixed(2), 'ms');
}

console.log('\n' + (bad ? bad + ' FAILURES' : 'all ' + total + ' throws land on the server\'s number; flights reproduce exactly'));
console.log('longest flight ' + longest.toFixed(2) + 's, slowest throw ' + slowest.toFixed(2) + ' ms');
process.exit(bad ? 1 : 0);
