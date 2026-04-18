class_name SimTypes
extends RefCounted

# Shared enums keep the simulation, application bridge, and presentation
# speaking the same language without coupling to scene nodes.
enum OrderType {
	NONE,
	MOVE,
	MARCH,
	ATTACK,
	DEFEND,
	PATROL,
	HOLD,
}

enum OrderStatus {
	CREATED,
	IN_TRANSIT,
	DELIVERED,
	FAILED,
}

enum DeliveryMethod {
	VOICE,
	MESSENGER,
}

enum UnitCategory {
	INFANTRY,
	CAVALRY,
	ARTILLERY,
	SUPPORT,
}

enum CompanyType {
	PIKEMEN,
	MUSKETEERS,
	CAVALRY,
	ARTILLERY,
	HQ,
	WAGONS,
}

enum RegimentalElementType {
	BANNER,
}

enum FormationType {
	LINE,
	COLUMN,
	SQUARE,
}

enum RegimentFormationState {
	DEFAULT,
	MARCH_COLUMN,
	PROTECTED,
	MUSKETEER_LINE,
	TERCIA,
}

enum RegimentFireBehavior {
	NONE,
	VOLLEY,
	COUNTERMARCH,
	CARACOLE,
}

enum EngagementState {
	NO_CONTACT,
	APPROACH,
	DEPLOY_FIRE,
	FIREFIGHT,
	ASSAULT,
	DISENGAGE,
	RECOVER,
}

enum FirearmContactMode {
	HALT_AND_FIRE,
	ADVANCE_BY_FIRE,
	PRESS_IMMEDIATELY,
}

enum ShockContactMode {
	ASSAULT,
	WITHDRAW,
}

enum TerrainType {
	PLAINS,
	FOREST,
	SWAMP,
	BUSHES,
	FARM,
	VILLAGE,
	CITY,
}

enum IntelDetail {
	NONE,
	BROAD,
	DETAILED,
	CLOSE,
}

enum BrigadeRole {
	CENTER,
	LEFT_FLANK,
	RIGHT_FLANK,
	RESERVE,
	SUPPORT_ARTILLERY,
}

enum BrigadeDeploymentRole {
	LEFT_WING,
	CENTER,
	RIGHT_WING,
	SECOND_LINE,
	RESERVE,
	VANGUARD,
}

enum RegimentDeploymentRole {
	LEFT_FLANK,
	CENTER,
	RIGHT_FLANK,
	SECOND_LINE,
	RESERVE,
	VANGUARD,
}

static func order_type_name(order_type: int) -> String:
	match order_type:
		OrderType.MOVE:
			return "Move"
		OrderType.MARCH:
			return "March"
		OrderType.ATTACK:
			return "Attack"
		OrderType.DEFEND:
			return "Defend"
		OrderType.PATROL:
			return "Patrol"
		OrderType.HOLD:
			return "Hold"
		_:
			return "Idle"


static func unit_category_name(category: int) -> String:
	match category:
		UnitCategory.CAVALRY:
			return "Cavalry"
		UnitCategory.ARTILLERY:
			return "Artillery"
		UnitCategory.SUPPORT:
			return "Support"
		_:
			return "Infantry"


static func company_type_name(company_type: int) -> String:
	match company_type:
		CompanyType.PIKEMEN:
			return "Pikemen"
		CompanyType.MUSKETEERS:
			return "Musketeers"
		CompanyType.CAVALRY:
			return "Cavalry"
		CompanyType.ARTILLERY:
			return "Artillery"
		CompanyType.HQ:
			return "Headquarters"
		CompanyType.WAGONS:
			return "Wagons"
		_:
			return "Company"


static func formation_name(formation_type: int) -> String:
	match formation_type:
		FormationType.COLUMN:
			return "Column"
		FormationType.SQUARE:
			return "Square"
		_:
			return "Line"


static func regiment_formation_state_name(formation_state: int) -> String:
	match formation_state:
		RegimentFormationState.MARCH_COLUMN:
			return "March Column"
		RegimentFormationState.PROTECTED:
			return "Protected"
		RegimentFormationState.MUSKETEER_LINE:
			return "Musketeer Line"
		RegimentFormationState.TERCIA:
			return "Tercia"
		_:
			return "Default"


static func regiment_fire_behavior_name(fire_behavior: int) -> String:
	match fire_behavior:
		RegimentFireBehavior.VOLLEY:
			return "Volley"
		RegimentFireBehavior.COUNTERMARCH:
			return "Countermarch"
		RegimentFireBehavior.CARACOLE:
			return "Caracole"
		_:
			return "None"


static func engagement_state_name(engagement_state: int) -> String:
	match engagement_state:
		EngagementState.APPROACH:
			return "Approach"
		EngagementState.DEPLOY_FIRE:
			return "Deploy Fire"
		EngagementState.FIREFIGHT:
			return "Firefight"
		EngagementState.ASSAULT:
			return "Assault"
		EngagementState.DISENGAGE:
			return "Disengage"
		EngagementState.RECOVER:
			return "Recover"
		_:
			return "No Contact"


static func terrain_name(terrain_type: int) -> String:
	match terrain_type:
		TerrainType.FOREST:
			return "Forest"
		TerrainType.SWAMP:
			return "Swamp"
		TerrainType.BUSHES:
			return "Bushes"
		TerrainType.FARM:
			return "Farm"
		TerrainType.VILLAGE:
			return "Village"
		TerrainType.CITY:
			return "City"
		_:
			return "Plains"


static func intel_detail_name(detail_level: int) -> String:
	match detail_level:
		IntelDetail.BROAD:
			return "Broad"
		IntelDetail.DETAILED:
			return "Detailed"
		IntelDetail.CLOSE:
			return "Close"
		_:
			return "None"

static func brigade_role_name(brigade_role: int) -> String:
	match brigade_role:
		BrigadeRole.LEFT_FLANK:
			return "Left Flank"
		BrigadeRole.RIGHT_FLANK:
			return "Right Flank"
		BrigadeRole.RESERVE:
			return "Reserve"
		BrigadeRole.SUPPORT_ARTILLERY:
			return "Support Artillery"
		_:
			return "Center"


static func brigade_deployment_role_name(deployment_role: int) -> String:
	match deployment_role:
		BrigadeDeploymentRole.LEFT_WING:
			return "Left Wing"
		BrigadeDeploymentRole.RIGHT_WING:
			return "Right Wing"
		BrigadeDeploymentRole.SECOND_LINE:
			return "Second Line"
		BrigadeDeploymentRole.RESERVE:
			return "Reserve"
		BrigadeDeploymentRole.VANGUARD:
			return "Vanguard"
		_:
			return "Center"


static func regiment_deployment_role_name(deployment_role: int) -> String:
	match deployment_role:
		RegimentDeploymentRole.LEFT_FLANK:
			return "Left Flank"
		RegimentDeploymentRole.RIGHT_FLANK:
			return "Right Flank"
		RegimentDeploymentRole.SECOND_LINE:
			return "Second Line"
		RegimentDeploymentRole.RESERVE:
			return "Reserve"
		RegimentDeploymentRole.VANGUARD:
			return "Vanguard"
		_:
			return "Center"
