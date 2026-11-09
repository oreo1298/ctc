// SPDX-FileCopyrightText: 2026 Siegefall contributors
// SPDX-License-Identifier: MIT
// Painted procedural sky: gradient, sun or moon with glow, posterised
// brush-stroke clouds that drift with the camera, and stars at night.
shader_type canvas_item;
render_mode unshaded;

#include "res://shaders/noise.gdshaderinc"

uniform vec4 sky_top : source_color = vec4(0.47, 0.71, 0.88, 1.0);
uniform vec4 sky_horizon : source_color = vec4(0.87, 0.94, 0.96, 1.0);
uniform vec4 haze : source_color = vec4(0.84, 0.9, 0.92, 1.0);
uniform vec4 sun_color : source_color = vec4(1.0, 0.95, 0.84, 1.0);
uniform vec4 cloud_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform vec2 sun_uv = vec2(0.18, 0.3);
uniform float sun_radius = 0.045;
uniform bool moon = false;
uniform float stars = 0.0;
uniform float aspect = 1.7778;
uniform vec2 cam_offset = vec2(0.0);
uniform float time_s = 0.0;
uniform int octaves_hint = 4;

float clouds(vec2 p) {
	float n = fbm(p);
	if (octaves_hint > 3) {
		n = n * 0.8 + 0.2 * vnoise(p * 7.0);
	}
	return n;
}

void fragment() {
	vec2 uv = SCREEN_UV;
	float h = smoothstep(0.0, 0.92, uv.y);
	vec3 c = mix(sky_top.rgb, sky_horizon.rgb, h * h * (3.0 - 2.0 * h));
	c = mix(c, haze.rgb, smoothstep(0.7, 1.0, uv.y) * 0.6);

	// stars
	if (stars > 0.0) {
		vec2 g = uv * vec2(aspect, 1.0) * 140.0;
		float s = hash12(floor(g));
		float tw = 0.6 + 0.4 * sin(time_s * 2.0 + s * 40.0);
		float star = step(0.993, s) * (1.0 - smoothstep(0.05, 0.3, length(fract(g) - 0.5)));
		c += vec3(star * tw * stars * (1.0 - uv.y));
	}

	// sun / moon
	vec2 d = (uv - sun_uv) * vec2(aspect, 1.0);
	float r = length(d);
	float disc = 1.0 - smoothstep(sun_radius - 0.004, sun_radius, r);
	float glow = exp(-r * (moon ? 14.0 : 7.0)) * (moon ? 0.35 : 0.55);
	c += sun_color.rgb * glow;
	if (moon) {
		float bite = 1.0 - smoothstep(sun_radius - 0.004, sun_radius, length(d - vec2(0.018, -0.012)));
		disc *= 1.0 - bite * 0.85;
	}
	c = mix(c, mix(sun_color.rgb, vec3(1.0), 0.5), disc);

	// painted clouds in two bands
	vec2 cp = vec2(uv.x * aspect * 2.4 + cam_offset.x * 0.00004 + time_s * 0.004, uv.y * 6.5);
	float band = smoothstep(0.06, 0.22, uv.y) * (1.0 - smoothstep(0.34, 0.52, uv.y));
	float n = clouds(cp + vec2(0.0, cam_offset.y * 0.00002)) * band;
	float body = smoothstep(0.46, 0.49, n);
	float lit = smoothstep(0.53, 0.56, n + (0.3 - uv.y) * 0.25);
	vec3 shade = mix(cloud_color.rgb, sky_top.rgb, 0.35);
	vec3 cc = mix(shade, cloud_color.rgb, lit);
	cc = mix(cc, sun_color.rgb, lit * 0.25);
	c = mix(c, cc, body * 0.92);

	// gentle vignette towards the corners
	vec2 q = uv - 0.5;
	c *= 1.0 - dot(q, q) * 0.18;
	COLOR = vec4(c, 1.0);
}
