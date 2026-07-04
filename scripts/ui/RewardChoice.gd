extends PanelContainer
class_name RewardChoice

signal reward_picked(index: int)

var cards_box: HBoxContainer

func _ready() -> void:
	visible = false
	custom_minimum_size = Vector2(560, 150)
	var root = VBoxContainer.new()
	add_child(root)
	var title = Label.new()
	title.text = "Choose one module"
	title.add_theme_font_size_override("font_size", 18)
	root.add_child(title)
	cards_box = HBoxContainer.new()
	root.add_child(cards_box)

func show_choices(card_ids: Array[String], module_defs: Dictionary) -> void:
	visible = true
	for child in cards_box.get_children():
		child.queue_free()
	for i in range(card_ids.size()):
		var data = module_defs[card_ids[i]]
		var button = Button.new()
		button.custom_minimum_size = Vector2(170, 92)
		button.text = "%s\n%dF %dS\n%s" % [data.display_name, data.build_cost_food, data.build_cost_soil, data.description_short]
		var index = i
		button.pressed.connect(func() -> void: reward_picked.emit(index))
		cards_box.add_child(button)

func hide_choices() -> void:
	visible = false
