class_name CoreV2PendingCommandQueue
extends RefCounted


var _commands: Array = []
var _next_command_seq: int = 1


func enqueue(command: Dictionary, received_tick: int) -> Dictionary:
	var queued_command: Dictionary = command.duplicate(true)
	var command_seq: int = _next_command_seq
	_next_command_seq += 1
	queued_command["command_seq"] = command_seq
	queued_command["received_tick"] = received_tick
	_commands.append(queued_command)
	return {
		"accepted": true,
		"command_seq": command_seq,
		"received_tick": received_tick,
		"queued_count": _commands.size(),
	}


func drain() -> Array:
	var result: Array = _commands
	_commands = []
	return result


func size() -> int:
	return _commands.size()
