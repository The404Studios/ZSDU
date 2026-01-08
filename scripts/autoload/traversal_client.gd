extends Node
## TraversalClient - Handles session discovery via external C# traversal server
##
## Connection flow:
## 1. DISCOVER - Query traversal server for sessions or register host
## 2. CONNECT  - Use returned info to establish ENet connection
## 3. SYNC     - Receive world snapshot
## 4. PLAY     - Normal gameplay
##
## Traversal server handles NAT traversal, session listing, heartbeats.

signal session_list_received(sessions: Array)
signal session_created(session_id: String)
signal session_joined(host_ip: String, host_port: int)
signal traversal_error(message: String)
signal connection_state_changed(state: ConnectionState)

enum ConnectionState {
	DISCONNECTED,
	DISCOVERING,
	CONNECTING,
	SYNCING,
	PLAYING,
	ERROR
}

# Traversal server config
const TRAVERSAL_HOST := "162.248.94.149"
const TRAVERSAL_PORT := 7777
const HEARTBEAT_INTERVAL := 5.0
const TIMEOUT_DURATION := 15.0

# Protocol message types
enum MessageType {
	# Client -> Server
	REGISTER_HOST = 1,
	UNREGISTER_HOST = 2,
	LIST_SESSIONS = 3,
	JOIN_SESSION = 4,
	HEARTBEAT = 5,

	# Server -> Client
	SESSION_CREATED = 101,
	SESSION_LIST = 102,
	JOIN_INFO = 103,
	ERROR = 104,
	HEARTBEAT_ACK = 105,
}

# Current state
var current_state: ConnectionState = ConnectionState.DISCONNECTED
var session_id: String = ""
var is_host := false

# Network
var tcp_client: StreamPeerTCP = null
var heartbeat_timer := 0.0
var timeout_timer := 0.0
var pending_data := PackedByteArray()

# Session info (when hosting)
var host_session_name := ""
var host_game_port := 27015
var host_max_players := 32
var host_current_players := 1


func _ready() -> void:
	set_process(false)  # Enable when connected


func _process(delta: float) -> void:
	if tcp_client == null:
		return

	# Poll TCP connection
	tcp_client.poll()
	var status := tcp_client.get_status()

	match status:
		StreamPeerTCP.STATUS_CONNECTED:
			_handle_connected(delta)
		StreamPeerTCP.STATUS_CONNECTING:
			_handle_connecting(delta)
		StreamPeerTCP.STATUS_ERROR:
			_handle_error("TCP connection error")
		StreamPeerTCP.STATUS_NONE:
			if current_state != ConnectionState.DISCONNECTED:
				_handle_error("Connection lost")


func _handle_connecting(delta: float) -> void:
	timeout_timer += delta
	if timeout_timer > TIMEOUT_DURATION:
		_handle_error("Connection timeout")


func _handle_connected(delta: float) -> void:
	# Read incoming data
	var available := tcp_client.get_available_bytes()
	if available > 0:
		var data := tcp_client.get_data(available)
		if data[0] == OK:
			pending_data.append_array(data[1])
			_process_incoming_data()

	# Heartbeat (if hosting)
	if is_host and current_state == ConnectionState.PLAYING:
		heartbeat_timer += delta
		if heartbeat_timer >= HEARTBEAT_INTERVAL:
			heartbeat_timer = 0.0
			_send_heartbeat()


func _process_incoming_data() -> void:
	# Simple length-prefixed protocol: [4 bytes length][data]
	while pending_data.size() >= 4:
		var length := pending_data.decode_u32(0)
		if pending_data.size() < 4 + length:
			break  # Wait for more data

		var message_data := pending_data.slice(4, 4 + length)
		pending_data = pending_data.slice(4 + length)

		_handle_message(message_data)


func _handle_message(data: PackedByteArray) -> void:
	if data.size() < 1:
		return

	var msg_type: int = data[0]
	var payload := data.slice(1)

	match msg_type:
		MessageType.SESSION_CREATED:
			_on_session_created(payload)
		MessageType.SESSION_LIST:
			_on_session_list(payload)
		MessageType.JOIN_INFO:
			_on_join_info(payload)
		MessageType.ERROR:
			_on_server_error(payload)
		MessageType.HEARTBEAT_ACK:
			pass  # Connection alive


func _on_session_created(payload: PackedByteArray) -> void:
	# Payload: session_id as string
	session_id = payload.get_string_from_utf8()
	print("[Traversal] Session created: %s" % session_id)

	_set_state(ConnectionState.PLAYING)
	session_created.emit(session_id)


func _on_session_list(payload: PackedByteArray) -> void:
	# Payload: JSON array of sessions
	var json_str := payload.get_string_from_utf8()
	var json := JSON.new()
	var error := json.parse(json_str)

	if error != OK:
		push_error("Failed to parse session list")
		return

	var sessions: Array = json.data if json.data is Array else []
	print("[Traversal] Received %d sessions" % sessions.size())

	session_list_received.emit(sessions)


func _on_join_info(payload: PackedByteArray) -> void:
	# Payload: JSON with host_ip, host_port
	var json_str := payload.get_string_from_utf8()
	var json := JSON.new()
	var error := json.parse(json_str)

	if error != OK:
		_handle_error("Invalid join info")
		return

	var info: Dictionary = json.data
	var host_ip: String = info.get("host_ip", "")
	var host_port: int = info.get("host_port", 27015)

	print("[Traversal] Join info: %s:%d" % [host_ip, host_port])

	_set_state(ConnectionState.CONNECTING)
	session_joined.emit(host_ip, host_port)


func _on_server_error(payload: PackedByteArray) -> void:
	var error_msg := payload.get_string_from_utf8()
	_handle_error(error_msg)


func _handle_error(message: String) -> void:
	push_error("[Traversal] Error: %s" % message)
	_set_state(ConnectionState.ERROR)
	traversal_error.emit(message)
	disconnect_traversal()


func _set_state(new_state: ConnectionState) -> void:
	if current_state != new_state:
		current_state = new_state
		connection_state_changed.emit(new_state)


# ============================================
# PUBLIC API
# ============================================

## Connect to traversal server
func connect_to_traversal() -> Error:
	if tcp_client != null:
		disconnect_traversal()

	tcp_client = StreamPeerTCP.new()
	var error := tcp_client.connect_to_host(TRAVERSAL_HOST, TRAVERSAL_PORT)

	if error != OK:
		push_error("[Traversal] Failed to connect: %s" % error_string(error))
		return error

	_set_state(ConnectionState.DISCOVERING)
	timeout_timer = 0.0
	set_process(true)

	print("[Traversal] Connecting to %s:%d" % [TRAVERSAL_HOST, TRAVERSAL_PORT])
	return OK


## Disconnect from traversal server
func disconnect_traversal() -> void:
	if is_host and session_id != "":
		_send_unregister()

	if tcp_client:
		tcp_client.disconnect_from_host()
		tcp_client = null

	_set_state(ConnectionState.DISCONNECTED)
	session_id = ""
	is_host = false
	pending_data.clear()
	set_process(false)


## Register as host (create session)
func register_host(session_name: String, game_port: int, max_players: int) -> void:
	if current_state != ConnectionState.DISCOVERING:
		# Need to connect first
		var error := connect_to_traversal()
		if error != OK:
			return
		# Wait for connection, then register
		await get_tree().create_timer(0.5).timeout

	host_session_name = session_name
	host_game_port = game_port
	host_max_players = max_players
	host_current_players = 1
	is_host = true

	var payload := {
		"name": session_name,
		"port": game_port,
		"max_players": max_players,
		"current_players": 1,
		"game_version": ProjectSettings.get_setting("application/config/version", "1.0"),
	}

	_send_message(MessageType.REGISTER_HOST, JSON.stringify(payload))
	print("[Traversal] Registering host: %s" % session_name)


## Request session list
func request_session_list() -> void:
	if current_state == ConnectionState.DISCONNECTED:
		var error := connect_to_traversal()
		if error != OK:
			return
		await get_tree().create_timer(0.5).timeout

	_send_message(MessageType.LIST_SESSIONS, "")
	print("[Traversal] Requesting session list")


## Join a session by ID
func join_session(target_session_id: String) -> void:
	if current_state == ConnectionState.DISCONNECTED:
		var error := connect_to_traversal()
		if error != OK:
			return
		await get_tree().create_timer(0.5).timeout

	session_id = target_session_id
	is_host = false

	_send_message(MessageType.JOIN_SESSION, target_session_id)
	print("[Traversal] Joining session: %s" % target_session_id)


## Update player count (host only)
func update_player_count(count: int) -> void:
	if not is_host:
		return

	host_current_players = count
	# This gets sent with heartbeat


## Generate a session ID (for offline/LAN use)
static func generate_session_id() -> String:
	var uuid := ""
	for i in range(32):
		if i == 8 or i == 12 or i == 16 or i == 20:
			uuid += "-"
		uuid += "0123456789abcdef"[randi() % 16]
	return uuid


# ============================================
# PRIVATE MESSAGING
# ============================================

func _send_message(msg_type: MessageType, payload: String) -> void:
	if tcp_client == null or tcp_client.get_status() != StreamPeerTCP.STATUS_CONNECTED:
		return

	var payload_bytes := payload.to_utf8_buffer()
	var message := PackedByteArray()
	message.append(msg_type)
	message.append_array(payload_bytes)

	# Length prefix
	var length := message.size()
	var packet := PackedByteArray()
	packet.resize(4)
	packet.encode_u32(0, length)
	packet.append_array(message)

	tcp_client.put_data(packet)


func _send_heartbeat() -> void:
	var payload := {
		"session_id": session_id,
		"current_players": host_current_players,
	}
	_send_message(MessageType.HEARTBEAT, JSON.stringify(payload))


func _send_unregister() -> void:
	_send_message(MessageType.UNREGISTER_HOST, session_id)


# ============================================
# STATE HELPERS
# ============================================

func is_connected_to_traversal() -> bool:
	return tcp_client != null and tcp_client.get_status() == StreamPeerTCP.STATUS_CONNECTED


func get_session_id() -> String:
	return session_id


func get_state_name() -> String:
	match current_state:
		ConnectionState.DISCONNECTED: return "DISCONNECTED"
		ConnectionState.DISCOVERING: return "DISCOVERING"
		ConnectionState.CONNECTING: return "CONNECTING"
		ConnectionState.SYNCING: return "SYNCING"
		ConnectionState.PLAYING: return "PLAYING"
		ConnectionState.ERROR: return "ERROR"
	return "UNKNOWN"
