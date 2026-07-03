extends Node

# Builds the shared TileSet resource once at boot, shared by every pooled
# ChunkNode's TileMapLayer. Two modes, same downstream interface:
#
#   - Real atlas present (TileConfig.ATLAS_PATH): TileSet.tile_size and the
#     atlas source's texture_region_size both stay at the atlas's native
#     resolution (320x320) — cell-index math never has to fight Godot's
#     region/tile-size scaling semantics. The "Game Boy" small logical look
#     is then achieved purely by scaling the ChunkNode itself down to
#     LOGICAL_TILE_SIZE/ATLAS_SOURCE_TILE_PX — a plain, well-understood
#     Node2D scale, not a TileSet-internal behavior we'd have to guess at
#     without a live editor to verify against.
#   - No atlas (true today): a placeholder atlas texture is synthesized
#     directly at LOGICAL_TILE_SIZE resolution, so tile_size == region_size
#     == LOGICAL_TILE_SIZE and no extra scale is needed at all.
#
# Callers (ChunkNode) read `visual_scale` and apply it to themselves.

const TileConfig = preload("res://scripts/world/tile/TileConfig.gd")
const TileSurfaceTable = preload("res://scripts/world/tile/TileSurfaceTable.gd")

const SOURCE_ID := 0

static func build() -> Dictionary:
	if ResourceLoader.exists(TileConfig.ATLAS_PATH):
		return _build_from_real_atlas()
	return _build_placeholder()

static func _build_from_real_atlas() -> Dictionary:
	var texture: Texture2D = load(TileConfig.ATLAS_PATH)
	texture.set_meta("_shadows_filter_hint", "nearest")  # documents the required import setting

	var region := Vector2i(TileConfig.ATLAS_SOURCE_TILE_PX, TileConfig.ATLAS_SOURCE_TILE_PX)
	var tile_set := TileSet.new()
	tile_set.tile_size = region

	var source := TileSetAtlasSource.new()
	source.texture = texture
	source.texture_region_size = region

	_populate_source(source)
	tile_set.add_source(source, SOURCE_ID)

	var scale_factor := Vector2(
		float(TileConfig.LOGICAL_TILE_SIZE.x) / float(TileConfig.ATLAS_SOURCE_TILE_PX),
		float(TileConfig.LOGICAL_TILE_SIZE.y) / float(TileConfig.ATLAS_SOURCE_TILE_PX)
	)
	return {"tile_set": tile_set, "visual_scale": scale_factor}

static func _build_placeholder() -> Dictionary:
	var cell := TileConfig.LOGICAL_TILE_SIZE
	var grid := TileConfig.ATLAS_GRID
	var image := Image.create_empty(cell.x * grid.x, cell.y * grid.y, false, Image.FORMAT_RGBA8)

	for surface_name in TileSurfaceTable.BASE_SURFACES:
		var entry: Dictionary = TileSurfaceTable.BASE_SURFACES[surface_name]
		var coord: Vector2i = entry["atlas_coord"]
		var color: Color = entry["fallback_color"]
		image.fill_rect(Rect2i(coord.x * cell.x, coord.y * cell.y, cell.x, cell.y), color)

	var texture := ImageTexture.create_from_image(image)

	var tile_set := TileSet.new()
	tile_set.tile_size = cell

	var source := TileSetAtlasSource.new()
	source.texture = texture
	source.texture_region_size = cell
	source.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST

	_populate_source(source)
	tile_set.add_source(source, SOURCE_ID)

	return {"tile_set": tile_set, "visual_scale": Vector2.ONE}

# Registers a base tile + its tinted alternatives at each atlas coordinate.
static func _populate_source(source: TileSetAtlasSource) -> void:
	var created_coords := {}
	for surface_name in TileSurfaceTable.BASE_SURFACES:
		var coord: Vector2i = TileSurfaceTable.BASE_SURFACES[surface_name]["atlas_coord"]
		if not created_coords.has(coord):
			source.create_tile(coord)
			created_coords[coord] = true

	for surface_name in TileSurfaceTable.VARIANT_SURFACES:
		var variant: Dictionary = TileSurfaceTable.VARIANT_SURFACES[surface_name]
		var base_coord: Vector2i = TileSurfaceTable.BASE_SURFACES[variant["base"]]["atlas_coord"]
		var alt_id: int = variant["alt_id"]
		source.create_alternative_tile(base_coord, alt_id)
		var tile_data := source.get_tile_data(base_coord, alt_id)
		tile_data.modulate = variant["tint"]

# Convenience for painting code: returns {source_id, atlas_coord, alt_id} for
# a surface name, ready to hand to TileMapLayer.set_cell(...).
static func cell_for(surface_name: String) -> Dictionary:
	return {
		"source_id": SOURCE_ID,
		"atlas_coord": TileSurfaceTable.atlas_coord_for(surface_name),
		"alt_id": TileSurfaceTable.alt_id_for(surface_name),
	}
