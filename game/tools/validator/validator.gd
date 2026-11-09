# SPDX-FileCopyrightText: 2026 Siegefall contributors
# SPDX-License-Identifier: MIT
extends Node
## Level validator bot (docs/DESIGN.md §6.4).
##
##   search: find the fewest-shot winning sequence for every level, with any
##           ammo (gold) and with only the ammo available on first visit
##           (proves the level is beatable when the player reaches it).
##   replay: re-run the stored proofs; fail if any no longer wins.
##
## Every trial loads the level into its own SubViewport + World2D (a fresh
## physics space), so trials match a fresh game launch exactly.
##
## Run (headless, fast):
##   scripts/godot.sh --headless --fixed-fps 60 --path game \
##     res://tools/validator/validator.tscn -- --validate=all --mode=search \
##     --out=/tmp/report.json --no-save --no-slowmo

const LEVEL_SCENE: PackedScene = preload("res://scenes/level/level.tscn")
const PHASE_MIN: float = 0.46
const PHASE_MAX: float = 0.74
const COARSE: float = 0.0075
const ROBUST_DELTA: float = 0.0025
const MAX_SHOTS: int = 8
const TAPS: Dictionary = {
	"none": [-1.0],
	"burst": [0.55, 0.85],
	"detonate": [-1.0, 0.9],
	"snap": [0.6],
	"open": [-1.0, 0.95],
}

var _trials: int = 0
var _model: TrebuchetModel
var _report: Dictionary = {}


func _ready() -> void:
	_model = TrebuchetModel.from_dict(Data.trebuchet)
	var ids: PackedStringArray = PackedStringArray()
	var arg: String = str(Game.cli.get("validate", "all"))
	ids = Data.campaign_levels() if arg == "all" else arg.split(",", false)
	var mode: String = str(Game.cli.get("mode", "replay"))
	if mode == "trial":
		# One scripted trial, e.g. --shots=boulder:0.65,keg:0.6@0.9
		var seq: Array[Dictionary] = []
		for s: String in str(Game.cli.get("shots", "")).split(",", false):
			var d: Dictionary = Level.parse_shot(s)
			seq.append(
				shot(
					str(d["ammo"]) if str(d["ammo"]) != "" else "boulder",
					float(d["phase"]),
					float(d["tap"])
				)
			)
		for i: int in int(str(Game.cli.get("repeat", "1"))):
			print("[validator] trial %s" % JSON.stringify(await trial(ids[0], seq)))
		get_tree().quit(0)
		return
	var failures: int = 0
	for id: String in ids:
		var t0: int = Time.get_ticks_msec()
		_trials = 0
		var entry: Dictionary
		if mode == "stability":
			entry = await _stability(id)
		elif mode == "search":
			entry = await _search_level(id)
		else:
			entry = await _replay_level(id)
		entry["trials"] = _trials
		entry["seconds"] = (Time.get_ticks_msec() - t0) / 1000.0
		_report[id] = entry
		var ok: bool = bool(entry.get("ok", false))
		if not ok:
			failures += 1
		print("[validator] %s %s %s" % [id, "OK" if ok else "FAIL", JSON.stringify(entry)])
	var out: String = str(Game.cli.get("out", ""))
	if not out.is_empty():
		var f := FileAccess.open(out, FileAccess.WRITE)
		f.store_string(JSON.stringify(_report, "  "))
		f.close()
	print("[validator] done: %d level(s), %d failure(s)" % [ids.size(), failures])
	get_tree().quit(1 if failures > 0 else 0)


# ---------------------------------------------------------------- trials ---
func trial(level_id: String, shots: Array[Dictionary]) -> Dictionary:
	_trials += 1
	Game.current_level_id = level_id
	Game.custom_level = {}
	var vp := SubViewport.new()
	vp.world_2d = World2D.new()
	vp.size = Vector2i(1280, 720)
	vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	vp.disable_3d = true
	add_child(vp)
	var lvl: Level = LEVEL_SCENE.instantiate()
	lvl.bot_mode = true
	lvl.bot_shots = shots
	vp.add_child(lvl)
	var result: Dictionary = await lvl.bot_done
	await get_tree().process_frame
	vp.free()
	return result


static func shot(ammo: String, phase: float, tap: float = -1.0) -> Dictionary:
	return {"ammo": ammo, "phase": snappedf(phase, 0.0001), "tap": tap}


## The castle must stand still on its own: a shot that lands next to the
## trebuchet must leave every block whole and every royal untouched.
func _stability(id: String) -> Dictionary:
	# Three harmless shots (~10 s of game time) also catch slow slides on ice.
	var miss: Dictionary = shot("boulder", 0.97)
	var r: Dictionary = await trial(id, [miss, miss, miss])
	# Idle royals tilt a hair; anything real scores far above 1.
	var ok: bool = float(r["score"]) < 1.0 and not bool(r["won"])
	return {"ok": ok, "score": r["score"], "targets_left": r["targets_left"]}


# ---------------------------------------------------------------- replay ---
func _replay_level(id: String) -> Dictionary:
	var lv: LevelData = Data.load_level(id)
	if not lv.is_valid():
		return {"ok": false, "error": "; ".join(lv.errors)}
	var src: Dictionary = lv.source
	var entry: Dictionary = {"ok": true}
	for key: String in ["solution", "solution_basic"]:
		var sol: Variant = src.get(key, [])
		if not sol is Array or (sol as Array).is_empty():
			entry["ok"] = false
			entry[key] = "missing"
			continue
		var shots: Array[Dictionary] = []
		for s: Variant in sol:
			var sd: Dictionary = s
			shots.append(
				shot(
					str(sd.get("ammo", "boulder")),
					float(sd.get("phase", 0.6)),
					float(sd.get("tap", -1.0))
				)
			)
		var r: Dictionary = await trial(id, shots)
		var won: bool = bool(r["won"]) and int(r["shots"]) <= shots.size()
		entry[key] = "wins in %d" % int(r["shots"]) if won else "LOST (%s)" % JSON.stringify(r)
		if not won:
			entry["ok"] = false
	return entry


# ---------------------------------------------------------------- search ---
func _available_ammo(id: String) -> PackedStringArray:
	var order: PackedStringArray = Data.campaign_levels()
	var here: int = order.find(id)
	var out := PackedStringArray()
	for a: Dictionary in Data.ammo:
		var after: Variant = a.get("unlock_after")
		if (
			after == null
			or (here >= 0 and order.find(str(after)) >= 0 and order.find(str(after)) < here)
		):
			out.append(str(a["id"]))
	return out


func _all_ammo() -> PackedStringArray:
	var out := PackedStringArray()
	for a: Dictionary in Data.ammo:
		out.append(str(a["id"]))
	return out


## Phases whose unobstructed arc passes over/into the castle (metres).
func _useful_phases(lv: LevelData, ammo_id: String, step: float) -> PackedFloat32Array:
	var rect := Rect2(Vector2.ZERO, Vector2.ZERO)
	var first: bool = true
	for b: Dictionary in lv.blocks:
		var p: Vector2 = b["pos"]
		rect = Rect2(p, Vector2.ZERO) if first else rect.expand(p)
		first = false
	for e: Dictionary in lv.enemies:
		rect = rect.expand(e["pos"])
	rect = rect.grow(1.5)
	var scale: float = float(Data.ammo_def(ammo_id).get("speed_scale", 1.0))
	var out := PackedFloat32Array()
	var p: float = PHASE_MIN
	while p <= PHASE_MAX + 1e-6:
		var pos: Vector2 = _model.projectile_pos(p) + lv.trebuchet_pos
		var v: Vector2 = _model.launch_velocity(p, scale)
		var hit: bool = false
		for i: int in 240:
			var t: float = i * 0.03
			var q: Vector2 = pos + v * t + Vector2(0.0, -0.5 * Units.GRAVITY_M * t * t)
			if rect.has_point(q):
				hit = true
				break
			var ground: float = Terrain.height_at(lv.terrain, q.x)
			if not is_nan(ground) and q.y < ground - 0.5 and t > 0.3:
				break
		if hit:
			out.append(p)
		p += step
	return out


func _candidates(lv: LevelData, ammo_ids: PackedStringArray, step: float) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for a: String in ammo_ids:
		var taps: Array = TAPS.get(str(Data.ammo_def(a).get("tap_action", "none")), [-1.0])
		for p: float in _useful_phases(lv, a, step):
			for t: Variant in taps:
				out.append(shot(a, p, float(t)))
	return out


## Fewest-shot winning sequence using only `ammo_ids`. Returns
## {"shots": n, "solution": [...], "robust": bool} or {"shots": 0} if none.
func _find(id: String, lv: LevelData, ammo_ids: PackedStringArray) -> Dictionary:
	var prefixes: Array[Dictionary] = [{"shots": [] as Array[Dictionary], "score": 0.0}]
	var depth: int = 0
	while depth < MAX_SHOTS:
		depth += 1
		var step: float = COARSE if depth == 1 else COARSE * 1.5
		var cands: Array[Dictionary] = _candidates(lv, ammo_ids, step)
		var scored: Array[Dictionary] = []
		var beam: int = 1 if depth > 3 else (4 if depth == 2 else 3)
		for pre: Dictionary in prefixes.slice(0, beam):
			var base: Array[Dictionary] = pre["shots"]
			for c: Dictionary in cands:
				var seq: Array[Dictionary] = base.duplicate()
				seq.append(c)
				var r: Dictionary = await trial(id, seq)
				scored.append({"shots": seq, "score": float(r["score"]), "won": bool(r["won"])})
		# Refine around the best near-misses (and winners) with finer phases.
		scored.sort_custom(
			func(a: Dictionary, b: Dictionary) -> bool: return float(a["score"]) > float(b["score"])
		)
		var refined: Array[Dictionary] = []
		for top: Dictionary in scored.slice(0, 6):
			var seq0: Array[Dictionary] = top["shots"]
			var last: Dictionary = seq0[seq0.size() - 1]
			for dp: float in [-0.004, -0.002, 0.002, 0.004]:
				var seq: Array[Dictionary] = seq0.slice(0, seq0.size() - 1)
				seq.append(shot(str(last["ammo"]), float(last["phase"]) + dp, float(last["tap"])))
				var r: Dictionary = await trial(id, seq)
				refined.append({"shots": seq, "score": float(r["score"]), "won": bool(r["won"])})
		scored.append_array(refined)
		scored.sort_custom(
			func(a: Dictionary, b: Dictionary) -> bool: return float(a["score"]) > float(b["score"])
		)
		var winners: Array[Dictionary] = []
		for s: Dictionary in scored:
			if bool(s["won"]):
				winners.append(s)
		if not winners.is_empty():
			for w: Dictionary in winners.slice(0, 6):
				if await _robust(id, w["shots"]):
					return {"shots": depth, "solution": w["shots"], "robust": true}
			return {"shots": depth, "solution": winners[0]["shots"], "robust": false}
		# Keep diverse prefixes: skip near-duplicate phases.
		prefixes.clear()
		for s: Dictionary in scored:
			var dup: bool = false
			for q: Dictionary in prefixes:
				if _similar(q["shots"], s["shots"]):
					dup = true
					break
			if not dup:
				prefixes.append(s)
			if prefixes.size() >= 4:
				break
	return {"shots": 0}


static func _similar(a: Array[Dictionary], b: Array[Dictionary]) -> bool:
	if a.size() != b.size():
		return false
	for i: int in a.size():
		if (
			str(a[i]["ammo"]) != str(b[i]["ammo"])
			or absf(float(a[i]["phase"]) - float(b[i]["phase"])) > 0.006
		):
			return false
	return true


## A solution is robust if nudging its last release a little either way
## still wins: a human can hit it.
func _robust(id: String, seq: Array[Dictionary]) -> bool:
	var last: Dictionary = seq[seq.size() - 1]
	for dp: float in [-ROBUST_DELTA, ROBUST_DELTA]:
		var s: Array[Dictionary] = seq.slice(0, seq.size() - 1)
		s.append(shot(str(last["ammo"]), float(last["phase"]) + dp, float(last["tap"])))
		var r: Dictionary = await trial(id, s)
		if not bool(r["won"]):
			return false
	return true


func _search_level(id: String) -> Dictionary:
	var lv: LevelData = Data.load_level(id)
	if not lv.is_valid():
		return {"ok": false, "error": "; ".join(lv.errors)}
	var basic_ammo: PackedStringArray = _available_ammo(id)
	var best: Dictionary = await _find(id, lv, _all_ammo())
	var basic: Dictionary = best
	var uses_only_basic: bool = int(best.get("shots", 0)) > 0
	for s: Dictionary in best.get("solution", []):
		if not basic_ammo.has(str(s["ammo"])):
			uses_only_basic = false
	if not uses_only_basic:
		basic = await _find(id, lv, basic_ammo)
	if int(basic.get("shots", 0)) == 0:
		return {"ok": false, "error": "no winning sequence with first-visit ammo %s" % [basic_ammo]}
	# Par must be fair to humans: a knife-edge solution (neighbouring
	# releases lose) proves the level is winnable, but par allows one more.
	var best_n: int = int(best["shots"]) if int(best.get("shots", 0)) > 0 else int(basic["shots"])
	var gold: int = best_n + (0 if bool(best.get("robust", basic.get("robust", false))) else 1)
	var basic_n: int = int(basic["shots"]) + (0 if bool(basic.get("robust", false)) else 1)
	var silver: int = maxi(gold + 1, basic_n)
	return {
		"ok": true,
		"par": {"gold": gold, "silver": silver, "bronze": silver + 2},
		"solution": best.get("solution", basic["solution"]),
		"solution_basic": basic["solution"],
		"robust": bool(best.get("robust", false)),
		"robust_basic": bool(basic.get("robust", false)),
		"basic_ammo": Array(basic_ammo),
	}
