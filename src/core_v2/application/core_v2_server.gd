class_name CoreV2Server
extends Node


signal snapshot_ready(snapshot: Dictionary)
signal command_acknowledged(ack: Dictionary)

const DEFAULT_TICK_RATE: float = 12.0
const DEFAULT_SNAPSHOT_RATE: float = 8.0

var battle_state: CoreV2BattleState
var player_army_id: StringName = &"blue"
var _tick_interval: float = 1.0 / DEFAULT_TICK_RATE
var _snapshot_interval: float = 1.0 / DEFAULT_SNAPSHOT_RATE
var _tick_accumulator: float = 0.0
var _snapshot_accumulator: float = 0.0
var _pending_commands := CoreV2PendingCommandQueue.new()
var _server_tick: int = 0
var _snapshot_seq: int = 0
var _last_static_world_revision_sent: int = -1
var _last_rare_world_revision_sent: int = -1


func configure(next_state: CoreV2BattleState, next_player_army_id: StringName) -> void:
	battle_state = next_state
	player_army_id = next_player_army_id
	_tick_accumulator = 0.0
	_snapshot_accumulator = 0.0
	_server_tick = 0
	_snapshot_seq = 0
	_last_static_world_revision_sent = -1
	_last_rare_world_revision_sent = -1
	_pending_commands = CoreV2PendingCommandQueue.new()
	_emit_bootstrap_static_snapshot()
	_emit_rare_world_delta_snapshot()
	_emit_dynamic_battle_snapshot()


func submit_client_command(command: Dictionary) -> void:
	if battle_state == null:
		return
	var validation: Dictionary = CoreV2CommandValidator.validate(battle_state, command)
	if not bool(validation.get("accepted", false)):
		emit_signal("command_acknowledged", {
			"accepted": false,
			"reason": String(validation.get("reason", "rejected")),
			"received_tick": _server_tick,
			"command_type": int(command.get("command_type", -1)),
		})
		return
	emit_signal("command_acknowledged", _pending_commands.enqueue(command, _server_tick))


func _physics_process(delta: float) -> void:
	if battle_state == null:
		return
	_tick_accumulator += delta
	_snapshot_accumulator += delta
	while _tick_accumulator >= _tick_interval:
		_process_pending_commands()
		if battle_state.phase == CoreV2Types.BattlePhase.ACTIVE:
			battle_state.advance(_tick_interval)
		_server_tick += 1
		_tick_accumulator -= _tick_interval

	if battle_state.static_world_revision != _last_static_world_revision_sent:
		_emit_bootstrap_static_snapshot()
	if battle_state.rare_world_revision != _last_rare_world_revision_sent:
		_emit_rare_world_delta_snapshot()
	if _snapshot_accumulator >= _snapshot_interval:
		_snapshot_accumulator = fmod(_snapshot_accumulator, _snapshot_interval)
		_emit_dynamic_battle_snapshot()


func _process_pending_commands() -> void:
	for command_value in _pending_commands.drain():
		var command: Dictionary = command_value
		var validation: Dictionary = CoreV2CommandValidator.validate(battle_state, command)
		if not bool(validation.get("accepted", false)):
			continue
		battle_state.process_command(command)
		battle_state.mark_battle_changed()


func _emit_bootstrap_static_snapshot() -> void:
	_snapshot_seq += 1
	var metadata: Dictionary = CoreV2SnapshotProtocol.make_metadata(
		CoreV2SnapshotProtocol.TYPE_BOOTSTRAP_STATIC,
		_server_tick,
		_snapshot_seq,
		battle_state.static_world_revision,
		battle_state.battle_revision
	)
	_last_static_world_revision_sent = battle_state.static_world_revision
	emit_signal("snapshot_ready", CoreV2SnapshotBuilder.build_bootstrap_static_snapshot(battle_state, player_army_id, metadata))


func _emit_rare_world_delta_snapshot() -> void:
	_snapshot_seq += 1
	var metadata: Dictionary = CoreV2SnapshotProtocol.make_metadata(
		CoreV2SnapshotProtocol.TYPE_RARE_WORLD_DELTA,
		_server_tick,
		_snapshot_seq,
		battle_state.static_world_revision,
		battle_state.battle_revision
	)
	metadata["rare_world_revision"] = battle_state.rare_world_revision
	_last_rare_world_revision_sent = battle_state.rare_world_revision
	emit_signal("snapshot_ready", CoreV2SnapshotBuilder.build_rare_world_delta_snapshot(battle_state, player_army_id, metadata))


func _emit_dynamic_battle_snapshot() -> void:
	_snapshot_seq += 1
	var metadata: Dictionary = CoreV2SnapshotProtocol.make_metadata(
		CoreV2SnapshotProtocol.TYPE_DYNAMIC_BATTLE_DELTA,
		_server_tick,
		_snapshot_seq,
		battle_state.static_world_revision,
		battle_state.battle_revision
	)
	metadata["pending_command_count"] = _pending_commands.size()
	emit_signal("snapshot_ready", CoreV2SnapshotBuilder.build_dynamic_battle_delta_snapshot(battle_state, player_army_id, metadata))
