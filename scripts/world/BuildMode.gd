extends RefCounted
class_name BuildMode

# Player-facing construction: place buildable Places (WALL/FARM_PLOT/HOUSE —
# reusing Place.gd rather than a parallel "Building" class) at a resource
# cost from Inventory, or free/unrestricted in GameConfig.dev_mode.
#
# Scope decision for this pass: placement is anchored to the existing town
# Point of Interest — new buildings become children of that same POI node,
# which means they inherit its floating-origin correctness "for free" (see
# WorldRoot.gd) with zero special-case code. True placement anywhere in the
# large wraparound world would need each building to track its own canonical
# world_pos like a POI does, which isn't verifiable without a live editor to
# test the interaction; "expand the existing town" is a clear, honest MVP
# boundary rather than a half-working version of the bigger feature.

enum State { INACTIVE, SELECTING, PLACING }

const PlaceScript = preload("res://scripts/world/Place.gd")
const PlaceScene = preload("res://scenes/Place.tscn")
const InventoryScript = preload("res://scripts/entities/Inventory.gd")

var state: State = State.INACTIVE
var inventory: RefCounted
var selected_type: int = PlaceScript.PlaceType.WALL
var _type_index: int = 0

var _player: Node2D

func _init(player: Node2D) -> void:
	_player = player
	inventory = InventoryScript.new()

func toggle() -> void:
	if state == State.INACTIVE:
		state = State.SELECTING
		_announce_selection()
	else:
		state = State.INACTIVE
		EventBus.log_info("Build mode closed.")

func is_active() -> bool:
	return state != State.INACTIVE

func cycle_type() -> void:
	if not is_active():
		return
	_type_index = (_type_index + 1) % PlaceScript.BUILDABLE_TYPES.size()
	selected_type = PlaceScript.BUILDABLE_TYPES[_type_index]
	_announce_selection()

func _announce_selection() -> void:
	var label: String = PlaceScript.TYPE_LABELS[selected_type]
	var cost: Dictionary = PlaceScript.BUILD_COSTS.get(selected_type, {})
	var cost_str := "free (dev mode)" if GameConfig.dev_mode else _format_cost(cost)
	EventBus.log_info("Build mode: %s (%s). [B] cycle, [E] place." % [label, cost_str])

func _format_cost(cost: Dictionary) -> String:
	var parts: Array = []
	for resource in cost:
		parts.append("%d %s" % [cost[resource], resource])
	return ", ".join(parts) if not parts.is_empty() else "free"

# Placement point: a fixed distance in front of the player, in whatever
# direction they're currently facing. Works identically for keyboard,
# gamepad, and touch — none of them need a separate "point at the world"
# concept, which a true mouse/cursor-driven placement would require.
const PLACE_DISTANCE: float = 48.0

func try_place() -> void:
	if state != State.SELECTING:
		return
	var poi := _town_poi()
	if poi == null:
		EventBus.log_warning("Nothing to build near — no settlement found.")
		return

	var cost: Dictionary = PlaceScript.BUILD_COSTS.get(selected_type, {})
	if not GameConfig.dev_mode:
		if not inventory.can_afford(cost):
			EventBus.log_warning("Not enough materials to build a %s." % PlaceScript.TYPE_LABELS[selected_type])
			return
		inventory.spend(cost)

	var target_global := _player.global_position + _player.facing.normalized() * PLACE_DISTANCE
	var local_pos: Vector2 = poi.to_local(target_global)

	var new_place: Node = PlaceScene.instantiate()
	new_place.place_name = PlaceScript.TYPE_LABELS[selected_type]
	new_place.place_type = selected_type
	new_place.position = local_pos
	poi.add_child(new_place)

	EventBus.log_info("Placed a %s." % PlaceScript.TYPE_LABELS[selected_type])

func _town_poi() -> Node:
	for poi in WorldSimulation.pois:
		if is_instance_valid(poi):
			return poi
	return null
