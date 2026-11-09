# SPDX-FileCopyrightText: 2026 Siegefall contributors
# SPDX-License-Identifier: MIT
class_name Backdrop
extends Node
## Storybook backdrop: a painted sky (screen space) and procedural parallax
## hill layers with trees, tinted by the realm palette and time of day.
## Lives in its own CanvasLayers so world lighting never touches it.

const SKY_SHADER: Shader = preload("res://shaders/sky.gdshader")
const HILL_SHADER: Shader = preload("res://shaders/hill.gdshader")

var _sky: ColorRect
var _sky_mat: ShaderMaterial
var _layers: Array[Node2D] = []
var _factors: Array[float] = []
var _time: float = 0.0
var _sun_elev: float = 30.0


func build(
	palette: Dictionary,
	grade: Dictionary,
	backdrop: Dictionary,
	world_right_m: float,
	seed_value: int
) -> void:
	var sky_layer := CanvasLayer.new()
	sky_layer.layer = -100
	add_child(sky_layer)
	_sky = ColorRect.new()
	_sky.set_anchors_preset(Control.PRESET_FULL_RECT)
	_sky.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_sky_mat = ShaderMaterial.new()
	_sky_mat.shader = SKY_SHADER
	_sky.material = _sky_mat
	sky_layer.add_child(_sky)
	for k: String in ["sky_top", "sky_horizon", "haze", "sun_color"]:
		_sky_mat.set_shader_parameter(k, Units.color(grade.get(k), Color.WHITE))
	_sky_mat.set_shader_parameter("cloud_color", Units.color(grade.get("cloud"), Color.WHITE))
	_sky_mat.set_shader_parameter("stars", float(grade.get("stars", 0.0)))
	_sky_mat.set_shader_parameter("moon", bool(grade.get("moon", false)))
	_sky_mat.set_shader_parameter("octaves_hint", 4 if _high_quality() else 3)
	_sun_elev = float(grade.get("sun_angle_deg", 30.0))

	var hills_layer := CanvasLayer.new()
	hills_layer.layer = -90
	add_child(hills_layer)
	var haze: Color = Units.color(grade.get("haze"), Color(0.85, 0.9, 0.92))
	var sky_top: Color = Units.color(grade.get("sky_top"), Color(0.47, 0.71, 0.88))
	# Distance tint: a blend of sky and horizon haze reads as cool air on
	# distant ridges instead of a muddy wash of the horizon colour.
	var air: Color = sky_top.lerp(haze, 0.5)
	var sun: Color = Units.color(grade.get("sun_color"), Color.WHITE)
	var n: int = clampi(int(backdrop.get("layers", 4)), 1, 6)
	if not _high_quality():
		n = mini(n, 3)
	var props: String = str(backdrop.get("props", "trees"))
	for i: int in n:
		# depth: 1 = farthest layer, 0 = nearest.
		var depth: float = 1.0 - float(i) / float(maxi(1, n - 1))
		var f: float = lerpf(0.12, 0.62, 1.0 - depth)
		var key: String = "far" if depth > 0.66 else ("mid" if depth > 0.2 else "near")
		var pal: Color = Units.color(palette.get(key), Color(0.5, 0.65, 0.5))
		var col: Color = pal.lerp(air, pow(depth, 1.5) * 0.5)
		var layer := Node2D.new()
		hills_layer.add_child(layer)
		_layers.append(layer)
		_factors.append(f)
		var width: float = (world_right_m * 100.0 + 9000.0) * f + 8000.0
		var amp: float = lerpf(120.0, 340.0, depth) * float(backdrop.get("roughness", 1.0))
		var ridge: float = -lerpf(70.0, 170.0, depth)
		var mat := ShaderMaterial.new()
		mat.shader = HILL_SHADER
		mat.set_shader_parameter("color", col)
		mat.set_shader_parameter("haze", haze)
		mat.set_shader_parameter("rim", sun)
		mat.set_shader_parameter("haze_amount", depth * 0.15)
		mat.set_shader_parameter("rim_amount", 0.14 + (1.0 - depth) * 0.12)
		var heights := _ridge(width, amp, ridge, seed_value + i * 101, 0.0011 / maxf(depth, 0.35))
		layer.add_child(_hill_polygon(heights, width, mat))
		if props == "trees" and i >= n - 2:
			var tree_col: Color = pal.darkened(0.28).lerp(air, pow(depth, 1.5) * 0.4)
			_add_trees(
				layer,
				heights,
				width,
				mat,
				tree_col,
				seed_value + i * 7,
				lerpf(0.55, 1.0, 1.0 - depth),
				i == n - 1
			)


func _high_quality() -> bool:
	return (
		RenderingServer.get_current_rendering_method() != "gl_compatibility"
		or Settings.quality == "high"
	)


## Ridge heights sampled every 40 layer-px from x = -4000.
static func _ridge(
	width: float, amp: float, ridge: float, s: int, freq: float
) -> PackedFloat32Array:
	var noise := FastNoiseLite.new()
	noise.seed = s
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = freq
	noise.fractal_octaves = 3
	var out := PackedFloat32Array()
	var count: int = int(width / 40.0) + 2
	for k: int in count:
		var x: float = -4000.0 + k * 40.0
		out.append(ridge - (noise.get_noise_1d(x) * 0.5 + 0.5) * amp)
	return out


static func _hill_polygon(
	heights: PackedFloat32Array, _width: float, mat: ShaderMaterial
) -> MeshInstance2D:
	var verts := PackedVector2Array()
	var uvs := PackedVector2Array()
	var bottom: float = 2600.0
	for k: int in heights.size() - 1:
		var x0: float = -4000.0 + k * 40.0
		var x1: float = x0 + 40.0
		var a := Vector2(x0, heights[k])
		var b := Vector2(x1, heights[k + 1])
		var quad: Array[Vector2] = [
			a, b, Vector2(x1, bottom), a, Vector2(x1, bottom), Vector2(x0, bottom)
		]
		var dep: Array[float] = [0.0, 0.0, bottom - b.y, 0.0, bottom - b.y, bottom - a.y]
		for q: int in 6:
			verts.append(quad[q])
			uvs.append(Vector2(quad[q].x / 1000.0, dep[q] / 100.0))
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var mi := MeshInstance2D.new()
	mi.mesh = mesh
	mi.material = mat
	return mi


## Chunky storybook trees. Far layers get clustered canopies that melt into
## the ridge (a tree line); the nearest layer gets a few distinct trees.
static func _add_trees(
	layer: Node2D,
	heights: PackedFloat32Array,
	width: float,
	mat: ShaderMaterial,
	col: Color,
	s: int,
	size: float,
	nearest: bool
) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = s
	var tree_mat := mat.duplicate() as ShaderMaterial
	tree_mat.set_shader_parameter("color", col)
	tree_mat.set_shader_parameter("rim_amount", 0.4)
	tree_mat.set_shader_parameter("haze_amount", 0.0)
	var x: float = -3800.0 + rng.randf_range(0.0, 300.0)
	while x < width - 4200.0:
		var cluster: int = rng.randi_range(1, 2 if nearest else 5)
		for c: int in cluster:
			var tx: float = x + c * rng.randf_range(50.0, 80.0) * size
			var k: int = clampi(int((tx + 4000.0) / 40.0), 0, heights.size() - 1)
			var gy: float = heights[k] + 18.0
			var r: float = rng.randf_range(50.0, 85.0) * size
			var trunk_h: float = (rng.randf_range(40.0, 70.0) if nearest else 10.0) * size
			if nearest:
				var trunk := Polygon2D.new()
				trunk.polygon = PackedVector2Array(
					[
						Vector2(tx - 9, gy + 10),
						Vector2(tx + 9, gy + 10),
						Vector2(tx + 6, gy - trunk_h - r * 0.5),
						Vector2(tx - 6, gy - trunk_h - r * 0.5)
					]
				)
				trunk.color = col.darkened(0.45)
				layer.add_child(trunk)
			var cy: float = gy - trunk_h - r * 0.75
			var pts := PackedVector2Array()
			for a: int in 20:
				var ang: float = TAU * a / 20.0
				var wob: float = 1.0 + 0.07 * sin(ang * 4.0 + float(s + c))
				pts.append(Vector2(tx, cy) + Vector2(cos(ang) * 0.92, sin(ang)) * r * wob)
			layer.add_child(_canopy_mesh(pts, cy - r, tree_mat))
		x += rng.randf_range(260.0, 900.0) if nearest else rng.randf_range(160.0, 700.0)


## A filled polygon as a mesh whose UV.y is depth below `top_y` (for the
## hill shader's sunlit rim). Polygon2D drops UVs without a texture.
static func _canopy_mesh(
	pts: PackedVector2Array, top_y: float, mat: ShaderMaterial
) -> MeshInstance2D:
	var idx: PackedInt32Array = Geometry2D.triangulate_polygon(pts)
	var verts := PackedVector2Array()
	var uvs := PackedVector2Array()
	for k: int in idx:
		var p: Vector2 = pts[k]
		verts.append(p)
		uvs.append(Vector2(p.x / 1000.0, (p.y - top_y) / 100.0 * 0.6))
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	var mesh := ArrayMesh.new()
	if not verts.is_empty():
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var mi := MeshInstance2D.new()
	mi.mesh = mesh
	mi.material = mat
	return mi


func _process(delta: float) -> void:
	_time += delta
	var cam: Camera2D = get_viewport().get_camera_2d()
	var vp: Vector2 = get_viewport().get_visible_rect().size
	_sky_mat.set_shader_parameter("aspect", vp.x / maxf(vp.y, 1.0))
	_sky_mat.set_shader_parameter("time_s", _time)
	var c := Vector2.ZERO
	var z: float = 1.0
	if cam != null:
		c = cam.get_screen_center_position()
		z = cam.zoom.x
		_sky_mat.set_shader_parameter("cam_offset", c)
	# Sun sits over the trebuchet side of the sky, at its elevation.
	_sky_mat.set_shader_parameter(
		"sun_uv", Vector2(0.2, clampf(0.62 - _sun_elev / 90.0 * 0.5, 0.08, 0.6))
	)
	var ground_screen_y: float = vp.y * 0.5 - c.y * z
	var horizon: float = vp.y * 0.66
	for i: int in _layers.size():
		var f: float = _factors[i]
		var zf: float = lerpf(0.55, z, f)
		var layer: Node2D = _layers[i]
		layer.scale = Vector2(zf, zf)
		layer.position = Vector2(vp.x * 0.5 - c.x * f * zf, lerpf(horizon, ground_screen_y, f))
