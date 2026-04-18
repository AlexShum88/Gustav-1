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
var movement_path: Array = []
var combat_target_id: StringName = &""
var combat_target_name: String = ""
var combat_range_m: float = 0.0
var combat_cooldown_seconds: float = 0.0
var combat_reload_seconds: float = 0.0
var combat_attack_kind: String = ""
var combat_melee_blocks: int = 0
var recent_casualties_inflicted: int = 0
var recent_casualties_taken: int = 0
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
var desired_formation_state: int = CoreV2Types.FormationState.LINE
var formation_frontage_m: float = 0.0
var desired_formation_frontage_m: float = 0.0
var sprite_offsets: Array = []
var sprite_offset_velocities: Array = []
var sprite_target_offsets: Array = []
var sprite_reform_from_offsets: Array = []
var sprite_roles: Array = []
var sprite_blocks: Array = []
var formation_elapsed_seconds: float = 0.0
var formation_duration_seconds: float = 1.0
var formation_progress: float = 1.0
var is_reforming: bool = false


func set_target(next_target: Vector3, order: CoreV2Order, next_movement_path: Array = [], next_facing: Vector3 = Vector3.ZERO) -> void:
	target_position = next_target
	current_order = order
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


func advance(delta: float, terrain_state = null) -> void:
	var position_2d := Vector2(position.x, position.z)
	var active_target: Vector3 = _get_active_movement_target()
	var target_2d := Vector2(active_target.x, active_target.z)
	var distance_to_target: float = position_2d.distance_to(target_2d)
	if distance_to_target <= WAYPOINT_ARRIVAL_RADIUS_M:
		_arrive_at_active_waypoint(terrain_state)
		_turn_toward_target_facing(delta, terrain_state)
		CoreV2FormationSystem.advance_battalion(self, delta, terrain_state)
		return

	# Рух іде до активного waypoint; швидкість бере terrain/road multiplier із server-state.
	var speed_multiplier: float = terrain_state.get_speed_multiplier_at(position, category) if terrain_state != null else 1.0
	var step: float = min(distance_to_target, move_speed_mps * speed_multiplier * delta)
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
		"is_reforming": is_reforming,
		"formation_progress": formation_progress,
		"status": status,
		"status_label": CoreV2Types.unit_status_name(status),
		"position": position,
		"target_position": target_position,
		"target_facing": target_facing,
		"facing": facing,
		"soldiers_total": soldiers_total,
		"sprite_count": sprite_count,
		"cohesion": cohesion,
		"ammunition": ammunition,
		"forage": forage,
		"training": training,
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
		"combat_melee_blocks": combat_melee_blocks,
		"recent_casualties_inflicted": recent_casualties_inflicted,
		"recent_casualties_taken": recent_casualties_taken,
		"recent_combat_event": recent_combat_event,
		"engagement_target_id": String(engagement_target_id),
		"engagement_mode": engagement_mode,
		"engagement_desired_range_m": engagement_desired_range_m,
		"engagement_target_lock_seconds": engagement_target_lock_seconds,
		"engagement_formation_cooldown_seconds": engagement_formation_cooldown_seconds,
		"separation_contacts": separation_contacts,
		"separation_push_m": separation_push_m,
		"formation_pressure_direction": formation_pressure_direction,
		"formation_pressure_m": formation_pressure_m,
		"sprite_block_targets": _create_sprite_block_target_snapshot(),
		"sprite_offsets": sprite_offsets.duplicate(true),
		"sprite_target_offsets": sprite_target_offsets.duplicate(true),
		"sprite_roles": sprite_roles.duplicate(true),
		"is_friendly": army_id == player_army_id,
		"commander_name": commander.display_name if commander != null else "",
		"order_label": CoreV2Types.order_type_name(
			current_order.order_type if current_order != null else CoreV2Types.OrderType.NONE
		),
		"order_type": current_order.order_type if current_order != null else CoreV2Types.OrderType.NONE,
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
