// ฉากหลังของฉากโชว์บนการ์ดความยาก: ไล่เฉดแนวตั้งตามจอ + แสงฟุ้งวงกลม + ขอบมืด · คิดตามพิกัดจอ จึงได้ทั้งการ์ดกว้างและแนวตั้ง
// ไม่มี TIME (ไม่มีงานต่อเฟรมเพิ่ม) · ไม่โดนหมอก · สีเป็นค่าที่จอแสดงตรง ๆ (Compatibility ไม่แปลง sRGB)
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, fog_disabled, shadows_disabled;

uniform vec3 top_colour = vec3(0.16, 0.16, 0.17);
uniform vec3 bottom_colour = vec3(0.01, 0.01, 0.012);
uniform vec3 glow_colour = vec3(0.2, 0.2, 0.21);
uniform vec2 glow_at = vec2(0.5, 0.1);      // จุดกลางแสงฟุ้ง (uv จอ: 0,0 = ซ้ายบน)
uniform float glow_r = 0.6;                 // รัศมี (สัดส่วนของด้านสั้นของจอ)
uniform float vignette = 0.6;

void fragment() {
	vec2 uv = SCREEN_UV;
	vec3 c = mix(top_colour, bottom_colour, clamp(uv.y, 0.0, 1.0));
	vec2 d = (uv - glow_at) * VIEWPORT_SIZE / min(VIEWPORT_SIZE.x, VIEWPORT_SIZE.y);
	float g = 1.0 - smoothstep(0.0, glow_r, length(d));
	c += glow_colour * g * g;
	vec2 v = uv - 0.5;
	c *= clamp(1.0 - vignette * dot(v, v) * 2.0, 0.0, 1.0);
	ALBEDO = c;
}
