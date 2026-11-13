class_name ArenaSound
extends RefCounted
## เสียงของอารีน่าผ่าน autoload Sfx (audio/sfx.gd): ชื่อเสียงของอารีน่า → ชนิดเสียงของหน้าเก่าใน ArenaData.SOUNDS
## ไม่มี Sfx (เทสบางชุด แอปที่ยังไม่มีเสียง) = เงียบ ไม่พัง · เสียงเป็นแค่ภาพ/เสียง ไม่แตะกติกา · static ล้วน


## [ชนิด, ความดัง, ระดับเสียง] ของชื่อนี้ หรือ [] ถ้าไม่รู้จัก
static func spec(id: String) -> Array:
	return ArenaData.SOUNDS.get(id, [])


static func sfx(n: Node) -> Node:
	if n == null or not n.is_inside_tree():
		return null
	return n.get_node_or_null(^"/root/Sfx")


## เล่นครั้งเดียว · at = จุดในโลก (Vector3) หรือ null (ไม่มีทิศ) · คืน true เมื่อ Sfx รับเล่น
static func play(n: Node, id: String, at: Variant = null) -> bool:
	var s := sfx(n)
	var sp := spec(id)
	if s == null or sp.is_empty() or not s.has_method(&"play"):
		return false
	var kind := StringName(str(sp[0]))
	if s.get_method_argument_count(&"play") >= 4:
		return bool(s.call(&"play", kind, at, float(sp[1]), float(sp[2])))
	return bool(s.call(&"play", kind, at))


## เสียงวน (เช่นดาบเลื่อยตอนถือ) จนกว่าจะ stop หรือ owner ออกจากต้นไม้ · คืนเลข (0 = ไม่ได้เล่น)
static func loop(n: Node, id: String) -> int:
	var s := sfx(n)
	var sp := spec(id)
	if s == null or sp.is_empty() or not s.has_method(&"loop"):
		return 0
	return int(s.call(&"loop", StringName(str(sp[0])), n, null))


static func stop(n: Node, loop_id: int) -> void:
	if loop_id <= 0:
		return
	var tree := Engine.get_main_loop() as SceneTree
	var s: Node = tree.root.get_node_or_null(^"Sfx") if tree != null else null
	if s != null and s.has_method(&"stop_loop"):
		s.call(&"stop_loop", loop_id)
