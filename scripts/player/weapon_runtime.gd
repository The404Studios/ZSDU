extends RefCounted
class_name WeaponRuntime
## WeaponRuntime - Ephemeral weapon state during raid
##
## Pure data + logic for a single weapon.
## No persistence, no backend calls.

# Weapon identity
var iid: String = ""
var def_id: String = ""
var name: String = ""

# Weapon stats (from item def)
var damage: float = 25.0
var fire_rate: float = 0.1  # Seconds between shots
var magazine_size: int = 30
var reload_time: float = 2.5
var base_spread: float = 0.02  # Radians
var ads_spread_mult: float = 0.3
var ammo_type: String = "9mm"
var weapon_type: String = "rifle"  # rifle, pistol, shotgun, smg, melee

# Current state
var current_ammo: int = 30
var chambered: bool = true
var durability: float = 1.0

# Mods (affects stats)
var mods: Array = []


func initialize(item_data: Dictionary, item_def: Dictionary) -> void:
	iid = item_data.get("iid", "")
	def_id = item_data.get("def_id", item_data.get("defId", ""))
	name = item_def.get("name", def_id)

	# Load stats from def
	damage = item_def.get("damage", 25.0)
	fire_rate = item_def.get("fire_rate", 0.1)
	magazine_size = item_def.get("magazine_size", 30)
	reload_time = item_def.get("reload_time", 2.5)
	base_spread = item_def.get("spread", 0.02)
	ads_spread_mult = item_def.get("ads_spread_mult", 0.3)
	ammo_type = item_def.get("ammo_type", "9mm")
	weapon_type = item_def.get("weapon_type", "rifle")

	# Load current state from item instance
	current_ammo = item_data.get("current_ammo", magazine_size)
	chambered = item_data.get("chambered", true)
	durability = item_data.get("durability", 1.0)
	mods = item_data.get("mods", [])

	# Apply mod effects
	_apply_mods()


func _apply_mods() -> void:
	# Apply stat modifications from attached mods
	for mod in mods:
		var mod_type: String = mod.get("type", "")
		var mod_value: float = mod.get("value", 0)

		match mod_type:
			"damage_mult":
				damage *= mod_value
			"fire_rate_mult":
				fire_rate *= mod_value
			"magazine_size":
				magazine_size += int(mod_value)
			"spread_mult":
				base_spread *= mod_value
			"reload_speed_mult":
				reload_time *= mod_value


## Check if weapon can fire
func can_fire() -> bool:
	if weapon_type == "melee":
		return true  # Melee always "fires"

	return chambered and current_ammo > 0 and durability > 0


## Check if magazine is empty
func is_magazine_empty() -> bool:
	return current_ammo <= 0


## Check if chamber is empty
func is_chamber_empty() -> bool:
	return not chambered


## Check if magazine is full
func is_magazine_full() -> bool:
	return current_ammo >= magazine_size


## Consume a round (fire)
func consume_round() -> void:
	if weapon_type == "melee":
		# Melee degrades durability instead
		durability = maxf(0, durability - 0.01)
		return

	if current_ammo > 0:
		current_ammo -= 1

		# For semi-auto, the next round is auto-chambered
		# For bolt/pump, chambered = false until chamber() is called
		if weapon_type in ["bolt", "pump", "revolver"]:
			chambered = false
		else:
			chambered = current_ammo > 0

		# Slight durability loss
		durability = maxf(0, durability - 0.001)


## Chamber a round (bolt-action, pump-action)
func chamber() -> void:
	if current_ammo > 0:
		chambered = true


## Add ammo to magazine
func add_ammo(count: int) -> void:
	current_ammo = mini(current_ammo + count, magazine_size)
	if current_ammo > 0:
		chambered = true


## Get spread based on ADS state
func get_spread(is_ads: bool) -> float:
	if is_ads:
		return base_spread * ads_spread_mult
	return base_spread


## Get state for network sync
func get_state() -> Dictionary:
	return {
		"iid": iid,
		"ammo": current_ammo,
		"chambered": chambered,
		"durability": durability,
	}


## Apply state from network
func apply_state(state: Dictionary) -> void:
	current_ammo = state.get("ammo", current_ammo)
	chambered = state.get("chambered", chambered)
	durability = state.get("durability", durability)
