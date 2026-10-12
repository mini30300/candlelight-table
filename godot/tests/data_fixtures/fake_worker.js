// fake_worker.js — a tiny stand-in for ../candlelight-server/worker.js used by gen_bt_data.py --self-test.
// It keeps the shapes the extractor relies on (docs/CODEMAP.md, "Server touch points"): one-line embedded pages
// (whose text must never win an anchor), comma-separated declarations, bare and quoted keys, single quotes,
// trailing commas, comments inside the table. Numbers here are made up; the real datasheets live in data/types.json.
const APP_HTML = "<!doctype html><script>var BT2 = {}; const BT_RULES = 1; const BT2 = { trap: 1 }; const BT_ARMY_EN = { x: 'y' };</script>";
const MAX_TOKENS = 40;                 // not a battle-table constant
const BT_ARMY_EN = { gr: "Greek", mod: "soldiers",
                     "*": "secret hero" };
function bt2Abilities(T) { return T.hero ? ["character"] : null; }
const BT_MAX_ACTS = 500, BT_MAX_PLAYERS = 24, BT_GONE_MS = 75000;
const BT_THEMES = ["ruin", "forest"];
const BT_TERRAINS = ["flat", "hills"];   // ราบ เนิน
const BT_RULES = 9;
const BT2 = {
  heavy:     { nm: "เกราะหนัก", fac: "mod", n: 3, pts: 90, mv: 6, T: 4, sv: 3, w: 2, ld: 6, oc: 1, gun: { nm: "heavy carbine", rng: 24, a: 2, bs: 3, s: 4, ap: 1, d: 1 }, mel: { nm: "armoured fists", a: 3, ws: 3, s: 4, ap: 0, d: 1 } },
  hoplite:   { nm: "โฮพไลต์", fac: "gr", n: 5, pts: 65, mv: 6, T: 3, sv: 4, w: 1, ld: 7, oc: 2, gun: null, mel: { nm: "long spear", a: 2, ws: 3, s: 4, ap: 0, d: 1 } },
  'cavalry': { nm: 'ทหารม้า', fac: "gr", n: 3, pts: 105, mv: 12, T: 5, sv: 4, w: 3, ld: 7, oc: 2, r: 1.1, gun: null, mel: { nm: "lance", a: 3, ws: 3, s: 5, ap: 1, d: 2, la: 1 }, },
  /* a block comment before a key */ sniper: { nm: "พลซุ่มยิง", fac: "mod", n: 1, pts: 40, mv: 6, T: 3, sv: 5, w: 2, ld: 7, oc: 1, hero: 1,
    gun: { nm: "sniper rifle \"long\"", rng: 36, a: 1, bs: 2, s: 5, ap: 2, d: 3, hv: 1 }, mel: { nm: "knife", a: 1, ws: 4, s: 3, ap: 0, d: 1 } },
};
const BT_LIST_LEN = 512;               // slots in an army list
