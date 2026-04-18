class_name TerrainGrid
extends RefCounted

var map_rect: Rect2 = Rect2()
var cell_size: float = 32.0
var width: int = 0
var height: int = 0
var _cells: Array = []
var _default_cell: TerrainCell = TerrainCell.new()


func build_from_regions(source_map_rect: Rect2, source_regions: Array, source_cell_size: float = 32.0) -> void:
	map_rect = source_map_rect
	cell_size = source_cell_size
	width = int(ceil(map_rect.size.x / cell_size))
	height = int(ceil(map_rect.size.y / cell_size))
	_cells.clear()
	_cells.resize(width * height)

	for y in range(height):
		for x in range(width):
			var world_position: Vector2 = map_rect.position + Vector2((float(x) + 0.5) * cell_size, (float(y) + 0.5) * cell_size)
			var cell: TerrainCell = _build_cell_for_position(world_position, source_regions)
			_cells[_to_index(x, y)] = cell


func get_cell_at(world_position: Vector2) -> TerrainCell:
	if width <= 0 or height <= 0:
		return _default_cell
	var clamped_position: Vector2 = Vector2(
		clamp(world_position.x, map_rect.position.x, map_rect.end.x - 0.001),
		clamp(world_position.y, map_rect.position.y, map_rect.end.y - 0.001)
	)
	var local_position: Vector2 = clamped_position - map_rect.position
	var x: int = clamp(int(floor(local_position.x / cell_size)), 0, width - 1)
	var y: int = clamp(int(floor(local_position.y / cell_size)), 0, height - 1)
	return _cells[_to_index(x, y)]


func _build_cell_for_position(world_position: Vector2, source_regions: Array) -> TerrainCell:
	var cell: TerrainCell = _default_cell.duplicate_cell()
	for region in source_regions:
		if region.contains(world_position):
			cell.copy_from_region(region)
	return cell


func _to_index(x: int, y: int) -> int:
	return y * width + x
