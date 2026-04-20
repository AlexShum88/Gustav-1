class_name CoreV2SnapshotProtocol
extends RefCounted


const SCHEMA_VERSION: int = 2
const TYPE_BOOTSTRAP_STATIC: String = "bootstrap_static"
const TYPE_RARE_WORLD_DELTA: String = "rare_world_delta"
const TYPE_DYNAMIC_BATTLE_DELTA: String = "dynamic_battle_delta"


static func make_metadata(
		snapshot_type: String,
		server_tick: int,
		snapshot_seq: int,
		world_revision: int,
		battle_revision: int
) -> Dictionary:
	return {
		"schema_version": SCHEMA_VERSION,
		"snapshot_type": snapshot_type,
		"server_tick": server_tick,
		"snapshot_seq": snapshot_seq,
		"world_revision": world_revision,
		"battle_revision": battle_revision,
	}


static func attach_metadata(payload: Dictionary, metadata: Dictionary) -> Dictionary:
	var result: Dictionary = payload.duplicate(true)
	for key_value in metadata.keys():
		result[key_value] = metadata[key_value]
	return result
