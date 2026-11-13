extends Control
## หน้าเล่นกับเพื่อน = ประตูเทียบยาน (NET_SPEC §7.2): ชื่อของตัวเอง, เปิดห้อง, ต่อด้วย IP (ใต้ชื่อ: แป้นพิมพ์บนจอไม่บัง),
## รายชื่อห้องใน Wi-Fi เดียวกัน (ไม่มี Wi-Fi = บอกให้ต่อ Wi-Fi), IP ตัวใหญ่พร้อมปุ่มคัดลอก,
## การ์ดห้อง (IP ของเจ้าห้อง ที่นั่งตอนเจ้าห้องตั้งเกม (ขึ้นก่อนรายชื่อ กดนั่งได้ทันที) คนในห้อง กองทัพที่อยากใช้)
## และออกจากห้อง/ปิดห้อง
## อ่านทุกอย่างจาก net (autoload Net; เทสใส่ของปลอมแบบเดียวกัน) ไม่เปิดช่องสื่อสารเอง: เปิดหน้า = net.find(true),
## ออก/ถูกบัง = net.find(false) · สามสถานะตาม net.state(): ค้นหา / กำลังเชื่อมต่อ / อยู่ในห้อง
## ถูกปฏิเสธหรือหลุด: เหตุผลแสดงในส่วนรายชื่อ แล้วกลับไปสถานะค้นหา (ข้อความจาก OnlineText)
## ชื่อผู้เล่นและ IP ที่พิมพ์ไม่แปล · ไม่มี _process (รายชื่อเปลี่ยนตามสัญญาณ ข้อความรอ 4 วิใช้ Timer)

const T_TITLE := "เล่นกับเพื่อน"
const T_NAME := "ชื่อของคุณ"
const T_HOST := "เปิดห้อง"
const T_FOUND := "ห้องที่พบใน Wi-Fi เดียวกัน"
const T_SEARCHING := "กำลังค้นหาห้อง…"
const T_NONE := "ยังไม่พบห้อง — ให้เพื่อนกดเปิดห้อง หรือใส่ IP ของเจ้าห้องด้านบน"
const T_ROOM := "ห้องของ {name}"
const T_COUNT := "{n}/{max} คน"
const T_JOIN := "เข้าร่วม"
const T_IP_HINT := "ใส่ IP ของเจ้าห้อง"
const T_IP_JOIN := "ต่อด้วย IP"
const T_HELP := "ต้องอยู่ Wi-Fi เดียวกัน · Windows: ถ้ามีหน้าต่างไฟร์วอลล์ ให้กดอนุญาต (เครือข่ายส่วนตัว)"
const T_CONNECTING := "กำลังเชื่อมต่อ…"
const T_CANCEL := "ยกเลิก"
const T_IPS := "IP ของเครื่องนี้: {ips}"
const T_HOST_HELP := "ให้เพื่อนที่อยู่ Wi-Fi เดียวกันกดประตูเทียบยานแล้วเลือกห้องนี้ หรือใส่ IP นี้"
const T_MEMBERS := "คนในห้อง"
const T_IS_HOST := "(เจ้าห้อง)"
const T_IS_YOU := "(คุณ)"
const T_PICK := "กองทัพที่อยากใช้: {army}"
const T_PICK_NONE := "ให้เจ้าห้องเลือก"
const T_SEATS := "ที่นั่ง"
const T_SEAT := "ทีม {n} · {owner} · {army}"
const T_SIT := "นั่งที่นี่"
const T_STAND := "ลุกจากที่นั่ง"
const T_BOT := "บอท"
const T_RANDOM := "สุ่ม"
const T_BACK := "กลับดาดฟ้า"
const T_LEAVE := "ออกจากห้อง"
const T_CLOSE := "ปิดห้อง"
const T_CLOSE_ASK := "ปิดห้อง? เพื่อนทุกคนจะหลุดจากห้อง"
const T_COPY := "คัดลอก IP"
const T_COPIED := "คัดลอกแล้ว"
const ROW_H := 56.0
const SWATCH := 22.0

@onready var margin: MarginContainer = %Margin
@onready var back_button: Button = %BackButton
@onready var title: Label = %Title
@onready var scroll: ScrollContainer = %Scroll
@onready var find_box: VBoxContainer = %FindBox
@onready var name_label: Label = %NameLabel
@onready var name_edit: LineEdit = %NameEdit
@onready var host_button: Button = %HostButton
@onready var found_panel: PanelContainer = %FoundPanel
@onready var found_title: Label = %FoundTitle
@onready var found_list: VBoxContainer = %FoundList
@onready var found_empty: Label = %FoundEmpty
@onready var reason_label: Label = %Reason
@onready var ip_edit: LineEdit = %IpEdit
@onready var ip_button: Button = %IpButton
@onready var help: Label = %Help
@onready var connect_box: HBoxContainer = %ConnectBox
@onready var connect_label: Label = %ConnectLabel
@onready var cancel_button: Button = %CancelButton
@onready var room_panel: PanelContainer = %RoomPanel
@onready var room_title: Label = %RoomTitle
@onready var room_note: Label = %RoomNote
@onready var host_ips: Label = %HostIps
@onready var copy_ip_button: Button = %CopyIpButton
@onready var host_help: Label = %HostHelp
@onready var disc_off: Label = %DiscOff
@onready var members_title: Label = %MembersTitle
@onready var member_list: VBoxContainer = %MemberList
@onready var pick_button: Button = %PickButton
@onready var seats_title: Label = %SeatsTitle
@onready var seat_list: VBoxContainer = %SeatList
@onready var leave_button: Button = %LeaveButton
@onready var confirm: Control = %Confirm
@onready var confirm_panel: PanelContainer = %ConfirmPanel
@onready var confirm_text: Label = %ConfirmText
@onready var confirm_yes: Button = %ConfirmYes
@onready var confirm_no: Button = %ConfirmNo
@onready var empty_timer: Timer = %EmptyTimer

## ระบบออนไลน์ (autoload Net หรือของปลอมในเทส; ตั้งก่อนเข้าต้นไม้ หรือเปลี่ยนทีหลังด้วย use_net)
var net: Node

var _reason_key := ""                # เหตุผลล่าสุดที่ต่อไม่ได้ (แปลใหม่ตอนสลับภาษา)
var _reason_args: Dictionary = {}
var _reason_row: Dictionary = {}     # แถวห้องที่รุ่นไม่ตรงที่ถูกแตะ
var _note_key := ""                  # บรรทัดบนการ์ดห้อง (กำลังต่อใหม่ / ต่อใหม่ได้แล้ว)
var _empty_long := false
var _finding := false
var _leaving := false


func _ready() -> void:
	var bg := get_node(^"Bg") as ColorRect
	bg.color = CandleStyle.BG
	CandleStyle.title(title, 40)
	for p: Control in [found_panel, room_panel, confirm_panel]:
		CandleStyle.panel(p)
	for l: Label in [name_label, found_title, members_title, seats_title, connect_label]:
		CandleStyle.text(l, 22)
	CandleStyle.title(room_title, 28)
	for l: Label in [found_empty, help, host_help, room_note]:
		CandleStyle.text(l, 18, true)
	CandleStyle.text(disc_off, 20)
	CandleStyle.title(host_ips, 28)   # IP ตัวใหญ่ อ่านข้ามโต๊ะได้
	CandleStyle.text(reason_label, 20)
	reason_label.add_theme_color_override(&"font_color", CandleStyle.DANGER)
	disc_off.add_theme_color_override(&"font_color", CandleStyle.DANGER)
	CandleStyle.title(confirm_text, 28)
	for b: Button in [back_button, ip_button, cancel_button, pick_button, leave_button, confirm_no, copy_ip_button]:
		CandleStyle.button(b)
	CandleStyle.button(host_button, true)
	CandleStyle.button(confirm_yes, true)
	for e: LineEdit in [name_edit, ip_edit]:
		e.add_theme_font_size_override(&"font_size", 22)
	back_button.pressed.connect(go_back)
	host_button.pressed.connect(host_room)
	ip_button.pressed.connect(join_ip)
	ip_edit.text_submitted.connect(func(_t: String) -> void: join_ip())
	cancel_button.pressed.connect(leave_room)
	pick_button.pressed.connect(cycle_pick)
	copy_ip_button.pressed.connect(copy_ip)
	leave_button.pressed.connect(_on_leave_pressed)
	confirm_yes.pressed.connect(func() -> void:
		confirm.hide()
		leave_room())
	confirm_no.pressed.connect(func() -> void: confirm.hide())
	name_edit.text_changed.connect(_on_name_changed)
	name_edit.text_submitted.connect(func(_t: String) -> void: _commit_name())
	name_edit.focus_exited.connect(_commit_name)
	empty_timer.one_shot = true
	empty_timer.timeout.connect(_on_empty_wait)
	confirm.hide()
	visibility_changed.connect(_on_visibility)
	get_viewport().size_changed.connect(_layout)
	use_net(net if net != null else get_node_or_null(^"/root/Net"))
	_layout()
	refresh()


func _enter_tree() -> void:
	_leaving = false


func _exit_tree() -> void:
	# ตั้งก่อนปิดรายชื่อ: net.find(false) ส่ง state_changed กลับมาทันที (ห้ามเปิดซ้ำระหว่างออก)
	_leaving = true
	_set_finding(false)


## ต่อกับระบบออนไลน์ n (null = ไม่มี: ปุ่มต่าง ๆ ไม่ทำอะไร)
func use_net(n: Node) -> void:
	var handlers := {"state_changed": _on_state, "members_changed": _on_members, "found_changed": _on_found,
		"refused": _on_refused, "lost": _on_lost, "reconnected": _on_reconnected, "message": _on_message}
	if net != null and is_instance_valid(net):
		for sig: String in handlers:
			if net.has_signal(sig) and net.is_connected(sig, handlers[sig]):
				net.disconnect(sig, handlers[sig])
	net = n
	if net != null:
		for sig: String in handlers:
			if net.has_signal(sig) and not net.is_connected(sig, handlers[sig]):
				net.connect(sig, handlers[sig])
	if is_node_ready():
		_finding = false
		refresh()


## สถานะของหน้า: "find" (ค้นหา/ออฟไลน์), "connecting", "room" (เปิดห้องหรืออยู่ในห้อง)
func view() -> String:
	var st := _state()
	if st == "connecting":
		return "connecting"
	if st == "hosting" or st == "joined" or st == "reconnecting":
		return "room"
	return "find"


## วาดข้อความทั้งหมดใหม่ตามภาษา แล้วจัดรายการตามสถานะของ net
func refresh() -> void:
	title.text = I18n.t(T_TITLE)
	back_button.text = I18n.t(T_BACK)
	name_label.text = I18n.t(T_NAME)
	host_button.text = I18n.t(T_HOST)
	found_title.text = I18n.t(T_FOUND)
	ip_edit.placeholder_text = I18n.t(T_IP_HINT)
	ip_button.text = I18n.t(T_IP_JOIN)
	help.text = I18n.t(T_HELP)
	connect_label.text = I18n.t(T_CONNECTING)
	cancel_button.text = I18n.t(T_CANCEL)
	members_title.text = I18n.t(T_MEMBERS)
	seats_title.text = I18n.t(T_SEATS)
	confirm_text.text = I18n.t(T_CLOSE_ASK)
	confirm_yes.text = I18n.t(T_CLOSE)
	confirm_no.text = I18n.t(T_CANCEL)
	disc_off.text = I18n.t(OnlineText.NO_DISCOVERY)
	if net != null and not name_edit.has_focus():
		var nm := str(net.call("my_name"))
		if nm == "":
			nm = str(net.call("set_my_name", OnlineText.default_name(randi_range(100, 999))))
		name_edit.text = nm
	_update()


## ปุ่มย้อนกลับ/Esc: ปิดกล่องถามก่อน ไม่มีกล่องก็ให้ App ถอยกลับดาดฟ้า (ยังอยู่ในห้อง)
func handle_back() -> bool:
	if confirm.visible:
		confirm.hide()
		return true
	return false


func go_back() -> void:
	if confirm.visible:
		confirm.hide()
		return
	if App.current() == self:
		App.pop()


func host_room() -> void:
	if net == null:
		return
	_commit_name()
	_clear_reason()
	net.call("host")
	_update()


## เข้าห้องจากรายชื่อ: แถวที่รุ่นไม่ตรงแค่บอกเหตุผล ไม่ต่อ
func join_row(row: Dictionary) -> void:
	if net == null:
		return
	if not bool(row.get("ok", true)):
		_reason_row = row
		_reason_key = ""
		_update()
		return
	_commit_name()
	_clear_reason()
	net.call("join", str(row.get("ip", "")), int(row.get("port", 0)))
	_update()


## ต่อด้วย IP ที่พิมพ์ (IPv4 จุดสี่ช่อง กับ :พอร์ต ได้; ไม่รับชื่อโฮสต์)
func join_ip() -> void:
	if net == null:
		return
	var parsed := NetGate.parse_ip(ip_edit.text)
	if parsed.is_empty():
		_set_reason("bad_ip", {})
		return
	_commit_name()
	_clear_reason()
	net.call("join", str(parsed["ip"]), int(parsed["port"]))
	_update()


func leave_room() -> void:
	if net == null:
		return
	net.call("leave")
	_update()


## กองทัพที่อยากใช้: ให้เจ้าห้องเลือก → กองทัพตามลำดับบนจอ → กลับมาให้เจ้าห้องเลือก
func cycle_pick() -> void:
	if net == null:
		return
	var facs := GameData.factions()
	var i := facs.find(_my_pick())
	net.call("set_pick", facs[i + 1] if i + 1 < facs.size() else "")
	_update()


## คัดลอก IP ของเครื่องนี้ (อันแรก) ไปคลิปบอร์ด ส่งต่อทางแชตได้
func copy_ip() -> void:
	if net == null:
		return
	var ips: PackedStringArray = net.call("local_ips")
	if ips.is_empty():
		return
	DisplayServer.clipboard_set(ips[0])
	copy_ip_button.text = I18n.t(T_COPIED)   # จนการ์ดห้องวาดใหม่ครั้งถัดไป


## นั่งที่ k (−1 = ลุกจากที่นั่งของตัวเอง) ตอนเจ้าห้องเปิดหน้าตั้งเกม
func claim(k: int) -> void:
	if net != null:
		net.call("claim", k)


## เหตุผลที่โชว์อยู่ ("" = ไม่มี) สำหรับเทส
func reason_text() -> String:
	return reason_label.text if reason_label.visible else ""


# ---- ภายใน ----

func _update() -> void:
	var v := view()
	# รายชื่อห้องเปิดอยู่ตลอดที่หน้านี้โชว์และยังไม่อยู่ในห้อง
	_set_finding(is_visible_in_tree() and v != "room")
	find_box.visible = v == "find"
	connect_box.visible = v == "connecting"
	room_panel.visible = v == "room"
	if v != "find":
		empty_timer.stop()
	if v == "room":
		_reason_key = ""
		_reason_row = {}
		_update_room()
	else:
		_note_key = ""
	_update_found()
	_update_reason()


func _update_found() -> void:
	for c in found_list.get_children():
		found_list.remove_child(c)
		c.queue_free()
	var rows: Array = net.call("found") if net != null else []
	for r: Dictionary in rows:
		found_list.add_child(_found_row(r))
	found_list.visible = not rows.is_empty()
	found_empty.visible = rows.is_empty()
	if rows.is_empty() and _no_lan():
		found_empty.text = OnlineText.reason("no_lan")   # เครื่องนี้ไม่ได้ต่อ Wi-Fi (เน็ตมือถืออย่างเดียว): บอกตรง ๆ
	elif rows.is_empty():
		found_empty.text = I18n.t(T_NONE if _empty_long else T_SEARCHING)
		if view() == "find" and not _empty_long and empty_timer.is_stopped() and is_visible_in_tree() and not _leaving:
			empty_timer.start()
	else:
		empty_timer.stop()
		_empty_long = false


func _found_row(r: Dictionary) -> Control:
	var ok := bool(r.get("ok", true))
	var row := HBoxContainer.new()
	row.name = "Room_%s" % str(r.get("t", r.get("ip", "")))
	row.add_theme_constant_override(&"separation", 12)
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override(&"separation", 0)
	var nm := Label.new()
	nm.name = "RoomName"
	nm.text = I18n.t(T_ROOM).format({"name": str(r.get("nm", ""))})
	CandleStyle.text(nm, 22)
	col.add_child(nm)
	var count := Label.new()
	count.name = "RoomCount"
	count.text = I18n.t(T_COUNT).format({"n": int(r.get("n", 0)), "max": int(r.get("max", 0))})
	CandleStyle.text(count, 18, true)
	col.add_child(count)
	if not ok:
		var why := Label.new()
		why.name = "RoomWhy"
		why.text = OnlineText.row_reason(r)
		why.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		CandleStyle.text(why, 18)
		why.add_theme_color_override(&"font_color", CandleStyle.DANGER)
		col.add_child(why)
		nm.modulate.a = 0.55
		count.modulate.a = 0.55
	row.add_child(col)
	var b := Button.new()
	b.name = "JoinButton"
	b.text = I18n.t(T_JOIN)
	CandleStyle.button(b, ok)
	b.custom_minimum_size = Vector2(160, ROW_H)
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	if not ok:
		b.modulate.a = 0.55
	b.pressed.connect(join_row.bind(r))
	row.add_child(b)
	return row


func _update_room() -> void:
	var host := bool(net.call("is_host"))
	var me := int(net.call("my_slot"))
	var hm: Dictionary = net.call("member", 0)
	room_title.text = I18n.t(T_ROOM).format({"name": str(hm.get("nm", ""))})
	var note := _note_key
	if _state() == "reconnecting":
		note = OnlineText.REASONS["reconnecting"]
	room_note.visible = note != ""
	room_note.text = I18n.t(note) if note != "" else ""
	host_ips.visible = host
	copy_ip_button.visible = host
	host_help.visible = host
	disc_off.visible = host and not bool(net.call("discovery_on"))
	if host:
		var ips: PackedStringArray = net.call("local_ips")
		host_ips.text = I18n.t(T_IPS).format({"ips": ", ".join(ips) if not ips.is_empty() else "—"})
		copy_ip_button.disabled = ips.is_empty()
		copy_ip_button.text = I18n.t(T_COPY)
		host_help.text = I18n.t(T_HOST_HELP)
	for c in member_list.get_children():
		member_list.remove_child(c)
		c.queue_free()
	for m: Dictionary in net.call("members"):
		member_list.add_child(_member_row(m, me))
	pick_button.visible = not host
	if not host:
		pick_button.text = I18n.t(T_PICK).format({"army": _army_name(_my_pick(), T_PICK_NONE)})
	for c in seat_list.get_children():
		seat_list.remove_child(c)
		c.queue_free()
	var seats: Array = net.call("setup_seats") if not host and str(net.call("room_state")) == "setup" else []
	seats_title.visible = not seats.is_empty()
	seat_list.visible = not seats.is_empty()
	for k in seats.size():
		seat_list.add_child(_seat_row(k, seats[k], me))
	leave_button.text = I18n.t(T_CLOSE if host else T_LEAVE)


func _member_row(m: Dictionary, me: int) -> Control:
	var slot := int(m.get("slot", -1))
	var row := HBoxContainer.new()
	row.name = "Member_%d" % slot
	row.add_theme_constant_override(&"separation", 12)
	var sw := ColorRect.new()
	sw.name = "Swatch"
	sw.color = HallWorld.slot_colour(slot)
	sw.custom_minimum_size = Vector2(SWATCH, SWATCH)
	sw.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(sw)
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override(&"separation", 0)
	var nm := Label.new()
	nm.name = "MemberName"
	var tag := ""
	if slot == 0:
		tag = " " + I18n.t(T_IS_HOST)
	if slot == me:
		tag += " " + I18n.t(T_IS_YOU)
	nm.text = str(m.get("nm", "")) + tag
	CandleStyle.text(nm, 22)
	col.add_child(nm)
	var where := Label.new()
	where.name = "MemberWhere"
	where.text = I18n.t(OnlineText.REASONS["reconnecting"]) if not bool(m.get("here", true)) else OnlineText.where_text(str(m.get("where", "deck")))
	CandleStyle.text(where, 18, true)
	col.add_child(where)
	row.add_child(col)
	return row


func _seat_row(k: int, s: Dictionary, me: int) -> Control:
	var owner := int(s.get("owner", -1))
	var row := HBoxContainer.new()
	row.name = "Seat_%d" % k
	row.add_theme_constant_override(&"separation", 12)
	var who := I18n.t(T_BOT)
	if owner == me:
		who = I18n.t(T_IS_YOU)
	elif owner >= 0:
		who = str((net.call("member", owner) as Dictionary).get("nm", "?"))
	var l := Label.new()
	l.name = "SeatText"
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.custom_minimum_size.y = ROW_H
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.text = I18n.t(T_SEAT).format({"n": int(s.get("team", 0)) + 1, "owner": who, "army": _army_name(str(s.get("fac", "")), T_RANDOM)})
	CandleStyle.text(l, 20)
	row.add_child(l)
	if owner < 0 or owner == me:
		var b := Button.new()
		b.name = "SitButton" if owner < 0 else "StandButton"
		b.text = I18n.t(T_SIT if owner < 0 else T_STAND)
		CandleStyle.button(b, owner < 0)
		b.custom_minimum_size = Vector2(200, ROW_H)
		b.pressed.connect(claim.bind(k if owner < 0 else -1))
		row.add_child(b)
	return row


func _update_reason() -> void:
	var text := ""
	if not _reason_row.is_empty():
		text = OnlineText.row_reason(_reason_row)
	elif _reason_key != "":
		text = OnlineText.reason(_reason_key, _reason_args)
	reason_label.text = text
	reason_label.visible = text != "" and view() == "find"


func _set_reason(key: String, args: Dictionary) -> void:
	_reason_key = key
	_reason_args = args
	_reason_row = {}
	_update()


func _clear_reason() -> void:
	_reason_key = ""
	_reason_args = {}
	_reason_row = {}


func _army_name(fac: String, none_key: String) -> String:
	if fac == "":
		return I18n.t(none_key)
	return I18n.t(str(GameData.faction(fac).get("nm", fac)))


func _my_pick() -> String:
	if net == null:
		return ""
	return str((net.call("member", int(net.call("my_slot"))) as Dictionary).get("pick", ""))


## ไม่มีเครือข่ายในบ้าน (Wi-Fi/ฮอตสปอต/สายแลน) บนเครื่องนี้
func _no_lan() -> bool:
	return net != null and net.has_method("has_lan") and not bool(net.call("has_lan"))


func _state() -> String:
	return str(net.call("state")) if net != null and is_instance_valid(net) else "off"


func _on_leave_pressed() -> void:
	if net != null and bool(net.call("is_host")):
		confirm.show()
	else:
		leave_room()


## ชื่อที่พิมพ์ส่งให้ net ทุกครั้งที่เปลี่ยน (net ทำความสะอาดและบันทึก) แต่ไม่เขียนกลับระหว่างพิมพ์
func _on_name_changed(t: String) -> void:
	if net != null and t.strip_edges() != "":
		net.call("set_my_name", t)


## ออกจากช่องชื่อ: ใช้ชื่อที่ทำความสะอาดแล้ว ว่างเปล่าได้ชื่อเริ่มต้น
func _commit_name() -> void:
	if net == null:
		return
	var t := name_edit.text
	if t.strip_edges() == "":
		t = OnlineText.default_name(randi_range(100, 999))
	name_edit.text = str(net.call("set_my_name", t))


func _set_finding(on: bool) -> void:
	# ออกจากต้นไม้แล้ว (ถูกปิด) ห้ามเปิดรายชื่อห้องกลับขึ้นมา
	if net == null or on == _finding or (on and _leaving):
		return
	_finding = on
	net.call("find", on)


func _on_visibility() -> void:
	if is_visible_in_tree():
		refresh()
	else:
		_set_finding(false)
		confirm.hide()
		empty_timer.stop()


func _on_empty_wait() -> void:
	_empty_long = true
	_update_found()


func _on_state(_s: StringName) -> void:
	_update()


func _on_members() -> void:
	_update()


func _on_found() -> void:
	if view() == "find":
		_update_found()


func _on_refused(key: String, args: Dictionary) -> void:
	_set_reason(key, args)


func _on_lost(key: String) -> void:
	_set_reason(key, {})


func _on_reconnected() -> void:
	_note_key = OnlineText.REASONS["reconnected"]
	_update()


func _on_message(_from: int, kind: int, _body: Dictionary) -> void:
	if kind == NetProto.SETUP and view() == "room":
		_update_room()


func _layout() -> void:
	CandleStyle.safe_margins(margin)
