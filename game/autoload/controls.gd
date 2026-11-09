# SPDX-FileCopyrightText: 2026 Siegefall contributors
# SPDX-License-Identifier: MIT
extends Node
## Default input bindings (keyboard, mouse, gamepad) registered in code so
## that remapping (Settings) can reset to them. Touch arrives as emulated mouse
## clicks, so a tap anywhere outside HUD buttons is "fire".

const ACTIONS: Dictionary = {
	"fire": [["key", KEY_SPACE], ["joy", JOY_BUTTON_A], ["mouse", MOUSE_BUTTON_LEFT]],
	"restart": [["key", KEY_R], ["joy", JOY_BUTTON_BACK]],
	"pause": [["key", KEY_ESCAPE], ["key", KEY_P], ["joy", JOY_BUTTON_START]],
	"ammo_next":
	[["key", KEY_E], ["joy", JOY_BUTTON_RIGHT_SHOULDER], ["mouse", MOUSE_BUTTON_WHEEL_DOWN]],
	"ammo_prev":
	[["key", KEY_Q], ["joy", JOY_BUTTON_LEFT_SHOULDER], ["mouse", MOUSE_BUTTON_WHEEL_UP]],
	"next_level": [["key", KEY_N]],
}


func _ready() -> void:
	reset_to_defaults()
	Input.use_accumulated_input = false


func reset_to_defaults() -> void:
	for action: String in ACTIONS:
		if InputMap.has_action(action):
			InputMap.action_erase_events(action)
		else:
			InputMap.add_action(action, 0.5)
		for spec: Array in ACTIONS[action]:
			InputMap.action_add_event(action, make_event(str(spec[0]), int(spec[1])))


static func make_event(kind: String, code: int) -> InputEvent:
	match kind:
		"mouse":
			var mb := InputEventMouseButton.new()
			mb.button_index = code as MouseButton
			return mb
		"joy":
			var jb := InputEventJoypadButton.new()
			jb.button_index = code as JoyButton
			return jb
	var k := InputEventKey.new()
	k.physical_keycode = code as Key
	return k
