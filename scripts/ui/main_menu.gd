extends Control
## MainMenu - Game entry point with full game flow
##
## Features:
## - Login/Account (uses FriendSystem player ID)
## - Quick Play (matchmaking)
## - Create/Join Lobby
## - Stash access (inventory management)
## - Settings
## - Direct Connect (LAN/debug)

# Main UI panels
var main_panel: PanelContainer = null
var login_panel: PanelContainer = null
var play_panel: PanelContainer = null
var settings_panel: PanelContainer = null

# Main menu buttons
var play_button: Button = null
var stash_button: Button = null
var character_button: Button = null
var traders_button: Button = null
var market_button: Button = null
var settings_button: Button = null
var quit_button: Button = null

# Play submenu buttons
var quick_play_button: Button = null
var create_lobby_button: Button = null
var join_lobby_button: Button = null
var direct_connect_button: Button = null
var back_to_main_button: Button = null

# Join lobby inputs
var lobby_code_input: LineEdit = null

# Direct connect inputs
var direct_connect_panel: PanelContainer = null
var address_input: LineEdit = null
var port_input: SpinBox = null
var host_button: Button = null
var join_button: Button = null
var back_from_direct_button: Button = null

# Login inputs
var username_input: LineEdit = null
var login_button: Button = null

# Status and info labels
var status_label: Label = null
var player_info_label: Label = null
var version_label: Label = null

# Player state
var player_id: String = ""
var is_logged_in: bool = false

# Menu manager (stash, loadout, traders, market)
var menu_manager: MenuManager = null
var current_loadout: Dictionary = {}


func _ready() -> void:
	# Check for dedicated server mode - skip UI and load game directly
	if _is_dedicated_server():
		print("[MainMenu] Dedicated server detected, loading game world...")
		# Wait for HeadlessServer to start the network
		# HeadlessServer handles server startup, we just load the scene
		await get_tree().create_timer(0.5).timeout
		get_tree().change_scene_to_file("res://scenes/game_world.tscn")
		return

	# Build the entire UI programmatically for full control
	_create_background()
	_create_main_menu()
	_create_play_menu()
	_create_direct_connect_menu()
	_create_login_panel()
	_create_settings_panel()
	_create_status_bar()

	# Apply saved settings on startup
	_apply_saved_settings()

	# Connect network signals
	if NetworkManager:
		NetworkManager.server_started.connect(_on_server_started)
		NetworkManager.client_connected.connect(_on_client_connected)
		NetworkManager.connection_failed.connect(_on_connection_failed)

	# Connect matchmaking signals
	if GameManagerClient:
		GameManagerClient.match_found.connect(_on_match_found)
		GameManagerClient.connection_error.connect(_on_matchmaking_error)

	# Connect lobby signals
	if LobbySystem:
		LobbySystem.lobby_created.connect(_on_lobby_created)
		LobbySystem.lobby_joined.connect(_on_lobby_joined)
		LobbySystem.lobby_error.connect(_on_lobby_error)

	# Connect economy signals
	if EconomyService:
		EconomyService.logged_in.connect(_on_economy_logged_in)
		EconomyService.login_failed.connect(_on_economy_login_failed)

	# Show mouse cursor
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

	# Check if already logged in
	if FriendSystem:
		player_id = FriendSystem.get_player_id()
		if player_id != "":
			_show_main_menu()
		else:
			_show_login()
	else:
		_show_login()


# ============================================
# UI CREATION
# ============================================

func _create_background() -> void:
	# Dark gradient background
	var bg := ColorRect.new()
	bg.name = "Background"
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0.08, 0.09, 0.1)
	add_child(bg)

	# Title
	var title := Label.new()
	title.name = "Title"
	title.text = "ZSDU"
	title.set_anchors_preset(Control.PRESET_CENTER_TOP)
	title.position = Vector2(-200, 60)
	title.custom_minimum_size = Vector2(400, 80)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 72)
	title.add_theme_color_override("font_color", Color(0.9, 0.2, 0.2))
	add_child(title)

	# Subtitle
	var subtitle := Label.new()
	subtitle.name = "Subtitle"
	subtitle.text = "Zombie Survival Defense Ultimate"
	subtitle.set_anchors_preset(Control.PRESET_CENTER_TOP)
	subtitle.position = Vector2(-200, 140)
	subtitle.custom_minimum_size = Vector2(400, 30)
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.add_theme_font_size_override("font_size", 18)
	subtitle.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	add_child(subtitle)


func _create_main_menu() -> void:
	main_panel = PanelContainer.new()
	main_panel.name = "MainPanel"
	main_panel.set_anchors_preset(Control.PRESET_CENTER)
	main_panel.custom_minimum_size = Vector2(320, 520)
	main_panel.position = Vector2(-160, -180)
	add_child(main_panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 15)
	main_panel.add_child(vbox)

	# Add margin
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 20)
	margin.add_theme_constant_override("margin_right", 20)
	margin.add_theme_constant_override("margin_top", 20)
	margin.add_theme_constant_override("margin_bottom", 20)
	main_panel.add_child(margin)

	var inner_vbox := VBoxContainer.new()
	inner_vbox.add_theme_constant_override("separation", 12)
	margin.add_child(inner_vbox)

	# Play button (opens play submenu)
	play_button = _create_menu_button("PLAY", Color(0.2, 0.7, 0.3))
	play_button.pressed.connect(_on_play_pressed)
	inner_vbox.add_child(play_button)

	# Character button (skills, attributes, gear)
	character_button = _create_menu_button("CHARACTER", Color(0.6, 0.4, 0.7))
	character_button.pressed.connect(_on_character_pressed)
	inner_vbox.add_child(character_button)

	# Stash button
	stash_button = _create_menu_button("STASH", Color(0.3, 0.5, 0.8))
	stash_button.pressed.connect(_on_stash_pressed)
	inner_vbox.add_child(stash_button)

	# Traders button
	traders_button = _create_menu_button("TRADERS", Color(0.7, 0.6, 0.3))
	traders_button.pressed.connect(_on_traders_pressed)
	inner_vbox.add_child(traders_button)

	# Market button
	market_button = _create_menu_button("MARKET", Color(0.3, 0.7, 0.6))
	market_button.pressed.connect(_on_market_pressed)
	inner_vbox.add_child(market_button)

	# Settings button
	settings_button = _create_menu_button("SETTINGS", Color(0.5, 0.5, 0.5))
	settings_button.pressed.connect(_on_settings_pressed)
	inner_vbox.add_child(settings_button)


func _create_settings_panel() -> void:
	settings_panel = PanelContainer.new()
	settings_panel.name = "SettingsPanel"
	settings_panel.set_anchors_preset(Control.PRESET_CENTER)
	settings_panel.custom_minimum_size = Vector2(500, 550)
	settings_panel.position = Vector2(-250, -225)
	settings_panel.visible = false
	add_child(settings_panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 25)
	margin.add_theme_constant_override("margin_right", 25)
	margin.add_theme_constant_override("margin_top", 20)
	margin.add_theme_constant_override("margin_bottom", 20)
	settings_panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	margin.add_child(vbox)

	# Title
	var title := Label.new()
	title.text = "SETTINGS"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 28)
	title.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8))
	vbox.add_child(title)

	var sep1 := HSeparator.new()
	vbox.add_child(sep1)

	# Audio section
	var audio_label := Label.new()
	audio_label.text = "Audio"
	audio_label.add_theme_font_size_override("font_size", 20)
	audio_label.add_theme_color_override("font_color", Color(0.6, 0.8, 0.9))
	vbox.add_child(audio_label)

	# Master Volume
	vbox.add_child(_create_volume_slider("Master Volume", "master_volume", 1.0))
	# Music Volume
	vbox.add_child(_create_volume_slider("Music Volume", "music_volume", 0.8))
	# SFX Volume
	vbox.add_child(_create_volume_slider("SFX Volume", "sfx_volume", 1.0))

	var sep2 := HSeparator.new()
	vbox.add_child(sep2)

	# Graphics section
	var graphics_label := Label.new()
	graphics_label.text = "Graphics"
	graphics_label.add_theme_font_size_override("font_size", 20)
	graphics_label.add_theme_color_override("font_color", Color(0.6, 0.8, 0.9))
	vbox.add_child(graphics_label)

	# Fullscreen toggle
	vbox.add_child(_create_toggle_setting("Fullscreen", "fullscreen", false))
	# VSync toggle
	vbox.add_child(_create_toggle_setting("VSync", "vsync", true))

	var sep3 := HSeparator.new()
	vbox.add_child(sep3)

	# Controls section
	var controls_label := Label.new()
	controls_label.text = "Controls"
	controls_label.add_theme_font_size_override("font_size", 20)
	controls_label.add_theme_color_override("font_color", Color(0.6, 0.8, 0.9))
	vbox.add_child(controls_label)

	# Mouse Sensitivity
	vbox.add_child(_create_sensitivity_slider("Mouse Sensitivity", "mouse_sensitivity", 0.5))

	# Spacer
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(spacer)

	# Buttons row
	var btn_row := HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 15)
	vbox.add_child(btn_row)

	var apply_btn := _create_menu_button("Apply", Color(0.3, 0.6, 0.3))
	apply_btn.custom_minimum_size = Vector2(140, 45)
	apply_btn.pressed.connect(_on_settings_apply_pressed)
	btn_row.add_child(apply_btn)

	var reset_btn := _create_menu_button("Reset", Color(0.6, 0.5, 0.3))
	reset_btn.custom_minimum_size = Vector2(140, 45)
	reset_btn.pressed.connect(_on_settings_reset_pressed)
	btn_row.add_child(reset_btn)

	var back_btn := _create_menu_button("Back", Color(0.4, 0.4, 0.4))
	back_btn.custom_minimum_size = Vector2(140, 45)
	back_btn.pressed.connect(_on_settings_back_pressed)
	btn_row.add_child(back_btn)


func _create_volume_slider(label_text: String, setting_name: String, default_value: float) -> HBoxContainer:
	var container := HBoxContainer.new()
	container.add_theme_constant_override("separation", 15)

	var label := Label.new()
	label.text = label_text
	label.custom_minimum_size = Vector2(140, 0)
	container.add_child(label)

	var slider := HSlider.new()
	slider.name = setting_name
	slider.min_value = 0.0
	slider.max_value = 1.0
	slider.step = 0.05
	slider.value = _load_setting(setting_name, default_value)
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.custom_minimum_size = Vector2(200, 25)
	slider.value_changed.connect(_on_volume_changed.bind(setting_name))
	container.add_child(slider)

	var value_label := Label.new()
	value_label.name = setting_name + "_value"
	value_label.text = "%d%%" % int(slider.value * 100)
	value_label.custom_minimum_size = Vector2(50, 0)
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	container.add_child(value_label)

	return container


func _create_sensitivity_slider(label_text: String, setting_name: String, default_value: float) -> HBoxContainer:
	var container := HBoxContainer.new()
	container.add_theme_constant_override("separation", 15)

	var label := Label.new()
	label.text = label_text
	label.custom_minimum_size = Vector2(140, 0)
	container.add_child(label)

	var slider := HSlider.new()
	slider.name = setting_name
	slider.min_value = 0.1
	slider.max_value = 2.0
	slider.step = 0.1
	slider.value = _load_setting(setting_name, default_value)
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.custom_minimum_size = Vector2(200, 25)
	slider.value_changed.connect(_on_sensitivity_changed.bind(setting_name))
	container.add_child(slider)

	var value_label := Label.new()
	value_label.name = setting_name + "_value"
	value_label.text = "%.1f" % slider.value
	value_label.custom_minimum_size = Vector2(50, 0)
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	container.add_child(value_label)

	return container


func _create_toggle_setting(label_text: String, setting_name: String, default_value: bool) -> HBoxContainer:
	var container := HBoxContainer.new()
	container.add_theme_constant_override("separation", 15)

	var label := Label.new()
	label.text = label_text
	label.custom_minimum_size = Vector2(140, 0)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	container.add_child(label)

	var toggle := CheckButton.new()
	toggle.name = setting_name
	toggle.button_pressed = _load_setting(setting_name, default_value)
	toggle.toggled.connect(_on_toggle_changed.bind(setting_name))
	container.add_child(toggle)

	return container


func _create_play_menu() -> void:
	play_panel = PanelContainer.new()
	play_panel.name = "PlayPanel"
	play_panel.set_anchors_preset(Control.PRESET_CENTER)
	play_panel.custom_minimum_size = Vector2(400, 400)
	play_panel.position = Vector2(-200, -120)
	play_panel.visible = false
	add_child(play_panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 20)
	margin.add_theme_constant_override("margin_right", 20)
	margin.add_theme_constant_override("margin_top", 20)
	margin.add_theme_constant_override("margin_bottom", 20)
	play_panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	margin.add_child(vbox)

	# Section title
	var title := Label.new()
	title.text = "PLAY"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 28)
	title.add_theme_color_override("font_color", Color(0.2, 0.7, 0.3))
	vbox.add_child(title)

	var separator := HSeparator.new()
	vbox.add_child(separator)

	# Quick Play
	quick_play_button = _create_menu_button("Quick Play", Color(0.3, 0.6, 0.3))
	quick_play_button.pressed.connect(_on_quick_play_pressed)
	vbox.add_child(quick_play_button)

	# Create Lobby
	create_lobby_button = _create_menu_button("Create Lobby", Color(0.3, 0.5, 0.7))
	create_lobby_button.pressed.connect(_on_create_lobby_pressed)
	vbox.add_child(create_lobby_button)

	# Join Lobby container
	var join_container := HBoxContainer.new()
	join_container.add_theme_constant_override("separation", 10)
	vbox.add_child(join_container)

	lobby_code_input = LineEdit.new()
	lobby_code_input.placeholder_text = "Lobby Code"
	lobby_code_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lobby_code_input.custom_minimum_size = Vector2(0, 45)
	join_container.add_child(lobby_code_input)

	join_lobby_button = Button.new()
	join_lobby_button.text = "Join"
	join_lobby_button.custom_minimum_size = Vector2(80, 45)
	join_lobby_button.pressed.connect(_on_join_lobby_pressed)
	join_container.add_child(join_lobby_button)

	# Separator
	var sep2 := HSeparator.new()
	vbox.add_child(sep2)

	# Direct Connect
	direct_connect_button = _create_menu_button("Direct Connect (LAN)", Color(0.5, 0.5, 0.5))
	direct_connect_button.pressed.connect(_on_direct_connect_pressed)
	vbox.add_child(direct_connect_button)

	# Spacer
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(spacer)

	# Back button
	back_to_main_button = _create_menu_button("Back", Color(0.4, 0.4, 0.4))
	back_to_main_button.pressed.connect(_on_back_to_main_pressed)
	vbox.add_child(back_to_main_button)


func _create_direct_connect_menu() -> void:
	direct_connect_panel = PanelContainer.new()
	direct_connect_panel.name = "DirectConnectPanel"
	direct_connect_panel.set_anchors_preset(Control.PRESET_CENTER)
	direct_connect_panel.custom_minimum_size = Vector2(350, 300)
	direct_connect_panel.position = Vector2(-175, -100)
	direct_connect_panel.visible = false
	add_child(direct_connect_panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 20)
	margin.add_theme_constant_override("margin_right", 20)
	margin.add_theme_constant_override("margin_top", 20)
	margin.add_theme_constant_override("margin_bottom", 20)
	direct_connect_panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	margin.add_child(vbox)

	# Title
	var title := Label.new()
	title.text = "Direct Connect"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 24)
	vbox.add_child(title)

	var separator := HSeparator.new()
	vbox.add_child(separator)

	# IP Address
	var addr_label := Label.new()
	addr_label.text = "IP Address:"
	vbox.add_child(addr_label)

	address_input = LineEdit.new()
	address_input.text = "127.0.0.1"
	address_input.custom_minimum_size = Vector2(0, 40)
	vbox.add_child(address_input)

	# Port
	var port_container := HBoxContainer.new()
	vbox.add_child(port_container)

	var port_label := Label.new()
	port_label.text = "Port:"
	port_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	port_container.add_child(port_label)

	port_input = SpinBox.new()
	port_input.min_value = 1024
	port_input.max_value = 65535
	port_input.value = 27015
	port_input.custom_minimum_size = Vector2(100, 40)
	port_container.add_child(port_input)

	# Buttons
	var btn_container := HBoxContainer.new()
	btn_container.add_theme_constant_override("separation", 10)
	vbox.add_child(btn_container)

	host_button = Button.new()
	host_button.text = "Host"
	host_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	host_button.custom_minimum_size = Vector2(0, 45)
	host_button.pressed.connect(_on_host_pressed)
	btn_container.add_child(host_button)

	join_button = Button.new()
	join_button.text = "Join"
	join_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	join_button.custom_minimum_size = Vector2(0, 45)
	join_button.pressed.connect(_on_join_pressed)
	btn_container.add_child(join_button)

	# Spacer
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(spacer)

	# Back
	back_from_direct_button = _create_menu_button("Back", Color(0.4, 0.4, 0.4))
	back_from_direct_button.pressed.connect(_on_back_from_direct_pressed)
	vbox.add_child(back_from_direct_button)


func _create_login_panel() -> void:
	login_panel = PanelContainer.new()
	login_panel.name = "LoginPanel"
	login_panel.set_anchors_preset(Control.PRESET_CENTER)
	login_panel.custom_minimum_size = Vector2(350, 200)
	login_panel.position = Vector2(-175, -50)
	login_panel.visible = false
	add_child(login_panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 20)
	margin.add_theme_constant_override("margin_right", 20)
	margin.add_theme_constant_override("margin_top", 20)
	margin.add_theme_constant_override("margin_bottom", 20)
	login_panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 15)
	margin.add_child(vbox)

	var title := Label.new()
	title.text = "Enter Your Name"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 22)
	vbox.add_child(title)

	username_input = LineEdit.new()
	username_input.placeholder_text = "Player Name"
	username_input.custom_minimum_size = Vector2(0, 45)
	username_input.text = "Player_%d" % (randi() % 9999)
	vbox.add_child(username_input)

	login_button = _create_menu_button("Continue", Color(0.2, 0.6, 0.3))
	login_button.pressed.connect(_on_login_pressed)
	vbox.add_child(login_button)


func _create_status_bar() -> void:
	# Player info (top right)
	player_info_label = Label.new()
	player_info_label.name = "PlayerInfo"
	player_info_label.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	player_info_label.position = Vector2(-250, 20)
	player_info_label.custom_minimum_size = Vector2(240, 30)
	player_info_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	player_info_label.add_theme_color_override("font_color", Color(0.6, 0.8, 0.6))
	add_child(player_info_label)

	# Status label (bottom center)
	status_label = Label.new()
	status_label.name = "StatusLabel"
	status_label.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	status_label.position = Vector2(-200, -60)
	status_label.custom_minimum_size = Vector2(400, 40)
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status_label.add_theme_font_size_override("font_size", 16)
	add_child(status_label)

	# Version (bottom left)
	version_label = Label.new()
	version_label.name = "Version"
	version_label.text = "v0.1.0 Alpha"
	version_label.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	version_label.position = Vector2(20, -40)
	version_label.add_theme_color_override("font_color", Color(0.4, 0.4, 0.4))
	add_child(version_label)


func _create_menu_button(text: String, color: Color) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.custom_minimum_size = Vector2(280, 50)

	# Style the button
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(8)
	style.set_content_margin_all(10)
	btn.add_theme_stylebox_override("normal", style)

	var hover := style.duplicate()
	hover.bg_color = color.lightened(0.2)
	btn.add_theme_stylebox_override("hover", hover)

	var pressed := style.duplicate()
	pressed.bg_color = color.darkened(0.2)
	btn.add_theme_stylebox_override("pressed", pressed)

	var disabled := style.duplicate()
	disabled.bg_color = Color(0.3, 0.3, 0.3)
	btn.add_theme_stylebox_override("disabled", disabled)

	btn.add_theme_font_size_override("font_size", 18)

	return btn


# ============================================
# PANEL SWITCHING
# ============================================

func _show_login() -> void:
	main_panel.visible = false
	play_panel.visible = false
	direct_connect_panel.visible = false
	login_panel.visible = true
	if settings_panel:
		settings_panel.visible = false
	player_info_label.visible = false


func _show_main_menu() -> void:
	main_panel.visible = true
	play_panel.visible = false
	direct_connect_panel.visible = false
	login_panel.visible = false
	if settings_panel:
		settings_panel.visible = false
	player_info_label.visible = true

	if FriendSystem:
		player_info_label.text = FriendSystem.local_player_name
	status_label.text = ""


func _show_play_menu() -> void:
	main_panel.visible = false
	play_panel.visible = true
	direct_connect_panel.visible = false
	login_panel.visible = false
	if settings_panel:
		settings_panel.visible = false
	status_label.text = ""


func _show_direct_connect() -> void:
	main_panel.visible = false
	play_panel.visible = false
	direct_connect_panel.visible = true
	login_panel.visible = false
	if settings_panel:
		settings_panel.visible = false
	status_label.text = ""


func _show_settings() -> void:
	main_panel.visible = false
	play_panel.visible = false
	direct_connect_panel.visible = false
	login_panel.visible = false
	settings_panel.visible = true
	status_label.text = ""


# ============================================
# BUTTON HANDLERS
# ============================================

func _on_login_pressed() -> void:
	var username := username_input.text.strip_edges()
	if username.is_empty():
		status_label.text = "Please enter a name"
		status_label.add_theme_color_override("font_color", Color.ORANGE)
		return

	status_label.text = "Logging in..."
	status_label.add_theme_color_override("font_color", Color.WHITE)
	login_button.disabled = true

	# Set player name in FriendSystem
	if FriendSystem:
		FriendSystem.local_player_name = username

	# Login to economy service
	if EconomyService:
		EconomyService.login(username)
	else:
		# No economy service, just proceed
		_complete_login(username)


func _on_economy_logged_in(_character_id: String, name: String) -> void:
	_complete_login(name)


func _on_economy_login_failed(error: String) -> void:
	# Even if economy login fails, allow playing
	status_label.text = "Warning: %s" % error
	status_label.add_theme_color_override("font_color", Color.ORANGE)
	login_button.disabled = false

	# Still allow proceeding
	var username := username_input.text.strip_edges()
	if username != "":
		_complete_login(username)


func _complete_login(username: String) -> void:
	is_logged_in = true
	if FriendSystem:
		player_id = FriendSystem.get_player_id()

	player_info_label.text = username
	_show_main_menu()


func _on_play_pressed() -> void:
	_show_play_menu()


func _on_stash_pressed() -> void:
	if not EconomyService or not EconomyService.is_logged_in:
		status_label.text = "Login required for stash access"
		status_label.add_theme_color_override("font_color", Color.ORANGE)
		return

	_open_menu_manager()


func _on_character_pressed() -> void:
	if not EconomyService or not EconomyService.is_logged_in:
		status_label.text = "Login required for character access"
		status_label.add_theme_color_override("font_color", Color.ORANGE)
		return

	_open_character_screen()


func _on_traders_pressed() -> void:
	if not EconomyService or not EconomyService.is_logged_in:
		status_label.text = "Login required for traders"
		status_label.add_theme_color_override("font_color", Color.ORANGE)
		return

	_open_traders_screen()


func _on_market_pressed() -> void:
	if not EconomyService or not EconomyService.is_logged_in:
		status_label.text = "Login required for market"
		status_label.add_theme_color_override("font_color", Color.ORANGE)
		return

	_open_market_screen()


func _on_settings_pressed() -> void:
	_show_settings()


func _on_quit_pressed() -> void:
	get_tree().quit()


func _on_back_to_main_pressed() -> void:
	_show_main_menu()


func _on_back_from_direct_pressed() -> void:
	_show_play_menu()


func _on_direct_connect_pressed() -> void:
	_show_direct_connect()


# ============================================
# PLAY MENU HANDLERS
# ============================================

func _on_quick_play_pressed() -> void:
	status_label.text = "Finding match..."
	status_label.add_theme_color_override("font_color", Color.WHITE)
	_disable_play_buttons()

	if GameManagerClient:
		GameManagerClient.quick_play(player_id, "survival")
	else:
		status_label.text = "Matchmaking not available"
		status_label.add_theme_color_override("font_color", Color.RED)
		_enable_play_buttons()


func _on_create_lobby_pressed() -> void:
	status_label.text = "Creating lobby..."
	status_label.add_theme_color_override("font_color", Color.WHITE)
	_disable_play_buttons()

	if LobbySystem and FriendSystem:
		var lobby_name := "%s's Game" % FriendSystem.local_player_name
		LobbySystem.create_lobby(lobby_name, 4, "survival")
	else:
		status_label.text = "Lobby system not available"
		status_label.add_theme_color_override("font_color", Color.RED)
		_enable_play_buttons()


func _on_join_lobby_pressed() -> void:
	var code := lobby_code_input.text.strip_edges().to_upper()
	if code.is_empty():
		status_label.text = "Enter a lobby code"
		status_label.add_theme_color_override("font_color", Color.ORANGE)
		return

	status_label.text = "Joining lobby..."
	status_label.add_theme_color_override("font_color", Color.WHITE)
	_disable_play_buttons()

	if LobbySystem:
		LobbySystem.join_lobby(code)
	else:
		status_label.text = "Lobby system not available"
		status_label.add_theme_color_override("font_color", Color.RED)
		_enable_play_buttons()


# ============================================
# DIRECT CONNECT HANDLERS
# ============================================

func _on_host_pressed() -> void:
	var port := int(port_input.value)

	status_label.text = "Starting server on port %d..." % port
	status_label.add_theme_color_override("font_color", Color.WHITE)
	_disable_direct_buttons()

	if NetworkManager:
		var error := NetworkManager.host_server(port)
		if error != OK:
			status_label.text = "Failed: %s" % error_string(error)
			status_label.add_theme_color_override("font_color", Color.RED)
			_enable_direct_buttons()
	else:
		status_label.text = "Network manager not available"
		status_label.add_theme_color_override("font_color", Color.RED)
		_enable_direct_buttons()


func _on_join_pressed() -> void:
	var address := address_input.text.strip_edges()
	var port := int(port_input.value)

	if address.is_empty():
		status_label.text = "Enter an IP address"
		status_label.add_theme_color_override("font_color", Color.ORANGE)
		return

	status_label.text = "Connecting to %s:%d..." % [address, port]
	status_label.add_theme_color_override("font_color", Color.WHITE)
	_disable_direct_buttons()

	if NetworkManager:
		var error := NetworkManager.join_server(address, port)
		if error != OK:
			status_label.text = "Failed: %s" % error_string(error)
			status_label.add_theme_color_override("font_color", Color.RED)
			_enable_direct_buttons()
	else:
		status_label.text = "Network manager not available"
		status_label.add_theme_color_override("font_color", Color.RED)
		_enable_direct_buttons()


# ============================================
# NETWORK CALLBACKS
# ============================================

func _on_server_started() -> void:
	status_label.text = "Server started! Loading game..."
	status_label.add_theme_color_override("font_color", Color.GREEN)
	_load_game()


func _on_client_connected() -> void:
	status_label.text = "Connected! Loading game..."
	status_label.add_theme_color_override("font_color", Color.GREEN)
	_load_game()


func _on_connection_failed() -> void:
	status_label.text = "Connection failed!"
	status_label.add_theme_color_override("font_color", Color.RED)
	_enable_direct_buttons()
	_enable_play_buttons()


func _on_match_found(server_info: Dictionary) -> void:
	var host: String = server_info.get("host", "127.0.0.1")
	var port: int = server_info.get("port", 27015)
	status_label.text = "Match found! Connecting..."
	status_label.add_theme_color_override("font_color", Color.GREEN)

	if NetworkManager:
		NetworkManager.join_server(host, port)


func _on_matchmaking_error(error_msg: String) -> void:
	status_label.text = "Matchmaking: %s" % error_msg
	status_label.add_theme_color_override("font_color", Color.RED)
	_enable_play_buttons()


func _on_lobby_created(_lobby_id: String) -> void:
	get_tree().change_scene_to_file("res://scenes/lobby.tscn")


func _on_lobby_joined(_lobby_data: Dictionary) -> void:
	get_tree().change_scene_to_file("res://scenes/lobby.tscn")


func _on_lobby_error(message: String) -> void:
	status_label.text = "Lobby: %s" % message
	status_label.add_theme_color_override("font_color", Color.RED)
	_enable_play_buttons()


# ============================================
# HELPERS
# ============================================

func _disable_play_buttons() -> void:
	if quick_play_button:
		quick_play_button.disabled = true
	if create_lobby_button:
		create_lobby_button.disabled = true
	if join_lobby_button:
		join_lobby_button.disabled = true
	if direct_connect_button:
		direct_connect_button.disabled = true


func _enable_play_buttons() -> void:
	if quick_play_button:
		quick_play_button.disabled = false
	if create_lobby_button:
		create_lobby_button.disabled = false
	if join_lobby_button:
		join_lobby_button.disabled = false
	if direct_connect_button:
		direct_connect_button.disabled = false


func _disable_direct_buttons() -> void:
	if host_button:
		host_button.disabled = true
	if join_button:
		join_button.disabled = true


func _enable_direct_buttons() -> void:
	if host_button:
		host_button.disabled = false
	if join_button:
		join_button.disabled = false


func _load_game() -> void:
	await get_tree().create_timer(0.5).timeout
	get_tree().change_scene_to_file("res://scenes/game_world.tscn")


## Check if running as dedicated server (headless mode)
func _is_dedicated_server() -> bool:
	var args := OS.get_cmdline_args()
	for arg in args:
		if arg == "--headless" or arg == "--server":
			return true
	return DisplayServer.get_name() == "headless"


# ============================================
# SETTINGS HANDLERS
# ============================================

const SETTINGS_PATH := "user://settings.cfg"

func _on_volume_changed(value: float, setting_name: String) -> void:
	# Update the value label
	var value_label := settings_panel.find_child(setting_name + "_value", true, false)
	if value_label:
		value_label.text = "%d%%" % int(value * 100)

	# Store temporarily (applied on "Apply")
	_pending_settings[setting_name] = value


func _on_sensitivity_changed(value: float, setting_name: String) -> void:
	var value_label := settings_panel.find_child(setting_name + "_value", true, false)
	if value_label:
		value_label.text = "%.1f" % value

	_pending_settings[setting_name] = value


func _on_toggle_changed(pressed: bool, setting_name: String) -> void:
	_pending_settings[setting_name] = pressed


var _pending_settings: Dictionary = {}


func _on_settings_apply_pressed() -> void:
	# Apply all pending settings
	for setting_name in _pending_settings:
		_apply_setting(setting_name, _pending_settings[setting_name])
		_save_setting(setting_name, _pending_settings[setting_name])

	_pending_settings.clear()

	status_label.text = "Settings applied"
	status_label.add_theme_color_override("font_color", Color.GREEN)


func _on_settings_reset_pressed() -> void:
	# Reset to defaults
	var defaults := {
		"master_volume": 1.0,
		"music_volume": 0.8,
		"sfx_volume": 1.0,
		"fullscreen": false,
		"vsync": true,
		"mouse_sensitivity": 0.5
	}

	for setting_name in defaults:
		var default_value = defaults[setting_name]
		_apply_setting(setting_name, default_value)
		_save_setting(setting_name, default_value)

		# Update UI controls
		var control := settings_panel.find_child(setting_name, true, false)
		if control is HSlider:
			control.value = default_value
		elif control is CheckButton:
			control.button_pressed = default_value

	_pending_settings.clear()

	status_label.text = "Settings reset to defaults"
	status_label.add_theme_color_override("font_color", Color.ORANGE)


func _on_settings_back_pressed() -> void:
	_pending_settings.clear()
	_show_main_menu()


func _apply_setting(setting_name: String, value: Variant) -> void:
	match setting_name:
		"master_volume":
			AudioServer.set_bus_volume_db(AudioServer.get_bus_index("Master"), linear_to_db(value))
		"music_volume":
			var idx := AudioServer.get_bus_index("Music")
			if idx >= 0:
				AudioServer.set_bus_volume_db(idx, linear_to_db(value))
		"sfx_volume":
			var idx := AudioServer.get_bus_index("SFX")
			if idx >= 0:
				AudioServer.set_bus_volume_db(idx, linear_to_db(value))
		"fullscreen":
			if value:
				DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
			else:
				DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		"vsync":
			DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if value else DisplayServer.VSYNC_DISABLED)
		"mouse_sensitivity":
			# Store sensitivity for player controller to access
			Engine.set_meta("mouse_sensitivity", value)


func _save_setting(setting_name: String, value: Variant) -> void:
	var config := ConfigFile.new()
	config.load(SETTINGS_PATH)
	config.set_value("settings", setting_name, value)
	config.save(SETTINGS_PATH)


func _load_setting(setting_name: String, default_value: Variant) -> Variant:
	var config := ConfigFile.new()
	if config.load(SETTINGS_PATH) == OK:
		return config.get_value("settings", setting_name, default_value)
	return default_value


func _apply_saved_settings() -> void:
	var config := ConfigFile.new()
	if config.load(SETTINGS_PATH) != OK:
		return

	# Apply all saved settings
	var settings := ["master_volume", "music_volume", "sfx_volume", "fullscreen", "vsync", "mouse_sensitivity"]
	var defaults := {
		"master_volume": 1.0,
		"music_volume": 0.8,
		"sfx_volume": 1.0,
		"fullscreen": false,
		"vsync": true,
		"mouse_sensitivity": 0.5
	}

	for setting_name in settings:
		var value = config.get_value("settings", setting_name, defaults.get(setting_name, 1.0))
		_apply_setting(setting_name, value)


# ============================================
# MENU MANAGER (Stash/Loadout/Traders/Market)
# ============================================

func _open_menu_manager() -> void:
	# Hide main menu panels
	if main_panel:
		main_panel.visible = false
	if play_panel:
		play_panel.visible = false

	# Create menu manager if doesn't exist
	if not menu_manager:
		var MenuManagerScript := preload("res://scripts/ui/menu_manager.gd")
		menu_manager = MenuManagerScript.new()
		menu_manager.set_anchors_preset(Control.PRESET_FULL_RECT)
		menu_manager.ready_for_game.connect(_on_loadout_ready)
		menu_manager.back_to_main_menu.connect(_on_menu_manager_closed)
		add_child(menu_manager)

	menu_manager.open()


func _on_menu_manager_closed() -> void:
	if menu_manager:
		menu_manager.visible = false

	# Show main menu again
	_show_main_menu()


func _on_loadout_ready(loadout: Dictionary) -> void:
	current_loadout = loadout
	print("[MainMenu] Loadout ready: %s" % loadout)

	# Store loadout for when game starts
	if menu_manager:
		menu_manager.visible = false

	status_label.text = "Loadout ready! Select a game mode to play"
	status_label.add_theme_color_override("font_color", Color.GREEN)
	_show_play_menu()


## Get the current loadout for spawning
func get_current_loadout() -> Dictionary:
	return current_loadout


# ============================================
# DIRECT SCREEN ACCESS
# ============================================

var character_screen: Control = null
var traders_screen_direct: Control = null
var market_screen_direct: Control = null


func _open_character_screen() -> void:
	# Hide main menu panels
	if main_panel:
		main_panel.visible = false
	if play_panel:
		play_panel.visible = false

	# Create character screen if doesn't exist
	if not character_screen:
		var CharacterScreenScript: GDScript = null
		if ResourceLoader.exists("res://scripts/ui/character/character_screen.gd"):
			CharacterScreenScript = preload("res://scripts/ui/character/character_screen.gd")

		if CharacterScreenScript:
			character_screen = CharacterScreenScript.new()
			character_screen.set_anchors_preset(Control.PRESET_FULL_RECT)
			if character_screen.has_signal("screen_closed"):
				character_screen.screen_closed.connect(_on_character_screen_closed)
			add_child(character_screen)
		else:
			status_label.text = "Character screen not yet implemented"
			status_label.add_theme_color_override("font_color", Color.ORANGE)
			_show_main_menu()
			return

	character_screen.visible = true
	if character_screen.has_method("open"):
		character_screen.open()


func _on_character_screen_closed() -> void:
	if character_screen:
		character_screen.visible = false
	_show_main_menu()


func _open_traders_screen() -> void:
	# Hide main menu panels
	if main_panel:
		main_panel.visible = false
	if play_panel:
		play_panel.visible = false

	# Use menu manager but go directly to traders
	if not menu_manager:
		var MenuManagerScript := preload("res://scripts/ui/menu_manager.gd")
		menu_manager = MenuManagerScript.new()
		menu_manager.set_anchors_preset(Control.PRESET_FULL_RECT)
		menu_manager.ready_for_game.connect(_on_loadout_ready)
		menu_manager.back_to_main_menu.connect(_on_menu_manager_closed)
		add_child(menu_manager)

	menu_manager.visible = true
	menu_manager.show_traders()


func _open_market_screen() -> void:
	# Hide main menu panels
	if main_panel:
		main_panel.visible = false
	if play_panel:
		play_panel.visible = false

	# Use menu manager but go directly to market
	if not menu_manager:
		var MenuManagerScript := preload("res://scripts/ui/menu_manager.gd")
		menu_manager = MenuManagerScript.new()
		menu_manager.set_anchors_preset(Control.PRESET_FULL_RECT)
		menu_manager.ready_for_game.connect(_on_loadout_ready)
		menu_manager.back_to_main_menu.connect(_on_menu_manager_closed)
		add_child(menu_manager)

	menu_manager.visible = true
	menu_manager.show_market()
