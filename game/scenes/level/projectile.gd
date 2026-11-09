# SPDX-FileCopyrightText: 2026 Siegefall contributors
# SPDX-License-Identifier: MIT
class_name Projectile
extends RigidBody2D
## A fired piece of ammo (game/data/ammo.json). Ballistic, no default air
## drag, so a release phase always produces the same arc.
##
## Special ammo acts on first impact or on a mid-air tap: scatter-stones
## burst, powder kegs explode, firepots ignite, frost flasks freeze, chain
## shot snaps apart, void flasks open a small black hole. Every effect runs
## inside the physics step (taps are queued to the next tick) so replays and
## the validator bot are exact.

signal impacted(projectile: Projectile, speed_mps: float)
signal settled(projectile: Projectile)
## Scatter-stones and chain shot replace themselves with smaller projectiles.
signal split(parent: Projectile, children: Array[Projectile])

const VOID_SHADER: Shader = preload("res://shaders/void.gdshader")

var ammo: Dictionary = {}
var kind: String = "circle"
var pre_velocity: Vector2 = Vector2.ZERO
var has_impacted: bool = false
var is_done: bool = false
var tap_used: bool = false
var world_rect_px: Rect2 = Rect2(-4000, -6000, 14000, 8000)
## Physics ticks since launch (used to record taps for exact replays).
var ticks: int = 0

var _age: float = 0.0
var _since_impact: float = 0.0
var _still: float = 0.0
var _impact_pending: bool = false
var _tap_requested: bool = false
var _effect_done: bool = false
var _fuse: float = -1.0
var _void_t: float = -1.0
var _void_fx: Node2D = null
var _fx: Dictionary = {}


func setup(ammo_def: Dictionary, pos_px: Vector2, vel_px: Vector2) -> void:
	ammo = ammo_def
	kind = str(ammo.get("shape", "circle"))
	var fx: Variant = ammo.get("effect", {})
	_fx = fx if fx is Dictionary else {}
	var r: float = float(ammo.get("radius", 0.4))
	position = pos_px
	linear_velocity = vel_px
	pre_velocity = vel_px
	linear_damp_mode = RigidBody2D.DAMP_MODE_REPLACE
	linear_damp = float(ammo.get("linear_damp", 0.0))
	angular_damp_mode = RigidBody2D.DAMP_MODE_REPLACE
	angular_damp = 0.4 if kind != "chain" else 0.0
	continuous_cd = RigidBody2D.CCD_MODE_CAST_SHAPE
	contact_monitor = true
	max_contacts_reported = 4
	collision_layer = Block.Layer.PROJECTILES
	collision_mask = Block.Layer.WORLD | Block.Layer.BLOCKS | Block.Layer.ENEMIES
	var pm := PhysicsMaterial.new()
	pm.friction = 0.7
	pm.bounce = 0.12
	physics_material_override = pm
	var density: float = float(ammo.get("density", 2400.0))
	if kind == "chain":
		var half: float = float(_fx.get("length", 1.3)) * 0.5 * Units.PX_PER_M
		for sx: float in [-1.0, 1.0]:
			var cs := CollisionShape2D.new()
			var c := CircleShape2D.new()
			c.radius = r * Units.PX_PER_M
			cs.shape = c
			cs.position = Vector2(sx * half, 0.0)
			add_child(cs)
		mass = 2.0 * PI * r * r * density
		angular_velocity = float(_fx.get("spin", 12.0))
	else:
		var cs := CollisionShape2D.new()
		cs.shape = ShapeGeometry.collision_shape_for({"shape": "circle", "radius": r})
		add_child(cs)
		mass = PI * r * r * density
		angular_velocity = -6.0
	add_child(make_visual(ammo))


# --------------------------------------------------------------- visuals ---
static func _look_material(ammo_def: Dictionary, bevel: float) -> ShaderMaterial:
	var look: Dictionary = ammo_def.get("look", {})
	var patterns: Dictionary = {"wood": 0, "stone": 1, "glass": 2, "ice": 3, "iron": 4, "rock": 7}
	var sm := ShaderMaterial.new()
	sm.shader = Block.SHADER
	sm.set_shader_parameter("pattern", int(patterns.get(str(look.get("pattern", "rock")), 7)))
	sm.set_shader_parameter("col_base", Units.color(look.get("base"), Color.GRAY))
	sm.set_shader_parameter("col_dark", Units.color(look.get("dark"), Color.DIM_GRAY))
	sm.set_shader_parameter("col_light", Units.color(look.get("light"), Color.LIGHT_GRAY))
	sm.set_shader_parameter("bevel_m", bevel)
	sm.set_shader_parameter("seed", 3.0)
	return sm


static func _disc(r_m: float, sm: ShaderMaterial, pos: Vector2 = Vector2.ZERO) -> MeshInstance2D:
	var mi := MeshInstance2D.new()
	mi.mesh = ShapeGeometry.bevel_mesh_for({"shape": "circle", "radius": r_m}, Vector2(3.1, 7.7))
	mi.material = sm
	mi.position = pos
	return mi


## The projectile's look; also used for the ammo sitting in the sling.
static func make_visual(ammo_def: Dictionary) -> Node2D:
	var r: float = float(ammo_def.get("radius", 0.4))
	var root := Node2D.new()
	var shape: String = str(ammo_def.get("shape", "circle"))
	var ink: Color = UiTheme.INK
	match shape:
		"cluster":
			var sm := _look_material(ammo_def, 0.15)
			var cr: float = float(
				(ammo_def.get("effect", {}) as Dictionary).get("child_radius", 0.2)
			)
			for k: int in 5:
				var a: float = TAU * k / 5.0 + 0.3
				root.add_child(_disc(cr, sm, Vector2.from_angle(a) * cr * 100.0 * 1.05))
			var band := Line2D.new()
			band.width = 6.0
			band.default_color = Color(0.55, 0.4, 0.25)
			band.points = PackedVector2Array([Vector2(-r * 90, -6), Vector2(r * 90, 6)])
			root.add_child(band)
		"keg":
			var sm := _look_material(ammo_def, 0.08)
			var mi := MeshInstance2D.new()
			mi.mesh = ShapeGeometry.bevel_mesh_for(
				{"shape": "rect", "size": Vector2(r * 1.7, r * 2.0)}
			)
			mi.material = sm
			root.add_child(mi)
			for y: float in [-0.55, 0.55]:
				var hoop := Line2D.new()
				hoop.width = 7.0
				hoop.default_color = Color(0.25, 0.25, 0.28)
				hoop.points = PackedVector2Array(
					[Vector2(-r * 88, y * r * 100), Vector2(r * 88, y * r * 100)]
				)
				root.add_child(hoop)
			var fuse := Line2D.new()
			fuse.width = 4.0
			fuse.default_color = ink
			fuse.points = PackedVector2Array([Vector2(0, -r * 100), Vector2(8, -r * 100 - 16)])
			root.add_child(fuse)
		"flask":
			var sm := _look_material(ammo_def, r * 0.8)
			var neck := MeshInstance2D.new()
			neck.mesh = ShapeGeometry.bevel_mesh_for(
				{"shape": "rect", "size": Vector2(r * 0.7, r * 0.9)}
			)
			neck.material = sm
			neck.position = Vector2(0, -r * 100 * 1.15)
			root.add_child(neck)
			root.add_child(_disc(r, sm))
			var look: Dictionary = ammo_def.get("look", {})
			if look.has("glow"):
				var glow := Sprite2D.new()
				glow.texture = Effects.soft_circle()
				glow.modulate = Color(Units.color(look.get("glow")), 0.55)
				glow.scale = Vector2.ONE * r * 3.2
				var add := CanvasItemMaterial.new()
				add.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
				glow.material = add
				root.add_child(glow)
			var cork := Polygon2D.new()
			var cw: float = r * 30.0
			cork.polygon = PackedVector2Array(
				[
					Vector2(-cw, -r * 160),
					Vector2(cw, -r * 160),
					Vector2(cw * 0.8, -r * 190),
					Vector2(-cw * 0.8, -r * 190)
				]
			)
			cork.color = Color(0.62, 0.45, 0.3)
			root.add_child(cork)
		"chain":
			var sm := _look_material(ammo_def, r * 0.9)
			var half: float = (
				float((ammo_def.get("effect", {}) as Dictionary).get("length", 1.3)) * 50.0
			)
			var links := Line2D.new()
			links.width = 8.0
			links.default_color = Color(0.3, 0.31, 0.35)
			links.points = PackedVector2Array([Vector2(-half, 0), Vector2(0, 6), Vector2(half, 0)])
			root.add_child(links)
			root.add_child(_disc(r, sm, Vector2(-half, 0)))
			root.add_child(_disc(r, sm, Vector2(half, 0)))
		_:
			root.add_child(_disc(r, _look_material(ammo_def, r * 0.9)))
	return root


# ---------------------------------------------------------------- gameplay ---
func damage_multiplier(material_id: String) -> float:
	var dv: Variant = ammo.get("damage_vs", {})
	if dv is Dictionary:
		return float((dv as Dictionary).get(material_id, 1.0))
	return 1.0


## Called by a block this projectile touches.
func on_hit_block(block: Block, _point: Vector2) -> void:
	if _fx.has("ignite_radius"):
		block.ignite.call_deferred()


func can_tap() -> bool:
	return not tap_used and not is_done and str(ammo.get("tap_action", "none")) != "none"


## Mid-air action. Applied on the next physics tick (deterministic).
func tap() -> bool:
	if not can_tap():
		return false
	tap_used = true
	_tap_requested = true
	return true


func _integrate_forces(state: PhysicsDirectBodyState2D) -> void:
	if not has_impacted and state.get_contact_count() > 0:
		has_impacted = true
		_impact_pending = true
		impacted.emit.call_deferred(self, pre_velocity.length() / Units.PX_PER_M)


func _physics_process(delta: float) -> void:
	ticks += 1
	if _tap_requested:
		_tap_requested = false
		_do_tap()
	if _impact_pending:
		_impact_pending = false
		_on_first_impact()
	if _fuse >= 0.0:
		_fuse -= delta
		if _fuse < 0.0:
			_explode()
	if _void_t >= 0.0:
		_void_step(delta)
		return
	pre_velocity = linear_velocity
	if is_done:
		return
	_age += delta
	if has_impacted:
		_since_impact += delta
	if linear_velocity.length() < 25.0:
		_still += delta
	else:
		_still = 0.0
	var out: bool = not world_rect_px.has_point(global_position)
	if out or _still > 0.4 or _since_impact > 3.0 or _age > 12.0:
		_finish(out)


func _finish(free_now: bool) -> void:
	if is_done:
		return
	is_done = true
	settled.emit(self)
	if free_now:
		queue_free()


func _do_tap() -> void:
	match str(ammo.get("tap_action", "none")):
		"burst":
			_burst()
		"detonate":
			_explode()
		"snap":
			_snap()
		"open":
			_open_void()


func _on_first_impact() -> void:
	if _effect_done:
		return
	match kind:
		"cluster":
			_burst()
		"keg":
			_fuse = float(_fx.get("fuse", 0.25))
		"flask":
			if _fx.has("ignite_radius"):
				_ignite_area()
			elif _fx.has("freeze_radius"):
				_freeze_area()
			elif _fx.has("pull"):
				_open_void()


# ---------------------------------------------------------------- effects ---
func _child_ammo(radius: float, density: float) -> Dictionary:
	return {
		"id": str(ammo.get("id", "")) + "_part",
		"shape": "circle",
		"radius": radius,
		"density": density,
		"material": ammo.get("material", "stone"),
		"tap_action": "none",
		"damage_vs": ammo.get("damage_vs", {}),
		"look": ammo.get("look", {}),
	}


func _spawn_children(defs: Array[Dictionary]) -> void:
	var kids: Array[Projectile] = []
	for d: Dictionary in defs:
		var p := Projectile.new()
		get_parent().add_child(p)
		p.setup(d["ammo"], d["pos"], d["vel"])
		p.world_rect_px = world_rect_px
		kids.append(p)
	_effect_done = true
	split.emit(self, kids)
	_finish(true)


func _burst() -> void:
	if _effect_done:
		return
	var count: int = int(_fx.get("count", 5))
	var spread: float = deg_to_rad(float(_fx.get("spread_deg", 7.0)))
	var child: Dictionary = _child_ammo(
		float(_fx.get("child_radius", 0.2)), float(_fx.get("child_density", 2400))
	)
	var v: Vector2 = pre_velocity
	var side: Vector2 = v.orthogonal().normalized() * float(child["radius"]) * 100.0 * 1.2
	var defs: Array[Dictionary] = []
	for k: int in count:
		var t: float = k - (count - 1) * 0.5
		defs.append(
			{
				"ammo": child,
				"pos": global_position + side * t,
				"vel": v.rotated(spread * t) * (1.0 - absf(t) * 0.02)
			}
		)
	Effects.dust(get_parent(), global_position, 0.5, Color(0.85, 0.8, 0.7))
	Sfx.play_at("burst", global_position, -4.0)
	_spawn_children(defs)


func _snap() -> void:
	if _effect_done:
		return
	var half: float = float(_fx.get("length", 1.3)) * 0.5 * Units.PX_PER_M
	var child: Dictionary = _child_ammo(
		float(ammo.get("radius", 0.22)), float(ammo.get("density", 7800))
	)
	var defs: Array[Dictionary] = []
	for sx: float in [-1.0, 1.0]:
		var arm: Vector2 = Vector2(sx * half, 0.0).rotated(rotation)
		var tangential: Vector2 = Vector2(-arm.y, arm.x) * angular_velocity
		defs.append(
			{"ammo": child, "pos": global_position + arm, "vel": linear_velocity + tangential}
		)
	Effects.sparks(get_parent(), global_position, 0.6)
	Sfx.play_at("iron_crack", global_position, -4.0)
	_spawn_children(defs)


## Bodies (blocks and enemies) within `radius_px` of `center`.
func _bodies_near(center: Vector2, radius_px: float) -> Array[RigidBody2D]:
	var out: Array[RigidBody2D] = []
	for group: String in ["blocks", "enemies"]:
		for n: Node in get_tree().get_nodes_in_group(group):
			var b := n as RigidBody2D
			if b == null or b == self:
				continue
			if b is Block and (b as Block).is_broken:
				continue
			if b is Enemy and (b as Enemy).is_dead:
				continue
			if b.global_position.distance_to(center) <= radius_px:
				out.append(b)
	return out


func _explode() -> void:
	if _effect_done:
		return
	_effect_done = true
	_fuse = -1.0
	var center: Vector2 = global_position
	var radius: float = float(_fx.get("radius", 3.5)) * Units.PX_PER_M
	var impulse: float = float(_fx.get("impulse", 5000.0)) * Units.PX_PER_M
	var damage: float = float(_fx.get("damage", 120.0))
	for b: RigidBody2D in _bodies_near(center, radius):
		var off: Vector2 = b.global_position - center
		var f: float = 1.0 - off.length() / radius
		var dir: Vector2 = off.normalized() if off.length() > 1.0 else Vector2.UP
		b.sleeping = false
		b.apply_central_impulse(dir * impulse * f)
		if b is Block:
			var blk: Block = b
			blk.apply_damage(
				damage * f * f * float(blk.mat.get("damage_scale", 1.0)),
				impulse * f / 100.0,
				center
			)
		elif b is Enemy:
			(b as Enemy).take_damage(
				damage * f * f * 0.6 * float((b as Enemy).def.get("damage_taken", 1.0))
			)
	Effects.explosion(get_parent(), center, radius)
	Effects.shake(0.95)
	Effects.haptic(1.0)
	Effects.slow_motion(0.3, 0.35)
	Sfx.play_at("boom", center, 2.0)
	Sfx.play_at("rumble", center, -3.0)
	_finish(true)


func _ignite_area() -> void:
	_effect_done = true
	var center: Vector2 = global_position
	var radius: float = float(_fx.get("ignite_radius", 2.0)) * Units.PX_PER_M
	for b: RigidBody2D in _bodies_near(center, radius):
		if b is Block:
			(b as Block).ignite()
		elif b is Enemy:
			(b as Enemy).take_damage(float(_fx.get("damage", 25.0)) * 0.3)
	Effects.fire_burst(get_parent(), center, radius)
	Sfx.play_at("flask_shatter", center, -2.0)
	Sfx.play_at("fire_start", center, -2.0)
	_finish(true)


func _freeze_area() -> void:
	_effect_done = true
	var center: Vector2 = global_position
	var radius: float = float(_fx.get("freeze_radius", 2.5)) * Units.PX_PER_M
	for b: RigidBody2D in _bodies_near(center, radius):
		if b is Block:
			(b as Block).freeze_solid()
		elif b is Enemy:
			(b as Enemy).freeze_solid()
	Effects.frost_burst(get_parent(), center, radius)
	Sfx.play_at("flask_shatter", center, -2.0)
	Sfx.play_at("frost_burst", center, -2.0)
	_finish(true)


func _open_void() -> void:
	if _effect_done:
		return
	_effect_done = true
	_void_t = float(_fx.get("duration", 1.6))
	freeze_mode = RigidBody2D.FREEZE_MODE_KINEMATIC
	set_deferred("freeze", true)
	collision_layer = 0
	collision_mask = 0
	for c: Node in get_children():
		if c is Node2D and not c is CollisionShape2D:
			(c as Node2D).visible = false
	_void_fx = Node2D.new()
	var disc := Sprite2D.new()
	disc.texture = Effects.soft_circle()
	var sm := ShaderMaterial.new()
	sm.shader = VOID_SHADER
	disc.material = sm
	disc.scale = Vector2.ONE * float(_fx.get("core", 1.0)) * 3.2
	_void_fx.add_child(disc)
	_void_fx.z_index = 8
	_void_fx.global_position = global_position
	get_parent().add_child(_void_fx)
	Sfx.play_at("void_hum", global_position, -2.0)
	Effects.shake(0.3)


func _void_step(delta: float) -> void:
	_void_t -= delta
	var center: Vector2 = global_position
	var radius: float = float(_fx.get("radius", 4.0)) * Units.PX_PER_M
	var core: float = float(_fx.get("core", 1.0)) * Units.PX_PER_M
	var pull: float = float(_fx.get("pull", 30.0)) * Units.PX_PER_M
	for b: RigidBody2D in _bodies_near(center, radius):
		var off: Vector2 = center - b.global_position
		var d: float = off.length()
		var f: float = 1.0 - d / radius
		b.sleeping = false
		# Acceleration-based pull (mass-independent, like gravity).
		b.apply_central_impulse(off.normalized() * pull * f * b.mass * delta)
		if d < core:
			if b is Block:
				var blk: Block = b
				if blk.generation > 0 and blk.area_m2 < 0.15:
					blk.break_apart()
				else:
					blk.apply_damage(float(_fx.get("core_damage", 90.0)) * delta, 0.0, center)
			elif b is Enemy:
				(b as Enemy).take_damage(float(_fx.get("core_damage", 90.0)) * delta * 0.5)
	if is_instance_valid(_void_fx):
		_void_fx.rotation += delta * 6.0
	if _void_t < 0.0:
		_void_t = -1.0
		if is_instance_valid(_void_fx):
			_void_fx.queue_free()
		Effects.poof(get_parent(), center)
		Sfx.play_at("void_pop", center, 0.0)
		Effects.shake(0.4)
		_finish(true)
