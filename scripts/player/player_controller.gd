extends CharacterBody3D
class_name PlayerController
## PlayerController - Main player orchestrator
##
## This is the root node that coordinates all subsystems:
## - MovementController: Physics, stamina, posture
## - CombatController: Weapons, reloads, ADS
## - AnimationController: Animation state machine
## - InventoryRuntime: Ephemeral in-raid inventory
## - PlayerNetworkController: Authority, sync, prediction
##
## The controller does NOT own persistence, inventory truth, or economy.
## Everything flows through the backend via RaidManager.

signal player_ready()
signal player_died()
signal player_downed()
signal player_revived()
signal player_spawned(position: Vector3)

# Player identity
var peer_id: int = 0
var character_id: String = ""
var is_local_player := false

# Health (server-authoritative)
@export var max_health := 100.0
var health: float = 100.0
var is_dead := false

# Downed/Revive system
var is_downed := false
var bleedout_timer: float = 0.0
const BLEEDOUT_TIME: float = 30.0  # Time to revive before death
const REVIVE_TIME: float = 4.0  # Time to complete revival
var reviving_player: PlayerController = null  # Who is reviving us
var being_revived_by: int = 0  # Peer ID of player reviving us
var revive_progress: float = 0.0
var down_count: int = 0  # Gets harder to revive after multiple downs

# Mouse look
var look_yaw: float = 0.0
var look_pitch: float = 0.0
const MOUSE_SENSITIVITY := 0.002

# Node references
@onready var collision_shape: CollisionShape3D = $CollisionShape3D
@onready var mesh: MeshInstance3D = $MeshInstance3D
@onready var camera_pivot: Node3D = $CameraPivot
@onready var camera: Camera3D = $CameraPivot/Camera3D

# Controllers (added as children dynamically)
var movement_controller: MovementController = null
var combat_controller: CombatController = null
var animation_controller: AnimationController = null
var inventory_runtime: InventoryRuntime = null
var equipment_runtime: EquipmentRuntime = null
var attribute_system: AttributeSystem = null
var skill_system: SkillSystem = null
var network_controller: PlayerNetworkController = null

# Prop handler (for barricade system)
var prop_handler: PropHandler = null

# Weapon manager (for visual weapons)
var weapon_manager: WeaponManager = null


func _ready() -> void:
	peer_id = get_multiplayer_authority()
	is_local_player = peer_id == multiplayer.get_unique_id()

	# Add to players group for collision detection
	add_to_group("players")

	_setup_controllers()
	_setup_local_player()

	health = max_health
	player_ready.emit()


func _setup_controllers() -> void:
	# Movement Controller
	movement_controller = MovementController.new()
	movement_controller.name = "MovementController"
	add_child(movement_controller)
	movement_controller.initialize(self, collision_shape)

	# Animation Controller (create even without animations for state tracking)
	animation_controller = AnimationController.new()
	animation_controller.name = "AnimationController"
	add_child(animation_controller)
	# Will be initialized with AnimationPlayer when FP_Arms are added

	# Inventory Runtime
	inventory_runtime = InventoryRuntime.new()
	inventory_runtime.name = "InventoryRuntime"
	add_child(inventory_runtime)

	# Equipment Runtime (armor, rig, accessories)
	equipment_runtime = EquipmentRuntime.new()
	equipment_runtime.stats_updated.connect(_on_equipment_stats_updated)

	# Connect equipment capacity to inventory
	inventory_runtime.update_capacity_from_equipment(equipment_runtime)

	# Attribute System (STR, AGI, END, INT, LCK)
	attribute_system = AttributeSystem.new()
	_load_character_progression()  # Load from saved data instead of defaults
	attribute_system.derived_stats_updated.connect(_on_derived_stats_updated)
	attribute_system.level_up.connect(_on_level_up)

	# Skill System (passive skill bonuses)
	skill_system = SkillSystem.new()
	_load_skill_progression()  # Load from saved data
	skill_system.skill_upgraded.connect(_on_skill_upgraded)

	# Combat Controller
	combat_controller = CombatController.new()
	combat_controller.name = "CombatController"
	add_child(combat_controller)
	combat_controller.initialize(animation_controller, inventory_runtime, camera)

	# Network Controller
	network_controller = PlayerNetworkController.new()
	network_controller.name = "NetworkController"
	add_child(network_controller)
	network_controller.initialize(self, peer_id)

	# Connect signals
	movement_controller.posture_changed.connect(_on_posture_changed)
	movement_controller.stamina_changed.connect(_on_stamina_changed)
	combat_controller.fire_requested.connect(_on_fire_requested)


func _setup_local_player() -> void:
	if is_local_player:
		# Enable camera
		camera.current = true
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

		# Hide own mesh (first person)
		if mesh:
			mesh.visible = false

		# Initialize prop handler
		prop_handler = PropHandler.new()
		add_child(prop_handler)
		prop_handler.initialize(self)

		# Connect prop handler to movement controller for carry penalties
		if movement_controller:
			movement_controller.prop_handler = prop_handler

		# Initialize hammer (all players spawn with hammer for barricading)
		_setup_hammer()

		# Initialize weapon manager (attached to camera pivot for first-person view)
		weapon_manager = WeaponManager.new()
		weapon_manager.name = "WeaponManager"
		camera_pivot.add_child(weapon_manager)
		weapon_manager.initialize(self, camera)

		# Equip weapons from inventory runtime
		_setup_weapons_from_inventory()

		# Register raid if we have one
		_register_raid_with_server()
	else:
		# Remote player
		camera.current = false


func _register_raid_with_server() -> void:
	# Called by client to send their raid info to server
	if RaidManager:
		RaidManager.client_register_raid()


## Setup hammer tool (all players spawn with one)
func _setup_hammer() -> void:
	var HammerScript: GDScript = null
	if ResourceLoader.exists("res://scripts/weapons/hammer.gd"):
		HammerScript = load("res://scripts/weapons/hammer.gd")

	if HammerScript:
		var hammer: Hammer = HammerScript.new()
		hammer.name = "Hammer"
		add_child(hammer)
		hammer.initialize(self)

		# Store reference using meta for input handling
		set_meta("hammer", hammer)
		print("[Player] Hammer equipped")
	else:
		push_warning("[Player] Hammer script not found")


## Setup visual weapons from inventory runtime
func _setup_weapons_from_inventory() -> void:
	if not weapon_manager or not inventory_runtime:
		return

	# Connect to loadout ready signal
	if not inventory_runtime.loadout_ready.is_connected(_on_loadout_ready):
		inventory_runtime.loadout_ready.connect(_on_loadout_ready)

	# If no loadout exists, set up default weapons for testing/development
	if inventory_runtime.get_weapon(0) == null:
		inventory_runtime.setup_default_loadout()

		# Bind primary weapon to combat controller
		if combat_controller:
			var weapon := inventory_runtime.get_weapon(0)
			if weapon:
				combat_controller.bind_weapon(weapon)

	# Setup visual weapons
	for i in range(3):
		var weapon := inventory_runtime.get_weapon(i)
		if weapon:
			weapon_manager.equip_weapon_from_runtime(i, weapon)


func _on_loadout_ready() -> void:
	_setup_weapons_from_inventory()


func _input(event: InputEvent) -> void:
	if not is_local_player:
		return

	if is_dead:
		return

	# Mouse look
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		look_yaw -= event.relative.x * MOUSE_SENSITIVITY
		look_pitch -= event.relative.y * MOUSE_SENSITIVITY
		look_pitch = clampf(look_pitch, -PI/2 + 0.1, PI/2 - 0.1)

		# Apply rotation locally for responsive feel
		rotation.y = look_yaw
		camera_pivot.rotation.x = look_pitch

	# Weapon slot switching (number keys)
	if event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_1:
				_switch_weapon_slot(0)
			KEY_2:
				_switch_weapon_slot(1)
			KEY_3:
				_switch_weapon_slot(2)


func _physics_process(delta: float) -> void:
	if is_dead:
		return

	# Process downed state (server-authoritative)
	if NetworkManager and NetworkManager.is_authority():
		if is_downed:
			_process_downed_state(delta)
			return  # Skip normal processing while downed
		else:
			_process_health_regen(delta)

	# Skip normal processing if downed
	if is_downed:
		return

	# Network controller handles all the tick logic based on authority
	# Movement and combat are processed there

	# Handle local input (props and hammer)
	if is_local_player:
		_process_local_input()

	# Update animation from movement state
	if animation_controller and movement_controller:
		animation_controller.update_from_movement(
			velocity,
			movement_controller.posture,
			is_on_floor(),
			movement_controller.is_sprinting
		)


## Process all local input (props and hammer)
func _process_local_input() -> void:
	# Handle interact key (E) - prop pickup/drop
	if Input.is_action_just_pressed("interact"):
		if prop_handler:
			prop_handler.handle_interact()

	# If holding a prop, prop_handler takes priority for primary/secondary actions
	if prop_handler and prop_handler.is_holding:
		if Input.is_action_just_pressed("primary_action"):
			prop_handler.handle_primary_action()  # Nail placement
		if Input.is_action_just_pressed("secondary_action"):
			prop_handler.handle_secondary_action()  # Throw
		return

	# Not holding prop - hammer handles primary/secondary
	var hammer: Hammer = get_meta("hammer") if has_meta("hammer") else null
	if hammer:
		if Input.is_action_just_pressed("primary_action"):
			hammer.primary_action()  # Place nail or swing
		if Input.is_action_just_pressed("secondary_action"):
			hammer.secondary_action()  # Repair nail


## Initialize loadout from RaidManager (called when raid starts)
func initialize_loadout(loadout: Dictionary, p_character_id: String, raid_id: String) -> void:
	character_id = p_character_id

	if inventory_runtime:
		inventory_runtime.initialize_from_loadout(loadout, p_character_id, raid_id)

	# Equip first weapon
	if combat_controller and inventory_runtime:
		var weapon := inventory_runtime.get_weapon(0)
		if weapon:
			combat_controller.bind_weapon(weapon)


## Switch weapon slot
func _switch_weapon_slot(slot: int) -> void:
	if weapon_manager:
		weapon_manager.switch_weapon(slot)
	if combat_controller and inventory_runtime:
		var weapon := inventory_runtime.get_weapon(slot)
		if weapon:
			combat_controller.bind_weapon(weapon)


## Apply recoil from weapon (called after firing)
func apply_weapon_recoil(recoil: Vector2) -> void:
	if not is_local_player:
		return

	# Apply recoil to camera pitch (vertical) and yaw (horizontal)
	look_pitch -= recoil.y
	look_yaw += recoil.x

	# Clamp pitch
	look_pitch = clampf(look_pitch, -PI/2 + 0.1, PI/2 - 0.1)

	# Apply immediately
	rotation.y = look_yaw
	camera_pivot.rotation.x = look_pitch


## Get network state for snapshot (called by GameState)
func get_network_state() -> Dictionary:
	if network_controller:
		return network_controller.get_network_state()

	# Fallback if no network controller
	return {
		"pos": global_position,
		"vel": velocity,
		"rot": rotation.y,
		"pitch": camera_pivot.rotation.x if camera_pivot else 0.0,
		"health": health,
		"dead": is_dead,
	}


## Apply network state from server (called by GameState)
func apply_network_state(state: Dictionary) -> void:
	# Apply health
	health = state.get("health", health)
	is_dead = state.get("dead", is_dead)

	if network_controller:
		network_controller.apply_network_state(state)


## Apply input from network (server-side, called by GameState)
func apply_input(input_data: Dictionary) -> void:
	if not NetworkManager.is_authority():
		return

	if network_controller:
		network_controller.server_receive_input(input_data)


## Take damage (server-side only)
## damage_type: "bullet", "blunt", "pierce", "zombie"
## is_headshot: True if the hit was to the head
func take_damage(amount: float, from_position: Vector3 = Vector3.ZERO, damage_type: String = "bullet", is_headshot: bool = false) -> void:
	if not NetworkManager.is_authority():
		return

	if is_dead:
		return

	# Downed players take reduced damage but still bleed out faster
	if is_downed:
		bleedout_timer += amount * 0.1  # Damage accelerates bleedout
		return

	# Apply armor reduction
	var final_damage := amount
	if equipment_runtime:
		final_damage = equipment_runtime.apply_armor(amount, damage_type, is_headshot)

	health -= final_damage

	# Broadcast damage event for direction indicator
	NetworkManager.broadcast_event.rpc("player_damaged", {
		"peer_id": peer_id,
		"source_position": from_position,
		"damage": final_damage
	})

	if health <= 0:
		health = 0
		_go_down()


## Go down (can be revived)
func _go_down() -> void:
	if is_downed or is_dead:
		return

	is_downed = true
	down_count += 1
	bleedout_timer = 0.0
	revive_progress = 0.0

	# Cancel any movement
	velocity = Vector3.ZERO

	if animation_controller:
		animation_controller.play_down()

	player_downed.emit()

	# Broadcast downed event
	NetworkManager.broadcast_event.rpc("player_downed", {
		"peer_id": peer_id,
		"position": global_position,
		"down_count": down_count
	})

	print("[Player] %d went down (count: %d)" % [peer_id, down_count])


## Die (permanent death)
func _die() -> void:
	if is_dead:
		return

	is_dead = true
	is_downed = false

	if animation_controller:
		animation_controller.play_death()

	player_died.emit()
	GameState.player_died.emit(peer_id)

	# Broadcast death event
	NetworkManager.broadcast_event.rpc("player_died", {
		"peer_id": peer_id,
		"position": global_position
	})


## Revive (called when revive completes)
func revive() -> void:
	if not NetworkManager.is_authority():
		return

	if not is_downed or is_dead:
		return

	is_downed = false
	revive_progress = 0.0
	being_revived_by = 0

	# Restore some health (less each time downed)
	var revive_health := max_health * (0.5 - down_count * 0.1)
	health = maxf(revive_health, max_health * 0.2)

	if animation_controller:
		animation_controller.play_revive()

	player_revived.emit()

	# Broadcast revive event
	NetworkManager.broadcast_event.rpc("player_revived", {
		"peer_id": peer_id,
		"health": health
	})

	print("[Player] %d was revived with %.0f HP" % [peer_id, health])


## Start reviving this player (called by another player)
func start_revive(reviver_peer_id: int) -> void:
	if not is_downed or is_dead or being_revived_by != 0:
		return

	being_revived_by = reviver_peer_id
	revive_progress = 0.0

	# Broadcast revive started
	NetworkManager.broadcast_event.rpc("revive_started", {
		"target_peer": peer_id,
		"reviver_peer": reviver_peer_id
	})


## Cancel reviving
func cancel_revive() -> void:
	if being_revived_by == 0:
		return

	var reviver := being_revived_by
	being_revived_by = 0
	revive_progress = 0.0

	# Broadcast revive cancelled
	NetworkManager.broadcast_event.rpc("revive_cancelled", {
		"target_peer": peer_id,
		"reviver_peer": reviver
	})


## Update revive progress (called each frame by reviving player)
func update_revive_progress(delta: float, reviver_peer_id: int) -> bool:
	if not is_downed or is_dead:
		return false

	if being_revived_by != reviver_peer_id:
		return false

	# Calculate revive speed (slower after multiple downs)
	var revive_mult := 1.0 - down_count * 0.15
	revive_progress += delta * revive_mult

	# Broadcast progress for UI
	NetworkManager.broadcast_event.rpc("revive_progress", {
		"target_peer": peer_id,
		"reviver_peer": reviver_peer_id,
		"progress": revive_progress / REVIVE_TIME
	})

	if revive_progress >= REVIVE_TIME:
		revive()
		return true

	return false


## Respawn (server-side)
func respawn(spawn_position: Vector3) -> void:
	if not NetworkManager.is_authority():
		return

	global_position = spawn_position
	velocity = Vector3.ZERO
	health = max_health
	is_dead = false

	player_spawned.emit(spawn_position)


## Request extraction (called when player reaches extraction zone)
func request_extract() -> void:
	if is_local_player:
		RaidManager.client_request_extract()


## Process health regeneration (server-side)
func _process_health_regen(delta: float) -> void:
	if health >= max_health:
		return

	# Get total health regen from all sources
	var health_regen := 0.0

	# From equipment
	if equipment_runtime:
		health_regen += equipment_runtime.get_stat("health_regen")

	# From attributes (endurance gives +0.1 HP/sec per point above base)
	if attribute_system:
		var derived: Dictionary = attribute_system.get_derived_stats()
		health_regen += derived.get("health_regen", 0.0)

	# Apply regeneration
	if health_regen > 0:
		health = minf(health + health_regen * delta, max_health)


## Process downed state (server-side) - bleedout timer
func _process_downed_state(delta: float) -> void:
	if not is_downed:
		return

	# Update bleedout timer
	bleedout_timer += delta

	# Faster bleedout after multiple downs
	var bleedout_mult := 1.0 + down_count * 0.2
	var effective_bleedout := BLEEDOUT_TIME / bleedout_mult

	# Broadcast bleedout progress for HUD
	if int(bleedout_timer * 2) % 2 == 0:  # Every 0.5 seconds
		NetworkManager.broadcast_event.rpc("bleedout_progress", {
			"peer_id": peer_id,
			"progress": bleedout_timer / effective_bleedout,
			"time_remaining": effective_bleedout - bleedout_timer
		})

	# Check if bleed out
	if bleedout_timer >= effective_bleedout:
		_die()


# ============================================
# SIGNAL HANDLERS
# ============================================

func _on_posture_changed(_posture: int) -> void:
	# Could update visuals, camera height, etc.
	pass


func _on_stamina_changed(_current: float, _max_value: float) -> void:
	# Could update HUD
	pass


func _on_fire_requested(_weapon_state: Dictionary) -> void:
	# Visual/audio feedback for local player
	if is_local_player:
		# Play muzzle flash, sound, etc.
		pass


# ============================================
# PUBLIC API
# ============================================

func get_camera() -> Camera3D:
	return camera


func get_camera_pivot() -> Node3D:
	return camera_pivot


func get_prop_handler() -> PropHandler:
	return prop_handler


func is_holding_prop() -> bool:
	return prop_handler != null and prop_handler.is_holding


func get_held_prop_id() -> int:
	if prop_handler:
		return prop_handler.held_prop_id
	return -1


func get_movement_controller() -> MovementController:
	return movement_controller


func get_combat_controller() -> CombatController:
	return combat_controller


func get_inventory_runtime() -> InventoryRuntime:
	return inventory_runtime


func get_equipment_runtime() -> EquipmentRuntime:
	return equipment_runtime


func get_weapon_manager() -> WeaponManager:
	return weapon_manager


func get_attribute_system() -> AttributeSystem:
	return attribute_system


# ============================================
# ATTRIBUTE HANDLERS
# ============================================

func _on_derived_stats_updated(stats: Dictionary) -> void:
	# Get skill bonuses
	var skill_bonuses: Dictionary = {}
	if skill_system:
		skill_bonuses = skill_system.get_stat_bonuses()

	# Update max health from endurance + skills
	var base_max_health: float = stats.get("max_health", 100.0)
	var health_mult: float = skill_bonuses.get("health_mult", 1.0)
	max_health = base_max_health * health_mult

	# Cap current health to new max
	if health > max_health:
		health = max_health

	# Update movement controller with attribute + skill multipliers
	if movement_controller:
		var move_mult: float = stats.get("move_speed_mult", 1.0) * skill_bonuses.get("move_speed_mult", 1.0)
		var sprint_mult: float = stats.get("sprint_speed_mult", 1.0) * skill_bonuses.get("sprint_mult", 1.0)
		var stamina_regen_mult: float = stats.get("stamina_regen_mult", 1.0) * skill_bonuses.get("stamina_regen_mult", 1.0)
		var stamina_mult: float = skill_bonuses.get("stamina_mult", 1.0)

		movement_controller.attribute_move_speed_mult = move_mult
		movement_controller.attribute_sprint_speed_mult = sprint_mult
		movement_controller.attribute_stamina_regen_mult = stamina_regen_mult
		movement_controller.max_stamina = stats.get("max_stamina", 100.0) * stamina_mult

	# Update combat controller with attribute + skill multipliers
	if combat_controller:
		var reload_mult: float = stats.get("reload_speed_mult", 1.0) * skill_bonuses.get("reload_speed_mult", 1.0)
		var ads_mult: float = stats.get("ads_speed_mult", 1.0) * skill_bonuses.get("ads_speed_mult", 1.0)
		var crit_chance: float = stats.get("crit_chance", 0.05) + skill_bonuses.get("crit_chance", 0.0)
		var crit_damage: float = stats.get("crit_damage_mult", 1.5) + (skill_bonuses.get("crit_damage", 1.5) - 1.5)

		combat_controller.attribute_reload_speed_mult = reload_mult
		combat_controller.attribute_ads_speed_mult = ads_mult
		combat_controller.attribute_crit_chance = crit_chance
		combat_controller.attribute_crit_damage_mult = crit_damage

		# Additional skill bonuses for combat
		combat_controller.skill_damage_mult = skill_bonuses.get("damage_mult", 1.0)
		combat_controller.skill_fire_rate_mult = skill_bonuses.get("fire_rate_mult", 1.0)
		combat_controller.skill_accuracy_mult = skill_bonuses.get("accuracy_mult", 1.0)
		combat_controller.skill_recoil_mult = skill_bonuses.get("recoil_mult", 1.0)


func _on_level_up(new_level: int, attribute_points: int) -> void:
	print("[Player] Leveled up to %d! (%d attribute points available)" % [new_level, attribute_points])

	# Show level up in HUD
	var hud := _find_fps_hud()
	if hud and hud.has_method("show_level_up"):
		hud.show_level_up(new_level, attribute_points)

	# Save progression
	if EconomyService and EconomyService.is_logged_in:
		EconomyService.save_character_data()


func _find_fps_hud() -> FpsHud:
	# Look in game world for HUD
	if GameState and GameState.world_node:
		var hud := GameState.world_node.get_node_or_null("FpsHud")
		if hud is FpsHud:
			return hud as FpsHud
	return null


func _on_equipment_stats_updated(total_stats: Dictionary) -> void:
	# Update inventory capacity
	if inventory_runtime:
		inventory_runtime.update_capacity_from_equipment(equipment_runtime)

	# Update movement speed modifier
	if movement_controller:
		movement_controller.equipment_speed_modifier = total_stats.get("speed_modifier", 1.0)
		movement_controller.equipment_stamina_modifier = total_stats.get("stamina_modifier", 1.0)


## Load character progression data from EconomyService
func _load_character_progression() -> void:
	if not attribute_system:
		return

	# Try to load from EconomyService (if logged in)
	if EconomyService and EconomyService.is_logged_in:
		var saved_data: Dictionary = EconomyService.get_character_data()

		# Load level and XP
		attribute_system.level = saved_data.get("level", 1)
		attribute_system.experience = saved_data.get("experience", 0)
		attribute_system.attribute_points = saved_data.get("attribute_points", 5)

		# Load base attributes
		var base_attrs: Dictionary = saved_data.get("base_attributes", {})
		if not base_attrs.is_empty():
			for attr_name in base_attrs:
				var attr_enum := _attr_name_to_enum(attr_name)
				if attr_enum >= 0:
					attribute_system.base_attributes[attr_enum] = base_attrs[attr_name]

		attribute_system._recalculate_derived_stats()
		print("[Player] Loaded character progression: Level %d, XP %d" % [
			attribute_system.level,
			attribute_system.experience
		])
	else:
		# No saved data - use defaults
		attribute_system.setup_default()


## Convert attribute name string to enum
func _attr_name_to_enum(name: String) -> int:
	match name.to_lower():
		"strength": return AttributeSystem.Attribute.STRENGTH
		"agility": return AttributeSystem.Attribute.AGILITY
		"endurance": return AttributeSystem.Attribute.ENDURANCE
		"intellect": return AttributeSystem.Attribute.INTELLECT
		"luck": return AttributeSystem.Attribute.LUCK
	return -1


## Grant XP to player (called after kills, objectives, etc.)
func grant_xp(amount: int) -> void:
	if attribute_system:
		attribute_system.add_experience(amount)

	# Also add XP to skill system for skill points
	if skill_system:
		skill_system.add_xp(amount)

	# Also persist to EconomyService
	if EconomyService and EconomyService.is_logged_in:
		EconomyService.add_experience(amount)


## Load skill progression data from EconomyService
func _load_skill_progression() -> void:
	if not skill_system:
		return

	# Try to load from EconomyService (if logged in)
	if EconomyService and EconomyService.is_logged_in:
		var saved_data: Dictionary = EconomyService.get_character_data()
		var skill_data: Dictionary = saved_data.get("skill_data", {})

		if not skill_data.is_empty():
			skill_system.load_save_data(skill_data)
			print("[Player] Loaded skill progression: %d skill points, prestige %d" % [
				skill_system.skill_points,
				skill_system.prestige_level
			])


## Called when a skill is upgraded
func _on_skill_upgraded(_category: String, skill_id: String, new_level: int) -> void:
	print("[Player] Skill '%s' upgraded to level %d" % [skill_id, new_level])

	# Recalculate derived stats with new skill bonuses
	if attribute_system:
		attribute_system._recalculate_derived_stats()

	# Save progression
	if EconomyService and EconomyService.is_logged_in:
		var skill_data := skill_system.get_save_data() if skill_system else {}
		EconomyService.save_character_data({"skill_data": skill_data})


## Get the skill system
func get_skill_system() -> SkillSystem:
	return skill_system
