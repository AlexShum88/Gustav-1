class_name FormationLayout
extends RefCounted

# Layout stores target slots for company modules.

var name: StringName = &""
var slots: Array = []


func _init(layout_name: StringName = &"") -> void:
	name = layout_name


func add_slot(module, local_position: Vector2, facing_angle: float, metadata: Dictionary = {}) -> void:
	slots.append({
		"module": module,
		"local_position": local_position,
		"facing_angle": facing_angle,
		"metadata": metadata.duplicate(true),
	})


func get_slot_count() -> int:
	return slots.size()
