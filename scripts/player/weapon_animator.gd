extends Node3D
class_name WeaponAnimator
## WeaponAnimator - Procedural first-person weapon animations
##
## Handles smooth, game-feel animations for FP weapons:
## - Weapon sway (follows mouse movement)
## - Weapon bob (walking/running oscillation)
## - Recoil (kick on fire)
## - ADS transitions
## - Inspect animation
## - Jump/land impact
##
## Attach as child of the weapon model root

signal recoil_applied(amount: Vector2)
signal ads_changed(is_ads: bool)

# Sway settings
@export_group("Sway")
@export var sway_amount := 0.02
@export var sway_smooth := 8.0
@export var sway_rotation_amount := 2.0
@export var max_sway := 0.1

# Bob settings
@export_group("Bob")
@export var bob_frequency := 2.5
@export var bob_amplitude := 0.02
@export var bob_amplitude_sprint := 0.04
@export var bob_rotation_amount := 1.0

# Recoil settings
@export_group("Recoil")
@export var recoil_kick_back := 0.05
@export var recoil_kick_up := 0.02
@export var recoil_rotation := 3.0
@export var recoil_recovery_speed := 8.0
@export var recoil_snap_speed := 25.0

# ADS settings
@export_group("ADS")
@export var ads_position := Vector3(0, -0.05, -0.1)  # Offset when aiming
@export var ads_rotation := Vector3.ZERO
@export var ads_fov := 50.0
@export var ads_transition_speed := 10.0

# Impact settings
@export_group("Impact")
@export var jump_bob := 0.03
@export var land_bob := 0.05
@export var impact_recovery := 5.0

# State
var is_ads := false
var is_sprinting := false
var is_moving := false
var velocity := Vector3.ZERO

# Animation state
var sway_offset := Vector3.ZERO
var sway_rotation := Vector3.ZERO
var bob_time := 0.0
var bob_offset := Vector3.ZERO
var bob_rotation := Vector3.ZERO
var recoil_offset := Vector3.ZERO
var recoil_rotation := Vector3.ZERO
var impact_offset := Vector3.ZERO
var ads_progress := 0.0

# Base transform (set on ready)
var base_position := Vector3.ZERO
var base_rotation := Vector3.ZERO

# Input tracking
var mouse_delta := Vector2.ZERO
var last_grounded := true


func _ready() -> void:
	base_position = position
	base_rotation = rotation


func _process(delta: float) -> void:
	_update_sway(delta)
	_update_bob(delta)
	_update_recoil(delta)
	_update_ads(delta)
	_update_impact(delta)
	_apply_transforms()


# ============================================
# SWAY (Mouse movement)
# ============================================

func _update_sway(delta: float) -> void:
	# Calculate target sway from mouse movement
	var target_sway := Vector3.ZERO
	target_sway.x = -mouse_delta.x * sway_amount
	target_sway.y = mouse_delta.y * sway_amount

	# Clamp sway
	target_sway.x = clampf(target_sway.x, -max_sway, max_sway)
	target_sway.y = clampf(target_sway.y, -max_sway, max_sway)

	# Smooth interpolation
	sway_offset = sway_offset.lerp(target_sway, sway_smooth * delta)

	# Rotation sway
	var target_rot := Vector3.ZERO
	target_rot.z = -mouse_delta.x * deg_to_rad(sway_rotation_amount)
	target_rot.x = mouse_delta.y * deg_to_rad(sway_rotation_amount)

	sway_rotation = sway_rotation.lerp(target_rot, sway_smooth * delta)

	# Decay mouse delta
	mouse_delta = mouse_delta.lerp(Vector2.ZERO, 10.0 * delta)


## Called from player input handler
func apply_mouse_delta(delta_input: Vector2) -> void:
	mouse_delta += delta_input


# ============================================
# BOB (Walking oscillation)
# ============================================

func _update_bob(delta: float) -> void:
	if not is_moving or is_ads:
		# Smoothly return to rest
		bob_offset = bob_offset.lerp(Vector3.ZERO, 5.0 * delta)
		bob_rotation = bob_rotation.lerp(Vector3.ZERO, 5.0 * delta)
		return

	# Advance bob timer
	var freq := bob_frequency
	var amp := bob_amplitude

	if is_sprinting:
		freq *= 1.5
		amp = bob_amplitude_sprint

	bob_time += delta * freq * velocity.length() * 0.5

	# Calculate bob offset (figure-8 pattern)
	var horizontal := sin(bob_time) * amp
	var vertical := abs(cos(bob_time)) * amp * 0.5

	bob_offset = Vector3(horizontal, vertical, 0)

	# Bob rotation (slight tilt with steps)
	bob_rotation = Vector3(
		cos(bob_time) * deg_to_rad(bob_rotation_amount),
		0,
		sin(bob_time) * deg_to_rad(bob_rotation_amount * 0.5)
	)


## Update movement state
func set_movement_state(vel: Vector3, moving: bool, sprinting: bool) -> void:
	velocity = vel
	is_moving = moving
	is_sprinting = sprinting


# ============================================
# RECOIL (Firing kick)
# ============================================

func _update_recoil(delta: float) -> void:
	# Recover from recoil
	recoil_offset = recoil_offset.lerp(Vector3.ZERO, recoil_recovery_speed * delta)
	recoil_rotation = recoil_rotation.lerp(Vector3.ZERO, recoil_recovery_speed * delta)


## Apply recoil kick (call when firing)
func apply_recoil(multiplier: float = 1.0) -> void:
	# Random horizontal variance
	var horizontal := randf_range(-0.5, 0.5) * recoil_kick_back * multiplier

	# Snap to recoil position
	var target := Vector3(-recoil_kick_back * multiplier, recoil_kick_up * multiplier, horizontal)

	# Add to current recoil (stacks for rapid fire)
	recoil_offset += target

	# Rotation kick
	var rot_kick := Vector3(
		deg_to_rad(recoil_rotation) * multiplier,
		deg_to_rad(randf_range(-recoil_rotation, recoil_rotation) * 0.3) * multiplier,
		deg_to_rad(randf_range(-recoil_rotation, recoil_rotation) * 0.2) * multiplier
	)
	recoil_rotation += rot_kick

	recoil_applied.emit(Vector2(rot_kick.y, rot_kick.x))


## Apply heavy recoil (shotgun, sniper, etc.)
func apply_heavy_recoil(multiplier: float = 2.0) -> void:
	apply_recoil(multiplier)

	# Extra visual kick
	recoil_offset.z -= recoil_kick_back * multiplier * 0.5


# ============================================
# ADS (Aim Down Sights)
# ============================================

func _update_ads(delta: float) -> void:
	var target := 1.0 if is_ads else 0.0
	ads_progress = lerpf(ads_progress, target, ads_transition_speed * delta)


## Toggle ADS
func set_ads(ads: bool) -> void:
	if is_ads != ads:
		is_ads = ads
		ads_changed.emit(is_ads)


## Get current ADS progress (0-1)
func get_ads_progress() -> float:
	return ads_progress


# ============================================
# IMPACT (Jump/Land)
# ============================================

func _update_impact(delta: float) -> void:
	# Recover from impact
	impact_offset = impact_offset.lerp(Vector3.ZERO, impact_recovery * delta)


## Call when player jumps
func on_jump() -> void:
	impact_offset.y = jump_bob


## Call when player lands
func on_land(fall_velocity: float) -> void:
	var impact_strength := clampf(abs(fall_velocity) / 15.0, 0.2, 1.0)
	impact_offset.y = -land_bob * impact_strength


## Update grounded state (auto-detect landing)
func set_grounded(grounded: bool, fall_velocity: float = 0.0) -> void:
	if grounded and not last_grounded:
		on_land(fall_velocity)
	last_grounded = grounded


# ============================================
# SPECIAL ANIMATIONS
# ============================================

## Play inspect animation (look at weapon)
func play_inspect() -> void:
	var tween := create_tween()

	# Rotate weapon to show it off
	tween.tween_property(self, "rotation", base_rotation + Vector3(0, deg_to_rad(45), deg_to_rad(-30)), 0.4)\
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

	# Hold
	tween.tween_interval(1.5)

	# Return to normal
	tween.tween_property(self, "rotation", base_rotation, 0.4)\
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


## Play equip animation (bring weapon up)
func play_equip() -> void:
	# Start below view
	position = base_position + Vector3(0, -0.3, 0)
	rotation = base_rotation + Vector3(deg_to_rad(30), 0, 0)

	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(self, "position", base_position, 0.35)\
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "rotation", base_rotation, 0.35)\
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)


## Play holster animation (lower weapon)
func play_holster() -> Tween:
	var target_pos := base_position + Vector3(0.1, -0.2, 0)
	var target_rot := base_rotation + Vector3(deg_to_rad(20), deg_to_rad(-30), 0)

	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(self, "position", target_pos, 0.25)\
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tween.tween_property(self, "rotation", target_rot, 0.25)\
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)

	return tween


## Play melee swing animation
func play_melee_swing() -> void:
	var tween := create_tween()

	# Wind up
	tween.tween_property(self, "rotation", base_rotation + Vector3(0, deg_to_rad(-20), deg_to_rad(15)), 0.1)

	# Swing
	tween.tween_property(self, "rotation", base_rotation + Vector3(deg_to_rad(-15), deg_to_rad(30), deg_to_rad(-20)), 0.08)\
		.set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)

	# Recovery
	tween.tween_property(self, "rotation", base_rotation, 0.2)\
		.set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)


## Play chamber animation (pump shotgun, bolt action)
func play_chamber() -> void:
	var tween := create_tween()

	# Pull back
	tween.tween_property(self, "position", base_position + Vector3(-0.02, 0, 0.05), 0.15)

	# Push forward with snap
	tween.tween_property(self, "position", base_position + Vector3(0.01, 0, -0.02), 0.1)\
		.set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)

	# Settle
	tween.tween_property(self, "position", base_position, 0.1)


# ============================================
# TRANSFORM APPLICATION
# ============================================

func _apply_transforms() -> void:
	# Calculate ADS blend
	var ads_pos := base_position.lerp(base_position + ads_position, ads_progress)
	var ads_rot := base_rotation.lerp(base_rotation + ads_rotation, ads_progress)

	# Reduce procedural animations when ADS
	var procedural_mult := 1.0 - ads_progress * 0.7

	# Combine all offsets
	var final_pos := ads_pos
	final_pos += sway_offset * procedural_mult
	final_pos += bob_offset * procedural_mult
	final_pos += recoil_offset
	final_pos += impact_offset * procedural_mult

	var final_rot := ads_rot
	final_rot += sway_rotation * procedural_mult
	final_rot += bob_rotation * procedural_mult
	final_rot += recoil_rotation

	# Apply
	position = final_pos
	rotation = final_rot


# ============================================
# CONFIGURATION
# ============================================

## Configure for a specific weapon type
func configure_for_weapon(weapon_type: String) -> void:
	match weapon_type:
		"pistol":
			recoil_kick_back = 0.03
			recoil_kick_up = 0.015
			recoil_rotation = 2.0
			bob_amplitude = 0.015

		"rifle":
			recoil_kick_back = 0.04
			recoil_kick_up = 0.02
			recoil_rotation = 2.5
			bob_amplitude = 0.02

		"shotgun":
			recoil_kick_back = 0.08
			recoil_kick_up = 0.04
			recoil_rotation = 5.0
			bob_amplitude = 0.025

		"sniper":
			recoil_kick_back = 0.06
			recoil_kick_up = 0.03
			recoil_rotation = 4.0
			bob_amplitude = 0.015
			sway_amount = 0.03  # More sway when not ADS

		"smg":
			recoil_kick_back = 0.025
			recoil_kick_up = 0.012
			recoil_rotation = 1.5
			bob_amplitude = 0.018

		"melee":
			recoil_kick_back = 0.0
			recoil_kick_up = 0.0
			recoil_rotation = 0.0
			bob_amplitude = 0.03
			sway_amount = 0.015
