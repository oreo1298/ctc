# SPDX-FileCopyrightText: 2026 Siegefall contributors
# SPDX-License-Identifier: MIT
extends Node
## Layered, variation-rich sound effects. Each logical sound "name" maps to
## res://audio/sfx/<name>_<n>.wav variations; a random one is played with
## pitch and gain jitter. Missing sounds are silently skipped.

const SFX_DIR: String = "res://audio/sfx"
const POOL_SIZE: int = 24
const MAX_PER_SOUND: int = 4

var _streams: Dictionary = {}  # name -> Array[AudioStream]
var _pool: Array[AudioStreamPlayer2D] = []
## A few UI players, so a jingle and a click can overlap.
var _ui: Array[AudioStreamPlayer] = []
var _ui_next: int = 0
var _next: int = 0
var _playing: Dictionary = {}  # name -> count this frame window
var _rng := RandomNumberGenerator.new()
## False on the Dummy audio driver (headless runs, machines without sound):
## nothing could be heard, and Dummy never releases playbacks.
var _enabled: bool = true


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_enabled = AudioServer.get_driver_name() != "Dummy"
	_ensure_buses()
	_scan()
	for i: int in POOL_SIZE:
		var p := AudioStreamPlayer2D.new()
		p.bus = "SFX"
		p.max_distance = 6000.0
		p.attenuation = 0.6
		add_child(p)
		_pool.append(p)
	for i: int in 3:
		var u := AudioStreamPlayer.new()
		u.bus = "UI"
		add_child(u)
		_ui.append(u)
	apply_volumes()
	Settings.changed.connect(apply_volumes)


func _ensure_buses() -> void:
	for bus: String in ["SFX", "Music", "UI"]:
		if AudioServer.get_bus_index(bus) < 0:
			AudioServer.add_bus()
			var idx: int = AudioServer.bus_count - 1
			AudioServer.set_bus_name(idx, bus)
			AudioServer.set_bus_send(idx, "Master")


func apply_volumes() -> void:
	AudioServer.set_bus_volume_db(0, linear_to_db(maxf(Settings.master_volume, 0.0001)))
	AudioServer.set_bus_volume_db(
		AudioServer.get_bus_index("SFX"), linear_to_db(maxf(Settings.sfx_volume, 0.0001))
	)
	AudioServer.set_bus_volume_db(
		AudioServer.get_bus_index("Music"), linear_to_db(maxf(Settings.music_volume, 0.0001))
	)


func _scan() -> void:
	var dir := DirAccess.open(SFX_DIR)
	if dir == null:
		return
	for f: String in dir.get_files():
		# Exported builds list the imported resources as *.wav.import.
		var file: String = f.trim_suffix(".import")
		if not file.ends_with(".wav"):
			continue
		var base: String = file.get_basename()
		var name: String = base.left(base.rfind("_")) if base.rfind("_") > 0 else base
		var stream: AudioStream = load(SFX_DIR.path_join(file)) as AudioStream
		if stream == null:
			continue
		if not _streams.has(name):
			_streams[name] = []
		if not (_streams[name] as Array).has(stream):
			(_streams[name] as Array).append(stream)


func has(name: String) -> bool:
	return _streams.has(name)


## Play a positional sound. Returns false if it does not exist.
func play_at(
	name: String, pos: Vector2, volume_db: float = 0.0, pitch_jitter: float = 0.08
) -> bool:
	if not _enabled or not _streams.has(name):
		return false
	if int(_playing.get(name, 0)) >= MAX_PER_SOUND:
		return false
	var list: Array = _streams[name]
	var p: AudioStreamPlayer2D = _pool[_next]
	_next = (_next + 1) % _pool.size()
	p.stream = list[_rng.randi() % list.size()]
	p.global_position = pos
	p.volume_db = volume_db + _rng.randf_range(-1.5, 1.0)
	p.pitch_scale = 1.0 + _rng.randf_range(-pitch_jitter, pitch_jitter)
	p.play()
	_playing[name] = int(_playing.get(name, 0)) + 1
	get_tree().create_timer(0.08, true, false, true).timeout.connect(
		func() -> void: _playing[name] = maxi(0, int(_playing.get(name, 1)) - 1)
	)
	return true


## Freeze or resume every in-world sound (the pause menu). UI clicks keep
## playing.
func pause_world(paused: bool) -> void:
	for p: AudioStreamPlayer2D in _pool:
		p.stream_paused = paused


func play_ui(name: String, volume_db: float = 0.0) -> void:
	if not _enabled or not _streams.has(name):
		return
	var list: Array = _streams[name]
	var u: AudioStreamPlayer = _ui[_ui_next]
	_ui_next = (_ui_next + 1) % _ui.size()
	u.stream = list[_rng.randi() % list.size()]
	u.volume_db = volume_db
	u.play()


## Layered impact: a material "body" layer plus, for harder hits, a
## "texture" layer (crack, tink, clang...), scaled by impulse.
func impact(material_id: String, impulse_ns: float, pos: Vector2) -> void:
	var loud: float = clampf(remap(impulse_ns, 50.0, 8000.0, -18.0, 0.0), -18.0, 0.0)
	play_at(material_id + "_hit", pos, loud)
	if impulse_ns > 1500.0:
		play_at(material_id + "_crack", pos, loud - 3.0)


func shatter(material_id: String, area_m2: float, pos: Vector2) -> void:
	play_at(material_id + "_break", pos, clampf(-8.0 + area_m2 * 6.0, -8.0, 2.0))
	if area_m2 > 1.0:
		play_at("rumble", pos, -6.0, 0.15)


func _exit_tree() -> void:
	for p: AudioStreamPlayer2D in _pool:
		p.stop()
		p.stream = null
	for u: AudioStreamPlayer in _ui:
		u.stop()
		u.stream = null
	_streams.clear()
