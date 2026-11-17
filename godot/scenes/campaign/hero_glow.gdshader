// แสงฟุ้งแบบบวกสีของฉากโชว์ (ไม่มี TIME): 0 = วงกลมฟุ้ง, 1 = ลำแสงทรงกรวย (จางลงล่าง ขอบนุ่ม), 2 = แถบหมอก, 3 = วงแหวน
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

uniform vec3 colour = vec3(1.0);
uniform float strength = 1.0;
uniform int mode = 0;
uniform float ring = 0.8;       // mode 3: รัศมีวง (0..1 ของครึ่งกว้าง)
uniform float width = 0.12;     // mode 3: ความหนาวง

void fragment() {
	vec2 uv = UV;
	float a = 0.0;
	if (mode == 0) {
		float r = length(uv - 0.5) * 2.0;
		a = 1.0 - smoothstep(0.0, 1.0, r);
		a *= a;
	} else if (mode == 1) {
		float face = abs(dot(normalize(NORMAL), normalize(VIEW)));
		a = pow(1.0 - uv.y, 1.6) * pow(face, 2.0);
	} else if (mode == 2) {
		float s = sin(uv.y * PI);
		a = s * s * smoothstep(0.0, 0.3, uv.x) * smoothstep(1.0, 0.7, uv.x);
	} else {
		float r = length(uv - 0.5) * 2.0;
		a = 1.0 - smoothstep(0.0, width, abs(r - ring));
	}
	ALBEDO = colour;
	ALPHA = clamp(a * strength, 0.0, 1.0);
}
