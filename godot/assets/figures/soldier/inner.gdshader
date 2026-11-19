// soldier_inner.gdshader — ชั้นในของทหารที่เห็นผ่านแผล (เนื้อ/กระดูก): ไม่รับไฟจากฉาก คิดแสงเองแบบผิว ไม่มี TIME
//   ซ่อนอยู่ (visible = false) จนกว่าจะมีแผล ; ส่วนแผลจาก wound.gdshaderinc (ขอบผิวขาดที่ระยะ 1 ตรงกับผิว)
//   CUSTOM0.x = ส่วนร่างกาย (เห็นเฉพาะแผลของส่วนเดียวกัน) ; render_priority 1 = วาดหลังผิว
//   ด้านหน้า: วาดเฉพาะในระยะ keep ของแผล ; เนื้อ (core > 0) = ทิ้งแกนแผลให้เห็นกระดูก วงเนื้อแดงเปียกรอบกระดูก
//     มืดลงเข้าหาแกน + ลายเนื้อ + แถบไขมันบางสีซีดใต้ขอบผิว ; กระดูก (core = 0) = ขาวงาช้างอมเลือดใกล้ขอบและเป็นจุด ๆ
//   ด้านใน (หน้าหลัง: NORMAL หันหาตาแล้ว) คิดแสง/เงาเปียกแบบเดียวกัน: เนื้อ = ก้นแผลแดงเข้ม มืดลงตรงกลางแผล
//     เฉพาะที่เส้นสายตาผ่านแผลของส่วนเดียวกัน ; กระดูก = ไขกระดูกตรงรอยตัด ทิ้งนอก keep
//   ลายเนื้อ = สัญญาณรบกวนในกรอบกระดูกของแผล (ไม่ไหลตามท่า)
shader_type spatial;
render_mode unshaded, cull_disabled;

uniform vec3 sun_dir = vec3(0.2, 1.0, 0.3);           // ทิศไปหาดวงอาทิตย์ (world)
uniform vec3 sun_colour = vec3(0.62, 0.64, 0.68);
uniform vec3 ambient_colour = vec3(0.34, 0.36, 0.42);
uniform vec3 base_colour = vec3(0.50, 0.07, 0.06);     // เนื้อแดงเปียก (กระดูก: ขาวงาช้าง)
uniform vec3 inner_colour = vec3(0.30, 0.05, 0.04);    // ด้านใน: ก้นแผลแดงเข้ม (กระดูก: ไขกระดูก)
uniform vec3 fat_colour = vec3(0.93, 0.82, 0.52);      // แถบไขมันใต้ขอบผิว
uniform vec3 blood_colour = vec3(0.42, 0.04, 0.03);    // เลือดบนกระดูก
uniform float core = 0.4;                              // แกนแผลที่เนื้อถูกตัด (เท่าของรัศมี) ; 0 = ชั้นกระดูก
uniform float keep = 1.2;                              // วาดด้านหน้าเฉพาะในระยะนี้ (เท่าของรัศมี)
uniform float fat_band = 1.0;                          // 1 = มีแถบไขมัน
uniform float blood = 0.0;                             // กระดูกอมเลือด (0 = ไม่มี)
uniform float wet = 0.5;                               // ความเงาเปียก

#include "wound.gdshaderinc"

varying vec3 v_pos;
varying vec3 v_light;
varying flat float v_part;

// เส้นสายตาจากกล้องถึงจุด pv (กรอบมุมมอง) ผ่านใกล้ศูนย์กลางแผลของส่วน part แค่ไหน (เท่าของรัศมี ; 9 = ไม่มี)
// mv = กรอบโมเดล -> มุมมอง ; wi = แผลนั้น
float ray_wound(vec3 pv, mat4 mv, float part, out int wi) {
	vec3 d = normalize(pv);
	float len = length(pv);
	float best = 9.0;
	wi = 0;
	for (int i = 0; i < 8; i++) {
		if (i >= wound_count) {
			break;
		}
		if (abs(wound_part[i] - part) > 0.5) {
			continue;
		}
		vec3 c = (mv * vec4(wounds[i].xyz, 1.0)).xyz;
		float t = clamp(dot(c, d), 0.0, len);
		float q = length(c - d * t) / wounds[i].w;
		if (q < best) {
			best = q;
			wi = i;
		}
	}
	return best;
}

vec3 shade(vec3 col, vec3 n, vec3 l, vec3 v, float gloss) {
	float diff = max((dot(n, l) + 0.3) / 1.3, 0.0);
	float spec = pow(max(dot(n, normalize(l + v)), 0.0), 40.0) * gloss;
	return col * (ambient_colour + sun_colour * diff) + sun_colour * spec;
}

void vertex() {
	v_pos = VERTEX;
	v_part = CUSTOM0.x;
	v_light = (VIEW_MATRIX * vec4(normalize(sun_dir), 0.0)).xyz;
}

void fragment() {
	if (wound_count <= 0) {
		discard;
	}
	vec3 col;
	float gloss = wet;
	vec3 lp;
	if (!FRONT_FACING) {
		if (core > 0.0) {
			int wi;
			float q = ray_wound(VERTEX, VIEW_MATRIX * MODEL_MATRIX, v_part, wi);
			if (q > 1.3) {
				discard;
			}
			lp = wound_local(wi, v_pos - wounds[wi].xyz);
			float mn = 0.6 * w_noise(lp * 5.0 + vec3(11.0)) + 0.4 * w_noise(lp * 13.0);
			col = inner_colour * (0.66 + 0.34 * smoothstep(0.0, 1.1, q + 0.6 * (mn - 0.5))) * (0.7 + 0.6 * mn);
			gloss = wet * (0.4 + 1.2 * mn);
		} else {
			if (wound_near(v_pos, 0.0, v_part, lp) > keep) {
				discard;
			}
			col = inner_colour * (0.85 + 0.3 * w_noise(lp * 9.0));
		}
	} else {
		float e = wound_near(v_pos, 0.0, v_part, lp);
		if (e > keep) {
			discard;
		}
		float mn = 0.6 * w_noise(lp * 6.0 + vec3(5.0)) + 0.4 * w_noise(lp * 15.0);
		col = base_colour;
		if (core > 0.0) {
			float c = wound_dist(v_pos, 37.0, v_part);
			if (c < core) {
				discard;
			}
			col *= mix(0.62, 1.0, smoothstep(core, core + 0.3, c + 0.25 * (mn - 0.5))) * (0.72 + 0.56 * mn);
			float fb = fat_band * smoothstep(0.90, 0.99, e);
			col = mix(col, fat_colour, fb * 0.9);
			gloss = wet * (0.7 + 0.6 * mn) + 0.15 * fb;
		} else {
			float b = blood * (0.2 + 0.8 * smoothstep(0.3, 0.55, e)) * (0.5 + mn);
			col = mix(col, blood_colour, clamp(b, 0.0, 0.85));
		}
	}
	ALBEDO = shade(col, normalize(NORMAL), normalize(v_light), VIEW, gloss);
}
