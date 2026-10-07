class_name DatasheetText
extends RefCounted
## ข้อความบนการ์ดข้อมูลหน่วย (หน้าจัดกองทัพ): หัวการ์ด ค่าประจำตัว ตารางอาวุธ ค่าพิเศษของอาวุธ ความสามารถ
## ถ้อยคำตาม abilityText / wpnLine ของหน้าเก่าและ data/rules_summary.md · แปลทั้งประโยคด้วย I18n.t ก่อน แล้วค่อยใส่ตัวเลข
## ({r} {n} ...) เพราะ I18n หาคำแปลทีละประโยค · ไม่มีถ้อยคำของหน่วยลับ (หน่วยลับไม่ขึ้นบนหน้านี้)

## หาโหนด I18n ผ่าน SceneTree (ไม่ใช้ชื่อ autoload ตรง ๆ: สคริปต์ -s ที่อ้างคลาสนี้คอมไพล์ก่อน autoload ลงทะเบียน)
static var _i18n: Node = null

## หัวตารางอาวุธ: ชื่อ ระยะ ครั้ง ฝีมือ แรง เจาะ ดาเมจ
const WEAPON_HEAD: PackedStringArray = ["อาวุธ", "ระยะ", "จำนวนครั้ง", "ฝีมือ", "แรง", "เจาะ", "ดาเมจ"]


## แปลตามภาษาที่เลือก (ไม่มี I18n ก็คืนไทย)
static func tl(th: String) -> String:
	if _i18n == null or not is_instance_valid(_i18n):
		var loop := Engine.get_main_loop()
		_i18n = (loop as SceneTree).root.get_node_or_null(^"I18n") if loop is SceneTree else null
	return str(_i18n.call("t", th)) if _i18n != null else th


## แปลแล้วใส่ค่า
static func tf(th: String, args: Dictionary = {}) -> String:
	var s := tl(th)
	return s.format(args) if not args.is_empty() else s


## แต้มแบบมีจุลภาค 1,000
static func fmt_pts(n: int) -> String:
	var s := str(absi(n))
	var out := ""
	while s.length() > 3:
		out = "," + s.right(3) + out
		s = s.left(s.length() - 3)
	return ("-" if n < 0 else "") + s + out


static func name_of(t: Dictionary) -> String:
	return tl(str(t.get("nm", "")))


static func desc_of(t: Dictionary) -> String:
	return tl(str(t.get("d", "")))


## "×5 · 45 แต้ม"
static func sub_of(t: Dictionary) -> String:
	return tf("×{n} · {pts} แต้ม", {"n": int(t.get("n", 0)), "pts": fmt_pts(int(t.get("pts", 0)))})


## ค่าประจำตัวเป็นคู่ [หัวข้อ, ค่า]: เดิน ทน เกราะ (เกราะพิเศษ) แผล ขวัญ คุมจุด
static func stats(t: Dictionary) -> Array[PackedStringArray]:
	var out: Array[PackedStringArray] = []
	var sv := int(t.get("sv", 7))
	out.append(PackedStringArray([tl("เดิน"), "%d\"" % int(t.get("mv", 0))]))
	out.append(PackedStringArray([tl("ทน"), str(int(t.get("T", 0)))]))
	out.append(PackedStringArray([tl("เกราะ"), tl("ไม่มี") if sv > 6 else "%d+" % sv]))
	if int(t.get("inv", 0)) > 0:
		out.append(PackedStringArray([tl("เกราะพิเศษ"), "%d++" % int(t.get("inv", 0))]))
	out.append(PackedStringArray([tl("แผล"), str(int(t.get("w", 0)))]))
	out.append(PackedStringArray([tl("ขวัญ"), "%d+" % int(t.get("ld", 0))]))
	out.append(PackedStringArray([tl("คุมจุด"), str(int(t.get("oc", 0)))]))
	return out


static func weapon_head() -> PackedStringArray:
	var out := PackedStringArray()
	for h in WEAPON_HEAD:
		out.append(tl(h))
	return out


## แถวตารางอาวุธ: [ชื่อ, ระยะ, ครั้ง, ฝีมือ, แรง, เจาะ, ดาเมจ]
static func weapon_row(w: Dictionary, melee: bool) -> PackedStringArray:
	var skill := ""
	if bool(w.get("tr", false)):
		skill = tl("อัตโนมัติ")
	else:
		skill = "%d+" % int(w.get("ws" if melee else "bs", 0))
	return PackedStringArray([
		tl(str(w.get("nm", ""))),
		tl("ประชิด") if melee else "%d\"" % int(w.get("rng", 0)),
		str(int(w.get("a", 0))),
		skill,
		str(int(w.get("s", 0))),
		str(int(w.get("ap", 0))),
		str(int(w.get("d", 0))),
	])


## ค่าพิเศษของอาวุธเป็นป้ายสั้น ๆ (ลำดับเดียวกับ wpnLine ของหน้าเก่า; tr อยู่ในช่องฝีมือแล้วแต่ขึ้นป้ายด้วย)
static func weapon_keywords(w: Dictionary) -> PackedStringArray:
	var out := PackedStringArray()
	if bool(w.get("tr", false)):
		out.append(tl("พ่น โดนอัตโนมัติ"))
	if bool(w.get("as", false)):
		out.append(tl("ยิงได้แม้วิ่ง"))
	if bool(w.get("hv", false)):
		out.append(tl("ยืนนิ่ง +1"))
	if int(w.get("rf", 0)) > 0:
		out.append(tf("ใกล้ครึ่งระยะ +{n}", {"n": int(w["rf"])}))
	if bool(w.get("pi", false)):
		out.append(tl("ยิงตอนประชิดได้"))
	if int(w.get("su", 0)) > 0:
		out.append(tl("6 = เข้าเพิ่ม"))
	if bool(w.get("la", false)):
		out.append(tl("บุกมา +1 เจาะ"))
	if bool(w.get("lh", false)):
		out.append(tl("เข้า 6 = เจาะเลย"))
	if bool(w.get("dw", false)):
		out.append(tl("เจาะ 6 = แผลตรง"))
	if bool(w.get("bl", false)):
		out.append(tl("ระเบิดวงกว้าง: เป้าทุก 5 ตัว +1 นัด"))
	if int(w.get("po", 0)) > 0:
		out.append(tf("พิษ: เจาะทหารเดินเท้าได้ {n}+", {"n": int(w["po"])}))
	if bool(w.get("mk", false)):
		out.append(tl("ชี้เป้า: ยิงเข้าแล้ว พวกเดียวกันยิงเป้านี้ +1 จนจบตา"))
	return out


## ความสามารถของหน่วยเป็นป้ายสั้น ๆ ตามลำดับของ abilityText (ไม่มีป้ายของหน่วยลับ)
static func abilities(t: Dictionary) -> PackedStringArray:
	var out := PackedStringArray()
	var r := GameData.const_int("AURA_R", 6)
	var aura := str(t.get("aura", ""))
	if bool(t.get("hero", false)):
		out.append(tl("★ ตัวเอก"))
	if bool(t.get("brave", false)):
		out.append(tl("ไม่เคยถอย"))
	if bool(t.get("aoc", false)):
		out.append(tl("เกราะศรัทธา (โดนเจาะ −1)"))
	if aura == "hit":
		out.append(tf("ผู้นำ: พวกในระยะ {r}\" เข้าเป้า +1", {"r": r}))
	elif aura == "ld":
		out.append(tf("ผู้นำ: พวกในระยะ {r}\" ไม่เสียขวัญ", {"r": r}))
	elif aura == "bless":
		out.append(tf("พรจากพระเจ้า: พวกในระยะ {r}\" ได้เซฟพิเศษ {inv}++", {"r": r, "inv": GameData.const_int("BLESS_INV", 5)}))
	elif aura == "rez":
		out.append(tf("เทพแห่งความตาย: หน่วยที่ลุกได้ในระยะ {r}\" ลุกตั้งแต่ {n}+", {"r": r, "n": GameData.const_int("REZ_AURA", 4)}))
	if bool(t.get("ca", false)):
		out.append(tl("บุกมา ตีเพิ่ม 1"))
	if bool(t.get("ac", false)):
		out.append(tl("วิ่งแล้วบุกได้"))
	if bool(t.get("fly", false)):
		out.append(tl("บิน (ถอยแล้วยิง/บุกได้)"))
	if bool(t.get("st", false)):
		out.append(tl("พรางตัว (โดนยิง −1)"))
	if int(t.get("rez", 0)) > 0:
		out.append(tf("ซ่อมตัวเอง {n}+", {"n": int(t["rez"])}))
	if bool(t.get("heel", false)):
		out.append(tl("ส้นเท้า: โดนเจาะได้ 6 ตายทันที"))
	if int(t.get("wind", 0)) > 0:
		out.append(tf("ลูกพระพาย: ตายแล้วลุกขึ้นใหม่ต้นเฟสคำสั่งถัดไป แผลเต็ม (ครั้งแรกแน่นอน ครั้งต่อไปทอย {n}+)", {"n": int(t["wind"])}))
	if t.get("spawn") is Dictionary:
		var sp: Dictionary = t["spawn"]
		out.append(tf("ซ่อน{unit} {n} ตัวในท้อง", {"unit": tl(str(GameData.ty(str(sp.get("k", ""))).get("nm", ""))), "n": int(sp.get("n", 0))}))
	if int(t.get("heal", 0)) > 0:
		out.append(tf("รักษาเพื่อนในระยะ {r}\"", {"r": int(t["heal"])}))
	if bool(t.get("ttn", false)):
		out.append(tl("ร่างมหึมา: ติดประชิดก็ยังยิงได้ ถอยแล้วยิง/บุกได้"))
	if int(t.get("vsh", 0)) > 0:
		out.append(tf("โล่พลังงาน {n} ชั้น (ชั้นละกันได้ทั้งนัด ฟื้นทุกต้นตา)", {"n": int(t["vsh"])}))
	if bool(t.get("hd", false)):
		out.append(tl("ความเสียหายที่โดนลดครึ่ง"))
	if bool(t.get("gk", false)):
		out.append(tl("ฆ่าได้แล้วฟื้นแผล"))
	if aura == "veil":
		out.append(tf("หมอกพิษ: พวกในระยะ {r}\" โดนยิงยากขึ้น", {"r": r}))
	if bool(t.get("veh", false)):
		out.append(tl("ยานพาหนะ"))
	match str(t.get("fac", "")):
		"el":
			out.append(tl("สมาธิรบ: วิ่งแล้วยังยิงได้"))
		"de":
			out.append(tf("ยิ่งรบยิ่งดุ: ตั้งแต่รอบ {n} ตีประชิดเข้า +1 และวิ่งแล้วบุกได้", {"n": GameData.const_int("PAIN_ROUND", 3)}))
		"cx":
			out.append(tl("สัญญาปีศาจ: ตีประชิดทอยเข้าได้ 6 เข้าเพิ่มอีกครั้ง"))
	return out


## หัวข้อภาคีของอัศวินเกราะพลัง (ch): [ชื่อภาคี, คำบรรยายสี]; ไม่มีภาคี = หน่วยทั่วไป ใช้ได้ทุกภาคี
static func chapter_heading(ch: String, chapters: Dictionary) -> PackedStringArray:
	if ch == "":
		return PackedStringArray([tl("หน่วยทั่วไป"), tl("ใช้ได้ทุกภาคี")])
	var c: Variant = chapters.get(ch)
	var desc := str(c[2]) if c is Array and (c as Array).size() > 2 else ""
	return PackedStringArray([tl(ch), tl(desc) if desc != "" else ""])
