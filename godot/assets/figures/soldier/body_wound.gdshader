// soldier_skin_wound.gdshader — ผิวทหารตอนมีแผล: แสงเหมือน soldier_skin.gdshader ทุกอย่าง + ส่วนแผล (wound.gdshaderinc)
//   ใช้เฉพาะวัสดุของตัวที่มีแผลบน hi/mid/lo (วัสดุร่วมและระดับ min ใช้ soldier_skin.gdshader ที่ไม่มีโค้ดแผล/discard)
//   CUSTOM0.w = ส่วนร่างกาย: แผลตัดเฉพาะผิวส่วนเดียวกับกระดูกของแผล ; ไม่มี TIME
//   wound_mode 2 (hi/mid) = ทิ้งผิวในแผล + ขอบแดงคล้ำ (เห็นเนื้อ/กระดูกข้างใน) ; 1 (lo หรือไม่มีชั้นใน) = สีแผลต่อจุดยอด
//   แสงวาบ/สีเตือนของตัวที่มีแผลมาทาง uniform flash/telegraph (ไม่มี material_overlay ทับรูแผล)
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
uniform int wound_mode = 2;
uniform vec3 wound_colour = vec3(0.30, 0.02, 0.02);    // ขอบแผลบนผิว / สีแผลของ lo

#include "wound.gdshaderinc"

varying vec3 v_col;
varying vec3 v_light;
varying float v_flesh;
varying vec3 v_pos;
varying float v_wound;
varying flat float v_part;

vec3 skin_light(vec3 n, vec3 l, float flesh) {
	float ndl = dot(n, l);
	float w = wrap * flesh;
	float diff = max((ndl + w) / (1.0 + w), 0.0);
	float edge = clamp(1.0 - abs(ndl - 0.05) * 2.4, 0.0, 1.0) * flesh;
	return ambient_colour + sun_colour * diff + warm * edge * 0.35;
}

void vertex() {
	v_col = COLOR.rgb;
	v_flesh = CUSTOM0.z;
	v_pos = VERTEX;
	v_part = CUSTOM0.w;
	v_wound = 0.0;
	if (wound_count > 0 && wound_mode == 1) {
		v_wound = (1.0 - smoothstep(0.7, 1.25, wound_dist(VERTEX, 0.0, CUSTOM0.w))) * 0.85;
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
