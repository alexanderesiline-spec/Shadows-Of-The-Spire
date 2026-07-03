extends Node

# Built once at boot, before ChunkManager starts streaming. Produces one
# cached grid (one entry per chunk) that everything downstream reads through
# get_biome() — nobody else ever samples the source PNG or noise directly, so
# swapping the real continent art in later only touches _build_from_png().

const TileConfigScript = preload("res://scripts/world/tile/TileConfig.gd")

enum Biome { OCEAN, HEARTLAND, OLD_FOREST, WETLANDS, FOOTHILLS, MOUNTAINS, DELTA }

const BIOME_NAMES := {
	Biome.OCEAN: "Ocean", Biome.HEARTLAND: "Heartland", Biome.OLD_FOREST: "Old Forest",
	Biome.WETLANDS: "Wetlands", Biome.FOOTHILLS: "Foothills", Biome.MOUNTAINS: "Mountains",
	Biome.DELTA: "Delta",
}

# For the overview map and any other "just show me a biome color" need.
const BIOME_DISPLAY_COLORS := {
	Biome.OCEAN:      Color("2f6b8f"),
	Biome.HEARTLAND:  Color("7fae4a"),
	Biome.OLD_FOREST:  Color("2f5c2a"),
	Biome.WETLANDS:   Color("4a5c3f"),
	Biome.FOOTHILLS:  Color("8a8378"),
	Biome.MOUNTAINS:  Color("7d7d7d"),
	Biome.DELTA:      Color("6fa0a8"),
}

# Nearest-color match table for reading a hand-painted continent PNG — the
# artist's palette won't hit these hex values exactly, so classification is
# by closest distance, not equality.
const PNG_PALETTE := {
	Biome.OCEAN:      Color("1d3f57"),
	Biome.HEARTLAND:  Color("7fae4a"),
	Biome.OLD_FOREST:  Color("2f5c2a"),
	Biome.WETLANDS:   Color("4a5c3f"),
	Biome.FOOTHILLS:  Color("8a8378"),
	Biome.MOUNTAINS:  Color("7d7d7d"),
	Biome.DELTA:      Color("6fa0a8"),
}

var world_seed: int = 0
var _grid: PackedByteArray = PackedByteArray()
var _width: int = 0
var _height: int = 0

func _ready() -> void:
	_width = TileConfigScript.WORLD_CHUNKS_X
	_height = TileConfigScript.WORLD_CHUNKS_Y
	world_seed = randi()
	rebuild()

# Regenerates the cached grid. Called at boot, and callable again if
# world_seed is deliberately changed (e.g. loading a save with a stored seed).
func rebuild() -> void:
	if ResourceLoader.exists(TileConfigScript.CONTINENT_MASK_PATH):
		_build_from_png()
	else:
		_build_from_noise()

func get_biome(chunk_coord: Vector2i) -> Biome:
	var x := posmod(chunk_coord.x, _width)
	var y := posmod(chunk_coord.y, _height)
	if _grid.is_empty():
		return Biome.HEARTLAND
	return _grid[y * _width + x] as Biome

func biome_name(biome: Biome) -> String:
	return BIOME_NAMES.get(biome, "Unknown")

func display_color(biome: Biome) -> Color:
	return BIOME_DISPLAY_COLORS.get(biome, Color.MAGENTA)

# Finds the nearest chunk of a given biome to a preferred coordinate — used by
# the town Point-of-Interest to place itself in Heartland without hardcoding
# blind, and by Demon's isolated spawn to find/force an ocean-locked chunk.
func find_nearest_biome_chunk(preferred: Vector2i, biome: Biome, search_radius: int = 24) -> Vector2i:
	if get_biome(preferred) == biome:
		return preferred
	for r in range(1, search_radius + 1):
		for dx in range(-r, r + 1):
			for dy in range(-r, r + 1):
				if maxi(absi(dx), absi(dy)) != r:
					continue
				var c := Vector2i(preferred.x + dx, preferred.y + dy)
				if get_biome(c) == biome:
					return c
	return preferred

func _build_from_png() -> void:
	var img: Image = Image.load_from_file(TileConfigScript.CONTINENT_MASK_PATH)
	img.convert(Image.FORMAT_RGB8)
	_grid = PackedByteArray()
	_grid.resize(_width * _height)
	for y in range(_height):
		for x in range(_width):
			var sample_x: int = int(float(x) / _width * img.get_width())
			var sample_y: int = int(float(y) / _height * img.get_height())
			var pixel := img.get_pixel(sample_x, sample_y)
			_grid[y * _width + x] = _nearest_biome(pixel)

func _nearest_biome(pixel: Color) -> int:
	var best := Biome.HEARTLAND
	var best_dist := INF
	for biome in PNG_PALETTE:
		var d := _color_distance(pixel, PNG_PALETTE[biome])
		if d < best_dist:
			best_dist = d
			best = biome
	return best

func _color_distance(a: Color, b: Color) -> float:
	return (a.r - b.r) ** 2 + (a.g - b.g) ** 2 + (a.b - b.b) ** 2

# No art yet — usable today. Two noise fields (elevation/moisture) classified
# through a simple Whittaker-style threshold table into the 6 biomes + ocean.
# Ocean is a normal low-elevation band, not a hard map edge.
func _build_from_noise() -> void:
	var elevation := FastNoiseLite.new()
	elevation.seed = world_seed
	elevation.frequency = 0.03
	elevation.fractal_octaves = 4

	var moisture := FastNoiseLite.new()
	moisture.seed = world_seed + 1000
	moisture.frequency = 0.05
	moisture.fractal_octaves = 3

	_grid = PackedByteArray()
	_grid.resize(_width * _height)
	for y in range(_height):
		for x in range(_width):
			var e := elevation.get_noise_2d(x, y)
			var m := (moisture.get_noise_2d(x, y) + 1.0) * 0.5   # 0..1
			_grid[y * _width + x] = _classify(e, m)

func _classify(elevation: float, moisture: float) -> int:
	const SEA_LEVEL := -0.1
	if elevation < SEA_LEVEL:
		return Biome.OCEAN
	elif elevation < 0.05:
		if moisture > 0.5:
			return Biome.DELTA
		elif moisture > 0.15:
			return Biome.WETLANDS
		else:
			return Biome.HEARTLAND
	elif elevation < 0.35:
		return Biome.OLD_FOREST if moisture > 0.25 else Biome.HEARTLAND
	elif elevation < 0.65:
		return Biome.FOOTHILLS
	else:
		return Biome.MOUNTAINS
