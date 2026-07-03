extends RefCounted
class_name ChunkDeltaStore

# Sparse per-tile terrain edits from dev-mode, layered on top of whatever
# ChunkGenerator would otherwise procedurally paint (including POI/island
# force-clears — a deliberate player edit has the final say). This is also
# what makes chunks safe to never persist wholesale: only these deltas ever
# need saving, everything else regenerates identically from world_seed.

static var _deltas: Dictionary = {}   # chunk_coord -> {tile_offset Vector2i: surface_name}

static func set_tile(chunk_coord: Vector2i, tile_offset: Vector2i, surface_name: String) -> void:
	if not _deltas.has(chunk_coord):
		_deltas[chunk_coord] = {}
	_deltas[chunk_coord][tile_offset] = surface_name

static func get_tile(chunk_coord: Vector2i, tile_offset: Vector2i) -> String:
	if not _deltas.has(chunk_coord):
		return ""
	return _deltas[chunk_coord].get(tile_offset, "")

static func has_deltas(chunk_coord: Vector2i) -> bool:
	return _deltas.has(chunk_coord)

# Flattened for JSON (Vector2i keys aren't JSON-safe): "x,y" chunk keys each
# mapping to a list of [tx, ty, surface_name] triples.
static func serialize() -> Dictionary:
	var out := {}
	for chunk_coord in _deltas:
		var key := "%d,%d" % [chunk_coord.x, chunk_coord.y]
		var tiles: Array = []
		for tile_offset in _deltas[chunk_coord]:
			tiles.append([tile_offset.x, tile_offset.y, _deltas[chunk_coord][tile_offset]])
		out[key] = tiles
	return out

static func deserialize(data: Dictionary) -> void:
	_deltas.clear()
	for key in data:
		var parts: PackedStringArray = key.split(",")
		var chunk_coord := Vector2i(int(parts[0]), int(parts[1]))
		_deltas[chunk_coord] = {}
		for triple in data[key]:
			_deltas[chunk_coord][Vector2i(triple[0], triple[1])] = triple[2]
