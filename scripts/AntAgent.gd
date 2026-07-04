extends Node2D
class_name AntAgent

var path: Array[Vector2] = []
var speed: float = 90.0
var progress: float = 0.0
var pulse: float = 0.0

func setup(points: Array[Vector2], p_speed: float = 90.0) -> void:
	path = points.duplicate()
	speed = p_speed
	progress = 0.0
	queue_redraw()

func update_path(points: Array[Vector2], p_speed: float = 90.0) -> void:
	path = points.duplicate()
	speed = p_speed
	progress = fmod(progress, _path_length())

func _process(delta: float) -> void:
	if path.size() < 2:
		return
	pulse = fmod(pulse + delta * 5.0, TAU)
	progress = fmod(progress + delta * speed, _path_length())
	position = _sample_path(progress)
	queue_redraw()

func _draw() -> void:
	var glow := 0.55 + sin(pulse) * 0.18
	draw_circle(Vector2.ZERO, 8.0, Color(1.0, 0.83, 0.20, glow * 0.45))
	draw_circle(Vector2.ZERO, 5.0, Color(1.0, 0.90, 0.30, 1.0))
	draw_circle(Vector2(5, 0), 3.5, Color(0.18, 0.08, 0.02, 1.0))
	draw_line(Vector2(-5, -4), Vector2(5, 4), Color(0.07, 0.035, 0.015, 1.0), 2.0)
	draw_line(Vector2(-5, 4), Vector2(5, -4), Color(0.07, 0.035, 0.015, 1.0), 2.0)

func _path_length() -> float:
	var length = 0.0
	for i in range(path.size() - 1):
		length += path[i].distance_to(path[i + 1])
	return max(1.0, length)

func _sample_path(distance: float) -> Vector2:
	var remaining = distance
	for i in range(path.size() - 1):
		var from_point = path[i]
		var to_point = path[i + 1]
		var segment = from_point.distance_to(to_point)
		if remaining <= segment:
			return from_point.lerp(to_point, remaining / max(1.0, segment))
		remaining -= segment
	return path.back()
