extends Node2D
class_name NestGrid

signal grid_clicked(cell: Vector2i)

var grid_size: Vector2i = Vector2i(10, 8)
var cell_size: int = 56
var excavated: Dictionary = {}
var preview = {
	"active": false,
	"origin": Vector2i.ZERO,
	"size": Vector2i.ONE,
	"ok": false,
	"reason": "",
	"connectors": {},
}

func configure(p_grid_size: Vector2i, p_cell_size: int) -> void:
	grid_size = p_grid_size
	cell_size = p_cell_size
	queue_redraw()

func set_excavated(cells: Dictionary) -> void:
	excavated = cells.duplicate()
	queue_redraw()

func set_preview(value: Dictionary) -> void:
	preview = value.duplicate(true)
	queue_redraw()

func clear_preview() -> void:
	preview = {"active": false}
	queue_redraw()

func world_to_cell(world_position: Vector2) -> Vector2i:
	var local = to_local(world_position)
	return Vector2i(floori(local.x / cell_size), floori(local.y / cell_size))

func cell_to_world(cell: Vector2i) -> Vector2:
	return Vector2(cell * cell_size)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		var cell = world_to_cell(get_global_mouse_position())
		if cell.x >= 0 and cell.y >= 0 and cell.x < grid_size.x and cell.y < grid_size.y:
			grid_clicked.emit(cell)

func _draw() -> void:
	for x in range(grid_size.x):
		for y in range(grid_size.y):
			var cell = Vector2i(x, y)
			var rect = Rect2(Vector2(cell * cell_size), Vector2(cell_size, cell_size))
			var fill = Color(0.11, 0.085, 0.055, 1.0)
			if excavated.has(_cell_key(cell)):
				fill = Color(0.24, 0.16, 0.09, 1.0)
			draw_rect(rect.grow(-1), fill, true)
			draw_rect(rect.grow(-1), Color(0.42, 0.30, 0.18, 0.55), false, 1.0)
	if bool(preview.get("active", false)):
		_draw_preview()

func _draw_preview() -> void:
	var origin: Vector2i = preview.get("origin", Vector2i.ZERO)
	var size: Vector2i = preview.get("size", Vector2i.ONE)
	var ok = bool(preview.get("ok", false))
	var color = Color(0.1, 0.9, 0.45, 0.38) if ok else Color(0.95, 0.25, 0.16, 0.38)
	var outline = Color(0.3, 1.0, 0.55, 1.0) if ok else Color(1.0, 0.25, 0.16, 1.0)
	var rect = Rect2(Vector2(origin * cell_size), Vector2(size * cell_size))
	draw_rect(rect.grow(-2), color, true)
	draw_rect(rect.grow(-2), outline, false, 3.0)
	var connectors: Dictionary = preview.get("connectors", {})
	var center = rect.get_center()
	for direction in connectors.keys():
		if not bool(connectors[direction]):
			continue
		var point = center
		match direction:
			"top":
				point = Vector2(center.x, rect.position.y)
			"right":
				point = Vector2(rect.end.x, center.y)
			"bottom":
				point = Vector2(center.x, rect.end.y)
			"left":
				point = Vector2(rect.position.x, center.y)
		draw_circle(point, 5.0, outline)

func _cell_key(cell: Vector2i) -> String:
	return "%d,%d" % [cell.x, cell.y]
