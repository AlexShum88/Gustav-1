class_name SimOrder
extends RefCounted

var id: StringName
var issuer_army_id: StringName = &""
var issuer_hq_id: StringName = &""
var recipient_brigade_id: StringName = &""
var order_type: int = SimTypes.OrderType.NONE
var target_position: Vector2 = Vector2.ZERO
var line_start: Vector2 = Vector2.ZERO
var line_end: Vector2 = Vector2.ZERO
var path_points: Array = []
var policies: Dictionary = {}
var issued_at: float = 0.0
var delivered_at: float = -1.0
var status: int = SimTypes.OrderStatus.CREATED
var delivery_method: int = SimTypes.DeliveryMethod.MESSENGER
var failure_reason: String = ""


func get_summary() -> String:
	return "%s to %s" % [
		SimTypes.order_type_name(order_type),
		recipient_brigade_id,
	]
