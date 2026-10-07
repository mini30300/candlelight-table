# godot/ — โต๊ะเทียนรุ่นใหม่บน Godot 4

แอปใหม่ (Android + Windows) กำลังถูกสร้างขึ้นใหม่ด้วย Godot 4.7 ในโฟลเดอร์นี้ ข้าง ๆ หน้าเว็บเดิมใน `app/`
แบบแผนทั้งหมดอยู่ใน `docs/ARCHITECTURE.md` (ออกแบบอย่างไร เพราะอะไร) และ `docs/PLAN.md` (งานเป็นช่วง R0–R6)
แผนที่โค้ดสำหรับเอเจนต์คือ `../docs/GODOT.md` (อยู่ที่ไหน ใครดูแล ต้องรักษาอะไรไว้) กติกาของ repo ใน `AGENTS.md`
ใช้ที่นี่ด้วย (ห้ามชื่อ/โลโก้ของค่ายเกมอื่น, ข้อความไทยทุกข้อความต้องมีคู่อังกฤษ, คำนวณกติกาให้ตรงกันทุกเครื่อง,
มือถืออ่อนต้องลื่น, ความลับไม่เข้า repo)

## โครงสร้าง

| ที่ | คืออะไร |
| --- | --- |
| `project.godot` | โปรเจกต์ Godot 4.7: เรนเดอร์ `gl_compatibility` ทั้งเดสก์ท็อปและมือถือ, 1280×720 ยืดแบบ `canvas_items`/`expand`, แนวนอน, นิ้วแตะจำลองเป็นเมาส์; autoload ตามลำดับ `App`, `I18n`, `Log`, `Clock` |
| `app/app.gd` | `App`: ตั้งค่าของแอป (ระดับกราฟิก hi/mid/lo/min, ภาษา th/en, เสียง, URL เซิร์ฟเวอร์) ใน `user://settings.cfg` + ตัวสลับหน้าจอ (`push`/`pop`/`current`) + ปุ่มย้อนกลับ |
| `app/log.gd` | `Log`: เก็บล็อก 500 บรรทัดล่าสุด (`info`/`warn`/`error`, `dump()` สำหรับปุ่มคัดลอกล็อก) |
| `app/clock.gd` | `Clock`: นาฬิกาเดียวของตัวจับเวลาฝั่งภาพ (`now_ms()`, `frozen`, `step(ms)`; เทสหยุดเวลาแล้วเดินเองได้) |
| `ui/i18n.gd` | `I18n`: พจนานุกรมไทย → อังกฤษ (คีย์คือข้อความไทย เหมือน `BT_I18N` ของหน้าเก่า); `I18n.english`, `I18n.t("…")`; ค้นตามลำดับ `EN` ในสคริปต์ → `ui/i18n_extra.json` → `data/i18n_en.json` |
| `ui/i18n_extra.json` | คำอังกฤษของข้อความไทยที่มีเฉพาะในแอปใหม่ — ข้อความไทยใหม่ทุกข้อความต้องมีคู่ที่นี่ |
| `ui/theme/default_theme.tres` | ธีมหลัก (`gui/theme/custom`): ฟอนต์ Sarabun |
| `core/` | แกนกติกา: เลขคณิตจำนวนเต็ม (`fx.gd`), ตัวสุ่ม PCG32 (`rng.gd`), แฮช (`hash.gd`), บันทึกการกระทำ (`actlog.gd`), โครง `Table` และ `version.gd` — ห้ามมีทศนิยม ตรีโกณ หรือตัวสุ่มของเอนจิน (`tests/unit/test_core_purity.gd` ตรวจ) |
| `table/camera_rig.gd` | `CameraRig`: ลาก/สองนิ้วหมุนและซูม, ล้อเมาส์, WASD, ปรับให้พอดีโต๊ะ (กล้องร่วมของทั้งสองโต๊ะ) |
| `table/table_view.gd`, `terrain_mesh.gd`, `props_layer.gd`, `rings.gd`, `figures/figure_pool.gd` | ภาพสามมิติของโต๊ะรบ: พื้นสนาม อุปกรณ์ วงแหวนสีทีมใต้ตัวหมาก และชั้นของฟิกเกอร์ตามระดับกราฟิก (ตัวใกล้ขยับได้ ตัวไกลวาดรวมเป็นชุด) |
| `scenes/main.tscn` + `main.gd`, `scenes/battle_table.tscn` | ฉากหลักของแอป (โลก + หน้าจอ + ชั้นซ้อน) และฉากโต๊ะรบ; ครั้งแรกเดาระดับกราฟิกจากเครื่อง (มือถือ → lo) |
| `ui/screens/gpu_check.tscn` | หน้าตรวจเครื่อง: ชื่อการ์ดจอ เฟรม/วิ จำนวนวาด หน่วยความจำ เลือกระดับกราฟิก ทดสอบหนัก พิมพ์ชื่อไทย ปุ่มคัดลอกตัวเลข |
| `assets/kits_import/kit_post_import.gd`, `assets/shaders/figure.gdshader` | ตอนนำเข้า รวมชุดโมเดลแต่ละตัวเป็นชิ้นเดียว (สี + ช่องสีสำหรับเพ้นท์) และเชดเดอร์ของฟิกเกอร์ (ไม่ย้อมสีทีม สีทีมคือวงแหวน) — กติกาใน `assets/kits/CONTRACT.md` |
| `assets/impostors/` | **สร้างขึ้นเอง ไม่ commit**: `tools/bake_impostors.gd` อบภาพแทนระยะไกล 16 มุม × 2 ระดับต่อตัว |
| `table/figures/kit_library.gd` | `KitLibrary`: ฟังก์ชันล้วนที่หารายชื่อ เลือก และจัดแถวชุดโมเดล (มีเทส) |
| `scenes/probe/` | ฉากทดสอบ (`probe.tscn`, `probe.gd`, `hud.gd`): โต๊ะ 40×30 ม., ท้องฟ้า + แดดมีเงา, แถวฟิกเกอร์, HUD ภาษาไทย |
| `assets/fonts/` | Sarabun (SIL OFL, `OFL.txt`) เป็นฟอนต์เริ่มต้นของธีม ภาษาไทยจึงแสดงได้ทุกที่ |
| `assets/shaders/table.gdshader` | พื้นโต๊ะลายหมากรุก + noise (ไม่ใช้เท็กซ์เจอร์) |
| `assets/kits/` | **สร้างขึ้นเอง ไม่ commit**: `tools/export_kits.js` ส่งออกฟิกเกอร์ทุกชุดจากหน้าเก่าเป็น `.glb` (312 ไฟล์, 48 MB) + `kits.json` (ดูด้านล่าง) |
| `data/` | ตารางข้อมูลเกมที่ `tools/export_data.js` ส่งออกจากหน้าเก่า (`data/README.md` อธิบายทุกไฟล์) — ห้ามแก้ด้วยมือ |
| `tools/` | `export_kits.js` (ฟิกเกอร์), `export_data.js` (ข้อมูลเกม), `record_oracle.js` (อัดเกมอ้างอิงจากหน้าเก่า), `validate_data.py` (ตรวจข้อมูล ชื่อต้องห้าม คำแปล ลูกเต๋า), `gen_bt_data.py` (ไฟล์ให้เซิร์ฟเวอร์), `godot.sh` (ดาวน์โหลด Godot ตรวจลายเซ็น), `kits.sh` (สร้างชุดโมเดลและอบภาพ), `bake_impostors.gd` |
| `data/schema/` | JSON schema ของทุกตาราง + `legacy_tokens.sha1`; `data/version.json` ตราข้อมูล |
| `tests/` | `run.sh` (คำสั่งเดียวรันทั้งชุด), `run_tests.gd` (ตัวรัน), `testing.gd` (assert), `unit/test_*.gd` (เทสหน่วย), `render_probe.gd` + `render/` (เทสภาพผ่าน xvfb), `oracle/` (เกมอ้างอิง 20 เกม), `selftest.gd` (เทสในไฟล์ .exe ที่ส่งออก), `data_fixtures/` (ตัวอย่างสำหรับตัวตรวจข้อมูล), `out/` (ผลลัพธ์ ไม่ commit) |
| `export_presets.cfg` | "Windows Desktop" (.exe x86_64) และ "Android" (APK arm64-v8a + armeabi-v7a, min SDK 24; `gradle_build/min_sdk` ต้องว่างไว้จนกว่าจะเปิดใช้ Gradle); ช่อง keystore เว้นว่างไว้โดยตั้งใจ |
| `docs/` | `ARCHITECTURE.md` และ `PLAN.md` |

## เตรียมเครื่อง

1. Godot 4.7.1 (ตัว editor ปกติ รันแบบ headless ได้ด้วย) CI ดาวน์โหลด
   `Godot_v4.7.1-stable_linux.x86_64.zip` จาก GitHub releases ของ Godot ด้านล่างเรียกไบนารีนั้นว่า `godot`
   (วางไว้ที่ `~/godot-bin/godot` แล้ว `tests/run.sh` จะหาเจอเอง หรือชี้ด้วยตัวแปร `GODOT`)
2. ชุดโมเดลไม่ได้ commit ไว้ สร้างครั้งเดียว (ราว 45 วินาที ผลเหมือนกันทุกครั้ง):
   ```bash
   cd tests && npm ci && npx playwright install chromium && cd ..      # ครั้งเดียว; ชุดเทสของหน้าเก่า
   node godot/tools/export_kits.js                                      # เขียน godot/assets/kits/*.glb + kits.json
   ```
   บน Claude Code on the web อาจไม่มี Chromium ของ Playwright: ใส่
   `CHROMIUM_PATH=$(ls -d /opt/pw-browsers/chromium-*/chrome-linux*/chrome | head -1)` หน้าคำสั่งที่สอง
   ไม่มีชุดโมเดล ฉากทดสอบจะแสดงกล่องสี 8 ใบแทน
3. นำเข้า asset (ต้องทำหลัง checkout ใหม่และทุกครั้งที่ `assets/` เปลี่ยน; editor ทำให้เองตอนเปิด):
   ```bash
   godot --headless --path godot --import
   ```

ทุกคำสั่งรันจากรากของ repository

## เทส

```bash
bash godot/tests/run.sh                 # quick: นำเข้า + เทสหน่วย (CI รันชุดนี้ทุก PR)
bash godot/tests/run.sh full            # quick + เรนเดอร์ฉากทดสอบและเทสภาพทั้งสี่ชุดผ่าน xvfb (รูปอยู่ใน tests/out)
python3 godot/tools/validate_data.py    # ตรวจข้อมูล ชื่อต้องห้าม คำแปลอังกฤษ ลูกเต๋า (CI รันทุก PR)
bash godot/tests/run.sh i18n            # เฉพาะเทสที่ path มีคำนี้ (เช่น i18n, unit/core)
GODOT=/path/to/godot TEST_OUT=/tmp/out bash godot/tests/run.sh   # เลือกไบนารีและโฟลเดอร์ผลลัพธ์ (ค่าเริ่มต้น godot/tests/out)

godot --headless --path godot -s tests/run_tests.gd              # ตัวรันโดยตรง: เทสทั้งหมด
godot --headless --path godot -s tests/run_tests.gd -- kit       # เฉพาะสคริปต์ที่ path มีคำว่า "kit"
```
ตัวรันหา `tests/unit/**/test_*.gd` (ทุกโฟลเดอร์ย่อย) และ `tests/golden/test_golden.gd` ถ้ามี; เทสแต่ละไฟล์
`extends "res://tests/testing.gd"` และมีเมธอด `func test_*()` ที่ใช้ `assert_true`, `assert_false`, `assert_eq`, `assert_ne`,
`assert_within` (ทศนิยม), `assert_digest` (ข้อความ digest) พิมพ์ `ok`/`FAIL` หนึ่งบรรทัดต่อหนึ่งข้อ (เหมือนชุด Playwright
ใน `tests/`) และออกด้วยโค้ด 1 เมื่อมีข้อใดพลาด autoload ทั้งสี่ใช้ได้ในเทส (ตัวรันเริ่มเทสที่เฟรมแรก หลัง `_ready()` ของ
autoload) เทสที่พลาดคือบั๊กที่ต้องแก้ ไม่ใช่เทสที่ต้องลบหรือผ่อน ทำอะไรก็เพิ่มเทสของสิ่งนั้น

## เรนเดอร์ฉากทดสอบ

```bash
timeout 180 xvfb-run -a -s "-screen 0 1280x720x24" godot --path godot --rendering-driver opengl3 \
  --resolution 1280x720 --audio-driver Dummy -s tests/render_probe.gd
```
บันทึก `godot/tests/out/probe.png` (ไทย) และ `probe_en.png` (หลังกดปุ่ม ENGLISH) และพิมพ์ชื่อการ์ดจอ
(`TEST_OUT` เปลี่ยนโฟลเดอร์ได้) เปิดดูรูปทุกครั้ง: ต้องเห็นโต๊ะ แสง ฟิกเกอร์ และข้อความไทยที่ไม่เป็นกล่องสี่เหลี่ยม
คำเตือน ALSA / V-Sync ไม่เป็นไร CI อัปโหลดรูปทั้งหมดเป็น artifact ชื่อ `godot-probe`

เทสภาพอีกสี่ชุดรันด้วยคำสั่งเดียวกันโดยเปลี่ยนสคริปต์เป็น `tests/render/test_lineup.gd` (ทุกชุดโมเดลนำเข้าถูก
และหนึ่งตัวใช้หนึ่งคำสั่งวาด), `tests/render/test_budgets.gd` (งบวาดต่อระดับกราฟิกบนฉาก 400 ตัว ทั้งสนามเริ่มต้นและสนามที่ของ
เต็มเพดาน 480 ชิ้น — ด่านของกติกาข้อ 6), `tests/render/test_main_screens.gd` (หน้าหลักและหน้าตรวจเครื่อง ไทย/อังกฤษ)
และ `tests/render/test_field_look.gd` (สนามจากกติกาทุกฉาก x ภูมิประเทศ 16 รูป `field_<ฉาก>_<ภูมิประเทศ>.png` + ท้องฟ้า
ต่อฉาก: ของที่วาดครบตามกติกา ความสูงพื้นตรงกับกติกา) `run.sh full` รันให้ทั้งหมด

## ส่งออก (export)

ต้องติดตั้ง export templates ก่อน: แตก `Godot_v4.7.1-stable_export_templates.tpz` แล้ววางเนื้อหาในโฟลเดอร์ `templates/`
ไว้ที่ `~/.local/share/godot/export_templates/4.7.1.stable/`

```bash
godot --headless --path godot --export-release "Windows Desktop" "$PWD/dist-godot/windows/CandlelightTable.exe"
godot --headless --path godot --export-debug "Android" "$PWD/dist-godot/android/candlelight-godot-debug.apk"
```
`dist-godot/` ไม่ commit Android ต้องมี Android SDK (platform-tools + build-tools), JDK 17 และ debug keystore
ตั้งค่าในไฟล์ editor settings ของ Godot `~/.config/godot/editor_settings-4.7.tres`
(`export/android/android_sdk_path`, `export/android/java_sdk_path`, `export/android/debug_keystore`,
`export/android/debug_keystore_user`, `export/android/debug_keystore_pass`); `.github/workflows/godot.yml` แสดงไฟล์จริง
การเซ็นรุ่นจริงยังไม่ต่อ: ช่อง `keystore/release*` ใน preset ว่างไว้ Godot จึงอ่าน
`GODOT_ANDROID_KEYSTORE_RELEASE_PATH` / `_USER` / `_PASSWORD` จาก environment แทน — ค่าเหล่านี้มาจาก GitHub secrets
เท่านั้น ไม่มีวันอยู่ใน repo

## CI

`.github/workflows/godot.yml` รันทุก push และ pull request ที่แตะ `godot/**` หรือตัว workflow:
`kits` (สร้างชุดโมเดลใหม่แล้วส่งต่อเป็น artifact) → `test` (เทสหน่วย + เรนเดอร์ฉากทดสอบผ่าน Xvfb),
`windows` (.exe รุ่นจริง) และ `android` (APK debug) ไบนารี Godot และ export templates ถูก cache ตามรุ่น

## ข้อตกลง

- GDScript แบบระบุชนิด (`var x: int`, `:=`, อาร์กิวเมนต์และค่าคืนมีชนิด) ไม่ใช้ C#
- commit ไฟล์ `.import` และ `.uid` ที่ Godot เขียนข้าง asset และสคริปต์ (CI พึ่งพามัน); `.godot/`, `tests/out/`
  และ `assets/kits/*.glb` + `kits.json` ไม่ commit
- คอมเมนต์ในโค้ดเกมสั้นและเป็นไทยเหมือนส่วนอื่นของ repo; ในเทส เครื่องมือ และเอกสารใช้อังกฤษได้
- ข้อความไทยบนจอทุกข้อความผ่าน `I18n.t()` และมีคู่อังกฤษใน `ui/i18n_extra.json` (ข้อความของหน้าเก่ามาจาก
  `data/i18n_en.json`); `tests/unit/test_i18n.gd` ตรวจว่าทุกข้อความที่ HUD ใช้มีคำอังกฤษและไม่มีไทยหลงเหลือ
- โค้ดกติกาต้องให้ผลเหมือนกันทุกเครื่อง (สุ่มจาก seed เท่านั้น ไม่ใช้ `randi()` ลอย ๆ ไม่ใช้เวลานาฬิกา); `core/` ใช้
  จำนวนเต็มล้วน (ดู `docs/ARCHITECTURE.md` §4)
- งานต่อเฟรมต้องน้อย: ระดับกราฟิกต่ำสุดต้องลื่นบนมือถืออ่อน (`gl_compatibility`, ไม่เพิ่ม pass)
- ชุดโมเดล: exporter อบ `scale` ของแต่ละชุดลงในเมชแล้ว (ฟิกเกอร์สูงเท่าของจริงในเกม ไททัน 9–30 ม.) จึงวางฉาก `.glb`
  ที่ scale 1 และใช้ `baseR` จาก `kits.json` เว้นระยะ
