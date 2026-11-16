shader_type spatial;
// Reverse subtraction clears color and alpha over any scenery, before UI/captions.
render_mode unshaded, blend_sub, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;
void fragment() { ALBEDO = vec3(1.0); ALPHA = 1.0; }
