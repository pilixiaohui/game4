extends PanelContainer
class_name RewardChoice

signal reward_picked(index: int)

var cards_box: HBoxContainer

func _ready() -> void:
	visible = false
	custom_minimum_size = Vector2(760, 350)
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.08, 0.075, 0.06, 0.96)
	panel_style.border_color = Color(0.82, 0.62, 0.24, 0.9)
	panel_style.set_border_width_all(2)
	panel_style.set_content_margin_all(18)
	add_theme_stylebox_override("panel", panel_style)
	var root = VBoxContainer.new()
	root.add_theme_constant_override("separation", 14)
	add_child(root)
	var title = Label.new()
	title.text = "Choose one module"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 22)
	root.add_child(title)
	cards_box = HBoxContainer.new()
	cards_box.add_theme_constant_override("separation", 14)
	root.add_child(cards_box)

func show_choices(card_ids: Array[String], module_defs: Dictionary, reward_context: Dictionary = {}) -> void:
	visible = true
	for child in cards_box.get_children():
		child.queue_free()
	for i in range(card_ids.size()):
		var data = module_defs[card_ids[i]]
		cards_box.add_child(_build_card(i, data, String(reward_context.get(card_ids[i], ""))))

func hide_choices() -> void:
	visible = false

func _build_card(index: int, data, reason: String = "") -> Control:
	var panel = PanelContainer.new()
	panel.custom_minimum_size = Vector2(230, 245)
	var card_style := StyleBoxFlat.new()
	card_style.bg_color = Color(0.12, 0.105, 0.08, 1.0)
	card_style.border_color = Color(0.55, 0.39, 0.18, 1.0)
	card_style.set_border_width_all(2)
	card_style.set_content_margin_all(12)
	panel.add_theme_stylebox_override("panel", card_style)
	var root = VBoxContainer.new()
	root.add_theme_constant_override("separation", 8)
	panel.add_child(root)
	var title = Label.new()
	title.text = data.display_name
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 18)
	root.add_child(title)
	var details = Label.new()
	details.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	details.text = "Cost: %dF %dS\nWorkers: %d\n%s" % [
		data.build_cost_food,
		data.build_cost_soil,
		data.worker_need,
		data.description_short,
	]
	root.add_child(details)
	if reason != "":
		var reason_label = Label.new()
		reason_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		reason_label.text = reason
		reason_label.add_theme_color_override("font_color", Color(1.0, 0.86, 0.45, 1.0))
		root.add_child(reason_label)
	var spacer = Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(spacer)
	var button = Button.new()
	button.custom_minimum_size = Vector2(0, 40)
	button.text = "Choose"
	button.pressed.connect(func() -> void: reward_picked.emit(index))
	root.add_child(button)
	return panel
