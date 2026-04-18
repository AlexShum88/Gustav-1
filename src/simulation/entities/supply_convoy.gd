class_name SupplyConvoy
extends SimEntity

var source_hq_id: StringName = &""
var recipient_brigade_id: StringName = &""
var target_hq_id: StringName = &""
var supply_load_amount: float = 0.18
var ammo_load_amount: float = 0.18
var speed: float = 54.0
var is_destroyed_in_transit: bool = false


func _init(
		entity_id: StringName = &"",
		entity_army_id: StringName = &"",
		entity_position: Vector2 = Vector2.ZERO
) -> void:
	super._init(entity_id, "Supply Convoy", entity_army_id, entity_position)
