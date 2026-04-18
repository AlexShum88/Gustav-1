class_name RegimentBehaviorSystem
extends RefCounted

var ruleset: BehaviorRuleset = BehaviorRuleset.new()


func tick(sim: BattleSimulation, delta: float) -> void:
	_tick_regiments(sim, delta)
	_tick_brigade_hqs(sim, delta)
	_resolve_regiment_overlap(sim)


func _tick_regiments(sim: BattleSimulation, delta: float) -> void:
	for regiment in sim.regiments.values():
		if regiment.get_total_strength() <= 0:
			regiment.is_destroyed = true
			continue
		regiment.fatigue = clamp(regiment.fatigue + delta * 0.003, 0.0, 1.0)
		_apply_order_behavior(sim, regiment, delta)
		regiment.update_subunit_blocks(delta, sim.time_seconds)


func _apply_order_behavior(sim: BattleSimulation, regiment: Battalion, delta: float) -> void:
	var terrain: TerrainCell = sim.get_terrain_at(regiment.position)
	var doctrine: BehaviorDoctrine = ruleset.get_doctrine(regiment.behavior_doctrine_id)
	_update_recent_engagement_metrics(regiment, delta)
	var nearest_visible_enemy: Battalion = _get_visible_enemy(sim, regiment)
	var nearby_enemy: Battalion = _resolve_engagement_target(sim, regiment, nearest_visible_enemy, doctrine)
	var nearby_enemy_distance: float = regiment.position.distance_to(nearby_enemy.position) if nearby_enemy != null else INF
	regiment.last_visible_enemy_distance = nearby_enemy_distance
	var brigade: Brigade = sim.brigades.get(regiment.brigade_id)
	var goal: Vector2 = regiment.current_target_position
	var forced_retreat: bool = false

	if regiment.order_policies.get("hold_reserve", false) and regiment.current_order_type == SimTypes.OrderType.ATTACK:
		goal = ruleset.get_reserve_goal(regiment, goal)
	if brigade != null:
		goal = _adjust_goal_for_brigade_role(regiment, brigade, goal)
	if regiment.order_policies.get("retreat_on_flank_collapse", false) and ruleset.should_retreat_on_flank_collapse(regiment, sim):
		goal = sim.get_army_fallback_position(regiment.army_id)
		forced_retreat = true

	var resolved_state: int = _resolve_engagement_state(
		sim,
		regiment,
		nearby_enemy,
		nearby_enemy_distance,
		doctrine,
		forced_retreat
	)
	_apply_engagement_state_transition(regiment, resolved_state, sim.time_seconds, doctrine)

	var formation_request: Dictionary = _resolve_engagement_formation(regiment, nearby_enemy, nearby_enemy_distance)
	_request_behavior_formation(
		regiment,
		int(formation_request.get("formation_type", regiment.formation.formation_type)),
		int(formation_request.get("formation_state", regiment.formation_state)),
		sim.time_seconds,
		bool(formation_request.get("urgent", false))
	)

	_apply_debug_overrides(regiment)

	regiment.fire_behavior = _resolve_engagement_fire_behavior(regiment, nearby_enemy, sim.time_seconds)
	if regiment.has_debug_forced_fire_behavior():
		regiment.fire_behavior = regiment.debug_forced_fire_behavior

	var movement_plan: Dictionary = _resolve_movement_plan(sim, regiment, brigade, goal, nearby_enemy, doctrine)
	goal = movement_plan.get("goal", goal)

	var desired_front: Vector2 = _get_desired_front(regiment, nearby_enemy, goal)
	_apply_orientation(regiment, desired_front, delta)

	if regiment.is_combat_locked(sim.time_seconds):
		regiment.state_label = "Holding contact"
		return

	var should_move: bool = bool(movement_plan.get("should_move", false))
	if not should_move:
		regiment.state_label = str(movement_plan.get("label", _get_role_state_label(regiment, brigade)))
		return

	var move_speed: float = ruleset.get_move_speed(regiment, terrain)
	if brigade != null:
		move_speed = _adjust_speed_for_brigade_role(regiment, brigade, move_speed)
	move_speed *= float(movement_plan.get("speed_multiplier", 1.0))
	regiment.state_label = str(movement_plan.get("label", _get_role_state_label(regiment, brigade)))
	regiment.move_toward(goal, move_speed, delta)


func _update_recent_engagement_metrics(regiment: Battalion, delta: float) -> void:
	var current_strength: int = regiment.get_total_strength()
	if regiment.last_strength_sample < 0:
		regiment.last_strength_sample = current_strength
	var losses_since_last_tick: int = max(0, regiment.last_strength_sample - current_strength)
	var loss_ratio: float = float(losses_since_last_tick) / float(max(1, regiment.initial_strength))
	var suppression_gain: float = max(0.0, regiment.suppression - regiment.last_suppression_sample)
	regiment.recent_casualty_rate = move_toward(regiment.recent_casualty_rate, 0.0, delta * 0.24)
	regiment.recent_incoming_pressure = move_toward(regiment.recent_incoming_pressure, 0.0, delta * 0.22)
	regiment.recent_casualty_rate = clamp(regiment.recent_casualty_rate + loss_ratio * 5.2, 0.0, 1.0)
	regiment.recent_incoming_pressure = clamp(regiment.recent_incoming_pressure + suppression_gain * 0.8 + loss_ratio * 4.6, 0.0, 1.0)
	regiment.recent_effective_losses = clamp(max(regiment.recent_casualty_rate, regiment.recent_incoming_pressure * 0.9), 0.0, 1.0)
	regiment.last_strength_sample = current_strength
	regiment.last_suppression_sample = regiment.suppression


func _resolve_engagement_target(
		sim: BattleSimulation,
		regiment: Battalion,
		nearest_enemy: Battalion,
		doctrine: BehaviorDoctrine
) -> Battalion:
	var current_target: Battalion = sim.regiments.get(regiment.engagement_target_regiment_id)
	if current_target != null and (current_target.is_destroyed or current_target.army_id == regiment.army_id):
		current_target = null
		regiment.engagement_target_regiment_id = &""
	if nearest_enemy == null:
		if current_target != null and regiment.engagement_state in [
			SimTypes.EngagementState.ASSAULT,
			SimTypes.EngagementState.DISENGAGE,
			SimTypes.EngagementState.RECOVER,
		]:
			var target_distance: float = regiment.position.distance_to(current_target.position)
			if target_distance <= regiment.get_vision_range() * 1.35:
				return current_target
		regiment.engagement_target_regiment_id = &""
		return null
	if current_target == null:
		regiment.engagement_target_regiment_id = nearest_enemy.id
		regiment.target_switch_cooldown_until = sim.time_seconds + 2.4
		regiment.engagement_anchor_position = regiment.position
		return nearest_enemy
	if current_target == nearest_enemy:
		return current_target
	var current_distance: float = regiment.position.distance_to(current_target.position)
	var nearest_distance: float = regiment.position.distance_to(nearest_enemy.position)
	if regiment.has_significant_firearm_capability() and regiment.engagement_state in [
		SimTypes.EngagementState.APPROACH,
		SimTypes.EngagementState.DEPLOY_FIRE,
		SimTypes.EngagementState.FIREFIGHT,
	]:
		var current_attack_window: float = max(regiment.get_attack_range() * 1.55, regiment.get_vision_range() * 0.42)
		if current_distance <= current_attack_window and nearest_enemy.category != SimTypes.UnitCategory.CAVALRY:
			return current_target
	if sim.time_seconds < regiment.target_switch_cooldown_until and current_distance <= regiment.get_vision_range() * 1.25:
		return current_target
	if current_distance > regiment.get_vision_range() * 1.3 \
			or nearest_distance <= current_distance * max(0.58, doctrine.retarget_distance_ratio * 0.82):
		regiment.engagement_target_regiment_id = nearest_enemy.id
		regiment.target_switch_cooldown_until = sim.time_seconds + 2.8
		regiment.engagement_anchor_position = regiment.position
		return nearest_enemy
	return current_target


func _resolve_engagement_state(
		sim: BattleSimulation,
		regiment: Battalion,
		nearby_enemy: Battalion,
		nearby_enemy_distance: float,
		doctrine: BehaviorDoctrine,
		forced_retreat: bool
) -> int:
	if regiment.is_charge_retreating(sim.time_seconds):
		return SimTypes.EngagementState.DISENGAGE
	if regiment.is_charge_recovering(sim.time_seconds):
		return SimTypes.EngagementState.RECOVER
	if regiment.is_combat_locked(sim.time_seconds):
		return SimTypes.EngagementState.ASSAULT
	if forced_retreat:
		return SimTypes.EngagementState.DISENGAGE
	if nearby_enemy == null:
		if regiment.engagement_state == SimTypes.EngagementState.DISENGAGE and sim.time_seconds < regiment.engagement_hold_until:
			return SimTypes.EngagementState.DISENGAGE
		if regiment.engagement_state == SimTypes.EngagementState.RECOVER and sim.time_seconds < regiment.engagement_hold_until:
			return SimTypes.EngagementState.RECOVER
		return SimTypes.EngagementState.NO_CONTACT

	var effective_fire_range: float = max(24.0, ruleset.get_effective_fire_range(regiment))
	var fire_hold_distance: float = effective_fire_range * doctrine.fire_hold_distance_ratio
	var tactical_contact_distance: float = regiment.get_tactical_contact_distance(nearby_enemy)
	var assault_distance: float = regiment.get_close_engagement_distance(nearby_enemy) * doctrine.assault_distance_ratio
	var confidence: float = _get_engagement_confidence(regiment)
	var should_disengage: bool = _should_disengage_from_pressure(regiment, doctrine)
	var static_order: bool = regiment.current_order_type in [SimTypes.OrderType.DEFEND, SimTypes.OrderType.HOLD]
	var state_locked: bool = sim.time_seconds < regiment.engagement_hold_until

	if regiment.engagement_state == SimTypes.EngagementState.DISENGAGE and state_locked:
		return SimTypes.EngagementState.DISENGAGE
	if regiment.engagement_state == SimTypes.EngagementState.RECOVER and state_locked:
		return SimTypes.EngagementState.RECOVER
	if regiment.engagement_state == SimTypes.EngagementState.ASSAULT \
			and state_locked \
			and nearby_enemy_distance <= tactical_contact_distance * 1.45:
		return SimTypes.EngagementState.ASSAULT

	if regiment.has_significant_firearm_capability():
		if should_disengage:
			if doctrine.shock_contact_mode == SimTypes.ShockContactMode.ASSAULT \
					and regiment.can_commit_assault() \
					and nearby_enemy_distance <= assault_distance \
					and confidence >= doctrine.assault_confidence_threshold:
				return SimTypes.EngagementState.ASSAULT
			return SimTypes.EngagementState.DISENGAGE
		if doctrine.firearm_contact_mode == SimTypes.FirearmContactMode.PRESS_IMMEDIATELY \
				and regiment.can_commit_assault() \
				and nearby_enemy_distance <= tactical_contact_distance * 1.2 \
				and confidence >= doctrine.assault_confidence_threshold - 0.08:
			return SimTypes.EngagementState.ASSAULT
		if regiment.can_commit_assault() \
				and nearby_enemy.category == SimTypes.UnitCategory.ARTILLERY \
				and nearby_enemy_distance <= assault_distance \
				and confidence >= doctrine.assault_confidence_threshold + 0.04:
			return SimTypes.EngagementState.ASSAULT
		var fire_ready_distance: float = max(
			fire_hold_distance,
			min(regiment.get_attack_range() * 0.92, tactical_contact_distance * 1.08)
		)
		if nearby_enemy_distance <= fire_ready_distance \
				or (regiment.is_firefight_engaged() and nearby_enemy_distance <= effective_fire_range * 1.15) \
				or (state_locked and regiment.is_firefight_engaged() and nearby_enemy_distance <= effective_fire_range * 1.22):
			return SimTypes.EngagementState.FIREFIGHT if regiment.can_use_structured_fire_behavior(sim.time_seconds) else SimTypes.EngagementState.DEPLOY_FIRE
		if static_order:
			return SimTypes.EngagementState.NO_CONTACT
		if doctrine.firearm_contact_mode == SimTypes.FirearmContactMode.ADVANCE_BY_FIRE and nearby_enemy_distance <= effective_fire_range * 1.1:
			return SimTypes.EngagementState.DEPLOY_FIRE
		return SimTypes.EngagementState.APPROACH

	if should_disengage and doctrine.shock_contact_mode == SimTypes.ShockContactMode.WITHDRAW:
		return SimTypes.EngagementState.DISENGAGE
	if regiment.can_commit_assault() \
			and (nearby_enemy_distance <= assault_distance \
			or (regiment.current_order_type == SimTypes.OrderType.ATTACK and nearby_enemy_distance <= tactical_contact_distance * 1.2)):
		return SimTypes.EngagementState.ASSAULT
	if static_order:
		return SimTypes.EngagementState.NO_CONTACT
	return SimTypes.EngagementState.APPROACH


func _apply_engagement_state_transition(
		regiment: Battalion,
		new_state: int,
		current_time_seconds: float,
		doctrine: BehaviorDoctrine
) -> void:
	var hold_until: float = -1.0
	match new_state:
		SimTypes.EngagementState.DISENGAGE:
			hold_until = current_time_seconds + max(1.4, doctrine.state_hold_duration)
		SimTypes.EngagementState.RECOVER:
			hold_until = current_time_seconds + doctrine.recovery_duration
		SimTypes.EngagementState.ASSAULT:
			hold_until = current_time_seconds + max(1.0, doctrine.state_hold_duration)
		SimTypes.EngagementState.DEPLOY_FIRE, SimTypes.EngagementState.FIREFIGHT:
			hold_until = current_time_seconds + doctrine.state_hold_duration
		_:
			hold_until = -1.0
	if regiment.engagement_state != new_state:
		regiment.engagement_state = new_state
		regiment.engagement_state_since = current_time_seconds
		regiment.engagement_hold_until = hold_until
		if new_state in [
			SimTypes.EngagementState.DEPLOY_FIRE,
			SimTypes.EngagementState.FIREFIGHT,
			SimTypes.EngagementState.DISENGAGE,
			SimTypes.EngagementState.RECOVER,
		]:
			regiment.engagement_anchor_position = regiment.position
		if new_state == SimTypes.EngagementState.NO_CONTACT:
			regiment.engagement_target_regiment_id = &""
		return
	if hold_until > 0.0:
		regiment.engagement_hold_until = max(regiment.engagement_hold_until, hold_until)


func _resolve_engagement_formation(regiment: Battalion, nearby_enemy: Battalion, nearby_enemy_distance: float) -> Dictionary:
	var desired_formation_type: int = regiment.formation.formation_type
	var desired_formation_state: int = regiment.formation_state
	var urgent_reform: bool = false
	if ruleset.should_form_square(regiment, nearby_enemy, nearby_enemy_distance):
		return {
			"formation_type": SimTypes.FormationType.SQUARE,
			"formation_state": SimTypes.RegimentFormationState.PROTECTED,
			"urgent": true,
		}
	match regiment.engagement_state:
		SimTypes.EngagementState.DEPLOY_FIRE, SimTypes.EngagementState.FIREFIGHT:
			if regiment.category == SimTypes.UnitCategory.ARTILLERY:
				desired_formation_type = SimTypes.FormationType.LINE
				desired_formation_state = SimTypes.RegimentFormationState.DEFAULT
			elif regiment.category == SimTypes.UnitCategory.INFANTRY and regiment.has_significant_firearm_capability():
				desired_formation_type = SimTypes.FormationType.LINE
				desired_formation_state = SimTypes.RegimentFormationState.MUSKETEER_LINE if regiment.has_pike_and_shot_companies() else SimTypes.RegimentFormationState.DEFAULT
			else:
				desired_formation_type = regiment.get_preferred_attack_formation()
				desired_formation_state = SimTypes.RegimentFormationState.DEFAULT
			urgent_reform = regiment.formation_state == SimTypes.RegimentFormationState.MARCH_COLUMN \
				or regiment.formation.formation_type == SimTypes.FormationType.COLUMN
		SimTypes.EngagementState.ASSAULT:
			desired_formation_type = regiment.get_preferred_attack_formation()
			desired_formation_state = SimTypes.RegimentFormationState.DEFAULT
			urgent_reform = nearby_enemy != null and nearby_enemy_distance <= regiment.get_close_engagement_distance(nearby_enemy) * 1.15
		SimTypes.EngagementState.DISENGAGE:
			desired_formation_type = SimTypes.FormationType.LINE if regiment.category != SimTypes.UnitCategory.CAVALRY else regiment.get_preferred_attack_formation()
			desired_formation_state = SimTypes.RegimentFormationState.DEFAULT
		_:
			if regiment.current_order_type == SimTypes.OrderType.MARCH:
				desired_formation_type = SimTypes.FormationType.COLUMN
				desired_formation_state = SimTypes.RegimentFormationState.MARCH_COLUMN
			elif regiment.current_order_type == SimTypes.OrderType.ATTACK:
				desired_formation_type = regiment.get_preferred_attack_formation()
				desired_formation_state = SimTypes.RegimentFormationState.DEFAULT
			elif regiment.current_order_type in [SimTypes.OrderType.DEFEND, SimTypes.OrderType.HOLD]:
				desired_formation_type = SimTypes.FormationType.LINE
				desired_formation_state = SimTypes.RegimentFormationState.DEFAULT
	if regiment.order_policies.get("deploy_on_contact", false) \
			and nearby_enemy != null \
			and ruleset.should_deploy_on_contact(regiment, nearby_enemy_distance) \
			and regiment.engagement_state in [
				SimTypes.EngagementState.APPROACH,
				SimTypes.EngagementState.DEPLOY_FIRE,
				SimTypes.EngagementState.FIREFIGHT,
			]:
		if regiment.category == SimTypes.UnitCategory.ARTILLERY:
			desired_formation_type = SimTypes.FormationType.LINE
			desired_formation_state = SimTypes.RegimentFormationState.DEFAULT
		elif regiment.category == SimTypes.UnitCategory.INFANTRY and regiment.has_significant_firearm_capability():
			desired_formation_type = SimTypes.FormationType.LINE
			desired_formation_state = SimTypes.RegimentFormationState.MUSKETEER_LINE if regiment.has_pike_and_shot_companies() else SimTypes.RegimentFormationState.DEFAULT
		else:
			desired_formation_type = regiment.get_preferred_attack_formation()
			desired_formation_state = SimTypes.RegimentFormationState.DEFAULT
		urgent_reform = true
	return {
		"formation_type": desired_formation_type,
		"formation_state": desired_formation_state,
		"urgent": urgent_reform,
	}


func _resolve_engagement_fire_behavior(regiment: Battalion, nearby_enemy: Battalion, current_time_seconds: float) -> int:
	if nearby_enemy == null:
		return SimTypes.RegimentFireBehavior.NONE
	if not [
		SimTypes.EngagementState.DEPLOY_FIRE,
		SimTypes.EngagementState.FIREFIGHT,
	].has(regiment.engagement_state):
		return SimTypes.RegimentFireBehavior.NONE
	if not regiment.can_use_structured_fire_behavior(current_time_seconds):
		return SimTypes.RegimentFireBehavior.NONE
	if regiment.formation_state == SimTypes.RegimentFormationState.PROTECTED or regiment.formation.formation_type == SimTypes.FormationType.SQUARE:
		return SimTypes.RegimentFireBehavior.VOLLEY
	return regiment.get_preferred_fire_behavior()


func _resolve_movement_plan(
		sim: BattleSimulation,
		regiment: Battalion,
		brigade: Brigade,
		base_goal: Vector2,
		nearby_enemy: Battalion,
		doctrine: BehaviorDoctrine
) -> Dictionary:
	var goal: Vector2 = base_goal
	var should_move: bool = false
	var speed_multiplier: float = 1.0
	var label: String = _get_role_state_label(regiment, brigade)
	match regiment.engagement_state:
		SimTypes.EngagementState.APPROACH:
			label = "Approaching contact"
			if nearby_enemy != null and regiment.current_order_type == SimTypes.OrderType.ATTACK:
				var support_blocker: Battalion = _find_frontline_friendly_blocker(sim, regiment, nearby_enemy)
				if support_blocker != null and regiment.category == SimTypes.UnitCategory.INFANTRY and regiment.has_significant_firearm_capability():
					label = "Taking support line"
					goal = _build_support_fire_goal(regiment, nearby_enemy, support_blocker)
					speed_multiplier = 0.58
				else:
					goal = _build_contact_goal(sim, regiment, nearby_enemy, false)
			should_move = regiment.current_order_type in [
				SimTypes.OrderType.MOVE,
				SimTypes.OrderType.MARCH,
				SimTypes.OrderType.ATTACK,
				SimTypes.OrderType.PATROL,
			]
			should_move = should_move or (regiment.current_order_type in [SimTypes.OrderType.DEFEND, SimTypes.OrderType.HOLD] and regiment.position.distance_to(goal) > 10.0)
			if nearby_enemy != null:
				var goal_tolerance: float = _get_contact_goal_tolerance(regiment, nearby_enemy, false)
				if label == "Taking support line":
					goal_tolerance = max(goal_tolerance, doctrine.firefight_anchor_leash * 1.35)
				should_move = should_move and regiment.position.distance_to(goal) > goal_tolerance
		SimTypes.EngagementState.DEPLOY_FIRE:
			label = "Deploying to fire"
			goal = regiment.engagement_anchor_position
			should_move = regiment.is_reforming(sim.time_seconds) or regiment.position.distance_to(goal) > 4.0
			speed_multiplier = 0.42
		SimTypes.EngagementState.FIREFIGHT:
			label = "Firefight"
			goal = regiment.engagement_anchor_position
			should_move = regiment.position.distance_to(goal) > doctrine.firefight_anchor_leash
			speed_multiplier = 0.32
		SimTypes.EngagementState.ASSAULT:
			label = "Assaulting"
			if nearby_enemy != null:
				goal = _build_contact_goal(sim, regiment, nearby_enemy, true)
				should_move = regiment.position.distance_to(goal) > _get_contact_goal_tolerance(regiment, nearby_enemy, true)
			else:
				should_move = false
			speed_multiplier = 0.98
		SimTypes.EngagementState.DISENGAGE:
			label = "Disengaging"
			goal = _build_disengage_goal(sim, regiment, nearby_enemy, doctrine, base_goal)
			should_move = true
			speed_multiplier = 0.62
		SimTypes.EngagementState.RECOVER:
			label = "Recovering"
			if regiment.is_charge_retreating(sim.time_seconds):
				goal = regiment.charge_retreat_target_position
				should_move = regiment.position.distance_to(goal) > 10.0
				speed_multiplier = 0.74
			else:
				goal = regiment.engagement_anchor_position
				should_move = regiment.position.distance_to(goal) > 5.0
				speed_multiplier = 0.36
		_:
			should_move = regiment.current_order_type in [
				SimTypes.OrderType.MOVE,
				SimTypes.OrderType.MARCH,
				SimTypes.OrderType.ATTACK,
				SimTypes.OrderType.PATROL,
			]
			should_move = should_move or (regiment.current_order_type in [SimTypes.OrderType.DEFEND, SimTypes.OrderType.HOLD] and regiment.position.distance_to(goal) > 10.0)
	if brigade != null and regiment.brigade_role == SimTypes.BrigadeRole.RESERVE and not brigade.reserve_committed:
		if regiment.engagement_state in [SimTypes.EngagementState.NO_CONTACT, SimTypes.EngagementState.APPROACH]:
			should_move = should_move and regiment.position.distance_to(goal) > 14.0
	if should_move and nearby_enemy == null:
		goal = _apply_friendly_deconfliction(sim, regiment, goal)
	return {
		"goal": goal,
		"should_move": should_move,
		"speed_multiplier": speed_multiplier,
		"label": label,
	}


func _build_disengage_goal(
		sim: BattleSimulation,
		regiment: Battalion,
		nearby_enemy: Battalion,
		doctrine: BehaviorDoctrine,
		base_goal: Vector2
) -> Vector2:
	if regiment.is_charge_retreating(sim.time_seconds):
		return regiment.charge_retreat_target_position
	if nearby_enemy == null:
		return sim.get_army_fallback_position(regiment.army_id)
	var retreat_direction: Vector2 = (regiment.position - nearby_enemy.position).normalized()
	if retreat_direction.length_squared() <= 0.001:
		retreat_direction = -regiment.front_direction.normalized()
	if retreat_direction.length_squared() <= 0.001:
		retreat_direction = Vector2.LEFT
	var fallback_bias: Vector2 = (sim.get_army_fallback_position(regiment.army_id) - regiment.position).normalized()
	if fallback_bias.length_squared() > 0.001:
		retreat_direction = retreat_direction.lerp(fallback_bias, 0.35).normalized()
	return regiment.position + retreat_direction * max(doctrine.withdraw_distance, regiment.get_close_engagement_distance(nearby_enemy) * 1.5)


func _build_contact_goal(sim: BattleSimulation, regiment: Battalion, nearby_enemy: Battalion, prefer_close_contact: bool) -> Vector2:
	if nearby_enemy == null:
		return regiment.current_target_position
	var enemy_front: Vector2 = nearby_enemy.front_direction.normalized()
	if enemy_front.length_squared() <= 0.001:
		enemy_front = (nearby_enemy.position - regiment.position).normalized()
	if enemy_front.length_squared() <= 0.001:
		enemy_front = Vector2.RIGHT
	var right_axis: Vector2 = Vector2(-enemy_front.y, enemy_front.x).normalized()
	var lane_offset: float = _resolve_contact_lane_offset(sim, regiment, nearby_enemy, right_axis)
	var relative_offset: Vector2 = regiment.position - nearby_enemy.position
	var front_projection: float = relative_offset.dot(enemy_front)
	var lateral_projection: float = relative_offset.dot(right_axis)
	var enemy_half_frontage: float = max(28.0, nearby_enemy.formation.frontage * 0.5)
	var enemy_half_depth: float = max(20.0, nearby_enemy.formation.depth * 0.5)
	var contact_normal: Vector2 = enemy_front
	var shell_anchor: Vector2 = nearby_enemy.position + right_axis * clamp(lane_offset, -enemy_half_frontage * 0.82, enemy_half_frontage * 0.82)
	if absf(lateral_projection) > absf(front_projection) * 1.1:
		contact_normal = right_axis if lateral_projection >= 0.0 else -right_axis
		shell_anchor = nearby_enemy.position \
			+ contact_normal * enemy_half_frontage \
			+ enemy_front * clamp(front_projection, -enemy_half_depth * 0.7, enemy_half_depth * 0.7)
	else:
		contact_normal = enemy_front if front_projection >= 0.0 else -enemy_front
		shell_anchor += contact_normal * enemy_half_depth
	var own_shell_depth: float = max(12.0, regiment.formation.depth * 0.46)
	var physical_spacing: float = own_shell_depth + (8.0 if prefer_close_contact else 18.0)
	var desired_spacing: float = physical_spacing
	if not prefer_close_contact and regiment.has_significant_firearm_capability():
		desired_spacing = max(regiment.get_tactical_contact_distance(nearby_enemy) * 0.22, physical_spacing)
	elif prefer_close_contact:
		desired_spacing = max(regiment.get_close_engagement_distance(nearby_enemy) * 0.16, physical_spacing)
	return shell_anchor + contact_normal * desired_spacing


func _find_frontline_friendly_blocker(sim: BattleSimulation, regiment: Battalion, nearby_enemy: Battalion) -> Battalion:
	if nearby_enemy == null:
		return null
	var enemy_front: Vector2 = (nearby_enemy.position - regiment.position).normalized()
	if enemy_front.length_squared() <= 0.001:
		enemy_front = nearby_enemy.front_direction.normalized()
	if enemy_front.length_squared() <= 0.001:
		enemy_front = Vector2.RIGHT
	var lateral_axis: Vector2 = Vector2(-enemy_front.y, enemy_front.x).normalized()
	var regiment_distance: float = regiment.position.distance_to(nearby_enemy.position)
	var best_blocker: Battalion = null
	var best_distance: float = INF
	for other_value in sim.regiments.values():
		var other: Battalion = other_value
		if other == regiment or other.is_destroyed or other.army_id != regiment.army_id:
			continue
		if other.engagement_target_regiment_id != nearby_enemy.id:
			continue
		if other.engagement_state not in [
			SimTypes.EngagementState.DEPLOY_FIRE,
			SimTypes.EngagementState.FIREFIGHT,
			SimTypes.EngagementState.ASSAULT,
		]:
			continue
		var other_distance: float = other.position.distance_to(nearby_enemy.position)
		if other_distance >= regiment_distance - 12.0:
			continue
		var lateral_distance: float = absf((other.position - nearby_enemy.position).dot(lateral_axis))
		var coverage_width: float = max(other.formation.frontage, other.formation.depth) * 0.72 + max(regiment.formation.frontage, regiment.formation.depth) * 0.34
		if lateral_distance > coverage_width:
			continue
		if other_distance < best_distance:
			best_distance = other_distance
			best_blocker = other
	return best_blocker


func _build_support_fire_goal(regiment: Battalion, nearby_enemy: Battalion, blocker: Battalion) -> Vector2:
	var away_from_enemy: Vector2 = (blocker.position - nearby_enemy.position).normalized()
	if away_from_enemy.length_squared() <= 0.001:
		away_from_enemy = (-nearby_enemy.front_direction).normalized()
	if away_from_enemy.length_squared() <= 0.001:
		away_from_enemy = regiment.front_direction.normalized()
	if away_from_enemy.length_squared() <= 0.001:
		away_from_enemy = Vector2.LEFT
	var lateral_axis: Vector2 = Vector2(-away_from_enemy.y, away_from_enemy.x).normalized()
	var support_depth: float = max(
		max(blocker.formation.depth, blocker.formation.frontage) * 0.52,
		max(regiment.formation.depth, regiment.formation.frontage) * 0.42
	) + 24.0
	var lateral_offset: float = (regiment.position - blocker.position).dot(lateral_axis)
	lateral_offset = clamp(lateral_offset, -42.0, 42.0)
	return blocker.position + away_from_enemy * support_depth + lateral_axis * lateral_offset * 0.35


func _resolve_contact_lane_offset(sim: BattleSimulation, regiment: Battalion, nearby_enemy: Battalion, right_axis: Vector2) -> float:
	var assigned_friendlies: Array = [regiment]
	for other_value in sim.regiments.values():
		var other: Battalion = other_value
		if other == regiment or other.is_destroyed or other.army_id != regiment.army_id:
			continue
		if other.engagement_target_regiment_id != nearby_enemy.id:
			continue
		if other.engagement_state == SimTypes.EngagementState.NO_CONTACT:
			continue
		assigned_friendlies.append(other)
	assigned_friendlies.sort_custom(func(a: Battalion, b: Battalion) -> bool:
		var a_priority: float = _get_contact_lane_priority(a)
		var b_priority: float = _get_contact_lane_priority(b)
		if not is_equal_approx(a_priority, b_priority):
			return a_priority < b_priority
		var a_lateral: float = (a.position - nearby_enemy.position).dot(right_axis)
		var b_lateral: float = (b.position - nearby_enemy.position).dot(right_axis)
		if not is_equal_approx(a_lateral, b_lateral):
			return a_lateral < b_lateral
		return String(a.id) < String(b.id)
	)
	var slot_index: int = assigned_friendlies.find(regiment)
	if slot_index < 0:
		return 0.0
	var centered_index: float = float(slot_index) - float(assigned_friendlies.size() - 1) * 0.5
	var own_width: float = max(56.0, min(max(regiment.formation.frontage, regiment.formation.depth), 150.0))
	var enemy_width: float = max(64.0, min(max(nearby_enemy.formation.frontage, nearby_enemy.formation.depth), 180.0))
	var slot_spacing: float = clamp(own_width * 0.72 + enemy_width * 0.34, 72.0, 152.0)
	return centered_index * slot_spacing


func _get_contact_lane_priority(regiment: Battalion) -> float:
	match regiment.brigade_role:
		SimTypes.BrigadeRole.LEFT_FLANK:
			return -1.5
		SimTypes.BrigadeRole.RIGHT_FLANK:
			return 1.5
		SimTypes.BrigadeRole.RESERVE:
			return 0.75
		SimTypes.BrigadeRole.SUPPORT_ARTILLERY:
			return 0.2
		_:
			return 0.0


func _get_contact_goal_tolerance(regiment: Battalion, nearby_enemy: Battalion, prefer_close_contact: bool) -> float:
	var desired_spacing: float = regiment.get_close_engagement_distance(nearby_enemy) if prefer_close_contact else regiment.get_tactical_contact_distance(nearby_enemy)
	return clamp(desired_spacing * 0.24, 12.0, 28.0)


func _get_engagement_confidence(regiment: Battalion) -> float:
	var base_confidence: float = 0.0
	base_confidence += regiment.morale * 0.32
	base_confidence += regiment.cohesion * 0.28
	base_confidence += regiment.get_strength_ratio() * 0.18
	base_confidence += regiment.commander_quality * 0.16
	base_confidence -= regiment.suppression * 0.24
	base_confidence -= regiment.recent_effective_losses * 0.28
	return clamp(base_confidence, 0.0, 1.0)


func _should_disengage_from_pressure(regiment: Battalion, doctrine: BehaviorDoctrine) -> bool:
	if regiment.suppression >= doctrine.disengage_suppression_threshold:
		return true
	if regiment.recent_casualty_rate >= doctrine.disengage_casualty_rate_threshold:
		return true
	if regiment.recent_effective_losses >= max(doctrine.disengage_casualty_rate_threshold * 1.15, 0.1):
		return true
	if regiment.morale <= 0.26 or regiment.cohesion <= 0.24:
		return true
	return false


func _get_visible_enemy(sim: BattleSimulation, regiment: Battalion) -> Battalion:
	var corridor_enemy: Battalion = _find_frontline_enemy_in_approach_corridor(sim, regiment)
	if corridor_enemy != null:
		var corridor_distance: float = regiment.position.distance_to(corridor_enemy.position)
		if corridor_distance <= regiment.get_vision_range() * 1.1 \
				and sim.sampled_visibility_between_battalions(regiment, corridor_enemy, 5) >= 0.2:
			return corridor_enemy
	var nearest_enemy: Battalion = sim.find_nearest_enemy(regiment)
	if nearest_enemy == null:
		return null
	var distance: float = regiment.position.distance_to(nearest_enemy.position)
	if distance > regiment.get_vision_range() * 1.1:
		return null
	if sim.sampled_visibility_between_battalions(regiment, nearest_enemy, 5) < 0.2:
		return null
	return nearest_enemy


func _find_frontline_enemy_in_approach_corridor(sim: BattleSimulation, regiment: Battalion) -> Battalion:
	var desired_direction: Vector2 = (regiment.current_target_position - regiment.position).normalized()
	if desired_direction.length_squared() <= 0.001:
		desired_direction = regiment.front_direction.normalized()
	if desired_direction.length_squared() <= 0.001:
		desired_direction = Vector2.UP
	var lateral_axis: Vector2 = Vector2(-desired_direction.y, desired_direction.x).normalized()
	var best_enemy: Battalion = null
	var best_ahead_distance: float = INF
	for candidate_value in sim.regiments.values():
		var candidate: Battalion = candidate_value
		if candidate.is_destroyed or candidate.army_id == regiment.army_id:
			continue
		var offset: Vector2 = candidate.position - regiment.position
		var ahead_distance: float = offset.dot(desired_direction)
		if ahead_distance <= 8.0:
			continue
		var lateral_distance: float = absf(offset.dot(lateral_axis))
		var corridor_width: float = max(regiment.formation.frontage, regiment.formation.depth) * 0.46 \
			+ max(candidate.formation.frontage, candidate.formation.depth) * 0.42
		if lateral_distance > corridor_width:
			continue
		if ahead_distance < best_ahead_distance:
			best_ahead_distance = ahead_distance
			best_enemy = candidate
	return best_enemy


func _get_desired_front(regiment: Battalion, nearby_enemy: Battalion, goal: Vector2) -> Vector2:
	if nearby_enemy != null:
		var enemy_direction: Vector2 = (nearby_enemy.position - regiment.position).normalized()
		if enemy_direction.length_squared() > 0.001:
			return enemy_direction
	var move_direction: Vector2 = (goal - regiment.position).normalized()
	if move_direction.length_squared() > 0.001:
		return move_direction
	return regiment.front_direction.normalized() if regiment.front_direction.length_squared() > 0.001 else Vector2.RIGHT


func _apply_orientation(regiment: Battalion, desired_front: Vector2, delta: float) -> void:
	var front: Vector2 = desired_front.normalized()
	if front.length_squared() <= 0.001:
		return
	regiment.front_direction = regiment.front_direction.lerp(front, min(1.0, delta * 6.0)).normalized()
	var desired_angle: float = front.angle() + PI * 0.5
	regiment.formation.orientation = lerp_angle(regiment.formation.orientation, desired_angle, min(1.0, delta * 6.0))


func _request_behavior_formation(regiment: Battalion, formation_type: int, formation_state: int, current_time_seconds: float, urgent: bool = false) -> void:
	if not urgent and regiment.is_reforming(current_time_seconds):
		return
	if not urgent \
			and regiment.desired_formation_type == formation_type \
			and regiment.desired_formation_state == formation_state:
		return
	regiment.request_formation_change(formation_type, formation_state, current_time_seconds, urgent)


func _apply_debug_overrides(regiment: Battalion) -> void:
	if regiment.has_debug_forced_formation():
		regiment.formation_state = regiment.debug_forced_formation_state
		match regiment.debug_forced_formation_state:
			SimTypes.RegimentFormationState.MARCH_COLUMN:
				regiment.formation.set_type(SimTypes.FormationType.COLUMN)
			SimTypes.RegimentFormationState.PROTECTED:
				regiment.formation.set_type(SimTypes.FormationType.SQUARE)
			_:
				regiment.formation.set_type(SimTypes.FormationType.LINE)
		regiment.desired_formation_type = regiment.formation.formation_type
		regiment.desired_formation_state = regiment.formation_state
		regiment.mark_target_layout_dirty()
	if regiment.has_debug_forced_fire_behavior():
		regiment.fire_behavior = regiment.debug_forced_fire_behavior


func _adjust_goal_for_brigade_role(regiment: Battalion, brigade: Brigade, goal: Vector2) -> Vector2:
	match regiment.brigade_role:
		SimTypes.BrigadeRole.SUPPORT_ARTILLERY:
			return goal
		SimTypes.BrigadeRole.RESERVE:
			if brigade.reserve_committed:
				return goal
			return ruleset.get_reserve_goal(regiment, goal)
		_:
			return goal


func _adjust_speed_for_brigade_role(regiment: Battalion, brigade: Brigade, move_speed: float) -> float:
	match regiment.brigade_role:
		SimTypes.BrigadeRole.RESERVE:
			return move_speed * (0.88 if not brigade.reserve_committed else 1.02)
		SimTypes.BrigadeRole.SUPPORT_ARTILLERY:
			return move_speed * 0.82
		SimTypes.BrigadeRole.LEFT_FLANK, SimTypes.BrigadeRole.RIGHT_FLANK:
			return move_speed * 1.04
		_:
			return move_speed


func _get_role_state_label(regiment: Battalion, brigade: Brigade) -> String:
	if regiment.current_order_type in [SimTypes.OrderType.DEFEND, SimTypes.OrderType.HOLD]:
		return "Holding reserve" if brigade != null and regiment.brigade_role == SimTypes.BrigadeRole.RESERVE and not brigade.reserve_committed else "Taking position"
	match regiment.brigade_role:
		SimTypes.BrigadeRole.LEFT_FLANK:
			return "Extending left flank"
		SimTypes.BrigadeRole.RIGHT_FLANK:
			return "Extending right flank"
		SimTypes.BrigadeRole.RESERVE:
			return "Holding reserve" if brigade != null and not brigade.reserve_committed else "Committing reserve"
		SimTypes.BrigadeRole.SUPPORT_ARTILLERY:
			return "Taking support line"
		_:
			return SimTypes.order_type_name(regiment.current_order_type)


func _apply_friendly_deconfliction(sim: BattleSimulation, regiment: Battalion, goal: Vector2) -> Vector2:
	var to_goal: Vector2 = goal - regiment.position
	if to_goal.length() <= 1.0:
		return goal
	var desired_direction: Vector2 = to_goal.normalized()
	var lateral: Vector2 = Vector2(-desired_direction.y, desired_direction.x)
	var strongest_blocker: Battalion = null
	var best_score: float = -INF
	for other_value in sim.regiments.values():
		var other: Battalion = other_value
		if other == regiment or other.is_destroyed or other.army_id != regiment.army_id:
			continue
		var offset: Vector2 = other.position - regiment.position
		var ahead_distance: float = offset.dot(desired_direction)
		if ahead_distance <= 4.0 or ahead_distance >= 220.0:
			continue
		var lateral_distance: float = absf(offset.dot(lateral))
		var clearance_width: float = (max(regiment.formation.frontage, regiment.formation.depth) + max(other.formation.frontage, other.formation.depth)) * 0.5
		if lateral_distance >= clearance_width:
			continue
		var same_brigade_bonus: float = 18.0 if other.brigade_id == regiment.brigade_id else 0.0
		var score: float = 150.0 - ahead_distance - lateral_distance + same_brigade_bonus
		if score > best_score:
			best_score = score
			strongest_blocker = other
	if strongest_blocker == null:
		return goal
	var blocker_offset: Vector2 = strongest_blocker.position - regiment.position
	var blocker_side: float = blocker_offset.dot(lateral)
	var side_sign: float = -1.0 if blocker_side > 2.0 else 1.0
	if absf(blocker_side) <= 2.0:
		side_sign = -1.0 if hash(String(regiment.id)) % 2 == 0 else 1.0
	var sidestep_distance: float = max(max(regiment.formation.frontage, regiment.formation.depth) * 0.55, 48.0)
	return goal + lateral * side_sign * sidestep_distance


func _tick_brigade_hqs(sim: BattleSimulation, delta: float) -> void:
	for brigade in sim.brigades.values():
		var brigade_hq: HQ = sim.hqs.get(brigade.hq_id)
		if brigade_hq == null:
			continue
		var anchor_position: Vector2 = sim.get_brigade_anchor_position(brigade)
		var desired_offset: Vector2 = sim.get_brigade_hq_offset(brigade)
		var target_position: Vector2 = anchor_position + desired_offset
		brigade_hq.move_toward(target_position, brigade_hq.mobility, delta)


func _resolve_regiment_overlap(sim: BattleSimulation) -> void:
	var active_regiments: Array = []
	var current_time: float = sim.time_seconds
	for regiment in sim.regiments.values():
		if regiment.is_destroyed:
			continue
		active_regiments.append(regiment)
	for i in range(active_regiments.size()):
		var left: Battalion = active_regiments[i]
		for j in range(i + 1, active_regiments.size()):
			var right: Battalion = active_regiments[j]
			var same_army: bool = left.army_id == right.army_id
			var offset: Vector2 = right.position - left.position
			var distance: float = offset.length()
			var overlap_scale: float = 0.24 if same_army else 0.22
			var minimum_gap: float = (max(left.formation.frontage, left.formation.depth) + max(right.formation.frontage, right.formation.depth)) * overlap_scale
			if distance >= minimum_gap:
				continue
			var push_direction: Vector2 = Vector2.RIGHT if distance <= 0.001 else offset.normalized()
			if same_army:
				var friendly_correction: float = (minimum_gap - distance) * 0.38
				_resolve_same_army_overlap(sim, left, right, push_direction, friendly_correction, current_time)
				continue
			_resolve_enemy_overlap(left, right, push_direction, distance, minimum_gap, current_time)


func _resolve_enemy_overlap(
		left: Battalion,
		right: Battalion,
		push_direction: Vector2,
		distance: float,
		minimum_gap: float,
		current_time: float
) -> void:
	var tactical_contact_distance: float = max(
		left.get_tactical_contact_distance(right),
		right.get_tactical_contact_distance(left)
	)
	var explicit_contact: bool = left.engagement_target_regiment_id == right.id \
		or right.engagement_target_regiment_id == left.id
	var mutual_contact: bool = left.is_engagement_state_active() and right.is_engagement_state_active()
	var direct_contact: bool = distance <= tactical_contact_distance * 1.15 and (explicit_contact or mutual_contact)
	var allowed_gap: float = minimum_gap * (0.78 if direct_contact else 1.0)
	if distance >= allowed_gap:
		return
	var correction: float = (allowed_gap - distance) * (0.18 if direct_contact else 0.24)
	if correction <= 0.01:
		return
	var left_fixed: bool = left.is_combat_locked(current_time) or left.is_engagement_state_active()
	var right_fixed: bool = right.is_combat_locked(current_time) or right.is_engagement_state_active()
	if direct_contact:
		correction = min(correction, 10.0)
		if left_fixed and not right_fixed:
			right.position += push_direction * correction
			return
		if right_fixed and not left_fixed:
			left.position -= push_direction * correction
			return
		left.position -= push_direction * correction * 0.5
		right.position += push_direction * correction * 0.5
		return
	left.position -= push_direction * correction
	right.position += push_direction * correction


func _resolve_same_army_overlap(sim: BattleSimulation, left: Battalion, right: Battalion, push_direction: Vector2, correction: float, current_time: float) -> void:
	var left_yield_score: float = _get_friendly_yield_score(left, right, push_direction)
	var right_yield_score: float = _get_friendly_yield_score(right, left, -push_direction)
	var mover: Battalion = left
	var blocker: Battalion = right
	var left_fixed: bool = left.is_combat_locked(current_time) or left.is_engagement_state_active()
	var right_fixed: bool = right.is_combat_locked(current_time) or right.is_engagement_state_active()
	var both_fixed: bool = left_fixed and right_fixed
	var shared_target: Battalion = _get_shared_engagement_target(sim, left, right)
	if shared_target != null and (left_fixed or right_fixed):
		var enemy_front: Vector2 = shared_target.front_direction.normalized()
		if enemy_front.length_squared() <= 0.001:
			enemy_front = (shared_target.position - (left.position + right.position) * 0.5).normalized()
		if enemy_front.length_squared() <= 0.001:
			enemy_front = Vector2.RIGHT
		var lateral_axis: Vector2 = Vector2(-enemy_front.y, enemy_front.x).normalized()
		var left_side: float = (left.position - shared_target.position).dot(lateral_axis)
		var right_side: float = (right.position - shared_target.position).dot(lateral_axis)
		var side_sign_left: float = -1.0 if left_side <= right_side else 1.0
		var side_sign_right: float = -side_sign_left
		var lateral_correction: float = clamp(correction * (0.6 if both_fixed else 0.95), 2.0, 10.0)
		if left_fixed and not right_fixed:
			right.position += lateral_axis * side_sign_right * lateral_correction
			return
		if right_fixed and not left_fixed:
			left.position += lateral_axis * side_sign_left * lateral_correction
			return
		left.position += lateral_axis * side_sign_left * lateral_correction * 0.5
		right.position += lateral_axis * side_sign_right * lateral_correction * 0.5
		return
	var adjusted_correction: float = correction * 0.36 if both_fixed else correction
	if left_fixed and not right_fixed:
		mover = right
		blocker = left
	elif right_fixed and not left_fixed:
		mover = left
		blocker = right
	elif right_yield_score > left_yield_score:
		mover = right
		blocker = left
	elif is_equal_approx(right_yield_score, left_yield_score):
		var left_goal_distance: float = left.position.distance_to(left.current_target_position)
		var right_goal_distance: float = right.position.distance_to(right.current_target_position)
		if right_goal_distance > left_goal_distance:
			mover = right
			blocker = left
	var goal_vector: Vector2 = mover.current_target_position - mover.position
	if goal_vector.length() > 1.0:
		var desired_direction: Vector2 = goal_vector.normalized()
		var lateral: Vector2 = Vector2(-desired_direction.y, desired_direction.x)
		var blocker_side: float = (blocker.position - mover.position).dot(lateral)
		var side_sign: float = -1.0 if blocker_side >= 0.0 else 1.0
		var sidestep_distance: float = max(adjusted_correction * (0.55 if both_fixed else 1.25), 4.0 if both_fixed else 6.0)
		var backstep_distance: float = min(adjusted_correction * (0.12 if both_fixed else 0.4), 3.0 if both_fixed else 10.0)
		mover.position += lateral * side_sign * sidestep_distance - desired_direction * backstep_distance
		return
	if mover == left:
		left.position -= push_direction * adjusted_correction
		return
	right.position += push_direction * adjusted_correction


func _get_shared_engagement_target(sim: BattleSimulation, left: Battalion, right: Battalion) -> Battalion:
	if left.engagement_target_regiment_id == &"" or left.engagement_target_regiment_id != right.engagement_target_regiment_id:
		return null
	var target: Battalion = sim.regiments.get(left.engagement_target_regiment_id)
	if target == null or target.is_destroyed:
		return null
	return target


func _get_friendly_yield_score(regiment: Battalion, blocker: Battalion, collision_direction: Vector2) -> float:
	var score: float = 0.0
	if regiment.current_order_type in [
		SimTypes.OrderType.MOVE,
		SimTypes.OrderType.MARCH,
		SimTypes.OrderType.ATTACK,
		SimTypes.OrderType.PATROL,
	]:
		score += 18.0
	if regiment.current_order_type == SimTypes.OrderType.MARCH:
		score += 6.0
	elif regiment.current_order_type in [SimTypes.OrderType.DEFEND, SimTypes.OrderType.HOLD]:
		score -= 14.0
	var goal_vector: Vector2 = regiment.current_target_position - regiment.position
	score += min(goal_vector.length(), 240.0) * 0.08
	if goal_vector.length() > 1.0 and collision_direction.length() > 0.001:
		score += max(goal_vector.normalized().dot(collision_direction.normalized()), 0.0) * 34.0
	if blocker.brigade_id == regiment.brigade_id:
		score += 4.0
	return score
