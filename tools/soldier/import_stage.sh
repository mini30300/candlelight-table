#!/usr/bin/env bash
# Import one soldier stage into the game in a single step:
#   bash tools/soldier/import_stage.sh <stage_dir>                     # the base body -> godot/assets/figures/soldier/
#   bash tools/soldier/import_stage.sh --as soldier_f1 <stage_dir>     # another body -> godot/assets/figures/soldier_f1/
# --as <target> picks the asset folder (soldier or soldier_<id>, the folders SoldierFigure.folder() maps body ids to).
# The generator source is imported once: with the base body (only when it changed). Another body's import leaves
# tools/soldier/generator alone and only says when the stage's source differs from it; --source copies it anyway.
# <stage_dir> is a generator folder (tools/soldier/README.md): project.godot, src/ (py, gd, run_all.sh) and its build in
# out/godot/ (rig.tscn, skin.res, body_hi/mid/lo/min.res, optional body_crowd.res, soldier_skin.tres,
# optional wound shaders src/gd/soldier_skin_wound.gdshader + src/gd/wound.gdshaderinc, optional inner_bone.res +
# inner_flesh.res with src/gd/soldier_inner.gdshader, which need the wound shaders) and out/data/rig.json.
# The clip library never comes from a stage: a stage's clips.res (or soldier_clips.res, humanoid_soldier.res) is ignored
# and the base folder's clips.res (tools/soldier/bake_clips.sh, one library for all five bodies) is kept; when the stage
# changed the clip generator (src/py/gait.py, actions.py, clips_soldier.py, rig.py) the import says to re-run
# bake_clips.sh. Steps, and nothing in the repository changes unless the first two succeed:
#  1. Godot re-saves the stage's files in a scratch project, so every path inside them points at the game's copy:
#     godot/assets/figures/<target>/{rig.tscn, skin.res, body_<level>.res, body.gdshader, body_material.tres,
#     body_face.gdshader, body_wound.gdshader, wound.gdshaderinc, face.gdshaderinc, inner_bone.res, inner_flesh.res,
#     inner.gdshader, outfit_<name>_<level>.res (OUTFITS="uniform heavy" picks; default every outfit the stage built)};
#     rig.json's driver constants travel inside rig.tscn (metadata "soldier_rig"); existing UIDs are kept.
#  2. The stage's generator source is checked for the banned names of AGENTS.md rule 1.
#  3. Assets go to godot/assets/figures/<target>/ (files the stage no longer makes are removed) and, for the base body or
#     with --source, the source to tools/soldier/generator/ (the durable copy matches the assets), the game project is
#     re-imported and IMPORTED.txt records the stage, the body (out/data/variant.json), the levels and the hashes.
# Then run the tests listed in tools/soldier/README.md. Environment: GODOT (default ~/godot-bin/godot, then godot on PATH).
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"
TARGET=soldier
SYNC_SRC=""
STAGE=""
while [ $# -gt 0 ]; do
  case "$1" in
    --as) TARGET="${2:-}"; shift 2 ;;
    --source) SYNC_SRC=1; shift ;;
    -*) echo "unknown option $1" >&2; exit 2 ;;
    *) [ -z "$STAGE" ] || { echo "one stage at a time" >&2; exit 2; }; STAGE="$1"; shift ;;
  esac
done
[ -n "$STAGE" ] || { echo "usage: $0 [--as soldier|soldier_<id>] [--source] <stage_dir>" >&2; exit 2; }
[[ "$TARGET" =~ ^soldier(_[a-z][a-z0-9]{0,11})?$ ]] || { echo "--as takes soldier or soldier_<id> (got '$TARGET')" >&2; exit 2; }
[ "$TARGET" = soldier ] && SYNC_SRC=1
STAGE="$(cd "$STAGE" && pwd)"
if [ -z "${GODOT:-}" ]; then
  for c in "$HOME/godot-bin/godot" "$(command -v godot 2>/dev/null || true)"; do
    if [ -n "$c" ] && [ -x "$c" ]; then GODOT="$c"; break; fi
  done
fi
if [ -z "${GODOT:-}" ] || [ ! -x "$GODOT" ]; then echo "no Godot binary: set GODOT" >&2; exit 2; fi
PY=/usr/bin/python3
[ -x "$PY" ] || PY=python3
DEST="$REPO/godot/assets/figures/$TARGET"
GEN="$HERE/generator"
OUTG="$STAGE/out/godot"

for f in rig.tscn skin.res soldier_skin.tres body_hi.res body_mid.res body_lo.res body_min.res; do
  [ -f "$OUTG/$f" ] || { echo "missing $OUTG/$f" >&2; exit 1; }
done
for f in src/gd/soldier_skin.gdshader src/run_all.sh; do
  [ -f "$STAGE/$f" ] || { echo "missing $STAGE/$f" >&2; exit 1; }
done
# the face section (ใหม่ 0.14) is included by the face skin shader (hi/mid/lo; the plain one is min's) and the wound one
if grep -qs 'face.gdshaderinc' "$STAGE/src/gd/soldier_skin.gdshader" "$STAGE/src/gd/soldier_skin_face.gdshader" \
    && [ ! -f "$STAGE/src/gd/face.gdshaderinc" ]; then
  echo "missing $STAGE/src/gd/face.gdshaderinc (a skin shader includes it)" >&2; exit 1
fi
# the wound shaders are optional, but come as a pair (the skin shader includes the wound code)
if [ -f "$STAGE/src/gd/soldier_skin_wound.gdshader" ] || [ -f "$STAGE/src/gd/wound.gdshaderinc" ]; then
  for f in src/gd/soldier_skin_wound.gdshader src/gd/wound.gdshaderinc; do
    [ -f "$STAGE/$f" ] || { echo "missing $STAGE/$f (the wound shaders come as a pair)" >&2; exit 1; }
  done
fi
# the wound layers are optional, but come as a set: both meshes, their shader and the wound shaders
if [ -f "$OUTG/inner_bone.res" ] || [ -f "$OUTG/inner_flesh.res" ]; then
  for f in out/godot/inner_bone.res out/godot/inner_flesh.res src/gd/soldier_inner.gdshader \
      src/gd/soldier_skin_wound.gdshader src/gd/wound.gdshaderinc; do
    [ -f "$STAGE/$f" ] || { echo "missing $STAGE/$f (the inner layers come as a set)" >&2; exit 1; }
  done
fi

WORK="$(mktemp -d "${TMPDIR:-/tmp}/soldier_import.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/out/godot" "$WORK/out/data" "$WORK/src/gd" "$WORK/old"
for f in rig.tscn skin.res soldier_skin.tres body_hi.res body_mid.res body_lo.res body_min.res body_crowd.res \
    clips.res soldier_clips.res humanoid_soldier.res inner_bone.res inner_flesh.res; do
  # the clip library is never taken from a stage: it lives only in the base folder, made by tools/soldier/bake_clips.sh
  # (one library at S = 1, every body plays it with its motion_scale)
  case "$f" in clips.res|soldier_clips.res|humanoid_soldier.res)
    if [ -f "$OUTG/$f" ]; then echo "ignore the stage's $f (the clip library comes from tools/soldier/bake_clips.sh)"; fi
    continue ;;
  esac
  if [ -f "$OUTG/$f" ]; then cp "$OUTG/$f" "$WORK/out/godot/"; fi
done
# outfits (ใหม่ 0.14 item 4): every outfit the stage built (out/godot/outfit_<name>_<level>.res, all four levels), or only
# the ones in OUTFITS="uniform heavy"; they go next to the body's files and IMPORTED.txt records them
for f in "$OUTG"/outfit_*_hi.res; do
  [ -f "$f" ] || continue
  o="$(basename "$f" _hi.res)"; o="${o#outfit_}"
  if [ -n "${OUTFITS:-}" ] && [[ " $OUTFITS " != *" $o "* ]]; then continue; fi
  for lv in hi mid lo min; do
    [ -f "$OUTG/outfit_${o}_$lv.res" ] || { echo "missing $OUTG/outfit_${o}_$lv.res (an outfit comes with all four levels)" >&2; exit 1; }
    cp "$OUTG/outfit_${o}_$lv.res" "$WORK/out/godot/"
  done
done
for o in ${OUTFITS:-}; do
  [ -f "$WORK/out/godot/outfit_${o}_hi.res" ] || { echo "the stage has no outfit '$o' (build.py --outfit $o)" >&2; exit 1; }
done
if [ -f "$STAGE/out/data/rig.json" ]; then cp "$STAGE/out/data/rig.json" "$WORK/out/data/"; fi
# the body's closed-eyelid colour (face.json of build.py): kept as meta on body_material.tres
if [ -f "$STAGE/out/data/face.json" ]; then cp "$STAGE/out/data/face.json" "$WORK/out/data/"; fi
cp "$STAGE/src/gd/soldier_skin.gdshader" "$WORK/src/gd/"
for f in soldier_skin_face.gdshader soldier_skin_wound.gdshader wound.gdshaderinc face.gdshaderinc; do
  if [ -f "$STAGE/src/gd/$f" ]; then cp "$STAGE/src/gd/$f" "$WORK/src/gd/"; fi
done
if [ -f "$WORK/out/godot/inner_bone.res" ]; then cp "$STAGE/src/gd/soldier_inner.gdshader" "$WORK/src/gd/"; fi
# the game's current files: only their UIDs are read, so a re-import changes content, not identity
if [ -d "$DEST" ]; then
  for f in "$DEST"/*.res "$DEST"/*.tres "$DEST"/*.tscn; do
    if [ -f "$f" ]; then cp "$f" "$WORK/old/"; fi
  done
fi
cat > "$WORK/project.godot" <<'EOF'
config_version=5

[application]
config/name="soldier-import"

[rendering]
renderer/rendering_method="gl_compatibility"
renderer/rendering_method.mobile="gl_compatibility"
EOF
cp "$HERE/gd/import_stage.gd" "$WORK/import_stage.gd"

echo "== 1. re-save the stage's files with the game's paths ($TARGET) =="
SOLDIER_DST="res://assets/figures/$TARGET/" "$GODOT" --headless --path "$WORK" -s import_stage.gd 2>&1 \
  | grep -v -e '^Godot Engine' -e '^$' || true
[ -f "$WORK/report.json" ] || { echo "the Godot step failed (no report): nothing was changed" >&2; exit 1; }

echo "== 2. generator source: banned-name check =="
NEWGEN="$WORK/generator"
mkdir -p "$NEWGEN/src"
# every source file under src/ (new modules and sub-folders included), never caches
(cd "$STAGE/src" && find . -name __pycache__ -prune -o -type f \( -name '*.py' -o -name '*.gd' -o -name '*.gdshader' \
    -o -name '*.gdshaderinc' -o -name '*.sh' -o -name '*.json' -o -name '*.md' -o -name '*.txt' \) -print) | LC_ALL=C sort | while read -r f; do
  mkdir -p "$NEWGEN/src/$(dirname "$f")"
  cp "$STAGE/src/$f" "$NEWGEN/src/$f"
done
if [ -f "$STAGE/project.godot" ]; then cp "$STAGE/project.godot" "$NEWGEN/"; fi
"$PY" "$HERE/check_names.py" --fix-math "$NEWGEN" || { echo "banned names in the stage's source: nothing was changed" >&2; exit 1; }

echo "== 3. copy into the repository =="
mkdir -p "$DEST"
NEW="$WORK/assets/figures/$TARGET"
# files the new stage no longer makes (a crowd level, a clip copy) go; .uid sidecars of kept files stay
for f in "$DEST"/*; do
  [ -f "$f" ] || continue
  base="$(basename "$f")"
  case "$base" in
    *.uid|IMPORTED.txt) continue ;;
    # the base body keeps its clip library (it comes from tools/soldier/bake_clips.sh, never from a stage)
    clips.res) if [ "$TARGET" = soldier ]; then echo "keep clips.res (bake_clips.sh)"; continue; fi ;;
  esac
  if [ ! -f "$NEW/$base" ]; then echo "remove $base"; rm -f "$f" "$f.uid"; fi
done
cp "$NEW"/* "$DEST/"
# the game's drivers are a port (SoldierFigure): say when the stage changed the code they were ported from
for f in src/gd/soldier_figure.gd src/py/correctives.py src/py/rig.py; do
  if [ -f "$GEN/$f" ] && ! cmp -s "$GEN/$f" "$NEWGEN/$f"; then
    echo "note: the stage changed $f: compare it with godot/scenes/arena/soldier_figure.gd (helper_rule, shape_weights, still rules)"
  fi
done
# the clip library is kept as it is: say when the stage changed the code it is made from
for f in src/py/gait.py src/py/actions.py src/py/clips_soldier.py src/py/rig.py; do
  if [ -f "$GEN/$f" ] && ! cmp -s "$GEN/$f" "$NEWGEN/$f"; then
    echo "note: the stage changed $f: re-run tools/soldier/bake_clips.sh (clips.res was kept as it is)"
  fi
done
echo "assets -> $DEST"
# the generator source comes in once: unchanged = nothing to do; another body's stage never replaces it unless --source
# (another body's build folder has its own project.godot name: only src/ counts there)
if diff -rq "$GEN/src" "$NEWGEN/src" > /dev/null 2>&1 && { [ "$TARGET" != soldier ] || cmp -s "$GEN/project.godot" "$NEWGEN/project.godot"; }; then
  echo "source: tools/soldier/generator already matches the stage"
elif [ -n "$SYNC_SRC" ] && [ "$TARGET" = soldier ]; then
  rm -rf "$GEN"
  mkdir -p "$GEN"
  cp -r "$NEWGEN"/. "$GEN"/
  echo "source -> $GEN"
elif [ -n "$SYNC_SRC" ]; then
  rm -rf "$GEN/src"
  cp -r "$NEWGEN/src" "$GEN/src"
  echo "source (src/ only, the generator keeps its project.godot) -> $GEN"
else
  echo "note: the stage's source differs from tools/soldier/generator (left as it is; --source copies it)"
fi

echo "== import the game project =="
LOCK="$REPO/godot/.import.lock"
if command -v flock > /dev/null; then
  flock "$LOCK" "$GODOT" --headless --path "$REPO/godot" --import > "$WORK/import.log" 2>&1 || { tail -20 "$WORK/import.log"; exit 1; }
else
  "$GODOT" --headless --path "$REPO/godot" --import > "$WORK/import.log" 2>&1 || { tail -20 "$WORK/import.log"; exit 1; }
fi
if grep -q 'ERROR' "$WORK/import.log"; then grep 'ERROR' "$WORK/import.log" | head -10; fi

echo "== record =="
"$PY" - "$WORK/report.json" "$DEST" "$(basename "$STAGE")" "$STAGE/out/data/variant.json" <<'PY'
import hashlib, json, os, sys
rep = json.load(open(sys.argv[1]))
dest, stage = sys.argv[2], sys.argv[3]
lines = ["Soldier assets imported by tools/soldier/import_stage.sh from stage '%s'." % stage,
         "Do not edit these files by hand: change the generator (tools/soldier/generator) and import again."]
if os.path.exists(sys.argv[4]):
    v = json.load(open(sys.argv[4]))
    lines.append("body: %s (%s), stature %.2f m, k %.4f, S %.5f, head %.4f" % (v.get("variant", "?"), v.get("label_en", ""),
                 float(v.get("stature", 0)), float(v.get("k", 1)), float(v.get("S", 0)), float(v.get("head_k", 1))))
lines += ["", "level  surfaces  verts   tris  blend_shapes    bytes"]
for lv in ["hi", "mid", "lo", "min", "crowd"]:
    if lv in rep["levels"]:
        r = rep["levels"][lv]
        lines.append("%-6s %8d %6d %6d %13d %8d" % (lv, r["surfaces"], r["verts"], r["tris"], r["shapes"], r["bytes"]))
if rep.get("inner"):
    lines += ["", "wound layers (hi/mid, hidden until the first wound; depth = least depth under the hi / mid skin)"]
    for lv in ["bone", "flesh"]:
        r = rep["inner"][lv]
        dep = r.get("depth_mm", {})
        lines.append("%-6s %8d %6d %6d %13s %8d  depth %s" % (lv, r["surfaces"], r["verts"], r["tris"], "-", r["bytes"],
                     " / ".join("%.2f mm" % dep[k] for k in ("hi", "mid") if k in dep) or "-"))
    pj = os.path.join(os.path.dirname(sys.argv[4]), "inner_posed.json")
    if os.path.exists(pj):
        p = json.load(open(pj))
        f, li = p["flesh"], p["flesh"].get("lbs_inverted", {})
        lines.append("posed (%d frames of the game's clips, inner_posed.py; %s): flesh above the hi skin at most %.2f mm, "
                     "chest front %.2f mm, hips %.2f mm; where LBS turns the depth against the skin: %s"
                     % (p["frames"], p["gate"], max(f["max_mm"], 0.0), max(f["regions"]["chest_front"]["max_mm"], 0.0),
                        max(f["regions"]["hips"]["max_mm"], 0.0),
                        "none" if not li.get("verts") else "%d verts, at most %.2f mm" % (li["verts"], li["max_mm"])))
        b = p.get("bone")
        if b:
            # กระดูกโผล่พ้นผิวตามท่า: เชดเดอร์ชั้นในวาดได้ในวงรอบแผล (นอกรู) ถ้าแผลอยู่ตรงนั้น
            lines.append("posed bone above the hi skin (drawn only in the ring just outside a wound): chest front %.2f mm, "
                         "hips %.2f mm, worst %.2f mm (%s)" % (max(b["regions"]["chest_front"]["max_mm"], 0.0),
                         max(b["regions"]["hips"]["max_mm"], 0.0), max(b["max_mm"], 0.0), b["worst"].split(" vertex")[0]))
        g = p.get("G13")
        if g:
            # ใหม่ 0.14: หน้า (กระดูกหน้า CUSTOM1 รอยต่อปาก เปลือกตาปิด ท่าหน้า)
            lines.append("face (G13, inner_posed.py): %s" % ("PASS" if g.get("pass") else "FAIL: " + "; ".join(g.get("fails", []))))
if rep.get("outfits"):
    # ใหม่ 0.14 ข้อ 4: ชุด (เมชเดียวต่อระดับแทนผิว) + เกตของ build.py --outfit (outfit_<ชื่อ>.json)
    lines += ["", "outfits (one mesh per level in place of the skin, one draw; build.py --outfit, outfits.py)"]
    for o in sorted(rep["outfits"]):
        oj = os.path.join(os.path.dirname(sys.argv[4]), "outfit_%s.json" % o)
        j = json.load(open(oj)) if os.path.exists(oj) else {}
        lines.append("outfit %s (%s / %s)" % (o, j.get("label", "?"), j.get("label_en", "?")))
        for lv in ["hi", "mid", "lo", "min"]:
            r = rep["outfits"][o][lv]
            lines.append("%-6s %8d %6d %6d %13d %8d" % (lv, r["surfaces"], r["verts"], r["tris"], r["shapes"], r["bytes"]))
        if j:
            g = j["levels"]
            lines.append("gates (closed pieces, tris <= budget - 3 %%, symmetry, soles at y = 0 +- 1.5 mm, CUSTOM0): %s; pieces %s"
                         % ("PASS" if all(v["pass"] for lv in g for v in g[lv]["gates"].values()) else "FAIL",
                            " / ".join(str(len(g[lv]["gates"]["closed"]["pieces"])) for lv in ["hi", "mid", "lo", "min"])))
            p = j.get("posed", {}).get("levels", {})
            lines.append("posed (%s): skin above cloth at most %s mm, gear in the cloth at most %s mm: %s" % (
                ", ".join("%s %d frames" % (lv, p[lv]["frames"]) for lv in p),
                " / ".join("%.2f" % max(p[lv]["skin_above_cloth_max_mm"], 0.0) for lv in p),
                " / ".join("%.1f" % max(list(p[lv]["gear_in_cloth_mm"].values()) + [0.0]) for lv in p),
                "PASS" if j.get("posed", {}).get("pass") else "FAIL"))
lines += ["", "bones (%d): %s" % (len(rep["bones"]), " ".join(rep["bones"])), "motion_scale: %.4f" % rep["motion_scale"]]
lines.append("driver constants: %s" % ("from the stage's rig.json" if "drivers" in rep else "none (the figure's stage-1 defaults)"))
# the clip library is never imported: one clips.res in the base folder (bake_clips.sh) for all five bodies
if os.path.exists(os.path.join(os.path.dirname(os.path.normpath(dest)), "soldier", "clips.res")):
    lines.append("soldier clip library: assets/figures/soldier/clips.res (made by tools/soldier/bake_clips.sh, not by the stage)")
else:
    lines.append("soldier clip library: none (the figure uses assets/anim/humanoid.res with its wrists eased)")
lines += ["", "sha256:"]
for name in sorted(os.listdir(dest)):
    p = os.path.join(dest, name)
    if name.endswith((".uid", ".txt")) or not os.path.isfile(p):
        continue
    lines.append("  %s  %s  %d bytes" % (hashlib.sha256(open(p, "rb").read()).hexdigest(), name, os.path.getsize(p)))
open(os.path.join(dest, "IMPORTED.txt"), "w").write("\n".join(lines) + "\n")
print("\n".join(lines))
PY
echo
echo "done. Next: the tests in tools/soldier/README.md (bash godot/tests/run.sh soldier, then the render suites)"
