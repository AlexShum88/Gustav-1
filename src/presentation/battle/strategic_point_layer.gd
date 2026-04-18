class_name StrategicPointLayer
extends Node2D

var _points: Array = []
var _world_view_rect: Rect2 = Rect2(-100000.0, -100000.0, 200000.0, 200000.0)


func update_points(points: Array) -> void:
	_points = points.duplicate(true)
	queue_redraw()


func set_world_view_rect(value: Rect2) -> void:
	_world_view_rect = value
	queue_redraw()


func _draw() -> void:
	for point in _points:
		var world_position: Vector2 = point.get("position", Vector2.ZERO)
		var radius: float = float(point.get("radius", 60.0))
		var owner_id: String = String(point.get("controlling_army_id", ""))
		var fill: Color = Color(0.8, 0.76, 0.26, 0.18)
		if owner_id == "blue":
			fill = Color(0.22, 0.48, 0.88, 0.18)
		elif owner_id == "red":
			fill = Color(0.82, 0.24, 0.2, 0.18)
		draw_circle(world_position, radius, fill)
		draw_arc(world_position, radius, 0.0, TAU, 40, Color(0.12, 0.12, 0.12, 0.85), 2.2)
