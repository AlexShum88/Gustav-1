class_name RegimentView
extends Node2D

var regiment_data: Dictionary = {}
var is_selected: bool = false
var _polygon: PackedVector2Array = PackedVector2Array()
var _target_position: Vector2 = Vector2.ZERO
var _target_polygon: PackedVector2Array = PackedVector2Array()
var _snapshot_interval: float = 1.0 / 12.0
var _label: Label


func _ready() -> void:
	z_index = 5
	_label = Label.new()
	_label.position = Vector2(-52.0, -46.0)
	_label.size = Vector2(120.0, 20.0)
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_label)


func _process(delta: float) -> void:
	var max_position_step: float = position.distance_to(_target_position) / max(_snapshot_interval, 0.001) * delta
	position = position.move_toward(_target_position, max_position_step)
	if _polygon.size() == _target_polygon.size() and not _polygon.is_empty():
		for index in range(_polygon.size()):
			var max_vertex_step: float = _polygon[index].distance_to(_target_polygon[index]) / max(_snapshot_interval, 0.001) * delta
			_polygon[index] = _polygon[index].move_toward(_target_polygon[index], max_vertex_step)
		queue_redraw()


func set_snapshot_interval(value: float) -> void:
	_snapshot_interval = max(0.001, value)


func update_from_snapshot(new_regiment_data: Dictionary, selected: bool) -> void:
	regiment_data = new_regiment_data
	is_selected = selected
	_target_position = regiment_data.get("position", Vector2.ZERO)
	_target_polygon = PackedVector2Array()
	for world_point in regiment_data.get("polygon", PackedVector2Array()):
		_target_polygon.append(world_point - _target_position)
	if _polygon.size() != _target_polygon.size() or _polygon.is_empty():
		position = _target_position
		_polygon = PackedVector2Array(_target_polygon)
	_label.text = regiment_data.get("display_name", "")
	_label.modulate = Color(1.0, 1.0, 1.0) if regiment_data.get("is_friendly", false) else Color(1.0, 0.88, 0.88)
	queue_redraw()


func contains_world_point(world_point: Vector2) -> bool:
	return Geometry2D.is_point_in_polygon(to_local(world_point), _polygon)


func _draw() -> void:
	if _polygon.is_empty():
		return
	var friendly: bool = bool(regiment_data.get("is_friendly", false))
	var frame_fill: Color = Color(0.24, 0.46, 0.82, 0.0) if friendly else Color(0.78, 0.26, 0.22, 0.0)
	var outline: Color = Color.WHITE if is_selected else Color(0.12, 0.12, 0.12, 0.28)
	var halo_color: Color = Color(0.72, 0.88, 1.0, 0.18) if friendly else Color(1.0, 0.78, 0.72, 0.18)
	if is_selected:
		halo_color = Color(1.0, 0.96, 0.76, 0.28)
	_draw_halo(halo_color)
	draw_colored_polygon(_polygon, frame_fill)
	draw_polyline(_closed_polygon(), outline, 1.1)
	_draw_frame_corners(outline)

	var symbol_pos := Vector2(0.0, 4.0)
	match int(regiment_data.get("category", SimTypes.UnitCategory.INFANTRY)):
		SimTypes.UnitCategory.CAVALRY:
			draw_circle(symbol_pos, 8.0, Color(0.97, 0.95, 0.88))
			draw_line(symbol_pos + Vector2(-10.0, 0.0), symbol_pos + Vector2(10.0, 0.0), Color.BLACK, 2.0)
		SimTypes.UnitCategory.ARTILLERY:
			draw_circle(symbol_pos + Vector2(-8.0, 0.0), 4.0, Color.BLACK)
			draw_circle(symbol_pos + Vector2(8.0, 0.0), 4.0, Color.BLACK)
			draw_line(symbol_pos + Vector2(-10.0, -6.0), symbol_pos + Vector2(10.0, -6.0), Color.BLACK, 2.0)
		_:
			draw_line(symbol_pos + Vector2(-10.0, 0.0), symbol_pos + Vector2(10.0, 0.0), Color.BLACK, 2.0)
			draw_line(symbol_pos + Vector2(0.0, -8.0), symbol_pos + Vector2(0.0, 8.0), Color.BLACK, 2.0)

	var ratio: float = clamp(float(regiment_data.get("strength_ratio", 1.0)), 0.0, 1.0)
	var bar_origin := Vector2(-26.0, 18.0)
	draw_rect(Rect2(bar_origin, Vector2(52.0, 5.0)), Color(0.12, 0.12, 0.12, 0.8))
	draw_rect(Rect2(bar_origin, Vector2(52.0 * ratio, 5.0)), Color(0.28, 0.82, 0.4, 0.92))


func _closed_polygon() -> PackedVector2Array:
	var closed := PackedVector2Array(_polygon)
	if not _polygon.is_empty():
		closed.append(_polygon[0])
	return closed


func _draw_frame_corners(color: Color) -> void:
	if _polygon.size() < 4:
		return
	var corner_length: float = 8.0
	for index in range(4):
		var current: Vector2 = _polygon[index]
		var previous: Vector2 = _polygon[(index + 3) % 4]
		var next: Vector2 = _polygon[(index + 1) % 4]
		var to_previous: Vector2 = (previous - current).normalized()
		var to_next: Vector2 = (next - current).normalized()
		draw_line(current, current + to_previous * corner_length, color, 1.6)
		draw_line(current, current + to_next * corner_length, color, 1.6)


func _draw_halo(color: Color) -> void:
	if _polygon.size() < 4:
		return
	var center: Vector2 = Vector2.ZERO
	for point in _polygon:
		center += point
	center /= float(_polygon.size())
	var outer: PackedVector2Array = PackedVector2Array()
	var inner: PackedVector2Array = PackedVector2Array()
	for point in _polygon:
		var direction: Vector2 = (point - center).normalized()
		if direction.length() <= 0.001:
			direction = Vector2.RIGHT
		outer.append(point + direction * 7.0)
		inner.append(point + direction * 2.0)
	for index in range(outer.size()):
		var next_index: int = (index + 1) % outer.size()
		var ring: PackedVector2Array = PackedVector2Array([
			outer[index],
			outer[next_index],
			inner[next_index],
			inner[index],
		])
		draw_colored_polygon(ring, color)
