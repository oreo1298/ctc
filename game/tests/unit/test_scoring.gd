# SPDX-FileCopyrightText: 2026 Siegefall contributors
# SPDX-License-Identifier: MIT
extends GutTest

const PAR: Dictionary = {"gold": 1, "silver": 2, "bronze": 4}


func test_medal_boundaries() -> void:
	assert_eq(Scoring.medal_for(1, PAR), Scoring.Medal.GOLD)
	assert_eq(Scoring.medal_for(2, PAR), Scoring.Medal.SILVER)
	assert_eq(Scoring.medal_for(3, PAR), Scoring.Medal.BRONZE)
	assert_eq(Scoring.medal_for(4, PAR), Scoring.Medal.BRONZE)
	assert_eq(Scoring.medal_for(5, PAR), Scoring.Medal.NONE)
	assert_eq(Scoring.medal_for(0, PAR), Scoring.Medal.NONE, "no shots, no medal")


func test_wider_par() -> void:
	var par: Dictionary = {"gold": 2, "silver": 3, "bronze": 6}
	assert_eq(Scoring.medal_for(2, par), Scoring.Medal.GOLD)
	assert_eq(Scoring.medal_for(6, par), Scoring.Medal.BRONZE)


func test_override_wins_over_bot_par() -> void:
	var lv: Dictionary = {"par": PAR, "par_override": {"gold": 3, "silver": 4, "bronze": 5}}
	assert_eq(int(Scoring.effective_par(lv)["gold"]), 3)
	lv["par_override"] = null
	assert_eq(int(Scoring.effective_par(lv)["gold"]), 1)
	assert_eq(int(Scoring.effective_par({})["bronze"]), 4, "sane default")


func test_medal_keys_round_trip() -> void:
	for m: Scoring.Medal in [
		Scoring.Medal.NONE, Scoring.Medal.BRONZE, Scoring.Medal.SILVER, Scoring.Medal.GOLD
	]:
		assert_eq(Scoring.medal_from_key(Scoring.medal_key(m)), m)
	assert_eq(Scoring.medal_from_key("platinum"), Scoring.Medal.NONE)


func test_better() -> void:
	assert_true(Scoring.better(Scoring.Medal.GOLD, Scoring.Medal.SILVER))
	assert_false(Scoring.better(Scoring.Medal.BRONZE, Scoring.Medal.BRONZE))


func test_score_rewards_spare_shots() -> void:
	assert_eq(Scoring.final_score(500, 1, PAR), 3500)
	assert_eq(Scoring.final_score(500, 9, PAR), 500)
	assert_eq(Scoring.final_score(-2000, 9, PAR), 0, "never negative")


func test_block_points_rounding() -> void:
	assert_eq(Scoring.block_points(60, 0.5), 30)
	assert_eq(Scoring.block_points(120, 2.0), 240)
	assert_eq(Scoring.block_points(10, 0.01), 5, "minimum 5 points")
