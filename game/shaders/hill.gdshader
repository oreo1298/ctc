// SPDX-FileCopyrightText: 2026 Siegefall contributors
// SPDX-License-Identifier: MIT
// Parallax hill silhouette. UV.x = x (layer px / 1000), UV.y = depth below
// the ridge in layer px / 100. Soft rim on the ridge, haze towards the base.
shader_type canvas_item;
render_mode unshaded;

#include "res://shaders/noise.gdshaderinc"

uniform vec4 color : source_color = vec4(0.5, 0.65, 0.5, 1.0);
uniform vec4 haze : source_color = vec4(0.85, 0.9, 0.92, 1.0);
uniform vec4 rim : source_color = vec4(1.0, 0.95, 0.85, 1.0);
uniform float haze_amount = 0.3;
uniform float rim_amount = 0.25;

void fragment() {
	float d = UV.y;
	vec3 c = color.rgb;
	c *= 0.95 + 0.1 * fbm(vec2(UV.x * 40.0, d * 2.0));
	c = mix(c, rim.rgb, (1.0 - smoothstep(0.0, 0.25, d)) * rim_amount);
	// Slightly darker and cooler away from the sunlit ridge, then valley mist.
	c *= 1.0 - smoothstep(0.3, 4.0, d) * 0.12;
	c = mix(c, haze.rgb, clamp(haze_amount + smoothstep(3.0, 9.0, d) * 0.25, 0.0, 1.0));
	COLOR = vec4(c, 1.0);
}
