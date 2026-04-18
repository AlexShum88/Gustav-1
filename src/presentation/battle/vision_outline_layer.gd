class_name VisionOutlineLayer
extends Node2D

var _outline_entries: Array = []
var _world_view_rect: Rect2 = Rect2(-100000.0, -100000.0, 200000.0, 200000.0)
var _last_draw_ms: float = 0.0


func update_outlines(entries: Array) -> void:
	_outline_entries = entries.duplicate(true)
	queue_redraw()


func set_world_view_rect(value: Rect2) -> void:
	if _world_view_rect == value:
		return
	_world_view_rect = value
	queue_redraw()


func _draw() -> void:
	var draw_start_us: int = Time.get_ticks_usec()
	for entry_value in _outline_entries:
		var entry: Dictionary = entry_value
		var outline: PackedVector2Array = entry.get("points", PackedVector2Array())
		if outline.size() < 3 or not _is_outline_visible(outline):
			continue
		var closed_outline: PackedVector2Array = PackedVector2Array(outline)
		closed_outline.append(outline[0])
		var is_selected: bool = bool(entry.get("is_selected", false))
		draw_polyline(
			closed_outline,
			Color(1.0, 1.0, 1.0, 0.95 if is_selected else 0.55),
			2.2 if is_selected else 1.3
		)
	_last_draw_ms = float(Time.get_ticks_usec() - draw_start_us) / 1000.0


func get_performance_stats() -> Dictionary:
	return {
		"draw_ms": _last_draw_ms,
		"outlines": _outline_entries.size(),
	}


func _is_outline_visible(outline: PackedVector2Array) -> bool:
	if _world_view_rect.size.x <= 0.0 or _world_view_rect.size.y <= 0.0:
		return true
	var bounds: Rect2 = Rect2(outline[0], Vector2.ZERO)
	for index in range(1, outline.size()):
		bounds = bounds.expand(outline[index])
	return _world_view_rect.intersects(bounds.grow(24.0))
