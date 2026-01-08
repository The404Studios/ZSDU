extends Control
## MainMenu - Game entry point with lobby system integration
##
## Provides:
## - Quick Play (solo or matchmaking)
## - Create Lobby (host a group)
## - Join Lobby (join by code)
## - Direct Connect (LAN/debug)

@onready var host_button: Button = $VBoxContainer/HostButton
@onready var join_button: Button = $VBoxContainer/JoinContainer/JoinButton
@onready var address_input: LineEdit = $VBoxContainer/JoinContainer/AddressInput
@onready var port_input: SpinBox = $VBoxContainer/PortContainer/PortInput
@onready var quit_button: Button = $VBoxContainer/QuitButton
@onready var status_label: Label = $StatusLabel

# Dynamically created lobby buttons
var quick_play_button: Button = null
var create_lobby_button: Button = null
var join_lobby_button: Button = null
var lobby_code_input: LineEdit = null

# Player ID for matchmaking
var player_id: String = ""


func _ready() -> void:
	# Use FriendSystem's player ID
	player_id = FriendSystem.get_player_id()

	# Connect existing buttons
	host_button.pressed.connect(_on_host_pressed)
	join_button.pressed.connect(_on_join_pressed)
	quit_button.pressed.connect(_on_quit_pressed)

	# Add lobby buttons dynamically
	_setup_lobby_buttons()

	# Connect network signals
	NetworkManager.server_started.connect(_on_server_started)
	NetworkManager.client_connected.connect(_on_client_connected)
	NetworkManager.connection_failed.connect(_on_connection_failed)

	# Connect matchmaking signals
	GameManagerClient.match_found.connect(_on_match_found)
	GameManagerClient.connection_error.connect(_on_matchmaking_error)

	# Connect lobby signals
	LobbySystem.lobby_created.connect(_on_lobby_created)
	LobbySystem.lobby_joined.connect(_on_lobby_joined)
	LobbySystem.lobby_error.connect(_on_lobby_error)

	# Show mouse
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _setup_lobby_buttons() -> void:
	var vbox: VBoxContainer = $VBoxContainer

	# Find spacer index to insert lobby buttons after
	var spacer_idx := 0
	for i in range(vbox.get_child_count()):
		if vbox.get_child(i).name == "Spacer":
			spacer_idx = i + 1
			break

	# Quick Play button
	quick_play_button = Button.new()
	quick_play_button.name = "QuickPlayButton"
	quick_play_button.text = "Quick Play"
	quick_play_button.custom_minimum_size.y = 40
	quick_play_button.pressed.connect(_on_quick_play_pressed)
	vbox.add_child(quick_play_button)
	vbox.move_child(quick_play_button, spacer_idx)

	# Create Lobby button
	create_lobby_button = Button.new()
	create_lobby_button.name = "CreateLobbyButton"
	create_lobby_button.text = "Create Lobby"
	create_lobby_button.custom_minimum_size.y = 40
	create_lobby_button.pressed.connect(_on_create_lobby_pressed)
	vbox.add_child(create_lobby_button)
	vbox.move_child(create_lobby_button, spacer_idx + 1)

	# Join Lobby container
	var join_lobby_container := HBoxContainer.new()
	join_lobby_container.name = "JoinLobbyContainer"
	vbox.add_child(join_lobby_container)
	vbox.move_child(join_lobby_container, spacer_idx + 2)

	lobby_code_input = LineEdit.new()
	lobby_code_input.placeholder_text = "Lobby Code"
	lobby_code_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lobby_code_input.custom_minimum_size.y = 40
	join_lobby_container.add_child(lobby_code_input)

	join_lobby_button = Button.new()
	join_lobby_button.text = "Join Lobby"
	join_lobby_button.custom_minimum_size = Vector2(100, 40)
	join_lobby_button.pressed.connect(_on_join_lobby_pressed)
	join_lobby_container.add_child(join_lobby_button)

	# Separator before direct connect
	var separator := HSeparator.new()
	vbox.add_child(separator)
	vbox.move_child(separator, spacer_idx + 3)

	# Label for direct connect section
	var direct_label := Label.new()
	direct_label.text = "--- Direct Connect (LAN) ---"
	direct_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(direct_label)
	vbox.move_child(direct_label, spacer_idx + 4)


# ============================================
# LOBBY BUTTONS
# ============================================

func _on_quick_play_pressed() -> void:
	status_label.text = "Finding match..."
	_disable_buttons()

	# Use matchmaking to find a server
	GameManagerClient.quick_play(player_id, "survival")


func _on_create_lobby_pressed() -> void:
	status_label.text = "Creating lobby..."
	_disable_buttons()

	# Create a lobby with player's name
	var lobby_name := "%s's Game" % FriendSystem.local_player_name
	LobbySystem.create_lobby(lobby_name, 4, "survival")


func _on_join_lobby_pressed() -> void:
	var code := lobby_code_input.text.strip_edges().to_upper()
	if code.is_empty():
		status_label.text = "Enter a lobby code"
		return

	status_label.text = "Joining lobby..."
	_disable_buttons()

	LobbySystem.join_lobby(code)


func _on_lobby_created(_lobby_id: String) -> void:
	get_tree().change_scene_to_file("res://scenes/lobby.tscn")


func _on_lobby_joined(_lobby_data: Dictionary) -> void:
	get_tree().change_scene_to_file("res://scenes/lobby.tscn")


func _on_lobby_error(message: String) -> void:
	status_label.text = "Error: %s" % message
	_enable_buttons()


# ============================================
# DIRECT CONNECT (LAN)
# ============================================

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


# ============================================
# NETWORK CALLBACKS
# ============================================

func _on_server_started() -> void:
	status_label.text = "Server started! Loading game..."
	_load_game()


func _on_client_connected() -> void:
	status_label.text = "Connected! Loading game..."
	_load_game()


func _on_connection_failed() -> void:
	status_label.text = "Connection failed!"
	_enable_buttons()


func _on_match_found(server_info: Dictionary) -> void:
	var host: String = server_info.get("host", "127.0.0.1")
	var port: int = server_info.get("port", 27015)
	status_label.text = "Match found! Connecting to %s:%d..." % [host, port]


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
	if create_lobby_button:
		create_lobby_button.disabled = true
	if join_lobby_button:
		join_lobby_button.disabled = true


func _enable_buttons() -> void:
	host_button.disabled = false
	join_button.disabled = false
	if quick_play_button:
		quick_play_button.disabled = false
	if create_lobby_button:
		create_lobby_button.disabled = false
	if join_lobby_button:
		join_lobby_button.disabled = false


func _load_game() -> void:
	await get_tree().create_timer(0.5).timeout
	get_tree().change_scene_to_file("res://scenes/game_world.tscn")
