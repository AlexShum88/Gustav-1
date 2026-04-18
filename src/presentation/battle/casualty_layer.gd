class_name CasualtyLayer
extends Node2D

const CELL_SIZE: float = 160.0
const CELL_TEXTURE_SIZE: int = 160
const MAX_CELL_UPDATES_PER_FRAME: int = 3
const CORPSE_FILL_COLOR: Color = Color(0.2, 0.06, 0.05, 0.34)
const CORPSE_STROKE_COLOR: Color = Color(0.1, 0.06, 0.05, 0.38)

var _regiments_by_id: Dictionary = {}
var _corpse_cells: Dictionary = {}
var _dirty_cell_queue: Array[Vector2i] = []
var _corpse_count: int = 0
var _world_view_rect: Rect2 = Rect2(-100000.0, -100000.0, 200000.0, 200000.0)
var _sim_time_seconds: float = 0.0
var _last_draw_ms: float = 0.0
var _last_update_ms: float = 0.0
var _last_visible_cells: int = 0
var _last_rebuilt_cells: int = 0


func _process(_delta: float) -> void:
	_last_update_ms = 0.0
	_last_rebuilt_cells = 0
	if _dirty_cell_queue.is_empty():
		return
	var update_start_us: int = Time.get_ticks_usec()
	var processed_cells: int = 0
	while processed_cells < MAX_CELL_UPDATES_PER_FRAME and not _dirty_cell_queue.is_empty():
		var cell_key: Vector2i = _dirty_cell_queue.pop_front()
		var cell_data: Dictionary = _corpse_cells.get(cell_key, {})
		if cell_data.is_empty():
			continue
		if not bool(cell_data.get("dirty", false)):
			continue
		cell_data = _flush_pending_markers_to_cell_texture(cell_key, cell_data)
		_corpse_cells[cell_key] = cell_data
		processed_cells += 1
	_last_rebuilt_cells = processed_cells
	_last_update_ms = float(Time.get_ticks_usec() - update_start_us) / 1000.0
	if processed_cells > 0:
		queue_redraw()


func set_world_view_rect(value: Rect2) -> void:
	if _world_view_rect == value:
		return
	_world_view_rect = value
	queue_redraw()


func set_sim_time_seconds(value: float) -> void:
	if value < _sim_time_seconds - 0.01:
		clear()
	_sim_time_seconds = value


func clear() -> void:
	_regiments_by_id.clear()
	_corpse_cells.clear()
	_dirty_cell_queue.clear()
	_corpse_count = 0
	queue_redraw()


func update_from_regiments(regiments: Array) -> void:
	var next_regiments_by_id: Dictionary = {}
	var visible_markers_added: bool = false
	for regiment_value in regiments:
		var regiment: Dictionary = regiment_value
		var regiment_id: StringName = StringName(regiment.get("id", ""))
		var companies: Array = _copy_companies(regiment.get("stands", []))
		var previous_companies: Array = _regiments_by_id.get(regiment_id, [])
		if not companies.is_empty() and not previous_companies.is_empty():
			visible_markers_added = _emit_corpse_markers(previous_companies, companies, regiment_id) or visible_markers_added
		next_regiments_by_id[regiment_id] = companies if not companies.is_empty() else previous_companies
	_regiments_by_id = next_regiments_by_id
	if visible_markers_added:
		queue_redraw()


func get_performance_stats() -> Dictionary:
	return {
		"draw_ms": _last_draw_ms,
		"update_ms": _last_update_ms,
		"corpses": _corpse_count,
		"visible_cells": _last_visible_cells,
		"rebuilt_cells": _last_rebuilt_cells,
	}


func _draw() -> void:
	var draw_start_us: int = Time.get_ticks_usec()
	_last_visible_cells = 0
	if _corpse_cells.is_empty():
		_last_draw_ms = 0.0
		return
	var min_cell: Vector2i = _get_min_visible_cell()
	var max_cell: Vector2i = _get_max_visible_cell()
	for cell_y in range(min_cell.y, max_cell.y + 1):
		for cell_x in range(min_cell.x, max_cell.x + 1):
			var cell_key: Vector2i = Vector2i(cell_x, cell_y)
			var cell_data: Dictionary = _corpse_cells.get(cell_key, {})
			if cell_data.is_empty():
				continue
			_last_visible_cells += 1
			var texture: Texture2D = cell_data.get("texture", null)
			if texture == null:
				continue
			draw_texture(texture, _get_cell_origin(cell_key))
	_last_draw_ms = float(Time.get_ticks_usec() - draw_start_us) / 1000.0


func _copy_companies(companies: Array) -> Array:
	var result: Array = []
	for company_value in companies:
		var company: Dictionary = company_value
		result.append({
			"id": company.get("id", ""),
			"soldiers": int(company.get("soldiers", 0)),
			"position": company.get("position", Vector2.ZERO),
			"front_direction": company.get("front_direction", Vector2.UP),
		})
	return result


func _emit_corpse_markers(previous_companies: Array, next_companies: Array, regiment_id: StringName) -> bool:
	if previous_companies.is_empty() or next_companies.is_empty():
		return false
	var next_by_id: Dictionary = {}
	for company_value in next_companies:
		var company: Dictionary = company_value
		next_by_id[StringName(company.get("id", ""))] = company
	var added_markers: bool = false
	for company_value in previous_companies:
		var previous_company: Dictionary = company_value
		var company_id: StringName = StringName(previous_company.get("id", ""))
		var next_company: Dictionary = next_by_id.get(company_id, {})
		if next_company.is_empty():
			continue
		var losses: int = max(0, int(previous_company.get("soldiers", 0)) - int(next_company.get("soldiers", 0)))
		if losses <= 0:
			continue
		added_markers = _add_corpse_markers_for_company(previous_company, losses, regiment_id) or added_markers
	return added_markers


func _add_corpse_markers_for_company(company: Dictionary, losses: int, regiment_id: StringName) -> bool:
	var center: Vector2 = company.get("position", Vector2.ZERO)
	var front: Vector2 = company.get("front_direction", Vector2.UP)
	if front.length_squared() <= 0.001:
		front = Vector2.UP
	front = front.normalized()
	var right_axis: Vector2 = Vector2(-front.y, front.x).normalized()
	var marker_count: int = clamp(int(ceil(float(losses) / 5.0)), 1, 3)
	var seed: int = _stable_marker_seed("%s|%s|%d|%.2f" % [String(regiment_id), String(company.get("id", "")), losses, _sim_time_seconds])
	var visible_added: bool = false
	for marker_index in range(marker_count):
		var angle: float = TAU * float(posmod(seed + marker_index * 37, 360)) / 360.0
		var radius: float = 4.0 + float(posmod(seed / 7 + marker_index * 19, 15))
		var spread: Vector2 = right_axis.rotated(angle) * radius * 0.38 + front.rotated(angle * 0.6) * radius * 0.22
		var position: Vector2 = center + spread
		var marker: Dictionary = {
			"position": position,
			"size": 2.2 + float(posmod(seed + marker_index * 11, 6)) * 0.18,
		}
		visible_added = _append_marker(marker) or visible_added
	return visible_added


func _append_marker(marker: Dictionary) -> bool:
	var position: Vector2 = marker.get("position", Vector2.ZERO)
	var cell_key: Vector2i = _get_cell_key(position)
	var cell_data: Dictionary = _corpse_cells.get(cell_key, {})
	if cell_data.is_empty():
		cell_data = {
			"image": null,
			"texture": null,
			"pending_markers": [],
			"dirty": true,
			"queued": false,
		}
	var pending_markers: Array = cell_data.get("pending_markers", [])
	pending_markers.append(marker)
	cell_data["pending_markers"] = pending_markers
	cell_data["dirty"] = true
	if not bool(cell_data.get("queued", false)):
		_dirty_cell_queue.append(cell_key)
		cell_data["queued"] = true
	_corpse_cells[cell_key] = cell_data
	_corpse_count += 1
	return _world_view_rect.intersects(Rect2(position - Vector2(12.0, 12.0), Vector2.ONE * 24.0))


func _flush_pending_markers_to_cell_texture(cell_key: Vector2i, cell_data: Dictionary) -> Dictionary:
	var image: Image = cell_data.get("image", null)
	if image == null:
		image = Image.create(CELL_TEXTURE_SIZE, CELL_TEXTURE_SIZE, false, Image.FORMAT_RGBA8)
		image.fill(Color(0.0, 0.0, 0.0, 0.0))
	var cell_origin: Vector2 = _get_cell_origin(cell_key)
	for marker_value in cell_data.get("pending_markers", []):
		_paint_marker_into_image(image, cell_origin, marker_value)
	var texture: ImageTexture = cell_data.get("texture", null)
	if texture == null:
		texture = ImageTexture.create_from_image(image)
	else:
		texture.update(image)
	cell_data["image"] = image
	cell_data["texture"] = texture
	cell_data["pending_markers"] = []
	cell_data["dirty"] = false
	cell_data["queued"] = false
	return cell_data


func _paint_marker_into_image(image: Image, cell_origin: Vector2, marker: Dictionary) -> void:
	var scale: float = float(CELL_TEXTURE_SIZE) / CELL_SIZE
	var local_position: Vector2 = (marker.get("position", Vector2.ZERO) - cell_origin) * scale
	var size: float = float(marker.get("size", 2.8)) * scale
	_paint_disc(image, local_position, size, CORPSE_FILL_COLOR)
	_paint_line(
		image,
		local_position + Vector2(-size, -size * 0.45),
		local_position + Vector2(size, size * 0.45),
		CORPSE_STROKE_COLOR,
		max(0.8, size * 0.34)
	)


func _paint_disc(image: Image, center: Vector2, radius: float, color: Color) -> void:
	var min_x: int = max(0, int(floor(center.x - radius - 1.0)))
	var max_x: int = min(CELL_TEXTURE_SIZE - 1, int(ceil(center.x + radius + 1.0)))
	var min_y: int = max(0, int(floor(center.y - radius - 1.0)))
	var max_y: int = min(CELL_TEXTURE_SIZE - 1, int(ceil(center.y + radius + 1.0)))
	var radius_squared: float = radius * radius
	for y in range(min_y, max_y + 1):
		for x in range(min_x, max_x + 1):
			var dx: float = (float(x) + 0.5) - center.x
			var dy: float = (float(y) + 0.5) - center.y
			if dx * dx + dy * dy > radius_squared:
				continue
			_blend_pixel(image, x, y, color)


func _paint_line(image: Image, from_point: Vector2, to_point: Vector2, color: Color, thickness: float) -> void:
	var steps: int = max(1, int(ceil(from_point.distance_to(to_point) * 1.4)))
	for step in range(steps + 1):
		var t: float = float(step) / float(steps)
		_paint_disc(image, from_point.lerp(to_point, t), thickness * 0.5, color)


func _blend_pixel(image: Image, x: int, y: int, color: Color) -> void:
	var existing: Color = image.get_pixel(x, y)
	var inverse_alpha: float = 1.0 - color.a
	var out_alpha: float = color.a + existing.a * inverse_alpha
	if out_alpha <= 0.0001:
		return
	var out_color: Color = Color(
		(color.r * color.a + existing.r * existing.a * inverse_alpha) / out_alpha,
		(color.g * color.a + existing.g * existing.a * inverse_alpha) / out_alpha,
		(color.b * color.a + existing.b * existing.a * inverse_alpha) / out_alpha,
		out_alpha
	)
	image.set_pixel(x, y, out_color)


func _get_cell_key(position: Vector2) -> Vector2i:
	return Vector2i(
		int(floor(position.x / CELL_SIZE)),
		int(floor(position.y / CELL_SIZE))
	)


func _get_cell_origin(cell_key: Vector2i) -> Vector2:
	return Vector2(float(cell_key.x) * CELL_SIZE, float(cell_key.y) * CELL_SIZE)


func _get_min_visible_cell() -> Vector2i:
	return Vector2i(
		int(floor(_world_view_rect.position.x / CELL_SIZE)),
		int(floor(_world_view_rect.position.y / CELL_SIZE))
	)


func _get_max_visible_cell() -> Vector2i:
	var max_position: Vector2 = _world_view_rect.position + _world_view_rect.size
	return Vector2i(
		int(floor(max_position.x / CELL_SIZE)),
		int(floor(max_position.y / CELL_SIZE))
	)


func _stable_marker_seed(text: String) -> int:
	var seed: int = 17
	for char_index in range(text.length()):
		seed = posmod(seed * 31 + text.unicode_at(char_index), 104729)
	return seed
