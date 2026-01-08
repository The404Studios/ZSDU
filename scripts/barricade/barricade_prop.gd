extends RigidBody3D
class_name BarricadeProp
## BarricadeProp - Physics-enabled prop for barricading
##
## JetBoom-style prop handling:
## - FREE:   Physics-simulated, nobody holding
## - HELD:   Frozen (kinematic), owned by one player
## - NAILED: Physics-simulated with constraints
##
## Props don't have HP - nails do.
## Physics determines what happens when nails break.

enum PropMode {
	FREE,
	HELD,
	NAILED
}

# Prop info
@export var prop_id: int = 0
@export var prop_name: String = "Prop"
@export var prop_mass: float = 10.0
@export var max_nails: int = 3  # JetBoom rule: max 3 nails per prop

# Prop state
var current_mode: PropMode = PropMode.FREE
var held_by_peer: int = -1
var attached_nail_ids: Array[int] = []

# Hold state (server-controlled)
var hold_offset: Vector3 = Vector3(0, 0, -2.0)  # Relative to player camera
var hold_rotation: Vector3 = Vector3.ZERO       # Euler angles

# Interpolation (client-side)
var _target_position: Vector3 = Vector3.ZERO
var _target_rotation: Vector3 = Vector3.ZERO
var _interpolation_speed: float = 15.0

# Visual feedback
var is_highlighted := false

# Constants
const HOLD_DISTANCE_MIN := 1.5
const HOLD_DISTANCE_MAX := 3.5
const ROTATION_SPEED := 2.0


func _ready() -> void:
	# Configure physics
	mass = prop_mass
	gravity_scale = 1.0
	can_sleep = true

	# Set collision layers (Props layer)
	collision_layer = 8  # Layer 4
	collision_mask = 27  # World, Players, Zombies, Props

	# Add to groups
	add_to_group("props")

	# Register with GameState on server
	if NetworkManager.is_authority():
		prop_id = GameState.register_prop_with_state(self, "")


func _physics_process(delta: float) -> void:
	match current_mode:
		PropMode.FREE:
			# Normal physics - nothing special
			pass

		PropMode.HELD:
			if NetworkManager.is_authority():
				_server_update_held_position(delta)
			else:
				_client_interpolate_held(delta)

		PropMode.NAILED:
			# Physics with constraints - handled by joints
			pass


# ============================================
# SERVER-SIDE HELD PROP POSITIONING
# ============================================

func _server_update_held_position(_delta: float) -> void:
	if held_by_peer < 0:
		return

	if held_by_peer not in GameState.players:
		release()
		return

	var holder: Node3D = GameState.players[held_by_peer]
	if not is_instance_valid(holder):
		release()
		return

	# Get player camera for positioning
	var camera: Camera3D = holder.get_camera() if holder.has_method("get_camera") else null
	if not camera:
		release()
		return

	# Calculate world position from hold offset
	var cam_transform := camera.global_transform

	# Apply hold offset (forward = -Z)
	var world_offset := cam_transform.basis * hold_offset
	var target_pos := cam_transform.origin + world_offset

	# Apply hold rotation
	var target_rot := hold_rotation

	# Set position directly (prop is frozen)
	global_position = target_pos
	rotation = target_rot


# ============================================
# CLIENT-SIDE INTERPOLATION
# ============================================

func _client_interpolate_held(delta: float) -> void:
	# Smooth interpolation to server position
	global_position = global_position.lerp(_target_position, _interpolation_speed * delta)
	rotation = rotation.lerp(_target_rotation, _interpolation_speed * delta)


# ============================================
# PICKUP SYSTEM (Server-Authoritative)
# ============================================

## Attempt to pick up prop (server-side only)
func pickup(peer_id: int) -> bool:
	if not NetworkManager.is_authority():
		return false

	# Validation
	if current_mode == PropMode.HELD:
		return false  # Already held

	if is_nailed():
		return false  # Can't pick up nailed props

	if peer_id not in GameState.players:
		return false

	var player: Node3D = GameState.players[peer_id]
	if not is_instance_valid(player):
		return false

	# Distance check
	var distance := global_position.distance_to(player.global_position)
	if distance > 4.0:
		return false

	# SUCCESS: Transfer authority
	held_by_peer = peer_id
	current_mode = PropMode.HELD

	# FREEZE physics (critical for JetBoom feel)
	freeze = true
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO

	# Initialize hold offset based on current position relative to player
	var camera: Camera3D = player.get_camera() if player.has_method("get_camera") else null
	if camera:
		var rel_pos := global_position - camera.global_position
		var local_offset := camera.global_transform.basis.inverse() * rel_pos
		hold_offset = local_offset
		hold_offset.z = clampf(hold_offset.z, -HOLD_DISTANCE_MAX, -HOLD_DISTANCE_MIN)

	hold_rotation = rotation

	print("[Prop %d] Picked up by peer %d" % [prop_id, peer_id])
	return true


## Release prop (server-side only)
func release() -> void:
	if not NetworkManager.is_authority():
		return

	if current_mode != PropMode.HELD:
		return

	var was_holder := held_by_peer
	held_by_peer = -1

	# Determine new mode
	if is_nailed():
		current_mode = PropMode.NAILED
	else:
		current_mode = PropMode.FREE

	# UNFREEZE physics
	freeze = false

	# Apply small impulse in forward direction (feels good)
	if was_holder in GameState.players:
		var player: Node3D = GameState.players[was_holder]
		if is_instance_valid(player):
			var camera: Camera3D = player.get_camera() if player.has_method("get_camera") else null
			if camera:
				var forward := -camera.global_basis.z
				apply_central_impulse(forward * mass * 0.5)

	print("[Prop %d] Released" % prop_id)


## Throw prop (server-side)
func throw_prop(direction: Vector3, force: float = 8.0) -> void:
	if not NetworkManager.is_authority():
		return

	if current_mode != PropMode.HELD:
		return

	held_by_peer = -1
	current_mode = PropMode.FREE
	freeze = false

	apply_central_impulse(direction * force * mass)
	print("[Prop %d] Thrown" % prop_id)


# ============================================
# ROTATION CONTROLS (Server processes client input)
# ============================================

## Apply rotation delta (server-side, from client input)
func apply_rotation_delta(delta_rotation: Vector3) -> void:
	if not NetworkManager.is_authority():
		return

	if current_mode != PropMode.HELD:
		return

	# Clamp rotation speed
	delta_rotation = delta_rotation.clamp(
		Vector3(-ROTATION_SPEED, -ROTATION_SPEED, -ROTATION_SPEED),
		Vector3(ROTATION_SPEED, ROTATION_SPEED, ROTATION_SPEED)
	)

	hold_rotation += delta_rotation

	# Normalize angles
	hold_rotation.x = wrapf(hold_rotation.x, -PI, PI)
	hold_rotation.y = wrapf(hold_rotation.y, -PI, PI)
	hold_rotation.z = wrapf(hold_rotation.z, -PI, PI)


## Adjust hold distance (server-side, from client input)
func adjust_hold_distance(delta: float) -> void:
	if not NetworkManager.is_authority():
		return

	if current_mode != PropMode.HELD:
		return

	hold_offset.z = clampf(hold_offset.z + delta, -HOLD_DISTANCE_MAX, -HOLD_DISTANCE_MIN)


# ============================================
# NAIL MANAGEMENT
# ============================================

## Check if prop can accept another nail
func can_accept_nail() -> bool:
	return attached_nail_ids.size() < max_nails


## Register a nail attached to this prop
func register_nail(nail_id: int) -> void:
	if nail_id not in attached_nail_ids:
		attached_nail_ids.append(nail_id)

		# If we were FREE, now we're NAILED
		if current_mode == PropMode.FREE:
			current_mode = PropMode.NAILED


## Unregister a nail from this prop
func unregister_nail(nail_id: int) -> void:
	attached_nail_ids.erase(nail_id)

	# If no more nails and not held, go back to FREE
	if attached_nail_ids.is_empty() and current_mode == PropMode.NAILED:
		current_mode = PropMode.FREE


## Get nailed state
func is_nailed() -> bool:
	return attached_nail_ids.size() > 0


## Check if being held
func is_held() -> bool:
	return current_mode == PropMode.HELD


## Get holder peer ID
func get_holder() -> int:
	return held_by_peer


# ============================================
# NETWORK STATE
# ============================================

## Get network state for snapshot
func get_network_state() -> Dictionary:
	return {
		"pos": global_position,
		"rot": rotation,
		"vel": linear_velocity,
		"ang_vel": angular_velocity,
		"mode": current_mode,
		"holder": held_by_peer,
		"hold_offset": hold_offset,
		"hold_rot": hold_rotation,
		"sleeping": sleeping,
		"nails": attached_nail_ids.duplicate(),
	}


## Apply network state (client-side)
func apply_network_state(state: Dictionary) -> void:
	if NetworkManager.is_authority():
		return

	var new_mode: PropMode = state.get("mode", PropMode.FREE) as PropMode
	current_mode = new_mode
	held_by_peer = state.get("holder", -1)

	# Sync attached nails
	var synced_nails: Array = state.get("nails", [])
	attached_nail_ids.clear()
	for nail_id in synced_nails:
		attached_nail_ids.append(nail_id as int)

	match current_mode:
		PropMode.FREE, PropMode.NAILED:
			# Interpolate physics state
			freeze = false
			var target_pos: Vector3 = state.pos
			var target_rot: Vector3 = state.rot

			if state.get("sleeping", false):
				global_position = target_pos
				rotation = target_rot
			else:
				global_position = global_position.lerp(target_pos, 0.5)
				rotation = rotation.lerp(target_rot, 0.5)

		PropMode.HELD:
			# Prop is frozen, use target for interpolation
			freeze = true
			_target_position = state.pos
			_target_rotation = state.rot
			hold_offset = state.get("hold_offset", hold_offset)
			hold_rotation = state.get("hold_rot", hold_rotation)


# ============================================
# VISUAL FEEDBACK
# ============================================

## Highlight for interaction (client-side visual)
func set_highlighted(highlighted: bool) -> void:
	is_highlighted = highlighted
	# TODO: Change material/outline


## Interact (toggle pickup/drop)
func interact(player: Node3D) -> void:
	if not NetworkManager.is_authority():
		return

	var peer_id: int = player.get("peer_id")
	if peer_id <= 0:
		return

	if current_mode == PropMode.HELD:
		if held_by_peer == peer_id:
			release()
	else:
		pickup(peer_id)
