class_name CoreV2EngagementMovementSystem
extends RefCounted


const INFANTRY_FIRE_STANDOFF_M: float = 105.0
const ARTILLERY_FIRE_STANDOFF_M: float = 760.0
const RANGE_HOLD_BUFFER_M: float = 18.0
const CLOSE_RANGE_BUFFER_M: float = 28.0
const TACTICAL_REACTION_RANGE_M: float = 520.0
const CAVALRY_REACTION_RANGE_M: float = 380.0
const RETREAT_DISTANCE_M: float = 360.0
const RETREAT_LOSS_RATIO: float = 1.45
const RETREAT_MIN_LOSSES: int = 5
const CHARGE_COMMIT_RANGE_M: float = 240.0
const SMOKE_CHARGE_COMMIT_RANGE_M: float = 310.0
const MELEE_POWER_ADVANTAGE: float = 1.25
const PRESSURE_WITHDRAWAL_COHESION_LOSS_PER_SECOND: float = 0.012
const RETREAT_COHESION_LOSS_PER_SECOND: float = 0.018
const SMOKE_ASSAULT_DENSITY: float = 0.42
const SMOKE_TARGET_SWITCH_DENSITY: float = 0.52
const INFANTRY_MELEE_CONTACT_RANGE_M: float = 95.0
const CAVALRY_MELEE_CONTACT_RANGE_M: float = 120.0
const TARGET_LOCK_SECONDS: float = 2.8
const TARGET_SWITCH_SCORE_MARGIN_M: float = 135.0
const FORMATION_DECISION_COOLDOWN_SECONDS: float = 5.5
const EMERGENCY_CAVALRY_FORMATION_RANGE_M: float = 210.0
const FACING_MIN_TURN_DEGREES: float = 7.0
const FACING_TURN_RATE_RADIANS_PER_SECOND: float = 1.45


static func update_engagement_movement(state: CoreV2BattleState, delta: float) -> void:
	if state == null or state.phase != CoreV2Types.BattlePhase.ACTIVE:
		return
	for army_value in state.armies.values():
		var army: CoreV2Army = army_value
		if army == null:
			continue
		for brigade_value in army.brigades:
			var brigade: CoreV2Brigade = brigade_value
			if brigade == null or brigade.is_reserve:
				continue
			for battalion_value in brigade.battalions:
				var battalion: CoreV2Battalion = battalion_value
				_update_battalion_engagement(state, brigade, battalion, delta)


static func _update_battalion_engagement(state: CoreV2BattleState, brigade: CoreV2Brigade, battalion: CoreV2Battalion, delta: float) -> void:
	_advance_engagement_timers(battalion, delta)
	if _is_unable_to_maneuver(battalion):
		_clear_engagement_maneuver(battalion)
		return
	var previous_target_id: StringName = battalion.engagement_target_id
	var target: CoreV2Battalion = _find_best_visible_enemy(state, battalion)
	if target == null:
		_clear_engagement_maneuver(battalion)
		return
	var distance_m: float = _distance_2d(battalion.position, target.position)
	if not _should_control_contact(brigade, battalion, target, distance_m):
		_clear_engagement_maneuver(battalion)
		return

	var maneuver: Dictionary = _resolve_maneuver(state, battalion, target, distance_m)
	var mode: String = String(maneuver.get("mode", "fire_standoff"))
	var desired_range_m: float = float(maneuver.get("desired_range_m", INFANTRY_FIRE_STANDOFF_M))
	battalion.engagement_target_id = target.id
	if previous_target_id != target.id:
		battalion.engagement_target_lock_seconds = TARGET_LOCK_SECONDS
	battalion.engagement_mode = mode
	battalion.engagement_desired_range_m = desired_range_m
	_request_contact_formation(battalion, target, mode, distance_m)
	_face_target(battalion, target.position, delta)

	_apply_pressure_withdrawal_cohesion_loss(state, battalion, target, mode, desired_range_m, distance_m, delta)
	if battalion.status == CoreV2Types.UnitStatus.ROUTING:
		return

	if mode == "retreat":
		_apply_tactical_target(state, battalion, _resolve_retreat_position(state, brigade, battalion, target))
		return

	var should_hold: bool = _should_hold_engagement_range(mode, distance_m, desired_range_m)
	if should_hold:
		_hold_fire_position(battalion)
		return

	var next_position: Vector3 = _resolve_standoff_position(state, battalion, target, desired_range_m)
	_apply_tactical_target(state, battalion, next_position, 0.1 if mode == "melee_charge" else 16.0)


static func _resolve_maneuver(state: CoreV2BattleState, battalion: CoreV2Battalion, target: CoreV2Battalion, distance_m: float) -> Dictionary:
	var is_losing_exchange: bool = _should_retreat(battalion)
	var smoke_density: float = state.get_smoke_density_between(battalion.position, target.position) if state != null else 0.0
	if battalion.current_order != null and battalion.current_order.order_type == CoreV2Types.OrderType.MELEE_ASSAULT:
		return {
			"mode": "melee_charge",
			"desired_range_m": _get_melee_contact_range_m(battalion),
		}
	if _should_use_smoke_for_melee_assault(battalion, target, distance_m, smoke_density):
		return {
			"mode": "melee_charge",
			"desired_range_m": _get_melee_contact_range_m(battalion),
		}
	if is_losing_exchange and _should_commit_melee(battalion, target, distance_m):
		return {
			"mode": "melee_charge",
			"desired_range_m": _get_melee_contact_range_m(battalion),
		}
	if is_losing_exchange:
		return {
			"mode": "retreat",
			"desired_range_m": INFANTRY_FIRE_STANDOFF_M,
		}
	if _should_commit_melee(battalion, target, distance_m):
		return {
			"mode": "melee_charge",
			"desired_range_m": _get_melee_contact_range_m(battalion),
		}
	if _should_force_melee_role(battalion, distance_m):
		return {
			"mode": "melee_charge",
			"desired_range_m": _get_melee_contact_range_m(battalion),
		}
	return {
		"mode": "fire_standoff",
		"desired_range_m": _get_fire_standoff_m(battalion),
	}


static func _should_hold_engagement_range(mode: String, distance_m: float, desired_range_m: float) -> bool:
	if mode == "melee_charge":
		return distance_m <= desired_range_m
	return distance_m <= desired_range_m + RANGE_HOLD_BUFFER_M and distance_m >= desired_range_m - CLOSE_RANGE_BUFFER_M


static func _should_control_contact(brigade: CoreV2Brigade, battalion: CoreV2Battalion, target: CoreV2Battalion, distance_m: float) -> bool:
	if battalion.current_order == null:
		return distance_m <= _get_local_reaction_range_m(battalion, target)
	if battalion.current_order.order_type == CoreV2Types.OrderType.ATTACK or battalion.current_order.order_type == CoreV2Types.OrderType.MELEE_ASSAULT:
		return true
	if bool(brigade.order_policies.get("deploy_on_contact", false)):
		return distance_m <= TACTICAL_REACTION_RANGE_M
	if battalion.current_order.order_type in [
		CoreV2Types.OrderType.MOVE,
		CoreV2Types.OrderType.MARCH,
		CoreV2Types.OrderType.PATROL,
	]:
		return distance_m <= TACTICAL_REACTION_RANGE_M
	return distance_m <= _get_local_reaction_range_m(battalion, target)


static func _request_contact_formation(battalion: CoreV2Battalion, target: CoreV2Battalion, mode: String, distance_m: float) -> void:
	var next_formation_state: int = _resolve_contact_formation(battalion, target, mode, distance_m)
	if next_formation_state < 0 or battalion.desired_formation_state == next_formation_state:
		return
	var is_emergency: bool = (
		battalion.category == CoreV2Types.UnitCategory.INFANTRY
		and target.category == CoreV2Types.UnitCategory.CAVALRY
		and next_formation_state == CoreV2Types.FormationState.DEFENSIVE
		and distance_m <= EMERGENCY_CAVALRY_FORMATION_RANGE_M
	)
	if battalion.is_reforming and not is_emergency:
		return
	if battalion.engagement_formation_cooldown_seconds > 0.0 and not is_emergency:
		return
	battalion.request_formation(next_formation_state)
	battalion.engagement_contact_formation_state = next_formation_state
	battalion.engagement_formation_cooldown_seconds = FORMATION_DECISION_COOLDOWN_SECONDS


static func _resolve_contact_formation(battalion: CoreV2Battalion, target: CoreV2Battalion, mode: String, distance_m: float) -> int:
	if battalion.category == CoreV2Types.UnitCategory.CAVALRY:
		return CoreV2Types.FormationState.LINE if mode == "melee_charge" else CoreV2Types.FormationState.COLUMN
	if battalion.category != CoreV2Types.UnitCategory.INFANTRY:
		return -1
	if mode == "melee_charge":
		return CoreV2Types.FormationState.LINE
	if target.category == CoreV2Types.UnitCategory.CAVALRY and distance_m <= CAVALRY_REACTION_RANGE_M:
		return CoreV2Types.FormationState.DEFENSIVE
	if mode == "fire_standoff" and battalion.ammunition > 0.02:
		return CoreV2Types.FormationState.MUSKETEER_LINE
	if mode == "retreat":
		return CoreV2Types.FormationState.LINE
	return -1


static func _should_retreat(battalion: CoreV2Battalion) -> bool:
	var taken: int = battalion.recent_casualties_taken
	var inflicted: int = battalion.recent_casualties_inflicted
	if taken < RETREAT_MIN_LOSSES:
		return false
	if battalion.cohesion < 0.34 and taken > inflicted:
		return true
	return float(taken) >= float(max(1, inflicted)) * RETREAT_LOSS_RATIO + 2.0


static func _should_commit_melee(battalion: CoreV2Battalion, target: CoreV2Battalion, distance_m: float) -> bool:
	if distance_m > CHARGE_COMMIT_RANGE_M:
		return false
	if battalion.cohesion < 0.46:
		return false
	if battalion.category == CoreV2Types.UnitCategory.CAVALRY:
		return true
	if battalion.ammunition <= 0.02:
		return true
	var melee_power: float = _resolve_melee_power(battalion)
	var target_melee_power: float = _resolve_melee_power(target)
	return melee_power >= target_melee_power * MELEE_POWER_ADVANTAGE


static func _should_use_smoke_for_melee_assault(battalion: CoreV2Battalion, target: CoreV2Battalion, distance_m: float, smoke_density: float) -> bool:
	if smoke_density < SMOKE_ASSAULT_DENSITY or distance_m > SMOKE_CHARGE_COMMIT_RANGE_M:
		return false
	if battalion.cohesion < 0.52:
		return false
	if battalion.category == CoreV2Types.UnitCategory.CAVALRY:
		return true
	if battalion.ammunition <= 0.02:
		return true
	return _resolve_melee_power(battalion) >= _resolve_melee_power(target) * 0.92


static func _should_force_melee_role(battalion: CoreV2Battalion, distance_m: float) -> bool:
	if distance_m > CHARGE_COMMIT_RANGE_M:
		return false
	return battalion.category == CoreV2Types.UnitCategory.CAVALRY or battalion.ammunition <= 0.02


static func _resolve_melee_power(battalion: CoreV2Battalion) -> float:
	return CoreV2BattalionCombatModel.resolve_melee_output(battalion)


static func _get_fire_standoff_m(battalion: CoreV2Battalion) -> float:
	if battalion.category == CoreV2Types.UnitCategory.ARTILLERY:
		return ARTILLERY_FIRE_STANDOFF_M
	if battalion.category == CoreV2Types.UnitCategory.CAVALRY:
		return _get_melee_contact_range_m(battalion)
	if battalion.ammunition <= 0.02:
		return _get_melee_contact_range_m(battalion)
	return INFANTRY_FIRE_STANDOFF_M


static func _get_melee_contact_range_m(battalion: CoreV2Battalion) -> float:
	return CAVALRY_MELEE_CONTACT_RANGE_M if battalion.category == CoreV2Types.UnitCategory.CAVALRY else INFANTRY_MELEE_CONTACT_RANGE_M


static func _get_melee_range_m(battalion: CoreV2Battalion) -> float:
	return CoreV2CombatSystem.CAVALRY_MELEE_RANGE_M if battalion.category == CoreV2Types.UnitCategory.CAVALRY else CoreV2CombatSystem.MELEE_RANGE_M


static func _get_local_reaction_range_m(battalion: CoreV2Battalion, target: CoreV2Battalion) -> float:
	var reaction_range_m: float = _get_fire_standoff_m(battalion) + 80.0
	if battalion.category == CoreV2Types.UnitCategory.INFANTRY:
		reaction_range_m = CoreV2CombatSystem.INFANTRY_FIRE_RANGE_M + 35.0
	if target != null and target.category == CoreV2Types.UnitCategory.CAVALRY:
		reaction_range_m = max(reaction_range_m, CAVALRY_REACTION_RANGE_M)
	return min(reaction_range_m, TACTICAL_REACTION_RANGE_M)


static func _find_best_visible_enemy(state: CoreV2BattleState, battalion: CoreV2Battalion) -> CoreV2Battalion:
	var visible_keys: Dictionary = state.visible_entity_keys_by_army.get(battalion.army_id, {})
	var best_target: CoreV2Battalion = null
	var best_score: float = INF
	var current_target: CoreV2Battalion = null
	var current_score: float = INF
	for target_value in state.get_all_battalions():
		var target: CoreV2Battalion = target_value
		if target.army_id == battalion.army_id or _is_unable_to_maneuver(target):
			continue
		if not visible_keys.has(CoreV2VisibilitySystem.battalion_key(target.id)):
			continue
		var distance_m: float = _distance_2d(battalion.position, target.position)
		var score: float = _score_visible_enemy(state, battalion, target, distance_m)
		if target.id == battalion.engagement_target_id:
			current_target = target
			current_score = score
		if score >= best_score:
			continue
		best_target = target
		best_score = score
	if current_target != null:
		if battalion.engagement_target_lock_seconds > 0.0:
			return current_target
		if best_target != null and best_target.id != current_target.id and best_score + TARGET_SWITCH_SCORE_MARGIN_M >= current_score:
			return current_target
	return best_target


static func _score_visible_enemy(state: CoreV2BattleState, battalion: CoreV2Battalion, target: CoreV2Battalion, distance_m: float) -> float:
	var smoke_density: float = state.get_smoke_density_between(battalion.position, target.position)
	var score: float = distance_m
	if _is_melee_or_charge_battalion(battalion):
		score -= smoke_density * 140.0
	else:
		score += smoke_density * 460.0
	if not _is_melee_or_charge_battalion(battalion) and smoke_density >= SMOKE_TARGET_SWITCH_DENSITY and distance_m > _get_melee_range_m(battalion):
		score += 220.0
	return score


static func _is_melee_or_charge_battalion(battalion: CoreV2Battalion) -> bool:
	if battalion.category == CoreV2Types.UnitCategory.CAVALRY:
		return true
	if battalion.current_order != null and battalion.current_order.order_type == CoreV2Types.OrderType.MELEE_ASSAULT:
		return true
	return battalion.ammunition <= 0.02


static func _apply_pressure_withdrawal_cohesion_loss(
		state: CoreV2BattleState,
		battalion: CoreV2Battalion,
		target: CoreV2Battalion,
		mode: String,
		desired_range_m: float,
		distance_m: float,
		delta: float
) -> void:
	if delta <= 0.0 or battalion.category == CoreV2Types.UnitCategory.ARTILLERY:
		return
	var is_pressure_withdrawal: bool = mode == "retreat"
	if mode == "fire_standoff" and distance_m < desired_range_m - CLOSE_RANGE_BUFFER_M:
		is_pressure_withdrawal = true
	if not is_pressure_withdrawal:
		return
	var loss_per_second: float = RETREAT_COHESION_LOSS_PER_SECOND if mode == "retreat" else PRESSURE_WITHDRAWAL_COHESION_LOSS_PER_SECOND
	if target.category == CoreV2Types.UnitCategory.CAVALRY or target.engagement_mode == "melee_charge":
		loss_per_second *= 1.35
	battalion.cohesion = max(0.0, battalion.cohesion - loss_per_second * delta)
	battalion.recent_combat_event = "Відхід під тиском: -згурт."
	if battalion.cohesion > CoreV2CombatSystem.ROUT_COHESION_THRESHOLD:
		return
	battalion.status = CoreV2Types.UnitStatus.ROUTING
	battalion.movement_path.clear()
	battalion.target_position = battalion.position
	state.recent_events.push_front("%s втратив згуртованість під час відходу під тиском." % battalion.display_name)
	while state.recent_events.size() > state.max_recent_events:
		state.recent_events.pop_back()


static func _resolve_standoff_position(
		state: CoreV2BattleState,
		battalion: CoreV2Battalion,
		target: CoreV2Battalion,
		desired_range_m: float
) -> Vector3:
	var direction_from_target: Vector2 = _direction_from_target(battalion.position, target.position)
	var next_position := Vector3(
		target.position.x + direction_from_target.x * desired_range_m,
		0.0,
		target.position.z + direction_from_target.y * desired_range_m
	)
	return _project_to_map(state, next_position)


static func _resolve_retreat_position(state: CoreV2BattleState, brigade: CoreV2Brigade, battalion: CoreV2Battalion, target: CoreV2Battalion) -> Vector3:
	var direction_from_target: Vector2 = _direction_from_target(battalion.position, target.position)
	if brigade != null and not brigade.hq_destroyed:
		var support_direction := Vector2(
			brigade.hq_position.x - battalion.position.x,
			brigade.hq_position.z - battalion.position.z
		)
		if support_direction.length_squared() > 0.001:
			direction_from_target = (direction_from_target * 0.68 + support_direction.normalized() * 0.32).normalized()
	var next_position := Vector3(
		battalion.position.x + direction_from_target.x * RETREAT_DISTANCE_M,
		0.0,
		battalion.position.z + direction_from_target.y * RETREAT_DISTANCE_M
	)
	return _project_to_map(state, next_position)


static func _apply_tactical_target(state: CoreV2BattleState, battalion: CoreV2Battalion, next_position: Vector3, update_threshold_m: float = 16.0) -> void:
	if _distance_2d(battalion.target_position, next_position) <= update_threshold_m:
		return
	var path: Array = state.plan_movement_path(
		battalion.position,
		next_position,
		battalion.category,
		CoreV2Types.OrderType.ATTACK,
		{"road_column": false}
	)
	battalion.set_target(next_position, battalion.current_order, path)


static func _hold_fire_position(battalion: CoreV2Battalion) -> void:
	battalion.movement_path.clear()
	battalion.target_position = battalion.position
	if battalion.status != CoreV2Types.UnitStatus.ROUTING:
		battalion.status = CoreV2Types.UnitStatus.ENGAGING


static func _clear_engagement_maneuver(battalion: CoreV2Battalion) -> void:
	if battalion == null:
		return
	battalion.engagement_target_id = &""
	battalion.engagement_mode = ""
	battalion.engagement_desired_range_m = 0.0
	battalion.engagement_contact_formation_state = -1


static func _is_unable_to_maneuver(battalion: CoreV2Battalion) -> bool:
	return battalion == null or battalion.status == CoreV2Types.UnitStatus.ROUTING or battalion.soldiers_total <= 0


static func _advance_engagement_timers(battalion: CoreV2Battalion, delta: float) -> void:
	if battalion == null or delta <= 0.0:
		return
	battalion.engagement_target_lock_seconds = max(0.0, battalion.engagement_target_lock_seconds - delta)
	battalion.engagement_formation_cooldown_seconds = max(0.0, battalion.engagement_formation_cooldown_seconds - delta)


static func _face_target(battalion: CoreV2Battalion, target_position: Vector3, delta: float) -> void:
	var desired_direction := Vector2(target_position.x - battalion.position.x, target_position.z - battalion.position.z)
	if desired_direction.length_squared() <= 0.001:
		return
	desired_direction = desired_direction.normalized()
	var current_direction := Vector2(battalion.facing.x, battalion.facing.z)
	if current_direction.length_squared() <= 0.001:
		battalion.facing = Vector3(desired_direction.x, 0.0, desired_direction.y)
		return
	current_direction = current_direction.normalized()
	var angle_delta: float = current_direction.angle_to(desired_direction)
	if abs(rad_to_deg(angle_delta)) <= FACING_MIN_TURN_DEGREES:
		return
	battalion.turn_toward_facing(Vector3(desired_direction.x, 0.0, desired_direction.y), delta)


static func _direction_from_target(from_position: Vector3, target_position: Vector3) -> Vector2:
	var direction := Vector2(from_position.x - target_position.x, from_position.z - target_position.z)
	if direction.length_squared() <= 0.001:
		return Vector2(0.0, 1.0)
	return direction.normalized()


static func _project_to_map(state: CoreV2BattleState, position_value: Vector3) -> Vector3:
	var max_x: float = state.map_rect.position.x + state.map_rect.size.x
	var max_z: float = state.map_rect.position.y + state.map_rect.size.y
	var clamped_position := Vector3(
		clamp(position_value.x, state.map_rect.position.x, max_x),
		position_value.y,
		clamp(position_value.z, state.map_rect.position.y, max_z)
	)
	return state.project_position_to_terrain(clamped_position)


static func _distance_2d(from_position: Vector3, to_position: Vector3) -> float:
	return Vector2(from_position.x, from_position.z).distance_to(Vector2(to_position.x, to_position.z))
