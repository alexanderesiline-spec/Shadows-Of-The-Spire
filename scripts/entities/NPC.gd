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

# Trust in the player specifically (0-100, 50 = neutral). Per-NPC, not a global
# reputation number — the tavernkeep can adore the player while a guard stays
# wary. Settles gently toward 50 each day so no single event brands them forever.
var trust_in_player: float = 50.0

# Relationships with OTHER NPCs — lazily seeded on first contact, keyed by the
# other NPC's instance id. Each entry: {"affinity": float 0-100, "type": String}.
# `type` is empty unless explicitly assigned (e.g. "spouse") at spawn. This is
# each NPC's own perception — it isn't mirrored automatically, so one side can
# hold a grudge the other doesn't.
var relationships: Dictionary = {}
var _colocation_cooldowns: Dictionary = {}   # other id -> hours remaining
var _prev_fear: float = 0.0                  # for detecting sudden fear spikes

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

# Inter-species relationship seeds, straight from the world's lore — grievance
# pairs start cooler, alliance pairs start warmer. Keyed by species pair sorted
# alphabetically and joined with "|" so lookup doesn't care about call order.
const SPECIES_RELATIONS := {
	"bear-kin|bird-kin": 15.0,   # alliance — shared highland territories
	"bird-kin|cat-kin": -15.0,   # grievance — old predator/prey tension
	"bear-kin|wolf-kin": -15.0,  # grievance — territorial competition
	"cat-kin|wolf-kin": 5.0,     # civil tolerance
	"demon|elf": -30.0,          # full historical warfare
}
const SAME_FACTION_TRUST_BONUS := 10.0
const FOX_KIN_UNIVERSAL_BONUS := 10.0    # considered lucky by every species
const LIZARD_KIN_MEDIATOR_BONUS := 5.0   # neutral, trusted by every species
const DEMON_UNIVERSAL_PENALTY := -15.0   # unliked by every non-demon species

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

func adjust_trust(delta: float) -> void:
	trust_in_player = clampf(trust_in_player + delta, 0.0, 100.0)

# How this NPC reacts to the player's business, given the trust between them.
# No player economy exists yet, so this is expressed as flavor/log outcome
# rather than an actual refused transaction — the lever is real, the till isn't.
func trade_response() -> String:
	match occupation:
		Occupation.MERCHANT, Occupation.TAVERNKEEP:
			if trust_in_player < 30.0:
				return "%s refuses to deal with you." % npc_name
			elif trust_in_player < 55.0:
				return "%s serves you, curt and businesslike." % npc_name
			else:
				return "%s greets you warmly, glad for your coin." % npc_name
		Occupation.GUARD:
			if trust_in_player < 25.0:
				return "%s eyes you with open suspicion." % npc_name
			elif trust_in_player < 60.0:
				return "%s gives you a wary nod." % npc_name
			else:
				return "%s greets you like an old friend." % npc_name
		_:
			return ""

func trust_label() -> String:
	if trust_in_player >= 75.0:
		return "Warm"
	elif trust_in_player >= 55.0:
		return "Friendly"
	elif trust_in_player >= 40.0:
		return "Neutral"
	elif trust_in_player >= 20.0:
		return "Wary"
	else:
		return "Hostile"

# ── NPC-to-NPC relationships ──────────────────────────────────────────────────

func _species_pair_key(a: String, b: String) -> String:
	return (a + "|" + b) if a <= b else (b + "|" + a)

# Where an NPC's opinion of another starts before any history between them —
# species table + shared faction, straight from the lore's inter-species notes.
func _seed_affinity(other: Node) -> float:
	var base := 50.0
	if faction == other.faction:
		base += SAME_FACTION_TRUST_BONUS
	if species != other.species:
		var key := _species_pair_key(species, other.species)
		if SPECIES_RELATIONS.has(key):
			base += SPECIES_RELATIONS[key]
	if species == "fox-kin" or other.species == "fox-kin":
		base += FOX_KIN_UNIVERSAL_BONUS
	if species == "lizard-kin" or other.species == "lizard-kin":
		base += LIZARD_KIN_MEDIATOR_BONUS
	if (species == "demon") != (other.species == "demon"):
		base += DEMON_UNIVERSAL_PENALTY
	return clampf(base, 0.0, 100.0)

func _relationship_entry(other: Node) -> Dictionary:
	var id := other.get_instance_id()
	if not relationships.has(id):
		relationships[id] = {"affinity": _seed_affinity(other), "type": ""}
	return relationships[id]

func get_affinity(other: Node) -> float:
	return _relationship_entry(other)["affinity"]

func adjust_affinity(other: Node, delta: float) -> void:
	var entry := _relationship_entry(other)
	entry["affinity"] = clampf(entry["affinity"] + delta, 0.0, 100.0)

func set_affinity(other: Node, value: float) -> void:
	_relationship_entry(other)["affinity"] = clampf(value, 0.0, 100.0)

# Explicitly tag a discrete bond (spouse, sibling, ...) that overrides the
# score-derived label regardless of how the number drifts.
func set_relationship_type(other: Node, type: String) -> void:
	_relationship_entry(other)["type"] = type

func relationship_label(other: Node) -> String:
	var entry := _relationship_entry(other)
	if entry["type"] != "":
		return String(entry["type"]).capitalize()
	var affinity: float = entry["affinity"]
	# Jealous NPCs read the same score less charitably — the Acquaintance/Rival
	# bands shrink, so marginal relationships tip into Rival or Enemy sooner.
	var jealous_shift := 10.0 if has_trait("jealous") else 0.0
	if affinity >= 80.0:
		return "Close Friend"
	elif affinity >= 62.0:
		return "Friend"
	elif affinity >= 40.0 + jealous_shift:
		return "Acquaintance"
	elif affinity >= 22.0 + jealous_shift:
		return "Rival"
	else:
		return "Enemy"

# The strongest positive and most negative relationship this NPC currently
# has, for the inspector. Only reports relationships already seeded (i.e.
# they've actually crossed paths) rather than seeding every NPC in the world.
func closest_relationships() -> Array:
	var best_friend: Node = null
	var best_friend_score := -INF
	var worst_rival: Node = null
	var worst_rival_score := INF
	for id in relationships:
		var n := instance_from_id(id)
		if n == null or not is_instance_valid(n):
			continue
		var aff: float = relationships[id]["affinity"]
		if aff > best_friend_score:
			best_friend_score = aff
			best_friend = n
		if aff < worst_rival_score:
			worst_rival_score = aff
			worst_rival = n
	return [best_friend, worst_rival]

# When does this NPC prefer to rest? Normally night; nocturnal folk flip it and
# sleep through the day instead.
func _rest_time() -> bool:
	return (not GameClock.is_night()) if has_trait("nocturnal") else GameClock.is_night()

# Hardy NPCs tire more slowly — route work/travel energy drains through this.
func _energy_cost(x: float) -> float:
	return x * (0.6 if has_trait("hardy") else 1.0)

# ── The hourly brain ─────────────────────────────────────────────────────────

func simulate_hour(_hour: int) -> void:
	# Catch a sudden fear spike since last hour (threatened, raided, ...) before
	# this hour's own effects run, so friends/family can react to it.
	if fear - _prev_fear >= 15.0:
		_broadcast_worry()
	_apply_hourly_effects()
	_decide()
	_refresh_label()
	_prev_fear = fear

func simulate_day(_day: int, _season: String) -> void:
	# Reset per-day one-shot log guards at the start of each day.
	_slept_in_logged = false
	_hungry_logged = false
	# Trust settles gently toward neutral — a single event doesn't brand an NPC.
	trust_in_player = lerpf(trust_in_player, 50.0, 0.08)
	# Relationships settle too — but the vengeful barely let grudges fade.
	for id in relationships:
		var entry: Dictionary = relationships[id]
		var aff: float = entry["affinity"]
		var settle_rate := 0.02 if (aff < 50.0 and has_trait("vengeful")) else 0.08
		entry["affinity"] = lerpf(aff, 50.0, settle_rate)

func _apply_hourly_effects() -> void:
	if _raid_cooldown > 0:
		_raid_cooldown -= 1
	if _pilfer_cooldown > 0:
		_pilfer_cooldown -= 1
	_tick_colocation_cooldowns()
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
			_process_colocation()
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

	# FLEE — if a raid is happening nearby, or the player is close and this NPC
	# doesn't trust them, and you're not the type to stand.
	var danger := maxf(WorldSimulation.danger_near(global_position), _player_threat())
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
			# Seek out an actual friend first; fall back to "wherever people
			# gather" only if nobody worth visiting is nearby.
			var friend := _find_friend_nearby(400.0)
			if friend != null:
				_target_pos = friend.global_position
				_has_target = true
			else:
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
			var threat := _nearest_threat_pos()
			_target_pos = global_position + (global_position - threat).normalized() * 220.0
			_has_target = true
		_:  # eating, idling → stay put
			_has_target = false

func _find_friend_nearby(radius: float) -> Node:
	var best: Node = null
	var best_affinity := 65.0   # only counts as "worth seeking out" above this
	for n in WorldSimulation.npcs:
		if not is_instance_valid(n) or n == self:
			continue
		var d: float = global_position.distance_to(n.global_position)
		if d > radius:
			continue
		var aff := get_affinity(n)
		if aff > best_affinity:
			best_affinity = aff
			best = n
	return best

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

# A sudden spike in this NPC's fear (threatened, raided, ...) is noticed by
# nearby friends and family, who grow afraid on their behalf — scaled by how
# much they care. Rivals and strangers don't react at all.
func _broadcast_worry() -> void:
	var loudest_friend: Node = null
	var loudest_worry := 0.0
	for n in WorldSimulation.npcs:
		if not is_instance_valid(n) or n == self:
			continue
		if global_position.distance_to(n.global_position) > 260.0:
			continue
		var aff := n.get_affinity(self)
		if aff < 62.0:                       # only Friend-or-better worries
			continue
		var worry := (aff - 50.0) / 50.0 * 25.0
		if n.has_trait("loyal"):
			worry *= 1.6
		n.fear = clampf(n.fear + worry, 0.0, 100.0)
		if worry > loudest_worry:
			loudest_worry = worry
			loudest_friend = n
	if loudest_friend != null:
		EventBus.notable(loudest_friend.npc_name, "%s notices %s is in danger and grows afraid." % [
			loudest_friend.npc_name, npc_name], 1)

# When two NPCs both end up socializing near each other, their relationship
# drifts — warmer for a normal pair, cooler (friction) for a lore-grievance
# species pair. Only the lower-instance-id side applies the mutual update so a
# colocated pair isn't double-counted (both sides tick "socializing" this hour).
func _process_colocation() -> void:
	for n in WorldSimulation.npcs:
		if not is_instance_valid(n) or n == self:
			continue
		if n.current_action != "socializing":
			continue
		if global_position.distance_to(n.global_position) > ARRIVE_RADIUS * 2.0:
			continue
		if get_instance_id() > n.get_instance_id():
			continue
		var id := n.get_instance_id()
		if _colocation_cooldowns.has(id):
			continue
		_colocation_cooldowns[id] = 6   # hours before this pair can drift again

		var key := _species_pair_key(species, n.species)
		var is_friction: bool = species != n.species and SPECIES_RELATIONS.get(key, 0.0) < 0.0
		if is_friction:
			var self_friction := -3.0 * (2.0 if has_trait("jealous") else 1.0)
			var other_friction := -3.0 * (2.0 if n.has_trait("jealous") else 1.0)
			adjust_affinity(n, self_friction)
			n.adjust_affinity(self, other_friction)
			EventBus.notable(npc_name, "Curt words pass between %s and %s." % [npc_name, n.npc_name], 0)
		else:
			var base_gain := 2.0
			# Charisma is about how fast OTHERS warm to you, not the reverse.
			var gain_toward_self := base_gain * (1.5 if has_trait("charismatic") else 1.0)
			var gain_toward_other := base_gain * (1.5 if n.has_trait("charismatic") else 1.0)
			n.adjust_affinity(self, gain_toward_self)
			adjust_affinity(n, gain_toward_other)

func _tick_colocation_cooldowns() -> void:
	var expired: Array = []
	for id in _colocation_cooldowns:
		_colocation_cooldowns[id] -= 1
		if _colocation_cooldowns[id] <= 0:
			expired.append(id)
	for id in expired:
		_colocation_cooldowns.erase(id)

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

func _nearest_threat_pos() -> Vector2:
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
	# The player counts as a threat too, if this NPC doesn't trust them.
	if trust_in_player < 35.0:
		var player := get_tree().get_first_node_in_group("player")
		if player != null and is_instance_valid(player):
			var d: float = global_position.distance_to(player.global_position)
			if d < best_d:
				best_d = d
				best = player.global_position
	return best

# Distance- and trust-scaled fear the player specifically inspires in this NPC.
# Only kicks in once trust drops below neutral-ish (35) and the player is close.
func _player_threat(radius: float = 200.0) -> float:
	if trust_in_player >= 35.0:
		return 0.0
	var player := get_tree().get_first_node_in_group("player")
	if player == null or not is_instance_valid(player):
		return 0.0
	var d: float = global_position.distance_to(player.global_position)
	if d > radius:
		return 0.0
	var proximity := (radius - d) / radius
	var wariness := (35.0 - trust_in_player) / 35.0
	return proximity * wariness

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
	var rel := closest_relationships()
	var rel_str := "hasn't met anyone yet"
	if rel[0] != null:
		rel_str = "%s (%s)" % [rel[0].npc_name, relationship_label(rel[0])]
		if rel[1] != null and rel[1] != rel[0]:
			rel_str += "  |  Coolest: %s (%s)" % [rel[1].npc_name, relationship_label(rel[1])]
	return "%s the %s %s [%s]\nDoing: %s\nHunger %d  Energy %d  Social %d  Fear %d\nCoin %d  Food %d%s\nTrust in you: %d (%s)\nClosest: %s\nTraits: %s" % [
		npc_name, species, occupation_name(), faction_name(),
		current_action, int(hunger), int(energy), int(social), int(fear),
		int(wealth), int(food),
		("  (hungover)" if _hungover else ""), int(trust_in_player), trust_label(),
		rel_str, trait_str
	]
