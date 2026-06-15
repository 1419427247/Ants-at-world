shader_type canvas_item;

uniform sampler2D u_input_tex;
uniform float u_dist_mod = 1.0;

void fragment()
{
	// Translate UVs from the square voronoi buffer back to viewport size.
	vec2 uv = UV;
	if (SCREEN_PIXEL_SIZE.x < SCREEN_PIXEL_SIZE.y)
		uv.y = ((uv.y - 0.5) * (SCREEN_PIXEL_SIZE.x / SCREEN_PIXEL_SIZE.y)) + 0.5;
	else
		uv.x = ((uv.x - 0.5) * (SCREEN_PIXEL_SIZE.y / SCREEN_PIXEL_SIZE.x)) + 0.5;

	// Input is the voronoi output which stores in each pixel the UVs of the closest surface.
	// Here we simply take that value, calculate the distance between the closest surface and this
	// pixel, and return that distance.
	vec4 tex = texture(u_input_tex, uv);
	float dist = distance(tex.xy, uv);
	float mapped = clamp(dist * u_dist_mod, 0.0, 1.0);
	COLOR = vec4(vec3(mapped), 1.0);
}
