# SPDX-FileCopyrightText: 2026 Siegefall contributors
# SPDX-License-Identifier: MIT
extends GutTest
## Powder stores chain-react; wind bends shots (and only sideways, in flight).

var lv: Level


func after_each() -> void:
	get_tree().paused = false
	Game.cli.erase("no-save")
	Game.custom_level = {}
	Effects.reset_time()


func _load(level: Dictionary) -> void:
	Game.cli["no-save"] = "true"
	Game.custom_from_editor = false
	Game.custom_level = level
	Game.current_level_id = ""
	lv = (load("res://scenes/level/level.tscn") as PackedScene).instantiate()
	add_child_autofree(lv)
	await wait_physics_frames(3)


func _powder_blocks() -> Array[Block]:
	var out: Array[Block] = []
	for n: Node in get_tree().get_nodes_in_group("blocks"):
		var b := n as Block
		if b != null and not b.is_broken and b.material_id == "powder":
			out.append(b)
	return out


func test_powder_is_a_valid_material() -> void:
	var m: Dictionary = Data.material("powder")
	assert_false(m.is_empty())
	assert_true(m.get("explosive") is Dictionary, "it has a blast")
	assert_true(bool(m.get("flammable", false)), "fire sets it off")
	assert_eq(ShareCode.MATERIALS.find("powder"), 7, "appended, so old codes still decode")


func test_one_cask_sets_off_its_neighbours() -> void:
	await _load(Data.load_level("dev-powder").source)
	var casks: Array[Block] = _powder_blocks()
	assert_eq(casks.size(), 5)
	var first: Block = casks[0]
	first.apply_damage(first.max_hp * 2.0)
	assert_false(first.is_broken, "lit, not gone yet: a short fuse first")
	assert_gt(first.fuse_ticks, 0)
	await wait_physics_frames(60)
	var left: Array[Block] = _powder_blocks()
	assert_lt(left.size(), 2, "the chain went through the row (left: %d)" % left.size())
	assert_lt(lv.targets_left, 3, "and took royals with it")


func test_fire_lights_the_fuse() -> void:
	await _load(Data.load_level("dev-powder").source)
	var cask: Block = _powder_blocks()[4]
	cask.ignite()
	assert_eq(cask.fuse_ticks, Block.BURN_FUSE_TICKS)
	await wait_physics_frames(Block.BURN_FUSE_TICKS + 5)
	assert_false(is_instance_valid(cask) and not cask.is_broken, "it went off")


func _landing_x(wind: float) -> float:
	var level: Dictionary = Data.load_level("greenmantle-01").source.duplicate(true)
	level["wind"] = wind
	await _load(level)
	lv.on_fire()
	await wait_physics_frames(2)
	lv.on_fire()
	await wait_until(func() -> bool: return lv.trebuchet.current_phase() >= 0.36, 5.0)
	lv.on_fire()
	var p: Projectile = lv.projectile
	await wait_until(func() -> bool: return not is_instance_valid(p) or p.has_impacted, 8.0)
	var x: float = p.global_position.x if is_instance_valid(p) else INF
	lv.queue_free()
	await wait_physics_frames(2)
	return x


func test_wind_bends_the_shot() -> void:
	var calm: float = await _landing_x(0.0)
	var tail: float = await _landing_x(6.0)
	var head: float = await _landing_x(-6.0)
	assert_gt(tail, calm + 50.0, "a tailwind carries the shot further")
	assert_lt(head, calm - 50.0, "a headwind holds it back")


func test_wind_survives_share_codes_and_is_light_on_iron() -> void:
	var level: Dictionary = Data.load_level("greenmantle-03").source.duplicate(true)
	level["wind"] = -3.5
	var r: Dictionary = ShareCode.decode(ShareCode.encode(level))
	assert_true(r["ok"])
	assert_almost_eq(float(r["level"].get("wind", 0.0)), -3.5, 0.001)
	var iron: float = Projectile.wind_accel_for(4.0, Data.ammo_def("iron"))
	var scatter: float = Projectile.wind_accel_for(4.0, Data.ammo_def("scatter"))
	assert_lt(absf(iron), absf(scatter), "heavy ammo drifts less")
