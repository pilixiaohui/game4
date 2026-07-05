extends SceneTree

const SCREENSHOT_DIR := "user://visual_smoke"

var failures: Array[String] = []

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var dir := DirAccess.open("user://")
	if dir != null:
		dir.make_dir_recursive("visual_smoke")
	var main_scene = load("res://scenes/Main.tscn")
	var main = main_scene.instantiate()
	root.add_child(main)
	await process_frame
	await _capture("01_start.png")
	main.get_node("UILayer/StartOverlay/StartPanel/VBox/StartButton").pressed.emit()
	await process_frame
	await _capture("02_nest.png")

	var state = main.get_node("GameState")
	_assert(not state.request_place_module("digging_room", Vector2i(0, 0), 0)["ok"], "Illegal placement is rejected")
	main._on_feedback("Cell is not excavated")
	await process_frame
	await _capture("03_illegal_place.png")

	_assert(state.request_place_module("straight_corridor", Vector2i(4, 2), 0)["ok"], "Corridor placed")
	_assert(state.request_place_module("digging_room", Vector2i(4, 1), 0)["ok"], "Digging room placed")
	_assert(state.request_place_module("fungus_farm", Vector2i(2, 3), 0)["ok"], "Fungus farm placed")
	main._rebuild_modules()
	main._refresh_all()
	for i in range(15):
		state.simulate_tick(1.0)
		await process_frame
	await _capture("04_transport.png")

	_supply_ui_smoke_resources(state)
	for i in range(80):
		state.simulate_tick(1.0)
	_supply_ui_smoke_card(state, "storage_chamber")
	_assert(state.request_place_module("storage_chamber", Vector2i(6, 3), 0)["ok"], "Storage placed")
	_supply_ui_smoke_resources(state)
	for i in range(80):
		state.simulate_tick(1.0)
	_supply_ui_smoke_card(state, "nursery")
	_assert(state.request_place_module("nursery", Vector2i(2, 5), 0)["ok"], "Nursery placed")
	_supply_ui_smoke_resources(state)
	for i in range(80):
		state.simulate_tick(1.0)
	_assert(state.request_place_module("surface_entrance", Vector2i(6, 4), 0)["ok"], "Entrance placed")
	main._rebuild_modules()
	main._refresh_all()
	var entrance_uid := _module_uid(state, "surface_entrance")
	main._on_module_pressed(entrance_uid)
	await process_frame
	await _capture("05_entrance_ready.png")
	_assert(state.start_external_stage("near_debris")["ok"], "Exploration started")
	state.active_external_run["result_roll"] = 0.0
	main._refresh_selected_popup()
	await process_frame
	await _capture("06_exploring.png")
	for i in range(int(state.external_stages["near_debris"].duration) + 1):
		state.simulate_tick(1.0)
		await process_frame
	main._on_reward_choice_ready(state.reward_choices)
	await process_frame
	await _capture("07_reward_modal.png")

	if failures.is_empty():
		print("Visual smoke passed. Uses supplied resources and seeded success for UI coverage only. Screenshots: %s" % ProjectSettings.globalize_path(SCREENSHOT_DIR))
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		quit(1)

func _capture(file_name: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	var image := root.get_viewport().get_texture().get_image()
	image.save_png("%s/%s" % [SCREENSHOT_DIR, file_name])

func _assert(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)

func _module_uid(state, module_id: String) -> String:
	for module_state in state.modules:
		if String(module_state["module_id"]) == module_id:
			return String(module_state["uid"])
	return ""

func _supply_ui_smoke_resources(state) -> void:
	state.resources["food"] = state.capacities["food"]
	state.resources["soil"] = state.capacities["soil"]

func _supply_ui_smoke_card(state, card_id: String) -> void:
	if not state.hand.has(card_id):
		state.hand.append(card_id)
