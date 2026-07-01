extends CharacterBody2D

# An individual, autonomous villager. The world is made of these.
# Each hour the NPC re-scores a handful of possible actions against its needs,
# personality traits, and what's happening around it, then pursues the best one.
# Nobody scripts "the farmer wakes at dawn" — it falls out of a diligent trait,
# rising hunger, and the day phase. That's what makes the town feel alive.

const Place = preload("res://scripts/world/Place.gd")

enum Faction { EMPIRE, RESISTANCE, NEUTRAL, BANDIT }
enum Occupation { FARMER, GUARD, MERCHANT, TAVERNKEEP, BANDIT, LABORER, IDLER }

@export var npc_name: String = "Villager"
@export var faction: Faction = Faction.NEUTRAL
@export var occupation: Occupation = Occupation.FARMER
@export var species: String = "human"
@export var traits: Array = []

# Needs — hunger/energy/fear/social on 0..100, wealth/food are counts.
# social is a satisfaction meter (high = content): it drifts down over time and
# is topped up by socializing. Low social = lonely = wants company.
var hunger: float = 30.0
var energy: float = 80.0
var fear: float = 0.0
var social: float = 70.0
var wealth: float = 10.0
var food: float = 5.0

# Assigned by the world spawner.
var home_place: Node = null
var work_place: Node = null
var town_center: Vector2 = Vector2.ZERO

# State
var current_action: String = "idling"
var _hungover: bool = false
var _target_pos: Vector2 = Vector2.ZERO
var _has_target: bool = false
var _prev_action: String = "idling"
var _slept_in_logged: bool = false
var _hungry_logged: bool = false
var _raid_cooldown: int = 0     # after a raid a bandit lies low for a while
var _pilfer_cooldown: int = 0   # after a petty theft a thief keeps their head down

const SPEED: float = 140.0
const ARRIVE_RADIUS: float = 26.0
const FOOD_COST: float = 3.0      # coins per food parcel at market
const DRINK_COST: float = 2.0
const FOOD_BUY_CAP: float = 8.0

const FACTION_COLORS := {
	Faction.EMPIRE:     Color(0.35, 0.45, 0.70),
	Faction.RESISTANCE: Color(0.30, 0.62, 0.35),
	Faction.NEUTRAL:    Color(0.70, 0.62, 0.48),
	Faction.BANDIT:     Color(0.66, 0.24, 0.22),
}

var _name_label: Label
var _action_label: Label

func _ready() -> void:
	add_to_group("npc")
	WorldSimulation.register_npc(self)
	_build_visual()
	_refresh_label()

func _exit_tree() -> void:
	WorldSimulation.unregister_npc(self)

func _build_visual() -> void:
	var color: Color = FACTION_COLORS.get(faction, Color.GRAY)

	var body := Polygon2D.new()
	body.polygon = PackedVector2Array([
		Vector2(-6, 9), Vector2(6, 9), Vector2(8, -2),
		Vector2(4, -6), Vector2(4, -12), Vector2(-4, -12),
		Vector2(-4, -6), Vector2(-8, -2)
	])
	body.color = color
	add_child(body)

	var head := Polygon2D.new()
	head.polygon = PackedVector2Array([
		Vector2(-4, -12), Vector2(4, -12), Vector2(4, -19), Vector2(-4, -19)
	])
	head.color = Color(0.9, 0.78, 0.64)
	add_child(head)

	_name_label = Label.new()
	_name_label.text = npc_name
	_name_label.position = Vector2(-30, -38)
	_name_label.add_theme_font_size_override("font_size", 9)
	_name_label.add_theme_color_override("font_color", color.lightened(0.5))
	add_child(_name_label)

	_action_label = Label.new()
	_action_label.position = Vector2(-30, -30)
	_action_label.add_theme_font_size_override("font_size", 8)
	_action_label.add_theme_color_override("font_color", Color(0.85, 0.85, 0.85))
	add_child(_action_label)

func _refresh_label() -> void:
	if _action_label:
		_action_label.text = current_action

# ── Movement ────────────────────────────────────────────────────────────────

func _physics_process(_delta: float) -> void:
	if _has_target and not _arrived():
		var dir := (_target_pos - global_position).normalized()
		velocity = dir * SPEED
	else:
		velocity = velocity.move_toward(Vector2.ZERO, SPEED * 6.0)
	move_and_slide()

func _arrived() -> bool:
	return (not _has_target) or global_position.distance_to(_target_pos) <= ARRIVE_RADIUS

func is_asleep() -> bool:
	return current_action == "sleeping"

func has_trait(t: String) -> bool:
	return traits.has(t)

# When does this NPC prefer to rest? Normally night; nocturnal folk flip it and
# sleep through the day instead.
func _rest_time() -> bool:
	return (not GameClock.is_night()) if has_trait("nocturnal") else GameClock.is_night()

# Hardy NPCs tire more slowly — route work/travel energy drains through this.
func _energy_cost(x: float) -> float:
	return x * (0.6 if has_trait("hardy") else 1.0)

# ── The hourly brain ─────────────────────────────────────────────────────────

func simulate_hour(_hour: int) -> void:
	_apply_hourly_effects()
	_decide()
	_refresh_label()

func simulate_day(_day: int, _season: String) -> void:
	# Reset per-day one-shot log guards at the start of each day.
	_slept_in_logged = false
	_hungry_logged = false

func _apply_hourly_effects() -> void:
	if _raid_cooldown > 0:
		_raid_cooldown -= 1
	if _pilfer_cooldown > 0:
		_pilfer_cooldown -= 1
	# Base metabolism. Gluttons burn through food faster.
	hunger = clampf(hunger + (5.0 if has_trait("glutton") else 3.0), 0.0, 100.0)
	if current_action != "sleeping":
		energy = clampf(energy - _energy_cost(2.0), 0.0, 100.0)
	# Company fades over time; loners feel it more slowly.
	social = clampf(social - (0.9 if has_trait("loner") else 1.5), 0.0, 100.0)

	# Still walking to the destination — no place effect yet, just leg-tax.
	if not _arrived():
		energy = clampf(energy - _energy_cost(1.0), 0.0, 100.0)
		return

	match current_action:
		"sleeping":
			energy = clampf(energy + 20.0, 0.0, 100.0)
			# NOTE: _hungover is deliberately NOT cleared here — it must persist
			# through the morning so the sleep-in bonus keeps the drunkard in bed
			# until midday. It's cleared on waking (see _decide).
		"eating":
			if food > 0:
				food -= 1
				hunger = clampf(hunger - 40.0, 0.0, 100.0)
		"farming":
			food += 3.0
			wealth += 1.0
			energy = clampf(energy - _energy_cost(4.0), 0.0, 100.0)
			hunger = clampf(hunger + 1.0, 0.0, 100.0)
		"guarding":
			wealth += 2.0
			energy = clampf(energy - _energy_cost(3.0), 0.0, 100.0)
			hunger = clampf(hunger + 1.0, 0.0, 100.0)
		"trading":
			wealth += 3.0
			energy = clampf(energy - _energy_cost(2.0), 0.0, 100.0)
		"socializing":
			social = clampf(social + 22.0, 0.0, 100.0)
			energy = clampf(energy - _energy_cost(1.0), 0.0, 100.0)
		"praying":
			fear = clampf(fear - 30.0, 0.0, 100.0)
			social = clampf(social + 4.0, 0.0, 100.0)
		"pilfering":
			_do_pilfer()
		"buying":
			if wealth >= FOOD_COST and food < FOOD_BUY_CAP:
				wealth -= FOOD_COST
				food += 4.0
		"drinking":
			if wealth >= DRINK_COST:
				wealth -= DRINK_COST
				_hungover = true
				energy = clampf(energy - 2.0, 0.0, 100.0)
		"lying low":
			energy = clampf(energy + 6.0, 0.0, 100.0)
		"raiding":
			_do_raid()
		"fleeing":
			energy = clampf(energy - 3.0, 0.0, 100.0)
			fear = clampf(fear - 20.0, 0.0, 100.0)
		_:
			energy = clampf(energy + 2.0, 0.0, 100.0)
			if occupation == Occupation.IDLER:
				wealth += 0.5  # odd jobs, scrounging — keeps the town drunk in ale

func _decide() -> void:
	var scores := _score_actions()

	# Pick the highest-scoring action; keep current on ties to avoid jitter.
	var best := current_action
	var best_score := -INF
	for action in scores:
		if scores[action] > best_score:
			best_score = scores[action]
			best = action

	# Ambient logging reads the state BEFORE we change action, so a still-sleeping
	# hungover NPC in the morning gets its "slept in" line before it wakes.
	_maybe_log_ambient()

	if best != current_action:
		_prev_action = current_action
		# Waking up clears the hangover for the day.
		if current_action == "sleeping" and best != "sleeping":
			_hungover = false
		current_action = best
		_announce_transition()

	_resolve_target(current_action)

func _score_actions() -> Dictionary:
	var s := {}
	var phase := GameClock.get_day_phase()
	var night := GameClock.is_night()

	# SLEEP — everyone can. Rest time is night, or daytime for the nocturnal.
	var sleep := (100.0 - energy) * 0.9
	if _rest_time():
		sleep += 45.0
	elif phase == "Dusk" and not has_trait("nocturnal"):
		sleep += 10.0
	if _hungover and (phase == "Dawn" or phase == "Morning"):
		sleep += 65.0                       # the drunkard sleeps in
	if has_trait("diligent") and phase == "Dawn":
		sleep -= 50.0                       # up before the sun
	if has_trait("lazy"):
		sleep += 20.0
	if hunger > 78.0:
		sleep -= 35.0                       # too hungry to rest
	s["sleeping"] = sleep

	# EAT — in place, only if food on hand. Gluttons reach for it sooner.
	if food > 0:
		s["eating"] = hunger * (1.5 if has_trait("glutton") else 1.2)

	# FLEE — if a raid is happening nearby and you're not the type to stand.
	var danger := WorldSimulation.danger_near(global_position)
	if danger > 0.05 and occupation != Occupation.GUARD and occupation != Occupation.BANDIT:
		var fl := danger * 70.0
		if has_trait("cowardly"):
			fl += 30.0
		if has_trait("brave"):
			fl -= 30.0
		if has_trait("hardy"):
			fl -= 25.0
		s["fleeing"] = fl

	# Occupation-specific productive actions.
	match occupation:
		Occupation.FARMER, Occupation.LABORER:
			s["farming"] = _work_score(phase, night, food < 4.0)
		Occupation.GUARD:
			s["guarding"] = _work_score(phase, night, false, true)
		Occupation.MERCHANT:
			s["trading"] = _work_score(phase, night, false)
		Occupation.TAVERNKEEP:
			s["trading"] = _work_score(phase, night, false)
		Occupation.BANDIT:
			_score_bandit(s, night)
		Occupation.IDLER:
			pass

	# BUY FOOD — anyone who doesn't grow their own. Misers hold out until hungry.
	if occupation != Occupation.FARMER and occupation != Occupation.LABORER \
			and occupation != Occupation.BANDIT:
		if food < 3.0 and wealth >= FOOD_COST and (not has_trait("miser") or hunger > 50.0):
			s["buying"] = 30.0 + hunger * 0.3

	# DRINK — evenings, if you can afford it; drunkards can't resist, misers won't.
	if (phase == "Dusk" or GameClock.hour >= 18) and wealth >= DRINK_COST and energy > 15.0:
		var drink := 18.0
		if has_trait("drunkard"):
			drink += 55.0
		if has_trait("glutton"):
			drink += 20.0
		if has_trait("miser"):
			drink -= 60.0
		if occupation == Occupation.BANDIT:
			drink -= 40.0
		s["drinking"] = drink

	# SOCIALIZE — seek company when the social meter dips (gregarious most of all).
	if not has_trait("loner"):
		var lonely := 100.0 - social
		var soc := lonely * (0.9 if has_trait("gregarious") else 0.45)
		if has_trait("gregarious"):
			soc += 15.0
		if _rest_time():
			soc -= 40.0                          # not while it's bedtime
		s["socializing"] = soc

	# PRAY — the devout visit the shrine, especially at Dawn/Dusk or when afraid.
	if has_trait("devout"):
		var pray := 12.0 + fear * 0.6
		if phase == "Dawn" or phase == "Dusk":
			pray += 25.0
		if _rest_time():
			pray -= 40.0
		s["praying"] = pray
	elif fear > 55.0 and WorldSimulation.get_nearest_place(global_position, Place.PlaceType.SHRINE) != null:
		s["praying"] = fear * 0.4                 # even the unfaithful seek comfort when terrified

	# PILFER — a thief lifts a purse when guards are scarce and prey is near.
	if has_trait("thief") and occupation != Occupation.BANDIT and _pilfer_cooldown == 0:
		var guards := WorldSimulation.count_guards_near(global_position, 260.0)
		var pilf := (18.0 + maxf(0.0, 30.0 - wealth)) / (1.0 + guards * 1.6)
		if GameClock.is_night():
			pilf += 8.0
		s["pilfering"] = pilf

	# IDLE — always available fallback.
	s["idling"] = 5.0
	return s

func _work_score(phase: String, night: bool, needs_food: bool, is_guard: bool = false) -> float:
	if energy < 18.0 or hunger > 88.0:
		return -10.0                        # too spent or too hungry to work
	var w := 40.0
	if has_trait("nocturnal"):
		# Productive under the stars, sluggish in daylight.
		w += (25.0 if night else -30.0)
	else:
		if phase == "Morning" or phase == "Day":
			w += 25.0
		if night:
			w -= 30.0
			if is_guard:
				w += 20.0                    # some guards do keep the night watch
	if has_trait("diligent"):
		w += 15.0
	if has_trait("lazy"):
		w -= 15.0
	if needs_food:
		w += 20.0                            # empty larder, get to work
	return w

func _score_bandit(s: Dictionary, night: bool) -> void:
	# Fresh off a raid — melt back into the treeline for a while.
	if _raid_cooldown > 0:
		s["raiding"] = -100.0
		s["lying low"] = 30.0
		return
	var guards := WorldSimulation.count_guards_near(town_center)
	var greed := 25.0 if has_trait("greedy") else 0.0
	var raid := hunger * 0.4 + greed + maxf(0.0, 40.0 - wealth)
	raid = raid / (1.0 + guards * 0.9)      # guards make raiding a bad idea
	if night:
		raid += 12.0                         # cover of darkness
	if hunger < 30.0 and wealth > 30.0:
		raid -= 30.0                         # fat and content, why risk it
	if has_trait("cowardly"):
		raid -= 15.0
	if has_trait("greedy"):
		raid += 5.0
	s["raiding"] = raid
	# Laying low grows more appealing the more guards are about.
	s["lying low"] = 16.0 + guards * 3.5

func _resolve_target(action: String) -> void:
	match action:
		"sleeping", "lying low":
			_set_target_place(home_place)
		"farming", "guarding", "trading":
			_set_target_place(work_place)
		"buying":
			_set_target_place(WorldSimulation.get_nearest_place(global_position, Place.PlaceType.MARKET))
		"drinking":
			_set_target_place(WorldSimulation.get_nearest_place(global_position, Place.PlaceType.TAVERN))
		"socializing":
			# Gather where people are: the market by day, the tavern by evening.
			var spot := WorldSimulation.get_nearest_place(global_position, Place.PlaceType.MARKET)
			if GameClock.get_day_phase() == "Dusk" or GameClock.hour >= 18:
				spot = WorldSimulation.get_nearest_place(global_position, Place.PlaceType.TAVERN)
			_set_target_place(spot)
		"praying":
			_set_target_place(WorldSimulation.get_nearest_place(global_position, Place.PlaceType.SHRINE))
		"pilfering":
			_set_target_place(WorldSimulation.get_nearest_place(global_position, Place.PlaceType.MARKET))
		"raiding":
			var mkt := WorldSimulation.get_nearest_place(global_position, Place.PlaceType.MARKET)
			if mkt:
				_target_pos = mkt.global_position
				_has_target = true
			else:
				_target_pos = town_center
				_has_target = true
		"fleeing":
			var threat := _nearest_raider_pos()
			_target_pos = global_position + (global_position - threat).normalized() * 220.0
			_has_target = true
		_:  # eating, idling → stay put
			_has_target = false

func _set_target_place(p: Node) -> void:
	if p != null and is_instance_valid(p):
		_target_pos = p.global_position
		_has_target = true
	else:
		_has_target = false

# ── Raiding & flee helpers ───────────────────────────────────────────────────

func _do_raid() -> void:
	var victim := _nearest_victim(150.0)
	var loot_w := 0.0
	var loot_f := 0.0
	if victim != null:
		loot_w = minf(victim.wealth, 8.0)
		victim.wealth -= loot_w
		loot_f = minf(victim.food, 3.0)
		victim.food -= loot_f
		victim.fear = clampf(victim.fear + 40.0, 0.0, 100.0)
	else:
		loot_w = 3.0  # a few scraps from an empty stall
	wealth += loot_w
	food += loot_f
	hunger = clampf(hunger - 5.0, 0.0, 100.0)
	_raid_cooldown = 10
	EventBus.notable(npc_name, "%s robs %s of %d coin near the market!" % [
		npc_name, (victim.npc_name if victim else "a stall"), int(loot_w)
	], 2)

func _do_pilfer() -> void:
	# Quieter than a raid: lift a couple coin from someone close, then lie low.
	var victim := _nearest_victim(120.0)
	var loot := 0.0
	if victim != null:
		loot = minf(victim.wealth, 3.0)
		victim.wealth -= loot
	wealth += loot
	_pilfer_cooldown = 14
	if loot >= 1.0:
		EventBus.notable(npc_name, "%s quietly lifts %d coin from %s." % [
			npc_name, int(loot), victim.npc_name], 1)

func _nearest_victim(radius: float) -> Node:
	var best: Node = null
	var best_d := radius
	for n in WorldSimulation.npcs:
		if not is_instance_valid(n) or n == self:
			continue
		if n.occupation == Occupation.BANDIT:
			continue
		var d: float = global_position.distance_to(n.global_position)
		if d < best_d:
			best_d = d
			best = n
	return best

func _nearest_raider_pos() -> Vector2:
	var best := town_center
	var best_d := INF
	for n in WorldSimulation.npcs:
		if not is_instance_valid(n) or n == self:
			continue
		if n.occupation == Occupation.BANDIT and n.current_action == "raiding":
			var d: float = global_position.distance_to(n.global_position)
			if d < best_d:
				best_d = d
				best = n.global_position
	return best

# ── Surfacing emergent moments to the event log (throttled) ──────────────────

func _announce_transition() -> void:
	var phase := GameClock.get_day_phase()
	match current_action:
		"farming", "guarding", "trading":
			if has_trait("diligent") and (phase == "Dawn" or phase == "Morning"):
				EventBus.notable(npc_name, "%s rises early to get to work." % npc_name, 0)
		"lying low":
			var guards := WorldSimulation.count_guards_near(town_center)
			if guards >= 2.0:
				EventBus.notable(npc_name,
					"%s keeps to the shadows — too many guards about today." % npc_name, 1)
		"drinking":
			if has_trait("drunkard"):
				EventBus.notable(npc_name, "%s settles in at the tavern for the night." % npc_name, 0)
		"praying":
			if has_trait("devout") and fear > 45.0:
				EventBus.notable(npc_name, "%s hurries to the shrine, shaken." % npc_name, 0)

func _maybe_log_ambient() -> void:
	var phase := GameClock.get_day_phase()
	# Slept in after a night of drinking.
	if current_action == "sleeping" and _hungover and phase == "Morning" \
			and not _slept_in_logged:
		_slept_in_logged = true
		EventBus.notable(npc_name, "%s sleeps off last night's ale, well past dawn." % npc_name, 0)
	# Going hungry with an empty larder.
	if hunger > 85.0 and food <= 0.0 and not _hungry_logged:
		_hungry_logged = true
		EventBus.notable(npc_name, "%s is going hungry." % npc_name, 1)

# ── Inspection (Player / HUD) ────────────────────────────────────────────────

func faction_name() -> String:
	return Faction.keys()[faction].capitalize()

func occupation_name() -> String:
	return Occupation.keys()[occupation].capitalize()

func get_status_short() -> String:
	return "%s (%s %s) — %s" % [npc_name, species, occupation_name(), current_action]

func get_detail() -> String:
	var trait_str := ", ".join(traits) if not traits.is_empty() else "none"
	return "%s the %s %s [%s]\nDoing: %s\nHunger %d  Energy %d  Social %d  Fear %d\nCoin %d  Food %d%s\nTraits: %s" % [
		npc_name, species, occupation_name(), faction_name(),
		current_action, int(hunger), int(energy), int(social), int(fear),
		int(wealth), int(food),
		("  (hungover)" if _hungover else ""), trait_str
	]
