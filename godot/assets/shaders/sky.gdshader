// ท้องฟ้าของโต๊ะ (table/sky.gd ตั้งค่าจาก data/sky.json): ไล่สีเรียบ ฟ้าบน -> ขอบฟ้า, ใต้ขอบฟ้าเป็นที่ราบในหมอก,
// แสงเรืองรอบดวงอาทิตย์, เส้นขอบฟ้าไกล/ใกล้จากเท็กซ์เจอร์ความสูง 720 จุดรอบตัว (เปิดเฉพาะ mid/hi)
shader_type sky;

uniform vec3 top_col : source_color = vec3(0.1, 0.09, 0.15);
uniform vec3 hor_col : source_color = vec3(0.42, 0.29, 0.33);
uniform vec3 fog_col : source_color = vec3(0.31, 0.24, 0.25);
uniform vec3 plain_col : source_color = vec3(0.11, 0.1, 0.09);
uniform vec3 glow_col : source_color = vec3(1.0, 0.59, 0.38);
uniform vec3 far_col : source_color = vec3(0.23, 0.19, 0.25);
uniform vec3 near_col : source_color = vec3(0.15, 0.13, 0.19);
uniform vec3 sun_dir = vec3(0.0, 0.1, 1.0);
uniform bool skyline_on = false;
uniform sampler2D skyline_tex : filter_linear, repeat_enable;
uniform float skyline_max = 0.25;

void sky() {
	vec3 d = normalize(EYEDIR);
	float e = asin(clamp(d.y, -1.0, 1.0));
	vec3 col;
	if (e >= 0.0) {
		// ฟ้า: ขอบฟ้าถึงฟ้าบนภายใน ~0.8 เรเดียน (ราวไล่สีของหน้าเก่าที่ 1.2 เท่าความสูงจอ)
		col = mix(hor_col, top_col, clamp(e / 0.8, 0.0, 1.0));
		float k = acos(clamp(dot(d, normalize(sun_dir)), -1.0, 1.0)) / 0.7;
		float g = k < 0.25 ? mix(0.55, 0.18, k / 0.25) : mix(0.18, 0.0, clamp((k - 0.25) / 0.75, 0.0, 1.0));
		col = mix(col, glow_col, g);
		if (skyline_on) {
			vec2 h = texture(skyline_tex, vec2(atan(d.x, d.z) / TAU, 0.5)).rg * skyline_max;
			if (e < h.r) {
				col = far_col;
			}
			if (e < h.g) {
				col = near_col;
			}
		}
	} else {
		// ที่ราบ: หมอกที่ขอบฟ้า เข้มลงเมื่อมองต่ำลง
		float t = clamp(-e / 0.5, 0.0, 1.0);
		vec3 mid = mix(fog_col, plain_col, 0.55);
		col = t < 0.3 ? mix(fog_col, mid, t / 0.3) : mix(mid, plain_col, (t - 0.3) / 0.7);
	}
	COLOR = col;
}
