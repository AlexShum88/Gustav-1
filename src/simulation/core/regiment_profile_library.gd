class_name RegimentProfileLibrary
extends RefCounted

const RegimentCommandProfile = preload("res://src/simulation/entities/regiment_command_profile.gd")
const RegimentBannerProfile = preload("res://src/simulation/entities/regiment_banner_profile.gd")


static func get_command_profile(profile_id: StringName, fallback_category: int = SimTypes.UnitCategory.INFANTRY) -> RegimentCommandProfile:
	match profile_id:
		&"infantry_standard":
			return RegimentCommandProfile.new(profile_id, "Standard Major", 4, 1.0, 1.0, 0.0)
		&"cavalry_standard":
			return RegimentCommandProfile.new(profile_id, "Horse Major", 4, 1.04, 1.02, 0.02)
		&"artillery_standard":
			return RegimentCommandProfile.new(profile_id, "Battery Major", 4, 0.92, 0.96, 0.0)
		&"expanded_colonel":
			return RegimentCommandProfile.new(profile_id, "Senior Major", 6, 1.06, 1.05, 0.04)
		&"tercio_maestre":
			return RegimentCommandProfile.new(profile_id, "Maestre de Campo", 8, 1.1, 1.08, 0.06)
		_:
			return get_default_command_profile(fallback_category)


static func get_default_command_profile(category: int) -> RegimentCommandProfile:
	match category:
		SimTypes.UnitCategory.CAVALRY:
			return get_command_profile(&"cavalry_standard", category)
		SimTypes.UnitCategory.ARTILLERY:
			return get_command_profile(&"artillery_standard", category)
		_:
			return get_command_profile(&"infantry_standard", category)


static func get_banner_profile(profile_id: StringName) -> RegimentBannerProfile:
	match profile_id:
		&"tercio_colors":
			return RegimentBannerProfile.new(profile_id, "Spanish Tercio Colors", &"banner_tercia")
		&"guard_colors":
			return RegimentBannerProfile.new(profile_id, "Guard Colors", &"banner_guard")
		_:
			return RegimentBannerProfile.new(&"standard_colors", "Standard Colors", &"banner")


static func get_default_banner_profile(_category: int) -> RegimentBannerProfile:
	return get_banner_profile(&"standard_colors")


static func get_command_profiles_for_category(category: int) -> Array:
	var profile_ids: Array = []
	match category:
		SimTypes.UnitCategory.CAVALRY:
			profile_ids = [&"cavalry_standard", &"expanded_colonel"]
		SimTypes.UnitCategory.ARTILLERY:
			profile_ids = [&"artillery_standard", &"expanded_colonel"]
		_:
			profile_ids = [&"infantry_standard", &"expanded_colonel", &"tercio_maestre"]
	var profiles: Array = []
	for profile_id_value in profile_ids:
		var profile_id: StringName = profile_id_value
		profiles.append(get_command_profile(profile_id, category))
	return profiles


static func get_banner_profiles_for_category(category: int) -> Array:
	var profile_ids: Array = [&"standard_colors", &"guard_colors"]
	if category == SimTypes.UnitCategory.INFANTRY:
		profile_ids.append(&"tercio_colors")
	var profiles: Array = []
	for profile_id_value in profile_ids:
		var profile_id: StringName = profile_id_value
		profiles.append(get_banner_profile(profile_id))
	return profiles
