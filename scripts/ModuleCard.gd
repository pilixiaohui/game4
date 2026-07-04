extends Button
class_name ModuleCard

signal card_selected(card_id: String)
signal card_rotated(card_id: String, rotation_steps: int)

var card_id: String = ""
var rotation_steps: int = 0
var data
var current_resources: Dictionary = {}

func setup(module_data, resources: Dictionary = {}) -> void:
	data = module_data
	card_id = data.id
	current_resources = resources.duplicate()
	rotation_steps = 0
	disabled = false
	custom_minimum_size = Vector2(150, 92)
	_update_text(resources)

func _ready() -> void:
	pressed.connect(_on_pressed)

func rotate_card() -> void:
	rotation_steps = posmod(rotation_steps + 1, 4)
	_update_text(current_resources)
	card_rotated.emit(card_id, rotation_steps)

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
		rotate_card()
		accept_event()

func _on_pressed() -> void:
	card_selected.emit(card_id)

func _update_text(resources: Dictionary) -> void:
	if data == null:
		return
	var size = data.rotated_size(rotation_steps)
	var cost = "%dF %dS" % [data.build_cost_food, data.build_cost_soil]
	var deficit = _deficit_text(resources)
	text = "%s\n%dx%d R%d\n%s%s" % [data.display_name, size.x, size.y, rotation_steps, cost, deficit]
	var affordable: bool = deficit == ""
	modulate = Color.WHITE if affordable else Color(1.0, 0.55, 0.45, 1.0)

func _deficit_text(resources: Dictionary) -> String:
	if resources.is_empty():
		return ""
	var missing: Array[String] = []
	var food_gap = data.build_cost_food - int(resources.get("food", 0))
	var soil_gap = data.build_cost_soil - int(resources.get("soil", 0))
	if food_gap > 0:
		missing.append("+%dF" % food_gap)
	if soil_gap > 0:
		missing.append("+%dS" % soil_gap)
	if missing.is_empty():
		return ""
	return "\nNeed %s" % " ".join(missing)
