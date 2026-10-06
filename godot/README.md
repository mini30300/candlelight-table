# godot/ — the Godot 4 rewrite of Candlelight Table

The new app (Android + Windows) is being rebuilt in Godot 4.7 here, next to the old HTML pages in `app/`.
This folder is the seed: a probe scene, the test runner, the export presets and the CI workflow
(`.github/workflows/godot.yml`). The rules in the repo's `AGENTS.md` apply here too (no Games Workshop /
Gundam names, Thai UI with an English entry for every string, determinism, weak phones, secrets never in the repo).

## Layout

| Path | What |
| --- | --- |
| `project.godot` | Godot 4.7 project: renderer `gl_compatibility` on desktop and mobile, 1280×720, stretch `canvas_items`/`expand`, landscape, touch emulates the mouse |
| `scenes/probe.tscn` | main scene: 40×30 m table, sky + sun with shadows, orbit camera, a row of figures, the HUD |
| `scripts/i18n.gd` | `I18n`: Thai → English dictionary (keys are the Thai strings, like `BT_I18N` in the old page); `I18n.english`, `I18n.t("…")` |
| `scripts/kit_lineup.gd` | `KitLineup`: pure helpers that list, pick and space the kits (unit-tested) |
| `scripts/probe.gd`, `orbit_camera.gd`, `hud.gd` | the probe scene's scripts |
| `assets/fonts/` | Sarabun (SIL OFL, `OFL.txt`); it is the project theme's default font so Thai renders everywhere |
| `assets/theme/default_theme.tres` | the default Theme (`gui/theme/custom`) |
| `assets/shaders/table.gdshader` | procedural checker + noise table top (no textures) |
| `assets/kits/` | **generated, git-ignored**: `godot/tools/export_kits.js` exports every figure kit of the old page as `.glb` (312 files, 48 MB) plus `kits.json`; see below |
| `tools/` | `export_kits.js` (figures) and `export_data.js` (game data) — Node scripts that read the old page |
| `data/` | game data exported by `tools/export_data.js` |
| `tests/` | `run_tests.gd` (runner), `testing.gd` (assertions), `test_*.gd` (tests), `render_probe.gd` (screenshot), `out/` (git-ignored output) |
| `export_presets.cfg` | "Windows Desktop" (x86_64 .exe) and "Android" (APK, arm64-v8a + armeabi-v7a, min SDK 24 from the prebuilt template; `gradle_build/min_sdk` must stay empty unless Gradle builds are enabled); keystore fields are empty on purpose |

## Setup

1. Godot 4.7.1 (the standard editor binary; it also runs headless). CI downloads
   `Godot_v4.7.1-stable_linux.x86_64.zip` from the Godot GitHub releases. Below, `godot` is that binary.
2. The figure kits are not committed. Make them once (about 45 s; deterministic):
   ```bash
   cd tests && npm ci && npx playwright install chromium && cd ..      # once; the old page's test setup
   node godot/tools/export_kits.js                                      # writes godot/assets/kits/*.glb + kits.json
   ```
   On Claude Code on the web Playwright's Chromium may be missing: prefix the second command with
   `CHROMIUM_PATH=$(ls -d /opt/pw-browsers/chromium-*/chrome-linux*/chrome | head -1)`.
   Without the kits the probe scene shows 8 coloured boxes instead.
3. Import the assets (needed after a fresh checkout and whenever `assets/` changes; the editor does it on open):
   ```bash
   godot --headless --path godot --import
   ```

All commands run from the repository root.

## Tests

```bash
godot --headless --path godot -s tests/run_tests.gd              # all tests
godot --headless --path godot -s tests/run_tests.gd -- kit        # only scripts whose file name contains "kit"
```
The runner finds `tests/test_*.gd`; each is a script that `extends "res://tests/testing.gd"` and defines
`func test_*()` methods using `assert_true`, `assert_false`, `assert_eq`, `assert_ne`. It prints one `ok`/`FAIL` line per
assertion (like the Playwright suites in `tests/`) and exits with code 1 on any failure. A failing test is a bug to fix,
never a test to delete or loosen. Add tests for what you build.

## Render probe

```bash
timeout 120 xvfb-run -a -s "-screen 0 1280x720x24" godot --path godot --rendering-driver opengl3 \
  --resolution 1280x720 --audio-driver Dummy -s tests/render_probe.gd
```
Saves `godot/tests/out/probe.png` (Thai) and `probe_en.png` (after pressing ENGLISH) and prints the GPU name.
Look at the PNGs: the table, the light, the figures and the Thai text must be visible and the Thai must not be boxes.
ALSA / V-Sync warnings in the output are harmless. CI uploads the PNGs as the `godot-probe` artifact.

## Exports

Export templates must be installed first: unzip `Godot_v4.7.1-stable_export_templates.tpz` and put the content of its
`templates/` folder in `~/.local/share/godot/export_templates/4.7.1.stable/`.

```bash
godot --headless --path godot --export-release "Windows Desktop" "$PWD/dist-godot/windows/CandlelightTable.exe"
godot --headless --path godot --export-debug "Android" "$PWD/dist-godot/android/candlelight-godot-debug.apk"
```
`dist-godot/` is git-ignored. Android needs an Android SDK (platform-tools + build-tools), JDK 17 and a debug keystore,
configured in Godot's editor settings file `~/.config/godot/editor_settings-4.7.tres`
(`export/android/android_sdk_path`, `export/android/java_sdk_path`, `export/android/debug_keystore`,
`export/android/debug_keystore_user`, `export/android/debug_keystore_pass`); `.github/workflows/godot.yml` shows the
exact file. Release signing is not wired yet: the preset's `keystore/release*` fields stay empty and Godot then reads
`GODOT_ANDROID_KEYSTORE_RELEASE_PATH` / `_USER` / `_PASSWORD` from the environment — those will come from GitHub
secrets, never from the repo.

## CI

`.github/workflows/godot.yml` runs on every push and pull request that touches `godot/**` or the workflow:
`kits` (regenerates the figure kits and shares them as an artifact) → `test` (unit tests + render probe under Xvfb),
`windows` (release .exe) and `android` (debug APK). The Godot binary and the needed export templates are cached by version.

## Conventions

- GDScript with static typing (`var x: int`, `:=`, typed arguments and return types).
- Commit the `.import` and `.uid` files Godot writes next to assets and scripts (CI relies on them); `.godot/`, `tests/out/`
  and `assets/kits/*.glb` + `kits.json` are git-ignored.
- Short Thai comments in game code, like the rest of the repo; English is fine in tests, tools and docs.
- Every Thai UI string goes through `I18n.t()` and has an entry in `scripts/i18n.gd`; `tests/test_i18n.gd` checks that
  every string the HUD uses has an English entry with no Thai left in it.
- Rules code must be deterministic (seeded random only; no `randi()` without a seed, no wall-clock time).
- Keep per-frame work small: the lowest graphics level must stay fast on weak phones (`gl_compatibility`, no extra passes).
- Kits: the exporter already bakes each kit's `scale` into the mesh (figures stand at their true game height, titans are
  9–30 m), so instantiate the `.glb` scenes at scale 1 and use `baseR` from `kits.json` for spacing.
