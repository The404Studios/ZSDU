extends Node3D
class_name Hammer
## Hammer - The tool for barricading
##
## JetBoom core mechanic:
## - Trace from player view
## - Validate prop + surface
## - Spawn constraint (nail)
## - Track nail HP
##
## Also used to repair nails.

# Hammer stats
@export var nail_damage_on_miss := 10.0  # Can swing at zombies
@export var nail_cooldown := 0.3
@export var repair_cooldown := 0.2
@export var max_reach := 4.0
@export var nails_per_swing := 1

# Current nail count (limited resource)
var nails_remaining: int = 50
var max_nails: int = 100

# State
var owner_player: PlayerController = null
var can_nail := true
var can_repair := true
var nail_timer := 0.0
var repair_timer := 0.0

# Preview ghost
var preview_position := Vector3.ZERO
var preview_normal := Vector3.ZERO
var preview_valid := false
var preview_prop: BarricadeProp = null
var preview_surface_id: int = -1  # -1 = world

# Visual references
@onready var hammer_mesh: MeshInstance3D = $HammerMesh if has_node("HammerMesh") else null
@onready var nail_preview: MeshInstance3D = $NailPreview if has_node("NailPreview") else null


func _ready() -> void:
	# Create preview mesh if not exists
	if not nail_preview:
		nail_preview = MeshInstance3D.new()
		nail_preview.name = "NailPreview"
		var cylinder := CylinderMesh.new()
		cylinder.top_radius = 0.02
		cylinder.bottom_radius = 0.03
		cylinder.height = 0.15
		nail_preview.mesh = cylinder
		nail_preview.visible = false
		add_child(nail_preview)


func _physics_process(delta: float) -> void:
	# Update cooldowns
	if not can_nail:
		nail_timer += delta
		if nail_timer >= nail_cooldown:
			can_nail = true
			nail_timer = 0.0

	if not can_repair:
		repair_timer += delta
		if repair_timer >= repair_cooldown:
			can_repair = true
			repair_timer = 0.0

	# Update preview (local player only)
	if owner_player and owner_player.is_local_player:
		_update_preview()


## Initialize with owner player
func initialize(player: PlayerController) -> void:
	owner_player = player


## Primary action - Place nail or swing
func primary_action() -> void:
	if not owner_player:
		return

	if not can_nail:
		return

	if nails_remaining <= 0:
		return

	# If we have a valid preview, place nail
	if preview_valid and preview_prop:
		_request_place_nail()
	else:
		# Swing at enemies
		_swing_attack()


## Secondary action - Repair nail
func secondary_action() -> void:
	if not owner_player:
		return

	if not can_repair:
		return

	_request_repair_nail()


## Update nail placement preview (client-side)
func _update_preview() -> void:
	preview_valid = false
	preview_prop = null
	preview_surface_id = -1

	if not owner_player:
		if nail_preview:
			nail_preview.visible = false
		return

	var camera := owner_player.get_camera()
	if not camera:
		if nail_preview:
			nail_preview.visible = false
		return

	# Raycast from camera
	var space_state := owner_player.get_world_3d().direct_space_state
	var from := camera.global_position
	var to := from - camera.global_basis.z * max_reach

	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.collision_mask = 0b00001001  # World + Props
	query.exclude = [owner_player]

	var result := space_state.intersect_ray(query)

	if not result:
		if nail_preview:
			nail_preview.visible = false
		return

	# Check what we hit
	var collider: Node = result.collider
	var hit_pos: Vector3 = result.position
	var hit_normal: Vector3 = result.normal

	# Did we hit a prop?
	if collider is BarricadeProp:
		preview_prop = collider as BarricadeProp

		# Check if prop can accept more nails
		if not preview_prop.can_accept_nail():
			if nail_preview:
				nail_preview.visible = false
			return

		# Check if prop is being held by another player
		if preview_prop.is_held():
			if nail_preview:
				nail_preview.visible = false
			return

		# Now we need to find what to nail it to
		# Second raycast through the prop
		var second_query := PhysicsRayQueryParameters3D.create(
			hit_pos + hit_normal * 0.1,
			hit_pos - hit_normal * 2.0
		)
		second_query.collision_mask = 0b00001001
		second_query.exclude = [owner_player, preview_prop]

		var second_result := space_state.intersect_ray(second_query)

		if second_result:
			var surface: Node = second_result.collider

			if surface is BarricadeProp:
				# Nail prop to prop
				preview_surface_id = surface.prop_id
			else:
				# Nail to world
				preview_surface_id = -1

			preview_position = hit_pos
			preview_normal = hit_normal
			preview_valid = true
		else:
			# Just nail to world at hit point
			preview_surface_id = -1
			preview_position = hit_pos
			preview_normal = hit_normal
			preview_valid = true
	else:
		# Hit world - look for nearby prop
		# Could implement "nail prop to wall" by finding nearest prop
		if nail_preview:
			nail_preview.visible = false
		return

	# Update preview visual
	if nail_preview and preview_valid:
		nail_preview.visible = true
		nail_preview.global_position = preview_position
		# Orient along normal
		var up := Vector3.UP
		if abs(preview_normal.dot(up)) > 0.99:
			up = Vector3.FORWARD
		nail_preview.look_at(preview_position + preview_normal, up)
		nail_preview.rotate_object_local(Vector3.RIGHT, PI/2)


## Request nail placement from server (client -> server)
func _request_place_nail() -> void:
	if not preview_valid or not preview_prop:
		return

	can_nail = false

	var action_data := {
		"prop_id": preview_prop.prop_id,
		"surface_id": preview_surface_id,
		"position": preview_position,
		"normal": preview_normal,
	}

	# Send request to server
	NetworkManager.request_action.rpc_id(1, "place_nail", action_data)

	# Optimistic: decrease local nail count
	nails_remaining -= 1


## Request nail repair from server
func _request_repair_nail() -> void:
	if not owner_player:
		return

	var camera := owner_player.get_camera()
	if not camera:
		return

	# Find nearest nail to crosshair
	var space_state := owner_player.get_world_3d().direct_space_state
	var from := camera.global_position
	var to := from - camera.global_basis.z * max_reach

	# Find nearest nail within reach
	var nearest_nail_id := -1
	var nearest_dist := max_reach

	for nail_id in GameState.nails:
		var nail: Dictionary = GameState.nails[nail_id]
		if not nail.get("active", false):
			continue

		var nail_pos: Vector3 = nail.get("position", Vector3.ZERO)
		var dist := from.distance_to(nail_pos)

		if dist < nearest_dist:
			# Check if nail is roughly in front of us
			var to_nail := (nail_pos - from).normalized()
			var forward := -camera.global_basis.z
			if to_nail.dot(forward) > 0.5:
				nearest_dist = dist
				nearest_nail_id = nail_id

	if nearest_nail_id >= 0:
		can_repair = false

		var action_data := {
			"nail_id": nearest_nail_id
		}

		NetworkManager.request_action.rpc_id(1, "repair_nail", action_data)


## Swing attack (when not nailing)
func _swing_attack() -> void:
	if not owner_player:
		return

	can_nail = false

	var camera := owner_player.get_camera()
	if not camera:
		return

	# Raycast for enemies
	var space_state := owner_player.get_world_3d().direct_space_state
	var from := camera.global_position
	var to := from - camera.global_basis.z * 2.0  # Short range melee

	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.collision_mask = 0b00000100  # Zombies only
	query.exclude = [owner_player]

	var result := space_state.intersect_ray(query)

	if result:
		# Send attack request
		var action_data := {
			"origin": from,
			"direction": -camera.global_basis.z,
			"damage": nail_damage_on_miss,
		}

		NetworkManager.request_action.rpc_id(1, "shoot", action_data)


## Add nails (from pickup, etc.)
func add_nails(count: int) -> void:
	nails_remaining = mini(nails_remaining + count, max_nails)


## Get nail count
func get_nail_count() -> int:
	return nails_remaining
