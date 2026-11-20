#!/usr/bin/env bash
# สร้างทหารขั้นที่ 1c ใหม่ทั้งหมด: ปั้น (Python) -> ผิวนิ่งเทียบไขมัน 0.8/1.0/1.3 -> วัด -> ชั้นในของแผล -> ประกอบ Godot -> ภาพ -> แผ่นสรุป -> เกต
#   bash src/run_all.sh                  (ทั้งหมด ~50 นาทีบน 4 คอร์)
#   FAT_LEVEL=1.0 bash src/run_all.sh    (ระดับไขมันของตัวหลัก ค่าเริ่ม 1.0 ; คูณความหนาไขมันและรัศมีเติมร่องทุกค่า)
#   SKIP_BUILD=1 bash src/run_all.sh     (ใช้ผลปั้นเดิม ทำเฉพาะ Godot + ภาพ + เกต)
#   SKIP_FAT=1 bash src/run_all.sh       (ไม่สร้างผิวเทียบระดับไขมัน)
#   VARIANT=f1 bash src/run_all.sh       (ร่างหลากหลาย variants.py: โฟลเดอร์ ../<VARIANT> ; ไม่มี blend shape ; ~12 นาที)
#   OUTFITS="uniform heavy" bash src/run_all.sh  (ชุด outfits.py: build.py --outfit ทีละชุดหลังตัวเปล่า + เกตท่า ~7 นาที/ชุด
#                                          -> outfit_<ชุด>_<ระดับ>.res + ภาพ out/renders/outfit_<ชุด>/ ; ใช้กับ VARIANT ได้)
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PY=/usr/bin/python3
GODOT=/root/godot-bin/godot
if [ -n "${VARIANT:-}" ]; then
  # ร่างหลากหลาย: โฟลเดอร์สร้างของร่าง = project.godot + src/ref ลิงก์ไปที่ตัวสร้างนี้ + out/ work/ ของตัวเอง
  VROOT="${VARIANT_ROOT:-$(dirname "$ROOT")/$VARIANT}"
  mkdir -p "$VROOT/out" "$VROOT/work"
  [ -e "$VROOT/src" ] || ln -s "$ROOT/src" "$VROOT/src"
  [ -e "$VROOT/ref" ] || ln -s "$ROOT/ref" "$VROOT/ref"
  [ -f "$VROOT/project.godot" ] || sed "s/^config\/name=.*/config\/name=\"soldier-$VARIANT\"/" "$ROOT/project.godot" > "$VROOT/project.godot"
  cd "$ROOT/src/py"
  if [ -z "${SKIP_BUILD:-}" ]; then
    nice -n 10 $PY build.py --variant "$VARIANT" --out "$VROOT/out" --work "$VROOT/work"
  fi
  $PY measure.py --variant "$VARIANT" ${VARIANT_ROOT:+--root "$VROOT"}
  $PY inner_layers.py --out "$VROOT/out" --work "$VROOT/work"   # ชั้นในของแผลของร่างนี้ (ไขมันของร่าง + pad, ส่วนสูง k)
  $PY inner_posed.py --out "$VROOT/out"                          # เนื้อไม่โผล่พ้นผิวในทุกท่าของเกม
  for o in ${OUTFITS:-}; do                                      # ชุด (ใหม่ 0.14): เมชชุด + เกต
    nice -n 10 $PY build.py --variant "$VARIANT" --outfit "$o" --out "$VROOT/out" --work "$VROOT/work"
  done
  cd "$VROOT"
  timeout 600 $GODOT --headless --path . -s res://src/gd/assemble.gd
  timeout 300 $GODOT --headless --path . -s res://src/gd/assemble_inner.gd
  mkdir -p out/renders/raw
  OUT_DIR="$VROOT/out/renders/raw" WHAT="turn budget" timeout 1200 xvfb-run -a -s "-screen 0 640x960x24" $GODOT --path . \
    --rendering-driver opengl3 --fixed-fps 60 --resolution 640x960 --audio-driver Dummy -s res://src/gd/render.gd
  K=$($PY -c "import json;print(json.load(open('$VROOT/out/data/variant.json'))['k'])")
  FIG_DIR="res://out/godot/" POSES="$VROOT/out/data/poses.json" K="$K" TAG="$VARIANT" OUT_DIR="$VROOT/out/renders/sheet" \
    timeout 900 xvfb-run -a -s "-screen 0 640x960x24" $GODOT --path . --rendering-driver opengl3 --resolution 640x960 \
    --audio-driver Dummy -s res://src/gd/vrender.gd
  for o in ${OUTFITS:-}; do
    OUTFIT="$o" FIG_DIR="res://out/godot/" POSES="$VROOT/out/data/poses.json" K="$K" TAG="${VARIANT}_$o" WHAT="main lod strip" \
      STRIP="$VROOT/out/data/outfit_strip.json" OUT_DIR="$VROOT/out/renders/outfit_$o" timeout 900 xvfb-run -a -s "-screen 0 640x960x24" \
      $GODOT --path . --rendering-driver opengl3 --resolution 640x960 --audio-driver Dummy -s res://src/gd/vrender.gd
  done
  cd "$ROOT/src/py"
  $PY gates.py --variant "$VARIANT" --out "$VROOT/out" --work "$VROOT/work"
  exit 0
fi
FAT="${FAT_LEVEL:-1.0}"
tag_of() { printf 'fat%03d' "$($PY -c "print(round(float('$1') * 100))")"; }
cd "$ROOT/src/py"
if [ -z "${SKIP_BUILD:-}" ]; then
  nice -n 10 $PY build.py --fat "$FAT"
  if [ -z "${SKIP_FAT:-}" ]; then
    for f in 0.8 1.0 1.3; do
      t=$(tag_of $f)
      if [ "$(tag_of "$FAT")" = "$t" ]; then
        $PY build.py --from weights --static "$t"                           # ใช้ผิวที่ปั้นแล้ว
      else
        nice -n 10 $PY build.py --fat $f --static "$t" --work "$ROOT/work/$t"
        rm -f "$ROOT/work/$t/stage_skin.npz"                                # ประหยัดดิสก์
      fi
    done
  fi
fi
$PY measure.py
$PY limits_check.py
$PY inner_layers.py                                 # ชั้นในของบาดแผล (เนื้อ/กระดูก) จาก skeleton.bin + ผิวปั้น
$PY inner_posed.py                                  # เนื้อไม่โผล่พ้นผิวในทุกท่าของเกม
for o in ${OUTFITS:-}; do                           # ชุด (ใหม่ 0.14): เมชชุด + เกต
  nice -n 10 $PY build.py --outfit "$o"
done
cd "$ROOT"
timeout 600 $GODOT --headless --path . -s res://src/gd/assemble.gd
timeout 300 $GODOT --headless --path . -s res://src/gd/assemble_inner.gd
mkdir -p out/renders/raw
OUT_DIR="$ROOT/out/renders/raw" timeout 2400 xvfb-run -a -s "-screen 0 640x960x24" $GODOT --path . --rendering-driver opengl3 \
  --fixed-fps 60 --resolution 640x960 --audio-driver Dummy -s res://src/gd/render.gd
for o in ${OUTFITS:-}; do
  OUTFIT="$o" FIG_DIR="res://out/godot/" POSES="$ROOT/out/data/poses.json" K=1 TAG="base_$o" WHAT="main lod strip" \
    STRIP="$ROOT/out/data/outfit_strip.json" OUT_DIR="$ROOT/out/renders/outfit_$o" timeout 900 xvfb-run -a -s "-screen 0 640x960x24" \
    $GODOT --path . --rendering-driver opengl3 --resolution 640x960 --audio-driver Dummy -s res://src/gd/vrender.gd
  $PY src/py/sheet.py --outfit "$o" --bodies base="$ROOT"
done
$PY src/py/sheet.py
$PY src/py/gates.py
