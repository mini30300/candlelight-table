# tools/soldier — the infantry soldier: generator and import

The soldier is a public figure of the Godot app ("ทหารราบ (ทดลอง)" / "Infantry (preview)" in the dressing room,
`Figures` kind `builtin`). Its body is built offline in anatomical order (skeleton, then muscles, then skin) by the
deterministic generator in `generator/`, then imported into the game as baked Godot resources under
`godot/assets/figures/soldier/`. The game side is `godot/scenes/arena/soldier_figure.gd` (`SoldierFigure`).

Public CI has no generator run: the baked files are committed, and this folder is the only durable copy of the source.
Build folders (fields, renders, logs: hundreds of MB) always live outside the repository.

## Layout

| Path | What |
| --- | --- |
| `generator/` | The generator exactly as the imported stage had it: `project.godot` (a small gl_compatibility project), `src/py/*.py` (the Python pipeline), `src/gd/*.gd` + shaders (Godot assembly, renders, inspection and the viewer figure it renders with), `src/run_all.sh`; the import copies every source file under the stage's `src/` (`.py .gd .gdshader .sh .json .md .txt`, no caches) |
| `import_stage.sh <stage_dir>` | One command from a finished build folder to the game: re-saves the stage's Godot files with the game's paths, syncs `generator/` from the stage, re-imports the game project, writes `godot/assets/figures/soldier/IMPORTED.txt` |
| `new_stage.sh <empty_dir>` | Makes a build folder from `generator/` and fills its `ref/` with the game's generated inputs |
| `gd/import_stage.gd` | The Godot half of the import (run by `import_stage.sh` in a scratch project) |
| `gd/export_clips.gd` | Writes `clips.json` from `godot/assets/anim/humanoid.res` (the generator's pose input) |
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
```

`run_all.sh` runs `build.py` (skin, weights, correctives, export), `measure.py` (proportions), `limits_check.py`
(clips against joint limits), the Godot assembly (`out/godot/`), the renders and `sheet.py` (owner sheets with Thai
captions in `out/renders/`). Look at the sheets before importing.

To swap in a newer stage (for example a stage-1b folder another agent built): run `import_stage.sh <that folder>` and
then the tests below. The import refuses to touch the repository when a required file is missing, Godot cannot load
the stage's files, or the source holds a banned name. The game's drivers are a port, not a copy: when the stage changed
`src/gd/soldier_figure.gd`, `src/py/correctives.py` or `src/py/rig.py`, the import prints a note, and
`git diff tools/soldier/generator` shows what to carry over into `SoldierFigure` (`helper_rule`, `shape_weights`, the
still rules).

## Tests after an import

```bash
bash godot/tests/run.sh soldier                               # tests/unit/test_soldier.gd: contract, assets, clips, rules
bash godot/tests/run.sh figures                               # the registry
xvfb-run -a -s "-screen 0 1280x720x24" ~/godot-bin/godot --path godot --rendering-driver opengl3 --resolution 1280x720 \
  --audio-driver Dummy -s tests/render/test_soldier.gd        # in the game: budgets, foot slide, deck, arena, mission, card, English
```
Then the render suites that touch figures (`test_campaign_heroes`, `test_arena_figures`, `test_kit_walker`,
`test_dressing`, `test_dressing_palettes`, `test_hall`, `test_mission`, `test_anim_footslide`, `test_budgets`,
`test_lineup`) or simply `bash godot/tests/run.sh full`. The PNGs of `test_soldier.gd` (deck, arena, mission, hero card,
dressing room, the four levels) are the quickest look at a new body in the game.

## The contract between the generator and the game

`SoldierFigure` reads only what is listed here; anything else a stage adds is ignored or reported by the unit test.

| File (`out/godot/` of a stage → `godot/assets/figures/soldier/`) | Rule |
| --- | --- |
| `rig.tscn` | root Node3D > `Skeleton3D` (that name). The 23 game bones of `godot/assets/kits/CONTRACT.md` §1 with their exact names, parents and SKRIG offsets × S, in SKRIG frames, so every clip of `humanoid.res` plays unchanged; `motion_scale` = S (1.1125 for a 1.78 m man). Helper bones may follow (never between game bones). |
| helper bones | Driven by name in `mixer_applied` on hi/mid/lo: `clavicle<L/R>` (raised and pushed forward with the upper arm), `<joint>_half<L/R>` (half the turn of `<joint><L/R>`: elbow, knee, hip), a name containing `twist` under `shoulder<L/R>` (takes back half the upper-arm twist) or under `elbow<L/R>` (takes half the wrist-and-hand twist: a forearm twist helper). A helper with no rule stays at rest and `test_soldier.gd` fails with its name: add a rule to `SoldierFigure.helper_rule`. |
| `skin.res` | one named bind per bone (binds are matched by name) |
| `body_hi/mid/lo/min.res`, optional `body_crowd.res` | one surface each (one draw call); triangles within `SoldierFigure.BUDGET` (24k / 16k / 9k / 5k, crowd 1.5k); soles at y = 0; `min` and `crowd` skinned to the 23 game bones only (no per-frame work there); blend shapes only on hi/mid |
| blend shapes | named `shoulder_down`, `shoulder_front`, `shoulder_up`, `elbow_flex`, `knee_flex`, `hip_flex`, `hip_ext` + `L`/`R`, driven on hi/mid from the joint angles by the formulas of `src/py/correctives.py` (`SoldierFigure.shape_weights`); a weight under 0.05 is 0. Another name fails the unit test: port its formula into `shape_weights`. |
| `soldier_skin.tres` + `src/gd/soldier_skin.gdshader` | an unshaded material that computes its own light (uniforms `sun_dir`, `sun_colour`, `ambient_colour`, `per_vertex`), no `TIME`; the game copies it to `body.gdshader` / `body_material.tres` |
| `out/data/rig.json` | `drivers`, `keys`, `bind_angles`, `arm_keys`: the driver constants; the import stores them in `rig.tscn` (metadata `soldier_rig`) |
| optional `clips.res` | a soldier copy of the clips (an AnimationLibrary with `humanoid.res`'s clip names and metadata). Used as it is: tracks it has for helper bones or blend shapes are not driven again. Without it the figure copies the clips it uses from `humanoid.res` and eases their wrists (wrist and hand turn together, twist and bend each at most 45°, no hand position tracks) because the shared clips turn the hand up to 180° for the rigid kits' weapons, which tears a continuous skin. |

## What the game does with it

- Deck walker, arena and campaign player (`ArenaActors.player_figure`), the campaign's "normal" hero card and the
  dressing room's preview all use `SoldierFigure`. It is never the default figure and takes no colour schemes.
- Clips: idle / walk / run at playback rate = speed / (clip speed × S); fire = the upper body held from the `fire` clip
  at its first shot plus a 0.16 s kick; punch = `bash_*`, swing = `thrust_*` at 1.8×; hit = `flinch`; die =
  `die_back` / `die_fwd` / `die_spin`; no reload clip. A/D turn it (H9 false), backwards = walk reversed, dodge = a short
  lean (H8). Deck speeds = clip speed × S × 1.4.
- Levels: hi/mid helpers + correctives, lo helpers only, min nothing per frame and a still pose within 10 frames of
  stopping; as the deck figure also still on lo. Meshes, materials and clips are cached in static variables.
- The hero card lights it through `set_light` on its own material copy (`HeroLight.apply`).

## Sizes (stage 1b: fat layer, new face, olive training shorts)

`body_hi.res` 3.56 MB and `body_mid.res` 2.38 MB (14 uncompressed-float blend shapes each), `body_lo.res` 0.16 MB,
`body_min.res` 0.09 MB, rig, skin, shader and material 18 KB: about 6.2 MB, already zstd-compressed, so the APK and the
Windows build each grow by about 6.2 MB. `tests/unit/test_soldier.gd` fails above 6.5 MB (the 90 MB APK target).
Compressed vertex attributes or fewer shapes on mid are the next saving.

The shorts are vertex paint only (`mesh.colours`, `OLIVE` / `SHORTS_TOP` / `SHORTS_HEM`): a placeholder until the
uniform exists. Their edges fade over 16–22 mm because the hi mesh's triangles are about 15 mm wide there, and a
sharper edge breaks into a zigzag.
