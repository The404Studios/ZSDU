extends Node
class_name MovementController
## MovementController - Pure physics movement
##
## Handles:
## - Walk / sprint / crouch / prone
## - Acceleration & inertia (Tarkov-like)
## - Stamina drain & recovery
## - Grounding & slope handling
##
## Does NOT:
## - Read inventory
## - Fire weapons
## - Decide damage
## - Talk to backend

signal stamina_changed(current: float, max_value: float)
signal posture_changed(posture: int)

# Movement constants
@export var walk_speed := 4.0
@export var sprint_speed := 7.5
@export var crouch_speed := 2.5
@export var prone_speed := 1.0

@export var acceleration := 18.0
@export var friction := 12.0
@export var air_control := 0.3
@export var gravity := 24.0
@export var jump_velocity := 5.5

# Stamina
@export var max_stamina := 100.0
@export var stamina_drain_sprint := 15.0
@export var stamina_drain_jump := 10.0
@export var stamina_regen := 8.0
@export var stamina_regen_delay := 2.0

# Posture heights (for collision shape adjustment)
@export var stand_height := 1.8
@export var crouch_height := 1.2
@export var prone_height := 0.5

# State
var posture: int = PlayerState.Posture.STAND
var stamina: float = 100.0
var is_sprinting: bool = false
var last_stamina_drain_time: float = 0.0

# References
var body: CharacterBody3D = null
var collision_shape: CollisionShape3D = null

# Desired velocity (from input processing)
var desired_velocity := Vector3.ZERO
var wants_jump := false


func initialize(p_body: CharacterBody3D, p_collision: CollisionShape3D) -> void:
	body = p_body
	collision_shape = p_collision
	stamina = max_stamina


## Process input and update desired movement state
func process_input(input: PlayerInput, delta: float) -> void:
	# Handle posture changes
	if input.crouch:
		_toggle_crouch()
	if input.prone:
		_toggle_prone()

	# Determine if sprinting is possible
	var can_sprint := (
		posture == PlayerState.Posture.STAND and
		stamina > 0 and
		input.sprint and
		input.move_dir.length() > 0.1 and
		body.is_on_floor()
	)

	is_sprinting = can_sprint

	# Get movement speed based on posture
	var speed := _get_movement_speed()

	# Apply sprint speed
	if is_sprinting:
		speed = sprint_speed

	# Calculate desired velocity
	desired_velocity = input.move_dir * speed

	# Handle jump
	wants_jump = input.jump and body.is_on_floor() and posture == PlayerState.Posture.STAND

	# Stamina management
	if is_sprinting:
		_drain_stamina(stamina_drain_sprint * delta)
	elif wants_jump:
		_drain_stamina(stamina_drain_jump)

	# Stamina regeneration
	_regenerate_stamina(delta)


## Apply physics movement (call this in _physics_process)
func apply_movement(delta: float) -> void:
	if not body:
		return

	var velocity := body.velocity

	# Gravity
	if not body.is_on_floor():
		velocity.y -= gravity * delta

	# Jump
	if wants_jump:
		velocity.y = jump_velocity
		wants_jump = false

	# Horizontal movement
	if body.is_on_floor():
		# Ground movement with acceleration
		velocity.x = lerpf(velocity.x, desired_velocity.x, acceleration * delta)
		velocity.z = lerpf(velocity.z, desired_velocity.z, acceleration * delta)

		# Apply friction when no input
		if desired_velocity.length() < 0.1:
			velocity.x = move_toward(velocity.x, 0, friction * delta)
			velocity.z = move_toward(velocity.z, 0, friction * delta)
	else:
		# Air control
		velocity.x = lerpf(velocity.x, desired_velocity.x, acceleration * delta * air_control)
		velocity.z = lerpf(velocity.z, desired_velocity.z, acceleration * delta * air_control)

	body.velocity = velocity
	body.move_and_slide()


## Get current movement speed based on posture
func _get_movement_speed() -> float:
	match posture:
		PlayerState.Posture.STAND:
			return walk_speed
		PlayerState.Posture.CROUCH:
			return crouch_speed
		PlayerState.Posture.PRONE:
			return prone_speed
	return walk_speed


## Toggle crouch posture
func _toggle_crouch() -> void:
	if posture == PlayerState.Posture.CROUCH:
		if _can_stand():
			_set_posture(PlayerState.Posture.STAND)
	elif posture == PlayerState.Posture.STAND:
		_set_posture(PlayerState.Posture.CROUCH)
	elif posture == PlayerState.Posture.PRONE:
		_set_posture(PlayerState.Posture.CROUCH)


## Toggle prone posture
func _toggle_prone() -> void:
	if posture == PlayerState.Posture.PRONE:
		_set_posture(PlayerState.Posture.CROUCH)
	elif posture != PlayerState.Posture.PRONE:
		_set_posture(PlayerState.Posture.PRONE)


## Check if player can stand up (ceiling clearance)
func _can_stand() -> bool:
	if not body or not collision_shape:
		return true

	# Raycast upward to check clearance
	var space_state := body.get_world_3d().direct_space_state
	var from := body.global_position + Vector3(0, 0.5, 0)
	var to := from + Vector3(0, stand_height - 0.5, 0)

	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.exclude = [body]

	var result := space_state.intersect_ray(query)
	return result.is_empty()


## Set posture and adjust collision shape
func _set_posture(new_posture: int) -> void:
	if posture == new_posture:
		return

	posture = new_posture

	# Adjust collision shape height
	if collision_shape and collision_shape.shape is CapsuleShape3D:
		var capsule := collision_shape.shape as CapsuleShape3D
		match posture:
			PlayerState.Posture.STAND:
				capsule.height = stand_height
				collision_shape.position.y = stand_height / 2
			PlayerState.Posture.CROUCH:
				capsule.height = crouch_height
				collision_shape.position.y = crouch_height / 2
			PlayerState.Posture.PRONE:
				capsule.height = prone_height
				collision_shape.position.y = prone_height / 2

	posture_changed.emit(posture)


## Drain stamina
func _drain_stamina(amount: float) -> void:
	stamina = maxf(0, stamina - amount)
	last_stamina_drain_time = Time.get_ticks_msec() / 1000.0
	stamina_changed.emit(stamina, max_stamina)


## Regenerate stamina
func _regenerate_stamina(delta: float) -> void:
	if stamina >= max_stamina:
		return

	var time_now := Time.get_ticks_msec() / 1000.0
	if time_now - last_stamina_drain_time < stamina_regen_delay:
		return

	stamina = minf(max_stamina, stamina + stamina_regen * delta)
	stamina_changed.emit(stamina, max_stamina)


## Get current state for network sync
func get_state() -> Dictionary:
	return {
		"posture": posture,
		"stamina": stamina,
		"sprinting": is_sprinting,
	}


## Apply state from network
func apply_state(state: Dictionary) -> void:
	if "posture" in state:
		_set_posture(state.posture)
	if "stamina" in state:
		stamina = state.stamina
	if "sprinting" in state:
		is_sprinting = state.sprinting
