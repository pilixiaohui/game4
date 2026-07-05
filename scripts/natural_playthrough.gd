extends SceneTree

const GameStateScript := preload("res://scripts/GameState.gd")
const StableRulesScript := preload("res://scripts/StableRules.gd")

const SCENARIO := {
	"name": "first_session_canonical_smoke",
	"opening_cards": ["straight_corridor", "digging_room", "fungus_farm"],
	"stockpile_choice_cards": ["corner_corridor"],
	"entrance_card": "surface_entrance",
	"post_reward_seconds": 240,
	"max_total_seconds": 900,
}

var failures: Array[String] = []
var events: Array[String] = []

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var state = GameStateScript.new()
	root.add_child(state)
	state.reset_game()
	_record(state, "start")

	for card_id in SCENARIO["opening_cards"]:
		_place_card_via_search(state, String(card_id), "opening module")

	var entrance_card := String(SCENARIO["entrance_card"])
	_make_stockpile_choice_before_entrance(state, entrance_card)
	_wait_until_search_placeable(state, entrance_card, 520.0)
	_place_card_via_search(state, entrance_card, "surface gate")
	var entrance_time: float = state.elapsed_seconds

	var stage_id := _best_natural_stage(state)
	_wait_until_stage_startable(state, stage_id, 180.0)
	var start_result: Dictionary = state.start_external_stage(stage_id)
	_assert(bool(start_result.get("ok", false)), "Natural path starts exploration")
	_record(state, "sent workers to %s" % state.external_stages[stage_id].display_name)

	while state.active_external_run.has("id") and failures.is_empty():
		state.simulate_tick(1.0)
		if state.elapsed_seconds > float(SCENARIO["max_total_seconds"]) - float(SCENARIO["post_reward_seconds"]):
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

	_wait_until_search_placeable(state, chosen_card, 300.0)
	var support_before := _support_metric(state, chosen_card)
	_place_card_via_search(state, chosen_card, "reward module")
	var support_time: float = state.elapsed_seconds
	for i in range(int(SCENARIO["post_reward_seconds"])):
		state.simulate_tick(1.0)
	var support_after := _support_metric(state, chosen_card)
	var total_time: float = state.elapsed_seconds
	_assert(total_time >= 600.0 and total_time <= 900.0, "Natural path covers a 10-15 minute first-session slice")
	_assert(_support_metric_improved(chosen_card, support_before, support_after), "Chosen reward changes its target pressure after continued play")
	_record(state, "continued after reward")

	if failures.is_empty():
		print("Canonical natural smoke passed.")
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

func _wait_until_search_placeable(state, card_id: String, timeout: float) -> void:
	var start_time := float(state.elapsed_seconds)
	while _best_placement(state, card_id).is_empty():
		state.simulate_tick(1.0)
		if float(state.elapsed_seconds) - start_time > timeout:
			_fail("Timed out waiting to place %s through legal search" % card_id)
			return

func _wait_until_stage_startable(state, stage_id: String, timeout: float) -> void:
	var start_time := float(state.elapsed_seconds)
	while failures.is_empty():
		var stage = state.external_stages[stage_id]
		if int(state.resources["food"]) >= stage.food_cost and int(state.workers["total"]) >= stage.worker_required:
			return
		state.simulate_tick(1.0)
		if float(state.elapsed_seconds) - start_time > timeout:
			_fail("Timed out waiting to start %s without resource grants" % stage_id)
			return

func _make_stockpile_choice_before_entrance(state, _entrance_card: String) -> void:
	var goal: Dictionary = state.nest_goal_summary()
	var order_id := _stockpile_order_for_gap(state)
	var order_result: Dictionary = state.set_work_order(order_id)
	_assert(bool(order_result.get("ok", false)), "Natural smoke can choose a stockpile work order")
	var choices: Array[String] = []
	for card_id in SCENARIO["stockpile_choice_cards"]:
		var typed_id := String(card_id)
		if state.hand.has(typed_id) and not _best_placement(state, typed_id).is_empty():
			choices.append("optional %s fit" % typed_id)
	_record(state, "stockpile decision: %s | %s | %s" % [
		state.work_order_label(),
		", ".join(choices) if not choices.is_empty() else "no safe side build yet",
		String(goal.get("action", "watch food/soil/flow")),
	])

func _stockpile_order_for_gap(state) -> String:
	var entrance = state.module_defs[String(SCENARIO["entrance_card"])]
	var food_gap: int = max(0, int(entrance.build_cost_food) - int(state.resources.get("food", 0)))
	var soil_gap: int = max(0, int(entrance.build_cost_soil) - int(state.resources.get("soil", 0)))
	var pressure_key := StableRulesScript.highest_pressure_key(state.city_pressure)
	if pressure_key == "throughput_pressure" and abs(food_gap - soil_gap) <= 4:
		return "tunnel_crew"
	if soil_gap > food_gap:
		return "soil_crew"
	if food_gap > soil_gap:
		return "food_crew"
	return "balanced"

func _place_card_via_search(state, card_id: String, label: String) -> void:
	if not failures.is_empty():
		return
	var placement := _best_placement(state, card_id)
	_assert(not placement.is_empty(), "Found legal placement for %s (%s)" % [card_id, label])
	if placement.is_empty():
		return
	var result: Dictionary = state.request_place_module(card_id, placement["origin"], int(placement["rotation"]))
	_assert(bool(result.get("ok", false)), "Natural path places %s (%s)" % [card_id, label])
	_record(state, "placed %s at %s r%d" % [card_id, str(placement["origin"]), int(placement["rotation"])])

func _best_placement(state, card_id: String) -> Dictionary:
	var best := {}
	var best_score := -999999.0
	for x in range(state.GRID_SIZE.x):
		for y in range(state.GRID_SIZE.y):
			for rotation in range(4):
				var origin := Vector2i(x, y)
				var check: Dictionary = state.can_place_module(card_id, origin, rotation)
				if not bool(check.get("ok", false)):
					continue
				var score := _placement_score(state, card_id, origin, rotation, check)
				if score > best_score:
					best_score = score
					best = {"origin": origin, "rotation": rotation, "score": score}
	return best

func _placement_score(state, card_id: String, origin: Vector2i, rotation: int, check: Dictionary) -> float:
	var data = state.module_defs[card_id]
	var score := 0.0
	var connection: Dictionary = check.get("connection", {})
	var neighbor_index := int(connection.get("neighbor", -1))
	if neighbor_index == 0:
		score += 8.0
	var center := Vector2(state.CORE_ORIGIN) + Vector2(1.0, 1.0)
	score -= Vector2(origin).distance_to(center) * 0.1
	if data.category == "corridor":
		score += 4.0
	if data.output_rates.has("soil"):
		score += 6.0 - float(origin.y) * 0.2
	if data.output_rates.has("food"):
		score += 6.0 - absf(float(origin.y - state.CORE_ORIGIN.y)) * 0.2
	if data.external_interface:
		score += 4.0 + float(origin.x) * 0.1
	if card_id in ["sorter", "storage_chamber", "nursery"]:
		score += _support_placement_score(state, card_id, origin)
	score -= float(rotation) * 0.01
	return score

func _support_placement_score(state, card_id: String, origin: Vector2i) -> float:
	var score := 0.0
	match card_id:
		"sorter":
			for route in state.transport_routes.values():
				var path: Array = route.get("path", [])
				for module_index in path:
					var module: Dictionary = state.modules[module_index]
					var distance: int = abs(int(module["origin"].x) - origin.x) + abs(int(module["origin"].y) - origin.y)
					score += max(0.0, 4.0 - float(distance))
		"storage_chamber":
			score += float(origin.x) * 0.1
		"nursery":
			score -= float(origin.y) * 0.1
	return score

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
	var pressure_key := StableRulesScript.highest_pressure_key(state.city_pressure)
	var priority: Array[String] = StableRulesScript.support_priority_for_pressure(pressure_key)
	for card_id in priority:
		var index: int = state.reward_choices.find(card_id)
		if index >= 0:
			return index
	return -1

func _support_metric(state, card_id: String) -> Dictionary:
	state.simulate_tick(0.0)
	match card_id:
		"storage_chamber", "overflow_silo":
			return {
				"capacity_pressure": float(state.city_pressure.get("capacity_pressure", 0.0)),
				"food_cap": int(state.capacities["food"]),
				"soil_cap": int(state.capacities["soil"]),
				"waste": int(state.overflow_waste["food"]) + int(state.overflow_waste["soil"]),
			}
		"nursery", "shift_roost":
			return {
				"worker_pressure": float(state.city_pressure.get("worker_pressure", 0.0)),
				"satisfaction": float(state.workers["satisfaction"]),
				"workers": int(state.workers["total"]),
			}
		"sorter", "relay_junction":
			return {
				"throughput_pressure": float(state.city_pressure.get("throughput_pressure", 0.0)),
				"worst_load": _worst_route_load(state),
			}
	return state.city_pressure.duplicate(true)

func _support_metric_improved(card_id: String, before: Dictionary, after: Dictionary) -> bool:
	match card_id:
		"storage_chamber", "overflow_silo":
			return int(after.get("food_cap", 0)) > int(before.get("food_cap", 0)) and float(after.get("capacity_pressure", 1.0)) <= float(before.get("capacity_pressure", 1.0))
		"nursery", "shift_roost":
			return int(after.get("workers", 0)) > int(before.get("workers", 0)) and float(after.get("satisfaction", 0.0)) >= float(before.get("satisfaction", 0.0))
		"sorter", "relay_junction":
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
