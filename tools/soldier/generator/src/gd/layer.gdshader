// layer.gdshader — ภาพชั้นโครงกระดูก/กล้ามเนื้อ (เครื่องมือทำภาพ ไม่ใช้ในเกม): สีจุดยอด + แสงในตัว
shader_type spatial;
render_mode unshaded, cull_back;
uniform vec3 sun_dir = vec3(0.2, 1.0, 0.3);
uniform vec3 sun_colour = vec3(0.62, 0.64, 0.68);
uniform vec3 ambient_colour = vec3(0.34, 0.36, 0.42);
uniform float gloss = 0.25;
varying vec3 v_col;
varying vec3 v_l;
void vertex() {
	v_col = COLOR.rgb;
	v_l = (VIEW_MATRIX * vec4(normalize(sun_dir), 0.0)).xyz;
}
void fragment() {
	vec3 n = normalize(NORMAL);
	vec3 l = normalize(v_l);
	float d = max((dot(n, l) + 0.3) / 1.3, 0.0);
	vec3 h = normalize(l + vec3(0.0, 0.0, 1.0));
	float s = pow(max(dot(n, h), 0.0), 24.0) * gloss;
	ALBEDO = v_col * (ambient_colour + sun_colour * d) + vec3(s);
}
