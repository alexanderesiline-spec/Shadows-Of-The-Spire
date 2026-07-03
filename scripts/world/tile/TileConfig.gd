extends Node

# Shared tile/chunk constants. Everything else (chunk generation, tileset
# building, streaming radii) reads these instead of hardcoding numbers, so the
# whole world can be re-tuned (e.g. after first Android perf testing) by
# editing this one file.

# Logical on-screen tile size — small, for the Game-Boy look. Independent of
# the atlas's source resolution (see ATLAS_SOURCE_TILE_PX below); Godot scales
# the drawn quad, so a hi-res source atlas downsamples to this automatically
# as long as texture filtering is Nearest (required once real art lands).
const LOGICAL_TILE_SIZE := Vector2i(16, 16)

const CHUNK_SIZE_TILES := 32

# World size in chunks per axis (confirmed starting scale for first Android
# perf pass — purely a tunable constant, not an architectural limit).
const WORLD_CHUNKS_X := 64
const WORLD_CHUNKS_Y := 64

# How many chunks around the player stay loaded. Kept small deliberately —
# tune upward once real perf numbers exist.
const LOAD_RADIUS := 3
const UNLOAD_MARGIN := 1   # hysteresis: only release past LOAD_RADIUS + this

# Expected real-atlas spec (artist-provided asset, not present yet):
# a 1280x1280 image, 4x4 grid of 320x320 source tiles.
const ATLAS_SOURCE_TILE_PX := 320
const ATLAS_GRID := Vector2i(4, 4)
const ATLAS_PATH := "res://art/tileset_atlas.png"

const CONTINENT_MASK_PATH := "res://art/continent_mask.png"

const PLAYER_WALK_SHEET_PATH := "res://art/player_walk.png"
