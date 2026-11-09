# SPDX-FileCopyrightText: 2026 Siegefall contributors
# SPDX-License-Identifier: MIT
class_name ShareCode
extends RefCounted
## Short text codes for sharing levels (docs/LEVEL_FORMAT.md §5).
##
##   SF1.<payload>.<check>      (dots: base64url itself uses "-" and "_")
##
## payload = base64url(DEFLATE(compact JSON)), where the compact JSON stores
## the level as integer arrays (centimetres, tenths of a degree, indices into
## fixed tables). check = first 4 bytes of SHA-256(payload) in base64url, to
## catch typos and truncated pastes. "SF1" is the format tag; future versions
## keep decoding older codes. The author's par (their fewest shots in
## test-play) travels with the code; solutions never do.

const TAG: String = "SF1"
const MAX_CODE_CHARS: int = 64000
const MAX_JSON_BYTES: int = 262144
const SHAPES: Array[String] = ["rect", "circle", "tri", "wedge", "poly"]
const MATERIALS: Array[String] = ["wood", "stone", "glass", "ice", "iron", "thatch", "cloth"]
const ENEMIES: Array[String] = ["king", "queen", "knight", "hostage"]
const TIMES: Array[String] = ["dawn", "morning", "noon", "afternoon", "golden", "dusk", "night"]
const STYLES: Array[String] = ["grass", "sand", "snow", "rock"]


static func encode(level: Dictionary) -> String:
	var bytes: PackedByteArray = JSON.stringify(_compact(level)).to_utf8_buffer()
	var payload: String = _b64url(bytes.compress(FileAccess.COMPRESSION_DEFLATE))
	return "%s.%s.%s" % [TAG, payload, _check(payload)]


## Returns {"ok": bool, "level": Dictionary, "error": String}.
static func decode(code: String) -> Dictionary:
	var clean: String = ""
	for c: String in code.strip_edges():
		if not c in [" ", "\n", "\r", "\t"]:
			clean += c
	if clean.length() > MAX_CODE_CHARS:
		return _fail(I18n.tr_noop("That code is too long."))
	var parts: PackedStringArray = clean.split(".")
	if parts.size() != 3 or parts[0] != TAG:
		return _fail(I18n.tr_noop("That doesn't look like a castle code (they start with SF1.)."))
	var payload: String = parts[1]
	if payload.length() < 8 or not _is_b64url(payload) or not _is_b64url(parts[2]):
		return _fail(I18n.tr_noop("The code is damaged or incomplete. Copy it again?"))
	if _check(payload) != parts[2]:
		return _fail(I18n.tr_noop("The code is damaged or incomplete. Copy it again?"))
	var raw: PackedByteArray = _unb64url(payload)
	if raw.is_empty():
		return _fail(I18n.tr_noop("The code is damaged."))
	var json_bytes: PackedByteArray = raw.decompress_dynamic(
		MAX_JSON_BYTES, FileAccess.COMPRESSION_DEFLATE
	)
	if json_bytes.is_empty():
		return _fail(I18n.tr_noop("The code is damaged or too large."))
	var parsed: Variant = JSON.parse_string(json_bytes.get_string_from_utf8())
	if not parsed is Dictionary:
		return _fail(I18n.tr_noop("The code is damaged."))
	var level: Dictionary = _expand(parsed)
	if level.is_empty():
		return _fail(I18n.tr_noop("The code uses a newer format than this version of the game."))
	return {"ok": true, "level": level, "error": ""}


static func _fail(msg: String) -> Dictionary:
	return {"ok": false, "level": {}, "error": msg}


# ------------------------------------------------------------ compaction ---
static func _cm(v: float) -> int:
	return roundi(v * 100.0)


static func _compact(lv: Dictionary) -> Dictionary:
	var world: Dictionary = lv.get("world", {})
	var treb: Dictionary = lv.get("trebuchet", {})
	var terrain: Array = []
	for t: Variant in lv.get("terrain", []):
		var td: Dictionary = t
		var flat: Array = [maxi(0, STYLES.find(str(td.get("style", "grass"))))]
		for p: Variant in td.get("points", []):
			var pt: Vector2 = Units.vec2(p)
			flat.append_array([_cm(pt.x), _cm(pt.y)])
		terrain.append(flat)
	var blocks: Array = []
	for b: Variant in lv.get("blocks", []):
		var bd: Dictionary = b
		var shape: String = str(bd.get("shape", "rect"))
		var pos: Vector2 = Units.vec2(bd.get("pos"))
		var row: Array = [
			maxi(0, SHAPES.find(shape)),
			maxi(0, MATERIALS.find(str(bd.get("material", "wood")))),
			_cm(pos.x),
			_cm(pos.y),
			roundi(float(bd.get("rot", 0.0)) * 10.0),
			1 if bool(bd.get("static", false)) else 0,
		]
		match shape:
			"circle":
				row.append(_cm(float(bd.get("radius", 0.5))))
			"poly":
				for p: Variant in bd.get("points", []):
					var pt: Vector2 = Units.vec2(p)
					row.append_array([_cm(pt.x), _cm(pt.y)])
			_:
				var size: Vector2 = Units.vec2(bd.get("size"), Vector2.ONE)
				row.append_array([_cm(size.x), _cm(size.y)])
		blocks.append(row)
	var enemies: Array = []
	for e: Variant in lv.get("enemies", []):
		var ed: Dictionary = e
		var pos: Vector2 = Units.vec2(ed.get("pos"))
		enemies.append(
			[
				maxi(0, ENEMIES.find(str(ed.get("type", "king")))),
				_cm(pos.x),
				_cm(pos.y),
				1 if bool(ed.get("flip", false)) else 0
			]
		)
	var out: Dictionary = {
		"v": 1,
		"n": str(lv.get("name", "")),
		"g": str(lv.get("grievance", "")),
		"t": maxi(0, TIMES.find(str(lv.get("time_of_day", "noon")))),
		"r": str(lv.get("realm", "greenmantle")),
		"w": [_cm(float(world.get("right", 50.0))), _cm(float(world.get("kill_y", -10.0)))],
		"k": [_cm(float(treb.get("x", 0.0))), _cm(float(treb.get("y", 0.0)))],
		"tr": terrain,
		"b": blocks,
		"e": enemies,
	}
	var par: Variant = lv.get("par")
	if par is Dictionary and not (par as Dictionary).is_empty():
		var pd: Dictionary = par
		out["p"] = [int(pd.get("gold", 1)), int(pd.get("silver", 2)), int(pd.get("bronze", 4))]
	return out


static func _m(v: Variant) -> float:
	return float(v) / 100.0


static func _pick(table: Array[String], i: Variant) -> String:
	var n: int = int(i)
	return table[n] if n >= 0 and n < table.size() else table[0]


static func _expand(c: Dictionary) -> Dictionary:
	if int(c.get("v", 0)) != 1:
		return {}
	var w: Array = c.get("w", [5000, -1000])
	var k: Array = c.get("k", [0, 0])
	var terrain: Array = []
	for t: Variant in c.get("tr", []):
		var ta: Array = t
		if ta.is_empty():
			continue
		var pts: Array = []
		var i: int = 1
		while i + 1 < ta.size():
			pts.append([_m(ta[i]), _m(ta[i + 1])])
			i += 2
		terrain.append({"points": pts, "style": _pick(STYLES, ta[0])})
	var blocks: Array = []
	for b: Variant in c.get("b", []):
		var ba: Array = b
		if ba.size() < 7:
			continue
		var shape: String = _pick(SHAPES, ba[0])
		var bd: Dictionary = {
			"shape": shape,
			"material": _pick(MATERIALS, ba[1]),
			"pos": [_m(ba[2]), _m(ba[3])],
		}
		if int(ba[4]) != 0:
			bd["rot"] = float(ba[4]) / 10.0
		if int(ba[5]) != 0:
			bd["static"] = true
		match shape:
			"circle":
				bd["radius"] = _m(ba[6])
			"poly":
				var pts: Array = []
				var i: int = 6
				while i + 1 < ba.size():
					pts.append([_m(ba[i]), _m(ba[i + 1])])
					i += 2
				bd["points"] = pts
			_:
				if ba.size() >= 8:
					bd["size"] = [_m(ba[6]), _m(ba[7])]
		blocks.append(bd)
	var enemies: Array = []
	for e: Variant in c.get("e", []):
		var ea: Array = e
		if ea.size() < 3:
			continue
		var ed: Dictionary = {"type": _pick(ENEMIES, ea[0]), "pos": [_m(ea[1]), _m(ea[2])]}
		if ea.size() > 3 and int(ea[3]) != 0:
			ed["flip"] = true
		enemies.append(ed)
	var name: String = str(c.get("n", "")).left(60)
	var level: Dictionary = {
		"format": "level",
		"version": 1,
		"id": "shared-" + slug(name if not name.is_empty() else "castle"),
		"name": name if not name.is_empty() else "Shared castle",
		"grievance": str(c.get("g", "")).left(200),
		"time_of_day": _pick(TIMES, c.get("t", 2)),
		"realm": str(c.get("r", "greenmantle")),
		"world": {"right": _m(w[0]), "kill_y": _m(w[1])},
		"trebuchet": {"x": _m(k[0]), "y": _m(k[1])},
		"terrain": terrain,
		"blocks": blocks,
		"enemies": enemies,
	}
	var p: Variant = c.get("p")
	if p is Array and (p as Array).size() == 3:
		var g: int = clampi(int(p[0]), 1, 99)
		var sv: int = clampi(int(p[1]), g, 99)
		level["par"] = {"gold": g, "silver": sv, "bronze": clampi(int(p[2]), sv, 99)}
	return level


## Lower-case letters, digits and dashes (ids and file names).
static func slug(s: String) -> String:
	var out: String = ""
	for ch: String in s.to_lower():
		if (ch >= "a" and ch <= "z") or (ch >= "0" and ch <= "9"):
			out += ch
		elif not out.ends_with("-"):
			out += "-"
	out = out.strip_edges().trim_prefix("-").trim_suffix("-").left(40)
	return out if not out.is_empty() else "castle"


# ---------------------------------------------------------------- base64 ---
static func _b64url(b: PackedByteArray) -> String:
	return Marshalls.raw_to_base64(b).replace("+", "-").replace("/", "_").replace("=", "")


static func _unb64url(s: String) -> PackedByteArray:
	var t: String = s.replace("-", "+").replace("_", "/")
	while t.length() % 4 != 0:
		t += "="
	return Marshalls.base64_to_raw(t)


static func _is_b64url(s: String) -> bool:
	if s.is_empty():
		return false
	for c: String in s:
		var ok: bool = (c >= "A" and c <= "Z") or (c >= "a" and c <= "z") or (c >= "0" and c <= "9")
		if not ok and c != "-" and c != "_":
			return false
	return true


static func _check(payload: String) -> String:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(payload.to_utf8_buffer())
	return _b64url(ctx.finish().slice(0, 4))
