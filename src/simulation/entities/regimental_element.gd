class_name RegimentalElement
extends RefCounted

var id: StringName = &""
var display_name: String = ""
var element_type: int = SimTypes.RegimentalElementType.BANNER
var local_position: Vector2 = Vector2.ZERO
var target_local_position: Vector2 = Vector2.ZERO
var front_direction: Vector2 = Vector2.RIGHT
var assigned_slot_id: StringName = &""
var placeholder_key: StringName = &"banner"


func _init(
		element_id: StringName = &"",
		name_text: String = "",
		initial_type: int = SimTypes.RegimentalElementType.BANNER
) -> void:
	id = element_id
	display_name = name_text
	element_type = initial_type
