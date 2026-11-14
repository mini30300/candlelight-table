class_name MissionScreen
extends Control
## หน้าภารกิจ เดินและยิงมุมมองบุคคลที่สาม (CAMPAIGN_SPEC §1.6, §5.3, track C เป็นเจ้าของ)
## ใช้ ArenaPlayer (scenes/arena/arena_player.tscn) ตัวที่แต่งในห้องแต่งตัว + MissionWorld + MissionHud
## start(spec) รับข้อมูลจาก CampaignGalaxy.mission_spec · จบภารกิจ (ชนะ / แพ้ / ออกกลางคัน) ส่ง finished(result) ครั้งเดียว
## หลังจอมืด — หน้านี้ไม่ปิดตัวเอง CampaignFlow แทนที่ด้วยหน้าสรุปผล · Esc = แผงหยุดชั่วคราว (เล่นต่อ / ออกจากภารกิจ / ตั้งค่า)
## TODO(track C): โลกภารกิจ ศัตรู เป้าหมาย HUD แผงหยุด จอมืด และนับผลตาม CAMPAIGN_SPEC §5.5

signal finished(result: Dictionary)

const SCENE := "res://ui/screens/mission_screen.tscn"

var spec: Dictionary = {}
var _done := false


## เรียกหลัง App.push ทันที
func start(s: Dictionary) -> void:
	spec = s
	# TODO(track C): สร้าง MissionWorld จาก spec (seed, biome, faction, modifier, primary, secondary, diff)


## จบภารกิจ (ครั้งเดียว): result ตาม CAMPAIGN_SPEC §5.5
func finish(result: Dictionary) -> void:
	if _done:
		return
	_done = true
	finished.emit(result)


## TODO(track C): Esc / ย้อนกลับ = เปิดแผงหยุดชั่วคราวแล้วคืน true เสมอ (ตอนนี้ยังเป็นโครง: คืน false ให้ App ถอยกลับ)
func handle_back() -> bool:
	return false
