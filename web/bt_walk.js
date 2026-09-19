// Measures walking pieces on the battle table without a browser:
//   node bt_walk.js [battle-table.html]
// The rig's own harnesses (h3.js, sync_baked.js) check the gait in the rig's local frame. This one checks the half the
// table adds: a piece is carried across the TABLE by its gait, and turns pivot about the planted foot, so a foot in
// contact must not move in TABLE coordinates either — including while the piece is turning.
const fs = require('fs'), path = require('path');
const src = fs.readFileSync(process.argv[2] || path.join(__dirname, 'battle-table.html'), 'utf8');
const a = src.indexOf('// ==MODULES-BEGIN=='), b = src.indexOf('// ==MODULES-END==');
if (a < 0 || b < 0) throw new Error('module markers not found in the page');
const M = new Function(src.slice(a, b) + ';return { SKRIG:SKRIG, MINI:MINI, WALKER:WALKER };')();
const { SKRIG: R, MINI, WALKER } = M;
const DT = 1/60, TABLE = { w: 120, d: 86 };

// a foot's contact points in table coordinates
function contacts(u, P){
  const W = R.fk(P), c = Math.cos(u.rot), s = Math.sin(u.rot), out = {};
  for (const S of ['L','R']){
    const cc = P.contact[S], keys = cc === 'heel' ? ['heel'] : cc === 'ball' ? ['toe'] : cc === 'flat' ? ['heel','toe'] : [];
    for (const k of keys){ const q = W[k + S].p;
      out[k + S] = [u.x + q[0]*c + q[2]*s, u.z - q[0]*s + q[2]*c]; }
  }
  return out;
}
function piece(x, z, rot){ return { k:'heavy', x, z, rot: rot||0, sel:false }; }

// Walk one piece through a list of destinations and report what the table sees.
function run(label, from, facing, marks, opt){
  opt = opt || {};
  const u = piece(from[0], from[1], facing), pinned = {};
  let slide = 0, slideAt = '', air = 0, nWalk = 0, airRun = 0, nRun = 0, frames = 0, t = 0, turnMax = 0, prevRot = u.rot, hip = 0;
  const arrivals = [];
  for (const m of marks){
    WALKER.goTo(u, m[0], m[1]);
    for (let i = 0; i < Math.round((opt.budget || 30) / DT); i++){
      const dt = opt.dt || DT;
      const alive = WALKER.step(u, dt, TABLE); t += dt; frames++;
      const P = u.ctl.pose, now = contacts(u, P);
      for (const k in now){ if (!pinned[k]) pinned[k] = now[k];
        else { const d = Math.hypot(now[k][0]-pinned[k][0], now[k][1]-pinned[k][1]);
               if (d > slide){ slide = d; slideAt = k + '@' + t.toFixed(2) + 's'; } } }
      for (const k in pinned) if (!(k in now)) delete pinned[k];
      // A walk has no flight phase; a run is airborne 36.7% of the time by design. So count only the frames the piece
      // is really walking: the driver asked for a walk AND the speed is down inside the walking band. `cur` is no good
      // here (it reads 'walk' through a run's ramp), and neither is `mode` alone (it flips to 'walk' while the piece is
      // still coasting down from run speed, which is legitimately airborne).
      if (u.ctl.mode === 'walk' && u.ctl.v > 0.3 && u.ctl.v <= R.V_WALK + 0.02){ nWalk++; if (!P.contact.L && !P.contact.R) air++; }
      if (u.ctl.v > R.V_WALK + 0.02){ nRun++; if (!P.contact.L && !P.contact.R) airRun++; }
      for (const S of ['L','R']) if (P.q['hip'+S]) hip = Math.max(hip, Math.abs(R.qToEul(P.q['hip'+S])[1]));
      turnMax = Math.max(turnMax, Math.abs(Math.atan2(Math.sin(u.rot-prevRot), Math.cos(u.rot-prevRot)))/dt); prevRot = u.rot;
      if (!alive) break;
    }
    arrivals.push(Math.hypot(u.x - m[0], u.z - m[1]));
  }
  const worst = Math.max(...arrivals);
  console.log(label.padEnd(30),
    'foot slide', (slide*1000).toFixed(2).padStart(6), 'mm', slideAt.padEnd(16),
    '| off the mark', (worst*1000).toFixed(0).padStart(4), 'mm',
    '| airborne walk', String(air).padStart(2) + '/' + String(nWalk).padStart(4) + 'f',
    'run', String(airRun).padStart(3) + '/' + String(nRun).padStart(4) + 'f',
    '| hip yaw', hip.toFixed(1).padStart(5), 'deg',
    '| frames', String(frames).padStart(4));
  return { slide, worst, air: nWalk ? air/nWalk : 0, frames, hip };
}

console.log('--- a piece walking to a mark (foot slide is measured in TABLE coordinates) ---');
run('straight ahead 8 m',        [0,-20], 0,          [[0,-12]]);
run('straight back 8 m (180 deg)',[0,-20], 0,         [[0,-28]]);
run('90 deg right, 6 m',         [0,0],   0,          [[6,0]]);
run('45 deg, 3 m',               [0,0],   0,          [[2.1,2.1]]);
run('a long run, 30 m',          [0,-40], 0,          [[0,-10]]);
run('short hop, 0.6 m',          [0,0],   0,          [[0,0.6]]);
run('four marks in a square',    [0,0],   0,          [[8,0],[8,8],[0,8],[0,0]]);
run('reversing, mark behind',    [0,0],   0,          [[0,6],[0,-6],[0,6]]);
run('pivot on the spot then go',  [0,0],  Math.PI,    [[0,9]]);
console.log('--- frame-rate independence (same trip, different dt) ---');
for (const dt of [1/60, 1/30, 1/20, 1/10]) run('8 m at ' + Math.round(1/dt) + ' fps', [0,-20], 0, [[0,-12]], { dt });

// What the bare rig does on the same mode changes, with the same metric. Anything the table's walking shows ABOVE these
// lines is the table's fault; anything at or below them the rig already did on its own.
console.log('--- reference: the bare rig, no table, same metric ---');
{
  const ref = (label, seq) => {
    const c = new R.Controller(); let nW = 0, aW = 0, nR = 0, aR = 0;
    for (const [m, secs] of seq){ c.set(m);
      for (let i = 0; i < Math.round(secs/DT); i++){ const P = c.step(DT);
        const off = !P.contact.L && !P.contact.R;
        if (c.mode === 'walk' && c.v > 0.3 && c.v <= R.V_WALK + 0.02){ nW++; if (off) aW++; }
        if (c.v > R.V_WALK + 0.02){ nR++; if (off) aR++; } } }
    console.log(label.padEnd(30), 'airborne walk', nW ? (100*aW/nW).toFixed(1).padStart(5)+'%' : '    -',
      '(' + nW + ' frames)', 'run', nR ? (100*aR/nR).toFixed(1).padStart(5)+'%' : '    -', '(' + nR + ' frames)');
  };
  ref('steady walk',        [['walk', 8]]);
  ref('steady run',         [['run', 8]]);
  ref('run -> walk',        [['run', 4], ['walk', 4]]);
  ref('idle -> walk',       [['idle', 1], ['walk', 6]]);
}

console.log('--- cost per frame ---');
{
  const N = 400, u = piece(0,-20,0); WALKER.goTo(u, 0, 10);
  let t0 = process.hrtime.bigint(); for (let i=0;i<N;i++) WALKER.step(u, DT, TABLE);
  const stepMs = Number(process.hrtime.bigint()-t0)/1e6/N;
  const P = u.ctl.pose;
  t0 = process.hrtime.bigint(); for (let i=0;i<N;i++){ MINI.pose('heavy', P); MINI.build('heavy', R.fk(P)); }
  const buildMs = Number(process.hrtime.bigint()-t0)/1e6/N;
  const nf = MINI.build('heavy', R.fk(P)).length;
  t0 = process.hrtime.bigint(); for (let i=0;i<50;i++) WALKER.make();
  const makeMs = Number(process.hrtime.bigint()-t0)/1e6/50;
  console.log('controller step  ', stepMs.toFixed(3), 'ms   ->', Math.floor(10/stepMs), 'pieces inside a 10 ms slice');
  console.log('live rig geometry', buildMs.toFixed(3), 'ms  (' + nf + ' faces) ->', Math.floor(20/buildMs), 'pieces inside a 20 ms slice');
  console.log('first move (make)', makeMs.toFixed(3), 'ms   one-off, when a piece is first told to move');
}
console.log('--- NaN / finiteness over a long session ---');
{
  const u = piece(0,0,0); let bad = 0;
  for (let m=0;m<12;m++){ WALKER.goTo(u, (m%4-1.5)*9, ((m*3)%5-2)*7);
    for (let i=0;i<900;i++){ const alive = WALKER.step(u, DT, TABLE); const P = u.ctl.pose;
      for (const n in P.q) for (const x of P.q[n]) if (!isFinite(x)) bad++;
      if (!isFinite(u.x) || !isFinite(u.z) || !isFinite(u.rot)) bad++;
      if (!alive) break; } }
  console.log('non-finite values', bad, bad ? 'FAIL' : 'ok', '| ended at', u.x.toFixed(2), u.z.toFixed(2));
}
