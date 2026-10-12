'use strict';
// mount_rig.js — the parts of a mount (horse, beast, bike) that the page moves with how far the piece has travelled
// (MINI.build reads mo.travel / mo.v: legs, hooves, tail, the head's nod, wheels) rather than with the rider's 23
// joints. export_kits.js gives each part a bone of its own (after the 23, under the pelvis) and binds the part's
// faces to it; bake_anim.js moves the parts every frame. Shared by both so they agree on the parts.
//
// Parts are found, not named: the kit is built standing (the rest the kit is exported in) and at many travel values;
// faces that move are grouped into rigid parts (one rigid transform per sample fits them all), small groups merge
// while a common fit stays close, and parts are joined into a tree where two of them turn about a common pivot. A leg
// is a chain of jointed parts from the body down to a part that touches the ground some of the time (a hoof).
//
// The page's legs swing by angle and do not stay put on the ground (its horse's hooves slide 8–80 cm per step). The
// bake keeps the page's parts, pivots, leg order, phase pattern, tail and head motion, and re-solves the legs so a
// foot on the ground stays where it landed: planGait / footAt / ik2 below. Only a mount whose every stepping part is
// the foot of such a leg gets bones (buildRig: gait); the others stay on the pelvis as before.

// ---------- the page side (these run inside the page through page.evaluate) ----------
// the kit standing, then at travel samples (a scaled kit's mo.travel is in table metres: steps are times its scale);
// arg.faces limits the copy to those faces. Packed (float32, base64) because copying nested arrays out of the page
// is slow: unpackSamples() turns it back into arrays that keep the page's face numbering (null = not copied).
function pageSampleMount(arg){
  var R = window.SKRIG, M = window.MINI, k = arg.kit, P = R.idlePose(0); M.pose(k, P); var Wd = R.fk(P);
  var S = (M.KITS[k] && M.KITS[k].scale) || 1, sel = arg.faces || null, restF = M.build(k, Wd, 1), i;
  var on = null; if (sel){ on = {}; sel.forEach(function(j){ on[j] = 1; }); }
  var counts = restF.map(function(f, j){ return on && !on[j] ? 0 : f.p.length; }), nv = 0; counts.forEach(function(c){ nv += c; });
  function pack(fs){ if (fs.length !== restF.length) return null; var a = new Float32Array(nv*3), o = 0;
    for (var j = 0; j < fs.length; j++){ if (!counts[j]) continue; if (fs[j].p.length !== counts[j]) return null;
      for (var m = 0; m < counts[j]; m++){ var q = fs[j].p[m]; a[o++] = q[0]; a[o++] = q[1]; a[o++] = q[2]; } }
    var b = new Uint8Array(a.buffer), str = ''; for (var x = 0; x < b.length; x += 8192) str += String.fromCharCode.apply(null, b.subarray(x, x + 8192)); return btoa(str); }
  var rest = pack(restF), samples = [];                       // packed now: the page may reuse its face objects
  arg.speeds.forEach(function(v){ for (i = 0; i < arg.n; i++){ var tr = i*arg.step*S, fs = M.build(k, Wd, 1, { travel: tr, v: v });
    samples.push({ v: v, tr: tr, count: fs.length, b64: pack(fs) }); } });
  return { counts: counts, rest: rest, samples: samples, scale: S };
}
// node side: the packed samples as arrays of points per face (null for faces not copied)
function unpackSamples(d){
  const un = b64 => { if (!b64) return null; const buf = Buffer.from(b64, 'base64'), a = new Float32Array(buf.buffer, buf.byteOffset, buf.length/4), out = []; let o = 0;
    for (const c of d.counts){ if (!c){ out.push(null); continue; } const f = []; for (let m = 0; m < c; m++){ f.push([a[o], a[o + 1], a[o + 2]]); o += 3; } out.push(f); } return out; };
  const rest = un(d.rest), samples = d.samples.map(s => ({ v: s.v, tr: s.tr, faces: un(s.b64) || [] }));
  return { rest, samples, scale: d.scale };
}
// the page side: the given faces of the kit at each {travel, v} (travel in table metres, as the page takes it)
function pageMountFaces(arg){
  var R = window.SKRIG, M = window.MINI, P = R.idlePose(0); M.pose(arg.kit, P); var Wd = R.fk(P), sel = arg.faces;
  return arg.at.map(function(m){ var fs = M.build(arg.kit, Wd, 1, m.rest ? undefined : { travel: m.travel, v: m.v });
    return { count: fs.length, faces: sel.map(function(i){ var f = fs[i]; return f ? f.p.map(function(q){ return [q[0], q[1], q[2]]; }) : null; }) }; });
}

// ---------- small maths (quaternions [x,y,z,w] as SKRIG; rigid fits by Horn's quaternion method) ----------
function jacobi4(A){
  const a = A.map(r => r.slice()), v = [[1, 0, 0, 0], [0, 1, 0, 0], [0, 0, 1, 0], [0, 0, 0, 1]];
  for (let s = 0; s < 60; s++){
    let off = 0; for (let p = 0; p < 3; p++) for (let q = p + 1; q < 4; q++) off += a[p][q]*a[p][q];
    if (off < 1e-24) break;
    for (let p = 0; p < 3; p++) for (let q = p + 1; q < 4; q++){
      if (Math.abs(a[p][q]) < 1e-300) continue;
      const th = (a[q][q] - a[p][p])/(2*a[p][q]), t = (th >= 0 ? 1 : -1)/(Math.abs(th) + Math.sqrt(th*th + 1)), c = 1/Math.sqrt(t*t + 1), sn = t*c;
      for (let k = 0; k < 4; k++){ const x = a[k][p], y = a[k][q]; a[k][p] = c*x - sn*y; a[k][q] = sn*x + c*y; }
      for (let k = 0; k < 4; k++){ const x = a[p][k], y = a[q][k]; a[p][k] = c*x - sn*y; a[q][k] = sn*x + c*y; }
      for (let k = 0; k < 4; k++){ const x = v[k][p], y = v[k][q]; v[k][p] = c*x - sn*y; v[k][q] = sn*x + c*y; }
    }
  }
  return { vals: [a[0][0], a[1][1], a[2][2], a[3][3]], vecs: v };
}
// S[r][c] = sum a_r b_c (centred): the rotation taking a onto b best
function hornQ(S){
  const [[xx, xy, xz], [yx, yy, yz], [zx, zy, zz]] = S;
  const N = [[xx + yy + zz, yz - zy, zx - xz, xy - yx], [yz - zy, xx - yy - zz, xy + yx, zx + xz],
             [zx - xz, xy + yx, -xx + yy - zz, yz + zy], [xy - yx, zx + xz, yz + zy, -xx - yy + zz]];
  const e = jacobi4(N); let bi = 0; for (let i = 1; i < 4; i++) if (e.vals[i] > e.vals[bi]) bi = i;
  let q = [e.vecs[1][bi], e.vecs[2][bi], e.vecs[3][bi], e.vecs[0][bi]]; const l = Math.hypot(q[0], q[1], q[2], q[3]) || 1;
  q = q.map(x => x/l); if (q[3] < 0) q = q.map(x => -x);
  return q;
}
const qmat = q => { const [x, y, z, w] = q; return [[1 - 2*(y*y + z*z), 2*(x*y - w*z), 2*(x*z + w*y)], [2*(x*y + w*z), 1 - 2*(x*x + z*z), 2*(y*z - w*x)], [2*(x*z - w*y), 2*(y*z + w*x), 1 - 2*(x*x + y*y)]]; };
const mv = (R, p) => [R[0][0]*p[0] + R[0][1]*p[1] + R[0][2]*p[2], R[1][0]*p[0] + R[1][1]*p[1] + R[1][2]*p[2], R[2][0]*p[0] + R[2][1]*p[1] + R[2][2]*p[2]];
const ap = (T, p) => { const r = mv(T.R, p); return [r[0] + T.t[0], r[1] + T.t[1], r[2] + T.t[2]]; };
const dist = (a, b) => Math.hypot(a[0] - b[0], a[1] - b[1], a[2] - b[2]);
const add = (a, b) => [a[0] + b[0], a[1] + b[1], a[2] + b[2]], sub = (a, b) => [a[0] - b[0], a[1] - b[1], a[2] - b[2]];
const scl = (a, k) => [a[0]*k, a[1]*k, a[2]*k], dot = (a, b) => a[0]*b[0] + a[1]*b[1] + a[2]*b[2];
const cross = (a, b) => [a[1]*b[2] - a[2]*b[1], a[2]*b[0] - a[0]*b[2], a[0]*b[1] - a[1]*b[0]];
const norm = a => { const l = Math.hypot(a[0], a[1], a[2]) || 1; return [a[0]/l, a[1]/l, a[2]/l]; };
function qmul(a, b){ const [ax, ay, az, aw] = a, [bx, by, bz, bw] = b;
  return [aw*bx + ax*bw + ay*bz - az*by, aw*by - ax*bz + ay*bw + az*bx, aw*bz + ax*by - ay*bx + az*bw, aw*bw - ax*bx - ay*by - az*bz]; }
const qconj = q => [-q[0], -q[1], -q[2], q[3]];
function qnorm(q){ const l = Math.hypot(q[0], q[1], q[2], q[3]) || 1; return q.map(v => v/l); }
function qrot(q, v){ const [x, y, z, w] = q, ux = y*v[2] - z*v[1], uy = z*v[0] - x*v[2], uz = x*v[1] - y*v[0];
  const vx = y*uz - z*uy, vy = z*ux - x*uz, vz = x*uy - y*ux; return [v[0] + 2*(w*ux + vx), v[1] + 2*(w*uy + vy), v[2] + 2*(w*uz + vz)]; }
function qaxis(ax, a){ const s = Math.sin(a/2), n = norm(ax); return [n[0]*s, n[1]*s, n[2]*s, Math.cos(a/2)]; }
// the rotation (as a quaternion) of an orthonormal frame given by its columns e1, e2, e3
function qframe(e1, e2, e3){ const m00 = e1[0], m10 = e1[1], m20 = e1[2], m01 = e2[0], m11 = e2[1], m21 = e2[2], m02 = e3[0], m12 = e3[1], m22 = e3[2], tr = m00 + m11 + m22;
  let q; if (tr > 0){ const s = Math.sqrt(tr + 1)*2; q = [(m21 - m12)/s, (m02 - m20)/s, (m10 - m01)/s, s/4]; }
  else if (m00 > m11 && m00 > m22){ const s = Math.sqrt(1 + m00 - m11 - m22)*2; q = [s/4, (m01 + m10)/s, (m02 + m20)/s, (m21 - m12)/s]; }
  else if (m11 > m22){ const s = Math.sqrt(1 + m11 - m00 - m22)*2; q = [(m01 + m10)/s, s/4, (m12 + m21)/s, (m02 - m20)/s]; }
  else { const s = Math.sqrt(1 + m22 - m00 - m11)*2; q = [(m02 + m20)/s, (m12 + m21)/s, s/4, (m10 - m01)/s]; }
  return qnorm(q); }
function qslerp(a, b, t){ let d = a[0]*b[0] + a[1]*b[1] + a[2]*b[2] + a[3]*b[3], bb = b; if (d < 0){ d = -d; bb = b.map(x => -x); }
  if (d > 0.9995) return qnorm(a.map((x, i) => x + (bb[i] - x)*t));
  const th = Math.acos(d), s = Math.sin(th); return a.map((x, i) => (x*Math.sin((1 - t)*th) + bb[i]*Math.sin(t*th))/s); }
// a rigid transform {q, R, t}: x -> R x + t
function xf(q, t){ q = qnorm(q); return { q, R: qmat(q), t }; }
function xmul(A, B){ return xf(qmul(A.q, B.q), add(mv(A.R, B.t), A.t)); }        // (A B) x = A (B x)
function xinv(A){ const qi = qconj(A.q), R = qmat(qi); return xf(qi, scl(mv(R, A.t), -1)); }
const XI = () => xf([0, 0, 0, 1], [0, 0, 0]);
// the rigid transform taking the points A onto B best
function rigidFit(A, B){
  const n = A.length, ca = [0, 0, 0], cb = [0, 0, 0];
  for (let i = 0; i < n; i++) for (let k = 0; k < 3; k++){ ca[k] += A[i][k]/n; cb[k] += B[i][k]/n; }
  const S = [[0, 0, 0], [0, 0, 0], [0, 0, 0]];
  for (let i = 0; i < n; i++) for (let r = 0; r < 3; r++) for (let c = 0; c < 3; c++) S[r][c] += (A[i][r] - ca[r])*(B[i][c] - cb[c]);
  const q = hornQ(S), R = qmat(q), Rc = mv(R, ca);
  return { q, R, t: [cb[0] - Rc[0], cb[1] - Rc[1], cb[2] - Rc[2]] };
}
// fit statistics, additive over faces: n, sum a, sum b, sum a b^T (9), sum |a|^2, sum |b|^2
const NST = 18;
function addStats(st, o, A, B){ for (let m = 0; m < A.length; m++){ const a = A[m], b = B[m];
  st[o] += 1; st[o + 1] += a[0]; st[o + 2] += a[1]; st[o + 3] += a[2]; st[o + 4] += b[0]; st[o + 5] += b[1]; st[o + 6] += b[2];
  for (let r = 0; r < 3; r++) for (let c = 0; c < 3; c++) st[o + 7 + r*3 + c] += a[r]*b[c];
  st[o + 16] += a[0]*a[0] + a[1]*a[1] + a[2]*a[2]; st[o + 17] += b[0]*b[0] + b[1]*b[1] + b[2]*b[2]; } }
function fitStats(st, o){
  const n = st[o], ca = [st[o + 1]/n, st[o + 2]/n, st[o + 3]/n], cb = [st[o + 4]/n, st[o + 5]/n, st[o + 6]/n], S = [[0, 0, 0], [0, 0, 0], [0, 0, 0]];
  for (let r = 0; r < 3; r++) for (let c = 0; c < 3; c++) S[r][c] = st[o + 7 + r*3 + c] - n*ca[r]*cb[c];
  const q = hornQ(S), R = qmat(q), Rc = mv(R, ca);
  let tr = 0; for (let r = 0; r < 3; r++) for (let c = 0; c < 3; c++) tr += R[r][c]*S[c][r];
  const e2 = (st[o + 16] - n*dot(ca, ca)) + (st[o + 17] - n*dot(cb, cb)) - 2*tr;
  return { q, R, t: [cb[0] - Rc[0], cb[1] - Rc[1], cb[2] - Rc[2]], rms: Math.sqrt(Math.max(0, e2)/n) };
}
// the RMS miss of the points behind some statistics under a given transform T
function rmsUnder(st, o, T){
  const n = st[o], R = T.R, t = T.t, sa = [st[o + 1], st[o + 2], st[o + 3]], sb = [st[o + 4], st[o + 5], st[o + 6]], Ra = mv(R, sa);
  let tr = 0; for (let r = 0; r < 3; r++) for (let c = 0; c < 3; c++) tr += R[r][c]*st[o + 7 + c*3 + r];
  const e2 = st[o + 17] + st[o + 16] + n*dot(t, t) - 2*tr - 2*dot(t, sb) + 2*dot(t, Ra);
  return Math.sqrt(Math.max(0, e2)/n);
}

// ---------- finding the parts ----------
// rest: faces (arrays of points) of the standing kit; samples: [{faces}] at travel samples (same faces).
// opt.candidates: the faces that may become parts (the exporter passes those no rider joint moves). Tolerances are in
// the kit's own metres (times opt.scale). Returns parts [{faces, worstMm, centre, ground, lifts, low}] in build order,
// the per sample transform of each part (T), the faces that do not move (still) and the samples used.
function findParts(rest, samples, opt){
  opt = Object.assign({ moveEps: 0.001, tol: 0.003, mergeTol: 0.02, maxParts: 48, candidates: null, scale: 1 }, opt || {});
  const K = opt.scale, moveEps = opt.moveEps*K, tol = opt.tol*K, mergeTol = opt.mergeTol*K;
  const S = samples.filter(s => s.faces.length === rest.length && s.faces.every((f, i) => !rest[i] || (f && f.length === rest[i].length)));
  const NS = S.length, cand = opt.candidates ? opt.candidates.filter(i => rest[i]) : rest.map((f, i) => i).filter(i => rest[i]);
  const moving = [], still = [];
  for (const i of cand){ const f = rest[i]; let d = 0; for (const s of S){ const g = s.faces[i]; for (let m = 0; m < f.length; m++) d = Math.max(d, dist(f[m], g[m])); }
    (d > moveEps ? moving : still).push(i); }
  if (!NS || !moving.length) return { parts: [], T: [], still, samples: S, moving: 0 };
  const faceStats = i => { const st = new Float64Array(NS*NST); for (let s = 0; s < NS; s++) addStats(st, s*NST, rest[i], S[s].faces[i]); return st; };
  const statsOf = idx => { const st = new Float64Array(NS*NST); for (const i of idx){ const fi = FST.get(i); for (let k = 0; k < st.length; k++) st[k] += fi[k]; } return st; };
  const FST = new Map(); for (const i of moving) FST.set(i, faceStats(i));
  const fitsOf = st => { const T = []; let rms = 0; for (let s = 0; s < NS; s++){ const f = fitStats(st, s*NST); T.push(f); rms = Math.max(rms, f.rms); } return { T, rms }; };
  const errOf = (T, idx) => { let e = 0; for (let s = 0; s < NS; s++) for (const i of idx){ const f = rest[i], g = S[s].faces[i]; for (let m = 0; m < f.length; m++) e = Math.max(e, dist(ap(T[s], f[m]), g[m])); } return e; };
  // 1. greedy rigid groups, seeded in build order
  const left = new Set(moving); let groups = [], gid = 0;
  for (const seed of moving){ if (!left.has(seed)) continue; left.delete(seed); const g = [seed]; let st = statsOf(g), T = fitsOf(st).T;
    for (let pass = 0; pass < 2; pass++){ for (const i of [...left]) if (errOf(T, [i]) < tol){ g.push(i); left.delete(i); } st = statsOf(g); T = fitsOf(st).T; }
    groups.push({ id: gid++, faces: g, st, T, ctr: centre(rest, g) }); }
  // 2. merge the pair whose common fit is closest while it stays within mergeTol (a mane that stretches, a hoof the
  //    page clamps to the ground), past it while there are more than maxParts parts
  // the cost of a pair: under their common fit, the worse of the two groups' RMS misses (a small group must not hide
  // behind a big one), worst sample
  const pairCost = (a, b) => { const st = new Float64Array(a.st.length); for (let k = 0; k < st.length; k++) st[k] = a.st[k] + b.st[k];
    let c = 0; for (let s = 0; s < NS; s++){ const T = fitStats(st, s*NST); c = Math.max(c, rmsUnder(a.st, s*NST, T), rmsUnder(b.st, s*NST, T)); } return c; };
  const near = (a, b) => { for (let s = 0; s < NS; s += 4) if (dist(ap(a.T[s], b.ctr), ap(b.T[s], b.ctr)) > 0.15*K) return false; return true; };
  const pairs = new Map(), key = (a, b) => a.id < b.id ? a.id + ':' + b.id : b.id + ':' + a.id;
  const addPairs = g => { for (const h of groups) if (h !== g) pairs.set(key(g, h), { a: g.id < h.id ? g : h, b: g.id < h.id ? h : g, near: near(g, h), cost: null }); };
  for (let a = 0; a < groups.length; a++) for (let b = a + 1; b < groups.length; b++) pairs.set(key(groups[a], groups[b]), { a: groups[a], b: groups[b], near: near(groups[a], groups[b]), cost: null });
  for (;;){
    const force = groups.length > opt.maxParts; let best = null;
    for (const p of pairs.values()){ if (p.blocked || (!p.near && !force)) continue;
      if (p.cost == null) p.cost = pairCost(p.a, p.b);
      if (!force && p.cost > mergeTol) continue;
      if (!best || p.cost < best.cost - 1e-12 || (Math.abs(p.cost - best.cost) <= 1e-12 && (p.a.id < best.a.id || (p.a.id === best.a.id && p.b.id < best.b.id)))) best = p; }
    if (!best) break;
    const faces = best.a.faces.concat(best.b.faces).sort((x, y) => x - y), st = statsOf(faces), T = fitsOf(st).T;
    if (!force && errOf(T, faces) > mergeTol){ best.blocked = true; continue; }
    for (const k of [...pairs.keys()]){ const p = pairs.get(k); if (p.a === best.a || p.b === best.a || p.a === best.b || p.b === best.b) pairs.delete(k); }
    groups = groups.filter(g => g !== best.a && g !== best.b);
    const g = { id: gid++, faces, st, T, ctr: centre(rest, faces) }; groups.push(g); addPairs(g);
  }
  for (const g of groups) g.faces.sort((x, y) => x - y);
  groups.sort((x, y) => x.faces[0] - y.faces[0]);                 // deterministic: by first face in build order
  const parts = groups.map(g => {
    let lo = Infinity, hi = -Infinity; S.forEach(s => { let m = Infinity; g.faces.forEach(f => s.faces[f].forEach(p => { m = Math.min(m, p[1]); })); lo = Math.min(lo, m); hi = Math.max(hi, m); });
    let ry = Infinity; g.faces.forEach(f => rest[f].forEach(p => { ry = Math.min(ry, p[1]); }));
    return { faces: g.faces, worstMm: Math.round(errOf(g.T, g.faces)*10000)/10, centre: g.ctr, ground: lo < 0.01*K, lifts: hi > 0.03*K, low: ry };
  });
  return { parts, T: groups.map(g => g.T.map(f => ({ q: f.q, R: f.R, t: f.t }))), still, samples: S, moving: moving.length, rest };
}
function centre(rest, faces){ const c = [0, 0, 0]; let n = 0; faces.forEach(i => rest[i].forEach(p => { c[0] += p[0]; c[1] += p[1]; c[2] += p[2]; n++; })); return c.map(x => x/(n || 1)); }
// the lowest points of some faces (rest): the mean of the vertices within eps of the lowest
function lowPoint(rest, faces, eps){ let lo = Infinity; faces.forEach(i => rest[i].forEach(p => { lo = Math.min(lo, p[1]); }));
  const c = [0, 0, 0]; let n = 0; faces.forEach(i => rest[i].forEach(p => { if (p[1] <= lo + eps){ c[0] += p[0]; c[1] += p[1]; c[2] += p[2]; n++; } })); return c.map(x => x/(n || 1)); }

// the point p (rest coordinates) both parts carry alike over every sample — their joint — and how well it fits
function pivot(TA, TB){
  // (R_a - R_b) p = t_b - t_a for every sample: least squares
  const AtA = [[0, 0, 0], [0, 0, 0], [0, 0, 0]], Atb = [0, 0, 0];
  for (let s = 0; s < TA.length; s++){ const D = [0, 1, 2].map(r => [0, 1, 2].map(c => TA[s].R[r][c] - TB[s].R[r][c])), b = [0, 1, 2].map(k => TB[s].t[k] - TA[s].t[k]);
    for (let r = 0; r < 3; r++){ for (let c = 0; c < 3; c++) for (let k = 0; k < 3; k++) AtA[r][c] += D[k][r]*D[k][c]; for (let k = 0; k < 3; k++) Atb[r] += D[k][r]*b[k]; } }
  const tr = AtA[0][0] + AtA[1][1] + AtA[2][2]; for (let i = 0; i < 3; i++) AtA[i][i] += 1e-9 + 1e-6*tr;   // a hinge: the point nearest the origin on its axis
  const p = solve3(AtA, Atb); let e = 0;
  for (let s = 0; s < TA.length; s++) e = Math.max(e, dist(ap(TA[s], p), ap(TB[s], p)));
  return { p, err: e };
}
function solve3(A, b){ const m = A.map((r, i) => r.concat([b[i]]));
  for (let c = 0; c < 3; c++){ let piv = c; for (let r = c + 1; r < 3; r++) if (Math.abs(m[r][c]) > Math.abs(m[piv][c])) piv = r; [m[c], m[piv]] = [m[piv], m[c]];
    for (let r = 0; r < 3; r++){ if (r === c) continue; const f = m[r][c]/m[c][c]; for (let k = c; k < 4; k++) m[r][k] -= f*m[c][k]; } }
  return [m[0][3]/m[0][0], m[1][3]/m[1][1], m[2][3]/m[2][2]]; }

// ---------- the tree of parts and the legs ----------
// Node P (= parts.length) is the pelvis: the faces that do not move with travel stay on it (T = identity). Parts join
// the tree where they share a pivot with a part already in it (closest first: a minimum spanning tree grown from the
// pelvis); when none does, the biggest part left hangs from the pelvis as a free part (the mount's body: it bobs).
// A leg is the chain from a free part down to a part that touches the ground some of the time; the last two jointed
// parts above the ground part (or the ground part itself) are its upper and lower segment for the two-bone IK.
function buildTree(found, opt){
  opt = Object.assign({ jointTol: 0.03, near: 0.15, scale: 1 }, opt || {});
  const P = found.parts, n = P.length, K = opt.scale, tol = opt.jointTol*K, NS = found.samples.length, rest = found.rest;
  // a joint must sit on both parts (a part that only bobs fits a far-away "pivot" of a tiny turn): near one of its
  // vertices, or inside its box (a hip deep inside a big barrel is far from every vertex of the barrel)
  const box = P.map(p => { const lo = [Infinity, Infinity, Infinity], hi = [-Infinity, -Infinity, -Infinity];
    for (const f of p.faces) for (const v of rest[f]) for (let k = 0; k < 3; k++){ lo[k] = Math.min(lo[k], v[k]); hi[k] = Math.max(hi[k], v[k]); } return [lo, hi]; });
  const nearOf = (i, p) => { if (i === n) return true; const [lo, hi] = box[i]; if ([0, 1, 2].every(k => p[k] >= lo[k] && p[k] <= hi[k])) return true;
    let m = Infinity; for (const f of P[i].faces) for (const v of rest[f]) m = Math.min(m, dist(v, p)); return m <= opt.near*K; };
  const TI = []; for (let s = 0; s < NS; s++) TI.push({ R: [[1, 0, 0], [0, 1, 0], [0, 0, 1]], t: [0, 0, 0] });
  const T = found.T.concat([TI]), E = [], PV = [];
  for (let a = 0; a <= n; a++){ E.push([]); PV.push([]); for (let b = 0; b <= n; b++){ if (a === b){ E[a].push(0); PV[a].push(null); continue; }
    if (b < a){ E[a].push(E[b][a]); PV[a].push(PV[b][a]); continue; } const pv = pivot(T[a], T[b]);
    E[a].push(nearOf(a, pv.p) && nearOf(b, pv.p) ? pv.err : Infinity); PV[a].push(pv.p); } }
  const parent = new Array(n + 1).fill(-1), joint = new Array(n + 1).fill(null), jointErr = new Array(n + 1).fill(null), free = new Array(n + 1).fill(false), inTree = new Set([n]);
  while (inTree.size < n + 1){
    let best = null;
    for (const a of inTree) for (let b = 0; b < n; b++){ if (inTree.has(b) || E[a][b] > tol) continue;
      if (!best || E[a][b] < best.e - 1e-12) best = { a, b, e: E[a][b] }; }
    if (best){ parent[best.b] = best.a; joint[best.b] = PV[best.a][best.b]; jointErr[best.b] = best.e; inTree.add(best.b); continue; }
    let big = -1; for (let b = 0; b < n; b++) if (!inTree.has(b) && (big < 0 || P[b].faces.length > P[big].faces.length)) big = b;
    parent[big] = n; free[big] = true; inTree.add(big);
  }
  const depthOf = i => { let d = 0; while (i !== n && !free[i]){ i = parent[i]; d++; } return d; };
  const legs = [];
  for (let f = 0; f < n; f++){
    if (!P[f].ground || !P[f].lifts || free[f]) continue;
    if (P.some((q, i) => i !== f && parent[i] === f && q.ground)) continue;          // a lower part also touches: not the foot
    const chain = []; let i = f; while (i !== n && !free[i]){ chain.unshift(i); i = parent[i]; }
    if (chain.length < 2) continue;
    const top = i, c = chain.slice(-3), three = c.length === 3;
    legs.push({ foot: f, body: top, chain, upper: three ? c[0] : c[c.length - 2], lower: three ? c[1] : c[c.length - 1], end: three ? c[2] : null,
      hip: joint[three ? c[0] : c[c.length - 2]], knee: joint[three ? c[1] : c[c.length - 1]], ankle: three ? joint[c[2]] : null,
      errMm: Math.round(Math.max(...c.map(x => jointErr[x] || 0))*10000)/10 });
  }
  return { parent, joint, jointErr, free, legs, depth: P.map((p, i) => depthOf(i)), pelvis: n };
}

// ---------- the rig as kits.json keeps it ----------
// d = pageSampleMount(...) over every face; opt.candidates = the faces no rider joint moves. Bones (parents first):
// the mount's body (the biggest free part that only sways), per leg its upper / lower segment and foot, then the
// other parts. A leg the gait can re-solve is rigid (each segment within maxSegMm, joints within maxJointMm).
const r5 = v => Math.round(v*1e5)/1e5, v5 = a => a.map(r5);
function buildRig(d, opt){
  opt = Object.assign({ candidates: null, maxSegMm: 20, maxJointMm: 20 }, opt || {});
  const K = d.scale || 1, found = findParts(d.rest, d.samples, { candidates: opt.candidates, scale: K });
  const out = { parts: found.parts.length, moving: found.moving, samples: found.samples.length, cycle: null, gait: false, why: null, bones: [], legs: [] };
  if (!found.parts.length){ out.why = found.samples.length ? 'nothing moves with travel' : 'the page changes the face count while it moves'; return out; }
  const tree = buildTree(found, { scale: K }), P = found.parts, n = P.length, S = found.samples, rest = d.rest;
  const turn = found.T.map(Ts => Math.max(...Ts.map(T => 2*Math.acos(Math.min(1, Math.abs(T.q[3]))))));
  let body = -1;
  P.forEach((p, i) => { if (tree.free[i] && turn[i] < 15*Math.PI/180 && p.faces.length >= 0.2*found.moving && (body < 0 || p.faces.length > P[body].faces.length)) body = i; });
  const legs = tree.legs.filter(L => L.body === body || L.body === n);
  legs.sort((a, b) => (b.hip[2] - a.hip[2]) || (b.hip[0] - a.hip[0]));               // front first, then left first
  const segOk = L => L.chain.length <= 3 && [L.upper, L.lower, L.end].every(i => i == null || P[i].worstMm <= opt.maxSegMm*K) && L.errMm <= opt.maxJointMm*K;
  // every part that steps on the ground must be the foot of one of those legs (else it would slide while the rest is pinned)
  const feetOk = P.every((p, i) => !(p.ground && p.lifts) || legs.some(L => L.foot === i));
  out.gait = legs.length >= 2 && legs.every(segOk) && feetOk;
  if (!out.gait) out.why = legs.length < 2 ? 'fewer than two legs hang from the body' : !legs.every(segOk) ? 'a leg part bends (not rigid) or a joint does not hold'
    : 'a part that steps on the ground is not the foot of a leg found from the body';
  // the page's own stride (travel per cycle) and each leg's phase in it, from the fastest samples: the swing of the
  // upper segment (its angle forward of straight down; the page swings it as a sine of travel); one cycle length for
  // all legs, least squares over a + b sin + c cos. Phase pi = the leg straight down moving back (mid stance).
  const vmax = Math.max(...S.map(s => s.v)), si = S.map((s, i) => i).filter(i => S[i].v === vmax), legEnd = L => L.end != null ? L.ankle : lowPoint(rest, P[L.lower].faces, 0.003*K);
  const series = legs.map(L => si.map(i => { const H = ap(found.T[L.upper][i], L.hip), Kn = ap(found.T[L.upper][i], L.knee); return Math.atan2(Kn[2] - H[2], H[1] - Kn[1]); })), trs = si.map(i => S[i].tr);
  const fitC = C => { let res = 0; const ph = []; for (const z of series){ const w = 2*Math.PI/C, A = [[0, 0, 0], [0, 0, 0], [0, 0, 0]], b = [0, 0, 0];
      trs.forEach((t, j) => { const f = [1, Math.sin(w*t), Math.cos(w*t)]; for (let r = 0; r < 3; r++){ b[r] += f[r]*z[j]; for (let c = 0; c < 3; c++) A[r][c] += f[r]*f[c]; } });
      for (let r = 0; r < 3; r++) A[r][r] += 1e-12; const x = solve3(A, b); trs.forEach((t, j) => { const e = z[j] - x[0] - x[1]*Math.sin(w*t) - x[2]*Math.cos(w*t); res += e*e; });
      ph.push({ phase: Math.atan2(x[2], x[1]), amp: Math.hypot(x[1], x[2]) }); } return { res, ph }; };
  if (legs.length && trs.length >= 8){
    let best = null; for (let C = 0.4*K; C <= 6*K; C += 0.01*K){ const f = fitC(C); if (!best || f.res < best.res) best = { C, res: f.res }; }
    for (let C = best.C - 0.01*K; C <= best.C + 0.01*K; C += 0.0002*K){ const f = fitC(C); if (f.res < best.res) best = { C, res: f.res }; }
    out.cycle = r5(best.C); const f = fitC(best.C); legs.forEach((L, i) => { L.phase = f.ph[i].phase; L.amp = f.ph[i].amp; });
  }
  // which side each knee bends to: the knee's offset from the hip-to-end line over the samples
  legs.forEach(L => { let acc = [0, 0, 0]; const E = legEnd(L);
    S.forEach((s, i) => { const H = ap(found.T[L.upper][i], L.hip), Kn = ap(found.T[L.upper][i], L.knee), A = ap(found.T[L.lower][i], E), u = norm(sub(A, H)), o = sub(Kn, H);
      acc = add(acc, sub(o, scl(u, dot(o, u)))); });
    L.pole = Math.hypot(acc[0], acc[1], acc[2]) > 1e-6*S.length*K ? norm(acc) : [0, 0, 1]; });
  // bones: parents first; a part hung from a leg segment that is not on that leg goes to the leg's top
  const onLeg = new Map(); legs.forEach((L, li) => L.chain.forEach(i => onLeg.set(i, li)));
  const parent = tree.parent.slice(), joined = P.map((p, i) => !tree.free[i]);
  for (let i = 0; i < n; i++) if (!onLeg.has(i) && onLeg.has(parent[i])){ parent[i] = legs[onLeg.get(parent[i])].body; joined[i] = false; }
  // depth first from the pelvis (the order Godot's importer gives the bones, so skin and skeleton agree): the body,
  // then the legs in order, then the other parts by their first face
  const order = [], name = new Map(), role = new Map(), kids = new Map();
  for (let i = 0; i < n; i++){ if (!kids.has(parent[i])) kids.set(parent[i], []); kids.get(parent[i]).push(i); }
  const rank = i => i === body ? [0, 0] : onLeg.has(i) ? [1, onLeg.get(i)*100 + legs[onLeg.get(i)].chain.indexOf(i)] : [2, P[i].faces[0]];
  for (const c of kids.values()) c.sort((a, b) => { const x = rank(a), y = rank(b); return x[0] - y[0] || x[1] - y[1]; });
  let more = 0;
  const visit = i => { if (i !== n){ order.push(i);
      if (i === body){ name.set(i, 'mount_body'); role.set(i, 'body'); }
      else if (onLeg.has(i)){ const li = onLeg.get(i), L = legs[li], r = i === L.upper ? 'upper' : i === L.lower ? 'lower' : i === L.end ? 'foot' : 'part';
        name.set(i, 'mount_leg' + li + '_' + (r === 'part' ? 'top' + L.chain.indexOf(i) : r)); role.set(i, r); }
      else { name.set(i, 'mount_part' + (more++)); role.set(i, 'part'); } }
    for (const c of kids.get(i) || []) visit(c); };
  visit(n);
  const boneName = i => i === n ? 'pelvis' : name.get(i);
  out.bones = order.map(i => ({ name: name.get(i), parent: boneName(parent[i]), role: role.get(i), origin: v5(joined[i] && tree.joint[i] ? tree.joint[i] : P[i].centre),
    jointMm: joined[i] && tree.jointErr[i] != null ? Math.round(tree.jointErr[i]*10000)/10 : null, worstMm: P[i].worstMm, ground: P[i].ground, faces: P[i].faces }));
  out.legs = legs.map(L => { const E = legEnd(L), c = lowPoint(rest, P[L.foot].faces, 0.003*K);
    return { upper: name.get(L.upper), lower: name.get(L.lower), foot: L.end != null ? name.get(L.end) : null, hip: v5(L.hip), knee: v5(L.knee), end: v5(E), contact: v5(c),
      l1: r5(dist(L.hip, L.knee)), l2: r5(dist(L.knee, E)), phase: L.phase != null ? r5(L.phase) : null, amp: L.amp != null ? r5(L.amp) : null, pole: v5(L.pole), errMm: L.errMm }; });
  out.body = body >= 0 ? 'mount_body' : null;
  return out;
}

// ---------- the gait ----------
// Two-bone IK in the rest frame of the leg: hip H, knee K0, end A0 (ankle or contact point) at rest; target X for the
// end; pole = the side the knee bends to. Returns the upper and lower segments' rotations (from their rest) and the knee.
function ik2(H, K0, A0, X, pole, reachK){
  const l1 = dist(H, K0), l2 = dist(K0, A0); let d = dist(H, X), u = norm(sub(X, H));
  const dmax = (l1 + l2)*(reachK || 0.999), dmin = Math.abs(l1 - l2)*1.001 + 1e-6, short = d > dmax;
  d = Math.min(dmax, Math.max(dmin, d));
  let v = sub(pole, scl(u, dot(pole, u))); if (Math.hypot(v[0], v[1], v[2]) < 1e-9) v = norm(cross(u, [1, 0, 0])); v = norm(v);
  const ca = Math.max(-1, Math.min(1, (l1*l1 + d*d - l2*l2)/(2*l1*d))), sa = Math.sqrt(1 - ca*ca);
  const K = add(H, add(scl(u, l1*ca), scl(v, l1*sa))), A = add(H, scl(u, d));
  const qUp = qFromTo2(sub(K0, H), sub(A0, H), sub(K, H), sub(A, H));
  const qLo = qmul(qFromTo1(qrot(qUp, sub(A0, K0)), sub(A, K)), qUp);
  return { qUp, qLo, K, A, short };
}
// the rotation taking direction a onto b (shortest arc)
function qFromTo1(a, b){ a = norm(a); b = norm(b); const c = cross(a, b), d = dot(a, b);
  if (d < -0.999999){ let ax = cross(a, [1, 0, 0]); if (Math.hypot(ax[0], ax[1], ax[2]) < 1e-6) ax = cross(a, [0, 1, 0]); return qaxis(ax, Math.PI); }
  return qnorm([c[0], c[1], c[2], 1 + d]); }
// the rotation taking the pair (a1 along, a2 in plane) onto (b1, b2): frames built from each pair
function qFromTo2(a1, a2, b1, b2){
  const fa = (x, y) => { const e1 = norm(x); let n = cross(x, y); if (Math.hypot(n[0], n[1], n[2]) < 1e-9) n = cross(x, [1, 0, 0]); const e3 = norm(n); return [e1, cross(e3, e1), e3]; };
  const A = fa(a1, a2), B = fa(b1, b2); return qmul(qframe(B[0], B[1], B[2]), qconj(qframe(A[0], A[1], A[2])));
}
// the plan of a gait: every leg keeps the page's phase; a foot is on the ground for the duty fraction beta of the
// cycle and stays where it landed. The stance length is what the stiffest leg can reach with the body dropped at
// most `drop`; the cycle is that length / beta. legs: [{H, A, l, phase}] (rest, kit metres), v: travel speed.
function planGait(legs, opt){
  const o = Object.assign({ beta: 0.6, drop: 0.03, reachK: 0.98, minStance: 0.12, maxStance: 2 }, opt || {});
  let half = Infinity;
  for (const L of legs){ const dx = L.A[0] - L.H[0], dy = L.H[1] - L.A[1] - o.drop, r = L.l*o.reachK;
    const h = Math.sqrt(Math.max(0, r*r - dx*dx - dy*dy)) - Math.abs(L.A[2] - L.H[2]); half = Math.min(half, h); }
  const Ls = Math.min(o.maxStance, Math.max(o.minStance, 2*half)), C = Ls/o.beta;
  return { beta: o.beta, stance: Ls, cycle: C, reachLimited: 2*half < o.minStance, drop: o.drop };
}
// where a foot is at travel d of the cycle (kit metres, in the figure's own frame: it moves in place, the ground
// slides back under it): planted (z falls at the travel speed) or in the air (smooth arc to the next landing)
function footAt(plan, L, d, lift){
  const TAU = Math.PI*2, th = ((TAU*d/plan.cycle + L.phase) % TAU + TAU) % TAU, b = plan.beta, Ls = plan.stance;
  const td = Math.PI*(1 - b), lo = Math.PI*(1 + b);                        // touchdown, lift-off (stance centred on pi)
  if (th >= td && th <= lo){ const s = (th - td)/(lo - td); return { p: [L.A[0], L.A[1], L.A[2] + Ls/2 - s*Ls], stance: true, s }; }
  // in the air: on the ground the foot moves one cycle ahead (eased: it leaves and lands at rest), while the figure
  // itself covers (1 - beta) of a cycle; in the figure's frame that is the difference
  const s = ((th - lo) % TAU + TAU) % TAU/(TAU*(1 - b)), e = s*s*(3 - 2*s);
  return { p: [L.A[0], L.A[1] + lift*16*s*s*(1 - s)*(1 - s), L.A[2] - Ls/2 + plan.cycle*e - plan.cycle*(1 - b)*s], stance: false, s };
}
// how far the body must drop so every hip reaches its foot (kit metres)
function dropFor(legs, feet, bodyAt, reach){
  let D = 0;
  legs.forEach((L, i) => { const H = bodyAt(L.H), X = feet[i], dx = X[0] - H[0], dz = X[2] - H[2], r = L.l*reach, h = r*r - dx*dx - dz*dz;
    const need = h > 0 ? (H[1] - X[1]) - Math.sqrt(h) : (H[1] - X[1]); D = Math.max(D, need); });
  return D;
}

module.exports = { pageSampleMount, unpackSamples, pageMountFaces, findParts, buildTree, buildRig, pivot, rigidFit, hornQ, qmat, mv, ap, dist, lowPoint, centre,
  ik2, planGait, footAt, dropFor, qmul, qconj, qnorm, qrot, qaxis, qslerp, qFromTo1, xf, xmul, xinv, XI, add, sub, scl, dot, cross, norm };
