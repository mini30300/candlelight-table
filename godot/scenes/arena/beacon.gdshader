// beacon.gdshader — โคมสัญญาณอำพันเหนือสวิตช์บอท (hi/mid เท่านั้น ตอนบอทเปิด; lo/min ใช้วัสดุธรรมดาที่ไม่มี TIME)
// แถบแสงหมุนรอบโคม: UV.x = มุมรอบแกนตั้ง (0..1) จาก ArenaBuilder.beacon_mesh
shader_type spatial;
render_mode unshaded, cull_disabled, fog_disabled;

uniform vec3 lamp = vec3(1.0, 0.72, 0.30);
uniform float speed = 0.9;       // รอบต่อวินาที

void fragment() {
	float a = fract(UV.x - TIME * speed);
	float band = smoothstep(0.0, 0.18, a) * (1.0 - smoothstep(0.18, 0.42, a));
	ALBEDO = lamp * (0.45 + 0.9 * band);
}
