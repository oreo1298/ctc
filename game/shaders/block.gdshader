// SPDX-FileCopyrightText: 2026 Siegefall contributors
// SPDX-License-Identifier: MIT
//
// Procedural block material for bevel meshes built by ShapeGeometry.
// COLOR carries per-vertex edge data (rg = outward edge normal, b = distance
// to that edge / DIST_RANGE); UV is the pattern coordinate in metres.
// Produces: material pattern, ink outline, bevel normals for 2D lights, a
// rim light, and procedural cracks driven by `damage`.
shader_type canvas_item;

#include "res://shaders/noise.gdshaderinc"

// 0 wood, 1 stone, 2 glass, 3 ice, 4 iron, 5 thatch, 6 cloth, 7 rock (ammo)
uniform int pattern = 0;
uniform vec4 col_base : source_color = vec4(0.72, 0.51, 0.31, 1.0);
uniform vec4 col_dark : source_color = vec4(0.49, 0.31, 0.17, 1.0);
uniform vec4 col_light : source_color = vec4(0.88, 0.69, 0.48, 1.0);
uniform vec4 ink : source_color = vec4(0.231, 0.184, 0.149, 1.0);
uniform vec4 rim_color : source_color = vec4(1.0, 0.93, 0.8, 1.0);
uniform float outline_px = 2.6;
uniform float outline_max_m = 0.07;
uniform float bevel_m = 0.10;
uniform float damage : hint_range(0.0, 1.0) = 0.0;
uniform float seed = 0.0;
uniform float frozen : hint_range(0.0, 1.0) = 0.0;
uniform float charred : hint_range(0.0, 1.0) = 0.0;
uniform float flash : hint_range(0.0, 1.0) = 0.0;
uniform float rim_strength = 0.55;
// Up to 4 impact marks: xy = pattern-space centre (m), z = radius, w = strength.
uniform vec4 marks[4];
// Non-colour material cue (accessibility): stamps a small glyph pattern.
uniform float glyphs : hint_range(0.0, 1.0) = 0.0;

const float DIST_RANGE = 1.5;

varying vec3 edge;

void vertex() {
	edge = COLOR.rgb;
	COLOR = vec4(1.0);
}

vec3 pat_wood(vec2 p) {
	float warp = fbm(vec2(p.x * 0.6, p.y * 5.0) + seed) * 2.2;
	float rings = 0.5 + 0.5 * sin(p.y * 46.0 + warp * 4.0);
	vec3 c = mix(col_base.rgb, col_dark.rgb, smoothstep(0.55, 1.0, rings) * 0.55);
	c = mix(c, col_light.rgb, smoothstep(0.62, 0.95, fbm(p * vec2(1.2, 9.0) + seed * 3.1)) * 0.35);
	// an occasional knot
	vec2 cell = floor(p / vec2(0.9, 0.3));
	vec2 kc = (cell + vec2(0.5) + (hash22(cell + seed) - 0.5) * 0.5) * vec2(0.9, 0.3);
	float k = length((p - kc) * vec2(1.0, 2.5));
	float ring = 1.0 - smoothstep(0.012, 0.03, abs(k - 0.045));
	c = mix(c, col_dark.rgb * 0.85, ring * step(hash12(cell + seed * 1.3), 0.3) * 0.7);
	return c;
}

vec3 pat_stone(vec2 p, out float mortar) {
	vec2 b = p / vec2(0.62, 0.31);
	float row = floor(b.y);
	b.x += mod(row, 2.0) * 0.5;
	vec2 cell = floor(b);
	vec2 f = fract(b);
	float dm = min(min(f.x, 1.0 - f.x) * 0.62, min(f.y, 1.0 - f.y) * 0.31);
	mortar = 1.0 - smoothstep(0.012, 0.028, dm);
	float tint = hash12(cell + seed);
	vec3 c = mix(col_base.rgb, mix(col_dark.rgb, col_light.rgb, tint), 0.4);
	c *= 0.88 + 0.24 * fbm(p * 7.0 + seed);
	return mix(c, col_dark.rgb * 0.75, mortar);
}

vec3 pat_glass(vec2 p) {
	float streak = smoothstep(0.75, 1.0, sin((p.x + p.y) * 9.0 + seed) * 0.5 + 0.5);
	vec3 c = mix(col_base.rgb, col_light.rgb, streak * 0.6);
	return mix(c, col_dark.rgb, fbm(p * 3.0 + seed) * 0.25);
}

vec3 pat_ice(vec2 p) {
	vec2 v = voronoi(p * 3.0 + seed);
	vec3 c = mix(col_base.rgb, col_light.rgb, v.y * 0.5);
	return mix(c, col_dark.rgb, (1.0 - smoothstep(0.02, 0.06, v.x)) * 0.5);
}

vec3 pat_iron(vec2 p) {
	vec2 g = fract(p / 0.5) - 0.5;
	float rivet = 1.0 - smoothstep(0.035, 0.05, length(g - vec2(0.36, 0.36)));
	vec3 c = mix(col_base.rgb, col_dark.rgb, fbm(p * 4.0 + seed) * 0.45);
	c = mix(c, col_light.rgb, smoothstep(0.7, 1.0, fbm(p * vec2(0.5, 8.0) + seed)) * 0.3);
	return mix(c, col_light.rgb, rivet * 0.8);
}

vec3 pat_thatch(vec2 p) {
	float strands = sin(p.x * 70.0 + fbm(p * vec2(2.0, 12.0) + seed) * 6.0) * 0.5 + 0.5;
	float rows = smoothstep(0.85, 1.0, fract(p.y / 0.22));
	vec3 c = mix(col_base.rgb, col_light.rgb, strands * 0.35);
	return mix(c, col_dark.rgb, rows * 0.6 + (1.0 - strands) * 0.15);
}

vec3 pat_cloth(vec2 p) {
	float weave = (sin(p.x * 160.0) * sin(p.y * 160.0)) * 0.5 + 0.5;
	float stripe = step(0.5, fract(p.x / 0.4));
	vec3 c = mix(col_base.rgb, col_dark.rgb, stripe * 0.35);
	return mix(c, col_light.rgb, weave * 0.12);
}

vec3 pat_rock(vec2 p) {
	float m = fbm(p * 3.2 + seed);
	float blot = smoothstep(0.45, 0.75, fbm(p * 6.5 + seed * 2.0));
	vec3 c = mix(col_dark.rgb, col_base.rgb, smoothstep(0.25, 0.7, m));
	c = mix(c, col_light.rgb, blot * 0.35);
	vec2 v = voronoi(p * 4.0 + seed);
	return mix(c, col_dark.rgb * 0.8, (1.0 - smoothstep(0.015, 0.04, v.x)) * 0.35);
}

float cracks(vec2 p) {
	if (damage <= 0.001) {
		return 0.0;
	}
	vec2 v = voronoi(p * 2.4 + vec2(seed * 7.3, seed * 1.7));
	float line = 1.0 - smoothstep(0.0, 0.035 + damage * 0.02, v.x);
	// Reveal crack cells progressively with damage.
	float reveal = step(v.y, damage * 1.15);
	return line * reveal;
}

void fragment() {
	vec2 p = UV;
	vec2 n2 = edge.rg * 2.0 - 1.0;
	float d = edge.b * DIST_RANGE;
	float mortar = 0.0;
	vec3 albedo;
	if (pattern == 0) {
		albedo = pat_wood(p);
	} else if (pattern == 1) {
		albedo = pat_stone(p, mortar);
	} else if (pattern == 2) {
		albedo = pat_glass(p);
	} else if (pattern == 3) {
		albedo = pat_ice(p);
	} else if (pattern == 4) {
		albedo = pat_iron(p);
	} else if (pattern == 5) {
		albedo = pat_thatch(p);
	} else if (pattern == 6) {
		albedo = pat_cloth(p);
	} else {
		albedo = pat_rock(p);
	}

	// Soft painterly shading inside the face: lighter towards the top-left.
	albedo *= 0.94 + 0.08 * clamp(d / 0.6, 0.0, 1.0);

	// Status effects.
	albedo = mix(albedo, vec3(0.78, 0.92, 1.0), frozen * 0.55);
	albedo = mix(albedo, vec3(0.16, 0.12, 0.1), charred * 0.8);

	// Impact marks: a scuffed, darker dimple with a lighter lip.
	float dent = 0.0;
	for (int i = 0; i < 4; i++) {
		vec4 m = marks[i];
		if (m.z > 0.0) {
			float r = length(p - m.xy) / m.z;
			float jag = 0.85 + 0.3 * vnoise((p - m.xy) * 18.0);
			dent = max(dent, (1.0 - smoothstep(0.0, jag, r)) * m.w);
		}
	}
	albedo = mix(albedo, col_dark.rgb * 0.7, dent * 0.55);

	float cr = cracks(p);
	albedo = mix(albedo, ink.rgb * 0.9, cr * 0.85);

	if (glyphs > 0.5) {
		vec2 g = fract(p / 0.35) - 0.5;
		float mark = 0.0;
		if (pattern == 0) mark = 1.0 - smoothstep(0.02, 0.04, abs(g.y));
		else if (pattern == 1) mark = 1.0 - smoothstep(0.05, 0.08, length(g));
		else if (pattern == 2 || pattern == 3) mark = 1.0 - smoothstep(0.02, 0.04, abs(g.x - g.y));
		else if (pattern == 4) mark = 1.0 - smoothstep(0.02, 0.04, min(abs(g.x), abs(g.y)));
		else mark = 1.0 - smoothstep(0.02, 0.04, abs(abs(g.x) - abs(g.y)));
		albedo = mix(albedo, ink.rgb, mark * 0.35);
	}

	// Bevel: tilt the normal towards the edge within bevel_m of it.
	float t = clamp(d / bevel_m, 0.0, 1.0);
	float tilt = (1.0 - t * t * (3.0 - 2.0 * t)) * 0.9;
	vec2 nxy = n2 * tilt;
	// Mortar grooves and cracks also catch the light.
	nxy *= 1.0 - cr * 0.5;
	nxy += vec2(0.0, -dent * 0.35);
	// Godot's canvas NORMAL is y-up; our edge normals are y-down screen space.
	NORMAL = normalize(vec3(nxy.x, -nxy.y, 1.0 - tilt * 0.55 + mortar * 0.2));

	// Ink outline, anti-aliased by screen-space derivative.
	float fw = max(fwidth(d), 0.0001);
	float ow = min(outline_px * fw, outline_max_m);
	float o = 1.0 - smoothstep(ow - fw, ow + fw, d);
	albedo = mix(albedo, ink.rgb, o);
	albedo = mix(albedo, vec3(1.0), flash * 0.6);
	COLOR = vec4(albedo, 1.0);
}

void light() {
	float ndl = dot(NORMAL, LIGHT_DIRECTION);
	float wrap = clamp((ndl + 0.3) / 1.3, 0.0, 1.0);
	vec3 lit = COLOR.rgb * LIGHT_COLOR.rgb * LIGHT_ENERGY * wrap;
	// Rim: bevels that face the light glow a little.
	float facing = clamp(dot(normalize(NORMAL.xy + vec2(1e-5)), normalize(LIGHT_DIRECTION.xy + vec2(1e-5))), 0.0, 1.0);
	float rim = pow(clamp(1.0 - NORMAL.z, 0.0, 1.0), 1.5) * facing * rim_strength;
	lit += rim_color.rgb * LIGHT_COLOR.rgb * LIGHT_ENERGY * rim;
	LIGHT = vec4(lit, LIGHT_COLOR.a);
}
