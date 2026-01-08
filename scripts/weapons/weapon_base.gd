extends Node3D
class_name WeaponBase
## WeaponBase - Base class for all weapons/tools
##
## Provides common functionality for weapons.

# Weapon info
@export var weapon_name := "Weapon"
@export var weapon_slot := 0

# Owner reference
var owner_player: PlayerController = null

# State
var is_equipped := false


## Initialize with owner player
func initialize(player: PlayerController) -> void:
	owner_player = player


## Called when weapon is equipped
func equip() -> void:
	is_equipped = true
	visible = true


## Called when weapon is unequipped
func unequip() -> void:
	is_equipped = false
	visible = false


## Primary action (override in subclass)
func primary_action() -> void:
	pass


## Secondary action (override in subclass)
func secondary_action() -> void:
	pass


## Reload (override in subclass)
func reload() -> void:
	pass


## Get weapon display info for UI
func get_display_info() -> Dictionary:
	return {
		"name": weapon_name,
		"slot": weapon_slot,
	}
