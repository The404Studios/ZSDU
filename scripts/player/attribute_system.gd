extends RefCounted
class_name AttributeSystem
## AttributeSystem - Character attributes and stat calculations
##
## Core attributes affect all gameplay aspects:
## - STRENGTH: Melee damage, carry weight, barricade HP
## - AGILITY: Move speed, reload speed, ADS speed
## - ENDURANCE: Max HP, stamina, stamina regen
## - INTELLECT: XP gain, skill cooldowns, crafting speed
## - LUCK: Crit chance, loot quality, proc chances
##
## Attributes can be modified by:
## - Base level (permanent)
## - Equipment bonuses
## - Buffs/debuffs (temporary)
## - Skills/perks (unlockable)

signal attribute_changed(attribute: String, old_value: int, new_value: int)
signal derived_stats_updated(stats: Dictionary)
signal level_up(new_level: int, attribute_points: int)
signal buff_applied(buff_id: String, attribute: String, amount: int)
signal buff_expired(buff_id: String)

# Core attributes
enum Attribute {
	STRENGTH,
	AGILITY,
	ENDURANCE,
	INTELLECT,
	LUCK
}

const ATTRIBUTE_NAMES := {
	Attribute.STRENGTH: "Strength",
	Attribute.AGILITY: "Agility",
	Attribute.ENDURANCE: "Endurance",
	Attribute.INTELLECT: "Intellect",
	Attribute.LUCK: "Luck"
}

const ATTRIBUTE_ABBREV := {
	Attribute.STRENGTH: "STR",
	Attribute.AGILITY: "AGI",
	Attribute.ENDURANCE: "END",
	Attribute.INTELLECT: "INT",
	Attribute.LUCK: "LCK"
}

const ATTRIBUTE_COLORS := {
	Attribute.STRENGTH: Color(0.9, 0.3, 0.3),   # Red
	Attribute.AGILITY: Color(0.3, 0.9, 0.3),    # Green
	Attribute.ENDURANCE: Color(0.9, 0.6, 0.2),  # Orange
	Attribute.INTELLECT: Color(0.3, 0.5, 0.9),  # Blue
	Attribute.LUCK: Color(0.9, 0.8, 0.2)        # Gold
}

const ATTRIBUTE_ICONS := {
	Attribute.STRENGTH: "res://assets/icons/attr_strength.png",
	Attribute.AGILITY: "res://assets/icons/attr_agility.png",
	Attribute.ENDURANCE: "res://assets/icons/attr_endurance.png",
	Attribute.INTELLECT: "res://assets/icons/attr_intellect.png",
	Attribute.LUCK: "res://assets/icons/attr_luck.png"
}

# Attribute descriptions for tooltips
const ATTRIBUTE_DESCRIPTIONS := {
	Attribute.STRENGTH: "Increases melee damage, carry capacity, and barricade durability.",
	Attribute.AGILITY: "Improves movement speed, reload speed, and aim-down-sights speed.",
	Attribute.ENDURANCE: "Boosts maximum health, stamina pool, and stamina regeneration.",
	Attribute.INTELLECT: "Enhances XP gain, reduces skill cooldowns, and speeds up interactions.",
	Attribute.LUCK: "Raises critical hit chance, improves loot quality, and increases proc rates."
}

# Base attribute values (level 1)
const BASE_ATTRIBUTE := 10
const MAX_ATTRIBUTE := 100
const POINTS_PER_LEVEL := 3

# Current character level
var level: int = 1
var experience: int = 0
var attribute_points: int = 0

# Base attributes (permanent, from leveling)
var base_attributes: Dictionary = {
	Attribute.STRENGTH: BASE_ATTRIBUTE,
	Attribute.AGILITY: BASE_ATTRIBUTE,
	Attribute.ENDURANCE: BASE_ATTRIBUTE,
	Attribute.INTELLECT: BASE_ATTRIBUTE,
	Attribute.LUCK: BASE_ATTRIBUTE
}

# Bonus attributes (from equipment, buffs, etc.)
var equipment_bonuses: Dictionary = {}
var buff_bonuses: Dictionary = {}
var perk_bonuses: Dictionary = {}

# Active buffs (buff_id -> {attribute, amount, expires_at})
var active_buffs: Dictionary = {}

# Cached derived stats
var derived_stats: Dictionary = {}


func _init() -> void:
	_recalculate_derived_stats()


## Get total attribute value (base + all bonuses)
func get_attribute(attr: Attribute) -> int:
	var total := base_attributes.get(attr, BASE_ATTRIBUTE)
	total += equipment_bonuses.get(attr, 0)
	total += _get_buff_bonus(attr)
	total += perk_bonuses.get(attr, 0)
	return clampi(total, 1, MAX_ATTRIBUTE)


## Get base attribute (without bonuses)
func get_base_attribute(attr: Attribute) -> int:
	return base_attributes.get(attr, BASE_ATTRIBUTE)


## Get attribute by name string
func get_attribute_by_name(name: String) -> int:
	match name.to_lower():
		"strength", "str": return get_attribute(Attribute.STRENGTH)
		"agility", "agi": return get_attribute(Attribute.AGILITY)
		"endurance", "end": return get_attribute(Attribute.ENDURANCE)
		"intellect", "int": return get_attribute(Attribute.INTELLECT)
		"luck", "lck": return get_attribute(Attribute.LUCK)
	return BASE_ATTRIBUTE


## Increase base attribute (when leveling up)
func increase_attribute(attr: Attribute, amount: int = 1) -> bool:
	if attribute_points < amount:
		return false

	if base_attributes[attr] + amount > MAX_ATTRIBUTE:
		return false

	var old_value := base_attributes[attr]
	base_attributes[attr] += amount
	attribute_points -= amount

	_recalculate_derived_stats()
	attribute_changed.emit(ATTRIBUTE_NAMES[attr], old_value, base_attributes[attr])
	return true


## Set equipment bonuses (called when equipment changes)
func set_equipment_bonuses(bonuses: Dictionary) -> void:
	equipment_bonuses = bonuses.duplicate()
	_recalculate_derived_stats()


## Apply a temporary buff
func apply_buff(buff_id: String, attr: Attribute, amount: int, duration: float) -> void:
	var expires_at := Time.get_unix_time_from_system() + duration

	active_buffs[buff_id] = {
		"attribute": attr,
		"amount": amount,
		"expires_at": expires_at
	}

	_recalculate_derived_stats()
	buff_applied.emit(buff_id, ATTRIBUTE_NAMES[attr], amount)


## Remove a buff
func remove_buff(buff_id: String) -> void:
	if buff_id in active_buffs:
		active_buffs.erase(buff_id)
		_recalculate_derived_stats()
		buff_expired.emit(buff_id)


## Get total buff bonus for an attribute
func _get_buff_bonus(attr: Attribute) -> int:
	var total := 0
	var current_time := Time.get_unix_time_from_system()

	for buff_id in active_buffs.keys():
		var buff: Dictionary = active_buffs[buff_id]
		if buff.attribute == attr:
			if buff.expires_at > current_time:
				total += buff.amount
			else:
				# Buff expired, remove it
				call_deferred("remove_buff", buff_id)

	return total


## Add experience and check for level up
func add_experience(amount: int) -> void:
	# Apply intellect bonus to XP
	var xp_mult := get_derived_stat("xp_multiplier")
	var actual_xp := int(amount * xp_mult)

	experience += actual_xp

	# Check for level up
	var xp_required := _get_xp_for_level(level + 1)
	while experience >= xp_required and level < 100:
		experience -= xp_required
		level += 1
		attribute_points += POINTS_PER_LEVEL

		level_up.emit(level, attribute_points)
		xp_required = _get_xp_for_level(level + 1)


## Get XP required for a level
func _get_xp_for_level(target_level: int) -> int:
	# Exponential curve: 100 * level^1.5
	return int(100 * pow(target_level, 1.5))


## Recalculate all derived stats from attributes
func _recalculate_derived_stats() -> void:
	var str_val := get_attribute(Attribute.STRENGTH)
	var agi_val := get_attribute(Attribute.AGILITY)
	var end_val := get_attribute(Attribute.ENDURANCE)
	var int_val := get_attribute(Attribute.INTELLECT)
	var lck_val := get_attribute(Attribute.LUCK)

	derived_stats = {
		# Strength-based
		"melee_damage_mult": 1.0 + (str_val - BASE_ATTRIBUTE) * 0.02,  # +2% per point
		"carry_weight": 50 + str_val * 2,  # Base 50 + 2 per STR
		"barricade_hp_mult": 1.0 + (str_val - BASE_ATTRIBUTE) * 0.015,  # +1.5% per point

		# Agility-based
		"move_speed_mult": 1.0 + (agi_val - BASE_ATTRIBUTE) * 0.01,  # +1% per point
		"reload_speed_mult": 1.0 + (agi_val - BASE_ATTRIBUTE) * 0.015,  # +1.5% per point
		"ads_speed_mult": 1.0 + (agi_val - BASE_ATTRIBUTE) * 0.02,  # +2% per point
		"sprint_speed_mult": 1.0 + (agi_val - BASE_ATTRIBUTE) * 0.015,

		# Endurance-based
		"max_health": 100 + (end_val - BASE_ATTRIBUTE) * 5,  # +5 HP per point
		"max_stamina": 100 + (end_val - BASE_ATTRIBUTE) * 3,  # +3 stamina per point
		"stamina_regen_mult": 1.0 + (end_val - BASE_ATTRIBUTE) * 0.02,  # +2% per point
		"health_regen": (end_val - BASE_ATTRIBUTE) * 0.1,  # +0.1 HP/sec per point

		# Intellect-based
		"xp_multiplier": 1.0 + (int_val - BASE_ATTRIBUTE) * 0.02,  # +2% XP per point
		"skill_cooldown_mult": 1.0 - (int_val - BASE_ATTRIBUTE) * 0.01,  # -1% cooldown per point
		"interaction_speed_mult": 1.0 + (int_val - BASE_ATTRIBUTE) * 0.015,  # +1.5% per point

		# Luck-based
		"crit_chance": 0.05 + lck_val * 0.005,  # 5% base + 0.5% per point
		"crit_damage_mult": 1.5 + (lck_val - BASE_ATTRIBUTE) * 0.02,  # 150% base + 2% per point
		"loot_quality_mult": 1.0 + (lck_val - BASE_ATTRIBUTE) * 0.02,  # +2% per point
		"proc_chance_mult": 1.0 + (lck_val - BASE_ATTRIBUTE) * 0.01,  # +1% per point
	}

	derived_stats_updated.emit(derived_stats)


## Get a derived stat
func get_derived_stat(stat_name: String) -> float:
	return derived_stats.get(stat_name, 1.0)


## Get all attributes as dictionary
func get_all_attributes() -> Dictionary:
	return {
		"strength": get_attribute(Attribute.STRENGTH),
		"agility": get_attribute(Attribute.AGILITY),
		"endurance": get_attribute(Attribute.ENDURANCE),
		"intellect": get_attribute(Attribute.INTELLECT),
		"luck": get_attribute(Attribute.LUCK)
	}


## Get attribute info for tooltip
func get_attribute_info(attr: Attribute) -> Dictionary:
	return {
		"name": ATTRIBUTE_NAMES[attr],
		"abbrev": ATTRIBUTE_ABBREV[attr],
		"color": ATTRIBUTE_COLORS[attr],
		"icon": ATTRIBUTE_ICONS[attr],
		"description": ATTRIBUTE_DESCRIPTIONS[attr],
		"base": get_base_attribute(attr),
		"total": get_attribute(attr),
		"equipment_bonus": equipment_bonuses.get(attr, 0),
		"buff_bonus": _get_buff_bonus(attr),
		"perk_bonus": perk_bonuses.get(attr, 0)
	}


## Serialize for save/network
func serialize() -> Dictionary:
	return {
		"level": level,
		"experience": experience,
		"attribute_points": attribute_points,
		"base_attributes": base_attributes.duplicate(),
		"perk_bonuses": perk_bonuses.duplicate()
	}


## Deserialize from save/network
func deserialize(data: Dictionary) -> void:
	level = data.get("level", 1)
	experience = data.get("experience", 0)
	attribute_points = data.get("attribute_points", 0)
	base_attributes = data.get("base_attributes", base_attributes).duplicate()
	perk_bonuses = data.get("perk_bonuses", {}).duplicate()
	_recalculate_derived_stats()


## Get level progress (0.0 - 1.0)
func get_level_progress() -> float:
	var xp_required := _get_xp_for_level(level + 1)
	return float(experience) / float(xp_required)


## Setup default attributes for testing
func setup_default() -> void:
	level = 1
	experience = 0
	attribute_points = 5  # Start with some points to allocate

	base_attributes = {
		Attribute.STRENGTH: 10,
		Attribute.AGILITY: 10,
		Attribute.ENDURANCE: 10,
		Attribute.INTELLECT: 10,
		Attribute.LUCK: 10
	}

	_recalculate_derived_stats()
