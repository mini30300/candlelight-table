// soldier_inner.gdshader — ชั้นในของทหารที่เห็นผ่านแผล (เนื้อ/กระดูก): ไม่รับไฟจากฉาก คิดแสงเองแบบผิว ไม่มี TIME
//   ซ่อนอยู่ (visible = false) จนกว่าจะมีแผล ; ฟังก์ชันแผลชุดเดียวกับ soldier_skin.gdshader (ขอบผิวขาดที่ระยะ 1)
//   ด้านหน้า: วาดเฉพาะในระยะ keep ของแผล ; core > 0 (เนื้อ) = ทิ้งแกนแผลให้เห็นกระดูก + แถบไขมันใต้ขอบผิว
//   ด้านใน (หน้าหลัง): เนื้อ = โพรงแดงคล้ำ (พื้นของแผล) เฉพาะที่เส้นสายตาผ่านทรงกลมแผล (ที่อื่นผิวยุบตามท่าแก้
//   แล้วเนื้อโผล่เป็นขอบดำ) ; กระดูก (core = 0) = ไขกระดูกตรงรอยตัด ทิ้งนอก keep
shader_type spatial;
render_mode unshaded, cull_disabled;

uniform vec3 sun_dir = vec3(0.2, 1.0, 0.3);           // ทิศไปหาดวงอาทิตย์ (world)
uniform vec3 sun_colour = vec3(0.62, 0.64, 0.68);
uniform vec3 ambient_colour = vec3(0.34, 0.36, 0.42);
uniform vec3 base_colour = vec3(0.50, 0.07, 0.06);     // เนื้อแดงเปียก (กระดูก: ขาวงาช้าง)
uniform vec3 inner_colour = vec3(0.13, 0.015, 0.012);  // ด้านใน: โพรง (กระดูก: ไขกระดูก)
uniform vec3 fat_colour = vec3(0.80, 0.66, 0.36);      // แถบไขมันใต้ขอบผิว
uniform float core = 0.55;                             // แกนแผลที่เนื้อถูกตัด (เท่าของรัศมี) ; 0 = ชั้นกระดูก
uniform float keep = 1.2;                              // วาดด้านหน้าเฉพาะในระยะนี้ (เท่าของรัศมี)
uniform float fat_band = 1.0;                          // 1 = มีแถบไขมัน
uniform float wet = 0.5;                               // ความเงาเปียก
uniform int wound_count = 0;
uniform vec4 wounds[8];
uniform vec4 wound_rot[8];

varying vec3 v_pos;
varying vec3 v_light;

// ---- แผล (เหมือนกันทุกตัวอักษรใน soldier_skin.gdshader) ----
float w_hash(vec3 p) {
	p = fract(p * 0.3183099 + vec3(0.71, 0.113, 0.419));
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float w_noise(vec3 x) {
	vec3 i = floor(x);
	vec3 f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(w_hash(i), w_hash(i + vec3(1.0, 0.0, 0.0)), f.x),
			mix(w_hash(i + vec3(0.0, 1.0, 0.0)), w_hash(i + vec3(1.0, 1.0, 0.0)), f.x), f.y),
		mix(mix(w_hash(i + vec3(0.0, 0.0, 1.0)), w_hash(i + vec3(1.0, 0.0, 1.0)), f.x),
			mix(w_hash(i + vec3(0.0, 1.0, 1.0)), w_hash(i + vec3(1.0, 1.0, 1.0)), f.x), f.y), f.z);
}

// ระยะถึงแผลที่ใกล้สุดเป็นเท่าของรัศมี (< 1 = ในแผล) ขอบหยักจากสัญญาณรบกวนในกรอบกระดูก ; seed แยกขอบแต่ละชั้น
float wound_dist(vec3 p, float seed) {
	float best = 9.0;
	for (int i = 0; i < 8; i++) {
		if (i >= wound_count) {
			break;
		}
		vec4 w = wounds[i];
		vec3 d = p - w.xyz;
		float r = length(d) / w.w;
		if (r > 1.6) {
			best = min(best, r);
			continue;
		}
		vec3 u = wound_rot[i].xyz;
		vec3 l = (d + 2.0 * cross(u, cross(u, d)) - 2.0 * wound_rot[i].w * cross(u, d)) / w.w;
		vec3 s = l * 2.6 + vec3(float(i) * 7.31 + seed);
		float n = 0.65 * w_noise(s) + 0.35 * w_noise(s * 2.7 + vec3(3.1));
		best = min(best, r * (1.0 + 0.42 * (n - 0.5)));
	}
	return best;
}
// ---- จบส่วนแผล ----

// เส้นสายตาจากกล้องถึงจุด pv (กรอบมุมมอง) ผ่านทรงกลมแผลใด ๆ ไหม (mv = กรอบโมเดล -> มุมมอง)
bool through_wound(vec3 pv, mat4 mv) {
	vec3 d = normalize(pv);
	float len = length(pv);
	for (int i = 0; i < 8; i++) {
		if (i >= wound_count) {
			break;
		}
		vec3 c = (mv * vec4(wounds[i].xyz, 1.0)).xyz;
		float t = clamp(dot(c, d), 0.0, len);
		if (length(c - d * t) < wounds[i].w * 1.3) {
			return true;
		}
	}
	return false;
}

void vertex() {
	v_pos = VERTEX;
	v_light = (VIEW_MATRIX * vec4(normalize(sun_dir), 0.0)).xyz;
}

void fragment() {
	if (wound_count <= 0) {
		discard;
	}
	if (!FRONT_FACING) {
		if (core > 0.0 ? !through_wound(VERTEX, VIEW_MATRIX * MODEL_MATRIX) : wound_dist(v_pos, 0.0) > keep) {
			discard;
		}
		ALBEDO = inner_colour;
	} else {
		float e = wound_dist(v_pos, 0.0);
		if (e > keep) {
			discard;
		}
		vec3 col = base_colour;
		if (core > 0.0) {
			float c = wound_dist(v_pos, 37.0);
			if (c < core) {
				discard;
			}
			col = mix(col * 0.55, col, smoothstep(core, core + 0.18, c));
			col = mix(col, fat_colour, fat_band * smoothstep(0.80, 0.98, e) * 0.85);
		}
		vec3 n = normalize(NORMAL);
		vec3 l = normalize(v_light);
		float diff = max((dot(n, l) + 0.3) / 1.3, 0.0);
		float spec = pow(max(dot(n, normalize(l + VIEW)), 0.0), 40.0) * wet;
		ALBEDO = col * (ambient_colour + sun_colour * diff) + sun_colour * spec;
	}
}
