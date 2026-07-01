extends CharacterBody2D

const SPEED: float = 160.0
const INTERACT_RADIUS: float = 70.0

var inventory: Dictionary = {"food": 10, "gold": 5, "wood": 0, "herb": 0}
var _nearby_entity: Node = null

func _ready() -> void:
	add_to_group("player")
	_build_visual()

func _build_visual() -> void:
	# Player body (upright figure)
	var body := Polygon2D.new()
	body.polygon = PackedVector2Array([
		Vector2(-7, 10), Vector2(7, 10),
		Vector2(9, -2), Vector2(4, -6),
		Vector2(4, -14), Vector2(-4, -14),
		Vector2(-4, -6), Vector2(-9, -2)
	])
	body.color = Color(0.2, 0.55, 1.0)
	add_child(body)

	# Head
	var head := Polygon2D.new()
	head.polygon = PackedVector2Array([
		Vector2(-5, -14), Vector2(5, -14),
		Vector2(5, -22), Vector2(-5, -22)
	])
	head.color = Color(0.9, 0.75, 0.6)
	add_child(head)

	var camera := Camera2D.new()
	camera.zoom = Vector2(1.6, 1.6)
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
	if event.is_action_pressed("interact") and _nearby_entity != null:
		_interact()

func _update_nearby() -> void:
	_nearby_entity = null
	var best_dist := INTERACT_RADIUS

	for v in WorldSimulation.villages:
		if is_instance_valid(v):
			var d: float = global_position.distance_to(v.global_position)
			if d < best_dist:
				best_dist = d
				_nearby_entity = v

	for f in WorldSimulation.factions:
		if is_instance_valid(f):
			var d: float = global_position.distance_to(f.global_position)
			if d < best_dist:
				best_dist = d
				_nearby_entity = f

func _interact() -> void:
	if _nearby_entity == null:
		return

	var info: String
	if _nearby_entity.has_method("get_status_short"):
		info = _nearby_entity.get_status_short()
	else:
		info = str(_nearby_entity.name)

	EventBus.player_interacted.emit(str(_nearby_entity.name), info)
	EventBus.log_info("[You] %s" % info)

func get_status() -> String:
	var inv := "Food:%d  Gold:%d  Wood:%d  Herb:%d" % [
		inventory.food, inventory.gold, inventory.wood, inventory.herb
	]
	if _nearby_entity and _nearby_entity.has_method("get_status_short"):
		inv += "\n[E] " + _nearby_entity.get_status_short()
	return inv
