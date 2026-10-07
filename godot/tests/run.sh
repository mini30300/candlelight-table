#!/bin/bash
# Test runner for the Godot app (mirrors tests/run.sh of the old pages). Run from anywhere:
#   bash godot/tests/run.sh            quick: import + unit tests (what CI runs on every PR)
#   bash godot/tests/run.sh full       quick + the render probe and the render tests under xvfb (tests/render/*.gd, PNGs in TEST_OUT)
#   bash godot/tests/run.sh <word>     only unit scripts whose path contains <word>, e.g. i18n or unit/core
# Environment:
#   GODOT     the Godot 4.7.1 binary (default: ~/godot-bin/godot, then `godot` on PATH)
#   TEST_OUT  output folder for logs and PNGs (default godot/tests/out)
# Exit code is non-zero on any failure. A failing test is a bug to fix, never a test to skip or loosen.
set -u
cd "$(dirname "$0")/../.." || exit 2            # the repository root; Godot gets --path godot

MODE="${1:-quick}"
if [ -z "${GODOT:-}" ]; then
  for c in "$HOME/godot-bin/godot" "$(command -v godot 2>/dev/null)"; do
    [ -n "$c" ] && [ -x "$c" ] && GODOT="$c" && break
  done
fi
if [ -z "${GODOT:-}" ] || [ ! -x "$GODOT" ]; then
  echo "FAIL  no Godot binary: set GODOT=/path/to/Godot_v4.7.1-stable_linux.x86_64 (see godot/README.md)" >&2
  exit 2
fi

TEST_OUT="${TEST_OUT:-godot/tests/out}"
case "$TEST_OUT" in /*) ;; *) TEST_OUT="$PWD/$TEST_OUT" ;; esac
export TEST_OUT
mkdir -p "$TEST_OUT"

echo "godot: $GODOT ($("$GODOT" --version 2>/dev/null | tail -1))"
echo "out:   $TEST_OUT"
status=0

echo "== import =="
if ! timeout 600 "$GODOT" --headless --path godot --import > "$TEST_OUT/import.log" 2>&1; then
  echo "FAIL  import (see $TEST_OUT/import.log)"; tail -20 "$TEST_OUT/import.log"; exit 1
fi
echo "ok    import"

echo "== unit =="
case "$MODE" in
  quick|full) FILTER=() ;;
  *) FILTER=(-- "$MODE") ;;
esac
timeout 900 "$GODOT" --headless --path godot -s tests/run_tests.gd "${FILTER[@]}" 2>&1 | tee "$TEST_OUT/unit.log"
rc=${PIPESTATUS[0]}
if [ "$rc" -ne 0 ]; then echo "FAIL  unit tests (exit $rc)"; status=1; fi

if [ "$MODE" = full ]; then
  echo "== render probe (xvfb + Mesa) =="
  if ! command -v xvfb-run > /dev/null; then
    echo "FAIL  xvfb-run not found (apt-get install xvfb libgl1-mesa-dri)"; status=1
  else
    rm -f "$TEST_OUT/probe.png" "$TEST_OUT/probe_en.png"
    timeout 300 xvfb-run -a -s "-screen 0 1280x720x24" "$GODOT" --path godot --rendering-driver opengl3 \
      --resolution 1280x720 --audio-driver Dummy -s tests/render_probe.gd 2>&1 | grep -v '^$' | tee "$TEST_OUT/render.log"
    rc=${PIPESTATUS[0]}
    if [ "$rc" -ne 0 ] || [ ! -s "$TEST_OUT/probe.png" ] || [ ! -s "$TEST_OUT/probe_en.png" ]; then
      echo "FAIL  render probe (exit $rc; see $TEST_OUT/render.log)"; status=1
    else
      echo "ok    render probe: $TEST_OUT/probe.png, probe_en.png"
    fi
    echo "== render tests (xvfb + Mesa) =="
    for suite in render/test_lineup render/test_budgets render/test_main_screens render/test_field_look render/test_army_screen render/test_anim_footslide; do
      name=$(basename "$suite")
      timeout 900 xvfb-run -a -s "-screen 0 1280x720x24" "$GODOT" --path godot --rendering-driver opengl3 \
        --resolution 1280x720 --audio-driver Dummy -s "tests/$suite.gd" 2>&1 | grep -v '^$' > "$TEST_OUT/$name.log"
      rc=${PIPESTATUS[0]}
      if [ "$rc" -ne 0 ] || ! grep -q '^PASS' "$TEST_OUT/$name.log"; then
        echo "FAIL  $name (exit $rc; see $TEST_OUT/$name.log)"; grep -E '^FAIL' "$TEST_OUT/$name.log" | head -20; status=1
      else
        echo "ok    $name: $(grep -E '^PASS' "$TEST_OUT/$name.log" | tail -1)"
      fi
    done
  fi
fi

if [ "$status" -eq 0 ]; then echo "PASS  $MODE"; else echo "FAIL  $MODE"; fi
exit $status
