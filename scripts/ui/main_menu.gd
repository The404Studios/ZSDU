extends Control
## MainMenu - Game entry point and server/client selection

@onready var host_button: Button = $VBoxContainer/HostButton
@onready var join_button: Button = $VBoxContainer/JoinContainer/JoinButton
@onready var address_input: LineEdit = $VBoxContainer/JoinContainer/AddressInput
@onready var port_input: SpinBox = $VBoxContainer/PortContainer/PortInput
@onready var quit_button: Button = $VBoxContainer/QuitButton
@onready var status_label: Label = $StatusLabel


func _ready() -> void:
	# Connect buttons
	host_button.pressed.connect(_on_host_pressed)
	join_button.pressed.connect(_on_join_pressed)
	quit_button.pressed.connect(_on_quit_pressed)

	# Connect network signals
	NetworkManager.server_started.connect(_on_server_started)
	NetworkManager.client_connected.connect(_on_client_connected)
	NetworkManager.connection_failed.connect(_on_connection_failed)

	# Show mouse
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _on_host_pressed() -> void:
	var port := int(port_input.value)

	status_label.text = "Starting server..."
	host_button.disabled = true
	join_button.disabled = true

	var error := NetworkManager.host_server(port)

	if error != OK:
		status_label.text = "Failed to start server: %s" % error_string(error)
		host_button.disabled = false
		join_button.disabled = false


func _on_join_pressed() -> void:
	var address := address_input.text.strip_edges()
	var port := int(port_input.value)

	if address.is_empty():
		status_label.text = "Please enter an IP address"
		return

	status_label.text = "Connecting to %s:%d..." % [address, port]
	host_button.disabled = true
	join_button.disabled = true

	var error := NetworkManager.join_server(address, port)

	if error != OK:
		status_label.text = "Failed to connect: %s" % error_string(error)
		host_button.disabled = false
		join_button.disabled = false


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
	host_button.disabled = false
	join_button.disabled = false


func _load_game() -> void:
	# Small delay for smooth transition
	await get_tree().create_timer(0.5).timeout
	get_tree().change_scene_to_file("res://scenes/game_world.tscn")
