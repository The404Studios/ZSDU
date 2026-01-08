extends Node
## HeadlessServer - Dedicated server backend integration
##
## Handles:
## - Environment variable parsing (GAME_PORT, BACKEND_HOST, BACKEND_PORT)
## - HTTP registration with backend (/servers/ready)
## - Heartbeat loop (/servers/heartbeat every 2s)
## - Auto-shutdown when empty for N seconds
##
## Only active when running with --headless flag.

signal server_registered(server_id: String)
signal registration_failed(error: String)
signal heartbeat_failed(error: String)
signal shutting_down(reason: String)

# ============================================
# LOCKED CONSTANTS (DO NOT CHANGE)
# ============================================
const HEARTBEAT_INTERVAL := 2.0      # Send heartbeat every 2 seconds
const HEARTBEAT_TIMEOUT := 6.0       # Backend marks dead after 6s without heartbeat
const EMPTY_SHUTDOWN_TIME := 120.0   # Shutdown after 2 minutes with no players
const READY_RETRY_INTERVAL := 2.0    # Retry /servers/ready every 2s on failure
const READY_MAX_RETRIES := 15        # Give up after 30 seconds

# ============================================
# CONFIGURATION (from environment)
# ============================================
var game_port: int = 27015
var backend_host: String = "127.0.0.1"
var backend_port: int = 8080
var is_headless: bool = false

# ============================================
# STATE
# ============================================
var server_id: String = ""
var is_registered: bool = false
var player_count: int = 0
var time_since_empty: float = 0.0
var heartbeat_timer: float = 0.0
var ready_retry_count: int = 0

# HTTP client
var _http_request: HTTPRequest = null
var _pending_request: String = ""


func _ready() -> void:
	# Check if running headless
	is_headless = _check_headless_mode()

	if not is_headless:
		print("[HeadlessServer] Not running in headless mode, disabled")
		set_process(false)
		return

	# Parse environment variables
	_load_config()

	# Create HTTP request node
	_http_request = HTTPRequest.new()
	_http_request.timeout = 10.0
	_http_request.request_completed.connect(_on_http_request_completed)
	add_child(_http_request)

	# Connect to NetworkManager signals
	if NetworkManager:
		NetworkManager.player_joined.connect(_on_player_joined)
		NetworkManager.player_left.connect(_on_player_left)
		NetworkManager.server_started.connect(_on_server_started)

	print("[HeadlessServer] ========================================")
	print("[HeadlessServer]  ZSDU Dedicated Server Starting")
	print("[HeadlessServer] ========================================")
	print("[HeadlessServer] Game Port: %d" % game_port)
	print("[HeadlessServer] Backend: %s:%d" % [backend_host, backend_port])
	print("[HeadlessServer] Heartbeat: %0.1fs interval, %0.1fs timeout" % [HEARTBEAT_INTERVAL, HEARTBEAT_TIMEOUT])
	print("[HeadlessServer] Empty shutdown: %0.0fs" % EMPTY_SHUTDOWN_TIME)

	# Start the ENet server
	_start_game_server()


func _process(delta: float) -> void:
	if not is_headless:
		return

	# Heartbeat loop (only when registered)
	if is_registered:
		heartbeat_timer += delta
		if heartbeat_timer >= HEARTBEAT_INTERVAL:
			heartbeat_timer = 0.0
			_send_heartbeat()

	# Empty server shutdown check
	if player_count == 0 and is_registered:
		time_since_empty += delta
		if time_since_empty >= EMPTY_SHUTDOWN_TIME:
			_shutdown("No players for %0.0f seconds" % EMPTY_SHUTDOWN_TIME)
	else:
		time_since_empty = 0.0


func _check_headless_mode() -> bool:
	# Check for --headless in command line args
	var args := OS.get_cmdline_args()
	for arg in args:
		if arg == "--headless" or arg == "--server":
			return true

	# Also check if display server is available (Godot 4 method)
	return DisplayServer.get_name() == "headless"


func _load_config() -> void:
	# GAME_PORT - The port this server listens on
	var env_port := OS.get_environment("GAME_PORT")
	if env_port != "":
		game_port = int(env_port)

	# BACKEND_HOST - The backend API host
	var env_host := OS.get_environment("BACKEND_HOST")
	if env_host != "":
		backend_host = env_host

	# BACKEND_PORT - The backend API port
	var env_backend_port := OS.get_environment("BACKEND_PORT")
	if env_backend_port != "":
		backend_port = int(env_backend_port)


func _start_game_server() -> void:
	print("[HeadlessServer] Starting ENet server on port %d..." % game_port)

	# Use NetworkManager to start the server (no traversal for dedicated servers)
	var error := NetworkManager.host_server(game_port, NetworkManager.MAX_PLAYERS)

	if error != OK:
		push_error("[HeadlessServer] Failed to start server: %s" % error_string(error))
		_shutdown("Failed to start ENet server")
		return


func _on_server_started() -> void:
	print("[HeadlessServer] ENet server started, registering with backend...")

	# Now register with the backend
	_send_ready()


# ============================================
# HTTP API CALLS
# ============================================

func _get_api_url(endpoint: String) -> String:
	return "http://%s:%d%s" % [backend_host, backend_port, endpoint]


## POST /servers/ready - Tell backend we're ready to accept players
func _send_ready() -> void:
	if _pending_request != "":
		return  # Already a request in flight

	var url := _get_api_url("/servers/ready")
	var body := JSON.stringify({
		"port": game_port
	})

	var headers := ["Content-Type: application/json"]
	var error := _http_request.request(url, headers, HTTPClient.METHOD_POST, body)

	if error != OK:
		push_error("[HeadlessServer] HTTP request failed: %s" % error_string(error))
		_schedule_ready_retry()
		return

	_pending_request = "ready"
	print("[HeadlessServer] POST /servers/ready (port=%d)" % game_port)


## POST /servers/heartbeat - Periodic keepalive
func _send_heartbeat() -> void:
	if server_id == "" or _pending_request != "":
		return

	var url := _get_api_url("/servers/heartbeat")
	var body := JSON.stringify({
		"serverId": server_id,
		"playerCount": player_count
	})

	var headers := ["Content-Type: application/json"]
	var error := _http_request.request(url, headers, HTTPClient.METHOD_POST, body)

	if error != OK:
		push_error("[HeadlessServer] Heartbeat request failed: %s" % error_string(error))
		return

	_pending_request = "heartbeat"


func _on_http_request_completed(result: int, response_code: int, headers: PackedStringArray, body: PackedByteArray) -> void:
	var request_type := _pending_request
	_pending_request = ""

	if result != HTTPRequest.RESULT_SUCCESS:
		push_error("[HeadlessServer] HTTP error (result=%d) for %s" % [result, request_type])

		if request_type == "ready":
			_schedule_ready_retry()
		elif request_type == "heartbeat":
			heartbeat_failed.emit("HTTP error: %d" % result)
		return

	if response_code < 200 or response_code >= 300:
		push_error("[HeadlessServer] HTTP %d for %s" % [response_code, request_type])

		if request_type == "ready":
			_schedule_ready_retry()
		return

	# Parse JSON response
	var json := JSON.new()
	var parse_error := json.parse(body.get_string_from_utf8())
	if parse_error != OK:
		push_error("[HeadlessServer] Invalid JSON response")
		return

	var data: Dictionary = json.data if json.data is Dictionary else {}

	match request_type:
		"ready":
			_handle_ready_response(data)
		"heartbeat":
			_handle_heartbeat_response(data)


func _handle_ready_response(data: Dictionary) -> void:
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

	server_registered.emit(server_id)


func _handle_heartbeat_response(data: Dictionary) -> void:
	if data.has("error"):
		push_error("[HeadlessServer] Heartbeat error: %s" % data.error)
		heartbeat_failed.emit(data.error)


func _schedule_ready_retry() -> void:
	ready_retry_count += 1

	if ready_retry_count > READY_MAX_RETRIES:
		push_error("[HeadlessServer] Max retries exceeded, shutting down")
		_shutdown("Failed to register with backend")
		return

	print("[HeadlessServer] Retry %d/%d in %0.1fs..." % [ready_retry_count, READY_MAX_RETRIES, READY_RETRY_INTERVAL])

	# Use timer for retry
	await get_tree().create_timer(READY_RETRY_INTERVAL).timeout
	_send_ready()


# ============================================
# PLAYER TRACKING
# ============================================

func _on_player_joined(peer_id: int) -> void:
	# peer_id 1 is always the server, not a real player
	if peer_id == 1:
		return

	player_count = _get_real_player_count()
	time_since_empty = 0.0
	print("[HeadlessServer] Player joined (peer=%d), count=%d" % [peer_id, player_count])


func _on_player_left(peer_id: int) -> void:
	# peer_id 1 is always the server, not a real player
	if peer_id == 1:
		return

	player_count = _get_real_player_count()
	print("[HeadlessServer] Player left (peer=%d), count=%d" % [peer_id, player_count])

	if player_count == 0:
		print("[HeadlessServer] Server empty, will shutdown in %0.0fs if no new players" % EMPTY_SHUTDOWN_TIME)


func _get_real_player_count() -> int:
	# Get connected peers, subtract 1 for server (peer_id 1)
	var peers := NetworkManager.get_peer_ids()
	var count := peers.size()
	if 1 in peers:
		count -= 1
	return maxi(0, count)


# ============================================
# SHUTDOWN
# ============================================

func _shutdown(reason: String) -> void:
	print("[HeadlessServer] ========================================")
	print("[HeadlessServer]  SHUTTING DOWN: %s" % reason)
	print("[HeadlessServer] ========================================")

	shutting_down.emit(reason)

	# Clean disconnect
	if NetworkManager:
		NetworkManager.disconnect_from_network()

	# Exit cleanly
	await get_tree().create_timer(1.0).timeout
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
