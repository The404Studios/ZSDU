extends RefCounted
class_name EquipmentRuntime
## EquipmentRuntime - Character equipment slots
##
## Manages equipped gear (armor, rig, backpack, accessories).
## This is separate from weapons which are in InventoryRuntime.
##
## Slots:
## - Helmet (head protection, visor)
## - Armor (body protection)
## - Rig (tactical rig with container slots)
## - Backpack (storage, weight)
## - Pendant (passive buffs)
## - Ring1, Ring2 (passive buffs)
## - Gloves (interaction bonuses)
## - Boots (movement bonuses)

signal equipment_changed(slot: String, item: Dictionary)
signal stats_updated(total_stats: Dictionary)

# Equipment slots
enum EquipSlot {
	HELMET,
	ARMOR,
	RIG,
	BACKPACK,
	PENDANT,
	RING_1,
	RING_2,
	GLOVES,
	BOOTS
}

# Slot names for serialization
const SLOT_NAMES := {
	EquipSlot.HELMET: "helmet",
	EquipSlot.ARMOR: "armor",
	EquipSlot.RIG: "rig",
	EquipSlot.BACKPACK: "backpack",
	EquipSlot.PENDANT: "pendant",
	EquipSlot.RING_1: "ring_1",
	EquipSlot.RING_2: "ring_2",
	EquipSlot.GLOVES: "gloves",
	EquipSlot.BOOTS: "boots",
}

# Current equipment (slot -> item data)
var equipped: Dictionary = {}

# Cached total stats from all equipment
var total_stats: Dictionary = {
	# Protection
	"armor_rating": 0.0,       # Damage reduction %
	"head_armor": 0.0,         # Head-specific protection
	"blunt_protection": 0.0,   # vs blunt damage
	"pierce_protection": 0.0,  # vs pierce damage

	# Capacity
	"container_slots": 0,      # Extra inventory slots from rig
	"backpack_capacity": 0,    # Weight capacity from backpack

	# Movement
	"speed_modifier": 1.0,     # Movement speed multiplier
	"stamina_modifier": 1.0,   # Stamina drain multiplier
	"noise_modifier": 1.0,     # Movement noise

	# Interaction
	"loot_speed": 1.0,         # Looting speed
	"barricade_speed": 1.0,    # Nailing/repair speed

	# Passive bonuses (from accessories)
	"health_regen": 0.0,       # HP/second
	"stamina_regen": 0.0,      # Extra stamina regen
	"xp_bonus": 0.0,           # XP gain multiplier
	"luck": 0.0,               # Loot quality modifier
}


func _init() -> void:
	_clear_equipment()


## Clear all equipment
func _clear_equipment() -> void:
	equipped = {
		"helmet": {},
		"armor": {},
		"rig": {},
		"backpack": {},
		"pendant": {},
		"ring_1": {},
		"ring_2": {},
		"gloves": {},
		"boots": {},
	}
	_recalculate_stats()


## Equip an item to a slot
func equip_item(slot: String, item: Dictionary) -> bool:
	if slot not in equipped:
		push_warning("[Equipment] Invalid slot: %s" % slot)
		return false

	# Validate item can go in this slot
	var item_slot: String = item.get("slot", "")
	if item_slot != slot and item_slot != "":
		push_warning("[Equipment] Item %s cannot go in slot %s" % [item.get("def_id", "?"), slot])
		return false

	equipped[slot] = item
	_recalculate_stats()

	equipment_changed.emit(slot, item)
	return true


## Unequip item from slot
func unequip_item(slot: String) -> Dictionary:
	if slot not in equipped:
		return {}

	var item: Dictionary = equipped[slot]
	equipped[slot] = {}
	_recalculate_stats()

	equipment_changed.emit(slot, {})
	return item


## Get item in slot
func get_equipped(slot: String) -> Dictionary:
	return equipped.get(slot, {})


## Check if slot has item
func has_equipped(slot: String) -> bool:
	var item: Dictionary = equipped.get(slot, {})
	return not item.is_empty()


## Get all equipped items
func get_all_equipped() -> Dictionary:
	return equipped.duplicate()


## Get total stats from all equipment
func get_total_stats() -> Dictionary:
	return total_stats.duplicate()


## Get specific stat
func get_stat(stat_name: String) -> float:
	return total_stats.get(stat_name, 0.0)


## Initialize from loadout data (from backend)
func initialize_from_loadout(loadout: Dictionary) -> void:
	_clear_equipment()

	# Load each slot from loadout
	for slot in equipped.keys():
		var item_data: Dictionary = loadout.get(slot, {})
		if not item_data.is_empty():
			equipped[slot] = item_data

	_recalculate_stats()
	print("[Equipment] Loaded %d equipped items" % _count_equipped())


## Count non-empty equipment slots
func _count_equipped() -> int:
	var count := 0
	for slot in equipped:
		if not equipped[slot].is_empty():
			count += 1
	return count


## Recalculate all stats from equipment
func _recalculate_stats() -> void:
	# Reset to defaults
	total_stats = {
		"armor_rating": 0.0,
		"head_armor": 0.0,
		"blunt_protection": 0.0,
		"pierce_protection": 0.0,
		"container_slots": 0,
		"backpack_capacity": 0,
		"speed_modifier": 1.0,
		"stamina_modifier": 1.0,
		"noise_modifier": 1.0,
		"loot_speed": 1.0,
		"barricade_speed": 1.0,
		"health_regen": 0.0,
		"stamina_regen": 0.0,
		"xp_bonus": 0.0,
		"luck": 0.0,
	}

	# Accumulate stats from each item
	for slot in equipped:
		var item: Dictionary = equipped[slot]
		if item.is_empty():
			continue

		var stats: Dictionary = item.get("stats", {})

		# Add protection stats
		total_stats["armor_rating"] += stats.get("armor_rating", 0.0)
		total_stats["head_armor"] += stats.get("head_armor", 0.0)
		total_stats["blunt_protection"] += stats.get("blunt_protection", 0.0)
		total_stats["pierce_protection"] += stats.get("pierce_protection", 0.0)

		# Add capacity stats
		total_stats["container_slots"] += stats.get("container_slots", 0)
		total_stats["backpack_capacity"] += stats.get("backpack_capacity", 0)

		# Multiply movement modifiers
		total_stats["speed_modifier"] *= stats.get("speed_modifier", 1.0)
		total_stats["stamina_modifier"] *= stats.get("stamina_modifier", 1.0)
		total_stats["noise_modifier"] *= stats.get("noise_modifier", 1.0)

		# Multiply interaction modifiers
		total_stats["loot_speed"] *= stats.get("loot_speed", 1.0)
		total_stats["barricade_speed"] *= stats.get("barricade_speed", 1.0)

		# Add passive bonuses
		total_stats["health_regen"] += stats.get("health_regen", 0.0)
		total_stats["stamina_regen"] += stats.get("stamina_regen", 0.0)
		total_stats["xp_bonus"] += stats.get("xp_bonus", 0.0)
		total_stats["luck"] += stats.get("luck", 0.0)

	stats_updated.emit(total_stats)


## Calculate damage after armor reduction
func apply_armor(damage: float, damage_type: String = "bullet", is_headshot: bool = false) -> float:
	var reduction := 0.0

	# Apply body armor
	if not is_headshot:
		reduction = total_stats["armor_rating"]

		# Apply damage type modifiers
		match damage_type:
			"blunt":
				reduction += total_stats["blunt_protection"]
			"pierce":
				reduction += total_stats["pierce_protection"]
	else:
		# Headshots use head armor only
		reduction = total_stats["head_armor"]

	# Clamp reduction (can't reduce more than 90%)
	reduction = clampf(reduction, 0.0, 0.9)

	return damage * (1.0 - reduction)


## Get container slots from rig
func get_container_slots() -> int:
	return int(total_stats["container_slots"])


## Get backpack capacity
func get_backpack_capacity() -> int:
	return int(total_stats["backpack_capacity"])


## Get movement speed modifier
func get_speed_modifier() -> float:
	return total_stats["speed_modifier"]


## Serialize for network
func get_network_state() -> Dictionary:
	var state := {}
	for slot in equipped:
		if not equipped[slot].is_empty():
			state[slot] = {
				"iid": equipped[slot].get("iid", ""),
				"def_id": equipped[slot].get("def_id", ""),
			}
	return state


## Apply network state
func apply_network_state(state: Dictionary) -> void:
	for slot in state:
		if slot in equipped:
			equipped[slot] = state[slot]
	_recalculate_stats()


## Setup default equipment for testing
func setup_default_equipment() -> void:
	# Basic armor
	equipped["armor"] = {
		"iid": "default_armor",
		"def_id": "basic_vest",
		"name": "Basic Vest",
		"slot": "armor",
		"stats": {
			"armor_rating": 0.15,  # 15% damage reduction
			"speed_modifier": 0.95,  # 5% slower
		}
	}

	# Basic rig
	equipped["rig"] = {
		"iid": "default_rig",
		"def_id": "tactical_rig",
		"name": "Tactical Rig",
		"slot": "rig",
		"stats": {
			"container_slots": 8,
		}
	}

	# Work gloves (faster barricading)
	equipped["gloves"] = {
		"iid": "default_gloves",
		"def_id": "work_gloves",
		"name": "Work Gloves",
		"slot": "gloves",
		"stats": {
			"barricade_speed": 1.25,  # 25% faster nailing
		}
	}

	_recalculate_stats()
	print("[Equipment] Set up default equipment")
