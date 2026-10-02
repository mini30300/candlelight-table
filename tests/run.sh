#!/usr/bin/env bash
# Run the battle table and desktop start page tests.
#   bash tests/run.sh            quick set (what CI runs on every pull request, about 15 minutes)
#   bash tests/run.sh full       everything: also long bot games, every army in English, effects and the older suites (about an hour)
#   bash tests/run.sh battle/english battle/net_sync:2     only these suites (":N" passes a scenario number)
# Environment:
#   PAGE=<path to a battle-table.html>   test another copy of the page (default: app/src/main/assets/battle-table.html)
#   CHROMIUM_PATH=<chrome binary>        use an already installed Chromium instead of Playwright's own
#   TEST_OUT=<folder>                    where logs and screenshots go (default: a new temporary folder)
# First time: cd tests && npm ci && npx playwright install chromium
set -u
cd "$(dirname "$0")"
MODE=${1:-quick}
export TEST_OUT=${TEST_OUT:-$(mktemp -d)}
mkdir -p "$TEST_OUT"

QUICK="battle/graphics_spectator battle/rules_armies battle/graphics_spectator_deploy battle/music battle/layout_panel
       battle/english battle/rules_data battle/ui_screens battle/net_sync:1 battle/net_sync_armies:1
       desktop/offline desktop/english"
FULL="$QUICK battle/net_sync:2 battle/net_sync:3 battle/net_sync_armies:2 battle/net_sync_armies:3
      battle/english_all_armies battle/fx_anims battle/smoke_bot_games $(ls battle/legacy/*.js | sed 's/\.js$//')"
case "$MODE" in
  quick) SUITES=$QUICK ;;
  full)  SUITES=$FULL ;;
  *)     SUITES="$*" ;;
esac

# the desktop start page is served over http, with the battle table next to it, like inside the app
DESK_PID=""
desk_up() {
  [ -n "$DESK_PID" ] && return
  mkdir -p "$TEST_OUT/dist"
  cp ../desktop/dist/index.html "$TEST_OUT/dist/index.html"
  cp "${PAGE:-../app/src/main/assets/battle-table.html}" "$TEST_OUT/dist/battle-table.html"
  python3 -m http.server "${DESK_PORT:-8766}" --bind 127.0.0.1 --directory "$TEST_OUT/dist" > "$TEST_OUT/http.log" 2>&1 &
  DESK_PID=$!
  for _ in $(seq 1 50); do curl -s -o /dev/null "http://127.0.0.1:${DESK_PORT:-8766}/index.html" && return; sleep 0.2; done
}
trap '[ -n "$DESK_PID" ] && kill "$DESK_PID" 2>/dev/null' EXIT

pass=0; fail=0; failed=""
: > "$TEST_OUT/summary.txt"
for s in $SUITES; do
  name=${s%%:*}; arg=""; [ "$name" != "$s" ] && arg=${s#*:}
  file=$name.js; [ -f "$file" ] || { echo "no such suite: $name"; fail=$((fail+1)); failed="$failed $s"; continue; }
  log="$TEST_OUT/$(echo "$s" | tr '/:' '__').log"
  limit=900; case "$name" in *smoke*|*fx_anims*|*english_all_armies*) limit=2400 ;; esac
  start=$(date +%s)
  if [ "${name%%/*}" = desktop ]; then desk_up; timeout "$limit" node "$file" "http://127.0.0.1:${DESK_PORT:-8766}" > "$log" 2>&1
  else timeout "$limit" node "$file" $arg > "$log" 2>&1; fi
  rc=$?
  secs=$(( $(date +%s) - start ))
  last=$(grep -v '^\s*$' "$log" | grep -v 'dbus\|handshake\|^\[pid' | tail -1 | cut -c1-140)
  if [ $rc -eq 0 ]; then pass=$((pass+1)); line="PASS  $s (${secs}s) :: $last"
  else fail=$((fail+1)); failed="$failed $s"; line="FAIL  $s (${secs}s, exit $rc) :: $last"; fi
  echo "$line" | tee -a "$TEST_OUT/summary.txt"
  if [ $rc -ne 0 ]; then   # show why right here (CI logs included), not only in the log file
    echo "----- last lines of $log -----"; grep -v '^\s*$' "$log" | grep -v 'dbus\|handshake\|^\[pid' | tail -40; echo "-----"
  fi
done
echo "$pass passed, $fail failed${failed:+ —$failed}   (logs: $TEST_OUT)" | tee -a "$TEST_OUT/summary.txt"
[ $fail -eq 0 ]
