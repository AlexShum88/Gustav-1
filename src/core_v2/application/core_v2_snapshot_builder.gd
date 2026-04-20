class_name CoreV2SnapshotBuilder
extends RefCounted


static func build_snapshot(state: CoreV2BattleState, player_army_id: StringName) -> Dictionary:
	# Compatibility helper for debug tools that still expect one merged snapshot.
	var bootstrap: Dictionary = build_bootstrap_static_snapshot(state, player_army_id, _legacy_metadata(CoreV2SnapshotProtocol.TYPE_BOOTSTRAP_STATIC, state))
	var rare: Dictionary = build_rare_world_delta_snapshot(state, player_army_id, _legacy_metadata(CoreV2SnapshotProtocol.TYPE_RARE_WORLD_DELTA, state))
	var dynamic: Dictionary = build_dynamic_battle_delta_snapshot(state, player_army_id, _legacy_metadata(CoreV2SnapshotProtocol.TYPE_DYNAMIC_BATTLE_DELTA, state))
	return _merge_snapshot_channels(_merge_snapshot_channels(bootstrap, rare), dynamic)


static func build_bootstrap_static_snapshot(state: CoreV2BattleState, player_army_id: StringName, metadata: Dictionary = {}) -> Dictionary:
	var payload: Dictionary = _base_payload(state, player_army_id, {
		"static_world": {
			"map_rect": state.map_rect,
			"deployment_zones": state.get_deployment_zone_snapshots(),
			"terrain_patches": state.get_terrain_patch_snapshots(),
			"roads": state.get_road_snapshots(),
			"scenario": {
				"map_size_m": Vector2(state.map_rect.size.x, state.map_rect.size.y),
				"player_army_id": String(player_army_id),
			},
		},
	})
	return CoreV2SnapshotProtocol.attach_metadata(payload, _metadata_or_default(metadata, CoreV2SnapshotProtocol.TYPE_BOOTSTRAP_STATIC, state))


static func build_rare_world_delta_snapshot(state: CoreV2BattleState, player_army_id: StringName, metadata: Dictionary = {}) -> Dictionary:
	var payload: Dictionary = _base_payload(state, player_army_id, {
		"rare_world": {
			"weather": state.get_weather_snapshot(),
			"objectives": _build_objective_snapshots(state),
			"rare_world_revision": state.rare_world_revision,
		},
	})
	return CoreV2SnapshotProtocol.attach_metadata(payload, _metadata_or_default(metadata, CoreV2SnapshotProtocol.TYPE_RARE_WORLD_DELTA, state))


static func build_dynamic_battle_delta_snapshot(state: CoreV2BattleState, player_army_id: StringName, metadata: Dictionary = {}) -> Dictionary:
	var dynamic_data: Dictionary = _build_dynamic_battle_data(state, player_army_id)
	var payload: Dictionary = _base_payload(state, player_army_id, {
		"units": dynamic_data["units"],
		"ui": dynamic_data["ui"],
	})
	return CoreV2SnapshotProtocol.attach_metadata(payload, _metadata_or_default(metadata, CoreV2SnapshotProtocol.TYPE_DYNAMIC_BATTLE_DELTA, state))


static func _build_dynamic_battle_data(state: CoreV2BattleState, player_army_id: StringName) -> Dictionary:
	var player_army: CoreV2Army = state.get_army(player_army_id)
	var enemy_army: CoreV2Army = _find_primary_enemy(state, player_army_id)
	var battalion_snapshots: Array = []
	var brigade_snapshots: Array = []
	var hq_snapshots: Array = []
	var baggage_snapshots: Array = []
	var messenger_snapshots: Array = state.get_order_messenger_snapshots(player_army_id)
	var visible_enemy_battalions: int = 0

	for army_value in state.armies.values():
		var army: CoreV2Army = army_value
		var is_friendly_army: bool = army.id == player_army_id
		if is_friendly_army or state.is_entity_visible_to_army(player_army_id, CoreV2VisibilitySystem.army_hq_key(army.id)):
			hq_snapshots.append(_with_entity_revision({
				"id": "%s_commander_hq" % String(army.id),
				"entity_kind": CoreV2Types.EntityKind.ARMY_HQ,
				"army_id": String(army.id),
				"army_name": army.display_name,
				"display_name": "Army HQ",
				"commander_name": army.commander.display_name if army.commander != null else "",
				"position": army.commander_position,
				"is_deployed": army.commander_deployed,
				"is_friendly": is_friendly_army,
				"health": army.commander_health,
				"recent_damage": army.commander_recent_damage,
				"is_destroyed": army.commander_destroyed,
				"status_label": "destroyed" if army.commander_destroyed else "active",
				"color": army.color,
			}))
		if is_friendly_army or state.is_entity_visible_to_army(player_army_id, CoreV2VisibilitySystem.baggage_key(army.id)):
			baggage_snapshots.append(_with_entity_revision({
				"id": "%s_baggage" % String(army.id),
				"entity_kind": CoreV2Types.EntityKind.BAGGAGE_TRAIN,
				"army_id": String(army.id),
				"display_name": "Baggage",
				"position": army.baggage_position,
				"is_deployed": army.baggage_deployed,
				"is_friendly": is_friendly_army,
				"color": army.color.darkened(0.15),
				"baggage_supply": army.baggage_supply,
				"baggage_ammo": army.baggage_ammo,
			}))
		for brigade_value in army.brigades:
			var brigade: CoreV2Brigade = brigade_value
			var is_brigade_visible: bool = is_friendly_army or state.is_entity_visible_to_army(player_army_id, CoreV2VisibilitySystem.brigade_hq_key(brigade.id))
			if is_brigade_visible:
				hq_snapshots.append(_with_entity_revision({
					"id": "%s_hq" % String(brigade.id),
					"entity_kind": CoreV2Types.EntityKind.BRIGADE_HQ,
					"army_id": String(army.id),
					"army_name": army.display_name,
					"brigade_id": String(brigade.id),
					"display_name": brigade.display_name,
					"commander_name": brigade.commander.display_name if brigade.commander != null else "",
					"position": brigade.hq_position,
					"is_friendly": is_friendly_army,
					"health": brigade.hq_health,
					"recent_damage": brigade.hq_recent_damage,
					"is_destroyed": brigade.hq_destroyed,
					"status_label": "destroyed" if brigade.hq_destroyed else "active",
					"battalion_ids": _build_brigade_battalion_ids(brigade, state, player_army_id, is_friendly_army),
					"battalion_names": _build_brigade_battalion_names(brigade, state, player_army_id, is_friendly_army),
					"battalion_count": _count_brigade_battalions_for_snapshot(brigade, state, player_army_id, is_friendly_army),
					"color": army.color.lightened(0.12),
					"order_label": CoreV2Types.order_type_name(
						brigade.current_order.order_type if brigade.current_order != null else CoreV2Types.OrderType.NONE
					),
					"frontage_gap_ratio": brigade.frontage_gap_ratio,
					"support_penalty": brigade.support_penalty,
					"line_stretch_ratio": brigade.line_stretch_ratio,
					"detached_battalion_ids": brigade.detached_battalion_ids.keys(),
				}))
			for battalion_value in brigade.battalions:
				var battalion: CoreV2Battalion = battalion_value
				if not is_friendly_army and not state.is_entity_visible_to_army(player_army_id, CoreV2VisibilitySystem.battalion_key(battalion.id)):
					continue
				if not is_friendly_army:
					visible_enemy_battalions += 1
					is_brigade_visible = true
				var battalion_snapshot: Dictionary = battalion.create_snapshot(player_army_id)
				battalion_snapshot["color"] = army.color
				battalion_snapshot["brigade_name"] = brigade.display_name
				battalion_snapshot["army_name"] = army.display_name
				battalion_snapshot["terrain_speed_multiplier"] = state.get_speed_multiplier_at(battalion.position, battalion.category)
				battalion_snapshot["terrain_vision_multiplier"] = state.get_visibility_multiplier_at(battalion.position)
				battalion_snapshot["terrain_defense_modifier"] = state.get_defense_modifier_at(battalion.position)
				battalion_snapshot["terrain_height_m"] = state.get_height_at(battalion.position)
				battalion_snapshot["terrain_label"] = state.get_terrain_label_at(battalion.position)
				battalion_snapshot["weather_vision_multiplier"] = state.get_weather_visibility_multiplier()
				battalion_snapshot["smoke_density"] = state.get_smoke_density_at(battalion.position)
				battalion_snapshot["smoke_vision_multiplier"] = state.get_smoke_vision_multiplier_at(battalion.position)
				battalion_snapshot["atmospheric_vision_multiplier"] = state.get_atmospheric_visibility_multiplier_at(battalion.position)
				battalion_snapshot["effective_vision_radius_m"] = state.get_observer_vision_radius_at(
					battalion.position,
					battalion.vision_radius_m
				)
				battalion_snapshots.append(_with_entity_revision(battalion_snapshot))
			if is_brigade_visible:
				brigade_snapshots.append(_with_entity_revision(brigade.create_snapshot()))

	return {
		"units": {
			"battalions": battalion_snapshots,
			"brigades": brigade_snapshots,
			"hqs": hq_snapshots,
			"baggage_trains": baggage_snapshots,
			"smoke_zones": state.get_smoke_zone_snapshots(player_army_id),
			"order_messengers": messenger_snapshots,
			"objectives": _build_objective_snapshots(state),
			"last_seen_markers": state.get_last_seen_marker_snapshots(player_army_id),
		},
		"ui": {
			"top_bar": _build_top_bar(player_army, enemy_army, state, player_army_id, visible_enemy_battalions),
			"recent_events": state.recent_events.duplicate(),
			"deployment": _build_deployment_info(player_army, state.phase),
			"reserve_queue": player_army.reserve_queue.duplicate(true) if player_army != null else [],
		},
	}


static func _build_objective_snapshots(state: CoreV2BattleState) -> Array:
	var objective_snapshots: Array = []
	for objective_value in state.objectives:
		var objective: CoreV2Objective = objective_value
		var objective_snapshot: Dictionary = objective.create_snapshot()
		var owner_army: CoreV2Army = state.get_army(objective.owner_army_id)
		objective_snapshot["owner_name"] = owner_army.display_name if owner_army != null else "Neutral"
		objective_snapshot["owner_color"] = owner_army.color if owner_army != null else Color(0.7, 0.7, 0.7)
		objective_snapshots.append(_with_entity_revision(objective_snapshot))
	return objective_snapshots


static func _base_payload(state: CoreV2BattleState, player_army_id: StringName, channels: Dictionary) -> Dictionary:
	return {
		"time_seconds": state.time_seconds,
		"phase": state.phase,
		"phase_label": CoreV2Types.battle_phase_name(state.phase),
		"player_army_id": String(player_army_id),
		"world_revision": state.static_world_revision,
		"battle_revision": state.battle_revision,
		"channels": channels,
	}


static func _metadata_or_default(metadata: Dictionary, snapshot_type: String, state: CoreV2BattleState) -> Dictionary:
	if not metadata.is_empty():
		return metadata
	return _legacy_metadata(snapshot_type, state)


static func _legacy_metadata(snapshot_type: String, state: CoreV2BattleState) -> Dictionary:
	return CoreV2SnapshotProtocol.make_metadata(
		snapshot_type,
		0,
		0,
		state.static_world_revision,
		state.battle_revision
	)


static func _merge_snapshot_channels(base: Dictionary, patch: Dictionary) -> Dictionary:
	var result: Dictionary = base.duplicate(true)
	var result_channels: Dictionary = result.get("channels", {})
	var patch_channels: Dictionary = patch.get("channels", {})
	for channel_key_value in patch_channels.keys():
		var channel_key: String = String(channel_key_value)
		result_channels[channel_key] = patch_channels[channel_key_value]
	result["channels"] = result_channels
	for key_value in patch.keys():
		var key: String = String(key_value)
		if key == "channels":
			continue
		result[key] = patch[key]
	return result


static func _with_entity_revision(entity_snapshot: Dictionary) -> Dictionary:
	var result: Dictionary = entity_snapshot.duplicate(true)
	if not result.has("entity_id"):
		result["entity_id"] = String(result.get("id", ""))
	result["entity_revision"] = result.hash()
	result["removed"] = false
	return result


static func _build_top_bar(
		player_army: CoreV2Army,
		enemy_army: CoreV2Army,
		state: CoreV2BattleState,
		player_army_id: StringName,
		visible_enemy_battalions: int
) -> Dictionary:
	return {
		"army_name": player_army.display_name if player_army != null else "Army",
		"phase_label": CoreV2Types.battle_phase_name(state.phase),
		"army_morale": player_army.army_morale if player_army != null else 0.0,
		"baggage_supply": player_army.baggage_supply if player_army != null else 0.0,
		"baggage_ammo": player_army.baggage_ammo if player_army != null else 0.0,
		"own_victory_points": player_army.victory_points if player_army != null else 0.0,
		"enemy_victory_points": enemy_army.victory_points if enemy_army != null else 0.0,
		"held_objectives": _count_owned_objectives(state, player_army.id if player_army != null else &""),
		"enemy_held_objectives": _count_owned_objectives(state, enemy_army.id if enemy_army != null else &""),
		"recent_supply_income": player_army.recent_supply_income if player_army != null else 0.0,
		"visible_enemy_battalions": visible_enemy_battalions,
		"last_seen_contacts": state.get_last_seen_marker_snapshots(player_army_id).size(),
		"own_order_messengers": state.count_order_messengers_for_army(player_army.id if player_army != null else &""),
		"weather_label": String(state.weather_profile.get("display_name", "Clear")),
		"weather_vision_multiplier": state.get_weather_visibility_multiplier(),
	}


static func _build_brigade_battalion_ids(brigade: CoreV2Brigade, state: CoreV2BattleState, player_army_id: StringName, include_all: bool) -> Array:
	var battalion_ids: Array = []
	for battalion_value in brigade.battalions:
		var battalion: CoreV2Battalion = battalion_value
		if not _should_include_brigade_battalion_in_snapshot(battalion, state, player_army_id, include_all):
			continue
		battalion_ids.append(String(battalion.id))
	return battalion_ids


static func _build_brigade_battalion_names(brigade: CoreV2Brigade, state: CoreV2BattleState, player_army_id: StringName, include_all: bool) -> Array:
	var battalion_names: Array = []
	for battalion_value in brigade.battalions:
		var battalion: CoreV2Battalion = battalion_value
		if not _should_include_brigade_battalion_in_snapshot(battalion, state, player_army_id, include_all):
			continue
		battalion_names.append(battalion.display_name)
	return battalion_names


static func _count_brigade_battalions_for_snapshot(brigade: CoreV2Brigade, state: CoreV2BattleState, player_army_id: StringName, include_all: bool) -> int:
	var result: int = 0
	for battalion_value in brigade.battalions:
		var battalion: CoreV2Battalion = battalion_value
		if _should_include_brigade_battalion_in_snapshot(battalion, state, player_army_id, include_all):
			result += 1
	return result


static func _should_include_brigade_battalion_in_snapshot(battalion: CoreV2Battalion, state: CoreV2BattleState, player_army_id: StringName, include_all: bool) -> bool:
	return include_all or state.is_entity_visible_to_army(player_army_id, CoreV2VisibilitySystem.battalion_key(battalion.id))


static func _build_deployment_info(player_army: CoreV2Army, battle_phase: int) -> Dictionary:
	if player_army == null:
		return {}
	return {
		"is_baggage_ready": player_army.baggage_deployed,
		"is_commander_ready": player_army.commander_deployed,
		"is_ready": player_army.is_deployment_ready(),
		"battle_phase": battle_phase,
	}


static func _find_primary_enemy(state: CoreV2BattleState, player_army_id: StringName) -> CoreV2Army:
	for army_id_value in state.armies.keys():
		var army_id: StringName = army_id_value
		if army_id == player_army_id:
			continue
		return state.armies[army_id]
	return null


static func _count_owned_objectives(state: CoreV2BattleState, army_id: StringName) -> int:
	var result: int = 0
	for objective_value in state.objectives:
		var objective: CoreV2Objective = objective_value
		if objective.owner_army_id == army_id:
			result += 1
	return result
