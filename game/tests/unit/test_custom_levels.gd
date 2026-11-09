# SPDX-FileCopyrightText: 2026 Siegefall contributors
# SPDX-License-Identifier: MIT
extends GutTest
## The player's saved castles (user://levels), files and imports.

const DIR: String = "user://test-custom-levels"


func before_each() -> void:
	CustomLevels.dir_override = DIR
	_wipe()


func after_each() -> void:
	_wipe()
	CustomLevels.dir_override = ""


func _wipe() -> void:
	var d := DirAccess.open(DIR)
	if d != null:
		for f: String in d.get_files():
			d.remove(f)
		DirAccess.remove_absolute(DIR)


func _castle(name: String) -> Dictionary:
	var lv: Dictionary = EditorModel.new_level()
	lv["name"] = name
	lv["enemies"] = [{"type": "king", "pos": [30.0, 0.55]}]
	return lv


func test_save_list_load_delete() -> void:
	assert_true(CustomLevels.list().is_empty())
	var a: Dictionary = _castle("Alpha")
	assert_true(CustomLevels.save_level(a))
	var listed: Array[Dictionary] = CustomLevels.list()
	assert_eq(listed.size(), 1)
	assert_eq(listed[0]["name"], "Alpha")
	assert_eq(int(listed[0]["enemies"]), 1)
	assert_eq(CustomLevels.load_level(str(a["id"]))["name"], "Alpha")
	assert_false(FileAccess.file_exists(CustomLevels.path_for(str(a["id"])) + ".tmp"), "atomic")
	CustomLevels.delete_level(str(a["id"]))
	assert_true(CustomLevels.list().is_empty())


func test_ids_are_unique_and_valid() -> void:
	var a: Dictionary = _castle("A")
	CustomLevels.save_level(a)
	var id: String = CustomLevels.unique_id()
	assert_ne(id, str(a["id"]))
	assert_true(Data.parse_level(_castle("B")).is_valid(), "new castles use valid ids")


func test_imports_never_overwrite() -> void:
	var a: Dictionary = _castle("Mine")
	CustomLevels.save_level(a)
	var shared: Dictionary = a.duplicate(true)
	shared["name"] = "Theirs"
	shared["solution"] = [{"ammo": "boulder", "phase": 0.6, "tap": -1}]
	var imported: Dictionary = CustomLevels.import_level(shared)
	assert_ne(imported["id"], a["id"])
	assert_false(imported.has("solution"))
	assert_eq(CustomLevels.list().size(), 2)
	assert_eq(CustomLevels.load_level(str(a["id"]))["name"], "Mine")


func test_files_that_are_not_castles_are_refused() -> void:
	DirAccess.make_dir_recursive_absolute(DIR)
	var p: String = DIR.path_join("junk.txt")
	var f := FileAccess.open(p, FileAccess.WRITE)
	f.store_string('{"hello": 1}')
	f.close()
	var r: Dictionary = CustomLevels.read_file(p)
	assert_false(r["ok"])
	assert_ne(r["error"], "")
	assert_false(CustomLevels.read_file(DIR.path_join("missing.json"))["ok"])
	DirAccess.remove_absolute(p)


func test_exported_file_reads_back() -> void:
	DirAccess.make_dir_recursive_absolute(DIR)
	var p: String = DIR.path_join("export.json")
	assert_true(CustomLevels.write_file(p, _castle("Exported")))
	var r: Dictionary = CustomLevels.read_file(p)
	assert_true(r["ok"], str(r["error"]))
	assert_eq(r["level"]["name"], "Exported")
	DirAccess.remove_absolute(p)
