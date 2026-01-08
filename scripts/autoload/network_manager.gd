extends Node
## NetworkManager - Server-authoritative ENet multiplayer with traversal support
##
## Connection flow:
## 1. DISCONNECTED - No connection
## 2. DISCOVERING  - Talking to traversal server
## 3. CONNECTING   - Establishing ENet connection
## 4. SYNCING      - Receiving world snapshot
## 5. PLAYING      - Normal gameplay
##
## Server owns: World, Zombies, Spawners, Barricade validation
## Clients own: ONLY their input

# Signals
signal server_started
signal server_stopped
signal client_connected
signal client_disconnected
signal connection_failed
signal player_joined(peer_id: int)
signal player_left(peer_id: int)
signal world_sync_complete
signal connection_state_changed(state: ConnectionState)

enum ConnectionState {
	DISCONNECTED,
	DISCOVERING,
	CONNECTING,
	SYNCING,
	PLAYING
}

# Constants
const DEFAULT_PORT := 27015
const MAX_PLAYERS := 32
const TICK_RATE := 60
const SYNC_TIMEOUT := 10.0

# Connection state
var current_state: ConnectionState = ConnectionState.DISCONNECTED
var session_id: String = ""

# Network state
var peer: ENetMultiplayerPeer = null
var is_server := false
var is_client := false
var local_peer_id := 0
var connected_peers: Array[int] = []

# Server-side player registry
var player_data: Dictionary = {}  # peer_id -> PlayerInfo

# Sync state
var sync_timer := 0.0
var awaiting_sync := false

class PlayerInfo:
	var peer_id: int
	var username: String
	var team: int  # 0 = human, 1 = zombie
	var spawn_position: Vector3
	var is_ready: bool = false
	var join_time: float = 0.0

	func _init(id: int, name: String = "Player"):
		peer_id = id
		username = name
		team = 0
		spawn_position = Vector3.ZERO
		join_time = Time.get_unix_time_from_system()


func _ready() -> void:
	# Connect to multiplayer signals
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)

	# Connect to traversal signals
	TraversalClient.session_created.connect(_on_traversal_session_created)
	TraversalClient.session_joined.connect(_on_traversal_session_joined)
	TraversalClient.traversal_error.connect(_on_traversal_error)


func _process(delta: float) -> void:
	if peer and peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED:
		peer.poll()

	# Handle sync timeout
	if awaiting_sync:
		sync_timer += delta
		if sync_timer > SYNC_TIMEOUT:
			push_error("[Network] Sync timeout")
			awaiting_sync = false
			_set_state(ConnectionState.PLAYING)  # Proceed anyway


func _set_state(new_state: ConnectionState) -> void:
	if current_state != new_state:
		var old_state := current_state
		current_state = new_state
		print("[Network] State: %s -> %s" % [_state_name(old_state), _state_name(new_state)])
		connection_state_changed.emit(new_state)


func _state_name(state: ConnectionState) -> String:
	match state:
		ConnectionState.DISCONNECTED: return "DISCONNECTED"
		ConnectionState.DISCOVERING: return "DISCOVERING"
		ConnectionState.CONNECTING: return "CONNECTING"
		ConnectionState.SYNCING: return "SYNCING"
		ConnectionState.PLAYING: return "PLAYING"
	return "UNKNOWN"


# ============================================
# PUBLIC API - HOST
# ============================================

## Host a game with traversal registration
func host_game(session_name: String, port: int = DEFAULT_PORT, max_clients: int = MAX_PLAYERS, use_traversal: bool = true) -> Error:
	# Start local server first
	var error := _start_enet_server(port, max_clients)
	if error != OK:
		return error

	# Generate session ID
	session_id = TraversalClient.generate_session_id()

	if use_traversal:
		_set_state(ConnectionState.DISCOVERING)
		TraversalClient.register_host(session_name, port, max_clients)
	else:
		# LAN-only mode
		_set_state(ConnectionState.PLAYING)
		print("[Network] LAN-only mode, session: %s" % session_id)

	return OK


## Host a server (legacy/direct)
func host_server(port: int = DEFAULT_PORT, max_clients: int = MAX_PLAYERS) -> Error:
	return host_game("Game_%d" % randi(), port, max_clients, false)


## Start ENet server (internal)
func _start_enet_server(port: int, max_clients: int) -> Error:
	peer = ENetMultiplayerPeer.new()
	var error := peer.create_server(port, max_clients)

	if error != OK:
		push_error("Failed to create server: %s" % error_string(error))
		return error

	multiplayer.multiplayer_peer = peer
	is_server = true
	is_client = false
	local_peer_id = 1

	print("[Server] Started on port %d" % port)
	server_started.emit()

	# Only register host as player in listen server mode (not dedicated/headless)
	if not _is_dedicated_server():
		_register_player(1, "Host")

	return OK


## Check if running as dedicated server (headless mode)
func _is_dedicated_server() -> bool:
	# Check command line args
	var args := OS.get_cmdline_args()
	for arg in args:
		if arg == "--headless" or arg == "--server":
			return true
	# Check display server
	return DisplayServer.get_name() == "headless"


# ============================================
# PUBLIC API - JOIN
# ============================================

## Join via traversal (session browser)
func join_via_traversal(target_session_id: String) -> void:
	_set_state(ConnectionState.DISCOVERING)
	TraversalClient.join_session(target_session_id)


## Join directly (LAN/known IP)
func join_server(address: String, port: int = DEFAULT_PORT) -> Error:
	_set_state(ConnectionState.CONNECTING)
	return _connect_enet(address, port)


## Connect ENet to host (internal)
func _connect_enet(address: String, port: int) -> Error:
	peer = ENetMultiplayerPeer.new()
	var error := peer.create_client(address, port)

	if error != OK:
		push_error("Failed to create client: %s" % error_string(error))
		_set_state(ConnectionState.DISCONNECTED)
		return error

	multiplayer.multiplayer_peer = peer
	is_server = false
	is_client = true

	print("[Client] Connecting to %s:%d" % [address, port])
	return OK


# ============================================
# PUBLIC API - DISCONNECT
# ============================================

## Disconnect and cleanup everything
func disconnect_from_network() -> void:
	# Unregister from traversal
	TraversalClient.disconnect_traversal()

	# Close ENet
	if peer:
		peer.close()
		peer = null

	multiplayer.multiplayer_peer = null
	is_server = false
	is_client = false
	local_peer_id = 0
	connected_peers.clear()
	player_data.clear()
	session_id = ""
	awaiting_sync = false

	_set_state(ConnectionState.DISCONNECTED)
	print("[Network] Disconnected")


# ============================================
# TRAVERSAL CALLBACKS
# ============================================

func _on_traversal_session_created(new_session_id: String) -> void:
	session_id = new_session_id
	_set_state(ConnectionState.PLAYING)
	print("[Network] Session registered: %s" % session_id)


func _on_traversal_session_joined(host_ip: String, host_port: int) -> void:
	print("[Network] Got join info: %s:%d" % [host_ip, host_port])
	_connect_enet(host_ip, host_port)


func _on_traversal_error(message: String) -> void:
	push_error("[Network] Traversal error: %s" % message)
	if current_state == ConnectionState.DISCOVERING:
		# Fall back to disconnected
		_set_state(ConnectionState.DISCONNECTED)
		connection_failed.emit()


# ============================================
# MULTIPLAYER CALLBACKS
# ============================================

func _on_peer_connected(peer_id: int) -> void:
	print("[Network] Peer connected: %d" % peer_id)

	if is_authority():
		_register_player(peer_id)
		# Send FULL world snapshot for join-in-progress
		_send_full_world_snapshot.rpc_id(peer_id, _serialize_full_world_state())

		# Update traversal player count
		TraversalClient.update_player_count(connected_peers.size())


func _on_peer_disconnected(peer_id: int) -> void:
	print("[Network] Peer disconnected: %d" % peer_id)

	if is_authority():
		_unregister_player(peer_id)
		TraversalClient.update_player_count(connected_peers.size())

	GameState.on_player_disconnected(peer_id)


func _on_connected_to_server() -> void:
	local_peer_id = multiplayer.get_unique_id()
	print("[Client] Connected to server. Local ID: %d" % local_peer_id)

	_set_state(ConnectionState.SYNCING)
	awaiting_sync = true
	sync_timer = 0.0

	# Get player info from FriendSystem (for identification) and LobbySystem (for spawn)
	var player_id: String = ""
	var player_name: String = "Player_%d" % local_peer_id
	var spawn_group: String = ""
	var spawn_index: int = 0

	if FriendSystem:
		player_id = FriendSystem.get_player_id()
		if FriendSystem.local_player_name != "":
			player_name = FriendSystem.local_player_name

	if LobbySystem:
		var spawn_info := LobbySystem.get_spawn_assignment()
		spawn_group = spawn_info.get("group", "")
		spawn_index = spawn_info.get("index", 0)

	# Request registration with full player info
	_request_registration.rpc_id(1, player_name, player_id, spawn_group, spawn_index)


func _on_connection_failed() -> void:
	print("[Client] Connection failed")
	disconnect_from_network()
	connection_failed.emit()


func _on_server_disconnected() -> void:
	print("[Client] Server disconnected")
	disconnect_from_network()
	client_disconnected.emit()


# ============================================
# STATE HELPERS
# ============================================

func is_authority() -> bool:
	return is_server or multiplayer.is_server()


func get_peer_ids() -> Array[int]:
	return connected_peers.duplicate()


func get_session_id() -> String:
	return session_id


func get_connection_state() -> ConnectionState:
	return current_state


## Returns true if running as dedicated server (headless mode)
func is_dedicated_server() -> bool:
	return _is_dedicated_server()


# ============================================
# PLAYER REGISTRATION
# ============================================

func _register_player(peer_id: int, username: String = "") -> void:
	if not is_authority():
		return

	if username.is_empty():
		username = "Player_%d" % peer_id

	var info := PlayerInfo.new(peer_id, username)
	player_data[peer_id] = info

	if peer_id not in connected_peers:
		connected_peers.append(peer_id)

	print("[Server] Registered player: %s (ID: %d)" % [username, peer_id])
	player_joined.emit(peer_id)


func _unregister_player(peer_id: int) -> void:
	if not is_authority():
		return

	if peer_id in player_data:
		var info: PlayerInfo = player_data[peer_id]
		print("[Server] Player left: %s (ID: %d)" % [info.username, peer_id])
		player_data.erase(peer_id)

	connected_peers.erase(peer_id)
	player_left.emit(peer_id)


# ============================================
# WORLD SNAPSHOT (JOIN-IN-PROGRESS)
# ============================================

## Serialize FULL world state for late joiners
func _serialize_full_world_state() -> Dictionary:
	return {
		"session_id": session_id,
		"wave": GameState.current_wave,
		"phase": GameState.current_phase,
		"players": _serialize_players(),
		"zombies": _serialize_zombies(),
		"props": _serialize_props(),
		"nails": _serialize_nails(),
	}


func _serialize_players() -> Array:
	var result := []
	for peer_id in player_data:
		var info: PlayerInfo = player_data[peer_id]
		var player_node: Node3D = GameState.players.get(peer_id)

		var player_state := {
			"id": info.peer_id,
			"username": info.username,
			"team": info.team,
		}

		if player_node and is_instance_valid(player_node):
			player_state["position"] = player_node.global_position
			player_state["health"] = player_node.get("health")
			player_state["is_dead"] = player_node.get("is_dead")

		result.append(player_state)

	return result


func _serialize_zombies() -> Array:
	var result := []
	for zombie_id in GameState.zombies:
		var zombie: Node3D = GameState.zombies[zombie_id]
		if not is_instance_valid(zombie):
			continue

		result.append({
			"id": zombie_id,
			"position": zombie.global_position,
			"rotation": zombie.rotation.y,
			"health": zombie.get("health"),
			"state": zombie.get("current_state"),
			"type": zombie.get("zombie_type"),
		})

	return result


func _serialize_props() -> Array:
	var result := []
	for prop_id in GameState.props:
		var prop: RigidBody3D = GameState.props[prop_id]
		if not is_instance_valid(prop):
			continue

		result.append({
			"id": prop_id,
			"position": prop.global_position,
			"rotation": prop.rotation,
			"sleeping": prop.sleeping,
			"linear_velocity": prop.linear_velocity,
			"angular_velocity": prop.angular_velocity,
		})

	return result


func _serialize_nails() -> Array:
	var result := []
	for nail_id in GameState.nails:
		var nail: Dictionary = GameState.nails[nail_id]
		if not nail.active:
			continue

		result.append({
			"id": nail_id,
			"prop_id": nail.prop_id,
			"surface_id": nail.surface_id,
			"position": nail.position,
			"normal": nail.normal,
			"hp": nail.hp,
			"max_hp": nail.max_hp,
			"repair_count": nail.repair_count,
			"owner_id": nail.owner_id,
		})

	return result


# ============================================
# RPCs
# ============================================

@rpc("any_peer", "reliable")
func _request_registration(username: String, player_id: String = "", spawn_group: String = "", spawn_index: int = 0) -> void:
	if not is_authority():
		return

	var sender_id := multiplayer.get_remote_sender_id()

	# Register player spawn info with HeadlessServer (for group spawning)
	if HeadlessServer and HeadlessServer.is_headless:
		if player_id != "":
			# Map player_id to peer_id for spawn lookup
			HeadlessServer.player_spawn_registry[sender_id] = {
				"group": spawn_group,
				"index": spawn_index
			}
			print("[Server] Registered spawn for peer %d: player=%s, group=%s, index=%d" % [
				sender_id, player_id, spawn_group, spawn_index
			])

	_register_player(sender_id, username)
	_confirm_registration.rpc_id(sender_id, sender_id, username)


@rpc("authority", "reliable")
func _confirm_registration(peer_id: int, username: String) -> void:
	local_peer_id = peer_id
	print("[Client] Registration confirmed: %s (ID: %d)" % [username, peer_id])


## Send full world snapshot to joining client
@rpc("authority", "reliable")
func _send_full_world_snapshot(state: Dictionary) -> void:
	print("[Client] Received full world snapshot")
	awaiting_sync = false

	# Apply full state
	GameState.apply_full_snapshot(state)

	_set_state(ConnectionState.PLAYING)
	client_connected.emit()
	world_sync_complete.emit()


## Legacy sync (kept for compatibility)
@rpc("authority", "reliable")
func _sync_state_to_peer(state: Dictionary) -> void:
	print("[Client] Received game state sync")
	GameState.apply_state(state)


@rpc("any_peer", "unreliable_ordered")
func send_player_input(input_data: Dictionary) -> void:
	if not is_authority():
		return

	var sender_id := multiplayer.get_remote_sender_id()
	GameState.process_player_input(sender_id, input_data)


@rpc("authority", "unreliable_ordered")
func broadcast_state_update(state: Dictionary) -> void:
	GameState.apply_snapshot(state)


@rpc("authority", "reliable")
func broadcast_event(event_type: String, event_data: Dictionary) -> void:
	GameState.handle_event(event_type, event_data)


@rpc("any_peer", "reliable")
func request_action(action_type: String, action_data: Dictionary) -> void:
	if not is_authority():
		return

	var sender_id := multiplayer.get_remote_sender_id()
	GameState.process_action_request(sender_id, action_type, action_data)
