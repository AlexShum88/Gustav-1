class_name CoreV2EnemyBehaviorSystem
extends RefCounted


const DECISION_INTERVAL_SECONDS: float = 7.5
const ATTACK_STANDOFF_M: float = 125.0
const ORDER_REISSUE_TARGET_DRIFT_M: float = 260.0
const OBJECTIVE_HOLD_RADIUS_M: float = 220.0


static func update_enemy_behavior(state: CoreV2BattleState, _delta: float) -> void:
	if state == null or state.phase != CoreV2Types.BattlePhase.ACTIVE:
		return
	for army_value in state.armies.values():
		var army: CoreV2Army = army_value
		if army == null or army.is_player_controlled or army.id == state.player_army_id:
			continue
		_update_enemy_army(state, army)


static func _update_enemy_army(state: CoreV2BattleState, army: CoreV2Army) -> void:
	for brigade_value in army.brigades:
		var brigade: CoreV2Brigade = brigade_value
		if brigade == null or brigade.is_reserve or brigade.battalions.is_empty():
			continue
		if state.time_seconds < brigade.ai_next_decision_time_seconds:
			continue
		if _has_pending_messenger(state, army.id, brigade.id):
			continue

		var intent: Dictionary = _build_brigade_intent(state, army, brigade)
		brigade.ai_next_decision_time_seconds = state.time_seconds + DECISION_INTERVAL_SECONDS
		if intent.is_empty():
			continue

		var order_type: int = int(intent.get("order_type", CoreV2Types.OrderType.NONE))
		var target_position: Vector3 = intent.get("target_position", brigade.hq_position)
		var policies: Dictionary = intent.get("policies", {})
		var focus_entity_id: StringName = StringName(policies.get("ai_focus_entity_id", ""))
		if not _should_issue_order(brigade, order_type, target_position, focus_entity_id):
			continue

		if state.issue_server_brigade_order(army.id, brigade.id, order_type, target_position, policies):
			brigade.ai_last_focus_entity_id = focus_entity_id
			brigade.ai_last_order_target = target_position


static func _build_brigade_intent(state: CoreV2BattleState, army: CoreV2Army, brigade: CoreV2Brigade) -> Dictionary:
	var visible_target: CoreV2Battalion = _find_visible_enemy_battalion(state, army, brigade)
	if visible_target != null:
		return {
			"order_type": CoreV2Types.OrderType.ATTACK,
			"target_position": _resolve_attack_position(state, brigade, visible_target),
			"policies": {
				"road_column": false,
				"deploy_on_contact": true,
				"ai_behavior": "attack_visible_target",
				"ai_focus_entity_id": String(visible_target.id),
			},
		}

	var objective: CoreV2Objective = _find_priority_objective(state, army, brigade)
	if objective == null:
		return {}
	var order_type: int = CoreV2Types.OrderType.DEFEND if _distance_2d(brigade.get_center_position(), objective.position) <= OBJECTIVE_HOLD_RADIUS_M else CoreV2Types.OrderType.MARCH
	return {
		"order_type": order_type,
		"target_position": objective.position,
		"policies": {
			"road_column": true,
			"deploy_on_contact": true,
			"ai_behavior": "secure_objective",
			"ai_focus_entity_id": String(objective.id),
		},
	}


static func _find_visible_enemy_battalion(state: CoreV2BattleState, army: CoreV2Army, brigade: CoreV2Brigade) -> CoreV2Battalion:
	var visible_keys: Dictionary = state.visible_entity_keys_by_army.get(army.id, {})
	var brigade_center: Vector3 = brigade.get_center_position()
	var nearest_target: CoreV2Battalion = null
	var nearest_distance_m: float = INF
	for battalion_value in state.get_all_battalions():
		var target: CoreV2Battalion = battalion_value
		if target.army_id == army.id or target.status == CoreV2Types.UnitStatus.ROUTING or target.soldiers_total <= 0:
			continue
		if not visible_keys.has(CoreV2VisibilitySystem.battalion_key(target.id)):
			continue
		var distance_m: float = _distance_2d(brigade_center, target.position)
		if distance_m >= nearest_distance_m:
			continue
		nearest_target = target
		nearest_distance_m = distance_m
	return nearest_target


static func _find_priority_objective(state: CoreV2BattleState, army: CoreV2Army, brigade: CoreV2Brigade) -> CoreV2Objective:
	var brigade_center: Vector3 = brigade.get_center_position()
	var best_objective: CoreV2Objective = null
	var best_score: float = INF
	for objective_value in state.objectives:
		var objective: CoreV2Objective = objective_value
		if objective == null:
			continue
		var distance_m: float = _distance_2d(brigade_center, objective.position)
		var ownership_penalty: float = 900.0 if objective.owner_army_id == army.id else 0.0
		var score: float = distance_m + ownership_penalty
		if score >= best_score:
			continue
		best_objective = objective
		best_score = score
	return best_objective


static func _resolve_attack_position(state: CoreV2BattleState, brigade: CoreV2Brigade, target: CoreV2Battalion) -> Vector3:
	var brigade_center: Vector3 = brigade.get_center_position()
	var direction_from_target := Vector2(brigade_center.x - target.position.x, brigade_center.z - target.position.z)
	if direction_from_target.length_squared() <= 0.001:
		return state.project_position_to_terrain(target.position)
	direction_from_target = direction_from_target.normalized()
	var attack_position := Vector3(
		target.position.x + direction_from_target.x * ATTACK_STANDOFF_M,
		0.0,
		target.position.z + direction_from_target.y * ATTACK_STANDOFF_M
	)
	return state.project_position_to_terrain(attack_position)


static func _should_issue_order(
		brigade: CoreV2Brigade,
		order_type: int,
		target_position: Vector3,
		focus_entity_id: StringName
) -> bool:
	if brigade.current_order == null:
		return true
	if brigade.current_order.order_type != order_type:
		return true
	if focus_entity_id != &"" and brigade.ai_last_focus_entity_id != focus_entity_id:
		return true
	return _distance_2d(brigade.current_order.target_position, target_position) > ORDER_REISSUE_TARGET_DRIFT_M


static func _has_pending_messenger(state: CoreV2BattleState, army_id: StringName, brigade_id: StringName) -> bool:
	for messenger_value in state.order_messengers:
		var messenger: CoreV2OrderMessenger = messenger_value
		if messenger.army_id == army_id and messenger.brigade_id == brigade_id and messenger.status == CoreV2Types.MessengerStatus.EN_ROUTE:
			return true
	return false


static func _distance_2d(from_position: Vector3, to_position: Vector3) -> float:
	return Vector2(from_position.x, from_position.z).distance_to(Vector2(to_position.x, to_position.z))
