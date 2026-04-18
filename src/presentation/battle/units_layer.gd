class_name UnitsLayer
extends Node2D

const MUSKETERS_TEXTURE: Texture2D = preload("res://assets/sprites/musketers.png")
const PIKE_TEXTURE: Texture2D = preload("res://assets/sprites/pike.png")
const DRAGOONS_TEXTURE: Texture2D = preload("res://assets/sprites/dragoons.png")
const KIRASIERS_TEXTURE: Texture2D = preload("res://assets/sprites/kirasiers.png")
const LIGHT_CAVALRY_TEXTURE: Texture2D = preload("res://assets/sprites/light_cavalry.png")
const FIELD_ARTILLERY_TEXTURE: Texture2D = preload("res://assets/sprites/field_artilery.png")
const LIGHT_ARTILLERY_TEXTURE: Texture2D = preload("res://assets/sprites/light_artilery.png")
const SIEGE_ARTILLERY_TEXTURE: Texture2D = preload("res://assets/sprites/siege_artilery.png")
const HQ_TEXTURE: Texture2D = preload("res://assets/sprites/hq.png")

var _regiments_by_id: Dictionary = {}
var _draw_order: Array = []
var _snapshot_interval: float = 1.0 / 16.0
var _is_animating: bool = false
var _view_zoom: float = 1.0
var _last_draw_ms: float = 0.0
var _last_visible_regiments: int = 0
var _selected_brigade_id: StringName = &""
var _sim_time_seconds: float = 0.0
var _world_view_rect: Rect2 = Rect2(-100000.0, -100000.0, 200000.0, 200000.0)


func _process(delta: float) -> void:
	if not _is_animating:
		return
	_is_animating = false
	for regiment_id in _draw_order:
		var entry: Dictionary = _regiments_by_id.get(regiment_id, {})
		if entry.is_empty():
			continue
		entry["position"] = entry.get("position", Vector2.ZERO).move_toward(
			entry.get("target_position", Vector2.ZERO),
			entry.get("position", Vector2.ZERO).distance_to(entry.get("target_position", Vector2.ZERO)) / max(_snapshot_interval, 0.001) * delta
		)
		entry["front_direction"] = _interpolate_direction(
			entry.get("front_direction", Vector2.RIGHT),
			entry.get("target_front_direction", Vector2.RIGHT),
			delta,
			8.0
		)
		_interpolate_polygon_array(entry, "polygon", "target_polygon", delta)
		_interpolate_nested_polygons(entry, delta)
		if _companies_use_interpolated_layout(entry.get("target_companies", [])):
			_interpolate_companies(entry, delta)
		if entry.get("position", Vector2.ZERO).distance_to(entry.get("target_position", Vector2.ZERO)) > 0.05 \
				or _direction_delta(
					entry.get("front_direction", Vector2.RIGHT),
					entry.get("target_front_direction", Vector2.RIGHT)
				) > 0.01 \
				or _has_pending_polygon_delta(entry) \
				or _has_pending_company_delta(entry):
			_is_animating = true
		_regiments_by_id[regiment_id] = entry
	queue_redraw()


func set_snapshot_interval(value: float) -> void:
	_snapshot_interval = max(0.001, value)


func set_view_zoom(value: float) -> void:
	var clamped_zoom: float = clamp(value, 0.4, 2.2)
	if absf(clamped_zoom - _view_zoom) <= 0.001:
		return
	_view_zoom = clamped_zoom
	queue_redraw()


func set_world_view_rect(value: Rect2) -> void:
	if _world_view_rect == value:
		return
	_world_view_rect = value
	queue_redraw()


func update_from_regiments(regiments: Array) -> void:
	var active_ids: Dictionary = {}
	var has_visual_change: bool = false
	for regiment_data in regiments:
		var regiment_id: StringName = StringName(regiment_data.get("id", ""))
		active_ids[regiment_id] = true
		var target_companies: Array = _copy_company_snapshots(regiment_data.get("stands", []), regiment_data)
		var target_subunit_polygons: Array = _duplicate_polygon_array(regiment_data.get("subunit_polygons", []))
		var target_entry: Dictionary = {
			"id": regiment_id,
			"display_name": String(regiment_data.get("display_name", "")),
			"brigade_id": StringName(regiment_data.get("brigade_id", "")),
			"position": regiment_data.get("position", Vector2.ZERO),
			"target_position": regiment_data.get("position", Vector2.ZERO),
			"front_direction": regiment_data.get("front_direction", Vector2.RIGHT),
			"target_front_direction": regiment_data.get("front_direction", Vector2.RIGHT),
			"polygon": _build_regiment_polygon_from_snapshot(regiment_data),
			"target_polygon": _build_regiment_polygon_from_snapshot(regiment_data),
			"subunit_polygons": _duplicate_polygon_array(target_subunit_polygons),
			"target_subunit_polygons": target_subunit_polygons,
			"subunit_types": regiment_data.get("subunit_types", []).duplicate(),
			"companies": _copy_company_snapshots(target_companies),
			"target_companies": target_companies,
			"regimental_elements": regiment_data.get("regimental_elements", []).duplicate(true),
			"category": int(regiment_data.get("category", SimTypes.UnitCategory.INFANTRY)),
			"formation_type": int(regiment_data.get("formation_type", SimTypes.FormationType.LINE)),
			"formation_state": int(regiment_data.get("formation_state", SimTypes.RegimentFormationState.DEFAULT)),
			"formation_frontage": float(regiment_data.get("formation_frontage", 116.0)),
			"formation_depth": float(regiment_data.get("formation_depth", 70.0)),
			"is_friendly": bool(regiment_data.get("is_friendly", false)),
			"fire_behavior": int(regiment_data.get("fire_behavior", SimTypes.RegimentFireBehavior.NONE)),
			"visual_test_fire": bool(regiment_data.get("visual_test_fire", false)),
			"is_selected": bool(_regiments_by_id.get(regiment_id, {}).get("is_selected", false)),
			"strength_ratio": float(regiment_data.get("strength_ratio", 1.0)),
		}
		if not _regiments_by_id.has(regiment_id):
			_regiments_by_id[regiment_id] = target_entry
			_draw_order.append(regiment_id)
			has_visual_change = true
			continue
		var existing: Dictionary = _regiments_by_id[regiment_id]
		var previous_target_position: Vector2 = existing.get("target_position", Vector2.ZERO)
		var previous_target_front_direction: Vector2 = existing.get("target_front_direction", Vector2.RIGHT)
		var previous_target_polygon: PackedVector2Array = existing.get("target_polygon", PackedVector2Array())
		var previous_target_subunit_polygons: Array = existing.get("target_subunit_polygons", [])
		var previous_target_companies: Array = existing.get("target_companies", [])
		var previous_visual_test_fire: bool = bool(existing.get("visual_test_fire", false))
		var previous_fire_behavior: int = int(existing.get("fire_behavior", SimTypes.RegimentFireBehavior.NONE))
		var previous_strength_ratio: float = float(existing.get("strength_ratio", 1.0))
		var previous_formation_type: int = int(existing.get("formation_type", SimTypes.FormationType.LINE))
		var previous_formation_state: int = int(existing.get("formation_state", SimTypes.RegimentFormationState.DEFAULT))
		var previous_formation_frontage: float = float(existing.get("formation_frontage", 116.0))
		var previous_formation_depth: float = float(existing.get("formation_depth", 70.0))
		existing["display_name"] = target_entry["display_name"]
		existing["brigade_id"] = target_entry["brigade_id"]
		existing["target_position"] = target_entry["target_position"]
		existing["target_front_direction"] = target_entry["target_front_direction"]
		existing["target_polygon"] = target_entry["target_polygon"]
		existing["target_subunit_polygons"] = target_entry["target_subunit_polygons"]
		if existing.get("polygon", PackedVector2Array()).size() != target_entry["target_polygon"].size():
			existing["polygon"] = PackedVector2Array(target_entry["target_polygon"])
		if existing.get("subunit_polygons", []).size() != target_entry["target_subunit_polygons"].size():
			existing["subunit_polygons"] = _duplicate_polygon_array(target_entry["target_subunit_polygons"])
		existing["subunit_types"] = target_entry["subunit_types"]
		existing["target_companies"] = target_entry["target_companies"]
		if existing.get("companies", []).size() != target_entry["target_companies"].size():
			existing["companies"] = _copy_company_snapshots(target_entry["target_companies"])
		existing["category"] = target_entry["category"]
		existing["formation_type"] = target_entry["formation_type"]
		existing["formation_state"] = target_entry["formation_state"]
		existing["formation_frontage"] = target_entry["formation_frontage"]
		existing["formation_depth"] = target_entry["formation_depth"]
		existing["is_friendly"] = target_entry["is_friendly"]
		existing["fire_behavior"] = target_entry["fire_behavior"]
		existing["visual_test_fire"] = target_entry["visual_test_fire"]
		existing["strength_ratio"] = target_entry["strength_ratio"]
		existing["regimental_elements"] = target_entry["regimental_elements"]
		_regiments_by_id[regiment_id] = existing
		if previous_target_position.distance_to(target_entry["target_position"]) > 0.01:
			has_visual_change = true
		elif _direction_delta(previous_target_front_direction, target_entry["target_front_direction"]) > 0.01:
			has_visual_change = true
		elif not _polygon_arrays_match(previous_target_polygon, target_entry["target_polygon"]):
			has_visual_change = true
		elif not _nested_polygons_match(previous_target_subunit_polygons, target_entry["target_subunit_polygons"]):
			has_visual_change = true
		elif previous_visual_test_fire != target_entry["visual_test_fire"]:
			has_visual_change = true
		elif previous_fire_behavior != target_entry["fire_behavior"]:
			has_visual_change = true
		elif absf(previous_strength_ratio - target_entry["strength_ratio"]) > 0.001:
			has_visual_change = true
		elif previous_formation_type != target_entry["formation_type"] \
				or previous_formation_state != target_entry["formation_state"] \
				or absf(previous_formation_frontage - target_entry["formation_frontage"]) > 0.01 \
				or absf(previous_formation_depth - target_entry["formation_depth"]) > 0.01:
			has_visual_change = true
		elif not _companies_match(previous_target_companies, target_entry["target_companies"]):
			has_visual_change = true
	var next_draw_order: Array = []
	for regiment_id in _draw_order:
		if not active_ids.has(regiment_id):
			_regiments_by_id.erase(regiment_id)
			has_visual_change = true
			continue
		next_draw_order.append(regiment_id)
	_draw_order = next_draw_order
	_is_animating = has_visual_change
	if has_visual_change:
		queue_redraw()


func set_sim_time_seconds(value: float) -> void:
	_sim_time_seconds = value
	queue_redraw()


func set_selected_regiment(selected_regiment_id: StringName) -> void:
	var has_selection_change: bool = false
	for regiment_id in _draw_order:
		var entry: Dictionary = _regiments_by_id.get(regiment_id, {})
		var next_selected: bool = regiment_id == selected_regiment_id
		if bool(entry.get("is_selected", false)) == next_selected:
			continue
		entry["is_selected"] = next_selected
		_regiments_by_id[regiment_id] = entry
		has_selection_change = true
	if has_selection_change:
		queue_redraw()


func set_selected_brigade(selected_brigade_id: StringName) -> void:
	if _selected_brigade_id == selected_brigade_id:
		return
	_selected_brigade_id = selected_brigade_id
	queue_redraw()


func get_regiment_snapshot(regiment_id: StringName) -> Dictionary:
	var entry: Dictionary = _regiments_by_id.get(regiment_id, {})
	return entry


func pick_regiment_at(world_position: Vector2) -> StringName:
	for index in range(_draw_order.size() - 1, -1, -1):
		var regiment_id: StringName = _draw_order[index]
		var entry: Dictionary = _regiments_by_id.get(regiment_id, {})
		if not _is_entry_visible(entry):
			continue
		for polygon in _build_subunit_polygons_from_entry(entry):
			if Geometry2D.is_point_in_polygon(world_position, polygon):
				return regiment_id
		if Geometry2D.is_point_in_polygon(world_position, _build_regiment_polygon_from_entry(entry)):
			return regiment_id
	return &""


func _draw() -> void:
	var draw_start_us: int = Time.get_ticks_usec()
	var font: Font = ThemeDB.fallback_font
	var font_size: int = 14
	var visible_regiments: int = 0
	for regiment_id in _draw_order:
		var entry: Dictionary = _regiments_by_id.get(regiment_id, {})
		if not _is_entry_visible(entry):
			continue
		visible_regiments += 1
		_draw_subunits(entry)
		_draw_regimental_elements(entry)
		_draw_regiment_frame(entry)
		_draw_regiment_symbol(entry)
		_draw_front_marker(entry)
		if _should_draw_strength_bar(entry):
			_draw_strength_bar(entry)
		if bool(entry.get("is_selected", false)) and font != null:
			_draw_company_strength_overlay(entry, font, font_size)
		if font != null and _should_draw_label(entry):
			_draw_regiment_label(entry, font, font_size)
	_last_visible_regiments = visible_regiments
	_last_draw_ms = float(Time.get_ticks_usec() - draw_start_us) / 1000.0


func get_performance_stats() -> Dictionary:
	return {
		"draw_ms": _last_draw_ms,
		"visible_regiments": _last_visible_regiments,
	}


func _is_entry_visible(entry: Dictionary) -> bool:
	if _world_view_rect.size.x <= 0.0 or _world_view_rect.size.y <= 0.0:
		return true
	var polygons: Array = entry.get("subunit_polygons", [])
	if not polygons.is_empty():
		var has_bounds: bool = false
		var bounds: Rect2 = Rect2()
		for polygon_value in polygons:
			var polygon: PackedVector2Array = polygon_value
			if polygon.is_empty():
				continue
			if not has_bounds:
				bounds = Rect2(polygon[0], Vector2.ZERO)
				has_bounds = true
			for point_index in range(1, polygon.size()):
				bounds = bounds.expand(polygon[point_index])
		if has_bounds:
			return _world_view_rect.intersects(bounds.grow(256.0))
	var center: Vector2 = entry.get("position", Vector2.ZERO)
	var half_extent: float = max(
		180.0,
		max(
			float(entry.get("formation_frontage", 116.0)),
			float(entry.get("formation_depth", 70.0))
		) * 1.05 + 192.0
	)
	var entry_rect: Rect2 = Rect2(center - Vector2.ONE * half_extent, Vector2.ONE * half_extent * 2.0)
	return _world_view_rect.intersects(entry_rect)


func _draw_subunits(entry: Dictionary) -> void:
	var polygons: Array = _build_subunit_polygons_from_entry(entry)
	var subunit_types: Array = entry.get("subunit_types", [])
	var companies: Array = entry.get("companies", [])
	for index in range(polygons.size()):
		var polygon: PackedVector2Array = polygons[index]
		if polygon.is_empty():
			continue
		var company_data: Dictionary = companies[index] if index < companies.size() else {}
		_draw_subunit_sprite(polygon, String(subunit_types[index] if index < subunit_types.size() else "musket"), entry, company_data)


func _draw_regimental_elements(entry: Dictionary) -> void:
	for element_value in entry.get("regimental_elements", []):
		var element: Dictionary = element_value
		var element_position: Vector2 = element.get("position", Vector2.ZERO)
		var texture: Texture2D = HQ_TEXTURE
		var target_size: Vector2 = Vector2(22.0, 22.0)
		draw_texture_rect(texture, Rect2(element_position - target_size * 0.5, target_size), false)


func _draw_regiment_frame(entry: Dictionary) -> void:
	var polygon: PackedVector2Array = _build_regiment_polygon_from_entry(entry)
	if polygon.is_empty():
		return
	var friendly: bool = bool(entry.get("is_friendly", false))
	var full_detail: bool = _is_full_detail_entry(entry)
	var in_selected_brigade: bool = _is_selected_brigade_entry(entry)
	var outline: Color = Color.WHITE if bool(entry.get("is_selected", false)) else Color(0.12, 0.12, 0.12, 0.28)
	var halo_color: Color = Color(0.72, 0.88, 1.0, 0.18) if friendly else Color(1.0, 0.78, 0.72, 0.18)
	if bool(entry.get("is_selected", false)):
		halo_color = Color(1.0, 0.96, 0.76, 0.28)
	elif in_selected_brigade:
		outline = Color(1.0, 1.0, 1.0, 0.85)
		halo_color = Color(1.0, 1.0, 1.0, 0.14)
	if full_detail:
		_draw_halo(polygon, halo_color)
	var closed_polygon: PackedVector2Array = PackedVector2Array(polygon)
	closed_polygon.append(polygon[0])
	draw_polyline(closed_polygon, outline, 1.8 if in_selected_brigade else (1.1 if full_detail else 0.8))
	if full_detail:
		_draw_frame_corners(polygon, outline)


func _draw_regiment_symbol(entry: Dictionary) -> void:
	var center: Vector2 = entry.get("position", Vector2.ZERO)
	var symbol_pos: Vector2 = center + Vector2(0.0, 4.0)
	match int(entry.get("category", SimTypes.UnitCategory.INFANTRY)):
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


func _draw_front_marker(entry: Dictionary) -> void:
	var front_direction: Vector2 = entry.get("front_direction", Vector2.ZERO)
	if front_direction.length_squared() <= 0.001:
		return
	front_direction = front_direction.normalized()
	var center: Vector2 = entry.get("position", Vector2.ZERO)
	var marker_origin: Vector2 = center + front_direction * 22.0
	var marker_tip: Vector2 = marker_origin + front_direction * 26.0
	var lateral: Vector2 = Vector2(-front_direction.y, front_direction.x)
	var color: Color = Color(1.0, 0.9, 0.3, 1.0) if bool(entry.get("is_selected", false)) else Color(1.0, 1.0, 1.0, 0.95)
	draw_line(marker_origin, marker_tip, Color(0.0, 0.0, 0.0, 0.8), 4.0)
	draw_line(marker_tip, marker_tip - front_direction * 9.0 + lateral * 6.0, Color(0.0, 0.0, 0.0, 0.8), 4.0)
	draw_line(marker_tip, marker_tip - front_direction * 9.0 - lateral * 6.0, Color(0.0, 0.0, 0.0, 0.8), 4.0)
	draw_line(marker_origin, marker_tip, color, 2.2)
	draw_line(marker_tip, marker_tip - front_direction * 9.0 + lateral * 6.0, color, 2.2)
	draw_line(marker_tip, marker_tip - front_direction * 9.0 - lateral * 6.0, color, 2.2)


func _draw_strength_bar(entry: Dictionary) -> void:
	var center: Vector2 = entry.get("position", Vector2.ZERO)
	var ratio: float = clamp(float(entry.get("strength_ratio", 1.0)), 0.0, 1.0)
	var bar_origin: Vector2 = center + Vector2(-26.0, 18.0)
	draw_rect(Rect2(bar_origin, Vector2(52.0, 5.0)), Color(0.12, 0.12, 0.12, 0.8))
	draw_rect(Rect2(bar_origin, Vector2(52.0 * ratio, 5.0)), Color(0.28, 0.82, 0.4, 0.92))


func _draw_regiment_label(entry: Dictionary, font: Font, font_size: int) -> void:
	var center: Vector2 = entry.get("position", Vector2.ZERO)
	var label_position: Vector2 = center + Vector2(-52.0, -46.0)
	var font_color: Color = Color(1.0, 1.0, 1.0) if bool(entry.get("is_friendly", false)) else Color(1.0, 0.88, 0.88)
	draw_string(font, label_position, String(entry.get("display_name", "")), HORIZONTAL_ALIGNMENT_LEFT, 120.0, font_size, font_color)


func _draw_company_strength_overlay(entry: Dictionary, font: Font, font_size: int) -> void:
	for company_value in entry.get("companies", []):
		var company: Dictionary = company_value
		var world_position: Vector2 = _get_company_render_center(company)
		var soldiers: int = int(company.get("soldiers", 0))
		var label_text: String = "%d" % soldiers
		var label_color: Color = Color(1.0, 0.96, 0.8)
		var label_position: Vector2 = world_position + Vector2(-10.0, -12.0)
		var background_rect: Rect2 = Rect2(label_position + Vector2(-3.0, -10.0), Vector2(26.0, 14.0))
		draw_rect(background_rect, Color(0.05, 0.05, 0.05, 0.58), true)
		draw_rect(background_rect, Color(1.0, 1.0, 1.0, 0.35), false, 1.0)
		draw_string(font, label_position, label_text, HORIZONTAL_ALIGNMENT_LEFT, 24.0, font_size - 1, label_color)


func _should_draw_label(entry: Dictionary) -> bool:
	if _is_full_detail_entry(entry):
		return true
	if bool(entry.get("is_selected", false)):
		return true
	if _view_zoom >= 1.15:
		return false
	return bool(entry.get("is_friendly", false))


func _should_draw_strength_bar(entry: Dictionary) -> bool:
	if _is_full_detail_entry(entry):
		return true
	if bool(entry.get("is_selected", false)):
		return true
	return _view_zoom <= 0.95


func _draw_subunit_sprite(polygon: PackedVector2Array, weapon_type: String, entry: Dictionary, company_data: Dictionary = {}) -> void:
	var texture: Texture2D = _get_subunit_texture(weapon_type, entry)
	if texture == null:
		return
	var visual_elements: Array = company_data.get("visual_elements", [])
	if not visual_elements.is_empty():
		_draw_company_visual_elements(texture, visual_elements, entry, company_data)
		return
	var center: Vector2 = _polygon_center(polygon)
	var front_direction: Vector2 = company_data.get("front_direction", entry.get("front_direction", Vector2.UP))
	if front_direction.length_squared() <= 0.001:
		front_direction = Vector2.UP
	front_direction = front_direction.normalized()
	var angle: float = front_direction.angle() + PI * 0.5
	_draw_sprite_instance(texture, center, angle, Vector2(16.0, 11.0))


func _draw_company_visual_elements(texture: Texture2D, visual_elements: Array, entry: Dictionary, company_data: Dictionary) -> void:
	var company_type: int = int(company_data.get("company_type", SimTypes.CompanyType.MUSKETEERS))
	match company_type:
		SimTypes.CompanyType.PIKEMEN, SimTypes.CompanyType.MUSKETEERS:
			var target_size: Vector2 = Vector2(16.0, 11.0)
			for element_index in range(visual_elements.size()):
				var element_value = visual_elements[element_index]
				var element: Dictionary = element_value
				var front_direction: Vector2 = element.get("front_direction", company_data.get("front_direction", entry.get("front_direction", Vector2.UP)))
				if front_direction.length_squared() <= 0.001:
					front_direction = Vector2.UP
				var angle: float = front_direction.normalized().angle() + PI * 0.5
				var firing_active: bool = _is_musketeer_element_firing(entry, company_data, element)
				_draw_sprite_instance(texture, element.get("position", Vector2.ZERO), angle, target_size, firing_active)
		SimTypes.CompanyType.CAVALRY:
			var target_size: Vector2 = Vector2(18.0, 12.0)
			for element_index in range(visual_elements.size()):
				var element_value = visual_elements[element_index]
				var element: Dictionary = element_value
				var front_direction: Vector2 = element.get("front_direction", company_data.get("front_direction", entry.get("front_direction", Vector2.UP)))
				if front_direction.length_squared() <= 0.001:
					front_direction = Vector2.UP
				var angle: float = front_direction.normalized().angle() + PI * 0.5
				var firing_active: bool = _is_cavalry_element_firing(entry, company_data, element_index)
				_draw_sprite_instance(texture, element.get("position", Vector2.ZERO), angle, target_size, firing_active)
		SimTypes.CompanyType.ARTILLERY:
			for element_index in range(visual_elements.size()):
				var element_value = visual_elements[element_index]
				var element: Dictionary = element_value
				var front_direction: Vector2 = element.get("front_direction", company_data.get("front_direction", entry.get("front_direction", Vector2.UP)))
				if front_direction.length_squared() <= 0.001:
					front_direction = Vector2.UP
				var angle: float = front_direction.normalized().angle() + PI * 0.5
				var role: StringName = element.get("role", &"gun")
				if role == &"crew":
					_draw_sprite_instance(MUSKETERS_TEXTURE, element.get("position", Vector2.ZERO), angle, Vector2(14.0, 10.0))
				else:
					var firing_active: bool = _is_artillery_element_firing(entry, company_data, element_index)
					_draw_sprite_instance(texture, element.get("position", Vector2.ZERO), angle, Vector2(20.0, 13.0), firing_active)
		_:
			var target_size: Vector2 = Vector2(16.0, 11.0)
			for element_value in visual_elements:
				var element: Dictionary = element_value
				var front_direction: Vector2 = element.get("front_direction", company_data.get("front_direction", entry.get("front_direction", Vector2.UP)))
				if front_direction.length_squared() <= 0.001:
					front_direction = Vector2.UP
				var angle: float = front_direction.normalized().angle() + PI * 0.5
				_draw_sprite_instance(texture, element.get("position", Vector2.ZERO), angle, target_size)


func _draw_sprite_instance(texture: Texture2D, sprite_center: Vector2, angle: float, target_size: Vector2, firing_active: bool = false) -> void:
	draw_set_transform(sprite_center, angle, Vector2.ONE)
	draw_texture_rect(texture, Rect2(-target_size * 0.5, target_size), false)
	if firing_active:
		var flash_center: Vector2 = Vector2(0.0, -target_size.y * 0.72)
		draw_circle(flash_center, 7.5, Color(1.0, 0.86, 0.42, 0.26))
		draw_circle(flash_center, 5.0, Color(1.0, 0.92, 0.62, 0.95))
		draw_circle(flash_center, 2.4, Color(1.0, 1.0, 1.0, 0.98))
		draw_circle(flash_center + Vector2(0.0, -4.5), 5.5, Color(0.86, 0.86, 0.82, 0.22))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _is_musketeer_element_firing(entry: Dictionary, company_data: Dictionary, element: Dictionary) -> bool:
	if int(company_data.get("company_type", SimTypes.CompanyType.MUSKETEERS)) != SimTypes.CompanyType.MUSKETEERS:
		return false
	var slot_role: String = String(company_data.get("slot_role", ""))
	var fire_behavior: int = int(company_data.get("fire_behavior", entry.get("fire_behavior", SimTypes.RegimentFireBehavior.NONE)))
	var countermarch_active: bool = fire_behavior == SimTypes.RegimentFireBehavior.COUNTERMARCH
	var supported_slot: bool = slot_role == "front_shot" \
		or slot_role == "left_shot" \
		or slot_role == "right_shot" \
		or slot_role == "inner_shot" \
		or slot_role == "corner_shot" \
		or slot_role == "countermarch_shot" \
		or slot_role == "countermarch_front" \
		or slot_role == "countermarch_support" \
		or slot_role == "countermarch_rear"
	if not supported_slot:
		return false
	if countermarch_active:
		var element_role: StringName = StringName(element.get("role", &""))
		if slot_role == "countermarch_front":
			if element_role != &"" and element_role != &"countermarch_front":
				return false
		elif slot_role != "countermarch_shot" or element_role != &"countermarch_front":
			return false
	elif slot_role == "countermarch_shot":
		return false
	var company_visual_fire: bool = bool(company_data.get("visual_fire_active", false))
	if company_visual_fire:
		return true
	var debug_visual_fire: bool = bool(entry.get("visual_test_fire", false))
	if not debug_visual_fire:
		return false
	var cycle_time: float = 1.35
	var fire_window: float = 0.42
	var phase_time: float = fmod(_sim_time_seconds + element.get("position", Vector2.ZERO).x * 0.002, cycle_time)
	return phase_time <= fire_window


func _is_artillery_element_firing(entry: Dictionary, company_data: Dictionary, element_index: int) -> bool:
	if int(company_data.get("company_type", SimTypes.CompanyType.ARTILLERY)) != SimTypes.CompanyType.ARTILLERY:
		return false
	if bool(company_data.get("visual_fire_active", false)):
		return true
	if not bool(entry.get("visual_test_fire", false)):
		return false
	var cycle_time: float = 1.6
	var fire_window: float = 0.5
	var phase_time: float = fmod(_sim_time_seconds + float(element_index) * 0.08, cycle_time)
	return phase_time <= fire_window


func _is_cavalry_element_firing(entry: Dictionary, company_data: Dictionary, element_index: int) -> bool:
	if int(company_data.get("company_type", SimTypes.CompanyType.CAVALRY)) != SimTypes.CompanyType.CAVALRY:
		return false
	var fire_behavior: int = int(company_data.get("fire_behavior", entry.get("fire_behavior", SimTypes.RegimentFireBehavior.NONE)))
	var slot_role: String = String(company_data.get("slot_role", ""))
	if fire_behavior != SimTypes.RegimentFireBehavior.CARACOLE or slot_role != "caracole_front":
		return false
	if bool(company_data.get("visual_fire_active", false)):
		return true
	if not bool(entry.get("visual_test_fire", false)):
		return false
	var cycle_time: float = 1.2
	var fire_window: float = 0.45
	var phase_time: float = fmod(_sim_time_seconds + float(element_index) * 0.05, cycle_time)
	return phase_time <= fire_window


func _get_subunit_texture(weapon_type: String, entry: Dictionary) -> Texture2D:
	var category: int = int(entry.get("category", SimTypes.UnitCategory.INFANTRY))
	var display_name: String = String(entry.get("display_name", "")).to_lower()
	match category:
		SimTypes.UnitCategory.CAVALRY:
			if display_name.contains("dragoon"):
				return DRAGOONS_TEXTURE
			if display_name.contains("cuirass") or display_name.contains("kirasier") or display_name.contains("guard horse"):
				return KIRASIERS_TEXTURE
			if display_name.contains("light"):
				return LIGHT_CAVALRY_TEXTURE
			if weapon_type == "pistol":
				return KIRASIERS_TEXTURE
			if weapon_type == "carbine":
				return DRAGOONS_TEXTURE
			return LIGHT_CAVALRY_TEXTURE
		SimTypes.UnitCategory.ARTILLERY:
			if display_name.contains("siege"):
				return SIEGE_ARTILLERY_TEXTURE
			if display_name.contains("light"):
				return LIGHT_ARTILLERY_TEXTURE
			return FIELD_ARTILLERY_TEXTURE
		_:
			if weapon_type == "pike":
				return PIKE_TEXTURE
			return MUSKETERS_TEXTURE


func _draw_frame_corners(polygon: PackedVector2Array, color: Color) -> void:
	if polygon.size() < 4:
		return
	var corner_length: float = 8.0
	for index in range(4):
		var current: Vector2 = polygon[index]
		var previous: Vector2 = polygon[(index + 3) % 4]
		var next: Vector2 = polygon[(index + 1) % 4]
		var to_previous: Vector2 = (previous - current).normalized()
		var to_next: Vector2 = (next - current).normalized()
		draw_line(current, current + to_previous * corner_length, color, 1.6)
		draw_line(current, current + to_next * corner_length, color, 1.6)


func _draw_halo(polygon: PackedVector2Array, color: Color) -> void:
	if polygon.size() < 4:
		return
	var center: Vector2 = _polygon_center(polygon)
	var outer: PackedVector2Array = PackedVector2Array()
	var inner: PackedVector2Array = PackedVector2Array()
	for point in polygon:
		var direction: Vector2 = (point - center).normalized()
		if direction.length() <= 0.001:
			direction = Vector2.RIGHT
		outer.append(point + direction * 7.0)
		inner.append(point + direction * 2.0)
	for index in range(outer.size()):
		var next_index: int = (index + 1) % outer.size()
		draw_colored_polygon(PackedVector2Array([outer[index], outer[next_index], inner[next_index], inner[index]]), color)


func _polygon_center(polygon: PackedVector2Array) -> Vector2:
	if polygon.is_empty():
		return Vector2.ZERO
	var total: Vector2 = Vector2.ZERO
	for point in polygon:
		total += point
	return total / float(polygon.size())


func _duplicate_polygon_array(polygons: Array) -> Array:
	var result: Array = []
	for polygon_value in polygons:
		result.append(PackedVector2Array(polygon_value))
	return result


func _copy_company_snapshots(companies: Array, regiment_data: Dictionary = {}) -> Array:
	var result: Array = []
	for company_value in companies:
		var company: Dictionary = company_value
		var visual_elements: Array = company.get("visual_elements", []).duplicate(true)
		result.append({
			"id": company.get("id", ""),
			"display_name": company.get("display_name", ""),
			"company_type": company.get("company_type", SimTypes.CompanyType.MUSKETEERS),
			"combat_role": company.get("combat_role", 0),
			"weapon_type": company.get("weapon_type", ""),
			"soldiers": company.get("soldiers", 0),
			"morale": company.get("morale", 0.0),
			"cohesion": company.get("cohesion", 0.0),
			"ammo": company.get("ammo", 0.0),
			"reload_state": company.get("reload_state", 0),
			"reload_progress": company.get("reload_progress", 0.0),
			"reload_ratio": company.get("reload_ratio", 0.0),
			"suppression": company.get("suppression", 0.0),
			"is_routed": company.get("is_routed", false),
			"can_fire_small_arms": company.get("can_fire_small_arms", false),
			"position": company.get("position", Vector2.ZERO),
			"front_direction": company.get("front_direction", Vector2.RIGHT),
			"slot_role": company.get("slot_role", ""),
			"fire_behavior": company.get("fire_behavior", SimTypes.RegimentFireBehavior.NONE),
			"visual_fire_active": company.get("visual_fire_active", false),
			"visual_elements": visual_elements,
		})
	if not regiment_data.is_empty():
		return _apply_regiment_visual_layout_to_companies(regiment_data, result)
	for company_index in range(result.size()):
		var copied_company: Dictionary = result[company_index]
		if copied_company.get("visual_elements", []).is_empty():
			copied_company["visual_elements"] = _build_company_visual_elements_from_snapshot(copied_company)
		result[company_index] = copied_company
	return result


func _build_regiment_polygon_from_entry(entry: Dictionary) -> PackedVector2Array:
	var cached_polygon: PackedVector2Array = entry.get("polygon", PackedVector2Array())
	if entry.get("companies", []).is_empty() and not cached_polygon.is_empty():
		return cached_polygon
	var points: Array = []
	for company_value in entry.get("companies", []):
		var company: Dictionary = company_value
		for element_value in company.get("visual_elements", []):
			var element: Dictionary = element_value
			points.append(element.get("position", Vector2.ZERO))
	for polygon_value in entry.get("subunit_polygons", []):
		var polygon: PackedVector2Array = polygon_value
		for point_value in polygon:
			points.append(point_value)
	if points.is_empty():
		if not cached_polygon.is_empty():
			return cached_polygon
		return _build_regiment_polygon_from_snapshot(entry)
	return _build_bounding_polygon_from_points(points, Vector2(22.0, 20.0))


func _build_subunit_polygons_from_entry(entry: Dictionary) -> Array:
	var cached_polygons: Array = entry.get("subunit_polygons", [])
	if not cached_polygons.is_empty():
		return cached_polygons
	var polygons: Array = []
	for company_value in entry.get("companies", []):
		var company: Dictionary = company_value
		var visual_elements: Array = company.get("visual_elements", [])
		if visual_elements.is_empty():
			visual_elements = _build_company_visual_elements_from_snapshot(company)
		polygons.append(_build_company_polygon_from_visual_elements(visual_elements))
	if polygons.is_empty():
		return _build_subunit_polygons_from_snapshot(entry, entry.get("companies", []))
	return polygons


func _build_regiment_polygon_from_snapshot(regiment_data: Dictionary) -> PackedVector2Array:
	var center: Vector2 = regiment_data.get("position", Vector2.ZERO)
	var front_direction: Vector2 = regiment_data.get("front_direction", Vector2.RIGHT)
	var frontage: float = max(24.0, float(regiment_data.get("formation_frontage", 116.0)))
	var depth: float = max(24.0, float(regiment_data.get("formation_depth", 70.0)))
	return _build_oriented_box(center, front_direction, frontage, depth)


func _build_subunit_polygons_from_snapshot(regiment_data: Dictionary, companies: Array) -> Array:
	var polygons: Array = []
	if companies.is_empty():
		return polygons
	var company_count: int = companies.size()
	var grid: Vector2i = _get_snapshot_subunit_grid(regiment_data, company_count)
	var columns: int = max(1, grid.x)
	var rows: int = max(1, grid.y)
	var frontage: float = max(24.0, float(regiment_data.get("formation_frontage", 116.0)))
	var depth: float = max(24.0, float(regiment_data.get("formation_depth", 70.0)))
	var gap: float = 10.0
	var usable_frontage: float = max(18.0, frontage - gap * float(columns + 1))
	var usable_depth: float = max(18.0, depth - gap * float(rows + 1))
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


func _interpolate_polygon_array(entry: Dictionary, source_key: String, target_key: String, delta: float) -> void:
	var source: PackedVector2Array = entry.get(source_key, PackedVector2Array())
	var target: PackedVector2Array = entry.get(target_key, PackedVector2Array())
	if source.size() != target.size():
		entry[source_key] = PackedVector2Array(target)
		return
	if source.is_empty():
		return
	for index in range(source.size()):
		var max_step: float = source[index].distance_to(target[index]) / max(_snapshot_interval, 0.001) * delta
		source[index] = source[index].move_toward(target[index], max_step)
	entry[source_key] = source


func _interpolate_nested_polygons(entry: Dictionary, delta: float) -> void:
	var polygons: Array = entry.get("subunit_polygons", [])
	var target_polygons: Array = entry.get("target_subunit_polygons", [])
	if polygons.size() != target_polygons.size():
		entry["subunit_polygons"] = _duplicate_polygon_array(target_polygons)
		return
	for polygon_index in range(polygons.size()):
		var polygon: PackedVector2Array = polygons[polygon_index]
		var target_polygon: PackedVector2Array = target_polygons[polygon_index]
		if polygon.size() != target_polygon.size():
			polygons[polygon_index] = PackedVector2Array(target_polygon)
			continue
		for vertex_index in range(polygon.size()):
			var max_step: float = polygon[vertex_index].distance_to(target_polygon[vertex_index]) / max(_snapshot_interval, 0.001) * delta
			polygon[vertex_index] = polygon[vertex_index].move_toward(target_polygon[vertex_index], max_step)
		polygons[polygon_index] = polygon
	entry["subunit_polygons"] = polygons


func _interpolate_companies(entry: Dictionary, delta: float) -> void:
	var companies: Array = entry.get("companies", [])
	var target_companies: Array = entry.get("target_companies", [])
	if companies.size() != target_companies.size():
		entry["companies"] = _copy_company_snapshots(target_companies)
		return
	for company_index in range(companies.size()):
		var company: Dictionary = companies[company_index]
		var target_company: Dictionary = target_companies[company_index]
		var current_position: Vector2 = company.get("position", Vector2.ZERO)
		var target_position: Vector2 = target_company.get("position", current_position)
		var max_step: float = current_position.distance_to(target_position) / max(_snapshot_interval, 0.001) * delta
		company["position"] = current_position.move_toward(target_position, max_step)
		company["front_direction"] = _interpolate_direction(
			company.get("front_direction", Vector2.UP),
			target_company.get("front_direction", Vector2.UP),
			delta,
			8.0
		)
		company["display_name"] = target_company.get("display_name", company.get("display_name", ""))
		company["company_type"] = target_company.get("company_type", company.get("company_type", SimTypes.CompanyType.MUSKETEERS))
		company["combat_role"] = target_company.get("combat_role", company.get("combat_role", 0))
		company["weapon_type"] = target_company.get("weapon_type", company.get("weapon_type", ""))
		company["soldiers"] = target_company.get("soldiers", company.get("soldiers", 0))
		company["morale"] = target_company.get("morale", company.get("morale", 0.0))
		company["cohesion"] = target_company.get("cohesion", company.get("cohesion", 0.0))
		company["ammo"] = target_company.get("ammo", company.get("ammo", 0.0))
		company["reload_state"] = target_company.get("reload_state", company.get("reload_state", 0))
		company["reload_progress"] = target_company.get("reload_progress", company.get("reload_progress", 0.0))
		company["reload_ratio"] = target_company.get("reload_ratio", company.get("reload_ratio", 0.0))
		company["suppression"] = target_company.get("suppression", company.get("suppression", 0.0))
		company["is_routed"] = target_company.get("is_routed", company.get("is_routed", false))
		company["can_fire_small_arms"] = target_company.get("can_fire_small_arms", company.get("can_fire_small_arms", false))
		company["slot_role"] = target_company.get("slot_role", company.get("slot_role", ""))
		company["fire_behavior"] = target_company.get("fire_behavior", company.get("fire_behavior", SimTypes.RegimentFireBehavior.NONE))
		company["visual_fire_active"] = target_company.get("visual_fire_active", false)
		var current_visual_elements: Array = company.get("visual_elements", [])
		var target_visual_elements: Array = target_company.get("visual_elements", [])
		if not current_visual_elements.is_empty() or not target_visual_elements.is_empty():
			company["visual_elements"] = _interpolate_visual_elements(
				current_visual_elements,
				target_visual_elements,
				delta
			)
		elif company.has("visual_elements"):
			company.erase("visual_elements")
		companies[company_index] = company
	entry["companies"] = companies


func _interpolate_visual_elements(elements: Array, target_elements: Array, delta: float) -> Array:
	if elements.size() != target_elements.size():
		return target_elements.duplicate(true)
	var result: Array = []
	for element_index in range(elements.size()):
		var element: Dictionary = elements[element_index]
		var target_element: Dictionary = target_elements[element_index]
		var current_position: Vector2 = element.get("position", Vector2.ZERO)
		var target_position: Vector2 = target_element.get("position", current_position)
		var max_step: float = current_position.distance_to(target_position) / max(_snapshot_interval, 0.001) * delta
		var next_element: Dictionary = target_element.duplicate(true)
		next_element["position"] = current_position.move_toward(target_position, max_step)
		next_element["front_direction"] = _interpolate_direction(
			element.get("front_direction", Vector2.UP),
			target_element.get("front_direction", Vector2.UP),
			delta,
			9.0
		)
		result.append(next_element)
	return result


func _interpolate_direction(current_direction: Vector2, target_direction: Vector2, delta: float, speed: float) -> Vector2:
	var current: Vector2 = current_direction.normalized() if current_direction.length_squared() > 0.001 else Vector2.UP
	var target: Vector2 = target_direction.normalized() if target_direction.length_squared() > 0.001 else current
	var blended: Vector2 = current.lerp(target, min(1.0, delta * speed))
	return blended.normalized() if blended.length_squared() > 0.001 else target


func _has_pending_polygon_delta(entry: Dictionary) -> bool:
	var polygon: PackedVector2Array = entry.get("polygon", PackedVector2Array())
	var target_polygon: PackedVector2Array = entry.get("target_polygon", PackedVector2Array())
	for index in range(min(polygon.size(), target_polygon.size())):
		if polygon[index].distance_to(target_polygon[index]) > 0.05:
			return true
	var polygons: Array = entry.get("subunit_polygons", [])
	var target_polygons: Array = entry.get("target_subunit_polygons", [])
	for polygon_index in range(min(polygons.size(), target_polygons.size())):
		var source_polygon: PackedVector2Array = polygons[polygon_index]
		var next_polygon: PackedVector2Array = target_polygons[polygon_index]
		for vertex_index in range(min(source_polygon.size(), next_polygon.size())):
			if source_polygon[vertex_index].distance_to(next_polygon[vertex_index]) > 0.05:
				return true
	return false


func _has_pending_company_delta(entry: Dictionary) -> bool:
	var companies: Array = entry.get("companies", [])
	var target_companies: Array = entry.get("target_companies", [])
	if not _companies_use_interpolated_layout(target_companies):
		return false
	if companies.size() != target_companies.size():
		return false
	for company_index in range(companies.size()):
		var company: Dictionary = companies[company_index]
		var target_company: Dictionary = target_companies[company_index]
		if company.get("position", Vector2.ZERO).distance_to(target_company.get("position", Vector2.ZERO)) > 0.05:
			return true
		if _direction_delta(
			company.get("front_direction", Vector2.RIGHT),
			target_company.get("front_direction", Vector2.RIGHT)
		) > 0.01:
			return true
		if not _visual_elements_match(company.get("visual_elements", []), target_company.get("visual_elements", [])):
			return true
	return false


func _polygon_arrays_match(left: PackedVector2Array, right: PackedVector2Array) -> bool:
	if left.size() != right.size():
		return false
	for index in range(left.size()):
		if left[index].distance_to(right[index]) > 0.01:
			return false
	return true


func _nested_polygons_match(left: Array, right: Array) -> bool:
	if left.size() != right.size():
		return false
	for polygon_index in range(left.size()):
		var left_polygon: PackedVector2Array = left[polygon_index]
		var right_polygon: PackedVector2Array = right[polygon_index]
		if not _polygon_arrays_match(left_polygon, right_polygon):
			return false
	return true


func _companies_match(left: Array, right: Array) -> bool:
	if left.size() != right.size():
		return false
	for index in range(left.size()):
		var left_company: Dictionary = left[index]
		var right_company: Dictionary = right[index]
		if String(left_company.get("id", "")) != String(right_company.get("id", "")):
			return false
		if int(left_company.get("soldiers", 0)) != int(right_company.get("soldiers", 0)):
			return false
		if String(left_company.get("slot_role", "")) != String(right_company.get("slot_role", "")):
			return false
		if bool(left_company.get("visual_fire_active", false)) != bool(right_company.get("visual_fire_active", false)):
			return false
		if left_company.get("position", Vector2.ZERO).distance_to(right_company.get("position", Vector2.ZERO)) > 0.01:
			return false
		if _direction_delta(
			left_company.get("front_direction", Vector2.RIGHT),
			right_company.get("front_direction", Vector2.RIGHT)
		) > 0.01:
			return false
		if not _visual_elements_match(left_company.get("visual_elements", []), right_company.get("visual_elements", [])):
			return false
	return true


func _visual_elements_match(left: Array, right: Array) -> bool:
	if left.size() != right.size():
		return false
	for index in range(left.size()):
		var left_element: Dictionary = left[index]
		var right_element: Dictionary = right[index]
		if left_element.get("position", Vector2.ZERO).distance_to(right_element.get("position", Vector2.ZERO)) > 0.01:
			return false
		if _direction_delta(
			left_element.get("front_direction", Vector2.RIGHT),
			right_element.get("front_direction", Vector2.RIGHT)
		) > 0.01:
			return false
		if StringName(left_element.get("role", &"")) != StringName(right_element.get("role", &"")):
			return false
	return true


func _build_company_visual_elements_from_snapshot(company: Dictionary) -> Array:
	var center: Vector2 = company.get("position", Vector2.ZERO)
	var front: Vector2 = company.get("front_direction", Vector2.UP)
	if front.length_squared() <= 0.001:
		front = Vector2.UP
	front = front.normalized()
	return [{
		"position": center,
		"front_direction": front,
		"role": StringName(company.get("slot_role", "")),
	}]


func _build_snapshot_world_elements_from_offsets(offsets: Array, center: Vector2, front: Vector2, right_axis: Vector2) -> Array:
	var result: Array = []
	for local_offset_value in offsets:
		var local_offset: Vector2 = local_offset_value
		result.append({
			"position": center + right_axis * local_offset.x + front * local_offset.y,
			"front_direction": front,
			"role": &"",
		})
	return result


func _get_snapshot_infantry_visual_offsets(company_type: int, slot_role: StringName) -> Array:
	match slot_role:
		&"advance_guard", &"rear_guard", &"column", &"column_core":
			return [
				Vector2(0.0, -13.5),
				Vector2(0.0, -4.5),
				Vector2(0.0, 4.5),
				Vector2(0.0, 13.5),
			]
		&"front_shot", &"rear_pike":
			return [
				Vector2(-16.5, 0.0),
				Vector2(-5.5, 0.0),
				Vector2(5.5, 0.0),
				Vector2(16.5, 0.0),
			]
		&"outer_pike":
			return [
				Vector2(0.0, -16.5),
				Vector2(0.0, -5.5),
				Vector2(0.0, 5.5),
				Vector2(0.0, 16.5),
			]
		&"inner_shot":
			return [
				Vector2(-11.0, -5.5),
				Vector2(11.0, -5.5),
				Vector2(-11.0, 5.5),
				Vector2(11.0, 5.5),
			]
		_:
			if company_type == SimTypes.CompanyType.PIKEMEN:
				return [
					Vector2(-6.5, -8.0),
					Vector2(6.5, -8.0),
					Vector2(-6.5, 8.0),
					Vector2(6.5, 8.0),
				]
			return [
				Vector2(-7.5, -7.5),
				Vector2(7.5, -7.5),
				Vector2(-7.5, 7.5),
				Vector2(7.5, 7.5),
			]


func _get_snapshot_cavalry_visual_offsets(slot_role: StringName) -> Array:
	if slot_role == &"cavalry_column" or slot_role == &"caracole_front":
		return [
			Vector2(-7.0, 0.0),
			Vector2(7.0, 0.0),
		]
	return [
		Vector2(0.0, -8.0),
		Vector2(0.0, 8.0),
	]


func _build_snapshot_artillery_company_elements(center: Vector2, front: Vector2, right_axis: Vector2) -> Array:
	return [
		{
			"position": center + right_axis * 4.0,
			"front_direction": front,
			"role": &"gun",
		},
		{
			"position": center - right_axis * 6.0,
			"front_direction": front,
			"role": &"crew",
		},
	]


func _build_countermarch_visual_elements_from_snapshot(center: Vector2, front: Vector2, right_axis: Vector2) -> Array:
	var swap_rows: bool = bool(int(floor(_sim_time_seconds * 0.95)) % 2)
	var fire_phase: bool = fmod(_sim_time_seconds, 1.15) <= 0.42
	var column_positions: Array = [-8.0, 8.0]
	var front_rank_y: float = 6.0
	var rear_rank_y: float = -6.0
	var result: Array = []
	var front_role: StringName = &"countermarch_front" if fire_phase else &"countermarch_support"
	var rear_role: StringName = &"countermarch_rear"
	if swap_rows:
		for column_x_value in column_positions:
			var column_x: float = float(column_x_value)
			result.append({
				"position": center + right_axis * column_x + front * rear_rank_y,
				"front_direction": front,
				"role": rear_role,
			})
		for column_x_value in column_positions:
			var column_x: float = float(column_x_value)
			result.append({
				"position": center + right_axis * column_x + front * front_rank_y,
				"front_direction": front,
				"role": front_role,
			})
		return result
	for column_x_value in column_positions:
		var column_x: float = float(column_x_value)
		result.append({
			"position": center + right_axis * column_x + front * front_rank_y,
			"front_direction": front,
			"role": front_role,
		})
	for column_x_value in column_positions:
		var column_x: float = float(column_x_value)
		result.append({
			"position": center + right_axis * column_x + front * rear_rank_y,
			"front_direction": front,
			"role": rear_role,
		})
	return result


func _build_company_polygon_from_visual_elements(elements: Array) -> PackedVector2Array:
	var points: Array = []
	for element_value in elements:
		var element: Dictionary = element_value
		points.append(element.get("position", Vector2.ZERO))
	return _build_bounding_polygon_from_points(points, Vector2(11.0, 9.0))


func _build_bounding_polygon_from_points(points: Array, padding: Vector2) -> PackedVector2Array:
	if points.is_empty():
		return PackedVector2Array()
	var min_x: float = INF
	var min_y: float = INF
	var max_x: float = -INF
	var max_y: float = -INF
	for point_value in points:
		var world_point: Vector2 = point_value
		min_x = min(min_x, world_point.x)
		min_y = min(min_y, world_point.y)
		max_x = max(max_x, world_point.x)
		max_y = max(max_y, world_point.y)
	return PackedVector2Array([
		Vector2(min_x, min_y) - padding,
		Vector2(max_x, min_y) + Vector2(padding.x, -padding.y),
		Vector2(max_x, max_y) + padding,
		Vector2(min_x, max_y) + Vector2(-padding.x, padding.y),
	])


func _companies_use_interpolated_layout(companies: Array) -> bool:
	return not companies.is_empty()


func _direction_delta(current_direction: Vector2, target_direction: Vector2) -> float:
	var current: Vector2 = current_direction.normalized() if current_direction.length_squared() > 0.001 else Vector2.RIGHT
	var target: Vector2 = target_direction.normalized() if target_direction.length_squared() > 0.001 else current
	return current.distance_to(target)


func _is_full_detail_entry(entry: Dictionary) -> bool:
	if bool(entry.get("is_selected", false)):
		return true
	return _is_selected_brigade_entry(entry)


func _is_selected_brigade_entry(entry: Dictionary) -> bool:
	var brigade_id: StringName = entry.get("brigade_id", &"")
	return _selected_brigade_id != &"" and brigade_id == _selected_brigade_id


func _polygon_bounds(polygon: PackedVector2Array) -> Rect2:
	var min_x: float = INF
	var min_y: float = INF
	var max_x: float = -INF
	var max_y: float = -INF
	for point in polygon:
		min_x = min(min_x, point.x)
		min_y = min(min_y, point.y)
		max_x = max(max_x, point.x)
		max_y = max(max_y, point.y)
	return Rect2(Vector2(min_x, min_y), Vector2(max_x - min_x, max_y - min_y)).grow(260.0)


func _get_company_render_center(company: Dictionary) -> Vector2:
	var visual_elements: Array = company.get("visual_elements", [])
	if not visual_elements.is_empty():
		return _get_visual_elements_center(visual_elements)
	return company.get("position", Vector2.ZERO)


func _apply_regiment_visual_layout_to_companies(regiment_data: Dictionary, companies: Array) -> Array:
	var all_have_visual_elements: bool = true
	for company_value in companies:
		var company_check: Dictionary = company_value
		if company_check.get("visual_elements", []).is_empty():
			all_have_visual_elements = false
			break
	if all_have_visual_elements:
		return companies
	var visual_entries: Array = _build_regiment_visual_company_entries(regiment_data, companies)
	if visual_entries.is_empty():
		for company_index in range(companies.size()):
			var fallback_company: Dictionary = companies[company_index]
			if fallback_company.get("visual_elements", []).is_empty():
				fallback_company["visual_elements"] = _build_company_visual_elements_from_snapshot(fallback_company)
			companies[company_index] = fallback_company
		return companies
	var entries_by_company: Dictionary = {}
	for visual_entry_value in visual_entries:
		var visual_entry: Dictionary = visual_entry_value
		entries_by_company[StringName(visual_entry.get("company_id", ""))] = visual_entry
	for company_index in range(companies.size()):
		var company: Dictionary = companies[company_index]
		var render_entry: Dictionary = entries_by_company.get(StringName(company.get("id", "")), {})
		if render_entry.is_empty():
			if company.get("visual_elements", []).is_empty():
				company["visual_elements"] = _build_company_visual_elements_from_snapshot(company)
			companies[company_index] = company
			continue
		var elements: Array = render_entry.get("elements", []).duplicate(true)
		company["slot_role"] = render_entry.get("slot_role", company.get("slot_role", ""))
		company["visual_elements"] = elements
		if not elements.is_empty():
			company["position"] = _get_visual_elements_center(elements)
			company["front_direction"] = _get_dominant_front_direction(elements)
		companies[company_index] = company
	return companies


func _build_regiment_visual_company_entries(regiment_data: Dictionary, companies: Array) -> Array:
	if companies.is_empty():
		return []
	var visual_entries: Array = regiment_data.get("stand_visual_entries", [])
	if visual_entries.is_empty():
		visual_entries = regiment_data.get("visual_company_entries", [])
	if visual_entries.is_empty():
		return []
	return _order_snapshot_visual_entries_by_company(companies, visual_entries)


func _build_snapshot_infantry_regiment_visual_layout(regiment_data: Dictionary, companies: Array) -> Array:
	if _has_pike_and_shot_companies(companies):
		return _build_snapshot_pike_and_shot_regiment_visual_layout(regiment_data, companies)
	return _build_snapshot_single_arm_infantry_visual_layout(regiment_data, companies)


func _build_snapshot_single_arm_infantry_visual_layout(regiment_data: Dictionary, companies: Array) -> Array:
	var musket_indices: Array = _get_company_indices_by_type(companies, SimTypes.CompanyType.MUSKETEERS)
	var pike_indices: Array = _get_company_indices_by_type(companies, SimTypes.CompanyType.PIKEMEN)
	var active_indices: Array = musket_indices if not musket_indices.is_empty() else pike_indices
	var primary_type: int = SimTypes.CompanyType.MUSKETEERS if not musket_indices.is_empty() else SimTypes.CompanyType.PIKEMEN
	var formation_state: int = int(regiment_data.get("formation_state", SimTypes.RegimentFormationState.DEFAULT))
	match formation_state:
		SimTypes.RegimentFormationState.MARCH_COLUMN:
			return _build_snapshot_single_arm_infantry_column_visual_elements(regiment_data, companies, active_indices, primary_type)
		SimTypes.RegimentFormationState.PROTECTED, SimTypes.RegimentFormationState.TERCIA:
			return _build_snapshot_single_arm_infantry_block_visual_elements(regiment_data, companies, active_indices, primary_type)
		SimTypes.RegimentFormationState.MUSKETEER_LINE:
			return _build_snapshot_single_arm_infantry_line_visual_elements(regiment_data, companies, active_indices, primary_type, true)
		_:
			return _build_snapshot_single_arm_infantry_line_visual_elements(regiment_data, companies, active_indices, primary_type, false)


func _build_snapshot_single_arm_infantry_line_visual_elements(regiment_data: Dictionary, companies: Array, company_indices: Array, company_type: int, expanded_front: bool) -> Array:
	var result: Array = []
	if company_indices.is_empty():
		return result
	var front: Vector2 = _get_regiment_front_direction(regiment_data)
	var right_axis: Vector2 = Vector2(-front.y, front.x).normalized()
	var center: Vector2 = regiment_data.get("position", Vector2.ZERO)
	var columns: int = min(max(1, company_indices.size()), 6)
	var rows: int = int(ceil(float(company_indices.size()) / float(columns)))
	var x_spacing: float = 42.0 if company_type == SimTypes.CompanyType.MUSKETEERS else 34.0
	var y_spacing: float = 28.0 if expanded_front else 24.0
	var company_centers: Array = _build_snapshot_rect_grid_offsets(columns, rows, x_spacing, y_spacing, Vector2.ZERO)
	var slot_role: String = "front_shot" if company_type == SimTypes.CompanyType.MUSKETEERS else "pike_core"
	var element_offsets: Array = _get_snapshot_infantry_visual_offsets(company_type, StringName(slot_role))
	for company_list_index in range(company_indices.size()):
		var company: Dictionary = companies[company_indices[company_list_index]]
		var company_center: Vector2 = center + right_axis * company_centers[company_list_index].x + front * company_centers[company_list_index].y
		result.append(_make_snapshot_company_visual_entry(
			company,
			slot_role,
			_build_snapshot_world_elements_from_offsets(element_offsets, company_center, front, right_axis)
		))
	return result


func _build_snapshot_single_arm_infantry_column_visual_elements(regiment_data: Dictionary, companies: Array, company_indices: Array, company_type: int) -> Array:
	var result: Array = []
	if company_indices.is_empty():
		return result
	var front: Vector2 = _get_regiment_front_direction(regiment_data)
	var right_axis: Vector2 = Vector2(-front.y, front.x).normalized()
	var center: Vector2 = regiment_data.get("position", Vector2.ZERO)
	var company_offsets: Array = _build_snapshot_front_to_rear_column_offsets(company_indices.size(), 38.0)
	var slot_role: StringName = &"column" if company_type == SimTypes.CompanyType.MUSKETEERS else &"column_core"
	var element_offsets: Array = _get_snapshot_infantry_visual_offsets(company_type, slot_role)
	for company_list_index in range(company_indices.size()):
		var company: Dictionary = companies[company_indices[company_list_index]]
		var company_center: Vector2 = center + front * company_offsets[company_list_index]
		result.append(_make_snapshot_company_visual_entry(
			company,
			String(slot_role),
			_build_snapshot_world_elements_from_offsets(element_offsets, company_center, front, right_axis)
		))
	return result


func _build_snapshot_single_arm_infantry_block_visual_elements(regiment_data: Dictionary, companies: Array, company_indices: Array, company_type: int) -> Array:
	var result: Array = []
	if company_indices.is_empty():
		return result
	var front: Vector2 = _get_regiment_front_direction(regiment_data)
	var right_axis: Vector2 = Vector2(-front.y, front.x).normalized()
	var center: Vector2 = regiment_data.get("position", Vector2.ZERO)
	var columns: int = int(ceil(sqrt(float(company_indices.size()))))
	var rows: int = int(ceil(float(company_indices.size()) / float(max(1, columns))))
	var company_centers: Array = _build_snapshot_rect_grid_offsets(columns, rows, 34.0, 28.0, Vector2.ZERO)
	var slot_role: String = "inner_shot" if company_type == SimTypes.CompanyType.MUSKETEERS else "pike_core"
	var element_offsets: Array = _get_snapshot_infantry_visual_offsets(company_type, StringName(slot_role))
	for company_list_index in range(company_indices.size()):
		var company: Dictionary = companies[company_indices[company_list_index]]
		var company_center: Vector2 = center + right_axis * company_centers[company_list_index].x + front * company_centers[company_list_index].y
		result.append(_make_snapshot_company_visual_entry(
			company,
			slot_role,
			_build_snapshot_world_elements_from_offsets(element_offsets, company_center, front, right_axis)
		))
	return result


func _build_snapshot_pike_and_shot_regiment_visual_layout(regiment_data: Dictionary, companies: Array) -> Array:
	if _is_snapshot_countermarch_active(regiment_data, companies):
		match int(regiment_data.get("formation_state", SimTypes.RegimentFormationState.DEFAULT)):
			SimTypes.RegimentFormationState.TERCIA:
				return _build_snapshot_tercia_countermarch_visual_elements(regiment_data, companies)
			SimTypes.RegimentFormationState.MUSKETEER_LINE:
				return _build_snapshot_musketeer_line_countermarch_visual_elements(regiment_data, companies)
			_:
				return _build_snapshot_line_countermarch_visual_elements(regiment_data, companies)
	match int(regiment_data.get("formation_state", SimTypes.RegimentFormationState.DEFAULT)):
		SimTypes.RegimentFormationState.MARCH_COLUMN:
			return _build_snapshot_pike_and_shot_column_visual_elements(regiment_data, companies)
		SimTypes.RegimentFormationState.PROTECTED:
			return _build_snapshot_pike_and_shot_protected_visual_elements(regiment_data, companies)
		SimTypes.RegimentFormationState.MUSKETEER_LINE:
			return _build_snapshot_pike_and_shot_musketeer_line_visual_elements(regiment_data, companies)
		SimTypes.RegimentFormationState.TERCIA:
			return _build_snapshot_pike_and_shot_tercia_visual_elements(regiment_data, companies)
		_:
			return _build_snapshot_pike_and_shot_line_visual_elements(regiment_data, companies)


func _build_snapshot_pike_and_shot_line_visual_elements(regiment_data: Dictionary, companies: Array) -> Array:
	var result: Array = []
	var musket_indices: Array = _get_company_indices_by_type(companies, SimTypes.CompanyType.MUSKETEERS)
	var pike_indices: Array = _get_company_indices_by_type(companies, SimTypes.CompanyType.PIKEMEN)
	var front: Vector2 = _get_regiment_front_direction(regiment_data)
	var right_axis: Vector2 = Vector2(-front.y, front.x).normalized()
	var center: Vector2 = regiment_data.get("position", Vector2.ZERO)
	var total_pike_elements: int = pike_indices.size() * 4
	var pike_columns: int = 4 if total_pike_elements > 8 else 2
	var pike_rows: int = int(ceil(float(total_pike_elements) / float(max(1, pike_columns))))
	var pike_offsets: Array = _build_snapshot_rect_grid_offsets(pike_columns, pike_rows, 20.0, 14.0, Vector2.ZERO)
	var pike_chunks: Array = _split_snapshot_offsets_for_companies(pike_offsets, pike_indices.size())
	for pike_list_index in range(pike_indices.size()):
		var pike_company: Dictionary = companies[pike_indices[pike_list_index]]
		result.append(_make_snapshot_company_visual_entry(
			pike_company,
			"pike_core",
			_build_snapshot_world_elements_from_offsets(pike_chunks[pike_list_index], center, front, right_axis)
		))
	var left_musket_count: int = int(ceil(float(musket_indices.size()) * 0.5))
	var right_musket_count: int = max(0, musket_indices.size() - left_musket_count)
	var musket_company_columns: int = 2 if left_musket_count <= 1 and right_musket_count <= 1 else 4
	var pike_half_width: float = _get_snapshot_grid_half_extent(pike_columns, 20.0, 9.0)
	var musket_half_width: float = _get_snapshot_grid_half_extent(musket_company_columns, 16.0, 9.0)
	var flank_center_x: float = pike_half_width + musket_half_width + 18.0
	if left_musket_count > 0:
		var left_columns: int = 2 if left_musket_count <= 1 else 4
		var left_rows: int = int(ceil(float(left_musket_count * 4) / float(left_columns)))
		var left_offsets: Array = _build_snapshot_rect_grid_offsets(left_columns, left_rows, 16.0, 16.0, Vector2(-flank_center_x, -5.0))
		var left_chunks: Array = _split_snapshot_offsets_for_companies(left_offsets, left_musket_count)
		for left_index in range(left_musket_count):
			var left_company: Dictionary = companies[musket_indices[left_index]]
			result.append(_make_snapshot_company_visual_entry(
				left_company,
				"left_shot",
				_build_snapshot_world_elements_from_offsets(left_chunks[left_index], center, front, right_axis)
			))
	if right_musket_count > 0:
		var right_columns: int = 2 if right_musket_count <= 1 else 4
		var right_rows: int = int(ceil(float(right_musket_count * 4) / float(right_columns)))
		var right_offsets: Array = _build_snapshot_rect_grid_offsets(right_columns, right_rows, 16.0, 16.0, Vector2(flank_center_x, -5.0))
		var right_chunks: Array = _split_snapshot_offsets_for_companies(right_offsets, right_musket_count)
		for right_index in range(right_musket_count):
			var right_company: Dictionary = companies[musket_indices[left_musket_count + right_index]]
			result.append(_make_snapshot_company_visual_entry(
				right_company,
				"right_shot",
				_build_snapshot_world_elements_from_offsets(right_chunks[right_index], center, front, right_axis)
			))
	return result


func _build_snapshot_pike_and_shot_column_visual_elements(regiment_data: Dictionary, companies: Array) -> Array:
	var result: Array = []
	var musket_indices: Array = _get_company_indices_by_type(companies, SimTypes.CompanyType.MUSKETEERS)
	var pike_indices: Array = _get_company_indices_by_type(companies, SimTypes.CompanyType.PIKEMEN)
	var front: Vector2 = _get_regiment_front_direction(regiment_data)
	var right_axis: Vector2 = Vector2(-front.y, front.x).normalized()
	var center: Vector2 = regiment_data.get("position", Vector2.ZERO)
	var lead_guard_count: int = int(ceil(float(musket_indices.size()) * 0.5))
	var ordered_indices: Array = []
	var ordered_roles: Array = []
	for lead_index in range(lead_guard_count):
		ordered_indices.append(musket_indices[lead_index])
		ordered_roles.append("advance_guard")
	for pike_index in pike_indices:
		ordered_indices.append(pike_index)
		ordered_roles.append("column_core")
	for rear_index in range(lead_guard_count, musket_indices.size()):
		ordered_indices.append(musket_indices[rear_index])
		ordered_roles.append("rear_guard")
	var company_offsets: Array = _build_snapshot_front_to_rear_column_offsets(ordered_indices.size(), 36.0)
	var element_offsets: Array = _build_snapshot_rect_grid_offsets(2, 2, 12.0, 12.0, Vector2.ZERO)
	for ordered_index in range(ordered_indices.size()):
		var company: Dictionary = companies[ordered_indices[ordered_index]]
		var company_center: Vector2 = center + front * company_offsets[ordered_index]
		result.append(_make_snapshot_company_visual_entry(
			company,
			ordered_roles[ordered_index],
			_build_snapshot_world_elements_from_offsets(element_offsets, company_center, front, right_axis)
		))
	return result


func _build_snapshot_pike_and_shot_musketeer_line_visual_elements(regiment_data: Dictionary, companies: Array) -> Array:
	var result: Array = []
	var musket_indices: Array = _get_company_indices_by_type(companies, SimTypes.CompanyType.MUSKETEERS)
	var pike_indices: Array = _get_company_indices_by_type(companies, SimTypes.CompanyType.PIKEMEN)
	var front: Vector2 = _get_regiment_front_direction(regiment_data)
	var right_axis: Vector2 = Vector2(-front.y, front.x).normalized()
	var center: Vector2 = regiment_data.get("position", Vector2.ZERO)
	var total_musket_elements: int = musket_indices.size() * 4
	var musket_columns: int = 4 if total_musket_elements <= 8 else 8
	var musket_rows: int = int(ceil(float(total_musket_elements) / float(max(1, musket_columns))))
	var musket_offsets: Array = _build_snapshot_rect_grid_offsets(musket_columns, musket_rows, 18.0, 14.0, Vector2(0.0, 23.0))
	var total_pike_elements: int = pike_indices.size() * 4
	var pike_columns: int = 4 if total_pike_elements > 8 else 2
	var pike_rows: int = int(ceil(float(total_pike_elements) / float(max(1, pike_columns))))
	var pike_offsets: Array = _build_snapshot_rect_grid_offsets(pike_columns, pike_rows, 20.0, 12.0, Vector2(0.0, -22.0))
	var musket_chunks: Array = _split_snapshot_offsets_for_companies(musket_offsets, musket_indices.size())
	for musket_list_index in range(musket_indices.size()):
		var musket_company: Dictionary = companies[musket_indices[musket_list_index]]
		var musket_elements: Array = []
		for local_offset_value in musket_chunks[musket_list_index]:
			var local_offset: Vector2 = local_offset_value
			musket_elements.append({
				"position": center + right_axis * local_offset.x + front * local_offset.y,
				"front_direction": front,
			})
		result.append(_make_snapshot_company_visual_entry(musket_company, "front_shot", musket_elements))
	var pike_chunks: Array = _split_snapshot_offsets_for_companies(pike_offsets, pike_indices.size())
	for pike_list_index in range(pike_indices.size()):
		var pike_company: Dictionary = companies[pike_indices[pike_list_index]]
		var pike_elements: Array = []
		for local_offset_value in pike_chunks[pike_list_index]:
			var local_offset: Vector2 = local_offset_value
			pike_elements.append({
				"position": center + right_axis * local_offset.x + front * local_offset.y,
				"front_direction": front,
			})
		result.append(_make_snapshot_company_visual_entry(pike_company, "rear_pike", pike_elements))
	return result


func _build_snapshot_line_countermarch_visual_elements(regiment_data: Dictionary, companies: Array) -> Array:
	var result: Array = []
	var musket_indices: Array = _get_company_indices_by_type(companies, SimTypes.CompanyType.MUSKETEERS)
	var pike_indices: Array = _get_company_indices_by_type(companies, SimTypes.CompanyType.PIKEMEN)
	var front: Vector2 = _get_regiment_front_direction(regiment_data)
	var right_axis: Vector2 = Vector2(-front.y, front.x).normalized()
	var center: Vector2 = regiment_data.get("position", Vector2.ZERO)
	var cycle_state: Dictionary = _get_snapshot_countermarch_cycle_state(regiment_data)
	var swap_rows: bool = bool(cycle_state.get("swap_rows", false))
	var fire_phase: bool = bool(cycle_state.get("fire_phase", true))
	var total_pike_elements: int = pike_indices.size() * 4
	var pike_columns: int = 4 if total_pike_elements > 8 else 2
	var pike_rows: int = int(ceil(float(total_pike_elements) / float(max(1, pike_columns))))
	var pike_offsets: Array = _build_snapshot_rect_grid_offsets(pike_columns, pike_rows, 20.0, 14.0, Vector2.ZERO)
	var pike_chunks: Array = _split_snapshot_offsets_for_companies(pike_offsets, pike_indices.size())
	for pike_list_index in range(pike_indices.size()):
		var pike_company: Dictionary = companies[pike_indices[pike_list_index]]
		result.append(_make_snapshot_company_visual_entry(
			pike_company,
			"pike_core",
			_build_snapshot_world_elements_from_offsets(pike_chunks[pike_list_index], center, front, right_axis)
		))
	var left_musket_count: int = int(ceil(float(musket_indices.size()) * 0.5))
	var right_musket_count: int = max(0, musket_indices.size() - left_musket_count)
	var flank_center_x: float = 52.0 if pike_columns <= 2 else 68.0
	var left_rank_offsets: Array = _build_snapshot_front_to_rear_column_offsets(left_musket_count, 24.0)
	for left_index in range(left_musket_count):
		var left_company: Dictionary = companies[musket_indices[left_index]]
		var left_center: Vector2 = center - right_axis * flank_center_x + front * left_rank_offsets[left_index]
		result.append(_make_snapshot_company_visual_entry(
			left_company,
			"countermarch_shot",
			_build_snapshot_countermarch_company_elements(left_center, front, right_axis, 16.0, 12.0, swap_rows, fire_phase)
		))
	var right_rank_offsets: Array = _build_snapshot_front_to_rear_column_offsets(right_musket_count, 24.0)
	for right_index in range(right_musket_count):
		var right_company: Dictionary = companies[musket_indices[left_musket_count + right_index]]
		var right_center: Vector2 = center + right_axis * flank_center_x + front * right_rank_offsets[right_index]
		result.append(_make_snapshot_company_visual_entry(
			right_company,
			"countermarch_shot",
			_build_snapshot_countermarch_company_elements(right_center, front, right_axis, 16.0, 12.0, swap_rows, fire_phase)
		))
	return result


func _build_snapshot_musketeer_line_countermarch_visual_elements(regiment_data: Dictionary, companies: Array) -> Array:
	var result: Array = []
	var musket_indices: Array = _get_company_indices_by_type(companies, SimTypes.CompanyType.MUSKETEERS)
	var pike_indices: Array = _get_company_indices_by_type(companies, SimTypes.CompanyType.PIKEMEN)
	var front: Vector2 = _get_regiment_front_direction(regiment_data)
	var right_axis: Vector2 = Vector2(-front.y, front.x).normalized()
	var center: Vector2 = regiment_data.get("position", Vector2.ZERO)
	var cycle_state: Dictionary = _get_snapshot_countermarch_cycle_state(regiment_data)
	var swap_rows: bool = bool(cycle_state.get("swap_rows", false))
	var fire_phase: bool = bool(cycle_state.get("fire_phase", true))
	var total_pike_elements: int = pike_indices.size() * 4
	var pike_columns: int = 4 if total_pike_elements > 8 else 2
	var pike_rows: int = int(ceil(float(total_pike_elements) / float(max(1, pike_columns))))
	var pike_offsets: Array = _build_snapshot_rect_grid_offsets(pike_columns, pike_rows, 20.0, 12.0, Vector2(0.0, -24.0))
	var pike_chunks: Array = _split_snapshot_offsets_for_companies(pike_offsets, pike_indices.size())
	for pike_list_index in range(pike_indices.size()):
		var pike_company: Dictionary = companies[pike_indices[pike_list_index]]
		result.append(_make_snapshot_company_visual_entry(
			pike_company,
			"rear_pike",
			_build_snapshot_world_elements_from_offsets(pike_chunks[pike_list_index], center, front, right_axis)
		))
	var musket_company_offsets: Array = _build_snapshot_rect_grid_offsets(min(4, max(1, musket_indices.size())), int(ceil(float(musket_indices.size()) / 4.0)), 26.0, 24.0, Vector2(0.0, 28.0))
	for musket_list_index in range(musket_indices.size()):
		var musket_company: Dictionary = companies[musket_indices[musket_list_index]]
		var company_offset: Vector2 = musket_company_offsets[musket_list_index]
		var company_center: Vector2 = center + right_axis * company_offset.x + front * company_offset.y
		result.append(_make_snapshot_company_visual_entry(
			musket_company,
			"countermarch_shot",
			_build_snapshot_countermarch_company_elements(company_center, front, right_axis, 16.0, 12.0, swap_rows, fire_phase)
		))
	return result


func _build_snapshot_tercia_countermarch_visual_elements(regiment_data: Dictionary, companies: Array) -> Array:
	var base_entries: Array = _build_snapshot_pike_and_shot_tercia_visual_elements(regiment_data, companies)
	var result: Array = []
	var cycle_state: Dictionary = _get_snapshot_countermarch_cycle_state(regiment_data)
	var swap_rows: bool = bool(cycle_state.get("swap_rows", false))
	var fire_phase: bool = bool(cycle_state.get("fire_phase", true))
	var entries_by_company: Dictionary = {}
	for entry_value in base_entries:
		var entry: Dictionary = entry_value
		entries_by_company[StringName(entry.get("company_id", ""))] = entry
	for company_value in companies:
		var company: Dictionary = company_value
		var base_entry: Dictionary = entries_by_company.get(StringName(company.get("id", "")), {})
		if base_entry.is_empty():
			continue
		if int(company.get("company_type", SimTypes.CompanyType.MUSKETEERS)) != SimTypes.CompanyType.MUSKETEERS:
			result.append(base_entry)
			continue
		result.append(_make_snapshot_company_visual_entry(
			company,
			"countermarch_shot",
			_build_snapshot_countermarch_elements_from_base_entry(base_entry, regiment_data, swap_rows, fire_phase)
		))
	return result


func _build_snapshot_pike_and_shot_protected_visual_elements(regiment_data: Dictionary, companies: Array) -> Array:
	var result: Array = []
	var musket_indices: Array = _get_company_indices_by_type(companies, SimTypes.CompanyType.MUSKETEERS)
	var pike_indices: Array = _get_company_indices_by_type(companies, SimTypes.CompanyType.PIKEMEN)
	var front: Vector2 = _get_regiment_front_direction(regiment_data)
	var right_axis: Vector2 = Vector2(-front.y, front.x).normalized()
	var center: Vector2 = regiment_data.get("position", Vector2.ZERO)
	var total_musket_elements: int = musket_indices.size() * 4
	var musket_rows: int = int(ceil(float(total_musket_elements) / 4.0))
	var musket_offsets: Array = _build_snapshot_rect_grid_offsets(4, musket_rows, 11.0, 16.0, Vector2.ZERO)
	var side_count: int = max(2, int((pike_indices.size() * 4) / 4))
	var pike_offsets: Array = []
	for local_offset_value in _build_snapshot_rect_grid_offsets(side_count, 1, 16.0, 16.0, Vector2(0.0, -30.0)):
		pike_offsets.append({"offset": local_offset_value, "front": -front})
	for local_offset_value in _build_snapshot_rect_grid_offsets(1, side_count, 16.0, 16.0, Vector2(-32.0, 0.0)):
		pike_offsets.append({"offset": local_offset_value, "front": -right_axis})
	for local_offset_value in _build_snapshot_rect_grid_offsets(1, side_count, 16.0, 16.0, Vector2(32.0, 0.0)):
		pike_offsets.append({"offset": local_offset_value, "front": right_axis})
	for local_offset_value in _build_snapshot_rect_grid_offsets(side_count, 1, 16.0, 16.0, Vector2(0.0, 30.0)):
		pike_offsets.append({"offset": local_offset_value, "front": front})
	var musket_chunks: Array = _split_snapshot_offsets_for_companies(musket_offsets, musket_indices.size())
	for musket_list_index in range(musket_indices.size()):
		var company: Dictionary = companies[musket_indices[musket_list_index]]
		var elements: Array = []
		for local_offset_value in musket_chunks[musket_list_index]:
			var local_offset: Vector2 = local_offset_value
			elements.append({
				"position": center + right_axis * local_offset.x + front * local_offset.y,
				"front_direction": front,
			})
		result.append(_make_snapshot_company_visual_entry(company, "inner_shot", elements))
	var pike_chunks: Array = _split_snapshot_offsets_for_companies(pike_offsets, pike_indices.size())
	for pike_list_index in range(pike_indices.size()):
		var company: Dictionary = companies[pike_indices[pike_list_index]]
		var elements: Array = []
		for entry_value in pike_chunks[pike_list_index]:
			var pike_entry: Dictionary = entry_value
			var local_offset: Vector2 = pike_entry.get("offset", Vector2.ZERO)
			var element_front: Vector2 = pike_entry.get("front", front)
			elements.append({
				"position": center + right_axis * local_offset.x + front * local_offset.y,
				"front_direction": element_front,
			})
		result.append(_make_snapshot_company_visual_entry(company, "outer_pike", elements))
	return result


func _build_snapshot_pike_and_shot_tercia_visual_elements(regiment_data: Dictionary, companies: Array) -> Array:
	var musket_indices: Array = _get_company_indices_by_type(companies, SimTypes.CompanyType.MUSKETEERS)
	var pike_indices: Array = _get_company_indices_by_type(companies, SimTypes.CompanyType.PIKEMEN)
	if musket_indices.is_empty() or pike_indices.is_empty():
		return _build_snapshot_pike_and_shot_line_visual_elements(regiment_data, companies)
	if musket_indices.size() >= 3 or pike_indices.size() >= 3:
		return _build_snapshot_full_tercia_visual_elements(regiment_data, companies, musket_indices, pike_indices)
	return _build_snapshot_compact_tercia_visual_elements(regiment_data, companies, musket_indices, pike_indices)


func _build_snapshot_full_tercia_visual_elements(regiment_data: Dictionary, companies: Array, musket_indices: Array, pike_indices: Array) -> Array:
	var result: Array = []
	var front: Vector2 = _get_regiment_front_direction(regiment_data)
	var right_axis: Vector2 = Vector2(-front.y, front.x).normalized()
	var center: Vector2 = regiment_data.get("position", Vector2.ZERO)
	var pike_company_columns: int = int(ceil(sqrt(float(max(1, pike_indices.size())))))
	var pike_company_rows: int = int(ceil(float(pike_indices.size()) / float(max(1, pike_company_columns))))
	var pike_company_centers: Array = _build_snapshot_rect_grid_offsets(pike_company_columns, pike_company_rows, 32.0, 30.0, Vector2.ZERO)
	for pike_list_index in range(pike_indices.size()):
		var pike_company: Dictionary = companies[pike_indices[pike_list_index]]
		var pike_block_offsets: Array = _build_snapshot_rect_grid_offsets(2, 2, 17.0, 15.0, pike_company_centers[pike_list_index])
		result.append(_make_snapshot_company_visual_entry(
			pike_company,
			"tercia_pike",
			_build_snapshot_world_elements_from_offsets(pike_block_offsets, center, front, right_axis)
		))
	var core_half_width: float = max(18.0, (float(pike_company_columns - 1) * 16.0) + 24.0)
	var core_half_depth: float = max(18.0, (float(pike_company_rows - 1) * 15.0) + 22.0)
	var sleeve_company_centers: Array = _build_snapshot_tercia_sleeve_company_centers(
		musket_indices.size(),
		core_half_width + 24.0,
		core_half_depth + 20.0,
		28.0,
		28.0
	)
	for musket_list_index in range(musket_indices.size()):
		var musket_company: Dictionary = companies[musket_indices[musket_list_index]]
		var corner_offset: Vector2 = sleeve_company_centers[musket_list_index]
		var local_offsets: Array = _build_snapshot_rect_grid_offsets(2, 2, 17.0, 17.0, corner_offset)
		result.append(_make_snapshot_company_visual_entry(
			musket_company,
			"corner_shot",
			_build_snapshot_world_elements_from_offsets(local_offsets, center, front, right_axis)
		))
	return result


func _build_snapshot_compact_tercia_visual_elements(regiment_data: Dictionary, companies: Array, musket_indices: Array, pike_indices: Array) -> Array:
	var result: Array = []
	var front: Vector2 = _get_regiment_front_direction(regiment_data)
	var right_axis: Vector2 = Vector2(-front.y, front.x).normalized()
	var center: Vector2 = regiment_data.get("position", Vector2.ZERO)
	var front_pike_block: Array = _build_snapshot_rect_grid_offsets(2, 2, 16.0, 14.0, Vector2(0.0, -10.0))
	var rear_pike_block: Array = _build_snapshot_rect_grid_offsets(2, 2, 16.0, 14.0, Vector2(0.0, 10.0))
	if pike_indices.size() >= 1:
		result.append(_make_snapshot_company_visual_entry(
			companies[pike_indices[0]],
			"tercia_pike",
			_build_snapshot_world_elements_from_offsets(front_pike_block, center, front, right_axis)
		))
	if pike_indices.size() >= 2:
		result.append(_make_snapshot_company_visual_entry(
			companies[pike_indices[1]],
			"tercia_pike",
			_build_snapshot_world_elements_from_offsets(rear_pike_block, center, front, right_axis)
		))
	var front_corner_offsets: Array = []
	front_corner_offsets.append_array(_build_snapshot_rect_grid_offsets(1, 2, 14.0, 14.0, Vector2(-36.0, 28.0)))
	front_corner_offsets.append_array(_build_snapshot_rect_grid_offsets(1, 2, 14.0, 14.0, Vector2(36.0, 28.0)))
	if musket_indices.size() >= 1:
		result.append(_make_snapshot_company_visual_entry(
			companies[musket_indices[0]],
			"corner_shot",
			_build_snapshot_world_elements_from_offsets(front_corner_offsets, center, front, right_axis)
		))
	var rear_corner_offsets: Array = []
	rear_corner_offsets.append_array(_build_snapshot_rect_grid_offsets(1, 2, 14.0, 14.0, Vector2(-36.0, -28.0)))
	rear_corner_offsets.append_array(_build_snapshot_rect_grid_offsets(1, 2, 14.0, 14.0, Vector2(36.0, -28.0)))
	if musket_indices.size() >= 2:
		result.append(_make_snapshot_company_visual_entry(
			companies[musket_indices[1]],
			"corner_shot",
			_build_snapshot_world_elements_from_offsets(rear_corner_offsets, center, front, right_axis)
		))
	return result


func _build_snapshot_cavalry_regiment_visual_layout(regiment_data: Dictionary, companies: Array) -> Array:
	if _is_snapshot_caracole_active(regiment_data):
		return _build_snapshot_cavalry_caracole_visual_elements(regiment_data, companies)
	if int(regiment_data.get("formation_type", SimTypes.FormationType.LINE)) == SimTypes.FormationType.COLUMN:
		return _build_snapshot_cavalry_column_visual_elements(regiment_data, companies)
	return _build_snapshot_cavalry_line_visual_elements(regiment_data, companies)


func _build_snapshot_cavalry_line_visual_elements(regiment_data: Dictionary, companies: Array) -> Array:
	var result: Array = []
	var front: Vector2 = _get_regiment_front_direction(regiment_data)
	var right_axis: Vector2 = Vector2(-front.y, front.x).normalized()
	var center: Vector2 = regiment_data.get("position", Vector2.ZERO)
	var company_offsets: Array = _build_snapshot_rect_grid_offsets(companies.size(), 1, 26.0, 18.0, Vector2.ZERO)
	var cavalry_offsets: Array = _get_snapshot_cavalry_visual_offsets(&"cavalry_line")
	for company_index in range(companies.size()):
		var company: Dictionary = companies[company_index]
		var company_center: Vector2 = center + right_axis * company_offsets[company_index].x + front * company_offsets[company_index].y
		result.append(_make_snapshot_company_visual_entry(company, "cavalry_line", _build_snapshot_world_elements_from_offsets(cavalry_offsets, company_center, front, right_axis)))
	return result


func _build_snapshot_cavalry_column_visual_elements(regiment_data: Dictionary, companies: Array) -> Array:
	var result: Array = []
	var front: Vector2 = _get_regiment_front_direction(regiment_data)
	var right_axis: Vector2 = Vector2(-front.y, front.x).normalized()
	var center: Vector2 = regiment_data.get("position", Vector2.ZERO)
	var company_offsets: Array = _build_snapshot_rect_grid_offsets(1, companies.size(), 20.0, 28.0, Vector2.ZERO)
	var cavalry_offsets: Array = _get_snapshot_cavalry_visual_offsets(&"cavalry_column")
	for company_index in range(companies.size()):
		var company: Dictionary = companies[company_index]
		var company_center: Vector2 = center + right_axis * company_offsets[company_index].x + front * company_offsets[company_index].y
		result.append(_make_snapshot_company_visual_entry(company, "cavalry_column", _build_snapshot_world_elements_from_offsets(cavalry_offsets, company_center, front, right_axis)))
	return result


func _build_snapshot_cavalry_caracole_visual_elements(regiment_data: Dictionary, companies: Array) -> Array:
	var result: Array = []
	var front: Vector2 = _get_regiment_front_direction(regiment_data)
	var right_axis: Vector2 = Vector2(-front.y, front.x).normalized()
	var cavalry_indices: Array = _get_company_indices_by_type(companies, SimTypes.CompanyType.CAVALRY)
	if cavalry_indices.is_empty():
		return result
	var cycle_state: Dictionary = _get_snapshot_caracole_cycle_state(regiment_data, cavalry_indices.size())
	var wave_size: int = int(cycle_state.get("wave_size", 1))
	var ordered_indices: Array = _rotate_snapshot_indices(cavalry_indices, int(cycle_state.get("cycle_index", 0)))
	var advanced_indices: Array = ordered_indices.slice(wave_size, ordered_indices.size())
	advanced_indices.append_array(ordered_indices.slice(0, wave_size))
	var start_offsets: Array = _build_snapshot_front_to_rear_column_offsets(ordered_indices.size(), 28.0)
	var end_offsets: Array = _build_snapshot_front_to_rear_column_offsets(advanced_indices.size(), 28.0)
	var cavalry_offsets: Array = _get_snapshot_cavalry_visual_offsets(&"cavalry_column")
	var flank_offset: float = -34.0
	var phase: int = int(cycle_state.get("phase", 0))
	var phase_progress: float = float(cycle_state.get("phase_progress", 0.0))
	var column_shift_weight: float = _get_snapshot_caracole_column_shift_weight(phase, phase_progress)
	var center: Vector2 = regiment_data.get("position", Vector2.ZERO)
	var start_center_by_company: Dictionary = {}
	var end_center_by_company: Dictionary = {}
	for ordered_index in range(ordered_indices.size()):
		var company_index: int = ordered_indices[ordered_index]
		start_center_by_company[company_index] = center + front * start_offsets[ordered_index]
	for advanced_index in range(advanced_indices.size()):
		var company_index: int = advanced_indices[advanced_index]
		end_center_by_company[company_index] = center + front * end_offsets[advanced_index]
	for ordered_index in range(ordered_indices.size()):
		var company_index: int = ordered_indices[ordered_index]
		var company: Dictionary = companies[company_index]
		var start_center: Vector2 = start_center_by_company.get(company_index, center)
		var end_center: Vector2 = end_center_by_company.get(company_index, start_center)
		var company_center: Vector2 = start_center
		var slot_role: String = "cavalry_column"
		if ordered_index < wave_size:
			var front_lane_center: Vector2 = start_center + right_axis * flank_offset
			var rear_lane_center: Vector2 = end_center + right_axis * flank_offset
			slot_role = "caracole_front" if phase == 0 else "caracole_reforming"
			match phase:
				0:
					company_center = start_center
				1:
					company_center = start_center.lerp(front_lane_center, phase_progress)
				2:
					company_center = front_lane_center.lerp(rear_lane_center, phase_progress)
				_:
					company_center = rear_lane_center.lerp(end_center, phase_progress)
		else:
			company_center = start_center.lerp(end_center, column_shift_weight)
		result.append(_make_snapshot_company_visual_entry(company, slot_role, _build_snapshot_world_elements_from_offsets(cavalry_offsets, company_center, front, right_axis)))
	return result


func _build_snapshot_artillery_regiment_visual_layout(regiment_data: Dictionary, companies: Array) -> Array:
	if int(regiment_data.get("formation_type", SimTypes.FormationType.LINE)) == SimTypes.FormationType.COLUMN:
		return _build_snapshot_artillery_column_visual_elements(regiment_data, companies)
	return _build_snapshot_artillery_line_visual_elements(regiment_data, companies)


func _build_snapshot_artillery_line_visual_elements(regiment_data: Dictionary, companies: Array) -> Array:
	var result: Array = []
	var front: Vector2 = _get_regiment_front_direction(regiment_data)
	var right_axis: Vector2 = Vector2(-front.y, front.x).normalized()
	var center: Vector2 = regiment_data.get("position", Vector2.ZERO)
	var company_offsets: Array = _build_snapshot_rect_grid_offsets(companies.size(), 1, 32.0, 22.0, Vector2.ZERO)
	for company_index in range(companies.size()):
		var company: Dictionary = companies[company_index]
		var company_center: Vector2 = center + right_axis * company_offsets[company_index].x + front * company_offsets[company_index].y
		result.append(_make_snapshot_company_visual_entry(company, "battery_line", _build_snapshot_artillery_company_elements(company_center, front, right_axis)))
	return result


func _build_snapshot_artillery_column_visual_elements(regiment_data: Dictionary, companies: Array) -> Array:
	var result: Array = []
	var front: Vector2 = _get_regiment_front_direction(regiment_data)
	var right_axis: Vector2 = Vector2(-front.y, front.x).normalized()
	var center: Vector2 = regiment_data.get("position", Vector2.ZERO)
	var company_offsets: Array = _build_snapshot_rect_grid_offsets(1, companies.size(), 20.0, 36.0, Vector2.ZERO)
	for company_index in range(companies.size()):
		var company: Dictionary = companies[company_index]
		var company_center: Vector2 = center + right_axis * company_offsets[company_index].x + front * company_offsets[company_index].y
		result.append(_make_snapshot_company_visual_entry(company, "battery_column", _build_snapshot_artillery_company_elements(company_center, front, right_axis)))
	return result


func _get_regiment_front_direction(regiment_data: Dictionary) -> Vector2:
	var front: Vector2 = regiment_data.get("front_direction", Vector2.UP)
	if front.length_squared() <= 0.001:
		front = Vector2.UP
	return front.normalized()


func _has_pike_and_shot_companies(companies: Array) -> bool:
	return not _get_company_indices_by_type(companies, SimTypes.CompanyType.MUSKETEERS).is_empty() \
		and not _get_company_indices_by_type(companies, SimTypes.CompanyType.PIKEMEN).is_empty()


func _get_company_indices_by_type(companies: Array, target_type: int) -> Array:
	var indices: Array = []
	for company_index in range(companies.size()):
		var company: Dictionary = companies[company_index]
		if int(company.get("company_type", SimTypes.CompanyType.MUSKETEERS)) == target_type:
			indices.append(company_index)
	return indices


func _is_snapshot_countermarch_active(regiment_data: Dictionary, companies: Array) -> bool:
	if int(regiment_data.get("fire_behavior", SimTypes.RegimentFireBehavior.NONE)) != SimTypes.RegimentFireBehavior.COUNTERMARCH:
		return false
	if int(regiment_data.get("category", SimTypes.UnitCategory.INFANTRY)) != SimTypes.UnitCategory.INFANTRY:
		return false
	if not _has_pike_and_shot_companies(companies):
		return false
	var formation_state: int = int(regiment_data.get("formation_state", SimTypes.RegimentFormationState.DEFAULT))
	if formation_state == SimTypes.RegimentFormationState.PROTECTED:
		return false
	return formation_state in [
		SimTypes.RegimentFormationState.DEFAULT,
		SimTypes.RegimentFormationState.MUSKETEER_LINE,
		SimTypes.RegimentFormationState.TERCIA,
	]


func _is_snapshot_caracole_active(regiment_data: Dictionary) -> bool:
	return int(regiment_data.get("fire_behavior", SimTypes.RegimentFireBehavior.NONE)) == SimTypes.RegimentFireBehavior.CARACOLE \
		and int(regiment_data.get("formation_type", SimTypes.FormationType.LINE)) == SimTypes.FormationType.COLUMN


func _make_snapshot_company_visual_entry(company: Dictionary, slot_role: String, elements: Array) -> Dictionary:
	return {
		"company_id": String(company.get("id", "")),
		"company_type": company.get("company_type", SimTypes.CompanyType.MUSKETEERS),
		"weapon_type": company.get("weapon_type", ""),
		"slot_role": slot_role,
		"elements": elements,
	}


func _order_snapshot_visual_entries_by_company(companies: Array, visual_entries: Array) -> Array:
	var entries_by_company: Dictionary = {}
	for entry_value in visual_entries:
		var entry: Dictionary = entry_value
		entries_by_company[StringName(entry.get("company_id", ""))] = entry
	var ordered_entries: Array = []
	for company_value in companies:
		var company: Dictionary = company_value
		var company_id: StringName = StringName(company.get("id", ""))
		if entries_by_company.has(company_id):
			ordered_entries.append(entries_by_company[company_id])
	return ordered_entries


func _get_visual_elements_center(elements: Array) -> Vector2:
	if elements.is_empty():
		return Vector2.ZERO
	var total: Vector2 = Vector2.ZERO
	for element_value in elements:
		var element: Dictionary = element_value
		total += element.get("position", Vector2.ZERO)
	return total / float(elements.size())


func _get_dominant_front_direction(elements: Array) -> Vector2:
	var total: Vector2 = Vector2.ZERO
	for element_value in elements:
		var element: Dictionary = element_value
		total += element.get("front_direction", Vector2.ZERO)
	if total.length_squared() <= 0.001:
		return Vector2.UP
	return total.normalized()


func _build_snapshot_rect_grid_offsets(columns: int, rows: int, x_spacing: float, y_spacing: float, center_offset: Vector2 = Vector2.ZERO) -> Array:
	var offsets: Array = []
	if columns <= 0 or rows <= 0:
		return offsets
	var half_width: float = float(columns - 1) * 0.5
	var half_height: float = float(rows - 1) * 0.5
	for row in range(rows):
		for column in range(columns):
			var local_x: float = (float(column) - half_width) * x_spacing + center_offset.x
			var local_y: float = (float(row) - half_height) * y_spacing + center_offset.y
			offsets.append(Vector2(local_x, local_y))
	return offsets


func _get_snapshot_grid_half_extent(columns: int, spacing: float, element_half_extent: float = 0.0) -> float:
	if columns <= 0:
		return element_half_extent
	return float(columns - 1) * spacing * 0.5 + element_half_extent


func _split_snapshot_offsets_for_companies(source: Array, company_count: int) -> Array:
	var result: Array = []
	for _index in range(max(1, company_count)):
		result.append([])
	if company_count <= 0:
		return result
	for source_index in range(source.size()):
		result[source_index % company_count].append(source[source_index])
	return result


func _build_snapshot_front_to_rear_column_offsets(count: int, spacing: float, shift: float = 0.0) -> Array:
	var offsets: Array = []
	if count <= 0:
		return offsets
	var front_offset: float = float(count - 1) * 0.5 * spacing + shift
	for index in range(count):
		offsets.append(front_offset - float(index) * spacing)
	return offsets


func _build_snapshot_countermarch_company_elements(center: Vector2, front: Vector2, right_axis: Vector2, width: float, depth: float, swap_rows: bool, fire_phase: bool) -> Array:
	var column_positions: Array = [-width * 0.5, width * 0.5]
	var front_rank_y: float = depth * 0.5
	var rear_rank_y: float = -depth * 0.5
	return _build_snapshot_countermarch_musket_elements(center, front, right_axis, column_positions, front_rank_y, rear_rank_y, swap_rows, fire_phase)


func _build_snapshot_countermarch_elements_from_base_entry(base_entry: Dictionary, regiment_data: Dictionary, swap_rows: bool, fire_phase: bool) -> Array:
	var base_elements: Array = base_entry.get("elements", [])
	if base_elements.is_empty():
		return []
	var center: Vector2 = _get_visual_elements_center(base_elements)
	var front: Vector2 = _get_dominant_front_direction(base_elements)
	if front.length_squared() <= 0.001:
		front = _get_regiment_front_direction(regiment_data)
	var right_axis: Vector2 = Vector2(-front.y, front.x).normalized()
	var projected_width: float = 0.0
	var projected_depth: float = 0.0
	for element_value in base_elements:
		var element: Dictionary = element_value
		var local_offset: Vector2 = element.get("position", center) - center
		projected_width = max(projected_width, absf(local_offset.dot(right_axis)))
		projected_depth = max(projected_depth, absf(local_offset.dot(front)))
	var width: float = max(14.0, projected_width * 2.0)
	var depth: float = max(10.0, projected_depth * 2.0)
	return _build_snapshot_countermarch_company_elements(center, front, right_axis, width, depth, swap_rows, fire_phase)


func _build_snapshot_countermarch_musket_elements(center: Vector2, front: Vector2, right_axis: Vector2, column_positions: Array, front_rank_y: float, rear_rank_y: float, swap_rows: bool, fire_phase: bool) -> Array:
	var result: Array = []
	var front_role: StringName = &"countermarch_front" if fire_phase else &"countermarch_support"
	var rear_role: StringName = &"countermarch_rear"
	if swap_rows:
		for column_x_value in column_positions:
			var column_x: float = float(column_x_value)
			result.append({
				"position": center + right_axis * column_x + front * rear_rank_y,
				"front_direction": front,
				"role": rear_role,
			})
		for column_x_value in column_positions:
			var column_x: float = float(column_x_value)
			result.append({
				"position": center + right_axis * column_x + front * front_rank_y,
				"front_direction": front,
				"role": front_role,
			})
		return result
	for column_x_value in column_positions:
		var column_x: float = float(column_x_value)
		result.append({
			"position": center + right_axis * column_x + front * front_rank_y,
			"front_direction": front,
			"role": front_role,
		})
	for column_x_value in column_positions:
		var column_x: float = float(column_x_value)
		result.append({
			"position": center + right_axis * column_x + front * rear_rank_y,
			"front_direction": front,
			"role": rear_role,
		})
	return result


func _get_snapshot_countermarch_cycle_state(regiment_data: Dictionary) -> Dictionary:
	var cycle_duration: float = 1.15
	var local_time: float = _sim_time_seconds + _get_regiment_phase_offset(regiment_data, cycle_duration)
	var cycle_progress: float = fposmod(local_time, cycle_duration)
	return {
		"swap_rows": bool(int(floor(local_time / cycle_duration)) % 2),
		"fire_phase": cycle_progress <= 0.42,
	}


func _get_snapshot_caracole_cycle_state(regiment_data: Dictionary, company_count: int) -> Dictionary:
	var phase_durations: Array = [0.45, 0.22, 0.55, 0.24]
	var cycle_duration: float = 1.46
	var local_time: float = _sim_time_seconds + _get_regiment_phase_offset(regiment_data, cycle_duration)
	var cycle_count: int = int(floor(local_time / cycle_duration))
	var phase_time: float = fposmod(local_time, cycle_duration)
	var phase: int = 0
	var elapsed: float = 0.0
	for phase_index in range(phase_durations.size()):
		var duration: float = float(phase_durations[phase_index])
		if phase_time <= elapsed + duration or phase_index == phase_durations.size() - 1:
			phase = phase_index
			phase_time -= elapsed
			break
		elapsed += duration
	var phase_duration: float = float(phase_durations[phase])
	var wave_size: int = _get_snapshot_caracole_wave_size(company_count)
	return {
		"wave_size": wave_size,
		"cycle_index": posmod(cycle_count * wave_size, max(1, company_count)),
		"phase": phase,
		"phase_progress": clamp(phase_time / max(0.001, phase_duration), 0.0, 1.0),
	}


func _get_snapshot_caracole_wave_size(company_count: int) -> int:
	if company_count <= 0:
		return 1
	return clamp(int(ceil(float(company_count) * 0.25)), 1, company_count)


func _get_snapshot_caracole_column_shift_weight(phase: int, phase_progress: float) -> float:
	match phase:
		0:
			return 0.0
		1:
			return phase_progress * 0.25
		2:
			return 0.25 + phase_progress * 0.5
		_:
			return 0.75 + phase_progress * 0.25


func _rotate_snapshot_indices(source: Array, front_index: int) -> Array:
	if source.is_empty():
		return []
	var rotated: Array = []
	var start_index: int = posmod(front_index, source.size())
	for index_offset in range(source.size()):
		rotated.append(source[(start_index + index_offset) % source.size()])
	return rotated


func _build_snapshot_tercia_sleeve_company_centers(count: int, half_width: float, half_depth: float, x_spacing: float, y_spacing: float) -> Array:
	var centers: Array = []
	if count <= 0:
		return centers
	var layer: int = 0
	while centers.size() < count:
		var layer_half_width: float = half_width + float(layer) * x_spacing * 1.2
		var layer_half_depth: float = half_depth + float(layer) * y_spacing * 1.2
		var layer_centers: Array = [
			Vector2(-layer_half_width, layer_half_depth),
			Vector2(layer_half_width, layer_half_depth),
			Vector2(-layer_half_width, -layer_half_depth),
			Vector2(layer_half_width, -layer_half_depth),
		]
		var front_slots: int = max(0, int(floor((layer_half_width * 2.0) / x_spacing)) - 1)
		for front_index in range(front_slots):
			var x: float = -layer_half_width + x_spacing * float(front_index + 1)
			layer_centers.append(Vector2(x, layer_half_depth))
		for rear_index in range(front_slots):
			var rear_x: float = -layer_half_width + x_spacing * float(rear_index + 1)
			layer_centers.append(Vector2(rear_x, -layer_half_depth))
		var side_slots: int = max(0, int(floor((layer_half_depth * 2.0) / y_spacing)) - 1)
		for left_index in range(side_slots):
			var left_y: float = -layer_half_depth + y_spacing * float(left_index + 1)
			layer_centers.append(Vector2(-layer_half_width, left_y))
		for right_index in range(side_slots):
			var right_y: float = -layer_half_depth + y_spacing * float(right_index + 1)
			layer_centers.append(Vector2(layer_half_width, right_y))
		for center_value in layer_centers:
			if centers.size() >= count:
				break
			centers.append(center_value)
		layer += 1
	return centers


func _get_regiment_phase_offset(regiment_data: Dictionary, period: float) -> float:
	if period <= 0.001:
		return 0.0
	var id_text: String = String(regiment_data.get("id", ""))
	var hash_value: int = 0
	for char_index in range(id_text.length()):
		hash_value = posmod(hash_value * 33 + id_text.unicode_at(char_index), 9973)
	return fposmod(float(hash_value) * 0.173, period)
