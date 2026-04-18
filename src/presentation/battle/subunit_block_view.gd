class_name SubunitBlockView
extends Node2D

var local_polygon: PackedVector2Array = PackedVector2Array()
var _target_local_polygon: PackedVector2Array = PackedVector2Array()
var fill_color: Color = Color.WHITE
var outline_color: Color = Color.BLACK
var _target_position: Vector2 = Vector2.ZERO
var _snapshot_interval: float = 1.0 / 12.0


func _process(delta: float) -> void:
	var max_position_step: float = position.distance_to(_target_position) / max(_snapshot_interval, 0.001) * delta
	position = position.move_toward(_target_position, max_position_step)
	if local_polygon.size() == _target_local_polygon.size() and not local_polygon.is_empty():
		for index in range(local_polygon.size()):
			var max_vertex_step: float = local_polygon[index].distance_to(_target_local_polygon[index]) / max(_snapshot_interval, 0.001) * delta
			local_polygon[index] = local_polygon[index].move_toward(_target_local_polygon[index], max_vertex_step)
		queue_redraw()


func set_snapshot_interval(value: float) -> void:
	_snapshot_interval = max(0.001, value)


func update_polygon(world_polygon: PackedVector2Array, regiment_position: Vector2, new_fill_color: Color, new_outline_color: Color) -> void:
	var center: Vector2 = _compute_polygon_center(world_polygon)
	_target_position = center - regiment_position
	_target_local_polygon = PackedVector2Array()
	for world_point in world_polygon:
		_target_local_polygon.append(world_point - center)
	if local_polygon.size() != _target_local_polygon.size() or local_polygon.is_empty():
		position = _target_position
		local_polygon = PackedVector2Array(_target_local_polygon)
	fill_color = new_fill_color
	outline_color = new_outline_color
	queue_redraw()


func contains_world_point(world_point: Vector2) -> bool:
	return Geometry2D.is_point_in_polygon(to_local(world_point), local_polygon)


func _draw() -> void:
	if local_polygon.is_empty():
		return
	draw_polyline(PackedVector2Array([
		local_polygon[0],
		local_polygon[1],
		local_polygon[2],
		local_polygon[3],
		local_polygon[0],
	]), Color(0.0, 0.0, 0.0, 0.18), 4.2)
	draw_colored_polygon(local_polygon, fill_color)
	var closed_polygon: PackedVector2Array = PackedVector2Array(local_polygon)
	if not local_polygon.is_empty():
		closed_polygon.append(local_polygon[0])
	draw_polyline(closed_polygon, outline_color, 2.2)


func _compute_polygon_center(world_polygon: PackedVector2Array) -> Vector2:
	if world_polygon.is_empty():
		return Vector2.ZERO
	var total: Vector2 = Vector2.ZERO
	for world_point in world_polygon:
		total += world_point
	return total / float(world_polygon.size())
