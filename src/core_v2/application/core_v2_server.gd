class_name CoreV2Server
extends Node


signal snapshot_ready(snapshot: Dictionary)

const DEFAULT_TICK_RATE: float = 12.0
const DEFAULT_SNAPSHOT_RATE: float = 8.0

var battle_state: CoreV2BattleState
var player_army_id: StringName = &"blue"
var _tick_interval: float = 1.0 / DEFAULT_TICK_RATE
var _snapshot_interval: float = 1.0 / DEFAULT_SNAPSHOT_RATE
var _tick_accumulator: float = 0.0
var _snapshot_accumulator: float = 0.0


func configure(next_state: CoreV2BattleState, next_player_army_id: StringName) -> void:
	battle_state = next_state
	player_army_id = next_player_army_id
	_tick_accumulator = 0.0
	_snapshot_accumulator = 0.0
	emit_signal("snapshot_ready", _build_snapshot())


func submit_client_command(command: Dictionary) -> void:
	if battle_state == null:
		return
	battle_state.process_command(command)
	emit_signal("snapshot_ready", _build_snapshot())


func _physics_process(delta: float) -> void:
	if battle_state == null:
		return
	_snapshot_accumulator += delta
	if battle_state.phase == CoreV2Types.BattlePhase.ACTIVE:
		# Симуляція тікає фіксованим кроком, щоб далі було легше детермінувати бій і мережу.
		_tick_accumulator += delta
		while _tick_accumulator >= _tick_interval:
			battle_state.advance(_tick_interval)
			_tick_accumulator -= _tick_interval
	if _snapshot_accumulator >= _snapshot_interval:
		_snapshot_accumulator = fmod(_snapshot_accumulator, _snapshot_interval)
		emit_signal("snapshot_ready", _build_snapshot())


func _build_snapshot() -> Dictionary:
	return CoreV2SnapshotBuilder.build_snapshot(battle_state, player_army_id)
