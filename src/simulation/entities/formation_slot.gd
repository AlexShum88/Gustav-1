class_name FormationSlot
extends RefCounted

var id: StringName = &""
var local_position: Vector2 = Vector2.ZERO
var facing_direction: Vector2 = Vector2.RIGHT
var role: StringName = &"line"
var tolerance_radius: float = 12.0
var occupant_company_id: StringName = &""


func _init(
		slot_id: StringName = &"",
		position_value: Vector2 = Vector2.ZERO,
		facing_value: Vector2 = Vector2.RIGHT,
		role_value: StringName = &"line",
		tolerance_value: float = 12.0
) -> void:
	id = slot_id
	local_position = position_value
	facing_direction = facing_value.normalized() if facing_value.length_squared() > 0.001 else Vector2.RIGHT
	role = role_value
	tolerance_radius = tolerance_value
