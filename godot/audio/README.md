# godot/audio — sound and music

The new app plays the old battle table's own sounds. The old page (`app/src/main/assets/battle-table.html`, `var SND`)
synthesizes everything with WebAudio; `godot/tools/bake_sfx.js` renders it offline through the page's test hook
`SND.probe` into WAV files. Nothing is committed: `bash godot/tools/kits.sh` (and CI's `kits` job) makes
`godot/assets/sfx/` — 42 kinds × 3 takes (`<kind>_<n>.wav`, 32 kHz mono), five music loops (`music/*.wav`, 24 kHz mono,
a `smpl` loop chunk so Godot imports them looping) and the manifest `sfx.json`. The project imports WAV as QOA
(`[importer_defaults] wav` in `project.godot`): 14 MB of WAV become about 3.2 MB in the export.

```bash
CHROMIUM_PATH=$(ls -d /opt/pw-browsers/chromium-*/chrome-linux*/chrome | head -1) node godot/tools/bake_sfx.js   # ~50 s
node godot/tools/bake_sfx.js --check        # validate an existing bake
```

## Sfx (autoload `/root/Sfx`, `audio/sfx.gd`)

| Call | What |
| --- | --- |
| `Sfx.play(kind: StringName, at = null, gain := 1.0, pitch := 1.0) -> bool` | one shot; `at` a `Vector3` world point (3D, panned and attenuated) or `null` (no direction). Returns true when it played (or would have, under the Dummy driver). |
| `Sfx.play_ui(kind)` | a screen sound on the UI bus |
| `Sfx.loop(kind, owner: Node, at = null) -> int` / `Sfx.stop_loop(id)` | a sound that repeats until stopped or until `owner` leaves the tree (e.g. `&"saw"` while a saw sword is held) |
| `Sfx.has(kind) -> bool` | the kind is baked |
| `Sfx.weapon_kind(fx_kind: String) -> StringName` | the old page's weapon → sound map: an FXS kind (`bolter`, `chain`, …) → `FXS[kind].snd`; a gun key from `FX_GUN` (`stormgun`, `lascan`, …) → its FXS kind's sound; an `LZ_SND` gun → `laser`; an `FX_SND` effect (`boom`, `vshield`, `wind`, `glow` → `heal`); unknown → `&""` |
| `Sfx.apply_settings()` | re-read `App.sfx_vol`, `App.mus_vol`, `App.snd` into the buses (the settings screen calls it) |

Kinds are the old page's `DEF` names exactly: `shot heavy laser zap flame bow bolt catapult throw swing hit clang boom
die dice charge saw vshield wind heal turn end bolter hbolter gatling sniper cannon rocket plasma melta beam warp chain
power hammer claw bite stomp quake ricochet debris ui`. As on the page, each kind has a minimum gap between two plays
(`gap` ms in `sfx.json`, e.g. shot 26 ms, end 3000 ms) and at most 22 sounds play at once; extra requests are dropped
(`Sfx.stats` counts played, dropped and asked). A take is picked at random (not seeded: sound is visual-only and never
feeds rules state). Every button in the app clicks (`ui`) through one `SceneTree.node_added` hook.

Where the page called `SND.at(kind, point, k)`, call `Sfx.play(kind, point, k)`. The page's mapping, for wiring battle
effects: shots → `Sfx.weapon_kind(fx)` or `laser`/`heavy`/`shot`; bows `bow`, throws `throw`, lobs `catapult`, bolts
`bolt`; a melee blow that hits → the weapon's sound or `hit`, a miss → `swing`; saves `clang` (saved) and `hit`
(failed); deaths `die` (k = 0.8 + 0.2 per model, at most 1.6); charge arrives `charge`; dice thrown `dice`; turn start
`turn`; game end `end`; machine wrecks `debris`; titan steps `stomp` / `quake`; flames `flame`, warp fire `warp`.

## Music (autoload `/root/Music`, `audio/music.gd`)

| Call | What |
| --- | --- |
| `Music.set_mood(mood: StringName)` | `&"menu"` (the page's older song, its menu style), `&"deck"` (the epic song at level 0), `&"battle"` (the epic song, levels 1–3), `&""` silence; crossfades over 1.2 s |
| `Music.set_intensity(x: float)` | a floor for the battle level: 0 → follow the fight only, 0.5 → at least level 2, 1 → level 3 (the page plays level 3 in the last round, at least 2 in the one before) |
| `Music.stop()` | same as `set_mood(&"")` |

The battle loops are rendered with the same chord picks bar by bar, so the three levels play in sync and the app swaps
between them at bar starts with the page's rules (up on an even bar, down one level every fourth bar). How fierce the
fight is comes from the sounds themselves, as on the page: every `Sfx.play` adds its kind's heat (die 3, charge 4,
boom 2.5, heavy 1.2, …; `heat` in `sfx.json`), fading over 6 s; above 8 → level 2, above 22 → level 3.
`_process` only runs during the battle mood.

## Buses and settings

`audio/bus_layout.tres` (`audio/buses/default_bus_layout`): Master (with the page's compressor: −16 dB, ratio 5),
Effects, Music, UI. Settings (`App`, saved in `user://settings.cfg`): `sfx_vol` (0..1, default 0.8 → Effects and UI),
`mus_vol` (0..1, default 0.6 → Music), `snd` (false = mute → Master muted). The settings screen has the rows
เสียงเอฟเฟกต์ / Sound effects (slider + ปิดเสียง / Mute) and เพลง / Music (slider).

Under the Dummy audio driver (headless tests) `quiet` is true: no players are made, but gaps, the voice cap, stats,
moods and levels work the same, so tests can check them.

Tests: `tests/unit/test_audio.gd` (manifest, imports, gap, voice cap, mute, loops, buses, settings round trip, heat and
levels, the button hook), `tests/flow/test_sound_flow.gd` (menu music, click, settings rows, English, deck music,
footsteps, station ping).
