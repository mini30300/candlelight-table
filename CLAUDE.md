@AGENTS.md

## Claude Code notes

- The rules, tests and the Claude ↔ Codex working agreement are in `AGENTS.md` (imported above); both agents follow it.
- On Claude Code on the web, Playwright's own Chromium may be missing: run the tests with
  `CHROMIUM_PATH=$(ls -d /opt/pw-browsers/chromium-*/chrome-linux*/chrome | head -1) bash tests/run.sh`.
- Open pull requests as drafts and watch them until CI is green; when Codex reviews a PR, answer every comment.
