class_name SimulationServer
extends Node

signal snapshot_ready(snapshot: Dictionary)

const DEFAULT_SIM_TICK_RATE: float = 16.0
const DEFAULT_SNAPSHOT_RATE: float = 12.0

var simulation: BattleSimulation
var player_army_id: StringName = &"blue"
var sim_tick_rate: float = DEFAULT_SIM_TICK_RATE
var snapshot_rate: float = DEFAULT_SNAPSHOT_RATE
var _sim_tick_step: float = 1.0 / DEFAULT_SIM_TICK_RATE
var _snapshot_step: float = 1.0 / DEFAULT_SNAPSHOT_RATE
var _sim_accumulator: float = 0.0
var _snapshot_accumulator: float = 0.0
var _paused: bool = false
var _battle_log_path: String = ""
var _battle_log_file: FileAccess
var _battle_log_buffer: Array = []
var _battle_log_flush_accumulator: float = 0.0
var _battle_log_state_accumulator: float = 0.0
var _seen_recent_events: Dictionary = {}
var _seen_recent_event_order: Array = []
var _view_interest: Dictionary = {}
var _static_world_sent: bool = false
var _last_units_regiment_hashes: Dictionary = {}

const BATTLE_LOG_DIR: String = "res://battle_logs"
const BATTLE_LOG_STATE_INTERVAL: float = 1.0
const BATTLE_LOG_FLUSH_INTERVAL: float = 0.5
const BATTLE_LOG_MAX_SEEN_EVENTS: int = 256
const PERF_WARN_SNAPSHOT_MS: float = 12.0
const PERF_WARN_VISIBILITY_MS: float = 6.0
const PERF_WARN_BEHAVIOR_MS: float = 4.0
const PERF_WARN_ADVANCE_MS: float = 20.0


func configure(new_simulation: BattleSimulation, new_player_army_id: StringName) -> void:
	_finalize_battle_log()
	simulation = new_simulation
	player_army_id = new_player_army_id
	_sim_accumulator = 0.0
	_snapshot_accumulator = 0.0
	_paused = false
	_battle_log_flush_accumulator = 0.0
	_battle_log_state_accumulator = 0.0
	_seen_recent_events.clear()
	_seen_recent_event_order.clear()
	_view_interest = {}
	_static_world_sent = false
	_last_units_regiment_hashes.clear()
	_initialize_battle_log()
	if simulation != null:
		emit_signal("snapshot_ready", _build_client_snapshot())


func set_paused(value: bool) -> void:
	_paused = value
	if simulation != null:
		emit_signal("snapshot_ready", _build_client_snapshot())


func set_view_interest(
		visible_rect: Rect2,
		zoom: float,
		selected_regiment_id: StringName = &"",
		selected_brigade_id: StringName = &""
) -> void:
	_view_interest = {
		"visible_rect": visible_rect,
		"zoom": zoom,
		"selected_regiment_id": String(selected_regiment_id),
		"selected_brigade_id": String(selected_brigade_id),
	}


func submit_player_command(command: Dictionary) -> void:
	if simulation == null:
		return
	simulation.queue_player_command(command)


func set_regiment_debug_formation(regiment_id: StringName, formation_state: int) -> void:
	if simulation == null:
		return
	simulation.set_regiment_debug_formation(regiment_id, formation_state)
	emit_signal("snapshot_ready", _build_client_snapshot())


func set_regiment_debug_fire_behavior(regiment_id: StringName, fire_behavior: int) -> void:
	if simulation == null:
		return
	simulation.set_regiment_debug_fire_behavior(regiment_id, fire_behavior)
	emit_signal("snapshot_ready", _build_client_snapshot())


func clear_regiment_debug_overrides(regiment_id: StringName) -> void:
	if simulation == null:
		return
	simulation.clear_regiment_debug_overrides(regiment_id)
	emit_signal("snapshot_ready", _build_client_snapshot())


func trigger_regiment_debug_fire(regiment_id: StringName, duration_seconds: float = 2.5) -> void:
	if simulation == null:
		return
	simulation.trigger_regiment_debug_fire(regiment_id, duration_seconds)
	emit_signal("snapshot_ready", _build_client_snapshot())


func set_regiment_command_profile(regiment_id: StringName, profile_id: StringName) -> void:
	if simulation == null:
		return
	if simulation.set_regiment_command_profile(regiment_id, profile_id):
		emit_signal("snapshot_ready", _build_client_snapshot())


func set_regiment_banner_profile(regiment_id: StringName, profile_id: StringName) -> void:
	if simulation == null:
		return
	if simulation.set_regiment_banner_profile(regiment_id, profile_id):
		emit_signal("snapshot_ready", _build_client_snapshot())


func add_company_to_regiment(regiment_id: StringName, company_type: int) -> void:
	if simulation == null:
		return
	if simulation.add_company_to_regiment(regiment_id, company_type):
		emit_signal("snapshot_ready", _build_client_snapshot())


func remove_company_from_regiment(regiment_id: StringName, company_type: int) -> void:
	if simulation == null:
		return
	if simulation.remove_company_from_regiment(regiment_id, company_type):
		emit_signal("snapshot_ready", _build_client_snapshot())


func _physics_process(delta: float) -> void:
	if simulation == null:
		return
	if _paused:
		_flush_battle_log(false)
		return
	_sim_accumulator += delta
	_snapshot_accumulator += delta
	_battle_log_flush_accumulator += delta
	_battle_log_state_accumulator += delta
	while _sim_accumulator >= _sim_tick_step:
		simulation.advance(_sim_tick_step)
		_capture_recent_events_for_log()
		if _battle_log_state_accumulator >= BATTLE_LOG_STATE_INTERVAL:
			_battle_log_state_accumulator = fmod(_battle_log_state_accumulator, BATTLE_LOG_STATE_INTERVAL)
			_append_periodic_state_snapshot()
		_sim_accumulator -= _sim_tick_step
	if _battle_log_flush_accumulator >= BATTLE_LOG_FLUSH_INTERVAL:
		_battle_log_flush_accumulator = fmod(_battle_log_flush_accumulator, BATTLE_LOG_FLUSH_INTERVAL)
		_flush_battle_log(false)
	if _snapshot_accumulator >= _snapshot_step:
		_snapshot_accumulator = fmod(_snapshot_accumulator, _snapshot_step)
		emit_signal("snapshot_ready", _build_client_snapshot())


func _build_client_snapshot() -> Dictionary:
	var snapshot: Dictionary = simulation.build_snapshot_for_army(player_army_id, _view_interest)
	var channels: Dictionary = snapshot.get("channels", {})
	if channels.has("units"):
		channels["units"] = _build_units_channel_delta(channels.get("units", {}))
	snapshot["meta"] = {
		"tick_interval": _sim_tick_step,
		"snapshot_interval": _snapshot_step,
		"battle_log_path": _battle_log_path,
	}
	if _static_world_sent:
		channels.erase("static_world")
	else:
		_static_world_sent = true
	return snapshot


func _build_units_channel_delta(units_channel: Dictionary) -> Dictionary:
	var unit_key: String = "battalions" if units_channel.has("battalions") else "regiments"
	var delta_key: String = "battalions_delta" if unit_key == "battalions" else "regiments_delta"
	var removed_key: String = "removed_battalion_ids" if unit_key == "battalions" else "removed_regiment_ids"
	var order_key: String = "battalion_order" if unit_key == "battalions" else "regiment_order"
	var regiments: Array = units_channel.get(unit_key, [])
	var next_hashes: Dictionary = {}
	var changed_regiments: Array = []
	var regiment_order: Array = []
	for regiment_value in regiments:
		var regiment_snapshot: Dictionary = regiment_value
		var regiment_id: String = String(regiment_snapshot.get("id", ""))
		var regiment_hash: int = regiment_snapshot.hash()
		regiment_order.append(regiment_id)
		next_hashes[regiment_id] = regiment_hash
		if int(_last_units_regiment_hashes.get(regiment_id, -1)) != regiment_hash:
			changed_regiments.append(regiment_snapshot)
	var removed_regiment_ids: Array = []
	for regiment_id_value in _last_units_regiment_hashes.keys():
		var regiment_id: String = String(regiment_id_value)
		if next_hashes.has(regiment_id):
			continue
		removed_regiment_ids.append(regiment_id)
	var send_full: bool = _last_units_regiment_hashes.is_empty() \
		or changed_regiments.size() > max(6, int(ceil(float(regiments.size()) * 0.55)))
	_last_units_regiment_hashes = next_hashes
	if send_full:
		return units_channel
	var delta_channel: Dictionary = {
		"stamp": units_channel.get("stamp", 0.0),
		"zoom": units_channel.get("zoom", 1.0),
		"visible_rect": units_channel.get("visible_rect", Rect2()),
		"is_delta": true,
		delta_key: changed_regiments,
		removed_key: removed_regiment_ids,
		order_key: regiment_order,
		"hqs": units_channel.get("hqs", []),
		"messengers": units_channel.get("messengers", []),
		"convoys": units_channel.get("convoys", []),
		"last_seen_markers": units_channel.get("last_seen_markers", []),
		"strategic_points": units_channel.get("strategic_points", []),
	}
	return delta_channel


func _exit_tree() -> void:
	_finalize_battle_log()


func _initialize_battle_log() -> void:
	if simulation == null:
		return
	var log_directory: String = ProjectSettings.globalize_path(BATTLE_LOG_DIR)
	DirAccess.make_dir_absolute(log_directory)
	var date_parts: Dictionary = Time.get_datetime_dict_from_system()
	var timestamp: String = "%04d%02d%02d_%02d%02d%02d" % [
		int(date_parts.get("year", 0)),
		int(date_parts.get("month", 0)),
		int(date_parts.get("day", 0)),
		int(date_parts.get("hour", 0)),
		int(date_parts.get("minute", 0)),
		int(date_parts.get("second", 0)),
	]
	_battle_log_path = "%s/battle_%s.log" % [log_directory, timestamp]
	_battle_log_file = FileAccess.open(_battle_log_path, FileAccess.WRITE)
	if _battle_log_file == null:
		_battle_log_path = ""
		return
	_enqueue_battle_log_line("# battle log")
	_enqueue_battle_log_line("player_army=%s sim_tick=%.4f snapshot_tick=%.4f" % [
		String(player_army_id),
		_sim_tick_step,
		_snapshot_step,
	])
	_enqueue_battle_log_line("map_rect=%s" % [str(simulation.map_rect)])
	for army_value in simulation.armies.values():
		var army: Army = army_value
		_enqueue_battle_log_line("army id=%s name=%s" % [String(army.id), army.display_name])
	_flush_battle_log(true)


func _finalize_battle_log() -> void:
	_flush_battle_log(true)
	_battle_log_file = null
	_battle_log_path = ""
	_battle_log_buffer.clear()


func _enqueue_battle_log_line(line: String) -> void:
	if _battle_log_file == null:
		return
	_battle_log_buffer.append(line)


func _flush_battle_log(force: bool) -> void:
	if _battle_log_file == null:
		return
	if _battle_log_buffer.is_empty() and not force:
		return
	for line_value in _battle_log_buffer:
		_battle_log_file.store_line(String(line_value))
	_battle_log_buffer.clear()
	_battle_log_file.flush()


func _capture_recent_events_for_log() -> void:
	if simulation == null:
		return
	for event_value in simulation.recent_events:
		var event_text: String = String(event_value)
		if _seen_recent_events.has(event_text):
			continue
		_seen_recent_events[event_text] = true
		_seen_recent_event_order.append(event_text)
		if _seen_recent_event_order.size() > BATTLE_LOG_MAX_SEEN_EVENTS:
			var expired_event: String = String(_seen_recent_event_order.pop_front())
			_seen_recent_events.erase(expired_event)
		_enqueue_battle_log_line("EVENT %s" % event_text)


func _append_periodic_state_snapshot() -> void:
	if simulation == null:
		return
	_enqueue_battle_log_line("")
	_enqueue_battle_log_line("[T=%.2f]" % simulation.time_seconds)
	_enqueue_battle_log_line(
			"PERF snapshot=%.2fms visibility=%.2fms logistics=%.2fms ai=%.2fms behavior=%.2fms combat=%.2fms combat_frame=%.2fms advance=%.2fms regiments=%d convoys=%d" % [
				simulation._last_snapshot_build_ms,
				simulation._last_visibility_update_ms,
				simulation._last_logistics_tick_ms,
				simulation._last_ai_tick_ms,
				simulation._last_behavior_tick_ms,
				simulation._last_combat_tick_ms,
				simulation.combat_system.last_frame_build_ms if simulation.combat_system != null else 0.0,
				simulation._last_advance_tick_ms,
				simulation.regiments.size(),
				simulation.supply_convoys.size(),
			]
	)
	if simulation.combat_system != null:
		_enqueue_battle_log_line(
			"COMBAT fire=%d shots=%d hits=%d fire_cas=%d art=%d art_hits=%d art_cas=%d charge=%d charge_cas=%d melee=%d melee_cas=%d" % [
				simulation.combat_system.last_small_arms_firers,
				simulation.combat_system.last_small_arms_samples,
				simulation.combat_system.last_small_arms_hits,
				simulation.combat_system.last_small_arms_casualties,
				simulation.combat_system.last_artillery_firers,
				simulation.combat_system.last_artillery_hits,
				simulation.combat_system.last_artillery_casualties,
				simulation.combat_system.last_charge_impacts,
				simulation.combat_system.last_charge_casualties,
				simulation.combat_system.last_melee_edges,
				simulation.combat_system.last_melee_casualties,
			]
		)
	if simulation._last_snapshot_build_ms >= PERF_WARN_SNAPSHOT_MS \
			or simulation._last_visibility_update_ms >= PERF_WARN_VISIBILITY_MS \
			or simulation._last_behavior_tick_ms >= PERF_WARN_BEHAVIOR_MS \
			or simulation._last_advance_tick_ms >= PERF_WARN_ADVANCE_MS:
		_enqueue_battle_log_line(
			"PERF_WARN snapshot=%.2f visibility=%.2f behavior=%.2f advance=%.2f" % [
				simulation._last_snapshot_build_ms,
				simulation._last_visibility_update_ms,
				simulation._last_behavior_tick_ms,
				simulation._last_advance_tick_ms,
			]
		)
	for regiment_value in simulation.regiments.values():
		var regiment: Battalion = regiment_value
		if regiment == null or regiment.is_destroyed:
			continue
		var nearest_enemy: Battalion = simulation.find_nearest_enemy(regiment)
		var nearest_enemy_id: String = "-" if nearest_enemy == null else String(nearest_enemy.id)
		var nearest_enemy_distance: float = -1.0 if nearest_enemy == null else regiment.position.distance_to(nearest_enemy.position)
		_enqueue_battle_log_line(
			"REG id=%s army=%s pos=(%.1f,%.1f) order=%s status=%s formation=%s reform=%s fire=%s strength=%d fatigue=%.3f nearest=%s dist=%.1f" % [
				String(regiment.id),
				String(regiment.army_id),
				regiment.position.x,
				regiment.position.y,
				SimTypes.order_type_name(regiment.current_order_type),
				regiment.state_label,
				SimTypes.regiment_formation_state_name(regiment.formation_state),
				"Y" if regiment.is_reforming(simulation.time_seconds) else "N",
				SimTypes.regiment_fire_behavior_name(regiment.fire_behavior),
				regiment.get_total_strength(),
				regiment.fatigue,
				nearest_enemy_id,
				nearest_enemy_distance,
			]
		)
