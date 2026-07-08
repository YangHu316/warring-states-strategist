shader_type canvas_item;
// 板块翻格子（RFC-004 §八）：板块即进度条——
// 从板块内容右缘起，按"格"（一格一城）把被占领的列翻为占领方颜色。
// lost_a/lost_b 为浮点，tween 时前沿格逐渐扫过 = 翻格动画。

uniform float total_cells = 25.0;
uniform float lost_a = 0.0;
uniform float lost_b = 0.0;
uniform vec4 color_a : source_color = vec4(0.0, 0.0, 0.0, 0.0);
uniform vec4 color_b : source_color = vec4(0.0, 0.0, 0.0, 0.0);
uniform float min_x = 0.0;
uniform float max_x = 1.0;
uniform float tint_strength : hint_range(0.0, 1.0) = 0.5;
// 本国底色：浅染整块板做领地分区标记（秦红/赵蓝/齐绿）
uniform vec4 base_color : source_color = vec4(0.0, 0.0, 0.0, 0.0);
uniform float base_strength : hint_range(0.0, 1.0) = 0.16;

void fragment() {
	vec4 tex = texture(TEXTURE, UV);
	vec3 rgb = tex.rgb;
	if (base_color.a > 0.001) {
		rgb = mix(rgb, base_color.rgb, base_strength);
	}
	float span = max(max_x - min_x, 0.0001);
	float x = clamp((UV.x - min_x) / span, 0.0, 1.0);
	float from_right = (1.0 - x) * total_cells;  // 右缘=0，向左递增（单位：格）
	float lost_total = lost_a + lost_b;
	if (from_right < lost_total && lost_total > 0.001) {
		vec4 tint = (from_right < lost_a) ? color_a : color_b;
		if (tint.a > 0.001) {
			float luma = dot(tex.rgb, vec3(0.299, 0.587, 0.114));
			// 占领色盖过本国底色（用原图取亮度，避免双重染色发闷）
			rgb = mix(tex.rgb, tint.rgb * (0.4 + luma * 0.8), tint_strength);
			// 格缝：列边界压暗，读出"一格一城"
			float fx = fract(from_right);
			float seam = smoothstep(0.0, 0.08, fx) * smoothstep(0.0, 0.08, 1.0 - fx);
			rgb *= mix(0.72, 1.0, seam);
			// 翻转前沿微亮（正在被翻的那一格）
			if (from_right > lost_total - 1.0) {
				rgb += vec3(0.10, 0.08, 0.03);
			}
		}
	}
	COLOR = vec4(rgb, tex.a);
}
