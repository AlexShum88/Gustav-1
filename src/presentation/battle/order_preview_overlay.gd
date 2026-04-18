class_name OrderPreviewOverlay
extends Node2D

var pending_order_type: int = SimTypes.OrderType.NONE
var preview_anchor_position: Vector2 = Vector2.ZERO
var preview_target_position: Vector2 = Vector2.ZERO


func update_preview(new_pending_order_type: int, new_preview_anchor_position: Vector2, new_preview_target_position: Vector2) -> void:
	pending_order_type = new_pending_order_type
	preview_anchor_position = new_preview_anchor_position
	preview_target_position = new_preview_target_position
	queue_redraw()


func _draw() -> void:
	if pending_order_type == SimTypes.OrderType.NONE:
		return
	if preview_anchor_position == Vector2.ZERO:
		draw_circle(preview_target_position, 16.0, Color(1.0, 1.0, 1.0, 0.14))
		draw_arc(preview_target_position, 16.0, 0.0, TAU, 24, Color.WHITE, 2.0)
		return
	if pending_order_type in [SimTypes.OrderType.DEFEND, SimTypes.OrderType.HOLD]:
		draw_line(preview_anchor_position, preview_target_position, Color(0.96, 0.9, 0.42, 0.95), 4.0)
		draw_circle(preview_anchor_position, 8.0, Color(0.96, 0.9, 0.42, 0.35))
		draw_circle(preview_target_position, 8.0, Color(0.96, 0.9, 0.42, 0.35))
	else:
		_draw_arrow(preview_anchor_position, preview_target_position, Color(0.76, 0.92, 1.0, 0.95), 4.0)


func _draw_arrow(start_position: Vector2, end_position: Vector2, color: Color, width: float) -> void:
	var direction: Vector2 = end_position - start_position
	if direction.length() <= 0.001:
		draw_circle(end_position, 12.0, color.darkened(0.2))
		return
	var normalized: Vector2 = direction.normalized()
	var head_size: float = 16.0
	var left_head: Vector2 = end_position - normalized * head_size + Vector2(-normalized.y, normalized.x) * head_size * 0.55
	var right_head: Vector2 = end_position - normalized * head_size - Vector2(-normalized.y, normalized.x) * head_size * 0.55
	draw_line(start_position, end_position, color, width)
	draw_line(end_position, left_head, color, width)
	draw_line(end_position, right_head, color, width)
