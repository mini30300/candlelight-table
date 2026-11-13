class_name ArenaData
extends RefCounted
## ตารางตัวเลขทั้งหมดของอารีน่าทดสอบอาวุธ (ARENA_SPEC §6.1) · ค่าคงที่ล้วน ไม่มีโหนด
## อยู่ใต้ ui/ เพราะมีชื่อไทย (lint ตรวจว่าเป็นคีย์ทั้งข้อความ) · ห้ามไฟล์อื่นเขียนตัวเลขต่อสู้เอง

const WEAPONS := {
	"gun": {"th": "ปืนไรเฟิล", "kind": "hitscan", "slot": 1, "damage": 12, "rate": 8.0, "mag": 30, "reload": 1.6,
		"range": 60.0, "knockback": 0.4, "stagger": false},
	"sword": {"th": "ดาบเลื่อย", "kind": "melee", "slot": 2, "damage": 45, "active": 0.18, "cooldown": 0.8,
		"reach": 2.3, "half_angle_deg": 75.0, "knockback": 2.0, "stagger": true},
	"punch": {"th": "หมัด", "kind": "melee", "slot": 0, "damage": 25, "active": 0.12, "cooldown": 0.55,
		"reach": 1.6, "half_angle_deg": 50.0, "knockback": 3.0, "stagger": true},
}
const PLAYER := {"hp": 100, "walk": 3.0, "run": 5.0, "accel": 12.0, "radius": 0.35, "invuln": 0.4, "down_time": 2.0,
	"holster": 0.15, "draw": 0.2}
const BEAST := {"th": "สัตว์รัง", "kit": "warrior", "hp": 300, "radius": 0.6, "height": 2.1, "walk": 1.5, "run": 3.7,
	"turn": 6.0, "attack_range": 2.2, "windup": 0.6, "attack_clip_speed": 0.6, "strike_damage": 18, "strike_reach": 2.6,
	"strike_half_angle_deg": 70.0, "recover": 0.7, "flinch": 0.35, "flinch_heavy": 0.8, "heavy_at": 40,
	"friction": 8.0, "think_hz": 10.0, "repath": 0.4, "grace": 3.0, "home_speed": 1.5,
	"strike_at": 0.72, "poise": 1.2}
## strike_at: กรงเล็บลงหลังเริ่มง้าง (วิ) = เหตุการณ์ shot ของท่า claw (0.433 วิ) ÷ attack_clip_speed · AI ใช้ค่านี้ ไม่ใช้ความยาวท่า
## poise: ระหว่างสะดุ้งและอีกกี่วิหลังสะดุ้งจบ (บอทเปิด) ที่โดนแล้วไม่สะดุ้งซ้ำ (ต่อย/ฟันรัวแล้วมันยังตะปบสวนได้)
## ยังเสียเลือด ถูกผลัก กะพริบตามปกติ
const RANGE := {"seed": 4404, "switch_cooldown": 1.0}
## พุ่งหลบ (Space / ปุ่ม "หลบ"): พุ่ง distance ม. ใน time วิ ตามทิศที่กด (ไม่กด = ถอยหลัง) อมตะ invuln วิแรก
## กดซ้ำได้หลังพุ่งจบ cooldown วิ · ease: ความเร็วลดเป็นเส้นตรง ต้น = เฉลี่ย × (1 + ease) ปลาย = เฉลี่ย × (1 − ease)
## hold_aim: ตัวละครที่ไม่เดินเยื้อง (H9) หันตามทิศเล็งอีกกี่วิหลังยิง/ฟัน/ต่อย
const DODGE := {"th": "หลบ", "distance": 3.8, "time": 0.3, "invuln": 0.25, "cooldown": 0.7, "ease": 0.6,
	"hold_aim": 0.6}
## เสียงอารีน่า: ชื่อ → [ชนิดเสียงของหน้าเก่า (DEF), ความดัง, ระดับเสียง] ผ่าน Sfx (ไม่มี Sfx = เงียบ)
const SOUNDS := {"gun": ["shot", 1.0, 1.0], "reload": ["clang", 0.7, 1.35], "empty": ["ui", 3.0, 0.7],
	"punch": ["swing", 0.8, 1.2], "punch_hit": ["hit", 1.2, 0.9], "saw_idle": ["saw", 0.35, 0.9],
	"saw_rev": ["saw", 1.1, 1.25], "saw_hit": ["chain", 1.0, 1.0], "beast_roar": ["charge", 1.0, 0.7],
	"beast_strike": ["claw", 1.0, 0.85], "beast_miss": ["swing", 0.9, 0.7], "beast_hit": ["bite", 0.6, 1.3],
	"beast_death": ["die", 1.6, 0.6], "switch": ["turn", 1.0, 1.0], "reset": ["heal", 1.0, 1.0],
	"dodge": ["swing", 1.2, 0.6]}
const NUMBERS := {"heavy_at": 25, "life": 0.8, "rise": 0.6, "still": 0.6, "pool": 8}
