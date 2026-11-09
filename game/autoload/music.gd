# SPDX-FileCopyrightText: 2026 Siegefall contributors
# SPDX-License-Identifier: MIT
extends Node
## Background music: a seamless loop per realm and one for the menus
## (rendered by tools/music/compose.py). Two players crossfade between
## tracks; the music dips under the win jingle and while the game is paused.
## Volume comes from the Music bus (Settings → Sound).

const TRACKS: Dictionary = {
	"menu": "res://audio/music/menu.wav",
	"greenmantle": "res://audio/music/greenmantle.wav",
	"saffron": "res://audio/music/saffron.wav",
	"frostfang": "res://audio/music/frostfang.wav",
}
const FADE: float = 1.6
const SILENT_DB: float = -40.0
const DIM_DB: float = -8.0

var current: String = ""
var _players: Array[AudioStreamPlayer] = []
var _active: int = 0
var _enabled: bool = true
var _dimmed: bool = false
var _tween: Tween = null
var _duck_tween: Tween = null


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	# No sound card (headless tests, CI): never load or play anything.
	_enabled = AudioServer.get_driver_name() != "Dummy"
	for i: int in 2:
		var p := AudioStreamPlayer.new()
		p.bus = "Music"
		p.volume_db = SILENT_DB
		add_child(p)
		_players.append(p)


## Crossfade to `track` (a realm id or "menu"). Unknown ids fall back to the
## menu theme; asking for the track already playing does nothing.
func play(track: String) -> void:
	if not TRACKS.has(track):
		track = "menu"
	if not _enabled or track == current:
		return
	current = track
	var stream := load(str(TRACKS[track])) as AudioStreamWAV
	if stream == null:
		return
	_ensure_loop(stream)
	var old: AudioStreamPlayer = _players[_active]
	_active = 1 - _active
	var nxt: AudioStreamPlayer = _players[_active]
	nxt.stream = stream
	nxt.volume_db = SILENT_DB
	nxt.play()
	_fade(old, nxt)


func stop() -> void:
	current = ""
	for p: AudioStreamPlayer in _players:
		p.stop()


## Quieter while the pause menu is open.
func dim(on: bool) -> void:
	if not _enabled or on == _dimmed:
		return
	_dimmed = on
	var p: AudioStreamPlayer = _players[_active]
	if p.playing:
		_new_tween(false).tween_property(p, "volume_db", _level(), 0.3)


## Dip under a jingle for `seconds`, then come back.
func duck(seconds: float, depth_db: float = -18.0) -> void:
	if not _enabled:
		return
	var p: AudioStreamPlayer = _players[_active]
	if not p.playing:
		return
	if _duck_tween != null:
		_duck_tween.kill()
	_duck_tween = _new_tween(true)
	_duck_tween.tween_property(p, "volume_db", _level() + depth_db, 0.25)
	_duck_tween.tween_interval(maxf(0.0, seconds - 0.25))
	_duck_tween.tween_property(p, "volume_db", _level(), 1.2)


func _level() -> float:
	return DIM_DB if _dimmed else 0.0


func _fade(old: AudioStreamPlayer, nxt: AudioStreamPlayer) -> void:
	var tw := _new_tween(false)
	tw.tween_property(nxt, "volume_db", _level(), FADE).set_ease(Tween.EASE_OUT)
	if old.playing:
		tw.parallel().tween_property(old, "volume_db", SILENT_DB, FADE)
		tw.tween_callback(old.stop)


func _new_tween(for_duck: bool) -> Tween:
	if not for_duck and _tween != null:
		_tween.kill()
	# Real time: slow motion and pausing must not stretch a fade.
	var tw := create_tween().set_ignore_time_scale(true)
	if not for_duck:
		_tween = tw
	return tw


## The WAVs carry no loop points: loop the whole file. The pieces are
## rendered so that the end flows into the start.
static func _ensure_loop(stream: AudioStreamWAV) -> void:
	if stream.loop_mode == AudioStreamWAV.LOOP_DISABLED:
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
		stream.loop_begin = 0
		stream.loop_end = roundi(stream.get_length() * stream.mix_rate)
