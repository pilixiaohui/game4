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
		var load_ratio := float(route.get("load_ratio", 0.0))
		var outer := Color(1.0, 0.84, 0.22, 0.48)
		var inner := Color(1.0, 0.96, 0.55, 0.85)
		if load_ratio >= 1.0:
			outer = Color(1.0, 0.18, 0.08, 0.62)
			inner = Color(1.0, 0.42, 0.22, 0.95)
		elif load_ratio >= 0.75:
			outer = Color(1.0, 0.46, 0.1, 0.55)
			inner = Color(1.0, 0.68, 0.24, 0.9)
		for i in range(points.size() - 1):
			draw_line(points[i], points[i + 1], outer, 7.0, true)
			draw_line(points[i], points[i + 1], inner, 2.5, true)
