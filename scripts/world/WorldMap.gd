extends Node2D

func _ready() -> void:
	_draw_terrain()
	_spawn_world()

func _draw_terrain() -> void:
	# Grass background
	var bg := ColorRect.new()
	bg.color = Color(0.17, 0.34, 0.14)
	bg.size = Vector2(2400, 2000)
	bg.position = Vector2(-200, -200)
	add_child(bg)
	move_child(bg, 0)

	# Forest patches (decorative)
	_add_patch(Vector2(650, 280), Color(0.12, 0.28, 0.10), 90, 60)
	_add_patch(Vector2(300, 560), Color(0.12, 0.28, 0.10), 120, 80)
	_add_patch(Vector2(1000, 200), Color(0.12, 0.28, 0.10), 80, 110)

	# River strip
	_add_patch(Vector2(500, 500), Color(0.15, 0.35, 0.55), 20, 400)

	# Mountain hints (top-right corner)
	_add_patch(Vector2(1050, 100), Color(0.38, 0.36, 0.34), 120, 90)
	_add_patch(Vector2(1100, 80), Color(0.45, 0.43, 0.41), 70, 60)

func _add_patch(pos: Vector2, color: Color, w: float, h: float) -> void:
	var rect := ColorRect.new()
	rect.color = color
	rect.size = Vector2(w, h)
	rect.position = pos
	add_child(rect)

func _spawn_world() -> void:
	# Villages — spread across the map with varied starting conditions
	_village(Vector2(210, 230), "Millhaven",   pop=22, food=110.0, gold=60.0, livestock=12)
	_village(Vector2(780, 380), "Ashford",     pop=16, food=75.0,  gold=35.0, livestock=7)
	_village(Vector2(420, 740), "Cresthollow", pop=28, food=130.0, gold=80.0, livestock=16)
	_village(Vector2(900, 650), "Dawnmere",    pop=12, food=50.0,  gold=20.0, livestock=5)

	# Bandit factions — start at varied desperation levels
	_faction(Vector2(560, 100), "The Ravagers",      pop=9,  food=35.0, gold=18.0)
	_faction(Vector2(80,  600), "Dusk Brotherhood",  pop=6,  food=55.0, gold=30.0)
	_faction(Vector2(700, 820), "Ironblood Wolves",  pop=12, food=20.0, gold=8.0)   # nearly raiding

	# Dragons — Ironblood is already hungry
	_dragon(Vector2(950, 820), "Ignarath",       hunger=18.0)
	_dragon(Vector2(130, 880), "Verath the Cold", hunger=55.0)  # will hunt soon

func _village(pos: Vector2, name: String, pop: int, food: float, gold: float, livestock: int) -> void:
	var v: Node = load("res://scenes/Village.tscn").instantiate()
	v.position = pos
	v.village_name = name
	v.population = pop
	v.food_stores = food
	v.gold = gold
	v.livestock_count = livestock
	add_child(v)

func _faction(pos: Vector2, name: String, pop: int, food: float, gold: float) -> void:
	var f: Node = load("res://scenes/BanditFaction.tscn").instantiate()
	f.position = pos
	f.faction_name = name
	f.population = pop
	f.food_supplies = food
	f.gold = gold
	add_child(f)

func _dragon(pos: Vector2, name: String, hunger: float) -> void:
	var d: Node = load("res://scenes/Dragon.tscn").instantiate()
	d.position = pos
	d.dragon_name = name
	d.hunger = hunger
	add_child(d)
