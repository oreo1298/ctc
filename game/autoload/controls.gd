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

## Actions shown (and remappable) in Settings, in order.
const REMAPPABLE: Array[String] = ["fire", "restart", "pause", "ammo_next", "ammo_prev"]


func _ready() -> void:
	reset_to_defaults()
	apply_overrides(Settings.bindings)
	Input.use_accumulated_input = false


## Replace the key (or button) of `kind` for `action` with `event`, keeping
## the other device kinds' bindings, and persist the result.
func rebind(action: String, event: InputEvent) -> void:
	var kind: String = kind_of(event)
	for e: InputEvent in InputMap.action_get_events(action):
		if kind_of(e) == kind:
			InputMap.action_erase_event(action, e)
	InputMap.action_add_event(action, event)
	Settings.bindings[action] = serialize(action)
	Settings.save_settings()


func reset_all() -> void:
	Settings.bindings = {}
	Settings.save_settings()
	reset_to_defaults()


func apply_overrides(overrides: Dictionary) -> void:
	for action: Variant in overrides:
		if not InputMap.has_action(str(action)):
			continue
		var list: Variant = overrides[action]
		if not list is Array:
			continue
		InputMap.action_erase_events(str(action))
		for spec: Variant in list:
			if spec is Array and (spec as Array).size() == 2:
				InputMap.action_add_event(str(action), make_event(str(spec[0]), int(spec[1])))


func serialize(action: String) -> Array:
	var out: Array = []
	for e: InputEvent in InputMap.action_get_events(action):
		var k: String = kind_of(e)
		var code: int = -1
		if e is InputEventKey:
			code = (e as InputEventKey).physical_keycode
		elif e is InputEventMouseButton:
			code = (e as InputEventMouseButton).button_index
		elif e is InputEventJoypadButton:
			code = (e as InputEventJoypadButton).button_index
		if code >= 0:
			out.append([k, code])
	return out


static func kind_of(e: InputEvent) -> String:
	if e is InputEventMouseButton:
		return "mouse"
	if e is InputEventJoypadButton:
		return "joy"
	return "key"


## Human-readable binding list, e.g. "Space · A · Left click".
static func describe(action: String) -> String:
	var parts: PackedStringArray = []
	for e: InputEvent in InputMap.action_get_events(action):
		if e is InputEventKey:
			parts.append(OS.get_keycode_string((e as InputEventKey).physical_keycode))
		elif e is InputEventMouseButton:
			var names: Dictionary = {
				MOUSE_BUTTON_LEFT: "Left click",
				MOUSE_BUTTON_RIGHT: "Right click",
				MOUSE_BUTTON_WHEEL_UP: "Wheel up",
				MOUSE_BUTTON_WHEEL_DOWN: "Wheel down",
			}
			parts.append(str(names.get((e as InputEventMouseButton).button_index, "Mouse")))
		elif e is InputEventJoypadButton:
			var pads: Dictionary = {
				JOY_BUTTON_A: "Pad A",
				JOY_BUTTON_B: "Pad B",
				JOY_BUTTON_X: "Pad X",
				JOY_BUTTON_Y: "Pad Y",
				JOY_BUTTON_BACK: "Pad Back",
				JOY_BUTTON_START: "Pad Start",
				JOY_BUTTON_LEFT_SHOULDER: "Pad LB",
				JOY_BUTTON_RIGHT_SHOULDER: "Pad RB",
			}
			parts.append(str(pads.get((e as InputEventJoypadButton).button_index, "Pad")))
	return " · ".join(parts)


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
