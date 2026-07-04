extends Node2D
class_name AntTrafficLayer

var routes: Array[Dictionary] = []

func set_routes(value: Array[Dictionary]) -> void:
	routes = value.duplicate(true)
	queue_redraw()

func _draw() -> void:
	for route in routes:
		var points: Array = route.get("points", [])
		if points.size() < 2:
			continue
		for i in range(points.size() - 1):
			draw_line(points[i], points[i + 1], Color(1.0, 0.84, 0.22, 0.48), 7.0, true)
			draw_line(points[i], points[i + 1], Color(1.0, 0.96, 0.55, 0.85), 2.5, true)
