// ship_drift.gdshader — ยานไกลลอยผ่านหน้าต่าง (hi/mid เท่านั้น; lo ใช้วัสดุธรรมดา ยานจอดนิ่ง, min ไม่มียาน)
// ยานทุกลำอยู่ใน MultiMesh เดียว: INSTANCE_CUSTOM = (ความเร็ว ม./วิ, เฟส ม., ช่วงลอย ม., ความยาวลำ ม.)
// ตำแหน่งของ instance = กลางช่วงลอย; ยานเลื่อนตามแกน x ของตัวเอง (= ทิศหัวเรือ) ย่อเหลือศูนย์ช่วง 8 % แรกและท้าย
shader_type spatial;
render_mode unshaded, cull_back, fog_disabled;

void vertex() {
	vec4 c = INSTANCE_CUSTOM;
	float span = max(c.z, 0.001);
	float s = mod(TIME * c.x + c.y, span);
	float k = clamp(min(s, span - s) / (0.08 * span), 0.0, 1.0);
	VERTEX *= k;
	VERTEX.x += (s - span * 0.5) / max(c.w, 0.001);
}

void fragment() {
	ALBEDO = COLOR.rgb;
}
