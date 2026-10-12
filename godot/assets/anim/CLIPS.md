# Animation clips — `assets/anim/clips.json` → `humanoid.res`

The figures of the new app move the way the old page moves them: every clip here is the page's own rig sampled frame
by frame, not hand animation. `tools/bake_anim.js` drives the page headlessly (SKRIG.Controller, SKRIG.idlePose,
WALKER, and the battle table's action poses through `window.BT`) and writes `clips.json`; `tools/bake_anim.gd` turns
it into ONE `AnimationLibrary`, `humanoid.res`, that every skinned kit plays (same 23 bones, same names, same rest
convention: no retargeting). Both files are generated and git-ignored; CI makes them in the `kits` job
(`tools/kits.sh`). Never hand-edit them: change the tools or this contract. This file is the only committed one here.

```bash
bash godot/tools/kits.sh                                   # kits, impostors, clips (CI does the same)
node godot/tools/bake_anim.js [--only walk,run] [--fidelity]   # the clips alone (Playwright, ~20 s)
node godot/tools/bake_anim.js --check                      # validate clips.json (python3 godot/tools/validate_data.py does too)
<godot> --headless --path godot -s tools/bake_anim.gd      # clips.json -> humanoid.res
```

## 1. Conventions

- **Bones**: the 23 joints of the kits (`SKRIG.J`, assets/kits/CONTRACT.md §1), in that order; a quaternion is the
  bone's rotation relative to its parent, `[x, y, z, w]` — exactly a Godot bone pose rotation. A ride clip also moves
  its mount's own bones (`mount_*`, after the 23 in that kit's skeleton, in kits.json `mountRig.bones` order).
- **Units**: rig metres of an unscaled 1.6 m figure, +Y up, the figure faces +Z, its left is +X. A kit of scale `S`
  (`kits.json` `scale`) plays a clip with `Skeleton3D.motion_scale = S` (position keys are scaled, rotations are not)
  and travels `S` times as fast — the page walks a scaled figure that much further per stride.
- **Rate**: keys every 1/30 s. A loop's last key is followed by its first one `length − (frames − 1)/30` later (the
  run's cycle is 0.683 s, not a whole number of frames); a one-shot clip is `(frames − 1)/30` long.
- **In place**: clips do not move the figure. `speed` (rig m/s) is how fast the node must travel while a clip plays;
  starts and stops carry `travel` (rig metres covered by each frame) instead; turns carry `turn` (radians, + = to the
  left) in the pelvis track — the node takes the turn when the clip ends.

## 2. `clips.json`

Top level: `format` 1, `fps` 30, `source` (the page's APP_VER), `joints`, `parents`, `offsets` (bone offsets in the
parent, rig metres), `proofs` (`humanoid`, `walker` = the biggest skinned walker, its scale, `mount` = the first
mount kit and `mountClip` its ride walk), `fidelity` (locomotion clips measured against the page on the proof kits),
`coverage` (with `--fidelity`: every kit walking), `notBaked` (what the page has that is not a clip, and why: also
each mount without a ride clip), `holdsSummary`, `clips`, `holds`.

Per clip:

| field | meaning |
| --- | --- |
| `loop`, `fps`, `frames`, `length` | as §1 |
| `q[bone]` | `frames` quaternions, every bone, every frame |
| `t[bone]` | `frames` translations where the bone moves: always the pelvis (its place in the figure: bob, sway, a fall, a turn); chest and shoulders while the idle breathes; a hand whose wrist the gear fit turned; every mount bone of a ride clip |
| `speed`, `travel`, `turn` | §1 |
| `contact.L / .R` | per frame which part of the foot the page pins to the ground: `heel`, `ball`, `flat` or `null` (in the air); the foot-slide test reads it |
| `events` | `[{t, kind}]`: `shot` (a shot leaves, an arrow is loosed, a blow lands), `thud` (a fall hits the ground), `raised` / `lower` (a shield is up / comes down); the runtime starts tracers and sounds on them, or holds a shield clip at `raised` until the dice stop |
| `alpha` | the page's fade, falls only (1 → 0) |
| `drives` | the bones the clip moves |
| `holds` | how a kit's own pose applies on top: `all` (locomotion: the kit's hold wins on every bone it names), `undriven` (actions: only on bones the clip leaves alone), `none` (seats) |
| `kind`, `from`, `gun`, `hand`, `heavy`, `base` | which of the page's attacks it is (`from` = the kit whose ANIM entry picked it) and the stance it was played from (`kit`: that kit's own, which only carries its arms; `bare`: the bare rig) |
| `gear` | where the gear fit turned a hand or forearm (bones, largest turn, RMS of the gear faces before → after) |
| `fidelity` | the clip on its kit against the page's own drawing (below) |
| `loopError`, `seam` | a loop's last→first step; a start's last frame / a stop's first frame against its loop's frame 0 |
| `bones` | ride clips: the mount bones the clip moves besides the 23 (`mount_*`, kits.json `mountRig.bones` order) |
| `feet` | ride clips: per hoof `{bone, point, contact}`: the bone it rides on, a point on its sole (rest, rig metres) and per frame whether it is on the ground; the foot-slide test reads it |
| `gait`, `cycle`, `stance`, `beta`, `crossFade`, `bob`, `keySlideMm` | ride clips: `planted` (legs re-solved), stride and stance length (rig metres), the share of the stride a hoof is down, how many last frames cross-fade into the stride before (§4), how far the body sinks (mm), hoof slide between keys (mm) |

`holds[kit].joints[bone]`, the kit's own pose (MINI.pose: a rifle at the low ready, a shield across the body, a hunch)
fitted over ~120 sampled base poses: `{C, w}` = `slerp(clip, C, w)`, `{mul}` = `clip * mul`, `{pre}` = `pre * clip`,
`res` = the worst miss in degrees; `"ik"` = the kit crouches: `holds[kit].root` lowers the pelvis (rig metres) and its
legs must be solved back onto the clip's feet (two-bone IK) — the bake does not do that part.
`tests/render/test_anim_footslide.gd` `apply_holds()` is the reference implementation of the layer.

## 3. `humanoid.res`

One `AnimationLibrary`, one `Animation` per clip, named as in `clips.json`. Tracks: a rotation track per bone and a
position track per entry of `t`, paths `Skeleton3D:<bone>` — the kit scene is `<kit>` (Node3D) > `Skeleton3D` >
`<kit>_mesh`, so an `AnimationPlayer` added as a child of `<kit>` with `root_node = ".."` plays them as they are.
`loop_mode` LINEAR for loops. Each Animation's metadata: `speed`, `turn`, `travel`, `contact_l`, `contact_r`,
`events`, `alpha`, `drives`, `hold_mode`, `kit`, `from`, `kind`, `gun`, `hand`, `heavy`, `set`, `note`, `seam`; a ride
clip also `bones`, `feet` (`[{bone, point: Vector3, contact: PackedByteArray}]`), `gait`, `cycle`. The library's
metadata: `holds` (Quaternions), `proofs` (`humanoid`, `walker`, `mount`, `mountClip`), `joints`, `source`. 0.6 MB.

## 4. The library

- **Locomotion** (bare rig; `holds: all`): `idle` (8.4 s loop: two breaths, weight shift, head; the first 2 s
  cross-fade so it loops, legs re-solved onto the idle feet), `walk` (1.000 s, 1.150 m/s), `run` (0.683 s,
  2.868 m/s), `walk_start` / `run_start` (from the stand of WALKER.make), `walk_stop` / `run_stop` (brake, feet settle,
  idle blends in), `turn_left` / `turn_right` / `turn_back` (WALKER's pivot on the spot at 1.3 rad/s, feet shuffling).
  The loops are the gait the Controller settles into from a stand (a run takes ~7 s to settle its feet half a cycle
  apart); `walk_start` ends exactly on `walk`'s frame 0, `run_start` ends 0.5 s after full speed and does not (seam
  13° at the ankles: cross-fade).
- **Actions** (`holds: undriven`): `fire`, `fire_heavy`, `fire_sniper`, `fire_pistol_l`, `fire_pistol_r` (mirror),
  `bow`, `throw`, `hurl`, `lob`, `cast`, `zap`, `flame`, `thrust_0..2`, `swing_0..2`, `swing2_0..2`, `twin`,
  `bash_0..2`, `claw_0..2` (the page's three variants per blow), `stomp` (a giant's two stamps).
- **Reactions**: `brace`, `brace_hit`, `flinch` (front), `flinch_back`, `flinch_left`, `flinch_right`,
  `flinch_heavy`, `die_back`, `die_fwd`, `die_kneel`, `die_spin`, `die_drop`, `die_blown`, `die_topple`.
- **Mounted**: `seat_<mount kit>` — the rider in the saddle (MINI.riderPose), one frame; the page draws riders still.
  `ride_walk_<kit>` / `ride_run_<kit>` (10 clips) for the 5 mounts whose legs are rigid chains (kits.json
  `mountRig.gait`: the page's horse, which three kits share, the centaur and the eight-legged horse): the rider seated
  and carried by the mount, `holds: none`. `tools/mount_rig.js` finds the parts the page moves with travel (body, leg
  segments, hooves, tail, head, wings) in its drawing at 80 travel samples and `export_kits.js` gives each a bone;
  the bake moves them as the page does, except the legs: the page swings them by angle and its hooves slide 8–80 cm
  a step, so the bake plans a gait with the page's leg order and phases (a hoof down 60 % of the walk, 45 % of the
  run; the body sinks up to 7–8 % of a leg so the stride reaches) and re-solves each leg (two-bone IK) so a hoof on
  the ground stays put. Parts the page does not repeat over its stride (a tail swaying at half the rate, wings with
  their own beat) cross-fade over the last 30 % of the frames into the stride before, bone by bone in the parent's
  frame, so the loop closes. The other 11 mounts (legs that bend, wheels, mounts the page redraws with another face
  count, nothing moving) have no mount bones and no ride clip — `notBaked` says why — and stay still under the rider
  as before; the runtime moves the whole model.
- **Gear fit**: the page draws a gun along the line between the hands, a bow upright at the aim, a spear or blade
  along the action's own direction and turns a raised shield to face the blow; the kits bind that geometry rigidly to
  one joint. The bake matches the gear faces of each hand / forearm between the kit's rest build and the page's build
  of every frame and turns the joint by the best rigid fit (Horn) when it beats the joint's own turn clearly.

## 5. Measured (APP_VER 9.4 page, bake of 7 Oct)

Foot slide while planted (`test_anim_footslide.gd`, 240 samples/s, gate 15 mm): walk 0.20 mm, run 0.76 mm, starts /
stops ≤ 0.7 mm, turns ≤ 0.06 mm, idle 0.01 mm on the humanoid; walk 0.45 mm / run 1.7 mm on the page's walker
(scale 2.2); walk 2.6 mm on the biggest walker (scale 13); a 10 % wrong speed slides 57 mm (the gate has teeth).
Hooves (the horse proof): ride walk 0.15 mm, ride run 0.81 mm; the other 8 ride clips ≤ 0.95 mm; the horse 10 % too
slow slides 65 mm. Every ride clip loops with its last→first key step inside its own largest step between keys
(without the cross-fade the wings' seam was 0.55 m).

Against the page's own drawing of the same kit (per-face miss, `fidelity`): locomotion on the rifleman ≤ 1.6 mm RMS;
`fire*`, `bash*`, `bow`, `lob`, `cast`, the falls and flinches ≤ 1 mm; swings, thrusts, `twin`, `brace` 7–30 mm RMS
(a wrist that carries a spear turns its hand with it). Not faithful: `throw` and `hurl` (the page moves a javelin to
the other hand / shows a rock only during the throw: a rigid skin cannot), `zap`, `claw`, `stomp` (their kits crouch
or lean; a bare-rig clip loses that during the action), and kits the rigid skin cannot follow at all (parts the page
builds between two joints: the biggest walker's skin alone misses by 0.5 m RMS, whatever the clip).
