#!/usr/bin/env bash
# ชุดท่าของทหารเอง: สร้างคลิป + ตรวจเกต (generator/src/py/clips_soldier.py) แล้วอบเป็น AnimationLibrary ด้วยตัวอบเดิมของเกม
# (godot/tools/bake_anim.gd: ไม่แก้ ไม่ต้องมีตัวห่อ — JSON ตามรูปแบบ CLIPS.md §2) -> godot/assets/figures/soldier/clips.res
# ไฟล์เดียวที่ S = 1 อยู่ในโฟลเดอร์ร่างหลักเท่านั้น: ร่างทั้ง 5 เล่นด้วย motion_scale = S ของตัวเอง
# อยู่ที่ tools/soldier/ (ไม่ใช่ใน generator/: import_stage.sh เขียนทับ generator/ จากขั้นปั้น และ new_stage.sh คัดลอก generator/)
#   bash tools/soldier/bake_clips.sh                        (~15 วิ ; เกตไม่ผ่าน = ไม่อบ ไม่มีอะไรเปลี่ยน ;
#                                                            ไฟล์เกิน 1 MB = คืนไฟล์เดิม ไม่มีอะไรเปลี่ยน)
#   STAGE=<build folder> bash ...                           (คัดลอก JSON ไป <stage>/ref/soldier_clips.json ให้ inner_posed.py ด้วย)
# Environment: GODOT (ค่าเริ่ม ~/godot-bin/godot แล้ว godot บน PATH), REPO (ค่าเริ่ม: รากของ repo นี้),
# CLIPS_JSON (ที่เก็บ JSON, ค่าเริ่มนอก repo: ${TMPDIR:-/tmp}/soldier_clips/soldier_clips.json)
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="${REPO:-$(cd "$HERE/../.." && pwd)}"
[ -f "$REPO/godot/project.godot" ] || { echo "no game project at $REPO/godot: set REPO" >&2; exit 2; }
if [ -z "${GODOT:-}" ]; then
  for c in "$HOME/godot-bin/godot" "$(command -v godot 2>/dev/null || true)"; do
    if [ -n "$c" ] && [ -x "$c" ]; then GODOT="$c"; break; fi
  done
fi
[ -n "${GODOT:-}" ] && [ -x "$GODOT" ] || { echo "no Godot binary: set GODOT" >&2; exit 2; }
PY=/usr/bin/python3
[ -x "$PY" ] || PY=python3
OUT="${CLIPS_JSON:-${TMPDIR:-/tmp}/soldier_clips/soldier_clips.json}"
mkdir -p "$(dirname "$OUT")"
# เป็นพาธเต็ม: Godot รันโดยมี cwd = godot/ (--path) จึงหา --in แบบพาธสัมพัทธ์ไม่เจอ
OUT="$(cd "$(dirname "$OUT")" && pwd)/$(basename "$OUT")"
DEST=res://assets/figures/soldier/clips.res
RES="$REPO/godot/assets/figures/soldier/clips.res"
MAX_BYTES=1000000                         # เท่ากับ tests/unit/test_soldier_clips.gd (MAX_BYTES)

echo "== 1. clips + gates (generator/src/py/clips_soldier.py) =="
"$PY" -B "$HERE/generator/src/py/clips_soldier.py" --out "$OUT" --report "${OUT%.json}_gates.json"

echo "== 2. bake (godot/tools/bake_anim.gd) -> $DEST =="
LOG="$(mktemp "${TMPDIR:-/tmp}/bake_clips.XXXXXX")"
OLD="$(mktemp "${TMPDIR:-/tmp}/bake_clips_old.XXXXXX")"
HAD=0
if [ -f "$RES" ]; then cp "$RES" "$OLD"; HAD=1; fi
trap 'rm -f "$LOG" "$OLD"' EXIT
# อบที่ที่เดิม (uid ของไฟล์คงเดิม) ; ไม่ผ่าน = คืนไฟล์เดิม
restore() { if [ "$HAD" = 1 ]; then cp "$OLD" "$RES"; else rm -f "$RES"; fi; }
"$GODOT" --headless --path "$REPO/godot" -s tools/bake_anim.gd -- --in "$OUT" --out "$DEST" > "$LOG" 2>&1 || true
grep -v -e '^Godot Engine' -e '^$' "$LOG" || true
grep -q '^bake_anim: ' "$LOG" || { restore; echo "the bake failed (clips.res unchanged)" >&2; exit 1; }
BYTES=$(wc -c < "$RES")
echo "clips.res: $BYTES bytes (gate <= $MAX_BYTES)"
[ "$BYTES" -le "$MAX_BYTES" ] || { restore; echo "clips.res would be over 1 MB (kept the old file)" >&2; exit 1; }
if [ -n "${STAGE:-}" ]; then
  mkdir -p "$STAGE/ref"
  cp "$OUT" "$STAGE/ref/soldier_clips.json"
  echo "posed-check clip list -> $STAGE/ref/soldier_clips.json"
fi
echo "done. Next: the soldier tests (tools/soldier/README.md)"
