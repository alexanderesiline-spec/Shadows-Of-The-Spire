extends Control

# The world map — built once from BiomeMap's cached grid (the generated
# biome data, not the raw continent PNG, per spec), one pixel per chunk,
# displayed nearest-filtered and scaled up. Player/POI markers plot by
# canonical world position, not local/rebased position, since this needs the
# true location in the world regardless of where the floating origin has
# everything rendered right now.

const TileConfig = preload("res://scripts/world/tile/TileConfig.gd")

const MAP_DISPLAY_SIZE := 480.0

var _texture_rect: TextureRect
var _built: bool = false
var player_ref: Node2D = null   # assigned externally once Player exists

func _ready() -> void:
	set_anchors_preset(Control.PRESET_CENTER)
	offset_left = -MAP_DISPLAY_SIZE / 2.0 - 10.0
	offset_top = -MAP_DISPLAY_SIZE / 2.0 - 30.0
	offset_right = MAP_DISPLAY_SIZE / 2.0 + 10.0
	offset_bottom = MAP_DISPLAY_SIZE / 2.0 + 30.0
	visible = false

	var bg := ColorRect.new()
	bg.color = Color(0.05, 0.05, 0.08, 0.92)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var title := Label.new()
	title.text = "The Siphoned Lands"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.set_anchors_preset(Control.PRESET_TOP_WIDE)
	title.offset_top = 4
	add_child(title)

	_texture_rect = TextureRect.new()
	_texture_rect.position = Vector2(10, 30)
	_texture_rect.size = Vector2(MAP_DISPLAY_SIZE, MAP_DISPLAY_SIZE)
	_texture_rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(_texture_rect)

func toggle() -> void:
	if not _built:
		_build_map_texture()
	visible = not visible
	if visible:
		queue_redraw()

func _build_map_texture() -> void:
	_built = true
	var w := TileConfig.WORLD_CHUNKS_X
	var h := TileConfig.WORLD_CHUNKS_Y
	var img := Image.create_empty(w, h, false, Image.FORMAT_RGBA8)
	for y in range(h):
		for x in range(w):
			var biome := BiomeMap.get_biome(Vector2i(x, y))
			img.set_pixel(x, y, BiomeMap.display_color(biome))
	_texture_rect.texture = ImageTexture.create_from_image(img)

func _process(_delta: float) -> void:
	if visible:
		queue_redraw()

func _draw() -> void:
	if not visible:
		return
	var world_chunks := Vector2(TileConfig.WORLD_CHUNKS_X, TileConfig.WORLD_CHUNKS_Y)
	var map_origin := _texture_rect.position

	for poi in WorldSimulation.pois:
		if is_instance_valid(poi) and "world_pos" in poi:
			_draw_marker(_world_to_map(poi.world_pos, world_chunks, map_origin), Color(1.0, 0.85, 0.3), 5.0)

	if player_ref != null and is_instance_valid(player_ref):
		_draw_marker(_world_to_map(player_ref.world_tile_pos, world_chunks, map_origin), Color(0.3, 0.7, 1.0), 4.0)

func _world_to_map(world_tile: Vector2, world_chunks: Vector2, map_origin: Vector2) -> Vector2:
	var chunk_pos := world_tile / float(TileConfig.CHUNK_SIZE_TILES)
	var fraction := chunk_pos / world_chunks
	return map_origin + fraction * MAP_DISPLAY_SIZE

func _draw_marker(pos: Vector2, color: Color, radius: float) -> void:
	draw_circle(pos, radius + 1.5, Color.BLACK)
	draw_circle(pos, radius, color)
