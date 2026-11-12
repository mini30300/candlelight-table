// holo.gdshader — ชั้นโฮโลแกรมเหนือโต๊ะรบ (hi/mid เท่านั้น; lo/min ใช้วัสดุธรรมดาทึบที่ไม่มี TIME)
// สีบวกเพิ่ม (blend_add) ไม่เขียนความลึก: กะพริบเบา ๆ + แถบสว่างเลื่อนขึ้นตามความสูง
// สีจุดยอด (COLOR) เป็น sRGB แสดงตรง ๆ แบบเดียวกับ flame.gdshader
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, fog_disabled;

uniform float base_y = 1.18;     // ระดับตาราง (ม.)
uniform float band_h = 0.42;     // ช่วงความสูงที่แถบเลื่อนผ่าน

varying float vy;
varying float vx;

void vertex() {
	vy = VERTEX.y;
	vx = VERTEX.x;
}

void fragment() {
	float flicker = 0.8 + 0.2 * sin(TIME * 3.1 + vx * 0.7);
	float h = (vy - base_y) / band_h;
	float band = 1.0 - smoothstep(0.0, 0.12, abs(fract(TIME * 0.4) - h));
	ALBEDO = COLOR.rgb * flicker * (1.0 + 0.6 * band);
}
