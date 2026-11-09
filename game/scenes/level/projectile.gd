# SPDX-FileCopyrightText: 2026 Siegefall contributors
# SPDX-License-Identifier: MIT
class_name Projectile
extends RigidBody2D
## A fired piece of ammo. Ballistic (no default air drag) so a release phase
## always produces the same arc; ammo data may add its own drag.

signal impacted(projectile: Projectile, speed_mps: float)
signal settled(projectile: Projectile)

var ammo: Dictionary = {}
var pre_velocity: Vector2 = Vector2.ZERO
var has_impacted: bool = false
var is_done: bool = false
var world_rect_px: Rect2 = Rect2(-4000, -6000, 14000, 8000)

var _age: float = 0.0
var _since_impact: float = 0.0
var _still: float = 0.0
var _impact_speed: float = 0.0


func setup(ammo_def: Dictionary, pos_px: Vector2, vel_px: Vector2) -> void:
	ammo = ammo_def
	var r: float = float(ammo.get("radius", 0.4))
	position = pos_px
	linear_velocity = vel_px
	pre_velocity = vel_px
	mass = PI * r * r * float(ammo.get("density", 2400.0))
	linear_damp_mode = RigidBody2D.DAMP_MODE_REPLACE
	linear_damp = float(ammo.get("linear_damp", 0.0))
	angular_damp_mode = RigidBody2D.DAMP_MODE_REPLACE
	angular_damp = 0.4
	continuous_cd = RigidBody2D.CCD_MODE_CAST_SHAPE
	contact_monitor = true
	max_contacts_reported = 4
	collision_layer = Block.Layer.PROJECTILES
	collision_mask = (
		Block.Layer.WORLD | Block.Layer.BLOCKS | Block.Layer.ENEMIES | Block.Layer.PROJECTILES
	)
	var pm := PhysicsMaterial.new()
	pm.friction = 0.7
	pm.bounce = 0.12
	physics_material_override = pm
	angular_velocity = -6.0

	var spec: Dictionary = {"shape": "circle", "radius": r}
	var cs := CollisionShape2D.new()
	cs.shape = ShapeGeometry.collision_shape_for(spec)
	add_child(cs)
	add_child(make_visual(ammo))


## The projectile's look; also used for the ammo sitting in the sling.
static func make_visual(ammo_def: Dictionary) -> Node2D:
	var r: float = float(ammo_def.get("radius", 0.4))
	var mi := MeshInstance2D.new()
	mi.mesh = ShapeGeometry.bevel_mesh_for({"shape": "circle", "radius": r}, Vector2(3.1, 7.7))
	var mat_id: String = str(ammo_def.get("material", "stone"))
	var sm: ShaderMaterial = (
		Block.shader_material_for("ammo:" + mat_id, Data.material(mat_id)).duplicate()
	)
	sm.set_shader_parameter("pattern", 7)
	sm.set_shader_parameter("bevel_m", r * 0.9)
	mi.material = sm
	return mi


func damage_multiplier(material_id: String) -> float:
	var dv: Variant = ammo.get("damage_vs", {})
	if dv is Dictionary:
		return float((dv as Dictionary).get(material_id, 1.0))
	return 1.0


func _integrate_forces(state: PhysicsDirectBodyState2D) -> void:
	if not has_impacted and state.get_contact_count() > 0:
		has_impacted = true
		_impact_speed = pre_velocity.length() / Units.PX_PER_M
		impacted.emit.call_deferred(self, _impact_speed)


func _physics_process(delta: float) -> void:
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
		is_done = true
		settled.emit(self)
		if out:
			queue_free()
