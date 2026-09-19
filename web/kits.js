// ---------- kits: whole figures built from primitives, anchored to joint frames ----------
// 'heavy'    = original heavy power-armour trooper   'infantry' = original line infantry   'hoplite' = bronze-age spearman
var KIT = 'heavy';
// per-kit arm overrides applied to the controller's pose before drawing (a hoplite carries the shield across the body, spear upright)
function kitPose(P){
  if (KIT !== 'hoplite') return;
  P.q.shoulderL = R.qslerp(P.q.shoulderL||R.QI, R.eul(-30, -90, 15), 0.92);   // upper arm turned in: the forearm crosses the chest
  P.q.elbowL = R.eul(-100, 0, 0); P.q.wristL = R.eul(0, 0, 0);
  P.q.shoulderR = R.qslerp(P.q.shoulderR||R.QI, R.eul(-12, 0, -8), 0.7); P.q.elbowR = R.qslerp(P.q.elbowR||R.QI, R.eul(-20,0,0), 0.7);
}
var Q = { qx:function(a){ return [Math.sin(a/2),0,0,Math.cos(a/2)]; }, qy:function(a){ return [0,Math.sin(a/2),0,Math.cos(a/2)]; }, qz:function(a){ return [0,0,Math.sin(a/2),Math.cos(a/2)]; } };

// withRot builds in a local frame; the primitives take the joint frame as the first argument, so wrap them:
var CUR_J = null;
function J(Wj, fn){ var p = CUR_J; CUR_J = Wj; fn(); CUR_J = p; }
var _armQuad = armQuad;
armQuad = function(Wj, a, b, c, d, kind, rim){ _armQuad(Wj || CUR_J, a, b, c, d, kind, rim); };


// A pauldron that reads as a plate, not a cap: a shell whose axis tilts outboard, so the rim rides high by the neck and
// hangs low over the upper arm; a visible edge thickness; an optional second plate (lame) hanging off the outboard side.
function pauldron(C, s, r, tilt, thick, lame, kind, trimKind, dx, dy){
  var c = [s*(Bm.shX+(dx==null?0.03:dx)), Bm.shY+(dy==null?0.02:dy), 0];
  var rot = R.qmul(Q.qz(-s*tilt*DEG), Q.qy(s*90*DEG));      // local +z -> outboard, local +y -> up tilted outboard
  J(C, function(){ withRot(rot, c, function(){
    armDome(null, [0,0,0], r, -14, 90, 12, 3, null, kind, 0.9, -125, 125, thick);   // open toward the neck
    if (lame) armDome(null, [0,-0.012,0], r*1.02, -48, -18, 8, 1, null, trimKind||kind, 0.9, -85, 85, thick*0.8);
  }); });
}
function kitHeavy(Wd){
  var hr = Bm.headR, H = Wd.head, C = Wd.chest, Sp = Wd.spine, Pv = Wd.pelvis;
  // ---- helmet: skull dome open at the face, an angular two-facet faceplate with a visor slot, chin block, side cheeks, collar
  J(H, function(){
    var r = hr*1.2, la = 22*DEG, lo = 48*DEG;
    armDome(H, [0,0.005,0], r, -30, 90, 12, 5, [-48,48,22], 'helm');
    var tl = [-r*Math.cos(la)*Math.sin(lo), 0.005+r*Math.sin(la), r*Math.cos(la)*Math.cos(lo)], tr = [-tl[0], tl[1], tl[2]], tc = [0, tl[1]+0.01, r*1.02];
    var ml = [-0.074, -0.012, 0.118], mr = [0.074, -0.012, 0.118], mc = [0, -0.02, 0.15];
    var bl = [-0.056, -0.095, 0.085], br = [0.056, -0.095, 0.085], bc = [0, -0.105, 0.105];
    armQuad(H, tl, tc, mc, ml, 'helm'); armQuad(H, tc, tr, mr, mc, 'helm');           // upper facets
    armQuad(H, ml, mc, bc, bl, 'helm'); armQuad(H, mc, mr, br, bc, 'helm');           // lower facets
    var sl = [-r*Math.cos(30*DEG)*Math.sin(lo), 0.005-r*Math.sin(30*DEG), r*Math.cos(30*DEG)*Math.cos(lo)], sr = [-sl[0], sl[1], sl[2]];
    armQuad(H, sl, bl, ml, tl, 'helm'); armQuad(H, tr, mr, br, sr, 'helm');           // cheeks close the sides
    armQuad(H, bl, bc, [0,-0.12,0.06], [-0.05,-0.115,0.045], 'helm'); armQuad(H, bc, br, [0.05,-0.115,0.045], [0,-0.12,0.06], 'helm');   // chin
    armBox(H, [0,0.018,0.128], 0.052, 0.006, 0.012, 'visor');                          // visor slot
    armBox(H, [0,hr*1.15,-0.01], 0.012, 0.025, 0.085, 'helm');                         // top ridge
  });
  armTube(C, 0.08, 0.075, 0.07, 0.12, 0.085, 0.078, 10, 0, Math.PI*2, 'trim');       // collar ring at the neck
  armTube(C, 0.0, 0.055, 0.05, 0.09, 0.055, 0.05, 8, 0, Math.PI*2, 'visor');          // neck seal (dark)
  // ---- torso
  armTube(Sp, 0.0, 0.17, 0.125, 0.16, 0.20, 0.14, 12, 0, Math.PI*2, 'plate');
  armTube(Sp, 0.16, 0.20, 0.14, 0.30, 0.24, 0.155, 12, 0, Math.PI*2, 'plate');
  armQuad(Sp, [0,0.12,0.155],[0.13,0.13,0.135],[0.115,0.29,0.15],[0,0.30,0.172], 'plate');
  armQuad(Sp, [-0.13,0.13,0.135],[0,0.12,0.155],[0,0.30,0.172],[-0.115,0.29,0.15], 'plate');
  armTube(Pv, 0.02, 0.155, 0.115, 0.15, 0.165, 0.12, 12, 0, Math.PI*2, 'plate');
  armBox(Pv, [0,0.02,0.0], 0.17, 0.02, 0.125, 'trim');
  armTube(Pv, 0.0, 0.12, 0.09, -0.14, 0.10, 0.075, 10, 0, Math.PI*2, 'limb');
  armDome(Pv, [0,-0.14,0], 0.10, -90, 0, 10, 2, null, 'limb', 0.75);
  // ---- shoulders: tilted plates with thickness and a lame
  pauldron(C, 1, 0.135, 25, 0.016, true, 'pauld', 'trim'); pauldron(C, -1, 0.135, 25, 0.016, true, 'pauld', 'trim');
  // ---- arms
  ['L','R'].forEach(function(S){
    armTube(Wd['shoulder'+S], -0.10, 0.068, 0.068, -0.26, 0.06, 0.06, 8, 0, Math.PI*2, 'limb');
    armTube(Wd['elbow'+S], -0.02, 0.058, 0.058, -0.20, 0.075, 0.07, 8, 0, Math.PI*2, 'limb');
    armDome(Wd['wrist'+S], [0,-0.06,0.01], 0.055, -90, 90, 8, 4, null, 'limb'); });
  // ---- legs
  ['L','R'].forEach(function(S){
    armTube(Wd['hip'+S], -0.05, 0.10, 0.095, -0.36, 0.085, 0.085, 8, 0, Math.PI*2, 'limb');
    armQuad(Wd['hip'+S], [-0.07,-0.08,0.10],[0.07,-0.08,0.10],[0.06,-0.32,0.09],[-0.06,-0.32,0.09], 'plate');
    armDome(Wd['knee'+S], [0,0,0.03], 0.075, -70, 70, 8, 3, null, 'plate', 1);
    armTube(Wd['knee'+S], -0.06, 0.085, 0.09, -0.37, 0.08, 0.082, 8, 0, Math.PI*2, 'limb');
    armBox(Wd['ankle'+S], [0,-0.04,0.045], 0.07, 0.05, 0.125, 'boot');
    armDome(Wd['ankle'+S], [0,-0.05,0.14], 0.065, -60, 60, 8, 2, null, 'boot', 0.8); });
  for (var i=0;i<6;i++){ var a0 = (i*60-24)*DEG, a1 = (i*60+24)*DEG; if (i===1||i===4) continue; armTube(Pv, -0.01, 0.17, 0.125, -0.19, 0.21, 0.16, 2, a0, a1, 'plate'); }
  // ---- power pack
  armBox(C, [0,0.07,-0.215], 0.135, 0.135, 0.075, 'pack');
  armTube(C, 0.20, 0.04, 0.04, 0.29, 0.036, 0.036, 8, 0, Math.PI*2, 'pack', -0.085); armTube(C, 0.20, 0.04, 0.04, 0.29, 0.036, 0.036, 8, 0, Math.PI*2, 'pack', 0.085);
  armBox(C, [0,-0.09,-0.20], 0.10, 0.03, 0.06, 'pack');
}

function kitInfantry(Wd){
  var hr = Bm.headR, H = Wd.head, C = Wd.chest, Sp = Wd.spine, Pv = Wd.pelvis;
  armDome(H, [0,0.01,0], hr*1.15, -12, 90, 12, 4, null, 'helm');
  armTube(H, -0.025, hr*1.22, hr*1.24, -0.005, hr*1.16, hr*1.16, 12, 0, Math.PI*2, 'trim');
  armTube(Sp, 0.02, 0.15, 0.115, 0.15, 0.165, 0.125, 10, 0, Math.PI*2, 'cloth');
  armTube(Sp, 0.15, 0.165, 0.125, 0.27, 0.18, 0.13, 10, 0, Math.PI*2, 'cloth');
  armBox(Sp, [-0.075,0.08,0.13], 0.035, 0.045, 0.028, 'pouch'); armBox(Sp, [0,0.075,0.135], 0.035, 0.045, 0.028, 'pouch'); armBox(Sp, [0.075,0.08,0.13], 0.035, 0.045, 0.028, 'pouch');
  armTube(Pv, 0.03, 0.14, 0.10, 0.14, 0.15, 0.108, 10, 0, Math.PI*2, 'cloth');
  armBox(Pv, [0,0.03,0.0], 0.15, 0.015, 0.108, 'trim');
  armTube(Pv, 0.01, 0.11, 0.085, -0.13, 0.095, 0.07, 10, 0, Math.PI*2, 'cloth');
  armDome(Pv, [0,-0.13,0], 0.095, -90, 0, 10, 2, null, 'cloth', 0.7);
  armTube(C, 0.0, 0.05, 0.045, 0.10, 0.045, 0.04, 8, 0, Math.PI*2, 'boot');
  pauldron(C, 1, 0.085, 25, 0.01, false, 'cloth', null, 0.01, 0.005); pauldron(C, -1, 0.085, 25, 0.01, false, 'cloth', null, 0.01, 0.005);
  ['L','R'].forEach(function(S){
    armTube(Wd['shoulder'+S], -0.09, 0.052, 0.052, -0.27, 0.046, 0.046, 8, 0, Math.PI*2, 'cloth');
    armTube(Wd['elbow'+S], -0.02, 0.046, 0.046, -0.215, 0.04, 0.04, 8, 0, Math.PI*2, 'cloth');
    armDome(Wd['wrist'+S], [0,-0.055,0.005], 0.042, -90, 90, 8, 3, null, 'boot'); });
  ['L','R'].forEach(function(S){
    armTube(Wd['hip'+S], -0.05, 0.08, 0.078, -0.37, 0.07, 0.07, 8, 0, Math.PI*2, 'cloth');
    armDome(Wd['knee'+S], [0,0,0.02], 0.058, -60, 60, 8, 2, null, 'pouch', 1);
    armTube(Wd['knee'+S], -0.05, 0.068, 0.07, -0.30, 0.062, 0.064, 8, 0, Math.PI*2, 'cloth');
    armTube(Wd['ankle'+S], 0.09, 0.062, 0.064, -0.045, 0.064, 0.066, 8, 0, Math.PI*2, 'boot');
    armBox(Wd['ankle'+S], [0,-0.045,0.045], 0.06, 0.03, 0.11, 'boot'); });
  armBox(C, [0,0.03,-0.19], 0.11, 0.12, 0.06, 'pouch');
  armRollX(C, [0,0.19,-0.19], 0.13, 0.045, 8, 'cloth');
}

function kitHoplite(Wd){
  var hr = Bm.headR, H = Wd.head, C = Wd.chest, Sp = Wd.spine, Pv = Wd.pelvis;
  // ---- helmet: bronze dome with cheek guards, a nasal bar, a tall horsehair crest front-to-back
  var r = hr*1.18;
  armDome(H, [0,0.01,0], r, -48, 90, 12, 5, [-40,40,4], 'helm');
  [-1,1].forEach(function(s){ armQuad(H, [s*0.078,0.0,0.086],[s*0.03,-0.005,0.112],[s*0.026,-0.105,0.09],[s*0.07,-0.09,0.055], 'helm'); });
  armBox(H, [0,-0.04,0.118], 0.011, 0.055, 0.008, 'helm');
  J(H, function(){ var n = 10, rb = r*1.02, x = 0.014, prev = null;
    for (var i=0;i<=n;i++){ var a = (55 - 205*i/n)*DEG, h = 0.045 + 0.10*Math.sin(Math.PI*i/n), d = [0, Math.cos(a), Math.sin(a)];
      var b0 = [ x, 0.01+rb*d[1], rb*d[2] ], t0 = [ x*0.6, 0.01+(rb+h)*d[1], (rb+h)*d[2] ], b1 = [-x, b0[1], b0[2]], t1 = [-x*0.6, t0[1], t0[2]];
      if (prev){ armQuad(H, prev.b0, b0, t0, prev.t0, 'red'); armQuad(H, b1, prev.b1, prev.t1, t1, 'red'); armQuad(H, prev.t0, t0, t1, prev.t1, 'red'); }
      prev = { b0:b0, t0:t0, b1:b1, t1:t1 }; } });
  // ---- cuirass: stiff linen torso, shoulder flaps, waist band; hanging strips (pteruges) over a red skirt
  armTube(Sp, 0.03, 0.15, 0.11, 0.17, 0.165, 0.12, 12, 0, Math.PI*2, 'plate');
  armTube(Sp, 0.17, 0.165, 0.12, 0.30, 0.185, 0.125, 12, 0, Math.PI*2, 'plate');
  [-1,1].forEach(function(s){ armQuad(C, [s*0.07,0.05,-0.11],[s*0.17,0.04,-0.07],[s*0.17,0.03,0.07],[s*0.07,0.05,0.12], 'plate'); });
  armBox(Pv, [0,0.03,0.0], 0.155, 0.018, 0.112, 'red');
  for (var i=0;i<10;i++){ var a0 = (i*36-14)*DEG, a1 = (i*36+14)*DEG; armTube(Pv, 0.015, 0.155, 0.115, -0.16, 0.175, 0.13, 1, a0, a1, 'plate'); }
  armTube(Pv, 0.0, 0.135, 0.1, -0.22, 0.15, 0.11, 12, 0, Math.PI*2, 'cloth');
  armTube(Pv, 0.0, 0.11, 0.085, -0.10, 0.10, 0.075, 10, 0, Math.PI*2, 'cloth');
  armTube(C, 0.0, 0.05, 0.045, 0.10, 0.045, 0.04, 8, 0, Math.PI*2, 'flesh');
  // ---- bare arms with bronze wrist bands
  ['L','R'].forEach(function(S){
    armTube(Wd['shoulder'+S], -0.03, 0.056, 0.056, -0.27, 0.046, 0.046, 8, 0, Math.PI*2, 'flesh');
    armTube(Wd['elbow'+S], -0.02, 0.046, 0.046, -0.15, 0.04, 0.04, 8, 0, Math.PI*2, 'flesh');
    armTube(Wd['elbow'+S], -0.15, 0.046, 0.046, -0.215, 0.046, 0.046, 8, 0, Math.PI*2, 'helm');
    armDome(Wd['wrist'+S], [0,-0.055,0.005], 0.04, -90, 90, 8, 3, null, 'flesh'); });
  // ---- bare thighs, bronze greaves, sandals
  ['L','R'].forEach(function(S){
    armTube(Wd['hip'+S], -0.04, 0.078, 0.076, -0.37, 0.066, 0.066, 8, 0, Math.PI*2, 'flesh');
    armDome(Wd['knee'+S], [0,0,0.015], 0.06, -60, 60, 8, 2, null, 'helm', 1);
    armTube(Wd['knee'+S], -0.05, 0.07, 0.074, -0.36, 0.06, 0.064, 8, 0, Math.PI*2, 'helm');
    armTube(Wd['ankle'+S], 0.0, 0.05, 0.05, -0.05, 0.048, 0.048, 8, 0, Math.PI*2, 'flesh');
    armBox(Wd['ankle'+S], [0,-0.062,0.045], 0.052, 0.01, 0.11, 'boot');
    armBox(Wd['ankle'+S], [0,-0.03,0.09], 0.05, 0.006, 0.01, 'boot'); armBox(Wd['ankle'+S], [0,-0.045,0.03], 0.05, 0.006, 0.01, 'boot'); });
  // ---- round shield on the left forearm: shallow bowl, bronze rim, central boss
  J(Wd.elbowL, function(){ var rot = Q.qz(-90*DEG), cen = [0.075,-0.14,0];   // disc normal = forearm's +x = forward once the arm is across the chest
    withRot(rot, cen, function(){
      armDome(null, [0,-1.56,0], 1.6, 77, 90, 16, 2, null, 'shield');
      armTube(null, 0.0, 0.365, 0.365, 0.03, 0.355, 0.355, 16, 0, Math.PI*2, 'trim');
      armDome(null, [0,0.03,0], 0.08, 0, 90, 8, 2, null, 'trim'); }); });
  // ---- spear in the right hand: ash shaft through the fist, bronze head
  J(Wd.wristR, function(){ armTube(Wd.wristR, -0.95, 0.014, 0.014, 1.25, 0.014, 0.014, 6, 0, Math.PI*2, 'wood');
    armTube(Wd.wristR, 1.25, 0.03, 0.02, 1.47, 0.002, 0.002, 6, 0, Math.PI*2, 'helm'); armTube(Wd.wristR, -0.95, 0.02, 0.02, -1.0, 0.006, 0.006, 6, 0, Math.PI*2, 'helm'); });
}
function armRollX(Wj, c, hx, r, seg, kind){
  for (var i=0;i<seg;i++){ var t0 = i/seg*Math.PI*2, t1 = (i+1)/seg*Math.PI*2;
    var y0 = c[1]+r*Math.cos(t0), z0 = c[2]+r*Math.sin(t0), y1 = c[1]+r*Math.cos(t1), z1 = c[2]+r*Math.sin(t1);
    armQuad(Wj, [c[0]-hx,y0,z0],[c[0]-hx,y1,z1],[c[0]+hx,y1,z1],[c[0]+hx,y0,z0], kind, RIM_RING); }
}
