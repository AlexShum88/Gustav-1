class_name TerrainRegion
extends RefCounted

var id: StringName
var display_name: String = ""
var polygon: PackedVector2Array = PackedVector2Array()
var terrain_type: int = SimTypes.TerrainType.PLAINS
var average_height: float = 0.0
var move_multiplier: float = 1.0
var defense_bonus: float = 0.0
var visibility_multiplier: float = 1.0
var has_road: bool = false


func contains(world_point: Vector2) -> bool:
	return Geometry2D.is_point_in_polygon(world_point, polygon)
