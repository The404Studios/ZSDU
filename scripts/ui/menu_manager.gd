extends Control
class_name MenuManager
## MenuManager - Coordinates navigation between stash, loadout, traders, and market screens
##
## Handles screen transitions and loadout submission to game.

signal ready_for_game(loadout: Dictionary)
signal back_to_main_menu

# Screen instances
var stash_screen: StashScreen = null
var loadout_screen: LoadoutScreen = null
var trader_screen: TraderScreen = null
var market_screen: MarketScreen = null

# Current screen
var current_screen: Control = null

# Preloaded scripts
var StashScreenScript := preload("res://scripts/ui/stash/stash_screen.gd")
var LoadoutScreenScript := preload("res://scripts/ui/loadout/loadout_screen.gd")
var TraderScreenScript := preload("res://scripts/ui/trader/trader_screen.gd")
var MarketScreenScript := preload("res://scripts/ui/market/market_screen.gd")


func _ready() -> void:
	_create_screens()
	_connect_signals()


func _create_screens() -> void:
	# Create all screens (hidden initially)
	stash_screen = _load_or_create_stash_screen()
	stash_screen.visible = false
	add_child(stash_screen)

	loadout_screen = LoadoutScreenScript.new()
	loadout_screen.visible = false
	add_child(loadout_screen)

	trader_screen = TraderScreenScript.new()
	trader_screen.visible = false
	add_child(trader_screen)

	market_screen = MarketScreenScript.new()
	market_screen.visible = false
	add_child(market_screen)


func _load_or_create_stash_screen() -> StashScreen:
	# Try to load from scene first
	var scene_path := "res://scenes/ui/stash_screen.tscn"
	if ResourceLoader.exists(scene_path):
		var scene := load(scene_path)
		if scene:
			return scene.instantiate() as StashScreen

	# Fallback to script-only creation
	var screen := StashScreenScript.new()
	screen.set_anchors_preset(Control.PRESET_FULL_RECT)
	return screen


func _connect_signals() -> void:
	# Stash screen navigation
	stash_screen.navigate_to_loadout.connect(show_loadout)
	stash_screen.navigate_to_traders.connect(show_traders)
	stash_screen.navigate_to_market.connect(show_market)
	stash_screen.screen_closed.connect(_on_screen_closed)

	# Loadout screen navigation
	loadout_screen.navigate_to_stash.connect(show_stash)
	loadout_screen.ready_for_raid.connect(_on_ready_for_raid)
	loadout_screen.screen_closed.connect(_on_screen_closed)

	# Trader screen navigation
	trader_screen.navigate_to_stash.connect(show_stash)
	trader_screen.navigate_to_market.connect(show_market)
	trader_screen.screen_closed.connect(_on_screen_closed)

	# Market screen navigation
	market_screen.navigate_to_stash.connect(show_stash)
	market_screen.navigate_to_traders.connect(show_traders)
	market_screen.screen_closed.connect(_on_screen_closed)


func open() -> void:
	visible = true
	show_stash()


func close() -> void:
	_hide_all_screens()
	visible = false
	back_to_main_menu.emit()


func show_stash() -> void:
	_switch_screen(stash_screen)
	stash_screen.open()


func show_loadout() -> void:
	_switch_screen(loadout_screen)
	loadout_screen.open()


func show_traders() -> void:
	_switch_screen(trader_screen)
	trader_screen.open()


func show_market() -> void:
	_switch_screen(market_screen)
	market_screen.open()


func _switch_screen(screen: Control) -> void:
	_hide_all_screens()
	screen.visible = true
	current_screen = screen


func _hide_all_screens() -> void:
	if stash_screen:
		stash_screen.visible = false
	if loadout_screen:
		loadout_screen.visible = false
	if trader_screen:
		trader_screen.visible = false
	if market_screen:
		market_screen.visible = false


func _on_screen_closed() -> void:
	close()


func _on_ready_for_raid(loadout: Dictionary) -> void:
	print("[MenuManager] Ready for raid with loadout: %s" % loadout)
	ready_for_game.emit(loadout)


func get_current_loadout() -> Dictionary:
	if loadout_screen:
		return loadout_screen.get_loadout()
	return {}
