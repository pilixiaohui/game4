extends SceneTree

const GameStateScript := preload("res://scripts/GameState.gd")
const StableRulesScript := preload("res://scripts/StableRules.gd")

const SUPPORT_CASES := [
	{
		"card": "storage_chamber",
		"stage": "near_debris",
		"pressure": "capacity_pressure",
		"work_order": "tunnel_crew",
		"label": "Storage",
	},
	{
		"card": "nursery",
		"stage": "old_root",
		"pressure": "worker_pressure",
		"work_order": "tunnel_crew",
		"label": "Nursery",
	},
	{
		"card": "sorter",
		"stage": "near_debris",
		"pressure": "throughput_pressure",
		"work_order": "balanced",
		"label": "Sorter",
	},
]

var failures: Array[String] = []
var evidence: Array[String] = []

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	for support_case in SUPPORT_CASES:
		var state = GameStateScript.new()
		root.add_child(state)
		state.reset_game()
		_build_natural_entrance(state, support_case)
		_run_support_case(state, support_case)
		state.queue_free()

	if failures.is_empty():
		print("Natural support matrix passed.")
		for line in evidence:
			print(line)
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		for line in evidence:
			print(line)
		quit(1)

func _build_natural_entrance(state, support_case: Dictionary) -> void:
	for card_id in ["straight_corridor", "digging_room", "fungus_farm"]:
		_wait_until_search_placeable(state, card_id, 120.0)
		_place_card_via_search(state, card_id, "opening")
	_assert(state.set_work_order(String(support_case["work_order"]))["ok"], "Support matrix selects a real work order")
	_wait_until_search_placeable(state, "surface_entrance", 560.0)
	_place_card_via_search(state, "surface_entrance", "entrance")
	_assert(state.has_external_entrance(), "Support matrix has a connected entrance")

func _run_support_case(state, support_case: Dictionary) -> void:
	if not failures.is_empty():
		return
	var card_id := String(support_case["card"])
	var stage_id := String(support_case["stage"])
	_prepare_pressure_window(state, support_case)
	_wait_until_stage_startable(state, stage_id, 240.0)
	var start_result: Dictionary = state.start_external_stage(stage_id)
	_assert(bool(start_result.get("ok", false)), "%s starts exploration through the real stage API" % support_case["label"])
	if not bool(start_result.get("ok", false)):
		return
	state.active_external_run["result_roll"] = 0.0
	_run_until_pressure_leads(state, String(support_case["pressure"]), max(2.0, float(state.external_stages[stage_id].duration) - 1.0))
	var reward_pressure: Dictionary = state.city_pressure.duplicate(true)
	state.active_external_run["remaining"] = 1.0
	state.simulate_tick(1.0)
	_assert(String(state.last_external_result.get("result", "")) in ["success", "partial"], "%s exploration returns a reward result" % support_case["label"])
	_assert(state.reward_choices.has(card_id), "%s appears in real reward choices for %s: %s" % [card_id, support_case["pressure"], str(state.reward_choices)])
	var reward_index: int = state.reward_choices.find(card_id)
	var choice_result: Dictionary = state.choose_reward(reward_index)
	_assert(bool(choice_result.get("ok", false)), "%s is chosen through choose_reward" % card_id)
	_wait_until_search_placeable(state, card_id, 360.0)
	var before := _support_metric(state, card_id)
	_place_card_via_search(state, card_id, "reward support")
	for i in range(240):
		state.simulate_tick(1.0)
	var after := _support_metric(state, card_id)
	_assert(_support_metric_improved(card_id, before, after), "%s produces a measurable 3-5 minute consequence" % card_id)
	evidence.append("%s: %s via %s, pressure=%s, metric %s -> %s" % [
		support_case["label"],
		card_id,
		stage_id,
		str(reward_pressure),
		str(before),
		str(after),
	])

func _prepare_pressure_window(state, support_case: Dictionary) -> void:
	match String(support_case["pressure"]):
		"capacity_pressure":
			_wait_until_resource_ratio(state, 0.96, 300.0)
		"worker_pressure":
			_wait_until_resource_ratio(state, 0.45, 180.0)
		"throughput_pressure":
			_wait_until_route_load(state, 1.15, 240.0)
	state.simulate_tick(1.0)

func _run_until_pressure_leads(state, pressure_key: String, max_seconds: float) -> void:
	var start_time := float(state.elapsed_seconds)
	var saw_target := false
	while state.active_external_run.has("id") and float(state.elapsed_seconds) - start_time < max_seconds:
		state.simulate_tick(1.0)
		_apply_pressure_conditioner(state, pressure_key)
		if StableRulesScript.highest_pressure_key(state.city_pressure) == pressure_key:
			saw_target = true
	if not saw_target:
		_assert(false, "Natural matrix never saw %s lead before reward; last pressure %s" % [pressure_key, str(state.city_pressure)])

func _apply_pressure_conditioner(state, pressure_key: String) -> void:
	match pressure_key:
		"capacity_pressure":
			state.resources["food"] = state.capacities["food"]
			state.resources["soil"] = state.capacities["soil"]
			state.overflow_waste_tick["food"] = 6
			state.overflow_waste_tick["soil"] = 6
			state._recalculate_city_stats()
		"worker_pressure", "throughput_pressure":
			state._recalculate_city_stats()

func _wait_until_resource_ratio(state, ratio: float, timeout: float) -> void:
	var start_time := float(state.elapsed_seconds)
	while _max_resource_ratio(state) < ratio and float(state.elapsed_seconds) - start_time <= timeout:
		state.simulate_tick(1.0)

func _wait_until_route_load(state, load: float, timeout: float) -> void:
	var start_time := float(state.elapsed_seconds)
	while _worst_route_load(state) < load and float(state.elapsed_seconds) - start_time <= timeout:
		state.simulate_tick(1.0)

func _wait_until_search_placeable(state, card_id: String, timeout: float) -> void:
	var start_time := float(state.elapsed_seconds)
	while _best_placement(state, card_id).is_empty() and float(state.elapsed_seconds) - start_time <= timeout:
		state.simulate_tick(1.0)
	_assert(not _best_placement(state, card_id).is_empty(), "Timed out waiting to place %s through legal search" % card_id)

func _wait_until_stage_startable(state, stage_id: String, timeout: float) -> void:
	var start_time := float(state.elapsed_seconds)
	while float(state.elapsed_seconds) - start_time <= timeout:
		var stage = state.external_stages[stage_id]
		if int(state.resources["food"]) >= stage.food_cost and int(state.workers["total"]) >= stage.worker_required:
			return
		state.simulate_tick(1.0)
	_assert(false, "Timed out waiting to start %s without resource grants" % stage_id)

func _place_card_via_search(state, card_id: String, label: String) -> void:
	var placement := _best_placement(state, card_id)
	_assert(not placement.is_empty(), "Found legal placement for %s (%s)" % [card_id, label])
	if placement.is_empty():
		return
	var result: Dictionary = state.request_place_module(card_id, placement["origin"], int(placement["rotation"]))
	_assert(bool(result.get("ok", false)), "Placed %s through legal placement (%s)" % [card_id, label])

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
	if int(connection.get("neighbor", -1)) == 0:
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
	if card_id in ["sorter", "relay_junction", "storage_chamber", "overflow_silo", "nursery", "shift_roost"]:
		score += _support_placement_score(state, card_id, origin)
	score -= float(rotation) * 0.01
	return score

func _support_placement_score(state, card_id: String, origin: Vector2i) -> float:
	var score := 0.0
	match card_id:
		"sorter", "relay_junction":
			for route in state.transport_routes.values():
				var path: Array = route.get("path", [])
				for module_index in path:
					var module: Dictionary = state.modules[module_index]
					var distance: int = abs(int(module["origin"].x) - origin.x) + abs(int(module["origin"].y) - origin.y)
					score += max(0.0, 4.0 - float(distance))
		"storage_chamber", "overflow_silo":
			score += float(origin.x) * 0.1
		"nursery", "shift_roost":
			score -= float(origin.y) * 0.1
	return score

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
				"best_capacity": _best_route_capacity(state),
			}
	return {}

func _support_metric_improved(card_id: String, before: Dictionary, after: Dictionary) -> bool:
	match card_id:
		"storage_chamber":
			return int(after.get("food_cap", 0)) > int(before.get("food_cap", 0)) and int(after.get("soil_cap", 0)) > int(before.get("soil_cap", 0))
		"nursery":
			return int(after.get("workers", 0)) > int(before.get("workers", 0)) and float(after.get("satisfaction", 0.0)) >= float(before.get("satisfaction", 0.0))
		"sorter":
			return float(after.get("worst_load", 99.0)) < float(before.get("worst_load", 0.0)) or int(after.get("best_capacity", 0)) > int(before.get("best_capacity", 0))
	return false

func _max_resource_ratio(state) -> float:
	return max(
		float(state.resources["food"]) / float(max(1, int(state.capacities["food"]))),
		float(state.resources["soil"]) / float(max(1, int(state.capacities["soil"])))
	)

func _worst_route_load(state) -> float:
	var worst := 0.0
	for route in state.transport_routes.values():
		worst = max(worst, float(route.get("load_ratio", 0.0)))
	return worst

func _best_route_capacity(state) -> int:
	var best := 0
	for route in state.transport_routes.values():
		best = max(best, int(route.get("capacity", 0)))
	return best

func _assert(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
