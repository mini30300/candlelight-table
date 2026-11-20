# tools/sound — the arena's body sounds

`make_body_sfx.py` makes `godot/assets/body_sfx/` (0.14, item 1b): footsteps from the CC0 pack "Footsteps Leather,
Cloth, Armor" (HaelDB, OpenGameArt) and synthesized panting (two voices, soft and hard tiers, inhale and exhale,
three takes each). The outputs are committed; CI does not run it. It reads downloaded files, so run it with the system
Python in isolated mode, and give the download its own new, empty folder:

```bash
/usr/bin/python3 -I tools/sound/make_body_sfx.py --fetch /tmp/body_sfx_dl     # download (licence and sha256 checked) + build all
/usr/bin/python3 -I tools/sound/make_body_sfx.py --rebuild /tmp/body_sfx_dl   # build again from that folder
/usr/bin/python3 -I tools/sound/make_body_sfx.py --synth-steps                # no network: synthesized footsteps
/usr/bin/python3 -I tools/sound/make_body_sfx.py --check [--src /tmp/body_sfx_dl]
/usr/bin/python3 -I tools/sound/make_body_sfx.py --mix /tmp/body_mix.wav      # 10 s listening mix, checked numerically
/root/godot-bin/godot --headless --path godot --import                       # after a rebuild: the .import files
```

Needs numpy and scipy (ffmpeg for the download). If the pack cannot be downloaded or its page no longer offers CC0,
`--fetch` synthesizes the footsteps instead and says why in `CREDITS.md`. The build is deterministic (seeded noise):
`--check` compares a rebuild with the committed WAVs. Tests: `godot/tests/unit/test_body_sfx.gd`.
