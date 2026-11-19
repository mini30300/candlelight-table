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
## ความเร็วคนปกติ (ม./วิ, 0.14 ข้อ 1b): walk เดินช้า (Ctrl) · jog วิ่งเหยาะ (W ค่าปกติ วิ่งได้นาน) · back เพดานถอยหลัง
## run วิ่งเร็วตอนแรงเต็ม (Shift) แล้วลดหา cs เมื่อเหนื่อย · sprint_accel อัตราเร่งตอนเร่งเป็นวิ่งเร็ว (/วิ)
## ความเหนื่อยแบบซ่อน (ArenaStamina): cs ความเร็ววิกฤต · dprime แรงสำรอง (ม. ที่วิ่งเกิน cs ได้) · knee สำรองต่ำกว่านี้ความเร็วสูงสุดเริ่มลด
const PLAYER := {"hp": 100, "walk": 1.5, "run": 5.6, "accel": 12.0, "radius": 0.35, "invuln": 0.4, "down_time": 2.0,
	"holster": 0.15, "draw": 0.2, "jog": 2.7, "back": 1.8, "sprint_accel": 4.0, "cs": 3.2, "dprime": 30.0, "knee": 0.5}
## ชั้นการเคลื่อนที่ ทับค่าใน PLAYER · human = PLAYER เอง · armoured = เกราะเสริมกำลัง เร็วกว่าทุกท่าและเหนื่อยช้ากว่า
## machine = หุ่นยนต์ ไม่เหนื่อย (cs 0) วิ่งเร็วคงที่
const MOVE_CLASS := {
	"human": {},
	"armoured": {"walk": 1.6, "jog": 3.2, "back": 2.0, "run": 6.5, "cs": 4.2, "dprime": 40.0, "knee": 0.5},
	"machine": {"walk": 1.4, "jog": 2.5, "back": 1.6, "run": 4.5, "cs": 0.0},
}
## ชุดตัว (walk_kit) → ชั้น · ที่ไม่อยู่ในนี้ = human
const MOVE_KITS := {"knight": "armoured", "kblade": "armoured", "kcapt": "armoured", "cxw": "armoured", "rwar": "machine"}
## เสียงหอบ (ไม่มีหลอดบนจอ) · e = 1 − แรงสำรอง · เปิดเมื่อ e ≥ on ปิดเมื่อ e < off · จังหวะ rate0 + rate1·e ครั้ง/นาที
## หายใจเข้า in_share ของรอบ · ดัง gain0 → gain1 (smoothstep จาก e = on ถึง gain_full) · ชุดหอบแรงเมื่อ e ≥ hard ลงเมื่อ e < hard_off
## ลมเข้าที่ถึงภายใน snap วิ เลื่อนไปตรงเท้าลง · เกราะเสริมกำลัง (หมวกปิด) ดัง × armour_gain เสียง × armour_pitch
const BREATH := {"on": 0.2, "off": 0.15, "rate0": 16.0, "rate1": 40.0, "in_share": 0.45, "gain0": 0.15, "gain1": 0.8,
	"gain_full": 0.9, "hard": 0.55, "hard_off": 0.5, "snap": 0.25, "armour_gain": 0.6, "armour_pitch": 0.94}
## เสียงฝีเท้า: ดังตามท่า walk / jog / run × (1 + tired·e) · ข้างตัว side ม. สูง y ม. · เท้าซ้าย pitch_l ขวา pitch_r
## โลหะ (เกราะ หุ่น) × metal_pitch · cadence = จุด (ม./วิ, ก้าว/นาที) ของวงล้อก้าว สำหรับตัวที่ไม่มีท่าเดินของตัวเอง
const STEPS := {"walk": 0.35, "jog": 0.55, "run": 0.8, "tired": 0.2, "side": 0.1, "y": 0.05, "pitch_l": 0.98,
	"pitch_r": 1.02, "metal_pitch": 0.9,
	"cadence": [Vector2(0.0, 90.0), Vector2(1.45, 103.0), Vector2(3.0, 164.0), Vector2(5.0, 180.0), Vector2(6.5, 195.0)]}
## แรงผลักร่างตอนตาย (ภาพล้วน: ร่างล้มตามฟิสิกส์ของทหาร hi/mid, ARENA_SPEC §9.8) · speed ม./วิ ที่อก ตามทิศจากผู้ตีไปหาผู้ตาย
## ของจริง: กรงเล็บ (แขนสัตว์ ~8 กก. × ~6 ม./วิ) ส่งให้ร่าง 75 กก. ได้ ~0.6 ม./วิ ดูจืด · visual × 4 ให้เห็นทิศชัด = 2.4
const PUSH := {"speed": 2.4, "real": 0.6, "visual": 4.0}
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
const DODGE := {"th": "หลบ", "distance": 3.8, "time": 0.3, "invuln": 0.25, "cooldown": 0.7, "ease": 0.6}
## เสียงอารีน่า: ชื่อ → [ชนิดเสียงของหน้าเก่า (DEF), ความดัง, ระดับเสียง] ผ่าน Sfx (ไม่มี Sfx = เงียบ)
const SOUNDS := {"gun": ["shot", 1.0, 1.0], "reload": ["clang", 0.7, 1.35], "empty": ["ui", 3.0, 0.7],
	"punch": ["swing", 0.8, 1.2], "punch_hit": ["hit", 1.2, 0.9], "saw_idle": ["saw", 0.35, 0.9],
	"saw_rev": ["saw", 1.1, 1.25], "saw_hit": ["chain", 1.0, 1.0], "beast_roar": ["charge", 1.0, 0.7],
	"beast_strike": ["claw", 1.0, 0.85], "beast_miss": ["swing", 0.9, 0.7], "beast_hit": ["bite", 0.6, 1.3],
	"beast_death": ["die", 1.6, 0.6], "switch": ["turn", 1.0, 1.0], "reset": ["heal", 1.0, 1.0],
	"dodge": ["swing", 1.2, 0.6]}
const NUMBERS := {"heavy_at": 25, "life": 0.8, "rise": 0.6, "still": 0.6, "pool": 8}
