class_name Messenger
extends SimEntity

var order_id: StringName = &""
var source_hq_id: StringName = &""
var recipient_hq_id: StringName = &""
var speed: float = 110.0
var delivery_radius: float = 18.0
var is_captured: bool = false


func _init(
		entity_id: StringName = &"",
		entity_army_id: StringName = &"",
		entity_position: Vector2 = Vector2.ZERO
) -> void:
	super._init(entity_id, "Messenger", entity_army_id, entity_position)
