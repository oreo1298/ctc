# SPDX-FileCopyrightText: 2026 Siegefall contributors
# SPDX-License-Identifier: MIT
extends Node
## Player settings. Stored in $XDG_CONFIG_HOME/<slug>/settings.cfg on Linux
## (docs/DESIGN.md §8.7) and in user://settings.cfg elsewhere.

signal changed

const SECTION: String = "settings"
const KEYS: Array[String] = [
	"screen_shake",
	"slow_motion",
	"reduce_flashing",
	"material_glyphs",
	"swing_speed",
	"show_ghost_trail",
	"show_swing_gauge",
	"one_button",
	"text_scale",
	"master_volume",
	"sfx_volume",
	"music_volume",
	"haptics",
	"quality",
	"locale",
	"bindings",
]

var screen_shake: bool = true
var slow_motion: bool = true
var reduce_flashing: bool = false
var material_glyphs: bool = false
var swing_speed: float = 1.0
var show_ghost_trail: bool = true
var show_swing_gauge: bool = true
var one_button: bool = false
var text_scale: float = 1.0
var master_volume: float = 0.8
var sfx_volume: float = 1.0
var music_volume: float = 0.6
var haptics: bool = true
var quality: String = "auto"
var locale: String = ""
## action -> Array of [kind, code] (see Controls); empty = defaults.
var bindings: Dictionary = {}
## Tests point this at a scratch file so they never touch real settings.
var path_override: String = ""


func _ready() -> void:
	load_settings()


func config_path() -> String:
	if not path_override.is_empty():
		return path_override
	if OS.has_feature("linuxbsd"):
		var slug: String = str(
			ProjectSettings.get_setting("application/config/custom_user_dir_name", "game")
		)
		return OS.get_config_dir().path_join(slug).path_join("settings.cfg")
	return "user://settings.cfg"


func load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(config_path()) != OK:
		return
	for k: String in KEYS:
		if cfg.has_section_key(SECTION, k):
			var v: Variant = cfg.get_value(SECTION, k)
			if typeof(v) == typeof(get(k)):
				set(k, v)
	swing_speed = clampf(swing_speed, 0.4, 1.0)
	text_scale = clampf(text_scale, 0.8, 1.6)
	apply_locale()


func apply_locale() -> void:
	if not locale.is_empty():
		TranslationServer.set_locale(locale)


func save_settings() -> void:
	var cfg := ConfigFile.new()
	for k: String in KEYS:
		cfg.set_value(SECTION, k, get(k))
	var path: String = config_path()
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var err: Error = cfg.save(path)
	if err != OK:
		push_warning("could not save settings to %s: %s" % [path, error_string(err)])
	changed.emit()
