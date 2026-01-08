extends Node
class_name CombatController
## CombatController - Weapons, reloads, ADS
##
## Handles:
## - Fire intent
## - Reload intent
## - ADS state
## - Cooldowns
## - Weapon binding
##
## Does NOT:
## - Apply authoritative damage (server does)
## - Decide inventory persistence
## - Handle animation timing directly

signal fire_requested(weapon_state: Dictionary)
signal reload_requested()
signal ads_changed(is_ads: bool)
signal weapon_switched(slot: int)
signal chamber_empty()
signal magazine_empty()

# State
var is_ads := false
var is_reloading := false
var is_firing := false
var fire_cooldown := 0.0

# Current weapon (runtime reference)
var current_weapon: WeaponRuntime = null
var current_slot := 0

# References
var animation_controller: AnimationController = null
var inventory_runtime: InventoryRuntime = null
var camera: Camera3D = null


func initialize(p_anim: AnimationController, p_inventory: InventoryRuntime, p_camera: Camera3D) -> void:
	animation_controller = p_anim
	inventory_runtime = p_inventory
	camera = p_camera

	# Connect animation events
	if animation_controller:
		animation_controller.anim_event.connect(_on_anim_event)


func _process(delta: float) -> void:
	# Update cooldowns
	if fire_cooldown > 0:
		fire_cooldown -= delta


## Process combat input
func process_input(input: PlayerInput) -> void:
	# ADS toggle
	if input.ads != is_ads:
		_set_ads(input.ads)

	# Fire
	if input.fire:
		_request_fire()

	# Reload
	if input.reload:
		_request_reload()

	# Weapon switch
	if input.weapon_slot >= 0:
		_switch_weapon(input.weapon_slot)


## Request fire (creates intent, actual fire happens on server validation)
func _request_fire() -> void:
	if is_reloading:
		return

	if fire_cooldown > 0:
		return

	if not current_weapon:
		return

	if not current_weapon.can_fire():
		if current_weapon.is_magazine_empty():
			magazine_empty.emit()
		elif current_weapon.is_chamber_empty():
			chamber_empty.emit()
		return

	# Consume round locally (will be validated by server)
	current_weapon.consume_round()

	# Set cooldown
	fire_cooldown = current_weapon.fire_rate

	# Build weapon state for network
	var weapon_state := {
		"slot": current_slot,
		"ads": is_ads,
		"origin": camera.global_position if camera else Vector3.ZERO,
		"direction": -camera.global_basis.z if camera else Vector3.FORWARD,
		"damage": current_weapon.damage,
		"spread": current_weapon.get_spread(is_ads),
	}

	fire_requested.emit(weapon_state)

	# Trigger animation
	if animation_controller:
		animation_controller.play_fire()


## Request reload
func _request_reload() -> void:
	if is_reloading:
		return

	if not current_weapon:
		return

	if current_weapon.is_magazine_full():
		return

	if not inventory_runtime:
		return

	# Check if we have ammo
	var ammo_type := current_weapon.ammo_type
	if not inventory_runtime.has_ammo(ammo_type):
		return

	is_reloading = true
	reload_requested.emit()

	# Trigger animation (actual reload happens via anim event)
	if animation_controller:
		animation_controller.play_reload()


## Set ADS state
func _set_ads(ads: bool) -> void:
	is_ads = ads
	ads_changed.emit(is_ads)

	if animation_controller:
		if is_ads:
			animation_controller.enter_ads()
		else:
			animation_controller.exit_ads()


## Switch weapon slot
func _switch_weapon(slot: int) -> void:
	if slot == current_slot:
		return

	if is_reloading:
		_cancel_reload()

	current_slot = slot

	# Get weapon from inventory runtime
	if inventory_runtime:
		current_weapon = inventory_runtime.get_weapon(slot)

	weapon_switched.emit(slot)

	if animation_controller:
		animation_controller.play_equip()


## Cancel reload (when switching weapons, etc.)
func _cancel_reload() -> void:
	is_reloading = false

	if animation_controller:
		animation_controller.cancel_reload()


## Handle animation events
## Reload timeline:
##   1. "remove_mag" - Magazine ejected (ammo emptied in InventoryRuntime)
##   2. "insert_mag" - New magazine inserted (ammo loaded in InventoryRuntime)
##   3. "chamber" - Round chambered (InventoryRuntime handles this)
##   4. "reload_done" - Animation complete, reload finished
func _on_anim_event(event_name: String) -> void:
	match event_name:
		"reload_done":
			_complete_reload()
		"reload_cancel":
			is_reloading = false
		"fire_end":
			is_firing = false


## Complete reload (called when reload animation finishes)
func _complete_reload() -> void:
	is_reloading = false
	# Ammo transfer is handled by InventoryRuntime via animation events
	# (remove_mag -> insert_mag -> chamber -> reload_done)


## Get current combat state for network sync
func get_state() -> Dictionary:
	return {
		"ads": is_ads,
		"reload": is_reloading,
		"slot": current_slot,
		"weapon": current_weapon.get_state() if current_weapon else {},
	}


## Apply state from network
func apply_state(state: Dictionary) -> void:
	is_ads = state.get("ads", is_ads)
	is_reloading = state.get("reload", is_reloading)

	var new_slot: int = state.get("slot", current_slot)
	if new_slot != current_slot:
		_switch_weapon(new_slot)

	if current_weapon and "weapon" in state:
		current_weapon.apply_state(state.weapon)


## Bind weapon reference
func bind_weapon(weapon: WeaponRuntime) -> void:
	current_weapon = weapon
