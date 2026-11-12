// telegraph.gdshader — เขตตะปบของสัตว์รังบนพื้นตอนง้าง (ทุกระดับ ไม่มีเวลาในตัว: ค่า fill มาจากสคริปต์ตอนง้างเท่านั้น)
// ขอบ = ระยะและมุมจริงของกรงเล็บ (strike_reach, ±strike_half_angle) สว่างตลอด · เนื้อในลามจากตัวออกไปถึงขอบพอดีตอนง้างครบ
// UV.x = ระยะจากตัว ÷ ระยะถึงขอบใน, UV.y = 1 บนขอบ 0 บนเนื้อ (HiveBeast._build_ring)
shader_type spatial;
render_mode unshaded, cull_disabled, blend_mix, depth_draw_never, fog_disabled;

uniform vec3 dim : source_color = vec3(0.40, 0.04, 0.03);
uniform vec3 hot : source_color = vec3(1.0, 0.16, 0.08);
uniform float fill = 0.0;
uniform float fill_alpha = 0.42;

void fragment() {
	if (UV.y < 0.5 && UV.x > fill) {
		discard;
	}
	ALBEDO = mix(dim, hot, fill);
	ALPHA = UV.y > 0.5 ? 0.95 : fill_alpha;
}
