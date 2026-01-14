extends Node3D
class_name Sigil
## Sigil - The defense objective
##
## Zombies target the sigil. If they reach it, bad things happen.
## Sigil provides passive bonuses and can have active abilities.

signal sigil_damaged(damage: float, current_health: float)
signal sigil_corrupted()  # Zombie reached sigil
signal sigil_destroyed()  # Health depleted

# Configuration
@export var max_health := 1000.0
@export var corruption_damage := 50.0  # Damage when zombie reaches sigil
@export var pulse_cooldown := 30.0  # Seconds between active pulses
@export var pulse_radius := 5.0
@export var pulse_knockback := 10.0

# Passive aura effects
@export var aura_radius := 15.0
@export var barricade_regen_bonus := 0.01  # % per second for barricades in range
@export var zombie_slow_factor := 0.8  # Zombies move at 80% speed in aura

# State
var health: float = 1000.0
var pulse_timer: float = 0.0
var pulse_ready := true
var total_corruption := 0  # Times zombies reached sigil

# Visual references
@onready var mesh: MeshInstance3D = $MeshInstance3D if has_node("MeshInstance3D") else null
@onready var aura_particles: GPUParticles3D = $AuraParticles if has_node("AuraParticles") else null


func _ready() -> void:
	health = max_health
	add_to_group("sigil")

	# Create collision area for zombie detection
	_setup_trigger_area()


func _physics_process(delta: float) -> void:
	if not NetworkManager.is_authority():
		return

	# Update pulse cooldown
	if not pulse_ready:
		pulse_timer += delta
		if pulse_timer >= pulse_cooldown:
			pulse_timer = 0.0
			pulse_ready = true


func _setup_trigger_area() -> void:
	# Create area to detect zombies reaching sigil
	var area := Area3D.new()
	area.name = "SigilTrigger"

	var collision := CollisionShape3D.new()
	var shape := SphereShape3D.new()
	shape.radius = 2.0  # Zombie must get this close
	collision.shape = shape
	area.add_child(collision)

	area.collision_layer = 0
	area.collision_mask = 0b00000100  # Zombies layer
	area.body_entered.connect(_on_body_entered)

	add_child(area)


func _on_body_entered(body: Node3D) -> void:
	if not NetworkManager.is_authority():
		return

	if body.is_in_group("zombies"):
		_on_zombie_reached_sigil(body)


## Called when a zombie reaches the sigil
func _on_zombie_reached_sigil(zombie: Node3D) -> void:
	total_corruption += 1
	take_damage(corruption_damage)

	print("[Sigil] Zombie reached sigil! Corruption: %d, Health: %.0f" % [total_corruption, health])

	sigil_corrupted.emit()

	# Kill the zombie that reached (they sacrifice themselves)
	if zombie.has_method("take_damage"):
		zombie.take_damage(9999, global_position)


## Take damage (from zombies reaching or special attacks)
func take_damage(amount: float) -> void:
	if not NetworkManager.is_authority():
		return

	health -= amount
	health = maxf(health, 0)

	sigil_damaged.emit(amount, health)

	if health <= 0:
		_on_sigil_destroyed()


## Heal the sigil
func heal(amount: float) -> void:
	if not NetworkManager.is_authority():
		return

	health = minf(health + amount, max_health)


## Activate pulse ability (knockback zombies)
func activate_pulse() -> void:
	if not NetworkManager.is_authority():
		return

	if not pulse_ready:
		return

	pulse_ready = false
	pulse_timer = 0.0

	# Find zombies in range and knock them back
	var zombies_hit := 0
	for zombie_id in GameState.zombies:
		var zombie: Node3D = GameState.zombies[zombie_id]
		if not is_instance_valid(zombie):
			continue

		var dist := global_position.distance_to(zombie.global_position)
		if dist <= pulse_radius:
			# Apply knockback
			var direction := zombie.global_position - global_position
			direction.y = 0
			direction = direction.normalized()

			if zombie is CharacterBody3D:
				zombie.velocity += direction * pulse_knockback + Vector3.UP * 3
			elif zombie is RigidBody3D:
				zombie.apply_impulse(direction * pulse_knockback * 10)

			zombies_hit += 1

	print("[Sigil] Pulse activated! Hit %d zombies" % zombies_hit)


func _on_sigil_destroyed() -> void:
	print("[Sigil] DESTROYED! Game Over")
	sigil_destroyed.emit()

	# Trigger game over
	if GameState:
		GameState._trigger_game_over("Sigil destroyed!")


## Check if position is in aura range
func is_in_aura(position: Vector3) -> bool:
	return global_position.distance_to(position) <= aura_radius


## Get zombie slow factor (for zombies in aura)
func get_zombie_slow() -> float:
	return zombie_slow_factor


## Get health percentage
func get_health_percent() -> float:
	return health / max_health


## Get network state for snapshot
func get_network_state() -> Dictionary:
	return {
		"health": health,
		"pulse_ready": pulse_ready,
		"corruption": total_corruption
	}


## Apply network state (client-side)
func apply_network_state(state: Dictionary) -> void:
	health = state.get("health", health)
	pulse_ready = state.get("pulse_ready", pulse_ready)
	total_corruption = state.get("corruption", total_corruption)
