# SPDX-FileCopyrightText: 2026 Siegefall contributors
# SPDX-License-Identifier: MIT
class_name LevelData
extends RefCounted
## A parsed, validated level (docs/LEVEL_FORMAT.md). Construct with
## LevelData.parse(dict, data_registry) and check `errors` before use: the
## same code path loads campaign levels, editor saves and share codes, so it
## must never trust its input.

const FORMAT: String = "level"
const VERSION: int = 1
const MAX_BLOCKS: int = 400
const MAX_ENEMIES: int = 40
const SHAPES: Array[String] = ["rect", "circle", "tri", "wedge", "poly"]
const TIMES: Array[String] = ["dawn", "morning", "noon", "afternoon", "golden", "dusk", "night"]

var id: String = ""
var name: String = ""
var grievance: String = ""
var time_of_day: String = "noon"
var realm: String = ""
var world_right: float = 50.0
var kill_y: float = -10.0
var trebuchet_pos: Vector2 = Vector2.ZERO
## Each entry: {"points": PackedVector2Array (metres), "style": String}
var terrain: Array[Dictionary] = []
## Normalised block specs: shape, material, pos (Vector2), rot (deg), size
## (Vector2), radius (float), points (PackedVector2Array), static (bool).
var blocks: Array[Dictionary] = []
## {"type": String, "pos": Vector2, "flip": bool}
var enemies: Array[Dictionary] = []
var par: Dictionary = {"gold": 1, "silver": 2, "bronze": 4}
var solution: Array[Dictionary] = []
var errors: PackedStringArray = PackedStringArray()
var source: Dictionary = {}


func is_valid() -> bool:
	return errors.is_empty()


## materials / enemy_types: dictionaries of known ids (values unused) so
## that unknown references are reported instead of crashing later.
static func parse(d: Dictionary, materials: Dictionary, enemy_types: Dictionary) -> LevelData:
	var lv := LevelData.new()
	lv.source = d
	var migrated: Dictionary = migrate(d, lv.errors)
	if not lv.errors.is_empty():
		return lv
	lv._parse_v1(migrated, materials, enemy_types)
	return lv


## Upgrade older level versions step by step to VERSION.
static func migrate(d: Dictionary, errs: PackedStringArray) -> Dictionary:
	if str(d.get("format", "")) != FORMAT:
		errs.append('not a level file (format must be "%s")' % FORMAT)
		return d
	var v: int = int(d.get("version", 0))
	if v < 1 or v > VERSION:
		errs.append("unsupported level version %d (this game reads up to %d)" % [v, VERSION])
		return d
	# Future: while v < VERSION: d = _MIGRATIONS[v].call(d); v += 1
	return d


func _parse_v1(d: Dictionary, materials: Dictionary, enemy_types: Dictionary) -> void:
	id = str(d.get("id", ""))
	if id.is_empty() or not _is_slug(id):
		errors.append("id must be lower-case letters, digits and dashes")
	name = str(d.get("name", id)).strip_edges().left(60)
	grievance = str(d.get("grievance", "")).strip_edges().left(200)
	time_of_day = str(d.get("time_of_day", "noon"))
	if not TIMES.has(time_of_day):
		errors.append("unknown time_of_day '%s'" % time_of_day)
	realm = str(d.get("realm", ""))

	var world: Variant = d.get("world")
	if world is Dictionary:
		var w: Dictionary = world
		world_right = clampf(float(w.get("right", 50.0)), 10.0, 200.0)
		kill_y = minf(float(w.get("kill_y", -10.0)), 0.0)
	else:
		errors.append("missing world")

	var treb: Variant = d.get("trebuchet")
	if treb is Dictionary:
		var t: Dictionary = treb
		trebuchet_pos = Vector2(float(t.get("x", 0.0)), float(t.get("y", 0.0)))

	_parse_terrain(d.get("terrain"))
	_parse_blocks(d.get("blocks"), materials)
	_parse_enemies(d.get("enemies"), enemy_types)

	par = Scoring.effective_par(d)
	if not (
		int(par.get("gold", 1)) <= int(par.get("silver", 2))
		and int(par.get("silver", 2)) <= int(par.get("bronze", 4))
	):
		errors.append("par must satisfy gold <= silver <= bronze")
	var sol: Variant = d.get("solution")
	if sol is Array:
		for s: Variant in sol:
			if s is Dictionary:
				solution.append(s)


func _parse_terrain(raw: Variant) -> void:
	if not raw is Array or (raw as Array).is_empty():
		errors.append("terrain must be a non-empty list")
		return
	for t: Variant in raw:
		if not t is Dictionary:
			errors.append("terrain entry is not an object")
			continue
		var pts := PackedVector2Array()
		var raw_pts: Variant = (t as Dictionary).get("points")
		if raw_pts is Array:
			for p: Variant in raw_pts:
				pts.append(Units.vec2(p))
		if pts.size() < 2:
			errors.append("terrain needs at least 2 points")
			continue
		for i: int in range(1, pts.size()):
			if pts[i].x <= pts[i - 1].x:
				errors.append("terrain points must go strictly left to right")
				break
		terrain.append({"points": pts, "style": str((t as Dictionary).get("style", "grass"))})


func _parse_blocks(raw: Variant, materials: Dictionary) -> void:
	if not raw is Array:
		errors.append("blocks must be a list")
		return
	var list: Array = raw
	if list.size() > MAX_BLOCKS:
		errors.append("too many blocks (%d > %d)" % [list.size(), MAX_BLOCKS])
		return
	for i: int in list.size():
		var b: Variant = list[i]
		if not b is Dictionary:
			errors.append("block %d is not an object" % i)
			continue
		var bd: Dictionary = b
		var shape: String = str(bd.get("shape", ""))
		var mat: String = str(bd.get("material", ""))
		if not SHAPES.has(shape):
			errors.append("block %d: unknown shape '%s'" % [i, shape])
			continue
		if not materials.has(mat):
			errors.append("block %d: unknown material '%s'" % [i, mat])
			continue
		var spec: Dictionary = {
			"shape": shape,
			"material": mat,
			"pos": Units.vec2(bd.get("pos")),
			"rot": float(bd.get("rot", 0.0)),
			"static": bool(bd.get("static", false)),
			"size": Units.vec2(bd.get("size"), Vector2.ONE),
			"radius": float(bd.get("radius", 0.5)),
			"points": PackedVector2Array(),
		}
		var size: Vector2 = spec["size"]
		if (
			shape in ["rect", "tri", "wedge"]
			and (size.x < 0.05 or size.y < 0.05 or size.x > 20.0 or size.y > 20.0)
		):
			errors.append("block %d: size out of range (0.05..20 m)" % i)
			continue
		if shape == "circle" and (float(spec["radius"]) < 0.05 or float(spec["radius"]) > 5.0):
			errors.append("block %d: radius out of range (0.05..5 m)" % i)
			continue
		if shape == "poly":
			var pts := PackedVector2Array()
			var raw_pts: Variant = bd.get("points")
			if raw_pts is Array:
				for p: Variant in raw_pts:
					pts.append(Units.vec2(p))
			if pts.size() < 3 or pts.size() > 8 or not ShapeGeometry.is_convex(pts):
				errors.append("block %d: poly must be a convex polygon with 3..8 points" % i)
				continue
			spec["points"] = pts
		blocks.append(spec)


func _parse_enemies(raw: Variant, enemy_types: Dictionary) -> void:
	if not raw is Array or (raw as Array).is_empty():
		errors.append("a level needs at least one enemy")
		return
	var list: Array = raw
	if list.size() > MAX_ENEMIES:
		errors.append("too many enemies (%d > %d)" % [list.size(), MAX_ENEMIES])
		return
	var targets: int = 0
	for i: int in list.size():
		var e: Variant = list[i]
		if not e is Dictionary:
			errors.append("enemy %d is not an object" % i)
			continue
		var ed: Dictionary = e
		var type: String = str(ed.get("type", ""))
		if not enemy_types.has(type):
			errors.append("enemy %d: unknown type '%s'" % [i, type])
			continue
		var info: Variant = enemy_types[type]
		if info is Dictionary and bool((info as Dictionary).get("target", true)):
			targets += 1
		enemies.append(
			{"type": type, "pos": Units.vec2(ed.get("pos")), "flip": bool(ed.get("flip", false))}
		)
	if targets == 0 and errors.is_empty():
		errors.append("a level needs at least one royal or knight to defeat")


static func _is_slug(s: String) -> bool:
	for c: String in s:
		if not (c >= "a" and c <= "z") and not (c >= "0" and c <= "9") and c != "-":
			return false
	return true
