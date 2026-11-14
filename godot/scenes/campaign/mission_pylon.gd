class_name MissionPylon
extends StaticBody3D
## เสาพิธีกรรมของค่ายลัทธิมืด (CAMPAIGN_SPEC §2.4, track C): ตัวชนชั้น 8 (กระสุนและดาบโดน) · พลังชีวิตอยู่ใน MissionObjectives
## take_hit ส่งต่อให้โลก (MissionWorld.pylon_hit) ตามสัญญาเดียวกับศัตรู · ไม่มีงานต่อเฟรม ไม่มีข้อความไทย

var world: Node3D


func take_hit(hit: Dictionary) -> Dictionary:
	if world == null or not world.has_method(&"pylon_hit"):
		return {"applied": 0, "hp": 0, "killed": false}
	return world.call(&"pylon_hit", self, hit)


func index() -> int:
	return int(get_meta("i", -1))
