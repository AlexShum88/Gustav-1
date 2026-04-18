class_name FormationModel
extends RefCounted

var formation_type: int = SimTypes.FormationType.LINE
var frontage: float = 116.0
var depth: float = 70.0
var orientation: float = 0.0


func _init(
		initial_type: int = SimTypes.FormationType.LINE,
		initial_frontage: float = 116.0,
		initial_depth: float = 70.0,
		initial_orientation: float = 0.0
) -> void:
	formation_type = initial_type
	frontage = initial_frontage
	depth = initial_depth
	orientation = initial_orientation


func set_type(new_type: int) -> void:
	formation_type = new_type
	match formation_type:
		SimTypes.FormationType.COLUMN:
			frontage = 62.0
			depth = 136.0
		SimTypes.FormationType.SQUARE:
			frontage = 98.0
			depth = 98.0
		_:
			frontage = 116.0
			depth = 70.0


func get_speed_multiplier() -> float:
	match formation_type:
		SimTypes.FormationType.COLUMN:
			return 1.15
		SimTypes.FormationType.SQUARE:
			return 0.72
		_:
			return 1.0


func get_fire_multiplier() -> float:
	match formation_type:
		SimTypes.FormationType.COLUMN:
			return 0.7
		SimTypes.FormationType.SQUARE:
			return 0.85
		_:
			return 1.0


func build_polygon(center: Vector2) -> PackedVector2Array:
	var local_points := PackedVector2Array([
		Vector2(-frontage * 0.5, -depth * 0.5),
		Vector2(frontage * 0.5, -depth * 0.5),
		Vector2(frontage * 0.5, depth * 0.5),
		Vector2(-frontage * 0.5, depth * 0.5),
	])
	var result := PackedVector2Array()
	for point in local_points:
		result.append(center + point.rotated(orientation))
	return result


func build_subunit_polygons(center: Vector2, slot_count: int) -> Array:
	var local_centers: Array = build_subunit_local_centers(slot_count)
	return build_subunit_polygons_from_local_centers(center, local_centers)


func build_subunit_polygons_from_local_centers(center: Vector2, local_centers: Array) -> Array:
	var polygons: Array = []
	var effective_slot_count: int = max(1, local_centers.size())
	var layout: Vector2i = _get_subunit_layout(effective_slot_count)
	var columns: int = max(1, layout.x)
	var rows: int = max(1, layout.y)
	var gap: float = 10.0
	var usable_frontage: float = max(18.0, frontage - gap * float(columns + 1))
	var usable_depth: float = max(18.0, depth - gap * float(rows + 1))
	var cell_width: float = usable_frontage / float(columns)
	var cell_depth: float = usable_depth / float(rows)
	for slot_index in range(effective_slot_count):
		var cell_center: Vector2 = local_centers[slot_index]
		var block_width: float = cell_width * 0.88
		var block_depth: float = cell_depth * 0.88
		var local_points: PackedVector2Array = PackedVector2Array([
			Vector2(-block_width * 0.5, -block_depth * 0.5),
			Vector2(block_width * 0.5, -block_depth * 0.5),
			Vector2(block_width * 0.5, block_depth * 0.5),
			Vector2(-block_width * 0.5, block_depth * 0.5),
		])
		var polygon: PackedVector2Array = PackedVector2Array()
		for point in local_points:
			polygon.append(center + (cell_center + point).rotated(orientation))
		polygons.append(polygon)
	return polygons


func build_subunit_local_centers(slot_count: int) -> Array:
	var centers: Array = []
	var effective_slot_count: int = max(1, slot_count)
	var layout: Vector2i = _get_subunit_layout(effective_slot_count)
	var columns: int = max(1, layout.x)
	var rows: int = max(1, layout.y)
	var gap: float = 10.0
	var usable_frontage: float = max(18.0, frontage - gap * float(columns + 1))
	var usable_depth: float = max(18.0, depth - gap * float(rows + 1))
	var cell_width: float = usable_frontage / float(columns)
	var cell_depth: float = usable_depth / float(rows)
	for slot_index in range(effective_slot_count):
		var column: int = slot_index % columns
		var row: int = slot_index / columns
		if row >= rows:
			row = rows - 1
		var x: float = -frontage * 0.5 + gap + cell_width * (float(column) + 0.5) + gap * float(column)
		var y: float = -depth * 0.5 + gap + cell_depth * (float(row) + 0.5) + gap * float(row)
		centers.append(Vector2(x, y))
	return centers


func _get_subunit_layout(slot_count: int) -> Vector2i:
	match formation_type:
		SimTypes.FormationType.COLUMN:
			return Vector2i(1, slot_count)
		SimTypes.FormationType.SQUARE:
			return Vector2i(2, int(ceil(float(slot_count) / 2.0)))
		_:
			return Vector2i(slot_count, 1)
