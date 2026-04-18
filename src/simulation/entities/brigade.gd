class_name Brigade
extends RefCounted

var id: StringName
var display_name: String = ""
var army_id: StringName = &""
var general_id: StringName = &""
var hq_id: StringName = &""
var regiment_ids: Array = []
var current_order_id: StringName = &""
var current_order_type: int = SimTypes.OrderType.HOLD
var order_policies: Dictionary = {}
var attachment_radius: float = 120.0
var target_position: Vector2 = Vector2.ZERO
var order_line_start: Vector2 = Vector2.ZERO
var order_line_end: Vector2 = Vector2.ZERO
var order_path_points: Array = []
var formation_facing: float = 0.0
var frontage_width: float = 180.0
var depth_spacing: float = 95.0
var reserve_committed: bool = false
var front_is_collapsed: bool = false
var reforming_line: bool = false
var threatened_flank: int = 0


func _init(
		brigade_id: StringName = &"",
		name_text: String = "",
		brigade_army_id: StringName = &"",
		brigade_general_id: StringName = &"",
		brigade_hq_id: StringName = &""
) -> void:
	id = brigade_id
	display_name = name_text
	army_id = brigade_army_id
	general_id = brigade_general_id
	hq_id = brigade_hq_id
