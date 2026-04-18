class_name TerrainCell
extends RefCounted

var terrain_type: int = SimTypes.TerrainType.PLAINS
var average_height: float = 0.0
var move_multiplier: float = 1.0
var defense_bonus: float = 0.0
var visibility_multiplier: float = 1.0
var has_road: bool = false


func copy_from_region(region: TerrainRegion) -> void:
	terrain_type = region.terrain_type
	average_height = region.average_height
	move_multiplier = region.move_multiplier
	defense_bonus = region.defense_bonus
	visibility_multiplier = region.visibility_multiplier
	has_road = region.has_road


func duplicate_cell() -> TerrainCell:
	var cell: TerrainCell = TerrainCell.new()
	cell.terrain_type = terrain_type
	cell.average_height = average_height
	cell.move_multiplier = move_multiplier
	cell.defense_bonus = defense_bonus
	cell.visibility_multiplier = visibility_multiplier
	cell.has_road = has_road
	return cell
