class_name SimEntity
extends RefCounted

var id: StringName
var display_name: String = ""
var army_id: StringName = &""
var position: Vector2 = Vector2.ZERO
var facing_angle: float = 0.0
var is_destroyed: bool = false


func _init(
		entity_id: StringName = &"",
		entity_name: String = "",
		entity_army_id: StringName = &"",
		entity_position: Vector2 = Vector2.ZERO
) -> void:
	id = entity_id
	display_name = entity_name
	army_id = entity_army_id
	position = entity_position


func move_toward(target: Vector2, speed: float, delta: float) -> void:
	var offset: Vector2 = target - position
	if offset.length() <= 0.001:
		return
	var step: float = min(offset.length(), speed * delta)
	position += offset.normalized() * step
	facing_angle = offset.angle()
