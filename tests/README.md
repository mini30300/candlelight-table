# Tests — battle table and desktop start page

Browser tests with Playwright + Chromium. They open `app/src/main/assets/battle-table.html` from disk (`file://`),
drive it through the `window.BT` test hook and the real buttons, and print one `ok` / `FAIL` line per check.
Every suite exits non-zero when a check fails.

## Run

```bash
cd tests && npm ci && npx playwright install --with-deps chromium   # once
bash tests/run.sh                 # quick set, about 15 minutes — the same as CI on every pull request
bash tests/run.sh full            # everything, about an hour
bash tests/run.sh battle/english battle/net_sync:2    # chosen suites (":N" = scenario number)
```

| Variable | Meaning |
| --- | --- |
| `PAGE` | test another copy of the page (default: the repo's `battle-table.html`) |
| `CHROMIUM_PATH` | use an installed Chromium instead of Playwright's own download |
| `TEST_OUT` | folder for logs, screenshots and `summary.txt` (default: a new temp folder) |

A single suite can also run alone: `node tests/battle/english.js [page]`.

## Suites

**Quick set (CI on every PR)**

| Suite | Checks |
| --- | --- |
| `battle/graphics_spectator` | lowest graphics level (button, fewer facets, step-down on slow phones, first-run guess), spectator mode as free play, the version label |
| `battle/rules_armies` | poison, designating, space elves shoot after advancing, dark elves from round 3, armies in datasheets and bot lists |
| `battle/graphics_spectator_deploy` | graphics setting remembered on every screen; spectator mode with the viewer placing each bot army |
| `battle/music` | music styles (mix / new / old) and the remembered choice |
| `battle/layout_panel` | side panel during a bot game: nothing overlaps on short desktops, tall screens and phones; the log stretches |
| `battle/english` | English mode: no Thai left on any screen through a whole bot game; the language switch; Thai mode unchanged |
| `battle/rules_data` | datasheets and rules data (fallen knights, chapter units, hidden units free of the budget), rules version, version label |
| `battle/ui_screens` | the army picker, each army's roster, no sideways scroll on desktop or phone, a bot game from the real start button |
| `battle/net_sync:1`, `battle/net_sync_armies:1` | two devices play one game: every act applied on the second device gives the same board (determinism) |
| `desktop/offline` | desktop start page: offline → battle table in a frame and back; online → straight to the server's /app |
| `desktop/english` | the desktop start page follows the language chosen in the battle table |

**Full set adds**

| Suite | Checks |
| --- | --- |
| `battle/net_sync:2..3`, `battle/net_sync_armies:2..3` | more two-device scenarios (objectives, longer games, other armies) |
| `battle/english_all_armies` | bot games covering all 15 armies in English: no Thai left anywhere |
| `battle/fx_anims` | attack animations, visual effects and sound effects (optional second argument: a reference page to compare against) |
| `battle/smoke_bot_games` | every figure builds at every detail level, every unit acts and walks, bots finish games with every army (long) |
| `battle/legacy/*` | 36 older suites from earlier rounds: rules v2–v6, dice tray, teams, clock, terrain, rooms, spectator, flight, sound, UI |

## When a test fails

A failing test is a bug to fix, not a test to delete or loosen. If behaviour changed on purpose, update the expectation
in the same pull request and say why in the PR description. Logs: `$TEST_OUT/<suite>.log`, summary: `$TEST_OUT/summary.txt`
(in CI: the `test-logs` artifact of the failed run).
