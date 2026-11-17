#!/usr/bin/env bash
# สร้างทหารขั้นที่ 1 ใหม่ทั้งหมด: ปั้น (Python) -> ประกอบ Godot -> ภาพ -> แผ่นสรุป -> วัดสัดส่วน/ช่วงข้อ
#   bash src/run_all.sh            (ทั้งหมด ~25 นาทีบน 4 คอร์)
#   SKIP_BUILD=1 bash src/run_all.sh   (ใช้ผลปั้นเดิม ทำเฉพาะ Godot + ภาพ)
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PY=/usr/bin/python3
GODOT=/root/godot-bin/godot
cd "$ROOT/src/py"
if [ -z "${SKIP_BUILD:-}" ]; then
  nice -n 10 $PY build.py
fi
$PY measure.py
$PY limits_check.py
cd "$ROOT"
timeout 600 $GODOT --headless --path . -s res://src/gd/assemble.gd
mkdir -p out/renders/raw
OUT_DIR="$ROOT/out/renders/raw" timeout 1800 xvfb-run -a -s "-screen 0 640x960x24" $GODOT --path . --rendering-driver opengl3 \
  --fixed-fps 60 --resolution 640x960 --audio-driver Dummy -s res://src/gd/render.gd
$PY src/py/sheet.py
