extends Node3D
## GameWorld - Main game scene controller
##
## Initializes the game world, spawns players, manages waves.
## Supports group spawning (teams spawn together) and solo spawning.

# Node references
@onready var players_container: Node = $Players
@onready var zombies_container: Node = $Zombies
@onready var props_container: Node = $Props
@onready var spawn_points: Node = $SpawnPoints
@onready var wave_manager: WaveManager = $WaveManager
@onready var hud: Control = $HUD

# Spawn point system
# Group spawners: Named groups that spawn together (e.g., "alpha", "bravo")
# Solo spawners: Individual spawn points for solo players
var group_spawn_points: Dictionary = {}  # group_name -> Array[Vector3]
var solo_spawn_points: Array[Vector3] = []
var player_spawn_positions: Array[Vector3] = []  # Legacy fallback

# Track which group spawners are in use
var active_groups: Dictionary = {}  # group_name -> [peer_ids]


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
	group_spawn_points.clear()
	solo_spawn_points.clear()

	if spawn_points:
		for child in spawn_points.get_children():
			if child is Node3D:
				# Group spawn points: "GroupSpawn_Alpha_0", "GroupSpawn_Alpha_1", etc.
				if child.name.begins_with("GroupSpawn_"):
					var parts: PackedStringArray = child.name.split("_")
					if parts.size() >= 2:
						var group_name: String = parts[1].to_lower()
						if group_name not in group_spawn_points:
							group_spawn_points[group_name] = []
						group_spawn_points[group_name].append(child.global_position)
				# Solo spawn points: "SoloSpawn_0", "SoloSpawn_1", etc.
				elif child.name.begins_with("SoloSpawn"):
					solo_spawn_points.append(child.global_position)
				# Legacy: "PlayerSpawn0", "PlayerSpawn1", etc.
				elif child.name.begins_with("PlayerSpawn"):
					player_spawn_positions.append(child.global_position)

	# Default spawn points if none found
	if player_spawn_positions.is_empty() and solo_spawn_points.is_empty():
		solo_spawn_points = [
			Vector3(0, 1, 0),
			Vector3(2, 1, 0),
			Vector3(-2, 1, 0),
			Vector3(0, 1, 2),
		]
		player_spawn_positions = solo_spawn_points.duplicate()

	# If only legacy spawn points found, use them as solo spawns too
	if solo_spawn_points.is_empty() and not player_spawn_positions.is_empty():
		solo_spawn_points = player_spawn_positions.duplicate()

	# Create default group if no groups defined
	if group_spawn_points.is_empty():
		group_spawn_points["default"] = [
			Vector3(5, 1, 5),
			Vector3(7, 1, 5),
			Vector3(5, 1, 7),
			Vector3(7, 1, 7),
		]

	print("[GameWorld] Spawn points loaded - Groups: %s, Solo: %d" % [
		group_spawn_points.keys(),
		solo_spawn_points.size()
	])


func _on_player_joined(peer_id: int) -> void:
	if NetworkManager.is_authority():
		_spawn_player(peer_id)


func _on_player_left(peer_id: int) -> void:
	# Cleanup handled by GameState
	pass


func _spawn_player(peer_id: int) -> void:
	if not NetworkManager.is_authority():
		return

	# Get spawn position based on lobby assignment or default
	var spawn_pos := _get_spawn_position_for_player(peer_id)

	# Spawn via GameState
	var player := GameState.spawn_player(peer_id, spawn_pos)

	if player:
		# Give starting equipment
		_equip_player(player)


## Get spawn position based on group assignment or solo
func _get_spawn_position_for_player(peer_id: int) -> Vector3:
	# Check if player has a lobby assignment (sent via RPC or stored in registry)
	var spawn_info := _get_player_spawn_info(peer_id)
	var group_name: String = spawn_info.get("group", "")
	var spawn_index: int = spawn_info.get("index", 0)

	# Group spawning
	if group_name != "" and group_name != "solo":
		# Find an available group spawner
		var target_group := group_name.to_lower()

		# If specific group doesn't exist, try to find any available one
		if target_group not in group_spawn_points:
			target_group = _find_available_group()

		if target_group != "":
			var positions: Array = group_spawn_points.get(target_group, [])
			if positions.size() > 0:
				# Track this player in the group
				if target_group not in active_groups:
					active_groups[target_group] = []
				if peer_id not in active_groups[target_group]:
					active_groups[target_group].append(peer_id)

				var pos_idx := spawn_index % positions.size()
				print("[GameWorld] Player %d spawning in group '%s' at index %d" % [peer_id, target_group, pos_idx])
				return positions[pos_idx]

	# Solo spawning
	if solo_spawn_points.size() > 0:
		var solo_idx := spawn_index % solo_spawn_points.size()
		print("[GameWorld] Player %d spawning solo at index %d" % [peer_id, solo_idx])
		return solo_spawn_points[solo_idx]

	# Fallback to legacy
	var legacy_idx := (peer_id - 1) % player_spawn_positions.size()
	print("[GameWorld] Player %d spawning at legacy index %d" % [peer_id, legacy_idx])
	return player_spawn_positions[legacy_idx]


## Find an available group spawner
func _find_available_group() -> String:
	# Return the first group that's not at capacity
	for group_name in group_spawn_points:
		var positions: Array = group_spawn_points[group_name]
		var current_count: int = active_groups.get(group_name, []).size()
		if current_count < positions.size():
			return group_name

	# If all full, return first group (will wrap around)
	if not group_spawn_points.is_empty():
		return group_spawn_points.keys()[0]

	return ""


## Get spawn info for a player (from lobby assignment or server registry)
func _get_player_spawn_info(peer_id: int) -> Dictionary:
	# On server, check if we have lobby data for this player
	# This would be set when the lobby starts the game
	var session_data := HeadlessServer.get_session_data() if has_node("/root/HeadlessServer") else {}
	var lobby_players: Array = session_data.get("lobby_players", [])

	for player_info in lobby_players:
		if player_info.get("peer_id") == peer_id:
			return {
				"group": player_info.get("group", ""),
				"index": player_info.get("spawn_index", 0)
			}

	# Check if running as dedicated server with HeadlessServer autoload
	if HeadlessServer and HeadlessServer.has_method("get_player_spawn_info"):
		return HeadlessServer.get_player_spawn_info(peer_id)

	# Default: Return info based on peer_id order
	return {
		"group": "",
		"index": peer_id - 1
	}


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
