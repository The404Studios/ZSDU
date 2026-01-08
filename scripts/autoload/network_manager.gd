extends Node
## NetworkManager - Server-authoritative ENet multiplayer
##
## This is the spine of the multiplayer system.
## Server owns: World, Zombies, Spawners, Barricade validation
## Clients own: ONLY their input
## Everything else is replicated from server.

# Signals
signal server_started
signal server_stopped
signal client_connected
signal client_disconnected
signal connection_failed
signal player_joined(peer_id: int)
signal player_left(peer_id: int)

# Constants
const DEFAULT_PORT := 27015
const MAX_PLAYERS := 32
const TICK_RATE := 60  # Physics ticks per second

# Network state
var peer: ENetMultiplayerPeer = null
var is_server := false
var is_client := false
var local_peer_id := 0
var connected_peers: Array[int] = []

# Server-side player registry
var player_data: Dictionary = {}  # peer_id -> PlayerInfo

class PlayerInfo:
	var peer_id: int
	var username: str
	var team: int  # 0 = human, 1 = zombie
	var spawn_position: Vector3
	var is_ready: bool = false

	func _init(id: int, name: str = "Player"):
		peer_id = id
		username = name
		team = 0
		spawn_position = Vector3.ZERO


func _ready() -> void:
	# Connect to multiplayer signals
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)


func _process(_delta: float) -> void:
	if peer and peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED:
		peer.poll()


## Host a server
func host_server(port: int = DEFAULT_PORT, max_clients: int = MAX_PLAYERS) -> Error:
	peer = ENetMultiplayerPeer.new()
	var error := peer.create_server(port, max_clients)

	if error != OK:
		push_error("Failed to create server: %s" % error_string(error))
		return error

	multiplayer.multiplayer_peer = peer
	is_server = true
	is_client = false
	local_peer_id = 1  # Server is always peer 1

	print("[Server] Started on port %d" % port)
	server_started.emit()

	# Server counts as a player too (listen server)
	_register_player(1, "Host")

	return OK


## Connect to a server
func join_server(address: str, port: int = DEFAULT_PORT) -> Error:
	peer = ENetMultiplayerPeer.new()
	var error := peer.create_client(address, port)

	if error != OK:
		push_error("Failed to create client: %s" % error_string(error))
		return error

	multiplayer.multiplayer_peer = peer
	is_server = false
	is_client = true

	print("[Client] Connecting to %s:%d" % [address, port])
	return OK


## Disconnect and cleanup
func disconnect_from_network() -> void:
	if peer:
		peer.close()
		peer = null

	multiplayer.multiplayer_peer = null
	is_server = false
	is_client = false
	local_peer_id = 0
	connected_peers.clear()
	player_data.clear()

	print("[Network] Disconnected")


## Check if we are the network authority (server)
func is_authority() -> bool:
	return is_server or multiplayer.is_server()


## Get all connected peer IDs
func get_peer_ids() -> Array[int]:
	return connected_peers.duplicate()


## Register a new player (server-side)
func _register_player(peer_id: int, username: str = "") -> void:
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


## Unregister a player (server-side)
func _unregister_player(peer_id: int) -> void:
	if not is_authority():
		return

	if peer_id in player_data:
		var info: PlayerInfo = player_data[peer_id]
		print("[Server] Player left: %s (ID: %d)" % [info.username, peer_id])
		player_data.erase(peer_id)

	connected_peers.erase(peer_id)
	player_left.emit(peer_id)


# Multiplayer callbacks
func _on_peer_connected(peer_id: int) -> void:
	print("[Network] Peer connected: %d" % peer_id)

	if is_authority():
		_register_player(peer_id)
		# Sync existing game state to new player
		_sync_state_to_peer.rpc_id(peer_id, _serialize_game_state())


func _on_peer_disconnected(peer_id: int) -> void:
	print("[Network] Peer disconnected: %d" % peer_id)

	if is_authority():
		_unregister_player(peer_id)

	# Notify game state
	GameState.on_player_disconnected(peer_id)


func _on_connected_to_server() -> void:
	local_peer_id = multiplayer.get_unique_id()
	print("[Client] Connected to server. Local ID: %d" % local_peer_id)
	client_connected.emit()

	# Request to register
	_request_registration.rpc_id(1, "Player_%d" % local_peer_id)


func _on_connection_failed() -> void:
	print("[Client] Connection failed")
	disconnect_from_network()
	connection_failed.emit()


func _on_server_disconnected() -> void:
	print("[Client] Server disconnected")
	disconnect_from_network()
	client_disconnected.emit()


## Client requests registration on server
@rpc("any_peer", "reliable")
func _request_registration(username: str) -> void:
	if not is_authority():
		return

	var sender_id := multiplayer.get_remote_sender_id()
	_register_player(sender_id, username)

	# Confirm registration back to client
	_confirm_registration.rpc_id(sender_id, sender_id, username)


## Server confirms registration to client
@rpc("authority", "reliable")
func _confirm_registration(peer_id: int, username: str) -> void:
	local_peer_id = peer_id
	print("[Client] Registration confirmed: %s (ID: %d)" % [username, peer_id])


## Serialize current game state for late joiners
func _serialize_game_state() -> Dictionary:
	return {
		"wave": GameState.current_wave,
		"phase": GameState.current_phase,
		"players": _serialize_players(),
	}


func _serialize_players() -> Array:
	var result := []
	for peer_id in player_data:
		var info: PlayerInfo = player_data[peer_id]
		result.append({
			"id": info.peer_id,
			"username": info.username,
			"team": info.team,
		})
	return result


## Sync game state to a newly connected peer
@rpc("authority", "reliable")
func _sync_state_to_peer(state: Dictionary) -> void:
	print("[Client] Received game state sync")
	GameState.apply_state(state)


## Send input to server (client -> server)
@rpc("any_peer", "unreliable_ordered")
func send_player_input(input_data: Dictionary) -> void:
	if not is_authority():
		return

	var sender_id := multiplayer.get_remote_sender_id()
	GameState.process_player_input(sender_id, input_data)


## Broadcast state update to all clients (server -> clients)
@rpc("authority", "unreliable_ordered")
func broadcast_state_update(state: Dictionary) -> void:
	# Clients receive and apply state
	GameState.apply_snapshot(state)


## Broadcast reliable event to all clients
@rpc("authority", "reliable")
func broadcast_event(event_type: String, event_data: Dictionary) -> void:
	GameState.handle_event(event_type, event_data)


## Request action from server (client -> server)
@rpc("any_peer", "reliable")
func request_action(action_type: String, action_data: Dictionary) -> void:
	if not is_authority():
		return

	var sender_id := multiplayer.get_remote_sender_id()
	GameState.process_action_request(sender_id, action_type, action_data)
