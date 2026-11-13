#!/usr/bin/env node
// record_battle_fx.js — the old page's attack choice per datasheet, as a fixture for scenes/battle/battle_fx_rules.gd.
// For every TYPE the page's own startAttack (window.BT.animate: one model attacks another, every dice a hit) runs once
// ranged and once in melee; the act it starts carries the attack kind (ANIM + stomp rule), the weapon effect kind
// (fxOf, with the page's guesses from weapon names) and whether the unit is a machine (machOf). Visual data only.
//   CHROMIUM_PATH=<chrome> node godot/tools/record_battle_fx.js        (PAGE=<file> for another copy of the page)
// Output: godot/tests/unit/fixtures/battle_fx/page_fx.json  {k: [ranged kind, ranged fx, melee kind, melee fx, mach]}
'use strict';
const fs = require('fs'), path = require('path');
const ROOT = path.resolve(__dirname, '..', '..');
const PAGE = path.resolve(process.env.PAGE || path.join(ROOT, 'app/src/main/assets/battle-table.html'));
const OUT = path.join(ROOT, 'godot/tests/unit/fixtures/battle_fx/page_fx.json');
function loadPlaywright(){
  try { return require('playwright'); } catch (e) { return require(path.join(ROOT, 'tests/node_modules/playwright')); }
}
(async () => {
  const pw = loadPlaywright();
  const browser = await pw.chromium.launch({ executablePath: process.env.CHROMIUM_PATH || undefined, args: ['--no-sandbox'] });
  const page = await browser.newPage();
  await page.goto('file://' + PAGE);
  await page.waitForFunction(() => window.BT && window.BT.TYPES && window.BT.TYPES.length > 0);
  const out = await page.evaluate(() => {
    const BT = window.BT, res = {};
    function one(k, melee){
      BT.units.length = 0;
      BT.add(k, 0, 0); BT.add('infantry', 0, 6);
      BT.animate(0, 1, melee, 2);
      const a = BT.units[0].act;
      return a ? [String(a.kind || ''), a.fk == null ? '' : String(a.fk), a.mach ? 1 : 0] : ['', '', 0];
    }
    BT.TYPES.forEach(function(T){
      let r = ['', '', 0], m = ['', '', 0];
      try { r = one(T.k, false); } catch (e) {}
      try { m = one(T.k, true); } catch (e) {}
      res[T.k] = [r[0], r[1], m[0], m[1], r[2] || m[2]];
    });
    BT.units.length = 0;
    return res;
  });
  await browser.close();
  const keys = Object.keys(out).sort(), sorted = {};
  keys.forEach(k => { sorted[k] = out[k]; });
  fs.mkdirSync(path.dirname(OUT), { recursive: true });
  fs.writeFileSync(OUT, JSON.stringify(sorted, null, 0).replace(/\],"/g, '],\n"') + '\n');
  console.log('wrote ' + path.relative(ROOT, OUT) + ' (' + keys.length + ' datasheets)');
})().catch(e => { console.error(e); process.exit(1); });
