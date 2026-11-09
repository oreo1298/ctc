# SPDX-FileCopyrightText: 2026 Siegefall contributors
# SPDX-License-Identifier: MIT
extends Node
## Juice: particles, screen shake requests, slow motion and haptics.
## Particles are CPUParticles2D so they behave the same on the Mobile and
## Compatibility renderers (counts are halved on the latter).

signal shake_requested(trauma: float)

## Physics always steps 1/BASE_TICKS seconds: slow motion runs *fewer* steps
## per real second instead of shorter ones, so outcomes never change.
const BASE_TICKS: int = 60

var particle_scale: float = 1.0
var _soft: Texture2D = null
var _splinter: Texture2D = null
var _shard: Texture2D = null
var _tongue: Texture2D = null
## Burning blocks with their own light (lights cost a pass per lit item).
var _fire_lights: int = 0
var _slowmo_until_usec: int = 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var compat: bool = RenderingServer.get_current_rendering_method() == "gl_compatibility"
	particle_scale = 0.6 if compat else 1.0


# ------------------------------------------------------------ time/shake ---
func shake(trauma: float) -> void:
	if Settings.screen_shake:
		shake_requested.emit(trauma)


## Slow time to `scale` (0.25, 0.3, 0.5 ...) for `real_seconds`.
func slow_motion(scale: float, real_seconds: float) -> void:
	if not Settings.slow_motion or Game.cli.has("no-slowmo"):
		return
	var ticks: int = maxi(1, roundi(BASE_TICKS * scale))
	Engine.physics_ticks_per_second = ticks
	Engine.time_scale = float(ticks) / BASE_TICKS
	_slowmo_until_usec = Time.get_ticks_usec() + int(real_seconds * 1_000_000.0)


func reset_time() -> void:
	_slowmo_until_usec = 0
	Engine.time_scale = 1.0
	Engine.physics_ticks_per_second = BASE_TICKS


func _process(_delta: float) -> void:
	if _slowmo_until_usec != 0 and Time.get_ticks_usec() >= _slowmo_until_usec:
		reset_time()


func haptic(strength: float) -> void:
	if Settings.haptics and OS.has_feature("mobile"):
		Input.vibrate_handheld(
			clampi(roundi(20.0 + strength * 60.0), 10, 90), clampf(strength, 0.1, 1.0)
		)


# ------------------------------------------------------------- textures ---
## A tongue of flame: round at the base, tapering to a point at the top,
## soft-edged. 48 x 96 px (0.48 x 0.96 m at scale 1).
func flame_tongue() -> Texture2D:
	if _tongue != null:
		return _tongue
	var w: int = 48
	var h: int = 96
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	for y: int in h:
		var v: float = (y + 0.5) / h
		var half: float
		if v > 0.7:
			half = sqrt(maxf(0.0, 1.0 - pow((v - 0.7) / 0.29, 2.0)))
		else:
			half = pow(v / 0.7, 1.5)
		for x: int in w:
			var u: float = absf((x + 0.5) / w * 2.0 - 1.0)
			var a: float = clampf((half - u) / 0.3, 0.0, 1.0)
			img.set_pixel(x, y, Color(1, 1, 1, a * a * (3.0 - 2.0 * a)))
	_tongue = ImageTexture.create_from_image(img)
	return _tongue


func soft_circle() -> Texture2D:
	if _soft == null:
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


## A thin sliver (wood splinters, straw) pointing along +y.
func splinter_texture() -> Texture2D:
	if _splinter == null:
		var img := Image.create(4, 16, false, Image.FORMAT_RGBA8)
		img.fill(Color(1, 1, 1, 1))
		for y: int in 16:
			var w: float = 1.0 - absf(y - 7.5) / 8.0
			for x: int in 4:
				img.set_pixel(
					x, y, Color(1, 1, 1, clampf(w * 2.0, 0.0, 1.0) * (1.0 if x in [1, 2] else 0.5))
				)
		_splinter = ImageTexture.create_from_image(img)
	return _splinter


## A small angular shard (glass, ice, stone grit).
func shard_texture() -> Texture2D:
	if _shard == null:
		var img := Image.create(12, 12, false, Image.FORMAT_RGBA8)
		img.fill(Color(0, 0, 0, 0))
		var tri := PackedVector2Array([Vector2(1, 11), Vector2(11, 8), Vector2(5, 0)])
		for y: int in 12:
			for x: int in 12:
				if Geometry2D.is_point_in_polygon(Vector2(x + 0.5, y + 0.5), tri):
					img.set_pixel(x, y, Color(1, 1, 1, 1))
		_shard = ImageTexture.create_from_image(img)
	return _shard


# ------------------------------------------------------------ particles ---
func _burst(parent: Node, pos: Vector2, amount: int, life: float) -> CPUParticles2D:
	var p := CPUParticles2D.new()
	p.one_shot = true
	p.explosiveness = 0.95
	p.amount = maxi(1, roundi(amount * particle_scale))
	p.lifetime = life
	p.position = pos
	p.local_coords = false
	p.emitting = true
	# Behind the terrain (z -1) and blocks: falling chips disappear into the
	# ground instead of drawing over the soil (CPU particles do not collide).
	p.z_index = -2
	parent.add_child(p)
	p.finished.connect(p.queue_free)
	return p


func _ramp(a: Color, b: Color) -> Gradient:
	var g := Gradient.new()
	g.set_color(0, a)
	g.set_color(1, b)
	return g


func _mat_colors(mat: Dictionary) -> Array[Color]:
	var colors: Dictionary = mat.get("colors", {})
	return [
		Units.color(colors.get("base"), Color.TAN),
		Units.color(colors.get("dark"), Color.SADDLE_BROWN),
		Units.color(colors.get("light"), Color.WHEAT),
	]


## Material-specific burst when a block breaks.
func break_burst(
	parent: Node, pos: Vector2, _material_id: String, mat: Dictionary, area_m2: float, style: String
) -> void:
	if parent == null:
		return
	var c: Array[Color] = _mat_colors(mat)
	var size: float = sqrt(area_m2)
	var n: int = 0
	match style:
		"splinter":
			n = clampi(int(area_m2 * 40.0), 8, 30)
			_flying(parent, pos, n, splinter_texture(), [c[0], c[1]], 1.0, true)
			dust(parent, pos, size * 0.8, c[2].lerp(Color(0.92, 0.88, 0.8), 0.6))
		"chunks":
			n = clampi(int(area_m2 * 30.0), 8, 30)
			_flying(parent, pos, n, shard_texture(), [c[0], c[1]], 1.2, false)
			dust(parent, pos, size * 1.6, c[2].lerp(Color(0.9, 0.87, 0.82), 0.5))
		"shards":
			n = clampi(int(area_m2 * 40.0), 8, 24)
			_flying(parent, pos, n, shard_texture(), [c[2], c[0]], 0.9, false)
			glitter(parent, pos, size)
		"dent":
			sparks(parent, pos, 1.0)
		"tufts":
			n = clampi(int(area_m2 * 80.0), 14, 40)
			_flying(parent, pos, n, splinter_texture(), [c[2], c[1]], 2.0, true, 0.35)
		"tear":
			_flying(parent, pos, 12, splinter_texture(), [c[0], c[1]], 1.5, true, 0.3)
		_:
			chips(parent, pos, mat, area_m2)


## Leftover tiny cells that are not worth a physics body.
func chips(parent: Node, pos: Vector2, mat: Dictionary, area_m2: float) -> void:
	var c: Array[Color] = _mat_colors(mat)
	var n: int = clampi(int(area_m2 * 200.0), 3, 10)
	_flying(parent, pos, n, shard_texture(), [c[0], c[1]], 1.0, false)


## colors = [start, end]
func _flying(
	parent: Node,
	pos: Vector2,
	amount: int,
	tex: Texture2D,
	colors: Array[Color],
	life: float,
	align: bool,
	grav_scale: float = 1.0
) -> void:
	var a: Color = colors[0]
	var b: Color = colors[1]
	var p := _burst(parent, pos, amount, life)
	p.texture = tex
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 30.0
	p.direction = Vector2.UP
	p.spread = 85.0
	p.initial_velocity_min = 140.0
	p.initial_velocity_max = 480.0
	p.gravity = Vector2(0, 980.0 * grav_scale)
	p.angular_velocity_min = -540.0
	p.angular_velocity_max = 540.0
	p.scale_amount_min = 0.8
	p.scale_amount_max = 1.8
	p.particle_flag_align_y = align
	p.color_initial_ramp = _ramp(a, b)
	var fade := Gradient.new()
	fade.set_color(0, Color.WHITE)
	fade.add_point(0.75, Color.WHITE)
	fade.set_color(1, Color(1, 1, 1, 0))
	p.color_ramp = fade


## Soft dust that drifts and hangs in the air for a few seconds.
func dust(parent: Node, pos: Vector2, size: float, tint: Color = Color(0.9, 0.86, 0.78)) -> void:
	var d := _burst(parent, pos, clampi(int(size * 10.0), 6, 26), 5.5)
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
	d.scale_amount_min = 1.0 * size
	d.scale_amount_max = 2.4 * size
	d.texture = soft_circle()
	var ramp := Gradient.new()
	ramp.set_color(0, Color(tint, 0.0))
	ramp.add_point(0.1, Color(tint, 0.45))
	ramp.add_point(0.55, Color(tint, 0.28))
	ramp.set_color(1, Color(tint, 0.0))
	d.color_ramp = ramp
	var sc := Curve.new()
	sc.add_point(Vector2(0, 0.45))
	sc.add_point(Vector2(1, 1.0))
	d.scale_amount_curve = sc
	d.z_index = 6


func glitter(parent: Node, pos: Vector2, size: float) -> void:
	var g := _burst(parent, pos, clampi(int(size * 8.0), 4, 10), 0.9)
	g.texture = soft_circle()
	g.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
	g.emission_sphere_radius = 40.0 * size
	g.direction = Vector2.UP
	g.spread = 180.0
	g.initial_velocity_min = 40.0
	g.initial_velocity_max = 160.0
	g.gravity = Vector2(0, 120)
	g.scale_amount_min = 0.08
	g.scale_amount_max = 0.18
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	g.material = mat
	g.color_ramp = _ramp(Color(1, 1, 1, 0.55), Color(0.7, 0.9, 1.0, 0.0))
	g.z_index = 5


func sparks(parent: Node, pos: Vector2, strength: float) -> void:
	if parent == null:
		return
	var s := _burst(parent, pos, roundi(10 + strength * 16.0), 0.45)
	s.texture = splinter_texture()
	s.particle_flag_align_y = true
	s.direction = Vector2.UP
	s.spread = 110.0
	s.initial_velocity_min = 200.0
	s.initial_velocity_max = 650.0 * strength + 200.0
	s.gravity = Vector2(0, 1400)
	s.scale_amount_min = 0.5
	s.scale_amount_max = 1.0
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	s.material = mat
	s.color_ramp = _ramp(Color(1.0, 0.95, 0.6), Color(1.0, 0.45, 0.1, 0.0))
	s.z_index = -2


## Cartoon "poof" for eliminated royals.
func poof(parent: Node, pos: Vector2) -> void:
	dust(parent, pos, 1.0, Color(1, 1, 1))
	var stars := _burst(parent, pos, 10, 0.8)
	stars.texture = shard_texture()
	stars.direction = Vector2.UP
	stars.spread = 180.0
	stars.initial_velocity_min = 150.0
	stars.initial_velocity_max = 320.0
	stars.gravity = Vector2(0, 300)
	stars.angular_velocity_min = -360.0
	stars.angular_velocity_max = 360.0
	stars.scale_amount_min = 1.0
	stars.scale_amount_max = 1.6
	stars.color = Color(1.0, 0.85, 0.3)
	stars.z_index = 6


## A puff where the projectile hits the ground.
func ground_puff(parent: Node, pos: Vector2, speed_mps: float) -> void:
	dust(parent, pos, clampf(speed_mps / 18.0, 0.4, 1.3), Color(0.82, 0.74, 0.6))


## Flames attached to a burning block; returns the node so it can be removed.
## `extents` = half-size of the burning block in px (flames cover it).
func flames(host: Node2D, size: float, extents: Vector2 = Vector2(30, 30)) -> Node2D:
	var root := Node2D.new()
	root.z_index = 5
	host.add_child(root)
	# Body: opaque tongues of flame (readable against a bright sky).
	var f := CPUParticles2D.new()
	var area_m2: float = extents.x * extents.y * 4.0 / 10000.0
	f.amount = maxi(10, roundi((14.0 + area_m2 * 18.0) * particle_scale))
	f.lifetime = 0.75
	f.local_coords = false
	f.texture = flame_tongue()
	f.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	f.emission_rect_extents = extents * 0.8
	f.direction = Vector2.UP
	f.spread = 10.0
	f.gravity = Vector2(0, -360)
	f.initial_velocity_min = 30.0
	f.initial_velocity_max = 90.0
	# Sideways sway, so tongues lick rather than rise in lines.
	f.tangential_accel_min = -60.0
	f.tangential_accel_max = 60.0
	# The tongue texture is 0.48 x 0.96 m: flames of roughly 1-2 m that
	# overlap into one blaze.
	f.scale_amount_min = 1.1
	f.scale_amount_max = 2.1
	var sc := Curve.new()
	sc.add_point(Vector2(0, 1.0))
	sc.add_point(Vector2(1, 0.2))
	f.scale_amount_curve = sc
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1.0, 0.9, 0.45, 0.95))
	ramp.add_point(0.25, Color(1.0, 0.6, 0.15, 0.95))
	ramp.add_point(0.6, Color(0.92, 0.25, 0.06, 0.75))
	ramp.set_color(1, Color(0.45, 0.08, 0.04, 0.0))
	f.color_ramp = ramp
	root.add_child(f)
	# Core: a small additive glow.
	var core := CPUParticles2D.new()
	core.amount = maxi(3, roundi(8 * size * particle_scale))
	core.lifetime = 0.45
	core.local_coords = false
	core.texture = flame_tongue()
	core.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	core.emission_rect_extents = extents * 0.6
	core.direction = Vector2.UP
	core.gravity = Vector2(0, -260)
	core.scale_amount_min = 0.8
	core.scale_amount_max = 1.3
	var add := CanvasItemMaterial.new()
	add.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	core.material = add
	core.color_ramp = _ramp(Color(1.0, 0.95, 0.6, 0.8), Color(1.0, 0.5, 0.1, 0.0))
	root.add_child(core)
	var smoke := CPUParticles2D.new()
	smoke.amount = maxi(3, roundi(6 * size * particle_scale))
	smoke.lifetime = 2.2
	smoke.local_coords = false
	smoke.texture = soft_circle()
	smoke.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
	smoke.emission_sphere_radius = 30.0 * size
	smoke.position = Vector2(0, -20)
	smoke.gravity = Vector2(10, -90)
	smoke.scale_amount_min = 0.8 * size
	smoke.scale_amount_max = 1.8 * size
	smoke.color_ramp = _ramp(Color(0.24, 0.21, 0.2, 0.45), Color(0.45, 0.43, 0.41, 0.0))
	root.add_child(smoke)
	# Embers: tiny bright sparks drifting up out of the fire.
	var embers := CPUParticles2D.new()
	embers.amount = maxi(4, roundi(10 * size * particle_scale))
	embers.lifetime = 1.6
	embers.local_coords = false
	embers.texture = soft_circle()
	embers.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	embers.emission_rect_extents = extents * 0.7
	embers.direction = Vector2.UP
	embers.spread = 35.0
	embers.gravity = Vector2(0, -70)
	embers.initial_velocity_min = 40.0
	embers.initial_velocity_max = 130.0
	embers.tangential_accel_min = -40.0
	embers.tangential_accel_max = 40.0
	embers.scale_amount_min = 0.05
	embers.scale_amount_max = 0.1
	embers.material = add
	embers.color_ramp = _ramp(Color(1.0, 0.75, 0.3, 1.0), Color(1.0, 0.3, 0.05, 0.0))
	root.add_child(embers)
	# Warm, flickering light on the surroundings, for the first few fires.
	var max_lights: int = 8 if particle_scale >= 1.0 else 3
	if _fire_lights < max_lights:
		_fire_lights += 1
		var light := PointLight2D.new()
		light.texture = soft_circle()
		light.texture_scale = 4.0 * maxf(size, 0.6)
		light.color = Color(1.0, 0.58, 0.22)
		light.energy = 0.8
		root.add_child(light)
		light.tree_exiting.connect(func() -> void: _fire_lights = maxi(0, _fire_lights - 1))
		var tw := light.create_tween().set_loops()
		tw.tween_property(light, "energy", 0.5, 0.12)
		tw.tween_property(light, "energy", 1.0, 0.09)
		tw.tween_property(light, "energy", 0.75, 0.15)
	return root


## Powder keg: flash, fireball, smoke and flying grit.
func explosion(parent: Node, pos: Vector2, radius_px: float) -> void:
	if parent == null:
		return
	var flash := Sprite2D.new()
	flash.texture = soft_circle()
	flash.position = pos
	flash.z_index = 9
	var add := CanvasItemMaterial.new()
	add.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	flash.material = add
	flash.scale = Vector2.ONE * radius_px / 32.0 * 0.6
	flash.modulate = Color(1.0, 0.85, 0.5, 0.0 if Settings.reduce_flashing else 0.9)
	parent.add_child(flash)
	var tw := flash.create_tween()
	tw.tween_property(flash, "modulate:a", 0.0, 0.35)
	tw.parallel().tween_property(flash, "scale", flash.scale * 1.6, 0.35)
	tw.tween_callback(flash.queue_free)
	var fire := _burst(parent, pos, 26, 0.6)
	fire.texture = soft_circle()
	fire.z_index = 8
	fire.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
	fire.emission_sphere_radius = radius_px * 0.2
	fire.direction = Vector2.UP
	fire.spread = 180.0
	fire.initial_velocity_min = 200.0
	fire.initial_velocity_max = 520.0
	fire.damping_min = 300.0
	fire.damping_max = 500.0
	fire.scale_amount_min = 1.2
	fire.scale_amount_max = 2.6
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1.0, 0.95, 0.6, 1.0))
	ramp.add_point(0.3, Color(1.0, 0.5, 0.15, 0.9))
	ramp.set_color(1, Color(0.3, 0.25, 0.22, 0.0))
	fire.color_ramp = ramp
	dust(parent, pos, radius_px / 160.0, Color(0.35, 0.32, 0.3))
	_flying(
		parent, pos, 24, shard_texture(), [Color(0.4, 0.3, 0.2), Color(0.2, 0.15, 0.1)], 1.0, false
	)


## Firepot: a splash of flame.
func fire_burst(parent: Node, pos: Vector2, radius_px: float) -> void:
	if parent == null:
		return
	var f := _burst(parent, pos, 22, 0.9)
	f.texture = soft_circle()
	f.z_index = 8
	f.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
	f.emission_sphere_radius = radius_px * 0.25
	f.direction = Vector2.UP
	f.spread = 75.0
	f.initial_velocity_min = 120.0
	f.initial_velocity_max = 360.0
	f.gravity = Vector2(0, -150)
	f.scale_amount_min = 0.8
	f.scale_amount_max = 1.8
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1.0, 0.9, 0.45, 0.95))
	ramp.add_point(0.5, Color(1.0, 0.4, 0.1, 0.8))
	ramp.set_color(1, Color(0.5, 0.1, 0.05, 0.0))
	f.color_ramp = ramp
	_flying(
		parent,
		pos,
		12,
		shard_texture(),
		[Color(0.72, 0.37, 0.2), Color(0.48, 0.23, 0.12)],
		0.9,
		false
	)


## Frost flask: icy mist and sparkle.
func frost_burst(parent: Node, pos: Vector2, radius_px: float) -> void:
	if parent == null:
		return
	dust(parent, pos, radius_px / 120.0, Color(0.82, 0.95, 1.0))
	glitter(parent, pos, radius_px / 100.0)
	_flying(
		parent,
		pos,
		18,
		shard_texture(),
		[Color(0.85, 0.97, 1.0), Color(0.5, 0.8, 0.95)],
		0.8,
		false
	)
