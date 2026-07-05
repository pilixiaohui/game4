extends SceneTree

const GameStateScript := preload("res://scripts/GameState.gd")

const SUPPORT_CASES := [
	{
		"card": "storage_chamber",
		"label": "Storage",
		"setup": [
			{"card": "nursery", "order": "tunnel_crew", "stage": "old_root", "wait": 90},
		],
		"branches": [
			{"order": "tunnel_crew", "stage": "near_debris", "wait": 360},
			{"order": "tunnel_crew", "stage": "loose_soil", "wait": 360},
			{"order": "balanced", "stage": "near_debris", "wait": 480},
			{"order": "balanced", "stage": "loose_soil", "wait": 480},
			{"order": "soil_crew", "stage": "near_debris", "wait": 600},
			{"order": "food_crew", "stage": "near_debris", "wait": 600},
		],
	},
	{
		"card": "nursery",
		"label": "Nursery",
		"branches": [
			{"order": "tunnel_crew", "stage": "old_root", "wait": 90},
		],
	},
	{
		"card": "sorter",
		"label": "Sorter",
		"branches": [
			{"order": "balanced", "stage": "near_debris", "wait": 0},
		],
	},
	{
		"card": "relay_junction",
		"label": "Relay tradeoff",
		"branches": [
			{"order": "balanced", "stage": "near_debris", "wait": 0},
		],
	},
]

var failures: Array[String] = []
var evidence: Array[String] = []

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	for support_case in SUPPORT_CASES:
		var accepted := _find_natural_branch(support_case)
		_assert(accepted, "%s natural branch found without resource grants, roll locks, or private reward generation" % support_case["label"])

	if failures.is_empty():
		print("Natural support matrix passed. Branches use legal placement, natural resources, deterministic unmodified rolls, real stage completion, real reward choices, and choose_reward().")
		for line in evidence:
			print(line)
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		for line in evidence:
			print(line)
		quit(1)

func _find_natural_branch(support_case: Dictionary) -> bool:
	for branch in support_case["branches"]:
		var state = GameStateScript.new()
		root.add_child(state)
		state.reset_game()
		var accepted := _try_branch(state, support_case, Dictionary(branch))
		state.queue_free()
		if accepted:
			return true
	return false

func _try_branch(state, support_case: Dictionary, branch: Dictionary) -> bool:
	for card_id in ["straight_corridor", "digging_room", "fungus_farm"]:
		if not _wait_until_search_placeable(state, card_id, 140.0):
			return false
		if not _place_card_via_search(state, card_id):
			return false
	var opening_order := String(branch["order"])
	if support_case.has("setup") and not Array(support_case["setup"]).is_empty():
		opening_order = String(Dictionary(Array(support_case["setup"])[0])["order"])
	if not bool(state.set_work_order(opening_order).get("ok", false)):
		return false
	if not _wait_until_search_placeable(state, "surface_entrance", 620.0):
		return false
	if not _place_card_via_search(state, "surface_entrance"):
		return false
	for setup_branch in support_case.get("setup", []):
		if not _run_reward_branch(state, Dictionary(setup_branch), "setup"):
			return false
	return _run_reward_branch(state, branch, String(support_case["label"]), String(support_case["card"]))

func _run_reward_branch(state, branch: Dictionary, label: String, required_card_id: String = "") -> bool:
	var order_id := String(branch["order"])
	var stage_id := String(branch["stage"])
	var wait_seconds := int(branch["wait"])
	if not bool(state.set_work_order(order_id).get("ok", false)):
		return false
	for i in range(wait_seconds):
		state.simulate_tick(1.0)
	if not _wait_until_stage_startable(state, stage_id, 300.0):
		return false
	var start_result: Dictionary = state.start_external_stage(stage_id)
	if not bool(start_result.get("ok", false)):
		return false
	var run_roll := float(state.active_external_run.get("result_roll", 1.0))
	var run_chance := float(state.active_external_run.get("success_chance", 0.0))
	while state.active_external_run.has("id"):
		state.simulate_tick(1.0)
	if not (String(state.last_external_result.get("result", "")) in ["success", "partial"]):
		return false
	var card_id := required_card_id
	if card_id == "":
		card_id = String(branch["card"])
	if not state.reward_choices.has(card_id):
		return false
	var reward_choices := _typed_string_array(state.reward_choices)
	var reward_index: int = state.reward_choices.find(card_id)
	if not bool(state.choose_reward(reward_index).get("ok", false)):
		return false
	if not _wait_until_search_placeable(state, card_id, 720.0):
		return false
	var before := _support_metric(state, card_id)
	if not _place_card_via_search(state, card_id):
		return false
	for i in range(240):
		state.simulate_tick(1.0)
	var after := _support_metric(state, card_id)
	if not _support_metric_improved(card_id, before, after):
		return false
	evidence.append("%s: card=%s order=%s stage=%s wait=%ds result=%s roll=%.3f chance=%.3f choices=%s metric %s -> %s" % [
		label,
		card_id,
		order_id,
		stage_id,
		wait_seconds,
		String(state.last_external_result.get("result", "")),
		run_roll,
		run_chance,
		str(reward_choices),
		str(before),
		str(after),
	])
	return true

func _wait_until_search_placeable(state, card_id: String, timeout: float) -> bool:
	var start_time := float(state.elapsed_seconds)
	while _best_placement(state, card_id).is_empty() and float(state.elapsed_seconds) - start_time <= timeout:
		state.simulate_tick(1.0)
	return not _best_placement(state, card_id).is_empty()

func _wait_until_stage_startable(state, stage_id: String, timeout: float) -> bool:
	var start_time := float(state.elapsed_seconds)
	while float(state.elapsed_seconds) - start_time <= timeout:
		var stage = state.external_stages[stage_id]
		if int(state.resources["food"]) >= stage.food_cost and int(state.workers["total"]) >= stage.worker_required:
			return true
		state.simulate_tick(1.0)
	return false

func _place_card_via_search(state, card_id: String) -> bool:
	var placement := _best_placement(state, card_id)
	if placement.is_empty():
		return false
	return bool(state.request_place_module(card_id, placement["origin"], int(placement["rotation"])).get("ok", false))

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
				"best_capacity": _best_route_capacity(state),
			}
	return {}

func _support_metric_improved(card_id: String, before: Dictionary, after: Dictionary) -> bool:
	match card_id:
		"storage_chamber", "overflow_silo":
			return int(after.get("food_cap", 0)) > int(before.get("food_cap", 0)) and int(after.get("soil_cap", 0)) > int(before.get("soil_cap", 0))
		"nursery", "shift_roost":
			return int(after.get("workers", 0)) > int(before.get("workers", 0)) and float(after.get("satisfaction", 0.0)) >= float(before.get("satisfaction", 0.0))
		"sorter", "relay_junction":
			return float(after.get("worst_load", 99.0)) < float(before.get("worst_load", 0.0)) or int(after.get("best_capacity", 0)) > int(before.get("best_capacity", 0))
	return false

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

func _typed_string_array(values: Array[String]) -> Array[String]:
	var result: Array[String] = []
	for value in values:
		result.append(String(value))
	return result

func _assert(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
