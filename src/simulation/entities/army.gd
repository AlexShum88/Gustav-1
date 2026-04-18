class_name Army
extends RefCounted

var id: StringName
var display_name: String = ""
var commander_id: StringName = &""
var general_ids: Array = []
var brigade_ids: Array = []
var detached_regiment_ids: Array = []
var baggage_hq_id: StringName = &""
var victory_points: float = 0.0
var is_ai_controlled: bool = false


func _init(army_id: StringName = &"", name_text: String = "") -> void:
	id = army_id
	display_name = name_text
