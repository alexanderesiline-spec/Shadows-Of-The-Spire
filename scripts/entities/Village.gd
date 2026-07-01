extends Node2D

@export var village_name: String = "Village"
@export var population: int = 20
@export var food_stores: float = 100.0
@export var gold: float = 50.0
@export var livestock_count: int = 10

const MAX_FOOD: float = 250.0
const FOOD_PER_PERSON_PER_DAY: float = 1.0
const FOOD_FROM_FARMING_BASE: float = 15.0
const FOOD_FROM_LIVESTOCK: float = 0.5  # per animal per day
const GOLD_FROM_TRADE: float = 0.12     # per person per day

var _name_label: Label

func _ready() -> void:
	WorldSimulation.register_village(self)
	_build_visual()

func _exit_tree() -> void:
	WorldSimulation.unregister_village(self)

func _build_visual() -> void:
	# House body
	var body := Polygon2D.new()
	body.polygon = PackedVector2Array([
		Vector2(-20, 8), Vector2(20, 8),
		Vector2(20, -8), Vector2(-20, -8)
	])
	body.color = Color(0.65, 0.52, 0.35)
	add_child(body)

	# Roof triangle
	var roof := Polygon2D.new()
	roof.polygon = PackedVector2Array([
		Vector2(-23, -8), Vector2(0, -30), Vector2(23, -8)
	])
	roof.color = Color(0.72, 0.22, 0.18)
	add_child(roof)

	# Door
	var door := Polygon2D.new()
	door.polygon = PackedVector2Array([
		Vector2(-5, 8), Vector2(5, 8),
		Vector2(5, -2), Vector2(-5, -2)
	])
	door.color = Color(0.35, 0.22, 0.1)
	add_child(door)

	_name_label = Label.new()
	_name_label.text = village_name
	_name_label.position = Vector2(-40, 12)
	_name_label.add_theme_font_size_override("font_size", 11)
	_name_label.add_theme_color_override("font_color", Color(0.9, 0.85, 0.7))
	add_child(_name_label)

func simulate_day(day: int, season: String) -> void:
	var season_multiplier: float
	match season:
		"Winter":  season_multiplier = 0.25
		"Autumn":  season_multiplier = 0.85
		"Spring":  season_multiplier = 1.1
		_:         season_multiplier = 1.2  # Summer

	var produced := FOOD_FROM_FARMING_BASE * season_multiplier
	produced += livestock_count * FOOD_FROM_LIVESTOCK
	food_stores = minf(food_stores + produced, MAX_FOOD)

	var consumed := population * FOOD_PER_PERSON_PER_DAY
	food_stores -= consumed

	if food_stores <= 0.0:
		food_stores = 0.0
		EventBus.village_crisis.emit(village_name, "famine")
		EventBus.log_danger("[%s] Famine! No food left for %d people." % [village_name, population])
	elif food_stores < 25.0:
		EventBus.log_warning("[%s] Food dangerously low (%.0f). Vulnerable to raids." % [village_name, food_stores])

	gold += population * GOLD_FROM_TRADE

func receive_raid(attacker_strength: int) -> Dictionary:
	var food_stolen := minf(food_stores * 0.35, float(attacker_strength) * 6.0)
	var gold_stolen := minf(gold * 0.25, float(attacker_strength) * 3.0)
	food_stores = maxf(0.0, food_stores - food_stolen)
	gold = maxf(0.0, gold - gold_stolen)
	return {"food": food_stolen, "gold": gold_stolen}

func lose_livestock(count: int) -> void:
	var actual_lost := mini(count, livestock_count)
	livestock_count -= actual_lost
	if actual_lost > 0:
		EventBus.livestock_attacked.emit(village_name, actual_lost)

func get_status_short() -> String:
	var warning := ""
	if food_stores < 25.0:
		warning = " [LOW FOOD]"
	return "%s — Food:%.0f Gold:%.0f Pop:%d Livestock:%d%s" % [
		village_name, food_stores, gold, population, livestock_count, warning
	]
