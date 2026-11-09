# SPDX-FileCopyrightText: 2026 Siegefall contributors
# SPDX-License-Identifier: MIT
class_name CustomLevels
extends RefCounted
## The player's own castles: one level JSON file each in user://levels
## (on Linux ~/.local/share/siegefall/levels). Writes are atomic (temp file,
## then rename) so a crash never leaves half a castle behind.

const DIR: String = "user://levels"
const MAX_FILE_BYTES: int = 1048576

## Tests point this somewhere else.
static var dir_override: String = ""


static func folder() -> String:
	return dir_override if not dir_override.is_empty() else DIR


static func path_for(id: String) -> String:
	return folder().path_join(id + ".json")


## A fresh id that no saved castle uses yet.
static func unique_id() -> String:
	var base: String = "custom-%d" % int(Time.get_unix_time_from_system())
	var id: String = base
	var n: int = 2
	while FileAccess.file_exists(path_for(id)):
		id = "%s-%d" % [base, n]
		n += 1
	return id


## Saved castles, most recently changed first:
## [{"id", "name", "modified", "blocks", "enemies", "par"}].
static func list() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var d := DirAccess.open(folder())
	if d == null:
		return out
	for f: String in d.get_files():
		if not f.ends_with(".json"):
			continue
		var id: String = f.get_basename()
		var lv: Dictionary = load_level(id)
		if lv.is_empty():
			continue
		(
			out
			. append(
				{
					"id": id,
					"name": str(lv.get("name", id)),
					"modified": FileAccess.get_modified_time(path_for(id)),
					"blocks": (lv.get("blocks", []) as Array).size(),
					"enemies": (lv.get("enemies", []) as Array).size(),
					"par": lv.get("par", {}),
				}
			)
		)
	out.sort_custom(
		func(a: Dictionary, b: Dictionary) -> bool: return int(a["modified"]) > int(b["modified"])
	)
	return out


static func load_level(id: String) -> Dictionary:
	var r: Dictionary = read_file(path_for(id))
	return r["level"] if r["ok"] else {}


static func save_level(level: Dictionary) -> bool:
	var id: String = str(level.get("id", ""))
	if id.is_empty():
		return false
	DirAccess.make_dir_recursive_absolute(folder())
	return write_file(path_for(id), level)


static func delete_level(id: String) -> void:
	if FileAccess.file_exists(path_for(id)):
		DirAccess.remove_absolute(path_for(id))


## Write a level as pretty JSON, atomically. Works for user:// and for
## absolute paths chosen in a file dialog.
static func write_file(path: String, level: Dictionary) -> bool:
	var tmp: String = path + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(JSON.stringify(level, "  ") + "\n")
	f.close()
	return DirAccess.rename_absolute(tmp, path) == OK


## Returns {"ok": bool, "level": Dictionary, "error": String}. Only checks
## that the file is a level; Data.parse_level reports what is wrong inside.
static func read_file(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {"ok": false, "level": {}, "error": I18n.tr_noop("File not found.")}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {"ok": false, "level": {}, "error": I18n.tr_noop("That file can't be opened.")}
	if f.get_length() > MAX_FILE_BYTES:
		return {
			"ok": false,
			"level": {},
			"error": I18n.tr_noop("That file is too large to be a castle.")
		}
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	if not parsed is Dictionary or str((parsed as Dictionary).get("format", "")) != "level":
		return {
			"ok": false, "level": {}, "error": I18n.tr_noop("That file isn't a Siegefall castle.")
		}
	return {"ok": true, "level": parsed, "error": ""}


## Store an imported castle (file or share code) under a new id so it never
## overwrites one of the player's own.
static func import_level(level: Dictionary) -> Dictionary:
	var lv: Dictionary = level.duplicate(true)
	lv["id"] = unique_id()
	for k: String in ["solution", "solution_basic", "$schema"]:
		lv.erase(k)
	save_level(lv)
	return lv
