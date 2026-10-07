#!/usr/bin/env node
// bake_anim.js — runs battle-table.html headlessly and samples the page's own rig, frame by frame, into animation
// clips for the new app: SKRIG.Controller (walk, run, starts and stops), SKRIG.idlePose (breathing idle), WALKER
// (turning on the spot), and the battle table's action poses through window.BT (shooting, bows, throws, melee blows,
// shields, flinches, falls). Every frame stores each of the 23 joints' LOCAL rotation (quaternion [x,y,z,w], the
// convention of the kits' Skeleton3D bones) and the pelvis translation, at 30 Hz. Nothing in the page is modified.
//
//   CHROMIUM_PATH=$(ls -d /opt/pw-browsers/chromium-*/chrome-linux*/chrome | head -1) node godot/tools/bake_anim.js
//   options: --out FILE (default godot/assets/anim/clips.json)  --page FILE  --proofs (only the three walk proofs)
//            --only name1,name2  --check [FILE] (validate an existing clips.json and exit)
//            --fidelity (also measure every skinned kit walking with its holds against the page's drawing, ~1 min)
//
// Then `godot --headless --path godot -s tools/bake_anim.gd` turns clips.json into assets/anim/humanoid.res.
// Units are the rig's: metres of an unscaled 1.6 m figure, +Y up, the figure faces +Z, its left is +X. A kit drawn at
// scale S plays the same clip with Skeleton3D.motion_scale = S and moves S times as fast (the page does the same).
'use strict';
const fs = require('fs'), path = require('path');
const ROOT = path.resolve(__dirname, '..', '..');
const ARGS = parseArgs(process.argv.slice(2));
const PAGE = path.resolve(ROOT, ARGS.page || 'app/src/main/assets/battle-table.html');
const OUT = path.resolve(ROOT, ARGS.out || 'godot/assets/anim/clips.json');
const KITS_JSON = path.resolve(ROOT, 'godot/assets/kits/kits.json');
const FPS = 30, SUB = 4;                 // 30 frames a second; the rig is stepped 4 times a frame (1/120 s)
const FORMAT = 1;

function parseArgs(a){ const o = {}; for (let i = 0; i < a.length; i++){ const m = /^--([\w-]+)$/.exec(a[i]); if (!m) continue;
  if (m[1] === 'proofs') o.proofs = true;
  else if (m[1] === 'fidelity') o.fidelity = true;
  else if (m[1] === 'check') o.check = (a[i + 1] && !a[i + 1].startsWith('--')) ? a[++i] : true;
  else o[m[1]] = a[++i]; } return o; }

// ---------- what to bake ----------
// Locomotion comes from SKRIG directly, on the bare rig. An action is the representative kit's own attack (the page
// picks it from that kit's ANIM entry), played from that kit's stance when its pose only carries the arms (a rifle at
// the low ready, a shield across the body), else from a bare rig (u.skn = NEUTRAL: MINI.pose leaves it alone). The
// joints an action leaves alone go back to the bare rig, so the library stays kit-neutral: a kit's own way of holding
// itself is the `holds` layer below. The gear the page turns by itself (a gun along the hands, a shield toward the blow)
// is fitted into the joints the kits bind it to (gearFix).
const NEUTRAL = '__neutral';
const ACTIONS = [
  // name, kit whose ANIM entry picks the action, melee, hits (shots or blows), variant per blow, notes
  { name: 'fire', kit: 'infantry', hits: 3, note: 'two-handed rifle: raise, three shots with recoil, lower' },
  { name: 'fire_heavy', kit: 'hmg', hits: 4, note: 'heavy gun fired from the hip, crouched against the kick' },
  { name: 'fire_sniper', kit: 'sniper', hits: 1, note: 'settles on the scope, one shot' },
  { name: 'fire_pistol_l', kit: 'cmdr', hits: 2, note: 'one-handed pistol in the left hand, arm straight at the target' },
  { name: 'bow', kit: 'archer', hits: 1, note: 'raise the bow, draw to the cheek, loose, lower' },
  { name: 'throw', kit: 'peltast', hits: 1, note: 'javelin: wind back over the shoulder, body twist, release' },
  { name: 'hurl', kit: 'herc', hits: 1, note: 'two hands lift a rock overhead and hurl it' },
  { name: 'lob', kit: 'mortar', hits: 2, note: 'tube held steep, two rounds lobbed' },
  { name: 'cast', kit: 'anubis', hits: 2, note: 'staff raised at the target, two bolts' },
  { name: 'zap', kit: 'thunder', hits: 1, note: 'hammer raised to the sky, lightning' },
  { name: 'flame', kit: 'flamer', hits: 3, note: 'flamer raised like a gun, a stream of fire' },
  { name: 'thrust_0', kit: 'hoplite', melee: true, hits: 1, vars: [0], note: 'spear thrust straight from the shoulder' },
  { name: 'thrust_1', kit: 'hoplite', melee: true, hits: 1, vars: [1], note: 'overarm spear stab' },
  { name: 'thrust_2', kit: 'hoplite', melee: true, hits: 1, vars: [2], note: 'rising spear thrust from low' },
  { name: 'swing_0', kit: 'levy', melee: true, hits: 1, vars: [0], note: 'one-handed cut down from over the shoulder' },
  { name: 'swing_1', kit: 'levy', melee: true, hits: 1, vars: [1], note: 'one-handed horizontal sweep' },
  { name: 'swing_2', kit: 'levy', melee: true, hits: 1, vars: [2], note: 'one-handed rising cut' },
  { name: 'swing2_0', kit: 'samurai', melee: true, hits: 1, vars: [0], note: 'two-handed cut from over the shoulder' },
  { name: 'swing2_1', kit: 'samurai', melee: true, hits: 1, vars: [1], note: 'two-handed horizontal sweep' },
  { name: 'swing2_2', kit: 'samurai', melee: true, hits: 1, vars: [2], note: 'two-handed rising cut' },
  { name: 'twin', kit: 'dabsong', melee: true, hits: 2, vars: [0, 1], note: 'two blades: right then left' },
  { name: 'bash_0', kit: 'infantry', melee: true, hits: 1, vars: [0], note: 'rifle butt straight jab' },
  { name: 'bash_1', kit: 'infantry', melee: true, hits: 1, vars: [1], note: 'rifle butt smash from overhead' },
  { name: 'bash_2', kit: 'infantry', melee: true, hits: 1, vars: [2], note: 'rifle butt side swing' },
  { name: 'claw_0', kit: 'mummy', melee: true, hits: 1, vars: [0], note: 'both hands raised, raking down' },
  { name: 'claw_1', kit: 'mummy', melee: true, hits: 1, vars: [1], note: 'right sweep, left follows' },
  { name: 'claw_2', kit: 'mummy', melee: true, hits: 1, vars: [2], note: 'arms wide, closing in front' },
  { name: 'stomp', kit: '@titan', melee: true, hits: 2, note: 'a giant lifts one leg high and stamps, then the other' }
];
const MIRRORS = [{ name: 'fire_pistol_r', from: 'fire_pistol_l', note: 'mirror of fire_pistol_l (the rig is symmetric)' }];
const REACTIONS = [
  { name: 'brace', kind: 'brace', note: 'shield raised toward the attacker, held, lowered (events: raised, lower)' },
  { name: 'brace_hit', kind: 'brace', knock: 0.3, note: 'the raised shield jolts under a blow' },
  { name: 'flinch', kind: 'flinch', from: 'front', k: 0.35, note: 'light flinch, hit from the front' },
  { name: 'flinch_back', kind: 'flinch', from: 'back', k: 0.35, note: 'light flinch, hit from behind' },
  { name: 'flinch_left', kind: 'flinch', from: 'left', k: 0.35, note: 'light flinch, hit from the left' },
  { name: 'flinch_right', kind: 'flinch', from: 'right', k: 0.35, note: 'light flinch, hit from the right' },
  { name: 'flinch_heavy', kind: 'flinch', from: 'front', k: 1, kb: 0.3, note: 'heavy hit from the front: knocked back a step' },
  { name: 'die_back', kind: 'die', v: 'back', note: 'falls on its back, away from the hit' },
  { name: 'die_fwd', kind: 'die', v: 'fwd', note: 'knees fold, falls forward' },
  { name: 'die_kneel', kind: 'die', v: 'kneel', note: 'sinks to its knees, then falls' },
  { name: 'die_spin', kind: 'die', v: 'spin', note: 'spins round and falls on its side' },
  { name: 'die_drop', kind: 'die', v: 'drop', note: 'drops straight down (a sniper hit)' },
  { name: 'die_blown', kind: 'die', v: 'blown', note: 'thrown back by a blast' },
  { name: 'die_topple', kind: 'die', v: 'topple', note: 'a giant topples slowly, the ground shakes' }
];
const LOCO = ['idle', 'walk', 'run', 'walk_start', 'walk_stop', 'run_start', 'run_stop', 'turn_left', 'turn_right', 'turn_back'];
const PROOFS = ['walk'];                        // --proofs: the walk the three proofs share (humanoid, walker = scaled rig)
const NOT_BAKED = [
  { name: 'lunge, turret, beam, gaze, spray, breath', why: 'beasts, vehicles and creatures without a humanoid skeleton: the page moves the whole model (no joints); they stay procedural until creature rigs exist' },
  { name: 'heal', why: 'needs a wounded friend as the target; the page plays it only from a dice throw (onThrowStart), not reachable through window.BT' },
  { name: 'rise, down', why: 'whole-figure tilt only (no joint motion): the runtime tilts the node' },
  { name: 'flying poses', why: 'fliers hold one pose (flyPose: idle + legs drawn up) and bob as a whole; not a clip yet' }
];

// ---------- runs inside the page: the sampler ----------
function pageLib(opt){
  var R = window.SKRIG, M = window.MINI, WK = window.WALKER, BT = window.BT;
  var J = R.J.map(function(j){ return j[0]; }), PAR = R.J.map(function(j){ return j[1]; }), OFF = R.J.map(function(j){ return j[2]; });
  var DT = 1/(opt.fps*opt.sub), NEUTRAL = opt.neutral;
  function qmul(a, b){ return R.qmul(a, b); }
  function qconj(q){ return [-q[0], -q[1], -q[2], q[3]]; }
  function qnorm(q){ var l = Math.hypot(q[0], q[1], q[2], q[3]) || 1; return [q[0]/l, q[1]/l, q[2]/l, q[3]/l]; }
  function qy(a){ return [0, Math.sin(a/2), 0, Math.cos(a/2)]; }
  function m3q(m){                                          // row-major 3x3 rotation -> quaternion
    var tr = m[0] + m[4] + m[8], s;
    if (tr > 0){ s = 0.5/Math.sqrt(tr + 1); return qnorm([(m[7] - m[5])*s, (m[2] - m[6])*s, (m[3] - m[1])*s, 0.25/s]); }
    if (m[0] > m[4] && m[0] > m[8]){ s = 2*Math.sqrt(1 + m[0] - m[4] - m[8]); return qnorm([0.25*s, (m[1] + m[3])/s, (m[2] + m[6])/s, (m[7] - m[5])/s]); }
    if (m[4] > m[8]){ s = 2*Math.sqrt(1 + m[4] - m[0] - m[8]); return qnorm([(m[1] + m[3])/s, 0.25*s, (m[5] + m[7])/s, (m[2] - m[6])/s]); }
    s = 2*Math.sqrt(1 + m[8] - m[0] - m[4]); return qnorm([(m[2] + m[6])/s, (m[5] + m[7])/s, 0.25*s, (m[3] - m[1])/s]); }
  // world frames of the rig (fk) -> local rotations + translations; xf = the page's whole-figure transform
  // (drawRig: v -> M v + push, about the feet), yaw = the piece's turn since the clip started
  function sample(W, xf, yaw){
    var q = [], t = [], i;
    for (i = 0; i < J.length; i++){ var n = J[i], w = W[n];
      if (!PAR[i]){ var p = w.p.slice(0, 3), r = w.q.slice(0, 4);
        if (xf && xf.m){ var m = xf.m; p = [m[0]*p[0] + m[1]*p[1] + m[2]*p[2], m[3]*p[0] + m[4]*p[1] + m[5]*p[2], m[6]*p[0] + m[7]*p[1] + m[8]*p[2]]; r = qmul(m3q(m), r); }
        if (xf && xf.push) p = [p[0] + xf.push[0], p[1] + xf.push[1], p[2] + xf.push[2]];
        if (yaw){ var qq = qy(yaw); p = R.qrot(qq, p); r = qmul(qq, r); }
        q.push(qnorm(r)); t.push(p); continue; }
      var P = W[PAR[i]], ci = qconj(P.q);
      q.push(qnorm(qmul(ci, w.q))); t.push(R.qrot(ci, R.sub(w.p, P.p))); }
    return { q: q, t: t };
  }
  function clonePose(P){ var q = {}, n; for (n in P.q) q[n] = P.q[n]; return { root: P.root.slice(), q: q, breath: P.breath || 0, contact: P.contact, v: P.v }; }
  function cnt(P){ var c = P && P.contact; return c ? [c.L || null, c.R || null] : [null, null]; }
  var SAMPLES = [];                                         // base poses kept for the holds layer
  function keep(P, every, i){ if (i % every === 0) SAMPLES.push(clonePose(P)); }

  // ---- locomotion: the v4 controller (one travel speed, planted feet pinned to the ground) ----
  // run it at a fixed speed until the gait repeats, then record one cycle from a right heel strike
  // (from WALKER.make(): a piece on the table always sets off from a stand, and the gait it settles into from there is
  // the one baked, so the start clips end exactly on this loop's frame 0)
  // a run set off from a stand takes ~7 s for its feet to settle half a cycle apart (a gait with a flight phase):
  // step until two right heel strikes in a row give the same pose; returns the controller just after that strike
  function steady(mode){
    var c = WK.make(), i, prev, last = null;
    c.set(mode);
    for (i = 0; i < 60*opt.fps*opt.sub; i++){ prev = c.R.st; c.step(DT);
      if (prev !== 'plant' && c.R.st === 'plant'){ var s = sample(R.fk(c.pose)); if (last && poseErr(s, last) < 1e-6) return { c: c, t: (i + 1)*DT }; last = s; } }
    throw new Error(mode + ': the gait never repeats');
  }
  function cycle(mode, noKeep){
    var S = steady(mode), c = S.c, settle = S.t, i, prev, rec = [{ P: clonePose(c.pose), W: R.fk(c.pose), tr: c.travel, v: c.v }], P, len = 0;
    for (i = 0; i < 4*opt.fps*opt.sub; i++){
      prev = c.R.st; P = c.step(DT);
      if (prev !== 'plant' && c.R.st === 'plant'){ len = i + 1; break; }
      rec.push({ P: clonePose(P), W: R.fk(P), tr: c.travel, v: c.v });
    }
    if (!len) throw new Error(mode + ': no repeating cycle');
    var end = clonePose(c.pose), Wend = R.fk(c.pose), frames = [], contact = [];
    var reg = [];
    for (i = 0; i < len; i += opt.sub){ var e = rec[i]; frames.push(sample(e.W)); contact.push(cnt(e.P)); reg.push({ P: e.P, tr: e.tr, v: e.v }); if (!noKeep) keep(e.P, 2, i/opt.sub); }
    if (!noKeep) REGL[mode] = { ref: reg, frames: frames };
    return { frames: frames, contact: contact, length: len*DT, speed: c.v, loop: true, loopErr: [sample(Wend), frames[0]],
      note: 'SKRIG.Controller ' + mode + ' at ' + c.v.toFixed(4) + ' m/s from a stand (WALKER.make), settled after ' + settle.toFixed(2) +
        ' s; one cycle from a right heel strike (' + len + ' steps of 1/' + (opt.fps*opt.sub) + ' s)' };
  }
  // a stand (WALKER.make: the settled idle stance) into a walk/run; ends on the right heel strike where `cycle` starts,
  // once the speed is steady and the gait has repeated
  function poseErr(A, B){ var e = 0; for (var i = 0; i < A.q.length; i++) e = Math.max(e, ang(A.q[i], B.q[i])); return e; }
  function start(mode){
    var vT = mode === 'run' ? R.V_RUN : R.V_WALK, end = -1, first = -1, pass, i, prev, frames, contact, travel, full = -1;
    var target = cycle(mode, true).frames[0], TOL = 0.25*Math.PI/180, MAXT = 2.5;
    // pass 0 finds the heel strike to end on: the first one at full speed whose pose is the loop's frame 0, looked for
    // during MAXT s at full speed; else the first heel strike 0.5 s after full speed (the seam is then reported).
    // pass 1 replays it (the rig is deterministic) with the frames lined up on that step.
    for (pass = 0; pass < 2; pass++){
      var c = WK.make(), tr0 = c.travel; frames = []; contact = []; travel = [];
      c.set(mode);
      if (pass === 1 && end % opt.sub === opt.sub - 1){ frames.push(sample(R.fk(c.pose))); contact.push(cnt(c.pose)); travel.push(0); }
      for (i = 0; i < 8*opt.fps*opt.sub; i++){
        prev = c.R.st; var P = c.step(DT);
        if (pass === 1 && (end - i) % opt.sub === 0){ frames.push(sample(R.fk(P))); contact.push(cnt(P)); travel.push(c.travel - tr0); }
        if (pass === 1 && i === end) break;
        if (pass > 0) continue;
        if (full < 0 && Math.abs(c.v - vT) < 1e-9) full = i;
        if (full >= 0 && prev !== 'plant' && c.R.st === 'plant'){
          if (first < 0 && (i - full)*DT >= 0.5) first = i;
          if (poseErr(sample(R.fk(P)), target) < TOL){ end = i; break; }
          if ((i - full)*DT > MAXT && first >= 0){ end = first; break; } }
      }
      if (end < 0) throw new Error(mode + ' start: never reached a steady gait');
    }
    return { frames: frames, contact: contact, travel: travel, length: (frames.length - 1)/opt.fps, speed: vT, loop: false,
      note: 'WALKER.make() stance, Controller set to ' + mode + '; ends on the first right heel strike at full speed whose pose is the ' + mode +
        ' loop\'s frame 0 (else the first one 0.5 s after reaching full speed; see seam)' };
  }
  // steady walk/run from a right heel strike, told to stop: brakes, the feet settle under the body, the idle blends in
  function stop(mode){
    var c = steady(mode).c, i, frames = [], contact = [], travel = [], tr0 = c.travel;
    frames.push(sample(R.fk(c.pose))); contact.push(cnt(c.pose)); travel.push(0);
    c.set('idle');
    for (i = 0; i < 8*opt.fps*opt.sub; i++){
      var P = c.step(DT);
      if ((i + 1) % opt.sub === 0){ frames.push(sample(R.fk(P))); contact.push(cnt(P)); travel.push(c.travel - tr0); }
      if (c.settled && c.v === 0 && c.wi >= 1 && (i + 1) % opt.sub === 0) break;
    }
    return { frames: frames, contact: contact, travel: travel, length: (frames.length - 1)/opt.fps, speed: 0, loop: false,
      note: 'steady ' + mode + ' (frame 0 = the ' + mode + ' loop\'s frame 0), Controller set to idle: brakes, settles both feet, blends to idle' };
  }
  // breathing idle (SKRIG.idlePose: breath 4.2 s, weight shift 7 s, head 9 s / 11 s), made to loop: the first B seconds
  // cross-fade from idlePose(t + L) into idlePose(t); the legs are solved again onto the idle feet so they never move
  function idle(L, B){
    var n = Math.round(L*opt.fps), frames = [], contact = [], k, IF = R.IDLE_FT, reg = [];
    var aL = IF.L.a, qL = R.footQ(IF.L.yaw, 0), aR = IF.R.a, qR = R.footQ(IF.R.yaw, 0);
    for (k = 0; k < n; k++){ var t = k/opt.fps, P;
      if (t >= B) P = R.idlePose(t);
      else { var A = R.idlePose(t + L), Bp = R.idlePose(t), s = R.clamp(t/B, 0, 1); s = s*s*(3 - 2*s);
        P = R.newPose(); P.root = [A.root[0] + (Bp.root[0] - A.root[0])*s, A.root[1] + (Bp.root[1] - A.root[1])*s, A.root[2] + (Bp.root[2] - A.root[2])*s];
        P.breath = A.breath + (Bp.breath - A.breath)*s;
        J.forEach(function(nm){ if (/^(hip|knee|ankle)/.test(nm)) return; var a = A.q[nm] || R.QI, b = Bp.q[nm] || R.QI; P.q[nm] = R.qslerp(a, b, s); });
        R.legIK(P, 'L', aL, qL); R.legIK(P, 'R', aR, qR); P.contact = { L: 'flat', R: 'flat' }; }
      frames.push(sample(R.fk(P))); contact.push(cnt(P)); keep(P, 6, k); reg.push({ P: clonePose(P), tr: 0, v: 0 }); }
    REGL.idle = { ref: reg, frames: frames };
    return { frames: frames, contact: contact, length: L, speed: 0, loop: true, loopErr: [sample(R.fk(R.idlePose(L))), frames[0]],
      note: 'SKRIG.idlePose over ' + L + ' s (two breaths); the first ' + B + ' s cross-fade from idlePose(t + ' + L + ') so the loop is seamless; feet re-solved onto the idle stance' };
  }
  // turning on the spot (WALKER: a bearing sharper than C.HOLD stops and pivots; the planted foot keeps its spot and the
  // feet shuffle back under the body). C.GO is set out of reach for the bake so the piece never walks off.
  function turn(deg){
    var u = { x: 0, z: 0, rot: 0, scale: 1 }, a = deg*Math.PI/180, frames = [], contact = [], yaws = [], i, go = WK.C.GO;
    WK.goTo(u, Math.sin(a)*40, Math.cos(a)*40); WK.C.GO = -1;
    var c = u.ctl, reg = []; frames.push(sample(R.fk(c.repose()), null, 0)); contact.push(cnt(c.pose)); yaws.push(0); reg.push({ P: clonePose(c.pose), yaw: 0 });
    try {
      for (i = 0; i < 10*opt.fps*opt.sub; i++){
        WK.step(u, DT, null);
        if ((i + 1) % opt.sub === 0){ var P = c.pose; frames.push(sample(R.fk(P), null, u.rot)); contact.push(cnt(P)); yaws.push(u.rot); reg.push({ P: clonePose(P), yaw: u.rot });
          if (i % (opt.sub*3) === 0) SAMPLES.push(clonePose(P)); }
        var d = Math.atan2(Math.sin(a - u.rot), Math.cos(a - u.rot));
        if (Math.abs(d) < 1e-9 && c.settled && c.v === 0 && c.wi >= 1 && (i + 1) % opt.sub === 0) break;
      }
    } finally { WK.C.GO = go; }
    if (Math.hypot(u.x, u.z) > 1e-9) throw new Error('turn ' + deg + ': the piece moved ' + Math.hypot(u.x, u.z));
    REGL['turn' + deg] = { ref: reg, frames: frames };
    return { frames: frames, contact: contact, yaw: yaws, length: (frames.length - 1)/opt.fps, speed: 0, turn: u.rot, loop: false,
      note: 'WALKER pivot on the spot toward a bearing of ' + deg + ' deg at ' + WK.C.TURN + ' rad/s; feet shuffle when they drift ' + WK.C.SHUFFLE + ' m; pelvis carries the turn (start facing = +Z)' };
  }

  // ---- actions through the battle table (window.BT) ----
  function fresh(){
    BT.units.length = 0; var F = BT.fallen(); F.length = 0; try { BT.fx8({ clear: true }); } catch (e){}
  }
  function basePose(k){ var P = R.idlePose(0); M.pose(k, P); return P; }
  function aimKit(spec){
    if (spec !== '@titan') return spec;
    var T = BT.TYPES.filter(function(T){ var K = M.KITS[T.k]; return T.ttn && !T.fly && K && !K.creature && !K.mount && R.fk(basePose(T.k)).ankleL; });
    return T.length ? T[0].k : null;
  }
  // step the piece's action 1/30 s at a time: frame 0 is the stance it starts from, the last frame the stance it ends in
  function local(W, i){ var n = J[i]; return PAR[i] ? qmul(qconj(W[PAR[i]].q), W[n].q) : W[n].q; }
  function copyW(W){ var o = {}, n; for (n in W) o[n] = { p: W[n].p.slice(0, 3), q: W[n].q.slice(0, 4) }; return o; }
  // step the piece's action 1/30 s at a time: frame 0 is the stance it starts from, the last frame the stance it ends
  // in; `gearKit` (the kit whose attack this is) puts the gear the page orients by itself into the bones that carry it
  function runAct(u, a, onTick, gearKit){
    var raw = [], alpha = [], ev = [], W0 = R.fk(basePose(u.skn || u.k)), done = {}, f = 0;
    raw.push({ W: copyW(W0), xf: null, gear: null }); alpha.push(1);
    var shotT = (a.shots || []).map(function(s){ return s.t; });
    while (u.act === a && f < 20*opt.fps){
      var t0 = a.t;
      // BT.tick = one simulation step + one draw; the bare rig (u.skn) has no palette of its own, so a draw may throw
      // after the step has run: the step is what counts, and it must have moved the action on by exactly 1/30 s
      try { BT.tick(1/opt.fps, 1); } catch (e){ if (u.act === a && Math.abs(a.t - t0 - 1/opt.fps) > 1e-9) throw e; }
      f++;
      if (onTick) onTick(a, f);
      if (u.act !== a) break;
      raw.push({ W: copyW(a.W || W0), xf: a.xf ? { m: a.xf.m ? a.xf.m.slice() : null, push: a.xf.push ? a.xf.push.slice() : null } : null,
        gear: a.gear ? JSON.parse(JSON.stringify(a.gear)) : null });
      alpha.push(a.xf && a.xf.alpha != null ? Math.max(0, a.xf.alpha) : 1);
      (a.shots || []).forEach(function(s, i){ if (s.done && !done[i]){ done[i] = 1; ev.push({ t: shotT[i] != null ? shotT[i] : a.t, kind: 'shot' }); } });
      if (a.loosed && !done.l){ done.l = 1; ev.push({ t: a.rel, kind: 'shot' }); }
      if (a.thud && !done.th){ done.th = 1; ev.push({ t: a.t, kind: 'thud' }); }
    }
    var dur = a.dur;
    if (a.kind === 'die') raw.push(raw[raw.length - 1]), alpha.push(0);             // it stays down (faded out)
    else raw.push({ W: copyW(W0), xf: null, gear: null }), alpha.push(1);          // back in its stance
    var ref = raw.map(function(r){ return { W: copyW(r.W), gear: r.gear, xf: r.xf }; });
    var gfix = gearKit ? gearFix(gearKit, raw) : null;
    return { frames: raw.map(function(r){ return sample(r.W, r.xf); }), alpha: alpha, events: ev, dur: dur, gearFix: gfix, ref: ref };
  }

  // ---- gear: the page draws a gun along the line between the hands, a bow upright at the aim, a spear or blade along
  // the action's own direction, a shield turned to face the blow (MINI.build reads the action's gear). The kits bind
  // that geometry rigidly to one joint (export_kits.js: the joint whose move carries the face), so the joint has to
  // turn the way the page turns the gear: per frame, the gear faces of each joint are matched between the kit's rest
  // build and the page's build of that frame, and the joint's world rotation becomes the best rigid fit (Horn) about
  // the joint. Faces that bend (a drawn bowstring) are left out of the fit.
  function copyF(fs){ return fs.map(function(f){ return { p: f.p.map(function(q){ return q.slice(0, 3); }), k: String(f.k) }; }); }
  function owners(kit, Wd, faces, act){
    var own = [], best = [], i, j, m;
    for (i = 0; i < faces.length; i++){ own.push(-1); best.push(0); }
    for (j = 0; j < J.length; j++){
      var F = copyW(Wd); F[J[j]].p[1] += 50;
      var fs = M.build(kit, F, 1, act ? { act: act } : undefined);
      if (fs.length !== faces.length) continue;
      for (i = 0; i < fs.length; i++){ var a = faces[i].p, c = fs[i].p, d = 0; if (a.length !== c.length) continue;
        for (m = 0; m < a.length; m++) d = Math.max(d, Math.hypot(c[m][0] - a[m][0], c[m][1] - a[m][1], c[m][2] - a[m][2]));
        if (d > 1 && d > best[i]){ best[i] = d; own[i] = j; } }
    }
    return own;
  }
  function jacobi4(A){
    var a = A.map(function(r){ return r.slice(); }), v = [[1, 0, 0, 0], [0, 1, 0, 0], [0, 0, 1, 0], [0, 0, 0, 1]], s, p, q, k;
    for (s = 0; s < 60; s++){
      var off = 0; for (p = 0; p < 3; p++) for (q = p + 1; q < 4; q++) off += a[p][q]*a[p][q];
      if (off < 1e-24) break;
      for (p = 0; p < 3; p++) for (q = p + 1; q < 4; q++){
        if (Math.abs(a[p][q]) < 1e-300) continue;
        var th = (a[q][q] - a[p][p])/(2*a[p][q]), t = (th >= 0 ? 1 : -1)/(Math.abs(th) + Math.sqrt(th*th + 1)), c = 1/Math.sqrt(t*t + 1), sn = t*c;
        for (k = 0; k < 4; k++){ var x = a[k][p], y = a[k][q]; a[k][p] = c*x - sn*y; a[k][q] = sn*x + c*y; }
        for (k = 0; k < 4; k++){ var x2 = a[p][k], y2 = a[q][k]; a[p][k] = c*x2 - sn*y2; a[q][k] = sn*x2 + c*y2; }
        for (k = 0; k < 4; k++){ var x3 = v[k][p], y3 = v[k][q]; v[k][p] = c*x3 - sn*y3; v[k][q] = sn*x3 + c*y3; }
      }
    }
    return { vals: [a[0][0], a[1][1], a[2][2], a[3][3]], vecs: v };
  }
  // the rotation q (about the origin) that takes the points A onto B best (Horn 1987: the top eigenvector of N)
  function horn(A, B){
    var S = [[0, 0, 0], [0, 0, 0], [0, 0, 0]], i, r, c;
    for (i = 0; i < A.length; i++) for (r = 0; r < 3; r++) for (c = 0; c < 3; c++) S[r][c] += A[i][r]*B[i][c];
    var xx = S[0][0], xy = S[0][1], xz = S[0][2], yx = S[1][0], yy = S[1][1], yz = S[1][2], zx = S[2][0], zy = S[2][1], zz = S[2][2];
    var N = [[xx + yy + zz, yz - zy, zx - xz, xy - yx], [yz - zy, xx - yy - zz, xy + yx, zx + xz],
             [zx - xz, xy + yx, -xx + yy - zz, yz + zy], [xy - yx, zx + xz, yz + zy, -xx - yy + zz]];
    var e = jacobi4(N), bi = 0; for (i = 1; i < 4; i++) if (e.vals[i] > e.vals[bi]) bi = i;
    return qnorm([e.vecs[1][bi], e.vecs[2][bi], e.vecs[3][bi], e.vecs[0][bi]]);
  }
  function groups(own, faces){ var g = {}; for (var i = 0; i < faces.length; i++){ var j = own[i]; if (j < 0) continue;
    var key = j + '|' + faces[i].k; (g[key] = g[key] || []).push(i); } return g; }
  // only the joints that hold things: the hands (gun, bow, spear, blade) and the forearms (a shield rides the forearm)
  var GEAR_BONES = { handL: 1, handR: 1, wristL: 1, wristR: 1, elbowL: 1, elbowR: 1 };
  function gearFix(kit, raw){
    var K = M.KITS[kit]; if (!K || K.mount || K.creature) return null;
    var S = K.scale || 1, W0 = R.fk(basePose(kit)), F0 = copyF(M.build(kit, W0, 1)), own0 = owners(kit, W0, F0, null), g0 = groups(own0, F0);
    var st = { kit: kit, frames: 0, bones: {}, maxDeg: 0, residualMm: 0 };
    // a hand or forearm is turned only on the side whose arm the action moves (else the kit's own arm hold has it)
    var moved = {};
    J.forEach(function(n, i){ if (!/^(shoulder|elbow|wrist|hand)/.test(n)) return; var side = n.slice(-1), l0 = local(raw[0].W, i);
      for (var f = 1; f < raw.length; f++) if (ang(local(raw[f].W, i), l0) > Math.PI/180){ moved[side] = 1; break; } });
    raw.forEach(function(r){
      var F1 = copyF(M.build(kit, r.W, 1, r.gear ? { act: r.gear } : undefined));
      var g1 = F1.length === F0.length ? g0 : groups(owners(kit, r.W, F1, r.gear), F1), fixedAny = false;
      var byBone = {};
      Object.keys(g0).forEach(function(key){ var b = g1[key]; if (!b) return; var j = +key.split('|')[0], a = g0[key], n = Math.min(a.length, b.length);
        for (var i = 0; i < n; i++){ var f0 = F0[a[i]], f1 = F1[b[i]]; if (f0.p.length !== f1.p.length) continue; (byBone[j] = byBone[j] || []).push([f0, f1]); } });
      Object.keys(byBone).forEach(function(js){
        var j = +js, n = J[j], pairs = byBone[js], P0 = W0[n].p, P1 = r.W[n].p, dq = qmul(r.W[n].q, qconj(W0[n].q));
        if (!GEAR_BONES[n] || !moved[n.slice(-1)]) return;   // a cape or a tabard spans joints: never turn the body for it
        var gear = pairs.filter(function(pr){ for (var m = 0; m < pr[0].p.length; m++){
          var a0 = R.sub(R.mul(pr[0].p[m], 1/S), P0), b1 = R.sub(R.mul(pr[1].p[m], 1/S), P1), pd = R.qrot(dq, a0);
          if (Math.hypot(b1[0] - pd[0], b1[1] - pd[1], b1[2] - pd[2]) > 0.002) return true; } return false; });
        if (!gear.length) return;
        // least squares over every gear face, then trimmed refits (faces missing by more than 5 mm or 1.5x the median
        // drop out: bending parts such as a drawn bowstring); the fit with the smallest RMS over ALL gear faces is kept,
        // and only if it beats the joint's own turn (FK) clearly: a fit never makes the page's gear worse
        var pts = function(set){ var A = [], Bp = []; set.forEach(function(pr){ for (var m = 0; m < pr[0].p.length; m++){
          A.push(R.sub(R.mul(pr[0].p[m], 1/S), P0)); Bp.push(R.sub(R.mul(pr[1].p[m], 1/S), P1)); } }); return [A, Bp]; };
        var all = pts(gear), rms = function(qq){ var e = 0; for (var i = 0; i < all[0].length; i++){ var a0 = R.qrot(qq, all[0][i]), b1 = all[1][i];
          e += (b1[0] - a0[0])*(b1[0] - a0[0]) + (b1[1] - a0[1])*(b1[1] - a0[1]) + (b1[2] - a0[2])*(b1[2] - a0[2]); } return Math.sqrt(e/all[0].length); };
        var use = gear, q = null, bestQ = null, bestE = rms(dq), fkE = bestE, pass;
        for (pass = 0; pass < 4 && use.length; pass++){
          var pp = pts(use); q = horn(pp[0], pp[1]);
          var e = rms(q); if (e < bestE){ bestE = e; bestQ = q; }
          var errs = use.map(function(pr){ var e2 = 0; for (var m = 0; m < pr[0].p.length; m++){ var a0 = R.qrot(q, R.sub(R.mul(pr[0].p[m], 1/S), P0)), b1 = R.sub(R.mul(pr[1].p[m], 1/S), P1);
            e2 = Math.max(e2, Math.hypot(b1[0] - a0[0], b1[1] - a0[1], b1[2] - a0[2])); } return e2; });
          var sorted = errs.slice().sort(function(x, y){ return x - y; }), lim = Math.max(0.005, 1.5*sorted[sorted.length >> 1]);
          var keep = use.filter(function(pr, i){ return errs[i] <= lim; });
          if (keep.length === use.length || !keep.length) break; use = keep;
        }
        if (!bestQ || bestE > 0.6*fkE) return;
        q = bestQ; var res = bestE;        var nq = qnorm(qmul(q, W0[n].q)), d = ang(nq, r.W[n].q);
        if (d < 0.3*Math.PI/180) return;
        r.W[n].q = nq; fixedAny = true;
        st.bones[n] = Math.max(st.bones[n] || 0, d*180/Math.PI); st.maxDeg = Math.max(st.maxDeg, d*180/Math.PI); st.residualMm = Math.max(st.residualMm, res*1000); st.fkMm = Math.max(st.fkMm || 0, fkE*1000);
      });
      if (fixedAny) st.frames++;
    });
    return st;
  }
  function action(spec){
    fresh(); var kit = aimKit(spec.kit); if (!kit) return { error: 'no kit for ' + spec.kit };
    var dist = spec.melee ? 1.4 : 10;
    BT.add(kit, 0, 0); BT.add('infantry', 0, dist);
    var u = BT.units[0], t = BT.units[1]; u.id = 'bake.0'; t.id = 'bake.1';
    BT.animate(0, 1, !!spec.melee, spec.hits);
    var a = u.act; if (!a) return { error: 'no action started for ' + kit };
    if (spec.vars) a.vars = spec.vars.slice();
    // the stance the action starts from: the kit's own when its pose only carries the arms (a rifle at the low ready,
    // a shield across the body: what every kit of that kind starts from), else a bare rig (no crouch in a shared clip)
    var own = armsOnly(kit);
    if (!own) u.skn = NEUTRAL;
    var r = runAct(u, a, null, kit);
    r.kit = spec.kit.charAt(0) === '@' ? spec.kit : kit; r.kind = a.kind; r.gun = a.gun || null; r.hand = a.hand || null; r.hv = !!a.hv;
    r.base = own ? 'kit' : 'bare';
    if (own) bareRest(r.frames);
    // what the page draws for this kit (its own stance), for the fidelity check
    REG[spec.name] = { kit: kit, ref: own ? r.ref : refRun(function(){ BT.add(kit, 0, 0); BT.add('infantry', 0, dist); BT.animate(0, 1, !!spec.melee, spec.hits);
      var u2 = BT.units[0], a2 = u2.act; if (a2 && spec.vars) a2.vars = spec.vars.slice(); return [u2, a2]; }) };
    delete r.ref;
    r.fidelity = REG[spec.name].ref ? fidelityOf(kit, REG[spec.name].ref, r.frames, 'undriven') : null;
    REG[spec.name].frames = r.frames;
    return r;
  }
  function debugFid(name){ var g = REG[name]; return fidelityOf(g.kit, g.ref, g.frames, 'undriven', true); }
  // the joints an action leaves alone go back to the bare rig's idle: a kit's holds put its own pose on them at play time
  // (the clip must not carry one kit's arm hold for every kit)
  var BARE = null;
  function bareRest(frames){
    if (!BARE) BARE = sample(R.fk(R.idlePose(0)));
    J.forEach(function(n, i){ if (!PAR[i]) return; var q0 = frames[0].q[i], moved = frames.some(function(fr){ return ang(fr.q[i], q0) > 0.5*Math.PI/180; });
      if (!moved) frames.forEach(function(fr){ fr.q[i] = BARE.q[i].slice(); }); });
  }
  function refRun(setup){ fresh(); var ua = setup(); if (!ua || !ua[1]) return null; return runAct(ua[0], ua[1], null, null).ref; }
  var REG = {};
  function armsOnly(k){
    var P0 = R.idlePose(0), P = clonePose(P0); M.pose(k, P);
    if (Math.hypot(P.root[0] - P0.root[0], P.root[1] - P0.root[1], P.root[2] - P0.root[2]) > 1e-9) return false;
    return J.every(function(n){ return /^(shoulder|elbow|wrist|hand)/.test(n) || ang(P0.q[n] || R.QI, P.q[n] || R.QI) < 1e-4; });
  }
  function axisFrom(from){ return { front: [0, 0, 1.6], back: [0, 0, -1.6], left: [1.6, 0, 0], right: [-1.6, 0, 0] }[from || 'front']; }
  function reaction(spec){
    fresh();
    var o = axisFrom(spec.from), kit = spec.kind === 'brace' ? 'hoplite' : 'infantry';
    BT.add(kit, 0, 0); BT.add('infantry', o[0], o[2]);
    // a shield is raised from the bearer's own stance (its other arm keeps the spear); a flinch or a fall from a bare
    // rig (the arms are the holds' business)
    var u = BT.units[0], brace = spec.kind === 'brace'; u.id = 'bake.0'; BT.units[1].id = 'bake.1'; if (!brace) u.skn = NEUTRAL; var a;
    if (spec.kind === 'brace'){ BT.brace(0, 1); a = u.act; }
    else if (spec.kind === 'flinch'){ BT.hurt8(0, 1, 1, null); a = u.act; a.k = spec.k; a.kb = spec.kb || 0; a.sy = 8;
      a.dur = 0.35 + 0.35*spec.k + (a.kb ? 0.3 : 0); }
    else if (spec.kind === 'die'){ BT.kill8(0, spec.v, 1, null); a = u.act; }      // falls away from piece 1
    if (!a) return { error: 'no ' + spec.kind + ' started' };
    var r = runAct(u, a, function(a, f){
      if (spec.kind === 'brace'){ if (spec.knock != null && a.knock == null && a.t >= spec.knock){ a.knock = a.t; a.hurt = false; }
        if (a.up >= 1 && !a._raised){ a._raised = 1; r0.events.push({ t: a.t, kind: 'raised' }); }
        if (a.t >= 0.5 && !a._low){ a._low = 1; r0.events.push({ t: a.t, kind: 'lower' }); } }
    }, brace ? kit : null);
    r.events = (r0.events || []).concat(r.events); r0.events = [];
    r.kit = brace ? kit : NEUTRAL; r.kind = spec.kind; r.base = brace ? 'kit' : 'bare';
    if (brace) bareRest(r.frames);
    REG[spec.name] = { kit: kit, ref: brace ? r.ref : refRun(function(){ BT.add(kit, 0, 0); BT.add('infantry', o[0], o[2]); var u2 = BT.units[0], a2;
      if (spec.kind === 'flinch'){ BT.hurt8(0, 1, 1, null); a2 = u2.act; a2.k = spec.k; a2.kb = spec.kb || 0; a2.sy = 8; a2.dur = 0.35 + 0.35*spec.k + (a2.kb ? 0.3 : 0); }
      else { BT.kill8(0, spec.v, 1, null); a2 = u2.act; }
      return [u2, a2]; }) };
    delete r.ref;
    r.fidelity = REG[spec.name].ref ? fidelityOf(kit, REG[spec.name].ref, r.frames, 'undriven') : null;
    REG[spec.name].frames = r.frames;
    return r;
  }
  var r0 = { events: [] };
  // a rider in the saddle (MINI.riderPose: the mount's seat height, lean, leg spread and how the arms are held)
  function seat(k){ var P = M.riderPose(k); return { frames: [sample(R.fk(P))], contact: [[null, null]], length: 0, speed: 0, loop: true, kit: k,
    note: 'MINI.riderPose(' + k + '): the rider of this mount, still (the page draws riders still)' }; }

  // ---- the holds layer: how each kit's own pose (MINI.pose, e.g. both hands on a rifle) changes a base pose ----
  // per joint a target rotation C and a weight w, so that kitPose(base) ~= slerp(base, C, w); fitted over the base
  // poses sampled above, with the residual. A kit whose pose moves the root re-solves its legs (crouch): legs = 'ik'.
  function qlog(q){ var v = Math.hypot(q[0], q[1], q[2]), w = q[3]; if (w < 0){ q = [-q[0], -q[1], -q[2], -w]; w = -w; } var a = Math.atan2(v, w);
    return v < 1e-12 ? [0, 0, 0] : [q[0]/v*a, q[1]/v*a, q[2]/v*a]; }
  function qexp(v){ var a = Math.hypot(v[0], v[1], v[2]), s = a < 1e-12 ? 1 : Math.sin(a)/a; return qnorm([v[0]*s, v[1]*s, v[2]*s, Math.cos(a)]); }
  function ang(a, b){ return 2*Math.acos(Math.min(1, Math.abs(a[0]*b[0] + a[1]*b[1] + a[2]*b[2] + a[3]*b[3]))); }
  function holds(kits){
    var out = {}, S = SAMPLES;
    kits.forEach(function(k){
      var K = M.KITS[k]; if (!K || K.creature) return;
      var posed = [], root = [], err = null;
      S.forEach(function(P0){ var P = clonePose(P0); try { M.pose(k, P); } catch (e){ err = String(e.message || e); } posed.push(P);
        root.push([P.root[0] - P0.root[0], P.root[1] - P0.root[1], P.root[2] - P0.root[2]]); });
      if (err){ out[k] = { error: err }; return; }
      var rmax = 0, rm = [0, 0, 0]; root.forEach(function(d){ rmax = Math.max(rmax, Math.hypot(d[0], d[1], d[2])); rm = [rm[0] + d[0]/S.length, rm[1] + d[1]/S.length, rm[2] + d[2]/S.length]; });
      var ik = rmax > 1e-6, joints = {}, worst = 0;
      J.forEach(function(n){
        var b = S.map(function(P){ return P.q[n] || R.QI; }), p = posed.map(function(P){ return P.q[n] || R.QI; }), i, touched = 0;
        for (i = 0; i < b.length; i++) touched = Math.max(touched, ang(b[i], p[i]));
        if (touched < 0.05*Math.PI/180) return;
        if (ik && /^(hip|knee|ankle)/.test(n)){ joints[n] = 'ik'; return; }
        // model 1: slerp(base, C, w) — a joint set to a constant (w = 1) or eased toward one (the page's qslerp holds)
        var ref = p[0], cr = qconj(ref), lb = b.map(function(q){ return qlog(qmul(cr, q)); }), lp = p.map(function(q){ return qlog(qmul(cr, q)); });
        var mb = [0, 0, 0], mp = [0, 0, 0], N = b.length, c;
        for (i = 0; i < N; i++) for (c = 0; c < 3; c++){ mb[c] += lb[i][c]/N; mp[c] += lp[i][c]/N; }
        var num = 0, den = 0;
        for (i = 0; i < N; i++) for (c = 0; c < 3; c++){ num += (lp[i][c] - mp[c])*(lb[i][c] - mb[c]); den += (lb[i][c] - mb[c])*(lb[i][c] - mb[c]); }
        var keepB = den > 1e-12 ? R.clamp(num/den, 0, 1) : 0, w = 1 - keepB, C;
        if (w < 0.02){ w = 0; C = ref; } else { var lc = [0, 0, 0]; for (c = 0; c < 3; c++) lc[c] = (mp[c] - keepB*mb[c])/w; C = qnorm(qmul(ref, qexp(lc))); }
        var res = 0; for (i = 0; i < N; i++) res = Math.max(res, ang(R.qslerp(b[i], C, w), p[i]));
        if (w >= 0.98 && res < 0.5*Math.PI/180) w = 1;
        var bestFit = { C: C, w: w, res: res };
        // models 2 and 3: a fixed turn added after (base * D, the page's qmul(P.q.x, eul(...))) or before (D * base)
        [['mul', function(bi, pi){ return qmul(qconj(bi), pi); }, function(bi, D){ return qmul(bi, D); }],
         ['pre', function(bi, pi){ return qmul(pi, qconj(bi)); }, function(bi, D){ return qmul(D, bi); }]].forEach(function(m){
          var d0 = m[1](b[0], p[0]), acc = [0, 0, 0], cd = qconj(d0);
          for (i = 0; i < N; i++){ var li = qlog(qmul(cd, m[1](b[i], p[i]))); for (c = 0; c < 3; c++) acc[c] += li[c]/N; }
          var D = qnorm(qmul(d0, qexp(acc))), rr = 0; for (i = 0; i < N; i++) rr = Math.max(rr, ang(m[2](b[i], D), p[i]));
          if (rr < bestFit.res - 0.05*Math.PI/180){ bestFit = { res: rr }; bestFit[m[0]] = D; } });
        worst = Math.max(worst, bestFit.res);
        joints[n] = bestFit;
      });
      out[k] = { joints: joints, root: ik ? rm : null, rootSpread: ik ? rmax : 0, ik: ik, worstDeg: worst*180/Math.PI };
      HOLDS[k] = out[k];
    });
    return out;
  }
  function flat(){ try { BT.setTerrain('flat'); BT.setBuildings(false); } catch (e){} var h0 = BT.heightAt(0, 0), h1 = BT.heightAt(0, 10), h2 = BT.heightAt(0, 1.4);
    return { h: [h0, h1, h2] }; }
  // ---- fidelity: the kit as the new app would draw it (its rest mesh moved by the clip's bones, with its holds)
  // against the page's own drawing of the same moment (MINI.build of that kit with the page's frames and gear) ----
  var HOLDS = {}, REGL = {}, REST = {}, IDX = {};
  J.forEach(function(n, i){ IDX[n] = i; });
  function rest(kit){ if (REST[kit]) return REST[kit]; var W0 = R.fk(basePose(kit)), F0 = copyF(M.build(kit, W0, 1));
    return (REST[kit] = { W0: W0, F0: F0, own: owners(kit, W0, F0, null), S: M.KITS[kit].scale || 1 }); }
  function applyHolds(q, hold, mode, drives){
    if (!hold || !hold.joints || mode === 'none') return q;
    Object.keys(hold.joints).forEach(function(n){ var v = hold.joints[n], i = IDX[n]; if (v === 'ik' || i == null) return;
      if (mode === 'undriven' && drives.indexOf(n) >= 0) return;
      var x = q[i]; if (v.C) x = R.qslerp(x, v.C, v.w); else if (v.mul) x = qmul(x, v.mul); else if (v.pre) x = qmul(v.pre, x); q[i] = qnorm(x); });
    return q;
  }
  function fkLocal(q, t){ var W = {}; for (var i = 0; i < J.length; i++){ var n = J[i];
    if (!PAR[i]) W[n] = { p: t[i].slice(), q: q[i] }; else { var P = W[PAR[i]]; W[n] = { p: R.add(P.p, R.qrot(P.q, t[i])), q: qmul(P.q, q[i]) }; } } return W; }
  function drivesOf(frames){ return J.filter(function(n, i){ return frames.some(function(fr){ return ang(fr.q[i], frames[0].q[i]) > 0.5*Math.PI/180 ||
    Math.hypot(fr.t[i][0] - frames[0].t[i][0], fr.t[i][1] - frames[0].t[i][1], fr.t[i][2] - frames[0].t[i][2]) > 0.002; }); }); }
  // errors per face (the largest vertex miss), over the frames whose page drawing has the rest mesh's faces
  // the page's frames as bones (pelvis carries the whole-figure transform and the turn, like the clips do)
  function floorW(ref){ var smp = sample(ref.W, ref.xf, ref.yaw || 0); return fkLocal(smp.q, smp.t); }
  function fidelityOf(kit, refs, frames, mode, per, floor){
    var rs = rest(kit), hold = HOLDS[kit], drives = drivesOf(frames), errs = [], byKey = {}, used = 0, S = rs.S, perFrame = [];
    for (var f = 0; f < frames.length && f < refs.length; f++){
      var ref = refs[f]; if (!ref) continue;
      var page = M.build(kit, ref.W, 1, ref.mo || (ref.gear ? { act: ref.gear } : undefined));
      if (page.length !== rs.F0.length) continue;
      var cy = ref.yaw ? Math.cos(ref.yaw) : 1, sy = ref.yaw ? Math.sin(ref.yaw) : 0;
      var q = frames[f].q.map(function(x){ return x.slice(); }); applyHolds(q, hold, mode, drives);
      var Wc = floor ? floorW(ref) : fkLocal(q, frames[f].t), D = {};
      for (var i = 0; i < rs.F0.length; i++){
        var j = rs.own[i] < 0 ? 0 : rs.own[i], n = J[j], d = D[n] || (D[n] = qmul(Wc[n].q, qconj(rs.W0[n].q))), f0 = rs.F0[i].p, f1 = page[i].p, e = 0;
        if (f0.length !== f1.length) continue;
        for (var m = 0; m < f0.length; m++){
          var o = R.qrot(d, [f0[m][0] - S*rs.W0[n].p[0], f0[m][1] - S*rs.W0[n].p[1], f0[m][2] - S*rs.W0[n].p[2]]);
          var x = S*Wc[n].p[0] + o[0], y = S*Wc[n].p[1] + o[1], z = S*Wc[n].p[2] + o[2], px = f1[m][0], py = f1[m][1], pz = f1[m][2];
          if (ref.xf){ var X = ref.xf; if (X.m){ var M3 = X.m, ax = px, ay = py, az = pz; px = M3[0]*ax + M3[1]*ay + M3[2]*az; py = M3[3]*ax + M3[4]*ay + M3[5]*az; pz = M3[6]*ax + M3[7]*ay + M3[8]*az; }
            if (X.push){ px += X.push[0]*S; py += X.push[1]*S; pz += X.push[2]*S; } }
          if (ref.yaw){ var rx = px*cy + pz*sy, rz = -px*sy + pz*cy; px = rx; pz = rz; }
          e = Math.max(e, Math.hypot(x - px, y - py, z - pz)); }
        errs.push(e); var k = page[i].k; byKey[k] = Math.max(byKey[k] || 0, e);
        if (per){ var pf = perFrame[f] || (perFrame[f] = { f: f, max: 0, key: '', bone: '' }); if (e > pf.max){ pf.max = e; pf.key = k; pf.bone = n; } } }
      used++;
    }
    if (per) return { perFrame: perFrame, drives: drives };
    if (!errs.length) return { kit: kit, frames: 0 };
    var sorted = errs.slice().sort(function(a, b){ return a - b; }), sq = 0; errs.forEach(function(e){ sq += e*e; });
    var worst = Object.keys(byKey).sort(function(a, b){ return byKey[b] - byKey[a]; })[0];
    var out = { kit: kit, frames: used, rmsMm: Math.sqrt(sq/errs.length)*1000, p95Mm: sorted[Math.floor(sorted.length*0.95)]*1000, maxMm: sorted[sorted.length - 1]*1000,
      worstKey: worst, worstKeyMm: byKey[worst]*1000 };
    if (!floor){ var fl = fidelityOf(kit, refs, frames, mode, false, true); if (fl.frames){ out.floorRmsMm = fl.rmsMm; out.floorP95Mm = fl.p95Mm; out.floorMaxMm = fl.maxMm; } }
    return out;
  }
  // a locomotion clip on a kit: the page's frame = the controller's pose with the kit's own pose (MINI.pose) on it
  function fidelityLoco(kit, name){
    var L = REGL[name]; if (!L) return null; var S = M.KITS[kit].scale || 1;
    var refs = L.ref.map(function(e){ var P = clonePose(e.P); M.pose(kit, P); return { W: R.fk(P), mo: { travel: (e.tr || 0)*S, v: e.v || 0 }, yaw: e.yaw || 0 }; });
    return fidelityOf(kit, refs, L.frames, 'all');
  }
  function coverage(kits, name){ var out = {}; kits.forEach(function(k){ try { out[k] = fidelityLoco(k, name); } catch (e){ out[k] = { error: String(e.message || e) }; } }); return out; }
  window.__BAKE = { J: J, PAR: PAR, OFF: OFF, cycle: cycle, start: start, stop: stop, idle: idle, turn: turn, action: action, reaction: reaction,
    seat: seat, holds: holds, flat: flat, nSamples: function(){ return SAMPLES.length; }, fidelityLoco: fidelityLoco, coverage: coverage, debugFid: debugFid,
    mounts: function(){ return Object.keys(M.KITS).filter(function(k){ return !!M.KITS[k].mount; }); },
    kits: function(){ return Object.keys(M.KITS); }, VW: R.V_WALK, VR: R.V_RUN, appVer: null };
  BT.clock(false);
  return { joints: J, parents: PAR, offsets: OFF, flat: flat() };
}

// ---------- node side: shape the clips ----------
const r6 = v => Math.round(v*1e6)/1e6, r5 = v => Math.round(v*1e5)/1e5;
// the page's frames -> per-joint tracks; quaternion signs kept continuous; translations only where they move
function toClip(J, OFF, b, extra){
  const n = b.frames.length, q = {}, t = {};
  J.forEach((jn, i) => {
    let prev = null; q[jn] = b.frames.map(fr => { let v = fr.q[i].slice();
      if (prev && prev[0]*v[0] + prev[1]*v[1] + prev[2]*v[2] + prev[3]*v[3] < 0) v = v.map(x => -x);
      prev = v; return v.map(r6); });
    const moves = i === 0 || b.frames.some(fr => Math.hypot(fr.t[i][0] - OFF[i][0], fr.t[i][1] - OFF[i][1], fr.t[i][2] - OFF[i][2]) > 1e-6);
    if (moves) t[jn] = b.frames.map(fr => fr.t[i].map(r5));
  });
  const drives = J.filter((jn, i) => q[jn].some(v => qang(v, q[jn][0]) > 0.5*Math.PI/180) ||
    (t[jn] && t[jn].some(v => Math.hypot(v[0] - t[jn][0][0], v[1] - t[jn][0][1], v[2] - t[jn][0][2]) > 0.002)));
  const clip = Object.assign({ loop: !!b.loop, fps: FPS, frames: n, length: r6(b.loop ? b.length : (n - 1)/FPS), speed: r6(b.speed || 0) }, extra || {});
  if (b.turn != null) clip.turn = r6(b.turn);
  if (b.kit && b.kit !== NEUTRAL && !clip.kit) clip.from = b.kit;          // the kit whose attack picked this action
  if (b.kind) clip.kind = b.kind;
  if (b.gun) clip.gun = b.gun;
  if (b.hand) clip.hand = b.hand;
  if (b.hv) clip.heavy = true;
  if (b.base) clip.base = b.base;
  if (b.fidelity && b.fidelity.frames) clip.fidelity = fid(b.fidelity);
  if (b.gearFix && b.gearFix.frames){ const g = b.gearFix, bones = {};
    for (const n of Object.keys(g.bones)) bones[n] = Math.round(g.bones[n]*10)/10;
    clip.gear = { frames: g.frames, bones, maxDeg: Math.round(g.maxDeg*10)/10, rmsMm: Math.round(g.residualMm*10)/10, rmsWithoutMm: Math.round((g.fkMm || 0)*10)/10 }; }
  clip.q = q; clip.t = t;
  if (b.contact) clip.contact = { L: b.contact.map(c => c[0]), R: b.contact.map(c => c[1]) };
  if (b.travel) clip.travel = b.travel.map(r5);
  if (b.alpha && b.alpha.some(a => a < 0.999)) clip.alpha = b.alpha.map(a => Math.round(a*1000)/1000);
  if (b.events && b.events.length) clip.events = b.events.map(e => ({ t: r6(e.t), kind: e.kind }));
  clip.drives = drives;
  if (b.note) clip.note = b.note;
  if (b.loopErr){ const [A, B] = b.loopErr; let qe = 0, te = 0;
    J.forEach((jn, i) => { qe = Math.max(qe, qang(A.q[i], B.q[i])); te = Math.max(te, Math.hypot(A.t[i][0] - B.t[i][0], A.t[i][1] - B.t[i][1], A.t[i][2] - B.t[i][2])); });
    clip.loopError = { deg: r6(qe*180/Math.PI), mm: r6(te*1000) }; }
  return clip;
}
const fid = f => f && f.frames ? { kit: f.kit, frames: f.frames, rmsMm: Math.round(f.rmsMm*10)/10, p95Mm: Math.round(f.p95Mm*10)/10, maxMm: Math.round(f.maxMm*10)/10,
  worstPart: f.worstKey, worstPartMm: Math.round(f.worstKeyMm*10)/10,
  floorRmsMm: f.floorRmsMm != null ? Math.round(f.floorRmsMm*10)/10 : null, floorP95Mm: f.floorP95Mm != null ? Math.round(f.floorP95Mm*10)/10 : null } : null;
function qang(a, b){ return 2*Math.acos(Math.min(1, Math.abs(a[0]*b[0] + a[1]*b[1] + a[2]*b[2] + a[3]*b[3]))); }
const swapLR = n => n.replace(/L$/, '\u0000').replace(/R$/, 'L').replace(/\u0000$/, 'R');
function mirror(clip, note){
  const c = JSON.parse(JSON.stringify(clip)), q = {}, t = {};
  for (const jn of Object.keys(clip.q)) q[swapLR(jn)] = clip.q[jn].map(v => [v[0], -v[1], -v[2], v[3]].map(x => x === 0 ? 0 : x));
  for (const jn of Object.keys(clip.t)) t[swapLR(jn)] = clip.t[jn].map(v => [v[0] === 0 ? 0 : -v[0], v[1], v[2]]);
  c.q = q; c.t = t; c.drives = clip.drives.map(swapLR);
  if (clip.contact) c.contact = { L: clip.contact.R, R: clip.contact.L };
  if (clip.turn) c.turn = -clip.turn;
  if (clip.hand) c.hand = clip.hand === 'L' ? 'R' : 'L';
  c.note = note; c.mirrorOf = true;
  return c;
}

// ---------- validation (also run by kits.sh after the bake, and by validate_data.py) ----------
function validate(doc){
  const errs = [], J = doc.joints || [];
  if (doc.format !== FORMAT) errs.push('format ' + doc.format + ' != ' + FORMAT);
  if (doc.fps !== FPS) errs.push('fps ' + doc.fps + ' != ' + FPS);
  if (J.length !== 23) errs.push('joints: ' + J.length + ' != 23');
  const names = Object.keys(doc.clips || {});
  if (!names.length) errs.push('no clips');
  for (const nm of names){ const c = doc.clips[nm], e = s => errs.push(nm + ': ' + s);
    if (!/^[a-z0-9_]+$/.test(nm)) e('name must be [a-z0-9_]');
    if (c.fps !== FPS) e('fps ' + c.fps);
    if (typeof c.loop !== 'boolean') e('loop flag missing');
    if (!(c.frames >= 1)) e('frames ' + c.frames);
    const span = (c.frames - 1)/FPS;
    if (c.loop ? !(c.length >= span - 1e-6 && c.length <= span + 1/FPS + 1e-6) : Math.abs(c.length - span) > 1e-6) e('length ' + c.length + ' vs ' + c.frames + ' frames');
    for (const jn of J){ const tr = c.q && c.q[jn];
      if (!tr) { e('joint ' + jn + ' missing'); continue; }
      if (tr.length !== c.frames) e(jn + ': ' + tr.length + ' keys for ' + c.frames + ' frames');
      for (const v of tr) if (v.length !== 4 || !v.every(Number.isFinite) || Math.abs(Math.hypot(...v) - 1) > 1e-4){ e(jn + ': bad quaternion ' + JSON.stringify(v)); break; } }
    for (const jn of Object.keys(c.q || {})) if (J.indexOf(jn) < 0) e('unknown joint ' + jn);
    if (!c.t || !c.t.pelvis) e('pelvis translation missing');
    for (const jn of Object.keys(c.t || {})){ if (J.indexOf(jn) < 0) e('translation of unknown joint ' + jn);
      if (c.t[jn].length !== c.frames || !c.t[jn].every(v => v.length === 3 && v.every(Number.isFinite))) e(jn + ': bad translations'); }
    if (c.contact && (c.contact.L.length !== c.frames || c.contact.R.length !== c.frames)) e('contact length');
    for (const k of ['travel', 'alpha']) if (c[k] && c[k].length !== c.frames) e(k + ' length');
    if (!Number.isFinite(c.speed) || c.speed < 0) e('speed ' + c.speed);
  }
  return errs;
}

async function main(){
  if (ARGS.check){ const f = ARGS.check === true ? OUT : path.resolve(ROOT, ARGS.check);
    const doc = JSON.parse(fs.readFileSync(f, 'utf8')), errs = validate(doc);
    for (const e of errs.slice(0, 40)) console.log('FAIL', e);
    console.log(errs.length ? errs.length + ' problems in ' + f : 'clips.json ok: ' + Object.keys(doc.clips).length + ' clips, ' + Object.keys(doc.holds || {}).length + ' kit holds');
    process.exit(errs.length ? 1 : 0); }
  const t0 = Date.now(), src = fs.readFileSync(PAGE, 'utf8'), appVer = (/var APP_VER = '([^']+)'/.exec(src) || [])[1] || '?';
  let pw; try { pw = require(path.join(ROOT, 'tests/node_modules/playwright')); } catch (e){ pw = require('playwright'); }
  const browser = await pw.chromium.launch({ executablePath: process.env.CHROMIUM_PATH || undefined, args: ['--no-sandbox'] });
  const page = await browser.newPage({ viewport: { width: 640, height: 400 } });
  page.on('pageerror', e => console.error('page error:', e.message));
  // the page's visual randomness (spark directions, miss points, blow variants) is seeded so a bake repeats exactly
  await page.addInitScript(() => { let s = 0x2545F491; Math.random = function(){ s |= 0; s = s + 0x6D2B79F5 | 0; let t = Math.imul(s ^ s >>> 15, 1 | s);
    t = t + Math.imul(t ^ t >>> 7, 61 | t) ^ t; return ((t ^ t >>> 14) >>> 0)/4294967296; }; });
  await page.goto('file://' + PAGE);
  await page.waitForFunction(() => window.BT && window.BT.G && window.MINI && window.SKRIG && window.WALKER, null, { timeout: 120000 });
  const info = await page.evaluate(pageLib, { fps: FPS, sub: SUB, neutral: NEUTRAL });
  const J = info.joints, OFF = info.offsets, clips = {}, skipped = [];
  const only = ARGS.only ? new Set(ARGS.only.split(',')) : null, want = n => (!only || only.has(n)) && (!ARGS.proofs || PROOFS.indexOf(n) >= 0);
  const put = (name, b, extra) => { if (b.error){ skipped.push({ name, why: b.error }); console.log('skip', name, b.error); return; }
    clips[name] = toClip(J, OFF, b, extra); const c = clips[name];
    console.log(('  ' + name).padEnd(18), String(c.frames).padStart(4), 'frames', (c.length.toFixed(3) + ' s').padStart(8), c.loop ? 'loop' : '    ',
      c.speed ? 'v ' + c.speed.toFixed(3) : '', c.turn ? 'turn ' + (c.turn*180/Math.PI).toFixed(1) + ' deg' : '', c.loopError ? 'loop error ' + c.loopError.deg.toFixed(4) + ' deg ' + c.loopError.mm.toFixed(3) + ' mm' : '', b.kit ? '(' + b.kit + (b.base ? ', ' + b.base + ' stance' : '') + ')' : '',
      c.gear ? 'gear ' + Object.keys(c.gear.bones).join('+') + ' up to ' + c.gear.maxDeg + ' deg, rms ' + c.gear.rmsWithoutMm + ' -> ' + c.gear.rmsMm + ' mm' : '',
      c.fidelity ? '| vs page: rms ' + c.fidelity.rmsMm + ' p95 ' + c.fidelity.p95Mm + ' max ' + c.fidelity.maxMm + ' mm (' + c.fidelity.worstPart + '; skin floor rms ' + c.fidelity.floorRmsMm + ')' : ''); };
  console.log('baking from battle-table.html APP_VER ' + appVer + (ARGS.proofs ? ' (proofs only)' : ''));
  // locomotion
  const loco = {
    idle: () => page.evaluate(() => window.__BAKE.idle(8.4, 2.0)),
    walk: () => page.evaluate(() => window.__BAKE.cycle('walk')),
    run: () => page.evaluate(() => window.__BAKE.cycle('run')),
    walk_start: () => page.evaluate(() => window.__BAKE.start('walk')),
    run_start: () => page.evaluate(() => window.__BAKE.start('run')),
    walk_stop: () => page.evaluate(() => window.__BAKE.stop('walk')),
    run_stop: () => page.evaluate(() => window.__BAKE.stop('run')),
    turn_left: () => page.evaluate(() => window.__BAKE.turn(90)),
    turn_right: () => page.evaluate(() => window.__BAKE.turn(-90)),
    turn_back: () => page.evaluate(() => window.__BAKE.turn(180))
  };
  for (const n of LOCO) if (want(n)) put(n, await loco[n](), { set: 'humanoid', holds: 'all' });
  // a start must end where its loop begins, a stop must begin there
  for (const [a, b, which] of [['walk_start', 'walk', 'last'], ['run_start', 'run', 'last'], ['walk_stop', 'walk', 'first'], ['run_stop', 'run', 'first']]){
    if (!clips[a] || !clips[b]) continue; const fa = which === 'last' ? clips[a].frames - 1 : 0; let qe = 0, te = 0;
    for (const jn of J){ qe = Math.max(qe, qang(clips[a].q[jn][fa], clips[b].q[jn][0])); }
    const ta = clips[a].t.pelvis[fa], tb = clips[b].t.pelvis[0]; te = Math.hypot(ta[0] - tb[0], ta[1] - tb[1], ta[2] - tb[2]);
    clips[a].seam = { with: b, deg: r6(qe*180/Math.PI), mm: r6(te*1000) };
    console.log('  seam', a, '->', b, (qe*180/Math.PI).toFixed(3), 'deg', (te*1000).toFixed(2), 'mm'); }
  // holds: every skinned kit (kits.json when present, else every kit the page knows)
  let kitList = await page.evaluate(() => window.__BAKE.kits()), manifest = null;
  if (fs.existsSync(KITS_JSON)){ manifest = JSON.parse(fs.readFileSync(KITS_JSON, 'utf8')); kitList = kitList.filter(k => manifest.kits[k] && manifest.kits[k].skinned); }
  const holdsRaw = await page.evaluate(ks => window.__BAKE.holds(ks), kitList), holds = {};
  let nArm = 0, nIk = 0, nNone = 0, nApprox = 0;
  for (const k of Object.keys(holdsRaw).sort()){ const h = holdsRaw[k]; if (h.error){ holds[k] = { error: h.error }; continue; }
    const j = {}; for (const n of Object.keys(h.joints)){ const v = h.joints[n]; if (v === 'ik'){ j[n] = 'ik'; continue; }
      const o = {}; if (v.C){ o.C = v.C.map(r6); o.w = Math.round(v.w*1000)/1000; } if (v.mul) o.mul = v.mul.map(r6); if (v.pre) o.pre = v.pre.map(r6);
      o.res = Math.round(v.res*180/Math.PI*100)/100; j[n] = o; }
    holds[k] = { joints: j }; if (h.ik){ holds[k].root = h.root.map(r5); holds[k].rootSpread = r5(h.rootSpread); holds[k].ik = true; nIk++; }
    if (!Object.keys(j).length) nNone++; else if (!h.ik) nArm++;
    if (!h.ik && h.worstDeg > 2) nApprox++; }
  if (!ARGS.proofs){
    for (const s of ACTIONS) if (want(s.name)) put(s.name, Object.assign(await page.evaluate(sp => window.__BAKE.action(sp), s), { note: s.note }), { set: 'humanoid', holds: 'undriven' });
    for (const m of MIRRORS) if (want(m.name) && clips[m.from]) clips[m.name] = mirror(clips[m.from], m.note);
    for (const s of REACTIONS) if (want(s.name)) put(s.name, Object.assign(await page.evaluate(sp => window.__BAKE.reaction(sp), s), { note: s.note }), { set: 'humanoid', holds: 'undriven' });
  }
  // what each action clip came from
  for (const n of Object.keys(clips)){ const c = clips[n]; if (c.kit === undefined) c.kit = null; }
  // mounted: one still seat per mount kit
  const mounts = await page.evaluate(() => window.__BAKE.mounts());
  if (!ARGS.proofs || (only && only.has('seat'))) for (const k of mounts) put('seat_' + k.replace(/[^a-z0-9_]/g, '_'), await page.evaluate(k => window.__BAKE.seat(k), k), { set: 'mount', kit: k, holds: 'none' });
  // walker proof: the biggest skinned two-legged kit that walks (not a mount, not a flier)
  let walker = null;
  if (manifest){ for (const [k, e] of Object.entries(manifest.kits)){ if (!e.skinned || e.mount || e.fly || (e.type && e.type.fly) || e.creature) continue;
    if (!walker || e.scale > manifest.kits[walker].scale) walker = k; } }
  // how close the shared clips + a kit's holds come to the page's own drawing of that kit (rest mesh moved by the bones)
  const LOCO_REG = { walk: 'walk', run: 'run', idle: 'idle', turn_left: 'turn90', turn_right: 'turn-90', turn_back: 'turn180' };
  const fidelity = [];
  for (const [nm, kit] of [['walk', 'infantry'], ['run', 'infantry'], ['idle', 'infantry'], ['turn_left', 'infantry'], ['walk', 'hoplite'], ['walk', 'mech'], ['walk', walker]]){
    if (!kit || !clips[nm] || (manifest && !manifest.kits[kit])) continue;
    const f = fid(await page.evaluate(([k, r]) => window.__BAKE.fidelityLoco(k, r), [kit, LOCO_REG[nm]]));
    if (!f) continue; fidelity.push(Object.assign({ clip: nm }, f)); if (kit === 'infantry') clips[nm].fidelity = f;
    console.log('  fidelity', nm.padEnd(10), 'on', kit === walker ? 'the biggest walker' : kit, ': rms', f.rmsMm, 'p95', f.p95Mm, 'max', f.maxMm, 'mm (' + f.worstPart + '; skin floor rms ' + f.floorRmsMm + ' p95 ' + f.floorP95Mm + ')'); }
  let coverage = null;
  if (ARGS.fidelity){                                     // every skinned kit walking with its holds (slow: ~1 min)
    const raw = await page.evaluate(ks => window.__BAKE.coverage(ks, 'walk'), kitList), bands = { under5: 0, under20: 0, under50: 0, over50: 0, failed: 0 };
    coverage = {};
    for (const k of Object.keys(raw).sort()){ const f = fid(raw[k]); coverage[k] = f || raw[k];
      if (!f) bands.failed++; else if (f.p95Mm < 5) bands.under5++; else if (f.p95Mm < 20) bands.under20++; else if (f.p95Mm < 50) bands.under50++; else bands.over50++; }
    coverage = { clip: 'walk', note: 'p95 of the per-face miss (mm, at the kit\'s scale) between the skinned kit (walk + its holds) and the page\'s drawing; crouching kits need leg IK the bake does not do', bands, kits: coverage };
    console.log('  coverage walk:', JSON.stringify(bands)); }
  await browser.close();
  const doc = { format: FORMAT, fps: FPS, source: 'battle-table.html APP_VER ' + appVer, generator: 'godot/tools/bake_anim.js',
    units: 'rig metres (an unscaled 1.6 m figure); a kit of scale S plays a clip with Skeleton3D.motion_scale = S and moves at speed*S',
    axes: '+Y up, the figure faces +Z, its left is +X; quaternions [x,y,z,w] = the bone\'s rotation relative to its parent (Godot bone pose rotation)',
    joints: J, parents: info.parents, offsets: OFF.map(o => o.map(r6)),
    proofs: { humanoid: 'infantry', walker: walker, walkerScale: walker && manifest ? manifest.kits[walker].scale : null, mount: mounts[0] || null },
    note: 'q = local rotation of every joint per frame; t = local translation where it moves (always the pelvis: its place in the figure; ' +
      'chest and shoulders when the idle breathes). contact = which part of each foot the page pins to the ground (heel, ball, flat, null = in the air). ' +
      'speed = how fast the figure travels while the clip plays (rig m/s, in place); travel = distance covered by each frame (starts and stops); turn = yaw the pelvis ' +
      'carries by the last frame (radians, + = to the left); events = the moments the page fires a shot or lands a blow; alpha = the page\'s fade (falls); ' +
      'drives = the joints the clip moves (a kit\'s holds apply to the others). holds[kit].joints[j]: the kit\'s own pose (MINI.pose) for that joint is ' +
      '{C, w}: slerp(clip, C, w) · {mul}: clip * mul · {pre}: pre * clip, res = the worst miss in degrees over the sampled poses; ' +
      '"ik" = the kit crouches (holds[kit].root offsets the pelvis, rig metres) and its legs must be solved back onto the clip\'s feet.',
    notBaked: NOT_BAKED.concat(skipped),
    holdsSummary: { kits: Object.keys(holds).length, armsOnly: nArm, crouchIk: nIk, untouched: nNone, approxOver2deg: nApprox },
    fidelity, coverage, clips, holds };
  const errs = validate(doc);
  if (errs.length){ for (const e of errs.slice(0, 30)) console.error('FAIL', e); process.exit(1); }
  fs.mkdirSync(path.dirname(OUT), { recursive: true });
  fs.writeFileSync(OUT, JSON.stringify(doc));
  console.log('baked ' + Object.keys(clips).length + ' clips, holds for ' + Object.keys(holds).length + ' kits (' + nArm + ' arms only, ' + nIk + ' crouch + leg IK, ' + nNone +
    ' untouched, ' + nApprox + ' fitted > 2 deg), ' + (fs.statSync(OUT).size/1048576).toFixed(2) + ' MB, ' + ((Date.now() - t0)/1000).toFixed(0) + ' s -> ' + path.relative(ROOT, OUT));
}
main().catch(e => { console.error(e); process.exit(1); });
