// figure.gdshader — ฟิกเกอร์จากชุดโมเดล (assets/kits หลัง kit_post_import.gd): พื้นผิวเดียว วัสดุเดียว
//   COLOR   = สีจานสีของชิ้นส่วน (sRGB 0..1 ตรงกับ MINI.SOLID ของหน้าเว็บ)
//   CUSTOM0 = (ธงทาสีได้ 0/1, ดัชนีจานสี 0..22, 0, 0)
// ทาสีทับ (งานสี): paint_tex แถว = งานสี 1 งาน, คอลัมน์ = ดัชนีจานสี (ไม่เกิน 16), alpha = ความแรงของสีทับ (0 = คงสีเดิม)
//   เลือกแถวด้วย paint_row (ชุดมีโครง: ตั้งบนวัสดุที่ duplicate) หรือ INSTANCE_CUSTOM.x (MultiMesh, use_instance_custom)
//   แถว < 0 = ใช้ COLOR ตามเดิม ; อ่านด้วย texelFetch (ไม่กรอง ไม่ซึมข้ามแถว)
// แสง: lambert ดวงอาทิตย์ + ambient ไม่มี specular ; คิดใน vertex ทั้งหมดเมื่อ per_vertex (lo/min) ; Compatibility renderer
// Compatibility renderer แสดง ALBEDO ตรง ๆ ไม่แปลง sRGB (ทดสอบแล้ว) จึงคิดสีและแสงใน sRGB เหมือนหน้าเว็บ
// สัญญาเต็มอยู่ใน assets/kits/CONTRACT.md
shader_type spatial;
render_mode unshaded, cull_back;

uniform sampler2D paint_tex : filter_nearest, repeat_disable;
uniform int paint_row = -1;
uniform bool use_instance_custom = false;
uniform bool per_vertex = true;
uniform bool mask_out = false;                       // อบ impostor: ส่งออก (ธงทาสีได้, 1 - ดัชนีจานสี/32, 0) แทนสี
uniform vec3 sun_dir = vec3(0.4, 0.8, 0.45);         // ทิศไปหาดวงอาทิตย์ (world) ไม่ต้อง normalize
uniform vec3 sun_colour = vec3(0.58, 0.56, 0.52);
uniform vec3 ambient_colour = vec3(0.46, 0.47, 0.52);

varying vec3 v_albedo;   // สีหลังทาสี (หรือค่ามาสก์)
varying vec3 v_light;    // per_vertex: แสงรวม ; ต่อพิกเซล: ทิศดวงอาทิตย์ใน view space

void vertex() {
	int slot = int(CUSTOM0.y + 0.5);
	float paintable = step(0.5, CUSTOM0.x);
	vec3 c = COLOR.rgb;
	int row = use_instance_custom ? int(floor(INSTANCE_CUSTOM.x + 0.5)) : paint_row;
	ivec2 ts = textureSize(paint_tex, 0);
	if (row >= 0 && row < ts.y) {
		vec4 p = texelFetch(paint_tex, ivec2(min(slot, ts.x - 1), row), 0);
		c = mix(c, p.rgb, p.a);
	}
	// มาสก์: ดัชนีเก็บเป็น 1 - slot/32 (ช่วงสว่าง ห่างกัน 8/255) เพราะทางออกจอของ Compatibility บีบค่าใกล้ดำ (วัดแล้ว)
	v_albedo = mask_out ? vec3(paintable, 1.0 - float(slot) / 32.0, 0.0) : c;
	vec3 n = normalize(MODEL_NORMAL_MATRIX * NORMAL);
	if (per_vertex) {
		v_light = ambient_colour + sun_colour * max(dot(n, normalize(sun_dir)), 0.0);
	} else {
		v_light = (VIEW_MATRIX * vec4(normalize(sun_dir), 0.0)).xyz;
	}
}

void fragment() {
	if (mask_out) {
		ALBEDO = v_albedo;
	} else if (per_vertex) {
		ALBEDO = v_albedo * v_light;
	} else {
		ALBEDO = v_albedo * (ambient_colour + sun_colour * max(dot(normalize(NORMAL), normalize(v_light)), 0.0));
	}
}
