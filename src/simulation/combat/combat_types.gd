class_name CombatTypes
extends RefCounted


enum CombatPosture {
	IDLE = 0,
	ADVANCING = 1,
	FIRING = 2,
	MELEE = 3,
	CHARGE_WINDUP = 4,
	CHARGE_COMMIT = 5,
	CHARGE_RECOVER = 6,
	RETIRING = 7,
}

enum CombatOrderMode {
	NONE = 0,
	HOLD_FIRE = 1,
	FIRE_AT_WILL = 2,
	VOLLEY = 3,
	COUNTERMARCH = 4,
	BRACE = 5,
	CHARGE = 6,
}

enum CombatRole {
	MUSKET = 0,
	PIKE = 1,
	CAVALRY = 2,
	ARTILLERY = 3,
}

enum ReloadState {
	READY = 0,
	FIRING = 1,
	RECOVERING = 2,
	RELOADING = 3,
}

enum ContactSide {
	NONE = 0,
	FRONT = 1,
	LEFT_FLANK = 2,
	RIGHT_FLANK = 4,
	REAR = 8,
}


static func resolve_combat_role(company_type: int, weapon_type: String) -> int:
	match company_type:
		SimTypes.CompanyType.PIKEMEN:
			return CombatRole.PIKE
		SimTypes.CompanyType.CAVALRY:
			return CombatRole.CAVALRY
		SimTypes.CompanyType.ARTILLERY:
			return CombatRole.ARTILLERY
		_:
			match weapon_type:
				"pike":
					return CombatRole.PIKE
				"cannon":
					return CombatRole.ARTILLERY
				"carbine", "pistol":
					return CombatRole.CAVALRY
				_:
					return CombatRole.MUSKET


static func build_empty_frame(time_seconds: float, delta: float) -> Dictionary:
	return {
		"time_seconds": time_seconds,
		"delta": delta,
		"regiment_frames": [],
		"company_frames": [],
		"sprite_frames": [],
		"contact_candidates": [],
		"visibility_cache": {},
		"broadphase_cells": {},
	}


static func build_empty_outcome_buffer() -> Dictionary:
	return {
		"companies": {},
		"regiments": {},
		"events": [],
	}


static func build_company_outcome_entry() -> Dictionary:
	return {
		"casualties": 0,
		"morale_delta": 0.0,
		"cohesion_delta": 0.0,
		"suppression_delta": 0.0,
		"ammo_delta": 0.0,
		"reload_state_override": -1,
		"reload_progress_override": -1.0,
		"forced_posture": -1,
		"forced_position_offset": Vector2.ZERO,
		"charge_broken": false,
		"entered_melee": false,
		"routed": false,
	}


static func build_regiment_outcome_entry() -> Dictionary:
	return {
		"morale_delta": 0.0,
		"cohesion_delta": 0.0,
		"suppression_delta": 0.0,
		"forced_posture": -1,
		"brace_until": -1.0,
		"charge_recovery_until": -1.0,
		"charge_retreat_until": -1.0,
		"charge_retreat_target_position": Vector2.ZERO,
		"charge_retreat_requested": false,
		"charge_resolved": false,
		"combat_lock_until": -1.0,
	}


static func combat_role_name(combat_role: int) -> String:
	match combat_role:
		CombatRole.PIKE:
			return "Pike"
		CombatRole.CAVALRY:
			return "Cavalry"
		CombatRole.ARTILLERY:
			return "Artillery"
		_:
			return "Musket"


static func reload_state_name(reload_state: int) -> String:
	match reload_state:
		ReloadState.FIRING:
			return "Firing"
		ReloadState.RECOVERING:
			return "Recovering"
		ReloadState.RELOADING:
			return "Reloading"
		_:
			return "Ready"


static func combat_posture_name(combat_posture: int) -> String:
	match combat_posture:
		CombatPosture.ADVANCING:
			return "Advancing"
		CombatPosture.FIRING:
			return "Firing"
		CombatPosture.MELEE:
			return "Melee"
		CombatPosture.CHARGE_WINDUP:
			return "Charge Windup"
		CombatPosture.CHARGE_COMMIT:
			return "Charge Commit"
		CombatPosture.CHARGE_RECOVER:
			return "Charge Recover"
		CombatPosture.RETIRING:
			return "Retiring"
		_:
			return "Idle"


static func combat_order_mode_name(combat_order_mode: int) -> String:
	match combat_order_mode:
		CombatOrderMode.HOLD_FIRE:
			return "Hold Fire"
		CombatOrderMode.FIRE_AT_WILL:
			return "Fire At Will"
		CombatOrderMode.VOLLEY:
			return "Volley"
		CombatOrderMode.COUNTERMARCH:
			return "Countermarch"
		CombatOrderMode.BRACE:
			return "Brace"
		CombatOrderMode.CHARGE:
			return "Charge"
		_:
			return "None"


static func contact_side_name(contact_side: int) -> String:
	match contact_side:
		ContactSide.FRONT:
			return "Front"
		ContactSide.LEFT_FLANK:
			return "Left Flank"
		ContactSide.RIGHT_FLANK:
			return "Right Flank"
		ContactSide.REAR:
			return "Rear"
		_:
			return "None"
