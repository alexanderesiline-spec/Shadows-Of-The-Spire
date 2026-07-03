extends RefCounted

# Deterministic chunk content — a pure function of world_seed + BiomeMap, so
# untouched chunks never need to be persisted; they regenerate identically on
# demand. Called by ChunkNode to paint its TileMapLayer.

const TileConfig = preload("res://scripts/world/tile/TileConfig.gd")
const TileSetBuilder = preload("res://scripts/world/tile/TileSetBuilder.gd")
const ChunkDeltaStore = preload("res://scripts/world/chunk/ChunkDeltaStore.gd")

# Biome -> the handful of surfaces that make up its ground texture. Picked
# per-tile via a deterministic hash (not stored) so a chunk regenerates
# pixel-identical every time without needing saved per-tile data.
const BIOME_SURFACES := {
	0: ["water", "water", "deep_water"],                 # BiomeMap.Biome.OCEAN
	1: ["grass", "grass", "dark grass", "flowers"],       # HEARTLAND
	2: ["grass", "moss", "dirt"],                         # OLD_FOREST
	3: ["swamp", "wetland", "water"],                     # WETLANDS
	4: ["rocky", "stone", "dry dirt"],                     # FOOTHILLS
	5: ["stone", "stone", "snow", "ice"],                  # MOUNTAINS
	6: ["sand", "wetland", "water"],                       # DELTA
}

# Force-clear registry: chunk_coord -> forced surface name. Populated by
# Points of Interest and special spawns (Demon's isolated island) so they
# never get a lava tile or open water spawned underfoot regardless of what
# the noise/PNG says for that coordinate.
static var _forced_chunks: Dictionary = {}

static func force_clear(chunk_coord: Vector2i, surface: String = "grass") -> void:
	_forced_chunks[chunk_coord] = surface

static func clear_force(chunk_coord: Vector2i) -> void:
	_forced_chunks.erase(chunk_coord)

static func generate_into(tile_map_layer: TileMapLayer, chunk_coord: Vector2i) -> void:
	tile_map_layer.clear()
	var forced: String = _forced_chunks.get(chunk_coord, "")
	var biome := BiomeMap.get_biome(chunk_coord)
	var surfaces: Array = BIOME_SURFACES.get(int(biome), ["grass"])
	var has_deltas := ChunkDeltaStore.has_deltas(chunk_coord)

	for ty in range(TileConfig.CHUNK_SIZE_TILES):
		for tx in range(TileConfig.CHUNK_SIZE_TILES):
			var surface_name: String
			if forced != "":
				surface_name = forced
			else:
				var world_tx := chunk_coord.x * TileConfig.CHUNK_SIZE_TILES + tx
				var world_ty := chunk_coord.y * TileConfig.CHUNK_SIZE_TILES + ty
				var idx := _tile_hash(world_tx, world_ty) % surfaces.size()
				surface_name = surfaces[idx]
			# A deliberate dev-mode terrain edit always wins, even over a
			# force-cleared POI/island tile.
			if has_deltas:
				var edit := ChunkDeltaStore.get_tile(chunk_coord, Vector2i(tx, ty))
				if edit != "":
					surface_name = edit
			var cell := TileSetBuilder.cell_for(surface_name)
			tile_map_layer.set_cell(Vector2i(tx, ty), cell["source_id"], cell["atlas_coord"], cell["alt_id"])

# Cheap deterministic pseudo-random pick per tile — no per-tile data is ever
# stored, it's re-derived identically from (world_seed, x, y) every time.
static func _tile_hash(x: int, y: int) -> int:
	var h := (x * 374761393 + y * 668265263 + BiomeMap.world_seed * 2246822519)
	h = (h ^ (h >> 13)) * 1274126177
	return absi(h ^ (h >> 16))
