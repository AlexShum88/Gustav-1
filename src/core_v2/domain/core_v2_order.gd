class_name CoreV2Order
extends RefCounted


static var _next_order_id: int = 1

var id: StringName = &""
var order_type: int = CoreV2Types.OrderType.NONE
var target_position: Vector3 = Vector3.ZERO
var issued_at_seconds: float = 0.0
var policies: Dictionary = {}


static func create(new_order_type: int, new_target_position: Vector3, issued_at: float, new_policies: Dictionary = {}) -> CoreV2Order:
	var order := CoreV2Order.new()
	order.id = StringName("core_v2_order_%03d" % _next_order_id)
	_next_order_id += 1
	order.order_type = new_order_type
	order.target_position = new_target_position
	order.issued_at_seconds = issued_at
	order.policies = new_policies.duplicate(true)
	return order


func create_snapshot() -> Dictionary:
	return {
		"id": String(id),
		"order_type": order_type,
		"order_label": CoreV2Types.order_type_name(order_type),
		"target_position": target_position,
		"issued_at_seconds": issued_at_seconds,
		"policies": policies.duplicate(true),
	}
