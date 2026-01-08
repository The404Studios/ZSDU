extends Control
## GameHUD - In-game UI display
##
## Shows health, nails, wave info, etc.
## Updates from local player state and game state.

@onready var wave_label: Label = $TopBar/WaveLabel
@onready var zombies_label: Label = $TopBar/ZombiesLabel
@onready var health_label: Label = $BottomBar/HealthLabel
@onready var nails_label: Label = $BottomBar/NailsLabel

# Local player reference
var local_player: PlayerController = null


func _ready() -> void:
	# Connect to game state signals
	GameState.wave_started.connect(_on_wave_started)
	GameState.wave_ended.connect(_on_wave_ended)
	GameState.player_spawned.connect(_on_player_spawned)

	# Initial state
	_update_wave_display(0, 0)


func _process(_delta: float) -> void:
	_update_player_stats()
	_update_zombie_count()


func _on_player_spawned(peer_id: int, player: Node3D) -> void:
	# Check if this is our local player
	if peer_id == NetworkManager.local_peer_id:
		local_player = player as PlayerController


func _on_wave_started(wave_number: int) -> void:
	if wave_label:
		wave_label.text = "Wave: %d" % wave_number


func _on_wave_ended(_wave_number: int) -> void:
	if wave_label:
		wave_label.text += " (Complete!)"


func _update_wave_display(wave: int, zombies: int) -> void:
	if wave_label:
		wave_label.text = "Wave: %d" % wave
	if zombies_label:
		zombies_label.text = "Zombies: %d" % zombies


func _update_player_stats() -> void:
	if not local_player or not is_instance_valid(local_player):
		# Try to find local player
		for peer_id in GameState.players:
			if peer_id == NetworkManager.local_peer_id:
				local_player = GameState.players[peer_id] as PlayerController
				break
		return

	# Update health
	if health_label:
		var health: float = local_player.health
		health_label.text = "Health: %d" % int(health)

	# Update nails
	if nails_label:
		var hammer := _get_player_hammer()
		if hammer:
			nails_label.text = "Nails: %d" % hammer.get_nail_count()


func _update_zombie_count() -> void:
	if zombies_label:
		var zombie_count := GameState.zombies.size()
		zombies_label.text = "Zombies: %d" % zombie_count


func _get_player_hammer() -> Hammer:
	if not local_player:
		return null

	for item in local_player.inventory:
		if item is Hammer:
			return item

	return null
