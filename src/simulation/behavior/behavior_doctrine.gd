class_name BehaviorDoctrine
extends RefCounted


var id: StringName = &""
var display_name: String = ""
var effective_fire_range_multiplier: float = 0.58
var march_speed_multiplier: float = 1.18
var attack_speed_multiplier: float = 0.9
var high_fatigue_speed_multiplier: float = 0.88
var reserve_offset_distance: float = 80.0
var contact_deploy_distance: float = 220.0
var anti_cavalry_square_distance: float = 90.0
var flank_pressure_radius: float = 180.0
var flank_pressure_margin: int = 1
var firearm_contact_mode: int = SimTypes.FirearmContactMode.HALT_AND_FIRE
var shock_contact_mode: int = SimTypes.ShockContactMode.ASSAULT
var fire_hold_distance_ratio: float = 0.9
var assault_distance_ratio: float = 1.18
var retarget_distance_ratio: float = 0.78
var disengage_suppression_threshold: float = 0.46
var disengage_casualty_rate_threshold: float = 0.08
var assault_confidence_threshold: float = 0.68
var withdraw_distance: float = 140.0
var recovery_duration: float = 2.0
var state_hold_duration: float = 1.2
var firefight_anchor_leash: float = 10.0


func _init(doctrine_id: StringName = &"", doctrine_name: String = "") -> void:
	id = doctrine_id
	display_name = doctrine_name
