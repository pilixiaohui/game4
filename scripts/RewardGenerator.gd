extends RefCounted
class_name RewardGenerator

const StableRulesScript := preload("res://scripts/StableRules.gd")

static func generate(stage, result: String, module_defs: Dictionary, city_pressure: Dictionary, draw_count: int) -> Dictionary:
	var choices: Array[String] = []
	var context: Dictionary = {}
	var pressure_key := StableRulesScript.highest_pressure_key(city_pressure)
	var pool := _expanded_reward_pool(stage, module_defs, pressure_key)
	_add_best_reward_for_pressure(choices, context, pool, module_defs, pressure_key)
	_add_best_reward_for_tags(choices, context, pool, module_defs, stage.tags, "Matches the outside site theme")
	_add_weighted_reward(choices, context, pool, module_defs, stage, city_pressure, "%s:%s:%d" % [stage.id, result, draw_count])
	if result == "partial" and choices.size() > 0:
		var card_id := choices[0]
		context[card_id] = "%s after a partial return" % String(context.get(card_id, "Stabilizes the city"))
	for card_id in pool:
		if choices.size() >= 3:
			break
		if module_defs.has(card_id) and not choices.has(card_id):
			choices.append(card_id)
			context[card_id] = "Keeps options open"
	_break_fixed_reward_set(choices, context, stage.card_reward_pool, pool, module_defs, pressure_key)
	return {
		"choices": choices,
		"context": context,
		"policy": "pressure_theme_weighted",
		"pressure_key": pressure_key,
	}

static func _expanded_reward_pool(stage, module_defs: Dictionary, pressure_key: String) -> Array[String]:
	var pool: Array[String] = []
	for card_id in stage.card_reward_pool:
		_append_unique_card(pool, module_defs, String(card_id))
	for card_id in _sorted_keys(module_defs):
		var data = module_defs[card_id]
		if data.rarity == "starter" or data.category == "core":
			continue
		var matches_stage := false
		for tag in data.reward_tags:
			if stage.tags.has(tag):
				matches_stage = true
		for tag in data.tags:
			if stage.tags.has(tag):
				matches_stage = true
		if matches_stage:
			_append_unique_card(pool, module_defs, String(card_id))
	for card_id in _sorted_keys(module_defs):
		var data = module_defs[card_id]
		if data.rarity == "starter" or data.category == "core":
			continue
		if data.solves_pressure.has(pressure_key):
			_append_unique_card(pool, module_defs, String(card_id))
			continue
		for tag in data.reward_tags:
			if StableRulesScript.tag_matches_pressure(String(tag), pressure_key):
				_append_unique_card(pool, module_defs, String(card_id))
	return pool

static func _append_unique_card(pool: Array[String], module_defs: Dictionary, card_id: String) -> void:
	if module_defs.has(card_id) and not pool.has(card_id):
		pool.append(card_id)

static func _add_best_reward_for_pressure(choices: Array[String], context: Dictionary, pool: Array[String], module_defs: Dictionary, pressure_key: String) -> void:
	var best_id := ""
	var best_score := -9999.0
	for card_id in pool:
		if not module_defs.has(card_id) or choices.has(card_id):
			continue
		var data = module_defs[card_id]
		var score := float(data.solves_pressure.get(pressure_key, 0)) * 3.0
		for tag in data.reward_tags:
			if StableRulesScript.tag_matches_pressure(String(tag), pressure_key):
				score += 1.0
		if score > best_score or (is_equal_approx(score, best_score) and String(card_id) < best_id):
			best_score = score
			best_id = card_id
	if best_id != "":
		choices.append(best_id)
		context[best_id] = StableRulesScript.pressure_reason(pressure_key)

static func _add_best_reward_for_tags(choices: Array[String], context: Dictionary, pool: Array[String], module_defs: Dictionary, tags: Array[String], reason: String) -> void:
	var best_id := ""
	var best_score := -9999.0
	for card_id in pool:
		if not module_defs.has(card_id) or choices.has(card_id):
			continue
		var data = module_defs[card_id]
		var score := 0.0
		for tag in data.reward_tags:
			if tags.has(tag):
				score += 2.0
		for tag in data.tags:
			if tags.has(tag):
				score += 1.0
		if score > best_score or (is_equal_approx(score, best_score) and String(card_id) < best_id):
			best_score = score
			best_id = card_id
	if best_id != "":
		choices.append(best_id)
		context[best_id] = reason

static func _add_weighted_reward(choices: Array[String], context: Dictionary, pool: Array[String], module_defs: Dictionary, stage_data, city_pressure: Dictionary, seed: String) -> void:
	var weighted: Array[Dictionary] = []
	var total := 0.0
	var pressure_key := StableRulesScript.highest_pressure_key(city_pressure)
	for card_id in pool:
		if not module_defs.has(card_id) or choices.has(card_id):
			continue
		var data = module_defs[card_id]
		var weight := 1.0
		for tag in data.reward_tags:
			weight += float(stage_data.reward_weights.get(tag, 0.0))
		for pressure in StableRulesScript.PRESSURE_ORDER:
			if data.solves_pressure.has(pressure):
				weight += float(city_pressure.get(pressure, 0.0)) * float(stage_data.pressure_weight_bonus.get(pressure, 0.0))
		weight += float(data.solves_pressure.get(pressure_key, 0)) * 2.0
		total += weight
		weighted.append({"id": card_id, "ceiling": total})
	if weighted.is_empty():
		return
	var roll := StableRulesScript.stable_roll(seed) * total
	for item in weighted:
		if roll <= float(item["ceiling"]):
			var card_id := String(item["id"])
			choices.append(card_id)
			context[card_id] = "Weighted by current nest pressure"
			return

static func _break_fixed_reward_set(choices: Array[String], context: Dictionary, base_pool: Array[String], expanded_pool: Array[String], module_defs: Dictionary, pressure_key: String) -> void:
	var base_trio: Array[String] = []
	for card_id in base_pool:
		if base_trio.size() >= 3:
			break
		base_trio.append(String(card_id))
	if choices.size() != 3 or not _same_card_set(choices, base_trio):
		return
	var replacement := _best_non_base_reward(choices, base_trio, expanded_pool, module_defs, pressure_key)
	if replacement == "":
		return
	var removed := String(choices.pop_back())
	context.erase(removed)
	choices.append(replacement)
	context[replacement] = "%s; changes this site's usual choices" % StableRulesScript.pressure_reason(pressure_key)

static func _best_non_base_reward(choices: Array[String], base_trio: Array[String], expanded_pool: Array[String], module_defs: Dictionary, pressure_key: String) -> String:
	var best_id := ""
	var best_score := -9999.0
	for card_id in expanded_pool:
		if base_trio.has(card_id) or choices.has(card_id):
			continue
		var data = module_defs[card_id]
		var score := float(data.solves_pressure.get(pressure_key, 0)) * 3.0
		for tag in data.reward_tags:
			if StableRulesScript.tag_matches_pressure(String(tag), pressure_key):
				score += 1.0
		if score > best_score or (is_equal_approx(score, best_score) and String(card_id) < best_id):
			best_score = score
			best_id = card_id
	return best_id

static func _same_card_set(left: Array[String], right: Array[String]) -> bool:
	if left.size() != right.size():
		return false
	for card_id in left:
		if not right.has(card_id):
			return false
	return true

static func _sorted_keys(dict: Dictionary) -> Array[String]:
	var result: Array[String] = []
	for key in dict.keys():
		result.append(String(key))
	result.sort()
	return result
