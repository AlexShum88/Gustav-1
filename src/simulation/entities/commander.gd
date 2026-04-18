class_name Commander
extends RefCounted

var id: StringName
var display_name: String = ""
var army_id: StringName = &""
var hq_id: StringName = &""
var command_voice_radius: float = 175.0
var command_quality: float = 0.85
var is_alive: bool = true


func _init(
		leader_id: StringName = &"",
		name_text: String = "",
		leader_army_id: StringName = &"",
		leader_hq_id: StringName = &""
) -> void:
	id = leader_id
	display_name = name_text
	army_id = leader_army_id
	hq_id = leader_hq_id
