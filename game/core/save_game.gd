# SPDX-FileCopyrightText: 2026 Siegefall contributors
# SPDX-License-Identifier: MIT
class_name SaveGame
extends RefCounted
## Versioned save data with step-by-step migrations (docs/DESIGN.md §8.7).
## Pure data + JSON (de)serialisation; file IO lives in the Game autoload.

const FORMAT_SUFFIX: String = "-save"
const VERSION: int = 1

## level id -> {"medal": String, "best_shots": int, "best_score": int}
var levels: Dictionary = {}
## Ammo ids the player has unlocked (also derivable from levels; cached).
var unlocked_ammo: PackedStringArray = PackedStringArray(["boulder"])
var last_level: String = ""


static func format_name() -> String:
	return (
		str(ProjectSettings.get_setting("application/config/custom_user_dir_name", "game"))
		+ FORMAT_SUFFIX
	)


func to_dict() -> Dictionary:
	return {
		"format": format_name(),
		"version": VERSION,
		"levels": levels,
		"unlocked_ammo": Array(unlocked_ammo),
		"last_level": last_level,
	}


## Parse any supported version. Unknown or corrupt input yields a fresh save
## and a message in `errs` (the caller keeps a backup of the bad file).
static func from_dict(d: Dictionary, errs: PackedStringArray) -> SaveGame:
	var s := SaveGame.new()
	var migrated: Dictionary = migrate(d, errs)
	if not errs.is_empty():
		return s
	var lv: Variant = migrated.get("levels", {})
	if lv is Dictionary:
		for k: Variant in lv:
			var e: Variant = (lv as Dictionary)[k]
			if e is Dictionary:
				var ed: Dictionary = e
				s.levels[str(k)] = {
					"medal": str(ed.get("medal", "none")),
					"best_shots": int(ed.get("best_shots", 0)),
					"best_score": int(ed.get("best_score", 0)),
				}
	var ua: Variant = migrated.get("unlocked_ammo", ["boulder"])
	if ua is Array:
		s.unlocked_ammo = PackedStringArray(ua as Array)
	if not s.unlocked_ammo.has("boulder"):
		s.unlocked_ammo.append("boulder")
	s.last_level = str(migrated.get("last_level", ""))
	return s


## Bring an older save up to VERSION. Each step is a pure function v -> v+1.
static func migrate(d: Dictionary, errs: PackedStringArray) -> Dictionary:
	var v: int = int(d.get("version", 0))
	if v < 1:
		errs.append("not a save file")
		return d
	if v > VERSION:
		errs.append("save is from a newer version of the game (v%d > v%d)" % [v, VERSION])
		return d
	var out: Dictionary = d.duplicate(true)
	while v < VERSION:
		# Add `_v1_to_v2(out)` etc. here as the format evolves.
		v += 1
	out["version"] = VERSION
	return out


## Record a win; returns true if anything improved.
func record_win(level_id: String, shots: int, medal: Scoring.Medal, score: int) -> bool:
	var prev: Dictionary = levels.get(level_id, {})
	var prev_medal: Scoring.Medal = Scoring.medal_from_key(str(prev.get("medal", "none")))
	var prev_shots: int = int(prev.get("best_shots", 0))
	var improved: bool = prev.is_empty()
	var entry: Dictionary = {
		"medal": Scoring.medal_key(prev_medal),
		"best_shots": prev_shots,
		"best_score": int(prev.get("best_score", 0)),
	}
	if Scoring.better(medal, prev_medal) or prev.is_empty():
		entry["medal"] = Scoring.medal_key(medal)
		improved = true
	if prev_shots == 0 or shots < prev_shots:
		entry["best_shots"] = shots
		improved = true
	if score > int(entry["best_score"]):
		entry["best_score"] = score
		improved = true
	levels[level_id] = entry
	return improved


func is_completed(level_id: String) -> bool:
	return levels.has(level_id)


func medal(level_id: String) -> Scoring.Medal:
	var e: Dictionary = levels.get(level_id, {})
	return Scoring.medal_from_key(str(e.get("medal", "none")))
