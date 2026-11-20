class_name FaceSpeech
extends RefCounted
## ปากพูดแบบเงียบ (ใหม่ 0.14 ข้อ 2): ข้อความ → ลำดับรูปปาก [[รหัส, วินาที], ...] ไม่มีเสียง (กรอบคำพูดบนจอ)
## ไทย: สระหน้า เ แ โ ใ ไ ออกเสียงหลังพยัญชนะ · วรรณยุกต์และ ็ ไม่มีรูปปาก · ตัวที่มี ์ ไม่ออกเสียง
##   ตัวสะกด ม บ ป พ ภ ฟ ปิดปาก · ไม่มีสระเขียน = สระในตัว (โอะ/อะ) · ๆ พูดคำก่อนซ้ำ · แบ่งคำด้วย TextServer
## อังกฤษ: ตัวอักษร + อักษรคู่ (th sh ch ee oo ...) · e ท้ายคำไม่ออกเสียง · ตัวซ้ำติดกันนับครั้งเดียว
## รหัส: rest ปากปิด · A อ้ากว้าง · E ยิ้มกว้าง · I แคบยิ้ม · O กลม · U ห่อ · F ฟันบนแตะปากล่าง · C พยัญชนะทั่วไป
## ผลเหมือนกันทุกครั้งทุกเครื่องที่ข้อความกับภาษาเดียวกัน (ไม่สุ่ม ไม่อ่านนาฬิกา)

const CODES: PackedStringArray = ["rest", "A", "E", "I", "O", "U", "F", "C"]
const T_VOWEL := 0.13
const T_CONS := 0.07
const T_CLOSE := 0.09
const T_GAP := 0.1            # ระหว่างคำ (ปากเกือบปิด)
const T_PAUSE := 0.28         # , . ! ? ฯลฯ
const T_END := 0.12           # ปิดปากท้ายประโยค

# อักษรไทยเป็นรหัสยูนิโค้ด: scenes/arena ไม่มีสตริงภาษาไทย (test_arena_text) · ชื่อตัวอักษรอยู่ในหมายเหตุ
const LEAD: PackedInt32Array = [0x0E40, 0x0E41, 0x0E42, 0x0E43, 0x0E44]          # เ แ โ ใ ไ
const SILENT: PackedInt32Array = [0x0E47, 0x0E48, 0x0E49, 0x0E4A, 0x0E4B]        # ็ ่ ้ ๊ ๋
const KARAN := 0x0E4C                                                            # ์
const REPEAT := 0x0E46                                                           # ๆ
const BILABIAL: PackedInt32Array = [0x0E1A, 0x0E1B, 0x0E1E, 0x0E1C, 0x0E20, 0x0E21]    # บ ป พ ผ ภ ม
const LABIO: PackedInt32Array = [0x0E1F, 0x0E1D]                                 # ฟ ฝ
const CLOSE_FINAL: PackedInt32Array = [0x0E21, 0x0E1A, 0x0E1B, 0x0E1E, 0x0E20, 0x0E1F] # ม บ ป พ ภ ฟ
const CLUSTER_1: PackedInt32Array = [0x0E01, 0x0E02, 0x0E04, 0x0E15, 0x0E1B, 0x0E1C, 0x0E1E]   # ก ข ค ต ป ผ พ
const CLUSTER_2: PackedInt32Array = [0x0E23, 0x0E25, 0x0E27]                     # ร ล ว
const HO_LEAD: PackedInt32Array = [0x0E07, 0x0E0D, 0x0E19, 0x0E21, 0x0E22, 0x0E23, 0x0E25, 0x0E27]   # ง ญ น ม ย ร ล ว
const HO := 0x0E2B            # ห
const O_ANG := 0x0E2D         # อ
const WO := 0x0E27            # ว
const YO := 0x0E22            # ย
const SARA_A := 0x0E30        # ะ
const SARA_AA := 0x0E32       # า
const SARA_I := 0x0E34        # ิ
const SARA_II := 0x0E35       # ี
const SARA_UEE := 0x0E37      # ื
const PUNCT := ",.!?;:…\"'()-–—"
const EN_DIGRAPH := {"th": ["C"], "sh": ["U"], "ch": ["U"], "ph": ["F"], "wh": ["U"], "ng": ["C"], "ck": ["C"],
	"qu": ["C", "U"], "ee": ["I"], "ea": ["I"], "oo": ["U"], "ou": ["O", "U"], "ow": ["O", "U"], "oa": ["O"],
	"ai": ["E", "I"], "ay": ["E", "I"], "oi": ["O", "I"], "oy": ["O", "I"], "au": ["O"], "aw": ["O"]}
const EN_VOWEL := {"a": "A", "e": "E", "i": "I", "o": "O", "u": "U"}

## ข้อความ → [[รหัส, วินาที], ...] (ว่าง = ไม่พูด) · lang "th"/"en" ("" = ดูจากตัวอักษร: มีอักษรไทย = ไทย)
static func visemes(text: String, lang := "") -> Array:
	var s := text.strip_edges()
	if s.is_empty():
		return []
	if lang == "":
		lang = "th" if _has_thai(s) else "en"
	var out := []
	if lang == "th":
		_thai(s, out)
	else:
		_english(s.to_lower(), out)
	if out.is_empty():
		return []
	_push(out, "rest", T_END)
	return _merge(out)


## ความยาวรวม (วิ) ของลำดับรูปปาก
static func duration(track: Array) -> float:
	var t := 0.0
	for v: Array in track:
		t += float(v[1])
	return t


## รหัสรูปปากที่เวลา t ของลำดับ ("" = พูดจบแล้ว)
static func code_at(track: Array, t: float) -> String:
	var acc := 0.0
	for v: Array in track:
		acc += float(v[1])
		if t < acc:
			return str(v[0])
	return ""


static func _has_thai(s: String) -> bool:
	for i in s.length():
		var c := s.unicode_at(i)
		if c >= 0x0E00 and c <= 0x0E7F:
			return true
	return false


static func _push(out: Array, code: String, t: float) -> void:
	out.append([code, t])


## รหัสเดียวกันติดกันรวมเป็นช่วงเดียว
static func _merge(a: Array) -> Array:
	var out := []
	for v: Array in a:
		if not out.is_empty() and str(out[-1][0]) == str(v[0]):
			out[-1][1] = float(out[-1][1]) + float(v[1])
		else:
			out.append([str(v[0]), float(v[1])])
	return out


# ---------------- ไทย ----------------

## แบ่งคำ (TextServer: พจนานุกรมไทยของ ICU) แล้วทำทีละคำ · ช่องว่าง/วรรคตอนเป็นช่วงหยุด
static func _thai(s: String, out: Array) -> void:
	var prev := []
	for w: String in words(s):
		if w.strip_edges().is_empty():
			_push(out, "rest", T_GAP)
			continue
		if w.length() == 1 and w.unicode_at(0) == REPEAT:
			_push(out, "rest", T_GAP)
			out.append_array(prev)
			continue
		if w.length() == 1 and PUNCT.contains(w):
			_push(out, "rest", T_PAUSE)
			continue
		var one := []
		_thai_word(w, one)
		if one.is_empty():
			continue
		if not out.is_empty() and str(out[-1][0]) != "rest":
			_push(out, "rest", T_GAP)
		out.append_array(one)
		prev = one


## คำของข้อความตามจุดแบ่งคำของ TextServer (ไทยใช้พจนานุกรมของ ICU) · ช่องว่าง วรรคตอน ๆ แยกเป็นชิ้นของตัวเอง
static func words(s: String) -> PackedStringArray:
	var out := PackedStringArray()
	var ts := TextServerManager.get_primary_interface()
	var b := ts.string_get_word_breaks(s, "th") if ts != null else PackedInt32Array()
	var pos := 0
	for i in range(0, b.size() - 1, 2):
		if b[i] > pos:
			_split_marks(s.substr(pos, b[i] - pos), out)
		_split_marks(s.substr(b[i], b[i + 1] - b[i]), out)
		pos = b[i + 1]
	if pos < s.length():
		_split_marks(s.substr(pos), out)
	return out


## ช่องว่าง วรรคตอน และ ๆ แยกออกจากคำ
static func _split_marks(w: String, out: PackedStringArray) -> void:
	var cur := ""
	for i in w.length():
		var c := w[i]
		if c == " " or w.unicode_at(i) == REPEAT or PUNCT.contains(c):
			if cur != "":
				out.append(cur)
				cur = ""
			out.append(c)
		else:
			cur += c
	if cur != "":
		out.append(cur)


static func _cons(c: int) -> bool:
	return c >= 0x0E01 and c <= 0x0E2E


## สระที่เขียนตามหลัง/บน/ล่างพยัญชนะ (ะ ั า ำ ิ ี ึ ื ุ ู ฺ ๅ)
static func _after_vowel(c: int) -> bool:
	return (c >= 0x0E30 and c <= 0x0E39) or c == 0x0E45


static func _init_code(c: int) -> String:
	if BILABIAL.has(c):
		return "rest"
	if LABIO.has(c):
		return "F"
	if c == WO:
		return "U"
	return "C"


static func _final_code(c: int) -> String:
	if CLOSE_FINAL.has(c):
		return "rest"
	if c == WO:
		return "U"
	if c == YO:
		return "I"
	return "C"


static func _vowel_codes(c: int) -> Array:
	match c:
		0x0E30, 0x0E31, 0x0E32, 0x0E45:      # ะ ั า ๅ
			return ["A"]
		0x0E33:                              # ำ
			return ["A", "rest"]
		0x0E34, 0x0E35:                      # ิ ี
			return ["I"]
		0x0E36, 0x0E37:                      # ึ ื
			return ["E"]
		0x0E38, 0x0E39:                      # ุ ู
			return ["U"]
	return []


## ตำแหน่งถัดไปที่ไม่ใช่วรรณยุกต์
static func _skip(u: PackedInt32Array, j: int) -> int:
	while j < u.size() and SILENT.has(u[j]):
		j += 1
	return j


static func _at(u: PackedInt32Array, j: int) -> int:
	return u[j] if j >= 0 and j < u.size() else 0


static func _cluster(a: int, b: int) -> bool:
	return (CLUSTER_1.has(a) and CLUSTER_2.has(b)) or (a == HO and HO_LEAD.has(b)) or (a == O_ANG and b == YO)


## หนึ่งคำ: พยัญชนะต้น → สระ → ตัวสะกด (สระหน้าเก็บไว้จนเจอพยัญชนะของมัน)
static func _thai_word(w: String, out: Array) -> void:
	var u := PackedInt32Array()
	for k in w.length():
		u.append(w.unicode_at(k))
	var n := u.size()
	var lead := 0
	var init := 0             # พยัญชนะต้นของพยางค์ที่ยังไม่มีสระ (0 = ไม่มี)
	var vowel := false        # พยางค์นี้มีสระแล้ว (พยัญชนะถัดไป = ตัวสะกด ถ้าไม่มีสระตามหลังมัน)
	var i := 0
	while i < n:
		var c := u[i]
		var nx := _at(u, _skip(u, i + 1))
		if SILENT.has(c) or c == KARAN:
			i += 1
			continue
		if LEAD.has(c):
			lead = c
			init = 0
			vowel = false
			i += 1
			continue
		if _after_vowel(c):
			for v: String in _vowel_codes(c):
				_push(out, v, T_CLOSE if v == "rest" else T_VOWEL)
			vowel = true
			i += 1
			continue
		if not _cons(c):
			i += 1                # ตัวเลข/อักษรอื่น: ข้าม
			continue
		if _at(u, i + 1) == KARAN:
			i += 2                # การันต์: ไม่ออกเสียง
			continue
		var opens := _after_vowel(nx) or (nx == O_ANG and lead == 0)
		if lead == 0 and vowel:
			if not _after_vowel(nx):
				# ตัวสะกด
				_push(out, _final_code(c), T_CLOSE if _final_code(c) == "rest" else T_CONS)
				vowel = false
				init = 0
				i += 1
				continue
		elif lead == 0 and init != 0:
			if c == O_ANG:
				_push(out, "O", T_VOWEL)       # อ เป็นสระ (พอ ก่อน)
				vowel = true
				i += 1
				continue
			if _cluster(init, c) and opens:
				_push(out, _init_code(c), T_CONS)   # อักษรควบ/ห นำ/อ นำ: ไม่มีสระในตัว
				init = c
				i += 1
				continue
			if opens:
				if init != O_ANG:
					_push(out, "A", T_VOWEL)       # สระอะในตัวของพยางค์ก่อน (สะ-วัด)
			else:
				_push(out, "O", T_VOWEL)           # สระโอะในตัว แล้วตัวนี้เป็นตัวสะกด (คน ผม)
				_push(out, _final_code(c), T_CLOSE if _final_code(c) == "rest" else T_CONS)
				init = 0
				vowel = false
				i += 1
				continue
		# พยัญชนะต้นใหม่ (อ ต้นคำไม่ออกเสียง)
		if c != O_ANG:
			_push(out, _init_code(c), T_CLOSE if _init_code(c) == "rest" else T_CONS)
		init = c
		vowel = false
		i += 1
		if lead != 0:
			var j := _skip(u, i)
			if j < n and _cons(u[j]) and _cluster(c, u[j]):
				_push(out, _init_code(u[j]), T_CONS)    # ควบหลังสระหน้า (เปล่า เกลียด)
				i = j + 1
				j = _skip(u, i)
			i = _lead_vowel(u, lead, j, out, i)
			lead = 0
			vowel = true
	if init != 0 and not vowel and init != O_ANG:
		_push(out, "O" if out.size() > 1 else "A", T_VOWEL)


## สระหน้า + สระที่ตามมา (เ-า เ-ีย เ-ือ เ-อ เ-ิ เ-ะ โ-ะ แ-ะ) · คืนตำแหน่งต่อไป
static func _lead_vowel(u: PackedInt32Array, lead: int, j: int, out: Array, i: int) -> int:
	var c1 := _at(u, j)
	var j2 := _skip(u, j + 1)
	var c2 := _at(u, j2)
	match lead:
		0x0E43, 0x0E44:          # ใ ไ
			_push(out, "A", T_VOWEL)
			_push(out, "I", T_CONS)
			return i
		0x0E42:                  # โ
			_push(out, "O", T_VOWEL)
			return j + 1 if c1 == SARA_A else i
		0x0E41:                  # แ
			_push(out, "E", T_VOWEL)
			return j + 1 if c1 == SARA_A else i
	# เ
	if c1 == SARA_AA:
		_push(out, "A", T_VOWEL)
		_push(out, "U", T_CONS)
		return j + 1
	if c1 == SARA_II and c2 == YO:
		_push(out, "I", T_CONS)
		_push(out, "A", T_VOWEL)
		return j2 + 1
	if c1 == SARA_UEE and c2 == O_ANG:
		_push(out, "E", T_CONS)
		_push(out, "A", T_VOWEL)
		return j2 + 1
	_push(out, "E", T_VOWEL)
	if c1 == O_ANG or c1 == SARA_I or c1 == SARA_A:
		return j + 1
	return i


# ---------------- อังกฤษ ----------------

static func _english(s: String, out: Array) -> void:
	var i := 0
	var n := s.length()
	var ws := 0               # ต้นคำปัจจุบัน
	while i < n:
		var c := s[i]
		var word_start := i == ws
		if c == " ":
			if not out.is_empty() and str(out[-1][0]) != "rest":
				_push(out, "rest", T_GAP)
			i += 1
			ws = i
			continue
		if PUNCT.contains(c):
			_push(out, "rest", T_PAUSE)
			i += 1
			ws = i
			continue
		if not ((c >= "a" and c <= "z") or (c >= "0" and c <= "9")):
			i += 1
			continue
		var pair := s.substr(i, 2)
		if pair.length() == 2 and EN_DIGRAPH.has(pair):
			for v: String in EN_DIGRAPH[pair]:
				var long := v in ["A", "E", "I", "O"] or pair == "oo"
				_push(out, v, T_VOWEL if long else T_CONS)
			i += 2
			continue
		if i > 0 and s[i - 1] == c and not EN_VOWEL.has(c):
			i += 1                # ตัวซ้ำ (ll ss tt) นับครั้งเดียว
			continue
		var end_word := i + 1 >= n or not (s[i + 1] >= "a" and s[i + 1] <= "z")
		if c == "e" and end_word and i - ws >= 3 and not EN_VOWEL.has(s[i - 1]):
			i += 1                # e ท้ายคำไม่ออกเสียง (make time)
			continue
		if EN_VOWEL.has(c):
			_push(out, EN_VOWEL[c], T_VOWEL)
		elif c == "y":
			if word_start:
				_push(out, "C", T_CONS)
			else:
				_push(out, "I", T_VOWEL)
		elif c >= "0" and c <= "9":
			_push(out, "C", T_CONS)
			_push(out, "A", T_VOWEL)
		elif c in ["b", "m", "p"]:
			_push(out, "rest", T_CLOSE)
		elif c in ["f", "v"]:
			_push(out, "F", T_CONS)
		elif c in ["w", "j"]:
			_push(out, "U", T_CONS)
		else:
			_push(out, "C", T_CONS)
		i += 1
