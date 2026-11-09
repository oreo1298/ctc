# SPDX-FileCopyrightText: 2026 Siegefall contributors
# SPDX-License-Identifier: MIT
class_name EditorView
extends Node2D
## Draws the castle being edited with the game's own art (backdrop, terrain,
## bevelled blocks, characters, trebuchet) plus an overlay for selection,
## the placement ghost, terrain handles, overlaps and the world's edge.
## Nothing here simulates: it is a still picture of the level document.

const BAD := Color(0.86, 0.2, 0.16)

var model: EditorModel
var selection: Dictionary = {}
var hover: Dictionary = {}
## {"block": Dictionary} or {"enemy": String, "pos": Vector2} (metres).
var ghost: Dictionary = {}
var show_points: bool = false

var _scenery_key: String = ""
var _backdrop: Backdrop = null
var _ambient: CanvasModulate
var _sun: DirectionalLight2D
var _terrain: Terrain = null
var _terrain_key: String = ""
var _pieces: Node2D
var _people: Node2D
var _treb: Trebuchet
var _overlay: _Overlay
var _ghost_node: Node2D = null
var _ghost_key: String = ""
var _overlaps: Array[Vector2i] = []
## Block visuals reused between refreshes, keyed by everything but position.
var _block_nodes: Array[Node2D] = []
var _block_keys: Array[String] = []


func _ready() -> void:
	_ambient = CanvasModulate.new()
	add_child(_ambient)
	_sun = DirectionalLight2D.new()
	_sun.height = 0.45
	_sun.max_distance = 2600.0
	add_child(_sun)
	_pieces = Node2D.new()
	add_child(_pieces)
	_treb = Trebuchet.new()
	add_child(_treb)
	_treb.setup(TrebuchetModel.from_dict(Data.trebuchet))
	_treb.set_ammo(Data.ammo_def("boulder"))
	_people = Node2D.new()
	add_child(_people)
	_overlay = _Overlay.new()
	_overlay.view = self
	_overlay.z_index = 50
	add_child(_overlay)


func refresh() -> void:
	var doc: Dictionary = model.doc
	_refresh_scenery(doc)
	_refresh_terrain(doc)
	_refresh_blocks()
	_refresh_people()
	_treb.position = Units.to_px(
		Units.vec2([doc.get("trebuchet", {}).get("x", 0.0), doc.get("trebuchet", {}).get("y", 0.0)])
	)
	_overlaps = model.overlaps()
	_overlay.queue_redraw()


func redraw_overlay() -> void:
	_refresh_ghost()
	_overlay.queue_redraw()


func world_right() -> float:
	return float(model.doc.get("world", {}).get("right", 50.0))


func kill_y() -> float:
	return float(model.doc.get("world", {}).get("kill_y", -10.0))


# --------------------------------------------------------------- scenery ---
func _refresh_scenery(doc: Dictionary) -> void:
	var key: String = "%s|%s|%d" % [doc.get("realm"), doc.get("time_of_day"), int(world_right())]
	if key == _scenery_key:
		return
	_scenery_key = key
	var realm: Dictionary = Data.realm(str(doc.get("realm", "")))
	if realm.is_empty() and not Data.realms.is_empty():
		realm = Data.realms[0]
	var grade: Dictionary = Data.grade(str(doc.get("time_of_day", "noon")))
	if _backdrop != null:
		_backdrop.queue_free()
	_backdrop = Backdrop.new()
	add_child(_backdrop)
	move_child(_backdrop, 0)
	_backdrop.build(realm.get("palette", {}), grade, realm.get("backdrop", {}), world_right(), 7)
	_ambient.color = Units.color(grade.get("ambient"), Color(0.85, 0.85, 0.85))
	_sun.color = Units.color(grade.get("sun_color"), Color.WHITE)
	_sun.energy = float(grade.get("sun_energy", 0.8))
	_sun.rotation_degrees = float(grade.get("sun_angle_deg", 30.0)) - 90.0
	_terrain_key = ""


func _refresh_terrain(doc: Dictionary) -> void:
	var key: String = JSON.stringify(doc.get("terrain", [])) + _scenery_key
	if key == _terrain_key:
		return
	_terrain_key = key
	if _terrain != null:
		_terrain.queue_free()
	_terrain = Terrain.new()
	add_child(_terrain)
	move_child(_terrain, _pieces.get_index())
	var pieces: Array[Dictionary] = []
	for t: Variant in doc.get("terrain", []):
		var td: Dictionary = t
		var pts := PackedVector2Array()
		for p: Variant in td.get("points", []):
			pts.append(Units.vec2(p))
		pieces.append({"points": pts, "style": str(td.get("style", "grass"))})
	var realm: Dictionary = Data.realm(str(doc.get("realm", "")))
	_terrain.build(pieces, kill_y(), realm.get("palette", {}))
	# The editor never simulates; keep the ground out of the physics space.
	_terrain.collision_layer = 0
	_terrain.process_mode = Node.PROCESS_MODE_DISABLED


# ---------------------------------------------------------------- pieces ---
static func _key_of(b: Dictionary) -> String:
	var copy: Dictionary = b.duplicate()
	copy.erase("pos")
	return JSON.stringify(copy)


static func block_visual(b: Dictionary, index: int) -> Node2D:
	var spec: Dictionary = EditorModel.spec_of(b)
	var mat_id: String = str(b.get("material", "wood"))
	var holder := Node2D.new()
	var mi := MeshInstance2D.new()
	var seed_value: float = float(index) * 1.618 + float(mat_id.hash() % 97)
	var uv: Transform2D = ShapeGeometry.default_uv_xform(
		spec, Vector2(seed_value * 3.7, seed_value * 1.3)
	)
	mi.mesh = ShapeGeometry.bevel_mesh_for(spec, Vector2.ZERO, uv)
	mi.material = Block.shader_material_for(mat_id, Data.material(mat_id))
	holder.add_child(mi)
	holder.rotation = Units.rot_to_godot(float(b.get("rot", 0.0)))
	return holder


func _refresh_blocks() -> void:
	var list: Array = model.blocks()
	# Pool existing visuals by key so moving a block never rebuilds its mesh.
	var pool: Dictionary = {}
	for k: int in _block_nodes.size():
		var arr: Array = pool.get(_block_keys[k], [])
		arr.append(_block_nodes[k])
		pool[_block_keys[k]] = arr
	var nodes: Array[Node2D] = []
	var keys: Array[String] = []
	for i: int in list.size():
		var b: Dictionary = list[i]
		var key: String = _key_of(b)
		var node: Node2D
		var spare: Array = pool.get(key, [])
		if not spare.is_empty():
			node = spare.pop_back()
		else:
			node = block_visual(b, i)
			_pieces.add_child(node)
		node.position = Units.to_px(Units.vec2(b.get("pos")))
		_pieces.move_child(node, i)
		nodes.append(node)
		keys.append(key)
	for arr: Variant in pool.values():
		for n: Variant in arr:
			(n as Node).queue_free()
	_block_nodes = nodes
	_block_keys = keys


static func person_visual(type: String, flip: bool) -> Node2D:
	var def: Dictionary = Data.enemy(type)
	var holder := Node2D.new()
	var body: Sprite2D = Enemy.body_sprite(def, flip)
	holder.add_child(body)
	var hg: Sprite2D = Enemy.headgear_sprite(def, body, flip)
	if hg != null:
		holder.add_child(hg)
	return holder


func _refresh_people() -> void:
	for c: Node in _people.get_children():
		c.queue_free()
	for e: Variant in model.enemies():
		var ed: Dictionary = e
		var n: Node2D = person_visual(str(ed.get("type", "king")), bool(ed.get("flip", false)))
		n.position = Units.to_px(Units.vec2(ed.get("pos")))
		_people.add_child(n)


func _refresh_ghost() -> void:
	var key: String = ""
	if ghost.has("block"):
		key = _key_of(ghost["block"])
	elif ghost.has("enemy"):
		key = str(ghost["enemy"])
	if key != _ghost_key:
		_ghost_key = key
		if _ghost_node != null:
			_ghost_node.queue_free()
			_ghost_node = null
		if ghost.has("block"):
			_ghost_node = block_visual(ghost["block"], 0)
		elif ghost.has("enemy"):
			_ghost_node = person_visual(str(ghost["enemy"]), false)
		if _ghost_node != null:
			_ghost_node.modulate = Color(1, 1, 1, 0.6)
			_ghost_node.z_index = 40
			add_child(_ghost_node)
	if _ghost_node != null:
		var pos: Vector2 = (
			Units.vec2((ghost["block"] as Dictionary).get("pos"))
			if ghost.has("block")
			else ghost.get("pos", Vector2.ZERO)
		)
		_ghost_node.position = Units.to_px(pos)


# --------------------------------------------------------------- overlay ---
class _Overlay:
	extends Node2D

	var view: EditorView

	func _zoom() -> float:
		var cam: Camera2D = get_viewport().get_camera_2d()
		return cam.zoom.x if cam != null else 1.0

	func _outline(pts: PackedVector2Array, col: Color, width: float) -> void:
		var px := PackedVector2Array()
		for p: Vector2 in pts:
			px.append(Units.to_px(p))
		px.append(px[0])
		draw_polyline(px, col, width, true)

	func _fill(pts: PackedVector2Array, col: Color) -> void:
		var px := PackedVector2Array()
		for p: Vector2 in pts:
			px.append(Units.to_px(p))
		if Geometry2D.triangulate_polygon(px).size() >= 3:
			draw_colored_polygon(px, col)

	func _person_rect(e: Dictionary) -> Rect2:
		var half: float = float(EditorModel.ENEMY_HALF.get(str(e.get("type", "")), 0.55))
		var c: Vector2 = Units.to_px(Units.vec2(e.get("pos")))
		var hpx: float = half * Units.PX_PER_M
		return Rect2(c - Vector2(38.0, hpx), Vector2(76.0, hpx * 2.0))

	func _draw() -> void:
		if view == null or view.model == null:
			return
		var w: float = 2.5 / _zoom()
		var model: EditorModel = view.model
		var blocks: Array = model.blocks()
		# The world's edge: things past it are out of play.
		var edge_x: float = view.world_right() * Units.PX_PER_M
		var top: float = -30.0 * Units.PX_PER_M
		var bottom: float = -view.kill_y() * Units.PX_PER_M
		var y: float = top
		while y < bottom:
			draw_line(
				Vector2(edge_x, y),
				Vector2(edge_x, minf(y + 40.0, bottom)),
				Color(UiTheme.INK, 0.55),
				w
			)
			y += 80.0
		for pair: Vector2i in view._overlaps:
			for k: int in [pair.x, pair.y]:
				if k < blocks.size():
					var o: PackedVector2Array = EditorModel.outline_m(blocks[k])
					_fill(o, Color(BAD, 0.35))
					_outline(o, BAD, w)
		# Anchors: a dashed iron frame says "this never moves".
		for b: Variant in blocks:
			if bool((b as Dictionary).get("static", false)):
				_outline(EditorModel.outline_m(b), Color(0.2, 0.22, 0.26, 0.9), w * 1.6)
				var c: Vector2 = Units.to_px(Units.vec2((b as Dictionary).get("pos")))
				draw_circle(c, 7.0 / _zoom(), Color(0.2, 0.22, 0.26))
				draw_circle(c, 4.0 / _zoom(), Color(0.75, 0.77, 0.8))
		_draw_sel(view.hover, Color(UiTheme.INK, 0.6), w)
		_draw_sel(view.selection, UiTheme.INK, w * 3.4)
		_draw_sel(view.selection, UiTheme.GOLD, w * 1.8)
		if view.ghost.has("block"):
			_outline(EditorModel.outline_m(view.ghost["block"]), Color(UiTheme.INK, 0.7), w)
		if view.show_points:
			_draw_points(w)

	func _draw_sel(sel: Dictionary, col: Color, width: float) -> void:
		var model: EditorModel = view.model
		match str(sel.get("kind", "")):
			"block":
				if int(sel["i"]) < model.blocks().size():
					_outline(EditorModel.outline_m(model.blocks()[int(sel["i"])]), col, width)
			"enemy":
				if int(sel["i"]) < model.enemies().size():
					var r: Rect2 = _person_rect(model.enemies()[int(sel["i"])])
					draw_rect(r, col, false, width)

	func _draw_points(w: float) -> void:
		var z: float = _zoom()
		var terrain: Array = view.model.doc.get("terrain", [])
		for i: int in terrain.size():
			var pts: Array = (terrain[i] as Dictionary).get("points", [])
			var line := PackedVector2Array()
			for p: Variant in pts:
				line.append(Units.to_px(Units.vec2(p)))
			if line.size() >= 2:
				draw_polyline(line, Color(UiTheme.PAPER, 0.8), w, true)
			for j: int in pts.size():
				var c: Vector2 = Units.to_px(Units.vec2(pts[j]))
				var on: bool = (
					str(view.selection.get("kind", "")) == "point"
					and int(view.selection.get("i", -1)) == i
					and int(view.selection.get("j", -1)) == j
				)
				draw_circle(c, 11.0 / z, UiTheme.INK)
				draw_circle(c, 8.0 / z, UiTheme.ACCENT if on else UiTheme.PAPER)
