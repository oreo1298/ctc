# SPDX-FileCopyrightText: 2026 Siegefall contributors
# SPDX-License-Identifier: MIT
extends GutTest
## Music: a looping track for every realm and the menus, and the player that
## crossfades, dims and ducks them.

var _was_enabled: bool


func before_each() -> void:
	# Tests run on the Dummy audio driver, where Music stays off; switch it on
	# so the code paths a player hears actually run.
	_was_enabled = Music._enabled
	Music._enabled = true
	Music.stop()


func after_each() -> void:
	Music.stop()
	Music.dim(false)
	for p: AudioStreamPlayer in Music._players:
		p.stream = null
	Music._enabled = _was_enabled


func test_every_realm_and_the_menu_have_a_seamless_loop() -> void:
	var ids: Array[String] = ["menu"]
	for r: Dictionary in Data.realms:
		ids.append(str(r.get("id", "")))
	for id: String in ids:
		assert_true(Music.TRACKS.has(id), "%s has music" % id)
		var s := load(str(Music.TRACKS[id])) as AudioStreamWAV
		assert_not_null(s, id)
		assert_eq(s.loop_mode, AudioStreamWAV.LOOP_FORWARD, "%s loops" % id)
		assert_eq(s.loop_begin, 0)
		assert_gt(s.get_length(), 30.0, "%s is a real piece, not a jingle" % id)


func test_crossfade_and_fallback() -> void:
	Music.play("greenmantle")
	assert_eq(Music.current, "greenmantle")
	var first: AudioStreamPlayer = Music._players[Music._active]
	assert_true(first.playing)
	Music.play("greenmantle")
	assert_eq(Music._players[Music._active], first, "asking again does not restart it")
	Music.play("saffron")
	assert_ne(Music._players[Music._active], first, "the other player fades in")
	assert_true(first.playing, "while the old one fades out")
	Music.play("no-such-realm")
	assert_eq(Music.current, "menu", "unknown realms get the menu theme")


func test_dim_and_duck_do_not_stop_the_music() -> void:
	Music.play("frostfang")
	Music.dim(true)
	Music.duck(1.0)
	await wait_seconds(0.4)
	assert_true(Music._players[Music._active].playing)
	assert_lt(Music._players[Music._active].volume_db, -5.0, "quieter while dimmed and ducked")
	Music.dim(false)


func test_win_sounds_exist() -> void:
	if not Sfx._enabled:
		pass_test("no audio driver: sound files are checked by the importer")
		return
	for s: String in ["win_jingle", "ui_stamp", "medal_gold"]:
		assert_true(Sfx.has(s), s)
