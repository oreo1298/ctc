# SPDX-FileCopyrightText: 2026 Siegefall contributors
# SPDX-License-Identifier: MIT
extends GutTest


func test_areas() -> void:
	assert_almost_eq(ShapeGeometry.area_m2({"shape": "rect", "size": Vector2(2, 0.5)}), 1.0, 0.0001)
	assert_almost_eq(ShapeGeometry.area_m2({"shape": "tri", "size": Vector2(2, 1)}), 1.0, 0.0001)
	assert_almost_eq(ShapeGeometry.area_m2({"shape": "circle", "radius": 1.0}), PI, 0.0001)


func test_convexity() -> void:
	assert_true(
		ShapeGeometry.is_convex(PackedVector2Array([Vector2(0, 0), Vector2(1, 0), Vector2(0, 1)]))
	)
	var concave := PackedVector2Array(
		[Vector2(0, 0), Vector2(2, 0), Vector2(1, 0.3), Vector2(2, 2), Vector2(0, 2)]
	)
	assert_false(ShapeGeometry.is_convex(concave))


func test_rect_skeleton_encodes_exact_inner_distance() -> void:
	var mesh: ArrayMesh = ShapeGeometry.bevel_mesh_for({"shape": "rect", "size": Vector2(3.8, 0.3)})
	var arrays: Array = mesh.surface_get_arrays(0)
	var cols: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
	var max_d: float = 0.0
	for c: Color in cols:
		max_d = maxf(max_d, c.b * ShapeGeometry.DIST_RANGE)
	assert_almost_eq(max_d, 0.15, 0.004, "inner distance = half the thickness (8-bit encoded)")
	assert_eq(cols.size() % 3, 0, "triangles")


func test_polygon_winding_consistent() -> void:
	for shape: String in ["rect", "tri", "wedge"]:
		var pts: PackedVector2Array = ShapeGeometry.polygon_for(
			{"shape": shape, "size": Vector2(1, 1)}
		)
		assert_gt(ShapeGeometry.signed_area(pts), 0.0, shape)
