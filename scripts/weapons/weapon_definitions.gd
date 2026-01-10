extends Node
class_name WeaponDefinitions
## WeaponDefinitions - Static weapon data
##
## Contains all weapon definitions that can be loaded into WeaponRuntime.
## This is used for both client prediction and server validation.
##
## In production, these would come from the backend item definitions.
## This file serves as fallback/default definitions.

# Weapon categories
const CATEGORY_RIFLE := "rifle"
const CATEGORY_SMG := "smg"
const CATEGORY_PISTOL := "pistol"
const CATEGORY_SHOTGUN := "shotgun"
const CATEGORY_SNIPER := "sniper"
const CATEGORY_MELEE := "melee"

# Ammo types
const AMMO_762 := "7.62x39"
const AMMO_556 := "5.56x45"
const AMMO_9MM := "9x19"
const AMMO_45ACP := "45acp"
const AMMO_12GA := "12ga"
const AMMO_308 := "7.62x51"

# All weapon definitions
static var WEAPONS: Dictionary = {
	# ============================================
	# RIFLES
	# ============================================
	"rifle_ak47": {
		"def_id": "rifle_ak47",
		"name": "AK-47",
		"description": "Reliable assault rifle with moderate recoil",
		"category": CATEGORY_RIFLE,
		"weapon_type": "rifle",
		"damage": 35.0,
		"fire_rate": 0.1,  # 600 RPM
		"magazine_size": 30,
		"reload_time": 2.5,
		"spread": 0.025,
		"ads_spread_mult": 0.3,
		"ammo_type": AMMO_762,
		"range": 200.0,
		"recoil_vertical": 0.03,
		"recoil_horizontal": 0.012,
		"recoil_recovery": 4.0,
		"weight": 3.5,
		"price": 25000,
	},
	"rifle_m4a1": {
		"def_id": "rifle_m4a1",
		"name": "M4A1",
		"description": "Accurate assault rifle with low recoil",
		"category": CATEGORY_RIFLE,
		"weapon_type": "rifle",
		"damage": 32.0,
		"fire_rate": 0.08,  # 750 RPM
		"magazine_size": 30,
		"reload_time": 2.3,
		"spread": 0.02,
		"ads_spread_mult": 0.25,
		"ammo_type": AMMO_556,
		"range": 220.0,
		"recoil_vertical": 0.022,
		"recoil_horizontal": 0.008,
		"recoil_recovery": 5.0,
		"weight": 3.2,
		"price": 30000,
	},
	"rifle_scar": {
		"def_id": "rifle_scar",
		"name": "SCAR-H",
		"description": "Hard-hitting battle rifle",
		"category": CATEGORY_RIFLE,
		"weapon_type": "rifle",
		"damage": 45.0,
		"fire_rate": 0.12,  # 500 RPM
		"magazine_size": 20,
		"reload_time": 2.8,
		"spread": 0.018,
		"ads_spread_mult": 0.2,
		"ammo_type": AMMO_308,
		"range": 250.0,
		"recoil_vertical": 0.04,
		"recoil_horizontal": 0.015,
		"recoil_recovery": 3.5,
		"weight": 4.0,
		"price": 45000,
	},

	# ============================================
	# SMGs
	# ============================================
	"smg_mp5": {
		"def_id": "smg_mp5",
		"name": "MP5",
		"description": "Accurate submachine gun",
		"category": CATEGORY_SMG,
		"weapon_type": "smg",
		"damage": 25.0,
		"fire_rate": 0.075,  # 800 RPM
		"magazine_size": 30,
		"reload_time": 2.0,
		"spread": 0.03,
		"ads_spread_mult": 0.35,
		"ammo_type": AMMO_9MM,
		"range": 100.0,
		"recoil_vertical": 0.015,
		"recoil_horizontal": 0.02,
		"recoil_recovery": 6.0,
		"weight": 2.5,
		"price": 18000,
	},
	"smg_ump45": {
		"def_id": "smg_ump45",
		"name": "UMP-45",
		"description": "Hard-hitting SMG with slower fire rate",
		"category": CATEGORY_SMG,
		"weapon_type": "smg",
		"damage": 32.0,
		"fire_rate": 0.1,  # 600 RPM
		"magazine_size": 25,
		"reload_time": 2.2,
		"spread": 0.028,
		"ads_spread_mult": 0.3,
		"ammo_type": AMMO_45ACP,
		"range": 80.0,
		"recoil_vertical": 0.02,
		"recoil_horizontal": 0.018,
		"recoil_recovery": 5.5,
		"weight": 2.7,
		"price": 15000,
	},
	"smg_vector": {
		"def_id": "smg_vector",
		"name": "Vector",
		"description": "Extremely fast fire rate with unique recoil system",
		"category": CATEGORY_SMG,
		"weapon_type": "smg",
		"damage": 22.0,
		"fire_rate": 0.05,  # 1200 RPM
		"magazine_size": 33,
		"reload_time": 1.8,
		"spread": 0.035,
		"ads_spread_mult": 0.4,
		"ammo_type": AMMO_45ACP,
		"range": 70.0,
		"recoil_vertical": 0.012,
		"recoil_horizontal": 0.025,
		"recoil_recovery": 7.0,
		"weight": 2.3,
		"price": 35000,
	},

	# ============================================
	# PISTOLS
	# ============================================
	"pistol_glock17": {
		"def_id": "pistol_glock17",
		"name": "Glock 17",
		"description": "Reliable 9mm sidearm",
		"category": CATEGORY_PISTOL,
		"weapon_type": "pistol",
		"damage": 28.0,
		"fire_rate": 0.15,  # Semi-auto
		"magazine_size": 17,
		"reload_time": 1.5,
		"spread": 0.04,
		"ads_spread_mult": 0.35,
		"ammo_type": AMMO_9MM,
		"range": 50.0,
		"recoil_vertical": 0.045,
		"recoil_horizontal": 0.02,
		"recoil_recovery": 8.0,
		"weight": 0.8,
		"price": 5000,
	},
	"pistol_m1911": {
		"def_id": "pistol_m1911",
		"name": "M1911",
		"description": "Classic .45 ACP pistol with stopping power",
		"category": CATEGORY_PISTOL,
		"weapon_type": "pistol",
		"damage": 42.0,
		"fire_rate": 0.18,
		"magazine_size": 7,
		"reload_time": 1.8,
		"spread": 0.035,
		"ads_spread_mult": 0.3,
		"ammo_type": AMMO_45ACP,
		"range": 45.0,
		"recoil_vertical": 0.06,
		"recoil_horizontal": 0.025,
		"recoil_recovery": 6.0,
		"weight": 1.0,
		"price": 8000,
	},
	"pistol_deagle": {
		"def_id": "pistol_deagle",
		"name": "Desert Eagle",
		"description": "Massive hand cannon",
		"category": CATEGORY_PISTOL,
		"weapon_type": "pistol",
		"damage": 65.0,
		"fire_rate": 0.3,
		"magazine_size": 7,
		"reload_time": 2.2,
		"spread": 0.05,
		"ads_spread_mult": 0.25,
		"ammo_type": AMMO_45ACP,  # Simplified
		"range": 60.0,
		"recoil_vertical": 0.1,
		"recoil_horizontal": 0.04,
		"recoil_recovery": 4.0,
		"weight": 1.8,
		"price": 20000,
	},

	# ============================================
	# SHOTGUNS
	# ============================================
	"shotgun_remington": {
		"def_id": "shotgun_remington",
		"name": "Remington 870",
		"description": "Pump-action shotgun with devastating close range damage",
		"category": CATEGORY_SHOTGUN,
		"weapon_type": "shotgun",
		"damage": 15.0,  # Per pellet, 8 pellets = 120 max
		"fire_rate": 0.8,  # Pump action
		"magazine_size": 6,
		"reload_time": 0.5,  # Per shell
		"spread": 0.08,
		"ads_spread_mult": 0.6,
		"ammo_type": AMMO_12GA,
		"range": 30.0,
		"recoil_vertical": 0.1,
		"recoil_horizontal": 0.04,
		"recoil_recovery": 3.0,
		"pellet_count": 8,
		"weight": 3.5,
		"price": 12000,
	},
	"shotgun_saiga": {
		"def_id": "shotgun_saiga",
		"name": "Saiga-12",
		"description": "Semi-automatic shotgun",
		"category": CATEGORY_SHOTGUN,
		"weapon_type": "shotgun",
		"damage": 12.0,  # Per pellet
		"fire_rate": 0.25,
		"magazine_size": 8,
		"reload_time": 3.0,
		"spread": 0.1,
		"ads_spread_mult": 0.5,
		"ammo_type": AMMO_12GA,
		"range": 25.0,
		"recoil_vertical": 0.08,
		"recoil_horizontal": 0.05,
		"recoil_recovery": 4.0,
		"pellet_count": 8,
		"weight": 4.0,
		"price": 28000,
	},

	# ============================================
	# SNIPERS
	# ============================================
	"sniper_mosin": {
		"def_id": "sniper_mosin",
		"name": "Mosin-Nagant",
		"description": "Bolt-action rifle with high damage",
		"category": CATEGORY_SNIPER,
		"weapon_type": "sniper",
		"damage": 85.0,
		"fire_rate": 1.5,  # Bolt action
		"magazine_size": 5,
		"reload_time": 0.8,  # Per round
		"spread": 0.005,
		"ads_spread_mult": 0.1,
		"ammo_type": AMMO_308,
		"range": 400.0,
		"recoil_vertical": 0.07,
		"recoil_horizontal": 0.015,
		"recoil_recovery": 2.5,
		"weight": 4.5,
		"price": 22000,
	},
	"sniper_svd": {
		"def_id": "sniper_svd",
		"name": "SVD Dragunov",
		"description": "Semi-automatic designated marksman rifle",
		"category": CATEGORY_SNIPER,
		"weapon_type": "sniper",
		"damage": 70.0,
		"fire_rate": 0.4,
		"magazine_size": 10,
		"reload_time": 3.0,
		"spread": 0.008,
		"ads_spread_mult": 0.15,
		"ammo_type": AMMO_308,
		"range": 350.0,
		"recoil_vertical": 0.055,
		"recoil_horizontal": 0.012,
		"recoil_recovery": 3.0,
		"weight": 4.2,
		"price": 45000,
	},

	# ============================================
	# MELEE
	# ============================================
	"melee_knife": {
		"def_id": "melee_knife",
		"name": "Combat Knife",
		"description": "Fast melee weapon",
		"category": CATEGORY_MELEE,
		"weapon_type": "melee",
		"damage": 50.0,
		"fire_rate": 0.5,  # Attack rate
		"magazine_size": 0,  # N/A
		"reload_time": 0.0,  # N/A
		"spread": 0.0,
		"ads_spread_mult": 1.0,
		"ammo_type": "",
		"range": 2.0,
		"recoil_vertical": 0.0,
		"recoil_horizontal": 0.0,
		"recoil_recovery": 0.0,
		"weight": 0.3,
		"price": 2000,
	},
	"melee_machete": {
		"def_id": "melee_machete",
		"name": "Machete",
		"description": "Heavy melee weapon with longer reach",
		"category": CATEGORY_MELEE,
		"weapon_type": "melee",
		"damage": 75.0,
		"fire_rate": 0.7,
		"magazine_size": 0,
		"reload_time": 0.0,
		"spread": 0.0,
		"ads_spread_mult": 1.0,
		"ammo_type": "",
		"range": 2.5,
		"recoil_vertical": 0.0,
		"recoil_horizontal": 0.0,
		"recoil_recovery": 0.0,
		"weight": 0.6,
		"price": 3500,
	},
}

# Ammo definitions
static var AMMO: Dictionary = {
	AMMO_762: {
		"def_id": AMMO_762,
		"name": "7.62x39mm",
		"description": "Standard rifle ammunition",
		"stack_size": 60,
		"price": 150,  # Per stack
	},
	AMMO_556: {
		"def_id": AMMO_556,
		"name": "5.56x45mm NATO",
		"description": "NATO standard rifle ammunition",
		"stack_size": 60,
		"price": 180,
	},
	AMMO_9MM: {
		"def_id": AMMO_9MM,
		"name": "9x19mm Parabellum",
		"description": "Common pistol and SMG ammunition",
		"stack_size": 50,
		"price": 100,
	},
	AMMO_45ACP: {
		"def_id": AMMO_45ACP,
		"name": ".45 ACP",
		"description": "Heavy pistol ammunition",
		"stack_size": 50,
		"price": 120,
	},
	AMMO_12GA: {
		"def_id": AMMO_12GA,
		"name": "12 Gauge",
		"description": "Shotgun shells",
		"stack_size": 20,
		"price": 200,
	},
	AMMO_308: {
		"def_id": AMMO_308,
		"name": "7.62x51mm NATO",
		"description": "High-powered rifle ammunition",
		"stack_size": 30,
		"price": 300,
	},
}


## Get weapon definition by ID
static func get_weapon(def_id: String) -> Dictionary:
	return WEAPONS.get(def_id, {})


## Get ammo definition by type
static func get_ammo(ammo_type: String) -> Dictionary:
	return AMMO.get(ammo_type, {})


## Get all weapons in a category
static func get_weapons_by_category(category: String) -> Array:
	var result := []
	for def_id in WEAPONS:
		if WEAPONS[def_id].category == category:
			result.append(WEAPONS[def_id])
	return result


## Get all weapon IDs
static func get_all_weapon_ids() -> Array:
	return WEAPONS.keys()


## Check if weapon exists
static func has_weapon(def_id: String) -> bool:
	return def_id in WEAPONS


## Calculate headshot damage
static func calculate_headshot_damage(base_damage: float) -> float:
	return base_damage * 2.5  # 2.5x headshot multiplier


## Calculate damage falloff based on distance
static func calculate_damage_falloff(base_damage: float, distance: float, max_range: float) -> float:
	if distance >= max_range:
		return base_damage * 0.3  # Minimum damage at max range

	var falloff_start := max_range * 0.5  # Start falloff at 50% of max range
	if distance < falloff_start:
		return base_damage

	var falloff_progress := (distance - falloff_start) / (max_range - falloff_start)
	return base_damage * (1.0 - falloff_progress * 0.7)  # Max 70% reduction
