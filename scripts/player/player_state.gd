extends RefCounted
class_name PlayerState
## PlayerState - Simple replicated state container
##
## Pure data class. No logic. No side effects.
## This is what gets serialized over the network.

# Identity
var peer_id: int = 0
var character_id: String = ""

# Transform
var position: Vector3 = Vector3.ZERO
var velocity: Vector3 = Vector3.ZERO
var rotation_y: float = 0.0
var pitch: float = 0.0

# Health
var health: float = 100.0
var max_health: float = 100.0
var is_dead: bool = false

# Movement state
var posture: int = Posture.STAND  # stand, crouch, prone
var is_sprinting: bool = false
var stamina: float = 100.0

# Combat state
var is_ads: bool = false
var is_reloading: bool = false
var weapon_state: Dictionary = {}

# Animation
var anim_state: String = "idle"

# Network
var input_sequence: int = 0
var server_tick: int = 0


enum Posture {
	STAND = 0,
	CROUCH = 1,
	PRONE = 2
}


func to_dict() -> Dictionary:
	return {
		"pos": position,
		"vel": velocity,
		"rot": rotation_y,
		"pitch": pitch,
		"health": health,
		"dead": is_dead,
		"posture": posture,
		"sprint": is_sprinting,
		"stamina": stamina,
		"ads": is_ads,
		"reload": is_reloading,
		"anim": anim_state,
		"seq": input_sequence,
		"tick": server_tick,
		"weapon": weapon_state,
	}


func from_dict(data: Dictionary) -> void:
	position = data.get("pos", position)
	velocity = data.get("vel", velocity)
	rotation_y = data.get("rot", rotation_y)
	pitch = data.get("pitch", pitch)
	health = data.get("health", health)
	is_dead = data.get("dead", is_dead)
	posture = data.get("posture", posture)
	is_sprinting = data.get("sprint", is_sprinting)
	stamina = data.get("stamina", stamina)
	is_ads = data.get("ads", is_ads)
	is_reloading = data.get("reload", is_reloading)
	anim_state = data.get("anim", anim_state)
	input_sequence = data.get("seq", input_sequence)
	server_tick = data.get("tick", server_tick)
	weapon_state = data.get("weapon", weapon_state)


func clone() -> PlayerState:
	var copy := PlayerState.new()
	copy.peer_id = peer_id
	copy.character_id = character_id
	copy.position = position
	copy.velocity = velocity
	copy.rotation_y = rotation_y
	copy.pitch = pitch
	copy.health = health
	copy.max_health = max_health
	copy.is_dead = is_dead
	copy.posture = posture
	copy.is_sprinting = is_sprinting
	copy.stamina = stamina
	copy.is_ads = is_ads
	copy.is_reloading = is_reloading
	copy.weapon_state = weapon_state.duplicate()
	copy.anim_state = anim_state
	copy.input_sequence = input_sequence
	copy.server_tick = server_tick
	return copy
