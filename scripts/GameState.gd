extends Node
class_name GameState

signal resource_changed(resources: Dictionary, capacities: Dictionary, workers: Dictionary)
signal hand_changed(hand: Array[String])
signal module_placed(module_state: Dictionary)
signal module_status_changed(module_state: Dictionary)
signal external_run_started(run_state: Dictionary)
signal external_run_finished(run_state: Dictionary)
signal reward_choice_ready(cards: Array[String])
signal reward_chosen(card_id: String)
signal feedback(message: String)

const ModuleDataScript := preload("res://scripts/data/ModuleData.gd")
const ExternalStageDataScript := preload("res://scripts/data/ExternalStageData.gd")

const GRID_SIZE := Vector2i(10, 8)
const CORE_ORIGIN := Vector2i(4, 3)
const MAX_HAND := 7
const MODULE_CATALOG_PATH := "res://data/modules.json"
const EXTERNAL_STAGE_CATALOG_PATH := "res://data/external_stages.json"

var module_defs: Dictionary = {}
var external_stages: Dictionary = {}
var resources = {"food": 20, "soil": 20}
var capacities = {"food": 50, "soil": 50}
var workers = {"total": 6, "demand": 0, "exploring": 0, "free": 6, "satisfaction": 1.0}
var hand: Array[String] = []
var modules: Array[Dictionary] = []
var excavated: Dictionary = {}
var occupied: Dictionary = {}
var reward_choices: Array[String] = []
var reward_choice_context: Dictionary = {}
var active_external_run: Dictionary = {}
var last_external_result: Dictionary = {}
var city_pressure: Dictionary = {}
var transport_routes: Dictionary = {}
var overflow_waste := {"food": 0, "soil": 0}
var overflow_waste_tick := {"food": 0, "soil": 0}
var frontier_cells: Dictionary = {}
var draw_count: int = 0
var elapsed_seconds: float = 0.0
var catalog_errors: Array[String] = []

func _ready() -> void:
	if module_defs.is_empty():
		reset_game()

func reset_game() -> void:
	_build_catalogs()
	resources = {"food": 20, "soil": 20}
	capacities = {"food": 50, "soil": 50}
	workers = {"total": 6, "demand": 0, "exploring": 0, "free": 6, "satisfaction": 1.0}
	hand = [
		"straight_corridor",
		"digging_room",
		"fungus_farm",
		"surface_entrance",
		"corner_corridor",
	]
	modules.clear()
	excavated.clear()
	occupied.clear()
	reward_choices.clear()
	reward_choice_context.clear()
	active_external_run.clear()
	last_external_result.clear()
	transport_routes.clear()
	overflow_waste = {"food": 0, "soil": 0}
	overflow_waste_tick = {"food": 0, "soil": 0}
	frontier_cells.clear()
	draw_count = 0
	elapsed_seconds = 0.0
	_excavate_initial_area()
	_refresh_frontier()
	_place_initial_core()
	_recalculate_city_stats()
	_emit_state()

func _build_catalogs() -> void:
	catalog_errors.clear()
	module_defs.clear()
	external_stages.clear()
	var module_rows = _load_catalog_array(MODULE_CATALOG_PATH)
	for row in module_rows:
		_load_module_definition(row)
	var stage_rows = _load_catalog_array(EXTERNAL_STAGE_CATALOG_PATH)
	for row in stage_rows:
		_load_external_stage(row)
	_validate_catalogs()
	for error in catalog_errors:
		push_error(error)

func _load_catalog_array(path: String) -> Array:
	if not FileAccess.file_exists(path):
		catalog_errors.append("Missing catalog: %s" % path)
		return []
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(parsed) != TYPE_ARRAY:
		catalog_errors.append("Catalog must be a JSON array: %s" % path)
		return []
	return parsed

func _load_module_definition(row: Dictionary) -> void:
	var id := String(row.get("id", ""))
	if id == "":
		catalog_errors.append("Module entry missing id")
		return
	if module_defs.has(id):
		catalog_errors.append("Duplicate module id: %s" % id)
		return
	var connectors := _connectors_from_row(row.get("connectors", {}), "module %s" % id)
	var size := _vector2i_from_array(row.get("size", [1, 1]), Vector2i.ONE)
	module_defs[id] = ModuleDataScript.make(
		id,
		String(row.get("display_name", id)),
		String(row.get("category", "")),
		size,
		connectors,
		int(row.get("build_cost_food", 0)),
		int(row.get("build_cost_soil", 0)),
		int(row.get("worker_need", 0)),
		Dictionary(row.get("output_rates", {})),
		Dictionary(row.get("storage", {})),
		int(row.get("throughput", 1)),
		float(row.get("base_cycle_time", 10.0)),
		bool(row.get("external_interface", false)),
		Array(row.get("tags", [])),
		String(row.get("rarity", "common")),
		String(row.get("description_short", "")),
		Array(row.get("reward_tags", row.get("tags", []))),
		Dictionary(row.get("solves_pressure", {})),
		Dictionary(row.get("creates_pressure", {})),
		int(row.get("transport_output", -1)),
		float(row.get("excavation_power", 0.0)),
		float(row.get("excavation_interval", 1.0))
	)

func _load_external_stage(row: Dictionary) -> void:
	var id := String(row.get("id", ""))
	if id == "":
		catalog_errors.append("External stage entry missing id")
		return
	if external_stages.has(id):
		catalog_errors.append("Duplicate external stage id: %s" % id)
		return
	external_stages[id] = ExternalStageDataScript.make(
		id,
		String(row.get("display_name", id)),
		float(row.get("duration", 20.0)),
		int(row.get("worker_required", 2)),
		int(row.get("food_cost", 4)),
		float(row.get("danger", 0.15)),
		_vector2i_from_array(row.get("base_food_reward", [0, 0]), Vector2i.ZERO),
		_vector2i_from_array(row.get("base_soil_reward", [0, 0]), Vector2i.ZERO),
		Array(row.get("card_reward_pool", [])),
		Array(row.get("tags", [])),
		float(row.get("success_base", 1.0 - float(row.get("danger", 0.15)))),
		float(row.get("risk", row.get("danger", 0.15))),
		Dictionary(row.get("reward_weights", {})),
		Dictionary(row.get("pressure_weight_bonus", {})),
		float(row.get("partial_resource_ratio", 0.55)),
		float(row.get("failure_resource_ratio", 0.3)),
		Array(row.get("guaranteed_slots", ["problem_solver", "stage_theme", "wildcard"]))
	)

func _connectors_from_row(value, context: String) -> Dictionary:
	var connectors := ModuleDataScript._blank_connectors()
	if typeof(value) != TYPE_DICTIONARY:
		catalog_errors.append("Invalid connectors for %s" % context)
		return connectors
	for direction in value.keys():
		if not ModuleDataScript.DIRECTIONS.has(direction):
			catalog_errors.append("Invalid connector '%s' for %s" % [direction, context])
			continue
		connectors[direction] = bool(value[direction])
	return connectors

func _vector2i_from_array(value, fallback: Vector2i) -> Vector2i:
	if typeof(value) != TYPE_ARRAY or value.size() < 2:
		return fallback
	return Vector2i(int(value[0]), int(value[1]))

func _validate_catalogs() -> void:
	for required_id in ["queen_core", "straight_corridor", "surface_entrance"]:
		if not module_defs.has(required_id):
			catalog_errors.append("Missing required module id: %s" % required_id)
	for module_id in module_defs.keys():
		var data = module_defs[module_id]
		var has_connector := false
		for direction in ModuleDataScript.DIRECTIONS:
			if bool(data.connectors.get(direction, false)):
				has_connector = true
		if not has_connector:
			catalog_errors.append("Module has no connectors: %s" % module_id)
		if data.size.x <= 0 or data.size.y <= 0:
			catalog_errors.append("Module has invalid size: %s" % module_id)
	for stage_id in external_stages.keys():
		var stage = external_stages[stage_id]
		if stage.card_reward_pool.size() < 3:
			catalog_errors.append("External stage must expose at least three rewards: %s" % stage_id)
		for card_id in stage.card_reward_pool:
			if not module_defs.has(card_id):
				catalog_errors.append("External stage %s references unknown reward module: %s" % [stage_id, card_id])
		if stage.success_base <= 0.0 or stage.success_base > 1.0:
			catalog_errors.append("External stage has invalid success_base: %s" % stage_id)
		if stage.risk < 0.0 or stage.risk > 1.0:
			catalog_errors.append("External stage has invalid risk: %s" % stage_id)

func _excavate_initial_area() -> void:
	for x in range(2, 8):
		for y in range(1, 6):
			excavated[_cell_key(Vector2i(x, y))] = true

func _place_initial_core() -> void:
	var core = _new_module_state("queen_core", CORE_ORIGIN, 0)
	modules.append(core)
	_mark_occupied(0)

func can_place_module(card_id: String, origin: Vector2i, rotation_steps: int) -> Dictionary:
	if not module_defs.has(card_id):
		return {"ok": false, "reason": "Unknown module"}
	if not hand.has(card_id):
		return {"ok": false, "reason": "Card not in hand"}
	var data = module_defs[card_id]
	var size = data.rotated_size(rotation_steps)
	var cells = _cells_for(origin, size)
	for cell in cells:
		if cell.x < 0 or cell.y < 0 or cell.x >= GRID_SIZE.x or cell.y >= GRID_SIZE.y:
			return {"ok": false, "reason": "Outside nest grid", "cells": cells}
		if not excavated.has(_cell_key(cell)):
			return {"ok": false, "reason": "Cell is not excavated", "cells": cells}
		if occupied.has(_cell_key(cell)):
			return {"ok": false, "reason": "Cell is occupied", "cells": cells}
	if resources["food"] < data.build_cost_food or resources["soil"] < data.build_cost_soil:
		return {"ok": false, "reason": "Not enough resources", "cells": cells}
	var connection = _find_connection_for(origin, size, data.rotated_connectors(rotation_steps))
	if connection.is_empty():
		return {"ok": false, "reason": "No matching city connector", "cells": cells}
	return {"ok": true, "reason": "OK", "cells": cells, "connection": connection}

func request_place_module(card_id: String, origin: Vector2i, rotation_steps: int) -> Dictionary:
	var check = can_place_module(card_id, origin, rotation_steps)
	if not check["ok"]:
		feedback.emit(str(check["reason"]))
		return check
	var data = module_defs[card_id]
	resources["food"] -= data.build_cost_food
	resources["soil"] -= data.build_cost_soil
	hand.erase(card_id)
	var module = _new_module_state(card_id, origin, rotation_steps)
	modules.append(module)
	_mark_occupied(modules.size() - 1)
	_refresh_frontier()
	_recalculate_city_stats()
	module_placed.emit(module.duplicate(true))
	hand_changed.emit(hand.duplicate())
	resource_changed.emit(resources.duplicate(), capacities.duplicate(), workers.duplicate())
	feedback.emit("%s connected" % data.display_name)
	return {"ok": true, "reason": "OK", "module": module}

func simulate_tick(delta: float) -> void:
	elapsed_seconds += delta
	overflow_waste_tick = {"food": 0, "soil": 0}
	if active_external_run.has("id"):
		active_external_run["remaining"] = max(0.0, float(active_external_run["remaining"]) - delta)
		if active_external_run["remaining"] <= 0.0:
			_finish_external_run()
	_recalculate_city_stats()
	_rebuild_transport_routes()
	for i in range(modules.size()):
		var module = modules[i]
		var data = module_defs[module["module_id"]]
		module["worker_effect"] = float(workers["satisfaction"])
		if data.output_rates.is_empty():
			module["status"] = "idle"
			module["last_blocker"] = "none"
			modules[i] = module
			continue
		var path = get_path_to_core(i)
		if path.is_empty():
			module["status"] = "disconnected"
			module["last_blocker"] = "disconnected"
			modules[i] = module
			continue
		var throughput_efficiency = _route_efficiency_for_module(i, path, data)
		var adjacency_bonus = _adjacency_bonus(i)
		var worker_effect = float(workers["satisfaction"])
		var efficiency = worker_effect * throughput_efficiency * adjacency_bonus
		module["efficiency"] = efficiency
		module["path"] = path
		module["progress"] = float(module.get("progress", 0.0)) + delta * efficiency
		module["last_blocker"] = _blocker_for_module(i, efficiency, throughput_efficiency, worker_effect)
		module["status"] = _status_for_module(module, efficiency)
		while float(module["progress"]) >= data.base_cycle_time:
			module["progress"] = float(module["progress"]) - data.base_cycle_time
			_queue_output(data.output_rates, module)
			if data.excavation_power > 0.0:
				_apply_excavation_progress(module, data)
		modules[i] = module
	_rebuild_transport_routes()
	_transport_pending_outputs(delta)
	_recalculate_city_stats()
	for i in range(modules.size()):
		var module = modules[i]
		var route := _route_for_module(i)
		if not route.is_empty():
			module["route_load"] = float(route.get("load_ratio", 0.0))
			if float(route.get("load_ratio", 0.0)) > 1.0 and String(module.get("last_blocker", "none")) == "none":
				module["last_blocker"] = "bottleneck"
				module["status"] = "constrained"
			modules[i] = module
		module_status_changed.emit(module.duplicate(true))
	resource_changed.emit(resources.duplicate(), capacities.duplicate(), workers.duplicate())

func _status_for_efficiency(efficiency: float) -> String:
	if efficiency <= 0.0:
		return "stalled"
	if efficiency < 0.7:
		return "constrained"
	if efficiency < 0.98:
		return "busy"
	return "running"

func _status_for_module(module: Dictionary, efficiency: float) -> String:
	if String(module.get("last_blocker", "none")) in ["bottleneck", "storage_full", "no_workers"]:
		return "constrained"
	return _status_for_efficiency(efficiency)

func _queue_output(rates: Dictionary, module: Dictionary) -> void:
	var pending: Dictionary = module.get("pending_output", {}).duplicate(true)
	for resource_name in rates.keys():
		pending[resource_name] = int(pending.get(resource_name, 0)) + int(rates[resource_name])
	module["pending_output"] = pending

func _route_efficiency_for_module(module_index: int, path: Array[int], data) -> float:
	var route := _route_for_module(module_index)
	var base := _throughput_efficiency(path, data)
	if route.is_empty():
		return base
	var load_ratio := float(route.get("load_ratio", 0.0))
	if load_ratio <= 1.0:
		return base
	return base / load_ratio

func _blocker_for_module(module_index: int, _efficiency: float, throughput_efficiency: float, worker_effect: float) -> String:
	if worker_effect < 0.98:
		return "no_workers"
	var route := _route_for_module(module_index)
	if not route.is_empty() and float(route.get("load_ratio", 0.0)) > 1.0:
		return "bottleneck"
	if throughput_efficiency < 0.98:
		return "bottleneck"
	var module: Dictionary = modules[module_index]
	if _pending_total(module.get("pending_output", {})) > 0 and _capacity_room_for_any_pending(module.get("pending_output", {})) <= 0:
		return "storage_full"
	return "none"

func _rebuild_transport_routes() -> void:
	transport_routes.clear()
	var node_use := {}
	for i in range(1, modules.size()):
		var module: Dictionary = modules[i]
		var data = module_defs[module["module_id"]]
		if data.output_rates.is_empty() and _pending_total(module.get("pending_output", {})) <= 0:
			continue
		var path := get_path_to_core(i)
		if path.size() <= 1:
			continue
		for module_index in path:
			node_use[module_index] = int(node_use.get(module_index, 0)) + 1
	for i in range(1, modules.size()):
		var module: Dictionary = modules[i]
		var data = module_defs[module["module_id"]]
		if data.output_rates.is_empty() and _pending_total(module.get("pending_output", {})) <= 0:
			continue
		var path := get_path_to_core(i)
		if path.size() <= 1:
			continue
		var min_throughput := 99
		var max_shared := 1
		var bottleneck_module := i
		for module_index in path:
			var path_module: Dictionary = modules[module_index]
			var path_data = module_defs[path_module["module_id"]]
			if path_data.throughput < min_throughput:
				min_throughput = path_data.throughput
				bottleneck_module = module_index
			max_shared = max(max_shared, int(node_use.get(module_index, 1)))
		var capacity: int = max(1, int(floor(float(min_throughput) / float(max_shared))))
		capacity += _sorter_support_for_path(path)
		var pending_total: int = _pending_total(module.get("pending_output", {}))
		var expected_output: int = max(1, int(data.transport_output))
		var load: float = float(max(pending_total, expected_output)) / float(capacity)
		transport_routes[String(module["uid"])] = {
			"module_index": i,
			"module_uid": String(module["uid"]),
			"path": path,
			"capacity": capacity,
			"load": max(pending_total, expected_output),
			"load_ratio": load,
			"bottleneck_module": bottleneck_module,
		}

func _route_for_module(module_index: int) -> Dictionary:
	if module_index < 0 or module_index >= modules.size():
		return {}
	return transport_routes.get(String(modules[module_index]["uid"]), {})

func _sorter_support_for_path(path: Array[int]) -> int:
	var support := 0
	var counted := {}
	for module_index in path:
		for neighbor in _connected_neighbors(module_index):
			if counted.has(neighbor):
				continue
			if String(modules[neighbor]["module_id"]) == "sorter":
				counted[neighbor] = true
				support += 1
	return support

func _transport_pending_outputs(delta: float) -> void:
	var route_keys := transport_routes.keys()
	route_keys.sort()
	for uid in route_keys:
		var route: Dictionary = transport_routes[uid]
		var module_index := int(route["module_index"])
		if module_index < 0 or module_index >= modules.size():
			continue
		var module: Dictionary = modules[module_index]
		var pending: Dictionary = module.get("pending_output", {}).duplicate(true)
		var capacity: int = max(1, int(route.get("capacity", 1))) * max(1, int(floor(delta)))
		var delivered := {}
		for resource_name in pending.keys():
			if capacity <= 0:
				break
			var amount := int(pending[resource_name])
			if amount <= 0:
				continue
			var moved: int = min(amount, capacity)
			var accepted := _add_resource_with_capacity(resource_name, moved)
			delivered[resource_name] = int(delivered.get(resource_name, 0)) + accepted
			pending[resource_name] = amount - moved
			capacity -= moved
			if accepted < moved:
				module["last_blocker"] = "storage_full"
				module["status"] = "constrained"
		for resource_name in pending.keys():
			if int(pending[resource_name]) <= 0:
				pending.erase(resource_name)
		module["pending_output"] = pending
		module["delivered_this_tick"] = delivered
		if _pending_total(pending) > 0 and String(module.get("last_blocker", "none")) == "none":
			module["last_blocker"] = "bottleneck"
			module["status"] = "constrained"
		modules[module_index] = module
	_rebuild_transport_routes()

func _add_resource_with_capacity(resource_name: String, amount: int) -> int:
	var before := int(resources.get(resource_name, 0))
	var cap := int(capacities.get(resource_name, before))
	var accepted: int = min(amount, max(0, cap - before))
	resources[resource_name] = before + accepted
	var waste: int = amount - accepted
	if waste > 0:
		overflow_waste[resource_name] = int(overflow_waste.get(resource_name, 0)) + waste
		overflow_waste_tick[resource_name] = int(overflow_waste_tick.get(resource_name, 0)) + waste
	return accepted

func _pending_total(pending: Dictionary) -> int:
	var total := 0
	for amount in pending.values():
		total += int(amount)
	return total

func _capacity_room_for_any_pending(pending: Dictionary) -> int:
	var total := 0
	for resource_name in pending.keys():
		total += max(0, int(capacities.get(resource_name, 0)) - int(resources.get(resource_name, 0)))
	return total

func _apply_excavation_progress(module: Dictionary, data) -> void:
	module["excavation_progress"] = float(module.get("excavation_progress", 0.0)) + data.excavation_power
	while float(module["excavation_progress"]) >= data.excavation_interval and not frontier_cells.is_empty():
		module["excavation_progress"] = float(module["excavation_progress"]) - data.excavation_interval
		var cell := _next_frontier_cell(module)
		if cell == Vector2i(-1, -1):
			return
		excavated[_cell_key(cell)] = true
		_refresh_frontier()

func _next_frontier_cell(module: Dictionary) -> Vector2i:
	var origin: Vector2i = module["origin"]
	var best := Vector2i(-1, -1)
	var best_distance := 99999
	for key in frontier_cells.keys():
		var parts := String(key).split(",")
		var cell := Vector2i(int(parts[0]), int(parts[1]))
		var distance: int = abs(cell.x - origin.x) + abs(cell.y - origin.y)
		if distance < best_distance:
			best_distance = distance
			best = cell
	return best

func start_external_stage(stage_id: String) -> Dictionary:
	if not external_stages.has(stage_id):
		return {"ok": false, "reason": "Unknown external stage"}
	if active_external_run.has("id"):
		return {"ok": false, "reason": "Exploration already running"}
	if not has_external_entrance():
		return {"ok": false, "reason": "No connected entrance"}
	var stage = external_stages[stage_id]
	_recalculate_city_stats()
	if resources["food"] < stage.food_cost:
		return {"ok": false, "reason": "Not enough food"}
	if int(workers["total"]) < stage.worker_required:
		return {"ok": false, "reason": "Not enough workers"}
	resources["food"] -= stage.food_cost
	var preview := external_stage_preview(stage_id)
	var run_seed := "%s:%d:%d:%d" % [stage.id, draw_count, modules.size(), int(resources["food"]) + int(resources["soil"])]
	active_external_run = {
		"id": stage.id,
		"display_name": stage.display_name,
		"remaining": stage.duration,
		"duration": stage.duration,
		"worker_required": stage.worker_required,
		"success_chance": preview["success_chance"],
		"risk": stage.risk,
		"modifiers": preview["modifiers"],
		"city_pressure_snapshot": city_pressure.duplicate(true),
		"seed": run_seed,
		"result_roll": _deterministic_roll(run_seed),
	}
	_recalculate_city_stats()
	external_run_started.emit(active_external_run.duplicate(true))
	resource_changed.emit(resources.duplicate(), capacities.duplicate(), workers.duplicate())
	return {"ok": true, "run": active_external_run.duplicate(true)}

func external_stage_preview(stage_id: String) -> Dictionary:
	if not external_stages.has(stage_id):
		return {}
	var stage = external_stages[stage_id]
	_recalculate_city_stats()
	var free_worker_ratio := 1.0
	if int(workers["total"]) > 0:
		free_worker_ratio = float(max(0, int(workers["free"]))) / float(max(1, int(workers["total"])))
	var free_worker_bonus := (free_worker_ratio - 0.35) * 0.18
	var capacity_room := 0.0
	for resource_name in ["food", "soil"]:
		capacity_room += float(max(0, int(capacities[resource_name]) - int(resources[resource_name]))) / float(max(1, int(capacities[resource_name])))
	var capacity_bonus := clampf((capacity_room / 2.0 - 0.25) * 0.12, -0.06, 0.08)
	var instability_penalty := 0.0
	for key in ["worker_pressure", "capacity_pressure", "throughput_pressure"]:
		instability_penalty += float(city_pressure.get(key, 0.0)) * 0.04
	var entrance_bonus := 0.04 if has_external_entrance() else 0.0
	var chance := clampf(stage.success_base - stage.risk * 0.35 + free_worker_bonus + capacity_bonus + entrance_bonus - instability_penalty, 0.1, 0.9)
	return {
		"success_chance": chance,
		"modifiers": {
			"free_workers": free_worker_bonus,
			"capacity_room": capacity_bonus,
			"connected_entrance": entrance_bonus,
			"city_pressure": -instability_penalty,
		},
		"risk": stage.risk,
	}

func external_stage_previews() -> Dictionary:
	var previews := {}
	for stage_id in external_stages.keys():
		previews[stage_id] = external_stage_preview(stage_id)
	return previews

func production_impact_summary() -> Dictionary:
	var production_count := 0
	var constrained_count := 0
	var total_efficiency := 0.0
	var worst_blocker := "none"
	for module in modules:
		var data = module_defs[module["module_id"]]
		if data.output_rates.is_empty():
			continue
		production_count += 1
		var efficiency := float(module.get("efficiency", 1.0))
		total_efficiency += efficiency
		var blocker := String(module.get("last_blocker", "none"))
		if efficiency < 0.98 or blocker != "none":
			constrained_count += 1
		if blocker != "none":
			worst_blocker = blocker
	var average := 1.0
	if production_count > 0:
		average = total_efficiency / float(production_count)
	return {
		"production_count": production_count,
		"constrained_count": constrained_count,
		"average_efficiency": average,
		"worker_satisfaction": float(workers.get("satisfaction", 1.0)),
		"workers_exploring": int(workers.get("exploring", 0)),
		"worst_blocker": worst_blocker,
	}

func nest_goal_summary() -> Dictionary:
	var milestone := _first_session_milestone()
	if not milestone.is_empty():
		return milestone
	var key := _highest_pressure_key()
	var value := float(city_pressure.get(key, 0.0))
	var label := "Keep the nest flowing"
	var action := "Add production, storage, workers, tunnels, or explore when ready."
	match key:
		"food_pressure":
			label = "Food stores are thin"
			action = "Grow food or scout debris before starting a costly build."
		"soil_pressure":
			label = "Soil limits expansion"
			action = "Run digging rooms or scout loose soil for the next chamber."
		"worker_pressure":
			label = "Workers are stretched"
			action = "Choose Nursery or delay exploration until production recovers."
		"capacity_pressure":
			label = "Stores are near full"
			action = "Build Storage before producers waste output."
		"throughput_pressure":
			label = "Tunnels are jammed"
			action = "Add Sorter or corridors near busy production routes."
		"expansion_pressure":
			label = "The nest needs room"
			action = "Let digging rooms open frontier cells before placing large modules."
	if value <= 0.05:
		label = "Nest is stable"
		action = "Prepare an entrance run or shape the next production wing."
	return {
		"key": key,
		"value": value,
		"label": label,
		"action": action,
		"time": elapsed_seconds,
	}

func _first_session_milestone() -> Dictionary:
	if reward_choices.size() > 0:
		return {
			"key": "reward_pending",
			"value": 1.0,
			"label": "Pick the next nest organ",
			"action": "Choose the card that answers the strongest pressure, then keep playing to feel the tradeoff.",
			"time": elapsed_seconds,
		}
	if active_external_run.has("id"):
		return {
			"key": "exploration_running",
			"value": 1.0,
			"label": "Foragers are outside",
			"action": "Watch production slow while workers are away; recover when they return.",
			"time": elapsed_seconds,
		}
	if not _has_module_id("digging_room"):
		return {
			"key": "build_soil",
			"value": 0.8,
			"label": "Start a soil line",
			"action": "Place a corridor above the queen, then attach a Digging Room to open future cells.",
			"time": elapsed_seconds,
		}
	if not _has_module_id("fungus_farm"):
		return {
			"key": "build_food",
			"value": 0.8,
			"label": "Start a food line",
			"action": "Place a Fungus Farm on the west side so the entrance has a food budget.",
			"time": elapsed_seconds,
		}
	if not _has_module_id("surface_entrance"):
		var entrance = module_defs.get("surface_entrance", null)
		if entrance != null:
			return {
				"key": "stockpile_entrance",
				"value": 0.75,
				"label": "Stockpile for the surface gate",
				"action": "Need %d food and %d soil; production and tunnel load decide how soon scouting starts." % [entrance.build_cost_food, entrance.build_cost_soil],
				"time": elapsed_seconds,
			}
	if last_external_result.is_empty():
		return {
			"key": "start_exploration",
			"value": 0.65,
			"label": "Choose the first scouting route",
			"action": "Compare outlook, risk, worker draw, and likely finds before sending workers out.",
			"time": elapsed_seconds,
		}
	for support_id in ["storage_chamber", "nursery", "sorter"]:
		if hand.has(support_id) and not _has_module_id(support_id):
			var data = module_defs[support_id]
			return {
				"key": "install_reward",
				"value": 0.7,
				"label": "Install %s" % data.display_name,
				"action": "%s Watch the pressure meter for the next 3-5 minutes after it connects." % data.description_short,
				"time": elapsed_seconds,
			}
	return {}

func _has_module_id(module_id: String) -> bool:
	for module in modules:
		if String(module.get("module_id", "")) == module_id:
			return true
	return false

func choose_reward(index: int) -> Dictionary:
	if index < 0 or index >= reward_choices.size():
		return {"ok": false, "reason": "Reward index out of range"}
	if hand.size() >= MAX_HAND:
		return {"ok": false, "reason": "Hand is full"}
	var card_id = reward_choices[index]
	hand.append(card_id)
	reward_choices.clear()
	reward_choice_context.clear()
	hand_changed.emit(hand.duplicate())
	reward_chosen.emit(card_id)
	return {"ok": true, "card_id": card_id}

func has_external_entrance() -> bool:
	for i in range(modules.size()):
		var module = modules[i]
		var data = module_defs[module["module_id"]]
		if data.external_interface and not get_path_to_core(i).is_empty():
			return true
	return false

func get_path_to_core(module_index: int) -> Array[int]:
	if module_index < 0 or module_index >= modules.size():
		return []
	if module_index == 0:
		return [0]
	var visited = {}
	var queue: Array[Array] = [[module_index, [module_index]]]
	while not queue.is_empty():
		var item: Array = queue.pop_front()
		var current: int = item[0]
		var path: Array = item[1]
		if current == 0:
			var typed_path: Array[int] = []
			for p in path:
				typed_path.append(int(p))
			return typed_path
		visited[current] = true
		for neighbor in _connected_neighbors(current):
			if not visited.has(neighbor):
				var next_path = path.duplicate()
				next_path.append(neighbor)
				queue.append([neighbor, next_path])
	return []

func active_transport_paths() -> Array[Array]:
	var paths: Array[Array] = []
	for route in active_transport_routes():
		paths.append(route["points"])
	return paths

func active_transport_routes() -> Array[Dictionary]:
	var routes: Array[Dictionary] = []
	for i in range(1, modules.size()):
		var module = modules[i]
		if String(module.get("status", "")) in ["running", "busy", "constrained"] or _pending_total(module.get("pending_output", {})) > 0:
			var path = get_path_to_core(i)
			if path.size() > 1:
				var points: Array[Vector2] = []
				for module_index in path:
					points.append(module_center_world(module_index))
				var route := _route_for_module(i)
				routes.append({
					"key": _transport_route_key(i, path),
					"module_uid": String(module["uid"]),
					"points": points,
					"load_ratio": float(route.get("load_ratio", 0.0)),
					"capacity": int(route.get("capacity", 0)),
					"load": int(route.get("load", 0)),
					"bottleneck_module": int(route.get("bottleneck_module", i)),
				})
	return routes

func _transport_route_key(module_index: int, path: Array[int]) -> String:
	var ids: Array[String] = []
	for index in path:
		ids.append(String(modules[index]["uid"]))
	return "%s:%s" % [modules[module_index]["uid"], "|".join(ids)]

func module_center_world(module_index: int, cell_size: int = 56) -> Vector2:
	var module = modules[module_index]
	var data = module_defs[module["module_id"]]
	var size = data.rotated_size(int(module["rotation"]))
	return (Vector2(module["origin"]) + Vector2(size) * 0.5) * float(cell_size)

func _finish_external_run() -> void:
	var stage = external_stages[active_external_run["id"]]
	var chance := float(active_external_run.get("success_chance", 0.5))
	var roll := float(active_external_run.get("result_roll", 1.0))
	var result := "failure"
	if roll <= chance:
		result = "success"
	elif roll <= min(0.95, chance + 0.22):
		result = "partial"
	var resource_ratio := 1.0
	if result == "partial":
		resource_ratio = stage.partial_resource_ratio
	elif result == "failure":
		resource_ratio = stage.failure_resource_ratio
	var food_gain := _reward_amount(stage.id, "food", stage.base_food_reward, resource_ratio)
	var soil_gain := _reward_amount(stage.id, "soil", stage.base_soil_reward, resource_ratio)
	var food_accepted := _add_resource_with_capacity("food", food_gain)
	var soil_accepted := _add_resource_with_capacity("soil", soil_gain)
	active_external_run["result"] = result
	active_external_run["success"] = result == "success"
	active_external_run["resource_gain"] = {"food": food_accepted, "soil": soil_accepted}
	active_external_run["resource_waste"] = {"food": food_gain - food_accepted, "soil": soil_gain - soil_accepted}
	external_run_finished.emit(active_external_run.duplicate(true))
	last_external_result = active_external_run.duplicate(true)
	if result in ["success", "partial"]:
		_generate_reward_choices(stage, result)
		reward_choice_ready.emit(reward_choices.duplicate())
	active_external_run.clear()
	_recalculate_city_stats()
	resource_changed.emit(resources.duplicate(), capacities.duplicate(), workers.duplicate())

func _reward_amount(stage_id: String, resource_name: String, reward_range: Vector2i, ratio: float) -> int:
	if reward_range.x <= 0 and reward_range.y <= 0:
		return 0
	var roll := _deterministic_roll("%s:%s:%d" % [stage_id, resource_name, draw_count])
	var base := reward_range.x + int(round(float(max(0, reward_range.y - reward_range.x)) * roll))
	return int(round(float(base) * ratio))

func _generate_reward_choices(stage, result: String) -> void:
	reward_choices.clear()
	reward_choice_context.clear()
	var pressure_key := _highest_pressure_key()
	var pool := _expanded_reward_pool(stage, pressure_key)
	_add_best_reward_for_pressure(pool, pressure_key)
	_add_best_reward_for_tags(pool, stage.tags, "Matches the outside site theme")
	_add_weighted_reward(pool, stage, "%s:%s:%d" % [stage.id, result, draw_count])
	if result == "partial" and reward_choices.size() > 0:
		var card_id := reward_choices[0]
		reward_choice_context[card_id] = "%s after a partial return" % String(reward_choice_context.get(card_id, "Stabilizes the city"))
	for card_id in pool:
		if reward_choices.size() >= 3:
			break
		if module_defs.has(card_id) and not reward_choices.has(card_id):
			reward_choices.append(card_id)
			reward_choice_context[card_id] = "Keeps options open"
	_break_fixed_reward_set(stage.card_reward_pool, pool, pressure_key)
	draw_count += 1

func _expanded_reward_pool(stage, pressure_key: String) -> Array[String]:
	var pool: Array[String] = []
	for card_id in stage.card_reward_pool:
		_append_unique_card(pool, String(card_id))
	for card_id in module_defs.keys():
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
			_append_unique_card(pool, String(card_id))
	for card_id in module_defs.keys():
		var data = module_defs[card_id]
		if data.rarity == "starter" or data.category == "core":
			continue
		if data.solves_pressure.has(pressure_key):
			_append_unique_card(pool, String(card_id))
			continue
		for tag in data.reward_tags:
			if _tag_matches_pressure(String(tag), pressure_key):
				_append_unique_card(pool, String(card_id))
	return pool

func _append_unique_card(pool: Array[String], card_id: String) -> void:
	if module_defs.has(card_id) and not pool.has(card_id):
		pool.append(card_id)

func _break_fixed_reward_set(base_pool: Array[String], expanded_pool: Array[String], pressure_key: String) -> void:
	var base_trio: Array[String] = []
	for card_id in base_pool:
		if base_trio.size() >= 3:
			break
		base_trio.append(String(card_id))
	if reward_choices.size() != 3 or not _same_card_set(reward_choices, base_trio):
		return
	var replacement := _best_non_base_reward(base_trio, expanded_pool, pressure_key)
	if replacement == "":
		return
	var removed := String(reward_choices.pop_back())
	reward_choice_context.erase(removed)
	reward_choices.append(replacement)
	reward_choice_context[replacement] = "%s; changes this site's usual choices" % _pressure_reason(pressure_key)

func _same_card_set(left: Array[String], right: Array[String]) -> bool:
	if left.size() != right.size():
		return false
	for card_id in left:
		if not right.has(card_id):
			return false
	return true

func _best_non_base_reward(base_trio: Array[String], expanded_pool: Array[String], pressure_key: String) -> String:
	var best_id := ""
	var best_score := -9999.0
	for card_id in expanded_pool:
		if base_trio.has(card_id) or reward_choices.has(card_id):
			continue
		var data = module_defs[card_id]
		var score := float(data.solves_pressure.get(pressure_key, 0)) * 3.0
		for tag in data.reward_tags:
			if _tag_matches_pressure(String(tag), pressure_key):
				score += 1.0
		if score > best_score:
			best_score = score
			best_id = card_id
	return best_id

func _add_best_reward_for_pressure(pool: Array[String], pressure_key: String) -> void:
	var best_id := ""
	var best_score := -9999.0
	for card_id in pool:
		if not module_defs.has(card_id) or reward_choices.has(card_id):
			continue
		var data = module_defs[card_id]
		var score := float(data.solves_pressure.get(pressure_key, 0)) * 3.0
		for tag in data.reward_tags:
			if _tag_matches_pressure(String(tag), pressure_key):
				score += 1.0
		if score > best_score:
			best_score = score
			best_id = card_id
	if best_id != "":
		reward_choices.append(best_id)
		reward_choice_context[best_id] = _pressure_reason(pressure_key)

func _add_best_reward_for_tags(pool: Array[String], tags: Array[String], reason: String) -> void:
	var best_id := ""
	var best_score := -9999.0
	for card_id in pool:
		if not module_defs.has(card_id) or reward_choices.has(card_id):
			continue
		var data = module_defs[card_id]
		var score := 0.0
		for tag in data.reward_tags:
			if tags.has(tag):
				score += 2.0
		for tag in data.tags:
			if tags.has(tag):
				score += 1.0
		if score > best_score:
			best_score = score
			best_id = card_id
	if best_id != "":
		reward_choices.append(best_id)
		reward_choice_context[best_id] = reason

func _add_weighted_reward(pool: Array[String], stage_data, seed: String) -> void:
	var weighted: Array[Dictionary] = []
	var total := 0.0
	var pressure_key := _highest_pressure_key()
	for card_id in pool:
		if not module_defs.has(card_id) or reward_choices.has(card_id):
			continue
		var data = module_defs[card_id]
		var weight := 1.0
		for tag in data.reward_tags:
			weight += float(stage_data.reward_weights.get(tag, 0.0))
		for pressure in city_pressure.keys():
			if data.solves_pressure.has(pressure):
				weight += float(city_pressure[pressure]) * float(stage_data.pressure_weight_bonus.get(pressure, 0.0))
		weight += float(data.solves_pressure.get(pressure_key, 0)) * 2.0
		total += weight
		weighted.append({"id": card_id, "ceiling": total})
	if weighted.is_empty():
		return
	var roll := _deterministic_roll(seed) * total
	for item in weighted:
		if roll <= float(item["ceiling"]):
			var card_id := String(item["id"])
			reward_choices.append(card_id)
			reward_choice_context[card_id] = "Weighted by current nest pressure"
			return

func _new_module_state(card_id: String, origin: Vector2i, rotation_steps: int) -> Dictionary:
	return {
		"uid": "%s_%d" % [card_id, modules.size()],
		"module_id": card_id,
		"origin": origin,
		"rotation": posmod(rotation_steps, 4),
		"status": "idle",
		"efficiency": 1.0,
		"worker_effect": 1.0,
		"last_blocker": "none",
		"pending_output": {},
		"delivered_this_tick": {},
		"route_load": 0.0,
		"excavation_progress": 0.0,
		"progress": 0.0,
		"path": [],
	}

func _mark_occupied(module_index: int) -> void:
	var module = modules[module_index]
	var data = module_defs[module["module_id"]]
	var size = data.rotated_size(int(module["rotation"]))
	for cell in _cells_for(module["origin"], size):
		occupied[_cell_key(cell)] = module_index

func _cells_for(origin: Vector2i, size: Vector2i) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for x in range(origin.x, origin.x + size.x):
		for y in range(origin.y, origin.y + size.y):
			cells.append(Vector2i(x, y))
	return cells

func _cell_key(cell: Vector2i) -> String:
	return "%d,%d" % [cell.x, cell.y]

func _find_connection_for(origin: Vector2i, size: Vector2i, connectors: Dictionary) -> Dictionary:
	var cells = _cells_for(origin, size)
	for cell in cells:
		for direction in ModuleDataScript.DIRECTIONS:
			if not bool(connectors[direction]):
				continue
			if not _cell_is_on_side(cell, origin, size, direction):
				continue
			var neighbor_cell: Vector2i = cell + ModuleDataScript.DELTAS[direction]
			var key = _cell_key(neighbor_cell)
			if not occupied.has(key):
				continue
			var neighbor_index: int = occupied[key]
			if _module_has_connector_at_cell(neighbor_index, neighbor_cell, ModuleDataScript.OPPOSITE[direction]):
				return {"from": cell, "to": neighbor_cell, "direction": direction, "neighbor": neighbor_index}
	return {}

func _cell_is_on_side(cell: Vector2i, origin: Vector2i, size: Vector2i, direction: String) -> bool:
	match direction:
		ModuleDataScript.TOP:
			return cell.y == origin.y
		ModuleDataScript.RIGHT:
			return cell.x == origin.x + size.x - 1
		ModuleDataScript.BOTTOM:
			return cell.y == origin.y + size.y - 1
		ModuleDataScript.LEFT:
			return cell.x == origin.x
	return false

func _module_has_connector_at_cell(module_index: int, cell: Vector2i, direction: String) -> bool:
	var module = modules[module_index]
	var data = module_defs[module["module_id"]]
	var origin: Vector2i = module["origin"]
	var size = data.rotated_size(int(module["rotation"]))
	var connectors = data.rotated_connectors(int(module["rotation"]))
	return bool(connectors[direction]) and _cell_is_on_side(cell, origin, size, direction)

func _connected_neighbors(module_index: int) -> Array[int]:
	var module = modules[module_index]
	var data = module_defs[module["module_id"]]
	var origin: Vector2i = module["origin"]
	var size = data.rotated_size(int(module["rotation"]))
	var connectors = data.rotated_connectors(int(module["rotation"]))
	var result: Array[int] = []
	for cell in _cells_for(origin, size):
		for direction in ModuleDataScript.DIRECTIONS:
			if not bool(connectors[direction]) or not _cell_is_on_side(cell, origin, size, direction):
				continue
			var neighbor_cell: Vector2i = cell + ModuleDataScript.DELTAS[direction]
			var key = _cell_key(neighbor_cell)
			if not occupied.has(key):
				continue
			var neighbor_index: int = occupied[key]
			if neighbor_index == module_index or result.has(neighbor_index):
				continue
			if _module_has_connector_at_cell(neighbor_index, neighbor_cell, ModuleDataScript.OPPOSITE[direction]):
				result.append(neighbor_index)
	return result

func _throughput_efficiency(path: Array[int], data) -> float:
	var path_throughput = 99
	for module_index in path:
		var path_module = modules[module_index]
		var path_data = module_defs[path_module["module_id"]]
		path_throughput = min(path_throughput, path_data.throughput)
	return min(1.0, float(path_throughput) / float(max(1, data.required_throughput)))

func _adjacency_bonus(module_index: int) -> float:
	var bonus = 1.0
	for neighbor in _connected_neighbors(module_index):
		if modules[neighbor]["module_id"] == "sorter":
			bonus += 0.15
	return bonus

func _recalculate_city_stats() -> void:
	capacities = {"food": 0, "soil": 0}
	var total_workers = 0
	var worker_demand = 0
	for module in modules:
		var data = module_defs[module["module_id"]]
		capacities["food"] += int(data.storage.get("food", 0))
		capacities["soil"] += int(data.storage.get("soil", 0))
		total_workers += int(data.storage.get("workers", 0))
		worker_demand += data.worker_need
	capacities["food"] = max(50, capacities["food"])
	capacities["soil"] = max(50, capacities["soil"])
	resources["food"] = min(resources["food"], capacities["food"])
	resources["soil"] = min(resources["soil"], capacities["soil"])
	var exploring := int(active_external_run.get("worker_required", 0))
	var base_satisfaction: float = 1.0 if worker_demand == 0 else min(1.0, float(max(0, total_workers - exploring)) / float(worker_demand))
	var exploration_drag: float = 0.0 if total_workers == 0 else float(exploring) / float(total_workers) * 0.35
	workers = {
		"total": total_workers,
		"demand": worker_demand,
		"exploring": exploring,
		"free": max(0, total_workers - worker_demand - exploring),
		"satisfaction": clampf(base_satisfaction - exploration_drag, 0.0, 1.0),
	}
	_rebuild_transport_routes()
	_recalculate_city_pressure()

func _recalculate_city_pressure() -> void:
	var next_food_cost := _next_build_cost("food")
	var next_soil_cost := _next_build_cost("soil")
	var food_ratio := float(resources["food"]) / float(max(1, capacities["food"]))
	var soil_ratio := float(resources["soil"]) / float(max(1, capacities["soil"]))
	var max_route_load := 0.0
	for route in transport_routes.values():
		max_route_load = max(max_route_load, float(route.get("load_ratio", 0.0)))
	var expansion_blocked := _has_affordable_blocked_card()
	city_pressure = {
		"food_pressure": clampf((0.35 - food_ratio) * 2.0 + (0.35 if int(resources["food"]) < next_food_cost else 0.0), 0.0, 1.0),
		"soil_pressure": clampf((0.35 - soil_ratio) * 2.0 + (0.35 if int(resources["soil"]) < next_soil_cost else 0.0), 0.0, 1.0),
		"worker_pressure": clampf((1.0 - float(workers["satisfaction"])) + (0.25 if int(workers["exploring"]) > 0 else 0.0), 0.0, 1.0),
		"capacity_pressure": clampf(max(food_ratio, soil_ratio) - 0.75 + float(_overflow_tick_total()) * 0.1, 0.0, 1.0),
		"throughput_pressure": clampf(max_route_load - 0.85, 0.0, 1.0),
		"expansion_pressure": 1.0 if expansion_blocked else 0.0,
	}

func _next_build_cost(resource_name: String) -> int:
	var best := 999
	for card_id in hand:
		if not module_defs.has(card_id):
			continue
		var data = module_defs[card_id]
		var cost: int = data.build_cost_food if resource_name == "food" else data.build_cost_soil
		if cost > 0:
			best = min(best, cost)
	return 0 if best == 999 else best

func _has_affordable_blocked_card() -> bool:
	for card_id in hand:
		if not module_defs.has(card_id):
			continue
		var data = module_defs[card_id]
		if int(resources["food"]) < data.build_cost_food or int(resources["soil"]) < data.build_cost_soil:
			continue
		if not _has_any_legal_position(card_id):
			return true
	return false

func _has_any_legal_position(card_id: String) -> bool:
	for x in range(GRID_SIZE.x):
		for y in range(GRID_SIZE.y):
			for rotation in range(4):
				var result := can_place_module(card_id, Vector2i(x, y), rotation)
				if bool(result.get("ok", false)):
					return true
	return false

func _overflow_tick_total() -> int:
	var total := 0
	for amount in overflow_waste_tick.values():
		total += int(amount)
	return total

func _highest_pressure_key() -> String:
	var best_key := "food_pressure"
	var best_value := -1.0
	for key in city_pressure.keys():
		var value := float(city_pressure[key])
		if value > best_value:
			best_value = value
			best_key = String(key)
	return best_key

func _tag_matches_pressure(tag: String, pressure_key: String) -> bool:
	return (
		(tag == "food" and pressure_key == "food_pressure")
		or (tag == "soil" and pressure_key == "soil_pressure")
		or (tag == "workers" and pressure_key == "worker_pressure")
		or (tag == "storage" and pressure_key == "capacity_pressure")
		or (tag == "throughput" and pressure_key == "throughput_pressure")
		or (tag == "expansion" and pressure_key == "expansion_pressure")
	)

func _pressure_reason(pressure_key: String) -> String:
	match pressure_key:
		"food_pressure":
			return "Relieves food pressure"
		"soil_pressure":
			return "Relieves soil pressure"
		"worker_pressure":
			return "Relieves worker pressure"
		"capacity_pressure":
			return "Relieves storage pressure"
		"throughput_pressure":
			return "Relieves tunnel bottlenecks"
		"expansion_pressure":
			return "Opens more build space"
	return "Relieves current nest pressure"

func _deterministic_roll(seed_text: String) -> float:
	var value: int = abs(hash(seed_text))
	return float(value % 1000) / 999.0

func _refresh_frontier() -> void:
	frontier_cells.clear()
	for key in excavated.keys():
		var parts := String(key).split(",")
		var cell := Vector2i(int(parts[0]), int(parts[1]))
		for direction in ModuleDataScript.DIRECTIONS:
			var neighbor: Vector2i = cell + ModuleDataScript.DELTAS[direction]
			if neighbor.x < 0 or neighbor.y < 0 or neighbor.x >= GRID_SIZE.x or neighbor.y >= GRID_SIZE.y:
				continue
			var neighbor_key := _cell_key(neighbor)
			if not excavated.has(neighbor_key):
				frontier_cells[neighbor_key] = true

func _excavate_around(origin: Vector2i, size: Vector2i, radius: int) -> void:
	for x in range(origin.x - radius, origin.x + size.x + radius):
		for y in range(origin.y - radius, origin.y + size.y + radius):
			if x >= 0 and y >= 0 and x < GRID_SIZE.x and y < GRID_SIZE.y:
				excavated[_cell_key(Vector2i(x, y))] = true

func _emit_state() -> void:
	resource_changed.emit(resources.duplicate(), capacities.duplicate(), workers.duplicate())
	hand_changed.emit(hand.duplicate())
