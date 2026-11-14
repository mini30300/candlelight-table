// ขอบแสงของตัวละครในฉากโชว์ (material_overlay บวกสี): ขอบที่หันออกจากกล้องสว่าง ตัวแยกจากฉากหลังมืด · ไม่มี TIME
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_back, shadows_disabled, fog_disabled;

uniform vec3 colour = vec3(0.5, 0.55, 0.65);
uniform float power = 3.0;
uniform float strength = 1.0;
uniform vec3 side = vec3(0.0);   // เอนขอบแสงไปทางนี้ (พิกัดกล้อง) · 0 = รอบตัว

void fragment() {
	float f = pow(1.0 - clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0), power);
	float s = 1.0;
	if (length(side) > 0.0) {
		s = clamp(dot(normalize(NORMAL), normalize(side)) * 0.6 + 0.55, 0.0, 1.0);
	}
	ALBEDO = colour;
	ALPHA = clamp(f * s * strength, 0.0, 1.0);
}
