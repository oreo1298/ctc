# SPDX-FileCopyrightText: 2026 Siegefall contributors
# SPDX-License-Identifier: MIT
extends Control
## Entry scene. Shows the title card for now; later milestones route from
## here to the main menu. Supports `-- --smoke-test` for CI: render a few
## frames, report the active renderer, and quit with exit code 0.

const SMOKE_FRAMES: int = 30

var _frames: int = 0
var _smoke: bool = false

@onready var _title: Label = %Title
@onready var _subtitle: Label = %Subtitle


func _ready() -> void:
	_smoke = OS.get_cmdline_user_args().has("--smoke-test")
	_title.text = str(ProjectSettings.get_setting("application/config/name"))
	_subtitle.text = (
		tr("Version %s") % str(ProjectSettings.get_setting("application/config/version"))
	)
	if _smoke:
		print(
			(
				"[smoke] %s %s"
				% [_title.text, ProjectSettings.get_setting("application/config/version")]
			)
		)
		print(
			(
				"[smoke] renderer=%s driver=%s display=%s"
				% [
					RenderingServer.get_current_rendering_method(),
					RenderingServer.get_current_rendering_driver_name(),
					DisplayServer.get_name(),
				]
			)
		)
		print("[smoke] user_dir=%s" % OS.get_user_data_dir())


func _process(_delta: float) -> void:
	if not _smoke:
		return
	_frames += 1
	if _frames >= SMOKE_FRAMES:
		print("[smoke] ok after %d frames" % _frames)
		get_tree().quit(0)
