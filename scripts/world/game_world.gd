extends Node3D
## GameWorld - Main game scene controller
##
## Initializes the game world, spawns players, manages waves.

# Node references
@onready var players_container: Node = $Players
@onready var zombies_container: Node = $Zombies
@onready var props_container: Node = $Props
@onready var spawn_points: Node = $SpawnPoints
@onready var wave_manager: WaveManager = $WaveManager
@onready var hud: Control = $HUD

# Player spawn points
var player_spawn_positions: Array[Vector3] = []


func _ready() -> void:
	# Initialize GameState with world reference
	GameState.initialize_world(self)

	# Collect spawn points
	_collect_spawn_points()

	# Connect signals
	NetworkManager.player_joined.connect(_on_player_joined)
	NetworkManager.player_left.connect(_on_player_left)
	GameState.zombie_killed.connect(wave_manager.on_zombie_killed)

	# Spawn existing players (for late joiners)
	for peer_id in NetworkManager.connected_peers:
		_spawn_player(peer_id)

	# Start waves on server after delay
	if NetworkManager.is_authority():
		await get_tree().create_timer(3.0).timeout
		wave_manager.start_waves()


func _collect_spawn_points() -> void:
	player_spawn_positions.clear()

	if spawn_points:
		for child in spawn_points.get_children():
			if child is Node3D and child.name.begins_with("PlayerSpawn"):
				player_spawn_positions.append(child.global_position)

	# Default spawn points if none found
	if player_spawn_positions.is_empty():
		player_spawn_positions = [
			Vector3(0, 1, 0),
			Vector3(2, 1, 0),
			Vector3(-2, 1, 0),
			Vector3(0, 1, 2),
		]


func _on_player_joined(peer_id: int) -> void:
	if NetworkManager.is_authority():
		_spawn_player(peer_id)


func _on_player_left(peer_id: int) -> void:
	# Cleanup handled by GameState
	pass


func _spawn_player(peer_id: int) -> void:
	if not NetworkManager.is_authority():
		return

	# Get spawn position
	var spawn_idx := (peer_id - 1) % player_spawn_positions.size()
	var spawn_pos := player_spawn_positions[spawn_idx]

	# Spawn via GameState
	var player := GameState.spawn_player(peer_id, spawn_pos)

	if player:
		# Give starting equipment
		_equip_player(player)


func _equip_player(player: PlayerController) -> void:
	# Give hammer
	var hammer_scene := load("res://scenes/weapons/hammer.tscn")
	if hammer_scene:
		var hammer: Hammer = hammer_scene.instantiate()
		hammer.initialize(player)

		var camera_pivot := player.get_camera_pivot()
		if camera_pivot:
			camera_pivot.add_child(hammer)
			hammer.position = Vector3(0.3, -0.2, -0.5)  # Offset for first person view

		player.inventory.append(hammer)
		player.current_weapon_slot = 0


## Fast round reset (for testing or game restart)
func reset_round() -> void:
	if not NetworkManager.is_authority():
		return

	# Reset waves
	wave_manager.reset_waves()

	# Clear all nails
	for nail_id in GameState.nails.keys():
		if GameState.nails[nail_id].has("joint_node"):
			var joint = GameState.nails[nail_id].joint_node
			if is_instance_valid(joint):
				joint.queue_free()
	GameState.nails.clear()

	# Reset props to original positions
	for prop_id in GameState.props:
		var prop: BarricadeProp = GameState.props[prop_id] as BarricadeProp
		if prop:
			prop.attached_nail_ids.clear()
			# Could reset position to original if stored

	# Respawn all players
	for peer_id in GameState.players:
		var player: PlayerController = GameState.players[peer_id] as PlayerController
		if player:
			var spawn_idx := (peer_id - 1) % player_spawn_positions.size()
			player.respawn(player_spawn_positions[spawn_idx])

	# Notify clients
	NetworkManager.broadcast_event.rpc("round_reset", {})

	# Restart waves
	await get_tree().create_timer(3.0).timeout
	wave_manager.start_waves()


func _input(event: InputEvent) -> void:
	# Debug: Reset round with F5 (server only)
	if event.is_action_pressed("ui_page_down") and NetworkManager.is_authority():
		reset_round()

	# Toggle mouse capture with Escape
	if event.is_action_pressed("ui_cancel"):
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		else:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
