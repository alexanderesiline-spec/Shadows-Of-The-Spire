extends Node

# The simulation registry. Entities register themselves here on _ready().
# GameClock drives ticks; this routes them to every registered entity.

var villages: Array = []
var factions: Array = []
var dragons: Array = []

func _ready() -> void:
	GameClock.hour_passed.connect(_on_hour_passed)
	GameClock.day_passed.connect(_on_day_passed)
	GameClock.season_changed.connect(_on_season_changed)

func register_village(v: Node) -> void:
	villages.append(v)

func register_faction(f: Node) -> void:
	factions.append(f)

func register_dragon(d: Node) -> void:
	dragons.append(d)

func unregister_village(v: Node) -> void:
	villages.erase(v)

func unregister_faction(f: Node) -> void:
	factions.erase(f)

func unregister_dragon(d: Node) -> void:
	dragons.erase(d)

func _on_hour_passed(hour: int) -> void:
	for f in factions:
		if is_instance_valid(f):
			f.simulate_hour(hour)
	for d in dragons:
		if is_instance_valid(d):
			d.simulate_hour(hour)

func _on_day_passed(day: int, season: String) -> void:
	for v in villages:
		if is_instance_valid(v):
			v.simulate_day(day, season)
	for f in factions:
		if is_instance_valid(f):
			f.simulate_day(day, season)

func _on_season_changed(season: String) -> void:
	EventBus.log_warning("== Season changed: %s ==" % season)

# Spatial queries used by factions and dragons when deciding targets.

func get_nearest_village(from_pos: Vector2, min_livestock: int = 0) -> Node:
	var nearest: Node = null
	var nearest_dist: float = INF
	for v in villages:
		if not is_instance_valid(v):
			continue
		if min_livestock > 0 and v.livestock_count < min_livestock:
			continue
		var d: float = from_pos.distance_to(v.global_position)
		if d < nearest_dist:
			nearest_dist = d
			nearest = v
	return nearest

func get_total_world_livestock() -> int:
	var total: int = 0
	for v in villages:
		if is_instance_valid(v):
			total += v.livestock_count
	return total
