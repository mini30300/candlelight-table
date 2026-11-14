class_name CampaignWeek
extends RefCounted
## สัปดาห์ของแคมเปญ (CAMPAIGN_SPEC §2.3): ทุกเครื่องเห็นกาแล็กซีเดียวกันทั้งสัปดาห์ เปลี่ยนทุกวันจันทร์ 00:00 UTC
## เลขสัปดาห์ = จำนวนสัปดาห์ (เริ่มวันจันทร์) นับจากสัปดาห์ของ 1 ม.ค. 1970 · ป้ายแบบ ISO "2026-W46" ไว้โชว์
## เวลาจริงอ่านที่เดียวคือ now_unix() (เทสตั้ง test_now เอง) · ไฟล์นี้ไม่มีข้อความไทย

const DAY := 86400
## วันที่ 0 ของ unix (1 ม.ค. 1970) เป็นวันพฤหัส: +3 วันให้สัปดาห์เริ่มวันจันทร์ 29 ธ.ค. 1969
const MONDAY_SHIFT := 3

## เทส: เวลา unix (วินาที UTC) ที่ใช้แทนนาฬิกาเครื่อง · -1 = ใช้นาฬิกาจริง
static var test_now := -1


## เวลา unix ตอนนี้ (วินาที UTC) — ที่เดียวในแคมเปญที่อ่านนาฬิกา
static func now_unix() -> int:
	if test_now >= 0:
		return test_now
	return int(Time.get_unix_time_from_system())


## เลขสัปดาห์ของเวลา unix
static func week_of(unix_s: int) -> int:
	return floori(float(floori(float(unix_s) / DAY) + MONDAY_SHIFT) / 7.0)


## สัปดาห์ปัจจุบัน
static func current() -> int:
	return week_of(now_unix())


## เวลา unix ตอนเริ่มสัปดาห์ (วันจันทร์ 00:00 UTC)
static func start_unix(week: int) -> int:
	return (week * 7 - MONDAY_SHIFT) * DAY


## วินาทีที่เหลือจนสุ่มเหตุการณ์ใหม่ (ต้นสัปดาห์ถัดไป)
static func seconds_to_reroll(unix_s: int) -> int:
	return start_unix(week_of(unix_s) + 1) - unix_s


## ป้าย ISO "YYYY-Www" ของสัปดาห์ (ปีของวันพฤหัสในสัปดาห์นั้น)
static func iso_label(week: int) -> String:
	var thu := start_unix(week) + 3 * DAY
	var d := Time.get_datetime_dict_from_unix_time(thu)
	var jan1 := Time.get_unix_time_from_datetime_dict({"year": d["year"], "month": 1, "day": 1, "hour": 0, "minute": 0, "second": 0})
	var n := floori(float(thu - jan1) / DAY / 7.0) + 1
	return "%04d-W%02d" % [int(d["year"]), n]


## ตัดวินาทีเป็น {d, h, m} ไว้โชว์ "อีก {d} วัน {h} ชม."
static func split(seconds: int) -> Dictionary:
	var s := maxi(seconds, 0)
	return {"d": floori(s / float(DAY)), "h": floori((s % DAY) / 3600.0), "m": floori((s % 3600) / 60.0)}
