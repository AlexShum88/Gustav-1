class_name Subunit
extends RefCounted

var display_name: String = ""
var category: int = SimTypes.UnitCategory.INFANTRY
var weapon_type: String = "musket"
var soldiers: int = 120
var training: float = 0.6
var local_position: Vector2 = Vector2.ZERO
var target_local_position: Vector2 = Vector2.ZERO


func _init(
		name_text: String = "",
		initial_category: int = SimTypes.UnitCategory.INFANTRY,
		initial_weapon_type: String = "musket",
		initial_soldiers: int = 120,
		initial_training: float = 0.6
) -> void:
	display_name = name_text
	category = initial_category
	weapon_type = initial_weapon_type
	soldiers = initial_soldiers
	training = initial_training


func get_max_range() -> float:
	match weapon_type:
		"cannon":
			return 250.0
		"carbine":
			return 135.0
		"pistol":
			return 70.0
		"pike":
			return 24.0
		_:
			return 165.0


func get_base_firepower() -> float:
	match weapon_type:
		"cannon":
			return 2.5
		"carbine":
			return 1.1
		"pistol":
			return 0.8
		"pike":
			return 0.72
		_:
			return 1.0


func get_effective_firepower() -> float:
	return soldiers * get_base_firepower() * lerpf(0.55, 1.25, clamp(training, 0.0, 1.0))
