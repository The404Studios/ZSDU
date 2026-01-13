extends Node
class_name InventoryRuntime
## InventoryRuntime - Ephemeral in-raid inventory
##
## Handles:
## - Track equipped weapon
## - Track mags & ammo during raid
## - Respond to animation events
## - Serialize into raid commit payload
##
## Does NOT:
## - Talk to backend
## - Modify stash
## - Persist anything
##
## This node is destroyed when raid ends.

signal weapon_equipped(slot: int, weapon: WeaponRuntime)
signal ammo_changed(ammo_type: String, count: int)
signal loot_picked_up(def_id: String, stack: int)
signal loadout_ready()

# Weapon slots (primary, secondary, melee)
var weapons: Array[WeaponRuntime] = [null, null, null]
var current_weapon_slot: int = 0

# Ammo storage (ammo_type -> count)
var ammo: Dictionary = {}

# Mags storage (for detailed mag simulation)
# mag_id -> { ammo_type, capacity, current }
var magazines: Dictionary = {}

# Provisional loot (picked up during raid, not yet committed)
var provisional_loot: Array[Dictionary] = []

# Loadout data (from EconomyService)
var loadout_iids: Dictionary = {}  # slot -> iid

# Character info
var character_id: String = ""
var raid_id: String = ""


func _ready() -> void:
	# Connect to animation events if we have an animation controller sibling
	var anim_controller := get_parent().get_node_or_null("AnimationController")
	if anim_controller and anim_controller is AnimationController:
		anim_controller.anim_event.connect(on_anim_event)


## Initialize from loadout (called when raid starts)
func initialize_from_loadout(loadout: Dictionary, p_character_id: String, p_raid_id: String) -> void:
	character_id = p_character_id
	raid_id = p_raid_id
	loadout_iids = loadout.duplicate()

	# Clear existing state
	weapons = [null, null, null]
	ammo.clear()
	magazines.clear()
	provisional_loot.clear()

	# Load weapons from loadout
	for slot_name in loadout:
		var iid: String = loadout[slot_name]
		var item_data = EconomyService.get_item(iid) if EconomyService else null
		if not item_data or item_data.is_empty():
			continue

		var def_id: String = item_data.get("def_id", item_data.get("defId", ""))
		var item_def: Dictionary = EconomyService.get_item_def(def_id) if EconomyService else {}

		match slot_name:
			"primary":
				weapons[0] = _create_weapon_runtime(item_data, item_def, 0)
			"secondary":
				weapons[1] = _create_weapon_runtime(item_data, item_def, 1)
			"melee":
				weapons[2] = _create_weapon_runtime(item_data, item_def, 2)
			"armor":
				# Armor handled separately
				pass
			"rig":
				# Rig provides container slots
				pass
			"backpack":
				# Backpack provides container slots
				pass

	loadout_ready.emit()


## Create weapon runtime from item data
func _create_weapon_runtime(item_data: Dictionary, item_def: Dictionary, slot: int) -> WeaponRuntime:
	var weapon := WeaponRuntime.new()
	weapon.initialize(item_data, item_def)
	weapons[slot] = weapon
	return weapon


## Get weapon in slot
func get_weapon(slot: int) -> WeaponRuntime:
	if slot >= 0 and slot < weapons.size():
		return weapons[slot]
	return null


## Get current weapon
func get_current_weapon() -> WeaponRuntime:
	return get_weapon(current_weapon_slot)


## Check if we have ammo of type
func has_ammo(ammo_type: String) -> bool:
	return ammo.get(ammo_type, 0) > 0


## Get ammo count
func get_ammo_count(ammo_type: String) -> int:
	return ammo.get(ammo_type, 0)


## Consume ammo
func consume_ammo(ammo_type: String, count: int) -> int:
	var available: int = ammo.get(ammo_type, 0)
	var consumed: int = mini(available, count)
	ammo[ammo_type] = available - consumed
	ammo_changed.emit(ammo_type, ammo[ammo_type])
	return consumed


## Add ammo (from pickup)
func add_ammo(ammo_type: String, count: int) -> void:
	ammo[ammo_type] = ammo.get(ammo_type, 0) + count
	ammo_changed.emit(ammo_type, ammo[ammo_type])


## Check if we have a mag for weapon
func has_mag() -> bool:
	# Simplified: just check if we have ammo for current weapon
	var weapon := get_current_weapon()
	if weapon:
		return has_ammo(weapon.ammo_type)
	return false


## Handle animation events
## These events are triggered by animation method tracks at specific frames
func on_anim_event(event_name: String) -> void:
	match event_name:
		"remove_mag":
			_detach_mag()
		"insert_mag":
			_attach_mag()
		"chamber":
			_chamber_round()
		"reload_done":
			_reload_done()


## Called when magazine is visually removed from weapon
func _detach_mag() -> void:
	var weapon := get_current_weapon()
	if weapon:
		# Store remaining ammo from old mag (could be returned to inventory)
		var remaining := weapon.current_ammo
		if remaining > 0:
			# Partial mag - could track this for tactical reload systems
			pass
		weapon.current_ammo = 0
		weapon.chambered = false


## Called when new magazine is visually inserted
func _attach_mag() -> void:
	var weapon := get_current_weapon()
	if not weapon:
		return

	# Transfer ammo from reserves to weapon
	var needed := weapon.magazine_size
	var available := get_ammo_count(weapon.ammo_type)
	var transfer := mini(needed, available)

	if transfer > 0:
		consume_ammo(weapon.ammo_type, transfer)
		weapon.add_ammo(transfer)


## Called when bolt/slide is racked to chamber a round
func _chamber_round() -> void:
	var weapon := get_current_weapon()
	if weapon:
		weapon.chamber()


## Called when reload animation completes
func _reload_done() -> void:
	# Final cleanup after reload
	var weapon := get_current_weapon()
	if weapon and weapon.current_ammo > 0:
		weapon.chambered = true


## Pick up loot during raid
func pickup_loot(def_id: String, stack: int = 1, durability: float = 1.0, mods: Array = []) -> bool:
	# Check if we have space (simplified: always allow for now)
	var loot_entry := {
		"def_id": def_id,
		"stack": stack,
		"durability": durability,
		"mods": mods,
	}

	provisional_loot.append(loot_entry)
	loot_picked_up.emit(def_id, stack)

	# Report to RaidManager
	if RaidManager and NetworkManager and NetworkManager.is_authority():
		var parent = get_parent()
		if parent:
			var peer_id = parent.get("peer_id")
			if peer_id:
				RaidManager.add_provisional_loot(peer_id, def_id, stack, durability, mods)

	return true


## Get provisional loot for raid commit
func get_provisional_loot() -> Array:
	return provisional_loot.duplicate()


## Get state for network sync
func get_state() -> Dictionary:
	var weapon_states := []
	for weapon in weapons:
		if weapon:
			weapon_states.append(weapon.get_state())
		else:
			weapon_states.append({})

	return {
		"slot": current_weapon_slot,
		"weapons": weapon_states,
		"ammo": ammo.duplicate(),
		"loot_count": provisional_loot.size(),
	}


## Apply state from network
func apply_state(state: Dictionary) -> void:
	current_weapon_slot = state.get("slot", current_weapon_slot)

	var weapon_states: Array = state.get("weapons", [])
	for i in range(mini(weapon_states.size(), weapons.size())):
		if weapons[i] and not weapon_states[i].is_empty():
			weapons[i].apply_state(weapon_states[i])

	if "ammo" in state:
		ammo = state.ammo.duplicate()


## Clean up (called when raid ends)
func cleanup() -> void:
	for weapon in weapons:
		if weapon:
			weapon.free()
	weapons = [null, null, null]
	ammo.clear()
	magazines.clear()
	provisional_loot.clear()


## Setup default loadout for testing/development
## Called when no RaidManager/EconomyService loadout is available
func setup_default_loadout() -> void:
	# Clear existing
	weapons = [null, null, null]
	ammo.clear()

	# Create default assault rifle
	var rifle := WeaponRuntime.new()
	rifle.def_id = "default_rifle"
	rifle.name = "Assault Rifle"
	rifle.damage = 25.0
	rifle.fire_rate = 0.1
	rifle.magazine_size = 30
	rifle.reload_time = 2.5
	rifle.base_spread = 0.02
	rifle.ads_spread_mult = 0.3
	rifle.ammo_type = "5.56"
	rifle.weapon_type = "rifle"
	rifle.current_ammo = 30
	rifle.chambered = true
	rifle.durability = 1.0
	weapons[0] = rifle

	# Create default pistol
	var pistol := WeaponRuntime.new()
	pistol.def_id = "default_pistol"
	pistol.name = "Pistol"
	pistol.damage = 20.0
	pistol.fire_rate = 0.15
	pistol.magazine_size = 15
	pistol.reload_time = 1.5
	pistol.base_spread = 0.03
	pistol.ads_spread_mult = 0.4
	pistol.ammo_type = "9mm"
	pistol.weapon_type = "pistol"
	pistol.current_ammo = 15
	pistol.chambered = true
	pistol.durability = 1.0
	weapons[1] = pistol

	# Create default melee knife
	var knife := WeaponRuntime.new()
	knife.def_id = "default_knife"
	knife.name = "Combat Knife"
	knife.damage = 35.0
	knife.fire_rate = 0.5
	knife.magazine_size = 0
	knife.reload_time = 0.0
	knife.base_spread = 0.0
	knife.ammo_type = ""
	knife.weapon_type = "melee"
	knife.current_ammo = 0
	knife.chambered = true
	knife.durability = 1.0
	weapons[2] = knife

	# Give starting ammo
	ammo["5.56"] = 120
	ammo["9mm"] = 60

	current_weapon_slot = 0
	loadout_ready.emit()
	print("[InventoryRuntime] Default loadout initialized")
