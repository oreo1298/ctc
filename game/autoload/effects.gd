# SPDX-FileCopyrightText: 2026 Siegefall contributors
# SPDX-License-Identifier: MIT
extends Node
## Fire-and-forget visual effects. Particles are CPUParticles2D so they work
## identically on the Mobile and Compatibility renderers.

signal shake_requested(trauma: float)

var particle_scale: float = 1.0
var _soft: Texture2D = null


func _ready() -> void:
	particle_scale = (
		1.0 if RenderingServer.get_current_rendering_method() != "gl_compatibility" else 0.6
	)


func shake(trauma: float) -> void:
	if Settings.screen_shake:
		shake_requested.emit(trauma)


func _burst(parent: Node, pos: Vector2, amount: int, life: float) -> CPUParticles2D:
	var p := CPUParticles2D.new()
	p.one_shot = true
	p.explosiveness = 0.95
	p.amount = maxi(1, roundi(amount * particle_scale))
	p.lifetime = life
	p.position = pos
	p.local_coords = false
	p.emitting = true
	parent.add_child(p)
	p.finished.connect(p.queue_free)
	return p


## Chips of material plus a lingering dust cloud.
func debris_burst(
	parent: Node, pos: Vector2, _material_id: String, mat: Dictionary, area_m2: float
) -> void:
	if parent == null:
		return
	var colors: Dictionary = mat.get("colors", {})
	var base: Color = Units.color(colors.get("base"), Color.TAN)
	var dark: Color = Units.color(colors.get("dark"), Color.SADDLE_BROWN)
	var chips := _burst(parent, pos, clampi(int(area_m2 * 30.0), 8, 40), 1.4)
	chips.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
	chips.emission_sphere_radius = 30.0 * sqrt(area_m2)
	chips.direction = Vector2.UP
	chips.spread = 80.0
	chips.initial_velocity_min = 120.0
	chips.initial_velocity_max = 420.0
	chips.gravity = Vector2(0, 980)
	chips.angular_velocity_min = -400.0
	chips.angular_velocity_max = 400.0
	chips.scale_amount_min = 5.0
	chips.scale_amount_max = 13.0
	var grad := Gradient.new()
	grad.set_color(0, base)
	grad.set_color(1, dark)
	chips.color_initial_ramp = grad
	dust(parent, pos, sqrt(area_m2) * 1.2, base.lerp(Color(0.92, 0.88, 0.8), 0.6))


## Soft dust that drifts and hangs in the air for a few seconds.
func dust(parent: Node, pos: Vector2, size: float, tint: Color = Color(0.9, 0.86, 0.78)) -> void:
	var d := _burst(parent, pos, clampi(int(size * 10.0), 6, 26), 4.5)
	d.explosiveness = 0.85
	d.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
	d.emission_sphere_radius = 45.0 * size
	d.direction = Vector2.UP
	d.spread = 180.0
	d.initial_velocity_min = 20.0
	d.initial_velocity_max = 90.0
	d.gravity = Vector2(6, -8)
	d.damping_min = 30.0
	d.damping_max = 50.0
	# The soft texture is 64 px wide: scale 1.0 is a 0.64 m puff.
	d.scale_amount_min = 0.9 * size
	d.scale_amount_max = 2.1 * size
	d.texture = soft_circle()
	var ramp := Gradient.new()
	ramp.set_color(0, Color(tint, 0.0))
	ramp.add_point(0.12, Color(tint, 0.38))
	ramp.add_point(0.6, Color(tint, 0.22))
	ramp.set_color(1, Color(tint, 0.0))
	d.color_ramp = ramp
	var sc := Curve.new()
	sc.add_point(Vector2(0, 0.4))
	sc.add_point(Vector2(1, 1.0))
	d.scale_amount_curve = sc
	d.z_index = 5


## Cartoon "poof" for eliminated royals.
func poof(parent: Node, pos: Vector2) -> void:
	dust(parent, pos, 1.1, Color(1, 1, 1))
	var stars := _burst(parent, pos, 10, 0.8)
	stars.direction = Vector2.UP
	stars.spread = 180.0
	stars.initial_velocity_min = 150.0
	stars.initial_velocity_max = 320.0
	stars.gravity = Vector2(0, 300)
	stars.scale_amount_min = 6.0
	stars.scale_amount_max = 11.0
	stars.color = Color(1.0, 0.85, 0.3)
	stars.z_index = 6


func soft_circle() -> Texture2D:
	if _soft != null:
		return _soft
	var g := GradientTexture2D.new()
	g.width = 64
	g.height = 64
	g.fill = GradientTexture2D.FILL_RADIAL
	g.fill_from = Vector2(0.5, 0.5)
	g.fill_to = Vector2(0.5, 0.0)
	var grad := Gradient.new()
	grad.set_color(0, Color(1, 1, 1, 1))
	grad.set_color(1, Color(1, 1, 1, 0))
	g.gradient = grad
	_soft = g
	return _soft
