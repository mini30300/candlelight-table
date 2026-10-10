# Kit contract — `assets/kits/*.glb` → imported figure scenes → impostors

What a kit file must contain, what the import turns it into, how the figure shader reads it, and how the baked
impostors are named. The files themselves are generated and git-ignored (`tools/export_kits.js` writes them; CI
rebuilds them from `battle-table.html`). Never hand-edit a kit; change the exporter, the import script or this contract.

## 1. The `.glb` the exporter writes (`tools/export_kits.js`)

One `<kit>.glb` per kit key of the page's `MINI.KITS` plus `kits.json`, the manifest.

- Units metres, +Y up, the figure faces **+Z**, its left is **+X**; the game's scale is baked into the mesh, so a
  kit is instantiated at scale 1. The figure stands on y = 0 (the base is not part of the kit).
- Geometry as the page builds it at full detail, standing still (`SKRIG.idlePose(0)` + `MINI.pose`), triangulated,
  **flat shaded**: every vertex carries its face normal; non-indexed.
- One glTF mesh with **one primitive per palette key**, each with its own material named after the key
  (`helm`, `plate`, `skin`, `gun` …) in first-seen order. `baseColorFactor` is the linear colour; `extras` carries
  `key`, `rgb` (the sRGB 0–255 colour from the page's `MINI.SOLID`) and `tint` (false for the NATURAL keys, see §4).
- **Skinned kits (260)**: a skin over the 23-joint humanoid rig, joint names and order = `SKRIG.J`
  (`pelvis, spine, chest, neck, head, shoulderL, elbowL, wristL, handL, shoulderR, elbowR, wristR, handR, hipL,
  kneeL, ankleL, toeL, heelL, hipR, kneeR, ankleR, toeR, heelR`), rigid weights (one joint per vertex, weight 1),
  node local rotations = the SKRIG local pose quaternions, so any SKRIG pose drives the bones. A mount carries the
  rider's seated skeleton (`MINI.riderPose`); the mount body is bound to `pelvis`. A mount whose legs are rigid chains
  the animation bake can re-solve (5 of the 16, kits.json `mountRig.gait`) also has a bone for every part the page
  moves with travel (body, leg segments, hooves, tail, head, wings), found by `tools/mount_rig.js`: named `mount_*`,
  after the 23, parents first under `pelvis`, rest rotation identity in the world; those parts are bound to them.
  The ride clips move them (assets/anim/CLIPS.md §4).
- **Rigid kits (52)**: no skin (vehicles, titans, most creatures). They get whole-mesh procedural motion until rigs
  arrive (`fly.json` has altitude/frequency for the flyers).

### `kits.json` fields used by the app

| field | meaning |
| --- | --- |
| `kits.<k>.file` | `<k>.glb` |
| `h`, `scale`, `kitScale` | the page's standing height before scale (1.75 m default), the kit's own scale and the type scale; the mesh is already scaled |
| `baseR` | base radius in metres for spacing (0.62 for infantry; from the type's `r`) |
| `bbox` | measured extent of the exported mesh `[[minx,miny,minz],[maxx,maxy,maxz]]` — the import must reproduce it |
| `skinned`, `joints` | whether a skin exists; 23 when it does, or 23 + the mount bones of a rigged mount |
| `mountRig` | mounts only: `gait` (the bake can re-solve the legs) or `why` not; `cycle` (the page's stride, metres of travel); `bones[]` `{name, parent, role, origin, worstMm, jointMm, faces}` in skeleton order after the 23 (empty when not `gait`); `legs[]` `{upper, lower, foot, hip, knee, end, contact, l1, l2, phase, amp, pole}` for the gait |
| `mount`, `hold`, `creature`, `fly` | the page's kit info: mount definition, what the hands hold, creature flag, flyer parameters |
| `materials[]` | `{key, rgb, tint}` in primitive order — **this order is the palette index** |
| `palette` | present when a variant borrows its base kit's palette (e.g. `knight_sword` → `knight`) |
| `type` | `{k, nm, fac, r, fly}` of the datasheet that uses the kit; `fac` is the army code |
| `natural` (top level) | the keys that are never offered for painting (skin, wood, metal, fire …) |

Scale sanity: for an ordinary figure the mesh height is within 50 % of `h × scale`; mounts and creatures may be up to
2× taller or 0.3× (rider on top, low scarab) — `tests/render/test_lineup.gd` checks both bands and the `bbox`.

## 2. What the import produces (`assets/kits_import/kit_post_import.gd`)

Applied to every `.glb` under `assets/kits/` through `[importer_defaults] scene` in `project.godot`
(`import_script/path`, `meshes/generate_lods=false`, `meshes/create_shadow_meshes=false`). The script only touches
files under `res://assets/kits/`; other scenes pass through unchanged. It prints one line per kit
(`kit_post_import <kit>: N surfaces -> 1, …`) so a `--import` log can be counted.

Imported scene (`load("res://assets/kits/<kit>.glb")`):

```
<kit>              Node3D   meta "kit" = {key, version, skinned, surfaces, verts_in, verts, tris, palette[], aabb[6]}
└─ Skeleton3D      (skinned kits only) 23 bones, names as above, rest pose = the exported idle pose (+ a rigged mount's own bones)
   └─ <kit>_mesh   MeshInstance3D, skin kept (one bind per bone), skeleton path "..", mesh = ArrayMesh with ONE surface
<kit>_mesh         (rigid kits) directly under the root
```

The one surface (`Mesh.PRIMITIVE_TRIANGLES`, indexed):

| array | content |
| --- | --- |
| `VERTEX`, `NORMAL` | positions and face normals; vertices are welded only when position, normal, palette slot and bone agree, so the flat shading is unchanged (≈ 35 % fewer vertices) |
| `COLOR` | the slot's palette colour, **sRGB** 0–1 (= `extras.rgb / 255`, the page's `MINI.SOLID`), RGBA8 |
| `CUSTOM0` | `RGBA_FLOAT` = `(paintable flag 0/1, palette index, 0, 0)`; the index is the material's position in `kits.json materials[]` (0 … 22) |
| `BONES`, `WEIGHTS` | skinned kits only, 4 per vertex as imported |

Rigid kits use `ARRAY_FLAG_COMPRESS_ATTRIBUTES` (16-bit positions/normals); skinned kits keep full precision.
Surface material = `res://assets/shaders/figure_material.tres` (one shared `ShaderMaterial` on `figure.gdshader`),
so a figure is **one draw call** and a thousand figures share one material. Materials from the glTF are discarded;
their keys, colours and flags live on in `meta.kit.palette` and in the vertex data.

Why `RGBA_FLOAT`: in Godot 4.7's Compatibility renderer a `RGBA8_UNORM` custom channel never reaches the vertex
shader and `RGBA_HALF` delivers only two components (measured under llvmpipe); float costs 16 bytes per vertex and works.

## 3. The figure shader (`assets/shaders/figure.gdshader`)

- Compatibility renderer only; `unshaded` with its own light: `ALBEDO = colour × (ambient_colour + sun_colour ×
  max(dot(N, sun_dir), 0))`, no specular. The Compatibility renderer displays `ALBEDO` as is (no linear→sRGB step,
  measured), so colours and light are computed in sRGB like the page. With `per_vertex = true` (lo/min) everything is
  evaluated in `vertex()`; because the kits are flat shaded this gives the same image as the per-pixel path, which
  exists for future smooth-shaded props. The uniforms `sun_dir` (world direction towards the sun), `sun_colour` and
  `ambient_colour` are set once by the table view.
- **Paint jobs** (the owner's model painter): `paint_tex` is a lookup texture, one **row per paint job**, one
  **column per palette index** (16 columns, nearest filtering, read with `texelFetch`, never bleeds between rows);
  texel alpha is the override strength (`0` = keep the model's own colour, `1` = replace it). The row comes from
  `paint_row` (an ordinary uniform: skinned figures use a duplicated material per paint job) or, with
  `use_instance_custom = true`, from `INSTANCE_CUSTOM.x` of a MultiMesh (`set_instance_custom_data(i, Color(row, 0, 0, 0))`).
  Row `< 0` means "unpainted", so the default material draws every kit in its own colours. Slots beyond the table's
  width clamp to the last column.
- **MultiMesh rule**: a MultiMesh of figures must set `use_colors = true` and give every instance `Color.WHITE`
  (`set_instance_color`). The Compatibility renderer multiplies the vertex `COLOR` by the instance colour, and with
  colours off and custom data on that colour is packed as zero — the figures come out black (measured; the test covers
  it). The instance colour is therefore also a free per-instance multiplier (highlight, fade).
- The **paintable flag** (`CUSTOM0.x`, `extras.tint`, `materials[].tint`) no longer dyes anything: it marks the slots
  a painter should offer by default (armour, cloth, trim …); NATURAL keys (skin, flesh, wood, steel, gold, bone, fire,
  fur …, the `natural` list) are flagged 0. A paint job may still override a slot with flag 0; the flag is UI guidance.
- Team identification is not done on the model: the team ring under the figure (`table/rings.gd`) carries the colour.
- `mask_out = true` outputs `(paintable flag, 1 − palette index / 32, 0)` instead of colour — used by the impostor
  bake. The index sits in the bright range on purpose: the Compatibility renderer's output curve crushes values near
  black (measured on llvmpipe: 8/255 → 2, 16 → 12, 32 → 30, 64 and above unchanged), so `index / 255` would not survive.

## 4. Impostors (`tools/bake_impostors.gd`, output `assets/impostors/`, git-ignored)

Per kit, two PNG strips of 16 columns × 2 rows of 64 × 64 px cells (`--cell` changes the size) and one manifest:

- `<kit>.png` RGBA8: colour with the default sun, alpha = coverage. Column *i* shows the figure from azimuth
  *i × 22.5°* measured from its front (+Z) towards its left (+X); row 0 from 20° above the horizon, row 1 from 50°
  (`pitches_deg` in the manifest). The figure is lit from the viewer's upper left in every cell.
- `<kit>_m.png` RGB8: R = paintable flag (255/0), G = 255 − 8 × palette index (`slot = round((255 − G) / 8)`),
  B = 0 — the same geometry, same cells, so a far-tier figure can still be recoloured per slot from a paint job.
- `impostors.json`: `cell`, `columns`, `rows`, `yaw_step_deg`, `pitches_deg` and per kit `size` (world units one
  cell covers: the diameter of the sphere around the kit's AABB) and `centre` (the figure-local point every cell is
  centred on). A billboard of `size × size` metres centred at the figure position + `centre` shows the strip's cell
  at the right scale for every facing.

The bake is deterministic (fixed scene, orthographic camera, no AA, llvmpipe) and runs under xvfb in about
0.2 s per kit. The runtime should read the PNGs with `Image.load()` when it builds the per-battle atlas; the texture
importer's VRAM compression would destroy the mask values.

## 5. Tests

`tests/render/test_lineup.gd` (xvfb): every kit loads, has one surface and the shared material, `COLOR` and float
`CUSTOM0` match `meta.kit.palette` and `kits.json`, skinned kits have 23 bones and 23 binds, rigid kits none, the AABB
equals the exporter's `bbox` and the height is in band; one `tests/out/lineup_<army>.png` per army with draw calls ≤
figures + 4; and a paint-job check where the same kit drawn with `paint_row = 0` / `INSTANCE_CUSTOM.x` differs from
the unpainted one. `tests/test_kit_lineup.gd` (unit) covers the manifest helpers.
