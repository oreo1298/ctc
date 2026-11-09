# SPDX-FileCopyrightText: 2026 Siegefall contributors
# SPDX-License-Identifier: MIT
extends Node
## Fracture benchmark: runtime Voronoi (two clipping implementations) vs.
## pre-broken shards, plus the cost of turning cells into physics pieces.
## Run: scripts/godot.sh --headless --path game res://tools/fracture_bench.tscn

const RUNS: int = 400

var _cases: Array[Dictionary] = [
	{
		"name": "wood plank 3.8x0.3",
		"size": Vector2(3.8, 0.3),
		"cells": 7,
		"aniso": Vector2(0.3, 1.0)
	},
	{"name": "stone block 1.2x0.8", "size": Vector2(1.2, 0.8), "cells": 7, "aniso": Vector2.ONE},
	{"name": "glass pane 1x1", "size": Vector2(1.0, 1.0), "cells": 14, "aniso": Vector2.ONE},
	{"name": "big stone 2x2", "size": Vector2(2.0, 2.0), "cells": 10, "aniso": Vector2.ONE},
]


func _ready() -> void:
	var cols: PackedStringArray = [
		"block",
		"cells",
		"runtime clip (µs)",
		"Geometry2D (µs)",
		"pre-broken lookup (µs)",
		"spawn pieces (µs)",
		"min/mean cell area ratio",
	]
	print("| %s |" % " | ".join(cols))
	print("|---|---|---|---|---|---|---|")
	var root := Node2D.new()
	add_child(root)
	for c: Dictionary in _cases:
		_bench(c, root)
	get_tree().quit()


func _bench(c: Dictionary, root: Node2D) -> void:
	var spec: Dictionary = {"shape": "rect", "size": c["size"]}
	var poly: PackedVector2Array = ShapeGeometry.polygon_for(spec)
	var rng := RandomNumberGenerator.new()
	var n: int = int(c["cells"])
	var aniso: Vector2 = c["aniso"]
	var impact: Vector2 = poly[0].lerp(poly[2], 0.3)
	var spread: float = (c["size"] as Vector2).length() * 25.0

	var t0: int = Time.get_ticks_usec()
	var cells: Array[PackedVector2Array] = []
	var ratio_min: float = 1.0
	var ratio_sum: float = 0.0
	for i: int in RUNS:
		rng.seed = i
		var seeds := Fracture.make_seeds(poly, n, impact, 0.5, spread, rng)
		cells = Fracture.voronoi_cells(poly, seeds, aniso)
		var areas: Array[float] = []
		for cell: PackedVector2Array in cells:
			areas.append(absf(ShapeGeometry.signed_area(cell)))
		var mean: float = 0.0
		for a: float in areas:
			mean += a
		mean /= maxf(1.0, areas.size())
		var mn: float = areas.min() if not areas.is_empty() else 0.0
		ratio_min = minf(ratio_min, mn / maxf(mean, 1.0))
		ratio_sum += mn / maxf(mean, 1.0)
	var t_clip: float = (Time.get_ticks_usec() - t0) / float(RUNS)

	t0 = Time.get_ticks_usec()
	for i: int in RUNS:
		rng.seed = i
		var seeds := Fracture.make_seeds(poly, n, impact, 0.5, spread, rng)
		Fracture.voronoi_cells_geometry2d(poly, seeds)
	var t_geo: float = (Time.get_ticks_usec() - t0) / float(RUNS)

	# Pre-broken: cells computed once (uniform seeds), then copied/transformed.
	rng.seed = 7
	var cached: Array[PackedVector2Array] = Fracture.voronoi_cells(
		poly, Fracture.make_seeds(poly, n, Vector2.ZERO, 0.0, 0.0, rng), aniso
	)
	var xf := Transform2D(0.3, Vector2(10, 20))
	t0 = Time.get_ticks_usec()
	for i: int in RUNS:
		var out: Array[PackedVector2Array] = []
		for cell: PackedVector2Array in cached:
			out.append(xf * cell)
	var t_pre: float = (Time.get_ticks_usec() - t0) / float(RUNS)

	# Spawning pieces (same for both approaches).
	var spawn_runs: int = 40
	t0 = Time.get_ticks_usec()
	var wood: Dictionary = {
		"density": 600,
		"hp_per_m2": 100,
		"friction": 0.6,
		"bounce": 0.1,
		"pattern": "wood",
		"colors": {"base": "#b9824f", "dark": "#7c4f2c", "light": "#e0b07a"},
	}
	for i: int in spawn_runs:
		for cell: PackedVector2Array in cells:
			var b := Block.new()
			var pts := PackedVector2Array()
			var cen: Vector2 = Fracture.centroid(cell)
			for p: Vector2 in cell:
				pts.append(Units.to_m(p - cen) * Vector2(1, 1))
			b.setup(
				{
					"shape": "poly",
					"material": "wood",
					"pos": Vector2.ZERO,
					"rot": 0.0,
					"points": pts
				},
				wood,
				i
			)
			root.add_child(b)
			b.free()
	var t_spawn: float = (Time.get_ticks_usec() - t0) / float(spawn_runs)
	print(
		(
			"| %s | %d | %.0f | %.0f | %.1f | %.0f | %.2f / %.2f |"
			% [c["name"], cells.size(), t_clip, t_geo, t_pre, t_spawn, ratio_min, ratio_sum / RUNS]
		)
	)
