class_name OnlineText
extends RefCounted
## ข้อความของระบบเล่นกับเพื่อน (NET_SPEC §3, §7.3): เหตุผลที่ต่อไม่ได้ (คีย์จาก NetGate และคีย์ในเครื่อง) → ข้อความไทย
## ที่แปลแล้ว, ที่อยู่ของสมาชิก (where) → ไทย, บรรทัดสถานะบนดาดฟ้า, ชื่อเริ่มต้น · คีย์ไทยทั้งก้อน (I18n.t แล้วค่อย format)
## ข้อความไทยของ net/ อยู่ที่นี่ทั้งหมด (net/ ไม่มีภาษาไทย) · หน้าตั้งเกม/สนามรบใช้ผ่าน load("res://ui/online_text.gd")

## เหตุผล → แม่แบบไทย (ตัวแปร {host} {mine} {n} {max} {port} มากับ args)
const REASONS := {
	"wrong_app": "รุ่นแอปไม่ตรงกัน: เจ้าห้อง {host} · คุณ {mine} — อัปเดตให้เป็นรุ่นเดียวกันก่อน",
	"wrong_rules": "กติกาหรือข้อมูลเกมไม่ตรงกัน (รุ่นกติกา {host} กับ {mine}) — อัปเดตให้เป็นรุ่นเดียวกันก่อน",
	"wrong_net": "ระบบเล่นกับเพื่อนคนละรุ่นกัน — อัปเดตให้เป็นรุ่นเดียวกันก่อน",
	"full": "ห้องเต็มแล้ว ({n}/{max} คน)",
	"not_lan": "เข้าได้เฉพาะเครื่องในวง Wi-Fi เดียวกัน",
	"wrong_game": "เครื่องนั้นไม่ใช่ห้องโต๊ะเทียน",
	"bad_message": "เครื่องนั้นไม่ใช่ห้องโต๊ะเทียน",
	"closing": "เจ้าห้องกำลังปิดห้อง",
	"port_busy": "เปิดห้องไม่ได้: พอร์ต {port} ถูกใช้อยู่ (เปิดแอปซ้อนกันอยู่หรือเปล่า)",
	"no_lan": "ไม่พบ Wi-Fi — ต่อ Wi-Fi ก่อนแล้วลองใหม่",
	"bad_ip": "IP ไม่ถูกต้อง",
	"timeout": "ต่อไม่ได้ — เช็กว่าอยู่ Wi-Fi เดียวกันและเจ้าห้องยังเปิดห้องอยู่",
	"host_left": "เจ้าห้องปิดห้องแล้ว",
	"reconnecting": "การเชื่อมต่อหลุด — กำลังต่อใหม่…",
	"reconnect_failed": "ต่อใหม่ไม่สำเร็จ — กลับมาเล่นคนเดียว",
	"reconnected": "ต่อใหม่ได้แล้ว",
}
## คีย์ของ NetGate (§3) และคีย์ที่เครื่องนี้ตัดสินเอง (เทสตรวจว่าครบ)
const GATE_KEYS: PackedStringArray = ["not_lan", "wrong_game", "wrong_net", "wrong_app", "wrong_rules", "full", "closing"]
const LOCAL_KEYS: PackedStringArray = ["port_busy", "no_lan", "bad_ip", "timeout", "host_left", "bad_message", "reconnect_failed"]
## บรรทัดบนการ์ดของเจ้าห้องเมื่อพอร์ตค้นหาห้องเปิดไม่ได้
const NO_DISCOVERY := "ค้นหาห้องอัตโนมัติไม่ได้บนเครื่องนี้ — เพื่อนใส่ IP แทนได้"
## สมาชิกอยู่ตรงไหน (MEMBERS.where)
const WHERE := {
	"deck": "อยู่บนดาดฟ้า",
	"setup": "กำลังตั้งเกม",
	"battle": "กำลังรบ",
	"arena": "อยู่ในอารีน่า",
	"army": "กำลังจัดกองทัพ",
	"settings": "ดูตั้งค่า",
	"menu": "อยู่หน้าแรก",
}
## บรรทัดสถานะบนดาดฟ้า (FriendTags)
const STATUS := "ออนไลน์ · ห้องของ {name} · {n}/{max} คน"
const DEFAULT_NAME := "ผู้เล่น {n}"


## ข้อความที่แปลแล้วของเหตุผล key (ไม่รู้จัก = ต่อไม่ได้แบบทั่วไป)
## รุ่นแอป ("ใหม่ 0.5") โชว์แค่ตัวเลขคำสุดท้าย ไม่โชว์คำไทยดิบ (แบบป้ายรุ่นหน้าแรก)
static func reason(key: String, args: Dictionary = {}) -> String:
	var th := str(REASONS.get(key, REASONS["timeout"]))
	var a := _strings(args)
	if key == "wrong_app":
		for k in ["host", "mine"]:
			if a.has(k):
				a[k] = version_number(str(a[k]))
	return I18n.t(th).format(a)


## ตัวเลขรุ่นจาก APP_VER ("ใหม่ 0.5" → "0.5")
static func version_number(app_ver: String) -> String:
	var parts := app_ver.strip_edges().split(" ", false)
	return parts[parts.size() - 1] if not parts.is_empty() else ""


## เหตุผลของแถวห้องที่รุ่นไม่ตรง (found() ที่ ok = false): args ของแถว (NetGate.check_beacon) หรือเลขจากบีคอนกับของเครื่องนี้
static func row_reason(row: Dictionary) -> String:
	var why := str(row.get("why", ""))
	var given: Variant = row.get("args")
	if given is Dictionary and not (given as Dictionary).is_empty():
		return reason(why, given)
	var args := {}
	match why:
		"wrong_app":
			args = {"host": str(row.get("app", "")), "mine": Version.APP_VER}
		"wrong_rules":
			args = {"host": str(row.get("rules", "")), "mine": str(Version.RULES_V)}
		"full":
			args = {"n": int(row.get("n", 0)), "max": int(row.get("max", 0))}
	return reason(why, args)


static func where_text(where: String) -> String:
	return I18n.t(str(WHERE.get(where, WHERE["deck"])))


static func status(host_name: String, n: int, max_n: int) -> String:
	return I18n.t(STATUS).format({"name": host_name, "n": n, "max": max_n})


## ชื่อเริ่มต้น "ผู้เล่น 123" (ตัวเลข 100–999) ตามภาษาตอนสร้าง แล้วไม่แปลอีก
static func default_name(n: int) -> String:
	return I18n.t(DEFAULT_NAME).format({"n": n})


static func _strings(args: Dictionary) -> Dictionary:
	var out := {}
	for k in args:
		out[str(k)] = str(args[k])
	return out
