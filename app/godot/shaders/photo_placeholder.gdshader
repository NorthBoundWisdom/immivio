shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_mix;
uniform vec2 surface_size = vec2(3.8, 2.14);
uniform float presentation_opacity = 1.0;

void fragment() {
	vec2 p = (UV - vec2(0.5)) * surface_size;
	vec2 half_size = surface_size * 0.5;
	float radius = min(0.09, min(half_size.x, half_size.y) * 0.2);
	vec2 q = abs(p) - half_size + vec2(radius);
	float distance = length(max(q, vec2(0.0))) + min(max(q.x, q.y), 0.0) - radius;
	float edge = 1.0 - smoothstep(-0.025, 0.0, distance);
	float rim = smoothstep(-0.045, -0.018, distance);
	float grain = fract(sin(dot(floor(UV * surface_size * 800.0), vec2(12.9898, 78.233))) * 43758.5453);
	vec3 frost = mix(vec3(0.075, 0.105, 0.13), vec3(0.17, 0.21, 0.24), UV.y);
	frost += (grain - 0.5) * 0.022 + rim * 0.08;
	// A quiet moving arc gives feedback even while a network transfer is still pending.
	float ring = 1.0 - smoothstep(0.004, 0.009, abs(length(p) - 0.045));
	float angle = atan(p.y, p.x) - TIME * 2.8;
	float arc = 0.5 + 0.5 * sin(angle);
	ALBEDO = mix(frost, vec3(0.64, 0.77, 0.79), ring * arc);
	ALPHA = edge * (0.58 + rim * 0.12 + ring * arc * 0.22) * presentation_opacity;
}
