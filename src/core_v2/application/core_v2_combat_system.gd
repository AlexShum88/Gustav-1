class_name CoreV2CombatSystem
extends RefCounted


const INFANTRY_FIRE_RANGE_M: float = 150.0
const ARTILLERY_FIRE_RANGE_M: float = 850.0
const MELEE_RANGE_M: float = 45.0
const CAVALRY_MELEE_RANGE_M: float = 70.0
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


static func update_combat(state: CoreV2BattleState, delta: float) -> void:
	var active_battalions: Array = _prepare_battalions_for_sprite_combat(state, delta)
	var combat_result: Dictionary = {
		"damage_events": [],
		"smoke_events": {},
	}
	for attacker_value in active_battalions:
		var attacker: CoreV2Battalion = attacker_value
		_update_sprite_block_attacks(state, attacker, combat_result)
	_apply_sprite_combat_results(state, combat_result)
	for battalion_value in active_battalions:
		_refresh_battalion_combat_summary(state, battalion_value)
	_update_headquarters_exposure(state, delta)


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
	battalion.combat_melee_blocks = 0
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
	if target.cohesion > ROUT_COHESION_THRESHOLD and target.soldiers_total > ROUT_SOLDIERS_THRESHOLD:
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
		attacker.sync_sprite_blocks(state)
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
	var damage_weight: float = 0.0
	for block_value in attacker.sprite_blocks:
		var block: CoreV2SpriteBlock = block_value
		if block.soldiers <= 0:
			continue
		var distance_m: float = _distance_2d(block.world_position, hq_position)
		var attack_profile: Dictionary = _build_sprite_attack_profile(attacker, block, distance_m)
		if attack_profile.is_empty():
			continue
		if not _is_target_in_fire_arc(attacker, block, hq_position, attack_profile):
			continue
		var smoke_density: float = state.get_smoke_density_between(block.world_position, hq_position)
		var attack_weight: float = max(0.15, attacker.training) * max(0.12, attacker.cohesion)
		if String(attack_profile.get("attack_kind", "")) == "melee":
			attack_weight *= _resolve_range_factor(distance_m, float(attack_profile.get("range_m", 1.0)))
			attack_weight *= _resolve_line_of_fire_factor(smoke_density, attack_profile)
			attack_weight *= clamp(float(block.soldiers) / SPRITE_SOLDIERS_BASELINE, 0.08, 1.2)
			attack_weight *= HQ_MELEE_DAMAGE_MULTIPLIER
		else:
			attack_weight = CoreV2CombatMath.resolve_fire_attack_weight(
				state,
				attacker,
				block,
				hq_position,
				distance_m,
				attack_profile,
				smoke_density
			)
		damage_weight += attack_weight
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
	return battalion == null or battalion.status == CoreV2Types.UnitStatus.ROUTING or battalion.soldiers_total <= 0 or battalion.sprite_count <= 0


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
