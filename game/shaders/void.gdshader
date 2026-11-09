// SPDX-FileCopyrightText: 2026 Siegefall contributors
// SPDX-License-Identifier: MIT
// Mini black hole: a dark core inside a bright, swirling accretion ring.
shader_type canvas_item;

#include "res://shaders/noise.gdshaderinc"

uniform vec4 core_color : source_color = vec4(0.05, 0.02, 0.09, 1.0);
uniform vec4 ring_color : source_color = vec4(0.78, 0.62, 1.0, 1.0);

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	float a = atan(p.y, p.x);
	float swirl = fbm(vec2(a * 2.0 + r * 6.0 - TIME * 4.0, r * 3.0));
	float ring = smoothstep(0.38, 0.55, r) * (1.0 - smoothstep(0.6, 0.95, r));
	vec3 c = mix(core_color.rgb, ring_color.rgb, ring * (0.5 + swirl));
	float alpha = (1.0 - smoothstep(0.85, 1.0, r)) * (r < 0.42 ? 1.0 : 0.75 + ring * 0.25);
	COLOR = vec4(c, alpha);
}
