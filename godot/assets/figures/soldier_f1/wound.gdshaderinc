// wound.gdshaderinc — ส่วนแผลที่ผิวมีแผล (soldier_skin_wound) และชั้นใน (soldier_inner) ใช้ร่วม: ขอบแผลตรงกันทุกชั้น
//   wounds[i] = ศูนย์กลางในกรอบโครง + รัศมี (w) ; wound_rot[i] = การหมุนของกระดูกที่แผลติด (ขอบหยักคงที่บนผิว)
//   wound_part[i] = ส่วนร่างกายของกระดูกนั้น (0 ลำตัว 1 หัว 2/3 แขนซ้าย/ขวา 4/5 ขาซ้าย/ขวา): แผลมีผลเฉพาะจุดยอด
//   ส่วนเดียวกัน (แผลข้างอกไม่เจาะต้นแขนที่แนบอยู่ ต้นขาด้านในไม่เจาะอีกข้าง) ; ไม่มี TIME
uniform int wound_count = 0;
uniform vec4 wounds[8];
uniform vec4 wound_rot[8];
uniform float wound_part[8];

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

// d (กรอบโครง จากศูนย์กลางแผล i) ในกรอบกระดูกของแผลนั้น เป็นเท่าของรัศมี
vec3 wound_local(int i, vec3 d) {
	vec3 u = wound_rot[i].xyz;
	return (d + 2.0 * cross(u, cross(u, d)) - 2.0 * wound_rot[i].w * cross(u, d)) / wounds[i].w;
}

// ระยะถึงแผลที่ใกล้สุดของส่วน part เป็นเท่าของรัศมี (< 1 = ในแผล) ขอบหยักจากสัญญาณรบกวนในกรอบกระดูก
// seed แยกขอบแต่ละชั้น ; lp = จุดในกรอบกระดูกของแผลนั้น (ลายเนื้อ) ใช้ได้เมื่อระยะ < 1.6
float wound_near(vec3 p, float seed, float part, out vec3 lp) {
	float best = 9.0;
	lp = vec3(0.0);
	for (int i = 0; i < 8; i++) {
		if (i >= wound_count) {
			break;
		}
		if (abs(wound_part[i] - part) > 0.5) {
			continue;
		}
		vec3 d = p - wounds[i].xyz;
		float r = length(d) / wounds[i].w;
		if (r > 1.6) {
			best = min(best, r);
			continue;
		}
		vec3 l = wound_local(i, d);
		vec3 s = l * 2.6 + vec3(float(i) * 7.31 + seed);
		float n = 0.65 * w_noise(s) + 0.35 * w_noise(s * 2.7 + vec3(3.1));
		float e = r * (1.0 + 0.42 * (n - 0.5));
		if (e < best) {
			best = e;
			lp = l + vec3(float(i) * 3.7);
		}
	}
	return best;
}

float wound_dist(vec3 p, float seed, float part) {
	vec3 lp;
	return wound_near(p, seed, part, lp);
}
