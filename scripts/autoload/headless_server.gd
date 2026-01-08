extends Node
## HeadlessServer - Dedicated server backend integration
##
## Handles:
## - Command line / environment config parsing
## - HTTP registration with backend (/servers/ready)
## - Timer-based heartbeat (/servers/heartbeat every 2s)
## - Auto-shutdown when empty for N seconds
## - Game event reporting (player join/leave, wave complete, match end)
##
## Only active when running with --headless or --server flag.
##
## Launch args example:
##   godot_server.exe --headless --port=27015 --backend=http://127.0.0.1:8080

signal server_registered(server_id: String)
signal registration_failed(error: String)
signal heartbeat_failed(error: String)
signal shutting_down(reason: String)

# ============================================
# CONFIGURATION (from cmdline or environment)
# ============================================
var game_port: int = 27015
var backend_url: String = "http://162.248.94.149:8080"  # Production server
var session_id: String = ""
var is_headless: bool = false

# ============================================
# STATE
# ============================================
var server_id: String = ""
var is_registered: bool = false
var player_count: int = 0
var last_player_left_time: float = -1.0
var ready_retry_count: int = 0

# Match tracking (for game event reporting)
var current_match_id: String = ""

# Session/Lobby data (for group spawning)
var session_data: Dictionary = {}
# lobby_players: Array of { "player_id": String, "peer_id": int, "group": String, "spawn_index": int }
var player_spawn_registry: Dictionary = {}  # peer_id -> { "group": String, "index": int }

# Timers
var _heartbeat_timer: Timer = null
var _ready_retry_timer: Timer = null

# HTTP for ready (with callback)
var _ready_http: HTTPRequest = null


func _ready() -> void:
	# Check if running headless
	is_headless = _check_headless_mode()

	if not is_headless:
		print("[HeadlessServer] Not running in headless mode, disabled")
		set_process(false)
		return

	# Parse configuration
	_parse_config()

	# Validate required config
	if game_port == 0:
		push_error("[HeadlessServer] No port specified (use --port= or GAME_PORT)")
		get_tree().quit(1)
		return

	# Create HTTP request for ready/retry
	_ready_http = HTTPRequest.new()
	_ready_http.timeout = 10.0
	_ready_http.request_completed.connect(_on_ready_response)
	add_child(_ready_http)

	# Create heartbeat timer
	_heartbeat_timer = Timer.new()
	_heartbeat_timer.wait_time = ServerConstants.HEARTBEAT_INTERVAL_SEC
	_heartbeat_timer.one_shot = false
	_heartbeat_timer.timeout.connect(_send_heartbeat)
	add_child(_heartbeat_timer)

	# Create ready retry timer
	_ready_retry_timer = Timer.new()
	_ready_retry_timer.wait_time = ServerConstants.READY_RETRY_INTERVAL_SEC
	_ready_retry_timer.one_shot = true
	_ready_retry_timer.timeout.connect(_send_ready)
	add_child(_ready_retry_timer)

	# Connect to NetworkManager signals
	if NetworkManager:
		NetworkManager.player_joined.connect(_on_player_joined)
		NetworkManager.player_left.connect(_on_player_left)
		NetworkManager.server_started.connect(_on_server_started)

	# Connect to GameState signals for wave events
	if GameState:
		GameState.wave_started.connect(_on_wave_started)
		GameState.wave_ended.connect(_on_wave_ended)

	print("[HeadlessServer] ========================================")
	print("[HeadlessServer]  ZSDU Dedicated Server Starting")
	print("[HeadlessServer] ========================================")
	print("[HeadlessServer] Game Port: %d" % game_port)
	print("[HeadlessServer] Backend: %s" % backend_url)
	print("[HeadlessServer] Session: %s" % (session_id if session_id != "" else "(auto)"))
	print("[HeadlessServer] Heartbeat: %0.1fs interval" % ServerConstants.HEARTBEAT_INTERVAL_SEC)
	print("[HeadlessServer] Empty shutdown: %0.0fs" % ServerConstants.EMPTY_SHUTDOWN_DELAY_SEC)

	# Start the ENet server
	_start_game_server()


func _process(_delta: float) -> void:
	if not is_headless or not is_registered:
		return

	# Empty server shutdown check
	if multiplayer.get_peers().is_empty():
		if last_player_left_time < 0:
			last_player_left_time = Time.get_unix_time_from_system()
			print("[HeadlessServer] Server empty, will shutdown in %0.0fs if no players" % ServerConstants.EMPTY_SHUTDOWN_DELAY_SEC)
	else:
		last_player_left_time = -1.0

	if last_player_left_time > 0:
		var elapsed := Time.get_unix_time_from_system() - last_player_left_time
		if elapsed >= ServerConstants.EMPTY_SHUTDOWN_DELAY_SEC:
			_shutdown("No players for %0.0f seconds" % ServerConstants.EMPTY_SHUTDOWN_DELAY_SEC)


func _check_headless_mode() -> bool:
	var args := OS.get_cmdline_args()
	for arg in args:
		if arg == "--headless" or arg == "--server":
			return true
	return DisplayServer.get_name() == "headless"


func _parse_config() -> void:
	# Parse command line args first (highest priority)
	var args := OS.get_cmdline_args()
	for arg in args:
		if arg.begins_with("--port="):
			game_port = int(arg.split("=")[1])
		elif arg.begins_with("--backend="):
			backend_url = arg.split("=")[1]
		elif arg.begins_with("--session_id="):
			session_id = arg.split("=")[1]

	# Fall back to environment variables
	var env_port := OS.get_environment("GAME_PORT")
	if env_port != "" and game_port == 27015:  # Only use env if cmdline didn't set
		game_port = int(env_port)

	var env_host := OS.get_environment("BACKEND_HOST")
	var env_backend_port := OS.get_environment("BACKEND_PORT")
	if env_host != "" and backend_url == "http://127.0.0.1:8080":
		var port_str := env_backend_port if env_backend_port != "" else "8080"
		backend_url = "http://%s:%s" % [env_host, port_str]


func _start_game_server() -> void:
	print("[HeadlessServer] Starting ENet server on port %d..." % game_port)

	var error := NetworkManager.host_server(game_port, NetworkManager.MAX_PLAYERS)

	if error != OK:
		push_error("[HeadlessServer] Failed to start server: %s" % error_string(error))
		_shutdown("Failed to start ENet server")


func _on_server_started() -> void:
	print("[HeadlessServer] ENet server started, registering with backend...")
	_send_ready()


# ============================================
# /servers/ready (ONE-TIME with retry)
# ============================================

func _send_ready() -> void:
	var url := backend_url + "/servers/ready"
	var payload := {"port": game_port}

	if session_id != "":
		payload["session_id"] = session_id

	var body := JSON.stringify(payload)
	var headers := ["Content-Type: application/json"]

	var error := _ready_http.request(url, headers, HTTPClient.METHOD_POST, body)
	if error != OK:
		push_error("[HeadlessServer] Ready request failed: %s" % error_string(error))
		_schedule_ready_retry()
		return

	print("[HeadlessServer] POST /servers/ready (port=%d)" % game_port)


func _on_ready_response(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS:
		push_error("[HeadlessServer] Ready HTTP error: %d" % result)
		_schedule_ready_retry()
		return

	if response_code < 200 or response_code >= 300:
		push_error("[HeadlessServer] Ready HTTP %d" % response_code)
		_schedule_ready_retry()
		return

	var json := JSON.new()
	if json.parse(body.get_string_from_utf8()) != OK:
		push_error("[HeadlessServer] Invalid JSON response")
		_schedule_ready_retry()
		return

	var data: Dictionary = json.data if json.data is Dictionary else {}

	if data.has("error"):
		push_error("[HeadlessServer] Ready failed: %s" % data.error)
		_schedule_ready_retry()
		return

	server_id = data.get("serverId", "")
	if server_id == "":
		push_error("[HeadlessServer] No serverId in response")
		_schedule_ready_retry()
		return

	is_registered = true
	ready_retry_count = 0

	print("[HeadlessServer] ========================================")
	print("[HeadlessServer]  REGISTERED: %s" % server_id)
	print("[HeadlessServer]  Ready to accept players!")
	print("[HeadlessServer] ========================================")

	# Start heartbeat timer
	_heartbeat_timer.start()

	server_registered.emit(server_id)


func _schedule_ready_retry() -> void:
	ready_retry_count += 1

	if ready_retry_count > ServerConstants.READY_MAX_RETRIES:
		push_error("[HeadlessServer] Max retries exceeded, shutting down")
		_shutdown("Failed to register with backend")
		return

	print("[HeadlessServer] Retry %d/%d in %0.1fs..." % [
		ready_retry_count,
		ServerConstants.READY_MAX_RETRIES,
		ServerConstants.READY_RETRY_INTERVAL_SEC
	])
	_ready_retry_timer.start()


# ============================================
# /servers/heartbeat (EVERY 2 SECONDS)
# ============================================

func _send_heartbeat() -> void:
	if server_id == "":
		return

	# Create new HTTPRequest for fire-and-forget
	var http := HTTPRequest.new()
	http.timeout = 5.0
	add_child(http)

	# Auto-cleanup after response
	http.request_completed.connect(func(_r, _c, _h, _b): http.queue_free())

	var url := backend_url + "/servers/heartbeat"
	var payload := {
		"serverId": server_id,
		"playerCount": player_count
	}

	var body := JSON.stringify(payload)
	var headers := ["Content-Type: application/json"]

	http.request(url, headers, HTTPClient.METHOD_POST, body)


# ============================================
# PLAYER TRACKING
# ============================================

func _on_player_joined(peer_id: int) -> void:
	if peer_id == 1:  # Server itself
		return

	player_count = _get_real_player_count()
	last_player_left_time = -1.0
	print("[HeadlessServer] Player joined (peer=%d), count=%d" % [peer_id, player_count])

	_report_player_joined(peer_id)


func _on_player_left(peer_id: int) -> void:
	if peer_id == 1:
		return

	player_count = _get_real_player_count()
	print("[HeadlessServer] Player left (peer=%d), count=%d" % [peer_id, player_count])

	_report_player_left(peer_id)


func _get_real_player_count() -> int:
	var peers := multiplayer.get_peers()
	return peers.size()


# ============================================
# GAME EVENT REPORTING
# ============================================

func _report_event(endpoint: String, data: Dictionary) -> void:
	if not is_registered:
		return

	var http := HTTPRequest.new()
	http.timeout = 5.0
	add_child(http)
	http.request_completed.connect(func(_r, _c, _h, _b): http.queue_free())

	var url := backend_url + endpoint
	var body := JSON.stringify(data)
	var headers := ["Content-Type: application/json"]

	http.request(url, headers, HTTPClient.METHOD_POST, body)


func _report_player_joined(peer_id: int) -> void:
	if current_match_id == "":
		return
	_report_event("/game/player_joined", {
		"matchId": current_match_id,
		"playerId": "peer_%d" % peer_id
	})


func _report_player_left(peer_id: int) -> void:
	if current_match_id == "":
		return
	_report_event("/game/player_left", {
		"matchId": current_match_id,
		"playerId": "peer_%d" % peer_id
	})


func _on_wave_started(wave_number: int) -> void:
	print("[HeadlessServer] Wave %d started" % wave_number)


func _on_wave_ended(wave_number: int) -> void:
	print("[HeadlessServer] Wave %d ended" % wave_number)
	var zombies_killed: int = GameState.wave_zombies_killed if GameState else 0
	_report_event("/game/wave_complete", {
		"matchId": current_match_id,
		"waveNumber": wave_number,
		"zombiesKilled": zombies_killed
	})


func report_match_end(reason: String = "completed") -> void:
	if current_match_id == "":
		return
	var final_wave: int = GameState.current_wave if GameState else 0
	_report_event("/game/match_end", {
		"matchId": current_match_id,
		"reason": reason,
		"finalWave": final_wave
	})
	print("[HeadlessServer] Reported match_end: %s (wave %d)" % [reason, final_wave])
	current_match_id = ""


func set_match_id(match_id: String) -> void:
	current_match_id = match_id
	print("[HeadlessServer] Match ID set: %s" % match_id)


# ============================================
# SHUTDOWN
# ============================================

func _shutdown(reason: String) -> void:
	print("[HeadlessServer] ========================================")
	print("[HeadlessServer]  SHUTTING DOWN: %s" % reason)
	print("[HeadlessServer] ========================================")

	# Stop timers
	if _heartbeat_timer:
		_heartbeat_timer.stop()

	# Report match end
	if current_match_id != "":
		report_match_end(reason)

	shutting_down.emit(reason)

	# Clean disconnect
	if NetworkManager:
		NetworkManager.disconnect_from_network()

	# Brief delay for cleanup
	await get_tree().create_timer(0.5).timeout
	get_tree().quit(0)


# ============================================
# PUBLIC API
# ============================================

func get_server_id() -> String:
	return server_id


func get_player_count() -> int:
	return player_count


func is_server_registered() -> bool:
	return is_registered


func get_uptime() -> float:
	return Time.get_ticks_msec() / 1000.0


# ============================================
# SESSION/LOBBY DATA MANAGEMENT
# ============================================

## Set session data (called when lobby starts the game)
func set_session_data(data: Dictionary) -> void:
	session_data = data
	print("[HeadlessServer] Session data set: %s" % data)

	# Parse lobby players for spawn registry
	var lobby_players: Array = data.get("lobby_players", [])
	for player_info in lobby_players:
		var player_id: String = player_info.get("player_id", "")
		var group: String = player_info.get("group", "")
		var spawn_index: int = player_info.get("spawn_index", 0)

		if player_id != "":
			# Store by player_id, will map to peer_id when they connect
			player_spawn_registry[player_id] = {
				"group": group,
				"index": spawn_index
			}
			print("[HeadlessServer] Registered spawn for %s: group=%s, index=%d" % [player_id, group, spawn_index])


## Get session data
func get_session_data() -> Dictionary:
	return session_data


## Register peer_id to player_id mapping (called when player connects and identifies)
func register_player_peer(player_id: String, peer_id: int) -> void:
	if player_id in player_spawn_registry:
		var info: Dictionary = player_spawn_registry[player_id]
		player_spawn_registry[peer_id] = info
		print("[HeadlessServer] Mapped peer %d to player %s (group=%s, index=%d)" % [
			peer_id, player_id, info.get("group", ""), info.get("index", 0)
		])


## Get spawn info for a peer
func get_player_spawn_info(peer_id: int) -> Dictionary:
	if peer_id in player_spawn_registry:
		return player_spawn_registry[peer_id]

	# Check if we have any spawn info stored by player_id that matches
	for key in player_spawn_registry:
		if key is int and key == peer_id:
			return player_spawn_registry[key]

	# Default fallback
	return {
		"group": "",
		"index": peer_id - 1
	}


## Clear all session data (for match end)
func clear_session_data() -> void:
	session_data = {}
	player_spawn_registry = {}
	print("[HeadlessServer] Session data cleared")
