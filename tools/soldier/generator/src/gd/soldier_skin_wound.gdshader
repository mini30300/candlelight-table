// soldier_skin_wound.gdshader — ผิวทหารตอนมีแผล: แสงเหมือน soldier_skin.gdshader ทุกอย่าง + ส่วนแผล (wound.gdshaderinc)
//   ใช้เฉพาะวัสดุของตัวที่มีแผลบน hi/mid/lo (วัสดุร่วมและระดับ min ใช้ soldier_skin.gdshader ที่ไม่มีโค้ดแผล/discard)
//   CUSTOM0.w = ส่วนร่างกาย: แผลตัดเฉพาะผิวส่วนเดียวกับกระดูกของแผล ; ไม่มี TIME
//   wound_mode 2 (hi/mid) = ทิ้งผิวในแผล + ขอบแดงคล้ำ (เห็นเนื้อ/กระดูกข้างใน) ; 1 (lo หรือไม่มีชั้นใน) = สีแผลต่อจุดยอด
//   แสงวาบ/สีเตือนของตัวที่มีแผลมาทาง uniform flash/telegraph (ไม่มี material_overlay ทับรูแผล)
//   หน้า (เปลือกตา ช่องปาก) อยู่ใน face.gdshaderinc เหมือน soldier_skin.gdshader
shader_type spatial;
render_mode unshaded, cull_back;

uniform bool per_vertex = false;
uniform vec3 sun_dir = vec3(0.3, 0.9, 0.3);            // ทิศไปหาดวงอาทิตย์ (world)
uniform vec3 sun_colour = vec3(0.86, 0.84, 0.80);
uniform vec3 ambient_colour = vec3(0.27, 0.28, 0.32);  // แสงรอบตัวเฉลี่ย (ครึ่งฟ้าคูณด้วย sky_tint/ground_tint)
uniform vec3 sky_tint = vec3(1.20, 1.16, 1.10);        // แสงรอบตัวจากฟ้า (ด้านที่หันขึ้น อุ่นกว่า)
uniform vec3 ground_tint = vec3(0.76, 0.75, 0.80);     // แสงรอบตัวจากพื้น (ด้านที่หันลง มืดกว่า)
uniform float wrap = 0.35;                             // แสงห่อของเนื้อ
uniform vec3 warm = vec3(0.30, 0.10, 0.05);            // สีอุ่นตรงขอบเงา (แทนแสงลอดผิว)
uniform float rim_light = 0.9;                         // แสงขอบจากฟ้า (ต่อพิกเซลเท่านั้น)
uniform float sheen = 0.06;                            // เงาผิวของเนื้อ (ต่อพิกเซลเท่านั้น)
uniform float flash = 0.0;
uniform float telegraph = 0.0;
uniform vec3 telegraph_colour = vec3(0.9, 0.08, 0.06);
uniform int wound_mode = 2;
uniform vec3 wound_colour = vec3(0.30, 0.02, 0.02);    // ขอบแผลบนผิว / สีแผลของ lo

#include "wound.gdshaderinc"
#include "face.gdshaderinc"

varying vec3 v_col;
varying vec3 v_light;
varying float v_flesh;
varying vec3 v_mat;
varying vec3 v_pos;
varying float v_wound;
varying flat float v_part;

// แสงกระจาย + ครึ่งฟ้า: n, l, up อยู่ในกรอบเดียวกัน (world ใน vertex, view ใน fragment)
vec3 skin_light(vec3 n, vec3 l, vec3 up, float flesh) {
	float ndl = dot(n, l);
	float w = wrap * flesh;
	float diff = max((ndl + w) / (1.0 + w), 0.0);
	float edge = clamp(1.0 - abs(ndl - 0.05) * 2.4, 0.0, 1.0) * flesh;
	vec3 amb = ambient_colour * mix(ground_tint, sky_tint, dot(n, up) * 0.5 + 0.5);
	return amb + sun_colour * diff + warm * edge * 0.35;
}

// ชนิดวัสดุ (CUSTOM0.x: ชุดของ tools/soldier outfits.py) -> (คูณแสงขอบ, เงาเพิ่ม, ความคมของเงา) ; 0 = ผิว (ค่าเดิมทุกตัว)
vec3 mat_gloss(float c) {
	int k = int(c + 0.5);
	if (k == 1) { return vec3(0.55, 0.012, 6.0); }   // ผ้า: ด้าน แสงขอบนุ่ม
	if (k == 2) { return vec3(0.85, 0.10, 18.0); }   // หนัง (รองเท้า)
	if (k == 3) { return vec3(0.60, 0.02, 8.0); }    // สายรัด/กระเป๋า
	if (k == 4) { return vec3(0.40, 0.01, 6.0); }    // พื้นยาง
	if (k == 5) { return vec3(1.00, 0.30, 40.0); }   // แผ่นเกราะ (เซรามิก/คาร์บอน)
	if (k == 6) { return vec3(0.80, 0.12, 16.0); }   // ชุดชั้นในคาร์บอน
	if (k == 7) { return vec3(0.70, 0.04, 10.0); }   // ผม
	if (k == 8) { return vec3(0.85, 0.25, 40.0); }   // โลหะ
	return vec3(1.0, 0.0, 24.0);
}

// ต่อพิกเซลเท่านั้น: แสงขอบจากฟ้า (ด้านที่หันขึ้น คูณสีผิว) + เงาผิวจาง ๆ ของเนื้อ ; v = ทิศไปหากล้อง ; m = mat_gloss
vec3 skin_gloss(vec3 col, vec3 n, vec3 l, vec3 up, vec3 v, float flesh, vec3 m) {
	float f = 1.0 - max(dot(n, v), 0.0);
	float r = f * f * f * rim_light * m.x * clamp(dot(n, up) * 0.6 + 0.6, 0.0, 1.0);
	float s = pow(max(dot(n, normalize(l + v)), 0.0), m.z) * (sheen * flesh + m.y) * smoothstep(0.0, 0.25, dot(n, l));
	return col * ambient_colour * sky_tint * r + sun_colour * s;
}

void vertex() {
	v_col = COLOR.rgb;
	v_flesh = CUSTOM0.z;
	v_mat = vec3(1.0, 0.0, 24.0);
	v_face = CUSTOM1;
	v_pos = VERTEX;
	v_part = CUSTOM0.w;
	v_wound = 0.0;
	if (wound_count > 0 && wound_mode == 1) {
		v_wound = (1.0 - smoothstep(0.7, 1.25, wound_dist(VERTEX, 0.0, CUSTOM0.w))) * 0.85;
	}
	vec3 n = normalize(MODEL_NORMAL_MATRIX * NORMAL);
	if (per_vertex) {
		v_light = skin_light(n, normalize(sun_dir), vec3(0.0, 1.0, 0.0), v_flesh);
	} else {
		v_light = (VIEW_MATRIX * vec4(normalize(sun_dir), 0.0)).xyz;
		v_mat = mat_gloss(CUSTOM0.x);
	}
}

void fragment() {
	vec3 lit;
	if (per_vertex) {
		lit = v_col * v_light;
	} else {
		vec3 n = normalize(NORMAL);
		vec3 l = normalize(v_light);
		vec3 up = VIEW_MATRIX[1].xyz;
		lit = v_col * skin_light(n, l, up, v_flesh) + skin_gloss(v_col, n, l, up, VIEW, v_flesh, v_mat);
	}
	// หน้า (face.gdshaderinc): เปลือกตา/ช่องปาก/ปากทาสี ทับด้วยแสงเดียวกับผิว (ไม่มีเงาผิว)
	if (face_on) {
		vec4 fp = face_paint(v_face);
		if (fp.a > 0.0) {
			vec3 lt = v_light;
			if (!per_vertex) {
				lt = skin_light(normalize(NORMAL), normalize(v_light), VIEW_MATRIX[1].xyz, v_flesh);
			}
			lit = mix(lit, fp.rgb * lt, fp.a);
		}
	}
	if (wound_count > 0) {
		if (wound_mode >= 2) {
			float e = wound_dist(v_pos, 0.0, v_part);
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
