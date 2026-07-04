extends Node2D
class_name NestModule

signal module_pressed(uid: String)

const ModuleDataScript := preload("res://scripts/data/ModuleData.gd")

var module_state: Dictionary = {}
var module_data
var cell_size: int = 56
var selected: bool = false

func setup(state: Dictionary, data, p_cell_size: int) -> void:
	module_state = state.duplicate(true)
	module_data = data
	cell_size = p_cell_size
	position = Vector2(module_state["origin"] * cell_size)
	queue_redraw()

func update_state(state: Dictionary) -> void:
	module_state = state.duplicate(true)
	queue_redraw()

func set_selected(value: bool) -> void:
	selected = value
	queue_redraw()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		var rect = _local_rect()
		if rect.has_point(to_local(get_global_mouse_position())):
			module_pressed.emit(String(module_state["uid"]))
			get_viewport().set_input_as_handled()

func _draw() -> void:
	if module_data == null:
		return
	var rect = _local_rect()
	draw_rect(rect.grow(-3), _fill_color(), true)
	draw_rect(rect.grow(-3), Color(0.05, 0.03, 0.02, 1.0), false, 3.0)
	draw_rect(rect.grow(-8), Color(1.0, 0.80, 0.34, 0.20), false, 1.5)
	if selected:
		draw_rect(rect.grow(-1), Color(1.0, 0.86, 0.35, 1.0), false, 3.0)
	_draw_connectors(rect)
	_draw_status_bar(rect)

func _local_rect() -> Rect2:
	var size = module_data.rotated_size(int(module_state.get("rotation", 0)))
	return Rect2(Vector2.ZERO, Vector2(size * cell_size))

func _fill_color() -> Color:
	match module_data.category:
		"core":
			return Color(0.62, 0.28, 0.22, 1.0)
		"corridor":
			return Color(0.42, 0.30, 0.18, 1.0)
		"production":
			return Color(0.24, 0.50, 0.28, 1.0)
		"storage":
			return Color(0.33, 0.42, 0.58, 1.0)
		"capacity":
			return Color(0.54, 0.38, 0.58, 1.0)
		"entrance":
			return Color(0.70, 0.55, 0.24, 1.0)
		"support":
			return Color(0.45, 0.46, 0.30, 1.0)
	return Color(0.35, 0.28, 0.22, 1.0)

func _draw_connectors(rect: Rect2) -> void:
	var connectors = module_data.rotated_connectors(int(module_state.get("rotation", 0)))
	var points = {
		ModuleDataScript.TOP: Vector2(rect.size.x * 0.5, 0),
		ModuleDataScript.RIGHT: Vector2(rect.size.x, rect.size.y * 0.5),
		ModuleDataScript.BOTTOM: Vector2(rect.size.x * 0.5, rect.size.y),
		ModuleDataScript.LEFT: Vector2(0, rect.size.y * 0.5),
	}
	for direction in connectors.keys():
		if bool(connectors[direction]):
			draw_circle(points[direction], 7.0, Color(1.0, 0.92, 0.32, 1.0))
			draw_circle(points[direction], 3.0, Color(0.25, 0.15, 0.04, 1.0))

func _draw_status_bar(rect: Rect2) -> void:
	var efficiency = clampf(float(module_state.get("efficiency", 1.0)), 0.0, 1.0)
	var bar_rect = Rect2(Vector2(6, rect.size.y - 10), Vector2((rect.size.x - 12) * efficiency, 4))
	var status = String(module_state.get("status", "idle"))
	var color = Color(0.25, 0.9, 0.35, 1.0)
	if status == "constrained":
		color = Color(1.0, 0.72, 0.18, 1.0)
	elif status in ["storage_full", "stalled", "disconnected"]:
		color = Color(1.0, 0.25, 0.16, 1.0)
	draw_rect(bar_rect, color, true)
