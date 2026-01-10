extends Area3D
class_name ExtractionZone
## ExtractionZone - Player extraction point
##
## Players can extract here once extraction is unlocked (wave 5+).
## Stand in zone for extraction_time seconds to extract.
## Extraction is interrupted if damaged or zone is exited.

signal extraction_started(peer_id: int)
signal extraction_progress(peer_id: int, progress: float)
signal extraction_complete(peer_id: int)
signal extraction_cancelled(peer_id: int)

@export var extraction_time := 5.0  # Seconds to extract
@export var zone_name := "Extraction Point"
@export var enabled := false  # Starts disabled, enabled when extraction unlocks

# Visual
@export var active_color := Color(0.2, 0.8, 0.2, 0.5)  # Green when active
@export var inactive_color := Color(0.5, 0.5, 0.5, 0.3)  # Gray when inactive

# State
var players_in_zone: Dictionary = {}  # peer_id -> extraction_timer
var extraction_mesh: MeshInstance3D = null


func _ready() -> void:
	# Connect area signals
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)

	# Create visual indicator
	_create_visual()

	# Connect to GameState extraction signal
	if GameState:
		GameState.extraction_available.connect(_on_extraction_unlocked)

	# Add to group for easy finding
	add_to_group("extraction_zones")

	# Set initial visual state
	_update_visual()


func _physics_process(delta: float) -> void:
	if not enabled:
		return

	if not NetworkManager.is_authority():
		return

	# Update extraction progress for each player in zone
	for peer_id in players_in_zone.keys():
		var player: Node3D = GameState.players.get(peer_id)

		# Check player is still valid and alive
		if not is_instance_valid(player):
			players_in_zone.erase(peer_id)
			continue

		var is_dead: bool = player.is_dead if "is_dead" in player else false
		if is_dead:
			_cancel_extraction(peer_id, "Player died")
			continue

		# Increment timer
		players_in_zone[peer_id] += delta
		var progress: float = players_in_zone[peer_id] / extraction_time

		extraction_progress.emit(peer_id, progress)

		# Check if extraction complete
		if players_in_zone[peer_id] >= extraction_time:
			_complete_extraction(peer_id)


## Create visual representation of extraction zone
func _create_visual() -> void:
	# Create cylinder mesh for zone indicator
	extraction_mesh = MeshInstance3D.new()
	extraction_mesh.name = "ZoneVisual"

	var cylinder := CylinderMesh.new()
	cylinder.top_radius = 2.0
	cylinder.bottom_radius = 2.0
	cylinder.height = 0.1
	extraction_mesh.mesh = cylinder

	# Create material
	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = inactive_color
	material.emission_enabled = true
	material.emission = inactive_color
	material.emission_energy_multiplier = 0.5
	extraction_mesh.material_override = material

	add_child(extraction_mesh)


## Update visual based on enabled state
func _update_visual() -> void:
	if not extraction_mesh:
		return

	var material := extraction_mesh.material_override as StandardMaterial3D
	if material:
		material.albedo_color = active_color if enabled else inactive_color
		material.emission = active_color if enabled else inactive_color


## Called when extraction is unlocked globally
func _on_extraction_unlocked() -> void:
	enabled = true
	_update_visual()
	print("[ExtractionZone] %s is now active!" % zone_name)


## Called when player enters zone
func _on_body_entered(body: Node3D) -> void:
	if not body is CharacterBody3D:
		return

	if not body.is_in_group("players"):
		# Check if it's a PlayerController
		if not body is PlayerController:
			return

	var peer_id: int = body.get("peer_id") if body else -1
	if peer_id <= 0:
		return

	# Only track if extraction is enabled
	if not enabled:
		return

	# Start extraction timer
	players_in_zone[peer_id] = 0.0
	extraction_started.emit(peer_id)

	print("[ExtractionZone] Player %d entered %s" % [peer_id, zone_name])

	# Notify clients
	if NetworkManager.is_authority():
		NetworkManager.broadcast_event.rpc("extraction_started", {
			"peer_id": peer_id,
			"zone": zone_name,
			"time": extraction_time,
		})


## Called when player exits zone
func _on_body_exited(body: Node3D) -> void:
	if not body is CharacterBody3D:
		return

	var peer_id: int = body.get("peer_id") if body else -1
	if peer_id <= 0:
		return

	if peer_id in players_in_zone:
		_cancel_extraction(peer_id, "Left extraction zone")


## Cancel extraction
func _cancel_extraction(peer_id: int, reason: String) -> void:
	if peer_id in players_in_zone:
		players_in_zone.erase(peer_id)
		extraction_cancelled.emit(peer_id)

		print("[ExtractionZone] Player %d extraction cancelled: %s" % [peer_id, reason])

		# Notify clients
		if NetworkManager.is_authority():
			NetworkManager.broadcast_event.rpc("extraction_cancelled", {
				"peer_id": peer_id,
				"reason": reason,
			})


## Complete extraction
func _complete_extraction(peer_id: int) -> void:
	if peer_id not in players_in_zone:
		return

	players_in_zone.erase(peer_id)
	extraction_complete.emit(peer_id)

	print("[ExtractionZone] Player %d extraction complete!" % peer_id)

	# Tell GameState to extract the player
	if NetworkManager.is_authority():
		GameState.extract_player(peer_id)


## Manually enable zone (for testing or custom triggers)
func enable_zone() -> void:
	enabled = true
	_update_visual()


## Manually disable zone
func disable_zone() -> void:
	enabled = false
	_update_visual()

	# Cancel all active extractions
	for peer_id in players_in_zone.keys():
		_cancel_extraction(peer_id, "Zone disabled")
