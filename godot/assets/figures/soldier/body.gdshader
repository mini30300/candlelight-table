// soldier_skin.gdshader — ผิวทหาร (ของแอปปกติ เขียนใหม่ทั้งหมด): ไม่รับไฟจากฉาก (unshaded) คิดแสงเองแบบฉากอารีน่า/ดาดฟ้า
//   COLOR.rgb = สีผิว × AO (sRGB) ; CUSTOM0 = (ธงทาสีได้ 0, ดัชนีจานสี 0, ความเป็นเนื้อ 0..1, ส่วนร่างกาย 0..5)
//   ไม่มีโค้ดแผล (วัสดุร่วมทุกตัว รวม min): ตัวที่มีแผลบน hi/mid/lo ใช้ soldier_skin_wound.gdshader บนวัสดุของตัวเอง
//   Compatibility renderer ไม่มี subsurface: ใช้แสงห่อ (wrap) + สีอุ่นตรงขอบเงา เฉพาะส่วนที่เป็นเนื้อ
//   per_vertex (lo/min): คิดแสงใน vertex ทั้งหมด ; ไม่มี TIME ; แสงวาบ/สีเตือน = uniform เดียว (ปกติ 0)
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

varying vec3 v_col;
varying vec3 v_light;
varying float v_flesh;

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
	vec3 n = normalize(MODEL_NORMAL_MATRIX * NORMAL);
	if (per_vertex) {
		v_light = skin_light(n, normalize(sun_dir), v_flesh);
	} else {
		v_light = (VIEW_MATRIX * vec4(normalize(sun_dir), 0.0)).xyz;
	}
}

void fragment() {
	vec3 lit = per_vertex ? v_col * v_light : v_col * skin_light(normalize(NORMAL), normalize(v_light), v_flesh);
	lit = mix(lit, telegraph_colour, telegraph * 0.4) + vec3(flash * 0.85);
	ALBEDO = lit;
}
