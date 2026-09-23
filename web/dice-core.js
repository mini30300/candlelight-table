// ==DICE-BEGIN==
// Shared dice: the same throw on every player's screen.
//
// The value is NOT decided here. The server rolls it and puts it in the room log, so every client already receives
// the same number; this only has to SHOW it. Given (kind, value, seed) the throw is fully determined: the seed drives
// a small PRNG instead of Math.random, the flight is simulated to rest offline, and the die's labels are then rotated
// by a true symmetry of the solid so the face that ended up on top reads `value`. Same inputs on every phone means
// the same tumble and the same landing face -- no syncing of the animation itself, and no way for two players to see
// different numbers.
//
// Originally ported from the stand-alone dice tray page, which has since been removed; this is now the only copy
// of the physics (board.html carries it verbatim, checked by dice-check.js).
var DICE = (function(){
"use strict";
var D = Math.PI/180;
function clamp(v,a,b){ return v<a?a:v>b?b:v; }
function add(a,b){ return [a[0]+b[0],a[1]+b[1],a[2]+b[2]]; }
function sub(a,b){ return [a[0]-b[0],a[1]-b[1],a[2]-b[2]]; }
function mul(a,s){ return [a[0]*s,a[1]*s,a[2]*s]; }
function dot(a,b){ return a[0]*b[0]+a[1]*b[1]+a[2]*b[2]; }
function cross(a,b){ return [a[1]*b[2]-a[2]*b[1], a[2]*b[0]-a[0]*b[2], a[0]*b[1]-a[1]*b[0]]; }
function len(a){ return Math.sqrt(dot(a,a)); }
function norm(a){ var l=len(a)||1; return [a[0]/l,a[1]/l,a[2]/l]; }
function qmul(a,b){ var ax=a[0],ay=a[1],az=a[2],aw=a[3],bx=b[0],by=b[1],bz=b[2],bw=b[3];
  return [aw*bx+ax*bw+ay*bz-az*by, aw*by-ax*bz+ay*bw+az*bx, aw*bz+ax*by-ay*bx+az*bw, aw*bw-ax*bx-ay*by-az*bz]; }
function qconj(q){ return [-q[0],-q[1],-q[2],q[3]]; }
function qnorm(q){ var l=Math.sqrt(q[0]*q[0]+q[1]*q[1]+q[2]*q[2]+q[3]*q[3])||1; return [q[0]/l,q[1]/l,q[2]/l,q[3]/l]; }
function qrot(q,v){ var x=q[0],y=q[1],z=q[2],w=q[3], ux=y*v[2]-z*v[1], uy=z*v[0]-x*v[2], uz=x*v[1]-y*v[0], vx=y*uz-z*uy, vy=z*ux-x*uz, vz=x*uy-y*ux;
  return [v[0]+2*(w*ux+vx), v[1]+2*(w*uy+vy), v[2]+2*(w*uz+vz)]; }
function qaxis(axis, ang){ var s = Math.sin(ang/2), a = norm(axis); return [a[0]*s, a[1]*s, a[2]*s, Math.cos(ang/2)]; }
function qFromTo(a,b){ var c = cross(a,b), d = dot(a,b); if (d < -0.99999){ var ax = Math.abs(a[0]) < 0.9 ? [1,0,0] : [0,1,0]; return qaxis(cross(a,ax), Math.PI); } return qnorm([c[0],c[1],c[2],1+d]); }

// mulberry32: small, fast, and identical on every engine, which is the whole point here
function rngFrom(seed){ var a = (seed >>> 0) || 1; return function(){
  a |= 0; a = a + 0x6D2B79F5 | 0;
  var t = Math.imul(a ^ a >>> 15, 1 | a); t = t + Math.imul(t ^ t >>> 7, 61 | t) ^ t;
  return ((t ^ t >>> 14) >>> 0) / 4294967296; }; }

// ---------- polyhedra. values so that opposite faces sum to max+1 (or 9 for the d10), like real dice ----------
function pairValues(verts, faces, max, sumTo){
  var C = faces.map(function(f){ var c=[0,0,0]; f.forEach(function(vi){ c = add(c, verts[vi]); }); return norm(c); });
  var vals = new Array(faces.length), used = {}, next = max === 9 ? 0 : 1, hi = sumTo;
  for (var i=0;i<faces.length;i++){ if (vals[i] !== undefined) continue; var opp = -1, bd = 1; for (var j=0;j<faces.length;j++){ var d = dot(C[i],C[j]); if (d < bd){ bd = d; opp = j; } }
    vals[i] = next; vals[opp] = hi - next; next++; while (used[next]) next++; used[vals[i]] = 1; used[vals[opp]] = 1; while (used[next]) next++; }
  return vals;
}
function poly(verts, faces, values, opts){
  var R = 0; verts.forEach(function(v){ R = Math.max(R, len(v)); }); verts = verts.map(function(v){ return mul(v, 1/R); });
  var F = faces.map(function(f, i){ var c = [0,0,0]; f.forEach(function(vi){ c = add(c, verts[vi]); }); c = mul(c, 1/f.length);
    var n = norm(cross(sub(verts[f[1]],verts[f[0]]), sub(verts[f[2]],verts[f[0]]))); if (dot(n,c) < 0){ n = mul(n,-1); f = f.slice().reverse(); }
    return { v:f, n:n, c:c, val:values[i] }; });
  var inr = 1e9; F.forEach(function(f){ inr = Math.min(inr, dot(f.n, f.c)); });
  return { verts:verts, faces:F, inr:inr, opts:opts||{} };
}
var PHI = (1+Math.sqrt(5))/2;
function facesFromHull(v, k, nF){
  var n = v.length, faces = [], seen = {};
  for (var a=0;a<n;a++) for (var b=a+1;b<n;b++) for (var c=b+1;c<n;c++){
    var nn = cross(sub(v[b],v[a]), sub(v[c],v[a])); if (len(nn) < 1e-6) continue; nn = norm(nn); var d0 = dot(nn, v[a]);
    var on = [], out = false, i, d;
    for (i=0;i<n;i++){ d = dot(nn, v[i]) - d0; if (d > 1e-6){ out = true; break; } if (Math.abs(d) < 1e-6) on.push(i); }
    if (out){ nn = mul(nn,-1); d0 = -d0; out = false; on = [];
      for (i=0;i<n;i++){ d = dot(nn, v[i]) - d0; if (d > 1e-6){ out = true; break; } if (Math.abs(d) < 1e-6) on.push(i); } }
    if (out || on.length !== k) continue;
    var key = on.slice().sort(function(x,y){ return x-y; }).join(','); if (seen[key]) continue; seen[key] = 1;
    var cen = [0,0,0]; on.forEach(function(i2){ cen = add(cen, v[i2]); }); cen = mul(cen, 1/k);
    var ux = norm(sub(v[on[0]], cen)), uy = cross(nn, ux);
    on.sort(function(p,q){ var dp = sub(v[p],cen), dq = sub(v[q],cen); return Math.atan2(dot(dp,uy),dot(dp,ux)) - Math.atan2(dot(dq,uy),dot(dq,ux)); });
    faces.push(on); if (faces.length === nF) return faces;
  }
  return faces;
}
function tetra(){ var v=[[1,1,1],[1,-1,-1],[-1,1,-1],[-1,-1,1]]; return poly(v, [[0,1,2],[0,3,1],[0,2,3],[1,3,2]], [1,2,3,4], { vertexRead:true }); }
function cube(){ var v=[]; for (var i=0;i<8;i++) v.push([i&1?1:-1, i&2?1:-1, i&4?1:-1]);
  var F = [[0,1,3,2],[4,6,7,5],[0,4,5,1],[2,3,7,6],[0,2,6,4],[1,5,7,3]]; return poly(v, F, pairValues(v, F, 6, 7)); }
function octa(){ var v=[[1,0,0],[-1,0,0],[0,1,0],[0,-1,0],[0,0,1],[0,0,-1]];
  var F = [[0,2,4],[2,1,4],[1,3,4],[3,0,4],[2,0,5],[1,2,5],[3,1,5],[0,3,5]]; return poly(v, F, pairValues(v, F, 8, 9)); }
function d10(){
  var r = 0.72, A = 1, lo = 0, hi = 0.5, h;
  for (var it=0; it<40; it++){ h = (lo+hi)/2; var T=[0,A,0], U1=[r,h,0], L=[r*Math.cos(36*D),-h,r*Math.sin(36*D)], U2=[r*Math.cos(72*D),h,r*Math.sin(72*D)];
    var vol = dot(cross(sub(U1,T), sub(U2,T)), sub(L,T)); if (vol > 0) hi = h; else lo = h; }
  var v=[[0,A,0],[0,-A,0]]; for (var i=0;i<10;i++){ var a=i*36*D; v.push([Math.cos(a)*r, (i%2?h:-h), Math.sin(a)*r]); }
  var F=[]; for (var k=0;k<10;k++){ var a2=2+k, b=2+(k+1)%10, c=2+(k+2)%10; F.push(k%2 ? [0,a2,b,c] : [1,c,b,a2]); }
  return poly(v, F, pairValues(v, F, 9, 9)); }
function dodeca(){ var v=[], i, j, k; for (i=-1;i<=1;i+=2) for (j=-1;j<=1;j+=2) for (k=-1;k<=1;k+=2) v.push([i,j,k]);
  for (i=-1;i<=1;i+=2) for (j=-1;j<=1;j+=2){ v.push([0, i/PHI, j*PHI]); v.push([i/PHI, j*PHI, 0]); v.push([i*PHI, 0, j/PHI]); }
  var F = facesFromHull(v, 5, 12); return poly(v, F, pairValues(v, F, 12, 13)); }
function icosa(){ var v=[], i, j; for (i=-1;i<=1;i+=2) for (j=-1;j<=1;j+=2){ v.push([0, i, j*PHI]); v.push([i, j*PHI, 0]); v.push([j*PHI, 0, i]); }
  var F = facesFromHull(v, 3, 20); return poly(v, F, pairValues(v, F, 20, 21)); }
var SHAPES = null;   // built on first use: a d12/d20 hull search is not worth paying for if nobody rolls
function shapes(){ if (!SHAPES) SHAPES = { 4:tetra(), 6:cube(), 8:octa(), 10:d10(), 12:dodeca(), 20:icosa() }; return SHAPES; }

// the rotation of the solid onto itself carrying face `from` onto face `to`
function symmetry(S, from, to, j){
  var fa = S.faces[from], fb = S.faces[to], q1 = qFromTo(fa.n, fb.n);
  var va = sub(qrot(q1, S.verts[fa.v[j]]), mul(fb.n, dot(fb.n, qrot(q1, S.verts[fa.v[j]])))), vb = sub(S.verts[fb.v[0]], mul(fb.n, dot(fb.n, S.verts[fb.v[0]])));
  var ang = Math.atan2(dot(cross(va,vb), fb.n), dot(va,vb));
  return qmul(qaxis(fb.n, ang), q1);
}
// relabel so that face `up` shows `want`: the values move with a true symmetry, so it stays a real die
function relabel(S, up, want){
  var from = -1; S.faces.forEach(function(f,i){ if (f.val === want) from = i; }); if (from < 0 || from === up) return S.faces.map(function(f){ return f.val; });
  var q = symmetry(S, from, up, 0), out = [];
  S.faces.forEach(function(f, i){ var c = qrot(qconj(q), f.c), best = 0, bd = -2; S.faces.forEach(function(g, k){ var d = dot(c, g.c); if (d > bd){ bd = d; best = k; } }); out[i] = S.faces[best].val; });
  return out;
}

// ---------- physics: rigid body with vertex contacts against a small tray ----------
var TRAY = { x:0.62, z:0.62 }, G = -9.8, DT = 1/120;
function stepDie(d, dt){
  if (d.done) return;
  var e = 0.32, mu = 0.45, hitAny = false;
  d.v[1] += G*dt; d.p = add(d.p, mul(d.v, dt));
  var wl = len(d.w); if (wl > 1e-6) d.q = qnorm(qmul(qaxis(d.w, wl*dt), d.q));
  for (var it=0; it<2; it++){
    var deepest = 0, dv = null, dn = null;
    for (var i=0;i<d.S.verts.length;i++){ var r = qrot(d.q, mul(d.S.verts[i], d.r)), x = add(d.p, r);
      var cands = [[x[1], [0,1,0]], [TRAY.x - x[0], [-1,0,0]], [x[0] + TRAY.x, [1,0,0]], [TRAY.z - x[2], [0,0,-1]], [x[2] + TRAY.z, [0,0,1]]];
      for (var c=0;c<cands.length;c++){ var pen = -cands[c][0]; if (pen > deepest){ deepest = pen; dv = r; dn = cands[c][1]; } } }
    if (!dv) break;
    hitAny = true;
    d.p = add(d.p, mul(dn, deepest));
    var vp = add(d.v, cross(d.w, dv)), vn = dot(vp, dn);
    if (vn < 0){
      var rn = cross(dv, dn), k = 1/d.m + dot(cross(rn, dv), dn)/d.I, j = -(1+e)*vn/k;
      d.v = add(d.v, mul(dn, j/d.m)); d.w = add(d.w, mul(cross(dv, mul(dn, j)), 1/d.I));
      var vt = sub(vp, mul(dn, vn)), vtl = len(vt);
      if (vtl > 1e-6){ var jt = Math.min(mu*j, vtl/k), imp = mul(vt, -jt/vtl); d.v = add(d.v, mul(imp, 1/d.m)); d.w = add(d.w, mul(cross(dv, imp), 1/d.I)); }
    }
  }
  if (hitAny){ d.v = mul(d.v, 0.985); d.w = mul(d.w, 0.965); }
  d.v = mul(d.v, 1 - 0.02*dt); d.w = mul(d.w, 1 - 0.05*dt);
  var sp = len(d.v), wl2 = len(d.w);
  if (sp < 0.12 && wl2 < 1.2 && d.p[1] < d.r*1.05){
    var dnf = downFace(d), n = qrot(d.q, d.S.faces[dnf].n), tilt = Math.acos(clamp(-n[1],-1,1));
    if (tilt < 14*D){ d.snapQ = qmul(qFromTo(n, [0,-1,0]), d.q); d.snapY = d.r*d.S.inr; d.done = true; }
  }
}
function downFace(d){ var best = 0, bd = 2; d.S.faces.forEach(function(f, i){ var y = qrot(d.q, f.n)[1]; if (y < bd){ bd = y; best = i; } }); return best; }
function upFace(d){ var best = 0, bd = -2; d.S.faces.forEach(function(f, i){ var y = qrot(d.q, f.n)[1]; if (y > bd){ bd = y; best = i; } }); return best; }
function upVertex(d){ var best = 0, bd = -2; d.S.verts.forEach(function(v, i){ var y = qrot(d.q, v)[1]; if (y > bd){ bd = y; best = i; } }); return best; }

// One throw of one die. `value` is the server's result; `seed` makes the flight identical on every device.
// Returns the recorded flight plus the labelling that makes the resting face read `value`.
function roll(kind, value, seed){
  var S = shapes()[kind]; if (!S) return null;                       // d100 and anything else: no dice, just the number
  var rnd = rngFrom(seed);
  var size = kind === 4 ? 0.23 : kind === 6 ? 0.2 : kind === 20 ? 0.24 : 0.22;
  var d = { kind:kind, S:S, r:size,
    p: [(rnd()-0.5)*0.5, 0.62 + rnd()*0.2, TRAY.z - 0.2],
    v: [(rnd()-0.5)*1.2, 0.2 + rnd()*0.5, -1.7 - rnd()*1.2],
    q: qnorm([rnd()-0.5, rnd()-0.5, rnd()-0.5, rnd()-0.5]),
    w: [(rnd()-0.5)*24, (rnd()-0.5)*14, (rnd()-0.5)*24],
    m:1, I:0.4*size*size, done:false };
  var frames = [], t = 0, maxT = 6;
  while (t < maxT){
    stepDie(d, DT); stepDie(d, DT); t += 2*DT;
    frames.push({ p: d.p.slice(), q: d.q.slice() });
    if (d.done) break;
  }
  if (!d.done){   // ran out of time still tumbling: drop it onto whichever face is down
    var dn = downFace(d), nn = qrot(d.q, d.S.faces[dn].n);
    d.snapQ = qmul(qFromTo(nn,[0,-1,0]), d.q); d.snapY = d.r*d.S.inr; d.done = true;
  }
  d.q = d.snapQ;
  var labels;
  if (S.opts.vertexRead){   // a d4 is read at the top vertex: that vertex's value sits on the face opposite it
    var vi = upVertex(d), opp = -1;
    S.faces.forEach(function(f,i){ if (f.v.indexOf(vi) < 0) opp = i; });
    labels = relabel(S, opp, value);
  } else labels = relabel(S, upFace(d), value);
  var rest = { p: [d.p[0], d.snapY, d.p[2]], q: d.snapQ.slice() };
  frames.push(rest);
  return { kind:kind, value:value, r:size, S:S, labels:labels, frames:frames, rest:rest, secs: frames.length*2*DT };
}
// what the die actually reads at rest, from its own geometry -- used by the harness to prove the relabel is honest
function faceUp(res){
  var d = { S:res.S, q:res.rest.q, r:res.r };
  if (res.S.opts.vertexRead){ var vi = upVertex(d), f = res.S.faces;
    for (var i=0;i<f.length;i++) if (f[i].v.indexOf(vi) < 0) return res.labels[i]; return res.labels[0]; }
  return res.labels[upFace(d)];
}
return { roll:roll, faceUp:faceUp, shapes:shapes, qrot:qrot, TRAY:TRAY, rngFrom:rngFrom };
})();
// ==DICE-END==
if (typeof module !== "undefined") module.exports = DICE;
