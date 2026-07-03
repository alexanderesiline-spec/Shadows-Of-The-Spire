extends Node2D

# The floating-origin coordinate frame. Player.world_tile_pos is the
# reference point every frame: the player's own node stays pinned at a fixed
# local anchor (Vector2.ZERO) forever, and everything else — chunks, Points
# of Interest — computes its on-screen position fresh each frame as the
# wrapped-shortest delta from the player's canonical position, in tile units
# converted to pixels.
#
# Why this matters for NPC.gd/Place.gd (which stay completely untouched): all
# NPCs are children of a POI, so their RELATIVE positions to each other are
# governed entirely by Godot's ordinary transform hierarchy and never change
# because of anything here. And because the player's global_position is a
# fixed constant while a POI's global_position is recomputed to be exactly
# "fixed_anchor + wrapped_delta(poi, player)", the existing distance-based
# NPC code (count_guards_near, danger_near, flee targeting, etc.) keeps
# producing the correct real-world distance without any changes — the vector
# arithmetic works out identically whether the player "moves" or the world
# scrolls under a stationary player, which is what actually happens here.

const TileConfig = preload("res://scripts/world/tile/TileConfig.gd")
const ChunkManagerScript = preload("res://scripts/world/chunk/ChunkManager.gd")

@onready var chunk_manager: Node2D = $ChunkManager
@onready var points_of_interest: Node2D = $PointsOfInterest

var player: Node2D = null   # assigned by Main.gd once Player is ready

func _process(_delta: float) -> void:
	if player == null or not is_instance_valid(player):
		return
	var ref: Vector2 = player.world_tile_pos

	chunk_manager.update_around(ref)

	var pixel_tile := float(TileConfig.LOGICAL_TILE_SIZE.x)
	for poi in points_of_interest.get_children():
		if not (poi is Node2D):
			continue
		var world_w := float(TileConfig.WORLD_CHUNKS_X * TileConfig.CHUNK_SIZE_TILES)
		var world_h := float(TileConfig.WORLD_CHUNKS_Y * TileConfig.CHUNK_SIZE_TILES)
		var dx := ChunkManagerScript.wrapped_delta(poi.world_pos.x, ref.x, world_w)
		var dy := ChunkManagerScript.wrapped_delta(poi.world_pos.y, ref.y, world_h)
		poi.position = Vector2(dx, dy) * pixel_tile
