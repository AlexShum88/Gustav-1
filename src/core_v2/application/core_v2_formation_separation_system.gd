class_name CoreV2FormationSeparationSystem
extends RefCounted


const ITERATIONS: int = 2
const FOOTPRINT_PADDING_M: float = 9.0
const MIN_CAPSULE_RADIUS_M: float = 16.0
const MAX_FRIENDLY_PUSH_PER_PAIR_M: float = 5.0
const MAX_FRIENDLY_PUSH_PER_TICK_M: float = 10.0
const FRIENDLY_PUSH_STRENGTH: float = 0.22
const ENEMY_ANTI_INTERPENETRATION_PUSH_M: float = 2.8
const MAX_RECOIL_PER_TICK_M: float = 14.0
const RECOIL_CONTEST_MARGIN: float = 0.08


static func update_formation_separation(state: CoreV2BattleState, delta: float) -> void:
	if state == null or delta <= 0.0:
		return
	var battalions: Array = _collect_battalions(state)
	if battalions.size() < 2:
		return
	for battalion_value in battalions:
		var battalion: CoreV2Battalion = battalion_value
		battalion.reset_contact_state()
	for _iteration in range(ITERATIONS):
		var footprints: Dictionary = _build_footprints(state, battalions)
		var friendly_pushes: Dictionary = {}
		var recoils: Dictionary = {}
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
				var contact_data: Dictionary = _resolve_pair_contact(first_footprint, second_footprint)
				if contact_data.is_empty():
					continue
				_accumulate_pair_response(state, friendly_pushes, recoils, first, second, contact_data)
		_apply_motion_responses(state, battalions, friendly_pushes, recoils)


static func _collect_battalions(state: CoreV2BattleState) -> Array:
	var result: Array = []
	for battalion_value in state.get_all_battalions():
		var battalion: CoreV2Battalion = battalion_value
		if battalion == null or battalion.status == CoreV2Types.UnitStatus.STAGING:
			continue
		if battalion.soldiers_total <= 0:
			continue
		battalion.ensure_formation_ready()
		battalion.sync_sprite_blocks(state)
		result.append(battalion)
	return result


static func _should_ignore_pair(first: CoreV2Battalion, second: CoreV2Battalion) -> bool:
	# Батальйони однієї бригади теж мають фронтове тертя; інакше вони можуть проходити один крізь одного.
	return first.id == second.id


static func _build_footprints(state: CoreV2BattleState, battalions: Array) -> Dictionary:
	var result: Dictionary = {}
	for battalion_value in battalions:
		var battalion: CoreV2Battalion = battalion_value
		result[battalion.id] = _build_footprint(state, battalion)
	return result


static func _build_footprint(state: CoreV2BattleState, battalion: CoreV2Battalion) -> Dictionary:
	var facing: Vector3 = battalion.facing
	if facing.length_squared() <= 0.0001:
		facing = Vector3.FORWARD
	facing = facing.normalized()
	var side := Vector3(-facing.z, 0.0, facing.x).normalized()
	# Контакт є battalion-level: формаційна геометрія домену є базою, а старі offsets лише уточнюють внутрішній footprint.
	var measured_width: float = max(24.0, battalion.formation_frontage_m)
	var measured_depth: float = max(18.0, battalion.formation_depth_m)
	var local_center := Vector3.ZERO
	if not battalion.sprite_offsets.is_empty():
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
		measured_width = max(measured_width, max_x - min_x)
		measured_depth = max(measured_depth, max_z - min_z)
		local_center = Vector3((min_x + max_x) * 0.5, 0.0, (min_z + max_z) * 0.5)
	var half_width: float = max(FOOTPRINT_PADDING_M, measured_width * 0.5 + FOOTPRINT_PADDING_M)
	var capsule_radius: float = max(MIN_CAPSULE_RADIUS_M, measured_depth * 0.5 + FOOTPRINT_PADDING_M)
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
		"half_width": half_width,
		"facing": Vector2(facing.x, facing.z),
		"side": Vector2(side.x, side.z),
	}


static func _resolve_pair_contact(first_footprint: Dictionary, second_footprint: Dictionary) -> Dictionary:
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
	var first_side: Vector2 = first_footprint.get("side", Vector2.RIGHT)
	var second_side: Vector2 = second_footprint.get("side", Vector2.RIGHT)
	var first_lateral: float = absf((second_center - first_center).dot(first_side.normalized()))
	var second_lateral: float = absf((first_center - second_center).dot(second_side.normalized()))
	var first_half_width: float = max(1.0, float(first_footprint.get("half_width", 1.0)))
	var second_half_width: float = max(1.0, float(second_footprint.get("half_width", 1.0)))
	var frontage_ratio: float = clamp(1.0 - ((first_lateral + second_lateral) * 0.5 / max(1.0, (first_half_width + second_half_width) * 0.5)), 0.0, 1.0)
	return {
		"direction": direction,
		"penetration_m": desired_distance - distance_m,
		"desired_distance_m": desired_distance,
		"frontage_ratio": frontage_ratio,
		"overlap_left": max(0.0, 1.0 - first_lateral / first_half_width),
		"overlap_right": max(0.0, 1.0 - second_lateral / second_half_width),
	}


static func _accumulate_pair_response(
		state: CoreV2BattleState,
		friendly_pushes: Dictionary,
		recoils: Dictionary,
		first: CoreV2Battalion,
		second: CoreV2Battalion,
		contact_data: Dictionary
) -> void:
	var direction: Vector2 = contact_data.get("direction", Vector2.ZERO)
	var penetration_m: float = float(contact_data.get("penetration_m", 0.0))
	if penetration_m <= 0.0:
		return
	if first.army_id == second.army_id:
		_accumulate_friendly_push(friendly_pushes, first, second, direction, penetration_m)
		return
	_accumulate_enemy_contact(state, friendly_pushes, recoils, first, second, direction, penetration_m, contact_data)


static func _accumulate_friendly_push(pushes: Dictionary, first: CoreV2Battalion, second: CoreV2Battalion, direction: Vector2, penetration_m: float) -> void:
	var push_amount: float = min(MAX_FRIENDLY_PUSH_PER_PAIR_M, penetration_m * FRIENDLY_PUSH_STRENGTH)
	if push_amount <= 0.0:
		return
	var first_mass: float = _resolve_battalion_mass(first)
	var second_mass: float = _resolve_battalion_mass(second)
	var total_mass: float = max(1.0, first_mass + second_mass)
	var first_share: float = second_mass / total_mass
	var second_share: float = first_mass / total_mass
	_add_push(pushes, first.id, -direction * push_amount * first_share)
	_add_push(pushes, second.id, direction * push_amount * second_share)
	first.separation_push_m += push_amount * first_share
	second.separation_push_m += push_amount * second_share


static func _accumulate_enemy_contact(
		state: CoreV2BattleState,
		friendly_pushes: Dictionary,
		recoils: Dictionary,
		first: CoreV2Battalion,
		second: CoreV2Battalion,
		direction: Vector2,
		penetration_m: float,
		contact_data: Dictionary
) -> void:
	var desired_distance_m: float = max(1.0, float(contact_data.get("desired_distance_m", 1.0)))
	var compression: float = clamp(penetration_m / desired_distance_m, 0.0, 1.0)
	var frontage_ratio: float = float(contact_data.get("frontage_ratio", 0.0))
	var contact_pressure: float = clamp(compression * (0.45 + frontage_ratio * 0.65), 0.0, 1.0)
	var is_frontal: bool = _is_frontal_contact(first, second, direction)
	var first_score: float = _resolve_contact_staying_score(state, first)
	var second_score: float = _resolve_contact_staying_score(state, second)
	var score_total: float = max(1.0, first_score + second_score)
	var first_recoil_risk: float = clamp((second_score - first_score) / score_total + contact_pressure * 0.45 + first.disorder * 0.18, 0.0, 1.0)
	var second_recoil_risk: float = clamp((first_score - second_score) / score_total + contact_pressure * 0.45 + second.disorder * 0.18, 0.0, 1.0)

	first.register_tactical_contact(
		second.id,
		Vector3(-direction.x, 0.0, -direction.y),
		frontage_ratio,
		float(contact_data.get("overlap_left", 0.0)),
		float(contact_data.get("overlap_right", 0.0)),
		compression,
		contact_pressure,
		first_recoil_risk,
		is_frontal
	)
	second.register_tactical_contact(
		first.id,
		Vector3(direction.x, 0.0, direction.y),
		frontage_ratio,
		float(contact_data.get("overlap_right", 0.0)),
		float(contact_data.get("overlap_left", 0.0)),
		compression,
		contact_pressure,
		second_recoil_risk,
		is_frontal
	)

	if is_frontal:
		_accumulate_recoil_if_contest_lost(recoils, first, second, direction, first_score, second_score, compression, contact_pressure)
	elif compression > 0.26:
		var emergency_push: float = min(ENEMY_ANTI_INTERPENETRATION_PUSH_M, penetration_m * 0.12)
		_add_push(friendly_pushes, first.id, -direction * emergency_push)
		_add_push(friendly_pushes, second.id, direction * emergency_push)


static func _accumulate_recoil_if_contest_lost(
		recoils: Dictionary,
		first: CoreV2Battalion,
		second: CoreV2Battalion,
		direction: Vector2,
		first_score: float,
		second_score: float,
		compression: float,
		contact_pressure: float
) -> void:
	var score_total: float = max(1.0, first_score + second_score)
	var normalized_advantage: float = absf(first_score - second_score) / score_total
	if normalized_advantage < RECOIL_CONTEST_MARGIN and contact_pressure < 0.46:
		return
	var recoil_amount: float = min(MAX_RECOIL_PER_TICK_M, 2.0 + compression * 7.0 + normalized_advantage * 14.0)
	if first_score < second_score:
		_add_push(recoils, first.id, -direction * recoil_amount)
		first.melee_commitment_state = CoreV2Types.MeleeCommitmentState.RECOIL
	else:
		_add_push(recoils, second.id, direction * recoil_amount)
		second.melee_commitment_state = CoreV2Types.MeleeCommitmentState.RECOIL


static func _is_frontal_contact(first: CoreV2Battalion, second: CoreV2Battalion, direction: Vector2) -> bool:
	var first_facing := Vector2(first.facing.x, first.facing.z)
	var second_facing := Vector2(second.facing.x, second.facing.z)
	if first_facing.length_squared() <= 0.001 or second_facing.length_squared() <= 0.001:
		return true
	first_facing = first_facing.normalized()
	second_facing = second_facing.normalized()
	return first_facing.dot(direction) > 0.12 and second_facing.dot(-direction) > 0.12


static func _resolve_contact_staying_score(state: CoreV2BattleState, battalion: CoreV2Battalion) -> float:
	var staying_power: float = CoreV2BattalionCombatModel.resolve_staying_power(state, battalion)
	var melee_power: float = CoreV2BattalionCombatModel.resolve_melee_output(battalion)
	var reform_penalty: float = 0.72 if battalion.is_reforming else 1.0
	var order_penalty: float = clamp(
		1.0 - battalion.terrain_distortion * 0.24 - battalion.movement_strain * 0.18 - battalion.compression_level * 0.12,
		0.45,
		1.0
	)
	return max(1.0, (staying_power + melee_power * 0.42) * reform_penalty * order_penalty)


static func _resolve_battalion_mass(battalion: CoreV2Battalion) -> float:
	var status_factor: float = 0.65 if battalion.status == CoreV2Types.UnitStatus.ROUTING else 1.0
	return max(120.0, float(battalion.soldiers_total)) * (0.55 + battalion.cohesion) * status_factor


static func _add_push(pushes: Dictionary, battalion_id: StringName, push: Vector2) -> void:
	var current_push: Vector2 = pushes.get(battalion_id, Vector2.ZERO)
	pushes[battalion_id] = current_push + push


static func _apply_motion_responses(state: CoreV2BattleState, battalions: Array, friendly_pushes: Dictionary, recoils: Dictionary) -> void:
	for battalion_value in battalions:
		var battalion: CoreV2Battalion = battalion_value
		var push: Vector2 = friendly_pushes.get(battalion.id, Vector2.ZERO)
		var push_length: float = push.length()
		if push_length > MAX_FRIENDLY_PUSH_PER_TICK_M:
			push = push.normalized() * MAX_FRIENDLY_PUSH_PER_TICK_M
			push_length = MAX_FRIENDLY_PUSH_PER_TICK_M
		var recoil: Vector2 = recoils.get(battalion.id, Vector2.ZERO)
		var recoil_length: float = recoil.length()
		if recoil_length > MAX_RECOIL_PER_TICK_M:
			recoil = recoil.normalized() * MAX_RECOIL_PER_TICK_M
			recoil_length = MAX_RECOIL_PER_TICK_M
		var total_motion: Vector2 = push + recoil
		var total_length: float = total_motion.length()
		if total_length <= 0.001:
			continue
		var pressure_direction := Vector3(push.x, 0.0, push.y)
		if recoil_length > 0.001:
			pressure_direction = Vector3(recoil.x, 0.0, recoil.y)
		if pressure_direction.length_squared() > 0.001:
			battalion.formation_pressure_direction = pressure_direction.normalized()
			battalion.formation_pressure_m = max(battalion.formation_pressure_m, total_length)
		battalion.position.x += total_motion.x
		battalion.position.z += total_motion.y
		battalion.position = state.project_position_to_terrain(battalion.position)
		battalion.separation_push_m += total_length
		if recoil_length > 0.001:
			CoreV2BattalionCombatModel.apply_functional_loss(
				battalion,
				recoil_length * 0.0016,
				recoil_length * 0.0011,
				0.0,
				recoil_length * 0.0028,
				recoil_length * 0.0024
			)
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
