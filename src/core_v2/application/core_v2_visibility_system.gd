class_name CoreV2VisibilitySystem
extends RefCounted


const ARMY_HQ_VISION_RADIUS_M: float = 1000.0
const BRIGADE_HQ_VISION_RADIUS_M: float = 850.0
const BAGGAGE_VISION_RADIUS_M: float = 650.0
const LAST_SEEN_TTL_SECONDS: float = 300.0
const LOS_SAMPLE_STEP_M: float = 60.0
const LOS_MAX_SAMPLES: int = 48
const LOS_ENDPOINT_GRACE_M: float = 35.0
const LOS_CLEARANCE_M: float = 3.0


static func battalion_key(battalion_id: StringName) -> String:
	return "battalion:%s" % String(battalion_id)


static func army_hq_key(army_id: StringName) -> String:
	return "army_hq:%s" % String(army_id)


static func brigade_hq_key(brigade_id: StringName) -> String:
	return "brigade_hq:%s" % String(brigade_id)


static func baggage_key(army_id: StringName) -> String:
	return "baggage:%s" % String(army_id)


static func messenger_key(messenger_id: StringName) -> String:
	return "messenger:%s" % String(messenger_id)


static func update_visibility(state: CoreV2BattleState) -> void:
	var next_visible_by_army: Dictionary = {}
	for observer_army_value in state.armies.values():
		var observer_army: CoreV2Army = observer_army_value
		var visible_keys: Dictionary = {}
		_add_friendly_entities(observer_army, visible_keys)
		for target_army_value in state.armies.values():
			var target_army: CoreV2Army = target_army_value
			if target_army.id == observer_army.id:
				continue
			_add_visible_enemy_entities(state, observer_army, target_army, visible_keys)
		next_visible_by_army[observer_army.id] = visible_keys

	state.visible_entity_keys_by_army = next_visible_by_army
	_prune_expired_last_seen(state)


static func build_last_seen_markers(state: CoreV2BattleState, observer_army_id: StringName) -> Array:
	var result: Array = []
	var markers_by_key: Dictionary = state.last_seen_by_army.get(observer_army_id, {})
	var visible_keys: Dictionary = state.visible_entity_keys_by_army.get(observer_army_id, {})
	for entity_key_value in markers_by_key.keys():
		var entity_key: String = String(entity_key_value)
		if visible_keys.has(entity_key):
			continue
		var marker: Dictionary = markers_by_key[entity_key]
		var seconds_ago: float = max(0.0, state.time_seconds - float(marker.get("last_seen_seconds", state.time_seconds)))
		if seconds_ago > LAST_SEEN_TTL_SECONDS:
			continue
		var marker_snapshot: Dictionary = marker.duplicate(true)
		marker_snapshot["entity_key"] = entity_key
		marker_snapshot["seconds_ago"] = seconds_ago
		result.append(marker_snapshot)
	return result


static func _add_friendly_entities(army: CoreV2Army, visible_keys: Dictionary) -> void:
	visible_keys[army_hq_key(army.id)] = true
	visible_keys[baggage_key(army.id)] = true
	for brigade_value in army.brigades:
		var brigade: CoreV2Brigade = brigade_value
		visible_keys[brigade_hq_key(brigade.id)] = true
		for battalion_value in brigade.battalions:
			var battalion: CoreV2Battalion = battalion_value
			visible_keys[battalion_key(battalion.id)] = true


static func _add_visible_enemy_entities(
		state: CoreV2BattleState,
		observer_army: CoreV2Army,
		target_army: CoreV2Army,
		visible_keys: Dictionary
) -> void:
	var last_seen_for_observer: Dictionary = state.last_seen_by_army.get(observer_army.id, {})
	if _can_army_see_position(state, observer_army, target_army.commander_position, 70.0):
		var entity_key: String = army_hq_key(target_army.id)
		visible_keys[entity_key] = true
		_record_last_seen(state, last_seen_for_observer, entity_key, target_army.id, "Штаб полководця", CoreV2Types.EntityKind.ARMY_HQ, target_army.commander_position)
	if _can_army_see_position(state, observer_army, target_army.baggage_position, 90.0):
		var entity_key: String = baggage_key(target_army.id)
		visible_keys[entity_key] = true
		_record_last_seen(state, last_seen_for_observer, entity_key, target_army.id, "Обоз", CoreV2Types.EntityKind.BAGGAGE_TRAIN, target_army.baggage_position)

	for messenger_value in state.order_messengers:
		var messenger: CoreV2OrderMessenger = messenger_value
		if messenger.army_id != target_army.id or messenger.status != CoreV2Types.MessengerStatus.EN_ROUTE:
			continue
		if not _can_army_see_position(state, observer_army, messenger.position, 24.0):
			continue
		var messenger_entity_key: String = messenger_key(messenger.id)
		visible_keys[messenger_entity_key] = true
		_record_last_seen(state, last_seen_for_observer, messenger_entity_key, target_army.id, "Гінець", CoreV2Types.EntityKind.MESSENGER, messenger.position)

	for brigade_value in target_army.brigades:
		var brigade: CoreV2Brigade = brigade_value
		if _can_army_see_position(state, observer_army, brigade.hq_position, 55.0):
			var brigade_entity_key: String = brigade_hq_key(brigade.id)
			visible_keys[brigade_entity_key] = true
			_record_last_seen(state, last_seen_for_observer, brigade_entity_key, target_army.id, brigade.display_name, CoreV2Types.EntityKind.BRIGADE_HQ, brigade.hq_position)
		for battalion_value in brigade.battalions:
			var battalion: CoreV2Battalion = battalion_value
			var target_radius: float = _estimate_battalion_target_radius(battalion)
			if not _can_army_see_position(state, observer_army, battalion.position, target_radius):
				continue
			var battalion_entity_key: String = battalion_key(battalion.id)
			visible_keys[battalion_entity_key] = true
			_record_last_seen(state, last_seen_for_observer, battalion_entity_key, target_army.id, battalion.display_name, CoreV2Types.EntityKind.BATTALION, battalion.position)

	state.last_seen_by_army[observer_army.id] = last_seen_for_observer


static func _can_army_see_position(state: CoreV2BattleState, observer_army: CoreV2Army, target_position: Vector3, target_radius_m: float) -> bool:
	if _can_point_see(state, observer_army.commander_position, ARMY_HQ_VISION_RADIUS_M, target_position, target_radius_m):
		return true
	if _can_point_see(state, observer_army.baggage_position, BAGGAGE_VISION_RADIUS_M, target_position, target_radius_m):
		return true
	for brigade_value in observer_army.brigades:
		var brigade: CoreV2Brigade = brigade_value
		if _can_point_see(state, brigade.hq_position, BRIGADE_HQ_VISION_RADIUS_M, target_position, target_radius_m):
			return true
		for battalion_value in brigade.battalions:
			var battalion: CoreV2Battalion = battalion_value
			for observer_point in _get_battalion_observer_points(battalion):
				if _can_point_see(state, observer_point, battalion.vision_radius_m, target_position, target_radius_m):
					return true
	return false


static func _can_point_see(state: CoreV2BattleState, observer_position: Vector3, vision_radius_m: float, target_position: Vector3, target_radius_m: float) -> bool:
	var observer_2d := Vector2(observer_position.x, observer_position.z)
	var target_2d := Vector2(target_position.x, target_position.z)
	var observer_height: float = state.get_height_at(observer_position)
	var target_height: float = state.get_height_at(target_position)
	var height_bonus: float = clamp((observer_height - target_height) * 8.0, -220.0, 520.0)
	var observer_terrain_multiplier: float = state.get_visibility_multiplier_at(observer_position)
	var target_terrain_multiplier: float = state.get_visibility_multiplier_at(target_position)
	var observer_atmospheric_multiplier: float = state.get_atmospheric_visibility_multiplier_at(observer_position)
	var target_smoke_multiplier: float = state.get_smoke_vision_multiplier_at(target_position)
	var effective_radius: float = max(120.0, vision_radius_m * observer_terrain_multiplier * observer_atmospheric_multiplier + height_bonus)
	var effective_target_radius: float = target_radius_m * min(1.0, target_terrain_multiplier * target_smoke_multiplier)
	var distance_m: float = observer_2d.distance_to(target_2d)
	if distance_m > effective_radius + effective_target_radius:
		return false
	return not _is_los_blocked_by_terrain(state, observer_position, target_position, distance_m)


static func _is_los_blocked_by_terrain(
		state: CoreV2BattleState,
		observer_position: Vector3,
		target_position: Vector3,
		distance_m: float
) -> bool:
	if distance_m <= LOS_ENDPOINT_GRACE_M * 2.0:
		return false
	var sample_count: int = int(clamp(ceil(distance_m / LOS_SAMPLE_STEP_M), 2.0, float(LOS_MAX_SAMPLES)))
	var endpoint_grace_t: float = min(0.24, LOS_ENDPOINT_GRACE_M / distance_m)
	var observer_eye_height: float = state.get_los_eye_height_at(observer_position)
	var target_eye_height: float = state.get_los_eye_height_at(target_position)
	var cover_depth_m: float = 0.0
	var was_inside_blocking_cover: bool = false
	var smoke_depth_m: float = 0.0
	var was_inside_smoke: bool = false
	var sample_step_m: float = distance_m / float(sample_count)
	for sample_index in range(1, sample_count):
		var t: float = float(sample_index) / float(sample_count)
		if t <= endpoint_grace_t or t >= 1.0 - endpoint_grace_t:
			continue
		var sample_position: Vector3 = observer_position.lerp(target_position, t)
		var sightline_height: float = lerp(observer_eye_height, target_eye_height, t)
		var terrain_height: float = state.get_height_at(sample_position)
		if terrain_height > sightline_height + LOS_CLEARANCE_M:
			return true
		var smoke_density: float = state.get_los_smoke_density_at(sample_position, sightline_height)
		if smoke_density <= 0.01:
			smoke_depth_m = 0.0
			was_inside_smoke = false
		else:
			smoke_depth_m += (sample_step_m if was_inside_smoke else sample_step_m * 0.5) * smoke_density
			was_inside_smoke = true
			if smoke_depth_m > state.get_los_smoke_penetration_at(sample_position):
				return true
		var cover_height: float = state.get_los_cover_height_at(sample_position)
		var blocker_height: float = terrain_height + cover_height
		if cover_height <= 0.01 or blocker_height <= sightline_height + LOS_CLEARANCE_M:
			cover_depth_m = 0.0
			was_inside_blocking_cover = false
			continue
		cover_depth_m += sample_step_m if was_inside_blocking_cover else sample_step_m * 0.5
		was_inside_blocking_cover = true
		if cover_depth_m > state.get_los_cover_penetration_at(sample_position):
			return true
	return false


static func _get_battalion_observer_points(battalion: CoreV2Battalion) -> Array:
	var facing: Vector3 = battalion.facing
	if facing.length_squared() <= 0.0001:
		facing = Vector3.FORWARD
	facing = facing.normalized()
	var side := Vector3(-facing.z, 0.0, facing.x).normalized()
	var half_frontage: float = _estimate_battalion_frontage_m(battalion) * 0.5
	return [
		battalion.position,
		battalion.position + side * half_frontage,
		battalion.position - side * half_frontage,
	]


static func _estimate_battalion_frontage_m(battalion: CoreV2Battalion) -> float:
	if battalion.category == CoreV2Types.UnitCategory.CAVALRY:
		return 120.0
	match battalion.formation_state:
		CoreV2Types.FormationState.MARCH_COLUMN:
			return 55.0
		CoreV2Types.FormationState.COLUMN:
			return 82.0
		CoreV2Types.FormationState.MUSKETEER_LINE:
			return 165.0
		CoreV2Types.FormationState.DEFENSIVE:
			return 110.0
		CoreV2Types.FormationState.TERCIA:
			return 125.0
		_:
			return 150.0


static func _estimate_battalion_target_radius(battalion: CoreV2Battalion) -> float:
	return max(45.0, _estimate_battalion_frontage_m(battalion) * 0.5)


static func _record_last_seen(
		state: CoreV2BattleState,
		last_seen_for_observer: Dictionary,
		entity_key: String,
		target_army_id: StringName,
		display_name: String,
		entity_kind: int,
		position: Vector3
) -> void:
	last_seen_for_observer[entity_key] = {
		"army_id": String(target_army_id),
		"display_name": display_name,
		"entity_kind": entity_kind,
		"entity_kind_label": CoreV2Types.entity_kind_name(entity_kind),
		"position": position,
		"last_seen_seconds": state.time_seconds,
	}


static func _prune_expired_last_seen(state: CoreV2BattleState) -> void:
	for observer_army_id_value in state.last_seen_by_army.keys():
		var observer_army_id: StringName = observer_army_id_value
		var markers_by_key: Dictionary = state.last_seen_by_army[observer_army_id]
		for entity_key_value in markers_by_key.keys():
			var entity_key: String = String(entity_key_value)
			var marker: Dictionary = markers_by_key[entity_key]
			var seconds_ago: float = state.time_seconds - float(marker.get("last_seen_seconds", state.time_seconds))
			if seconds_ago <= LAST_SEEN_TTL_SECONDS:
				continue
			markers_by_key.erase(entity_key)
		state.last_seen_by_army[observer_army_id] = markers_by_key
