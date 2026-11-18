// soldier_skin.gdshader — ผิวทหาร (ของแอปปกติ เขียนใหม่ทั้งหมด): ไม่รับไฟจากฉาก (unshaded) คิดแสงเองแบบฉากอารีน่า/ดาดฟ้า
//   COLOR.rgb = สีผิว × AO (sRGB) ; CUSTOM0 = (ธงทาสีได้ 0, ดัชนีจานสี 0, ความเป็นเนื้อ 0..1, 0)
//   Compatibility renderer ไม่มี subsurface: ใช้แสงห่อ (wrap) + สีอุ่นตรงขอบเงา เฉพาะส่วนที่เป็นเนื้อ
//   per_vertex (lo/min): คิดแสงใน vertex ทั้งหมด ; ไม่มี TIME ; แสงวาบ/สีเตือน = uniform เดียว (ปกติ 0)
//   แผล (ทำงานเมื่อ wound_count > 0 เท่านั้น วัสดุของตัวนั้นเอง): wounds[i] = ศูนย์กลางในกรอบโครง + รัศมี (w)
//     wound_rot[i] = การหมุนของกระดูกที่แผลติด (ขอบหยักคงที่บนผิว ไม่ไหลตามท่า) ; ฟังก์ชันแผลชุดเดียวกับ soldier_inner
//     wound_mode 2 (hi/mid) = ทิ้งผิวในแผล + ขอบแดงคล้ำ (เห็นเนื้อ/กระดูกข้างใน) ; 1 (lo) = สีแผลต่อจุดยอด ไม่ทิ้งผิว
shader_type spatial;
render_mode unshaded, cull_back;

uniform bool per_vertex = false;
uniform vec3 sun_dir = vec3(0.2, 1.0, 0.3);           // ทิศไปหาดวงอาทิตย์ (world)
uniform vec3 sun_colour = vec3(0.62, 0.64, 0.68);
uniform vec3 ambient_colour = vec3(0.34, 0.36, 0.42);
uniform float wrap = 0.45;                             // แสงห่อของเนื้อ
uniform vec3 warm = vec3(0.30, 0.10, 0.05);            // สีอุ่นตรงขอบเงา (แทนแสงลอดผิว)
uniform float flash = 0.0;
uniform float telegraph = 0.0;
uniform vec3 telegraph_colour = vec3(0.9, 0.08, 0.06);
uniform int wound_count = 0;
uniform int wound_mode = 2;
uniform vec4 wounds[8];
uniform vec4 wound_rot[8];
uniform vec3 wound_colour = vec3(0.30, 0.02, 0.02);    // ขอบแผลบนผิว / สีแผลของ lo

varying vec3 v_col;
varying vec3 v_light;
varying float v_flesh;
varying vec3 v_pos;
varying float v_wound;

vec3 skin_light(vec3 n, vec3 l, float flesh) {
	float ndl = dot(n, l);
	float w = wrap * flesh;
	float diff = max((ndl + w) / (1.0 + w), 0.0);
	float edge = clamp(1.0 - abs(ndl - 0.05) * 2.4, 0.0, 1.0) * flesh;
	return ambient_colour + sun_colour * diff + warm * edge * 0.35;
}

// ---- แผล (เหมือนกันทุกตัวอักษรใน soldier_inner.gdshader) ----
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

void vertex() {
	v_col = COLOR.rgb;
	v_flesh = CUSTOM0.z;
	v_pos = VERTEX;
	v_wound = 0.0;
	if (wound_count > 0 && wound_mode == 1) {
		v_wound = (1.0 - smoothstep(0.7, 1.25, wound_dist(VERTEX, 0.0))) * 0.85;
	}
	vec3 n = normalize(MODEL_NORMAL_MATRIX * NORMAL);
	if (per_vertex) {
		v_light = skin_light(n, normalize(sun_dir), v_flesh);
	} else {
		v_light = (VIEW_MATRIX * vec4(normalize(sun_dir), 0.0)).xyz;
	}
}

void fragment() {
	vec3 lit = per_vertex ? v_col * v_light : v_col * skin_light(normalize(NORMAL), normalize(v_light), v_flesh);
	if (wound_count > 0) {
		if (wound_mode >= 2) {
			float e = wound_dist(v_pos, 0.0);
			if (e < 1.0) {
				discard;
			}
			float rim = 1.0 - smoothstep(1.0, 1.32, e);
			lit = mix(lit, wound_colour * (0.45 + 0.55 * smoothstep(1.0, 1.07, e)), rim * 0.9);
		} else {
			lit = mix(lit, wound_colour, v_wound);
		}
	}
	lit = mix(lit, telegraph_colour, telegraph * 0.4) + vec3(flash * 0.85);
	ALBEDO = lit;
}
