class_name RegimentCommandProfile
extends RefCounted

var id: StringName = &""
var display_name: String = ""
var max_companies: int = 4
var reform_speed_multiplier: float = 1.0
var banner_reform_speed_multiplier: float = 1.0
var command_quality_bonus: float = 0.0


func _init(
		profile_id: StringName = &"",
		name_text: String = "",
		company_capacity: int = 4,
		reform_multiplier: float = 1.0,
		banner_reform_multiplier: float = 1.0,
		quality_bonus: float = 0.0
) -> void:
	id = profile_id
	display_name = name_text
	max_companies = max(1, company_capacity)
	reform_speed_multiplier = max(0.2, reform_multiplier)
	banner_reform_speed_multiplier = max(0.2, banner_reform_multiplier)
	command_quality_bonus = quality_bonus
