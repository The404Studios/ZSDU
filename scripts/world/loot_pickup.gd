extends Area3D
class_name LootPickup
## LootPickup - World item that players can pick up
##
## Spawned by:
## - Zombie death drops
## - Container searches
## - World spawns
##
## Players interact to pick up, loot goes to RaidManager as provisional

signal picked_up(peer_id: int)

# Loot data
var def_id: String = ""
var stack: int = 1
var durability: float = 1.0
var mods: Array = []
var loot_id: int = -1

# Visual
var mesh_instance: MeshInstance3D = null
var collision_shape: CollisionShape3D = null
var label_3d: Label3D = null

# Pickup state
var is_picked_up: bool = false
var pickup_cooldown: float = 0.0

# Rarity colors for visual feedback
const RARITY_COLORS := {
	"common": Color(0.6, 0.6, 0.6),
	"uncommon": Color(0.3, 0.8, 0.3),
	"rare": Color(0.3, 0.5, 1.0),
	"epic": Color(0.7, 0.3, 0.9),
	"legendary": Color(1.0, 0.8, 0.2),
}


func _ready() -> void:
	# Setup collision
	collision_layer = 0
	collision_mask = 0b00000010  # Player layer

	# Connect signals
	body_entered.connect(_on_body_entered)

	# Create visual mesh
	_create_visuals()


func _create_visuals() -> void:
	# Collision shape (sphere)
	collision_shape = CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 0.5
	collision_shape.shape = sphere
	add_child(collision_shape)

	# Visual mesh (small box/cube representing the item)
	mesh_instance = MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.3, 0.3, 0.3)
	mesh_instance.mesh = box
	mesh_instance.position = Vector3(0, 0.2, 0)
	add_child(mesh_instance)

	# Add slight floating animation
	var tween := create_tween()
	tween.set_loops()
	tween.tween_property(mesh_instance, "position:y", 0.35, 1.0).set_trans(Tween.TRANS_SINE)
	tween.tween_property(mesh_instance, "position:y", 0.2, 1.0).set_trans(Tween.TRANS_SINE)

	# Rotation animation
	var rot_tween := create_tween()
	rot_tween.set_loops()
	rot_tween.tween_property(mesh_instance, "rotation:y", TAU, 4.0).from(0.0)


func _process(delta: float) -> void:
	if pickup_cooldown > 0:
		pickup_cooldown -= delta


## Initialize with loot data
func setup(p_def_id: String, p_stack: int = 1, p_durability: float = 1.0, p_mods: Array = []) -> void:
	def_id = p_def_id
	stack = p_stack
	durability = p_durability
	mods = p_mods

	_update_visuals()


## Update visuals based on item type
func _update_visuals() -> void:
	if not mesh_instance:
		return

	# Get item definition if available
	var rarity := "common"
	var item_name := def_id

	# Try to get item info from EconomyService
	if EconomyService and EconomyService.has_method("get_item_def"):
		var item_def: Dictionary = EconomyService.get_item_def(def_id)
		if not item_def.is_empty():
			rarity = item_def.get("rarity", "common")
			item_name = item_def.get("name", def_id)

	# Set color based on rarity
	var color: Color = RARITY_COLORS.get(rarity, RARITY_COLORS.common)

	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = 0.5
	mesh_instance.material_override = material

	# Add floating label
	if not label_3d:
		label_3d = Label3D.new()
		label_3d.position = Vector3(0, 0.6, 0)
		label_3d.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label_3d.font_size = 24
		label_3d.outline_size = 4
		label_3d.modulate = color
		add_child(label_3d)

	# Update label
	if stack > 1:
		label_3d.text = "%s x%d" % [item_name, stack]
	else:
		label_3d.text = item_name


func _on_body_entered(body: Node3D) -> void:
	if is_picked_up:
		return

	if pickup_cooldown > 0:
		return

	# Check if it's a player
	if body is PlayerController:
		var player := body as PlayerController
		_pickup(player)


## Handle pickup by player
func _pickup(player: PlayerController) -> void:
	if is_picked_up:
		return

	if not NetworkManager.is_authority():
		# Client can't directly pick up, request from server
		_request_pickup.rpc_id(1)
		return

	_server_pickup(player.peer_id)


## Server-side pickup processing
func _server_pickup(peer_id: int) -> void:
	if is_picked_up:
		return

	is_picked_up = true

	# Add to player's provisional loot
	if RaidManager:
		RaidManager.add_provisional_loot(peer_id, def_id, stack, durability, mods)

	# Emit signal
	picked_up.emit(peer_id)

	# Notify all clients
	_sync_pickup.rpc(peer_id)

	# Remove from EntityRegistry (handles queue_free internally)
	if EntityRegistry:
		EntityRegistry.remove_loot(loot_id)
	else:
		queue_free()


## Client requests pickup
@rpc("any_peer", "reliable")
func _request_pickup() -> void:
	if not NetworkManager.is_authority():
		return

	var sender := multiplayer.get_remote_sender_id()

	# Verify sender is close enough
	if GameState and sender in GameState.players:
		var player: Node3D = GameState.players[sender]
		if is_instance_valid(player):
			var dist := global_position.distance_to(player.global_position)
			if dist < 3.0:
				_server_pickup(sender)


## Sync pickup to clients
@rpc("authority", "call_local", "reliable")
func _sync_pickup(_peer_id: int) -> void:
	is_picked_up = true
	# Visual feedback
	if mesh_instance:
		var tween := create_tween()
		tween.tween_property(mesh_instance, "scale", Vector3.ZERO, 0.2)
		tween.tween_callback(queue_free)


## Get network state
func get_network_state() -> Dictionary:
	return {
		"pos": global_position,
		"def_id": def_id,
		"stack": stack,
		"durability": durability,
		"picked_up": is_picked_up
	}


## Apply network state
func apply_network_state(state: Dictionary) -> void:
	global_position = state.get("pos", global_position)
	if not is_picked_up:
		is_picked_up = state.get("picked_up", false)
		if is_picked_up:
			queue_free()
