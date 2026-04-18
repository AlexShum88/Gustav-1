class_name CoreV2FormationSeparationSystem
extends RefCounted


const ITERATIONS: int = 2
const FOOTPRINT_PADDING_M: float = 9.0
const MIN_CAPSULE_RADIUS_M: float = 16.0
const MAX_PUSH_PER_PAIR_M: float = 12.0
const MAX_PUSH_PER_TICK_M: float = 24.0
const ENEMY_PUSH_STRENGTH: float = 1.0
const FRIENDLY_PUSH_STRENGTH: float = 0.35


static func update_formation_separation(state: CoreV2BattleState, delta: float) -> void:
	if state == null or delta <= 0.0:
		return
	var battalions: Array = _collect_battalions(state)
	if battalions.size() < 2:
		return
	for battalion_value in battalions:
		var battalion: CoreV2Battalion = battalion_value
		battalion.separation_contacts = 0
		battalion.separation_push_m = 0.0
	for _iteration in range(ITERATIONS):
		var footprints: Dictionary = _build_footprints(state, battalions)
		var pushes: Dictionary = {}
		for first_index in range(battalions.size()):
			var first: CoreV2Battalion = battalions[first_index]
			var first_footprint: Dictionary = footprints.get(first.id, {})
			if first_footprint.is_empty():
				continue
			for second_index in range(first_index + 1, battalions.size()):
				var second: CoreV2Battalion = battalions[second_index]
				if _should_ignore_pair(first, second):
					continue
				var second_footprint: Dictionary = footprints.get(second.id, {})
				if second_footprint.is_empty():
					continue
				var push_data: Dictionary = _resolve_pair_push(first_footprint, second_footprint)
				if push_data.is_empty():
					continue
				_accumulate_pair_push(pushes, first, second, push_data)
		_apply_pushes(state, battalions, pushes)


static func _collect_battalions(state: CoreV2BattleState) -> Array:
	var result: Array = []
	for battalion_value in state.get_all_battalions():
		var battalion: CoreV2Battalion = battalion_value
		if battalion == null or battalion.status == CoreV2Types.UnitStatus.STAGING:
			continue
		if battalion.soldiers_total <= 0 or battalion.sprite_count <= 0:
			continue
		battalion.ensure_formation_ready()
		battalion.sync_sprite_blocks(state)
		result.append(battalion)
	return result


static func _should_ignore_pair(first: CoreV2Battalion, second: CoreV2Battalion) -> bool:
	return first.army_id == second.army_id and first.brigade_id == second.brigade_id


static func _build_footprints(state: CoreV2BattleState, battalions: Array) -> Dictionary:
	var result: Dictionary = {}
	for battalion_value in battalions:
		var battalion: CoreV2Battalion = battalion_value
		result[battalion.id] = _build_footprint(state, battalion)
	return result


static func _build_footprint(state: CoreV2BattleState, battalion: CoreV2Battalion) -> Dictionary:
	if battalion.sprite_offsets.is_empty():
		return {}
	var min_x: float = INF
	var max_x: float = -INF
	var min_z: float = INF
	var max_z: float = -INF
	for offset_value in battalion.sprite_offsets:
		var offset: Vector3 = offset_value
		min_x = min(min_x, offset.x)
		max_x = max(max_x, offset.x)
		min_z = min(min_z, offset.z)
		max_z = max(max_z, offset.z)
	var facing: Vector3 = battalion.facing
	if facing.length_squared() <= 0.0001:
		facing = Vector3.FORWARD
	facing = facing.normalized()
	var side := Vector3(-facing.z, 0.0, facing.x).normalized()
	var half_width: float = max(FOOTPRINT_PADDING_M, (max_x - min_x) * 0.5 + FOOTPRINT_PADDING_M)
	var capsule_radius: float = max(MIN_CAPSULE_RADIUS_M, (max_z - min_z) * 0.5 + FOOTPRINT_PADDING_M)
	var local_center := Vector3((min_x + max_x) * 0.5, 0.0, (min_z + max_z) * 0.5)
	var center: Vector3 = battalion.position + side * local_center.x + facing * local_center.z
	center.y = state.get_height_at(center)
	var start_2d := Vector2(center.x - side.x * half_width, center.z - side.z * half_width)
	var end_2d := Vector2(center.x + side.x * half_width, center.z + side.z * half_width)
	return {
		"battalion": battalion,
		"center": Vector2(center.x, center.z),
		"segment_start": start_2d,
		"segment_end": end_2d,
		"capsule_radius": capsule_radius,
		"broad_radius": half_width + capsule_radius,
	}


static func _resolve_pair_push(first_footprint: Dictionary, second_footprint: Dictionary) -> Dictionary:
	var first_center: Vector2 = first_footprint.get("center", Vector2.ZERO)
	var second_center: Vector2 = second_footprint.get("center", Vector2.ZERO)
	var broad_radius: float = float(first_footprint.get("broad_radius", 0.0)) + float(second_footprint.get("broad_radius", 0.0))
	if first_center.distance_to(second_center) > broad_radius:
		return {}
	var closest: Dictionary = _closest_points_on_segments_2d(
		first_footprint.get("segment_start", first_center),
		first_footprint.get("segment_end", first_center),
		second_footprint.get("segment_start", second_center),
		second_footprint.get("segment_end", second_center)
	)
	var desired_distance: float = float(first_footprint.get("capsule_radius", 0.0)) + float(second_footprint.get("capsule_radius", 0.0))
	var distance_m: float = float(closest.get("distance", INF))
	if distance_m >= desired_distance:
		return {}
	var closest_first: Vector2 = closest.get("point_a", first_center)
	var closest_second: Vector2 = closest.get("point_b", second_center)
	var direction: Vector2 = closest_second - closest_first
	if direction.length_squared() <= 0.001:
		direction = second_center - first_center
	if direction.length_squared() <= 0.001:
		direction = Vector2(1.0, 0.0)
	direction = direction.normalized()
	return {
		"direction": direction,
		"penetration_m": desired_distance - distance_m,
	}


static func _accumulate_pair_push(pushes: Dictionary, first: CoreV2Battalion, second: CoreV2Battalion, push_data: Dictionary) -> void:
	var direction: Vector2 = push_data.get("direction", Vector2.ZERO)
	var penetration_m: float = float(push_data.get("penetration_m", 0.0))
	if penetration_m <= 0.0:
		return
	var push_strength: float = FRIENDLY_PUSH_STRENGTH if first.army_id == second.army_id else ENEMY_PUSH_STRENGTH
	var push_amount: float = min(MAX_PUSH_PER_PAIR_M, penetration_m * 0.42 * push_strength)
	if push_amount <= 0.0:
		return
	var first_mass: float = _resolve_battalion_mass(first)
	var second_mass: float = _resolve_battalion_mass(second)
	var total_mass: float = max(1.0, first_mass + second_mass)
	var first_share: float = second_mass / total_mass
	var second_share: float = first_mass / total_mass
	_add_push(pushes, first.id, -direction * push_amount * first_share)
	_add_push(pushes, second.id, direction * push_amount * second_share)
	first.separation_contacts += 1
	second.separation_contacts += 1


static func _resolve_battalion_mass(battalion: CoreV2Battalion) -> float:
	var status_factor: float = 0.65 if battalion.status == CoreV2Types.UnitStatus.ROUTING else 1.0
	return max(120.0, float(battalion.soldiers_total)) * (0.55 + battalion.cohesion) * status_factor


static func _add_push(pushes: Dictionary, battalion_id: StringName, push: Vector2) -> void:
	var current_push: Vector2 = pushes.get(battalion_id, Vector2.ZERO)
	pushes[battalion_id] = current_push + push


static func _apply_pushes(state: CoreV2BattleState, battalions: Array, pushes: Dictionary) -> void:
	for battalion_value in battalions:
		var battalion: CoreV2Battalion = battalion_value
		var push: Vector2 = pushes.get(battalion.id, Vector2.ZERO)
		var push_length: float = push.length()
		if push_length <= 0.001:
			continue
		if push_length > MAX_PUSH_PER_TICK_M:
			push = push.normalized() * MAX_PUSH_PER_TICK_M
			push_length = MAX_PUSH_PER_TICK_M
		var pressure_direction := Vector3(push.x, 0.0, push.y)
		if pressure_direction.length_squared() > 0.001:
			battalion.formation_pressure_direction = pressure_direction.normalized()
			battalion.formation_pressure_m = max(battalion.formation_pressure_m, push_length)
		battalion.position.x += push.x
		battalion.position.z += push.y
		battalion.position = state.project_position_to_terrain(battalion.position)
		battalion.separation_push_m += push_length
		battalion.sync_sprite_blocks(state)


static func _closest_points_on_segments_2d(first_start: Vector2, first_end: Vector2, second_start: Vector2, second_end: Vector2) -> Dictionary:
	var best_first: Vector2 = first_start
	var best_second: Vector2 = second_start
	var best_distance_squared: float = INF
	var candidates: Array = [
		[first_start, _closest_point_on_segment(first_start, second_start, second_end)],
		[first_end, _closest_point_on_segment(first_end, second_start, second_end)],
		[_closest_point_on_segment(second_start, first_start, first_end), second_start],
		[_closest_point_on_segment(second_end, first_start, first_end), second_end],
	]
	for candidate_value in candidates:
		var candidate: Array = candidate_value
		var first_point: Vector2 = candidate[0]
		var second_point: Vector2 = candidate[1]
		var distance_squared: float = first_point.distance_squared_to(second_point)
		if distance_squared >= best_distance_squared:
			continue
		best_distance_squared = distance_squared
		best_first = first_point
		best_second = second_point
	return {
		"point_a": best_first,
		"point_b": best_second,
		"distance": sqrt(best_distance_squared),
	}


static func _closest_point_on_segment(point: Vector2, segment_start: Vector2, segment_end: Vector2) -> Vector2:
	var segment: Vector2 = segment_end - segment_start
	var segment_length_squared: float = segment.length_squared()
	if segment_length_squared <= 0.001:
		return segment_start
	var t: float = clamp((point - segment_start).dot(segment) / segment_length_squared, 0.0, 1.0)
	return segment_start + segment * t
