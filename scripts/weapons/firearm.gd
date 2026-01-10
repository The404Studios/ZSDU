extends Node3D
class_name Firearm
## Firearm - Visual weapon with shooting mechanics
##
## Handles:
## - Visual representation (model, animations)
## - Muzzle flash and ejection effects
## - Recoil animation
## - Sound effects
## - Raycast shooting (client-side prediction)
##
## Works with WeaponRuntime for data and CombatController for input.

signal fired(hit_info: Dictionary)
signal reloaded()
signal equipped()
signal unequipped()

# Weapon configuration
@export var weapon_id: String = "rifle_ak47"
@export var weapon_name: String = "AK-47"
@export var weapon_type: String = "rifle"  # rifle, pistol, shotgun, smg, sniper

# Shooting stats (can be overridden by WeaponRuntime)
@export var damage: float = 35.0
@export var fire_rate: float = 0.1  # Seconds between shots
@export var magazine_size: int = 30
@export var reload_time: float = 2.5
@export var base_spread: float = 0.02  # Radians
@export var ads_spread_mult: float = 0.3
@export var range_max: float = 200.0
@export var pellet_count: int = 1  # >1 for shotguns

# Recoil configuration
@export var recoil_vertical: float = 0.02  # Radians per shot
@export var recoil_horizontal: float = 0.01
@export var recoil_recovery: float = 5.0  # How fast recoil recovers
@export var recoil_ads_mult: float = 0.5  # Recoil reduction when ADS

# Visual configuration
@export var muzzle_flash_duration: float = 0.05
@export var shell_eject_force: float = 5.0

# Node references (set up in scene or created dynamically)
var weapon_mesh: MeshInstance3D = null
var muzzle_point: Marker3D = null
var ejection_point: Marker3D = null
var muzzle_flash: GPUParticles3D = null
var muzzle_light: OmniLight3D = null

# Shell ejection scene
var shell_scene: PackedScene = null

# Audio
var audio_fire: AudioStreamPlayer3D = null
var audio_reload: AudioStreamPlayer3D = null
var audio_empty: AudioStreamPlayer3D = null

# State
var owner_player: PlayerController = null
var weapon_runtime: WeaponRuntime = null
var is_equipped: bool = false
var is_ads: bool = false
var current_recoil: Vector2 = Vector2.ZERO  # Accumulated recoil (x=horizontal, y=vertical)

# Timers
var fire_cooldown: float = 0.0
var muzzle_flash_timer: float = 0.0


func _ready() -> void:
	_setup_components()


func _process(delta: float) -> void:
	# Update cooldowns
	if fire_cooldown > 0:
		fire_cooldown -= delta

	# Update muzzle flash
	if muzzle_flash_timer > 0:
		muzzle_flash_timer -= delta
		if muzzle_flash_timer <= 0:
			_hide_muzzle_flash()

	# Recover recoil
	if current_recoil.length() > 0.001:
		current_recoil = current_recoil.lerp(Vector2.ZERO, recoil_recovery * delta)


## Initialize with owner player
func initialize(player: PlayerController) -> void:
	owner_player = player


## Bind weapon runtime data
func bind_runtime(runtime: WeaponRuntime) -> void:
	weapon_runtime = runtime

	# Override stats from runtime if available
	if runtime:
		damage = runtime.damage
		fire_rate = runtime.fire_rate
		magazine_size = runtime.magazine_size
		reload_time = runtime.reload_time
		base_spread = runtime.base_spread
		weapon_type = runtime.weapon_type


## Set up visual components
func _setup_components() -> void:
	# Find or create muzzle point
	if not muzzle_point:
		muzzle_point = get_node_or_null("MuzzlePoint") as Marker3D
		if not muzzle_point:
			muzzle_point = Marker3D.new()
			muzzle_point.name = "MuzzlePoint"
			muzzle_point.position = Vector3(0, 0, -0.5)  # Default forward
			add_child(muzzle_point)

	# Find or create ejection point
	if not ejection_point:
		ejection_point = get_node_or_null("EjectionPoint") as Marker3D
		if not ejection_point:
			ejection_point = Marker3D.new()
			ejection_point.name = "EjectionPoint"
			ejection_point.position = Vector3(0.05, 0.05, -0.1)  # Right side
			add_child(ejection_point)

	# Create muzzle flash particles
	if not muzzle_flash:
		muzzle_flash = get_node_or_null("MuzzleFlash") as GPUParticles3D
		if not muzzle_flash:
			_create_muzzle_flash()

	# Create muzzle light
	if not muzzle_light:
		muzzle_light = get_node_or_null("MuzzleLight") as OmniLight3D
		if not muzzle_light:
			_create_muzzle_light()

	# Find or create audio players
	if not audio_fire:
		audio_fire = get_node_or_null("AudioFire") as AudioStreamPlayer3D
		if not audio_fire:
			audio_fire = AudioStreamPlayer3D.new()
			audio_fire.name = "AudioFire"
			add_child(audio_fire)

	if not audio_reload:
		audio_reload = get_node_or_null("AudioReload") as AudioStreamPlayer3D
		if not audio_reload:
			audio_reload = AudioStreamPlayer3D.new()
			audio_reload.name = "AudioReload"
			add_child(audio_reload)

	if not audio_empty:
		audio_empty = get_node_or_null("AudioEmpty") as AudioStreamPlayer3D
		if not audio_empty:
			audio_empty = AudioStreamPlayer3D.new()
			audio_empty.name = "AudioEmpty"
			add_child(audio_empty)


## Create muzzle flash particles
func _create_muzzle_flash() -> void:
	muzzle_flash = GPUParticles3D.new()
	muzzle_flash.name = "MuzzleFlash"
	muzzle_flash.emitting = false
	muzzle_flash.one_shot = true
	muzzle_flash.explosiveness = 1.0
	muzzle_flash.amount = 8
	muzzle_flash.lifetime = 0.1

	var material := ParticleProcessMaterial.new()
	material.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	material.emission_sphere_radius = 0.02
	material.direction = Vector3(0, 0, -1)
	material.spread = 30.0
	material.initial_velocity_min = 2.0
	material.initial_velocity_max = 5.0
	material.gravity = Vector3.ZERO
	material.scale_min = 0.05
	material.scale_max = 0.1
	material.color = Color(1.0, 0.8, 0.3, 1.0)
	muzzle_flash.process_material = material

	# Simple quad mesh for particles
	var mesh := QuadMesh.new()
	mesh.size = Vector2(0.1, 0.1)
	muzzle_flash.draw_pass_1 = mesh

	if muzzle_point:
		muzzle_point.add_child(muzzle_flash)
	else:
		add_child(muzzle_flash)


## Create muzzle light
func _create_muzzle_light() -> void:
	muzzle_light = OmniLight3D.new()
	muzzle_light.name = "MuzzleLight"
	muzzle_light.light_color = Color(1.0, 0.8, 0.4)
	muzzle_light.light_energy = 0.0
	muzzle_light.omni_range = 3.0
	muzzle_light.omni_attenuation = 2.0

	if muzzle_point:
		muzzle_point.add_child(muzzle_light)
	else:
		add_child(muzzle_light)


## Equip this weapon
func equip() -> void:
	is_equipped = true
	visible = true
	equipped.emit()


## Unequip this weapon
func unequip() -> void:
	is_equipped = false
	visible = false
	current_recoil = Vector2.ZERO
	unequipped.emit()


## Set ADS state
func set_ads(ads: bool) -> void:
	is_ads = ads


## Try to fire the weapon
## Returns true if fired successfully
func try_fire(camera: Camera3D) -> bool:
	if fire_cooldown > 0:
		return false

	if weapon_runtime and not weapon_runtime.can_fire():
		# Play empty click sound
		if weapon_runtime.is_magazine_empty():
			_play_empty_sound()
		return false

	# Fire!
	_do_fire(camera)
	return true


## Perform the actual fire
func _do_fire(camera: Camera3D) -> void:
	fire_cooldown = fire_rate

	# Consume ammo
	if weapon_runtime:
		weapon_runtime.consume_round()

	# Show muzzle flash
	_show_muzzle_flash()

	# Play fire sound
	_play_fire_sound()

	# Eject shell
	_eject_shell()

	# Apply recoil
	_apply_recoil()

	# Perform raycast(s)
	var hits := _perform_raycast(camera)

	# Emit fired signal with hit info
	var hit_info := {
		"weapon_id": weapon_id,
		"damage": damage,
		"hits": hits,
		"origin": muzzle_point.global_position if muzzle_point else global_position,
		"is_ads": is_ads,
	}
	fired.emit(hit_info)


## Perform raycast shooting
func _perform_raycast(camera: Camera3D) -> Array:
	if not camera:
		return []

	var hits := []
	var space_state := get_world_3d().direct_space_state

	# Get spread based on ADS
	var spread := base_spread * (ads_spread_mult if is_ads else 1.0)

	# Add accumulated recoil to spread
	spread += current_recoil.length() * 0.5

	var origin := camera.global_position
	var base_direction := -camera.global_basis.z

	# Fire multiple pellets for shotguns
	for _i in range(pellet_count):
		# Apply spread
		var spread_x := randf_range(-spread, spread)
		var spread_y := randf_range(-spread, spread)
		var direction := base_direction.rotated(camera.global_basis.x, spread_y)
		direction = direction.rotated(camera.global_basis.y, spread_x)

		var end := origin + direction * range_max

		var query := PhysicsRayQueryParameters3D.create(origin, end)
		query.collision_mask = 0b00001111  # World, players, zombies, props

		if owner_player:
			query.exclude = [owner_player]

		var result := space_state.intersect_ray(query)

		if result:
			hits.append({
				"position": result.position,
				"normal": result.normal,
				"collider": result.collider,
				"distance": origin.distance_to(result.position),
			})

	return hits


## Apply recoil
func _apply_recoil() -> void:
	var recoil_mult := recoil_ads_mult if is_ads else 1.0

	# Random horizontal recoil
	var h_recoil := randf_range(-recoil_horizontal, recoil_horizontal) * recoil_mult
	# Consistent upward recoil
	var v_recoil := recoil_vertical * recoil_mult

	current_recoil.x += h_recoil
	current_recoil.y += v_recoil

	# Apply visual recoil to weapon (kick back)
	# This would be animated in a real game
	if owner_player and owner_player.is_local_player:
		# Apply to camera pivot
		var camera_pivot := owner_player.get_camera_pivot()
		if camera_pivot:
			# The actual camera rotation is handled by player controller
			# We just accumulate recoil here and let it be applied
			pass


## Get accumulated recoil for camera adjustment
func get_recoil() -> Vector2:
	return current_recoil


## Consume recoil (called after applying to camera)
func consume_recoil() -> Vector2:
	var recoil := current_recoil
	current_recoil = Vector2.ZERO
	return recoil


## Show muzzle flash effect
func _show_muzzle_flash() -> void:
	muzzle_flash_timer = muzzle_flash_duration

	if muzzle_flash:
		muzzle_flash.emitting = true

	if muzzle_light:
		muzzle_light.light_energy = 2.0


## Hide muzzle flash effect
func _hide_muzzle_flash() -> void:
	if muzzle_light:
		muzzle_light.light_energy = 0.0


## Eject shell casing
func _eject_shell() -> void:
	if not ejection_point:
		return

	if not shell_scene:
		return  # No shell to eject

	var shell: RigidBody3D = shell_scene.instantiate()
	get_tree().root.add_child(shell)
	shell.global_position = ejection_point.global_position
	shell.global_rotation = ejection_point.global_rotation

	# Apply ejection force
	var eject_dir := ejection_point.global_basis.x + ejection_point.global_basis.y * 0.5
	shell.apply_impulse(eject_dir.normalized() * shell_eject_force)
	shell.apply_torque_impulse(Vector3(randf(), randf(), randf()) * 2.0)

	# Auto-cleanup shell after a few seconds
	var timer := get_tree().create_timer(5.0)
	timer.timeout.connect(func():
		if is_instance_valid(shell):
			shell.queue_free()
	)


## Play fire sound
func _play_fire_sound() -> void:
	if audio_fire and audio_fire.stream:
		audio_fire.pitch_scale = randf_range(0.95, 1.05)
		audio_fire.play()


## Play empty click sound
func _play_empty_sound() -> void:
	if audio_empty and audio_empty.stream:
		audio_empty.play()


## Play reload sound
func play_reload_sound() -> void:
	if audio_reload and audio_reload.stream:
		audio_reload.play()


## Get ammo display info
func get_ammo_info() -> Dictionary:
	if weapon_runtime:
		return {
			"current": weapon_runtime.current_ammo,
			"max": weapon_runtime.magazine_size,
			"chambered": weapon_runtime.chambered,
		}
	return {
		"current": 0,
		"max": magazine_size,
		"chambered": false,
	}


## Get weapon display info
func get_display_info() -> Dictionary:
	return {
		"id": weapon_id,
		"name": weapon_name,
		"type": weapon_type,
		"ammo": get_ammo_info(),
	}
