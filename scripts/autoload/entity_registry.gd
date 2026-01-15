extends Node
## EntityRegistry - Server-authoritative network entity registry
##
## Every interactable thing (player, zombie, prop, corpse, turret, shop) is an Entity.
## Server issues net_ids and owns all state.
## Clients request interactions via single RPC pipe.
##
## This is NOT a full ECS - it's a lightweight registry with authority.

signal entity_registered(net_id: int, entity_type: String)
signal entity_unregistered(net_id: int)
signal entity_event_received(net_id: int, event: String, payload: Dictionary)
signal interaction_result(net_id: int, action: String, success: bool, data: Dictionary)

# ============================================
# ENTITY TYPES
# ============================================
enum EntityType {
	PLAYER,
	ZOMBIE,
	PROP,
	CORPSE,
	TURRET,
	SHOP,
	NAIL,
	LOOTBAG
}

# ============================================
# CONSTANTS
# ============================================
const INTERACT_DISTANCE := 3.0  # Max distance for interactions
const PHASE_DURATION := 2.0     # How long phase lasts

# ============================================
# STATE
# ============================================
var _next_id: int = 1
var entities: Dictionary = {}  # net_id -> entity node
var entity_types: Dictionary = {}  # net_id -> EntityType
var entity_owners: Dictionary = {}  # net_id -> peer_id (optional)
var entity_components: Dictionary = {}  # net_id -> { component_name -> data }

# Team shared currency (ZS-style)
var team_currency: int = 0
const STARTING_CURRENCY := 100

# Phase state tracking
var phasing_players: Dictionary = {}  # peer_id -> { end_time, original_mask }


func _ready() -> void:
	# Connect to NetworkManager for player join/leave
	if NetworkManager:
		NetworkManager.player_joined.connect(_on_player_joined)
		NetworkManager.player_left.connect(_on_player_left)


func _physics_process(delta: float) -> void:
	if not NetworkManager.is_authority():
		return

	# Update phase timers
	_update_phase_states()


# ============================================
# ENTITY REGISTRATION (Server-side)
# ============================================

## Register an entity and get a net_id
func register_entity(entity: Node, type: EntityType, owner_peer: int = -1) -> int:
	if not NetworkManager.is_authority():
		push_error("[EntityRegistry] Only server can register entities")
		return -1

	var net_id := _next_id
	_next_id += 1

	entities[net_id] = entity
	entity_types[net_id] = type
	if owner_peer > 0:
		entity_owners[net_id] = owner_peer
	entity_components[net_id] = {}

	# Set net_id on the entity node
	if "net_id" in entity:
		entity.net_id = net_id
	else:
		entity.set_meta("net_id", net_id)

	# Broadcast to clients
	_broadcast_entity_registered.rpc(net_id, type, owner_peer)

	entity_registered.emit(net_id, _type_to_string(type))
	print("[EntityRegistry] Registered: %s #%d (owner: %d)" % [_type_to_string(type), net_id, owner_peer])

	return net_id


## Unregister an entity
func unregister_entity(net_id: int) -> void:
	if not NetworkManager.is_authority():
		return

	if net_id not in entities:
		return

	entities.erase(net_id)
	entity_types.erase(net_id)
	entity_owners.erase(net_id)
	entity_components.erase(net_id)

	# Broadcast to clients
	_broadcast_entity_unregistered.rpc(net_id)

	entity_unregistered.emit(net_id)
	print("[EntityRegistry] Unregistered: #%d" % net_id)


## Add a component to an entity
func add_component(net_id: int, component_name: String, data: Dictionary) -> void:
	if net_id not in entity_components:
		entity_components[net_id] = {}

	entity_components[net_id][component_name] = data


## Get a component from an entity
func get_component(net_id: int, component_name: String) -> Dictionary:
	if net_id not in entity_components:
		return {}
	return entity_components[net_id].get(component_name, {})


## Update a component
func update_component(net_id: int, component_name: String, updates: Dictionary) -> void:
	if net_id not in entity_components:
		return
	if component_name not in entity_components[net_id]:
		entity_components[net_id][component_name] = {}

	for key in updates:
		entity_components[net_id][component_name][key] = updates[key]


## Get entity by net_id
func get_entity(net_id: int) -> Node:
	return entities.get(net_id)


## Get entity type
func get_entity_type(net_id: int) -> EntityType:
	return entity_types.get(net_id, EntityType.PROP)


## Get entities by type
func get_entities_by_type(type: EntityType) -> Array:
	var result := []
	for net_id in entity_types:
		if entity_types[net_id] == type:
			if net_id in entities and is_instance_valid(entities[net_id]):
				result.append(entities[net_id])
	return result


# ============================================
# INTERACTION PIPE (THE CORE)
# ============================================

## Client requests an interaction (single entry point for all actions)
@rpc("any_peer", "reliable")
func request_interact(net_id: int, action: String, payload: Dictionary = {}) -> void:
	if not NetworkManager.is_authority():
		return

	var sender_id := multiplayer.get_remote_sender_id()

	# Validate player exists
	if sender_id not in GameState.players:
		_send_interact_result.rpc_id(sender_id, net_id, action, false, {"error": "Player not found"})
		return

	var player: Node3D = GameState.players[sender_id]
	if not is_instance_valid(player):
		_send_interact_result.rpc_id(sender_id, net_id, action, false, {"error": "Player invalid"})
		return

	# Some actions use different ID types:
	# - "phase_toggle": net_id is prop_id from GameState.props
	# - "place_turret": net_id is ignored (position in payload)
	# - Others: net_id is EntityRegistry net_id
	var skip_entity_validation := action in ["phase_toggle", "place_turret"]

	if not skip_entity_validation:
		# Validate entity exists in EntityRegistry
		if net_id not in entities:
			_send_interact_result.rpc_id(sender_id, net_id, action, false, {"error": "Entity not found"})
			return

		var entity: Node = entities[net_id]
		if not is_instance_valid(entity):
			_send_interact_result.rpc_id(sender_id, net_id, action, false, {"error": "Entity invalid"})
			return

		# Check distance
		var entity_pos: Vector3 = entity.global_position if entity is Node3D else Vector3.ZERO
		var distance := player.global_position.distance_to(entity_pos)
		if distance > INTERACT_DISTANCE:
			_send_interact_result.rpc_id(sender_id, net_id, action, false, {"error": "Too far"})
			return

	# Route to action handler
	var result := _handle_action(sender_id, net_id, action, payload)

	# Send result back to requester
	_send_interact_result.rpc_id(sender_id, net_id, action, result.success, result.data)


## Handle a specific action (server-side)
func _handle_action(peer_id: int, net_id: int, action: String, payload: Dictionary) -> Dictionary:
	match action:
		# Phase through props
		"phase_toggle":
			return _action_phase_toggle(peer_id, net_id)

		# Loot corpse
		"loot":
			return _action_loot(peer_id, net_id)

		# Rigidify corpse
		"rigidify":
			return _action_rigidify(peer_id, net_id)

		# Shop actions
		"shop_open":
			return _action_shop_open(peer_id, net_id)
		"shop_buy":
			return _action_shop_buy(peer_id, net_id, payload)
		"shop_sell":
			return _action_shop_sell(peer_id, net_id, payload)

		# Turret placement
		"place_turret":
			return _action_place_turret(peer_id, payload)

		# Turret refill
		"refill_turret":
			return _action_refill_turret(peer_id, net_id)

		# Repair nail
		"repair_nail":
			return _action_repair_nail(peer_id, net_id)

		_:
			return {"success": false, "data": {"error": "Unknown action"}}


# ============================================
# ACTION HANDLERS
# ============================================

## Phase through nailed props (JetBoom-style)
## NOTE: Props use prop_id from GameState, not net_id from EntityRegistry
func _action_phase_toggle(peer_id: int, prop_id: int) -> Dictionary:
	# Look up prop in GameState (props aren't registered in EntityRegistry)
	if prop_id not in GameState.props:
		return {"success": false, "data": {"error": "Prop not found"}}

	var prop: Node = GameState.props[prop_id]
	if not is_instance_valid(prop):
		return {"success": false, "data": {"error": "Prop invalid"}}

	# Check distance
	if peer_id in GameState.players:
		var player: Node3D = GameState.players[peer_id]
		if is_instance_valid(player) and prop is Node3D:
			var distance := player.global_position.distance_to(prop.global_position)
			if distance > INTERACT_DISTANCE:
				return {"success": false, "data": {"error": "Too far"}}

	# Check prop has nails
	var has_nails := false
	if prop.has_method("has_nails"):
		has_nails = prop.has_nails()
	elif "attached_nail_ids" in prop:
		has_nails = prop.attached_nail_ids.size() > 0

	if not has_nails:
		return {"success": false, "data": {"error": "Prop must be nailed"}}

	# Already phasing?
	if peer_id in phasing_players:
		return {"success": false, "data": {"error": "Already phasing"}}

	# Start phase
	var player: Node3D = GameState.players[peer_id]
	if not player is CollisionObject3D:
		return {"success": false, "data": {"error": "Player has no collision"}}

	var collision_player: CollisionObject3D = player as CollisionObject3D
	var original_mask := collision_player.collision_mask

	# Disable collision with Props layer (layer 4 = bit 3)
	collision_player.collision_mask &= ~(1 << 3)

	phasing_players[peer_id] = {
		"end_time": Time.get_ticks_msec() / 1000.0 + PHASE_DURATION,
		"original_mask": original_mask
	}

	# Broadcast phase started
	_broadcast_entity_event.rpc(peer_id, "phase_started", {"duration": PHASE_DURATION})

	print("[EntityRegistry] Player %d started phasing" % peer_id)
	return {"success": true, "data": {"duration": PHASE_DURATION}}


## Update phase states (server tick)
func _update_phase_states() -> void:
	var current_time := Time.get_ticks_msec() / 1000.0
	var to_remove := []

	for peer_id in phasing_players:
		var phase_data: Dictionary = phasing_players[peer_id]
		if current_time >= phase_data.end_time:
			to_remove.append(peer_id)

	for peer_id in to_remove:
		_end_phase(peer_id)


func _end_phase(peer_id: int) -> void:
	if peer_id not in phasing_players:
		return

	var phase_data: Dictionary = phasing_players[peer_id]

	if peer_id in GameState.players:
		var player: Node3D = GameState.players[peer_id]
		if player is CollisionObject3D:
			var collision_player: CollisionObject3D = player as CollisionObject3D
			collision_player.collision_mask = phase_data.original_mask

	phasing_players.erase(peer_id)

	# Broadcast phase ended
	_broadcast_entity_event.rpc(peer_id, "phase_ended", {})

	print("[EntityRegistry] Player %d stopped phasing" % peer_id)


## Loot a corpse
func _action_loot(peer_id: int, corpse_net_id: int) -> Dictionary:
	var corpse_type := get_entity_type(corpse_net_id)
	if corpse_type != EntityType.CORPSE and corpse_type != EntityType.LOOTBAG:
		return {"success": false, "data": {"error": "Not lootable"}}

	var loot_component := get_component(corpse_net_id, "loot")
	if loot_component.is_empty():
		return {"success": false, "data": {"error": "Nothing to loot"}}

	if loot_component.get("looted", false):
		return {"success": false, "data": {"error": "Already looted"}}

	# Get loot items
	var items: Dictionary = loot_component.get("items", {})

	# Add to team currency (ZS-style shared pool)
	var scrap: int = items.get("scrap", 0)
	team_currency += scrap

	# Mark as looted
	update_component(corpse_net_id, "loot", {"looted": true})

	# Broadcast loot event
	_broadcast_entity_event.rpc(corpse_net_id, "looted", {
		"by": peer_id,
		"items": items,
		"team_currency": team_currency
	})

	print("[EntityRegistry] Player %d looted corpse #%d (+%d scrap, team: %d)" % [peer_id, corpse_net_id, scrap, team_currency])
	return {"success": true, "data": {"items": items, "team_currency": team_currency}}


## Rigidify a corpse (turn into physics prop)
func _action_rigidify(peer_id: int, corpse_net_id: int) -> Dictionary:
	var corpse_type := get_entity_type(corpse_net_id)
	if corpse_type != EntityType.CORPSE:
		return {"success": false, "data": {"error": "Not a corpse"}}

	var corpse: Node = entities[corpse_net_id]
	if not is_instance_valid(corpse):
		return {"success": false, "data": {"error": "Corpse invalid"}}

	# Check if already rigid
	var rigid_component := get_component(corpse_net_id, "rigid")
	if rigid_component.get("is_rigid", false):
		return {"success": false, "data": {"error": "Already rigid"}}

	# Convert to rigid body (if corpse has the method)
	if corpse.has_method("make_rigid"):
		corpse.make_rigid()
	else:
		# Manual rigidification
		if corpse is RigidBody3D:
			corpse.freeze = false

	# Update entity type to PROP (now it can be nailed, picked up, etc)
	entity_types[corpse_net_id] = EntityType.PROP
	update_component(corpse_net_id, "rigid", {"is_rigid": true, "by": peer_id})

	# Broadcast rigidify event
	_broadcast_entity_event.rpc(corpse_net_id, "rigidified", {"by": peer_id})

	print("[EntityRegistry] Player %d rigidified corpse #%d" % [peer_id, corpse_net_id])
	return {"success": true, "data": {}}


## Open shop
func _action_shop_open(peer_id: int, shop_net_id: int) -> Dictionary:
	var shop_type := get_entity_type(shop_net_id)
	if shop_type != EntityType.SHOP:
		return {"success": false, "data": {"error": "Not a shop"}}

	# Get shop catalog
	var shop_component := get_component(shop_net_id, "shop")
	var catalog: Array = shop_component.get("catalog", _get_default_catalog())

	return {"success": true, "data": {"catalog": catalog, "team_currency": team_currency}}


## Buy from shop
func _action_shop_buy(peer_id: int, shop_net_id: int, payload: Dictionary) -> Dictionary:
	var shop_type := get_entity_type(shop_net_id)
	if shop_type != EntityType.SHOP:
		return {"success": false, "data": {"error": "Not a shop"}}

	var item_id: String = payload.get("item_id", "")
	var quantity: int = payload.get("quantity", 1)

	if item_id == "":
		return {"success": false, "data": {"error": "No item specified"}}

	# Get catalog and find item
	var shop_component := get_component(shop_net_id, "shop")
	var catalog: Array = shop_component.get("catalog", _get_default_catalog())

	var item_data: Dictionary = {}
	for item in catalog:
		if item.get("id") == item_id:
			item_data = item
			break

	if item_data.is_empty():
		return {"success": false, "data": {"error": "Item not found"}}

	var total_cost: int = item_data.get("price", 0) * quantity

	# Check team currency
	if team_currency < total_cost:
		return {"success": false, "data": {"error": "Not enough currency"}}

	# Deduct currency
	team_currency -= total_cost

	# Give item to player
	_give_item_to_player(peer_id, item_id, quantity)

	# Broadcast purchase
	_broadcast_entity_event.rpc(shop_net_id, "item_purchased", {
		"by": peer_id,
		"item_id": item_id,
		"quantity": quantity,
		"cost": total_cost,
		"team_currency": team_currency
	})

	print("[EntityRegistry] Player %d bought %dx %s for %d (team: %d)" % [peer_id, quantity, item_id, total_cost, team_currency])
	return {"success": true, "data": {"item_id": item_id, "quantity": quantity, "team_currency": team_currency}}


## Sell to shop
func _action_shop_sell(peer_id: int, shop_net_id: int, payload: Dictionary) -> Dictionary:
	var shop_type := get_entity_type(shop_net_id)
	if shop_type != EntityType.SHOP:
		return {"success": false, "data": {"error": "Not a shop"}}

	var item_id: String = payload.get("item_id", "")
	var quantity: int = payload.get("quantity", 1)

	# Simplified: just add currency (no inventory tracking yet)
	var sell_value: int = _get_sell_value(item_id) * quantity
	team_currency += sell_value

	# Broadcast sale
	_broadcast_entity_event.rpc(shop_net_id, "item_sold", {
		"by": peer_id,
		"item_id": item_id,
		"quantity": quantity,
		"value": sell_value,
		"team_currency": team_currency
	})

	print("[EntityRegistry] Player %d sold %dx %s for %d (team: %d)" % [peer_id, quantity, item_id, sell_value, team_currency])
	return {"success": true, "data": {"value": sell_value, "team_currency": team_currency}}


## Place a turret
func _action_place_turret(peer_id: int, payload: Dictionary) -> Dictionary:
	var position: Vector3 = payload.get("position", Vector3.ZERO)
	var rotation: float = payload.get("rotation", 0.0)

	# Cost check
	var turret_cost := 50
	if team_currency < turret_cost:
		return {"success": false, "data": {"error": "Not enough currency"}}

	# Validate position (raycast to ground, not inside wall)
	var player: Node3D = GameState.players[peer_id]
	if player.global_position.distance_to(position) > 5.0:
		return {"success": false, "data": {"error": "Too far to place"}}

	# Deduct cost
	team_currency -= turret_cost

	# Spawn turret
	var turret := _spawn_turret(position, rotation, peer_id)

	print("[EntityRegistry] Player %d placed turret #%d at %s" % [peer_id, turret.net_id, position])
	return {"success": true, "data": {"net_id": turret.net_id, "team_currency": team_currency}}


## Refill turret ammo
func _action_refill_turret(peer_id: int, turret_net_id: int) -> Dictionary:
	var turret_type := get_entity_type(turret_net_id)
	if turret_type != EntityType.TURRET:
		return {"success": false, "data": {"error": "Not a turret"}}

	var weapon_component := get_component(turret_net_id, "weapon")
	var current_ammo: int = weapon_component.get("ammo", 0)
	var max_ammo: int = weapon_component.get("max_ammo", 100)

	if current_ammo >= max_ammo:
		return {"success": false, "data": {"error": "Already full"}}

	var refill_cost := 10
	if team_currency < refill_cost:
		return {"success": false, "data": {"error": "Not enough currency"}}

	team_currency -= refill_cost
	update_component(turret_net_id, "weapon", {"ammo": max_ammo})

	# Broadcast refill
	_broadcast_entity_event.rpc(turret_net_id, "turret_refilled", {
		"by": peer_id,
		"ammo": max_ammo,
		"team_currency": team_currency
	})

	return {"success": true, "data": {"ammo": max_ammo, "team_currency": team_currency}}


## Repair a nail
func _action_repair_nail(peer_id: int, nail_net_id: int) -> Dictionary:
	var nail_type := get_entity_type(nail_net_id)
	if nail_type != EntityType.NAIL:
		return {"success": false, "data": {"error": "Not a nail"}}

	# Delegate to GameState's nail repair system
	if GameState:
		GameState._handle_nail_repair(peer_id, {"nail_id": nail_net_id})

	return {"success": true, "data": {}}


# ============================================
# SPAWNERS
# ============================================

## Spawn a corpse when zombie dies
func spawn_corpse(position: Vector3, zombie_type: String = "walker") -> Node3D:
	if not NetworkManager.is_authority():
		return null

	# Create corpse node (simplified - just a RigidBody3D)
	var corpse := RigidBody3D.new()
	corpse.name = "Corpse_%d" % _next_id
	corpse.global_position = position
	corpse.freeze = true  # Frozen until rigidified

	# Add collision shape
	var collision := CollisionShape3D.new()
	var shape := CapsuleShape3D.new()
	shape.radius = 0.4
	shape.height = 1.6
	collision.shape = shape
	collision.rotation.x = PI / 2  # Lying down
	corpse.add_child(collision)

	# Add to world
	if GameState.world_node:
		GameState.world_node.add_child(corpse)

	# Register entity
	var net_id := register_entity(corpse, EntityType.CORPSE)

	# Add loot component (scrap for team currency)
	var loot_value := _get_zombie_loot_value(zombie_type)
	add_component(net_id, "loot", {
		"items": {"scrap": loot_value},
		"looted": false
	})

	# Add rigid component (not rigid yet)
	add_component(net_id, "rigid", {"is_rigid": false})

	# Also spawn individual loot drops (Tarkov-style items for player inventory)
	_spawn_zombie_loot_drops(position, zombie_type)

	return corpse


## Spawn individual loot drops from zombie death (Tarkov-style)
func _spawn_zombie_loot_drops(position: Vector3, zombie_type: String) -> void:
	# Get possible loot based on zombie type
	var loot_table := _get_zombie_loot_table(zombie_type)

	# Roll for each loot entry
	for entry in loot_table:
		if randf() < entry.chance:
			var drop_pos := position + Vector3(
				randf_range(-0.5, 0.5),
				0.2,
				randf_range(-0.5, 0.5)
			)
			spawn_loot_drop(drop_pos, entry.def_id, entry.get("stack", 1))


## Get loot table for zombie type
func _get_zombie_loot_table(zombie_type: String) -> Array:
	match zombie_type:
		"walker":
			return [
				{"def_id": "ammo_pistol", "chance": 0.15, "stack": randi_range(2, 5)},
				{"def_id": "bandage", "chance": 0.10, "stack": 1},
				{"def_id": "scrap_metal", "chance": 0.20, "stack": randi_range(1, 3)},
			]
		"runner":
			return [
				{"def_id": "ammo_pistol", "chance": 0.20, "stack": randi_range(3, 8)},
				{"def_id": "energy_drink", "chance": 0.15, "stack": 1},
				{"def_id": "scrap_metal", "chance": 0.25, "stack": randi_range(2, 4)},
			]
		"brute":
			return [
				{"def_id": "ammo_rifle", "chance": 0.30, "stack": randi_range(5, 15)},
				{"def_id": "medkit", "chance": 0.20, "stack": 1},
				{"def_id": "armor_plate", "chance": 0.10, "stack": 1},
				{"def_id": "scrap_metal", "chance": 0.40, "stack": randi_range(3, 6)},
			]
		"crawler":
			return [
				{"def_id": "ammo_pistol", "chance": 0.10, "stack": randi_range(1, 3)},
				{"def_id": "scrap_metal", "chance": 0.15, "stack": 1},
			]
		_:
			return [
				{"def_id": "scrap_metal", "chance": 0.20, "stack": 1},
			]


## Spawn a loot pickup in the world
func spawn_loot_drop(position: Vector3, def_id: String, stack: int = 1, durability: float = 1.0, mods: Array = []) -> Node3D:
	if not NetworkManager.is_authority():
		return null

	# Load LootPickup script
	var LootPickupScript: GDScript = null
	if ResourceLoader.exists("res://scripts/world/loot_pickup.gd"):
		LootPickupScript = load("res://scripts/world/loot_pickup.gd")

	if not LootPickupScript:
		push_warning("[EntityRegistry] LootPickup script not found, skipping drop")
		return null

	var loot: Area3D = LootPickupScript.new()
	loot.name = "Loot_%d" % _next_id
	loot.global_position = position

	# Add to world
	if GameState.world_node:
		GameState.world_node.add_child(loot)
	else:
		push_error("[EntityRegistry] No world_node for loot drop")
		loot.queue_free()
		return null

	# Initialize loot data
	loot.setup(def_id, stack, durability, mods)

	# Register entity
	var net_id := register_entity(loot, EntityType.LOOTBAG)
	loot.loot_id = net_id

	# Add loot component
	add_component(net_id, "loot", {
		"def_id": def_id,
		"stack": stack,
		"durability": durability,
		"mods": mods,
		"picked_up": false
	})

	# Broadcast loot spawned
	_broadcast_entity_event.rpc(net_id, "loot_spawned", {
		"position": position,
		"def_id": def_id,
		"stack": stack
	})

	print("[EntityRegistry] Spawned loot: %s x%d at %s" % [def_id, stack, position])
	return loot


## Remove loot from world (called when picked up)
func remove_loot(net_id: int) -> void:
	if not NetworkManager.is_authority():
		return

	if net_id in entities:
		var loot: Node = entities[net_id]
		if is_instance_valid(loot):
			loot.queue_free()
		unregister_entity(net_id)


## Spawn a shop at position
func spawn_shop(position: Vector3, catalog: Array = []) -> Node3D:
	if not NetworkManager.is_authority():
		return null

	var shop := StaticBody3D.new()
	shop.name = "Shop_%d" % _next_id
	shop.global_position = position

	# Add collision shape
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(2, 2, 1)
	collision.shape = shape
	shop.add_child(collision)

	# Add to world
	if GameState.world_node:
		GameState.world_node.add_child(shop)

	# Register entity
	var net_id := register_entity(shop, EntityType.SHOP)

	# Add shop component
	add_component(net_id, "shop", {
		"catalog": catalog if not catalog.is_empty() else _get_default_catalog()
	})

	return shop


## Spawn a turret at position
func _spawn_turret(position: Vector3, rotation: float, owner_peer: int) -> Node3D:
	var turret := StaticBody3D.new()
	turret.name = "Turret_%d" % _next_id
	turret.global_position = position
	turret.rotation.y = rotation

	# Add collision shape
	var collision := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = 0.5
	shape.height = 1.0
	collision.shape = shape
	turret.add_child(collision)

	# Add to world
	if GameState.world_node:
		GameState.world_node.add_child(turret)

	# Register entity
	var net_id := register_entity(turret, EntityType.TURRET, owner_peer)

	# Add components
	add_component(net_id, "health", {"hp": 100, "max_hp": 100})
	add_component(net_id, "weapon", {
		"damage": 10,
		"fire_rate": 5.0,
		"range": 20.0,
		"ammo": 100,
		"max_ammo": 100
	})
	add_component(net_id, "targeting", {
		"target_net_id": -1,
		"last_fire": 0.0
	})

	# Broadcast turret spawned
	_broadcast_entity_event.rpc(net_id, "turret_spawned", {
		"position": position,
		"rotation": rotation,
		"owner": owner_peer
	})

	return turret


# ============================================
# TURRET AI (Server-side)
# ============================================

func process_turrets(delta: float) -> void:
	if not NetworkManager.is_authority():
		return

	for net_id in entity_types:
		if entity_types[net_id] != EntityType.TURRET:
			continue

		if net_id not in entities:
			continue

		var turret: Node3D = entities[net_id]
		if not is_instance_valid(turret):
			continue

		_update_turret(net_id, turret, delta)


func _update_turret(net_id: int, turret: Node3D, delta: float) -> void:
	var weapon := get_component(net_id, "weapon")
	var targeting := get_component(net_id, "targeting")

	var ammo: int = weapon.get("ammo", 0)
	if ammo <= 0:
		return

	var fire_rate: float = weapon.get("fire_rate", 5.0)
	var damage: float = weapon.get("damage", 10)
	var range_sq: float = weapon.get("range", 20.0) ** 2
	var last_fire: float = targeting.get("last_fire", 0.0)
	var current_time := Time.get_ticks_msec() / 1000.0

	if current_time - last_fire < 1.0 / fire_rate:
		return

	# Find nearest zombie
	var nearest_zombie: Node3D = null
	var nearest_dist_sq := range_sq

	for zombie_id in GameState.zombies:
		var zombie: Node3D = GameState.zombies[zombie_id]
		if not is_instance_valid(zombie):
			continue

		var dist_sq := turret.global_position.distance_squared_to(zombie.global_position)
		if dist_sq < nearest_dist_sq:
			nearest_dist_sq = dist_sq
			nearest_zombie = zombie

	if nearest_zombie == null:
		return

	# Fire!
	update_component(net_id, "weapon", {"ammo": ammo - 1})
	update_component(net_id, "targeting", {"last_fire": current_time})

	# Damage zombie
	if nearest_zombie.has_method("take_damage"):
		nearest_zombie.take_damage(damage, turret.global_position)

	# Broadcast fire event
	_broadcast_entity_event.rpc(net_id, "turret_fire", {
		"target_position": nearest_zombie.global_position
	})


# ============================================
# HELPERS
# ============================================

func _get_default_catalog() -> Array:
	return [
		{"id": "ammo_rifle", "name": "Rifle Ammo", "price": 5, "type": "ammo"},
		{"id": "ammo_shotgun", "name": "Shotgun Shells", "price": 8, "type": "ammo"},
		{"id": "ammo_pistol", "name": "Pistol Ammo", "price": 3, "type": "ammo"},
		{"id": "medkit", "name": "Medkit", "price": 25, "type": "heal"},
		{"id": "turret", "name": "Turret", "price": 50, "type": "deployable"},
		{"id": "nails", "name": "Nails (10)", "price": 10, "type": "material"},
	]


func _get_sell_value(item_id: String) -> int:
	match item_id:
		"scrap": return 1
		"ammo_rifle", "ammo_pistol": return 2
		"ammo_shotgun": return 4
		_: return 1


func _get_zombie_loot_value(zombie_type: String) -> int:
	match zombie_type:
		"walker": return randi_range(1, 3)
		"runner": return randi_range(2, 5)
		"brute": return randi_range(5, 10)
		"crawler": return randi_range(1, 2)
		_: return 2


func _give_item_to_player(peer_id: int, item_id: String, quantity: int) -> void:
	# For now, broadcast that player received item
	# Full inventory integration would go here
	_broadcast_entity_event.rpc(peer_id, "item_received", {
		"item_id": item_id,
		"quantity": quantity
	})


func _type_to_string(type: EntityType) -> String:
	match type:
		EntityType.PLAYER: return "player"
		EntityType.ZOMBIE: return "zombie"
		EntityType.PROP: return "prop"
		EntityType.CORPSE: return "corpse"
		EntityType.TURRET: return "turret"
		EntityType.SHOP: return "shop"
		EntityType.NAIL: return "nail"
		EntityType.LOOTBAG: return "lootbag"
	return "unknown"


# ============================================
# NETWORK CALLBACKS
# ============================================

func _on_player_joined(peer_id: int) -> void:
	if not NetworkManager.is_authority():
		return

	# Register player as entity
	if peer_id in GameState.players:
		var player: Node3D = GameState.players[peer_id]
		register_entity(player, EntityType.PLAYER, peer_id)

	# Sync existing entity state to late joiner (after a short delay to ensure player is ready)
	await get_tree().create_timer(0.5).timeout
	sync_to_client(peer_id)


func _on_player_left(peer_id: int) -> void:
	# Clean up player's phasing state
	if peer_id in phasing_players:
		phasing_players.erase(peer_id)

	# Find and unregister player entity
	for net_id in entity_owners.keys():
		if entity_owners[net_id] == peer_id and entity_types.get(net_id) == EntityType.PLAYER:
			unregister_entity(net_id)
			break


# ============================================
# RPCs - Client broadcasts
# ============================================

@rpc("authority", "reliable")
func _broadcast_entity_registered(net_id: int, type: EntityType, owner_peer: int) -> void:
	# Client receives registration
	entity_types[net_id] = type
	if owner_peer > 0:
		entity_owners[net_id] = owner_peer
	entity_registered.emit(net_id, _type_to_string(type))


@rpc("authority", "reliable")
func _broadcast_entity_unregistered(net_id: int) -> void:
	entity_types.erase(net_id)
	entity_owners.erase(net_id)
	entities.erase(net_id)
	entity_unregistered.emit(net_id)


@rpc("authority", "reliable")
func _broadcast_entity_event(net_id: int, event: String, payload: Dictionary) -> void:
	entity_event_received.emit(net_id, event, payload)

	# Handle specific events client-side
	match event:
		"phase_started":
			# Visual feedback for phasing
			pass
		"looted":
			# Update team currency display
			team_currency = payload.get("team_currency", team_currency)
		"item_purchased", "item_sold":
			team_currency = payload.get("team_currency", team_currency)


@rpc("authority", "reliable")
func _send_interact_result(net_id: int, action: String, success: bool, data: Dictionary) -> void:
	interaction_result.emit(net_id, action, success, data)


# ============================================
# PUBLIC API
# ============================================

func get_team_currency() -> int:
	return team_currency


func reset_for_new_round() -> void:
	if not NetworkManager.is_authority():
		return

	# Clear all non-player, non-prop entities
	var to_remove := []
	for net_id in entity_types:
		var type: int = entity_types[net_id]
		if type != EntityType.PLAYER and type != EntityType.PROP:
			to_remove.append(net_id)

	for net_id in to_remove:
		var entity: Node = entities.get(net_id)
		if is_instance_valid(entity):
			entity.queue_free()
		unregister_entity(net_id)

	# Reset currency
	team_currency = STARTING_CURRENCY
	phasing_players.clear()


# ============================================
# LATE JOINER SYNC (Foot-gun #1 fix)
# ============================================

## Serialize all entities for late joiner sync
func serialize_all() -> Dictionary:
	var entity_list := []

	for net_id in entities:
		if not is_instance_valid(entities[net_id]):
			continue

		var entity: Node = entities[net_id]
		var type: EntityType = entity_types.get(net_id, EntityType.PROP)

		var entity_data := {
			"net_id": net_id,
			"type": type,
			"owner": entity_owners.get(net_id, -1),
			"components": entity_components.get(net_id, {}),
		}

		# Add transform for 3D entities
		if entity is Node3D:
			entity_data["position"] = entity.global_position
			entity_data["rotation"] = entity.rotation

		entity_list.append(entity_data)

	# Include phasing players state
	var phasing_list := []
	for peer_id in phasing_players:
		phasing_list.append({
			"peer_id": peer_id,
			"end_time": phasing_players[peer_id].end_time
		})

	return {
		"entities": entity_list,
		"team_currency": team_currency,
		"phasing_players": phasing_list,
		"next_id": _next_id
	}


## Send full entity state to a specific client (server calls this on player join)
func sync_to_client(peer_id: int) -> void:
	if not NetworkManager.is_authority():
		return

	var snapshot := serialize_all()
	_receive_entity_snapshot.rpc_id(peer_id, snapshot)
	print("[EntityRegistry] Synced %d entities to peer %d" % [snapshot.entities.size(), peer_id])


## Client receives full entity state (late joiner)
@rpc("authority", "reliable")
func _receive_entity_snapshot(snapshot: Dictionary) -> void:
	print("[EntityRegistry] Receiving entity snapshot...")

	# Apply team currency
	team_currency = snapshot.get("team_currency", STARTING_CURRENCY)

	# Apply next_id to prevent collisions
	_next_id = maxi(_next_id, snapshot.get("next_id", 1))

	# Rebuild entity tracking (NOT spawning - that's GameState's job)
	var entity_list: Array = snapshot.get("entities", [])
	for entity_data in entity_list:
		var net_id: int = entity_data.get("net_id", -1)
		var type: EntityType = entity_data.get("type", EntityType.PROP) as EntityType
		var owner: int = entity_data.get("owner", -1)
		var components: Dictionary = entity_data.get("components", {})

		# Store tracking info (entity nodes are spawned by GameState.apply_full_snapshot)
		entity_types[net_id] = type
		if owner > 0:
			entity_owners[net_id] = owner
		entity_components[net_id] = components

	# Apply phasing state (for visual feedback)
	var phasing_list: Array = snapshot.get("phasing_players", [])
	for phasing_data in phasing_list:
		var peer_id: int = phasing_data.get("peer_id", -1)
		if peer_id > 0:
			# Store for visual purposes (actual collision is server-side)
			phasing_players[peer_id] = {
				"end_time": phasing_data.get("end_time", 0.0),
				"original_mask": 0  # Not needed client-side
			}

	print("[EntityRegistry] Applied snapshot: %d entities, %d currency" % [entity_list.size(), team_currency])


## Check if a player is currently phasing (for visual feedback)
func is_player_phasing(peer_id: int) -> bool:
	return peer_id in phasing_players
