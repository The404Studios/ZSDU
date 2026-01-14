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

	# NOTE: We do NOT register/spawn here anymore!
	# Registration happens when client sends _request_registration RPC
	# This ensures proper spawn claiming from backend happens first
	# The full snapshot is sent AFTER registration completes

	if is_authority():
		# Track connection for player count
		if peer_id not in connected_peers:
			connected_peers.append(peer_id)
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

	# Get player identity and lobby info
	var player_id: String = ""
	var player_name: String = "Player_%d" % local_peer_id
	var lobby_id: String = ""

	if FriendSystem:
		player_id = FriendSystem.get_player_id()
		if FriendSystem.local_player_name != "":
			player_name = FriendSystem.local_player_name

	if LobbySystem:
		lobby_id = LobbySystem.get_lobby_id()

	# Request registration with dictionary payload (future-proof)
	# Server is 100% authoritative for spawn assignment - client sends NO spawn info
	_request_registration.rpc_id(1, {
		"player_id": player_id,
		"player_name": player_name,
		"lobby_id": lobby_id
	})


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
	# Check if we're the server, handling case where no peer exists
	if is_server:
		return true
	# Only call multiplayer.is_server() if a peer is assigned
	if multiplayer.multiplayer_peer != null and multiplayer.multiplayer_peer.get_connection_status() != MultiplayerPeer.CONNECTION_DISCONNECTED:
		return multiplayer.is_server()
	return false


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

	# Prevent duplicate registration/spawn
	var is_new := peer_id not in player_data

	if username.is_empty():
		username = "Player_%d" % peer_id

	var info := PlayerInfo.new(peer_id, username)
	player_data[peer_id] = info

	if peer_id not in connected_peers:
		connected_peers.append(peer_id)

	print("[Server] Registered player: %s (ID: %d, new=%s)" % [username, peer_id, is_new])

	# Only emit player_joined for new players (triggers spawn)
	if is_new:
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
		if not nail.get("active", false):
			continue

		result.append({
			"id": nail_id,
			"prop_id": nail.get("prop_id", -1),
			"surface_id": nail.get("surface_id", -1),
			"position": nail.get("position", Vector3.ZERO),
			"normal": nail.get("normal", Vector3.UP),
			"hp": nail.get("hp", 0.0),
			"max_hp": nail.get("max_hp", 100.0),
			"repair_count": nail.get("repair_count", 0),
			"owner_id": nail.get("owner_id", -1),
		})

	return result


# ============================================
# RPCs
# ============================================

## Client registration RPC - uses dictionary payload for future-proofing
## Server is 100% authoritative for spawn assignment
@rpc("any_peer", "reliable")
func _request_registration(client_info: Dictionary) -> void:
	if not is_authority():
		return

	var sender_id := multiplayer.get_remote_sender_id()

	# Extract client-provided info (identity only, NO spawn data accepted)
	var player_id: String = client_info.get("player_id", "")
	var player_name: String = client_info.get("player_name", "Player_%d" % sender_id)
	var lobby_id: String = client_info.get("lobby_id", "")

	# Register player for spawn lookup
	# Server will claim spawn from backend - client has NO say in spawn position
	if HeadlessServer and HeadlessServer.is_headless:
		HeadlessServer.player_spawn_registry[sender_id] = {
			"player_id": player_id,
			"lobby_id": lobby_id,
			"group": "",   # Server-authoritative: set by backend only
			"index": -1    # Server-authoritative: set by backend only
		}
		print("[Server] Registered player peer %d: player=%s, lobby=%s" % [
			sender_id, player_id, lobby_id
		])

		# Claim spawn from backend (server-authoritative)
		# IMPORTANT: Wait for spawn claim before registering player
		if lobby_id != "" and player_id != "":
			await _claim_spawn_async(sender_id, player_id, lobby_id)

	_register_player(sender_id, player_name)
	_confirm_registration.rpc_id(sender_id, sender_id, player_name)

	# Send full world snapshot AFTER registration (player is now spawned)
	# This ensures the new player sees all existing entities including themselves
	_send_full_world_snapshot.rpc_id(sender_id, _serialize_full_world_state())


## Claim spawn assignment from backend (server-only)
func _claim_spawn_async(peer_id: int, player_id: String, lobby_id: String) -> void:
	if not HeadlessServer or not HeadlessServer.is_headless:
		return

	# Create HTTP request to backend
	var http := HTTPRequest.new()
	http.timeout = 5.0
	add_child(http)

	var url := BackendConfig.get_http_url() + "/lobby/claim_spawn"
	var body := JSON.stringify({
		"lobbyId": lobby_id,
		"playerId": player_id
	})
	var headers := ["Content-Type: application/json"]

	var error := http.request(url, headers, HTTPClient.METHOD_POST, body)
	if error != OK:
		http.queue_free()
		push_warning("[Server] Failed to claim spawn for %s" % player_id)
		return

	var result = await http.request_completed
	http.queue_free()

	if result[0] != HTTPRequest.RESULT_SUCCESS or result[1] < 200 or result[1] >= 300:
		push_warning("[Server] Claim spawn HTTP error for %s" % player_id)
		return

	var json := JSON.new()
	if json.parse(result[3].get_string_from_utf8()) != OK:
		return

	var data: Dictionary = json.data if json.data is Dictionary else {}

	# Update spawn registry with server-authoritative data
	if peer_id in HeadlessServer.player_spawn_registry:
		HeadlessServer.player_spawn_registry[peer_id]["group"] = data.get("groupName", "")
		HeadlessServer.player_spawn_registry[peer_id]["index"] = data.get("spawnIndex", 0)
		print("[Server] Claimed spawn for peer %d: group=%s, index=%d" % [
			peer_id,
			data.get("groupName", ""),
			data.get("spawnIndex", 0)
		])


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
