shader_type canvas_item;

// Coordinates in metres keep the field continuous across the entire map.
uniform vec2 world_origin;
uniform float terrain_seed;
uniform sampler2D road_mask : filter_linear, repeat_disable;
uniform vec2 hollow_center = vec2(64.0, 47.0);
uniform vec2 reedbank_center = vec2(180.0, 47.0);
uniform vec2 dust_center = vec2(122.0, 128.0);
// Weather per town (x: Alder Hollow, y: Reedbank, z: Dustvale), each 0..1; blended by distance.
uniform vec3 town_wet = vec3(0.0);
uniform vec3 town_snow = vec3(0.0);
uniform vec3 town_mud = vec3(0.0);
// How much of each season shows (spring, summer, autumn, winter); sums to 1.
uniform vec4 season_weights = vec4(0.0, 1.0, 0.0, 0.0);
varying vec2 land;

void vertex() {
	land = (VERTEX + world_origin) / 24.0;
}

float hash_cell(vec2 p) {
	vec3 q = fract(vec3(p.xyx) * 0.1031);
	q += dot(q, q.yzx + 33.33);
	return fract((q.x + q.y) * q.z);
}

float field(vec2 p) {
	vec2 cell = floor(p);
	vec2 f = fract(p);
	vec2 blend = f * f * (3.0 - 2.0 * f);
	return mix(
		mix(hash_cell(cell), hash_cell(cell + vec2(1.0, 0.0)), blend.x),
		mix(hash_cell(cell + vec2(0.0, 1.0)), hash_cell(cell + vec2(1.0, 1.0)), blend.x),
		blend.y);
}

void fragment() {
	vec2 p = land + vec2(terrain_seed * 0.013, terrain_seed * 0.017);
	vec2 warp = vec2(field(p * 0.023), field(p * 0.027 + 34.0)) * 15.0;
	vec2 warped = p + warp;
	float masses = field(warped * 0.037) * 0.69 + field(warped * 0.105) * 0.31;
	float hollow = length((land - hollow_center) / vec2(35.0, 27.0));
	float reedbank = length((land - reedbank_center) / vec2(34.0, 26.0));
	float village = 1.0 - smoothstep(0.52, 1.21, min(hollow, reedbank));
	// Dustvale, in the south: dry, pink-brown ground with thin, patchy cover.
	float dust = 1.0 - smoothstep(0.55, 1.35, length((land - dust_center) / vec2(50.0, 40.0)));
	float upland = 1.0 - smoothstep(0.35, 1.4, length((land - vec2(89.0, 0.0)) / vec2(48.0, 24.0)));
	float broken_edge = (field(warped * 0.32) - 0.5) * 0.077;
	float woodland = smoothstep(0.43, 0.545, masses + 0.045 + broken_edge - village * 0.37 - upland * 0.22 - dust * 0.62);

	float ground_grain = field(vec2(p.x * 1.9, p.y * 3.7));
	float earth_bands = field(warped * vec2(0.27, 0.48));
	vec3 loam = mix(vec3(0.50, 0.33, 0.19), vec3(0.78, 0.62, 0.36), earth_bands * 0.68 + ground_grain * 0.32);
	// Packed reddish earth around the settlements, as in the top-down references.
	loam = mix(loam, vec3(0.50, 0.30, 0.18), village * 0.55);
	// Pink dust over the dry ground, with lighter, paler streaks.
	loam = mix(loam, mix(vec3(0.58, 0.43, 0.40), vec3(0.74, 0.60, 0.55), earth_bands * 0.7 + ground_grain * 0.3), dust * 0.88);

	// Small undergrowth patches give the forest texture at overview zoom.
	vec2 leaf = p * 0.76 + vec2(field(p * 0.62 + 8.0), field(p * 0.71 + 29.0)) * 0.83;
	vec2 leaf_cell = floor(leaf);
	vec2 leaf_center = vec2(hash_cell(leaf_cell + 16.0), hash_cell(leaf_cell + 71.0)) * 0.66 + 0.17;
	vec2 leaf_offset = (fract(leaf) - leaf_center) * vec2(1.0, 1.28);
	float undergrowth = 1.0 - smoothstep(0.06, 0.61, length(leaf_offset));
	float green = field(warped * 0.42) * 0.65 + undergrowth * 0.24 + ground_grain * 0.11;
	vec3 fern = mix(vec3(0.02, 0.085, 0.06), vec3(0.11, 0.24, 0.16), green);
	fern = mix(fern, vec3(0.34, 0.33, 0.17), dust * 0.75);  // scrub looks olive and dry here
	// The seasons: fresh green in spring, deep green in summer, rust in autumn, dull in winter.
	vec3 fern_spring = fern * vec3(1.06, 1.22, 0.90) + vec3(0.01, 0.025, 0.0);
	vec3 fern_autumn = mix(fern, vec3(0.33, 0.19, 0.07), 0.45);
	vec3 fern_winter = mix(fern, vec3(0.17, 0.15, 0.12), 0.55);
	fern = fern_spring * season_weights.x + fern * season_weights.y + fern_autumn * season_weights.z + fern_winter * season_weights.w;
	loam = mix(loam, loam * vec3(0.90, 0.92, 0.96), season_weights.w);
	vec3 color = mix(loam, fern, woodland);
	float grid_distance = min(fract(land.x + 0.5), fract(land.y + 0.5));
	float grid = (1.0 - smoothstep(0.0, 0.04, grid_distance)) * (1.0 - smoothstep(0.05, 0.12, fwidth(land.x)));
	float track = texture(road_mask, UV).r;
	float edge_grain = field(p * 0.91 + 13.0);
	float blend = smoothstep(0.06, 0.91, track + (edge_grain - 0.52) * track * 0.45);
	vec3 sand = mix(vec3(0.60, 0.48, 0.29), vec3(0.82, 0.73, 0.54), ground_grain * 0.40 + earth_bands * 0.60);
	float grit = smoothstep(0.69, 0.94, field(p * 10.0));
	sand *= 1.0 - grit * 0.20;
	sand = mix(sand, vec3(0.80, 0.66, 0.60), dust * 0.55);
	color = mix(color, sand, blend * 0.96);
	// Each place takes its nearest town's weather, blended softly between towns.
	vec3 d = vec3(length(land - hollow_center), length(land - reedbank_center), length(land - dust_center)) + 1.0;
	vec3 near = 1.0 / (d * d * d * d);
	near /= near.x + near.y + near.z;
	float wet = dot(near, town_wet);
	float snowy = dot(near, town_snow);
	float mud = dot(near, town_mud);
	color *= 1.0 - wet * 0.26;                                    // wet ground is darker
	color = mix(color, color * vec3(0.88, 0.93, 1.0), wet * 0.35);  // and a little cooler
	vec3 mud_color = mix(vec3(0.24, 0.16, 0.10), vec3(0.33, 0.23, 0.14), edge_grain);
	color = mix(color, mud_color, blend * smoothstep(0.3, 0.9, mud) * 0.92);   // muddy roads
	vec3 snow_color = mix(vec3(0.86, 0.90, 0.92), vec3(0.95, 0.97, 0.98), ground_grain);
	color = mix(color, snow_color, snowy * (0.9 - blend * 0.3));
	COLOR = vec4(color * (1.0 - grid * 0.065 * (1.0 - blend)), 1.0);
}
