class_name CoreV2BattalionCombatModel
extends RefCounted


const PIKE_BASE_SHARE: float = 0.36
const LEFT_SHOT_BASE_SHARE: float = 0.32
const RIGHT_SHOT_BASE_SHARE: float = 0.32


static func initialize_composite(battalion: CoreV2Battalion) -> void:
	if battalion == null:
		return
	var total: float = float(max(0, battalion.soldiers_total))
	if battalion.category == CoreV2Types.UnitCategory.INFANTRY:
		battalion.pike_strength = total * PIKE_BASE_SHARE
		battalion.shot_strength_left = total * LEFT_SHOT_BASE_SHARE
		battalion.shot_strength_right = total * RIGHT_SHOT_BASE_SHARE
	elif battalion.category == CoreV2Types.UnitCategory.CAVALRY:
		battalion.pike_strength = total
		battalion.shot_strength_left = 0.0
		battalion.shot_strength_right = 0.0
	else:
		battalion.pike_strength = 0.0
		battalion.shot_strength_left = total
		battalion.shot_strength_right = 0.0
	_normalize_composition_to_total(battalion)
	update_condition(battalion, null)


static func update_condition(battalion: CoreV2Battalion, state: CoreV2BattleState) -> void:
	if battalion == null:
		return
	_normalize_composition_to_total(battalion)
	var terrain_speed: float = state.get_speed_multiplier_at(battalion.position, battalion.category) if state != null else 1.0
	var terrain_defense: float = state.get_defense_modifier_at(battalion.position) if state != null else 0.0
	var smoke_density: float = state.get_smoke_density_at(battalion.position) if state != null else battalion.smoke_burden
	battalion.terrain_distortion = _resolve_terrain_order_strain(state, battalion, terrain_speed, terrain_defense)
	battalion.smoke_burden = lerp(battalion.smoke_burden, smoke_density, 0.35)
	battalion.alignment_score = clamp(
		battalion.alignment_score - battalion.terrain_distortion * 0.014 - battalion.disorder * 0.010 - battalion.contact_pressure * 0.012,
		0.0,
		1.0
	)
	if not battalion.is_reforming and battalion.separation_contacts <= 0 and not battalion.is_in_contact:
		battalion.alignment_score = min(1.0, battalion.alignment_score + 0.006)
	battalion.front_continuity = clamp(1.0 - battalion.disorder * 0.42 - battalion.interpenetration_stress * 0.28 - battalion.compression_level * 0.42, 0.0, 1.0)
	battalion.depth_cohesion = clamp(1.0 - battalion.fatigue * 0.30 - battalion.terrain_distortion * 0.25 - battalion.contact_pressure * 0.18, 0.0, 1.0)
	battalion.ammo_state = clamp(battalion.ammunition, 0.0, 1.0)
	if battalion.is_reforming:
		battalion.disorder = min(1.0, battalion.disorder + 0.006 + battalion.terrain_distortion * 0.004)
	if battalion.suppression > 0.0:
		battalion.suppression = max(0.0, battalion.suppression - (0.0009 if battalion.is_in_contact else 0.0018))
	if battalion.disorder > 0.0 and not battalion.is_reforming and not battalion.is_in_contact:
		var recovery: float = 0.0018 * clamp((battalion.drill_quality + battalion.officer_quality) * 0.5, 0.2, 1.0)
		battalion.disorder = max(0.0, battalion.disorder - recovery)
	_maybe_degrade_fire_doctrine(battalion)


static func build_outputs(state: CoreV2BattleState, battalion: CoreV2Battalion) -> Dictionary:
	update_condition(battalion, state)
	return {
		"fire_output": resolve_fire_output(battalion),
		"melee_output": resolve_melee_output(battalion),
		"staying_power": resolve_staying_power(state, battalion),
		"maneuver_power": resolve_maneuver_power(state, battalion),
	}


static func resolve_fire_output(battalion: CoreV2Battalion) -> float:
	if battalion.category == CoreV2Types.UnitCategory.CAVALRY:
		return 0.0
	var shot_strength: float = battalion.shot_strength_left + battalion.shot_strength_right
	if battalion.category == CoreV2Types.UnitCategory.ARTILLERY:
		shot_strength = max(1.0, float(battalion.soldiers_total)) * 0.35
	var doctrine: Dictionary = _resolve_fire_doctrine_modifiers(battalion)
	var formation_factor: float = _resolve_formation_fire_factor(battalion)
	var active_rank_share: float = _resolve_active_fire_rank_share(battalion)
	var pressure_factor: float = clamp(
		1.0 - battalion.suppression * 0.65 - battalion.disorder * 0.55 - battalion.smoke_burden * 0.48 - battalion.contact_pressure * 0.35 - battalion.terrain_distortion * 0.28,
		0.08,
		1.15
	)
	var quality_factor: float = clamp((battalion.drill_quality * 0.62 + battalion.officer_quality * 0.18 + battalion.cohesion * 0.2), 0.12, 1.18)
	return shot_strength * active_rank_share * battalion.ammo_state * formation_factor * pressure_factor * quality_factor * float(doctrine.get("fire_output", 1.0))


static func resolve_melee_output(battalion: CoreV2Battalion) -> float:
	var formation_factor: float = _resolve_formation_melee_factor(battalion)
	var condition_factor: float = clamp(battalion.cohesion * 0.48 + battalion.morale * 0.32 + (1.0 - battalion.fatigue) * 0.2, 0.08, 1.15)
	var disorder_factor: float = clamp(1.0 - battalion.disorder * 0.72 - battalion.suppression * 0.28 - battalion.compression_level * 0.18 - battalion.terrain_distortion * 0.22, 0.05, 1.0)
	var alignment_factor: float = clamp(battalion.alignment_score * 0.62 + battalion.front_continuity * 0.38, 0.12, 1.08)
	if battalion.category == CoreV2Types.UnitCategory.CAVALRY:
		return float(battalion.soldiers_total) * 1.32 * condition_factor * disorder_factor * formation_factor * alignment_factor
	return (battalion.pike_strength * 1.38 + (battalion.shot_strength_left + battalion.shot_strength_right) * 0.38) * condition_factor * disorder_factor * formation_factor * alignment_factor


static func resolve_staying_power(state: CoreV2BattleState, battalion: CoreV2Battalion) -> float:
	var terrain_defense: float = state.get_defense_modifier_at(battalion.position) if state != null else 0.0
	var depth_factor: float = _resolve_formation_depth_factor(battalion)
	var command_factor: float = clamp((battalion.officer_quality + battalion.morale) * 0.5, 0.1, 1.12)
	var contact_penalty: float = clamp(1.0 - battalion.compression_level * 0.24 - battalion.contact_pressure * 0.16, 0.35, 1.0)
	var terrain_order_factor: float = clamp(1.0 - battalion.terrain_distortion * 0.18, 0.62, 1.0)
	return float(max(1, battalion.soldiers_total)) * depth_factor * command_factor * battalion.front_continuity * battalion.depth_cohesion * contact_penalty * terrain_order_factor * (1.0 + terrain_defense)


static func resolve_maneuver_power(state: CoreV2BattleState, battalion: CoreV2Battalion) -> float:
	var terrain_speed: float = state.get_speed_multiplier_at(battalion.position, battalion.category) if state != null else 1.0
	var formation_factor: float = _resolve_formation_maneuver_factor(battalion)
	var drill_factor: float = clamp(battalion.drill_quality * 0.72 + battalion.cohesion * 0.28, 0.1, 1.08)
	var contact_factor: float = clamp(1.0 - battalion.contact_pressure * 0.72 - battalion.compression_level * 0.38, 0.05, 1.0)
	return battalion.move_speed_mps * terrain_speed * formation_factor * drill_factor * contact_factor * clamp(1.0 - battalion.disorder * 0.72 - battalion.fatigue * 0.45 - battalion.terrain_distortion * 0.34, 0.08, 1.0)


static func apply_material_loss(battalion: CoreV2Battalion, casualties: int, pressure_is_melee: bool) -> void:
	if battalion == null or casualties <= 0:
		return
	var remaining_loss: float = float(min(casualties, battalion.soldiers_total))
	var pike_weight: float = 1.25 if pressure_is_melee else 0.82
	var left_weight: float = 0.88 if pressure_is_melee else 1.05
	var right_weight: float = left_weight
	var total_weight: float = battalion.pike_strength * pike_weight + battalion.shot_strength_left * left_weight + battalion.shot_strength_right * right_weight
	if total_weight <= 0.001:
		battalion.soldiers_total = max(0, battalion.soldiers_total - int(remaining_loss))
		return
	var pike_loss: float = min(battalion.pike_strength, remaining_loss * (battalion.pike_strength * pike_weight / total_weight))
	var left_loss: float = min(battalion.shot_strength_left, remaining_loss * (battalion.shot_strength_left * left_weight / total_weight))
	var right_loss: float = min(battalion.shot_strength_right, remaining_loss * (battalion.shot_strength_right * right_weight / total_weight))
	battalion.pike_strength = max(0.0, battalion.pike_strength - pike_loss)
	battalion.shot_strength_left = max(0.0, battalion.shot_strength_left - left_loss)
	battalion.shot_strength_right = max(0.0, battalion.shot_strength_right - right_loss)
	battalion.soldiers_total = max(0, battalion.soldiers_total - int(round(pike_loss + left_loss + right_loss)))
	_normalize_composition_to_total(battalion)


static func apply_functional_loss(
		battalion: CoreV2Battalion,
		cohesion_loss: float,
		morale_loss: float,
		suppression_gain: float,
		disorder_gain: float,
		alignment_loss: float
) -> void:
	if battalion == null:
		return
	battalion.cohesion = clamp(battalion.cohesion - cohesion_loss, 0.0, 1.0)
	battalion.morale = clamp(battalion.morale - morale_loss, 0.0, 1.0)
	battalion.suppression = clamp(battalion.suppression + suppression_gain, 0.0, 1.0)
	battalion.disorder = clamp(battalion.disorder + disorder_gain, 0.0, 1.0)
	battalion.alignment_score = clamp(battalion.alignment_score - alignment_loss, 0.0, 1.0)
	_maybe_degrade_fire_doctrine(battalion)


static func _normalize_composition_to_total(battalion: CoreV2Battalion) -> void:
	var total_components: float = battalion.pike_strength + battalion.shot_strength_left + battalion.shot_strength_right
	var total_soldiers: float = float(max(0, battalion.soldiers_total))
	if total_soldiers <= 0.0:
		battalion.pike_strength = 0.0
		battalion.shot_strength_left = 0.0
		battalion.shot_strength_right = 0.0
		return
	if total_components <= 0.001:
		initialize_composite(battalion)
		return
	var scale: float = total_soldiers / total_components
	battalion.pike_strength *= scale
	battalion.shot_strength_left *= scale
	battalion.shot_strength_right *= scale


static func _resolve_terrain_order_strain(state: CoreV2BattleState, battalion: CoreV2Battalion, terrain_speed: float, terrain_defense: float) -> float:
	# Терен у цій моделі не тільки гальмує рух, а й руйнує здатність маси людей тримати фронт і процедуру вогню.
	var type_strain: float = 0.0
	if state != null:
		match state.get_terrain_type_at(battalion.position):
			CoreV2Types.TerrainType.FOREST:
				type_strain = 0.22
			CoreV2Types.TerrainType.MARSH:
				type_strain = 0.34
			CoreV2Types.TerrainType.BRUSH:
				type_strain = 0.16
			CoreV2Types.TerrainType.FARM:
				type_strain = 0.12
			CoreV2Types.TerrainType.VILLAGE:
				type_strain = 0.20
			CoreV2Types.TerrainType.TOWN:
				type_strain = 0.26
			CoreV2Types.TerrainType.HILL:
				type_strain = 0.10
			CoreV2Types.TerrainType.RAVINE:
				type_strain = 0.38
			_:
				type_strain = 0.0
	var speed_strain: float = max(0.0, 1.0 - terrain_speed) * 0.82
	var cover_strain: float = max(0.0, terrain_defense) * 0.18
	var pressure_strain: float = battalion.movement_strain * 0.28 + battalion.contact_pressure * 0.16 + battalion.compression_level * 0.10
	return clamp(speed_strain + cover_strain + type_strain + pressure_strain, 0.0, 1.0)


static func _resolve_fire_doctrine_modifiers(battalion: CoreV2Battalion) -> Dictionary:
	match battalion.fire_doctrine:
		CoreV2Types.FireDoctrine.COUNTERMARCH:
			return {
				"fire_output": lerp(0.72, 1.18, battalion.drill_quality) * clamp(battalion.alignment_score, 0.2, 1.0),
				"smoke": 1.08,
			}
		CoreV2Types.FireDoctrine.ROLLING_FIRE:
			return {"fire_output": 1.04, "smoke": 1.0}
		CoreV2Types.FireDoctrine.IRREGULAR_FIRE:
			return {"fire_output": 0.58, "smoke": 1.22}
		_:
			return {"fire_output": 0.92 + battalion.volley_readiness * 0.28, "smoke": 0.92}


static func _resolve_active_fire_rank_share(battalion: CoreV2Battalion) -> float:
	if battalion.category == CoreV2Types.UnitCategory.ARTILLERY:
		return 1.0
	match battalion.formation_state:
		CoreV2Types.FormationState.MUSKETEER_LINE:
			return 0.48
		CoreV2Types.FormationState.LINE:
			return 0.36
		CoreV2Types.FormationState.TERCIA:
			return 0.24
		CoreV2Types.FormationState.DEFENSIVE:
			return 0.22
		CoreV2Types.FormationState.COLUMN:
			return 0.18
		CoreV2Types.FormationState.MARCH_COLUMN:
			return 0.10
		_:
			return 0.16


static func _maybe_degrade_fire_doctrine(battalion: CoreV2Battalion) -> void:
	var ordered_stress: float = battalion.suppression * 0.34 + battalion.disorder * 0.32 + (1.0 - battalion.alignment_score) * 0.24
	ordered_stress += battalion.terrain_distortion * 0.16 + battalion.contact_pressure * 0.22
	ordered_stress -= battalion.drill_quality * 0.22
	if battalion.fire_doctrine == CoreV2Types.FireDoctrine.COUNTERMARCH and ordered_stress > 0.46:
		battalion.fire_doctrine = CoreV2Types.FireDoctrine.IRREGULAR_FIRE
		battalion.recent_combat_event = "Fire procedure broke into irregular fire"
	elif battalion.fire_doctrine == CoreV2Types.FireDoctrine.ROLLING_FIRE and ordered_stress > 0.58:
		battalion.fire_doctrine = CoreV2Types.FireDoctrine.IRREGULAR_FIRE
		battalion.recent_combat_event = "Rolling fire broke into irregular fire"
	elif battalion.fire_doctrine == CoreV2Types.FireDoctrine.SALVO and ordered_stress > 0.70:
		battalion.fire_doctrine = CoreV2Types.FireDoctrine.IRREGULAR_FIRE
		battalion.recent_combat_event = "Salvo fire broke into irregular fire"


static func _resolve_formation_fire_factor(battalion: CoreV2Battalion) -> float:
	var reform_penalty: float = 0.64 if battalion.is_reforming else 1.0
	match battalion.formation_state:
		CoreV2Types.FormationState.MUSKETEER_LINE:
			return 1.18 * reform_penalty
		CoreV2Types.FormationState.LINE:
			return 1.0 * reform_penalty
		CoreV2Types.FormationState.TERCIA:
			return 0.72 * reform_penalty
		CoreV2Types.FormationState.COLUMN, CoreV2Types.FormationState.MARCH_COLUMN:
			return 0.42 * reform_penalty
		CoreV2Types.FormationState.DEFENSIVE:
			return 0.58 * reform_penalty
		_:
			return 0.35


static func _resolve_formation_melee_factor(battalion: CoreV2Battalion) -> float:
	var reform_penalty: float = 0.72 if battalion.is_reforming else 1.0
	match battalion.formation_state:
		CoreV2Types.FormationState.DEFENSIVE:
			return 1.28 * reform_penalty
		CoreV2Types.FormationState.TERCIA:
			return 1.16 * reform_penalty
		CoreV2Types.FormationState.COLUMN:
			return 1.02 * reform_penalty
		CoreV2Types.FormationState.MARCH_COLUMN:
			return 0.62 * reform_penalty
		CoreV2Types.FormationState.MUSKETEER_LINE:
			return 0.72 * reform_penalty
		_:
			return 1.0 * reform_penalty


static func _resolve_formation_depth_factor(battalion: CoreV2Battalion) -> float:
	match battalion.formation_state:
		CoreV2Types.FormationState.TERCIA:
			return 1.28
		CoreV2Types.FormationState.DEFENSIVE:
			return 1.18
		CoreV2Types.FormationState.COLUMN:
			return 1.08
		CoreV2Types.FormationState.MARCH_COLUMN:
			return 0.82
		CoreV2Types.FormationState.MUSKETEER_LINE:
			return 0.86
		_:
			return 1.0


static func _resolve_formation_maneuver_factor(battalion: CoreV2Battalion) -> float:
	var reform_penalty: float = 0.7 if battalion.is_reforming else 1.0
	match battalion.formation_state:
		CoreV2Types.FormationState.MARCH_COLUMN:
			return 1.18 * reform_penalty
		CoreV2Types.FormationState.COLUMN:
			return 1.05 * reform_penalty
		CoreV2Types.FormationState.TERCIA:
			return 0.72 * reform_penalty
		CoreV2Types.FormationState.DEFENSIVE:
			return 0.55 * reform_penalty
		_:
			return 0.88 * reform_penalty
