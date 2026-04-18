class_name BattleScenarioFactory
extends RefCounted

const TERRAIN_GRID_CELL_SIZE: float = 12.0
const STAND_HEADCOUNT: int = 50
const ArmyDefinition = preload("res://src/meta/army_editor/army_definition.gd")


static func create_phase_one_battle() -> BattleSimulation:
	var sim: BattleSimulation = BattleSimulation.new()
	sim.map_rect = Rect2(0.0, 0.0, 2800.0, 1800.0)

	_create_terrain(sim)
	_build_terrain_grid(sim)
	_create_armies(sim)
	_create_objectives(sim)
	return sim


static func create_large_test_battle(side_army_overrides = {}) -> BattleSimulation:
	var sim: BattleSimulation = BattleSimulation.new()
	sim.map_rect = Rect2(0.0, 0.0, 8400.0, 5400.0)
	var normalized_side_army_overrides: Dictionary = _normalize_large_side_army_overrides(side_army_overrides)

	_create_large_terrain(sim)
	_build_terrain_grid(sim)
	_create_large_armies(sim)
	for army_id in normalized_side_army_overrides.keys():
		_replace_large_side_army(sim, StringName(army_id), normalized_side_army_overrides[army_id])
	_create_large_objectives(sim)
	return sim


static func _create_terrain(sim: BattleSimulation) -> void:
	var plains: TerrainRegion = TerrainRegion.new()
	plains.id = &"terrain_plains"
	plains.display_name = "Open plain"
	plains.terrain_type = SimTypes.TerrainType.PLAINS
	plains.move_multiplier = 1.0
	plains.defense_bonus = 0.0
	plains.visibility_multiplier = 1.0
	plains.polygon = PackedVector2Array([
		Vector2(0.0, 0.0),
		Vector2(2800.0, 0.0),
		Vector2(2800.0, 1800.0),
		Vector2(0.0, 1800.0),
	])
	sim.terrain_regions.append(plains)

	var forest: TerrainRegion = TerrainRegion.new()
	forest.id = &"terrain_forest"
	forest.display_name = "North copse"
	forest.terrain_type = SimTypes.TerrainType.FOREST
	forest.move_multiplier = 0.72
	forest.defense_bonus = 0.08
	forest.visibility_multiplier = 0.7
	forest.average_height = 0.1
	forest.polygon = PackedVector2Array([
		Vector2(260.0, 180.0),
		Vector2(820.0, 210.0),
		Vector2(790.0, 560.0),
		Vector2(220.0, 510.0),
	])
	sim.terrain_regions.append(forest)

	var east_forest: TerrainRegion = TerrainRegion.new()
	east_forest.id = &"terrain_east_forest"
	east_forest.display_name = "East woodline"
	east_forest.terrain_type = SimTypes.TerrainType.FOREST
	east_forest.move_multiplier = 0.74
	east_forest.defense_bonus = 0.08
	east_forest.visibility_multiplier = 0.7
	east_forest.average_height = 0.08
	east_forest.polygon = PackedVector2Array([
		Vector2(1980.0, 1210.0),
		Vector2(2520.0, 1180.0),
		Vector2(2580.0, 1540.0),
		Vector2(1940.0, 1580.0),
	])
	sim.terrain_regions.append(east_forest)

	var swamp: TerrainRegion = TerrainRegion.new()
	swamp.id = &"terrain_swamp"
	swamp.display_name = "Southern marsh"
	swamp.terrain_type = SimTypes.TerrainType.SWAMP
	swamp.move_multiplier = 0.55
	swamp.defense_bonus = 0.02
	swamp.visibility_multiplier = 0.82
	swamp.average_height = -0.2
	swamp.polygon = PackedVector2Array([
		Vector2(1820.0, 1260.0),
		Vector2(2440.0, 1290.0),
		Vector2(2380.0, 1700.0),
		Vector2(1710.0, 1660.0),
	])
	sim.terrain_regions.append(swamp)

	var village: TerrainRegion = TerrainRegion.new()
	village.id = &"terrain_village"
	village.display_name = "Midden Village"
	village.terrain_type = SimTypes.TerrainType.VILLAGE
	village.move_multiplier = 0.82
	village.defense_bonus = 0.12
	village.visibility_multiplier = 0.76
	village.average_height = 0.05
	village.has_road = true
	village.polygon = PackedVector2Array([
		Vector2(1280.0, 720.0),
		Vector2(1640.0, 700.0),
		Vector2(1680.0, 1040.0),
		Vector2(1240.0, 1020.0),
	])
	sim.terrain_regions.append(village)

	var ridge: TerrainRegion = TerrainRegion.new()
	ridge.id = &"terrain_ridge"
	ridge.display_name = "Crossroads ridge"
	ridge.terrain_type = SimTypes.TerrainType.FARM
	ridge.move_multiplier = 0.93
	ridge.defense_bonus = 0.1
	ridge.visibility_multiplier = 1.05
	ridge.average_height = 0.35
	ridge.has_road = true
	ridge.polygon = PackedVector2Array([
		Vector2(780.0, 520.0),
		Vector2(2080.0, 470.0),
		Vector2(2240.0, 700.0),
		Vector2(860.0, 770.0),
	])
	sim.terrain_regions.append(ridge)

	var central_bushes: TerrainRegion = TerrainRegion.new()
	central_bushes.id = &"terrain_central_bushes"
	central_bushes.display_name = "Central hedges"
	central_bushes.terrain_type = SimTypes.TerrainType.BUSHES
	central_bushes.move_multiplier = 0.86
	central_bushes.defense_bonus = 0.06
	central_bushes.visibility_multiplier = 0.82
	central_bushes.average_height = 0.02
	central_bushes.polygon = PackedVector2Array([
		Vector2(970.0, 1110.0),
		Vector2(1480.0, 1080.0),
		Vector2(1520.0, 1350.0),
		Vector2(930.0, 1380.0),
	])
	sim.terrain_regions.append(central_bushes)


static func _create_large_terrain(sim: BattleSimulation) -> void:
	var plains: TerrainRegion = TerrainRegion.new()
	plains.id = &"terrain_large_plains"
	plains.display_name = "Open plain"
	plains.terrain_type = SimTypes.TerrainType.PLAINS
	plains.move_multiplier = 1.0
	plains.defense_bonus = 0.0
	plains.visibility_multiplier = 1.0
	plains.polygon = PackedVector2Array([
		Vector2(0.0, 0.0),
		Vector2(8400.0, 0.0),
		Vector2(8400.0, 5400.0),
		Vector2(0.0, 5400.0),
	])
	sim.terrain_regions.append(plains)

	var north_woods: TerrainRegion = TerrainRegion.new()
	north_woods.id = &"terrain_large_north_woods"
	north_woods.display_name = "Northern woods"
	north_woods.terrain_type = SimTypes.TerrainType.FOREST
	north_woods.move_multiplier = 0.72
	north_woods.defense_bonus = 0.08
	north_woods.visibility_multiplier = 0.68
	north_woods.average_height = 0.08
	north_woods.polygon = PackedVector2Array([
		Vector2(600.0, 380.0),
		Vector2(2560.0, 420.0),
		Vector2(2480.0, 1500.0),
		Vector2(520.0, 1420.0),
	])
	sim.terrain_regions.append(north_woods)

	var western_marsh: TerrainRegion = TerrainRegion.new()
	western_marsh.id = &"terrain_large_western_marsh"
	western_marsh.display_name = "Western marsh"
	western_marsh.terrain_type = SimTypes.TerrainType.SWAMP
	western_marsh.move_multiplier = 0.55
	western_marsh.defense_bonus = 0.02
	western_marsh.visibility_multiplier = 0.82
	western_marsh.average_height = -0.18
	western_marsh.polygon = PackedVector2Array([
		Vector2(420.0, 3160.0),
		Vector2(2020.0, 3040.0),
		Vector2(2140.0, 4700.0),
		Vector2(360.0, 4840.0),
	])
	sim.terrain_regions.append(western_marsh)

	var central_ridge: TerrainRegion = TerrainRegion.new()
	central_ridge.id = &"terrain_large_central_ridge"
	central_ridge.display_name = "Central ridge"
	central_ridge.terrain_type = SimTypes.TerrainType.FARM
	central_ridge.move_multiplier = 0.93
	central_ridge.defense_bonus = 0.1
	central_ridge.visibility_multiplier = 1.05
	central_ridge.average_height = 0.34
	central_ridge.has_road = true
	central_ridge.polygon = PackedVector2Array([
		Vector2(1960.0, 2140.0),
		Vector2(6720.0, 1860.0),
		Vector2(7060.0, 2500.0),
		Vector2(2280.0, 2860.0),
	])
	sim.terrain_regions.append(central_ridge)

	var central_hedges: TerrainRegion = TerrainRegion.new()
	central_hedges.id = &"terrain_large_central_hedges"
	central_hedges.display_name = "Central hedges"
	central_hedges.terrain_type = SimTypes.TerrainType.BUSHES
	central_hedges.move_multiplier = 0.86
	central_hedges.defense_bonus = 0.06
	central_hedges.visibility_multiplier = 0.8
	central_hedges.average_height = 0.02
	central_hedges.polygon = PackedVector2Array([
		Vector2(3180.0, 2820.0),
		Vector2(4840.0, 2700.0),
		Vector2(5120.0, 3620.0),
		Vector2(3040.0, 3780.0),
	])
	sim.terrain_regions.append(central_hedges)

	var south_bushes: TerrainRegion = TerrainRegion.new()
	south_bushes.id = &"terrain_large_south_bushes"
	south_bushes.display_name = "Southern scrub"
	south_bushes.terrain_type = SimTypes.TerrainType.BUSHES
	south_bushes.move_multiplier = 0.84
	south_bushes.defense_bonus = 0.05
	south_bushes.visibility_multiplier = 0.8
	south_bushes.average_height = 0.01
	south_bushes.polygon = PackedVector2Array([
		Vector2(5160.0, 3880.0),
		Vector2(7060.0, 3800.0),
		Vector2(7320.0, 5020.0),
		Vector2(5020.0, 5160.0),
	])
	sim.terrain_regions.append(south_bushes)

	var east_woodline: TerrainRegion = TerrainRegion.new()
	east_woodline.id = &"terrain_large_east_woodline"
	east_woodline.display_name = "Eastern woodline"
	east_woodline.terrain_type = SimTypes.TerrainType.FOREST
	east_woodline.move_multiplier = 0.74
	east_woodline.defense_bonus = 0.08
	east_woodline.visibility_multiplier = 0.7
	east_woodline.average_height = 0.07
	east_woodline.polygon = PackedVector2Array([
		Vector2(6540.0, 920.0),
		Vector2(8040.0, 980.0),
		Vector2(7920.0, 2580.0),
		Vector2(6380.0, 2480.0),
	])
	sim.terrain_regions.append(east_woodline)

	var east_village: TerrainRegion = TerrainRegion.new()
	east_village.id = &"terrain_large_east_village"
	east_village.display_name = "East hamlet belt"
	east_village.terrain_type = SimTypes.TerrainType.VILLAGE
	east_village.move_multiplier = 0.82
	east_village.defense_bonus = 0.12
	east_village.visibility_multiplier = 0.76
	east_village.average_height = 0.05
	east_village.has_road = true
	east_village.polygon = PackedVector2Array([
		Vector2(5660.0, 2560.0),
		Vector2(7060.0, 2480.0),
		Vector2(7220.0, 3400.0),
		Vector2(5540.0, 3500.0),
	])
	sim.terrain_regions.append(east_village)

	var south_farms: TerrainRegion = TerrainRegion.new()
	south_farms.id = &"terrain_large_south_farms"
	south_farms.display_name = "Southern farms"
	south_farms.terrain_type = SimTypes.TerrainType.FARM
	south_farms.move_multiplier = 0.95
	south_farms.defense_bonus = 0.04
	south_farms.visibility_multiplier = 0.96
	south_farms.average_height = 0.03
	south_farms.has_road = true
	south_farms.polygon = PackedVector2Array([
		Vector2(2380.0, 3880.0),
		Vector2(4540.0, 3760.0),
		Vector2(4700.0, 4980.0),
		Vector2(2260.0, 5060.0),
	])
	sim.terrain_regions.append(south_farms)


static func _build_terrain_grid(sim: BattleSimulation) -> void:
	var grid: TerrainGrid = TerrainGrid.new()
	grid.build_from_regions(sim.map_rect, sim.terrain_regions, TERRAIN_GRID_CELL_SIZE)
	sim.terrain_grid = grid


static func _create_armies(sim: BattleSimulation) -> void:
	var blue: Army = Army.new(&"blue", "Blue Army")
	var red: Army = Army.new(&"red", "Red Army")
	blue.is_ai_controlled = false
	red.is_ai_controlled = true
	sim.armies[blue.id] = blue
	sim.armies[red.id] = red
	sim.visible_enemy_ids_by_army[blue.id] = {}
	sim.visible_enemy_ids_by_army[red.id] = {}
	sim.last_seen_markers_by_army[blue.id] = {}
	sim.last_seen_markers_by_army[red.id] = {}

	_create_army_package(
		sim,
		blue,
		Vector2(220.0, 1340.0),
		Vector2(130.0, 1600.0),
		[
			{
				"id": "blue_line",
				"name": "1st Line Brigade",
				"hq_pos": Vector2(480.0, 1210.0),
				"regiments": [
					_make_regiment_template("Blue Forward I", SimTypes.UnitCategory.INFANTRY, Vector2(390.0, 1140.0), 0.72),
					_make_regiment_template("Blue Forward II", SimTypes.UnitCategory.INFANTRY, Vector2(485.0, 1160.0), 0.7),
					_make_regiment_template("Blue Forward III", SimTypes.UnitCategory.INFANTRY, Vector2(575.0, 1145.0), 0.69),
					_make_regiment_template("Blue Reserve I", SimTypes.UnitCategory.INFANTRY, Vector2(420.0, 1265.0), 0.68),
					_make_regiment_template("Blue Reserve II", SimTypes.UnitCategory.INFANTRY, Vector2(540.0, 1285.0), 0.67),
					_make_regiment_template("Blue Grand Battery", SimTypes.UnitCategory.ARTILLERY, Vector2(495.0, 1370.0), 0.76),
				],
			},
			{
				"id": "blue_mixed",
				"name": "2nd Mixed Brigade",
				"hq_pos": Vector2(600.0, 1480.0),
				"regiments": [
					_make_regiment_template("Blue Fusiliers", SimTypes.UnitCategory.INFANTRY, Vector2(520.0, 1415.0), 0.74),
					_make_regiment_template("Blue Shot Battalion", SimTypes.UnitCategory.INFANTRY, Vector2(615.0, 1430.0), 0.71),
					_make_regiment_template("Blue Guard Horse", SimTypes.UnitCategory.CAVALRY, Vector2(700.0, 1445.0), 0.82),
					_make_regiment_template("Blue Cuirassiers", SimTypes.UnitCategory.CAVALRY, Vector2(760.0, 1510.0), 0.79),
					_make_regiment_template("Blue Rear Foot", SimTypes.UnitCategory.INFANTRY, Vector2(565.0, 1545.0), 0.7),
				],
			},
			{
				"id": "blue_light",
				"name": "3rd Light Brigade",
				"hq_pos": Vector2(350.0, 1010.0),
				"regiments": [
					_make_regiment_template("Blue Left Foot", SimTypes.UnitCategory.INFANTRY, Vector2(275.0, 950.0), 0.68),
					_make_regiment_template("Blue Center Foot", SimTypes.UnitCategory.INFANTRY, Vector2(360.0, 970.0), 0.69),
					_make_regiment_template("Blue Right Foot", SimTypes.UnitCategory.INFANTRY, Vector2(450.0, 950.0), 0.68),
					_make_regiment_template("Blue Light Horse", SimTypes.UnitCategory.CAVALRY, Vector2(395.0, 1060.0), 0.72),
				],
			},
			{
				"id": "blue_tercio",
				"name": "4th Tercio Brigade",
				"hq_pos": Vector2(1010.0, 1555.0),
				"regiments": [
					_make_regiment_template(
						"Blue Spanish Tercio",
						SimTypes.UnitCategory.INFANTRY,
						Vector2(980.0, 1450.0),
						0.78,
						_make_spanish_tercio_company_templates(),
						{
							"commander_profile_id": &"tercio_maestre",
							"commander_name": "Blue Maestre de Campo",
							"banner_profile_id": &"tercio_colors",
						}
					),
				],
			},
		]
	)


static func _create_large_armies(sim: BattleSimulation) -> void:
	var blue: Army = Army.new(&"blue", "Blue Army")
	var red: Army = Army.new(&"red", "Red Army")
	blue.is_ai_controlled = false
	red.is_ai_controlled = true
	sim.armies[blue.id] = blue
	sim.armies[red.id] = red
	sim.visible_enemy_ids_by_army[blue.id] = {}
	sim.visible_enemy_ids_by_army[red.id] = {}
	sim.last_seen_markers_by_army[blue.id] = {}
	sim.last_seen_markers_by_army[red.id] = {}

	_create_army_package(
		sim,
		blue,
		Vector2(640.0, 4240.0),
		Vector2(260.0, 4920.0),
		[
			{
				"id": "blue_line",
				"name": "1st Line Brigade",
				"hq_pos": Vector2(1220.0, 3920.0),
				"regiments": [
					_make_regiment_template("Blue Forward I", SimTypes.UnitCategory.INFANTRY, Vector2(1020.0, 3780.0), 0.72),
					_make_regiment_template("Blue Forward II", SimTypes.UnitCategory.INFANTRY, Vector2(1220.0, 3810.0), 0.7),
					_make_regiment_template("Blue Forward III", SimTypes.UnitCategory.INFANTRY, Vector2(1430.0, 3790.0), 0.69),
					_make_regiment_template("Blue Reserve I", SimTypes.UnitCategory.INFANTRY, Vector2(1110.0, 4060.0), 0.68),
					_make_regiment_template("Blue Reserve II", SimTypes.UnitCategory.INFANTRY, Vector2(1370.0, 4090.0), 0.67),
					_make_regiment_template("Blue Grand Battery", SimTypes.UnitCategory.ARTILLERY, Vector2(1250.0, 4340.0), 0.76),
				],
			},
			{
				"id": "blue_mixed",
				"name": "2nd Mixed Brigade",
				"hq_pos": Vector2(1840.0, 4460.0),
				"regiments": [
					_make_regiment_template("Blue Fusiliers", SimTypes.UnitCategory.INFANTRY, Vector2(1680.0, 4340.0), 0.74),
					_make_regiment_template("Blue Shot Battalion", SimTypes.UnitCategory.INFANTRY, Vector2(1870.0, 4370.0), 0.71),
					_make_regiment_template("Blue Guard Horse", SimTypes.UnitCategory.CAVALRY, Vector2(2050.0, 4290.0), 0.82),
					_make_regiment_template("Blue Cuirassiers", SimTypes.UnitCategory.CAVALRY, Vector2(2220.0, 4510.0), 0.79),
					_make_regiment_template("Blue Rear Foot", SimTypes.UnitCategory.INFANTRY, Vector2(1840.0, 4610.0), 0.7),
				],
			},
			{
				"id": "blue_light",
				"name": "3rd Light Brigade",
				"hq_pos": Vector2(820.0, 3260.0),
				"regiments": [
					_make_regiment_template("Blue Left Foot", SimTypes.UnitCategory.INFANTRY, Vector2(640.0, 3140.0), 0.68),
					_make_regiment_template("Blue Center Foot", SimTypes.UnitCategory.INFANTRY, Vector2(830.0, 3180.0), 0.69),
					_make_regiment_template("Blue Right Foot", SimTypes.UnitCategory.INFANTRY, Vector2(1010.0, 3140.0), 0.68),
					_make_regiment_template("Blue Light Horse", SimTypes.UnitCategory.CAVALRY, Vector2(900.0, 3360.0), 0.72),
				],
			},
			{
				"id": "blue_tercio",
				"name": "4th Tercio Brigade",
				"hq_pos": Vector2(2840.0, 4660.0),
				"regiments": [
					_make_regiment_template(
						"Blue Spanish Tercio",
						SimTypes.UnitCategory.INFANTRY,
						Vector2(2740.0, 4520.0),
						0.78,
						_make_spanish_tercio_company_templates(),
						{
							"commander_profile_id": &"tercio_maestre",
							"commander_name": "Blue Maestre de Campo",
							"banner_profile_id": &"tercio_colors",
						}
					),
				],
			},
		]
	)

	_create_army_package(
		sim,
		red,
		Vector2(7720.0, 1180.0),
		Vector2(8100.0, 540.0),
		[
			{
				"id": "red_line",
				"name": "Scarlet Line Brigade",
				"hq_pos": Vector2(7140.0, 1520.0),
				"regiments": [
					_make_regiment_template("Scarlet Forward I", SimTypes.UnitCategory.INFANTRY, Vector2(6960.0, 1380.0), 0.73),
					_make_regiment_template("Scarlet Forward II", SimTypes.UnitCategory.INFANTRY, Vector2(7150.0, 1400.0), 0.71),
					_make_regiment_template("Scarlet Forward III", SimTypes.UnitCategory.INFANTRY, Vector2(7340.0, 1380.0), 0.7),
					_make_regiment_template("Scarlet Reserve I", SimTypes.UnitCategory.INFANTRY, Vector2(7040.0, 1650.0), 0.69),
					_make_regiment_template("Scarlet Reserve II", SimTypes.UnitCategory.INFANTRY, Vector2(7290.0, 1670.0), 0.68),
					_make_regiment_template("Scarlet Grand Battery", SimTypes.UnitCategory.ARTILLERY, Vector2(7170.0, 1900.0), 0.72),
				],
			},
			{
				"id": "red_mixed",
				"name": "Scarlet Mixed Brigade",
				"hq_pos": Vector2(6480.0, 1040.0),
				"regiments": [
					_make_regiment_template("Scarlet Fusiliers", SimTypes.UnitCategory.INFANTRY, Vector2(6320.0, 920.0), 0.75),
					_make_regiment_template("Scarlet Shot Battalion", SimTypes.UnitCategory.INFANTRY, Vector2(6500.0, 950.0), 0.72),
					_make_regiment_template("Scarlet Horse", SimTypes.UnitCategory.CAVALRY, Vector2(6690.0, 900.0), 0.73),
					_make_regiment_template("Scarlet Cuirassiers", SimTypes.UnitCategory.CAVALRY, Vector2(6840.0, 1140.0), 0.78),
					_make_regiment_template("Scarlet Rear Foot", SimTypes.UnitCategory.INFANTRY, Vector2(6470.0, 1240.0), 0.71),
				],
			},
			{
				"id": "red_light",
				"name": "Scarlet Light Brigade",
				"hq_pos": Vector2(7440.0, 2360.0),
				"regiments": [
					_make_regiment_template("Scarlet Left Foot", SimTypes.UnitCategory.INFANTRY, Vector2(7260.0, 2240.0), 0.69),
					_make_regiment_template("Scarlet Center Foot", SimTypes.UnitCategory.INFANTRY, Vector2(7450.0, 2270.0), 0.68),
					_make_regiment_template("Scarlet Right Foot", SimTypes.UnitCategory.INFANTRY, Vector2(7630.0, 2240.0), 0.69),
					_make_regiment_template("Scarlet Light Horse", SimTypes.UnitCategory.CAVALRY, Vector2(7510.0, 2460.0), 0.72),
				],
			},
		]
	)

	_create_army_package(
		sim,
		red,
		Vector2(2580.0, 430.0),
		Vector2(2680.0, 180.0),
		[
			{
				"id": "red_line",
				"name": "Scarlet Line Brigade",
				"hq_pos": Vector2(2310.0, 560.0),
				"regiments": [
					_make_regiment_template("Scarlet Forward I", SimTypes.UnitCategory.INFANTRY, Vector2(2220.0, 500.0), 0.73),
					_make_regiment_template("Scarlet Forward II", SimTypes.UnitCategory.INFANTRY, Vector2(2310.0, 515.0), 0.71),
					_make_regiment_template("Scarlet Forward III", SimTypes.UnitCategory.INFANTRY, Vector2(2405.0, 500.0), 0.7),
					_make_regiment_template("Scarlet Reserve I", SimTypes.UnitCategory.INFANTRY, Vector2(2250.0, 625.0), 0.69),
					_make_regiment_template("Scarlet Reserve II", SimTypes.UnitCategory.INFANTRY, Vector2(2370.0, 640.0), 0.68),
					_make_regiment_template("Scarlet Grand Battery", SimTypes.UnitCategory.ARTILLERY, Vector2(2315.0, 735.0), 0.72),
				],
			},
			{
				"id": "red_mixed",
				"name": "Scarlet Mixed Brigade",
				"hq_pos": Vector2(2210.0, 330.0),
				"regiments": [
					_make_regiment_template("Scarlet Fusiliers", SimTypes.UnitCategory.INFANTRY, Vector2(2135.0, 270.0), 0.75),
					_make_regiment_template("Scarlet Shot Battalion", SimTypes.UnitCategory.INFANTRY, Vector2(2225.0, 285.0), 0.72),
					_make_regiment_template("Scarlet Horse", SimTypes.UnitCategory.CAVALRY, Vector2(2315.0, 295.0), 0.73),
					_make_regiment_template("Scarlet Cuirassiers", SimTypes.UnitCategory.CAVALRY, Vector2(2380.0, 355.0), 0.78),
					_make_regiment_template("Scarlet Rear Foot", SimTypes.UnitCategory.INFANTRY, Vector2(2180.0, 390.0), 0.71),
				],
			},
			{
				"id": "red_light",
				"name": "Scarlet Light Brigade",
				"hq_pos": Vector2(2480.0, 820.0),
				"regiments": [
					_make_regiment_template("Scarlet Left Foot", SimTypes.UnitCategory.INFANTRY, Vector2(2400.0, 760.0), 0.69),
					_make_regiment_template("Scarlet Center Foot", SimTypes.UnitCategory.INFANTRY, Vector2(2485.0, 780.0), 0.68),
					_make_regiment_template("Scarlet Right Foot", SimTypes.UnitCategory.INFANTRY, Vector2(2575.0, 760.0), 0.69),
					_make_regiment_template("Scarlet Light Horse", SimTypes.UnitCategory.CAVALRY, Vector2(2520.0, 875.0), 0.72),
				],
			},
		]
	)


static func _create_army_package(
		sim: BattleSimulation,
		army: Army,
		commander_pos: Vector2,
		baggage_pos: Vector2,
		brigade_templates: Array
) -> void:
	var commander_hq := HQ.new(StringName("%s_commander_hq" % army.id), "%s Headquarters" % army.display_name, army.id, commander_pos)
	commander_hq.role = "commander"
	commander_hq.command_radius = 180.0
	commander_hq.mobility = 36.0
	sim.hqs[commander_hq.id] = commander_hq

	var baggage_hq := HQ.new(StringName("%s_baggage_hq" % army.id), "%s Baggage Train" % army.display_name, army.id, baggage_pos)
	baggage_hq.role = "baggage"
	baggage_hq.command_radius = 90.0
	baggage_hq.mobility = 20.0
	baggage_hq.supply_stock = 1.0
	baggage_hq.ammo_stock = 1.0
	sim.hqs[baggage_hq.id] = baggage_hq
	army.baggage_hq_id = baggage_hq.id

	var commander := Commander.new(StringName("%s_commander" % army.id), "%s Commander" % army.display_name, army.id, commander_hq.id)
	sim.commanders[commander.id] = commander
	army.commander_id = commander.id

	for brigade_template in brigade_templates:
		var brigade_hq := HQ.new(
			StringName("%s_hq" % brigade_template["id"]),
			"%s HQ" % brigade_template["name"],
			army.id,
			brigade_template["hq_pos"]
		)
		brigade_hq.role = "brigade"
		brigade_hq.command_radius = 128.0
		sim.hqs[brigade_hq.id] = brigade_hq

		var brigade := Brigade.new(
			StringName(brigade_template["id"]),
			brigade_template["name"],
			army.id,
			StringName("%s_general" % brigade_template["id"]),
			brigade_hq.id
		)
		brigade.current_order_type = SimTypes.OrderType.HOLD
		sim.brigades[brigade.id] = brigade
		army.brigade_ids.append(brigade.id)

		var general := General.new(
			brigade.general_id,
			"%s General" % brigade.display_name,
			army.id,
			brigade_hq.id,
			brigade.id
		)
		general.aggression = 0.58 if army.is_ai_controlled else 0.0
		general.caution = 0.52 if army.is_ai_controlled else 0.35
		general.decision_interval_seconds = 5.0 if army.is_ai_controlled else 9999.0
		sim.generals[general.id] = general
		army.general_ids.append(general.id)

		for regiment_template in brigade_template["regiments"]:
			var regiment := _create_regiment(
				StringName("%s_%s" % [brigade.id, String(regiment_template["name"]).to_snake_case()]),
				regiment_template["name"],
				army.id,
				brigade.id,
				regiment_template["category"],
				regiment_template["position"],
				regiment_template["training"],
				regiment_template.get("company_templates", []),
				StringName(regiment_template.get("commander_profile_id", _get_default_command_profile_id(int(regiment_template["category"]), regiment_template.get("company_templates", []).size()))),
				String(regiment_template.get("commander_name", "%s Major" % regiment_template["name"])),
				StringName(regiment_template.get("banner_profile_id", _get_default_banner_profile_id(int(regiment_template["category"]))))
			)
			regiment.current_target_position = regiment.position
			sim.regiments[regiment.id] = regiment
			brigade.regiment_ids.append(regiment.id)


static func _create_objectives(sim: BattleSimulation) -> void:
	var crossroads := StrategicPoint.new(&"sp_crossroads", "Crossroads", &"", Vector2(1460.0, 830.0))
	crossroads.radius = 120.0
	crossroads.victory_rate_per_second = 0.65
	sim.strategic_points[crossroads.id] = crossroads

	var orchard := StrategicPoint.new(&"sp_orchard", "North Orchard", &"", Vector2(960.0, 560.0))
	orchard.radius = 88.0
	orchard.victory_rate_per_second = 0.48
	sim.strategic_points[orchard.id] = orchard

	var ford := StrategicPoint.new(&"sp_ford", "South Ford", &"", Vector2(1910.0, 1410.0))
	ford.radius = 90.0
	ford.victory_rate_per_second = 0.48
	sim.strategic_points[ford.id] = ford

	var east_hamlet := StrategicPoint.new(&"sp_east_hamlet", "East Hamlet", &"", Vector2(2060.0, 980.0))
	east_hamlet.radius = 84.0
	east_hamlet.victory_rate_per_second = 0.44
	sim.strategic_points[east_hamlet.id] = east_hamlet


static func _create_large_objectives(sim: BattleSimulation) -> void:
	var crossroads := StrategicPoint.new(&"sp_grand_crossroads", "Grand Crossroads", &"", Vector2(4140.0, 2620.0))
	crossroads.radius = 180.0
	crossroads.victory_rate_per_second = 0.72
	sim.strategic_points[crossroads.id] = crossroads

	var north_orchard := StrategicPoint.new(&"sp_north_orchard", "North Orchard", &"", Vector2(2820.0, 1480.0))
	north_orchard.radius = 130.0
	north_orchard.victory_rate_per_second = 0.5
	sim.strategic_points[north_orchard.id] = north_orchard

	var ridge_ford := StrategicPoint.new(&"sp_ridge_ford", "Ridge Ford", &"", Vector2(5920.0, 2280.0))
	ridge_ford.radius = 130.0
	ridge_ford.victory_rate_per_second = 0.52
	sim.strategic_points[ridge_ford.id] = ridge_ford

	var west_marsh := StrategicPoint.new(&"sp_west_marsh", "West Causeway", &"", Vector2(1700.0, 3880.0))
	west_marsh.radius = 120.0
	west_marsh.victory_rate_per_second = 0.48
	sim.strategic_points[west_marsh.id] = west_marsh

	var east_hamlet := StrategicPoint.new(&"sp_east_hamlet_large", "East Hamlet", &"", Vector2(6660.0, 3060.0))
	east_hamlet.radius = 125.0
	east_hamlet.victory_rate_per_second = 0.5
	sim.strategic_points[east_hamlet.id] = east_hamlet

	var southern_farms := StrategicPoint.new(&"sp_south_farms", "South Farms", &"", Vector2(3600.0, 4420.0))
	southern_farms.radius = 135.0
	southern_farms.victory_rate_per_second = 0.46
	sim.strategic_points[southern_farms.id] = southern_farms

	var eastern_woodline := StrategicPoint.new(&"sp_eastern_woodline", "East Woodline", &"", Vector2(7180.0, 1820.0))
	eastern_woodline.radius = 120.0
	eastern_woodline.victory_rate_per_second = 0.46
	sim.strategic_points[eastern_woodline.id] = eastern_woodline


static func _create_regiment(
		regiment_id: StringName,
		display_name: String,
		army_id: StringName,
		brigade_id: StringName,
		category: int,
		position: Vector2,
		training: float,
		company_templates: Array = [],
		commander_profile_id: StringName = &"",
		commander_name: String = "",
		banner_profile_id: StringName = &""
) -> Battalion:
	var battalion := Battalion.new(regiment_id, display_name, army_id, position)
	battalion.brigade_id = brigade_id
	battalion.category = category
	battalion.base_commander_quality = training
	battalion.commander_quality = training
	battalion.behavior_doctrine_id = _get_default_behavior_doctrine_for_category(category)
	battalion.base_speed = 52.0 if category == SimTypes.UnitCategory.CAVALRY else 42.0
	battalion.base_speed = 32.0 if category == SimTypes.UnitCategory.ARTILLERY else battalion.base_speed
	battalion.formation = FormationModel.new(SimTypes.FormationType.LINE)
	battalion.commander_name = commander_name
	battalion.set_commander_identity(
		commander_name,
		commander_profile_id if commander_profile_id != &"" else _get_default_command_profile_id(category, company_templates.size())
	)
	battalion.set_banner_identity(
		banner_profile_id if banner_profile_id != &"" else _get_default_banner_profile_id(category)
	)
	battalion.stands = _create_stands_for_category(battalion.id, category, training, company_templates)
	battalion.initialize_company_positions()
	battalion.initial_strength = battalion.get_total_strength()
	battalion.initialize_regiment_combat_state()
	return battalion


static func _create_stands_for_category(regiment_id: StringName, category: int, training: float, company_templates: Array = []) -> Array:
	var result: Array = []
	var source_templates: Array = company_templates
	if source_templates.is_empty():
		source_templates = _build_default_editor_company_templates_for_category(category)
	for company_index in range(source_templates.size()):
		var template: Dictionary = source_templates[company_index]
		result.append_array(_expand_company_template_to_stands(regiment_id, category, training, template, company_index))
	return result


static func _create_companies_for_category(regiment_id: StringName, category: int, training: float, company_templates: Array = []) -> Array:
	return _create_stands_for_category(regiment_id, category, training, company_templates)


static func _expand_company_template_to_stands(
		regiment_id: StringName,
		category: int,
		training: float,
		template: Dictionary,
		company_index: int
) -> Array:
	var result: Array = []
	var editor_company_tag: StringName = StringName("%s_company_template_%02d" % [String(regiment_id), company_index + 1])
	var template_name: String = String(template.get("name", "Company %d" % [company_index + 1]))
	var company_type: int = int(template.get("company_type", SimTypes.CompanyType.MUSKETEERS))
	var weapon_type: String = String(template.get("weapon_type", "musket"))
	var requested_soldiers: int = max(1, int(template.get("soldiers", STAND_HEADCOUNT)))
	var stand_count: int = max(1, int(ceil(float(requested_soldiers) / float(STAND_HEADCOUNT))))
	var remaining_soldiers: int = requested_soldiers
	for stand_index in range(stand_count):
		var stand_soldiers: int = min(STAND_HEADCOUNT, remaining_soldiers)
		if stand_index == stand_count - 1:
			stand_soldiers = max(1, remaining_soldiers)
		var stand: CombatStand = CombatStand.new(
			StringName("%s_stand_%02d_%02d" % [String(regiment_id), company_index + 1, stand_index + 1]),
			"%s Stand %d" % [template_name, stand_index + 1],
			company_type,
			category,
			weapon_type,
			stand_soldiers,
			training
		)
		stand.editor_company_tag = editor_company_tag
		stand.editor_company_name = template_name
		stand.home_segment = _resolve_stand_home_segment(company_type, stand_index, stand_count)
		result.append(stand)
		remaining_soldiers = max(0, remaining_soldiers - stand_soldiers)
	return result


static func _resolve_stand_home_segment(company_type: int, stand_index: int, stand_count: int) -> StringName:
	if company_type == SimTypes.CompanyType.ARTILLERY:
		return &"battery"
	if stand_count <= 1:
		return &"center"
	var ratio: float = float(stand_index) / float(max(1, stand_count - 1))
	if ratio <= 0.25:
		return &"left"
	if ratio >= 0.75:
		return &"right"
	if company_type == SimTypes.CompanyType.PIKEMEN:
		return &"core"
	return &"center"


static func _build_default_editor_company_templates_for_category(category: int) -> Array:
	match category:
		SimTypes.UnitCategory.CAVALRY:
			return [
				_make_company_template("1st Squadron", SimTypes.CompanyType.CAVALRY, "carbine", 150),
				_make_company_template("2nd Squadron", SimTypes.CompanyType.CAVALRY, "pistol", 150),
				_make_company_template("3rd Squadron", SimTypes.CompanyType.CAVALRY, "pistol", 150),
				_make_company_template("4th Squadron", SimTypes.CompanyType.CAVALRY, "carbine", 150),
			]
		SimTypes.UnitCategory.ARTILLERY:
			return [
				_make_company_template("Battery Section A", SimTypes.CompanyType.ARTILLERY, "cannon", 100),
				_make_company_template("Battery Section B", SimTypes.CompanyType.ARTILLERY, "cannon", 100),
				_make_company_template("Battery Section C", SimTypes.CompanyType.ARTILLERY, "cannon", 100),
				_make_company_template("Battery Section D", SimTypes.CompanyType.ARTILLERY, "cannon", 100),
			]
		_:
			return [
				_make_company_template("1st Musketeer Company", SimTypes.CompanyType.MUSKETEERS, "musket", 200),
				_make_company_template("2nd Musketeer Company", SimTypes.CompanyType.MUSKETEERS, "musket", 200),
				_make_company_template("1st Pike Company", SimTypes.CompanyType.PIKEMEN, "pike", 200),
				_make_company_template("2nd Pike Company", SimTypes.CompanyType.PIKEMEN, "pike", 200),
			]


static func _make_regiment_template(name_text: String, category: int, position: Vector2, training: float, company_templates: Array = [], options: Dictionary = {}) -> Dictionary:
	var template: Dictionary = {
		"name": name_text,
		"category": category,
		"position": position,
		"training": training,
	}
	if not company_templates.is_empty():
		template["company_templates"] = company_templates
	for option_key in options.keys():
		template[option_key] = options[option_key]
	return template


static func _make_company_template(name_text: String, company_type: int, weapon_type: String, soldiers: int) -> Dictionary:
	return {
		"name": name_text,
		"company_type": company_type,
		"weapon_type": weapon_type,
		"soldiers": soldiers,
	}


static func _make_spanish_tercio_company_templates() -> Array:
	return [
		_make_company_template("1st Musketeer Company", SimTypes.CompanyType.MUSKETEERS, "musket", 200),
		_make_company_template("2nd Musketeer Company", SimTypes.CompanyType.MUSKETEERS, "musket", 200),
		_make_company_template("3rd Musketeer Company", SimTypes.CompanyType.MUSKETEERS, "musket", 200),
		_make_company_template("4th Musketeer Company", SimTypes.CompanyType.MUSKETEERS, "musket", 200),
		_make_company_template("1st Pike Company", SimTypes.CompanyType.PIKEMEN, "pike", 200),
		_make_company_template("2nd Pike Company", SimTypes.CompanyType.PIKEMEN, "pike", 200),
		_make_company_template("3rd Pike Company", SimTypes.CompanyType.PIKEMEN, "pike", 200),
		_make_company_template("4th Pike Company", SimTypes.CompanyType.PIKEMEN, "pike", 200),
	]


static func _normalize_large_side_army_overrides(side_army_overrides) -> Dictionary:
	var normalized: Dictionary = {}
	if side_army_overrides == null:
		return normalized
	if side_army_overrides is Dictionary:
		for side_key in side_army_overrides.keys():
			var army_definition = side_army_overrides[side_key]
			if army_definition is ArmyDefinition:
				normalized[StringName(side_key)] = army_definition
		return normalized
	if side_army_overrides is ArmyDefinition:
		normalized[&"blue"] = side_army_overrides
	return normalized


static func _replace_large_side_army(sim: BattleSimulation, army_id: StringName, army_definition: ArmyDefinition) -> void:
	var side_config: Dictionary = _get_large_side_override_config(army_id)
	if side_config.is_empty():
		return
	var existing_army = sim.armies.get(army_id, null)
	var is_ai_controlled: bool = army_id != &"blue"
	if existing_army != null:
		is_ai_controlled = bool(existing_army.is_ai_controlled)
	_remove_army_package(sim, army_id)
	var army: Army = Army.new(army_id, army_definition.display_name)
	army.is_ai_controlled = is_ai_controlled
	sim.armies[army.id] = army
	sim.visible_enemy_ids_by_army[army.id] = {}
	sim.last_seen_markers_by_army[army.id] = {}
	_create_army_package(
		sim,
		army,
		side_config.get("commander_pos", Vector2.ZERO),
		side_config.get("baggage_pos", Vector2.ZERO),
		_build_large_side_brigade_templates(army_definition, side_config)
	)


static func _remove_army_package(sim: BattleSimulation, army_id: StringName) -> void:
	sim.armies.erase(army_id)
	sim.visible_enemy_ids_by_army.erase(army_id)
	sim.last_seen_markers_by_army.erase(army_id)
	for regiment_id in sim.regiments.keys():
		var regiment: Battalion = sim.regiments[regiment_id]
		if regiment.army_id == army_id:
			sim.regiments.erase(regiment_id)
	for brigade_id in sim.brigades.keys():
		var brigade: Brigade = sim.brigades[brigade_id]
		if brigade.army_id == army_id:
			sim.brigades.erase(brigade_id)
	for general_id in sim.generals.keys():
		var general: General = sim.generals[general_id]
		if general.army_id == army_id:
			sim.generals.erase(general_id)
	for commander_id in sim.commanders.keys():
		var commander: Commander = sim.commanders[commander_id]
		if commander.army_id == army_id:
			sim.commanders.erase(commander_id)
	for hq_id in sim.hqs.keys():
		var hq: HQ = sim.hqs[hq_id]
		if hq.army_id == army_id:
			sim.hqs.erase(hq_id)


static func _build_large_side_brigade_templates(army_definition: ArmyDefinition, side_config: Dictionary) -> Array:
	var result: Array = []
	var grouped_brigades: Dictionary = {}
	for brigade_def_value in army_definition.brigades:
		var role_key: int = int(brigade_def_value.deployment_role)
		if not grouped_brigades.has(role_key):
			grouped_brigades[role_key] = []
		grouped_brigades[role_key].append(brigade_def_value)

	var role_order: Array = [
		SimTypes.BrigadeDeploymentRole.VANGUARD,
		SimTypes.BrigadeDeploymentRole.LEFT_WING,
		SimTypes.BrigadeDeploymentRole.CENTER,
		SimTypes.BrigadeDeploymentRole.RIGHT_WING,
		SimTypes.BrigadeDeploymentRole.SECOND_LINE,
		SimTypes.BrigadeDeploymentRole.RESERVE,
	]
	for role_value in role_order:
		var brigades_for_role: Array = grouped_brigades.get(role_value, [])
		if brigades_for_role.is_empty():
			continue
		for role_index in range(brigades_for_role.size()):
			var brigade_def = brigades_for_role[role_index]
			var brigade_origin: Vector2 = _get_large_side_brigade_origin_for_role(side_config, int(role_value), role_index, brigades_for_role.size())
			result.append({
				"id": String(brigade_def.id),
				"name": brigade_def.display_name,
				"hq_pos": brigade_origin + Vector2(0.0, 170.0),
				"regiments": _build_large_side_regiment_templates(brigade_def.regiments, brigade_origin, side_config),
			})
	return result


static func _build_large_side_regiment_templates(regiments: Array, brigade_origin: Vector2, side_config: Dictionary) -> Array:
	var templates: Array = []
	if regiments.is_empty():
		return templates
	var grouped_regiments: Dictionary = {}
	for regiment_def_value in regiments:
		var role_key: int = int(regiment_def_value.deployment_role)
		if not grouped_regiments.has(role_key):
			grouped_regiments[role_key] = []
		grouped_regiments[role_key].append(regiment_def_value)

	var role_order: Array = [
		SimTypes.RegimentDeploymentRole.VANGUARD,
		SimTypes.RegimentDeploymentRole.LEFT_FLANK,
		SimTypes.RegimentDeploymentRole.CENTER,
		SimTypes.RegimentDeploymentRole.RIGHT_FLANK,
		SimTypes.RegimentDeploymentRole.SECOND_LINE,
		SimTypes.RegimentDeploymentRole.RESERVE,
	]
	for role_value in role_order:
		var regiments_for_role: Array = grouped_regiments.get(role_value, [])
		if regiments_for_role.is_empty():
			continue
		for role_index in range(regiments_for_role.size()):
			var regiment_def = regiments_for_role[role_index]
			var position: Vector2 = brigade_origin + _get_large_side_regiment_offset_for_role(side_config, int(role_value), role_index, regiments_for_role.size())
			templates.append(_make_regiment_template(
				regiment_def.display_name,
				regiment_def.category,
				position,
				regiment_def.training,
				regiment_def.companies.duplicate(true),
				{
					"commander_profile_id": regiment_def.commander_profile_id,
					"commander_name": regiment_def.commander_name,
					"banner_profile_id": regiment_def.banner_profile_id,
				}
			))
	return templates


static func _get_large_side_override_config(army_id: StringName) -> Dictionary:
	match army_id:
		&"blue":
			return {
				"army_center": Vector2(1880.0, 3900.0),
				"front": Vector2.UP,
				"commander_pos": Vector2(640.0, 4240.0),
				"baggage_pos": Vector2(260.0, 4920.0),
			}
		&"red":
			return {
				"army_center": Vector2(6520.0, 1500.0),
				"front": Vector2.DOWN,
				"commander_pos": Vector2(7760.0, 1160.0),
				"baggage_pos": Vector2(8140.0, 480.0),
			}
		_:
			return {}


static func _get_large_side_brigade_origin_for_role(side_config: Dictionary, deployment_role: int, role_index: int, role_count: int) -> Vector2:
	var center_offset: float = float(role_index) - float(role_count - 1) * 0.5
	var army_center: Vector2 = side_config.get("army_center", Vector2.ZERO)
	var forward: Vector2 = side_config.get("front", Vector2.UP).normalized()
	var right: Vector2 = Vector2(-forward.y, forward.x)
	match deployment_role:
		SimTypes.BrigadeDeploymentRole.LEFT_WING:
			return army_center - right * 900.0 + forward * 40.0 - forward * center_offset * 360.0
		SimTypes.BrigadeDeploymentRole.RIGHT_WING:
			return army_center + right * 960.0 + forward * 40.0 - forward * center_offset * 360.0
		SimTypes.BrigadeDeploymentRole.SECOND_LINE:
			return army_center + right * center_offset * 340.0 - forward * 480.0
		SimTypes.BrigadeDeploymentRole.RESERVE:
			return army_center + right * center_offset * 340.0 - forward * 960.0
		SimTypes.BrigadeDeploymentRole.VANGUARD:
			return army_center + right * center_offset * 340.0 + forward * 520.0
		_:
			return army_center + right * center_offset * 340.0


static func _get_large_side_regiment_offset_for_role(side_config: Dictionary, deployment_role: int, role_index: int, role_count: int) -> Vector2:
	var center_offset: float = float(role_index) - float(role_count - 1) * 0.5
	var forward: Vector2 = side_config.get("front", Vector2.UP).normalized()
	var right: Vector2 = Vector2(-forward.y, forward.x)
	match deployment_role:
		SimTypes.RegimentDeploymentRole.LEFT_FLANK:
			return -right * 260.0 - forward * center_offset * 140.0
		SimTypes.RegimentDeploymentRole.RIGHT_FLANK:
			return right * 260.0 - forward * center_offset * 140.0
		SimTypes.RegimentDeploymentRole.SECOND_LINE:
			return right * center_offset * 210.0 - forward * 200.0
		SimTypes.RegimentDeploymentRole.RESERVE:
			return right * center_offset * 210.0 - forward * 380.0
		SimTypes.RegimentDeploymentRole.VANGUARD:
			return right * center_offset * 210.0 + forward * 220.0
		_:
			return right * center_offset * 210.0


static func _get_default_command_profile_id(category: int, company_count: int) -> StringName:
	if company_count >= 8 and category == SimTypes.UnitCategory.INFANTRY:
		return &"tercio_maestre"
	match category:
		SimTypes.UnitCategory.CAVALRY:
			return &"cavalry_standard"
		SimTypes.UnitCategory.ARTILLERY:
			return &"artillery_standard"
		_:
			return &"expanded_colonel" if company_count > 4 else &"infantry_standard"


static func _get_default_banner_profile_id(category: int) -> StringName:
	match category:
		SimTypes.UnitCategory.INFANTRY:
			return &"standard_colors"
		SimTypes.UnitCategory.CAVALRY:
			return &"guard_colors"
		_:
			return &"standard_colors"


static func _get_default_doctrine_for_category(category: int) -> StringName:
	match category:
		SimTypes.UnitCategory.CAVALRY:
			return &"cavalry_shock"
		SimTypes.UnitCategory.ARTILLERY:
			return &"artillery_battery"
		_:
			return &"default"


static func _get_default_behavior_doctrine_for_category(category: int) -> StringName:
	match category:
		SimTypes.UnitCategory.CAVALRY:
			return &"cavalry_mobile"
		SimTypes.UnitCategory.ARTILLERY:
			return &"artillery_static"
		_:
			return &"default"
