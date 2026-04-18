class_name GeneralAISystem
extends RefCounted


func tick(sim: BattleSimulation, delta: float) -> void:
	for general in sim.generals.values():
		var typed_general: General = general
		if not typed_general.is_alive:
			continue
		var army: Army = sim.armies.get(typed_general.army_id)
		if army == null or not army.is_ai_controlled:
			continue
		typed_general.next_decision_time = max(0.0, typed_general.next_decision_time - delta)
		if typed_general.next_decision_time > 0.0:
			continue
		typed_general.next_decision_time = typed_general.decision_interval_seconds
		_process_general_decision(sim, typed_general)


func _process_general_decision(sim: BattleSimulation, general: General) -> void:
	var brigade: Brigade = sim.brigades.get(general.brigade_id)
	if brigade == null:
		return
	var brigade_regiments: Array = _get_active_brigade_regiments(sim, brigade)
	if brigade_regiments.is_empty():
		return
	var brigade_center: Vector2 = _get_brigade_center(brigade_regiments)
	var nearest_enemy: Battalion = _find_nearest_enemy_to_position(sim, brigade_center, general.army_id)
	var nearest_enemy_distance: float = brigade_center.distance_to(nearest_enemy.position) if nearest_enemy != null else INF
	var local_enemy_pressure: int = sim.count_enemy_regiments_near(brigade_center, general.army_id, 220.0)
	var local_friendly_support: int = sim.count_friendly_regiments_near(brigade_center, general.army_id, 220.0)
	var threat_vector: Vector2 = _get_local_threat_vector(sim, brigade_center, general.army_id, 320.0)
	var has_flank_threat: bool = _is_flank_threat(brigade, threat_vector)

	if local_enemy_pressure > local_friendly_support + 1 + int(round(general.caution * 2.0)):
		_issue_ai_brigade_order(
			sim,
			brigade,
			SimTypes.OrderType.DEFEND,
			sim.get_army_fallback_position(general.army_id),
			{
				"road_column": false,
				"deploy_on_contact": true,
				"retreat_on_flank_collapse": true,
				"hold_reserve": false,
			}
		)
		return

	if has_flank_threat:
		_issue_ai_defensive_line(
			sim,
			brigade,
			brigade_center,
			threat_vector.normalized(),
			{
				"road_column": false,
				"deploy_on_contact": true,
				"retreat_on_flank_collapse": true,
				"hold_reserve": true,
			}
		)
		return

	var contested_point: StrategicPoint = _find_best_objective(sim, brigade_center, general.army_id)
	if contested_point != null and nearest_enemy_distance > 170.0:
		_issue_ai_brigade_order(
			sim,
			brigade,
			SimTypes.OrderType.MARCH,
			contested_point.position,
			{
				"road_column": true,
				"deploy_on_contact": true,
				"retreat_on_flank_collapse": false,
				"hold_reserve": false,
			}
		)
		return

	if nearest_enemy != null:
		var aggressive_threshold: float = lerpf(150.0, 260.0, general.aggression)
		if nearest_enemy_distance <= aggressive_threshold:
			_issue_ai_brigade_order(
				sim,
				brigade,
				SimTypes.OrderType.ATTACK,
				nearest_enemy.position,
				{
					"road_column": false,
					"deploy_on_contact": true,
					"retreat_on_flank_collapse": local_enemy_pressure > local_friendly_support,
					"hold_reserve": local_enemy_pressure >= local_friendly_support,
				}
			)
			return

	if contested_point != null:
		_issue_ai_brigade_order(
			sim,
			brigade,
			SimTypes.OrderType.MOVE,
			contested_point.position,
			{
				"road_column": true,
				"deploy_on_contact": true,
				"retreat_on_flank_collapse": false,
				"hold_reserve": false,
			}
		)
		return

	_issue_ai_brigade_order(
		sim,
		brigade,
		SimTypes.OrderType.DEFEND,
		brigade_center,
		{
			"road_column": false,
			"deploy_on_contact": true,
			"retreat_on_flank_collapse": true,
			"hold_reserve": true,
		}
	)


func _issue_ai_brigade_order(sim: BattleSimulation, brigade: Brigade, order_type: int, target_position: Vector2, policies: Dictionary) -> void:
	if _brigade_has_pending_order(sim, brigade.id):
		return
	var same_order_type: bool = brigade.current_order_type == order_type
	var same_policies: bool = brigade.order_policies.hash() == policies.hash()
	var current_target: Vector2 = brigade.target_position if brigade.target_position != Vector2.ZERO else sim.brigade_position(brigade)
	if same_order_type and same_policies and current_target.distance_to(target_position) <= 36.0:
		return
	sim.queue_player_command({
		"army_id": String(brigade.army_id),
		"recipient_brigade_id": String(brigade.id),
		"order_type": order_type,
		"target_position": target_position,
		"path_points": [sim.brigade_position(brigade), target_position],
		"line_start": Vector2.ZERO,
		"line_end": Vector2.ZERO,
		"policies": policies.duplicate(true),
	})


func _issue_ai_defensive_line(sim: BattleSimulation, brigade: Brigade, center: Vector2, facing_direction: Vector2, policies: Dictionary) -> void:
	if _brigade_has_pending_order(sim, brigade.id):
		return
	var threat_vector: Vector2 = _get_local_threat_vector(sim, center, brigade.army_id, 320.0)
	var frontage_scale: float = 0.92
	if _is_flank_threat(brigade, threat_vector):
		frontage_scale = 0.62
	elif threat_vector.length() > 18.0:
		frontage_scale = 0.76
	var frontage: float = _estimate_brigade_frontage(sim, brigade) * frontage_scale
	var safe_direction: Vector2 = facing_direction.normalized() if facing_direction.length() > 0.001 else Vector2.UP
	var lateral: Vector2 = Vector2(-safe_direction.y, safe_direction.x)
	var half_frontage: float = frontage * 0.5
	var line_start: Vector2 = center - lateral * half_frontage
	var line_end: Vector2 = center + lateral * half_frontage
	var same_order_type: bool = brigade.current_order_type in [SimTypes.OrderType.DEFEND, SimTypes.OrderType.HOLD]
	var same_policies: bool = brigade.order_policies.hash() == policies.hash()
	var similar_line: bool = brigade.order_line_start.distance_to(line_start) <= 48.0 and brigade.order_line_end.distance_to(line_end) <= 48.0
	if same_order_type and same_policies and similar_line:
		return
	sim.queue_player_command({
		"army_id": String(brigade.army_id),
		"recipient_brigade_id": String(brigade.id),
		"order_type": SimTypes.OrderType.DEFEND,
		"target_position": center,
		"path_points": [],
		"line_start": line_start,
		"line_end": line_end,
		"policies": policies.duplicate(true),
	})


func _brigade_has_pending_order(sim: BattleSimulation, brigade_id: StringName) -> bool:
	for order_value in sim.orders.values():
		var order: SimOrder = order_value
		if order.recipient_brigade_id != brigade_id:
			continue
		if order.status in [SimTypes.OrderStatus.CREATED, SimTypes.OrderStatus.IN_TRANSIT]:
			return true
	return false


func _get_active_brigade_regiments(sim: BattleSimulation, brigade: Brigade) -> Array:
	var result: Array = []
	for regiment_id in brigade.regiment_ids:
		var regiment: Battalion = sim.regiments.get(regiment_id)
		if regiment == null or regiment.is_destroyed:
			continue
		result.append(regiment)
	return result


func _get_brigade_center(regiments: Array) -> Vector2:
	var total_position: Vector2 = Vector2.ZERO
	for regiment in regiments:
		var typed_regiment: Battalion = regiment
		total_position += typed_regiment.position
	return total_position / float(max(1, regiments.size()))


func _find_nearest_enemy_to_position(sim: BattleSimulation, world_position: Vector2, army_id: StringName) -> Battalion:
	var best_regiment: Battalion = null
	var best_distance: float = INF
	for regiment in sim.regiments.values():
		var typed_regiment: Battalion = regiment
		if typed_regiment.army_id == army_id or typed_regiment.is_destroyed:
			continue
		var distance: float = world_position.distance_to(typed_regiment.position)
		if distance < best_distance:
			best_distance = distance
			best_regiment = typed_regiment
	return best_regiment


func _find_best_objective(sim: BattleSimulation, brigade_center: Vector2, army_id: StringName) -> StrategicPoint:
	var best_point: StrategicPoint = null
	var best_score: float = -INF
	for point in sim.strategic_points.values():
		var typed_point: StrategicPoint = point
		var distance_score: float = 1000.0 - brigade_center.distance_to(typed_point.position)
		var control_score: float = 0.0
		if typed_point.controlling_army_id == &"":
			control_score = 220.0
		elif typed_point.controlling_army_id != army_id:
			control_score = 320.0
		else:
			control_score = -120.0
		var score: float = distance_score + control_score + typed_point.victory_rate_per_second * 100.0
		if score > best_score:
			best_score = score
			best_point = typed_point
	return best_point


func _estimate_brigade_frontage(sim: BattleSimulation, brigade: Brigade) -> float:
	var frontage: float = 120.0
	var count: int = 0
	for regiment_id in brigade.regiment_ids:
		var regiment: Battalion = sim.regiments.get(regiment_id)
		if regiment == null or regiment.is_destroyed:
			continue
		frontage += max(64.0, regiment.formation.frontage) * 0.78
		count += 1
	if count <= 1:
		return frontage
	return frontage


func _get_local_threat_vector(sim: BattleSimulation, center: Vector2, army_id: StringName, radius: float) -> Vector2:
	var threat: Vector2 = Vector2.ZERO
	for regiment_value in sim.regiments.values():
		var regiment: Battalion = regiment_value
		if regiment.army_id == army_id or regiment.is_destroyed:
			continue
		var offset: Vector2 = regiment.position - center
		var distance: float = offset.length()
		if distance > radius or distance <= 0.001:
			continue
		var weight: float = 1.0 - distance / radius
		threat += offset.normalized() * weight
	return threat


func _is_flank_threat(brigade: Brigade, threat_vector: Vector2) -> bool:
	if threat_vector.length() <= 16.0:
		return false
	var current_facing: Vector2 = Vector2.RIGHT.rotated(brigade.formation_facing)
	var lateral: Vector2 = Vector2(-current_facing.y, current_facing.x)
	return absf(threat_vector.normalized().dot(lateral)) >= 0.58

