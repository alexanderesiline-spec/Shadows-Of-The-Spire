extends CharacterBody2D

# A free-roaming observer/participant. The world runs with or without them, but
# the player can now nudge it: greeting builds trust, threatening breaks it.
# Faction alignment and real combat/economy come in a later phase.

const SPEED: float = 170.0
const INTERACT_RADIUS: float = 90.0
const GREET_TRUST_GAIN: float = 1.0
const GREET_COOLDOWN_HOURS: int = 3       # stops trust-farming by spamming E
const THREATEN_TRUST_LOSS: float = 25.0
const THREATEN_FEAR_GAIN: float = 35.0
const THREATEN_GOSSIP_RADIUS: float = 220.0

# Mana — the resource, not spells yet. Untrained average mage: 100 pool (lore).
var mana: float = 100.0
var max_mana: float = 100.0
const MANA_RESTORE_RESTING: float = 100.0 / 2.5   # full in ~2.5h stationary
const MANA_RESTORE_WALKING: float = 100.0 / 4.5   # full in ~4.5h while moving

var _nearby_npc: Node = null
var _moved_this_hour: bool = false
var _greet_cooldowns: Dictionary = {}   # NPC instance id -> hours remaining

func _ready() -> void:
	add_to_group("player")
	_build_visual()
	GameClock.hour_passed.connect(_on_hour_passed)

func _build_visual() -> void:
	var body := Polygon2D.new()
	body.polygon = PackedVector2Array([
		Vector2(-7, 10), Vector2(7, 10),
		Vector2(9, -2), Vector2(4, -6),
		Vector2(4, -14), Vector2(-4, -14),
		Vector2(-4, -6), Vector2(-9, -2)
	])
	body.color = Color(0.2, 0.55, 1.0)
	add_child(body)

	var head := Polygon2D.new()
	head.polygon = PackedVector2Array([
		Vector2(-5, -14), Vector2(5, -14),
		Vector2(5, -22), Vector2(-5, -22)
	])
	head.color = Color(0.9, 0.75, 0.6)
	add_child(head)

	var camera := Camera2D.new()
	camera.zoom = Vector2(1.5, 1.5)
	add_child(camera)

func _physics_process(_delta: float) -> void:
	var dir := Vector2(
		Input.get_axis("ui_left", "ui_right"),
		Input.get_axis("ui_up", "ui_down")
	)
	if dir != Vector2.ZERO:
		velocity = dir.normalized() * SPEED
		_moved_this_hour = true
	else:
		velocity = velocity.move_toward(Vector2.ZERO, SPEED * 8.0)
	move_and_slide()
	_update_nearby()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("interact") and _nearby_npc != null:
		_greet()
	elif event.is_action_pressed("threaten") and _nearby_npc != null:
		_threaten()

func _update_nearby() -> void:
	_nearby_npc = null
	var best_dist := INTERACT_RADIUS
	for n in WorldSimulation.npcs:
		if is_instance_valid(n):
			var d: float = global_position.distance_to(n.global_position)
			if d < best_dist:
				best_dist = d
				_nearby_npc = n

func get_nearby_npc() -> Node:
	return _nearby_npc

# ── Mana restoration ─────────────────────────────────────────────────────────
# Ticks once per in-game hour (mirrors how NPC needs regen) rather than per
# frame, keyed on whether the player stood still or walked during that hour.
# Lore's "no restoration in combat/running" tier has no hook yet — there's no
# combat or sprint in this build — so only the two active tiers apply so far.

func _on_hour_passed(_hour: int) -> void:
	var rate := MANA_RESTORE_WALKING if _moved_this_hour else MANA_RESTORE_RESTING
	mana = clampf(mana + rate, 0.0, max_mana)
	_moved_this_hour = false
	_tick_greet_cooldowns()

func get_mana_status() -> String:
	return "Mana %d / %d" % [int(mana), int(max_mana)]

# ── Greet & Threaten — the player's two levers on NPC trust ─────────────────

func _greet() -> void:
	var n := _nearby_npc
	EventBus.player_interacted.emit(n.npc_name, n.get_detail())
	EventBus.log_info("[You inspect] %s" % n.get_status_short())

	var response: String = n.trade_response()
	if response != "":
		EventBus.log_info(response)

	var id := n.get_instance_id()
	if not _greet_cooldowns.has(id):
		n.adjust_trust(GREET_TRUST_GAIN)
		_greet_cooldowns[id] = GREET_COOLDOWN_HOURS

func _threaten() -> void:
	var n := _nearby_npc
	n.adjust_trust(-THREATEN_TRUST_LOSS)
	n.fear = clampf(n.fear + THREATEN_FEAR_GAIN, 0.0, 100.0)
	EventBus.notable(n.npc_name, "You threaten %s. They recoil in fear." % n.npc_name, 2)
	WorldSimulation.gossip_near(n.global_position, -8.0, THREATEN_GOSSIP_RADIUS, n)

func _tick_greet_cooldowns() -> void:
	var expired: Array = []
	for id in _greet_cooldowns:
		_greet_cooldowns[id] -= 1
		if _greet_cooldowns[id] <= 0:
			expired.append(id)
	for id in expired:
		_greet_cooldowns.erase(id)

# ── Inspection (HUD) ─────────────────────────────────────────────────────────

func get_status() -> String:
	var s := get_mana_status()
	if _nearby_npc and is_instance_valid(_nearby_npc):
		s += "\nNear: %s\n[E] greet   [R] threaten" % _nearby_npc.get_status_short()
	else:
		s += "\nWandering the plains town...\nWalk up to someone and press E."
	return s
