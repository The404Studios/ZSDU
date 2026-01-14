extends Node
## LobbySystem - Pre-game lobby and group management
##
## Handles:
## - Creating/joining lobbies
## - Group formation (leader + members)
## - Ready state management
## - Game start coordination
##
## NOTE: Spawn assignment is SERVER-AUTHORITATIVE.
## Client only stores what server tells it for UI display.
##
## Flow: Main Menu -> Lobby -> Game

signal lobby_created(lobby_id: String)
signal lobby_joined(lobby_data: Dictionary)
signal lobby_updated(lobby_data: Dictionary)
signal lobby_left()
signal player_joined_lobby(player_id: String, player_name: String)
signal player_left_lobby(player_id: String)
signal player_ready_changed(player_id: String, is_ready: bool)
signal game_starting(countdown: int)
signal game_started()
signal lobby_error(message: String)

# Lobby states
enum LobbyState {
	NONE,
	CREATING,
	IN_LOBBY,
	STARTING,
	IN_GAME
}

# Configuration
const LOBBY_UPDATE_INTERVAL := 2.0
const START_COUNTDOWN := 5

# Current state
var current_state: LobbyState = LobbyState.NONE
var current_lobby: Dictionary = {}
var is_leader := false
var local_player_ready := false

# Update timer
var _update_timer: Timer = null

# Spawn assignment (display only - server is authoritative)
# These are set when server confirms spawn, NOT by client
var assigned_spawn_group: String = ""
var assigned_spawn_index: int = 0


func _ready() -> void:
	_update_timer = Timer.new()
	_update_timer.wait_time = LOBBY_UPDATE_INTERVAL
	_update_timer.one_shot = false
	_update_timer.timeout.connect(_poll_lobby_updates)
	add_child(_update_timer)

	# Connect to network signals for error handling
	NetworkManager.connection_failed.connect(_on_connection_failed)
	NetworkManager.client_disconnected.connect(_on_disconnected)


# ============================================
# PUBLIC API - LOBBY MANAGEMENT
# ============================================

## Create a new lobby
func create_lobby(lobby_name: String, max_players: int = 4, game_mode: String = "survival") -> void:
	if current_state != LobbyState.NONE:
		lobby_error.emit("Already in a lobby")
		return

	current_state = LobbyState.CREATING

	var result = await _api_request("/lobby/create", {
		"playerId": FriendSystem.get_player_id(),
		"playerName": FriendSystem.local_player_name,
		"lobbyName": lobby_name,
		"maxPlayers": max_players,
		"gameMode": game_mode
	})

	if result.has("error"):
		current_state = LobbyState.NONE
		lobby_error.emit(result.error)
		return

	# API always returns { lobby: {...} }
	current_lobby = result.get("lobby", {})
	is_leader = true
	current_state = LobbyState.IN_LOBBY

	_update_timer.start()
	lobby_created.emit(current_lobby.get("id", ""))
	lobby_joined.emit(current_lobby)

	print("[Lobby] Created lobby: %s (code: %s)" % [current_lobby.get("name", ""), current_lobby.get("id", "")])


## Join an existing lobby by ID or code
func join_lobby(lobby_id: String) -> void:
	if current_state != LobbyState.NONE:
		lobby_error.emit("Already in a lobby")
		return

	var result = await _api_request("/lobby/join", {
		"playerId": FriendSystem.get_player_id(),
		"playerName": FriendSystem.local_player_name,
		"lobbyId": lobby_id
	})

	if result.has("error"):
		lobby_error.emit(result.error)
		return

	# API always returns { lobby: {...} }
	current_lobby = result.get("lobby", {})
	is_leader = current_lobby.get("leaderId") == FriendSystem.get_player_id()
	current_state = LobbyState.IN_LOBBY

	_update_timer.start()
	lobby_joined.emit(current_lobby)

	print("[Lobby] Joined lobby: %s (code: %s)" % [current_lobby.get("name", ""), current_lobby.get("id", "")])


## Leave current lobby
func leave_lobby() -> void:
	if current_state == LobbyState.NONE:
		return

	await _api_request("/lobby/leave", {
		"playerId": FriendSystem.get_player_id(),
		"lobbyId": current_lobby.get("id", "")
	})

	_cleanup_lobby()
	lobby_left.emit()


## Set ready state
func set_ready(ready: bool) -> void:
	if current_state != LobbyState.IN_LOBBY:
		return

	local_player_ready = ready

	await _api_request("/lobby/ready", {
		"playerId": FriendSystem.get_player_id(),
		"lobbyId": current_lobby.get("id", ""),
		"ready": ready
	})


## Start the game (leader only)
func start_game() -> void:
	if not is_leader:
		lobby_error.emit("Only the leader can start the game")
		return

	if current_state != LobbyState.IN_LOBBY:
		return

	# Check if all players are ready
	var players: Array = current_lobby.get("players", [])
	for player in players:
		if not player.get("ready", false):
			lobby_error.emit("Not all players are ready")
			return

	current_state = LobbyState.STARTING

	var result = await _api_request("/lobby/start", {
		"playerId": FriendSystem.get_player_id(),
		"lobbyId": current_lobby.get("id", "")
	})

	if result.has("error"):
		current_state = LobbyState.IN_LOBBY
		lobby_error.emit(result.error)
		return

	# Server info returned
	var default_host: String = BackendConfig.get_game_server_host() if BackendConfig else "127.0.0.1"
	var server_host: String = result.get("serverHost", default_host)
	var server_port: int = result.get("serverPort", 27015)

	# Start countdown
	_start_countdown(server_host, server_port)


## Quick play - Create solo lobby and auto-start
func quick_play(game_mode: String = "survival") -> void:
	await create_lobby("Quick Play", 1, game_mode)

	if current_state == LobbyState.IN_LOBBY:
		set_ready(true)
		await get_tree().create_timer(0.5).timeout
		start_game()


## Get list of public lobbies
func get_public_lobbies() -> Array:
	var result = await _api_request("/lobby/list", {}, "GET")

	if result.has("error"):
		return []

	return result.get("lobbies", [])


## Invite a friend to current lobby
func invite_friend(friend_id: String) -> void:
	if current_state != LobbyState.IN_LOBBY:
		return

	FriendSystem.invite_friend(friend_id)


# ============================================
# LOBBY POLLING
# ============================================

func _poll_lobby_updates() -> void:
	if current_state != LobbyState.IN_LOBBY:
		return

	var result = await _api_request("/lobby/status", {
		"lobbyId": current_lobby.get("id", "")
	})

	if result.has("error"):
		return

	# API always returns { lobby: {...} }
	var new_lobby: Dictionary = result.get("lobby", {})

	# Check for player changes
	var old_players: Array = current_lobby.get("players", [])
	var new_players: Array = new_lobby.get("players", [])

	# Detect joins
	for player in new_players:
		var found := false
		for old_player in old_players:
			if old_player.get("id") == player.get("id"):
				found = true
				# Check ready change
				if old_player.get("ready") != player.get("ready"):
					player_ready_changed.emit(player.get("id"), player.get("ready"))
				break
		if not found:
			player_joined_lobby.emit(player.get("id"), player.get("name"))

	# Detect leaves
	for old_player in old_players:
		var found := false
		for player in new_players:
			if player.get("id") == old_player.get("id"):
				found = true
				break
		if not found:
			player_left_lobby.emit(old_player.get("id"))

	# Check for game start
	if new_lobby.get("state") == "starting":
		var server_host: String = new_lobby.get("serverHost", BackendConfig.get_game_server_host())
		var server_port: int = new_lobby.get("serverPort", 27015)
		current_state = LobbyState.STARTING
		_start_countdown(server_host, server_port)

	current_lobby = new_lobby
	is_leader = current_lobby.get("leaderId") == FriendSystem.get_player_id()

	lobby_updated.emit(current_lobby)


# ============================================
# GAME START
# ============================================

func _start_countdown(server_host: String, server_port: int) -> void:
	_update_timer.stop()

	for i in range(START_COUNTDOWN, 0, -1):
		game_starting.emit(i)
		await get_tree().create_timer(1.0).timeout

	# NOTE: Spawn assignment is SERVER-AUTHORITATIVE
	# We store lobby info for UI display, but server decides actual spawn
	# The server will call set_spawn_assignment() when it confirms our spawn
	assigned_spawn_group = current_lobby.get("name", "")  # Group name for UI only
	assigned_spawn_index = -1  # Server will assign

	current_state = LobbyState.IN_GAME
	game_started.emit()

	# Connect to game server - server will validate our lobbyId and assign spawn
	print("[Lobby] Connecting to game server %s:%d (lobby: %s)" % [
		server_host, server_port, current_lobby.get("id", "")
	])
	NetworkManager.join_server(server_host, server_port)

	# Scene transition happens via NetworkManager.client_connected signal


# ============================================
# HELPERS
# ============================================

func _cleanup_lobby() -> void:
	_update_timer.stop()
	current_lobby = {}
	is_leader = false
	local_player_ready = false
	current_state = LobbyState.NONE
	assigned_spawn_group = ""
	assigned_spawn_index = 0


func _api_request(endpoint: String, data: Dictionary, method: String = "POST") -> Dictionary:
	# Create fresh HTTPRequest per call to avoid concurrency issues
	var http := HTTPRequest.new()
	http.timeout = 10.0
	add_child(http)

	var url := BackendConfig.get_http_url() + endpoint
	var headers := ["Content-Type: application/json"]
	var body := JSON.stringify(data) if not data.is_empty() else ""
	var http_method := HTTPClient.METHOD_POST if method == "POST" else HTTPClient.METHOD_GET

	var error := http.request(url, headers, http_method, body)
	if error != OK:
		http.queue_free()
		return {"error": "Request failed (%s)" % error_string(error)}

	var result = await http.request_completed
	http.queue_free()

	if result[0] != HTTPRequest.RESULT_SUCCESS:
		return {"error": "HTTP error (%d)" % result[0]}

	if result[1] < 200 or result[1] >= 300:
		return {"error": "HTTP %d" % result[1]}

	var json := JSON.new()
	if json.parse(result[3].get_string_from_utf8()) != OK:
		return {"error": "Invalid JSON response"}

	return json.data if json.data is Dictionary else {"data": json.data}


# ============================================
# STATE GETTERS
# ============================================

func get_lobby_state() -> LobbyState:
	return current_state


func get_current_lobby() -> Dictionary:
	return current_lobby


func is_in_lobby() -> bool:
	return current_state == LobbyState.IN_LOBBY


func is_lobby_leader() -> bool:
	return is_leader


func get_lobby_players() -> Array:
	return current_lobby.get("players", [])


func get_lobby_name() -> String:
	return current_lobby.get("name", "")


func get_spawn_assignment() -> Dictionary:
	return {
		"group": assigned_spawn_group,
		"index": assigned_spawn_index
	}


## Called by server (via RPC) when it assigns our spawn
## Client only stores this for UI display - server is authoritative
func set_spawn_assignment(group: String, index: int) -> void:
	assigned_spawn_group = group
	assigned_spawn_index = index
	print("[Lobby] Server assigned spawn: group=%s, index=%d" % [group, index])


## Get current lobby ID (for sending to server on connect)
func get_lobby_id() -> String:
	return current_lobby.get("id", "")


# ============================================
# CONNECTION ERROR HANDLING
# ============================================

func _on_connection_failed() -> void:
	if current_state == LobbyState.IN_GAME or current_state == LobbyState.STARTING:
		print("[Lobby] Connection to game server failed!")
		lobby_error.emit("Failed to connect to game server")

		# Return to lobby state so player can try again
		current_state = LobbyState.IN_LOBBY
		_update_timer.start()


func _on_disconnected() -> void:
	if current_state == LobbyState.IN_GAME:
		print("[Lobby] Disconnected from game server")
		lobby_error.emit("Disconnected from game server")

		# Cleanup lobby state
		_cleanup_lobby()
