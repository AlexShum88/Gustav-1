class_name RegimentBannerProfile
extends RefCounted

var id: StringName = &""
var display_name: String = ""
var placeholder_key: StringName = &"banner"


func _init(
		profile_id: StringName = &"",
		name_text: String = "",
		banner_placeholder_key: StringName = &"banner"
) -> void:
	id = profile_id
	display_name = name_text
	placeholder_key = banner_placeholder_key
