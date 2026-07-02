extends Node

# The simulation registry. Entities register themselves here on _ready().
# GameClock drives ticks; this routes them to every registered NPC.
# The world is agent-driven: individual NPCs read context from here to decide
# what to do each hour, so the world stays alive with no player input.

var npcs: Array = []
var places: Array = []

# Town-wide "how many guards are visibly about today" pressure. Bandits read it.
# Fluctuates day to day (shift patterns + a random surge) so some days feel safer.
var patrol_level: float = 1.0

func _ready() -> void:
	GameClock.hour_passed.connect(_on_hour_passed)
	GameClock.day_passed.connect(_on_day_passed)
	GameClock.season_changed.connect(_on_season_changed)
	_roll_patrol_level()

func register_npc(n: Node) -> void:
	npcs.append(n)

func register_place(p: Node) -> void:
	places.append(p)

func unregister_npc(n: Node) -> void:
	npcs.erase(n)

func unregister_place(p: Node) -> void:
	places.erase(p)

func _on_hour_passed(hour: int) -> void:
	for n in npcs:
		if is_instance_valid(n):
			n.simulate_hour(hour)

func _on_day_passed(day: int, season: String) -> void:
	_roll_patrol_level()
	for n in npcs:
		if is_instance_valid(n):
			n.simulate_day(day, season)

func _on_season_changed(season: String) -> void:
	EventBus.log_warning("== The season turns to %s ==" % season)

func _roll_patrol_level() -> void:
	# Base 1.0, occasional heavy-patrol days (muster, imperial inspection) up to ~2.5.
	patrol_level = 1.0 + randf() * 0.6
	if randf() < 0.25:
		patrol_level += 0.8 + randf() * 0.6
		EventBus.log_warning("The town crawls with extra guards today.")

# ── Context queries the NPC utility AI reads ─────────────────────────────────

# Count guards physically near a position — actual bodies on the ground — then
# scale by the town's patrol_level so "busy" days genuinely deter bandits.
func count_guards_near(pos: Vector2, radius: float = 320.0) -> float:
	var count: float = 0.0
	for n in npcs:
		if not is_instance_valid(n):
			continue
		if n.occupation == n.Occupation.GUARD and not n.is_asleep():
			if pos.distance_to(n.global_position) <= radius:
				count += 1.0
	return count * patrol_level

func get_nearest_place(from_pos: Vector2, type: int) -> Node:
	var nearest: Node = null
	var nearest_dist: float = INF
	for p in places:
		if not is_instance_valid(p) or p.place_type != type:
			continue
		var d: float = from_pos.distance_to(p.global_position)
		if d < nearest_dist:
			nearest_dist = d
			nearest = p
	return nearest

func get_places_of_type(type: int) -> Array:
	var out: Array = []
	for p in places:
		if is_instance_valid(p) and p.place_type == type:
			out.append(p)
	return out

# Weighted threat near a position — bandits mid-raid and other hostiles, closer
# means scarier. Used by timid NPCs to decide whether to flee.
func danger_near(pos: Vector2, radius: float = 260.0) -> float:
	var threat: float = 0.0
	for n in npcs:
		if not is_instance_valid(n):
			continue
		if n.occupation == n.Occupation.BANDIT and n.current_action == "raiding":
			var d: float = pos.distance_to(n.global_position)
			if d <= radius:
				threat += (radius - d) / radius
	return threat

# Word travels: when something happens to the player's trust with one NPC,
# nearby witnesses adjust their own trust too — scaled down by distance so
# only those close enough to have seen it are affected. `exclude` is the NPC
# the event already applied full effect to directly. `source_npc`, if given,
# additionally weights each witness's reaction by their own relationship to
# the person it happened to — a friend hears about it more strongly than a
# stranger standing at the same distance.
func gossip_near(pos: Vector2, delta: float, radius: float, exclude: Node = null,
		source_npc: Node = null) -> void:
	for n in npcs:
		if not is_instance_valid(n) or n == exclude:
			continue
		var d: float = pos.distance_to(n.global_position)
		if d <= radius:
			var weight: float = (radius - d) / radius
			if source_npc != null and is_instance_valid(source_npc):
				var affinity: float = n.get_affinity(source_npc)
				weight *= 0.5 + (affinity / 100.0)   # roughly 0.5x-1.5x
			n.adjust_trust(delta * weight)
