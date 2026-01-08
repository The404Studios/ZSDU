extends CharacterBody3D
class_name PlayerController
## PlayerController - Server-authoritative player with client-side prediction
##
## Clients: Send input, predict locally, reconcile with server
## Server: Receives input, simulates authoritatively, broadcasts state

# Movement constants
const WALK_SPEED := 5.0
const SPRINT_SPEED := 8.0
const JUMP_VELOCITY := 5.0
const MOUSE_SENSITIVITY := 0.002
const ACCELERATION := 10.0
const FRICTION := 8.0
const AIR_CONTROL := 0.3

# Player state
@export var max_health := 100.0
var health: float = 100.0
var is_dead := false
var is_sprinting := false

# Network state
var peer_id: int = 0
var is_local_player := false

# Input state (sent to server)
var input_direction := Vector3.ZERO
var look_rotation := Vector2.ZERO  # pitch, yaw
var wants_jump := false
var wants_sprint := false
var wants_primary := false
var wants_secondary := false
var wants_reload := false
var wants_interact := false

# Client-side prediction
var pending_inputs: Array[Dictionary] = []
var last_server_position := Vector3.ZERO
var last_server_velocity := Vector3.ZERO
var input_sequence := 0

# Node references
@onready var camera_pivot: Node3D = $CameraPivot
@onready var camera: Camera3D = $CameraPivot/Camera3D
@onready var collision_shape: CollisionShape3D = $CollisionShape3D
@onready var mesh: MeshInstance3D = $MeshInstance3D

# Inventory / Equipment
var current_weapon_slot := 0
var inventory: Array[Node] = []


func _ready() -> void:
	# Determine if this is our local player
	peer_id = get_multiplayer_authority()
	is_local_player = peer_id == multiplayer.get_unique_id()

	if is_local_player:
		# Enable camera, capture mouse
		camera.current = true
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

		# Hide own mesh (first person)
		if mesh:
			mesh.visible = false
	else:
		# Disable camera for remote players
		camera.current = false

	# Initialize health
	health = max_health


func _input(event: InputEvent) -> void:
	if not is_local_player:
		return

	# Mouse look
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		look_rotation.y -= event.relative.x * MOUSE_SENSITIVITY
		look_rotation.x -= event.relative.y * MOUSE_SENSITIVITY
		look_rotation.x = clampf(look_rotation.x, -PI/2 + 0.1, PI/2 - 0.1)

		# Apply rotation locally for responsive feel
		rotation.y = look_rotation.y
		camera_pivot.rotation.x = look_rotation.x


func _physics_process(delta: float) -> void:
	if is_local_player:
		_gather_input()
		_send_input_to_server()
		_predict_movement(delta)
	elif NetworkManager.is_authority():
		# Server simulates all players
		_server_simulate(delta)


## Gather input from local player
func _gather_input() -> void:
	# Movement direction
	var input_dir := Vector2.ZERO
	if Input.is_action_pressed("move_forward"):
		input_dir.y -= 1
	if Input.is_action_pressed("move_backward"):
		input_dir.y += 1
	if Input.is_action_pressed("move_left"):
		input_dir.x -= 1
	if Input.is_action_pressed("move_right"):
		input_dir.x += 1

	input_direction = Vector3(input_dir.x, 0, input_dir.y).normalized()

	# Transform to world space based on look direction
	input_direction = input_direction.rotated(Vector3.UP, look_rotation.y)

	# Actions
	wants_jump = Input.is_action_just_pressed("jump")
	wants_sprint = Input.is_action_pressed("sprint")
	wants_primary = Input.is_action_pressed("primary_action")
	wants_secondary = Input.is_action_pressed("secondary_action")
	wants_reload = Input.is_action_just_pressed("reload")
	wants_interact = Input.is_action_just_pressed("interact")

	is_sprinting = wants_sprint and input_direction.length() > 0.1 and is_on_floor()


## Send input to server
func _send_input_to_server() -> void:
	input_sequence += 1

	var input_data := {
		"seq": input_sequence,
		"dir": input_direction,
		"look": look_rotation,
		"jump": wants_jump,
		"sprint": wants_sprint,
		"primary": wants_primary,
		"secondary": wants_secondary,
		"reload": wants_reload,
		"interact": wants_interact,
	}

	# Store for reconciliation
	pending_inputs.append({
		"seq": input_sequence,
		"input": input_data,
		"position": global_position,
		"velocity": velocity,
	})

	# Limit pending inputs buffer
	while pending_inputs.size() > 60:
		pending_inputs.pop_front()

	# Send to server
	NetworkManager.send_player_input.rpc_id(1, input_data)


## Client-side prediction
func _predict_movement(delta: float) -> void:
	_apply_movement(delta)


## Server-side simulation
func _server_simulate(delta: float) -> void:
	_apply_movement(delta)


## Apply movement physics
func _apply_movement(delta: float) -> void:
	# Gravity
	if not is_on_floor():
		velocity.y -= ProjectSettings.get_setting("physics/3d/default_gravity") * delta

	# Jump
	if wants_jump and is_on_floor():
		velocity.y = JUMP_VELOCITY
		wants_jump = false

	# Movement speed
	var speed := SPRINT_SPEED if is_sprinting else WALK_SPEED

	# Ground movement
	if is_on_floor():
		var target_velocity := input_direction * speed
		velocity.x = move_toward(velocity.x, target_velocity.x, ACCELERATION * delta * speed)
		velocity.z = move_toward(velocity.z, target_velocity.z, ACCELERATION * delta * speed)
	else:
		# Air control
		var target_velocity := input_direction * speed * AIR_CONTROL
		velocity.x = move_toward(velocity.x, target_velocity.x, ACCELERATION * delta * speed * AIR_CONTROL)
		velocity.z = move_toward(velocity.z, target_velocity.z, ACCELERATION * delta * speed * AIR_CONTROL)

	# Apply friction when no input
	if input_direction.length() < 0.1 and is_on_floor():
		velocity.x = move_toward(velocity.x, 0, FRICTION * delta * speed)
		velocity.z = move_toward(velocity.z, 0, FRICTION * delta * speed)

	move_and_slide()


## Apply input from network (server-side, called by GameState)
func apply_input(input_data: Dictionary) -> void:
	if not NetworkManager.is_authority():
		return

	# Apply look rotation
	if "look" in input_data:
		look_rotation = input_data.look
		rotation.y = look_rotation.y
		camera_pivot.rotation.x = look_rotation.x

	# Apply movement input
	if "dir" in input_data:
		input_direction = input_data.dir

	# Apply actions
	wants_jump = input_data.get("jump", false)
	wants_sprint = input_data.get("sprint", false)
	wants_primary = input_data.get("primary", false)
	wants_secondary = input_data.get("secondary", false)
	wants_reload = input_data.get("reload", false)
	wants_interact = input_data.get("interact", false)

	is_sprinting = wants_sprint and input_direction.length() > 0.1 and is_on_floor()

	# Handle weapon actions
	if wants_primary:
		_handle_primary_action()
	if wants_secondary:
		_handle_secondary_action()
	if wants_interact:
		_handle_interact()


## Get network state for snapshot (server-side)
func get_network_state() -> Dictionary:
	return {
		"pos": global_position,
		"vel": velocity,
		"rot": rotation.y,
		"pitch": camera_pivot.rotation.x,
		"health": health,
		"dead": is_dead,
		"sprinting": is_sprinting,
	}


## Apply network state from server (client-side)
func apply_network_state(state: Dictionary) -> void:
	if is_local_player:
		# Reconciliation for local player
		_reconcile_with_server(state)
	else:
		# Direct interpolation for remote players
		_interpolate_to_state(state)


## Reconcile local prediction with server state
func _reconcile_with_server(state: Dictionary) -> void:
	var server_pos: Vector3 = state.pos
	var server_vel: Vector3 = state.vel

	# Check if we need correction
	var pos_error := global_position.distance_to(server_pos)

	if pos_error > 0.5:
		# Significant error - snap to server position
		global_position = server_pos
		velocity = server_vel
	elif pos_error > 0.1:
		# Small error - smooth correction
		global_position = global_position.lerp(server_pos, 0.3)
		velocity = velocity.lerp(server_vel, 0.3)

	# Apply other state
	health = state.get("health", health)
	is_dead = state.get("dead", is_dead)


## Interpolate remote player to state
func _interpolate_to_state(state: Dictionary) -> void:
	# Smooth position interpolation
	var target_pos: Vector3 = state.pos
	global_position = global_position.lerp(target_pos, 0.5)

	# Apply rotation
	rotation.y = state.get("rot", rotation.y)
	camera_pivot.rotation.x = state.get("pitch", camera_pivot.rotation.x)

	# Apply state
	health = state.get("health", health)
	is_dead = state.get("dead", is_dead)
	is_sprinting = state.get("sprinting", is_sprinting)


## Handle primary action (shoot/hammer)
func _handle_primary_action() -> void:
	# Get current weapon and trigger
	var weapon := _get_current_weapon()
	if weapon and weapon.has_method("primary_action"):
		weapon.primary_action()


## Handle secondary action (aim/alt fire)
func _handle_secondary_action() -> void:
	var weapon := _get_current_weapon()
	if weapon and weapon.has_method("secondary_action"):
		weapon.secondary_action()


## Handle interact (pickup props, use objects)
func _handle_interact() -> void:
	# Raycast to find interactable
	if not camera:
		return

	var space_state := get_world_3d().direct_space_state
	var from := camera.global_position
	var to := from - camera.global_basis.z * 3.0  # 3 meter reach

	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.exclude = [self]

	var result := space_state.intersect_ray(query)

	if result and result.collider.has_method("interact"):
		result.collider.interact(self)


## Get currently equipped weapon
func _get_current_weapon() -> Node:
	if current_weapon_slot >= 0 and current_weapon_slot < inventory.size():
		return inventory[current_weapon_slot]
	return null


## Take damage (server-side)
func take_damage(amount: float, _from_position: Vector3 = Vector3.ZERO) -> void:
	if not NetworkManager.is_authority():
		return

	if is_dead:
		return

	health -= amount

	if health <= 0:
		health = 0
		_die()


## Die (server-side)
func _die() -> void:
	is_dead = true
	GameState.player_died.emit(peer_id)

	# Could trigger respawn timer, spectate mode, etc.


## Respawn (server-side)
func respawn(spawn_position: Vector3) -> void:
	if not NetworkManager.is_authority():
		return

	global_position = spawn_position
	velocity = Vector3.ZERO
	health = max_health
	is_dead = false


## Get camera for weapons/tools
func get_camera() -> Camera3D:
	return camera


## Get camera pivot for weapon attachment
func get_camera_pivot() -> Node3D:
	return camera_pivot
