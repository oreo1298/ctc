# SPDX-FileCopyrightText: 2026 Siegefall contributors
# SPDX-License-Identifier: MIT
extends GutTest
## Share codes: compact, checked, and safe to paste from anywhere.


func _level(id: String = "greenmantle-12") -> Dictionary:
	return Data.load_level(id).source


func test_round_trip_keeps_the_castle() -> void:
	for id: String in ["greenmantle-01", "saffron-12", "frostfang-12"]:
		var src: Dictionary = _level(id)
		var code: String = ShareCode.encode(src)
		var r: Dictionary = ShareCode.decode(code)
		assert_true(r["ok"], "%s: %s" % [id, r["error"]])
		var lv: Dictionary = r["level"]
		assert_eq((lv["blocks"] as Array).size(), (src["blocks"] as Array).size(), id)
		assert_eq((lv["enemies"] as Array).size(), (src["enemies"] as Array).size(), id)
		assert_eq(lv["time_of_day"], src["time_of_day"])
		var a: Vector2 = Units.vec2((src["blocks"] as Array)[3]["pos"])
		var b: Vector2 = Units.vec2((lv["blocks"] as Array)[3]["pos"])
		assert_almost_eq(a, b, Vector2(0.006, 0.006), "positions survive to the centimetre")
		var parsed: LevelData = Data.parse_level(lv)
		assert_true(parsed.is_valid(), "; ".join(parsed.errors))
		assert_false(lv.has("solution"), "proofs are not shared")


func test_codes_are_short() -> void:
	var code: String = ShareCode.encode(_level("greenmantle-01"))
	assert_lt(code.length(), 450, "level 1 fits in a short message (%d chars)" % code.length())
	assert_true(code.begins_with("SF1."))


func test_whitespace_and_line_breaks_are_ignored() -> void:
	var code: String = ShareCode.encode(_level("greenmantle-03"))
	var messy: String = "  " + code.substr(0, 40) + "\n" + code.substr(40) + "  \n"
	assert_true(ShareCode.decode(messy)["ok"])


func test_typos_and_truncation_are_caught() -> void:
	var code: String = ShareCode.encode(_level("greenmantle-03"))
	var i: int = 20
	var swapped: String = code.substr(0, i) + ("A" if code[i] != "A" else "B") + code.substr(i + 1)
	assert_false(ShareCode.decode(swapped)["ok"], "one changed character")
	assert_false(ShareCode.decode(code.substr(0, code.length() - 5))["ok"], "truncated")


func test_garbage_is_rejected_politely() -> void:
	for junk: String in [
		"", "hello", "SF1..", "SF1.a.b", "SF9.abc.def", "SF1.!!!!.xxxx", "SF1.AAAAAAAAAA.AAAAAA"
	]:
		var r: Dictionary = ShareCode.decode(junk)
		assert_false(r["ok"], junk)
		assert_ne(r["error"], "")
