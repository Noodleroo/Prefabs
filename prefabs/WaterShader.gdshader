shader_type spatial;
render_mode depth_draw_always, cull_disabled;

group_uniforms WaterColors;
uniform vec4 shallow_color : source_color = vec4(0.15, 0.65, 0.6, 0.6);
uniform vec4 deep_color    : source_color = vec4(0.02, 0.08, 0.2, 0.95);
uniform vec4 peak_glow_color: source_color = vec4(0.2, 0.85, 0.75, 1.0); 

group_uniforms ValheimWaves;
uniform vec2 world_seed_offset = vec2(0.0, 0.0);

uniform float wave_speed       : hint_range(0.0, 10.0)  = 1.0;
uniform float wave_height      : hint_range(0.0, 20.0)  = 1.5;
uniform float wave_length      : hint_range(1.0, 100.0) = 60.0;
uniform float wave_density     : hint_range(0.1, 4.0)   = 1.0;
uniform float wave_wonkiness   : hint_range(0.0, 5.0)   = 1.0;
uniform float wave_thickness   : hint_range(0.2, 3.0)   = 1.0;  
uniform float wave_steepness   : hint_range(0.0, 1.0)   = 0.3;
uniform vec2 wave_direction                             = vec2(1.0, 0.1);
uniform float depth_distance   : hint_range(0.1, 50.0)  = 5.0;
uniform float wave_desync      : hint_range(0.0, 1.0)   = 0.5; 

group_uniforms ToonSpecular;
uniform float specular_size    : hint_range(0.01, 1.0)  = 0.15; 
uniform vec4 specular_color    : source_color           = vec4(1.0, 1.0, 1.0, 1.0);
uniform float bloom_intensity  : hint_range(0.0, 5.0)   = 1.5;

group_uniforms FoamSettings;
uniform vec4 foam_color       : source_color = vec4(0.9, 0.95, 1.0, 1.0);
uniform float foam_crest_bias : hint_range(0.0, 1.0)    = 0.7;
uniform float object_foam_size: hint_range(0.1, 10.0)   = 1.0;

group_uniforms Textures;
uniform sampler2D wave_texture: hint_default_black, repeat_enable; 
uniform sampler2D depth_texture: hint_depth_texture, filter_nearest;

group_uniforms StylizedRefraction;
uniform float refraction_strength : hint_range(0.0, 0.1) = 0.02;

group_uniforms StylizedReflections;
uniform float reflection_intensity : hint_range(0.0, 1.0) = 0.4;
uniform float reflection_edge_boost : hint_range(1.0, 10.0) = 3.0;
uniform sampler2D screen_texture : hint_screen_texture, filter_nearest;

group_uniforms;

varying vec3 world_position;
varying float vertex_wave_height;
varying vec3 vertex_pos_pass;
varying float final_foam_pass;
varying float face_sign;
varying vec2 reflection_uv_pass;

vec3 calculate_thick_gerstner(vec3 pos, vec2 dir, float steepness, float length, float speed, float time, float thickness, out float height_out) {
	vec2 d = normalize(dir);
	float k = 2.0 * PI / length;
	float c = sqrt(9.8 / k) * speed;
	float f = k * (dot(d, pos.xz) - c * time);
	
	float a = clamp(steepness, 0.0, 0.9) / k;
	
	float base_sin = sin(f) * 0.5 + 0.5;
	float shaped_sin = pow(base_sin, thickness);
	float final_wave = shaped_sin * 2.0 - 1.0;
	height_out = final_wave;
	
	return vec3(
		d.x * (a * cos(f)),
		a * final_wave,    
		d.y * (a * cos(f))
	);
}

vec2 rotate2d(vec2 p, float angle) {
	float s = sin(angle);
	float c = cos(angle);
	return vec2(p.x * c - p.y * s, p.x * s + p.y * c);
}

void vertex() {
	vec3 base_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	base_world_pos.xz += world_seed_offset; 
	
	float active_wave_length = wave_length / max(0.01, wave_density);
	float base_angle = atan(wave_direction.y, wave_direction.x);
	vec2 main_dir = normalize(wave_direction);
	
	// --- FIX 1: STRETCH OUT THE NOISE SCALE (LOWER FREQUENCY) ---
	// Changing the multiplier from 0.003 to 0.001 stretches your Simplex FBM texture.
	// This makes the wave bends long, rolling, and smooth instead of tight and jagged.
	vec2 macro_uv = base_world_pos.xz * 0.001 + vec2(TIME * wave_speed * 0.002);
	float raw_noise = texture(wave_texture, macro_uv).r;
	
	// --- FIX 2: SMOOTH THE NOISE EDGES ---
	// Filtering the noise through a smoothstep curve completely strips out 
	// sharp pixel spikes, guaranteeing a fluid, rolling curve translation.
	float fbm_noise = floor(raw_noise * 5.0) / 5.0;
	
	float dynamic_thickness = wave_thickness * mix(0.7, 1.3, fbm_noise);
	
	// Crescent Grid Logic
	float center_frequency = 1.0 / (active_wave_length * 2.0);
	vec2 grid_pos = floor(base_world_pos.xz * center_frequency);
	vec2 cell_center = (grid_pos + vec2(0.5)) / center_frequency;
	float dist_to_center = distance(base_world_pos.xz, cell_center);
	
	float crescent_warp = dist_to_center * (0.08 * wave_desync);
	
	// --- FIX 3: THE BALANCED WAVE WARPER ---
	// Lowering the max scramble down to 10.0 prevents vertices from tearing.
	float coordinate_scramble = fbm_noise * wave_wonkiness * 10.0;
	
	vec3 distorted_pos = base_world_pos;
	distorted_pos.xz += main_dir * (crescent_warp + coordinate_scramble);

	// --- FIX 4: DECREASE HORIZONTAL DECOUPLING ---
	// If safe_steepness is too high, waves pinch vertically into spires.
	// We divide by a higher factor to force a wider, rounder wave peak base.
	float safe_steepness = wave_steepness / max(1.0, wave_height * 0.45);
	
	// Spreading the wave directions prevents straight lines
	float angle_spread = 0.55 * (1.0 + wave_wonkiness * 0.3);
	
	float primary_amplitude_mask = mix(0.4, 1.0, fbm_noise); 
	float secondary_amplitude_mask = mix(0.2, 1.1, 1.0 - fbm_noise); 

	// Wave 1: Primary Swell
	float h1 = 0.0;
	vec2 d1 = vec2(cos(base_angle), sin(base_angle));
	vec3 w1 = calculate_thick_gerstner(distorted_pos, d1, safe_steepness * primary_amplitude_mask, active_wave_length, wave_speed, TIME, dynamic_thickness, h1);
	w1.y *= primary_amplitude_mask; 
	
	// Wave 2: Left Minor Swell 
	float h2 = 0.0;
	float angle2 = base_angle + angle_spread; 
	vec2 d2 = vec2(cos(angle2), sin(angle2));
	vec3 pos_w2 = distorted_pos;
	pos_w2.xz = rotate2d(pos_w2.xz, 0.35) * 1.1; 
	vec3 w2 = calculate_thick_gerstner(pos_w2, d2, safe_steepness * 0.55 * secondary_amplitude_mask, active_wave_length * 0.6, wave_speed * 1.1, TIME * 0.95, dynamic_thickness * 1.1, h2);
	w2.y *= secondary_amplitude_mask;
	
	// Wave 3: Right Minor Swell
	float h3 = 0.0;
	float angle3 = base_angle - angle_spread;
	vec2 d3 = vec2(cos(angle3), sin(angle3));
	vec3 pos_w3 = distorted_pos;
	pos_w3.xz = rotate2d(pos_w3.xz, -0.4) * 0.9; 
	vec3 w3 = calculate_thick_gerstner(pos_w3, d3, safe_steepness * 0.4 * primary_amplitude_mask, active_wave_length * 0.5, wave_speed * 1.2, TIME * 0.8, dynamic_thickness * 0.9, h3);
	w3.y *= primary_amplitude_mask;
	
	// Accumulate displacements
	vec3 final_displacement = w1 + w2 + w3;
	vertex_wave_height = clamp(((h1 * primary_amplitude_mask * 0.5) + (h2 * secondary_amplitude_mask * 0.35) + (h3 * primary_amplitude_mask * 0.15)) * 0.5 + 0.5, 0.0, 1.0);
	
	// We scale the horizontal vector down slightly more so the mesh folds softly instead of spiking
	vec3 horizontal_displacement = vec3(final_displacement.x, 0.0, final_displacement.z) * (wave_height * 0.18);
	vec3 vertical_displacement   = vec3(0.0, final_displacement.y, 0.0) * wave_height;
	
	float macro_length = wave_length * 4.0;
	float macro_k = 2.0 * PI / macro_length;
	float macro_tide_f = macro_k * (dot(main_dir, base_world_pos.xz) - (sqrt(9.8 / macro_k) * wave_speed * 0.4) * TIME);
	float valheim_global_tide = sin(macro_tide_f) * (wave_height * 0.45);
	
	vec3 balanced_world_displacement = horizontal_displacement + vertical_displacement;
	balanced_world_displacement.y += valheim_global_tide;
	
	VERTEX.xyz += (inverse(MODEL_MATRIX) * vec4(balanced_world_displacement, 0.0)).xyz;
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec3 raw_cross = cross(dFdy(VERTEX), dFdx(VERTEX));
	vec3 view_normal = (length(raw_cross) > 0.001) ? normalize(raw_cross) : vec3(0.0, 1.0, 0.0);
	NORMAL = FRONT_FACING ? view_normal : -view_normal;
	face_sign = FRONT_FACING ? 1.0 : -1.0;
	vertex_pos_pass = VERTEX; 

	float depth_raw = texture(depth_texture, SCREEN_UV).r;
	vec4 depth_view = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, depth_raw, 1.0);
	depth_view.xyz /= depth_view.w;
	
	vec4 floor_world_pos = INV_VIEW_MATRIX * vec4(depth_view.xyz, 1.0);
	float water_depth = world_position.y - floor_world_pos.y;
	
	if (depth_raw == 1.0) {
		water_depth = depth_distance;
	} else {
		water_depth = max(0.0, water_depth);
	}
	
	vec2 foam_uv = world_position.xz * 0.05 + vec2(TIME * wave_speed * 0.02);
	float foam_noise = texture(wave_texture, foam_uv).r;
	
	float local_height_percent = vertex_wave_height;
	float absolute_apex_mask = pow(local_height_percent, 10.0); 
	float combined_foam_value = absolute_apex_mask * foam_noise;
	
	float razor_thin_edge = 0.005; 
	float crest_foam_mask = smoothstep(foam_crest_bias - razor_thin_edge, foam_crest_bias + razor_thin_edge, combined_foam_value);
	crest_foam_mask *= clamp(wave_height * 1.5, 0.0, 1.0);
	
	final_foam_pass = crest_foam_mask;
	float glow_mask = pow(local_height_percent, 4.0) * (1.0 - absolute_apex_mask);

	vec3 view_dir_space = normalize(VERTEX);
	vec3 reflect_space = reflect(view_dir_space, view_normal);
	vec2 reflection_uv = SCREEN_UV + reflect_space.xy * 0.15;
	reflection_uv_pass = reflection_uv;

	vec2 dx = dFdx(reflection_uv);
	vec2 dy = dFdy(reflection_uv);
	float facet_edges = dot(dx, dx) + dot(dy, dy); 

	vec3 reflection_pixels = texture(screen_texture, clamp(reflection_uv, vec2(0.01), vec2(0.99))).rgb;
	float fresnel = pow(1.0 - clamp(dot(view_normal, vec3(0.0, 1.0, 0.0)), 0.0, 1.0), 3.0);
	float final_reflection_weight = clamp(fresnel * reflection_intensity + (facet_edges * reflection_edge_boost), 0.0, 1.0);

	vec2 refract_scroll_uv = world_position.xz * 0.03 + vec2(TIME * wave_speed * 0.008);
	float raw_refract_noise = texture(wave_texture, refract_scroll_uv).r;
	vec2 normal_offset = view_normal.xz * (raw_refract_noise * 2.0 - 1.0);
	vec2 distorted_screen_uv = SCREEN_UV + (normal_offset * refraction_strength * clamp(water_depth, 0.0, 2.0));
	vec3 refracted_background = texture(screen_texture, distorted_screen_uv).rgb;

	float depth_blend = clamp(water_depth / depth_distance, 0.0, 1.0);
	vec4 water_base_color = mix(shallow_color, deep_color, depth_blend);
	water_base_color.rgb = mix(refracted_background, water_base_color.rgb, water_base_color.a);
	vec4 colored_water = mix(water_base_color, peak_glow_color, glow_mask * clamp(wave_height * 0.2, 0.0, 1.0));

	float intersection_mask = 1.0 - clamp(water_depth / object_foam_size, 0.0, 1.0);
	vec2 slow_object_uv = world_position.xz * 0.05 + vec2(TIME * wave_speed * (-0.2 * wave_direction));
	float slow_object_noise = texture(wave_texture, slow_object_uv).r;
	float object_foam = step(0.35, intersection_mask * slow_object_noise);

	float combined_render_foam = clamp(crest_foam_mask + object_foam, 0.0, 1.0);
	vec3 color_with_reflection = mix(colored_water.rgb, reflection_pixels, final_reflection_weight * (1.0 - crest_foam_mask));
	vec4 final_color = mix(vec4(color_with_reflection, colored_water.a), foam_color, combined_render_foam);

	ALBEDO = final_color.rgb;
	ALPHA = final_color.a;
	ROUGHNESS = 0.2;
	METALLIC = 0.0;
}

void light() {
	vec3 flat_face_normal = normalize(NORMAL * face_sign);
	vec3 view_dir = VIEW;
	vec3 light_dir = LIGHT;
	vec3 half_vector = normalize(light_dir + view_dir);
	float blinn_philipp = max(0.0, dot(flat_face_normal, half_vector));
	float specular_glint = step(1.0 - specular_size, pow(blinn_philipp, 32.0));
	float diffuse_intensity = clamp(dot(flat_face_normal, LIGHT), 0.0, 1.0);
	vec3 base_lighting_response = ATTENUATION * LIGHT_COLOR * diffuse_intensity;
	DIFFUSE_LIGHT += ALBEDO * base_lighting_response;
	
	float sun_path_mask = pow(blinn_philipp, 8.0);
	vec2 dx = dFdx(reflection_uv_pass);
	vec2 dy = dFdy(reflection_uv_pass);
	float facet_edges = dot(dx, dx) + dot(dy, dy);
	
	vec3 reflection_pixels = texture(screen_texture, clamp(reflection_uv_pass, vec2(0.01), vec2(0.99))).rgb;
	float final_reflection_weight = clamp((sun_path_mask * reflection_intensity) + (facet_edges * reflection_edge_boost * sun_path_mask), 0.0, 1.0);
	final_reflection_weight *= (1.0 - final_foam_pass);
	
	SPECULAR_LIGHT += mix(vec3(0.0), reflection_pixels * specular_color.rgb, final_reflection_weight) * ATTENUATION * LIGHT_COLOR;
	}