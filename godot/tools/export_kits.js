#!/usr/bin/env node
// export_kits.js — runs battle-table.html headlessly and exports every figure kit (MINI.KITS) as a glTF binary
// (.glb) with flat-shaded materials and, where the humanoid rig moves the geometry, a 23-joint skeleton with rigid
// skin weights. Also writes kits.json (the manifest). Nothing in the page is modified.
//
//   CHROMIUM_PATH=$(ls -d /opt/pw-browsers/chromium-*/chrome-linux*/chrome | head -1) node godot/tools/export_kits.js
//   options: --out DIR (default godot/assets/kits)  --only k1,k2  --page FILE  --check (verify existing .glb files only)
//
// Coordinates are exported exactly as the page builds them: metres, +Y up, the figure faces +Z, its left is +X.
// A mount (horse, beast) also gets a bone for each part the page moves with travel (legs, hooves, tail: mount_rig.js),
// after the 23 joints and under the pelvis, when its legs are rigid chains the animation bake can re-solve
// (mountRig.gait); kits.json mountRig lists the bones, or says why there are none (mountRig.why).
'use strict';
const fs = require('fs'), path = require('path');
const MR = require('./mount_rig.js');
const ROOT = path.resolve(__dirname, '..', '..');
const ARGS = parseArgs(process.argv.slice(2));
const PAGE = path.resolve(ROOT, ARGS.page || 'app/src/main/assets/battle-table.html');
const OUT = path.resolve(ROOT, ARGS.out || 'godot/assets/kits');
const JOINT_SHIFT = 50;            // how far (m) a joint is moved to see which faces follow it
const MOVE_EPS = 1;                // a vertex displaced more than this belongs to the moved joint

function parseArgs(a){ const o = {}; for (let i = 0; i < a.length; i++){ const m = /^--([\w-]+)$/.exec(a[i]); if (!m) continue;
  if (m[1] === 'check') o.check = true; else o[m[1]] = a[++i]; } return o; }

// ---------- small vector / quaternion helpers (same conventions as SKRIG: quaternions are [x,y,z,w]) ----------
const qconj = q => [-q[0], -q[1], -q[2], q[3]];
function qmul(a, b){ const [ax, ay, az, aw] = a, [bx, by, bz, bw] = b;
  return [aw*bx + ax*bw + ay*bz - az*by, aw*by - ax*bz + ay*bw + az*bx, aw*bz + ax*by - ay*bx + az*bw, aw*bw - ax*bx - ay*by - az*bz]; }
function qrot(q, v){ const [x, y, z, w] = q;
  const ux = y*v[2] - z*v[1], uy = z*v[0] - x*v[2], uz = x*v[1] - y*v[0];
  const vx = y*uz - z*uy, vy = z*ux - x*uz, vz = x*uy - y*ux;
  return [v[0] + 2*(w*ux + vx), v[1] + 2*(w*uy + vy), v[2] + 2*(w*uz + vz)]; }
function qnorm(q){ const l = Math.hypot(q[0], q[1], q[2], q[3]) || 1; return q.map(v => v/l); }
function qmat3(q){ const [x, y, z, w] = q;        // rows of the rotation matrix
  return [[1 - 2*(y*y + z*z), 2*(x*y - w*z), 2*(x*z + w*y)], [2*(x*y + w*z), 1 - 2*(x*x + z*z), 2*(y*z - w*x)], [2*(x*z - w*y), 2*(y*z + w*x), 1 - 2*(x*x + y*y)]]; }
const sub = (a, b) => [a[0] - b[0], a[1] - b[1], a[2] - b[2]];
const cross = (a, b) => [a[1]*b[2] - a[2]*b[1], a[2]*b[0] - a[0]*b[2], a[0]*b[1] - a[1]*b[0]];
const dot = (a, b) => a[0]*b[0] + a[1]*b[1] + a[2]*b[2];
const vlen = a => Math.hypot(a[0], a[1], a[2]);
const srgbToLinear = c => { c /= 255; return c <= 0.04045 ? c/12.92 : Math.pow((c + 0.055)/1.055, 2.4); };

// ---------- read the page source for the few game-script tables that are not reachable from window ----------
function readPageTables(src){
  const ver = /var APP_VER = '([^']+)'/.exec(src);
  const nat = /var NATURAL = \{([\s\S]*?)\};/.exec(src);
  if (!nat) throw new Error('NATURAL not found in page source');
  const natural = nat[1].split('\n').map(l => l.replace(/\/\/.*$/, '')).join(' ').match(/\b([A-Za-z_]\w*)\s*:\s*1\b/g).map(s => s.split(':')[0].trim());
  let fly = {};
  const fk = /var FLY_K = (\{[\s\S]*?\});/.exec(src);     // { kit:{ alt, hz, legs? }, ... } over a few lines
  if (fk){ try { fly = new Function('return ' + fk[1])(); } catch (e){ fly = {}; } }
  return { appVer: ver ? ver[1] : '?', natural, fly };
}

// ---------- runs inside the page: build one kit standing still at full detail, then find which joint moves each face ----------
function pageExport(arg){
  var kit = arg.kit, opt = arg, R = window.SKRIG, M = window.MINI, K = M.kitInfo(kit), J = R.J.map(function(j){ return j[0]; }), i, j;
  function copyW(W){ var o = {}, n; for (n in W) o[n] = { p: W[n].p.slice(0, 3), q: W[n].q.slice(0, 4) }; return o; }   // a pose may carry a 4-vector root
  function copyF(fs){ return fs.map(function(f){ return { p: f.p.map(function(q){ return q.slice(); }), n: f.n ? f.n.slice() : null, k: String(f.k) }; }); }
  var P = R.idlePose(0); M.pose(kit, P); var Wd = copyW(R.fk(P));                // how the game builds a standing figure
  var base = copyF(M.build(kit, Wd, 1));
  var rider = K.mount ? copyW(R.fk(M.riderPose(kit))) : null;                   // a mount draws its rider from its own seated frames
  var frames = rider || Wd, owner = [], best = [], mism = [];
  for (i = 0; i < base.length; i++){ owner.push(-1); best.push(0); }
  for (j = 0; j < J.length; j++){
    var fs, F = copyW(frames); F[J[j]].p[1] += opt.shift;
    fs = rider ? M.build(kit, Wd, 1, { rider: F }) : M.build(kit, F, 1);
    if (fs.length !== base.length){ mism.push(J[j] + ':' + fs.length + '/' + base.length); continue; }
    for (i = 0; i < fs.length; i++){ var a = base[i].p, c = fs[i].p, d = 0, m;
      if (a.length !== c.length){ mism.push(J[j] + ':face' + i); break; }
      for (m = 0; m < a.length; m++){ var dd = Math.hypot(c[m][0] - a[m][0], c[m][1] - a[m][1], c[m][2] - a[m][2]); if (dd > d) d = dd; }
      if (d > opt.eps && d > best[i]){ best[i] = d; owner[i] = j; } }
  }
  var moved = 0; for (i = 0; i < owner.length; i++) if (owner[i] >= 0) moved++;
  var bk = kit.lastIndexOf('_') > 0 ? kit.slice(0, kit.lastIndexOf('_')) : null;     // a variant borrows its base kit's palette
  var palKey = M.SOLID[kit] ? kit : (bk && M.SOLID[bk]) ? bk : 'heavy';
  var T = null; for (i = 0; i < window.BT.TYPES.length; i++) if (window.BT.TYPES[i].k === kit) T = window.BT.TYPES[i];
  if (!T && bk) for (i = 0; i < window.BT.TYPES.length; i++) if (window.BT.TYPES[i].k === bk) T = window.BT.TYPES[i];
  return { faces: base, owner: owner, moved: moved, mism: mism, joints: J, parent: R.J.map(function(j){ return j[1]; }),
    frames: frames, riderFrames: !!rider, scale: K.scale || 1, kitScale: window.BT.kitInfo(kit).scale, h: K.h || 1.75,
    mount: K.mount || null, creature: !!K.creature, hold: K.hold || (K.mount && K.mount.hold) || null,
    palette: palKey, solid: M.SOLID[palKey], type: T ? { k: T.k, nm: T.nm, fac: T.fac, r: T.r || null, fly: !!T.fly } : null };
}

// ---------- geometry: polygon normal and triangulation ----------
function newell(p){ let n = [0, 0, 0]; for (let i = 0; i < p.length; i++){ const a = p[i], b = p[(i + 1) % p.length];
  n[0] += (a[1] - b[1])*(a[2] + b[2]); n[1] += (a[2] - b[2])*(a[0] + b[0]); n[2] += (a[0] - b[0])*(a[1] + b[1]); } return n; }
// ear clipping in the polygon's own plane; returns index triples with the polygon's winding. Falls back to a fan.
function triangulate(p, n){
  const m = p.length; if (m === 3) return [[0, 1, 2]];
  const ax = Math.abs(n[0]) > 0.5 ? [0, 1, 0] : [1, 0, 0], u = cross(ax, n), v = cross(n, u), lu = vlen(u) || 1, lv = vlen(v) || 1;
  const P = p.map(q => [dot(q, u)/lu, dot(q, v)/lv]);
  const area2 = (a, b, c) => (P[b][0] - P[a][0])*(P[c][1] - P[a][1]) - (P[c][0] - P[a][0])*(P[b][1] - P[a][1]);
  const inside = (a, b, c, x) => area2(a, b, x) >= 0 && area2(b, c, x) >= 0 && area2(c, a, x) >= 0;
  let idx = []; for (let i = 0; i < m; i++) idx.push(i);
  const out = []; let guard = 0;
  while (idx.length > 3 && guard++ < 4*m){
    let cut = false;
    for (let i = 0; i < idx.length; i++){ const a = idx[(i + idx.length - 1) % idx.length], b = idx[i], c = idx[(i + 1) % idx.length];
      if (area2(a, b, c) <= 1e-12) continue;
      let ok = true; for (const x of idx){ if (x === a || x === b || x === c) continue; if (inside(a, b, c, x)){ ok = false; break; } }
      if (!ok) continue;
      out.push([a, b, c]); idx.splice(i, 1); cut = true; break; }
    if (!cut) break;
  }
  if (idx.length === 3) out.push(idx.slice());
  else for (let i = 1; i + 1 < idx.length; i++) out.push([idx[0], idx[i], idx[i + 1]]);   // could not clip (self-touching): fan the rest
  return out;
}

// ---------- GLB writer ----------
function f32(arr){ const b = Buffer.alloc(arr.length*4); for (let i = 0; i < arr.length; i++) b.writeFloatLE(arr[i], i*4); return b; }
function pad4(b, fill){ const r = b.length % 4; return r ? Buffer.concat([b, Buffer.alloc(4 - r, fill)]) : b; }
function buildGlb(kit, data, tables){
  const S = data.scale, skinned = data.owner != null, J = data.joints, PAR = data.parent;
  // materials: one per palette key, in first-seen order; a key the palette lacks falls back on plate (as drawRig does)
  const matIndex = new Map(), materials = [], groups = [];
  for (const f of data.faces){ if (!matIndex.has(f.k)){ matIndex.set(f.k, materials.length);
    let rgb = data.solid[f.k] || data.solid.plate || [128, 128, 128]; rgb = rgb.slice(0, 3).map(Math.round);
    const tint = tables.natural.indexOf(f.k) < 0;
    materials.push({ name: f.k, doubleSided: false,
      pbrMetallicRoughness: { baseColorFactor: [srgbToLinear(rgb[0]), srgbToLinear(rgb[1]), srgbToLinear(rgb[2]), 1], metallicFactor: 0, roughnessFactor: 1 },
      extras: { key: f.k, tint, rgb, missing: !data.solid[f.k] || undefined } });
    groups.push({ pos: [], nrm: [], jnt: [], tris: 0 }); } }
  let nFlip = 0, degenerate = 0, triangles = 0, fallback = 0;
  const bb = [[Infinity, Infinity, Infinity], [-Infinity, -Infinity, -Infinity]];
  data.faces.forEach((f, fi) => {
    let n = newell(f.p), l = vlen(n);
    if (l < 1e-12){ degenerate++; return; }                    // no area: nothing to draw
    n = [n[0]/l, n[1]/l, n[2]/l];
    if (f.n && dot(n, f.n) < 0) nFlip++;                       // the winding decides (so does the page's renderer)
    const g = groups[matIndex.get(f.k)], joint = skinned ? (data.owner[fi] >= 0 ? data.owner[fi] : 0) : 0;
    if (skinned && data.owner[fi] < 0) fallback++;
    for (const t of triangulate(f.p, n)) for (const vi of t){ const q = f.p[vi];
      g.pos.push(q[0], q[1], q[2]); g.nrm.push(n[0], n[1], n[2]); g.jnt.push(joint);
      for (let a = 0; a < 3; a++){ if (q[a] < bb[0][a]) bb[0][a] = q[a]; if (q[a] > bb[1][a]) bb[1][a] = q[a]; } }
    triangles += Math.max(0, f.p.length - 2);
  });
  // buffer, bufferViews, accessors
  const bufs = [], views = [], accessors = []; let off = 0;
  function view(buf, target){ views.push({ buffer: 0, byteOffset: off, byteLength: buf.length, target }); bufs.push(buf); off += buf.length; return views.length - 1; }
  function accessor(bv, componentType, count, type, extra){ accessors.push(Object.assign({ bufferView: bv, componentType, count, type }, extra || {})); return accessors.length - 1; }
  const primitives = [];
  groups.forEach((g, gi) => { const n = g.pos.length/3; if (!n) return;
    const mn = [Infinity, Infinity, Infinity], mx = [-Infinity, -Infinity, -Infinity];
    for (let i = 0; i < g.pos.length; i++){ const a = i % 3; if (g.pos[i] < mn[a]) mn[a] = g.pos[i]; if (g.pos[i] > mx[a]) mx[a] = g.pos[i]; }
    const attributes = { POSITION: accessor(view(f32(g.pos), 34962), 5126, n, 'VEC3', { min: mn, max: mx }),
                         NORMAL: accessor(view(f32(g.nrm), 34962), 5126, n, 'VEC3') };
    if (skinned){ const jb = Buffer.alloc(n*4); for (let i = 0; i < n; i++) jb[i*4] = g.jnt[i];
      attributes.JOINTS_0 = accessor(view(jb, 34962), 5121, n, 'VEC4');
      const wb = new Array(n*4).fill(0); for (let i = 0; i < n; i++) wb[i*4] = 1;
      attributes.WEIGHTS_0 = accessor(view(f32(wb), 34962), 5126, n, 'VEC4'); }
    primitives.push({ attributes, material: gi, mode: 4 }); });
  // nodes: root, then (if skinned) the joint hierarchy and the skin
  const nodes = [{ name: kit, children: [] }], scenes = [{ nodes: [0] }], skins = [];
  const meshNode = { name: kit + '_mesh', mesh: 0 };
  if (skinned){
    const world = {}, nodeOf = {}, ibm = [];
    J.forEach((jn, ji) => { const W = data.frames[jn], ps = W.p.map(v => v*S), q = qnorm(W.q); world[jn] = { p: ps, q };
      const par = PAR[ji], node = { name: jn, children: [] };
      if (par == null){ node.translation = ps; node.rotation = q; }
      else { const Pw = world[par]; node.translation = qrot(qconj(Pw.q), sub(ps, Pw.p)); node.rotation = qnorm(qmul(qconj(Pw.q), q)); }
      nodeOf[jn] = nodes.length; nodes.push(node);
      if (par == null) nodes[0].children.push(nodeOf[jn]); else nodes[nodeOf[par]].children.push(nodeOf[jn]);
      const Rt = qmat3(q);                                                     // inverse bind = R^T · T(-p), column-major
      const tx = -(Rt[0][0]*ps[0] + Rt[1][0]*ps[1] + Rt[2][0]*ps[2]), ty = -(Rt[0][1]*ps[0] + Rt[1][1]*ps[1] + Rt[2][1]*ps[2]), tz = -(Rt[0][2]*ps[0] + Rt[1][2]*ps[1] + Rt[2][2]*ps[2]);
      ibm.push(Rt[0][0], Rt[0][1], Rt[0][2], 0, Rt[1][0], Rt[1][1], Rt[1][2], 0, Rt[2][0], Rt[2][1], Rt[2][2], 0, tx, ty, tz, 1); });
    for (const nd of nodes) if (nd.children && !nd.children.length) delete nd.children;
    skins.push({ name: kit + '_skin', inverseBindMatrices: accessor(view(f32(ibm)), 5126, J.length, 'MAT4'), joints: J.map(jn => nodeOf[jn]), skeleton: nodeOf[J[0]] });
    meshNode.skin = 0;
  }
  nodes[0].children.push(nodes.length); nodes.push(meshNode);
  const bin = Buffer.concat(bufs);
  const json = { asset: { version: '2.0', generator: 'candlelight-table godot/tools/export_kits.js',
      extras: { kit, source: 'battle-table.html APP_VER ' + tables.appVer, units: 'metres', up: '+Y', front: '+Z', left: '+X', baseColorFactor: 'linear (sRGB rgb in material extras)' } },
    scene: 0, scenes, nodes, meshes: [{ name: kit, primitives }], materials, accessors, bufferViews: views, buffers: [{ byteLength: bin.length }] };
  if (skins.length) json.skins = skins;
  const jsonBuf = pad4(Buffer.from(JSON.stringify(json), 'utf8'), 0x20), binBuf = pad4(bin, 0);
  const head = Buffer.alloc(12); head.write('glTF', 0, 'ascii'); head.writeUInt32LE(2, 4); head.writeUInt32LE(12 + 8 + jsonBuf.length + 8 + binBuf.length, 8);
  const h1 = Buffer.alloc(8); h1.writeUInt32LE(jsonBuf.length, 0); h1.writeUInt32LE(0x4E4F534A, 4);
  const h2 = Buffer.alloc(8); h2.writeUInt32LE(binBuf.length, 0); h2.writeUInt32LE(0x004E4942, 4);
  return { glb: Buffer.concat([head, h1, jsonBuf, h2, binBuf]), triangles, degenerate, nFlip, fallback, bbox: bb,
    materials: materials.map(m => ({ key: m.extras.key, rgb: m.extras.rgb, tint: m.extras.tint })) };
}

// ---------- structural check of a written .glb (independent re-read) ----------
function checkGlb(file){
  const b = fs.readFileSync(file), errs = [];
  if (b.toString('ascii', 0, 4) !== 'glTF' || b.readUInt32LE(4) !== 2) errs.push('bad magic/version');
  if (b.readUInt32LE(8) !== b.length) errs.push('length field ' + b.readUInt32LE(8) + ' != file ' + b.length);
  const jl = b.readUInt32LE(12); if (b.readUInt32LE(16) !== 0x4E4F534A || jl % 4) errs.push('bad JSON chunk');
  const bo = 20 + jl + 8, bl = b.readUInt32LE(20 + jl); if (b.readUInt32LE(24 + jl) !== 0x004E4942 || bl % 4 || bo + bl !== b.length) errs.push('bad BIN chunk');
  let g; try { g = JSON.parse(b.toString('utf8', 20, 20 + jl)); } catch (e){ return { ok: false, errs: ['JSON: ' + e.message] }; }
  if (g.buffers[0].byteLength > bl) errs.push('buffer longer than BIN chunk');
  const SZ = { SCALAR: 1, VEC3: 3, VEC4: 4, MAT4: 16 }, CS = { 5121: 1, 5123: 2, 5126: 4 };
  g.accessors.forEach((a, i) => { const bv = g.bufferViews[a.bufferView], need = a.count*SZ[a.type]*CS[a.componentType];
    if (!bv || bv.byteOffset + bv.byteLength > g.buffers[0].byteLength) errs.push('accessor ' + i + ': view out of buffer');
    else if (need > bv.byteLength) errs.push('accessor ' + i + ': ' + need + ' > view ' + bv.byteLength);
    if (bv && bv.byteOffset % 4) errs.push('accessor ' + i + ': view not 4-aligned'); });
  g.nodes.forEach((n, i) => { if ((n.translation && (n.translation.length !== 3 || !n.translation.every(Number.isFinite))) ||
    (n.rotation && (n.rotation.length !== 4 || !n.rotation.every(Number.isFinite)))) errs.push('node ' + i + ' (' + n.name + '): bad translation/rotation'); });
  const nJ = g.skins ? g.skins[0].joints.length : 0;
  let verts = 0;
  for (const pr of g.meshes[0].primitives){
    const pa = g.accessors[pr.attributes.POSITION], bv = g.bufferViews[pa.bufferView], mn = [Infinity, Infinity, Infinity], mx = [-Infinity, -Infinity, -Infinity];
    if (pa.count % 3) errs.push('primitive vertex count not a multiple of 3');
    verts += pa.count;
    for (let i = 0; i < pa.count*3; i++){ const v = b.readFloatLE(bo + bv.byteOffset + i*4), a = i % 3; if (!isFinite(v)) errs.push('NaN position'); if (v < mn[a]) mn[a] = v; if (v > mx[a]) mx[a] = v; }
    for (let a = 0; a < 3; a++) if (Math.abs(mn[a] - pa.min[a]) > 1e-6 || Math.abs(mx[a] - pa.max[a]) > 1e-6) errs.push('POSITION min/max mismatch');
    if (g.accessors[pr.attributes.NORMAL].count !== pa.count) errs.push('NORMAL count');
    if (pr.material == null || !g.materials[pr.material]) errs.push('material missing');
    if (nJ){ const ja = g.accessors[pr.attributes.JOINTS_0], wa = g.accessors[pr.attributes.WEIGHTS_0];
      if (!ja || !wa || ja.count !== pa.count || wa.count !== pa.count) errs.push('JOINTS_0/WEIGHTS_0 count');
      else { const jv = g.bufferViews[ja.bufferView], wv = g.bufferViews[wa.bufferView];
        for (let i = 0; i < ja.count; i++){ if (b[bo + jv.byteOffset + i*4] >= nJ) errs.push('joint index out of range');
          let s = 0; for (let k = 0; k < 4; k++) s += b.readFloatLE(bo + wv.byteOffset + i*16 + k*4); if (Math.abs(s - 1) > 1e-6) errs.push('weights do not sum to 1'); } } }
    else if (pr.attributes.JOINTS_0 != null) errs.push('JOINTS_0 without skin');
  }
  if (nJ){ const sk = g.skins[0], ia = g.accessors[sk.inverseBindMatrices];
    if (ia.count !== nJ || ia.type !== 'MAT4') errs.push('inverseBindMatrices count/type');
    // the node hierarchy must rebuild each joint's world frame, and its inverse bind matrix must undo it
    const world = {}, iv = g.bufferViews[ia.bufferView];
    const visit = (ni, Pp, Pq) => { const nd = g.nodes[ni], q = nd.rotation || [0, 0, 0, 1], t = nd.translation || [0, 0, 0];
      const wq = Pq ? qmul(Pq, q) : q, rt = Pq ? qrot(Pq, t) : t, wp = Pp ? [Pp[0] + rt[0], Pp[1] + rt[1], Pp[2] + rt[2]] : t; world[ni] = { p: wp, q: wq };
      for (const c of nd.children || []) visit(c, wp, wq); };
    visit(sk.skeleton, null, null);
    sk.joints.forEach((ni, ji) => { const W = world[ni]; if (!W){ errs.push('joint ' + ji + ' not under skeleton root'); return; }
      const m = []; for (let k = 0; k < 16; k++) m.push(b.readFloatLE(bo + iv.byteOffset + ji*64 + k*4));
      const p = W.p, r = [m[0]*p[0] + m[4]*p[1] + m[8]*p[2] + m[12], m[1]*p[0] + m[5]*p[1] + m[9]*p[2] + m[13], m[2]*p[0] + m[6]*p[1] + m[10]*p[2] + m[14]];
      if (Math.hypot(r[0], r[1], r[2]) > 1e-4) errs.push('inverse bind matrix of joint ' + ji + ' does not map its origin to 0'); });
  }
  const uniq = Array.from(new Set(errs));
  return { ok: !uniq.length, errs: uniq, verts, bytes: b.length, skinned: !!nJ };
}

// ---------- main ----------
async function main(){
  fs.mkdirSync(OUT, { recursive: true });
  if (ARGS.check){ let bad = 0; for (const f of fs.readdirSync(OUT).filter(f => f.endsWith('.glb')).sort()){ const r = checkGlb(path.join(OUT, f));
      if (!r.ok){ bad++; console.log('FAIL', f, r.errs.join('; ')); } }
    console.log(bad ? bad + ' bad files' : 'all .glb files pass the structural check'); process.exit(bad ? 1 : 0); }
  const src = fs.readFileSync(PAGE, 'utf8'), tables = readPageTables(src);
  const { chromium } = require(path.join(ROOT, 'tests/node_modules/playwright'));
  const browser = await chromium.launch({ executablePath: process.env.CHROMIUM_PATH || undefined, args: ['--no-sandbox'] });
  const page = await browser.newPage({ viewport: { width: 800, height: 600 } });
  page.on('pageerror', e => console.error('page error:', e.message));
  await page.goto('file://' + PAGE);
  await page.waitForFunction(() => window.BT && window.BT.G && window.MINI && window.SKRIG, null, { timeout: 120000 });
  let kits = await page.evaluate(() => Object.keys(window.MINI.KITS));
  const SPEEDS = await page.evaluate(() => [window.SKRIG.V_WALK, window.SKRIG.V_RUN]);
  if (ARGS.only) kits = ARGS.only.split(',').filter(k => kits.indexOf(k) >= 0);
  const manifest = { exported: 0, failed: 0, skinned: 0, unskinned: 0, bytes: 0, faces: 0, triangles: 0,
    units: 'metres', up: '+Y', front: '+Z', left: '+X', source: 'battle-table.html APP_VER ' + tables.appVer,
    note: 'Geometry as the page builds it at full detail (LOD 1), standing still (SKRIG.idlePose(0) + MINI.pose); flat shading: every vertex carries its face normal. ' +
      'Joint names and order are SKRIG.J; a joint node\'s local rotation is the SKRIG local quaternion [x,y,z,w] of that pose, so any SKRIG pose can drive the bones. ' +
      'h is the kit\'s standing height the game uses (unitH: kit h or 1.75) before scale; bbox is the measured extent of the exported mesh. Materials: one per palette key; baseColorFactor is linear, extras.rgb is the sRGB 0-255 colour from MINI.SOLID; extras.tint says the game dyes it with the team colour.',
    natural: tables.natural, kits: {} };
  const t0 = Date.now();
  for (const kit of kits){
    let data; const entry = { file: kit + '.glb' };
    try {
      data = await page.evaluate(pageExport, { kit, shift: JOINT_SHIFT, eps: MOVE_EPS });
      if (data.mism.length){ entry.skinNote = 'face count changed when moving ' + data.mism.join(', ') + ': exported without skin'; data.owner = null; }
      else if (!data.moved){ entry.skinNote = 'no face follows the humanoid joints: exported without skin'; data.owner = null; }
      else if (data.riderFrames) entry.skinNote = 'skeleton is the rider\'s seated frames (MINI.riderPose); the mount\'s own body is bound to the pelvis';
      if (data.owner && data.mount){                      // the mount's moving parts: a bone each (mount_rig.js)
        const cand = []; data.owner.forEach((o, i) => { if (o < 0) cand.push(i); });
        const smp = MR.unpackSamples(await page.evaluate(MR.pageSampleMount, { kit, speeds: SPEEDS, n: 40, step: 0.125, faces: cand }));
        const rig = MR.buildRig(smp, { candidates: cand });
        // bones only where the bake can re-solve the legs (hooves stay put); else the body stays on the pelvis as before
        if (rig.gait && rig.bones.length){
          rig.bones.forEach((b, bi) => { data.joints.push(b.name); data.parent.push(b.parent); data.frames[b.name] = { p: b.origin.map(v => v/data.scale), q: [0, 0, 0, 1] };
            for (const f of b.faces) data.owner[f] = 23 + bi; });
          entry.skinNote = (entry.skinNote || '') + '; its ' + rig.bones.length + ' moving parts (legs, tail, head) have bones of their own after the 23 (mountRig)';
        } else { rig.bones = []; rig.legs = []; }
        entry.mountRig = rig;
      }
      const g = buildGlb(kit, data, tables), file = path.join(OUT, kit + '.glb');
      fs.writeFileSync(file, g.glb);
      const chk = checkGlb(file);
      Object.assign(entry, { faces: data.faces.length, triangles: g.triangles, bytes: g.glb.length, h: data.h, scale: data.scale, kitScale: data.kitScale,
        baseR: data.type ? (!data.type.r || data.type.r <= 0.8 ? 0.62 : Math.round(data.type.r*17.27)/20) : null,
        mount: data.mount, creature: data.creature, hold: data.hold, skinned: data.owner != null, joints: data.owner != null ? data.joints.length : 0,
        materials: g.materials, bbox: g.bbox.map(v => v.map(x => +x.toFixed(4))) });
      if (data.palette !== kit) entry.palette = data.palette;
      if (data.type) entry.type = data.type;
      if (tables.fly[kit]) entry.fly = tables.fly[kit];
      if (g.fallback) entry.pelvisFallback = g.fallback;
      if (g.degenerate) entry.degenerate = g.degenerate;
      if (g.nFlip) entry.normalFlipped = g.nFlip;
      if (!chk.ok) entry.check = chk.errs;
      manifest.exported++; manifest.bytes += g.glb.length; manifest.faces += data.faces.length; manifest.triangles += g.triangles;
      if (entry.skinned) manifest.skinned++; else manifest.unskinned++;
    } catch (e){ if (process.env.EXPORT_DEBUG) console.error(e); entry.error = String(e && e.message || e).split('\n')[0]; manifest.failed++; console.error('FAIL', kit, entry.error); }
    manifest.kits[kit] = entry;
  }
  await browser.close();
  fs.writeFileSync(path.join(OUT, 'kits.json'), JSON.stringify(manifest, null, 1));
  const bad = Object.values(manifest.kits).filter(e => e.check).length;
  console.log('exported ' + manifest.exported + ' kits (' + manifest.skinned + ' skinned, ' + manifest.unskinned + ' unskinned), failed ' + manifest.failed +
    ', ' + manifest.triangles + ' triangles, ' + (manifest.bytes/1048576).toFixed(1) + ' MB, ' + ((Date.now() - t0)/1000).toFixed(0) + ' s' + (bad ? ', ' + bad + ' FAILED the structural check' : ''));
  console.log('written to ' + OUT);
  if (manifest.failed || bad) process.exit(1);
}
main().catch(e => { console.error(e); process.exit(1); });
