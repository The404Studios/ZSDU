extends Node
class_name PropHandler
## PropHandler - Client-side prop interaction controller
##
## Handles:
## - Prop pickup/drop input
## - Rotation controls (mouse wheel, Q/E)
## - Hold distance adjustment
## - Nail placement while holding
## - Visual feedback (crosshair, highlights)

signal prop_picked_up(prop_id: int)
signal prop_dropped(prop_id: int)
signal nail_placed(nail_id: int)
signal carrying_state_changed(is_carrying: bool, prop_mass: float)

# Carry speed penalties
const CARRY_SPEED_MULT := 0.6  # 60% speed when carrying
const CARRY_NO_SPRINT := true  # Can't sprint while carrying
const CARRY_NO_JUMP := true    # Can't jump while carrying

# Owner reference
var owner_player: PlayerController = null
var owner_camera: Camera3D = null

# Currently held prop (client prediction)
var held_prop_id: int = -1
var is_holding := false
var held_prop_mass: float = 1.0  # Mass affects speed penalty

# Rotation input state
var rotation_input := Vector3.ZERO
var distance_input := 0.0

# Input settings
const ROTATION_SENSITIVITY := 0.1
const DISTANCE_SENSITIVITY := 0.3
const FINE_ROTATION_MULT := 0.25

# Raycast settings
const INTERACT_DISTANCE := 4.0
const NAIL_DISTANCE := 3.0

# Rate limiting
var last_action_time := 0.0
const BASE_ACTION_COOLDOWN := 0.1
const BASE_NAIL_COOLDOWN := 0.25


func _ready() -> void:
	set_process_input(false)  # Enable when initialized


func initialize(player: PlayerController) -> void:
	owner_player = player
	owner_camera = player.get_camera()
	set_process_input(true)


func _input(event: InputEvent) -> void:
	if not owner_player or not owner_player.is_local_player:
		return

	# Mouse wheel for rotation/distance
	if event is InputEventMouseButton:
		if event.pressed:
			match event.button_index:
				MOUSE_BUTTON_WHEEL_UP:
					if Input.is_action_pressed("sprint"):
						# Shift + scroll = distance
						distance_input = DISTANCE_SENSITIVITY
					else:
						# Scroll = Y rotation
						rotation_input.y += ROTATION_SENSITIVITY
				MOUSE_BUTTON_WHEEL_DOWN:
					if Input.is_action_pressed("sprint"):
						distance_input = -DISTANCE_SENSITIVITY
					else:
						rotation_input.y -= ROTATION_SENSITIVITY


func _process(delta: float) -> void:
	if not owner_player or not owner_player.is_local_player:
		return

	# Gather rotation input from keys
	_gather_rotation_input(delta)

	# Send input to server if holding
	if is_holding and (rotation_input.length() > 0.001 or abs(distance_input) > 0.001):
		_send_hold_update()
		rotation_input = Vector3.ZERO
		distance_input = 0.0

	# Update crosshair / highlights
	_update_interaction_feedback()


func _gather_rotation_input(delta: float) -> void:
	var rot_speed := ROTATION_SENSITIVITY
	if Input.is_action_pressed("sprint"):
		rot_speed *= FINE_ROTATION_MULT

	# Q/E for roll (Z rotation)
	if Input.is_action_pressed("slot_1"):  # Reusing slot_1 as Q
		rotation_input.z -= rot_speed * delta * 60.0
	if Input.is_action_pressed("slot_3"):  # Reusing slot_3 as E equivalent
		rotation_input.z += rot_speed * delta * 60.0

	# Could add more rotation keys here


## Handle interact input (E key)
func handle_interact() -> void:
	if not _can_act():
		return

	if is_holding:
		# Drop prop
		_request_drop()
	else:
		# Try to pick up prop
		var prop := _raycast_for_prop()
		if prop:
			_request_pickup(prop.prop_id)


## Handle primary action while holding (nail placement)
func handle_primary_action() -> void:
	if not is_holding:
		return

	if not _can_act(true):  # true = nail action, use barricade_speed modifier
		return

	# Try to nail the held prop
	var nail_target := _raycast_for_nail_surface()
	if nail_target:
		_request_nail_while_holding(nail_target)


## Handle secondary action (throw)
func handle_secondary_action() -> void:
	if not is_holding:
		return

	if not _can_act():
		return

	_request_throw()


func _can_act(is_nail_action: bool = false) -> bool:
	var current_time := Time.get_ticks_msec() / 1000.0

	# Get base cooldown
	var base_cd := BASE_NAIL_COOLDOWN if is_nail_action else BASE_ACTION_COOLDOWN

	# Apply barricade_speed modifier from equipment (faster = shorter cooldown)
	var cooldown := base_cd
	if owner_player and owner_player.equipment_runtime:
		var barricade_speed: float = owner_player.equipment_runtime.get_stat("barricade_speed")
		if barricade_speed > 0:
			cooldown = base_cd / barricade_speed  # 1.25x speed = 0.8x cooldown

	if current_time - last_action_time < cooldown:
		return false
	last_action_time = current_time
	return true


# ============================================
# RAYCASTING
# ============================================

func _raycast_for_prop() -> BarricadeProp:
	if not owner_camera:
		return null

	var space_state := owner_player.get_world_3d().direct_space_state
	var from := owner_camera.global_position
	var to := from - owner_camera.global_basis.z * INTERACT_DISTANCE

	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.collision_mask = 0b00001000  # Props layer
	query.exclude = [owner_player]

	var result := space_state.intersect_ray(query)

	if result and result.collider is BarricadeProp:
		return result.collider as BarricadeProp

	return null


func _raycast_for_nail_surface() -> Dictionary:
	if not owner_camera:
		return {}

	var space_state := owner_player.get_world_3d().direct_space_state
	var from := owner_camera.global_position
	var to := from - owner_camera.global_basis.z * NAIL_DISTANCE

	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.collision_mask = 0b00001001  # World + Props
	query.exclude = [owner_player]

	# If holding a prop, exclude it from raycast
	if held_prop_id >= 0 and held_prop_id in GameState.props:
		var held_prop: Node = GameState.props[held_prop_id]
		if is_instance_valid(held_prop):
			query.exclude.append(held_prop)

	var result := space_state.intersect_ray(query)

	if result:
		var surface_id := -1  # World
		if result.collider is BarricadeProp:
			surface_id = result.collider.prop_id

		return {
			"position": result.position,
			"normal": result.normal,
			"surface_id": surface_id,
		}

	return {}


# ============================================
# NETWORK REQUESTS
# ============================================

func _request_pickup(prop_id: int) -> void:
	NetworkManager.request_action.rpc_id(1, "pickup_prop", {
		"prop_id": prop_id,
	})

	# Optimistic: assume success
	_set_carrying(true, prop_id)


func _request_drop() -> void:
	NetworkManager.request_action.rpc_id(1, "drop_prop", {
		"prop_id": held_prop_id,
	})

	var dropped_id := held_prop_id
	_set_carrying(false)
	prop_dropped.emit(dropped_id)


func _request_throw() -> void:
	if not owner_camera:
		return

	var direction := -owner_camera.global_basis.z

	NetworkManager.request_action.rpc_id(1, "throw_prop", {
		"prop_id": held_prop_id,
		"direction": direction,
	})

	var thrown_id := held_prop_id
	_set_carrying(false)
	prop_dropped.emit(thrown_id)


func _send_hold_update() -> void:
	NetworkManager.request_action.rpc_id(1, "hold_update", {
		"prop_id": held_prop_id,
		"rotation_delta": rotation_input,
		"distance_delta": distance_input,
	})


func _request_nail_while_holding(target: Dictionary) -> void:
	NetworkManager.request_action.rpc_id(1, "nail_while_holding", {
		"prop_id": held_prop_id,
		"surface_id": target.surface_id,
		"position": target.position,
		"normal": target.normal,
	})


# ============================================
# VISUAL FEEDBACK
# ============================================

func _update_interaction_feedback() -> void:
	# Highlight props we can interact with
	var prop := _raycast_for_prop()

	# Clear previous highlights
	for prop_id in GameState.props:
		var p: BarricadeProp = GameState.props[prop_id] as BarricadeProp
		if p:
			p.set_highlighted(false)

	# Highlight current target
	if prop and not is_holding:
		prop.set_highlighted(true)


# ============================================
# SERVER RESPONSE HANDLING
# ============================================

## Called when server confirms pickup
func on_pickup_confirmed(prop_id: int) -> void:
	_set_carrying(true, prop_id)
	prop_picked_up.emit(prop_id)


## Called when server rejects pickup
func on_pickup_rejected() -> void:
	_set_carrying(false)


## Called when server confirms drop/release
func on_drop_confirmed() -> void:
	var old_id := held_prop_id
	_set_carrying(false)
	prop_dropped.emit(old_id)


## Called when prop is forcibly taken (by server or another event)
func on_prop_lost() -> void:
	_set_carrying(false)


## Sync with server state
func sync_held_state(prop_id: int) -> void:
	if prop_id >= 0:
		_set_carrying(true, prop_id)
	else:
		_set_carrying(false)


## Set carrying state and emit signal for movement penalties
func _set_carrying(carrying: bool, prop_id: int = -1) -> void:
	var was_holding := is_holding
	is_holding = carrying
	held_prop_id = prop_id if carrying else -1

	# Get prop mass for speed calculations
	if carrying and prop_id >= 0 and GameState and prop_id in GameState.props:
		var prop: Node = GameState.props[prop_id]
		if prop is RigidBody3D:
			held_prop_mass = prop.mass
		else:
			held_prop_mass = 1.0
	else:
		held_prop_mass = 1.0

	# Notify player of state change for movement penalties
	if was_holding != carrying:
		carrying_state_changed.emit(carrying, held_prop_mass)


## Get speed multiplier based on carrying state
func get_carry_speed_mult() -> float:
	if is_holding:
		# Heavier props = slower (clamped between 0.4 and 0.7)
		var mass_factor := clampf(1.0 - (held_prop_mass - 1.0) * 0.1, 0.4, 0.7)
		return CARRY_SPEED_MULT * mass_factor
	return 1.0


## Check if player can sprint (can't while carrying)
func can_sprint() -> bool:
	return not (is_holding and CARRY_NO_SPRINT)


## Check if player can jump (can't while carrying)
func can_jump() -> bool:
	return not (is_holding and CARRY_NO_JUMP)
