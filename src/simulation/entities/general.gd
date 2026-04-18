class_name General
extends RefCounted

var id: StringName
var display_name: String = ""
var army_id: StringName = &""
var hq_id: StringName = &""
var brigade_id: StringName = &""
var command_voice_radius: float = 125.0
var command_quality: float = 0.72
var rally_power: float = 0.14
var is_alive: bool = true
var aggression: float = 0.62
var caution: float = 0.46
var decision_interval_seconds: float = 6.0
var next_decision_time: float = 0.0


func _init(
		leader_id: StringName = &"",
		name_text: String = "",
		leader_army_id: StringName = &"",
		leader_hq_id: StringName = &"",
		leader_brigade_id: StringName = &""
) -> void:
	id = leader_id
	display_name = name_text
	army_id = leader_army_id
	hq_id = leader_hq_id
	brigade_id = leader_brigade_id
