extends Node2D
class_name AntAgent

var path: Array[Vector2] = []
var speed: float = 90.0
var progress: float = 0.0

func setup(points: Array[Vector2], p_speed: float = 90.0) -> void:
	path = points.duplicate()
	speed = p_speed
	progress = 0.0
	queue_redraw()

func _process(delta: float) -> void:
	if path.size() < 2:
		return
	progress = fmod(progress + delta * speed, _path_length())
	position = _sample_path(progress)

func _draw() -> void:
	draw_circle(Vector2.ZERO, 4.0, Color(0.04, 0.025, 0.018, 1.0))
	draw_circle(Vector2(3, 0), 2.5, Color(0.04, 0.025, 0.018, 1.0))

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
