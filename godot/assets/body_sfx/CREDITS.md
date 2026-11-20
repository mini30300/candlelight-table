# Body sounds: sources and licences

Footsteps and panting of the arena (0.14, item 1b). Made by `tools/sound/make_body_sfx.py`; do not edit the WAVs by hand.

## Footsteps (recorded): `step_boot_*`, `step_metal_*`

- Pack: "Footsteps Leather, Cloth, Armor" by HaelDB, https://opengameart.org/content/footsteps-leather-cloth-armor
- File: https://opengameart.org/sites/default/files/footsteps.zip (sha256 `94b5155d119d9378315c2b4457c00098d78a36f2a2c436d5145687d1d3bad257`)
- Licence: **CC0 1.0** (public domain dedication), https://creativecommons.org/publicdomain/zero/1.0/. The page lists OGA-BY 3.0, CC0; we use the pack under CC0.
- Licence checked on the page on 2026-11-19. CC0 needs no credit; we keep it for the record.
- Processing: ffmpeg to mono 32 kHz, 40 Hz high-pass, leading silence cut at -45 dBFS, at most 0.35 s,
  1 ms / 10 ms fades, peak -3 dBFS.

| File | Take in the pack | sha256 of the WAV |
| --- | --- | --- |
| `step_boot_0.wav` | `footsteps/step_lth1.ogg` | `d3d7397ca1b46b6ab899343eb7d736a6b3516e18fe2d4c68b9676cbd5358682b` |
| `step_boot_1.wav` | `footsteps/step_lth2.ogg` | `808aa2d241787120697a89d2b848fd993bb9e148d3cb1cfd191fd1fc81bf7891` |
| `step_boot_2.wav` | `footsteps/step_lth33.ogg` | `d3e157e43b873024595617865d59fd724138410fb33559783ced7d4ce30b911f` |
| `step_boot_3.wav` | `footsteps/step_lth4.ogg` | `665970e215698e15ee82ea7549400c8cdc448c4844585af096c65805f43720ca` |
| `step_metal_0.wav` | `footsteps/step_metal.ogg` | `4d7214ea74b8ba1b1d9ab4506a76e3f9116572d7aac7584aaf3aebac8f0bae78` |
| `step_metal_1.wav` | `footsteps/step_metal (2).ogg` | `fc043ee7cd764976958cc035fb38b58579f2a1222bf06ef194c66d1951432fe3` |
| `step_metal_2.wav` | `footsteps/step_metal (3).ogg` | `be0d98e402193286b8470117795cbb29f1bb2221d456199559adb9d6b60e2505` |
| `step_metal_3.wav` | `footsteps/step_metal (4).ogg` | `eaa109cca81194602ce598b70ebe9d70275de7851bce83ba896df4a841a0bf56` |

## Panting (synthesized): `pant_{in,out}_{soft,hard}_{low,high}_*`

- Made by the script from seeded white noise shaped by vocal-tract formants (low voice F1 600 / F2 1250 /
  F3 2600 Hz, high voice x1.18), soft and hard tiers, inhale and exhale, three takes each; the hard exhale adds
  a weak voiced "huh" (Rosenberg glottal pulses). No recordings, no third-party material.
- The spectral tilt was tuned so the octave bands follow the CC0 recording "Breathing Tired" by mikeask
  (https://opengameart.org/content/breathing-tired), used for measuring only; nothing of it is shipped.
