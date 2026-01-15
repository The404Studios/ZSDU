extends Node
class_name LootGeneratorService
## LootGenerator - Procedural loot generation system
##
## Generates random items with:
## - Random rarity tiers (Common to Legendary)
## - Random attributes and modifiers
## - Random weapon variants
## - Trinkets with special effects

signal loot_generated(loot_data: Dictionary)

# Rarity weights (higher number = more common)
const RARITY_WEIGHTS := {
	"common": 50,
	"uncommon": 30,
	"rare": 15,
	"epic": 4,
	"legendary": 1
}

const RARITY_COLORS := {
	"common": Color(0.6, 0.6, 0.6),
	"uncommon": Color(0.3, 0.8, 0.3),
	"rare": Color(0.3, 0.5, 1.0),
	"epic": Color(0.7, 0.3, 0.9),
	"legendary": Color(1.0, 0.8, 0.2),
}

# Attribute multipliers by rarity
const RARITY_MULT := {
	"common": 1.0,
	"uncommon": 1.15,
	"rare": 1.35,
	"epic": 1.6,
	"legendary": 2.0
}

# Max modifier count by rarity
const RARITY_MOD_COUNT := {
	"common": 0,
	"uncommon": 1,
	"rare": 2,
	"epic": 3,
	"legendary": 4
}

# ============================================
# WEAPON DEFINITIONS
# ============================================

const WEAPON_TYPES := {
	"pistol": {
		"names": ["Glock", "M9", "USP", "Revolver", "Desert Eagle", "Five-Seven", "P226"],
		"prefixes": ["Tactical", "Silenced", "Extended", "Custom", "Modified", "Combat", "Elite"],
		"suffixes": ["Mk.II", "Mk.III", "Pro", "Alpha", "Prime", "X", "Plus"],
		"base_damage": 15,
		"base_fire_rate": 4.0,
		"base_mag_size": 12,
		"base_reload_time": 1.5,
		"base_accuracy": 0.85,
		"damage_variance": 5,
	},
	"smg": {
		"names": ["Vector", "MP5", "UMP45", "MP7", "P90", "Uzi", "MAC-10"],
		"prefixes": ["Compact", "Extended", "Drum-Fed", "Tactical", "Suppressed", "Rapid"],
		"suffixes": ["Mk.II", "S", "X", "Tactical", "Pro", "Elite"],
		"base_damage": 12,
		"base_fire_rate": 12.0,
		"base_mag_size": 30,
		"base_reload_time": 2.0,
		"base_accuracy": 0.70,
		"damage_variance": 4,
	},
	"rifle": {
		"names": ["M4", "AK-47", "SCAR", "G36", "HK416", "Galil", "FAL"],
		"prefixes": ["Assault", "Tactical", "DMR", "Heavy", "Light", "Custom"],
		"suffixes": ["Mk.II", "Carbine", "A1", "A2", "Elite", "Tactical"],
		"base_damage": 25,
		"base_fire_rate": 8.0,
		"base_mag_size": 30,
		"base_reload_time": 2.5,
		"base_accuracy": 0.80,
		"damage_variance": 8,
	},
	"shotgun": {
		"names": ["M870", "SPAS-12", "Benelli", "AA-12", "Saiga", "KSG", "Super 90"],
		"prefixes": ["Pump", "Auto", "Sawed-off", "Tactical", "Breacher", "Combat"],
		"suffixes": ["Mk.II", "Tactical", "Pro", "Magnum", "Extended"],
		"base_damage": 80,  # Per shell (pellets)
		"base_fire_rate": 1.2,
		"base_mag_size": 8,
		"base_reload_time": 4.0,
		"base_accuracy": 0.60,
		"damage_variance": 20,
	},
	"sniper": {
		"names": ["M24", "AWP", "Barrett", "SVD", "Remington", "L96", "CheyTac"],
		"prefixes": ["Precision", "Anti-Material", "Heavy", "Tactical", "DMR"],
		"suffixes": ["Mk.II", "A1", "M", "Pro", "Elite", "Match"],
		"base_damage": 90,
		"base_fire_rate": 0.8,
		"base_mag_size": 5,
		"base_reload_time": 3.5,
		"base_accuracy": 0.95,
		"damage_variance": 15,
	},
	"lmg": {
		"names": ["M249", "PKM", "MG42", "M60", "RPK", "L86", "Stoner"],
		"prefixes": ["Heavy", "Light", "Squad", "Suppressive", "Sustained"],
		"suffixes": ["Mk.II", "A1", "Para", "E", "SAW"],
		"base_damage": 20,
		"base_fire_rate": 10.0,
		"base_mag_size": 100,
		"base_reload_time": 5.0,
		"base_accuracy": 0.65,
		"damage_variance": 6,
	},
	"melee": {
		"names": ["Machete", "Fire Axe", "Crowbar", "Baseball Bat", "Katana", "Combat Knife", "Sledgehammer"],
		"prefixes": ["Sharpened", "Reinforced", "Serrated", "Weighted", "Balanced", "Bloodied"],
		"suffixes": ["of Rending", "of Slaying", "Mk.II", "Prime", "X"],
		"base_damage": 50,
		"base_fire_rate": 1.5,  # Attack speed
		"base_mag_size": 0,
		"base_reload_time": 0,
		"base_accuracy": 1.0,
		"damage_variance": 15,
	}
}

# ============================================
# WEAPON MODIFIERS
# ============================================

const WEAPON_MODIFIERS := {
	"damage_boost": {"name": "+Damage", "stat": "damage", "min": 5, "max": 25, "type": "flat"},
	"damage_mult": {"name": "Damage %", "stat": "damage", "min": 5, "max": 20, "type": "percent"},
	"fire_rate": {"name": "+Fire Rate", "stat": "fire_rate", "min": 5, "max": 15, "type": "percent"},
	"mag_size": {"name": "+Mag Size", "stat": "mag_size", "min": 5, "max": 30, "type": "percent"},
	"reload_speed": {"name": "-Reload Time", "stat": "reload_time", "min": -5, "max": -20, "type": "percent"},
	"accuracy": {"name": "+Accuracy", "stat": "accuracy", "min": 3, "max": 12, "type": "percent"},
	"crit_chance": {"name": "+Crit Chance", "stat": "crit_chance", "min": 2, "max": 10, "type": "flat"},
	"crit_damage": {"name": "+Crit Damage", "stat": "crit_damage", "min": 10, "max": 50, "type": "percent"},
	"headshot": {"name": "+Headshot Dmg", "stat": "headshot_mult", "min": 10, "max": 40, "type": "percent"},
	"penetration": {"name": "+Penetration", "stat": "penetration", "min": 5, "max": 20, "type": "flat"},
	"lifesteal": {"name": "Lifesteal", "stat": "lifesteal", "min": 1, "max": 5, "type": "percent"},
	"explosive": {"name": "Explosive", "stat": "explosive_chance", "min": 2, "max": 8, "type": "flat"},
}

# ============================================
# TRINKET DEFINITIONS
# ============================================

const TRINKET_BASES := [
	{"name": "Ring", "slot": "ring", "icon": "ring"},
	{"name": "Amulet", "slot": "amulet", "icon": "amulet"},
	{"name": "Charm", "slot": "charm", "icon": "charm"},
	{"name": "Talisman", "slot": "talisman", "icon": "talisman"},
	{"name": "Pendant", "slot": "pendant", "icon": "pendant"},
	{"name": "Badge", "slot": "badge", "icon": "badge"},
]

const TRINKET_PREFIXES := [
	"Lucky", "Blessed", "Cursed", "Ancient", "Enchanted", "Glowing",
	"Dark", "Golden", "Silver", "Bone", "Crystal", "Iron", "Ethereal"
]

const TRINKET_SUFFIXES := [
	"of Power", "of Protection", "of Swiftness", "of Fortune",
	"of Vitality", "of Precision", "of Resilience", "of Rage",
	"of the Hunter", "of the Guardian", "of Shadows", "of Light"
]

const TRINKET_EFFECTS := {
	"health_boost": {"name": "+Max Health", "stat": "max_health", "min": 5, "max": 25, "type": "percent"},
	"stamina_boost": {"name": "+Max Stamina", "stat": "max_stamina", "min": 5, "max": 20, "type": "percent"},
	"move_speed": {"name": "+Move Speed", "stat": "move_speed", "min": 3, "max": 12, "type": "percent"},
	"damage_resist": {"name": "+Damage Resist", "stat": "damage_resist", "min": 3, "max": 15, "type": "percent"},
	"health_regen": {"name": "+Health Regen", "stat": "health_regen", "min": 0.5, "max": 3, "type": "flat"},
	"stamina_regen": {"name": "+Stamina Regen", "stat": "stamina_regen", "min": 5, "max": 20, "type": "percent"},
	"xp_boost": {"name": "+XP Gain", "stat": "xp_mult", "min": 5, "max": 25, "type": "percent"},
	"gold_find": {"name": "+Gold Find", "stat": "gold_mult", "min": 5, "max": 30, "type": "percent"},
	"luck": {"name": "+Luck", "stat": "luck", "min": 1, "max": 5, "type": "flat"},
	"crit_chance": {"name": "+Crit Chance", "stat": "crit_chance", "min": 2, "max": 8, "type": "percent"},
	"damage_all": {"name": "+All Damage", "stat": "damage_mult", "min": 3, "max": 12, "type": "percent"},
	"reload_speed": {"name": "+Reload Speed", "stat": "reload_mult", "min": 5, "max": 15, "type": "percent"},
}

# ============================================
# ARMOR DEFINITIONS
# ============================================

const ARMOR_SLOTS := {
	"head": {
		"names": ["Helmet", "Hood", "Cap", "Mask", "Visor"],
		"base_armor": 10,
		"base_durability": 100,
	},
	"chest": {
		"names": ["Vest", "Plate Carrier", "Body Armor", "Tactical Vest", "Kevlar"],
		"base_armor": 30,
		"base_durability": 150,
	},
	"legs": {
		"names": ["Pants", "Cargo Pants", "Combat Pants", "Tactical Trousers"],
		"base_armor": 15,
		"base_durability": 100,
	},
	"gloves": {
		"names": ["Gloves", "Tactical Gloves", "Combat Gloves", "Fingerless Gloves"],
		"base_armor": 5,
		"base_durability": 80,
	},
	"boots": {
		"names": ["Boots", "Combat Boots", "Tactical Boots", "Running Shoes"],
		"base_armor": 8,
		"base_durability": 100,
	}
}

const ARMOR_PREFIXES := [
	"Military", "Police", "Civilian", "Heavy", "Light", "Reinforced",
	"Padded", "Ballistic", "Tactical", "Stealth", "Assault"
]

# ============================================
# CONSUMABLE DEFINITIONS
# ============================================

const CONSUMABLES := {
	"medkit": {"name": "Medkit", "effect": "heal", "value": 50, "use_time": 3.0},
	"medkit_large": {"name": "Large Medkit", "effect": "heal", "value": 100, "use_time": 5.0},
	"bandage": {"name": "Bandage", "effect": "heal_over_time", "value": 5, "duration": 10.0, "use_time": 1.5},
	"stim_speed": {"name": "Speed Stim", "effect": "buff_speed", "value": 30, "duration": 30.0, "use_time": 1.0},
	"stim_damage": {"name": "Damage Stim", "effect": "buff_damage", "value": 20, "duration": 30.0, "use_time": 1.0},
	"stim_defense": {"name": "Defense Stim", "effect": "buff_defense", "value": 25, "duration": 30.0, "use_time": 1.0},
	"adrenaline": {"name": "Adrenaline", "effect": "instant_stamina", "value": 100, "use_time": 0.5},
	"painkiller": {"name": "Painkiller", "effect": "damage_resist", "value": 15, "duration": 60.0, "use_time": 2.0},
	"energy_drink": {"name": "Energy Drink", "effect": "stamina_regen", "value": 50, "duration": 120.0, "use_time": 2.0},
}

# ============================================
# GENERATION FUNCTIONS
# ============================================

## Generate random rarity based on weights
func roll_rarity(luck_bonus: float = 0.0) -> String:
	var total_weight := 0
	for rarity in RARITY_WEIGHTS:
		total_weight += RARITY_WEIGHTS[rarity]

	# Apply luck bonus (increases chance of better rarity)
	var roll := randi() % total_weight
	roll -= int(luck_bonus * 10)  # Luck shifts roll towards better loot

	var cumulative := 0
	for rarity in RARITY_WEIGHTS:
		cumulative += RARITY_WEIGHTS[rarity]
		if roll < cumulative:
			return rarity

	return "common"


## Generate a random weapon
func generate_weapon(weapon_type: String = "", force_rarity: String = "", luck_bonus: float = 0.0) -> Dictionary:
	# Pick random weapon type if not specified
	if weapon_type == "" or weapon_type not in WEAPON_TYPES:
		var types := WEAPON_TYPES.keys()
		weapon_type = types[randi() % types.size()]

	var base: Dictionary = WEAPON_TYPES[weapon_type]
	var rarity := force_rarity if force_rarity != "" else roll_rarity(luck_bonus)
	var rarity_mult: float = RARITY_MULT[rarity]

	# Generate name
	var base_name: String = base.names[randi() % base.names.size()]
	var full_name := base_name

	# Add prefix for uncommon+
	if rarity != "common" and randf() > 0.3:
		var prefix: String = base.prefixes[randi() % base.prefixes.size()]
		full_name = prefix + " " + base_name

	# Add suffix for rare+
	if rarity in ["rare", "epic", "legendary"] and randf() > 0.4:
		var suffix: String = base.suffixes[randi() % base.suffixes.size()]
		full_name = full_name + " " + suffix

	# Calculate stats with variance and rarity multiplier
	var damage_var: int = base.damage_variance
	var damage: int = int((base.base_damage + randi_range(-damage_var, damage_var)) * rarity_mult)
	var fire_rate: float = base.base_fire_rate * (1.0 + (rarity_mult - 1.0) * 0.3)
	var mag_size: int = int(base.base_mag_size * (1.0 + (rarity_mult - 1.0) * 0.5))
	var reload_time: float = base.base_reload_time / (1.0 + (rarity_mult - 1.0) * 0.3)
	var accuracy: float = minf(base.base_accuracy * (1.0 + (rarity_mult - 1.0) * 0.2), 0.98)

	# Generate modifiers
	var mods: Array = []
	var mod_count: int = RARITY_MOD_COUNT[rarity]
	var available_mods := WEAPON_MODIFIERS.keys()

	for i in range(mod_count):
		if available_mods.is_empty():
			break
		var mod_id: String = available_mods[randi() % available_mods.size()]
		available_mods.erase(mod_id)

		var mod_def: Dictionary = WEAPON_MODIFIERS[mod_id]
		var value: float = randf_range(mod_def.min, mod_def.max) * rarity_mult
		mods.append({
			"id": mod_id,
			"name": mod_def.name,
			"stat": mod_def.stat,
			"value": value,
			"type": mod_def.type
		})

	var weapon := {
		"type": "weapon",
		"weapon_type": weapon_type,
		"def_id": "weapon_%s_%d" % [weapon_type, randi()],
		"name": full_name,
		"rarity": rarity,
		"damage": damage,
		"fire_rate": fire_rate,
		"mag_size": mag_size,
		"reload_time": reload_time,
		"accuracy": accuracy,
		"modifiers": mods,
		"durability": 1.0,
		"value": _calculate_weapon_value(rarity, mod_count),
	}

	loot_generated.emit(weapon)
	return weapon


## Generate a random trinket
func generate_trinket(force_rarity: String = "", luck_bonus: float = 0.0) -> Dictionary:
	var rarity := force_rarity if force_rarity != "" else roll_rarity(luck_bonus)
	var rarity_mult: float = RARITY_MULT[rarity]

	# Pick random base
	var base: Dictionary = TRINKET_BASES[randi() % TRINKET_BASES.size()]

	# Generate name
	var prefix: String = TRINKET_PREFIXES[randi() % TRINKET_PREFIXES.size()]
	var suffix: String = TRINKET_SUFFIXES[randi() % TRINKET_SUFFIXES.size()]
	var full_name := prefix + " " + base.name

	if rarity in ["rare", "epic", "legendary"]:
		full_name = full_name + " " + suffix

	# Generate effects
	var effects: Array = []
	var effect_count := 1 + RARITY_MOD_COUNT[rarity]
	var available_effects := TRINKET_EFFECTS.keys()

	for i in range(effect_count):
		if available_effects.is_empty():
			break
		var effect_id: String = available_effects[randi() % available_effects.size()]
		available_effects.erase(effect_id)

		var effect_def: Dictionary = TRINKET_EFFECTS[effect_id]
		var value: float = randf_range(effect_def.min, effect_def.max) * rarity_mult
		effects.append({
			"id": effect_id,
			"name": effect_def.name,
			"stat": effect_def.stat,
			"value": value,
			"type": effect_def.type
		})

	var trinket := {
		"type": "trinket",
		"def_id": "trinket_%s_%d" % [base.slot, randi()],
		"name": full_name,
		"slot": base.slot,
		"rarity": rarity,
		"effects": effects,
		"value": _calculate_trinket_value(rarity, effect_count),
	}

	loot_generated.emit(trinket)
	return trinket


## Generate random armor piece
func generate_armor(slot: String = "", force_rarity: String = "", luck_bonus: float = 0.0) -> Dictionary:
	# Pick random slot if not specified
	if slot == "" or slot not in ARMOR_SLOTS:
		var slots := ARMOR_SLOTS.keys()
		slot = slots[randi() % slots.size()]

	var base: Dictionary = ARMOR_SLOTS[slot]
	var rarity := force_rarity if force_rarity != "" else roll_rarity(luck_bonus)
	var rarity_mult: float = RARITY_MULT[rarity]

	# Generate name
	var prefix: String = ARMOR_PREFIXES[randi() % ARMOR_PREFIXES.size()]
	var base_name: String = base.names[randi() % base.names.size()]
	var full_name := prefix + " " + base_name

	# Calculate stats
	var armor: int = int(base.base_armor * rarity_mult * randf_range(0.9, 1.1))
	var durability: int = int(base.base_durability * rarity_mult * randf_range(0.9, 1.1))

	# Generate bonus effects for higher rarities
	var effects: Array = []
	if rarity in ["rare", "epic", "legendary"]:
		var effect_count := RARITY_MOD_COUNT[rarity] - 1
		var available_effects := ["move_speed", "stamina_boost", "damage_resist", "health_boost"]

		for i in range(effect_count):
			if available_effects.is_empty():
				break
			var effect_id: String = available_effects[randi() % available_effects.size()]
			available_effects.erase(effect_id)

			var effect_def: Dictionary = TRINKET_EFFECTS.get(effect_id, {})
			if not effect_def.is_empty():
				var value: float = randf_range(effect_def.min, effect_def.max) * rarity_mult * 0.5
				effects.append({
					"id": effect_id,
					"name": effect_def.name,
					"stat": effect_def.stat,
					"value": value,
					"type": effect_def.type
				})

	var armor_piece := {
		"type": "armor",
		"def_id": "armor_%s_%d" % [slot, randi()],
		"name": full_name,
		"slot": slot,
		"rarity": rarity,
		"armor": armor,
		"max_durability": durability,
		"current_durability": durability,
		"effects": effects,
		"value": _calculate_armor_value(rarity, armor),
	}

	loot_generated.emit(armor_piece)
	return armor_piece


## Generate random consumable
func generate_consumable(consumable_type: String = "") -> Dictionary:
	# Pick random consumable if not specified
	if consumable_type == "" or consumable_type not in CONSUMABLES:
		var types := CONSUMABLES.keys()
		consumable_type = types[randi() % types.size()]

	var base: Dictionary = CONSUMABLES[consumable_type]

	var consumable := {
		"type": "consumable",
		"consumable_type": consumable_type,
		"def_id": consumable_type,
		"name": base.name,
		"rarity": "common",
		"effect": base.effect,
		"value": base.value,
		"duration": base.get("duration", 0.0),
		"use_time": base.use_time,
		"stack": 1,
		"sell_value": 10,
	}

	loot_generated.emit(consumable)
	return consumable


## Generate ammo
func generate_ammo(ammo_type: String = "", count: int = 0) -> Dictionary:
	var ammo_types := ["pistol_ammo", "rifle_ammo", "shotgun_ammo", "sniper_ammo"]

	if ammo_type == "" or ammo_type not in ammo_types:
		ammo_type = ammo_types[randi() % ammo_types.size()]

	if count <= 0:
		count = randi_range(10, 60)

	var ammo := {
		"type": "ammo",
		"def_id": ammo_type,
		"name": ammo_type.replace("_", " ").capitalize(),
		"rarity": "common",
		"stack": count,
		"sell_value": count / 5,
	}

	loot_generated.emit(ammo)
	return ammo


## Generate random loot drop for zombie kill
func generate_zombie_loot(zombie_type: int, wave: int = 1, luck_bonus: float = 0.0) -> Array:
	var loot: Array = []

	# Base drop chance (increases with wave)
	var drop_chance := 0.3 + wave * 0.02

	# Zombie type bonuses
	var bonus_mult := 1.0
	match zombie_type:
		1:  # Runner
			bonus_mult = 1.1
		2:  # Brute
			bonus_mult = 1.5
			drop_chance += 0.2
		3:  # Crawler
			bonus_mult = 0.8
		4:  # Spitter
			bonus_mult = 1.3
		5:  # Screamer
			bonus_mult = 1.4
			drop_chance += 0.15
		6:  # Exploder
			bonus_mult = 1.2
		7:  # Boss
			bonus_mult = 3.0
			drop_chance = 1.0  # Boss always drops loot

	# Roll for drops
	if randf() < drop_chance:
		# Determine what to drop
		var roll := randf()

		if roll < 0.4:
			# Ammo
			loot.append(generate_ammo())
		elif roll < 0.6:
			# Consumable
			loot.append(generate_consumable())
		elif roll < 0.8:
			# Weapon (rarer)
			loot.append(generate_weapon("", "", luck_bonus * bonus_mult))
		elif roll < 0.9:
			# Armor
			loot.append(generate_armor("", "", luck_bonus * bonus_mult))
		else:
			# Trinket (rarest from regular zombies)
			loot.append(generate_trinket("", luck_bonus * bonus_mult))

	# Boss guaranteed extra drops
	if zombie_type == 7:
		loot.append(generate_weapon("", "rare", luck_bonus))
		if randf() > 0.5:
			loot.append(generate_trinket("", luck_bonus))

	return loot


## Calculate weapon sell value
func _calculate_weapon_value(rarity: String, mod_count: int) -> int:
	var base_value := 50
	match rarity:
		"uncommon": base_value = 100
		"rare": base_value = 250
		"epic": base_value = 500
		"legendary": base_value = 1000
	return base_value + mod_count * 25


## Calculate trinket sell value
func _calculate_trinket_value(rarity: String, effect_count: int) -> int:
	var base_value := 30
	match rarity:
		"uncommon": base_value = 80
		"rare": base_value = 200
		"epic": base_value = 400
		"legendary": base_value = 800
	return base_value + effect_count * 20


## Calculate armor sell value
func _calculate_armor_value(rarity: String, armor: int) -> int:
	var base_value := 40
	match rarity:
		"uncommon": base_value = 90
		"rare": base_value = 220
		"epic": base_value = 450
		"legendary": base_value = 900
	return base_value + armor * 2


## Get rarity color
func get_rarity_color(rarity: String) -> Color:
	return RARITY_COLORS.get(rarity, RARITY_COLORS.common)


## Format item tooltip text
func format_item_tooltip(item: Dictionary) -> String:
	var lines: Array[String] = []

	lines.append("[%s] %s" % [item.rarity.to_upper(), item.name])

	if item.type == "weapon":
		lines.append("Damage: %d" % item.damage)
		lines.append("Fire Rate: %.1f/s" % item.fire_rate)
		lines.append("Magazine: %d" % item.mag_size)
		lines.append("Accuracy: %d%%" % int(item.accuracy * 100))

		if not item.modifiers.is_empty():
			lines.append("")
			for mod in item.modifiers:
				var value_str := "+%d" % int(mod.value) if mod.type == "flat" else "+%d%%" % int(mod.value)
				lines.append("%s %s" % [mod.name, value_str])

	elif item.type == "trinket":
		for effect in item.effects:
			var value_str := "+%.1f" % effect.value if effect.type == "flat" else "+%d%%" % int(effect.value)
			lines.append("%s %s" % [effect.name, value_str])

	elif item.type == "armor":
		lines.append("Armor: %d" % item.armor)
		lines.append("Durability: %d/%d" % [item.current_durability, item.max_durability])

		if not item.effects.is_empty():
			lines.append("")
			for effect in item.effects:
				var value_str := "+%.1f" % effect.value if effect.type == "flat" else "+%d%%" % int(effect.value)
				lines.append("%s %s" % [effect.name, value_str])

	elif item.type == "consumable":
		lines.append("Effect: %s" % item.effect)
		if item.duration > 0:
			lines.append("Duration: %.0fs" % item.duration)

	lines.append("")
	lines.append("Value: %d gold" % item.get("value", item.get("sell_value", 0)))

	return "\n".join(lines)
