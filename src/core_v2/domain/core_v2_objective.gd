class_name CoreV2Objective
extends RefCounted


var id: StringName = &""
var display_name: String = ""
var terrain_type: String = "village"
var position: Vector3 = Vector3.ZERO
var capture_radius_m: float = 240.0
var owner_army_id: StringName = &""
var victory_rate_per_second: float = 0.25
var resource_rate_per_second: float = 0.5


func create_snapshot() -> Dictionary:
	return {
		"id": String(id),
		"display_name": display_name,
		"terrain_type": terrain_type,
		"position": position,
		"capture_radius_m": capture_radius_m,
		"owner_army_id": String(owner_army_id),
		"victory_rate_per_second": victory_rate_per_second,
		"resource_rate_per_second": resource_rate_per_second,
	}
