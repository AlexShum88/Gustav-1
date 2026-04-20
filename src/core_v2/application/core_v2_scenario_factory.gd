class_name CoreV2ScenarioFactory
extends RefCounted


const ENABLE_BLUE_STRESS_TEST_BRIGADES: bool = false
const STRESS_TEST_BRIGADE_COUNT: int = 5
const STRESS_TEST_BATTALIONS_PER_BRIGADE: int = 10
const STRESS_TEST_BATTALION_SPACING_X: float = 480.0
const STRESS_TEST_BRIGADE_SPACING_Z: float = 180.0
const RED_FORWARD_TEST_HQ_Z: float = 2020.0
const RED_FORWARD_TEST_LINE_Z: float = 2200.0


static func create_test_sandbox() -> CoreV2BattleState:
	var state := CoreV2BattleState.new()

	var blue_army: CoreV2Army = _create_blue_army()
	var red_army: CoreV2Army = _create_red_army()
	state.player_army_id = blue_army.id
	state.add_army(blue_army)
	state.add_army(red_army)

	state.add_objective(_create_objective("village_center", "Центральне село", Vector3(0.0, 0.0, 0.0)))
	state.add_objective(_create_objective("village_west", "Західне село", Vector3(-1250.0, 0.0, -180.0)))
	state.add_objective(_create_objective("village_east", "Східне село", Vector3(1320.0, 0.0, 180.0)))
	_configure_test_terrain(state)
	_snap_entities_to_terrain(state)

	state.recent_events = [
		"Створено sandbox для core_v2.",
		"Синя армія чекає розміщення обозу та полководця.",
		"Червона армія вже розгорнута для тесту серверного циклу.",
	]
	if ENABLE_BLUE_STRESS_TEST_BRIGADES:
		state.recent_events.push_front("Навантажувальний тест: синя армія має 5 бригад по 10 батальйонів.")
	state.recent_events.push_front("Terrain v2: додано базові поверхні, висоти й дороги.")
	return state


static func _configure_test_terrain(state: CoreV2BattleState) -> void:
	state.add_terrain_patch(
		"center_village_ground",
		"Центральне село",
		CoreV2Types.TerrainType.VILLAGE,
		Rect2(-420.0, -360.0, 840.0, 720.0),
		2.0,
		0.82,
		0.72,
		0.18,
		Color(0.56, 0.48, 0.34, 0.68)
	)
	state.add_terrain_patch(
		"west_village_ground",
		"Західне село",
		CoreV2Types.TerrainType.VILLAGE,
		Rect2(-1660.0, -520.0, 760.0, 680.0),
		1.5,
		0.84,
		0.74,
		0.16,
		Color(0.54, 0.46, 0.32, 0.66)
	)
	state.add_terrain_patch(
		"east_village_ground",
		"Східне село",
		CoreV2Types.TerrainType.VILLAGE,
		Rect2(960.0, -180.0, 760.0, 700.0),
		1.5,
		0.84,
		0.74,
		0.16,
		Color(0.54, 0.46, 0.32, 0.66)
	)
	state.add_terrain_patch(
		"west_forest",
		"Західний ліс",
		CoreV2Types.TerrainType.FOREST,
		Rect2(-4700.0, -1200.0, 1750.0, 2500.0),
		8.0,
		0.52,
		0.48,
		0.24,
		Color(0.12, 0.28, 0.13, 0.74)
	)
	state.add_terrain_patch(
		"east_brush",
		"Східні кущі",
		CoreV2Types.TerrainType.BRUSH,
		Rect2(2650.0, -840.0, 1700.0, 1680.0),
		4.0,
		0.68,
		0.62,
		0.14,
		Color(0.24, 0.38, 0.16, 0.62)
	)
	state.add_terrain_patch(
		"south_marsh",
		"Південне болото",
		CoreV2Types.TerrainType.MARSH,
		Rect2(-880.0, 1180.0, 1760.0, 880.0),
		-3.0,
		0.46,
		0.78,
		-0.08,
		Color(0.18, 0.31, 0.28, 0.62)
	)
	state.add_terrain_patch(
		"north_hill_foothill",
		"Північний пагорб: підніжжя",
		CoreV2Types.TerrainType.HILL,
		Rect2(-1160.0, -2620.0, 2320.0, 1580.0),
		16.0,
		0.9,
		1.12,
		0.08,
		Color(0.38, 0.45, 0.24, 0.5),
		620.0
	)
	state.add_terrain_patch(
		"north_hill_slope",
		"Північний пагорб: схил",
		CoreV2Types.TerrainType.HILL,
		Rect2(-900.0, -2380.0, 1800.0, 1120.0),
		34.0,
		0.86,
		1.22,
		0.12,
		Color(0.42, 0.48, 0.26, 0.58),
		420.0
	)
	state.add_terrain_patch(
		"north_hill_crown",
		"Північний пагорб: гребінь",
		CoreV2Types.TerrainType.HILL,
		Rect2(-520.0, -2160.0, 1040.0, 620.0),
		58.0,
		0.82,
		1.32,
		0.16,
		Color(0.48, 0.53, 0.28, 0.66),
		260.0
	)
	state.add_terrain_patch(
		"east_ravine_outer",
		"Східний рівчак: схили",
		CoreV2Types.TerrainType.RAVINE,
		Rect2(1660.0, -2120.0, 820.0, 2480.0),
		-6.0,
		0.68,
		0.76,
		0.1,
		Color(0.24, 0.22, 0.18, 0.46),
		260.0
	)
	state.add_terrain_patch(
		"east_ravine_inner",
		"Східний рівчак: дно",
		CoreV2Types.TerrainType.RAVINE,
		Rect2(1840.0, -1940.0, 460.0, 2120.0),
		-16.0,
		0.58,
		0.64,
		0.2,
		Color(0.25, 0.22, 0.18, 0.62),
		180.0
	)
	state.add_terrain_patch(
		"east_ravine_bed",
		"Східний рівчак: русло",
		CoreV2Types.TerrainType.RAVINE,
		Rect2(1960.0, -1720.0, 220.0, 1680.0),
		-24.0,
		0.48,
		0.58,
		0.24,
		Color(0.18, 0.16, 0.14, 0.68),
		90.0
	)
	state.add_terrain_patch(
		"blue_farms",
		"Південні ферми",
		CoreV2Types.TerrainType.FARM,
		Rect2(-2440.0, 2300.0, 1500.0, 980.0),
		1.0,
		0.92,
		0.9,
		0.08,
		Color(0.56, 0.50, 0.24, 0.54)
	)
	state.add_terrain_patch(
		"red_farms",
		"Північні ферми",
		CoreV2Types.TerrainType.FARM,
		Rect2(920.0, -3300.0, 1560.0, 960.0),
		1.0,
		0.92,
		0.9,
		0.08,
		Color(0.56, 0.50, 0.24, 0.54)
	)
	state.add_road(
		"north_south_road",
		"Північна дорога",
		[
			Vector3(-180.0, 0.0, -4700.0),
			Vector3(-240.0, 0.0, -2600.0),
			Vector3(-120.0, 0.0, -760.0),
			Vector3(0.0, 0.0, 0.0),
			Vector3(160.0, 0.0, 1220.0),
			Vector3(260.0, 0.0, 2880.0),
			Vector3(180.0, 0.0, 4680.0),
		],
		110.0,
		1.34
	)
	state.add_road(
		"west_east_road",
		"Східно-західна дорога",
		[
			Vector3(-4600.0, 0.0, -160.0),
			Vector3(-2600.0, 0.0, -260.0),
			Vector3(-1250.0, 0.0, -180.0),
			Vector3(0.0, 0.0, 0.0),
			Vector3(1320.0, 0.0, 180.0),
			Vector3(2860.0, 0.0, 220.0),
			Vector3(4560.0, 0.0, 140.0),
		],
		120.0,
		1.32
	)
	state.set_weather(
		"light_mist",
		"Легкий серпанок",
		0.92,
		Color(0.74, 0.78, 0.72, 0.16)
	)
	state.add_smoke_zone(
		"center_village_smoke",
		"Дим біля центрального села",
		Vector3(160.0, 0.0, -80.0),
		420.0,
		0.72,
		34.0,
		190.0,
		Color(0.62, 0.63, 0.58, 0.34)
	)
	state.add_smoke_zone(
		"east_road_smoke",
		"Дим над східною дорогою",
		Vector3(1680.0, 0.0, 220.0),
		340.0,
		0.56,
		28.0,
		220.0,
		Color(0.58, 0.59, 0.55, 0.28)
	)


static func _snap_entities_to_terrain(state: CoreV2BattleState) -> void:
	for objective_value in state.objectives:
		var objective: CoreV2Objective = objective_value
		objective.position = state.project_position_to_terrain(objective.position)
	for army_value in state.armies.values():
		var army: CoreV2Army = army_value
		army.commander_position = state.project_position_to_terrain(army.commander_position)
		army.commander_target_position = state.project_position_to_terrain(army.commander_target_position)
		army.baggage_position = state.project_position_to_terrain(army.baggage_position)
		army.baggage_target_position = state.project_position_to_terrain(army.baggage_target_position)
		for brigade_value in army.brigades:
			var brigade: CoreV2Brigade = brigade_value
			brigade.hq_position = state.project_position_to_terrain(brigade.hq_position)
			brigade.hq_target_position = state.project_position_to_terrain(brigade.hq_target_position)
			for battalion_value in brigade.battalions:
				var battalion: CoreV2Battalion = battalion_value
				battalion.position = state.project_position_to_terrain(battalion.position)
				battalion.target_position = state.project_position_to_terrain(battalion.target_position)


static func _create_blue_army() -> CoreV2Army:
	var army := CoreV2Army.new()
	army.id = &"blue"
	army.display_name = "Синя армія"
	army.color = Color(0.26, 0.55, 0.91)
	army.is_player_controlled = true
	army.commander = _create_commander("blue_commander", "Старший полководець")
	army.deployment_zones = {
		"baggage": Rect2(-1800.0, 3920.0, 3600.0, 620.0),
		"commander": Rect2(-2400.0, 2620.0, 4800.0, 940.0),
	}
	army.reserve_queue = [
		{"name": "Гвардійська бригада", "cost": 120, "status": "Резерв"},
		{"name": "Кінний резерв", "cost": 90, "status": "Резерв"},
	]

	if ENABLE_BLUE_STRESS_TEST_BRIGADES:
		_add_blue_stress_test_brigades(army)
		return army

	var first_brigade := CoreV2Brigade.new()
	first_brigade.id = &"blue_brigade_1"
	first_brigade.army_id = army.id
	first_brigade.display_name = "1-ша піхотна бригада"
	first_brigade.commander = _create_commander("blue_brigade_1_general", "Генерал Вишневський")
	first_brigade.hq_position = Vector3(-420.0, 0.0, 3120.0)
	first_brigade.hq_target_position = first_brigade.hq_position
	first_brigade.add_battalion(_create_battalion("blue_line_left", "Лівий батальйон", army.id, first_brigade.id, Vector3(-640.0, 0.0, 3340.0), Vector3(-220.0, 0.0, 220.0)))
	first_brigade.add_battalion(_create_battalion("blue_line_center", "Центральний батальйон", army.id, first_brigade.id, Vector3(-420.0, 0.0, 3340.0), Vector3(0.0, 0.0, 220.0)))
	first_brigade.add_battalion(_create_battalion("blue_line_right", "Правий батальйон", army.id, first_brigade.id, Vector3(-200.0, 0.0, 3340.0), Vector3(220.0, 0.0, 220.0)))
	army.add_brigade(first_brigade)

	var second_brigade := CoreV2Brigade.new()
	second_brigade.id = &"blue_brigade_2"
	second_brigade.army_id = army.id
	second_brigade.display_name = "2-га змішана бригада"
	second_brigade.commander = _create_commander("blue_brigade_2_general", "Генерал Дорошенко")
	second_brigade.hq_position = Vector3(620.0, 0.0, 3280.0)
	second_brigade.hq_target_position = second_brigade.hq_position
	second_brigade.add_battalion(_create_battalion("blue_mix_left", "Лівий мушкетерський", army.id, second_brigade.id, Vector3(420.0, 0.0, 3500.0), Vector3(-200.0, 0.0, 220.0)))
	second_brigade.add_battalion(_create_battalion("blue_mix_center", "Центральний мушкетерський", army.id, second_brigade.id, Vector3(620.0, 0.0, 3500.0), Vector3(0.0, 0.0, 220.0)))
	second_brigade.add_battalion(_create_cavalry_battalion("blue_mix_horse", "Кінний ескадрон", army.id, second_brigade.id, Vector3(860.0, 0.0, 3540.0), Vector3(260.0, 0.0, 260.0)))
	army.add_brigade(second_brigade)

	return army


static func _create_red_army() -> CoreV2Army:
	var army := CoreV2Army.new()
	army.id = &"red"
	army.display_name = "Червона армія"
	army.color = Color(0.86, 0.29, 0.25)
	army.commander = _create_commander("red_commander", "Генерал Шеремет")
	army.deployment_zones = {
		"baggage": Rect2(-1800.0, -4540.0, 3600.0, 620.0),
		"commander": Rect2(-2400.0, -3560.0, 4800.0, 940.0),
	}
	army.set_baggage_position(Vector3(0.0, 0.0, -4200.0))
	army.set_commander_position(Vector3(0.0, 0.0, 1780.0))

	var first_brigade := CoreV2Brigade.new()
	first_brigade.id = &"red_brigade_1"
	first_brigade.army_id = army.id
	first_brigade.display_name = "1-ша лінійна бригада"
	first_brigade.commander = _create_commander("red_brigade_1_general", "Генерал Сокол")
	first_brigade.hq_position = Vector3(-520.0, 0.0, RED_FORWARD_TEST_HQ_Z)
	first_brigade.hq_target_position = first_brigade.hq_position
	first_brigade.add_battalion(_create_battalion("red_line_left", "Лівий батальйон", army.id, first_brigade.id, Vector3(-760.0, 0.0, RED_FORWARD_TEST_LINE_Z), Vector3(-240.0, 0.0, -240.0)))
	first_brigade.add_battalion(_create_battalion("red_line_center", "Центральний батальйон", army.id, first_brigade.id, Vector3(-520.0, 0.0, RED_FORWARD_TEST_LINE_Z), Vector3(0.0, 0.0, -240.0)))
	first_brigade.add_battalion(_create_battalion("red_line_right", "Правий батальйон", army.id, first_brigade.id, Vector3(-280.0, 0.0, RED_FORWARD_TEST_LINE_Z), Vector3(240.0, 0.0, -240.0)))
	army.add_brigade(first_brigade)

	var second_brigade := CoreV2Brigade.new()
	second_brigade.id = &"red_brigade_2"
	second_brigade.army_id = army.id
	second_brigade.display_name = "2-га ударна бригада"
	second_brigade.commander = _create_commander("red_brigade_2_general", "Генерал Баранов")
	second_brigade.hq_position = Vector3(740.0, 0.0, RED_FORWARD_TEST_HQ_Z + 40.0)
	second_brigade.hq_target_position = second_brigade.hq_position
	second_brigade.add_battalion(_create_battalion("red_mix_left", "Лівий батальйон", army.id, second_brigade.id, Vector3(420.0, 0.0, RED_FORWARD_TEST_LINE_Z + 60.0), Vector3(-240.0, 0.0, -260.0)))
	second_brigade.add_battalion(_create_battalion("red_mix_center", "Центральний батальйон", army.id, second_brigade.id, Vector3(660.0, 0.0, RED_FORWARD_TEST_LINE_Z + 60.0), Vector3(0.0, 0.0, -260.0)))
	second_brigade.add_battalion(_create_cavalry_battalion("red_mix_horse", "Кінний резерв", army.id, second_brigade.id, Vector3(900.0, 0.0, RED_FORWARD_TEST_LINE_Z + 60.0), Vector3(260.0, 0.0, -300.0)))
	army.add_brigade(second_brigade)

	return army


static func _create_objective(id_text: String, display_name: String, objective_position: Vector3) -> CoreV2Objective:
	var objective := CoreV2Objective.new()
	objective.id = StringName(id_text)
	objective.display_name = display_name
	objective.position = objective_position
	objective.capture_radius_m = 320.0
	objective.victory_rate_per_second = 0.35
	objective.resource_rate_per_second = 0.8
	return objective


static func _add_blue_stress_test_brigades(army: CoreV2Army) -> void:
	var start_position := Vector3(-2160.0, 0.0, 2720.0)
	for brigade_index in range(STRESS_TEST_BRIGADE_COUNT):
		var brigade_number: int = brigade_index + 1
		var brigade := CoreV2Brigade.new()
		brigade.id = StringName("blue_stress_brigade_%02d" % brigade_number)
		brigade.army_id = army.id
		brigade.display_name = "Навантажувальна бригада %d" % brigade_number
		brigade.commander = _create_commander(
			"blue_stress_brigade_%02d_general" % brigade_number,
			"Тестовий генерал %d" % brigade_number
		)
		var brigade_z: float = start_position.z + float(brigade_index) * STRESS_TEST_BRIGADE_SPACING_Z
		brigade.hq_position = Vector3(start_position.x - 180.0, 0.0, brigade_z - 90.0)
		brigade.hq_target_position = brigade.hq_position
		for battalion_index in range(STRESS_TEST_BATTALIONS_PER_BRIGADE):
			var battalion_number: int = battalion_index + 1
			var battalion_position := Vector3(
				start_position.x + float(battalion_index) * STRESS_TEST_BATTALION_SPACING_X,
				0.0,
				brigade_z
			)
			var slot_offset := Vector3(
				(float(battalion_index) - float(STRESS_TEST_BATTALIONS_PER_BRIGADE - 1) * 0.5) * 240.0,
				0.0,
				float(brigade_index) * 190.0
			)
			brigade.add_battalion(_create_battalion(
				"blue_stress_b%02d_%02d" % [brigade_number, battalion_number],
				"Стрес батальйон %d.%02d" % [brigade_number, battalion_number],
				army.id,
				brigade.id,
				battalion_position,
				slot_offset
			))
		army.add_brigade(brigade)


static func _create_battalion(
		id_text: String,
		display_name: String,
		army_id: StringName,
		brigade_id: StringName,
		spawn_position: Vector3,
		slot_offset: Vector3
) -> CoreV2Battalion:
	var battalion := CoreV2Battalion.new()
	battalion.id = StringName(id_text)
	battalion.army_id = army_id
	battalion.brigade_id = brigade_id
	battalion.display_name = display_name
	battalion.position = spawn_position
	battalion.target_position = spawn_position
	battalion.slot_offset = slot_offset
	battalion.commander = _create_commander("%s_commander" % id_text, "Майор %s" % display_name)
	battalion.training = 0.72
	battalion.cohesion = 0.84
	battalion.ammunition = 0.92
	battalion.forage = 0.88
	battalion.move_speed_mps = 31.0
	battalion.vision_radius_m = 1500.0
	battalion.soldiers_total = 1000
	battalion.sprite_count = 20
	battalion.status = CoreV2Types.UnitStatus.IDLE
	battalion.ensure_formation_ready()
	CoreV2BattalionCombatModel.initialize_composite(battalion)
	return battalion


static func _create_cavalry_battalion(
		id_text: String,
		display_name: String,
		army_id: StringName,
		brigade_id: StringName,
		spawn_position: Vector3,
		slot_offset: Vector3
) -> CoreV2Battalion:
	var battalion: CoreV2Battalion = _create_battalion(id_text, display_name, army_id, brigade_id, spawn_position, slot_offset)
	battalion.category = CoreV2Types.UnitCategory.CAVALRY
	battalion.move_speed_mps = 46.0
	battalion.vision_radius_m = 2000.0
	battalion.formation_state = CoreV2Types.FormationState.COLUMN
	battalion.desired_formation_state = battalion.formation_state
	CoreV2FormationSystem.initialize_battalion(battalion)
	return battalion


static func _create_commander(id_text: String, display_name: String) -> CoreV2Commander:
	var commander := CoreV2Commander.new()
	commander.id = StringName(id_text)
	commander.display_name = display_name
	commander.command_rating = 0.78
	commander.morale_rating = 0.74
	return commander
