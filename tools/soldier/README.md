# tools/soldier — the infantry soldier: generator and import

The soldier is a public figure of the Godot app ("ทหารราบ (ทดลอง)" / "Infantry (preview)" in the dressing room,
`Figures` kind `builtin`). Its body is built offline in anatomical order (skeleton, then muscles, then skin) by the
deterministic generator in `generator/`, then imported into the game as baked Godot resources under
`godot/assets/figures/soldier/`. Four more bodies (two men, two women: "ทหารราบ ชาย 2/3 (ทดลอง)", "ทหารราบ หญิง 1/2
(ทดลอง)") come from the same generator (`variants.py`) and live in `godot/assets/figures/soldier_<id>/` (see
**Bodies** below). The game side is `godot/scenes/arena/soldier_figure.gd` (`SoldierFigure`).

Public CI has no generator run: the baked files are committed, and this folder is the only durable copy of the source.
Build folders (fields, renders, logs: hundreds of MB) always live outside the repository.

## Layout

| Path | What |
| --- | --- |
| `generator/` | The generator exactly as the imported stage had it: `project.godot` (a small gl_compatibility project), `src/py/*.py` (the Python pipeline), `src/gd/*.gd` + shaders (Godot assembly, renders, inspection and the viewer figure it renders with), `src/run_all.sh`; the import copies every source file under the stage's `src/` (`.py .gd .gdshader .sh .json .md .txt`, no caches) |
| `import_stage.sh [--as soldier_<id>] <stage_dir>` | One command from a finished build folder to the game: re-saves the stage's Godot files with the game's paths, syncs `generator/` from the stage (the base body only: another body's import leaves it alone unless `--source`), re-imports the game project, writes `godot/assets/figures/<target>/IMPORTED.txt`; `--as soldier_<id>` imports another body into its own folder |
| `new_stage.sh <empty_dir>` | Makes a build folder from `generator/` and fills its `ref/` with the game's generated inputs |
| `gd/import_stage.gd` | The Godot half of the import (run by `import_stage.sh` in a scratch project) |
| `gd/export_clips.gd` | Writes `clips.json` from `godot/assets/anim/humanoid.res` (the generator's pose input) |
| `bake_clips.sh` | The soldier's own clips (~15 s): `generator/src/py/clips_soldier.py` (`gait.py` + `actions.py`) makes 26 clips at S = 1 and runs their gates (foot slide on all 5 bodies, loops, joint limits, wrists, arms vs torso; falls: no pop before the thud, no bounce after it, limbs on the floor from 0.25 s after it; punches and cuts land ahead and end facing front; the aim at the shoulder; game timings, step rates), then `godot/tools/bake_anim.gd` bakes them unchanged into `godot/assets/figures/soldier/clips.res` (<= 1 MB). A failed gate bakes nothing; a failed bake or a file over 1 MB puts the old `clips.res` back. It lives here, not in `generator/`, because an import replaces `generator/` with the stage's copy. `STAGE=<build folder>` also copies the JSON to `<stage>/ref/soldier_clips.json` for `inner_posed.py` |
| `check_names.py` | The banned-name scan of AGENTS.md rule 1 over the generator source (the data lint only covers `godot/`) |

## Requirements

- `/usr/bin/python3` with numpy, scipy, scikit-image, trimesh, fast_simplification and Pillow (the `python3` on PATH in
  the agents' containers lacks them). No randomness: two builds give byte-identical `out/data/body_*.bin`.
- Godot 4.7.1 at `~/godot-bin/godot` (the scripts take `GODOT=...`; `src/run_all.sh` names `/root/godot-bin/godot`),
  `xvfb-run` for renders, and a Thai font at `/root/.fonts/THSarabunNew*.ttf` for the captioned sheets (`sheet.py`).
- The game's generated inputs: `bash godot/tools/kits.sh` (kits, `humanoid.res`, `clips.json`); `new_stage.sh` copies
  them into the build folder's `ref/`.

## Rebuild, check, import

```bash
bash tools/soldier/new_stage.sh /tmp/soldier_build            # outside the repository
bash /tmp/soldier_build/src/run_all.sh                        # ~25 min on 4 cores (SKIP_BUILD=1 redoes Godot + renders only)
#   or only the meshes: (cd /tmp/soldier_build/src/py && /usr/bin/python3 build.py --layers 0)   # ~4 min
bash tools/soldier/import_stage.sh /tmp/soldier_build         # into godot/assets/figures/soldier + generator/
# another body (variants.py: m2 m3 f1 f2), next to the build folder: <dir>/../f1, then into soldier_f1/
VARIANT=f1 bash /tmp/soldier_build/src/run_all.sh             # ~20 min (build, measure, wound layers, posed check, Godot, renders, gates)
bash tools/soldier/import_stage.sh --as soldier_f1 /tmp/f1
```

`run_all.sh` runs `build.py` (skin, weights, correctives, export), `measure.py` (proportions), `limits_check.py`
(clips against joint limits), `inner_layers.py` (the wound layers), the Godot assembly (`out/godot/`: `assemble.gd`,
then `assemble_inner.gd`), the renders and `sheet.py` (owner sheets with Thai captions in `out/renders/`). Look at the
sheets before importing. Only the wound layers again, in a few seconds, from a folder that has `work/stage_skin.npz`,
`work/stage_weights.npz`, `out/data/skeleton.bin` and `out/data/body_hi.bin` / `body_mid.bin`:
`(cd <stage>/src/py && /usr/bin/python3 inner_layers.py) && ~/godot-bin/godot --headless --path <stage> -s res://src/gd/assemble_inner.gd`
(another body: `inner_layers.py --out <dir>/out --work <dir>/work`, about 6 minutes with the posed push).
`inner_layers.py` checks every inner vertex against the hi and mid skin it will be drawn under (exact distance to the
closest triangle) and stops the build when flesh is less than 1 mm or bone less than 2 mm deep; it writes the least
depths into `out/data/inner_layers.json`, `assemble_inner.gd` stores them on the meshes (`depth_mm`) and the import
prints them in `IMPORTED.txt`. A build made before the body parts existed gets them without re-sculpting:
`(cd <stage>/src/py && /usr/bin/python3 bake_parts.py)` (byte for byte what the current `build.py` writes), then
`assemble.gd` and the two wound-layer steps. `inner_posed.py [--out DIR]` (about 3 minutes, `run_all.sh` runs it) poses
the hi skin and both layers through every 2nd frame of the soldier's clips (all 26 of `ref/soldier_clips.json` when the
stage has it: `new_stage.sh` writes it, `STAGE=<stage> bake_clips.sh` refreshes it; else the 15 humanoid clips with wrists eased as in the game; helpers driven) and measures each inner vertex against the posed skin of its own body part, skipping points a fold of
skin still covers (winding number): `out/data/inner_posed.json`, printed in `IMPORTED.txt`.

To swap in a newer stage (for example a stage-1b folder another agent built): run `import_stage.sh <that folder>` and
then the tests below. The import refuses to touch the repository when a required file is missing, Godot cannot load
the stage's files, or the source holds a banned name. The game's drivers are a port, not a copy: when the stage changed
`src/gd/soldier_figure.gd`, `src/py/correctives.py` or `src/py/rig.py`, the import prints a note, and
`git diff tools/soldier/generator` shows what to carry over into `SoldierFigure` (`helper_rule`, `shape_weights`, the
still rules).

## Tests after an import

```bash
bash godot/tests/run.sh soldier                               # tests/unit/test_soldier.gd + test_soldier_clips.gd + test_soldier_wounds.gd
bash godot/tests/run.sh figures                               # the registry
xvfb-run -a -s "-screen 0 1280x720x24" ~/godot-bin/godot --path godot --rendering-driver opengl3 --resolution 1280x720 \
  --audio-driver Dummy -s tests/render/test_soldier.gd        # in the game: budgets, foot slide, deck, arena, mission, card, English
```
Then `tests/render/test_soldier_wounds.gd` (the same way: flesh and bone in a chest wound on hi/mid with no background
through the hole, tint on lo, min unchanged, seven poses with nothing changed outside the wounds, a flank wound that
never cuts the arm in a run cycle, real hits and death in the arena) and the render suites that touch figures (`test_campaign_heroes`,
`test_arena_figures`, `test_kit_walker`, `test_dressing`, `test_dressing_palettes`, `test_hall`, `test_mission`,
`test_anim_footslide`, `test_budgets`, `test_lineup`) or simply `bash godot/tests/run.sh full`. The PNGs of `test_soldier.gd` (deck, arena, mission, hero card,
dressing room, the four levels) are the quickest look at a new body in the game. Both soldier suites also run every
other body: the unit tests check each `soldier_<id>/` folder against the same contract (its own S, no blend shapes, its
own wound layers under its own skin, the folder caps), and the render tests walk each body on the deck and in the
arena at its own S (`soldier_<id>_deck_*.png`, `_hero_*.png`, `_arena_hi.png`) and wound f1's chest
(`soldier_wound_f1_*.png`). A new body's names must fit its dressing-room button on one line at 1280 × 720 in Thai and
English (209 px at font size 19; `test_soldier.gd` measures every button, `soldier_dressing_names_<th|en>.png`); the
unit tests also read each other body's `IMPORTED.txt` for the posed bone check.

## The contract between the generator and the game

`SoldierFigure` reads only what is listed here; anything else a stage adds is ignored or reported by the unit test.

| File (`out/godot/` of a stage → `godot/assets/figures/soldier/`) | Rule |
| --- | --- |
| `rig.tscn` | root Node3D > `Skeleton3D` (that name). The 23 game bones of `godot/assets/kits/CONTRACT.md` §1 with their exact names, parents and SKRIG offsets × S, in SKRIG frames, so every clip of `humanoid.res` plays unchanged; `motion_scale` = S = stature / 1.6 (1.1125 for the 1.78 m base; every body has the base's 38 bones at the base offsets × its S ratio). Helper and face bones may follow (never between game bones). |
| helper bones | Driven by name in `mixer_applied` on hi/mid/lo: `clavicle<L/R>` (raised and pushed forward with the upper arm), `<joint>_half<L/R>` (half the turn of `<joint><L/R>`: elbow, knee, hip), a name containing `twist` under `shoulder<L/R>` (takes back half the upper-arm twist) or under `elbow<L/R>` (takes half the wrist-and-hand twist: a forearm twist helper). A helper with no rule stays at rest and `test_soldier.gd` fails with its name: add a rule to `SoldierFigure.helper_rule`. |
| face bones (ใหม่ 0.14) | `head_jaw`, `head_lipL/R`, `head_browL/R`: leaves under `head` (the `head_` prefix makes them body part 1), no clip tracks and no driver: the game moves them. `head_jaw` turns about its own +X (opens; ~1.7 mm at the lips per degree, 0-8°); the lip corners and brows move by translation in the head frame (lips ±3 / ±3 / ±2 mm, brows ±1.5 / -2.5..+4 mm, × the body's S ratio). Weighted on hi/mid only (from the `head` weight; lo/min/crowd keep it on `head`); the mandible of the wound bone layer rides `head_jaw`. `inner_posed.py` checks these ranges (`FACE_POSES`, gate G13). |
| `skin.res` | one named bind per bone (binds are matched by name) |
| `body_hi/mid/lo/min.res`, optional `body_crowd.res` | one surface each (one draw call); triangles within `SoldierFigure.BUDGET` (24k / 16k / 9k / 5k, crowd 1.5k); soles at y = 0; `min` and `crowd` skinned to the 23 game bones only (no per-frame work there); blend shapes only on hi/mid, and none at all on the other bodies (hi/mid run the helpers only); `CUSTOM1` (RGBA float) on hi/mid/lo only = face coordinates (`src/py/face.py`): eye u, eye v (the closed lid covers \|u\|, \|v\| <= 1), mouth x, mouth y (mouth corners at (±1, 0)); hi/mid carry the mouth seam (a second row of vertices 0.3 mm under the upper-lip row and a strip of triangles between them, which opens with the jaw), coded in eye u/v: upper row (16, 8), lower row (8, 16), corners (12, 12) |
| blend shapes | named `shoulder_down`, `shoulder_front`, `shoulder_up`, `elbow_flex`, `knee_flex`, `hip_flex`, `hip_ext` + `L`/`R`, driven on hi/mid from the joint angles by the formulas of `src/py/correctives.py` (`SoldierFigure.shape_weights`); a weight under 0.05 is 0. Another name fails the unit test: port its formula into `shape_weights`. |
| `soldier_skin.tres` + `src/gd/soldier_skin.gdshader` | an unshaded material that computes its own light (uniforms `sun_dir`, `sun_colour`, `ambient_colour`, `per_vertex`), no `TIME`, and no wound code or `discard` (the shared material of every soldier, min included); the game copies it to `body.gdshader` / `body_material.tres`. It has no face code either (min's shader); `src/gd/soldier_skin_face.gdshader` is the same skin plus the face (copied as `body_face.gdshader`, the shared hi/mid/lo material). The face skin and the wound skin include `src/gd/face.gdshaderinc` (copied as `face.gdshaderinc`): `face_on` (default off = the static face), the body's `face_lid_colour` (set in the material by `assemble.gd`), `face_mouth_colour`, `face_teeth_colour` and the per-figure `instance uniform vec4 face_state` (lids closing 0..1, extra lower-lid raise 0..1, painted mouth open 0..1, width -1..1); it paints after the light, never discards |
| body parts | `CUSTOM0.w` of every `body_<level>.res` vertex = its body part from its dominant bone (`src/py/parts.py`: 0 torso with the clavicles, 1 head and neck, 2/3 left/right arm, 4/5 left/right leg with `hip_half`/`knee_half`); `SoldierFigure.body_part` uses the same name rules (`test_soldier_wounds.gd` checks every vertex) |
| optional `src/gd/soldier_skin_wound.gdshader` + `src/gd/wound.gdshaderinc` (a pair) | the skin while wounded (the figure's own material on hi/mid/lo): the same uniforms and `skin_light()` as `soldier_skin.gdshader` plus the wound section, which lives once in `wound.gdshaderinc` (`#include "wound.gdshaderinc"`, a relative path, so the file keeps its name in the game); the game copies them to `body_wound.gdshader` / `wound.gdshaderinc`. Without the pair the figure takes no wounds |
| `out/data/rig.json` | `drivers`, `keys`, `bind_angles`, `arm_keys`: the driver constants; the import stores them in `rig.tscn` (metadata `soldier_rig`) |
| optional `inner_bone.res` + `inner_flesh.res` + `src/gd/soldier_inner.gdshader` (a set; needs the wound pair) | the wound layers (`inner_layers.py`, `assemble_inner.gd`): one surface each, bound to the binds of `skin.res`, `CUSTOM0.x` = the body part. Bone: the anatomical bone parts of `skeleton.bin` decimated per part to about 5k triangles, each part rigid on its own bone (one weight of 1; the clavicle and scapula ride `clavicle<L/R>`, the kneecap `knee_half<L/R>`), every vertex at least 2 mm under the hi and mid skin. Flesh: the sculpt decimated to 7k and inset by the fat map (3–16 mm), at least 1 mm under the hi and mid skin, weights from the hi/mid weights. Material on the inner shader (unshaded, own light, no `TIME`, includes `wound.gdshaderinc`) with the layer's values and `render_priority` 1 (drawn after the skin); meta `depth_mm` = the least depths; the game copies the shader to `inner.gdshader` |
| `clips.res` (from `bake_clips.sh`, never from a stage: `import_stage.sh` ignores a stage's clip files and keeps the base folder's `clips.res`; base folder only) | the soldier's own clips at S = 1, shared by every body (played with `motion_scale` = S): idle, walk, jog, run, turn_l/r, aim, fire, reload, punch_0..2, swing_0..2, hit_front/back/left/right, hit_heavy, die_back/fwd/spin/knees, die_min_back/fwd, tracks on the 23 game bones only (face bones stay free); metadata `kind`, `from`, `speed`, `turn`, `contact_l/r`, `events`. The figure maps requests from `kind`/`from`. Without it the figure copies the clips it uses from `humanoid.res` and eases their wrists (wrist and hand turn together, twist and bend each at most 45°, no hand position tracks) because the shared clips turn the hand up to 180° for the rigid kits' weapons, which tears a continuous skin. |

## What the game does with it

- Deck walker, arena and campaign player (`ArenaActors.player_figure`), the campaign's "normal" hero card and the
  dressing room's preview all use `SoldierFigure`. It is never the default figure and takes no colour schemes. Each
  body is its own `Figures.BUILTINS` entry (`soldier`, `soldier_m2`, `soldier_m3`, `soldier_f1`, `soldier_f2`);
  `Figures.make_builtin` sets the figure's `body_id` before `setup` (or `setup({"body": id})`), and the figure loads
  everything from `SoldierFigure.folder(id)`; an unknown id falls back to the base body.
- Clips (own `clips.res`, ใหม่ 0.14): walk / jog / run by rig speed (speed / S: walk < 2.0 <= jog < 3.6 <= run, 5 %
  hysteresis, the step phase kept) at rate = speed / (clip speed × S), so the arena's W (3 m/s) is a jog and Shift
  (5 m/s) a run; turning on the spot (A/D, mouse; player and enemy, not the deck, not min) steps `turn_l` / `turn_r` at
  yaw rate / 2.618 rad/s (clamped to 0.6–1.6×); fire = the upper body from `fire` key 0 (= `aim`) plus a 0.16 s kick; reload = the 1.6 s
  `reload` clip on the upper body over the current loop (returns 1.6; the arena's own timer is the lockout; not on min);
  punch_0..2 / swing_0..2 at rate 1.0 (shot at 0.12 / 0.18 s = the weapons' `active`); hit by the side `set_hit_from`
  gave (min: hit_front); die_back from the front, die_fwd from behind, die_spin from a side or a seeded die_knees; min
  falls with die_min_back / die_min_fwd (still from key 6). Deck speeds stay 1.61 / 4.0147 × S m/s (the old walk / run
  speed × S × 1.4: move speeds are gameplay); the own walk plays at 1.24× there, 127 steps/min. Without `clips.res`:
  idle / walk / run, `bash_*` / `thrust_*` at 1.8×, `flinch`, die_back/fwd/spin, no reload clip, deck speeds = clip
  speed × S × 1.4, as before. A/D turn it (H9 false), backwards = walk reversed, dodge = a short lean (H8).
- Levels: hi/mid helpers + correctives (the other bodies: helpers only), lo helpers only, min nothing per frame and a
  still pose within 10 frames of stopping; as the deck figure also still on lo. Rig, skin, materials, driver constants,
  S, helper rules, meshes, wound layers and wound spots are cached in static variables per body folder; the clips are
  shared. S is each rig's `motion_scale`, so playback rates and deck speeds follow each body's stature.
- The hero card lights it through `set_light` on its own material copy (`HeroLight.apply`).
- Wounds (visual only): `add_wound(bone, local_offset, radius)` cuts only the bone's body part; a hit adds one small
  seeded-random wound, death two or three larger ones, at most 8, cleared on `setup` and on the revive. Spots come
  from `body_lo` with the largest radius each takes (clear of the part seams; on a limb within 0.55 × the distance to
  the bone axis); `set_hit_from(world_dir)` puts the next hit's wounds on the side facing the attacker; three random
  numbers per wound on every level. hi/mid: the figure's own skin material on `body_wound.gdshader` cuts the skin
  (ragged edge, dark-red rim) and the wound layers show wet flesh, a thin fat band, bone and a lit deep-red cavity;
  lo: a red tint only; min: nothing, on the plain `body.gdshader`. The wound layers exist only after the first wound
  and are hidden without one (godot/docs/ARENA_SPEC.md §9.6).

## Sizes (ใหม่ 0.14: base body plus four bodies, with face coordinates)

The base (`soldier/`): `body_hi.res` 3.74 MB and `body_mid.res` 2.49 MB (14 uncompressed-float blend shapes each),
`body_lo.res` 0.22 MB, `body_min.res` 0.09 MB, the wound layers and rig, skin, shaders and material: 6.75 MB. The other
bodies have no blend shapes: 1.48-1.50 MB each with their own wound layers and shader copies (hi about 0.58 MB, mid
0.39 MB, lo 0.22 MB, min 0.09 MB). All five: 12.7 MB, already zstd-compressed, so the APK and the Windows build each grow
by about that. `CUSTOM1` (16 bytes per vertex on hi/mid/lo) is most of the growth over 0.13 (11.0 MB); half floats would
halve it.

The owner's app target is now 3 GB, but a GitHub release file may be at most 2 GiB, so CI fails an APK above 1900 MB
(`.github/workflows/godot.yml`, `godot/docs/ARCHITECTURE.md`). `tests/unit/test_soldier.gd` holds the soldier to a
small share of that: the base folder at most 10 MB (`BASE_CAP`), each other body at most 4 MB (`VARIANT_CAP`), all
soldier folders together at most 60 MB (`ALL_CAP`, about 3 % of the ceiling). Compressed vertex attributes or fewer
shapes on mid are still the next saving for the base.

## Bodies (`variants.py`, imported into `godot/assets/figures/soldier_<id>/`)

| id | dressing room (th / en) | build | S |
| --- | --- | --- | --- |
| m2 | ทหารราบ ชาย 2 (ทดลอง) / Infantry M2 (preview) | man 1.86 m, deep brown skin, black buzz cut, broad jaw, heavy build | 1.1625 |
| m3 | ทหารราบ ชาย 3 (ทดลอง) / Infantry M3 (preview) | man 1.70 m, light skin, short brown hair, long narrow face, wiry | 1.0625 |
| f1 | ทหารราบ หญิง 1 (ทดลอง) / Infantry W1 (preview) | woman 1.60 m, tan skin, Southeast Asian face, high bun, pear shape, khaki top | 1.0 |
| f2 | ทหารราบ หญิง 2 (ทดลอง) / Infantry W2 (preview) | woman 1.73 m, dark brown skin, curly hair, straight athletic build, sage top | 1.08125 |

Each is a named configuration in `generator/src/py/variants.py`; with no variant every hook is skipped, so the default
build still reproduces the base byte for byte (checked: every `body_*.bin`, both inner layers, `skeleton.bin`, the
muscle layers and the imported Godot files; `rig.tscn` differs only in Godot's node `unique_id`). `build.py --variant
<id>` scales the whole body by k = stature / 1.78 at export (the head by k^-0.6 more, so its real size goes as
k^0.4), exports no blend shapes and writes `out/data/variant.json`; `run_all.sh` with `VARIANT=<id>` builds in
`../<id>/` next to the generator folder (`src` and `ref` linked).

Wound layers of a body: `inner_layers.py` reads `variant.json`, insets the flesh by that body's own fat map (computed
before the head warp) plus the thickness of its pad pieces (breasts, slope pads, infraclavicular fat: up to 40 mm;
`FAT_HI_V`), scales it by k, checks it under the hi and mid skin like the base, then moves every flesh vertex that pokes
out of the posed hi skin in any clip frame (`inner_posed.push_posed`: each such frame is a linear constraint on the
move, solved by repeated projection, never through the other side of a thin part such as an ear). Since ใหม่ 0.14 every
body, the base included, is pushed and checked this way against the soldier's own 26 clips (`ref/soldier_clips.json`,
every 2nd frame) and the face poses (`FACE_POSES`); the flesh push runs up to three passes, each with a fresh 30 mm cap,
for the few armpit points that different clips pull in different directions. The posed check must then show no flesh
above the skin at the chest front and the hips, and at most 0.5 mm elsewhere; the armpit points where linear skinning
turns the depth against the skin cannot be fixed by moving the flesh and are reported apart (base: 2 vertices up to
0.86 mm; the other bodies: none). The inner layers are drawn only inside a wound of the same body part, and the armpit
has no wound spot. Rigid bone pieces (shoulder blade, collarbone) can come up through the skin by 12-17 mm in the
widest arm swings on every body; they too are drawn only inside a wound, but the inner shader also draws bone in a
ring just outside the hole (out to about 1.2-1.5 times the wound radius), so bone above the skin there shows over
unbroken skin while a wounded figure runs or punches. Posed bone at the chest front and the hips is therefore gated
on every body at no more than the base body + 0.5 mm (`inner_posed.py`: `BONE_BASE_MM` 0.817 / 6.332 mm, from the base
report of ใหม่ 0.14; `BONE_OVER_MM`), and `inner_layers.py` first pushes the rigid bone vertices of those two regions
that come up further than `BONE_PUSH_MM` (0.817 / 6.332 mm = the stage-1c base - 0.1 mm, fixed) in any clip frame down
in the bind pose (`inner_posed.push_bone`, the same solver as the flesh, at most 10 mm, still at least 2.5 mm under
the hi and mid skin; base 5 vertices up to 5.4 mm, m2 1 up to 0.1 mm, m3 6 up to 6.0 mm, f1 3 up to 4.0 mm, f2 7 up to
7.3 mm). Posed bone, chest front / hips / worst (mm): base 0.82 / 6.33 / 22.79, m2 0.82 / 0.54 / 25.29, m3 0.82 / 6.33 /
20.54, f1 0.82 / 1.02 / 18.06, f2 0.82 / 6.33 / 23.59 (printed in `IMPORTED.txt`; the worst values are the shoulder
blade in the widest swings and punches). The same check also runs the face poses: the head part's flesh and bone stay
under the skin with the jaw open 8° (the mandible pieces ride `head_jaw`), and gate G13 (`inner_posed.face_gate`)
checks the face itself (README contract rows above).

Stage 1c's abdominal grooves and navel also get a little vertex shade (`mesh.colours`: `CAV_K`, on lo `FAR_K`), because
the game's top light gives a vertical groove almost no shading.

The shorts are vertex paint only (`mesh.colours`, `OLIVE` / `SHORTS_TOP` / `SHORTS_HEM`): a placeholder until the
uniform exists. Their edges fade over 16–22 mm because the hi mesh's triangles are about 15 mm wide there, and a
sharper edge breaks into a zigzag.
