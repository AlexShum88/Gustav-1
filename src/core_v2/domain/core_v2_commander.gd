class_name CoreV2Commander
extends RefCounted


var id: StringName = &""
var display_name: String = ""
var command_rating: float = 0.75
var morale_rating: float = 0.75
var is_alive: bool = true


func create_snapshot() -> Dictionary:
	return {
		"id": String(id),
		"display_name": display_name,
		"command_rating": command_rating,
		"morale_rating": morale_rating,
		"is_alive": is_alive,
	}
