extends SceneTree

const GameStateScript := preload("res://scripts/GameState.gd")

var failures: Array[String] = []

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var main_scene = load("res://scenes/Main.tscn")
	_assert(main_scene != null, "Main scene loads")
	var main = main_scene.instantiate()
	root.add_child(main)
	await process_frame
	_assert(main.get_script() != null, "Main script is attached and compiled")
	_assert(main.get_node_or_null("GameState") != null, "Main creates GameState")
	_assert(main.get_node_or_null("WorldRoot/NestGrid") != null, "Main creates Node2D nest grid")
	_assert(main.get_node_or_null("WorldRoot/AntTrafficLayer") != null, "Main creates transport path layer")
	_assert(main.get_node_or_null("UILayer/BottomHandTray") != null, "Main creates hand tray UI")
	_assert(main.get_node("UILayer/BottomHandTray").get_child_count() > 0, "Main populates module hand UI")
	_assert(main.get_node_or_null("UILayer/StartOverlay") != null, "Main creates start overlay")
	_assert(main.get_node("UILayer/StartOverlay").visible, "Start overlay is visible on first screen")
	_assert(main.get_node_or_null("UILayer/ModalDimmer") != null, "Main creates modal dimmer")
	_assert(not main.get_node("UILayer/ModalDimmer").visible, "Modal dimmer starts hidden")
	main.queue_free()

	var state = GameStateScript.new()
	root.add_child(state)
	state.reset_game()

	# Invariant: scene boot creates the authoritative game state and object layers.
	_assert(state.catalog_errors.is_empty(), "Catalog ids, connectors, and reward references validate")
	_assert(state.modules.size() == 1, "Queen core starts placed")
	_assert(state.hand.has("straight_corridor"), "Opening hand has a corridor")

	# Invariant: invalid placement attempts have no gameplay side effects.
	_assert_invalid_place_has_no_side_effects(state, "straight_corridor", Vector2i(4, 3), 0, "occupied cell is rejected")
	_assert_invalid_place_has_no_side_effects(state, "digging_room", Vector2i(0, 0), 0, "unexcavated cell is rejected")
	_assert_invalid_place_has_no_side_effects(state, "digging_room", Vector2i(2, 1), 0, "excavated but disconnected module is rejected")
	_assert_invalid_place_has_no_side_effects(state, "straight_corridor", Vector2i(6, 3), 0, "connector mismatch is rejected")
	var saved_resources: Dictionary = state.resources.duplicate(true)
	state.resources["soil"] = 1
	_assert_invalid_place_has_no_side_effects(state, "straight_corridor", Vector2i(4, 2), 0, "insufficient resources are rejected")
	state.resources = saved_resources

	# Invariant: valid connector placement mutates authoritative state exactly once.
	var before_place := _snapshot_state(state)
	_assert(state.request_place_module("straight_corridor", Vector2i(4, 2), 0)["ok"], "Places corridor with matching connector")
	_assert_eq(int(state.resources["food"]), int(before_place["resources"]["food"]), "Free food cost is not deducted")
	_assert_eq(int(state.resources["soil"]), int(before_place["resources"]["soil"]) - 2, "Corridor deducts exact soil cost")
	_assert(not state.hand.has("straight_corridor"), "Placed corridor card leaves hand")
	_assert_eq(state.modules.size(), int(before_place["module_count"]) + 1, "Valid placement adds one module")

	before_place = _snapshot_state(state)
	_assert(state.request_place_module("digging_room", Vector2i(4, 1), 0)["ok"], "Places digging room through corridor")
	_assert_eq(int(state.resources["food"]), int(before_place["resources"]["food"]) - 2, "Digging room deducts exact food cost")
	_assert_eq(int(state.resources["soil"]), int(before_place["resources"]["soil"]) - 5, "Digging room deducts exact soil cost")

	before_place = _snapshot_state(state)
	_assert(state.request_place_module("fungus_farm", Vector2i(2, 3), 0)["ok"], "Places fungus farm next to core")
	_assert_eq(int(state.resources["food"]), int(before_place["resources"]["food"]) - 4, "Fungus farm deducts exact food cost")
	_assert_eq(int(state.resources["soil"]), int(before_place["resources"]["soil"]) - 6, "Fungus farm deducts exact soil cost")

	# Invariant: connected production changes resources through tick simulation.
	var food_before = int(state.resources["food"])
	var soil_before = int(state.resources["soil"])
	for i in range(60):
		state.simulate_tick(1.0)
	_assert(int(state.resources["food"]) > food_before, "Fungus farm produces food")
	_assert(int(state.resources["soil"]) > soil_before, "Digging room produces soil")
	var fungus_index := _module_index(state, "fungus_farm")
	_assert(fungus_index >= 0, "Production test has fungus farm")
	if fungus_index >= 0:
		var fungus_state: Dictionary = state.modules[fungus_index]
		_assert(fungus_state.has("pending_output"), "Production module tracks pending output")
		_assert(fungus_state.has("delivered_this_tick"), "Production module tracks transported delivery")
	_assert(not state.transport_routes.is_empty(), "Transport routes are tracked for active production")
	_assert(state.city_pressure.has("throughput_pressure"), "City pressure includes throughput pressure")

	# Invariant: capacity modules change caps and full storage blocks overflow.
	var food_cap_before = int(state.capacities["food"])
	var soil_cap_before = int(state.capacities["soil"])
	before_place = _snapshot_state(state)
	_assert(state.request_place_module("storage_chamber", Vector2i(6, 3), 0)["ok"], "Places storage chamber")
	_assert_eq(int(state.resources["food"]), int(before_place["resources"]["food"]) - 2, "Storage deducts exact food cost")
	_assert_eq(int(state.resources["soil"]), int(before_place["resources"]["soil"]) - 8, "Storage deducts exact soil cost")
	_assert(int(state.capacities["food"]) > food_cap_before, "Storage raises food capacity")
	_assert(int(state.capacities["soil"]) > soil_cap_before, "Storage raises soil capacity")
	state.resources["food"] = state.capacities["food"]
	var capped_food := int(state.resources["food"])
	var waste_before := int(state.overflow_waste["food"])
	for i in range(35):
		state.simulate_tick(1.0)
	_assert_eq(int(state.resources["food"]), capped_food, "Food production does not overflow capacity")
	_assert(int(state.overflow_waste["food"]) > waste_before, "Full storage records overflow waste")

	_grant_build_resources(state)
	before_place = _snapshot_state(state)
	_assert(state.request_place_module("nursery", Vector2i(2, 5), 0)["ok"], "Places nursery")
	_assert_eq(int(state.resources["food"]), int(before_place["resources"]["food"]) - 10, "Nursery deducts exact food cost")
	_assert_eq(int(state.resources["soil"]), int(before_place["resources"]["soil"]) - 8, "Nursery deducts exact soil cost")
	_assert(int(state.workers["total"]) >= 9, "Nursery raises worker capacity")
	_assert_eq(int(state.workers["total"]), int(before_place["workers"]["total"]) + 3, "Nursery raises worker capacity by exact amount")
	_assert_eq(int(state.resources["food"]), min(int(state.resources["food"]), int(state.capacities["food"])), "Food remains within capacity after nursery")
	_assert_eq(int(state.resources["soil"]), min(int(state.resources["soil"]), int(state.capacities["soil"])), "Soil remains within capacity after nursery")

	_grant_build_resources(state)
	before_place = _snapshot_state(state)
	_assert(state.request_place_module("surface_entrance", Vector2i(6, 4), 0)["ok"], "Places connected surface entrance")
	_assert_eq(int(state.resources["food"]), int(before_place["resources"]["food"]) - 12, "Entrance deducts exact food cost")
	_assert_eq(int(state.resources["soil"]), int(before_place["resources"]["soil"]) - 12, "Entrance deducts exact soil cost")
	_assert(state.has_external_entrance(), "Connected entrance unlocks exploration")

	# Invariant: external runs require a connected entrance and workers reduce production efficiency.
	var no_entrance_state = GameStateScript.new()
	root.add_child(no_entrance_state)
	no_entrance_state.reset_game()
	_assert(not no_entrance_state.start_external_stage("near_debris")["ok"], "Exploration is rejected without a connected entrance")
	_assert(no_entrance_state.active_external_run.is_empty(), "Rejected exploration does not create an active run")
	no_entrance_state.queue_free()

	var shortage_state = GameStateScript.new()
	root.add_child(shortage_state)
	shortage_state.reset_game()
	_build_worker_shortage_state(shortage_state)
	_assert(float(shortage_state.workers["satisfaction"]) < 1.0, "Worker over-demand lowers worker satisfaction")
	shortage_state.simulate_tick(1.0)
	var shortage_fungus_index := _module_index(shortage_state, "fungus_farm")
	_assert(shortage_fungus_index >= 0, "Shortage state has fungus farm")
	if shortage_fungus_index >= 0:
		var shortage_fungus: Dictionary = shortage_state.modules[shortage_fungus_index]
		_assert(float(shortage_fungus["efficiency"]) < 1.0, "Worker shortage lowers production efficiency")
	shortage_state.queue_free()

	var chance_normal := float(state.external_stage_preview("near_debris")["success_chance"])
	_assert(chance_normal > 0.1 and chance_normal < 0.9, "Exploration preview exposes bounded success chance")
	var pre_explore := _snapshot_state(state)
	var start_result: Dictionary = state.start_external_stage("near_debris")
	_assert(start_result["ok"], "Starts external exploration when entrance and workers are available")
	_assert_eq(int(state.resources["food"]), int(pre_explore["resources"]["food"]) - 4, "Exploration deducts exact food cost")
	_assert_eq(int(state.workers["exploring"]), 2, "Exploration reserves exact worker count")
	_assert(state.active_external_run.has("city_pressure_snapshot"), "Exploration freezes city pressure context")
	_assert(state.active_external_run.has("result_roll"), "Exploration stores deterministic result roll")
	var duplicate_before := _snapshot_state(state)
	_assert(not state.start_external_stage("near_debris")["ok"], "Duplicate exploration start is rejected")
	_assert_same_snapshot(duplicate_before, _snapshot_state(state), "Duplicate exploration has no side effects")

	# Invariant: completed exploration creates exactly one selectable reward outcome from rules.
	state.active_external_run["result_roll"] = 0.0
	for i in range(21):
		state.simulate_tick(1.0)
	_assert_eq(String(state.last_external_result.get("result", "")), "success", "Low roll resolves exploration as success")
	_assert(state.reward_choices.size() == 3, "Exploration creates three reward choices")
	_assert(not state.reward_choice_context.is_empty(), "Reward choices include rule reasons")
	_assert(state.active_external_run.is_empty(), "Finished exploration clears active run")
	var hand_before: int = state.hand.size()
	var chosen_card := ""
	if not state.reward_choices.is_empty():
		chosen_card = String(state.reward_choices[0])
	_assert(state.choose_reward(0)["ok"], "Chooses one reward card")
	_assert(state.hand.size() == hand_before + 1, "Reward card enters hand")
	_assert(state.hand.has(chosen_card), "Chosen reward card is the card added to hand")
	_assert(state.reward_choices.is_empty(), "Choosing a reward clears the other choices")

	# Invariant: exploration outcomes are reproducible and have three result bands.
	var partial_state = GameStateScript.new()
	root.add_child(partial_state)
	partial_state.reset_game()
	_build_exploration_ready_state(partial_state)
	_assert(partial_state.start_external_stage("near_debris")["ok"], "Partial setup starts exploration")
	partial_state.active_external_run["result_roll"] = min(0.94, float(partial_state.active_external_run["success_chance"]) + 0.1)
	for i in range(25):
		partial_state.simulate_tick(1.0)
	_assert_eq(String(partial_state.last_external_result.get("result", "")), "partial", "Mid roll resolves exploration as partial")
	partial_state.queue_free()

	var failure_state = GameStateScript.new()
	root.add_child(failure_state)
	failure_state.reset_game()
	_build_exploration_ready_state(failure_state)
	_assert(failure_state.start_external_stage("near_debris")["ok"], "Failure setup starts risky exploration")
	failure_state.active_external_run["result_roll"] = 0.99
	for i in range(25):
		failure_state.simulate_tick(1.0)
	_assert_eq(String(failure_state.last_external_result.get("result", "")), "failure", "High roll resolves exploration as failure")
	_assert(failure_state.reward_choices.is_empty(), "Failure does not grant normal card choices")
	failure_state.queue_free()

	# Invariant: city pressure shapes rewards instead of returning a fixed trio.
	var pressure_state = GameStateScript.new()
	root.add_child(pressure_state)
	pressure_state.reset_game()
	_build_exploration_ready_state(pressure_state)
	pressure_state.resources["food"] = pressure_state.capacities["food"]
	pressure_state.resources["soil"] = pressure_state.capacities["soil"]
	pressure_state.simulate_tick(1.0)
	_assert(float(pressure_state.city_pressure["capacity_pressure"]) > 0.0, "Capacity pressure is computed from full storage")
	_assert(pressure_state.start_external_stage("near_debris")["ok"], "Pressure reward setup starts exploration")
	pressure_state.active_external_run["result_roll"] = 0.0
	for i in range(25):
		pressure_state.simulate_tick(1.0)
	_assert(pressure_state.reward_choices.has("storage_chamber"), "Capacity pressure injects storage into reward choices")
	pressure_state.queue_free()

	# Invariant: digging progress unlocks frontier cells over time, not on placement.
	var dig_state = GameStateScript.new()
	root.add_child(dig_state)
	dig_state.reset_game()
	_grant_build_resources(dig_state)
	var excavated_before: int = dig_state.excavated.size()
	_assert(dig_state.request_place_module("straight_corridor", Vector2i(4, 2), 0)["ok"], "Dig setup places corridor")
	_grant_build_resources(dig_state)
	_assert(dig_state.request_place_module("digging_room", Vector2i(4, 1), 0)["ok"], "Dig setup places digging room")
	_assert_eq(dig_state.excavated.size(), excavated_before, "Placing digging room does not instantly excavate extra cells")
	for i in range(35):
		dig_state.simulate_tick(1.0)
	_assert(dig_state.excavated.size() > excavated_before, "Digging room unlocks frontier through progress")
	dig_state.queue_free()

	if failures.is_empty():
		print("Headless validation passed.")
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		quit(1)

func _assert(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)

func _assert_eq(actual, expected, message: String) -> void:
	if actual != expected:
		failures.append("%s (expected %s, got %s)" % [message, str(expected), str(actual)])

func _assert_invalid_place_has_no_side_effects(state, card_id: String, origin: Vector2i, rotation_steps: int, message: String) -> void:
	var before := _snapshot_state(state)
	var result: Dictionary = state.request_place_module(card_id, origin, rotation_steps)
	_assert(not bool(result["ok"]), message)
	_assert_same_snapshot(before, _snapshot_state(state), "%s has no side effects" % message)

func _assert_same_snapshot(before: Dictionary, after: Dictionary, message: String) -> void:
	_assert(before["resources"] == after["resources"], "%s: resources unchanged" % message)
	_assert(before["capacities"] == after["capacities"], "%s: capacities unchanged" % message)
	_assert(before["workers"] == after["workers"], "%s: workers unchanged" % message)
	_assert(before["hand"] == after["hand"], "%s: hand unchanged" % message)
	_assert(before["module_count"] == after["module_count"], "%s: module count unchanged" % message)
	_assert(before["occupied_count"] == after["occupied_count"], "%s: occupied count unchanged" % message)
	_assert(before["reward_choices"] == after["reward_choices"], "%s: reward choices unchanged" % message)
	_assert(before["active_external_run"] == after["active_external_run"], "%s: active run unchanged" % message)
	_assert(before["pending_outputs"] == after["pending_outputs"], "%s: pending outputs unchanged" % message)
	_assert(before["overflow_waste"] == after["overflow_waste"], "%s: overflow waste unchanged" % message)

func _snapshot_state(state) -> Dictionary:
	return {
		"resources": state.resources.duplicate(true),
		"capacities": state.capacities.duplicate(true),
		"workers": state.workers.duplicate(true),
		"hand": state.hand.duplicate(),
		"module_count": state.modules.size(),
		"occupied_count": state.occupied.size(),
		"reward_choices": state.reward_choices.duplicate(),
		"active_external_run": state.active_external_run.duplicate(true),
		"pending_outputs": _pending_outputs_snapshot(state),
		"overflow_waste": state.overflow_waste.duplicate(true),
	}

func _pending_outputs_snapshot(state) -> Array:
	var result: Array = []
	for module in state.modules:
		result.append(module.get("pending_output", {}).duplicate(true))
	return result

func _module_index(state, module_id: String) -> int:
	for i in range(state.modules.size()):
		if String(state.modules[i]["module_id"]) == module_id:
			return i
	return -1

func _build_worker_shortage_state(state) -> void:
	_grant_build_resources(state)
	_assert(state.request_place_module("straight_corridor", Vector2i(4, 2), 0)["ok"], "Shortage setup places corridor")
	_grant_build_resources(state)
	_assert(state.request_place_module("digging_room", Vector2i(4, 1), 0)["ok"], "Shortage setup places digging room")
	_grant_build_resources(state)
	_assert(state.request_place_module("fungus_farm", Vector2i(2, 3), 0)["ok"], "Shortage setup places fungus farm")
	_grant_build_resources(state)
	_assert(state.request_place_module("storage_chamber", Vector2i(6, 3), 0)["ok"], "Shortage setup places storage")
	_grant_build_resources(state)
	_assert(state.request_place_module("surface_entrance", Vector2i(6, 4), 0)["ok"], "Shortage setup places entrance")
	_grant_build_resources(state)
	_assert(state.request_place_module("corner_corridor", Vector2i(5, 2), 1)["ok"], "Shortage setup places corner corridor")
	state.hand.append("sorter")
	_grant_build_resources(state)
	_assert(state.request_place_module("sorter", Vector2i(6, 2), 0)["ok"], "Shortage setup places sorter")
	state.hand.append("storage_chamber")
	_grant_build_resources(state)
	_assert(state.request_place_module("storage_chamber", Vector2i(2, 5), 0)["ok"], "Shortage setup places second storage")

func _build_exploration_ready_state(state) -> void:
	_grant_build_resources(state)
	_assert(state.request_place_module("straight_corridor", Vector2i(4, 2), 0)["ok"], "Explore setup places corridor")
	_grant_build_resources(state)
	_assert(state.request_place_module("digging_room", Vector2i(4, 1), 0)["ok"], "Explore setup places digging room")
	_grant_build_resources(state)
	_assert(state.request_place_module("fungus_farm", Vector2i(2, 3), 0)["ok"], "Explore setup places fungus farm")
	_grant_build_resources(state)
	_assert(state.request_place_module("storage_chamber", Vector2i(6, 3), 0)["ok"], "Explore setup places storage")
	_grant_build_resources(state)
	_assert(state.request_place_module("nursery", Vector2i(2, 5), 0)["ok"], "Explore setup places nursery")
	_grant_build_resources(state)
	_assert(state.request_place_module("surface_entrance", Vector2i(6, 4), 0)["ok"], "Explore setup places entrance")
	_grant_build_resources(state)

func _grant_build_resources(state) -> void:
	state.resources["food"] = state.capacities["food"]
	state.resources["soil"] = state.capacities["soil"]
