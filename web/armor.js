// ---------- armour: real geometry anchored to joint frames (never camera-facing cards) ----------
// Every piece is a small mesh built in a joint's local frame and carried by that joint's world rotation, so it stays
// glued to the body from any camera angle. Faces are depth-sorted with the bones (pass 1), back faces culled, flat-shaded
// from a fixed world light, drawn as a soft fill plus a rim/edge line in the page's line-art language.
var ARM_LIGHT = R.norm([-0.5, 0.8, 0.45]);
var ARM_KEYS = ['helm','chest','pauld','arms','legs','skirt','pack'];
var ARM_TH = { helm:'หมวก', chest:'เกราะอก', pauld:'บ่า', arms:'แขน', legs:'ขา', skirt:'กระโปรง', pack:'เป้หลัง' };
var FACES = [], FACE_POOL = [];
function armFace(pts, n, kind, rim){ var f = FACE_POOL[FACES.length] || (FACE_POOL[FACES.length] = { p:[], n:null, k:0, z:0 }); f.p = pts; f.n = n; f.k = kind; f.rim = rim || RIM_ALL; FACES.push(f); }
var RIM_ALL = [1,1,1,1], RIM_RING = [1,0,1,0], RIM_NONE = [0,0,0,0], RIM_BOT = [1,0,0,0], RIM_TOP = [0,0,1,0];
// local -> world for a joint frame
function fw(Wj, l){ return R.add(Wj.p, R.qrot(Wj.q, l)); }
function armQuad(Wj, a, b, c, d, kind, rim){   // local corners, counter-clockwise seen from outside
  var A = fw(Wj,a), Bq = fw(Wj,b), Cq = fw(Wj,c), Dq = fw(Wj,d);
  var n = R.norm(R.cross(R.sub(Bq,A), R.sub(Dq,A)));
  armFace([A,Bq,Cq,Dq], n, kind, rim);
}
// tube along local -Y or +Y between y0 and y1, elliptical radii (rx,rz) at each end, arc from a0..a1 (radians, full ring by default)
var LROT = null, LCEN = null;   // optional local rotation / centre applied to every primitive point (set by withRot)
function lp(p){ if (!LROT) return p; var q = R.qrot(LROT, p); return LCEN ? R.add(LCEN, q) : q; }
function withRot(rot, cen, fn){ var pr = LROT, pc = LCEN; LROT = rot; LCEN = cen || null; fn(); LROT = pr; LCEN = pc; }
function armTube(Wj, y0, r0x, r0z, y1, r1x, r1z, seg, a0, a1, kind, xoff){
  a0 = a0==null ? 0 : a0; a1 = a1==null ? Math.PI*2 : a1; xoff = xoff||0;
  var full = Math.abs(a1-a0-Math.PI*2) < 1e-6, n = seg, step = (a1-a0)/n;
  for (var i=0;i<n;i++){ var t0 = a0+i*step, t1 = a0+(i+1)*step, c0=Math.cos(t0), s0=Math.sin(t0), c1=Math.cos(t1), s1=Math.sin(t1);
    var p00=lp([xoff+r0x*s0, y0, r0z*c0]), p01=lp([xoff+r0x*s1, y0, r0z*c1]), p10=lp([xoff+r1x*s0, y1, r1z*c0]), p11=lp([xoff+r1x*s1, y1, r1z*c1]);
    if (y1 > y0) armQuad(Wj, p00, p01, p11, p10, kind, RIM_RING); else armQuad(Wj, p01, p00, p10, p11, kind, RIM_RING); }
}
// spherical cap: centre c (local), radius r, latitude from lat0..lat1 (deg, 90 = top), longitudes skipping [skip0,skip1] (deg, 0 = +Z front)
// lonA..lonB (deg, optional) limits the longitudes; thick (optional) adds a visible rim band of that thickness along the lower edge
function armDome(Wj, c, r, lat0, lat1, nLon, nLat, skipLon, kind, sy, lonA, lonB, thick){
  sy = sy||1; var LA = lonA==null ? -180 : lonA, LB = lonB==null ? 180 : lonB;
  var f = function(la, lo, rr){ lo *= D; rr = rr||r; return lp([c[0]+rr*Math.cos(la)*Math.sin(lo), c[1]+sy*rr*Math.sin(la), c[2]+rr*Math.cos(la)*Math.cos(lo)]); };
  for (var j=0;j<nLat;j++){ var la0 = (lat0 + (lat1-lat0)*j/nLat)*D, la1 = (lat0 + (lat1-lat0)*(j+1)/nLat)*D;
    for (var i=0;i<nLon;i++){ var lo0 = LA + (LB-LA)*i/nLon, lo1 = LA + (LB-LA)*(i+1)/nLon;
      if (skipLon && lo0 >= skipLon[0] && lo1 <= skipLon[1] && la1 < skipLon[2]*D) continue;
      armQuad(Wj, f(la0,lo0), f(la0,lo1), f(la1,lo1), f(la1,lo0), kind, j===0 ? RIM_BOT : RIM_NONE);
      if (thick && j===0) armQuad(Wj, f(la0,lo0), f(la0,lo0,r-thick), f(la0,lo1,r-thick), f(la0,lo1), kind, RIM_ALL);
      if (thick && LB-LA < 359 && i===0) armQuad(Wj, f(la0,lo0), f(la1,lo0), f(la1,lo0,r-thick), f(la0,lo0,r-thick), kind, RIM_ALL);
      if (thick && LB-LA < 359 && i===nLon-1) armQuad(Wj, f(la0,lo1,r-thick), f(la1,lo1,r-thick), f(la1,lo1), f(la0,lo1), kind, RIM_ALL); } }
}
function armBox(Wj, c, hx, hy, hz, kind){
  var x0=c[0]-hx, x1=c[0]+hx, y0=c[1]-hy, y1=c[1]+hy, z0=c[2]-hz, z1=c[2]+hz, P = function(x,y,z){ return lp([x,y,z]); };
  armQuad(Wj,P(x0,y0,z1),P(x1,y0,z1),P(x1,y1,z1),P(x0,y1,z1),kind); armQuad(Wj,P(x1,y0,z0),P(x0,y0,z0),P(x0,y1,z0),P(x1,y1,z0),kind);
  armQuad(Wj,P(x1,y0,z1),P(x1,y0,z0),P(x1,y1,z0),P(x1,y1,z1),kind); armQuad(Wj,P(x0,y0,z0),P(x0,y0,z1),P(x0,y1,z1),P(x0,y1,z0),kind);
  armQuad(Wj,P(x0,y1,z1),P(x1,y1,z1),P(x1,y1,z0),P(x0,y1,z0),kind); armQuad(Wj,P(x0,y0,z0),P(x1,y0,z0),P(x1,y0,z1),P(x0,y0,z1),kind);
}
// a quad given in the current local rotation
function armQuadL(Wj, a, b, c, d, kind, rim){ armQuad(Wj, lp(a), lp(b), lp(c), lp(d), kind, rim); }
var Bm = R.B, DEG = Math.PI/180, STL_K = 0.025;   // mm of the miniature -> metres on the rig
var MESH_VIS = [];
// a decimated STL part in a joint frame: faces filled + shaded, lines only on creases and on the silhouette (front/back boundary)
function armMesh(Wj, key, off, k, kind, rot){
  var Pm = STL_PARTS[key]; if (!Pm) return;
  var v = Pm.v, f = Pm.f, adj = Pm.adj, cr = Pm.cr, n = f.length/3, W = [], i;
  for (i=0;i<v.length;i+=3){ var l = [v[i]*k+off[0], v[i+1]*k+off[1], v[i+2]*k+off[2]]; if (rot) l = R.qrot(rot, l); W.push(fw(Wj, l)); }
  // first pass: projected corners, facing
  var PP = [], VIS = MESH_VIS; VIS.length = n;
  for (i=0;i<W.length;i++) PP.push(proj(W[i]));
  var first = FACES.length;
  for (i=0;i<n;i++){ var a = f[3*i], b = f[3*i+1], c = f[3*i+2], pa = PP[a], pb = PP[b], pc = PP[c];
    if (!pa||!pb||!pc){ VIS[i] = 0; continue; }
    var ar = (pb.x-pa.x)*(pc.y-pa.y) - (pc.x-pa.x)*(pb.y-pa.y); VIS[i] = ar < 0 ? 1 : 0; }
  for (i=0;i<n;i++){ if (!VIS[i]) continue; var a2 = f[3*i], b2 = f[3*i+1], c2 = f[3*i+2];
    var nn = R.norm(R.cross(R.sub(W[b2],W[a2]), R.sub(W[c2],W[a2])));
    var rim = [0,0,0]; for (var e=0;e<3;e++){ var nb = adj[3*i+e]; rim[e] = (cr[3*i+e] || nb < 0 || !VIS[nb]) ? 1 : 0; }
    var fc = FACE_POOL[FACES.length] || (FACE_POOL[FACES.length] = { p:[], n:null, k:0, z:0 });
    fc.p = [W[a2],W[b2],W[c2]]; fc.n = nn; fc.k = kind; fc.rim = rim; fc.pre = [PP[a2],PP[b2],PP[c2]]; FACES.push(fc); }
}
function buildArmor(Wd, on){
  FACES.length = 0;
  if (KIT === 'heavy') kitHeavy(Wd); else if (KIT === 'infantry') kitInfantry(Wd); else if (KIT === 'hoplite') kitHoplite(Wd);
  // project, cull, shade
  for (var k=0;k<FACES.length;k++){ var f = FACES[k], pp = [], z = 0, ok = true;
    if (f.pre){ pp = f.pre; f.pre = null; for (var m0=0;m0<pp.length;m0++) z += pp[m0].z; }
    else for (var m=0;m<f.p.length;m++){ var q = proj(f.p[m]); if (!q){ ok = false; break; } pp.push(q); z += q.z; }
    if (!ok){ f.z = -1; continue; }
    var ar = 0; for (var m2=0;m2<pp.length;m2++){ var p0 = pp[m2], p1 = pp[(m2+1)%pp.length]; ar += p0.x*p1.y - p1.x*p0.y; }
    if (ar >= 0){ f.z = -1; continue; }   // back face (screen y is down, so outward = negative area)
    f.pp = pp; f.z = z/pp.length; f.sh = 0.5 + 0.5*Math.max(0, R.dot(f.n, ARM_LIGHT));
    pushItem(3, k, f.z); }
}
var ARM_COL = {
  sketch:{ helm:[112,132,160], plate:[104,126,158], pauld:[92,116,150], limb:[118,136,164], pack:[96,108,130], visor:[40,48,70], trim:[150,140,110], boot:[80,86,100], cloth:[120,130,120], pouch:[100,108,96], edge:'42,58,85', edgeA:0.55, fillA:0.88 },
  game:  { helm:[236,233,224], plate:[236,233,224], pauld:[236,233,224], limb:[236,233,224], pack:[236,233,224], visor:[224,178,106], trim:[224,178,106], boot:[236,233,224], cloth:[236,233,224], pouch:[236,233,224], edge:'255,252,244', edgeA:0.85, fillA:0.14 }
};
// solid look (shaded plates): one palette per kit, used in both page styles
var SOLID = {
  heavy:    { helm:[92,112,150], plate:[88,110,150], pauld:[84,106,146], limb:[78,98,134], pack:[66,74,90], visor:[28,30,40], trim:[196,168,92], boot:[54,56,66], cloth:[90,100,120], pouch:[70,76,88] },
  infantry: { helm:[84,94,62], plate:[96,104,72], pauld:[96,104,72], limb:[92,100,70], pack:[76,82,58], visor:[30,30,30], trim:[112,120,86], boot:[56,50,44], cloth:[98,106,74], pouch:[76,82,58] },
  hoplite:  { helm:[184,134,66], plate:[214,204,182], pauld:[214,204,182], limb:[200,152,118], pack:[110,80,50], visor:[20,20,24], trim:[184,134,66], boot:[96,68,42], cloth:[158,40,40], pouch:[46,56,96], red:[160,36,36], flesh:[200,152,118], wood:[120,86,54], shield:[46,56,96] }
};
function drawArmorFace(k, pal){
  var f = FACES[k], pp = f.pp, C2 = ARM_COL[st.style], c = C2[f.k] || C2.plate, sh = f.sh;
  ctx.beginPath(); ctx.moveTo(pp[0].x,pp[0].y); for (var i=1;i<pp.length;i++) ctx.lineTo(pp[i].x,pp[i].y); ctx.closePath();
  if (st.solid){   // shaded plates: colour by kit, light from ARM_LIGHT, thin dark edges on the piece rims only
    var S = SOLID[KIT] || SOLID.heavy, sc = S[f.k] || S.plate, l = 0.42 + 0.62*sh, amb = pal.glow ? 0.9 : 1.0;
    ctx.fillStyle = 'rgb(' + Math.round(Math.min(255, sc[0]*l*amb)) + ',' + Math.round(Math.min(255, sc[1]*l*amb)) + ',' + Math.round(Math.min(255, sc[2]*l*amb)) + ')'; ctx.fill();
    armEdges(f, 'rgba(10,12,18,0.55)', 'rgba(10,12,18,0.0)', Math.max(0.8, 0.008*pp[0].s));
  } else if (pal.glow){   // in-game: opaque near-black plate with a faint lit wash (hides the bones inside), amber-white edges
    var w = 0.06 + 0.16*sh;
    ctx.fillStyle = 'rgb(' + Math.round(11+(c[0]-11)*w) + ',' + Math.round(11+(c[1]-11)*w) + ',' + Math.round(14+(c[2]-14)*w) + ')'; ctx.fill();
    armEdges(f, 'rgba(224,178,106,' + (0.35 + 0.45*sh).toFixed(3) + ')', 'rgba(224,178,106,0.10)', Math.max(1, 0.012*pp[0].s));
  } else {
    var l = 0.55 + 0.45*sh;
    ctx.fillStyle = 'rgba(' + Math.round(c[0]*l + 255*(1-l)*0.9) + ',' + Math.round(c[1]*l + 255*(1-l)*0.9) + ',' + Math.round(c[2]*l + 255*(1-l)*0.9) + ',' + C2.fillA + ')'; ctx.fill();
    armEdges(f, rgba(C2.edge, C2.edgeA), rgba(C2.edge, 0.10), Math.max(1, 0.010*pp[0].s));
  }
}
function armEdges(f, rimStyle, seamStyle, w){
  var pp = f.pp, rim = f.rim, n = pp.length;
  ctx.lineWidth = 0.8; ctx.strokeStyle = seamStyle; ctx.beginPath();
  for (var i=0;i<n;i++){ if (rim[i]) continue; ctx.moveTo(pp[i].x,pp[i].y); ctx.lineTo(pp[(i+1)%n].x,pp[(i+1)%n].y); } ctx.stroke();
  ctx.lineWidth = w; ctx.strokeStyle = rimStyle; ctx.beginPath();
  for (var j=0;j<n;j++){ if (!rim[j]) continue; ctx.moveTo(pp[j].x,pp[j].y); ctx.lineTo(pp[(j+1)%n].x,pp[(j+1)%n].y); } ctx.stroke();
}
