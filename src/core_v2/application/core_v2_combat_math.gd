class_name CoreV2CombatMath
extends RefCounted


const MUSKET_MAX_ACCURACY: float = 0.24
const MUSKET_RANGE_CURVE_POWER: float = 1.12
const MUSKET_CASUALTY_CONVERSION: float = 0.18
const MUSKET_MIN_EFFECTIVE_RANGE_FACTOR: float = 0.012

const ARTILLERY_MAX_ACCURACY: float = 0.52
const ARTILLERY_RANGE_CURVE_POWER: float = 0.82
const ARTILLERY_CREW_FIREPOWER_SHARE: float = 0.14
const ARTILLERY_CASUALTY_CONVERSION: float = 0.42

const FIRE_RNG_MIN: float = 0.85
const FIRE_RNG_MAX: float = 1.15
const SMOKE_ACCURACY_LOSS: float = 0.88


static func resolve_fire_casualties(
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
	var max_range_m: float = float(attack_profile.get("range_m", 1.0))
	var effective_shooters: float = _resolve_effective_shooters(attacker, block, attack_kind)
	if effective_shooters <= 0.0:
		return 0.0

	# Сервер рахує один агрегований залп блоку, а не окремі кидки для кожного солдата.
	var range_accuracy: float = _resolve_range_accuracy(distance_m, max_range_m, attack_kind)
	var attack_multiplier: float = _resolve_attacker_fire_multiplier(attacker)
	var line_multiplier: float = _resolve_line_of_fire_multiplier(state, target_block.world_position, smoke_density)
	var target_multiplier: float = _resolve_target_fire_multiplier(state, target, target_block)
	var casualty_conversion: float = _resolve_casualty_conversion(attack_kind)
	var rng_factor: float = _resolve_seeded_rng_factor(state, attacker, block, target, target_block, attack_kind)

	var expected_casualties: float = effective_shooters
	expected_casualties *= range_accuracy
	expected_casualties *= casualty_conversion
	expected_casualties *= attack_multiplier
	expected_casualties *= line_multiplier
	expected_casualties *= target_multiplier
	expected_casualties *= rng_factor
	return clamp(expected_casualties, 0.0, float(max(0, target_block.soldiers)))


static func resolve_fire_attack_weight(
		state: CoreV2BattleState,
		attacker: CoreV2Battalion,
		block: CoreV2SpriteBlock,
		target_position: Vector3,
		distance_m: float,
		attack_profile: Dictionary,
		smoke_density: float
) -> float:
	var attack_kind: String = String(attack_profile.get("attack_kind", ""))
	var max_range_m: float = float(attack_profile.get("range_m", 1.0))
	var effective_shooters: float = _resolve_effective_shooters(attacker, block, attack_kind)
	if effective_shooters <= 0.0:
		return 0.0
	var attack_weight: float = effective_shooters / float(CoreV2SpriteBlock.DEFAULT_SOLDIERS_PER_BLOCK)
	attack_weight *= _resolve_range_accuracy(distance_m, max_range_m, attack_kind)
	attack_weight *= _resolve_attacker_fire_multiplier(attacker)
	attack_weight *= _resolve_line_of_fire_multiplier(state, target_position, smoke_density)
	return attack_weight


static func resolve_casualty_rounding_roll(
		attacker: CoreV2Battalion,
		block: CoreV2SpriteBlock,
		target: CoreV2Battalion,
		target_block: CoreV2SpriteBlock,
		attack_kind: String
) -> float:
	var seed_text: String = "%s|%d|%s|%d|%s|%d|round" % [
		String(attacker.id),
		block.index,
		String(target.id),
		target_block.index,
		attack_kind,
		block.combat_sequence,
	]
	var rng := RandomNumberGenerator.new()
	rng.seed = _positive_hash(seed_text)
	return rng.randf()


static func _resolve_effective_shooters(attacker: CoreV2Battalion, block: CoreV2SpriteBlock, attack_kind: String) -> float:
	if attack_kind == "artillery":
		return float(block.soldiers) * ARTILLERY_CREW_FIREPOWER_SHARE
	if attack_kind != "musket":
		return 0.0
	var role_share: float = _resolve_role_fire_share(block.role)
	if role_share <= 0.0:
		return 0.0
	var rank_factor: float = _resolve_firing_rank_factor(attacker)
	return float(block.soldiers) * role_share * rank_factor


static func _resolve_role_fire_share(role: String) -> float:
	match role:
		"musketeer":
			return 1.0
		"mixed":
			return 0.55
		_:
			return 0.0


static func _resolve_firing_rank_factor(attacker: CoreV2Battalion) -> float:
	var formation_factor: float = 0.62
	match attacker.formation_state:
		CoreV2Types.FormationState.MUSKETEER_LINE:
			formation_factor = 0.94
		CoreV2Types.FormationState.LINE:
			formation_factor = 0.72
		CoreV2Types.FormationState.DEFENSIVE:
			formation_factor = 0.38
		CoreV2Types.FormationState.TERCIA:
			formation_factor = 0.48
		CoreV2Types.FormationState.COLUMN:
			formation_factor = 0.32
		CoreV2Types.FormationState.MARCH_COLUMN:
			formation_factor = 0.18
	if attacker.is_reforming:
		formation_factor *= lerp(0.55, 1.0, clamp(attacker.formation_progress, 0.0, 1.0))
	return formation_factor


static func _resolve_range_accuracy(distance_m: float, max_range_m: float, attack_kind: String) -> float:
	if max_range_m <= 0.01 or distance_m > max_range_m:
		return 0.0
	var closeness: float = 1.0 - clamp(distance_m / max_range_m, 0.0, 1.0)
	if attack_kind == "artillery":
		return ARTILLERY_MAX_ACCURACY * pow(closeness, ARTILLERY_RANGE_CURVE_POWER)
	return max(MUSKET_MIN_EFFECTIVE_RANGE_FACTOR, MUSKET_MAX_ACCURACY * pow(closeness, MUSKET_RANGE_CURVE_POWER))


static func _resolve_attacker_fire_multiplier(attacker: CoreV2Battalion) -> float:
	var training_factor: float = lerp(0.58, 1.24, clamp(attacker.training, 0.0, 1.0))
	var cohesion_factor: float = lerp(0.35, 1.12, clamp(attacker.cohesion, 0.0, 1.0))
	var ammo_factor: float = clamp(0.35 + attacker.ammunition * 0.72, 0.35, 1.0)
	return training_factor * cohesion_factor * ammo_factor


static func _resolve_line_of_fire_multiplier(state: CoreV2BattleState, target_position: Vector3, smoke_density: float) -> float:
	var smoke_multiplier: float = max(0.12, 1.0 - clamp(smoke_density, 0.0, 1.0) * SMOKE_ACCURACY_LOSS)
	var weather_multiplier: float = state.get_weather_visibility_multiplier()
	var target_visibility_multiplier: float = state.get_visibility_multiplier_at(target_position)
	return smoke_multiplier * clamp(weather_multiplier, 0.25, 1.15) * clamp(target_visibility_multiplier, 0.45, 1.08)


static func _resolve_target_fire_multiplier(state: CoreV2BattleState, target: CoreV2Battalion, target_block: CoreV2SpriteBlock) -> float:
	var cover_multiplier: float = max(0.24, 1.0 - state.get_defense_modifier_at(target_block.world_position))
	var exposure_multiplier: float = _resolve_target_formation_exposure(target.formation_state)
	var cohesion_vulnerability: float = lerp(1.18, 0.92, clamp(target.cohesion, 0.0, 1.0))
	if target_block.soldiers < CoreV2SpriteBlock.DEFAULT_SOLDIERS_PER_BLOCK:
		cohesion_vulnerability *= 1.05
	return clamp(cover_multiplier * exposure_multiplier * cohesion_vulnerability, 0.18, 1.75)


static func _resolve_target_formation_exposure(formation_state: int) -> float:
	match formation_state:
		CoreV2Types.FormationState.MARCH_COLUMN:
			return 1.42
		CoreV2Types.FormationState.COLUMN:
			return 1.28
		CoreV2Types.FormationState.TERCIA:
			return 1.22
		CoreV2Types.FormationState.MUSKETEER_LINE:
			return 1.06
		CoreV2Types.FormationState.DEFENSIVE:
			return 0.72
		_:
			return 1.0


static func _resolve_casualty_conversion(attack_kind: String) -> float:
	if attack_kind == "artillery":
		return ARTILLERY_CASUALTY_CONVERSION
	return MUSKET_CASUALTY_CONVERSION


static func _resolve_seeded_rng_factor(
		_state: CoreV2BattleState,
		attacker: CoreV2Battalion,
		block: CoreV2SpriteBlock,
		target: CoreV2Battalion,
		target_block: CoreV2SpriteBlock,
		attack_kind: String
) -> float:
	var seed_text: String = "%s|%d|%s|%d|%s|%d" % [
		String(attacker.id),
		block.index,
		String(target.id),
		target_block.index,
		attack_kind,
		block.combat_sequence,
	]
	var rng := RandomNumberGenerator.new()
	rng.seed = _positive_hash(seed_text)
	return rng.randf_range(FIRE_RNG_MIN, FIRE_RNG_MAX)


static func _positive_hash(seed_text: String) -> int:
	var seed_value: int = seed_text.hash()
	if seed_value < 0:
		seed_value = -seed_value
	return seed_value
