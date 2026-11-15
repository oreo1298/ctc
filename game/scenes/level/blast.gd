# SPDX-FileCopyrightText: 2026 Siegefall contributors
# SPDX-License-Identifier: MIT
class_name Blast
extends RefCounted
## An explosion: pushes, damages and sets off what is near, then shows and
## sounds it. Used by the powder keg ammo and by powder stores in castles,
## so both behave the same. Deterministic: bodies are visited in tree order
## and nothing here uses a random number.


## Live blocks and enemies within `radius_px` of `center`, except `skip`.
static func bodies_near(
	tree: SceneTree, center: Vector2, radius_px: float, skip: Node = null
) -> Array[RigidBody2D]:
	var out: Array[RigidBody2D] = []
	for group: String in ["blocks", "enemies"]:
		for n: Node in tree.get_nodes_in_group(group):
			var b := n as RigidBody2D
			if b == null or b == skip:
				continue
			if b is Block and (b as Block).is_broken:
				continue
			if b is Enemy and (b as Enemy).is_dead:
				continue
			if b.global_position.distance_to(center) <= radius_px:
				out.append(b)
	return out


## `fx`: {"radius" (m), "impulse" (N·s at the centre), "damage"}. `show`
## scales the effects (a cask is a smaller boom than a keg).
static func detonate(
	at: Node, center: Vector2, fx: Dictionary, skip: Node = null, show: float = 1.0
) -> void:
	var radius: float = float(fx.get("radius", 3.5)) * Units.PX_PER_M
	var impulse: float = float(fx.get("impulse", 5000.0)) * Units.PX_PER_M
	var damage: float = float(fx.get("damage", 120.0))
	for b: RigidBody2D in bodies_near(at.get_tree(), center, radius, skip):
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
	var parent: Node = at.get_parent()
	Effects.explosion(parent, center, radius * show)
	Effects.shake(0.95 * show)
	Effects.haptic(show)
	Effects.slow_motion(0.3, 0.35)
	Sfx.play_at("boom", center, 2.0 if show >= 1.0 else -1.0)
	Sfx.play_at("rumble", center, -3.0 if show >= 1.0 else -7.0)
