class_name GroundLayer
extends Node2D

var map_rect: Rect2 = Rect2(0.0, 0.0, 1600.0, 900.0)
var ground_color: Color = Color(0.64, 0.61, 0.47, 1.0)


func update_map_rect(new_map_rect: Rect2) -> void:
	if map_rect == new_map_rect:
		return
	map_rect = new_map_rect
	queue_redraw()


func _draw() -> void:
	draw_rect(map_rect, ground_color)

