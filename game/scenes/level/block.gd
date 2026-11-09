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
## At 0 HP the block fractures (runtime Voronoi, style per material) into
## physical pieces that continue its motion and its surface pattern.

signal broken(block: Block, points: int)
signal hit(block: Block, impulse_ns: float)
## Emitted instead of spawning directly so the level can enforce a body
## budget: `cells` are convex polygons in this block's local px space.
signal fractured(block: Block, cells: Array[PackedVector2Array], impact_local: Vector2)

enum Layer { WORLD = 1, BLOCKS = 2, ENEMIES = 4, PROJECTILES = 8, PROPS = 16 }

const PATTERNS: Array[String] = ["wood", "stone", "glass", "ice", "iron", "thatch", "cloth"]
const SHADER: Shader = preload("res://shaders/block.gdshader")
const MAX_MARKS: int = 4
## Pieces smaller than this become particles instead of bodies.
const MIN_PIECE_M2: float = 0.018
const MAX_GENERATION: int = 2

static var _shared: Dictionary = {}

var spec: Dictionary = {}
var material_id: String = ""
var mat: Dictionary = {}
var area_m2: float = 1.0
var max_hp: float = 1.0
var hp: float = 1.0
var is_broken: bool = false
## 0 = placed by the level; pieces are 1, pieces of pieces 2.
var generation: int = 0
var uv_xform: Transform2D = Transform2D.IDENTITY
## Velocity at the start of the current physics step (read by neighbours).
var pre_velocity: Vector2 = Vector2.ZERO
var burning: bool = false
var frozen: bool = false
var charred: float = 0.0

var _pending_damage: float = 0.0
var _pending_impulse: float = 0.0
var _pending_point: Vector2 = Vector2.ZERO
var _last_impact_local: Vector2 = Vector2.ZERO
var _visual: MeshInstance2D
var _own_material: ShaderMaterial = null
var _seed: float = 0.0
var _flash: float = 0.0
var _marks: Array[Vector4] = []
var _burn_fx: Node2D = null
var _burn_t: float = 0.0
var _rng := RandomNumberGenerator.new()


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


func setup(
	block_spec: Dictionary, material_def: Dictionary, index: int, piece_uv: Variant = null
) -> void:
	spec = block_spec
	material_id = str(block_spec.get("material", "wood"))
	mat = material_def
	area_m2 = ShapeGeometry.area_m2(spec)
	max_hp = float(mat.get("hp_per_m2", 100.0)) * area_m2
	hp = max_hp
	_seed = float(index) * 1.618 + float(material_id.hash() % 97)
	_rng.seed = hash(Vector2(float(index), float(material_id.hash())))
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

	uv_xform = (
		piece_uv
		if piece_uv is Transform2D
		else ShapeGeometry.default_uv_xform(spec, Vector2(_seed * 3.7, _seed * 1.3))
	)
	_visual = MeshInstance2D.new()
	_visual.mesh = ShapeGeometry.bevel_mesh_for(spec, Vector2.ZERO, uv_xform)
	_visual.material = shader_material_for(material_id, mat)
	add_child(_visual)

	var occ := LightOccluder2D.new()
	var op := OccluderPolygon2D.new()
	op.polygon = ShapeGeometry.polygon_for(spec)
	op.cull_mode = OccluderPolygon2D.CULL_DISABLED
	occ.occluder = op
	add_child(occ)


func _physics_process(delta: float) -> void:
	if _pending_damage > 0.0:
		var dmg: float = _pending_damage
		var imp: float = _pending_impulse
		_pending_damage = 0.0
		_pending_impulse = 0.0
		apply_damage(dmg, imp, _pending_point)
	pre_velocity = linear_velocity
	if _flash > 0.0 and _own_material != null:
		_flash = maxf(0.0, _flash - 0.12)
		_own_material.set_shader_parameter("flash", 0.0 if Settings.reduce_flashing else _flash)
	if burning:
		_burn(delta)


func _integrate_forces(state: PhysicsDirectBodyState2D) -> void:
	if is_broken:
		return
	var speed_mult: float = 0.3 if frozen else 1.0
	var threshold: float = float(mat.get("impact_speed", 1.5)) * Units.PX_PER_M * speed_mult
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
			pr.on_hit_block(self, state.get_contact_local_position(i))
		elif other is Enemy:
			other_v = (other as Enemy).pre_velocity
		var n: Vector2 = state.get_contact_local_normal(i)
		var approach: float = absf((other_v - pre_velocity).dot(n))
		if approach < threshold:
			continue
		var impulse_ns: float = imp / Units.PX_PER_M
		if impulse_ns > _pending_impulse:
			_pending_impulse = impulse_ns
			_pending_point = state.get_contact_local_position(i)
		var brittle: float = 2.5 if frozen else 1.0
		_pending_damage += impulse_ns / 100.0 * float(mat.get("damage_scale", 1.0)) * mult * brittle


## `point` is a global position of the hit (for marks and fracture bias).
func apply_damage(amount: float, impulse_ns: float = 0.0, point: Vector2 = Vector2.INF) -> void:
	if is_broken or freeze:
		return
	hp -= amount
	if point != Vector2.INF:
		_last_impact_local = to_local(point)
	if impulse_ns >= 50.0:
		hit.emit(self, impulse_ns)
		Sfx.impact(material_id, impulse_ns, global_position if point == Vector2.INF else point)
		if material_id == "iron" and impulse_ns > 1500.0 and point != Vector2.INF:
			Effects.sparks(get_parent(), point, clampf(impulse_ns / 6000.0, 0.3, 1.0))
	if hp <= 0.0:
		break_apart()
		return
	_ensure_own_material()
	_own_material.set_shader_parameter("damage", clampf(1.0 - hp / max_hp, 0.0, 1.0))
	if impulse_ns >= 400.0 and point != Vector2.INF:
		_add_mark(_last_impact_local, clampf(impulse_ns / 4000.0, 0.25, 1.0))
	_flash = 0.5


func _ensure_own_material() -> void:
	if _own_material != null:
		return
	_own_material = (_visual.material as ShaderMaterial).duplicate() as ShaderMaterial
	_own_material.set_shader_parameter("seed", _seed)
	_visual.material = _own_material


## Impact marks (scuffs, chips, dents) painted by the shader.
func _add_mark(local_px: Vector2, strength: float) -> void:
	var uv: Vector2 = uv_xform * local_px
	var r: float = 0.08 + strength * 0.12
	_marks.append(Vector4(uv.x, uv.y, r, strength))
	if _marks.size() > MAX_MARKS:
		_marks.remove_at(0)
	var arr: Array[Vector4] = _marks.duplicate()
	while arr.size() < MAX_MARKS:
		arr.append(Vector4(0, 0, 0, 0))
	_own_material.set_shader_parameter("marks", arr)


# ------------------------------------------------------------- fracture ---
func break_apart() -> void:
	if is_broken:
		return
	is_broken = true
	var pts: int = Scoring.block_points(int(mat.get("points", 50)), area_m2)
	broken.emit(self, pts)
	var style: String = "shards" if frozen else str(mat.get("fracture", "chunks"))
	var cells: Array[PackedVector2Array] = []
	if generation < MAX_GENERATION and not burning:
		cells = compute_cells(style)
	Effects.break_burst(get_parent(), global_position, material_id, mat, area_m2, style)
	Sfx.shatter(material_id, area_m2, global_position)
	fractured.emit(self, cells, _last_impact_local)
	queue_free()


## Convex cells (local px) for this block's fracture style.
func compute_cells(style: String) -> Array[PackedVector2Array]:
	var poly: PackedVector2Array = ShapeGeometry.polygon_for(spec)
	var size_px: float = sqrt(area_m2) * Units.PX_PER_M
	var impact: Vector2 = _last_impact_local
	if not Geometry2D.is_point_in_polygon(impact, poly):
		impact = Vector2.ZERO
	var n: int = 4
	var bias: float = 0.4
	var aniso := Vector2.ONE
	match style:
		"splinter":
			n = clampi(roundi(area_m2 * 6.0) + 3, 3, 8)
			# Elongate cells along the grain (the block's longer local axis).
			var b: Rect2 = Fracture._bounds(poly)
			aniso = Vector2(0.3, 1.0) if b.size.x >= b.size.y else Vector2(1.0, 0.3)
		"chunks":
			n = clampi(roundi(area_m2 * 5.0) + 3, 3, 9)
			bias = 0.5
		"shards":
			n = clampi(roundi(area_m2 * 10.0) + 5, 5, 14)
			bias = 0.6
		"dent":
			n = clampi(roundi(area_m2 * 2.0) + 2, 2, 3)
			bias = 0.0
		"tufts":
			n = 3
		"tear":
			return Fracture.tear(poly, impact, _rng)
	var seeds: PackedVector2Array = Fracture.make_seeds(poly, n, impact, bias, size_px * 0.35, _rng)
	return Fracture.voronoi_cells(poly, seeds, aniso)


## Spec + uv transform for a piece cut from this block (cell in local px).
func piece_spec(cell: PackedVector2Array) -> Dictionary:
	var c: Vector2 = Fracture.centroid(cell)
	var pts := PackedVector2Array()
	for p: Vector2 in cell:
		pts.append(Units.to_m(p - c))
	var world_pos: Vector2 = to_global(c)
	return {
		"shape": "poly",
		"material": material_id,
		"pos": Units.to_m(world_pos),
		"rot": -rad_to_deg(rotation),
		"points": pts,
		"static": false,
		"_local_centroid": c,
	}


# ---------------------------------------------------------------- status ---
func ignite() -> void:
	if burning or not bool(mat.get("flammable", false)) or is_broken:
		return
	burning = true
	_ensure_own_material()
	_burn_fx = Effects.flames(self, sqrt(area_m2))
	Sfx.play_at("fire_start", global_position, -6.0)


func _burn(delta: float) -> void:
	_burn_t += delta
	var rate: float = float(mat.get("burn_rate", 0.12))
	hp -= max_hp * rate * delta
	charred = minf(1.0, charred + rate * delta * 1.2)
	_own_material.set_shader_parameter("charred", charred)
	# Spread to touching flammable blocks twice a second.
	if _burn_t >= 0.5:
		_burn_t = 0.0
		for b: Node2D in get_colliding_bodies():
			if b is Block and _rng.randf() < 0.45:
				(b as Block).ignite()
	if hp <= 0.0:
		break_apart()


func freeze_solid() -> void:
	if frozen or is_broken:
		return
	frozen = true
	if burning:
		burning = false
		if is_instance_valid(_burn_fx):
			_burn_fx.queue_free()
	_ensure_own_material()
	_own_material.set_shader_parameter("frozen", 1.0)


## Retire settled debris: shrink the visual (bodies must not be scaled),
## stop colliding with anything but the ground, then free.
func shrink_away() -> void:
	is_broken = true
	collision_layer = 0
	collision_mask = Layer.WORLD
	var tw := create_tween()
	# Physics clock: freeing a body must land on the same physics step no
	# matter how fast real time runs (slow motion).
	tw.set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
	(
		tw
		. tween_property(_visual, "scale", Vector2(0.05, 0.05), 0.6)
		. set_trans(Tween.TRANS_BACK)
		. set_ease(Tween.EASE_IN)
	)
	tw.tween_callback(queue_free)
