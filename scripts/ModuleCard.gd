extends Button
class_name ModuleCard

signal card_selected(card_id: String)
signal card_rotated(card_id: String, rotation_steps: int)

var card_id: String = ""
var rotation_steps: int = 0
var data

func setup(module_data, affordable: bool = true) -> void:
	data = module_data
	card_id = data.id
	rotation_steps = 0
	disabled = false
	custom_minimum_size = Vector2(150, 92)
	_update_text(affordable)

func _ready() -> void:
	pressed.connect(_on_pressed)

func rotate_card() -> void:
	rotation_steps = posmod(rotation_steps + 1, 4)
	_update_text(not disabled)
	card_rotated.emit(card_id, rotation_steps)

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
		rotate_card()
		accept_event()

func _on_pressed() -> void:
	card_selected.emit(card_id)

func _update_text(affordable: bool) -> void:
	if data == null:
		return
	var size = data.rotated_size(rotation_steps)
	var cost = "%dF %dS" % [data.build_cost_food, data.build_cost_soil]
	text = "%s\n%dx%d R%d\n%s" % [data.display_name, size.x, size.y, rotation_steps, cost]
	modulate = Color.WHITE if affordable else Color(1.0, 0.55, 0.45, 1.0)
