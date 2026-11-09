# SPDX-FileCopyrightText: 2026 Siegefall contributors
# SPDX-License-Identifier: MIT
extends Node
## Session flow (menu <-> level), progression and the save file.

signal save_changed

const SAVE_PATH: String = "user://save.json"
const MENU_SCENE: String = "res://scenes/menu/main_menu.tscn"
const LEVEL_SCENE: String = "res://scenes/level/level.tscn"
const LEVEL_SELECT_SCENE: String = "res://scenes/menu/level_select.tscn"
const SETTINGS_SCENE: String = "res://scenes/menu/settings.tscn"
const EDITOR_SCENE: String = "res://scenes/editor/editor.tscn"
const FADE_TIME: float = 0.22

var save: SaveGame = SaveGame.new()
var current_level_id: String = ""
## Level built from data outside the campaign (editor test-play, share code).
var custom_level: Dictionary = {}
## The castle editor's document and undo history; it outlives the editor
## scene so test-play can return to exactly where the player left off.
var editor: EditorModel = null
## True while test-playing the castle open in the editor.
var custom_from_editor: bool = false
var selected_ammo: String = "boulder"
## Parsed command-line options (after `--`), e.g. --level=greenmantle-01.
var cli: Dictionary = {}

## Set by a level when it is won (for --quit-after exit codes).
var last_level_won: bool = false

var _fade: ColorRect
var _fade_layer: CanvasLayer
var _changing: bool = false

var _dev_time: float = 0.0
var _shots: Array[Dictionary] = []
var _quit_after: float = -1.0
var _perf: PerfProbe = null


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_parse_cli()
	_build_fade()
	load_save()
	_setup_dev_options()


## --screenshots=t:file,...  save the viewport t seconds after launch
## --quit-after=seconds      quit then (exit 0, or 3 if a level was not won
##                           while --level was given)
## --perf                    print frame/physics timings when quitting
func _setup_dev_options() -> void:
	if cli.has("screenshots"):
		for s: String in str(cli["screenshots"]).split(",", false):
			var kv: PackedStringArray = s.split(":", true, 1)
			if kv.size() == 2:
				_shots.append({"t": kv[0].to_float(), "file": kv[1]})
		_shots.sort_custom(
			func(a: Dictionary, b: Dictionary) -> bool: return float(a["t"]) < float(b["t"])
		)
	if cli.has("quit-after"):
		_quit_after = str(cli["quit-after"]).to_float()
	if cli.has("perf"):
		_perf = PerfProbe.new()
	set_process(not _shots.is_empty() or _quit_after > 0.0 or _perf != null)


func _process(delta: float) -> void:
	_dev_time += delta
	if _perf != null:
		_perf.sample()
	if not _shots.is_empty():
		# Skip rendering until just before the next capture (fast on llvmpipe).
		RenderingServer.render_loop_enabled = _dev_time >= float(_shots[0]["t"]) - 0.3
		while not _shots.is_empty() and _dev_time >= float(_shots[0]["t"]):
			var file: String = str(_shots[0]["file"])
			_shots.remove_at(0)
			var img: Image = get_viewport().get_texture().get_image()
			DirAccess.make_dir_recursive_absolute(file.get_base_dir())
			img.save_png(file)
			print("[screenshot] %s" % file)
		if _shots.is_empty():
			RenderingServer.render_loop_enabled = true
	if _quit_after > 0.0 and _dev_time >= _quit_after:
		var code: int = 0
		if cli.has("level") and cli.has("autoplay") and not last_level_won:
			code = 3
		if _perf != null:
			print(_perf.summary())
		get_tree().quit(code)


func _parse_cli() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--"):
			var kv: PackedStringArray = arg.substr(2).split("=", true, 1)
			cli[kv[0]] = kv[1] if kv.size() > 1 else "true"


func _build_fade() -> void:
	_fade_layer = CanvasLayer.new()
	_fade_layer.layer = 128
	add_child(_fade_layer)
	_fade = ColorRect.new()
	_fade.color = Color(0.953, 0.918, 0.835, 0.0)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fade_layer.add_child(_fade)


# ------------------------------------------------------------------ flow ---
func goto_menu() -> void:
	_change_scene(MENU_SCENE)


func goto_levels() -> void:
	_change_scene(LEVEL_SELECT_SCENE)


func goto_settings() -> void:
	_change_scene(SETTINGS_SCENE)


func goto_editor() -> void:
	if ResourceLoader.exists(EDITOR_SCENE):
		_change_scene(EDITOR_SCENE)


func play_level(level_id: String) -> void:
	current_level_id = level_id
	custom_level = {}
	save.last_level = level_id
	if not is_ammo_unlocked(selected_ammo):
		selected_ammo = "boulder"
	_change_scene(LEVEL_SCENE)


func play_custom(level_dict: Dictionary, from_editor: bool = false) -> void:
	current_level_id = ""
	custom_level = level_dict.duplicate(true)
	custom_from_editor = from_editor
	if not is_ammo_unlocked(selected_ammo):
		selected_ammo = "boulder"
	_change_scene(LEVEL_SCENE)


## Where "Menu" leads from a level: the editor after test-play, otherwise
## the level list.
func leave_level() -> void:
	if not custom_level.is_empty() and custom_from_editor:
		goto_editor()
	else:
		goto_levels()


## A custom castle was won. From the editor, the fewest shots becomes the
## castle's par (saved with it). Returns true for a new record.
func record_custom_win(shots: int) -> bool:
	if not custom_from_editor or editor == null:
		return false
	if not editor.record_par(shots):
		return false
	custom_level["par"] = editor.doc["par"]
	CustomLevels.save_level(editor.doc)
	return true


## Instant retry: no fade, no confirmation.
func restart_level() -> void:
	get_tree().paused = false
	Effects.reset_time()
	get_tree().reload_current_scene()


func next_level_id(level_id: String) -> String:
	var all: PackedStringArray = Data.campaign_levels()
	var i: int = all.find(level_id)
	if i >= 0 and i + 1 < all.size():
		return all[i + 1]
	return ""


func _change_scene(path: String) -> void:
	if _changing:
		return
	_changing = true
	get_tree().paused = false
	Effects.reset_time()
	var tw := create_tween()
	tw.tween_property(_fade, "color:a", 1.0, FADE_TIME)
	await tw.finished
	get_tree().change_scene_to_file(path)
	await get_tree().process_frame
	var tw2 := create_tween()
	tw2.tween_property(_fade, "color:a", 0.0, FADE_TIME)
	_changing = false


# ----------------------------------------------------------- progression ---
## A level is open if it is the first of the campaign, its predecessor is
## completed, or the player already completed it. Dev/custom levels: always.
func is_level_unlocked(level_id: String) -> bool:
	if cli.has("unlock-all"):
		return true
	var all: PackedStringArray = Data.campaign_levels()
	var i: int = all.find(level_id)
	if i <= 0:
		return true
	return save.is_completed(level_id) or save.is_completed(all[i - 1])


func is_realm_unlocked(realm_id: String) -> bool:
	var r: Dictionary = Data.realm(realm_id)
	var levels: Array = r.get("levels", [])
	return levels.is_empty() or is_level_unlocked(str(levels[0]))


## First level the player has not completed yet (or the last level).
func next_unfinished_level() -> String:
	var all: PackedStringArray = Data.campaign_levels()
	for id: String in all:
		if not save.is_completed(id):
			return id
	return all[all.size() - 1] if not all.is_empty() else ""


func medal_count(medal: Scoring.Medal) -> int:
	var n: int = 0
	for id: String in save.levels:
		if save.medal(id) == medal:
			n += 1
	return n


func is_ammo_unlocked(ammo_id: String) -> bool:
	return save.unlocked_ammo.has(ammo_id)


func unlocked_ammo_list() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for a: Dictionary in Data.ammo:
		if is_ammo_unlocked(str(a.get("id", ""))):
			out.append(a)
	return out


## Returns ids of ammo newly unlocked by finishing `level_id`.
func record_win(
	level_id: String, shots: int, medal: Scoring.Medal, score: int
) -> PackedStringArray:
	var newly := PackedStringArray()
	if level_id.is_empty():
		return newly
	save.record_win(level_id, shots, medal, score)
	for a: Dictionary in Data.ammo:
		var id: String = str(a.get("id", ""))
		if str(a.get("unlock_after", "")) == level_id and not save.unlocked_ammo.has(id):
			save.unlocked_ammo.append(id)
			newly.append(id)
	write_save()
	save_changed.emit()
	return newly


# ------------------------------------------------------------------ save ---
func load_save() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		save = SaveGame.new()
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(SAVE_PATH))
	var errs := PackedStringArray()
	if parsed is Dictionary:
		save = SaveGame.from_dict(parsed, errs)
	else:
		errs.append("save file is not valid JSON")
	if not errs.is_empty():
		push_warning("Save not loaded (%s); keeping a copy as save.json.corrupt" % "; ".join(errs))
		DirAccess.copy_absolute(
			ProjectSettings.globalize_path(SAVE_PATH),
			ProjectSettings.globalize_path(SAVE_PATH + ".corrupt")
		)
		save = SaveGame.new()


## Atomic write: temp file, keep a .bak of the previous save, then rename.
func write_save() -> void:
	if cli.has("no-save"):
		return
	var tmp: String = SAVE_PATH + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		push_error("cannot write %s: %s" % [tmp, error_string(FileAccess.get_open_error())])
		return
	f.store_string(JSON.stringify(save.to_dict(), "  "))
	f.close()
	var abs_save: String = ProjectSettings.globalize_path(SAVE_PATH)
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.copy_absolute(abs_save, abs_save + ".bak")
	DirAccess.rename_absolute(ProjectSettings.globalize_path(tmp), abs_save)


func _exit_tree() -> void:
	Block.clear_shared()
