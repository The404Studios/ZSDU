extends Node
## PlayerInteractions - Client-side interaction handler
##
## Handles:
## - Phase through props (F key near nailed props)
## - Loot corpses (E key)
## - Shop interaction (E key near shop)
## - Turret placement (from shop menu)
##
## All actions go through EntityRegistry.request_interact RPC

class_name PlayerInteractions

# Reference to owning player
var player: Node3D = null
var peer_id: int = -1

# UI references
var interaction_prompt: Label = null
var shop_ui: Control = null
var loot_ui: Control = null

# State
var is_phasing: bool = false
var phase_timer: float = 0.0
var nearby_entity_id: int = -1
var nearby_entity_type: String = ""

# Detection settings
const INTERACT_DISTANCE := 3.0
const DETECTION_INTERVAL := 0.1
var _detection_timer: float = 0.0


func _ready() -> void:
	# Get player reference
	player = get_parent()
	if player:
		peer_id = player.get_multiplayer_authority()

	# Connect to EntityRegistry signals
	if EntityRegistry:
		EntityRegistry.interaction_result.connect(_on_interaction_result)
		EntityRegistry.entity_event_received.connect(_on_entity_event)


func _process(delta: float) -> void:
	if not player or not is_multiplayer_authority():
		return

	# Update phase timer (visual feedback)
	if is_phasing:
		phase_timer -= delta
		if phase_timer <= 0:
			is_phasing = false
			_update_phase_visual(false)

	# Periodic entity detection
	_detection_timer += delta
	if _detection_timer >= DETECTION_INTERVAL:
		_detection_timer = 0.0
		_detect_nearby_entities()


func _input(event: InputEvent) -> void:
	if not player or not is_multiplayer_authority():
		return

	# Phase key (F) - phase through nailed props
	if event.is_action_pressed("phase") and nearby_entity_id >= 0:
		if nearby_entity_type == "prop":
			_request_phase()

	# Interact key (E) - loot, shop, rigidify
	if event.is_action_pressed("interact") and nearby_entity_id >= 0:
		match nearby_entity_type:
			"corpse":
				_request_loot()
			"shop":
				_request_shop_open()
			"turret":
				_request_turret_refill()


# ============================================
# ENTITY DETECTION
# ============================================

func _detect_nearby_entities() -> void:
	if not player:
		return

	var player_pos: Vector3 = player.global_position
	var nearest_id := -1
	var nearest_type := ""
	var nearest_dist := INTERACT_DISTANCE

	# Check EntityRegistry entities
	if EntityRegistry:
		# Check corpses
		for entity in EntityRegistry.get_entities_by_type(EntityRegistry.EntityType.CORPSE):
			if not is_instance_valid(entity):
				continue
			var dist: float = player_pos.distance_to(entity.global_position)
			if dist < nearest_dist:
				var loot := EntityRegistry.get_component(entity.net_id, "loot")
				if not loot.get("looted", false):
					nearest_dist = dist
					nearest_id = entity.net_id
					nearest_type = "corpse"

		# Check shops
		for entity in EntityRegistry.get_entities_by_type(EntityRegistry.EntityType.SHOP):
			if not is_instance_valid(entity):
				continue
			var dist: float = player_pos.distance_to(entity.global_position)
			if dist < nearest_dist:
				nearest_dist = dist
				nearest_id = entity.net_id
				nearest_type = "shop"

		# Check turrets (for refill)
		for entity in EntityRegistry.get_entities_by_type(EntityRegistry.EntityType.TURRET):
			if not is_instance_valid(entity):
				continue
			var dist: float = player_pos.distance_to(entity.global_position)
			if dist < nearest_dist:
				var weapon := EntityRegistry.get_component(entity.net_id, "weapon")
				if weapon.get("ammo", 100) < weapon.get("max_ammo", 100):
					nearest_dist = dist
					nearest_id = entity.net_id
					nearest_type = "turret"

	# Check nailed props (for phasing)
	for prop_id in GameState.props:
		var prop: RigidBody3D = GameState.props[prop_id]
		if not is_instance_valid(prop):
			continue

		# Check if prop has nails
		var has_nails := false
		if "attached_nail_ids" in prop:
			has_nails = prop.attached_nail_ids.size() > 0

		if not has_nails:
			continue

		var dist: float = player_pos.distance_to(prop.global_position)
		if dist < nearest_dist:
			nearest_dist = dist
			nearest_id = prop.prop_id if "prop_id" in prop else -1
			nearest_type = "prop"

	# Update state
	nearby_entity_id = nearest_id
	nearby_entity_type = nearest_type

	# Update UI prompt
	_update_interaction_prompt()


func _update_interaction_prompt() -> void:
	if not interaction_prompt:
		return

	if nearby_entity_id < 0:
		interaction_prompt.visible = false
		return

	interaction_prompt.visible = true

	match nearby_entity_type:
		"corpse":
			interaction_prompt.text = "[E] Loot Corpse"
		"shop":
			interaction_prompt.text = "[E] Open Shop"
		"prop":
			interaction_prompt.text = "[F] Phase Through"
		"turret":
			interaction_prompt.text = "[E] Refill Turret (10 currency)"
		_:
			interaction_prompt.text = "[E] Interact"


# ============================================
# INTERACTION REQUESTS
# ============================================

func _request_phase() -> void:
	if is_phasing:
		return

	if nearby_entity_id < 0:
		return

	# Check if this prop is actually registered in EntityRegistry
	# If not, we need to find its net_id via the prop_id
	var net_id := nearby_entity_id

	# Props might be tracked by prop_id in GameState, not net_id in EntityRegistry
	# For now, we'll request using the prop_id and let server validate
	if EntityRegistry:
		EntityRegistry.request_interact.rpc_id(1, net_id, "phase_toggle", {})


func _request_loot() -> void:
	if nearby_entity_id < 0 or nearby_entity_type != "corpse":
		return

	if EntityRegistry:
		EntityRegistry.request_interact.rpc_id(1, nearby_entity_id, "loot", {})


func _request_shop_open() -> void:
	if nearby_entity_id < 0 or nearby_entity_type != "shop":
		return

	if EntityRegistry:
		EntityRegistry.request_interact.rpc_id(1, nearby_entity_id, "shop_open", {})


func _request_turret_refill() -> void:
	if nearby_entity_id < 0 or nearby_entity_type != "turret":
		return

	if EntityRegistry:
		EntityRegistry.request_interact.rpc_id(1, nearby_entity_id, "refill_turret", {})


func request_shop_buy(shop_net_id: int, item_id: String, quantity: int = 1) -> void:
	if EntityRegistry:
		EntityRegistry.request_interact.rpc_id(1, shop_net_id, "shop_buy", {
			"item_id": item_id,
			"quantity": quantity
		})


func request_place_turret(position: Vector3, rotation: float = 0.0) -> void:
	if EntityRegistry:
		EntityRegistry.request_interact.rpc_id(1, -1, "place_turret", {
			"position": position,
			"rotation": rotation
		})


func request_rigidify(corpse_net_id: int) -> void:
	if EntityRegistry:
		EntityRegistry.request_interact.rpc_id(1, corpse_net_id, "rigidify", {})


# ============================================
# RESPONSE HANDLERS
# ============================================

func _on_interaction_result(net_id: int, action: String, success: bool, data: Dictionary) -> void:
	if not success:
		var error: String = data.get("error", "Action failed")
		print("[Interactions] %s failed: %s" % [action, error])
		_show_error(error)
		return

	match action:
		"phase_toggle":
			_start_phase(data.get("duration", 2.0))
		"loot":
			_show_loot_result(data)
		"shop_open":
			_open_shop_ui(net_id, data)
		"shop_buy":
			_show_purchase_result(data)
		"place_turret":
			_show_turret_placed(data)
		"refill_turret":
			_show_turret_refilled(data)


func _on_entity_event(net_id: int, event: String, payload: Dictionary) -> void:
	match event:
		"phase_started":
			if payload.get("by", -1) == peer_id:
				_start_phase(payload.get("duration", 2.0))
		"phase_ended":
			if net_id == peer_id:
				_end_phase()
		"looted":
			# Update UI with new team currency
			_update_currency_display()
		"item_purchased", "item_sold":
			_update_currency_display()
		"turret_spawned":
			# Could play placement sound
			pass
		"turret_fire":
			# Could play firing sound for nearby turrets
			pass


# ============================================
# PHASE VISUAL FEEDBACK
# ============================================

func _start_phase(duration: float) -> void:
	is_phasing = true
	phase_timer = duration
	_update_phase_visual(true)


func _end_phase() -> void:
	is_phasing = false
	phase_timer = 0.0
	_update_phase_visual(false)


func _update_phase_visual(phasing: bool) -> void:
	if not player:
		return

	# Could add visual effect like transparency or shader
	# For now, just update a potential phase indicator
	if player.has_method("set_phasing"):
		player.set_phasing(phasing)


# ============================================
# UI HELPERS
# ============================================

func _show_error(message: String) -> void:
	# Show error notification
	print("[Interactions] Error: %s" % message)


func _show_loot_result(data: Dictionary) -> void:
	var items: Dictionary = data.get("items", {})
	var currency: int = data.get("team_currency", 0)

	print("[Interactions] Looted: %s (Team: %d)" % [items, currency])

	# Could show loot popup
	_update_currency_display()


func _open_shop_ui(shop_net_id: int, data: Dictionary) -> void:
	var catalog: Array = data.get("catalog", [])
	var currency: int = data.get("team_currency", 0)

	print("[Interactions] Shop opened with %d items (Team: %d currency)" % [catalog.size(), currency])

	# Would open shop UI here
	if shop_ui and shop_ui.has_method("open"):
		shop_ui.open(shop_net_id, catalog, currency)


func _show_purchase_result(data: Dictionary) -> void:
	var item_id: String = data.get("item_id", "")
	var quantity: int = data.get("quantity", 1)

	print("[Interactions] Purchased %dx %s" % [quantity, item_id])

	# Handle special items
	if item_id == "turret":
		# Enter turret placement mode
		_enter_placement_mode("turret")

	_update_currency_display()


func _show_turret_placed(data: Dictionary) -> void:
	var net_id: int = data.get("net_id", -1)
	print("[Interactions] Turret placed (ID: %d)" % net_id)

	_update_currency_display()


func _show_turret_refilled(data: Dictionary) -> void:
	var ammo: int = data.get("ammo", 0)
	print("[Interactions] Turret refilled to %d ammo" % ammo)

	_update_currency_display()


func _update_currency_display() -> void:
	# Update currency UI
	if EntityRegistry:
		var currency: int = EntityRegistry.get_team_currency()
		# Would update HUD here
		print("[Interactions] Team currency: %d" % currency)


func _enter_placement_mode(item_type: String) -> void:
	# Would enter placement mode for turret/etc
	print("[Interactions] Entering %s placement mode" % item_type)


# ============================================
# PUBLIC API
# ============================================

func get_nearby_entity_id() -> int:
	return nearby_entity_id


func get_nearby_entity_type() -> String:
	return nearby_entity_type


func is_player_phasing() -> bool:
	return is_phasing


func get_team_currency() -> int:
	if EntityRegistry:
		return EntityRegistry.get_team_currency()
	return 0
