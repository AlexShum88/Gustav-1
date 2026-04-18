class_name CoreV2OrderMessenger
extends RefCounted


const ARRIVAL_RADIUS_M: float = 18.0

static var _next_messenger_id: int = 1

var id: StringName = &""
var army_id: StringName = &""
var brigade_id: StringName = &""
var display_name: String = ""
var origin_position: Vector3 = Vector3.ZERO
var position: Vector3 = Vector3.ZERO
var target_position: Vector3 = Vector3.ZERO
var move_speed_mps: float = 95.0
var order: CoreV2Order
var policies: Dictionary = {}
var issued_at_seconds: float = 0.0
var delivered_at_seconds: float = 0.0
var intercepted_at_seconds: float = 0.0
var intercepted_by_army_id: StringName = &""
var intercepted_by_entity_id: StringName = &""
var status: int = CoreV2Types.MessengerStatus.EN_ROUTE


static func create(
		new_army_id: StringName,
		new_brigade_id: StringName,
		start_position: Vector3,
		destination_position: Vector3,
		new_order: CoreV2Order,
		new_policies: Dictionary,
		created_at_seconds: float
) -> CoreV2OrderMessenger:
	var messenger := CoreV2OrderMessenger.new()
	messenger.id = StringName("core_v2_messenger_%03d" % _next_messenger_id)
	_next_messenger_id += 1
	messenger.army_id = new_army_id
	messenger.brigade_id = new_brigade_id
	messenger.display_name = "Гінець"
	messenger.origin_position = start_position
	messenger.position = start_position
	messenger.target_position = destination_position
	messenger.order = new_order
	messenger.policies = new_policies.duplicate(true)
	messenger.issued_at_seconds = created_at_seconds
	return messenger


func advance(delta: float, terrain_state = null) -> bool:
	if status != CoreV2Types.MessengerStatus.EN_ROUTE:
		return false
	var position_2d := Vector2(position.x, position.z)
	var target_2d := Vector2(target_position.x, target_position.z)
	var distance_to_target: float = position_2d.distance_to(target_2d)
	if distance_to_target <= ARRIVAL_RADIUS_M:
		position = target_position
		if terrain_state != null:
			position.y = terrain_state.get_height_at(position)
		status = CoreV2Types.MessengerStatus.DELIVERED
		return true
	var speed_multiplier: float = terrain_state.get_speed_multiplier_at(position, CoreV2Types.UnitCategory.CAVALRY) if terrain_state != null else 1.0
	var step: float = min(distance_to_target, move_speed_mps * speed_multiplier * delta)
	var movement_direction_2d: Vector2 = (target_2d - position_2d).normalized()
	position.x += movement_direction_2d.x * step
	position.z += movement_direction_2d.y * step
	if terrain_state != null:
		position.y = terrain_state.get_height_at(position)
	return false


func create_snapshot(player_army_id: StringName) -> Dictionary:
	var order_snapshot: Dictionary = order.create_snapshot() if order != null else {}
	var distance_remaining_m: float = Vector2(position.x, position.z).distance_to(Vector2(target_position.x, target_position.z))
	return {
		"id": String(id),
		"army_id": String(army_id),
		"brigade_id": String(brigade_id),
		"display_name": display_name,
		"entity_kind": CoreV2Types.EntityKind.MESSENGER,
		"position": position,
		"target_position": target_position,
		"origin_position": origin_position,
		"move_speed_mps": move_speed_mps,
		"status": status,
		"status_label": CoreV2Types.messenger_status_name(status),
		"order_id": String(order.id) if order != null else "",
		"order_type": int(order_snapshot.get("order_type", CoreV2Types.OrderType.NONE)),
		"order_label": String(order_snapshot.get("order_label", "Без наказу")),
		"issued_at_seconds": issued_at_seconds,
		"delivered_at_seconds": delivered_at_seconds,
		"intercepted_at_seconds": intercepted_at_seconds,
		"intercepted_by_army_id": String(intercepted_by_army_id),
		"intercepted_by_entity_id": String(intercepted_by_entity_id),
		"distance_remaining_m": distance_remaining_m,
		"is_friendly": army_id == player_army_id,
	}
