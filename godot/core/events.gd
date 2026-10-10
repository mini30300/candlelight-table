class_name Events
extends RefCounted
## เหตุการณ์ที่ core ส่งให้ฝั่งภาพและ UI (ARCHITECTURE §3): Dictionary {"e": Id, ...payload}
## payload เป็น int / String / bool / Array / Dictionary เท่านั้น; คีย์ "e" สงวนไว้

## ชนิดเหตุการณ์และรูปร่าง payload
enum Id {
	BAD_ACT,         # {key, seq, a}            act ที่ใช้ไม่ได้ (Table.apply ตอบ; ไม่อยู่ในรายการ §3)
	SQUAD_ORDERED,   # {id, path: [[x, z]...]}  หมู่ได้รับคำสั่งเดิน (MI)
	MOVE_STEP,       # {uid, gx, gz}            โมเดลก้าวถึงจุดกติกา
	ATTACK_STAGE,    # {p, stage, dice: [int]}  ขั้นของการโจมตี p
	DICE_REQUESTED,  # {roller, kind, n}        ขอให้ผู้ทอยทอยลูกเต๋า n ลูก
	HIT,             # {p, n}
	WOUND,           # {p, n}
	SAVE,            # {p, n}
	DAMAGE,          # {uid, hp}                hp ที่เหลือ
	DEATH,           # {uid}
	FALLEN,          # {uid}
	SHOCK,           # {sid}
	CHARGE,          # {sid, tid}
	HEAL,            # {uid, hp}
	REZ,             # {uid}
	PHASE,           # {ph}
	TURN,            # {team, round}
	OBJECTIVE,       # {i, owner}
	LOG_LINE,        # {key, args: []}          ข้อความบันทึก (key แปลผ่าน i18n)
	STRAT,           # {k, team}
	DESYNC,          # {seq, local_digest, remote_digest}
	OVER,            # {result}
}


## สร้างเหตุการณ์: {"e": id} ตามด้วย payload (คีย์ "e" ใน payload ถูกข้าม)
static func make(id: Id, payload: Dictionary) -> Dictionary:
	var ev := {"e": int(id)}
	for k: Variant in payload:
		if k != "e":
			ev[k] = payload[k]
	return ev


## id ของเหตุการณ์ (-1 ถ้าไม่มี)
static func id_of(ev: Dictionary) -> int:
	if ev.has("e") and typeof(ev["e"]) == TYPE_INT:
		return int(ev["e"])
	return -1


## id ถูกต้องไหม
static func is_valid(id: int) -> bool:
	return id >= 0 and id < Id.size()


## ชื่อของ id สำหรับบันทึกและทดสอบ ("?" ถ้าไม่มี)
static func name_of(id: int) -> String:
	if not is_valid(id):
		return "?"
	return String(Id.keys()[id])
