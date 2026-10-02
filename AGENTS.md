# AGENTS.md — candlelight-table

Instructions for AI coding agents on this repository. OpenAI Codex reads this file directly; Claude Code reads it
through `CLAUDE.md`. Two agents may work here side by side, given tasks by the owner (GitHub: mini30300).
The owner is not a programmer and reads Thai: explain results to them in plain Thai.

## The project

"Candlelight Table" (โต๊ะเทียน): a D&D table and a battle table (โต๊ะรบ) you play with friends, bots or Claude.
It lives in two repositories that ship together:

| Repo | What | Ships by |
| --- | --- | --- |
| **candlelight-table** (this one) | Android app (`app/`), Windows app (`desktop/`, Tauri), and the two big pages they bundle | merge to `main` → `.github/workflows/build.yml` builds the APK and .exe and publishes release `build-N` |
| **candlelight-server** | Cloudflare Worker `worker.js` (API, rooms, MCP tools for Claude) + web app `app.html` | merge to `main` → deploys automatically |

The big pages in this repo:
- `app/src/main/assets/battle-table.html` — the battle table: one self-contained file of about 35,600 lines (3.3 MB):
  canvas software-3D renderer, rigged figures, datasheets, 40k-style rules, bots, online rooms, sound, English mode.
  It also runs offline from `file://` (phone app, .exe).
- `app/src/main/assets/board.html` — the 3D board of the D&D table, loaded by the web app inside an iframe.

`docs/CODEMAP.md` maps both files with search anchors (grep for them; line numbers drift). Read it before editing.

## How a change ships

1. One task → one branch → one **draft** pull request. Never push to `main`. Agents never merge, approve or close PRs;
   the owner merges.
2. Changed `battle-table.html` or `board.html`? The server carries copies: in candlelight-server run `python3 embed.py`
   (it reads `../candlelight-table/app/src/main/assets/`) and open a PR there too. **Merge order: candlelight-server first,
   then candlelight-table.** Write the order in both PR descriptions.
3. User-visible change to the battle table → bump `var APP_VER = '9.4';` (9.4 → 9.5 …). Rules change that other devices
   must agree on → also the rules version and the server's gate (see CODEMAP); old clients must not silently disagree.
4. Every release gets a Thai note in `web/`, named like the latest one
   (`สิ่งที่เปลี่ยน-<วัน><เดือน>69-รุ่น<ver>-<หัวข้อสั้น>.md`): what changed in plain Thai, what was tested, merge order.

## Hard rules

1. **No Games Workshop / Warhammer names or iconography, and no Gundam names, logos or markings** — not in code, unit
   names, translations, comments, commits or PRs. Look-alike units get descriptive names ("Heavy Armour Knights",
   "Hound Titan", "Holy Walker"). Never use: Space Marine, Astartes, Tyranid, Necron, Ork (write Orc), T'au/Tau,
   Eldar/Aeldari, Drukhari, Chaos (as a faction), Khorne, Nurgle, Tzeentch, Slaanesh, Imperium, Primarch, Terminator,
   Dreadnought, Land Raider, Leman Russ, Carnifex, Warhound/Warlord/Reaver/Imperator (titan classes), Knight
   Castellan/Paladin/Warden, Crisis suit, Riptide, Stormsurge, Gundam or any mobile-suit name.
2. **Secrets never enter the repo, chats, PRs, issues or logs.** Signing keys and Cloudflare tokens live only in GitHub
   Actions secrets. Never ask the owner to paste a key; if a task needs one, stop and say which secret to set and where.
3. **Hidden units stay hidden.** Never write how a hidden or secret unit is unlocked in notes, PRs, issues or comments.
4. **Thai is the default.** Every new Thai UI string needs an English entry: battle table → the `BT_I18N` dictionary;
   board → `B_EN ? "English" : "ไทย"`; web app → `EN` in candlelight-server `app.html`. `tests/battle/english.js` fails if
   Thai is left on screen in English mode.
5. **Determinism.** Every device in a room must compute the same battle: seeded random only, no `Math.random()` or
   `Date.now()` in rules, unit rule positions (`gx`/`gz`) are authoritative. Visual-only differences are fine.
   `tests/battle/net_sync*.js` check this.
6. **Weak phones.** The lowest graphics level (`min`, "potato") must stay fast; add nothing per-frame to it.
7. **Edit the big files surgically**: exact, minimal replacements; never reformat, re-indent or re-order them.
8. Keep code comments short and in Thai, like the surrounding code. English is fine in tests and docs.

## Tests — run before every push

`tests/` holds Playwright suites (see `tests/README.md`). Once: `cd tests && npm ci && npx playwright install --with-deps chromium`.

```bash
bash tests/run.sh                 # quick set, ~15 min — CI runs the same on every pull request ("Tests" check)
bash tests/run.sh full            # everything, ~1 h — run it for rules, network or renderer changes
bash tests/run.sh battle/english  # one suite;  PAGE=<file> tests another copy of the page
```

If Playwright's own Chromium is missing, point `CHROMIUM_PATH` at any Chromium binary. A failing test is a bug to fix,
never a test to delete, skip or loosen; if behaviour changed on purpose, update the expectation in the same PR and say
why. Add checks for what you build. The Android app compiles in CI (`gradle assembleDebug`); the Windows app builds
on `windows-latest` only.

## Working alongside another agent (Claude ↔ Codex)

- **Branches**: Claude uses `claude/…`, Codex uses `codex/…`. One task per branch and PR.
- **Before you start**, list the open PRs in both repos. If one already changes the same area (e.g. both touching the
  rules section of `battle-table.html`), don't start a conflicting change: wait for it to merge, build on top of it, or
  ask the owner. Small, focused PRs conflict less.
- **Start from the latest `main`.** If `main` moves while your PR is open, merge `main` into your branch; never
  force-push or rebase a branch someone else may have checked out.
- **Talk through the PR.** The description says what changed, why, which files/areas, how it was tested and what is
  left (use the PR template). Leave a comment when you stop: done / not done / next step.
- **Review each other.** Either agent may be asked to review the other's PR. Treat review comments as bug reports:
  verify, then fix and push, or reply with the reason. Ask Codex for a review by commenting `@codex review`.
- Never rewrite, force-push or close the other agent's PR; propose changes in a review comment instead.

## Review guidelines

Codex uses this section when reviewing pull requests; Claude follows it too. Flag as **must fix**:
- a banned trademark name (rule 1), a secret or token (rule 2), how a hidden unit is unlocked (rule 3);
- new Thai UI text without an English entry, or English mode showing Thai;
- rules code that can differ between devices; a rules change without a rules-version bump;
- `battle-table.html` / `board.html` changed without a matching re-embed PR in candlelight-server;
- a user-visible change without an `APP_VER` bump or a Thai note;
- a deleted, skipped or loosened test; a new feature without a test;
- extra per-frame work on the lowest graphics level.
Not blocking: naming, comment wording, small refactors — mention them as suggestions.
