class_name CoreV2CombatEngagement
extends RefCounted


var id: StringName = &""
var participants_attackers: Array = []
var participants_defenders: Array = []
var contact_type: String = "ranged_skirmish"
var center: Vector3 = Vector3.ZERO
var sector_geometry: Dictionary = {}
var engagement_intensity: float = 0.0
var local_advantage_state: Dictionary = {}


static func create(
		engagement_id: StringName,
		attacker: CoreV2Battalion,
		defender: CoreV2Battalion,
		next_contact_type: String,
		next_center: Vector3,
		next_sector_geometry: Dictionary
) -> CoreV2CombatEngagement:
	var engagement := CoreV2CombatEngagement.new()
	engagement.id = engagement_id
	engagement.participants_attackers = [attacker]
	engagement.participants_defenders = [defender]
	engagement.contact_type = next_contact_type
	engagement.center = next_center
	engagement.sector_geometry = next_sector_geometry.duplicate(true)
	return engagement
