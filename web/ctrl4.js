// ==== v4 controller: ONE travel speed (a scalar with acceleration limits), gait derived from speed, feet ground-tracked ====
// Nothing ever crossfades two independent walking loops. The stance foot is pinned to a ground point; the swing foot flies
// to the landing point of the *current* speed; the body (pelvis, spine, arms) reads its phase from the right foot.
// Idle / attack only blend the UPPER body and the root; feet get there by explicit steps. A step, once started, always lands.
var V_WALK = WALK.S/WALK.T, V_RUN = RUN.S/RUN.T;
var ACC = 6.0, DEC = 7.0, JERK = 70;               // m/s^2, m/s^3 — run reaches full speed in ~0.55 s, stops from run in ~0.5 s, no step in acceleration
var STEP_T = 0.22, SETTLE_TOL = 0.05, FLIGHT_B = 0.5, REACH_MAX = 0.9993;
var IDLE_FT = { L:{ a:[0.11,B.ankH,0.03], yaw:8 }, R:{ a:[-0.11,B.ankH,-0.02], yaw:-10 } };
var ATK_FT  = { L:{ a:sub([FRONT_X,0,AK.ready.fBz], qrot(footQ(FRONT_YAW,0),FOOT_BALL)), yaw:FRONT_YAW }, R:{ a:BACK_ANK.slice(), yaw:BACK_YAW } };
var UPPER = ['pelvis','spine','chest','neck','shoulderL','elbowL','wristL','shoulderR','elbowR','wristR'];
var FADE = 0.3;   // kept for the export

function footLow(a,q){ return a[1] + Math.min(qrot(q,FOOT_HEEL)[1], qrot(q,FOOT_BALL)[1]); }
function h3(p0,m0,p1,m1,s){ var s2=s*s, s3=s2*s; return (2*s3-3*s2+1)*p0 + (s3-2*s2+s)*m0 + (-2*s3+3*s2)*p1 + (s3-s2)*m1; }
function bumpC(s){ return 28.94*s*s*(1-s)*(1-s)*(1-s); }   // zero slope both ends, peak 1 at s=0.4

// Blended walk/run numbers for a travel speed. Above walking speed the two tables mix; below it the cadence slows
// (frequency ~ sqrt(speed)) and the stride shrinks with it, so a slow stroll takes short slow steps, not tiny fast ones.
function gaitParams(v){
  var b = clamp((v - V_WALK)/(V_RUN - V_WALK), 0, 1), G = {};
  for (var k in WALK) G[k] = lerp(WALK[k], RUN[k], b);
  if (v < V_WALK){ var f = (1/WALK.T) * Math.sqrt(Math.max(v, 0.03)/V_WALK); G.T = 1/f; }
  G.S = Math.max(v, 0.03) * G.T;
  G.b = b; G.g = v < V_WALK ? sstep(v/V_WALK) : 1;   // g = how much the body moves like a walker
  return G;
}
// Upper body of the gait at phase ph (right foot phase, 0 = right heel strike). g scales every sway to nothing at speed 0.
function gaitBody(G, ph, p){
  var w = TAU*ph, g = G.g, yaw = G.yaw*Math.cos(w)*g, tilt = -G.tilt*Math.sin(w-TAU*G.swayPh)*g;
  p.root = [ -G.sway*Math.sin(w-TAU*G.swayPh)*g, lerp(STAND_H-0.012, G.h - G.bob*Math.cos(2*(w-TAU*G.bobPh)), g), 0 ];
  p.q.pelvis = eul(G.lean*g, yaw, tilt);
  p.q.spine  = eul(G.spLean*g, -yaw*G.spYaw, -tilt*0.6);
  p.q.chest  = eul(G.chLean*g, -yaw*G.chYaw, -tilt*0.3);
  var aw = w - TAU*G.armLag;
  [['R',-Math.cos(aw),-1],['L',Math.cos(aw),1]].forEach(function(A){
    var f=A[1], s=A[2], armC = lerp(3, G.armC, g), armA = G.armA*g, elb = lerp(13, G.elb, g), elbA = G.elbA*g;
    p.q['shoulder'+A[0]] = eul(-(armC+armA*f), s*-6*g + s*-10*(1-g), s*lerp(6, G.abd, g));
    p.q['elbow'+A[0]] = eul(-(elb + elbA*(f+1)/2), 0, 0);
    p.q['wrist'+A[0]] = eul(lerp(-8,-6,g), 0, s*-4*(1-g));
  });
  stabilizeHead(p, G.headPitch*g + 1*(1-g), 0, 0.85);
}
function blendUpper(a, b, w, out){ UPPER.forEach(function(n){ out.q[n] = w<=0 ? (a.q[n]||QI) : w>=1 ? (b.q[n]||QI) : qslerp(a.q[n]||QI, b.q[n]||QI, w); }); }

// ---- one foot ----
// st: 'plant' (ground pinned) | 'swing' (gait flight to a landing point) | 'step' (scripted move to a body-relative spot) | 'ext' (pose supplies it)
function Foot(side){ this.S = side; this.s = side==='L'?1:-1; this.st = 'plant'; this.gz = 0; this.gx = 0; this.yaw = 0; this.pitch = 0;
  this.gait = false; this.zRef = 0; this.a = IDLE_FT[side].a.slice(); this.q = footQ(IDLE_FT[side].yaw, 0); this.c = 'flat'; this.u = 0; this.sw = 0; }
Foot.prototype.plantHere = function(travel, gait, zRef, G){   // pin the foot where it is now (ankle a, orientation q)
  var heel = add(this.a, qrot(this.q, FOOT_HEEL)), e = qToEul(this.q);
  this.st = 'plant'; this.gz = heel[2] + travel; this.gx = heel[0]; this.gait = !!gait; this.zRef = zRef; this.u = 0; this.c = 'flat';
  this.G = G || WALK; this.dS = Math.max(this.G.d*this.G.S, 0.35);   // stance length fixed at plant time: u is then continuous whatever the taps
  this.yaw = e[1]; this.ph = gait ? 0 : -e[0]; this.kh = 1; this.kp = 1; this.pitch = this.ph;
  if (this.ph < 0){ var ball = add(this.a, qrot(this.q, FOOT_BALL)), hb = qrot(qy(this.yaw*D), [0,0,B.heel+B.ball]); this.gz = ball[2] - hb[2] + travel; this.gx = ball[0] - hb[0]; }   // heel raised: the ball is the pivot; heel = ball - yawed (heel->ball)
};
// dt, flat: while standing still the rockers relax to a flat foot (kp -> 0); a pitch inherited from a pose relaxes too (kh -> 0)
Foot.prototype.planted = function(Gv, travel, dt, flat){
  var G = this.G, heelZ = this.gz - travel, Lhb = B.heel+B.ball;
  var u = clamp((this.zRef - heelZ)/this.dS, 0, 1); this.u = u;
  this.kp += ((flat ? 0 : 1) - this.kp) * Math.min(1, dt/0.15); this.kh = Math.max(0, this.kh - dt/0.15);
  var yawq = qy(this.yaw*D), pf = 0, br = 'flat';
  if (this.gait && u < G.ur1){ var r = 1-u/G.ur1; pf = G.th*r*r; br = 'heel'; }
  else if (u > G.ur2){ var w = (u-G.ur2)/(1-G.ur2); pf = -G.tt*w*w; br = 'ball'; }
  var p = pf*this.kp + this.ph*this.kh, q = qmul(yawq, qx(-p*D)), a;
  if (p > 1e-6){ a = sub([this.gx,0,heelZ], qrot(q,FOOT_HEEL)); this.c = 'heel'; }
  else if (p < -1e-6){ a = sub(add([this.gx,0,heelZ], qrot(yawq,[0,0,Lhb])), qrot(q,FOOT_BALL)); this.c = 'ball'; }
  else { q = yawq; a = sub([this.gx,0,heelZ], qrot(q,FOOT_HEEL)); this.c = 'flat'; }
  this.pitch = p; this.a = a; this.q = q;
};
Foot.prototype.toeOff = function(G, v, Tsw){
  this.st = 'swing'; this.sw = 0; this.T = Tsw; this.rate = 1; this.d = G.d; this.Gs = { lift:G.lift, th:G.th }; this.a0 = this.a.slice(); this.p0 = this.pitch; this.y0 = this.yaw; this.v0 = v; this.c = null;
};
Foot.prototype.swing = function(G, dt, v, travel, footX, zS){
  // targets follow the current gait with a short lag, so a tap mid-swing bends the flight path instead of jumping it
  var Gs = this.Gs, kf = Math.min(1, dt/0.2); if (Gs.zS === undefined){ Gs.zS = zS; Gs.footX = footX; }
  Gs.lift += (G.lift-Gs.lift)*kf; Gs.th += (G.th-Gs.th)*kf; Gs.zS += (zS-Gs.zS)*kf; Gs.footX += (footX-Gs.footX)*kf;
  this.sw = Math.min(1, this.sw + dt*this.rate/this.T); var s = this.sw, k = this.T/this.rate;
  var yaw = lerp(this.y0, 0, s), tq = footQ(0, Gs.th), a1 = sub([Gs.footX,0,Gs.zS], qrot(tq,FOOT_HEEL));
  var a = [ h3(this.a0[0],0,a1[0],0,s), h3(this.a0[1],0,a1[1],0,s) + Gs.lift*bumpC(s), h3(this.a0[2],-this.v0*k,a1[2],-v*k,s) ];
  var p = h3(this.p0,0,Gs.th,0,s);
  this.a = a; this.pitch = p; this.yaw = yaw; this.q = qmul(qy(yaw*D), qx(-p*D));
  if (s >= 1-1e-9){ this.a = a1; this.pitch = Gs.th; this.yaw = 0; this.q = tq; this.plantHere(travel, true, Gs.zS, G); this.pitch = Gs.th; }
  return this.st === 'plant';
};
Foot.prototype.stepTo = function(a1, yaw1, T, lift){ this.st = 'step'; this.sw = 0; this.T = T; this.a0 = this.a.slice(); this.a1 = a1.slice(); this.y0 = this.yaw; this.y1 = yaw1; this.lift = lift||0.045; this.c = null; };
Foot.prototype.stepping = function(dt, travel){
  this.sw = Math.min(1, this.sw + dt/this.T); var s = sstep(this.sw), u = this.sw;
  this.a = [ lerp(this.a0[0],this.a1[0],s), lerp(this.a0[1],this.a1[1],s) + this.lift*bump2(u), lerp(this.a0[2],this.a1[2],s) ];
  this.yaw = lerp(this.y0, this.y1, s); this.pitch = 0; this.q = qy(this.yaw*D);
  if (this.sw >= 1-1e-9){ this.a = this.a1.slice(); this.yaw = this.y1; this.q = qy(this.yaw*D); this.plantHere(travel, false, 0, WALK); }
  return this.sw >= 1;
};

// ---- controller ----
function Controller(){
  this.mode = 'walk'; this.cur = 'walk'; this.speed = V_WALK; this.travel = 0; this.travelX = 0; this.v = V_WALK;
  this.L = new Foot('L'); this.R = new Foot('R'); this.wi = 0; this.wa = 0; this.atk = null; this.tAtk = 0; this.settled = false; this.seq = null;
  this.idleT = 0; this.tree = null; this.pose = null; this.feet = {};
  // start mid-walk like the old demo: right foot just planted at its strike point, left foot at the phase-0.28 spot
  var fR = gaitFoot(WALK,0,'R'), fL = gaitFoot(WALK,0,'L'), self = this;
  [['R',fR],['L',fL]].forEach(function(x){ var F = self[x[0]], f = x[1]; F.a = f.a.slice(); F.q = footQ(0,f.p); F.pitch = f.p; F.yaw = 0; F.plantHere(0, true, WALK.zS, WALK); });
}
Controller.prototype.set = function(m){ if (MOTIONS[m]) this.mode = m; };
Controller.prototype.target = function(){ return this.mode==='walk' ? V_WALK : this.mode==='run' ? V_RUN : 0; };
// "out of leg": the foot trails the hip and the leg is at full stretch (a foot ahead of the hip can be at full stretch legitimately at heel strike)
Controller.prototype.overreach = function(F, root, pq){ var hip = add(root, qrot(pq,[F.s*B.hipX,B.hipY,0])); return F.a[2] < hip[2]-0.1 && len(sub(F.a,hip))/(B.thigh+B.shin) > REACH_MAX; };

Controller.prototype.step = function(dt){
  dt = clamp(dt, 0, 1/30);
  var m = this.mode, vT = this.target(), v = this.speed, stopping = vT === 0, self = this;
  // --- 1. speed: one scalar, accelerate / brake with limits, never overshoots ---
  var aT = this.atk ? 0 : v < vT - 1e-9 ? ACC : v > vT + 1e-9 ? -DEC : 0, a = this.acc||0;
  // near the target, the acceleration must already be tapering: cap |a| so v lands on vT without overshoot (a^2 <= 2*J*|vT-v|)
  var room = Math.sqrt(2*JERK*Math.abs(vT - v)); aT = clamp(aT, -room, room);
  a += clamp(aT - a, -JERK*dt, JERK*dt); if (vT === 0 && a > 0) a = 0; if (v <= 0 && a < 0) a = 0; this.acc = a;
  if (this.atk){ v = 0; this.acc = 0; } else { var v2 = v + a*dt; if ((v < vT && v2 > vT) || (v > vT && v2 < vT) || Math.abs(v2-vT) < 1e-4){ v2 = vT; this.acc = 0; } if (v2 < 0){ v2 = 0; this.acc = 0; } v = v2; }
  this.speed = v; this.travel += v*dt; this.v = v;
  this.vBody = (this.vBody===undefined ? v : this.vBody) + (v - (this.vBody===undefined ? v : this.vBody))*Math.min(1, dt/0.22);   // the upper body follows the speed with a short lag: walk<->run arm changes ease in
  var vRef = stopping ? v : Math.max(v, vT), G = gaitParams(vRef), Gv = gaitParams(this.vBody), P = newPose(), L = this.L, R = this.R;
  var braking = stopping && v > 0;

  // --- 2. feet ---
  if (this.atk){ this.atkFeet(P, dt); }
  else {
    var moving = v > 0 || !stopping;
    if (moving && this.settled){ this.settled = false; this.seq = null; var back = L.a[2] < R.a[2] ? L : R, fr = back===L ? R : L;
      back.toeOff(G, 0, (1-G.d)*G.T); fr.plantHere(this.travel, true, G.zS, G); }
    var Tsw = clamp((1-G.d)*G.T, 0.15, 0.45); if (braking) Tsw = Math.min(Tsw, 0.22);
    var kb = stopping ? clamp(v/V_WALK,0,1) : 1, zLand = lerp(0.0, G.zS, kb), footXL = lerp(0.11, G.footX, kb);
    [L,R].forEach(function(F){ var O = F===L ? R : L;
      if (F.st==='swing'){ if (braking){ var rT = Math.max(F.rate, (1-F.sw)*F.T/0.22); F.rate += (rT - F.rate)*Math.min(1, dt/0.08); }   // land within ~0.22 s when stopping; the speed-up itself ramps
        F.swing(G, dt, v, self.travel, F.s*footXL, zLand); }
      else if (F.st==='step'){ F.stepping(dt, self.travel); }
    });
    // planted feet: pin, then decide toe-off (never while stopping unless the leg runs out of reach)
    var body = newPose(); gaitBody(Gv, this.phaseR(Gv), body);
    [R,L].forEach(function(F){ var O = F===L ? R : L; if (F.st!=='plant') return;
      F.planted(Gv, self.travel, dt, stopping && v < 0.05);
      var over = self.overreach(F, body.root, body.q.pelvis||QI), want = F.u >= 1 || over;
      var allowed = (!stopping || over) && (O.st==='plant' || G.b >= FLIGHT_B || over) && v > 0;
      if (want && allowed) F.toeOff(G, v, Tsw);
    });
    // stopped: settle the feet onto the idle stance with explicit steps, one at a time
    if (v === 0 && stopping && !this.settled && L.st==='plant' && R.st==='plant') this.settle();
  }

  // --- 3. body: gait body (phase from the right foot) <-> idle <-> attack, upper body + root only ---
  var gb = newPose(); gaitBody(Gv, this.phaseR(Gv), gb);
  this.wi = clamp(this.wi + (this.settled && !this.atk && !this.seq && this.mode !== 'attack' ? dt/0.3 : -dt/0.25), 0, 1);
  this.idleT += dt; var ib = idlePose(this.idleT);
  var wi = sstep(this.wi);
  P.root = [lerp(gb.root[0], ib.root[0], wi), lerp(gb.root[1], ib.root[1], wi), lerp(gb.root[2], ib.root[2], wi)];
  blendUpper(gb, ib, wi, P); P.breath = ib.breath*wi;
  if (this.wa > 0 || this.atk){ var ap = this.atk ? this.atkPose : (this.seq === 'in' ? attackPose(0) : (this.atkHold || attackPose(0))), w = sstep(this.wa);
    P.root = [lerp(P.root[0],ap.root[0],w), lerp(P.root[1],ap.root[1],w), lerp(P.root[2],ap.root[2],w)];
    var tmp = newPose(); for (var n in P.q) tmp.q[n] = P.q[n]; blendUpper(tmp, ap, w, P); P.breath *= (1-w); P.phase = ap.phase; }
  P.sword = sstep(this.wa);
  var leanT = braking && !this.atk ? -4*D*clamp(v/V_WALK,0,1) : 0; this.lean = (this.lean||0) + clamp(leanT - (this.lean||0), -40*D*dt, 40*D*dt);
  if (this.lean) P.q.spine = qmul(qx(this.lean), P.q.spine||QI);
  // --- 4. legs from the tracked feet. A planted foot is never pulled by the IK clamp: the pelvis dips instead (knees bend) ---
  var pq = P.q.pelvis||QI, LEG = (B.thigh+B.shin)*0.995, dip = 0;
  [L,R].forEach(function(F){ var pl = F.st==='plant' || (F.st==='ext' && F.stx); if (!pl) return;
    var hip = add(P.root, qrot(pq,[F.s*B.hipX,B.hipY,0])), dh = Math.hypot(F.a[0]-hip[0], F.a[2]-hip[2]);
    var maxV = Math.sqrt(Math.max(0, LEG*LEG - dh*dh)), ex = (hip[1]-F.a[1]) - maxV; if (ex > dip) dip = ex; });
  var dp = this.dip||0; dp += (dip - dp)*Math.min(1, dt/0.12); if (dip > dp) dp = dip;   // needed dip applies at once, a released dip eases out
  if (dp > 0) P.root[1] -= dp;
  this.dip = dp;
  P.contact = {}; this.feet = {};
  [L,R].forEach(function(F){ var a = F.a.slice(), q = F.q, lw = footLow(a,q); if (lw < 0) a[1] -= lw;
    var pl = F.st==='plant' || (F.st==='ext' && F.stx);
    solveLeg(P, F.S, a, q, pl); P.contact[F.S] = pl ? (F.c||'flat') : null; self.feet[F.S] = { a:a, q:q, st:pl }; });
  P.v = v; this.cur = this.atk ? 'attack' : this.settled ? 'idle' : (G.b > 0.5 ? 'run' : 'walk');
  this.pose = P; this.travelX = 0;
  // --- 5. attack entry / exit sequencing ---
  this.atkSeq(dt);
  return P;
};
Controller.prototype.phaseR = function(G){ var F = this.R, ph = this.lastPh||0, d = G.d;   // d of the CURRENT speed: u and sw are continuous, so ph is
  if (F.st==='plant') ph = F.u*d; else if (F.st==='swing') ph = d + F.sw*(1-d);
  this.lastPh = ph; return ph; };
Controller.prototype.settle = function(){
  var L = this.L, R = this.R, self = this, need = [];
  [L,R].forEach(function(F){ var t = IDLE_FT[F.S]; if (Math.hypot(F.a[0]-t.a[0], F.a[2]-t.a[2]) > SETTLE_TOL) need.push(F); });
  if (!need.length){ this.settled = true; return; }
  need.sort(function(a,b){ var ta=IDLE_FT[a.S].a, tb=IDLE_FT[b.S].a; return Math.hypot(b.a[0]-tb[0],b.a[2]-tb[2]) - Math.hypot(a.a[0]-ta[0],a.a[2]-ta[2]); });
  var F = need[0], t = IDLE_FT[F.S]; F.stepTo(t.a, t.yaw, STEP_T, 0.04);
};
// attack: enter only from a settled stand (R steps back, L steps forward while the upper body blends); leave at a safe point
Controller.prototype.leaveAttack = function(){
  var L = this.L, R = this.R; this.atkHold = this.atkPose || attackPose(0); this.holdRun = !!this.atk; this.atk = null; this.seq = 'out'; this.settled = false;
  if (this.mode === 'idle' || this.mode === 'attack'){ L.plantHere(this.travel,false,0,WALK); R.plantHere(this.travel,false,0,WALK); this.stepQ = null; }   // settle() walks the feet home
  else { var Gt = gaitParams(this.target()); L.plantHere(this.travel,true,Gt.zS,Gt); R.plantHere(this.travel,false,0,Gt); R.toeOff(Gt, 0, 0.3); this.stepQ = null; }
};
// attack: enter only from a settled stand (R steps back, L steps forward while the upper body blends); leave at a safe point
Controller.prototype.atkSeq = function(dt){
  var L = this.L, R = this.R;
  if (this.atk){
    this.tAtk += dt; this.atkPose = attackPose(this.tAtk);
    var tt = frac(this.tAtk/ATK.T)*ATK.T, safe = tt < ATK.windup[0] || tt >= ATK.impact;
    if (this.mode !== 'attack' && safe){ L.a = this.atkPose.feet.L.a.slice(); L.q = this.atkPose.feet.L.q; R.a = this.atkPose.feet.R.a.slice(); R.q = this.atkPose.feet.R.q; this.leaveAttack(); }
    this.wa = clamp(this.wa + dt/0.3, 0, 1);
    return;
  }
  if (this.seq === 'in'){
    if (this.mode !== 'attack'){ this.leaveAttack(); return; }   // cancelled before the swing started: walk the feet back, no loop
    this.wa = clamp(this.wa + dt/0.44, 0, 1);
    if (L.st==='plant' && R.st==='plant'){ if (this.stepQ.length){ var F = this.stepQ.shift(), t = ATK_FT[F.S]; F.stepTo(t.a, t.yaw, 0.18, 0.045); }
      else if (this.wa >= 1){ this.seq = null; this.atk = 'loop'; this.tAtk = ATK.windup[0]; this.atkPose = attackPose(this.tAtk); } }
    return;
  }
  if (this.seq === 'out'){ if (this.holdRun){ this.tAtk += dt; this.atkHold = attackPose(this.tAtk); }   // the swing finishes its recovery while it fades out: no frozen arm
    this.wa = clamp(this.wa - dt/0.45, 0, 1); if (this.wa <= 0){ this.seq = null; this.tAtk = 0; } return; }
  this.wa = clamp(this.wa - dt/0.3, 0, 1);
  if (this.mode === 'attack' && this.settled && L.st==='plant' && R.st==='plant'){ this.seq = 'in'; this.stepQ = [R, L]; this.settled = false; }
};
Controller.prototype.atkFeet = function(P, dt){ var ap = this.atkPose || attackPose(this.tAtk), L = this.L, R = this.R;
  [L,R].forEach(function(F){ var f = ap.feet[F.S]; F.st = 'ext'; F.stx = !!f.st; F.a = f.a.slice(); F.q = f.q; F.c = f.c; }); };
