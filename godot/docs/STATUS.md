# Where the game work stopped (9 Oct 2569)

The owner paused the game on 9 Oct to work on another project. Everything below is what a later session needs to pick up.

## On this branch (claude/new-session-fsucoo, draft PR #27), CI green
- R0 complete. R1 so far: `godot/docs/R1_PORT_SPEC.md` (the contract, waves 0–6, lead decisions at the end of §9),
  `core/battle/state.gd`, `core/field/*`, rules-core waves 1–2 (offsets, blocking, squads, strats, data exports, army,
  objectives, combat, abilities registry, moves), field look (V1), sample gothic ruin (V5, waiting for the owner's
  verdict before the full set), army picker (V4), 79 baked animation clips (V2). 2,097 unit checks, render suites,
  exported-game self-test (`windows-smoke`, also reproducible locally with a `--export-pack` + linux template).

## Done but not yet on this branch
- **Rule-1 fix of the old page (battle table 9.5)**: commit `ec4608f` on local branch `rule1-port`
  (worktree `.claude/worktrees/wf_563738c7-976-26`; same change as `cda0135`). Redesigns the confirmed marks:
  the secret giant mech's V antenna and V skirt mark, knb1's red saltire, the medic's red cross (now a white cross on
  green), the doom glyph; comments only for code-text names. The independent check step never ran (session limit):
  review it, re-run the page suites, then cherry-pick, and open the candlelight-server re-embed PR
  (`python3 embed.py`). Merge order then: candlelight-server first. Verdicts: workflow run `wf_563738c7-976` journal.

## 10 Oct: wave 3 landed
Pend queue + ability handlers, board + act codec, oracle harness (24 recordings, page hash), deploy speed (unit grid),
reviewed (one grid bug in spawn_from fixed). 2,569 unit checks. Open for wave 5: the dispatcher maps act t "" to no
match for targeted codes; Battle.make applies fixture units0 itself; the caller runs BtTurn.check_over after every
pend applier and prune. New log keys (atk_done, dice_short, shock_*, chg_*, heal_roll, rez_roll, wind_*, …) need I18n.

## Next steps, in order
1. Review and land the rule-1 fix (above) with its server PR.
2. Wave 4 (turn, roller + bot, net wire numbers) from `scratchpad/r1-core-waves-3-4.js`, then waves 5–6 (acts dispatcher + battle, goldens, smoke bots, perf, oracle green, `docs/GODOT.md`).
3. R1-V3: play the baked clips on the figures (AnimationTree), ruin full set after the owner approves the sample.
4. Owner gates: R0-H (APK GPU-check screenshot), ruin sample verdict, R7 collection design week.

## Budget rule agreed with the owner (8 Oct)
Run one workflow at a time (parallel runs hit the 5-hour limit and lose half-finished agents); Opus for builders.
Near the weekly reset the owner may say "use it all".
