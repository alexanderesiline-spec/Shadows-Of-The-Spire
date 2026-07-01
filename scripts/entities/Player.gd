extends CharacterBody2D

# A free-roaming observer/participant. In this build the player mostly wanders
# and inspects — the world runs with or without them. Faction alignment and
# real interaction come in a later phase.

const SPEED: float = 170.0
const INTERACT_RADIUS: float = 90.0

var _nearby_npc: Node = null

func _ready() -> void:
	add_to_group("player")
	_build_visual()

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
	velocity = dir.normalized() * SPEED if dir != Vector2.ZERO \
			   else velocity.move_toward(Vector2.ZERO, SPEED * 8.0)
	move_and_slide()
	_update_nearby()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("interact") and _nearby_npc != null:
		_interact()

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

func _interact() -> void:
	if _nearby_npc == null:
		return
	EventBus.player_interacted.emit(_nearby_npc.npc_name, _nearby_npc.get_detail())
	EventBus.log_info("[You inspect] %s" % _nearby_npc.get_status_short())

func get_status() -> String:
	if _nearby_npc and is_instance_valid(_nearby_npc):
		return "Near: %s\n[E] inspect" % _nearby_npc.get_status_short()
	return "Wandering the plains town...\nWalk up to someone and press E."
