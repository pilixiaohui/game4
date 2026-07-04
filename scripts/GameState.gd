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
var active_external_run: Dictionary = {}
var draw_count: int = 0
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
		"storage_chamber",
		"nursery",
		"surface_entrance",
		"corner_corridor",
	]
	modules.clear()
	excavated.clear()
	occupied.clear()
	reward_choices.clear()
	active_external_run.clear()
	draw_count = 0
	_excavate_initial_area()
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
		String(row.get("description_short", ""))
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
		Array(row.get("tags", []))
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
		if stage.card_reward_pool.size() != 3:
			catalog_errors.append("External stage must expose exactly three rewards: %s" % stage_id)
		for card_id in stage.card_reward_pool:
			if not module_defs.has(card_id):
				catalog_errors.append("External stage %s references unknown reward module: %s" % [stage_id, card_id])

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
	if card_id == "digging_room":
		_excavate_around(origin, data.rotated_size(rotation_steps), 1)
	_recalculate_city_stats()
	module_placed.emit(module.duplicate(true))
	hand_changed.emit(hand.duplicate())
	resource_changed.emit(resources.duplicate(), capacities.duplicate(), workers.duplicate())
	feedback.emit("%s connected" % data.display_name)
	return {"ok": true, "reason": "OK", "module": module}

func simulate_tick(delta: float) -> void:
	if active_external_run.has("id"):
		active_external_run["remaining"] = max(0.0, float(active_external_run["remaining"]) - delta)
		if active_external_run["remaining"] <= 0.0:
			_finish_external_run()
	_recalculate_city_stats()
	for i in range(modules.size()):
		var module = modules[i]
		var data = module_defs[module["module_id"]]
		if data.output_rates.is_empty():
			module["status"] = "idle"
			modules[i] = module
			continue
		var path = get_path_to_core(i)
		if path.is_empty():
			module["status"] = "disconnected"
			modules[i] = module
			continue
		var throughput_efficiency = _throughput_efficiency(path, data)
		var adjacency_bonus = _adjacency_bonus(i)
		var efficiency = float(workers["satisfaction"]) * throughput_efficiency * adjacency_bonus
		module["efficiency"] = efficiency
		module["path"] = path
		module["progress"] = float(module.get("progress", 0.0)) + delta * efficiency
		module["status"] = _status_for_efficiency(efficiency)
		while float(module["progress"]) >= data.base_cycle_time:
			module["progress"] = float(module["progress"]) - data.base_cycle_time
			_apply_output(data.output_rates, module)
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

func _apply_output(rates: Dictionary, module: Dictionary) -> void:
	for resource_name in rates.keys():
		var before = int(resources.get(resource_name, 0))
		var cap = int(capacities.get(resource_name, before))
		resources[resource_name] = min(cap, before + int(rates[resource_name]))
		if int(resources[resource_name]) == before and before >= cap:
			module["status"] = "storage_full"

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
	if int(workers["free"]) < stage.worker_required:
		return {"ok": false, "reason": "Not enough free workers"}
	resources["food"] -= stage.food_cost
	active_external_run = {
		"id": stage.id,
		"display_name": stage.display_name,
		"remaining": stage.duration,
		"duration": stage.duration,
		"worker_required": stage.worker_required,
	}
	_recalculate_city_stats()
	external_run_started.emit(active_external_run.duplicate(true))
	resource_changed.emit(resources.duplicate(), capacities.duplicate(), workers.duplicate())
	return {"ok": true, "run": active_external_run.duplicate(true)}

func choose_reward(index: int) -> Dictionary:
	if index < 0 or index >= reward_choices.size():
		return {"ok": false, "reason": "Reward index out of range"}
	if hand.size() >= MAX_HAND:
		return {"ok": false, "reason": "Hand is full"}
	var card_id = reward_choices[index]
	hand.append(card_id)
	reward_choices.clear()
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
		if String(module.get("status", "")) in ["running", "busy", "constrained"]:
			var path = get_path_to_core(i)
			if path.size() > 1:
				var points: Array[Vector2] = []
				for module_index in path:
					points.append(module_center_world(module_index))
				routes.append({
					"key": _transport_route_key(i, path),
					"module_uid": String(module["uid"]),
					"points": points,
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
	var success = stage.danger < 0.5
	var food_gain = stage.base_food_reward.x if success else int(stage.base_food_reward.x * 0.3)
	var soil_gain = stage.base_soil_reward.x if success else int(stage.base_soil_reward.x * 0.3)
	resources["food"] = min(capacities["food"], resources["food"] + food_gain)
	resources["soil"] = min(capacities["soil"], resources["soil"] + soil_gain)
	active_external_run["success"] = success
	external_run_finished.emit(active_external_run.duplicate(true))
	if success:
		reward_choices = []
		for card_id in stage.card_reward_pool:
			if module_defs.has(card_id) and reward_choices.size() < 3:
				reward_choices.append(card_id)
		reward_choice_ready.emit(reward_choices.duplicate())
	active_external_run.clear()
	_recalculate_city_stats()
	resource_changed.emit(resources.duplicate(), capacities.duplicate(), workers.duplicate())

func _new_module_state(card_id: String, origin: Vector2i, rotation_steps: int) -> Dictionary:
	return {
		"uid": "%s_%d" % [card_id, modules.size()],
		"module_id": card_id,
		"origin": origin,
		"rotation": posmod(rotation_steps, 4),
		"status": "idle",
		"efficiency": 1.0,
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
	var exploring = int(active_external_run.get("worker_required", 0))
	var total_demand = worker_demand + exploring
	workers = {
		"total": total_workers,
		"demand": worker_demand,
		"exploring": exploring,
		"free": max(0, total_workers - worker_demand - exploring),
		"satisfaction": 1.0 if worker_demand == 0 else min(1.0, float(max(0, total_workers - exploring)) / float(worker_demand)),
	}

func _excavate_around(origin: Vector2i, size: Vector2i, radius: int) -> void:
	for x in range(origin.x - radius, origin.x + size.x + radius):
		for y in range(origin.y - radius, origin.y + size.y + radius):
			if x >= 0 and y >= 0 and x < GRID_SIZE.x and y < GRID_SIZE.y:
				excavated[_cell_key(Vector2i(x, y))] = true

func _emit_state() -> void:
	resource_changed.emit(resources.duplicate(), capacities.duplicate(), workers.duplicate())
	hand_changed.emit(hand.duplicate())
