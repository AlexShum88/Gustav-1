class_name CoreV2Brigade
extends RefCounted


const WAYPOINT_ARRIVAL_RADIUS_M: float = 4.0
const HQ_REAR_OFFSET_M: float = 260.0
const ORDER_LINE_MIN_WIDTH_M: float = 70.0
const BATTALION_LINE_GAP_M: float = 34.0
const BATTALION_MIN_SLOT_WIDTH_M: float = 90.0
const BATTALION_MAX_FRONTAGE_M: float = 260.0
const BRIGADE_ROW_SPACING_M: float = 190.0
const COLUMN_ROW_SPACING_M: float = 145.0

var id: StringName = &""
var army_id: StringName = &""
var display_name: String = ""
var morale: float = 0.92
var hq_position: Vector3 = Vector3.ZERO
var hq_target_position: Vector3 = Vector3.ZERO
var hq_move_speed_mps: float = 20.0
var commander: CoreV2Commander
var battalions: Array = []
var current_order: CoreV2Order
var order_policies: Dictionary = {}
var hq_movement_path: Array = []
var is_reserve: bool = false
var reserve_cost: int = 0
var hq_health: float = 1.0
var hq_destroyed: bool = false
var hq_recent_damage: float = 0.0
var ai_next_decision_time_seconds: float = 0.0
var ai_last_focus_entity_id: StringName = &""
var ai_last_order_target: Vector3 = Vector3.ZERO


func add_battalion(battalion: CoreV2Battalion) -> void:
	if battalion == null:
		return
	battalions.append(battalion)
	battalion.brigade_id = id
	battalion.army_id = army_id


func issue_order(order: CoreV2Order, policies: Dictionary = {}, terrain_state = null) -> void:
	# Викликається лише після доставки наказу до штабу бригади.
	if hq_destroyed:
		return
	current_order = order
	order_policies = policies.duplicate(true)
	_update_hq_follow_target(terrain_state)
	var desired_formations: Dictionary = {}
	for battalion_value in battalions:
		var battalion: CoreV2Battalion = battalion_value
		desired_formations[battalion.id] = CoreV2FormationSystem.choose_formation_for_order(battalion, order, order_policies)
	var order_layout: Dictionary = _build_order_layout(order, desired_formations)
	for battalion_index in range(battalions.size()):
		var battalion: CoreV2Battalion = battalions[battalion_index]
		var slot: Dictionary = order_layout.get(battalion.id, {})
		var desired_formation: int = int(slot.get("formation_state", desired_formations.get(battalion.id, battalion.desired_formation_state)))
		var formation_slot_offset: Vector3 = slot.get("slot_offset", Vector3.ZERO)
		var battalion_facing: Vector3 = slot.get("facing", battalion.facing)
		var battalion_frontage_m: float = float(slot.get("frontage_m", battalion.desired_formation_frontage_m))
		var battalion_target: Vector3 = _project_if_possible(order.target_position + formation_slot_offset, terrain_state)
		var battalion_path: Array = _plan_entity_path(battalion.position, battalion_target, battalion.category, order, terrain_state)
		battalion.slot_offset = formation_slot_offset
		battalion.request_formation(desired_formation, battalion_frontage_m)
		battalion.set_target(battalion_target, order, battalion_path, battalion_facing)


func advance(delta: float, terrain_state = null) -> void:
	_update_hq_follow_target(terrain_state)
	_advance_hq(delta, terrain_state)
	for battalion_value in battalions:
		var battalion: CoreV2Battalion = battalion_value
		battalion.advance(delta, terrain_state)


func get_center_position() -> Vector3:
	if battalions.is_empty():
		return hq_position
	var sum: Vector3 = Vector3.ZERO
	for battalion_value in battalions:
		var battalion: CoreV2Battalion = battalion_value
		sum += battalion.position
	return sum / float(battalions.size())


func create_snapshot() -> Dictionary:
	return {
		"id": String(id),
		"army_id": String(army_id),
		"display_name": display_name,
		"morale": morale,
		"hq_position": hq_position,
		"hq_target_position": hq_target_position,
		"hq_movement_path": hq_movement_path.duplicate(true),
		"hq_health": hq_health,
		"hq_destroyed": hq_destroyed,
		"hq_recent_damage": hq_recent_damage,
		"current_order": current_order.create_snapshot() if current_order != null else {},
		"commander_name": commander.display_name if commander != null else "",
		"is_reserve": is_reserve,
		"reserve_cost": reserve_cost,
		"ai_next_decision_time_seconds": ai_next_decision_time_seconds,
		"ai_last_focus_entity_id": String(ai_last_focus_entity_id),
		"ai_last_order_target": ai_last_order_target,
	}


func _advance_hq(delta: float, terrain_state = null) -> void:
	if hq_destroyed:
		return
	var hq_2d := Vector2(hq_position.x, hq_position.z)
	var active_target: Vector3 = _get_active_hq_target()
	var target_2d := Vector2(active_target.x, active_target.z)
	var distance_to_target: float = hq_2d.distance_to(target_2d)
	if distance_to_target <= WAYPOINT_ARRIVAL_RADIUS_M:
		_arrive_hq_waypoint(terrain_state)
		return
	var speed_multiplier: float = terrain_state.get_speed_multiplier_at(hq_position, CoreV2Types.UnitCategory.HQ) if terrain_state != null else 1.0
	var movement_direction_2d: Vector2 = (target_2d - hq_2d).normalized()
	var step: float = min(distance_to_target, hq_move_speed_mps * speed_multiplier * delta)
	hq_position.x += movement_direction_2d.x * step
	hq_position.z += movement_direction_2d.y * step
	if terrain_state != null:
		hq_position.y = terrain_state.get_height_at(hq_position)


func _update_hq_follow_target(terrain_state = null) -> void:
	if hq_destroyed or battalions.is_empty():
		hq_movement_path.clear()
		return
	var brigade_center: Vector3 = get_center_position()
	var brigade_forward: Vector3 = _resolve_brigade_forward(brigade_center)
	var follow_target: Vector3 = brigade_center - brigade_forward * HQ_REAR_OFFSET_M
	hq_target_position = _project_if_possible(follow_target, terrain_state)
	hq_movement_path.clear()


func _resolve_brigade_forward(brigade_center: Vector3) -> Vector3:
	var forward_sum: Vector3 = Vector3.ZERO
	for battalion_value in battalions:
		var battalion: CoreV2Battalion = battalion_value
		if battalion.status == CoreV2Types.UnitStatus.ROUTING:
			continue
		forward_sum += battalion.facing
	if forward_sum.length_squared() > 0.0001:
		return forward_sum.normalized()
	if current_order != null:
		var order_direction: Vector3 = current_order.target_position - brigade_center
		order_direction.y = 0.0
		if order_direction.length_squared() > 0.0001:
			return order_direction.normalized()
	return Vector3.FORWARD


func _project_if_possible(position_value: Vector3, terrain_state = null) -> Vector3:
	if terrain_state == null:
		return position_value
	return terrain_state.project_position_to_terrain(position_value)


func _plan_entity_path(
		from_position: Vector3,
		to_position: Vector3,
		unit_category: int,
		order: CoreV2Order,
		terrain_state = null
) -> Array:
	if terrain_state == null or order == null:
		return []
	return terrain_state.plan_movement_path(from_position, to_position, unit_category, order.order_type, order_policies)


func _get_active_hq_target() -> Vector3:
	return hq_movement_path[0] if not hq_movement_path.is_empty() else hq_target_position


func _arrive_hq_waypoint(terrain_state = null) -> void:
	if not hq_movement_path.is_empty():
		hq_position = hq_movement_path[0]
		hq_movement_path.remove_at(0)
		if terrain_state != null:
			hq_position.y = terrain_state.get_height_at(hq_position)
		if not hq_movement_path.is_empty() or _distance_2d(hq_position, hq_target_position) > WAYPOINT_ARRIVAL_RADIUS_M:
			return
	hq_position = hq_target_position
	if terrain_state != null:
		hq_position.y = terrain_state.get_height_at(hq_position)


func _distance_2d(from_position: Vector3, to_position: Vector3) -> float:
	return Vector2(from_position.x, from_position.z).distance_to(Vector2(to_position.x, to_position.z))


func _build_order_layout(order: CoreV2Order, desired_formations: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	if order == null or battalions.is_empty():
		return result
	var brigade_center: Vector3 = get_center_position()
	var line_data: Dictionary = _resolve_order_line_data(order, brigade_center)
	var formation_center: Vector3 = line_data.get("center", order.target_position)
	var facing: Vector3 = line_data.get("facing", _resolve_brigade_forward(brigade_center))
	var side: Vector3 = _side_from_facing(facing)
	var has_explicit_line: bool = bool(line_data.get("has_explicit_line", false))
	var frontage_m: float = float(line_data.get("frontage_m", 0.0))
	if frontage_m <= 0.0 or not has_explicit_line:
		frontage_m = _estimate_auto_brigade_frontage(desired_formations)
	var columns: int = _resolve_brigade_columns(frontage_m, desired_formations, has_explicit_line)
	var rows: int = int(ceil(float(battalions.size()) / float(max(1, columns))))
	var slot_width_m: float = max(BATTALION_MIN_SLOT_WIDTH_M, frontage_m / float(max(1, columns)))
	var row_spacing_m: float = _resolve_row_spacing(desired_formations)
	for battalion_index in range(battalions.size()):
		var battalion: CoreV2Battalion = battalions[battalion_index]
		var row: int = int(floor(float(battalion_index) / float(columns)))
		var column: int = battalion_index % columns
		var lateral_offset_m: float = (float(column) - float(columns - 1) * 0.5) * slot_width_m
		var depth_offset_m: float = -float(row) * row_spacing_m if has_explicit_line else (float(rows - 1) * 0.5 - float(row)) * row_spacing_m
		var target_position: Vector3 = formation_center + side * lateral_offset_m + facing * depth_offset_m
		var formation_state: int = int(desired_formations.get(battalion.id, battalion.desired_formation_state))
		var frontage_for_battalion_m: float = _resolve_battalion_frontage_m(battalion, formation_state, slot_width_m, has_explicit_line)
		result[battalion.id] = {
			"slot_offset": target_position - order.target_position,
			"facing": facing,
			"frontage_m": frontage_for_battalion_m,
			"formation_state": formation_state,
		}
	return result


func _resolve_order_line_data(order: CoreV2Order, brigade_center: Vector3) -> Dictionary:
	var line_start: Vector3 = _get_policy_vector3("formation_line_start", Vector3.ZERO)
	var line_end: Vector3 = _get_policy_vector3("formation_line_end", Vector3.ZERO)
	var line_vector: Vector3 = line_end - line_start
	line_vector.y = 0.0
	var has_explicit_line: bool = bool(order_policies.get("flexible_formation", false)) and line_vector.length() >= ORDER_LINE_MIN_WIDTH_M
	if has_explicit_line:
		var center: Vector3 = (line_start + line_end) * 0.5
		return {
			"center": center,
			"facing": _resolve_order_facing(order, brigade_center, line_start, line_end),
			"frontage_m": line_vector.length(),
			"has_explicit_line": true,
		}
	return {
		"center": order.target_position,
		"facing": _resolve_order_facing(order, brigade_center, line_start, line_end),
		"frontage_m": 0.0,
		"has_explicit_line": false,
	}


func _resolve_order_facing(order: CoreV2Order, brigade_center: Vector3, line_start: Vector3, line_end: Vector3) -> Vector3:
	var policy_facing: Vector3 = _get_policy_vector3("formation_facing", Vector3.ZERO)
	policy_facing.y = 0.0
	if policy_facing.length_squared() > 0.001:
		return policy_facing.normalized()
	var line_vector: Vector3 = line_end - line_start
	line_vector.y = 0.0
	if line_vector.length() >= ORDER_LINE_MIN_WIDTH_M:
		var line_axis_2d := Vector2(line_vector.x, line_vector.z).normalized()
		var first_normal := Vector2(-line_axis_2d.y, line_axis_2d.x)
		var line_center: Vector3 = (line_start + line_end) * 0.5
		var to_line := Vector2(line_center.x - brigade_center.x, line_center.z - brigade_center.z)
		if to_line.length_squared() > 0.001 and first_normal.dot(to_line.normalized()) < 0.0:
			first_normal = -first_normal
		return Vector3(first_normal.x, 0.0, first_normal.y).normalized()
	var order_direction: Vector3 = order.target_position - brigade_center if order != null else Vector3.ZERO
	order_direction.y = 0.0
	if order_direction.length_squared() > 0.001:
		return order_direction.normalized()
	return _resolve_brigade_forward(brigade_center)


func _estimate_auto_brigade_frontage(desired_formations: Dictionary) -> float:
	if battalions.is_empty():
		return BATTALION_MIN_SLOT_WIDTH_M
	if desired_formations.is_empty():
		return max(BATTALION_MIN_SLOT_WIDTH_M, float(battalions.size()) * BATTALION_MIN_SLOT_WIDTH_M)
	if _all_formations_prefer_depth(desired_formations):
		return BATTALION_MIN_SLOT_WIDTH_M * float(min(2, battalions.size()))
	var frontage_m: float = 0.0
	for battalion_value in battalions:
		var battalion: CoreV2Battalion = battalion_value
		var formation_state: int = int(desired_formations.get(battalion.id, battalion.desired_formation_state))
		frontage_m += _default_battalion_frontage_m(battalion, formation_state)
	frontage_m += BATTALION_LINE_GAP_M * float(max(0, battalions.size() - 1))
	return max(BATTALION_MIN_SLOT_WIDTH_M, frontage_m)


func _resolve_brigade_columns(frontage_m: float, desired_formations: Dictionary, has_explicit_line: bool) -> int:
	var battalion_count: int = max(1, battalions.size())
	if not has_explicit_line:
		if _all_formations_prefer_depth(desired_formations):
			return min(2, battalion_count)
		return battalion_count
	var columns: int = int(floor(max(BATTALION_MIN_SLOT_WIDTH_M, frontage_m) / BATTALION_MIN_SLOT_WIDTH_M))
	return int(clamp(columns, 1, battalion_count))


func _resolve_battalion_frontage_m(
		battalion: CoreV2Battalion,
		formation_state: int,
		slot_width_m: float,
		has_explicit_line: bool
) -> float:
	var default_frontage_m: float = _default_battalion_frontage_m(battalion, formation_state)
	if _formation_prefers_depth(formation_state):
		return default_frontage_m
	if not has_explicit_line:
		return default_frontage_m
	var available_frontage_m: float = max(CoreV2FormationSystem.MIN_FLEX_FRONTAGE_M, slot_width_m - BATTALION_LINE_GAP_M)
	return clamp(available_frontage_m, CoreV2FormationSystem.MIN_FLEX_FRONTAGE_M, BATTALION_MAX_FRONTAGE_M)


func _default_battalion_frontage_m(battalion: CoreV2Battalion, formation_state: int) -> float:
	if battalion == null:
		return BATTALION_MIN_SLOT_WIDTH_M
	match formation_state:
		CoreV2Types.FormationState.MARCH_COLUMN:
			return 52.0
		CoreV2Types.FormationState.COLUMN:
			return 82.0
		CoreV2Types.FormationState.DEFENSIVE:
			return 112.0
		CoreV2Types.FormationState.TERCIA:
			return 136.0
		_:
			if battalion.category == CoreV2Types.UnitCategory.CAVALRY:
				return clamp(float(max(4, battalion.sprite_count - 1)) * CoreV2FormationSystem.SPRITE_SPACING_M * 1.15, 120.0, BATTALION_MAX_FRONTAGE_M)
			if battalion.category == CoreV2Types.UnitCategory.ARTILLERY:
				return clamp(float(max(1, battalion.sprite_count - 1)) * CoreV2FormationSystem.SPRITE_SPACING_M * 1.4, 92.0, BATTALION_MAX_FRONTAGE_M)
			return clamp(float(max(6, battalion.sprite_count - 1)) * CoreV2FormationSystem.SPRITE_SPACING_M, 110.0, BATTALION_MAX_FRONTAGE_M)


func _resolve_row_spacing(desired_formations: Dictionary) -> float:
	return COLUMN_ROW_SPACING_M if _all_formations_prefer_depth(desired_formations) else BRIGADE_ROW_SPACING_M


func _all_formations_prefer_depth(desired_formations: Dictionary) -> bool:
	if desired_formations.is_empty():
		return false
	for formation_state_value in desired_formations.values():
		if not _formation_prefers_depth(int(formation_state_value)):
			return false
	return true


func _formation_prefers_depth(formation_state: int) -> bool:
	return formation_state == CoreV2Types.FormationState.COLUMN or formation_state == CoreV2Types.FormationState.MARCH_COLUMN


func _side_from_facing(facing_value: Vector3) -> Vector3:
	var forward: Vector3 = facing_value
	forward.y = 0.0
	if forward.length_squared() <= 0.001:
		forward = Vector3.FORWARD
	forward = forward.normalized()
	return Vector3(-forward.z, 0.0, forward.x).normalized()


func _get_policy_vector3(key: String, fallback: Vector3) -> Vector3:
	var value = order_policies.get(key, fallback)
	if value is Vector3:
		var vector_value: Vector3 = value
		return vector_value
	return fallback
