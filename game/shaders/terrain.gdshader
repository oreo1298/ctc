// SPDX-FileCopyrightText: 2026 Siegefall contributors
// SPDX-License-Identifier: MIT
// Ground strip: UV.x = x in metres, UV.y = depth below the surface in metres.
shader_type canvas_item;

#include "res://shaders/noise.gdshaderinc"

uniform vec4 top_color : source_color = vec4(0.55, 0.76, 0.4, 1.0);
uniform vec4 body_color : source_color = vec4(0.43, 0.62, 0.3, 1.0);
uniform vec4 deep_color : source_color = vec4(0.3, 0.43, 0.23, 1.0);
uniform vec4 soil_color : source_color = vec4(0.47, 0.37, 0.28, 1.0);
uniform vec4 ink : source_color = vec4(0.231, 0.184, 0.149, 1.0);
uniform float outline_px = 3.0;
uniform float outline_max_m = 0.09;
uniform float band_m = 0.55;
// 0 grass, 1 sand, 2 snow, 3 rock
uniform int style = 0;

void fragment() {
	float x = UV.x;
	float d = UV.y;
	// Scalloped, slightly ragged underside of the turf.
	float scallop = abs(sin(x * 2.6)) * 0.06 + (fbm(vec2(x * 1.7, 0.0)) - 0.5) * 0.14;
	float band = band_m + scallop;
	vec3 c;
	if (d < band) {
		float k = smoothstep(0.0, band, d);
		c = mix(top_color.rgb, body_color.rgb, k * 0.75);
		if (style == 1) {
			// wind ripples in sand
			c *= 0.95 + 0.08 * sin(x * 9.0 + fbm(vec2(x, d) * 2.0) * 4.0);
		} else if (style == 2) {
			// soft snow with a cool shadow towards its underside
			c = mix(c, vec3(0.75, 0.83, 0.95), smoothstep(0.2, 1.0, d / band) * 0.4);
			c *= 0.98 + 0.03 * vnoise(vec2(x * 6.0, d * 3.0));
		} else if (style == 3) {
			c *= 0.9 + 0.15 * fbm(vec2(x * 3.0, d * 6.0));
		} else {
			c *= 0.94 + 0.1 * vnoise(vec2(x * 18.0, d * 6.0));
		}
		// soft shadow at the bottom of the turf
		c = mix(c, deep_color.rgb, smoothstep(band - 0.08, band, d) * 0.45);
	} else {
		float k = smoothstep(band, band + 4.0, d);
		vec3 soil = mix(soil_color.rgb, deep_color.rgb, 0.25);
		c = mix(soil, deep_color.rgb * 0.7, k);
		float strata = sin(d * 3.2 + fbm(vec2(x * 0.35, d * 0.6)) * 4.0) * 0.5 + 0.5;
		c *= 0.93 + 0.1 * strata;
		c *= 0.95 + 0.08 * fbm(vec2(x, d) * 2.5);
		// turf lip shadow
		c = mix(c, ink.rgb, (1.0 - smoothstep(0.0, 0.1, d - band)) * 0.3);
	}
	float fw = max(fwidth(d), 0.0001);
	float ow = min(outline_px * fw, outline_max_m);
	float o = 1.0 - smoothstep(ow - fw, ow + fw, d);
	c = mix(c, ink.rgb, o);
	float tilt = (1.0 - smoothstep(0.0, 0.25, d)) * 0.7;
	NORMAL = normalize(vec3(0.0, tilt, 1.0 - tilt * 0.5));
	COLOR = vec4(c, 1.0);
}

void light() {
	float ndl = dot(NORMAL, LIGHT_DIRECTION);
	float wrap = clamp((ndl + 0.35) / 1.35, 0.0, 1.0);
	LIGHT = vec4(COLOR.rgb * LIGHT_COLOR.rgb * LIGHT_ENERGY * wrap, LIGHT_COLOR.a);
}
