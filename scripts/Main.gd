extends Node

const NestModuleScript := preload("res://scripts/NestModule.gd")
const ModuleCardScript := preload("res://scripts/ModuleCard.gd")
const AntAgentScript := preload("res://scripts/AntAgent.gd")

const CELL_SIZE := 56

@onready var state = $GameState
@onready var grid = $WorldRoot/NestGrid
@onready var module_layer: Node2D = $WorldRoot/ModuleLayer
@onready var ant_layer: Node2D = $WorldRoot/AntTrafficLayer
@onready var resource_label: Label = $UILayer/TopResourceBar
@onready var hand_tray: HBoxContainer = $UILayer/BottomHandTray
@onready var feedback_label: Label = $UILayer/FeedbackQueue
@onready var stockpile_choice_bar: HBoxContainer = $UILayer/StockpileChoiceBar
@onready var food_crew_button: Button = $UILayer/StockpileChoiceBar/FoodCrewButton
@onready var soil_crew_button: Button = $UILayer/StockpileChoiceBar/SoilCrewButton
@onready var tunnel_crew_button: Button = $UILayer/StockpileChoiceBar/TunnelCrewButton
@onready var balanced_crew_button: Button = $UILayer/StockpileChoiceBar/BalancedCrewButton
@onready var popup = $UILayer/ObjectPopup
@onready var modal_dimmer: ColorRect = $UILayer/ModalDimmer
@onready var reward_choice = $UILayer/RewardChoice
@onready var start_overlay: ColorRect = $UILayer/StartOverlay
@onready var start_button: Button = $UILayer/StartOverlay/StartPanel/VBox/StartButton
@onready var simulation_timer: Timer = $SimulationTimer

var selected_card_id: String = ""
var selected_rotation: int = 0
var selected_module_uid: String = ""
var module_nodes: Dictionary = {}
var ant_agents: Dictionary = {}

func _ready() -> void:
	grid.configure(Vector2i(10, 8), CELL_SIZE)
	modal_dimmer.mouse_filter = Control.MOUSE_FILTER_STOP
	start_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	_wire_signals()
	simulation_timer.stop()
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

func _wire_signals() -> void:
	grid.grid_clicked.connect(_on_grid_clicked)
	state.resource_changed.connect(_on_resource_changed)
	state.hand_changed.connect(_on_hand_changed)
	state.module_placed.connect(_on_module_placed)
	state.module_status_changed.connect(_on_module_status_changed)
	state.external_run_started.connect(_on_external_run_changed)
	state.external_run_finished.connect(_on_external_run_changed)
	state.reward_choice_ready.connect(_on_reward_choice_ready)
	state.feedback.connect(_on_feedback)
	popup.external_stage_selected.connect(_on_external_stage_selected)
	reward_choice.reward_picked.connect(_on_reward_picked)
	start_button.pressed.connect(_on_start_pressed)
	food_crew_button.pressed.connect(func() -> void: _on_work_order_selected("food_crew"))
	soil_crew_button.pressed.connect(func() -> void: _on_work_order_selected("soil_crew"))
	tunnel_crew_button.pressed.connect(func() -> void: _on_work_order_selected("tunnel_crew"))
	balanced_crew_button.pressed.connect(func() -> void: _on_work_order_selected("balanced"))
	simulation_timer.timeout.connect(func() -> void: state.simulate_tick(1.0))

func _on_start_pressed() -> void:
	start_overlay.visible = false
	simulation_timer.start()

func _refresh_all() -> void:
	grid.set_excavated(state.excavated)
	_on_resource_changed(state.resources, state.capacities, state.workers)
	_on_hand_changed(state.hand)
	_sync_ants()

func _on_resource_changed(resources: Dictionary, capacities: Dictionary, workers: Dictionary) -> void:
	var goal: Dictionary = state.nest_goal_summary()
	resource_label.text = "Food %d/%d   Soil %d/%d   Workers %d free / %d total   Flow %d%%\n%s - %s" % [
		resources["food"],
		capacities["food"],
		resources["soil"],
		capacities["soil"],
		workers["free"],
		workers["total"],
		int(round(float(workers["satisfaction"]) * 100.0)),
		String(goal.get("label", "Nest is stable")),
		String(goal.get("action", _pressure_summary())),
	]
	_refresh_hand_affordability()
	_refresh_stockpile_choices()
	_refresh_selected_popup()

func _on_hand_changed(hand: Array[String]) -> void:
	for child in hand_tray.get_children():
		child.queue_free()
	for card_id in hand:
		var data = state.module_defs[card_id]
		var card = ModuleCardScript.new()
		card.setup(data, state.resources)
		card.card_selected.connect(_on_card_selected)
		card.card_rotated.connect(_on_card_rotated)
		hand_tray.add_child(card)

func _refresh_hand_affordability() -> void:
	for child in hand_tray.get_children():
		if child.get_script() == ModuleCardScript:
			child.setup(child.data, state.resources)

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
		_sync_ants()
	else:
		_on_feedback(result["reason"])

func _on_module_placed(module_state: Dictionary) -> void:
	_create_module_node(module_state)
	grid.set_excavated(state.excavated)
	_sync_ants()

func _on_module_status_changed(module_state: Dictionary) -> void:
	var uid = String(module_state["uid"])
	if module_nodes.has(uid):
		module_nodes[uid].update_state(module_state)
	if uid == selected_module_uid:
			var data = state.module_defs[module_state["module_id"]]
			popup.show_module(module_state, data, state.external_stages, state.active_external_run, state.external_stage_previews(), _city_status())
	_sync_ants()

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
			popup.show_module(module_state, data, state.external_stages, state.active_external_run, state.external_stage_previews(), _city_status())
			return

func _clear_module_selection() -> void:
	for node in module_nodes.values():
		node.set_selected(false)

func _on_external_stage_selected(stage_id: String) -> void:
	var result = state.start_external_stage(stage_id)
	_on_feedback("Exploration started" if result["ok"] else result["reason"])
	_refresh_selected_popup()
	_sync_ants()

func _on_work_order_selected(order_id: String) -> void:
	var result: Dictionary = state.set_work_order(order_id)
	_on_feedback("Crew focus changed" if result.get("ok", false) else String(result.get("reason", "Cannot change crew focus")))

func _on_external_run_changed(_run_state: Dictionary) -> void:
	_refresh_selected_popup()

func _on_reward_choice_ready(cards: Array[String]) -> void:
	popup.hide_popup()
	modal_dimmer.visible = true
	reward_choice.show_choices(cards, state.module_defs, state.reward_choice_context)
	_on_feedback("Exploration returned with module choices")

func _on_reward_picked(index: int) -> void:
	var result = state.choose_reward(index)
	if result["ok"]:
		reward_choice.hide_choices()
		modal_dimmer.visible = false
		_on_feedback("Added %s to hand" % state.module_defs[result["card_id"]].display_name)
	else:
		_on_feedback(result["reason"])

func _on_feedback(message: String) -> void:
	feedback_label.text = message

func _sync_ants() -> void:
	if ant_layer == null:
		return
	var seen := {}
	var routes = state.active_transport_routes()
	if ant_layer.has_method("set_routes"):
		ant_layer.set_routes(routes)
	for route in routes:
		var key := String(route["key"])
		seen[key] = true
		if not ant_agents.has(key):
			var ant = AntAgentScript.new()
			ant.setup(route["points"], 95.0)
			ant_layer.add_child(ant)
			ant_agents[key] = ant
		else:
			ant_agents[key].update_path(route["points"], 95.0)
	for key in ant_agents.keys():
		if not seen.has(key):
			ant_agents[key].queue_free()
			ant_agents.erase(key)

func _refresh_selected_popup() -> void:
	if selected_module_uid == "" or not popup.visible:
		return
	for module_state in state.modules:
		if module_state["uid"] == selected_module_uid:
			var data = state.module_defs[module_state["module_id"]]
			popup.show_module(module_state, data, state.external_stages, state.active_external_run, state.external_stage_previews(), _city_status())
			return

func _refresh_stockpile_choices() -> void:
	var should_show: bool = not state.has_external_entrance() and state.modules.size() >= 3 and state.reward_choices.is_empty()
	stockpile_choice_bar.visible = should_show
	var selected: String = state.work_order
	for button in [food_crew_button, soil_crew_button, tunnel_crew_button, balanced_crew_button]:
		button.disabled = false
		button.modulate = Color.WHITE
	match selected:
		"food_crew":
			food_crew_button.modulate = Color(1.0, 0.86, 0.45, 1.0)
		"soil_crew":
			soil_crew_button.modulate = Color(1.0, 0.86, 0.45, 1.0)
		"tunnel_crew":
			tunnel_crew_button.modulate = Color(1.0, 0.86, 0.45, 1.0)
		"balanced":
			balanced_crew_button.modulate = Color(1.0, 0.86, 0.45, 1.0)

func _pressure_summary() -> String:
	if state.city_pressure.is_empty():
		return "stable"
	var best_key := ""
	var best_value := -1.0
	for key in state.city_pressure.keys():
		var value := float(state.city_pressure[key])
		if value > best_value:
			best_key = String(key)
			best_value = value
	if best_value <= 0.05:
		return "stable"
	return "%s %d%%" % [best_key.replace("_pressure", ""), int(round(best_value * 100.0))]

func _city_status() -> Dictionary:
	return {
		"workers": state.workers.duplicate(true),
		"city_pressure": state.city_pressure.duplicate(true),
		"production_impact": state.production_impact_summary(),
	}
