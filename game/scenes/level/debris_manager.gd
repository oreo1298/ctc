# SPDX-FileCopyrightText: 2026 Siegefall contributors
# SPDX-License-Identifier: MIT
class_name DebrisManager
extends Node
## Turns fractured blocks into physical pieces under a body budget
## (docs/DESIGN.md §8.2: ~300 dynamic bodies) and retires settled debris.

signal piece_spawned(piece: Block)

const MAX_BODIES: int = 320
const MAX_FRACTURES_PER_TICK: int = 3
## Small settled pieces fade away after this long asleep.
const DEBRIS_LIFETIME: float = 5.0
const SMALL_PIECE_M2: float = 0.15

var world: Node2D
var body_count: int = 0

var _queue: Array[Dictionary] = []
var _fractures_this_tick: int = 0
var _asleep_time: Dictionary = {}  # instance id -> seconds asleep
var _pieces: Array[Block] = []
var _index: int = 10000


func register(b: Block) -> void:
	body_count += 1
	b.add_to_group("blocks")
	b.fractured.connect(_on_fractured)
	b.tree_exited.connect(func() -> void: body_count -= 1)


func _on_fractured(b: Block, cells: Array[PackedVector2Array], impact_local: Vector2) -> void:
	if cells.is_empty():
		return
	var job: Dictionary = {
		"parent_xform": b.global_transform,
		"lin": b.linear_velocity,
		"ang": b.angular_velocity,
		"impact": b.to_global(impact_local),
		"impulse": maxf(1.0, b.mass * 0.002),
		"mat": b.mat,
		"material_id": b.material_id,
		"generation": b.generation + 1,
		"uv_xform": b.uv_xform,
		"specs": [],
		"frozen": b.frozen,
	}
	var specs: Array = job["specs"]
	for cell: PackedVector2Array in cells:
		specs.append(b.piece_spec(cell))
	if _fractures_this_tick < MAX_FRACTURES_PER_TICK:
		_fractures_this_tick += 1
		_spawn(job)
	else:
		_queue.append(job)


func _physics_process(delta: float) -> void:
	_fractures_this_tick = 0
	while not _queue.is_empty() and _fractures_this_tick < MAX_FRACTURES_PER_TICK:
		_fractures_this_tick += 1
		_spawn(_queue.pop_front())
	_retire_settled(delta)


func _spawn(job: Dictionary) -> void:
	var mat: Dictionary = job["mat"]
	var xf: Transform2D = job["parent_xform"]
	for s: Variant in job["specs"]:
		var spec: Dictionary = s
		var area: float = ShapeGeometry.area_m2(spec)
		var world_pos: Vector2 = Units.to_px(spec["pos"])
		if area < Block.MIN_PIECE_M2 or (body_count >= MAX_BODIES and not _make_room()):
			Effects.chips(world, world_pos, mat, area)
			continue
		var p := Block.new()
		var local_c: Vector2 = spec["_local_centroid"]
		var uv: Transform2D = (job["uv_xform"] as Transform2D) * Transform2D(0.0, local_c)
		_index += 1
		p.setup(spec, mat, _index, uv)
		p.generation = int(job["generation"])
		# Pieces are a bit weaker than fresh blocks: they are already broken.
		p.max_hp *= 0.7
		p.hp = p.max_hp
		world.add_child(p)
		register(p)
		var r: Vector2 = world_pos - xf.origin
		var spin: Vector2 = Vector2(-r.y, r.x) * float(job["ang"])
		var away: Vector2 = (world_pos - (job["impact"] as Vector2)).normalized()
		# Torn cloth flops apart; everything else gets a small outward kick.
		var torn: bool = str(mat.get("fracture", "")) == "tear"
		p.linear_velocity = (job["lin"] as Vector2) + spin + away * (220.0 if torn else 90.0)
		p.angular_velocity = float(job["ang"]) + (signf(away.x) * 2.5 if torn else 0.0)
		if bool(job["frozen"]):
			p.freeze_solid()
		_pieces.append(p)
		piece_spawned.emit(p)


## Free the oldest settled small piece to make room. Returns true on success.
func _make_room() -> bool:
	for i: int in _pieces.size():
		var p: Block = _pieces[i]
		if is_instance_valid(p) and p.sleeping and p.area_m2 < SMALL_PIECE_M2:
			_pieces.remove_at(i)
			_fade_out(p)
			return true
	return false


func _retire_settled(delta: float) -> void:
	var i: int = 0
	while i < _pieces.size():
		var p: Block = _pieces[i]
		if not is_instance_valid(p) or p.is_broken:
			_pieces.remove_at(i)
			continue
		var id: int = p.get_instance_id()
		if p.area_m2 < SMALL_PIECE_M2 and p.linear_velocity.length() < 8.0:
			_asleep_time[id] = float(_asleep_time.get(id, 0.0)) + delta
			if float(_asleep_time[id]) > DEBRIS_LIFETIME:
				_asleep_time.erase(id)
				_pieces.remove_at(i)
				_fade_out(p)
				continue
		else:
			_asleep_time.erase(id)
		i += 1


func _fade_out(p: Block) -> void:
	p.shrink_away()
