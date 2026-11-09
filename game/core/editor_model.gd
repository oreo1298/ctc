# SPDX-FileCopyrightText: 2026 Siegefall contributors
# SPDX-License-Identifier: MIT
class_name EditorModel
extends RefCounted
## The castle editor's document and operations, independent of any UI so
## they can be unit-tested. The document is an ordinary level dictionary
## (docs/LEVEL_FORMAT.md); a selection is {"kind": "block"|"enemy"|"point",
## "i": index, "j": point index (terrain)} or {}.
##
## Placement settles things onto the surface below them (block tops or the
## terrain), so castles built in the editor stand still when play starts:
## a block or person rests on the highest surface under it whose top is no
## higher than its centre, so dropping something on the upper half of a
## block stacks it on top. Anchors (static blocks) stay where they are put.
##
## "par" in the document is the author's own record from test-play; any
## edit that changes the castle (not just its name or sky) clears it.

signal changed

const ROT_STEP: float = 15.0
const SNAP: float = 0.05
const MAX_UNDO: int = 100
const ENEMY_HALF: Dictionary = {"king": 0.55, "queen": 0.55, "knight": 0.575, "hostage": 0.5}
## Fields that only change the look or the words, so they keep the par.
const COSMETIC: Array[String] = ["name", "grievance", "time_of_day", "realm"]
const MIN_WORLD_RIGHT: float = 24.0
const MAX_WORLD_RIGHT: float = 120.0

var doc: Dictionary = {}
var _undo: Array[String] = []
var _redo: Array[String] = []


static func new_level() -> Dictionary:
	return {
		"format": "level",
		"version": 1,
		"id": CustomLevels.unique_id(),
		"name": "My Castle",
		"grievance": "",
		"time_of_day": "afternoon",
		"realm": "greenmantle",
		"world": {"right": 52.0, "kill_y": -10.0},
		"trebuchet": {"x": 0.0, "y": 0.0},
		"terrain": [{"points": [[-24.0, 0.0], [90.0, 0.0]], "style": "grass"}],
		"blocks": [],
		"enemies": [],
	}


func load_doc(d: Dictionary) -> void:
	doc = d.duplicate(true)
	for k: String in ["par_override", "solution", "solution_basic", "content_hash", "$schema"]:
		doc.erase(k)
	_undo.clear()
	_redo.clear()
	changed.emit()


# ------------------------------------------------------------ undo/redo ---
func checkpoint(keeps_par: bool = false) -> void:
	_undo.append(JSON.stringify(doc))
	if not keeps_par:
		doc.erase("par")
	if _undo.size() > MAX_UNDO:
		_undo.remove_at(0)
	_redo.clear()


func can_undo() -> bool:
	return not _undo.is_empty()


func can_redo() -> bool:
	return not _redo.is_empty()


func undo() -> void:
	if _undo.is_empty():
		return
	_redo.append(JSON.stringify(doc))
	doc = JSON.parse_string(_undo.pop_back())
	changed.emit()


func redo() -> void:
	if _redo.is_empty():
		return
	_undo.append(JSON.stringify(doc))
	doc = JSON.parse_string(_redo.pop_back())
	changed.emit()


# ------------------------------------------------------------ geometry ---
func blocks() -> Array:
	return doc.get("blocks", [])


func enemies() -> Array:
	return doc.get("enemies", [])


static func spec_of(b: Dictionary) -> Dictionary:
	return {
		"shape": str(b.get("shape", "rect")),
		"size": Units.vec2(b.get("size"), Vector2.ONE),
		"radius": float(b.get("radius", 0.5)),
		"points": _points(b.get("points", [])),
		"rot": float(b.get("rot", 0.0)),
	}


static func _points(raw: Variant) -> PackedVector2Array:
	var out := PackedVector2Array()
	if raw is Array:
		for p: Variant in raw:
			out.append(Units.vec2(p))
	return out


## World-space outline (metres, y up) of a block.
static func outline_m(b: Dictionary) -> PackedVector2Array:
	var spec: Dictionary = spec_of(b)
	var local: PackedVector2Array = ShapeGeometry.polygon_for(spec)
	var rot: float = Units.rot_to_godot(float(spec["rot"]))
	var pos: Vector2 = Units.vec2(b.get("pos"))
	var out := PackedVector2Array()
	for p: Vector2 in local:
		out.append(Units.to_m(p.rotated(rot)) + pos)
	return out


static func aabb_m(b: Dictionary) -> Rect2:
	var pts: PackedVector2Array = outline_m(b)
	var r := Rect2(pts[0], Vector2.ZERO)
	for p: Vector2 in pts:
		r = r.expand(p)
	return r


func terrain_height(x: float) -> float:
	var pieces: Array[Dictionary] = []
	for t: Variant in doc.get("terrain", []):
		pieces.append({"points": _points((t as Dictionary).get("points", []))})
	var h: float = Terrain.height_at(pieces, x)
	return h if not is_nan(h) else float(doc.get("world", {}).get("kill_y", -10.0))


## Highest supporting surface under the span [x0, x1] for something whose
## centre is at height `y`, ignoring block `skip`.
func surface_below(x0: float, x1: float, y: float, skip: int = -1) -> float:
	var best: float = -INF
	for k: int in 5:
		best = maxf(best, terrain_height(lerpf(x0, x1, k / 4.0)))
	var list: Array = blocks()
	for i: int in list.size():
		if i == skip:
			continue
		var r: Rect2 = aabb_m(list[i])
		var overlap: float = minf(x1, r.end.x) - maxf(x0, r.position.x)
		# A block counts if `y` is above its top, or at least above its middle:
		# dropping onto the upper half of a block stacks on it.
		if overlap > 0.04 and (r.end.y <= y + 0.12 or r.get_center().y <= y):
			best = maxf(best, r.end.y)
	return best


# ----------------------------------------------------------- operations ---
static func make_block(preset: Dictionary, material: String, pos: Vector2) -> Dictionary:
	var b: Dictionary = {
		"shape": str(preset.get("shape", "rect")),
		"material": material,
		"pos": [snappedf(pos.x, SNAP), snappedf(pos.y, SNAP)],
	}
	if b["shape"] == "circle":
		b["radius"] = float(preset.get("radius", 0.4))
	else:
		var size: Array = preset.get("size", [1.0, 0.3])
		b["size"] = [float(size[0]), float(size[1])]
	return b


## The block as it would land if placed at `pos` (for the placement ghost).
func preview_block(preset: Dictionary, material: String, pos: Vector2) -> Dictionary:
	var b: Dictionary = make_block(preset, material, pos)
	var p: Vector2 = rest_block(b)
	b["pos"] = [p.x, p.y]
	return b


## Where a person placed at `pos` would stand.
func preview_enemy(type: String, pos: Vector2) -> Vector2:
	return rest_enemy({"type": type, "pos": [snappedf(pos.x, SNAP), pos.y]})


func add_block(preset: Dictionary, material: String, pos: Vector2) -> Dictionary:
	checkpoint()
	blocks().append(make_block(preset, material, pos))
	var sel: Dictionary = {"kind": "block", "i": blocks().size() - 1}
	_settle(sel)
	changed.emit()
	return sel


func add_enemy(type: String, pos: Vector2) -> Dictionary:
	checkpoint()
	enemies().append({"type": type, "pos": [snappedf(pos.x, SNAP), pos.y]})
	var sel: Dictionary = {"kind": "enemy", "i": enemies().size() - 1}
	_settle(sel)
	changed.emit()
	return sel


## Move to `pos` (centre). With `settle`, comes to rest on the surface below.
func move(sel: Dictionary, pos: Vector2, settle: bool = true) -> void:
	var p := Vector2(snappedf(pos.x, SNAP), snappedf(pos.y, SNAP))
	match str(sel.get("kind", "")):
		"block":
			blocks()[int(sel["i"])]["pos"] = [p.x, p.y]
		"enemy":
			enemies()[int(sel["i"])]["pos"] = [p.x, p.y]
		"point":
			var pts: Array = doc["terrain"][int(sel["i"])]["points"]
			var j: int = int(sel["j"])
			var lo: float = float(pts[j - 1][0]) + 0.1 if j > 0 else -1000.0
			var hi: float = float(pts[j + 1][0]) - 0.1 if j < pts.size() - 1 else 1000.0
			pts[j] = [clampf(p.x, lo, hi), p.y]
			changed.emit()
			return
	if settle:
		_settle(sel)
	changed.emit()


## Resting centre for block `b` (index `skip` in the list, or -1).
func rest_block(b: Dictionary, skip: int = -1) -> Vector2:
	var pos: Vector2 = Units.vec2(b["pos"])
	if bool(b.get("static", false)):
		return pos
	var r: Rect2 = aabb_m(b)
	var s: float = surface_below(r.position.x, r.end.x, pos.y, skip)
	return Vector2(pos.x, snappedf(pos.y + (s - r.position.y), 0.001))


func rest_enemy(e: Dictionary) -> Vector2:
	var pos: Vector2 = Units.vec2(e["pos"])
	var half: float = float(ENEMY_HALF.get(str(e.get("type", "")), 0.55))
	var s: float = surface_below(pos.x - 0.25, pos.x + 0.25, pos.y)
	return Vector2(pos.x, snappedf(s + half, 0.001))


func _settle(sel: Dictionary) -> void:
	var kind: String = str(sel.get("kind", ""))
	if kind == "block":
		var b: Dictionary = blocks()[int(sel["i"])]
		var p: Vector2 = rest_block(b, int(sel["i"]))
		b["pos"] = [p.x, p.y]
	elif kind == "enemy":
		var e: Dictionary = enemies()[int(sel["i"])]
		var p: Vector2 = rest_enemy(e)
		e["pos"] = [p.x, p.y]


func rotate(sel: Dictionary, steps: int) -> void:
	if str(sel.get("kind", "")) != "block":
		return
	checkpoint()
	var b: Dictionary = blocks()[int(sel["i"])]
	b["rot"] = fposmod(float(b.get("rot", 0.0)) + steps * ROT_STEP + 180.0, 360.0) - 180.0
	if is_zero_approx(float(b["rot"])):
		b.erase("rot")
	_settle(sel)
	changed.emit()


## axis 0 = width (or radius), 1 = height. delta in metres.
func resize(sel: Dictionary, axis: int, delta: float) -> void:
	if str(sel.get("kind", "")) != "block":
		return
	checkpoint()
	var b: Dictionary = blocks()[int(sel["i"])]
	if str(b["shape"]) == "circle":
		b["radius"] = clampf(float(b.get("radius", 0.4)) + delta * 0.5, 0.1, 3.0)
	elif b.has("size"):
		var size: Array = b["size"]
		size[axis] = clampf(snappedf(float(size[axis]) + delta, SNAP), 0.1, 12.0)
	_settle(sel)
	changed.emit()


func set_material(sel: Dictionary, material: String) -> void:
	if str(sel.get("kind", "")) != "block":
		return
	checkpoint()
	blocks()[int(sel["i"])]["material"] = material
	changed.emit()


func flip(sel: Dictionary) -> void:
	if str(sel.get("kind", "")) != "enemy":
		return
	checkpoint()
	var e: Dictionary = enemies()[int(sel["i"])]
	e["flip"] = not bool(e.get("flip", false))
	changed.emit()


func duplicate_sel(sel: Dictionary) -> Dictionary:
	var kind: String = str(sel.get("kind", ""))
	if kind != "block" and kind != "enemy":
		return sel
	checkpoint()
	var list: Array = blocks() if kind == "block" else enemies()
	var copy: Dictionary = (list[int(sel["i"])] as Dictionary).duplicate(true)
	var pos: Vector2 = Units.vec2(copy["pos"])
	var w: float = aabb_m(copy).size.x if kind == "block" else 0.7
	copy["pos"] = [pos.x + w, pos.y]
	list.append(copy)
	var out: Dictionary = {"kind": kind, "i": list.size() - 1}
	_settle(out)
	changed.emit()
	return out


func delete(sel: Dictionary) -> void:
	var kind: String = str(sel.get("kind", ""))
	if kind == "block":
		checkpoint()
		blocks().remove_at(int(sel["i"]))
	elif kind == "enemy":
		checkpoint()
		enemies().remove_at(int(sel["i"]))
	elif kind == "point":
		var pts: Array = doc["terrain"][int(sel["i"])]["points"]
		if pts.size() <= 2:
			return
		checkpoint()
		pts.remove_at(int(sel["j"]))
	changed.emit()


## Insert a terrain point on the segment nearest to `pos`.
func insert_point(pos: Vector2) -> Dictionary:
	var best: Dictionary = {}
	var best_d: float = 1.5
	var terrain: Array = doc.get("terrain", [])
	for i: int in terrain.size():
		var pts: Array = terrain[i]["points"]
		for j: int in pts.size() - 1:
			var a: Vector2 = Units.vec2(pts[j])
			var b: Vector2 = Units.vec2(pts[j + 1])
			if pos.x <= a.x + 0.2 or pos.x >= b.x - 0.2:
				continue
			var d: float = Geometry2D.get_closest_point_to_segment(pos, a, b).distance_to(pos)
			if d < best_d:
				best_d = d
				best = {"kind": "point", "i": i, "j": j + 1}
	if best.is_empty():
		return {}
	checkpoint()
	var arr: Array = terrain[int(best["i"])]["points"]
	arr.insert(int(best["j"]), [snappedf(pos.x, SNAP), snappedf(pos.y, SNAP)])
	changed.emit()
	return best


## Topmost thing under `pos` (metres): enemies, then blocks (last drawn
## first), then terrain points within `point_radius`.
func pick(pos: Vector2, point_radius: float = 0.5, include_points: bool = false) -> Dictionary:
	if include_points:
		var terrain: Array = doc.get("terrain", [])
		for i: int in terrain.size():
			var pts: Array = terrain[i]["points"]
			for j: int in pts.size():
				if Units.vec2(pts[j]).distance_to(pos) <= point_radius:
					return {"kind": "point", "i": i, "j": j}
	var es: Array = enemies()
	for i: int in range(es.size() - 1, -1, -1):
		var e: Dictionary = es[i]
		var c: Vector2 = Units.vec2(e["pos"])
		if (
			absf(pos.x - c.x) < 0.38
			and absf(pos.y - c.y) < float(ENEMY_HALF.get(str(e["type"]), 0.55))
		):
			return {"kind": "enemy", "i": i}
	var bs: Array = blocks()
	for i: int in range(bs.size() - 1, -1, -1):
		if Geometry2D.is_point_in_polygon(pos, outline_m(bs[i])):
			return {"kind": "block", "i": i}
	return {}


func set_meta_field(key: String, value: Variant) -> void:
	if doc.get(key) == value:
		return
	checkpoint(key in COSMETIC)
	doc[key] = value
	changed.emit()


func set_world_right(right: float) -> void:
	var w: Dictionary = doc.get("world", {})
	var r: float = clampf(snappedf(right, 1.0), MIN_WORLD_RIGHT, MAX_WORLD_RIGHT)
	if is_equal_approx(float(w.get("right", 0.0)), r):
		return
	checkpoint()
	w["right"] = r
	doc["world"] = w
	changed.emit()


func set_terrain_style(style: String) -> void:
	checkpoint(true)
	for t: Variant in doc.get("terrain", []):
		(t as Dictionary)["style"] = style
	changed.emit()


## An anchor is static: it never moves or breaks (good for bridges).
func toggle_static(sel: Dictionary) -> void:
	if str(sel.get("kind", "")) != "block":
		return
	checkpoint()
	var b: Dictionary = blocks()[int(sel["i"])]
	if bool(b.get("static", false)):
		b.erase("static")
	else:
		b["static"] = true
	changed.emit()


## Record a win from test-play: the fewest shots becomes the castle's par.
func record_par(shots: int) -> bool:
	var par: Dictionary = doc.get("par", {})
	if not par.is_empty() and int(par.get("gold", 99)) <= shots:
		return false
	doc["par"] = {"gold": shots, "silver": shots + 1, "bronze": shots + 3}
	changed.emit()
	return true


## Pairs of block indices whose shapes overlap by more than a sliver. They
## would be pushed apart violently when play starts.
func overlaps() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var list: Array = blocks()
	var outlines: Array[PackedVector2Array] = []
	var boxes: Array[Rect2] = []
	for b: Variant in list:
		var o: PackedVector2Array = outline_m(b)
		outlines.append(o)
		var r := Rect2(o[0], Vector2.ZERO)
		for p: Vector2 in o:
			r = r.expand(p)
		boxes.append(r.grow(-0.02))
	for i: int in list.size():
		for j: int in range(i + 1, list.size()):
			if not boxes[i].intersects(boxes[j]):
				continue
			var area: float = 0.0
			for poly: PackedVector2Array in Geometry2D.intersect_polygons(outlines[i], outlines[j]):
				area += absf(_area(poly))
			if area > 0.01:
				out.append(Vector2i(i, j))
	return out


static func _area(poly: PackedVector2Array) -> float:
	var a: float = 0.0
	for k: int in poly.size():
		var p: Vector2 = poly[k]
		var q: Vector2 = poly[(k + 1) % poly.size()]
		a += p.x * q.y - q.x * p.y
	return a * 0.5


func count_targets() -> int:
	var n: int = 0
	for e: Variant in enemies():
		if bool(Data.enemy(str((e as Dictionary).get("type", ""))).get("target", true)):
			n += 1
	return n


## What stops the castle from being played (blocking) and what is merely
## worth a look (warnings), in words for the player.
func problems() -> Dictionary:
	var blocking := PackedStringArray()
	var warnings := PackedStringArray()
	if count_targets() == 0:
		blocking.append(tr("Place a king, queen or knight to defeat."))
	elif blocks().size() > LevelData.MAX_BLOCKS:
		blocking.append(
			tr("Too many blocks: %d is the most a castle can have.") % LevelData.MAX_BLOCKS
		)
	elif enemies().size() > LevelData.MAX_ENEMIES:
		blocking.append(tr("Too many people: %d is the most.") % LevelData.MAX_ENEMIES)
	else:
		for e: String in validate():
			blocking.append(e)
	if not overlaps().is_empty():
		warnings.append(tr("Some blocks overlap (red). They will jump apart when play starts."))
	var right: float = float(doc.get("world", {}).get("right", 50.0))
	var past: bool = false
	for b: Variant in blocks():
		past = past or aabb_m(b).end.x > right
	for e: Variant in enemies():
		past = past or Units.vec2((e as Dictionary).get("pos")).x > right
	if past:
		warnings.append(tr("Something is past the edge of the world (dashed line)."))
	return {"blocking": blocking, "warnings": warnings}


func validate() -> PackedStringArray:
	return Data.parse_level(doc).errors
