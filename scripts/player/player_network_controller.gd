extends Node
class_name PlayerNetworkController
## PlayerNetworkController - Authority enforcement & network sync
##
## Handles:
## - Authority enforcement
## - Input replication
## - State replication
## - Prediction & reconciliation (lightweight)
##
## Server authoritative model:
## - Client sends input
## - Server simulates
## - Server sends back state
## - Client interpolates/reconciles

signal state_received(state: Dictionary)

# Network identity
var peer_id: int = 0
var is_local_player := false
var is_authority := false

# Input buffering for client-side prediction
var pending_inputs: Array[Dictionary] = []
var input_sequence: int = 0
var last_acked_sequence: int = 0

# Reconciliation
var last_server_position := Vector3.ZERO
var last_server_velocity := Vector3.ZERO
var reconciliation_threshold := 0.1  # Meters
var snap_threshold := 0.5  # Snap if error exceeds this

# Interpolation (for remote players)
var interpolator: NetworkInterpolator = null
var interpolation_buffer: Array[Dictionary] = []  # Legacy fallback
var interpolation_delay := 0.1  # 100ms buffer
var last_render_time := 0.0

# References
var body: CharacterBody3D = null
var movement_controller: MovementController = null
var combat_controller: CombatController = null
var animation_controller: AnimationController = null
var inventory_runtime: InventoryRuntime = null
var camera_pivot: Node3D = null


func initialize(p_body: CharacterBody3D, p_peer_id: int) -> void:
	body = p_body
	peer_id = p_peer_id
	is_local_player = peer_id == multiplayer.get_unique_id()
	is_authority = multiplayer.is_server()

	# Create interpolator for remote players
	if not is_local_player:
		interpolator = NetworkInterpolator.new()

	# Get sibling controllers
	movement_controller = body.get_node_or_null("MovementController")
	combat_controller = body.get_node_or_null("CombatController")
	animation_controller = body.get_node_or_null("AnimationController")
	inventory_runtime = body.get_node_or_null("InventoryRuntime")
	camera_pivot = body.get_node_or_null("CameraPivot")

	# Connect signals
	if combat_controller:
		combat_controller.fire_requested.connect(_on_fire_requested)
		combat_controller.reload_requested.connect(_on_reload_requested)


func _physics_process(delta: float) -> void:
	if is_local_player and not is_authority:
		_client_tick(delta)
	elif is_authority:
		_server_tick(delta)
	else:
		_remote_player_tick(delta)


## Client tick - gather input, send to server, predict locally
func _client_tick(delta: float) -> void:
	# Get camera look rotation
	var look_yaw := body.rotation.y
	var look_pitch := camera_pivot.rotation.x if camera_pivot else 0.0

	# Gather input
	input_sequence += 1
	var input := PlayerInput.gather_local(look_yaw, look_pitch, input_sequence)

	# Store for reconciliation
	pending_inputs.append({
		"seq": input_sequence,
		"input": input,
		"position": body.global_position,
		"velocity": body.velocity,
	})

	# Limit buffer size
	while pending_inputs.size() > 60:
		pending_inputs.pop_front()

	# Send to server
	_send_input_to_server(input)

	# Local prediction
	if movement_controller:
		movement_controller.process_input(input, delta)
		movement_controller.apply_movement(delta)

	if combat_controller:
		combat_controller.process_input(input)


## Server tick - simulate all players authoritatively
func _server_tick(_delta: float) -> void:
	# Server receives inputs via RPC and processes them in GameState
	pass


## Remote player tick - interpolate between received states
func _remote_player_tick(_delta: float) -> void:
	if not interpolator:
		return

	var state := interpolator.get_interpolated_state()
	if state.is_empty():
		return

	# Apply interpolated/extrapolated position
	body.global_position = state.get("position", body.global_position)
	body.velocity = state.get("velocity", Vector3.ZERO)

	# Rotation is stored as Vector3 in interpolator
	var rotation: Vector3 = state.get("rotation", Vector3(0, body.rotation.y, 0))
	body.rotation.y = rotation.y

	if camera_pivot:
		camera_pivot.rotation.x = rotation.x

	# Periodic cleanup
	if Engine.get_physics_frames() % 60 == 0:
		interpolator.cleanup_old_states()


## Send input to server
func _send_input_to_server(input: PlayerInput) -> void:
	NetworkManager.send_player_input.rpc_id(1, input.to_dict())


## Receive and process input on server
func server_receive_input(input_dict: Dictionary) -> void:
	if not is_authority:
		return

	var input := PlayerInput.from_dict(input_dict)

	# Apply look rotation
	body.rotation.y = input.look_yaw
	if camera_pivot:
		camera_pivot.rotation.x = input.look_pitch

	# Process through controllers
	var delta := get_physics_process_delta_time()

	if movement_controller:
		movement_controller.process_input(input, delta)

	if combat_controller:
		combat_controller.process_input(input)


## Get current state for network broadcast
func get_network_state() -> Dictionary:
	var state := {
		"pos": body.global_position,
		"vel": body.velocity,
		"rot": body.rotation.y,
		"pitch": camera_pivot.rotation.x if camera_pivot else 0.0,
		"seq": last_acked_sequence,
		"tick": Engine.get_physics_frames(),
	}

	if movement_controller:
		state.merge(movement_controller.get_state())

	if combat_controller:
		state.merge(combat_controller.get_state())

	if animation_controller:
		state["anim"] = animation_controller.get_current_state_name()

	return state


## Apply network state (called from GameState.apply_snapshot)
func apply_network_state(state: Dictionary) -> void:
	if is_local_player:
		_reconcile_with_server(state)
	else:
		_buffer_state_for_interpolation(state)

	state_received.emit(state)


## Reconcile local prediction with server state
func _reconcile_with_server(state: Dictionary) -> void:
	var server_pos: Vector3 = state.get("pos", body.global_position)
	var server_vel: Vector3 = state.get("vel", body.velocity)
	var server_seq: int = state.get("seq", 0)

	last_server_position = server_pos
	last_server_velocity = server_vel
	last_acked_sequence = server_seq

	# Check prediction error
	var pos_error := body.global_position.distance_to(server_pos)

	if pos_error > snap_threshold:
		# Large error - snap to server
		body.global_position = server_pos
		body.velocity = server_vel
		pending_inputs.clear()
	elif pos_error > reconciliation_threshold:
		# Small error - smooth correction
		body.global_position = body.global_position.lerp(server_pos, 0.3)
		body.velocity = body.velocity.lerp(server_vel, 0.3)

		# Re-simulate unacked inputs
		_resimulate_pending_inputs(server_seq)

	# Apply other state
	if movement_controller:
		movement_controller.apply_state(state)

	if combat_controller:
		combat_controller.apply_state(state)


## Re-simulate inputs that haven't been acked yet
func _resimulate_pending_inputs(acked_seq: int) -> void:
	# Remove acked inputs
	while not pending_inputs.is_empty() and pending_inputs[0].seq <= acked_seq:
		pending_inputs.pop_front()

	# Re-apply remaining inputs
	var delta := get_physics_process_delta_time()
	for pending in pending_inputs:
		var input: PlayerInput = pending.input
		if movement_controller:
			movement_controller.process_input(input, delta)
			movement_controller.apply_movement(delta)


## Buffer state for interpolation (remote players)
func _buffer_state_for_interpolation(state: Dictionary) -> void:
	if interpolator:
		var server_tick: int = state.get("tick", Engine.get_physics_frames())
		var position: Vector3 = state.get("pos", body.global_position)
		var rotation := Vector3(state.get("pitch", 0.0), state.get("rot", body.rotation.y), 0.0)
		var velocity: Vector3 = state.get("vel", Vector3.ZERO)

		interpolator.push_state(server_tick, position, rotation, velocity)

	# Apply animation state immediately (no interpolation needed)
	if animation_controller:
		animation_controller.apply_state(state)


## Apply state immediately (fallback)
func _apply_state_immediate(state: Dictionary) -> void:
	body.global_position = state.get("position", body.global_position)
	body.velocity = state.get("velocity", Vector3.ZERO)
	body.rotation.y = state.get("rotation_y", body.rotation.y)

	if camera_pivot:
		camera_pivot.rotation.x = state.get("pitch", 0.0)


## Get network quality metrics (for debugging/UI)
func get_network_metrics() -> Dictionary:
	if interpolator:
		return interpolator.get_metrics()
	return {
		"buffer_size": 0,
		"is_extrapolating": false,
		"time_since_update": 0.0,
		"interpolation_delay": interpolation_delay,
	}


## Handle fire request (send to server for validation)
func _on_fire_requested(weapon_state: Dictionary) -> void:
	if not is_authority:
		# Client: send to server for validation
		_send_action_to_server("shoot", weapon_state)
	else:
		# Server: validate and apply
		_server_validate_fire(weapon_state)


## Handle reload request
func _on_reload_requested() -> void:
	if not is_authority:
		_send_action_to_server("reload", {})


## Send action to server
func _send_action_to_server(action_type: String, data: Dictionary) -> void:
	NetworkManager.send_action_request.rpc_id(1, action_type, data)


## Server validates fire action
func _server_validate_fire(weapon_state: Dictionary) -> void:
	# Perform server-side raycast
	var origin: Vector3 = weapon_state.get("origin", Vector3.ZERO)
	var direction: Vector3 = weapon_state.get("direction", Vector3.FORWARD)
	var damage: float = weapon_state.get("damage", 25.0)
	var spread: float = weapon_state.get("spread", 0.02)

	# Apply spread
	direction = direction.rotated(Vector3.UP, randf_range(-spread, spread))
	direction = direction.rotated(body.global_basis.x, randf_range(-spread, spread))

	# Raycast
	var space_state := body.get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(origin, origin + direction * 1000.0)
	query.exclude = [body]
	query.collision_mask = 0b00000111  # World, Players, Zombies

	var result := space_state.intersect_ray(query)

	if result:
		var collider := result.collider

		# Damage zombies
		if collider.is_in_group("zombies"):
			var zombie_id: int = collider.get("zombie_id")
			GameState._damage_zombie(zombie_id, damage, result.position)

		# Damage other players (if friendly fire enabled)
		# if collider.is_in_group("players"):
		#     collider.take_damage(damage, result.position)
