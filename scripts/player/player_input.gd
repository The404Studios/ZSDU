extends RefCounted
class_name PlayerInput
## PlayerInput - Input packet structure
##
## Immutable input snapshot sent from client to server.
## This is deterministic - same input = same result.

var sequence: int = 0
var tick: int = 0

# Movement
var move_dir: Vector3 = Vector3.ZERO  # World-space direction
var look_yaw: float = 0.0
var look_pitch: float = 0.0

# Movement actions
var jump: bool = false
var sprint: bool = false
var crouch: bool = false
var prone: bool = false

# Combat actions
var fire: bool = false
var ads: bool = false
var reload: bool = false

# Interaction
var interact: bool = false
var drop: bool = false

# Weapon slots
var weapon_slot: int = -1  # -1 = no change


func to_dict() -> Dictionary:
	return {
		"seq": sequence,
		"tick": tick,
		"move": [move_dir.x, move_dir.z],
		"yaw": look_yaw,
		"pitch": look_pitch,
		"jump": jump,
		"sprint": sprint,
		"crouch": crouch,
		"prone": prone,
		"fire": fire,
		"ads": ads,
		"reload": reload,
		"interact": interact,
		"drop": drop,
		"slot": weapon_slot,
	}


static func from_dict(data: Dictionary) -> PlayerInput:
	var input := PlayerInput.new()
	input.sequence = data.get("seq", 0)
	input.tick = data.get("tick", 0)

	var move: Array = data.get("move", [0.0, 0.0])
	input.move_dir = Vector3(move[0], 0, move[1])

	input.look_yaw = data.get("yaw", 0.0)
	input.look_pitch = data.get("pitch", 0.0)
	input.jump = data.get("jump", false)
	input.sprint = data.get("sprint", false)
	input.crouch = data.get("crouch", false)
	input.prone = data.get("prone", false)
	input.fire = data.get("fire", false)
	input.ads = data.get("ads", false)
	input.reload = data.get("reload", false)
	input.interact = data.get("interact", false)
	input.drop = data.get("drop", false)
	input.weapon_slot = data.get("slot", -1)
	return input


## Create from local input actions (client-side)
static func gather_local(look_yaw: float, look_pitch: float, seq: int = 0) -> PlayerInput:
	var input := PlayerInput.new()
	input.sequence = seq
	input.tick = Engine.get_physics_frames()

	# Movement direction (local space)
	var dir := Vector2.ZERO
	if Input.is_action_pressed("move_forward"):
		dir.y -= 1
	if Input.is_action_pressed("move_backward"):
		dir.y += 1
	if Input.is_action_pressed("move_left"):
		dir.x -= 1
	if Input.is_action_pressed("move_right"):
		dir.x += 1

	dir = dir.normalized()

	# Transform to world space
	var local_dir := Vector3(dir.x, 0, dir.y)
	input.move_dir = local_dir.rotated(Vector3.UP, look_yaw)

	input.look_yaw = look_yaw
	input.look_pitch = look_pitch

	input.jump = Input.is_action_just_pressed("jump")
	input.sprint = Input.is_action_pressed("sprint")
	input.crouch = Input.is_action_just_pressed("crouch") if InputMap.has_action("crouch") else false
	input.prone = Input.is_action_just_pressed("prone") if InputMap.has_action("prone") else false

	input.fire = Input.is_action_pressed("primary_action")
	input.ads = Input.is_action_pressed("secondary_action")
	input.reload = Input.is_action_just_pressed("reload")
	input.interact = Input.is_action_just_pressed("interact")
	input.drop = Input.is_action_just_pressed("drop") if InputMap.has_action("drop") else false

	# Weapon slots
	if Input.is_action_just_pressed("slot_1"):
		input.weapon_slot = 0
	elif Input.is_action_just_pressed("slot_2"):
		input.weapon_slot = 1
	elif Input.is_action_just_pressed("slot_3"):
		input.weapon_slot = 2

	return input
