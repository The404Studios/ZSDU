extends Node3D
class_name WeaponManager
## WeaponManager - Manages equipped visual weapons for the player
##
## Handles:
## - Equipping/unequipping visual weapon nodes
## - Weapon switching with animations
## - First-person viewmodel positioning
## - Weapon sway and bob
## - Coordinates between CombatController and Firearm
##
## Attached to the player's camera pivot for first-person view.

signal weapon_changed(slot: int, weapon: Firearm)
signal weapon_fired(hit_info: Dictionary)

# Weapon slots
var weapons: Array[Firearm] = [null, null, null]  # Primary, Secondary, Melee
var current_slot: int = 0
var current_weapon: Firearm = null

# Owner references
var owner_player: PlayerController = null
var camera: Camera3D = null
var combat_controller: CombatController = null
var inventory_runtime: InventoryRuntime = null

# Viewmodel positioning
@export var viewmodel_offset := Vector3(0.15, -0.1, -0.3)
@export var ads_offset := Vector3(0.0, -0.05, -0.2)
@export var sprint_offset := Vector3(0.2, -0.2, -0.2)

# Weapon sway/bob settings
@export var sway_amount := 0.002
@export var sway_smooth := 8.0
@export var bob_frequency := 10.0
@export var bob_amplitude := 0.01

# State
var is_switching := false
var switch_timer := 0.0
var switch_duration := 0.3
var target_slot := 0

# Sway state
var sway_offset := Vector3.ZERO
var bob_time := 0.0
var current_position_offset := Vector3.ZERO

# Weapon scene cache (preloaded weapon scenes)
var weapon_scenes: Dictionary = {}


func _ready() -> void:
	# Preload common weapon scenes
	_preload_weapon_scenes()


func _process(delta: float) -> void:
	if not owner_player or not owner_player.is_local_player:
		return

	# Handle weapon switching
	if is_switching:
		_process_switch(delta)

	# Update viewmodel position (sway, bob, ADS lerp)
	_update_viewmodel(delta)


## Initialize with owner player
func initialize(player: PlayerController, p_camera: Camera3D) -> void:
	owner_player = player
	camera = p_camera

	# Get references from player
	combat_controller = player.combat_controller
	inventory_runtime = player.inventory_runtime

	# Connect to combat controller signals
	if combat_controller:
		combat_controller.fire_requested.connect(_on_fire_requested)
		combat_controller.weapon_switched.connect(_on_weapon_switch_requested)
		combat_controller.ads_changed.connect(_on_ads_changed)


## Preload weapon scene templates
func _preload_weapon_scenes() -> void:
	# These would be actual weapon scene files
	# For now, we'll create them dynamically
	pass


## Equip a weapon to a slot from WeaponRuntime
func equip_weapon_from_runtime(slot: int, runtime: WeaponRuntime) -> void:
	if slot < 0 or slot >= 3:
		return

	# Unequip existing weapon in slot
	if weapons[slot]:
		weapons[slot].unequip()
		weapons[slot].queue_free()
		weapons[slot] = null

	if not runtime:
		return

	# Create visual weapon from runtime
	var firearm := _create_firearm_for_runtime(runtime)
	if firearm:
		add_child(firearm)
		firearm.initialize(owner_player)
		firearm.bind_runtime(runtime)
		firearm.fired.connect(_on_weapon_fired)
		weapons[slot] = firearm

		# Hide initially unless it's the current slot
		if slot != current_slot:
			firearm.unequip()
		else:
			firearm.equip()
			current_weapon = firearm
			weapon_changed.emit(slot, firearm)


## Create a Firearm node for a WeaponRuntime
func _create_firearm_for_runtime(runtime: WeaponRuntime) -> Firearm:
	var firearm := Firearm.new()
	firearm.name = "Weapon_%s" % runtime.def_id

	# Set weapon properties from runtime
	firearm.weapon_id = runtime.def_id
	firearm.weapon_name = runtime.name
	firearm.weapon_type = runtime.weapon_type
	firearm.damage = runtime.damage
	firearm.fire_rate = runtime.fire_rate
	firearm.magazine_size = runtime.magazine_size
	firearm.reload_time = runtime.reload_time
	firearm.base_spread = runtime.base_spread

	# Set type-specific properties
	match runtime.weapon_type:
		"rifle":
			firearm.recoil_vertical = 0.025
			firearm.recoil_horizontal = 0.01
			_create_rifle_mesh(firearm)
		"smg":
			firearm.recoil_vertical = 0.015
			firearm.recoil_horizontal = 0.02
			_create_smg_mesh(firearm)
		"pistol":
			firearm.recoil_vertical = 0.04
			firearm.recoil_horizontal = 0.015
			_create_pistol_mesh(firearm)
		"shotgun":
			firearm.recoil_vertical = 0.08
			firearm.recoil_horizontal = 0.03
			firearm.pellet_count = 8
			_create_shotgun_mesh(firearm)
		"sniper":
			firearm.recoil_vertical = 0.06
			firearm.recoil_horizontal = 0.01
			_create_sniper_mesh(firearm)
		"melee":
			firearm.pellet_count = 1
			firearm.range_max = 2.5
			_create_melee_mesh(firearm)

	# Position for first person view
	firearm.position = viewmodel_offset

	return firearm


## Create placeholder rifle mesh
func _create_rifle_mesh(firearm: Firearm) -> void:
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = "WeaponMesh"

	# Create a simple box mesh as placeholder
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.05, 0.08, 0.6)  # Rifle-like shape
	mesh_instance.mesh = mesh

	# Dark metal material
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.15, 0.15, 0.15)
	material.metallic = 0.8
	material.roughness = 0.4
	mesh_instance.set_surface_override_material(0, material)

	mesh_instance.position = Vector3(0, 0, -0.1)
	firearm.add_child(mesh_instance)
	firearm.weapon_mesh = mesh_instance

	# Add stock
	var stock := MeshInstance3D.new()
	var stock_mesh := BoxMesh.new()
	stock_mesh.size = Vector3(0.04, 0.1, 0.2)
	stock.mesh = stock_mesh
	stock.set_surface_override_material(0, material)
	stock.position = Vector3(0, -0.02, 0.2)
	mesh_instance.add_child(stock)

	# Add muzzle point
	var muzzle := Marker3D.new()
	muzzle.name = "MuzzlePoint"
	muzzle.position = Vector3(0, 0, -0.4)
	firearm.add_child(muzzle)
	firearm.muzzle_point = muzzle


## Create placeholder SMG mesh
func _create_smg_mesh(firearm: Firearm) -> void:
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = "WeaponMesh"

	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.04, 0.1, 0.35)
	mesh_instance.mesh = mesh

	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.2, 0.2, 0.2)
	material.metallic = 0.7
	material.roughness = 0.5
	mesh_instance.set_surface_override_material(0, material)

	mesh_instance.position = Vector3(0, 0, -0.05)
	firearm.add_child(mesh_instance)
	firearm.weapon_mesh = mesh_instance

	var muzzle := Marker3D.new()
	muzzle.name = "MuzzlePoint"
	muzzle.position = Vector3(0, 0, -0.25)
	firearm.add_child(muzzle)
	firearm.muzzle_point = muzzle


## Create placeholder pistol mesh
func _create_pistol_mesh(firearm: Firearm) -> void:
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = "WeaponMesh"

	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.03, 0.12, 0.15)
	mesh_instance.mesh = mesh

	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.1, 0.1, 0.1)
	material.metallic = 0.9
	material.roughness = 0.3
	mesh_instance.set_surface_override_material(0, material)

	mesh_instance.position = Vector3(0, 0, 0)
	firearm.add_child(mesh_instance)
	firearm.weapon_mesh = mesh_instance

	var muzzle := Marker3D.new()
	muzzle.name = "MuzzlePoint"
	muzzle.position = Vector3(0, 0.04, -0.1)
	firearm.add_child(muzzle)
	firearm.muzzle_point = muzzle


## Create placeholder shotgun mesh
func _create_shotgun_mesh(firearm: Firearm) -> void:
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = "WeaponMesh"

	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.05, 0.08, 0.7)
	mesh_instance.mesh = mesh

	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.25, 0.15, 0.1)  # Wood-ish
	material.metallic = 0.3
	material.roughness = 0.7
	mesh_instance.set_surface_override_material(0, material)

	mesh_instance.position = Vector3(0, 0, -0.15)
	firearm.add_child(mesh_instance)
	firearm.weapon_mesh = mesh_instance

	var muzzle := Marker3D.new()
	muzzle.name = "MuzzlePoint"
	muzzle.position = Vector3(0, 0, -0.5)
	firearm.add_child(muzzle)
	firearm.muzzle_point = muzzle


## Create placeholder sniper mesh
func _create_sniper_mesh(firearm: Firearm) -> void:
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = "WeaponMesh"

	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.04, 0.1, 0.9)
	mesh_instance.mesh = mesh

	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.12, 0.12, 0.12)
	material.metallic = 0.85
	material.roughness = 0.35
	mesh_instance.set_surface_override_material(0, material)

	mesh_instance.position = Vector3(0, 0, -0.2)
	firearm.add_child(mesh_instance)
	firearm.weapon_mesh = mesh_instance

	# Add scope
	var scope := MeshInstance3D.new()
	var scope_mesh := CylinderMesh.new()
	scope_mesh.top_radius = 0.02
	scope_mesh.bottom_radius = 0.02
	scope_mesh.height = 0.15
	scope.mesh = scope_mesh
	scope.rotation_degrees.x = 90
	scope.position = Vector3(0, 0.08, -0.1)
	mesh_instance.add_child(scope)

	var muzzle := Marker3D.new()
	muzzle.name = "MuzzlePoint"
	muzzle.position = Vector3(0, 0, -0.65)
	firearm.add_child(muzzle)
	firearm.muzzle_point = muzzle


## Create placeholder melee mesh (knife)
func _create_melee_mesh(firearm: Firearm) -> void:
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = "WeaponMesh"

	# Blade
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.02, 0.03, 0.2)
	mesh_instance.mesh = mesh

	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.7, 0.7, 0.75)
	material.metallic = 1.0
	material.roughness = 0.2
	mesh_instance.set_surface_override_material(0, material)

	mesh_instance.position = Vector3(0, 0, -0.05)
	firearm.add_child(mesh_instance)
	firearm.weapon_mesh = mesh_instance

	# Handle
	var handle := MeshInstance3D.new()
	var handle_mesh := BoxMesh.new()
	handle_mesh.size = Vector3(0.025, 0.04, 0.1)
	handle.mesh = handle_mesh
	var handle_mat := StandardMaterial3D.new()
	handle_mat.albedo_color = Color(0.2, 0.15, 0.1)
	handle.set_surface_override_material(0, handle_mat)
	handle.position = Vector3(0, 0, 0.1)
	mesh_instance.add_child(handle)

	var muzzle := Marker3D.new()
	muzzle.name = "MuzzlePoint"
	muzzle.position = Vector3(0, 0, -0.15)
	firearm.add_child(muzzle)
	firearm.muzzle_point = muzzle


## Switch to weapon slot
func switch_weapon(slot: int) -> void:
	if slot < 0 or slot >= 3:
		return

	if slot == current_slot and not is_switching:
		return

	if is_switching:
		return

	target_slot = slot
	is_switching = true
	switch_timer = 0.0

	# Start unequip animation on current weapon
	if current_weapon:
		current_weapon.unequip()


## Process weapon switch animation
func _process_switch(delta: float) -> void:
	switch_timer += delta

	if switch_timer >= switch_duration:
		# Complete switch
		is_switching = false

		current_slot = target_slot
		current_weapon = weapons[current_slot]

		if current_weapon:
			current_weapon.equip()

		weapon_changed.emit(current_slot, current_weapon)


## Update viewmodel position with sway and bob
func _update_viewmodel(delta: float) -> void:
	if not current_weapon:
		return

	# Get target offset based on state
	var target_offset := viewmodel_offset

	if combat_controller and combat_controller.is_ads:
		target_offset = ads_offset
	elif owner_player and owner_player.movement_controller:
		if owner_player.movement_controller.is_sprinting:
			target_offset = sprint_offset

	# Calculate weapon sway from mouse movement
	# This would use input delta, but for now just use a subtle effect
	var mouse_delta := Vector2.ZERO
	if Input.get_last_mouse_velocity().length() > 0:
		mouse_delta = Input.get_last_mouse_velocity() * 0.0001

	sway_offset = sway_offset.lerp(
		Vector3(-mouse_delta.x * sway_amount, mouse_delta.y * sway_amount, 0),
		sway_smooth * delta
	)

	# Calculate weapon bob when moving
	var bob_offset := Vector3.ZERO
	if owner_player and owner_player.velocity.length() > 0.5:
		bob_time += delta * bob_frequency
		bob_offset.x = sin(bob_time) * bob_amplitude
		bob_offset.y = abs(cos(bob_time)) * bob_amplitude * 2.0
	else:
		bob_time = 0.0

	# Lerp to target position
	current_position_offset = current_position_offset.lerp(
		target_offset + sway_offset + bob_offset,
		10.0 * delta
	)

	current_weapon.position = current_position_offset


## Handle fire request from combat controller
func _on_fire_requested(weapon_state: Dictionary) -> void:
	if current_weapon and camera:
		current_weapon.try_fire(camera)


## Handle weapon switch request
func _on_weapon_switch_requested(slot: int) -> void:
	switch_weapon(slot)


## Handle ADS state change
func _on_ads_changed(is_ads: bool) -> void:
	if current_weapon:
		current_weapon.set_ads(is_ads)


## Handle weapon fired (visual feedback only)
## NOTE: Network sending is handled by PlayerNetworkController._on_fire_requested
## We only handle visual/audio effects here to avoid duplicate server requests
func _on_weapon_fired(hit_info: Dictionary) -> void:
	weapon_fired.emit(hit_info)
	# Visual effects only - network handled elsewhere


## Get current weapon info for HUD
func get_current_weapon_info() -> Dictionary:
	if current_weapon:
		return current_weapon.get_display_info()
	return {}


## Get ammo info for HUD
func get_ammo_info() -> Dictionary:
	if current_weapon:
		return current_weapon.get_ammo_info()
	return {"current": 0, "max": 0, "chambered": false}
