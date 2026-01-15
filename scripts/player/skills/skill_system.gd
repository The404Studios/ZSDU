extends Node
class_name SkillSystem
## SkillSystem - RPG skill progression with categories and prestige
##
## Features:
## - 4 main categories: OFFENSE, DEFENSE, HANDLING, CONDITIONING
## - Budget system determines skill power/quality
## - Prestige system for subclass determination
## - Skill tiers with accumulated budget
## - Major skills, major attributes, skill sets

signal skill_upgraded(category: String, skill_id: String, new_level: int)
signal budget_changed(category: String, new_budget: float)
signal prestige_level_changed(new_level: int)
signal subclass_unlocked(subclass_name: String)
signal skill_points_changed(new_points: int)

# Categories
enum Category {
	OFFENSE,
	DEFENSE,
	HANDLING,
	CONDITIONING
}

const CATEGORY_NAMES := {
	Category.OFFENSE: "Offense",
	Category.DEFENSE: "Defense",
	Category.HANDLING: "Handling",
	Category.CONDITIONING: "Conditioning"
}

const CATEGORY_COLORS := {
	Category.OFFENSE: Color(0.9, 0.3, 0.3),
	Category.DEFENSE: Color(0.3, 0.5, 0.9),
	Category.HANDLING: Color(0.3, 0.8, 0.4),
	Category.CONDITIONING: Color(0.9, 0.7, 0.2)
}

# Skill tier thresholds
const TIER_THRESHOLDS := [0, 100, 300, 600, 1000, 1500]  # Budget needed for each tier
const MAX_SKILL_LEVEL := 10
const BASE_SKILL_COST := 1  # Skill points per level
const LEVEL_COST_SCALING := 1.5  # Each level costs more

# State
var prestige_level: int = 0
var skill_points: int = 0
var total_xp: int = 0

# Category budgets (accumulated from leveling skills in that category)
var category_budgets: Dictionary = {
	Category.OFFENSE: 0.0,
	Category.DEFENSE: 0.0,
	Category.HANDLING: 0.0,
	Category.CONDITIONING: 0.0
}

# Skill levels by category
var skills: Dictionary = {}  # category -> {skill_id -> level}

# Delay penalty tracking (skills become harder if not leveled right away)
var skill_delay_penalties: Dictionary = {}  # skill_id -> penalty_multiplier

# Subclass (determined by budget distribution)
var current_subclass: String = ""
var subclass_quality: String = "C"  # A, B, or C based on budget


func _init() -> void:
	_initialize_skills()


func _initialize_skills() -> void:
	# Initialize all skill categories
	skills = {
		Category.OFFENSE: {
			"damage_boost": 0,
			"critical_chance": 0,
			"critical_damage": 0,
			"penetration": 0,
			"fire_rate": 0,
			"reload_speed": 0,
		},
		Category.DEFENSE: {
			"health_boost": 0,
			"armor_rating": 0,
			"damage_reduction": 0,
			"bleed_resistance": 0,
			"stagger_resistance": 0,
			"regeneration": 0,
		},
		Category.HANDLING: {
			"accuracy": 0,
			"recoil_control": 0,
			"swap_speed": 0,
			"aim_stability": 0,
			"movement_accuracy": 0,
			"quick_scope": 0,
		},
		Category.CONDITIONING: {
			"stamina_boost": 0,
			"stamina_regen": 0,
			"movement_speed": 0,
			"sprint_duration": 0,
			"jump_height": 0,
			"noise_reduction": 0,
		}
	}


## Get skill level
func get_skill_level(category: Category, skill_id: String) -> int:
	if category in skills and skill_id in skills[category]:
		return skills[category][skill_id]
	return 0


## Upgrade a skill
func upgrade_skill(category: Category, skill_id: String) -> bool:
	if not can_upgrade_skill(category, skill_id):
		return false

	var current_level: int = skills[category][skill_id]
	var cost := get_skill_upgrade_cost(category, skill_id)

	# Deduct skill points
	skill_points -= cost
	skill_points_changed.emit(skill_points)

	# Increase level
	skills[category][skill_id] = current_level + 1

	# Add budget to category (budget = level * base_value * penalty)
	var penalty: float = skill_delay_penalties.get(skill_id, 1.0)
	var budget_gain: float = 10.0 * (current_level + 1) / penalty
	category_budgets[category] += budget_gain
	budget_changed.emit(CATEGORY_NAMES[category], category_budgets[category])

	# Increase delay penalty for next level (harder if you wait)
	skill_delay_penalties[skill_id] = skill_delay_penalties.get(skill_id, 1.0) + 0.1

	# Update subclass
	_update_subclass()

	skill_upgraded.emit(CATEGORY_NAMES[category], skill_id, current_level + 1)
	return true


## Check if skill can be upgraded
func can_upgrade_skill(category: Category, skill_id: String) -> bool:
	if category not in skills or skill_id not in skills[category]:
		return false

	var current_level: int = skills[category][skill_id]
	if current_level >= MAX_SKILL_LEVEL:
		return false

	var cost := get_skill_upgrade_cost(category, skill_id)
	return skill_points >= cost


## Get cost to upgrade skill
func get_skill_upgrade_cost(category: Category, skill_id: String) -> int:
	var current_level: int = skills[category].get(skill_id, 0)
	var base_cost: float = BASE_SKILL_COST * pow(LEVEL_COST_SCALING, current_level)
	var penalty: float = skill_delay_penalties.get(skill_id, 1.0)
	return int(ceil(base_cost * penalty))


## Add skill points
func add_skill_points(points: int) -> void:
	skill_points += points
	skill_points_changed.emit(skill_points)


## Add XP (used for leveling)
func add_xp(xp: int) -> void:
	total_xp += xp
	# Award skill points at XP thresholds
	var xp_per_point := 100 + (prestige_level * 50)
	var points_earned := total_xp / xp_per_point
	if points_earned > skill_points:
		var new_points := points_earned - skill_points
		add_skill_points(new_points)


## Get current tier for a category
func get_category_tier(category: Category) -> int:
	var budget: float = category_budgets.get(category, 0.0)
	for i in range(TIER_THRESHOLDS.size() - 1, -1, -1):
		if budget >= TIER_THRESHOLDS[i]:
			return i
	return 0


## Get budget percentage to next tier
func get_tier_progress(category: Category) -> float:
	var budget: float = category_budgets.get(category, 0.0)
	var current_tier := get_category_tier(category)

	if current_tier >= TIER_THRESHOLDS.size() - 1:
		return 1.0

	var current_threshold: float = TIER_THRESHOLDS[current_tier]
	var next_threshold: float = TIER_THRESHOLDS[current_tier + 1]
	var range_size: float = next_threshold - current_threshold

	return clampf((budget - current_threshold) / range_size, 0.0, 1.0)


## Update subclass based on budget distribution
func _update_subclass() -> void:
	var total_budget: float = 0.0
	var highest_category: Category = Category.OFFENSE
	var highest_budget: float = 0.0

	for cat in category_budgets:
		var budget: float = category_budgets[cat]
		total_budget += budget
		if budget > highest_budget:
			highest_budget = budget
			highest_category = cat

	# Determine subclass quality based on total budget
	if total_budget >= 3000:
		subclass_quality = "A"
	elif total_budget >= 1500:
		subclass_quality = "B"
	else:
		subclass_quality = "C"

	# Determine subclass name based on dominant category
	var old_subclass := current_subclass
	match highest_category:
		Category.OFFENSE:
			current_subclass = "Striker"
		Category.DEFENSE:
			current_subclass = "Guardian"
		Category.HANDLING:
			current_subclass = "Marksman"
		Category.CONDITIONING:
			current_subclass = "Runner"

	if current_subclass != old_subclass and old_subclass != "":
		subclass_unlocked.emit(current_subclass)


## Prestige (reset skills, gain permanent bonuses)
func prestige() -> bool:
	# Require certain conditions
	var total_budget: float = 0.0
	for cat in category_budgets:
		total_budget += category_budgets[cat]

	if total_budget < 2000:
		return false

	prestige_level += 1

	# Reset skills but keep some budget as bonus
	var kept_budget: float = total_budget * 0.1 * prestige_level

	_initialize_skills()
	skill_delay_penalties.clear()

	# Distribute kept budget evenly
	for cat in category_budgets:
		category_budgets[cat] = kept_budget / 4.0
		budget_changed.emit(CATEGORY_NAMES[cat], category_budgets[cat])

	skill_points = prestige_level * 5  # Bonus starting points
	skill_points_changed.emit(skill_points)

	prestige_level_changed.emit(prestige_level)
	return true


## Get derived stat bonuses from skills
func get_stat_bonuses() -> Dictionary:
	var bonuses := {}

	# Offense bonuses
	bonuses["damage_mult"] = 1.0 + get_skill_level(Category.OFFENSE, "damage_boost") * 0.05
	bonuses["crit_chance"] = get_skill_level(Category.OFFENSE, "critical_chance") * 0.02
	bonuses["crit_damage"] = 1.5 + get_skill_level(Category.OFFENSE, "critical_damage") * 0.1
	bonuses["armor_pen"] = get_skill_level(Category.OFFENSE, "penetration") * 0.03
	bonuses["fire_rate_mult"] = 1.0 + get_skill_level(Category.OFFENSE, "fire_rate") * 0.03
	bonuses["reload_speed_mult"] = 1.0 + get_skill_level(Category.OFFENSE, "reload_speed") * 0.05

	# Defense bonuses
	bonuses["health_mult"] = 1.0 + get_skill_level(Category.DEFENSE, "health_boost") * 0.05
	bonuses["armor_bonus"] = get_skill_level(Category.DEFENSE, "armor_rating") * 2
	bonuses["damage_reduction"] = get_skill_level(Category.DEFENSE, "damage_reduction") * 0.02
	bonuses["bleed_resist"] = get_skill_level(Category.DEFENSE, "bleed_resistance") * 0.1
	bonuses["stagger_resist"] = get_skill_level(Category.DEFENSE, "stagger_resistance") * 0.1
	bonuses["health_regen"] = get_skill_level(Category.DEFENSE, "regeneration") * 0.5

	# Handling bonuses
	bonuses["accuracy_mult"] = 1.0 + get_skill_level(Category.HANDLING, "accuracy") * 0.05
	bonuses["recoil_mult"] = 1.0 - get_skill_level(Category.HANDLING, "recoil_control") * 0.05
	bonuses["swap_speed_mult"] = 1.0 + get_skill_level(Category.HANDLING, "swap_speed") * 0.1
	bonuses["aim_stability"] = get_skill_level(Category.HANDLING, "aim_stability") * 0.05
	bonuses["move_accuracy"] = get_skill_level(Category.HANDLING, "movement_accuracy") * 0.05
	bonuses["ads_speed_mult"] = 1.0 + get_skill_level(Category.HANDLING, "quick_scope") * 0.1

	# Conditioning bonuses
	bonuses["stamina_mult"] = 1.0 + get_skill_level(Category.CONDITIONING, "stamina_boost") * 0.05
	bonuses["stamina_regen_mult"] = 1.0 + get_skill_level(Category.CONDITIONING, "stamina_regen") * 0.05
	bonuses["move_speed_mult"] = 1.0 + get_skill_level(Category.CONDITIONING, "movement_speed") * 0.02
	bonuses["sprint_mult"] = 1.0 + get_skill_level(Category.CONDITIONING, "sprint_duration") * 0.05
	bonuses["jump_mult"] = 1.0 + get_skill_level(Category.CONDITIONING, "jump_height") * 0.03
	bonuses["noise_mult"] = 1.0 - get_skill_level(Category.CONDITIONING, "noise_reduction") * 0.05

	# Prestige bonuses (small permanent bonuses)
	bonuses["prestige_damage"] = prestige_level * 0.02
	bonuses["prestige_health"] = prestige_level * 0.02
	bonuses["prestige_xp"] = prestige_level * 0.05

	return bonuses


## Get save data
func get_save_data() -> Dictionary:
	return {
		"prestige_level": prestige_level,
		"skill_points": skill_points,
		"total_xp": total_xp,
		"category_budgets": category_budgets.duplicate(),
		"skills": skills.duplicate(true),
		"skill_delay_penalties": skill_delay_penalties.duplicate(),
		"current_subclass": current_subclass,
		"subclass_quality": subclass_quality
	}


## Load save data
func load_save_data(data: Dictionary) -> void:
	prestige_level = data.get("prestige_level", 0)
	skill_points = data.get("skill_points", 0)
	total_xp = data.get("total_xp", 0)

	var saved_budgets: Dictionary = data.get("category_budgets", {})
	for cat in category_budgets:
		category_budgets[cat] = saved_budgets.get(cat, 0.0)

	var saved_skills: Dictionary = data.get("skills", {})
	for cat in skills:
		if cat in saved_skills:
			for skill_id in skills[cat]:
				if skill_id in saved_skills[cat]:
					skills[cat][skill_id] = saved_skills[cat][skill_id]

	skill_delay_penalties = data.get("skill_delay_penalties", {}).duplicate()
	current_subclass = data.get("current_subclass", "")
	subclass_quality = data.get("subclass_quality", "C")
