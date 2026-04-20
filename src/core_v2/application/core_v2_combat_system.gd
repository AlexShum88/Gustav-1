class_name CoreV2CombatSystem
extends RefCounted


const INFANTRY_FIRE_RANGE_M: float = 150.0
const ARTILLERY_FIRE_RANGE_M: float = 850.0
const MELEE_RANGE_M: float = 62.0
const CAVALRY_MELEE_RANGE_M: float = 90.0
const INFANTRY_RELOAD_SECONDS: float = 14.0
const ARTILLERY_RELOAD_SECONDS: float = 22.0
const MELEE_RELOAD_SECONDS: float = 4.5
const CAVALRY_RELOAD_SECONDS: float = 7.0
const MIN_COHESION: float = 0.0
const ROUT_COHESION_THRESHOLD: float = 0.16
const ROUT_SOLDIERS_THRESHOLD: int = 80
const AMMO_PER_FIRE_ACTION: float = 0.012
const ARTILLERY_AMMO_PER_FIRE_ACTION: float = 0.02
const VICTORY_POINTS_PER_CASUALTY: float = 0.004
const ARMY_MORALE_LOSS_PER_CASUALTY: float = 0.000015
const HQ_DAMAGE_PER_SECOND: float = 0.006
const HQ_MELEE_DAMAGE_MULTIPLIER: float = 2.1
const BRIGADE_HQ_DESTROYED_COHESION_LOSS: float = 0.16
const ARMY_HQ_DESTROYED_COHESION_LOSS: float = 0.12
const SMOKE_FIRE_TARGET_SCORE_PENALTY_M: float = 520.0
const SMOKE_FIRE_ACCURACY_LOSS: float = 0.82
const SPRITE_SOLDIERS_BASELINE: float = 50.0
const ENGAGEMENT_TARGET_SCORE_BONUS_M: float = 130.0
const PREVIOUS_TARGET_SCORE_BONUS_M: float = 70.0
const MIN_TARGET_SEARCH_RADIUS_M: float = 120.0
const TARGET_SEARCH_RADIUS_PER_SPRITE_M: float = 5.5
const FIRE_CASUALTY_CONVERSION: float = 0.118
const MELEE_CASUALTY_CONVERSION_PER_SECOND: float = 0.046
const MELEE_IMPACT_SHOCK_MULTIPLIER: float = 1.85
const MELEE_BREAKTHROUGH_RATIO: float = 1.30


static func update_combat(state: CoreV2BattleState, delta: float) -> void:
	var active_battalions: Array = _prepare_battalions_for_composite_combat(state, delta)
	var engagements: Array = _build_combat_engagements(state, active_battalions)
	_resolve_combat_engagements(state, engagements, delta)
	for battalion_value in active_battalions:
		var battalion: CoreV2Battalion = battalion_value
		if battalion.last_engagement_id == &"":
			_clear_combat_summary_only(battalion)
	_update_headquarters_exposure(state, delta)


static func _prepare_battalions_for_composite_combat(state: CoreV2BattleState, delta: float) -> Array:
	var active_battalions: Array = []
	for battalion_value in state.get_all_battalions():
		var battalion: CoreV2Battalion = battalion_value
		_decay_recent_combat_stats(battalion, delta)
		battalion.reload_cycle_state = max(0.0, battalion.reload_cycle_state - delta)
		if battalion.reload_cycle_state <= 0.0:
			battalion.volley_readiness = clamp(battalion.volley_readiness + delta / max(1.0, _resolve_reload_seconds(battalion)), 0.0, 1.0)
		if _is_unable_to_fight(battalion):
			_clear_combat_summary_only(battalion)
			continue
		CoreV2BattalionCombatModel.update_condition(battalion, state)
		battalion.last_engagement_id = &""
		if battalion.combat_target_id == &"":
			_clear_combat_summary_only(battalion)
		active_battalions.append(battalion)
	return active_battalions


static func _build_combat_engagements(state: CoreV2BattleState, active_battalions: Array) -> Array:
	var engagements: Array = []
	for attacker_index in range(active_battalions.size()):
		var attacker: CoreV2Battalion = active_battalions[attacker_index]
		for defender_index in range(attacker_index + 1, active_battalions.size()):
			var defender: CoreV2Battalion = active_battalions[defender_index]
			if defender.army_id == attacker.army_id:
				continue
			var attacker_visible_keys: Dictionary = state.visible_entity_keys_by_army.get(attacker.army_id, {})
			var defender_visible_keys: Dictionary = state.visible_entity_keys_by_army.get(defender.army_id, {})
			var attacker_sees_defender: bool = attacker_visible_keys.has(CoreV2VisibilitySystem.battalion_key(defender.id))
			var defender_sees_attacker: bool = defender_visible_keys.has(CoreV2VisibilitySystem.battalion_key(attacker.id))
			if not attacker_sees_defender and not defender_sees_attacker:
				continue
			var distance_m: float = _distance_2d(attacker.position, defender.position)
			var max_contact_range_m: float = max(_get_attack_range_m(attacker), _get_attack_range_m(defender))
			max_contact_range_m += _estimate_battalion_contact_radius(attacker) + _estimate_battalion_contact_radius(defender)
			if distance_m > max_contact_range_m:
				continue
			var contact_type: String = _resolve_engagement_contact_type(attacker, defender, distance_m)
			var sector_geometry: Dictionary = _build_sector_geometry(state, attacker, defender, distance_m)
			engagements.append(CoreV2CombatEngagement.create(
				StringName("eng:%s:%s" % [String(attacker.id), String(defender.id)]),
				attacker,
				defender,
				contact_type,
				(attacker.position + defender.position) * 0.5,
				sector_geometry
			))
	return engagements


static func _resolve_engagement_contact_type(attacker: CoreV2Battalion, defender: CoreV2Battalion, distance_m: float) -> String:
	var melee_range: float = max(_get_melee_range_m(attacker), _get_melee_range_m(defender))
	if distance_m <= melee_range + _estimate_battalion_contact_radius(attacker) * 0.5 + _estimate_battalion_contact_radius(defender) * 0.5:
		return "melee_press"
	if attacker.engagement_mode == "assault" or defender.engagement_mode == "assault":
		return "assault"
	if distance_m <= max(_get_attack_range_m(attacker), _get_attack_range_m(defender)):
		return "volley_exchange"
	return "ranged_skirmish"


static func _build_sector_geometry(state: CoreV2BattleState, attacker: CoreV2Battalion, defender: CoreV2Battalion, distance_m: float) -> Dictionary:
	var attacker_side := Vector3(-attacker.facing.z, 0.0, attacker.facing.x).normalized()
	var defender_side := Vector3(-defender.facing.z, 0.0, defender.facing.x).normalized()
	var attacker_to_defender: Vector3 = defender.position - attacker.position
	attacker_to_defender.y = 0.0
	var lateral_offset_attacker: float = absf(attacker_to_defender.dot(attacker_side))
	var lateral_offset_defender: float = absf((-attacker_to_defender).dot(defender_side))
	var attacker_frontage: float = max(24.0, attacker.formation_frontage_m)
	var defender_frontage: float = max(24.0, defender.formation_frontage_m)
	var average_frontage: float = max(24.0, (attacker_frontage + defender_frontage) * 0.5)
	var frontage_coverage_ratio: float = clamp(1.0 - ((lateral_offset_attacker + lateral_offset_defender) * 0.5 / average_frontage), 0.12, 1.0)
	var gap_ratio: float = clamp((lateral_offset_attacker + lateral_offset_defender) * 0.5 / max(1.0, average_frontage), 0.0, 1.0)
	return {
		"distance_m": distance_m,
		"frontage_coverage_ratio": frontage_coverage_ratio,
		"overlap_left": max(0.0, 1.0 - lateral_offset_attacker / max(1.0, attacker_frontage)),
		"overlap_right": max(0.0, 1.0 - lateral_offset_defender / max(1.0, defender_frontage)),
		"support_depth_ratio": clamp((attacker.formation_depth_m + defender.formation_depth_m) / max(1.0, average_frontage), 0.1, 1.4),
		"adjacent_support_score": _estimate_adjacent_support_score(state, attacker, defender),
		"gap_ratio": gap_ratio,
	}


static func _estimate_adjacent_support_score(state: CoreV2BattleState, battalion: CoreV2Battalion, enemy: CoreV2Battalion) -> float:
	var support_score: float = 0.0
	for other_value in state.get_all_battalions():
		var other: CoreV2Battalion = other_value
		if other == battalion or other.army_id != battalion.army_id or _is_unable_to_fight(other):
			continue
		var distance_m: float = _distance_2d(other.position, battalion.position)
		if distance_m > max(180.0, battalion.formation_frontage_m * 1.2):
			continue
		var enemy_distance_m: float = _distance_2d(other.position, enemy.position)
		if enemy_distance_m < distance_m:
			support_score += 0.18
		else:
			support_score += 0.1
	return clamp(support_score, 0.0, 0.45)


static func _resolve_combat_engagements(state: CoreV2BattleState, engagements: Array, delta: float) -> void:
	for engagement_value in engagements:
		var engagement: CoreV2CombatEngagement = engagement_value
		if engagement.participants_attackers.is_empty() or engagement.participants_defenders.is_empty():
			continue
		var attacker: CoreV2Battalion = engagement.participants_attackers[0]
		var defender: CoreV2Battalion = engagement.participants_defenders[0]
		if _is_unable_to_fight(attacker) or _is_unable_to_fight(defender):
			continue
		attacker.last_engagement_id = engagement.id
		defender.last_engagement_id = engagement.id
		if engagement.contact_type == "volley_exchange" or engagement.contact_type == "ranged_skirmish" or engagement.contact_type == "assault":
			_resolve_ranged_exchange(state, attacker, defender, engagement, delta)
			if not _is_unable_to_fight(defender) and not _is_unable_to_fight(attacker):
				_resolve_ranged_exchange(state, defender, attacker, engagement, delta)
		if engagement.contact_type == "assault" or engagement.contact_type == "melee_press":
			_resolve_assault_or_melee(state, attacker, defender, engagement, delta)
			if not _is_unable_to_fight(defender) and not _is_unable_to_fight(attacker):
				_resolve_assault_or_melee(state, defender, attacker, engagement, delta)


static func _resolve_ranged_exchange(
		state: CoreV2BattleState,
		attacker: CoreV2Battalion,
		defender: CoreV2Battalion,
		engagement: CoreV2CombatEngagement,
		delta: float
) -> void:
	var distance_m: float = float(engagement.sector_geometry.get("distance_m", _distance_2d(attacker.position, defender.position)))
	var visible_keys: Dictionary = state.visible_entity_keys_by_army.get(attacker.army_id, {})
	if not visible_keys.has(CoreV2VisibilitySystem.battalion_key(defender.id)) and distance_m > _get_melee_range_m(attacker):
		return
	if attacker.ammunition <= 0.01:
		return
	if attacker.reload_cycle_state > 0.0:
		_set_composite_combat_summary(attacker, defender, engagement, "artillery" if attacker.category == CoreV2Types.UnitCategory.ARTILLERY else "musket", false)
		return
	var max_range_m: float = _get_attack_range_m(attacker)
	if distance_m > max_range_m + _estimate_battalion_contact_radius(defender):
		return
	var effective_distance_m: float = max(0.0, distance_m - _estimate_battalion_contact_radius(defender) * 0.35)
	var outputs: Dictionary = CoreV2BattalionCombatModel.build_outputs(state, attacker)
	var fire_output: float = float(outputs.get("fire_output", 0.0))
	if fire_output <= 0.01:
		return
	var range_factor: float = _resolve_fire_distance_curve(effective_distance_m, max_range_m)
	var terrain_cover: float = max(0.18, 1.0 - state.get_defense_modifier_at(defender.position))
	var formation_vulnerability: float = _resolve_target_formation_vulnerability(defender)
	var smoke_factor: float = max(0.12, 1.0 - state.get_smoke_density_between(attacker.position, defender.position) * SMOKE_FIRE_ACCURACY_LOSS)
	var frontage_factor: float = float(engagement.sector_geometry.get("frontage_coverage_ratio", 1.0))
	var expected_casualties: float = fire_output * range_factor * terrain_cover * formation_vulnerability * smoke_factor * frontage_factor * FIRE_CASUALTY_CONVERSION
	expected_casualties *= _seeded_rng_factor(attacker, defender, state, "fire")
	var casualties: int = _resolve_casualties_with_carry(defender, expected_casualties, false, _seeded_fraction(attacker, defender, state, "fire_round"))
	var pressure: float = clamp(expected_casualties / max(1.0, float(defender.soldiers_total)) * 9.2 + range_factor * frontage_factor * 0.026, 0.0, 0.20)
	_apply_composite_damage(state, attacker, defender, max(0, casualties), false, {
		"cohesion_loss": pressure * 0.92,
		"morale_loss": pressure * 0.46,
		"suppression_gain": pressure * 2.25,
		"disorder_gain": pressure * 1.10,
		"alignment_loss": pressure * 0.86,
	})
	attacker.ammunition = max(0.0, attacker.ammunition - (ARTILLERY_AMMO_PER_FIRE_ACTION if attacker.category == CoreV2Types.UnitCategory.ARTILLERY else AMMO_PER_FIRE_ACTION))
	attacker.ammo_state = attacker.ammunition
	attacker.reload_cycle_state = _resolve_reload_seconds(attacker)
	attacker.volley_readiness = 0.0
	state.emit_weapon_smoke(attacker, defender.position, "artillery" if attacker.category == CoreV2Types.UnitCategory.ARTILLERY else "musket")
	_set_composite_combat_summary(attacker, defender, engagement, "artillery" if attacker.category == CoreV2Types.UnitCategory.ARTILLERY else "musket", false)


static func _resolve_assault_or_melee(
		state: CoreV2BattleState,
		attacker: CoreV2Battalion,
		defender: CoreV2Battalion,
		engagement: CoreV2CombatEngagement,
		delta: float
) -> void:
	var distance_m: float = float(engagement.sector_geometry.get("distance_m", _distance_2d(attacker.position, defender.position)))
	var melee_range: float = _get_melee_range_m(attacker) + _estimate_battalion_contact_radius(attacker) * 0.5 + _estimate_battalion_contact_radius(defender) * 0.5
	var outputs: Dictionary = CoreV2BattalionCombatModel.build_outputs(state, attacker)
	var defender_outputs: Dictionary = CoreV2BattalionCombatModel.build_outputs(state, defender)
	if distance_m > melee_range:
		attacker.melee_commitment_state = CoreV2Types.MeleeCommitmentState.APPROACH
		_set_composite_combat_summary(attacker, defender, engagement, "assault", true)
		return
	if attacker.melee_commitment_state == CoreV2Types.MeleeCommitmentState.APPROACH:
		attacker.melee_commitment_state = CoreV2Types.MeleeCommitmentState.COMMITMENT_CHECK
	if attacker.melee_commitment_state == CoreV2Types.MeleeCommitmentState.COMMITMENT_CHECK:
		var commitment: float = attacker.cohesion * 0.42 + attacker.morale * 0.36 + attacker.officer_quality * 0.22
		commitment -= attacker.suppression * 0.28 + attacker.disorder * 0.22 + attacker.recoil_tendency * 0.18
		if commitment < 0.34:
			attacker.melee_commitment_state = CoreV2Types.MeleeCommitmentState.RECOIL
			CoreV2BattalionCombatModel.apply_functional_loss(attacker, 0.045, 0.035, 0.04, 0.075, 0.055)
			return
		attacker.melee_commitment_state = CoreV2Types.MeleeCommitmentState.IMPACT
	var impact_multiplier: float = MELEE_IMPACT_SHOCK_MULTIPLIER if attacker.melee_commitment_state == CoreV2Types.MeleeCommitmentState.IMPACT else 1.0
	var frontage_factor: float = float(engagement.sector_geometry.get("frontage_coverage_ratio", 1.0))
	var support_factor: float = 1.0 + float(engagement.sector_geometry.get("adjacent_support_score", 0.0))
	var contact_factor: float = 1.0 + attacker.contact_pressure * 0.18 + attacker.compression_level * 0.08
	var melee_pressure: float = float(outputs.get("melee_output", 0.0)) * frontage_factor * support_factor * contact_factor
	var defender_staying: float = max(1.0, float(defender_outputs.get("staying_power", 1.0)))
	var pressure_ratio: float = melee_pressure / defender_staying
	var expected_casualties: float = melee_pressure * clamp(pressure_ratio, 0.45, 2.35) * MELEE_CASUALTY_CONVERSION_PER_SECOND * delta * impact_multiplier
	expected_casualties *= _seeded_rng_factor(attacker, defender, state, "melee")
	var casualties: int = _resolve_casualties_with_carry(defender, expected_casualties, true, _seeded_fraction(attacker, defender, state, "melee_round"))
	var functional_scale: float = clamp((0.070 + pressure_ratio * 0.115 + attacker.contact_pressure * 0.060 + defender.compression_level * 0.045) * delta * impact_multiplier, 0.0, 0.32)
	_apply_composite_damage(state, attacker, defender, max(0, casualties), true, {
		"cohesion_loss": functional_scale * 1.75,
		"morale_loss": functional_scale * 1.32,
		"suppression_gain": functional_scale * 0.80,
		"disorder_gain": functional_scale * 2.05,
		"alignment_loss": functional_scale * 1.55,
	})
	defender.recoil_tendency = max(
		defender.recoil_tendency,
		clamp((pressure_ratio - 0.82) * 0.28 + attacker.contact_pressure * 0.18 + defender.compression_level * 0.16, 0.0, 1.0)
	)
	if pressure_ratio >= MELEE_BREAKTHROUGH_RATIO:
		attacker.melee_commitment_state = CoreV2Types.MeleeCommitmentState.BREAKTHROUGH
		defender.melee_commitment_state = CoreV2Types.MeleeCommitmentState.RECOIL
		defender.recoil_tendency = max(defender.recoil_tendency, clamp((pressure_ratio - 1.0) * 0.65, 0.0, 1.0))
	else:
		attacker.melee_commitment_state = CoreV2Types.MeleeCommitmentState.PRESS
	_set_composite_combat_summary(attacker, defender, engagement, "melee", true)


static func _apply_composite_damage(
		state: CoreV2BattleState,
		attacker: CoreV2Battalion,
		defender: CoreV2Battalion,
		casualties: int,
		pressure_is_melee: bool,
		functional_damage: Dictionary
) -> void:
	if casualties > 0:
		CoreV2BattalionCombatModel.apply_material_loss(defender, casualties, pressure_is_melee)
		defender.recent_casualties_taken += casualties
		attacker.recent_casualties_inflicted += casualties
		_update_army_combat_scores(state, attacker, defender, casualties)
	CoreV2BattalionCombatModel.apply_functional_loss(
		defender,
		float(functional_damage.get("cohesion_loss", 0.0)),
		float(functional_damage.get("morale_loss", 0.0)),
		float(functional_damage.get("suppression_gain", 0.0)),
		float(functional_damage.get("disorder_gain", 0.0)),
		float(functional_damage.get("alignment_loss", 0.0))
	)
	if casualties > 0:
		var attack_label: String = "melee" if pressure_is_melee else "fire"
		attacker.recent_combat_event = "%s %s: +%d" % [defender.display_name, attack_label, casualties]
		defender.recent_combat_event = "%s %s: -%d" % [attacker.display_name, attack_label, casualties]
	_check_rout(state, defender)


static func _set_composite_combat_summary(attacker: CoreV2Battalion, defender: CoreV2Battalion, engagement: CoreV2CombatEngagement, attack_kind: String, is_melee: bool) -> void:
	attacker.combat_target_id = defender.id
	attacker.combat_target_name = defender.display_name
	attacker.combat_range_m = float(engagement.sector_geometry.get("distance_m", _distance_2d(attacker.position, defender.position)))
	attacker.combat_cooldown_seconds = attacker.reload_cycle_state
	attacker.combat_reload_seconds = _resolve_reload_seconds(attacker)
	attacker.combat_attack_kind = attack_kind
	attacker.combat_melee_pressure = clamp(attacker.contact_pressure + (0.55 if is_melee else 0.0), 0.0, 1.0)
	if attacker.status != CoreV2Types.UnitStatus.ROUTING:
		attacker.status = CoreV2Types.UnitStatus.ENGAGING


static func _resolve_fire_distance_curve(distance_m: float, max_range_m: float) -> float:
	if max_range_m <= 0.001:
		return 0.0
	if max_range_m <= CAVALRY_MELEE_RANGE_M:
		return 0.0
	var normalized_distance: float = clamp(distance_m / max_range_m, 0.0, 1.0)
	return max(0.0, pow(1.0 - normalized_distance, 1.05)) * 0.86


static func _resolve_target_formation_vulnerability(target: CoreV2Battalion) -> float:
	var factor: float = 1.0 + target.disorder * 0.22 + target.compression_level * 0.18 - target.front_continuity * 0.08
	match target.formation_state:
		CoreV2Types.FormationState.COLUMN, CoreV2Types.FormationState.MARCH_COLUMN:
			factor *= 1.32
		CoreV2Types.FormationState.TERCIA:
			factor *= 1.18
		CoreV2Types.FormationState.DEFENSIVE:
			factor *= 0.76
		CoreV2Types.FormationState.MUSKETEER_LINE:
			factor *= 1.05
	return clamp(factor, 0.52, 1.65)


static func _resolve_casualties_with_carry(target: CoreV2Battalion, expected_casualties: float, is_melee: bool, rounding_roll: float) -> int:
	if expected_casualties <= 0.0:
		return 0
	if is_melee:
		target.melee_casualty_carry += expected_casualties
		var melee_casualties: int = int(floor(target.melee_casualty_carry + rounding_roll))
		melee_casualties = min(melee_casualties, target.soldiers_total)
		target.melee_casualty_carry = max(0.0, target.melee_casualty_carry - float(melee_casualties))
		return melee_casualties
	target.fire_casualty_carry += expected_casualties
	var fire_casualties: int = int(floor(target.fire_casualty_carry + rounding_roll))
	fire_casualties = min(fire_casualties, target.soldiers_total)
	target.fire_casualty_carry = max(0.0, target.fire_casualty_carry - float(fire_casualties))
	return fire_casualties


static func _resolve_reload_seconds(battalion: CoreV2Battalion) -> float:
	if battalion.category == CoreV2Types.UnitCategory.ARTILLERY:
		return ARTILLERY_RELOAD_SECONDS / max(0.35, battalion.drill_quality)
	var doctrine_multiplier: float = 1.0
	match battalion.fire_doctrine:
		CoreV2Types.FireDoctrine.SALVO:
			doctrine_multiplier = 1.18
		CoreV2Types.FireDoctrine.COUNTERMARCH:
			doctrine_multiplier = 0.92 if battalion.drill_quality > 0.68 else 1.18
		CoreV2Types.FireDoctrine.ROLLING_FIRE:
			doctrine_multiplier = 1.0
		CoreV2Types.FireDoctrine.IRREGULAR_FIRE:
			doctrine_multiplier = 1.35
	return INFANTRY_RELOAD_SECONDS * doctrine_multiplier / max(0.35, battalion.drill_quality)


static func _seeded_rng_factor(attacker: CoreV2Battalion, defender: CoreV2Battalion, state: CoreV2BattleState, salt: String) -> float:
	return lerp(0.85, 1.15, _seeded_fraction(attacker, defender, state, salt))


static func _seeded_fraction(attacker: CoreV2Battalion, defender: CoreV2Battalion, state: CoreV2BattleState, salt: String) -> float:
	var seed_text: String = "%s:%s:%d:%s" % [String(attacker.id), String(defender.id), int(floor(state.time_seconds * 10.0)), salt]
	var value: int = abs(seed_text.hash())
	return float(value % 10000) / 10000.0


static func _estimate_battalion_contact_radius(battalion: CoreV2Battalion) -> float:
	return max(24.0, max(battalion.formation_frontage_m, battalion.formation_depth_m) * 0.35)


static func _prepare_battalions_for_sprite_combat(state: CoreV2BattleState, delta: float) -> Array:
	var active_battalions: Array = []
	for battalion_value in state.get_all_battalions():
		var battalion: CoreV2Battalion = battalion_value
		_decay_recent_combat_stats(battalion, delta)
		if _is_unable_to_fight(battalion):
			_clear_combat_state(battalion, delta)
			continue
		battalion.ensure_formation_ready()
		battalion.sync_sprite_blocks(state)
		for block_value in battalion.sprite_blocks:
			var block: CoreV2SpriteBlock = block_value
			block.advance_cooldown(delta)
		active_battalions.append(battalion)
	return active_battalions


static func _update_sprite_block_attacks(state: CoreV2BattleState, attacker: CoreV2Battalion, combat_result: Dictionary) -> void:
	if not _has_ready_sprite_block(attacker):
		return
	var target_candidates: Array = _build_target_candidates(state, attacker)
	if target_candidates.is_empty():
		for block_value in attacker.sprite_blocks:
			var idle_block: CoreV2SpriteBlock = block_value
			idle_block.clear_target()
		return
	for block_value in attacker.sprite_blocks:
		var block: CoreV2SpriteBlock = block_value
		if not block.can_attack():
			continue
		var target_data: Dictionary = _select_target_for_sprite_block(state, attacker, block, target_candidates)
		if target_data.is_empty():
			block.clear_target()
			continue

		var target: CoreV2Battalion = target_data.get("target_battalion", null) as CoreV2Battalion
		var target_block: CoreV2SpriteBlock = target_data.get("target_block", null) as CoreV2SpriteBlock
		var attack_profile: Dictionary = target_data.get("attack_profile", {})
		if target == null or target_block == null or attack_profile.is_empty():
			block.clear_target()
			continue

		var attack_kind: String = String(attack_profile.get("attack_kind", ""))
		var reload_seconds: float = float(attack_profile.get("reload_seconds", MELEE_RELOAD_SECONDS))
		var smoke_density: float = float(target_data.get("smoke_density", 0.0))
		block.set_target(target.id, target_block.index, target_block.world_position, attack_kind, reload_seconds, smoke_density)

		if bool(attack_profile.get("uses_ammo", false)):
			attacker.ammunition = max(0.0, attacker.ammunition - float(attack_profile.get("ammo_cost", 0.0)))
			combat_result["smoke_events"][attacker.id] = {
				"attacker": attacker,
				"target_position": target_block.world_position,
				"attack_kind": attack_kind,
			}

		var expected_casualties: float = _resolve_sprite_expected_casualties(
			state,
			attacker,
			block,
			target,
			target_block,
			float(target_data.get("distance_m", 0.0)),
			attack_profile,
			smoke_density
		)
		if expected_casualties <= 0.0:
			continue
		combat_result["damage_events"].append({
			"attacker": attacker,
			"attacker_sprite_index": block.index,
			"target": target,
			"target_sprite_index": target_block.index,
			"expected_casualties": expected_casualties,
			"attack_profile": attack_profile,
		})


static func _build_target_candidates(state: CoreV2BattleState, attacker: CoreV2Battalion) -> Array:
	var visible_keys: Dictionary = state.visible_entity_keys_by_army.get(attacker.army_id, {})
	var target_candidates: Array = []
	var max_attack_range_m: float = _get_attack_range_m(attacker)
	var attacker_search_radius_m: float = _estimate_target_search_radius_m(attacker)
	for target_value in state.get_all_battalions():
		var target: CoreV2Battalion = target_value
		if target.army_id == attacker.army_id or _is_unable_to_fight(target):
			continue
		if not visible_keys.has(CoreV2VisibilitySystem.battalion_key(target.id)):
			continue
		if _distance_2d(attacker.position, target.position) > max_attack_range_m + attacker_search_radius_m + _estimate_target_search_radius_m(target):
			continue
		target.ensure_formation_ready()
		target.sync_sprite_blocks(state)
		target_candidates.append(target)
	return target_candidates


static func _has_ready_sprite_block(attacker: CoreV2Battalion) -> bool:
	for block_value in attacker.sprite_blocks:
		var block: CoreV2SpriteBlock = block_value
		if block.can_attack():
			return true
	return false


static func _select_target_for_sprite_block(state: CoreV2BattleState, attacker: CoreV2Battalion, block: CoreV2SpriteBlock, target_candidates: Array) -> Dictionary:
	var best_target_data: Dictionary = {}
	var best_score: float = INF
	var max_attack_range_m: float = _get_attack_range_m(attacker)
	for target_value in target_candidates:
		var target: CoreV2Battalion = target_value
		if _distance_2d(block.world_position, target.position) > max_attack_range_m + _estimate_target_search_radius_m(target):
			continue
		for target_block_value in target.sprite_blocks:
			var target_block: CoreV2SpriteBlock = target_block_value
			if target_block.soldiers <= 0:
				continue
			var distance_m: float = _distance_2d(block.world_position, target_block.world_position)
			var attack_profile: Dictionary = _build_sprite_attack_profile(attacker, block, distance_m)
			if attack_profile.is_empty():
				continue
			if not _is_target_in_fire_arc(attacker, block, target_block.world_position, attack_profile):
				continue
			var smoke_density: float = state.get_smoke_density_between(block.world_position, target_block.world_position)
			var target_score: float = _score_sprite_target(attacker, block, target, target_block, distance_m, smoke_density, attack_profile)
			if target_score >= best_score:
				continue
			best_score = target_score
			best_target_data = {
				"target_battalion": target,
				"target_block": target_block,
				"distance_m": distance_m,
				"attack_profile": attack_profile,
				"smoke_density": smoke_density,
			}
	return best_target_data


static func _score_sprite_target(
		attacker: CoreV2Battalion,
		block: CoreV2SpriteBlock,
		target: CoreV2Battalion,
		target_block: CoreV2SpriteBlock,
		distance_m: float,
		smoke_density: float,
		attack_profile: Dictionary
) -> float:
	var score: float = distance_m
	var attack_kind: String = String(attack_profile.get("attack_kind", ""))
	if attack_kind == "melee":
		score -= smoke_density * 120.0
	else:
		score += smoke_density * SMOKE_FIRE_TARGET_SCORE_PENALTY_M
	if target.id == attacker.engagement_target_id:
		score -= ENGAGEMENT_TARGET_SCORE_BONUS_M
	if target.id == block.target_battalion_id and target_block.index == block.target_sprite_index:
		score -= PREVIOUS_TARGET_SCORE_BONUS_M
	if target_block.soldiers < CoreV2SpriteBlock.DEFAULT_SOLDIERS_PER_BLOCK:
		score -= 12.0
	return score


static func _build_sprite_attack_profile(attacker: CoreV2Battalion, block: CoreV2SpriteBlock, distance_m: float) -> Dictionary:
	var role: String = block.role
	if attacker.category == CoreV2Types.UnitCategory.ARTILLERY:
		if distance_m > ARTILLERY_FIRE_RANGE_M or attacker.ammunition <= 0.01:
			return {}
		return {
			"attack_kind": "artillery",
			"range_m": ARTILLERY_FIRE_RANGE_M,
			"reload_seconds": ARTILLERY_RELOAD_SECONDS / max(0.4, attacker.training),
			"uses_ammo": true,
			"ammo_cost": ARTILLERY_AMMO_PER_FIRE_ACTION / max(1.0, float(attacker.sprite_count)),
			"arc_cos": 0.28,
			"cohesion_damage_multiplier": 1.22,
		}
	if attacker.category == CoreV2Types.UnitCategory.CAVALRY:
		if distance_m > CAVALRY_MELEE_RANGE_M:
			return {}
		return {
			"attack_kind": "melee",
			"range_m": CAVALRY_MELEE_RANGE_M,
			"reload_seconds": CAVALRY_RELOAD_SECONDS / max(0.45, attacker.training),
			"base_casualties": 1.15,
			"uses_ammo": false,
			"ammo_cost": 0.0,
			"arc_cos": -0.05,
			"cohesion_damage_multiplier": 1.35,
		}
	if distance_m <= MELEE_RANGE_M and _can_role_melee(role):
		return {
			"attack_kind": "melee",
			"range_m": MELEE_RANGE_M,
			"reload_seconds": MELEE_RELOAD_SECONDS / max(0.45, attacker.training),
			"base_casualties": _get_role_melee_base_casualties(role),
			"uses_ammo": false,
			"ammo_cost": 0.0,
			"arc_cos": -0.25,
			"cohesion_damage_multiplier": 1.35,
		}
	if distance_m <= INFANTRY_FIRE_RANGE_M and attacker.ammunition > 0.01 and _can_role_fire(role):
		return {
			"attack_kind": "musket",
			"range_m": INFANTRY_FIRE_RANGE_M,
			"reload_seconds": INFANTRY_RELOAD_SECONDS / max(0.45, attacker.training),
			"uses_ammo": true,
			"ammo_cost": AMMO_PER_FIRE_ACTION / max(1.0, float(attacker.sprite_count)),
			"arc_cos": 0.1,
			"cohesion_damage_multiplier": 1.08,
		}
	return {}


static func _resolve_sprite_expected_casualties(
		state: CoreV2BattleState,
		attacker: CoreV2Battalion,
		block: CoreV2SpriteBlock,
		target: CoreV2Battalion,
		target_block: CoreV2SpriteBlock,
		distance_m: float,
		attack_profile: Dictionary,
		smoke_density: float
) -> float:
	var attack_kind: String = String(attack_profile.get("attack_kind", ""))
	if attack_kind == "musket" or attack_kind == "artillery":
		return CoreV2CombatMath.resolve_fire_casualties(
			state,
			attacker,
			block,
			target,
			target_block,
			distance_m,
			attack_profile,
			smoke_density
		)
	return _resolve_melee_expected_casualties(state, attacker, block, target, target_block, distance_m, attack_profile, smoke_density)


static func _resolve_melee_expected_casualties(
		state: CoreV2BattleState,
		attacker: CoreV2Battalion,
		block: CoreV2SpriteBlock,
		target: CoreV2Battalion,
		target_block: CoreV2SpriteBlock,
		distance_m: float,
		attack_profile: Dictionary,
		smoke_density: float
) -> float:
	var range_factor: float = _resolve_range_factor(distance_m, float(attack_profile.get("range_m", 1.0)))
	var attacker_factor: float = max(0.15, attacker.training) * max(0.12, attacker.cohesion)
	var line_of_fire_factor: float = _resolve_line_of_fire_factor(smoke_density, attack_profile)
	var target_factor: float = _resolve_target_vulnerability(state, target, target_block)
	var block_strength: float = clamp(float(block.soldiers) / SPRITE_SOLDIERS_BASELINE, 0.08, 1.2)
	var expected_casualties: float = float(attack_profile.get("base_casualties", 0.0))
	expected_casualties *= block_strength * range_factor * attacker_factor * line_of_fire_factor * target_factor
	return clamp(expected_casualties, 0.0, float(max(0, target_block.soldiers)))


static func _apply_sprite_combat_results(state: CoreV2BattleState, combat_result: Dictionary) -> void:
	var damaged_targets: Dictionary = {}
	for event_value in combat_result.get("damage_events", []):
		var event: Dictionary = event_value
		var attacker: CoreV2Battalion = event.get("attacker", null) as CoreV2Battalion
		var target: CoreV2Battalion = event.get("target", null) as CoreV2Battalion
		if attacker == null or target == null or _is_unable_to_fight(target):
			continue
		var target_block: CoreV2SpriteBlock = target.get_sprite_block(int(event.get("target_sprite_index", -1)))
		if target_block == null or target_block.soldiers <= 0:
			continue
		var attack_profile: Dictionary = event.get("attack_profile", {})
		target_block.damage_carry += float(event.get("expected_casualties", 0.0))
		var casualties: int = _resolve_applied_casualties_from_carry(
			attacker,
			int(event.get("attacker_sprite_index", -1)),
			target,
			target_block,
			attack_profile
		)
		if casualties <= 0:
			continue
		casualties = min(casualties, target_block.soldiers)
		target_block.damage_carry = max(0.0, target_block.damage_carry - float(casualties))
		target_block.soldiers = max(0, target_block.soldiers - casualties)
		target.soldiers_total = max(0, target.soldiers_total - casualties)
		target.cohesion = max(MIN_COHESION, target.cohesion - _resolve_cohesion_loss(target, casualties, attack_profile))
		target.recent_casualties_taken += casualties
		attacker.recent_casualties_inflicted += casualties
		var attack_kind: String = String(attack_profile.get("attack_kind", ""))
		var attack_label: String = "рукопашна" if attack_kind == "melee" else attack_kind
		attacker.recent_combat_event = "%s[%d] %s: %d втрат" % [target.display_name, target_block.index, attack_label, casualties]
		target.recent_combat_event = "%s %s: -%d" % [attacker.display_name, attack_label, casualties]
		_update_army_combat_scores(state, attacker, target, casualties)
		damaged_targets[target.id] = target

	for target_value in damaged_targets.values():
		var damaged_target: CoreV2Battalion = target_value
		_compact_dead_sprite_blocks(damaged_target)
		_check_rout(state, damaged_target)

	for smoke_value in combat_result.get("smoke_events", {}).values():
		var smoke_event: Dictionary = smoke_value
		var smoke_attacker: CoreV2Battalion = smoke_event.get("attacker", null) as CoreV2Battalion
		if smoke_attacker == null:
			continue
		state.emit_weapon_smoke(
			smoke_attacker,
			smoke_event.get("target_position", smoke_attacker.position),
			String(smoke_event.get("attack_kind", ""))
		)


static func _compact_dead_sprite_blocks(target: CoreV2Battalion) -> void:
	var alive_blocks: Array = []
	var alive_offsets: Array = []
	var alive_velocities: Array = []
	var alive_roles: Array = []
	var total_soldiers: int = 0
	for block_value in target.sprite_blocks:
		var block: CoreV2SpriteBlock = block_value
		if block.soldiers <= 0:
			continue
		alive_blocks.append(block)
		var old_index: int = block.index
		if old_index >= 0 and old_index < target.sprite_offsets.size():
			alive_offsets.append(target.sprite_offsets[old_index])
		else:
			alive_offsets.append(block.local_offset)
		if old_index >= 0 and old_index < target.sprite_offset_velocities.size():
			alive_velocities.append(target.sprite_offset_velocities[old_index])
		else:
			alive_velocities.append(Vector3.ZERO)
		if old_index >= 0 and old_index < target.sprite_roles.size():
			alive_roles.append(target.sprite_roles[old_index])
		else:
			alive_roles.append(block.role)
		total_soldiers += block.soldiers
	if alive_blocks.size() == target.sprite_blocks.size():
		target.soldiers_total = total_soldiers
		return
	target.sprite_blocks = alive_blocks
	target.sprite_count = alive_blocks.size()
	target.soldiers_total = total_soldiers
	if target.sprite_count <= 0:
		target.sprite_offsets.clear()
		target.sprite_offset_velocities.clear()
		target.sprite_target_offsets.clear()
		target.sprite_reform_from_offsets.clear()
		target.sprite_roles.clear()
		return
	target.sprite_offsets = alive_offsets
	target.sprite_offset_velocities = alive_velocities
	target.sprite_roles = alive_roles
	target.sprite_reform_from_offsets = alive_offsets.duplicate(true)
	target.sprite_target_offsets = alive_offsets.duplicate(true)
	CoreV2FormationSystem.request_formation(target, target.desired_formation_state)
	target.sync_sprite_blocks()


static func _resolve_applied_casualties_from_carry(
		attacker: CoreV2Battalion,
		attacker_sprite_index: int,
		target: CoreV2Battalion,
		target_block: CoreV2SpriteBlock,
		attack_profile: Dictionary
) -> int:
	var attack_kind: String = String(attack_profile.get("attack_kind", ""))
	if attack_kind != "musket" and attack_kind != "artillery":
		return int(floor(target_block.damage_carry))
	var attacker_block: CoreV2SpriteBlock = attacker.get_sprite_block(attacker_sprite_index)
	if attacker_block == null:
		return int(floor(target_block.damage_carry))
	var rounding_roll: float = CoreV2CombatMath.resolve_casualty_rounding_roll(
		attacker,
		attacker_block,
		target,
		target_block,
		attack_kind
	)
	return int(floor(target_block.damage_carry + rounding_roll))


static func _refresh_battalion_combat_summary(state: CoreV2BattleState, battalion: CoreV2Battalion) -> void:
	var target_counts: Dictionary = {}
	var nearest_range_m: float = INF
	var min_cooldown: float = INF
	var max_reload: float = 0.0
	var attack_kind_counts: Dictionary = {}
	var melee_blocks: int = 0
	for block_value in battalion.sprite_blocks:
		var block: CoreV2SpriteBlock = block_value
		if block.target_battalion_id == &"":
			continue
		target_counts[block.target_battalion_id] = int(target_counts.get(block.target_battalion_id, 0)) + 1
		if not block.last_attack_kind.is_empty():
			attack_kind_counts[block.last_attack_kind] = int(attack_kind_counts.get(block.last_attack_kind, 0)) + 1
			if block.last_attack_kind == "melee":
				melee_blocks += 1
		nearest_range_m = min(nearest_range_m, _distance_2d(block.world_position, block.target_world_position))
		min_cooldown = min(min_cooldown, block.combat_cooldown_seconds)
		max_reload = max(max_reload, block.combat_reload_seconds)
	if target_counts.is_empty():
		_clear_combat_summary_only(battalion)
		return
	var best_target_id: StringName = &""
	var best_count: int = -1
	for target_id_value in target_counts.keys():
		var target_id: StringName = target_id_value
		var count: int = int(target_counts[target_id])
		if count <= best_count:
			continue
		best_target_id = target_id
		best_count = count
	var target: CoreV2Battalion = state.get_battalion(best_target_id)
	battalion.combat_target_id = best_target_id
	battalion.combat_target_name = target.display_name if target != null else String(best_target_id)
	battalion.combat_range_m = nearest_range_m if nearest_range_m < INF else 0.0
	battalion.combat_cooldown_seconds = min_cooldown if min_cooldown < INF else 0.0
	battalion.combat_reload_seconds = max_reload
	battalion.combat_attack_kind = _pick_primary_attack_kind(attack_kind_counts)
	battalion.combat_melee_blocks = melee_blocks
	if battalion.status != CoreV2Types.UnitStatus.ROUTING:
		battalion.status = CoreV2Types.UnitStatus.ENGAGING


static func _pick_primary_attack_kind(attack_kind_counts: Dictionary) -> String:
	var best_kind: String = ""
	var best_count: int = -1
	for kind_value in attack_kind_counts.keys():
		var kind: String = String(kind_value)
		var count: int = int(attack_kind_counts[kind])
		if count <= best_count:
			continue
		best_kind = kind
		best_count = count
	return best_kind


static func _clear_combat_summary_only(battalion: CoreV2Battalion) -> void:
	battalion.combat_target_id = &""
	battalion.combat_target_name = ""
	battalion.combat_range_m = 0.0
	battalion.combat_cooldown_seconds = 0.0
	battalion.combat_reload_seconds = 0.0
	battalion.combat_attack_kind = ""
	battalion.combat_melee_pressure = 0.0
	if battalion.status == CoreV2Types.UnitStatus.ENGAGING:
		battalion.status = CoreV2Types.UnitStatus.MOVING if not battalion.movement_path.is_empty() else CoreV2Types.UnitStatus.IDLE


static func _can_role_fire(role: String) -> bool:
	return role == "musketeer" or role == "mixed"


static func _can_role_melee(role: String) -> bool:
	return role in ["pikeman", "mixed", "musketeer", "cavalry"]


static func _get_role_melee_base_casualties(role: String) -> float:
	match role:
		"pikeman":
			return 0.85
		"mixed":
			return 0.62
		"cavalry":
			return 1.15
		"musketeer":
			return 0.28
		_:
			return 0.38


static func _is_target_in_fire_arc(attacker: CoreV2Battalion, block: CoreV2SpriteBlock, target_position: Vector3, attack_profile: Dictionary) -> bool:
	if attacker.formation_state == CoreV2Types.FormationState.DEFENSIVE and String(attack_profile.get("attack_kind", "")) != "artillery":
		return true
	var direction_to_target := Vector2(target_position.x - block.world_position.x, target_position.z - block.world_position.z)
	if direction_to_target.length_squared() <= 0.001:
		return true
	direction_to_target = direction_to_target.normalized()
	var facing := Vector2(attacker.facing.x, attacker.facing.z)
	if facing.length_squared() <= 0.001:
		return true
	facing = facing.normalized()
	return facing.dot(direction_to_target) >= float(attack_profile.get("arc_cos", -0.25))


static func _resolve_range_factor(distance_m: float, max_range_m: float) -> float:
	if max_range_m <= MELEE_RANGE_M:
		return 1.0
	var normalized_distance: float = clamp(distance_m / max_range_m, 0.0, 1.0)
	return lerp(1.25, 0.22, normalized_distance)


static func _resolve_target_vulnerability(state: CoreV2BattleState, target: CoreV2Battalion, target_block: CoreV2SpriteBlock) -> float:
	var factor: float = 1.0 - state.get_defense_modifier_at(target_block.world_position)
	factor *= lerp(1.22, 0.82, clamp(target.cohesion, 0.0, 1.0))
	match target.formation_state:
		CoreV2Types.FormationState.MARCH_COLUMN:
			factor *= 1.22
		CoreV2Types.FormationState.COLUMN:
			factor *= 1.12
		CoreV2Types.FormationState.DEFENSIVE:
			factor *= 0.76
		CoreV2Types.FormationState.TERCIA:
			factor *= 0.88
	if target_block.soldiers < CoreV2SpriteBlock.DEFAULT_SOLDIERS_PER_BLOCK:
		factor *= 1.08
	return max(0.18, factor)


static func _resolve_line_of_fire_factor(smoke_density: float, attack_profile: Dictionary) -> float:
	if String(attack_profile.get("attack_kind", "")) == "melee":
		return 1.0
	return max(0.16, 1.0 - smoke_density * SMOKE_FIRE_ACCURACY_LOSS)


static func _resolve_cohesion_loss(target: CoreV2Battalion, casualties: int, attack_profile: Dictionary) -> float:
	var loss: float = float(casualties) / max(1.0, float(target.soldiers_total + casualties)) * 1.4
	loss *= float(attack_profile.get("cohesion_damage_multiplier", 1.0))
	return loss


static func _update_army_combat_scores(
		state: CoreV2BattleState,
		attacker: CoreV2Battalion,
		target: CoreV2Battalion,
		casualties: int
) -> void:
	var attacker_army: CoreV2Army = state.get_army(attacker.army_id)
	var target_army: CoreV2Army = state.get_army(target.army_id)
	if attacker_army != null:
		attacker_army.victory_points += float(casualties) * VICTORY_POINTS_PER_CASUALTY
	if target_army != null:
		target_army.army_morale = max(0.0, target_army.army_morale - float(casualties) * ARMY_MORALE_LOSS_PER_CASUALTY)


static func _check_rout(state: CoreV2BattleState, target: CoreV2Battalion) -> void:
	if target.status == CoreV2Types.UnitStatus.ROUTING:
		return
	var has_collapsed: bool = target.morale < 0.14 and target.disorder > 0.70 and target.recoil_tendency > 0.45
	if target.cohesion > ROUT_COHESION_THRESHOLD and target.soldiers_total > ROUT_SOLDIERS_THRESHOLD and not has_collapsed:
		return
	target.status = CoreV2Types.UnitStatus.ROUTING
	target.movement_path.clear()
	target.target_position = target.position
	target.recent_combat_event = "Розбитий"
	var target_army: CoreV2Army = state.get_army(target.army_id)
	if target_army != null:
		target_army.army_morale = max(0.0, target_army.army_morale - 0.04)
	state.recent_events.push_front("%s втратив згуртованість і тікає." % target.display_name)
	while state.recent_events.size() > state.max_recent_events:
		state.recent_events.pop_back()


static func _update_headquarters_exposure(state: CoreV2BattleState, delta: float) -> void:
	_decay_headquarters_damage_markers(state, delta)
	for attacker_value in state.get_all_battalions():
		var attacker: CoreV2Battalion = attacker_value
		if _is_unable_to_fight(attacker):
			continue
		_damage_visible_enemy_headquarters(state, attacker, delta)


static func _damage_visible_enemy_headquarters(state: CoreV2BattleState, attacker: CoreV2Battalion, delta: float) -> void:
	var visible_keys: Dictionary = state.visible_entity_keys_by_army.get(attacker.army_id, {})
	for target_army_value in state.armies.values():
		var target_army: CoreV2Army = target_army_value
		if target_army == null or target_army.id == attacker.army_id:
			continue
		if not target_army.commander_destroyed:
			var army_hq_key: String = CoreV2VisibilitySystem.army_hq_key(target_army.id)
			if visible_keys.has(army_hq_key):
				_apply_army_hq_damage(state, attacker, target_army, delta)
		for brigade_value in target_army.brigades:
			var brigade: CoreV2Brigade = brigade_value
			if brigade == null or brigade.hq_destroyed:
				continue
			var brigade_hq_key: String = CoreV2VisibilitySystem.brigade_hq_key(brigade.id)
			if visible_keys.has(brigade_hq_key):
				_apply_brigade_hq_damage(state, attacker, target_army, brigade, delta)


static func _apply_army_hq_damage(state: CoreV2BattleState, attacker: CoreV2Battalion, target_army: CoreV2Army, delta: float) -> void:
	var damage: float = _resolve_hq_damage(state, attacker, target_army.commander_position, delta)
	if damage <= 0.0:
		return
	target_army.commander_health = max(0.0, target_army.commander_health - damage)
	target_army.commander_recent_damage += damage
	if target_army.commander_health > 0.0 or target_army.commander_destroyed:
		return
	target_army.commander_destroyed = true
	target_army.army_morale = max(0.0, target_army.army_morale - 0.18)
	for battalion_value in target_army.get_all_battalions():
		var battalion: CoreV2Battalion = battalion_value
		battalion.cohesion = max(MIN_COHESION, battalion.cohesion - ARMY_HQ_DESTROYED_COHESION_LOSS)
	_push_event(state, "%s втрачає штаб полководця. Організація армії падає." % target_army.display_name)


static func _apply_brigade_hq_damage(
		state: CoreV2BattleState,
		attacker: CoreV2Battalion,
		target_army: CoreV2Army,
		brigade: CoreV2Brigade,
		delta: float
) -> void:
	var damage: float = _resolve_hq_damage(state, attacker, brigade.hq_position, delta)
	if damage <= 0.0:
		return
	brigade.hq_health = max(0.0, brigade.hq_health - damage)
	brigade.hq_recent_damage += damage
	if brigade.hq_health > 0.0 or brigade.hq_destroyed:
		return
	brigade.hq_destroyed = true
	brigade.morale = max(0.0, brigade.morale - 0.28)
	target_army.army_morale = max(0.0, target_army.army_morale - 0.05)
	for battalion_value in brigade.battalions:
		var battalion: CoreV2Battalion = battalion_value
		battalion.cohesion = max(MIN_COHESION, battalion.cohesion - BRIGADE_HQ_DESTROYED_COHESION_LOSS)
	_push_event(state, "%s втратила штаб бригади. Батальйони дезорганізовані." % brigade.display_name)


static func _resolve_hq_damage(state: CoreV2BattleState, attacker: CoreV2Battalion, hq_position: Vector3, delta: float) -> float:
	var distance_m: float = _distance_2d(attacker.position, hq_position)
	var outputs: Dictionary = CoreV2BattalionCombatModel.build_outputs(state, attacker)
	var damage_weight: float = 0.0
	if distance_m <= _get_melee_range_m(attacker) + 45.0:
		damage_weight += float(outputs.get("melee_output", 0.0)) * HQ_MELEE_DAMAGE_MULTIPLIER * 0.002
	elif distance_m <= _get_attack_range_m(attacker):
		var smoke_factor: float = max(0.12, 1.0 - state.get_smoke_density_between(attacker.position, hq_position) * SMOKE_FIRE_ACCURACY_LOSS)
		damage_weight += float(outputs.get("fire_output", 0.0)) * _resolve_fire_distance_curve(distance_m, _get_attack_range_m(attacker)) * smoke_factor * 0.003
	return delta * HQ_DAMAGE_PER_SECOND * damage_weight


static func _push_event(state: CoreV2BattleState, event_text: String) -> void:
	state.recent_events.push_front(event_text)
	while state.recent_events.size() > state.max_recent_events:
		state.recent_events.pop_back()


static func _decay_headquarters_damage_markers(state: CoreV2BattleState, delta: float) -> void:
	var decay_weight: float = clamp(delta * 0.45, 0.0, 1.0)
	for army_value in state.armies.values():
		var army: CoreV2Army = army_value
		army.commander_recent_damage = lerp(army.commander_recent_damage, 0.0, decay_weight)
		for brigade_value in army.brigades:
			var brigade: CoreV2Brigade = brigade_value
			brigade.hq_recent_damage = lerp(brigade.hq_recent_damage, 0.0, decay_weight)


static func _decay_recent_combat_stats(battalion: CoreV2Battalion, delta: float) -> void:
	var decay_weight: float = clamp(delta * 0.65, 0.0, 1.0)
	battalion.recent_casualties_inflicted = int(round(lerp(float(battalion.recent_casualties_inflicted), 0.0, decay_weight)))
	battalion.recent_casualties_taken = int(round(lerp(float(battalion.recent_casualties_taken), 0.0, decay_weight)))
	if battalion.recent_casualties_inflicted <= 0 and battalion.recent_casualties_taken <= 0:
		battalion.recent_combat_event = ""


static func _clear_combat_state(battalion: CoreV2Battalion, delta: float) -> void:
	for block_value in battalion.sprite_blocks:
		var block: CoreV2SpriteBlock = block_value
		block.advance_cooldown(delta)
		block.clear_target()
	_clear_combat_summary_only(battalion)


static func _is_unable_to_fight(battalion: CoreV2Battalion) -> bool:
	return battalion == null or battalion.status == CoreV2Types.UnitStatus.ROUTING or battalion.soldiers_total <= 0


static func _get_attack_range_m(battalion: CoreV2Battalion) -> float:
	match battalion.category:
		CoreV2Types.UnitCategory.ARTILLERY:
			return ARTILLERY_FIRE_RANGE_M
		CoreV2Types.UnitCategory.CAVALRY:
			return CAVALRY_MELEE_RANGE_M
		_:
			return INFANTRY_FIRE_RANGE_M if battalion.ammunition > 0.01 else MELEE_RANGE_M


static func _estimate_target_search_radius_m(battalion: CoreV2Battalion) -> float:
	return max(MIN_TARGET_SEARCH_RADIUS_M, float(max(1, battalion.sprite_count)) * TARGET_SEARCH_RADIUS_PER_SPRITE_M)


static func _get_melee_range_m(battalion: CoreV2Battalion) -> float:
	return CAVALRY_MELEE_RANGE_M if battalion.category == CoreV2Types.UnitCategory.CAVALRY else MELEE_RANGE_M


static func _distance_2d(from_position: Vector3, to_position: Vector3) -> float:
	return Vector2(from_position.x, from_position.z).distance_to(Vector2(to_position.x, to_position.z))
