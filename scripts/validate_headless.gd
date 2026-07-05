extends SceneTree

const GameStateScript := preload("res://scripts/GameState.gd")
const StableRulesScript := preload("res://scripts/StableRules.gd")
const GoalAdvisorScript := preload("res://scripts/GoalAdvisor.gd")

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
	_assert(main.get_node_or_null("UILayer/StockpileChoiceBar/FoodCrewButton") != null, "Main exposes stockpile work order choices")
	_assert(main.get_node("UILayer/ObjectPopup").find_child("StageScroll", true, false) != null, "Entrance popup stage list uses a scroll boundary")
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
	var stockpile_goal: Dictionary = state.nest_goal_summary()
	_assert(String(stockpile_goal.get("key", "")) == "stockpile_entrance", "Entrance stockpile phase has a goal")
	_assert(String(stockpile_goal.get("action", "")).contains("Small jobs:"), "Entrance stockpile phase gives small choices or feedback goals")
	_assert(String(stockpile_goal.get("action", "")).contains("Food, Soil, or Tunnel"), "Entrance stockpile phase points to real work order choices")

	# Invariant: connected production changes resources through tick simulation.
	var food_before = int(state.resources["food"])
	var soil_before = int(state.resources["soil"])
	var observed_pending_output := false
	for i in range(90):
		state.simulate_tick(1.0)
		for module_state in state.modules:
			if _pending_total(module_state.get("pending_output", {})) > 0:
				observed_pending_output = true
	_assert(int(state.resources["food"]) > food_before, "Fungus farm produces food")
	_assert(int(state.resources["soil"]) > soil_before, "Digging room produces soil")
	var fungus_index := _module_index(state, "fungus_farm")
	_assert(fungus_index >= 0, "Production test has fungus farm")
	if fungus_index >= 0:
		var fungus_state: Dictionary = state.modules[fungus_index]
		_assert(fungus_state.has("pending_output"), "Production module tracks pending output")
		_assert(fungus_state.has("delivered_this_tick"), "Production module tracks transported delivery")
		_assert(String(fungus_state.get("last_blocker", "")) == "bottleneck", "Low throughput production exposes a bottleneck blocker")
		_assert(observed_pending_output, "Low throughput production leaves pending output during the production cycle")
	_assert(not state.transport_routes.is_empty(), "Transport routes are tracked for active production")
	_assert(state.city_pressure.has("throughput_pressure"), "City pressure includes throughput pressure")

	# Invariant: entrance waiting choices are real work orders, not resource grants.
	_assert_work_order_choices_have_tradeoffs()

	# Invariant: capacity modules change caps and full storage blocks overflow.
	var food_cap_before = int(state.capacities["food"])
	var soil_cap_before = int(state.capacities["soil"])
	_ensure_card(state, "storage_chamber")
	_wait_until_placeable(state, "storage_chamber", Vector2i(6, 3), 0, 180)
	before_place = _snapshot_state(state)
	_assert(state.request_place_module("storage_chamber", Vector2i(6, 3), 0)["ok"], "Places storage chamber")
	_assert_eq(int(state.resources["food"]), int(before_place["resources"]["food"]) - 4, "Storage deducts exact food cost")
	_assert_eq(int(state.resources["soil"]), int(before_place["resources"]["soil"]) - 12, "Storage deducts exact soil cost")
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
	_ensure_card(state, "nursery")
	before_place = _snapshot_state(state)
	_assert(state.request_place_module("nursery", Vector2i(2, 5), 0)["ok"], "Places nursery")
	_assert_eq(int(state.resources["food"]), int(before_place["resources"]["food"]) - 14, "Nursery deducts exact food cost")
	_assert_eq(int(state.resources["soil"]), int(before_place["resources"]["soil"]) - 12, "Nursery deducts exact soil cost")
	_assert(int(state.workers["total"]) >= 10, "Nursery raises worker capacity")
	_assert_eq(int(state.workers["total"]), int(before_place["workers"]["total"]) + 4, "Nursery raises worker capacity by exact amount")
	_assert_eq(int(state.resources["food"]), min(int(state.resources["food"]), int(state.capacities["food"])), "Food remains within capacity after nursery")
	_assert_eq(int(state.resources["soil"]), min(int(state.resources["soil"]), int(state.capacities["soil"])), "Soil remains within capacity after nursery")

	_grant_build_resources(state)
	before_place = _snapshot_state(state)
	_assert(state.request_place_module("surface_entrance", Vector2i(6, 4), 0)["ok"], "Places connected surface entrance")
	_assert_eq(int(state.resources["food"]), int(before_place["resources"]["food"]) - 22, "Entrance deducts exact food cost")
	_assert_eq(int(state.resources["soil"]), int(before_place["resources"]["soil"]) - 22, "Entrance deducts exact soil cost")
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
	var chance_loose := float(state.external_stage_preview("loose_soil")["success_chance"])
	var chance_old := float(state.external_stage_preview("old_root")["success_chance"])
	_assert(_bounded_chance(chance_normal), "Near debris success chance is bounded")
	_assert(_bounded_chance(chance_loose), "Loose soil success chance is bounded")
	_assert(_bounded_chance(chance_old), "Old root success chance is bounded")
	_assert(chance_normal != chance_loose or chance_loose != chance_old, "Different stages expose different success chances")
	var preview_before := _snapshot_state(state)
	state.external_stage_previews()
	state.external_stage_preview("near_debris")
	_assert_same_snapshot(preview_before, _snapshot_state(state), "External stage previews are read-only")
	_assert_eq(StableRulesScript.highest_pressure_key({"food_pressure": 1.0, "throughput_pressure": 1.0}), "throughput_pressure", "Pressure tie-break uses stable priority")
	_assert_eq(StableRulesScript.stable_roll("same-seed"), StableRulesScript.stable_roll("same-seed"), "Stable roll is reproducible")
	var sorter_goal := GoalAdvisorScript.summary({
		"modules": [
			{"module_id": "digging_room"},
			{"module_id": "fungus_farm"},
			{"module_id": "surface_entrance"},
			{"module_id": "sorter"},
		],
		"hand": [],
		"module_defs": {},
		"city_pressure": {"throughput_pressure": 0.65},
		"last_external_result": {"result": "success"},
		"elapsed_seconds": 700.0,
	})
	_assert(String(sorter_goal.get("label", "")).contains("Bottleneck eased"), "Sorter follow-up goal says the bottleneck eased")
	_assert(String(sorter_goal.get("action", "")).contains("remaining jam"), "Sorter follow-up goal still points to the next problem")
	var pre_explore := _snapshot_state(state)
	var start_result: Dictionary = state.start_external_stage("near_debris")
	_assert(start_result["ok"], "Starts external exploration when entrance and workers are available")
	_assert_eq(int(state.resources["food"]), int(pre_explore["resources"]["food"]) - 6, "Exploration deducts exact food cost")
	_assert_eq(int(state.workers["exploring"]), 3, "Exploration reserves exact worker count")
	_assert(state.active_external_run.has("city_pressure_snapshot"), "Exploration freezes city pressure context")
	_assert(state.active_external_run.has("result_roll"), "Exploration stores deterministic result roll")
	var duplicate_before := _snapshot_state(state)
	_assert(not state.start_external_stage("near_debris")["ok"], "Duplicate exploration start is rejected")
	_assert_same_snapshot(duplicate_before, _snapshot_state(state), "Duplicate exploration has no side effects")

	# Invariant: completed exploration creates exactly one selectable reward outcome from rules.
	state.active_external_run["result_roll"] = 0.0
	for i in range(int(state.external_stages["near_debris"].duration) + 1):
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

	var full_hand_state = GameStateScript.new()
	root.add_child(full_hand_state)
	full_hand_state.reset_game()
	full_hand_state.reward_choices.clear()
	full_hand_state.reward_choices.append("fungus_farm")
	full_hand_state.reward_choices.append("storage_chamber")
	full_hand_state.reward_choices.append("nursery")
	while full_hand_state.hand.size() < 7:
		full_hand_state.hand.append("straight_corridor")
	var full_hand_before := _snapshot_state(full_hand_state)
	_assert(not full_hand_state.choose_reward(0)["ok"], "Full hand rejects reward choice")
	_assert_same_snapshot(full_hand_before, _snapshot_state(full_hand_state), "Full hand reward rejection has no side effects")
	full_hand_state.queue_free()

	# Invariant: exploration outcomes are reproducible and have three result bands.
	var partial_state = GameStateScript.new()
	root.add_child(partial_state)
	partial_state.reset_game()
	_build_exploration_ready_state(partial_state)
	_assert(partial_state.start_external_stage("near_debris")["ok"], "Partial setup starts exploration")
	partial_state.active_external_run["result_roll"] = min(0.94, float(partial_state.active_external_run["success_chance"]) + 0.1)
	for i in range(int(partial_state.external_stages["near_debris"].duration) + 1):
		partial_state.simulate_tick(1.0)
	_assert_eq(String(partial_state.last_external_result.get("result", "")), "partial", "Mid roll resolves exploration as partial")
	partial_state.queue_free()

	var failure_state = GameStateScript.new()
	root.add_child(failure_state)
	failure_state.reset_game()
	_build_exploration_ready_state(failure_state)
	_assert(failure_state.start_external_stage("near_debris")["ok"], "Failure setup starts risky exploration")
	failure_state.active_external_run["result_roll"] = 0.99
	for i in range(int(failure_state.external_stages["near_debris"].duration) + 1):
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
	for i in range(int(pressure_state.external_stages["near_debris"].duration) + 1):
		pressure_state.simulate_tick(1.0)
	_assert(pressure_state.reward_choices.size() == 3, "Pressure reward setup still creates three choices")
	_assert(pressure_state.reward_choice_context.size() > 0, "Pressure reward setup records rule reasons")
	pressure_state.queue_free()

	var reward_probe = GameStateScript.new()
	root.add_child(reward_probe)
	reward_probe.reset_game()
	var fixed_near_debris := ["straight_corridor", "fungus_farm", "storage_chamber"]
	var capacity_rewards := _reward_set_for_pressure(reward_probe, "near_debris", "capacity_pressure")
	var worker_rewards := _reward_set_for_pressure(reward_probe, "near_debris", "worker_pressure")
	var throughput_rewards := _reward_set_for_pressure(reward_probe, "near_debris", "throughput_pressure")
	var soil_rewards := _reward_set_for_pressure(reward_probe, "near_debris", "soil_pressure")
	_assert(capacity_rewards.has("storage_chamber"), "Capacity pressure can still offer storage")
	_assert(capacity_rewards.has("overflow_silo"), "Capacity pressure also offers a cheaper storage tradeoff")
	_assert(not _same_card_set(capacity_rewards, fixed_near_debris), "A fixed pool card appearing is not enough to prove pressure-shaped rewards")
	_assert(worker_rewards.has("nursery"), "Worker pressure changes same-stage rewards toward worker capacity")
	_assert(worker_rewards.has("shift_roost"), "Worker pressure also offers a smaller worker tradeoff")
	_assert(throughput_rewards.has("sorter"), "Throughput pressure can offer Sorter")
	_assert(throughput_rewards.has("relay_junction"), "Throughput pressure also offers Relay Junction")
	_assert(soil_rewards.has("digging_room"), "Soil pressure changes same-stage rewards toward soil production")
	_assert(_pressure_solution_count(reward_probe, capacity_rewards, "capacity_pressure") >= 2, "Same stage has at least two capacity solutions")
	_assert(_pressure_solution_count(reward_probe, worker_rewards, "worker_pressure") >= 2, "Same stage has at least two worker solutions")
	_assert(_pressure_solution_count(reward_probe, throughput_rewards, "throughput_pressure") >= 2, "Same stage has at least two throughput solutions")
	_assert(_set_key(capacity_rewards) != _set_key(worker_rewards), "Same stage has different reward set under capacity vs worker pressure")
	_assert(_set_key(worker_rewards) != _set_key(soil_rewards), "Same stage has different reward set under worker vs soil pressure")
	_assert(_set_key(throughput_rewards) != _set_key(capacity_rewards), "Same stage has different reward set under throughput vs capacity pressure")
	reward_probe.queue_free()

	var visible_impact_state = GameStateScript.new()
	root.add_child(visible_impact_state)
	visible_impact_state.reset_game()
	_build_exploration_ready_state_without_nursery(visible_impact_state)
	_assert(int(visible_impact_state.workers["free"]) < int(visible_impact_state.external_stages["loose_soil"].worker_required), "Impact setup has fewer free workers than exploration requires")
	var before_explore_satisfaction := float(visible_impact_state.workers["satisfaction"])
	var before_explore_fungus_index := _module_index(visible_impact_state, "fungus_farm")
	var before_explore_efficiency := 1.0
	if before_explore_fungus_index >= 0:
		before_explore_efficiency = float(visible_impact_state.modules[before_explore_fungus_index].get("efficiency", 1.0))
	_assert(visible_impact_state.start_external_stage("loose_soil")["ok"], "Exploration can draw workers from active production when total workers are enough")
	visible_impact_state.simulate_tick(1.0)
	var impacted_fungus_index := _module_index(visible_impact_state, "fungus_farm")
	_assert(impacted_fungus_index >= 0, "Visible impact setup has fungus farm")
	if impacted_fungus_index >= 0:
		var impacted_fungus: Dictionary = visible_impact_state.modules[impacted_fungus_index]
		_assert(float(visible_impact_state.workers["satisfaction"]) < before_explore_satisfaction, "Exploration lowers global worker satisfaction")
		_assert(float(impacted_fungus["worker_effect"]) < 1.0, "Exploration lowers production module worker effect")
		_assert(float(impacted_fungus["efficiency"]) < before_explore_efficiency, "Exploration visibly lowers production module efficiency")
		_assert(String(impacted_fungus["last_blocker"]) == "no_workers", "Exploration exposes no_workers blocker on production module")
	var impact_summary: Dictionary = visible_impact_state.production_impact_summary()
	_assert(float(impact_summary["worker_satisfaction"]) < 1.0, "Production impact summary exposes global worker satisfaction")
	_assert(int(impact_summary["constrained_count"]) > 0, "Production impact summary exposes constrained production count")
	visible_impact_state.queue_free()

	# Invariant: support rewards create measurable 3-5 minute consequences when installed.
	var storage_effect_state = GameStateScript.new()
	root.add_child(storage_effect_state)
	storage_effect_state.reset_game()
	_build_basic_production_state(storage_effect_state)
	storage_effect_state.resources["food"] = storage_effect_state.capacities["food"] - 1
	for i in range(180):
		storage_effect_state.simulate_tick(1.0)
	var waste_without_storage := int(storage_effect_state.overflow_waste["food"])
	_ensure_card(storage_effect_state, "storage_chamber")
	_grant_build_resources(storage_effect_state)
	_assert(storage_effect_state.request_place_module("storage_chamber", Vector2i(6, 3), 0)["ok"], "Storage consequence setup places storage")
	storage_effect_state.resources["food"] = 49
	storage_effect_state.overflow_waste["food"] = 0
	for i in range(180):
		storage_effect_state.simulate_tick(1.0)
	_assert(int(storage_effect_state.overflow_waste["food"]) < waste_without_storage, "Storage reward reduces overflow waste within 3 minutes")
	storage_effect_state.queue_free()

	var silo_effect_state = GameStateScript.new()
	root.add_child(silo_effect_state)
	silo_effect_state.reset_game()
	_build_basic_production_state(silo_effect_state)
	var silo_food_cap_before := int(silo_effect_state.capacities["food"])
	_ensure_card(silo_effect_state, "overflow_silo")
	_grant_build_resources(silo_effect_state)
	_assert(silo_effect_state.request_place_module("overflow_silo", Vector2i(6, 3), 0)["ok"], "Overflow Silo consequence setup places silo")
	_assert(int(silo_effect_state.capacities["food"]) > silo_food_cap_before, "Overflow Silo raises capacity")
	_assert(int(silo_effect_state.capacities["food"]) < int(silo_effect_state.module_defs["storage_chamber"].storage["food"]) + 50, "Overflow Silo has a smaller capacity payoff than Storage Chamber")
	silo_effect_state.queue_free()

	var nursery_effect_state = GameStateScript.new()
	root.add_child(nursery_effect_state)
	nursery_effect_state.reset_game()
	_build_exploration_ready_state_without_nursery(nursery_effect_state)
	_assert(nursery_effect_state.start_external_stage("loose_soil")["ok"], "Nursery consequence setup starts worker pressure")
	nursery_effect_state.simulate_tick(1.0)
	var satisfaction_before_nursery := float(nursery_effect_state.workers["satisfaction"])
	_ensure_card(nursery_effect_state, "nursery")
	_grant_build_resources(nursery_effect_state)
	_assert(nursery_effect_state.request_place_module("nursery", Vector2i(2, 5), 0)["ok"], "Nursery consequence setup places nursery")
	for i in range(180):
		nursery_effect_state.simulate_tick(1.0)
	_assert(float(nursery_effect_state.workers["satisfaction"]) > satisfaction_before_nursery, "Nursery reward improves worker satisfaction within 3 minutes")
	nursery_effect_state.queue_free()

	var roost_effect_state = GameStateScript.new()
	root.add_child(roost_effect_state)
	roost_effect_state.reset_game()
	_build_exploration_ready_state_without_nursery(roost_effect_state)
	var workers_before_roost := int(roost_effect_state.workers["total"])
	_ensure_card(roost_effect_state, "shift_roost")
	_grant_build_resources(roost_effect_state)
	_assert(roost_effect_state.request_place_module("shift_roost", Vector2i(6, 3), 0)["ok"], "Shift Roost consequence setup places roost")
	_assert_eq(int(roost_effect_state.workers["total"]), workers_before_roost + 2, "Shift Roost adds fewer workers than Nursery")
	_assert(int(roost_effect_state.module_defs["shift_roost"].build_cost_food + roost_effect_state.module_defs["shift_roost"].build_cost_soil) < int(roost_effect_state.module_defs["nursery"].build_cost_food + roost_effect_state.module_defs["nursery"].build_cost_soil), "Shift Roost is cheaper than Nursery")
	roost_effect_state.queue_free()

	var sorter_effect_state = GameStateScript.new()
	root.add_child(sorter_effect_state)
	sorter_effect_state.reset_game()
	_build_basic_production_state(sorter_effect_state)
	sorter_effect_state.simulate_tick(1.0)
	var sorter_fungus_index := _module_index(sorter_effect_state, "fungus_farm")
	_assert(sorter_fungus_index >= 0, "Sorter consequence setup has fungus farm")
	var route_before_sorter: Dictionary = sorter_effect_state._route_for_module(sorter_fungus_index)
	_ensure_card(sorter_effect_state, "sorter")
	_grant_build_resources(sorter_effect_state)
	_assert(sorter_effect_state.request_place_module("sorter", Vector2i(6, 3), 0)["ok"], "Sorter consequence setup places sorter")
	sorter_effect_state.simulate_tick(1.0)
	var route_after_sorter: Dictionary = sorter_effect_state._route_for_module(sorter_fungus_index)
	_assert(int(route_after_sorter.get("capacity", 0)) > int(route_before_sorter.get("capacity", 0)), "Sorter reward raises adjacent route capacity")
	_assert(float(route_after_sorter.get("load_ratio", 99.0)) < float(route_before_sorter.get("load_ratio", 0.0)), "Sorter reward lowers route load pressure")
	sorter_effect_state.queue_free()

	var relay_effect_state = GameStateScript.new()
	root.add_child(relay_effect_state)
	relay_effect_state.reset_game()
	_build_basic_production_state(relay_effect_state)
	relay_effect_state.simulate_tick(1.0)
	var relay_fungus_index := _module_index(relay_effect_state, "fungus_farm")
	var route_before_relay: Dictionary = relay_effect_state._route_for_module(relay_fungus_index)
	_ensure_card(relay_effect_state, "relay_junction")
	_grant_build_resources(relay_effect_state)
	_assert(relay_effect_state.request_place_module("relay_junction", Vector2i(6, 3), 0)["ok"], "Relay Junction consequence setup places relay")
	relay_effect_state.simulate_tick(1.0)
	var route_after_relay: Dictionary = relay_effect_state._route_for_module(relay_fungus_index)
	_assert(int(route_after_relay.get("capacity", 0)) > int(route_before_relay.get("capacity", 0)), "Relay Junction also raises adjacent route capacity")
	_assert(int(route_after_sorter.get("capacity", 0)) > int(route_after_relay.get("capacity", 0)), "Sorter has a stronger route payoff than Relay Junction")
	relay_effect_state.queue_free()

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

func _assert_work_order_choices_have_tradeoffs() -> void:
	var food_state = GameStateScript.new()
	root.add_child(food_state)
	food_state.reset_game()
	_build_basic_production_state(food_state)
	food_state.resources["food"] = 0
	food_state.resources["soil"] = 0
	var food_before := _snapshot_state(food_state)
	_assert(food_state.set_work_order("food_crew")["ok"], "Food Crew work order is accepted")
	_assert_eq(food_before["resources"], _snapshot_state(food_state)["resources"], "Work order choice does not grant resources")
	for i in range(120):
		food_state.simulate_tick(1.0)
	var food_focus_food := int(food_state.resources["food"])
	var food_focus_soil := int(food_state.resources["soil"])
	food_state.queue_free()

	var soil_state = GameStateScript.new()
	root.add_child(soil_state)
	soil_state.reset_game()
	_build_basic_production_state(soil_state)
	soil_state.resources["food"] = 0
	soil_state.resources["soil"] = 0
	_assert(soil_state.set_work_order("soil_crew")["ok"], "Soil Crew work order is accepted")
	for i in range(120):
		soil_state.simulate_tick(1.0)
	var soil_focus_food := int(soil_state.resources["food"])
	var soil_focus_soil := int(soil_state.resources["soil"])
	soil_state.queue_free()

	var tunnel_state = GameStateScript.new()
	root.add_child(tunnel_state)
	tunnel_state.reset_game()
	_build_basic_production_state(tunnel_state)
	tunnel_state.simulate_tick(1.0)
	var fungus_index := _module_index(tunnel_state, "fungus_farm")
	var balanced_route: Dictionary = tunnel_state._route_for_module(fungus_index)
	_assert(tunnel_state.set_work_order("tunnel_crew")["ok"], "Tunnel Crew work order is accepted")
	tunnel_state.simulate_tick(1.0)
	var tunnel_route: Dictionary = tunnel_state._route_for_module(fungus_index)
	_assert(int(tunnel_route.get("capacity", 0)) > int(balanced_route.get("capacity", 0)), "Tunnel Crew raises route capacity")
	tunnel_state.queue_free()

	_assert(food_focus_food > soil_focus_food, "Food Crew produces more food than Soil Crew")
	_assert(soil_focus_soil > food_focus_soil, "Soil Crew produces more soil than Food Crew")

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
	_assert(before["city_pressure"] == after["city_pressure"], "%s: city pressure unchanged" % message)
	_assert(before["transport_routes"] == after["transport_routes"], "%s: transport routes unchanged" % message)

func _wait_until_placeable(state, card_id: String, origin: Vector2i, rotation: int, max_seconds: int) -> void:
	for i in range(max_seconds + 1):
		if bool(state.can_place_module(card_id, origin, rotation).get("ok", false)):
			return
		state.simulate_tick(1.0)
	_assert(false, "Timed out waiting for %s to become placeable" % card_id)

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
		"city_pressure": state.city_pressure.duplicate(true),
		"transport_routes": state.transport_routes.duplicate(true),
	}

func _pending_outputs_snapshot(state) -> Array:
	var result: Array = []
	for module in state.modules:
		result.append(module.get("pending_output", {}).duplicate(true))
	return result

func _pending_total(pending: Dictionary) -> int:
	var total := 0
	for amount in pending.values():
		total += int(amount)
	return total

func _bounded_chance(value: float) -> bool:
	return value >= 0.1 and value <= 0.9

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
	_ensure_card(state, "storage_chamber")
	_grant_build_resources(state)
	_assert(state.request_place_module("storage_chamber", Vector2i(6, 3), 0)["ok"], "Shortage setup places storage")
	_grant_build_resources(state)
	_assert(state.request_place_module("surface_entrance", Vector2i(6, 4), 0)["ok"], "Shortage setup places entrance")
	_grant_build_resources(state)
	_assert(state.request_place_module("corner_corridor", Vector2i(5, 2), 1)["ok"], "Shortage setup places corner corridor")
	state.hand.append("sorter")
	_grant_build_resources(state)
	_assert(state.request_place_module("sorter", Vector2i(6, 2), 0)["ok"], "Shortage setup places sorter")
	_ensure_card(state, "storage_chamber")
	_grant_build_resources(state)
	_assert(state.request_place_module("storage_chamber", Vector2i(2, 5), 0)["ok"], "Shortage setup places second storage")

func _build_basic_production_state(state) -> void:
	_grant_build_resources(state)
	_assert(state.request_place_module("straight_corridor", Vector2i(4, 2), 0)["ok"], "Basic production setup places corridor")
	_grant_build_resources(state)
	_assert(state.request_place_module("digging_room", Vector2i(4, 1), 0)["ok"], "Basic production setup places digging room")
	_grant_build_resources(state)
	_assert(state.request_place_module("fungus_farm", Vector2i(2, 3), 0)["ok"], "Basic production setup places fungus farm")

func _build_exploration_ready_state(state) -> void:
	_grant_build_resources(state)
	_assert(state.request_place_module("straight_corridor", Vector2i(4, 2), 0)["ok"], "Explore setup places corridor")
	_grant_build_resources(state)
	_assert(state.request_place_module("digging_room", Vector2i(4, 1), 0)["ok"], "Explore setup places digging room")
	_grant_build_resources(state)
	_assert(state.request_place_module("fungus_farm", Vector2i(2, 3), 0)["ok"], "Explore setup places fungus farm")
	_ensure_card(state, "storage_chamber")
	_grant_build_resources(state)
	_assert(state.request_place_module("storage_chamber", Vector2i(6, 3), 0)["ok"], "Explore setup places storage")
	_ensure_card(state, "nursery")
	_grant_build_resources(state)
	_assert(state.request_place_module("nursery", Vector2i(2, 5), 0)["ok"], "Explore setup places nursery")
	_grant_build_resources(state)
	_assert(state.request_place_module("surface_entrance", Vector2i(6, 4), 0)["ok"], "Explore setup places entrance")
	_grant_build_resources(state)

func _build_exploration_ready_state_without_nursery(state) -> void:
	_grant_build_resources(state)
	_assert(state.request_place_module("straight_corridor", Vector2i(4, 2), 0)["ok"], "Impact setup places corridor")
	_grant_build_resources(state)
	_assert(state.request_place_module("digging_room", Vector2i(4, 1), 0)["ok"], "Impact setup places digging room")
	_grant_build_resources(state)
	_assert(state.request_place_module("fungus_farm", Vector2i(2, 3), 0)["ok"], "Impact setup places fungus farm")
	_grant_build_resources(state)
	_assert(state.request_place_module("surface_entrance", Vector2i(6, 4), 0)["ok"], "Impact setup places entrance")
	_grant_build_resources(state)

func _ensure_card(state, card_id: String) -> void:
	if not state.hand.has(card_id):
		state.hand.append(card_id)

func _reward_set_for_pressure(state, stage_id: String, pressure_key: String) -> Array[String]:
	state.city_pressure = _pressure_dict(pressure_key)
	state.active_external_run = {"id": stage_id}
	state.reward_choices.clear()
	state.reward_choice_context.clear()
	state.draw_count = 0
	state._generate_reward_choices(state.external_stages[stage_id], "success")
	var result: Array[String] = []
	for card_id in state.reward_choices:
		result.append(String(card_id))
	state.active_external_run.clear()
	return result

func _pressure_dict(active_key: String) -> Dictionary:
	return {
		"food_pressure": 0.0 if active_key != "food_pressure" else 1.0,
		"soil_pressure": 0.0 if active_key != "soil_pressure" else 1.0,
		"worker_pressure": 0.0 if active_key != "worker_pressure" else 1.0,
		"capacity_pressure": 0.0 if active_key != "capacity_pressure" else 1.0,
		"throughput_pressure": 0.0 if active_key != "throughput_pressure" else 1.0,
		"expansion_pressure": 0.0 if active_key != "expansion_pressure" else 1.0,
	}

func _same_card_set(left: Array, right: Array) -> bool:
	if left.size() != right.size():
		return false
	for card_id in left:
		if not right.has(card_id):
			return false
	return true

func _set_key(cards: Array) -> String:
	var copy: Array[String] = []
	for card_id in cards:
		copy.append(String(card_id))
	copy.sort()
	return "|".join(copy)

func _pressure_solution_count(state, cards: Array, pressure_key: String) -> int:
	var count := 0
	for card_id in cards:
		if not state.module_defs.has(card_id):
			continue
		var data = state.module_defs[card_id]
		if data.solves_pressure.has(pressure_key):
			count += 1
	return count

func _grant_build_resources(state) -> void:
	state.resources["food"] = state.capacities["food"]
	state.resources["soil"] = state.capacities["soil"]
