# SPDX-FileCopyrightText: 2026 Siegefall contributors
# SPDX-License-Identifier: MIT
class_name ShapeGeometry
extends RefCounted
## Polygons and "bevel meshes" for block shapes.
##
## A bevel mesh splits a convex shape into triangles that each touch exactly
## one edge, and stores per vertex (in COLOR) the outward normal of that edge
## (rg) and the distance to it (b, metres / DIST_RANGE). Distance to a line is
## linear, so after interpolation every fragment knows its exact distance to
## the nearest edge and that edge's normal. block.gdshader turns this into ink
## outlines and normal-mapped bevels without any per-block texture.
##
## All outputs are in local pixel space (y down), centred on the block.

const DIST_RANGE: float = 1.5
const CIRCLE_SEGMENTS: int = 28


## Local outline polygon (px, y down, CCW on screen) for a normalised spec.
static func polygon_for(spec: Dictionary) -> PackedVector2Array:
	var shape: String = spec.get("shape", "rect")
	var size: Vector2 = spec.get("size", Vector2.ONE) * Units.PX_PER_M
	var hw: float = size.x * 0.5
	var hh: float = size.y * 0.5
	match shape:
		"rect":
			return PackedVector2Array(
				[Vector2(-hw, -hh), Vector2(hw, -hh), Vector2(hw, hh), Vector2(-hw, hh)]
			)
		"tri":
			return PackedVector2Array([Vector2(0.0, -hh), Vector2(hw, hh), Vector2(-hw, hh)])
		"wedge":
			return PackedVector2Array([Vector2(-hw, -hh), Vector2(hw, hh), Vector2(-hw, hh)])
		"circle":
			var r: float = float(spec.get("radius", 0.5)) * Units.PX_PER_M
			var pts := PackedVector2Array()
			for i: int in CIRCLE_SEGMENTS:
				pts.append(Vector2.from_angle(TAU * i / CIRCLE_SEGMENTS) * r)
			return pts
		"poly":
			var src: PackedVector2Array = spec.get("points", PackedVector2Array())
			var pts := PackedVector2Array()
			for p: Vector2 in src:
				pts.append(Units.to_px(p))
			if signed_area(pts) < 0.0:
				pts.reverse()
			return pts
	return PackedVector2Array()


## Area in m² of a normalised spec.
static func area_m2(spec: Dictionary) -> float:
	if spec.get("shape", "") == "circle":
		var r: float = float(spec.get("radius", 0.5))
		return PI * r * r
	return absf(signed_area(polygon_for(spec))) / (Units.PX_PER_M * Units.PX_PER_M)


## Shoelace area; positive for clockwise-in-y-up == counter-clockwise on a
## y-down screen... i.e. positive for the winding polygon_for() produces.
static func signed_area(pts: PackedVector2Array) -> float:
	var a: float = 0.0
	for i: int in pts.size():
		var p: Vector2 = pts[i]
		var q: Vector2 = pts[(i + 1) % pts.size()]
		a += p.x * q.y - q.x * p.y
	return a * 0.5


static func is_convex(pts: PackedVector2Array) -> bool:
	if pts.size() < 3:
		return false
	var sign: int = 0
	for i: int in pts.size():
		var a: Vector2 = pts[i]
		var b: Vector2 = pts[(i + 1) % pts.size()]
		var c: Vector2 = pts[(i + 2) % pts.size()]
		var cross: float = (b - a).cross(c - b)
		if absf(cross) < 1e-9:
			continue
		var s: int = 1 if cross > 0.0 else -1
		if sign == 0:
			sign = s
		elif s != sign:
			return false
	return sign != 0


## Collision shape for a spec.
static func collision_shape_for(spec: Dictionary) -> Shape2D:
	match str(spec.get("shape", "rect")):
		"rect":
			var r := RectangleShape2D.new()
			r.size = (spec.get("size", Vector2.ONE) as Vector2) * Units.PX_PER_M
			return r
		"circle":
			var c := CircleShape2D.new()
			c.radius = float(spec.get("radius", 0.5)) * Units.PX_PER_M
			return c
	var poly := ConvexPolygonShape2D.new()
	poly.points = polygon_for(spec)
	return poly


## Bevel mesh for a spec. `uv_offset` shifts the pattern (per-block variety);
## the pattern's x axis follows the longer side so wood grain runs along beams.
static func bevel_mesh_for(spec: Dictionary, uv_offset: Vector2 = Vector2.ZERO) -> ArrayMesh:
	var shape: String = spec.get("shape", "rect")
	var verts := PackedVector2Array()
	var cols := PackedColorArray()
	if shape == "rect":
		_rect_skeleton((spec.get("size", Vector2.ONE) as Vector2) * Units.PX_PER_M, verts, cols)
	elif shape == "circle":
		_circle_fan(float(spec.get("radius", 0.5)) * Units.PX_PER_M, verts, cols)
	else:
		_convex_fan(polygon_for(spec), verts, cols)
	var size: Vector2 = spec.get("size", Vector2.ONE)
	var vertical: bool = shape == "rect" and size.y > size.x
	var uvs := PackedVector2Array()
	for v: Vector2 in verts:
		var m: Vector2 = Vector2(v.x, -v.y) / Units.PX_PER_M
		if vertical:
			m = Vector2(m.y, -m.x)
		uvs.append(m + uv_offset)
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_COLOR] = cols
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


static func _edge_color(normal: Vector2, dist_px: float) -> Color:
	return Color(
		normal.x * 0.5 + 0.5,
		normal.y * 0.5 + 0.5,
		clampf(dist_px / Units.PX_PER_M / DIST_RANGE, 0.0, 1.0),
		1.0
	)


static func _tri(
	verts: PackedVector2Array,
	cols: PackedColorArray,
	a: Vector2,
	b: Vector2,
	c: Vector2,
	ca: Color,
	cb: Color,
	cc: Color
) -> void:
	verts.append_array([a, b, c])
	cols.append_array([ca, cb, cc])


## Exact straight skeleton of a rectangle: two trapezoids and two triangles.
static func _rect_skeleton(
	size: Vector2, verts: PackedVector2Array, cols: PackedColorArray
) -> void:
	var hw: float = size.x * 0.5
	var hh: float = size.y * 0.5
	var d: float = minf(hw, hh)
	var tl := Vector2(-hw, -hh)
	var tr := Vector2(hw, -hh)
	var br := Vector2(hw, hh)
	var bl := Vector2(-hw, hh)
	var i0: Vector2
	var i1: Vector2
	if hw >= hh:
		i0 = Vector2(-hw + d, 0.0)
		i1 = Vector2(hw - d, 0.0)
	else:
		i0 = Vector2(0.0, -hh + d)
		i1 = Vector2(0.0, hh - d)
	# For a wide rect i0 is the left inner point; for a tall rect it is the top.
	var faces: Array = [
		[Vector2.UP, tl, tr, i1 if hw >= hh else i0, i0],
		[Vector2.DOWN, br, bl, i0 if hw >= hh else i1, i1],
		[Vector2.LEFT, bl, tl, i0, i0 if hw >= hh else i1],
		[Vector2.RIGHT, tr, br, i1, i1 if hw >= hh else i0],
	]
	for f: Array in faces:
		var n: Vector2 = f[0]
		var a: Vector2 = f[1]
		var b: Vector2 = f[2]
		var c: Vector2 = f[3]
		var e: Vector2 = f[4]
		var c0: Color = _edge_color(n, 0.0)
		var cd: Color = _edge_color(n, d)
		_tri(verts, cols, a, b, c, c0, c0, cd)
		if not c.is_equal_approx(e):
			_tri(verts, cols, a, c, e, c0, cd, cd)


static func _circle_fan(r: float, verts: PackedVector2Array, cols: PackedColorArray) -> void:
	for i: int in CIRCLE_SEGMENTS:
		var a0: float = TAU * i / CIRCLE_SEGMENTS
		var a1: float = TAU * (i + 1) / CIRCLE_SEGMENTS
		var n0: Vector2 = Vector2.from_angle(a0)
		var n1: Vector2 = Vector2.from_angle(a1)
		var nm: Vector2 = Vector2.from_angle((a0 + a1) * 0.5)
		_tri(
			verts,
			cols,
			Vector2.ZERO,
			n0 * r,
			n1 * r,
			_edge_color(nm, r),
			_edge_color(n0, 0.0),
			_edge_color(n1, 0.0)
		)


## Fan from an interior point (the incentre for triangles). Exact near edges,
## which is all the outline and bevel need.
static func _convex_fan(
	pts: PackedVector2Array, verts: PackedVector2Array, cols: PackedColorArray
) -> void:
	var n: int = pts.size()
	var c: Vector2 = _interior_point(pts)
	for i: int in n:
		var a: Vector2 = pts[i]
		var b: Vector2 = pts[(i + 1) % n]
		var edge: Vector2 = (b - a).normalized()
		var normal := Vector2(edge.y, -edge.x)
		# Make sure it points away from the interior point.
		if normal.dot(a - c) < 0.0:
			normal = -normal
		var dist: float = absf((c - a).dot(normal))
		_tri(
			verts,
			cols,
			c,
			a,
			b,
			_edge_color(normal, dist),
			_edge_color(normal, 0.0),
			_edge_color(normal, 0.0)
		)


static func _interior_point(pts: PackedVector2Array) -> Vector2:
	if pts.size() == 3:
		var a: Vector2 = pts[0]
		var b: Vector2 = pts[1]
		var c: Vector2 = pts[2]
		var la: float = b.distance_to(c)
		var lb: float = c.distance_to(a)
		var lc: float = a.distance_to(b)
		var s: float = la + lb + lc
		if s > 0.0:
			return (a * la + b * lb + c * lc) / s
	var sum := Vector2.ZERO
	for p: Vector2 in pts:
		sum += p
	return sum / maxf(1.0, pts.size())
