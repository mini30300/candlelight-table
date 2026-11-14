// เงาให้ตัวละครที่ไม่คิดแสง (ไข่ ตัวสีเรียบ) ในฉากโชว์: overlay แบบคูณสี ด้านที่หันหาไฟสว่าง ด้านอื่นมืดลง · ไม่มี TIME
shader_type spatial;
render_mode unshaded, blend_mul, depth_draw_never, cull_back, shadows_disabled, fog_disabled;

uniform vec3 light_dir = vec3(0.0, 1.0, 0.15);   // ทิศไปหาไฟ (world)
uniform float dark = 0.24;                       // ด้านมืดสุด (คูณ)

void fragment() {
	vec3 l = normalize((VIEW_MATRIX * vec4(normalize(light_dir), 0.0)).xyz);
	float f = clamp(dot(normalize(NORMAL), l) * 0.6 + 0.4, 0.0, 1.0);
	ALBEDO = vec3(mix(dark, 0.92, f));
}
