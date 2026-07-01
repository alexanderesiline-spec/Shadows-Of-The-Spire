extends Node2D

# Spawns a single living plains town on the edge of Oakspire's territory:
# places (homes, fields, tavern, market, guard post) and a cast of NPCs who go
# about their day on their own. A bandit camp sits out in the treeline.

const Place = preload("res://scripts/world/Place.gd")
const NPC_ = preload("res://scripts/entities/NPC.gd")   # for enum access below
const NPCScene = preload("res://scenes/NPC.tscn")
const PlaceScene = preload("res://scenes/Place.tscn")

const TOWN_CENTER := Vector2(600, 380)

func _ready() -> void:
	_draw_terrain()
	_spawn_town()

func _draw_terrain() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.19, 0.36, 0.16)
	bg.size = Vector2(2400, 2000)
	bg.position = Vector2(-400, -400)
	add_child(bg)
	move_child(bg, 0)

	# Treeline around the bandit camp (top-right).
	_patch(Vector2(900, 600), Color(0.11, 0.26, 0.10), 260, 240)
	_patch(Vector2(940, 640), Color(0.09, 0.22, 0.09), 160, 150)
	# Woodland fringe (left) and a river.
	_patch(Vector2(180, 300), Color(0.11, 0.26, 0.10), 130, 220)
	_patch(Vector2(430, 620), Color(0.15, 0.35, 0.55), 380, 22)

func _patch(pos: Vector2, color: Color, w: float, h: float) -> void:
	var rect := ColorRect.new()
	rect.color = color
	rect.size = Vector2(w, h)
	rect.position = pos
	add_child(rect)

func _spawn_town() -> void:
	# ── Places ──────────────────────────────────────────────────────────────
	var guard_post := _place("Watch Post",  Place.PlaceType.GUARD_POST, Vector2(560, 330))
	var market     := _place("Market",      Place.PlaceType.MARKET,     Vector2(680, 360))
	var tavern     := _place("The Bent Nail", Place.PlaceType.TAVERN,   Vector2(620, 290))
	var field_a    := _place("North Field",  Place.PlaceType.FIELD,     Vector2(300, 300))
	var field_b    := _place("South Field",  Place.PlaceType.FIELD,     Vector2(340, 470))
	var camp       := _place("Bandit Camp",  Place.PlaceType.CAMP,      Vector2(960, 640))

	var homes: Array = []
	for hp in [Vector2(500, 470), Vector2(560, 510), Vector2(700, 470),
			   Vector2(760, 420), Vector2(720, 540), Vector2(470, 300),
			   Vector2(440, 540), Vector2(660, 500)]:
		homes.append(_place("Home", Place.PlaceType.HOME, hp))

	# ── Townsfolk ───────────────────────────────────────────────────────────
	# Diligent farmers — up at dawn, work the fields, feed themselves.
	_npc("Doran",  NPC_.Faction.NEUTRAL, NPC_.Occupation.FARMER, "human",
		["diligent"], homes[0], field_a)
	_npc("Wenna", NPC_.Faction.NEUTRAL, NPC_.Occupation.FARMER, "human",
		["diligent"], homes[6], field_b)
	_npc("Sella",  NPC_.Faction.NEUTRAL, NPC_.Occupation.FARMER, "human",
		[], homes[1], field_a)

	# A demi-human laborer working the fields — lore texture.
	_npc("Rukh",   NPC_.Faction.NEUTRAL, NPC_.Occupation.LABORER, "wolf-kin",
		["diligent"], homes[7], field_b)

	# Imperial guards — presence keeps bandits honest. One brave night-watch.
	_npc("Sgt. Balen", NPC_.Faction.EMPIRE, NPC_.Occupation.GUARD, "human",
		["brave"], homes[2], guard_post)
	_npc("Corvin",     NPC_.Faction.EMPIRE, NPC_.Occupation.GUARD, "human",
		["diligent"], homes[3], guard_post)

	# Market & tavern keepers — earn coin, buy food, sleep.
	_npc("Merrow", NPC_.Faction.NEUTRAL, NPC_.Occupation.MERCHANT, "human",
		["greedy"], homes[4], market)
	_npc("Pip",    NPC_.Faction.NEUTRAL, NPC_.Occupation.TAVERNKEEP, "human",
		[], homes[5], tavern)

	# The town drunk — earns a little, drinks it away, sleeps in every morning.
	_npc("Old Ferro", NPC_.Faction.NEUTRAL, NPC_.Occupation.IDLER, "human",
		["drunkard", "lazy"], homes[0], null)

	# A resistance scout passing through — watches, keeps to himself.
	_npc("Levsca", NPC_.Faction.RESISTANCE, NPC_.Occupation.IDLER, "human",
		["brave"], homes[1], null)

	# Bandits in the treeline — raid when the coast is clear, lie low otherwise.
	_npc("Grix",  NPC_.Faction.BANDIT, NPC_.Occupation.BANDIT, "human",
		["greedy"], camp, null)
	_npc("Nettle", NPC_.Faction.BANDIT, NPC_.Occupation.BANDIT, "human",
		["cowardly"], camp, null)
	_npc("Hask",  NPC_.Faction.BANDIT, NPC_.Occupation.BANDIT, "human",
		["greedy", "brave"], camp, null)

func _place(pname: String, type: int, pos: Vector2) -> Node:
	var p: Node = PlaceScene.instantiate()
	p.place_name = pname
	p.place_type = type
	p.position = pos
	add_child(p)
	return p

func _npc(pname: String, fac: int, occ: int, species: String, traits: Array,
		home: Node, work: Node) -> Node:
	var n: Node = NPCScene.instantiate()
	n.npc_name = pname
	n.faction = fac
	n.occupation = occ
	n.species = species
	n.traits = traits
	n.town_center = TOWN_CENTER
	# Start the NPC at home, and vary needs so they don't act in lockstep.
	if home != null:
		n.position = home.position + Vector2(randf_range(-14, 14), randf_range(-14, 14))
	else:
		n.position = TOWN_CENTER
	n.hunger = randf_range(20.0, 55.0)
	n.energy = randf_range(55.0, 95.0)
	n.wealth = randf_range(6.0, 18.0)
	n.food = randf_range(2.0, 6.0)
	add_child(n)
	# home_place/work_place are set after add_child so refs are valid.
	n.home_place = home
	n.work_place = work
	return n
