// พื้นโต๊ะ: ตารางหมากรุกช่องละ 2 ม. + ลายสุ่ม + เส้นทุก 10 ม. (คำนวณจากตำแหน่งโลก ไม่ใช้เท็กซ์เจอร์)
shader_type spatial;
render_mode cull_back;

uniform vec3 colour_a : source_color = vec3(0.36, 0.44, 0.24);
uniform vec3 colour_b : source_color = vec3(0.30, 0.38, 0.20);
uniform vec3 line_colour : source_color = vec3(0.18, 0.16, 0.12);
uniform float cell = 2.0;
uniform float grid = 10.0;

varying vec3 world_pos;

float hash2(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash2(i);
	float b = hash2(i + vec2(1.0, 0.0));
	float c = hash2(i + vec2(0.0, 1.0));
	float d = hash2(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = world_pos.xz;
	float checker = mod(floor(p.x / cell) + floor(p.y / cell), 2.0);
	vec3 col = mix(colour_a, colour_b, checker);
	float n = value_noise(p * 1.7) * 0.6 + value_noise(p * 7.3) * 0.4;
	col *= 0.82 + 0.36 * n;
	vec2 g = abs(fract(p / grid + 0.5) - 0.5) * grid;
	float line = 1.0 - smoothstep(0.03, 0.09, min(g.x, g.y));
	col = mix(col, line_colour, line * 0.7);
	ALBEDO = col;
	ROUGHNESS = 0.92;
	SPECULAR = 0.15;
}
