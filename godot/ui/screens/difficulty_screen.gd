class_name DifficultyScreen
extends Control
## หน้าเลือกความยาก (CAMPAIGN_SPEC §1.3, §3, track B เป็นเจ้าของ): การ์ด 4 ใบ ธรรมดา / ยาก / ยากมาก / ภัยพิบัติ
## แต่ละใบมีฉากโชว์ (HeroStage + CampaignHeroes) ชื่อ คำอธิบาย และตัวคูณคะแนน (CampaignRules.difficulty / mult_text)
## เลือกแล้ว: ส่ง chosen(id) — หน้านี้ไม่ปิดตัวเอง CampaignFlow เป็นคนเปลี่ยนไปหน้ากาแล็กซี · ‹ กลับ / Esc = App ถอยกลับ
## ฉากสดได้ทีละใบ (ใบที่เลือก/ชี้อยู่) ใบอื่นเป็นภาพนิ่งที่วาดครั้งเดียว · min: ภาพนิ่งทั้ง 4 ใบ ไม่มีงานต่อเฟรม
## TODO(track B): สร้าง UI ในโค้ดแบบ DressingScreen (CandleStyle, safe margins, จอกว้าง 4 ใบเรียงแถว / จอแคบ 2×2 หรือเลื่อน)

signal chosen(difficulty: StringName)

const SCENE := "res://ui/screens/difficulty_screen.tscn"

var ctx: Dictionary = {}


## เรียกหลัง App.push ทันที: ctx = {"last": ความยากที่เลือกครั้งก่อน ("" = ยังไม่เคย), "from": "deck" | "room"}
func open(c: Dictionary) -> void:
	ctx = c
	# TODO(track B): สร้างการ์ด ไฮไลต์ ctx.last เริ่มฉากของใบแรก


## เลือกความยาก (ปุ่มการ์ด / เทส)
func choose(id: StringName) -> void:
	if not CampaignGalaxy.DIFFICULTIES.has(String(id)):
		return
	chosen.emit(id)


func handle_back() -> bool:
	return false
