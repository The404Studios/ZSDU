extends Node
class_name AnimationController
## AnimationController - The spine of correctness
##
## Handles:
## - Own AnimationTree / AnimationPlayer
## - Translate state → animation
## - Emit events (reload, fire, chamber)
## - Keep visuals in sync with logic
##
## Animation controls WHEN.
## Systems control WHAT.

signal anim_event(event_name: String)
signal animation_finished(anim_name: String)

# Animation state machine states
enum AnimState {
	IDLE,
	WALK,
	SPRINT,
	CROUCH_IDLE,
	CROUCH_WALK,
	PRONE_IDLE,
	PRONE_CRAWL,
	JUMP,
	FALL,
	FIRE,
	RELOAD,
	EQUIP,
	ADS_ENTER,
	ADS_IDLE,
	ADS_EXIT,
	MELEE,
	INTERACT,
	DEAD,
}

# Current state
var current_state: AnimState = AnimState.IDLE
var is_ads := false
var is_reloading := false

# References
var animation_player: AnimationPlayer = null
var animation_tree: AnimationTree = null

# Animation name mappings
var state_to_anim := {
	AnimState.IDLE: "idle",
	AnimState.WALK: "walk",
	AnimState.SPRINT: "sprint",
	AnimState.CROUCH_IDLE: "crouch_idle",
	AnimState.CROUCH_WALK: "crouch_walk",
	AnimState.PRONE_IDLE: "prone_idle",
	AnimState.PRONE_CRAWL: "prone_crawl",
	AnimState.JUMP: "jump",
	AnimState.FALL: "fall",
	AnimState.FIRE: "fire",
	AnimState.RELOAD: "reload",
	AnimState.EQUIP: "equip",
	AnimState.ADS_ENTER: "ads_enter",
	AnimState.ADS_IDLE: "ads_idle",
	AnimState.ADS_EXIT: "ads_exit",
	AnimState.MELEE: "melee",
	AnimState.INTERACT: "interact",
	AnimState.DEAD: "dead",
}


func initialize(p_animation_player: AnimationPlayer, p_animation_tree: AnimationTree = null) -> void:
	animation_player = p_animation_player
	animation_tree = p_animation_tree

	if animation_player:
		animation_player.animation_finished.connect(_on_animation_finished)

	# If using AnimationTree, configure state machine
	if animation_tree:
		_setup_animation_tree()


func _setup_animation_tree() -> void:
	# Configure blend tree / state machine parameters
	# This would be customized based on your actual animation setup
	pass


## Update animation based on movement state
func update_from_movement(velocity: Vector3, posture: int, is_grounded: bool, is_sprinting: bool) -> void:
	if is_reloading:
		return  # Don't interrupt reload

	var speed := Vector2(velocity.x, velocity.z).length()
	var moving := speed > 0.5

	match posture:
		PlayerState.Posture.STAND:
			if not is_grounded:
				if velocity.y > 0:
					_transition_to(AnimState.JUMP)
				else:
					_transition_to(AnimState.FALL)
			elif is_sprinting and moving:
				_transition_to(AnimState.SPRINT)
			elif moving:
				if is_ads:
					_transition_to(AnimState.ADS_IDLE)
				else:
					_transition_to(AnimState.WALK)
			else:
				if is_ads:
					_transition_to(AnimState.ADS_IDLE)
				else:
					_transition_to(AnimState.IDLE)

		PlayerState.Posture.CROUCH:
			if moving:
				_transition_to(AnimState.CROUCH_WALK)
			else:
				_transition_to(AnimState.CROUCH_IDLE)

		PlayerState.Posture.PRONE:
			if moving:
				_transition_to(AnimState.PRONE_CRAWL)
			else:
				_transition_to(AnimState.PRONE_IDLE)


## Play fire animation
func play_fire() -> void:
	_play_one_shot(AnimState.FIRE)


## Play reload animation
func play_reload() -> void:
	is_reloading = true
	_transition_to(AnimState.RELOAD)

	# Fallback timer if no animation player (ensures reload completes)
	if not animation_player or not animation_player.has_animation("reload"):
		_start_reload_fallback_timer()


## Cancel reload animation
func cancel_reload() -> void:
	is_reloading = false
	_transition_to(AnimState.IDLE)


## Play equip animation
func play_equip() -> void:
	_play_one_shot(AnimState.EQUIP)


## Enter ADS
func enter_ads() -> void:
	is_ads = true
	_transition_to(AnimState.ADS_ENTER)


## Exit ADS
func exit_ads() -> void:
	is_ads = false
	_transition_to(AnimState.ADS_EXIT)


## Play melee animation
func play_melee() -> void:
	_play_one_shot(AnimState.MELEE)


## Play interact animation
func play_interact() -> void:
	_play_one_shot(AnimState.INTERACT)


## Play death animation
func play_death() -> void:
	_transition_to(AnimState.DEAD)


## Transition to a new state
func _transition_to(new_state: AnimState) -> void:
	if current_state == new_state:
		return

	current_state = new_state

	var anim_name: String = state_to_anim.get(new_state, "idle")

	if animation_tree:
		# Use blend tree / state machine
		animation_tree.set("parameters/state/transition_request", anim_name)
	elif animation_player:
		# Direct animation player
		if animation_player.has_animation(anim_name):
			animation_player.play(anim_name)


## Play one-shot animation without changing state
func _play_one_shot(state: AnimState) -> void:
	var anim_name: String = state_to_anim.get(state, "idle")

	if animation_tree:
		# Trigger one-shot on blend tree
		animation_tree.set("parameters/oneshot/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)
		animation_tree.set("parameters/oneshot_anim/transition_request", anim_name)
	elif animation_player:
		if animation_player.has_animation(anim_name):
			animation_player.play(anim_name)


## Called when animation finishes
func _on_animation_finished(anim_name: String) -> void:
	animation_finished.emit(anim_name)

	# Emit specific events based on animation
	match anim_name:
		"reload":
			is_reloading = false
			anim_event.emit("reload_done")
		"fire":
			anim_event.emit("fire_end")
		"equip":
			anim_event.emit("equip_complete")
		"ads_enter":
			anim_event.emit("ads_ready")
		"ads_exit":
			anim_event.emit("ads_done")
			is_ads = false
		"melee":
			anim_event.emit("melee_hit")
		"interact":
			anim_event.emit("interact_complete")

	# Return to idle after one-shots
	if anim_name in ["fire", "equip", "ads_enter", "ads_exit", "melee", "interact"]:
		if not is_reloading and not is_ads:
			_transition_to(AnimState.IDLE)
		elif is_ads:
			_transition_to(AnimState.ADS_IDLE)


## Called from animation tracks for custom events
## Animation tracks should call this via method tracks
##
## Reload timeline events (call these from animation method tracks at correct frames):
##   - "remove_mag": Called when magazine is visually removed from weapon
##   - "insert_mag": Called when new magazine is visually inserted
##   - "chamber": Called when bolt/slide is racked to chamber a round
##   - "reload_done": Called automatically when reload animation finishes
##
## Other events:
##   - "fire_start": Called at start of muzzle flash
##   - "fire_end": Called when fire animation completes
##   - "melee_hit": Called at point of melee impact
##   - "equip_complete": Called when weapon is ready after switching
##
## Example animation method track keyframes for a rifle reload:
##   Frame 0: trigger_event("remove_mag")
##   Frame 30: trigger_event("insert_mag")
##   Frame 50: trigger_event("chamber")
##   Animation end: reload_done emitted automatically
func trigger_event(event_name: String) -> void:
	anim_event.emit(event_name)


## Get current animation state name
func get_current_state_name() -> String:
	return state_to_anim.get(current_state, "idle")


## Get state for network sync
func get_state() -> Dictionary:
	return {
		"anim": get_current_state_name(),
		"ads": is_ads,
		"reload": is_reloading,
	}


## Apply state from network
func apply_state(state: Dictionary) -> void:
	# Remote players just need visual sync
	# We don't need to replicate the full state machine
	var anim_name: String = state.get("anim", "idle")

	# Find matching state
	for anim_state in state_to_anim:
		if state_to_anim[anim_state] == anim_name:
			_transition_to(anim_state)
			break

	is_ads = state.get("ads", false)
	is_reloading = state.get("reload", false)


## Fallback timer for reload when no animation exists
## Uses the weapon's reload_time if available, otherwise 2.5s default
func _start_reload_fallback_timer() -> void:
	var reload_time := 2.5  # Default reload time

	# Try to get actual reload time from parent's combat controller
	var parent := get_parent()
	if parent and parent.has_method("get_combat_controller"):
		var combat: CombatController = parent.get_combat_controller()
		if combat and combat.current_weapon:
			reload_time = combat.current_weapon.reload_time

	# Create one-shot timer
	var timer := get_tree().create_timer(reload_time)
	timer.timeout.connect(_on_reload_fallback_timeout)


## Called when reload fallback timer completes
func _on_reload_fallback_timeout() -> void:
	if is_reloading:
		is_reloading = false
		# Emit the reload events that would normally come from animation
		anim_event.emit("remove_mag")
		anim_event.emit("insert_mag")
		anim_event.emit("chamber")
		anim_event.emit("reload_done")
		_transition_to(AnimState.IDLE)
