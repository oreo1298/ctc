# SPDX-FileCopyrightText: 2026 Siegefall contributors
# SPDX-License-Identifier: MIT
class_name Block
extends RigidBody2D
## A breakable castle block built from a normalised level spec and a
## material definition (game/data/materials.json).
##
## Damage model (docs/DESIGN.md §8.5): every contact reports its impulse, but
## only contacts where the two bodies were approaching faster than the
## material's `impact_speed` count, so resting weight never cracks anything.

signal broken(block: Block, points: int)
signal hit(block: Block, impulse_ns: float)

enum Layer { WORLD = 1, BLOCKS = 2, ENEMIES = 4, PROJECTILES = 8, PROPS = 16 }

const PATTERNS: Array[String] = ["wood", "stone", "glass", "ice", "iron", "thatch", "cloth"]
const SHADER: Shader = preload("res://shaders/block.gdshader")

static var _shared: Dictionary = {}

var spec: Dictionary = {}
var material_id: String = ""
var mat: Dictionary = {}
var area_m2: float = 1.0
var max_hp: float = 1.0
var hp: float = 1.0
var is_broken: bool = false
## Velocity at the start of the current physics step (read by neighbours).
var pre_velocity: Vector2 = Vector2.ZERO

var _pending_damage: float = 0.0
var _pending_impulse: float = 0.0
var _visual: MeshInstance2D
var _own_material: ShaderMaterial = null
var _seed: float = 0.0
var _flash: float = 0.0


## Shared ShaderMaterial for a material id (blocks share until damaged).
static func shader_material_for(id: String, def: Dictionary) -> ShaderMaterial:
	if _shared.has(id):
		return _shared[id]
	var m := ShaderMaterial.new()
	m.shader = SHADER
	var colors: Dictionary = def.get("colors", {})
	m.set_shader_parameter("pattern", maxi(0, PATTERNS.find(str(def.get("pattern", "wood")))))
	m.set_shader_parameter("col_base", Units.color(colors.get("base")))
	m.set_shader_parameter("col_dark", Units.color(colors.get("dark")))
	m.set_shader_parameter("col_light", Units.color(colors.get("light")))
	m.set_shader_parameter("glyphs", 1.0 if Settings.material_glyphs else 0.0)
	_shared[id] = m
	return m


static func clear_shared() -> void:
	_shared.clear()


func setup(block_spec: Dictionary, material_def: Dictionary, index: int) -> void:
	spec = block_spec
	material_id = str(block_spec.get("material", "wood"))
	mat = material_def
	area_m2 = ShapeGeometry.area_m2(spec)
	max_hp = float(mat.get("hp_per_m2", 100.0)) * area_m2
	hp = max_hp
	_seed = float(index) * 1.618 + float(material_id.hash() % 97)
	position = Units.to_px(spec.get("pos", Vector2.ZERO))
	rotation = Units.rot_to_godot(float(spec.get("rot", 0.0)))
	mass = maxf(0.5, area_m2 * float(mat.get("density", 600.0)))
	var pm := PhysicsMaterial.new()
	pm.friction = float(mat.get("friction", 0.6))
	pm.bounce = float(mat.get("bounce", 0.05))
	physics_material_override = pm
	collision_layer = Layer.BLOCKS
	collision_mask = Layer.WORLD | Layer.BLOCKS | Layer.ENEMIES | Layer.PROJECTILES | Layer.PROPS
	contact_monitor = true
	max_contacts_reported = 6
	can_sleep = true
	if bool(spec.get("static", false)):
		freeze = true
		freeze_mode = RigidBody2D.FREEZE_MODE_STATIC

	var cs := CollisionShape2D.new()
	cs.shape = ShapeGeometry.collision_shape_for(spec)
	add_child(cs)

	_visual = MeshInstance2D.new()
	_visual.mesh = ShapeGeometry.bevel_mesh_for(spec, Vector2(_seed * 3.7, _seed * 1.3))
	_visual.material = shader_material_for(material_id, mat)
	add_child(_visual)

	var occ := LightOccluder2D.new()
	var op := OccluderPolygon2D.new()
	op.polygon = ShapeGeometry.polygon_for(spec)
	op.cull_mode = OccluderPolygon2D.CULL_DISABLED
	occ.occluder = op
	add_child(occ)


func _physics_process(_delta: float) -> void:
	if _pending_damage > 0.0:
		var dmg: float = _pending_damage
		var imp: float = _pending_impulse
		_pending_damage = 0.0
		_pending_impulse = 0.0
		apply_damage(dmg, imp)
	pre_velocity = linear_velocity
	if _flash > 0.0 and _own_material != null:
		_flash = maxf(0.0, _flash - 0.12)
		_own_material.set_shader_parameter("flash", _flash)


func _integrate_forces(state: PhysicsDirectBodyState2D) -> void:
	if is_broken:
		return
	var threshold: float = float(mat.get("impact_speed", 1.5)) * Units.PX_PER_M
	for i: int in state.get_contact_count():
		var imp: float = state.get_contact_impulse(i).length()
		if imp <= 0.0:
			continue
		var other: Object = state.get_contact_collider_object(i)
		var other_v: Vector2 = Vector2.ZERO
		var mult: float = 1.0
		if other is Block:
			other_v = (other as Block).pre_velocity
		elif other is Projectile:
			var pr: Projectile = other
			other_v = pr.pre_velocity
			mult = pr.damage_multiplier(material_id)
		elif other is Enemy:
			other_v = (other as Enemy).pre_velocity
		var n: Vector2 = state.get_contact_local_normal(i)
		var approach: float = absf((other_v - pre_velocity).dot(n))
		if approach < threshold:
			continue
		var impulse_ns: float = imp / Units.PX_PER_M
		_pending_impulse = maxf(_pending_impulse, impulse_ns)
		_pending_damage += impulse_ns / 100.0 * float(mat.get("damage_scale", 1.0)) * mult


func apply_damage(amount: float, impulse_ns: float = 0.0) -> void:
	if is_broken or freeze:
		return
	hp -= amount
	if impulse_ns >= 50.0:
		hit.emit(self, impulse_ns)
	if hp <= 0.0:
		break_apart()
		return
	_ensure_own_material()
	_own_material.set_shader_parameter("damage", clampf(1.0 - hp / max_hp, 0.0, 1.0))
	_flash = 0.5


func _ensure_own_material() -> void:
	if _own_material != null:
		return
	_own_material = (_visual.material as ShaderMaterial).duplicate() as ShaderMaterial
	_own_material.set_shader_parameter("seed", _seed)
	_visual.material = _own_material


## Milestone 1: blocks vanish in a puff of material-coloured debris.
## Milestone 2 replaces this with real fracture into physical pieces.
func break_apart() -> void:
	if is_broken:
		return
	is_broken = true
	var pts: int = Scoring.block_points(int(mat.get("points", 50)), area_m2)
	broken.emit(self, pts)
	Effects.debris_burst(get_parent(), global_position, material_id, mat, area_m2)
	queue_free()
