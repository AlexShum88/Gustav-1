class_name SubunitBatchView
extends Node2D

const LAYER_MARGIN: float = 10.0

var _entries_by_key: Dictionary = {}
var _draw_order: Array = []
var _snapshot_interval: float = 1.0 / 12.0
var _is_animating: bool = false
var _last_draw_ms: float = 0.0
var _last_visible_entries: int = 0
var _world_view_rect: Rect2 = Rect2(-100000.0, -100000.0, 200000.0, 200000.0)


func _process(delta: float) -> void:
	if not _is_animating:
		return
	_is_animating = false
	for entry_key in _draw_order:
		var entry: Dictionary = _entries_by_key.get(entry_key, {})
		var polygon: PackedVector2Array = entry.get("polygon", PackedVector2Array())
		var target_polygon: PackedVector2Array = entry.get("target_polygon", PackedVector2Array())
		if polygon.size() != target_polygon.size() or polygon.is_empty():
			continue
		for index in range(polygon.size()):
			var max_vertex_step: float = polygon[index].distance_to(target_polygon[index]) / max(_snapshot_interval, 0.001) * delta
			polygon[index] = polygon[index].move_toward(target_polygon[index], max_vertex_step)
			if polygon[index].distance_to(target_polygon[index]) > 0.05:
				_is_animating = true
		entry["polygon"] = polygon
		_entries_by_key[entry_key] = entry
	if _is_animating:
		queue_redraw()
	else:
		queue_redraw()


func set_snapshot_interval(value: float) -> void:
	_snapshot_interval = max(0.001, value)


func set_selected_regiment(selected_regiment_id: StringName) -> void:
	var has_change: bool = false
	for entry_key in _draw_order:
		var entry: Dictionary = _entries_by_key.get(entry_key, {})
		if entry.is_empty():
			continue
		var next_outline: Color = Color.WHITE if entry.get("regiment_id", &"") == selected_regiment_id else Color(0.14, 0.14, 0.14, 0.92)
		if entry.get("outline", Color.BLACK) == next_outline:
			continue
		entry["outline"] = next_outline
		_entries_by_key[entry_key] = entry
		has_change = true
	if has_change:
		queue_redraw()


func set_world_view_rect(value: Rect2) -> void:
	if _world_view_rect == value:
		return
	_world_view_rect = value
	queue_redraw()


func clear() -> void:
	_entries_by_key.clear()
	_draw_order.clear()
	_is_animating = false
	queue_redraw()


func update_from_regiments(regiments: Array, selected_regiment_id: StringName) -> void:
	var active_keys: Dictionary = {}
	for regiment_data in regiments:
		var regiment_id: StringName = StringName(regiment_data.get("id", ""))
		var friendly: bool = bool(regiment_data.get("is_friendly", false))
		var selected: bool = regiment_id == selected_regiment_id
		var block_fill: Color = Color(0.24, 0.46, 0.82, 0.94) if friendly else Color(0.78, 0.26, 0.22, 0.94)
		var outline: Color = Color.WHITE if selected else Color(0.14, 0.14, 0.14, 0.92)
		var subunit_polygons: Array = _build_subunit_polygons(regiment_data)
		for index in range(subunit_polygons.size()):
			var entry_key: String = "%s:%d" % [String(regiment_id), index]
			active_keys[entry_key] = true
			var tint_strength: float = 0.12 if index % 2 == 0 else -0.08
			var subunit_fill: Color = block_fill.lightened(tint_strength) if tint_strength > 0.0 else block_fill.darkened(absf(tint_strength))
			var target_polygon: PackedVector2Array = PackedVector2Array(subunit_polygons[index])
			if not _entries_by_key.has(entry_key):
				_entries_by_key[entry_key] = {
					"regiment_id": regiment_id,
					"polygon": PackedVector2Array(target_polygon),
					"target_polygon": PackedVector2Array(target_polygon),
					"fill": subunit_fill,
					"outline": outline,
				}
				_draw_order.append(entry_key)
				continue
			var entry: Dictionary = _entries_by_key[entry_key]
			entry["regiment_id"] = regiment_id
			entry["target_polygon"] = target_polygon
			entry["fill"] = subunit_fill
			entry["outline"] = outline
			_entries_by_key[entry_key] = entry
			_is_animating = true
	var next_draw_order: Array = []
	for entry_key in _draw_order:
		if not active_keys.has(entry_key):
			_entries_by_key.erase(entry_key)
			continue
		next_draw_order.append(entry_key)
	_draw_order = next_draw_order
	queue_redraw()


func get_performance_stats() -> Dictionary:
	return {
		"draw_ms": _last_draw_ms,
		"visible_entries": _last_visible_entries,
	}


func pick_regiment_at(world_position: Vector2) -> StringName:
	for index in range(_draw_order.size() - 1, -1, -1):
		var entry: Dictionary = _entries_by_key.get(_draw_order[index], {})
		var polygon: PackedVector2Array = entry.get("polygon", PackedVector2Array())
		if polygon.is_empty() or not _is_polygon_visible(polygon):
			continue
		if Geometry2D.is_point_in_polygon(world_position, polygon):
			return entry.get("regiment_id", &"")
	return &""


func _draw() -> void:
	var draw_start_us: int = Time.get_ticks_usec()
	var visible_entries: int = 0
	for entry_key in _draw_order:
		var entry: Dictionary = _entries_by_key.get(entry_key, {})
		var polygon: PackedVector2Array = entry.get("polygon", PackedVector2Array())
		if polygon.is_empty() or not _is_polygon_visible(polygon):
			continue
		visible_entries += 1
		var closed_polygon: PackedVector2Array = PackedVector2Array(polygon)
		closed_polygon.append(polygon[0])
		draw_polyline(closed_polygon, Color(0.0, 0.0, 0.0, 0.18), 4.2)
		draw_colored_polygon(polygon, entry.get("fill", Color.WHITE))
		draw_polyline(closed_polygon, entry.get("outline", Color.BLACK), 2.2)
	_last_visible_entries = visible_entries
	_last_draw_ms = float(Time.get_ticks_usec() - draw_start_us) / 1000.0


func _build_subunit_polygons(regiment_data: Dictionary) -> Array:
	var snapshot_polygons: Array = regiment_data.get("subunit_polygons", [])
	if not snapshot_polygons.is_empty():
		return snapshot_polygons
	return _build_subunit_polygons_from_companies(regiment_data, regiment_data.get("stands", []))


func _build_subunit_polygons_from_companies(regiment_data: Dictionary, companies: Array) -> Array:
	var polygons: Array = []
	if companies.is_empty():
		return polygons
	var company_count: int = companies.size()
	var grid: Vector2i = _get_snapshot_subunit_grid(regiment_data, company_count)
	var columns: int = max(1, grid.x)
	var rows: int = max(1, grid.y)
	var frontage: float = max(24.0, float(regiment_data.get("formation_frontage", 116.0)))
	var depth: float = max(24.0, float(regiment_data.get("formation_depth", 70.0)))
	var usable_frontage: float = max(18.0, frontage - LAYER_MARGIN * float(columns + 1))
	var usable_depth: float = max(18.0, depth - LAYER_MARGIN * float(rows + 1))
	var cell_width: float = usable_frontage / float(columns)
	var cell_depth: float = usable_depth / float(rows)
	var category: int = int(regiment_data.get("category", SimTypes.UnitCategory.INFANTRY))
	var width_scale: float = 0.88
	var depth_scale: float = 0.88
	if category == SimTypes.UnitCategory.CAVALRY:
		width_scale = 0.94
		depth_scale = 0.82
	elif category == SimTypes.UnitCategory.ARTILLERY:
		width_scale = 0.72
		depth_scale = 0.94
	var block_width: float = max(14.0, cell_width * width_scale)
	var block_depth: float = max(14.0, cell_depth * depth_scale)
	var regiment_front: Vector2 = regiment_data.get("front_direction", Vector2.RIGHT)
	for company_value in companies:
		var company: Dictionary = company_value
		var company_position: Vector2 = company.get("position", regiment_data.get("position", Vector2.ZERO))
		var company_front: Vector2 = company.get("front_direction", regiment_front)
		polygons.append(_build_oriented_box(company_position, company_front, block_width, block_depth))
	return polygons


func _get_snapshot_subunit_grid(regiment_data: Dictionary, company_count: int) -> Vector2i:
	if company_count <= 1:
		return Vector2i.ONE
	var formation_type: int = int(regiment_data.get("formation_type", SimTypes.FormationType.LINE))
	var formation_state: int = int(regiment_data.get("formation_state", SimTypes.RegimentFormationState.DEFAULT))
	if formation_state == SimTypes.RegimentFormationState.MARCH_COLUMN or formation_type == SimTypes.FormationType.COLUMN:
		return Vector2i(1, company_count)
	if formation_state == SimTypes.RegimentFormationState.PROTECTED or formation_type == SimTypes.FormationType.SQUARE:
		var protected_columns: int = min(company_count, 2)
		return Vector2i(protected_columns, int(ceil(float(company_count) / float(protected_columns))))
	if formation_state == SimTypes.RegimentFormationState.TERCIA:
		var tercia_columns: int = min(company_count, 3 if company_count >= 6 else 2)
		return Vector2i(tercia_columns, int(ceil(float(company_count) / float(tercia_columns))))
	return Vector2i(company_count, 1)


func _build_oriented_box(center: Vector2, front_direction: Vector2, width: float, depth: float) -> PackedVector2Array:
	var front: Vector2 = front_direction.normalized() if front_direction.length_squared() > 0.001 else Vector2.RIGHT
	var right_axis: Vector2 = Vector2(-front.y, front.x).normalized()
	var half_width: float = width * 0.5
	var half_depth: float = depth * 0.5
	return PackedVector2Array([
		center - right_axis * half_width - front * half_depth,
		center + right_axis * half_width - front * half_depth,
		center + right_axis * half_width + front * half_depth,
		center - right_axis * half_width + front * half_depth,
	])


func _is_polygon_visible(polygon: PackedVector2Array) -> bool:
	if _world_view_rect.size.x <= 0.0 or _world_view_rect.size.y <= 0.0:
		return true
	var bounds: Rect2 = Rect2(polygon[0], Vector2.ZERO)
	for index in range(1, polygon.size()):
		bounds = bounds.expand(polygon[index])
	return _world_view_rect.intersects(bounds.grow(256.0))
