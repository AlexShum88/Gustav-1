class_name BrigadeFormationPlannerSystem
extends RefCounted


func tick(sim: BattleSimulation, delta: float) -> void:
	for brigade_value in sim.brigades.values():
		var brigade: Brigade = brigade_value
		_plan_brigade(sim, brigade, delta)


func _plan_brigade(sim: BattleSimulation, brigade: Brigade, delta: float) -> void:
	var regiments: Array = _get_active_regiments(sim, brigade)
	if regiments.is_empty():
		return
	if _should_hold_initial_positions(brigade):
		_preserve_current_positions(regiments)
		return
	var anchor: Vector2 = sim.get_brigade_anchor_position(brigade)
	var objective: Vector2 = _get_brigade_objective(brigade, anchor)
	var direction: Vector2 = _get_planning_direction(sim, brigade, anchor, objective)
	var lateral: Vector2 = Vector2(-direction.y, direction.x)
	_update_brigade_threat_assessment(sim, brigade, anchor, direction)
	_assign_regiment_roles(sim, brigade, regiments, anchor, direction)
	brigade.formation_facing = direction.angle()
	brigade.frontage_width = _get_frontage_width(regiments)
	brigade.depth_spacing = _get_depth_spacing(brigade)
	_apply_regiment_slots(sim, brigade, regiments, objective, direction, lateral)
	_apply_orientation(regiments, direction, delta)


func _should_hold_initial_positions(brigade: Brigade) -> bool:
	return brigade.current_order_id == &"" \
		and brigade.current_order_type == SimTypes.OrderType.HOLD \
		and not _has_line_order(brigade) \
		and brigade.order_path_points.is_empty() \
		and brigade.target_position == Vector2.ZERO


func _preserve_current_positions(regiments: Array) -> void:
	for regiment_value in regiments:
		var regiment: Battalion = regiment_value
		regiment.current_target_position = regiment.position


func _get_active_regiments(sim: BattleSimulation, brigade: Brigade) -> Array:
	var result: Array = []
	for regiment_id in brigade.regiment_ids:
		var regiment: Battalion = sim.regiments.get(regiment_id)
		if regiment == null or regiment.is_destroyed:
			continue
		result.append(regiment)
	return result


func _get_brigade_objective(brigade: Brigade, anchor: Vector2) -> Vector2:
	if brigade.current_order_type in [SimTypes.OrderType.DEFEND, SimTypes.OrderType.HOLD] and _has_line_order(brigade):
		return (brigade.order_line_start + brigade.order_line_end) * 0.5
	if brigade.order_path_points.size() >= 2:
		return brigade.order_path_points[brigade.order_path_points.size() - 1]
	if brigade.target_position != Vector2.ZERO:
		return brigade.target_position
	return anchor


func _get_planning_direction(sim: BattleSimulation, brigade: Brigade, anchor: Vector2, objective: Vector2) -> Vector2:
	var threat_vector: Vector2 = _get_threat_vector(sim, brigade, anchor)
	if threat_vector.length() > 24.0:
		var threat_direction: Vector2 = threat_vector.normalized()
		var objective_direction_hint: Vector2 = (objective - anchor).normalized() if objective.distance_to(anchor) > 8.0 else threat_direction
		var lateral_pressure: float = absf(threat_direction.dot(Vector2(-objective_direction_hint.y, objective_direction_hint.x)))
		if lateral_pressure >= 0.72:
			return threat_direction
	if brigade.current_order_type in [SimTypes.OrderType.MOVE, SimTypes.OrderType.MARCH, SimTypes.OrderType.ATTACK, SimTypes.OrderType.PATROL] and brigade.order_path_points.size() >= 2:
		var path_start: Vector2 = brigade.order_path_points[0]
		var path_end: Vector2 = brigade.order_path_points[brigade.order_path_points.size() - 1]
		var path_direction: Vector2 = path_end - path_start
		if path_direction.length() > 8.0:
			return path_direction.normalized()
	if brigade.current_order_type in [SimTypes.OrderType.DEFEND, SimTypes.OrderType.HOLD] and _has_line_order(brigade):
		var line_direction: Vector2 = brigade.order_line_end - brigade.order_line_start
		if line_direction.length() > 8.0:
			var line_normal: Vector2 = Vector2(-line_direction.y, line_direction.x).normalized()
			var nearest_enemy_for_line: Battalion = _find_nearest_enemy_to_brigade(sim, brigade, (brigade.order_line_start + brigade.order_line_end) * 0.5)
			if nearest_enemy_for_line != null:
				var to_enemy: Vector2 = nearest_enemy_for_line.position - (brigade.order_line_start + brigade.order_line_end) * 0.5
				if to_enemy.dot(line_normal) < 0.0:
					line_normal = -line_normal
			return line_normal
	var nearest_enemy: Battalion = _find_nearest_enemy_to_brigade(sim, brigade, anchor)
	if nearest_enemy != null:
		var enemy_direction: Vector2 = nearest_enemy.position - anchor
		if enemy_direction.length() > 8.0:
			return enemy_direction.normalized()
	var objective_direction: Vector2 = objective - anchor
	if objective_direction.length() > 8.0:
		return objective_direction.normalized()
	if absf(brigade.formation_facing) > 0.001:
		return Vector2.RIGHT.rotated(brigade.formation_facing)
	return Vector2.UP


func _apply_regiment_slots(sim: BattleSimulation, brigade: Brigade, regiments: Array, objective: Vector2, direction: Vector2, lateral: Vector2) -> void:
	if brigade.current_order_type in [SimTypes.OrderType.MOVE, SimTypes.OrderType.MARCH] and brigade.order_policies.get("road_column", false):
		_assign_column_slots(regiments, objective, direction)
		return
	if brigade.current_order_type in [SimTypes.OrderType.DEFEND, SimTypes.OrderType.HOLD] and _has_line_order(brigade):
		_assign_line_order_slots(sim, brigade, regiments)
		return
	var role_groups: Dictionary = _group_regiments_by_role(regiments)
	var front_line: Array = []
	front_line.append_array(role_groups.get(SimTypes.BrigadeRole.LEFT_FLANK, []))
	front_line.append_array(role_groups.get(SimTypes.BrigadeRole.CENTER, []))
	front_line.append_array(role_groups.get(SimTypes.BrigadeRole.RIGHT_FLANK, []))
	var rear_line: Array = []
	rear_line.append_array(role_groups.get(SimTypes.BrigadeRole.RESERVE, []))
	rear_line.append_array(role_groups.get(SimTypes.BrigadeRole.SUPPORT_ARTILLERY, []))
	if front_line.is_empty() and not rear_line.is_empty():
		var first_rear: Battalion = rear_line.pop_front()
		first_rear.brigade_role = SimTypes.BrigadeRole.CENTER
		front_line.append(first_rear)
	_assign_role_based_line_slots(brigade, role_groups, objective, direction, lateral)
	_assign_support_slots(brigade, role_groups, objective, direction, lateral)


func _assign_column_slots(regiments: Array, objective: Vector2, direction: Vector2) -> void:
	var ordered_regiments: Array = _sort_regiments_for_line(regiments)
	var interval: float = _get_interval(regiments) * 1.18
	for index in range(ordered_regiments.size()):
		var regiment: Battalion = ordered_regiments[index]
		regiment.current_target_position = objective - direction * float(index) * interval


func _assign_line_order_slots(sim: BattleSimulation, brigade: Brigade, regiments: Array) -> void:
	var role_groups: Dictionary = _group_regiments_by_role(regiments)
	var front_line: Array = []
	front_line.append_array(role_groups.get(SimTypes.BrigadeRole.LEFT_FLANK, []))
	front_line.append_array(role_groups.get(SimTypes.BrigadeRole.CENTER, []))
	front_line.append_array(role_groups.get(SimTypes.BrigadeRole.RIGHT_FLANK, []))
	var rear_line: Array = []
	rear_line.append_array(role_groups.get(SimTypes.BrigadeRole.RESERVE, []))
	rear_line.append_array(role_groups.get(SimTypes.BrigadeRole.SUPPORT_ARTILLERY, []))
	if front_line.is_empty() and not rear_line.is_empty():
		var first_rear: Battalion = rear_line.pop_front()
		first_rear.brigade_role = SimTypes.BrigadeRole.CENTER
		front_line.append(first_rear)
	_assign_line_order_front_slots(brigade, role_groups)
	var line_direction: Vector2 = (brigade.order_line_end - brigade.order_line_start).normalized()
	var line_normal: Vector2 = Vector2(-line_direction.y, line_direction.x).normalized()
	var line_center: Vector2 = (brigade.order_line_start + brigade.order_line_end) * 0.5
	var nearest_enemy: Battalion = _find_nearest_enemy_to_brigade(sim, brigade, line_center)
	if nearest_enemy != null and (nearest_enemy.position - line_center).dot(line_normal) < 0.0:
		line_normal = -line_normal
	_assign_support_line_order_slots(brigade, role_groups, line_center, line_direction, line_normal)


func _assign_along_segment(regiments: Array, line_start: Vector2, line_end: Vector2, depth_offset: Vector2) -> void:
	var count: int = regiments.size()
	if count == 0:
		return
	var ordered_regiments: Array = _sort_regiments_for_line(regiments)
	var line_direction: Vector2 = (line_end - line_start).normalized()
	var segment_length: float = line_start.distance_to(line_end)
	var segment_padding: float = min(segment_length * 0.18, max(28.0, _get_interval(regiments) * 0.32))
	var start_point: Vector2 = line_start + line_direction * segment_padding + depth_offset
	var end_point: Vector2 = line_end - line_direction * segment_padding + depth_offset
	if count == 1:
		var single_regiment: Battalion = ordered_regiments[0]
		single_regiment.current_target_position = (start_point + end_point) * 0.5
		return
	for index in range(count):
		var regiment: Battalion = ordered_regiments[index]
		var t: float = float(index) / float(count - 1)
		regiment.current_target_position = start_point.lerp(end_point, t)


func _assign_line_slots(regiments: Array, center: Vector2, lateral: Vector2, depth_offset: Vector2) -> void:
	var count: int = regiments.size()
	if count == 0:
		return
	var interval: float = _get_interval(regiments)
	var ordered_regiments: Array = _sort_regiments_for_line(regiments)
	for index in range(count):
		var regiment: Battalion = ordered_regiments[index]
		var lateral_index: float = float(index) - float(count - 1) * 0.5
		regiment.current_target_position = center + depth_offset + lateral * lateral_index * interval


func _assign_role_based_line_slots(brigade: Brigade, role_groups: Dictionary, center: Vector2, direction: Vector2, lateral: Vector2) -> void:
	var interval: float = _get_interval(_collect_regiments_from_groups(role_groups))
	var left_flank: Array = role_groups.get(SimTypes.BrigadeRole.LEFT_FLANK, [])
	var centers: Array = role_groups.get(SimTypes.BrigadeRole.CENTER, [])
	var right_flank: Array = role_groups.get(SimTypes.BrigadeRole.RIGHT_FLANK, [])
	_assign_line_slots(centers, center, lateral, Vector2.ZERO)
	for index in range(left_flank.size()):
		var regiment: Battalion = left_flank[index]
		var depth_bias: float = 0.0 if brigade.reserve_committed else float(index % 2) * 0.18
		regiment.current_target_position = center - lateral * interval * (float(centers.size()) * 0.5 + 1.12 + float(index)) - direction * brigade.depth_spacing * depth_bias
	for index in range(right_flank.size()):
		var regiment: Battalion = right_flank[index]
		var depth_bias: float = 0.0 if brigade.reserve_committed else float(index % 2) * 0.18
		regiment.current_target_position = center + lateral * interval * (float(centers.size()) * 0.5 + 1.12 + float(index)) - direction * brigade.depth_spacing * depth_bias


func _assign_support_slots(brigade: Brigade, role_groups: Dictionary, center: Vector2, direction: Vector2, lateral: Vector2) -> void:
	var reserves: Array = role_groups.get(SimTypes.BrigadeRole.RESERVE, [])
	var artillery: Array = role_groups.get(SimTypes.BrigadeRole.SUPPORT_ARTILLERY, [])
	if not reserves.is_empty():
		var reserve_center: Vector2 = center - direction * brigade.depth_spacing
		if brigade.reserve_committed and brigade.threatened_flank != 0:
			reserve_center += lateral * float(brigade.threatened_flank) * max(60.0, brigade.frontage_width * 0.22)
		_assign_line_slots(reserves, reserve_center, lateral, Vector2.ZERO)
	if not artillery.is_empty():
		_assign_line_slots(artillery, center, lateral, -direction * brigade.depth_spacing * 1.7)


func _assign_support_line_order_slots(brigade: Brigade, role_groups: Dictionary, line_center: Vector2, line_direction: Vector2, line_normal: Vector2) -> void:
	var reserves: Array = role_groups.get(SimTypes.BrigadeRole.RESERVE, [])
	var artillery: Array = role_groups.get(SimTypes.BrigadeRole.SUPPORT_ARTILLERY, [])
	if not reserves.is_empty():
		var flank_shift: Vector2 = line_direction * brigade.frontage_width * 0.24 * float(brigade.threatened_flank) if brigade.reserve_committed and brigade.threatened_flank != 0 else Vector2.ZERO
		var reserve_start: Vector2 = line_center - line_direction * brigade.frontage_width * 0.18 - line_normal * brigade.depth_spacing + flank_shift
		var reserve_end: Vector2 = line_center + line_direction * brigade.frontage_width * 0.18 - line_normal * brigade.depth_spacing + flank_shift
		_assign_along_segment(reserves, reserve_start, reserve_end, Vector2.ZERO)
	if not artillery.is_empty():
		var artillery_start: Vector2 = line_center - line_direction * brigade.frontage_width * 0.16 - line_normal * brigade.depth_spacing * 1.7
		var artillery_end: Vector2 = line_center + line_direction * brigade.frontage_width * 0.16 - line_normal * brigade.depth_spacing * 1.7
		_assign_along_segment(artillery, artillery_start, artillery_end, Vector2.ZERO)


func _assign_line_order_front_slots(brigade: Brigade, role_groups: Dictionary) -> void:
	var line_direction: Vector2 = (brigade.order_line_end - brigade.order_line_start).normalized()
	var left_flank: Array = role_groups.get(SimTypes.BrigadeRole.LEFT_FLANK, [])
	var centers: Array = role_groups.get(SimTypes.BrigadeRole.CENTER, [])
	var right_flank: Array = role_groups.get(SimTypes.BrigadeRole.RIGHT_FLANK, [])
	var line_start: Vector2 = brigade.order_line_start
	var line_end: Vector2 = brigade.order_line_end
	var line_length: float = line_start.distance_to(line_end)
	if line_length <= 1.0:
		return
	var center_bias: float = 0.5
	if brigade.threatened_flank < 0:
		center_bias = 0.34
	elif brigade.threatened_flank > 0:
		center_bias = 0.66
	var center_span: float = clamp(line_length * 0.42, line_length * 0.28, line_length * 0.56)
	var center_center: Vector2 = line_start.lerp(line_end, center_bias)
	var center_start: Vector2 = center_center - line_direction * center_span * 0.5
	var center_end: Vector2 = center_center + line_direction * center_span * 0.5
	var left_start: Vector2 = line_start
	var left_end: Vector2 = center_start
	var right_start: Vector2 = center_end
	var right_end: Vector2 = line_end
	if brigade.threatened_flank < 0:
		left_end = center_end
		right_start = center_end
	elif brigade.threatened_flank > 0:
		right_start = center_start
		left_end = center_start
	_assign_along_segment(left_flank, left_start, left_end, Vector2.ZERO)
	_assign_along_segment(centers, center_start, center_end, Vector2.ZERO)
	_assign_along_segment(right_flank, right_start, right_end, Vector2.ZERO)


func _sort_regiments_for_line(regiments: Array) -> Array:
	var infantry: Array = []
	var cavalry: Array = []
	var artillery: Array = []
	for regiment_value in regiments:
		var regiment: Battalion = regiment_value
		match regiment.category:
			SimTypes.UnitCategory.CAVALRY:
				cavalry.append(regiment)
			SimTypes.UnitCategory.ARTILLERY:
				artillery.append(regiment)
			_:
				infantry.append(regiment)
	var ordered: Array = []
	for regiment_value in infantry:
		ordered.append(regiment_value)
	if not cavalry.is_empty():
		ordered = _interleave_flanks(ordered, cavalry)
	for regiment_value in artillery:
		ordered.append(regiment_value)
	return ordered


func _assign_regiment_roles(sim: BattleSimulation, brigade: Brigade, regiments: Array, anchor: Vector2, _direction: Vector2) -> void:
	brigade.front_is_collapsed = _is_front_collapsing(regiments)
	brigade.reforming_line = _should_reform_line(regiments)
	var artillery: Array = []
	var cavalry: Array = []
	var infantry: Array = []
	for regiment_value in regiments:
		var regiment: Battalion = regiment_value
		match regiment.category:
			SimTypes.UnitCategory.ARTILLERY:
				artillery.append(regiment)
			SimTypes.UnitCategory.CAVALRY:
				cavalry.append(regiment)
			_:
				infantry.append(regiment)
	for regiment_value in artillery:
		var artillery_regiment: Battalion = regiment_value
		artillery_regiment.brigade_role = SimTypes.BrigadeRole.SUPPORT_ARTILLERY

	var reserve_candidates: Array = []
	var reserve_count: int = _get_desired_reserve_count(brigade, regiments)
	if reserve_count > 0:
		reserve_candidates = _pick_reserve_candidates(infantry, cavalry, reserve_count)
	if not reserve_candidates.is_empty():
		brigade.reserve_committed = _should_commit_reserve(sim, brigade, anchor, reserve_candidates[0])
	else:
		brigade.reserve_committed = false

	for regiment_value in infantry:
		var infantry_regiment: Battalion = regiment_value
		infantry_regiment.brigade_role = SimTypes.BrigadeRole.CENTER
	for regiment_value in cavalry:
		var cavalry_regiment: Battalion = regiment_value
		cavalry_regiment.brigade_role = SimTypes.BrigadeRole.CENTER

	if not brigade.reserve_committed:
		for reserve_value in reserve_candidates:
			var reserve_regiment: Battalion = reserve_value
			reserve_regiment.brigade_role = SimTypes.BrigadeRole.RESERVE

	var flank_candidates: Array = []
	for regiment_value in cavalry:
		var cavalry_regiment: Battalion = regiment_value
		if not reserve_candidates.has(cavalry_regiment) or brigade.reserve_committed:
			flank_candidates.append(cavalry_regiment)
	if flank_candidates.is_empty() and infantry.size() >= 3:
		flank_candidates.append(infantry.front())
		flank_candidates.append(infantry.back())

	if flank_candidates.size() >= 1:
		var left_regiment: Battalion = flank_candidates[0]
		if not reserve_candidates.has(left_regiment) or brigade.reserve_committed:
			left_regiment.brigade_role = SimTypes.BrigadeRole.LEFT_FLANK
	if flank_candidates.size() >= 2:
		var right_regiment: Battalion = flank_candidates[1]
		if not reserve_candidates.has(right_regiment) or brigade.reserve_committed:
			right_regiment.brigade_role = SimTypes.BrigadeRole.RIGHT_FLANK

	if brigade.front_is_collapsed and not reserve_candidates.is_empty():
		brigade.reserve_committed = true
		for reserve_value in reserve_candidates:
			var reserve_regiment: Battalion = reserve_value
			if reserve_regiment.category == SimTypes.UnitCategory.ARTILLERY:
				reserve_regiment.brigade_role = SimTypes.BrigadeRole.SUPPORT_ARTILLERY
			elif brigade.threatened_flank < 0:
				reserve_regiment.brigade_role = SimTypes.BrigadeRole.LEFT_FLANK
			elif brigade.threatened_flank > 0:
				reserve_regiment.brigade_role = SimTypes.BrigadeRole.RIGHT_FLANK
			else:
				reserve_regiment.brigade_role = SimTypes.BrigadeRole.CENTER
	_rebalance_front_roles_for_threat(brigade, infantry, cavalry, reserve_candidates)


func _pick_reserve_candidates(infantry: Array, cavalry: Array, reserve_count: int) -> Array:
	var candidates: Array = []
	for regiment_value in infantry:
		candidates.append(regiment_value)
	if candidates.is_empty():
		for regiment_value in cavalry:
			candidates.append(regiment_value)
	candidates.sort_custom(func(a: Battalion, b: Battalion) -> bool:
		var score_a: float = a.commander_quality + float(a.get_total_strength()) * 0.001 - a.fatigue * 0.5
		var score_b: float = b.commander_quality + float(b.get_total_strength()) * 0.001 - b.fatigue * 0.5
		return score_a > score_b
	)
	var result: Array = []
	for index in range(min(reserve_count, candidates.size())):
		result.append(candidates[index])
	return result


func _get_desired_reserve_count(brigade: Brigade, regiments: Array) -> int:
	var reserve_count: int = 0
	if brigade.order_policies.get("hold_reserve", false):
		reserve_count = 1
	if brigade.current_order_type in [SimTypes.OrderType.DEFEND, SimTypes.OrderType.HOLD] and _has_line_order(brigade):
		var line_length: float = brigade.order_line_start.distance_to(brigade.order_line_end)
		var interval: float = _get_interval(regiments)
		var full_line_requirement: float = interval * float(max(0, regiments.size() - 1))
		if line_length < full_line_requirement * 0.92:
			reserve_count = max(reserve_count, 1)
		if line_length < full_line_requirement * 0.76:
			reserve_count = max(reserve_count, 2)
	return min(reserve_count, max(0, regiments.size() - 1))


func _should_commit_reserve(sim: BattleSimulation, brigade: Brigade, anchor: Vector2, reserve_regiment: Battalion) -> bool:
	if brigade.current_order_type == SimTypes.OrderType.ATTACK:
		var nearest_enemy: Battalion = _find_nearest_enemy_to_brigade(sim, brigade, anchor)
		if nearest_enemy != null and anchor.distance_to(nearest_enemy.position) <= 150.0:
			return true
	if brigade.front_is_collapsed:
		return true
	if brigade.threatened_flank != 0:
		return true
	if reserve_regiment.fatigue > 0.82:
		return true
	return false


func _is_front_collapsing(regiments: Array) -> bool:
	return false


func _should_reform_line(regiments: Array) -> bool:
	return regiments.size() >= 2


func _group_regiments_by_role(regiments: Array) -> Dictionary:
	var groups: Dictionary = {
		SimTypes.BrigadeRole.LEFT_FLANK: [],
		SimTypes.BrigadeRole.CENTER: [],
		SimTypes.BrigadeRole.RIGHT_FLANK: [],
		SimTypes.BrigadeRole.RESERVE: [],
		SimTypes.BrigadeRole.SUPPORT_ARTILLERY: [],
	}
	for regiment_value in regiments:
		var regiment: Battalion = regiment_value
		groups[regiment.brigade_role].append(regiment)
	return groups


func _collect_regiments_from_groups(role_groups: Dictionary) -> Array:
	var result: Array = []
	for role_key in role_groups.keys():
		for regiment_value in role_groups[role_key]:
			result.append(regiment_value)
	return result


func _interleave_flanks(center_regiments: Array, flank_regiments: Array) -> Array:
	var result: Array = center_regiments.duplicate()
	for index in range(flank_regiments.size()):
		if index % 2 == 0:
			result.push_front(flank_regiments[index])
		else:
			result.push_back(flank_regiments[index])
	return result


func _get_interval(regiments: Array) -> float:
	var widest: float = 72.0
	for regiment_value in regiments:
		var regiment: Battalion = regiment_value
		widest = max(widest, max(regiment.formation.frontage, regiment.formation.depth))
	return widest * 1.72


func _get_frontage_width(regiments: Array) -> float:
	var count: int = regiments.size()
	if count <= 1:
		return 90.0
	return _get_interval(regiments) * float(count - 1)


func _get_depth_spacing(brigade: Brigade) -> float:
	match brigade.current_order_type:
		SimTypes.OrderType.MARCH:
			return 132.0
		SimTypes.OrderType.DEFEND:
			return 162.0
		_:
			return 146.0


func _apply_orientation(regiments: Array, direction: Vector2, delta: float) -> void:
	var desired_angle: float = direction.angle() + PI * 0.5
	var rotation_speed: float = clamp(delta * 5.0, 0.0, 1.0)
	for regiment_value in regiments:
		var regiment: Battalion = regiment_value
		regiment.formation.orientation = lerp_angle(regiment.formation.orientation, desired_angle, rotation_speed)


func _find_nearest_enemy_to_brigade(sim: BattleSimulation, brigade: Brigade, anchor: Vector2) -> Battalion:
	var best_regiment: Battalion = null
	var best_distance: float = INF
	for regiment_value in sim.regiments.values():
		var regiment: Battalion = regiment_value
		if regiment.army_id == brigade.army_id or regiment.is_destroyed:
			continue
		var distance: float = anchor.distance_to(regiment.position)
		if distance < best_distance:
			best_distance = distance
			best_regiment = regiment
	return best_regiment


func _has_line_order(brigade: Brigade) -> bool:
	return brigade.order_line_start.distance_to(brigade.order_line_end) > 16.0


func _rebalance_front_roles_for_threat(brigade: Brigade, infantry: Array, cavalry: Array, reserve_candidates: Array) -> void:
	if brigade.threatened_flank == 0:
		return
	var movable: Array = []
	for regiment_value in cavalry:
		var regiment: Battalion = regiment_value
		if reserve_candidates.has(regiment):
			continue
		movable.append(regiment)
	for regiment_value in infantry:
		var regiment: Battalion = regiment_value
		if reserve_candidates.has(regiment):
			continue
		movable.append(regiment)
	var desired_role: int = SimTypes.BrigadeRole.LEFT_FLANK if brigade.threatened_flank < 0 else SimTypes.BrigadeRole.RIGHT_FLANK
	var opposite_role: int = SimTypes.BrigadeRole.RIGHT_FLANK if brigade.threatened_flank < 0 else SimTypes.BrigadeRole.LEFT_FLANK
	var current_flank_count: int = 0
	for regiment_value in movable:
		var regiment: Battalion = regiment_value
		if regiment.brigade_role == desired_role:
			current_flank_count += 1
	if current_flank_count >= 2:
		return
	for regiment_value in movable:
		var regiment: Battalion = regiment_value
		if regiment.brigade_role == opposite_role:
			regiment.brigade_role = desired_role
			return
	for regiment_value in movable:
		var regiment: Battalion = regiment_value
		if regiment.brigade_role == SimTypes.BrigadeRole.CENTER:
			regiment.brigade_role = desired_role
			return


func _update_brigade_threat_assessment(sim: BattleSimulation, brigade: Brigade, anchor: Vector2, direction: Vector2) -> void:
	var threat_vector: Vector2 = _get_threat_vector(sim, brigade, anchor)
	brigade.threatened_flank = 0
	if threat_vector.length() <= 8.0:
		return
	var lateral: Vector2 = Vector2(-direction.y, direction.x)
	var lateral_pressure: float = threat_vector.normalized().dot(lateral)
	if lateral_pressure <= -0.45:
		brigade.threatened_flank = -1
	elif lateral_pressure >= 0.45:
		brigade.threatened_flank = 1


func _get_threat_vector(sim: BattleSimulation, brigade: Brigade, anchor: Vector2) -> Vector2:
	var threat: Vector2 = Vector2.ZERO
	for regiment_value in sim.regiments.values():
		var regiment: Battalion = regiment_value
		if regiment.army_id == brigade.army_id or regiment.is_destroyed:
			continue
		var offset: Vector2 = regiment.position - anchor
		var distance: float = offset.length()
		if distance > 320.0 or distance <= 0.001:
			continue
		var weight: float = 1.0 - distance / 320.0
		threat += offset.normalized() * weight
	return threat
