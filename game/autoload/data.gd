# SPDX-FileCopyrightText: 2026 Siegefall contributors
# SPDX-License-Identifier: MIT
extends Node
## Read-only registry of all game content loaded from res://data/*.json.
## Content lives in data; this script only loads and indexes it.

const DATA_DIR: String = "res://data"

var materials: Dictionary = {}
var ammo: Array[Dictionary] = []
var ammo_by_id: Dictionary = {}
var enemies: Dictionary = {}
var trebuchet: Dictionary = {}
var time_of_day: Dictionary = {}
## Realms sorted by "order".
var realms: Array[Dictionary] = []
var realm_by_id: Dictionary = {}
## level id -> realm id
var level_realm: Dictionary = {}
var load_errors: PackedStringArray = PackedStringArray()


func _ready() -> void:
	reload()


func reload() -> void:
	load_errors.clear()
	materials = _dict(load_json("materials.json").get("materials", {}))
	enemies = _dict(load_json("enemies.json").get("enemies", {}))
	trebuchet = load_json("trebuchet.json")
	time_of_day = _dict(load_json("time_of_day.json").get("grades", {}))
	ammo.clear()
	ammo_by_id.clear()
	var raw_ammo: Variant = load_json("ammo.json").get("ammo", [])
	if raw_ammo is Array:
		for a: Variant in raw_ammo:
			if a is Dictionary:
				ammo.append(a)
				ammo_by_id[str((a as Dictionary).get("id", ""))] = a
	_load_realms()
	for e: String in load_errors:
		push_error(e)


func load_json(rel_path: String) -> Dictionary:
	var path: String = DATA_DIR.path_join(rel_path)
	if not FileAccess.file_exists(path):
		load_errors.append("missing data file %s" % path)
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not parsed is Dictionary:
		load_errors.append("invalid JSON in %s" % path)
		return {}
	return parsed


func _load_realms() -> void:
	realms.clear()
	realm_by_id.clear()
	level_realm.clear()
	var dir := DirAccess.open(DATA_DIR.path_join("realms"))
	if dir == null:
		load_errors.append("missing res://data/realms")
		return
	for f: String in dir.get_files():
		if not f.ends_with(".json"):
			continue
		var r: Dictionary = load_json("realms".path_join(f))
		if r.is_empty():
			continue
		realms.append(r)
		realm_by_id[str(r.get("id", ""))] = r
		var levels: Variant = r.get("levels", [])
		if levels is Array:
			for lid: Variant in levels:
				level_realm[str(lid)] = str(r.get("id", ""))
	realms.sort_custom(
		func(a: Dictionary, b: Dictionary) -> bool:
			return int(a.get("order", 0)) < int(b.get("order", 0))
	)


## Campaign level ids in play order across all realms.
func campaign_levels() -> PackedStringArray:
	var out := PackedStringArray()
	for r: Dictionary in realms:
		var levels: Variant = r.get("levels", [])
		if levels is Array:
			for lid: Variant in levels:
				out.append(str(lid))
	return out


func level_path(level_id: String) -> String:
	var realm: String = str(level_realm.get(level_id, "dev"))
	return DATA_DIR.path_join("levels").path_join(realm).path_join(level_id + ".json")


## Load and validate a campaign level. Check `.errors` on the result.
func load_level(level_id: String) -> LevelData:
	var path: String = level_path(level_id)
	var parsed: Variant = null
	if FileAccess.file_exists(path):
		parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not parsed is Dictionary:
		var lv := LevelData.new()
		lv.errors.append("cannot read level '%s' (%s)" % [level_id, path])
		return lv
	return LevelData.parse(parsed, materials, enemies)


func parse_level(d: Dictionary) -> LevelData:
	return LevelData.parse(d, materials, enemies)


func material(id: String) -> Dictionary:
	return _dict(materials.get(id, {}))


func enemy(id: String) -> Dictionary:
	return _dict(enemies.get(id, {}))


func ammo_def(id: String) -> Dictionary:
	return _dict(ammo_by_id.get(id, {}))


func realm(id: String) -> Dictionary:
	return _dict(realm_by_id.get(id, {}))


func grade(time: String) -> Dictionary:
	return _dict(time_of_day.get(time, time_of_day.get("noon", {})))


static func _dict(v: Variant) -> Dictionary:
	return v if v is Dictionary else {}
