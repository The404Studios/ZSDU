extends CharacterBody3D
class_name PlayerController
## PlayerController - Main player orchestrator
##
## This is the root node that coordinates all subsystems:
## - MovementController: Physics, stamina, posture
## - CombatController: Weapons, reloads, ADS
## - AnimationController: Animation state machine
## - InventoryRuntime: Ephemeral in-raid inventory
## - PlayerNetworkController: Authority, sync, prediction
##
## The controller does NOT own persistence, inventory truth, or economy.
## Everything flows through the backend via RaidManager.

signal player_ready()
signal player_died()
signal player_spawned(position: Vector3)

# Player identity
var peer_id: int = 0
var character_id: String = ""
var is_local_player := false

# Health (server-authoritative)
@export var max_health := 100.0
var health: float = 100.0
var is_dead := false

# Mouse look
var look_yaw: float = 0.0
var look_pitch: float = 0.0
const MOUSE_SENSITIVITY := 0.002

# Node references
@onready var collision_shape: CollisionShape3D = $CollisionShape3D
@onready var mesh: MeshInstance3D = $MeshInstance3D
@onready var camera_pivot: Node3D = $CameraPivot
@onready var camera: Camera3D = $CameraPivot/Camera3D

# Controllers (added as children dynamically)
var movement_controller: MovementController = null
var combat_controller: CombatController = null
var animation_controller: AnimationController = null
var inventory_runtime: InventoryRuntime = null
var network_controller: PlayerNetworkController = null

# Prop handler (for barricade system)
var prop_handler: PropHandler = null


func _ready() -> void:
	peer_id = get_multiplayer_authority()
	is_local_player = peer_id == multiplayer.get_unique_id()

	_setup_controllers()
	_setup_local_player()

	health = max_health
	player_ready.emit()


func _setup_controllers() -> void:
	# Movement Controller
	movement_controller = MovementController.new()
	movement_controller.name = "MovementController"
	add_child(movement_controller)
	movement_controller.initialize(self, collision_shape)

	# Animation Controller (create even without animations for state tracking)
	animation_controller = AnimationController.new()
	animation_controller.name = "AnimationController"
	add_child(animation_controller)
	# Will be initialized with AnimationPlayer when FP_Arms are added

	# Inventory Runtime
	inventory_runtime = InventoryRuntime.new()
	inventory_runtime.name = "InventoryRuntime"
	add_child(inventory_runtime)

	# Combat Controller
	combat_controller = CombatController.new()
	combat_controller.name = "CombatController"
	add_child(combat_controller)
	combat_controller.initialize(animation_controller, inventory_runtime, camera)

	# Network Controller
	network_controller = PlayerNetworkController.new()
	network_controller.name = "NetworkController"
	add_child(network_controller)
	network_controller.initialize(self, peer_id)

	# Connect signals
	movement_controller.posture_changed.connect(_on_posture_changed)
	movement_controller.stamina_changed.connect(_on_stamina_changed)
	combat_controller.fire_requested.connect(_on_fire_requested)


func _setup_local_player() -> void:
	if is_local_player:
		# Enable camera
		camera.current = true
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

		# Hide own mesh (first person)
		if mesh:
			mesh.visible = false

		# Initialize prop handler
		prop_handler = PropHandler.new()
		add_child(prop_handler)
		prop_handler.initialize(self)

		# Register raid if we have one
		_register_raid_with_server()
	else:
		# Remote player
		camera.current = false


func _register_raid_with_server() -> void:
	# Called by client to send their raid info to server
	if RaidManager:
		RaidManager.client_register_raid()


func _input(event: InputEvent) -> void:
	if not is_local_player:
		return

	if is_dead:
		return

	# Mouse look
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		look_yaw -= event.relative.x * MOUSE_SENSITIVITY
		look_pitch -= event.relative.y * MOUSE_SENSITIVITY
		look_pitch = clampf(look_pitch, -PI/2 + 0.1, PI/2 - 0.1)

		# Apply rotation locally for responsive feel
		rotation.y = look_yaw
		camera_pivot.rotation.x = look_pitch


func _physics_process(delta: float) -> void:
	if is_dead:
		return

	# Network controller handles all the tick logic based on authority
	# Movement and combat are processed there

	# Update animation from movement state
	if animation_controller and movement_controller:
		animation_controller.update_from_movement(
			velocity,
			movement_controller.posture,
			is_on_floor(),
			movement_controller.is_sprinting
		)


## Initialize loadout from RaidManager (called when raid starts)
func initialize_loadout(loadout: Dictionary, p_character_id: String, raid_id: String) -> void:
	character_id = p_character_id

	if inventory_runtime:
		inventory_runtime.initialize_from_loadout(loadout, p_character_id, raid_id)

	# Equip first weapon
	if combat_controller and inventory_runtime:
		var weapon := inventory_runtime.get_weapon(0)
		if weapon:
			combat_controller.bind_weapon(weapon)


## Get network state for snapshot (called by GameState)
func get_network_state() -> Dictionary:
	if network_controller:
		return network_controller.get_network_state()

	# Fallback if no network controller
	return {
		"pos": global_position,
		"vel": velocity,
		"rot": rotation.y,
		"pitch": camera_pivot.rotation.x if camera_pivot else 0.0,
		"health": health,
		"dead": is_dead,
	}


## Apply network state from server (called by GameState)
func apply_network_state(state: Dictionary) -> void:
	# Apply health
	health = state.get("health", health)
	is_dead = state.get("dead", is_dead)

	if network_controller:
		network_controller.apply_network_state(state)


## Apply input from network (server-side, called by GameState)
func apply_input(input_data: Dictionary) -> void:
	if not NetworkManager.is_authority():
		return

	if network_controller:
		network_controller.server_receive_input(input_data)


## Take damage (server-side only)
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

	if animation_controller:
		animation_controller.play_death()

	player_died.emit()
	GameState.player_died.emit(peer_id)


## Respawn (server-side)
func respawn(spawn_position: Vector3) -> void:
	if not NetworkManager.is_authority():
		return

	global_position = spawn_position
	velocity = Vector3.ZERO
	health = max_health
	is_dead = false

	player_spawned.emit(spawn_position)


## Request extraction (called when player reaches extraction zone)
func request_extract() -> void:
	if is_local_player:
		RaidManager.client_request_extract()


# ============================================
# SIGNAL HANDLERS
# ============================================

func _on_posture_changed(_posture: int) -> void:
	# Could update visuals, camera height, etc.
	pass


func _on_stamina_changed(_current: float, _max_value: float) -> void:
	# Could update HUD
	pass


func _on_fire_requested(_weapon_state: Dictionary) -> void:
	# Visual/audio feedback for local player
	if is_local_player:
		# Play muzzle flash, sound, etc.
		pass


# ============================================
# PUBLIC API
# ============================================

func get_camera() -> Camera3D:
	return camera


func get_camera_pivot() -> Node3D:
	return camera_pivot


func get_prop_handler() -> PropHandler:
	return prop_handler


func is_holding_prop() -> bool:
	return prop_handler != null and prop_handler.is_holding


func get_held_prop_id() -> int:
	if prop_handler:
		return prop_handler.held_prop_id
	return -1


func get_movement_controller() -> MovementController:
	return movement_controller


func get_combat_controller() -> CombatController:
	return combat_controller


func get_inventory_runtime() -> InventoryRuntime:
	return inventory_runtime
