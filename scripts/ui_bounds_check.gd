extends SceneTree

const VIEWPORT_SIZE := Vector2i(1280, 720)

var failures: Array[String] = []

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("UI bounds check requires a display server. Run it with xvfb-run, not pure --headless.")
		quit(1)
		return

	root.size = VIEWPORT_SIZE
	DisplayServer.window_set_size(VIEWPORT_SIZE)
	var main_scene = load("res://scenes/Main.tscn")
	_assert(main_scene != null, "Main scene loads")
	var main = main_scene.instantiate()
	root.add_child(main)
	await _settle_frames(3)

	_assert_control_inside(main.get_node("UILayer/StartOverlay/StartPanel"), "start panel")
	_assert_control_inside(main.get_node("UILayer/StartOverlay/StartPanel/VBox/StartButton"), "start button")
	main.get_node("UILayer/StartOverlay/StartPanel/VBox/StartButton").pressed.emit()
	await _settle_frames(2)

	var state = main.get_node("GameState")
	_place_opening_for_ui(main, state)
	await _settle_frames(2)
	_assert_control_inside(main.get_node("UILayer/TopResourceBar"), "top resource goal text")
	_assert_control_inside(main.get_node("UILayer/BottomHandTray"), "bottom hand tray")
	_assert_control_inside(main.get_node("UILayer/FeedbackQueue"), "feedback queue")
	_assert_control_inside(main.get_node("UILayer/StockpileChoiceBar"), "stockpile choice bar")
	for button_path in [
		"UILayer/StockpileChoiceBar/FoodCrewButton",
		"UILayer/StockpileChoiceBar/SoilCrewButton",
		"UILayer/StockpileChoiceBar/TunnelCrewButton",
		"UILayer/StockpileChoiceBar/BalancedCrewButton",
	]:
		_assert_control_inside(main.get_node(button_path), button_path.get_file())
	for card in main.get_node("UILayer/BottomHandTray").get_children():
		if card is Control and card.visible:
			_assert_rect_inside((card as Control).get_global_rect(), "visible hand card")

	_place_entrance_for_ui(main, state)
	var entrance_uid := _module_uid(state, "surface_entrance")
	_assert(entrance_uid != "", "UI bounds setup has entrance")
	main._on_module_pressed(entrance_uid)
	await _settle_frames(3)
	var popup = main.get_node("UILayer/ObjectPopup")
	_assert_control_inside(popup, "entrance popup")
	var stage_scroll = popup.find_child("StageScroll", true, false)
	var stage_box = popup.find_child("StageBox", true, false)
	_assert(stage_scroll != null, "entrance popup has StageScroll")
	_assert(stage_box != null, "entrance popup has StageBox")
	if stage_scroll != null:
		_assert_control_inside(stage_scroll, "entrance stage scroll")
	if stage_box != null and stage_box.get_child_count() > 0:
		var first_stage = stage_box.get_child(0)
		if first_stage is Control:
			_assert_control_inside(first_stage, "first entrance stage entry")
		var explore_button = _first_button(first_stage)
		_assert(explore_button != null, "first entrance stage has Explore button")
		if explore_button != null:
			_assert_control_inside(explore_button, "first Explore button")

	state.reward_choices.clear()
	for reward_card_id in ["storage_chamber", "nursery", "sorter"]:
		state.reward_choices.append(reward_card_id)
	main._on_reward_choice_ready(state.reward_choices)
	await _settle_frames(3)
	var reward_choice = main.get_node("UILayer/RewardChoice")
	_assert_control_inside(reward_choice, "reward choice modal")
	if reward_choice.cards_box != null:
		_assert_control_inside(reward_choice.cards_box, "reward card row")
		for reward_card in reward_choice.cards_box.get_children():
			if reward_card is Control:
				_assert_control_inside(reward_card, "reward card")
			var choose_button = _first_button(reward_card)
			_assert(choose_button != null, "reward card has Choose button")
			if choose_button != null:
				_assert_control_inside(choose_button, "reward Choose button")

	if failures.is_empty():
		print("UI bounds check passed: 1280x720 start, work-order, entrance, and reward controls are visible inside the viewport.")
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		quit(1)

func _place_opening_for_ui(main, state) -> void:
	_supply_build_resources(state)
	_assert(state.request_place_module("straight_corridor", Vector2i(4, 2), 0)["ok"], "UI setup places corridor")
	_supply_build_resources(state)
	_assert(state.request_place_module("digging_room", Vector2i(4, 1), 0)["ok"], "UI setup places digging room")
	_supply_build_resources(state)
	_assert(state.request_place_module("fungus_farm", Vector2i(2, 3), 0)["ok"], "UI setup places fungus farm")
	main._rebuild_modules()
	main._refresh_all()

func _place_entrance_for_ui(main, state) -> void:
	_supply_build_resources(state)
	_assert(state.request_place_module("surface_entrance", Vector2i(6, 4), 0)["ok"], "UI setup places entrance")
	main._rebuild_modules()
	main._refresh_all()

func _supply_build_resources(state) -> void:
	state.resources["food"] = state.capacities["food"]
	state.resources["soil"] = state.capacities["soil"]

func _settle_frames(count: int) -> void:
	for i in range(count):
		await process_frame
	await RenderingServer.frame_post_draw

func _assert_control_inside(control: Control, label: String) -> void:
	_assert(control != null, "%s exists" % label)
	if control == null:
		return
	_assert(control.visible and control.is_visible_in_tree(), "%s is visible" % label)
	_assert_rect_inside(control.get_global_rect(), label)

func _assert_rect_inside(rect: Rect2, label: String) -> void:
	var viewport := Rect2(Vector2.ZERO, Vector2(VIEWPORT_SIZE))
	var end := rect.position + rect.size
	_assert(rect.size.x > 0.0 and rect.size.y > 0.0, "%s has non-zero size: %s" % [label, str(rect)])
	_assert(viewport.has_point(rect.position), "%s top-left is inside viewport: %s" % [label, str(rect)])
	_assert(end.x <= viewport.end.x + 0.5 and end.y <= viewport.end.y + 0.5, "%s bottom-right is inside viewport: %s" % [label, str(rect)])

func _module_uid(state, module_id: String) -> String:
	for module_state in state.modules:
		if String(module_state["module_id"]) == module_id:
			return String(module_state["uid"])
	return ""

func _first_button(node: Node) -> Button:
	if node is Button:
		return node
	for child in node.get_children():
		var found := _first_button(child)
		if found != null:
			return found
	return null

func _assert(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
