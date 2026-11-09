# SPDX-FileCopyrightText: 2026 Siegefall contributors
# SPDX-License-Identifier: MIT
class_name Fracture
extends RefCounted
## Voronoi fracture of convex polygons (docs/DESIGN.md §8.5).
##
## Cells are computed by clipping the source polygon with the bisector
## half-planes between seed points (Sutherland-Hodgman), which keeps every
## cell convex, so pieces can use ConvexPolygonShape2D directly. Seeds can be
## biased towards the impact point (smaller pieces where it was hit) and the
## metric can be anisotropic (wood splinters along its grain).
##
## Everything is deterministic for a given RandomNumberGenerator seed.

const MIN_CELL_AREA_PX: float = 9.0


## Seeds for `poly` (px, local), `count` of them, `bias` (0..1) of which
## cluster around `impact` (local px) within `spread` px.
static func make_seeds(
	poly: PackedVector2Array,
	count: int,
	impact: Vector2,
	bias: float,
	spread: float,
	rng: RandomNumberGenerator
) -> PackedVector2Array:
	var bb: Rect2 = _bounds(poly)
	var seeds := PackedVector2Array()
	var near: int = roundi(count * clampf(bias, 0.0, 1.0))
	# Minimum spacing (a loose Poisson-disk) keeps out sliver cells; it is
	# relaxed if the polygon is too cramped to fit every seed.
	var area: float = absf(ShapeGeometry.signed_area(poly))
	var min_d: float = sqrt(area / maxf(1.0, count)) * 0.55
	var tries: int = 0
	while seeds.size() < count and tries < count * 60:
		tries += 1
		if tries % (count * 15) == 0:
			min_d *= 0.7
		var p: Vector2
		if seeds.size() < near:
			var a: float = rng.randf() * TAU
			var r: float = sqrt(rng.randf()) * spread
			p = impact + Vector2.from_angle(a) * r
		else:
			p = Vector2(
				rng.randf_range(bb.position.x, bb.end.x), rng.randf_range(bb.position.y, bb.end.y)
			)
		if not Geometry2D.is_point_in_polygon(p, poly):
			continue
		var ok: bool = true
		for q: Vector2 in seeds:
			if p.distance_to(q) < min_d:
				ok = false
				break
		if ok:
			seeds.append(p)
	return seeds


## Voronoi cells of `poly` for `seeds` (both in the same space). `aniso`
## scales the metric: Vector2(0.35, 1) makes cells ~3x longer along x.
static func voronoi_cells(
	poly: PackedVector2Array, seeds: PackedVector2Array, aniso: Vector2 = Vector2.ONE
) -> Array[PackedVector2Array]:
	var inv := Vector2(1.0 / aniso.x, 1.0 / aniso.y)
	var tpoly := PackedVector2Array()
	for p: Vector2 in poly:
		tpoly.append(p * aniso)
	var tseeds := PackedVector2Array()
	for s: Vector2 in seeds:
		tseeds.append(s * aniso)
	var cells: Array[PackedVector2Array] = []
	for i: int in tseeds.size():
		var cell: PackedVector2Array = tpoly
		var si: Vector2 = tseeds[i]
		for j: int in tseeds.size():
			if i == j:
				continue
			var sj: Vector2 = tseeds[j]
			cell = clip_half_plane(cell, (si + sj) * 0.5, sj - si)
			if cell.size() < 3:
				break
		if cell.size() < 3:
			continue
		var out := PackedVector2Array()
		for p: Vector2 in cell:
			out.append(p * inv)
		if absf(ShapeGeometry.signed_area(out)) >= MIN_CELL_AREA_PX:
			cells.append(out)
	return cells


## Keep the part of `pts` where (p - m) . n <= 0.
static func clip_half_plane(pts: PackedVector2Array, m: Vector2, n: Vector2) -> PackedVector2Array:
	var out := PackedVector2Array()
	var count: int = pts.size()
	for k: int in count:
		var a: Vector2 = pts[k]
		var b: Vector2 = pts[(k + 1) % count]
		var da: float = (a - m).dot(n)
		var db: float = (b - m).dot(n)
		if da <= 0.0:
			out.append(a)
		if (da <= 0.0) != (db <= 0.0):
			out.append(a.lerp(b, da / (da - db)))
	return out


## Same cells via Geometry2D.intersect_polygons (benchmark comparison only).
static func voronoi_cells_geometry2d(
	poly: PackedVector2Array, seeds: PackedVector2Array
) -> Array[PackedVector2Array]:
	var cells: Array[PackedVector2Array] = []
	var big: float = 100000.0
	for i: int in seeds.size():
		var cell: PackedVector2Array = poly
		for j: int in seeds.size():
			if i == j:
				continue
			var m: Vector2 = (seeds[i] + seeds[j]) * 0.5
			var n: Vector2 = (seeds[j] - seeds[i]).normalized()
			var t := Vector2(-n.y, n.x)
			var half := PackedVector2Array(
				[m + t * big, m + t * big - n * big, m - t * big - n * big, m - t * big]
			)
			var res: Array[PackedVector2Array] = Geometry2D.intersect_polygons(cell, half)
			if res.is_empty():
				cell = PackedVector2Array()
				break
			cell = res[0]
		if cell.size() >= 3:
			cells.append(cell)
	return cells


## Split along a jagged line through `impact` (cloth tearing): two pieces.
static func tear(
	poly: PackedVector2Array, impact: Vector2, rng: RandomNumberGenerator
) -> Array[PackedVector2Array]:
	# A roughly vertical tear (horizontal normal): banners and drapes split
	# into two strips that flop apart instead of restacking.
	var angle: float = rng.randf_range(-0.4, 0.4)
	var n: Vector2 = Vector2.from_angle(angle)
	var a: PackedVector2Array = clip_half_plane(poly, impact, n)
	var b: PackedVector2Array = clip_half_plane(poly, impact, -n)
	var out: Array[PackedVector2Array] = []
	for c: PackedVector2Array in [a, b]:
		if c.size() >= 3 and absf(ShapeGeometry.signed_area(c)) >= MIN_CELL_AREA_PX:
			out.append(c)
	return out


static func centroid(pts: PackedVector2Array) -> Vector2:
	var a: float = 0.0
	var c := Vector2.ZERO
	for i: int in pts.size():
		var p: Vector2 = pts[i]
		var q: Vector2 = pts[(i + 1) % pts.size()]
		var cr: float = p.cross(q)
		a += cr
		c += (p + q) * cr
	if absf(a) < 1e-6:
		var s := Vector2.ZERO
		for p: Vector2 in pts:
			s += p
		return s / maxf(1.0, pts.size())
	return c / (3.0 * a)


static func _bounds(poly: PackedVector2Array) -> Rect2:
	var r := Rect2(poly[0], Vector2.ZERO)
	for p: Vector2 in poly:
		r = r.expand(p)
	return r
