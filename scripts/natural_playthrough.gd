extends SceneTree

const GameStateScript := preload("res://scripts/GameState.gd")

var failures: Array[String] = []
var events: Array[String] = []

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var state = GameStateScript.new()
	root.add_child(state)
	state.reset_game()
	_record(state, "start")

	_place_or_fail(state, "straight_corridor", Vector2i(4, 2), 0, "first tunnel")
	_place_or_fail(state, "digging_room", Vector2i(4, 1), 0, "soil line")
	_place_or_fail(state, "fungus_farm", Vector2i(2, 3), 0, "food line")

	_wait_until_placeable(state, "surface_entrance", Vector2i(6, 4), 0, 520.0)
	_place_or_fail(state, "surface_entrance", Vector2i(6, 4), 0, "surface gate")
	var entrance_time: float = state.elapsed_seconds

	var stage_id := _best_natural_stage(state)
	var start_result: Dictionary = state.start_external_stage(stage_id)
	_assert(bool(start_result.get("ok", false)), "Natural path starts exploration")
	_record(state, "sent workers to %s" % state.external_stages[stage_id].display_name)

	while state.active_external_run.has("id") and failures.is_empty():
		state.simulate_tick(1.0)
		if state.elapsed_seconds > 850.0:
			_fail("Exploration did not resolve inside first-session window")
			break
	var reward_time: float = state.elapsed_seconds
	_assert(String(state.last_external_result.get("result", "")) in ["success", "partial"], "Natural exploration returns a reward-bearing result")
	_assert(state.reward_choices.size() == 3, "Natural exploration presents three reward choices")
	var chosen_index := _choose_support_reward(state)
	_assert(chosen_index >= 0, "Natural reward set contains Storage, Nursery, or Sorter support")
	var chosen_card := String(state.reward_choices[chosen_index]) if chosen_index >= 0 else ""
	var pressure_before: Dictionary = state.city_pressure.duplicate(true)
	var choose_result: Dictionary = state.choose_reward(chosen_index)
	_assert(bool(choose_result.get("ok", false)), "Natural path chooses a real reward card")
	_record(state, "chose %s" % chosen_card)

	var placement := _reward_placement(chosen_card)
	_wait_until_placeable(state, chosen_card, Vector2i(placement.get("x", 6), placement.get("y", 3)), int(placement.get("r", 0)), 300.0)
	var support_before := _support_metric(state, chosen_card)
	_place_or_fail(state, chosen_card, Vector2i(placement.get("x", 6), placement.get("y", 3)), int(placement.get("r", 0)), "reward module")
	var support_time: float = state.elapsed_seconds
	for i in range(240):
		state.simulate_tick(1.0)
	var support_after := _support_metric(state, chosen_card)
	var total_time: float = state.elapsed_seconds
	_assert(total_time >= 600.0 and total_time <= 900.0, "Natural path covers a 10-15 minute first-session slice")
	_assert(_support_metric_improved(chosen_card, support_before, support_after), "Chosen reward changes its target pressure after continued play")
	_record(state, "continued after reward")

	if failures.is_empty():
		print("Natural playthrough passed.")
		print("Evidence: entrance %.0fs, reward %.0fs, installed %s at %.0fs, total %.0fs." % [entrance_time, reward_time, chosen_card, support_time, total_time])
		print("Pressure before reward: %s" % str(pressure_before))
		print("Support metric before/after: %s -> %s" % [str(support_before), str(support_after)])
		for event in events:
			print(event)
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		for event in events:
			print(event)
		quit(1)

func _wait_until_placeable(state, card_id: String, origin: Vector2i, rotation: int, timeout: float) -> void:
	var start_time := float(state.elapsed_seconds)
	while not bool(state.can_place_module(card_id, origin, rotation).get("ok", false)):
		state.simulate_tick(1.0)
		if float(state.elapsed_seconds) - start_time > timeout:
			_fail("Timed out waiting to place %s: %s" % [card_id, state.can_place_module(card_id, origin, rotation).get("reason", "unknown")])
			return

func _place_or_fail(state, card_id: String, origin: Vector2i, rotation: int, label: String) -> void:
	if not failures.is_empty():
		return
	var result: Dictionary = state.request_place_module(card_id, origin, rotation)
	_assert(bool(result.get("ok", false)), "Natural path places %s (%s)" % [card_id, label])
	_record(state, "placed %s" % card_id)

func _best_natural_stage(state) -> String:
	var best_id := "near_debris"
	var best_score := -999.0
	for stage_id in state.external_stages.keys():
		var stage = state.external_stages[stage_id]
		if int(state.resources["food"]) < stage.food_cost:
			continue
		if int(state.workers["total"]) < stage.worker_required:
			continue
		var preview: Dictionary = state.external_stage_preview(stage_id)
		var score := float(preview.get("success_chance", 0.0)) - float(stage.risk) * 0.4
		if score > best_score:
			best_score = score
			best_id = String(stage_id)
	return best_id

func _choose_support_reward(state) -> int:
	var pressure_key := _highest_pressure_key(state)
	var priority: Array[String] = []
	match pressure_key:
		"capacity_pressure":
			priority = ["storage_chamber", "sorter", "nursery"]
		"worker_pressure":
			priority = ["nursery", "storage_chamber", "sorter"]
		"throughput_pressure":
			priority = ["sorter", "storage_chamber", "nursery"]
		_:
			priority = ["storage_chamber", "nursery", "sorter"]
	for card_id in priority:
		var index: int = state.reward_choices.find(card_id)
		if index >= 0:
			return index
	return -1

func _highest_pressure_key(state) -> String:
	var best_key := "food_pressure"
	var best_value := -1.0
	for key in state.city_pressure.keys():
		var value := float(state.city_pressure[key])
		if value > best_value:
			best_value = value
			best_key = String(key)
	return best_key

func _reward_placement(card_id: String) -> Dictionary:
	match card_id:
		"nursery":
			return {"x": 2, "y": 5, "r": 0}
		"storage_chamber":
			return {"x": 6, "y": 3, "r": 0}
		"sorter":
			return {"x": 6, "y": 3, "r": 0}
	return {"x": 6, "y": 3, "r": 0}

func _support_metric(state, card_id: String) -> Dictionary:
	state.simulate_tick(0.0)
	match card_id:
		"storage_chamber":
			return {
				"capacity_pressure": float(state.city_pressure.get("capacity_pressure", 0.0)),
				"food_cap": int(state.capacities["food"]),
				"soil_cap": int(state.capacities["soil"]),
				"waste": int(state.overflow_waste["food"]) + int(state.overflow_waste["soil"]),
			}
		"nursery":
			return {
				"worker_pressure": float(state.city_pressure.get("worker_pressure", 0.0)),
				"satisfaction": float(state.workers["satisfaction"]),
				"workers": int(state.workers["total"]),
			}
		"sorter":
			return {
				"throughput_pressure": float(state.city_pressure.get("throughput_pressure", 0.0)),
				"worst_load": _worst_route_load(state),
			}
	return state.city_pressure.duplicate(true)

func _support_metric_improved(card_id: String, before: Dictionary, after: Dictionary) -> bool:
	match card_id:
		"storage_chamber":
			return int(after.get("food_cap", 0)) > int(before.get("food_cap", 0)) and float(after.get("capacity_pressure", 1.0)) <= float(before.get("capacity_pressure", 1.0))
		"nursery":
			return int(after.get("workers", 0)) > int(before.get("workers", 0)) and float(after.get("satisfaction", 0.0)) >= float(before.get("satisfaction", 0.0))
		"sorter":
			return float(after.get("worst_load", 99.0)) < float(before.get("worst_load", 0.0)) or float(after.get("throughput_pressure", 1.0)) <= float(before.get("throughput_pressure", 1.0))
	return false

func _worst_route_load(state) -> float:
	var worst := 0.0
	for route in state.transport_routes.values():
		worst = max(worst, float(route.get("load_ratio", 0.0)))
	return worst

func _record(state, label: String) -> void:
	events.append("%04ds %s | F%d/%d S%d/%d W%d/%d flow %d%%" % [
		int(state.elapsed_seconds),
		label,
		int(state.resources["food"]),
		int(state.capacities["food"]),
		int(state.resources["soil"]),
		int(state.capacities["soil"]),
		int(state.workers["free"]),
		int(state.workers["total"]),
		int(round(float(state.workers["satisfaction"]) * 100.0)),
	])

func _assert(condition: bool, message: String) -> void:
	if not condition:
		_fail(message)

func _fail(message: String) -> void:
	if not failures.has(message):
		failures.append(message)
