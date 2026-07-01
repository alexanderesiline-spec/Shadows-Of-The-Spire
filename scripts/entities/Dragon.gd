extends Node2D

@export var dragon_name: String = "Ignarath"
@export var hunger: float = 20.0
@export var territory_radius: float = 600.0

# Hunger drives everything. If it gets too high, the dragon hunts.
const HUNGER_PER_HOUR: float = 1.2
const NIGHT_HUNGER_BONUS: float = 0.6     # more active after dark
const HUNT_THRESHOLD: float = 68.0        # starts hunting
const HUNGER_AFTER_FEEDING: float = 8.0
const LIVESTOCK_EATEN: int = 4
const HUNT_COOLDOWN_HOURS: int = 8
const TERRITORY_PATROL_CHANCE: float = 0.1  # chance to attack farms in territory regardless of hunger

var is_hunting: bool = false
var home_position: Vector2
var _hunt_cooldown: int = 0

func _ready() -> void:
	WorldSimulation.register_dragon(self)
	home_position = global_position
	_build_visual()

func _exit_tree() -> void:
	WorldSimulation.unregister_dragon(self)

func _build_visual() -> void:
	# Dragon silhouette (diamond body + wing hints)
	var body := Polygon2D.new()
	body.polygon = PackedVector2Array([
		Vector2(0, -22),   # head
		Vector2(18, 0),    # right wing tip
		Vector2(6, 18),    # tail right
		Vector2(0, 12),    # tail center
		Vector2(-6, 18),   # tail left
		Vector2(-18, 0),   # left wing tip
	])
	body.color = Color(0.45, 0.05, 0.65)
	add_child(body)

	# Eyes
	var eye_left := Polygon2D.new()
	eye_left.polygon = PackedVector2Array([
		Vector2(-5, -18), Vector2(-2, -18), Vector2(-2, -14), Vector2(-5, -14)
	])
	eye_left.color = Color(1.0, 0.3, 0.0)
	add_child(eye_left)

	var eye_right := Polygon2D.new()
	eye_right.polygon = PackedVector2Array([
		Vector2(2, -18), Vector2(5, -18), Vector2(5, -14), Vector2(2, -14)
	])
	eye_right.color = Color(1.0, 0.3, 0.0)
	add_child(eye_right)

	var label := Label.new()
	label.text = dragon_name
	label.position = Vector2(-40, 22)
	label.add_theme_font_size_override("font_size", 11)
	label.add_theme_color_override("font_color", Color(0.85, 0.5, 1.0))
	add_child(label)

func simulate_hour(hour: int) -> void:
	var gain := HUNGER_PER_HOUR
	if GameClock.is_night():
		gain += NIGHT_HUNGER_BONUS
	hunger = minf(100.0, hunger + gain)

	if _hunt_cooldown > 0:
		_hunt_cooldown -= 1
		return

	if is_hunting:
		return

	# Primary trigger: genuinely hungry
	var driven_by_hunger := hunger >= HUNT_THRESHOLD

	# Secondary trigger: territorial patrol even when not starving
	var territorial_strike := (randf() < TERRITORY_PATROL_CHANCE
		and WorldSimulation.get_total_world_livestock() > 5
		and hunger > 30.0)

	if driven_by_hunger or territorial_strike:
		_go_hunt(driven_by_hunger)

func _go_hunt(hungry: bool) -> void:
	# Prefer villages with livestock inside territory first, then anywhere
	var target := WorldSimulation.get_nearest_village(global_position, 1)
	if target == null:
		EventBus.log_info("[%s] Hungry (%.0f) but all livestock gone..." % [dragon_name, hunger])
		return

	is_hunting = true
	_hunt_cooldown = HUNT_COOLDOWN_HOURS

	var reason := "hunger (%.0f/100)" % hunger if hungry else "territorial patrol"
	EventBus.dragon_attack_started.emit(dragon_name, target.village_name)
	EventBus.log_danger("[DRAGON] %s descends on %s! Reason: %s." % [
		dragon_name, target.village_name, reason
	])

	target.lose_livestock(LIVESTOCK_EATEN)
	hunger = HUNGER_AFTER_FEEDING

	EventBus.dragon_fed.emit(dragon_name, target.village_name, LIVESTOCK_EATEN)
	EventBus.log_danger("[DRAGON] %s fed on %d livestock at %s. Retreating to lair." % [
		dragon_name, LIVESTOCK_EATEN, target.village_name
	])

	is_hunting = false

func get_status_short() -> String:
	var state: String
	if is_hunting:
		state = "HUNTING"
	elif _hunt_cooldown > 0:
		state = "resting (%dh)" % _hunt_cooldown
	elif hunger >= HUNT_THRESHOLD:
		state = "HUNGRY — will hunt soon"
	else:
		state = "passive"
	return "%s — Hunger:%.0f/100 [%s]" % [dragon_name, hunger, state]
