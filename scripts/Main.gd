extends Node

const GameStateScript := preload("res://scripts/GameState.gd")
const NestGridScript := preload("res://scripts/NestGrid.gd")
const NestModuleScript := preload("res://scripts/NestModule.gd")
const ModuleCardScript := preload("res://scripts/ModuleCard.gd")
const AntAgentScript := preload("res://scripts/AntAgent.gd")
const ObjectPopupScript := preload("res://scripts/ui/ObjectPopup.gd")
const RewardChoiceScript := preload("res://scripts/ui/RewardChoice.gd")

const CELL_SIZE := 56

var state
var world_root: Node2D
var grid
var module_layer: Node2D
var ant_layer: Node2D
var ui_layer: CanvasLayer
var resource_label: Label
var hand_tray: HBoxContainer
var feedback_label: Label
var popup
var reward_choice
var simulation_timer: Timer
var selected_card_id: String = ""
var selected_rotation: int = 0
var selected_module_uid: String = ""
var module_nodes: Dictionary = {}

func _ready() -> void:
	_build_scene_tree()
	_connect_state()
	state.reset_game()
	_rebuild_modules()
	_refresh_all()

func _input(event: InputEvent) -> void:
	if selected_card_id != "" and event.is_action_pressed("rotate_module"):
		selected_rotation = posmod(selected_rotation + 1, 4)
		_update_preview()

func _process(_delta: float) -> void:
	if selected_card_id != "":
		_update_preview()

func _build_scene_tree() -> void:
	state = GameStateScript.new()
	state.name = "GameState"
	add_child(state)

	world_root = Node2D.new()
	world_root.name = "WorldRoot"
	world_root.position = Vector2(120, 84)
	add_child(world_root)

	var camera = Camera2D.new()
	camera.name = "Camera2D"
	camera.position = Vector2(280, 220)
	camera.enabled = true
	world_root.add_child(camera)

	grid = NestGridScript.new()
	grid.name = "NestGrid"
	grid.configure(Vector2i(10, 8), CELL_SIZE)
	world_root.add_child(grid)

	module_layer = Node2D.new()
	module_layer.name = "ModuleLayer"
	world_root.add_child(module_layer)

	ant_layer = Node2D.new()
	ant_layer.name = "AntTrafficLayer"
	world_root.add_child(ant_layer)

	ui_layer = CanvasLayer.new()
	ui_layer.name = "UILayer"
	add_child(ui_layer)

	resource_label = Label.new()
	resource_label.name = "TopResourceBar"
	resource_label.position = Vector2(16, 12)
	resource_label.add_theme_font_size_override("font_size", 20)
	ui_layer.add_child(resource_label)

	hand_tray = HBoxContainer.new()
	hand_tray.name = "BottomHandTray"
	hand_tray.position = Vector2(16, 598)
	hand_tray.size = Vector2(1120, 112)
	ui_layer.add_child(hand_tray)

	feedback_label = Label.new()
	feedback_label.name = "FeedbackQueue"
	feedback_label.position = Vector2(16, 548)
	feedback_label.add_theme_font_size_override("font_size", 16)
	ui_layer.add_child(feedback_label)

	popup = ObjectPopupScript.new()
	popup.name = "ObjectPopup"
	popup.position = Vector2(980, 96)
	ui_layer.add_child(popup)

	reward_choice = RewardChoiceScript.new()
	reward_choice.name = "RewardChoice"
	reward_choice.position = Vector2(360, 230)
	ui_layer.add_child(reward_choice)

	simulation_timer = Timer.new()
	simulation_timer.name = "SimulationTimer"
	simulation_timer.wait_time = 1.0
	simulation_timer.autostart = true
	simulation_timer.timeout.connect(func() -> void: state.simulate_tick(1.0))
	add_child(simulation_timer)

func _connect_state() -> void:
	grid.grid_clicked.connect(_on_grid_clicked)
	state.resource_changed.connect(_on_resource_changed)
	state.hand_changed.connect(_on_hand_changed)
	state.module_placed.connect(_on_module_placed)
	state.module_status_changed.connect(_on_module_status_changed)
	state.reward_choice_ready.connect(_on_reward_choice_ready)
	state.feedback.connect(_on_feedback)
	popup.external_stage_selected.connect(_on_external_stage_selected)
	reward_choice.reward_picked.connect(_on_reward_picked)

func _refresh_all() -> void:
	grid.set_excavated(state.excavated)
	_on_resource_changed(state.resources, state.capacities, state.workers)
	_on_hand_changed(state.hand)
	_refresh_ants()

func _on_resource_changed(resources: Dictionary, capacities: Dictionary, workers: Dictionary) -> void:
	resource_label.text = "Food %d/%d   Soil %d/%d   Workers %d free / %d total   Load %d%%" % [
		resources["food"],
		capacities["food"],
		resources["soil"],
		capacities["soil"],
		workers["free"],
		workers["total"],
		int(round(float(workers["satisfaction"]) * 100.0)),
	]
	_refresh_hand_affordability()
	_refresh_ants()

func _on_hand_changed(hand: Array[String]) -> void:
	for child in hand_tray.get_children():
		child.queue_free()
	for card_id in hand:
		var data = state.module_defs[card_id]
		var card = ModuleCardScript.new()
		card.setup(data, _can_afford(data))
		card.card_selected.connect(_on_card_selected)
		card.card_rotated.connect(_on_card_rotated)
		hand_tray.add_child(card)

func _refresh_hand_affordability() -> void:
	for child in hand_tray.get_children():
		if child.get_script() == ModuleCardScript:
			child.setup(child.data, _can_afford(child.data))

func _can_afford(data) -> bool:
	return state.resources["food"] >= data.build_cost_food and state.resources["soil"] >= data.build_cost_soil

func _on_card_selected(card_id: String) -> void:
	selected_card_id = card_id
	selected_rotation = 0
	selected_module_uid = ""
	_clear_module_selection()
	popup.hide_popup()
	_update_preview()
	_on_feedback("Place %s; press R or right-click a card to rotate" % state.module_defs[card_id].display_name)

func _on_card_rotated(card_id: String, rotation_steps: int) -> void:
	if selected_card_id == card_id:
		selected_rotation = rotation_steps
		_update_preview()

func _update_preview() -> void:
	if selected_card_id == "":
		grid.clear_preview()
		return
	var data = state.module_defs[selected_card_id]
	var cell = grid.world_to_cell(grid.get_global_mouse_position())
	var check = state.can_place_module(selected_card_id, cell, selected_rotation)
	grid.set_preview({
		"active": true,
		"origin": cell,
		"size": data.rotated_size(selected_rotation),
		"ok": bool(check["ok"]),
		"reason": check["reason"],
		"connectors": data.rotated_connectors(selected_rotation),
	})

func _on_grid_clicked(cell: Vector2i) -> void:
	if selected_card_id == "":
		popup.hide_popup()
		_clear_module_selection()
		return
	var result = state.request_place_module(selected_card_id, cell, selected_rotation)
	if result["ok"]:
		selected_card_id = ""
		selected_rotation = 0
		grid.clear_preview()
	else:
		_on_feedback(result["reason"])

func _on_module_placed(module_state: Dictionary) -> void:
	_create_module_node(module_state)
	grid.set_excavated(state.excavated)

func _on_module_status_changed(module_state: Dictionary) -> void:
	var uid = String(module_state["uid"])
	if module_nodes.has(uid):
		module_nodes[uid].update_state(module_state)
	if uid == selected_module_uid:
		var data = state.module_defs[module_state["module_id"]]
		popup.show_module(module_state, data, state.external_stages)

func _rebuild_modules() -> void:
	for child in module_layer.get_children():
		child.queue_free()
	module_nodes.clear()
	for module_state in state.modules:
		_create_module_node(module_state)

func _create_module_node(module_state: Dictionary) -> void:
	var data = state.module_defs[module_state["module_id"]]
	var node = NestModuleScript.new()
	node.setup(module_state, data, CELL_SIZE)
	node.module_pressed.connect(_on_module_pressed)
	module_layer.add_child(node)
	module_nodes[module_state["uid"]] = node

func _on_module_pressed(uid: String) -> void:
	selected_card_id = ""
	grid.clear_preview()
	selected_module_uid = uid
	_clear_module_selection()
	for module_state in state.modules:
		if module_state["uid"] == uid:
			var data = state.module_defs[module_state["module_id"]]
			module_nodes[uid].set_selected(true)
			popup.show_module(module_state, data, state.external_stages)
			return

func _clear_module_selection() -> void:
	for node in module_nodes.values():
		node.set_selected(false)

func _on_external_stage_selected(stage_id: String) -> void:
	var result = state.start_external_stage(stage_id)
	_on_feedback("Exploration started" if result["ok"] else result["reason"])

func _on_reward_choice_ready(cards: Array[String]) -> void:
	reward_choice.show_choices(cards, state.module_defs)
	_on_feedback("Exploration returned with module choices")

func _on_reward_picked(index: int) -> void:
	var result = state.choose_reward(index)
	if result["ok"]:
		reward_choice.hide_choices()
		_on_feedback("Added %s to hand" % state.module_defs[result["card_id"]].display_name)
	else:
		_on_feedback(result["reason"])

func _on_feedback(message: String) -> void:
	feedback_label.text = message

func _refresh_ants() -> void:
	if ant_layer == null:
		return
	for child in ant_layer.get_children():
		child.queue_free()
	for path in state.active_transport_paths():
		var ant = AntAgentScript.new()
		ant.setup(path, 95.0)
		ant_layer.add_child(ant)
