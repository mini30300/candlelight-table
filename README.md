# Candlelight Table (Android)

แอพ D&D บนมือถือ ที่ Claude เป็น Dungeon Master ผ่านห้องแชท

- เซิร์ฟเวอร์กลาง: `https://candlelight-table.mini3030023450.workers.dev` (Cloudflare Worker + D1)
- แอพนี้คุยกับเซิร์ฟเวอร์ผ่าน REST และ Claude อ่าน/เขียนผ่าน MCP ที่ `/mcp`

## Build
GitHub Actions จะ build ให้อัตโนมัติทุกครั้งที่ push ไป `main` — ไฟล์ .apk อยู่ที่แท็บ Releases
