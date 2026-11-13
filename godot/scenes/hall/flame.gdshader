// flame.gdshader — เปลวเทียนในห้องโถง (hi/mid เท่านั้น; lo/min ใช้วัสดุธรรมดาที่ไม่มี TIME)
// เปลวไฟทุกดวงอยู่ใน MultiMesh เดียว: INSTANCE_CUSTOM.x = เฟสสุ่มต่อดวง (0..1) ให้ไหวไม่พร้อมกัน
// สีจุดยอด (COLOR) เป็น sRGB; Compatibility renderer แสดง ALBEDO ตรง ๆ เหมือนวัสดุมาตรฐาน (วัดแล้ว)
shader_type spatial;
render_mode unshaded, cull_disabled, fog_disabled;

uniform float wobble = 0.22;     // ยืดหดตามแนวตั้งมากสุด (สัดส่วน)
uniform float sway = 0.012;      // ส่ายข้างที่ยอด (เมตร)

void vertex() {
	float ph = INSTANCE_CUSTOM.x * 6.2832;
	float h = clamp(VERTEX.y / 0.155, 0.0, 1.0);
	float s = 1.0 + wobble * h * (0.6 * sin(TIME * 8.3 + ph) + 0.4 * sin(TIME * 17.9 + ph * 2.1));
	VERTEX.y *= s;
	VERTEX.xz *= 1.0 - 0.3 * (s - 1.0);
	VERTEX.x += sway * h * sin(TIME * 5.7 + ph * 3.1);
	VERTEX.z += sway * 0.6 * h * sin(TIME * 4.3 + ph * 1.7);
}

void fragment() {
	ALBEDO = COLOR.rgb;
}
