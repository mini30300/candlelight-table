// face.gdshaderinc — หน้าของทหาร (ใหม่ 0.14): เปลือกตาปิด/หรี่ + ช่องปากเมื่อกรามอ้า (แถบรอยต่อปาก hi/mid) + ปากทาสี (lo)
//   include ใน soldier_skin.gdshader และ soldier_skin_wound.gdshader ; ทับสีหลังคิดแสง (แสงเดียวกับผิว) ; ไม่มี TIME ไม่มี discard
//   CUSTOM1 = (ตา u, ตา v, ปาก x, ปาก y) จาก tools/soldier face.py: อัลมอนด์ตาขยาย = |u|,|v| <= 1 ; มุมปาก = (±1, 0)
//     แถวรอยต่อปากเก็บในช่องตา: u + v = 24 เฉพาะในแถบช่องปาก (v = 0 ริมฝีปากบน -> 1 ริมฝีปากล่าง) ; min ไม่มี CUSTOM1
//   face_state (ต่อตัว instance uniform): x เปลือกตาบนลง 0..1 (1 = ปิดสนิท) y เปลือกตาล่างขึ้น 0..1 z ปากทาสีอ้า 0..1 w ปากกว้าง -1..1
//   ค่าเริ่ม: face_on ปิด และ face_state = 0 -> หน้าเดิมทุกพิกเซล ; face_lid_colour ของแต่ละร่างตั้งในวัสดุ (assemble.gd)
uniform bool face_on = false;
uniform vec3 face_lid_colour = vec3(0.62, 0.45, 0.37);
uniform vec3 face_mouth_colour = vec3(0.13, 0.04, 0.04);
uniform vec3 face_teeth_colour = vec3(0.78, 0.74, 0.66);
instance uniform vec4 face_state = vec4(0.0);

varying vec4 v_face;

// สีที่ทับ (rgb) และน้ำหนัก (a) ของพิกเซลที่พิกัดหน้า f
vec4 face_paint(vec4 f) {
	// แถบช่องปาก (hi/mid): ฟันบนใต้ริมฝีปากบน แล้วมืดลงข้างใน (ตอนหุบแถบสูง 0.3 มม. แทบไม่เห็น)
	if (f.x + f.y > 23.9) {
		float v = clamp((f.y - 8.0) / 8.0, 0.0, 1.0);
		return vec4(mix(face_teeth_colour, face_mouth_colour, smoothstep(0.14, 0.30, v)), 1.0);
	}
	vec4 o = vec4(0.0);
	// เปลือกตา: ขอบบนลงจากเหนืออัลมอนด์ (v 1.2) ขอบล่างขึ้นจาก -1.2 ไปพบกันที่ v -0.35 เมื่อปิดสนิท (x = 1) ;
	//   y ยกขอบล่างเพิ่ม (หรี่ตา) ; ขนตาเข้มที่ขอบเปลือกบน
	float au = abs(f.x);
	if (au < 1.04 && abs(f.y) < 1.06 && face_state.x + face_state.y > 0.0) {
		float top = mix(1.2, -0.4, face_state.x);
		float bot = min(mix(-1.2, -0.3, face_state.x) + 1.1 * face_state.y, top + 0.1);
		float cov = max(smoothstep(top - 0.05, top + 0.05, f.y), 1.0 - smoothstep(bot - 0.05, bot + 0.05, f.y));
		cov *= (1.0 - smoothstep(1.0, 1.04, au)) * (1.0 - smoothstep(1.0, 1.06, abs(f.y)));
		float lash = (1.0 - smoothstep(0.0, 0.22, f.y - top)) * smoothstep(0.04, 0.2, face_state.x);
		o = vec4(face_lid_colour * (1.0 - 0.45 * lash), cov);
	}
	// ปากทาสี (lo หรือเมื่อเกมสั่ง): วงรีมืดใต้แนวปาก + ฟันบนเมื่ออ้ากว้าง
	if (face_state.z > 0.0 && abs(f.z) < 1.3 && abs(f.w) < 1.0) {
		float a = 0.80 * (1.0 + 0.22 * face_state.w);
		float h = 0.04 + 0.30 * face_state.z * (1.0 - 0.25 * face_state.w);
		vec2 q = vec2(f.z / a, (f.w + 0.35 * h) / h);
		float m = 1.0 - smoothstep(0.75, 1.0, dot(q, q));
		vec3 c = mix(face_mouth_colour, face_teeth_colour, smoothstep(0.35, 0.6, q.y) * smoothstep(0.25, 0.5, face_state.z));
		o = vec4(c, max(o.a, m));
	}
	return o;
}
