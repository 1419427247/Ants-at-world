shader_type canvas_item;

// Uniforms
uniform int u_rays_per_pixel = 32;
uniform sampler2D u_distance_data;
uniform sampler2D u_scene_data;
uniform float u_emission_multi = 1.0;
uniform int u_max_raymarch_steps = 64;
uniform float u_dist_mod = 1.0;

void get_surface(vec2 uv, out float emissive, out vec3 colour)
{
	vec4 emissive_data = texture(u_scene_data, uv);
	emissive = max(emissive_data.r, max(emissive_data.g, emissive_data.b)) * u_emission_multi;
	colour = emissive_data.rgb;
}

bool raymarch(vec2 origin, vec2 dir, float aspect, out vec2 hit_pos)
{
	float current_dist = 0.0;
	for (int i = 0; i < u_max_raymarch_steps; i++)
	{
		vec2 sample_point = origin + dir * current_dist;
		sample_point.x /= aspect; // Convert back to UV space when sampling the distance field.

		// Early exit if we hit the edge of the screen.
		if (sample_point.x > 1.0 || sample_point.x < 0.0 || sample_point.y > 1.0 || sample_point.y < 0.0)
			return false;

		float dist_to_surface = texture(u_distance_data, sample_point).r / u_dist_mod;

		// We've hit a surface if distance field returns 0 or close to 0.
		if (dist_to_surface < 0.001)
		{
			hit_pos = sample_point;
			return true;
		}

		// If we don't hit a surface, continue marching along the ray.
		current_dist += dist_to_surface;
	}
	return false;
}

float random(vec2 st)
{
	return fract(sin(dot(st.xy, vec2(12.9898, 78.233))) * 43758.5453123);
}

void fragment()
{
	float pixel_emis = 0.0;
	vec3 pixel_col = vec3(0.0);

	// Convert from UV aspect to world aspect.
	vec2 uv = UV;
	float aspect = SCREEN_PIXEL_SIZE.y / SCREEN_PIXEL_SIZE.x;
	uv.x *= aspect;

	float rand2pi = random(UV * vec2(TIME, -TIME)) * 2.0 * PI;
	float golden_angle = PI * 0.7639320225; // Gives a good ray distribution.

	// Cast our rays.
	for (int i = 0; i < u_rays_per_pixel; i++)
	{
		float cur_angle = rand2pi + golden_angle * float(i);
		vec2 ray_dir = normalize(vec2(cos(cur_angle), sin(cur_angle)));
		vec2 ray_origin = uv;

		vec2 hit_pos;
		bool hit = raymarch(ray_origin, ray_dir, aspect, hit_pos);
		if (hit)
		{
			float mat_emissive;
			vec3 mat_colour;
			get_surface(hit_pos, mat_emissive, mat_colour);

			pixel_emis += mat_emissive;
			pixel_col += mat_colour;
		}
	}

	pixel_col /= pixel_emis;
	pixel_emis /= float(u_rays_per_pixel);

	COLOR = vec4(pixel_emis * pixel_col, 1.0);
}
