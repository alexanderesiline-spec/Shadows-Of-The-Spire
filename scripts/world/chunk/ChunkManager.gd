extends Node2D

# Streams a fixed pool of ChunkNodes around the player's current position on a
# finite, torus-wrapped grid. Chunks are pooled — repainted and repositioned,
# never instantiated/freed at runtime — to avoid per-frame allocation churn.
#
# Design note on the floating origin: rather than rebasing incrementally on
# each chunk-boundary crossing (real drift risk, and awkward to verify without
# a live editor), the player is treated as a fixed reference point and every
# loaded chunk's on-screen position is recomputed FRESH every frame as the
# wrapped-shortest delta from the player's canonical world position. This
# costs a per-frame pass over ~(2*LOAD_RADIUS+1)^2 nodes (a few dozen), which
# is negligible, in exchange for eliminating drift entirely — nothing ever
# accumulates, every frame's positions are independently correct. Pool
# acquire/release (which chunks are loaded at all) still only churns on the
# coarser chunk-boundary-crossing granularity, since that's the expensive part.

const TileConfig = preload("res://scripts/world/tile/TileConfig.gd")
const TileSetBuilder = preload("res://scripts/world/tile/TileSetBuilder.gd")
const ChunkScene = preload("res://scenes/world/Chunk.tscn")

var _pool: Array = []          # every pooled ChunkNode
var _loaded: Dictionary = {}   # chunk_coord (Vector2i) -> ChunkNode
var _last_center_chunk: Vector2i = Vector2i(999999, 999999)   # forces first load

func _ready() -> void:
	var built := TileSetBuilder.build()
	var shared_tile_set: TileSet = built["tile_set"]
	var visual_scale: Vector2 = built["visual_scale"]

	var pool_side := (TileConfig.LOAD_RADIUS + TileConfig.UNLOAD_MARGIN) * 2 + 1
	var pool_size := pool_side * pool_side
	for i in range(pool_size):
		var node: Node2D = ChunkScene.instantiate()
		add_child(node)
		node.setup(shared_tile_set, visual_scale)
		node.unload()
		_pool.append(node)

# world_tile_pos: the player's canonical position, in whole tile units
# (continuous/float — fractional part just affects sub-tile smoothness of the
# scroll, not which chunks are loaded). Called every frame by WorldRoot.
func update_around(world_tile_pos: Vector2) -> void:
	var chunk_size := TileConfig.CHUNK_SIZE_TILES
	var center_chunk := Vector2i(
		floori(world_tile_pos.x / chunk_size),
		floori(world_tile_pos.y / chunk_size)
	)

	if center_chunk != _last_center_chunk:
		_last_center_chunk = center_chunk
		_restream(center_chunk)

	# Reposition every currently loaded chunk relative to the player's exact
	# (possibly fractional, mid-chunk) position — this is what makes the
	# world scroll smoothly rather than snapping chunk-by-chunk.
	var pixel_tile := float(TileConfig.LOGICAL_TILE_SIZE.x)
	for coord in _loaded:
		var node: Node2D = _loaded[coord]
		var chunk_origin := Vector2(coord.x * chunk_size, coord.y * chunk_size)
		var delta := _wrapped_delta_vec2(chunk_origin, world_tile_pos)
		node.position = delta * pixel_tile

func _restream(center_chunk: Vector2i) -> void:
	var wanted := {}
	for dx in range(-TileConfig.LOAD_RADIUS, TileConfig.LOAD_RADIUS + 1):
		for dy in range(-TileConfig.LOAD_RADIUS, TileConfig.LOAD_RADIUS + 1):
			wanted[_wrap_chunk(Vector2i(center_chunk.x + dx, center_chunk.y + dy))] = true

	var unload_radius := TileConfig.LOAD_RADIUS + TileConfig.UNLOAD_MARGIN
	var to_unload: Array = []
	for coord in _loaded:
		var d := _wrapped_delta_vec2i(coord, center_chunk)
		if maxi(absi(d.x), absi(d.y)) > unload_radius:
			to_unload.append(coord)
	for coord in to_unload:
		var node: Node2D = _loaded[coord]
		node.unload()
		_loaded.erase(coord)

	for coord in wanted:
		if _loaded.has(coord):
			continue
		var node := _acquire_pooled_node()
		if node == null:
			continue   # pool exhausted — shouldn't happen with correct sizing
		node.load_chunk(coord)
		_loaded[coord] = node

func _acquire_pooled_node() -> Node2D:
	for node in _pool:
		if not node.active:
			return node
	return null

func _wrap_chunk(coord: Vector2i) -> Vector2i:
	return Vector2i(
		posmod(coord.x, TileConfig.WORLD_CHUNKS_X),
		posmod(coord.y, TileConfig.WORLD_CHUNKS_Y)
	)

# The single mechanism that answers "how is the wrap seam handled" — every
# distance/placement computation goes through this shortest-signed-delta-on-
# a-torus helper. There is no seam-specific code anywhere else; a chunk just
# past the world edge is indistinguishable from one in the interior.
static func wrapped_delta(a: float, b: float, size: float) -> float:
	return fposmod(a - b + size / 2.0, size) - size / 2.0

static func _wrapped_delta_vec2(a: Vector2, b: Vector2) -> Vector2:
	var world_w := float(TileConfig.WORLD_CHUNKS_X * TileConfig.CHUNK_SIZE_TILES)
	var world_h := float(TileConfig.WORLD_CHUNKS_Y * TileConfig.CHUNK_SIZE_TILES)
	return Vector2(wrapped_delta(a.x, b.x, world_w), wrapped_delta(a.y, b.y, world_h))

static func _wrapped_delta_vec2i(a: Vector2i, b: Vector2i) -> Vector2i:
	var dx := int(wrapped_delta(float(a.x), float(b.x), float(TileConfig.WORLD_CHUNKS_X)))
	var dy := int(wrapped_delta(float(a.y), float(b.y), float(TileConfig.WORLD_CHUNKS_Y)))
	return Vector2i(dx, dy)
