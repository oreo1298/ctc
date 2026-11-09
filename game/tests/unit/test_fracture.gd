# SPDX-FileCopyrightText: 2026 Siegefall contributors
# SPDX-License-Identifier: MIT
extends GutTest
## Runtime Voronoi fracture: pieces must be convex (ConvexPolygonShape2D),
## cover the block (no lost or duplicated mass) and be reproducible.


func _poly() -> PackedVector2Array:
	return ShapeGeometry.polygon_for({"shape": "rect", "size": Vector2(2.0, 1.0)})


func _cells(seed_value: int, aniso: Vector2 = Vector2.ONE) -> Array[PackedVector2Array]:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var seeds := Fracture.make_seeds(_poly(), 8, Vector2(30, 10), 0.5, 40.0, rng)
	return Fracture.voronoi_cells(_poly(), seeds, aniso)


func test_cells_are_convex() -> void:
	for s: int in 20:
		for cell: PackedVector2Array in _cells(s, Vector2(0.3, 1.0)):
			assert_true(ShapeGeometry.is_convex(cell), "seed %d produced a concave cell" % s)


func test_area_is_conserved() -> void:
	var total: float = absf(ShapeGeometry.signed_area(_poly()))
	for s: int in 10:
		var sum: float = 0.0
		for cell: PackedVector2Array in _cells(s):
			sum += absf(ShapeGeometry.signed_area(cell))
		assert_almost_eq(sum, total, total * 0.002, "seed %d" % s)


func test_deterministic_for_a_seed() -> void:
	var a := _cells(42)
	var b := _cells(42)
	assert_eq(a.size(), b.size())
	for i: int in a.size():
		assert_eq(a[i], b[i])


func test_no_slivers() -> void:
	for s: int in 20:
		var cells := _cells(s)
		var mean: float = absf(ShapeGeometry.signed_area(_poly())) / cells.size()
		for cell: PackedVector2Array in cells:
			assert_gt(absf(ShapeGeometry.signed_area(cell)), mean * 0.05, "sliver with seed %d" % s)


func test_tear_gives_two_pieces() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var halves := Fracture.tear(_poly(), Vector2.ZERO, rng)
	assert_eq(halves.size(), 2)


func test_half_plane_clip() -> void:
	var sq := PackedVector2Array([Vector2(0, 0), Vector2(2, 0), Vector2(2, 2), Vector2(0, 2)])
	var left := Fracture.clip_half_plane(sq, Vector2(1, 0), Vector2(1, 0))
	assert_almost_eq(absf(ShapeGeometry.signed_area(left)), 2.0, 0.0001)
