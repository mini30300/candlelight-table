# tests/data_fixtures — inputs for `tools/validate_data.py --fixtures` and `tools/gen_bt_data.py --self-test`

`python3 godot/tools/validate_data.py` runs these at the end of every lint run; `--fixtures` runs only them. Each
folder mimics the `godot/` layout (`data/`, `ui/`, `app/`) and is linted on its own with the real schemas from
`godot/data/schema/`.

| Fixture | Expected | What is planted |
| --- | --- | --- |
| `fail_banned_name/` | **fails** the banned-name scan | a GDScript constant carrying a name from AGENTS.md rule 1. The file is stored as `planted.gd.rot13` (ROT13), so the repository never contains the word itself; the runner decodes it into a temporary folder and scans that |
| `fail_float_dice/data/types.json` | **fails** the `unit.json` schema and the dice check | a gun with `"a": 2.5` (dice counts must be integers) |
| `fail_i18n_missing/` | **fails** the Thai → English check | `ui/screens/sample.gd` shows `"ยังไม่มีคำแปล"`, which is in neither `ui/i18n_extra.json` nor a page string |
| `fail_secret/` | **fails** the secrets guard | `notes.txt.rot13` decodes to a private-key header line (ROT13 for the same reason as above) |
| `ok/data/map_layout_sample.json` | passes `map_layout.json` | an 8×6 dungeon with every section filled (RLE runs add up to 48 cells; see docs/DATA.md) |
| `ok/data/monster_sample.json` | passes `monster.json` | a bestiary entry in the battle datasheet shape |
| `ok/ui/`, `ok/app/` | pass the Thai → English check and the name scan | Thai literals (plain, triple-quoted, with `{n}` and `%d` placeholders, joined fragments) that `ok/ui/i18n_extra.json` covers |
| `fake_worker.js` + `fake_worker.expected.json` | `gen_bt_data.py --self-test` passes | a tiny Worker with the real anchors (`const BT_RULES = 9;`, `const BT2 = {`, `const BT_ARMY_EN = {`, comma-joined constants), a one-line embedded page that must not win an anchor, bare and quoted keys, single quotes, trailing commas and comments inside the table |

Keep the numbers in the fixtures made up (they are not datasheets) and never put a real secret or a plain banned word
here: the `.rot13` files exist so the planted inputs stay unreadable at rest.
