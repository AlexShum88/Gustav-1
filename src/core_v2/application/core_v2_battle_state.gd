class_name CoreV2BattleState
extends RefCounted


const SMOKE_MIN_VISIBILITY_MULTIPLIER: float = 0.18
const WEAPON_SMOKE_MUSKET_RADIUS_M: float = 135.0
const WEAPON_SMOKE_ARTILLERY_RADIUS_M: float = 210.0
const WEAPON_SMOKE_MUSKET_LIFETIME_SECONDS: float = 42.0
const WEAPON_SMOKE_ARTILLERY_LIFETIME_SECONDS: float = 58.0
const WEAPON_SMOKE_DECAY_PER_SECOND: float = 0.018
const VOICE_COMMAND_RADIUS_M: float = 100.0
const MESSENGER_INFANTRY_INTERCEPTION_RADIUS_M: float = 120.0
const MESSENGER_CAVALRY_INTERCEPTION_RADIUS_M: float = 190.0
const MESSENGER_ARTILLERY_INTERCEPTION_RADIUS_M: float = 85.0
const TERRAIN_HEIGHT_FADE_MIN_M: float = 160.0
const TERRAIN_HEIGHT_FADE_MAX_M: float = 760.0
const ROAD_HEIGHT_SAMPLE_STEP_M: float = 160.0
const ROAD_ROUTE_MIN_DIRECT_DISTANCE_M: float = 520.0
const ROAD_ROUTE_ACCESS_RADIUS_M: float = 1250.0
const ROAD_ROUTE_ACCEPTED_DETOUR_FACTOR: float = 1.22
const ROAD_ROUTE_NODE_MERGE_RADIUS_M: float = 72.0
const ROAD_ROUTE_MAX_ENTRY_POINTS: int = 6
const ROAD_ROUTE_MAX_EXIT_POINTS: int = 6
const ROAD_ROUTE_OFFROAD_SAMPLE_STEP_M: float = 260.0

var map_rect: Rect2 = Rect2(-5000.0, -5000.0, 10000.0, 10000.0)
var time_seconds: float = 0.0
var phase: int = CoreV2Types.BattlePhase.DEPLOYMENT
var player_army_id: StringName = &"blue"
var armies: Dictionary = {}
var objectives: Array = []
var terrain_patches: Array = []
var roads: Array = []
var _road_route_graph_cache: Dictionary = {}
var smoke_zones: Array = []
var order_messengers: Array = []
var weather_profile: Dictionary = {
	"id": "clear",
	"display_name": "Ясно",
	"vision_multiplier": 1.0,
	"color": Color(0.7, 0.8, 0.9, 0.12),
}
var recent_events: Array = []
var max_recent_events: int = 10
var visible_entity_keys_by_army: Dictionary = {}
var last_seen_by_army: Dictionary = {}
var static_world_revision: int = 1
var rare_world_revision: int = 1
var battle_revision: int = 1
var _visibility_accumulator: float = 0.0
var _visibility_interval: float = 0.25
var _last_seen_accumulator: float = 0.0
var _last_seen_interval: float = 1.0
var _visibility_observer_cursor: int = 0


func add_army(army: CoreV2Army) -> void:
	if army == null:
		return
	armies[army.id] = army
	visible_entity_keys_by_army[army.id] = {}
	last_seen_by_army[army.id] = {}
	mark_static_world_changed()


func add_objective(objective: CoreV2Objective) -> void:
	if objective == null:
		return
	objectives.append(objective)
	mark_rare_world_changed()


func add_terrain_patch(
		id_text: String,
		display_name: String,
		terrain_type: int,
		rect: Rect2,
		height_m: float,
		speed_multiplier: float,
		vision_multiplier: float,
		defense_modifier: float,
		color: Color,
		height_fade_m: float = -1.0
) -> void:
	terrain_patches.append({
		"id": id_text,
		"display_name": display_name,
		"terrain_type": terrain_type,
		"terrain_label": CoreV2Types.terrain_type_name(terrain_type),
		"rect": rect,
		"height_m": height_m,
		"height_fade_m": _resolve_height_fade_m(rect, height_fade_m),
		"speed_multiplier": speed_multiplier,
		"vision_multiplier": vision_multiplier,
		"defense_modifier": defense_modifier,
		"color": color,
	})
	mark_static_world_changed()


func add_road(id_text: String, display_name: String, points: Array, width_m: float, speed_multiplier: float) -> void:
	var projected_points: Array = _project_polyline_to_terrain(points, ROAD_HEIGHT_SAMPLE_STEP_M)
	roads.append({
		"id": id_text,
		"display_name": display_name,
		"points": projected_points,
		"width_m": width_m,
		"speed_multiplier": speed_multiplier,
		"color": Color(0.46, 0.39, 0.25, 0.92),
	})
	_road_route_graph_cache.clear()
	mark_static_world_changed()


func set_weather(id_text: String, display_name: String, vision_multiplier: float, color: Color) -> void:
	weather_profile = {
		"id": id_text,
		"display_name": display_name,
		"vision_multiplier": clamp(vision_multiplier, 0.15, 1.35),
		"color": color,
	}
	mark_rare_world_changed()


func add_smoke_zone(
		id_text: String,
		display_name: String,
		position: Vector3,
		radius_m: float,
		density: float,
		height_m: float,
		penetration_m: float,
		color: Color,
		decay_per_second: float = 0.0,
		lifetime_seconds: float = -1.0
) -> void:
	var projected_position: Vector3 = project_position_to_terrain(position)
	smoke_zones.append({
		"id": id_text,
		"display_name": display_name,
		"position": projected_position,
		"radius_m": max(1.0, radius_m),
		"density": clamp(density, 0.0, 1.0),
		"height_m": max(1.0, height_m),
		"penetration_m": max(1.0, penetration_m),
		"color": color,
		"direction": Vector3.FORWARD,
		"decay_per_second": max(0.0, decay_per_second),
		"expires_at_seconds": time_seconds + lifetime_seconds if lifetime_seconds > 0.0 else -1.0,
		"source_army_id": "",
		"source_entity_id": "",
	})
	mark_rare_world_changed()


func emit_weapon_smoke(attacker: CoreV2Battalion, target_position: Vector3, attack_kind: String) -> void:
	if attacker == null:
		return
	if attack_kind != "musket" and attack_kind != "artillery":
		return
	var direction: Vector3 = target_position - attacker.position
	direction.y = 0.0
	if direction.length_squared() <= 0.001:
		direction = attacker.facing
	direction = direction.normalized()
	var is_artillery: bool = attack_kind == "artillery"
	var radius_m: float = WEAPON_SMOKE_ARTILLERY_RADIUS_M if is_artillery else WEAPON_SMOKE_MUSKET_RADIUS_M
	var density: float = 0.5 if is_artillery else 0.34
	var height_m: float = 40.0 if is_artillery else 24.0
	var penetration_m: float = 125.0 if is_artillery else 155.0
	var lifetime_seconds: float = WEAPON_SMOKE_ARTILLERY_LIFETIME_SECONDS if is_artillery else WEAPON_SMOKE_MUSKET_LIFETIME_SECONDS
	var offset_m: float = 80.0 if is_artillery else 38.0
	var color_alpha: float = 0.24 if is_artillery else 0.18
	var smoke_position: Vector3 = attacker.position + direction * offset_m
	var smoke_id: String = "weapon_smoke:%s" % String(attacker.id)
	_upsert_smoke_zone(
		smoke_id,
		"Дим пострілів: %s" % attacker.display_name,
		smoke_position,
		radius_m,
		density,
		height_m,
		penetration_m,
		Color(0.58, 0.58, 0.53, color_alpha),
		WEAPON_SMOKE_DECAY_PER_SECOND,
		lifetime_seconds,
		attacker.army_id,
		attacker.id,
		direction
	)


func _upsert_smoke_zone(
		id_text: String,
		display_name: String,
		position: Vector3,
		radius_m: float,
		density: float,
		height_m: float,
		penetration_m: float,
		color: Color,
		decay_per_second: float,
		lifetime_seconds: float,
		source_army_id: StringName = &"",
		source_entity_id: StringName = &"",
		direction: Vector3 = Vector3.FORWARD
) -> void:
	var projected_position: Vector3 = project_position_to_terrain(position)
	var smoke_index: int = _find_smoke_zone_index(id_text)
	var next_density: float = clamp(density, 0.0, 1.0)
	if smoke_index >= 0:
		var existing_smoke: Dictionary = smoke_zones[smoke_index]
		next_density = clamp(max(float(existing_smoke.get("density", 0.0)) * 0.72, next_density) + next_density * 0.28, 0.0, 0.95)
	var smoke_snapshot: Dictionary = {
		"id": id_text,
		"display_name": display_name,
		"position": projected_position,
		"radius_m": max(1.0, radius_m),
		"density": next_density,
		"height_m": max(1.0, height_m),
		"penetration_m": max(1.0, penetration_m),
		"color": color,
		"direction": direction.normalized() if direction.length_squared() > 0.001 else Vector3.FORWARD,
		"decay_per_second": max(0.0, decay_per_second),
		"expires_at_seconds": time_seconds + lifetime_seconds if lifetime_seconds > 0.0 else -1.0,
		"source_army_id": String(source_army_id),
		"source_entity_id": String(source_entity_id),
	}
	if smoke_index >= 0:
		smoke_zones[smoke_index] = smoke_snapshot
	else:
		smoke_zones.append(smoke_snapshot)


func _find_smoke_zone_index(id_text: String) -> int:
	for index in range(smoke_zones.size()):
		var smoke: Dictionary = smoke_zones[index]
		if String(smoke.get("id", "")) == id_text:
			return index
	return -1


func _should_include_smoke_zone_in_snapshot(smoke: Dictionary, observer_army_id: StringName) -> bool:
	if phase != CoreV2Types.BattlePhase.ACTIVE or observer_army_id == &"":
		return true
	var source_army_id: StringName = StringName(smoke.get("source_army_id", ""))
	var source_entity_id: StringName = StringName(smoke.get("source_entity_id", ""))
	if source_army_id == &"" or source_entity_id == &"":
		return true
	if source_army_id == observer_army_id:
		return true
	return is_entity_visible_to_army(observer_army_id, CoreV2VisibilitySystem.battalion_key(source_entity_id))


func get_army(army_id: StringName) -> CoreV2Army:
	return armies.get(army_id, null)


func get_player_army() -> CoreV2Army:
	return get_army(player_army_id)


func mark_static_world_changed() -> void:
	static_world_revision += 1
	battle_revision += 1


func mark_rare_world_changed() -> void:
	rare_world_revision += 1
	battle_revision += 1


func mark_battle_changed() -> void:
	battle_revision += 1


func process_command(command: Dictionary) -> void:
	# Усі дії клієнта проходять тут, щоб правила залишались сервер-авторитативними.
	var command_type: int = int(command.get("command_type", -1))
	match command_type:
		CoreV2Types.CommandType.PLACE_BAGGAGE:
			_process_place_baggage(command)
		CoreV2Types.CommandType.PLACE_COMMANDER:
			_process_place_commander(command)
		CoreV2Types.CommandType.ISSUE_BRIGADE_ORDER:
			_process_issue_brigade_order(command)
		CoreV2Types.CommandType.ISSUE_BATTALION_ORDER:
			_process_issue_battalion_order(command)
		CoreV2Types.CommandType.START_BATTLE:
			_process_start_battle(command)
		CoreV2Types.CommandType.DEBUG_FORCE_FORMATION:
			_process_debug_force_formation(command)
		_:
			_push_event("Сервер отримав невідому команду.")


func advance(delta: float) -> void:
	# Під час активної паузи час битви не йде: сервер лише чекає стартового розгортання.
	if phase != CoreV2Types.BattlePhase.ACTIVE:
		return
	time_seconds += delta
	_advance_smoke_zones(delta)
	_last_seen_accumulator += delta
	if _last_seen_accumulator >= _last_seen_interval:
		_last_seen_accumulator = fmod(_last_seen_accumulator, _last_seen_interval)
		CoreV2VisibilitySystem.prune_last_seen(self)
	CoreV2EnemyBehaviorSystem.update_enemy_behavior(self, delta)
	CoreV2EngagementMovementSystem.update_engagement_movement(self, delta)
	for army_value in armies.values():
		var army: CoreV2Army = army_value
		army.advance(delta, self)
	CoreV2FormationSeparationSystem.update_formation_separation(self, delta)
	_visibility_accumulator += delta
	if _visibility_accumulator >= _visibility_interval:
		_visibility_accumulator = fmod(_visibility_accumulator, _visibility_interval)
		_update_visibility()
		_update_messenger_interception()
	_advance_order_messengers(delta)
	CoreV2CombatSystem.update_combat(self, delta)
	_update_objective_control(delta)
	_update_resolution_state()
	mark_battle_changed()


func get_all_battalions() -> Array:
	var result: Array = []
	for army_value in armies.values():
		var army: CoreV2Army = army_value
		result.append_array(army.get_all_battalions())
	return result


func get_battalion(battalion_id: StringName) -> CoreV2Battalion:
	for battalion_value in get_all_battalions():
		var battalion: CoreV2Battalion = battalion_value
		if battalion.id == battalion_id:
			return battalion
	return null


func issue_server_brigade_order(
		army_id: StringName,
		brigade_id: StringName,
		order_type: int,
		target_position: Vector3,
		policies: Dictionary = {}
) -> bool:
	if phase != CoreV2Types.BattlePhase.ACTIVE:
		return false
	var army: CoreV2Army = get_army(army_id)
	if army == null:
		return false
	var brigade: CoreV2Brigade = army.get_brigade(brigade_id)
	if brigade == null:
		return false
	return _issue_brigade_order(army, brigade, order_type, target_position, policies)


func issue_server_battalion_order(
		army_id: StringName,
		battalion_id: StringName,
		order_type: int,
		target_position: Vector3,
		policies: Dictionary = {}
) -> bool:
	if phase != CoreV2Types.BattlePhase.ACTIVE:
		return false
	var battalion: CoreV2Battalion = get_battalion(battalion_id)
	if battalion == null or battalion.army_id != army_id:
		return false
	var army: CoreV2Army = get_army(army_id)
	if army == null:
		return false
	var brigade: CoreV2Brigade = army.get_brigade(battalion.brigade_id)
	if brigade == null:
		return false
	return _issue_battalion_order(army, brigade, battalion, order_type, target_position, policies)


func get_deployment_zone_snapshots() -> Array:
	var snapshots: Array = []
	for army_value in armies.values():
		var army: CoreV2Army = army_value
		for zone_name_value in army.deployment_zones.keys():
			var zone_name: String = String(zone_name_value)
			var zone_rect: Rect2 = army.deployment_zones[zone_name]
			snapshots.append({
				"army_id": String(army.id),
				"army_name": army.display_name,
				"zone_type": zone_name,
				"rect": zone_rect,
				"color": army.color,
			})
	return snapshots


func get_terrain_patch_snapshots() -> Array:
	return terrain_patches.duplicate(true)


func get_road_snapshots() -> Array:
	return roads.duplicate(true)


func plan_movement_path(
		start_position: Vector3,
		target_position: Vector3,
		unit_category: int,
		order_type: int,
		policies: Dictionary
) -> Array:
	if not _should_use_road_route(order_type, policies):
		return []
	var start_projected: Vector3 = project_position_to_terrain(start_position)
	var target_projected: Vector3 = project_position_to_terrain(target_position)
	var direct_distance_m: float = _distance_2d(start_projected, target_projected)
	if roads.is_empty() or direct_distance_m < ROAD_ROUTE_MIN_DIRECT_DISTANCE_M:
		return []
	var direct_cost: float = _estimate_offroad_route_cost(start_projected, target_projected, unit_category)
	var route_result: Dictionary = _find_road_route(start_projected, target_projected, unit_category)
	if route_result.is_empty():
		return []
	if float(route_result.get("cost", INF)) > direct_cost * ROAD_ROUTE_ACCEPTED_DETOUR_FACTOR:
		return []
	return route_result.get("points", []).duplicate(true)


func get_weather_snapshot() -> Dictionary:
	return weather_profile.duplicate(true)


func get_smoke_zone_snapshots(observer_army_id: StringName = &"") -> Array:
	var snapshots: Array = []
	for smoke_value in smoke_zones:
		var smoke: Dictionary = smoke_value
		if not _should_include_smoke_zone_in_snapshot(smoke, observer_army_id):
			continue
		snapshots.append(smoke.duplicate(true))
	return snapshots


func get_order_messenger_snapshots(observer_army_id: StringName) -> Array:
	var snapshots: Array = []
	for messenger_value in order_messengers:
		var messenger: CoreV2OrderMessenger = messenger_value
		var is_friendly: bool = messenger.army_id == observer_army_id
		if not is_friendly and not is_entity_visible_to_army(observer_army_id, CoreV2VisibilitySystem.messenger_key(messenger.id)):
			continue
		var snapshot: Dictionary = messenger.create_snapshot(observer_army_id)
		var army: CoreV2Army = get_army(messenger.army_id)
		snapshot["color"] = army.color.lightened(0.18) if army != null else Color(0.88, 0.82, 0.55)
		snapshot["army_name"] = army.display_name if army != null else String(messenger.army_id)
		snapshots.append(snapshot)
	return snapshots


func count_order_messengers_for_army(army_id: StringName) -> int:
	var count: int = 0
	for messenger_value in order_messengers:
		var messenger: CoreV2OrderMessenger = messenger_value
		if messenger.army_id == army_id and messenger.status == CoreV2Types.MessengerStatus.EN_ROUTE:
			count += 1
	return count


func project_position_to_terrain(world_position: Vector3) -> Vector3:
	var result: Vector3 = world_position
	result.y = get_height_at(world_position)
	return result


func get_height_at(world_position: Vector3) -> float:
	var height_m: float = 0.0
	var point_2d := Vector2(world_position.x, world_position.z)
	for patch_value in terrain_patches:
		var patch: Dictionary = patch_value
		var influence: float = _get_height_patch_influence(point_2d, patch)
		if influence <= 0.0:
			continue
		height_m = lerp(height_m, float(patch.get("height_m", height_m)), influence)
	return height_m


func _get_height_patch_influence(point_2d: Vector2, patch: Dictionary) -> float:
	var patch_rect: Rect2 = patch.get("rect", Rect2())
	if not patch_rect.has_point(point_2d):
		return 0.0
	var fade_m: float = max(0.0, float(patch.get("height_fade_m", _resolve_height_fade_m(patch_rect))))
	if fade_m <= 0.01:
		return 1.0
	var distance_to_edge: float = min(
		min(point_2d.x - patch_rect.position.x, patch_rect.end.x - point_2d.x),
		min(point_2d.y - patch_rect.position.y, patch_rect.end.y - point_2d.y)
	)
	var max_fade_m: float = max(1.0, min(absf(patch_rect.size.x), absf(patch_rect.size.y)) * 0.5)
	return _smoothstep01(distance_to_edge / min(fade_m, max_fade_m))


func _resolve_height_fade_m(rect: Rect2, requested_fade_m: float = -1.0) -> float:
	if requested_fade_m >= 0.0:
		return requested_fade_m
	return clamp(
		min(absf(rect.size.x), absf(rect.size.y)) * 0.28,
		TERRAIN_HEIGHT_FADE_MIN_M,
		TERRAIN_HEIGHT_FADE_MAX_M
	)


func _smoothstep01(value: float) -> float:
	var t: float = clamp(value, 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)


func _project_polyline_to_terrain(points: Array, sample_step_m: float) -> Array:
	var projected_points: Array = []
	if points.is_empty():
		return projected_points
	var first_point: Vector3 = points[0]
	projected_points.append(project_position_to_terrain(first_point))
	for point_index in range(1, points.size()):
		var segment_start: Vector3 = points[point_index - 1]
		var segment_end: Vector3 = points[point_index]
		var distance_m: float = Vector2(segment_start.x, segment_start.z).distance_to(Vector2(segment_end.x, segment_end.z))
		var sample_count: int = max(1, int(ceil(distance_m / max(1.0, sample_step_m))))
		for sample_index in range(1, sample_count + 1):
			var t: float = float(sample_index) / float(sample_count)
			projected_points.append(project_position_to_terrain(segment_start.lerp(segment_end, t)))
	return projected_points


func _should_use_road_route(order_type: int, policies: Dictionary) -> bool:
	if not bool(policies.get("road_column", false)):
		return false
	return order_type in [
		CoreV2Types.OrderType.MOVE,
		CoreV2Types.OrderType.MARCH,
		CoreV2Types.OrderType.PATROL,
	]


func _find_road_route(start_position: Vector3, target_position: Vector3, unit_category: int) -> Dictionary:
	var graph: Dictionary = _build_road_route_graph()
	var nodes: Array = graph.get("nodes", [])
	var adjacency: Array = graph.get("adjacency", [])
	if nodes.is_empty():
		return {}
	var entry_candidates: Array = _find_nearest_road_nodes(
		nodes,
		start_position,
		ROAD_ROUTE_ACCESS_RADIUS_M,
		ROAD_ROUTE_MAX_ENTRY_POINTS
	)
	var exit_candidates: Array = _find_nearest_road_nodes(
		nodes,
		target_position,
		ROAD_ROUTE_ACCESS_RADIUS_M,
		ROAD_ROUTE_MAX_EXIT_POINTS
	)
	if entry_candidates.is_empty() or exit_candidates.is_empty():
		return {}

	var distances: Dictionary = {}
	var previous: Dictionary = {}
	var open_nodes: Dictionary = {}
	for entry_value in entry_candidates:
		var entry: Dictionary = entry_value
		var entry_index: int = int(entry.get("index", -1))
		if entry_index < 0:
			continue
		var entry_position: Vector3 = nodes[entry_index]
		var entry_cost: float = _estimate_offroad_route_cost(start_position, entry_position, unit_category)
		if not distances.has(entry_index) or entry_cost < float(distances[entry_index]):
			distances[entry_index] = entry_cost
			previous[entry_index] = -1
			open_nodes[entry_index] = true

	_run_road_dijkstra(adjacency, distances, previous, open_nodes)

	var best_exit_index: int = -1
	var best_cost: float = INF
	for exit_value in exit_candidates:
		var exit_candidate: Dictionary = exit_value
		var exit_index: int = int(exit_candidate.get("index", -1))
		if exit_index < 0 or not distances.has(exit_index):
			continue
		var exit_position: Vector3 = nodes[exit_index]
		var total_cost: float = float(distances[exit_index]) + _estimate_offroad_route_cost(exit_position, target_position, unit_category)
		if total_cost >= best_cost:
			continue
		best_cost = total_cost
		best_exit_index = exit_index
	if best_exit_index < 0:
		return {}

	var route_indices: Array = _reconstruct_road_route_indices(best_exit_index, previous)
	var route_points: Array = _build_route_points_from_indices(route_indices, nodes, target_position)
	if route_points.is_empty():
		return {}
	return {
		"cost": best_cost,
		"points": route_points,
	}


func _build_road_route_graph() -> Dictionary:
	if not _road_route_graph_cache.is_empty():
		return _road_route_graph_cache
	var nodes: Array = []
	var adjacency: Array = []
	for road_value in roads:
		var road: Dictionary = road_value
		var points: Array = road.get("points", [])
		if points.size() < 2:
			continue
		var road_speed_multiplier: float = max(0.1, float(road.get("speed_multiplier", 1.0)))
		var previous_index: int = -1
		for point_value in points:
			var point: Vector3 = point_value
			var node_index: int = _find_or_add_road_node(nodes, adjacency, point)
			if previous_index >= 0 and previous_index != node_index:
				var from_position: Vector3 = nodes[previous_index]
				var to_position: Vector3 = nodes[node_index]
				_add_road_graph_edge(adjacency, previous_index, node_index, _distance_2d(from_position, to_position) / road_speed_multiplier)
			previous_index = node_index
	_road_route_graph_cache = {
		"nodes": nodes,
		"adjacency": adjacency,
	}
	return _road_route_graph_cache


func _find_or_add_road_node(nodes: Array, adjacency: Array, point: Vector3) -> int:
	for index in range(nodes.size()):
		var existing_point: Vector3 = nodes[index]
		if _distance_2d(existing_point, point) <= ROAD_ROUTE_NODE_MERGE_RADIUS_M:
			return index
	nodes.append(project_position_to_terrain(point))
	adjacency.append([])
	return nodes.size() - 1


func _add_road_graph_edge(adjacency: Array, from_index: int, to_index: int, cost: float) -> void:
	if cost <= 0.001:
		return
	adjacency[from_index].append({
		"to": to_index,
		"cost": cost,
	})
	adjacency[to_index].append({
		"to": from_index,
		"cost": cost,
	})


func _find_nearest_road_nodes(nodes: Array, position_value: Vector3, max_radius_m: float, max_count: int) -> Array:
	var candidates: Array = []
	var fallback_candidate: Dictionary = {}
	for index in range(nodes.size()):
		var node_position: Vector3 = nodes[index]
		var distance_m: float = _distance_2d(position_value, node_position)
		if fallback_candidate.is_empty() or distance_m < float(fallback_candidate.get("distance_m", INF)):
			fallback_candidate = {
				"index": index,
				"distance_m": distance_m,
			}
		if distance_m > max_radius_m:
			continue
		_insert_route_candidate(candidates, {
			"index": index,
			"distance_m": distance_m,
		}, max_count)
	if candidates.is_empty() and not fallback_candidate.is_empty() and float(fallback_candidate.get("distance_m", INF)) <= max_radius_m * 1.75:
		candidates.append(fallback_candidate)
	return candidates


func _insert_route_candidate(candidates: Array, candidate: Dictionary, max_count: int) -> void:
	var insert_at: int = candidates.size()
	for index in range(candidates.size()):
		if float(candidate.get("distance_m", INF)) < float(candidates[index].get("distance_m", INF)):
			insert_at = index
			break
	candidates.insert(insert_at, candidate)
	while candidates.size() > max_count:
		candidates.pop_back()


func _run_road_dijkstra(adjacency: Array, distances: Dictionary, previous: Dictionary, open_nodes: Dictionary) -> void:
	while not open_nodes.is_empty():
		var current_index: int = _pop_nearest_open_route_node(open_nodes, distances)
		if current_index < 0:
			return
		var current_distance: float = float(distances[current_index])
		for edge_value in adjacency[current_index]:
			var edge: Dictionary = edge_value
			var next_index: int = int(edge.get("to", -1))
			if next_index < 0:
				continue
			var next_distance: float = current_distance + float(edge.get("cost", INF))
			if distances.has(next_index) and next_distance >= float(distances[next_index]):
				continue
			distances[next_index] = next_distance
			previous[next_index] = current_index
			open_nodes[next_index] = true


func _pop_nearest_open_route_node(open_nodes: Dictionary, distances: Dictionary) -> int:
	var best_index: int = -1
	var best_distance: float = INF
	for node_index_value in open_nodes.keys():
		var node_index: int = int(node_index_value)
		var node_distance: float = float(distances.get(node_index, INF))
		if node_distance >= best_distance:
			continue
		best_index = node_index
		best_distance = node_distance
	if best_index >= 0:
		open_nodes.erase(best_index)
	return best_index


func _reconstruct_road_route_indices(exit_index: int, previous: Dictionary) -> Array:
	var reversed_indices: Array = []
	var current_index: int = exit_index
	while current_index >= 0:
		reversed_indices.append(current_index)
		current_index = int(previous.get(current_index, -1))
	reversed_indices.reverse()
	return reversed_indices


func _build_route_points_from_indices(route_indices: Array, nodes: Array, target_position: Vector3) -> Array:
	var route_points: Array = []
	for index_value in route_indices:
		var node_index: int = int(index_value)
		if node_index < 0 or node_index >= nodes.size():
			continue
		_append_route_point(route_points, nodes[node_index])
	_append_route_point(route_points, project_position_to_terrain(target_position))
	return route_points


func _append_route_point(route_points: Array, point: Vector3) -> void:
	var projected_point: Vector3 = project_position_to_terrain(point)
	if not route_points.is_empty() and _distance_2d(route_points[route_points.size() - 1], projected_point) <= ROAD_ROUTE_NODE_MERGE_RADIUS_M:
		route_points[route_points.size() - 1] = projected_point
		return
	route_points.append(projected_point)


func _estimate_offroad_route_cost(from_position: Vector3, to_position: Vector3, unit_category: int) -> float:
	var distance_m: float = _distance_2d(from_position, to_position)
	if distance_m <= 0.001:
		return 0.0
	var sample_count: int = max(1, int(ceil(distance_m / ROAD_ROUTE_OFFROAD_SAMPLE_STEP_M)))
	var previous_position: Vector3 = from_position
	var cost: float = 0.0
	for sample_index in range(1, sample_count + 1):
		var t: float = float(sample_index) / float(sample_count)
		var next_position: Vector3 = from_position.lerp(to_position, t)
		var midpoint: Vector3 = previous_position.lerp(next_position, 0.5)
		var speed_multiplier: float = get_speed_multiplier_at(midpoint, unit_category)
		cost += _distance_2d(previous_position, next_position) / max(0.1, speed_multiplier)
		previous_position = next_position
	return cost


func _distance_2d(from_position: Vector3, to_position: Vector3) -> float:
	return Vector2(from_position.x, from_position.z).distance_to(Vector2(to_position.x, to_position.z))


func get_speed_multiplier_at(world_position: Vector3, unit_category: int = CoreV2Types.UnitCategory.INFANTRY) -> float:
	var speed_multiplier: float = 1.0
	var point_2d := Vector2(world_position.x, world_position.z)
	for patch_value in terrain_patches:
		var patch: Dictionary = patch_value
		var patch_rect: Rect2 = patch.get("rect", Rect2())
		if patch_rect.has_point(point_2d):
			speed_multiplier = float(patch.get("speed_multiplier", speed_multiplier))
	if unit_category == CoreV2Types.UnitCategory.CAVALRY and _is_rough_terrain(point_2d):
		speed_multiplier = min(speed_multiplier, 0.8)
	for road_value in roads:
		var road: Dictionary = road_value
		if _is_point_on_road(point_2d, road):
			speed_multiplier = max(speed_multiplier, float(road.get("speed_multiplier", speed_multiplier)))
	return max(0.1, speed_multiplier)


func get_visibility_multiplier_at(world_position: Vector3) -> float:
	var vision_multiplier: float = 1.0
	var point_2d := Vector2(world_position.x, world_position.z)
	for patch_value in terrain_patches:
		var patch: Dictionary = patch_value
		var patch_rect: Rect2 = patch.get("rect", Rect2())
		if patch_rect.has_point(point_2d):
			vision_multiplier = float(patch.get("vision_multiplier", vision_multiplier))
	return max(0.15, vision_multiplier)


func get_weather_visibility_multiplier() -> float:
	return clamp(float(weather_profile.get("vision_multiplier", 1.0)), 0.15, 1.35)


func get_smoke_density_at(world_position: Vector3) -> float:
	return _get_smoke_density_at(world_position)


func get_smoke_density_between(from_position: Vector3, to_position: Vector3) -> float:
	var from_2d := Vector2(from_position.x, from_position.z)
	var to_2d := Vector2(to_position.x, to_position.z)
	var segment: Vector2 = to_2d - from_2d
	var segment_length_squared: float = segment.length_squared()
	if segment_length_squared <= 0.01:
		return get_smoke_density_at(from_position)
	var strongest_density: float = 0.0
	for smoke_value in smoke_zones:
		var smoke: Dictionary = smoke_value
		var smoke_position: Vector3 = smoke.get("position", Vector3.ZERO)
		var smoke_radius_m: float = float(smoke.get("radius_m", 0.0))
		if smoke_radius_m <= 0.01:
			continue
		var smoke_2d := Vector2(smoke_position.x, smoke_position.z)
		var closest_t: float = clamp((smoke_2d - from_2d).dot(segment) / segment_length_squared, 0.0, 1.0)
		var closest_point: Vector2 = from_2d + segment * closest_t
		var distance_to_line_m: float = closest_point.distance_to(smoke_2d)
		if distance_to_line_m > smoke_radius_m:
			continue
		var edge_factor: float = 1.0 - clamp(distance_to_line_m / smoke_radius_m, 0.0, 1.0)
		var smoke_density: float = float(smoke.get("density", 0.0)) * (0.35 + 0.65 * edge_factor)
		strongest_density = max(strongest_density, smoke_density)
	return clamp(strongest_density, 0.0, 1.0)


func get_los_smoke_density_at(world_position: Vector3, sightline_height: float) -> float:
	return _get_smoke_density_at(world_position, sightline_height)


func get_smoke_vision_multiplier_at(world_position: Vector3) -> float:
	return max(SMOKE_MIN_VISIBILITY_MULTIPLIER, 1.0 - get_smoke_density_at(world_position) * 0.75)


func get_atmospheric_visibility_multiplier_at(world_position: Vector3) -> float:
	return max(0.1, get_weather_visibility_multiplier() * get_smoke_vision_multiplier_at(world_position))


func get_los_smoke_penetration_at(world_position: Vector3) -> float:
	var point_2d := Vector2(world_position.x, world_position.z)
	var penetration_m: float = INF
	for smoke_value in smoke_zones:
		var smoke: Dictionary = smoke_value
		var smoke_position: Vector3 = smoke.get("position", Vector3.ZERO)
		var smoke_radius_m: float = float(smoke.get("radius_m", 0.0))
		if smoke_radius_m <= 0.01:
			continue
		if point_2d.distance_to(Vector2(smoke_position.x, smoke_position.z)) > smoke_radius_m:
			continue
		penetration_m = min(penetration_m, float(smoke.get("penetration_m", penetration_m)))
	return penetration_m


func get_observer_vision_radius_at(world_position: Vector3, base_vision_radius_m: float) -> float:
	var height_bonus: float = clamp(get_height_at(world_position) * 8.0, -220.0, 520.0)
	var visibility_multiplier: float = get_visibility_multiplier_at(world_position) * get_atmospheric_visibility_multiplier_at(world_position)
	return max(120.0, base_vision_radius_m * visibility_multiplier + height_bonus)


func get_los_eye_height_at(world_position: Vector3) -> float:
	return get_height_at(world_position) + 2.2


func get_los_blocker_height_at(world_position: Vector3) -> float:
	return get_height_at(world_position) + get_los_cover_height_at(world_position)


func get_los_cover_height_at(world_position: Vector3) -> float:
	match get_terrain_type_at(world_position):
		CoreV2Types.TerrainType.FOREST:
			return 18.0
		CoreV2Types.TerrainType.TOWN:
			return 14.0
		CoreV2Types.TerrainType.VILLAGE:
			return 8.0
		CoreV2Types.TerrainType.BRUSH:
			return 4.0
		CoreV2Types.TerrainType.FARM:
			return 2.0
		_:
			return 0.0


func get_los_cover_penetration_at(world_position: Vector3) -> float:
	match get_terrain_type_at(world_position):
		CoreV2Types.TerrainType.FOREST:
			return 100.0
		CoreV2Types.TerrainType.TOWN:
			return 80.0
		CoreV2Types.TerrainType.VILLAGE:
			return 110.0
		CoreV2Types.TerrainType.BRUSH:
			return 150.0
		CoreV2Types.TerrainType.FARM:
			return 220.0
		_:
			return INF


func get_terrain_type_at(world_position: Vector3) -> int:
	var terrain_type: int = CoreV2Types.TerrainType.PLAIN
	var point_2d := Vector2(world_position.x, world_position.z)
	for patch_value in terrain_patches:
		var patch: Dictionary = patch_value
		var patch_rect: Rect2 = patch.get("rect", Rect2())
		if patch_rect.has_point(point_2d):
			terrain_type = int(patch.get("terrain_type", terrain_type))
	return terrain_type


func get_terrain_label_at(world_position: Vector3) -> String:
	var terrain_label: String = CoreV2Types.terrain_type_name(CoreV2Types.TerrainType.PLAIN)
	var point_2d := Vector2(world_position.x, world_position.z)
	for patch_value in terrain_patches:
		var patch: Dictionary = patch_value
		var patch_rect: Rect2 = patch.get("rect", Rect2())
		if patch_rect.has_point(point_2d):
			terrain_label = String(patch.get("terrain_label", terrain_label))
	return terrain_label


func get_defense_modifier_at(world_position: Vector3) -> float:
	var defense_modifier: float = 0.0
	var point_2d := Vector2(world_position.x, world_position.z)
	for patch_value in terrain_patches:
		var patch: Dictionary = patch_value
		var patch_rect: Rect2 = patch.get("rect", Rect2())
		if patch_rect.has_point(point_2d):
			defense_modifier = float(patch.get("defense_modifier", defense_modifier))
	return defense_modifier


func is_entity_visible_to_army(observer_army_id: StringName, entity_key: String) -> bool:
	if phase != CoreV2Types.BattlePhase.ACTIVE:
		return true
	var visible_keys: Dictionary = visible_entity_keys_by_army.get(observer_army_id, {})
	return visible_keys.has(entity_key)


func get_last_seen_marker_snapshots(observer_army_id: StringName) -> Array:
	if phase != CoreV2Types.BattlePhase.ACTIVE:
		return []
	return CoreV2VisibilitySystem.build_last_seen_markers(self, observer_army_id)


func _process_place_baggage(command: Dictionary) -> void:
	var army: CoreV2Army = get_army(StringName(command.get("army_id", "")))
	if army == null:
		return
	var placement: Vector3 = project_position_to_terrain(command.get("position", Vector3.ZERO))
	if not _point_inside_zone(placement, army.deployment_zones.get("baggage", Rect2())):
		_push_event("%s: обоз можна ставити лише у тиловій зоні." % army.display_name)
		return
	army.set_baggage_position(placement)
	_push_event("%s розмістила обоз." % army.display_name)


func _process_place_commander(command: Dictionary) -> void:
	var army: CoreV2Army = get_army(StringName(command.get("army_id", "")))
	if army == null:
		return
	var placement: Vector3 = project_position_to_terrain(command.get("position", Vector3.ZERO))
	if not _point_inside_zone(placement, army.deployment_zones.get("commander", Rect2())):
		_push_event("%s: полководця треба ставити в зоні штабу." % army.display_name)
		return
	army.set_commander_position(placement)
	_push_event("%s розмістила штаб полководця." % army.display_name)


func _process_issue_brigade_order(command: Dictionary) -> void:
	if phase != CoreV2Types.BattlePhase.ACTIVE:
		_push_event("Поки діє активна пауза, нове ядро дозволяє лише розміщення штабів.")
		return
	var army: CoreV2Army = get_army(StringName(command.get("army_id", "")))
	if army == null:
		return
	var brigade: CoreV2Brigade = army.get_brigade(StringName(command.get("brigade_id", "")))
	if brigade == null:
		return
	var order_type: int = int(command.get("order_type", CoreV2Types.OrderType.NONE))
	var target_position: Vector3 = command.get("target_position", brigade.hq_position)
	var policies: Dictionary = command.get("policies", {})
	_issue_brigade_order(army, brigade, order_type, target_position, policies)


func _process_issue_battalion_order(command: Dictionary) -> void:
	if phase != CoreV2Types.BattlePhase.ACTIVE:
		return
	var army: CoreV2Army = get_army(StringName(command.get("army_id", "")))
	if army == null:
		return
	var battalion: CoreV2Battalion = get_battalion(StringName(command.get("battalion_id", "")))
	if battalion == null or battalion.army_id != army.id:
		return
	var brigade: CoreV2Brigade = army.get_brigade(battalion.brigade_id)
	if brigade == null:
		return
	var order_type: int = int(command.get("order_type", CoreV2Types.OrderType.NONE))
	var target_position: Vector3 = command.get("target_position", battalion.position)
	var policies: Dictionary = command.get("policies", {})
	_issue_battalion_order(army, brigade, battalion, order_type, target_position, policies)


func _issue_battalion_order(
		army: CoreV2Army,
		brigade: CoreV2Brigade,
		battalion: CoreV2Battalion,
		order_type: int,
		raw_target_position: Vector3,
		policies: Dictionary
) -> bool:
	if army.commander_destroyed or brigade.hq_destroyed:
		_push_event("%s: direct battalion order rejected because command chain is broken." % battalion.display_name)
		return false
	var target_position: Vector3 = project_position_to_terrain(raw_target_position)
	if not map_rect.has_point(Vector2(target_position.x, target_position.z)):
		return false
	var order: CoreV2Order = CoreV2Order.create(order_type, target_position, time_seconds, policies)
	var accepted: bool = brigade.issue_battalion_override(
		battalion.id,
		order,
		policies,
		self,
		time_seconds
	)
	if accepted:
		_push_event("%s received direct battalion override: %s." % [
			battalion.display_name,
			CoreV2Types.order_type_name(order_type),
		])
	return accepted


func _issue_brigade_order(
		army: CoreV2Army,
		brigade: CoreV2Brigade,
		order_type: int,
		raw_target_position: Vector3,
		policies: Dictionary
) -> bool:
	if army.commander_destroyed:
		_push_event("%s: штаб полководця втрачено, наказ не може бути виданий." % army.display_name)
		return false
	if brigade.hq_destroyed:
		_push_event("%s: штаб бригади втрачено, наказ не може бути прийнятий." % brigade.display_name)
		return false
	var target_position: Vector3 = project_position_to_terrain(raw_target_position)
	if not map_rect.has_point(Vector2(target_position.x, target_position.z)):
		_push_event("Наказ відхилено: ціль поза межами мапи.")
		return false
	var order: CoreV2Order = CoreV2Order.create(order_type, target_position, time_seconds, policies)
	_cancel_pending_messengers_for_brigade(army.id, brigade.id)
	var command_distance_m: float = Vector2(army.commander_position.x, army.commander_position.z).distance_to(
		Vector2(brigade.hq_position.x, brigade.hq_position.z)
	)
	if command_distance_m <= VOICE_COMMAND_RADIUS_M:
		_deliver_brigade_order(army, brigade, order, policies, "голосом")
		return true
	var messenger := CoreV2OrderMessenger.create(
		army.id,
		brigade.id,
		project_position_to_terrain(army.commander_position),
		project_position_to_terrain(brigade.hq_position),
		order,
		policies,
		time_seconds
	)
	order_messengers.append(messenger)
	_push_event("Гінець вирушив до \"%s\" з наказом \"%s\". Дистанція %.0f м." % [
		brigade.display_name,
		CoreV2Types.order_type_name(order_type),
		command_distance_m,
	])
	return true


func _deliver_brigade_order(
		army: CoreV2Army,
		brigade: CoreV2Brigade,
		order: CoreV2Order,
		policies: Dictionary,
		delivery_label: String
) -> void:
	if army == null or brigade == null or order == null:
		return
	if army.commander_destroyed or brigade.hq_destroyed:
		_push_event("%s не прийняла наказ \"%s\": командний пункт втрачено." % [
			brigade.display_name,
			CoreV2Types.order_type_name(order.order_type),
		])
		return
	brigade.issue_order(order, policies, self)
	brigade.hq_target_position = project_position_to_terrain(brigade.hq_target_position)
	for battalion_value in brigade.battalions:
		var battalion: CoreV2Battalion = battalion_value
		battalion.target_position = project_position_to_terrain(battalion.target_position)
	_push_event("%s отримала наказ \"%s\" (%s)." % [
		brigade.display_name,
		CoreV2Types.order_type_name(order.order_type),
		delivery_label,
	])


func _cancel_pending_messengers_for_brigade(army_id: StringName, brigade_id: StringName) -> void:
	var remaining_messengers: Array = []
	for messenger_value in order_messengers:
		var messenger: CoreV2OrderMessenger = messenger_value
		if messenger.army_id == army_id and messenger.brigade_id == brigade_id:
			_forget_last_seen_entity(CoreV2VisibilitySystem.messenger_key(messenger.id))
			continue
		remaining_messengers.append(messenger)
	order_messengers = remaining_messengers


func _process_start_battle(_command: Dictionary) -> void:
	if phase != CoreV2Types.BattlePhase.DEPLOYMENT:
		return
	for army_value in armies.values():
		var army: CoreV2Army = army_value
		if army.is_deployment_ready():
			continue
		_push_event("%s ще не завершила стартове розгортання." % army.display_name)
		return
	phase = CoreV2Types.BattlePhase.ACTIVE
	time_seconds = 0.0
	_visibility_accumulator = 0.0
	CoreV2VisibilitySystem.update_visibility(self)
	_push_event("Бій розпочато. Сервер перейшов у real-time режим.")


func _process_debug_force_formation(command: Dictionary) -> void:
	var army_id: StringName = StringName(command.get("army_id", ""))
	var battalion: CoreV2Battalion = get_battalion(StringName(command.get("battalion_id", "")))
	if battalion == null or battalion.army_id != army_id:
		return
	var formation_state: int = int(command.get("formation_state", battalion.desired_formation_state))
	battalion.request_formation(formation_state)
	_push_event("%s: debug-формація %s." % [
		battalion.display_name,
		CoreV2Types.formation_state_name(formation_state),
	])


func _advance_smoke_zones(delta: float) -> void:
	if smoke_zones.is_empty():
		return
	var remaining_smoke_zones: Array = []
	for smoke_value in smoke_zones:
		var smoke: Dictionary = smoke_value
		var decay_per_second: float = float(smoke.get("decay_per_second", 0.0))
		if decay_per_second > 0.0:
			smoke["density"] = max(0.0, float(smoke.get("density", 0.0)) - decay_per_second * delta)
		var expires_at_seconds: float = float(smoke.get("expires_at_seconds", -1.0))
		if expires_at_seconds > 0.0 and time_seconds >= expires_at_seconds:
			continue
		if decay_per_second > 0.0 and float(smoke.get("density", 0.0)) <= 0.025:
			continue
		remaining_smoke_zones.append(smoke)
	smoke_zones = remaining_smoke_zones


func _advance_order_messengers(delta: float) -> void:
	var remaining_messengers: Array = []
	for messenger_value in order_messengers:
		var messenger: CoreV2OrderMessenger = messenger_value
		if messenger.status != CoreV2Types.MessengerStatus.EN_ROUTE:
			continue
		var army: CoreV2Army = get_army(messenger.army_id)
		if army == null:
			continue
		var brigade: CoreV2Brigade = army.get_brigade(messenger.brigade_id)
		if brigade == null:
			continue
		messenger.target_position = project_position_to_terrain(brigade.hq_position)
		if messenger.advance(delta, self):
			messenger.delivered_at_seconds = time_seconds
			_deliver_brigade_order(army, brigade, messenger.order, messenger.policies, "гінцем")
			_forget_last_seen_entity(CoreV2VisibilitySystem.messenger_key(messenger.id))
			continue
		remaining_messengers.append(messenger)
	order_messengers = remaining_messengers


func _update_messenger_interception() -> void:
	if order_messengers.is_empty():
		return
	var remaining_messengers: Array = []
	for messenger_value in order_messengers:
		var messenger: CoreV2OrderMessenger = messenger_value
		if messenger.status != CoreV2Types.MessengerStatus.EN_ROUTE:
			continue
		var interceptor: CoreV2Battalion = _find_messenger_interceptor(messenger)
		if interceptor == null:
			remaining_messengers.append(messenger)
			continue
		messenger.status = CoreV2Types.MessengerStatus.INTERCEPTED
		messenger.intercepted_at_seconds = time_seconds
		messenger.intercepted_by_army_id = interceptor.army_id
		messenger.intercepted_by_entity_id = interceptor.id
		_forget_last_seen_entity(CoreV2VisibilitySystem.messenger_key(messenger.id))
		var target_brigade_name: String = _get_brigade_display_name(messenger.army_id, messenger.brigade_id)
		_push_event("Гінця до \"%s\" перехопив \"%s\". Наказ \"%s\" втрачено." % [
			target_brigade_name,
			interceptor.display_name,
			CoreV2Types.order_type_name(messenger.order.order_type if messenger.order != null else CoreV2Types.OrderType.NONE),
		])
	order_messengers = remaining_messengers


func _find_messenger_interceptor(messenger: CoreV2OrderMessenger) -> CoreV2Battalion:
	var messenger_key: String = CoreV2VisibilitySystem.messenger_key(messenger.id)
	for army_value in armies.values():
		var army: CoreV2Army = army_value
		if army.id == messenger.army_id:
			continue
		var visible_keys: Dictionary = visible_entity_keys_by_army.get(army.id, {})
		if not visible_keys.has(messenger_key):
			continue
		var nearest_interceptor: CoreV2Battalion = _find_nearest_interceptor_in_army(army, messenger.position)
		if nearest_interceptor != null:
			return nearest_interceptor
	return null


func _find_nearest_interceptor_in_army(army: CoreV2Army, messenger_position: Vector3) -> CoreV2Battalion:
	var nearest_interceptor: CoreV2Battalion = null
	var nearest_distance_m: float = INF
	var messenger_2d := Vector2(messenger_position.x, messenger_position.z)
	for battalion_value in army.get_all_battalions():
		var battalion: CoreV2Battalion = battalion_value
		if battalion.status == CoreV2Types.UnitStatus.ROUTING:
			continue
		var interception_radius_m: float = _get_messenger_interception_radius(battalion)
		var battalion_2d := Vector2(battalion.position.x, battalion.position.z)
		var distance_m: float = battalion_2d.distance_to(messenger_2d)
		if distance_m > interception_radius_m or distance_m >= nearest_distance_m:
			continue
		nearest_interceptor = battalion
		nearest_distance_m = distance_m
	return nearest_interceptor


func _get_messenger_interception_radius(battalion: CoreV2Battalion) -> float:
	match battalion.category:
		CoreV2Types.UnitCategory.CAVALRY:
			return MESSENGER_CAVALRY_INTERCEPTION_RADIUS_M
		CoreV2Types.UnitCategory.ARTILLERY:
			return MESSENGER_ARTILLERY_INTERCEPTION_RADIUS_M
		_:
			return MESSENGER_INFANTRY_INTERCEPTION_RADIUS_M


func _get_brigade_display_name(army_id: StringName, brigade_id: StringName) -> String:
	var army: CoreV2Army = get_army(army_id)
	if army == null:
		return String(brigade_id)
	var brigade: CoreV2Brigade = army.get_brigade(brigade_id)
	return brigade.display_name if brigade != null else String(brigade_id)


func _forget_last_seen_entity(entity_key: String) -> void:
	for army_id_value in last_seen_by_army.keys():
		var army_id: StringName = army_id_value
		var markers_by_key: Dictionary = last_seen_by_army.get(army_id, {})
		markers_by_key.erase(entity_key)
		last_seen_by_army[army_id] = markers_by_key


func _update_objective_control(delta: float) -> void:
	# Поки що стратегічні пункти рахуються просто: хто один стоїть у радіусі, той і контролює.
	for army_value in armies.values():
		var army: CoreV2Army = army_value
		army.recent_supply_income = 0.0

	for objective_value in objectives:
		var objective: CoreV2Objective = objective_value
		var presence: Dictionary = {}
		for battalion_value in get_all_battalions():
			var battalion: CoreV2Battalion = battalion_value
			if battalion.status == CoreV2Types.UnitStatus.ROUTING:
				continue
			if battalion.position.distance_to(objective.position) > objective.capture_radius_m:
				continue
			presence[battalion.army_id] = int(presence.get(battalion.army_id, 0)) + 1
		if presence.size() == 1:
			var controlling_army_id: StringName = presence.keys()[0]
			if objective.owner_army_id != controlling_army_id:
				objective.owner_army_id = controlling_army_id
				mark_rare_world_changed()
				var controlling_army: CoreV2Army = get_army(controlling_army_id)
				_push_event("%s взяла під контроль пункт \"%s\"." % [
					controlling_army.display_name if controlling_army != null else String(controlling_army_id),
					objective.display_name,
				])
		elif presence.size() > 1:
			if objective.owner_army_id != &"":
				objective.owner_army_id = &""
				mark_rare_world_changed()

		if objective.owner_army_id == &"":
			continue
		var owner_army: CoreV2Army = get_army(objective.owner_army_id)
		if owner_army == null:
			continue
		var supply_income: float = objective.resource_rate_per_second * delta
		var victory_income: float = objective.victory_rate_per_second * delta
		owner_army.supply_points += supply_income
		owner_army.recent_supply_income += supply_income
		owner_army.victory_points += victory_income
		owner_army.baggage_supply += supply_income * 0.18


func _update_resolution_state() -> void:
	for army_value in armies.values():
		var army: CoreV2Army = army_value
		if army.army_morale > 0.0 and army.victory_points < 25.0:
			continue
		phase = CoreV2Types.BattlePhase.RESOLVED
		_push_event("Бій завершено: %s досягла умови перемоги." % army.display_name)
		return


func _point_inside_zone(point: Vector3, zone_rect: Rect2) -> bool:
	return zone_rect.has_point(Vector2(point.x, point.z))


func _is_rough_terrain(point_2d: Vector2) -> bool:
	var is_rough: bool = false
	for patch_value in terrain_patches:
		var patch: Dictionary = patch_value
		var patch_rect: Rect2 = patch.get("rect", Rect2())
		if not patch_rect.has_point(point_2d):
			continue
		var terrain_type: int = int(patch.get("terrain_type", CoreV2Types.TerrainType.PLAIN))
		is_rough = terrain_type in [
			CoreV2Types.TerrainType.FOREST,
			CoreV2Types.TerrainType.MARSH,
			CoreV2Types.TerrainType.BRUSH,
			CoreV2Types.TerrainType.RAVINE,
		]
	return is_rough


func _is_point_on_road(point_2d: Vector2, road: Dictionary) -> bool:
	var points: Array = road.get("points", [])
	if points.size() < 2:
		return false
	var half_width: float = float(road.get("width_m", 0.0)) * 0.5
	for index in range(points.size() - 1):
		var from_point: Vector3 = points[index]
		var to_point: Vector3 = points[index + 1]
		var from_2d := Vector2(from_point.x, from_point.z)
		var to_2d := Vector2(to_point.x, to_point.z)
		if _distance_to_segment(point_2d, from_2d, to_2d) <= half_width:
			return true
	return false


func _get_smoke_density_at(world_position: Vector3, sightline_height: float = INF) -> float:
	var point_2d := Vector2(world_position.x, world_position.z)
	var density: float = 0.0
	for smoke_value in smoke_zones:
		var smoke: Dictionary = smoke_value
		var smoke_position: Vector3 = smoke.get("position", Vector3.ZERO)
		var smoke_radius_m: float = float(smoke.get("radius_m", 0.0))
		if smoke_radius_m <= 0.01:
			continue
		var distance_m: float = point_2d.distance_to(Vector2(smoke_position.x, smoke_position.z))
		if distance_m > smoke_radius_m:
			continue
		if sightline_height < INF and sightline_height > get_height_at(world_position) + float(smoke.get("height_m", 0.0)):
			continue
		var edge_factor: float = 1.0 - clamp(distance_m / smoke_radius_m, 0.0, 1.0)
		var smoke_density: float = float(smoke.get("density", 0.0)) * (0.35 + 0.65 * edge_factor)
		density = max(density, smoke_density)
	return clamp(density, 0.0, 1.0)


func _distance_to_segment(point: Vector2, segment_start: Vector2, segment_end: Vector2) -> float:
	var segment: Vector2 = segment_end - segment_start
	var segment_length_squared: float = segment.length_squared()
	if segment_length_squared <= 0.001:
		return point.distance_to(segment_start)
	var t: float = clamp((point - segment_start).dot(segment) / segment_length_squared, 0.0, 1.0)
	return point.distance_to(segment_start + segment * t)


func _push_event(text: String) -> void:
	recent_events.push_front(text)
	while recent_events.size() > max_recent_events:
		recent_events.pop_back()


func _update_visibility() -> void:
	CoreV2VisibilitySystem.update_visibility_staged(self)
