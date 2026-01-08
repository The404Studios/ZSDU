extends Control
## MainMenu - Game entry point and server/client selection

@onready var host_button: Button = $VBoxContainer/HostButton
@onready var join_button: Button = $VBoxContainer/JoinContainer/JoinButton
@onready var address_input: LineEdit = $VBoxContainer/JoinContainer/AddressInput
@onready var port_input: SpinBox = $VBoxContainer/PortContainer/PortInput
@onready var quit_button: Button = $VBoxContainer/QuitButton
@onready var status_label: Label = $StatusLabel

# Optional Quick Play button (add to scene if desired)
@onready var quick_play_button: Button = $VBoxContainer/QuickPlayButton if has_node("VBoxContainer/QuickPlayButton") else null

# Player ID for matchmaking (generated once per session)
var player_id: String = ""


func _ready() -> void:
	# Generate player ID
	player_id = "player_%d" % randi()

	# Connect buttons
	host_button.pressed.connect(_on_host_pressed)
	join_button.pressed.connect(_on_join_pressed)
	quit_button.pressed.connect(_on_quit_pressed)

	# Connect Quick Play if it exists
	if quick_play_button:
		quick_play_button.pressed.connect(_on_quick_play_pressed)

	# Connect network signals
	NetworkManager.server_started.connect(_on_server_started)
	NetworkManager.client_connected.connect(_on_client_connected)
	NetworkManager.connection_failed.connect(_on_connection_failed)

	# Connect matchmaking signals
	GameManagerClient.match_found.connect(_on_match_found)
	GameManagerClient.connection_error.connect(_on_matchmaking_error)

	# Show mouse
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _on_host_pressed() -> void:
	var port := int(port_input.value)

	status_label.text = "Starting server..."
	_disable_buttons()

	var error := NetworkManager.host_server(port)

	if error != OK:
		status_label.text = "Failed to start server: %s" % error_string(error)
		_enable_buttons()


func _on_join_pressed() -> void:
	var address := address_input.text.strip_edges()
	var port := int(port_input.value)

	if address.is_empty():
		status_label.text = "Please enter an IP address"
		return

	status_label.text = "Connecting to %s:%d..." % [address, port]
	_disable_buttons()

	var error := NetworkManager.join_server(address, port)

	if error != OK:
		status_label.text = "Failed to connect: %s" % error_string(error)
		_enable_buttons()


func _on_quit_pressed() -> void:
	get_tree().quit()


func _on_server_started() -> void:
	status_label.text = "Server started! Loading game..."
	_load_game()


func _on_client_connected() -> void:
	status_label.text = "Connected! Loading game..."
	_load_game()


func _on_connection_failed() -> void:
	status_label.text = "Connection failed!"
	_enable_buttons()


# ============================================
# QUICK PLAY / MATCHMAKING
# ============================================

func _on_quick_play_pressed() -> void:
	status_label.text = "Finding match..."
	_disable_buttons()

	# Use GameManagerClient to find a match
	GameManagerClient.quick_play(player_id, "survival")


func _on_match_found(server_info: Dictionary) -> void:
	var host: String = server_info.get("host", "127.0.0.1")
	var port: int = server_info.get("port", 27015)

	status_label.text = "Match found! Connecting to %s:%d..." % [host, port]
	# Connection is handled by quick_play, which calls NetworkManager.join_server


func _on_matchmaking_error(error_msg: String) -> void:
	status_label.text = "Matchmaking failed: %s" % error_msg
	_enable_buttons()


# ============================================
# HELPERS
# ============================================

func _disable_buttons() -> void:
	host_button.disabled = true
	join_button.disabled = true
	if quick_play_button:
		quick_play_button.disabled = true


func _enable_buttons() -> void:
	host_button.disabled = false
	join_button.disabled = false
	if quick_play_button:
		quick_play_button.disabled = false


func _load_game() -> void:
	# Small delay for smooth transition
	await get_tree().create_timer(0.5).timeout
	get_tree().change_scene_to_file("res://scenes/game_world.tscn")
