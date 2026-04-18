class_name LastSeenMarker
extends RefCounted

var enemy_regiment_id: StringName = &""
var observer_army_id: StringName = &""
var position: Vector2 = Vector2.ZERO
var detail_level: int = SimTypes.IntelDetail.BROAD
var remaining_time: float = 14.0
var label: String = "Last seen"
