class_name CoreV2Army
extends RefCounted


var id: StringName = &""
var display_name: String = ""
var color: Color = Color.WHITE
var commander: CoreV2Commander
var commander_position: Vector3 = Vector3.ZERO
var commander_target_position: Vector3 = Vector3.ZERO
var commander_deployed: bool = false
var commander_health: float = 1.0
var commander_destroyed: bool = false
var commander_recent_damage: float = 0.0
var baggage_position: Vector3 = Vector3.ZERO
var baggage_target_position: Vector3 = Vector3.ZERO
var baggage_deployed: bool = false
var baggage_supply: float = 160.0
var baggage_ammo: float = 120.0
var army_morale: float = 1.0
var victory_points: float = 0.0
var supply_points: float = 0.0
var recent_supply_income: float = 0.0
var brigades: Array = []
var reserve_queue: Array = []
var deployment_zones: Dictionary = {}
var is_player_controlled: bool = false


func add_brigade(brigade: CoreV2Brigade) -> void:
	if brigade == null:
		return
	brigade.army_id = id
	brigades.append(brigade)
	for battalion_value in brigade.battalions:
		var battalion: CoreV2Battalion = battalion_value
		battalion.army_id = id


func get_all_battalions() -> Array:
	var result: Array = []
	for brigade_value in brigades:
		var brigade: CoreV2Brigade = brigade_value
		result.append_array(brigade.battalions)
	return result


func is_deployment_ready() -> bool:
	return baggage_deployed and commander_deployed


func get_brigade(brigade_id: StringName) -> CoreV2Brigade:
	for brigade_value in brigades:
		var brigade: CoreV2Brigade = brigade_value
		if brigade.id == brigade_id:
			return brigade
	return null


func set_commander_position(next_position: Vector3) -> void:
	commander_position = next_position
	commander_target_position = next_position
	commander_deployed = true


func set_baggage_position(next_position: Vector3) -> void:
	baggage_position = next_position
	baggage_target_position = next_position
	baggage_deployed = true


func advance(delta: float, terrain_state = null) -> void:
	for brigade_value in brigades:
		var brigade: CoreV2Brigade = brigade_value
		brigade.advance(delta, terrain_state)
	_move_hub(delta, true, terrain_state)
	_move_hub(delta, false, terrain_state)


func create_snapshot() -> Dictionary:
	return {
		"id": String(id),
		"display_name": display_name,
		"color": color,
		"commander_name": commander.display_name if commander != null else "",
		"commander_position": commander_position,
		"commander_deployed": commander_deployed,
		"commander_health": commander_health,
		"commander_destroyed": commander_destroyed,
		"commander_recent_damage": commander_recent_damage,
		"baggage_position": baggage_position,
		"baggage_deployed": baggage_deployed,
		"army_morale": army_morale,
		"baggage_supply": baggage_supply,
		"baggage_ammo": baggage_ammo,
		"victory_points": victory_points,
		"supply_points": supply_points,
		"recent_supply_income": recent_supply_income,
		"is_player_controlled": is_player_controlled,
	}


func _move_hub(delta: float, is_commander: bool, terrain_state = null) -> void:
	if is_commander and commander_destroyed:
		return
	var source_position: Vector3 = commander_position if is_commander else baggage_position
	var target_position: Vector3 = commander_target_position if is_commander else baggage_target_position
	var source_2d := Vector2(source_position.x, source_position.z)
	var target_2d := Vector2(target_position.x, target_position.z)
	var distance_to_target: float = source_2d.distance_to(target_2d)
	if distance_to_target <= 0.25:
		source_position = target_position
	else:
		var unit_category: int = CoreV2Types.UnitCategory.HQ if is_commander else CoreV2Types.UnitCategory.SUPPLY
		var speed_multiplier: float = terrain_state.get_speed_multiplier_at(source_position, unit_category) if terrain_state != null else 1.0
		var step: float = min(distance_to_target, 10.0 * speed_multiplier * delta)
		var movement_direction_2d: Vector2 = (target_2d - source_2d).normalized()
		source_position.x += movement_direction_2d.x * step
		source_position.z += movement_direction_2d.y * step
	if terrain_state != null:
		source_position.y = terrain_state.get_height_at(source_position)
	if is_commander:
		commander_position = source_position
	else:
		baggage_position = source_position
