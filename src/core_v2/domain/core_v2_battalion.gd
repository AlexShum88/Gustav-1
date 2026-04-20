class_name CoreV2Battalion
extends RefCounted


const WAYPOINT_ARRIVAL_RADIUS_M: float = 4.0
const FRONT_TURN_SPEED_SHARE: float = 0.55
const FRONT_TURN_MIN_RATE_RPS: float = 0.16
const FRONT_TURN_MAX_RATE_RPS: float = 0.75
const FRONT_TURN_MIN_RADIUS_M: float = 32.0

var id: StringName = &""
var army_id: StringName = &""
var brigade_id: StringName = &""
var display_name: String = ""
var category: int = CoreV2Types.UnitCategory.INFANTRY
var formation_state: int = CoreV2Types.FormationState.LINE
var status: int = CoreV2Types.UnitStatus.STAGING
var position: Vector3 = Vector3.ZERO
var target_position: Vector3 = Vector3.ZERO
var target_facing: Vector3 = Vector3.FORWARD
var slot_offset: Vector3 = Vector3.ZERO
var facing: Vector3 = Vector3.FORWARD
var soldiers_total: int = 1000
var sprite_count: int = 20
var cohesion: float = 0.86
var ammunition: float = 1.0
var forage: float = 1.0
var training: float = 0.72
var move_speed_mps: float = 32.0
var vision_radius_m: float = 1500.0
var commander: CoreV2Commander
var current_order: CoreV2Order
var order_source: int = CoreV2Types.OrderSource.BRIGADE
var active_order: CoreV2Order
var order_delay_remaining: float = 0.0
var order_age: float = 0.0
var override_expires_at: float = -1.0
var inherits_brigade_intent_after_override: bool = true
var movement_path: Array = []
var combat_target_id: StringName = &""
var combat_target_name: String = ""
var combat_range_m: float = 0.0
var combat_cooldown_seconds: float = 0.0
var combat_reload_seconds: float = 0.0
var combat_attack_kind: String = ""
var combat_melee_blocks: int = 0
var combat_melee_pressure: float = 0.0
var recent_casualties_inflicted: int = 0
var recent_casualties_taken: int = 0
var fire_casualty_carry: float = 0.0
var melee_casualty_carry: float = 0.0
var recent_combat_event: String = ""
var engagement_target_id: StringName = &""
var engagement_mode: String = ""
var engagement_desired_range_m: float = 0.0
var engagement_target_lock_seconds: float = 0.0
var engagement_formation_cooldown_seconds: float = 0.0
var engagement_contact_formation_state: int = -1
var separation_contacts: int = 0
var separation_push_m: float = 0.0
var formation_pressure_direction: Vector3 = Vector3.ZERO
var formation_pressure_m: float = 0.0
var is_in_contact: bool = false
var contact_frontage_ratio: float = 0.0
var contact_overlap_left: float = 0.0
var contact_overlap_right: float = 0.0
var compression_level: float = 0.0
var contact_pressure: float = 0.0
var recoil_tendency: float = 0.0
var alignment_loss_from_contact: float = 0.0
var locked_in_melee: bool = false
var contact_opponent_ids: Array = []
var desired_formation_state: int = CoreV2Types.FormationState.LINE
var formation_frontage_m: float = 0.0
var desired_formation_frontage_m: float = 0.0
var sprite_offsets: Array = []
var sprite_offset_velocities: Array = []
var sprite_target_offsets: Array = []
var sprite_reform_from_offsets: Array = []
var sprite_roles: Array = []
var sprite_blocks: Array = []
var legacy_sprite_blocks_enabled: bool = false
var formation_elapsed_seconds: float = 0.0
var formation_duration_seconds: float = 1.0
var formation_progress: float = 1.0
var is_reforming: bool = false
var pike_strength: float = 360.0
var shot_strength_left: float = 320.0
var shot_strength_right: float = 320.0
var shot_reserve_strength: float = 0.0
var officer_quality: float = 0.72
var drill_quality: float = 0.72
var formation_depth_m: float = 0.0
var alignment_score: float = 1.0
var front_continuity: float = 1.0
var depth_cohesion: float = 1.0
var terrain_distortion: float = 0.0
var interpenetration_stress: float = 0.0
var morale: float = 0.86
var fatigue: float = 0.0
var disorder: float = 0.0
var suppression: float = 0.0
var ammo_state: float = 1.0
var smoke_burden: float = 0.0
var melee_commitment_state: int = CoreV2Types.MeleeCommitmentState.NONE
var cavalry_threat_response: int = CoreV2Types.FormationState.DEFENSIVE
var fire_doctrine: int = CoreV2Types.FireDoctrine.SALVO
var reload_cycle_state: float = 0.0
var volley_readiness: float = 1.0
var road_contact_state: String = "offroad"
var movement_state: String = "idle"
var movement_strain: float = 0.0
var visibility_profile: Dictionary = {}
var last_engagement_id: StringName = &""


func set_target(next_target: Vector3, order: CoreV2Order, next_movement_path: Array = [], next_facing: Vector3 = Vector3.ZERO) -> void:
	target_position = next_target
	current_order = order
	active_order = order
	order_age = 0.0
	movement_path = _sanitize_movement_path(next_movement_path)
	if next_facing.length_squared() > 0.001:
		target_facing = next_facing.normalized()
	if _distance_2d(position, target_position) <= 8.0 and movement_path.is_empty():
		status = CoreV2Types.UnitStatus.HOLDING if order != null and order.order_type in [
			CoreV2Types.OrderType.DEFEND,
			CoreV2Types.OrderType.HOLD,
		] else CoreV2Types.UnitStatus.IDLE
		return
	status = CoreV2Types.UnitStatus.MOVING


func issue_direct_override(
		order: CoreV2Order,
		next_target: Vector3,
		next_movement_path: Array,
		next_facing: Vector3,
		current_time_seconds: float,
		override_duration_seconds: float
) -> void:
	order_source = CoreV2Types.OrderSource.BATTALION_OVERRIDE
	override_expires_at = current_time_seconds + override_duration_seconds if override_duration_seconds > 0.0 else -1.0
	inherits_brigade_intent_after_override = true
	set_target(next_target, order, next_movement_path, next_facing)


func has_active_battalion_override(current_time_seconds: float) -> bool:
	if order_source != CoreV2Types.OrderSource.BATTALION_OVERRIDE:
		return false
	return override_expires_at < 0.0 or current_time_seconds < override_expires_at


func clear_battalion_override() -> void:
	if order_source == CoreV2Types.OrderSource.BATTALION_OVERRIDE:
		order_source = CoreV2Types.OrderSource.BRIGADE
	override_expires_at = -1.0


func advance(delta: float, terrain_state = null) -> void:
	order_age += delta
	var position_2d := Vector2(position.x, position.z)
	var active_target: Vector3 = _get_active_movement_target()
	var target_2d := Vector2(active_target.x, active_target.z)
	var distance_to_target: float = position_2d.distance_to(target_2d)
	if distance_to_target <= WAYPOINT_ARRIVAL_RADIUS_M:
		_arrive_at_active_waypoint(terrain_state)
		_turn_toward_target_facing(delta, terrain_state)
		CoreV2FormationSystem.advance_battalion(self, delta, terrain_state)
		_update_battalion_condition(terrain_state, delta)
		return

	# Рух іде до активного waypoint; швидкість бере terrain/road multiplier із server-state.
	var speed_multiplier: float = terrain_state.get_speed_multiplier_at(position, category) if terrain_state != null else 1.0
	var contact_speed_multiplier: float = _resolve_contact_movement_multiplier(active_target)
	var step: float = min(distance_to_target, move_speed_mps * speed_multiplier * contact_speed_multiplier * delta)
	var movement_direction_2d: Vector2 = (target_2d - position_2d).normalized()
	if movement_direction_2d.length_squared() > 0.0001 and engagement_target_id == &"":
		turn_toward_facing(Vector3(movement_direction_2d.x, 0.0, movement_direction_2d.y), delta, speed_multiplier)
	position.x += movement_direction_2d.x * step
	position.z += movement_direction_2d.y * step
	if terrain_state != null:
		position.y = terrain_state.get_height_at(position)
	if step > 0.0 and status != CoreV2Types.UnitStatus.ROUTING:
		status = CoreV2Types.UnitStatus.MOVING
	CoreV2FormationSystem.advance_battalion(self, delta, terrain_state)
	_update_battalion_condition(terrain_state, delta)


func request_formation(next_formation_state: int, next_frontage_m: float = -1.0) -> void:
	CoreV2FormationSystem.request_formation(self, next_formation_state, next_frontage_m)


func turn_toward_facing(desired_facing: Vector3, delta: float, speed_multiplier: float = 1.0) -> void:
	if delta <= 0.0:
		return
	var desired_flat := Vector3(desired_facing.x, 0.0, desired_facing.z)
	if desired_flat.length_squared() <= 0.001:
		return
	desired_flat = desired_flat.normalized()
	var current_flat := Vector3(facing.x, 0.0, facing.z)
	if current_flat.length_squared() <= 0.001:
		facing = desired_flat
		return
	current_flat = current_flat.normalized()
	var current_angle: float = atan2(current_flat.z, current_flat.x)
	var desired_angle: float = atan2(desired_flat.z, desired_flat.x)
	var angle_delta: float = wrapf(desired_angle - current_angle, -PI, PI)
	var max_turn: float = _get_max_front_turn_rate(speed_multiplier) * delta
	if absf(angle_delta) <= max_turn:
		facing = desired_flat
		return
	var next_angle: float = current_angle + clamp(angle_delta, -max_turn, max_turn)
	facing = Vector3(cos(next_angle), 0.0, sin(next_angle)).normalized()


func ensure_formation_ready() -> void:
	if sprite_offsets.size() == sprite_count and sprite_roles.size() == sprite_count:
		sync_sprite_blocks()
		return
	CoreV2FormationSystem.initialize_battalion(self)
	sync_sprite_blocks()


func sync_sprite_blocks(terrain_state = null) -> void:
	# Старий 50-man block шар залишено лише як опційний legacy/debug шлях.
	# Авторитетна бойова логіка і основний клієнтський рендер працюють від стану батальйону.
	if not legacy_sprite_blocks_enabled:
		if not sprite_blocks.is_empty():
			sprite_blocks.clear()
		return
	if sprite_offsets.size() != sprite_count or sprite_roles.size() != sprite_count:
		return
	_resize_sprite_blocks()
	_normalize_sprite_block_soldiers()
	for index in range(sprite_count):
		var block: CoreV2SpriteBlock = sprite_blocks[index]
		block.sync_from_battalion(
			army_id,
			id,
			index,
			String(sprite_roles[index]),
			sprite_offsets[index],
			get_sprite_world_position(index, terrain_state)
		)


func get_sprite_block(sprite_index: int) -> CoreV2SpriteBlock:
	if sprite_index < 0 or sprite_index >= sprite_blocks.size():
		return null
	return sprite_blocks[sprite_index] as CoreV2SpriteBlock


func get_sprite_world_position(sprite_index: int, terrain_state = null) -> Vector3:
	if sprite_index < 0 or sprite_index >= sprite_offsets.size():
		return position
	var world_position: Vector3 = position + _transform_local_offset(sprite_offsets[sprite_index], facing)
	if terrain_state != null:
		world_position.y = terrain_state.get_height_at(world_position)
	return world_position


func create_snapshot(player_army_id: StringName) -> Dictionary:
	ensure_formation_ready()
	var visual_state: Dictionary = create_visual_state()
	return {
		"id": String(id),
		"army_id": String(army_id),
		"brigade_id": String(brigade_id),
		"display_name": display_name,
		"category": category,
		"category_label": CoreV2Types.unit_category_name(category),
		"formation_state": formation_state,
		"formation_label": CoreV2Types.formation_state_name(formation_state),
		"desired_formation_state": desired_formation_state,
		"desired_formation_label": CoreV2Types.formation_state_name(desired_formation_state),
		"formation_frontage_m": formation_frontage_m,
		"desired_formation_frontage_m": desired_formation_frontage_m,
		"formation_depth_m": formation_depth_m,
		"is_reforming": is_reforming,
		"formation_progress": formation_progress,
		"status": status,
		"status_label": CoreV2Types.unit_status_name(status),
		"position": position,
		"target_position": target_position,
		"target_facing": target_facing,
		"facing": facing,
		"soldiers_total": soldiers_total,
		"visible_strength_estimate": soldiers_total,
		"pike_strength": pike_strength,
		"shot_strength_left": shot_strength_left,
		"shot_strength_right": shot_strength_right,
		"pike_ratio": _safe_ratio(pike_strength, float(max(1, soldiers_total))),
		"shot_ratio": _safe_ratio(shot_strength_left + shot_strength_right, float(max(1, soldiers_total))),
		"cohesion": cohesion,
		"morale": morale,
		"fatigue": fatigue,
		"disorder": disorder,
		"suppression": suppression,
		"alignment_score": alignment_score,
		"front_continuity": front_continuity,
		"depth_cohesion": depth_cohesion,
		"terrain_distortion": terrain_distortion,
		"interpenetration_stress": interpenetration_stress,
		"ammunition": ammunition,
		"ammo_state": ammo_state,
		"forage": forage,
		"training": training,
		"drill_quality": drill_quality,
		"officer_quality": officer_quality,
		"move_speed_mps": move_speed_mps,
		"vision_radius_m": vision_radius_m,
		"terrain_speed_multiplier": 1.0,
		"terrain_defense_modifier": 0.0,
		"movement_path": movement_path.duplicate(true),
		"combat_target_id": String(combat_target_id),
		"combat_target_name": combat_target_name,
		"combat_range_m": combat_range_m,
		"combat_cooldown_seconds": combat_cooldown_seconds,
		"combat_reload_seconds": combat_reload_seconds,
		"combat_attack_kind": combat_attack_kind,
		"combat_melee_pressure": combat_melee_pressure,
		"recent_casualties_inflicted": recent_casualties_inflicted,
		"recent_casualties_taken": recent_casualties_taken,
		"recent_combat_event": recent_combat_event,
		"engagement_target_id": String(engagement_target_id),
		"engagement_mode": engagement_mode,
		"engagement_desired_range_m": engagement_desired_range_m,
		"engagement_target_lock_seconds": engagement_target_lock_seconds,
		"engagement_formation_cooldown_seconds": engagement_formation_cooldown_seconds,
		"last_engagement_id": String(last_engagement_id),
		"separation_contacts": separation_contacts,
		"separation_push_m": separation_push_m,
		"formation_pressure_direction": formation_pressure_direction,
		"formation_pressure_m": formation_pressure_m,
		"is_in_contact": is_in_contact,
		"contact_frontage_ratio": contact_frontage_ratio,
		"contact_overlap_left": contact_overlap_left,
		"contact_overlap_right": contact_overlap_right,
		"compression_level": compression_level,
		"contact_pressure": contact_pressure,
		"recoil_tendency": recoil_tendency,
		"alignment_loss_from_contact": alignment_loss_from_contact,
		"locked_in_melee": locked_in_melee,
		"contact_opponent_ids": contact_opponent_ids.duplicate(),
		"order_source": order_source,
		"order_source_label": CoreV2Types.order_source_name(order_source),
		"order_age": order_age,
		"override_expires_at": override_expires_at,
		"inherits_brigade_intent_after_override": inherits_brigade_intent_after_override,
		"fire_doctrine": fire_doctrine,
		"fire_doctrine_label": CoreV2Types.fire_doctrine_name(fire_doctrine),
		"reload_cycle_state": reload_cycle_state,
		"volley_readiness": volley_readiness,
		"smoke_burden": smoke_burden,
		"melee_commitment_state": melee_commitment_state,
		"melee_commitment_label": CoreV2Types.melee_commitment_state_name(melee_commitment_state),
		"movement_state": movement_state,
		"movement_strain": movement_strain,
		"road_contact_state": road_contact_state,
		"visibility_profile": visibility_profile.duplicate(true),
		"visual_state": visual_state,
		"is_friendly": army_id == player_army_id,
		"commander_name": commander.display_name if commander != null else "",
		"order_label": CoreV2Types.order_type_name(
			current_order.order_type if current_order != null else CoreV2Types.OrderType.NONE
		),
		"order_type": current_order.order_type if current_order != null else CoreV2Types.OrderType.NONE,
	}


func create_visual_state() -> Dictionary:
	var width_m: float = max(36.0, formation_frontage_m)
	var depth_m: float = max(24.0, formation_depth_m)
	if width_m <= 36.0 or depth_m <= 24.0:
		var footprint: Dictionary = _measure_current_footprint()
		width_m = max(width_m, float(footprint.get("frontage_m", width_m)))
		depth_m = max(depth_m, float(footprint.get("depth_m", depth_m)))
	var disorder_band: float = clamp(disorder * 0.55 + (1.0 - cohesion) * 0.25 + terrain_distortion * 0.2, 0.0, 1.0)
	return {
		"position": position,
		"facing": facing,
		"formation_state": formation_state,
		"formation_progress": formation_progress,
		"frontage_m": width_m,
		"depth_m": depth_m,
		"alignment_score": alignment_score,
		"front_continuity": front_continuity,
		"depth_cohesion": depth_cohesion,
		"disorder_band": disorder_band,
		"smoke_burden": smoke_burden,
		"compression_level": compression_level,
		"contact_pressure": contact_pressure,
		"contact_frontage_ratio": contact_frontage_ratio,
		"recoil_tendency": recoil_tendency,
		"locked_in_melee": locked_in_melee,
		"formation_pressure_direction": formation_pressure_direction,
		"terrain_distortion": terrain_distortion,
		"cohesion": cohesion,
		"morale": morale,
		"pike_ratio": _safe_ratio(pike_strength, float(max(1, soldiers_total))),
		"shot_ratio": _safe_ratio(shot_strength_left + shot_strength_right, float(max(1, soldiers_total))),
		"engagement_state": engagement_mode,
		"combat_attack_kind": combat_attack_kind,
		"combat_melee_pressure": combat_melee_pressure,
		"order_source": order_source,
		"movement_state": movement_state,
	}


func _sanitize_movement_path(next_movement_path: Array) -> Array:
	var result: Array = []
	for waypoint_value in next_movement_path:
		var waypoint: Vector3 = waypoint_value
		if result.is_empty():
			if _distance_2d(position, waypoint) <= WAYPOINT_ARRIVAL_RADIUS_M:
				continue
		elif _distance_2d(result[result.size() - 1], waypoint) <= WAYPOINT_ARRIVAL_RADIUS_M:
			continue
		result.append(waypoint)
	if not result.is_empty() and _distance_2d(result[result.size() - 1], target_position) > WAYPOINT_ARRIVAL_RADIUS_M:
		result.append(target_position)
	return result


func _get_active_movement_target() -> Vector3:
	return movement_path[0] if not movement_path.is_empty() else target_position


func reset_contact_state() -> void:
	separation_contacts = 0
	separation_push_m = 0.0
	is_in_contact = false
	contact_frontage_ratio = 0.0
	contact_overlap_left = 0.0
	contact_overlap_right = 0.0
	compression_level = 0.0
	contact_pressure = 0.0
	recoil_tendency = 0.0
	alignment_loss_from_contact = 0.0
	locked_in_melee = false
	contact_opponent_ids.clear()


func register_tactical_contact(
		opponent_id: StringName,
		pressure_direction: Vector3,
		frontage_ratio: float,
		overlap_left: float,
		overlap_right: float,
		compression: float,
		pressure: float,
		recoil_risk: float,
		is_melee_locked: bool
) -> void:
	is_in_contact = true
	separation_contacts += 1
	contact_frontage_ratio = max(contact_frontage_ratio, clamp(frontage_ratio, 0.0, 1.0))
	contact_overlap_left = max(contact_overlap_left, clamp(overlap_left, 0.0, 1.0))
	contact_overlap_right = max(contact_overlap_right, clamp(overlap_right, 0.0, 1.0))
	compression_level = max(compression_level, clamp(compression, 0.0, 1.0))
	contact_pressure = max(contact_pressure, clamp(pressure, 0.0, 1.0))
	recoil_tendency = max(recoil_tendency, clamp(recoil_risk, 0.0, 1.0))
	alignment_loss_from_contact = max(alignment_loss_from_contact, contact_pressure * 0.035 + compression_level * 0.025)
	locked_in_melee = locked_in_melee or is_melee_locked
	if not contact_opponent_ids.has(String(opponent_id)):
		contact_opponent_ids.append(String(opponent_id))
	var flat_pressure := Vector3(pressure_direction.x, 0.0, pressure_direction.z)
	if flat_pressure.length_squared() > 0.001:
		formation_pressure_direction = flat_pressure.normalized()
	formation_pressure_m = max(formation_pressure_m, 10.0 + contact_pressure * 26.0 + compression_level * 18.0)


func _arrive_at_active_waypoint(terrain_state = null) -> void:
	if not movement_path.is_empty():
		position = movement_path[0]
		movement_path.remove_at(0)
		if terrain_state != null:
			position.y = terrain_state.get_height_at(position)
		if not movement_path.is_empty() or _distance_2d(position, target_position) > WAYPOINT_ARRIVAL_RADIUS_M:
			if status != CoreV2Types.UnitStatus.ROUTING:
				status = CoreV2Types.UnitStatus.MOVING
			return

	position = target_position
	if terrain_state != null:
		position.y = terrain_state.get_height_at(position)
	if current_order != null and current_order.order_type in [
		CoreV2Types.OrderType.DEFEND,
		CoreV2Types.OrderType.HOLD,
	]:
		status = CoreV2Types.UnitStatus.HOLDING
	elif status != CoreV2Types.UnitStatus.ROUTING:
		status = CoreV2Types.UnitStatus.IDLE


func _distance_2d(from_position: Vector3, to_position: Vector3) -> float:
	return Vector2(from_position.x, from_position.z).distance_to(Vector2(to_position.x, to_position.z))


func _turn_toward_target_facing(delta: float, terrain_state = null) -> void:
	if engagement_target_id != &"":
		return
	if target_facing.length_squared() <= 0.001:
		return
	var flat_facing := Vector3(target_facing.x, 0.0, target_facing.z)
	if flat_facing.length_squared() <= 0.001:
		return
	var speed_multiplier: float = terrain_state.get_speed_multiplier_at(position, category) if terrain_state != null else 1.0
	turn_toward_facing(flat_facing, delta, speed_multiplier)


func _get_max_front_turn_rate(speed_multiplier: float) -> float:
	var radius_m: float = max(FRONT_TURN_MIN_RADIUS_M, _estimate_formation_radius_m())
	var turn_speed_mps: float = max(1.0, move_speed_mps * max(0.1, speed_multiplier) * FRONT_TURN_SPEED_SHARE)
	return clamp(turn_speed_mps / radius_m, FRONT_TURN_MIN_RATE_RPS, FRONT_TURN_MAX_RATE_RPS)


func _estimate_formation_radius_m() -> float:
	var radius_m: float = FRONT_TURN_MIN_RADIUS_M
	for offset_value in sprite_offsets:
		var offset: Vector3 = offset_value
		radius_m = max(radius_m, Vector2(offset.x, offset.z).length())
	for offset_value in sprite_target_offsets:
		var offset: Vector3 = offset_value
		radius_m = max(radius_m, Vector2(offset.x, offset.z).length())
	return radius_m


func _update_battalion_condition(terrain_state, delta: float) -> void:
	if delta <= 0.0:
		return
	var footprint: Dictionary = _measure_current_footprint()
	formation_frontage_m = max(formation_frontage_m, float(footprint.get("frontage_m", formation_frontage_m)))
	formation_depth_m = float(footprint.get("depth_m", formation_depth_m))
	interpenetration_stress = clamp(float(separation_contacts) * 0.10 + separation_push_m / 48.0 + compression_level * 0.72 + contact_pressure * 0.36, 0.0, 1.0)
	movement_state = "moving" if status == CoreV2Types.UnitStatus.MOVING else "stationary"
	var terrain_speed: float = terrain_state.get_speed_multiplier_at(position, category) if terrain_state != null else 1.0
	road_contact_state = "road" if terrain_speed > 1.08 else "offroad"
	movement_strain = clamp((1.0 - terrain_speed) + interpenetration_stress * 0.55 + contact_pressure * 0.22 + (0.25 if is_reforming else 0.0), 0.0, 1.0)
	fatigue = clamp(fatigue + (0.0025 if status == CoreV2Types.UnitStatus.MOVING else -0.0015) * delta, 0.0, 1.0)
	if is_in_contact:
		disorder = clamp(disorder + (contact_pressure * 0.020 + compression_level * 0.026) * delta, 0.0, 1.0)
		alignment_score = clamp(alignment_score - alignment_loss_from_contact * delta, 0.0, 1.0)
		front_continuity = clamp(front_continuity - compression_level * 0.035 * delta, 0.0, 1.0)
	CoreV2BattalionCombatModel.update_condition(self, terrain_state)


func _measure_current_footprint() -> Dictionary:
	if sprite_offsets.is_empty():
		return {
			"frontage_m": formation_frontage_m if formation_frontage_m > 0.0 else 80.0,
			"depth_m": formation_depth_m if formation_depth_m > 0.0 else 48.0,
		}
	var min_x: float = INF
	var max_x: float = -INF
	var min_z: float = INF
	var max_z: float = -INF
	for offset_value in sprite_offsets:
		var offset: Vector3 = offset_value
		min_x = min(min_x, offset.x)
		max_x = max(max_x, offset.x)
		min_z = min(min_z, offset.z)
		max_z = max(max_z, offset.z)
	return {
		"frontage_m": max(12.0, max_x - min_x),
		"depth_m": max(12.0, max_z - min_z),
	}


func _safe_ratio(value: float, total: float) -> float:
	if total <= 0.001:
		return 0.0
	return clamp(value / total, 0.0, 1.0)


func _resolve_contact_movement_multiplier(active_target: Vector3) -> float:
	if not is_in_contact:
		return 1.0
	var target_direction: Vector3 = active_target - position
	target_direction.y = 0.0
	if target_direction.length_squared() <= 0.001:
		return 1.0
	target_direction = target_direction.normalized()
	var pressure_direction: Vector3 = formation_pressure_direction
	pressure_direction.y = 0.0
	if pressure_direction.length_squared() <= 0.001:
		return clamp(1.0 - contact_pressure * 0.72 - compression_level * 0.48, 0.12, 1.0)
	pressure_direction = pressure_direction.normalized()
	var moving_into_pressure: float = clamp(target_direction.dot(-pressure_direction), 0.0, 1.0)
	var base_multiplier: float = 1.0 - contact_pressure * lerp(0.36, 0.88, moving_into_pressure)
	base_multiplier -= compression_level * lerp(0.18, 0.55, moving_into_pressure)
	if locked_in_melee and moving_into_pressure > 0.2:
		base_multiplier = min(base_multiplier, 0.08)
	return clamp(base_multiplier, 0.03, 1.0)


func _resize_sprite_blocks() -> void:
	while sprite_blocks.size() > sprite_count:
		sprite_blocks.pop_back()
	while sprite_blocks.size() < sprite_count:
		var new_index: int = sprite_blocks.size()
		var role: String = String(sprite_roles[new_index]) if new_index < sprite_roles.size() else "mixed"
		sprite_blocks.append(CoreV2SpriteBlock.create(id, army_id, new_index, role, _estimate_new_sprite_block_soldiers()))


func _normalize_sprite_block_soldiers() -> void:
	if sprite_blocks.is_empty():
		return
	var total_from_blocks: int = 0
	for block_value in sprite_blocks:
		var block: CoreV2SpriteBlock = block_value
		total_from_blocks += max(0, block.soldiers)
	var delta_soldiers: int = soldiers_total - total_from_blocks
	if delta_soldiers == 0:
		return
	var block_index: int = 0
	var guard_limit: int = abs(delta_soldiers) + sprite_blocks.size() + 1
	while delta_soldiers != 0 and block_index < guard_limit:
		var block: CoreV2SpriteBlock = sprite_blocks[block_index % sprite_blocks.size()]
		if delta_soldiers > 0:
			block.soldiers += 1
			delta_soldiers -= 1
		elif block.soldiers > 0:
			block.soldiers -= 1
			delta_soldiers += 1
		block_index += 1


func _estimate_new_sprite_block_soldiers() -> int:
	return int(max(1.0, ceil(float(max(1, soldiers_total)) / float(max(1, sprite_count)))))


func _transform_local_offset(local_offset: Vector3, direction: Vector3) -> Vector3:
	var forward: Vector3 = direction
	if forward.length_squared() <= 0.0001:
		forward = Vector3.FORWARD
	forward = forward.normalized()
	var side := Vector3(-forward.z, 0.0, forward.x).normalized()
	return side * local_offset.x + Vector3.UP * local_offset.y + forward * local_offset.z


func _create_sprite_block_target_snapshot() -> Array:
	var result: Array = []
	for block_value in sprite_blocks:
		var block: CoreV2SpriteBlock = block_value
		if block.target_battalion_id == &"" and block.combat_cooldown_seconds <= 0.0:
			continue
		result.append({
			"index": block.index,
			"soldiers": block.soldiers,
			"target_battalion_id": String(block.target_battalion_id),
			"target_sprite_index": block.target_sprite_index,
			"cooldown": block.combat_cooldown_seconds,
			"attack_kind": block.last_attack_kind,
			"smoke_density": block.last_line_of_fire_density,
		})
	return result
