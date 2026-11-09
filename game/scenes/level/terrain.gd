# SPDX-FileCopyrightText: 2026 Siegefall contributors
# SPDX-License-Identifier: MIT
class_name Terrain
extends StaticBody2D
## Static ground built from a level's terrain polylines (metres, y up).
## Visual: one strip mesh per piece whose UV.y is depth below the surface.

const SHADER: Shader = preload("res://shaders/terrain.gdshader")
const DEPTH_BELOW_KILL: float = 8.0


func build(pieces: Array[Dictionary], kill_y: float, palette: Dictionary) -> void:
	collision_layer = Block.Layer.WORLD
	collision_mask = 0
	var pm := PhysicsMaterial.new()
	pm.friction = 0.9
	pm.bounce = 0.0
	physics_material_override = pm
	var mat := ShaderMaterial.new()
	mat.shader = SHADER
	mat.set_shader_parameter(
		"top_color", Units.color(palette.get("ground_top"), Color(0.55, 0.76, 0.4))
	)
	mat.set_shader_parameter(
		"body_color", Units.color(palette.get("ground"), Color(0.43, 0.62, 0.3))
	)
	mat.set_shader_parameter(
		"deep_color", Units.color(palette.get("ground_deep"), Color(0.3, 0.43, 0.23))
	)
	mat.set_shader_parameter("ink", Units.color(palette.get("ink"), Color(0.23, 0.18, 0.15)))
	var bottom_m: float = kill_y - DEPTH_BELOW_KILL
	for piece: Dictionary in pieces:
		var top: PackedVector2Array = piece.get("points", PackedVector2Array())
		if top.size() < 2:
			continue
		# Collision: the closed polygon, decomposed into convex parts by Godot.
		var poly := PackedVector2Array()
		for p: Vector2 in top:
			poly.append(Units.to_px(p))
		poly.append(Units.to_px(Vector2(top[top.size() - 1].x, bottom_m)))
		poly.append(Units.to_px(Vector2(top[0].x, bottom_m)))
		var cp := CollisionPolygon2D.new()
		cp.build_mode = CollisionPolygon2D.BUILD_SOLIDS
		cp.polygon = poly
		add_child(cp)
		var mi := MeshInstance2D.new()
		mi.mesh = _strip_mesh(top, bottom_m)
		var styles: Array[String] = ["grass", "sand", "snow", "rock"]
		var piece_mat := mat.duplicate() as ShaderMaterial
		piece_mat.set_shader_parameter(
			"style", maxi(0, styles.find(str(piece.get("style", "grass"))))
		)
		mi.material = piece_mat
		mi.z_index = -1
		add_child(mi)
		var occ := LightOccluder2D.new()
		var op := OccluderPolygon2D.new()
		op.polygon = poly
		occ.occluder = op
		add_child(occ)


static func _strip_mesh(top: PackedVector2Array, bottom_m: float) -> ArrayMesh:
	var verts := PackedVector2Array()
	var uvs := PackedVector2Array()
	for i: int in top.size() - 1:
		var a: Vector2 = top[i]
		var b: Vector2 = top[i + 1]
		var a2 := Vector2(a.x, bottom_m)
		var b2 := Vector2(b.x, bottom_m)
		var quad: Array[Vector2] = [a, b, b2, a, b2, a2]
		var depth: Array[float] = [0.0, 0.0, b.y - bottom_m, 0.0, b.y - bottom_m, a.y - bottom_m]
		for k: int in 6:
			verts.append(Units.to_px(quad[k]))
			uvs.append(Vector2(quad[k].x, depth[k]))
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


## Surface height (metres) at x, or NAN if x is outside every piece.
static func height_at(pieces: Array[Dictionary], x: float) -> float:
	for piece: Dictionary in pieces:
		var top: PackedVector2Array = piece.get("points", PackedVector2Array())
		for i: int in top.size() - 1:
			if x >= top[i].x and x <= top[i + 1].x:
				var t: float = (x - top[i].x) / maxf(0.0001, top[i + 1].x - top[i].x)
				return lerpf(top[i].y, top[i + 1].y, t)
	return NAN
