class_name CoreV2Types
extends RefCounted


enum BattlePhase {
	DEPLOYMENT,
	ACTIVE,
	RESOLVED,
}

enum CommandType {
	PLACE_BAGGAGE,
	PLACE_COMMANDER,
	ISSUE_BRIGADE_ORDER,
	START_BATTLE,
	DEBUG_FORCE_FORMATION,
}

enum OrderType {
	NONE,
	MOVE,
	MARCH,
	ATTACK,
	MELEE_ASSAULT,
	DEFEND,
	PATROL,
	HOLD,
}

enum EntityKind {
	NONE,
	BATTALION,
	BRIGADE_HQ,
	ARMY_HQ,
	BAGGAGE_TRAIN,
	OBJECTIVE,
	MESSENGER,
}

enum UnitCategory {
	INFANTRY,
	CAVALRY,
	ARTILLERY,
	SUPPLY,
	HQ,
}

enum FormationState {
	LINE,
	MUSKETEER_LINE,
	DEFENSIVE,
	TERCIA,
	COLUMN,
	MARCH_COLUMN,
}

enum UnitStatus {
	STAGING,
	IDLE,
	MOVING,
	HOLDING,
	ENGAGING,
	ROUTING,
}

enum MessengerStatus {
	EN_ROUTE,
	DELIVERED,
	INTERCEPTED,
}

enum TerrainType {
	PLAIN,
	FOREST,
	MARSH,
	BRUSH,
	FARM,
	VILLAGE,
	TOWN,
	HILL,
	RAVINE,
}


static func battle_phase_name(value: int) -> String:
	match value:
		BattlePhase.DEPLOYMENT:
			return "Активна пауза"
		BattlePhase.ACTIVE:
			return "Битва"
		BattlePhase.RESOLVED:
			return "Завершено"
		_:
			return "Невідомо"


static func command_type_name(value: int) -> String:
	match value:
		CommandType.PLACE_BAGGAGE:
			return "Розміщення обозу"
		CommandType.PLACE_COMMANDER:
			return "Розміщення полководця"
		CommandType.ISSUE_BRIGADE_ORDER:
			return "Наказ бригаді"
		CommandType.START_BATTLE:
			return "Початок битви"
		CommandType.DEBUG_FORCE_FORMATION:
			return "Debug: примусова формація"
		_:
			return "Невідома команда"


static func order_type_name(value: int) -> String:
	match value:
		OrderType.MOVE:
			return "Рух"
		OrderType.MARCH:
			return "Марш"
		OrderType.ATTACK:
			return "Атака"
		OrderType.MELEE_ASSAULT:
			return "Рукопашна атака"
		OrderType.DEFEND:
			return "Оборона"
		OrderType.PATROL:
			return "Патруль"
		OrderType.HOLD:
			return "Утримання"
		_:
			return "Без наказу"


static func entity_kind_name(value: int) -> String:
	match value:
		EntityKind.BATTALION:
			return "Батальйон"
		EntityKind.BRIGADE_HQ:
			return "Штаб бригади"
		EntityKind.ARMY_HQ:
			return "Штаб полководця"
		EntityKind.BAGGAGE_TRAIN:
			return "Обоз"
		EntityKind.OBJECTIVE:
			return "Стратегічний пункт"
		EntityKind.MESSENGER:
			return "Гінець"
		_:
			return "Сутність"


static func unit_category_name(value: int) -> String:
	match value:
		UnitCategory.CAVALRY:
			return "Кавалерія"
		UnitCategory.ARTILLERY:
			return "Артилерія"
		UnitCategory.SUPPLY:
			return "Постачання"
		UnitCategory.HQ:
			return "Штаб"
		_:
			return "Піхота"


static func formation_state_name(value: int) -> String:
	match value:
		FormationState.MUSKETEER_LINE:
			return "Лінія мушкетерів"
		FormationState.DEFENSIVE:
			return "Захисний стрій"
		FormationState.TERCIA:
			return "Терція"
		FormationState.COLUMN:
			return "Колона"
		FormationState.MARCH_COLUMN:
			return "Маршева колона"
		_:
			return "Лінія"


static func unit_status_name(value: int) -> String:
	match value:
		UnitStatus.STAGING:
			return "Очікує розгортання"
		UnitStatus.MOVING:
			return "Рухається"
		UnitStatus.HOLDING:
			return "Утримує позицію"
		UnitStatus.ENGAGING:
			return "В бою"
		UnitStatus.ROUTING:
			return "Тікає"
		_:
			return "Готовий"


static func messenger_status_name(value: int) -> String:
	match value:
		MessengerStatus.DELIVERED:
			return "Доставив наказ"
		MessengerStatus.INTERCEPTED:
			return "Перехоплений"
		_:
			return "Везе наказ"


static func terrain_type_name(value: int) -> String:
	match value:
		TerrainType.FOREST:
			return "Ліс"
		TerrainType.MARSH:
			return "Болото"
		TerrainType.BRUSH:
			return "Кущі"
		TerrainType.FARM:
			return "Ферма"
		TerrainType.VILLAGE:
			return "Село"
		TerrainType.TOWN:
			return "Місто"
		TerrainType.HILL:
			return "Пагорб"
		TerrainType.RAVINE:
			return "Рівчак"
		_:
			return "Рівнина"
