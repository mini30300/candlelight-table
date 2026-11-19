// soldier_skin.gdshader — ผิวทหาร (ของแอปปกติ เขียนใหม่ทั้งหมด): ไม่รับไฟจากฉาก (unshaded) คิดแสงเองแบบฉากอารีน่า/ดาดฟ้า
//   COLOR.rgb = สีผิว × AO (sRGB) ; CUSTOM0 = (ธงทาสีได้ 0, ดัชนีจานสี 0, ความเป็นเนื้อ 0..1, ส่วนร่างกาย 0..5)
//   ไม่มีโค้ดแผล (วัสดุร่วมทุกตัว รวม min): ตัวที่มีแผลบน hi/mid/lo ใช้ soldier_skin_wound.gdshader บนวัสดุของตัวเอง
//   Compatibility renderer ไม่มี subsurface: ใช้แสงห่อ (wrap) + สีอุ่นตรงขอบเงา เฉพาะส่วนที่เป็นเนื้อ
//   แสงรอบตัวแบบครึ่งฟ้า: ด้านที่หันขึ้นสว่างอุ่น ด้านที่หันลงมืดลง (คูณ ambient_colour ฉากที่ตั้งไฟเองยังคุมได้) ตัวจึงมีมิติ
//   ต่อพิกเซล (hi/mid): + แสงขอบจากฟ้า (fresnel) + เงาผิวจาง ๆ ของเนื้อ (skin_gloss)
//   per_vertex (lo/min): คิดแสงใน vertex ทั้งหมด (มีแค่ครึ่งฟ้า ไม่มีแสงขอบ/เงาผิว) ; ไม่มี TIME ; แสงวาบ/สีเตือน = uniform เดียว (ปกติ 0)
//   หน้า (เปลือกตา ช่องปาก) อยู่ใน face.gdshaderinc: ค่าเริ่ม = หน้าเดิม ; min ไม่เปิด face_on
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

#include "face.gdshaderinc"

varying vec3 v_col;
varying vec3 v_light;
varying float v_flesh;

// แสงกระจาย + ครึ่งฟ้า: n, l, up อยู่ในกรอบเดียวกัน (world ใน vertex, view ใน fragment)
vec3 skin_light(vec3 n, vec3 l, vec3 up, float flesh) {
	float ndl = dot(n, l);
	float w = wrap * flesh;
	float diff = max((ndl + w) / (1.0 + w), 0.0);
	float edge = clamp(1.0 - abs(ndl - 0.05) * 2.4, 0.0, 1.0) * flesh;
	vec3 amb = ambient_colour * mix(ground_tint, sky_tint, dot(n, up) * 0.5 + 0.5);
	return amb + sun_colour * diff + warm * edge * 0.35;
}

// ต่อพิกเซลเท่านั้น: แสงขอบจากฟ้า (ด้านที่หันขึ้น คูณสีผิว) + เงาผิวจาง ๆ ของเนื้อ ; v = ทิศไปหากล้อง
vec3 skin_gloss(vec3 col, vec3 n, vec3 l, vec3 up, vec3 v, float flesh) {
	float f = 1.0 - max(dot(n, v), 0.0);
	float r = f * f * f * rim_light * clamp(dot(n, up) * 0.6 + 0.6, 0.0, 1.0);
	float s = pow(max(dot(n, normalize(l + v)), 0.0), 24.0) * sheen * flesh * smoothstep(0.0, 0.25, dot(n, l));
	return col * ambient_colour * sky_tint * r + sun_colour * s;
}

void vertex() {
	v_col = COLOR.rgb;
	v_flesh = CUSTOM0.z;
	v_face = CUSTOM1;
	vec3 n = normalize(MODEL_NORMAL_MATRIX * NORMAL);
	if (per_vertex) {
		v_light = skin_light(n, normalize(sun_dir), vec3(0.0, 1.0, 0.0), v_flesh);
	} else {
		v_light = (VIEW_MATRIX * vec4(normalize(sun_dir), 0.0)).xyz;
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
		lit = v_col * skin_light(n, l, up, v_flesh) + skin_gloss(v_col, n, l, up, VIEW, v_flesh);
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
	lit = mix(lit, telegraph_colour, telegraph * 0.4) + vec3(flash * 0.85);
	ALBEDO = lit;
}
