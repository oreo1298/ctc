# SPDX-FileCopyrightText: 2026 Siegefall contributors
# SPDX-License-Identifier: MIT
class_name Enemy
extends RigidBody2D
## A royal, knight or hostage. Takes damage like a block (approach-speed
## gated impulses), and is eliminated slapstick-style: squash, poof, and the
## headgear flies off as its own little physics prop. No gore, ever.

signal eliminated(enemy: Enemy, points: int)
signal hurt(enemy: Enemy, amount: float)

const ART_SCALE: float = 2.0  # SVGs are imported at 2x (project importer defaults)

var type_id: String = ""
var def: Dictionary = {}
var max_hp: float = 40.0
var hp: float = 40.0
var is_target: bool = true
var is_dead: bool = false
var pre_velocity: Vector2 = Vector2.ZERO
var kill_y_px: float = 1000.0

var _pending: float = 0.0
## Newtons of load from blocks resting on top, measured last physics step.
var _load_n: float = 0.0
var _body: Sprite2D
var _headgear: Sprite2D = null
var _headgear_lost: bool = false
var _wobble: float = 0.0


func setup(id: String, enemy_def: Dictionary, pos_m: Vector2, flip: bool) -> void:
	type_id = id
	def = enemy_def
	max_hp = float(def.get("hp", 40.0))
	hp = max_hp
	is_target = bool(def.get("target", true))
	position = Units.to_px(pos_m)
	mass = float(def.get("mass", 90.0))
	var pm := PhysicsMaterial.new()
	pm.friction = 0.8
	pm.bounce = 0.05
	physics_material_override = pm
	collision_layer = Block.Layer.ENEMIES
	collision_mask = (
		Block.Layer.WORLD
		| Block.Layer.BLOCKS
		| Block.Layer.ENEMIES
		| Block.Layer.PROJECTILES
		| Block.Layer.PROPS
	)
	contact_monitor = true
	max_contacts_reported = 4
	angular_damp = 2.0

	var r: float = float(def.get("radius", 0.3)) * Units.PX_PER_M
	var h: float = float(def.get("height", 1.1)) * Units.PX_PER_M
	var cap := CapsuleShape2D.new()
	cap.radius = r
	cap.height = h
	var cs := CollisionShape2D.new()
	cs.shape = cap
	add_child(cs)

	_body = Sprite2D.new()
	_body.texture = load(str(def.get("art", ""))) as Texture2D
	_body.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_body.flip_h = flip
	if _body.texture != null:
		var s: float = h / (_body.texture.get_height() / ART_SCALE) / ART_SCALE
		_body.scale = Vector2(s, s)
	add_child(_body)

	var hg_path: Variant = def.get("headgear")
	if hg_path is String and not (hg_path as String).is_empty():
		_headgear = Sprite2D.new()
		_headgear.texture = load(hg_path as String) as Texture2D
		_headgear.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		_headgear.scale = _body.scale
		# Character art puts the top of the head at 8% of the body height.
		_headgear.position = Vector2(0.0, -h * 0.5 + h * 0.06)
		_headgear.flip_h = flip
		add_child(_headgear)


func _physics_process(delta: float) -> void:
	if is_dead:
		return
	if _pending > 0.0:
		var dmg: float = _pending
		_pending = 0.0
		take_damage(dmg)
	pre_velocity = linear_velocity
	if global_position.y > kill_y_px:
		eliminate()
	# Idle wobble so they look alive (visual only).
	_wobble += delta
	_body.rotation = sin(_wobble * 2.2 + float(get_instance_id() % 7)) * 0.03


func _integrate_forces(state: PhysicsDirectBodyState2D) -> void:
	if is_dead:
		return
	var threshold: float = float(def.get("impact_speed", 1.2)) * Units.PX_PER_M
	var load_n: float = 0.0
	for i: int in state.get_contact_count():
		var imp: float = state.get_contact_impulse(i).length()
		if imp <= 0.0:
			continue
		var other: Object = state.get_contact_collider_object(i)
		# Sustained weight pressing down from a block above us (crushing).
		if other is Block and state.get_contact_local_normal(i).y > 0.5:
			load_n += imp / Units.PX_PER_M / state.step
		var other_v := Vector2.ZERO
		if other is Block:
			other_v = (other as Block).pre_velocity
		elif other is Projectile:
			other_v = (other as Projectile).pre_velocity
		elif other is Enemy:
			other_v = (other as Enemy).pre_velocity
		var approach: float = absf((other_v - pre_velocity).dot(state.get_contact_local_normal(i)))
		if approach < threshold:
			continue
		# Enemies are light, so scale their damage per kg moved rather than raw impulse.
		_pending += imp / Units.PX_PER_M / 100.0 * float(def.get("damage_taken", 1.0)) * 2.0
	_load_n = load_n
	var crush: float = float(def.get("crush_force", 2200.0))
	if load_n > crush:
		# Squashed under a heavy block: a few tenths of a second does it.
		_pending += (load_n - crush) / crush * 30.0 * state.step * float(def.get("damage_taken", 1.0))


func take_damage(amount: float) -> void:
	if is_dead:
		return
	hp -= amount
	hurt.emit(self, amount)
	var at: float = float(def.get("headgear_at_hp", 0.0))
	if _headgear != null and not _headgear_lost and at > 0.0 and hp <= max_hp * at:
		_pop_headgear()
	var tw := create_tween()
	_body.modulate = Color(1.0, 0.75, 0.75)
	tw.tween_property(_body, "modulate", Color.WHITE, 0.25)
	if hp <= 0.0:
		eliminate()


func _pop_headgear() -> void:
	if _headgear == null or _headgear_lost:
		return
	_headgear_lost = true
	var prop := RigidBody2D.new()
	prop.collision_layer = Block.Layer.PROPS
	prop.collision_mask = Block.Layer.WORLD | Block.Layer.BLOCKS
	prop.mass = 3.0
	var cs := CollisionShape2D.new()
	var c := CircleShape2D.new()
	c.radius = 14.0
	cs.shape = c
	prop.add_child(cs)
	var spr := Sprite2D.new()
	spr.texture = _headgear.texture
	spr.scale = _headgear.global_scale
	spr.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	prop.add_child(spr)
	prop.global_position = _headgear.global_position
	prop.rotation = global_rotation
	var side: float = 1.0 if randf() > 0.5 else -1.0
	prop.linear_velocity = Vector2(side * randf_range(120.0, 260.0), randf_range(-620.0, -460.0))
	prop.angular_velocity = side * randf_range(8.0, 14.0)
	get_parent().add_child(prop)
	_headgear.visible = false
	# Lost headgear fades away after a while so it never clutters the level.
	var tw := prop.create_tween()
	tw.tween_interval(6.0)
	tw.tween_property(spr, "modulate:a", 0.0, 1.0)
	tw.tween_callback(prop.queue_free)


func eliminate() -> void:
	if is_dead:
		return
	is_dead = true
	hp = 0.0
	_pop_headgear()
	eliminated.emit(self, int(def.get("points", 0)))
	collision_layer = 0
	collision_mask = Block.Layer.WORLD
	var tw := create_tween()
	tw.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	tw.tween_property(_body, "scale", Vector2(_body.scale.x * 1.45, _body.scale.y * 0.18), 0.16)
	tw.tween_callback(func() -> void: Effects.poof(get_parent(), global_position))
	tw.tween_property(_body, "modulate:a", 0.0, 0.12)
	tw.tween_callback(queue_free)
