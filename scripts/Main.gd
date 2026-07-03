extends Node2D

const RaceData = preload("res://scripts/entities/RaceData.gd")

func _ready() -> void:
	var world_root: Node2D = $WorldRoot
	var world_map: Node2D = $WorldRoot/PointsOfInterest/WorldMap
	var player: Node2D = $WorldRoot/Player

	# By this point WorldMap._ready() has already run (children ready before
	# parent) and resolved its real position in the world — start the player
	# exactly there regardless of where BiomeMap ended up placing Heartland.
	# Races with their own fixed spawn (Demon's isolated island) already set
	# world_tile_pos in Player._apply_character_setup() — don't override that.
	if not RaceData.has_spawn_override(player.race_name):
		player.world_tile_pos = world_map.world_pos
	world_root.player = player

	EventBus.log_info("A plains town on the edge of Oakspire's reach.")
	EventBus.log_info("The townsfolk keep their own hours. Watch a while.")
	EventBus.log_warning("Bandits wait in the treeline for a quiet day.")
