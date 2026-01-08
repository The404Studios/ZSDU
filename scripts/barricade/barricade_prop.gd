extends RigidBody3D
class_name BarricadeProp
## BarricadeProp - Physics-enabled prop for barricading
##
## These are the objects players nail together.
## Props don't have HP - nails do.
## Physics determines what happens when nails break.

# Prop info
@export var prop_id: int = 0
@export var prop_name: String = "Prop"
@export var prop_mass: float = 10.0
@export var max_nails: int = 3  # JetBoom rule: max 3 nails per prop

# Prop state
var is_carried := false
var carrier_id: int = -1  # peer_id of carrying player
var attached_nail_ids: Array[int] = []

# Interaction
var is_highlighted := false

# Carry offset
const CARRY_DISTANCE := 2.0
const CARRY_HEIGHT := 1.2


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
		prop_id = GameState.register_prop(self)


func _physics_process(delta: float) -> void:
	if is_carried and carrier_id >= 0:
		_update_carry_position(delta)


## Update position when being carried
func _update_carry_position(delta: float) -> void:
	if carrier_id not in GameState.players:
		drop()
		return

	var carrier: Node3D = GameState.players[carrier_id]
	if not is_instance_valid(carrier):
		drop()
		return

	# Get target position in front of player
	var camera: Camera3D = carrier.get_camera() if carrier.has_method("get_camera") else null
	var target_pos: Vector3

	if camera:
		target_pos = camera.global_position - camera.global_basis.z * CARRY_DISTANCE
		target_pos.y = carrier.global_position.y + CARRY_HEIGHT
	else:
		target_pos = carrier.global_position + carrier.global_basis.z * CARRY_DISTANCE
		target_pos.y += CARRY_HEIGHT

	# Smoothly move to target (physics-based)
	var direction := global_position.direction_to(target_pos)
	var distance := global_position.distance_to(target_pos)

	if distance > 0.1:
		linear_velocity = direction * distance * 10.0
	else:
		linear_velocity = Vector3.ZERO

	# Reduce angular velocity while carried
	angular_velocity = angular_velocity.lerp(Vector3.ZERO, 5.0 * delta)


## Pickup this prop (server-side)
func pickup(peer_id: int) -> bool:
	if not NetworkManager.is_authority():
		return false

	# Can't pickup if already carried
	if is_carried:
		return false

	# Can't pickup if nailed
	if attached_nail_ids.size() > 0:
		return false

	# Check player exists
	if peer_id not in GameState.players:
		return false

	is_carried = true
	carrier_id = peer_id

	# Reduce gravity while carried
	gravity_scale = 0.1

	# Wake up physics
	sleeping = false

	return true


## Drop this prop (server-side)
func drop() -> void:
	if not NetworkManager.is_authority():
		return

	is_carried = false
	carrier_id = -1

	# Restore gravity
	gravity_scale = 1.0


## Throw this prop (server-side)
func throw(direction: Vector3, force: float = 10.0) -> void:
	if not NetworkManager.is_authority():
		return

	drop()

	# Apply impulse
	apply_central_impulse(direction * force * mass)


## Check if prop can accept another nail
func can_accept_nail() -> bool:
	return attached_nail_ids.size() < max_nails


## Register a nail attached to this prop
func register_nail(nail_id: int) -> void:
	if nail_id not in attached_nail_ids:
		attached_nail_ids.append(nail_id)


## Unregister a nail from this prop
func unregister_nail(nail_id: int) -> void:
	attached_nail_ids.erase(nail_id)


## Get nailed state
func is_nailed() -> bool:
	return attached_nail_ids.size() > 0


## Interact (used by player)
func interact(player: Node3D) -> void:
	if not NetworkManager.is_authority():
		return

	var peer_id: int = player.get("peer_id")
	if peer_id <= 0:
		return

	if is_carried:
		if carrier_id == peer_id:
			drop()
	else:
		pickup(peer_id)


## Highlight for interaction (client-side visual)
func set_highlighted(highlighted: bool) -> void:
	is_highlighted = highlighted
	# Could change material/outline here


## Get network state
func get_network_state() -> Dictionary:
	return {
		"pos": global_position,
		"rot": rotation,
		"vel": linear_velocity,
		"ang_vel": angular_velocity,
		"carried": is_carried,
		"carrier": carrier_id,
		"sleeping": sleeping,
	}


## Apply network state (client-side)
func apply_network_state(state: Dictionary) -> void:
	if NetworkManager.is_authority():
		return

	# Interpolate position for smooth visuals
	if not state.get("sleeping", false):
		global_position = global_position.lerp(state.pos, 0.5)
		rotation = rotation.lerp(state.rot, 0.5)
	else:
		# Snap to position if sleeping
		global_position = state.pos
		rotation = state.rot

	is_carried = state.get("carried", false)
	carrier_id = state.get("carrier", -1)
