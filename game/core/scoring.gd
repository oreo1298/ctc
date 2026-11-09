# SPDX-FileCopyrightText: 2026 Siegefall contributors
# SPDX-License-Identifier: MIT
class_name Scoring
extends RefCounted
## Medal and points rules (docs/DESIGN.md §3.6). Pure functions.

enum Medal { NONE, BRONZE, SILVER, GOLD }

const MEDAL_KEYS: Array[String] = ["none", "bronze", "silver", "gold"]


## Medal for winning in `shots` given par {gold, silver, bronze}.
static func medal_for(shots: int, par: Dictionary) -> Medal:
	if shots <= 0:
		return Medal.NONE
	if shots <= int(par.get("gold", 1)):
		return Medal.GOLD
	if shots <= int(par.get("silver", 2)):
		return Medal.SILVER
	if shots <= int(par.get("bronze", 4)):
		return Medal.BRONZE
	return Medal.NONE


static func medal_key(m: Medal) -> String:
	return MEDAL_KEYS[m]


static func medal_from_key(key: String) -> Medal:
	var i: int = MEDAL_KEYS.find(key)
	return Medal.NONE if i < 0 else (i as Medal)


## Is `a` a better medal than `b`?
static func better(a: Medal, b: Medal) -> bool:
	return int(a) > int(b)


## Effective par: a designer override wins over the bot-computed par.
static func effective_par(level: Dictionary) -> Dictionary:
	var over: Variant = level.get("par_override")
	if over is Dictionary:
		return over
	var par: Variant = level.get("par")
	if par is Dictionary:
		return par
	return {"gold": 1, "silver": 2, "bronze": 4}


## Points for destroying a block of `area_m2` square metres of a material
## worth `points_per_m2`.
static func block_points(points_per_m2: int, area_m2: float) -> int:
	return maxi(5, roundi(points_per_m2 * area_m2 / 5.0) * 5)


## Final score: earned points plus a bonus for every shot under bronze par.
static func final_score(points: int, shots: int, par: Dictionary) -> int:
	var spare: int = maxi(0, int(par.get("bronze", 4)) - shots)
	return maxi(0, points + spare * 1000)
