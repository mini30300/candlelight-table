#!/usr/bin/env bash
# สร้างทหารขั้นที่ 1c ใหม่ทั้งหมด: ปั้น (Python) -> ผิวนิ่งเทียบไขมัน 0.8/1.0/1.3 -> วัด -> ชั้นในของแผล -> ประกอบ Godot -> ภาพ -> แผ่นสรุป -> เกต
#   bash src/run_all.sh                  (ทั้งหมด ~50 นาทีบน 4 คอร์)
#   FAT_LEVEL=1.0 bash src/run_all.sh    (ระดับไขมันของตัวหลัก ค่าเริ่ม 1.0 ; คูณความหนาไขมันและรัศมีเติมร่องทุกค่า)
#   SKIP_BUILD=1 bash src/run_all.sh     (ใช้ผลปั้นเดิม ทำเฉพาะ Godot + ภาพ + เกต)
#   SKIP_FAT=1 bash src/run_all.sh       (ไม่สร้างผิวเทียบระดับไขมัน)
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PY=/usr/bin/python3
GODOT=/root/godot-bin/godot
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
cd "$ROOT"
timeout 600 $GODOT --headless --path . -s res://src/gd/assemble.gd
timeout 300 $GODOT --headless --path . -s res://src/gd/assemble_inner.gd
mkdir -p out/renders/raw
OUT_DIR="$ROOT/out/renders/raw" timeout 2400 xvfb-run -a -s "-screen 0 640x960x24" $GODOT --path . --rendering-driver opengl3 \
  --fixed-fps 60 --resolution 640x960 --audio-driver Dummy -s res://src/gd/render.gd
$PY src/py/sheet.py
$PY src/py/gates.py
