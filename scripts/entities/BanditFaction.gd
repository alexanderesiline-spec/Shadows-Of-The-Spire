extends Node2D

@export var faction_name: String = "Raiders"
@export var population: int = 8
@export var food_supplies: float = 40.0
@export var gold: float = 20.0
@export var morale: float = 60.0

# Needs thresholds that drive emergent behavior
const FOOD_PER_BANDIT_PER_HOUR: float = 0.12
const RAID_FOOD_THRESHOLD: float = 30.0   # raid when food drops below this
const RAID_GOLD_THRESHOLD: float = 15.0   # also raid when gold is very low
const RAID_COOLDOWN_HOURS: int = 14       # can't raid again for this many hours
const RECRUIT_COST_GOLD: float = 8.0
const RECRUIT_CHANCE_PER_DAY: float = 0.2  # higher population = more likely to recruit
const MIN_RAID_FORCE: int = 3

var _raid_cooldown: int = 0
var _is_raiding: bool = false

func _ready() -> void:
	WorldSimulation.register_faction(self)
	_build_visual()

func _exit_tree() -> void:
	WorldSimulation.unregister_faction(self)

func _build_visual() -> void:
	# Tent / camp marker
	var tent := Polygon2D.new()
	tent.polygon = PackedVector2Array([
		Vector2(-18, 12), Vector2(0, -22), Vector2(18, 12)
	])
	tent.color = Color(0.7, 0.28, 0.08)
	add_child(tent)

	# Small campfire dot
	var fire := Polygon2D.new()
	fire.polygon = PackedVector2Array([
		Vector2(-4, 18), Vector2(4, 18), Vector2(2, 12), Vector2(-2, 12)
	])
	fire.color = Color(1.0, 0.55, 0.1)
	add_child(fire)

	var label := Label.new()
	label.text = faction_name
	label.position = Vector2(-40, 22)
	label.add_theme_font_size_override("font_size", 11)
	label.add_theme_color_override("font_color", Color(1.0, 0.6, 0.4))
	add_child(label)

func simulate_hour(hour: int) -> void:
	# Consume food every hour
	food_supplies = maxf(0.0, food_supplies - population * FOOD_PER_BANDIT_PER_HOUR)

	# Morale drops when starving
	if food_supplies < 5.0:
		morale = maxf(0.0, morale - 3.0)
	elif food_supplies > 60.0:
		morale = minf(100.0, morale + 0.5)

	if _raid_cooldown > 0:
		_raid_cooldown -= 1
		return

	# Emergent raid decision: hungry OR broke AND have enough fighters
	var need_food := food_supplies < RAID_FOOD_THRESHOLD
	var need_gold := gold < RAID_GOLD_THRESHOLD and food_supplies < 60.0
	var can_raid  := population >= MIN_RAID_FORCE and not _is_raiding

	if (need_food or need_gold) and can_raid:
		_attempt_raid()

func simulate_day(day: int, season: String) -> void:
	# Harsher winters mean bandits get desperate faster
	if season == "Winter":
		food_supplies = maxf(0.0, food_supplies - population * 0.8)
		morale = maxf(0.0, morale - 4.0)
		if food_supplies < 20.0:
			EventBus.log_warning("[%s] Desperate in winter — starvation forcing them to raid harder." % faction_name)

	# Recruitment: spend gold to grow the faction
	if randf() < RECRUIT_CHANCE_PER_DAY and gold >= RECRUIT_COST_GOLD and morale > 30.0:
		population += 1
		gold -= RECRUIT_COST_GOLD
		EventBus.faction_grew.emit(faction_name, population)
		EventBus.log_info("[%s] Recruited a new member. Now %d strong." % [faction_name, population])

func _attempt_raid() -> void:
	var target := WorldSimulation.get_nearest_village(global_position)
	if target == null:
		return

	_is_raiding = true
	_raid_cooldown = RAID_COOLDOWN_HOURS

	var reason := "starving (food: %.0f)" % food_supplies if food_supplies < RAID_FOOD_THRESHOLD \
				  else "broke (gold: %.0f)" % gold

	EventBus.raid_started.emit(faction_name, target.village_name)
	EventBus.log_danger("[RAID] %s (%d fighters, %s) attacks %s!" % [
		faction_name, population, reason, target.village_name
	])

	var loot := target.receive_raid(population)
	food_supplies = minf(food_supplies + loot.food, 120.0)
	gold += loot.gold
	morale = minf(100.0, morale + 20.0)

	EventBus.raid_ended.emit(faction_name, target.village_name, loot)
	EventBus.log_danger("[RAID] %s looted %.0f food + %.0f gold from %s." % [
		faction_name, loot.food, loot.gold, target.village_name
	])

	_is_raiding = false

func get_status_short() -> String:
	var state := "raiding" if _is_raiding else ("cooldown" if _raid_cooldown > 0 else "watching")
	return "%s — Pop:%d Food:%.0f Gold:%.0f Morale:%.0f [%s]" % [
		faction_name, population, food_supplies, gold, morale, state
	]
