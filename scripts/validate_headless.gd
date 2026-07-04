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
	_assert(main.get_node_or_null("GameState") != null, "Main creates GameState")
	_assert(main.get_node_or_null("WorldRoot/NestGrid") != null, "Main creates Node2D nest grid")
	_assert(main.get_node_or_null("UILayer/BottomHandTray") != null, "Main creates hand tray UI")
	main.queue_free()

	var state = GameStateScript.new()
	root.add_child(state)
	state.reset_game()

	_assert(state.modules.size() == 1, "Queen core starts placed")
	_assert(state.hand.has("straight_corridor"), "Opening hand has a corridor")
	_assert(not state.can_place_module("digging_room", Vector2i(0, 0), 0)["ok"], "Cannot place without city connector")
	_assert(not state.can_place_module("straight_corridor", Vector2i(4, 3), 0)["ok"], "Cannot place on occupied cells")

	_assert(state.request_place_module("straight_corridor", Vector2i(4, 2), 0)["ok"], "Places corridor with matching connector")
	_assert(state.request_place_module("digging_room", Vector2i(4, 1), 0)["ok"], "Places digging room through corridor")
	_assert(state.request_place_module("fungus_farm", Vector2i(2, 3), 0)["ok"], "Places fungus farm next to core")

	var food_before = int(state.resources["food"])
	var soil_before = int(state.resources["soil"])
	for i in range(60):
		state.simulate_tick(1.0)
	_assert(int(state.resources["food"]) > food_before, "Fungus farm produces food")
	_assert(int(state.resources["soil"]) > soil_before, "Digging room produces soil")

	var food_cap_before = int(state.capacities["food"])
	var soil_cap_before = int(state.capacities["soil"])
	_assert(state.request_place_module("storage_chamber", Vector2i(6, 3), 0)["ok"], "Places storage chamber")
	_assert(int(state.capacities["food"]) > food_cap_before, "Storage raises food capacity")
	_assert(int(state.capacities["soil"]) > soil_cap_before, "Storage raises soil capacity")

	for i in range(80):
		state.simulate_tick(1.0)
	_assert(state.request_place_module("nursery", Vector2i(2, 5), 0)["ok"], "Places nursery")
	_assert(int(state.workers["total"]) >= 9, "Nursery raises worker capacity")
	_assert(state.request_place_module("surface_entrance", Vector2i(6, 4), 0)["ok"], "Places connected surface entrance")
	_assert(state.has_external_entrance(), "Connected entrance unlocks exploration")

	var start_result: Dictionary = state.start_external_stage("near_debris")
	_assert(start_result["ok"], "Starts external exploration when entrance and workers are available")
	for i in range(21):
		state.simulate_tick(1.0)
	_assert(state.reward_choices.size() == 3, "Exploration creates three reward choices")
	var hand_before: int = state.hand.size()
	_assert(state.choose_reward(0)["ok"], "Chooses one reward card")
	_assert(state.hand.size() == hand_before + 1, "Reward card enters hand")

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
