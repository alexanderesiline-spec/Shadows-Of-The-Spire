extends Node2D

# One pooled visual chunk. ChunkManager repaints and repositions these rather
# than instantiating/freeing chunks as the player roams, avoiding per-frame
# allocation churn — matters for Android.

const ChunkGenerator = preload("res://scripts/world/chunk/ChunkGenerator.gd")

var chunk_coord: Vector2i = Vector2i.ZERO
var active: bool = false

@onready var tile_map_layer: TileMapLayer = $TileMapLayer

func setup(shared_tile_set: TileSet, visual_scale: Vector2) -> void:
	tile_map_layer.tile_set = shared_tile_set
	scale = visual_scale

func load_chunk(coord: Vector2i) -> void:
	chunk_coord = coord
	ChunkGenerator.generate_into(tile_map_layer, coord)
	active = true
	visible = true

func unload() -> void:
	active = false
	visible = false
